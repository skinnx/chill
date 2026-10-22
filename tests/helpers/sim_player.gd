class_name SimPlayer
extends RefCounted
## Test driver: plays a [WorldSim] through a schedule of sessions with a spending policy, the way
## tools/sim/economy_sim.py run_player() does. Only PLAYER behaviour lives here (schedules,
## policies); every game rule is the real WorldSim. Collects the E1/E5/E6 audit counters.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const DAY := 86400.0
const HOUR := 3600.0
const SESSION_LENGTHS_S: Array[float] = [30.0, 180.0, 600.0]
const GAP_MIN_S := 600.0
const GAP_MAX_S := 3.0 * DAY
const GAP_MEDIAN_MIN_S := 1200.0

## name, purchases per session by length (30 s, 3 min, 10 min), buy probability, boat probability
const POLICIES := {
	"gentle": {"budget": {30: 1, 180: 2, 300: 3, 600: 4}, "buy_p": 0.8, "boat_p": 0.3},
	"keen": {"budget": {30: 2, 180: 5, 300: 6, 600: 10}, "buy_p": 1.0, "boat_p": 0.5},
	"greedy": {"budget": {30: 99, 180: 99, 300: 99, 600: 99}, "buy_p": 1.0, "boat_p": 0.0},
	"drain": {"budget": {30: 99, 180: 99, 300: 99, 600: 99}, "buy_p": 1.0, "boat_p": 1.0},
}

var sim: WorldSim
var content: GameContent
var policy: Dictionary
var policy_name: String
var rng := RandomNumberGenerator.new()
var install_unix: float

# audit counters
var sessions: int = 0
var e5_no_afford: int = 0
var e5_no_new: int = 0
var e1_violations: int = 0
var max_display: int = 0
var max_price: int = 0
var first_visit_t: float = INF
var species_after_first_session: int = 0

## Active Play v1 (GDD §14): play the wish clock, help visible wishes, gather, brew and offer.
var active_play: bool = false
var wishes_helped: int = 0
var cups_offered: int = 0

var _last_snapshot: Dictionary = {}
var _last_ambient: String = ""


func _init(p_content: GameContent, seed: int, p_policy: String, install_local_hour: float) -> void:
	content = p_content
	policy_name = p_policy
	policy = POLICIES[p_policy]
	rng.seed = seed
	# Install at the given local hour on 2026-10-20 in UTC (tz offset 0): deterministic phases.
	install_unix = 1792454400.0 + install_local_hour * HOUR
	sim = WorldSim.new_game(content, seed, install_unix, 0.0)


## A heterogeneous random schedule: own session-length mix and own typical gap (10 min - 3 days).
func random_schedule(days: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var mix := [rng.randf(), rng.randf(), rng.randf()]
	var log_med := log(GAP_MEDIAN_MIN_S) + rng.randf() * (log(DAY) - log(GAP_MEDIAN_MIN_S))
	var first: float = [30.0, 180.0, 300.0][_pick([0.1, 0.3, 0.6])]
	out.append(Vector2(0.0, first))
	var t := first
	while true:
		var gap := clampf(exp(log_med + rng.randfn(0.0, 1.0)), GAP_MIN_S, GAP_MAX_S)
		t += gap
		if t >= days * DAY:
			break
		var length := SESSION_LENGTHS_S[_pick(mix)]
		out.append(Vector2(t, length))
		t += length
	return out


## The GDD reference player: 2 x 5 min per day around 08:00 and 20:00 local (install at 20:00).
func reference_schedule(days: int) -> Array[Vector2]:
	var out: Array[Vector2] = [Vector2(0.0, 300.0)]
	var install_local := 20.0 * HOUR
	for d in days + 1:
		for hh: float in [8.0, 20.0]:
			var t := d * DAY + hh * HOUR + (rng.randf() - 0.5) * HOUR - install_local
			if t > 2.0 * HOUR and t < days * DAY:
				out.append(Vector2(t, 300.0))
	out.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	return out


## Plays every session; returns self for chaining.
func play(schedule: Array[Vector2]) -> SimPlayer:
	var seed_tap := rng.randf_range(3.0, 25.0)
	var skip_seed := rng.randf() < 0.10
	_last_snapshot = sim.monotone_snapshot()
	for i in schedule.size():
		var start := schedule[i].x
		var length := schedule[i].y
		sim.advance(start)
		var events := sim.drain_events()
		_check_monotone()
		sessions += 1
		var first := i == 0
		if first and not skip_seed:
			sim.advance(start + seed_tap)
			sim.tap_tutorial_seed()
			events.append_array(sim.drain_events())
		elif not sim.state.seed_planted and i > 0:
			sim.tap_tutorial_seed()
			events.append_array(sim.drain_events())
		# E5 "something new": news since last time, a visitor still here doing something else
		# (bouts are shorter than the 10 min minimum gap), the greeter, or a palette/weather change.
		var ambient := "%s/%s" % [sim.phase_at(sim.state.t), sim.weather_at(sim.state.t)]
		var greeter_possible := sim.real_visitor_count() < int(content.economy["max_present"]) and _met_not_present()
		var new := not events.is_empty()
		var greeter := greeter_possible and (not new or sim.real_visitor_count() == 0)
		if not (first or new or sim.real_visitor_count() > 0 or greeter
				or (ambient != _last_ambient and _last_ambient != "")):
			e5_no_new += 1
		sim.collect()
		_track_display()
		# E5 "affordable": the leaf boat (1 dew) or a catalogue copy; the install session has the seed.
		var cheapest := _cheapest()
		if not (first or sim.state.dew >= int(content.economy["leaf_boat_cost"]) or cheapest <= sim.state.dew):
			e5_no_afford += 1
		var key := int(length) if [30, 180, 300, 600].has(int(length)) else 300
		var budget: int = policy["budget"][key]
		_pet_all()
		budget -= _shop(budget)
		_boats()
		if active_play:
			_active_session(start, length)
		sim.advance(start + length)
		if key >= 180:
			sim.collect()
			_pet_all()
			_track_display()
			_shop(budget)
			_boats()
		sim.drain_events()
		if first:
			species_after_first_session = sim.met_count()
		_last_snapshot = sim.monotone_snapshot()
		_last_ambient = "%s/%s" % [sim.phase_at(sim.state.t), sim.weather_at(sim.state.t)]
	for t: float in sim.state.met.values():
		first_visit_t = minf(first_visit_t, t - install_unix)
	return self


## One minute at a time: the wish clock, then help with visible wishes through the action each
## asks for, gather petals, and brew a cup for a present friend (simple brewing).
func _active_session(start: float, length: float) -> void:
	var t := start
	while t + 60.0 <= start + length:
		t += 60.0
		sim.advance(t)
		sim.active.wishes.foreground_tick(sim, 60.0)
		for w: Dictionary in sim.state.wishes.duplicate():
			if String(w["state"]) != WorldState.WISH_OPEN or rng.randf() > 0.6:
				continue
			_help(StringName(w["species"]), StringName(w["wish"]), t)
		if sim.state.tea_unlocked:
			sim.active.tea.harvest_bed(sim, &"", t)
			if not sim.state.present.is_empty() and rng.randf() < 0.3:
				_brew_and_offer(StringName(sim.state.present[rng.randi_range(0, sim.state.present.size() - 1)]["species"]), t)
			if sim.catalogue_options().is_empty():
				for x: Dictionary in GameContent._records(content.tea["teaware"]):
					if sim.active.tea.buy_teaware(sim, StringName(x["id"])):
						break


func _help(species: StringName, wish: StringName, t: float) -> void:
	var tg: Dictionary = content.wish_targets[wish]
	var before := sim.state.wishes_granted
	match StringName(tg["kind"]):
		&"pet":
			sim.pet(species, sim.unix_at(t))
		&"boat":
			sim.float_boat()
		&"play_taps":
			for i in int(tg["n"]):
				sim.active.wishes.on_action(sim, WishRules.ACT_TAP_CREATURE, {"species": species}, t)
		&"chime_tap":
			sim.active.wishes.on_action(sim, WishRules.ACT_RING_CHIME, {}, t)
		&"stream_tap":
			sim.active.wishes.on_action(sim, WishRules.ACT_STREAM_TAP, {}, t)
		&"decor_tap":
			sim.active.wishes.on_action(sim, WishRules.ACT_DECOR_TAP, {"set": String(tg["arg"])}, t)
		&"bed_invite":
			for s: Dictionary in sim.state.stems:
				if String(s["flower"]) == String(tg["arg"]) and int(s["stage"]) >= WorldSim.STAGE_BLOOM:
					sim.active.wishes.on_action(sim, WishRules.ACT_BED_TAP, {"bed": StringName(s["bed"])}, t)
					break
		&"decor_near":
			var fav := sim.active.favourite_spot_pos(sim, species)
			for p: Dictionary in sim.state.decor_layout:
				if String(p["set"]) == String(tg["arg"]):
					sim.active.move(sim, String(p["id"]), sim.active.decor.offset_norm(fav, Vector2(30.0, 30.0)))
					break
		_:
			_brew_and_offer(species, t)
	if sim.state.wishes_granted > before:
		wishes_helped += 1


func _brew_and_offer(species: StringName, t: float) -> void:
	var best := &""
	for f: Dictionary in content.flowers:
		if sim.active.tea.pantry_of(sim, StringName(f["id"])) >= 2:
			best = StringName(f["id"])
			break
	if best == &"" or sim.state.tray.size() >= 6:
		return
	sim.active.tea.pot_add_petal(sim, best)
	sim.active.tea.pot_add_petal(sim, best)
	if sim.active.tea.pour(sim, true, t) == &"":
		return
	if not sim.active.tea.offer(sim, sim.state.tray.size() - 1, species, t).is_empty():
		cups_offered += 1


func _shop(budget: int) -> int:
	var bought := 0
	while bought < budget:
		if rng.randf() > float(policy["buy_p"]):
			break
		var opts: Array[Dictionary] = []
		for o: Dictionary in sim.catalogue_options():
			if int(o["price"]) <= sim.state.dew:
				opts.append(o)
		if opts.is_empty():
			break
		var o: Dictionary = opts[rng.randi_range(0, opts.size() - 1)]
		var item := StringName(o["item"])
		var ok := sim.buy_flower(item) >= 0 if content.is_flower(item) else sim.buy_decor(item)
		if not ok:
			break
		bought += 1
	return bought


func _boats() -> void:
	var cost := int(content.economy["leaf_boat_cost"])
	if policy_name == "drain":
		while sim.state.dew >= cost:
			sim.float_boat()
	elif sim.state.dew >= cost and rng.randf() < float(policy["boat_p"]):
		sim.float_boat()


func _pet_all() -> void:
	for p: Dictionary in sim.state.present.duplicate():
		sim.pet(StringName(p["species"]), sim.unix_at(sim.state.t))


func _cheapest() -> int:
	var c := 1 << 30
	for o: Dictionary in sim.catalogue_options():
		c = mini(c, int(o["price"]))
	return c


func _met_not_present() -> bool:
	for sp: String in sim.state.met:
		if not sim.is_present(StringName(sp)):
			return true
	return false


func _track_display() -> void:
	for v: int in sim.displayed_values():
		max_display = maxi(max_display, v)
	for o: Dictionary in sim.catalogue_options():
		max_price = maxi(max_price, int(o["price"]))


## E1 between sessions: only the world step ran since the last snapshot (taken after the player's
## actions), so nothing at all may have shrunk: wallet + basket + cup, basket items, stems,
## growth stages, décor, friends met, photos, postcards, affection, boats, owned copies.
func _check_monotone() -> void:
	var now := sim.monotone_snapshot()
	for k: String in _last_snapshot:
		var a: Variant = _last_snapshot[k]
		var b: Variant = now[k]
		if a is Dictionary:
			for key: Variant in a:
				if int((b as Dictionary).get(key, 0)) < int(a[key]):
					e1_violations += 1
		elif float(b) < float(a) - 1e-9:
			e1_violations += 1


func _pick(weights: Array) -> int:
	var tot := 0.0
	for w: Variant in weights:
		tot += float(w)
	var x := rng.randf() * tot
	var acc := 0.0
	for i in weights.size():
		acc += float(weights[i])
		if x < acc:
			return i
	return weights.size() - 1
