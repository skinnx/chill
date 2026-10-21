extends GutTest
## Round-3 UI contracts: touch feedback is visible on the first frames of a press (I1, Art Bible
## §10.3), faux glass surfaces share one material so the HUD batches (§4.19), the HUD dims at
## night without breaking ink contrast (§1.3, X2), and the new primary fill passes AA.

const AA := 4.5


func test_press_pose_dips_and_ripples() -> void:
	var b := Button.new()
	b.text = "Plant"
	b.size = Vector2(300, 132)
	add_child_autofree(b)
	PressFeedback.attach(b)
	PressFeedback.pose(b, 0.08)
	assert_lt(b.scale.y, 1.0, "the press dips by touch-down + 80 ms")
	var ripple := b.get_node_or_null(^"Ripple")
	if ripple == null:
		for c: Node in b.get_children(true):
			if c.name == &"Ripple":
				ripple = c
	assert_not_null(ripple, "a ripple grows from the touch point")
	if ripple != null:
		var m := (ripple as CanvasItem).material as ShaderMaterial
		var progress: float = m.get_shader_parameter(&"u_progress")
		assert_gt(progress, 0.0, "ripple under way")


func test_squash_press_is_wider_than_tall() -> void:
	var b := Button.new()
	b.size = Vector2(252, 216)
	add_child_autofree(b)
	PressFeedback.attach(b, &"", 2.0, true)
	PressFeedback.pose(b, 0.2)
	assert_gt(b.scale.x, b.scale.y, "M3 squash: the tab gives back width")
	assert_almost_eq(b.pivot_offset.y, 216.0, 0.01, "squashes onto its baseline")


func test_faux_glass_surfaces_share_one_material() -> void:
	var a := GlassPanel.new()
	var c := GlassPanel.new()
	add_child_autofree(a)
	add_child_autofree(c)
	a.size = Vector2(300, 120)
	c.size = Vector2(120, 120)
	var ga := a.get_child(0, true) as CanvasItem
	var gc := c.get_child(0, true) as CanvasItem
	assert_not_null(ga.material)
	assert_eq(ga.material, gc.material, "same elevation + pill + fill -> one material (one batch)")


func test_night_tint_keeps_ink_on_glass_aa() -> void:
	var tint := UiTokens.color(&"hud_night_tint")
	var ink := UiTokens.color(&"ink") * tint
	for token: StringName in [&"surface", &"surface_hi", &"primary_tint"]:
		var bg := UiTokens.color(token) * tint
		assert_true(UiTokens.contrast(ink, bg) >= AA, "%s at night: %.2f" % [token, UiTokens.contrast(ink, bg)])
	var on_primary := UiTokens.contrast(UiTokens.color(&"surface_hi") * tint, UiTokens.color(&"primary_pressed") * tint)
	assert_true(on_primary >= AA, "primary pill label at night: %.2f" % on_primary)


func test_primary_and_secondary_text_pass_aa() -> void:
	var hi := UiTokens.color(&"surface_hi")
	assert_true(UiTokens.contrast(hi, UiTokens.color(&"primary_pressed")) >= AA, "primary pill label")
	assert_true(UiTokens.contrast(hi, UiTokens.color(&"primary_deep")) >= AA, "pressed primary pill label")
	assert_true(UiTokens.contrast(UiTokens.color(&"ink_soft"), UiTokens.color(&"surface")) >= AA, "secondary text")
	assert_true(UiTokens.contrast(UiTokens.color(&"primary_pressed"), UiTokens.color(&"primary_tint")) >= AA,
			"selected dock label on its capsule")
	assert_true(UiTokens.contrast(UiTokens.color(&"leaf"), UiTokens.color(&"leaf_tint")) >= AA, "done chip")
