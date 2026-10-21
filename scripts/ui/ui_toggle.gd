class_name UiToggle
extends BaseButton
## Settings switch (Art Bible §9.5: 156 x 90 at the row's right; the whole row is the hit, so the
## row forwards its taps here). On: leaf track + surface_hi thumb with a check; off:
## toggle_off_track with a 1 dp toggle_off_border (ink_2, 5.8:1, WCAG 1.4.11) and the thumb left.
## Thumb moves on `micro`; the track colour crossfades on `short` (§10.3); S15 on change.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const TRACK_W := 156.0
const TRACK_H := 90.0
const THUMB_INSET := 9.0
const BORDER_DP := 1.0
const CHECK_PX := 36.0
const CUE_TOGGLE := &"S15"

var _t: float = 0.0
var _tween: Tween


func _init() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(TRACK_W, TRACK_H)
	toggled.connect(_on_toggled)


func _ready() -> void:
	_t = 1.0 if button_pressed else 0.0


## Sets the state without the cue or animation (initial values, setting changes from elsewhere).
func set_silent(on: bool) -> void:
	set_pressed_no_signal(on)
	_t = 1.0 if on else 0.0
	queue_redraw()


func _on_toggled(on: bool) -> void:
	AudioDirector.play_cue(CUE_TOGGLE, {"on": on})
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_t, _t, 1.0 if on else 0.0, Motion.duration(&"micro")) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	FrameGovernor.hold_for(Motion.duration(&"short"))


func _set_t(v: float) -> void:
	_t = v
	queue_redraw()


func _draw() -> void:
	var r := Rect2((size - Vector2(TRACK_W, TRACK_H)) * 0.5, Vector2(TRACK_W, TRACK_H))
	var off := UiTokens.color(&"toggle_off_track")
	var on := UiTokens.color(&"leaf")
	var track := UiTokens.fill_box(off.lerp(on, _t), TRACK_H * 0.5)
	var bw := roundi(BORDER_DP * UiTokens.PX_PER_DP * (1.0 - _t))
	if bw > 0:
		track.border_color = UiTokens.color(&"toggle_off_border")
		track.set_border_width_all(bw)
	draw_style_box(track, r)
	var d := TRACK_H - THUMB_INSET * 2.0
	var x0 := r.position.x + THUMB_INSET + d * 0.5
	var x1 := r.end.x - THUMB_INSET - d * 0.5
	var c := Vector2(lerpf(x0, x1, _t), r.get_center().y)
	var thumb := UiTokens.fill_box(UiTokens.color(&"surface_hi"), d * 0.5, UiTokens.E1)
	draw_style_box(thumb, Rect2(c - Vector2(d, d) * 0.5, Vector2(d, d)))
	if _t > 0.5:
		var tex := Icons.texture(&"check", CHECK_PX)
		if tex != null:
			var m := Color(1, 1, 1, clampf((_t - 0.5) * 2.0, 0.0, 1.0))
			draw_texture_rect(tex, Rect2(c - Vector2(CHECK_PX, CHECK_PX) * 0.5, Vector2(CHECK_PX, CHECK_PX)), false, m)
