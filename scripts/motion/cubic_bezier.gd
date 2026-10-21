class_name CubicBezier
extends RefCounted
## CSS cubic-bezier(x1, y1, x2, y2) easing (Art Bible §10.1, motion_tokens.json curves).
## Use with PropertyTweener.set_custom_interpolator(curve.progress) and TRANS_LINEAR (05 §3.2).

const NEWTON_ITERATIONS := 6
const NEWTON_MIN_SLOPE := 1e-6
const BISECTION_ITERATIONS := 24

var x1: float
var y1: float
var x2: float
var y2: float


func _init(p_x1: float, p_y1: float, p_x2: float, p_y2: float) -> void:
	x1 = clampf(p_x1, 0.0, 1.0)
	y1 = p_y1
	x2 = clampf(p_x2, 0.0, 1.0)
	y2 = p_y2


static func from_array(a: Array) -> CubicBezier:
	var v := PackedFloat64Array(a)
	return CubicBezier.new(v[0], v[1], v[2], v[3])


## Eased progress for linear progress [param x] in [0, 1].
func progress(x: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	return _sample(y1, y2, _solve_t(x))


func _solve_t(x: float) -> float:
	var t := x
	for _i in NEWTON_ITERATIONS:
		var err := _sample(x1, x2, t) - x
		if absf(err) < 1e-7:
			return t
		var d := _slope(x1, x2, t)
		if absf(d) < NEWTON_MIN_SLOPE:
			break
		t -= err / d
	var lo := 0.0
	var hi := 1.0
	t = x
	for _i in BISECTION_ITERATIONS:
		var v := _sample(x1, x2, t)
		if absf(v - x) < 1e-7:
			return t
		if v < x:
			lo = t
		else:
			hi = t
		t = (lo + hi) * 0.5
	return t


static func _sample(a: float, b: float, t: float) -> float:
	var u := 1.0 - t
	return 3.0 * u * u * t * a + 3.0 * u * t * t * b + t * t * t


static func _slope(a: float, b: float, t: float) -> float:
	var u := 1.0 - t
	return 3.0 * u * u * a + 6.0 * u * t * (b - a) + 3.0 * t * t * (1.0 - b)
