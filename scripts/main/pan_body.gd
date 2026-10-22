class_name PanBody
extends RefCounted
## Motion of the map pan (docs/ARCHITECTURE.md §3.4): 1:1 drag, inertial glide with friction,
## rubber band past the rest bounds and a spring back (motion token "move"). Pure: the caller feeds
## positions and steps it; [method offset] is what the camera shows.
##
## State is kept as an unconstrained "raw" pan per axis; the shown offset is the rubber-banded raw
## (identity inside the rest bounds, so dragging inside them tracks the finger exactly). Under
## Reduce Motion there is no inertia and no overshoot: the offset is the raw pan clamped to the rest
## bounds and a release simply stops.

enum Axis { IDLE, GLIDE, SPRING }

## Spring rest thresholds in px and px/s (the token epsilons are for unit-scale values).
const REST_X_PX := 0.1
const REST_V_PX_S := 2.0

var rest := Rect2()
var hard := Rect2()
var rubber_k: float = 0.55
var friction_per_s: float = 4.5
var min_speed: float = 12.0
var max_speed: float = 3600.0
var spring_hz: float = 2.4
var spring_zeta: float = 0.8
var reduce_motion: bool = false

var raw := Vector2.ZERO
var velocity := Vector2.ZERO
var dragging: bool = false

var _mode: Array[int] = [Axis.IDLE, Axis.IDLE]
var _springs: Array[Spring] = [null, null]


func set_bounds(p_rest: Rect2, p_hard: Rect2) -> void:
	rest = p_rest
	hard = p_hard
	if not dragging and not is_moving():
		raw = PanMath.clamp_2d(raw, rest)


## What the camera shows (rubber-banded, or clamped under Reduce Motion).
func offset() -> Vector2:
	if reduce_motion:
		return PanMath.clamp_2d(raw, rest)
	return PanMath.rubber_2d(raw, rest, hard, rubber_k)


func is_moving() -> bool:
	return _mode[0] != Axis.IDLE or _mode[1] != Axis.IDLE


func is_active() -> bool:
	return dragging or is_moving()


## A finger landed: any glide or spring stops where it is (a press catches the map).
func stop() -> void:
	if reduce_motion:
		raw = PanMath.clamp_2d(raw, rest)
	velocity = Vector2.ZERO
	_mode = [Axis.IDLE, Axis.IDLE]


func begin_drag() -> void:
	stop()
	dragging = true


func drag_to(p_raw: Vector2) -> void:
	raw = p_raw


## Finger up with [param v] px/s (pan units). Inside the bounds the pan glides with friction; past
## them it springs back to the edge, keeping its speed (interruptible). Reduce Motion: stops.
func release(v: Vector2) -> void:
	dragging = false
	if reduce_motion:
		raw = PanMath.clamp_2d(raw, rest)
		velocity = Vector2.ZERO
		_mode = [Axis.IDLE, Axis.IDLE]
		return
	velocity = v.limit_length(max_speed)
	for i in 2:
		var lo := rest.position[i]
		var hi := rest.end[i]
		if raw[i] < lo or raw[i] > hi:
			_spring_axis(i, clampf(raw[i], lo, hi), velocity[i])
		elif absf(velocity[i]) >= min_speed:
			_mode[i] = Axis.GLIDE
		else:
			_mode[i] = Axis.IDLE
			velocity[i] = 0.0


## Glides to [param target] (clamped to the rest bounds) on the spring; instant under Reduce Motion.
func glide_to(target: Vector2) -> void:
	dragging = false
	var t := PanMath.clamp_2d(target, rest)
	if reduce_motion:
		raw = t
		velocity = Vector2.ZERO
		_mode = [Axis.IDLE, Axis.IDLE]
		return
	for i in 2:
		_spring_axis(i, t[i], velocity[i])


## Jumps to [param p] (clamped), e.g. QA --qa-pan or a layout change.
func snap(p: Vector2) -> void:
	dragging = false
	raw = PanMath.clamp_2d(p, rest)
	velocity = Vector2.ZERO
	_mode = [Axis.IDLE, Axis.IDLE]


## Advances the glide / spring by [param dt] s. Returns true while still moving.
func step(dt: float) -> bool:
	if dragging or dt <= 0.0:
		return is_moving()
	for i in 2:
		match _mode[i]:
			Axis.GLIDE:
				_step_glide(i, dt)
			Axis.SPRING:
				var s := _springs[i]
				raw[i] = s.step(dt)
				velocity[i] = s.velocity
				if s.is_at_rest():
					raw[i] = s.target
					velocity[i] = 0.0
					_mode[i] = Axis.IDLE
	return is_moving()


## Exact exponential friction: v(t) = v0·e^(−k t), x(t) = x0 + v0·(1 − e^(−k t))/k. Crossing a
## rest edge hands the remaining speed to the spring (it overshoots into the rubber band and
## settles on the edge).
func _step_glide(i: int, dt: float) -> void:
	var v0 := velocity[i]
	var k := maxf(friction_per_s, 0.001)
	var e := exp(-k * dt)
	raw[i] += v0 * (1.0 - e) / k
	velocity[i] = v0 * e
	var lo := rest.position[i]
	var hi := rest.end[i]
	if raw[i] < lo or raw[i] > hi:
		_spring_axis(i, clampf(raw[i], lo, hi), velocity[i])
	elif absf(velocity[i]) < min_speed:
		velocity[i] = 0.0
		_mode[i] = Axis.IDLE


func _spring_axis(i: int, target: float, v: float) -> void:
	var s := Spring.new(spring_hz, spring_zeta, raw[i])
	s.rest_epsilon_x = REST_X_PX
	s.rest_epsilon_v = REST_V_PX_S
	s.velocity = v
	s.target = target
	_springs[i] = s
	_mode[i] = Axis.SPRING
	if s.is_at_rest():
		raw[i] = target
		velocity[i] = 0.0
		_mode[i] = Axis.IDLE
