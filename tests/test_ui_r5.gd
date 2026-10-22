extends GutTest
## Round-5 UI contracts (QA r4 ui section): an open sheet draws by kind (one surface material,
## content layered above surfaces, same-font labels on one z), no per-item modulate inside a
## batch, the night scheme gives sheets / cards / modal cards a dim surface with AA text, the
## 200 % text setting really scales the dock labels (grid dock, icons never shrink) and the top
## bar, and the recap line reads as a whole sentence.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const SEED := 4242
const SCREEN := Vector2(1080, 1920)
const SAFE_BOTTOM := 127.0
const AA := 4.5
const AAA := 7.0
const TEXT_200 := 200
const RATIO_200 := 2.0

var c: GameContent
var _saved_sim: WorldSim
var _saved_ready: bool
var _saved_content: GameContent
var _saved_persist: bool
var _saved_scale: Variant


func before_all() -> void:
	c = ContentRegistry.content


func before_each() -> void:
	_saved_sim = Game.sim
	_saved_ready = Game.is_ready
	_saved_content = Game.content
	Game.content = c
	_saved_persist = Settings.persist
	Settings.persist = false
	_saved_scale = Settings.get_value(Settings.TEXT_SCALE)
	Game.sim = WorldSim.new_game(c, SEED, Clock.now_unix(), 0.0)
	Game.is_ready = true


func after_each() -> void:
	UiTokens.night_scheme = false
	Settings.set_value(Settings.TEXT_SCALE, _saved_scale)
	Settings.persist = _saved_persist
	Game.sim = _saved_sim
	Game.is_ready = _saved_ready
	Game.content = _saved_content


static func _abs_z(n: CanvasItem) -> int:
	return UiBatch._parent_abs(n) + n.z_index


static func _in_live_scene(n: Node, root: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != root:
		if UiBatch._is_opaque_scene(p):
			return true
		p = p.get_parent()
	return false


static func _leaves(root: Node, kind: Variant) -> Array[Node]:
	return root.find_children("*", kind, true, false)


func _album() -> AlbumSheet:
	var s := AlbumSheet.new()
	if not s.night:
		s.theme = UiTheme.theme
	s.size = Vector2(1032, 1075)
	s.z_index = SheetHost.Z_SHEET
	add_child_autofree(s)
	return s


# ------------------------------------------------------------------ batching (blocker)

func test_sheet_surfaces_share_one_material_and_sit_under_the_content() -> void:
	var s := _album()
	await wait_frames(2)
	var surfaces: Array[Node] = _leaves(s, "UiSurface")
	assert_gt(surfaces.size(), 12, "cards, chip, grabber, plates and tracks are batched surfaces")
	var mats := {}
	var top_surface := -INF
	for n: Node in surfaces:
		mats[(n as CanvasItem).material] = true
		top_surface = maxf(top_surface, float(_abs_z(n as CanvasItem)))
	assert_true(mats.size() <= 2, "one surface material (chrome + scroll fade variant): %d" % mats.size())
	var labels: Array[Node] = _leaves(s, "Label")
	var by_font := {}
	for n: Node in labels:
		var l := n as Label
		assert_gt(float(_abs_z(l)), top_surface - float(UiBatch.SCROLL_BAND), "label above its band's surfaces")
		var key := "%d|%d|%s" % [l.get_theme_font(&"font").get_rid().get_id(), l.get_theme_font_size(&"font_size"),
				UiBatch._in_scroll(l, s)]
		if not by_font.has(key):
			by_font[key] = {}
		(by_font[key] as Dictionary)[_abs_z(l)] = true
	for key: String in by_font:
		assert_eq((by_font[key] as Dictionary).size(), 1, "labels of one font+size share one z (%s)" % key)


func test_no_per_item_modulate_inside_the_grid() -> void:
	var s := _album()
	await wait_frames(2)
	for n: Node in _leaves(s, "TextureRect"):
		var t := n as TextureRect
		if t is BakedWell or _in_live_scene(t, s) or not t.is_visible_in_tree():
			continue
		assert_eq(t.modulate, Color.WHITE, "%s: opacity goes through the material, never modulate" % s.get_path_to(t))


func test_scroll_has_no_canvas_group_mask() -> void:
	var s := _album()
	await wait_frames(1)
	for n: Node in s.find_children("*", "CanvasItem", true, false):
		assert_eq((n as CanvasItem).clip_children, CanvasItem.CLIP_CHILDREN_DISABLED, "%s has no clip_children" % n.name)
	assert_eq(UiBatch.FADE_BOTTOM_PX, 120.0, "the bottom fade is 120 px, shown only while more waits below (round 6)")


func test_surface_instance_data_is_two_slots() -> void:
	var sh := load(UiSurface.SHADER) as Shader
	var count := 0
	for line: String in sh.code.split("\n"):
		if line.strip_edges().begins_with("instance uniform"):
			count += 1
	assert_eq(count, 2, "two instance slots per surface (the instance buffer is shared with the world)")
	var content := load(UiBatch.CONTENT_SHADER) as Shader
	for line: String in content.code.split("\n"):
		assert_false(line.strip_edges().begins_with("instance uniform"), "content leaves use no instance slots")


# ------------------------------------------------------------------ night scheme

func test_night_scheme_pairs_pass_aa() -> void:
	UiTokens.night_scheme = true
	var pairs := [[&"ink", &"surface_hi", AAA], [&"ink", &"surface", AAA], [&"ink_soft", &"surface_hi", AA],
		[&"ink_2", &"surface_hi", AA], [&"ink_2", &"gold_tint", AA], [&"ink", &"gold_tint", AA],
		[&"primary_deep", &"raised", AA], [&"ink_soft", &"primary_tint", AA], [&"leaf", &"leaf_tint", AA],
		[&"ink", &"coral_tint", AA]]
	for p: Array in pairs:
		var cr := UiTokens.contrast(UiTokens.sc(StringName(p[0])), UiTokens.sc(StringName(p[1])))
		assert_true(cr >= float(p[2]), "night %s on %s: %.2f" % [p[0], p[1], cr])
	var on_primary := UiTokens.contrast(UiTokens.color(&"surface_hi"), UiTokens.color(&"primary_pressed"))
	assert_true(on_primary >= AA, "pill label keeps its day cream on the day pill: %.2f" % on_primary)


func test_sheet_built_at_night_is_dim_with_cream_text() -> void:
	UiTokens.night_scheme = true
	var s := _album()
	await wait_frames(2)
	assert_true(s.night, "the sheet remembers its scheme")
	var card_lum := 1.0
	for n: Node in _leaves(s, "UiSurface"):
		var u := n as UiSurface
		if u.radius == float(ThemeBuilder.R_L):
			card_lum = minf(card_lum, u.color.get_luminance())
	assert_lt(card_lum, 0.35, "night cards are dim (QA r4: no near-white panel at night)")
	var l := s.title
	assert_gt(l.get_theme_color(&"font_color").get_luminance(), 0.8, "night text is cream")


func test_day_sheet_stays_light() -> void:
	var s := _album()
	await wait_frames(1)
	assert_false(s.night)
	assert_lt(s.title.get_theme_color(&"font_color").get_luminance(), 0.3, "day ink")


# ------------------------------------------------------------------ text size 200 %

func test_dock_labels_take_the_full_200_percent_size() -> void:
	var dock := DockView.new()
	dock.theme = UiTheme.theme
	add_child_autofree(dock)
	dock.layout(SCREEN, SAFE_BOTTOM)
	var h100 := dock.pill_rect().size.y
	var w100 := dock.pill_rect().size.x
	var base := {}
	var icons := {}
	for id: StringName in DockView.ORDER:
		base[id] = dock.button(id).label.get_combined_minimum_size().y
		icons[id] = dock.button(id).icon_px
	Settings.set_value(Settings.TEXT_SCALE, TEXT_200)
	dock.theme = UiTheme.theme
	await wait_frames(2)
	dock.layout(SCREEN, SAFE_BOTTOM)
	var full := roundi(float(ThemeBuilder.SIZE_CAPTION) * RATIO_200)
	for id: StringName in DockView.ORDER:
		var b := dock.button(id)
		var fs := b.label.get_theme_font_size(&"font_size")
		assert_true(fs >= roundi(float(full) * DockView.LABEL_SHRINK_FLOOR), "%s label near Caption 36 x 2.0 (%d)" % [id, fs])
		assert_true(b.label.get_combined_minimum_size().y >= 1.6 * float(base[id]), "%s label really grew" % id)
		assert_eq(b.icon_px, float(icons[id]), "icons never shrink")
		var font := b.label.get_theme_font(&"font")
		var w := font.get_string_size(b.label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		assert_true(w <= b.size.x - DockView.label_pad() * 2.0 + 0.5, "%s label fits its tab" % id)
	assert_gt(dock.pill_rect().size.y, h100, "the pebble grows taller")
	assert_true(dock.pill_rect().size.x >= w100, "... and wider")
	assert_true(dock.pill_rect().position.x >= DockView.PILL_SIDE - 0.5, "never wider than the screen")


func test_top_bar_numerals_scale_with_text() -> void:
	Settings.set_value(Settings.TEXT_SCALE, TEXT_200)
	await wait_frames(2)
	var top := TopBarView.new()
	top.theme = UiTheme.theme
	add_child_autofree(top)
	await wait_frames(2)
	top.layout(SCREEN, 72.0)
	var dew := top.dew_chip.get_child(1) as Label
	assert_eq(dew.get_theme_font_size(&"font_size"), roundi(float(ThemeBuilder.SIZE_HUD) * RATIO_200), "numerals x 2.0")
	assert_gt(top.dew_chip.size.y, TopBarView.CHIP_H, "the chip grows with its text")


# ------------------------------------------------------------------ recap copy

func test_recap_visit_line_is_a_whole_sentence() -> void:
	var t := I18n.fmt(OverlayHost.RECAP_ONE_VISITED_HI, {"name": "Pip"})
	assert_true(t.begins_with("Pip"), "names the friend")
	assert_gt(t.split(" ").size(), 3, "a whole sentence, not 'Pip dropped by'")


# ------------------------------------------------------------------ plush product shots (r5 owner)
func test_portrait_well_is_a_product_sweep_tinted_by_the_friend() -> void:
	var sp: StringName = &"puffmoss"
	var cell := AlbumSheet.portrait_cell(sp, true, &"awake")
	add_child_autofree(cell)
	assert_true(cell is LiveWell, "a met friend's cell is a well")
	var mat := (cell as LiveWell).material as ShaderMaterial
	assert_eq(float(mat.get_shader_parameter(&"u_product")), 1.0, "portrait wells use the product sweep")
	var res: Dictionary = (c.palettes.get("creatures", {}) as Dictionary).get("species_resolved", {})
	var accent := Color.html(String((res.get(String(sp), {}) as Dictionary).get("accent", "#000000")))
	var tint: Color = mat.get_shader_parameter(&"u_pr_tint")
	assert_true(tint.is_equal_approx(accent), "the sweep takes the friend's accent colour")


func test_portrait_hides_the_world_cast_shadow() -> void:
	var p := CreaturePortrait.new()
	p.setup(&"puffmoss", true, &"awake", false)
	p.size = Vector2(300, 300)
	add_child_autofree(p)
	await get_tree().process_frame
	var cast := p.mossling.get_node_or_null(^"Visual/Shadow") as CanvasItem
	assert_not_null(cast)
	if cast != null:
		assert_false(cast.visible, "the studio well paints the toy's own contact shadow")


func test_an_open_sheets_tab_never_looks_asleep() -> void:
	var b := RoundButton.new()
	add_child_autofree(b)
	b.asleep = true
	assert_true(b.looks_asleep())
	b.active = true
	assert_false(b.looks_asleep(), "the selected tab under its own sheet is fully awake")
