extends Node
## TimeOfDay (autoload): the Art Bible's PaletteDriver + WeatherDriver + celestial writer.
##
## Reads the device clock (Clock), maps it to the g_day palette key (TodMath, world.json), samples
## the OKLab palettes (PaletteDriver, palettes.json), blends the weather of the deterministic day
## plan (WeatherPlan + WeatherDriver, 30 s crossfade), applies the rain transform and pushes the
## shader globals declared in project.godot [shader_globals] (Art Bible §4.1).
##
## Push policy (Art Bible §3.3 step 4): 2 Hz in steady state, every frame while weather
## crossfades or an override changes; only values that changed are sent, and the CPU mirror means
## global_shader_parameter_get() is never called during play.
##
## QA user args: --tod=<0..1> pins g_day · --weather=<clear|breeze|rain> pins the weather.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

signal phase_changed(phase: StringName)
signal weather_changed(weather: StringName)
## Emitted after each push with the CPU mirror of every global this driver owns.
signal globals_updated(values: Dictionary)

const PUSH_INTERVAL_S := 0.5
const EPSILON := 1e-4

var phase: StringName = &""
var weather: StringName = &"clear"
var g_day: float = 0.4
## Canvas offset of the bottom-anchored design frame: (centering x, viewport_h - 1920).
var world_offset: Vector2 = Vector2.ZERO
## Current palette colours by slot (all 27, for consumers such as the sky gradient texture).
var colors: Dictionary = {}
var scalars: Dictionary = {}

var palette: PaletteDriver
var weather_driver: WeatherDriver
var celestial: Celestial

var _content: GameContent
var _plan: WeatherPlan
var _override_g_day: float = NAN
var _override_weather: StringName = &""
var _mirror: Dictionary = {}
var _accum: float = INF
var _force: bool = true


func _ready() -> void:
	_content = ContentRegistry.content
	palette = PaletteDriver.new(_content.palettes)
	var tod: Dictionary = _content.palettes["tod"]
	var cel: Dictionary = tod["celestial"]
	celestial = Celestial.new(cel)
	_plan = WeatherPlan.new(_content, 0)
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--tod="):
			_override_g_day = clampf(a.get_slice("=", 1).to_float(), 0.0, 1.0)
		elif a.begins_with("--weather="):
			_override_weather = StringName(a.get_slice("=", 1))
	weather = _target_weather()
	weather_driver = WeatherDriver.new(_content.world, weather)
	Clock.time_overridden.connect(func() -> void: _force = true)
	_update(0.0)


func _process(delta: float) -> void:
	_update(delta)


## The weather plan is seeded per install (Game calls this after loading the save).
func set_install_seed(install_seed: int) -> void:
	_plan = WeatherPlan.new(_content, install_seed)
	weather_driver.snap_to(_target_weather())
	_force = true


func set_world_offset(offset: Vector2) -> void:
	world_offset = offset
	_set_global(&"g_world_offset", offset)


## QA / debug: pin g_day (NAN releases) and/or the weather (&"" releases).
func set_overrides(p_g_day: float, p_weather: StringName) -> void:
	_override_g_day = p_g_day
	_override_weather = p_weather
	weather_driver.snap_to(_target_weather())
	_force = true


## Every global this driver would write at local time [param local_s] with weather weights as
## they are now. Pure apart from reading the current crossfade state (used by tests and QA).
func evaluate(local_s: float) -> Dictionary:
	var gd := _override_g_day if not is_nan(_override_g_day) else TodMath.g_day_at(_content, local_s)
	var col := palette.sample_colors(gd)
	var sc := palette.sample_scalars(gd)
	var r := weather_driver.weight(WeatherPlan.RAIN)
	palette.apply_rain(col, sc, r)
	var ambient_mult := weather_driver.blend("ambient_mult")
	var amb: Color = col["ambient"]
	col["ambient"] = Color(amb.r * ambient_mult, amb.g * ambient_mult, amb.b * ambient_mult, amb.a)
	var cloud := weather_driver.blend("cloud_cover")
	var hour := TodMath.seconds_of_day(local_s) / TodMath.SECONDS_PER_HOUR
	var cel := celestial.evaluate(hour if is_nan(_override_g_day) else _hour_for_g_day(gd), cloud)
	var out := {&"g_day": gd, &"g_wind": weather_driver.blend("g_wind"), &"g_cloud": cloud, &"g_rain": r,
		&"g_sun_dir": cel["sun_dir"], &"g_sun_pos": (cel["sun"] as Vector2) + world_offset,
		&"g_moon_pos": (cel["moon"] as Vector2) + world_offset, &"g_celestial": cel["visibility"],
		&"g_halo": Vector2(float(sc.get("halo_scale", 1.0)), float(sc.get("halo_alpha", 0.0)))}
	for slot: String in PaletteDriver.COLOR_GLOBALS:
		if col.has(slot):
			out[PaletteDriver.COLOR_GLOBALS[slot]] = col[slot]
	for name: String in PaletteDriver.SCALAR_GLOBALS:
		if sc.has(name):
			out[PaletteDriver.SCALAR_GLOBALS[name]] = float(sc[name])
	out[&"_colors"] = col
	out[&"_scalars"] = sc
	return out


func current_weather_particles() -> float:
	return weather_driver.blend("rain_particles")


func _update(delta: float) -> void:
	var local_s := Clock.now_local()
	var target := _target_weather()
	if target != weather:
		weather = target
		weather_changed.emit(weather)
	var moving := weather_driver.step(target, delta)
	_accum += delta
	if not (moving or _force or _accum >= PUSH_INTERVAL_S):
		return
	_accum = 0.0
	_force = false
	var values := evaluate(local_s)
	g_day = float(values[&"g_day"])
	colors = values[&"_colors"]
	scalars = values[&"_scalars"]
	for key: StringName in values:
		if not String(key).begins_with("_"):
			_set_global(key, values[key])
	var ph := TodMath.phase_id_at(_content, local_s) if is_nan(_override_g_day) else _phase_for_g_day(g_day)
	if ph != phase:
		phase = ph
		phase_changed.emit(phase)
	globals_updated.emit(_mirror)


func _target_weather() -> StringName:
	if _override_weather != &"" and _content.weather_by_id.has(_override_weather):
		return _override_weather
	return _plan.weather_at(Clock.now_local())


func _set_global(name: StringName, value: Variant) -> void:
	if _mirror.has(name) and _approx_equal(_mirror[name], value):
		return
	_mirror[name] = value
	RenderingServer.global_shader_parameter_set(name, value)


## Phase whose key is nearest to a pinned g_day (QA override).
func _phase_for_g_day(gd: float) -> StringName:
	var best: StringName = &""
	var best_d := INF
	for p: Dictionary in _content.phases:
		var k := float(p["g_day"])
		var d := minf(absf(gd - k), absf(gd - fposmod(k, 1.0)))
		if d < best_d:
			best_d = d
			best = StringName(p["id"])
	return best


## A representative clock hour for a pinned g_day, so the sun/moon match the palette in captures.
func _hour_for_g_day(gd: float) -> float:
	var ph := _phase_for_g_day(gd)
	var p: Dictionary = _content.phases[_content.phase_index[ph]]
	var crossfade := float(_content.world.get("phase_crossfade_s", 0.0))
	return (float(p["start_s"]) + crossfade) / TodMath.SECONDS_PER_HOUR + 0.5


static func _approx_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_FLOAT:
			return absf(float(a) - float(b)) < EPSILON
		TYPE_VECTOR2:
			return (a as Vector2).is_equal_approx(b as Vector2)
		TYPE_COLOR:
			return (a as Color).is_equal_approx(b as Color)
	return a == b
