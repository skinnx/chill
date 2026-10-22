class_name PetalFlight
extends Node2D
## Gathered petals lifting off a bed and arcing to the tea nook's jar (Active F2, ACTIVE_TEA §2.2):
## gather_fly_ms 600 on the `move` spring (no linear tween), 40 ms stagger, a soft arc, each petal
## turning a little as it flies. One canvas item for every petal in the air (one draw call while
## they fly, none at rest). Under Reduce Motion the petals fade toward the jar instead of arcing.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const ARC_K := 0.32
const MAX_PETALS := 8
const SCALE := 0.8

## [from, to, flower colour, delay s, spring]
var _petals: Array[Dictionary] = []
var _arrived: Callable = Callable()
var _qa_frozen: bool = false


func _init() -> void:
	z_index = 2
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## Launches one petal per entry of [param origins] ({pos: Vector2, flower: StringName}) toward
## [param to]; [param on_arrive] runs once when the first petal lands.
func launch(origins: Array[Dictionary], to: Vector2, stagger_s: float, on_arrive: Callable = Callable()) -> void:
	var n := mini(origins.size(), MAX_PETALS)
	for i in n:
		var o: Dictionary = origins[i]
		var s := Motion.spring(&"move", 0.0)
		s.target = 1.0
		_petals.append({"from": o["pos"], "to": to + Vector2(float(i % 3 - 1) * 6.0, 0.0),
			"color": TeaArt.flower_color(StringName(o["flower"])), "delay": stagger_s * float(i), "spring": s,
			"spin": float(i) * 1.3})
	_arrived = on_arrive
	FrameGovernor.hold_for(1.0 + stagger_s * float(n))
	set_process(true)


func is_flying() -> bool:
	return not _petals.is_empty()


## QA: hold the flight where it is.
func freeze() -> void:
	_qa_frozen = true


func _process(delta: float) -> void:
	if _qa_frozen:
		return
	step(delta)


func step(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for p: Dictionary in _petals:
		if float(p["delay"]) > 0.0:
			p["delay"] = float(p["delay"]) - delta
			keep.append(p)
			continue
		var s: Spring = p["spring"]
		s.step(delta)
		if s.value >= 0.985 or s.is_at_rest():
			if _arrived.is_valid():
				_arrived.call()
				_arrived = Callable()
			continue
		keep.append(p)
	_petals = keep
	queue_redraw()
	if _petals.is_empty():
		set_process(false)
	else:
		FrameGovernor.poke()


func _draw() -> void:
	for p: Dictionary in _petals:
		if float(p["delay"]) > 0.0:
			continue
		var s: Spring = p["spring"]
		var e := clampf(s.value, 0.0, 1.0)
		var from: Vector2 = p["from"]
		var to: Vector2 = p["to"]
		var c: Color = p["color"]
		var at := from.lerp(to, e)
		if Motion.reduce_motion:
			at = to
			c.a = e
		else:
			at += Vector2(0.0, -sin(PI * e) * from.distance_to(to) * ARC_K)
		TeaArt.draw(self, &"petal", at, SCALE * (1.0 - 0.35 * e), float(p["spin"]) + e * 2.4, c)
