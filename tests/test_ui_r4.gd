extends GutTest
## Round-4 UI contracts (QA r3 ui section): the night chrome keeps every label above WCAG AA over
## the darkest and brightest night backdrops, only the HUD chrome follows it (sheets stay light),
## the pill ripple never washes over its label, the new segmented thumb and the dock's selected
## label pass AA, and the night icon variant redraws the ink layer.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const AA := 4.5
## Night backdrops behind the chrome: the night sky, the dusk horizon and a lantern pool.
const NIGHT_BACKDROPS: Array[String] = ["#1C2140", "#3A3560", "#C9A66B", "#FFE2A8"]


func after_each() -> void:
	GlassPanel.set_night(0.0)


func test_night_chrome_labels_pass_aa_over_any_night_backdrop() -> void:
	var nt := GlassPanel.night_tokens()
	var fill := float(nt.get("fill", 0.0))
	assert_gt(fill, 0.8, "night glass is mostly opaque")
	var ink := UiTokens.color(&"night_ink")
	for hex: String in NIGHT_BACKDROPS:
		var glass := Color.html(hex).lerp(UiTokens.color(&"night_glass"), fill)
		var cr := UiTokens.contrast(ink, glass)
		assert_true(cr >= AA, "night ink on night glass over %s: %.2f" % [hex, cr])
	for token: StringName in [&"night_capsule", &"night_track"]:
		var cr2 := UiTokens.contrast(ink, UiTokens.color(token))
		assert_true(cr2 >= AA, "night ink on %s: %.2f" % [token, cr2])
	# the light ripple on the night dock (capped) keeps the label legible
	var rip := UiTokens.color(&"night_capsule").lerp(UiTokens.color(&"surface_hi"), PressFeedback.ON_DARK_RIPPLE_MAX)
	assert_true(UiTokens.contrast(ink, rip) >= AA, "night label over the capped ripple")


func test_hysteresis_thresholds_are_ordered() -> void:
	var nt := GlassPanel.night_tokens()
	assert_lt(float(nt.get("off", 1.0)), float(nt.get("on", 0.0)), "off < on (no flicker at the threshold)")


func test_sheet_dim_keeps_primary_label_aa() -> void:
	var dim := 1.0 - float(GlassPanel.night_tokens().get("sheet_dim", 0.0))
	var k := Color(dim, dim, dim)
	var label := UiTokens.color(&"surface_hi") * k
	for token: StringName in [&"primary_pressed", &"primary_deep"]:
		var cr := UiTokens.contrast(label, UiTokens.color(token) * k)
		assert_true(cr >= AA, "pill label on dimmed %s: %.2f" % [token, cr])
	var ink := UiTokens.contrast(UiTokens.color(&"ink") * k, UiTokens.color(&"surface") * k)
	assert_true(ink >= AA, "ink on the dimmed sheet: %.2f" % ink)


func test_pill_ripple_crest_keeps_label_aa() -> void:
	var a0 := float((UiTokens.ui_block("ring").get("alpha", [0.35]) as Array)[0])
	var a := minf(a0 * PressFeedback.PILL_RIPPLE_SHARE, 1.0)
	for token: StringName in [&"primary_pressed", &"primary_deep"]:
		var under := UiTokens.color(token).lerp(UiTokens.color(&"primary"), a)
		var cr := UiTokens.contrast(UiTokens.color(&"surface_hi"), under)
		assert_true(cr >= AA, "label over the ripple crest on %s: %.2f" % [token, cr])


func test_ripple_draws_under_the_button_label() -> void:
	var b := Button.new()
	b.text = "Plant"
	b.size = Vector2(360, 144)
	add_child_autofree(b)
	PressFeedback.attach(b)
	PressFeedback.pose(b, 0.09)
	var rip: Node = null
	for n: Node in b.get_children(true):
		if n.name == &"Ripple":
			rip = n
	assert_not_null(rip, "ripple present")
	if rip == null:
		return
	var l := rip.get_node_or_null(^"RippleLabel") as Label
	assert_not_null(l, "the label rides above the ripple")
	if l != null:
		assert_eq(l.text, "Plant")
	assert_almost_eq(b.get_theme_color(&"font_color").a, 0.0, 0.001, "the button's own text is hidden meanwhile")


func test_segmented_and_selected_tab_labels_pass_aa() -> void:
	var sel := UiTokens.contrast(UiTokens.color(&"primary_deep"), UiTokens.color(&"surface_hi"))
	assert_true(sel >= AA, "segmented selected label on its thumb: %.2f" % sel)
	var other := UiTokens.contrast(UiTokens.color(&"ink_soft"), UiTokens.color(&"primary_tint"))
	assert_true(other >= AA, "segmented label on the track: %.2f" % other)
	var tab := UiTokens.contrast(UiTokens.color(RoundButton.ACTIVE_LABEL_TOKEN), UiTokens.color(&"primary_tint"))
	assert_true(tab >= 6.0, "selected dock label on its capsule, comfortably above AA: %.2f" % tab)


func test_only_night_aware_glass_follows_the_night_scheme() -> void:
	var chip := GlassPanel.new()
	chip.night_aware = true
	var toast := GlassPanel.new()
	add_child_autofree(chip)
	add_child_autofree(toast)
	chip.size = Vector2(300, 120)
	toast.size = Vector2(300, 120)
	GlassPanel.set_night(1.0)
	var mc := (chip.get_child(0, true) as CanvasItem).material as ShaderMaterial
	var mt := (toast.get_child(0, true) as CanvasItem).material as ShaderMaterial
	assert_ne(mc, mt, "chrome and non-chrome glass never share a material")
	assert_almost_eq(float(mc.get_shader_parameter(&"u_night")), 1.0, 0.001, "chip goes night")
	var tn: Variant = mt.get_shader_parameter(&"u_night")
	assert_true(tn == null or is_zero_approx(float(tn)), "toast glass stays light")


func test_round_button_label_lerps_to_night_ink() -> void:
	var b := RoundButton.new()
	add_child_autofree(b)
	b.set_label("Garden")
	b.night_k = 1.0
	assert_true(b.label.get_theme_color(&"font_color").is_equal_approx(UiTokens.color(&"night_ink")), "night label")
	b.night_k = 0.0
	assert_false(b.label.has_theme_color_override(&"font_color"), "day label back on the theme's ink")


func test_night_icon_variant_redraws_ink() -> void:
	var base := load(Icons.DIR + "garden.svg") as DPITexture
	var src := Icons.variant_source(base.get_source(), false, true)
	var ink := "#" + UiTokens.color(&"ink").to_html(false).to_upper()
	var night := "#" + UiTokens.color(&"night_ink").to_html(false).to_upper()
	assert_false(src.contains(ink), "no day ink left")
	assert_true(src.contains(night), "strokes in night ink")
	var atlas := Icons.hud_atlas()
	assert_true(atlas.has(Icons.atlas_key(&"dock_garden", DockView.HERO_ICON_PX, false, true)),
			"night hero tab icon in the HUD atlas")
	assert_true(atlas.has(Icons.atlas_key(&"gear", TopBarView.ICON_PX, true, true)),
			"night selected gear in the HUD atlas")
	assert_true(atlas.has(Icons.atlas_key(&"dew", 72.0, false, true)), "night dew icon in the HUD atlas")
