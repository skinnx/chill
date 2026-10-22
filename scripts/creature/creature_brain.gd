class_name CreatureBrain
extends RefCounted
## The creature brain (docs/ARCHITECTURE.md §5.4, GDD §4.1.3): turns the sim's visitors into
## behaviour bouts at spots. Pure and view-side: it never changes WorldState; it reads content,
## the world queries it is given and the visits it is told about.
##
## Rules (GDD §4.1.3):
##  * bouts last bout_s (120-360 s, clipped to the departure), drawn from the species' behaviour
##    weights; night x3 nap; in rain, rain-likers x1.5 play and everyone else picks a shelter
##    spot when one allows the behaviour, else holds a leaf umbrella;
##  * the first bout and every nap go to the favourite spot (favourite_p = 60 %) when it is free
##    and allows the behaviour, otherwise a random free spot that allows it;
##  * spot capacity is respected (capacity-2 spots have two slots), nibble uses bed nibble points
##    (beds with stems; liked or required flowers preferred) or the Clover Bank, wander anchors at
##    a wander spot or the open tend zone;
##  * a new bout never repeats the previous (behaviour, spot) pair;
##  * deterministic: each visit draws from its own RNG seeded hash([install_seed, species,
##    arrive_t]), and all visitors are planned together in time order, so the same visits always
##    produce the same bouts (also after a reload).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const NAP := &"nap"
const NIBBLE := &"nibble"
const PLAY := &"play"
const WANDER := &"wander"
const STREAM := &"sit_by_stream"
const BEHAVIOURS: Array[StringName] = [NAP, NIBBLE, PLAY, WANDER, STREAM]
const NIGHT := &"night"
const RAIN := &"rain"
## Spot id used for a wander bout anchored in the open tend zone (no spot capacity).
const OPEN_FIELD := &"open_field"
const CLOVER_BANK := &"clover_bank"
## Nibble at a bed: spot id is "<bed_id>#<nibble point index>".
const NIBBLE_SEP := "#"
const MAX_DRAWS := 8
## Liked / required flowers make a bed this much more likely for nibbling.
const LIKED_BED_MULT := 3.0
const MAX_BOUTS_PER_ADVANCE := 4096


## One planned bout.
class Bout:
	var behaviour: StringName = &""
	var spot: StringName = &""
	var slot: int = 0
	var pos: Vector2 = Vector2.ZERO
	var start_t: float = 0.0
	var end_t: float = 0.0
	var shelter: bool = false
	var umbrella: bool = false
	## Species this one plays with (capacity-2 play spots), or &"".
	var partner: StringName = &""

	func key() -> String:
		return "%s@%s" % [behaviour, spot]

	func covers(t: float) -> bool:
		return t >= start_t and t < end_t


## One visit being planned.
class Visit:
	var species: StringName = &""
	var arrive_t: float = 0.0
	var depart_t: float = 0.0
	var greeter: bool = false
	var rng := RandomNumberGenerator.new()
	var bouts: Array[Bout] = []
	var planned_to: float = 0.0

	func last() -> Bout:
		return bouts.back() if not bouts.is_empty() else null


var content: GameContent
var install_seed: int = 0
## Callable(t: float) -> Dictionary {phase: StringName, weather: StringName}.
var env: Callable = Callable()
## Callable(item_id: StringName) -> int: décor copies owned (spot unlocks).
var owned: Callable = Callable()
## Callable(bed_id: StringName) -> Array of flower ids with a stem in that bed.
var bed_flowers: Callable = Callable()

var _visits: Array[Visit] = []
var _b: Dictionary = {}
var _slots: Dictionary = {}
var _frame: Vector2 = Vector2(1080, 1920)


func _init(p_content: GameContent, p_install_seed: int) -> void:
	content = p_content
	install_seed = p_install_seed
	var view: Dictionary = content.creature_rig.get("view", {})
	_b = view.get("behaviour", {})
	_slots = view.get("spot_slots_px", {})
	var frame: Dictionary = content.spots_doc.get("frame", {})
	_frame = Vector2(float(frame.get("width_px", 1080)), float(frame.get("height_px", 1920)))


## Seed of one visit (ARCHITECTURE §5.4: hash([install_seed, species, arrive_t])).
static func visit_seed(p_install_seed: int, species: StringName, arrive_t: float) -> int:
	return hash([p_install_seed, String(species), arrive_t])


func add_visit(species: StringName, arrive_t: float, depart_t: float, greeter: bool = false) -> Visit:
	remove_visit(species)
	var v := Visit.new()
	v.species = species
	v.arrive_t = arrive_t
	v.depart_t = maxf(depart_t, arrive_t)
	v.greeter = greeter
	v.rng.seed = visit_seed(install_seed, species, arrive_t)
	v.planned_to = arrive_t
	_visits.append(v)
	return v


func remove_visit(species: StringName) -> void:
	for i in range(_visits.size() - 1, -1, -1):
		if _visits[i].species == species:
			_visits.remove_at(i)


func has_visit(species: StringName) -> bool:
	return _visit(species) != null


func visit(species: StringName) -> Visit:
	return _visit(species)


func visits() -> Array[Visit]:
	return _visits


## Plans every visit up to [param t] (world seconds), all visitors together in time order.
func advance(t: float) -> void:
	for guard in MAX_BOUTS_PER_ADVANCE:
		var next: Visit = null
		for v: Visit in _visits:
			if v.planned_to > t or v.planned_to >= v.depart_t:
				continue
			if next == null or v.planned_to < next.planned_to \
					or (v.planned_to == next.planned_to and String(v.species) < String(next.species)):
				next = v
		if next == null:
			return
		var bout := _plan_bout(next, next.planned_to)
		next.bouts.append(bout)
		next.planned_to = bout.end_t


## The bout [param species] is in at [param t] (null when not planned or outside the visit).
func current(species: StringName, t: float) -> Bout:
	var v := _visit(species)
	if v == null:
		return null
	for i in range(v.bouts.size() - 1, -1, -1):
		var b := v.bouts[i]
		if b.covers(t):
			return b
		if b.end_t <= t:
			break
	return null


## Forces the bout of a visit from [param t] (QA fixtures and the boat-watching override).
func force_bout(species: StringName, behaviour: StringName, spot: StringName, t: float, seconds: float) -> Bout:
	var v := _visit(species)
	if v == null:
		return null
	while not v.bouts.is_empty() and v.bouts.back().start_t >= t:
		v.bouts.pop_back()
	if not v.bouts.is_empty() and v.bouts.back().end_t > t:
		v.bouts.back().end_t = t
	var b := Bout.new()
	b.behaviour = behaviour
	b.spot = spot
	b.start_t = t
	b.end_t = minf(t + seconds, v.depart_t) if v.depart_t > t else t + seconds
	b.slot = _free_slot(spot, t, v)
	b.pos = spot_position(spot, b.slot, v)
	b.shelter = is_shelter(spot)
	var rain := StringName(_env(t).get("weather", &"")) == RAIN
	var sp: Dictionary = content.species_by_id.get(species, {})
	b.umbrella = rain and not _likes_weather(sp, RAIN) and not b.shelter
	v.bouts.append(b)
	v.planned_to = b.end_t
	return b


## Longest nap that overlaps (t0, t1]: {species, spot, seconds} or {} (the recap's "napped at").
## The longest nap of an absence, for the welcome-back recap (GDD §7.5 "{name} napped at the
## {spot}", ARCHITECTURE §12 open issue (a): the line was written in the MVP and has waited for
## this class ever since).
##
## Nothing about a past visit is stored anywhere. The brain is deterministic - each visit draws
## from its own RNG seeded by (install_seed, species, arrive_t) - so the bouts of the visits that
## happened while the app was closed are simply REPLANNED here from the catch-up events, which
## already carry each arrival's depart_t. [param events] is that catch-up list; the window is
## [param from_t] .. [param to_t] in world seconds. Returns {} or {species, spot, seconds}.
static func nap_during(content: GameContent, sim: WorldSim, events: Array[Dictionary], from_t: float,
		to_t: float) -> Dictionary:
	if sim == null or content == null or to_t <= from_t:
		return {}
	var brain := CreatureBrain.new(content, sim.state.install_seed)
	brain.env = func(t: float) -> Dictionary:
		return {"phase": sim.phase_at(t), "weather": sim.weather_at(t)}
	brain.owned = func(item: StringName) -> int:
		return sim.owned_count(item)
	brain.bed_flowers = func(bed_id: StringName) -> Array:
		var out: Array = []
		for st: Dictionary in sim.state.stems:
			if StringName(st["bed"]) == bed_id:
				out.append(StringName(st["flower"]))
		return out
	for ev: Dictionary in events:
		if StringName(ev.get("type", &"")) != WorldSim.EV_ARRIVED or bool(ev.get("peek", false)):
			continue
		var sp := StringName(ev["species"])
		var arrive := float(ev.get("t", from_t))
		var depart := float(ev.get("depart_t", arrive))
		if depart <= from_t or arrive >= to_t or brain.has_visit(sp):
			continue
		brain.add_visit(sp, arrive, depart, bool(ev.get("from_greeter", false)))
	brain.advance(to_t)
	return brain.longest_nap(from_t, to_t)


func longest_nap(t0: float, t1: float) -> Dictionary:
	var best := {}
	var best_s := 0.0
	for v: Visit in _visits:
		for b: Bout in v.bouts:
			if b.behaviour != NAP:
				continue
			var s := minf(b.end_t, t1) - maxf(b.start_t, t0)
			if s > best_s:
				best_s = s
				best = {"species": v.species, "spot": b.spot, "seconds": s}
	return best


# ================================================================= planning

func _plan_bout(v: Visit, t: float) -> Bout:
	var e := _env(t)
	var rain := StringName(e.get("weather", &"")) == RAIN
	var night := StringName(e.get("phase", &"")) == NIGHT
	var sp: Dictionary = content.species_by_id.get(v.species, {})
	var likes_rain := _likes_weather(sp, RAIN)
	var weights := {}
	var base: Dictionary = sp.get("behaviours", {})
	for beh: StringName in BEHAVIOURS:
		var w := float(base.get(String(beh), 0.0))
		if beh == NAP and night:
			w *= float(_b.get("night_nap_mult", 3.0))
		if beh == PLAY and rain and likes_rain:
			w *= float(_b.get("rain_play_mult", 1.5))
		weights[beh] = w
	var first := v.bouts.is_empty()
	var prev := v.last()
	var prev_key := prev.key() if prev != null else ""
	var bout: Bout = null
	for attempt in MAX_DRAWS:
		var beh := _draw(v.rng, weights)
		if beh == &"":
			break
		var cand := _candidates(beh, t, v, rain and not likes_rain)
		# never repeat the previous (behaviour, spot) pair
		cand = cand.filter(func(c: Dictionary) -> bool: return "%s@%s" % [beh, c["spot"]] != prev_key)
		if cand.is_empty():
			weights[beh] = 0.0
			continue
		var pick := _pick_spot(v, cand, first or beh == NAP)
		bout = Bout.new()
		bout.behaviour = beh
		bout.spot = StringName(pick["spot"])
		bout.slot = int(pick.get("slot", 0))
		bout.partner = StringName(pick.get("partner", &""))
		break
	if bout == null:
		# nothing fits (every spot taken): stroll in the open tend zone
		bout = Bout.new()
		bout.behaviour = WANDER
		bout.spot = OPEN_FIELD
	var dur: Array = _b.get("bout_s", [120, 360])
	bout.start_t = t
	bout.end_t = minf(t + v.rng.randf_range(float(dur[0]), float(dur[1])), v.depart_t)
	if bout.end_t <= t:
		bout.end_t = v.depart_t
	bout.pos = spot_position(bout.spot, bout.slot, v)
	bout.shelter = is_shelter(bout.spot)
	bout.umbrella = rain and not likes_rain and not bout.shelter
	return bout


## Spots (or nibble points) that allow [param beh] and have room at [param t].
func _candidates(beh: StringName, t: float, v: Visit, want_shelter: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if beh == NIBBLE:
		for bed: Dictionary in content.beds:
			var bed_id := StringName(bed["id"])
			var flowers: Array = bed_flowers.call(bed_id) if bed_flowers.is_valid() else []
			if flowers.is_empty():
				continue
			var mult := LIKED_BED_MULT if _likes_any(v.species, flowers) else 1.0
			var pts: Array = bed.get("nibble_points", [])
			for i in pts.size():
				var id := StringName("%s%s%d" % [bed_id, NIBBLE_SEP, i])
				if _occupants(id, 0, t, v) == 0:
					out.append({"spot": id, "slot": 0, "w": mult})
	for s: Dictionary in content.spots:
		var id := StringName(s["id"])
		var allows: Array = s.get("behaviours", [])
		if not allows.has(String(beh)) or not _spot_exists(s):
			continue
		var cap := int(s.get("capacity", 1))
		for slot in cap:
			if _occupants(id, slot, t, v) == 0:
				var c := {"spot": id, "slot": slot, "w": 1.0}
				if beh == PLAY and cap > 1:
					var mate := _occupant_species(id, (slot + 1) % cap, t, v)
					if mate != &"":
						c["partner"] = mate
						c["w"] = 2.0       # play together (GDD §4.1.3)
				out.append(c)
				break
	if want_shelter:
		var sheltered := out.filter(func(c: Dictionary) -> bool: return is_shelter(StringName(c["spot"])))
		if not sheltered.is_empty():
			return sheltered
	if beh == WANDER and out.is_empty():
		out.append({"spot": OPEN_FIELD, "slot": 0, "w": 1.0})
	return out


func _pick_spot(v: Visit, cand: Array[Dictionary], favour: bool) -> Dictionary:
	var fav := StringName((content.species_by_id.get(v.species, {}) as Dictionary).get("favourite_spot", ""))
	var p_fav := float(_b.get("favourite_p", 0.6))
	if favour:
		var roll := v.rng.randf()
		for c: Dictionary in cand:
			if StringName(c["spot"]) == fav and roll < p_fav:
				return c
	var total := 0.0
	for c: Dictionary in cand:
		total += float(c["w"])
	var r := v.rng.randf() * total
	for c: Dictionary in cand:
		r -= float(c["w"])
		if r <= 0.0:
			return c
	return cand.back()


static func _draw(rng: RandomNumberGenerator, weights: Dictionary) -> StringName:
	var total := 0.0
	for k: StringName in BEHAVIOURS:
		total += maxf(float(weights.get(k, 0.0)), 0.0)
	if total <= 0.0:
		return &""
	var r := rng.randf() * total
	for k: StringName in BEHAVIOURS:
		r -= maxf(float(weights.get(k, 0.0)), 0.0)
		if r <= 0.0 and float(weights.get(k, 0.0)) > 0.0:
			return k
	for k: StringName in BEHAVIOURS:
		if float(weights.get(k, 0.0)) > 0.0:
			return k
	return &""


# ================================================================= spots

## Feet position (design px) of a spot / slot. Nibble points come from the bed; the open field
## picks a seeded point in the tend zone.
func spot_position(spot: StringName, slot: int, v: Visit = null) -> Vector2:
	var s := String(spot)
	if s.contains(NIBBLE_SEP):
		var bed: Dictionary = content.beds_by_id.get(StringName(s.get_slice(NIBBLE_SEP, 0)), {})
		var pts: Array = bed.get("nibble_points", [])
		var i := s.get_slice(NIBBLE_SEP, 1).to_int()
		if i < pts.size():
			var pt: Array = pts[i]
			return Vector2(float(pt[0]) * _frame.x, float(pt[1]) * _frame.y)
		return Vector2.ZERO
	if spot == OPEN_FIELD:
		var zone: Dictionary = _b.get("tend_zone_px", {})
		var zx: Array = zone.get("x", [110, 970])
		var zy: Array = zone.get("y", [880, 1420])
		var rng := v.rng if v != null else RandomNumberGenerator.new()
		return Vector2(rng.randf_range(float(zx[0]), float(zx[1])), rng.randf_range(float(zy[0]), float(zy[1])))
	var sp: Dictionary = content.spots_by_id.get(spot, {})
	var p := Vector2(float(sp.get("x", 0.5)) * _frame.x, float(sp.get("y", 0.5)) * _frame.y)
	var offs: Array = _slots.get(s, [])
	if slot < offs.size():
		var o: Array = offs[slot]
		p += Vector2(float(o[0]), float(o[1]))
	return p


func is_shelter(spot: StringName) -> bool:
	var sp: Dictionary = content.spots_by_id.get(spot, {})
	return bool(sp.get("shelter", false))


## Spot id of a nibble point's bed (or &"" for a spot).
static func nibble_bed(spot: StringName) -> StringName:
	var s := String(spot)
	return StringName(s.get_slice(NIBBLE_SEP, 0)) if s.contains(NIBBLE_SEP) else &""


func _spot_exists(s: Dictionary) -> bool:
	var item := String(s.get("requires_item", ""))
	if item == "":
		return true
	var n: int = owned.call(StringName(item)) if owned.is_valid() else 0
	return n >= int(s.get("requires_min", 0))


func _occupants(spot: StringName, slot: int, t: float, except: Visit) -> int:
	return 1 if _occupant_species(spot, slot, t, except) != &"" else 0


func _occupant_species(spot: StringName, slot: int, t: float, except: Visit) -> StringName:
	if spot == OPEN_FIELD:
		return &""
	for v: Visit in _visits:
		if v == except:
			continue
		for i in range(v.bouts.size() - 1, -1, -1):
			var b := v.bouts[i]
			if b.end_t <= t:
				break
			if b.start_t <= t and b.spot == spot and b.slot == slot:
				return v.species
	return &""


func _free_slot(spot: StringName, t: float, v: Visit) -> int:
	var sp: Dictionary = content.spots_by_id.get(spot, {})
	var cap := int(sp.get("capacity", 1))
	for slot in cap:
		if _occupants(spot, slot, t, v) == 0:
			return slot
	return 0


func _visit(species: StringName) -> Visit:
	for v: Visit in _visits:
		if v.species == species:
			return v
	return null


func _env(t: float) -> Dictionary:
	return env.call(t) if env.is_valid() else {}


static func _likes_weather(sp: Dictionary, weather: StringName) -> bool:
	for l: Dictionary in sp.get("likes_weather", []):
		if StringName(l.get("weather", "")) == weather:
			return true
	return false


func _likes_any(species: StringName, flowers: Array) -> bool:
	var sp: Dictionary = content.species_by_id.get(species, {})
	for key: String in ["likes_items", "requires"]:
		for l: Dictionary in sp.get(key, []):
			if flowers.has(StringName(l.get("item", ""))) or flowers.has(String(l.get("item", ""))):
				return true
	return false
