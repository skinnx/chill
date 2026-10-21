class_name UiSheet
extends GlassPanel
## Base bottom sheet (Art Bible §9.4-9.5, GDD §8.1): live glass (the one live surface, C7), r-xl 96
## on all corners, e3, floating 24 px above the dock. A grabber (120 x 12 ink @ 0.25) and the
## header band (Title 84 at x 72; close plate Ø 108 surface_hi with a 180 px hit) form the swipe
## zone: the sheet tracks the finger (`press`) and a release beyond 25 % of its height or faster
## than 1000 px/s dismisses it, otherwise it settles back on `move`. Subclasses fill [member body]
## (local px, below the header) in [method build_body] and may use [method make_scroll].
##
## Geometry (local px, sheet x0 = 24 at the 1080 frame): header 48..228, content from 252.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

signal close_requested

const GRABBER := Vector2(120, 12)
const GRABBER_Y := 22.0
const GRABBER_ALPHA := 0.25
const HEADER_TOP := 48.0
const HEADER_H := 180.0
const TITLE_X := 48.0
const CLOSE_PLATE := 108.0
const CLOSE_HIT := 180.0
const CLOSE_ICON := 48.0
const CONTENT_TOP := 252.0
## Content inset: cards run x 72..1008 on the frame = 48 px inside the sheet.
const SIDE := 48.0
const BOTTOM_PAD := 24.0
## Scrolled content fades out over 72 px at the bottom edge (§9.4).
const FADE_PX := 72.0
## In-card buttons: 48 dp (Art Bible §9.4 draws 132 with a hit grown into the card padding; a
## Button's hit is its rect, so the visual itself is the 48 dp target).
const CARD_BUTTON_H := 144.0
## Sheet titles sit in the fixed 180 px header band: they stop growing at 130 % (the content
## below scales fully and reflows, Art Bible §9.1).
const TITLE_SCALE_CAP := 1.3
## Minimum touch target, 48 dp (I2).
const MIN_TARGET := 144.0

var sheet_id: StringName = &""
var title_key: String = ""
var title: Label
var close_button: RoundButton
var body: Control
var header_extra: HBoxContainer
var _swipe: Control
var _drag_from: float = -1.0
var _drag_base: float = 0.0
var _drag_y: float = 0.0
var _drag_v: float = 0.0
var _drag_last_t: float = 0.0
var _built: bool = false


func _init() -> void:
	super._init()
	radius = ThemeBuilder.R_XL
	elevation = UiTokens.E3
	live = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	super._ready()
	_build_chrome()
	build_body()
	_built = true
	refresh_texts()


func _notification(what: int) -> void:
	if (what == NOTIFICATION_TRANSLATION_CHANGED or what == NOTIFICATION_THEME_CHANGED) and _built:
		refresh_texts.call_deferred()


## Override: build the content into [member body].
func build_body() -> void:
	pass


## Override: re-apply translated strings (language change).
func refresh_texts() -> void:
	if title != null:
		title.text = tr(title_key)
		title.remove_theme_font_size_override(&"font_size")
		var cap := roundi(float(ThemeBuilder.SIZE_TITLE) * TITLE_SCALE_CAP)
		if title.get_theme_font_size(&"font_size") > cap:
			title.add_theme_font_size_override(&"font_size", cap)
		_place_header_extra()


## Override: reflect the latest world state (sim events while open).
func refresh() -> void:
	pass


## A vertical scroll list filling [member body] below [param top] (local px of the body), with the
## 72 px fade mask at the bottom edge: the list sits inside a mask (clip_children) whose alpha
## falls to 0 over the last FADE_PX, so content melts into the glass. Returns the VBox to fill.
func make_scroll(top: float, separation: int = 24) -> VBoxContainer:
	var h := body.size.y - top
	var mask := TextureRect.new()
	mask.name = "FadeMask"
	mask.position = Vector2(0.0, top)
	mask.size = Vector2(body.size.x, h)
	mask.mouse_filter = Control.MOUSE_FILTER_PASS
	mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_offset(0, 1.0 - FADE_PX / maxf(h, FADE_PX))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 256
	mask.texture = gt
	mask.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mask.stretch_mode = TextureRect.STRETCH_SCALE
	body.add_child(mask)
	var sc := ScrollContainer.new()
	sc.name = "Scroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.position = Vector2.ZERO
	sc.size = Vector2(body.size.x, h)
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	mask.add_child(sc)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override(&"margin_left", roundi(SIDE))
	pad.add_theme_constant_override(&"margin_right", roundi(SIDE))
	pad.add_theme_constant_override(&"margin_top", 6)
	pad.add_theme_constant_override(&"margin_bottom", roundi(FADE_PX))
	pad.mouse_filter = Control.MOUSE_FILTER_PASS
	sc.add_child(pad)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", separation)
	list.mouse_filter = Control.MOUSE_FILTER_PASS
	pad.add_child(list)
	return list



func _build_chrome() -> void:
	_swipe = Control.new()
	_swipe.name = "SwipeZone"
	_swipe.position = Vector2.ZERO
	_swipe.size = Vector2(size.x, HEADER_TOP + HEADER_H)
	_swipe.mouse_filter = Control.MOUSE_FILTER_STOP
	_swipe.gui_input.connect(_on_swipe_input)
	_swipe.draw.connect(_draw_grabber)
	add_child(_swipe)
	title = Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.position = Vector2(TITLE_X, HEADER_TOP)
	title.size = Vector2(size.x - TITLE_X - CLOSE_HIT - SIDE, HEADER_H)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(title)
	header_extra = HBoxContainer.new()
	header_extra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_extra.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(header_extra)
	close_button = RoundButton.new()
	close_button.name = "Close"
	close_button.plate_px = CLOSE_PLATE
	close_button.icon_px = CLOSE_ICON
	close_button.icon_name = &"close"
	close_button.size = Vector2(CLOSE_HIT, CLOSE_HIT)
	close_button.position = Vector2(size.x - TITLE_X - CLOSE_PLATE * 0.5 - CLOSE_HIT * 0.5, HEADER_TOP)
	PressFeedback.attach(close_button)
	close_button.pressed.connect(func() -> void: close_requested.emit())
	add_child(close_button)
	body = Control.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.position = Vector2(0.0, CONTENT_TOP)
	body.size = Vector2(size.x, size.y - CONTENT_TOP - BOTTOM_PAD)
	body.clip_contents = true
	add_child(body)
	_place_header_extra()


func _place_header_extra() -> void:
	var tw := title.get_combined_minimum_size().x
	var font := title.get_theme_font(&"font")
	if font != null:
		tw = font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title.get_theme_font_size(&"font_size")).x
	header_extra.position = Vector2(TITLE_X + tw + 24.0, HEADER_TOP)
	header_extra.size = Vector2(maxf(close_button.position.x - header_extra.position.x, 0.0), HEADER_H)


func _draw_grabber() -> void:
	var r := Rect2(Vector2((size.x - GRABBER.x) * 0.5, GRABBER_Y), GRABBER)
	_swipe.draw_style_box(UiTokens.fill_box(UiTokens.tinted(&"ink", GRABBER_ALPHA), GRABBER.y * 0.5), r)


# ------------------------------------------------------------------ swipe to dismiss (GDD §8.2)

func _on_swipe_input(event: InputEvent) -> void:
	var now := Time.get_ticks_msec() * UiTokens.MS
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_drag_from = mb.global_position.y
			_drag_base = position.y
			_drag_y = 0.0
			_drag_v = 0.0
			_drag_last_t = now
			Motion.stop_springs(self)
		elif _drag_from >= 0.0:
			_drag_from = -1.0
			var sw := UiTokens.ui_block("swipe_dismiss")
			if _drag_y > size.y * float(sw.get("distance_frac", 0.25)) or _drag_v > float(sw.get("velocity_px_s", 1000.0)):
				close_requested.emit()
			else:
				Motion.spring_to(self, "position", Vector2(position.x, _drag_base), &"move")
		_swipe.accept_event()
	elif event is InputEventMouseMotion and _drag_from >= 0.0:
		var mm := event as InputEventMouseMotion
		var dy := maxf(0.0, mm.global_position.y - _drag_from)
		var dt := maxf(now - _drag_last_t, 1e-3)
		_drag_v = lerpf(_drag_v, (dy - _drag_y) / dt, 0.5)
		_drag_last_t = now
		_drag_y = dy
		position.y = _drag_base + dy
		FrameGovernor.hold_for(Motion.duration(&"short"))
		_swipe.accept_event()


# ------------------------------------------------------------------ small builders for subclasses

static func label(text: String, variation: StringName, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## A surface_hi card (never glass on glass) with content padding [param pad].
static func card(pad: int = 24, radius_px: float = ThemeBuilder.R_L, level: int = UiTokens.E1) -> PanelContainer:
	var p := PanelContainer.new()
	var box := UiTokens.fill_box(UiTokens.color(&"surface_hi"), radius_px, level)
	box.set_content_margin_all(pad)
	p.add_theme_stylebox_override(&"panel", box)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p


## Primary (or secondary) pill button with the press feedback wired.
static func pill_button(text: String, primary: bool = true, height: float = CARD_BUTTON_H) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0.0, height)
	if not primary:
		b.theme_type_variation = &"SecondaryButton"
	PressFeedback.attach(b)
	return b


## A thin divider in ink @ 0.10 (settings rows).
static func divider() -> Control:
	var c := ColorRect.new()
	c.color = UiTokens.tinted(&"ink", UiTokens.alpha(&"divider"))
	c.custom_minimum_size = Vector2(0.0, UiTokens.PX_PER_DP)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
