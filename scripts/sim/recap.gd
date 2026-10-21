class_name Recap
extends RefCounted
## Welcome-back recap (GDD §7.5): shown on resume when the gap >= welcome_back_min_gap_s and at
## least one event happened. Up to MAX_LINES lines, in priority order, never listing what did not
## happen. Pure: built from the catch-up event list; the UI formats lines at display time so the
## language and custom names are always current.
##
## Line = {"key": StringName, "species": StringName (or &"")}.
## Priority (GDD §13.5.3): new friend -> away-scene teaser -> cousin -> postcard -> hearts ->
## clue -> visitors (the GDD's "{name} napped at the {spot}" line needs the creature brain's bout
## history and replaces this slot once that exists) -> nest -> gifts waiting -> new flowers opened
## -> photos -> it rained. The teaser names nobody and always gets a line when a scene is staged.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const MAX_LINES := 3
## Weather is sampled this often across the absence to detect rain (the plan's episodes are >= 1 h).
const RAIN_SAMPLE_S := 600.0


static func should_show(content: GameContent, gap_s: float, events: Array[Dictionary]) -> bool:
	return gap_s >= float(content.economy["welcome_back_min_gap_s"]) and not events.is_empty()


static func build(sim: WorldSim, events: Array[Dictionary], from_t: float, to_t: float) -> Array[Dictionary]:
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
	# GDD §13.5.3 priority: new friend, scene teaser, cousin, postcard, hearts, clue, visitors,
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
	if clue:
		cands.append({"key": &"RECAP_CLUE", "species": &""})
	if visitors.size() == 1:
		cands.append({"key": &"RECAP_ONE_VISITED", "species": visitors[0]})
	elif visitors.size() > 1:
		cands.append({"key": &"RECAP_FRIENDS_VISITED", "species": visitors[0]})
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
		_add(lines, StringName(line["key"]), StringName(line["species"]))
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


static func _add(lines: Array[Dictionary], key: StringName, species: StringName) -> void:
	if lines.size() < MAX_LINES:
		lines.append({"key": key, "species": species})


static func _rained(sim: WorldSim, from_t: float, to_t: float) -> bool:
	var t := from_t
	while t <= to_t:
		if sim.weather_at(t) == WeatherPlan.RAIN:
			return true
		t += RAIN_SAMPLE_S
	return false
