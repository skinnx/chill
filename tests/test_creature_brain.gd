extends GutTest
## Creature brain (docs/ARCHITECTURE.md §5.4, GDD §4.1.3): bouts are deterministic per visit and
## survive a save/reload, last 120-360 s, never repeat the previous (behaviour, spot) pair,
## respect spot capacity and décor unlocks, nap more at night, shelter in rain and favour the
## favourite spot.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const SEED := 424242
const DAY_S := 86400.0

var content: GameContent


func before_all() -> void:
	content = GameContent.load_from_dir()


func _brain(seed_v: int, phase: StringName = &"day", weather: StringName = &"clear",
		owned_all: bool = false, beds_planted: bool = true) -> CreatureBrain:
	var b := CreatureBrain.new(content, seed_v)
	b.env = func(_t: float) -> Dictionary: return {"phase": phase, "weather": weather}
	b.owned = func(_item: StringName) -> int: return 10 if owned_all else 0
	b.bed_flowers = func(bed: StringName) -> Array:
		return [&"sweet_clover", &"button_daisy"] if beds_planted and bed == &"bed_1" else []
	return b


func _species_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for s: Dictionary in content.species:
		out.append(StringName(s["id"]))
	return out


## Five visitors with staggered arrivals, planned over [param hours].
func _populate(b: CreatureBrain, hours: float, offset: int = 0) -> Array[StringName]:
	var ids := _species_ids()
	var picked: Array[StringName] = []
	for i in 5:
		var sp := ids[(i + offset) % ids.size()]
		picked.append(sp)
		b.add_visit(sp, 100.0 + 37.0 * float(i), 100.0 + 37.0 * float(i) + hours * 3600.0)
	b.advance(100.0 + hours * 3600.0)
	return picked


func _signature(b: CreatureBrain) -> PackedStringArray:
	var out := PackedStringArray()
	for v: CreatureBrain.Visit in b.visits():
		for bout: CreatureBrain.Bout in v.bouts:
			out.append("%s %s %s %d %.3f %.3f %s" % [v.species, bout.behaviour, bout.spot, bout.slot,
				bout.start_t, bout.end_t, bout.pos])
	return out


func test_visit_seed_is_the_architecture_formula() -> void:
	assert_eq(CreatureBrain.visit_seed(SEED, &"puffmoss", 30.0), hash([SEED, "puffmoss", 30.0]))
	assert_ne(CreatureBrain.visit_seed(SEED, &"puffmoss", 30.0), CreatureBrain.visit_seed(SEED, &"puffmoss", 31.0))


func test_same_visits_plan_the_same_bouts() -> void:
	var a := _brain(SEED)
	var b := _brain(SEED)
	_populate(a, 2.0)
	_populate(b, 2.0)
	var sa := _signature(a)
	assert_gt(sa.size(), 10, "two hours of five visitors plan many bouts")
	assert_eq(sa, _signature(b), "deterministic given the install seed and the visits")
	var c := _brain(SEED + 1)
	_populate(c, 2.0)
	assert_ne(sa, _signature(c), "another install plans differently")


func test_planning_incrementally_equals_planning_at_once() -> void:
	var a := _brain(SEED)
	_populate(a, 3.0)
	var b := _brain(SEED)
	var ids := _species_ids()
	for i in 5:
		b.add_visit(ids[i], 100.0 + 37.0 * float(i), 100.0 + 37.0 * float(i) + 3.0 * 3600.0)
	var t := 100.0
	while t < 100.0 + 3.0 * 3600.0:
		t += 1.0 / 30.0 * 997.0   # uneven steps, like frames over a long session
		b.advance(t)
	b.advance(100.0 + 3.0 * 3600.0)
	assert_eq(_signature(a), _signature(b), "frame-by-frame planning matches a one-shot plan (reload)")


func test_bouts_last_120_to_360_s_and_never_repeat_the_pair() -> void:
	var b := _brain(SEED)
	_populate(b, 6.0)
	var dur: Array = (content.creature_rig["view"]["behaviour"] as Dictionary)["bout_s"]
	for v: CreatureBrain.Visit in b.visits():
		var prev := ""
		for i in v.bouts.size():
			var bout := v.bouts[i]
			var s := bout.end_t - bout.start_t
			var clipped := is_equal_approx(bout.end_t, v.depart_t)
			assert_true(s <= float(dur[1]) + 1e-6, "bout <= 360 s (%s %.0f)" % [v.species, s])
			assert_true(s >= float(dur[0]) - 1e-6 or clipped, "bout >= 120 s unless cut by the departure")
			assert_ne(bout.key(), prev, "%s never repeats %s" % [v.species, prev])
			prev = bout.key()
			if i > 0:
				assert_almost_eq(bout.start_t, v.bouts[i - 1].end_t, 1e-6, "bouts are contiguous")


func test_spot_capacity_is_respected() -> void:
	var b := _brain(SEED, &"day", &"clear", true)
	_populate(b, 8.0, 3)
	var t := 120.0
	while t < 8.0 * 3600.0:
		var used := {}
		for v: CreatureBrain.Visit in b.visits():
			var bout := b.current(v.species, t)
			if bout == null or bout.spot == CreatureBrain.OPEN_FIELD:
				continue
			var key := "%s/%d" % [bout.spot, bout.slot]
			assert_false(used.has(key), "%s is free when %s takes it at %.0f" % [key, v.species, t])
			used[key] = true
			var sp: Dictionary = content.spots_by_id.get(bout.spot, {})
			if not sp.is_empty():
				assert_lt(bout.slot, int(sp["capacity"]), "slot within capacity")
		t += 30.0


func test_decor_spots_only_when_owned() -> void:
	var b := _brain(SEED, &"day", &"clear", false)
	_populate(b, 10.0)
	for v: CreatureBrain.Visit in b.visits():
		for bout: CreatureBrain.Bout in v.bouts:
			var sp: Dictionary = content.spots_by_id.get(bout.spot, {})
			if not sp.is_empty():
				assert_eq(String(sp["requires_item"]), "", "%s needs no décor (none owned)" % bout.spot)


func test_behaviours_only_at_spots_that_allow_them() -> void:
	var b := _brain(SEED, &"day", &"clear", true)
	_populate(b, 10.0, 5)
	for v: CreatureBrain.Visit in b.visits():
		for bout: CreatureBrain.Bout in v.bouts:
			if bout.spot == CreatureBrain.OPEN_FIELD:
				assert_eq(bout.behaviour, CreatureBrain.WANDER, "only wander uses the open field")
				continue
			var bed := CreatureBrain.nibble_bed(bout.spot)
			if bed != &"":
				assert_eq(bout.behaviour, CreatureBrain.NIBBLE, "bed nibble points host nibbling")
				assert_eq(bed, &"bed_1", "only a bed with stems is nibbled")
				continue
			var allows: Array = (content.spots_by_id[bout.spot] as Dictionary)["behaviours"]
			assert_true(allows.has(String(bout.behaviour)), "%s allows %s" % [bout.spot, bout.behaviour])


func test_nibble_falls_back_to_the_clover_bank_without_beds() -> void:
	var b := _brain(SEED, &"day", &"clear", false, false)
	_populate(b, 10.0)
	for v: CreatureBrain.Visit in b.visits():
		for bout: CreatureBrain.Bout in v.bouts:
			if bout.behaviour == CreatureBrain.NIBBLE:
				assert_eq(bout.spot, CreatureBrain.CLOVER_BANK, "no stems anywhere: nibble at the Clover Bank")


func _nap_share(phase: StringName) -> float:
	var naps := 0
	var total := 0
	for k in 12:
		var b := _brain(SEED + k, phase)
		_populate(b, 6.0, k)
		for v: CreatureBrain.Visit in b.visits():
			for bout: CreatureBrain.Bout in v.bouts:
				total += 1
				if bout.behaviour == CreatureBrain.NAP:
					naps += 1
	return float(naps) / float(maxi(total, 1))


func test_night_triples_naps() -> void:
	var day := _nap_share(&"day")
	var night := _nap_share(&"night")
	assert_gt(night, day * 1.6, "night naps (%.2f) well above day naps (%.2f)" % [night, day])


func test_rain_shelters_or_umbrellas_and_rain_likers_play() -> void:
	var b := _brain(SEED, &"day", &"rain", true)
	_populate(b, 8.0, 2)
	for v: CreatureBrain.Visit in b.visits():
		var sp: Dictionary = content.species_by_id[v.species]
		var likes := false
		for l: Dictionary in sp["likes_weather"]:
			likes = likes or String(l["weather"]) == "rain"
		for bout: CreatureBrain.Bout in v.bouts:
			if likes:
				assert_false(bout.umbrella, "%s loves rain: no umbrella" % v.species)
			else:
				assert_true(bout.shelter or bout.umbrella, "%s shelters or holds a leaf in rain" % v.species)
				assert_false(bout.shelter and bout.umbrella, "no umbrella under a shelter")


func test_first_bout_favours_the_favourite_spot() -> void:
	var hits := 0
	var tries := 0
	for k in 60:
		var b := _brain(SEED + 1000 + k)
		b.add_visit(&"pebblepaw", 10.0, 7200.0)
		b.advance(11.0)
		var first := b.current(&"pebblepaw", 10.0)
		if first.behaviour == CreatureBrain.STREAM:
			tries += 1
			if first.spot == &"stream_bend":
				hits += 1
	assert_gt(tries, 10, "pebblepaw often sits by the stream first")
	assert_gt(float(hits) / float(tries), 0.45, "the favourite spot wins about 60 % of first bouts")


func test_capacity_two_spots_pair_players() -> void:
	var b := _brain(SEED)
	b.add_visit(&"honeyhum", 0.0, 4000.0)
	b.add_visit(&"capling", 0.0, 4000.0)
	var x := b.force_bout(&"honeyhum", CreatureBrain.PLAY, &"sun_stone", 0.0, 300.0)
	var y := b.force_bout(&"capling", CreatureBrain.PLAY, &"sun_stone", 0.0, 300.0)
	assert_ne(x.slot, y.slot, "two players share the sun stone in two slots")
	assert_ne(x.pos, y.pos, "slots are apart")


func test_longest_nap_for_the_recap() -> void:
	var b := _brain(SEED)
	b.add_visit(&"puffmoss", 0.0, 4000.0)
	b.force_bout(&"puffmoss", CreatureBrain.NAP, &"sun_stone", 100.0, 300.0)
	var r := b.longest_nap(0.0, 4000.0)
	assert_eq(StringName(r["species"]), &"puffmoss")
	assert_eq(StringName(r["spot"]), &"sun_stone")
	assert_almost_eq(float(r["seconds"]), 300.0, 1e-6)


func test_brain_follows_a_real_sim_across_a_save_reload() -> void:
	var now := 1776500000.0
	var sim := WorldSim.new_game(content, SEED, now, 0.0)
	sim.tap_tutorial_seed()
	sim.advance(5.0 * 3600.0)
	var t := sim.state.t
	var reloaded := WorldSim.new(content, WorldState.from_dict(sim.state.to_dict()))
	var plans: Array[PackedStringArray] = []
	for s: WorldSim in [sim, reloaded]:
		var b := CreatureBrain.new(content, s.state.install_seed)
		b.env = func(at: float) -> Dictionary: return {"phase": s.phase_at(at), "weather": s.weather_at(at)}
		b.owned = func(item: StringName) -> int: return s.owned_count(item)
		b.bed_flowers = func(bed: StringName) -> Array:
			var out: Array = []
			for st: Dictionary in s.state.stems:
				if StringName(st["bed"]) == bed:
					out.append(StringName(st["flower"]))
			return out
		for p: Dictionary in s.state.present:
			b.add_visit(StringName(p["species"]), float(p["arrive_t"]), float(p["depart_t"]), bool(p["greeter"]))
		b.advance(t)
		var sig := PackedStringArray()
		for p: Dictionary in s.state.present:
			var bout := b.current(StringName(p["species"]), t)
			assert_not_null(bout, "every visitor is doing something at t")
			sig.append("%s %s %s" % [p["species"], bout.behaviour, bout.spot])
		plans.append(sig)
	assert_gt(plans[0].size(), 0, "someone is visiting after five hours")
	assert_eq(plans[0], plans[1], "the same visit looks the same after a reload")


func test_forced_bouts_carry_the_rain_umbrella_rule() -> void:
	var b := _brain(SEED, &"day", &"rain")
	b.add_visit(&"buttonbud", 0.0, 3600.0)
	b.add_visit(&"puddlewump", 0.0, 3600.0)
	var dry := b.force_bout(&"buttonbud", &"wander", &"clover_bank", 10.0, 60.0)
	assert_true(dry.umbrella, "a forced bout in rain away from shelter holds a leaf")
	var wet := b.force_bout(&"puddlewump", &"play", &"stream_bend", 10.0, 60.0)
	assert_false(wet.umbrella, "puddlewump loves rain: no umbrella")
