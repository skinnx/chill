class_name WorldSim
extends RefCounted
## The deterministic world step (GDD §5, docs/ARCHITECTURE.md §5).
##
## A GDScript port of tools/sim/economy_sim.py `Player` (the reference implementation the economy
## was validated with): one event-driven [method advance] for live play and offline catch-up.
## Pure: no nodes, no autoloads, no wall clock. Time comes in as arguments (world seconds, unix
## seconds, time-zone offset), so the whole game history is reproducible from the save and tests
## run headless in milliseconds.
##
## Invariant E1: nothing in [method advance] removes or decreases anything the player owns.
## Only explicit player actions (buy, float_boat, collect moving dew from basket to wallet)
## spend or move value, and they never fail into a loss.
##
## Output: every change is appended to an event outbox ([method drain_events]); the Game autoload
## turns events into signals for views, the recap and audio.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

# ---------------------------------------------------------------- event types (outbox)
const EV_ARRIVED := &"arrived"            ## {species, t, debut, peek, scripted, from_greeter, depart_t}
const EV_DEPARTED := &"departed"          ## {species, t, gift_dew}
const EV_GREETER_ARRIVED := &"greeter_arrived"  ## {species, t}
const EV_GREETER_LEFT := &"greeter_left"  ## {species, t}
const EV_MET := &"met"                    ## {species, t}
const EV_GIFT := &"gift"                  ## {species, gift_item, dew, slot, t}
const EV_PHOTO := &"photo"                ## {species, pose, new, t}
const EV_BASKET_FULL := &"basket_full"    ## {t}
const EV_STAGE := &"stage"                ## {stem, flower, stage, t}  stage 3 = bloom
const EV_HEARTS := &"hearts"              ## {species, hearts, t}
const EV_POSTCARD := &"postcard"          ## {id, template, species, t}
const EV_COLLECTED := &"collected"        ## {dew, gifts, cup, kept, t}
const EV_PLANTED := &"planted"            ## {stem, flower, bed, slot, tutorial, cost, t}
const EV_PLACED := &"placed"              ## {decor, index, cost, t}
const EV_BOAT := &"boat"                  ## {count, watchers, t}
const EV_PETTED := &"petted"              ## {species, credited, t}
# Retention v1 (GDD §13.9; RetentionRules emits these)
const EV_MYSTERY_OPENED := &"mystery_opened"  ## {mystery, kind, target, signs, t}
const EV_SIGN_DUE := &"sign_due"          ## {key, mystery, index, sign, species, variant, anchor, appear_t, ...}
const EV_SIGN_VISIBLE := &"sign_visible"  ## same fields; anchor set (at most max_visible at once)
const EV_CLUE := &"clue"                  ## sign fields + {riddle_key, found, total, solved}
const EV_NEST_STAGE := &"nest_stage"      ## {species, style, stage, stage_id, built}
const EV_SCENE_STAGED := &"scene_staged"  ## {scene, cast, phase, weather, world_t, shown_s, resumed, ...}
const EV_SCENE_ARCHIVED := &"scene_archived"  ## memory {scene, cast, phase, weather, world_t, unix, index}
const EV_COUSIN_MET := &"cousin_met"      ## {variant, species}
const EV_COUSIN_ARRIVED := &"cousin_arrived"  ## {variant, species, first}
const EV_KEEPSAKE := &"keepsake"          ## {species}

const STAGE_SEED := 0
const STAGE_SPROUT := 1
const STAGE_BUD := 2
const STAGE_BLOOM := 3
const ROLE_FIRST := "first"
const ROLE_SECOND := "second"
const ROLE_THIRD := "third"
const KIND_ARRIVE := "arrive"
const KIND_POSTCARD := "postcard"

var content: GameContent
var state: WorldState
## Retention v1 rules (GDD §13): mysteries, signs, nests, cousins, scenes. Holds no reference back.
var retention: RetentionRules

var _eco: Dictionary
var _ob: Dictionary
var _rng := RandomNumberGenerator.new()
var _weather: WeatherPlan
var _events: Array[Dictionary] = []
## Derived caches (rebuilt from state, never saved).
var _bloomed: Dictionary = {}
var _snug: float = 0.0
var _cup_rate_h: float = 0.0
var _lmin: float = 0.0
var _lmax: float = 0.0
var _lhalf: float = 1.0
## Earliest pending event time; INF-safe sentinel. Valid while not _dirty.
var _next_t: float = 0.0
var _dirty: bool = true
## Cached [time, stem index] of the next growth stage; rebuilt only when stems change.
var _growth_next: Array = [INF, -1]
var _growth_dirty: bool = true


func _init(p_content: GameContent, p_state: WorldState) -> void:
	content = p_content
	state = p_state
	_eco = content.economy
	_ob = _eco["onboarding"]
	_rng.state = state.rng_state
	_weather = WeatherPlan.new(content, state.install_seed)
	_lmin = float(_eco["lambda_min_per_h"]) / TodMath.SECONDS_PER_HOUR
	_lmax = float(_eco["lambda_max_per_h"]) / TodMath.SECONDS_PER_HOUR
	_lhalf = float(_eco["snug_half"])
	retention = RetentionRules.new(content)
	_rebuild_caches()
	if state.retention_v < WorldState.RETENTION_VERSION:
		retention.migrate_v1(self)  # a schema-1 save (GDD §13.6); events reach the next drain


## A fresh install: world clock 0 at [param now_unix], onboarding scheduled (GDD §3.4).
static func new_game(p_content: GameContent, install_seed: int, now_unix: float, tz_offset_s: float) -> WorldSim:
	var st := WorldState.new()
	st.install_seed = install_seed
	st.installed_unix = now_unix
	st.anchor_world_t = 0.0
	st.anchor_unix = now_unix
	st.tz_offset_s = tz_offset_s
	var seeder := RandomNumberGenerator.new()
	seeder.seed = install_seed
	st.rng_state = seeder.state
	st.retention_v = WorldState.RETENTION_VERSION
	var sim := WorldSim.new(p_content, st)
	sim._start_onboarding()
	return sim


# ================================================================= clock mapping

func unix_at(t: float) -> float:
	return state.anchor_unix + (t - state.anchor_world_t)


func local_at(t: float) -> float:
	return unix_at(t) + state.tz_offset_s


func phase_at(t: float) -> StringName:
	return TodMath.phase_id_at(content, local_at(t))


func weather_at(t: float) -> StringName:
	return _weather.weather_at(local_at(t))


func season_at(t: float) -> StringName:
	return content.season_for_world_day(floori(t / TodMath.SECONDS_PER_DAY))


## Pins world second [param world_t] to wall time [param now_unix] (resume, launch, save).
func set_anchor(world_t: float, now_unix: float, tz_offset_s: float) -> void:
	state.anchor_world_t = world_t
	state.anchor_unix = now_unix
	state.tz_offset_s = tz_offset_s


## Offline progress on launch/resume (GDD §5.8, synthesis C14):
## delta = clamp(now - saved_at, 0, offline_clamp_s); time beyond the clamp is skipped ("the hollow
## rested"); a clock rolled back gives delta 0 and simply re-anchors. Events are timed so that the
## last one lands at now: wall(t_event) = now - (world_end - t_event).
func catch_up(now_unix: float, tz_offset_s: float, saved_at_unix: float) -> Dictionary:
	var raw := now_unix - saved_at_unix
	var clamp_s := float(_eco["offline_clamp_s"])
	var delta := clampf(raw, 0.0, clamp_s)
	var world_end := state.t + delta
	set_anchor(world_end, now_unix, tz_offset_s)
	var n := advance(world_end)
	return {"raw_s": raw, "delta_s": delta, "skipped_s": maxf(0.0, raw - clamp_s), "rolled_back": raw < 0.0, "events": n}


# ================================================================= the world step

## Processes every world event in (t, to_t] in time order (ties: scripted -> growth -> departure
## -> candidate, as the reference). Returns the number of events processed. Never goes back.
func advance(to_t: float) -> int:
	if to_t <= state.t:
		return 0
	if not _dirty and to_t < _next_t:
		_settle_cup(to_t)
		state.t = to_t
		return 0
	var n := 0
	while true:
		var t_scr: float = state.scripted[0]["t"] if not state.scripted.is_empty() else INF
		if _growth_dirty:
			_growth_next = _next_growth()
			_growth_dirty = false
		var gro := _growth_next
		var t_gro: float = gro[0]
		var dep := _next_departure()
		var t_dep: float = dep[0]
		var t_can := state.next_candidate_t
		var t_ret := retention.next_event_t(self, state.t)
		var t_next := minf(minf(minf(t_scr, t_gro), minf(t_dep, t_can)), t_ret)
		if t_next > to_t:
			_next_t = t_next
			_dirty = false
			break
		var prev_t := state.t
		state.t = maxf(state.t, t_next)
		n += 1
		if t_next == t_scr:
			var ev: Dictionary = state.scripted.pop_front()
			if ev["kind"] == KIND_ARRIVE:
				_arrive(t_next, StringName(ev["species"]), float(ev["stay_s"]), int(ev["gift_dew"]), true)
			else:
				_send_event_postcard_id(String(ev["id"]), t_next)
		elif t_next == t_gro:
			_grow(int(gro[1]), t_next)
			_growth_dirty = true
		elif t_next == t_ret:
			retention.process(self, prev_t, t_next)
		elif t_next == t_dep:
			_depart(int(dep[1]), t_next)
		else:
			_candidate(t_next)
			state.next_candidate_t += _expo(_lmax)
	_settle_cup(to_t)
	state.t = to_t
	return n


func drain_events() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out


func has_events() -> bool:
	return not _events.is_empty()


# ================================================================= player actions

## The glowing tutorial seed (GDD §3.4): a free copy of the tutorial flower with fast stages.
## Tapping within the tap window pulls the first two scripted visitors forward. Returns the stem
## index, or -1 if already planted.
func tap_tutorial_seed() -> int:
	if state.seed_planted:
		return -1
	var t := state.t
	var flower := StringName(_ob["tutorial_flower"])
	var bed := StringName(_ob["tutorial_bed"])
	if not GardenRules.has_room(content, state.stems, bed):
		bed = GardenRules.auto_bed(content, state.stems, flower)
	var slot := GardenRules.choose_slot(content, state.stems, bed, flower)
	state.seed_planted = true
	state.seed_tap_t = t
	state.owned[String(flower)] = owned_count(flower) + 1
	state.stems.append({"flower": String(flower), "bed": String(bed), "slot": slot, "planted_t": t,
		"tutorial": true, "stage": STAGE_SEED})
	var idx := state.stems.size() - 1
	_growth_dirty = true
	if t <= float(_ob["tutorial_tap_window_s"]):
		var t1 := clampf(t + float(_ob["first_visitor_after_plant_s"]), float(_ob["first_visitor_min_s"]),
			float(_ob["first_visitor_max_s"]))
		_reschedule(ROLE_FIRST, t1)
		var bloom_t := t + float(_ob["tutorial_bloom_at_s"])
		_reschedule(ROLE_SECOND, minf(bloom_t + float(_ob["second_visitor_after_bloom_s"]),
				float(_ob["second_visitor_latest_s"])))
	_emit(EV_PLANTED, {"stem": idx, "flower": flower, "bed": bed, "slot": slot, "tutorial": true, "cost": 0})
	_dirty = true
	return idx


## Plant one copy of [param flower_id]. [param bed_id] empty = rules 1-2 pick the bed (GDD §2.4).
## Returns the new stem index or -1 (not affordable, all copies owned, or no bed has room).
func buy_flower(flower_id: StringName, bed_id: StringName = &"") -> int:
	if not content.is_flower(flower_id) or not can_buy(flower_id):
		return -1
	var bed := bed_id
	if bed == &"" or not GardenRules.has_room(content, state.stems, bed):
		bed = GardenRules.auto_bed(content, state.stems, flower_id)
	if bed == &"":
		return -1
	var slot := GardenRules.choose_slot(content, state.stems, bed, flower_id)
	var cost := price_of(flower_id)
	state.dew -= cost
	state.items_bought += 1
	state.owned[String(flower_id)] = owned_count(flower_id) + 1
	state.stems.append({"flower": String(flower_id), "bed": String(bed), "slot": slot, "planted_t": state.t,
		"tutorial": false, "stage": STAGE_SEED})
	var idx := state.stems.size() - 1
	_growth_dirty = true
	_emit(EV_PLANTED, {"stem": idx, "flower": flower_id, "bed": bed, "slot": slot, "tutorial": false, "cost": cost})
	_dirty = true
	return idx


## Place one copy of [param decor_id] at the next anchor position (GDD §2.5). Returns success.
func buy_decor(decor_id: StringName) -> bool:
	if not content.is_decor(decor_id) or not can_buy(decor_id):
		return false
	var cost := price_of(decor_id)
	var first_ever := total_decor_owned() == 0
	state.dew -= cost
	state.items_bought += 1
	var index := owned_count(decor_id)
	state.owned[String(decor_id)] = index + 1
	_snug += float(content.decor_by_id[decor_id]["snug"])
	_emit(EV_PLACED, {"decor": decor_id, "index": index, "cost": cost})
	if first_ever:
		_send_event_postcard(&"first_decor", state.t)
	retention.check_mysteries(self, state.t)
	_dirty = true
	return true


## Collect all (GDD §5.7): every gift that fits under the wallet cap plus floor(cup); the
## fractional cup remainder stays; gifts above the cap wait in the basket. Returns dew gained.
func collect() -> int:
	_settle_cup(state.t)
	var cap := int(_eco["wallet_cap"])
	var got := 0
	var gifts := 0
	var keep: Array[Dictionary] = []
	for g: Dictionary in state.basket:
		var v := int(g["dew"])
		if state.dew + got + v <= cap:
			got += v
			gifts += 1
		else:
			keep.append(g)
	var cup_whole := floori(state.cup)
	var cup_take := maxi(0, mini(cup_whole, cap - state.dew - got))
	state.cup -= cup_take
	got += cup_take
	state.basket = keep
	state.dew += got
	state.last_collect_t = state.t
	state.cup_last_t = state.t
	_emit(EV_COLLECTED, {"dew": got, "gifts": gifts, "cup": cup_take, "kept": keep.size()})
	_dirty = true
	return got


## The always-affordable ritual (GDD §4.4): every real visitor that has not watched a boat this
## visit gains affection. Returns false only when the wallet is below the boat cost.
func float_boat() -> bool:
	var cost := int(_eco["leaf_boat_cost"])
	if state.dew < cost:
		return false
	state.dew -= cost
	state.boats += 1
	var watchers: Array[StringName] = []
	for p: Dictionary in state.present:
		if not p["greeter"] and not p["boat_credit"]:
			p["boat_credit"] = true
			watchers.append(StringName(p["species"]))
			_add_affection(StringName(p["species"]), int(_eco["affection_per_boat"]), state.t)
	_emit(EV_BOAT, {"count": state.boats, "watchers": watchers})
	if state.boats == 10:
		_send_event_postcard(&"boats_10", state.t)
	return true


## Pet a mossling in the hollow (GDD §5.10, §5.6). Affection once per visit; for the greeter only
## if that friend was not petted within greeter_pet_cooldown_s. The UI never states the credit.
func pet(species: StringName, now_unix: float) -> bool:
	var i := _present_index(species)
	if i < 0:
		return false
	var p: Dictionary = state.present[i]
	var credited := false
	if p["greeter"]:
		var last := float(state.last_pet_unix.get(String(species), -INF))
		credited = now_unix - last >= float(_eco["greeter_pet_cooldown_s"])
	else:
		credited = not p["pet_credit"]
		p["pet_credit"] = true
	if credited:
		state.last_pet_unix[String(species)] = now_unix
		_add_affection(species, int(_eco["affection_per_pet"]), state.t)
	_emit(EV_PETTED, {"species": species, "credited": credited})
	return credited


## Greeter rule (GDD §5.6): a met friend that is not here strolls in to say hello. No gift and no
## visit affection, so opening the app often is never an advantage. Returns the species or &"".
func add_greeter(at_t: float) -> StringName:
	if real_visitor_count() >= int(_eco["max_present"]) or _greeter_index() >= 0:
		return &""
	var pool: Array[StringName] = []
	for s: Dictionary in content.species:
		var id := StringName(s["id"])
		if is_met(id) and _present_index(id) < 0:
			pool.append(id)
	if pool.is_empty():
		return &""
	var species := pool[_rng.randi_range(0, pool.size() - 1)]
	state.rng_state = _rng.state
	state.present.append({"species": String(species), "arrive_t": at_t,
		"depart_t": at_t + float(_eco["greeter_stay_s"]), "gift_dew": 0, "gift_item": "",
		"boat_credit": true, "pet_credit": false, "scripted": false, "greeter": true, "cousin": ""})
	_emit(EV_GREETER_ARRIVED, {"species": species})
	_dirty = true
	return species


## The greeter leaves when the app is backgrounded (GDD §5.6).
func dismiss_greeter() -> void:
	var i := _greeter_index()
	if i >= 0:
		var p: Dictionary = state.present[i]
		state.present.remove_at(i)
		_emit(EV_GREETER_LEFT, {"species": StringName(p["species"])})
		_dirty = true


func set_custom_name(species: StringName, raw_name: String) -> String:
	var clean := NameRules.sanitize(raw_name)
	if clean.is_empty():
		state.names.erase(String(species))
	else:
		state.names[String(species)] = clean
	return clean


func mark_postcard_read(id: String) -> void:
	for p: Dictionary in state.postcards:
		if p["id"] == id:
			p["read"] = true


# ================================================================= queries

func owned_count(item_id: StringName) -> int:
	return int(state.owned.get(String(item_id), 0))


func bloomed_count(flower_id: StringName) -> int:
	return int(_bloomed.get(flower_id, 0))


## Attraction counts: bloomed stems for flowers, copies for décor (GDD §4.1.4).
func item_count(item_id: StringName) -> int:
	return bloomed_count(item_id) if content.is_flower(item_id) else owned_count(item_id)


func total_decor_owned() -> int:
	var n := 0
	for d: Dictionary in content.decor:
		n += owned_count(StringName(d["id"]))
	return n


func price_of(item_id: StringName) -> int:
	return content.price(item_id, owned_count(item_id))


func is_maxed(item_id: StringName) -> bool:
	return owned_count(item_id) >= content.max_copies(item_id)


func can_buy(item_id: StringName) -> bool:
	if is_maxed(item_id) or price_of(item_id) > state.dew:
		return false
	if content.is_flower(item_id):
		return not GardenRules.beds_with_room(content, state.stems).is_empty()
	return true


## The first copy of a flower type asks the player to choose a bed (GDD §2.4 rule 1).
func needs_bed_choice(flower_id: StringName) -> bool:
	for s: Dictionary in state.stems:
		if StringName(s["flower"]) == flower_id:
			return false
	return true


## (item id, price) of every copy that can still be bought, flowers then décor.
func catalogue_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f: Dictionary in content.flowers:
		var id := StringName(f["id"])
		if not is_maxed(id):
			out.append({"item": id, "price": price_of(id)})
	for d: Dictionary in content.decor:
		var id := StringName(d["id"])
		if not is_maxed(id):
			out.append({"item": id, "price": price_of(id)})
	return out


func snugness() -> float:
	return _snug


## lambda(S) = lambda_min + (lambda_max - lambda_min) * S / (S + S_half), per hour (GDD §5.4).
func lambda_per_h() -> float:
	return _lam() * TodMath.SECONDS_PER_HOUR


func cup_rate_per_h() -> float:
	return _cup_rate_h


func cup_value() -> float:
	return state.cup


func cup_brimming() -> bool:
	return state.t >= state.last_collect_t + float(_eco["dew_cup_saturation_s"])


func basket_full() -> bool:
	return state.basket.size() >= int(_eco["basket_slots"])


func basket_dew() -> int:
	var n := 0
	for g: Dictionary in state.basket:
		n += int(g["dew"])
	return n


func is_met(species: StringName) -> bool:
	return state.met.has(String(species))


func met_count() -> int:
	return state.met.size()


func affection_of(species: StringName) -> int:
	return int(state.affection.get(String(species), 0))


func hearts_of(species: StringName) -> int:
	return content.hearts_for(affection_of(species))


func is_present(species: StringName) -> bool:
	return _present_index(species) >= 0


func real_visitor_count() -> int:
	var n := 0
	for p: Dictionary in state.present:
		if not p["greeter"]:
			n += 1
	return n


func photo_count() -> int:
	var n := 0
	for k: String in state.photos:
		var bits := int(state.photos[k])
		for i in WorldState.POSE_COUNT:
			if bits & (1 << i):
				n += 1
	return n


## Passive income right now in dew/min: cup rate + expected visitor gifts (GDD §5.3).
func income_per_min() -> float:
	var t := state.t
	var ph := phase_at(t)
	var wx := weather_at(t)
	var tw := 0.0
	var tg := 0.0
	for s: Dictionary in content.species:
		var id := StringName(s["id"])
		if _eligible_ignoring_presence(id, ph, t):
			var w := _weight(id, ph, wx)
			tw += w
			tg += w * float(s["gift_dew"])
	var g := tg / tw if tw > 0.0 else 0.0
	return (_cup_rate_h + lambda_per_h() * g) / 60.0


## Values that may be shown on screen (E6 audit): wallet, basket total, cup, every price.
func displayed_values() -> PackedInt32Array:
	var out := PackedInt32Array([state.dew, basket_dew(), floori(state.cup)])
	for o: Dictionary in catalogue_options():
		out.append(int(o["price"]))
	return out


## Everything that must never decrease without a player action (E1 checks).
func monotone_snapshot() -> Dictionary:
	var stages := 0
	for s: Dictionary in state.stems:
		stages += int(s["stage"])
	return {"wallet_plus_basket_plus_cup": float(state.dew + basket_dew()) + state.cup,
		"basket_items": state.basket.size(), "stems": state.stems.size(), "growth_stages": stages,
		"decor": total_decor_owned(), "met": met_count(), "photos": photo_count(),
		"postcards": state.postcards.size(), "affection": state.affection.duplicate(), "boats": state.boats,
		"owned": state.owned.duplicate(), "t": state.t,
		# Retention v1 (G1): hearts, nest stages, clues + waiting signs, cousins, memories, keepsakes
		"hearts": _hearts_map(), "nest_stages": _nest_stage_map(), "clues_and_signs": _clue_total() + state.signs.size(),
		"mysteries": state.mysteries.size(), "cousins": state.variants_met.size(),
		"memories_and_pending": state.memories.size() + (0 if state.pending_scene.is_empty() else 1),
		"scenes_seen": state.scenes_seen.duplicate(), "keepsakes": state.keepsakes.size(),
		"signature_gifts": state.signature_gifts.size(),
		"postcards_and_waiting": state.postcards.size() + state.postcards_waiting.size()}


func _hearts_map() -> Dictionary:
	var out := {}
	for s: Dictionary in content.species:
		out[String(s["id"])] = hearts_of(StringName(s["id"]))
	return out


func _nest_stage_map() -> Dictionary:
	var out := {}
	for sp: String in state.nests:
		out[sp] = int((state.nests[sp] as Dictionary)["stage"])
	return out


func _clue_total() -> int:
	var n := 0
	for m: String in state.clues:
		n += retention.clue_count(self, m)
	return n


# ================================================================= internals: events

func _start_onboarding() -> void:
	state.next_candidate_t = float(_ob["poisson_start_s"]) + _expo(_lmax)
	_schedule(float(_ob["first_visitor_default_s"]), KIND_ARRIVE, StringName(_ob["first_visitor"]),
		float(_ob["first_visitor_stay_s"]), int(_ob["first_visitor_gift_dew"]), "", ROLE_FIRST)
	_schedule(float(_ob["second_visitor_latest_s"]), KIND_ARRIVE, StringName(_ob["second_visitor"]),
		float(_ob["second_visitor_stay_s"]), int(_ob["second_visitor_gift_dew"]), "", ROLE_SECOND)
	var third := StringName(_ob["third_visitor"])
	var stay3 := _uniform(float(_eco["stay_min_s"]), float(_eco["stay_max_s"])) \
			* float(content.species_by_id[third]["stay_mult"])
	_schedule(float(_ob["third_visitor_at_s"]), KIND_ARRIVE, third, stay3, 0, "", ROLE_THIRD)
	var welcome: Dictionary = content.event_postcards_by_trigger.get(&"onboarding", {})
	if not welcome.is_empty():
		_schedule(float(_ob["welcome_postcard_at_s"]), KIND_POSTCARD, &"", 0.0, 0, String(welcome["id"]), "")


func _schedule(t: float, kind: String, species: StringName, stay_s: float, gift_dew: int, id: String,
		role: String) -> void:
	var ev := {"t": t, "kind": kind, "species": String(species), "stay_s": stay_s, "gift_dew": gift_dew,
		"id": id, "role": role}
	var i := state.scripted.size()
	while i > 0 and float(state.scripted[i - 1]["t"]) > t:
		i -= 1
	state.scripted.insert(i, ev)
	_dirty = true


func _reschedule(role: String, t: float) -> void:
	for i in state.scripted.size():
		var ev: Dictionary = state.scripted[i]
		if ev["role"] == role:
			state.scripted.remove_at(i)
			_schedule(maxf(t, state.t), String(ev["kind"]), StringName(ev["species"]), float(ev["stay_s"]),
				int(ev["gift_dew"]), String(ev["id"]), role)
			return


func _next_growth() -> Array:
	var best_t := INF
	var best_i := -1
	var best_stage := 99
	for i in state.stems.size():
		var s: Dictionary = state.stems[i]
		var stage := int(s["stage"])
		if stage >= STAGE_BLOOM:
			continue
		var t := float(s["planted_t"]) + _stage_times(s)[stage]
		if t < best_t or (t == best_t and stage < best_stage):
			best_t = t
			best_i = i
			best_stage = stage
	return [best_t, best_i]


func _next_departure() -> Array:
	var best_t := INF
	var best_i := -1
	for i in state.present.size():
		var t := float(state.present[i]["depart_t"])
		if t < best_t:
			best_t = t
			best_i = i
	return [best_t, best_i]


## Cumulative stage times [sprout, bud, bloom] for a stem (tutorial seed: onboarding times).
func _stage_times(stem: Dictionary) -> PackedFloat64Array:
	if stem["tutorial"]:
		return PackedFloat64Array([float(_ob["tutorial_sprout_at_s"]), float(_ob["tutorial_bud_at_s"]),
			float(_ob["tutorial_bloom_at_s"])])
	var f: Dictionary = content.flowers_by_id[StringName(stem["flower"])]
	return PackedFloat64Array([float(f["sprout_at_s"]), float(f["bud_at_s"]), float(f["bloom_at_s"])])


func _grow(i: int, t: float) -> void:
	var stem: Dictionary = state.stems[i]
	var stage := int(stem["stage"]) + 1
	var flower := StringName(stem["flower"])
	if stage == STAGE_BLOOM:
		_settle_cup(t)  # before the cup rate changes
		_bloomed[flower] = bloomed_count(flower) + 1
		var f: Dictionary = content.flowers_by_id[flower]
		_snug += float(f["snug"])
		_cup_rate_h += float(f["dew_per_hour"])
	stem["stage"] = stage
	_emit(EV_STAGE, {"stem": i, "flower": flower, "stage": stage}, t)
	if stage == STAGE_BLOOM and not stem["tutorial"] and not state.first_bloom_postcard_sent:
		state.first_bloom_postcard_sent = true
		_send_event_postcard(&"first_bloom_by_purchase", t)
	if stage == STAGE_BLOOM:
		retention.check_mysteries(self, t)


func _candidate(t: float) -> void:
	if _u() * _lmax >= _lam():
		return  # thinning: exact for the piecewise-constant lambda(S)
	var ph := phase_at(t)
	var wx := weather_at(t)
	var elig: Array[StringName] = []
	for s: Dictionary in content.species:
		var id := StringName(s["id"])
		if _eligible(id, ph, t):
			elig.append(id)
	if elig.is_empty():
		return
	var debut: Array[StringName] = []
	for id: StringName in elig:
		if not is_met(id):
			debut.append(id)
	var pool := elig
	if not debut.is_empty() and _u() < float(_eco["debut_chance"]):
		pool = debut
	var weights := PackedFloat64Array()
	for id: StringName in pool:
		weights.append(_weight(id, ph, wx))
	var k := pool[_pick(weights)]
	var stay := _uniform(float(_eco["stay_min_s"]), float(_eco["stay_max_s"])) \
			* float(content.species_by_id[k]["stay_mult"])
	_arrive(t, k, stay, 0, false)


func _eligible(id: StringName, ph: StringName, t: float) -> bool:
	var i := _present_index(id)
	if i >= 0 and not state.present[i]["greeter"]:
		return false  # a greeter of this species may become the real visit (GDD §5.6)
	return _eligible_ignoring_presence(id, ph, t)


func _eligible_ignoring_presence(id: StringName, ph: StringName, t: float) -> bool:
	if not is_met(id) and t < retention.debut_ok_t(self, id):
		return false  # GDD §13.3.1: an unmet friend debuts only after its signs are out
	var s: Dictionary = content.species_by_id[id]
	var phases: Array = s["phases"]
	if not phases.is_empty() and not phases.has(String(ph)):
		return false
	var seasons: Array = s.get("seasons", [])
	if not seasons.is_empty() and not seasons.has(String(season_at(t))):
		return false
	for r: Dictionary in s["requires"]:
		if item_count(StringName(r["item"])) < int(r["min"]):
			return false
	return true


## w(k) = base * prod(satisfied likes) * (best friend mult) (GDD §5.5).
func _weight(id: StringName, ph: StringName, wx: StringName) -> float:
	var s: Dictionary = content.species_by_id[id]
	var w := float(s["base_weight"])
	for l: Dictionary in s["likes_items"]:
		if item_count(StringName(l["item"])) >= int(l["min"]):
			w *= float(l["mult"])
	for l: Dictionary in s["likes_weather"]:
		if StringName(l["weather"]) == wx:
			w *= float(l["mult"])
	for l: Dictionary in s["likes_phases"]:
		if StringName(l["phase"]) == ph:
			w *= float(l["mult"])
	if hearts_of(id) >= int(_eco["best_friend_heart"]):
		w *= float(_eco["best_friend_weight_mult"])
	return w


func _arrive(t: float, species: StringName, stay: float, scripted_gift: int, scripted: bool) -> void:
	var debut := not is_met(species)
	if debut:
		state.met[String(species)] = unix_at(t)
		_emit(EV_MET, {"species": species}, t)
		if met_count() == content.species.size():
			_send_event_postcard(&"all_species_met", t)
		retention.on_debut(self, species, t)
	if phase_at(t) == &"night":
		_send_event_postcard(&"first_night_visit", t)
	if weather_at(t) == WeatherPlan.RAIN:
		_send_event_postcard(&"first_rain_visit", t)
	if retention.visit_affection_due(self, species, t):  # the 20 h rest (GDD §13.2.1)
		_add_affection(species, int(_eco["affection_per_visit"]), t)
	var sdef: Dictionary = content.species_by_id[species]
	var gift := scripted_gift if scripted_gift > 0 else int(sdef["gift_dew"])
	var gift_item := retention.gift_item_for(self, species)
	var gi := _greeter_index()
	var from_greeter := gi >= 0 and StringName(state.present[gi]["species"]) == species
	if real_visitor_count() >= int(_eco["max_present"]):
		# A peek visit: waves from the rim, leaves the gift, no stay (GDD §4.1.3).
		_emit(EV_ARRIVED, {"species": species, "debut": debut, "peek": true, "scripted": scripted,
			"from_greeter": false, "depart_t": t}, t)
		_leave_gift(t, species, gift, gift_item)
		return
	var visit := {"species": String(species), "arrive_t": t, "depart_t": t + stay, "gift_dew": gift,
		"gift_item": gift_item, "boat_credit": false, "pet_credit": false, "scripted": scripted, "greeter": false,
		"cousin": ""}
	if from_greeter:
		state.present[gi] = visit
	else:
		state.present.append(visit)
	_emit(EV_ARRIVED, {"species": species, "debut": debut, "peek": false, "scripted": scripted,
		"from_greeter": from_greeter, "depart_t": t + stay}, t)
	retention.on_base_arrival(self, species, visit, t)
	# Room for real visitors always wins over the greeter.
	if state.present.size() > int(_eco["max_present"]):
		dismiss_greeter()
	_dirty = true


func _depart(i: int, t: float) -> void:
	var p: Dictionary = state.present[i]
	state.present.remove_at(i)
	var species := StringName(p["species"])
	if p["greeter"]:
		_emit(EV_GREETER_LEFT, {"species": species}, t)
		return
	_emit(EV_DEPARTED, {"species": species, "gift_dew": int(p["gift_dew"]), "cousin": String(p.get("cousin", ""))}, t)
	_leave_gift(t, species, int(p["gift_dew"]), String(p["gift_item"]))


func _leave_gift(t: float, species: StringName, dew: int, visit_item: String) -> void:
	var slots := int(_eco["basket_slots"])
	if state.basket.size() < slots:
		# From ♥2 the friend leaves its signature gift instead (same dew, GDD §13.2.2).
		var gift_item := retention.gift_item_for(self, species)
		if gift_item == "":
			gift_item = visit_item
		var signature := retention.is_signature_item(species, gift_item)
		var first_signature := signature and retention.note_signature_gift(self, species, t)
		state.basket.append({"species": String(species), "gift_item": gift_item, "dew": dew, "signature": signature})
		_emit(EV_GIFT, {"species": species, "gift_item": gift_item, "dew": dew, "slot": state.basket.size() - 1,
			"signature": signature, "first_signature": first_signature}, t)
		if _u() < float(_eco["photo_chance_with_gift"]):
			_take_photo(t, species)
		if state.basket.size() == slots and not state.basket_full_seen:
			state.basket_full_seen = true
			_emit(EV_BASKET_FULL, {}, t)
			_send_event_postcard(&"basket_full_first", t)
	else:
		_take_photo(t, species)  # a full basket turns gifts into photos: absence is never wasted


func _take_photo(t: float, species: StringName) -> void:
	var b: Dictionary = content.species_by_id[species]["behaviours"]
	var weights := PackedFloat64Array()
	for pose: StringName in GameContent.BEHAVIOURS:
		weights.append(float(b.get(String(pose), 0.0)))
	var p := _pick(weights)
	var bit := 1 << p
	var bits := int(state.photos.get(String(species), 0))
	var is_new := (bits & bit) == 0
	state.photos[String(species)] = bits | bit
	var pose_id := GameContent.BEHAVIOURS[p]
	state.photo_meta["%s/%s" % [species, pose_id]] = {"phase": String(phase_at(t)),
		"weather": String(weather_at(t)), "world_t": t}
	_emit(EV_PHOTO, {"species": species, "pose": pose_id, "new": is_new}, t)


func _add_affection(species: StringName, n: int, t: float) -> void:
	var before := hearts_of(species)
	state.affection[String(species)] = affection_of(species) + n
	var after := hearts_of(species)
	if after <= before:
		return
	# Unlocks per level (GDD §13.2.2): stories ♥2/4/5, nest ♥3, keepsake ♥5.
	for lvl in range(before + 1, after + 1):
		retention.on_heart_level(self, species, lvl, t)
	_emit(EV_HEARTS, {"species": species, "hearts": after, "from": before}, t)
	retention.after_hearts(self, after, t)


func _send_event_postcard(trigger: StringName, t: float) -> void:
	var p: Dictionary = content.event_postcards_by_trigger.get(trigger, {})
	if not p.is_empty():
		send_postcard(String(p["id"]), String(p["template"]), &"", t)


func _send_event_postcard_id(id: String, t: float) -> void:
	for trig: StringName in content.event_postcards_by_trigger:
		var p: Dictionary = content.event_postcards_by_trigger[trig]
		if p["id"] == id:
			send_postcard(id, String(p["template"]), &"", t)
			return


## Delivers postcard [param id] once (a repeat id is ignored). Used by RetentionRules too.
func send_postcard(id: String, template: String, species: StringName, t: float) -> void:
	if has_postcard(id):
		return
	state.postcards.append({"id": id, "template": template, "species": String(species),
		"received_unix": unix_at(t), "read": false})
	_emit(EV_POSTCARD, {"id": id, "template": template, "species": species}, t)


func _settle_cup(t: float) -> void:
	var sat_end := minf(t, state.last_collect_t + float(_eco["dew_cup_saturation_s"]))
	if sat_end > state.cup_last_t:
		state.cup += _cup_rate_h / TodMath.SECONDS_PER_HOUR * (sat_end - state.cup_last_t)
	state.cup_last_t = maxf(state.cup_last_t, t)


func _lam() -> float:
	return _lmin + (_lmax - _lmin) * _snug / (_snug + _lhalf)


func _rebuild_caches() -> void:
	_bloomed.clear()
	_snug = 0.0
	_cup_rate_h = float(_eco["dew_cup_base_per_h"])
	for s: Dictionary in state.stems:
		if int(s["stage"]) >= STAGE_BLOOM:
			var flower := StringName(s["flower"])
			if not content.flowers_by_id.has(flower):
				continue
			var f: Dictionary = content.flowers_by_id[flower]
			_bloomed[flower] = bloomed_count(flower) + 1
			_snug += float(f["snug"])
			_cup_rate_h += float(f["dew_per_hour"])
	for d: Dictionary in content.decor:
		_snug += float(d["snug"]) * owned_count(StringName(d["id"]))
	_dirty = true


func _present_index(species: StringName) -> int:
	for i in state.present.size():
		if StringName(state.present[i]["species"]) == species:
			return i
	return -1


func _greeter_index() -> int:
	for i in state.present.size():
		if state.present[i]["greeter"]:
			return i
	return -1


func has_postcard(id: String) -> bool:
	for p: Dictionary in state.postcards:
		if p["id"] == id:
			return true
	return false


## Appends an event to the outbox (RetentionRules emits through this).
func emit_event(type: StringName, data: Dictionary, t: float = NAN) -> void:
	_emit(type, data, t)


## Retention state changed outside the event loop (new signs, a tap): recompute the next event.
func mark_dirty() -> void:
	_dirty = true


func _emit(type: StringName, data: Dictionary, t: float = NAN) -> void:
	data["type"] = type
	data["t"] = state.t if is_nan(t) else t
	_events.append(data)


# ================================================================= rng (state persisted)

func _u() -> float:
	var v := _rng.randf()
	state.rng_state = _rng.state
	return minf(v, 0.9999999999)


func _uniform(a: float, b: float) -> float:
	return a + (b - a) * _u()


func _expo(rate: float) -> float:
	return -log(1.0 - _u()) / rate


func _pick(weights: PackedFloat64Array) -> int:
	var tot := 0.0
	for w: float in weights:
		tot += w
	var x := _u() * tot
	var acc := 0.0
	for i in weights.size():
		acc += weights[i]
		if x < acc:
			return i
	return weights.size() - 1
