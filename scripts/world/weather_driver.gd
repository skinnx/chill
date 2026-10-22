class_name WeatherDriver
extends RefCounted
## Crossfades between weather states (GDD §6.2: 30 s, world.json weather_crossfade_s) and blends
## the per-weather numbers of world.json (g_wind, cloud cover, ambient multiplier, rain particles).
## Pure: [method step] is driven by the TimeOfDay autoload; tests drive it directly.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

var _defs: Dictionary = {}
var _crossfade_s: float = 30.0
var _target: StringName = &""
var _from: Dictionary = {}
var _weights: Dictionary = {}
var _elapsed: float = 0.0


func _init(world: Dictionary, initial: StringName = &"clear") -> void:
	for w: Dictionary in world["weather"]:
		_defs[StringName(w["id"])] = w
	_crossfade_s = maxf(0.001, float(world.get("weather_crossfade_s", 30.0)))
	snap_to(initial)


## Jump straight to a state (boot, QA override): no crossfade.
func snap_to(id: StringName) -> void:
	_target = id
	_weights.clear()
	for k: StringName in _defs:
		_weights[k] = 1.0 if k == id else 0.0
	_from = _weights.duplicate()
	_elapsed = _crossfade_s


func target() -> StringName:
	return _target


func is_crossfading() -> bool:
	return _elapsed < _crossfade_s


## Advances the crossfade toward [param id] by [param dt] seconds. Returns true if values moved.
func step(id: StringName, dt: float) -> bool:
	if id != _target:
		_from = _weights.duplicate()
		_target = id
		_elapsed = 0.0
	if _elapsed >= _crossfade_s:
		return false
	_elapsed = minf(_crossfade_s, _elapsed + dt)
	var k := smoothstep(0.0, 1.0, _elapsed / _crossfade_s)
	for w: StringName in _defs:
		var goal := 1.0 if w == _target else 0.0
		_weights[w] = lerpf(float(_from.get(w, 0.0)), goal, k)
	return true


func weight(id: StringName) -> float:
	return float(_weights.get(id, 0.0))


## Blended value of a numeric world.json weather field (g_wind, cloud_cover, ambient_mult ...).
func blend(field: String) -> float:
	var v := 0.0
	for w: StringName in _defs:
		v += float(_weights[w]) * float((_defs[w] as Dictionary).get(field, 0.0))
	return v
