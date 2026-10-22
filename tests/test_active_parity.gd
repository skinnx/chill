extends GutTest
## Active Play v1 parity with the reference sim (GDD §14.11 a8): a scripted schedule generated
## online from tools/sim/economy_sim.py (active_parity_trace: foreground wish checks with the sky
## pinned, visits, departures, help through the action each wish asks for, gathering, brewing,
## offering, two gaps past the 20 h rests) replayed through the real WorldSim. After every op the
## wish list (species, wish, open/held, opened_t), the hash index, the gaps, the wish and tea
## rests, stamps, grants, affection, the petal anchors and jars, the recipe book, the tray, cups
## offered and the wallet must match: wish spawns are bit-exact through the retention hash.
##
## Regenerate the fixture after a rule or data change:
##   python3 tools/sim/economy_sim.py --active-parity-export tests/fixtures/active_parity.json

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const FIXTURE := "res://tests/fixtures/active_parity.json"
## Godot's JSON number parser may be 1 ulp off (docs/ARCHITECTURE.md §6); times are < 1e6 s.
const EPS := 1e-6

var c: GameContent
var trace: Dictionary


func before_all() -> void:
	c = GameContent.load_from_dir()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	trace = parsed if parsed is Dictionary else {}


func test_fixture_is_present_and_covers_every_feature() -> void:
	assert_false(trace.is_empty(), "active parity fixture loads")
	var ops: Array = trace["ops"]
	assert_eq(ops.size(), (trace["steps"] as Array).size())
	var kinds := {}
	for op: Dictionary in ops:
		kinds[String(op["op"])] = true
		if String(op["op"]) == "act":
			kinds["act:%s" % op["kind"]] = true
	for k: String in ["check", "arrive", "depart", "act", "harvest", "brew", "offer", "act:pet", "act:boat",
			"act:bed_tap", "act:tap_creature"]:
		assert_true(kinds.has(k), "the schedule exercises %s" % k)
	var last: Dictionary = (trace["steps"] as Array).back()
	assert_gt(int(last["wishes_granted"]), 20, "many wishes granted")
	assert_gt((last["recipes_found"] as Array).size(), 10, "many recipes found")


func test_scripted_schedule_matches_the_reference_sim() -> void:
	var sim := ActiveTestUtil.quiet_sim(c, int(trace["seed"]), float(trace["install_local_s"]))
	var ops: Array = trace["ops"]
	var steps: Array = trace["steps"]
	var spawned := 0
	for i in ops.size():
		var op: Dictionary = ops[i]
		var label := "step %d (%s @ %s)" % [i, op["op"], op["t"]]
		var before := sim.state.wishes.size()
		_apply(sim, op)
		if String(op["op"]) == "check" and sim.state.wishes.size() > before:
			spawned += 1
		if not _check_step(sim, steps[i], label):
			return  # the first divergence is the useful one
	assert_gt(spawned, 30, "wish spawns compared bit-exactly")


func _apply(sim: WorldSim, op: Dictionary) -> void:
	var t := float(op["t"])
	var stay := float(trace["stay_s"])
	match String(op["op"]):
		"items":
			var it: Dictionary = trace["items"]
			sim.advance(maxf(t, sim.state.t))
			ActiveTestUtil.set_garden(sim, c, it["bloomed"], it["owned"], float(it["bloom_t"]))
			sim.state.dew = int(it["dew"])
		"arrive":
			sim.advance(maxf(t, sim.state.t))
			sim._arrive(t, StringName(op["species"]), stay, 0, false)
		"depart":
			ActiveTestUtil.depart(sim, StringName(op["species"]), t)
		"check":
			ActiveTestUtil.check(sim, t, StringName(op["phase"]), StringName(op["weather"]))
		"act":
			ActiveTestUtil.act(sim, StringName(op["kind"]), op.get("args", {}), t)
		"harvest":
			sim.advance(maxf(t, sim.state.t))
			sim.active.tea.harvest_bed(sim, &"", t)
		"brew":
			ActiveTestUtil.brew(sim, op["petals"], int(op["drops"]), t)
		"offer":
			sim.advance(maxf(t, sim.state.t))
			sim.active.tea.offer(sim, int(op["index"]), StringName(op["species"]), t)
	sim.drain_events()


func _check_step(sim: WorldSim, exp: Dictionary, label: String) -> bool:
	var st := sim.state
	var ok := true
	var got_w: Array = []
	for w: Dictionary in st.wishes:
		got_w.append([String(w["species"]), String(w["wish"]), String(w["state"]), bool(w["placed"])])
	var want_w: Array = []
	for row: Variant in exp["wishes"]:
		var r: Array = row
		want_w.append([String(r[0]), String(r[1]), String(r[2]), bool(r[3])])
	ok = _eq(JSON.stringify(got_w), JSON.stringify(want_w), "%s: wishes" % label) and ok
	if ok:
		for i in st.wishes.size():
			ok = _near(float(st.wishes[i]["opened_t"]), float(exp["wishes"][i][4]), "%s: opened_t %d" % [label, i]) and ok
	ok = _eq(st.wish_checks, int(exp["wish_checks"]), "%s: wish_checks" % label) and ok
	var last: Variant = exp["wish_last_t"]
	ok = _near(st.wish_last_t, WorldState.NEVER_T if last == null else float(last), "%s: wish_last_t" % label) and ok
	ok = _times(st.wish_friend_t, exp["wish_friend_t"], "%s: wish_friend_t" % label) and ok
	ok = _times(st.wish_aff_t, exp["wish_aff_t"], "%s: wish_aff_t" % label) and ok
	var stamps: Array[String] = []
	for sp: String in st.wish_stamps:
		for w: StringName in sim.active.wishes.stamps(sim, StringName(sp)):
			stamps.append("%s/%s" % [sp, w])
	stamps.sort()
	ok = _eq(JSON.stringify(stamps), JSON.stringify(exp["stamps"]), "%s: stamps" % label) and ok
	ok = _eq(st.wishes_granted, int(exp["wishes_granted"]), "%s: wishes_granted" % label) and ok
	ok = _eq(st.wish_tutorial_done, bool(exp["tutorial_done"]), "%s: tutorial" % label) and ok
	for sp: String in exp["affection"]:
		ok = _eq(sim.affection_of(StringName(sp)), int(exp["affection"][sp]), "%s: affection %s" % [label, sp]) and ok
	ok = _eq(st.tea_unlocked, bool(exp["tea_unlocked"]), "%s: tea_unlocked" % label) and ok
	var pantry := {}
	for f: String in st.pantry:
		if int(st.pantry[f]) != 0:
			pantry[f] = int(st.pantry[f])
	ok = _eq(TestUtil.canonical(pantry), TestUtil.canonical(_ints(exp["pantry"])), "%s: pantry" % label) and ok
	var anchors := {}
	for i in st.stems.size():
		var f := String(st.stems[i]["flower"])
		if not anchors.has(f):
			anchors[f] = []
		(anchors[f] as Array).append(sim.active.tea.anchor(sim, i))
	var want_a: Dictionary = exp["petal_anchors"]
	ok = _eq(anchors.size(), want_a.size(), "%s: anchored flowers" % label) and ok
	for f: String in want_a:
		var g: Array = anchors.get(f, [])
		var e: Array = want_a[f]
		ok = _eq(g.size(), e.size(), "%s: %s stems" % [label, f]) and ok
		for j in mini(g.size(), e.size()):
			ok = _near(float(g[j]), float(e[j]), "%s: %s anchor %d" % [label, f, j]) and ok
	var found: Array[String] = []
	for r: String in st.recipes_found:
		found.append(r)
	found.sort()
	ok = _eq(JSON.stringify(found), JSON.stringify(exp["recipes_found"]), "%s: recipes" % label) and ok
	var tray: Array[String] = []
	for cup: Dictionary in st.tray:
		tray.append(String(cup["recipe"]))
	ok = _eq(JSON.stringify(tray), JSON.stringify(exp["tray"]), "%s: tray" % label) and ok
	ok = _times(st.tea_aff_t, exp["tea_aff_t"], "%s: tea_aff_t" % label) and ok
	ok = _eq(st.cups_offered, int(exp["cups_offered"]), "%s: cups offered" % label) and ok
	ok = _eq(st.dew, int(exp["dew"]), "%s: dew" % label) and ok
	var present: Array[String] = []
	for p: Dictionary in st.present:
		present.append(String(p["species"]))
	present.sort()
	ok = _eq(JSON.stringify(present), JSON.stringify(exp["present"]), "%s: present" % label) and ok
	return ok


static func _ints(d: Dictionary) -> Dictionary:
	var out := {}
	for k: String in d:
		out[k] = int(d[k])
	return out


func _eq(got: Variant, want: Variant, msg: String) -> bool:
	assert_eq(got, want, msg)
	return got == want


func _near(got: float, want: float, msg: String) -> bool:
	var ok := absf(got - want) <= EPS * maxf(1.0, absf(want))
	assert_true(ok, "%s: %s vs %s" % [msg, got, want])
	return ok


func _times(got: Dictionary, want: Dictionary, msg: String) -> bool:
	var ok := _eq(got.size(), want.size(), "%s: %s vs %s" % [msg, got.keys(), want.keys()])
	for k: String in want:
		ok = _near(float(got.get(k, -1.0)), float(want[k]), "%s: %s" % [msg, k]) and ok
	return ok
