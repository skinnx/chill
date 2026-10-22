class_name DecorEditChrome
extends Control
## Active F3 edit-mode chrome (docs/gdd/ACTIVE_DECOR.md §8, §10-§11; Art Bible §9; px at H 1920,
## T 120). It lives in the HUD (HudController.edit_chrome_host(), under the modal cards and the
## toast) while the HUD's own top bar and dock fade out:
##  * Undo: faux glass circle Ø 120 in the gear's slot with a curved-arrow glyph; hit 216 x 216.
##    Nothing to undo: the glyph at 0.35 and a press gives the soft S11 tok (never a dead button).
##  * Banner: faux glass pill h 96 "Arranging the garden" (Label 42, passive).
##  * Done: primary pill 264 x 120 (Label 42, Nunito 800, surface_hi), hit 336 x 216.
##  * Context hint: toast-style faux glass pill h 96 centred at y 400 (DECOR_EDIT_HINT for 4 s on
##    entry, the selection / tray hints, or one soft DECOR_HINT_* reason, which wins).
##  * Selection chip: surface_hi card (e1) with round buttons Ø 156 (hit 180 = 60 dp, 24 px apart)
##    and Caption labels under them: Turn, Put away (+ Lift a pebble on a stack, or Find a spot for
##    a tray piece in hand). 36 px above the piece's top, or under its foot if that would cross
##    y 400; clamped to x 24-1056 and above the tray; it follows the piece (and the pan).
##  * The storage tray ([DecorEditTray]) in the dock's place.
## A full-width band over the top row consumes presses (as the HUD band does in play). Left-handed:
## Undo and Done swap sides and the chip's buttons mirror. Night: dim glass and night_ink labels.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

signal done_pressed
signal undo_pressed
signal turn_pressed
signal put_away_pressed
signal lift_pebble_pressed
signal find_spot_pressed

const T_MIN := 120.0
const TOP_GAP := 24.0
const SIDE := 48.0
const CIRCLE := 120.0
const HIT := 216.0
const HIT_PAD := 48.0
const ICON := 72.0
const BANNER_H := 96.0
const BANNER_X := Vector2(240.0, 744.0)
const DONE := Vector2(264.0, 120.0)
const DONE_HIT_PAD := 24.0
const HINT_H := 96.0
const HINT_Y := 400.0
const HINT_PAD := 48.0
const HINT_MAX_W := 936.0
const HINT_ENTRY_S := 4.0
const REASON_S := 2.5
const CHIP_BTN := 156.0
const CHIP_HIT := 180.0
const CHIP_GAP := 24.0
const CHIP_PAD := 18.0
const CHIP_LABEL_GAP := 6.0
const CHIP_ABOVE := 36.0
const CHIP_X := Vector2(24.0, 1056.0)
const CHIP_RADIUS := 72.0
const CHIP_TRAY_GAP := 24.0
const TRAY_RISE := 48.0
const DISABLED_ALPHA := 0.35
const LARGE_TEXT := 150
## Glyphs and labels draw above every chrome surface in z layers (as TopBarView), so the labels
## batch in one call instead of alternating with the plates.
const Z_GLYPH := 2
const Z_LABEL := 3
const KIND_TURN := &"turn"
const KIND_PUT := &"put_away"
const KIND_LIFT := &"lift"
const KIND_FIND := &"find"
const KIND_UNDO := &"undo"

var edit: DecorEdit
var hud: HudController
var tray: DecorEditTray
## The last screen-reader announcement (A11Y_DECOR_*; tests and QA read it).
var last_announcement: String = ""

var _band: Control
var _undo: Button
var _undo_glass: GlassPanel
var _undo_glyph: Glyph
var _banner: GlassPanel
var _banner_label: Label
var _done: Button
var _done_plate: UiSurface
var _done_label: Label
var _hint: GlassPanel
var _hint_label: Label
var _hint_kind: StringName = &""
var _hint_text: String = ""
var _hint_set: StringName = &""
var _hint_t: float = -1.0
var _reason_t: float = -1.0
var _chip: Control
var _chip_plate: UiSurface
var _chip_kinds: Array[StringName] = []
var _chip_for: String = ""
var _screen := Vector2(1080, 1920)
var _safe := Rect2(48, 72, 48, 127)
var _night_k: float = -1.0
var _frozen: bool = false
var _open: bool = false


## A drawn glyph (no icon in the set fits): turn, put away, lift a pebble, find a spot, undo.
class Glyph:
	extends Control
	var kind: StringName = &""
	var ink := Color.BLACK
	var plate := Color(0, 0, 0, 0)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = Z_GLYPH

	## One triangle array per glyph (one draw call; DecorEdit.Tris): the plate, round-capped
	## strokes and a soft 1.5 px rim that stands in for antialiasing.
	func _draw() -> void:
		var t := DecorEdit.Tris.new()
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		if plate.a > 0.0:
			t.ellipse(c, Vector2(r, r), plate, 56)
			t.line(DecorEdit._ellipse_points(c, Vector2(r, r) - Vector2(0.75, 0.75), 56), 1.5, Color(plate, plate.a * 0.5))
		var s := r * (0.46 if plate.a > 0.0 else 0.62)
		var w := maxf(2.0, s * 0.2)
		match kind:
			&"turn":
				_stroke(t, _arc(c, s * 0.8, -60.0, 210.0), w)
				_head(t, c + Vector2.from_angle(deg_to_rad(-60.0)) * s * 0.8, deg_to_rad(30.0), s * 0.42)
			&"undo":
				var o := c + Vector2(s * 0.1, s * 0.1)
				_stroke(t, _arc(o, s * 0.62, -200.0, 40.0), w)
				_head(t, o + Vector2.from_angle(deg_to_rad(-200.0)) * s * 0.62, deg_to_rad(70.0), s * 0.42)
			&"put_away":
				_stroke(t, PackedVector2Array([c + Vector2(-s, s * 0.15), c + Vector2(-s * 0.8, s * 0.85),
					c + Vector2(s * 0.8, s * 0.85), c + Vector2(s, s * 0.15)]), w)
				_stroke(t, PackedVector2Array([c + Vector2(0.0, -s), c + Vector2(0.0, s * 0.3)]), w)
				_head(t, c + Vector2(0.0, s * 0.42), PI * 0.5, s * 0.42)
			&"lift":
				t.ellipse(c + Vector2(0.0, s * 0.62), Vector2(s * 0.32, s * 0.32), ink, 24)
				_stroke(t, PackedVector2Array([c + Vector2(0.0, s * 0.1), c + Vector2(0.0, -s * 0.8)]), w)
				_head(t, c + Vector2(0.0, -s * 0.92), -PI * 0.5, s * 0.42)
			&"find":
				var pts := PackedVector2Array()
				for k in 8:
					var a := TAU * float(k) / 8.0 - PI * 0.5
					pts.append(c + Vector2(cos(a), sin(a)) * (s if k % 2 == 0 else s * 0.34))
				t.fan(c, pts, ink)
		t.flush(self)

	static func _arc(c: Vector2, r: float, from_deg: float, to_deg: float, n: int = 24) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for k in n + 1:
			pts.append(c + Vector2.from_angle(deg_to_rad(lerpf(from_deg, to_deg, float(k) / float(n)))) * r)
		return pts

	## A round-capped, round-jointed stroke.
	func _stroke(t: DecorEdit.Tris, path: PackedVector2Array, w: float) -> void:
		t.line(path, w, ink)
		for q: Vector2 in path:
			t.ellipse(q, Vector2(w, w) * 0.5, ink, 12)

	## An open arrow head at [param tip] pointing along [param angle].
	func _head(t: DecorEdit.Tris, tip: Vector2, angle: float, len: float) -> void:
		var w := maxf(2.0, len * 0.42)
		var a := tip - Vector2.from_angle(angle - 0.6) * len
		var b := tip - Vector2.from_angle(angle + 0.6) * len
		_stroke(t, PackedVector2Array([a, tip + Vector2.from_angle(angle) * w * 0.3, b]), w)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func _ready() -> void:
	_band = Control.new()
	_band.name = "EditBand"
	_band.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_band)
	_build_undo()
	_build_banner()
	_build_done()
	_build_hint()
	_chip = Control.new()
	_chip.name = "Chip"
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.visible = false
	add_child(_chip)
	_chip_plate = UiSurface.make(UiTokens.color(&"surface_hi"), CHIP_RADIUS, UiTokens.E1)
	_chip.add_child(_chip_plate)
	tray = DecorEditTray.new()
	tray.name = "Tray"
	add_child(tray)
	get_viewport().size_changed.connect(_layout)
	Settings.changed.connect(func(key: StringName, _v: Variant) -> void:
		if key == Settings.LEFT_HANDED or key == Settings.TEXT_SCALE:
			_layout())
	_layout()


func _build_undo() -> void:
	_undo = Button.new()
	_undo.flat = true
	_undo.focus_mode = Control.FOCUS_NONE
	_undo.name = "Undo"
	_undo.tooltip_text = tr("A11Y_DECOR_UNDO")
	add_child(_undo)
	_undo_glass = GlassPanel.new()
	_undo_glass.night_aware = true
	_undo_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_undo.add_child(_undo_glass)
	_undo_glyph = Glyph.new()
	_undo_glyph.kind = KIND_UNDO
	_undo_glass.add_child(_undo_glyph)
	PressFeedback.attach(_undo)
	_undo.pressed.connect(func() -> void:
		if not Game.can_undo_decor():
			PressFeedback.nudge(_undo_glass)
		undo_pressed.emit())


func _build_banner() -> void:
	_banner = GlassPanel.new()
	_banner.name = "Banner"
	_banner.night_aware = true
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)
	_banner_label = UiSheet.label(tr("DECOR_EDIT_TITLE"), &"StrongLabel")
	_banner_label.z_index = Z_LABEL
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_banner_label.clip_text = true
	_banner.add_child(_banner_label)


func _build_done() -> void:
	_done = Button.new()
	_done.flat = true
	_done.focus_mode = Control.FOCUS_NONE
	_done.name = "Done"
	add_child(_done)
	_done_plate = UiSurface.make(UiTokens.color(&"primary_pressed"), UiSurface.PILL, UiTokens.E1)
	_done_plate.lip_alpha = ThemeBuilder.LIP_ALPHA
	_done.add_child(_done_plate)
	_done_label = UiSheet.label(tr("DECOR_EDIT_DONE"), &"StrongLabel")
	_done_label.z_index = Z_LABEL
	_done_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_done_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_done_label.add_theme_color_override(&"font_color", UiTokens.color(&"surface_hi"))
	_done.add_child(_done_label)
	PressFeedback.attach(_done)
	_done.button_down.connect(func() -> void: _done_plate.color = UiTokens.color(&"primary_deep"))
	_done.button_up.connect(func() -> void: _done_plate.color = UiTokens.color(&"primary_pressed"))
	_done.pressed.connect(func() -> void: done_pressed.emit())


func _build_hint() -> void:
	_hint = GlassPanel.new()
	_hint.name = "Hint"
	_hint.night_aware = true
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	add_child(_hint)
	_hint_label = UiSheet.label("", &"StrongLabel")
	_hint_label.z_index = Z_LABEL
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.add_child(_hint_label)


func _layout() -> void:
	if _undo == null:
		return
	_screen = get_viewport_rect().size
	if hud != null:
		_safe = hud.safe_margins()
	var left := Settings.get_bool(Settings.LEFT_HANDED)
	var y := maxf(_safe.position.y, T_MIN) + TOP_GAP
	var w := _screen.x
	var undo_x := w - SIDE - CIRCLE if left else SIDE
	_undo.position = Vector2(undo_x - HIT_PAD, y)
	_undo.size = Vector2(HIT, HIT)
	_undo_glass.position = Vector2(HIT_PAD, 0.0)
	_undo_glass.size = Vector2(CIRCLE, CIRCLE)
	_undo_glyph.size = Vector2(ICON, ICON)
	_undo_glyph.position = Vector2(CIRCLE - ICON, CIRCLE - ICON) * 0.5
	_undo.pivot_offset = Vector2(HIT_PAD + CIRCLE * 0.5, CIRCLE * 0.5)
	_undo.set_meta(PressFeedback.META_RIPPLE_RECT, Rect2(Vector2(HIT_PAD, 0.0), Vector2(CIRCLE, CIRCLE)))
	_undo.set_meta(PressFeedback.META_RIPPLE_RADIUS, CIRCLE * 0.5)
	var done_w := maxf(DONE.x, _done_label.get_combined_minimum_size().x + 72.0)
	var done_x := SIDE if left else w - SIDE - done_w
	_done.position = Vector2(done_x - DONE_HIT_PAD, y)
	_done.size = Vector2(done_w + DONE_HIT_PAD * 2.0, HIT)
	_done_plate.position = Vector2(DONE_HIT_PAD, 0.0)
	_done_plate.size = Vector2(done_w, DONE.y)
	_done_label.position = _done_plate.position
	_done_label.size = _done_plate.size
	_done.pivot_offset = _done_plate.position + _done_plate.size * 0.5
	_done.set_meta(PressFeedback.META_RIPPLE_RECT, Rect2(_done_plate.position, _done_plate.size))
	_done.set_meta(PressFeedback.META_RIPPLE_RADIUS, DONE.y * 0.5)
	var bx0 := (undo_x + CIRCLE + TOP_GAP * 3.0) if not left else (done_x + done_w + TOP_GAP)
	var bx1 := (done_x - TOP_GAP) if not left else (undo_x - TOP_GAP * 3.0)
	var bw := minf(bx1 - bx0, maxf(BANNER_X.y - BANNER_X.x, _banner_label.get_combined_minimum_size().x + 72.0))
	_banner.position = Vector2((bx0 + bx1 - bw) * 0.5, y + (CIRCLE - BANNER_H) * 0.5)
	_banner.size = Vector2(bw, BANNER_H)
	_banner_label.size = _banner.size
	_banner_label.position = Vector2.ZERO
	_band.position = Vector2.ZERO
	_band.size = Vector2(w, y + HIT)
	tray.layout(_screen, _safe.size.y)
	_place_hint()


func _hint_y() -> float:
	return maxf(HINT_Y, _safe.position.y + HINT_Y - T_MIN)


func _place_hint() -> void:
	var max_w := minf(HINT_MAX_W, _screen.x - SIDE * 2.0)
	var font := _hint_label.get_theme_font(&"font")
	var fs := _hint_label.get_theme_font_size(&"font_size")
	_hint_label.text = wrap_text(_hint_text, font, fs, max_w - HINT_PAD * 2.0)
	var lines := _hint_label.text.split("\n")
	var widest := 0.0
	for line: String in lines:
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var w := minf(max_w, widest + HINT_PAD * 2.0 + 2.0)
	var h := maxf(HINT_H, _hint_label.get_combined_minimum_size().y + 36.0)
	_hint.size = Vector2(w, h)
	_hint.radius = HINT_H * 0.5
	_hint.position = Vector2((_screen.x - w) * 0.5, _hint_y() - h * 0.5)
	_hint_label.position = Vector2(HINT_PAD, 0.0)
	_hint_label.size = Vector2(w - HINT_PAD * 2.0, h)


## Greedy word wrap of [param text] to [param width] px (explicit line breaks instead of Label
## autowrap, whose cached minimum height follows a stale width when the text changes size).
static func wrap_text(text: String, font: Font, fs: int, width: float) -> String:
	var out: PackedStringArray = []
	var line := ""
	for word: String in text.split(" ", false):
		var cand := word if line == "" else line + " " + word
		if line != "" and font.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
			out.append(line)
			line = word
		else:
			line = cand
	if line != "":
		out.append(line)
	return "\n".join(out)


# ------------------------------------------------------------------ open / close

func open(hint: bool) -> void:
	_open = true
	visible = true
	_layout()
	refresh()
	modulate.a = 0.0
	Motion.fade_in(self, &"standard")
	tray.position.y += TRAY_RISE
	Motion.tween(tray, "position:y", tray.position.y - TRAY_RISE, &"standard")
	set_hint(&"enter" if hint else &"")
	if hint:
		_hint_t = HINT_ENTRY_S


func close() -> void:
	_open = false
	hide_chip()
	_hint.visible = false
	_reason_t = -1.0
	var t := Motion.fade_out(self, &"exit")
	t.finished.connect(func() -> void:
		if not _open:
			visible = false)


func is_open() -> bool:
	return _open


func toast(text: String) -> void:
	if hud != null and hud.overlays != null:
		hud.overlays.show_toast(text)


func announce(text: String) -> void:
	last_announcement = text


func refresh() -> void:
	var can := Game.sim != null and Game.can_undo_decor()
	_undo_glyph.modulate.a = 1.0 if can else DISABLED_ALPHA
	tray.refresh()
	if edit != null and edit.selected != "" and _chip.visible:
		var p := DecorLayer.current.piece(edit.selected) if DecorLayer.current != null else null
		if p != null:
			show_chip(p)


## The tray after a put-away: the tile of [param pop_set] pops (S38 is the caller's).
func refresh_tray(pop_set: StringName) -> void:
	tray.refresh(pop_set)
	refresh()


func freeze() -> void:
	_frozen = true
	set_process(false)


# ------------------------------------------------------------------ hints

## Context hint: &"" (none), &"enter", &"selected", &"tray" (with the set), &"tray_drop".
func set_hint(kind: StringName, set_id: StringName = &"") -> void:
	if kind == &"":
		if _hint_kind == &"enter" and _hint_t > 0.0:
			return  # the entry hint keeps its 4 s unless something replaces it
		_hint_kind = &""
		_reason_t = -1.0
		_hint.visible = false
		return
	if kind == _hint_kind and set_id == _hint_set and _hint.visible and _reason_t < 0.0:
		return
	_hint_kind = kind
	_hint_set = set_id
	_reason_t = -1.0
	_hint_t = HINT_ENTRY_S if kind == &"enter" else -1.0
	var name := tr(String((ContentRegistry.content.decor_by_id.get(set_id, {}) as Dictionary).get("name_key", "")))
	match kind:
		&"enter":
			_show_text(tr("DECOR_EDIT_HINT"))
		&"selected":
			_show_text(I18n.fmt(&"DECOR_EDIT_SELECTED_HINT", {"decor": name}))
		&"tray":
			_show_text(I18n.fmt(&"DECOR_EDIT_TRAY_HINT", {"decor": name}))
		&"tray_drop":
			_show_text(tr("DECOR_TRAY_DROP"))


## One soft reason (DECOR_HINT_*), shown over any context hint for a moment.
func show_reason(text: String) -> void:
	_hint_kind = &"reason"
	_hint_t = -1.0
	if _reason_t < 0.0 or _hint_text != text:
		_show_text(text)
	_reason_t = REASON_S


func hint_text() -> String:
	return _hint_text if _hint.visible else ""


func _show_text(text: String) -> void:
	var was := _hint.visible
	_hint_text = text
	_place_hint()
	_hint.visible = true
	if not was and not _frozen:
		_hint.modulate.a = 0.0
		Motion.fade_in(_hint, &"short")


# ------------------------------------------------------------------ selection chip

func show_chip(p: DecorLayer.Piece) -> void:
	var kinds: Array[StringName] = []
	var rules := Game.decor_rules()
	if rules.rot_steps(p.decor) > 1:
		kinds.append(KIND_TURN)
	kinds.append(KIND_PUT)
	if p.decor == DecorLayer.CAIRN and p.pebbles.size() > 1:
		kinds.append(KIND_LIFT)
	_chip_for = p.id
	_build_chip(kinds)


func show_find_chip() -> void:
	_chip_for = ""
	_build_chip([KIND_FIND])


func hide_chip() -> void:
	_chip.visible = false
	_chip_for = ""


func chip_kinds() -> Array[StringName]:
	return _chip_kinds if _chip.visible else ([] as Array[StringName])


func set_hand(s: StringName) -> void:
	tray.set_hand(s)
	if s != &"":
		show_find_chip()
	elif _chip_for == "":
		hide_chip()


func _build_chip(kinds: Array[StringName]) -> void:
	for c: Node in _chip.get_children():
		if c != _chip_plate:
			c.queue_free()
	if Settings.get_bool(Settings.LEFT_HANDED):
		kinds.reverse()
	_chip_kinds = kinds
	var stacked := Settings.get_int(Settings.TEXT_SCALE) >= LARGE_TEXT
	var label_h := 0.0
	var cols: Array[Control] = []
	for k: StringName in kinds:
		var col := _chip_button(k)
		cols.append(col)
		_chip.add_child(col)
		label_h = maxf(label_h, (col.get_node(^"Label") as Label).get_combined_minimum_size().y)
	var col_h := CHIP_HIT + CHIP_LABEL_GAP + label_h
	var col_w := CHIP_HIT
	for col: Control in cols:
		col_w = maxf(col_w, (col.get_node(^"Label") as Label).get_combined_minimum_size().x)
	var n := cols.size()
	var size_v := Vector2(CHIP_PAD * 2.0 + col_w, CHIP_PAD * 2.0 + col_h * n + CHIP_GAP * (n - 1)) if stacked \
			else Vector2(CHIP_PAD * 2.0 + col_w * n + CHIP_GAP * (n - 1), CHIP_PAD * 2.0 + col_h)
	for i in n:
		var col := cols[i]
		col.size = Vector2(col_w, col_h)
		col.position = Vector2(CHIP_PAD, CHIP_PAD + (col_h + CHIP_GAP) * i) if stacked \
				else Vector2(CHIP_PAD + (col_w + CHIP_GAP) * i, CHIP_PAD)
		var b := col.get_node(^"Button") as Control
		b.position = Vector2((col_w - CHIP_HIT) * 0.5, 0.0)
		var l := col.get_node(^"Label") as Label
		l.size = Vector2(col_w, label_h)
		l.position = Vector2(0.0, CHIP_HIT + CHIP_LABEL_GAP)
	_chip.size = size_v
	_chip_plate.size = size_v
	_chip_plate.position = Vector2.ZERO
	_chip.visible = true
	_night_chip()
	_chip.pivot_offset = size_v * 0.5
	if not _frozen:
		_chip.scale = Vector2.ONE * 0.92
		_chip.modulate.a = 0.0
		Motion.spring_to(_chip, "scale", Vector2.ONE, &"pop")
		Motion.fade_in(_chip, &"short")
	_place_chip()


func _chip_button(kind: StringName) -> Control:
	var col := Control.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.name = String(kind)
	var b := Button.new()
	b.name = "Button"
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.size = Vector2(CHIP_HIT, CHIP_HIT)
	col.add_child(b)
	var g := Glyph.new()
	g.name = "Glyph"
	g.kind = kind
	g.size = Vector2(CHIP_BTN, CHIP_BTN)
	g.position = Vector2(CHIP_HIT - CHIP_BTN, CHIP_HIT - CHIP_BTN) * 0.5
	g.plate = UiTokens.color(&"primary_tint")
	g.ink = UiTokens.color(&"ink")
	b.add_child(g)
	b.pivot_offset = Vector2(CHIP_HIT, CHIP_HIT) * 0.5
	b.set_meta(PressFeedback.META_RIPPLE_RECT, Rect2(g.position, g.size))
	b.set_meta(PressFeedback.META_RIPPLE_RADIUS, CHIP_BTN * 0.5)
	PressFeedback.attach(b)
	var keys := {KIND_TURN: "DECOR_EDIT_TURN", KIND_PUT: "DECOR_EDIT_PUT_AWAY", KIND_LIFT: "DECOR_EDIT_LIFT_PEBBLE",
		KIND_FIND: "DECOR_EDIT_FIND_SPOT"}
	var l := UiSheet.label(tr(String(keys[kind])), &"CaptionLabel")
	l.z_index = Z_LABEL
	l.name = "Label"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	b.pressed.connect(_on_chip.bind(kind))
	return col


func _on_chip(kind: StringName) -> void:
	match kind:
		KIND_TURN:
			turn_pressed.emit()
		KIND_PUT:
			put_away_pressed.emit()
		KIND_LIFT:
			lift_pebble_pressed.emit()
		KIND_FIND:
			find_spot_pressed.emit()


func _place_chip() -> void:
	if not _chip.visible:
		return
	var x_range := Vector2(CHIP_X.x, _screen.x - (1080.0 - CHIP_X.y))
	var bottom := tray.position.y - CHIP_TRAY_GAP
	if _chip_for == "":
		var t := tray.tile_centre(tray.hand)
		var r := DecorEdit.chip_rect(t - Vector2(0.0, tray.size.y * 0.5), t, _chip.size, CHIP_ABOVE, _hint_y(), x_range,
				bottom)
		_chip.position = r.position
		return
	var layer := DecorLayer.current
	var p := layer.piece(_chip_for) if layer != null else null
	if p == null:
		hide_chip()
		return
	var top := layer.to_canvas(layer.top_of(p))
	var foot := layer.to_canvas(p.foot)
	var r2 := DecorEdit.chip_rect(top, foot, _chip.size, CHIP_ABOVE, _hint_y() + HINT_H * 0.5, x_range, bottom)
	_chip.position = r2.position


func chip_rect() -> Rect2:
	return Rect2(_chip.position, _chip.size) if _chip.visible else Rect2()


# ------------------------------------------------------------------ tray

func set_tray_hover(on: bool) -> void:
	tray.set_hover(on)


func tray_drop_rect() -> Rect2:
	return tray.drop_rect()


func tray_target(s: StringName) -> Vector2:
	return tray.tile_centre(s)


func _process(delta: float) -> void:
	if not visible:
		return
	if _hint_t > 0.0:
		_hint_t -= delta
		if _hint_t <= 0.0 and _hint_kind == &"enter":
			_hint_kind = &""
			_hint.visible = false
	if _reason_t > 0.0:
		_reason_t -= delta
		if _reason_t <= 0.0:
			_reason_t = -1.0
			_hint_kind = &""
			_hint.visible = false
	_place_chip()
	var k := GlassPanel.night_k
	if absf(k - _night_k) > 1e-3:
		_night_k = k
		var ink := UiTokens.color(&"ink").lerp(UiTokens.color(&"night_ink"), k)
		_banner_label.add_theme_color_override(&"font_color", ink)
		_hint_label.add_theme_color_override(&"font_color", ink)
		_undo_glyph.ink = ink
		_undo_glyph.queue_redraw()
		_night_chip()
		tray.set_night(k)


## Night chrome (§11, as the dock): the chip turns night_capsule with night_ink labels and dim
## button plates instead of a cream slab under the night sky.
func _night_chip() -> void:
	var k := maxf(_night_k, 0.0)
	_chip_plate.color = UiTokens.color(&"surface_hi").lerp(UiTokens.color(&"night_capsule"), k)
	var ink := UiTokens.color(&"ink").lerp(UiTokens.color(&"night_ink"), k)
	var plate := UiTokens.color(&"primary_tint").lerp(_night_token(&"primary_tint"), k)
	for col: Node in _chip.get_children():
		var l := col.get_node_or_null(^"Label") as Label
		if l != null:
			l.add_theme_color_override(&"font_color", ink)
		var g := col.get_node_or_null(^"Button/Glyph") as Glyph
		if g != null:
			g.ink = ink
			g.plate = plate
			g.queue_redraw()


static func _night_token(token: StringName) -> Color:
	var n: Dictionary = ContentRegistry.palettes().get("ui_night", {})
	return Color.html(String(n[String(token)])) if n.has(String(token)) else UiTokens.color(token)
