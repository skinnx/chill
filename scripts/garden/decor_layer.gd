class_name DecorLayer
extends Node2D
## The six décor sets (scenes/garden/decor_layer.tscn at World/Ground/Play/Decor; GDD §2.5, §4.3,
## §14; Art Bible §6.6; docs/gdd/ACTIVE_DECOR.md): every placed copy stands where the Active F3 layout
## (Game.decor_layout(), frame-normalised foot positions) says, turned by its rot step, depth-scaled
## and y-sorted with props, beds and creatures, with a tinted contact shadow; all pieces are regions
## of one tone-mask atlas drawn with one prop_tone material ([DecorKit]). The wind chime is not
## movable (v1) and keeps its willow-branch anchors.
##
##  * leaf_pinwheel: spins with the wind, w = (0.3 + 0.9 g_wind (1 + 0.35 gust)) rev/s capped at
##    1.2; tap = spin burst to 2.5 rev/s decaying with tau 1.2 s, S19. Turn steps: front, 3/4
##    right (x squash 0.72), back (blades swapped), 3/4 left.
##  * pebble_cairn: stacks of 1-10 flat pebbles (offset +-4 px, tilt +-5 deg; a turn re-seeds them).
##  * toadstool_seat: a cluster of >= 3 (30 dp link) is a fairy ring: six glow motes join it at
##    dusk and night around its centroid.
##  * stream_stones: stepping stones in the brook; each registers a riffle with the BrookLayer.
##  * firefly_lantern: crook (faces left or right) + jar + glowing core (x g_lights), a breathing
##    head halo, a warm pool on the meadow (LampRegistry) and its brook reflection; the jar sways a
##    little; tap = +60 % over 200 ms, hold 2 s, back over 1.2 s, S20.
##  * wind_chime: ceramic tubes along the willow branch, each a pendulum on the follow spring
##    forced by wind and gusts; the branch tap (PropsLayer prop_tapped ring_chime) and the
##    AudioDirector's breeze gusts (S21) swing them.
## A newly placed piece fades in over 300 ms with a pop (0.6 -> 1), a 4-mote dust puff and S05.
## Touch-down on any piece: squash 0.94 + tint + S01 + the world TouchRing in the same frame; the
## action fires on release (pinwheel spin, lantern brighten, the still pieces' wobble) and reports
## Game.world_action(&"decor_tap", {set, piece}) for Active F1 wishes.
##
## Hit priority (WorldPan, ARCHITECTURE §3.5, GDD §14.4 D5): pinwheels and lanterns PRIO_DECOR (64 dp
## hit, 20 dp core); cairn stacks, toadstools and stones PRIO_STILL (60 dp hit, 20 dp core), so a
## still piece never outranks a mossling, prop, bed or a ready bed. Long-press 450 ms on any movable
## piece (the radial ring fill from 150 ms, Art Bible §4.18) claims the drag (WorldPan.claim_drag)
## and opens Active F3 edit mode with that piece already lifted ([DecorEdit]); a drag before that
## pans as on a bed.
##
## Draw budget (decor_placement.json draw): pinwheels keep one stamp each (they spin); the static
## pieces (stacks, toadstools, stones, lanterns) merge into one stamp per (set, 16 dp y band) for
## y-sort, and the nearest bands of a set merge when the décor total would pass 20
## ([method band_groups]). A pressed, popping or held piece draws on its own stamp until it settles.
## Children: [BasketFill], [LeafBoats] and the Active F3 [DecorEdit] controller.
##
## Touch strip (Director R3 #1): --qa-garden=<kind>:<ms> acts QA_TOUCH_AT_S after the world is ready
## and FREEZES the décor <ms> later (default --frames=90; ms <= 1500). Kinds: lantern (tap the
## first lantern: <ms> after the release, the +60 % brighten; try --tod=1.0 --fixture=night_lanterns),
## pinwheel (tap: the spin burst and dust puff), chime (the willow branch tap: tubes mid-swing),
## place (a new pinwheel pops in with its dust puff, as after buying it), hold (a long-press on the
## first toadstool: the ring fill at <ms> after touch-down). PlotsLayer handles bed, unfurl and
## ready; DecorEdit handles --qa-decor-edit.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const CUE_TOUCH := &"S01"
const CUE_PLACE := &"S05"
const CUE_PINWHEEL := &"S19"
const CUE_LANTERN := &"S20"
const CUE_CHIME := &"S21"
const PINWHEEL := &"leaf_pinwheel"
const CAIRN := &"pebble_cairn"
const TOADSTOOL := &"toadstool_seat"
const STONES := &"stream_stones"
const LANTERN := &"firefly_lantern"
const CHIME := &"wind_chime"
const CHIME_BRANCH := &"wind_chime_branch"
const RING_CHIME := &"ring_chime"
const DECOR_TAP := &"decor_tap"
const FREE_DECOR := &"free_decor"
## Art Bible §6.6 pinwheel: idle w = (0.3 + 0.9 g_wind (1 + 0.35 gust)) rev/s, cap 1.2; burst 2.5
## rev/s decaying with tau 1.2 s (below the 3.75 rev/s wagon-wheel limit of 4 blades at 30 fps).
const PW_BASE_REV := 0.3
const PW_WIND_REV := 0.9
const PW_GUST := 0.35
const PW_IDLE_CAP := 1.2
const PW_BURST_REV := 2.5
const PW_BURST_TAU := 1.2
## Gust envelope (palettes.json weather.gust: k 62, spacing 1742 px), mirrored on the CPU.
const GUST_K := 62.0
const GUST_SPACING := 1742.0
const LOOP_S := 600.0
## world_light.gdshaderinc gust_at (round 4): the gust front is diagonal and lags with depth.
const GUST_DEPTH_LAG := 0.9
const GUST_DEPTH_Y0 := 1150.0
## Art Bible §6.6 chimes: forced 2-6 deg by wind x gust; tap impulse 8 deg staggered 40 ms.
const CHIME_FORCE_DEG := Vector2(2.0, 6.0)
const CHIME_TAP_DEG := 8.0
const CHIME_GUST_DEG := 4.0
const CHIME_STAGGER_S := 0.04
const CHIME_OWN_CUE_S := 0.25
## Lantern jar sway (deg at full wind x gust) and brighten envelope (Art Bible §6.6).
const JAR_SWAY_DEG := 2.5
const LANTERN_BOOST := 0.6
const LANTERN_RISE_S := 0.2
const LANTERN_HOLD_S := 2.0
const LANTERN_FALL_S := 1.2
## Art Bible §8.3: lantern pools r 150 px; base pool intensity leaves room for the brighten.
## Round 5 (QA r4: five lanterns on the bank merged into one flat strip): the pools are a little
## tighter and brighter, so each lantern keeps its own warm island with a darker gap between.
const LANTERN_POOL_R := 122.0
const LANTERN_POOL_I := 0.8
const LANTERN_POOL_DY := -8.0
## Round 4 (QA r3 c7: the lantern tap was barely visible): at the top of the brighten the pool
## grows (round 5: 122 -> 160 px) and the glass halo blooms 1.35x, and the touch ring is warm and
## stronger.
const LANTERN_POOL_R_BOOST := 160.0
const LANTERN_HALO_POP := 0.5
## Touch ring alpha on décor (motion_tokens ui.ring is 0.35 on the busy meadow: too faint there).
const RING_ALPHA := 0.6
## Round 4 (hand-placed, not a fence): each lantern's crook is a little taller or shorter
## (deterministic per copy). Its x jitter is baked into the Active F3 layout by the migration.
const LANTERN_JITTER_PX := 10.0
const LANTERN_HEIGHT_JITTER := 0.07
const RING_WARM := Color(1.0, 0.86, 0.58)
## LampRegistry holds 12 lamps (mushrooms + boat candles share it): lanterns past this have no pool.
const MAX_LANTERN_POOLS := 8
## Halos (Art Bible §4.13): lantern head r0 18 px, quad 108 px; ring motes r0 6 px.
const LANTERN_HALO := Vector2(18.0, 108.0)
const LANTERN_HALO_ALPHA := 0.55
const MOTE_HALO := Vector2(6.0, 36.0)
const MOTE_ALPHA := 0.5
## The fairy-ring motes sit on an ellipse this much wider / taller than the cluster (design px),
## never smaller than the MVP ring's half size.
const MOTE_RING_PAD := Vector2(26.0, 12.0)
const MOTE_RING_MIN := Vector2(40.0, 18.0)
## Cairn jitter (Art Bible §6.6) and pebbles carrying moss (copies 2 and 6).
const CAIRN_JITTER_PX := 4.0
const CAIRN_TILT_DEG := 5.0
## Touch strip timeline (matches PlotsLayer): act this long after the world is ready, tap length.
const ARG_QA_GARDEN := "--qa-garden="
const QA_KINDS: Array[String] = ["lantern", "pinwheel", "chime", "place", "hold"]
const QA_TOUCH_AT_S := 1.2
const QA_TAP_S := 0.08
## Hit radii (GDD §8.4: >= 60 dp, 64 dp in the look zone) in dp. Round 7: only the CORE (the
## piece itself, radius 20 dp) outranks a plain bed it overlaps (WorldPan.tier). Still pieces read
## decor_placement.json hit.still_piece_hit_dp / still_piece_core_dp.
const HIT_DP := 64.0
const CORE_DP := 20.0
## Placement (Art Bible §6.6): 300 ms fade + pop 0.6 -> 1 + 4 dust motes. A taller cairn stack
## that gains a pebble pops less (the whole stack would look like it fell).
const PLACE_FROM_SCALE := 0.6
const STACK_FROM_SCALE := 0.9
const PUFF_MOTES := 4
const PUFF_RADIUS := 26.0
const PUFF_S := 0.5
## Depth scale (Art Bible §2.4).
const DEPTH := Vector3(0.62, 760.0, 740.0)
## Every additive décor glow (lantern heads, ring motes) shares one node drawn after the whole play
## layer (one halo_add batch instead of one per piece); below the 1920 frame bottom.
const GLOW_SORT_Y := 2000.0
## Contact shadows: [half_w, half_h, height] at depth 1 per set.
const SHADOWS := {
	&"leaf_pinwheel": Vector3(9.0, 3.0, 90.0), &"firefly_lantern": Vector3(13.0, 4.0, 150.0),
	&"toadstool_seat": Vector3(20.0, 5.5, 44.0), &"pebble_cairn": Vector3(30.0, 7.0, 40.0),
}
## Art Bible §4.18 long-press fill: radius 48 dp around the touch, 6 dp stroke, primary @ 0.9.
const RING_FILL_SHADER := "res://shaders/ui/ring_fill.gdshader"
const FILL_RADIUS_DP := 48.0
const FILL_STROKE_DP := 6.0
const FILL_ALPHA := 0.9
## Static sets that merge into y bands (one stamp per set and band).
const STATIC_SETS: Array[StringName] = [&"pebble_cairn", &"toadstool_seat", &"stream_stones", &"firefly_lantern"]
## A held piece (and the chime rail) always keeps a draw call of the décor budget free.
const HELD_RESERVE := 1

static var current: DecorLayer = null

var kit: DecorKit
var basket: BasketFill
var boats: LeafBoats
## Active F3 edit controller (a child; null when the feature is off).
var edit: DecorEdit

var _content: GameContent
var _pieces: Dictionary = {}           # decor id -> Array of Piece (copy order; cairn: one per stack)
var _by_id: Dictionary = {}            # unit id ("set#n", a cairn stack's base) -> Piece
## movable_pieces() is asked for on every frame of edit mode (the overlay draws a ring per piece)
## and it used to build and lambda-sort a fresh Array each time. The set only changes when a
## piece enters or leaves _by_id, so it is cached and rebuilt on demand (round 9).
var _movable: Array[Piece] = []
var _movable_dirty: bool = true
var _shadows: Node2D
var _chime_set: Node2D
var _motes: Node2D
var _glow: Node2D
var _units: Dictionary = {}           # unit key -> Unit (one y-sort unit = one stamp)
var _wind: float = 0.35
var _light: Dictionary = {}
var _dp: float = 3.0
var _set_scale: Dictionary = {}
var _press: Piece = null
var _press_pos := Vector2.ZERO
var _press_t: float = 0.0
var _press_canvas := Vector2.ZERO
var _long_fired: bool = false
var _fill: Node2D
var _fill_mat: ShaderMaterial
var _long_s: float = 0.45
var _fill_from_s: float = 0.15
var _band_px: float = 48.0
var _draw_max: int = 20
var _chime_own_s: float = -1.0
var _puffs: Array[Dictionary] = []
var _pop_s: float = 0.3
var _cairn_step := Vector2(0.0, -16.32)
var _qa_kind: String = ""
var _qa_ms: float = 0.0
var _qa_t: float = -1.0
var _qa_step: int = 0
var _qa_frozen: bool = false
var _qa_ring: TouchRing


class Piece:
	extends RefCounted
	## Layout id ("set#n"; a cairn stack is its base pebble's id).
	var id: String = ""
	var decor: StringName
	var index: int
	## Active F3 turn step and its render (decor_placement.json sets.*.rot_render).
	var rot: int = 0
	var flip: float = 1.0
	var squash_x: float = 1.0
	var variant: int = 0
	var seed: int = 0
	## Cairn: pebbles in the stack (ids bottom first).
	var pebbles: PackedStringArray = PackedStringArray()
	## The piece's own node (standalone pieces; a unit piece while pressed, popping in or held).
	var node: Node2D
	## The piece's own stamp (null once a unit piece is merged into its unit's stamp).
	var stamp: MeshInstance2D
	var unit: String = ""
	var merged: bool = false
	var head_pivot := Vector2.ZERO
	var foot := Vector2.ZERO
	var depth: float = 1.0
	var hit := Vector2.ZERO
	var angle: float = 0.0
	var burst_t: float = -1.0
	var pend: Spring
	var boost_t: float = -1.0
	var boost_k: float = 1.0
	var halo: HaloSprite
	var lamp: StringName = &""
	var press: Spring
	var tint: float = 0.0
	var appear_t: float = -1.0
	var pop: Spring
	var shadow: ContactShadow
	## Active F3: lifted by the edit controller (its node follows [method DecorLayer.pose]).
	var held: bool = false
	## Held out of the tray: not in the layout as placed yet (freed on unhold if still stored).
	var temp: bool = false


## A static group drawn as one stamp (a y band of a static set, or the chime rail).
class Unit:
	extends RefCounted
	var key: String
	var node: Node2D
	var stamp: MeshInstance2D
	## Quads in piece order (chime: copy order) or by foot y (bands).
	var by_y: bool = true


func _ready() -> void:
	current = self
	add_to_group(WorldPan.GROUP_HIT)
	_content = ContentRegistry.content
	kit = DecorKit.new(_content)
	_dp = float(_content.spots_doc["frame"]["px_per_dp"])
	_set_scale = kit.layout.get("set_scale", {})
	_pop_s = float(_content.motion["durations_ms"]["fade_in_min"]) / 1000.0
	var dp_doc := _content.decor_placement
	var em: Dictionary = dp_doc.get("edit_mode", {})
	_long_s = float(em.get("enter_long_press_ms", 450)) / 1000.0
	_fill_from_s = float(em.get("enter_long_press_fill_start_ms", 150)) / 1000.0
	var draw: Dictionary = dp_doc.get("draw", {})
	_band_px = float(draw.get("merge_band_dp", 16)) * _dp
	_draw_max = int(draw.get("decor_draw_calls_max", 20))
	var ca: Array = (_content.anchors_by_decor.get(CAIRN, {}) as Dictionary).get("positions", [])
	if ca.size() >= 2:
		var a0 := GardenRules.frame_to_px(_content, Vector2(float(ca[0][0]), float(ca[0][1])))
		var a1 := GardenRules.frame_to_px(_content, Vector2(float(ca[1][0]), float(ca[1][1])))
		_cairn_step = (a1 - a0) / depth_scale(a0.y)
	_shadows = Node2D.new()
	_shadows.name = "Shadows"
	_shadows.y_sort_enabled = false
	add_child(_shadows)
	_glow = Node2D.new()
	_glow.name = "Glow"
	_glow.position = Vector2(0.0, GLOW_SORT_Y)
	add_child(_glow)
	_chime_set = Node2D.new()
	_chime_set.name = "Chimes"
	_chime_set.position = Vector2(0.0, float(kit.layout.get("chime_sort_y", 806.0)))
	add_child(_chime_set)
	basket = BasketFill.new()
	basket.name = "BasketFill"
	add_child(basket)
	basket.setup(_content, kit)
	boats = LeafBoats.new()
	boats.name = "LeafBoats"
	add_child(boats)
	boats.setup(_content, kit)
	_build_fill()
	edit = DecorEdit.new()
	edit.name = "DecorEdit"
	add_child(edit)
	edit.setup(self)
	_light = _current_light()
	_wind = float(_light.get(&"g_wind", _wind))
	TimeOfDay.globals_updated.connect(_on_light)
	Game.sim_event.connect(_on_sim_event)
	Game.world_ready.connect(func(_recap: Array) -> void: _build_all())
	AudioDirector.cue_played.connect(_on_cue_played)
	tree_exiting.connect(_on_exit)
	_connect_branch.call_deferred()
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(ARG_QA_GARDEN):
			var kv := a.trim_prefix(ARG_QA_GARDEN).split(":")
			if QA_KINDS.has(kv[0]):
				_qa_kind = kv[0]
				_qa_ms = kv[1].to_float() if kv.size() > 1 else 0.0
				_qa_t = 0.0
	if Game.is_ready:
		_build_all()


func _on_exit() -> void:
	for list: Array in _pieces.values():
		for p: Piece in list:
			_release_world(p)
	kit.release()
	if current == self:
		current = null


func _connect_branch() -> void:
	var props := get_node_or_null("../../Props/PropsLayer")
	if props != null and props.has_signal(&"prop_tapped"):
		props.connect(&"prop_tapped", _on_prop_tapped)


static func depth_scale(y: float) -> float:
	return clampf(DEPTH.x + (1.0 - DEPTH.x) * (y - DEPTH.y) / DEPTH.z, DEPTH.x, 1.0)


static func gust_at(x: float, g_time: float) -> float:
	var ph := fposmod(g_time * GUST_K / LOOP_S - x / GUST_SPACING, 1.0)
	return smoothstep(0.0, 0.25, ph) * (1.0 - smoothstep(0.25, 0.6, ph))


## The same front at a design-px position (lags with depth like the shaders' gust_at).
static func gust_at_pos(p: Vector2, g_time: float) -> float:
	return gust_at(p.x - (p.y - GUST_DEPTH_Y0) * GUST_DEPTH_LAG, g_time)


## Idle pinwheel speed (rev/s) for a wind and gust value (Art Bible §6.6).
static func pinwheel_rev_s(wind: float, gust: float) -> float:
	return minf(PW_BASE_REV + PW_WIND_REV * wind * (1.0 + PW_GUST * gust), PW_IDLE_CAP)


## Draw-budget banding (decor_placement.json draw): [param bands_by_set] maps a set id to its
## sorted, distinct y-band indices; returns set id -> Array of groups (each an Array[int] of
## consecutive bands drawn as ONE stamp). While the total would pass [param budget], the set with
## the most groups merges its two nearest neighbouring groups (a few dp of y-sort imprecision).
static func band_groups(bands_by_set: Dictionary, budget: int) -> Dictionary:
	var out := {}
	var total := 0
	for s: Variant in bands_by_set:
		var groups: Array = []
		for b: Variant in bands_by_set[s]:
			groups.append([int(b)])
		out[s] = groups
		total += groups.size()
	while total > maxi(budget, bands_by_set.size()):
		var pick: Variant = null
		var most := 1
		for s: Variant in out:
			var n := (out[s] as Array).size()
			if n > most:
				most = n
				pick = s
		if pick == null:
			break
		var groups: Array = out[pick]
		var best_i := 0
		var best_gap := 1 << 30
		for i in groups.size() - 1:
			var gap := int((groups[i + 1] as Array)[0]) - int((groups[i] as Array).back())
			if gap < best_gap:
				best_gap = gap
				best_i = i
		(groups[best_i] as Array).append_array(groups[best_i + 1])
		groups.remove_at(best_i + 1)
		total -= 1
	return out


# ================================================================= build

func _count(id: StringName) -> int:
	return Game.sim.owned_count(id) if Game.sim != null else 0


func _build_all() -> void:
	if Game.sim == null:
		return
	_sync_layout(false)
	basket.refresh()


## Re-reads the layout (after an edit commit, an undo, a purchase); [method _sync_layout].
func refresh(animate_new: bool = false) -> void:
	_sync_layout(animate_new)


## The placed units of the Active F3 layout: unit id -> {set, index, x, y, rot, pebbles}.
func _layout_units() -> Dictionary:
	var out := {}
	if Game.sim == null:
		return out
	var cairn: Array[Dictionary] = []
	for rec: Dictionary in Game.decor_layout():
		if bool(rec.get("stored", false)):
			continue
		var set_id := StringName(String(rec["set"]))
		if set_id == CAIRN:
			cairn.append(rec)
			continue
		out[String(rec["id"])] = {"set": set_id, "index": _copy_index(String(rec["id"])), "x": float(rec["x"]),
			"y": float(rec["y"]), "rot": int(rec.get("rot", 0)), "pebbles": PackedStringArray([String(rec["id"])])}
	cairn.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("level", 0)) < int(b.get("level", 0)))
	for rec: Dictionary in cairn:
		var base := String(rec.get("stack", ""))
		if base == "":
			base = String(rec["id"])
		if not out.has(base):
			out[base] = {"set": CAIRN, "index": _copy_index(base), "x": float(rec["x"]), "y": float(rec["y"]),
				"rot": int(rec.get("rot", 0)), "pebbles": PackedStringArray()}
		var u: Dictionary = out[base]
		var pebbles: PackedStringArray = u["pebbles"]
		pebbles.append(String(rec["id"]))
		u["pebbles"] = pebbles  # a packed array is a value: write it back
		if String(rec["id"]) == base:
			u["x"] = float(rec["x"])
			u["y"] = float(rec["y"])
			u["rot"] = int(rec.get("rot", 0))
	return out


static func _copy_index(id: String) -> int:
	return int(id.get_slice(DecorPlacementRules.ID_SEP, 1))


## Brings the pieces in line with the layout: new units appear ([param animate]: the purchase pop),
## moved / turned / restacked ones are rebuilt in place, stored ones leave. Held pieces keep their
## node where the edit controller poses them.
func _sync_layout(animate: bool) -> void:
	if Game.sim == null:
		return
	var units := _layout_units()
	var changed := false
	for id: String in units:
		var u: Dictionary = units[id]
		var p: Piece = _by_id.get(id)
		var foot := GardenRules.frame_to_px(_content, Vector2(float(u["x"]), float(u["y"])))
		if p == null:
			p = _add_piece(StringName(u["set"]), int(u["index"]), foot, int(u["rot"]), u["pebbles"], id, animate)
			changed = true
			continue
		p.temp = false
		var pebbles: PackedStringArray = u["pebbles"]
		if p.foot.distance_to(foot) > 0.01 or p.rot != int(u["rot"]) or p.pebbles != pebbles:
			var grew := pebbles.size() > p.pebbles.size()
			_update_piece(p, foot, int(u["rot"]), pebbles)
			if grew and animate:
				_pop(p, STACK_FROM_SCALE)
			changed = true
	for id: String in _by_id.keys():
		var p: Piece = _by_id[id]
		if not units.has(id) and not p.held:
			_remove_piece(p)
			changed = true
	_sync_chimes(animate)
	if changed:
		_relayout_units()
	_refresh_ring()


func _sync_chimes(animate: bool) -> void:
	var list: Array = _pieces.get(CHIME, [])
	for i in range(list.size(), _count(CHIME)):
		_add_piece(CHIME, i, _anchor(CHIME, i), 0, PackedStringArray(), "%s#%d" % [CHIME, i], animate)


func _anchor(id: StringName, i: int) -> Vector2:
	var a: Dictionary = _content.anchors_by_decor.get(id, {})
	var pos: Array = a.get("positions", [])
	if pos.is_empty():
		return Vector2.ZERO
	var q: Array = pos[mini(i, pos.size() - 1)]
	return GardenRules.frame_to_px(_content, Vector2(float(q[0]), float(q[1])))


func _add_piece(id: StringName, i: int, foot: Vector2, rot: int, pebbles: PackedStringArray, uid: String,
		animate: bool) -> Piece:
	var p := Piece.new()
	p.id = uid
	p.decor = id
	p.index = i
	p.press = Motion.spring(&"press", 1.0)
	p.pop = Motion.spring(&"pop", 1.0)
	if id == CHIME:
		p.pend = Motion.spring(&"follow", 0.0)
	elif id == LANTERN:
		p.pend = Motion.spring(&"follow", 0.0)
	if id == PINWHEEL:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([String(PINWHEEL), p.index])
		p.angle = rng.randf() * TAU
	_place(p, foot, rot, pebbles)
	var list: Array = _pieces.get(id, [])
	list.append(p)
	list.sort_custom(func(a: Piece, b: Piece) -> bool: return a.index < b.index)
	_pieces[id] = list
	if id != CHIME:
		_by_id[uid] = p
		_movable_dirty = true
	if id == CHIME:
		p.unit = "chimes"
	elif _is_static(id):
		p.unit = "pending"
	if not _is_static(id) or animate:
		_make_own_stamp(p)
	elif id == CHIME:
		p.merged = true
		_rebuild_unit("chimes")
	else:
		p.merged = true
	_make_shadow(p)
	_attach_world(p)
	if animate:
		_pop(p, PLACE_FROM_SCALE)
	return p


func _is_static(id: StringName) -> bool:
	return id == CHIME or STATIC_SETS.has(id)


## Sets a piece's foot, turn and stack, and derives its depth, render and hit point.
func _place(p: Piece, foot: Vector2, rot: int, pebbles: PackedStringArray) -> void:
	p.foot = foot
	p.rot = rot
	p.pebbles = pebbles
	p.depth = depth_scale(foot.y) * float(_set_scale.get(String(p.decor), 1.0))
	if p.decor == LANTERN:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([String(LANTERN), p.index])
		rng.randf()  # the x jitter draw (now baked into the layout by the migration)
		p.depth *= 1.0 + rng.randf_range(-1.0, 1.0) * LANTERN_HEIGHT_JITTER
	var steps: Array = _content.placement_set(p.decor).get("rot_render", [])
	var r: Dictionary = steps[posmod(rot, steps.size())] if not steps.is_empty() else {}
	p.flip = -1.0 if bool(r.get("flip", false)) else 1.0
	p.squash_x = float(r.get("squash_x", 1.0))
	p.variant = int(r.get("variant", 0))
	p.seed = int(r.get("jitter_seed", 0))
	match p.decor:
		PINWHEEL:
			p.head_pivot = Vector2(0.0, float(kit.layout.get("pinwheel_head_dy", -86.0)) * p.depth)
			p.hit = p.foot + p.head_pivot
		LANTERN:
			var hook: Array = kit.layout.get("lantern_hook", [30, 28])
			p.head_pivot = kit.frame_point("lantern_crook", Vector2(float(hook[0]), float(hook[1]))) * p.depth
			p.head_pivot.x *= p.flip
			p.hit = _jar_centre(p)
		_:
			p.head_pivot = Vector2.ZERO
			p.hit = visual_centre_of(p)


func _jar_centre(p: Piece) -> Vector2:
	return p.foot + p.head_pivot + Vector2(0.0, float(kit.layout.get("jar_centre_dy", 28.0)) * p.depth)


## A moved, turned or restacked piece: new render, shadow, pool and riffle (its node is rebuilt
## unless the edit controller holds it).
func _update_piece(p: Piece, foot: Vector2, rot: int, pebbles: PackedStringArray) -> void:
	var was_held := p.held
	_place(p, foot, rot, pebbles)
	if p.shadow != null:
		p.shadow.queue_free()
		p.shadow = null
	_make_shadow(p)
	_attach_world(p)
	if p.node != null:
		var pos := p.node.position
		var sc := p.node.scale
		var rotation_now := p.node.rotation
		var a := p.node.modulate.a
		var z := p.node.z_index
		p.node.queue_free()
		p.node = null
		p.stamp = null
		_make_own_stamp(p)
		if was_held:
			p.node.position = pos
			p.node.scale = sc
			p.node.rotation = rotation_now
			p.node.modulate.a = a
			p.node.z_index = z


func _remove_piece(p: Piece) -> void:
	_release_world(p)
	if p.node != null:
		p.node.queue_free()
		p.node = null
	if p.shadow != null:
		p.shadow.queue_free()
		p.shadow = null
	if p.halo != null:
		p.halo.queue_free()
		p.halo = null
	if _press == p:
		_press = null
		_hide_fill()
	_by_id.erase(p.id)
	_movable_dirty = true
	var list: Array = _pieces.get(p.decor, [])
	list.erase(p)


func _make_shadow(p: Piece) -> void:
	if not SHADOWS.has(p.decor):
		return
	var s: Vector3 = SHADOWS[p.decor]
	p.shadow = ContactShadow.new(Vector2(s.x, s.y) * p.depth, s.z * p.depth, 1.0)
	p.shadow.position = p.foot
	_shadows.add_child(p.shadow)
	p.shadow.set_light(_light)


## Pools, halos and riffles that live outside the stamp (LampRegistry, the glow node, BrookLayer).
func _attach_world(p: Piece) -> void:
	match p.decor:
		LANTERN:
			var lk: Dictionary = _content.motion["loops_k"]
			if p.halo == null:
				p.halo = HaloSprite.new().setup(LANTERN_HALO.x * p.depth, LANTERN_HALO.y * p.depth,
						Color(1, 1, 1, LANTERN_HALO_ALPHA), float((lk["lantern_breath"] as Array)[0]),
						HaloSprite.FLAG_NIGHT + HaloSprite.FLAG_ACCENT, float(p.index) * 1.7)
				_glow.add_child(p.halo)
			p.halo.position = _jar_centre(p) - _glow.position
			if p.index < MAX_LANTERN_POOLS:
				p.lamp = StringName("lantern_%d" % p.index)
				LampRegistry.set_lamp(p.lamp, Vector2(p.foot.x + p.head_pivot.x, p.foot.y + LANTERN_POOL_DY),
						LANTERN_POOL_R, LANTERN_POOL_I)
		STONES:
			if BrookLayer.current != null:
				BrookLayer.current.set_stone(_stone_key(p), p.foot, kit.size_of("stream_stone").x * 0.5 * p.depth)


func _release_world(p: Piece) -> void:
	if p.lamp != &"":
		LampRegistry.remove_lamp(p.lamp)
		p.lamp = &""
	if p.decor == STONES and BrookLayer.current != null:
		BrookLayer.current.remove_stone(_stone_key(p))


func _stone_key(p: Piece) -> StringName:
	return StringName("decor_stone_%d" % p.index)


## The piece's own node + stamp: standalone pieces always, unit pieces while they pop in, are
## pressed or held (then they merge into their band's stamp).
func _make_own_stamp(p: Piece) -> void:
	var q := DecorKit.Quads.new()
	_piece_quads(p, q, p.foot)
	p.stamp = kit.stamp(q)
	p.stamp.name = "Stamp"
	p.node = Node2D.new()
	p.node.position = p.foot
	p.node.add_child(p.stamp)
	add_child(p.node)
	p.node.name = p.id.replace(DecorPlacementRules.ID_SEP, "_")
	_apply_node_scale(p, 1.0)
	if p.decor == PINWHEEL:
		DecorKit.set_stamp_head(p.stamp, p.head_pivot, p.angle)


## Pinwheels turn by scaling their own node (the 3/4 view squashes the spinning head, flips mirror).
func _apply_node_scale(p: Piece, s: float) -> void:
	if p.node == null:
		return
	if p.decor == PINWHEEL:
		p.node.scale = Vector2(s * p.squash_x * p.flip, s)
	else:
		p.node.scale = Vector2.ONE * s


## Appends the quads of piece [param p] to [param q], in px relative to [param origin].
func _piece_quads(p: Piece, q: DecorKit.Quads, origin: Vector2) -> void:
	var o := p.foot - origin
	var d := p.depth
	var f := p.flip
	match p.decor:
		PINWHEEL:
			var blades := PackedStringArray(["pinwheel_a", "pinwheel_b"])
			if p.variant == 1:
				blades.reverse()  # the back face: blade colours swapped
			kit.add_quad(q, "pinwheel_stick", o, d)
			for b: String in blades:
				kit.add_quad(q, b, o + p.head_pivot, d, 0.0, "", -1.0, DecorKit.GROUP_HEAD)
		LANTERN:
			var mats: Dictionary = _content.palettes["materials"]
			var em := float((mats["lantern_light"] as Dictionary).get("night_emission", 0.85))
			kit.add_quad(q, "lantern_crook", o, d, 0.0, "", -1.0, DecorKit.GROUP_STATIC, f)
			var g := DecorKit.GROUP_TUBE + mini(p.index, DecorKit.MAX_TUBES - 1)
			kit.add_quad(q, "lantern_core", o + p.head_pivot + Vector2(0.0, float(kit.layout.get("lantern_core_dy", 14.0)) * d),
					d, 0.0, "", em, g, f)
			kit.add_quad(q, "lantern_jar", o + p.head_pivot, d, 0.0, "", -1.0, g, f)
		CHIME:
			var parts: Array = kit.layout.get("chime_parts", ["chime_mid"])
			kit.add_quad(q, String(parts[p.index % parts.size()]), o, d, 0.0, "", -1.0,
					DecorKit.GROUP_TUBE + mini(p.index, DecorKit.MAX_TUBES - 1))
		CAIRN:
			var cparts: Array = kit.layout.get("cairn_parts", ["pebble_0"])
			var first := p.id == DecorPlacementRules.piece_id(CAIRN, 0) and p.seed == 0
			for lvl in p.pebbles.size():
				var rng := RandomNumberGenerator.new()
				rng.seed = hash([String(CAIRN), lvl]) if first else hash([String(CAIRN), p.id, lvl, p.seed])
				var part := String(cparts[mini(lvl, cparts.size() - 1)])
				var shrink := 1.0 - 0.05 * float(maxi(0, lvl - cparts.size() + 1))
				var jx := rng.randf_range(-1.0, 1.0) * CAIRN_JITTER_PX
				var tilt := deg_to_rad(rng.randf_range(-1.0, 1.0) * CAIRN_TILT_DEG)
				var off := o + _cairn_step * depth_scale(p.foot.y) * float(lvl) + Vector2(jx * f, 0.0)
				kit.add_quad(q, part, off, d * shrink, tilt * f, "", -1.0, DecorKit.GROUP_STATIC, f)
		TOADSTOOL:
			kit.add_quad(q, "toadstool_stem", o, d, 0.0, "", -1.0, DecorKit.GROUP_STATIC, f)
			kit.add_quad(q, "toadstool_cap", o + Vector2(0.0, float(kit.layout.get("toadstool_cap_dy", -20.0)) * d), d,
					0.0, "", -1.0, DecorKit.GROUP_STATIC, f)
		STONES:
			kit.add_quad(q, "stream_stone", o, d, 0.0, "", -1.0, DecorKit.GROUP_STATIC, f)


## The piece's visual centre (design px): its foot moved up by visual_centre_dy_dp (a cairn by
## half its stack too). Edit-mode hits and the still pieces' play hits sit here.
func visual_centre_of(p: Piece) -> Vector2:
	var dy := float(_content.placement_set(p.decor).get("visual_centre_dy_dp", 0.0)) * _dp
	var c := p.foot + Vector2(0.0, dy)
	if p.decor == CAIRN and p.pebbles.size() > 1:
		c += _cairn_step * depth_scale(p.foot.y) * float(p.pebbles.size() - 1) * 0.5
	return c


## The top of the piece (design px): where the selection chip and the dust puff go.
func top_of(p: Piece) -> Vector2:
	if p.head_pivot != Vector2.ZERO:
		return p.foot + p.head_pivot + Vector2(0.0, -PUFF_RADIUS * p.depth)
	if p.decor == CAIRN:
		return p.foot + _cairn_step * depth_scale(p.foot.y) * float(maxi(p.pebbles.size(), 1)) \
				+ Vector2(0.0, -PUFF_RADIUS * p.depth)
	return p.foot + Vector2(0.0, -PUFF_RADIUS * 1.6 * p.depth)


## Static pieces regroup into (set, y band) stamps under the draw budget ([method band_groups]).
func _relayout_units() -> void:
	var bands := {}
	var members := {}
	var pinwheels := 0
	for p: Piece in _by_id.values():
		if p.decor == PINWHEEL:
			pinwheels += 1
		if not STATIC_SETS.has(p.decor):
			continue
		var b := floori(p.foot.y / _band_px)
		var list: Array = bands.get(p.decor, [])
		if not list.has(b):
			list.append(b)
		bands[p.decor] = list
	for s: Variant in bands:
		(bands[s] as Array).sort()
	var chime := 1 if _count(CHIME) > 0 else 0
	var groups := band_groups(bands, _draw_max - pinwheels - chime - HELD_RESERVE)
	var key_of := {}
	for s: Variant in groups:
		for g: Array in groups[s]:
			var key := "%s|%d" % [s, int(g[0])]
			for b: Variant in g:
				key_of["%s|%d" % [s, int(b)]] = key
	for p: Piece in _by_id.values():
		if STATIC_SETS.has(p.decor):
			p.unit = String(key_of.get("%s|%d" % [p.decor, floori(p.foot.y / _band_px)], ""))
			members[p.unit] = true
	for key: String in _units.keys():
		if key != "chimes" and not members.has(key):
			var u: Unit = _units[key]
			u.node.queue_free()
			_units.erase(key)
	for key: String in members:
		_rebuild_unit(key)


func _unit(key: String) -> Unit:
	var u: Unit = _units.get(key)
	if u != null:
		return u
	u = Unit.new()
	u.key = key
	if key == "chimes":
		u.node = _chime_set
		u.by_y = false
	else:
		u.node = Node2D.new()
		u.node.name = key.replace("|", "_")
		add_child(u.node)
	u.stamp = kit.stamp()
	u.stamp.name = "Stamp"
	u.node.add_child(u.stamp)
	_units[key] = u
	return u


## Rebuilds a unit's stamp from its merged pieces; a band sorts at its front-most foot.
func _rebuild_unit(key: String) -> void:
	if key == "" or key == "pending":
		return
	var u := _unit(key)
	var members: Array[Piece] = []
	var all: Array = _by_id.values() if key != "chimes" else _pieces.get(CHIME, [])
	var front := -INF
	for p: Piece in all:
		if p.unit == key:
			front = maxf(front, p.foot.y)
			if p.merged:
				members.append(p)
	if key != "chimes" and front > -INF:
		u.node.position = Vector2(0.0, front)
	if u.by_y:
		members.sort_custom(func(a: Piece, b: Piece) -> bool: return a.foot.y < b.foot.y)
	else:
		members.sort_custom(func(a: Piece, b: Piece) -> bool: return a.index < b.index)
	var q := DecorKit.Quads.new()
	for p: Piece in members:
		_piece_quads(p, q, u.node.position)
	u.stamp.mesh = DecorKit.build_mesh(q)


## A unit piece that finished popping in (or was released) joins its band's stamp.
func _merge(p: Piece) -> void:
	if p.unit == "" or p.merged or p.held:
		return
	if p.unit == "pending":
		_relayout_units()
	p.merged = true
	if p.node != null:
		p.node.queue_free()
	p.node = null
	p.stamp = null
	_rebuild_unit(p.unit)


## The fairy rings: glow motes around every cluster of >= ring.forms_at toadstools (30 dp link).
func _refresh_ring() -> void:
	var rings: Array[Rect2] = []
	if Game.sim != null:
		var ring: Dictionary = _content.placement_set(TOADSTOOL).get("ring", {})
		var layout := Game.sim.state.decor_layout
		for cl: Array in Game.decor_rules().clusters(layout, TOADSTOOL):
			if cl.size() < int(ring.get("forms_at", 3)):
				continue
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for rec: Variant in cl:
				var r: Dictionary = rec
				var px := GardenRules.frame_to_px(_content, Vector2(float(r["x"]), float(r["y"])))
				lo = lo.min(px)
				hi = hi.max(px)
			rings.append(Rect2(lo, hi - lo))
	if _motes != null:
		_motes.queue_free()
		_motes = null
	if rings.is_empty():
		return
	_motes = Node2D.new()
	_motes.name = "RingMotes"
	_glow.add_child(_motes)
	var n := int((_content.placement_set(TOADSTOOL).get("ring", {}) as Dictionary).get("glow_motes", 6))
	var k := float((_content.motion["loops_k"]["glow_mushroom"] as Array)[0])
	var cap_dy := float(kit.layout.get("toadstool_cap_dy", -20.0))
	for rr: Rect2 in rings:
		var centre := rr.get_center() + Vector2(0.0, cap_dy * 0.5) - _glow.position
		var rad := (rr.size * 0.5 + MOTE_RING_PAD).max(MOTE_RING_MIN)
		for i in n:
			var a := TAU * (float(i) + 0.5) / float(n)
			var h := HaloSprite.new().setup(MOTE_HALO.x, MOTE_HALO.y, Color(1, 1, 1, MOTE_ALPHA), k,
					HaloSprite.FLAG_NIGHT + HaloSprite.FLAG_ACCENT, float(i) * 1.3)
			h.position = centre + Vector2(cos(a) * rad.x, sin(a) * rad.y)
			_motes.add_child(h)


func _piece_top(p: Piece) -> Vector2:
	if p.head_pivot != Vector2.ZERO:
		return p.foot + p.head_pivot
	return p.foot + Vector2(0.0, -PUFF_RADIUS * p.depth)


func _pop(p: Piece, from: float) -> void:
	if p.node == null:
		_detach(p)
	p.appear_t = 0.0
	p.pop = Motion.spring(&"pop", from)
	p.pop.target = 1.0
	if from <= PLACE_FROM_SCALE:
		p.node.modulate.a = 0.0
	_puff(_piece_top(p))
	AudioDirector.play_cue(CUE_PLACE, {"world": true, "position": _canvas_of(p.foot)})
	FrameGovernor.hold_for(Motion.duration(&"emphasized"))


# ================================================================= sim binding

func _on_sim_event(ev: Dictionary) -> void:
	var type := StringName(ev["type"])
	var catch_up := bool(ev.get("catch_up", false))
	match type:
		WorldSim.EV_PLACED:
			_sync_layout(not catch_up)
		WorldSim.EV_DECOR_PLACED, WorldSim.EV_DECOR_STORED, WorldSim.EV_DECOR_UNDONE:
			_sync_layout(false)
		WorldSim.EV_BOAT:
			if not catch_up:
				boats.launch()


func _on_light(values: Dictionary) -> void:
	_light = values.duplicate()
	_wind = float(values.get(&"g_wind", _wind))
	for s: Node in _shadows.get_children():
		(s as ContactShadow).set_light(values)


func _current_light() -> Dictionary:
	var v := TimeOfDay.evaluate(Clock.now_local())
	v[&"g_world_offset"] = TimeOfDay.world_offset
	return v


func _on_cue_played(id: StringName, _caption: StringName, _pos: Vector2) -> void:
	if id != CUE_CHIME:
		return
	if _chime_own_s >= 0.0:
		return  # our own tap already swung them
	_kick_chimes(CHIME_GUST_DEG)


func _on_prop_tapped(prop_id: StringName, action: StringName, _pos: Vector2) -> void:
	if prop_id != CHIME_BRANCH or action != RING_CHIME or _count(CHIME) == 0:
		return
	_chime_own_s = 0.0
	AudioDirector.play_cue(CUE_CHIME, {"shells": _count(CHIME), "position": _canvas_of(_anchor(CHIME, 0))})
	_kick_chimes(CHIME_TAP_DEG)


func _kick_chimes(deg: float) -> void:
	var list: Array = _pieces.get(CHIME, [])
	for i in list.size():
		var p: Piece = list[i]
		var dir := 1.0 if i % 2 == 0 else -1.0
		var dv := deg_to_rad(deg) * dir * TAU * p.pend.frequency_hz
		get_tree().create_timer(CHIME_STAGGER_S * float(i)).timeout.connect(func() -> void: p.pend.kick(dv))
	FrameGovernor.hold_for(2.0)


# ================================================================= frame

func _process(delta: float) -> void:
	if _qa_frozen:
		return
	if _qa_kind != "":
		_step_qa(delta)
		if _qa_frozen:
			return
	var gt := Clock.g_time
	var motion := 0.3 if Motion.reduce_motion else 1.0
	if _chime_own_s >= 0.0:
		_chime_own_s += delta
		if _chime_own_s > CHIME_OWN_CUE_S:
			_chime_own_s = -1.0
	for p: Piece in _pieces.get(PINWHEEL, []):
		var rev := pinwheel_rev_s(_wind, gust_at_pos(p.hit, gt)) * motion
		if p.burst_t >= 0.0:
			p.burst_t += delta
			rev = maxf(rev, PW_BURST_REV * exp(-p.burst_t / PW_BURST_TAU))
			if p.burst_t > PW_BURST_TAU * 5.0:
				p.burst_t = -1.0
		p.angle = fposmod(p.angle + rev * TAU * delta, TAU)
		if p.stamp != null:
			DecorKit.set_stamp_head(p.stamp, p.head_pivot, p.angle)
	var force := deg_to_rad(lerpf(CHIME_FORCE_DEG.x, CHIME_FORCE_DEG.y, clampf(_wind, 0.0, 1.0))) * motion
	var chimes: Unit = _units.get("chimes")
	for p: Piece in _pieces.get(CHIME, []):
		p.pend.target = force * (0.35 + 0.65 * gust_at_pos(p.foot, gt))
		p.angle = p.pend.step(delta)
		_swing(p, chimes)
	for p: Piece in _pieces.get(LANTERN, []):
		p.pend.target = deg_to_rad(JAR_SWAY_DEG) * _wind * gust_at_pos(p.foot, gt) * motion
		p.angle = p.pend.step(delta)
		_swing(p, _units.get(p.unit))
		if p.boost_t >= 0.0:
			_step_boost(p, delta)
	for list: Array in _pieces.values():
		for p: Piece in list:
			_step_piece(p, delta)
	_step_long_press(delta)
	_step_puffs(delta)


func _step_piece(p: Piece, delta: float) -> void:
	if p.appear_t >= 0.0:
		p.appear_t += delta
		var s := p.pop.step(delta)
		if p.node != null:
			p.node.modulate.a = maxf(p.node.modulate.a, clampf(p.appear_t / _pop_s, 0.0, 1.0))
			_apply_node_scale(p, s)
		if p.appear_t >= _pop_s and p.pop.is_at_rest():
			p.appear_t = -1.0
			if p.node != null and not p.held:
				_apply_node_scale(p, 1.0)
				p.node.modulate.a = 1.0
	if not p.press.is_at_rest() or p.press.target < 1.0 or p.tint > 0.0 or p.boost_t >= 0.0:
		var v := p.press.step(delta)
		p.tint = maxf(0.0, p.tint - delta / Motion.duration(&"short"))
		if p.stamp != null:
			DecorKit.set_stamp_fx(p.stamp, p.tint, v, p.boost_k)
	elif p.unit != "" and not p.merged and p.appear_t < 0.0 and _press != p and not p.held:
		_merge(p)  # popped in / touched / set down and settled: back into the band's single stamp


## Swings a GROUP_TUBE piece (chime tube, lantern jar) in whichever stamp holds it.
func _swing(p: Piece, u: Unit) -> void:
	var pivot := p.head_pivot
	if p.merged and u != null:
		DecorKit.set_stamp_tube(u.stamp, p.index, p.foot + pivot - u.node.position, p.angle)
	elif p.stamp != null:
		DecorKit.set_stamp_tube(p.stamp, p.index, pivot, p.angle)


## A touched unit piece leaves the band's stamp for its own while it squashes, glows or is held.
func _detach(p: Piece) -> void:
	if p.node != null:
		return
	p.merged = false
	_make_own_stamp(p)
	_rebuild_unit(p.unit)


func _step_boost(p: Piece, delta: float) -> void:
	p.boost_t += delta
	var t := p.boost_t
	var e := 0.0
	if t < LANTERN_RISE_S:
		e = t / LANTERN_RISE_S
	elif t < LANTERN_RISE_S + LANTERN_HOLD_S:
		e = 1.0
	elif t < LANTERN_RISE_S + LANTERN_HOLD_S + LANTERN_FALL_S:
		e = 1.0 - (t - LANTERN_RISE_S - LANTERN_HOLD_S) / LANTERN_FALL_S
	else:
		p.boost_t = -1.0
	var se := smoothstep(0.0, 1.0, e)
	var k := 1.0 + LANTERN_BOOST * se
	var c: Color = p.halo.get_instance_shader_parameter(&"i_color")
	c.a = LANTERN_HALO_ALPHA * k
	p.halo.set_instance_shader_parameter(&"i_color", c)
	p.halo.scale = Vector2.ONE * (1.0 + LANTERN_HALO_POP * se)
	p.boost_k = k
	if p.stamp != null:
		DecorKit.set_stamp_fx(p.stamp, p.tint, p.press.value, k)
	if p.lamp != &"":
		LampRegistry.set_lamp(p.lamp, Vector2(p.foot.x + p.head_pivot.x, p.foot.y + LANTERN_POOL_DY),
				lerpf(LANTERN_POOL_R, LANTERN_POOL_R_BOOST, se), LANTERN_POOL_I * k)


func _puff(at: Vector2) -> void:
	var dots: Array[Sprite2D] = []
	for i in PUFF_MOTES:
		var sp := kit.sprite("dust_dot", depth_scale(at.y))
		sp.position = at
		sp.z_index = 1
		add_child(sp)
		dots.append(sp)
	_puffs.append({"t": 0.0, "at": at, "dots": dots})


## A settle's dust puff at [param at] (design px), for the edit controller.
func puff(at: Vector2) -> void:
	_puff(at)


func _step_puffs(delta: float) -> void:
	for i in range(_puffs.size() - 1, -1, -1):
		var pf: Dictionary = _puffs[i]
		var t := float(pf["t"]) + delta
		pf["t"] = t
		var u := clampf(t / PUFF_S, 0.0, 1.0)
		var dots: Array = pf["dots"]
		for j in dots.size():
			var sp: Sprite2D = dots[j]
			var a := PI + PI * (float(j) + 0.5) / float(dots.size())
			sp.position = (pf["at"] as Vector2) + Vector2.from_angle(a) * PUFF_RADIUS * (0.3 + 0.7 * sin(u * PI * 0.5))
			sp.modulate.a = 1.0 - u
		if u >= 1.0:
			for sp2: Sprite2D in dots:
				sp2.queue_free()
			_puffs.remove_at(i)


func _canvas_of(design: Vector2) -> Vector2:
	# canvas (world) px: the caption host applies the camera (map pan) itself
	return get_global_transform() * design


# ================================================================= Active F3 edit hooks

## The placed (or held) unit by id; a cairn pebble id resolves to its stack.
func piece(id: String) -> Piece:
	var p: Piece = _by_id.get(id)
	if p != null:
		return p
	for q: Piece in _by_id.values():
		if q.pebbles.has(id):
			return q
	return null


## Every movable unit drawn now (edit targets): Array of Piece.
func movable_pieces() -> Array[Piece]:
	if _movable_dirty:
		_movable_dirty = false
		_movable.clear()
		for p: Piece in _by_id.values():
			if not p.temp:
				_movable.append(p)
		_movable.sort_custom(func(a: Piece, b: Piece) -> bool: return a.id < b.id)
	return _movable


## Lifts unit [param id] out of its band onto its own stamp (z 1, above the friends) so the edit
## controller can pose it. A stored piece ([param stored_set] given) is built as a temporary piece
## from the tray. False if there is no such piece.
func hold(id: String, stored_set: StringName = &"", at: Vector2 = Vector2.ZERO) -> bool:
	var p := piece(id)
	if p == null and stored_set != &"":
		p = _add_piece(stored_set, _copy_index(id), at, 0, PackedStringArray([id]), id, false)
		p.temp = true
		_relayout_units()
	if p == null:
		return false
	if _press == p:
		_end_press(false)
	p.held = true
	if p.decor == STONES and BrookLayer.current != null:
		BrookLayer.current.remove_stone(_stone_key(p))  # the riffle waits for the stone's new place
	_detach(p)
	p.node.z_index = 1
	return true


## Poses a held piece: foot at [param foot] (design px), raised [param rise_px], scaled
## [param scale_k] (x the depth change since it was built), faded to [param alpha], leaning
## [param lean] rad about its foot. Its shadow stays on the ground and grows with [param lift].
func pose(id: String, foot: Vector2, rise_px: float, scale_k: float, alpha: float, lean: float, lift: float) -> void:
	var p := piece(id)
	if p == null or p.node == null:
		return
	var depth_k := depth_scale(foot.y) / maxf(depth_scale(p.foot.y), 0.01)
	p.node.position = foot + Vector2(0.0, -rise_px)
	_apply_node_scale(p, scale_k * depth_k)
	p.node.rotation = lean
	p.node.modulate.a = alpha
	if p.shadow != null:
		p.shadow.position = foot
		p.shadow.scale = Vector2.ONE * (1.0 + 0.25 * lift) * depth_k
		p.shadow.modulate.a = 1.0 - 0.3 * lift
	if p.decor == LANTERN:
		var jar := p.node.position + (p.head_pivot + Vector2(0.0, float(kit.layout.get("jar_centre_dy", 28.0)) * p.depth)) \
				* scale_k * depth_k
		if p.halo != null:
			p.halo.position = jar - _glow.position
		if p.lamp != &"":
			LampRegistry.set_lamp(p.lamp, Vector2(jar.x, foot.y + LANTERN_POOL_DY), LANTERN_POOL_R, LANTERN_POOL_I)


## Sets a held piece down: it re-reads its place from the layout (the commit, or its old spot)
## and rejoins its band once its springs rest. A temporary tray piece that stayed stored leaves.
func unhold(id: String) -> void:
	var p := piece(id)
	if p == null:
		return
	p.held = false
	if p.node != null:
		p.node.z_index = 0
		p.node.rotation = 0.0
		p.node.modulate.a = 1.0
		p.node.position = p.foot
		_apply_node_scale(p, 1.0)
	if p.shadow != null:
		p.shadow.position = p.foot
		p.shadow.scale = Vector2.ONE
		p.shadow.modulate.a = 1.0
	_attach_world(p)
	_sync_layout(false)


## The piece's stamp at its layout spot at alpha [param alpha]: where Undo and a float home go
## (the origin ghost while it is carried). The caller frees it.
func make_ghost(id: String, alpha: float = -1.0) -> Node2D:
	var p := piece(id)
	if p == null:
		return null
	var q := DecorKit.Quads.new()
	_piece_quads(p, q, p.foot)
	var n := Node2D.new()
	n.name = "Ghost"
	n.position = p.foot
	n.add_child(kit.stamp(q))
	if p.decor == PINWHEEL:
		n.scale = Vector2(p.squash_x * p.flip, 1.0)
		DecorKit.set_stamp_head(n.get_child(0) as MeshInstance2D, p.head_pivot, p.angle)
	var a := alpha if alpha >= 0.0 else float((_content.decor_placement.get("edit_mode", {}) as Dictionary).get(
			"origin_ghost_alpha", 0.22))
	n.modulate.a = a
	add_child(n)
	return n


## A piece taken out of the tray pops out (S35 is the caller's): fade + pop + dust puff.
func pop_in(id: String) -> void:
	var p := piece(id)
	if p != null:
		_pop(p, PLACE_FROM_SCALE)


## The world touch ring at [param at] (design px): a soft "nothing here" on an edit-mode ground tap.
func ring(at: Vector2) -> void:
	_ring(at)


## The design-px foot of a unit as the layout has it (Vector2.INF if none).
func foot_of(id: String) -> Vector2:
	var p := piece(id)
	return p.foot if p != null else Vector2.INF


## Design px -> canvas px (input space) and back.
func to_canvas(design: Vector2) -> Vector2:
	return get_global_transform_with_canvas() * design


func to_design(canvas: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * canvas


func px_per_dp() -> float:
	return _dp


# ================================================================= touch

## WorldPan (the world input arbiter, ARCHITECTURE §3.5): the nearest piece within its hit
## (+ slop): pinwheels and lanterns PRIO_DECOR (64 dp, 20 dp core), the still pieces PRIO_STILL
## (60 dp, 20 dp core). Beds with a ready bud, props, mosslings and beds outrank them.
func world_hit(canvas_pos: Vector2, slop: float) -> Dictionary:
	var pos := get_global_transform_with_canvas().affine_inverse() * canvas_pos
	var best := {}
	var hit: Dictionary = _content.decor_placement.get("hit", {})
	var r := HIT_DP * _dp * 0.5
	var still_r := float(hit.get("still_piece_hit_dp", 60)) * _dp * 0.5
	var still_core := float(hit.get("still_piece_core_dp", CORE_DP)) * _dp
	var still_prio := int(hit.get("prio_still_piece_play", WorldPan.PRIO_STILL))
	for p: Piece in _by_id.values():
		if p.held or p.temp:
			continue
		var tappable := p.decor == PINWHEEL or p.decor == LANTERN
		var cand := WorldPan.circle_hit(pos, p.hit, r if tappable else still_r, slop,
				WorldPan.PRIO_DECOR if tappable else still_prio, p)
		if cand.is_empty():
			continue
		# the generous ring is for empty ground; only the piece itself outranks a bed
		cand["core"] = float(cand["d"]) <= (CORE_DP * _dp if tappable else still_core)
		if best.is_empty() or WorldPan.better(cand, best):
			best = cand
	return best


func world_press(key: Variant, canvas_pos: Vector2) -> void:
	var p := key as Piece
	if p == null:
		return
	if _press != null:
		_end_press(false)
	_press_canvas = canvas_pos
	_touch_down(p, get_global_transform_with_canvas().affine_inverse() * canvas_pos)


## After the long-press claimed the drag, the finger carries the piece (the edit controller).
func world_drag(key: Variant, canvas_pos: Vector2) -> void:
	var p := key as Piece
	if p != null and _long_fired and edit != null:
		edit.world_drag(p.id, canvas_pos)


func world_release(key: Variant, canvas_pos: Vector2, act: bool) -> void:
	var p := key as Piece
	if p != null and _long_fired and edit != null:
		_long_fired = false
		edit.world_release(p.id, canvas_pos, act)
		return
	if _press != null and _press == key:
		_end_press(act)


## Debug overlay (--debug-hits): the pieces' hit circles in canvas px.
func world_hit_shapes() -> Array:
	var out: Array = []
	var xf := get_global_transform_with_canvas()
	var k := xf.get_scale().x
	var hit: Dictionary = _content.decor_placement.get("hit", {})
	for p: Piece in _by_id.values():
		var tappable := p.decor == PINWHEEL or p.decor == LANTERN
		var r := (HIT_DP if tappable else float(hit.get("still_piece_hit_dp", 60))) * _dp * 0.5 * k
		var core := (CORE_DP if tappable else float(hit.get("still_piece_core_dp", CORE_DP))) * _dp * k
		out.append({"kind": "circle", "c": xf * p.hit, "r": r, "core": core,
			"prio": WorldPan.PRIO_DECOR if tappable else WorldPan.PRIO_STILL, "name": String(p.decor)})
	return out


## Touch-down on a piece: squash 0.94 + tint + touch ring + S01 (with its haptic) at once; the
## long-press clock starts.
func _touch_down(p: Piece, pos: Vector2) -> void:
	_detach(p)
	_press = p
	_press_pos = pos
	_press_t = 0.0
	_long_fired = false
	p.press = Motion.spring(&"press", p.press.value)
	p.press.target = float(_content.motion["ui"]["world_touch_squash"])
	p.tint = 1.0
	_ring(pos, p.decor == LANTERN)
	AudioDirector.play_cue(CUE_TOUCH, {"world": true, "position": _canvas_of(p.hit)})
	FrameGovernor.hold_for(Motion.duration(&"short"))
	set_process(true)


func _ring(pos: Vector2, warm: bool = false) -> void:
	_qa_ring = TouchRing.spawn(self, pos)
	_qa_ring.z_index = 1
	var v: Vector4 = _qa_ring.get_instance_shader_parameter(&"i_ring")
	v.z = RING_ALPHA
	_qa_ring.set_instance_shader_parameter(&"i_ring", v)
	if warm:
		_qa_ring.set_instance_shader_parameter(&"i_tint", RING_WARM)


func _end_press(act: bool) -> void:
	var p := _press
	_press = null
	_hide_fill()
	var pop := Motion.spring(&"pop", p.press.value)
	pop.velocity = p.press.velocity
	pop.target = 1.0
	p.press = pop
	if not act:
		return
	if p.decor == PINWHEEL:
		p.burst_t = 0.0
		AudioDirector.play_cue(CUE_PINWHEEL, {"position": _canvas_of(p.hit)})
		_puff(p.hit)
		FrameGovernor.hold_for(PW_BURST_TAU * 3.0)
	elif p.decor == LANTERN:
		p.boost_t = 0.0
		AudioDirector.play_cue(CUE_LANTERN, {"position": _canvas_of(p.hit)})
		FrameGovernor.hold_for(LANTERN_RISE_S + LANTERN_HOLD_S + LANTERN_FALL_S)
	# Active F3 still pieces (cairn, toadstool, stone): the wobble is the squash springing back on pop
	if Game.sim != null:
		Game.world_action(DECOR_TAP, {"set": p.decor, "piece": p.id})


func _build_fill() -> void:
	_fill = Node2D.new()
	_fill.name = "LongPressFill"
	_fill.z_index = 2
	_fill.visible = false
	_fill_mat = ShaderMaterial.new()
	_fill_mat.shader = load(RING_FILL_SHADER) as Shader
	var size := FILL_RADIUS_DP * 2.0 * _dp
	_fill_mat.set_shader_parameter(&"u_size", Vector2(size, size))
	_fill_mat.set_shader_parameter(&"u_stroke", FILL_STROKE_DP * _dp)
	_fill_mat.set_shader_parameter(&"u_color", Color(UiTokens.color(&"primary"), FILL_ALPHA))
	_fill_mat.set_shader_parameter(&"u_track", Color(UiTokens.color(&"surface_hi"), 0.0))
	_fill.material = _fill_mat
	_fill.draw.connect(func() -> void: _fill.draw_rect(Rect2(Vector2.ZERO, Vector2(size, size)), Color.WHITE))
	add_child(_fill)


func _hide_fill() -> void:
	if _fill != null:
		_fill.visible = false


## The long-press: ring fill from 150 ms, at 450 ms the drag is claimed and edit mode opens with
## the piece lifted under the finger (ACTIVE_DECOR §2).
func _step_long_press(delta: float) -> void:
	if _press == null or _long_fired or _qa_frozen:
		return
	_press_t += delta
	if not Game.feature_on(FREE_DECOR) or not _content.is_movable_decor(_press.decor):
		return
	var u := (_press_t - _fill_from_s) / maxf(_long_s - _fill_from_s, 0.001)
	if u > 0.0:
		var size := FILL_RADIUS_DP * 2.0 * _dp
		_fill.position = _press_pos - Vector2(size, size) * 0.5
		_fill.visible = true
		_fill_mat.set_shader_parameter(&"u_progress", clampf(u, 0.0, 1.0))
		FrameGovernor.poke()
	if _press_t >= _long_s:
		_fire_long_press()


func _fire_long_press() -> void:
	var p := _press
	var pan := WorldPan.current
	if pan != null and pan.target() == self and not pan.claim_drag():
		return
	_long_fired = pan != null and pan.target() == self
	_press = null
	_hide_fill()
	p.press = Motion.spring(&"pop", p.press.value)
	p.press.target = 1.0
	if edit != null:
		edit.begin_from_long_press(p.id, _press_canvas, _long_fired)


## Number of placed copies of a décor set (tests, QA; a cairn counts its pebbles).
func piece_count(id: StringName) -> int:
	var n := 0
	for p: Piece in _pieces.get(id, []):
		if not p.temp:
			n += maxi(p.pebbles.size(), 1)
	return n


# ================================================================= QA touch strip

## --qa-garden timeline: act at QA_TOUCH_AT_S (taps release QA_TAP_S later), freeze <ms> after the
## release (lantern, pinwheel), the touch-down (hold) or the action (chime, place).
func _step_qa(delta: float) -> void:
	if _qa_t < 0.0 or not Game.is_ready:
		return
	_qa_t += delta
	var act_at := QA_TOUCH_AT_S
	var tap := _qa_kind == "lantern" or _qa_kind == "pinwheel"
	if _qa_step == 0 and _qa_t >= act_at:
		_qa_step = 1
		match _qa_kind:
			"lantern", "pinwheel", "hold":
				var set_id := LANTERN if _qa_kind == "lantern" else (PINWHEEL if _qa_kind == "pinwheel" else TOADSTOOL)
				var list: Array = _pieces.get(set_id, [])
				if list.is_empty():
					push_warning("--qa-garden=%s: no such décor placed (use --fixture=garden_mid)" % _qa_kind)
					_qa_kind = ""
					return
				var first: Piece = list[0]
				_touch_down(first, first.hit)
			"chime":
				_ring(_anchor(CHIME, 0))
				_on_prop_tapped(CHIME_BRANCH, RING_CHIME, Vector2.ZERO)
			"place":
				var n := piece_count(PINWHEEL)
				_add_piece(PINWHEEL, n, _anchor(PINWHEEL, n), 0, PackedStringArray(), "qa#%d" % n, true)
	if tap and _qa_step == 1 and _qa_t >= act_at + QA_TAP_S:
		_qa_step = 2
		_end_press(true)
	var freeze_at := act_at + (QA_TAP_S if tap else 0.0) + _qa_ms / 1000.0
	if _qa_step >= 1 and _qa_t >= freeze_at:
		if _qa_kind == "hold":
			_step_long_press(0.0)
		_qa_frozen = true
		if is_instance_valid(_qa_ring):
			_qa_ring.freeze_at(minf(_qa_t - act_at, _qa_ring.duration_s * 0.9))
