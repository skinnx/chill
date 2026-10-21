class_name DockView
extends Control
## The bottom dock (Art Bible §9.4-9.5, GDD §8.1, I2): a faux-glass pill x 24..W-24, 240 tall,
## anchored at bottom = H - max(safe bottom, 127) - 12, with four surface_hi plates in the order
## [Settings][Garden][Basket][Album] (mirrored when left-handed). Garden and Basket are the 72 dp
## plates (the frequent pair, centre), Settings and Album 56 dp; every hit is 228 x 228 (76 dp).
## Basket: coral count badge, gold ring_fill (count / 24) and a brim sparkle when full. During
## onboarding Garden, Basket and Album are "asleep" (50 %, still tappable) until their moment.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

signal button_pressed(id: StringName)

const ORDER: Array[StringName] = [&"settings", &"garden", &"basket", &"album"]
const LABEL_KEYS := {&"settings": "DOCK_SETTINGS", &"garden": "DOCK_GARDEN", &"basket": "DOCK_BASKET",
	&"album": "DOCK_ALBUM"}
const BIG: Array[StringName] = [&"garden", &"basket"]
const PILL_H := 240.0
const PILL_SIDE := 24.0
const BOTTOM_MIN := 127.0
const BOTTOM_GAP := 12.0
const HIT := 228.0
const PLATE_BIG := 216.0
const PLATE_SMALL := 168.0
const ICON_BIG := 84.0
const ICON_SMALL := 72.0
## Dock labels stop growing at 130 % text size (Art Bible §9.1).
const LABEL_SCALE_CAP := 1.3
const BADGE_MIN := 48.0
const BADGE_PAD := 12.0
const RING_SHADER := "res://shaders/ui/ring_fill.gdshader"
const RING_PX := 132.0
const RING_DP := 3.0
const SPARKLE_PX := 30.0
## Brim sparkle: 3 sparkles every 600/76 s (Art Bible §9.4, ambient k 76).
const BRIM_PERIOD_S := 600.0 / 76.0
const BRIM_SPARKLES := 3
const NEW_DOT_PX := 27.0

var left_handed: bool = false
var buttons: Dictionary = {}
var pill: GlassPanel
var _badge: Control
var _badge_label: Label
var _ring: ColorRect
var _ring_mat: ShaderMaterial
var _new_dot: Control
var _sparkles: Array[TextureRect] = []
var _brim_t: float = 0.0
var _full: bool = false
var _basket_slots: int = 24
var _screen: Vector2 = Vector2(1080, 1920)
var _safe_bottom: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_basket_slots = int(ContentRegistry.content.economy.get("basket_slots", _basket_slots))
	pill = GlassPanel.new()
	pill.name = "Pill"
	add_child(pill)
	for id: StringName in ORDER:
		var b := RoundButton.new()
		b.name = String(id).capitalize()
		var big := BIG.has(id)
		b.plate_px = PLATE_BIG if big else PLATE_SMALL
		b.icon_px = ICON_BIG if big else ICON_SMALL
		b.icon_name = id
		b.set_label(tr(String(LABEL_KEYS[id])))
		PressFeedback.attach(b)
		b.pressed.connect(func() -> void: button_pressed.emit(id))
		add_child(b)
		buttons[id] = b
	_build_basket_extras()
	_cap_label_sizes()
	UiTheme.theme_rebuilt.connect(func(_t: Theme) -> void: _cap_label_sizes())
	Game.basket_changed.connect(func(n: int, _dew: int) -> void: set_basket_count(n))
	if Game.sim != null:
		set_basket_count(Game.sim.state.basket.size())


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and not buttons.is_empty():
		for id: StringName in ORDER:
			(buttons[id] as RoundButton).set_label(tr(String(LABEL_KEYS[id])))


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
	var cy := bottom - PILL_H * 0.5
	for i in ORDER.size():
		var id: StringName = ORDER[ORDER.size() - 1 - i] if left_handed else ORDER[i]
		var b := buttons[id] as RoundButton
		var cx := screen.x * float(2 * i + 1) / float(ORDER.size() * 2)
		b.position = Vector2(cx - HIT * 0.5, cy - HIT * 0.5)
		b.size = Vector2(HIT, HIT)
	_place_basket_extras()


func set_active(id: StringName) -> void:
	for k: StringName in ORDER:
		(buttons[k] as RoundButton).active = k == id


## Onboarding (GDD §3.4): which plates are awake.
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
	set_process(_full)
	if not _full:
		for s: TextureRect in _sparkles:
			s.visible = false


func _process(delta: float) -> void:
	if not _full:
		return
	_brim_t = fposmod(_brim_t + delta, BRIM_PERIOD_S)
	var b := buttons[&"basket"] as RoundButton
	var c := b.position + b.center()
	for i in _sparkles.size():
		var s := _sparkles[i]
		var u := clampf((_brim_t - float(i) * 0.18) / 0.9, 0.0, 1.0)
		s.visible = u > 0.0 and u < 1.0
		var ang := -PI * 0.5 + (float(i) - 1.0) * 0.7
		var r := PLATE_BIG * 0.5 + 6.0 + 18.0 * u
		s.position = c + Vector2(cos(ang), sin(ang)) * r - Vector2(SPARKLE_PX, SPARKLE_PX) * 0.5
		s.modulate.a = sin(u * PI)
		s.scale = Vector2.ONE * (0.6 + 0.4 * sin(u * PI))


func _build_basket_extras() -> void:
	_ring = ColorRect.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.size = Vector2(RING_PX, RING_PX)
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = load(RING_SHADER) as Shader
	_ring_mat.set_shader_parameter(&"u_size", Vector2(RING_PX, RING_PX))
	_ring_mat.set_shader_parameter(&"u_stroke", RING_DP * UiTokens.PX_PER_DP)
	_ring_mat.set_shader_parameter(&"u_color", UiTokens.color(&"gold"))
	_ring_mat.set_shader_parameter(&"u_track", UiTokens.color(&"gold_tint"))
	_ring.material = _ring_mat
	var basket := buttons[&"basket"] as RoundButton
	basket.add_child(_ring)
	basket.move_child(_ring, 0)
	_badge = Control.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.draw.connect(func() -> void:
		_badge.draw_style_box(UiTokens.fill_box(UiTokens.color(&"coral"), _badge.size.y * 0.5, UiTokens.E1),
				Rect2(Vector2.ZERO, _badge.size)))
	basket.add_child(_badge)
	_badge_label = Label.new()
	_badge_label.theme_type_variation = &"CaptionLabel"
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_child(_badge_label)
	_new_dot = Control.new()
	_new_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_new_dot.size = Vector2(NEW_DOT_PX, NEW_DOT_PX)
	_new_dot.visible = false
	_new_dot.draw.connect(func() -> void:
		_new_dot.draw_style_box(UiTokens.fill_box(UiTokens.color(&"coral"), NEW_DOT_PX * 0.5, UiTokens.E1),
				Rect2(Vector2.ZERO, _new_dot.size)))
	(buttons[&"garden"] as RoundButton).add_child(_new_dot)
	for i in BRIM_SPARKLES:
		var s := Icons.rect(&"sparkle", SPARKLE_PX)
		s.pivot_offset = Vector2(SPARKLE_PX, SPARKLE_PX) * 0.5
		s.visible = false
		add_child(s)
		_sparkles.append(s)


func _place_basket_extras() -> void:
	var basket := buttons[&"basket"] as RoundButton
	var c := basket.center()
	var icon_c := c + Vector2(0.0, -_label_h(basket) * 0.5)
	_ring.position = icon_c - Vector2(RING_PX, RING_PX) * 0.5
	var lw := _badge_label.get_combined_minimum_size()
	var bw := maxf(BADGE_MIN, lw.x + BADGE_PAD * 2.0)
	var bh := maxf(BADGE_MIN, lw.y)
	var corner := c + Vector2(PLATE_BIG, -PLATE_BIG) * 0.5 * 0.7071
	_badge.size = Vector2(bw, bh)
	_badge.position = corner - Vector2(bw * 0.5, bh * 0.5)
	_badge_label.size = _badge.size
	_badge.queue_redraw()
	var garden := buttons[&"garden"] as RoundButton
	var gc := garden.center() + Vector2(PLATE_BIG, -PLATE_BIG) * 0.5 * 0.7071
	_new_dot.position = gc - _new_dot.size * 0.5


func _label_h(b: RoundButton) -> float:
	return b.label.get_combined_minimum_size().y + RoundButton.LABEL_GAP if b.label != null else 0.0


## Dock labels cap at 130 % text size; above that the icons carry the meaning (§9.1).
func _cap_label_sizes() -> void:
	var cap := roundi(float(ThemeBuilder.SIZE_CAPTION) * LABEL_SCALE_CAP)
	for id: StringName in ORDER:
		var b := buttons[id] as RoundButton
		if b.label == null:
			continue
		var size_px := b.label.get_theme_font_size(&"font_size")
		if size_px > cap:
			b.label.add_theme_font_size_override(&"font_size", cap)
		else:
			b.label.remove_theme_font_size_override(&"font_size")
		b.set_label(b.label.text)
