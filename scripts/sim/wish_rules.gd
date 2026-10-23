class_name WishRules
extends RefCounted
## Active F1 Wishes (GDD §14, docs/gdd/ACTIVE_WISHES.md; data/wishes.json).
##
## A port of the wish half of tools/sim/economy_sim.py `Player` (wish_check, wish_eligible,
## wish_open, wish_grant, wish_on_arrive, wish_on_depart, wish_fill_slots, greeter_wish) plus the
## fulfilment detection from the actions the player already has (ACTIVE_WISHES §5). [WorldSim]
## owns one instance through [ActiveRules]; the world is passed in as [param sim] on every call.
##
## Guarantees: wishes spawn only in foreground time ([method foreground_tick], never inside
## advance() or catch-up), every random choice is a [RetentionHash] draw keyed by wish_checks
## (AP7; the world RNG stream is never touched), a wish is never removed except by [method grant]
## (a friend who leaves keeps it, held, and brings it back), and wish affection has its own 20 h
## rest per friend (AP6).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## World actions that can grant a wish (Game.world_action kinds).
const ACT_PET := &"pet"
const ACT_TAP_CREATURE := &"tap_creature"
const ACT_RING_CHIME := &"ring_chime"
const ACT_BED_TAP := &"bed_tap"
const ACT_DECOR_TAP := &"decor_tap"
const ACT_STREAM_TAP := &"stream_tap"
const ACT_BOAT := &"boat"
const TEA_KINDS: Array[StringName] = [&"tea", &"tea_kind", &"tea_petal", &"tea_loved"]

var content: GameContent
## Species the creature layer reports as napping, petted, entering or leaving (no new wish).
var busy: PackedStringArray = PackedStringArray()
var _tu: Dictionary
var _rw: Dictionary
var _max_visible: int
var _max_pending: int
var _first_wish_t: float
var _first_wish: StringName
var _onboarding_friends: Array[StringName] = []


func _init(p_content: GameContent) -> void:
	content = p_content
	_tu = content.wishes_doc["tuning"]
	_rw = content.wishes_doc["reward"]
	_max_visible = int(_tu["max_visible"])
	_max_pending = int(_tu["max_pending"])
	var ob: Dictionary = content.economy["onboarding"]
	var fw: Dictionary = _tu["first_wish"]
	_first_wish = StringName(fw["wish"])
	# economy_sim: the first wish comes after_onboarding_s past the onboarding's Poisson start.
	_first_wish_t = float(ob["poisson_start_s"]) + float(fw["after_onboarding_s"])
	for k: String in ["first_visitor", "second_visitor", "third_visitor"]:
		_onboarding_friends.append(StringName(ob[k]))


# ================================================================= reads

func index_of(sim: WorldSim, species: StringName) -> int:
	for i in sim.state.wishes.size():
		if StringName(sim.state.wishes[i]["species"]) == species:
			return i
	return -1


## The pending wish of [param species] ({} if none).
func wish_of(sim: WorldSim, species: StringName) -> Dictionary:
	var i := index_of(sim, species)
	return {} if i < 0 else sim.state.wishes[i]


func visible_count(sim: WorldSim) -> int:
	var n := 0
	for w: Dictionary in sim.state.wishes:
		if String(w["state"]) == WorldState.WISH_OPEN:
			n += 1
	return n


func target(wish: StringName) -> Dictionary:
	return content.wish_targets.get(wish, {})


func target_kind(wish: StringName) -> StringName:
	return StringName(target(wish).get("kind", &""))


func is_tea_wish(wish: StringName) -> bool:
	return TEA_KINDS.has(target_kind(wish))


## Stamps of [param species]: wish ids granted at least once, in data order.
func stamps(sim: WorldSim, species: StringName) -> Array[StringName]:
	var bits := int(sim.state.wish_stamps.get(String(species), 0))
	var out: Array[StringName] = []
	for i in content.wishes.size():
		if bits & (1 << i):
			out.append(StringName(content.wishes[i]["id"]))
	return out


func stamp_count(sim: WorldSim) -> int:
	var n := 0
	for sp: String in sim.state.wish_stamps:
		var bits := int(sim.state.wish_stamps[sp])
		for i in content.wishes.size():
			if bits & (1 << i):
				n += 1
	return n


## View rows for the bubbles, Album and the wish list: [{species, wish, state, icon, title_key,
## hint_key, present, placed, taps, opened_t}], oldest first.
func view(sim: WorldSim) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var list := sim.state.wishes.duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["opened_t"]) < float(b["opened_t"]))
	for w: Dictionary in list:
		out.append(view_of(sim, w))
	return out


func view_of(sim: WorldSim, w: Dictionary) -> Dictionary:
	var def: Dictionary = content.wishes_by_id.get(StringName(w["wish"]), {})
	var tg := target(StringName(w["wish"]))
	return {"species": StringName(w["species"]), "wish": StringName(w["wish"]), "state": StringName(w["state"]),
		"icon": StringName(def.get("icon", "")), "title_key": String(def.get("title_key", "")),
		"hint_key": String(def.get("hint_key", "")), "granted_pose": StringName(def.get("granted_pose", "")),
		"kind": StringName(tg.get("kind", "")), "arg": String(tg.get("arg", "")),
		"present": sim.is_present(StringName(w["species"])),
		"placed": bool(w["placed"]), "taps": int(w["taps"]), "taps_needed": int(tg.get("n", 0)),
		"opened_t": float(w["opened_t"])}


# ================================================================= spawning (ACTIVE_WISHES §4)

## Foreground seconds (Game calls this every frame while the world is unblocked and edit mode is
## off): one [method check] per spawn_check_s, the cadence kept across reloads in wish_fg_s.
## [param blocked] skips the time entirely (a sheet, a card, edit mode).
func foreground_tick(sim: WorldSim, dt: float, blocked: bool = false) -> void:
	if blocked or dt <= 0.0 or not sim.active.feature_on(ActiveRules.FEATURE_WISHES):
		return
	var st := sim.state
	var period := float(_tu["spawn_check_s"])
	st.wish_fg_s += dt
	while st.wish_fg_s >= period:
		st.wish_fg_s -= period
		check(sim, st.t)


## One spawn check at world time [param t] (ACTIVE_WISHES §4.1). [param ph] / [param wx] override
## the phase and weather (the parity test pins them; empty = the world's own).
func check(sim: WorldSim, t: float, ph: StringName = &"", wx: StringName = &"") -> void:
	var st := sim.state
	var n := st.wish_checks
	st.wish_checks += 1
	var present := _present_real(sim)
	if not st.wish_tutorial_done and t >= _first_wish_t:
		for k: StringName in _onboarding_friends:
			if _visit_of(present, k).is_empty() or index_of(sim, k) >= 0:
				continue
			_open(sim, k, _first_wish, t)
			st.wish_tutorial_done = true
			return
	if visible_count(sim) >= _max_visible or st.wishes.size() >= _max_pending:
		return
	if t - st.wish_last_t < float(_tu["global_gap_s"]):
		return
	var seed := st.install_seed
	if RetentionHash.u(seed, ["wish_roll", n]) >= float(_tu["spawn_chance"]):
		return
	var cands: Array[Dictionary] = []
	for p: Dictionary in present:
		var sp := StringName(p["species"])
		if index_of(sim, sp) >= 0 or busy.has(String(sp)):
			continue
		if t - float(p["arrive_t"]) < float(_tu["min_present_s"]):
			continue
		if t - float(st.wish_friend_t.get(String(sp), WorldState.NEVER_T)) < float(_tu["friend_gap_s"]):
			continue
		if _visit_spawns(sim, p) >= int(_tu["max_spawned_per_visit"]):
			continue
		cands.append(p)
	if cands.is_empty():
		return
	var pick_i := mini(cands.size() - 1, floori(RetentionHash.u(seed, ["wish_friend", n]) * cands.size()))
	var k := StringName(cands[pick_i]["species"])
	var phase := ph if ph != &"" else sim.phase_at(t)
	var weather := wx if wx != &"" else sim.weather_at(t)
	var weights := PackedFloat64Array()
	var tot := 0.0
	for w: Dictionary in content.wishes:
		var x := weight(sim, k, StringName(w["id"]), phase, weather)
		weights.append(x)
		tot += x
	if tot <= 0.0:
		return
	var x := RetentionHash.u(seed, ["wish_pick", n]) * tot
	var pick := -1
	for i in weights.size():
		if weights[i] > 0.0:
			pick = i
	var acc := 0.0
	for i in weights.size():
		acc += weights[i]
		if weights[i] > 0.0 and x < acc:
			pick = i
			break
	_open(sim, k, StringName(content.wishes[pick]["id"]), t)


## w = weight x (1 + trait_bonus x matches) x prefer x boost x unseen x repeat (0 if ineligible).
func weight(sim: WorldSim, species: StringName, wish: StringName, ph: StringName, wx: StringName) -> float:
	if not eligible(sim, species, wish, ph, wx):
		return 0.0
	var w: Dictionary = content.wishes_by_id[wish]
	var traits: Array = content.wish_traits.get(species, [])
	var matches := 0
	for tag: Variant in w["tags"]:
		if traits.has(String(tag)):
			matches += 1
	var x := float(w["weight"]) * (1.0 + float(_tu["trait_bonus"]) * matches)
	if Array(w["prefer"]).has(String(species)):
		x *= float(_tu["prefer_mult"])
	var boost: Dictionary = w["boost"]
	# one product, in the reference's order (bit-exact weights for the parity pick)
	x *= float((boost.get("phases", {}) as Dictionary).get(String(ph), 1.0)) \
			* float((boost.get("weather", {}) as Dictionary).get(String(wx), 1.0))
	var bit := 1 << int(content.wish_index[wish])
	if int(sim.state.wish_stamps.get(String(species), 0)) & bit == 0:
		x *= float(_tu["unseen_mult"])
	if String(sim.state.wish_last_id.get(String(species), "")) == String(wish):
		x *= float(_tu["repeat_mult"])
	return x


## The "fulfillable now" rule (ACTIVE_WISHES §4.3): requires hold now; spawn_when gates only
## appearance (fulfilment never re-checks time or weather).
func eligible(sim: WorldSim, species: StringName, wish: StringName, ph: StringName, wx: StringName) -> bool:
	var w: Dictionary = content.wishes_by_id.get(wish, {})
	if w.is_empty():
		return false
	var only: Array = w["species_only"]
	var sw: Dictionary = w["spawn_when"]
	var phases: Array = sw.get("phases", [])
	var weather: Array = sw.get("weather", [])
	if (not only.is_empty() and not only.has(String(species))) or (not phases.is_empty() and not phases.has(String(ph))) \
			or (not weather.is_empty() and not weather.has(String(wx))):
		return false
	var req: Dictionary = w["requires"]
	var feature := StringName(req.get("feature", ""))
	if feature != &"" and not sim.active.feature_on(feature):
		return false
	if feature == ActiveRules.FEATURE_TEA and not sim.state.tea_unlocked:
		return false
	var bloomed: Dictionary = req.get("bloomed", {})
	for f: Variant in bloomed:
		if sim.bloomed_count(StringName(f)) < int(bloomed[f]):
			return false
	var owned: Dictionary = req.get("owned", {})
	for d: Variant in owned:
		if sim.active.decor_placed_count(sim, StringName(d)) < int(owned[d]):
			return false
	if bool(req.get("buddy_present", false)) and not sim.is_present(sim.retention.best_friend(species)):
		return false
	return not (bool(req.get("not_already_near", false)) and _decor_near(sim, species, StringName(target(wish)["arg"])))


## A placed piece of [param set_id] within near_dp of the friend's favourite spot.
func _decor_near(sim: WorldSim, species: StringName, set_id: StringName) -> bool:
	var fav := sim.active.favourite_spot_pos(sim, species)
	return sim.active.decor.nearest_piece_dp(set_id, fav, sim.state.decor_layout) <= float(_tu["near_dp"])


func _open(sim: WorldSim, species: StringName, wish: StringName, t: float) -> void:
	var st := sim.state
	var visible := visible_count(sim) < _max_visible
	st.wishes.append({"species": String(species), "wish": String(wish), "opened_t": t,
		"state": WorldState.WISH_OPEN if visible else WorldState.WISH_HELD, "taps": 0, "placed": false})
	st.wish_last_t = t
	st.wish_friend_t[String(species)] = t
	st.wish_last_id[String(species)] = String(wish)
	var pi := sim.present_index(species)
	var arrive := float(st.present[pi]["arrive_t"]) if pi >= 0 else t
	var vc: Dictionary = st.wish_visit_count.get(String(species), {})
	var n := int(vc.get("n", 0)) if float(vc.get("arrive_t", NAN)) == arrive else 0
	st.wish_visit_count[String(species)] = {"arrive_t": arrive, "n": n + 1}
	sim.emit_event(WorldSim.EV_WISH_OPENED, {"species": species, "wish": wish, "visible": visible}, t)


func _visit_spawns(sim: WorldSim, visit: Dictionary) -> int:
	var vc: Dictionary = sim.state.wish_visit_count.get(String(visit["species"]), {})
	return int(vc.get("n", 0)) if float(vc.get("arrive_t", NAN)) == float(visit["arrive_t"]) else 0


## Real visitors (not the greeter) in album order: the spawn candidates.
func _present_real(sim: WorldSim) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in sim.state.present:
		if not bool(p["greeter"]):
			out.append(p)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return content.album_index(StringName(a["species"])) < content.album_index(StringName(b["species"])))
	return out


static func _visit_of(list: Array[Dictionary], species: StringName) -> Dictionary:
	for p: Dictionary in list:
		if StringName(p["species"]) == species:
			return p
	return {}


# ================================================================= visits (held / open)

## A friend arrived (a real visit or the greeter): a wish placed for it while away is granted; a
## held wish takes a free visible slot.
func on_arrive(sim: WorldSim, species: StringName, t: float) -> void:
	var i := index_of(sim, species)
	if i < 0:
		return
	var w: Dictionary = sim.state.wishes[i]
	if bool(w["placed"]):
		grant(sim, species, t, true)
	elif String(w["state"]) == WorldState.WISH_HELD and visible_count(sim) < _max_visible:
		w["state"] = WorldState.WISH_OPEN
		sim.emit_event(WorldSim.EV_WISH_SHOWN, {"species": species, "wish": StringName(w["wish"])}, t)


## A friend left: its visible wish is held (never lost) and a freed slot goes to the oldest held
## wish of a friend still here.
func on_depart(sim: WorldSim, species: StringName, t: float) -> void:
	var i := index_of(sim, species)
	if i < 0:
		return
	var w: Dictionary = sim.state.wishes[i]
	if String(w["state"]) == WorldState.WISH_OPEN:
		w["state"] = WorldState.WISH_HELD
		sim.emit_event(WorldSim.EV_WISH_HELD, {"species": species, "wish": StringName(w["wish"])}, t)
		fill_slots(sim, t)


func fill_slots(sim: WorldSim, t: float) -> void:
	var held: Array[Dictionary] = []
	for w: Dictionary in sim.state.wishes:
		if String(w["state"]) == WorldState.WISH_HELD and sim.is_present(StringName(w["species"])):
			held.append(w)
	held.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["opened_t"]) < float(b["opened_t"]))
	for w: Dictionary in held:
		if visible_count(sim) >= _max_visible:
			return
		w["state"] = WorldState.WISH_OPEN
		sim.emit_event(WorldSim.EV_WISH_SHOWN, {"species": StringName(w["species"]), "wish": StringName(w["wish"])}, t)


## The greeter (GDD §14.2.3) is preferably a met friend that is away and holds a wish (oldest
## opened_t first, not one already placed for); &"" if none.
func greeter_pick(sim: WorldSim) -> StringName:
	var best := &""
	var best_t := INF
	for w: Dictionary in sim.state.wishes:
		var sp := StringName(w["species"])
		if String(w["state"]) != WorldState.WISH_HELD or bool(w["placed"]) or not sim.is_met(sp) or sim.is_present(sp):
			continue
		if float(w["opened_t"]) < best_t:
			best_t = float(w["opened_t"])
			best = sp
	return best


# ================================================================= fulfilment (ACTIVE_WISHES §5)

## An action the player already has: [param kind] one of ACT_*, [param args] {species} for pet /
## tap_creature, {bed} for bed_tap, {set} for decor_tap, {} otherwise. Every open wish of a present
## friend it matches is granted (one action can grant two wishes). Returns the species granted.
func on_action(sim: WorldSim, kind: StringName, args: Dictionary, t: float) -> Array[StringName]:
	var out: Array[StringName] = []
	if not sim.active.feature_on(ActiveRules.FEATURE_WISHES):
		return out
	# match against the wishes open when the action happened (a slot refilled by a grant waits
	# for the next action), then grant in wish order
	var hits: Array[StringName] = []
	for w: Dictionary in sim.state.wishes:
		var sp := StringName(w["species"])
		if String(w["state"]) != WorldState.WISH_OPEN or not sim.is_present(sp):
			continue
		var tg := target(StringName(w["wish"]))
		var tk := StringName(tg["kind"])
		var arg := String(tg["arg"])
		var hit := false
		match kind:
			ACT_PET:
				hit = tk == &"pet" and StringName(args.get("species", &"")) == sp
			ACT_TAP_CREATURE:
				if tk == &"play_taps" and StringName(args.get("species", &"")) == sp:
					w["taps"] = int(w["taps"]) + 1
					hit = int(w["taps"]) >= maxi(1, int(tg["n"]))
					if not hit:
						sim.emit_event(WorldSim.EV_WISH_PROGRESS, {"species": sp, "wish": StringName(w["wish"]),
							"taps": int(w["taps"]), "needed": int(tg["n"])}, t)
			ACT_RING_CHIME:
				hit = tk == &"chime_tap"
			ACT_BED_TAP:
				hit = tk == &"bed_invite" and _bed_has_bloom(sim, StringName(args.get("bed", &"")), StringName(arg))
			ACT_DECOR_TAP:
				hit = tk == &"decor_tap" and String(args.get("set", "")) == arg
			ACT_STREAM_TAP:
				hit = tk == &"stream_tap"
			ACT_BOAT:
				hit = tk == &"boat"
		if hit:
			hits.append(sp)
	for sp: StringName in hits:
		if grant(sim, sp, t) != &"":
			out.append(sp)
	return out


func _bed_has_bloom(sim: WorldSim, bed: StringName, flower: StringName) -> bool:
	for s: Dictionary in sim.state.stems:
		if StringName(s["bed"]) == bed and StringName(s["flower"]) == flower and int(s["stage"]) >= WorldSim.STAGE_BLOOM:
			return true
	return false


## A cup was offered (TeaRules.offer): the friend's open tea wish is granted if the cup satisfies
## it. Returns the wish granted or &"".
func on_offer(sim: WorldSim, species: StringName, recipe: StringName, petals: Array, t: float) -> StringName:
	var w := wish_of(sim, species)
	if w.is_empty() or String(w["state"]) != WorldState.WISH_OPEN:
		return &""
	var wish := StringName(w["wish"])
	if not is_tea_wish(wish) or not sim.active.tea.satisfies(sim, wish, species, recipe, petals):
		return &""
	grant(sim, species, t)
	return wish


## An Active F3 piece of [param set_id] settled at [param pos] (never mid-drag): a decor_near
## wish whose friend's favourite spot lies within near_dp is granted now if the friend is here,
## else marked placed and granted on its next arrival. Returns the species granted now.
func on_decor_placed(sim: WorldSim, set_id: StringName, pos: Vector2, t: float) -> Array[StringName]:
	var out: Array[StringName] = []
	for w: Dictionary in sim.state.wishes.duplicate():
		var tg := target(StringName(w["wish"]))
		if StringName(tg["kind"]) != &"decor_near" or StringName(tg["arg"]) != set_id or bool(w["placed"]):
			continue
		var sp := StringName(w["species"])
		var fav := sim.active.favourite_spot_pos(sim, sp)
		if sim.active.decor.dist_dp(pos, fav) > float(_tu["near_dp"]):
			continue
		if sim.is_present(sp):
			# Only a wish the player can actually SEE may be granted here, the same guard
			# on_action has (round 8). HELD means two different things: a friend who LEFT keeps
			# its wish (handled below, and granted on its next arrival), but a friend who is
			# HERE and held has no bubble - its slot belongs to another friend - so granting it
			# would hand out the pose, the stamp, the gift petal and the once-per-20 h affection
			# for a goal that was never shown. That one waits for fill_slots; a wish never
			# expires, so nothing is lost by waiting.
			if String(w["state"]) != WorldState.WISH_OPEN:
				continue
			grant(sim, sp, t)
			out.append(sp)
		else:
			w["placed"] = true
			sim.emit_event(WorldSim.EV_WISH_PLACED, {"species": sp, "wish": StringName(w["wish"])}, t)
	return out


## Grants [param species]'s wish atomically (ACTIVE_WISHES §5-§6): removed, stamped the first
## time, +affection_per_wish if its own rest has passed, one gift petal by the shared rule (tea
## unlocked, jar caps respected), and a freed visible slot refilled. Returns the wish granted.
func grant(sim: WorldSim, species: StringName, t: float, on_arrival: bool = false) -> StringName:
	var st := sim.state
	var i := index_of(sim, species)
	if i < 0:
		return &""
	var w: Dictionary = st.wishes[i]
	st.wishes.remove_at(i)
	var wish := StringName(w["wish"])
	st.wishes_granted += 1
	st.wish_last_t = t
	st.wish_friend_t[String(species)] = t
	var bit := 1 << int(content.wish_index[wish])
	var bits := int(st.wish_stamps.get(String(species), 0))
	var first := bits & bit == 0
	st.wish_stamps[String(species)] = bits | bit
	var aff := 0
	if t - float(st.wish_aff_t.get(String(species), -INF)) >= float(_rw["wish_affection_rest_s"]):
		st.wish_aff_t[String(species)] = t
		aff = int(_rw["affection_per_wish"])
		sim.add_affection(species, aff, t)
	var gift := &""
	if st.tea_unlocked:
		var f := sim.active.tea.gift_flower(sim, species)
		if f != &"" and sim.active.tea.add_petals(sim, f, 1) > 0:
			gift = f
	sim.emit_event(WorldSim.EV_WISH_GRANTED, {"species": species, "wish": wish, "affection": aff,
		"gift_flower": gift, "first_stamp": first, "on_arrival": on_arrival,
		"granted_pose": StringName((content.wishes_by_id[wish] as Dictionary).get("granted_pose", ""))}, t)
	fill_slots(sim, t)
	return wish
