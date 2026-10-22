class_name WorldPan
extends Node
## The ONE world input arbiter (docs/ARCHITECTURE.md §3.4-3.5, GDD §2.5, §8.2, §8.4): it picks the
## single world target of every press and decides between that tap and a map drag. Main owns the
## camera and steps [member body].
##
## Input & hit-testing contract (ARCHITECTURE §3.5):
## - One input path in the world: touch index 0 on devices, the real left mouse button on desktop
##   and web. Emulated mouse events (a touch's twin, device -1) are ignored here, and no world
##   layer reads input itself any more, so nothing in the world can act twice for one touch.
## - It is the LAST child of Main, so its _unhandled_input sees every press the HUD did not take
##   (sheets, scrims, bands and buttons consume theirs in the GUI pass).
## - A press asks every node in [constant GROUP_HIT] for its best candidate
##   (world_hit(canvas_pos, slop_px) -> {prio, inside, core?, d, key, drag?}) and picks ONE: a
##   target whose core contains the aim point beats one whose generous outer hit does, which beats
##   one only reached through the fat-finger slop ([member slop_px] ~9 dp); then the higher
##   GDD §2.5 priority; then the nearer centre. On touch
##   the aim point sits [member aim_up_px] above the contact (contacts land low, 02 §1.1). The
##   winner gets world_press() at once (feedback in the same frame, I1).
## - The action fires on RELEASE (world_release(key, pos, act = true)) only if the finger stayed
##   within [member threshold_px] (the pan threshold: one number, no gap where neither or both
##   happen). Moving further cancels the tap (act = false) and starts the pan. A target that
##   claims the drag (a mossling: stroke = pet) gets world_drag() instead and never pans.
## - A press that lands while the map glides only catches it (no tap after a fling). A press while
##   a sheet or modal card is open ([member blocked]) does nothing (the GUI consumed it anyway).
## - No pan STARTS within 24 dp of a side edge (spots.json safe_x, I2); taps there still work.
## - A press that finds no target is an empty press: two of them within double_tap_ms glide home.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")
@warning_ignore_start("unsafe_method_access")

signal drag_started
## A drag or a home glide begins (Main folds the idle drift into the pan).
signal motion_started
## A world target was picked for a press (QA, tests): its layer node and key.
signal target_pressed(layer: Node, key: Variant)

enum Kind { NONE, PRESS, MOVE, RELEASE }

## Nodes that offer world targets implement world_hit / world_press / world_release (and
## world_drag when their candidate sets "drag": true).
const GROUP_HIT := &"world_hit"
## GDD §2.5 hit priority, highest first (choose-a-bed mode lifts beds with room above all).
const PRIO_CHOOSE_BED := 7
const PRIO_MOSSLING := 6
const PRIO_READY_BED := 5
const PRIO_PROP := 4
const PRIO_DECOR := 3
const PRIO_BED := 2
const PRIO_STREAM := 1
## Fat-finger slop around every world hit area and the upward aim offset of a touch (dp).
const SLOP_DP := 9.0
const AIM_UP_DP := 3.0

static var current: WorldPan = null

var body := PanBody.new()
## () -> bool: true while a sheet or modal card is open (no panning or world taps through it).
var blocked := Callable()
## Camera zoom (finger px -> pan px).
var zoom: float = 1.0
## Visible width in px (edge rule).
var view_width: float = 1080.0
var edge_px: float = 72.0
var threshold_px: float = 24.0
var slop_px: float = 27.0
var aim_up_px: float = 9.0
var velocity_window_s: float = 0.1
var double_tap_s: float = 0.3
var double_tap_slop_px: float = 48.0

var _down: bool = false
var _down_touch: bool = false
var _armed: bool = false
var _dragging: bool = false
var _press := Vector2.ZERO
var _origin := Vector2.ZERO
var _raw0 := Vector2.ZERO
var _samples: Array[Vector3] = []
var _last_tap := Vector3(0.0, 0.0, -INF)
var _ev_pos := Vector2.ZERO
var _ev_touch: bool = false
## The press's world target (null = none) and its candidate.
var _target: Node = null
var _target_key: Variant = null
var _target_drag: bool = false
var _empty: bool = false


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
	slop_px = float(pan_cfg.get("tap_slop_dp", SLOP_DP)) * dp
	aim_up_px = float(pan_cfg.get("aim_up_dp", AIM_UP_DP)) * dp
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


## The world target held by the current press (null when none).
func target() -> Node:
	return _target


## Glides back to the home view (double tap on empty ground; instant under Reduce Motion).
func go_home() -> void:
	motion_started.emit()
	body.glide_to(Vector2.ZERO)


## Ends any drag in progress without inertia and drops the pending world tap (a sheet opened, the
## app was suspended).
func cancel() -> void:
	if _dragging:
		body.release(Vector2.ZERO)
	_release_target(false)
	_armed = false
	_dragging = false
	_down = false


## Picks the one world target for a press at [param canvas_pos] (viewport px) among [param layers]
## (default: the GROUP_HIT nodes). Returns {} or the winning candidate with "layer" added.
func resolve(canvas_pos: Vector2, layers: Array = []) -> Dictionary:
	if layers.is_empty() and is_inside_tree():
		layers = get_tree().get_nodes_in_group(GROUP_HIT)
	var best := {}
	for n: Variant in layers:
		var layer := n as Node
		if layer == null or not is_instance_valid(layer) or not layer.is_inside_tree():
			continue
		if layer is CanvasItem and not (layer as CanvasItem).is_visible_in_tree():
			continue
		var c: Dictionary = layer.call(&"world_hit", canvas_pos, slop_px)
		if c.is_empty():
			continue
		c["layer"] = layer
		if best.is_empty() or better(c, best):
			best = c
	return best


## Candidate order: the hit tier (core > the rest of the hit area > only within the slop), then
## priority, then the nearer centre. A candidate's "core" (default: its whole "inside") lets an
## optional target with a generous hit (a 64 dp décor piece over a bed's edge) keep the generous
## hit for empty ground without stealing presses that land squarely on a core target.
static func better(a: Dictionary, b: Dictionary) -> bool:
	var ta := tier(a)
	var tb := tier(b)
	if ta != tb:
		return ta > tb
	var pa := int(a.get("prio", 0))
	var pb := int(b.get("prio", 0))
	if pa != pb:
		return pa > pb
	return float(a.get("d", INF)) < float(b.get("d", INF))


## 2 = core hit, 1 = inside the (generous) hit area, 0 = reached through the slop only.
static func tier(c: Dictionary) -> int:
	if not bool(c.get("inside", false)):
		return 0
	return 2 if bool(c.get("core", true)) else 1


## Shared helper for layers: a circle candidate (centre / radius in the layer's px; the canvas
## point already converted). Returns {} when [param p] is beyond radius + slop.
static func circle_hit(p: Vector2, centre: Vector2, radius: float, slop: float, prio: int, key: Variant) -> Dictionary:
	var d := p.distance_to(centre)
	if d > radius + slop:
		return {}
	return {"prio": prio, "inside": d <= radius, "d": d, "key": key}


## Shared helper for layers: a rect candidate.
static func rect_hit(p: Vector2, rect: Rect2, slop: float, prio: int, key: Variant) -> Dictionary:
	if not rect.grow(slop).has_point(p):
		return {}
	return {"prio": prio, "inside": rect.has_point(p), "d": p.distance_to(rect.get_center()), "key": key}


func _unhandled_input(event: InputEvent) -> void:
	if _kind(event) != Kind.PRESS:
		return
	if _down and _ev_touch != _down_touch:
		return  # the other path while a pointer is down (a real mouse during a touch)
	var gliding := body.is_moving()
	if gliding:
		body.stop()  # a press catches a gliding map, and does nothing else (no tap after a fling)
	_release_target(false)
	_down = true
	_down_touch = _ev_touch
	_dragging = false
	_armed = false
	_empty = false
	_press = _ev_pos
	_samples.clear()
	if _is_blocked():
		_down = false
		return
	if not gliding:
		var aim := _ev_pos - Vector2(0.0, aim_up_px if _ev_touch else 0.0)
		var hit := resolve(aim)
		if not hit.is_empty():
			_target = hit["layer"]
			_target_key = hit.get("key")
			_target_drag = bool(hit.get("drag", false))
			_target.call(&"world_press", _target_key, _ev_pos)
			target_pressed.emit(_target, _target_key)
			get_viewport().set_input_as_handled()
		else:
			_empty = true
	if _target_drag or _ev_pos.x < edge_px or _ev_pos.x > view_width - edge_px:
		return
	_armed = true


func _input(event: InputEvent) -> void:
	var kind := _kind(event)
	if not _down or _ev_touch != _down_touch:
		return
	if kind == Kind.RELEASE:
		_on_release()
	elif kind == Kind.MOVE:
		_on_move()


func _on_move() -> void:
	if _target != null:
		if _target_drag:
			_target.call(&"world_drag", _target_key, _ev_pos)
			get_viewport().set_input_as_handled()
			return
		if _ev_pos.distance_to(_press) > threshold_px:
			_release_target(false)  # the finger left the tap: no action on release
	if _ev_pos.distance_to(_press) > threshold_px:
		_empty = false
	if not _armed:
		return
	if not _dragging:
		if _is_blocked() or _ev_pos.distance_to(_press) < threshold_px:
			return
		_dragging = true
		# start from the slop boundary so the map does not jump by the threshold
		_origin = _press + (_ev_pos - _press).normalized() * threshold_px
		motion_started.emit()
		body.begin_drag()
		_raw0 = body.raw
		drag_started.emit()
	body.drag_to(_raw0 - (_ev_pos - _origin) / maxf(zoom, 0.01))
	_sample(body.raw)
	FrameGovernor.poke()
	get_viewport().set_input_as_handled()


func _on_release() -> void:
	_down = false
	_armed = false
	if _dragging:
		_dragging = false
		body.release(_velocity())
		FrameGovernor.poke()
		get_viewport().set_input_as_handled()
		return
	if not body.is_active() and body.offset() != body.raw:
		motion_started.emit()
		body.release(Vector2.ZERO)  # a glide caught in the rubber band springs back to the edge
	if _target != null:
		# a sheet or card that opened during the press (a timer, a sim event) takes the tap
		var act := not _is_blocked() and (_target_drag or _ev_pos.distance_to(_press) <= threshold_px)
		_release_target(act)
		get_viewport().set_input_as_handled()
		return
	if _empty and _ev_pos.distance_to(_press) <= threshold_px:
		_on_empty_tap()
	_empty = false


## Ends the held target's press: [param act] fires its action (a tap), false only springs back.
func _release_target(act: bool) -> void:
	var t := _target
	var key: Variant = _target_key
	_target = null
	_target_key = null
	_target_drag = false
	if t != null and is_instance_valid(t):
		t.call(&"world_release", key, _ev_pos, act)


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
