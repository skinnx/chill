class_name ShadowMath
extends RefCounted
## Cast-shadow geometry shared by every standing object (Art Bible §4.12, §8.1; palettes.json
## tod.celestial elevation_rule): direction away from the brighter body (g_sun_dir), length
## clamp(0.35 / elev, 0.35, 2.5) and a lean toward the viewer that grows with backlight. Pure: the
## globals come in as TimeOfDay's mirror dictionary (globals_updated).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const HORIZON_Y := 690.0
const ELEVATION_SPAN_PX := 400.0
const ELEV_MIN := 0.05
const LEN_K := 0.35
const LEN_MAX := 2.5
const SIDE_K := 0.8
const TOWARD_VIEWER := 0.10
const BACKLIGHT_K := 0.60
## Round 3 (QA r2: "long shadows toward the viewer, fanning away from the sun"): the cast runs
## length_factor x the object height from the foot (2.5 h at golden), clamped to CAST_MAX_PX, and
## with backlight it turns from the key's side direction to the ray from the sun through the foot.
const CAST_MAX_PX := 220.0
const FAN_MIN_DIST := 1.0


## Elevation 0.05..1 of the brighter body.
static func elevation(values: Dictionary) -> float:
	var cel: Vector2 = values.get(&"g_celestial", Vector2(1, 0))
	var body: Vector2 = values.get(&"g_sun_pos", Vector2(780, 380)) if cel.x >= cel.y \
			else values.get(&"g_moon_pos", Vector2(820, 380))
	var off: Vector2 = values.get(&"g_world_offset", Vector2.ZERO)
	return clampf((HORIZON_Y - (body - off).y) / ELEVATION_SPAN_PX, ELEV_MIN, 1.0)


static func length_factor(values: Dictionary) -> float:
	return clampf(LEN_K / elevation(values), LEN_K, LEN_MAX)


## Cast offset in px (away from the light, toward the viewer) for an object `height_px` tall: the
## centre of the cast ellipse, half the cast length from the foot. With `foot` (design px) the
## direction fans away from the sun in proportion to the backlight (contre-jour at golden).
static func cast_offset(values: Dictionary, height_px: float, foot: Vector2 = Vector2.INF) -> Vector2:
	var d := cast_dir(values, foot)
	return d * cast_length(values, height_px) * 0.5


## Full cast length in px: length_factor x height, clamped.
static func cast_length(values: Dictionary, height_px: float) -> float:
	return minf(length_factor(values) * height_px, CAST_MAX_PX)


## Unit direction of the cast (screen, y down).
static func cast_dir(values: Dictionary, foot: Vector2 = Vector2.INF) -> Vector2:
	var dir: Vector2 = values.get(&"g_sun_dir", Vector2(0.6, -0.8))
	var back := float(values.get(&"g_backlight", 0.1))
	var side := Vector2(-dir.x * SIDE_K, TOWARD_VIEWER + BACKLIGHT_K * back).normalized()
	if not foot.is_finite():
		return side
	var off: Vector2 = values.get(&"g_world_offset", Vector2.ZERO)
	var sun: Vector2 = (values.get(&"g_sun_pos", Vector2(780, 380)) as Vector2) - off
	var ray := foot - sun
	if ray.length() < FAN_MIN_DIST or ray.y <= 0.0:
		return side
	return side.lerp(ray.normalized(), clampf(back, 0.0, 1.0)).normalized()
