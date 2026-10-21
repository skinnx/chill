class_name Butterflies
extends Node2D
## Butterflies over the garden (Art Bible §7.1 "not particles"): 0-3 little boids by day and at
## golden hour (clear or breeze, never in rain) once at least 3 stems have bloomed. Each one
## drifts in from the side, seeks a bloomed flower (90-150 px/s, a lazy wander on top), lands on it
## for 3-8 s with its wings slowly opening and closing (0.5 Hz), then picks another; in flight the
## wings flap at 2.4 Hz with short glides. Colours come from the petal rows of fl_buttercup and
## fl_forget_me_not with a colour-line body. All of them are ONE mesh drawn with the flora
## material (one draw call), rebuilt each frame from a handful of quads.
##
## Deterministic per install (seeded), so a capture is reproducible; under Reduce Motion they
## glide (no flapping) at 0.3 x speed.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## Art Bible §7.1.
const MAX_COUNT := 3
const MIN_BLOOMS := 3
const PHASES: Array[StringName] = [&"day", &"golden"]
const SPEED := Vector2(90.0, 150.0)
const LAND_S := Vector2(3.0, 8.0)
const FLAP_HZ := 2.4
const REST_FLAP_HZ := 0.5
const Y_BAND := Vector2(700.0, 1450.0)
const COLOUR_FLOWERS: Array[StringName] = [&"buttercup", &"forget_me_not"]
## Shape and feel [J]: wing scale at depth 1, steering, wander, glides, fades.
const WING_SCALE := 1.7
const STEER := 2.2
const WANDER_PX_S := 70.0
const WANDER_HZ := 0.35
const GLIDE_EVERY_S := 1.7
const GLIDE_S := 0.45
const ARRIVE_PX := 10.0
const PERCH_DY := -6.0
const FADE_S := 0.3
const OFFSCREEN_X := Vector2(-60.0, 1140.0)
const SORT_Y := 1915.0
const SPAWN_GAP_S := 2.5
const DEPTH := Vector3(0.62, 760.0, 740.0)
## FrameGovernor quality tier at which butterflies stay away.
const LOW_TIER := 2

var _builder: FloraBuilder
var _mesh: MeshInstance2D
var _rng := RandomNumberGenerator.new()
var _flies: Array[Fly] = []
var _rows: Array[int] = []
var _spawn_t: float = 0.0
var _tips: Callable


class Fly:
	extends RefCounted
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var target := Vector2.ZERO
	var has_target: bool = false
	var land_left: float = 0.0
	var speed: float = 120.0
	var row: int = 0
	var t: float = 0.0
	var phase: float = 0.0
	var alpha: float = 0.0
	var leaving: bool = false


## [param tips] returns the design positions of bloomed flower heads (Array[Vector2]).
func setup(builder: FloraBuilder, material: ShaderMaterial, atlas: Texture2D, content: GameContent,
		tips: Callable, install_seed: int) -> void:
	_builder = builder
	_tips = tips
	_rng.seed = hash([install_seed, "butterflies"])
	for id: StringName in COLOUR_FLOWERS:
		_rows.append(FloraBuilder.row_of(content, id))
	position = Vector2(0.0, SORT_Y)
	_mesh = MeshInstance2D.new()
	_mesh.texture = atlas
	_mesh.material = material
	_mesh.position = Vector2(0.0, -SORT_Y)
	add_child(_mesh)


func count() -> int:
	return _flies.size()


func _wanted(blooms: int) -> int:
	if not PHASES.has(TimeOfDay.phase) or TimeOfDay.weather == &"rain" or blooms < MIN_BLOOMS:
		return 0
	if FrameGovernor.tier >= LOW_TIER:
		return 0  # the lowest quality tier sheds the optional life first
	return mini(MAX_COUNT, blooms / MIN_BLOOMS)


func _process(delta: float) -> void:
	if _builder == null:
		return
	var tips: Array = _tips.call()
	var want := _wanted(tips.size())
	_spawn_t -= delta
	if _flies.size() < want and _spawn_t <= 0.0:
		_spawn()
		_spawn_t = SPAWN_GAP_S
	var leaving := _flies.size() - want
	for f: Fly in _flies:
		if leaving > 0 and not f.leaving:
			f.leaving = true
			f.has_target = false
			leaving -= 1
	var motion := 0.3 if Motion.reduce_motion else 1.0
	for i in range(_flies.size() - 1, -1, -1):
		var f := _flies[i]
		_step(f, delta * motion, tips)
		if f.leaving and (f.pos.x < OFFSCREEN_X.x or f.pos.x > OFFSCREEN_X.y):
			_flies.remove_at(i)
	_draw_mesh()


func _spawn() -> void:
	var f := Fly.new()
	var left := _rng.randf() < 0.5
	f.pos = Vector2(OFFSCREEN_X.x if left else OFFSCREEN_X.y, _rng.randf_range(Y_BAND.x + 150.0, Y_BAND.y - 150.0))
	f.speed = _rng.randf_range(SPEED.x, SPEED.y)
	f.row = _rows[_rng.randi_range(0, _rows.size() - 1)]
	f.phase = _rng.randf() * TAU
	_flies.append(f)


func _step(f: Fly, dt: float, tips: Array) -> void:
	f.t += dt
	f.alpha = minf(1.0, f.alpha + dt / FADE_S)
	if f.land_left > 0.0:
		f.land_left -= dt
		if f.land_left <= 0.0:
			f.has_target = false
			f.vel = Vector2(_rng.randf_range(-1.0, 1.0), -1.0).normalized() * f.speed * 0.5
		return
	if not f.has_target:
		if f.leaving:
			f.target = Vector2(OFFSCREEN_X.x - 100.0 if f.pos.x < 540.0 else OFFSCREEN_X.y + 100.0, f.pos.y - 80.0)
			f.has_target = true
		elif not tips.is_empty():
			f.target = tips[_rng.randi_range(0, tips.size() - 1)] as Vector2 + Vector2(0.0, PERCH_DY)
			f.has_target = true
	var to := f.target - f.pos if f.has_target else Vector2.ZERO
	var wander := Vector2(sin(TAU * WANDER_HZ * f.t + f.phase), cos(TAU * WANDER_HZ * 1.37 * f.t + f.phase * 1.3))
	var desired := to.normalized() * f.speed if to.length() > 1.0 else Vector2.ZERO
	desired += wander * WANDER_PX_S * clampf(to.length() / 120.0, 0.0, 1.0)
	f.vel = f.vel.lerp(desired, clampf(STEER * dt, 0.0, 1.0))
	f.pos += f.vel * dt
	f.pos.y = clampf(f.pos.y, Y_BAND.x, Y_BAND.y) if not f.leaving else f.pos.y
	if f.has_target and not f.leaving and f.pos.distance_to(f.target) < ARRIVE_PX:
		f.pos = f.target
		f.vel = Vector2.ZERO
		f.land_left = _rng.randf_range(LAND_S.x, LAND_S.y)


func _draw_mesh() -> void:
	if _flies.is_empty():
		if _mesh.mesh != null:
			_mesh.mesh = null
		return
	_builder.begin()
	for f: Fly in _flies:
		var depth := clampf(DEPTH.x + (1.0 - DEPTH.x) * (f.pos.y - DEPTH.y) / DEPTH.z, DEPTH.x, 1.0)
		var open := 1.0
		var tilt := 0.0
		if f.land_left > 0.0:
			open = 0.55 + 0.45 * absf(cos(PI * REST_FLAP_HZ * f.t + f.phase))
		elif not Motion.reduce_motion:
			var glide := fposmod(f.t + f.phase, GLIDE_EVERY_S) < GLIDE_S
			open = 1.0 if glide else 0.2 + 0.8 * absf(cos(PI * FLAP_HZ * f.t + f.phase))
			tilt = clampf(f.vel.x / 400.0, -0.35, 0.35)
		var s := WING_SCALE * depth
		_builder.add_stamp("wing", f.pos, tilt, Vector2(s * open, s), FloraBuilder.PART_PETAL, f.row, f.alpha)
		_builder.add_stamp("wing", f.pos, tilt, Vector2(-s * open, s), FloraBuilder.PART_PETAL, f.row, f.alpha)
	_mesh.mesh = _builder.end_mesh()
