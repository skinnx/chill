class_name DecorLayer
extends Node2D
## The six décor sets (scenes/garden/decor_layer.tscn at World/Ground/Play/Decor; GDD §2.5, §4.3,
## Art Bible §6.6): every owned copy stands at the next spots.json décor anchor, depth-scaled and
## y-sorted with props, beds and creatures, with a tinted contact shadow; all pieces are regions
## of one tone-mask atlas drawn with one prop_tone material ([DecorKit]).
##
##  * leaf_pinwheel: spins with the wind, w = (0.3 + 0.9 g_wind (1 + 0.35 gust)) rev/s capped at
##    1.2; tap = spin burst to 2.5 rev/s decaying with tau 1.2 s, S19.
##  * pebble_cairn: one flat pebble more per copy (offset +-4 px, tilt +-5 deg, moss on 2 and 6).
##  * toadstool_seat: the ring around the toadstool_ring spot; with >= 3 at dusk/night six glow
##    motes join the caps.
##  * stream_stones: stepping stones in the brook; each registers a riffle with the BrookLayer.
##  * firefly_lantern: crook + jar + glowing core (x g_lights), a breathing head halo, a 150 px
##    warm pool on the meadow (LampRegistry) and its brook reflection; the jar sways a little;
##    tap = +60 % over 200 ms, hold 2 s, back over 1.2 s, S20.
##  * wind_chime: ceramic tubes along the willow branch, each a pendulum on the follow spring
##    forced by wind and gusts; the branch tap (PropsLayer prop_tapped ring_chime) and the
##    AudioDirector's breeze gusts (S21) swing them.
## A newly placed piece fades in over 300 ms with a pop (0.6 -> 1), a 4-mote dust puff and S05.
## Touch-down on a tappable piece: squash 0.94 + tint + S01 in the same frame; the action fires on
## release. Children: [BasketFill] (gifts and dew in the basket) and [LeafBoats] (the brook ritual).
## Every piece is a décor stamp (DecorKit, shaders/flora/decor_stamp.gdshader): one MeshInstance2D
## per pinwheel / lantern, one per static group (cairn, ring halves, stones, the chime tubes).
## Touch-down also spawns the world TouchRing (bloom + eased ring + sparkles) at the piece.
##
## Touch strip (Director R3 #1): --qa-garden=<kind>:<ms> acts QA_TOUCH_AT_S after the world is ready
## and FREEZES the décor <ms> later (default --frames=90; ms <= 1500). Kinds: lantern (tap the
## first lantern: <ms> after the release, the +60 % brighten; try --tod=1.0 --fixture=night_lanterns),
## pinwheel (tap: the spin burst and dust puff), chime (the willow branch tap: tubes mid-swing),
## place (a new pinwheel pops in with its dust puff, as after buying it). PlotsLayer handles bed,
## unfurl and ready.

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
## Round 4 (hand-placed, not a fence): each lantern on the bank path stands a little off its anchor
## and its crook is a little taller or shorter (deterministic per copy).
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
const RING_MIN := 3
## Cairn jitter (Art Bible §6.6) and pebbles carrying moss (copies 2 and 6).
const CAIRN_JITTER_PX := 4.0
const CAIRN_TILT_DEG := 5.0
## Touch strip timeline (matches PlotsLayer): act this long after the world is ready, tap length.
const ARG_QA_GARDEN := "--qa-garden="
const QA_KINDS: Array[String] = ["lantern", "pinwheel", "chime", "place"]
const QA_TOUCH_AT_S := 1.2
const QA_TAP_S := 0.08
## Hit radii (GDD §8.4: >= 60 dp, 64 dp in the look zone) in dp. Round 7: only the CORE (the
## piece itself, radius 20 dp) outranks a plain bed it overlaps (WorldPan.tier).
const HIT_DP := 64.0
const CORE_DP := 20.0
## Placement (Art Bible §6.6): 300 ms fade + pop 0.6 -> 1 + 4 dust motes.
const PLACE_FROM_SCALE := 0.6
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

static var current: DecorLayer = null

var kit: DecorKit
var basket: BasketFill
var boats: LeafBoats

var _content: GameContent
var _pieces: Dictionary = {}           # decor id -> Array of Piece
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
var _chime_own_s: float = -1.0
var _puffs: Array[Dictionary] = []
var _pop_s: float = 0.3
var _qa_kind: String = ""
var _qa_ms: float = 0.0
var _qa_t: float = -1.0
var _qa_step: int = 0
var _qa_frozen: bool = false
var _qa_ring: TouchRing


class Piece:
	extends RefCounted
	var decor: StringName
	var index: int
	## The piece's own node (standalone pieces; a unit piece only while it pops in).
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


## A static group drawn as one stamp (the cairn, each half of the toadstool ring, the stones).
class Unit:
	extends RefCounted
	var key: String
	var node: Node2D
	var stamp: MeshInstance2D
	## Quads in piece order (cairn: stacking order) or by foot y (ring halves, stones).
	var by_y: bool = true


func _ready() -> void:
	current = self
	add_to_group(WorldPan.GROUP_HIT)
	_content = ContentRegistry.content
	kit = DecorKit.new(_content)
	_dp = float(_content.spots_doc["frame"]["px_per_dp"])
	_set_scale = kit.layout.get("set_scale", {})
	_pop_s = float(_content.motion["durations_ms"]["fade_in_min"]) / 1000.0
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
			if p.lamp != &"":
				LampRegistry.remove_lamp(p.lamp)
	if BrookLayer.current != null:
		for i in _count(STONES):
			BrookLayer.current.remove_stone(_stone_key(i))
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


# ================================================================= build

func _count(id: StringName) -> int:
	return Game.sim.owned_count(id) if Game.sim != null else 0


func _build_all() -> void:
	if Game.sim == null:
		return
	for d: Dictionary in _content.decor:
		var id := StringName(d["id"])
		var n := _count(id)
		var list: Array = _pieces.get(id, [])
		for i in range(list.size(), n):
			_add_piece(id, i, false)
	_refresh_ring()
	basket.refresh()


func _anchor(id: StringName, i: int) -> Vector2:
	var a: Dictionary = _content.anchors_by_decor.get(id, {})
	var pos: Array = a.get("positions", [])
	if pos.is_empty():
		return Vector2.ZERO
	var q: Array = pos[mini(i, pos.size() - 1)]
	return GardenRules.frame_to_px(_content, Vector2(float(q[0]), float(q[1])))


func _add_piece(id: StringName, i: int, animate: bool) -> Piece:
	var p := Piece.new()
	p.decor = id
	p.index = i
	p.foot = _anchor(id, i)
	p.depth = depth_scale(p.foot.y) * float(_set_scale.get(String(id), 1.0))
	if id == LANTERN:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([String(LANTERN), i])
		p.foot.x += rng.randf_range(-1.0, 1.0) * LANTERN_JITTER_PX
		p.depth *= 1.0 + rng.randf_range(-1.0, 1.0) * LANTERN_HEIGHT_JITTER
	p.press = Motion.spring(&"press", 1.0)
	p.pop = Motion.spring(&"pop", 1.0)
	p.unit = _unit_key(p)
	match id:
		PINWHEEL:
			_setup_pinwheel(p)
		LANTERN:
			_setup_lantern(p)
		CHIME:
			p.pend = Motion.spring(&"follow", 0.0)
			p.hit = p.foot
		STONES:
			p.hit = p.foot
			if BrookLayer.current != null:
				BrookLayer.current.set_stone(_stone_key(p.index), p.foot, kit.size_of("stream_stone").x * 0.5 * p.depth)
		_:
			p.hit = p.foot
	var list: Array = _pieces.get(id, [])
	list.append(p)
	_pieces[id] = list
	if p.unit == "" or animate:
		_make_own_stamp(p)
	else:
		p.merged = true
		_rebuild_unit(p.unit)
	if SHADOWS.has(id) and (id != CAIRN or i == 0):
		var s: Vector3 = SHADOWS[id]
		p.shadow = ContactShadow.new(Vector2(s.x, s.y) * p.depth, s.z * p.depth, 1.0)
		p.shadow.position = p.foot
		_shadows.add_child(p.shadow)
		p.shadow.set_light(_light)
	if animate:
		p.appear_t = 0.0
		p.pop = Motion.spring(&"pop", PLACE_FROM_SCALE)
		p.pop.target = 1.0
		p.node.modulate.a = 0.0
		_puff(_piece_top(p))
		AudioDirector.play_cue(CUE_PLACE, {"world": true, "position": _canvas_of(p.foot)})
		FrameGovernor.hold_for(Motion.duration(&"emphasized"))
	return p


## The piece's own node + stamp: standalone pieces always, unit pieces while they pop in (then
## they merge into the unit's stamp).
func _make_own_stamp(p: Piece) -> void:
	var q := DecorKit.Quads.new()
	_piece_quads(p, q, p.foot)
	p.stamp = kit.stamp(q)
	p.stamp.name = "Stamp"
	p.node = Node2D.new()
	p.node.position = p.foot
	p.node.add_child(p.stamp)
	add_child(p.node)
	p.node.name = "%s_%d" % [p.decor, p.index]
	if p.decor == PINWHEEL:
		DecorKit.set_stamp_head(p.stamp, p.head_pivot, p.angle)


## Appends the quads of piece [param p] to [param q], in px relative to [param origin].
func _piece_quads(p: Piece, q: DecorKit.Quads, origin: Vector2) -> void:
	var o := p.foot - origin
	var d := p.depth
	match p.decor:
		PINWHEEL:
			kit.add_quad(q, "pinwheel_stick", o, d)
			kit.add_quad(q, "pinwheel_a", o + p.head_pivot, d, 0.0, "", -1.0, DecorKit.GROUP_HEAD)
			kit.add_quad(q, "pinwheel_b", o + p.head_pivot, d, 0.0, "", -1.0, DecorKit.GROUP_HEAD)
		LANTERN:
			var mats: Dictionary = _content.palettes["materials"]
			var em := float((mats["lantern_light"] as Dictionary).get("night_emission", 0.85))
			kit.add_quad(q, "lantern_crook", o, d)
			var g := DecorKit.GROUP_TUBE + mini(p.index, DecorKit.MAX_TUBES - 1)
			kit.add_quad(q, "lantern_core", o + p.head_pivot + Vector2(0.0, float(kit.layout.get("lantern_core_dy", 14.0)) * d),
					d, 0.0, "", em, g)
			kit.add_quad(q, "lantern_jar", o + p.head_pivot, d, 0.0, "", -1.0, g)
		CHIME:
			var parts: Array = kit.layout.get("chime_parts", ["chime_mid"])
			kit.add_quad(q, String(parts[p.index % parts.size()]), o, d, 0.0, "", -1.0,
					DecorKit.GROUP_TUBE + mini(p.index, DecorKit.MAX_TUBES - 1))
		CAIRN:
			var cparts: Array = kit.layout.get("cairn_parts", ["pebble_0"])
			var base: Piece = (_pieces.get(CAIRN, []) as Array)[0]
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([String(CAIRN), p.index])
			var part := String(cparts[mini(p.index, cparts.size() - 1)])
			var shrink := 1.0 - 0.05 * float(maxi(0, p.index - cparts.size() + 1))
			var off := base.foot - origin + (p.foot - base.foot) + Vector2(rng.randf_range(-1.0, 1.0) * CAIRN_JITTER_PX, 0.0)
			kit.add_quad(q, part, off, base.depth * shrink, deg_to_rad(rng.randf_range(-1.0, 1.0) * CAIRN_TILT_DEG))
		TOADSTOOL:
			kit.add_quad(q, "toadstool_stem", o, d)
			kit.add_quad(q, "toadstool_cap", o + Vector2(0.0, float(kit.layout.get("toadstool_cap_dy", -20.0)) * d), d)
		STONES:
			kit.add_quad(q, "stream_stone", o, d)


func _setup_pinwheel(p: Piece) -> void:
	p.head_pivot = Vector2(0.0, float(kit.layout.get("pinwheel_head_dy", -86.0)) * p.depth)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(PINWHEEL), p.index])
	p.angle = rng.randf() * TAU
	p.hit = p.foot + p.head_pivot


func _setup_lantern(p: Piece) -> void:
	var hook: Array = kit.layout.get("lantern_hook", [30, 28])
	p.head_pivot = kit.frame_point("lantern_crook", Vector2(float(hook[0]), float(hook[1]))) * p.depth
	var lk: Dictionary = _content.motion["loops_k"]
	p.halo = HaloSprite.new().setup(LANTERN_HALO.x * p.depth, LANTERN_HALO.y * p.depth,
			Color(1, 1, 1, LANTERN_HALO_ALPHA), float((lk["lantern_breath"] as Array)[0]),
			HaloSprite.FLAG_NIGHT + HaloSprite.FLAG_ACCENT, float(p.index) * 1.7)
	var jar_centre := p.foot + p.head_pivot + Vector2(0.0, float(kit.layout.get("jar_centre_dy", 28.0)) * p.depth)
	p.halo.position = jar_centre - _glow.position
	_glow.add_child(p.halo)
	p.pend = Motion.spring(&"follow", 0.0)
	p.hit = jar_centre
	if p.index < MAX_LANTERN_POOLS:
		p.lamp = StringName("lantern_%d" % p.index)
		LampRegistry.set_lamp(p.lamp, Vector2(p.foot.x + p.head_pivot.x, p.foot.y + LANTERN_POOL_DY),
				LANTERN_POOL_R, LANTERN_POOL_I)


## Stepping stones (in the water, no one stands behind them), the cairn, the chime tubes (each
## swings on its own about its hanging point, in the shader) and each half of the toadstool ring
## (back half behind a mossling sitting in the ring, front half in front of it) are single sort
## units drawn as ONE stamp each (synthesis §3 <= 100 draw calls).
func _unit_key(p: Piece) -> String:
	match p.decor:
		CHIME:
			return "chimes"
		LANTERN:
			return "lanterns"
		STONES:
			return "stones"
		CAIRN:
			return "cairn"
		TOADSTOOL:
			return "toadstools_back" if p.foot.y < _ring_centre().y else "toadstools_front"
	return ""


func _ring_centre() -> Vector2:
	var ring: Dictionary = kit.layout.get("toadstool_ring", {})
	var c: Array = ring.get("centre", [345.6, 825.6])
	return Vector2(float(c[0]), float(c[1]))


func _unit(key: String) -> Unit:
	var u: Unit = _units.get(key)
	if u != null:
		return u
	u = Unit.new()
	u.key = key
	var sort_y := 0.0
	match key:
		"stones":
			sort_y = _max_anchor_y(STONES)
		"cairn":
			sort_y = _anchor(CAIRN, 0).y
			u.by_y = false
		"lanterns":
			sort_y = _max_anchor_y(LANTERN)
		"toadstools_back":
			sort_y = _ring_centre().y - 1.0
		_:
			sort_y = _max_anchor_y(TOADSTOOL)
	if key == "chimes":
		u.node = _chime_set
	else:
		u.node = Node2D.new()
		u.node.name = key
		u.node.position = Vector2(_anchor(CAIRN, 0).x if key == "cairn" else 0.0, sort_y)
		add_child(u.node)
	u.stamp = kit.stamp()
	u.stamp.name = "Stamp"
	u.node.add_child(u.stamp)
	_units[key] = u
	return u


## Rebuilds a unit's stamp from its merged pieces.
func _rebuild_unit(key: String) -> void:
	var u := _unit(key)
	var members: Array[Piece] = []
	for list: Array in _pieces.values():
		for p: Piece in list:
			if p.unit == key and p.merged:
				members.append(p)
	if u.by_y:
		members.sort_custom(func(a: Piece, b: Piece) -> bool: return a.foot.y < b.foot.y)
	else:
		members.sort_custom(func(a: Piece, b: Piece) -> bool: return a.index < b.index)
	var q := DecorKit.Quads.new()
	for p: Piece in members:
		_piece_quads(p, q, u.node.position)
	u.stamp.mesh = DecorKit.build_mesh(q)


## A unit piece that finished popping in joins its unit's stamp.
func _merge(p: Piece) -> void:
	if p.unit == "" or p.merged:
		return
	p.merged = true
	if p.node != null:
		p.node.queue_free()
	p.node = null
	p.stamp = null
	_rebuild_unit(p.unit)


func _max_anchor_y(id: StringName) -> float:
	var a: Dictionary = _content.anchors_by_decor.get(id, {})
	var y := 0.0
	for q: Array in a.get("positions", []):
		y = maxf(y, GardenRules.frame_to_px(_content, Vector2(float(q[0]), float(q[1]))).y)
	return y


func _stone_key(i: int) -> StringName:
	return StringName("decor_stone_%d" % i)


func _refresh_ring() -> void:
	var on := _count(TOADSTOOL) >= RING_MIN
	if on and _motes == null:
		var ring: Dictionary = kit.layout.get("toadstool_ring", {})
		var c: Array = ring.get("centre", [345.6, 825.6])
		var r: Array = ring.get("radii", [72.0, 34.0])
		var n := int(ring.get("motes", 6))
		var centre := Vector2(float(c[0]), float(c[1]))
		_motes = Node2D.new()
		_motes.name = "RingMotes"
		_motes.position = centre - _glow.position
		_glow.add_child(_motes)
		var k := float((_content.motion["loops_k"]["glow_mushroom"] as Array)[0])
		for i in n:
			var a := TAU * (float(i) + 0.5) / float(n)
			var h := HaloSprite.new().setup(MOTE_HALO.x, MOTE_HALO.y, Color(1, 1, 1, MOTE_ALPHA), k,
					HaloSprite.FLAG_NIGHT + HaloSprite.FLAG_ACCENT, float(i) * 1.3)
			h.position = Vector2(cos(a) * float(r[0]), sin(a) * float(r[1]))
			_motes.add_child(h)
	elif not on and _motes != null:
		_motes.queue_free()
		_motes = null


func _piece_top(p: Piece) -> Vector2:
	if p.head_pivot != Vector2.ZERO:
		return p.foot + p.head_pivot
	return p.foot + Vector2(0.0, -PUFF_RADIUS * p.depth)


# ================================================================= sim binding

func _on_sim_event(ev: Dictionary) -> void:
	var type := StringName(ev["type"])
	if type == WorldSim.EV_PLACED:
		var id := StringName(ev["decor"])
		var list: Array = _pieces.get(id, [])
		var catch_up := bool(ev.get("catch_up", false))
		for i in range(list.size(), _count(id)):
			_add_piece(id, i, not catch_up)
		_refresh_ring()
	elif type == WorldSim.EV_BOAT and not bool(ev.get("catch_up", false)):
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
	var lanterns: Unit = _units.get("lanterns")
	for p: Piece in _pieces.get(CHIME, []):
		p.pend.target = force * (0.35 + 0.65 * gust_at_pos(p.foot, gt))
		p.angle = p.pend.step(delta)
		_swing(p, chimes)
	for p: Piece in _pieces.get(LANTERN, []):
		p.pend.target = deg_to_rad(JAR_SWAY_DEG) * _wind * gust_at_pos(p.foot, gt) * motion
		p.angle = p.pend.step(delta)
		_swing(p, lanterns)
		if p.boost_t >= 0.0:
			_step_boost(p, delta)
	for list: Array in _pieces.values():
		for p: Piece in list:
			_step_piece(p, delta)
	_step_puffs(delta)


func _step_piece(p: Piece, delta: float) -> void:
	if p.appear_t >= 0.0:
		p.appear_t += delta
		var s := p.pop.step(delta)
		if p.node != null:
			p.node.modulate.a = clampf(p.appear_t / _pop_s, 0.0, 1.0)
			p.node.scale = Vector2.ONE * s
		if p.appear_t >= _pop_s and p.pop.is_at_rest():
			p.appear_t = -1.0
			if p.node != null:
				p.node.scale = Vector2.ONE
				p.node.modulate.a = 1.0
	if not p.press.is_at_rest() or p.press.target < 1.0 or p.tint > 0.0 or p.boost_t >= 0.0:
		var v := p.press.step(delta)
		p.tint = maxf(0.0, p.tint - delta / Motion.duration(&"short"))
		if p.stamp != null:
			DecorKit.set_stamp_fx(p.stamp, p.tint, v, p.boost_k)
	elif p.unit != "" and not p.merged and p.appear_t < 0.0 and _press != p:
		_merge(p)  # popped in / touched and settled: back into the unit's single stamp


## Swings a GROUP_TUBE piece (chime tube, lantern jar) in whichever stamp holds it.
func _swing(p: Piece, u: Unit) -> void:
	var pivot := p.head_pivot
	if p.merged and u != null:
		DecorKit.set_stamp_tube(u.stamp, p.index, p.foot + pivot - u.node.position, p.angle)
	elif p.stamp != null:
		DecorKit.set_stamp_tube(p.stamp, p.index, pivot, p.angle)


## A touched unit piece leaves the unit's stamp for its own while it squashes and glows.
func _detach(p: Piece) -> void:
	if p.unit == "" or not p.merged:
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


# ================================================================= touch

## WorldPan (the world input arbiter, ARCHITECTURE §3.5): the nearest tappable piece (pinwheel,
## lantern) within its 64 dp hit (+ slop). Beds with a ready bud and props outrank décor.
func world_hit(canvas_pos: Vector2, slop: float) -> Dictionary:
	var pos := get_global_transform_with_canvas().affine_inverse() * canvas_pos
	var best := {}
	var r := HIT_DP * _dp * 0.5
	for id: StringName in [PINWHEEL, LANTERN]:
		for p: Piece in _pieces.get(id, []):
			var cand := WorldPan.circle_hit(pos, p.hit, r, slop, WorldPan.PRIO_DECOR, p)
			if cand.is_empty():
				continue
			# the generous 64 dp ring is for empty ground; only the piece itself outranks a bed
			cand["core"] = float(cand["d"]) <= CORE_DP * _dp
			if best.is_empty() or WorldPan.better(cand, best):
				best = cand
	return best


func world_press(key: Variant, canvas_pos: Vector2) -> void:
	var p := key as Piece
	if p == null:
		return
	if _press != null:
		_end_press(false)
	_touch_down(p, get_global_transform_with_canvas().affine_inverse() * canvas_pos)


func world_release(key: Variant, _canvas_pos: Vector2, act: bool) -> void:
	if _press != null and _press == key:
		_end_press(act)


## Debug overlay (--debug-hits): the tappable pieces' hit circles in canvas px.
func world_hit_shapes() -> Array:
	var out: Array = []
	var xf := get_global_transform_with_canvas()
	var r := HIT_DP * _dp * 0.5 * xf.get_scale().x
	for id: StringName in [PINWHEEL, LANTERN]:
		for p: Piece in _pieces.get(id, []):
			out.append({"kind": "circle", "c": xf * p.hit, "r": r, "core": CORE_DP * _dp * xf.get_scale().x,
				"prio": WorldPan.PRIO_DECOR, "name": String(id)})
	return out


## Touch-down on a tappable piece: squash 0.94 + tint + touch ring + S01 (with its haptic) at once.
func _touch_down(p: Piece, pos: Vector2) -> void:
	_detach(p)
	_press = p
	_press_pos = pos
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


## Number of pieces built for a décor set (tests, QA).
func piece_count(id: StringName) -> int:
	return (_pieces.get(id, []) as Array).size()


# ================================================================= QA touch strip

## --qa-garden timeline: act at QA_TOUCH_AT_S (taps release QA_TAP_S later), freeze <ms> after the
## release (lantern, pinwheel) or the action (chime, place).
func _step_qa(delta: float) -> void:
	if _qa_t < 0.0 or not Game.is_ready:
		return
	_qa_t += delta
	var act_at := QA_TOUCH_AT_S
	var tap := _qa_kind == "lantern" or _qa_kind == "pinwheel"
	if _qa_step == 0 and _qa_t >= act_at:
		_qa_step = 1
		match _qa_kind:
			"lantern", "pinwheel":
				var list: Array = _pieces.get(LANTERN if _qa_kind == "lantern" else PINWHEEL, [])
				if list.is_empty():
					push_warning("--qa-garden=%s: no such décor placed (use --fixture=garden_mid)" % _qa_kind)
					_qa_kind = ""
					return
				_touch_down(list[0], (list[0] as Piece).hit)
			"chime":
				_ring(_anchor(CHIME, 0))
				_on_prop_tapped(CHIME_BRANCH, RING_CHIME, Vector2.ZERO)
			"place":
				_add_piece(PINWHEEL, piece_count(PINWHEEL), true)
	if tap and _qa_step == 1 and _qa_t >= act_at + QA_TAP_S:
		_qa_step = 2
		_end_press(true)
	var freeze_at := act_at + (QA_TAP_S if tap else 0.0) + _qa_ms / 1000.0
	if _qa_step >= 1 and _qa_t >= freeze_at:
		_qa_frozen = true
		if is_instance_valid(_qa_ring):
			_qa_ring.freeze_at(minf(_qa_t - act_at, _qa_ring.duration_s * 0.9))
