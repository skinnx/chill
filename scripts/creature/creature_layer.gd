extends Node2D
## CreatureLayer (scenes/creatures/creature_layer.tscn at World/Ground/Play/Creatures): the view
## of the visitors in Game.sim (docs/ARCHITECTURE.md §5.4, GDD §4.1.3, Art Bible §5.7).
##
##  * Spawns a Mossling per visitor in sim.state.present, fades it in at its species' entry (or in
##    place when the world loads with it already here), and walks it out on departure.
##  * Plans behaviour bouts with the pure CreatureBrain (seeded per visit) and commands each
##    mossling: walk (hop / waddle) to the bout's spot, then nap / nibble / play / wander / sit.
##  * Touch: hit-tests mosslings first (hit priority, GDD §2.5), squash on touch-down, chirp (S13)
##    or snore (S14), name tag on tap, a second tap within 2 s emits [signal card_requested];
##    long-press 450 ms or a 24 px stroke pets (purr S03 while held, Game.pet on release).
##  * Creatures with their feet above the meadow crest draw from BehindCrest (added under
##    World/Ground before Meadow at runtime), so they rise into view over the hill.
##  * Reports nappers to Game for the audio snores (Game.report_sleepers).
##
## QA user args: --qa-creatures=<n> (a fixture of n mosslings in varied behaviours at their
## favourite spots), --qa-pet=<species> (that mossling is petted during the capture, hearts at
## ~3 s; add --qa-pet-hold to capture it mid-pet), --qa-walk (fixture creatures enter from their
## entries instead of starting in place).

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
const ARG_TOD := "--tod="
const ARG_WEATHER := "--weather="
const BEHIND_CREST := "BehindCrest"
const GROUND := "Ground"
## QA fixture: species, behaviour and spot, in the order --qa-creatures takes them (only spots
## that exist without décor, so a fresh install shows them).
const QA_FIXTURE: Array[Array] = [
	[&"puffmoss", &"nap", &"sun_stone"],
	[&"buttonbud", &"nibble", &"clover_bank"],
	[&"pebblepaw", &"sit_by_stream", &"stream_bend"],
	[&"honeyhum", &"play", &"moss_cushion"],
	[&"dandelfluff", &"play", &"hill_crest"],
	[&"primpip", &"nap", &"stump_hollow"],
	[&"bellkin", &"wander", &"willow_root"],
	[&"fernwhisk", &"nap", &"fern_shade"],
	[&"moonpuff", &"nap", &"moon_rock"],
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

var rig: MosslingRig
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
var _crest: PackedVector2Array = PackedVector2Array()
var _touch: Mossling = null
var _last_tap: Dictionary = {}           # species -> ticks s
var _qa_count: int = 0
var _qa_pet: StringName = &""
var _qa_walk: bool = false
var _qa_pet_hold: bool = false
var _qa_t: float = 0.0
var _qa_pet_state: int = 0
var _pinned_env: bool = false
var _rain: bool = false
var _sleepers: PackedStringArray = PackedStringArray()
var _frame: Vector2 = Vector2(1080, 1920)
var _obstacles: Array[Rect2] = []
var _feed := PaletteFeed.new()


func _ready() -> void:
	_content = ContentRegistry.content
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
		elif a.begins_with(ARG_TOD) or a.begins_with(ARG_WEATHER):
			_pinned_env = true
	Game.sim_event.connect(_on_sim_event)
	Game.world_ready.connect(_on_world_ready)
	Game.suspended.connect(_on_suspended)
	if Game.is_ready:
		# deferred: BehindCrest is added to Ground, which is still setting up its children now
		_on_world_ready.call_deferred([])


func _on_globals(_values: Dictionary) -> void:
	_feed.apply(TimeOfDay.colors)


func _exit_tree() -> void:
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
	if _qa_count > 0 or _qa_pet != &"":
		_qa_tick(delta)


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
	if _behind == null:
		return
	for m: Mossling in _all():
		var behind := m.feet().y < crest_y(m.feet().x) - CREST_MARGIN_PX
		var want: Node = _behind if behind else self
		if m.get_parent() != want:
			m.reparent(want, false)


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

func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		var p := _local(mb.position)
		if mb.pressed:
			var m := _hit(p)
			if m != null:
				_touch = m
				m.touch_down(p)
				get_viewport().set_input_as_handled()
		elif _touch != null:
			_touch.touch_up(p)
			_touch = null
			get_viewport().set_input_as_handled()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _touch != null:
		_touch.touch_move(_local(mm.position))
		get_viewport().set_input_as_handled()


func _local(screen: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen


## Front-most mossling under the point (largest feet y draws on top).
func _hit(p: Vector2) -> Mossling:
	var best: Mossling = null
	for m: Mossling in _all():
		if m.hit_test(p) and (best == null or m.feet().y > best.feet().y):
			best = m
	return best


func _on_touched(m: Mossling) -> void:
	# I1: the cue fires on touch-down, with the squash, in the same frame
	if m.asleep:
		AudioDirector.play_cue(&"S14", {"position": m.global_position})
	else:
		AudioDirector.play_cue(&"S13", {"voice_step": m.voice_step, "position": m.global_position})


func _on_tapped(m: Mossling) -> void:
	var tap: Dictionary = (_content.motion.get("creature", {}) as Dictionary).get("tap", {})
	var window_s := float(tap.get("second_tap_opens_card_ms", 2000.0)) * MS
	var now := Clock.ticks_s()
	var last := float(_last_tap.get(m.species_id, -INF))
	_last_tap[m.species_id] = now
	if now - last <= window_s:
		card_requested.emit(m.species_id)
		_last_tap.erase(m.species_id)
		return
	m.show_name(Game.display_name(m.species_id) if Game.is_ready else String(m.species_id))


func _on_petted(m: Mossling) -> void:
	if Game.is_ready and not _is_qa(m.species_id):
		Game.pet(m.species_id)
	mossling_petted.emit(m.species_id)


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
		var params := {"shelter": bout.shelter, "look": -0.6}
		if bout.behaviour == CreatureBrain.NIBBLE:
			params["lean_dir"] = 1.0
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
