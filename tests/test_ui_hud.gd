extends GutTest
## The UI layer (Art Bible §9, §10.3; GDD §7.6, §8; I1-I3, X1-X2): the HUD and dock land on the
## §9.5 wireframe px (and mirror when left-handed), every target is >= 48 dp, every text/backdrop
## pair the UI can draw meets WCAG AA (including ink over the live glass at its adaptive tint over
## the worst backdrops, A7), the duotone icon set is complete and recolourable, touch-down gives
## a visual change in the same frame, the sheets open/close/swap one at a time with a Back handler,
## Settings rows write through Settings, the dew counter formats per language and the recap card
## lists its lines.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const SEED := 4242
const SCREEN := Vector2(1080, 1920)
const SAFE_TOP := 72.0
const SAFE_BOTTOM := 127.0
const MIN_TARGET_PX := 144.0
const AA := 4.5
const AA_LARGE_ICON := 3.0
## Every icon the UI code asks for (Art Bible §9.3 set as used).
const ICONS: Array[StringName] = [&"dew", &"watch", &"watch_closed", &"garden", &"album", &"basket", &"settings",
	&"close", &"back", &"heart", &"heart_empty", &"sun", &"moon", &"dawn", &"golden", &"dusk", &"cloud", &"breeze",
	&"rain", &"postcard", &"check", &"plus", &"minus", &"music", &"haptics", &"motion", &"transparency",
	&"text_size", &"mono", &"hand", &"language", &"photo", &"pencil", &"sparkle",
	&"gear", &"dock_garden", &"dock_garden_sleep", &"dock_basket", &"dock_basket_sleep", &"dock_basket_1",
	&"dock_basket_2", &"dock_basket_3", &"dock_album", &"sleep_z"]

var c: GameContent
var _saved_sim: WorldSim
var _saved_ready: bool
var _saved_content: GameContent
var _saved_persist: bool
var _saved_settings: Dictionary = {}


func before_all() -> void:
	c = ContentRegistry.content


func before_each() -> void:
	_saved_sim = Game.sim
	_saved_ready = Game.is_ready
	_saved_content = Game.content
	Game.content = c
	_saved_persist = Settings.persist
	Settings.persist = false
	for k: StringName in [Settings.LEFT_HANDED, Settings.REDUCE_MOTION, Settings.MONO, Settings.TEXT_SCALE]:
		_saved_settings[k] = Settings.get_value(k)
	Game.sim = WorldSim.new_game(c, SEED, Clock.now_unix(), 0.0)
	Game.is_ready = true


func after_each() -> void:
	for k: StringName in _saved_settings:
		Settings.set_value(k, _saved_settings[k])
	Settings.persist = _saved_persist
	Game.sim = _saved_sim
	Game.is_ready = _saved_ready
	Game.content = _saved_content


# ------------------------------------------------------------------ layout (Art Bible §9.5)

func test_top_bar_matches_wireframe() -> void:
	var top := TopBarView.new()
	add_child_autofree(top)
	top.layout(SCREEN, SAFE_TOP)
	assert_eq(Rect2(top.gear.position, top.gear.size), Rect2(0, 144, 216, 216),
			"Settings gear: chip 48..168, hit 0..216 x 144..360 (72 dp), round 6")
	assert_eq(top.dew_chip.position, Vector2(192, 144), "dew chip beside the gear at x 192, y = T 120 + 24")
	assert_eq(top.time_chip.position, Vector2(768, 144), "time chip x 768..888")
	assert_eq(top.time_chip.size, Vector2(120, 120))
	var eye := Rect2(top.eye.position, top.eye.size)
	assert_eq(eye, Rect2(864, 144, 216, 216), "eye hit 864..1080 x 144..360 (72 dp)")
	top.left_handed = true
	top.layout(SCREEN, SAFE_TOP)
	assert_eq(top.eye.position.x + TopBarView.EYE_HIT_PAD_X, 48.0, "left-handed: eye at x 48")
	assert_almost_eq(top.gear.position.x + TopBarView.EYE_HIT_PAD_X, 912.0, 0.5, "left-handed: gear at x 912")
	assert_almost_eq(top.dew_chip.position.x + top.dew_chip.size.x, 888.0, 0.5, "dew chip right-aligned to 888")


func test_time_peek_stops_short_of_the_dew_chip() -> void:
	var top := TopBarView.new()
	add_child_autofree(top)
	top.dew_chip.visible = true
	top.layout(SCREEN, SAFE_TOP)
	top.call(&"_set_peek", 2000.0)
	var dew_end := top.dew_chip.position.x + top.dew_chip.size.x
	assert_true(top.time_chip.position.x >= dew_end + TopBarView.GAP - 0.5, "peek clamps before the dew chip")
	assert_eq(top.time_chip.position.x + top.time_chip.size.x, 888.0, "the time chip keeps its right edge")


func test_dock_matches_wireframe_and_mirrors() -> void:
	var dock := DockView.new()
	add_child_autofree(dock)
	dock.layout(SCREEN, SAFE_BOTTOM)
	# Round 6: a floating pebble 132..948 x 1553..1757 (68 dp tall, 36 px above the 127 px inset).
	assert_eq(dock.pill_rect(), Rect2(132, 1553, 816, 204), "dock pebble")
	assert_eq(DockView.ORDER, [&"album", &"garden", &"basket"] as Array[StringName], "three destinations")
	assert_null(dock.button(&"settings"), "Settings lives in the top bar now")
	var centres := {&"album": 270.0, &"garden": 540.0, &"basket": 810.0}
	for id: StringName in centres:
		var b := dock.button(id)
		assert_almost_eq(b.position.x + b.center().x, float(centres[id]), 0.01, "centre of %s" % id)
		assert_true(b.size.x >= 228.0 and b.size.y >= 228.0, "%s hit >= 76 dp" % id)
		assert_true(b.position.y <= 1553.0 and b.position.y + b.size.y >= 1757.0, "%s hit covers the pebble" % id)
	var hero := dock.button(&"garden")
	assert_gt(hero.icon_px, dock.button(&"basket").icon_px, "Garden is the larger hero")
	assert_true(dock.top() < dock.pill_rect().position.y, "the hero plate pokes above the pebble")
	assert_true(hero.position.y <= dock.top(), "... and its hit covers the plate")
	dock.left_handed = true
	dock.layout(SCREEN, SAFE_BOTTOM)
	var basket := dock.button(&"basket")
	assert_almost_eq(basket.position.x + basket.center().x, 270.0, 0.01, "left-handed order reversed")
	var album := dock.button(&"album")
	assert_almost_eq(album.position.x + album.center().x, 810.0, 0.01)


func test_dock_tab_hits_do_not_overlap_and_the_pebble_takes_its_presses() -> void:
	var dock := DockView.new()
	add_child_autofree(dock)
	dock.layout(SCREEN, SAFE_BOTTOM)
	var rects: Array[Rect2] = []
	for id: StringName in DockView.ORDER:
		rects.append(Rect2(dock.button(id).position, dock.button(id).size))
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			assert_false(rects[i].intersection(rects[j]).has_area(), "tab hits do not overlap")
	assert_eq(dock.pill.mouse_filter, Control.MOUSE_FILTER_STOP, "the pebble consumes its presses (WorldPan)")
	assert_true(dock.input_controls().has(dock.pill), "ambient watch turns the pebble off too")
	# round 7 (owner: "I often mis-tap the dock"): the tabs tile the pebble edge to edge, no dead gap
	var order: Array[Rect2] = []
	for i in DockView.ORDER.size():
		var b := dock.button(dock._id_at(i))
		order.append(Rect2(b.position, b.size))
	var pill := dock.pill_rect()
	assert_almost_eq(order[0].position.x, pill.position.x, 0.01, "the first tab starts at the pebble's edge")
	assert_almost_eq(order[2].end.x, pill.end.x, 0.01, "the last tab ends at the pebble's edge")
	for i in 2:
		assert_almost_eq(order[i].end.x, order[i + 1].position.x, 0.01, "tabs %d/%d are contiguous" % [i, i + 1])
	for r: Rect2 in order:
		assert_true(r.size.x >= 76.0 * 3.0 and r.size.y >= 76.0 * 3.0, "dock hit >= 76 dp (%s)" % r)
		assert_almost_eq(r.end.y, dock.guard.position.y, 0.01, "tabs reach down to the gesture guard")
	assert_eq(dock.guard.mouse_filter, Control.MOUSE_FILTER_STOP, "the gesture-bar inset eats its presses")
	assert_almost_eq(dock.guard.size.y, maxf(SAFE_BOTTOM, DockView.BOTTOM_MIN), 0.01)
	assert_almost_eq(dock.guard.position.y + dock.guard.size.y, SCREEN.y, 0.01)


func test_dock_labels_fit_their_tab() -> void:
	var dock := DockView.new()
	add_child_autofree(dock)
	dock.layout(SCREEN, SAFE_BOTTOM)
	for id: StringName in DockView.ORDER:
		var b := dock.button(id)
		var font := b.label.get_theme_font(&"font")
		var w := font.get_string_size(b.label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				b.label.get_theme_font_size(&"font_size")).x
		assert_true(w <= b.plate_px - DockView.LABEL_PAD * 2.0 + 0.5, "%s label fits its tab" % id)
		assert_eq(b.label.theme_type_variation, &"DockLabel", "Baloo 2 dock label")


func test_dock_bubble_follows_the_open_sheet() -> void:
	var dock := DockView.new()
	add_child_autofree(dock)
	dock.layout(SCREEN, SAFE_BOTTOM)
	dock.set_active(&"basket")
	dock.snap_active()
	var b := dock.button(&"basket")
	assert_almost_eq(dock.cap_x, b.position.x + b.icon_center().x, 0.01, "bubble behind the Basket icon")
	assert_almost_eq(dock.cap_y, b.position.y + b.icon_center().y, 0.01)
	assert_eq(dock.cap_a, 1.0)
	assert_true(b.active)
	dock.set_active(&"settings")
	dock.snap_active()
	assert_eq(dock.cap_a, 0.0, "Settings (top bar) selects no tab")
	assert_false(b.active)
	dock.set_active(&"")
	dock.snap_active()
	assert_eq(dock.cap_a, 0.0, "no sheet: no bubble")


func test_basket_shows_fill_without_a_count() -> void:
	var dock := DockView.new()
	add_child_autofree(dock)
	dock.layout(SCREEN, SAFE_BOTTOM)
	dock.set_basket_count(0)
	assert_eq(dock.icon_for(&"basket"), &"dock_basket")
	dock.set_basket_count(3)
	assert_eq(dock.icon_for(&"basket"), &"dock_basket_1", "a dew drop peeks out")
	dock.set_basket_count(9)
	assert_eq(dock.icon_for(&"basket"), &"dock_basket_2", "+ a bloom")
	dock.set_basket_count(24)
	assert_eq(dock.icon_for(&"basket"), &"dock_basket_3", "brimming")
	for n: Node in dock.find_children("*", "Label", true, false):
		assert_false((n as Label).text.is_valid_int(), "no numeric badge anywhere in the dock")


func test_asleep_tabs_stay_in_full_colour() -> void:
	var dock := DockView.new()
	add_child_autofree(dock)
	dock.layout(SCREEN, SAFE_BOTTOM)
	for id: StringName in DockView.ORDER:
		dock.set_asleep(id, true)
		var b := dock.button(id)
		assert_eq(b.icon_node().modulate.a, 1.0, "%s icon not greyed" % id)
		assert_eq(b.label.modulate.a, 1.0, "%s label not greyed" % id)
		assert_eq(b.mouse_filter, Control.MOUSE_FILTER_STOP, "%s still tappable" % id)
	assert_eq(dock.icon_for(&"garden"), &"dock_garden_sleep", "sleepy closed-eye pot")
	dock.set_asleep(&"garden", false)
	assert_eq(dock.icon_for(&"garden"), &"dock_garden")


func test_new_marks_are_sparkles() -> void:
	var dock := DockView.new()
	add_child_autofree(dock)
	dock.layout(SCREEN, SAFE_BOTTOM)
	dock.set_new(&"album", true)
	assert_true(dock.has_new(&"album"))
	dock.set_active(&"album")
	assert_false(dock.has_new(&"album"), "opening the Album clears its sparkle")


func test_sheet_rect_sits_above_the_dock() -> void:
	var host := SheetHost.new()
	add_child_autofree(host)
	host.layout(SCREEN, 1541.0)
	assert_eq(host.sheet_rect(), Rect2(24, 442, 1032, 1075), "sheet 24..1056 x 442..1517 at H 1920")
	host.layout(Vector2(1080, 2400), 2021.0)
	assert_eq(host.sheet_rect().size.y, roundf(SheetHost.TALL_FRAC * 2400.0),
			"20:9: the medium detent is 0.66 H (round 6)")
	assert_eq(host.sheet_rect().end.y, 1997.0, "bottom = dock top - 24")


# ------------------------------------------------------------------ targets (I2)

func test_every_ui_target_is_at_least_48_dp() -> void:
	var dock := DockView.new()
	add_child_autofree(dock)
	dock.layout(SCREEN, SAFE_BOTTOM)
	for b: Variant in dock.buttons.values():
		var r := b as Control
		assert_true(r.size.x >= MIN_TARGET_PX and r.size.y >= MIN_TARGET_PX, "dock target")
	var top := TopBarView.new()
	add_child_autofree(top)
	top.layout(SCREEN, SAFE_TOP)
	assert_true(top.gear.size.x >= 216.0 and top.gear.size.y >= 216.0, "Settings gear hit >= 72 dp")
	assert_true(UiSheet.CLOSE_HIT >= MIN_TARGET_PX, "sheet close hit")
	assert_true(UiSheet.CARD_BUTTON_H >= MIN_TARGET_PX, "card buttons")
	assert_true(Segmented.HEIGHT + Segmented.HIT_GROW * 2.0 >= MIN_TARGET_PX, "segmented hit")
	assert_true(UiSlider.MIN_H >= MIN_TARGET_PX, "slider row")
	assert_true(SettingsSheet.ROW_H >= MIN_TARGET_PX and SettingsSheet.STEP_HIT >= MIN_TARGET_PX, "settings rows")
	assert_true(TopBarView.EYE_HIT.x >= MIN_TARGET_PX, "eye")


# ------------------------------------------------------------------ contrast (X2, A7)

func test_text_pairs_meet_wcag_aa() -> void:
	var ink := UiTokens.color(&"ink")
	var ink_2 := UiTokens.color(&"ink_2")
	var hi := UiTokens.color(&"surface_hi")
	var pairs := [
		[ink, hi, "ink on surface_hi"], [ink, UiTokens.color(&"surface"), "ink on surface"],
		[ink_2, hi, "ink_2 on surface_hi"], [hi, UiTokens.color(&"primary"), "surface_hi on primary"],
		[hi, UiTokens.color(&"primary_pressed"), "surface_hi on primary_pressed"],
		[ink, UiTokens.color(&"coral"), "badge count on coral"], [ink, UiTokens.color(&"gold_tint"), "price on gold_tint"],
		[ink_2, UiTokens.color(&"gold_tint"), "unaffordable price on gold_tint"],
		[ink, UiTokens.color(&"primary_tint"), "ink on primary_tint"],
		[ink, UiTokens.color(&"coral_tint"), "ink on coral_tint"],
	]
	for p: Array in pairs:
		assert_true(UiTokens.contrast(p[0], p[1]) >= AA, "%s: %.2f" % [p[2], UiTokens.contrast(p[0], p[1])])


## Faux glass (0.84 surface) and the live glass's adaptive tint over a sweep of backdrops from
## black to white and saturated hues: ink must stay >= 4.5:1 everywhere (Art Bible §4.17 A7).
func test_ink_on_glass_over_worst_backdrops() -> void:
	var ink := UiTokens.color(&"ink")
	var surface := UiTokens.color(&"surface")
	var faux := UiTokens.alpha(&"glass_faux_fill")
	var ad := UiTokens.alpha_section(&"glass_live_adaptive")
	var worst := INF
	var backdrops: Array[Color] = []
	for i in 21:
		var g := float(i) / 20.0
		backdrops.append(Color(g, g, g))
	backdrops.append_array([Color("#1B1A2E"), Color("#4A6FD6"), Color("#256F5C"), Color("#FF9A7A"), Color("#6F4A8E")])
	for b: Color in backdrops:
		worst = minf(worst, UiTokens.contrast(ink, b.lerp(surface, faux)))
		var l := 0.2126 * b.r + 0.7152 * b.g + 0.0722 * b.b
		var tint := lerpf(float(ad["max"]), float(ad["min"]),
				smoothstep(float(ad["backdrop_luma_lo"]), float(ad["backdrop_luma_hi"]), l))
		worst = minf(worst, UiTokens.contrast(ink, b.lerp(surface, tint)))
	assert_true(worst >= AA, "ink on any glass >= 4.5:1 (worst %.2f)" % worst)


func test_icons_complete_duotone_and_recolourable() -> void:
	var ink := UiTokens.color(&"ink")
	for name: StringName in ICONS:
		assert_true(Icons.exists(name), "icon %s exists" % name)
		var tex := Icons.texture(name, 72.0)
		assert_not_null(tex, "icon %s rasterises" % name)
		if tex != null:
			assert_eq(tex.get_size(), Vector2(72, 72), "icon %s at 72 px" % name)
		var src := FileAccess.get_file_as_string(Icons.DIR + String(name) + ".svg")
		assert_false(src.contains("<text"), "no SVG <text> in %s" % name)
		assert_false(src.contains("filter"), "no filters in %s" % name)
	assert_true(UiTokens.contrast(ink, UiTokens.color(&"surface")) >= AA_LARGE_ICON, "icon ink >= 3:1")
	var big := Icons.texture(&"garden", 168.0)
	assert_eq(big.get_size(), Vector2(168, 168), "icons re-rasterise per size (crisp at any scale)")
	var active := Icons.texture(&"garden", 72.0, true) as DPITexture
	assert_true(active.get_source().contains(Icons.ACCENT_ACTIVE), "active variant lifts the accent to 100 %")


func test_dock_icons_and_labels_pass_contrast_over_the_worst_backdrops() -> void:
	var di: Dictionary = ContentRegistry.palettes()["dock_icon"]
	var outline := Color.html(String(di["outline"]))
	var outline_night := Color.html(String(di["outline_night"]))
	var fill := GlassPanel.HUD_FILL
	var night_fill := float(GlassPanel.night_tokens().get("fill", 0.88))
	for backdrop: Color in [Color.BLACK, Color.WHITE, Color("#1E3A2A"), Color("#7FB8E8")]:
		var glass := backdrop.lerp(UiTokens.color(&"hud_glass"), fill)
		assert_true(UiTokens.contrast(outline, glass) >= AA_LARGE_ICON, "dock icon outline on day glass over %s" % backdrop)
		assert_true(UiTokens.contrast(UiTokens.color(&"ink"), glass) >= AA, "dock label on day glass over %s" % backdrop)
		var ng := backdrop.lerp(UiTokens.color(&"night_glass"), night_fill)
		assert_true(UiTokens.contrast(outline_night, ng) >= AA_LARGE_ICON, "night icon edge over %s" % backdrop)
		assert_true(UiTokens.contrast(UiTokens.color(&"night_ink"), ng) >= AA, "night label over %s" % backdrop)
	for token: StringName in [&"bubble_leaf", &"bubble_gold", &"bubble_coral"]:
		assert_true(UiTokens.contrast(UiTokens.color(&"ink"), UiTokens.color(token)) >= AA, "label on %s" % token)
		assert_true(UiTokens.contrast(outline, UiTokens.color(token)) >= AA_LARGE_ICON, "icon on %s" % token)
	var src := FileAccess.get_file_as_string(Icons.DIR + "dock_garden.svg")
	assert_true(src.contains(String(di["outline"])), "dock icons draw their outline in dock_icon.outline")
	var night_src := Icons.variant_source(src, false, true)
	assert_true(night_src.contains(String(di["outline_night"])), "night variant: cream sticker edge")


# ------------------------------------------------------------------ touch (I1, Art Bible §10.3)

func test_touch_down_changes_the_control_in_the_same_frame() -> void:
	var b := RoundButton.new()
	b.size = Vector2(228, 228)
	b.icon_name = &"garden"
	PressFeedback.attach(b)
	add_child_autofree(b)
	b.button_down.emit()
	assert_true(b.modulate.r > 1.0, "instant tint lift on touch-down")
	await wait_seconds(0.12)
	assert_true(b.scale.x < 0.99, "scales toward press_scale within ~100 ms (got %.3f)" % b.scale.x)
	b.button_up.emit()
	await wait_seconds(0.6)
	assert_almost_eq(b.scale.x, 1.0, 0.01, "springs back to 1 on release (pop)")


# ------------------------------------------------------------------ sheets (GDD §8.1)

func test_sheets_open_close_swap_one_at_a_time_with_back() -> void:
	var host := SheetHost.new()
	host.factory = func(id: StringName) -> UiSheet:
		var s := UiSheet.new()
		s.title_key = String(id)
		return s
	add_child_autofree(host)
	host.layout(SCREEN, 1541.0)
	host.open(&"garden", true)
	assert_eq(host.current_id, &"garden")
	assert_true(host.current.is_live(), "the open sheet is the live glass")
	host.toggle(&"album", true)
	assert_eq(host.current_id, &"album", "another dock button swaps")
	var sheets := host.get_children().filter(func(n: Node) -> bool: return n is UiSheet and not n.is_queued_for_deletion())
	assert_eq(sheets.size(), 1, "exactly one sheet")
	Game.handle_back()
	assert_false(host.is_open(), "Back closes the top sheet")
	host.toggle(&"basket", true)
	host.toggle(&"basket", true)
	assert_false(host.is_open(), "the same dock button closes it")


func test_settings_rows_write_through_settings() -> void:
	Settings.set_value(Settings.MONO, false)
	var s := SettingsSheet.new()
	s.size = Vector2(1032, 1075)
	add_child_autofree(s)
	await wait_frames(2)
	var toggles: Array[Node] = s.find_children("*", "UiToggle", true, false)
	assert_true(toggles.size() >= 7, "every on/off setting has a switch")
	var segs: Array[Node] = s.find_children("*", "Segmented", true, false)
	assert_eq(segs.size(), 3, "music, haptics, language")
	var sliders: Array[Node] = s.find_children("*", "UiSlider", true, false)
	assert_eq(sliders.size(), 3, "three volumes")
	var mono_row: Button = null
	for t: Node in toggles:
		var row := t.get_parent().get_parent().get_parent().get_parent() as PanelContainer
		var labels: Array[Node] = row.find_children("*", "Label", true, false)
		if not labels.is_empty() and (labels[0] as Label).text == tr("SET_MONO"):
			mono_row = row.get_child(0) as Button
	assert_not_null(mono_row, "mono row found")
	if mono_row != null:
		mono_row.pressed.emit()
		assert_true(Settings.get_bool(Settings.MONO), "the whole row toggles the setting")


# ------------------------------------------------------------------ copy

func test_dew_counter_formats_per_language() -> void:
	var was := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	assert_eq(TopBarView.format_dew(12345), "12,345")
	assert_eq(TopBarView.format_dew(7), "7")
	TranslationServer.set_locale("vi")
	assert_eq(TopBarView.format_dew(99999), "99.999")
	TranslationServer.set_locale(was)


func test_recap_card_lists_lines_with_names() -> void:
	var o := OverlayHost.new()
	add_child_autofree(o)
	o.layout(SCREEN, Rect2(48, 72, 48, 127))
	o.show_recap([{"key": &"RECAP_ONE_VISITED", "species": &"puffmoss"}, {"key": &"RECAP_GIFTS", "species": &""}], true)
	assert_true(o.is_modal_open())
	var texts := PackedStringArray()
	for l: Node in o.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	var joined := " | ".join(texts)
	assert_string_contains(joined, Game.display_name(&"puffmoss"))
	assert_string_contains(joined, tr("RECAP_GIFTS"))
	o.close_modal(true)
	assert_false(o.is_modal_open())


# ------------------------------------------------------------------ clues (round 10)

## GDD §13.3.3: a found clue says what it was; where clues go is explained once, on the first one,
## and the note skips the toast entirely because it earns the riddle card.
func test_a_found_clue_says_what_it_was_and_explains_itself_only_once() -> void:
	var first := HudController.clue_line({"sign": "footprints"}, 1)
	assert_string_contains(first, tr("CLUE_FOUND_TITLE"))
	assert_string_contains(first, tr("CLUE_FOUND_FOOTPRINTS"))
	assert_string_contains(first, tr("CLUE_ADDED"), "the first clue says where it went")
	var later := HudController.clue_line({"sign": "rustle"}, 4)
	assert_string_contains(later, tr("CLUE_FOUND_RUSTLE"))
	assert_false(later.contains(tr("CLUE_ADDED")), "and never explains itself again")
	assert_eq(HudController.clue_line({"sign": "note"}, 9), "", "the note opens the riddle instead")
	for kind: String in ["footprints", "dropped", "rustle"]:
		var line := HudController.clue_line({"sign": kind}, 9)
		assert_false(line.contains("CLUE_FOUND_"), "%s has a written line, not a key: '%s'" % [kind, line])


func test_the_riddle_card_reads_the_note_back_and_closes() -> void:
	var o := OverlayHost.new()
	add_child_autofree(o)
	o.layout(SCREEN, Rect2(48, 72, 48, 127))
	o.show_riddle({"sign": "note", "riddle_key": "RIDDLE_CAPLING", "mystery": &"capling"}, true)
	assert_true(o.is_modal_open(), "the note stops the player, gently")
	var texts := PackedStringArray()
	for l: Node in o.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	var joined := " | ".join(texts)
	assert_string_contains(joined, tr("CLUE_FOUND_TITLE"))
	assert_string_contains(joined, tr("RIDDLE_CAPLING"), "the riddle itself, not its key")
	var done: Button = null
	for b: Node in o.find_children("*", "Button", true, false):
		if (b as Button).text == tr("COMMON_DONE"):
			done = b as Button
	assert_not_null(done, "one way out, and it is a 48 dp pill")
	assert_true(done.size.y >= MIN_TARGET_PX or done.custom_minimum_size.y >= MIN_TARGET_PX)
	done.pressed.emit()
	o.close_modal(true)
	assert_false(o.is_modal_open())
