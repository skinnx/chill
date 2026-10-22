extends GutTest
## Environment round 3 (qa/reports/round2.md env section): long shadows that fan away from a low
## sun and are clamped, the value frame mesh leaves the focal ellipse open, lamp pools hold a broad
## plateau, the touch flourish follows motion_tokens ui.ring, and the chime branch answers the wind
## chime's touch.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const SUN := Vector2(560, 640)


func after_each() -> void:
	LampRegistry.clear()


func _golden() -> Dictionary:
	return {&"g_celestial": Vector2(1, 0), &"g_world_offset": Vector2.ZERO, &"g_backlight": 1.0,
		&"g_sun_pos": SUN, &"g_sun_dir": (SUN - Vector2(540, 1150)).normalized()}


func test_low_sun_shadows_are_long_and_clamped() -> void:
	var v := _golden()
	var len := ShadowMath.cast_length(v, 60.0)
	assert_almost_eq(len, ShadowMath.length_factor(v) * 60.0, 0.01, "length = factor x height")
	assert_gt(len, 60.0 * 2.0, "golden shadows run over 2x the object height")
	assert_eq(ShadowMath.cast_length(v, 1000.0), ShadowMath.CAST_MAX_PX, "clamped")
	var day := v.duplicate()
	day[&"g_sun_pos"] = Vector2(780, 300)
	day[&"g_backlight"] = 0.1
	assert_lt(ShadowMath.cast_length(day, 60.0), len, "a high sun casts shorter shadows")


func test_backlit_shadows_fan_away_from_the_sun() -> void:
	var v := _golden()
	var left := ShadowMath.cast_dir(v, Vector2(200, 1200))
	var right := ShadowMath.cast_dir(v, Vector2(900, 1200))
	var centre := ShadowMath.cast_dir(v, Vector2(SUN.x, 1200))
	assert_lt(left.x, -0.2, "left of the sun: shadow leans left")
	assert_gt(right.x, 0.2, "right of the sun: shadow leans right")
	assert_gt(centre.y, 0.95, "under the sun: straight toward the viewer")
	for d: Vector2 in [left, right, centre]:
		assert_gt(d.y, 0.0, "always toward the viewer")
		assert_almost_eq(d.length(), 1.0, 0.001)
	# Without a foot position the old side direction holds (tests/test_world_env.gd contract).
	assert_eq(ShadowMath.cast_dir(v), ShadowMath.cast_dir(v, Vector2.INF))


func test_value_frame_leaves_the_focal_open() -> void:
	var focal := Vector2(540, 1123)
	for r: Rect2 in ValueFrame.rects():
		assert_false(r.has_point(focal), "the sun stone is never under the multiply mesh")
	var area := 0.0
	for r: Rect2 in ValueFrame.rects():
		area += r.get_area()
	var screen := (ValueFrame.DESIGN_W + 2.0 * ValueFrame.BLEED_X) * 2400.0
	# Round 4 (directive 1): the frame covers the whole play area around the focal; still well under
	# the full screen (one cheap multiply pass, dropped at governor tier 1+).
	assert_lt(area / screen, 0.6, "fill stays well under the full screen")
	assert_eq(ValueFrame.build_mesh().get_surface_count(), 1, "one surface, one draw call")


func test_lamp_pools_hold_a_plateau() -> void:
	LampRegistry.set_lamp(&"a", Vector2(300, 1400), 150.0, 1.0)
	var centre := LampRegistry.weight_at(Vector2(300, 1400))
	var half := LampRegistry.weight_at(Vector2(375, 1400))
	assert_gt(half, LampRegistry.PEAK_RANGE.y * 0.6, "half the radius out the pool is still strong")
	assert_lt(half, centre)
	assert_eq(LampRegistry.weight_at(Vector2(451, 1400)), 0.0, "zero past the radius")


func test_touch_ring_follows_motion_tokens() -> void:
	var r := TouchRing.new()
	add_child_autofree(r)
	var ui: Dictionary = ContentRegistry.motion_tokens()["ui"]
	var px := float(ContentRegistry.content.spots_doc["frame"]["px_per_dp"])
	assert_almost_eq(r.duration_s, float(ui["stream_ripple_ms"]) / 1000.0, 0.001, "380 ms")
	assert_almost_eq(r.radius_px, float(ui["ring"]["radius_dp"]) * px, 0.01, "36 dp")
	r.freeze_at(0.1)
	var v: Vector4 = r.get_instance_shader_parameter(&"i_ring")
	assert_almost_eq(v.x, 0.1 / r.duration_s, 0.001, "frozen progress")
	var sp: Array = ui["sparkles"]
	assert_between(v.w, float(sp[0]), float(sp[1]), "sparkle count from ui.sparkles")


func test_chime_branch_answers_the_wind_chime() -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PropsLayer.ATLAS_JSON))
	var found := false
	for part: Dictionary in doc["parts"]:
		if String(part["id"]) == "chime_branch":
			found = String(part.get("touch", "")) == "wind_chime_branch"
	assert_true(found, "the chime branch sprite is the wind chime's touch target")
	var props: Array = ContentRegistry.content.spots_doc["props"]
	var ids: Array[String] = []
	for p: Dictionary in props:
		ids.append(String(p["id"]))
	assert_has(ids, "wind_chime_branch")
