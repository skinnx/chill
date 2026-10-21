class_name UiSlider
extends Control
## Volume slider (Art Bible §9.5): track 12 px r-pill in toggle_off_track with a primary fill to
## the thumb; thumb Ø 72 surface_hi on e1; 11 detents (step 10) with a TICK per detent in Full
## haptics. The whole row is the hit; a drag starts after the project's 24 px threshold, a tap
## jumps to the nearest detent. Values are 0..100 (Settings volume_*).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

signal value_changed(value: int)

const TRACK_H := 12.0
const THUMB_D := 72.0
const STEP := 10
const MAX := 100
## 48 dp touch height (I2).
const MIN_H := 144.0

var value: int = 80
var _dragging: bool = false
var _press_x: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(0.0, MIN_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func set_value_silent(v: int) -> void:
	value = clampi(v, 0, MAX)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_press_x = mb.position.x
			_dragging = false
			AudioDirector.play_cue(PressFeedback.CUE_TOUCH)
		else:
			_set_from_x(mb.position.x)
			_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		var mm := event as InputEventMouseMotion
		if not _dragging and absf(mm.position.x - _press_x) >= float(ProjectSettings.get_setting(
				"gui/common/drag_threshold", 24)):
			_dragging = true
		if _dragging:
			_set_from_x(mm.position.x)
		accept_event()


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
	draw_style_box(UiTokens.fill_box(UiTokens.color(&"toggle_off_track"), TRACK_H * 0.5), tr_rect)
	var u := float(value) / float(MAX)
	var fill := Rect2(tr_rect.position, Vector2(tr_rect.size.x * u, TRACK_H))
	if fill.size.x > 0.5:
		draw_style_box(UiTokens.fill_box(UiTokens.color(&"primary"), TRACK_H * 0.5), fill)
	var c := Vector2(tr_rect.position.x + tr_rect.size.x * u, size.y * 0.5)
	var thumb := UiTokens.fill_box(UiTokens.color(&"surface_hi"), THUMB_D * 0.5, UiTokens.E1)
	thumb.border_color = UiTokens.tinted(&"ink", UiTokens.alpha(&"divider"))
	thumb.set_border_width_all(roundi(UiTokens.PX_PER_DP))
	draw_style_box(thumb, Rect2(c - Vector2(THUMB_D, THUMB_D) * 0.5, Vector2(THUMB_D, THUMB_D)))
