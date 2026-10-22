extends GutTest
## Save schema 2 (GDD §13.6): forward migration from a REAL schema-1 save written by the MVP code
## (tests/fixtures/save_schema1.json, generated before the schema bump), nothing lost, the
## content-aware migration steps, lossless round trip of every retention field, the .bak
## fallback with an old file, and type coercion of the new fields.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const FIXTURE := "res://tests/fixtures/save_schema1.json"
const DIR := "user://test_retention_saves"
const DAY := 86400.0

var c: GameContent
var path: String
var store: SaveStore
var v1_text: String
var v1_world: Dictionary


func before_all() -> void:
	c = GameContent.load_from_dir()
	v1_text = FileAccess.get_file_as_string(FIXTURE)
	var doc: Dictionary = JSON.parse_string(v1_text)
	v1_world = doc["world"]


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	path = "%s/save_%d.json" % [DIR, randi()]
	store = SaveStore.new(path, func(w: Dictionary) -> Dictionary: return WorldState.from_dict(w).to_dict())


func after_each() -> void:
	AtomicFile.remove_all(path)


func _write_raw(p: String, text: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _hearts(world: Dictionary, sp: String) -> int:
	return c.hearts_for(int((world["affection"] as Dictionary).get(sp, 0)))


func test_fixture_is_a_real_schema_one_save() -> void:
	var doc: Dictionary = JSON.parse_string(v1_text)
	assert_eq(int(doc["schema"]), 1)
	assert_eq(SaveStore.SCHEMA, 2, "Retention v1 bumped the schema by one")
	assert_false(v1_world.has("nests") or v1_world.has("signs"), "no retention fields yet")
	var spread := {}
	for sp: String in v1_world["affection"]:
		spread[_hearts(v1_world, sp)] = true
	assert_true(spread.size() >= 4, "hearts spread over several levels: %s" % spread)


func test_schema_one_save_migrates_forward_without_losing_anything() -> void:
	_write_raw(path, v1_text)
	var res := store.read()
	assert_true(bool(res["ok"]), str(res.get("error")))
	assert_eq(res["source"], SaveStore.SOURCE_MAIN)
	assert_eq(int(res["schema"]), SaveStore.SCHEMA)
	var w: Dictionary = res["world"]
	# The v1 payload as the v1 code typed it (JSON numbers are floats until coerced).
	var v1_typed := WorldState.from_dict(v1_world).to_dict()
	for key: String in v1_world:
		if key in ["basket", "present"]:
			continue
		assert_eq(TestUtil.canonical(w[key]), TestUtil.canonical(v1_typed[key]), "%s kept as it was" % key)
	for list: String in ["basket", "present"]:
		var old: Array = v1_typed[list]
		var new: Array = w[list]
		assert_eq(new.size(), old.size(), "%s entries kept" % list)
		for i in old.size():
			for k: String in old[i]:
				if (v1_world[list][i] as Dictionary).has(k):
					assert_eq(TestUtil.canonical(new[i][k]), TestUtil.canonical(old[i][k]), "%s[%d].%s" % [list, i, k])
	assert_false((v1_world["basket"] as Array).is_empty(), "the fixture has gifts waiting")
	if not (w["basket"] as Array).is_empty():
		assert_false(bool(w["basket"][0]["signature"]), "basket entries gain signature = false")
	assert_eq(int(w["retention_v"]), 0, "the content-aware steps are still to run")
	for key: String in SaveStore.RETENTION_V1_DEFAULTS:
		assert_true(w.has(key), "new field %s added" % key)


func test_content_aware_migration_steps() -> void:
	_write_raw(path, v1_text)
	var w: Dictionary = store.read()["world"]
	var sim := WorldSim.new(c, WorldState.from_dict(w))
	var st := sim.state
	var events := sim.drain_events()
	assert_eq(st.retention_v, WorldState.RETENTION_VERSION)
	for s: Dictionary in c.species:
		var sp := String(s["id"])
		var h := _hearts(v1_world, sp)
		assert_eq(sim.affection_of(StringName(sp)), int((v1_world["affection"] as Dictionary).get(sp, 0)),
			"affection untouched")
		if h > 0:
			assert_eq(int(st.hearts_seen[sp]), h, "%s: hearts_seen = hearts, nobody re-toasts" % sp)
		assert_eq(st.nests.has(sp), h >= 3, "%s: nest iff ♥3+" % sp)
		if h >= 3:
			assert_eq(float(st.nests[sp]["built_t"]), float(v1_world["t"]), "built at migration time, twigs")
			assert_eq(int(st.nests[sp]["stage"]), 0)
		assert_eq(st.keepsakes.has(sp), h >= 5, "%s: keepsake iff ♥5" % sp)
		if h >= 5:
			var tpl := String(s["postcard_heart5"])
			assert_true(st.postcards.any(func(p: Dictionary) -> bool: return p["template"] == tpl), "%s ♥5 story sent" % sp)
		if h >= 4:
			var tpl4 := String(s["postcard_heart4"])
			var sent := st.postcards.any(func(p: Dictionary) -> bool: return p["template"] == tpl4)
			var waiting := st.postcards_waiting.any(func(id: String) -> bool: return id.begins_with(sp + "_h4"))
			assert_true(sent or waiting, "%s ♥4 story sent or waiting for its buddy" % sp)
	assert_true(st.visit_aff_t.is_empty(), "the 20 h rest starts empty: the next visit counts")
	assert_true(st.postcards.size() >= (v1_world["postcards"] as Array).size(), "postcards only added")
	assert_gt(RetentionTestUtil.count_events(events, WorldSim.EV_NEST_STAGE), 0)
	# Mysteries open at migration for unmet friends whose requires hold.
	var w2 := w.duplicate(true)
	(w2["owned"] as Dictionary)["toadstool_seat"] = 5
	var sim2 := WorldSim.new(c, WorldState.from_dict(w2))
	assert_true(sim2.state.mysteries.has("capling"), "capling's mystery opens at migration")
	assert_eq(float(sim2.state.mysteries["capling"]["open_t"]), float(w2["t"]))
	assert_false(sim2.state.mysteries.has("puffmoss"), "met friends never get one")
	# Runs once: a migrated save reloads without repeating it.
	var again := WorldSim.new(c, WorldState.from_dict(sim2.state.to_dict()))
	assert_false(again.has_events())
	assert_eq(TestUtil.canonical(again.state.to_dict()), TestUtil.canonical(sim2.state.to_dict()))


func test_migrated_world_plays_on_and_round_trips_losslessly() -> void:
	_write_raw(path, v1_text)
	var w: Dictionary = store.read()["world"]
	var sim := WorldSim.new(c, WorldState.from_dict(w))
	var saved_at := float(JSON.parse_string(v1_text)["saved_at_unix"])
	var before := sim.monotone_snapshot()
	sim.catch_up(saved_at + 5.0 * DAY, 0.0, saved_at)
	sim.retention.on_return(sim, float(w["t"]), sim.state.t)
	RetentionTestUtil.tap_all_signs(sim)
	var after := sim.monotone_snapshot()
	for k: String in before:
		if before[k] is Dictionary:
			for key: Variant in before[k]:
				assert_true(int((after[k] as Dictionary).get(key, 0)) >= int(before[k][key]), "%s[%s]" % [k, key])
		else:
			assert_true(float(after[k]) >= float(before[k]) - 1e-9, k)
	var world := sim.state.to_dict()
	assert_eq(store.write(world, saved_at + 5.0 * DAY, "0.2.0"), OK)
	var res := store.read()
	assert_true(bool(res["ok"]), str(res.get("error")))
	assert_eq(int(res["schema"]), 2)
	assert_eq(TestUtil.canonical(res["world"]), TestUtil.canonical(world), "every retention field round-trips")


func test_old_backup_is_migrated_when_the_main_file_is_corrupt() -> void:
	_write_raw(path, "{\"format\": \"mossling-meadow-save\", \"schema\": 2, \"world\": {tru")
	_write_raw(path + ".bak", v1_text)
	var res := store.read()
	assert_true(bool(res["ok"]), str(res.get("error")))
	assert_eq(res["source"], SaveStore.SOURCE_BACKUP)
	assert_eq(int(res["schema"]), 2)
	assert_eq(TestUtil.canonical((res["world"] as Dictionary)["met"]), TestUtil.canonical(v1_world["met"]))


func test_migration_only_adds_and_is_idempotent() -> void:
	var w := {"t": 5.0, "nests": {"puffmoss": {"style": "moss_bowl", "built_t": 1.0, "stage": 2}}, "scene_returns": 7}
	var m := SaveStore.migrate(1, w)
	assert_eq(int(m["scene_returns"]), 7, "an existing value is never overwritten")
	assert_eq(int(m["nests"]["puffmoss"]["stage"]), 2)
	assert_eq(float(m["last_bg_t"]), -1.0)
	assert_false(w.has("signs"), "the input is not mutated")
	assert_eq(SaveStore.migrate(9, w), w, "unknown schemas pass through")


func test_retention_fields_are_coerced_on_load() -> void:
	var s := WorldState.from_dict({
		"nests": "nope", "signs": [{"mystery": "capling", "index": "1", "appear_t": "12.5"}, 3],
		"clues": {"capling": -4}, "scene_returns": -3, "pending_scene": {"scene": "", "cast": ["x"]},
		"memories": [{"scene": "nap_pile", "cast": "puffmoss"}], "postcards_waiting": [5],
		"scene_cast": {"nap_pile": ["a", 2]}, "retention_v": "1",
	})
	assert_true(s.nests.is_empty())
	assert_eq(s.signs.size(), 1)
	assert_eq(int(s.signs[0]["index"]), 1)
	assert_eq(float(s.signs[0]["appear_t"]), 12.5)
	assert_eq(String(s.signs[0]["anchor"]), "")
	assert_eq(int(s.clues["capling"]), 0, "never negative")
	assert_eq(s.scene_returns, 0)
	assert_true(s.pending_scene.is_empty(), "a scene without an id is no scene")
	assert_eq((s.memories[0]["cast"] as Array).size(), 0)
	assert_eq(s.postcards_waiting, ["5"] as Array[String])
	assert_eq(s.scene_cast["nap_pile"], ["a", "2"])
	assert_eq(s.retention_v, 1)
