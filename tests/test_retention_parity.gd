extends GutTest
## Offline parity with the reference sim (GDD §13.9): a scripted schedule with no world-RNG draws
## (tools/sim/economy_sim.py parity_ops) run through the real WorldSim must reproduce the
## reference's retention state after every step: affection and the 20 h rest, hearts, story
## postcards and the ♥4 wait, nests, mystery open / debut-ok times, every sign appear_t, clues,
## cousin debuts, and every scene roll, pick and cast.
##
## Regenerate the fixture after a rule or data change:
##   python3 tools/sim/economy_sim.py --parity-export tests/fixtures/retention_parity.json

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const FIXTURE := "res://tests/fixtures/retention_parity.json"
## Godot's JSON number parser may be 1 ulp off (docs/ARCHITECTURE.md §6); times are < 1e6 s.
const EPS := 1e-6
const VISIT_STAY_S := 3600.0  # tools/sim/economy_sim.py parity_trace stay
const STEM_BED := "bed_1"

var c: GameContent
var trace: Dictionary


func before_all() -> void:
	c = GameContent.load_from_dir()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	trace = parsed if parsed is Dictionary else {}


## The parity world: local time = t + install_local_s (the reference's clock), no scripted
## onboarding and no Poisson visitors, so only the scripted ops act.
static func parity_sim(content: GameContent, seed: int, install_local_s: float) -> WorldSim:
	return RetentionTestUtil.quiet_sim(content, seed, install_local_s)


## Applies one parity op (the reference's run of the same op is tools/sim/economy_sim.py
## parity_trace). Returns the scene result for "return" ops, else {}.
static func apply_op(sim: WorldSim, content: GameContent, op: Dictionary) -> Dictionary:
	var t := float(op["t"])
	sim.advance(maxf(t, sim.state.t))
	match String(op["op"]):
		"visit":
			sim._arrive(t, StringName(op["species"]), VISIT_STAY_S, 0, false)
			sim.state.present.clear()
			sim.mark_dirty()
		"pet":
			for i in int(op["n"]):
				sim._add_affection(StringName(op["species"]), 1, t)
		"items":
			_set_items(sim, content, op)
			sim.retention.check_mysteries(sim, t)
		"tap_signs":
			while true:
				var vis := sim.retention.visible_signs(sim)
				if vis.is_empty():
					break
				for s: Dictionary in vis:
					sim.retention.tap_sign(sim, String(s["key"]))
		"return":
			for sp: Variant in op["present"]:
				sim.state.present.append({"species": String(sp), "arrive_t": t, "depart_t": INF, "gift_dew": 0,
					"gift_item": "", "boat_credit": true, "pet_credit": true, "scripted": false, "greeter": false,
					"cousin": ""})
			var prof := {}
			for row: Variant in op["profile"]:
				var r: Array = row
				prof["%s|%s" % [r[0], r[1]]] = float(r[2])
			var r_before := sim.state.scene_returns
			sim.retention.on_return(sim, float(op["prev_end"]), t, prof)
			var out := {}
			if sim.state.scene_returns > r_before:
				out = {"r": sim.state.scene_returns, "scene": null, "cast": []}
				if not sim.state.pending_scene.is_empty():
					out["scene"] = String(sim.state.pending_scene["scene"])
					out["cast"] = (sim.state.pending_scene["cast"] as Array).duplicate()
					sim.retention.tap_scene(sim)
			sim.state.present.clear()
			sim.mark_dirty()
			return out
	return {}


static func _set_items(sim: WorldSim, content: GameContent, op: Dictionary) -> void:
	var st := sim.state
	st.stems.clear()
	st.owned.clear()
	var bloomed: Dictionary = op["bloomed"]
	for f: Dictionary in content.flowers:
		var n := int(bloomed.get(String(f["id"]), 0))
		for i in n:
			st.stems.append({"flower": String(f["id"]), "bed": STEM_BED, "slot": i, "planted_t": -1.0e7,
				"tutorial": false, "stage": WorldSim.STAGE_BLOOM})
		if n > 0:
			st.owned[String(f["id"])] = n
	var owned: Dictionary = op["owned"]
	for id: Variant in owned:
		st.owned[String(id)] = int(owned[id])
	st.boats = int(op.get("boats", st.boats))
	sim._rebuild_caches()


func test_fixture_is_present_and_matches_the_data() -> void:
	assert_false(trace.is_empty(), "parity fixture loads")
	assert_eq((trace["ops"] as Array).size(), (trace["steps"] as Array).size())
	assert_gt((trace["ops"] as Array).size(), 40, "a long scripted schedule")


func test_scripted_schedule_matches_the_reference_sim() -> void:
	var sim := parity_sim(c, int(trace["seed"]), float(trace["install_local_s"]))
	var ops: Array = trace["ops"]
	var steps: Array = trace["steps"]
	var scenes_checked := 0
	for i in ops.size():
		var op: Dictionary = ops[i]
		var exp: Dictionary = steps[i]
		var label := "step %d (%s @ %s)" % [i, op["op"], op["t"]]
		var got := apply_op(sim, c, op)
		_check_step(sim, exp, label)
		var exp_scene: Variant = exp["scene"]
		if exp_scene is Dictionary:
			var es: Dictionary = exp_scene
			assert_eq(int(got.get("r", -1)), int(es["r"]), "%s: return index" % label)
			assert_eq(str(got.get("scene", null)), str(es["scene"]), "%s: scene pick" % label)
			assert_eq(JSON.stringify(got.get("cast", [])), JSON.stringify(es["cast"]), "%s: cast" % label)
			scenes_checked += 1
		else:
			assert_true(got.is_empty(), "%s: not a qualifying return" % label)
	assert_gt(scenes_checked, 15, "scene rolls compared")


func _check_step(sim: WorldSim, exp: Dictionary, label: String) -> void:
	var st := sim.state
	for sp: String in exp["hearts"]:
		assert_eq(sim.hearts_of(StringName(sp)), int(exp["hearts"][sp]), "%s: hearts %s" % [label, sp])
		assert_eq(sim.affection_of(StringName(sp)), int(exp["affection"][sp]), "%s: affection %s" % [label, sp])
	_assert_times(st.visit_aff_t, exp["visit_aff_t"], "%s: visit rest" % label)
	var myst: Dictionary = exp["mysteries"]
	assert_eq(st.mysteries.size(), myst.size(), "%s: open mysteries %s" % [label, st.mysteries.keys()])
	for id: String in myst:
		var m: Dictionary = st.mysteries.get(id, {})
		assert_false(m.is_empty(), "%s: mystery %s open" % [label, id])
		if m.is_empty():
			continue
		assert_almost_eq(float(m["open_t"]), float(myst[id][0]), EPS, "%s: %s open_t" % [label, id])
		assert_almost_eq(float(m["ok_t"]), float(myst[id][1]), EPS, "%s: %s ok_t" % [label, id])
	var want_signs := {}
	for row: Variant in exp["signs"]:
		var r: Array = row
		want_signs["%s/%d" % [r[0], int(r[1])]] = float(r[2])
	assert_eq(st.signs.size(), want_signs.size(), "%s: waiting signs" % label)
	for s: Dictionary in st.signs:
		var key := RetentionRules.sign_key(s)
		assert_true(want_signs.has(key), "%s: sign %s expected" % [label, key])
		assert_almost_eq(float(s["appear_t"]), float(want_signs.get(key, -1.0)), EPS, "%s: %s appear_t" % [label, key])
	var clues := 0
	for m: String in st.clues:
		clues += sim.retention.clue_count(sim, m)
	assert_eq(clues, int(exp["clues"]), "%s: clues" % label)
	var stories: Array[String] = []
	for p: Dictionary in st.postcards:
		if String(p["id"]).contains("_h"):
			stories.append(String(p["id"]))
	stories.sort()
	assert_eq(JSON.stringify(stories), JSON.stringify(exp["story_postcards"]), "%s: story postcards" % label)
	var waiting := st.postcards_waiting.duplicate()
	waiting.sort()
	assert_eq(JSON.stringify(waiting), JSON.stringify(exp["waiting"]), "%s: waiting postcards" % label)
	var nests := {}
	for sp: String in st.nests:
		nests[sp] = float((st.nests[sp] as Dictionary)["built_t"])
	_assert_times(nests, exp["nests"], "%s: nests" % label)
	_assert_times(st.variants_met, exp["cousins"], "%s: cousins" % label)


func _assert_times(got: Dictionary, want: Dictionary, label: String) -> void:
	assert_eq(got.size(), want.size(), "%s: %s vs %s" % [label, got.keys(), want.keys()])
	for k: String in want:
		assert_almost_eq(float(got.get(k, -1.0)), float(want[k]), EPS, "%s: %s" % [label, k])
