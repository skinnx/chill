extends GutTest
## Clock frame-clock mode (docs/QA.md §3.2): with --frame-clock (or in Movie Maker mode) wall time
## and ticks advance by the frame delta only, so a capture run under --fixed-fps replays
## bit-identically whatever the system clock reads, and recorded video stays in sync with the world.

const ClockScript := preload("res://scripts/autoload/clock.gd")
const FIXED_DT := 1.0 / 30.0
const FRAMES := 90
## 2026-04-18 10:00 UTC, the capture tool's default wall clock.
const PINNED_UNIX := 1776506400.0


func _make_clock(frame_mode: bool) -> ClockScript:
	var c: ClockScript = ClockScript.new()
	c.frame_clock = frame_mode  # set before _ready, as tools/qa/capture.gd does
	add_child_autofree(c)
	c.set_process(false)  # the test drives frames by hand
	return c


func _run_frames(c: ClockScript, n: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i in n:
		c._process(FIXED_DT)
		out.append(c.now_unix())
	return out


func test_frame_clock_replays_identically() -> void:
	var a := _make_clock(true)
	a.override_now(PINNED_UNIX)
	var seq_a := _run_frames(a, FRAMES)
	OS.delay_msec(20)  # the system clock moves on; the frame clock must not care
	var b := _make_clock(true)
	b.override_now(PINNED_UNIX)
	var seq_b := _run_frames(b, FRAMES)
	assert_eq(seq_a, seq_b, "two runs with the same --now and frame deltas give the same wall times")
	assert_eq(a.ticks_s(), b.ticks_s())
	assert_almost_eq(a.ticks_s(), FRAMES * FIXED_DT, 1e-9, "ticks = sum of frame deltas")
	assert_eq(a.now_unix(), PINNED_UNIX + a.ticks_s(), "now = pinned + frame time, exactly")


func test_frame_clock_ignores_real_time() -> void:
	var c := _make_clock(true)
	c.override_now(PINNED_UNIX)
	var before := c.now_unix()
	var ticks_before := c.ticks_s()
	OS.delay_msec(30)
	assert_eq(c.now_unix(), before, "no frame, no time")
	assert_eq(c.ticks_s(), ticks_before)


func test_override_mid_run_and_clear() -> void:
	var c := _make_clock(true)
	_run_frames(c, 10)
	c.override_now(PINNED_UNIX + 3600.0)
	assert_almost_eq(c.now_unix(), PINNED_UNIX + 3600.0, 1e-6)
	c._process(FIXED_DT)
	assert_almost_eq(c.now_unix(), PINNED_UNIX + 3600.0 + FIXED_DT, 1e-6, "time keeps flowing by frames")
	c.clear_overrides()
	assert_almost_eq(c.now_unix(), Time.get_unix_time_from_system(), 5.0, "cleared: back near the system clock")


func test_system_clock_mode_unchanged() -> void:
	var c := _make_clock(false)
	assert_false(c.frame_clock, "frame clock stays off without --frame-clock or Movie Maker")
	assert_almost_eq(c.ticks_s(), Time.get_ticks_usec() / 1000000.0, 0.05)
	c.override_now(PINNED_UNIX)
	assert_almost_eq(c.now_unix(), PINNED_UNIX, 0.05)
