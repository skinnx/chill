extends GutTest
## Environment layers (Art Bible §2.4, §4.4-4.19, §7): deterministic terrain recipes inside their
## y bands, Poisson spacing, the particle budget (<= 3 systems, <= 150 particles in every state),
## shadow direction against the light, the lamp registry cap, the brook contract, the prop atlas
## layout against spots.json / palettes.json, the grass count V4 needs (>= 260 tufts) and the
## stream tap ripple.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const PHASES: Array[StringName] = [&"dawn", &"day", &"golden", &"dusk", &"night"]
const WEATHERS: Array[StringName] = [&"clear", &"breeze", &"rain"]

var c: GameContent


func before_all() -> void:
	c = GameContent.load_from_dir()


func after_each() -> void:
	LampRegistry.clear()


func test_terrain_is_deterministic_and_in_its_bands() -> void:
	var far_a := TerrainMath.sample_far(6.0)
	var far_b := TerrainMath.sample_far(6.0)
	assert_eq(far_a, far_b, "far crest is deterministic")
	var far := TerrainMath.y_range(far_a)
	assert_between(far.x, 560.0, 640.0, "far crest top (Art Bible §2.3: crest 610-670 minus the rises)")
	assert_between(far.y, 630.0, 700.0, "far crest lowest point")
	var mid := TerrainMath.y_range(TerrainMath.sample_mid(4.0))
	assert_between(mid.x, 480.0, 600.0, "mid canopy top")
	assert_lt(mid.y, 800.0, "mid crest stays above its body bottom")
	var meadow := TerrainMath.sample_meadow(2.0)
	for x: float in [0.0, 300.0, 600.0, 800.0, 1000.0, 1080.0]:
		assert_between(TerrainMath.meadow_base(x), 725.0, 820.0, "meadow crest at x %d" % x)
	assert_eq(meadow[0].x, TerrainMath.X_MIN, "geometry spans the wide-screen bleed")
	assert_almost_eq(meadow[meadow.size() - 1].x, TerrainMath.X_MAX, 2.0)


func test_hash_and_noise_ranges() -> void:
	for i in 500:
		var h := TerrainMath.hash01(i, 7)
		assert_true(h >= 0.0 and h < 1.0)
		var n := TerrainMath.fbm1(float(i) * 0.013, 2.2, 7, 0.68, 11)
		assert_true(n >= -1.0 and n <= 1.0)


func test_poisson_respects_min_distance() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var r := 30.0
	var pts := TerrainMath.poisson_disk(Rect2(0, 0, 600, 400), r, r, func(_p: Vector2) -> float: return r,
			func(_p: Vector2) -> bool: return true, rng)
	assert_gt(pts.size(), 100)
	var worst := INF
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			worst = minf(worst, pts[i].distance_to(pts[j]))
	assert_gte(worst, r - 0.001, "no two samples closer than r")


func test_particle_budget_holds_in_every_state() -> void:
	for ph: StringName in PHASES:
		for w: StringName in WEATHERS:
			var comp := ParticleBudget.composition(ph, w, 120)
			assert_lte(comp.size(), ParticleBudget.MAX_SYSTEMS, "%s/%s systems" % [ph, w])
			assert_lte(ParticleBudget.total(comp), ParticleBudget.MAX_PARTICLES, "%s/%s particles" % [ph, w])
	assert_true(ParticleBudget.composition(&"night", &"clear", 0).has(&"fireflies"))
	assert_true(ParticleBudget.composition(&"day", &"breeze", 0).has(&"seeds"), "dandelion seeds on the breeze")
	assert_false(ParticleBudget.can_start({&"a": 10, &"b": 10, &"c": 10}, 5), "a 4th system waits")
	assert_false(ParticleBudget.can_start({&"rain": 120}, 36), "no room over 150")
	assert_true(ParticleBudget.can_start({&"rain": 120}, 6))


func test_every_system_fades_in_for_at_least_300_ms() -> void:
	for id: StringName in AmbientParticles.SYSTEMS:
		var cfg: Dictionary = AmbientParticles.SYSTEMS[id]
		var fade := float(cfg.get("fade", AmbientParticles.FADE_IN_S))
		if id == &"splash":
			continue  # a ring grows from its centre (radius ease-out); it is never a pop
		assert_gte(fade, 0.3, "%s fade-in (V5)" % id)
		assert_lte(int(cfg["peak"]), ParticleBudget.MAX_PARTICLES)


func test_shadows_fall_away_from_the_light() -> void:
	var base := {&"g_celestial": Vector2(1, 0), &"g_world_offset": Vector2.ZERO, &"g_backlight": 0.1}
	for sun: Vector2 in [Vector2(200, 540), Vector2(780, 380), Vector2(560, 640), Vector2(300, 420)]:
		var v := base.duplicate()
		v[&"g_sun_pos"] = sun
		v[&"g_sun_dir"] = (sun - Vector2(540, 1150)).normalized()
		var off := ShadowMath.cast_offset(v, 100.0)
		assert_gt(off.y, 0.0, "shadows lean toward the viewer")
		if absf((v[&"g_sun_dir"] as Vector2).x) > 0.05:
			assert_true(signf(off.x) == -signf((v[&"g_sun_dir"] as Vector2).x), "x away from the sun at %s" % sun)
		var len_k := ShadowMath.length_factor(v)
		assert_between(len_k, 0.35, 2.5)
	var low := base.duplicate()
	low[&"g_sun_pos"] = Vector2(560, 680)
	var high := base.duplicate()
	high[&"g_sun_pos"] = Vector2(560, 300)
	assert_gt(ShadowMath.length_factor(low), ShadowMath.length_factor(high), "low sun, long shadows")


func test_lamp_registry_caps_and_orders() -> void:
	for i in 15:
		LampRegistry.set_lamp(StringName("l%02d" % i), Vector2(i * 10, 1400), 150.0, 1.0)
	assert_eq(LampRegistry.lamp_count(), LampRegistry.MAX_LAMPS)
	var a := LampRegistry.lamps()
	assert_eq(a[0].x, 0.0, "stable key order")
	LampRegistry.remove_lamp(&"l00")
	assert_eq(LampRegistry.lamps()[0].x, 10.0)


func test_brook_contract() -> void:
	assert_almost_eq(BrookLayer.half_width_px(c), 0.036 * 1920.0 * 0.5, 0.01, "water_width is a fraction of height")
	var fit := BrookLayer.centre_fit(c)
	for p: Vector2 in BrookLayer.polyline_px(c):
		assert_lt(absf(fit.x + fit.y * p.x - p.y), 16.0, "linear fit within 16 px (the near-bank term blends over 50 px)")


func test_path_profile() -> void:
	var top := MeadowLayer.path_at(780.0)
	var bottom := MeadowLayer.path_at(1440.0)
	assert_gt(top.w, 0.5)
	assert_gt(bottom.z, top.z, "the path widens toward the brook")
	assert_eq(MeadowLayer.path_at(700.0).w, 0.0, "nothing above the crest")


func test_prop_atlas_matches_data() -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PropsLayer.ATLAS_JSON))
	var size := PackedFloat64Array(doc["size"] as Array)
	var mats: Dictionary = c.palettes["materials"]
	var props_seen := {}
	for part: Dictionary in doc["parts"]:
		assert_true(mats.has(String(part["material"])), "%s material" % part["id"])
		var r := PackedFloat64Array(part["region"] as Array)
		assert_true(r[0] >= 0 and r[1] >= 0 and r[0] + r[2] <= size[0] and r[1] + r[3] <= size[1],
				"%s region inside the atlas" % part["id"])
		var prop := StringName(String(part["prop"]))
		if prop != &"":
			assert_true(c.props_by_id.has(prop), "%s belongs to a spots.json prop" % part["id"])
			props_seen[prop] = true
	for id: StringName in [&"willow", &"mailbox", &"stump", &"basket", &"sun_stone_rock", &"spring_rock"]:
		assert_true(props_seen.has(id), "%s is drawn" % id)


func test_grass_has_enough_tufts_for_v4() -> void:
	var g := GrassField.new()
	add_child_autofree(g)
	assert_gte(g.positions.size(), 260, "Art Bible A8: >= 260 tufts")
	for p: Vector2 in g.positions:
		assert_gt(p.y, TerrainMath.meadow_base(p.x) - 12.0, "tufts grow on the meadow")


func test_stream_tap_makes_a_ripple() -> void:
	var b: BrookLayer = (load("res://scenes/world/stream.tscn") as PackedScene).instantiate()
	add_child_autofree(b)
	watch_signals(b)
	var x := 540.0
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.device = 0
	ev.position = b.get_global_transform_with_canvas() * Vector2(x, b.centre_y_at(x))
	b._unhandled_input(ev)
	assert_signal_emitted(b, "tapped")
	var away := ev.duplicate() as InputEventMouseButton
	away.position = b.get_global_transform_with_canvas() * Vector2(x, 1000.0)
	b._unhandled_input(away)
	assert_signal_emit_count(b, "tapped", 1, "taps away from the water are ignored")


func test_grass_bands_sort_behind_creatures_in_them() -> void:
	# Round 1 blocker: a band's origin is its TOP edge, so no clump behind a creature's feet can
	# draw in front of it (only a clump just in front of the feet may hide behind the body).
	var g := GrassField.new()
	add_child_autofree(g)
	for b: Node in g.get_children():
		var mmi := b as MultiMeshInstance2D
		if mmi == null:
			continue
		for i in mmi.multimesh.instance_count:
			assert_gte(mmi.multimesh.get_instance_transform_2d(i).origin.y, -0.001, "%s clump above its band origin" % b.name)


func test_lamp_pools_are_discrete() -> void:
	LampRegistry.set_lamp(&"a", Vector2(300, 1400), 150.0, 1.0)
	LampRegistry.set_lamp(&"b", Vector2(540, 1400), 150.0, 1.0)
	var centre := LampRegistry.weight_at(Vector2(300, 1400))
	var gap := LampRegistry.weight_at(Vector2(420, 1400))
	assert_gt(centre, 0.3, "a pool peaks at its lamp")
	assert_lt(gap, centre * 0.5, "max-combined pools leave a darker gap between lanterns")
	assert_eq(LampRegistry.weight_at(Vector2(300, 1800)), 0.0, "nothing outside the pool")
