class_name WishAlbum
extends RefCounted
## Active F1 Wishes in the Album (ACTIVE_WISHES §7.3, §7.4; GDD §14.11 b FE-W). AlbumSheet calls
## these builders from its wish section only:
##
##  * [method chip]: the Friends tab's WISH_LIST_BUTTON chip (48 dp) with an unread dot when a wish
##    opened since the list was last seen (Game.wish_list_unread: never a number).
##  * [method detail_section]: the friend detail's ALBUM_WISHING row (icon, title, hint; a 48 dp
##    "Say hello" when the friend is here, the held note when away), the Active F2 "Tea" line
##    (Game.tea_prefs_seen) and the ALBUM_WISH_STAMPS row (48 dp felt stamps, tap shows the title;
##    ALBUM_WISH_STAMPS_EMPTY when none yet).
##  * [method build_list]: the WISH_LIST_TITLE card pushed like a friend page: up to 4 rows
##    (portrait, title, hint, here / away, "Say hello" when here), WISH_LIST_EMPTY when none.
##
## Every wish icon and stamp comes from the WishIcons atlas (one texture: one draw call with the
## sheet's batching), the portraits from the shared BakedWell atlas.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## The Album page id of the wish list (AlbumSheet keeps it in its friend slot, so Back works).
const PAGE := &"__wishes"
## Sizes in UI px (3 px per dp): the 48 dp stamp and Visit target, the wishing icon, the dot.
const STAMP_PX := 144.0
const STAMP_ICON_PX := 96.0
const WISH_ICON_PX := 120.0
const ROW_PORTRAIT := 168.0
const ROW_STAMP_PX := 84.0
const DOT_PX := 21.0
const CHIP_ICON_PX := 72.0
const ROW_SEP := 18
const STAMP_GAP := 24
const MAX_ROWS := 4
## Album › friend: stamps per row before the flow wraps is the layout's; the caption under them.
const STAMP_CAPTION_H := 54.0


static func _names() -> Callable:
	return func(sp: StringName) -> String: return Game.display_name(sp)


# ------------------------------------------------------------------ the Friends chip

## The Wishes chip at the top of Album › Friends; [param open] is called on press.
static func chip(open: Callable) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	var b := Button.new()
	b.name = "WishListChip"
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0.0, UiSheet.MIN_TARGET)
	b.tooltip_text = TranslationServer.translate("WISH_LIST_TITLE")
	var pill := UiSheet.chip(&"surface_hi", UiSurface.PILL, Vector4(30, 0, 36, 0), UiTokens.E1)
	pill.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(pill)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	pill.add_child(h)
	var ic := WishIcons.rect(WishIcons.BUBBLE, CHIP_ICON_PX)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := UiSheet.label(TranslationServer.translate("WISH_LIST_BUTTON"), &"StrongLabel")
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	if Game.sim != null and Game.wish_list_unread():
		var dot := UiSurface.make(UiTokens.color(&"coral"), UiSurface.PILL)
		dot.name = "UnreadDot"
		dot.custom_minimum_size = Vector2(DOT_PX, DOT_PX)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(dot)
	var w := pill.get_combined_minimum_size().x
	b.custom_minimum_size = Vector2(w, UiSheet.MIN_TARGET)
	b.set_meta(PressFeedback.META_RIPPLE_RADIUS, UiSheet.MIN_TARGET * 0.5)
	PressFeedback.attach(b)
	b.pressed.connect(open)
	row.add_child(b)
	return row


# ------------------------------------------------------------------ friend detail

## The wish section of [param sp]'s detail card, appended to [param v] (AlbumSheet._build_detail).
static func detail_section(v: VBoxContainer, sp: StringName, sheet: Control) -> void:
	var w := Game.wish_of(sp)
	if not w.is_empty():
		v.add_child(_wishing_row(sp, w, sheet))
	if Game.feature_on(&"tea") and Game.tea_unlocked():
		v.add_child(_tea_line(sp))
	v.add_child(_stamps(sp))


static func _wishing_row(sp: StringName, w: Dictionary, sheet: Control) -> Control:
	var c := WishText
	var content := ContentRegistry.content
	var wish := StringName(w["wish"])
	var box := UiSheet.chip(&"gold_tint", float(ThemeBuilder.R_M), Vector4(30, 24, 30, 24))
	box.name = "WishingRow"
	box.tooltip_text = c.a11y(content, &"A11Y_WISH_BUBBLE", wish, sp, _names())
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 24)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(h)
	h.add_child(_stamp_art(StringName(w["icon"]), WISH_ICON_PX))
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(col)
	col.add_child(UiSheet.label(TranslationServer.translate("ALBUM_WISHING"), &"SecondaryLabel"))
	col.add_child(UiSheet.label(c.title(content, wish, sp, _names()), &"StrongLabel", true))
	col.add_child(UiSheet.label(c.hint(content, wish, sp, _names()), &"BodyLabel", true))
	if bool(w["present"]):
		col.add_child(_visit_button(sp, sheet))
	else:
		col.add_child(UiSheet.label(I18n.fmt(&"WISH_TIP_HELD", WishText.args(content, sp, _names())),
			&"SecondaryLabel", true))
	return box


static func _tea_line(sp: StringName) -> Control:
	var prefs := Game.tea_prefs_seen(sp)
	var loves: Array = prefs.get("loves", [])
	var likes: Array = prefs.get("likes", [])
	var text := ""
	if not loves.is_empty():
		text = I18n.fmt(&"ALBUM_TEA_LOVES", {"recipes": _recipe_names(loves)})
	elif not likes.is_empty():
		text = I18n.fmt(&"ALBUM_TEA_LIKES", {"recipes": _recipe_names(likes)})
	else:
		text = I18n.fmt(&"ALBUM_TEA_UNKNOWN", {"name": Game.display_name(sp)})
	var h := HBoxContainer.new()
	h.name = "TeaLine"
	h.add_theme_constant_override(&"separation", 24)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := UiSheet.label(TranslationServer.translate("ALBUM_TEA"), &"SecondaryLabel")
	head.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(head)
	var val := UiSheet.label(text, &"StrongLabel", true)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	return h


static func _recipe_names(ids: Array) -> String:
	var out := PackedStringArray()
	for r: Variant in ids:
		var def: Dictionary = ContentRegistry.content.recipes_by_id.get(StringName(String(r)), {})
		var key := String(def.get("name_key", "TEA_R_%s_NAME" % String(r).to_upper()))
		out.append(TranslationServer.translate(key))
	return ", ".join(out)


## ALBUM_WISH_STAMPS: one felt stamp per wish granted with this friend (tap: its title shows under
## the row), or the empty line.
static func _stamps(sp: StringName) -> Control:
	var v := VBoxContainer.new()
	v.name = "WishStamps"
	v.add_theme_constant_override(&"separation", 12)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(UiSheet.label(TranslationServer.translate("ALBUM_WISH_STAMPS"), &"SecondaryLabel"))
	var stamps := Game.wish_stamps(sp)
	if stamps.is_empty():
		v.add_child(UiSheet.label(TranslationServer.translate("ALBUM_WISH_STAMPS_EMPTY"), &"BodyLabel", true))
		return v
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", STAMP_GAP)
	flow.add_theme_constant_override(&"v_separation", STAMP_GAP)
	flow.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(flow)
	var caption := UiSheet.label("", &"CaptionLabel", true)
	caption.custom_minimum_size = Vector2(0.0, STAMP_CAPTION_H)
	var content := ContentRegistry.content
	for wish: StringName in stamps:
		var def: Dictionary = content.wishes_by_id.get(wish, {})
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(STAMP_PX, STAMP_PX)
		var title := WishText.title(content, wish, sp, _names())
		b.tooltip_text = title
		b.add_child(_stamp_art(StringName(String(def.get("icon", ""))), STAMP_PX))
		b.set_meta(PressFeedback.META_RIPPLE_RADIUS, STAMP_PX * 0.5)
		PressFeedback.attach(b)
		b.pressed.connect(func() -> void: caption.text = title)
		flow.add_child(b)
	v.add_child(caption)
	return v


## A felt stamp disc with the wish icon on it (two regions of the one WishIcons texture).
static func _stamp_art(icon: StringName, px: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(px, px)
	holder.size = Vector2(px, px)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var disc := WishIcons.rect(WishIcons.STAMP, px)
	holder.add_child(disc)
	var ip := px * STAMP_ICON_PX / STAMP_PX
	var ic := WishIcons.rect(icon, ip)
	ic.position = Vector2((px - ip) * 0.5, (px - ip) * 0.5)
	holder.add_child(ic)
	return holder


static func _visit_button(sp: StringName, sheet: Control) -> Button:
	var b := UiSheet.pill_button(TranslationServer.translate("WISH_LIST_VISIT"), false, UiSheet.MIN_TARGET, true)
	b.name = "Visit"
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(func() -> void: visit(sp, sheet))
	return b


## Closes the Album and glides the camera to [param sp] (map pan glide, ARCHITECTURE §3.4).
static func visit(sp: StringName, sheet: Control) -> void:
	var n: Node = sheet
	while n != null and not (n is HudController):
		n = n.get_parent()
	var hud := n as HudController
	if hud != null:
		hud.sheets.close()
	if CreatureLayer.current != null and CreatureLayer.current.wishes != null:
		CreatureLayer.current.wishes.visit(sp)


# ------------------------------------------------------------------ the wish list card

## The WISH_LIST_TITLE card into [param list] (marks the list seen: the chip's dot clears).
static func build_list(list: VBoxContainer, sheet: Control) -> void:
	Game.mark_wish_list_seen()
	var c := UiSheet.card(30, ThemeBuilder.R_L, UiTokens.E1)
	c.name = "WishList"
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 24)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	list.add_child(c)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 18)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hi := WishIcons.rect(WishIcons.BUBBLE, CHIP_ICON_PX * 1.25)
	hi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hi)
	var t := UiSheet.label(TranslationServer.translate("WISH_LIST_TITLE"), &"TitleLabel", true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(t)
	v.add_child(head)
	var rows := Game.wishes()
	if rows.is_empty():
		v.add_child(UiSheet.label(TranslationServer.translate("WISH_LIST_EMPTY"), &"BodyLabel", true))
		return
	for i in mini(rows.size(), MAX_ROWS):
		v.add_child(_list_row(rows[i], sheet))


static func _list_row(w: Dictionary, sheet: Control) -> Control:
	var content := ContentRegistry.content
	var sp := StringName(w["species"])
	var wish := StringName(w["wish"])
	var row := UiSheet.chip(&"surface", float(ThemeBuilder.R_M), Vector4(24, 24, 24, 24))
	row.name = "WishRow_%s" % sp
	row.tooltip_text = WishText.a11y(content, &"A11Y_WISH_LIST_ROW", wish, sp, _names())
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 24)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var face := Control.new()
	face.custom_minimum_size = Vector2(ROW_PORTRAIT, ROW_PORTRAIT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var well := BakedWell.create("stamp|%s" % sp, Vector2(ROW_PORTRAIT, ROW_PORTRAIT), ROW_PORTRAIT * 0.5,
		func(_sz: Vector2) -> Control: return AlbumSheet.portrait_cell(sp, true, &"happy"))
	well.size = Vector2(ROW_PORTRAIT, ROW_PORTRAIT)
	face.add_child(well)
	h.add_child(face)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(col)
	col.add_child(UiSheet.label(Game.display_name(sp), &"SecondaryLabel"))
	# the wish's stamp leads its title (a badge over the portrait hid under the baked well)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override(&"separation", 12)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(_stamp_art(StringName(w["icon"]), ROW_STAMP_PX))
	var tl := UiSheet.label(WishText.title(content, wish, sp, _names()), &"StrongLabel", true)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(tl)
	col.add_child(title_row)
	col.add_child(UiSheet.label(WishText.hint(content, wish, sp, _names()), &"BodyLabel", true))
	var here := bool(w["present"])
	var where := UiSheet.label(TranslationServer.translate("WISH_LIST_HERE" if here else "WISH_LIST_AWAY"),
		&"CaptionLabel", true)
	col.add_child(where)
	if here:
		col.add_child(_visit_button(sp, sheet))
	return row
