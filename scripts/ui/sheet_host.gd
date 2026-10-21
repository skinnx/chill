class_name SheetHost
extends Control
## Hosts the bottom sheets (Art Bible §4.17, §9.4, §10.3; GDD §8.1). Draw order inside the HUD
## layer is BackBufferCopy (rect = the sheet, so the live glass sees the world WITHOUT the scrim)
## -> Scrim (scrim @ 0.24, fades on `short`, a tap closes) -> the one open sheet. Exactly one
## sheet at a time: tapping the same dock button closes it, another one swaps with a 200 ms
## crossfade. In: rise 96 px + fade on `standard`; out: `exit` (~210 ms). Back closes the sheet
## (Game.push_back_handler). Audio: S07 on open/swap, S08 on close, AudioDirector.set_sheet_open.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

signal sheet_changed(id: StringName)

const CUE_OPEN := &"S07"
const CUE_CLOSE := &"S08"
## Art Bible §9.4: height = round(0.56 H), bottom = dock top - 24.
const HEIGHT_FRAC := 0.56
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
var _bbc: BackBufferCopy
var _scrim: ColorRect
var _back := Callable()
var _screen: Vector2 = Vector2(1080, 1920)


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
		var r := sheet_rect()
		current.position = r.position
		_sync_copy()


## The open sheet's rect in screen px.
func sheet_rect() -> Rect2:
	var bottom := dock_top - DOCK_GAP
	var h := minf(roundf(HEIGHT_FRAC * _screen.y), bottom - (top_limit + DOCK_GAP))
	return Rect2(SIDE, bottom - h, _screen.x - SIDE * 2.0, h)


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
	var r := sheet_rect()
	if instant:
		s.position = r.position
	else:
		var rise := float(UiTokens.ui_block("sheet_open").get("rise_px", 96.0))
		s.modulate.a = 0.0
		if Motion.reduce_motion:
			s.position = r.position
			var t := s.create_tween()
			t.tween_property(s, "modulate:a", 1.0, Motion.duration(&"reduce_motion_crossfade"))
		else:
			s.position = r.position + Vector2(0.0, rise)
			# M3-Expressive (round 4): the sheet rises on the `pop` spring, a few px of overshoot
			# and settle, while it fades in on `standard`.
			Motion.spring_to(s, "position", r.position, OPEN_SPRING)
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
	var t := Motion.tween(_scrim, "modulate:a", 0.0, &"short")
	t.finished.connect(func() -> void:
		if current == null:
			_scrim.visible = false)
	var rise := float(UiTokens.ui_block("sheet_open").get("rise_px", 96.0))
	if Motion.reduce_motion:
		var f := s.create_tween()
		f.tween_property(s, "modulate:a", 0.0, Motion.duration(&"reduce_motion_crossfade"))
		f.finished.connect(s.queue_free)
	else:
		Motion.stop_springs(s)
		Motion.exit(s, "position", s.position + Vector2(0.0, rise))
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
func refresh() -> void:
	if current != null:
		current.refresh()


func _swap(id: StringName, instant: bool, quiet: bool = false) -> void:
	var old := current
	var s := _make(id)
	if s == null:
		return
	if not quiet:
		AudioDirector.play_cue(CUE_OPEN)
	s.position = sheet_rect().position
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
	_sync_copy()
	sheet_changed.emit(id)


func _make(id: StringName) -> UiSheet:
	if not factory.is_valid():
		return null
	var s: UiSheet = factory.call(id)
	if s == null:
		return null
	var r := sheet_rect()
	s.sheet_id = id
	s.size = r.size
	s.position = r.position
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
	var r := sheet_rect()
	var rise := float(UiTokens.ui_block("sheet_open").get("rise_px", 96.0))
	_bbc.copy_mode = BackBufferCopy.COPY_MODE_RECT
	_bbc.rect = Rect2(r.position - Vector2(0.0, OVERSHOOT_PX), r.size + Vector2(0.0, rise + OVERSHOOT_PX)).grow(2.0)


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			close()
		_scrim.accept_event()
