class_name TeaRules
extends RefCounted
## Active F2 Tea & Treats rules (GDD §14, docs/gdd/ACTIVE_TEA.md; data/tea.json).
##
## A port of the tea half of tools/sim/economy_sim.py `Player` (petals_ready, harvest, brew,
## reaction, offer, tea_satisfies) plus the game-only pieces the reference folds into one step
## (the pot, the tray, teaware, the recipe book). Pure and fully deterministic (tea has no
## randomness at all, AP7). [WorldSim] owns one instance through [ActiveRules]; the world it acts on
## is passed in as [param sim], so this object holds no reference back to it.
##
## Cozy guarantees (ACTIVE_TEA §1): harvesting never harms a flower (its stage, dew and attraction
## are untouched; only the petal anchor moves); nothing decays (petals, cups and treats never
## spoil); nothing is discarded (a full jar stops gathering and the petals wait on the stems;
## petals and drops taken out of the pot go back, drops refunded); every pot makes something.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const REACT_CONTENT := &"content"
const REACT_LIKED := &"liked"
const REACT_LOVED := &"loved"
const KIND_TEA := &"tea"
const KIND_TREAT := &"treat"
const SLOTS: Array[String] = ["teapot", "cup", "cloth"]
const TRIGGER_FIRST_CUP := &"first_cup_offered"
const TRIGGER_BOOK := &"all_named_recipes_found"

var content: GameContent
var _hold: int
var _drop_cost: int
var _max_petals: int
var _max_drops: int
var _min_petals: int
var _stir_target: float
var _stir_step: float
var _tray_slots: int
var _rest_s: float
var _likes_at: int


func _init(p_content: GameContent) -> void:
	content = p_content
	var te := content.tea
	_hold = int(te["harvest"]["petal_hold_per_stem"])
	_drop_cost = int(te["dew_drop"]["cost_dew"])
	_max_petals = int(te["pot"]["max_petals"])
	_min_petals = int(te["pot"]["min_petals"])
	_max_drops = int(te["pot"]["max_drops"])
	_stir_target = float(te["brewing"]["stir_target_deg"])
	_stir_step = float(te["brewing"]["stir_tap_alt_deg_per_tap"])
	_tray_slots = int(te["tray"]["slots"])
	_rest_s = float(te["offering"]["affection_rest_s"])
	_likes_at = int(te["likes_revealed_at_heart"])


# ================================================================= unlock (ACTIVE_TEA §2.3)

## The nook wakes once onboarding is done (the welcome postcard time) and a stem has bloomed.
## Returns true when it unlocked now.
func check_unlock(sim: WorldSim, t: float) -> bool:
	var st := sim.state
	if st.tea_unlocked or not sim.active.feature_on(ActiveRules.FEATURE_TEA):
		return false
	var un: Dictionary = content.tea["unlock"]
	var onboarding_done_t := float(content.economy["onboarding"]["welcome_postcard_at_s"])
	if bool(un.get("requires_onboarding_done", true)) and t < onboarding_done_t:
		return false
	if _bloomed_stems(sim) < int(un["requires_bloomed_stems"]):
		return false
	st.tea_unlocked = true
	sim.emit_event(WorldSim.EV_TEA_UNLOCKED, {}, t)
	return true


func _bloomed_stems(sim: WorldSim) -> int:
	var n := 0
	for s: Dictionary in sim.state.stems:
		if int(s["stage"]) >= WorldSim.STAGE_BLOOM:
			n += 1
	return n


# ================================================================= petals (ACTIVE_TEA §2.1)

static func stem_key(stem: Dictionary) -> String:
	return "%s:%d" % [stem["bed"], int(stem["slot"])]


func regrow_s(flower: StringName) -> float:
	var row: Dictionary = content.petals_by_flower.get(flower, {})
	return float(row.get("petal_regrow_s", INF))


func jar_cap(flower: StringName) -> int:
	var row: Dictionary = content.petals_by_flower.get(flower, {})
	return int(row.get("pantry_cap", 0))


func pantry_of(sim: WorldSim, flower: StringName) -> int:
	return int(sim.state.pantry.get(String(flower), 0))


func room(sim: WorldSim, flower: StringName) -> int:
	return maxi(0, jar_cap(flower) - pantry_of(sim, flower))


## The petal anchor of stem [param i]: petal_from_t, else its bloom time.
func anchor(sim: WorldSim, i: int) -> float:
	var stem: Dictionary = sim.state.stems[i]
	return float(sim.state.petal_from_t.get(stem_key(stem), sim.stem_bloom_t(i)))


## ready(t) = min(hold, floor((t - pa) / regrow)) for a bloomed stem, else 0.
func stem_ready(sim: WorldSim, i: int, t: float) -> int:
	var stem: Dictionary = sim.state.stems[i]
	if int(stem["stage"]) < WorldSim.STAGE_BLOOM:
		return 0
	var reg := regrow_s(StringName(stem["flower"]))
	if reg == INF or reg <= 0.0:
		return 0
	return clampi(floori((t - anchor(sim, i)) / reg), 0, _hold)


## Petals a tap on [param bed_id] would gather now (&"" = every bed), limited by each jar's room.
func petals_ready(sim: WorldSim, bed_id: StringName, t: float) -> int:
	var per := {}
	for i in sim.state.stems.size():
		var stem: Dictionary = sim.state.stems[i]
		if bed_id != &"" and StringName(stem["bed"]) != bed_id:
			continue
		var r := stem_ready(sim, i, t)
		if r > 0:
			per[String(stem["flower"])] = int(per.get(String(stem["flower"]), 0)) + r
	var n := 0
	for f: String in per:
		n += mini(int(per[f]), room(sim, StringName(f)))
	return n


## Ready petals per flower on [param bed_id] (&"" = all), before jar limits (bed card, glints).
func ready_by_flower(sim: WorldSim, bed_id: StringName, t: float) -> Dictionary:
	var per := {}
	for i in sim.state.stems.size():
		var stem: Dictionary = sim.state.stems[i]
		if bed_id == &"" or StringName(stem["bed"]) == bed_id:
			var r := stem_ready(sim, i, t)
			if r > 0:
				per[StringName(stem["flower"])] = int(per.get(StringName(stem["flower"]), 0)) + r
	return per


## Seconds until the next petal grows on [param bed_id] (INF if none can: no bloom, or full).
func next_petal_in_s(sim: WorldSim, bed_id: StringName, t: float) -> float:
	var best := INF
	for i in sim.state.stems.size():
		var stem: Dictionary = sim.state.stems[i]
		if StringName(stem["bed"]) != bed_id or int(stem["stage"]) < WorldSim.STAGE_BLOOM:
			continue
		var reg := regrow_s(StringName(stem["flower"]))
		if stem_ready(sim, i, t) >= _hold or reg == INF:
			continue
		var into := fposmod(t - anchor(sim, i), reg)
		best = minf(best, reg - into)
	return best


## Gathers every ready petal of [param bed_id] (&"" = all beds) that fits, in stem order (a tap on
## a bed, ACTIVE_TEA §2.1). The rest waits on the stems. Returns flower -> petals gathered.
func harvest_bed(sim: WorldSim, bed_id: StringName, t: float) -> Dictionary:
	var st := sim.state
	var got := {}
	for i in st.stems.size():
		var stem: Dictionary = st.stems[i]
		if bed_id != &"" and StringName(stem["bed"]) != bed_id:
			continue
		var flower := StringName(stem["flower"])
		var free := room(sim, flower)
		if free <= 0:
			continue
		var ready := stem_ready(sim, i, t)
		if ready <= 0:
			continue
		var k := mini(ready, free)
		var reg := regrow_s(flower)
		var pa := anchor(sim, i)
		# A partly grown stem keeps its progress; a full stem's clock had paused (like the cup).
		st.petal_from_t[stem_key(stem)] = pa + k * reg if ready < _hold else t - (ready - k) * reg
		st.pantry[String(flower)] = pantry_of(sim, flower) + k
		got[flower] = int(got.get(flower, 0)) + k
	if not got.is_empty():
		sim.emit_event(WorldSim.EV_PETALS, {"bed": bed_id, "counts": got.duplicate()}, t)
	return got


## Adds up to [param n] petals of [param flower] to its jar (never past the cap). Returns added.
func add_petals(sim: WorldSim, flower: StringName, n: int) -> int:
	var k := mini(maxi(0, n), room(sim, flower))
	if k > 0:
		sim.state.pantry[String(flower)] = pantry_of(sim, flower) + k
	return k


## The shared gift-petal rule (GDD §14.2.4): the friend's gift_petal if it has a bloomed stem,
## else the flower with the most bloomed stems (ties: garden order).
func gift_flower(sim: WorldSim, species: StringName) -> StringName:
	var pr: Dictionary = content.tea_prefs.get(species, {})
	var own := StringName(pr.get("gift_petal", ""))
	if own != &"" and sim.bloomed_count(own) > 0:
		return own
	var best := &""
	var best_n := -1
	for f: Dictionary in content.flowers:
		var id := StringName(f["id"])
		if sim.bloomed_count(id) > best_n:
			best_n = sim.bloomed_count(id)
			best = id
	return best


# ================================================================= the pot (ACTIVE_TEA §3-§4)

func pot_add_petal(sim: WorldSim, flower: StringName) -> bool:
	var pot := sim.state.pot
	var petals: Array = pot["petals"]
	if not content.petals_by_flower.has(flower) or petals.size() >= _max_petals or pantry_of(sim, flower) <= 0:
		return false
	sim.state.pantry[String(flower)] = pantry_of(sim, flower) - 1
	petals.append(String(flower))
	return true


## Takes petal [param index] back out of the pot into its jar (it came from there).
func pot_remove(sim: WorldSim, index: int) -> bool:
	var petals: Array = sim.state.pot["petals"]
	if index < 0 or index >= petals.size():
		return false
	var f := String(petals[index])
	petals.remove_at(index)
	sim.state.pantry[f] = int(sim.state.pantry.get(f, 0)) + 1
	if petals.is_empty():
		sim.state.pot["stir_deg"] = 0.0
	return true


## A dew drop into the pot: charged now (cost_dew), refunded by [method pot_remove_drop].
func pot_add_drop(sim: WorldSim) -> bool:
	var pot := sim.state.pot
	if int(pot["drops"]) >= _max_drops or sim.state.dew < _drop_cost:
		return false
	sim.state.dew -= _drop_cost
	pot["drops"] = int(pot["drops"]) + 1
	return true


func pot_remove_drop(sim: WorldSim) -> bool:
	var pot := sim.state.pot
	if int(pot["drops"]) <= 0:
		return false
	pot["drops"] = int(pot["drops"]) - 1
	sim.state.dew += _drop_cost
	return true


## Stir progress: |deg| (either direction, any speed) up to stir_target_deg; one call adds at most
## one tap-alternative step. Needs a petal in the pot. Returns the progress.
func pot_stir(sim: WorldSim, deg: float) -> float:
	var pot := sim.state.pot
	if (pot["petals"] as Array).is_empty():
		return 0.0
	pot["stir_deg"] = minf(_stir_target, float(pot["stir_deg"]) + minf(absf(deg), _stir_step))
	return float(pot["stir_deg"])


func stir_target() -> float:
	return _stir_target


## What the pot would make now (&"" = not brewable yet: no petal).
func pot_recipe(sim: WorldSim) -> StringName:
	var pot := sim.state.pot
	return content.match_recipe(pot["petals"], int(pot["drops"]))


## Pours (or, [param simple], brews in one tap without the stir) into the next free tray slot.
## Returns the recipe made, or &"" (no petal, the stir not done, or the tray full: the pot keeps
## everything). First brews of a recipe enter the book (EV_RECIPE_FOUND).
func pour(sim: WorldSim, simple: bool, t: float) -> StringName:
	var st := sim.state
	var pot := st.pot
	var recipe := pot_recipe(sim)
	if recipe == &"" or st.tray.size() >= _tray_slots:
		return &""
	if not simple and float(pot["stir_deg"]) < _stir_target:
		return &""
	var petals: Array = (pot["petals"] as Array).duplicate()
	st.tray.append({"recipe": String(recipe), "made_unix": sim.unix_at(t), "drops": int(pot["drops"]),
		"petals": petals})
	st.pot = {"petals": [], "drops": 0, "stir_deg": 0.0}
	var first := not st.recipes_found.has(String(recipe))
	sim.emit_event(WorldSim.EV_BREWED, {"recipe": recipe, "kind": recipe_kind(recipe), "new": first,
		"tray_index": st.tray.size() - 1}, t)
	if first:
		st.recipes_found[String(recipe)] = sim.unix_at(t)
		sim.emit_event(WorldSim.EV_RECIPE_FOUND, {"recipe": recipe, "found": st.recipes_found.size(),
			"total": content.recipes.size()}, t)
		if named_found(sim) >= content.named_recipe_count:
			sim.send_trigger_postcard(TRIGGER_BOOK, t)
	return recipe


func named_found(sim: WorldSim) -> int:
	var n := 0
	for r: String in sim.state.recipes_found:
		if content.is_named_recipe(StringName(r)):
			n += 1
	return n


func recipe_kind(recipe: StringName) -> StringName:
	var r: Dictionary = content.recipes_by_id.get(recipe, {})
	return StringName(r.get("kind", "tea"))


# ================================================================= offering (ACTIVE_TEA §6-§7)

func reaction(species: StringName, recipe: StringName) -> StringName:
	var pr: Dictionary = content.tea_prefs.get(species, {})
	if Array(pr.get("loves", [])).has(String(recipe)):
		return REACT_LOVED
	if Array(pr.get("likes", [])).has(String(recipe)):
		return REACT_LIKED
	return REACT_CONTENT


## Whether a cup of [param recipe] with [param petals] offered to [param species] grants
## [param wish] (a tea target; buddy wishes need the best buddy present). Pure.
func satisfies(sim: WorldSim, wish: StringName, species: StringName, recipe: StringName, petals: Array) -> bool:
	var tg: Dictionary = content.wish_targets.get(wish, {})
	if tg.is_empty():
		return false
	var kind := StringName(tg["kind"])
	var arg := String(tg["arg"])
	if kind == &"tea":
		return String(recipe) == arg
	var req: Dictionary = (content.wishes_by_id[wish] as Dictionary)["requires"]
	if bool(req.get("buddy_present", false)) and not sim.is_present(sim.retention.best_friend(species)):
		return false
	match kind:
		&"tea_kind":
			return String(recipe_kind(recipe)) == arg
		&"tea_petal":
			return petals.has(arg)
		&"tea_loved":
			return reaction(species, recipe) == REACT_LOVED
	return false


## Offers tray cup [param tray_index] to a present friend: it sips and reacts (never dislikes).
## Affection at most once per friend per affection_rest_s (tea_aff_t; the greeter 0); liked and
## loved cups tuck petals of the friend's gift flower back into the pantry (not the greeter);
## then a matching open tea wish is granted. Returns {} if nothing happened, else
## {species, recipe, reaction, affection, petals_back, flower, wish_granted}.
func offer(sim: WorldSim, tray_index: int, species: StringName, t: float) -> Dictionary:
	var st := sim.state
	var pi := sim.present_index(species)
	if pi < 0 or tray_index < 0 or tray_index >= st.tray.size():
		return {}
	var greeter := bool(st.present[pi]["greeter"])
	var cup: Dictionary = st.tray[tray_index]
	st.tray.remove_at(tray_index)
	var recipe := StringName(cup["recipe"])
	var petals: Array = cup.get("petals", [])
	var react := reaction(species, recipe)
	var seen: Array = st.tea_prefs_seen.get(String(species), [])
	if not seen.has(String(recipe)):
		seen.append(String(recipe))
	st.tea_prefs_seen[String(species)] = seen
	st.cups_offered += 1
	var of: Dictionary = content.tea["offering"]
	var aff := 0
	var back := 0
	var flower := &""
	if not greeter:
		var last := float(st.tea_aff_t.get(String(species), -INF))
		if t - last >= _rest_s:
			st.tea_aff_t[String(species)] = t
			aff = int(of["affection_%s" % react])
			sim.add_affection(species, aff, t)
		var want := 0
		if react == REACT_LIKED:
			want = int(of["petals_back_liked"])
		elif react == REACT_LOVED:
			want = int(of["petals_back_loved"])
		if want > 0:
			flower = gift_flower(sim, species)
			back = add_petals(sim, flower, want)
	var granted := sim.active.wishes.on_offer(sim, species, recipe, petals, t)
	sim.emit_event(WorldSim.EV_TEA_OFFERED, {"species": species, "recipe": recipe, "reaction": react,
		"affection": aff, "petals_back": back, "flower": flower, "wish_granted": granted, "greeter": greeter}, t)
	if st.cups_offered == 1:
		sim.send_trigger_postcard(TRIGGER_FIRST_CUP, t)
	return {"species": species, "recipe": recipe, "reaction": react, "affection": aff, "petals_back": back,
		"flower": flower, "wish_granted": granted}


## Recipes whose reaction [param species] is known: seen reactions, or every love and like from
## likes_revealed_at_heart. {loves: Array[String], likes: Array[String], seen: Array[String]}.
func known_prefs(sim: WorldSim, species: StringName) -> Dictionary:
	var pr: Dictionary = content.tea_prefs.get(species, {})
	var seen: Array = sim.state.tea_prefs_seen.get(String(species), [])
	var all := sim.hearts_of(species) >= _likes_at
	var loves: Array[String] = []
	var likes: Array[String] = []
	for r: Variant in pr.get("loves", []):
		if all or seen.has(String(r)):
			loves.append(String(r))
	for r: Variant in pr.get("likes", []):
		if all or seen.has(String(r)):
			likes.append(String(r))
	return {"loves": loves, "likes": likes, "seen": seen.duplicate()}


# ================================================================= teaware (ACTIVE_TEA §9)

func teaware_price(id: StringName) -> int:
	var x: Dictionary = content.teaware_by_id.get(id, {})
	return int(x.get("cost", 0))


func owns_teaware(sim: WorldSim, id: StringName) -> bool:
	var x: Dictionary = content.teaware_by_id.get(id, {})
	return not x.is_empty() and (bool(x.get("default", false)) or sim.state.teaware_owned.has(String(id)))


## Buys a cosmetic piece (a dew sink, snug 0). False if unknown, owned or not affordable.
func buy_teaware(sim: WorldSim, id: StringName) -> bool:
	var x: Dictionary = content.teaware_by_id.get(id, {})
	if x.is_empty() or owns_teaware(sim, id) or int(x["cost"]) > sim.state.dew:
		return false
	sim.state.dew -= int(x["cost"])
	sim.state.teaware_owned.append(String(id))
	sim.emit_event(WorldSim.EV_TEAWARE, {"slot": StringName(x["slot"]), "id": id, "bought": true, "cost": int(x["cost"])})
	return true


func use_teaware(sim: WorldSim, id: StringName) -> bool:
	if not owns_teaware(sim, id):
		return false
	var slot := String((content.teaware_by_id[id] as Dictionary)["slot"])
	sim.state.teaware_set[slot] = String(id)
	sim.emit_event(WorldSim.EV_TEAWARE, {"slot": StringName(slot), "id": id, "bought": false, "cost": 0})
	return true


## slot -> teaware id in use (defaults filled in).
func teaware_in_use(sim: WorldSim) -> Dictionary:
	var out := {}
	for slot: String in SLOTS:
		out[slot] = String(sim.state.teaware_set.get(slot, content.teaware_default.get(slot, "")))
	return out


## Prices of the teaware still for sale (E6 audit).
func teaware_for_sale(sim: WorldSim) -> PackedInt32Array:
	var out := PackedInt32Array()
	for x: Dictionary in GameContent._records(content.tea["teaware"]):
		if not owns_teaware(sim, StringName(x["id"])):
			out.append(int(x["cost"]))
	return out
