class_name TerrainMath
extends RefCounted
## Pure geometry for the hollow's landscape (Art Bible §2.4, §4.4): seeded 1D fBm, the far crest,
## the mid tree line with canopy bumps, the meadow crest with its grass fringe, Catmull-Rom
## resampling of the brook and Bridson Poisson-disk sampling. Deterministic for a given seed on
## every platform (integer hashing, no engine RNG state), so the same hollow is built every boot.

## Wide-screen bleed: layer geometry spans x in [-400, 1480] (Art Bible §2.1, U9).
const X_MIN := -400.0
const X_MAX := 1480.0
const FRAME_W := 1080.0
const HASH_MASK := 0xFFFFFFFF
const HASH_NORM := 4294967296.0

## Art Bible §2.4 recipes.
const FAR_BASE_Y := 640.0
const FAR_AMP := 26.0
const FAR_F0 := 2.2
const FAR_OCTAVES := 7
const FAR_GAIN := 0.68
const FAR_SEED := 11
## Two broad rises of the far ridge: (centre x, rise px, sigma px).
const FAR_RISES: Array[Vector3] = [Vector3(380.0, 34.0, 90.0), Vector3(820.0, 22.0, 70.0)]
const MID_KNOTS: Array[Vector2] = [Vector2(0, 600), Vector2(300, 640), Vector2(520, 700), Vector2(700, 705),
		Vector2(900, 650), Vector2(1080, 610)]
const MID_AMP := 18.0
const MID_F0 := 6.0
const MID_OCTAVES := 7
const MID_GAIN := 0.70
const MID_SEED := 23
const MID_CANOPY_PER_FRAME := 120
const MID_CANOPY_R := Vector2(10.0, 46.0)
const MID_CANOPY_SINK := Vector2(0.15, 0.6)
const MEADOW_KNOTS: Array[Vector2] = [Vector2(0, 800), Vector2(300, 790), Vector2(600, 758), Vector2(800, 742),
		Vector2(1000, 790), Vector2(1080, 805)]
const MEADOW_AMP := 6.0
const MEADOW_F0 := 4.0
const MEADOW_OCTAVES := 6
const MEADOW_GAIN := 0.68
const MEADOW_SEED := 31
const MEADOW_FRINGE_PER_FRAME := 140
const MEADOW_FRINGE_R := Vector2(3.0, 10.0)
const MEADOW_FRINGE_SEED := 37


## Integer hash of (i, seed) -> [0, 1).
static func hash01(i: int, seed: int) -> float:
	var x := (i * 374761393 + seed * 668265263 + 0x9E3779B9) & HASH_MASK
	x = ((x ^ (x >> 13)) * 1274126177) & HASH_MASK
	x = (x ^ (x >> 16)) & HASH_MASK
	return float(x) / HASH_NORM


## 1D value noise in [-1, 1], smoothstep-interpolated.
static func vnoise1(x: float, seed: int) -> float:
	var i := floori(x)
	var f := x - float(i)
	var u := f * f * (3.0 - 2.0 * f)
	return lerpf(hash01(i, seed), hash01(i + 1, seed), u) * 2.0 - 1.0


## Normalised fBm in [-1, 1]: octaves at f0 * 2^k with amplitude gain^k (D = 2 - H, gain = 2^-H).
static func fbm1(x: float, f0: float, octaves: int, gain: float, seed: int) -> float:
	var s := 0.0
	var norm := 0.0
	var amp := 1.0
	var f := f0
	for k in octaves:
		s += amp * vnoise1(x * f, seed * 131 + k * 17)
		norm += amp
		amp *= gain
		f *= 2.0
	return s / norm


## Far ridge crest y at design x (Art Bible §2.4).
static func far_crest(x: float) -> float:
	var y := FAR_BASE_Y + FAR_AMP * fbm1(x / FRAME_W, FAR_F0, FAR_OCTAVES, FAR_GAIN, FAR_SEED)
	for r: Vector3 in FAR_RISES:
		var d := (x - r.x) / r.z
		y -= r.y * exp(-0.5 * d * d)
	return y


## Smooth curve through knots (Catmull-Rom in x; linear extrapolation outside the knots).
static func knot_curve(knots: Array[Vector2], x: float) -> float:
	var n := knots.size()
	if x <= knots[0].x:
		var s0 := (knots[1].y - knots[0].y) / (knots[1].x - knots[0].x)
		return knots[0].y + s0 * (x - knots[0].x) * 0.5
	if x >= knots[n - 1].x:
		var s1 := (knots[n - 1].y - knots[n - 2].y) / (knots[n - 1].x - knots[n - 2].x)
		return knots[n - 1].y + s1 * (x - knots[n - 1].x) * 0.5
	var i := 0
	while i < n - 2 and x > knots[i + 1].x:
		i += 1
	var p0 := knots[maxi(i - 1, 0)]
	var p1 := knots[i]
	var p2 := knots[i + 1]
	var p3 := knots[mini(i + 2, n - 1)]
	var t := (x - p1.x) / (p2.x - p1.x)
	var m1 := (p2.y - p0.y) / maxf(p2.x - p0.x, 1.0) * (p2.x - p1.x)
	var m2 := (p3.y - p1.y) / maxf(p3.x - p1.x, 1.0) * (p2.x - p1.x)
	var t2 := t * t
	var t3 := t2 * t
	return (2.0 * t3 - 3.0 * t2 + 1.0) * p1.y + (t3 - 2.0 * t2 + t) * m1 + (-2.0 * t3 + 3.0 * t2) * p2.y \
		+ (t3 - t2) * m2


## Samples x0..x1 every `step` px of a crest function.
static func sample_far(step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var x := X_MIN
	while x <= X_MAX + 0.01:
		out.append(Vector2(x, far_crest(x)))
		x += step
	return out


## Mid tree line: fBm ridge topped with power-law canopy circles; upper envelope every `step` px.
static func sample_mid(step: float) -> PackedVector2Array:
	var circles := _canopy_circles()
	var out := PackedVector2Array()
	var x := X_MIN
	while x <= X_MAX + 0.01:
		var y := knot_curve(MID_KNOTS, x) + MID_AMP * fbm1(x / FRAME_W, MID_F0, MID_OCTAVES, MID_GAIN, MID_SEED)
		for c: Vector3 in circles:
			var dx := x - c.x
			if absf(dx) < c.z:
				y = minf(y, c.y - sqrt(c.z * c.z - dx * dx))
		out.append(Vector2(x, y))
		x += step
	return out


static func _canopy_circles() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var count := roundi(MID_CANOPY_PER_FRAME * (X_MAX - X_MIN) / FRAME_W)
	for i in count:
		var cx := lerpf(X_MIN, X_MAX, hash01(i, MID_SEED + 1))
		var r := power_law(hash01(i, MID_SEED + 2), MID_CANOPY_R.x, MID_CANOPY_R.y)
		var sink := lerpf(MID_CANOPY_SINK.x, MID_CANOPY_SINK.y, hash01(i, MID_SEED + 3))
		var ridge := knot_curve(MID_KNOTS, cx) + MID_AMP * fbm1(cx / FRAME_W, MID_F0, MID_OCTAVES, MID_GAIN, MID_SEED)
		out.append(Vector3(cx, ridge + sink * r, r))
	return out


## Pareto (alpha 2) radius in [r0, r1] from a uniform u: many small, few large (Art Bible §2.4).
static func power_law(u: float, r0: float, r1: float) -> float:
	return 1.0 / (1.0 / r0 - u * (1.0 / r0 - 1.0 / r1))


## Meadow crest (walkable hill top) with its grass fringe of small bumps, every `step` px.
static func sample_meadow(step: float) -> PackedVector2Array:
	var bumps: Array[Vector3] = []
	var count := roundi(MEADOW_FRINGE_PER_FRAME * (X_MAX - X_MIN) / FRAME_W)
	for i in count:
		var bx := lerpf(X_MIN, X_MAX, (float(i) + hash01(i, MEADOW_FRINGE_SEED)) / float(count))
		var r := lerpf(MEADOW_FRINGE_R.x, MEADOW_FRINGE_R.y, hash01(i, MEADOW_FRINGE_SEED + 1))
		bumps.append(Vector3(bx, meadow_base(bx) + r * lerpf(0.35, 0.75, hash01(i, MEADOW_FRINGE_SEED + 2)), r))
	var out := PackedVector2Array()
	var x := X_MIN
	while x <= X_MAX + 0.01:
		var y := meadow_base(x)
		for b: Vector3 in bumps:
			var dx := x - b.x
			if absf(dx) < b.z:
				y = minf(y, b.y - sqrt(b.z * b.z - dx * dx))
		out.append(Vector2(x, y))
		x += step
	return out


## Meadow crest without the fringe (what feet stand on).
static func meadow_base(x: float) -> float:
	return knot_curve(MEADOW_KNOTS, x) + MEADOW_AMP * fbm1(x / FRAME_W, MEADOW_F0, MEADOW_OCTAVES, MEADOW_GAIN,
			MEADOW_SEED)


## Highest point (smallest y) and lowest point (largest y) of a sampled crest.
static func y_range(points: PackedVector2Array) -> Vector2:
	var lo := INF
	var hi := -INF
	for p: Vector2 in points:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	return Vector2(lo, hi)


## Linear interpolation of a crest sampled at a uniform step from X_MIN.
static func crest_at(points: PackedVector2Array, x: float) -> float:
	if points.size() < 2:
		return 0.0
	var step := points[1].x - points[0].x
	var f := clampf((x - points[0].x) / step, 0.0, float(points.size() - 1) - 0.001)
	var i := floori(f)
	return lerpf(points[i].y, points[i + 1].y, f - float(i))


## Centripetal-free uniform Catmull-Rom through `pts`, resampled every `spacing` px of arc length.
static func resample_catmull_rom(pts: PackedVector2Array, spacing: float) -> PackedVector2Array:
	var dense := PackedVector2Array()
	var n := pts.size()
	const SUB := 24
	for i in n - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, n - 1)]
		for s in SUB:
			var t := float(s) / SUB
			dense.append(_cr(p0, p1, p2, p3, t))
	dense.append(pts[n - 1])
	var out := PackedVector2Array([dense[0]])
	var carry := 0.0
	for i in range(1, dense.size()):
		var a := dense[i - 1]
		var b := dense[i]
		var seg := a.distance_to(b)
		var pos := spacing - carry
		while pos <= seg:
			out.append(a.lerp(b, pos / seg))
			pos += spacing
		carry = seg - (pos - spacing)
	if out[out.size() - 1].distance_to(dense[dense.size() - 1]) > spacing * 0.25:
		out.append(dense[dense.size() - 1])
	return out


static func _cr(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Bridson Poisson-disk sampling in `rect` with a position-dependent minimum distance
## (`radius_at.call(p) -> float`, must stay within [r_min, r_max]) and an acceptance test
## (`accept.call(p) -> bool`). Deterministic for a seeded `rng`.
static func poisson_disk(rect: Rect2, r_min: float, r_max: float, radius_at: Callable, accept: Callable,
		rng: RandomNumberGenerator, tries: int = 24) -> PackedVector2Array:
	var cell := r_min / sqrt(2.0)
	var gw := ceili(rect.size.x / cell)
	var gh := ceili(rect.size.y / cell)
	var grid := PackedInt32Array()
	grid.resize(gw * gh)
	grid.fill(-1)
	var pts := PackedVector2Array()
	var active := PackedInt32Array()
	# Seed a coarse grid so regions split by rejected areas (a brook, a bed) all get filled.
	var seed_step := r_max * 4.0
	var sy := rect.position.y + seed_step * 0.5
	while sy < rect.end.y:
		var sx := rect.position.x + seed_step * 0.5
		while sx < rect.end.x:
			var sp := Vector2(sx, sy) + Vector2(rng.randf() - 0.5, rng.randf() - 0.5) * seed_step * 0.5
			if rect.has_point(sp) and accept.call(sp):
				var r_s: float = radius_at.call(sp)
				if _far_enough(sp, r_s, pts, grid, rect, cell, gw, gh, ceili(r_max / cell) + 1):
					pts.append(sp)
					active.append(pts.size() - 1)
					grid[_cell_index(sp, rect, cell, gw, gh)] = pts.size() - 1
			sx += seed_step
		sy += seed_step
	var reach := ceili(r_max / cell) + 1
	while not active.is_empty():
		var ai := rng.randi_range(0, active.size() - 1)
		var base := pts[active[ai]]
		var r_base: float = radius_at.call(base)
		var placed := false
		for _t in tries:
			var ang := rng.randf() * TAU
			var dist := r_base * (1.0 + rng.randf())
			var p := base + Vector2(cos(ang), sin(ang)) * dist
			if not rect.has_point(p):
				continue
			var r_p: float = radius_at.call(p)
			if not _far_enough(p, r_p, pts, grid, rect, cell, gw, gh, reach):
				continue
			if not accept.call(p):
				continue
			pts.append(p)
			active.append(pts.size() - 1)
			grid[_cell_index(p, rect, cell, gw, gh)] = pts.size() - 1
			placed = true
			break
		if not placed:
			active.remove_at(ai)
	return pts


static func _cell_index(p: Vector2, rect: Rect2, cell: float, gw: int, gh: int) -> int:
	var cx := clampi(floori((p.x - rect.position.x) / cell), 0, gw - 1)
	var cy := clampi(floori((p.y - rect.position.y) / cell), 0, gh - 1)
	return cy * gw + cx


static func _far_enough(p: Vector2, r: float, pts: PackedVector2Array, grid: PackedInt32Array, rect: Rect2,
		cell: float, gw: int, gh: int, reach: int) -> bool:
	var cx := floori((p.x - rect.position.x) / cell)
	var cy := floori((p.y - rect.position.y) / cell)
	for gy in range(maxi(cy - reach, 0), mini(cy + reach + 1, gh)):
		for gx in range(maxi(cx - reach, 0), mini(cx + reach + 1, gw)):
			var idx := grid[gy * gw + gx]
			if idx >= 0 and pts[idx].distance_squared_to(p) < r * r:
				return false
	return true
