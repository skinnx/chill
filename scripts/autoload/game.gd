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

# --- Active Play v1 (GDD §14.11; docs/ARCHITECTURE.md §3.1). Fired from the sim events in order,
# after sim_event (same dictionaries). Active F1 Wishes:
## A friend floats a new wish (visible = its bubble shows now; else it is held for later).
signal wish_opened(species: StringName, wish: StringName, visible: bool)
## A held wish took a visible slot (its friend came back, or a slot freed).
signal wish_shown(species: StringName, wish: StringName)
## Its friend left: the wish is kept for a later visit (no toast).
signal wish_held(species: StringName, wish: StringName)
## Granted: delight pose, stamp (first_stamp), gift petal (gift_flower or &""), affection 0/1.
## on_arrival: a decor_near piece was set while the friend was away. offline: it happened during
## catch-up, so the welcome-back card is already telling the player - the view must stay quiet
## (ACTIVE_WISHES §7.5: the toast OR the recap line, never both), exactly as [signal heart_up] does.
signal wish_granted(species: StringName, wish: StringName, affection: int, gift_flower: StringName,
		first_stamp: bool, on_arrival: bool, offline: bool)
# Active F2 Tea & Treats:
## The tea nook woke (GDD §14.11 calls this signal tea_unlocked; renamed because the query
## [method tea_unlocked] holds that name): fade it in, toast TEA_NOOK_AWAKE once.
signal tea_nook_awake
signal petals_harvested(bed_id: StringName, counts: Dictionary)
signal recipe_found(recipe: StringName)
## A cup was sipped: reaction content/liked/loved, petals tucked back into the pantry.
signal tea_offered(species: StringName, recipe: StringName, reaction: StringName, petals: int)
signal teaware_changed(slot: StringName, id: StringName)
# Active F3 Free décor placement:
## After the settle only (never mid-drag): move, glide, take out, turn, a purchase.
signal decor_placed(set_id: StringName, piece_id: String, pos_norm: Vector2, rot_deg: int)
signal decor_stored(set_id: StringName, piece_id: String)
signal decor_edit_entered
signal decor_edit_exited

const ARG_SEED := "--seed="
const QUIT_SETTLE_FRAMES := 2
## Wall-clock time the audio mix thread gets to free stopped playbacks before quitting. Frames are
## not enough on their own: under --fixed-fps or Movie Maker they can run far faster than the
## mixer, which then still holds the pad/bed playbacks at exit.
const QUIT_SETTLE_MS := 150
const ARG_WORLD_SPEED := "--world-speed="
## decor.json fx flag of the wind chime: each owned one adds a shell note (AUDIO_BIBLE §5, S21).
const FX_CHIME_NOTE := "adds_chime_note"
## One-time tips (save field tips_seen, schema 4): the décor press-and-hold toast after the first
## movable décor purchase, and the Album's "keeps the wish for another visit" note.
const TIP_DECOR_LONG_PRESS := &"decor_long_press"
const TIP_WISH_KEPT := &"wish_kept"

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
## Reasons the wish clock is paused besides sheets, cards and edit mode (QA, FE requests).
var _wish_pause: Dictionary = {}
## Pieces turned by the player during this edit session (they keep their turn; beautify).
var _edit_turned: Dictionary = {}


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
		var from_t := sim.state.t - float(catch.get("delta_s", 0.0))
		recap = Recap.build(sim, events, from_t, sim.state.t,
				CreatureBrain.nap_during(content, sim, events, from_t, sim.state.t))
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
	wish_foreground_tick(delta)  # Active F1: one spawn check per 60 s of unblocked foreground time
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
			InputPrecision.release_all()
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


# ================================================================= Active Play v1 API (GDD §14.11)
# Every call returns false / -1 / {} / &"" and changes nothing on failure. World views call
# world_action() from world_release(act = true) only, so a pan or a cancelled press grants nothing.

## Active Play feature flags: &"wishes", &"tea", &"free_decor" (a build constant, all on in v1).
func feature_on(flag: StringName) -> bool:
	return sim != null and sim.active.feature_on(flag)


## An action the player already has, for wish fulfilment (ACTIVE_WISHES §5): &"tap_creature"
## {species}, &"ring_chime", &"bed_tap" {bed}, &"decor_tap" {set, piece}, &"stream_tap" {pos}.
## (Petting and the leaf boat report themselves through pet() / float_boat().) Returns the
## species whose wish it granted.
func world_action(kind: StringName, args: Dictionary = {}) -> Array[StringName]:
	_sync()
	var granted := sim.active.wishes.on_action(sim, kind, args, sim.state.t)
	_after_action()
	return granted


## Foreground seconds for the wish clock. Game calls it every frame; it does nothing while a sheet
## or card is open (WorldPan.blocked), in edit mode, or while paused by [method pause_wishes].
func wish_foreground_tick(dt: float) -> void:
	if sim == null or not is_ready or is_suspended:
		return
	sim.active.wishes.foreground_tick(sim, dt, _wishes_blocked())
	if sim.has_events():
		_dispatch(sim.drain_events(), false)


## Pauses (or resumes) wish spawn checks for [param reason] (e.g. &"scene" while a scene is up).
func pause_wishes(reason: StringName, on: bool) -> void:
	if on:
		_wish_pause[reason] = true
	else:
		_wish_pause.erase(reason)


## The creature layer reports friends that are napping, being petted, entering or leaving: they
## do not start a new wish (their existing wish waits).
func report_wish_busy(species: PackedStringArray) -> void:
	if sim != null:
		sim.active.wishes.busy = species


func _wishes_blocked() -> bool:
	if sim.active.edit_mode or not _wish_pause.is_empty() or not _back_handlers.is_empty():
		return true
	var pan := WorldPan.current
	return pan != null and is_instance_valid(pan) and pan.is_blocked()


## Pending wishes, oldest first: [{species, wish, state, icon, title_key, hint_key, granted_pose,
## kind, arg, present, placed, taps, taps_needed, opened_t}].
func wishes() -> Array[Dictionary]:
	return sim.active.wishes.view(sim)


## The wish [param species] holds ({} if none).
func wish_of(species: StringName) -> Dictionary:
	var w := sim.active.wishes.wish_of(sim, species)
	return {} if w.is_empty() else sim.active.wishes.view_of(sim, w)


## Stamps of a friend (wish ids granted at least once, in wishes.json order).
func wish_stamps(species: StringName) -> Array[StringName]:
	return sim.active.wishes.stamps(sim, species)


## The wish list chip's unread dot: a wish opened since the card was last seen (never a number).
func wish_list_unread() -> bool:
	for w: Dictionary in sim.state.wishes:
		if float(w["opened_t"]) > sim.state.wish_list_seen_t:
			return true
	return false


func tip_seen(tip: StringName) -> bool:
	return sim != null and bool(sim.state.tips_seen.get(String(tip), false))


## Marks [param tip] shown; returns true the first time only (show the tip then).
func mark_tip_seen(tip: StringName) -> bool:
	if sim == null or tip_seen(tip):
		return false
	sim.state.tips_seen[String(tip)] = true
	SaveService.request_save()
	return true


func mark_wish_list_seen() -> void:
	sim.state.wish_list_seen_t = sim.state.t
	SaveService.request_save()


# --- Active F2 Tea & Treats

func tea_unlocked() -> bool:
	return sim.state.tea_unlocked


## A bed's petal branch (the bed release when no bud is ready): gathers every ready petal that
## fits. The view also calls world_action(&"bed_tap", {bed}) on every bed release. Returns flower
## -> count ({} when nothing was ready or the jars are full).
func harvest_bed(bed_id: StringName) -> Dictionary:
	_sync()
	if not sim.state.tea_unlocked:
		return {}
	var got := sim.active.tea.harvest_bed(sim, bed_id, sim.state.t)
	_after_action()
	return got


## Petals a tap on [param bed_id] would gather now (glints, hit priority 5, the bed card).
func petals_ready(bed_id: StringName) -> int:
	if sim == null or not sim.state.tea_unlocked:
		return 0
	return sim.active.tea.petals_ready(sim, bed_id, world_now() if is_ready else sim.state.t)


## Seconds until the next petal on a bed (INF if none can grow: no bloom, or all full).
func next_petal_in_s(bed_id: StringName) -> float:
	return sim.active.tea.next_petal_in_s(sim, bed_id, sim.state.t)


## flower -> petals in its jar.
func pantry() -> Dictionary:
	return sim.state.pantry.duplicate()


## {petals: Array[String], drops, stir_deg, recipe (what it makes now or &""), stir_target}.
func pot() -> Dictionary:
	var p := sim.state.pot.duplicate(true)
	p["recipe"] = sim.active.tea.pot_recipe(sim)
	p["stir_target"] = sim.active.tea.stir_target()
	return p


func pot_add_petal(flower: StringName) -> bool:
	return _tea_op(func() -> bool: return sim.active.tea.pot_add_petal(sim, flower))


func pot_remove(index: int) -> bool:
	return _tea_op(func() -> bool: return sim.active.tea.pot_remove(sim, index))


func pot_add_drop() -> bool:
	return _tea_op(func() -> bool: return sim.active.tea.pot_add_drop(sim))


func pot_remove_drop() -> bool:
	return _tea_op(func() -> bool: return sim.active.tea.pot_remove_drop(sim))


## Adds |deg| of stir (either direction); returns the stirred degrees, capped at the stir target
## (0 with an empty pot).
func pot_stir(deg: float) -> float:
	var v := sim.active.tea.pot_stir(sim, deg)
	SaveService.request_save()
	return v


func pot_pour() -> StringName:
	return _brew(false)


## Simple brewing (Settings): one tap, no stir.
func simple_brew() -> StringName:
	return _brew(true)


func _brew(simple: bool) -> StringName:
	_sync()
	if not sim.state.tea_unlocked:
		return &""
	var r := sim.active.tea.pour(sim, simple, sim.state.t)
	_after_action()
	return r


func _tea_op(op: Callable) -> bool:
	_sync()
	if not sim.state.tea_unlocked:
		return false
	var ok: bool = op.call()
	_after_action()
	return ok


## Cups and treats waiting: [{recipe, made_unix, drops, petals, kind}].
func tray() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Dictionary in sim.state.tray:
		var d := c.duplicate(true)
		d["kind"] = sim.active.tea.recipe_kind(StringName(c["recipe"]))
		out.append(d)
	return out


## Offers tray cup [param tray_index] to a present friend. {reaction, petals_back, wish_granted,
## affection, recipe, flower} or {} (no such cup, or the friend is not here).
func offer_cup(tray_index: int, species: StringName) -> Dictionary:
	_sync()
	var res := sim.active.tea.offer(sim, tray_index, species, sim.state.t)
	_after_action()
	return res


## recipe id -> unix time first brewed (the book).
func recipes_found() -> Dictionary:
	return sim.state.recipes_found.duplicate()


## {loves, likes, seen}: the recipes whose reaction is known (seen, or all at ♥3).
func tea_prefs_seen(species: StringName) -> Dictionary:
	return sim.active.tea.known_prefs(sim, species)


func buy_teaware(id: StringName) -> bool:
	_sync()
	var ok := sim.active.tea.buy_teaware(sim, id)
	_after_action()
	return ok


func use_teaware(id: StringName) -> bool:
	_sync()
	var ok := sim.active.tea.use_teaware(sim, id)
	_after_action()
	return ok


## {owned: Array[String] (defaults included), in_use: {teapot, cup, cloth}}.
func teaware() -> Dictionary:
	var owned: Array[String] = []
	for id: StringName in content.teaware_by_id:
		if sim.active.tea.owns_teaware(sim, id):
			owned.append(String(id))
	return {"owned": owned, "in_use": sim.active.tea.teaware_in_use(sim)}


# --- Active F3 Free décor placement

## One record per owned movable copy: {id "set#n", set, x, y, rot, stored, stack, level}.
func decor_layout() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in sim.state.decor_layout:
		out.append(p.duplicate())
	return out


## Placed copies of a set (wish gates, fx); attraction keeps counting owned copies.
func decor_placed_count(set_id: StringName) -> int:
	return sim.active.decor_placed_count(sim, set_id)


## The pure placement rules (validate / sockets / snap / magnet / nudge, ACTIVE_DECOR §4-§5) for
## the live drag; pass [method decor_context] and [method decor_layout].
func decor_rules() -> DecorPlacementRules:
	return sim.active.decor


func decor_context() -> Dictionary:
	return sim.active.context(sim)


## Settles piece [param piece_id] at [param pos_norm] (snap, nudge or float home) and commits.
## rot >= 0 sets the turn step too. {ok, pos, nudged, socket, reason, merge}; ok false = it floats
## home and nothing changed (show the reason's DECOR_HINT_* key).
func move_decor(piece_id: String, pos_norm: Vector2, rot: int = -1) -> Dictionary:
	_sync()
	var res := sim.active.move(sim, piece_id, pos_norm, rot)
	if bool(res.get("ok", false)):
		_face_cluster(piece_id)
	_after_action()
	return res


## Turn one step; returns the new step or -1.
func turn_decor(piece_id: String) -> int:
	_sync()
	var r := sim.active.turn(sim, piece_id)
	if r >= 0:
		_edit_turned[piece_id] = true
	_after_action()
	return r


## Put away into the tray (a cairn base takes its stack). The piece keeps counting for friends.
func store_decor(piece_id: String) -> bool:
	_sync()
	var ok := sim.active.store(sim, piece_id)
	_after_action()
	return ok


## Takes one stored piece of a set out to [param pos_norm]; Vector2.INF = "Find a spot".
func take_out_decor(set_id: StringName, pos_norm: Vector2 = Vector2.INF) -> Dictionary:
	_sync()
	var res := sim.active.take_out(sim, set_id, pos_norm)
	_after_action()
	return res


## "Lift a pebble": the top pebble of a stack, now a loose piece to set down. Its id or "".
func lift_pebble(stack_id: String) -> String:
	_sync()
	var id := sim.active.lift_pebble(sim, stack_id)
	_after_action()
	return id


## One-step undo of the last edit-mode commit. False (nothing changed) if there is none.
func undo_decor() -> bool:
	_sync()
	var ok := sim.active.undo(sim)
	_after_action()
	return ok


func can_undo_decor() -> bool:
	return sim.active.can_undo()


## Enters or leaves Active F3 edit mode (wish checks pause; spots recompute on exit).
func set_edit_mode(on: bool) -> bool:
	_sync()
	var ok := sim.active.set_edit_mode(sim, on)
	if ok:
		_edit_turned.clear()
	_after_action()
	return ok


func edit_mode() -> bool:
	return sim != null and sim.active.edit_mode


## A spot's position now (normalised frame): derived spots follow the placed décor (§7).
func spot_position(spot_id: StringName) -> Vector2:
	return sim.active.spot_pos(spot_id)


## Beautify (decor_placement.json face_cluster): a dropped pinwheel or lantern takes the turn step
## most common in its cluster unless the player turned it in this edit session.
func _face_cluster(piece_id: String) -> void:
	var beautify: Dictionary = content.decor_placement["beautify"]
	if _edit_turned.has(piece_id) or not bool(beautify.get("face_cluster", false)):
		return
	var i := DecorPlacementRules.find(sim.state.decor_layout, piece_id)
	var rec: Dictionary = sim.state.decor_layout[i]
	var set_id := StringName(rec["set"])
	if set_id != &"leaf_pinwheel" and set_id != DecorPlacementRules.LANTERN:
		return
	for cl: Array in sim.active.decor.clusters(sim.state.decor_layout, set_id):
		var ids := cl.map(func(p: Variant) -> String: return String((p as Dictionary)["id"]))
		if not ids.has(piece_id) or cl.size() < 2:
			continue
		var votes := {}
		for p: Variant in cl:
			var q: Dictionary = p
			if String(q["id"]) != piece_id:
				votes[int(q["rot"])] = int(votes.get(int(q["rot"]), 0)) + 1
		var best := int(rec["rot"])
		var best_n := 0
		for r: int in votes:
			if int(votes[r]) > best_n:
				best_n = int(votes[r])
				best = r
		rec["rot"] = best


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
		_:
			_emit_active(ev, offline)


## Typed Active Play v1 signals (GDD §14.11 a5; the same events also went out as sim_event).
func _emit_active(ev: Dictionary, offline: bool = false) -> void:
	match StringName(ev["type"]):
		WorldSim.EV_WISH_OPENED:
			wish_opened.emit(StringName(ev["species"]), StringName(ev["wish"]), bool(ev["visible"]))
		WorldSim.EV_WISH_SHOWN:
			wish_shown.emit(StringName(ev["species"]), StringName(ev["wish"]))
		WorldSim.EV_WISH_HELD:
			wish_held.emit(StringName(ev["species"]), StringName(ev["wish"]))
		WorldSim.EV_WISH_GRANTED:
			wish_granted.emit(StringName(ev["species"]), StringName(ev["wish"]), int(ev["affection"]),
				StringName(ev["gift_flower"]), bool(ev["first_stamp"]), bool(ev["on_arrival"]), offline)
		WorldSim.EV_TEA_UNLOCKED:
			tea_nook_awake.emit()
		WorldSim.EV_PETALS:
			petals_harvested.emit(StringName(ev["bed"]), ev["counts"])
		WorldSim.EV_RECIPE_FOUND:
			recipe_found.emit(StringName(ev["recipe"]))
		WorldSim.EV_TEA_OFFERED:
			tea_offered.emit(StringName(ev["species"]), StringName(ev["recipe"]), StringName(ev["reaction"]),
				int(ev["petals_back"]))
		WorldSim.EV_TEAWARE:
			if not bool(ev["bought"]):
				teaware_changed.emit(StringName(ev["slot"]), StringName(ev["id"]))
		WorldSim.EV_DECOR_PLACED:
			decor_placed.emit(StringName(ev["set"]), String(ev["piece"]), ev["pos"], int(ev["rot_deg"]))
		WorldSim.EV_DECOR_STORED:
			decor_stored.emit(StringName(ev["set"]), String(ev["piece"]))
		WorldSim.EV_DECOR_EDIT:
			if bool(ev["on"]):
				decor_edit_entered.emit()
			else:
				decor_edit_exited.emit()


## The creature layer reports who is napping (view-side state, ARCHITECTURE §5.4): sleepers
## snore at night and do not coo.
func report_sleepers(species: PackedStringArray) -> void:
	if species == _sleepers:
		return
	_sleepers = species
	if is_ready:
		_push_audio_state()


## True while [param species] naps in the hollow (from report_sleepers; Active F2: a cup offered
## to a napping friend waits beside it, ACTIVE_TEA §7).
func is_napping(species: StringName) -> bool:
	return _sleepers.has(String(species))


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
	# No release event arrives when the app goes away under a finger, so any gesture that holds the
	# raw pointer would keep it for the rest of the session (ARCHITECTURE §3.5).
	InputPrecision.release_all()
	_sync()
	sim.dismiss_greeter()
	_greeter_left_s = -1.0
	sim.active.set_edit_mode(sim, false)  # the app always resumes in play mode (ACTIVE_DECOR §2)
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
		var from_t := sim.state.t - float(catch["delta_s"])
		recap = Recap.build(sim, events, from_t, sim.state.t,
				CreatureBrain.nap_during(content, sim, events, from_t, sim.state.t))
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
