extends GutTest
## Time-of-day palette pipeline (Art Bible §3.3-3.4, GDD §6): clock -> g_day, OKLab interpolation
## (checked against Godot's own Gradient in OKLab mode), rain transform, weather crossfade,
## celestial path, and that TimeOfDay pushes the declared shader globals.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const TOL := 1.0 / 255.0

var c: GameContent
var pd: PaletteDriver


func before_all() -> void:
	c = GameContent.load_from_dir()
	pd = PaletteDriver.new(c.palettes)


func _hex(slot: String, palette: String) -> Color:
	return Color.html(String(c.palettes["tod"]["palettes"][palette][slot]))


func _close(a: Color, b: Color, tol: float = TOL) -> bool:
	return absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol and absf(a.b - b.b) <= tol


func test_keys_reproduce_the_five_palettes_exactly() -> void:
	for k: Dictionary in c.palettes["tod"]["gradient_keys"]:
		var cols := pd.sample_colors(float(k["g_day"]))
		for slot: String in ["sky_top", "sky_horizon", "near", "ambient", "key", "water_deep"]:
			var want := _hex(slot, String(k["palette"]))
			assert_true(_close(cols[slot], want), "%s at g_day %s: %s vs %s" % [slot, k["g_day"],
					(cols[slot] as Color).to_html(false), want.to_html(false)])


func test_midpoints_match_godot_gradient_in_oklab() -> void:
	for slot: String in ["sky_top", "sky_mid", "far", "near", "ambient", "shadow"]:
		var g := pd.make_gradient(slot)
		assert_eq(g.interpolation_color_space, Gradient.GRADIENT_COLOR_SPACE_OKLAB)
		for x: float in [0.1, 0.3, 0.5, 0.7, 0.9, 0.55]:
			var mine: Color = pd.sample_colors(x)[slot]
			var engine := g.sample(x)
			assert_true(_close(mine, engine, 1.5 / 255.0),
					"%s @ %.2f: %s vs engine %s" % [slot, x, mine.to_html(false), engine.to_html(false)])


func test_oklab_round_trip() -> void:
	for hex: String in ["#F0EEE9", "#111938", "#FFCB7D", "#4A6FD6", "#000000", "#FFFFFF"]:
		var col := Color.html(hex)
		assert_true(_close(PaletteMath.from_oklab(PaletteMath.to_oklab(col)), col, 0.5 / 255.0), hex)


func test_scalars_interpolate_linearly() -> void:
	var day: Dictionary = c.palettes["tod"]["scalars"]["day"]
	var golden: Dictionary = c.palettes["tod"]["scalars"]["golden"]
	var mid := pd.sample_scalars(0.5)
	assert_almost_eq(float(mid["backlight"]), (float(day["backlight"]) + float(golden["backlight"])) * 0.5, 1e-9)


func test_clock_to_g_day() -> void:
	var h := 3600.0
	assert_almost_eq(TodMath.g_day_at(c, 12.0 * h), 0.4, 1e-9, "noon = day")
	assert_almost_eq(TodMath.g_day_at(c, 23.0 * h), 1.0, 1e-9, "23:00 = night (1.0)")
	assert_almost_eq(TodMath.g_day_at(c, 1.0 * h), 0.0, 1e-9, "01:00 = night (0.0 after midnight)")
	assert_almost_eq(TodMath.g_day_at(c, 5.0 * h), 0.0, 1e-9, "dawn crossfade starts at 05:00")
	assert_almost_eq(TodMath.g_day_at(c, 5.0 * h + 1200.0), 0.1, 1e-9, "half-way through the 40 min crossfade")
	assert_almost_eq(TodMath.g_day_at(c, 5.0 * h + 2400.0), 0.2, 1e-9, "dawn reached")
	assert_almost_eq(TodMath.g_day_at(c, 20.5 * h + 1200.0), 0.9, 1e-9, "dusk -> night crossfade")
	assert_eq(TodMath.phase_id_at(c, 4.0 * h), &"night")
	assert_eq(TodMath.phase_id_at(c, 17.0 * h), &"golden")
	# Continuity: no jump larger than one minute of crossfade anywhere except the invisible 1 -> 0.
	var prev := TodMath.g_day_at(c, 0.0)
	var t := 60.0
	while t < 86400.0:
		var gd := TodMath.g_day_at(c, t)
		var jump := absf(gd - prev)
		assert_true(jump < 0.01 or absf(jump - 1.0) < 1e-9, "g_day jump %.4f at %.0f s" % [jump, t])
		prev = gd
		t += 60.0


func test_rain_transform_softens_and_is_identity_when_dry() -> void:
	var cols := pd.sample_colors(0.4)
	var sc := pd.sample_scalars(0.4)
	var dry := cols.duplicate()
	var dry_sc := sc.duplicate()
	pd.apply_rain(dry, dry_sc, 0.0)
	assert_true(_close(dry["sky_top"], cols["sky_top"], 0.0))
	var wet := cols.duplicate()
	var wet_sc := sc.duplicate()
	pd.apply_rain(wet, wet_sc, 1.0)
	var l0 := PaletteMath.to_oklab(cols["sky_top"])
	var l1 := PaletteMath.to_oklab(wet["sky_top"])
	assert_lt(Vector2(l1.y, l1.z).length(), Vector2(l0.y, l0.z).length() * 0.6, "chroma x0.55 in rain")
	assert_almost_eq(float(wet_sc["shafts"]), 0.0, 1e-9, "no light shafts in rain")
	assert_gt(float(wet_sc["mist"]), float(sc["mist"]))


func test_weather_crossfade_takes_thirty_seconds() -> void:
	var wd := WeatherDriver.new(c.world, &"clear")
	assert_almost_eq(wd.blend("g_wind"), 0.35, 1e-9)
	var t := 0.0
	while t < 15.0:
		wd.step(&"rain", 0.5)
		t += 0.5
	assert_between(wd.weight(&"rain"), 0.2, 0.8, "half-way")
	while t < 31.0:
		wd.step(&"rain", 0.5)
		t += 0.5
	assert_almost_eq(wd.weight(&"rain"), 1.0, 1e-9)
	assert_almost_eq(wd.blend("ambient_mult"), 0.92, 1e-9)
	assert_false(wd.is_crossfading())


func test_celestial_paths() -> void:
	var cel := Celestial.new(c.palettes["tod"]["celestial"])
	var noon := cel.evaluate(12.5, 0.0)
	assert_almost_eq((noon["sun"] as Vector2).x, 780.0, 1e-6, "keyed point is reproduced")
	assert_almost_eq((noon["visibility"] as Vector2).x, 1.0, 1e-6)
	assert_almost_eq((noon["sun_dir"] as Vector2).length(), 1.0, 1e-6)
	var night := cel.evaluate(23.5, 0.0)
	assert_eq((night["visibility"] as Vector2).x, 0.0, "no sun at night")
	assert_almost_eq((night["visibility"] as Vector2).y, 1.0, 1e-6, "moon up")
	var cloudy := cel.evaluate(12.5, 1.0)
	assert_almost_eq((cloudy["visibility"] as Vector2).x, 1.0 - Celestial.SUN_CLOUD_DIM, 1e-6)


func test_time_of_day_pushes_declared_globals() -> void:
	var values := TimeOfDay.evaluate(12.0 * 3600.0)
	for name: StringName in [&"g_day", &"g_sky_top", &"g_ambient", &"g_key", &"g_rim", &"g_halo", &"g_sun_pos",
			&"g_celestial", &"g_wind", &"g_rain", &"g_cloud", &"g_water_deep"]:
		assert_true(values.has(name), "evaluate() provides %s" % name)
		assert_true(ProjectSettings.has_setting("shader_globals/" + String(name)), "%s is declared in project.godot" % name)
	for key: String in ProjectSettings.get_property_list().map(func(p: Dictionary) -> String: return String(p["name"])):
		if key.begins_with("shader_globals/"):
			var g := key.trim_prefix("shader_globals/")
			var other_writer := g in ["g_time", "g_motion", "g_world_offset", "g_cam_pan"]
			assert_true(values.has(StringName(g)) or other_writer, "%s has a writer" % g)
