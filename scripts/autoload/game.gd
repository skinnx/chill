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

# --- Retention v1 (GDD §13; docs/ARCHITECTURE.md §3.1). Fired from the sim events in order, after
# sim_event; catch-up (offline) events carry offline = true. Payloads are the event dictionaries.
## A friend reached a new heart level (live: celebrate + toast; offline: recap line, toasts later).
signal heart_up(species: StringName, hearts: int, offline: bool)
## A mystery opened for an unmet friend or a cousin (Album › Clues gains a card).
signal mystery_opened(mystery: StringName, kind: StringName, target: StringName)
## A sign took a visible slot at its anchor (fade in 600 ms; at most 3 at once).
signal sign_appeared(sign: Dictionary)
## A visible sign was tapped: clue_lift + S23, toast; a note opens the riddle reader.
signal clue_found(clue: Dictionary)
## A nest was built (stage 0) or grew a stage.
signal nest_grew(species: StringName, stage: int, offline: bool)
## A staged scene is waiting in the world (new or re-shown after a close).
signal scene_ready(scene: Dictionary)
## The pending scene was archived to Album › Memories (tap or linger_s of foreground time).
signal scene_archived(memory: Dictionary)
signal cousin_met(variant: StringName, species: StringName)
## A cousin came along with its base friend (first visit or every 3rd arrival).
signal cousin_arrived(variant: StringName, species: StringName, first: bool)
signal keepsake_added(species: StringName)

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
		var t_bg := sim.state.t  # the world was last running when it was saved
		catch = sim.catch_up(now, tz, float(res["saved_at_unix"]))
		sim.retention.on_return(sim, t_bg, sim.state.t)  # GDD §13.4: an away scene may be staged
		resumed_save = true
	else:
		if SaveService.has_save():
			SaveService.quarantine()
		sim = WorldSim.new_game(content, _new_install_seed(), now, tz)
	sim.state.open_count += 1  # the wave-on-open hash key (GDD §13.2.2)
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
	if not sim.state.pending_scene.is_empty():
		sim.retention.foreground_tick(sim, delta)  # archived after linger_s of foreground time
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


# ================================================================= Retention v1 API (GDD §13.9)

## Taps a visible sign ([code]sign["key"][/code] from [method visible_signs] / [signal sign_appeared]).
## Returns false if it is not visible (nothing changes).
func tap_sign(sign_key: String) -> bool:
	_sync()
	var ok := sim.retention.tap_sign(sim, sign_key)
	_after_action()
	return ok


## Taps the staged scene (a participant or prop): it is archived to Memories. False if none.
func tap_scene() -> bool:
	_sync()
	var ok := sim.retention.tap_scene(sim)
	_after_action()
	return ok


## Foreground seconds while a scene is shown (Game calls this every frame; exposed for tests/QA).
func scene_foreground_tick(dt: float) -> void:
	sim.retention.foreground_tick(sim, dt)
	if sim.has_events():
		_dispatch(sim.drain_events(), false)


## Records the background moment for the 2 h scene rule (Game calls it on suspend).
func on_background(world_t: float) -> void:
	sim.state.last_bg_t = world_t


## {scene, cast: Array[String], phase, weather, world_t, shown_s} or {} if nothing is staged.
func pending_scene() -> Dictionary:
	return sim.state.pending_scene.duplicate(true)


## Signs on screen now (<= 3): {key, mystery, index, sign, species, variant, anchor, appear_t,
## footprint, dropped, tint}.
func visible_signs() -> Array[Dictionary]:
	return sim.retention.visible_signs(sim)


## Album › Clues cards in display order (RetentionRules.clue_cards).
func clue_cards() -> Array[Dictionary]:
	return sim.retention.clue_cards(sim)


## The clue card of one mystery: a species id (unmet friend) or a variant id (cousin).
func clues_for(mystery: StringName) -> Dictionary:
	return sim.retention.clue_card(sim, String(mystery))


func heart_level(species: StringName) -> int:
	return sim.hearts_of(species)


## Friend card unlock lines: [{heart, reached, album_key, toast_key, unlocks}] (no points shown).
func unlocks(species: StringName) -> Array[Dictionary]:
	return sim.retention.unlock_list(sim, species)


## Heart-ups not yet celebrated ([{species, hearts, seen}]); the UI toasts them after the recap.
func unseen_hearts() -> Array[Dictionary]:
	return sim.retention.unseen_hearts(sim)


func mark_hearts_seen(species: StringName) -> void:
	sim.retention.mark_hearts_seen(sim, species)
	SaveService.request_save()


## {species, style, stage, stage_id, built_t, style_key, stage_key, x, y} or {} (no nest).
func nest_state(species: StringName) -> Dictionary:
	return sim.retention.nest_view(sim, species)


## Every nest, keyed by species.
func nests() -> Dictionary:
	var out := {}
	for sp: String in sim.state.nests:
		out[StringName(sp)] = sim.retention.nest_view(sim, StringName(sp))
	return out


## Album › Memories (moments), oldest first: {scene, cast, phase, weather, world_t, unix}.
func memories() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: Dictionary in sim.state.memories:
		out.append(m.duplicate(true))
	return out


## Album › Keepsakes: {portraits, signature_gifts, cousins}.
func keepsakes() -> Dictionary:
	return sim.retention.keepsake_view(sim)


## The cousin row of a friend card ({} if the species has no cousin).
func cousin_of(species: StringName) -> Dictionary:
	return sim.retention.cousin_view(sim, species)


## variant id -> unix time met.
func variants_met() -> Dictionary:
	return sim.state.variants_met.duplicate()


## {friend, met, active}: the best-buddy pair is active once both are met and either is at ♥4.
func best_buddy(species: StringName) -> Dictionary:
	return sim.retention.buddy_view(sim, species)


## Who waves when the hollow opens (after the recap closes): [{species, delay_s, pose}].
func wave_plan() -> Array[Dictionary]:
	return sim.retention.wave_plan(sim, sim.state.open_count)


## Renaming stays available from the first meeting (Director ruling on GDD §13.11 Q1).
func can_rename(species: StringName) -> bool:
	return sim.is_met(species)


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
		_emit_retention(ev, catch_up)
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


## Typed Retention v1 signals for P2 views (the same events also went out as sim_event).
func _emit_retention(ev: Dictionary, offline: bool) -> void:
	match StringName(ev["type"]):
		WorldSim.EV_HEARTS:
			heart_up.emit(StringName(ev["species"]), int(ev["hearts"]), offline)
		WorldSim.EV_MYSTERY_OPENED:
			mystery_opened.emit(StringName(ev["mystery"]), StringName(ev["kind"]), StringName(ev["target"]))
		WorldSim.EV_SIGN_VISIBLE:
			sign_appeared.emit(ev)
		WorldSim.EV_CLUE:
			clue_found.emit(ev)
		WorldSim.EV_NEST_STAGE:
			nest_grew.emit(StringName(ev["species"]), int(ev["stage"]), offline)
		WorldSim.EV_SCENE_STAGED:
			scene_ready.emit(ev)
		WorldSim.EV_SCENE_ARCHIVED:
			scene_archived.emit(ev)
		WorldSim.EV_COUSIN_MET:
			cousin_met.emit(StringName(ev["variant"]), StringName(ev["species"]))
		WorldSim.EV_COUSIN_ARRIVED:
			cousin_arrived.emit(StringName(ev["variant"]), StringName(ev["species"]), bool(ev["first"]))
		WorldSim.EV_KEEPSAKE:
			keepsake_added.emit(StringName(ev["species"]))


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
	on_background(sim.state.t)
	sim.set_anchor(sim.state.t, _suspended_at_unix, Clock.tz_offset_s())
	is_suspended = true
	SaveService.save_now(&"paused")
	suspended.emit()


func _resume() -> void:
	if not is_suspended:
		return
	var catch := sim.catch_up(Clock.now_unix(), Clock.tz_offset_s(), _suspended_at_unix)
	sim.retention.on_return(sim, sim.state.last_bg_t, sim.state.t)  # GDD §13.4
	sim.state.open_count += 1
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
