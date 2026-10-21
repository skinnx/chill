class_name DockView
extends Control
## The bottom dock (Art Bible §9.4-9.5, GDD §8.1, I2; round-3 direction: a Liquid-Glass-era tab
## bar with M3-Expressive springs): one faux-glass pill x 24..W-24, 240 tall, anchored at
## bottom = H - max(safe bottom, 127) - 12, holding four EQUAL tabs in the order
## [Settings][Garden][Basket][Album] (mirrored when left-handed). Each tab is a 252 x 216 hit
## (84 x 72 dp) with an 84 px duotone icon over its Caption label (never a label squeezed inside a
## circle). The open sheet's tab sits in a primary_tint selection capsule that springs between
## tabs on `move` and fades out when no sheet is open; its icon takes the accent and its label the
## primary. Touch-down: the tab squashes on its baseline (0.92), a press capsule appears under it
## and a ripple grows from the finger, all in the same frame.
## Basket: coral count badge at the icon's shoulder, gold ring_fill (count / 24) around the icon
## and a brim sparkle when full. During onboarding Garden, Basket and Album are "asleep" (50 %,
## still tappable) until their moment. Labels stop growing at 130 % text and shrink to fit the tab.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

signal button_pressed(id: StringName)

const ORDER: Array[StringName] = [&"settings", &"garden", &"basket", &"album"]
const LABEL_KEYS := {&"settings": "DOCK_SETTINGS", &"garden": "DOCK_GARDEN", &"basket": "DOCK_BASKET",
	&"album": "DOCK_ALBUM"}
const PILL_H := 240.0
const PILL_SIDE := 24.0
const BOTTOM_MIN := 127.0
const BOTTOM_GAP := 12.0
## Tabs inset from the pill edge (the capsule's concentric gap: 120 - 12 = 108 radius).
const PILL_INSET := 12.0
const ICON_PX := 84.0
const LABEL_GAP := 6.0
## Label side padding inside a tab.
const LABEL_PAD := 18.0
## Smallest label size when shrinking to fit (Caption 36 is the floor at 100 %; shrink only
## happens for long translations at large text).
const LABEL_MIN_PX := 30
## Dock labels stop growing at 130 % text size (Art Bible §9.1).
const LABEL_SCALE_CAP := 1.3
## Press depth (2 x ui.press_scale's dip = 0.92) with an M3 squash.
const PRESS_DEPTH := 2.0
## The press capsule under a pressed, unselected tab: primary_tint at this alpha.
const PRESS_CAPSULE_ALPHA := 0.75
## Selection capsule hairline: primary at this alpha, 1 dp.
const CAPSULE_LINE_ALPHA := 0.16
## ... and at night the hairline is the glass rim colour, a little stronger (the capsule's edge).
const NIGHT_LINE_ALPHA := 0.5
const BADGE_MIN := 48.0
const BADGE_PAD := 12.0
## Badge centre from the icon centre (the icon's top-right shoulder).
const BADGE_OFFSET := Vector2(42.0, -36.0)
const RING_SHADER := "res://shaders/ui/ring_fill.gdshader"
const RING_PX := 126.0
const RING_DP := 3.0
const SPARKLE_PX := 30.0
## Brim sparkle: 3 sparkles every 600/76 s (Art Bible §9.4, ambient k 76).
const BRIM_PERIOD_S := 600.0 / 76.0
const BRIM_SPARKLES := 3
const NEW_DOT_PX := 27.0
const NEW_DOT_OFFSET := Vector2(36.0, -33.0)
## Draw order lifts, shared with the top bar so the whole HUD batches by kind: glass at z 0,
## badge plates z 1, every icon (one atlas) z 2, every label z 3.
const Z_BADGES := 1
const Z_ICONS := 2
const Z_LABELS := 3
## Onboarding (GDD §3.4): "the Basket button glints every 6 s" until the first collect.
const GLINT_PERIOD_S := 6.0

var left_handed: bool = false
var buttons: Dictionary = {}
var pill: GlassPanel
## Selection capsule x (px, screen) and alpha; both spring (`move`, `short`).
var cap_x: float = 0.0:
	set(v):
		cap_x = v
		if _plates != null:
			_plates.queue_redraw()
var cap_a: float = 0.0:
	set(v):
		cap_a = v
		if _plates != null:
			_plates.queue_redraw()
var _active: StringName = &""
var _plates: Control
var _badge: Control
var _badge_label: Label
var _ring: ColorRect
var _ring_mat: ShaderMaterial
var _new_dot: Control
var _sparkles: Array[TextureRect] = []
var _brim_t: float = 0.0
var _full: bool = false
var _glint: bool = false
var _was_pressing: bool = false
var _basket_slots: int = 24
var _screen: Vector2 = Vector2(1080, 1920)
var _safe_bottom: float = 0.0
var _tab_size: Vector2 = Vector2(252, 216)
var _night_k: float = 0.0
var _night_icons: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_basket_slots = int(ContentRegistry.content.economy.get("basket_slots", _basket_slots))
	pill = GlassPanel.new()
	pill.name = "Pill"
	pill.night_aware = true
	add_child(pill)
	# Draw-call budget (Art Bible §4.19: HUD + dock ~14): the capsules are drawn by one layer
	# (one batch), the icons come from one atlas and sit next to each other in draw order (one
	# batch), and the labels are lifted to z 1 so they draw together (one batch).
	_plates = Control.new()
	_plates.name = "Capsules"
	_plates.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plates.set_anchors_preset(Control.PRESET_FULL_RECT)
	_plates.draw.connect(_draw_capsules)
	add_child(_plates)
	_build_ring()
	var atlas := Icons.hud_atlas()
	for id: StringName in ORDER:
		var b := RoundButton.new()
		b.name = String(id).capitalize()
		b.draw_plate = false
		b.icon_px = ICON_PX
		b.label_gap = LABEL_GAP
		b.tint_active_label = true
		b.set_meta(&"ripple_owner_shape", true)
		b.set_meta(PressFeedback.META_RIPPLE_ON_DARK, false)
		b.icon_textures = _tab_icons(atlas, id)
		b.icon_name = id
		b.icon_z = Z_ICONS
		b.set_label(tr(String(LABEL_KEYS[id])))
		b.label.z_index = Z_LABELS
		b.label.clip_text = false
		b.tooltip_text = tr(String(LABEL_KEYS[id]))
		PressFeedback.attach(b, PressFeedback.CUE_TOUCH, PRESS_DEPTH, true)
		b.pressed.connect(func() -> void: button_pressed.emit(id))
		b.appearance_changed.connect(_plates.queue_redraw)
		add_child(b)
		buttons[id] = b
	_build_basket_extras()
	_fit_labels()
	UiTheme.theme_rebuilt.connect(func(_t: Theme) -> void: _fit_labels.call_deferred())
	Game.basket_changed.connect(func(n: int, _dew: int) -> void: set_basket_count(n))
	if Game.sim != null:
		set_basket_count(Game.sim.state.basket.size())


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and not buttons.is_empty():
		_fit_labels.call_deferred()
	if what == NOTIFICATION_TRANSLATION_CHANGED and not buttons.is_empty():
		for id: StringName in ORDER:
			(buttons[id] as RoundButton).set_label(tr(String(LABEL_KEYS[id])))
			(buttons[id] as RoundButton).tooltip_text = tr(String(LABEL_KEYS[id]))
		_fit_labels.call_deferred()


func _tab_icons(atlas: Dictionary, id: StringName) -> Array[Texture2D]:
	var icons: Array[Texture2D] = [atlas[Icons.atlas_key(id, ICON_PX, false, _night_icons)] as Texture2D,
			atlas[Icons.atlas_key(id, ICON_PX, true, _night_icons)] as Texture2D]
	return icons


## Night chrome (palettes ui_alpha.night_chrome; the pill glass follows GlassPanel.night_k): tab
## labels lerp to night_ink, the capsules and the basket ring track to night_capsule /
## night_track, ripples turn light (white, capped) and the icons take their night variant at the
## crossfade's midpoint.
func set_night(k: float) -> void:
	_night_k = clampf(k, 0.0, 1.0)
	var icons_night := _night_k >= 0.5
	var swap := icons_night != _night_icons
	_night_icons = icons_night
	var atlas := Icons.hud_atlas()
	for id: StringName in ORDER:
		var b := buttons[id] as RoundButton
		b.night_k = _night_k
		b.set_meta(PressFeedback.META_RIPPLE_ON_DARK, icons_night)
		if swap:
			b.icon_textures = _tab_icons(atlas, id)
			b.icon_name = id
	_ring_mat.set_shader_parameter(&"u_track", UiTokens.color(&"gold_tint").lerp(UiTokens.color(&"night_track"), _night_k))
	_plates.queue_redraw()


func _capsule_color() -> Color:
	return UiTokens.color(&"primary_tint").lerp(UiTokens.color(&"night_capsule"), _night_k)


func button(id: StringName) -> RoundButton:
	return buttons.get(id) as RoundButton


## The pill's rect in screen px (sheets sit 24 px above its top).
func pill_rect() -> Rect2:
	return Rect2(pill.position, pill.size)


func layout(screen: Vector2, safe_bottom: float) -> void:
	_screen = screen
	_safe_bottom = safe_bottom
	var bottom := screen.y - maxf(safe_bottom, BOTTOM_MIN) - BOTTOM_GAP
	pill.position = Vector2(PILL_SIDE, bottom - PILL_H)
	pill.size = Vector2(screen.x - PILL_SIDE * 2.0, PILL_H)
	_tab_size = Vector2((pill.size.x - PILL_INSET * 2.0) / float(ORDER.size()), PILL_H - PILL_INSET * 2.0)
	for i in ORDER.size():
		var b := buttons[_id_at(i)] as RoundButton
		b.position = Vector2(pill.position.x + PILL_INSET + _tab_size.x * float(i), pill.position.y + PILL_INSET)
		b.size = _tab_size
		b.plate_px = _tab_size.x
		b.label_w = _tab_size.x - LABEL_PAD * 2.0
		b.set_meta(PressFeedback.META_RIPPLE_RECT, Rect2(Vector2.ZERO, _tab_size))
		b.set_meta(PressFeedback.META_RIPPLE_RADIUS, _tab_size.y * 0.5)
		b.pivot_offset = Vector2(_tab_size.x * 0.5, _tab_size.y)
	if _active != &"":
		Motion.stop_springs(self)
		cap_x = _tab_x(_active)
	_plates.queue_redraw()
	_place_basket_extras()


## The open sheet's tab (&"" = none): the capsule springs there (or fades in at it).
func set_active(id: StringName) -> void:
	for k: StringName in ORDER:
		(buttons[k] as RoundButton).active = k == id
	var was := _active
	_active = id
	if id == &"":
		Motion.spring_to(self, "cap_a", 0.0, &"press")
		return
	var x := _tab_x(id)
	if was == &"" or cap_a < 0.05 or Motion.reduce_motion:
		Motion.stop_springs(self)
		cap_x = x
		cap_a = 0.0 if not Motion.reduce_motion else 1.0
		Motion.spring_to(self, "cap_a", 1.0, &"press")
	else:
		Motion.spring_to(self, "cap_x", x, &"move")
		Motion.spring_to(self, "cap_a", 1.0, &"press")
	FrameGovernor.hold_for(Motion.duration(&"standard"))


## QA: snaps the capsule (no spring) for deterministic stills.
func snap_active() -> void:
	Motion.stop_springs(self)
	if _active != &"":
		cap_x = _tab_x(_active)
		cap_a = 1.0
	else:
		cap_a = 0.0


## Onboarding (GDD §3.4): which tabs are awake.
func set_asleep(id: StringName, asleep: bool) -> void:
	var b := buttons.get(id) as RoundButton
	if b != null and b.asleep != asleep:
		b.asleep = asleep
		if not asleep:
			b.scale = Vector2.ONE * float(UiTokens.ui_block("counter_tick").get("scale", 1.08))
			Motion.spring_to(b, "scale", Vector2.ONE, &"pop")


func set_new_dot(on: bool) -> void:
	_new_dot.visible = on


func set_basket_count(n: int) -> void:
	_badge.visible = n > 0
	_badge_label.text = str(n)
	_full = n >= _basket_slots
	_ring_mat.set_shader_parameter(&"u_progress", clampf(float(n) / float(_basket_slots), 0.0, 1.0))
	_ring.visible = n > 0
	_place_basket_extras()
	_sync_sparkles()


## Onboarding glint on the Basket tab (a gift waits and nothing was ever collected).
func set_glint(on: bool) -> void:
	if _glint != on:
		_glint = on
		_brim_t = 0.0
		_sync_sparkles()


func _sync_sparkles() -> void:
	if not (_full or _glint):
		for s: TextureRect in _sparkles:
			s.visible = false


func _id_at(i: int) -> StringName:
	return ORDER[ORDER.size() - 1 - i] if left_handed else ORDER[i]


func _tab_x(id: StringName) -> float:
	var b := buttons.get(id) as RoundButton
	return b.position.x if b != null else 0.0


func _process(delta: float) -> void:
	# The capsule layer and the basket extras follow each tab's press scale (PressFeedback).
	var pressing := false
	for b: Variant in buttons.values():
		if not (b as RoundButton).scale.is_equal_approx(Vector2.ONE):
			pressing = true
	if pressing or _was_pressing:
		_plates.queue_redraw()
		_place_basket_extras()
	_was_pressing = pressing
	if not (_full or _glint):
		return
	_brim_t = fposmod(_brim_t + delta, GLINT_PERIOD_S if _glint and not _full else BRIM_PERIOD_S)
	var basket := buttons[&"basket"] as RoundButton
	var c := basket.position + basket.icon_center()
	for i in _sparkles.size():
		var s := _sparkles[i]
		var u := clampf((_brim_t - float(i) * 0.18) / 0.9, 0.0, 1.0)
		s.visible = u > 0.0 and u < 1.0
		var ang := -PI * 0.5 + (float(i) - 1.0) * 0.7
		var r := RING_PX * 0.5 + 6.0 + 18.0 * u
		s.position = c + Vector2(cos(ang), sin(ang)) * r - Vector2(SPARKLE_PX, SPARKLE_PX) * 0.5
		s.modulate.a = sin(u * PI)
		s.scale = Vector2.ONE * (0.6 + 0.4 * sin(u * PI))


func _build_ring() -> void:
	_ring = ColorRect.new()
	_ring.name = "BasketRing"
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.size = Vector2(RING_PX, RING_PX)
	_ring.pivot_offset = _ring.size * 0.5
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = load(RING_SHADER) as Shader
	_ring_mat.set_shader_parameter(&"u_size", Vector2(RING_PX, RING_PX))
	_ring_mat.set_shader_parameter(&"u_stroke", RING_DP * UiTokens.PX_PER_DP)
	_ring_mat.set_shader_parameter(&"u_color", UiTokens.color(&"gold"))
	_ring_mat.set_shader_parameter(&"u_track", UiTokens.color(&"gold_tint"))
	_ring.material = _ring_mat
	add_child(_ring)


## A tab's rect on screen with its press transform (scale about the baseline pivot).
func _tab_rect(b: RoundButton, x: float) -> Rect2:
	var s := b.scale
	var piv := Vector2(x, b.position.y) + b.pivot_offset
	var p0 := Vector2(x, b.position.y)
	var pos := piv + (p0 - piv) * s
	return Rect2(pos, b.size * s)


func _draw_capsules() -> void:
	var r := _tab_size.y * 0.5
	# press capsules under pressed, unselected tabs
	for id: StringName in ORDER:
		var b := buttons.get(id) as RoundButton
		if b == null or not b.visible or b.active or not b.looks_pressed():
			continue
		var rect := _tab_rect(b, b.position.x)
		var pc := _capsule_color()
		pc.a = PRESS_CAPSULE_ALPHA
		_plates.draw_style_box(UiTokens.fill_box(pc, r), rect)
	if cap_a <= 0.01 or _active == &"":
		return
	var ab := buttons.get(_active) as RoundButton
	var rect2 := _tab_rect(ab, cap_x)
	var fill := _capsule_color()
	fill.a = clampf(cap_a, 0.0, 1.0)
	var box := UiTokens.fill_box(fill, rect2.size.y * 0.5, UiTokens.E1)
	box.shadow_color.a *= clampf(cap_a, 0.0, 1.0)
	var line := UiTokens.color(&"primary").lerp(UiTokens.color(&"night_glass_rim"), _night_k)
	line.a = lerpf(CAPSULE_LINE_ALPHA, NIGHT_LINE_ALPHA, _night_k) * clampf(cap_a, 0.0, 1.0)
	box.border_color = line
	box.set_border_width_all(roundi(UiTokens.PX_PER_DP))
	_plates.draw_style_box(box, rect2)


func _build_basket_extras() -> void:
	var basket := buttons[&"basket"] as RoundButton
	_badge = Control.new()
	_badge.z_index = Z_BADGES
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.draw.connect(func() -> void:
		_badge.draw_style_box(UiTokens.fill_box(UiTokens.color(&"coral"), _badge.size.y * 0.5, UiTokens.E1),
				Rect2(Vector2.ZERO, _badge.size)))
	basket.add_child(_badge)
	_badge_label = Label.new()
	_badge_label.z_index = Z_LABELS - Z_BADGES  # relative to the badge plate
	_badge_label.theme_type_variation = &"CaptionLabel"
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_child(_badge_label)
	_new_dot = Control.new()
	_new_dot.z_index = Z_BADGES
	_new_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_new_dot.size = Vector2(NEW_DOT_PX, NEW_DOT_PX)
	_new_dot.visible = false
	_new_dot.draw.connect(func() -> void:
		_new_dot.draw_style_box(UiTokens.fill_box(UiTokens.color(&"coral"), NEW_DOT_PX * 0.5, UiTokens.E1),
				Rect2(Vector2.ZERO, _new_dot.size)))
	(buttons[&"garden"] as RoundButton).add_child(_new_dot)
	var atlas_sparkle := Icons.hud_atlas().get(Icons.atlas_key(&"sparkle", SPARKLE_PX)) as Texture2D
	for i in BRIM_SPARKLES:
		var s := Icons.rect(&"sparkle", SPARKLE_PX)
		s.texture = atlas_sparkle
		s.z_index = Z_ICONS
		s.pivot_offset = Vector2(SPARKLE_PX, SPARKLE_PX) * 0.5
		s.visible = false
		add_child(s)
		_sparkles.append(s)


func _place_basket_extras() -> void:
	var basket := buttons[&"basket"] as RoundButton
	var ic := basket.icon_center()
	var piv := basket.position + basket.pivot_offset
	var ic_screen := piv + (basket.position + ic - piv) * basket.scale
	_ring.position = ic_screen - Vector2(RING_PX, RING_PX) * 0.5
	_ring.scale = basket.scale
	var lw := _badge_label.get_combined_minimum_size()
	var bw := maxf(BADGE_MIN, lw.x + BADGE_PAD * 2.0)
	var bh := maxf(BADGE_MIN, lw.y)
	_badge.size = Vector2(bw, bh)
	_badge.position = ic + BADGE_OFFSET - Vector2(bw * 0.5, bh * 0.5)
	_badge_label.size = _badge.size
	_badge.queue_redraw()
	var garden := buttons[&"garden"] as RoundButton
	_new_dot.position = garden.icon_center() + NEW_DOT_OFFSET - _new_dot.size * 0.5


## Dock labels cap at 130 % text size (§9.1) and shrink to fit the tab (long translations at
## large text), so a label never crosses the capsule edge.
func _fit_labels() -> void:
	var cap := roundi(float(ThemeBuilder.SIZE_CAPTION) * LABEL_SCALE_CAP)
	for id: StringName in ORDER:
		var b := buttons[id] as RoundButton
		if b.label == null:
			continue
		b.label.remove_theme_font_size_override(&"font_size")
		var fs := mini(b.label.get_theme_font_size(&"font_size"), cap)
		var font := b.label.get_theme_font(&"font")
		var max_w := (_tab_size.x - LABEL_PAD * 2.0)
		while font != null and fs > LABEL_MIN_PX and \
				font.get_string_size(b.label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
			fs -= 1
		b.label.add_theme_font_size_override(&"font_size", fs)
		b.set_label(b.label.text)
	_badge_label.remove_theme_font_size_override(&"font_size")
	if _badge_label.get_theme_font_size(&"font_size") > cap:
		_badge_label.add_theme_font_size_override(&"font_size", cap)
	_place_basket_extras()
