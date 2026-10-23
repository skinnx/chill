class_name SheetHost
extends Control
## Hosts the bottom sheets (Art Bible §4.17, §9.4, §10.3; GDD §8.1). Draw order inside the HUD
## layer is BackBufferCopy (rect = the sheet, so the live glass sees the world WITHOUT the scrim)
## -> Scrim (scrim @ 0.24, fades on `short`, a tap closes) -> the one open sheet. Exactly one
## sheet at a time: tapping the same dock button closes it, another one swaps with a 200 ms
## crossfade. In: rise 96 px + fade on `standard`; out: `exit` (~210 ms). Back closes the sheet
## (Game.push_back_handler). Audio: S07 on open/swap, S08 on close, AudioDirector.set_sheet_open.
##
## Round 6 (device QA): two detents per sheet (UiSheet.configure): medium = round(0.56 H) on
## 16:9, growing with the screen's aspect to 0.66 H on tall phones; large = everything up to the
## top bar (+ 24), at most 0.80 H. While a field in the sheet is being edited, the sheet rises
## above the on-screen keyboard (DisplayServer.virtual_keyboard_get_height) and the field is
## scrolled into view.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

signal sheet_changed(id: StringName)

const CUE_OPEN := &"S07"
const CUE_CLOSE := &"S08"
## Art Bible §9.4: height = round(0.56 H) on 16:9 (H/W 1.78), bottom = dock top - 24; on taller
## screens the medium detent grows to TALL_FRAC at H/W >= TALL_ASPECT (0.66 x 2400 = 1584 at 20:9).
const HEIGHT_FRAC := 0.56
const TALL_FRAC := 0.66
const BASE_ASPECT := 16.0 / 9.0
const TALL_ASPECT := 2.2
## The large detent never covers more than this share of the screen (nor the top bar).
const LARGE_FRAC := 0.80
const DOCK_GAP := 24.0
const SIDE := 24.0
## The sheet draws above the dock's z-lifted layers (DockView.Z_LABELS) while it slides over them;
## its contents are layered from here up by kind (UiBatch: base .. base + 2 x SCROLL_BAND).
const Z_SHEET := 10
const OPEN_SPRING := &"pop"
## The glass copy also covers the open spring's overshoot above the rest position.
const OVERSHOOT_PX := 16.0

var current: UiSheet
var current_id: StringName = &""
## The HUD chrome (top bar + dock) lives between the scrim and the sheet, so the scrim dims only
## the world while the HUD and dock stay crisp (§9.4).
var chrome: Control
## Callable(id) -> UiSheet, set by the HUD.
var factory: Callable
var dock_top: float = 1541.0
## The top bar's bottom edge (screen px): a sheet never rises above it + DOCK_GAP (large text
## grows both the top bar and the dock, round 5).
var top_limit: float = 0.0
## The neutral night dim of the sheets (HudController, night_chrome.sheet_dim): rgb only, the
## open / close motion drives modulate.a.
var tint: Color = Color.WHITE:
	set(v):
		tint = v
		for c: Node in get_children():
			if c is UiSheet:
				var s := c as UiSheet
				s.modulate = Color(v.r, v.g, v.b, s.modulate.a)
## QA (--qa-kb): a simulated on-screen keyboard height in canvas px (< 0: the real one).
var qa_keyboard_px: float = -1.0
var _bbc: BackBufferCopy
var _scrim: ColorRect
var _back := Callable()
var _screen: Vector2 = Vector2(1080, 1920)
var _lift_to: float = 0.0
var _kb_restore_expanded: bool = false
var _scrim_press := Vector2(-INF, -INF)
## A refresh that arrived while the player had a finger on the sheet (see [method refresh]).
var _refresh_pending: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_bbc = BackBufferCopy.new()
	_bbc.name = "GlassCopy"
	_bbc.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	add_child(_bbc)
	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = UiTokens.tinted(&"scrim", UiTokens.alpha(&"scrim_sheet"))
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.visible = false
	_scrim.gui_input.connect(_on_scrim_input)
	add_child(_scrim)
	chrome = Control.new()
	chrome.name = "Chrome"
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chrome.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(chrome)
	_back = close
	Settings.changed.connect(func(key: StringName, _v: Variant) -> void:
		if key == Settings.REDUCE_TRANSPARENCY:
			_sync_copy())


func is_open() -> bool:
	return current != null


func layout(screen: Vector2, p_dock_top: float) -> void:
	_screen = screen
	dock_top = p_dock_top
	if current != null:
		_configure(current, true)
		_sync_copy()


## The open sheet's rect in screen px at its medium (opening) detent.
func sheet_rect() -> Rect2:
	var bottom := dock_top - DOCK_GAP
	var aspect := _screen.y / maxf(_screen.x, 1.0)
	var k := clampf((aspect - BASE_ASPECT) / (TALL_ASPECT - BASE_ASPECT), 0.0, 1.0)
	var frac := lerpf(HEIGHT_FRAC, TALL_FRAC, k)
	var h := minf(roundf(frac * _screen.y), _room(bottom))
	return Rect2(SIDE, bottom - h, _screen.x - SIDE * 2.0, h)


## The large detent's rect: up to the top bar (+ 24), at most LARGE_FRAC of the screen.
func large_rect() -> Rect2:
	var bottom := dock_top - DOCK_GAP
	var h := maxf(minf(roundf(LARGE_FRAC * _screen.y), _room(bottom)), sheet_rect().size.y)
	return Rect2(SIDE, bottom - h, _screen.x - SIDE * 2.0, h)


func _room(bottom: float) -> float:
	return bottom - (top_limit + DOCK_GAP)


func _configure(s: UiSheet, keep: bool) -> void:
	var r := sheet_rect()
	s.configure(r.position.x, r.size.x, r.end.y, r.size.y, large_rect().size.y, keep)


## The on-screen keyboard's height in canvas px (0 when hidden).
func keyboard_height() -> float:
	if qa_keyboard_px >= 0.0:
		return qa_keyboard_px
	var px := float(DisplayServer.virtual_keyboard_get_height())
	if px <= 0.0:
		return 0.0
	var win := float(DisplayServer.window_get_size().y)
	return px * get_viewport_rect().size.y / maxf(win, 1.0)


func _process(_delta: float) -> void:
	if _refresh_pending and current != null and not current.is_touched():
		refresh()
	if current == null or current.rest_bottom <= 0.0:
		return
	var focus := get_viewport().gui_get_focus_owner()
	var editing := focus is LineEdit and current.is_ancestor_of(focus)
	var kb := keyboard_height() if editing else 0.0
	var lift := 0.0
	if kb > 0.0:
		lift = maxf(current.rest_bottom - (_screen.y - kb - DOCK_GAP), 0.0)
	if not is_equal_approx(lift, _lift_to):
		var was_lifted := _lift_to > 0.0
		_lift_to = lift
		if lift > 0.0 and not was_lifted:
			_kb_restore_expanded = current.expanded
		# while lifted the sheet takes all the room between the top bar and the keyboard
		var room := _room(current.rest_bottom - lift)
		var rest_h := current.h_large if _kb_restore_expanded else current.h_medium
		var h := minf(current.h_large, room) if lift > 0.0 else rest_h
		if lift <= 0.0:
			current.expanded = _kb_restore_expanded
		Motion.spring_to(current, "lift", lift, UiSheet.DETENT_SPRING)
		Motion.spring_to(current, "sheet_h", maxf(h, 0.0), UiSheet.DETENT_SPRING)
		FrameGovernor.hold_for(Motion.duration(&"standard"))
		_sync_copy()
	if editing and kb > 0.0:
		var sc := current.scroll_list()
		if sc != null:
			sc.ensure_control_visible(focus as Control)


## Opens [param id]; the same id closes it; another id swaps (crossfade). [param instant] skips the
## motion (QA stills).
func toggle(id: StringName, instant: bool = false) -> void:
	if current_id == id:
		close()
	elif current != null:
		_swap(id, instant)
	else:
		open(id, instant)


func open(id: StringName, instant: bool = false) -> void:
	if current != null:
		_swap(id, instant)
		return
	var s := _make(id)
	if s == null:
		return
	AudioDirector.play_cue(CUE_OPEN)
	AudioDirector.set_sheet_open(true)
	Game.push_back_handler(_back)
	_scrim.visible = true
	if instant:
		_scrim.modulate.a = 1.0
	else:
		_scrim.modulate.a = 0.0
		Motion.tween(_scrim, "modulate:a", 1.0, &"short")
	if instant:
		s.rise = 0.0
	else:
		var rise := float(UiTokens.ui_block("sheet_open").get("rise_px", 96.0))
		s.modulate.a = 0.0
		if Motion.reduce_motion:
			s.rise = 0.0
			var t := s.create_tween()
			t.tween_property(s, "modulate:a", 1.0, Motion.duration(&"reduce_motion_crossfade"))
		else:
			s.rise = rise
			# M3-Expressive (round 4): the sheet rises on the `pop` spring, a few px of overshoot
			# and settle, while it fades in on `standard`.
			Motion.spring_to(s, "rise", 0.0, OPEN_SPRING)
			Motion.tween(s, "modulate:a", 1.0, &"standard")
	_sync_copy()
	sheet_changed.emit(id)


func close() -> void:
	if current == null:
		return
	var s := current
	current = null
	current_id = &""
	Game.remove_back_handler(_back)
	AudioDirector.play_cue(CUE_CLOSE)
	AudioDirector.set_sheet_open(false)
	# The closing sheet takes no more input (a fast second tap on Plant / Collect never acts
	# twice); its rect and the fading scrim still consume presses until it is gone, so nothing
	# reaches the world through a sheet that is still on screen (ARCHITECTURE §3.5).
	s.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	s.closing = true
	var t := Motion.tween(_scrim, "modulate:a", 0.0, &"short")
	t.finished.connect(_hide_scrim_when_clear)
	s.tree_exited.connect(_hide_scrim_when_clear)
	var rise := float(UiTokens.ui_block("sheet_open").get("rise_px", 96.0))
	if Motion.reduce_motion:
		var f := s.create_tween()
		f.tween_property(s, "modulate:a", 0.0, Motion.duration(&"reduce_motion_crossfade"))
		f.finished.connect(s.queue_free)
	else:
		Motion.stop_springs(s)
		Motion.exit(s, "rise", s.rise + rise)
		var f := Motion.exit(s, "modulate:a", 0.0)
		f.finished.connect(s.queue_free)
	_bbc.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	sheet_changed.emit(&"")


## Rebuilds the open sheet (the night scheme switched): the same sheet and tab, crossfaded.
func rebuild(instant: bool = false) -> void:
	if current == null:
		return
	var id := current_id
	var tab := -1
	if current.has_method(&"current_tab"):
		tab = int(current.call(&"current_tab"))
	_swap(id, instant, true)
	if tab >= 0 and current != null and current.has_method(&"select_tab"):
		current.call(&"select_tab", tab, false)


## Re-reads the world into the open sheet (sim events, wallet changes).
## Reflects the latest world state in the open sheet - unless the player is touching it.
##
## A gift landing in the basket, a bloom, a heart, a postcard: each fires a sim event, and the
## sheet's own refresh() rebuilds its rows. Doing that under a thumb frees the row the press
## belongs to, so the tap never happens and the sheet appears to swallow it (round 9). The news
## is not urgent - it waits for the finger to leave.
func refresh() -> void:
	if current == null:
		return
	if current.is_touched():
		_refresh_pending = true
		set_process(true)
		return
	_refresh_pending = false
	current.refresh()


func _swap(id: StringName, instant: bool, quiet: bool = false) -> void:
	var old := current
	var s := _make(id)
	if s == null:
		return
	if not quiet:
		AudioDirector.play_cue(CUE_OPEN)
	if old != null and old.expanded:
		s.expand(true, false)
	if old != null:
		var dur := Motion.duration(&"short")
		if instant:
			old.queue_free()
		else:
			var f := old.create_tween()
			f.tween_property(old, "modulate:a", 0.0, dur)
			f.finished.connect(old.queue_free)
			s.modulate.a = 0.0
			var t := s.create_tween()
			t.tween_property(s, "modulate:a", 1.0, dur)
			FrameGovernor.hold_for(dur)
		old.live = false
		old.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
		old.closing = true
	_sync_copy()
	sheet_changed.emit(id)


func _make(id: StringName) -> UiSheet:
	if not factory.is_valid():
		return null
	var s: UiSheet = factory.call(id)
	if s == null:
		return null
	s.sheet_id = id
	_configure(s, false)
	_lift_to = 0.0
	s.close_requested.connect(close)
	s.z_index = Z_SHEET
	s.modulate = Color(tint.r, tint.g, tint.b, s.modulate.a)
	add_child(s)
	current = s
	current_id = id
	return s


## The copy rect covers the sheet plus its rise, so the glass is right during the motion too.
func _sync_copy() -> void:
	if current == null or not current.is_live():
		_bbc.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
		return
	# the large detent's top (or, lifted above the keyboard, the top bar) down to the rise's end
	var r := large_rect()
	var rise := float(UiTokens.ui_block("sheet_open").get("rise_px", 96.0))
	var top := minf(r.position.y, top_limit + DOCK_GAP) if _lift_to > 0.0 else r.position.y
	var bottom := r.end.y + rise
	_bbc.copy_mode = BackBufferCopy.COPY_MODE_RECT
	_bbc.rect = Rect2(Vector2(r.position.x, top - OVERSHOOT_PX),
			Vector2(r.size.x, bottom - top + OVERSHOOT_PX)).grow(2.0)


## The scrim stays up (consuming presses) until the closing sheet has left and its fade is done.
func _hide_scrim_when_clear() -> void:
	if current != null or not is_inside_tree():
		return
	for c: Node in get_children():
		if c is UiSheet and not c.is_queued_for_deletion() and c.is_inside_tree():
			return
	_scrim.visible = false


## A tap on the scrim closes the sheet: the press must start on the scrim and the release land
## within the 10 dp slop (a drag over the dimmed world does nothing). Both twins of a touch stop
## here (MOUSE_FILTER_STOP), so the world behind never sees the tap.
func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_scrim_press = mb.global_position
			elif _scrim_press.x > -INF and mb.global_position.distance_to(_scrim_press) <= TapGuard.slop_px():
				_scrim_press = Vector2(-INF, -INF)
				close()
			else:
				_scrim_press = Vector2(-INF, -INF)
	_scrim.accept_event()


## The scrim (tests, QA overlay).
func scrim() -> Control:
	return _scrim
