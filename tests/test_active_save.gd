extends GutTest
## Save schema 3 (GDD §14.9): forward migration from a REAL schema-2 save written by the
## pre-Active code (tests/fixtures/save_schema2.json, generated before the schema bump), nothing
## lost, fixed décor anchors -> free positions (on screen within 0.5 px; only the two pinwheels
## under the tea nook nudged), the tea unlock, the whole chain from schema 1, the .bak fallback,
## a lossless round trip of every Active Play field, and type coercion.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const FIXTURE := "res://tests/fixtures/save_schema2.json"
const FIXTURE_V1 := "res://tests/fixtures/save_schema1.json"
const DIR := "user://test_active_saves"
const DAY := 86400.0
## On-screen tolerance of the migration (GDD §14.9 step 1).
const MAX_SHIFT_PX := 0.5
const NUDGED: Array[String] = ["leaf_pinwheel#4", "leaf_pinwheel#8"]

var c: GameContent
var path: String
var store: SaveStore
var v2_text: String
var v2_world: Dictionary


func before_all() -> void:
	c = GameContent.load_from_dir()
	v2_text = FileAccess.get_file_as_string(FIXTURE)
	var doc: Dictionary = JSON.parse_string(v2_text)
	v2_world = doc["world"]


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


func _migrated_sim() -> WorldSim:
	_write_raw(path, v2_text)
	var res := store.read()
	assert_true(bool(res["ok"]), str(res.get("error")))
	return WorldSim.new(c, WorldState.from_dict(res["world"]))


## Where DecorLayer drew copy [param n] of [param set_id] before free placement (design px).
func _legacy_px(set_id: StringName, n: int) -> Vector2:
	var pos: Array = (c.anchors_by_decor[set_id] as Dictionary)["positions"]
	var q: Array = pos[0 if set_id == DecorPlacementRules.CAIRN else n]
	var p := GardenRules.frame_to_px(c, Vector2(float(q[0]), float(q[1])))
	if set_id == DecorPlacementRules.LANTERN:
		p.x += DecorPlacementRules.legacy_lantern_jitter_px(n)
	return p


func test_fixture_is_a_real_schema_two_save() -> void:
	var doc: Dictionary = JSON.parse_string(v2_text)
	assert_eq(int(doc["schema"]), 2)
	assert_true(SaveStore.SCHEMA >= 3, "Active Play v1 bumped the schema by one (tips_seen to 4)")
	assert_true(SaveStore.MIGRATABLE.has(2))
	assert_false(v2_world.has("decor_layout") or v2_world.has("wishes") or v2_world.has("pantry"), "no active fields yet")
	assert_true(v2_world.has("nests") and v2_world.has("signs"), "a real retention-era save")
	var owned: Dictionary = v2_world["owned"]
	assert_true(int(owned.get("leaf_pinwheel", 0)) >= 9, "pinwheel copies 4 and 8 exist (the tea-nook overlap)")
	assert_true(int(owned.get("pebble_cairn", 0)) >= 3 and int(owned.get("firefly_lantern", 0)) >= 3)


func test_schema_two_save_migrates_forward_without_losing_anything() -> void:
	_write_raw(path, v2_text)
	var res := store.read()
	assert_true(bool(res["ok"]), str(res.get("error")))
	assert_eq(res["source"], SaveStore.SOURCE_MAIN)
	assert_eq(int(res["schema"]), SaveStore.SCHEMA)
	var w: Dictionary = res["world"]
	var v2_typed := WorldState.from_dict(v2_world).to_dict()
	for key: String in v2_world:
		assert_eq(TestUtil.canonical(w[key]), TestUtil.canonical(v2_typed[key]), "%s kept as it was" % key)
	for key: String in SaveStore.ACTIVE_V1_DEFAULTS:
		assert_true(w.has(key), "%s added" % key)
	assert_eq(int(w["active_v"]), 0, "the content-aware step is still to run")


func test_content_aware_migration_keeps_every_piece_where_it_stood() -> void:
	var before := WorldState.from_dict(v2_world)
	var sim := _migrated_sim()
	var st := sim.state
	assert_eq(st.active_v, WorldState.ACTIVE_VERSION)
	var expected := 0
	for d: Dictionary in c.decor:
		if c.is_movable_decor(StringName(d["id"])):
			expected += int(before.owned.get(String(d["id"]), 0))
	assert_eq(st.decor_layout.size(), expected, "one record per owned movable copy")
	var ids := {}
	var ctx := sim.active.context(sim)
	for p: Dictionary in st.decor_layout:
		var id := String(p["id"])
		assert_false(ids.has(id), "unique id %s" % id)
		ids[id] = true
		assert_false(bool(p["stored"]), "%s placed" % id)
		assert_eq(int(p["rot"]), 0, "%s rot 0" % id)
		var set_id := StringName(p["set"])
		assert_ne(set_id, &"wind_chime", "the chime stays on its branch")
		var n := int(id.get_slice("#", 1))
		var now := GardenRules.frame_to_px(c, Vector2(float(p["x"]), float(p["y"])))
		var shift := now.distance_to(_legacy_px(set_id, n))
		if NUDGED.has(id):
			assert_gt(shift, MAX_SHIFT_PX, "%s nudged out of the tea nook" % id)
			assert_lt(shift / 3.0, 48.0 + 1e-3, "%s nudged within 48 dp (%.1f dp)" % [id, shift / 3.0])
			assert_eq(sim.active.decor.validate_hard(set_id, Vector2(float(p["x"]), float(p["y"])), ctx),
				DecorPlacementRules.VALID, "%s now clear of the hard exclusions" % id)
		else:
			assert_lt(shift, MAX_SHIFT_PX, "%s did not move on screen (%.3f px)" % [id, shift])
		if set_id == DecorPlacementRules.CAIRN:
			assert_eq(String(p["stack"]), "" if n == 0 else "pebble_cairn#0", "one cairn stack in copy order")
			assert_eq(int(p["level"]), n)
	assert_eq(TestUtil.canonical(st.owned), TestUtil.canonical(before.owned), "owned untouched")
	assert_eq(TestUtil.canonical(st.affection), TestUtil.canonical(before.affection), "affection untouched")
	assert_eq(str(st.rng_state), str(before.rng_state), "the world RNG stream is untouched")
	assert_eq(TestUtil.canonical(st.nests), TestUtil.canonical(before.nests), "retention untouched")
	assert_true(st.wishes.is_empty() and not st.wish_tutorial_done, "no wish open; the teaching wish still to come")
	assert_true(st.tea_unlocked, "onboarding done and stems bloom: the nook wakes")
	assert_true(st.petal_from_t.is_empty(), "petal anchors absent: full stems for a returning player")
	assert_gt(sim.active.tea.petals_ready(sim, &"", st.t), 0, "a generous first harvest")


func test_migration_is_idempotent_and_survives_a_round_trip() -> void:
	var sim := _migrated_sim()
	var layout := TestUtil.canonical(sim.state.decor_layout)
	var again := WorldSim.new(c, WorldState.from_dict(sim.state.to_dict()))
	assert_eq(TestUtil.canonical(again.state.decor_layout), layout, "a second load changes nothing")
	assert_eq(store.write(again.state.to_dict(), 1.0e9, "0.3.0"), OK)
	var res := store.read()
	assert_eq(int(res["schema"]), SaveStore.SCHEMA)
	var third := WorldSim.new(c, WorldState.from_dict(res["world"]))
	assert_eq(TestUtil.canonical(third.state.decor_layout), layout)


func test_schema_one_save_migrates_through_to_schema_three() -> void:
	_write_raw(path, FileAccess.get_file_as_string(FIXTURE_V1))
	var res := store.read()
	assert_true(bool(res["ok"]), str(res.get("error")))
	assert_eq(int(res["schema"]), SaveStore.SCHEMA)
	var sim := WorldSim.new(c, WorldState.from_dict(res["world"]))
	assert_eq(sim.state.retention_v, WorldState.RETENTION_VERSION)
	assert_eq(sim.state.active_v, WorldState.ACTIVE_VERSION)
	var movable := 0
	for d: Dictionary in c.decor:
		if c.is_movable_decor(StringName(d["id"])):
			movable += sim.owned_count(StringName(d["id"]))
	assert_eq(sim.state.decor_layout.size(), movable)


func test_old_backup_is_migrated_when_the_main_file_is_corrupt() -> void:
	_write_raw(path, "{\"format\": \"mossling-meadow-save\", \"schema\": 3, \"world\": {tru")
	_write_raw(path + ".bak", v2_text)
	var res := store.read()
	assert_true(bool(res["ok"]), str(res.get("error")))
	assert_eq(res["source"], SaveStore.SOURCE_BACKUP)
	assert_eq(int(res["schema"]), SaveStore.SCHEMA)
	var sim := WorldSim.new(c, WorldState.from_dict(res["world"]))
	assert_gt(sim.state.decor_layout.size(), 0, "the .bak migrates the same way")


func test_migration_only_adds_and_never_overwrites() -> void:
	var w := {"t": 5.0, "wishes": [{"species": "puffmoss", "wish": "cuddle"}], "pantry": {"sweet_clover": 3}}
	var m := SaveStore.migrate(2, w)
	assert_eq((m["wishes"] as Array).size(), 1, "an existing value is never overwritten")
	assert_eq(int((m["pantry"] as Dictionary)["sweet_clover"]), 3)
	assert_eq(int(m["active_v"]), 0)
	assert_true(m.has("decor_layout") and m.has("tea_aff_t") and m.has("wish_stamps"))
	assert_eq(TestUtil.canonical(SaveStore.migrate(2, m)), TestUtil.canonical(m), "idempotent")


func test_every_active_field_round_trips() -> void:
	var sim := _migrated_sim()
	var st := sim.state
	st.wishes = [{"species": "puffmoss", "wish": "clover_tea", "opened_t": 12.5, "state": "held", "taps": 2,
		"placed": true}]
	st.wish_checks = 17
	st.wish_fg_s = 33.25
	st.wish_last_t = 101.0
	st.wish_friend_t = {"puffmoss": 101.0}
	st.wish_visit_count = {"puffmoss": {"arrive_t": 90.0, "n": 1}}
	st.wish_last_id = {"puffmoss": "clover_tea"}
	st.wish_aff_t = {"buttonbud": 5.0}
	st.wish_stamps = {"puffmoss": 5}
	st.wishes_granted = 3
	st.wish_tutorial_done = true
	st.wish_list_seen_t = 77.0
	st.pantry = {"sweet_clover": 4}
	st.petal_from_t = {"bed_1:0": 12.0}
	st.pot = {"petals": ["sweet_clover"], "drops": 1, "stir_deg": 180.0}
	st.tray = [{"recipe": "clover_tea", "made_unix": 1.0e9, "drops": 0, "petals": ["sweet_clover", "sweet_clover"]}]
	st.recipes_found = {"clover_tea": 1.0e9}
	st.tea_prefs_seen = {"puffmoss": ["clover_tea"]}
	st.tea_aff_t = {"puffmoss": 50.0}
	st.teaware_owned = ["daisy_cup"]
	st.teaware_set = {"cup": "daisy_cup"}
	st.cups_offered = 2
	st.tea_flags = {"nook_seen": true}
	var world := st.to_dict()
	assert_eq(store.write(world, 1.0e9, "0.3.0"), OK)
	var res := store.read()
	assert_true(bool(res["ok"]), str(res.get("error")))
	assert_eq(TestUtil.canonical(res["world"]), TestUtil.canonical(world), "every active field round-trips")


func test_hand_edited_active_fields_are_coerced() -> void:
	var w := v2_world.duplicate(true)
	w["wishes"] = [{"species": 5, "wish": "cuddle", "opened_t": "x", "state": "open", "taps": -1}, "junk"]
	w["pantry"] = {"sweet_clover": -4, "bluebell": "3"}
	w["pot"] = {"petals": "nope", "drops": -2, "stir_deg": -90}
	w["decor_layout"] = [{"id": "leaf_pinwheel#0", "set": "leaf_pinwheel", "x": "0.5", "y": 0.42, "rot": 1.0}]
	var s := WorldState.from_dict(w)
	assert_eq(s.wishes.size(), 1, "non-records are dropped")
	assert_eq(String(s.wishes[0]["species"]), "5")
	assert_eq(int(s.pantry["sweet_clover"]), 0, "counts never negative")
	assert_eq(int(s.pantry["bluebell"]), 3)
	assert_eq((s.pot["petals"] as Array).size(), 0)
	assert_eq(int(s.pot["drops"]), 0)
	assert_eq(float(s.pot["stir_deg"]), 0.0)
	assert_eq(typeof(s.decor_layout[0]["x"]), TYPE_FLOAT)
	assert_eq(typeof(s.decor_layout[0]["rot"]), TYPE_INT)


# ------------------------------------------------------------------ schema 4: tips_seen

func test_schema_three_save_gains_empty_tips_seen() -> void:
	assert_eq(SaveStore.SCHEMA, 4, "tips_seen bumped the schema by one")
	assert_true(SaveStore.MIGRATABLE.has(3))
	# a schema-3 file exactly as the Active Play v1 code wrote it: the world without tips_seen
	var sim := _migrated_sim()
	var w := sim.state.to_dict()
	w.erase("tips_seen")
	var doc := {"format": SaveStore.FORMAT, "schema": 3, "app_version": "active-v1", "saved_at_unix": 1.0,
		"sha256": SaveStore.checksum(w), "world": w}
	_write_raw(path, JSON.stringify(doc, "\t", true, true))
	var res := store.read()
	assert_true(bool(res["ok"]), str(res.get("error")))
	assert_eq(int(res["schema"]), SaveStore.SCHEMA)
	var got: Dictionary = res["world"]
	assert_true(got.has("tips_seen") and (got["tips_seen"] as Dictionary).is_empty(), "every tip still to show")
	var before := WorldState.from_dict(w).to_dict()
	before.erase("tips_seen")
	var after := got.duplicate(true)
	after.erase("tips_seen")
	assert_eq(JSON.stringify(after, "", true), JSON.stringify(before, "", true), "nothing else changed")


func test_tips_seen_round_trips_and_coerces() -> void:
	var st := WorldState.new()
	st.tips_seen = {"decor_long_press": true}
	assert_eq(store.write(st.to_dict(), 5.0, "test"), OK)
	var res := store.read()
	assert_true(bool(res["ok"]), str(res.get("error")))
	assert_eq(WorldState.from_dict(res["world"]).tips_seen, {"decor_long_press": true})
	var odd := WorldState.from_dict({"tips_seen": {"a": 1.0, "b": false, "c": true, "d": "yes"}})
	assert_eq(odd.tips_seen, {"a": true, "c": true}, "only shown tips are kept, as true")
	assert_eq(WorldState.from_dict({"tips_seen": [1, 2]}).tips_seen, {}, "a wrong type is ignored")
