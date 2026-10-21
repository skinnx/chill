class_name BasketSheet
extends UiSheet
## The gift basket (GDD §3.2, §5.3, §5.7; Art Bible §9.4-9.5 wireframe): the dew cup widget (the
## acorn cup with its gold level ring, "Dew cup" + amount, "The dew cup is brimming." when full),
## 8 x 3 tiles of 108 px (surface_hi, r-xs; a live gift stamp, or an empty ring + dot) and the
## primary "Collect all". Collecting flies every gift to the dew chip (500 ms `emphasized`, 30 ms
## stagger, capped at 240 ms) while the counter rolls; the tiles fade on `short`.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const TILE := 108.0
const TILE_GAP := 12
const COLUMNS := 8
const STAMP := 84.0
const CUP := 132.0
const CUP_RING_DP := 3.0
const RING_SHADER := "res://shaders/ui/ring_fill.gdshader"
const EMPTY_DOT := 9.0
const EMPTY_RING_DP := 2.0
const COLLECT_H := 144.0
const FLY_PX := 72.0
const CUP_ITEM := &"acorn_cup"

var hud: HudController
var _count: Label
var _cup_amount: Label
var _cup_note: Label
var _cup_ring: ShaderMaterial
var _grid: GridContainer
var _collect: Button
var _hint: Label
var _flying: bool = false


func _init() -> void:
	super._init()
	title_key = "BASKET_TITLE"


func build_body() -> void:
	_count = _count_chip()
	header_extra.add_child(_count.get_parent())
	var v := VBoxContainer.new()
	v.position = Vector2(SIDE, 0.0)
	v.size = Vector2(body.size.x - SIDE * 2.0, body.size.y)
	v.add_theme_constant_override(&"separation", 24)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(v)
	v.add_child(_cup_widget())
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override(&"h_separation", TILE_GAP)
	_grid.add_theme_constant_override(&"v_separation", TILE_GAP)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_grid)
	v.add_child(center)
	_hint = label("", &"CaptionLabel", true)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_hint)
	_collect = pill_button(tr("BASKET_COLLECT_ALL"), true, COLLECT_H)
	_collect.pressed.connect(_on_collect)
	v.add_child(_collect)
	refresh()


func refresh_texts() -> void:
	super.refresh_texts()
	if _collect != null:
		_collect.text = tr("BASKET_COLLECT_ALL")
		refresh()


func refresh() -> void:
	if Game.sim == null or _grid == null or _flying:
		return
	var sim := Game.sim
	var slots := int(ContentRegistry.content.economy.get("basket_slots", 24))
	var basket := sim.state.basket
	_count.text = "%d / %d" % [basket.size(), slots]
	_cup_amount.text = TopBarView.format_dew(floori(sim.cup_value()))
	var brim := sim.cup_brimming()
	_cup_note.text = tr("BASKET_CUP_BRIMMING") if brim else tr("BASKET_CUP_DESC")
	var sat := float(ContentRegistry.content.economy.get("dew_cup_saturation_s", 43200.0))
	var level := clampf((sim.state.t - sim.state.last_collect_t) / maxf(sat, 1.0), 0.0, 1.0)
	_cup_ring.set_shader_parameter(&"u_progress", level)
	for c: Node in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for i in slots:
		_grid.add_child(_tile(basket[i] if i < basket.size() else {}))
	var empty := basket.is_empty() and floori(sim.cup_value()) <= 0
	_collect.disabled = empty
	_collect.theme_type_variation = &"SecondaryButton" if empty else &""
	if empty:
		_hint.text = tr("BASKET_EMPTY")
	elif sim.basket_full():
		_hint.text = tr("BASKET_FULL_NOTE")
	else:
		_hint.text = ""
	_hint.visible = _hint.text != ""


func _count_chip() -> Label:
	var p := PanelContainer.new()
	var box := UiTokens.fill_box(UiTokens.color(&"surface_hi"), 36.0, UiTokens.E1)
	box.content_margin_left = 30
	box.content_margin_right = 30
	p.add_theme_stylebox_override(&"panel", box)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.custom_minimum_size = Vector2(168.0, 72.0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label("", &"StrongLabel")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return l


func _cup_widget() -> Control:
	var c := card(24, ThemeBuilder.R_L, UiTokens.E1)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 30)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(h)
	var well := Control.new()
	well.custom_minimum_size = Vector2(CUP, CUP)
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.draw.connect(func() -> void:
		well.draw_style_box(UiTokens.fill_box(UiTokens.color(&"gold_tint"), CUP * 0.5), Rect2(Vector2.ZERO, well.size)))
	var ring := ColorRect.new()
	ring.size = Vector2(CUP, CUP)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cup_ring = ShaderMaterial.new()
	_cup_ring.shader = load(RING_SHADER) as Shader
	_cup_ring.set_shader_parameter(&"u_size", Vector2(CUP, CUP))
	_cup_ring.set_shader_parameter(&"u_stroke", CUP_RING_DP * UiTokens.PX_PER_DP)
	_cup_ring.set_shader_parameter(&"u_color", UiTokens.color(&"gold"))
	_cup_ring.set_shader_parameter(&"u_track", Color(UiTokens.color(&"gold"), 0.0))
	ring.material = _cup_ring
	well.add_child(ring)
	var prev := ItemPreview.new()
	prev.size = Vector2(CUP, CUP)
	prev.position = Vector2.ZERO
	well.add_child(prev)
	prev.show_item(CUP_ITEM)
	h.add_child(well)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cl := label(tr("BASKET_CUP"), &"StrongLabel")
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(cl)
	var amt := HBoxContainer.new()
	amt.add_theme_constant_override(&"separation", 6)
	amt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Icons.rect(&"dew", 48.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	amt.add_child(ic)
	_cup_amount = label("0", &"PriceLabel")
	amt.add_child(_cup_amount)
	top.add_child(amt)
	v.add_child(top)
	_cup_note = label("", &"SecondaryLabel", true)
	v.add_child(_cup_note)
	return c


func _tile(gift: Dictionary) -> Control:
	var t := Control.new()
	t.custom_minimum_size = Vector2(TILE, TILE)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var filled := not gift.is_empty()
	t.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, t.size)
		if filled:
			t.draw_style_box(UiTokens.fill_box(UiTokens.color(&"gold_tint"), ThemeBuilder.R_XS), r)
		else:
			var box := UiTokens.fill_box(Color(0, 0, 0, 0), ThemeBuilder.R_XS)
			box.border_color = UiTokens.tinted(&"ink", UiTokens.alpha(&"divider"))
			box.set_border_width_all(roundi(EMPTY_RING_DP * UiTokens.PX_PER_DP))
			t.draw_style_box(box, r)
			var dot_c := UiTokens.tinted(&"ink", UiTokens.alpha(&"divider"))
			t.draw_circle(r.get_center(), EMPTY_DOT * 0.5, dot_c, true, -1.0, true))
	if filled:
		var prev := ItemPreview.new()
		prev.size = Vector2(STAMP, STAMP)
		prev.position = Vector2(TILE - STAMP, TILE - STAMP) * 0.5
		t.add_child(prev)
		prev.show_item(StringName(String(gift.get("gift_item", ""))))
		t.set_meta(&"gift", true)
	return t


func _on_collect() -> void:
	if Game.sim == null or _flying:
		return
	var origins: Array[Vector2] = []
	for c: Node in _grid.get_children():
		var t := c as Control
		if t != null and t.has_meta(&"gift"):
			origins.append(t.global_position + t.size * 0.5)
			var prev := t.get_child(0) as ItemPreview
			if prev != null:
				prev.visible = false
	_flying = true
	var target := hud.top_bar.dew_target_point() if hud != null else Vector2(120, 200)
	var layer: Control = hud.overlays if hud != null else self
	var basket := Game.sim.state.basket.duplicate()
	for i in origins.size():
		var gift: StringName = &""
		if i < basket.size():
			gift = StringName(String((basket[i] as Dictionary).get("gift_item", "")))
		_fly(layer, gift, origins[i], target, Motion.stagger_delay(i))
	for c: Node in _grid.get_children():
		Motion.fade_out(c as CanvasItem, &"short")
	Game.collect_all()
	var settle := Motion.duration(&"emphasized") + Motion.stagger_delay(origins.size())
	get_tree().create_timer(settle).timeout.connect(func() -> void:
		_flying = false
		refresh())


func _fly(layer: Control, gift: StringName, from: Vector2, to: Vector2, delay: float) -> void:
	var p := ItemPreview.new()
	p.size = Vector2(FLY_PX, FLY_PX)
	p.position = from - p.size * 0.5
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(p)
	p.show_item(gift if gift != &"" else &"dew_drop")
	var dur := Motion.duration(&"emphasized")
	var t := p.create_tween()
	t.tween_interval(delay)
	if Motion.reduce_motion:
		t.tween_property(p, "modulate:a", 0.0, Motion.duration(&"short"))
	else:
		var mid := from.lerp(to, 0.5) + Vector2(0.0, -180.0)
		t.tween_method(func(u: float) -> void:
			var e := UiTokens.ease(&"emphasized", u)
			var a := from.lerp(mid, e)
			var b := mid.lerp(to, e)
			p.position = a.lerp(b, e) - p.size * 0.5
			p.scale = Vector2.ONE * lerpf(1.0, 0.55, e), 0.0, 1.0, dur)
		t.tween_property(p, "modulate:a", 0.0, Motion.duration(&"micro"))
	t.tween_callback(p.queue_free)
	FrameGovernor.hold_for(delay + dur)
