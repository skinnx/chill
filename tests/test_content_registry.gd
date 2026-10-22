extends GutTest
## ContentRegistry / GameContent: every data file loads, indexes and cross-references resolve,
## and the formulas reproduce the GDD tables (GDD §4, §5.2, §10).

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

var c: GameContent


func before_all() -> void:
	c = GameContent.load_from_dir()


func test_all_files_load_without_errors() -> void:
	assert_eq(c.errors.size(), 0, "content errors: %s" % ", ".join(c.errors))
	for stem: String in GameContent.FILES:
		assert_false((c.raw[stem] as Dictionary).is_empty(), "%s.json loaded" % stem)


func test_autoload_shares_the_same_valid_content() -> void:
	assert_true(ContentRegistry.is_valid())
	assert_eq(ContentRegistry.content.species.size(), c.species.size())


func test_mvp_content_counts() -> void:
	assert_eq(c.species.size(), 12, "12 species")
	assert_eq(c.flowers.size(), 8, "8 flowers")
	assert_eq(c.decor.size(), 6, "6 decor sets")
	assert_eq(c.beds.size(), 5, "5 beds")
	assert_eq(c.spots.size(), 13, "13 spots")
	assert_eq(c.phases.size(), 5, "5 phases")
	assert_eq(c.weather.size(), 3, "3 weather states")
	assert_eq(c.catalogue_size(), 140, "140 purchasable copies")


func test_sorted_by_order_fields() -> void:
	for i in c.species.size():
		assert_eq(int(c.species[i]["album_order"]), i + 1)
	assert_eq(String(c.flowers[0]["id"]), "sweet_clover")
	assert_eq(String(c.phases[0]["id"]), "dawn")
	assert_eq(String(c.beds[0]["id"]), "bed_1")


func test_price_ladders_match_gdd_table() -> void:
	# GDD §5.2 full ladders (first, second, last copy).
	assert_eq(c.price(&"sweet_clover", 0), 15)
	assert_eq(c.price(&"sweet_clover", 1), 17)
	assert_eq(c.price(&"sweet_clover", 9), 35)
	assert_eq(c.price(&"moonbloom", 9), 354)
	assert_eq(c.price(&"wind_chime", 0), 190)
	assert_eq(c.price(&"wind_chime", 9), 527)
	var total := 0
	for f: Dictionary in c.flowers:
		for n in int(f["max_copies"]):
			total += c.price(StringName(f["id"]), n)
	for d: Dictionary in c.decor:
		for n in int(d["max_copies"]):
			total += c.price(StringName(d["id"]), n)
	assert_eq(total, 19461, "catalogue total (GDD §5.2)")


func test_every_reference_resolves() -> void:
	for s: Dictionary in c.species:
		assert_true(c.spots_by_id.has(StringName(s["favourite_spot"])))
		assert_true(c.entries_by_id.has(StringName(s["entry"])))
		for r: Dictionary in s["requires"]:
			assert_true(c.item_kind.has(StringName(r["item"])), "requires %s" % r["item"])
		var rig: Dictionary = s["rig"]
		for slot: String in ["fur", "fur_2", "belly", "accent"]:
			assert_true((c.palettes["creatures"]["tokens"] as Dictionary).has(String(rig[slot])), "token %s" % rig[slot])
	for f: Dictionary in c.flowers:
		assert_true((c.palettes["flora"]["flowers"] as Dictionary).has(String(f["petal_token"])))
	for d: Dictionary in c.decor:
		assert_true(c.anchors_by_decor.has(StringName(d["anchor"])))
		assert_eq((c.anchors_by_decor[StringName(d["anchor"])]["positions"] as Array).size(), int(d["max_copies"]),
			"one anchor position per copy")


func test_beds_hold_every_flower_copy() -> void:
	var stems := 0
	for b: Dictionary in c.beds:
		stems += mini(int(b["capacity"]), (b["stems"] as Array).size())
	var copies := 0
	for f: Dictionary in c.flowers:
		copies += int(f["max_copies"])
	assert_eq(stems, copies, "GDD §2.4: planting can never dead-end")


func test_hearts_thresholds() -> void:
	assert_eq(c.hearts_for(0), 0)
	assert_eq(c.hearts_for(3), 1)
	assert_eq(c.hearts_for(39), 4)
	assert_eq(c.hearts_for(40), 5)


func test_other_data_files_are_indexed() -> void:
	var tod: Dictionary = c.palettes["tod"]
	var pals: Dictionary = tod["palettes"]
	var springs: Dictionary = c.motion["springs"]
	var time: Dictionary = c.motion["time"]
	var rig_species: Dictionary = c.creature_rig["species"]
	assert_true(pals.has("golden"))
	assert_true(springs.has("jelly"))
	assert_eq(int(time["g_time_wrap_s"]), 600)
	assert_true(rig_species.has("moonpuff"))
	assert_eq(c.season_for_world_day(0), &"spring")
	assert_eq(c.season_for_world_day(100), &"spring")


func test_broken_documents_are_reported_not_crashing() -> void:
	var docs := c.raw.duplicate(true)
	(docs["species"]["species"][0] as Dictionary)["favourite_spot"] = "nowhere"
	var broken := GameContent.from_documents(docs)
	assert_false(broken.is_valid())
	assert_true(", ".join(broken.errors).contains("nowhere"))
