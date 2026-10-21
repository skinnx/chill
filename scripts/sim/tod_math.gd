class_name TodMath
extends RefCounted
## Device-clock time of day (GDD §6.1, world.json). Pure static functions shared by the sim
## (phase-gated visitors) and the TimeOfDay driver (palette), so gameplay and picture agree.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const SECONDS_PER_DAY := 86400.0
const SECONDS_PER_HOUR := 3600.0


static func seconds_of_day(local_s: float) -> float:
	return fposmod(local_s, SECONDS_PER_DAY)


## Local calendar day number (days since 1970-01-01 in local time).
static func local_day(local_s: float) -> int:
	return floori(local_s / SECONDS_PER_DAY)


## Index into [member GameContent.phases] of the phase active at [param local_s].
## Before the first phase start of the day it is still the last phase (night).
static func phase_index_at(content: GameContent, local_s: float) -> int:
	var sod := seconds_of_day(local_s)
	var idx := content.phases.size() - 1
	for i in content.phases.size():
		if sod >= float(content.phases[i]["start_s"]):
			idx = i
	return idx


static func phase_id_at(content: GameContent, local_s: float) -> StringName:
	return StringName(content.phases[phase_index_at(content, local_s)]["id"])


## The palette key g_day at [param local_s] (Art Bible §3.3 step 1).
## Each phase crossfades from the previous phase's key over world.phase_crossfade_s starting at
## its start. The phase whose key is 1.0 (night) reads 0.0 after midnight; the palette gradient
## has night at both ends, so the jump at 00:00 is invisible.
static func g_day_at(content: GameContent, local_s: float) -> float:
	var sod := seconds_of_day(local_s)
	var n := content.phases.size()
	var i := phase_index_at(content, local_s)
	var cur: Dictionary = content.phases[i]
	var prev: Dictionary = content.phases[posmod(i - 1, n)]
	var crossfade := maxf(1.0, float(content.world.get("phase_crossfade_s", 0.0)))
	var start := float(cur["start_s"])
	# Seconds since this phase began; the last phase wraps past midnight.
	var since := sod - start
	if since < 0.0:
		since += SECONDS_PER_DAY
	var to_key := _key_at(cur, sod)
	var from_key := _key_at(prev, sod)
	var k := clampf(since / crossfade, 0.0, 1.0)
	return lerpf(from_key, to_key, k)


## True while the palette is still moving toward the current phase's key.
static func is_crossfading(content: GameContent, local_s: float) -> bool:
	var sod := seconds_of_day(local_s)
	var cur: Dictionary = content.phases[phase_index_at(content, local_s)]
	var since := sod - float(cur["start_s"])
	if since < 0.0:
		since += SECONDS_PER_DAY
	return since < float(content.world.get("phase_crossfade_s", 0.0))


static func _key_at(phase: Dictionary, sod: float) -> float:
	var key := float(phase["g_day"])
	# A key of 1.0 is the same palette as 0.0. After midnight (before this phase's start in
	# clock order) use 0.0 so that interpolation toward dawn (0.2) runs the short way.
	if key >= 1.0 and sod < float(phase["start_s"]):
		return 0.0
	return key
