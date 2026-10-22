extends GutTest
## Save format and crash safety (synthesis D12, docs/ARCHITECTURE.md §6): round trip, checksum,
## corrupt-file fallback to .bak / orphaned .tmp, schema handling, type coercion.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const DIR := "user://test_saves"
const DAY := 86400.0

var c: GameContent
var path: String
var store: SaveStore


func before_all() -> void:
	c = GameContent.load_from_dir()


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	path = "%s/save_%d.json" % [DIR, randi()]
	store = SaveStore.new(path, func(w: Dictionary) -> Dictionary: return WorldState.from_dict(w).to_dict())


func after_each() -> void:
	AtomicFile.remove_all(path)


func _played_world(seed: int) -> WorldSim:
	var sim := WorldSim.new_game(c, seed, 1792454400.0 + 20.0 * 3600.0, 25200.0)
	sim.advance(10.0)
	sim.tap_tutorial_seed()
	sim.advance(2.0 * DAY)
	sim.collect()
	sim.buy_flower(&"sweet_clover")
	sim.set_custom_name(&"puffmoss", "Bơ Bơ")
	sim.advance(2.5 * DAY)
	sim.drain_events()
	return sim


func test_round_trip_is_lossless() -> void:
	var sim := _played_world(1)
	var world := sim.state.to_dict()
	assert_eq(store.write(world, 1792700000.25, "0.1.0"), OK)
	var res := store.read()
	assert_true(bool(res["ok"]), str(res.get("error")))
	assert_eq(res["source"], SaveStore.SOURCE_MAIN)
	assert_eq(float(res["saved_at_unix"]), 1792700000.25)
	var loaded: Dictionary = res["world"]
	assert_eq(TestUtil.canonical(loaded), TestUtil.canonical(world), "every field round-trips")
	var back := WorldState.from_dict(loaded)
	assert_eq(back.rng_state, sim.state.rng_state, "64-bit RNG state survives (stored as a string)")
	assert_eq(back.install_seed, sim.state.install_seed)
	assert_eq(String(back.names["puffmoss"]), "Bơ Bơ")


func test_second_write_keeps_previous_as_backup() -> void:
	var a := _played_world(2).state.to_dict()
	var b := _played_world(3).state.to_dict()
	assert_eq(store.write(a, 100.0, "0.1.0"), OK)
	assert_eq(store.write(b, 200.0, "0.1.0"), OK)
	assert_true(FileAccess.file_exists(path + AtomicFile.BAK_SUFFIX))
	assert_false(FileAccess.file_exists(path + AtomicFile.TMP_SUFFIX), "temp file renamed away")
	assert_eq(float(store.read()["saved_at_unix"]), 200.0)


func test_corrupt_main_falls_back_to_backup() -> void:
	var a := _played_world(4).state.to_dict()
	assert_eq(store.write(a, 100.0, "0.1.0"), OK)
	assert_eq(store.write(_played_world(5).state.to_dict(), 200.0, "0.1.0"), OK)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{\"format\": \"mossling-meadow-save\", \"schema\": 1, \"world\": {tru")  # truncated write
	f.close()
	var res := store.read()
	assert_true(bool(res["ok"]))
	assert_eq(res["source"], SaveStore.SOURCE_BACKUP)
	assert_eq(float(res["saved_at_unix"]), 100.0)
	var loaded: Dictionary = res["world"]
	assert_eq(TestUtil.canonical(loaded), TestUtil.canonical(a))
	assert_eq((res["tried"] as Array).size(), 1, "the broken main file is reported")


func test_checksum_mismatch_is_treated_as_corrupt() -> void:
	var a := _played_world(6).state.to_dict()
	assert_eq(store.write(a, 100.0, "0.1.0"), OK)
	assert_eq(store.write(a, 200.0, "0.1.0"), OK)
	var text := FileAccess.get_file_as_string(path)
	var doc: Dictionary = JSON.parse_string(text)
	(doc["world"] as Dictionary)["dew"] = 99999  # a bit flip / hand edit that still parses
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "\t", true, true))
	f.close()
	var res := store.read()
	assert_eq(res["source"], SaveStore.SOURCE_BACKUP)
	var loaded: Dictionary = res["world"]
	assert_ne(int(loaded["dew"]), 99999)


func test_orphaned_temp_file_is_used_when_main_is_missing() -> void:
	var a := _played_world(7).state.to_dict()
	assert_eq(store.write(a, 100.0, "0.1.0"), OK)
	# Simulate a crash between "main -> .bak" and ".tmp -> main".
	DirAccess.rename_absolute(path, path + AtomicFile.TMP_SUFFIX)
	var res := store.read()
	assert_true(bool(res["ok"]))
	assert_eq(res["source"], SaveStore.SOURCE_TMP)


func test_no_file_and_garbage_files() -> void:
	assert_false(bool(store.read()["ok"]))
	assert_eq(store.read()["source"], SaveStore.SOURCE_NONE)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("not json at all")
	f.close()
	assert_false(bool(store.read()["ok"]))


func test_future_schema_is_refused_not_misread() -> void:
	var text := store.encode(_played_world(8).state.to_dict(), 1.0, "9.9")
	var doc: Dictionary = JSON.parse_string(text)
	doc["schema"] = SaveStore.SCHEMA + 1
	var res := store.decode(JSON.stringify(doc))
	assert_false(bool(res["ok"]))
	assert_string_contains(String(res["error"]), "unsupported schema")


func test_world_state_coerces_bad_types() -> void:
	var s := WorldState.from_dict({"dew": "12", "t": -5, "basket": [{"species": 3, "dew": "7"}, "junk"],
		"owned": {"sweet_clover": -2}, "seed_planted": 1})
	assert_eq(s.dew, 12)
	assert_eq(s.t, 0.0, "the world clock is never negative")
	assert_eq(s.basket.size(), 1)
	assert_eq(String(s.basket[0]["species"]), "3")
	assert_eq(int(s.basket[0]["dew"]), 7)
	assert_eq(int(s.owned["sweet_clover"]), 0, "counts are never negative")
	assert_true(s.seed_planted)


func test_save_service_uses_registered_provider() -> void:
	var was := SaveService.enabled
	SaveService.enabled = false
	assert_false(SaveService.save_now(&"test"), "disabled service writes nothing")
	SaveService.enabled = was
