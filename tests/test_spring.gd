extends GutTest
## Analytic spring and bezier helpers (Art Bible §10.1-10.2, motion_tokens.json): every spring
## token converges within its settle time, overshoots by the analytic amount, is frame-rate
## independent and keeps velocity when retargeted; Reduce Motion springs never overshoot.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

var tokens: Dictionary


func before_all() -> void:
	tokens = GameContent.load_from_dir().motion


func _run(s: Spring, seconds: float, dt: float) -> Dictionary:
	var peak := s.value
	var settle_t := -1.0
	var t := 0.0
	var span := absf(s.target - s.value)
	while t < seconds:
		var v := s.step(dt)
		t += dt
		peak = maxf(peak, v)
		if settle_t < 0.0 and absf(v - s.target) <= 0.02 * span:
			settle_t = t
		elif absf(v - s.target) > 0.02 * span:
			settle_t = -1.0
	return {"peak": peak, "settle_t": settle_t}


func test_every_token_converges_with_its_overshoot() -> void:
	for name: String in ["press", "move", "pop", "jelly", "follow"]:
		var spec: Dictionary = tokens["springs"][name]
		var s := Spring.new(float(spec["f_hz"]), float(spec["zeta"]), 0.0)
		s.target = 1.0
		var r := _run(s, 3.0, 1.0 / 240.0)
		assert_almost_eq(s.value, 1.0, 0.001, "%s converges" % name)
		assert_almost_eq(float(r["peak"]) - 1.0, float(spec["overshoot"]), 0.01, "%s overshoot" % name)
		assert_almost_eq(float(r["peak"]) - 1.0, Spring.overshoot(float(spec["zeta"])), 0.002, "%s analytic overshoot" % name)
		# Tokens state the classic 2 % envelope time 4 / (zeta * omega). The real step response
		# enters the band at about that time (a little later as zeta approaches 1).
		var omega := TAU * float(spec["f_hz"])
		var envelope_ms := 4000.0 / (float(spec["zeta"]) * omega)
		assert_almost_eq(float(spec["settle_ms"]), envelope_ms, 1.0, "%s token settle_ms is the envelope time" % name)
		var settle_ms := float(r["settle_t"]) * 1000.0
		assert_true(settle_ms > 0.0 and settle_ms <= envelope_ms * 1.1,
				"%s settles by ~%.0f ms (got %.0f)" % [name, envelope_ms, settle_ms])


func test_frame_rate_independent() -> void:
	var a := Spring.new(2.6, 0.4, 0.0)
	var b := Spring.new(2.6, 0.4, 0.0)
	a.target = 1.0
	b.target = 1.0
	for i in 30:
		a.step(1.0 / 30.0)
	for i in 120:
		b.step(1.0 / 120.0)
	assert_almost_eq(a.value, b.value, 1e-9, "same state after 1 s at 30 or 120 fps")
	assert_almost_eq(a.velocity, b.velocity, 1e-7)


func test_stable_with_long_frames() -> void:
	var s := Spring.new(6.0, 0.9, 0.0)
	s.target = 1.0
	for i in 20:
		s.step(0.25)  # a 4 fps hitch never explodes (closed form, no integration error)
	assert_almost_eq(s.value, 1.0, 1e-6)


func test_retarget_keeps_velocity() -> void:
	var s := Spring.new(2.4, 0.8, 0.0)
	s.target = 1.0
	for i in 6:
		s.step(1.0 / 60.0)
	var v := s.velocity
	var x := s.value
	s.target = -1.0
	assert_eq(s.velocity, v, "retargeting does not reset velocity")
	assert_eq(s.value, x)
	s.step(1.0 / 60.0)
	assert_gt(s.value, x - 0.05, "continues smoothly from the current motion")


func test_critically_damped_never_overshoots() -> void:
	var s := Spring.new(2.6, 1.0, 0.0)
	s.target = 1.0
	var r := _run(s, 3.0, 1.0 / 60.0)
	assert_true(float(r["peak"]) <= 1.0 + 1e-9)
	var over := Spring.new(2.6, 1.6, 0.0)
	over.target = 1.0
	r = _run(over, 6.0, 1.0 / 60.0)
	assert_true(float(r["peak"]) <= 1.0 + 1e-9, "overdamped too")
	assert_almost_eq(over.value, 1.0, 0.001)


func test_reduce_motion_springs_are_critically_damped() -> void:
	var was := Motion.reduce_motion
	Motion.reduce_motion = true
	assert_true(Motion.spring_params(&"jelly").y >= 1.0)
	Motion.reduce_motion = false
	assert_almost_eq(Motion.spring_params(&"jelly").y, 0.4, 1e-6)
	Motion.reduce_motion = was


func test_spring_2d_matches_scalar() -> void:
	var s := Spring.new(3.2, 0.6, 0.0)
	var s2 := Spring2D.new(3.2, 0.6, Vector2.ZERO)
	s.target = 1.0
	s2.target = Vector2(1.0, -2.0)
	for i in 40:
		s.step(1.0 / 60.0)
		s2.step(1.0 / 60.0)
	assert_almost_eq(s2.value.x, s.value, 1e-6)
	assert_almost_eq(s2.value.y, -2.0 * s.value, 1e-6)


func test_cubic_bezier_tokens() -> void:
	var std := CubicBezier.from_array(tokens["curves"]["standard"]["bezier"])
	assert_eq(std.progress(0.0), 0.0)
	assert_eq(std.progress(1.0), 1.0)
	var prev := 0.0
	for i in 101:
		var y := std.progress(i / 100.0)
		assert_true(y >= prev - 1e-9, "monotonic")
		prev = y
	var linear := CubicBezier.new(1.0 / 3.0, 1.0 / 3.0, 2.0 / 3.0, 2.0 / 3.0)
	assert_almost_eq(linear.progress(0.37), 0.37, 1e-6)
	var amb := CubicBezier.from_array(tokens["curves"]["ambient"]["bezier"])
	assert_almost_eq(amb.progress(0.5), 0.5, 1e-6, "ease-in-out is symmetric")


func test_motion_token_durations() -> void:
	assert_almost_eq(Motion.duration(&"standard"), 0.32, 1e-9)
	assert_almost_eq(Motion.duration(&"exit"), 0.32 * 0.65, 1e-9)
	assert_almost_eq(Motion.duration(&"short"), 0.2, 1e-9)
	assert_almost_eq(Motion.stagger_delay(3), 0.09, 1e-9)
	assert_almost_eq(Motion.stagger_delay(100), 0.24, 1e-9, "stagger is capped")
