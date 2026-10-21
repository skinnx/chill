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
## Touch-down: the thumb stretches toward the far side (M3-Expressive switch), a visible state on
## the very first frame.
const PRESS_STRETCH := 0.32

## QA stills (--qa-press=toggle): draw the touch-down thumb without a touch.
var force_pressed: bool = false:
	set(v):
		force_pressed = v
		queue_redraw()
var _t: float = 0.0
var _tween: Tween
## Round 5: track, thumb and check are batched leaves (UiSurface x 2 + the UI icon atlas).
var _track: UiSurface
var _thumb: UiSurface
var _check: TextureRect


func _init() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(TRACK_W, TRACK_H)
	toggled.connect(_on_toggled)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	_track = UiSurface.new()
	_track.name = "Track"
	_track.radius = UiSurface.PILL
	add_child(_track, false, Node.INTERNAL_MODE_FRONT)
	set_meta(UiSurface.META_OWNER, _track)
	var holder := Control.new()
	holder.name = "ThumbLayer"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_meta(UiSurface.META_OWNER, true)
	add_child(holder, false, Node.INTERNAL_MODE_FRONT)
	_thumb = UiSurface.new()
	_thumb.name = "Thumb"
	_thumb.radius = UiSurface.PILL
	_thumb.elevation = UiTokens.E1
	holder.add_child(_thumb)
	_check = TextureRect.new()
	_check.name = "Check"
	_check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_check.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_check.size = Vector2(CHECK_PX, CHECK_PX)
	holder.add_child(_check)


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
	# day tokens for the switch itself (the leaf track and the light thumb read on both schemes)
	_track.color = UiTokens.sc(&"toggle_off_track").lerp(UiTokens.color(&"leaf"), _t)
	_track.border_color = UiTokens.sc(&"toggle_off_border")
	_track.border_px = roundf(BORDER_DP * UiTokens.PX_PER_DP * (1.0 - _t))
	_track.position = r.position
	_track.size = r.size
	var d := TRACK_H - THUMB_INSET * 2.0
	var x0 := r.position.x + THUMB_INSET + d * 0.5
	var x1 := r.end.x - THUMB_INSET - d * 0.5
	var c := Vector2(lerpf(x0, x1, _t), r.get_center().y)
	var m := get_draw_mode()
	var stretch := d * PRESS_STRETCH if force_pressed or m == DRAW_PRESSED or m == DRAW_HOVER_PRESSED else 0.0
	# stretch toward the side the thumb will travel to
	var sx := c.x - d * 0.5 - (stretch if _t > 0.5 else 0.0)
	_thumb.color = UiTokens.color(&"surface_hi")
	_thumb.position = Vector2(sx, c.y - d * 0.5)
	_thumb.size = Vector2(d + stretch, d)
	if _check.texture == null:
		var at: Variant = Icons.ui_atlas().get(Icons.atlas_key(&"check", CHECK_PX))
		_check.texture = at if at is Texture2D else Icons.texture(&"check", CHECK_PX)
	_check.position = c - Vector2(CHECK_PX, CHECK_PX) * 0.5
	UiBatch.set_alpha(_check, clampf((_t - 0.5) * 2.0, 0.0, 1.0))
	_check.visible = _t > 0.5
