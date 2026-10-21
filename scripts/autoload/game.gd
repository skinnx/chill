extends Node
## Game (autoload, last): glue between the pure [WorldSim] and the node world
## (docs/ARCHITECTURE.md §3, §5).
##
##  * boot(): load the save (or start a new install), offline catch-up, recap, greeter plan.
##  * Every frame: advance the sim to the live world clock (monotonic ticks since the last
##    rebase), drain sim events and re-emit them as [signal sim_event].
##  * Player actions: the UI calls the methods below; they advance to "now", act, dispatch,
##    and request a debounced save.
##  * Lifecycle: PAUSED -> suspend (greeter leaves, save); RESUMED -> catch-up + recap;
##    FOCUS_OUT / close -> save. Android Back -> top handler, else [signal leave_requested].
## Views never mutate state directly; they read [member sim] and listen to signals.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## After boot and after every resume. recap: Array of {key, species} lines (may be empty).
signal world_ready(recap: Array)
## Every sim event in order (see WorldSim.EV_*). Catch-up events carry "catch_up": true.
signal sim_event(event: Dictionary)
signal wallet_changed(dew: int)
signal basket_changed(count: int, dew: int)
## Back pressed with nothing open: the UI shows "Leave the hollow for now?" (GDD §8.1).
signal leave_requested
signal suspended
signal resumed

const ARG_SEED := "--seed="
const QUIT_SETTLE_FRAMES := 2
## Wall-clock time the audio mix thread gets to free stopped playbacks before quitting. Frames are
## not enough on their own: under --fixed-fps or Movie Maker they can run far faster than the
## mixer, which then still holds the pad/bed playbacks at exit.
const QUIT_SETTLE_MS := 150
const ARG_WORLD_SPEED := "--world-speed="
## decor.json fx flag of the wind chime: each owned one adds a shell note (AUDIO_BIBLE §5, S21).
const FX_CHIME_NOTE := "adds_chime_note"

var content: GameContent
var sim: WorldSim
var is_ready: bool = false
var is_suspended: bool = false
## Result of the last catch-up ({raw_s, delta_s, skipped_s, rolled_back, events}).
var last_catch_up: Dictionary = {}
## QA: world seconds per real second (default 1; e.g. 60 to watch a day pass in 24 min).
var world_speed: float = 1.0

var _world_base_t: float = 0.0
var _ticks_base_s: float = 0.0
var _suspended_at_unix: float = 0.0
var _last_dew: int = -1
var _last_basket: int = -1
var _back_handlers: Array[Callable] = []
var _greeter_wanted: bool = false
var _greeter_left_s: float = -1.0
var _session_rng := RandomNumberGenerator.new()
var _seed_override: int = 0
var _has_seed_override: bool = false
## Species napping right now, reported by the creature layer (AUDIO_BIBLE §8.7 snores).
var _sleepers: PackedStringArray = PackedStringArray()


func _ready() -> void:
	process_priority = -50  # after Clock, before views
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false  # desktop close: save and stop audio first (quit_cleanly)
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(ARG_SEED):
			_seed_override = a.trim_prefix(ARG_SEED).to_int()
			_has_seed_override = true
		elif a.begins_with(ARG_WORLD_SPEED):
			world_speed = maxf(0.0, a.trim_prefix(ARG_WORLD_SPEED).to_float())


## Loads or creates the world. Called once by the boot scene behind the splash.
func boot() -> void:
	content = ContentRegistry.content
	var now := Clock.now_unix()
	var tz := Clock.tz_offset_s()
	var res := SaveService.load_world()
	var catch := {}
	var resumed_save := false
	if res["ok"]:
		var world: Dictionary = res["world"]
		sim = WorldSim.new(content, WorldState.from_dict(world))
		catch = sim.catch_up(now, tz, float(res["saved_at_unix"]))
		resumed_save = true
	else:
		if SaveService.has_save():
			SaveService.quarantine()
		sim = WorldSim.new_game(content, _new_install_seed(), now, tz)
	_session_rng.seed = hash([sim.state.install_seed, now])
	TimeOfDay.set_install_seed(sim.state.install_seed)
	AudioDirector.set_install_seed(sim.state.install_seed)
	SaveService.register_provider(_save_payload)
	_rebase()
	last_catch_up = catch
	var events := sim.drain_events()
	var recap: Array[Dictionary] = []
	if resumed_save and Recap.should_show(content, float(catch.get("raw_s", 0.0)), events):
		recap = Recap.build(sim, events, sim.state.t - float(catch.get("delta_s", 0.0)), sim.state.t)
	_plan_greeter(events, resumed_save)
	_dispatch(events, true)
	_push_audio_state()
	is_ready = true
	SaveService.save_now(&"boot")
	world_ready.emit(recap)


func _process(delta: float) -> void:
	if not is_ready or is_suspended:
		return
	sim.advance(world_now())
	if sim.has_events():
		_dispatch(sim.drain_events(), false)
	if _greeter_left_s >= 0.0:
		_greeter_left_s -= delta
		if _greeter_left_s < 0.0:
			sim.add_greeter(sim.state.t)
			_dispatch(sim.drain_events(), false)


func _notification(what: int) -> void:
	if not is_ready:
		if what == NOTIFICATION_WM_CLOSE_REQUEST:
			get_tree().quit()  # closed during boot: nothing to save yet
		return
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_suspend()
		NOTIFICATION_APPLICATION_RESUMED:
			_resume()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if not is_suspended:
				SaveService.save_now(&"focus_out")
		NOTIFICATION_WM_CLOSE_REQUEST:
			_suspend()
			quit_cleanly()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			handle_back()


## Live world clock: world seconds at the last rebase + monotonic seconds since.
func world_now() -> float:
	return _world_base_t + (Clock.ticks_s() - _ticks_base_s) * world_speed


# ================================================================= player actions (UI API)

func tap_seed() -> int:
	_sync()
	var i := sim.tap_tutorial_seed()
	_after_action()
	return i


## First copy of a flower: pass the bed the player chose (beds with room glow, GDD §2.4).
func plant(flower_id: StringName, bed_id: StringName = &"") -> int:
	_sync()
	var i := sim.buy_flower(flower_id, bed_id)
	_after_action()
	return i


func place(decor_id: StringName) -> bool:
	_sync()
	var ok := sim.buy_decor(decor_id)
	_after_action()
	return ok


func collect_all() -> int:
	_sync()
	var got := sim.collect()
	_after_action()
	return got


func float_boat() -> bool:
	_sync()
	var ok := sim.float_boat()
	_after_action()
	return ok


func pet(species: StringName) -> bool:
	_sync()
	var ok := sim.pet(species, Clock.now_unix())
	_after_action()
	return ok


func rename(species: StringName, new_name: String) -> String:
	var clean := sim.set_custom_name(species, new_name)
	SaveService.request_save()
	return clean


func read_postcard(id: String) -> void:
	sim.mark_postcard_read(id)
	SaveService.request_save()


## Custom name, else the default name in the current language.
func display_name(species: StringName) -> String:
	var custom: String = sim.state.names.get(String(species), "")
	if custom != "":
		return custom
	var s: Dictionary = content.species_by_id.get(species, {})
	return tr(String(s.get("default_name_key", ""))) if not s.is_empty() else String(species)


## The UI calls this once the hollow is visible (after the boot cover / recap): the greeter
## strolls in greeter_delay_min_s..max_s later (GDD §5.6).
func notify_world_visible() -> void:
	if _greeter_wanted:
		_greeter_wanted = false
		var eco := content.economy
		_greeter_left_s = _session_rng.randf_range(float(eco["greeter_delay_min_s"]), float(eco["greeter_delay_max_s"]))


# ================================================================= back button (I3)

## The top-most open card/sheet registers a handler that closes it (and removes itself).
func push_back_handler(handler: Callable) -> void:
	_back_handlers.erase(handler)
	_back_handlers.append(handler)


func remove_back_handler(handler: Callable) -> void:
	_back_handlers.erase(handler)


func handle_back() -> void:
	while not _back_handlers.is_empty():
		var h: Callable = _back_handlers.back()
		if h.is_valid():
			h.call()
			return
		_back_handlers.pop_back()
	leave_requested.emit()


## "Leave for now": save, then send the app to the background (Android) or quit.
func leave_now() -> void:
	_suspend()
	if not Platform.move_task_to_back():
		await quit_cleanly()


## Stops audio, lets the AudioServer release its playbacks (at least [constant QUIT_SETTLE_FRAMES]
## frames and [constant QUIT_SETTLE_MS] ms), then quits (no leaked instances at exit).
func quit_cleanly(exit_code: int = 0) -> void:
	AudioDirector.stop_all()
	var since := Time.get_ticks_msec()
	var frames := 0
	while frames < QUIT_SETTLE_FRAMES or Time.get_ticks_msec() - since < QUIT_SETTLE_MS:
		await get_tree().process_frame
		frames += 1
	get_tree().quit(exit_code)


# ================================================================= internals

func _sync() -> void:
	if is_ready and not is_suspended:
		sim.advance(world_now())


func _after_action() -> void:
	if sim.has_events():
		_dispatch(sim.drain_events(), false)
	SaveService.request_save()


func _dispatch(events: Array[Dictionary], catch_up: bool) -> void:
	for ev: Dictionary in events:
		if catch_up:
			ev["catch_up"] = true
		sim_event.emit(ev)
	if not events.is_empty():
		_push_audio_state()
	var dew := sim.state.dew
	if dew != _last_dew:
		_last_dew = dew
		wallet_changed.emit(dew)
	var n := sim.state.basket.size()
	if n != _last_basket:
		_last_basket = n
		basket_changed.emit(n, sim.basket_dew())


## The creature layer reports who is napping (view-side state, ARCHITECTURE §5.4): sleepers
## snore at night and do not coo.
func report_sleepers(species: PackedStringArray) -> void:
	if species == _sleepers:
		return
	_sleepers = species
	if is_ready:
		_push_audio_state()


## AudioDirector.set_world_state (AUDIO_BIBLE §8.7, §11): owned chime shells, the voice_step of
## every awake mossling in the hollow and the number of nappers (from report_sleepers).
func _push_audio_state() -> void:
	var shells := 0
	for id: StringName in content.decor_by_id:
		var fx: Array = (content.decor_by_id[id] as Dictionary).get("fx", [])
		if fx.has(FX_CHIME_NOTE):
			shells += sim.owned_count(id)
	var awake := PackedInt32Array()
	var sleeping := 0
	for p: Dictionary in sim.state.present:
		if _sleepers.has(String(p["species"])):
			sleeping += 1
			continue
		var sp: Dictionary = content.species_by_id.get(StringName(p["species"]), {})
		awake.append(int(sp.get("voice_step", 0)))
	AudioDirector.set_world_state(shells, awake, sleeping)


func _rebase() -> void:
	_world_base_t = sim.state.t
	_ticks_base_s = Clock.ticks_s()


func _suspend() -> void:
	if is_suspended or sim == null:
		return
	_sync()
	sim.dismiss_greeter()
	_greeter_left_s = -1.0
	if sim.has_events():
		_dispatch(sim.drain_events(), false)
	_suspended_at_unix = Clock.now_unix()
	sim.set_anchor(sim.state.t, _suspended_at_unix, Clock.tz_offset_s())
	is_suspended = true
	SaveService.save_now(&"paused")
	suspended.emit()


func _resume() -> void:
	if not is_suspended:
		return
	var catch := sim.catch_up(Clock.now_unix(), Clock.tz_offset_s(), _suspended_at_unix)
	last_catch_up = catch
	_rebase()
	var events := sim.drain_events()
	var recap: Array[Dictionary] = []
	if Recap.should_show(content, float(catch["raw_s"]), events):
		recap = Recap.build(sim, events, sim.state.t - float(catch["delta_s"]), sim.state.t)
	_plan_greeter(events, true)
	_dispatch(events, true)
	is_suspended = false
	resumed.emit()
	world_ready.emit(recap)


## Greeter rule (GDD §5.6): nothing happened since the last close, or nobody is in the hollow.
func _plan_greeter(events: Array[Dictionary], returning: bool) -> void:
	_greeter_wanted = returning and (events.is_empty() or sim.real_visitor_count() == 0) and sim.met_count() > 0


func _save_payload() -> Dictionary:
	_sync()
	var now := Clock.now_unix()
	sim.set_anchor(sim.state.t, now, Clock.tz_offset_s())
	return {"world": sim.state.to_dict(), "saved_at_unix": now}


func _new_install_seed() -> int:
	if _has_seed_override:
		return _seed_override
	var bytes := Crypto.new().generate_random_bytes(8)
	return bytes.decode_s64(0)
