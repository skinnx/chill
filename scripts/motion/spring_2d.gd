class_name Spring2D
extends RefCounted
## Vector2 version of [Spring] (same closed-form transition), for positions and scales.

var rest_epsilon_x: float = 0.0005
var rest_epsilon_v: float = 0.002
var frequency_hz: float = 1.0
var damping_ratio: float = 1.0
var value: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var target: Vector2 = Vector2.ZERO


func _init(p_frequency_hz: float = 2.4, p_damping_ratio: float = 0.8, p_value: Vector2 = Vector2.ZERO) -> void:
	frequency_hz = maxf(0.001, p_frequency_hz)
	damping_ratio = maxf(0.0, p_damping_ratio)
	value = p_value
	target = p_value


func step(dt: float) -> Vector2:
	if is_at_rest():
		value = target
		velocity = Vector2.ZERO
		return value
	if dt <= 0.0:
		return value
	var c := Spring.transition(frequency_hz, damping_ratio, dt)
	var x0 := value - target
	var v0 := velocity
	value = target + x0 * c[0] + v0 * c[1]
	velocity = x0 * c[2] + v0 * c[3]
	return value


func is_at_rest() -> bool:
	return (value - target).length() < rest_epsilon_x and velocity.length() < rest_epsilon_v


func snap(p_value: Vector2) -> void:
	value = p_value
	target = p_value
	velocity = Vector2.ZERO


func kick(dv: Vector2) -> void:
	velocity += dv
