extends GutTest
## InputPrecision (scripts/core/input_precision.gd, ARCHITECTURE §3.5): raw-pointer mode for the
## gestures that integrate the path of a finger. The counted holders are what keep two overlapping
## gestures from restoring accumulation under one another.

# Tests read Dictionaries and engine singletons; each conversion is explicit at the read site
# (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const A := &"test_a"
const B := &"test_b"

var _was: bool = true


func before_each() -> void:
	InputPrecision.release_all()
	_was = Input.is_using_accumulated_input()


func after_each() -> void:
	InputPrecision.release_all()
	Input.set_use_accumulated_input(_was)


func test_godot_accumulates_input_by_default() -> void:
	# The premise of the whole helper, re-checked against the engine the project ships on: with
	# accumulation on, a handler sees at most one motion event per rendered frame.
	assert_true(_was, "Godot 4.7.2 boots with input accumulation on")
	assert_false(ProjectSettings.get_setting("input_devices/buffering/agile_event_flushing", false),
			"agile flushing stays off: it only adds flushes before PHYSICS steps (30 Hz here) and is Android-only")


func test_one_holder_turns_accumulation_off_and_back_on() -> void:
	Input.set_use_accumulated_input(true)
	InputPrecision.acquire(A)
	assert_false(Input.is_using_accumulated_input(), "the gesture reads the pointer raw")
	assert_true(InputPrecision.is_precise())
	assert_true(InputPrecision.holds(A))
	InputPrecision.release(A)
	assert_true(Input.is_using_accumulated_input(), "and the frame-rate default comes back")
	assert_false(InputPrecision.is_precise())


func test_acquiring_twice_under_one_name_is_a_single_claim() -> void:
	Input.set_use_accumulated_input(true)
	InputPrecision.acquire(A)
	InputPrecision.acquire(A)
	assert_eq(InputPrecision.holder_count(), 1, "the same gesture cannot hold twice")
	InputPrecision.release(A)
	assert_true(Input.is_using_accumulated_input())


func test_overlapping_holders_do_not_restore_under_one_another() -> void:
	Input.set_use_accumulated_input(true)
	InputPrecision.acquire(A)
	InputPrecision.acquire(B)
	InputPrecision.release(A)
	assert_false(Input.is_using_accumulated_input(), "B is still stirring")
	InputPrecision.release(B)
	assert_true(Input.is_using_accumulated_input(), "the last one out puts it back")


func test_releasing_an_unknown_holder_changes_nothing() -> void:
	Input.set_use_accumulated_input(true)
	InputPrecision.release(B)
	assert_true(Input.is_using_accumulated_input())
	InputPrecision.acquire(A)
	InputPrecision.release(B)
	assert_false(Input.is_using_accumulated_input(), "A still holds it")
	assert_eq(InputPrecision.holder_count(), 1)


func test_release_all_is_the_safety_net_for_a_cancelled_gesture() -> void:
	Input.set_use_accumulated_input(true)
	InputPrecision.acquire(A)
	InputPrecision.acquire(B)
	InputPrecision.release_all()
	assert_true(Input.is_using_accumulated_input())
	assert_eq(InputPrecision.holder_count(), 0)


func test_it_restores_what_it_found_not_a_hard_coded_true() -> void:
	# A device or a QA run that deliberately starts without accumulation keeps that afterwards.
	Input.set_use_accumulated_input(false)
	InputPrecision.acquire(A)
	InputPrecision.release(A)
	assert_false(Input.is_using_accumulated_input(), "the helper puts back what was in force")
