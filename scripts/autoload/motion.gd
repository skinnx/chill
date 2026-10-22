extends Node
## Motion (autoload #6): motion tokens (data/motion_tokens.json, Art Bible §10) as tween and
## spring helpers, with Reduce Motion applied in one place (X1, §10.4).
##
##   Motion.tween(node, "modulate:a", 1.0, &"short")          # token duration + curve
##   Motion.exit(node, "position:y", 1700.0)                    # exit = 0.65 x standard
##   var s := Motion.spring(&"jelly", 1.0)                      # analytic Spring (RM: zeta 1)
##   Motion.spring_to(button, "scale", Vector2.ONE, &"pop")     # driven here every frame
##   Motion.fade_in(node)                                       # never pop-in (>= 300 ms, V5)
##
## UI tweens report themselves to FrameGovernor so the frame rate stays at 60 while they run (C21).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

signal reduce_motion_changed(enabled: bool)

const SPATIAL_PROPERTIES: Array[String] = ["position", "global_position", "scale", "rotation",
	"offset", "size", "offset_transform_position", "offset_transform_scale", "offset_transform_rotation"]
const MS := 0.001

var tokens: Dictionary = {}
var reduce_motion: bool = false

var _curves: Dictionary = {}
## Active spring drives: [{object, property, spring, is_vec2}]
var _drives: Array[Dictionary] = []


func _ready() -> void:
	tokens = ContentRegistry.motion_tokens()
	var curves := _sect("curves")
	for name: String in curves:
		var c: Dictionary = curves[name]
		if c.has("bezier"):
			var bz: Array = c["bezier"]
			_curves[name] = CubicBezier.from_array(bz)
	reduce_motion = Settings.get_bool(Settings.REDUCE_MOTION)
	Settings.changed.connect(_on_setting_changed)


func _process(delta: float) -> void:
	if _drives.is_empty():
		return
	var i := 0
	while i < _drives.size():
		var d: Dictionary = _drives[i]
		# a Variant first: a freed object cannot be assigned to a typed Object var
		var raw: Variant = d["object"]
		if not is_instance_valid(raw):
			_drives.remove_at(i)
			continue
		var obj := raw as Object
		var prop: NodePath = d["property"]
		var done := false
		if d["is_vec2"]:
			var s2: Spring2D = d["spring"]
			obj.set_indexed(prop, s2.step(delta))
			done = s2.is_at_rest()
		else:
			var s1: Spring = d["spring"]
			obj.set_indexed(prop, s1.step(delta))
			done = s1.is_at_rest()
		if done:
			_drives.remove_at(i)
		else:
			i += 1
	FrameGovernor.hold_for(delta * 2.0)


# ------------------------------------------------------------------ durations and curves

## Token duration in seconds ("short", "standard", "emphasized", "exit", "micro", ...).
func duration(token: StringName) -> float:
	var d := _sect("durations_ms")
	if token == &"exit":
		return float(d.get("standard", 0.0)) * float(d.get("exit_factor", 1.0)) * MS
	if d.has(String(token)):
		return float(d[String(token)]) * MS
	var t := _sub(_sect("tokens"), String(token))
	if t.has("duration"):
		return float(d.get(String(t["duration"]), 0.0)) * MS
	return float(d.get("standard", 0.0)) * MS


## Name of the curve a token uses (motion_tokens tokens.<t>.curve).
func curve_of(token: StringName) -> String:
	var t := _sub(_sect("tokens"), String(token))
	return String(t.get("curve", "standard"))


## Applies a named curve to a tweener: exact bezier via a custom interpolator (TRANS_LINEAR), else
## the token's built-in trans/ease.
func apply_curve(tw: PropertyTweener, curve_name: String) -> PropertyTweener:
	if _curves.has(curve_name):
		var bz: CubicBezier = _curves[curve_name]
		tw.set_trans(Tween.TRANS_LINEAR).set_custom_interpolator(bz.progress)
		return tw
	var c := _sub(_sect("curves"), curve_name)
	tw.set_trans(_trans(String(c.get("trans", "SINE")))).set_ease(_ease(String(c.get("ease", "IN_OUT"))))
	return tw


func stagger_delay(index: int) -> float:
	var d := _sect("durations_ms")
	return minf(float(index) * float(d.get("stagger_step", 0.0)), float(d.get("stagger_cap", 0.0))) * MS


# ------------------------------------------------------------------ tweens

## Tweens [param property] of [param node] to [param to] with a motion token. Under Reduce
## Motion spatial properties jump at the midpoint of a 150 ms crossfade instead of moving.
func tween(node: Node, property: String, to: Variant, token: StringName = &"standard", ui: bool = true) -> Tween:
	var dur := duration(token)
	if reduce_motion and _is_spatial(property) and node is CanvasItem:
		return _crossfade_set(node as CanvasItem, property, to)
	var t := node.create_tween()
	apply_curve(t.tween_property(node, property, to, dur), curve_of(token))
	if ui:
		FrameGovernor.hold_for(dur)
	return t


## Exit motion (dismissals): 0.65 x standard with the exit curve.
func exit(node: Node, property: String, to: Variant, ui: bool = true) -> Tween:
	return tween(node, property, to, &"exit", ui)


## Fade in over at least durations_ms.fade_in_min (no pop-in, V5).
func fade_in(item: CanvasItem, token: StringName = &"standard") -> Tween:
	var d := _sect("durations_ms")
	var dur := maxf(duration(token), float(d.get("fade_in_min", 0.0)) * MS)
	item.modulate.a = 0.0
	var t := item.create_tween()
	apply_curve(t.tween_property(item, "modulate:a", 1.0, dur), curve_of(token))
	FrameGovernor.hold_for(dur)
	return t


func fade_out(item: CanvasItem, token: StringName = &"exit") -> Tween:
	var t := item.create_tween()
	var dur := duration(token)
	apply_curve(t.tween_property(item, "modulate:a", 0.0, dur), curve_of(token))
	FrameGovernor.hold_for(dur)
	return t


# ------------------------------------------------------------------ springs

## A new analytic spring with a token's f and zeta (critically damped under Reduce Motion).
func spring(token: StringName, value: float = 0.0) -> Spring:
	var p := spring_params(token)
	var s := Spring.new(p.x, p.y, value)
	var eps := rest_epsilon()
	s.rest_epsilon_x = float(eps.get("x", s.rest_epsilon_x))
	s.rest_epsilon_v = float(eps.get("v", s.rest_epsilon_v))
	return s


func spring_2d(token: StringName, value: Vector2 = Vector2.ZERO) -> Spring2D:
	var p := spring_params(token)
	var s := Spring2D.new(p.x, p.y, value)
	var eps := rest_epsilon()
	s.rest_epsilon_x = float(eps.get("x", s.rest_epsilon_x))
	s.rest_epsilon_v = float(eps.get("v", s.rest_epsilon_v))
	return s


## motion_tokens springs.integrator.rest_epsilon: {x, v}, the distance and speed below which a
## spring counts as settled (empty when the tokens do not define it; the springs' defaults apply).
func rest_epsilon() -> Dictionary:
	return _sub(_sub(_sect("springs"), "integrator"), "rest_epsilon")


## (f_hz, zeta) of a spring token.
func spring_params(token: StringName) -> Vector2:
	var s := _sub(_sect("springs"), String(token))
	var f := float(s.get("f_hz", 1.0))
	var z := float(s.get("zeta", 1.0))
	if reduce_motion:
		z = maxf(z, 1.0)
	return Vector2(f, z)


## Drives [param property] toward [param to] with a spring token until it settles. Retargets an
## existing drive on the same property (keeps velocity: interruptible).
func spring_to(object: Object, property: String, to: Variant, token: StringName) -> void:
	for d: Dictionary in _drives:
		if d["object"] == object and d["property"] == NodePath(property):
			if d["is_vec2"]:
				(d["spring"] as Spring2D).target = to
			else:
				(d["spring"] as Spring).target = float(to)
			return
	var current: Variant = object.get_indexed(NodePath(property))
	var is_vec2 := current is Vector2
	var s: RefCounted
	if is_vec2:
		var start: Vector2 = current
		var s2 := spring_2d(token, start)
		s2.target = to
		s = s2
	else:
		var s1 := spring(token, float(current))
		s1.target = float(to)
		s = s1
	_drives.append({"object": object, "property": NodePath(property), "spring": s, "is_vec2": is_vec2})


func stop_springs(object: Object) -> void:
	_drives = _drives.filter(func(d: Dictionary) -> bool: return d["object"] != object)


# ------------------------------------------------------------------ internals

func _crossfade_set(item: CanvasItem, property: String, to: Variant) -> Tween:
	var rm := _sect("reduce_motion")
	var half := float(rm.get("spatial_to_crossfade_ms", 0.0)) * MS * 0.5
	var a := item.modulate.a
	var t := item.create_tween()
	t.tween_property(item, "modulate:a", 0.0, half)
	t.tween_callback(func() -> void: item.set_indexed(NodePath(property), to))
	t.tween_property(item, "modulate:a", a, half)
	FrameGovernor.hold_for(half * 2.0)
	return t


func _sect(key: String) -> Dictionary:
	return _sub(tokens, key)


static func _sub(d: Dictionary, key: String) -> Dictionary:
	var v: Variant = d.get(key)
	return v if v is Dictionary else {}


static func _is_spatial(property: String) -> bool:
	var base := property.get_slice(":", 0)
	return SPATIAL_PROPERTIES.has(base)


static func _trans(name: String) -> Tween.TransitionType:
	match name:
		"QUAD":
			return Tween.TRANS_QUAD
		"CUBIC":
			return Tween.TRANS_CUBIC
		"EXPO":
			return Tween.TRANS_EXPO
		"BACK":
			return Tween.TRANS_BACK
		"SINE":
			return Tween.TRANS_SINE
		"LINEAR":
			return Tween.TRANS_LINEAR
	return Tween.TRANS_SINE


static func _ease(name: String) -> Tween.EaseType:
	match name:
		"IN":
			return Tween.EASE_IN
		"OUT":
			return Tween.EASE_OUT
		"IN_OUT":
			return Tween.EASE_IN_OUT
	return Tween.EASE_IN_OUT


func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key == Settings.REDUCE_MOTION:
		reduce_motion = bool(value)
		reduce_motion_changed.emit(reduce_motion)
