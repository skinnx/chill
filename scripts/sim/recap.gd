class_name Recap
extends RefCounted
## Welcome-back recap (GDD §7.5): shown on resume when the gap >= welcome_back_min_gap_s and at
## least one event happened. Up to MAX_LINES lines, in priority order, never listing what did not
## happen. Pure: built from the catch-up event list; the UI formats lines at display time so the
## language and custom names are always current.
##
## Line = {"key": StringName, "species": StringName (or &"")}.
## Priority (GDD §13.5.3, §14.11 a5): new friend -> away-scene teaser -> cousin -> postcard ->
## hearts -> a wish granted on arrival (Active F1 RECAP_WISH) -> clue -> the longest nap of the
## absence ("{name} napped at the {spot}", GDD §7.5), which takes the visitors slot when there was
## one, else visitors -> a friend still hoping for something (RECAP_WISH_WAITING) -> nest -> gifts
## waiting -> new flowers opened -> photos -> it rained. The teaser names nobody and always gets a
## line when a scene is staged.
##
## Round 8: the nap line was written in the MVP and waited for the creature brain. Nothing about a
## past visit is stored - [method CreatureBrain.nap_during] replans the absence's bouts from the
## catch-up events, which is exact because the brain is deterministic. [param nap] is its result
## ({} when nobody napped); the caller passes it in so this stays a pure sim-side function.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const MAX_LINES := 3
## Weather is sampled this often across the absence to detect rain (the plan's episodes are >= 1 h).
const RAIN_SAMPLE_S := 600.0


static func should_show(content: GameContent, gap_s: float, events: Array[Dictionary]) -> bool:
	return gap_s >= float(content.economy["welcome_back_min_gap_s"]) and not events.is_empty()


static func build(sim: WorldSim, events: Array[Dictionary], from_t: float, to_t: float,
		nap: Dictionary = {}) -> Array[Dictionary]:
	var met: Array[StringName] = []
	var visitors: Array[StringName] = []
	var postcard := false
	var gifts := false
	var bloomed := false
	var photos := false
	var scene := &""
	var cousin := &""
	var heart_sp := &""
	var heart_n := 0
	var clue := false
	var nest := &""
	var wish := &""
	for ev: Dictionary in events:
		match ev["type"]:
			WorldSim.EV_MET:
				met.append(StringName(ev["species"]))
			WorldSim.EV_ARRIVED:
				var sp := StringName(ev["species"])
				if not bool(ev["debut"]) and not visitors.has(sp):
					visitors.append(sp)
			WorldSim.EV_POSTCARD:
				postcard = true
			WorldSim.EV_GIFT:
				gifts = true
			WorldSim.EV_STAGE:
				bloomed = bloomed or int(ev["stage"]) == WorldSim.STAGE_BLOOM
			WorldSim.EV_PHOTO:
				photos = photos or bool(ev["new"])
			WorldSim.EV_SCENE_STAGED:
				scene = StringName(ev["scene"])
			WorldSim.EV_COUSIN_MET:
				if cousin == &"":
					cousin = StringName(ev["species"])
			WorldSim.EV_HEARTS:
				if int(ev["hearts"]) > heart_n:
					heart_n = int(ev["hearts"])
					heart_sp = StringName(ev["species"])
			WorldSim.EV_SIGN_DUE:
				clue = true
			WorldSim.EV_NEST_STAGE:
				if nest == &"":
					nest = StringName(ev["species"])
			WorldSim.EV_WISH_GRANTED:
				if wish == &"" and bool(ev.get("on_arrival", false)):
					wish = StringName(ev["species"])  # a decor_near piece set while it was away
	# GDD §13.5.3 priority: new friend, scene teaser, cousin, postcard, hearts, wish, clue, visitors,
	# nest, gifts, flowers, photos, rain.
	var cands: Array[Dictionary] = []
	for sp: StringName in met:
		cands.append({"key": &"RECAP_NEW_FRIEND", "species": sp})
	var teaser := {}
	if scene != &"":
		var sdef: Dictionary = sim.content.scenes_by_id.get(scene, {})
		teaser = {"key": StringName(sdef.get("teaser_key", "")), "species": &"", "scene": scene}
		cands.append(teaser)
	if cousin != &"":
		cands.append({"key": &"RECAP_COUSIN", "species": cousin})
	if postcard:
		cands.append({"key": &"RECAP_POSTCARD", "species": &""})
	if heart_sp != &"":
		cands.append({"key": &"RECAP_HEARTS", "species": heart_sp})
	if wish != &"":
		cands.append({"key": &"RECAP_WISH", "species": wish})
	if clue:
		cands.append({"key": &"RECAP_CLUE", "species": &""})
	if not nap.is_empty():
		# "{name} napped at the {spot}" is a better line than "{name} dropped by": it says what
		# they did, not just that they came, so it takes the visitors slot (GDD §13.5.3).
		cands.append({"key": &"RECAP_NAPPED", "species": StringName(nap.get("species", &"")),
			"spot": StringName(nap.get("spot", &""))})
	elif visitors.size() == 1:
		cands.append({"key": &"RECAP_ONE_VISITED", "species": visitors[0]})
	elif visitors.size() > 1:
		cands.append({"key": &"RECAP_FRIENDS_VISITED", "species": visitors[0]})
	var waiting := wish_waiting(sim)
	if waiting != &"" and wish == &"":
		cands.append({"key": &"RECAP_WISH_WAITING", "species": waiting})
	if nest != &"":
		cands.append({"key": &"RECAP_NEST", "species": nest})
	if gifts and not sim.state.basket.is_empty():
		cands.append({"key": &"RECAP_GIFTS", "species": &""})
	if bloomed:
		cands.append({"key": &"RECAP_BLOOMED", "species": &""})
	if photos:
		cands.append({"key": &"RECAP_PHOTOS", "species": &""})
	var lines: Array[Dictionary] = []
	for line: Dictionary in cands:
		_add(lines, StringName(line["key"]), StringName(line["species"]), StringName(line.get("spot", &"")))
	if not teaser.is_empty() and not _has_key(lines, StringName(teaser["key"])):
		lines[lines.size() - 1] = {"key": StringName(teaser["key"]), "species": &""}  # the teaser always shows
	if lines.size() < MAX_LINES and _rained(sim, from_t, to_t):
		_add(lines, &"RECAP_RAINED", &"")
	return lines


static func _has_key(lines: Array[Dictionary], key: StringName) -> bool:
	for l: Dictionary in lines:
		if StringName(l["key"]) == key:
			return true
	return false


static func _add(lines: Array[Dictionary], key: StringName, species: StringName,
		spot: StringName = &"") -> void:
	if lines.size() >= MAX_LINES:
		return
	var line := {"key": key, "species": species}
	if spot != &"":
		line["spot"] = spot  # only RECAP_NAPPED carries one; every other line keeps its shape
	lines.append(line)


## The friend to name in RECAP_WISH_WAITING: the oldest wish still waiting to be granted, a friend
## who is here preferred. A wish never expires, so this line can never become a deadline - it is
## only an offer, in the three seconds when the player is most receptive (GDD §14.0 AP3).
static func wish_waiting(sim: WorldSim) -> StringName:
	var best := &""
	var best_t := INF
	var present_best := false
	for w: Dictionary in sim.state.wishes:
		var state := String(w.get("state", ""))
		if state != WorldState.WISH_OPEN and state != WorldState.WISH_HELD:
			continue
		var sp := StringName(String(w.get("species", "")))
		if sp == &"":
			continue
		var here := sim.is_present(sp)
		var t := float(w.get("opened_t", 0.0))
		if (here and not present_best) or (here == present_best and t < best_t):
			best = sp
			best_t = t
			present_best = here
	return best


static func _rained(sim: WorldSim, from_t: float, to_t: float) -> bool:
	var t := from_t
	while t <= to_t:
		if sim.weather_at(t) == WeatherPlan.RAIN:
			return true
		t += RAIN_SAMPLE_S
	return false
