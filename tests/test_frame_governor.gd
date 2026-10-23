extends GutTest
## FrameGovernor (scripts/autoload/frame_governor.gd, synthesis C21, 02 §4.4): the frame-rate and
## quality-tier policy, and the two round-8 rules that keep it from landing on the player - a
## pointer on the glass counts as activity, and a tier step is held back until the gesture is over.

# Tests read Dictionaries and GUT asserts take Variants, so every value is converted or compared
# explicitly (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

var _enabled: bool = true
var _ambient: bool = false
var _tier: int = 0


func before_each() -> void:
	_enabled = FrameGovernor.enabled
	_ambient = FrameGovernor.ambient_mode
	_tier = FrameGovernor.tier
	FrameGovernor.enabled = true
	FrameGovernor.ambient_mode = false
	FrameGovernor.poke()


func after_each() -> void:
	_release()
	FrameGovernor.tier = _tier
	FrameGovernor.ambient_mode = _ambient
	FrameGovernor.enabled = _enabled
	FrameGovernor.poke()


func _touch(pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = pressed
	FrameGovernor._input(e)


func _release() -> void:
	_touch(false)


## A thumb resting on the glass sends no events at all, so without tracking the press the session
## went idle under the finger and the next drag frame applied two frames of travel at once.
func test_a_pointer_on_the_glass_is_activity_even_when_it_sends_nothing() -> void:
	_touch(true)
	# Past the 8 s idle gate, but inside the 16 s staleness guard: a genuinely resting thumb.
	FrameGovernor._last_activity_s = Clock.ticks_s() - 10.0
	FrameGovernor._process(0.016)
	assert_false(FrameGovernor.idle, "a finger is down: stay at 60 fps")
	_release()
	FrameGovernor._last_activity_s = Clock.ticks_s() - 60.0
	FrameGovernor._process(0.016)
	assert_true(FrameGovernor.idle, "and once it lifts, the idle rate comes back")


func test_a_release_that_never_arrives_cannot_pin_the_session_at_60() -> void:
	_touch(true)
	FrameGovernor._last_activity_s = Clock.ticks_s() - FrameGovernor.POINTER_STALE_S - 1.0
	FrameGovernor._process(0.016)
	assert_false(FrameGovernor._pointer_down, "a pointer with no events for 16 s is treated as gone")
	assert_true(FrameGovernor.idle)


func test_losing_focus_clears_the_pointer() -> void:
	_touch(true)
	assert_true(FrameGovernor._pointer_down)
	FrameGovernor._notification(FrameGovernor.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_false(FrameGovernor._pointer_down, "no release arrives when the app goes away under a finger")


## The tier step takes the foreground frame, the vignette, the shafts, clouds and grass off the
## screen in one frame. Panning is the heaviest render path, so it is also the most likely thing to
## trip the slow-frame test: without this the pop landed in the middle of the player's own drag.
func test_a_tier_step_waits_until_the_player_is_not_mid_gesture() -> void:
	FrameGovernor.tier = 0
	_touch(true)
	watch_signals(FrameGovernor)
	FrameGovernor._set_tier(1)
	assert_eq(FrameGovernor.tier, 0, "nothing pops while a finger is down")
	assert_signal_not_emitted(FrameGovernor, "tier_changed")
	assert_eq(FrameGovernor._pending_tier, 1, "the step is remembered")
	_release()
	FrameGovernor._process(0.016)
	assert_eq(FrameGovernor.tier, 1, "and lands as soon as the hand is off the glass")
	assert_signal_emitted(FrameGovernor, "tier_changed")
	assert_eq(FrameGovernor._pending_tier, -1)


func test_a_tier_step_with_no_hand_on_the_glass_is_immediate() -> void:
	FrameGovernor.tier = 0
	_release()
	watch_signals(FrameGovernor)
	FrameGovernor._set_tier(1)
	assert_eq(FrameGovernor.tier, 1)
	assert_signal_emitted(FrameGovernor, "tier_changed")


func test_a_step_back_to_the_tier_it_is_already_on_clears_the_pending_one() -> void:
	FrameGovernor.tier = 0
	_touch(true)
	FrameGovernor._set_tier(1)
	assert_eq(FrameGovernor._pending_tier, 1)
	FrameGovernor._set_tier(0)
	assert_eq(FrameGovernor._pending_tier, -1, "the frames recovered before the hand lifted: no pop at all")
	_release()
	FrameGovernor._process(0.016)
	assert_eq(FrameGovernor.tier, 0)
