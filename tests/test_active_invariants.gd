extends GutTest
## Active Play v1 invariants (GDD §14.0 AP1-AP8, §14.10): E1 nothing decreases between sessions
## with the whole active layer in play (wishes, petals, cups, recipes, stamps, teaware, the
## layout), E5 something affordable and something new every session, E6 every displayed value
## (teaware prices and jar counts too) <= display_max, no dew created by tea or wishes, jars never
## over their cap, a 30-day absence keeps every wish, and the QA fixture active_mid.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const DAY := 86400.0
const SIM_DAYS := 12
const PLAYERS := 6

var c: GameContent


func before_all() -> void:
	c = GameContent.load_from_dir()


func test_e1_e5_e6_with_active_play() -> void:
	var sessions := 0
	var helped := 0
	var cups := 0
	var e1 := 0
	var policies := ["gentle", "keen", "greedy", "drain"]
	for i in PLAYERS:
		var p := SimPlayer.new(c, 4242 + i, policies[i % policies.size()], 8.0 + float(i * 3 % 14))
		p.active_play = true
		p.play(p.reference_schedule(SIM_DAYS) if i % 2 == 0 else p.random_schedule(SIM_DAYS))
		sessions += p.sessions
		helped += p.wishes_helped
		cups += p.cups_offered
		e1 += p.e1_violations
		assert_eq(p.e5_no_afford, 0, "E5 affordable (player %d)" % i)
		assert_eq(p.e5_no_new, 0, "E5 something new (player %d)" % i)
		assert_lte(p.max_display, int(c.economy["display_max"]), "E6 (player %d)" % i)
		for f: String in p.sim.state.pantry:
			assert_lte(int(p.sim.state.pantry[f]), p.sim.active.tea.jar_cap(StringName(f)), "jars never over their cap")
		assert_lte(p.sim.state.wishes.size(), int(c.wishes_doc["tuning"]["max_pending"]))
	gut.p("active play: %d sessions, %d wishes helped, %d cups offered" % [sessions, helped, cups])
	assert_eq(e1, 0, "E1: nothing shrank between sessions")
	assert_gt(helped, 10, "wishes were granted along the way")
	assert_gt(cups, 10, "cups were offered along the way")


func test_tea_and_wishes_create_no_dew() -> void:
	var sim := ActiveTestUtil.quiet_sim(c)
	ActiveTestUtil.set_garden(sim, c, {&"sweet_clover": 4, &"button_daisy": 2}, {&"wind_chime": 1})
	sim.advance(1000.0)
	sim.state.dew = 50
	sim.state.tea_unlocked = true
	ActiveTestUtil.arrive(sim, &"puffmoss", 1000.0)
	var dew := sim.state.dew
	for i in 20:
		var t := 1000.0 + 600.0 * (i + 1)
		sim.advance(t)
		sim.active.tea.harvest_bed(sim, &"", t)
		ActiveTestUtil.give_wish(sim, &"puffmoss", &"sing_along")
		ActiveTestUtil.act(sim, WishRules.ACT_RING_CHIME, {}, t)
		if ActiveTestUtil.brew(sim, [&"sweet_clover"], 0, t) != &"":
			sim.active.tea.offer(sim, 0, &"puffmoss", t)
		assert_lte(sim.state.dew, dew, "no faucet: tea and wishes never add dew")
	assert_eq(sim.state.dew, dew, "a cup without drops costs nothing")


func test_thirty_days_away_keeps_every_wish_and_petal() -> void:
	var sim := ActiveTestUtil.quiet_sim(c)
	ActiveTestUtil.set_garden(sim, c, {&"sweet_clover": 4}, {})
	sim.advance(1000.0)
	sim.state.tea_unlocked = true
	for sp: StringName in [&"puffmoss", &"buttonbud", &"pebblepaw"]:
		ActiveTestUtil.arrive(sim, sp, 1000.0)
	ActiveTestUtil.give_wish(sim, &"puffmoss", &"cuddle")
	ActiveTestUtil.give_wish(sim, &"buttonbud", &"brook_song")
	ActiveTestUtil.give_wish(sim, &"pebblepaw", &"boat_ride")
	for sp: StringName in [&"puffmoss", &"buttonbud", &"pebblepaw"]:
		ActiveTestUtil.depart(sim, sp, 1100.0)
	var before := sim.monotone_snapshot()
	sim.catch_up(sim.unix_at(sim.state.t) + 30.0 * DAY, 0.0, sim.unix_at(sim.state.t))
	var after := sim.monotone_snapshot()
	var a: Dictionary = before["active"]
	var b: Dictionary = after["active"]
	for k: String in a:
		assert_true(int(b[k]) >= int(a[k]), "%s never decreases offline" % k)
	assert_eq(sim.state.wishes.size(), 3, "every wish waits (held)")
	assert_eq(sim.active.tea.petals_ready(sim, &"", sim.state.t), 8, "full stems, nothing wilted")


func test_active_mid_fixture() -> void:
	var sim := WorldSim.new_game(c, 99, 1792454400.0, 0.0)
	sim.advance(4000.0)
	GardenFixture.apply(c, sim.state, GardenFixture.MID)
	sim = WorldSim.new(c, sim.state)
	ActiveFixture.apply(sim)
	sim = WorldSim.new(c, sim.state)
	var st := sim.state
	assert_eq(sim.active.wishes.visible_count(sim), 2, "two bubbles in the hollow")
	assert_eq(st.wishes.size(), 3, "and one held by an away friend")
	assert_true(st.tea_unlocked)
	assert_gt(st.pantry.size(), 3, "a pantry with petals")
	assert_gt(sim.active.tea.petals_ready(sim, &"bed_1", st.t), 0, "glints on bed_1")
	assert_eq(st.recipes_found.size(), ActiveFixture.RECIPES.size(), "recipes found")
	assert_eq(st.tray.size(), 2)
	var ctx := sim.active.context(sim)
	var moved := 0
	for p: Dictionary in st.decor_layout:
		if bool(p["stored"]):
			continue
		var pos := Vector2(float(p["x"]), float(p["y"]))
		var anchors: Array = (c.anchors_by_decor[StringName(p["set"])] as Dictionary)["positions"]
		var n := int(String(p["id"]).get_slice("#", 1))
		var a := anchors[0 if StringName(p["set"]) == DecorPlacementRules.CAIRN else n] as Array
		if sim.active.decor.dist_dp(pos, Vector2(float(a[0]), float(a[1]))) > 4.0:
			moved += 1
			assert_eq(sim.active.decor.validate_hard(StringName(p["set"]), pos, ctx), DecorPlacementRules.VALID,
				"%s stands on valid ground" % p["id"])
	assert_gt(moved, 5, "free-placed décor")
	assert_eq(sim.active.decor.placed_count(st.decor_layout, &"stream_stones"), sim.owned_count(&"stream_stones") - 1,
		"one stone tucked away")
