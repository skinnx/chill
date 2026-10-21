class_name MeadowScatter
extends RefCounted
## Deterministic layout of the meadow dressing (Art Bible §4.6, §6.4; round-2 directive 2):
## felted grass clumps in odd Poisson clusters (2.5x denser at the meadow's edges, banks, around
## props and beds than in the open rest areas) plus ground cover: clover patches, small moss mounds
## and sprinkles of wild micro-flowers, also in odd clusters. Nothing grows inside beds, props, the
## brook or on the path. Pure and seeded: GrassField (clumps, y-sorted bands) and MeadowLayer
## (ground cover, under the play layer) build the same layout. Cached per content instance.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

enum Kind { CLUMP, CLOVER, MOSS, FLOWERS }

const SEED := 4242
const COVER_SEED := 5151
const Y_RANGE := Vector2(700.0, 1960.0)
const X_RANGE := Vector2(-220.0, 1300.0)
## Poisson radii of clump CLUSTERS (px at depth 1): open meadow vs edges (2.5x denser = / sqrt 2.5).
const R_OPEN := 150.0
const R_EDGE := 70.0
## Odd-feeling cluster sizes (Art Bible §11.4 "odd clusters").
const CLUSTER_SIZES: Array[int] = [1, 1, 3, 3, 3, 5, 2]
const CLUSTER_SPREAD_PX := 17.0
## Ground cover: Poisson radius of cover clusters and their size.
const R_COVER := 120.0
const COVER_CLUSTER: Array[int] = [1, 3, 3, 5]
const COVER_SPREAD_PX := 30.0
## Depth scale (Art Bible §2.4) for things on the ground, steepened toward the viewer below the
## brook (the near ground reads closer: up to ~1.55 at the frame bottom).
const DEPTH := Vector3(0.62, 760.0, 740.0)
const NEAR_BOOST := Vector3(1500.0, 1960.0, 0.32)
## Clearances (px).
const PATH_CLEAR := 62.0
const BROOK_CLEAR := 10.0
const CREST_CLEAR := 14.0
const EDGE_REACH := 90.0
## Art dressing footprints (Art Bible §2.4): willow trunk, moon rock, moss mound, clover bank,
## glow mushrooms; (cx, cy, rx, ry).
const DRESSING_BLOCKERS: Array[Vector4] = [Vector4(118, 812, 60, 26), Vector4(800, 776, 64, 26),
		Vector4(378, 1152, 48, 22), Vector4(702, 1150, 36, 18), Vector4(488, 1170, 36, 16)]

## Fixed art dressing (Art Bible §2.4): the moss cushion at moss_cushion, the clover patch at
## clover_bank and three clover patches; (x, y, kind, scale multiplier).
const FIXED_COVER: Array[Vector4] = [Vector4(378, 1150, Kind.MOSS, 2.6), Vector4(702, 1152, Kind.CLOVER, 1.7),
		Vector4(430, 1290, Kind.CLOVER, 1.4), Vector4(700, 1225, Kind.CLOVER, 1.3), Vector4(905, 1385, Kind.CLOVER, 1.4)]

static var _cache: Dictionary = {}

## Clumps: position (design px of the root).
var clumps := PackedVector2Array()
## Ground cover: position and kind (Kind.CLOVER / MOSS / FLOWERS).
var cover := PackedVector2Array()
var cover_kind := PackedInt32Array()
## Per-item scale multiplier (1 except the fixed dressing).
var cover_scale := PackedFloat32Array()

var _crest := PackedVector2Array()
var _brook := PackedVector2Array()
var _brook_half: float = 34.5
var _blockers: Array[Vector4] = []


## Shared layout for this content (built once).
static func for_content(content: GameContent) -> MeadowScatter:
	var key := content.get_instance_id()
	if not _cache.has(key):
		var s := MeadowScatter.new()
		s._build(content)
		_cache[key] = s
	return _cache[key]


static func depth_scale(y: float) -> float:
	var s := clampf(DEPTH.x + (1.0 - DEPTH.x) * (y - DEPTH.y) / DEPTH.z, DEPTH.x, 1.0)
	return s + NEAR_BOOST.z * smoothstep(NEAR_BOOST.x, NEAR_BOOST.y, y)


func _build(content: GameContent) -> void:
	_crest = TerrainMath.sample_meadow(4.0)
	_collect_blockers(content)
	_brook = TerrainMath.resample_catmull_rom(BrookLayer.polyline_px(content), 12.0)
	_brook_half = BrookLayer.half_width_px(content) + BrookLayer.BANK_PX
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var rect := Rect2(X_RANGE.x, Y_RANGE.x, X_RANGE.y - X_RANGE.x, Y_RANGE.y - Y_RANGE.x)
	var radius := func(p: Vector2) -> float:
		return lerpf(R_OPEN, R_EDGE, edge_weight(p)) * depth_scale(p.y)
	var accept := func(p: Vector2) -> bool: return allowed(p)
	var centres := TerrainMath.poisson_disk(rect, R_EDGE * DEPTH.x, R_OPEN * depth_scale(Y_RANGE.y), radius,
			accept, rng)
	clumps = _clusters(centres, rng, CLUSTER_SIZES, CLUSTER_SPREAD_PX)
	var crng := RandomNumberGenerator.new()
	crng.seed = COVER_SEED
	var cradius := func(p: Vector2) -> float:
		return R_COVER * lerpf(1.6, 1.0, edge_weight(p)) * depth_scale(p.y)
	var ccentres := TerrainMath.poisson_disk(rect, R_COVER * DEPTH.x, R_COVER * 1.6 * depth_scale(Y_RANGE.y),
			cradius, accept, crng)
	for c: Vector2 in ccentres:
		var kind := _cover_kind(c, crng)
		var pts := _clusters(PackedVector2Array([c]), crng, COVER_CLUSTER, COVER_SPREAD_PX)
		for p: Vector2 in pts:
			cover.append(p)
			cover_kind.append(kind)
			cover_scale.append(1.0)
	for f: Vector4 in FIXED_COVER:
		cover.append(Vector2(f.x, f.y))
		cover_kind.append(int(f.z))
		cover_scale.append(f.w)


## Banks favour moss and flowers, the open meadow clover, the edges a mix (deterministic).
func _cover_kind(p: Vector2, rng: RandomNumberGenerator) -> int:
	var near_brook := absf(p.y - brook_y(p.x)) - _brook_half < 120.0
	var u := rng.randf()
	if near_brook:
		return Kind.MOSS if u < 0.4 else (Kind.FLOWERS if u < 0.75 else Kind.CLOVER)
	if edge_weight(p) > 0.5:
		return Kind.MOSS if u < 0.3 else (Kind.FLOWERS if u < 0.55 else Kind.CLOVER)
	return Kind.CLOVER if u < 0.6 else (Kind.FLOWERS if u < 0.8 else Kind.MOSS)


## Expands cluster centres: the first item is the anchor, the rest scatter close around it.
func _clusters(centres: PackedVector2Array, rng: RandomNumberGenerator, sizes: Array[int],
		spread: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for c: Vector2 in centres:
		out.append(c)
		var n := sizes[rng.randi_range(0, sizes.size() - 1)]
		var s := depth_scale(c.y)
		for i in n - 1:
			var a := rng.randf() * TAU
			var p := c + Vector2(cos(a), sin(a) * 0.55) * rng.randf_range(0.55, 1.0) * spread * s * (1.0 + 0.6 * float(i))
			if allowed(p):
				out.append(p)
	return out


func _collect_blockers(content: GameContent) -> void:
	var frame: Dictionary = content.spots_doc["frame"]
	var dp := float(frame["px_per_dp"])
	for b: Dictionary in content.beds:
		var c := GardenRules.frame_to_px(content, Vector2(float(b["x"]), float(b["y"])))
		_blockers.append(Vector4(c.x, c.y, float(b["hit_w_dp"]) * dp * 0.5, float(b["hit_h_dp"]) * dp * 0.5))
	for p: Dictionary in content.props_by_id.values():
		if String(p["id"]) in ["willow", "wind_chime_branch"]:
			continue
		var c := GardenRules.frame_to_px(content, Vector2(float(p["x"]), float(p["y"])))
		var half := Vector2(float(p["w_dp"]), float(p["h_dp"])) * dp * 0.5
		_blockers.append(Vector4(c.x, c.y, half.x * 1.04, half.y * 1.2))
	for v: Vector4 in DRESSING_BLOCKERS:
		_blockers.append(v)


func allowed(p: Vector2) -> bool:
	if p.y < TerrainMath.crest_at(_crest, p.x) + CREST_CLEAR:
		return false
	for e: Vector4 in _blockers:
		var q := Vector2((p.x - e.x) / e.z, (p.y - e.y) / e.w)
		if q.length_squared() < 1.0:
			return false
	if absf(p.y - brook_y(p.x)) < _brook_half + BROOK_CLEAR:
		return false
	var path := MeadowLayer.path_at(p.y)
	if path.w > 0.3 and absf(p.x - path.y) < PATH_CLEAR:
		return false
	return true


## 0 in the open meadow .. 1 at edges: crest, frame sides, banks, around props and beds.
func edge_weight(p: Vector2) -> float:
	var w := 1.0 - smoothstep(0.0, 160.0, p.y - TerrainMath.crest_at(_crest, p.x))
	w = maxf(w, 1.0 - smoothstep(60.0, 220.0, minf(p.x, 1080.0 - p.x)))
	w = maxf(w, 1.0 - smoothstep(0.0, 90.0, absf(p.y - brook_y(p.x)) - _brook_half))
	for e: Vector4 in _blockers:
		var q := Vector2((p.x - e.x) / e.z, (p.y - e.y) / e.w)
		var d := (q.length() - 1.0) * minf(e.z, e.w)
		w = maxf(w, 1.0 - smoothstep(0.0, EDGE_REACH, d))
	return w


func brook_y(x: float) -> float:
	var pts := _brook
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		if (x <= a.x and x >= b.x) or (x >= a.x and x <= b.x):
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x) if absf(b.x - a.x) > 0.001 else 0.0)
	return pts[pts.size() - 1].y if x < pts[pts.size() - 1].x else pts[0].y
