class_name WorldPan
extends Node
## One-finger map drag: the input arbiter between world taps and camera panning
## (docs/ARCHITECTURE.md §3.4, GDD §8.2). Main owns the camera and steps [member body].
##
## Arbitration:
## - It is the LAST child of Main, so its _unhandled_input sees every press the HUD did not take
##   (sheets, scrims and buttons consume theirs in the GUI pass) before any world layer. It never
##   consumes a press: the layers still get touch-down feedback in the same frame (I1).
## - A press arms a pan unless a sheet or modal card is open ([member blocked]), the press lies
##   within 24 dp of a side edge (spots.json safe_x, I2), or a world object claimed the pointer for
##   its own drag ([method claim_pointer]: a mossling stroke / pet).
## - Motion is read in _input (so a drag that crosses the dock keeps panning). The pan starts only
##   past gui/common/drag_threshold (24 px); then every node in GROUP_PRESS gets
##   cancel_world_press() (beds, décor, mosslings drop their pending tap / long-press),
##   [signal drag_started] fires, and the drag's motion and release events are consumed.
## - One input path: touch events (index 0) on devices, real mouse on desktop / web; the emulated
##   mouse events of a touch are ignored, as in every world layer.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

signal drag_started
## A drag or a home glide begins (Main folds the idle drift into the pan).
signal motion_started

enum Kind { NONE, PRESS, MOVE, RELEASE }

## Nodes that hold a pending world press implement cancel_world_press().
const GROUP_PRESS := &"world_press"

static var current: WorldPan = null

var body := PanBody.new()
## () -> bool: true while a sheet or modal card is open (no panning through it).
var blocked := Callable()
## Camera zoom (finger px -> pan px).
var zoom: float = 1.0
## Visible width in px (edge rule).
var view_width: float = 1080.0
var edge_px: float = 72.0
var threshold_px: float = 24.0
var velocity_window_s: float = 0.1
var double_tap_s: float = 0.3
var double_tap_slop_px: float = 48.0

var _armed: bool = false
var _armed_touch: bool = false
var _dragging: bool = false
var _claimed: bool = false
var _empty_press: bool = false
var _press := Vector2.ZERO
var _origin := Vector2.ZERO
var _raw0 := Vector2.ZERO
var _samples: Array[Vector3] = []
var _last_tap := Vector3(0.0, 0.0, -INF)
var _ev_pos := Vector2.ZERO
var _ev_touch: bool = false


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


## Reads the tokens (motion_tokens world.pan, spots.json frame/safe_x, the drag threshold).
func configure(pan_cfg: Dictionary, frame: Dictionary, safe_x: Dictionary) -> void:
	var dp := float(frame.get("px_per_dp", 3.0))
	var fw := float(frame.get("width_px", 1080.0))
	edge_px = float(safe_x.get("x0", 24.0 * dp / fw)) * fw
	threshold_px = float(ProjectSettings.get_setting("gui/common/drag_threshold", 24))
	velocity_window_s = float(pan_cfg.get("velocity_window_ms", 100.0)) / 1000.0
	double_tap_s = float(pan_cfg.get("double_tap_ms", 300.0)) / 1000.0
	double_tap_slop_px = float(pan_cfg.get("double_tap_slop_dp", 16.0)) * dp
	body.rubber_k = float(pan_cfg.get("rubber_k", 0.55))
	body.friction_per_s = float(pan_cfg.get("glide_friction_per_s", 4.5))
	body.min_speed = float(pan_cfg.get("glide_min_speed_dp_s", 4.0)) * dp
	body.max_speed = float(pan_cfg.get("glide_max_speed_dp_s", 1200.0)) * dp
	var sp := Motion.spring_params(StringName(String(pan_cfg.get("settle_spring", "move"))))
	body.spring_hz = sp.x
	body.spring_zeta = sp.y
	body.reduce_motion = Motion.reduce_motion


func offset() -> Vector2:
	return body.offset()


func is_dragging() -> bool:
	return _dragging


## A world object took this pointer for its own drag (a mossling stroke): no pan until release.
static func claim_pointer() -> void:
	if current != null:
		current._claimed = true


## Main: this press reached the end of the input chain (nothing in the world took it).
func mark_empty_press() -> void:
	if _armed and not _dragging and not _claimed:
		_empty_press = true


## Glides back to the home view (double tap on empty ground; instant under Reduce Motion).
func go_home() -> void:
	motion_started.emit()
	body.glide_to(Vector2.ZERO)


## Ends any drag in progress without inertia (a sheet opened, the app was suspended).
func cancel() -> void:
	if _dragging:
		body.release(Vector2.ZERO)
	_armed = false
	_dragging = false


func _unhandled_input(event: InputEvent) -> void:
	if _kind(event) != Kind.PRESS:
		return
	if body.is_moving():
		body.stop()  # a press catches a gliding map
	if _is_blocked() or _ev_pos.x < edge_px or _ev_pos.x > view_width - edge_px:
		return
	_armed = true
	_armed_touch = _ev_touch
	_dragging = false
	_empty_press = false
	_press = _ev_pos
	_samples.clear()


func _input(event: InputEvent) -> void:
	var kind := _kind(event)
	if kind == Kind.RELEASE:
		_on_release()
	elif kind == Kind.MOVE and _armed and _ev_touch == _armed_touch:
		_on_move()


func _on_move() -> void:
	if not _dragging:
		if _claimed or _is_blocked() or _ev_pos.distance_to(_press) < threshold_px:
			return
		_dragging = true
		_empty_press = false
		# start from the slop boundary so the map does not jump by the threshold
		_origin = _press + (_ev_pos - _press).normalized() * threshold_px
		motion_started.emit()
		body.begin_drag()
		_raw0 = body.raw
		get_tree().call_group(GROUP_PRESS, &"cancel_world_press")
		drag_started.emit()
	body.drag_to(_raw0 - (_ev_pos - _origin) / maxf(zoom, 0.01))
	_sample(body.raw)
	FrameGovernor.poke()
	get_viewport().set_input_as_handled()


func _on_release() -> void:
	var was_claimed := _claimed
	_claimed = false
	var mine := _armed and _ev_touch == _armed_touch
	if mine:
		_armed = false
	if mine and _dragging:
		_dragging = false
		body.release(_velocity())
		FrameGovernor.poke()
		get_viewport().set_input_as_handled()
		return
	if not body.is_active() and body.offset() != body.raw:
		motion_started.emit()
		body.release(Vector2.ZERO)  # a glide caught in the rubber band springs back to the edge
	if mine and _empty_press and not was_claimed:
		_on_empty_tap()


func _on_empty_tap() -> void:
	var now := Clock.ticks_s()
	var prev := Vector2(_last_tap.x, _last_tap.y)
	if now - _last_tap.z <= double_tap_s and prev.distance_to(_press) <= double_tap_slop_px:
		_last_tap = Vector3(0.0, 0.0, -INF)
		if body.offset().length() > 1.0:
			go_home()
		return
	_last_tap = Vector3(_press.x, _press.y, now)


func _sample(p: Vector2) -> void:
	var t := Clock.ticks_s()
	_samples.append(Vector3(p.x, p.y, t))
	while _samples.size() > 2 and t - _samples[0].z > velocity_window_s:
		_samples.remove_at(0)


## Pan velocity over the last velocity_window (px/s); 0 if the finger rested before lifting.
func _velocity() -> Vector2:
	if _samples.size() < 2:
		return Vector2.ZERO
	var a := _samples[0]
	var b := _samples[_samples.size() - 1]
	var dt := b.z - a.z
	if dt <= 0.001 or Clock.ticks_s() - b.z > velocity_window_s:
		return Vector2.ZERO
	return Vector2(b.x - a.x, b.y - a.y) / dt


func _is_blocked() -> bool:
	return blocked.is_valid() and bool(blocked.call())


## Classifies [param event] on the one input path (touch index 0, or a real left mouse button) and
## stores its position in _ev_pos / _ev_touch.
func _kind(event: InputEvent) -> Kind:
	var st := event as InputEventScreenTouch
	if st != null:
		if st.index != 0:
			return Kind.NONE
		_ev_pos = st.position
		_ev_touch = true
		return Kind.PRESS if st.pressed else Kind.RELEASE
	var sd := event as InputEventScreenDrag
	if sd != null:
		if sd.index != 0:
			return Kind.NONE
		_ev_pos = sd.position
		_ev_touch = true
		return Kind.MOVE
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return Kind.NONE
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return Kind.NONE
		_ev_pos = mb.position
		_ev_touch = false
		return Kind.PRESS if mb.pressed else Kind.RELEASE
	var mm := event as InputEventMouseMotion
	if mm != null and mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_ev_pos = mm.position
		_ev_touch = false
		return Kind.MOVE
	return Kind.NONE
