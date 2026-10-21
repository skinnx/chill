extends GutTest
## Décor, gifts, boats and the QA fixtures (Art Bible §6.6-6.8, GDD §2.5, §4.3-4.5, docs/QA.md
## §5.1): the décor atlas covers every part the layer places, with known palettes.json materials;
## the pinwheel never spins past the wagon-wheel limit; the gust mirror matches the shader's
## envelope; the fixtures are deterministic, respect the placement rules (one stem per slot, max
## copies) and put every stem at the stage they list right now, and the sim built on a fixture is
## consistent (bloomed counts, snugness) and advances without regressing anything.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

## Art Bible §6.6: 4 blades at 30 fps alias above 3.75 rev/s.
const WAGON_WHEEL_REV_S := 3.75
const SEED := 4242

var c: GameContent
var decor_doc: Dictionary


func before_all() -> void:
	c = GameContent.load_from_dir()
	decor_doc = JSON.parse_string(FileAccess.get_file_as_string(DecorKit.ATLAS_JSON))


func after_each() -> void:
	LampRegistry.clear()


func _fresh_state() -> WorldState:
	return WorldSim.new_game(c, SEED, 1.79e9, 0.0).state


func test_decor_atlas_parts_and_materials() -> void:
	var parts: Dictionary = decor_doc["parts"]
	var layout: Dictionary = decor_doc["layout"]
	var mats: Dictionary = c.palettes["materials"]
	var needed: Array[String] = ["pinwheel_a", "pinwheel_b", "pinwheel_stick", "stream_stone", "toadstool_cap",
		"toadstool_stem", "lantern_crook", "lantern_core", "lantern_jar", "dew_drop", "basket_rim", "leaf_boat",
		"candle", "dust_dot"]
	for id: Variant in layout["cairn_parts"]:
		needed.append(String(id))
	for id2: Variant in layout["chime_parts"]:
		needed.append(String(id2))
	for g: Variant in (layout["gift_parts"] as Dictionary).values():
		needed.append(String(g))
	for id3: String in needed:
		assert_true(parts.has(id3), "décor part %s exists" % id3)
		if parts.has(id3):
			assert_true(mats.has(String((parts[id3] as Dictionary)["material"])), "%s material exists" % id3)
	for item: Dictionary in c.economy["gift_items"]:
		assert_true((layout["gift_parts"] as Dictionary).has(String(item["id"])), "gift %s has a stamp" % item["id"])
	for d: Dictionary in c.decor:
		assert_true((layout["set_scale"] as Dictionary).has(String(d["id"])), "set %s has a scale" % d["id"])
	var imp := ConfigFile.new()
	assert_eq(imp.load("res://art/decor/decor_atlas.svg.import"), OK)
	assert_eq(int(imp.get_value("params", "compress/mode")), 0, "lossless tone mask")


func test_pinwheel_speed_respects_the_caps() -> void:
	for w: float in [0.0, 0.35, 0.55, 0.85, 1.0, 2.0]:
		for g: float in [0.0, 0.5, 1.0]:
			var rev := DecorLayer.pinwheel_rev_s(w, g)
			assert_true(rev >= DecorLayer.PW_BASE_REV - 1e-6, "idle never stops")
			assert_true(rev <= DecorLayer.PW_IDLE_CAP + 1e-6, "idle capped at 1.2 rev/s")
	assert_lt(DecorLayer.PW_BURST_REV, WAGON_WHEEL_REV_S, "the tap burst stays below the wagon-wheel limit")


func test_gust_mirror_is_an_envelope() -> void:
	var peak := 0.0
	for i in 600:
		var g := DecorLayer.gust_at(float(i) * 3.0, 17.0)
		assert_between(g, 0.0, 1.0)
		peak = maxf(peak, g)
	assert_gt(peak, 0.9, "the gust reaches full strength somewhere along x")
	assert_almost_eq(DecorLayer.gust_at(100.0, 0.0), DecorLayer.gust_at(100.0, 600.0), 1e-4,
			"loops at the 600 s g_time wrap")


func test_fixtures_are_deterministic_and_follow_the_rules() -> void:
	for name: String in GardenFixture.names():
		var a := _fresh_state()
		var b := _fresh_state()
		assert_true(GardenFixture.apply(c, a, name))
		assert_true(GardenFixture.apply(c, b, name))
		assert_eq(JSON.stringify(a.stems), JSON.stringify(b.stems), "%s is deterministic" % name)
		var taken := {}
		for s: Dictionary in a.stems:
			var key := "%s/%d" % [s["bed"], s["slot"]]
			assert_false(taken.has(key), "%s: one stem per slot (%s)" % [name, key])
			taken[key] = true
			var bed: Dictionary = c.beds_by_id[StringName(s["bed"])]
			assert_true(int(s["slot"]) >= 0 and int(s["slot"]) < int(bed["capacity"]))
		for id: String in a.owned:
			assert_true(int(a.owned[id]) <= c.max_copies(StringName(id)), "%s: %s within max copies" % [name, id])
		assert_true(a.seed_planted, "the tutorial seed is done in a mid-game garden")
		assert_true(a.basket.size() > 0 and a.basket.size() <= int(c.economy["basket_slots"]))
	assert_false(GardenFixture.apply(c, _fresh_state(), "nope"), "unknown fixture refused")


func test_mid_garden_has_mixed_stages_and_every_set() -> void:
	var st := _fresh_state()
	GardenFixture.apply(c, st, GardenFixture.MID)
	var stages := {}
	var beds := {}
	for s: Dictionary in st.stems:
		stages[int(s["stage"])] = true
		beds[String(s["bed"])] = true
	for stage: int in [WorldSim.STAGE_SEED, WorldSim.STAGE_SPROUT, WorldSim.STAGE_BUD, WorldSim.STAGE_BLOOM]:
		assert_true(stages.has(stage), "mid garden shows stage %d" % stage)
	assert_eq(beds.size(), c.beds.size(), "every bed is planted")
	for d: Dictionary in c.decor:
		assert_gt(int(st.owned.get(String(d["id"]), 0)), 0, "décor set %s is placed" % d["id"])
	var night := _fresh_state()
	GardenFixture.apply(c, night, GardenFixture.NIGHT_LANTERNS)
	assert_eq(int(night.owned["firefly_lantern"]), GardenFixture.NIGHT_LANTERN_COUNT, "night with 5 lanterns")


func test_fixture_stages_are_current_and_the_sim_stays_consistent() -> void:
	var st := _fresh_state()
	GardenFixture.apply(c, st, GardenFixture.MID)
	var sim := WorldSim.new(c, st)
	var blooms := 0
	for s: Dictionary in st.stems:
		var f: Dictionary = c.flowers_by_id[StringName(s["flower"])]
		var times := [0.0, float(f["sprout_at_s"]), float(f["bud_at_s"]), float(f["bloom_at_s"]), INF]
		var age := st.t - float(s["planted_t"])
		var stage := int(s["stage"])
		assert_true(age >= float(times[stage]) and age < float(times[stage + 1]),
				"%s stem is at stage %d right now (age %.0f s)" % [s["flower"], stage, age])
		if stage == WorldSim.STAGE_BLOOM:
			blooms += 1
	var bloomed := 0
	for f2: Dictionary in c.flowers:
		bloomed += sim.bloomed_count(StringName(f2["id"]))
	assert_eq(bloomed, blooms, "bloom caches rebuilt from the fixture")
	assert_gt(sim.snugness(), 0.0)
	var before := sim.monotone_snapshot()
	sim.advance(st.t + 3600.0)
	var after := sim.monotone_snapshot()
	for k: Variant in before:
		if before[k] is int or before[k] is float:
			assert_true(float(after[k]) >= float(before[k]), "E1: %s never decreases" % k)
	for s2: Dictionary in st.stems:
		assert_true(int(s2["stage"]) >= 0 and int(s2["stage"]) <= WorldSim.STAGE_BLOOM)


func test_lantern_pools_fit_the_lamp_registry() -> void:
	# Glow mushrooms (1) + lantern pools + up to max_on_water boat candles must fit u_lamps[12].
	var boats := int(c.motion["ui"]["leaf_boat"]["max_on_water"])
	assert_true(1 + DecorLayer.MAX_LANTERN_POOLS + boats <= LampRegistry.MAX_LAMPS)
