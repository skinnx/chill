class_name TapGuard
extends RefCounted
## Makes every UI button forgiving and predictable on a phone (docs/ARCHITECTURE.md §3.5,
## GDD §8.2, §8.4). PressFeedback.attach wires it to every BaseButton:
##  * Press slop: a press whose finger travels more than [constant SLOP_DP] (10 dp) from where it
##    landed is cancelled (no action on release, the press visual springs back), so a scroll, a
##    swipe or a sloppy drag never fires a button. Sliding off the rect cancels too (BaseButton).
##  * Scroll-through: a button inside a ScrollContainer passes its presses on to the list
##    (MOUSE_FILTER_PASS), so a drag that starts on a button scrolls the sheet; the list's
##    scroll_deadzone equals the slop, and its NOTIFICATION_SCROLL_BEGIN cancels the button press.
##  * Fling catch: a press while its list is still moving (a fling) only stops the list.
##  * Debounce: one action per press - a second press within [constant DEBOUNCE_MS] of the last
##    action on the same button is swallowed (fast double taps on Plant, Collect all, a dock tab).
## One path: the guard reads the emulated-mouse twin of a touch and the real mouse alike
## (both carry global_position), and BaseButton itself fires once per tap (on the first release
## of the pair; the second finds no press attempt).

# Data boundary: values read from metadata / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const SLOP_DP := 10.0
const DEBOUNCE_MS := 350
## A list whose scroll value changed this recently is still moving (fling or drag).
const MOVING_MS := 90
const META_FROM := &"_tap_from"
const META_FIRED := &"_tap_fired_ms"
const META_SCROLL_MS := &"_tap_scroll_ms"
const META_WIRED := &"_tap_guard"


static func slop_px() -> float:
	return SLOP_DP * UiTokens.PX_PER_DP


static func attach(button: BaseButton) -> void:
	if button.has_meta(META_WIRED):
		return
	button.set_meta(META_WIRED, true)
	button.gui_input.connect(_on_input.bind(button))
	button.pressed.connect(func() -> void: button.set_meta(META_FIRED, Time.get_ticks_msec()))
	if button.is_inside_tree():
		_adopt_scroll(button)
	button.tree_entered.connect(_adopt_scroll.bind(button))


## True when [param c] sits inside a ScrollContainer (it then passes presses on to the list).
static func scroll_of(c: Control) -> ScrollContainer:
	var n := c.get_parent()
	while n != null:
		if n is ScrollContainer:
			return n as ScrollContainer
		n = n.get_parent()
	return null


## Cancels [param button]'s current press: no action on release, the press visual springs back.
static func cancel(button: BaseButton) -> void:
	button.remove_meta(META_FROM)
	button.notification(Control.NOTIFICATION_SCROLL_BEGIN)
	PressFeedback.up(button)


## Marks a list moving whenever it scrolls (fling catch); idempotent.
static func watch_scroll(sc: ScrollContainer) -> void:
	if sc.has_meta(META_WIRED):
		return
	sc.set_meta(META_WIRED, true)
	sc.scroll_deadzone = roundi(slop_px())
	var mark := func(_v: float) -> void: sc.set_meta(META_SCROLL_MS, Time.get_ticks_msec())
	sc.get_v_scroll_bar().value_changed.connect(mark)
	sc.get_h_scroll_bar().value_changed.connect(mark)


static func is_moving(sc: ScrollContainer) -> bool:
	return sc != null and Time.get_ticks_msec() - int(sc.get_meta(META_SCROLL_MS, -100000)) < MOVING_MS


static func _adopt_scroll(button: BaseButton) -> void:
	var sc := scroll_of(button)
	if sc == null:
		return
	watch_scroll(sc)
	if button.mouse_filter == Control.MOUSE_FILTER_STOP:
		button.mouse_filter = Control.MOUSE_FILTER_PASS


static func _on_input(event: InputEvent, button: BaseButton) -> void:
	if button.disabled:
		return
	var press := PointerGate.is_press(event)
	if press:
		var fired := int(button.get_meta(META_FIRED, -100000))
		if Time.get_ticks_msec() - fired < DEBOUNCE_MS:
			button.accept_event()  # a double tap: one action per press
			return
		if not button.has_meta(META_FROM):
			button.set_meta(META_FROM, global_of(event, button))
		if is_moving(scroll_of(button)):
			# the list is still gliding: this press only catches it (after both twins of the touch)
			cancel.call_deferred(button)
		return
	var mb := event as InputEventMouseButton
	var st := event as InputEventScreenTouch
	if (mb != null and not mb.pressed) or (st != null and not st.pressed):
		button.remove_meta(META_FROM)
		return
	if not button.has_meta(META_FROM):
		return
	var moving := event is InputEventScreenDrag or (event is InputEventMouseMotion
			and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT)
	if moving and global_of(event, button).distance_to(button.get_meta(META_FROM) as Vector2) > slop_px():
		cancel(button)


## Cancels every pending button press inside [param root]. Round 9: a list that hands its drag to
## the sheet must do this, or a pull-down that started on a row would also fire that row - the
## row's own 10 dp slop has not been crossed yet when the sheet claims the gesture at 8 dp.
static func cancel_in(root: Node) -> void:
	for n: Node in root.find_children("*", "BaseButton", true, false):
		var b := n as BaseButton
		if b != null and b.has_meta(META_FROM):
			cancel(b)


## The event's point in viewport px (mouse events carry it; touch events are local to the control).
static func global_of(event: InputEvent, c: Control) -> Vector2:
	var me := event as InputEventMouse
	if me != null:
		return me.global_position
	var p: Variant = event.get("position")
	return c.get_global_transform_with_canvas() * (p as Vector2) if p is Vector2 else Vector2.ZERO
