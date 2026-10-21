extends GutTest
## Design-principle invariants of the world step (synthesis §4, GDD §5, §9):
## E1 nothing decreases (incl. 30 days away and a clock rollback), E5 abundance, E6 small numbers,
## offline clamp (C14), basket saturation, onboarding pacing and determinism.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const DAY := 86400.0
const HOUR := 3600.0
const BASE_UNIX := 1792454400.0  # 2026-10-20 00:00 UTC
## Smaller than the Python sim's 10,000 + 2,000 (GDScript CI budget); same rules, same checks.
const RANDOM_PLAYERS := 48
const REFERENCE_PLAYERS := 12
const SIM_DAYS := 30

var c: GameContent


func before_all() -> void:
	c = GameContent.load_from_dir()


func _new_sim(seed: int = 7, hour: float = 20.0) -> WorldSim:
	return WorldSim.new_game(c, seed, BASE_UNIX + hour * HOUR, 0.0)


func _play_days(sim: WorldSim, days: int) -> void:
	sim.advance(10.0)
	sim.tap_tutorial_seed()
	var t := 300.0
	while t < days * DAY:
		sim.advance(t)
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
		t += 12.0 * HOUR
	sim.drain_events()


func _assert_not_less(before: Dictionary, after: Dictionary, label: String) -> void:
	for k: String in before:
		var a: Variant = before[k]
		var b: Variant = after[k]
		if a is Dictionary:
			for key: Variant in a:
				assert_true(int((b as Dictionary).get(key, 0)) >= int(a[key]),
						"%s: %s[%s] %s -> %s" % [label, k, key, a[key], (b as Dictionary).get(key, 0)])
		else:
			assert_true(float(b) >= float(a) - 1e-9, "%s: %s %s -> %s" % [label, k, a, b])


# ----------------------------------------------------------------- E1

func test_e1_thirty_days_away_nothing_decreases() -> void:
	var sim := _new_sim()
	_play_days(sim, 3)
	var saved := sim.monotone_snapshot()
	var saved_at := sim.unix_at(sim.state.t)
	var res := sim.catch_up(saved_at + 30.0 * DAY, 0.0, saved_at)
	_assert_not_less(saved, sim.monotone_snapshot(), "30 days away")
	assert_gt(int(res["events"]), 0, "the hollow kept living")


func test_e1_clock_rollback_changes_nothing() -> void:
	var sim := _new_sim()
	_play_days(sim, 2)
	var before := sim.state.to_dict()
	var saved_at := sim.unix_at(sim.state.t)
	var res := sim.catch_up(saved_at - DAY, 0.0, saved_at)
	assert_true(bool(res["rolled_back"]))
	assert_eq(float(res["delta_s"]), 0.0)
	var after := sim.state.to_dict()
	for k: String in before:
		if not String(k).begins_with("anchor"):
			assert_eq(JSON.stringify(after[k]), JSON.stringify(before[k]), "rollback left %s unchanged" % k)
	assert_almost_eq(float(after["anchor_unix"]), saved_at - DAY, 1e-6, "re-anchored to the new now")


func test_e1_no_decay_during_random_play() -> void:
	var total := 0
	for i in 8:
		var p := SimPlayer.new(c, 1000 + i, ["gentle", "keen", "greedy", "drain"][i % 4], 7.0 + i)
		p.play(p.random_schedule(10))
		total += p.e1_violations
	assert_eq(total, 0, "E1 violations across sessions")


# ----------------------------------------------------------------- offline clamp (C14)

func test_offline_delta_is_clamped_to_seven_days() -> void:
	var sim := _new_sim()
	_play_days(sim, 1)
	var t0 := sim.state.t
	var saved_at := sim.unix_at(t0)
	var res := sim.catch_up(saved_at + 30.0 * DAY, 0.0, saved_at)
	var clamp_s := float(c.economy["offline_clamp_s"])
	assert_almost_eq(float(res["delta_s"]), clamp_s, 1e-6)
	assert_almost_eq(float(res["skipped_s"]), 30.0 * DAY - clamp_s, 1e-6)
	assert_almost_eq(sim.state.t, t0 + clamp_s, 1e-6, "world clock advanced exactly 7 days")
	assert_almost_eq(sim.unix_at(sim.state.t), saved_at + 30.0 * DAY, 1e-3, "last event lands at now")


func test_short_gap_is_not_clamped() -> void:
	var sim := _new_sim()
	_play_days(sim, 1)
	var saved_at := sim.unix_at(sim.state.t)
	var res := sim.catch_up(saved_at + 5.0 * HOUR, 0.0, saved_at)
	assert_almost_eq(float(res["delta_s"]), 5.0 * HOUR, 1e-6)
	assert_eq(float(res["skipped_s"]), 0.0)


# ----------------------------------------------------------------- basket saturation

func test_basket_saturates_then_photos() -> void:
	var sim := _new_sim(11)
	_play_days(sim, 3)
	sim.collect()
	var photos_before := sim.photo_count()
	var saved_at := sim.unix_at(sim.state.t)
	sim.catch_up(saved_at + 7.0 * DAY, 0.0, saved_at)
	var slots := int(c.economy["basket_slots"])
	assert_eq(sim.state.basket.size(), slots, "basket is full after a week away")
	assert_true(sim.state.basket_full_seen)
	assert_gt(sim.photo_count(), photos_before, "a full basket turns gifts into photos")
	assert_true(sim.cup_brimming(), "cup brims after dew_cup_saturation_s")
	var ids := sim.state.postcards.map(func(p: Dictionary) -> String: return String(p["id"]))
	assert_has(ids, "brimming", "first full basket sends the brimming postcard")


func test_basket_never_exceeds_slots() -> void:
	var sim := _new_sim(5)
	sim.tap_tutorial_seed()
	var slots := int(c.economy["basket_slots"])
	var t := 0.0
	while t < 14.0 * DAY:
		t += HOUR
		sim.advance(t)
		assert_true(sim.state.basket.size() <= slots)
	assert_eq(sim.state.basket.size(), slots)


func test_saturation_hours_at_mid_game_snugness() -> void:
	# GDD §5.4 table: 24 slots / lambda(S); validation target 10-14 h at S = 60.
	var eco := c.economy
	var s := 60.0
	var lam := float(eco["lambda_min_per_h"]) \
			+ (float(eco["lambda_max_per_h"]) - float(eco["lambda_min_per_h"])) * s / (s + float(eco["snug_half"]))
	var hours := float(eco["basket_slots"]) / lam
	var target: Array = eco["validation_targets"]["basket_saturation_hours"]
	assert_between(hours, float(target[0]), float(target[1]))


func test_cup_stops_filling_after_saturation_and_keeps_remainder() -> void:
	var sim := _new_sim(3)
	sim.advance(10.0)
	sim.collect()
	var sat := float(c.economy["dew_cup_saturation_s"])
	sim.advance(sim.state.t + sat + 6.0 * HOUR)
	var brim := sim.cup_value()
	sim.advance(sim.state.t + DAY)
	assert_almost_eq(sim.cup_value(), brim, 1e-9, "no dew lost, none added while brimming")
	var frac := brim - floorf(brim)
	sim.collect()
	assert_almost_eq(sim.cup_value(), frac, 1e-9, "fractional remainder stays in the cup")


# ----------------------------------------------------------------- E5 / E6

func test_e5_e6_random_and_reference_players() -> void:
	var sessions := 0
	var no_afford := 0
	var no_new := 0
	var max_display := 0
	var max_price := 0
	var policies := ["gentle", "keen", "keen", "gentle", "greedy", "drain"]
	for i in RANDOM_PLAYERS:
		var p := SimPlayer.new(c, 20261020 + i, policies[i % policies.size()], 7.0 + float(i % 16))
		p.play(p.random_schedule(SIM_DAYS))
		sessions += p.sessions
		no_afford += p.e5_no_afford
		no_new += p.e5_no_new
		max_display = maxi(max_display, p.max_display)
		max_price = maxi(max_price, p.max_price)
	for i in REFERENCE_PLAYERS:
		var p := SimPlayer.new(c, 777000 + i, "gentle" if i % 2 == 0 else "keen", 20.0)
		p.play(p.reference_schedule(SIM_DAYS))
		sessions += p.sessions
		no_afford += p.e5_no_afford
		no_new += p.e5_no_new
		max_display = maxi(max_display, p.max_display)
	gut.p("E5/E6 over %d sessions: no_afford %d, no_new %d, max displayed %d, max price %d"
			% [sessions, no_afford, no_new, max_display, max_price])
	assert_gt(sessions, 1000, "enough sessions to mean something")
	assert_eq(no_afford, 0, "E5: every session can buy something")
	assert_eq(no_new, 0, "E5: every session has something new to see")
	var cap := int(c.economy["display_max"])
	assert_true(max_display <= cap, "E6: max displayed %d <= %d" % [max_display, cap])
	assert_true(max_price <= cap, "E6: max price %d" % max_price)


func test_wallet_cap_keeps_gifts_waiting() -> void:
	var sim := _new_sim(9)
	var cap := int(c.economy["wallet_cap"])
	sim.state.dew = cap - 5
	sim.state.basket.append({"species": "puffmoss", "gift_item": "acorn_cup", "dew": 12})
	var got := sim.collect()
	assert_true(sim.state.dew <= cap)
	assert_eq(sim.state.basket.size(), 1, "the gift waits in the basket (brimming jar)")
	assert_true(got <= 5)


# ----------------------------------------------------------------- onboarding and pacing

func test_onboarding_first_five_minutes() -> void:
	var sim := _new_sim(42)
	sim.advance(12.0)
	sim.tap_tutorial_seed()
	sim.advance(300.0)
	var met_t := {}
	for ev: Dictionary in sim.drain_events():
		if ev["type"] == WorldSim.EV_MET:
			met_t[ev["species"]] = float(ev["t"])
	assert_eq(met_t.size(), 3, "3 friends in the first 5 minutes")
	var first := float(met_t[StringName(c.economy["onboarding"]["first_visitor"])])
	assert_between(first, 20.0, 40.0, "first visitor at 20-40 s")
	assert_eq(sim.owned_count(&"sweet_clover"), 1, "the tutorial seed is a free clover")
	assert_eq(sim.price_of(&"sweet_clover"), 17, "clover #2 costs 17 (GDD §3.4)")


func test_untapped_seed_still_brings_visitors() -> void:
	var sim := _new_sim(43)
	sim.advance(300.0)
	assert_eq(sim.met_count(), 3)
	assert_false(sim.state.seed_planted, "the seed waits until tapped (E4)")


func test_world_step_is_deterministic_across_save_and_load() -> void:
	var a := _new_sim(99)
	var b := _new_sim(99)
	_play_days(a, 2)
	_play_days(b, 2)
	var reloaded: Dictionary = JSON.parse_string(JSON.stringify(b.state.to_dict(), "", true, true))
	var mid := WorldSim.new(c, WorldState.from_dict(reloaded))
	a.advance(a.state.t + 5.0 * DAY)
	mid.advance(mid.state.t + 5.0 * DAY)
	# Godot's number parser can return a double 1 ulp away, so floats compare with a relative
	# tolerance; every count, id, string and the RNG state must match exactly.
	assert_eq(TestUtil.canonical(mid.state.to_dict()), TestUtil.canonical(a.state.to_dict()),
		"a save/load in the middle does not change the future")


func test_greeter_gives_no_gift_and_leaves_on_dismiss() -> void:
	var sim := _new_sim(17)
	sim.advance(400.0)
	sim.drain_events()
	var present_before := sim.real_visitor_count()
	var sp := sim.add_greeter(sim.state.t)
	if sp == &"":
		pending("every met friend is present in this seed")
		return
	assert_eq(sim.real_visitor_count(), present_before, "the greeter is not a visit")
	var aff := sim.affection_of(sp)
	sim.dismiss_greeter()
	assert_false(sim.is_present(sp), "the greeter left with the app backgrounded")
	assert_eq(sim.affection_of(sp), aff, "no visit affection for a greeter")
	for ev: Dictionary in sim.drain_events():
		assert_ne(ev["type"], WorldSim.EV_GIFT, "no gift from a greeter")


func test_bed_rules_cluster_and_fill_order() -> void:
	var sim := _new_sim(21)
	sim.state.dew = 10000
	var i1 := sim.buy_flower(&"bluebell", &"bed_3")
	var i2 := sim.buy_flower(&"bluebell")
	assert_eq(String(sim.state.stems[i1]["bed"]), "bed_3", "first copy goes where the player chose")
	assert_eq(String(sim.state.stems[i2]["bed"]), "bed_3", "later copies join the same bed")
	var i3 := sim.buy_flower(&"primrose")
	assert_eq(String(sim.state.stems[i3]["bed"]), "bed_1", "first copy without a choice: lowest fill order")
