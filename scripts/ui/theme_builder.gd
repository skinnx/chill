class_name ThemeBuilder
extends RefCounted
## Builds the base UI Theme from the design tokens (Art Bible §3.5, §9.1, §9.2; synthesis §3
## type scale; D6 fonts). ui/theme/base_theme.tres is this output at 100 % text size, written by
## tools/ui/build_theme.gd; at runtime the UI rebuilds it for the Text size setting (X1) and the
## language (Vietnamese +12 % line spacing). The UI Engineer owns the look from here on: extend the
## token tables below rather than hand-editing the .tres.
##
## Type variations: TitleLabel, BodyLabel, StrongLabel, CaptionLabel, SecondaryLabel,
## HudNumeral, PriceLabel; buttons: (default = primary), SecondaryButton; panels: Card, Sheet,
## Chip, ModalCard.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const FONT_BODY := "res://fonts/nunito/Nunito-Medium.woff2"
const FONT_STRONG := "res://fonts/nunito/Nunito-Bold.woff2"
const FONT_HEAVY := "res://fonts/nunito/Nunito-ExtraBold.woff2"
const FONT_TITLE := "res://fonts/baloo2/Baloo2-Bold.woff2"
const FONT_NUMERALS := "res://fonts/baloo2/Baloo2-Bold-Numerals.woff2"

## Type scale in px at 100 % (1 dp = 3 px).
const SIZE_CAPTION := 36
const SIZE_LABEL := 42
const SIZE_BODY := 48
const SIZE_PRICE := 48
const SIZE_HUD := 66
const SIZE_TITLE := 84
## Radii (Art Bible §9.2): r-xs 24, r-s 30, r-m 48, r-l 72, r-xl 96.
const R_XS := 24
const R_S := 30
const R_M := 48
const R_L := 72
const R_XL := 96
const CORNER_DETAIL_SMALL := 12
const CORNER_DETAIL_LARGE := 16
## Elevation (alpha, blur size, y offset) in ink, never black.
const E1 := [0.06, 24, 6]
const E2 := [0.12, 48, 18]
const E3 := [0.16, 72, 24]
## Button heights (Art Bible §9.4): 156 px primary (52 dp), 132 inside cards.
const BUTTON_H := 156
const CARD_PADDING := 24
const BUTTON_PAD_X := 48
## 1 dp outline of the secondary button: ink @ 0.10.
const HAIRLINE_PX := 3
const HAIRLINE_ALPHA := 0.10
## Dock labels stop scaling at 130 % (Art Bible §9.1); handled by the dock, not here.
const LINE_SPACING_EN := 0.0


## [param palettes] = data/palettes.json; [param text_scale] 1.0 .. 2.0 (X1);
## [param vietnamese] adds the +12 % line spacing; [param reduce_transparency] makes glass opaque.
static func build(palettes: Dictionary, text_scale: float = 1.0, vietnamese: bool = false,
		reduce_transparency: bool = false) -> Theme:
	var ui: Dictionary = palettes["ui"]
	var uid: Dictionary = palettes["ui_derived"]
	var ua: Dictionary = palettes["ui_alpha"]
	var ink := Color.html(String(ui["ink"]))
	var ink_2 := Color.html(String(ui["ink_2"]))
	var surface := Color.html(String(ui["surface"]))
	var surface_hi := Color.html(String(ui["surface_hi"]))
	var primary := Color.html(String(ui["primary"]))
	var primary_pressed := Color.html(String(uid["primary_pressed"]))
	var primary_tint := Color.html(String(uid["primary_tint"]))
	var glass_fill := 1.0 if reduce_transparency else float(ua["glass_faux_fill"])

	var body := load(FONT_BODY) as Font
	var strong := load(FONT_STRONG) as Font
	var heavy := load(FONT_HEAVY) as Font
	var title := load(FONT_TITLE) as Font
	var numerals := load(FONT_NUMERALS) as Font

	var t := Theme.new()
	t.default_font = body
	t.default_font_size = _px(SIZE_BODY, text_scale)
	# --- labels
	t.set_color(&"font_color", &"Label", ink)
	t.set_font(&"font", &"Label", body)
	t.set_font_size(&"font_size", &"Label", _px(SIZE_BODY, text_scale))
	t.set_constant(&"line_spacing", &"Label", _spacing(SIZE_BODY, text_scale, vietnamese))
	_label_variation(t, &"BodyLabel", body, _px(SIZE_BODY, text_scale), ink, _spacing(SIZE_BODY, text_scale, vietnamese))
	_label_variation(t, &"TitleLabel", title, _px(SIZE_TITLE, text_scale), ink,
			_spacing(SIZE_TITLE, text_scale, vietnamese))
	_label_variation(t, &"StrongLabel", strong, _px(SIZE_LABEL, text_scale), ink,
			_spacing(SIZE_LABEL, text_scale, vietnamese))
	_label_variation(t, &"CaptionLabel", strong, _px(SIZE_CAPTION, text_scale), ink,
			_spacing(SIZE_CAPTION, text_scale, vietnamese))
	# ink_2 only on opaque surface / surface_hi, never on glass (Art Bible A7).
	_label_variation(t, &"SecondaryLabel", strong, _px(SIZE_CAPTION, text_scale), ink_2,
			_spacing(SIZE_CAPTION, text_scale, vietnamese))
	_label_variation(t, &"HudNumeral", numerals, _px(SIZE_HUD, text_scale), ink, 0)
	_label_variation(t, &"PriceLabel", title, _px(SIZE_PRICE, text_scale), ink, 0)
	t.set_color(&"font_color", &"RichTextLabel", ink)
	t.set_font(&"normal_font", &"RichTextLabel", body)
	t.set_font(&"bold_font", &"RichTextLabel", strong)
	t.set_font_size(&"normal_font_size", &"RichTextLabel", _px(SIZE_BODY, text_scale))
	t.set_font_size(&"bold_font_size", &"RichTextLabel", _px(SIZE_BODY, text_scale))

	# --- buttons: primary pill by default (no focus ring after taps; 4.6 separates focus kinds)
	var pill := roundi(BUTTON_H * 0.5)
	t.set_stylebox(&"normal", &"Button", _box(primary, pill, E1, ink, BUTTON_PAD_X))
	t.set_stylebox(&"hover", &"Button", _box(primary, pill, E1, ink, BUTTON_PAD_X))
	t.set_stylebox(&"pressed", &"Button", _box(primary_pressed, pill, E1, ink, BUTTON_PAD_X))
	t.set_stylebox(&"hover_pressed", &"Button", _box(primary_pressed, pill, E1, ink, BUTTON_PAD_X))
	t.set_stylebox(&"disabled", &"Button", _box(primary, pill, [], ink, BUTTON_PAD_X))
	t.set_stylebox(&"focus", &"Button", StyleBoxEmpty.new())
	t.set_font(&"font", &"Button", heavy)
	t.set_font_size(&"font_size", &"Button", _px(SIZE_LABEL, text_scale))
	for c: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color",
			&"font_focus_color", &"font_disabled_color"]:
		t.set_color(c, &"Button", surface_hi)
	t.set_type_variation(&"SecondaryButton", &"Button")
	var sec := _box(surface_hi, pill, E1, ink, BUTTON_PAD_X)
	sec.border_color = Color(ink, HAIRLINE_ALPHA)
	sec.set_border_width_all(HAIRLINE_PX)
	t.set_stylebox(&"normal", &"SecondaryButton", sec)
	t.set_stylebox(&"hover", &"SecondaryButton", sec)
	var sec_p := sec.duplicate() as StyleBoxFlat
	sec_p.bg_color = primary_tint
	t.set_stylebox(&"pressed", &"SecondaryButton", sec_p)
	t.set_stylebox(&"hover_pressed", &"SecondaryButton", sec_p)
	for c: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color",
			&"font_focus_color", &"font_disabled_color"]:
		t.set_color(c, &"SecondaryButton", ink)

	# --- panels
	t.set_stylebox(&"panel", &"PanelContainer", StyleBoxEmpty.new())
	_panel_variation(t, &"Card", _box(surface_hi, R_L, E1, ink, CARD_PADDING))
	_panel_variation(t, &"Sheet", _box(Color(surface, glass_fill), R_XL, E3, ink, R_L))
	_panel_variation(t, &"Chip", _box(Color(surface, glass_fill), roundi(float(BUTTON_H) * 0.5), E2, ink, R_XS))
	_panel_variation(t, &"ModalCard", _box(surface_hi, R_L, E3, ink, R_L))

	# --- text input (rename, GDD §7.3)
	var field := _box(surface_hi, R_S, [], ink, R_XS)
	field.border_color = Color(ink, HAIRLINE_ALPHA)
	field.set_border_width_all(HAIRLINE_PX)
	t.set_stylebox(&"normal", &"LineEdit", field)
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = primary
	t.set_stylebox(&"focus", &"LineEdit", field_focus)
	t.set_font(&"font", &"LineEdit", body)
	t.set_font_size(&"font_size", &"LineEdit", _px(SIZE_BODY, text_scale))
	t.set_color(&"font_color", &"LineEdit", ink)
	t.set_color(&"font_placeholder_color", &"LineEdit", ink_2)
	t.set_color(&"caret_color", &"LineEdit", ink)
	t.set_color(&"selection_color", &"LineEdit", primary_tint)

	# --- scrolling: touch-first, thin bars in ink @ 0.25
	var grab := _box(Color(ink, 0.25), R_XS, [], ink, 0)
	for bar: StringName in [&"VScrollBar", &"HScrollBar"]:
		t.set_stylebox(&"scroll", bar, StyleBoxEmpty.new())
		t.set_stylebox(&"grabber", bar, grab)
		t.set_stylebox(&"grabber_highlight", bar, grab)
		t.set_stylebox(&"grabber_pressed", bar, grab)
	return t


## A type-scale size at a Text size setting (X1), for controls that size themselves.
static func px(size: int, text_scale: float) -> int:
	return _px(size, text_scale)


## Extra line spacing: Vietnamese lines get +12 % for stacked marks (synthesis §3).
static func _spacing(size: int, text_scale: float, vietnamese: bool) -> int:
	if not vietnamese:
		return roundi(LINE_SPACING_EN)
	return roundi(float(_px(size, text_scale)) * (I18n.VI_LINE_SPACING_MUL - 1.0))


static func _px(size: int, text_scale: float) -> int:
	return roundi(float(size) * clampf(text_scale, 1.0, 2.0))


static func _label_variation(t: Theme, name: StringName, font: Font, size: int, color: Color,
		line_spacing: int) -> void:
	t.set_type_variation(name, &"Label")
	t.set_font(&"font", name, font)
	t.set_font_size(&"font_size", name, size)
	t.set_color(&"font_color", name, color)
	t.set_constant(&"line_spacing", name, line_spacing)


static func _panel_variation(t: Theme, name: StringName, box: StyleBoxFlat) -> void:
	t.set_type_variation(name, &"PanelContainer")
	t.set_stylebox(&"panel", name, box)


## Rounded fill with an optional elevation shadow [alpha, size, y offset] in ink.
static func _box(fill: Color, radius: int, elevation: Array, ink: Color, pad: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.set_corner_radius_all(radius)
	b.corner_detail = CORNER_DETAIL_SMALL if radius <= R_M else CORNER_DETAIL_LARGE
	b.anti_aliasing = true
	b.set_content_margin_all(pad)
	if elevation.size() == 3:
		b.shadow_color = Color(ink, float(elevation[0]))
		b.shadow_size = int(elevation[1])
		b.shadow_offset = Vector2(0, float(elevation[2]))
	return b
