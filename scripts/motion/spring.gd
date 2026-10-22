class_name Spring
extends RefCounted
## Analytic damped spring (Art Bible §10.2, motion_tokens.json springs).
##
## Mass 1, natural frequency f (Hz), damping ratio zeta. Instead of integrating, each step applies
## the exact closed-form solution of x'' + 2*zeta*w*x' + w^2*(x - target) = 0 over dt, so it is
## frame-rate independent, unconditionally stable at 30 fps and needs no sub-steps. Retargeting
## keeps the current value and velocity (interruptible motion, 05 §3.1).
##
## Usage:
##   var s := Spring.new(2.6, 0.4, 1.0)    # or Motion.spring(&"jelly")
##   s.target = 0.88
##   func _process(dt): node.scale = Vector2.ONE * s.step(dt)

## Value below this distance and velocity counts as settled (motion_tokens springs.integrator).
var rest_epsilon_x: float = 0.0005
var rest_epsilon_v: float = 0.002

var frequency_hz: float = 1.0
var damping_ratio: float = 1.0
var value: float = 0.0
var velocity: float = 0.0
var target: float = 0.0


func _init(p_frequency_hz: float = 2.4, p_damping_ratio: float = 0.8, p_value: float = 0.0) -> void:
	frequency_hz = maxf(0.001, p_frequency_hz)
	damping_ratio = maxf(0.0, p_damping_ratio)
	value = p_value
	target = p_value


## Advances by [param dt] seconds and returns the new value.
func step(dt: float) -> float:
	if dt <= 0.0 or is_at_rest():
		if is_at_rest():
			value = target
			velocity = 0.0
		return value
	var c := Spring.transition(frequency_hz, damping_ratio, dt)
	var x0 := value - target
	var v0 := velocity
	value = target + c[0] * x0 + c[1] * v0
	velocity = c[2] * x0 + c[3] * v0
	return value


func is_at_rest() -> bool:
	return absf(value - target) < rest_epsilon_x and absf(velocity) < rest_epsilon_v


## Moves value and target together (no motion), e.g. on layout changes.
func snap(p_value: float) -> void:
	value = p_value
	target = p_value
	velocity = 0.0


## Adds an impulse (velocity kick), e.g. a chime struck by a gust.
func kick(dv: float) -> void:
	velocity += dv


## Closed-form state transition over dt for unit mass:
## x(dt) - T = c0*(x0 - T) + c1*v0, v(dt) = c2*(x0 - T) + c3*v0.
static func transition(f_hz: float, zeta: float, dt: float) -> PackedFloat64Array:
	var w := TAU * f_hz
	if absf(zeta - 1.0) < 1e-4:
		var e := exp(-w * dt)
		return PackedFloat64Array([e * (1.0 + w * dt), e * dt, -e * w * w * dt, e * (1.0 - w * dt)])
	if zeta < 1.0:
		var wd := w * sqrt(1.0 - zeta * zeta)
		var e := exp(-zeta * w * dt)
		var cs := cos(wd * dt)
		var sn := sin(wd * dt)
		return PackedFloat64Array([
			e * (cs + zeta * w / wd * sn),
			e * sn / wd,
			-e * w * w / wd * sn,
			e * (cs - zeta * w / wd * sn)])
	var sq := sqrt(zeta * zeta - 1.0)
	var r1 := -w * (zeta - sq)
	var r2 := -w * (zeta + sq)
	var e1 := exp(r1 * dt)
	var e2 := exp(r2 * dt)
	var inv := 1.0 / (r2 - r1)
	# x = c1 e^{r1 t} + c2 e^{r2 t}, c2 = (v0 - r1 x0)/(r2 - r1), c1 = x0 - c2
	return PackedFloat64Array([
		(r2 * e1 - r1 * e2) * inv,
		(e2 - e1) * inv,
		r1 * r2 * (e1 - e2) * inv,
		(r2 * e2 - r1 * e1) * inv])


## Peak overshoot fraction of an underdamped step response: exp(-zeta*pi/sqrt(1-zeta^2)).
static func overshoot(zeta: float) -> float:
	if zeta >= 1.0:
		return 0.0
	return exp(-zeta * PI / sqrt(1.0 - zeta * zeta))
