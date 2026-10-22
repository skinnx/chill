class_name WeatherPlan
extends RefCounted
## Deterministic daily weather plan (GDD §6.2, world.json weather_plan).
##
## For each local calendar day d the plan RNG is seeded from (install_seed, d); it draws the
## number of rain and breeze episodes from the count probabilities, then for each episode a start
## uniform in the day and a duration uniform in [min, max]. Episodes may cross midnight, so a
## lookup also checks the previous day. Rain wins over breeze, otherwise clear. A drawn plan never
## changes, so the sim (offline catch-up) and the live driver always agree.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const CLEAR := &"clear"
const BREEZE := &"breeze"
const RAIN := &"rain"
const SALT := "weather"
const CACHE_DAYS := 16

var _content: GameContent
var _install_seed: int
## day -> {"rain": PackedFloat64Array [a0, b0, a1, b1...], "breeze": ...} in local seconds.
var _cache: Dictionary = {}


func _init(content: GameContent, install_seed: int) -> void:
	_content = content
	_install_seed = install_seed


func weather_at(local_s: float) -> StringName:
	var d := TodMath.local_day(local_s)
	var breeze := false
	for dd: int in [d, d - 1]:
		var plan := day_plan(dd)
		var rain: PackedFloat64Array = plan["rain"]
		var breezes: PackedFloat64Array = plan["breeze"]
		if _inside(rain, local_s):
			return RAIN
		if not breeze and _inside(breezes, local_s):
			breeze = true
	return BREEZE if breeze else CLEAR


## Episodes of local day [param day] as flat [start, end, start, end ...] arrays.
func day_plan(day: int) -> Dictionary:
	if _cache.has(day):
		return _cache[day]
	var wp: Dictionary = _content.world["weather_plan"]
	var rng := RandomNumberGenerator.new()
	rng.seed = plan_seed(_install_seed, day)
	var rain_probs: Array = wp["rain_count_probs"]
	var breeze_probs: Array = wp["breeze_count_probs"]
	var plan := {
		"rain": _episodes(rng, day, rain_probs, float(wp["rain_min_s"]), float(wp["rain_max_s"])),
		"breeze": _episodes(rng, day, breeze_probs, float(wp["breeze_min_s"]), float(wp["breeze_max_s"])),
	}
	if _cache.size() >= CACHE_DAYS:
		_cache.clear()
	_cache[day] = plan
	return plan


## Stable across platforms and runs: String.hash() is a fixed djb2 variant.
static func plan_seed(install_seed: int, day: int) -> int:
	return ("%s/%d/%d" % [SALT, install_seed, day]).hash()


static func _episodes(rng: RandomNumberGenerator, day: int, probs: Array, lo: float, hi: float) -> PackedFloat64Array:
	var x := rng.randf()
	var acc := 0.0
	var n := probs.size() - 1
	for i in probs.size():
		acc += float(probs[i])
		if x < acc:
			n = i
			break
	var out := PackedFloat64Array()
	for _i in n:
		var start := float(day) * TodMath.SECONDS_PER_DAY + rng.randf() * TodMath.SECONDS_PER_DAY
		out.append(start)
		out.append(start + rng.randf_range(lo, hi))
	return out


static func _inside(episodes: PackedFloat64Array, local_s: float) -> bool:
	var i := 0
	while i + 1 < episodes.size():
		if local_s >= episodes[i] and local_s < episodes[i + 1]:
			return true
		i += 2
	return false
