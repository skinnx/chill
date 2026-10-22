extends GutTest
## Active F2 Tea & Treats (GDD §14, docs/gdd/ACTIVE_TEA.md): harvesting never harms a flower,
## petals regrow by the offline-exact anchor formula and pause on a full stem, jars cap gathering
## without losing anything, every pot makes something, the pot returns what is taken out (drops
## refunded), no dew is ever created, reactions never dislike, the 20 h tea rest, the greeter's 0,
## petals back, tea wishes, teaware, the nook unlock and the tea postcards.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const T0 := 1000.0
const CLOVER := &"sweet_clover"
const GARDEN := {&"sweet_clover": 2, &"button_daisy": 2, &"buttercup": 1, &"moonbloom": 2, &"primrose": 1}

var c: GameContent


func before_all() -> void:
	c = GameContent.load_from_dir()


func _sim(bloom_t: float = -1.0e5) -> WorldSim:
	var sim := ActiveTestUtil.quiet_sim(c)
	ActiveTestUtil.set_garden(sim, c, GARDEN, {}, bloom_t)
	sim.advance(T0)
	sim.state.dew = 100
	return sim


func test_the_nook_wakes_after_onboarding_and_a_bloom() -> void:
	var sim := ActiveTestUtil.quiet_sim(c)
	sim.advance(200.0)
	ActiveTestUtil.set_garden(sim, c, GARDEN, {})
	sim.advance(230.0)
	assert_false(sim.state.tea_unlocked, "onboarding still running")
	sim.advance(260.0)
	assert_true(sim.state.tea_unlocked)
	var evs := sim.drain_events().filter(func(e: Dictionary) -> bool:
		return StringName(e["type"]) == WorldSim.EV_TEA_UNLOCKED)
	assert_eq(evs.size(), 1, "once")
	var bare := ActiveTestUtil.quiet_sim(c)
	bare.advance(5000.0)
	assert_false(bare.state.tea_unlocked, "no bloom, no nook")


func test_harvest_never_harms_a_flower() -> void:
	var sim := _sim()
	var stages := []
	for s: Dictionary in sim.state.stems:
		stages.append(int(s["stage"]))
	var cup_rate := sim.cup_rate_per_h()
	var snug := sim.snugness()
	var bloomed := sim.bloomed_count(CLOVER)
	var got := sim.active.tea.harvest_bed(sim, &"bed_1", sim.state.t)
	assert_gt(int(got.get(CLOVER, 0)), 0)
	for i in sim.state.stems.size():
		assert_eq(int(sim.state.stems[i]["stage"]), int(stages[i]), "every stem still blooms")
	assert_eq(sim.cup_rate_per_h(), cup_rate, "dew per hour unchanged")
	assert_eq(sim.snugness(), snug, "attraction unchanged")
	assert_eq(sim.bloomed_count(CLOVER), bloomed)


func test_petals_regrow_offline_exactly_and_pause_when_full() -> void:
	var sim := _sim()
	var tea := sim.active.tea
	var reg := tea.regrow_s(CLOVER)
	var hold := int(c.tea["harvest"]["petal_hold_per_stem"])
	assert_eq(tea.stem_ready(sim, 0, sim.state.t), hold, "bloomed long ago: a full stem")
	tea.harvest_bed(sim, &"", sim.state.t)
	assert_eq(tea.stem_ready(sim, 0, sim.state.t), 0)
	assert_eq(tea.stem_ready(sim, 0, sim.state.t + reg - 1.0), 0)
	assert_eq(tea.stem_ready(sim, 0, sim.state.t + reg), 1, "one petal per regrow period")
	assert_eq(tea.stem_ready(sim, 0, sim.state.t + 30.0 * ActiveTestUtil.DAY), hold, "a full stem simply waits")
	# partial progress is kept on a partial harvest
	var t1 := sim.state.t + 1.5 * reg
	sim.advance(t1)
	tea.harvest_bed(sim, &"", t1)
	assert_eq(tea.stem_ready(sim, 0, t1 + 0.5 * reg), 1, "the half-grown petal kept its progress")
	# live and offline agree: many small steps == one long jump (a pure function of the save and t)
	var a := _sim()
	var b := _sim()
	a.active.tea.harvest_bed(a, &"", T0)
	b.active.tea.harvest_bed(b, &"", T0)
	var t := T0
	for i in 40:
		t += 1234.5
		a.advance(t)
	b.advance(t)
	var got_a := a.active.tea.harvest_bed(a, &"", t)
	var got_b := b.active.tea.harvest_bed(b, &"", t)
	assert_eq(TestUtil.canonical(got_a), TestUtil.canonical(got_b))
	assert_eq(TestUtil.canonical(a.state.petal_from_t), TestUtil.canonical(b.state.petal_from_t))


func test_jars_cap_gathering_and_the_rest_waits_on_the_stems() -> void:
	var sim := _sim()
	sim.state.pantry[String(CLOVER)] = 23
	var got := sim.active.tea.harvest_bed(sim, &"", sim.state.t)
	assert_eq(int(got.get(CLOVER, 0)), 1, "one petal fits")
	assert_eq(int(sim.state.pantry[String(CLOVER)]), 24)
	var waiting := 0
	for i in sim.state.stems.size():
		if StringName(sim.state.stems[i]["flower"]) == CLOVER:
			waiting += sim.active.tea.stem_ready(sim, i, sim.state.t)
	assert_eq(waiting, 3, "the other petals wait on the flowers (nothing discarded)")
	assert_eq(sim.active.tea.room(sim, CLOVER), 0)


func test_every_pot_makes_something() -> void:
	var flowers: Array[String] = []
	for f: Dictionary in c.flowers:
		flowers.append(String(f["id"]))
	var n := 0
	for a in flowers.size():
		for b in range(a, flowers.size() + 1):
			for d in range(b, flowers.size() + 1):
				var mix: Array = [flowers[a]]
				if b < flowers.size():
					mix.append(flowers[b])
				if d < flowers.size() and b < flowers.size():
					mix.append(flowers[d])
				for drops in 3:
					var r := c.match_recipe(mix, drops)
					assert_ne(r, &"", "%s + %d drops makes something" % [mix, drops])
					assert_eq(c.recipes_by_id[r]["kind"], "treat" if drops == 2 else "tea", "two drops make a treat")
					n += 1
	assert_gt(n, 400)
	assert_eq(c.match_recipe(["sweet_clover", "sweet_clover"], 0), &"clover_tea")
	assert_eq(c.match_recipe(["buttercup", "sweet_clover", "button_daisy"], 0), &"meadow_blend", "order never matters")
	assert_eq(c.match_recipe([], 0), &"", "an empty pot is not brewable yet")


func test_pot_gives_back_what_is_taken_out_and_never_creates_dew() -> void:
	var sim := _sim()
	var tea := sim.active.tea
	tea.harvest_bed(sim, &"", sim.state.t)
	var jar := tea.pantry_of(sim, CLOVER)
	var dew := sim.state.dew
	assert_true(tea.pot_add_petal(sim, CLOVER))
	assert_true(tea.pot_add_drop(sim))
	assert_eq(sim.state.dew, dew - 3, "a drop is charged when it goes in")
	assert_true(tea.pot_remove_drop(sim))
	assert_eq(sim.state.dew, dew, "and refunded when taken out")
	assert_true(tea.pot_remove(sim, 0))
	assert_eq(tea.pantry_of(sim, CLOVER), jar, "the petal is back in its jar")
	assert_false(tea.pot_remove(sim, 0), "nothing to take out")
	sim.state.dew = 2
	assert_false(tea.pot_add_drop(sim), "not affordable: nothing charged")
	assert_eq(sim.state.dew, 2)
	for i in 3:
		assert_true(tea.pot_add_petal(sim, CLOVER))
	assert_false(tea.pot_add_petal(sim, CLOVER), "three petals at most")


func test_brew_needs_the_stir_unless_simple_and_keeps_the_pot_when_the_tray_is_full() -> void:
	var sim := _sim()
	var tea := sim.active.tea
	tea.harvest_bed(sim, &"", sim.state.t)
	tea.pot_add_petal(sim, CLOVER)
	tea.pot_add_petal(sim, CLOVER)
	assert_eq(tea.pour(sim, false, sim.state.t), &"", "the stir comes first")
	for i in 3:
		tea.pot_stir(sim, -200.0)
	assert_eq(float(sim.state.pot["stir_deg"]), tea.stir_target(), "either direction, capped at the target")
	assert_eq(tea.pour(sim, false, sim.state.t), &"clover_tea")
	assert_true(sim.state.recipes_found.has("clover_tea"))
	sim.state.pantry["button_daisy"] = 24
	for i in 5:
		assert_ne(ActiveTestUtil.brew(sim, ["button_daisy"], 0, sim.state.t), &"")
	assert_eq(sim.state.tray.size(), 6)
	tea.pot_add_petal(sim, &"button_daisy")
	assert_eq(tea.pour(sim, true, sim.state.t), &"", "the tray is full")
	assert_eq((sim.state.pot["petals"] as Array).size(), 1, "the pot keeps its contents")


func test_reactions_rest_petals_back_and_the_greeter() -> void:
	var sim := _sim()
	sim.state.tea_unlocked = true
	for f: Variant in GARDEN:
		sim.state.pantry[String(f)] = 10
	ActiveTestUtil.arrive(sim, &"puffmoss", T0)
	var aff := sim.affection_of(&"puffmoss")
	ActiveTestUtil.brew(sim, [CLOVER, CLOVER], 0, T0 + 1.0)
	var res := sim.active.tea.offer(sim, 0, &"puffmoss", T0 + 2.0)
	assert_eq(res["reaction"], TeaRules.REACT_LOVED, "puffmoss loves clover tea")
	assert_eq(int(res["affection"]), 2)
	assert_eq(int(res["petals_back"]), 2)
	assert_eq(sim.affection_of(&"puffmoss"), aff + 2)
	assert_eq(int(sim.state.cups_offered), 1)
	assert_true(sim.has_postcard("first_tea"), "the first cup sends its postcard")
	ActiveTestUtil.brew(sim, [&"button_daisy"], 0, T0 + 3.0)
	var again := sim.active.tea.offer(sim, 0, &"puffmoss", T0 + 4.0)
	assert_eq(again["reaction"], TeaRules.REACT_CONTENT, "never a dislike")
	assert_eq(int(again["affection"]), 0, "one tea credit per friend per 20 h")
	ActiveTestUtil.brew(sim, [CLOVER, CLOVER], 0, T0 + 72000.0 + 5.0)
	assert_eq(int(sim.active.tea.offer(sim, 0, &"puffmoss", T0 + 72000.0 + 6.0)["affection"]), 2, "after the rest")
	assert_eq(sim.active.tea.offer(sim, 0, &"honeyhum", T0 + 72010.0), {}, "only a friend who is here")
	# the greeter sips and reacts with 0 affection and no petals back
	sim.state.met["bellkin"] = 1.0
	ActiveTestUtil.depart(sim, &"puffmoss", T0 + 72020.0)
	sim.add_greeter(sim.state.t)
	var g := StringName(sim.state.present[0]["species"])
	var ga := sim.affection_of(g)
	ActiveTestUtil.brew(sim, [CLOVER, CLOVER], 0, sim.state.t)
	var gr := sim.active.tea.offer(sim, 0, g, sim.state.t)
	assert_eq(int(gr["affection"]), 0)
	assert_eq(int(gr["petals_back"]), 0)
	assert_eq(sim.affection_of(g), ga)


func test_known_prefs_from_reactions_and_at_three_hearts() -> void:
	var sim := _sim()
	var k := sim.active.tea.known_prefs(sim, &"puffmoss")
	assert_true((k["loves"] as Array).is_empty())
	sim.state.tea_prefs_seen["puffmoss"] = ["clover_tea"]
	assert_eq((sim.active.tea.known_prefs(sim, &"puffmoss")["loves"] as Array), ["clover_tea"])
	sim.state.affection["puffmoss"] = 15
	var all := sim.active.tea.known_prefs(sim, &"puffmoss")
	assert_eq((all["loves"] as Array).size(), 2)
	assert_eq((all["likes"] as Array).size(), 3)


func test_a_cup_grants_a_matching_tea_wish_and_stacks_with_the_tea_credit() -> void:
	var sim := _sim()
	sim.state.tea_unlocked = true
	sim.state.pantry[String(CLOVER)] = 10
	ActiveTestUtil.arrive(sim, &"puffmoss", T0)
	ActiveTestUtil.give_wish(sim, &"puffmoss", &"daisy_tea")
	sim.state.pantry["button_daisy"] = 3
	ActiveTestUtil.brew(sim, [CLOVER, CLOVER], 0, T0 + 1.0)
	var miss := sim.active.tea.offer(sim, 0, &"puffmoss", T0 + 2.0)
	assert_eq(miss["wish_granted"], &"", "a cup that does not match is simply sipped")
	assert_false(sim.active.wishes.wish_of(sim, &"puffmoss").is_empty())
	ActiveTestUtil.brew(sim, [&"button_daisy"], 0, T0 + 3.0)
	var aff := sim.affection_of(&"puffmoss")
	var hit := sim.active.tea.offer(sim, 0, &"puffmoss", T0 + 4.0)
	assert_eq(hit["wish_granted"], &"daisy_tea", "any cup with a daisy petal")
	assert_eq(sim.affection_of(&"puffmoss"), aff + 1, "the wish point (the tea credit already used today)")
	assert_true(sim.active.wishes.wish_of(sim, &"puffmoss").is_empty())


func test_teaware_is_a_sink_only() -> void:
	var sim := _sim()
	var tea := sim.active.tea
	sim.state.dew = 400
	assert_false(tea.buy_teaware(sim, &"acorn_teapot"), "defaults are owned already")
	assert_true(tea.use_teaware(sim, &"acorn_teapot"))
	assert_false(tea.use_teaware(sim, &"moon_kettle"), "not owned")
	assert_false(tea.buy_teaware(sim, &"moon_kettle"), "not affordable")
	assert_true(tea.buy_teaware(sim, &"toadstool_teapot"))
	assert_eq(sim.state.dew, 100)
	assert_false(tea.buy_teaware(sim, &"toadstool_teapot"), "once")
	assert_true(tea.use_teaware(sim, &"toadstool_teapot"))
	assert_eq(tea.teaware_in_use(sim)["teapot"], "toadstool_teapot")
	assert_eq(tea.teaware_in_use(sim)["cup"], "walnut_cup")
	var lam := sim.lambda_per_h()
	tea.buy_teaware(sim, &"daisy_cup")
	assert_eq(sim.lambda_per_h(), lam, "teaware snug 0: visitor maths untouched")


func test_the_book_postcard_after_every_named_recipe() -> void:
	var sim := _sim()
	sim.state.dew = 99999
	for r: Dictionary in c.recipes:
		if String(r.get("match", "")) == "fallback":
			continue
		var petals: Dictionary = r["petals"]
		var mix: Array = []
		for f: Variant in petals:
			sim.state.pantry[String(f)] = 24
			for i in int(petals[f]):
				mix.append(String(f))
		assert_eq(ActiveTestUtil.brew(sim, mix, int(r["drops"]), sim.state.t), StringName(r["id"]))
		sim.state.tray.clear()
	assert_true(sim.has_postcard("tea_book"))
