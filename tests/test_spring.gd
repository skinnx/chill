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


## Round 9: a DRIVEN spring (Motion.spring_to) rests within a fraction of the distance it set out
## to travel, not within an absolute 0.0005. Half of these springs move properties measured in
## PIXELS, and settling a 300 px panel to within 1/2000 of a pixel takes the `move` spring 1.10 s
## against 0.63 s for 0.15 px - half a second of travel nobody can see, during which Motion holds
## the whole app at 60 fps. The spring class's own default is unchanged for standalone users.
func test_a_driven_spring_rests_in_scale_with_its_travel() -> void:
	var node := Node2D.new()
	add_child_autofree(node)
	node.position = Vector2.ZERO
	Motion.spring_to(node, "position:x", 300.0, &"move")
	var eps: float = -1.0
	for d: Dictionary in Motion._drives:
		if d["object"] == node:
			eps = float((d["spring"] as Spring).rest_epsilon_x)
	assert_almost_eq(eps, 300.0 * Motion.REST_REL, 1e-6, "0.05 % of the travel")
	assert_gt(eps, 0.0005, "which is looser than the absolute token floor for a travel this long")


func test_a_driven_spring_lands_exactly_on_its_target() -> void:
	# Resting early must leave no residue: `rise` stopped 0.3 px short is invisible, but code that
	# asks `rise > 0.0` is not blind to it.
	var node := Node2D.new()
	add_child_autofree(node)
	node.position = Vector2.ZERO
	Motion.spring_to(node, "position:x", 300.0, &"move")
	for i in 240:
		Motion._process(1.0 / 60.0)
		if Motion._drives.is_empty():
			break
	assert_true(Motion._drives.is_empty(), "the drive finished")
	assert_eq(node.position.x, 300.0, "and wrote the exact target, not 299.9")


## A tiny motion keeps the absolute floor: the relative rest is a MAXimum against it, never a
## licence to stop a 1-unit alpha fade 0.0005 short of its end.
func test_a_small_travel_keeps_the_absolute_floor() -> void:
	var node := Node2D.new()
	add_child_autofree(node)
	node.modulate.a = 0.0
	Motion.spring_to(node, "modulate:a", 1.0, &"move")
	for d: Dictionary in Motion._drives:
		if d["object"] == node:
			assert_almost_eq(float((d["spring"] as Spring).rest_epsilon_x), 0.0005, 1e-9,
					"an alpha 0->1 stays on the token floor")
	Motion.stop_springs(node)


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


func test_motion_springs_use_token_rest_epsilon() -> void:
	var eps: Dictionary = tokens["springs"]["integrator"]["rest_epsilon"]
	var s := Motion.spring(&"jelly")
	var s2 := Motion.spring_2d(&"follow")
	assert_almost_eq(s.rest_epsilon_x, float(eps["x"]), 1e-12)
	assert_almost_eq(s.rest_epsilon_v, float(eps["v"]), 1e-12)
	assert_almost_eq(s2.rest_epsilon_x, float(eps["x"]), 1e-12)
	assert_almost_eq(s2.rest_epsilon_v, float(eps["v"]), 1e-12)


## Synthesis V5 on the loop table: breathing 3.5-4.5 s awake / 5-6 s asleep, and the night's
## 18 fireflies (Art Bible §7.1-7.2) start fewer than 3 glows per second scene-wide (WCAG 2.3.1).
func test_loop_periods_meet_v5() -> void:
	var k: Dictionary = tokens["loops_k"]
	var wrap := float(tokens["time"]["g_time_wrap_s"])
	for name: String in k:
		var r: Array = k[name]
		for v: Variant in r:
			assert_eq(float(v), floorf(float(v)), "%s: k must be an integer (C4)" % name)
	var awake: Array = k["breathe_awake"]
	var asleep: Array = k["breathe_asleep"]
	assert_between(wrap / float(awake[1]), 3.5, 4.5, "fastest awake breath")
	assert_between(wrap / float(awake[0]), 3.5, 4.5, "slowest awake breath")
	assert_between(wrap / float(asleep[1]), 5.0, 6.0, "fastest asleep breath")
	assert_between(wrap / float(asleep[0]), 5.0, 6.0, "slowest asleep breath")
	const NIGHT_FIREFLIES := 18
	var fire: Array = k["firefly_cycle"]
	assert_true(NIGHT_FIREFLIES * float(fire[1]) / wrap <= 3.0, "firefly glow onsets per second <= 3")
