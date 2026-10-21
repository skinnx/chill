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
const BACKLIGHT_K := 0.30


## Elevation 0.05..1 of the brighter body.
static func elevation(values: Dictionary) -> float:
	var cel: Vector2 = values.get(&"g_celestial", Vector2(1, 0))
	var body: Vector2 = values.get(&"g_sun_pos", Vector2(780, 380)) if cel.x >= cel.y \
			else values.get(&"g_moon_pos", Vector2(820, 380))
	var off: Vector2 = values.get(&"g_world_offset", Vector2.ZERO)
	return clampf((HORIZON_Y - (body - off).y) / ELEVATION_SPAN_PX, ELEV_MIN, 1.0)


static func length_factor(values: Dictionary) -> float:
	return clampf(LEN_K / elevation(values), LEN_K, LEN_MAX)


## Cast offset in px (away from the light, toward the viewer) for an object `height_px` tall.
static func cast_offset(values: Dictionary, height_px: float) -> Vector2:
	var dir: Vector2 = values.get(&"g_sun_dir", Vector2(0.6, -0.8))
	var back := float(values.get(&"g_backlight", 0.1))
	return Vector2(-dir.x * SIDE_K, TOWARD_VIEWER + BACKLIGHT_K * back) * length_factor(values) * height_px * 0.5
