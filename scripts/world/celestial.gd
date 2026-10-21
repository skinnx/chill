class_name Celestial
extends RefCounted
## Sun and moon paths (Art Bible §3.3 step 5, palettes.json tod.celestial): hour-keyed
## Catmull-Rom paths in design px, 30 min fades at the path ends, light direction from the
## brighter body. Pure; the TimeOfDay autoload adds g_world_offset and pushes the globals.

## Art Bible §3.3: "sun visibility x (1 - 0.85 g_cloud)".
const SUN_CLOUD_DIM := 0.85

var _sun_t := PackedFloat64Array()
var _sun_p := PackedVector2Array()
var _moon_t := PackedFloat64Array()
var _moon_p := PackedVector2Array()
var _fade_h := 0.5
var _center := Vector2.ZERO


func _init(celestial: Dictionary) -> void:
	var sun_keys: Array = celestial["sun"]
	var moon_keys: Array = celestial["moon"]
	_load_path(sun_keys, _sun_t, _sun_p)
	_load_path(moon_keys, _moon_t, _moon_p)
	var fade_minutes: float = celestial.get("fade_minutes", 30)
	_fade_h = fade_minutes / 60.0
	var center: Array = celestial["scene_center"]
	var c := PackedFloat64Array(center)
	_center = Vector2(c[0], c[1])


## {sun: Vector2, moon: Vector2, visibility: Vector2(sun, moon), sun_dir: Vector2} at a local hour.
func evaluate(local_hour: float, cloud: float) -> Dictionary:
	var sun := _sample(_sun_t, _sun_p, local_hour)
	var moon := _sample(_moon_t, _moon_p, local_hour)
	var sun_vis: float = sun[1] * (1.0 - SUN_CLOUD_DIM * clampf(cloud, 0.0, 1.0))
	var moon_vis: float = moon[1]
	var body: Vector2 = sun[0] if sun_vis >= moon_vis else moon[0]
	var dir := (body - _center).normalized()
	return {"sun": sun[0], "moon": moon[0], "visibility": Vector2(sun_vis, moon_vis), "sun_dir": dir}


static func _load_path(keys: Array, times: PackedFloat64Array, points: PackedVector2Array) -> void:
	var last := -INF
	for k: Variant in keys:
		var key: Array = k
		var a := PackedFloat64Array(key)
		var h := a[0]
		while h < last:
			h += 24.0  # unwrap paths that cross midnight (the moon)
		last = h
		times.append(h)
		points.append(Vector2(a[1], a[2]))


## [position, visibility]; positions clamp to the path ends outside the path's hours.
func _sample(times: PackedFloat64Array, points: PackedVector2Array, hour: float) -> Array:
	var h := fposmod(hour, 24.0)
	if h < times[0] and h + 24.0 <= times[times.size() - 1]:
		h += 24.0
	var t0 := times[0]
	var t1 := times[times.size() - 1]
	if h <= t0:
		return [points[0], 0.0]
	if h >= t1:
		return [points[points.size() - 1], 0.0]
	var vis := smoothstep(0.0, _fade_h, h - t0) * smoothstep(0.0, _fade_h, t1 - h)
	var i := 0
	while i < times.size() - 2 and h > times[i + 1]:
		i += 1
	var p := _hermite(times, points, i, h)
	return [p, vis]


## Time-aware Catmull-Rom (cubic Hermite with finite-difference tangents) on segment i.
static func _hermite(times: PackedFloat64Array, points: PackedVector2Array, i: int, h: float) -> Vector2:
	var n := times.size()
	var ta := times[i]
	var tb := times[i + 1]
	var dt := tb - ta
	var u := (h - ta) / dt
	var m0 := _tangent(times, points, i, n)
	var m1 := _tangent(times, points, i + 1, n)
	var u2 := u * u
	var u3 := u2 * u
	return (2.0 * u3 - 3.0 * u2 + 1.0) * points[i] + (u3 - 2.0 * u2 + u) * dt * m0 \
		+ (-2.0 * u3 + 3.0 * u2) * points[i + 1] + (u3 - u2) * dt * m1


static func _tangent(times: PackedFloat64Array, points: PackedVector2Array, i: int, n: int) -> Vector2:
	var a := maxi(i - 1, 0)
	var b := mini(i + 1, n - 1)
	return (points[b] - points[a]) / (times[b] - times[a])
