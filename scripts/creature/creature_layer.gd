class_name CreatureLayer
extends Node2D
## CreatureLayer (scenes/creatures/creature_layer.tscn at World/Ground/Play/Creatures): the view
## of the visitors in Game.sim (docs/ARCHITECTURE.md §5.4, GDD §4.1.3, Art Bible §5.7).
##
##  * Spawns a Mossling per visitor in sim.state.present, fades it in at its species' entry (or in
##    place when the world loads with it already here), and walks it out on departure.
##  * Plans behaviour bouts with the pure CreatureBrain (seeded per visit) and commands each
##    mossling: walk (hop / waddle) to the bout's spot, then nap / nibble / play / wander / sit.
##  * Touch (through WorldPan, the one world input arbiter: mosslings top the GDD §2.5 priority and
##    claim the drag): squash on touch-down, chirp (S13)
##    or snore (S14), name tag on tap, a second tap within 2 s emits [signal card_requested];
##    long-press 450 ms or a 24 px stroke pets (purr S03 while held, Game.pet on release).
##  * Creatures with their feet above the meadow crest draw from BehindCrest (added under
##    World/Ground before Meadow at runtime), so they rise into view over the hill.
##  * Reports nappers to Game for the audio snores (Game.report_sleepers).
##  * Active F1 Wishes: its WishView child shows the wish bubbles, the wish caption on a tap and the
##    delight on a grant (scripts/creature/wish_view.gd, which also documents --qa-wish). While a
##    friend holds a play_taps wish every tap counts toward it, so the second-tap card shortcut
##    waits until the game of tag is over (the card stays one Album tap away).
##
## QA user args: --qa-creatures=<n> (a fixture of n mosslings in varied behaviours at their
## favourite spots), --qa-pet=<species> (that mossling is petted during the capture, hearts at
## ~3 s; add --qa-pet-hold to capture it mid-pet), --qa-walk (fixture creatures enter from their
## entries instead of starting in place).
## Touch strip (Director R3 #1): --qa-touch=<species>:<kind>:<ms> touches that mossling at
## QA_TOUCH_AT_S after the fixture spawns and FREEZES it (and its stamps) <ms> later, so a still
## proves the feedback. Kinds: tap (down, up after 80 ms: ripple, squash, ^ ^ eyes, sparkles,
## name tag; a napper only stirs), hold (down, never up: ripple, fill ring < 450 ms, then the pet
## squash 0.88 with happy eyes and little hearts), release (pet for QA_RELEASE_HOLD_S, then up:
## <ms> after the release, the heart bouquet and the overshoot). Needs --frames >= 90.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## A second tap within tap.second_tap_opens_card_ms asks the UI for this friend's card.
signal card_requested(species: StringName)
## A mossling was petted (after release; the UI may show a heart counter).
signal mossling_petted(species: StringName)

const ARG_QA_CREATURES := "--qa-creatures="
const ARG_QA_PET := "--qa-pet="
const ARG_QA_WALK := "--qa-walk"
const ARG_QA_PET_HOLD := "--qa-pet-hold"
const ARG_QA_TOUCH := "--qa-touch="
const QA_TOUCH_AT_S := 1.0
const QA_TAP_UP_S := 0.08
const QA_RELEASE_HOLD_S := 1.2
const QA_PARTNER_MAX_PX := 360.0
const ARG_TOD := "--tod="
const ARG_WEATHER := "--weather="
const BEHIND_CREST := "BehindCrest"
const SHADOWS := "CreatureShadows"
## The shadow host's y: far above the frame, so the y-sorted Play draws it first.
const SHADOW_SORT_Y := -100000.0
const GROUND := "Ground"
## QA fixture: species, behaviour, spot and pose hints (Mossling.perform params), in the order
## --qa-creatures takes them (only spots that exist without décor, so a fresh install shows
## them). The hints vary the looks and faces so one still reads as a lively hollow (QA r3 #2):
## friends turn toward each other, one beams "^ ^", the stream-sitter watches the water.
const QA_FIXTURE: Array[Array] = [
	[&"puffmoss", &"nap", &"sun_stone", {}],
	[&"buttonbud", &"nibble", &"clover_bank", {}],
	[&"pebblepaw", &"sit_by_stream", &"stream_bend", {"look": 0.7}],
	[&"honeyhum", &"play", &"moss_cushion", {"look": 0.8, "look_hold_s": 8.0, "happy_s": 8.0}],
	[&"dandelfluff", &"play", &"hill_crest", {"look": -0.5, "look_hold_s": 8.0}],
	[&"primpip", &"nap", &"stump_hollow", {}],
	[&"bellkin", &"wander", &"willow_root", {"look": 0.4}],
	[&"fernwhisk", &"nap", &"fern_shade", {}],
	[&"moonpuff", &"nap", &"moon_rock", {}],
]
const QA_PET_DOWN_S := 0.4
const QA_PET_UP_S := 2.5
const QA_FIXTURE_STAY_S := 3600.0
## Path shaping: a gentle sideways bow so walks are never ruler-straight.
const PATH_BOW := 0.12
const PATH_STEP_PX := 60.0
const BOAT_WATCH_PX := 300.0
const BANK_OFFSET_PX := 46.0
const CREST_MARGIN_PX := 4.0
const MS := 0.001
## play_taps hop aside: the friend stays this long off its bout spot before the brain walks it back.
const HOP_ASIDE_HOLD_S := 4.0

## The live layer (null when no main scene is loaded): the Album's "Say hello" reaches the hollow.
static var current: CreatureLayer = null

var rig: MosslingRig
## Active F1: the wish bubbles and delights (child node).
var wishes: WishView
var brain: CreatureBrain

var _content: GameContent
var _fur: ShaderMaterial
var _shadow: ShaderMaterial
var _fx: Dictionary = {}
var _mosslings: Dictionary = {}          # species -> Mossling (visitors)
var _extras: Array[Mossling] = []        # peeks and leavers
var _commanded: Dictionary = {}          # species -> Bout last commanded
var _override_until: Dictionary = {}     # species -> world t (boat watching)
var _behind: Node2D
var _shadows: Node2D
var _shadow_batch_bias: float = 0.0
var _focal_spot: StringName = &""
var _crest: PackedVector2Array = PackedVector2Array()
var _touch: Mossling = null
var _last_tap: Dictionary = {}           # species -> ticks s
var _qa_count: int = 0
var _qa_pet: StringName = &""
var _qa_walk: bool = false
var _qa_pet_hold: bool = false
var _qa_t: float = 0.0
var _qa_pet_state: int = 0
var _qa_touch: PackedStringArray = PackedStringArray()   # species, kind, ms
var _qa_touch_t: float = -1.0
var _pinned_env: bool = false
var _rain: bool = false
var _sleepers: PackedStringArray = PackedStringArray()
var _frame: Vector2 = Vector2(1080, 1920)
var _obstacles: Array[Rect2] = []
var _feed := PaletteFeed.new()
## Retention v1 ♥1 "waves hello on open" (GDD §13.2): the plan Game handed us on world_ready,
## still waiting for the hollow to be clear. Entries are {species, delay_s, pose}.
var _waves: Array[Dictionary] = []
## Retention v1 F3 away scenes (GDD §13.4): the staged scene's id and its cast. Present friends
## walk to their slots under an override; absent ones are summoned as extras and leave when the
## scene is archived. Nothing here changes state: a tap goes through Game.tap_scene.
var _scene_id: StringName = &""
var _scene_cast: Array[Mossling] = []
var _scene_extras: Array[Mossling] = []
## Seconds the hollow has been clear since the plan arrived (the welcome-back card counts as
## covered: the friends say hello to the player, not to the back of a card).
var _wave_t: float = 0.0


func _ready() -> void:
	add_to_group(WorldPan.GROUP_HIT)
	current = self
	_content = ContentRegistry.content
	wishes = WishView.new()
	wishes.name = "WishView"
	wishes.layer = self
	add_child(wishes)
	rig = MosslingRig.new(_content)
	_fur = rig.make_fur_material()
	MosslingRig.bind_palette(_fur, _feed)
	_feed.apply(TimeOfDay.colors)
	TimeOfDay.globals_updated.connect(_on_globals)
	_shadow = rig.make_shadow_material()
	_fx = rig.make_fx_materials()
	var frame: Dictionary = _content.spots_doc.get("frame", {})
	_frame = Vector2(float(frame.get("width_px", 1080)), float(frame.get("height_px", 1920)))
	var crest: Array = (rig.view().get("crest", {}) as Dictionary).get("points", [])
	for pt: Array in crest:
		_crest.append(Vector2(float(pt[0]), float(pt[1])))
	var obs: Dictionary = rig.view().get("obstacles", {})
	var px_per_dp := float(frame.get("px_per_dp", 3))
	for id: Variant in obs.get("props", []):
		var pr: Dictionary = _content.props_by_id.get(StringName(String(id)), {})
		if pr.is_empty():
			continue
		var size := Vector2(float(pr["w_dp"]), float(pr["h_dp"])) * px_per_dp * float(obs.get("scale", 0.5)) \
			+ Vector2.ONE * 2.0 * float(obs.get("margin_px", 30.0))
		var c := Vector2(float(pr["x"]) * _frame.x, float(pr["y"]) * _frame.y)
		_obstacles.append(Rect2(c - size * 0.5, size))
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(ARG_QA_CREATURES):
			_qa_count = clampi(a.trim_prefix(ARG_QA_CREATURES).to_int(), 0, QA_FIXTURE.size())
		elif a.begins_with(ARG_QA_PET):
			_qa_pet = StringName(a.trim_prefix(ARG_QA_PET))
		elif a == ARG_QA_WALK:
			_qa_walk = true
		elif a == ARG_QA_PET_HOLD:
			_qa_pet_hold = true
		elif a.begins_with(ARG_QA_TOUCH):
			_qa_touch = a.trim_prefix(ARG_QA_TOUCH).split(":")
			if _qa_touch.size() < 3:
				push_warning("--qa-touch=<species>:<tap|hold|release>:<ms>")
				_qa_touch = PackedStringArray()
		elif a.begins_with(ARG_TOD) or a.begins_with(ARG_WEATHER):
			_pinned_env = true
	Game.sim_event.connect(_on_sim_event)
	Game.world_ready.connect(_on_world_ready)
	Game.suspended.connect(_on_suspended)
	Game.scene_ready.connect(_stage_scene)
	Game.scene_archived.connect(func(_m: Dictionary) -> void: _end_scene())
	if Game.is_ready:
		# deferred: BehindCrest is added to Ground, which is still setting up its children now
		_on_world_ready.call_deferred([])


func _on_globals(_values: Dictionary) -> void:
	_feed.apply(TimeOfDay.colors)


func _exit_tree() -> void:
	if current == self:
		current = null
	if _touch != null:
		AudioDirector.stop_purr()


# ================================================================= sim binding

func _on_world_ready(_recap: Array) -> void:
	var sim := Game.sim
	if sim == null:
		return
	if brain == null or brain.install_seed != sim.state.install_seed:
		brain = CreatureBrain.new(_content, sim.state.install_seed)
		brain.env = _env_at
		brain.owned = func(item: StringName) -> int: return Game.sim.owned_count(item)
		brain.bed_flowers = _bed_flowers
		brain.nests = func(sp: StringName) -> Dictionary: return Game.nest_state(sp)
	_ensure_behind()
	# everyone already in the hollow appears where their bout puts them (fade in place)
	var here := {}
	for p: Dictionary in sim.state.present:
		var sp := StringName(p["species"])
		here[sp] = true
		if not brain.has_visit(sp):
			brain.add_visit(sp, float(p["arrive_t"]), float(p["depart_t"]), bool(p["greeter"]))
		if not _mosslings.has(sp):
			_spawn(sp, false)
	for sp: StringName in _mosslings.keys():
		if not here.has(sp) and not _is_qa(sp):
			_send_away(sp)
	if _qa_count > 0 and _qa_t == 0.0:
		_spawn_fixture()
	wishes.sync()
	# ♥1: the friends who know you look up and say hello once the card is out of the way.
	_waves = Game.wave_plan()
	_wave_t = 0.0
	# F3: a scene pending from before the close (or staged by this return) is on stage already.
	var pending := Game.pending_scene()
	if not pending.is_empty():
		_stage_scene(pending)


func _on_suspended() -> void:
	if _touch != null:
		_touch.cancel_touch()
		_touch = null


func _on_sim_event(ev: Dictionary) -> void:
	if brain == null or bool(ev.get("catch_up", false)):
		return
	var type := StringName(ev["type"])
	match type:
		WorldSim.EV_ARRIVED:
			var sp := StringName(ev["species"])
			if bool(ev.get("peek", false)):
				_spawn_peek(sp)
				return
			var p := _present(sp)
			if p.is_empty():
				return
			brain.add_visit(sp, float(p["arrive_t"]), float(p["depart_t"]), false)
			_commanded.erase(sp)
			if _mosslings.has(sp):
				(_mosslings[sp] as Mossling).is_greeter = false
			else:
				var m := _spawn(sp, true)
				if bool(ev.get("debut", false)):
					m.walk_finished.connect(func() -> void: m.sparkle(5), CONNECT_ONE_SHOT)
		WorldSim.EV_GREETER_ARRIVED:
			var sp := StringName(ev["species"])
			var p := _present(sp)
			if p.is_empty():
				return
			brain.add_visit(sp, float(p["arrive_t"]), float(p["depart_t"]), true)
			var m := _spawn(sp, true)
			m.is_greeter = true
			m.walk_finished.connect(m.greet, CONNECT_ONE_SHOT)
		WorldSim.EV_DEPARTED, WorldSim.EV_GREETER_LEFT:
			_send_away(StringName(ev["species"]))
		WorldSim.EV_BOAT:
			_watch_boat()
		WorldSim.EV_HEARTS:
			var m: Mossling = _mosslings.get(StringName(ev["species"]))
			if m != null:
				m.sparkle(5)


func _present(sp: StringName) -> Dictionary:
	for p: Dictionary in Game.sim.state.present:
		if StringName(p["species"]) == sp:
			return p
	return {}


func _now() -> float:
	return Game.world_now() if Game.is_ready else 0.0


## Runs the ♥1 wave plan once the recap (or any card) is out of the way, each friend after its
## own deterministic delay. A friend that has since left, fallen asleep or started leaving is
## simply skipped: a hello is never owed, and nothing about it can be missed.
func _wave_tick(delta: float) -> void:
	if _waves.is_empty():
		return
	var pan := WorldPan.current
	if pan != null and pan.is_blocked():
		return
	_wave_t += delta
	var still: Array[Dictionary] = []
	for w: Dictionary in _waves:
		if _wave_t < float(w["delay_s"]):
			still.append(w)
			continue
		var sp := StringName(w["species"])
		var m: Mossling = _mosslings.get(sp)
		if m != null and is_instance_valid(m) and not m.leaving and not m.asleep:
			m.play_pose(StringName(w["pose"]))
	_waves = still


func _env_at(t: float) -> Dictionary:
	if _pinned_env or Game.sim == null:
		return {"phase": TimeOfDay.phase, "weather": TimeOfDay.weather}
	return {"phase": Game.sim.phase_at(t), "weather": Game.sim.weather_at(t)}


func _bed_flowers(bed_id: StringName) -> Array:
	var out: Array = []
	if Game.sim == null:
		return out
	for st: Dictionary in Game.sim.state.stems:
		if StringName(st["bed"]) == bed_id:
			out.append(StringName(st["flower"]))
	return out


# ================================================================= frame

func _process(delta: float) -> void:
	if brain == null:
		return
	var t := _now()
	brain.advance(t)
	_rain = StringName(_env_at(t).get("weather", &"")) == CreatureBrain.RAIN
	for sp: StringName in _mosslings:
		var m: Mossling = _mosslings[sp]
		if m.leaving:
			continue
		if float(_override_until.get(sp, -INF)) > t:
			continue
		var bout := brain.current(sp, t)
		if bout != null and _commanded.get(sp) != bout:
			_commanded[sp] = bout
			_command(m, bout)
		if bout != null:
			m.set_rain(_rain, bout.shelter, bout.umbrella)
	_update_depth_parents()
	_report_sleepers()
	_wave_tick(delta)
	if _qa_count > 0 or _qa_pet != &"":
		_qa_tick(delta)
	if not _qa_touch.is_empty():
		_qa_touch_tick(delta)


func _command(m: Mossling, bout: CreatureBrain.Bout) -> void:
	var params := {"shelter": bout.shelter}
	var bed := CreatureBrain.nibble_bed(bout.spot)
	if bed != &"":
		var bp := GardenRules.bed_position_px(_content, bed)
		params["lean_dir"] = signf(bp.x - bout.pos.x) if absf(bp.x - bout.pos.x) > 1.0 else 1.0
	elif bout.behaviour == CreatureBrain.NIBBLE:
		params["lean_dir"] = 1.0 if m.feet().x < _frame.x * 0.5 else -1.0
	if bout.partner != &"" and _mosslings.has(bout.partner):
		params["partner"] = _mosslings[bout.partner]
		params["offset_s"] = float(rig.behaviour().get("play_pair_offset_s", 0.8))
	var perch := float((rig.view().get("perch_sort_px", {}) as Dictionary).get(String(bout.spot), 0.0))
	var target := bout.pos
	var go := func() -> void:
		m.set_sort_bias(perch)
		m.perform(bout.behaviour, bout.spot, params)
	if m.feet().distance_to(target) < 6.0:
		go.call()
		return
	m.set_sort_bias(0.0)
	m.walk(_path(m.feet(), target, m.seed01), go)


## A gently bowed path (quadratic through a sideways-offset midpoint), sampled every ~60 px,
## that steps around the big props (basket, sun stone, stump, spring rock, mailbox) unless the
## walk ends on that prop.
func _path(from: Vector2, to: Vector2, seed01: float) -> PackedVector2Array:
	var d := to - from
	var n := maxi(1, ceili(d.length() / PATH_STEP_PX))
	var side := 1.0 if fposmod(seed01 * 7.0, 1.0) < 0.5 else -1.0
	var mid := from + d * 0.5 + Vector2(-d.y, d.x).normalized() * d.length() * PATH_BOW * side
	var out := PackedVector2Array()
	for i in range(1, n + 1):
		var u := float(i) / float(n)
		var p := from.lerp(mid, u).lerp(mid.lerp(to, u), u)
		out.append(p if i == n else _around_props(p, to))
	return out


## Pushes a path point out of every obstacle ellipse that does not contain the walk's target.
func _around_props(p: Vector2, target: Vector2) -> Vector2:
	for o: Rect2 in _obstacles:
		var c := o.get_center()
		var r := o.size * 0.5
		if ((target - c) / r).length() <= 1.0:
			continue
		var q := (p - c) / r
		var k := q.length()
		if k < 1.0:
			p = c + (q / maxf(k, 1e-3)) * r
	return p


# ================================================================= spawning

func _make(sp: StringName, seed01: float) -> Mossling:
	var m := Mossling.new()
	add_child(m)
	m.setup(rig, sp, seed01, _fur, _shadow, _fx)
	m.tapped.connect(_on_tapped)
	m.touched.connect(_on_touched)
	m.petted.connect(_on_petted)
	m.pet_started.connect(func(x: Mossling) -> void: AudioDirector.start_purr(x.voice_step))
	m.pet_ended.connect(func(_x: Mossling) -> void: AudioDirector.stop_purr())
	m.left_hollow.connect(_on_left)
	return m


func _seed_for(sp: StringName) -> float:
	var v := brain.visit(sp)
	var s := CreatureBrain.visit_seed(brain.install_seed, sp, v.arrive_t if v != null else 0.0)
	return fposmod(float(s & 0xFFFF) / 65536.0, 1.0)


## A visitor's mossling. [param walk_in]: fade in at the entry and walk to the first bout (a live
## arrival); otherwise it fades in at its current bout (the world loaded with it already here).
func _spawn(sp: StringName, walk_in: bool) -> Mossling:
	var m := _make(sp, _seed_for(sp))
	_mosslings[sp] = m
	brain.advance(_now())
	var bout := brain.current(sp, _now())
	var entry := _entry_px(sp)
	if walk_in or bout == null:
		var target := bout.pos if bout != null else entry
		var arrive := Callable()
		if bout != null:
			_commanded[sp] = bout
			var perch := float((rig.view().get("perch_sort_px", {}) as Dictionary).get(String(bout.spot), 0.0))
			arrive = func() -> void:
				m.set_sort_bias(perch)
				m.perform(bout.behaviour, bout.spot, {"shelter": bout.shelter})
		m.enter_from(entry, _path(entry, target, m.seed01), arrive)
		AudioDirector.play_cue(&"S12", {"voice_step": m.voice_step, "haptic": false})
	else:
		m.enter_from(bout.pos, PackedVector2Array(), Callable())
		_commanded.erase(sp)
	return m


func _send_away(sp: StringName) -> void:
	var m: Mossling = _mosslings.get(sp)
	if m != null:
		_scene_cast.erase(m)
	brain.remove_visit(sp)
	_commanded.erase(sp)
	_override_until.erase(sp)
	if m == null:
		return
	_mosslings.erase(sp)
	if _touch == m:
		_touch = null
	_extras.append(m)
	m.set_sort_bias(0.0)
	m.leave_to(_path(m.feet(), _entry_px(sp), m.seed01))


func _spawn_peek(sp: StringName) -> void:
	var m := _make(sp, randf())
	_extras.append(m)
	var entry := _entry_px(sp)
	var rim := entry.lerp(Vector2(_frame.x * 0.5, entry.y), 0.18)
	m.peek(entry, _path(entry, rim, m.seed01), _path(rim, entry, m.seed01))


func _on_left(m: Mossling) -> void:
	_extras.erase(m)
	m.queue_free()


func _entry_px(sp: StringName) -> Vector2:
	var s: Dictionary = _content.species_by_id.get(sp, {})
	var e: Dictionary = _content.entries_by_id.get(StringName(s.get("entry", "")), {})
	return Vector2(float(e.get("x", 0.5)) * _frame.x, float(e.get("y", 0.5)) * _frame.y)


## Leaf boat (GDD §4.1.3): awake mosslings turn to watch; those within 300 px of the stream
## hop to the bank and sit there until it has passed.
func _watch_boat() -> void:
	var ui: Dictionary = (_content.motion.get("ui", {}) as Dictionary).get("leaf_boat", {})
	var drift := float(ui.get("drift_s", 40.0))
	var t := _now()
	var spring: Dictionary = _content.props_by_id.get(&"spring_rock", {})
	var spring_x := float(spring.get("x", 0.95)) * _frame.x
	for sp: StringName in _mosslings:
		var m: Mossling = _mosslings[sp]
		if m.asleep or m.leaving:
			continue
		var bank := _bank_point(m.feet().x)
		m.turn_to(signf(spring_x - m.feet().x) * 0.7)
		if m.feet().distance_to(bank) <= BOAT_WATCH_PX and m.behaviour != CreatureBrain.STREAM:
			_override_until[sp] = t + drift
			_commanded.erase(sp)
			m.set_sort_bias(0.0)
			m.walk(_path(m.feet(), bank, m.seed01), func() -> void:
				m.perform(CreatureBrain.STREAM, &"", {"look": signf(spring_x - bank.x) * 0.7}))


## The upper bank above the brook at x (stream polyline from spots.json).
func bank_point(x: float) -> Vector2:
	return _bank_point(x)


func _bank_point(x: float) -> Vector2:
	var poly: Array = (_content.spots_doc.get("stream", {}) as Dictionary).get("polyline", [])
	var best := Vector2(x, _frame.y * 0.75)
	for i in range(poly.size() - 1):
		var a: Array = poly[i]
		var b: Array = poly[i + 1]
		var ax := float(a[0]) * _frame.x
		var bx := float(b[0]) * _frame.x
		if (x <= ax and x >= bx) or (x >= ax and x <= bx):
			var u := (x - ax) / (bx - ax) if absf(bx - ax) > 1e-3 else 0.0
			best = Vector2(x, lerpf(float(a[1]), float(b[1]), u) * _frame.y - BANK_OFFSET_PX)
	return best


# ================================================================= Active F1 wish helpers

## The visitor mossling of [param sp] (null when it is not in the hollow).
func mossling(sp: StringName) -> Mossling:
	var m: Mossling = _mosslings.get(sp)
	return m if m != null and is_instance_valid(m) else null


func visitors() -> Array[Mossling]:
	var out: Array[Mossling] = []
	for sp: StringName in _mosslings:
		out.append(_mosslings[sp])
	return out


## The design frame (spots.json frame, px).
func frame_size() -> Vector2:
	return _frame


## A walk for a wish (to the bed, the piece, the bank): the brain waits [param hold_s] before it
## plans this friend again, then [param then] runs at the destination.
func walk_for_wish(m: Mossling, to: Vector2, hold_s: float, then: Callable) -> void:
	var sp := m.species_id
	_override_until[sp] = _now() + hold_s
	_commanded.erase(sp)
	m.set_sort_bias(0.0)
	m.walk(_path(m.feet(), to, m.seed01), then)


## play_taps (ACTIVE_WISHES §5): a small hop [param px] aside to a free point of the tend zone,
## then a look back at the player.
func hop_aside(m: Mossling, px: float) -> void:
	var zone: Dictionary = rig.behaviour().get("tend_zone_px", {})
	var zx: Array = zone.get("x", [110, 970])
	var dir := -1.0 if m.feet().x > _frame.x * 0.5 else 1.0
	if fposmod(m.seed01 * 13.0 + float(_now()), 1.0) < 0.3:
		dir = -dir
	var to := m.feet() + Vector2(dir * px, -px * 0.15)
	to.x = clampf(to.x, float(zx[0]), float(zx[1]))
	walk_for_wish(m, to, HOP_ASIDE_HOLD_S, m.look_at_camera)


# ================================================================= depth: behind the crest

func _ensure_behind() -> void:
	if _behind != null and is_instance_valid(_behind):
		return
	var ground: Node = get_parent()
	while ground != null and ground.name != GROUND:
		ground = ground.get_parent()
	if ground == null:
		return
	var existing := ground.get_node_or_null(BEHIND_CREST)
	if existing is Node2D:
		_behind = existing as Node2D
		return
	_behind = Node2D.new()
	_behind.name = BEHIND_CREST
	_behind.y_sort_enabled = true
	ground.add_child(_behind)
	ground.move_child(_behind, 0)
	# same space as this layer (Play and its children sit at the Ground origin)
	_behind.global_transform = get_global_transform()


func crest_y(x: float) -> float:
	if _crest.size() < 2:
		return -INF
	for i in range(_crest.size() - 1):
		var a := _crest[i]
		var b := _crest[i + 1]
		if x >= a.x and x <= b.x:
			var u := (x - a.x) / maxf(b.x - a.x, 1e-3)
			return lerpf(a.y, b.y, u * u * (3.0 - 2.0 * u))
	return _crest[0].y if x < _crest[0].x else _crest[_crest.size() - 1].y


func _update_depth_parents() -> void:
	_ensure_shadows()
	for m: Mossling in _all():
		var behind := _behind != null and m.feet().y < crest_y(m.feet().x) - CREST_MARGIN_PX
		var want: Node = _behind if behind else self
		if _behind != null and m.get_parent() != want:
			m.reparent(want, false)
		# meadow creatures draw their shadows from one batch under everything on the meadow;
		# creatures perched on a prop (sort bias above view.shadow_batch_max_bias_px) and behind
		# the crest keep theirs in their own subtree, so it lands on the prop / behind the hill
		var batch := not behind and m.sort_bias() <= _shadow_batch_bias
		m.set_shadow_host(_shadows if batch else null)
		m.set_focal(m.spot_id == _focal_spot and not m.is_walking() and not m.leaving)


## The shared shadow host (Art Bible §4.19 batching): sorts before every prop and creature in
## Play, its children draw in tree order with one material and no instance uniforms.
func _ensure_shadows() -> void:
	if _shadows != null and is_instance_valid(_shadows):
		return
	_shadow_batch_bias = float(rig.view().get("shadow_batch_max_bias_px", 0.0))
	_focal_spot = StringName(String(rig.view().get("focal_spot", "sun_stone")))
	_shadows = Node2D.new()
	_shadows.name = SHADOWS
	_shadows.position = Vector2(0.0, SHADOW_SORT_Y)
	add_child(_shadows)


func _all() -> Array[Mossling]:
	var out: Array[Mossling] = []
	for sp: StringName in _mosslings:
		out.append(_mosslings[sp])
	out.append_array(_extras)
	return out


func _report_sleepers() -> void:
	var s := PackedStringArray()
	for sp: StringName in _mosslings:
		if (_mosslings[sp] as Mossling).asleep:
			s.append(String(sp))
	if s != _sleepers:
		_sleepers = s
		Game.report_sleepers(s)


# ================================================================= touch

## WorldPan (the world input arbiter, ARCHITECTURE §3.5): the mossling nearest the point whose hit circle
## (+ the fat-finger slop) holds the point. A mossling claims the drag: a stroke on it pets it and
## never pans the map.
func world_hit(canvas_pos: Vector2, slop: float) -> Dictionary:
	var p := _local(canvas_pos)
	var best := {}
	for m: Mossling in _all():
		var c := m.hit_circle()
		if c.z <= 0.0:
			continue
		# inside beats slop; then the nearer body centre (two friends side by side split the overlap)
		var cand := WorldPan.circle_hit(p, Vector2(c.x, c.y), c.z, slop, WorldPan.PRIO_MOSSLING, m)
		if not cand.is_empty() and (best.is_empty() or WorldPan.better(cand, best)):
			best = cand
	if not best.is_empty():
		best["drag"] = true
	return best


func world_press(key: Variant, canvas_pos: Vector2) -> void:
	var m := key as Mossling
	if m == null or not is_instance_valid(m):
		return
	_touch = m
	m.touch_down(_local(canvas_pos))


func world_drag(key: Variant, canvas_pos: Vector2) -> void:
	var m := key as Mossling
	if m != null and is_instance_valid(m) and m == _touch:
		m.touch_move(_local(canvas_pos))


func world_release(key: Variant, canvas_pos: Vector2, act: bool) -> void:
	var m := key as Mossling
	_touch = null
	if m == null or not is_instance_valid(m):
		return
	if act:
		m.touch_up(_local(canvas_pos))
	else:
		m.cancel_touch()


## Debug overlay (--debug-hits): every touchable mossling's hit circle, in canvas px.
func world_hit_shapes() -> Array:
	var out: Array = []
	var xf := get_global_transform_with_canvas()
	for m: Mossling in _all():
		var c := m.hit_circle()
		if c.z > 0.0:
			out.append({"kind": "circle", "c": xf * Vector2(c.x, c.y), "r": c.z * xf.get_scale().x,
				"prio": WorldPan.PRIO_MOSSLING, "name": String(m.species_id)})
	return out


func _local(screen: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen


func _on_touched(m: Mossling) -> void:
	# I1: the cue fires on touch-down, with the squash, in the same frame
	if m.asleep:
		AudioDirector.play_cue(&"S14", {"position": m.global_position})
	else:
		AudioDirector.play_cue(&"S13", {"voice_step": m.voice_step, "position": m.global_position})


func _on_tapped(m: Mossling) -> void:
	if _scene_cast.has(m) and Game.is_ready:
		Game.tap_scene()  # GDD §13.4 step 6: the player looked - it goes to Memories (and the name tag still shows)
	var tap: Dictionary = (_content.motion.get("creature", {}) as Dictionary).get("tap", {})
	var window_s := float(tap.get("second_tap_opens_card_ms", 2000.0)) * MS
	var now := Clock.ticks_s()
	var last := float(_last_tap.get(m.species_id, -INF))
	_last_tap[m.species_id] = now
	var tag_game := Game.is_ready and StringName(Game.wish_of(m.species_id).get("kind", "")) == &"play_taps"
	if now - last <= window_s and not tag_game:
		card_requested.emit(m.species_id)
		_last_tap.erase(m.species_id)
		return
	if not wishes.on_tapped(m):
		m.show_name(Game.display_name(m.species_id) if Game.is_ready else String(m.species_id))


func _on_petted(m: Mossling) -> void:
	if Game.is_ready and not _is_qa(m.species_id):
		Game.pet(m.species_id)
	mossling_petted.emit(m.species_id)


# ================================================================= away scenes (Retention v1 F3)

## Stages [param sc] (a Game.pending_scene / scene_ready record): each role's friend goes to its
## slot and holds the scene's pose (SceneLayer.scene_pose). A friend already in the hollow walks
## there under an override; one who is not fades in at the slot as an extra, like a greeter: no
## gift, no affection, and it walks off when the scene ends.
func _stage_scene(sc: Dictionary) -> void:
	var id := StringName(String(sc.get("scene", "")))
	if id == &"" or id == _scene_id:
		return
	if _scene_id != &"":
		_end_scene()
	var cast: Array = sc.get("cast", [])
	var def: Dictionary = _content.scenes_by_id.get(id, {})
	var roles: Array = def.get("roles", [])
	var anchor := SceneLayer.anchor_px(_content, id, cast)
	_scene_id = id
	for i in cast.size():
		var sp := StringName(String(cast[i]))
		var slot := SceneLayer.slot_px(_content, id, i, cast)
		var pose_id := StringName(String((roles[i] as Dictionary).get("pose", ""))) if i < roles.size() else &""
		var pose := SceneLayer.scene_pose(pose_id, slot, anchor)
		var m: Mossling = _mosslings.get(sp)
		if m != null and not m.leaving:
			_override_until[sp] = INF
			m.set_sort_bias(0.0)
			var hold := func() -> void:
				m.perform(StringName(String(pose["behaviour"])), SceneLayer.SCENE_SPOT, pose["params"])
			if m.feet().distance_to(slot) < 6.0:
				hold.call()
			else:
				m.walk(_path(m.feet(), slot, m.seed01), hold)
		else:
			m = _make(sp, fposmod(float(hash([String(sp), String(id)]) & 0xFFFF) / 65536.0, 1.0))
			_extras.append(m)
			_scene_extras.append(m)
			m.enter_from(slot, PackedVector2Array(), Callable())
			m.perform(StringName(String(pose["behaviour"])), SceneLayer.SCENE_SPOT, pose["params"])
		_scene_cast.append(m)
	AudioDirector.play_cue(SceneLayer.CUE_STAGED, {"haptic": false})


## The scene was archived (tapped, or 600 s of foreground time): the visitors go back to their
## bouts and the summoned friends walk off.
func _end_scene() -> void:
	for m: Mossling in _scene_cast:
		if not is_instance_valid(m):
			continue
		if _scene_extras.has(m):
			if not m.leaving:
				m.leave_to(_path(m.feet(), _entry_px(m.species_id), m.seed01))
		else:
			_override_until.erase(m.species_id)
			_commanded.erase(m.species_id)  # the brain re-commands on the next frame
	_scene_cast.clear()
	_scene_extras.clear()
	_scene_id = &""


## Tests and the debug readout: the staged scene and who is in it.
func staged_scene() -> StringName:
	return _scene_id


func is_in_scene(m: Mossling) -> bool:
	return _scene_cast.has(m)


# ================================================================= QA fixture

func _is_qa(sp: StringName) -> bool:
	for row: Array in QA_FIXTURE.slice(0, _qa_count):
		if row[0] == sp:
			return true
	return false


## --qa-creatures=n: n mosslings in varied behaviours at their favourite spots (fresh install,
## no décor needed), each planned through the brain like a real visit.
func _spawn_fixture() -> void:
	var t := _now()
	for i in _qa_count:
		var row: Array = QA_FIXTURE[i]
		var sp: StringName = row[0]
		if _mosslings.has(sp):
			continue
		brain.add_visit(sp, t - 1.0, t + QA_FIXTURE_STAY_S, false)
		var bout := brain.force_bout(sp, row[1], row[2], t, QA_FIXTURE_STAY_S)
		var m := _make(sp, _seed_for(sp))
		_mosslings[sp] = m
		_commanded[sp] = bout
		var perch := float((rig.view().get("perch_sort_px", {}) as Dictionary).get(String(bout.spot), 0.0))
		var params := {"shelter": bout.shelter}
		var hints: Dictionary = row[3] if row.size() > 3 else {}
		params.merge(hints)
		if bout.behaviour == CreatureBrain.NIBBLE:
			params["lean_dir"] = 1.0
		elif bout.behaviour == CreatureBrain.PLAY:
			# a lively still: players face their nearest friend (two friends chatting)
			var near: Mossling = null
			for other: StringName in _mosslings:
				var o: Mossling = _mosslings[other]
				if o != m and (near == null or o.feet().distance_to(bout.pos) < near.feet().distance_to(bout.pos)):
					near = o
			if near != null and near.feet().distance_to(bout.pos) <= QA_PARTNER_MAX_PX:
				params["partner"] = near
		if _qa_walk:
			var entry := _entry_px(sp)
			m.enter_from(entry, _path(entry, bout.pos, m.seed01), func() -> void:
				m.set_sort_bias(perch)
				m.perform(bout.behaviour, bout.spot, params))
		else:
			m.place_at(bout.pos)
			m.set_sort_bias(perch)
			m.perform(bout.behaviour, bout.spot, params)
			if bout.behaviour == CreatureBrain.NAP:
				m.debug_pose(&"asleep")
	_qa_t = maxf(_qa_t, 1e-3)


## --qa-touch timeline (see the header): touch at QA_TOUCH_AT_S, freeze <ms> after the touch
## (tap / hold) or after the release (release).
func _qa_touch_tick(delta: float) -> void:
	var sp := StringName(_qa_touch[0])
	if not _mosslings.has(sp):
		return
	var m: Mossling = _mosslings[sp]
	if _qa_touch_t < 0.0:
		_qa_touch_t = 0.0
	var t0 := _qa_touch_t - QA_TOUCH_AT_S
	_qa_touch_t += delta
	var t1 := _qa_touch_t - QA_TOUCH_AT_S
	var kind := _qa_touch[1]
	var ms := _qa_touch[2].to_float() * MS
	var at := m.feet() - Vector2(0.0, rig.body_px(sp) * 0.55 * m.depth)
	if t0 < 0.0 and t1 >= 0.0:
		_touch = m
		m.touch_down(at)
	if kind == "tap" and t0 < QA_TAP_UP_S and t1 >= QA_TAP_UP_S:
		m.touch_up(at)
		_touch = null
	if kind != "tap" and t1 > 0.0 and t1 < QA_RELEASE_HOLD_S:
		m.touch_move(at + Vector2(sin(t1 * 5.0) * 6.0, 0.0))
	if kind == "release" and t0 < QA_RELEASE_HOLD_S and t1 >= QA_RELEASE_HOLD_S:
		m.touch_up(at)
		_touch = null
	var freeze_at := ms + (QA_RELEASE_HOLD_S if kind == "release" else 0.0)
	if t0 < freeze_at and t1 >= freeze_at:
		m.freeze(true)


func _qa_tick(delta: float) -> void:
	_qa_t += delta
	if _qa_pet == &"" or not _mosslings.has(_qa_pet):
		return
	var m: Mossling = _mosslings[_qa_pet]
	var head := m.feet() - Vector2(0.0, rig.body_px(_qa_pet) * 0.5 * m.depth)
	if _qa_pet_state == 0 and _qa_t >= QA_PET_DOWN_S:
		_qa_pet_state = 1
		m.touch_down(head)
	elif _qa_pet_state == 1:
		m.touch_move(head + Vector2(sin(_qa_t * 5.0) * 6.0, 0.0))
		if _qa_t >= QA_PET_UP_S and not _qa_pet_hold:
			_qa_pet_state = 2
			m.touch_up(head)
