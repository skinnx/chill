class_name GrassField
extends Node2D
## Meadow grass (Art Bible §4.6, §6.4): Poisson-disk tufts (Bridson), 2.5x denser at the meadow's
## edges, banks and around props/beds than in the open rest areas, none inside beds, props, the
## path or the brook; one shared 4-blade tuft mesh drawn as 5 MultiMesh depth bands so creatures
## sort against grass to about +-90 px. V4 needs >= 260 tufts (A8); the layout gives ~600.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const SHADER_PATH := "res://shaders/world/grass.gdshader"
const SEED := 4242
## Band edges in design y (Art Bible §4.6 + the near bank below the brook).
const BANDS: Array[float] = [700.0, 1000.0, 1200.0, 1380.0, 1530.0, 1960.0]
const X_RANGE := Vector2(-200.0, 1280.0)
## Poisson radii of tuft CLUSTERS (px at depth 1): open meadow vs edges (2.5x denser = radius /
## sqrt(2.5)); each cluster holds an odd-feeling 1-5 tufts (Art Bible §11.4 "odd clusters").
const R_OPEN := 118.0
const R_EDGE := 60.0
const CLUSTER_SIZES: Array[int] = [1, 2, 3, 3, 4, 5]
const CLUSTER_SPREAD_PX := 15.0
## Tuft mesh: authored 28 px tall at depth 1; (base x, angle rad, length k, root width px) per blade.
const TUFT_H := 26.0
const BLADES: Array[Vector4] = [Vector4(-7.0, -0.5, 0.66, 7.0), Vector4(-2.5, -0.12, 1.0, 8.0),
		Vector4(2.5, 0.18, 0.84, 7.6), Vector4(7.0, 0.52, 0.58, 6.4)]
const SEGMENTS := 4
## Instance variation (Art Bible §11.4: scale +-8-15 %, rotation +-3-6 deg).
const HEIGHT_RANGE := Vector2(0.72, 1.28)
const WIDTH_RANGE := Vector2(0.85, 1.15)
const ROT_DEG := 4.0
const LEAN_PX := 3.0
## Depth scale s(y) (Art Bible §2.4).
const DEPTH := Vector3(0.62, 760.0, 740.0)
## Clearances (px).
const PATH_CLEAR := 60.0
const BROOK_CLEAR := 8.0
const CREST_CLEAR := 12.0
const EDGE_REACH := 90.0
## Governor tier 1 keeps 60 % of the tufts (Art Bible §4.19).
const TIER1_KEEP := 0.6

var positions := PackedVector2Array()

var _mat: ShaderMaterial
var _feed := PaletteFeed.new()
var _crest := PackedVector2Array()
var _brook: BrookLayer = null
var _blockers: Array[Vector4] = []  # (cx, cy, rx, ry) ellipses
var _bands: Array[MultiMeshInstance2D] = []


func _ready() -> void:
	var content := ContentRegistry.content
	_crest = TerrainMath.sample_meadow(4.0)
	_collect_blockers(content)
	var brook_pts := TerrainMath.resample_catmull_rom(BrookLayer.polyline_px(content), 12.0)
	var half := BrookLayer.half_width_px(content) + BrookLayer.BANK_PX
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var rect := Rect2(X_RANGE.x, BANDS[0], X_RANGE.y - X_RANGE.x, BANDS[BANDS.size() - 1] - BANDS[0])
	var radius := func(p: Vector2) -> float:
		return lerpf(R_OPEN, R_EDGE, _edge_weight(p, brook_pts, half)) * depth_scale(p.y)
	var accept := func(p: Vector2) -> bool: return _allowed(p, brook_pts, half)
	var centres := TerrainMath.poisson_disk(rect, R_EDGE * DEPTH.x, R_OPEN, radius, accept, rng)
	positions = _clusters(centres, rng, brook_pts, half)
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH) as Shader
	var gk: Array = ContentRegistry.motion_tokens()["loops_k"]["grass_sway"]
	_feed.bind(_mat, &"grass_tip", "grass_tip")
	_feed.bind(_mat, &"grass_root", "grass_root")
	_feed.bind(_mat, &"ground_back_lit", "ground_back_lit")
	_feed.bind(_mat, &"ground_front_lit", "ground_front_lit")
	_feed.apply(TimeOfDay.colors)
	TimeOfDay.globals_updated.connect(func(_v: Dictionary) -> void: _feed.apply(TimeOfDay.colors))
	LampRegistry.bind_material(_mat)
	tree_exiting.connect(func() -> void: LampRegistry.unbind_material(_mat))
	_build_bands(tuft_mesh(), rng, Vector2(float(gk[0]), float(gk[1])))


## Expands cluster centres into tufts: the first is the anchor, the rest scatter close around it.
func _clusters(centres: PackedVector2Array, rng: RandomNumberGenerator, brook_pts: PackedVector2Array,
		half: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for c: Vector2 in centres:
		out.append(c)
		var n := CLUSTER_SIZES[rng.randi_range(0, CLUSTER_SIZES.size() - 1)]
		var s := depth_scale(c.y)
		for i in n - 1:
			var a := rng.randf() * TAU
			var p := c + Vector2(cos(a), sin(a) * 0.55) * rng.randf_range(0.5, 1.0) * CLUSTER_SPREAD_PX * s * float(i + 1) * 0.7
			if _allowed(p, brook_pts, half):
				out.append(p)
	return out


static func depth_scale(y: float) -> float:
	return clampf(DEPTH.x + (1.0 - DEPTH.x) * (y - DEPTH.y) / DEPTH.z, DEPTH.x, 1.0)


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
	# Art dressing footprints (Art Bible §2.4): willow trunk, moon rock, moss mound, clover bank.
	for v: Vector4 in [Vector4(118, 812, 60, 26), Vector4(800, 776, 64, 26), Vector4(378, 1152, 48, 22),
			Vector4(702, 1150, 36, 18), Vector4(488, 1170, 36, 16)]:
		_blockers.append(v)


func _allowed(p: Vector2, brook_pts: PackedVector2Array, half: float) -> bool:
	if p.y < TerrainMath.crest_at(_crest, p.x) + CREST_CLEAR:
		return false
	for e: Vector4 in _blockers:
		var q := Vector2((p.x - e.x) / e.z, (p.y - e.y) / e.w)
		if q.length_squared() < 1.0:
			return false
	if absf(p.y - _brook_y(brook_pts, p.x)) < half + BROOK_CLEAR:
		return false
	var path := MeadowLayer.path_at(p.y)
	if path.w > 0.3 and absf(p.x - path.y) < PATH_CLEAR:
		return false
	return true


## 0 in the open meadow .. 1 at edges: crest, frame sides, banks, around props and beds.
func _edge_weight(p: Vector2, brook_pts: PackedVector2Array, half: float) -> float:
	var w := 1.0 - smoothstep(0.0, 160.0, p.y - TerrainMath.crest_at(_crest, p.x))
	w = maxf(w, 1.0 - smoothstep(60.0, 220.0, minf(p.x, 1080.0 - p.x)))
	w = maxf(w, 1.0 - smoothstep(0.0, 80.0, absf(p.y - _brook_y(brook_pts, p.x)) - half))
	for e: Vector4 in _blockers:
		var q := Vector2((p.x - e.x) / e.z, (p.y - e.y) / e.w)
		var d := (q.length() - 1.0) * minf(e.z, e.w)
		w = maxf(w, 1.0 - smoothstep(0.0, EDGE_REACH, d))
	return w


static func _brook_y(pts: PackedVector2Array, x: float) -> float:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		if (x <= a.x and x >= b.x) or (x >= a.x and x <= b.x):
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x) if absf(b.x - a.x) > 0.001 else 0.0)
	return pts[pts.size() - 1].y if x < pts[pts.size() - 1].x else pts[0].y


## The shared tuft: 4 tapered, slightly curved blades rooted around x = 0 (Art Bible §4.6).
static func tuft_mesh() -> ArrayMesh:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for b: Vector4 in BLADES:
		var base := verts.size()
		var length := TUFT_H * b.z
		for s in SEGMENTS + 1:
			var t := float(s) / SEGMENTS
			var bend := signf(b.y) * t * t * length * 0.12
			var c := Vector2(b.x + sin(b.y) * length * t + bend, -cos(b.y) * length * t)
			var hw := (b.w * pow(1.0 - t, 0.75) + 1.4) * 0.5
			var n := Vector2(cos(b.y), sin(b.y))
			verts.append(c - n * hw)
			uvs.append(Vector2(0.0, 1.0 - t))
			verts.append(c + n * hw)
			uvs.append(Vector2(1.0, 1.0 - t))
		for s in SEGMENTS:
			var k := base + s * 2
			idx.append_array(PackedInt32Array([k, k + 2, k + 1, k + 1, k + 2, k + 3]))
	var cols := PackedColorArray()
	cols.resize(verts.size())
	cols.fill(Color.WHITE)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_bands(mesh: ArrayMesh, rng: RandomNumberGenerator, k_range: Vector2) -> void:
	for bi in BANDS.size() - 1:
		var lo := BANDS[bi]
		var hi := BANDS[bi + 1]
		var pts := PackedVector2Array()
		for p: Vector2 in positions:
			if p.y >= lo and p.y < hi:
				pts.append(p)
		if pts.is_empty():
			continue
		_shuffle(pts, rng)
		var origin := Vector2(0.0, 0.5 * (lo + hi))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = pts.size()
		for i in pts.size():
			var p := pts[i]
			var s := depth_scale(p.y)
			var flip := -1.0 if rng.randf() < 0.5 else 1.0
			var sx := s * rng.randf_range(WIDTH_RANGE.x, WIDTH_RANGE.y) * flip
			var sy := s * rng.randf_range(HEIGHT_RANGE.x, HEIGHT_RANGE.y)
			var xf := Transform2D(deg_to_rad(rng.randf_range(-ROT_DEG, ROT_DEG)), Vector2(sx, sy), 0.0, p - origin)
			mm.set_instance_transform_2d(i, xf)
			mm.set_instance_color(i, Color(rng.randf(), rng.randf(), 1.0, 1.0))
			var k := floorf(rng.randf_range(k_range.x, k_range.y + 1.0))
			mm.set_instance_custom_data(i, Color(k, TUFT_H * sy, rng.randf() * TAU, rng.randf_range(-LEAN_PX, LEAN_PX)))
		var node := MultiMeshInstance2D.new()
		node.name = "Band%d" % bi
		node.multimesh = mm
		node.material = _mat
		node.position = origin
		add_child(node)
		_bands.append(node)
	FrameGovernor.tier_changed.connect(_apply_tier)
	_apply_tier(FrameGovernor.tier)


## Governor tier 1+: grass x 0.6 (instances are shuffled, so the thinning is even).
func _apply_tier(tier: int) -> void:
	for b: MultiMeshInstance2D in _bands:
		var n := b.multimesh.instance_count
		b.multimesh.visible_instance_count = n if tier == 0 else roundi(n * TIER1_KEEP)


static func _shuffle(pts: PackedVector2Array, rng: RandomNumberGenerator) -> void:
	for i in range(pts.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := pts[i]
		pts[i] = pts[j]
		pts[j] = t
