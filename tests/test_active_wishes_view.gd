extends GutTest
## Active F1 Wishes front-end (GDD §14.11 b FE-W, docs/gdd/ACTIVE_WISHES.md §7-§9): the icon atlas
## covers every wish, every wish string fills every placeholder for every friend in both
## languages, the delight poses map and settle within the celebrate token, the bubble's life cycle
## (fade in, wait dim, tuck, pop, free) in one CanvasItem, and the live creature layer on the
## active_mid world: bubbles only for open wishes of present friends (<= 2), the tap caption, the
## grant pop + pose, the game-of-tag tap rule and the busy report; the Album's wish section and the
## wish list card.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const SEED := 4242
const LAYER_SCENE := "res://scenes/creatures/creature_layer.tscn"
const LOCALES: Array[String] = ["en", "vi"]

var c: GameContent
var _saved_sim: WorldSim
var _saved_ready: bool
var _saved_content: GameContent
var _saved_locale: String
var _saved_persist: bool


func before_all() -> void:
	c = ContentRegistry.content


func before_each() -> void:
	_saved_sim = Game.sim
	_saved_ready = Game.is_ready
	_saved_content = Game.content
	_saved_locale = TranslationServer.get_locale()
	_saved_persist = Settings.persist
	Settings.persist = false
	Game.content = c


func after_each() -> void:
	TranslationServer.set_locale(_saved_locale)
	Settings.persist = _saved_persist
	Game.sim = _saved_sim
	Game.is_ready = _saved_ready
	Game.content = _saved_content


## The active_mid world (garden_mid + friends, two open wishes and one held) as Game.sim.
func _active_world() -> WorldSim:
	var st := WorldSim.new_game(c, SEED, Clock.now_unix(), 0.0).state
	GardenFixture.apply(c, st, GardenFixture.MID)
	var sim := WorldSim.new(c, st)
	ActiveFixture.apply(sim)
	sim = WorldSim.new(c, st)
	sim.drain_events()
	Game.sim = sim
	Game.is_ready = true
	return sim


func _layer() -> CreatureLayer:
	var l: CreatureLayer = (load(LAYER_SCENE) as PackedScene).instantiate()
	add_child_autofree(l)
	return l


func _names() -> Callable:
	return func(sp: StringName) -> String: return "N_" + String(sp)


# ------------------------------------------------------------------ art and copy (pure)

func test_every_wish_icon_has_its_own_atlas_art() -> void:
	var ids := WishIcons.all_icon_ids()
	for w: Dictionary in c.wishes:
		var icon := StringName(String(w["icon"]))
		assert_true(ids.has(icon), "%s: icon %s is drawn in the atlas" % [w["id"], icon])
		assert_eq(WishIcons.resolve(icon), icon, "%s resolves to itself" % icon)
	for f: Dictionary in c.flowers:
		assert_true(ids.has(StringName("flower:%s" % f["id"])), "flower %s has an icon" % f["id"])
	assert_eq(WishIcons.resolve(&"nonsense"), WishIcons.FALLBACK, "an unknown icon falls back softly")


func test_atlas_regions_are_disjoint_and_inside_the_texture() -> void:
	var regions: Dictionary = WishIcons.atlas()["regions"]
	var tex := WishIcons.texture()
	assert_not_null(tex, "the atlas texture exists")
	var all: Array = regions.values()
	for i in all.size():
		var a: Rect2 = all[i]
		assert_true(a.size.x > 0.0 and a.size.y > 0.0, "region %d has a size" % i)
		for j in range(i + 1, all.size()):
			assert_false(a.intersects(all[j] as Rect2), "regions %d and %d do not overlap" % [i, j])
	for k: StringName in [WishIcons.BUBBLE, WishIcons.STAMP, WishIcons.PETAL, WishIcons.SLEEP_Z]:
		assert_true(regions.has(k), "%s is in the atlas" % k)


func test_every_wish_string_fills_its_placeholders() -> void:
	for loc: String in LOCALES:
		TranslationServer.set_locale(loc)
		for w: Dictionary in c.wishes:
			var wish := StringName(String(w["id"]))
			for s: Dictionary in c.species:
				var sp := StringName(String(s["id"]))
				for text: String in [WishText.title(c, wish, sp, _names()), WishText.hint(c, wish, sp, _names()),
						WishText.tag(c, wish, sp, _names()),
						WishText.a11y(c, &"A11Y_WISH_LIST_ROW", wish, sp, _names()),
						WishText.a11y(c, &"A11Y_WISH_BUBBLE", wish, sp, _names())]:
					assert_false(text.contains("{") or text.contains("}"), "%s/%s/%s: %s" % [loc, wish, sp, text])
					assert_ne(text, "", "%s/%s/%s has copy" % [loc, wish, sp])


func test_tag_reads_name_dot_wish() -> void:
	TranslationServer.set_locale("en")
	assert_eq(WishText.tag(c, &"cuddle", &"puffmoss", _names()), "N_puffmoss · A cuddle")


func test_grant_toasts_fill_their_placeholders() -> void:
	for loc: String in LOCALES:
		TranslationServer.set_locale(loc)
		var args := WishText.args(c, &"puffmoss", _names())
		for gift: StringName in [&"", &"sweet_clover"]:
			for arrival: bool in [false, true]:
				var t := WishView.grant_toast_text(&"puffmoss", gift, arrival, args)
				assert_false(t.contains("{"), "%s toast: %s" % [loc, t])
				assert_true(t.contains("N_puffmoss"), "the toast names the friend")


func test_every_granted_pose_has_a_delight_that_settles() -> void:
	var pres: Dictionary = c.wishes_doc["presentation"]
	var granted_ms := float(pres["granted_ms"])
	var dur: Dictionary = c.motion["durations_ms"]
	assert_true(granted_ms <= float(dur["celebrate_max_input_block"]), "the delight fits the celebrate token")
	for w: Dictionary in c.wishes:
		var pose := StringName(String(w["granted_pose"]))
		assert_true(DelightPose.MOTION.has(pose), "%s: granted_pose %s is mapped (D15)" % [w["id"], pose])
		var m := DelightPose.motion_of(pose)
		assert_almost_eq(DelightPose.lift_bu(m, 1.0), 0.0, 1e-4, "%s lands" % pose)
		assert_almost_eq(DelightPose.wiggle(m, 0.9, 1.0), 0.0, 1e-4, "%s stops swaying" % pose)
		for i in 11:
			assert_true(DelightPose.lift_bu(m, float(i) / 10.0) >= 0.0, "%s never sinks" % pose)
	assert_true(DelightPose.MOTION.has(&"sip_tea"), "FE-T's sip_tea pose exists")


# ------------------------------------------------------------------ the bubble

func test_bubble_life_cycle_in_one_canvas_item() -> void:
	var b := WishBubble.new()
	add_child_autofree(b)
	b.setup(&"wish_heart", 0.3, false)
	assert_eq(b.phase, WishBubble.Phase.IN)
	assert_eq(b.get_child_count(), 0, "one CanvasItem draws cloud, icon and petals (1 draw call)")
	assert_eq(b.z_index, WishBubble.BUBBLE_Z)
	for i in 40:
		b._process(0.05)
	assert_eq(b.phase, WishBubble.Phase.IDLE, "faded in")
	assert_almost_eq(b.modulate.a, 1.0, 0.01)
	b.waiting = true
	for i in 40:
		b._process(0.05)
	var pres: Dictionary = c.wishes_doc["presentation"]
	assert_almost_eq(b.modulate.a, float(pres["napping_bubble_alpha"]), 0.01, "a waiting wish shows at 45 %")
	b.waiting = false
	b.tucked = true
	for i in 40:
		b._process(0.05)
	assert_almost_eq(b.modulate.a, 0.0, 0.01, "tucked under the name tag")
	b.tucked = false
	watch_signals(b)
	b.pop(Color.PINK)
	assert_true(b.is_leaving())
	b._process(0.1)
	assert_gt(b.pop_progress(), 0.0, "the pop runs")
	for i in 20:
		if is_instance_valid(b) and b.phase != WishBubble.Phase.GONE:
			b._process(0.05)
	assert_signal_emitted(b, "finished", "the bubble frees itself after the pop")


func test_bubble_is_not_a_world_target() -> void:
	var b := WishBubble.new()
	add_child_autofree(b)
	b.setup(&"wish_heart", 0.0, true)
	assert_false(b.is_in_group(WorldPan.GROUP_HIT), "the bubble never takes a press (§8.1)")
	assert_false(b.has_method(&"world_hit"))


# ------------------------------------------------------------------ the live layer

func test_bubbles_mirror_open_wishes_of_present_friends() -> void:
	var sim := _active_world()
	var l := _layer()
	await wait_process_frames(3)
	var want := WishView.visible_wishes()
	assert_eq(want.size(), 2, "active_mid shows two bubbles")
	assert_eq(l.wishes.bubble_count(), want.size(), "one bubble per open wish of a present friend")
	assert_true(l.wishes.bubble_of(&"puffmoss") != null)
	assert_true(l.wishes.bubble_of(&"buttonbud") != null)
	assert_null(l.wishes.bubble_of(&"dandelfluff"), "a held wish shows no bubble")
	assert_eq(l.wishes.bubble_of(&"puffmoss").icon, &"wish_teacup")
	assert_true(sim.state.wishes.size() == 3, "nothing changed in the sim")


func test_tap_shows_the_wish_caption_and_counts() -> void:
	_active_world()
	TranslationServer.set_locale("en")
	var l := _layer()
	await wait_process_frames(3)
	var m := l.mossling(&"puffmoss")
	assert_not_null(m)
	l._on_tapped(m)
	var tag := m.name_tag_text()
	assert_eq(tag.size(), 2, "the tag shows")
	assert_true(tag[0].contains("·") and tag[0].contains(Game.display_name(&"puffmoss")), "name · wish: %s" % tag[0])
	assert_ne(tag[1], "", "the hint line shows")
	await wait_process_frames(2)
	assert_true(l.wishes.bubble_of(&"puffmoss").tucked, "the bubble tucks under its caption")


func test_grant_pops_the_bubble_and_plays_the_pose() -> void:
	var sim := _active_world()
	var l := _layer()
	await wait_process_frames(3)
	var b := l.wishes.bubble_of(&"puffmoss")
	var got := l.wishes.qa_fulfil(&"puffmoss")
	assert_eq(got, [&"puffmoss"] as Array[StringName], "the clover cup grants the clover-tea wish")
	assert_true(is_instance_valid(b) and b.phase == WishBubble.Phase.POP, "the bubble pops")
	assert_null(l.wishes.bubble_of(&"puffmoss"), "no bubble while it pops")
	assert_eq(l.mossling(&"puffmoss").current_pose(), &"delight_sip", "the friend sips with delight")
	assert_true(Game.wish_of(&"puffmoss").is_empty(), "the wish was granted in the sim")
	assert_true(sim.state.wishes_granted > 6)


func test_game_of_tag_taps_never_open_the_card() -> void:
	var sim := _active_world()
	sim.state.wishes[0] = {"species": "puffmoss", "wish": "tag_game", "opened_t": sim.state.t, "state": "open",
		"taps": 0, "placed": false}
	var l := _layer()
	await wait_process_frames(3)
	watch_signals(l)
	var m := l.mossling(&"puffmoss")
	l._on_tapped(m)
	l._on_tapped(m)
	assert_signal_not_emitted(l, "card_requested", "a second tap counts for the game of tag")
	l._on_tapped(m)
	assert_true(Game.wish_of(&"puffmoss").is_empty(), "three taps grant the game of tag")
	l._last_tap.clear()
	l._on_tapped(m)
	l._on_tapped(m)
	assert_signal_emitted(l, "card_requested", "without the wish the second tap opens the card again")


func test_busy_friends_are_reported() -> void:
	_active_world()
	var l := _layer()
	await wait_process_frames(3)
	var m := l.mossling(&"buttonbud")
	m.debug_pose(&"asleep")
	await wait_process_frames(2)
	assert_true(Game.sim.active.wishes.busy.has("buttonbud"), "a napper starts no new wish")
	assert_true(l.wishes.bubble_of(&"buttonbud").waiting, "its wish waits at 45 %")
	assert_true(l.wishes.bubble_of(&"buttonbud").sleepy, "with a little z")


func test_edit_mode_dims_every_bubble() -> void:
	_active_world()
	var l := _layer()
	await wait_process_frames(3)
	Game.decor_edit_entered.emit()
	await wait_process_frames(2)
	for sp: StringName in [&"puffmoss", &"buttonbud"]:
		assert_true(l.wishes.bubble_of(sp).waiting, "%s waits while décor is arranged" % sp)
	Game.decor_edit_exited.emit()
	await wait_process_frames(2)
	assert_false(l.wishes.bubble_of(&"puffmoss").waiting)


# ------------------------------------------------------------------ Album

func _find(root: Node, node_name: String) -> Node:
	if root.name == node_name:
		return root
	for ch: Node in root.get_children():
		var hit := _find(ch, node_name)
		if hit != null:
			return hit
	return null


func test_album_detail_has_the_wish_section() -> void:
	_active_world()
	var v := VBoxContainer.new()
	add_child_autofree(v)
	WishAlbum.detail_section(v, &"puffmoss", v)
	assert_not_null(_find(v, "WishingRow"), "puffmoss holds a wish")
	assert_not_null(_find(v, "Visit"), "puffmoss is here: Say hello")
	assert_not_null(_find(v, "TeaLine"), "the tea nook is awake: the Tea line")
	var stamps := _find(v, "WishStamps")
	assert_not_null(stamps)
	assert_eq(Game.wish_stamps(&"puffmoss").size(), 2)
	var away := VBoxContainer.new()
	add_child_autofree(away)
	WishAlbum.detail_section(away, &"dandelfluff", away)
	assert_not_null(_find(away, "WishingRow"), "an away friend's held wish shows too")
	assert_null(_find(away, "Visit"), "no Say hello for a friend who is away")


func test_wish_list_chip_dot_and_card() -> void:
	_active_world()
	assert_true(Game.wish_list_unread(), "active_mid has a wish newer than the last look")
	var chip := WishAlbum.chip(func() -> void: pass)
	add_child_autofree(chip)
	assert_not_null(_find(chip, "UnreadDot"), "an unread dot (never a number)")
	var list := VBoxContainer.new()
	add_child_autofree(list)
	WishAlbum.build_list(list, list)
	assert_false(Game.wish_list_unread(), "opening the card clears the dot")
	var rows := 0
	for w: Dictionary in Game.wishes():
		if _find(list, "WishRow_%s" % w["species"]) != null:
			rows += 1
	assert_eq(rows, 3, "one row per pending wish (<= 4)")
	var chip2 := WishAlbum.chip(func() -> void: pass)
	add_child_autofree(chip2)
	assert_null(_find(chip2, "UnreadDot"))


func test_wish_list_empty_state() -> void:
	var sim := _active_world()
	sim.state.wishes.clear()
	var list := VBoxContainer.new()
	add_child_autofree(list)
	WishAlbum.build_list(list, list)
	assert_null(_find(list, "WishRow_puffmoss"), "no rows, the empty line instead")


# ------------------------------------------------------------------ polish (integration QA)

func test_album_wish_card_offers_tea_to_a_present_friend() -> void:
	_active_world()
	var v := VBoxContainer.new()
	add_child_autofree(v)
	WishAlbum.detail_section(v, &"puffmoss", v)
	var b := _find(v, "OfferTea") as Button
	assert_not_null(b, "the tea nook is awake and puffmoss is here: Offer tea")
	if b == null:
		return
	assert_eq(b.text, tr("ALBUM_OFFER_TEA"))
	assert_gte(b.custom_minimum_size.y, UiSheet.MIN_TARGET, ">= 48 dp target")
	assert_true(b.has_meta(TapGuard.META_WIRED), "TapGuard: slop, scroll-through and debounce")
	assert_ne(b.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_not_null(_find(v, "Visit"), "Say hello stays beside it")
	var away := VBoxContainer.new()
	add_child_autofree(away)
	WishAlbum.detail_section(away, &"dandelfluff", away)
	assert_null(_find(away, "OfferTea"), "no Offer tea for a friend who is away")
	Game.sim.state.tea_unlocked = false
	assert_false(WishAlbum.offer_tea_available(&"puffmoss"), "no Offer tea before the nook wakes")


func test_offer_tea_without_a_hud_does_nothing() -> void:
	_active_world()
	var v := VBoxContainer.new()
	add_child_autofree(v)
	WishAlbum.offer_tea(&"puffmoss", v)  # no HudController above: no sheet, no error
	assert_true(Game.wish_of(&"puffmoss").size() > 0, "nothing was offered")


func test_the_kept_note_shows_once() -> void:
	var sim := _active_world()
	sim.state.tips_seen.clear()
	WishAlbum._kept_shown.clear()
	var args := {"name": "Bơ"}
	var first := WishAlbum.held_note(&"dandelfluff", args)
	assert_eq(first, I18n.fmt(&"WISH_TIP_HELD", args), "the first time: the keeps-the-wish note")
	assert_true(Game.tip_seen(Game.TIP_WISH_KEPT), "remembered in tips_seen (saved)")
	assert_eq(WishAlbum.held_note(&"dandelfluff", args), first, "it keeps its place this run")
	WishAlbum._kept_shown.clear()  # a later session
	assert_eq(WishAlbum.held_note(&"dandelfluff", args), tr("WISH_LIST_AWAY"), "then the plain away line")
	WishAlbum._kept_shown.clear()


func test_a_tea_that_grants_a_wish_makes_one_toast() -> void:
	_active_world()
	var l := _layer()
	await wait_process_frames(3)
	WishView._tea_lines.clear()
	var got := l.wishes.qa_fulfil(&"puffmoss")
	assert_eq(got, [&"puffmoss"] as Array[StringName])
	await wait_process_frames(2)
	assert_true(WishView._tea_lines.has(&"puffmoss"), "the wish left its line for the tea toast (no toast of its own)")
	var res := {"reaction": TeaRules.REACT_LOVED, "wish_granted": "clover_tea", "petals_back": 0}
	var text := TeaSheet.merged_toast("ignored", res, &"puffmoss", "Bơ", "trà cỏ ba lá")
	assert_string_starts_with(text, I18n.fmt(&"TEA_REACT_LOVED", {"name": "Bơ", "recipe": "trà cỏ ba lá"}))
	assert_gt(text.length(), I18n.fmt(&"TEA_REACT_LOVED", {"name": "Bơ", "recipe": "trà cỏ ba lá"}).length() + 4,
		"the wish's thanks follows in the same toast")
	assert_false(WishView._tea_lines.has(&"puffmoss"), "taken once")
	assert_eq(TeaSheet.merged_toast("plain", {"wish_granted": ""}, &"puffmoss", "Bơ", "x"), "plain")


func test_recipe_names_read_naturally_mid_sentence() -> void:
	for loc: String in LOCALES:
		TranslationServer.set_locale(loc)
		for r: Dictionary in c.recipes:
			var id := StringName(String(r["id"]))
			var title := TeaArt.recipe_name(id)
			var mid := TeaArt.recipe_name_mid(id)
			assert_eq(mid.substr(1), title.substr(1), "only the first letter changes")
			assert_eq(mid.left(1), title.left(1).to_lower(), "%s %s: lower-case inside a sentence" % [loc, id])
	TranslationServer.set_locale("vi")
	var line := I18n.fmt(&"TEA_REACT_LOVED", {"name": "Bơ", "recipe": TeaArt.recipe_name_mid(&"sleepy_tea")})
	assert_false(line.contains("Trà"), "no capital T inside the sentence: %s" % line)
