class_name AlbumSheet
extends UiSheet
## The Album (GDD §7.1-7.4; Art Bible §9.4-9.5 wireframe): a "{met} / {total}" chip by the title
## and three tabs. Friends: a 3-column grid of 288 x 372 surface_hi cards with a live portrait
## (the real rig at the current palette), the name and five hearts; friends not met yet show a
## soft silhouette, "Not met yet" and their hint (never a lock). Tapping a friend pushes its
## detail card (portrait, name with a rename pencil, Pet when visiting, favourite spot, hearts,
## first met, likes). Photos: live polaroids of the poses taken. Postcards: newest first, an
## unread dot, tap to read. Names are editable (12 characters, filtered to the fonts' coverage).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const CARD_W := 288.0
const CARD_PAD := 18
const WELL_H := 216.0
const HEART_PX := 36.0
const HEARTS := 5
const COLUMNS := 3
const COLUMNS_LARGE_TEXT := 2
const LARGE_TEXT := 150
const GAP := 24
const DETAIL_WELL := 480.0
const POLAROID_H := 336.0
const MAX_PHOTOS := 12
const POSTCARD_ROW_H := 168.0
const DOT_PX := 21.0
const NAME_MAX := 12
const POSE_SLEEP := "nap"
const CUE_PET := &"S03"

var _tabs: Segmented
var _list: VBoxContainer
var _scroll: ScrollContainer
var _count: Label
var _tab: int = 0
var _friend: StringName = &""
var _name_edit: LineEdit


func _init() -> void:
	super._init()
	title_key = "ALBUM_TITLE"


func build_body() -> void:
	var chip := PanelContainer.new()
	var box := UiTokens.fill_box(UiTokens.color(&"surface_hi"), 36.0, UiTokens.E1)
	box.content_margin_left = 30
	box.content_margin_right = 30
	chip.add_theme_stylebox_override(&"panel", box)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.custom_minimum_size = Vector2(168.0, 72.0)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count = label("", &"StrongLabel")
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(_count)
	header_extra.add_child(chip)
	_tabs = Segmented.new()
	_tabs.position = Vector2(SIDE, 0.0)
	_tabs.size = Vector2(body.size.x - SIDE * 2.0, Segmented.HEIGHT)
	body.add_child(_tabs)
	_tabs.setup(_tab_texts(), _tab)
	_tabs.selected.connect(func(i: int) -> void: select_tab(i))
	_list = make_scroll(Segmented.HEIGHT + 24.0)
	_scroll = _list.get_parent().get_parent() as ScrollContainer
	_fill()


func refresh_texts() -> void:
	super.refresh_texts()
	if _tabs != null:
		_tabs.set_texts(_tab_texts())
		_fill()


func refresh() -> void:
	if _list != null and (_name_edit == null or not _name_edit.has_focus()):
		var keep := _scroll.scroll_vertical
		_fill()
		_scroll.set_deferred(&"scroll_vertical", keep)


func select_tab(i: int, animate: bool = true) -> void:
	_tab = clampi(i, 0, 2)
	_friend = &""
	_tabs.select(_tab, animate)
	_fill()
	_scroll.scroll_vertical = 0
	if animate:
		_list.modulate.a = 0.0
		Motion.tween(_list, "modulate:a", 1.0, &"short")


## Friend detail (pushed with `standard`; Back / the back chevron returns to the grid).
func show_friend(species: StringName) -> void:
	_tab = 0
	_tabs.select(0, false)
	_friend = species
	_fill()
	_scroll.scroll_vertical = 0
	if not Motion.reduce_motion:
		_list.position.x += 96.0
		Motion.tween(_list, "position:x", _list.position.x - 96.0, &"standard")
	_list.modulate.a = 0.0
	Motion.tween(_list, "modulate:a", 1.0, &"standard")


func _tab_texts() -> PackedStringArray:
	return PackedStringArray([tr("ALBUM_TAB_FRIENDS"), tr("ALBUM_TAB_PHOTOS"), tr("ALBUM_TAB_POSTCARDS")])


func _fill() -> void:
	for c: Node in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_name_edit = null
	if Game.sim == null:
		return
	_count.text = "%d / %d" % [Game.sim.met_count(), ContentRegistry.content.species.size()]
	if _friend != &"":
		_build_detail(_friend)
		return
	match _tab:
		0:
			_build_friends()
		1:
			_build_photos()
		2:
			_build_postcards()


## Species in album_order (GameContent keeps them sorted).
func _ordered_species() -> Array[Dictionary]:
	return ContentRegistry.content.species


## Keeps only characters the fonts can draw (GDD §7.3: others are filtered silently while typing).
static func _filter_name(t: String) -> String:
	var out := ""
	for i in t.length():
		if NameRules.is_allowed(t.unicode_at(i)):
			out += t[i]
	return out


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = COLUMNS_LARGE_TEXT if Settings.get_int(Settings.TEXT_SCALE) >= LARGE_TEXT else COLUMNS
	g.add_theme_constant_override(&"h_separation", GAP)
	g.add_theme_constant_override(&"v_separation", GAP)
	g.mouse_filter = Control.MOUSE_FILTER_PASS
	return g


# ------------------------------------------------------------------ friends

func _build_friends() -> void:
	var g := _grid()
	_list.add_child(g)
	var w := (body.size.x - SIDE * 2.0 - float(GAP * (g.columns - 1))) / float(g.columns)
	for s: Dictionary in _ordered_species():
		g.add_child(_friend_card(StringName(String(s["id"])), s, w))


func _friend_card(sp: StringName, s: Dictionary, w: float) -> Control:
	var met := Game.sim.is_met(sp)
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, 0.0)
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	var c := card(CARD_PAD, ThemeBuilder.R_L, UiTokens.E1)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	v.add_child(_portrait_well(sp, met, WELL_H, &"awake"))
	if met:
		var n := label(Game.display_name(sp), &"StrongLabel")
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(n)
		v.add_child(_hearts(Game.sim.hearts_of(sp), true))
		b.pressed.connect(show_friend.bind(sp))
		PressFeedback.attach(b)
	else:
		var n2 := label(tr("ALBUM_NOT_MET"), &"StrongLabel")
		n2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(n2)
		var h := label(tr(String(s.get("hint_key", ""))), &"SecondaryLabel", true)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.max_lines_visible = 3
		v.add_child(h)
	c.resized.connect(func() -> void: b.custom_minimum_size = Vector2(w, c.get_combined_minimum_size().y))
	b.custom_minimum_size = Vector2(w, c.get_combined_minimum_size().y)
	return b


func _portrait_well(sp: StringName, met: bool, h: float, pose: StringName) -> Control:
	var p := CreaturePortrait.new()
	p.setup(sp, met, pose)
	if met:
		return LiveWell.wrap(p, Vector2(0.0, h), ThemeBuilder.R_M)
	var well := PanelContainer.new()
	well.add_theme_stylebox_override(&"panel", UiTokens.fill_box(UiTokens.color(&"surface"), ThemeBuilder.R_M))
	well.custom_minimum_size = Vector2(0.0, h)
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(p)
	return well


func _hearts(n: int, center: bool) -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER if center else BoxContainer.ALIGNMENT_BEGIN
	h.add_theme_constant_override(&"separation", 3)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.tooltip_text = I18n.fmt(&"ALBUM_HEARTS_A11Y", {"hearts": n})
	for i in HEARTS:
		var r := Icons.rect(&"heart" if i < n else &"heart_empty", HEART_PX)
		if i >= n:
			r.modulate.a = 0.35
		h.add_child(r)
	return h


# ------------------------------------------------------------------ friend detail

func _build_detail(sp: StringName) -> void:
	var s: Dictionary = ContentRegistry.content.species_by_id.get(sp, {})
	var sim := Game.sim
	var back := Button.new()
	back.flat = true
	back.focus_mode = Control.FOCUS_NONE
	back.text = tr("COMMON_BACK")
	back.icon = Icons.texture(&"back", 48.0)
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.add_theme_color_override(&"font_color", UiTokens.color(&"ink"))
	back.add_theme_color_override(&"font_pressed_color", UiTokens.color(&"ink"))
	back.add_theme_color_override(&"font_hover_color", UiTokens.color(&"ink"))
	back.custom_minimum_size = Vector2(0.0, MIN_TARGET)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func() -> void:
		_friend = &""
		_fill())
	PressFeedback.attach(back)
	_list.add_child(back)
	var c := card(30, ThemeBuilder.R_L, UiTokens.E1)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 18)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	_list.add_child(c)
	var best := sim.hearts_of(sp) >= int(ContentRegistry.content.economy.get("best_friend_heart", 5))
	var well := _portrait_well(sp, true, DETAIL_WELL, &"happy" if best else &"awake")
	v.add_child(well)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override(&"separation", 12)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_edit = LineEdit.new()
	_name_edit.text = Game.display_name(sp)
	_name_edit.placeholder_text = tr("ALBUM_NAME_HINT")
	_name_edit.max_length = NAME_MAX
	_name_edit.flat = true
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.add_theme_font_override(&"font", get_theme_font(&"font", &"TitleLabel"))
	_name_edit.add_theme_font_size_override(&"font_size", get_theme_font_size(&"font_size", &"TitleLabel"))
	_name_edit.text_submitted.connect(func(t: String) -> void: _rename(sp, t))
	_name_edit.focus_exited.connect(func() -> void:
		if _name_edit != null:
			_rename(sp, _name_edit.text))
	_name_edit.text_changed.connect(func(t: String) -> void:
		var clean := _filter_name(t)
		if clean != t:
			var caret := _name_edit.caret_column
			_name_edit.text = clean
			_name_edit.caret_column = mini(caret, clean.length()))
	name_row.add_child(_name_edit)
	var pencil := RoundButton.new()
	pencil.plate_px = 108.0
	pencil.icon_px = 48.0
	pencil.icon_name = &"pencil"
	pencil.fill_token = &"primary_tint"
	pencil.elevation = UiTokens.E0
	pencil.custom_minimum_size = Vector2(MIN_TARGET, MIN_TARGET)
	pencil.tooltip_text = tr("ALBUM_RENAME")
	PressFeedback.attach(pencil)
	pencil.pressed.connect(func() -> void:
		_name_edit.grab_focus()
		_name_edit.select_all())
	name_row.add_child(pencil)
	v.add_child(name_row)
	if best:
		v.add_child(_pill_tag(tr("ALBUM_BEST_FRIEND"), &"gold_tint"))
	v.add_child(_hearts(sim.hearts_of(sp), false))
	if sim.is_present(sp):
		var pet := pill_button(tr("ALBUM_PET"), true, ThemeBuilder.BUTTON_H)
		pet.pressed.connect(func() -> void:
			AudioDirector.play_cue(CUE_PET)
			Game.pet(sp)
			_fill())
		v.add_child(pet)
	v.add_child(_fact(tr("ALBUM_FAVOURITE_SPOT"), _spot_text(sp, s)))
	var met_unix := float(sim.state.met.get(String(sp), 0.0))
	if met_unix > 0.0:
		var date := Time.get_date_string_from_unix_time(int(met_unix + sim.state.tz_offset_s))
		v.add_child(label(I18n.fmt(&"ALBUM_FIRST_MET", {"date": date}), &"SecondaryLabel", true))
	v.add_child(label(tr(String(s.get("desc_key", ""))), &"BodyLabel", true))


func _spot_text(sp: StringName, s: Dictionary) -> String:
	if Game.sim.hearts_of(sp) < 1:
		return tr("ALBUM_SPOT_SECRET")
	var spot := String(s.get("favourite_spot", ""))
	return tr("SPOT_" + spot.to_upper()) if spot != "" else tr("ALBUM_SPOT_SECRET")


func _fact(head: String, value: String) -> Control:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := label(head, &"SecondaryLabel")
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(a)
	h.add_child(label(value, &"StrongLabel"))
	return h


func _pill_tag(text: String, fill: StringName) -> Control:
	var p := PanelContainer.new()
	var box := UiTokens.fill_box(UiTokens.color(fill), 30.0)
	box.content_margin_left = 30
	box.content_margin_right = 30
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	p.add_theme_stylebox_override(&"panel", box)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(label(text, &"StrongLabel"))
	return p


func _rename(sp: StringName, t: String) -> void:
	if Game.sim == null:
		return
	var clean := Game.rename(sp, t)
	if _name_edit != null and not _name_edit.has_focus():
		_name_edit.text = clean if clean != "" else Game.display_name(sp)


# ------------------------------------------------------------------ photos

func _build_photos() -> void:
	var sim := Game.sim
	var g := _grid()
	_list.add_child(g)
	var w := (body.size.x - SIDE * 2.0 - float(GAP * (g.columns - 1))) / float(g.columns)
	var behaviours := GameContent.BEHAVIOURS
	var shown := 0
	for s: Dictionary in _ordered_species():
		var sp := String(s["id"])
		var bits := int(sim.state.photos.get(sp, 0))
		for i in behaviours.size():
			if bits & (1 << i) and shown < MAX_PHOTOS:
				g.add_child(_polaroid(StringName(sp), String(behaviours[i]), w))
				shown += 1
	if shown == 0:
		_list.add_child(_empty_note(&"photo", tr("ALBUM_PHOTO_EMPTY")))


func _polaroid(sp: StringName, pose: String, w: float) -> Control:
	var c := card(CARD_PAD, ThemeBuilder.R_M, UiTokens.E1)
	c.custom_minimum_size = Vector2(w, POLAROID_H)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	v.add_child(_portrait_well(sp, true, WELL_H, &"asleep" if pose == POSE_SLEEP else &"awake"))
	var l := label(tr("BEHAVIOUR_" + pose.to_upper()), &"CaptionLabel")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return c


# ------------------------------------------------------------------ postcards

func _build_postcards() -> void:
	var cards := Game.sim.state.postcards
	if cards.is_empty():
		_list.add_child(_empty_note(&"postcard", tr("RECAP_POSTCARD")))
		return
	for i in range(cards.size() - 1, -1, -1):
		_list.add_child(_postcard_row(cards[i]))


func _postcard_row(pc: Dictionary) -> Control:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0.0, POSTCARD_ROW_H)
	var c := card(24, ThemeBuilder.R_L, UiTokens.E1)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(c)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 24)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(h)
	var sp := StringName(String(pc.get("species", "")))
	var plate := Control.new()
	plate.custom_minimum_size = Vector2(120.0, 120.0)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.draw.connect(func() -> void:
		plate.draw_style_box(UiTokens.fill_box(UiTokens.color(&"coral_tint"), 60.0), Rect2(Vector2.ZERO, plate.size)))
	if sp != &"" and Game.sim.is_met(sp):
		var p := CreaturePortrait.new()
		p.size = Vector2(120.0, 120.0)
		p.setup(sp, true, &"happy", false)
		plate.add_child(p)
	else:
		var ic := Icons.rect(&"postcard", 72.0)
		ic.position = Vector2(24.0, 24.0)
		plate.add_child(ic)
	h.add_child(plate)
	var name := Game.display_name(sp) if sp != &"" else ""
	var text := I18n.fmt(StringName(String(pc.get("template", ""))), {"name": name})
	var l := label(text, &"BodyLabel")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(l)
	if not bool(pc.get("read", false)):
		var dot := Control.new()
		dot.custom_minimum_size = Vector2(DOT_PX, DOT_PX)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.tooltip_text = tr("POSTCARD_NEW_A11Y")
		dot.draw.connect(func() -> void:
			dot.draw_circle(dot.size * 0.5, DOT_PX * 0.5, UiTokens.color(&"coral"), true, -1.0, true))
		h.add_child(dot)
	PressFeedback.attach(b)
	b.pressed.connect(func() -> void:
		var hud := _hud()
		if hud != null:
			hud.overlays.show_postcard(pc)
		_fill())
	return b


func _empty_note(icon: StringName, text: String) -> Control:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override(&"separation", 18)
	v.custom_minimum_size = Vector2(0.0, 360.0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Icons.rect(icon, 120.0)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := label(text, &"StrongLabel", true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return v


func _hud() -> HudController:
	var n: Node = self
	while n != null and not (n is HudController):
		n = n.get_parent()
	return n as HudController
