class_name PointerGate
extends RefCounted
## Swallows the rest of ONE pointer gesture (docs/ARCHITECTURE.md §3.5): after [method begin] with
## the gesture's press, [method swallow] returns true for every pointer event of that gesture -
## a touch and its emulated mouse twin (Input dispatches the emulated event first), their moves
## and releases - and lets go after the gesture's final release. Used for the ambient wake (the
## first tap only wakes) so a woken dock tab or the world behind never acts on that tap.

## Safety net: a gesture whose release never arrives (focus lost) stops being swallowed.
const MAX_S := 5.0

var active: bool = false
var _touch: bool = false
var _since_ms: int = 0


## True for a primary press on either path (touch, emulated or real left mouse button).
static func is_press(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	if mb != null:
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	var st := event as InputEventScreenTouch
	return st != null and st.pressed and st.index == 0


static func is_pointer(event: InputEvent) -> bool:
	return event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventScreenTouch \
			or event is InputEventScreenDrag


## Starts swallowing the gesture that [param press] began.
func begin(press: InputEvent) -> void:
	active = true
	_touch = press is InputEventScreenTouch or press.device == InputEvent.DEVICE_ID_EMULATION
	_since_ms = Time.get_ticks_msec()


func swallow(event: InputEvent) -> bool:
	if not active or not is_pointer(event):
		return false
	if Time.get_ticks_msec() - _since_ms > int(MAX_S * 1000.0):
		active = false
		return false
	if _touch:
		var st := event as InputEventScreenTouch
		if st != null and not st.pressed and st.index == 0:
			active = false  # the touch's own release ends it (its emulated twin came first)
		return true
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		active = false
	return true
