class_name DockView
extends Control
## The bottom dock (Art Bible §9.4-9.5, GDD §8.1, I2). Round 6 (owner: "the bottom menu is still
## not friendly"): a floating warm-glass pebble holding the three destinations
## [Album] [Garden] [Basket] (left-handed: [Basket] [Garden] [Album]); Settings moved to a gear in
## the top bar. Garden is the centre hero: a larger icon on a raised round plate that pokes out of
## the pebble's top. Icons are plush full-colour stickers (tools/ui/make_icons.py dock_*), labels
## DockLabel (Baloo 2, Caption size).
## Selected tab (its sheet open): a soft bubble in the tab's own tint behind the icon that springs
## between tabs on `move` and pops in on `pop`; the icon pops. Touch-down (same frame): the tab
## squashes toward the bubble's bottom, a press bubble appears and a ripple grows inside it.
## Basket: never a count, never red. What peeks over the rim shows how full it is (empty, a dew
## drop, + a bloom, brimming), with a soft warm glow behind it while there is something to
## collect; brim sparkles when full and the onboarding glint every 6 s. New things (Garden after
## the first collect, Album after a new friend) get a tiny twinkling sparkle, never a dot.
## Onboarding "not yet" tabs stay in full colour: a sleepy closed-eye icon that breathes under a
## bobbing "z z" (static under Reduce Motion); a tap still opens the sheet's friendly empty state.
## Text size: labels take the full size; the pebble widens (up to the screen) and grows taller.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

signal button_pressed(id: StringName)

## Right-handed order, left to right: the frequent Basket sits under the right thumb.
const ORDER: Array[StringName] = [&"album", &"garden", &"basket"]
const HERO := &"garden"
const LABEL_KEYS := {&"garden": "DOCK_GARDEN", &"basket": "DOCK_BASKET", &"album": "DOCK_ALBUM"}
## Bubble tint of each tab (palettes ui_derived).
const BUBBLE_TOKENS := {&"garden": &"bubble_leaf", &"basket": &"bubble_gold", &"album": &"bubble_coral"}
## Ripple colour of each tab (its accent, never the cool primary).
const RIPPLE_TOKENS := {&"garden": &"leaf", &"basket": &"gold_deep", &"album": &"coral"}
## Pebble: 68 dp tall at 100 % text, at least 816 px wide (272 dp), centred, floating BOTTOM_GAP
## above max(safe bottom, BOTTOM_MIN).
const PILL_H := 204.0
const PILL_W_MIN := 816.0
const PILL_SIDE := 24.0
const BOTTOM_MIN := 127.0
const BOTTOM_GAP := 36.0
const PILL_INSET := 12.0
const SIDE_TAB_W := 252.0
const HERO_TAB_W := 288.0
## Icons 32 dp (sides) and 36 dp (hero).
const ICON_PX := 96.0
const HERO_ICON_PX := 108.0
## Space above a side icon inside the tab, the icon-to-label gap and the label's bottom padding.
const ICON_TOP := 12.0
const LABEL_GAP := 2.0
const LABEL_BOTTOM := 8.0
const LABEL_PAD := 14.0
## ... and at large text (>= 150 %), so long labels keep clear of the pebble's round ends.
const LABEL_PAD_LARGE := 36.0
## Hero plate: a raised round plate (Ø 150) whose top pokes HERO_POKE above the pebble.
const HERO_PLATE_PX := 150.0
const HERO_POKE := 27.0
const HERO_RING_DP := 1.5
const HERO_RING_ALPHA := 0.3
## Hit rects grow past the pebble (>= 76 dp tall): up and down by HIT_GROW, the hero to its plate.
const HIT_GROW := 24.0
## Selection bubble around a side icon (icon + pad), radius = half its height.
const BUBBLE_PAD := Vector2(60.0, 30.0)
## Press bubble under a pressed, unselected tab: its tint at this alpha.
const PRESS_BUBBLE_ALPHA := 0.95
## Smallest label size when shrinking to fit (a long translation at large text): 80 % of full,
## never below Caption 30 px.
const LABEL_MIN_PX := 30
const LABEL_SHRINK_FLOOR := 0.8
## Press depth (2 x ui.press_scale's dip = 0.92) with an M3 squash.
const PRESS_DEPTH := 2.0
## Basket glow (palettes basket_glow): a soft warm halo behind the icon while gifts wait; its
## strength grows from GLOW_MIN to 1 with the fill.
const GLOW_PX := 120.0
const GLOW_SPREAD := 30
const GLOW_FILL_ALPHA := 0.32
const GLOW_SHADOW_ALPHA := 0.5
const GLOW_MIN := 0.55
## Basket fill states: count thresholds for dock_basket_1 / _2 / _3.
const FILL_LEVELS: Array[int] = [1, 8, 16]
const SPARKLE_PX := 30.0
const SLEEP_Z_PX := 42.0
## Brim sparkle: 3 sparkles every 600/76 s (Art Bible §9.4, ambient k 76).
const BRIM_PERIOD_S := 600.0 / 76.0
const BRIM_SPARKLES := 3
## Draw order lifts, shared with the top bar so the whole HUD batches by kind: glass at z 0,
## plates / bubbles / glow at z 0 after the glass (one layer), every icon and sprite (one atlas)
## z 2, every label z 3.
const Z_BADGES := 1
const Z_ICONS := 2
const Z_LABELS := 3
## Onboarding (GDD §3.4): "the Basket button glints every 6 s" until the first collect.
const GLINT_PERIOD_S := 6.0

var left_handed: bool = false
var buttons: Dictionary = {}
var pill: GlassPanel
## Full-width strip over the bottom inset (the Android gesture bar / home indicator, Z5): presses
## that start there are taken by the HUD and do nothing (no tab, no world tap, no pan).
var guard: Control
## Selection bubble: centre (screen px), size, pop scale and alpha; all spring.
var cap_x: float = 0.0:
	set(v):
		cap_x = v
		_redraw_plates()
var cap_y: float = 0.0:
	set(v):
		cap_y = v
		_redraw_plates()
var cap_w: float = 0.0:
	set(v):
		cap_w = v
		_redraw_plates()
var cap_h: float = 0.0:
	set(v):
		cap_h = v
		_redraw_plates()
var cap_s: float = 1.0:
	set(v):
		cap_s = v
		_redraw_plates()
var cap_a: float = 0.0:
	set(v):
		cap_a = v
		_redraw_plates()
var _active: StringName = &""
## The bubble's colour blends from the tab it left to the tab it heads for.
var _cap_from: StringName = &""
var _cap_from_x: float = 0.0
var _plates: Control
var _sparkles: Array[TextureRect] = []
var _new_sparkles: Dictionary = {}
var _sleep_z: Dictionary = {}
var _new: Dictionary = {}
var _brim_t: float = 0.0
var _t: float = 0.0
var _full: bool = false
var _glint: bool = false
var _count: int = 0
var _was_pressing: bool = false
var _basket_slots: int = 24
var _screen: Vector2 = Vector2(1080, 1920)
var _safe_bottom: float = 0.0
var _pill_h: float = PILL_H
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
	# The pebble's own glass takes its presses too (between and around the tabs), so a touch on
	# the dock never reaches the world (WorldPan arbitration).
	pill.mouse_filter = Control.MOUSE_FILTER_STOP
	guard = Control.new()
	guard.name = "GestureGuard"
	guard.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(guard)
	# Draw-call budget (Art Bible §4.19): the plates, bubbles and glow are drawn by one layer, the
	# icons and sprites come from one atlas at z 2, the labels draw together at z 3.
	_plates = Control.new()
	_plates.name = "Bubbles"
	_plates.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plates.set_anchors_preset(Control.PRESET_FULL_RECT)
	_plates.draw.connect(_draw_plates)
	add_child(_plates)
	for id: StringName in ORDER:
		var b := RoundButton.new()
		b.name = String(id).capitalize()
		b.draw_plate = false
		b.asleep_dims = false
		b.icon_px = HERO_ICON_PX if id == HERO else ICON_PX
		b.label_gap = LABEL_GAP
		b.set_meta(&"ripple_owner_shape", true)
		b.set_meta(PressFeedback.META_RIPPLE_ON_DARK, false)
		b.set_meta(PressFeedback.META_RIPPLE_COLOR, UiTokens.color(StringName(RIPPLE_TOKENS[id])))
		b.icon_z = Z_ICONS
		b.set_label(tr(String(LABEL_KEYS[id])))
		b.label.theme_type_variation = &"DockLabel"
		b.label.z_index = Z_LABELS
		b.label.clip_text = false
		b.tooltip_text = tr(String(LABEL_KEYS[id]))
		PressFeedback.attach(b, PressFeedback.CUE_TOUCH, PRESS_DEPTH, true)
		b.pressed.connect(func() -> void: button_pressed.emit(id))
		b.appearance_changed.connect(_redraw_plates)
		add_child(b)
		buttons[id] = b
		_sleep_z[id] = _sprite(&"sleep_z", SLEEP_Z_PX)
		_new_sparkles[id] = _sprite(&"sparkle", SPARKLE_PX)
	for i in BRIM_SPARKLES:
		_sparkles.append(_sprite(&"sparkle", SPARKLE_PX))
	_refresh_icons()
	_fit_labels()
	UiTheme.theme_rebuilt.connect(func(_t2: Theme) -> void: _fit_labels.call_deferred())
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


func _sprite(icon: StringName, px: float) -> TextureRect:
	var s := Icons.rect(icon, px)
	s.texture = Icons.hud_atlas().get(Icons.atlas_key(icon, px)) as Texture2D
	s.z_index = Z_ICONS
	s.pivot_offset = Vector2(px, px) * 0.5
	s.visible = false
	add_child(s)
	return s


## The icon a tab shows now: sleepy while asleep, the basket by how full it is.
func icon_for(id: StringName) -> StringName:
	var b := buttons.get(id) as RoundButton
	var asleep := b != null and b.asleep and not b.active
	if id == &"basket":
		if asleep and _count == 0:
			return &"dock_basket_sleep"
		var lv := 0
		for i in FILL_LEVELS.size():
			if _count >= FILL_LEVELS[i]:
				lv = i + 1
		return &"dock_basket" if lv == 0 else StringName("dock_basket_%d" % lv)
	if id == &"garden" and asleep:
		return &"dock_garden_sleep"
	return StringName("dock_" + String(id))


func _refresh_icons() -> void:
	var atlas := Icons.hud_atlas()
	for id: StringName in ORDER:
		var b := buttons[id] as RoundButton
		var tex := atlas.get(Icons.atlas_key(icon_for(id), b.icon_px, false, _night_icons)) as Texture2D
		var icons: Array[Texture2D] = [tex, tex]
		b.icon_textures = icons
		b.icon_name = id
	for i in _sparkles.size():
		_sparkles[i].texture = atlas.get(Icons.atlas_key(&"sparkle", SPARKLE_PX, false, _night_icons)) as Texture2D
	for id: StringName in ORDER:
		(_new_sparkles[id] as TextureRect).texture = _sparkles[0].texture
		(_sleep_z[id] as TextureRect).texture = atlas.get(Icons.atlas_key(&"sleep_z", SLEEP_Z_PX, false,
				_night_icons)) as Texture2D
	_place_extras()


## Night chrome (palettes ui_alpha.night_chrome; the pebble glass follows GlassPanel.night_k):
## labels lerp to night_ink, the bubbles and the hero plate to night_capsule, ripples turn light
## (white, capped) and the icons take their night variant (cream sticker edge) at the midpoint.
func set_night(k: float) -> void:
	_night_k = clampf(k, 0.0, 1.0)
	var icons_night := _night_k >= 0.5
	var swap := icons_night != _night_icons
	_night_icons = icons_night
	for id: StringName in ORDER:
		var b := buttons[id] as RoundButton
		b.night_k = _night_k
		b.set_meta(PressFeedback.META_RIPPLE_ON_DARK, icons_night)
	if swap:
		_refresh_icons()
	_redraw_plates()


func bubble_color(id: StringName) -> Color:
	var day := UiTokens.color(StringName(BUBBLE_TOKENS.get(id, &"primary_tint")))
	return day.lerp(UiTokens.color(&"night_capsule"), _night_k)


func button(id: StringName) -> RoundButton:
	return buttons.get(id) as RoundButton


## The pebble's rect in screen px.
func pill_rect() -> Rect2:
	return Rect2(pill.position, pill.size)


## The dock's top edge including the hero plate (sheets float 24 px above it).
func top() -> float:
	return pill.position.y - HERO_POKE


## Every control that takes input (ambient watch turns them off).
func input_controls() -> Array[Control]:
	var out: Array[Control] = [pill]
	for b: Variant in buttons.values():
		out.append(b as Control)
	return out


func layout(screen: Vector2, safe_bottom: float) -> void:
	_screen = screen
	_safe_bottom = safe_bottom
	_fit_labels()
	var lh := _label_h()
	_pill_h = maxf(PILL_H, PILL_INSET * 2.0 + ICON_TOP + ICON_PX + LABEL_GAP + lh + LABEL_BOTTOM)
	var widths := _tab_widths()
	var pill_w := PILL_INSET * 2.0
	for w: float in widths:
		pill_w += w
	var bottom := screen.y - maxf(safe_bottom, BOTTOM_MIN) - BOTTOM_GAP
	pill.position = Vector2(roundf((screen.x - pill_w) * 0.5), bottom - _pill_h)
	pill.size = Vector2(pill_w, _pill_h)
	var x := pill.position.x
	var p := pill.position.y
	var label_top := p + _pill_h - PILL_INSET - LABEL_BOTTOM - lh
	# The tabs tile the whole pebble edge to edge (the outer two take its insets and round ends)
	# and reach down to the gesture guard: no dead gap anywhere on the dock (ARCHITECTURE §3.5).
	var guard_h := maxf(safe_bottom, BOTTOM_MIN)
	guard.position = Vector2(0.0, screen.y - guard_h)
	guard.size = Vector2(screen.x, guard_h)
	for i in ORDER.size():
		var id := _id_at(i)
		var b := buttons[id] as RoundButton
		var w := widths[i] + (PILL_INSET if i == 0 or i == ORDER.size() - 1 else 0.0)
		var inner := PILL_INSET if i == 0 else 0.0
		var hero := id == HERO
		var hit_top := p - (HERO_POKE + HIT_GROW * 0.5 if hero else HIT_GROW)
		var hit_bottom := maxf(p + _pill_h + HIT_GROW, guard.position.y)
		b.position = Vector2(x, hit_top)
		b.size = Vector2(w, hit_bottom - hit_top)
		var icon_px := b.icon_px
		var icon_c_y := p - HERO_POKE + HERO_PLATE_PX * 0.5 if hero else label_top - LABEL_GAP - icon_px * 0.5
		var icon_top := icon_c_y - icon_px * 0.5
		b.label_gap = label_top - (icon_top + icon_px)
		var stack_h := label_top + lh - icon_top
		b.inline = false
		var vis_w := widths[i]
		b.label_w = vis_w - label_pad() * 2.0
		b.plate_px = vis_w
		b.plate_center = Vector2(inner + vis_w * 0.5, icon_top - hit_top + stack_h * 0.5)
		var br := _bubble_local(b)
		b.set_meta(PressFeedback.META_RIPPLE_RECT, br)
		b.set_meta(PressFeedback.META_RIPPLE_RADIUS, br.size.y * 0.5)
		b.pivot_offset = Vector2(br.get_center().x, br.end.y)
		x += w
	if _active != &"":
		Motion.stop_springs(self)
		_snap_cap(_active)
	_redraw_plates()
	_place_extras()


func _tab_widths() -> Array[float]:
	var side := SIDE_TAB_W
	var hero := HERO_TAB_W
	for id: StringName in ORDER:
		var lw := _label_w(id) + label_pad() * 2.0
		if id == HERO:
			hero = maxf(hero, lw)
		else:
			side = maxf(side, lw)
	var room := _screen.x - PILL_SIDE * 2.0 - PILL_INSET * 2.0
	if side * 2.0 + hero > room:
		side = floorf(room / 3.0)
		hero = room - side * 2.0
	var out: Array[float] = []
	for i in ORDER.size():
		out.append(hero if _id_at(i) == HERO else side)
	return out


func _label_w(id: StringName) -> float:
	var l := (buttons[id] as RoundButton).label
	var font := l.get_theme_font(&"font")
	if font == null:
		return 0.0
	return font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size(&"font_size")).x


func _label_h() -> float:
	var h := 0.0
	for id: StringName in ORDER:
		h = maxf(h, (buttons[id] as RoundButton).label.get_combined_minimum_size().y)
	return h


## The bubble behind a tab's icon, in the tab's local px: the hero plate's circle for Garden.
func _bubble_local(b: RoundButton) -> Rect2:
	var c := b.icon_center()
	var sz := Vector2(HERO_PLATE_PX, HERO_PLATE_PX) if buttons.get(HERO) == b \
			else Vector2(b.icon_px, b.icon_px) + BUBBLE_PAD
	return Rect2(c - sz * 0.5, sz)


## A tab's label side padding at the current Text size.
static func label_pad() -> float:
	return LABEL_PAD_LARGE if text_scale() >= 1.5 else LABEL_PAD


## The Text size setting as a factor (1.0 .. 2.0).
static func text_scale() -> float:
	return float(Settings.get_int(Settings.TEXT_SCALE)) / 100.0


func _snap_cap(id: StringName) -> void:
	var b := buttons.get(id) as RoundButton
	if b == null:
		return
	var r := _bubble_local(b)
	cap_x = b.position.x + r.get_center().x
	cap_y = b.position.y + r.get_center().y
	cap_w = r.size.x
	cap_h = r.size.y
	_cap_from = id


## The open sheet's tab (&"" or a sheet without a tab, e.g. Settings = none): the bubble springs
## there (or pops in at it).
func set_active(id: StringName) -> void:
	if not buttons.has(id):
		id = &""
	for k: StringName in ORDER:
		(buttons[k] as RoundButton).active = k == id
	var was := _active
	_active = id
	_refresh_icons()
	if id == &"":
		Motion.spring_to(self, "cap_a", 0.0, &"press")
		return
	var b := buttons[id] as RoundButton
	var r := _bubble_local(b)
	var c := b.position + r.get_center()
	var tok := UiTokens.ui_block("dock")
	if was == &"" or cap_a < 0.05 or Motion.reduce_motion:
		Motion.stop_springs(self)
		_snap_cap(id)
		cap_a = 1.0 if Motion.reduce_motion else 0.0
		cap_s = 1.0 if Motion.reduce_motion else float(tok.get("select_pop_from", 0.82))
		Motion.spring_to(self, "cap_a", 1.0, &"press")
		Motion.spring_to(self, "cap_s", 1.0, &"pop")
	else:
		_cap_from = was
		_cap_from_x = cap_x
		Motion.spring_to(self, "cap_x", c.x, &"move")
		Motion.spring_to(self, "cap_y", c.y, &"move")
		Motion.spring_to(self, "cap_w", r.size.x, &"move")
		Motion.spring_to(self, "cap_h", r.size.y, &"move")
		Motion.spring_to(self, "cap_a", 1.0, &"press")
	if not Motion.reduce_motion:
		var icon := b.icon_node()
		icon.pivot_offset = icon.size * 0.5
		icon.scale = Vector2.ONE * float(tok.get("icon_pop", 1.1))
		Motion.spring_to(icon, "scale", Vector2.ONE, &"pop")
	if id == &"garden" or id == &"album":
		set_new(id, false)
	FrameGovernor.hold_for(Motion.duration(&"standard"))


## QA: snaps the bubble (no spring) for deterministic stills.
func snap_active() -> void:
	Motion.stop_springs(self)
	if _active != &"":
		_snap_cap(_active)
		cap_a = 1.0
		cap_s = 1.0
	else:
		cap_a = 0.0


## Onboarding (GDD §3.4): which tabs are awake. Asleep tabs keep their colour (round 6).
func set_asleep(id: StringName, asleep: bool) -> void:
	var b := buttons.get(id) as RoundButton
	if b != null and b.asleep != asleep:
		b.asleep = asleep
		_refresh_icons()
		if not asleep:
			b.icon_node().scale = Vector2.ONE
			b.scale = Vector2.ONE * float(UiTokens.ui_block("counter_tick").get("scale", 1.08))
			Motion.spring_to(b, "scale", Vector2.ONE, &"pop")


func is_asleep(id: StringName) -> bool:
	var b := buttons.get(id) as RoundButton
	return b != null and b.asleep


## A tiny twinkling sparkle on a tab with something new (never a dot badge).
func set_new(id: StringName, on: bool) -> void:
	if not buttons.has(id):
		return
	_new[id] = on
	_place_extras()


func has_new(id: StringName) -> bool:
	return bool(_new.get(id, false))


## Compatibility: Garden's "new" mark (GDD §3.4 "the Garden button wakes with a small new mark").
func set_new_dot(on: bool) -> void:
	set_new(&"garden", on)


func set_basket_count(n: int) -> void:
	var changed := n != _count
	_count = n
	_full = n >= _basket_slots
	if changed and not buttons.is_empty():
		_refresh_icons()
	_redraw_plates()
	_sync_sparkles()


func basket_count() -> int:
	return _count


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


func _redraw_plates() -> void:
	if _plates != null:
		_plates.queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	# The bubble layer and the extras follow each tab's press scale (PressFeedback).
	var pressing := false
	for b: Variant in buttons.values():
		if not (b as RoundButton).scale.is_equal_approx(Vector2.ONE):
			pressing = true
	if pressing or _was_pressing:
		_redraw_plates()
		_place_extras()
	_was_pressing = pressing
	_animate_ambient()
	if not (_full or _glint):
		return
	_brim_t = fposmod(_brim_t + delta, GLINT_PERIOD_S if _glint and not _full else BRIM_PERIOD_S)
	var basket := buttons[&"basket"] as RoundButton
	var c := _screen_point(basket, basket.icon_center())
	for i in _sparkles.size():
		var s := _sparkles[i]
		var u := clampf((_brim_t - float(i) * 0.18) / 0.9, 0.0, 1.0)
		s.visible = u > 0.0 and u < 1.0
		var ang := -PI * 0.5 + (float(i) - 1.0) * 0.7
		var r := basket.icon_px * 0.5 + 6.0 + 18.0 * u
		s.position = c + Vector2(cos(ang), sin(ang)) * r - Vector2(SPARKLE_PX, SPARKLE_PX) * 0.5
		s.modulate.a = sin(u * PI)
		s.scale = Vector2.ONE * (0.6 + 0.4 * sin(u * PI))


## Sleepy breathing, the bobbing "z z" and the new-thing twinkle (static under Reduce Motion).
func _animate_ambient() -> void:
	var tok := UiTokens.ui_block("dock")
	var still := Motion.reduce_motion
	for id: StringName in ORDER:
		var b := buttons[id] as RoundButton
		var z := _sleep_z[id] as TextureRect
		var asleep := b.asleep and not b.active
		var icon := b.icon_node()
		if asleep and not still:
			var period := 600.0 / float(tok.get("asleep_breathe_k", 110))
			var k := 1.0 + float(tok.get("asleep_breathe_amp", 0.03)) * sin(TAU * _t / period)
			icon.pivot_offset = Vector2(icon.size.x * 0.5, icon.size.y)
			icon.scale = Vector2(2.0 - k, k)
		elif asleep:
			icon.scale = Vector2.ONE
		if z.visible and not still:
			var zp := 600.0 / float(tok.get("zz_k", 124))
			var bob := float(tok.get("zz_bob_dp", 3)) * UiTokens.PX_PER_DP
			z.position.y = float(z.get_meta(&"base_y", z.position.y)) - bob * sin(TAU * _t / zp)
			z.modulate.a = 0.75 + 0.25 * sin(TAU * _t / zp)
		var sp := _new_sparkles[id] as TextureRect
		if sp.visible and not still:
			var tp := 600.0 / float(tok.get("new_twinkle_k", 76))
			var u := 0.5 + 0.5 * sin(TAU * _t / tp)
			sp.scale = Vector2.ONE * (0.75 + 0.3 * u)
			sp.rotation = 0.25 * u


## A point in a tab's local px on screen, with its press transform.
func _screen_point(b: RoundButton, local: Vector2) -> Vector2:
	var piv := b.position + b.pivot_offset
	return piv + (b.position + local - piv) * b.scale


func _screen_rect(b: RoundButton, local: Rect2) -> Rect2:
	var p0 := _screen_point(b, local.position)
	return Rect2(p0, local.size * b.scale)


func _draw_plates() -> void:
	if buttons.is_empty():
		return
	var night_plate := UiTokens.color(&"night_capsule")
	# the basket's warm glow while gifts wait (grows with the fill)
	if _count > 0:
		var bk := buttons[&"basket"] as RoundButton
		var c := _screen_point(bk, bk.icon_center())
		var fill_k := lerpf(GLOW_MIN, 1.0, clampf(float(_count) / float(_basket_slots), 0.0, 1.0))
		var glow := UiTokens.color(&"basket_glow")
		var g := UiTokens.fill_box(Color(glow, GLOW_FILL_ALPHA * fill_k * (1.0 - 0.5 * _night_k)), GLOW_PX * 0.5)
		g.shadow_color = Color(glow, GLOW_SHADOW_ALPHA * fill_k * (1.0 - 0.4 * _night_k))
		g.shadow_size = GLOW_SPREAD
		g.anti_aliasing = true
		var gs := GLOW_PX * bk.scale.x
		_plates.draw_style_box(g, Rect2(c - Vector2(gs, gs) * 0.5, Vector2(gs, gs)))
	# the hero plate: raised, always there
	var hero := buttons[HERO] as RoundButton
	var hr := _screen_rect(hero, _bubble_local(hero))
	var plate := UiTokens.color(&"surface_hi").lerp(night_plate, _night_k)
	var hb := UiTokens.fill_box(plate, hr.size.y * 0.5, UiTokens.E1)
	hb.shadow_color = Color(UiTokens.color(&"hud_shadow"), 0.14)
	hb.shadow_size = 18
	hb.shadow_offset = Vector2(0, 6)
	var ring := UiTokens.color(&"leaf").lerp(UiTokens.color(&"night_glass_rim"), _night_k)
	ring.a = HERO_RING_ALPHA
	hb.border_color = ring
	hb.set_border_width_all(roundi(HERO_RING_DP * UiTokens.PX_PER_DP))
	hb.anti_aliasing = true
	hb.corner_detail = 32
	_plates.draw_style_box(hb, hr)
	# press bubbles under pressed, unselected tabs
	for id: StringName in ORDER:
		var b := buttons.get(id) as RoundButton
		if b == null or not b.visible or b.active or not b.looks_pressed():
			continue
		var rect := _screen_rect(b, _bubble_local(b))
		var pc := bubble_color(id)
		pc.a = PRESS_BUBBLE_ALPHA
		var pb := UiTokens.fill_box(pc, rect.size.y * 0.5)
		var edge := UiTokens.color(StringName(RIPPLE_TOKENS[id])).lerp(UiTokens.color(&"night_glass_rim"), _night_k)
		edge.a = 0.35
		pb.border_color = edge
		pb.set_border_width_all(roundi(UiTokens.PX_PER_DP))
		pb.anti_aliasing = true
		pb.corner_detail = 32
		_plates.draw_style_box(pb, rect)
	if cap_a <= 0.01 or _active == &"":
		return
	var ab := buttons.get(_active) as RoundButton
	var sz := Vector2(cap_w, cap_h) * cap_s * ab.scale
	var centre := Vector2(cap_x, cap_y)
	if not ab.scale.is_equal_approx(Vector2.ONE):
		centre = _screen_point(ab, _bubble_local(ab).get_center())
	var rect2 := Rect2(centre - sz * 0.5, sz)
	var fill := bubble_color(_active)
	if _cap_from != _active and buttons.has(_cap_from):
		var tx := ab.position.x + _bubble_local(ab).get_center().x
		var span := absf(tx - _cap_from_x)
		var u := 1.0 if span < 1.0 else clampf(1.0 - absf(tx - cap_x) / span, 0.0, 1.0)
		fill = bubble_color(_cap_from).lerp(fill, u)
	fill.a = clampf(cap_a, 0.0, 1.0)
	var box := UiTokens.fill_box(fill, rect2.size.y * 0.5)
	var line := UiTokens.color(&"surface_hi").lerp(UiTokens.color(&"night_glass_rim"), _night_k)
	line.a = 0.9 * clampf(cap_a, 0.0, 1.0) * (1.0 - 0.5 * _night_k)
	box.border_color = line
	box.set_border_width_all(roundi(UiTokens.PX_PER_DP))
	box.anti_aliasing = true
	box.corner_detail = 32
	_plates.draw_style_box(box, rect2)


## Sleepy "z z" and new-thing sparkles sit at each icon's top-right shoulder.
func _place_extras() -> void:
	for id: StringName in ORDER:
		var b := buttons.get(id) as RoundButton
		if b == null:
			continue
		var ic := _screen_point(b, b.icon_center())
		var half := b.icon_px * 0.5
		var z := _sleep_z[id] as TextureRect
		z.visible = b.asleep and not b.active
		var zp := ic + Vector2(half * 0.62, -half * 1.08)
		z.position = zp
		z.set_meta(&"base_y", zp.y)
		var sp := _new_sparkles[id] as TextureRect
		sp.visible = has_new(id) and not b.asleep
		sp.position = ic + Vector2(half * 0.72, -half * 0.95) - Vector2(SPARKLE_PX, SPARKLE_PX) * 0.5


## Labels take the Text size setting in full; a long translation shrinks to fit its tab (to 80 %,
## never below Caption 30 px) once the pebble has reached the screen's width.
func _fit_labels() -> void:
	if buttons.is_empty():
		return
	var room := (_screen.x - PILL_SIDE * 2.0 - PILL_INSET * 2.0) / 3.0 - label_pad() * 2.0
	for id: StringName in ORDER:
		var b := buttons[id] as RoundButton
		if b.label == null:
			continue
		b.label.remove_theme_font_size_override(&"font_size")
		var full := b.label.get_theme_font_size(&"font_size")
		var fs := full
		var font := b.label.get_theme_font(&"font")
		var floor_px := maxi(LABEL_MIN_PX, roundi(float(full) * LABEL_SHRINK_FLOOR))
		while font != null and fs > floor_px and \
				font.get_string_size(b.label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
			fs -= 1
		b.label.add_theme_font_size_override(&"font_size", fs)
		b.set_label(b.label.text)
	_place_extras()
