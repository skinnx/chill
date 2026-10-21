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
	&"text_size", &"mono", &"hand", &"language", &"photo", &"pencil", &"sparkle"]

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
	assert_eq(top.dew_chip.position, Vector2(48, 144), "dew chip at x 48, y = T 120 + 24")
	assert_eq(top.time_chip.position, Vector2(768, 144), "time chip x 768..888")
	assert_eq(top.time_chip.size, Vector2(120, 120))
	var eye := Rect2(top.eye.position, top.eye.size)
	assert_eq(eye, Rect2(864, 144, 216, 216), "eye hit 864..1080 x 144..360 (72 dp)")
	top.left_handed = true
	top.layout(SCREEN, SAFE_TOP)
	assert_eq(top.eye.position.x + TopBarView.EYE_HIT_PAD_X, 48.0, "left-handed: eye at x 48")
	assert_almost_eq(top.dew_chip.position.x + top.dew_chip.size.x, 1032.0, 0.5, "dew chip right-aligned to 1032")


func test_dock_matches_wireframe_and_mirrors() -> void:
	var dock := DockView.new()
	add_child_autofree(dock)
	dock.layout(SCREEN, SAFE_BOTTOM)
	assert_eq(dock.pill_rect(), Rect2(24, 1541, 1032, 240), "dock pill 24..1056 x 1541..1781")
	var centres := {&"settings": 135.0, &"garden": 405.0, &"basket": 675.0, &"album": 945.0}
	for id: StringName in centres:
		var b := dock.button(id)
		assert_almost_eq(b.position.x + b.size.x * 0.5, float(centres[id]), 0.01, "centre of %s" % id)
		assert_almost_eq(b.position.y + b.size.y * 0.5, 1661.0, 0.01)
		assert_true(b.size.x >= DockView.HIT and b.size.y >= DockView.HIT, "dock hit 76 dp")
	dock.left_handed = true
	dock.layout(SCREEN, SAFE_BOTTOM)
	assert_almost_eq(dock.button(&"album").position.x + DockView.HIT * 0.5, 135.0, 0.01, "left-handed order reversed")
	assert_almost_eq(dock.button(&"settings").position.x + DockView.HIT * 0.5, 945.0, 0.01)


func test_sheet_rect_sits_above_the_dock() -> void:
	var host := SheetHost.new()
	add_child_autofree(host)
	host.layout(SCREEN, 1541.0)
	assert_eq(host.sheet_rect(), Rect2(24, 442, 1032, 1075), "sheet 24..1056 x 442..1517 at H 1920")
	host.layout(Vector2(1080, 2400), 2021.0)
	assert_eq(host.sheet_rect().size.y, roundf(0.56 * 2400.0), "height = round(0.56 H)")
	assert_eq(host.sheet_rect().end.y, 1997.0, "bottom = dock top - 24")


# ------------------------------------------------------------------ targets (I2)

func test_every_ui_target_is_at_least_48_dp() -> void:
	var dock := DockView.new()
	add_child_autofree(dock)
	dock.layout(SCREEN, SAFE_BOTTOM)
	for b: Variant in dock.buttons.values():
		var r := b as Control
		assert_true(r.size.x >= MIN_TARGET_PX and r.size.y >= MIN_TARGET_PX, "dock target")
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
