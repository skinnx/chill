class_name UiSlider
extends Control
## Volume slider (Art Bible §9.5): track 12 px r-pill in toggle_off_track with a primary fill to
## the thumb; thumb Ø 72 surface_hi on e1; 11 detents (step 10) with a TICK per detent in Full
## haptics. The whole row is the hit; a HORIZONTAL drag starts after the project's 24 px threshold,
## a tap jumps to the nearest detent; a vertical gesture over it scrolls the sheet and never moves
## the value (ARCHITECTURE §3.5). Values are 0..100 (Settings volume_*).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

signal value_changed(value: int)

## A press is PENDING until it moves: horizontally past the drag threshold it becomes the slider's
## DRAG; vertically past the 10 dp slop it is the sheet's SCROLL and the value never changes.
enum Gesture { NONE, PENDING, DRAG, SCROLL }

const TRACK_H := 12.0
const THUMB_D := 72.0
const STEP := 10
const MAX := 100
## 48 dp touch height (I2).
const MIN_H := 144.0

var value: int = 80
var _state: Gesture = Gesture.NONE
var _press_at := Vector2.ZERO
## Round 5: track, fill and thumb are batched UiSurfaces.
var _track: UiSurface
var _fill: UiSurface
var _thumb: UiSurface


func _init() -> void:
	custom_minimum_size = Vector2(0.0, MIN_H)
	# PASS: inside a sheet's scroll list a vertical drag over the slider scrolls the list
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_NONE
	_track = UiSurface.make(Color.WHITE, UiSurface.PILL)
	add_child(_track, false, Node.INTERNAL_MODE_FRONT)
	set_meta(UiSurface.META_OWNER, _track)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_meta(UiSurface.META_OWNER, true)
	add_child(holder, false, Node.INTERNAL_MODE_FRONT)
	_fill = UiSurface.make(Color.WHITE, UiSurface.PILL)
	holder.add_child(_fill)
	var top := Control.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.set_meta(UiSurface.META_OWNER, true)
	holder.add_child(top)
	_thumb = UiSurface.make(Color.WHITE, UiSurface.PILL, UiTokens.E1)
	top.add_child(_thumb)


func set_value_silent(v: int) -> void:
	value = clampi(v, 0, MAX)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_press_at = mb.global_position
			_state = Gesture.PENDING
			AudioDirector.play_cue(PressFeedback.CUE_TOUCH)
		else:
			# a tap (the finger stayed put) jumps to the nearest detent; a drag ends where it is;
			# a vertical gesture was the sheet's scroll and changes nothing
			if _state == Gesture.PENDING or _state == Gesture.DRAG:
				_set_from_x(mb.position.x)
			_state = Gesture.NONE
		# the press and the release travel on to the scroll list (it must see both to scroll)
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		var mm := event as InputEventMouseMotion
		if _state == Gesture.PENDING:
			var d := (mm.global_position - _press_at).abs()
			if d.y > TapGuard.slop_px() and d.y >= d.x:
				_state = Gesture.SCROLL
			elif d.x >= float(ProjectSettings.get_setting("gui/common/drag_threshold", 24)) and d.x > d.y:
				_state = Gesture.DRAG
			elif maxf(d.x, d.y) > TapGuard.slop_px():
				_state = Gesture.SCROLL
		if _state == Gesture.DRAG:
			_set_from_x(mm.position.x)
			accept_event()  # a horizontal drag is the slider's alone


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCROLL_BEGIN and _state == Gesture.PENDING:
		_state = Gesture.SCROLL  # the list started scrolling: this gesture is not for the slider


func _track_rect() -> Rect2:
	var x0 := THUMB_D * 0.5
	return Rect2(x0, (size.y - TRACK_H) * 0.5, maxf(size.x - THUMB_D, 1.0), TRACK_H)


func _set_from_x(x: float) -> void:
	var tr_rect := _track_rect()
	var u := clampf((x - tr_rect.position.x) / tr_rect.size.x, 0.0, 1.0)
	var v := clampi(roundi(u * float(MAX) / float(STEP)) * STEP, 0, MAX)
	if v != value:
		value = v
		Haptics.play(Haptics.TICK)
		value_changed.emit(value)
		queue_redraw()


func _draw() -> void:
	var tr_rect := _track_rect()
	_track.color = UiTokens.sc(&"toggle_off_track")
	_track.position = tr_rect.position
	_track.size = tr_rect.size
	var u := float(value) / float(MAX)
	_fill.color = UiTokens.sc(&"primary")
	_fill.position = tr_rect.position
	_fill.size = Vector2(maxf(tr_rect.size.x * u, TRACK_H), TRACK_H)
	_fill.visible = u > 0.0
	var c := Vector2(tr_rect.position.x + tr_rect.size.x * u, size.y * 0.5)
	_thumb.color = UiTokens.color(&"surface_hi")
	_thumb.border_color = UiTokens.tinted(&"ink", UiTokens.alpha(&"divider"))
	_thumb.border_px = UiTokens.PX_PER_DP
	_thumb.position = c - Vector2(THUMB_D, THUMB_D) * 0.5
	_thumb.size = Vector2(THUMB_D, THUMB_D)
