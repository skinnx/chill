class_name LeafBoats
extends Node2D
## The leaf-boat ritual on the brook (GDD §4.4, Art Bible §6.8): each boat event launches a
## folded-leaf boat at the spring rock (fade 300 ms + pop) that drifts the brook centre line
## right -> left in leaf_boat.drift_s (40 s), bobbing +-4 deg at k 124 with a faint wake (sparse
## brook ripples), and fades out at the left edge. From golden hour to dawn it carries a tiny
## candle (lantern_light emission + a halo_add r0 8 px core breathing at k 181 + a small warm pool).
## Up to max_on_water at once; extra launches queue queue_gap_s apart. Boats y-sort with the
## creatures watching them from the bank.
##
## QA user arg: --qa-boat=<0..1> puts one boat (settled, candle by phase) at that fraction of its
## drift, so a frozen-time still can show it.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## Where boats start (just downstream of the spring rock's cleft) and leave (past the left edge).
const START_X := 985.0
const END_X := -70.0
const FADE_S := 0.3
const CANDLE_PHASES: Array[StringName] = [&"golden", &"dusk", &"night", &"dawn"]
const CANDLE_HALO := Vector2(8.0, 48.0)
const CANDLE_HALO_ALPHA := 0.6
const CANDLE_POOL_R := 70.0
const CANDLE_POOL_I := 0.3
const CANDLE_DX := -6.0
const WAKE_EVERY_S := 2.4
const WAKE_AMP := 0.3
const WAKE_BEHIND_PX := 26.0
const BOB_PX := 1.5
const LOOP_S := 600.0
const DEPTH := Vector3(0.62, 760.0, 740.0)
const ARG_QA_BOAT := "--qa-boat="

var _content: GameContent
var _kit: DecorKit
var _cfg: Dictionary = {}
var _queue: int = 0
var _since_launch: float = INF
var _boats: Array[Boat] = []
var _serial: int = 0
var _path := PackedVector2Array()
var _cum := PackedFloat32Array()
var _qa_u: float = -1.0


class Boat:
	extends RefCounted
	var node: Node2D
	var sprite: Sprite2D
	var candle: Sprite2D
	var halo: HaloSprite
	var lamp: StringName
	var t: float = 0.0
	var wake_t: float = 0.0
	var phase: float = 0.0
	var pop: Spring


func setup(content: GameContent, kit: DecorKit) -> void:
	_content = content
	_kit = kit
	y_sort_enabled = true
	_cfg = content.motion["ui"]["leaf_boat"]
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(ARG_QA_BOAT):
			_qa_u = clampf(a.trim_prefix(ARG_QA_BOAT).to_float(), 0.0, 1.0)
			set_process(true)


## Queues one boat (Game boat event).
func launch() -> void:
	_queue += 1
	set_process(true)


func on_water() -> int:
	return _boats.size()


func _ensure_path() -> bool:
	if not _path.is_empty():
		return true
	var brook := BrookLayer.current
	if brook == null or brook.centre.size() < 2:
		return false
	var pts := PackedVector2Array()
	for p: Vector2 in brook.centre:
		if p.x <= START_X and p.x >= END_X:
			pts.append(p)
	if pts.size() < 2:
		return false
	_path = pts
	_cum.resize(pts.size())
	_cum[0] = 0.0
	for i in range(1, pts.size()):
		_cum[i] = _cum[i - 1] + pts[i].distance_to(pts[i - 1])
	return true


func _point_at(d: float) -> Vector2:
	var total := _cum[_cum.size() - 1]
	d = clampf(d, 0.0, total)
	for i in range(1, _cum.size()):
		if _cum[i] >= d:
			var seg := _cum[i] - _cum[i - 1]
			return _path[i - 1].lerp(_path[i], (d - _cum[i - 1]) / maxf(seg, 0.001))
	return _path[_path.size() - 1]


func _spawn() -> void:
	var b := Boat.new()
	_serial += 1
	b.phase = float(_serial) * 2.3
	b.node = Node2D.new()
	b.node.name = "Boat%d" % _serial
	add_child(b.node)
	var depth := clampf(DEPTH.x + (1.0 - DEPTH.x) * (_path[0].y - DEPTH.y) / DEPTH.z, DEPTH.x, 1.0)
	b.sprite = _kit.sprite("leaf_boat", depth)
	b.node.add_child(b.sprite)
	if CANDLE_PHASES.has(TimeOfDay.phase):
		b.candle = _kit.sprite("candle", depth)
		b.candle.position = Vector2(CANDLE_DX, -_kit.size_of("leaf_boat").y * 0.45) * depth
		b.node.add_child(b.candle)
		var k := float((_content.motion["loops_k"]["lantern_breath"] as Array)[0])
		b.halo = HaloSprite.new().setup(CANDLE_HALO.x, CANDLE_HALO.y, Color(1, 1, 1, CANDLE_HALO_ALPHA), k,
				HaloSprite.FLAG_NIGHT + HaloSprite.FLAG_ACCENT, b.phase)
		b.halo.position = b.candle.position + Vector2(0.0, -_kit.size_of("candle").y * 0.8 * depth)
		b.node.add_child(b.halo)
		b.lamp = StringName("boat_%d" % (_serial % int(_cfg.get("max_on_water", 3))))
	b.pop = Motion.spring(&"pop", 0.6)
	b.pop.target = 1.0
	b.node.modulate.a = 0.0
	_boats.append(b)
	_place(b)


func _process(delta: float) -> void:
	if _qa_u >= 0.0 and _ensure_path():
		_spawn()
		var b := _boats[_boats.size() - 1]
		b.t = _qa_u * float(_cfg.get("drift_s", 40.0))
		b.pop.snap(1.0)
		_place(b)
		_qa_u = -1.0
	_since_launch += delta
	if _queue > 0 and _boats.size() < int(_cfg.get("max_on_water", 3)) \
			and _since_launch >= float(_cfg.get("queue_gap_s", 4.0)) and _ensure_path():
		_queue -= 1
		_since_launch = 0.0
		_spawn()
	if _boats.is_empty():
		if _queue == 0:
			set_process(false)
		return
	var drift := float(_cfg.get("drift_s", 40.0))
	for i in range(_boats.size() - 1, -1, -1):
		var b := _boats[i]
		b.t += delta
		b.pop.step(delta)
		_place(b)
		b.wake_t += delta
		if b.wake_t >= WAKE_EVERY_S and BrookLayer.current != null:
			b.wake_t = 0.0
			BrookLayer.current.add_ripple(b.node.position + Vector2(WAKE_BEHIND_PX, 0.0), WAKE_AMP)
		if b.t >= drift:
			if b.lamp != &"":
				LampRegistry.remove_lamp(b.lamp)
			b.node.queue_free()
			_boats.remove_at(i)
	FrameGovernor.poke()


func _place(b: Boat) -> void:
	var drift := float(_cfg.get("drift_s", 40.0))
	var u := clampf(b.t / drift, 0.0, 1.0)
	var p := _point_at(u * _cum[_cum.size() - 1])
	var k := float(_cfg.get("bob_k", 124))
	var bob := sin(TAU * k / LOOP_S * Clock.g_time + b.phase)
	b.node.position = p + Vector2(0.0, bob * BOB_PX)
	b.sprite.rotation = deg_to_rad(float(_cfg.get("bob_deg", 4.0))) * bob * (0.3 if Motion.reduce_motion else 1.0)
	b.node.scale = Vector2.ONE * b.pop.value
	var fade_in := clampf(b.t / FADE_S, 0.0, 1.0)
	var fade_out := clampf((drift - b.t) / FADE_S, 0.0, 1.0)
	b.node.modulate.a = minf(fade_in, fade_out)
	if b.lamp != &"":
		LampRegistry.set_lamp(b.lamp, p, CANDLE_POOL_R, CANDLE_POOL_I * b.node.modulate.a)
