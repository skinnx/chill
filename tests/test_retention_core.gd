extends GutTest
## Retention v1 rules (GDD §13): the retention hash golden vectors (§13.1), the 20 h visit rest
## (§13.2.1), heart unlock order (§13.2.2), nests (§13.2.3), signs before debuts that never
## expire (§13.3.1-2), cousins (§13.3.5), away scenes (§13.4: min absence, one per return,
## cast, determinism, pending across close, linger), nothing ever decreasing (G1), the same code
## path live and offline, the recap teaser and the QA fixtures.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const HOUR := 3600.0
const DAY := 86400.0
const BASE_UNIX := 1792454400.0  # 2026-10-20 00:00 UTC
const ONBOARDING: Array[StringName] = [&"puffmoss", &"buttonbud", &"pebblepaw"]
## Everything every species requires (species.json), plus the scene props.
const ALL_BLOOMED := {&"buttercup": 2, &"forget_me_not": 3, &"dandelion": 2, &"bluebell": 3, &"primrose": 3,
	&"moonbloom": 5, &"sweet_clover": 4, &"button_daisy": 2}
const ALL_OWNED := {&"toadstool_seat": 5, &"stream_stones": 5, &"firefly_lantern": 5, &"wind_chime": 5,
	&"pebble_cairn": 3}

var c: GameContent


func before_all() -> void:
	c = GameContent.load_from_dir()


# ----------------------------------------------------------------- §13.1 determinism

func test_golden_hash_vectors() -> void:
	assert_eq(RetentionHash.u(12345, ["sign", "honeyhum", 0]), 0.90297526886713)
	assert_eq(RetentionHash.u(12345, ["sign", "honeyhum", 1]), 0.02754163461250092)
	assert_eq(RetentionHash.u(12345, ["scene_roll", 1]), 0.8649366456155851)
	assert_eq(RetentionHash.u(12345, ["scene_pick", 1]), 0.6148913306348076)
	assert_eq(RetentionHash.u(0, ["sign", "twilight_puffmoss", 0]), 0.7363310847892622)
	assert_eq(RetentionHash.fnv1a64(""), RetentionHash.FNV_OFFSET, "FNV-1a of nothing is the offset basis")
	assert_eq(RetentionHash.lshr(-1, 11), (1 << 53) - 1, "logical shift masks the sign bits")
	for i in 200:
		var x := RetentionHash.u(-7046029254386353131 + i, ["x", i])
		assert_true(x >= 0.0 and x < 1.0, "u in [0, 1)")


func test_retention_never_draws_from_the_world_rng() -> void:
	var sim := RetentionTestUtil.quiet_sim(c)
	RetentionTestUtil.meet(sim, RetentionTestUtil.all_species(c), 30.0)
	var rng_before := sim.state.rng_state
	RetentionTestUtil.set_items(sim, c, ALL_BLOOMED, ALL_OWNED)
	RetentionTestUtil.pet(sim, &"puffmoss", 40, 1000.0)
	sim.advance(3.0 * DAY)
	RetentionTestUtil.tap_all_signs(sim)
	for r in 10:
		sim.retention.on_return(sim, sim.state.t - 3.0 * HOUR, sim.state.t, {"night|clear": 7200.0})
		sim.retention.tap_scene(sim)
	assert_eq(sim.state.rng_state, rng_before, "signs, scenes and cousins use RetentionHash only (G6)")


# ----------------------------------------------------------------- §13.2 friendship

func test_visit_affection_rests_twenty_hours_per_friend() -> void:
	var rest := float(c.economy["visit_affection_rest_s"])
	assert_eq(rest, 72000.0, "20 h of world time")
	var sim := RetentionTestUtil.quiet_sim(c)
	RetentionTestUtil.visit(sim, &"puffmoss", 100.0)
	RetentionTestUtil.visit(sim, &"buttonbud", 200.0)
	assert_eq(sim.affection_of(&"puffmoss"), 1)
	RetentionTestUtil.visit(sim, &"puffmoss", 100.0 + rest - 1.0)
	assert_eq(sim.affection_of(&"puffmoss"), 1, "a visit inside the rest gives nothing")
	assert_eq(float(sim.state.visit_aff_t["puffmoss"]), 100.0, "and does not restart the rest")
	RetentionTestUtil.visit(sim, &"buttonbud", 200.0 + rest - 1.0)
	assert_eq(sim.affection_of(&"buttonbud"), 1, "the rest is per friend")
	RetentionTestUtil.visit(sim, &"puffmoss", 100.0 + rest)
	assert_eq(sim.affection_of(&"puffmoss"), 2, "exactly 20 h later it warms again")
	# Pets are unchanged: once per visit, no rest.
	sim._arrive(sim.state.t, &"puffmoss", 600.0, 0, false)
	assert_true(sim.pet(&"puffmoss", 0.0))
	assert_false(sim.pet(&"puffmoss", 0.0), "once per visit")
	assert_eq(sim.affection_of(&"puffmoss"), 3)


func test_heart_unlocks_arrive_in_order() -> void:
	var sim := RetentionTestUtil.quiet_sim(c)
	RetentionTestUtil.visit(sim, &"puffmoss", 30.0)
	var thr: Array = c.economy["heart_thresholds"]
	var seen_levels: Array[int] = []
	var t := 100.0
	for lvl in range(1, 6):
		var need := int(thr[lvl - 1]) - sim.affection_of(&"puffmoss")
		RetentionTestUtil.pet(sim, &"puffmoss", need, t)
		assert_eq(sim.hearts_of(&"puffmoss"), lvl)
		for e: Dictionary in sim.drain_events():
			if e["type"] == WorldSim.EV_HEARTS:
				seen_levels.append(int(e["hearts"]))
		match lvl:
			1:
				assert_false(sim.has_postcard("puffmoss_h2"))
				assert_true(sim.state.nests.is_empty())
			2:
				assert_true(sim.has_postcard("puffmoss_h2"), "♥2 story postcard I")
				assert_eq(sim.retention.gift_item_for(sim, &"puffmoss"), "sig_moss_tuft", "♥2 signature gift")
			3:
				var n: Dictionary = sim.state.nests["puffmoss"]
				assert_eq(String(n["style"]), "moss_bowl", "♥3 builds its nest")
				assert_eq(float(n["built_t"]), t)
			4:
				assert_false(sim.has_postcard("puffmoss_h4"), "♥4 waits for the unmet buddy")
				assert_true(sim.state.postcards_waiting.has("puffmoss_h4"))
				assert_false(sim.retention.pair_active(sim, &"puffmoss"))
			5:
				assert_true(sim.has_postcard("puffmoss_h5"), "♥5 story postcard III")
				assert_true(sim.state.keepsakes.has("puffmoss"), "♥5 keepsake")
		t += 100.0
	assert_eq(seen_levels, [1, 2, 3, 4, 5], "one heart event per level, ascending")
	RetentionTestUtil.visit(sim, &"moonpuff", t)
	assert_true(sim.has_postcard("puffmoss_h4"), "the buddy's first visit sends chapter II")
	assert_true(sim.state.postcards_waiting.is_empty())
	assert_true(sim.retention.pair_active(sim, &"puffmoss"), "best buddies once both met and one is at ♥4+")
	var p: Dictionary = {}
	for pc: Dictionary in sim.state.postcards:
		if pc["id"] == "puffmoss_h4":
			p = pc
	assert_eq(String(p["template"]), String(c.species_by_id[&"puffmoss"]["postcard_heart4"]))
	# A skipped level (several points at once) still unlocks everything in between.
	var sim2 := RetentionTestUtil.quiet_sim(c)
	RetentionTestUtil.visit(sim2, &"buttonbud", 10.0)
	RetentionTestUtil.visit(sim2, &"honeyhum", 20.0)
	sim2._add_affection(&"buttonbud", 50, 30.0)
	for id: String in ["buttonbud_h2", "buttonbud_h4", "buttonbud_h5"]:
		assert_true(sim2.has_postcard(id), "%s after a multi-level jump" % id)
	assert_true(sim2.state.nests.has("buttonbud") and sim2.state.keepsakes.has("buttonbud"))


func test_signature_gift_from_heart_two_keeps_the_dew() -> void:
	var sim := RetentionTestUtil.quiet_sim(c)
	var sdef: Dictionary = c.species_by_id[&"puffmoss"]
	sim.advance(10.0)
	sim._arrive(10.0, &"puffmoss", 60.0, 0, false)
	sim.advance(100.0)
	assert_eq(String(sim.state.basket[0]["gift_item"]), String(sdef["gift_item"]), "before ♥2: the usual gift")
	assert_false(bool(sim.state.basket[0]["signature"]))
	sim._add_affection(&"puffmoss", 10, 100.0)
	sim._arrive(200.0, &"puffmoss", 60.0, 0, false)
	sim.advance(300.0)
	var events := sim.drain_events()
	assert_eq(String(sim.state.basket[1]["gift_item"]), String(sdef["signature_gift"]))
	assert_true(bool(sim.state.basket[1]["signature"]))
	assert_eq(int(sim.state.basket[1]["dew"]), int(sdef["gift_dew"]), "same gift_dew: the economy is unchanged")
	var first := 0
	for e: Dictionary in events:
		if e["type"] == WorldSim.EV_GIFT and bool(e["first_signature"]):
			first += 1
	assert_eq(first, 1, "the first signature gift carries the note")
	assert_true(sim.state.signature_gifts.has("puffmoss"), "Keepsakes lists it")
	assert_false(c.gift_item_def(StringName(sdef["signature_gift"])).is_empty())


func test_nest_grows_in_real_time_and_never_shrinks() -> void:
	var sim := RetentionTestUtil.quiet_sim(c)
	RetentionTestUtil.visit(sim, &"honeyhum", 10.0)
	RetentionTestUtil.pet(sim, &"honeyhum", 14, 1000.0)
	sim.drain_events()
	assert_eq(int(sim.state.nests["honeyhum"]["stage"]), 0, "twigs")
	sim.advance(1000.0 + DAY - 1.0)
	assert_eq(int(sim.state.nests["honeyhum"]["stage"]), 0)
	sim.advance(1000.0 + DAY)
	assert_eq(int(sim.state.nests["honeyhum"]["stage"]), 1, "moss bed after 1 day")
	var saved := sim.unix_at(sim.state.t)
	var back := WorldSim.new(c, WorldState.from_dict(sim.state.to_dict()))
	back.catch_up(saved + 3.0 * DAY, 0.0, saved)
	var stages: Array[int] = []
	for e: Dictionary in sim.drain_events() + back.drain_events():
		if e["type"] == WorldSim.EV_NEST_STAGE:
			stages.append(int(e["stage"]))
	assert_eq(int(back.state.nests["honeyhum"]["stage"]), 2, "flower canopy after 3 days, grown offline")
	assert_eq(stages, [1, 2], "one event per stage")
	assert_eq(StringName(back.retention.nest_view(back, &"honeyhum")["stage_id"]), &"flower_canopy")
	back.advance(back.state.t + 30.0 * DAY)
	assert_eq(int(back.state.nests["honeyhum"]["stage"]), 2, "never wilts")


# ----------------------------------------------------------------- §13.3 signs and debuts

func test_signs_precede_the_debut_and_never_expire() -> void:
	var sim := WorldSim.new_game(c, 77, BASE_UNIX + 9.0 * HOUR, 0.0)
	sim.advance(400.0)
	RetentionTestUtil.set_items(sim, c, {&"buttercup": 2}, {})
	var m: Dictionary = sim.state.mysteries["honeyhum"]
	assert_eq(float(m["open_t"]), 400.0, "opens the moment its requires hold")
	var last := -INF
	var windows := c.sign_windows(2, false)
	for i in 2:
		var s: Dictionary = sim.state.signs[i]
		var lo := float(windows[i][0])
		var hi := float(windows[i][1])
		var expect := 400.0 + lo + (hi - lo) * RetentionHash.u(77, ["sign", "honeyhum", i])
		assert_almost_eq(float(s["appear_t"]), expect, 1e-9, "sign %d time from the retention hash" % i)
		last = maxf(last, float(s["appear_t"]))
	assert_almost_eq(float(m["ok_t"]), last + float(c.mysteries["debut_after_last_sign_s"]), 1e-9)
	var met_t := INF
	var due := 0
	var t := 400.0
	while t < 30.0 * DAY:
		t += HOUR
		sim.advance(t)
		for e: Dictionary in sim.drain_events():
			if e["type"] == WorldSim.EV_MET and e["species"] == &"honeyhum":
				met_t = float(e["t"])
			elif e["type"] == WorldSim.EV_SIGN_DUE:
				due += 1
	assert_true(sim.is_met(&"honeyhum"), "the debut happens although no sign was tapped")
	assert_true(met_t >= float(m["ok_t"]), "never before the signs are out (%f >= %f)" % [met_t, m["ok_t"]])
	assert_eq(due, 2, "each sign comes due once")
	assert_eq(sim.state.signs.size(), 2, "after 30 days both signs are still waiting (never expire)")
	assert_true(float(sim.state.mysteries["honeyhum"]["solved_unix"]) >= 0.0, "the mystery is solved by the debut")
	assert_eq(RetentionTestUtil.tap_all_signs(sim), 2, "and can still be collected")
	assert_eq(sim.retention.clue_count(sim, "honeyhum"), 2)
	assert_true(bool(sim.retention.clue_card(sim, "honeyhum")["riddle_found"]), "the note carries the riddle")


func test_onboarding_friends_have_no_mystery_and_unmet_friends_wait() -> void:
	var sim := RetentionTestUtil.quiet_sim(c)
	for sp: StringName in ONBOARDING:
		assert_eq(sim.retention.debut_ok_t(sim, sp), -INF)
	assert_eq(sim.retention.debut_ok_t(sim, &"capling"), INF, "no mystery yet: not eligible")
	RetentionTestUtil.set_items(sim, c, {}, {&"toadstool_seat": 5})
	assert_eq(sim.state.signs.size(), 3, "rare friends get three signs")
	assert_eq(String(sim.state.signs[2]["type"]), "note", "every debut mystery ends with the note")
	assert_false(sim._eligible_ignoring_presence(&"capling", &"day", sim.state.t))
	assert_true(sim._eligible_ignoring_presence(&"capling", &"day", float(sim.state.mysteries["capling"]["ok_t"])))


func test_at_most_three_signs_are_visible_at_distinct_anchors() -> void:
	var sim := RetentionTestUtil.quiet_sim(c)
	RetentionTestUtil.meet(sim, ONBOARDING, 30.0)
	RetentionTestUtil.set_items(sim, c, ALL_BLOOMED, ALL_OWNED)
	assert_eq(sim.state.mysteries.size(), 9, "all nine non-onboarding mysteries open")
	sim.advance(7.0 * DAY)
	var events := sim.drain_events()
	assert_eq(RetentionTestUtil.count_events(events, WorldSim.EV_SIGN_DUE), sim.state.signs.size())
	assert_eq(RetentionTestUtil.count_events(events, WorldSim.EV_SIGN_VISIBLE), 3, "the queue waits for a slot")
	var vis := sim.retention.visible_signs(sim)
	assert_eq(vis.size(), 3)
	var anchors := {}
	for s: Dictionary in vis:
		anchors[s["anchor"]] = true
		var ok := false
		for a: Dictionary in c.sign_anchors:
			if StringName(a["id"]) == s["anchor"]:
				ok = (a["types"] as Array).has(String(s["sign"]))
		assert_true(ok, "anchor %s lists the %s type" % [s["anchor"], s["sign"]])
	assert_eq(anchors.size(), 3, "one sign per anchor")
	var hidden := ""
	for s: Dictionary in sim.state.signs:
		if String(s["anchor"]) == "":
			hidden = RetentionRules.sign_key(s)
			break
	assert_false(sim.retention.tap_sign(sim, hidden), "a queued sign cannot be tapped yet")
	var total := sim.state.signs.size()
	assert_true(sim.retention.tap_sign(sim, String(vis[0]["key"])))
	assert_eq(sim.retention.visible_signs(sim).size(), 3, "the freed slot fills from the queue")
	assert_eq(RetentionTestUtil.tap_all_signs(sim), total - 1)
	assert_true(sim.state.signs.is_empty())


# ----------------------------------------------------------------- §13.3.5 cousins

func test_cousin_debut_is_deterministic_and_repeats_every_third_visit() -> void:
	var sim := RetentionTestUtil.quiet_sim(c)  # local = t + 20:00
	RetentionTestUtil.meet(sim, RetentionTestUtil.all_species(c), 30.0)
	RetentionTestUtil.pet(sim, &"puffmoss", 40, 100.0)
	var m: Dictionary = sim.state.mysteries["twilight_puffmoss"]
	assert_eq(String(m["kind"]), "variant")
	var ok_t := float(m["ok_t"])
	var golden_t := ceilf((ok_t + 10800.0) / DAY) * DAY - 10800.0  # 17:00 local after ok_t
	RetentionTestUtil.visit(sim, &"puffmoss", golden_t - DAY)  # golden, but before its signs are out
	assert_false(sim.state.variants_met.has("twilight_puffmoss"), "not before cousin_ok_t")
	RetentionTestUtil.visit(sim, &"puffmoss", golden_t + 6.0 * HOUR)  # 23:00: night
	assert_false(sim.state.variants_met.has("twilight_puffmoss"), "not at night")
	golden_t += DAY
	sim.advance(golden_t)
	var fillers: Array[StringName] = [&"glowmote", &"moonpuff", &"capling", &"bellkin", &"primpip"]
	for i in int(c.economy["max_present"]) - 1:
		sim.state.present.append({"species": String(fillers[i]), "arrive_t": golden_t, "depart_t": INF, "gift_dew": 0,
			"gift_item": "", "boat_credit": true, "pet_credit": true, "scripted": false, "greeter": false, "cousin": ""})
	sim._arrive(golden_t, &"puffmoss", 600.0, 0, false)
	assert_false(sim.state.variants_met.has("twilight_puffmoss"), "no free place: it comes another time")
	sim.state.present.clear()
	RetentionTestUtil.visit(sim, &"puffmoss", golden_t + 60.0)
	assert_true(sim.state.variants_met.has("twilight_puffmoss"), "golden hour after its signs: the cousin arrives")
	var arrivals := 0
	var t := golden_t + 120.0
	for i in 9:
		sim.advance(t)
		sim._arrive(t, &"puffmoss", 60.0, 0, false)
		if String(sim.state.present[sim.state.present.size() - 1]["cousin"]) != "":
			arrivals += 1
		sim.state.present.clear()
		t += 120.0
	assert_eq(arrivals, 3, "every cousin_every_n_visits-th base arrival brings it")
	assert_eq(int(sim.state.cousin_visits["puffmoss"]), 9)


# ----------------------------------------------------------------- §13.4 away scenes

func _scene_world(seed: int = 12345) -> WorldSim:
	var sim := RetentionTestUtil.quiet_sim(c, seed)
	RetentionTestUtil.meet(sim, [&"puffmoss", &"buttonbud", &"pebblepaw", &"honeyhum", &"primpip", &"moonpuff"], 30.0)
	sim.state.boats = 10
	RetentionTestUtil.set_items(sim, c, ALL_BLOOMED, ALL_OWNED)
	RetentionTestUtil.pet(sim, &"puffmoss", 30, 100.0)
	sim.advance(DAY)
	sim.drain_events()
	return sim


func test_scene_needs_two_hours_away_and_at_most_one_per_return() -> void:
	var sim := _scene_world()
	var t := sim.state.t
	var min_abs := float(c.scenes_doc["min_absence_s"])
	assert_false(sim.retention.on_return(sim, t - min_abs + 1.0, t), "under 2 h is not a return")
	assert_eq(sim.state.scene_returns, 0)
	assert_false(sim.retention.on_return(sim, -1.0, t), "the first launch is not a return")
	var staged := 0
	var r := 0
	while staged == 0 and r < 40:
		sim.retention.on_return(sim, t - min_abs, t, {"night|rain": 7200.0})
		r += 1
		staged = RetentionTestUtil.count_events(sim.drain_events(), WorldSim.EV_SCENE_STAGED)
	assert_eq(staged, 1, "one scene per return")
	var returns := sim.state.scene_returns
	var pending := sim.state.pending_scene.duplicate(true)
	assert_true(sim.retention.on_return(sim, t - DAY, t + DAY, {"night|rain": 7200.0}))
	var ev := sim.drain_events()
	assert_eq(sim.state.scene_returns, returns, "a pending scene is re-shown, no new pick")
	assert_eq(JSON.stringify(sim.state.pending_scene), JSON.stringify(pending))
	assert_true(bool(ev[0]["resumed"]))


func test_scene_selection_is_deterministic_unseen_first_and_seeded() -> void:
	var picks: Array[String] = []
	for run in 2:
		var sim := _scene_world()
		var seq := _scene_sequence(sim, 40)
		picks.append(";".join(seq))
		if run == 0:
			var first_seen := {}
			for i in seq.size():
				var id := seq[i].get_slice(":", 0)
				if id != "-" and not first_seen.has(id):
					first_seen[id] = i
			assert_eq(first_seen.size(), c.scenes.size(), "every eligible scene appears: %s" % first_seen)
			var last_first := 0
			for id: String in first_seen:
				last_first = maxi(last_first, int(first_seen[id]))
			for i in last_first:
				var id := seq[i].get_slice(":", 0)
				assert_true(id == "-" or int(first_seen[id]) == i, "no repeat before all are seen once (%d %s)" % [i, id])
			assert_eq(sim.state.memories.size(), sim.state.scene_returns - _misses(seq), "every staged scene archived")
	assert_eq(picks[0], picks[1], "same save, same returns: same scenes and casts")
	assert_ne(";".join(_scene_sequence(_scene_world(999), 40)), picks[0], "another install seed rolls differently")


## [param n] returns 10 h apart (3 h away each), each staged scene tapped: "scene:cast" or "-".
func _scene_sequence(sim: WorldSim, n: int) -> PackedStringArray:
	var seq := PackedStringArray()
	for i in n:
		var t := sim.state.t + 10.0 * HOUR
		sim.advance(t)
		sim.retention.on_return(sim, t - 3.0 * HOUR, t, {"night|clear": 7200.0, "dusk|rain": 3600.0})
		var p := sim.state.pending_scene
		seq.append("%s:%s" % [p.get("scene", "-"), ",".join(p.get("cast", []))])
		sim.retention.tap_scene(sim)
	return seq


func _misses(seq: PackedStringArray) -> int:
	var n := 0
	for s: String in seq:
		if s.begins_with("-"):
			n += 1
	return n


func test_scene_conditions_follow_the_absence_profile() -> void:
	var sim := _scene_world()
	var nap: Dictionary = c.scenes_by_id[&"nap_pile"]
	assert_true(sim.retention.scene_ok(sim, nap, {"night|clear": 3600.0}), "1 h of night")
	assert_false(sim.retention.scene_ok(sim, nap, {"night|clear": 3599.0, "day|clear": 9000.0}))
	assert_true(sim.retention.scene_ok(sim, nap, {"day|rain": 1800.0}), "or 30 min of rain")
	var fort: Dictionary = c.scenes_by_id[&"leaf_fort"]
	assert_false(sim.retention.scene_ok(sim, fort, {"night|clear": 99999.0}), "the fort needs rain")
	var regatta: Dictionary = c.scenes_by_id[&"boat_regatta"]
	assert_true(sim.retention.scene_ok(sim, regatta, {}))
	sim.state.boats = 9
	assert_false(sim.retention.scene_ok(sim, regatta, {}), "10 boats floated")
	var prof := sim.retention.away_profile(sim, 0.0, 7200.0)
	var tot := 0.0
	for k: String in prof:
		tot += float(prof[k])
	assert_almost_eq(tot, 7200.0, 1e-9, "the profile covers the whole absence")


func test_cast_rules_prefer_new_faces_present_and_pairs() -> void:
	var sim := _scene_world()
	var tower: Dictionary = c.scenes_by_id[&"pebble_tower"]
	var cast := sim.retention.cast_for(sim, tower)
	assert_eq(cast[0], "primpip", "the builder role prefers primpip")
	assert_eq(cast[1], "puffmoss", "then the highest hearts")
	sim.state.present.append({"species": "honeyhum", "arrive_t": 0.0, "depart_t": INF, "gift_dew": 0, "gift_item": "",
		"boat_credit": true, "pet_credit": true, "scripted": false, "greeter": false, "cousin": ""})
	cast = sim.retention.cast_for(sim, tower)
	assert_eq(cast[1], "honeyhum", "present visitors before absent friends")
	sim.state.scene_cast["pebble_tower"] = ["honeyhum", "puffmoss"]
	cast = sim.retention.cast_for(sim, tower)
	assert_false(cast.has("honeyhum") or cast.has("puffmoss"), "friends new to the scene first: %s" % [cast])
	var crowns: Dictionary = c.scenes_by_id[&"flower_crowns"]
	assert_eq(sim.retention.cast_for(sim, crowns).size(), (crowns["roles"] as Array).size())
	var pair: Dictionary = c.scenes_by_id[&"pair_nap"]
	assert_eq(sim.retention.cast_for(sim, pair), ["puffmoss", "moonpuff"] as Array[String], "the ♥4 pair, lead first")
	var watchers: Dictionary = c.scenes_by_id[&"moon_watchers"]
	var w := sim.retention.cast_for(sim, watchers)
	assert_eq(w.size(), 2)
	assert_eq(String(c.species_by_id[StringName(w[0])]["best_friend"]), w[1], "a best-buddy pair")


func test_pending_scene_survives_close_and_archives_after_linger() -> void:
	var sim := _scene_world()
	var t := sim.state.t
	sim.retention.stage_scene(sim, &"pair_nap", sim.retention.cast_for(sim, c.scenes_by_id[&"pair_nap"]), t)
	var reloaded := WorldSim.new(c, WorldState.from_dict(JSON.parse_string(JSON.stringify(sim.state.to_dict()))))
	assert_eq(String(reloaded.state.pending_scene["scene"]), "pair_nap", "survives an app close")
	var linger := float(c.scenes_doc["linger_s"])
	reloaded.retention.foreground_tick(reloaded, linger - 1.0)
	assert_false(reloaded.state.pending_scene.is_empty())
	var again := WorldSim.new(c, WorldState.from_dict(reloaded.state.to_dict()))
	again.retention.foreground_tick(again, 0.5)
	assert_false(again.state.pending_scene.is_empty(), "foreground time adds up across closes")
	again.retention.foreground_tick(again, 0.5)
	assert_true(again.state.pending_scene.is_empty(), "archived after linger_s of foreground time")
	assert_eq(again.state.memories.size(), 1)
	var mem: Dictionary = again.state.memories[0]
	for key: String in ["scene", "cast", "phase", "weather", "world_t", "unix"]:
		assert_true(mem.has(key), "memory has %s" % key)
	assert_false(again.retention.tap_scene(again), "nothing pending")
	sim.retention.tap_scene(sim)
	assert_eq(sim.state.memories.size(), 1, "a tap archives it too")


# ----------------------------------------------------------------- G1 / G2 / one code path

func _played(seed: int, days: int) -> WorldSim:
	var sim := WorldSim.new_game(c, seed, BASE_UNIX + 20.0 * HOUR, 0.0)
	sim.advance(10.0)
	sim.tap_tutorial_seed()
	var t := 300.0
	var last_end := 0.0
	while t < days * DAY:
		sim.advance(t)
		sim.retention.on_return(sim, last_end, t)
		sim.collect()
		for p: Dictionary in sim.state.present.duplicate():
			sim.pet(StringName(p["species"]), sim.unix_at(t))
		for o: Dictionary in sim.catalogue_options():
			if int(o["price"]) <= sim.state.dew:
				var item := StringName(o["item"])
				if c.is_flower(item):
					sim.buy_flower(item)
				else:
					sim.buy_decor(item)
		RetentionTestUtil.tap_all_signs(sim)
		sim.retention.foreground_tick(sim, 300.0)
		last_end = t + 300.0
		sim.advance(last_end)
		t += 12.0 * HOUR
	sim.drain_events()
	return sim


func test_thirty_days_away_nothing_decreases_or_is_lost() -> void:
	var sim := _played(3, 6)
	sim.retention.stage_scene(sim, &"nap_pile", sim.retention.cast_for(sim, c.scenes_by_id[&"nap_pile"]), sim.state.t)
	var before := sim.monotone_snapshot()
	var signs_before := sim.state.signs.size()
	var saved_at := sim.unix_at(sim.state.t)
	var t_bg := sim.state.t
	var back := WorldSim.new(c, WorldState.from_dict(sim.state.to_dict()))
	back.catch_up(saved_at + 30.0 * DAY, 0.0, saved_at)
	back.retention.on_return(back, t_bg, back.state.t)
	var after := back.monotone_snapshot()
	for k: String in before:
		var a: Variant = before[k]
		if a is Dictionary:
			for key: Variant in a:
				assert_true(int((after[k] as Dictionary).get(key, 0)) >= int(a[key]), "%s[%s] never decreases" % [k, key])
		else:
			assert_true(float(after[k]) >= float(a) - 1e-9, "%s %s -> %s" % [k, a, after[k]])
	assert_true(back.state.signs.size() >= signs_before, "untapped signs still wait")
	assert_eq(String(back.state.pending_scene["scene"]), "nap_pile", "the pending scene is still there")
	assert_true(back.state.nests.size() >= sim.state.nests.size())


func test_live_and_offline_take_the_same_code_path() -> void:
	var live := _played(11, 3)
	var offline := WorldSim.new(c, WorldState.from_dict(live.state.to_dict()))
	var t0 := live.state.t
	var t := t0
	while t < t0 + 5.0 * DAY:
		t += 517.0
		live.advance(t)
	offline.advance(t)
	var a := live.state.to_dict()
	var b := offline.state.to_dict()
	for key: String in ["signs", "mysteries", "nests", "met", "affection", "variants_met", "postcards", "visit_aff_t"]:
		assert_eq(TestUtil.canonical(a[key]), TestUtil.canonical(b[key]), "%s identical live vs one catch-up" % key)


# ----------------------------------------------------------------- recap, API views, QA fixture

func test_recap_shows_the_scene_teaser_and_retention_lines() -> void:
	var sim := RetentionTestUtil.quiet_sim(c)
	var events: Array[Dictionary] = [
		{"type": WorldSim.EV_ARRIVED, "species": &"buttonbud", "debut": false, "t": 1.0},
		{"type": WorldSim.EV_MET, "species": &"bellkin", "t": 2.0},
		{"type": WorldSim.EV_MET, "species": &"primpip", "t": 2.5},
		{"type": WorldSim.EV_MET, "species": &"capling", "t": 2.7},
		{"type": WorldSim.EV_HEARTS, "species": &"puffmoss", "hearts": 3, "t": 3.0},
		{"type": WorldSim.EV_SCENE_STAGED, "scene": &"leaf_fort", "t": 4.0},
	]
	var lines := Recap.build(sim, events, 0.0, 0.0)
	assert_eq(lines.size(), Recap.MAX_LINES)
	assert_eq(lines[0]["key"], &"RECAP_NEW_FRIEND")
	assert_eq(lines[2]["key"], &"RECAP_SCENE_LEAF_FORT", "the teaser always gets a line")
	events.resize(1)
	events.append({"type": WorldSim.EV_HEARTS, "species": &"honeyhum", "hearts": 4, "t": 3.0})
	events.append({"type": WorldSim.EV_SIGN_DUE, "t": 3.5})
	lines = Recap.build(sim, events, 0.0, 0.0)
	assert_eq(lines[0], {"key": &"RECAP_HEARTS", "species": &"honeyhum"})
	assert_eq(lines[1]["key"], &"RECAP_CLUE")
	assert_eq(lines[2]["key"], &"RECAP_ONE_VISITED")


func test_view_models_for_the_album() -> void:
	var sim := _scene_world()
	var unlocks := sim.retention.unlock_list(sim, &"puffmoss")
	assert_eq(unlocks.size(), 5)
	assert_true(bool(unlocks[3]["reached"]) and not bool(unlocks[4]["reached"]))
	assert_eq(sim.retention.unseen_hearts(sim).size(), 1, "puffmoss's hearts not celebrated yet")
	sim.retention.mark_hearts_seen(sim, &"puffmoss")
	assert_eq(sim.retention.unseen_hearts(sim).size(), 0, "never toasts twice")
	var cards := sim.retention.clue_cards(sim)
	assert_eq(cards.size(), sim.state.mysteries.size())
	for i in cards.size() - 1:
		assert_true(c.album_index(StringName(cards[i]["species"])) <= c.album_index(StringName(cards[i + 1]["species"])),
			"Clues cards in album order")
	assert_eq(StringName(sim.retention.nest_view(sim, &"puffmoss")["style"]), &"moss_bowl")
	assert_eq(sim.retention.cousin_view(sim, &"puffmoss")["variant"], &"twilight_puffmoss")
	assert_true(bool(sim.retention.buddy_view(sim, &"puffmoss")["active"]))
	sim.state.present.append({"species": "puffmoss", "arrive_t": 0.0, "depart_t": INF, "gift_dew": 0, "gift_item": "",
		"boat_credit": true, "pet_credit": true, "scripted": false, "greeter": false, "cousin": ""})
	var wave := sim.retention.wave_plan(sim, 3)
	assert_eq(wave.size(), 1)
	var d := float(wave[0]["delay_s"])
	assert_true(d >= 0.6 and d <= 1.6, "wave delay 0.6-1.6 s")
	assert_eq(d, sim.retention.wave_plan(sim, 3)[0]["delay_s"], "deterministic per open")


func test_retention_mid_fixture_and_every_qa_scene() -> void:
	for id: Dictionary in c.scenes:
		var sim := WorldSim.new_game(c, 1, BASE_UNIX + 12.0 * HOUR, 0.0)
		GardenFixture.apply(c, sim.state, GardenFixture.MID)
		sim = WorldSim.new(c, sim.state)
		RetentionFixture.apply(sim, StringName(id["id"]))
		sim = WorldSim.new(c, sim.state)
		var p := sim.state.pending_scene
		assert_eq(StringName(p["scene"]), StringName(id["id"]), "--qa-scene=%s stages it" % id["id"])
		assert_eq((p["cast"] as Array).size(), (id["roles"] as Array).size(), "%s has a full cast" % id["id"])
		if id["id"] != RetentionFixture.DEFAULT_SCENE:
			continue
		var hearts := {}
		for s: Dictionary in c.species:
			if sim.is_met(StringName(s["id"])):
				hearts[sim.hearts_of(StringName(s["id"]))] = true
		assert_eq(hearts.keys().size(), 5, "hearts spread 1-5: %s" % hearts)
		var stages := {}
		for sp: String in sim.state.nests:
			stages[int(sim.state.nests[sp]["stage"])] = true
		assert_eq(stages.size(), 3, "nests at twigs, moss bed and canopy")
		var open := 0
		for m: String in sim.state.mysteries:
			if float(sim.state.mysteries[m]["solved_unix"]) < 0.0:
				open += 1
		assert_eq(open, 2, "two open mysteries")
		var per := {}
		for s: Dictionary in sim.retention.visible_signs(sim):
			per[s["mystery"]] = int(per.get(s["mystery"], 0)) + 1
		assert_eq(per, {&"capling": 1, &"puddlewump": 1}, "one visible sign each")
		assert_eq(sim.state.variants_met.size(), 1, "one cousin met")
		assert_true(sim.state.memories.size() >= 2)
