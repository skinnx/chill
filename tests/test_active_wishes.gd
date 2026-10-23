extends GutTest
## Active F1 Wishes (GDD §14, docs/gdd/ACTIVE_WISHES.md): deterministic spawns from the hash
## (never the world RNG), foreground only (never inside advance or catch-up), caps and gaps, held
## wishes kept across visits, every fulfilment target, grant rewards with their own 20 h rest,
## the gift petal and stamps, the greeter bringing a held wish, and "a wish never disappears
## except by grant".

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const T0 := 1000.0
const GARDEN := {&"sweet_clover": 3, &"button_daisy": 2, &"bluebell": 2, &"moonbloom": 1}
const DECOR := {&"leaf_pinwheel": 2, &"wind_chime": 1, &"firefly_lantern": 1}

var c: GameContent


func before_all() -> void:
	c = GameContent.load_from_dir()


func _sim(seed: int = 24680) -> WorldSim:
	var sim := ActiveTestUtil.quiet_sim(c, seed)
	ActiveTestUtil.set_garden(sim, c, GARDEN, DECOR)
	sim.advance(T0)
	sim.state.dew = 200
	return sim


func _grants(sim: WorldSim) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in sim.drain_events():
		if StringName(e["type"]) == WorldSim.EV_WISH_GRANTED:
			out.append(e)
	return out


## A session: three friends, one check per minute for [param minutes].
func _play(sim: WorldSim, minutes: int, t0: float = T0) -> Array:
	for sp: StringName in [&"puffmoss", &"buttonbud", &"honeyhum"]:
		if not sim.is_present(sp):
			ActiveTestUtil.arrive(sim, sp, t0)
	var lines: Array = []
	for i in minutes:
		var t := t0 + 60.0 * (i + 1)
		sim.advance(t)
		sim.active.wishes.foreground_tick(sim, 60.0)
		for w: Dictionary in sim.state.wishes:
			lines.append("%d:%s:%s:%s" % [i, w["species"], w["wish"], w["state"]])
	return lines


func test_spawns_are_deterministic_and_never_touch_the_world_rng() -> void:
	var a := _sim()
	var b := _sim()
	var rng_before := a.state.rng_state
	var la := _play(a, 40)
	var lb := _play(b, 40)
	assert_eq(JSON.stringify(la), JSON.stringify(lb), "the same save and play give the same wishes")
	assert_gt(a.state.wish_checks, 30)
	assert_false(a.state.wishes.is_empty() and a.state.wishes_granted == 0, "something spawned")
	assert_eq(a.state.rng_state, rng_before, "wish draws are the stateless hash, never the world stream")
	var other := _sim(13579)
	assert_ne(JSON.stringify(_play(other, 40)), JSON.stringify(la), "another install seed, other wishes")


func test_no_wish_spawns_inside_advance_or_catch_up() -> void:
	var sim := _sim()
	for sp: StringName in [&"puffmoss", &"buttonbud"]:
		ActiveTestUtil.arrive(sim, sp, T0)
	sim.advance(T0 + 20.0 * ActiveTestUtil.HOUR)
	sim.catch_up(sim.unix_at(sim.state.t) + 3.0 * ActiveTestUtil.DAY, 0.0, sim.unix_at(sim.state.t))
	assert_eq(sim.state.wish_checks, 0, "offline time runs no check (AP6)")
	assert_true(sim.state.wishes.is_empty())


func test_foreground_cadence_survives_reloads_and_pauses_when_blocked() -> void:
	var sim := _sim()
	sim.active.wishes.foreground_tick(sim, 45.0)
	assert_eq(sim.state.wish_checks, 0)
	var again := WorldSim.new(c, WorldState.from_dict(sim.state.to_dict()))
	again.active.wishes.foreground_tick(again, 15.0)
	assert_eq(again.state.wish_checks, 1, "45 s + 15 s across a reload = one check")
	again.active.wishes.foreground_tick(again, 600.0, true)
	assert_eq(again.state.wish_checks, 1, "a sheet, card or edit mode stops the wish clock")
	again.active.features[ActiveRules.FEATURE_WISHES] = false
	again.active.wishes.foreground_tick(again, 600.0)
	assert_eq(again.state.wish_checks, 1, "the feature flag off: no wishes")


func test_caps_and_the_teaching_wish() -> void:
	var sim := _sim()
	_play(sim, 120)
	var st := sim.state
	assert_lte(sim.active.wishes.visible_count(sim), int(c.wishes_doc["tuning"]["max_visible"]))
	assert_lte(st.wishes.size(), int(c.wishes_doc["tuning"]["max_pending"]))
	var per := {}
	for w: Dictionary in st.wishes:
		assert_false(per.has(w["species"]), "one wish per friend")
		per[w["species"]] = true
	assert_true(st.wish_tutorial_done)
	assert_true((st.wish_stamps.has("puffmoss") or st.wishes.any(func(w: Dictionary) -> bool:
		return String(w["wish"]) == "cuddle")), "the first wish is the scripted cuddle for an onboarding friend")


func test_a_friend_who_leaves_keeps_its_wish() -> void:
	var sim := _sim()
	ActiveTestUtil.arrive(sim, &"puffmoss", T0)
	ActiveTestUtil.give_wish(sim, &"puffmoss", &"cuddle")
	ActiveTestUtil.depart(sim, &"puffmoss", T0 + 10.0)
	var w := sim.active.wishes.wish_of(sim, &"puffmoss")
	assert_eq(String(w["state"]), WorldState.WISH_HELD, "held, never lost")
	sim.advance(T0 + 30.0 * ActiveTestUtil.DAY)
	assert_false(sim.active.wishes.wish_of(sim, &"puffmoss").is_empty(), "wishes never expire")
	ActiveTestUtil.arrive(sim, &"puffmoss", T0 + 30.0 * ActiveTestUtil.DAY)
	assert_eq(String(sim.active.wishes.wish_of(sim, &"puffmoss")["state"]), WorldState.WISH_OPEN, "back with it")


func test_every_world_target_grants_its_wish() -> void:
	var cases := [
		[&"cuddle", WishRules.ACT_PET, {"species": &"puffmoss"}],
		[&"sing_along", WishRules.ACT_RING_CHIME, {}],
		[&"nap_daisies", WishRules.ACT_BED_TAP, {"bed": &"bed_1"}],
		[&"watch_fireflies", WishRules.ACT_DECOR_TAP, {"set": &"firefly_lantern"}],
		[&"brook_song", WishRules.ACT_STREAM_TAP, {}],
		[&"boat_ride", WishRules.ACT_BOAT, {}],
	]
	for row: Array in cases:
		var sim := _sim()
		ActiveTestUtil.arrive(sim, &"puffmoss", T0)
		ActiveTestUtil.give_wish(sim, &"puffmoss", row[0])
		sim.drain_events()
		ActiveTestUtil.act(sim, row[1], row[2], T0 + 5.0)
		assert_eq(_grants(sim).size(), 1, "%s granted by %s" % [row[0], row[1]])
		assert_true(sim.active.wishes.wish_of(sim, &"puffmoss").is_empty())


func test_a_mismatched_action_or_a_pan_grants_nothing() -> void:
	var sim := _sim()
	ActiveTestUtil.arrive(sim, &"puffmoss", T0)
	ActiveTestUtil.give_wish(sim, &"puffmoss", &"nap_daisies")
	sim.drain_events()
	ActiveTestUtil.act(sim, WishRules.ACT_BED_TAP, {"bed": &"bed_3"}, T0 + 5.0)
	ActiveTestUtil.act(sim, WishRules.ACT_STREAM_TAP, {}, T0 + 6.0)
	assert_true(_grants(sim).is_empty(), "a bed without daisies, or another action, is no mistake: it waits")
	assert_false(sim.active.wishes.wish_of(sim, &"puffmoss").is_empty())


func test_play_taps_needs_its_taps() -> void:
	var sim := _sim()
	ActiveTestUtil.arrive(sim, &"buttonbud", T0)
	ActiveTestUtil.give_wish(sim, &"buttonbud", &"tag_game")
	sim.drain_events()
	ActiveTestUtil.act(sim, WishRules.ACT_TAP_CREATURE, {"species": &"buttonbud"}, T0 + 1.0)
	ActiveTestUtil.act(sim, WishRules.ACT_TAP_CREATURE, {"species": &"buttonbud"}, T0 + 2.0)
	assert_true(_grants(sim).is_empty())
	ActiveTestUtil.act(sim, WishRules.ACT_TAP_CREATURE, {"species": &"buttonbud"}, T0 + 3.0)
	assert_eq(_grants(sim).size(), 1, "the third tap")


func test_one_action_grants_every_matching_open_wish() -> void:
	var sim := _sim()
	ActiveTestUtil.arrive(sim, &"puffmoss", T0)
	ActiveTestUtil.arrive(sim, &"pebblepaw", T0)
	ActiveTestUtil.give_wish(sim, &"puffmoss", &"boat_ride")
	ActiveTestUtil.give_wish(sim, &"pebblepaw", &"candle_boat")
	sim.drain_events()
	ActiveTestUtil.act(sim, WishRules.ACT_BOAT, {}, T0 + 5.0)
	assert_eq(_grants(sim).size(), 2)


func test_grant_rewards_rest_twenty_hours_and_stamp_once() -> void:
	var sim := _sim()
	sim.state.tea_unlocked = true
	ActiveTestUtil.arrive(sim, &"puffmoss", T0)
	var aff0 := sim.affection_of(&"puffmoss")
	ActiveTestUtil.give_wish(sim, &"puffmoss", &"brook_song")
	sim.drain_events()
	ActiveTestUtil.act(sim, WishRules.ACT_STREAM_TAP, {}, T0 + 5.0)
	var g := _grants(sim)
	assert_eq(int(g[0]["affection"]), 1)
	assert_true(bool(g[0]["first_stamp"]))
	assert_eq(StringName(g[0]["gift_flower"]), &"sweet_clover", "puffmoss's gift petal (it blooms)")
	assert_eq(int(sim.state.pantry["sweet_clover"]), 1)
	assert_eq(sim.affection_of(&"puffmoss"), aff0 + 1)
	ActiveTestUtil.give_wish(sim, &"puffmoss", &"brook_song")
	ActiveTestUtil.act(sim, WishRules.ACT_STREAM_TAP, {}, T0 + 3600.0)
	g = _grants(sim)
	assert_eq(int(g[0]["affection"]), 0, "within the 20 h rest: no point (the delight and gift remain)")
	assert_false(bool(g[0]["first_stamp"]), "a stamp is earned once")
	assert_eq(sim.affection_of(&"puffmoss"), aff0 + 1)
	ActiveTestUtil.give_wish(sim, &"puffmoss", &"brook_song")
	ActiveTestUtil.act(sim, WishRules.ACT_STREAM_TAP, {}, T0 + 72000.0 + 10.0)
	assert_eq(int(_grants(sim)[0]["affection"]), 1, "after the rest")
	assert_eq(JSON.stringify(sim.active.wishes.stamps(sim, &"puffmoss")), JSON.stringify(["brook_song"]))


func test_gift_petal_respects_the_jar_cap_and_needs_the_nook() -> void:
	var sim := _sim()
	sim.active.features[ActiveRules.FEATURE_TEA] = false
	sim.state.tea_unlocked = false
	ActiveTestUtil.arrive(sim, &"puffmoss", T0)
	ActiveTestUtil.give_wish(sim, &"puffmoss", &"brook_song")
	ActiveTestUtil.act(sim, WishRules.ACT_STREAM_TAP, {}, T0 + 1.0)
	assert_eq(int(sim.state.pantry.get("sweet_clover", 0)), 0, "no gift without the tea nook (no dew instead)")
	sim.active.features[ActiveRules.FEATURE_TEA] = true
	sim.state.tea_unlocked = true
	sim.state.pantry["sweet_clover"] = 24
	ActiveTestUtil.give_wish(sim, &"puffmoss", &"brook_song")
	ActiveTestUtil.act(sim, WishRules.ACT_STREAM_TAP, {}, T0 + 2.0)
	assert_eq(int(sim.state.pantry["sweet_clover"]), 24, "a full jar: the petal stays on the flower")


func test_eligibility_is_fulfillable_now() -> void:
	var sim := _sim()
	var ws := sim.active.wishes
	ActiveTestUtil.arrive(sim, &"puffmoss", T0)
	sim.state.tea_unlocked = false
	assert_false(ws.eligible(sim, &"puffmoss", &"clover_tea", &"day", &"clear"), "tea wishes wait for the nook")
	sim.state.tea_unlocked = true
	assert_true(ws.eligible(sim, &"puffmoss", &"clover_tea", &"day", &"clear"))
	assert_false(ws.eligible(sim, &"puffmoss", &"tidy_primroses", &"day", &"clear"), "no primrose blooms")
	assert_false(ws.eligible(sim, &"puffmoss", &"moonbloom_glow", &"day", &"clear"), "dusk and night only")
	assert_true(ws.eligible(sim, &"puffmoss", &"moonbloom_glow", &"night", &"clear"))
	assert_false(ws.eligible(sim, &"puffmoss", &"rain_splash", &"day", &"clear"))
	assert_false(ws.eligible(sim, &"puffmoss", &"stones_nearby", &"day", &"clear"), "species_only")
	assert_false(ws.eligible(sim, &"puffmoss", &"share_tea", &"day", &"clear"), "needs the best buddy here")
	assert_false(ws.eligible(sim, &"dandelfluff", &"pinwheel_nearby", &"day", &"clear"),
		"a pinwheel already stands by the hill crest: nothing to do")
	sim.active.store(sim, "leaf_pinwheel#0")
	sim.active.store(sim, "leaf_pinwheel#1")
	assert_false(ws.eligible(sim, &"dandelfluff", &"pinwheel_nearby", &"day", &"clear"),
		"nothing placed: the owned gate reads placed pieces")
	sim.active.take_out(sim, &"leaf_pinwheel", Vector2(0.2, 0.43))
	assert_true(ws.eligible(sim, &"dandelfluff", &"pinwheel_nearby", &"day", &"clear"), "placed, and far from the crest")


func test_greeter_brings_a_held_wish_and_never_spawns_one() -> void:
	var sim := _sim()
	sim.state.met["fernwhisk"] = 1.0
	sim.state.met["bellkin"] = 1.0
	ActiveTestUtil.arrive(sim, &"bellkin", T0)
	ActiveTestUtil.give_wish(sim, &"bellkin", &"cuddle")
	ActiveTestUtil.depart(sim, &"bellkin", T0 + 10.0)
	for i in 8:
		var sim2 := WorldSim.new(c, WorldState.from_dict(sim.state.to_dict()))
		var g := sim2.add_greeter(T0 + 20.0)
		assert_eq(g, &"bellkin", "the greeter is the friend holding a wish")
		assert_eq(String(sim2.active.wishes.wish_of(sim2, &"bellkin")["state"]), WorldState.WISH_OPEN, "brought along")
		sim.state.rng_state += 1
	var sim3 := _sim()
	sim3.state.met["fernwhisk"] = 1.0
	sim3.add_greeter(T0)
	sim3.active.wishes.foreground_tick(sim3, 3600.0)
	for w: Dictionary in sim3.state.wishes:
		assert_ne(String(w["species"]), "fernwhisk", "a greeter never spawns a wish")


## Round 8: only a wish the player can SEE may be granted by a décor placement, the same guard
## on_action has. A held wish has no bubble - its slot belongs to another friend - so granting it
## hands out the pose, the stamp, the gift petal and the once-per-20 h affection for a goal that
## was never shown. A wish never expires, so waiting for its bubble costs nothing.
func test_a_placement_never_grants_a_wish_the_player_has_not_seen() -> void:
	var sim := _sim()
	ActiveTestUtil.arrive(sim, &"dandelfluff", T0)
	ActiveTestUtil.give_wish(sim, &"dandelfluff", &"pinwheel_nearby")
	var held: Dictionary = sim.state.wishes[0]
	held["state"] = WorldState.WISH_HELD
	sim.drain_events()
	var fav := sim.active.favourite_spot_pos(sim, &"dandelfluff")
	sim.active.wishes.on_decor_placed(sim, &"leaf_pinwheel", fav, sim.state.t)
	assert_eq(_grants(sim).size(), 0, "a held wish waits for its bubble")
	assert_eq(sim.state.wishes.size(), 1, "and is still there")
	# The same placement, once the bubble is up, grants as before.
	held["state"] = WorldState.WISH_OPEN
	sim.active.wishes.on_decor_placed(sim, &"leaf_pinwheel", fav, sim.state.t)
	assert_eq(_grants(sim).size(), 1, "an open wish is granted")


## HELD means two different things, and only one of them is the bug above: a friend who LEFT keeps
## its wish and is meant to find the piece waiting on its next visit (ACTIVE_WISHES §5).
func test_a_piece_set_while_a_friend_is_away_still_waits_for_it() -> void:
	var sim := _sim()
	ActiveTestUtil.arrive(sim, &"dandelfluff", T0)
	ActiveTestUtil.give_wish(sim, &"dandelfluff", &"pinwheel_nearby")
	var fav := sim.active.favourite_spot_pos(sim, &"dandelfluff")
	ActiveTestUtil.depart(sim, &"dandelfluff", T0 + 10.0)
	sim.drain_events()
	sim.active.wishes.on_decor_placed(sim, &"leaf_pinwheel", fav, sim.state.t)
	var w := sim.active.wishes.wish_of(sim, &"dandelfluff")
	assert_true(bool(w.get("placed", false)), "the piece is remembered for when it comes back")


func test_a_wish_never_disappears_except_by_grant() -> void:
	var sim := _sim(777)
	sim.state.tea_unlocked = true
	var known := {}
	var t := T0
	var friends: Array[StringName] = [&"puffmoss", &"buttonbud", &"honeyhum", &"pebblepaw", &"bellkin"]
	for i in 600:
		t += 60.0
		sim.advance(t)
		if i % 17 == 0:
			var sp := friends[floori(i / 17.0) % friends.size()]
			if sim.is_present(sp):
				ActiveTestUtil.depart(sim, sp, t)
			else:
				ActiveTestUtil.arrive(sim, sp, t)
		sim.active.wishes.foreground_tick(sim, 60.0)
		if i % 5 == 0:
			for kind: StringName in [WishRules.ACT_STREAM_TAP, WishRules.ACT_RING_CHIME, WishRules.ACT_BOAT]:
				ActiveTestUtil.act(sim, kind, {}, t)
			for w: Dictionary in sim.state.wishes.duplicate():
				var sp := StringName(w["species"])
				if String(w["state"]) == WorldState.WISH_OPEN and sim.active.wishes.target_kind(StringName(w["wish"])) == &"pet":
					ActiveTestUtil.act(sim, WishRules.ACT_PET, {"species": sp}, t)
				elif String(w["state"]) == WorldState.WISH_OPEN and i % 10 == 0:
					sim.active.wishes.grant(sim, sp, t)  # every other kind: the grant itself
		var granted := {}
		for e: Dictionary in sim.drain_events():
			if StringName(e["type"]) == WorldSim.EV_WISH_GRANTED:
				granted["%s/%s" % [e["species"], e["wish"]]] = true
		var now := {}
		for w: Dictionary in sim.state.wishes:
			now["%s/%s" % [w["species"], w["wish"]]] = true
		for key: String in known:
			if not now.has(key):
				assert_true(granted.has(key), "%s left only by a grant" % key)
		known = now
	assert_gt(sim.state.wishes_granted, 5)
