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
const LANTERN_POOL_R := 150.0
const LANTERN_POOL_I := 0.6
const LANTERN_POOL_DY := -8.0
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
## Hit radii (GDD §8.4: >= 60 dp, 64 dp in the look zone) in dp.
const HIT_DP := 64.0
const DRAG_CANCEL_PX := 24.0
## Placement (Art Bible §6.6): 300 ms fade + pop 0.6 -> 1 + 4 dust motes.
const PLACE_FROM_SCALE := 0.6
const PUFF_MOTES := 4
const PUFF_RADIUS := 26.0
const PUFF_S := 0.5
## Depth scale (Art Bible §2.4).
const DEPTH := Vector3(0.62, 760.0, 740.0)
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
var _wind: float = 0.35
var _light: Dictionary = {}
var _dp: float = 3.0
var _set_scale: Dictionary = {}
var _press: Piece = null
var _press_pos := Vector2.ZERO
var _chime_own_s: float = -1.0
var _puffs: Array[Dictionary] = []
var _pop_s: float = 0.3


class Piece:
	extends RefCounted
	var decor: StringName
	var index: int
	var node: Node2D
	var sprites: Array[Sprite2D] = []
	var head: Node2D
	var foot := Vector2.ZERO
	var depth: float = 1.0
	var hit := Vector2.ZERO
	var angle: float = 0.0
	var burst_t: float = -1.0
	var pend: Spring
	var boost_t: float = -1.0
	var halo: HaloSprite
	var core: Sprite2D
	var lamp: StringName = &""
	var press: Spring
	var tint: float = 0.0
	var appear_t: float = -1.0
	var pop: Spring
	var shadow: ContactShadow


func _ready() -> void:
	current = self
	_content = ContentRegistry.content
	kit = DecorKit.new(_content)
	_dp = float(_content.spots_doc["frame"]["px_per_dp"])
	_set_scale = kit.layout.get("set_scale", {})
	_pop_s = float(_content.motion["durations_ms"]["fade_in_min"]) / 1000.0
	_shadows = Node2D.new()
	_shadows.name = "Shadows"
	_shadows.y_sort_enabled = false
	add_child(_shadows)
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
	p.press = Motion.spring(&"press", 1.0)
	p.pop = Motion.spring(&"pop", 1.0)
	p.node = Node2D.new()
	p.node.name = "%s_%d" % [id, i]
	p.node.position = p.foot
	match id:
		PINWHEEL:
			_build_pinwheel(p)
		CAIRN:
			_build_cairn(p)
		TOADSTOOL:
			_build_toadstool(p)
		STONES:
			_build_stone(p)
		LANTERN:
			_build_lantern(p)
		CHIME:
			_build_chime(p)
	if p.node.get_parent() == null:
		add_child(p.node)
	if SHADOWS.has(id) and (id != CAIRN or i == 0):
		var s: Vector3 = SHADOWS[id]
		p.shadow = ContactShadow.new(Vector2(s.x, s.y) * p.depth, s.z * p.depth, 1.0)
		p.shadow.position = p.foot
		_shadows.add_child(p.shadow)
		p.shadow.set_light(_light)
	var list: Array = _pieces.get(id, [])
	list.append(p)
	_pieces[id] = list
	if animate:
		p.appear_t = 0.0
		p.pop = Motion.spring(&"pop", PLACE_FROM_SCALE)
		p.pop.target = 1.0
		for sp: Sprite2D in p.sprites:
			sp.modulate.a = 0.0
		_puff(_piece_top(p))
		AudioDirector.play_cue(CUE_PLACE, {"world": true, "position": _canvas_of(p.foot)})
		FrameGovernor.hold_for(Motion.duration(&"emphasized"))
	return p


func _add_sprite(p: Piece, parent: Node2D, part: String, pos: Vector2, material_id: String = "",
		emission: float = -1.0) -> Sprite2D:
	var sp := kit.sprite(part, p.depth, material_id, emission)
	sp.position = pos
	parent.add_child(sp)
	p.sprites.append(sp)
	return sp


func _build_pinwheel(p: Piece) -> void:
	_add_sprite(p, p.node, "pinwheel_stick", Vector2.ZERO)
	p.head = Node2D.new()
	p.head.position = Vector2(0.0, float(kit.layout.get("pinwheel_head_dy", -86.0)) * p.depth)
	p.node.add_child(p.head)
	_add_sprite(p, p.head, "pinwheel_a", Vector2.ZERO)
	_add_sprite(p, p.head, "pinwheel_b", Vector2.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(PINWHEEL), p.index])
	p.angle = rng.randf() * TAU
	p.head.rotation = p.angle
	p.hit = p.foot + p.head.position


func _build_cairn(p: Piece) -> void:
	# All pebbles live under the base copy's node (one sort unit); later copies add sprites to it.
	var parts: Array = kit.layout.get("cairn_parts", ["pebble_0"])
	var base: Piece = p
	var list: Array = _pieces.get(CAIRN, [])
	if p.index > 0 and not list.is_empty():
		base = list[0]
		p.node.queue_free()
		p.node = base.node
	else:
		p.node.y_sort_enabled = false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(CAIRN), p.index])
	var part := String(parts[mini(p.index, parts.size() - 1)])
	var shrink := 1.0 - 0.05 * float(maxi(0, p.index - parts.size() + 1))
	var off := _anchor(CAIRN, p.index) - base.foot + Vector2(rng.randf_range(-1.0, 1.0) * CAIRN_JITTER_PX, 0.0)
	var sp := kit.sprite(part, base.depth * shrink)
	sp.position = off
	sp.rotation = deg_to_rad(rng.randf_range(-1.0, 1.0) * CAIRN_TILT_DEG)
	base.node.add_child(sp)
	p.sprites.append(sp)
	p.hit = p.foot


func _build_toadstool(p: Piece) -> void:
	_add_sprite(p, p.node, "toadstool_stem", Vector2.ZERO)
	_add_sprite(p, p.node, "toadstool_cap", Vector2(0.0, float(kit.layout.get("toadstool_cap_dy", -20.0)) * p.depth))
	p.hit = p.foot


func _build_stone(p: Piece) -> void:
	_add_sprite(p, p.node, "stream_stone", Vector2.ZERO)
	p.hit = p.foot
	if BrookLayer.current != null:
		BrookLayer.current.set_stone(_stone_key(p.index), p.foot, kit.size_of("stream_stone").x * 0.5 * p.depth)


func _stone_key(i: int) -> StringName:
	return StringName("decor_stone_%d" % i)


func _build_lantern(p: Piece) -> void:
	_add_sprite(p, p.node, "lantern_crook", Vector2.ZERO)
	var hook: Array = kit.layout.get("lantern_hook", [30, 28])
	p.head = Node2D.new()
	p.head.position = kit.frame_point("lantern_crook", Vector2(float(hook[0]), float(hook[1]))) * p.depth
	p.node.add_child(p.head)
	var mats: Dictionary = _content.palettes["materials"]
	var em := float((mats["lantern_light"] as Dictionary).get("night_emission", 0.85))
	p.core = _add_sprite(p, p.head, "lantern_core", Vector2(0.0, float(kit.layout.get("lantern_core_dy", 14.0)) * p.depth),
			"", em)
	_add_sprite(p, p.head, "lantern_jar", Vector2.ZERO)
	var lk: Dictionary = _content.motion["loops_k"]
	p.halo = HaloSprite.new().setup(LANTERN_HALO.x * p.depth, LANTERN_HALO.y * p.depth,
			Color(1, 1, 1, LANTERN_HALO_ALPHA), float((lk["lantern_breath"] as Array)[0]),
			HaloSprite.FLAG_NIGHT + HaloSprite.FLAG_ACCENT, float(p.index) * 1.7)
	p.halo.position = Vector2(0.0, float(kit.layout.get("jar_centre_dy", 28.0)) * p.depth)
	p.head.add_child(p.halo)
	p.pend = Motion.spring(&"follow", 0.0)
	p.hit = p.foot + p.head.position + p.halo.position
	if p.index < MAX_LANTERN_POOLS:
		p.lamp = StringName("lantern_%d" % p.index)
		LampRegistry.set_lamp(p.lamp, Vector2(p.foot.x + p.head.position.x, p.foot.y + LANTERN_POOL_DY),
				LANTERN_POOL_R, LANTERN_POOL_I)


func _build_chime(p: Piece) -> void:
	var parts: Array = kit.layout.get("chime_parts", ["chime_mid"])
	p.node.position = p.foot - _chime_set.position
	_chime_set.add_child(p.node)
	_add_sprite(p, p.node, String(parts[p.index % parts.size()]), Vector2.ZERO)
	p.head = p.node
	p.pend = Motion.spring(&"follow", 0.0)
	p.hit = p.foot


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
		_motes.position = centre
		add_child(_motes)
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
	if p.head != null and p.decor != CHIME:
		return p.foot + p.head.position
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
	var gt := Clock.g_time
	var motion := 0.3 if Motion.reduce_motion else 1.0
	if _chime_own_s >= 0.0:
		_chime_own_s += delta
		if _chime_own_s > CHIME_OWN_CUE_S:
			_chime_own_s = -1.0
	for p: Piece in _pieces.get(PINWHEEL, []):
		var rev := pinwheel_rev_s(_wind, gust_at(p.hit.x, gt)) * motion
		if p.burst_t >= 0.0:
			p.burst_t += delta
			rev = maxf(rev, PW_BURST_REV * exp(-p.burst_t / PW_BURST_TAU))
			if p.burst_t > PW_BURST_TAU * 5.0:
				p.burst_t = -1.0
		p.angle = fposmod(p.angle + rev * TAU * delta, TAU)
		p.head.rotation = p.angle
	var force := deg_to_rad(lerpf(CHIME_FORCE_DEG.x, CHIME_FORCE_DEG.y, clampf(_wind, 0.0, 1.0))) * motion
	for p: Piece in _pieces.get(CHIME, []):
		p.pend.target = force * (0.35 + 0.65 * gust_at(p.foot.x, gt))
		p.head.rotation = p.pend.step(delta)
	for p: Piece in _pieces.get(LANTERN, []):
		p.pend.target = deg_to_rad(JAR_SWAY_DEG) * _wind * gust_at(p.foot.x, gt) * motion
		p.head.rotation = p.pend.step(delta)
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
		for sp: Sprite2D in p.sprites:
			sp.modulate.a = clampf(p.appear_t / _pop_s, 0.0, 1.0)
			sp.scale = Vector2.ONE * s * p.depth / kit.atlas_scale
		if p.appear_t >= _pop_s and p.pop.is_at_rest():
			p.appear_t = -1.0
	if not p.press.is_at_rest() or p.press.target < 1.0 or p.tint > 0.0:
		var v := p.press.step(delta)
		p.tint = maxf(0.0, p.tint - delta / Motion.duration(&"short"))
		for sp: Sprite2D in p.sprites:
			DecorKit.set_press(sp, p.tint, v)


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
	var k := 1.0 + LANTERN_BOOST * smoothstep(0.0, 1.0, e)
	var c: Color = p.halo.get_instance_shader_parameter(&"i_color")
	c.a = LANTERN_HALO_ALPHA * k
	p.halo.set_instance_shader_parameter(&"i_color", c)
	var mats: Dictionary = _content.palettes["materials"]
	DecorKit.set_emission(p.core, float((mats["lantern_light"] as Dictionary).get("night_emission", 0.85)) * k)
	if p.lamp != &"":
		LampRegistry.set_lamp(p.lamp, Vector2(p.foot.x + p.head.position.x, p.foot.y + LANTERN_POOL_DY),
				LANTERN_POOL_R, LANTERN_POOL_I * k)


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
	return get_global_transform_with_canvas() * design


# ================================================================= touch

func _unhandled_input(event: InputEvent) -> void:
	var pressed := false
	var released := false
	if event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
		released = not pressed
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or mb.device == InputEvent.DEVICE_ID_EMULATION:
			return
		pressed = mb.pressed
		released = not mb.pressed
	elif _press != null and (event is InputEventScreenDrag or event is InputEventMouseMotion):
		var lm: Vector2 = make_input_local(event).get("position")
		if lm.distance_to(_press_pos) > DRAG_CANCEL_PX:
			_end_press(false)
		return
	else:
		return
	var pos: Vector2 = make_input_local(event).get("position")
	if pressed:
		if PlotsLayer.current != null and PlotsLayer.current.claims(pos):
			return  # a bed with a ready bud outranks décor (GDD §2.5 hit priority)
		var p := _piece_at(pos)
		if p == null:
			return
		_press = p
		_press_pos = pos
		p.press = Motion.spring(&"press", p.press.value)
		p.press.target = float(_content.motion["ui"]["world_touch_squash"])
		p.tint = 1.0
		AudioDirector.play_cue(CUE_TOUCH, {"world": true, "position": _canvas_of(p.hit)})
		FrameGovernor.hold_for(Motion.duration(&"short"))
		get_viewport().set_input_as_handled()
	elif released and _press != null:
		_end_press(pos.distance_to(_press_pos) <= DRAG_CANCEL_PX)
		get_viewport().set_input_as_handled()


func _piece_at(pos: Vector2) -> Piece:
	var best: Piece = null
	var best_d := INF
	var r := HIT_DP * _dp * 0.5
	for id: StringName in [PINWHEEL, LANTERN]:
		for p: Piece in _pieces.get(id, []):
			var d := pos.distance_to(p.hit)
			if d <= r and d < best_d:
				best = p
				best_d = d
	return best


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
