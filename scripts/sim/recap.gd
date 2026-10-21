class_name Recap
extends RefCounted
## Welcome-back recap (GDD §7.5): shown on resume when the gap >= welcome_back_min_gap_s and at
## least one event happened. Up to MAX_LINES lines, in priority order, never listing what did not
## happen. Pure: built from the catch-up event list; the UI formats lines at display time so the
## language and custom names are always current.
##
## Line = {"key": StringName, "species": StringName (or &"")}.
## Priority: new friend -> postcard -> visitors (the GDD's "{name} napped at the {spot}" line
## needs the creature brain's bout history and replaces this slot once that exists) -> gifts
## waiting -> new flowers opened -> photos -> it rained.

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
	var lines: Array[Dictionary] = []
	var met: Array[StringName] = []
	var visitors: Array[StringName] = []
	var postcard := false
	var gifts := false
	var bloomed := false
	var photos := false
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
	for sp: StringName in met:
		_add(lines, &"RECAP_NEW_FRIEND", sp)
	if postcard:
		_add(lines, &"RECAP_POSTCARD", &"")
	if visitors.size() == 1:
		_add(lines, &"RECAP_ONE_VISITED", visitors[0])
	elif visitors.size() > 1:
		_add(lines, &"RECAP_FRIENDS_VISITED", visitors[0])
	if gifts and not sim.state.basket.is_empty():
		_add(lines, &"RECAP_GIFTS", &"")
	if bloomed:
		_add(lines, &"RECAP_BLOOMED", &"")
	if photos:
		_add(lines, &"RECAP_PHOTOS", &"")
	if lines.size() < MAX_LINES and _rained(sim, from_t, to_t):
		_add(lines, &"RECAP_RAINED", &"")
	return lines


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
