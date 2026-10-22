class_name GardenSheet
extends UiSheet
## The Garden shop (GDD §4.2-4.4, §8.1; Art Bible §9.4-9.5 wireframe): tabs Flowers | Décor (the
## Décor tab ends with the Leaf boat row), one surface_hi row card per item with a live mini-render
## well (leaf_tint), name, "{owned} of {max}", the price chip in dew, dew-yield drops (flowers),
## "Blooms in about …", "Loved by …" and the Plant / Place button. Affordability is shown kindly:
## a secondary "A little more dew" button and an ink_2 price; a press gives the soft S11 tok and a
## ±2 dp nudge (never red, never a shake). Buying closes the sheet so the planting / placing plays
## in the world; a flower's first copy enters choose-a-bed mode (GDD §2.4).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const WELL := 252.0
const WELL_RADIUS := 48.0
const DROP_PX := 33.0
const PRICE_ICON := 48.0
const CHIP_PAD := 18
## Large text (Art Bible §9.1: cards grow and reflow at >= 150 %): the well stacks on top.
const STACK_AT_TEXT := 150
const WELL_BANNER_H := 216.0
const DONE_CHIP_H := 96.0
const DONE_ICON := 36.0
const CUE_NOT_YET := &"S11"
const LEAF_BOAT := &"leaf_boat"
## Number of yield drops for the flowers' dew_per_hour terciles (Art Bible §9.4: 1-3 drops).
const MAX_DROPS := 3
const EMPTY_DROP_ALPHA := 0.25

var hud: HudController
var _tabs: Segmented
var _list: VBoxContainer
var _scroll: ScrollContainer
var _tab: int = 0
var _yield_cuts: Vector2 = Vector2(0.6, 1.2)


func _init() -> void:
	super._init()
	title_key = "GARDEN_TITLE"


func build_body() -> void:
	_tabs = Segmented.new()
	_tabs.position = Vector2(SIDE, 0.0)
	_tabs.size = Vector2(body.size.x - SIDE * 2.0, Segmented.HEIGHT)
	body.add_child(_tabs)
	_tabs.setup(PackedStringArray([tr("GARDEN_TAB_FLOWERS"), tr("GARDEN_TAB_DECOR")]), _tab)
	_tabs.selected.connect(func(i: int) -> void: select_tab(i))
	_list = make_scroll(Segmented.HEIGHT + 24.0)
	keep_scroll_below(_tabs)
	_scroll = _list.get_parent().get_parent() as ScrollContainer
	_compute_yield_cuts()
	_fill()


func refresh_texts() -> void:
	super.refresh_texts()
	if _tabs != null:
		_tabs.set_texts(PackedStringArray([tr("GARDEN_TAB_FLOWERS"), tr("GARDEN_TAB_DECOR")]))
		_fill()


func refresh() -> void:
	if _list != null:
		var keep := _scroll.scroll_vertical
		_fill()
		_scroll.set_deferred(&"scroll_vertical", keep)


## The selected tab (a night-scheme rebuild keeps it).
func current_tab() -> int:
	return _tab


func select_tab(i: int, animate: bool = true) -> void:
	_tab = clampi(i, 0, 1)
	_tabs.select(_tab, animate)
	_fill()
	_scroll.scroll_vertical = 0
	if animate:
		_list.modulate.a = 0.0
		Motion.tween(_list, "modulate:a", 1.0, &"short")


func _fill() -> void:
	for c: Node in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if Game.sim == null:
		return
	var content := ContentRegistry.content
	var rows: Array[Dictionary] = []
	rows.assign(content.flowers.duplicate() if _tab == 0 else content.decor.duplicate())
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["garden_order"]) < int(b["garden_order"]))
	for d: Dictionary in rows:
		_list.add_child(_item_card(StringName(String(d["id"])), d, _tab == 0))
	if _tab == 1:
		_list.add_child(_boat_card())


# ------------------------------------------------------------------ cards

func _item_card(id: StringName, d: Dictionary, flower: bool) -> Control:
	var sim := Game.sim
	var owned := sim.owned_count(id)
	var max_n := ContentRegistry.content.max_copies(id)
	var maxed := sim.is_maxed(id)
	var price := sim.price_of(id)
	var affordable := price <= sim.state.dew
	var shell := _card_frame(id)
	var info: VBoxContainer = shell[1]
	var row1 := HBoxContainer.new()
	row1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_l := label(tr(String(d.get("name_key", ""))), &"StrongLabel")
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row1.add_child(name_l)
	row1.add_child(label(I18n.fmt(&"GARDEN_OWNED", {"owned": owned, "max": max_n}), &"SecondaryLabel"))
	info.add_child(row1)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override(&"separation", 18)
	row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip := _price_chip(price, affordable or maxed)
	row2.add_child(chip)
	chip.visible = not maxed
	if flower:
		row2.add_child(_drops(float(d.get("dew_per_hour", 0.0))))
	info.add_child(row2)
	if flower and not maxed:
		info.add_child(label(I18n.fmt(&"GARDEN_BLOOMS_IN", {"time": I18n.duration_text(float(d.get("bloom_at_s", 0.0)))}),
				&"SecondaryLabel", true))
	var loved := _loved_line(id)
	if loved != "":
		info.add_child(label(loved, &"SecondaryLabel", true))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(spacer)
	var text := tr("GARDEN_PLANT") if flower else tr("GARDEN_PLACE")
	if maxed:
		text = tr("GARDEN_ALL_PLANTED") if flower else tr("GARDEN_ALL_PLACED")
	elif not affordable:
		text = tr("GARDEN_MORE_DEW")
	if maxed:
		# Done is a quiet state, not a dead button (round-2 QA: a full-width grey "All planted").
		info.add_child(_done_chip(text))
		return shell[0]
	var room := not flower or not GardenRules.beds_with_room(ContentRegistry.content, sim.state.stems).is_empty()
	var b := pill_button(text, affordable and room)
	# hugs its label, aligned with the text column (and the "All planted" chip)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(_on_buy.bind(id, flower, b, chip))
	info.add_child(b)
	return shell[0]


func _boat_card() -> Control:
	var sim := Game.sim
	var price := int(ContentRegistry.content.economy.get("leaf_boat_cost", 1))
	var affordable := price <= sim.state.dew
	var shell := _card_frame(LEAF_BOAT)
	var info: VBoxContainer = shell[1]
	info.add_child(label(tr("GARDEN_LEAF_BOAT"), &"StrongLabel"))
	var chip := _price_chip(price, affordable)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chip)
	info.add_child(row)
	info.add_child(label(tr("GARDEN_LEAF_BOAT_DESC"), &"SecondaryLabel", true))
	var b := pill_button(tr("GARDEN_FLOAT") if affordable else tr("GARDEN_MORE_DEW"), affordable)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(_on_boat.bind(b, chip))
	info.add_child(b)
	return shell[0]


## [card, info VBox]: a surface_hi row card with the live-render well on the left; at large
## text (>= 150 %) the well becomes a banner on top so the text keeps the full card width.
func _card_frame(item: StringName) -> Array:
	var c := card(24, ThemeBuilder.R_L, UiTokens.E1)
	var stacked := Settings.get_int(Settings.TEXT_SCALE) >= STACK_AT_TEXT
	var h: BoxContainer = VBoxContainer.new() if stacked else HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 24 if stacked else 30)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(h)
	# the live-lit mini-render, baked once per light (BakedWell: every well of the list in one batch)
	var key := "item|%s|%s" % [item, light_key()]
	var well := BakedWell.create(key, Vector2(0.0, WELL_BANNER_H) if stacked else Vector2(WELL, WELL), WELL_RADIUS,
			func(_sz: Vector2) -> Control:
				var prev := ItemPreview.new()
				var w := LiveWell.wrap(prev, Vector2.ZERO, 0.0)
				prev.show_item(item)
				return w)
	well.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(well)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override(&"separation", 9)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(info)
	return [c, info]


## The light a live-lit preview was baked in (phase, weather, lantern level): wells re-bake when it
## changes.
static func light_key() -> String:
	return "%s|%s|%d|%s" % [TimeOfDay.phase, TimeOfDay.weather,
			roundi(float(TimeOfDay.scalars.get("lights", 0.0)) * 4.0), "n" if UiTokens.night_scheme else "d"]


func _price_chip(price: int, affordable: bool) -> Control:
	var p := chip(&"gold_tint", 36.0, Vector4(CHIP_PAD, 0, CHIP_PAD + 6, 0))
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var ic := Icons.rect(&"dew", PRICE_ICON)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := label(TopBarView.format_dew(price), &"PriceLabel")
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if not affordable:
		l.add_theme_color_override(&"font_color", UiTokens.sc(&"ink_2"))
	h.add_child(l)
	return p


## "All planted ✓": a leaf_tint pill with a check (leaf ink on leaf_tint, 5.3:1).
func _done_chip(text: String) -> Control:
	var p := chip(&"leaf_tint", UiSurface.PILL, Vector4(30, 0, 36, 0))
	p.custom_minimum_size = Vector2(0.0, DONE_CHIP_H)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.size_flags_vertical = Control.SIZE_SHRINK_END
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var ic := Icons.rect(&"check", DONE_ICON)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := label(text, &"StrongLabel")
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override(&"font_color", UiTokens.sc(&"leaf"))
	h.add_child(l)
	return p


func _drops(dew_per_hour: float) -> Control:
	var n := 1
	if dew_per_hour > _yield_cuts.y:
		n = 3
	elif dew_per_hour > _yield_cuts.x:
		n = 2
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 0)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.tooltip_text = tr("GARDEN_DEW_YIELD")
	for i in MAX_DROPS:
		var r := Icons.rect(&"dew", DROP_PX)
		r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UiBatch.set_alpha(r, 1.0 if i < n else EMPTY_DROP_ALPHA)
		h.add_child(r)
	return h


func _compute_yield_cuts() -> void:
	var v: Array[float] = []
	for f: Dictionary in ContentRegistry.content.flowers:
		v.append(float(f.get("dew_per_hour", 0.0)))
	v.sort()
	if v.size() >= 3:
		_yield_cuts = Vector2(v[v.size() / 3], v[(v.size() * 2) / 3])


## "Loved by {names}" for met friends who like or need this item; a kind hint if only friends not
## met yet do (GDD §8.1); "" if nobody.
func _loved_line(item: StringName) -> String:
	var met: PackedStringArray = []
	var unmet := false
	for s: Dictionary in ContentRegistry.content.species:
		var likes := false
		for l: Variant in s.get("likes_items", []):
			if l is Dictionary and String((l as Dictionary).get("item", "")) == String(item):
				likes = true
		for r: Variant in s.get("requires", []):
			var rid: String = String((r as Dictionary).get("item", "")) if r is Dictionary else str(r)
			if rid == String(item):
				likes = true
		if not likes:
			continue
		var sp := StringName(String(s["id"]))
		if Game.sim.is_met(sp):
			met.append(Game.display_name(sp))
		else:
			unmet = true
	if not met.is_empty():
		return I18n.fmt(&"GARDEN_LOVED_BY", {"names": ", ".join(met)})
	return tr("GARDEN_LOVED_BY_SOMEONE") if unmet else ""


# ------------------------------------------------------------------ actions

func _on_buy(id: StringName, flower: bool, b: Button, chip: Control) -> void:
	var sim := Game.sim
	if not sim.can_buy(id):
		_not_yet(b, chip)
		return
	if flower and sim.needs_bed_choice(id) and hud != null:
		hud.begin_choose_bed(id)
		return
	close_requested.emit()
	if flower:
		Game.plant(id)
	else:
		Game.place(id)


func _on_boat(b: Button, chip: Control) -> void:
	var price := int(ContentRegistry.content.economy.get("leaf_boat_cost", 1))
	if price > Game.sim.state.dew:
		_not_yet(b, chip)
		return
	close_requested.emit()
	Game.float_boat()


func _not_yet(b: Button, chip: Control) -> void:
	AudioDirector.play_cue(CUE_NOT_YET)
	PressFeedback.nudge(b)
	chip.pivot_offset = chip.size * 0.5
	chip.scale = Vector2.ONE * float(UiTokens.ui_block("counter_tick").get("scale", 1.08))
	Motion.spring_to(chip, "scale", Vector2.ONE, &"pop")
