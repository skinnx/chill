class_name InputPrecision
extends RefCounted
## Raw-pointer mode for the gestures that integrate the PATH of a finger (ARCHITECTURE §3.5).
##
## Godot accumulates input by default: "all input events generated during a frame will be merged
## and emitted when the frame is done rendering. Therefore, this limits the number of input
## method calls per second to the rendering FPS" (Input.set_use_accumulated_input; verified on
## 4.7.2 — Input.is_using_accumulated_input() is true at boot, and
## input_devices/buffering/agile_event_flushing is false, so events reach the tree once per
## rendered frame). The docs name freehand drawing as the case to turn it off for.
##
## That default is right for every gesture that only needs the LATEST position — the map pan, a
## carried décor piece, a slider, a petal under the thumb — because those are redrawn once per
## frame anyway, so extra samples would change nothing on screen. It is wrong for a gesture whose
## meaning is the path itself: the tea stir sums |Δθ| around the pot, so at 30 fps it measures a
## fast circle from half as many chords as at 60 fps and the same hand movement counts for less.
## The stir is this project's only path-integrating gesture, so it is the only holder (TeaPot).
##
## Holders are counted by name, so two overlapping gestures can never restore accumulation under
## one another, and re-acquiring under the same name is a no-op. The value in force when the first
## holder arrived is what gets restored, so a device or a test that starts without accumulation
## keeps that. [method release_all] is the safety net for a cancelled gesture, a sheet that closes
## mid-drag, an app that loses focus and a test that fails half way through.

## Holder name -> true. Empty = accumulation is whatever the project set.
static var _holders: Dictionary[StringName, bool] = {}
## The accumulation setting to put back when the last holder leaves.
static var _restore: bool = true


## Takes raw-pointer mode in the name of [param holder] (idempotent per name).
static func acquire(holder: StringName) -> void:
	if holder == &"":
		push_error("InputPrecision.acquire: a holder needs a name")
		return
	if _holders.has(holder):
		return
	if _holders.is_empty():
		_restore = Input.is_using_accumulated_input()
		Input.set_use_accumulated_input(false)
	_holders[holder] = true


## Gives up [param holder]'s claim; accumulation returns when the last holder leaves.
static func release(holder: StringName) -> void:
	if not _holders.erase(holder):
		return
	if _holders.is_empty():
		Input.set_use_accumulated_input(_restore)


## Drops every claim at once (a cancelled gesture, FOCUS_OUT, a test tearing down).
static func release_all() -> void:
	if _holders.is_empty():
		return
	_holders.clear()
	Input.set_use_accumulated_input(_restore)


## True while at least one holder has raw-pointer mode.
static func is_precise() -> bool:
	return not _holders.is_empty()


static func holder_count() -> int:
	return _holders.size()


## True when [param holder] currently holds a claim (tests, debug overlays).
static func holds(holder: StringName) -> bool:
	return _holders.has(holder)
