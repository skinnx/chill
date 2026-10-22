class_name TeaSheet
extends UiSheet
## The Tea nook sheet (Active F2 Tea & Treats; GDD §14.1, §14.11 FE-T; ACTIVE_TEA §3-§10). Tabs
## Brew | Recipes | Teaware (Teaware after the first brew). Opens at the large detent: the Brew tab
## is a fixed layout (TeaPot: pot, spoon, tray, pantry) whose drags never pan, scroll or close the
## sheet; the swipe-to-dismiss lives on the grabber and header only (UiSheet).
##
##  * Brew: drag or tap petals in, stir, pour (or Simple brewing: one Brew pill). A new cup rises
##    in the reveal card (recipe, kind chip; "A new recipe!" the first time); a tap dismisses it.
##  * Tap a cup on the tray: the pantry rows become "Offer to a friend" (64 dp portrait chips of the
##    friends visiting, those with a tea wish first, then by hearts). A chip closes the sheet, the
##    cup arcs from the nook to the friend (TeaNook), it sips, and the reaction toast follows. All
##    through Game.offer_cup (the wish grant and its own feedback belong to Active F1).
##  * Recipes: "9 of 24 recipes", the any-mix tip, a 3-column grid of cards in book order. Found:
##    the cup, name, kind, the mix, loved / liked by (met friends, revealed only) and "Fill the
##    pot"; still to find: a soft silhouette, "Still a secret" and the hint. A recipe a visiting
##    friend wishes for wears that friend's name.
##  * Teaware: three sections (teapot, cups, cloth) of item cards: price chip, "Place" (buys and
##    uses), "Use" / "In use"; not affordable = the Garden's soft "A little more dew".
##
## Entry points (HudController hooks): the tea nook prop in the world (TeaNook.open_requested), the
## Basket sheet's "Tea nook" row, and QA --qa-sheet=tea. [method wire] connects the world side.
##
## QA user args (tools/qa/capture.sh still --fixture=active_mid --qa-tea=<state>):
##   --qa-tea=brew|drag|stir|pour|reveal|offer|simple|recipes|teaware   opens the sheet in that state,
##       frozen mid-interaction where it has one (drag: a petal carried over the pot; stir: two
##       thirds round with the swirl; pour: mid-pour into the tray; reveal: a new recipe's card;
##       offer: a cup picked with the friend chips; simple: Simple brewing's Brew pill)
##   --qa-tea-gather=<bed_id>[@<ms>]   (PlotsLayer) taps that bed for its petals and freezes the
##       flight to the nook <ms> after the tap (default 260)

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const ARG_QA_TEA := "--qa-tea="
const TAB_BREW := 0
const TAB_RECIPES := 1
const TAB_TEAWARE := 2
const COLUMNS := 3
const CARD_MIN := Vector2(96.0, 128.0) * UiTokens.PX_PER_DP
const CARD_ICON_H := 150.0
const MIX_H := 54.0
const CHIP := 64.0 * UiTokens.PX_PER_DP
const CHIP_GAP := 8.0 * UiTokens.PX_PER_DP
const REVEAL_ICON := 264.0
const REVEAL_HOLD_S := 2.6
const TEAWARE_ICON := 180.0
## The reveal card's layer offset (above TeaPot's TEX slot and its labels' TEXT slots).
const REVEAL_LIFT := UiBatch.TEXT + UiBatch.TEXT_SLOTS
## "Fill the pot" pills in the 96 dp recipe cards keep a slim side padding.
const FILL_PAD := 15.0
const CUE_NOT_YET := &"S11"
const CUE_RECIPE := &"S33"
const CUE_CLINK := &"S32"
const HAPTIC_MEDIUM := {"subtle": "MEDIUM", "full": "MEDIUM"}
const SLOTS: Array[String] = ["teapot", "cup", "cloth"]
const SLOT_KEYS := {"teapot": "TEA_SLOT_TEAPOT", "cup": "TEA_SLOT_CUP", "cloth": "TEA_SLOT_CLOTH"}

static var _wired_hud: HudController = null

var hud: HudController
var pot: TeaPot
var _tabs: Segmented
var _tab: int = TAB_BREW
var _brew: Control
var _offer: Control
var _reveal: Control
var _reveal_t: float = -1.0
var _list: VBoxContainer
var _scroll: ScrollContainer
## Opened from a friend (the Album's "Offer tea"): a tapped cup goes straight to this friend.
var _for_friend: StringName = &""


static func make(p_hud: HudController) -> TeaSheet:
	var s := TeaSheet.new()
	s.hud = p_hud
	return s


func _init() -> void:
	super._init()
	title_key = "TEA_SHEET_TITLE"


func _ready() -> void:
	super._ready()
	# the pot and two jar rows need the room: the Tea sheet opens at the large detent
	expand(true, false)
	Game.sim_event.connect(_on_sim_event)


func _on_sim_event(ev: Dictionary) -> void:
	match StringName(String(ev.get("type", ""))):
		WorldSim.EV_PETALS, WorldSim.EV_TEA_OFFERED, WorldSim.EV_TEAWARE, WorldSim.EV_ARRIVED, WorldSim.EV_DEPARTED:
			if not pot.is_busy():
				refresh()


func build_body() -> void:
	_tabs = Segmented.new()
	_tabs.position = Vector2(SIDE, 0.0)
	_tabs.size = Vector2(body.size.x - SIDE * 2.0, Segmented.HEIGHT)
	body.add_child(_tabs)
	_tabs.setup(_tab_texts(), _tab)
	_tabs.selected.connect(func(i: int) -> void: select_tab(i))
	_list = make_scroll(Segmented.HEIGHT + 24.0)
	keep_scroll_below(_tabs)
	_scroll = _list.get_parent().get_parent() as ScrollContainer
	_brew = Control.new()
	_brew.name = "Brew"
	_brew.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_brew)
	_brew.set_anchors_preset(Control.PRESET_FULL_RECT)
	_brew.offset_left = SIDE
	_brew.offset_right = -SIDE
	_brew.offset_bottom = 0.0
	var place := func() -> void:
		if is_instance_valid(_brew) and is_instance_valid(_tabs):
			_brew.offset_top = _tabs.position.y + _tabs.size.y + TABS_GAP + LIST_TOP_PAD
	_tabs.resized.connect(place)
	place.call()
	pot = TeaPot.new()
	pot.name = "TeaPot"
	pot.simple = simple_brewing()
	_brew.add_child(pot)
	pot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pot.brewed.connect(_on_brewed)
	pot.cup_tapped.connect(_on_cup_tapped)
	pot.changed.connect(func() -> void:
		if _offer != null and pot.selected_cup >= Game.tray().size():
			close_offer())
	_show_tab()


## Simple brewing: the Settings toggle, by default the Reduce Motion value (ACTIVE_TEA §4).
static func simple_brewing() -> bool:
	return Settings.get_bool(Settings.SIMPLE_BREWING)


func _tab_texts() -> PackedStringArray:
	var t := PackedStringArray([tr("TEA_TAB_BREW"), tr("TEA_TAB_RECIPES")])
	if teaware_open():
		t.append(tr("TEA_TAB_TEAWARE"))
	return t


## The Teaware tab appears after the first brew (ACTIVE_TEA §9; GDD §14.4 D19).
static func teaware_open() -> bool:
	return Game.sim != null and not Game.recipes_found().is_empty()


func refresh_texts() -> void:
	super.refresh_texts()
	if _tabs != null:
		_tabs.set_texts(_tab_texts())
		if pot != null:
			pot.refresh_texts()
		_fill()


func refresh() -> void:
	if pot == null:
		return
	pot.refresh()
	if _tabs.get_child_count() != _tab_texts().size():
		_tabs.setup(_tab_texts(), _tab)
	if _tab != TAB_BREW:
		var keep := _scroll.scroll_vertical
		_fill()
		_scroll.set_deferred(&"scroll_vertical", keep)
	elif _offer != null:
		_build_offer()


func current_tab() -> int:
	return _tab


func select_tab(i: int, animate: bool = true) -> void:
	_tab = clampi(i, 0, _tab_texts().size() - 1)
	_tabs.select(_tab, animate)
	_show_tab()
	if animate:
		var c: Control = _brew if _tab == TAB_BREW else _list
		c.modulate.a = 0.0
		Motion.tween(c, "modulate:a", 1.0, &"short")


func _show_tab() -> void:
	_brew.visible = _tab == TAB_BREW
	_scroll.visible = _tab != TAB_BREW
	if _tab != TAB_BREW:
		close_offer()
	_fill()
	_scroll.scroll_vertical = 0


func _process(delta: float) -> void:
	super._process(delta)
	if _reveal_t >= 0.0:
		_reveal_t += delta
		if _reveal_t >= REVEAL_HOLD_S:
			dismiss_reveal()


# ------------------------------------------------------------------ reveal (ACTIVE_TEA §4)

func _on_brewed(recipe: StringName, first: bool, _tray_index: int) -> void:
	show_reveal(recipe, first)
	if _tabs.get_child_count() != _tab_texts().size():
		_tabs.setup(_tab_texts(), _tab)


## The result card rises over the pot (`emphasized`; a 150 ms fade under Reduce Motion); a tap
## dismisses it early, and input is never blocked behind it.
func show_reveal(recipe: StringName, first: bool, instant: bool = false) -> void:
	dismiss_reveal(true)
	var r: Dictionary = ContentRegistry.content.recipes_by_id.get(recipe, {})
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.name = "Reveal"
	var c := card(36, ThemeBuilder.R_L, UiTokens.E2)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(c)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override(&"separation", 12)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	if first:
		var stamp := chip(&"coral_tint", UiSurface.PILL, Vector4(30, 6, 30, 6))
		stamp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var sl := label(tr("TEA_NEW_RECIPE"), &"StrongLabel")
		sl.add_theme_color_override(&"font_color", UiTokens.sc(&"ink"))
		stamp.add_child(sl)
		v.add_child(stamp)
	var icon := TeaIcon.of_recipe(recipe, true, Vector2(REVEAL_ICON, REVEAL_ICON))
	icon.glow = 1.0 if first else 0.0
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(icon)
	var name_l := label(tr(String(r.get("name_key", ""))), &"BodyLabel", true)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	var kind := chip(&"leaf_tint" if String(r.get("kind", "tea")) == "tea" else &"gold_tint", UiSurface.PILL,
			Vector4(24, 0, 24, 0))
	kind.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	kind.add_child(label(tr("TEA_BOOK_TEA" if String(r.get("kind", "tea")) == "tea" else "TEA_BOOK_TREAT"),
			&"CaptionLabel"))
	v.add_child(kind)
	b.pressed.connect(func() -> void: dismiss_reveal())
	_brew.add_child(b)
	# the card lies over the pot: lift its whole layer above the TeaPot (and the pot's labels)
	b.set_meta(&"tea_lift", REVEAL_LIFT)
	b.z_index += REVEAL_LIFT
	var area := pot.pot_area()
	var w := minf(area.size.x * 0.62, 620.0)
	b.size = Vector2(w, 0.0)
	b.custom_minimum_size = Vector2(w, 0.0)
	c.custom_minimum_size = Vector2(w, 0.0)
	c.resized.connect(func() -> void:
		if is_instance_valid(b) and is_instance_valid(c):
			b.size = c.size
			b.position = Vector2((pot.size.x - pot.tray_width() - c.size.x) * 0.5, maxf((area.size.y - c.size.y) * 0.5, 0.0)))
	_reveal = b
	_reveal_t = 0.0
	if first:
		TeaArt.cue(CUE_RECIPE, {}, HAPTIC_MEDIUM)
	if instant:
		return
	if Motion.reduce_motion:
		b.modulate.a = 0.0
		var t := b.create_tween()
		t.tween_property(b, "modulate:a", 1.0, Motion.duration(&"reduce_motion_crossfade"))
	else:
		b.modulate.a = 0.0
		b.scale = Vector2.ONE * 0.9
		b.pivot_offset = Vector2(w * 0.5, 200.0)
		Motion.tween(b, "modulate:a", 1.0, &"emphasized")
		Motion.spring_to(b, "scale", Vector2.ONE, &"pop")
	FrameGovernor.hold_for(Motion.duration(&"emphasized"))


func dismiss_reveal(instant: bool = false) -> void:
	_reveal_t = -1.0
	if _reveal == null or not is_instance_valid(_reveal):
		_reveal = null
		return
	var b := _reveal
	_reveal = null
	if instant:
		b.queue_free()
		return
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Motion.fade_out(b, &"short")
	t.finished.connect(b.queue_free)


func reveal_card() -> Control:
	return _reveal if _reveal != null and is_instance_valid(_reveal) else null


# ------------------------------------------------------------------ offering (ACTIVE_TEA §7)

func _on_cup_tapped(i: int) -> void:
	if _for_friend != &"" and Game.sim.present_index(_for_friend) >= 0:
		offer_to(i, _for_friend)
		return
	if pot.selected_cup == i and _offer != null:
		close_offer()
		return
	open_offer(i)


## The pantry rows become the "Offer to a friend" row for tray cup [param i].
func open_offer(i: int) -> void:
	pot.selected_cup = i
	pot.offer_mode = true
	AudioDirector.play_cue(&"S01")
	_build_offer()


func close_offer() -> void:
	if pot != null:
		pot.selected_cup = -1
		pot.offer_mode = false
	if _offer != null and is_instance_valid(_offer):
		_offer.queue_free()
	_offer = null


## Present friends for the offer row: those holding a tea wish first, then by hearts (desc).
static func offer_order() -> Array[StringName]:
	var out: Array[StringName] = []
	if Game.sim == null:
		return out
	for p: Dictionary in Game.sim.state.present:
		out.append(StringName(String(p["species"])))
	var wish := func(sp: StringName) -> int:
		var w := Game.wish_of(sp)
		return 1 if not w.is_empty() and String(w.get("kind", "")).begins_with("tea") else 0
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		var wa: int = wish.call(a)
		var wb: int = wish.call(b)
		if wa != wb:
			return wa > wb
		var ha := Game.heart_level(a)
		var hb := Game.heart_level(b)
		if ha != hb:
			return ha > hb
		return String(a) < String(b))
	return out


func _build_offer() -> void:
	if _offer != null and is_instance_valid(_offer):
		_offer.queue_free()
	var r := pot.jars_rect()
	var box := VBoxContainer.new()
	box.name = "Offer"
	box.add_theme_constant_override(&"separation", 12)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = r.position + Vector2(0.0, -24.0)
	box.size = Vector2(r.size.x, r.size.y + 24.0)
	_brew.add_child(box)
	_offer = box
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := label(tr("TEA_OFFER_TITLE"), &"StrongLabel")
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(tl)
	var back := RoundButton.new()
	back.name = "OfferBack"
	back.plate_px = 96.0
	back.icon_px = 42.0
	back.icon_name = &"back"
	back.custom_minimum_size = Vector2(MIN_TARGET, MIN_TARGET)
	PressFeedback.attach(back)
	back.pressed.connect(close_offer)
	head.add_child(back)
	box.add_child(head)
	var friends := offer_order()
	if friends.is_empty():
		box.add_child(label(tr("TEA_OFFER_NOBODY"), &"SecondaryLabel", true))
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", roundi(CHIP_GAP * 2.0))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var cup := pot.selected_cup
	for sp: StringName in friends:
		row.add_child(_friend_chip(sp, cup))


func _friend_chip(sp: StringName, cup: int) -> Control:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.name = "Chip_%s" % sp
	b.custom_minimum_size = Vector2(CHIP, CHIP + 60.0)
	b.tooltip_text = I18n.fmt(&"TEA_OFFER_A11Y", {"recipe": _cup_name(cup), "name": Game.display_name(sp)})
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override(&"separation", 6)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(v)
	var well := BakedWell.create("teachip|%s" % sp, Vector2(CHIP, CHIP), CHIP * 0.5, func(_sz: Vector2) -> Control:
		return AlbumSheet.portrait_cell(sp, true, &"happy"))
	well.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(well)
	var w := Game.wish_of(sp)
	if not w.is_empty() and String(w.get("kind", "")).begins_with("tea"):
		var badge := Icons.rect(&"sparkle", 30.0)
		badge.position = Vector2(CHIP - 30.0, 0.0)
		well.add_child(badge)
	var nl := label(Game.display_name(sp), &"CaptionLabel")
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.custom_minimum_size = Vector2(CHIP, 0.0)
	v.add_child(nl)
	PressFeedback.attach(b)
	b.pressed.connect(offer_to.bind(cup, sp))
	return b


func _cup_name(i: int) -> String:
	var tray := Game.tray()
	if i < 0 or i >= tray.size():
		return ""
	var r: Dictionary = ContentRegistry.content.recipes_by_id.get(StringName(String(tray[i]["recipe"])), {})
	return tr(String(r.get("name_key", "")))


## Offers tray cup [param i] to [param sp]: the sheet closes, the cup arcs to the friend, then the
## reaction (all decided by Game.offer_cup).
func offer_to(i: int, sp: StringName) -> void:
	var tray := Game.tray()
	if i < 0 or i >= tray.size():
		return
	var cup: Dictionary = tray[i]
	var res := Game.offer_cup(i, sp)
	if res.is_empty():
		refresh()
		return
	close_offer()
	close_requested.emit()
	present_offer(hud, sp, cup, res)


## Opens the Tea sheet to offer [param species] a cup (an entry for the Album's friend page,
## Active F1 / FE-W): tapping a cup on the tray offers it to that friend straight away.
static func open_for_friend(p_hud: HudController, species: StringName) -> void:
	if p_hud == null or Game.sim == null or not Game.tea_unlocked():
		return
	p_hud.open_sheet(&"tea")
	var s := p_hud.sheets.current as TeaSheet
	if s == null:
		return
	s.select_tab(TAB_BREW, false)
	s._for_friend = species
	if Game.tray().is_empty():
		s.pot.show_note(TranslationServer.translate("TEA_TRAY_EMPTY"))
	else:
		s.pot.show_note(TranslationServer.translate("TEA_OFFER_TITLE") + " · " + Game.display_name(species))


## The world side of an offering (also for an Album "Offer tea" entry, Active F1): the cup arc,
## the clink, and the reaction toast after the sip.
static func present_offer(p_hud: HudController, sp: StringName, cup: Dictionary, res: Dictionary) -> void:
	var of: Dictionary = ContentRegistry.content.tea.get("offering", {})
	var arc := float(of.get("cup_arc_ms", 320.0)) * UiTokens.MS
	var sip := float(of.get("sip_ms", 2400.0)) * UiTokens.MS
	var color := TeaArt.recipe_color(StringName(String(cup.get("recipe", ""))), cup.get("petals", []))
	var treat := StringName(String(cup.get("kind", "tea"))) == TeaRules.KIND_TREAT
	if TeaNook.current != null:
		TeaNook.current.send_cup(sp, color, treat)
	var name := Game.display_name(sp)
	var recipe_name := TeaArt.recipe_name(StringName(String(res.get("recipe", ""))))
	var text := reaction_text(res, name, recipe_name)
	var asleep := Game.is_napping(sp)
	if asleep:
		text = I18n.fmt(&"TEA_OFFER_ASLEEP", {"name": name})
	if p_hud == null or not p_hud.is_inside_tree():
		return
	var tree := p_hud.get_tree()
	tree.create_timer(arc).timeout.connect(func() -> void: TeaArt.cue(CUE_CLINK, {}, {}))
	tree.create_timer(0.0 if asleep else arc + sip).timeout.connect(func() -> void:
		if is_instance_valid(p_hud):
			p_hud.overlays.show_toast(text))


## The reaction line (+ the petals line when some fit in the pantry).
static func reaction_text(res: Dictionary, name: String, recipe_name: String) -> String:
	var react := StringName(String(res.get("reaction", "content")))
	var key := &"TEA_REACT_CONTENT"
	if react == TeaRules.REACT_LOVED:
		key = &"TEA_REACT_LOVED"
	elif react == TeaRules.REACT_LIKED:
		key = &"TEA_REACT_LIKED"
	var text := I18n.fmt(key, {"name": name, "recipe": recipe_name})
	if int(res.get("petals_back", 0)) > 0:
		var f: Dictionary = ContentRegistry.content.flowers_by_id.get(StringName(String(res.get("flower", ""))), {})
		text += " " + I18n.fmt(&"TEA_REACT_PETALS", {"name": name,
			"flower": TranslationServer.translate(String(f.get("name_key", ""))).to_lower()})
	return text


# ------------------------------------------------------------------ Recipes and Teaware tabs

func _fill() -> void:
	if _list == null:
		return
	for c: Node in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if Game.sim == null or _tab == TAB_BREW:
		return
	if _tab == TAB_RECIPES:
		_fill_recipes()
	else:
		_fill_teaware()


func _fill_recipes() -> void:
	var content := ContentRegistry.content
	var found := Game.recipes_found()
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var count := label(I18n.fmt(&"TEA_BOOK_COUNT", {"count": found.size(), "total": content.recipes.size()}),
			&"StrongLabel")
	head.add_child(count)
	_list.add_child(head)
	_list.add_child(label(tr("TEA_BOOK_TIP"), &"SecondaryLabel", true))
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override(&"h_separation", 24)
	grid.add_theme_constant_override(&"v_separation", 24)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(grid)
	var wished := _wished_recipes()
	for r: Dictionary in content.recipes:
		var id := StringName(String(r["id"]))
		grid.add_child(_recipe_card(id, r, found.has(String(id)), String(wished.get(id, ""))))


## recipe id -> the display name of a visiting friend wishing for it (tea:<recipe> wishes).
func _wished_recipes() -> Dictionary:
	var out := {}
	for w: Dictionary in Game.wishes():
		if StringName(w.get("kind", &"")) == &"tea" and bool(w.get("present", false)):
			out[StringName(String(w.get("arg", "")))] = Game.display_name(StringName(w["species"]))
	return out


func _recipe_card(id: StringName, r: Dictionary, found: bool, wisher: String) -> Control:
	var c := card(18, ThemeBuilder.R_M, UiTokens.E1)
	c.custom_minimum_size = CARD_MIN
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	var icon := TeaIcon.of_recipe(id, found, Vector2(0.0, CARD_ICON_H))
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(icon)
	if wisher != "":
		var wc := chip(&"coral_tint", UiSurface.PILL, Vector4(18, 0, 18, 0))
		wc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var wh := HBoxContainer.new()
		wh.add_theme_constant_override(&"separation", 6)
		wh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sp := Icons.rect(&"sparkle", 30.0)
		sp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		wh.add_child(sp)
		var wl := label(wisher, &"CaptionLabel")
		wl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		wh.add_child(wl)
		wc.add_child(wh)
		v.add_child(wc)
	var named := String(r.get("match", "")) != "fallback"
	if not found:
		var sl := label(tr("TEA_BOOK_SECRET"), &"StrongLabel", true)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.add_theme_color_override(&"font_color", UiTokens.sc(&"ink_2"))
		v.add_child(sl)
		var hl := label(tr(String(r.get("hint_key", ""))), &"SecondaryLabel", true)
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(hl)
		return c
	var nl := label(tr(String(r.get("name_key", ""))), &"StrongLabel", true)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nl)
	var mix := _mix_of(id)
	if named:
		var mi := TeaIcon.of_mix(mix[0], int(mix[1]), Vector2(0.0, MIX_H))
		mi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(mi)
	else:
		var hl2 := label(tr(String(r.get("hint_key", ""))), &"SecondaryLabel", true)
		hl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(hl2)
	var by := _loved_line(id)
	if by != "":
		var bl := label(by, &"SecondaryLabel", true)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(bl)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)
	if named:
		var can := can_fill(id)
		var b := pill_button(tr("TEA_BOOK_FILL") if can else tr("TEA_BOOK_FILL_MORE"), can, CARD_BUTTON_H, false)
		b.custom_minimum_size.x = 0.0
		b.clip_text = true
		for st: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"]:
			var sb := b.get_theme_stylebox(st)
			if sb != null:
				sb.content_margin_left = FILL_PAD
				sb.content_margin_right = FILL_PAD
		b.add_theme_font_size_override(&"font_size", roundi(ThemeBuilder.SIZE_CAPTION * Settings.get_int(
				Settings.TEXT_SCALE) / 100.0))
		b.pressed.connect(_on_fill.bind(id, b))
		v.add_child(b)
	return c


## [petals: Array (flower ids, repeats), drops] of a named recipe.
static func _mix_of(id: StringName) -> Array:
	var content := ContentRegistry.content
	var want := content.recipe_petals(id)
	var list: Array = []
	var keys := want.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int((content.petals_by_flower.get(StringName(str(a)), {}) as Dictionary).get("jar_order", 0)) \
				< int((content.petals_by_flower.get(StringName(str(b)), {}) as Dictionary).get("jar_order", 0)))
	for f: Variant in keys:
		for i in int(want[f]):
			list.append(String(f))
	var r: Dictionary = content.recipes_by_id.get(id, {})
	return [list, int(r.get("drops", 0))]


## "Loved by …" / "Liked by …" for met friends whose preference is revealed (ACTIVE_TEA §6).
func _loved_line(id: StringName) -> String:
	var loves: PackedStringArray = []
	var likes: PackedStringArray = []
	for sp_v: Variant in ContentRegistry.content.tea_prefs:
		var sp := StringName(str(sp_v))
		if not Game.sim.is_met(sp):
			continue
		var known := Game.tea_prefs_seen(sp)
		if (known.get("loves", []) as Array).has(String(id)):
			loves.append(Game.display_name(sp))
		elif (known.get("likes", []) as Array).has(String(id)):
			likes.append(Game.display_name(sp))
	if not loves.is_empty():
		return I18n.fmt(&"TEA_BOOK_LOVED_BY", {"names": ", ".join(loves)})
	if not likes.is_empty():
		return I18n.fmt(&"TEA_BOOK_LIKED_BY", {"names": ", ".join(likes)})
	return ""


## True when the pantry (plus what the pot holds now) and the wallet can make recipe [param id].
static func can_fill(id: StringName) -> bool:
	if Game.sim == null:
		return false
	var mix := _mix_of(id)
	var have := Game.pantry()
	var pot_now := Game.pot()
	for f: Variant in pot_now.get("petals", []):
		have[String(f)] = int(have.get(String(f), 0)) + 1
	var need := {}
	for f: Variant in mix[0]:
		need[String(f)] = int(need.get(String(f), 0)) + 1
	for f: String in need:
		if int(have.get(f, 0)) < int(need[f]):
			return false
	var cost := int(TeaArt.tea_num("dew_drop", "cost_dew", 3))
	var refund := int(pot_now.get("drops", 0)) * cost
	return Game.sim.state.dew + refund >= int(mix[1]) * cost


## "Fill the pot": returns what the pot holds to the pantry (drops refunded), then adds the
## recipe's petals and drops (charged, refundable) and switches to Brew.
func fill_pot(id: StringName) -> bool:
	if not can_fill(id) or pot.is_busy():
		return false
	var mix := _mix_of(id)
	var safety := 8
	while not (Game.pot().get("petals", []) as Array).is_empty() and safety > 0:
		Game.pot_remove(0)
		safety -= 1
	while int(Game.pot().get("drops", 0)) > 0 and safety > -8:
		Game.pot_remove_drop()
		safety -= 1
	for f: Variant in mix[0]:
		Game.pot_add_petal(StringName(String(f)))
	for d in int(mix[1]):
		Game.pot_add_drop()
	select_tab(TAB_BREW)
	pot.refresh()
	TeaArt.cue(TeaPot.CUE_PLIP, {}, TeaPot.HAPTIC_TICK)
	return true


func _on_fill(id: StringName, b: Button) -> void:
	if not fill_pot(id):
		AudioDirector.play_cue(CUE_NOT_YET)
		PressFeedback.nudge(b)


func _fill_teaware() -> void:
	var content := ContentRegistry.content
	var tw := Game.teaware()
	var owned: Array = tw.get("owned", [])
	var in_use: Dictionary = tw.get("in_use", {})
	for slot: String in SLOTS:
		_list.add_child(label(tr(String(SLOT_KEYS[slot])), &"StrongLabel"))
		for x: Dictionary in GameContent._records(content.tea["teaware"]):
			if String(x["slot"]) != slot:
				continue
			var id := StringName(String(x["id"]))
			_list.add_child(_teaware_card(id, x, owned.has(String(id)), String(in_use.get(slot, "")) == String(id)))


func _teaware_card(id: StringName, x: Dictionary, owned: bool, using: bool) -> Control:
	var c := card(24, ThemeBuilder.R_L, UiTokens.E1)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 30)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(h)
	var icon := TeaIcon.of_teaware(id, Vector2(TEAWARE_ICON, TEAWARE_ICON))
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override(&"separation", 9)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	v.add_child(label(tr(String(x.get("name_key", ""))), &"StrongLabel", true))
	var price := int(x.get("cost", 0))
	var affordable := price <= Game.sim.state.dew
	if not owned:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_price_chip(price, affordable))
		v.add_child(row)
	var text := tr("TEA_TEAWARE_IN_USE") if using else tr("TEA_TEAWARE_USE")
	if not owned:
		text = tr("TEA_TEAWARE_PLACE") if affordable else tr("GARDEN_MORE_DEW")
	var b := pill_button(text, not using and (owned or affordable))
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.disabled = using
	b.pressed.connect(_on_teaware.bind(id, owned, b))
	v.add_child(b)
	return c


func _price_chip(price: int, affordable: bool) -> Control:
	var p := chip(&"gold_tint", 36.0, Vector4(18, 0, 24, 0))
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var ic := Icons.rect(&"dew", 48.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := label(TopBarView.format_dew(price), &"PriceLabel")
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if not affordable:
		l.add_theme_color_override(&"font_color", UiTokens.sc(&"ink_2"))
	h.add_child(l)
	return p


func _on_teaware(id: StringName, owned: bool, b: Button) -> void:
	if not owned:
		if not Game.buy_teaware(id):
			AudioDirector.play_cue(CUE_NOT_YET)
			PressFeedback.nudge(b)
			return
	Game.use_teaware(id)
	AudioDirector.play_cue(&"S05")
	refresh()


# ------------------------------------------------------------------ world wiring (HudController)

## Connects the tea nook, the petal harvest and the tea toasts to [param p_hud] (idempotent).
static func wire(p_hud: HudController) -> void:
	if _wired_hud == p_hud:
		return
	_wired_hud = p_hud
	if not Game.tea_nook_awake.is_connected(_on_nook_awake):
		Game.tea_nook_awake.connect(_on_nook_awake)
	if TeaNook.current != null and not TeaNook.current.open_requested.is_connected(_on_nook_open):
		TeaNook.current.open_requested.connect(_on_nook_open)
	if PlotsLayer.current != null and not PlotsLayer.current.jar_full.is_connected(_on_jar_full):
		PlotsLayer.current.jar_full.connect(_on_jar_full)
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(ARG_QA_TEA):
			var state := a.trim_prefix(ARG_QA_TEA)
			if Game.is_ready:
				_qa_open.call_deferred(state)
			else:
				Game.world_ready.connect(func(_r: Array) -> void: _qa_open.call_deferred(state), CONNECT_ONE_SHOT)


static func _on_nook_awake() -> void:
	if _wired_hud != null and is_instance_valid(_wired_hud):
		_wired_hud.overlays.show_toast(TranslationServer.translate("TEA_NOOK_AWAKE"))


static func _on_nook_open() -> void:
	if _wired_hud != null and is_instance_valid(_wired_hud) and _wired_hud.sheets.current_id != &"tea":
		_wired_hud.open_sheet(&"tea")


static func _on_jar_full(flower: StringName) -> void:
	if _wired_hud == null or not is_instance_valid(_wired_hud):
		return
	var f: Dictionary = ContentRegistry.content.flowers_by_id.get(flower, {})
	_wired_hud.overlays.show_toast(I18n.fmt(&"TEA_JAR_FULL",
			{"flower": TranslationServer.translate(String(f.get("name_key", ""))).to_lower()}))


## The bed card's tea lines (OverlayHost.show_bed_card): spare petals and the next one (good news
## only, E2), or the jars-full note.
static func bed_card_text(bed: StringName, text: String) -> String:
	if Game.sim == null or not Game.tea_unlocked():
		return text
	var ready := Game.petals_ready(bed)
	if ready > 0:
		text += " · " + I18n.fmt(&"TEA_BED_PETALS", {"count": ready})
	var next := Game.next_petal_in_s(bed)
	if next < INF and next > 0.0:
		text += " · " + I18n.fmt(&"TEA_BED_NEXT", {"minutes": maxi(1, roundi(next / 60.0))})
	return text


## --qa-tea=<state>: the Tea sheet open in a mid-interaction state (see the header).
static func _qa_open(state: String) -> void:
	var h := _wired_hud
	if h == null or not is_instance_valid(h):
		return
	if state == "simple":
		Settings.set_value(Settings.SIMPLE_BREWING, true)
	h.open_sheet(&"tea", true)
	var s := h.sheets.current as TeaSheet
	if s == null:
		return
	for i in 3:
		await h.get_tree().process_frame
	if not is_instance_valid(s):
		return
	s.qa_state(state)


## Puts the open sheet into QA state [param state] (also used by tests).
func qa_state(state: String) -> void:
	match state:
		"recipes":
			select_tab(TAB_RECIPES, false)
		"teaware":
			select_tab(TAB_TEAWARE, false)
		"drag":
			var j := pot.jar_flowers.find(&"sweet_clover")
			var from := pot.jar_rect(maxi(j, 0)).get_center()
			pot.press(from)
			pot.move(from + Vector2(0.0, -40.0))
			pot.move(pot.stir_centre() + Vector2(150.0, -40.0))
			pot.qa_freeze = true
		"stir":
			Game.pot_stir(180.0)
			pot.refresh()
			var c := pot.stir_centre()
			var r := 260.0
			pot.press(c + Vector2(r, 0.0))
			for k in 12:
				var a := TAU * float(k + 1) / 24.0
				pot.move(c + Vector2(cos(a), sin(a)) * r)
			pot.qa_freeze = true
		"pour":
			_qa_stir_full()
			pot.pour()
			pot.qa_advance(float(ContentRegistry.content.tea["brewing"]["pour_ms"]) * UiTokens.MS * 0.52)
			pot.qa_freeze = true
		"reveal":
			# a recipe still to find, so the card wears "A new recipe!"
			while not (Game.pot().get("petals", []) as Array).is_empty():
				Game.pot_remove(0)
			Game.pot_add_petal(&"buttercup")
			Game.pot_add_petal(&"buttercup")
			_qa_stir_full()
			pot.pour()
			pot.qa_advance(float(ContentRegistry.content.tea["brewing"]["pour_ms"]) * UiTokens.MS + 0.05)
			if _reveal != null:
				_reveal.modulate.a = 1.0
				_reveal.scale = Vector2.ONE
			_reveal_t = -INF
			pot.qa_freeze = true
		"offer":
			open_offer(0)
		"simple":
			pot.simple = true
			pot.refresh()


func _qa_stir_full() -> void:
	for k in 3:
		Game.pot_stir(180.0)
	pot.refresh()
