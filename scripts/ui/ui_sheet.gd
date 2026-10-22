class_name UiSheet
extends GlassPanel
## Base bottom sheet (Art Bible §9.4-9.5, GDD §8.1): live glass (the one live surface, C7), r-xl 96
## on all corners, e3, floating 24 px above the dock. A grabber (120 x 12 ink @ 0.25) and the
## header band (Title 84 at x 72; close plate Ø 108 surface_hi with a 180 px hit) form the swipe
## zone: the sheet tracks the finger (`press`) and a release beyond 25 % of its height or faster
## than 1000 px/s dismisses it, otherwise it settles back on `move`. Subclasses fill [member body]
## (local px, below the header) in [method build_body] and may use [method make_scroll].
##
## Round 6 (device QA 720x1600: "the content window is small, cards are cut at the bottom"):
## two detents. The sheet opens at [member h_medium] (0.56 H on 16:9, up to 0.66 H on tall
## phones) and the grabber / header drags it up to [member h_large] (everything up to the top bar,
## at most 0.80 H) or back down; below the medium detent the same drag dismisses. The body and the
## scroll list are anchored to the sheet, so they follow its height. The scroll list keeps its
## last item clear of the rounded bottom edge (bottom padding) and shows soft fades only at the
## edges where more content waits. [member lift] raises the whole sheet above the on-screen
## keyboard (SheetHost).
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
## Room under the last scrolled item, so it never sits on the rounded bottom edge.
const LIST_END_PAD := 48.0
const LIST_TOP_PAD := 12.0
## Tabs -> scroll list: the segment hit's 24 px reach + 8 dp, less the list's own top pad.
const TABS_GAP := 24.0 + 24.0 - LIST_TOP_PAD
## A drag past the large detent stretches a little (rubber band), at most this far.
const OVERDRAG_PX := 48.0
const OVERDRAG_K := 0.3
## Release speed (px/s) that picks the detent in the fling direction.
const DETENT_FLING := 600.0
## The swipe velocity window, the same number WorldPan uses (motion_tokens world.pan).
const VELOCITY_WINDOW_S := 0.1
const DETENT_SPRING := &"move"
## Scrolled content fades out over UiBatch.FADE_BOTTOM_PX at the bottom edge and FADE_TOP_PX at
## the top, each only while there is more to scroll that way (round 6).
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
## Geometry, set by SheetHost ([method configure]): the bottom edge at rest (screen px) and the
## two detent heights. 0 = unmanaged (tests size the sheet themselves).
var rest_bottom: float = 0.0
## At the large detent.
var expanded: bool = false
var h_medium: float = 0.0
var h_large: float = 0.0
## The current height (springs between the detents).
var sheet_h: float = 0.0:
	set(v):
		sheet_h = v
		_apply_geometry()
## Slide below the rest position (the open rise, a dismiss drag, the exit).
var rise: float = 0.0:
	set(v):
		rise = v
		_apply_geometry()
## Leaving (SheetHost close / swap): input is off, the rect still consumes presses via the scrim.
var closing: bool = false
## Raise above the on-screen keyboard (SheetHost).
var lift: float = 0.0:
	set(v):
		lift = v
		_apply_geometry()
var _swipe: Control
var _drag_from: float = -1.0
var _drag_h0: float = 0.0
var _drag_base: float = 0.0
var _drag_y: float = 0.0
## (offset px, time s) samples of the swipe, pruned to VELOCITY_WINDOW_S.
var _samples: Array[Vector2] = []
var _built: bool = false
## The scroll list made by [method make_scroll] (its window drives the content fade).
var _fade_scroll: ScrollContainer
var _window := Rect2()
var _bands := Vector2(-1.0, -1.0)


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
	if _fade_scroll == null or not is_instance_valid(_fade_scroll) or not _fade_scroll.is_visible_in_tree():
		return
	var r := _fade_scroll.get_global_rect()
	# fades only where more content waits (a hard edge reads as "cut off", a fade on the first
	# or the last item reads as an overlap bug): they grow in with the scroll distance
	var bar := _fade_scroll.get_v_scroll_bar()
	var above := float(_fade_scroll.scroll_vertical)
	var below := maxf(bar.max_value - bar.page - above, 0.0)
	# (>= 1 px: a zero-width smoothstep is undefined in GLSL)
	var bands := Vector2(maxf(UiBatch.FADE_TOP_PX * clampf(above / UiBatch.FADE_TOP_PX, 0.0, 1.0), 1.0),
			maxf(UiBatch.FADE_BOTTOM_PX * clampf(below / UiBatch.FADE_BOTTOM_PX, 0.0, 1.0), 1.0))
	if r != _window or not bands.is_equal_approx(_bands):
		_window = r
		_bands = bands
		UiBatch.set_window(r, bands)


## SheetHost: places the sheet (x, width, bottom edge) with its two detents and opens it at the
## medium one (or keeps the current detent when [param keep] and it is expanded).
func configure(x: float, width: float, bottom: float, medium: float, large: float, keep: bool = false) -> void:
	rest_bottom = bottom
	h_medium = medium
	h_large = maxf(large, medium)
	position.x = x
	size.x = width
	Motion.stop_springs(self)
	sheet_h = h_large if keep and expanded else h_medium
	if not (keep and expanded):
		expanded = false


## Springs to the large ([param on]) or the medium detent.
func expand(on: bool, animate: bool = true) -> void:
	if rest_bottom <= 0.0:
		return
	expanded = on and h_large > h_medium + 1.0
	var to := h_large if expanded else h_medium
	if animate:
		Motion.spring_to(self, "sheet_h", to, DETENT_SPRING)
		FrameGovernor.hold_for(Motion.duration(&"standard"))
	else:
		sheet_h = to


func _apply_geometry() -> void:
	if rest_bottom <= 0.0 or sheet_h <= 0.0:
		return
	size.y = sheet_h
	position.y = rest_bottom - lift - sheet_h + rise


## The scroll list (or null): QA, keyboard lift.
func scroll_list() -> ScrollContainer:
	return _fade_scroll if _fade_scroll != null and is_instance_valid(_fade_scroll) else null


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
	var sc := ScrollContainer.new()
	sc.name = "Scroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	# scroll deadzone = the 10 dp button slop; presses during a fling only catch it (TapGuard)
	TapGuard.watch_scroll(sc)
	# the list's clip is the scroll window: everything inside it moves and clips with it
	sc.clip_contents = true
	UiBatch.mark_scroll(sc)
	body.add_child(sc)
	# anchored to the body, so the window follows the sheet's detent height
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.offset_left = 0.0
	sc.offset_right = 0.0
	sc.offset_top = top
	sc.offset_bottom = 0.0
	_fade_scroll = sc
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override(&"margin_left", roundi(SIDE))
	pad.add_theme_constant_override(&"margin_right", roundi(SIDE))
	pad.add_theme_constant_override(&"margin_top", roundi(LIST_TOP_PAD))
	pad.add_theme_constant_override(&"margin_bottom", roundi(LIST_END_PAD))
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


## Keeps the scroll list's top [param gap] px below [param c] (tabs above the list grow with
## large text or a wrapped option, so the list must follow them). The default keeps the first
## card >= 8 dp below the tabs' hit, which reaches Segmented.HIT_GROW under the track (round 7).
func keep_scroll_below(c: Control, gap: float = TABS_GAP, at_least: float = 0.0) -> void:
	var sc := _fade_scroll
	var place := func() -> void:
		if is_instance_valid(sc) and is_instance_valid(c):
			sc.offset_top = maxf(c.position.y + c.size.y + gap, at_least)
	c.resized.connect(place)
	place.call()


## Hides (alpha 0) every row of [param list] (and every cell of a grid row) outside the scroll
## window, plus a shadow margin; partly visible rows draw as usual. Round 6: measured in the
## scroll's content space (scroll_vertical), not with global rects: `value_changed` fires before
## the ScrollContainer moves its content, so global rects were one scroll step stale and a long
## jump (a fling, QA --qa-scroll) culled exactly the rows coming into view.
static func _cull_rows(sc: ScrollContainer, list: Control) -> void:
	if not is_instance_valid(sc) or not is_instance_valid(list) or not sc.is_inside_tree():
		return
	var top := float(sc.scroll_vertical) - CULL_MARGIN
	var bottom := float(sc.scroll_vertical) + sc.size.y + CULL_MARGIN
	var base := _offset_in(list, sc)
	for row: Node in list.get_children():
		var rc := row as Control
		if rc == null:
			continue
		var items: Array[Node] = []
		if row is GridContainer:
			items.assign(row.get_children())
		else:
			items.append(row)
		for n: Node in items:
			var c := n as Control
			if c == null:
				continue
			var y := base + rc.position.y + (c.position.y if c != rc else 0.0)
			var on := y + c.size.y >= top and y <= bottom
			c.modulate.a = 1.0 if on else 0.0


## [param c]'s y inside the scroll's content (the sum of positions below the scrolled child).
static func _offset_in(c: Control, sc: ScrollContainer) -> float:
	var y := 0.0
	var n: Node = c
	while n != null and n.get_parent() != sc:
		y += (n as Control).position.y if n is Control else 0.0
		n = n.get_parent()
	return y


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
	# the scroll clips itself; the tabs above it share the chrome's (absent) clip, so they batch
	body.clip_contents = false
	add_child(body)
	# anchored: the body follows the sheet between its detents
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 0.0
	body.offset_right = 0.0
	body.offset_top = CONTENT_TOP
	body.offset_bottom = -BOTTOM_PAD
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
			drag_begin(mb.global_position.y, now)
		elif _drag_from >= 0.0:
			drag_end(now)
		_swipe.accept_event()
	elif event is InputEventMouseMotion and _drag_from >= 0.0:
		drag_to((event as InputEventMouseMotion).global_position.y, now)
		_swipe.accept_event()


## The swipe's speed in px/s over the last [constant VELOCITY_WINDOW_S], and **0 when the finger
## has rested** for longer than that (round 8). This replaced a per-EVENT exponential average
## (alpha 0.5), which had two faults. Its time constant was the frame interval, because Godot
## merges input once per rendered frame (ARCHITECTURE §3.5), so the same flick measured ~1,135 px/s
## at 60 fps and ~920 px/s at 30 - one phone dismissed the sheet and another bounced it back. And
## it never decayed: pull a sheet down a little, hold it there to look at the world behind it, lift
## - and the sheet closed on the speed of a pull that had finished a second ago. This is the same
## time-windowed estimate [WorldPan] uses, with the same staleness guard.
func drag_velocity(now: float) -> float:
	if _samples.size() < 2:
		return 0.0
	var first := _samples[0]
	var last := _samples[_samples.size() - 1]
	var dt := last.y - first.y
	if dt <= 1e-3 or now - last.y > VELOCITY_WINDOW_S:
		return 0.0
	return (last.x - first.x) / dt


func _sample(dy: float, now: float) -> void:
	_samples.append(Vector2(dy, now))
	while _samples.size() > 2 and now - _samples[0].y > VELOCITY_WINDOW_S:
		_samples.remove_at(0)


## The header drag (public for tests): up toward the large detent, down to the medium one and,
## below it, out (dismiss).
func drag_begin(y: float, now: float) -> void:
	_drag_from = y
	_drag_h0 = sheet_h if rest_bottom > 0.0 else size.y
	_drag_base = position.y - rise
	_drag_y = 0.0
	_samples.clear()
	_samples.append(Vector2(0.0, now))
	Motion.stop_springs(self)


func drag_to(y: float, now: float) -> void:
	var dy := y - _drag_from
	_sample(dy, now)
	_drag_y = dy
	if rest_bottom <= 0.0:
		rise = maxf(dy, 0.0)
		position.y = _drag_base + rise
	else:
		var want := _drag_h0 - dy
		var top_h := h_large
		if want > top_h:
			sheet_h = top_h + minf((want - top_h) * OVERDRAG_K, OVERDRAG_PX)
			rise = 0.0
		elif want < h_medium:
			sheet_h = h_medium
			rise = h_medium - want
		else:
			sheet_h = want
			rise = 0.0
	FrameGovernor.hold_for(Motion.duration(&"short"))


func drag_end(now: float = -1.0) -> void:
	_drag_from = -1.0
	var v := drag_velocity(now if now >= 0.0 else Time.get_ticks_msec() * UiTokens.MS)
	var sw := UiTokens.ui_block("swipe_dismiss")
	var dist := float(sw.get("distance_frac", 0.25)) * (h_medium if h_medium > 0.0 else size.y)
	var fast := float(sw.get("velocity_px_s", 1000.0))
	var at_medium := rest_bottom <= 0.0 or sheet_h <= h_medium + 1.0
	if rise > dist or (at_medium and v > fast and rise > 0.0):
		close_requested.emit()
		return
	if rest_bottom <= 0.0:
		Motion.spring_to(self, "position", Vector2(position.x, _drag_base), DETENT_SPRING)
		rise = 0.0
		return
	Motion.spring_to(self, "rise", 0.0, DETENT_SPRING)
	var up := v < -DETENT_FLING
	var down := v > DETENT_FLING
	var nearer_large := absf(sheet_h - h_large) < absf(sheet_h - h_medium)
	expand(up or (nearer_large and not down))


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
