class_name ParticleBudget
extends RefCounted
## The <= 3 systems / <= 150 particles rule (synthesis D9, Art Bible §7.2). Pure: which ambient
## systems a time of day + weather wants (and how many particles each), and whether one more
## system may start while others are still finishing.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const MAX_SYSTEMS := 3
const MAX_PARTICLES := 150

## Art Bible §7.2 composition table (amounts are the peak; the rain count is world.json's).
const CLEAR := {
	&"dawn": {&"dust": 24, &"pollen": 8},
	&"day": {&"dust": 30, &"pollen": 10},
	&"golden": {&"dust": 36, &"pollen": 10},
	&"dusk": {&"fireflies": 10, &"pollen": 6},
	&"night": {&"fireflies": 18},
}
const BREEZE := {
	&"dawn": {&"dust": 24, &"seeds": 12, &"petals": 10},
	&"day": {&"dust": 24, &"seeds": 12, &"petals": 10},
	&"golden": {&"dust": 30, &"seeds": 12, &"petals": 10},
	&"dusk": {&"fireflies": 10, &"pollen": 6, &"seeds": 8},
	&"night": {&"fireflies": 18},
}
const SPLASH_AMOUNT := 6


## System id -> particle amount for a phase and weather (rain_particles from world.json in rain).
static func composition(phase: StringName, weather: StringName, rain_particles: int) -> Dictionary:
	if weather == &"rain":
		return {&"rain": rain_particles, &"splash": SPLASH_AMOUNT}
	var table: Dictionary = BREEZE if weather == &"breeze" else CLEAR
	var c: Dictionary = table.get(phase, table[&"day"])
	return c.duplicate()


## May `amount` more particles start, given the amounts of systems still alive (emitting or
## finishing their last particles)?
static func can_start(alive: Dictionary, amount: int) -> bool:
	if alive.size() + 1 > MAX_SYSTEMS:
		return false
	var total := amount
	for k: Variant in alive:
		total += int(alive[k])
	return total <= MAX_PARTICLES


static func total(comp: Dictionary) -> int:
	var t := 0
	for k: Variant in comp:
		t += int(comp[k])
	return t
