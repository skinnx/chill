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
## Scrolled content fades out over UiBatch.FADE_BOTTOM_PX (96) at the bottom edge and 24 px at
## the top (round 5, QA r4: the 72 px fade read as an overlap bug); the list ends this far above
## the sheet's bottom so the last card clears the fade.
const FADE_PX := UiBatch.FADE_BOTTOM_PX
## Scroll culling margin (the e1 card shadow reaches 30 px).
const CULL_MARGIN := 36.0
## In-card buttons: 48 dp (Art Bible §9.4 draws 132 with a hit grown into the card padding; a
## Button's hit is its rect, so the visual itself is the 48 dp target).
const CARD_BUTTON_H := 144.0
## Sheet titles sit in the fixed 180 px header band: they stop growing at 130 % (the content
## below scales fully and reflows, Art Bible §9.1).
const TITLE_SCALE_CAP := 1.3
## Minimum touch target, 48 dp (I2).
const MIN_TARGET := 144.0
## A hugging pill is never narrower than 120 dp (a short label still reads as a button).
const MIN_PILL_W := 360.0

var sheet_id: StringName = &""
var title_key: String = ""
var title: Label
var close_button: RoundButton
var body: Control
var header_extra: HBoxContainer
## Built in the night scheme (UiTokens.night_scheme at construction; HudController rebuilds an
## open sheet when the chrome switches).
var night: bool = false
var _swipe: Control
var _drag_from: float = -1.0
var _drag_base: float = 0.0
var _drag_y: float = 0.0
var _drag_v: float = 0.0
var _drag_last_t: float = 0.0
var _built: bool = false
## The scroll list made by [method make_scroll] (its window drives the content fade).
var _fade_scroll: ScrollContainer
var _window := Rect2()


func _init() -> void:
	night = UiTokens.night_scheme
	night_surface = night
	super._init()
	radius = ThemeBuilder.R_XL
	elevation = UiTokens.E3
	live = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if night:
		theme = ThemeBuilder.night_theme()


func _ready() -> void:
	super._ready()
	var was := UiTokens.night_scheme
	UiTokens.night_scheme = night
	_build_chrome()
	build_body()
	_built = true
	refresh_texts()
	UiTokens.night_scheme = was
	# Round 5 draw-call budget: the whole sheet draws by kind (UiBatch), a dozen calls in all.
	UiBatch.adopt(self, z_index)
	if night:
		UiTheme.theme_rebuilt.connect(func(_t: Theme) -> void: theme = ThemeBuilder.night_theme())


func _process(_delta: float) -> void:
	if _fade_scroll == null or not is_instance_valid(_fade_scroll):
		return
	var r := _fade_scroll.get_global_rect()
	if r != _window:
		_window = r
		UiBatch.set_window(r)


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


## A vertical scroll list filling [member body] below [param top] (local px of the body). Its
## content fades out at the window's edges in the shared UI materials (UiBatch, round 5: no
## clip_children mask, which split the list into its own canvas group). Returns the VBox to fill.
func make_scroll(top: float, separation: int = 24) -> VBoxContainer:
	var h := body.size.y - top
	var sc := ScrollContainer.new()
	sc.name = "Scroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.position = Vector2(0.0, top)
	sc.size = Vector2(body.size.x, h)
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	UiBatch.mark_scroll(sc)
	body.add_child(sc)
	_fade_scroll = sc
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override(&"margin_left", roundi(SIDE))
	pad.add_theme_constant_override(&"margin_right", roundi(SIDE))
	pad.add_theme_constant_override(&"margin_top", roundi(UiBatch.FADE_TOP_PX * 0.5))
	pad.add_theme_constant_override(&"margin_bottom", roundi(FADE_PX))
	pad.mouse_filter = Control.MOUSE_FILTER_PASS
	sc.add_child(pad)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", separation)
	list.mouse_filter = Control.MOUSE_FILTER_PASS
	pad.add_child(list)
	# rows scrolled fully out of the window are culled by alpha (the canvas skips a subtree below
	# alpha 0.007; layout untouched), so long lists cost no vertices off screen
	var cull := func() -> void: _cull_rows(sc, list)
	sc.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: cull.call())
	list.sort_children.connect(func() -> void: cull.call_deferred())
	sc.resized.connect(func() -> void: cull.call_deferred())
	return list


## Hides (alpha 0) every row of [param list] (and every cell of a grid row) outside the scroll
## window, plus a shadow margin; partly visible rows draw as usual.
static func _cull_rows(sc: ScrollContainer, list: Control) -> void:
	if not is_instance_valid(sc) or not is_instance_valid(list) or not sc.is_inside_tree():
		return
	var window := sc.get_global_rect().grow(CULL_MARGIN)
	for row: Node in list.get_children():
		var items: Array[Node] = []
		if row is GridContainer:
			items.assign(row.get_children())
		else:
			items.append(row)
		for n: Node in items:
			var c := n as Control
			if c == null:
				continue
			var on := window.intersects(c.get_global_rect())
			c.modulate.a = 1.0 if on else 0.0



func _build_chrome() -> void:
	_swipe = Control.new()
	_swipe.name = "SwipeZone"
	_swipe.position = Vector2.ZERO
	_swipe.size = Vector2(size.x, HEADER_TOP + HEADER_H)
	_swipe.mouse_filter = Control.MOUSE_FILTER_STOP
	_swipe.gui_input.connect(_on_swipe_input)
	add_child(_swipe)
	var grab := UiSurface.make(UiTokens.sc_tinted(&"ink", GRABBER_ALPHA), UiSurface.PILL)
	grab.name = "Grabber"
	grab.position = Vector2((size.x - GRABBER.x) * 0.5, GRABBER_Y)
	grab.size = GRABBER
	_swipe.add_child(grab)
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
	# the scroll clips itself; the tabs above it share the chrome's (absent) clip, so they batch
	body.clip_contents = false
	add_child(body)
	_place_header_extra()


func _place_header_extra() -> void:
	var tw := title.get_combined_minimum_size().x
	var font := title.get_theme_font(&"font")
	if font != null:
		tw = font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title.get_theme_font_size(&"font_size")).x
	header_extra.position = Vector2(TITLE_X + tw + 24.0, HEADER_TOP)
	header_extra.size = Vector2(maxf(close_button.position.x - header_extra.position.x, 0.0), HEADER_H)


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
	return UiSurface.panel(UiTokens.sc(&"surface_hi"), radius_px, level, pad)


## A pill / chip panel of token [param fill] (a batched surface behind its content).
static func chip(fill: StringName, radius_px: float, pad: Vector4, level: int = UiTokens.E0) -> PanelContainer:
	var p := UiSurface.panel(UiTokens.sc(fill), radius_px, level, pad)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Primary (or secondary) pill button with the press feedback wired. Round 4 (QA r3: full-width
## blue slabs read as 2023 Material and flooded the frame): buttons hug their label (min
## MIN_PILL_W), centred; [param hug] false keeps a full-width stack (two-choice dialogs).
static func pill_button(text: String, primary: bool = true, height: float = CARD_BUTTON_H, hug: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(MIN_PILL_W if hug else 0.0, height)
	if hug:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if not primary:
		b.theme_type_variation = &"SecondaryButton"
	# Round 5: the pill is a batched UiSurface behind the button's own text (one draw for every
	# surface, one per font for the text) instead of a StyleBoxFlat polygon per state.
	var empty := StyleBoxEmpty.new()
	empty.set_content_margin_all(ThemeBuilder.BUTTON_PAD_X)
	for st: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"]:
		b.add_theme_stylebox_override(st, empty)
	var surf := UiSurface.attach_to(b, UiSurface.make(Color.WHITE, UiSurface.PILL, UiTokens.E1))
	var night_now := UiTokens.night_scheme
	var sync := func() -> void: _sync_pill(b, surf, night_now)
	b.draw.connect(sync)
	b.button_down.connect(sync)
	b.button_up.connect(sync)
	sync.call()
	PressFeedback.attach(b)
	return b


## The pill's look for its state (ThemeBuilder button styles, as batched surfaces): primary =
## primary_pressed with the top lip, pressed primary_deep, disabled flat; secondary = surface_hi
## with a 1 dp ink hairline, pressed primary_tint, disabled (done) surface without elevation.
static func _sync_pill(b: Button, s: UiSurface, night_built: bool) -> void:
	var was := UiTokens.night_scheme
	UiTokens.night_scheme = night_built
	var down := b.button_pressed or b.get_draw_mode() == BaseButton.DRAW_PRESSED \
			or b.get_draw_mode() == BaseButton.DRAW_HOVER_PRESSED
	if b.theme_type_variation == &"SecondaryButton":
		var idle := UiTokens.sc(&"primary_tint") if down else UiTokens.sc(&"surface_hi")
		s.color = UiTokens.sc(&"surface") if b.disabled else idle
		s.border_px = ThemeBuilder.HAIRLINE_PX
		s.border_color = UiTokens.sc_tinted(&"ink", ThemeBuilder.HAIRLINE_ALPHA)
		s.lip_alpha = 0.0
		s.elevation = UiTokens.E0 if b.disabled else UiTokens.E1
	else:
		s.color = UiTokens.color(&"primary_deep") if down else UiTokens.color(&"primary_pressed")
		s.border_px = 0.0
		s.lip_alpha = 0.0 if down or b.disabled else ThemeBuilder.LIP_ALPHA
		s.elevation = UiTokens.E0 if b.disabled else UiTokens.E1
	UiTokens.night_scheme = was


## A thin divider in ink @ 0.10 (settings rows).
static func divider() -> Control:
	var c := UiSurface.make(UiTokens.sc_tinted(&"ink", UiTokens.alpha(&"divider")), 0.0)
	c.custom_minimum_size = Vector2(0.0, UiTokens.PX_PER_DP)
	return c
