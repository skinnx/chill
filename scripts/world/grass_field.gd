class_name GrassField
extends Node2D
## Meadow grass (Art Bible §4.6, §6.4; round-2 directive 2): soft, rounded, felted grass clumps in
## odd Poisson clusters (MeadowScatter), drawn analytically by shaders/world/grass.gdshader on
## small quads, batched as MultiMesh depth bands inside the y-sorted play layer.
##
## Sorting (QA round 1 blocker: tufts drew across a creature's face): each band's origin is its
## TOP edge, so a band sorts behind every creature whose feet are inside or below it. The only
## possible error is a clump just in front of a creature's feet drawing behind it, which hides
## under the body instead of crossing it. Bands are 105 px tall where creatures walk (crest to the
## brook) and one band covers the near bank, where no creature stands.
##
## The ground cover (clover, moss mounds, wild flowers) is built by [method build_cover] into the
## meadow layer, under everything that stands. V4 needs >= 260 clumps (A8).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const SHADER_PATH := "res://shaders/world/grass.gdshader"
const MOSS_TEX := "res://art/fx/moss_tile.png"
const SEED := 4243
## Band edges (design y): 105 px bands from above the crest to the brook, then the near bank.
const BAND_TOP := 700.0
const BAND_STEP := 105.0
const BAND_SPLIT := 1540.0
const BAND_BOTTOM := 1980.0
## Quad (local px at depth 1, root at the origin): x +-QUAD_HW, y -QUAD_TOP..QUAD_BOTTOM.
const QUAD_HW := 23.0
const QUAD_TOP := 42.0
const QUAD_BOTTOM := 7.0
## Instance variation (Art Bible §11.4: scale +-8-15 %, rotation +-3-6 deg).
const HEIGHT_RANGE := Vector2(0.78, 1.22)
const WIDTH_RANGE := Vector2(0.88, 1.12)
const ROT_DEG := 4.0
const LEAN_PX := 3.0
const AMP_PX := Vector2(4.0, 7.0)
const COVER_AMP_PX := Vector2(1.0, 2.5)
## Wild flower petals (palettes.json flora tokens) -> grass.gdshader petal_a..d.
const PETAL_TOKENS: Array[String] = ["fl_daisy", "fl_buttercup", "fl_forget_me_not", "fl_clover"]
## Governor tier 1 keeps 60 % of the clumps (Art Bible §4.19).
const TIER1_KEEP := 0.6

var positions := PackedVector2Array()

var _mat: ShaderMaterial
var _feed := PaletteFeed.new()
var _bands: Array[MultiMeshInstance2D] = []


func _ready() -> void:
	var content := ContentRegistry.content
	var scatter := MeadowScatter.for_content(content)
	positions = scatter.clumps
	_mat = make_material(_feed)
	TimeOfDay.globals_updated.connect(func(_v: Dictionary) -> void: _feed.apply(TimeOfDay.colors))
	tree_exiting.connect(func() -> void: LampRegistry.unbind_material(_mat))
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var gk: Array = ContentRegistry.motion_tokens()["loops_k"]["grass_sway"]
	_build_bands(quad_mesh(), rng, Vector2(float(gk[0]), float(gk[1])))


## One grass material (palette slots bound to `feed`, lamps, moss texture, flower tokens).
static func make_material(feed: PaletteFeed) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH) as Shader
	for slot: String in ["grass_tip", "grass_root", "ground_back_lit", "ground_front_lit"]:
		feed.bind(mat, StringName(slot), slot)
	feed.apply(TimeOfDay.colors)
	mat.set_shader_parameter(&"moss_tex", load(MOSS_TEX) as Texture2D)
	var flowers: Dictionary = ContentRegistry.palettes()["flora"]["flowers"]
	var names: Array[StringName] = [&"petal_a", &"petal_b", &"petal_c", &"petal_d"]
	for i in PETAL_TOKENS.size():
		var petal: Array = flowers[PETAL_TOKENS[i]]["petal"]
		mat.set_shader_parameter(names[i], Color.html(String(petal[0])))
	var daisy: Array = flowers["fl_daisy"]["petal"]
	mat.set_shader_parameter(&"flower_eye", Color.html(String(daisy[2])))
	LampRegistry.bind_material(mat)
	return mat


static func depth_scale(y: float) -> float:
	return MeadowScatter.depth_scale(y)


## The shared quad (2 triangles) every dressing item is drawn on.
static func quad_mesh() -> ArrayMesh:
	var verts := PackedVector2Array([Vector2(-QUAD_HW, -QUAD_TOP), Vector2(QUAD_HW, -QUAD_TOP),
			Vector2(QUAD_HW, QUAD_BOTTOM), Vector2(-QUAD_HW, QUAD_BOTTOM)])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var cols := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Band edges in design y.
static func band_edges() -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var y := BAND_TOP
	while y < BAND_SPLIT:
		out.append(y)
		y += BAND_STEP
	out.append(BAND_SPLIT)
	out.append(BAND_BOTTOM)
	return out


## Fills a MultiMesh with items (design px, kind) relative to `origin`, back to front.
static func fill(mm: MultiMesh, items: PackedVector2Array, kinds: PackedInt32Array, origin: Vector2,
		rng: RandomNumberGenerator, k_range: Vector2, amp_range: Vector2,
		scales: PackedFloat32Array = PackedFloat32Array()) -> void:
	var order := range(items.size())
	order.sort_custom(func(a: int, b: int) -> bool: return items[a].y < items[b].y)
	mm.instance_count = items.size()
	for n in order.size():
		var i: int = order[n]
		var p := items[i]
		var s := depth_scale(p.y) * (scales[i] if i < scales.size() else 1.0)
		var flip := -1.0 if rng.randf() < 0.5 else 1.0
		var sx := s * rng.randf_range(WIDTH_RANGE.x, WIDTH_RANGE.y) * flip
		var sy := s * rng.randf_range(WIDTH_RANGE.x, WIDTH_RANGE.y)
		var xf := Transform2D(deg_to_rad(rng.randf_range(-ROT_DEG, ROT_DEG)), Vector2(sx, sy), 0.0, p - origin)
		mm.set_instance_transform_2d(n, xf)
		var kind := kinds[i] if i < kinds.size() else MeadowScatter.Kind.CLUMP
		var hk := rng.randf_range(HEIGHT_RANGE.x, HEIGHT_RANGE.y)
		mm.set_instance_color(n, Color(rng.randf(), rng.randf(), float(kind) / 4.0, hk))
		var k := floorf(rng.randf_range(k_range.x, k_range.y + 1.0))
		mm.set_instance_custom_data(n, Color(k, rng.randf_range(amp_range.x, amp_range.y), rng.randf() * TAU,
				rng.randf_range(-LEAN_PX, LEAN_PX)))


## The ground cover (clover, moss mounds, wild flowers) as one MultiMesh node for the meadow layer.
static func build_cover(content: GameContent, feed: PaletteFeed) -> MultiMeshInstance2D:
	var scatter := MeadowScatter.for_content(content)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	var gk: Array = ContentRegistry.motion_tokens()["loops_k"]["grass_sway"]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad_mesh()
	fill(mm, scatter.cover, scatter.cover_kind, Vector2.ZERO, rng, Vector2(float(gk[0]), float(gk[1])), COVER_AMP_PX,
			scatter.cover_scale)
	var node := MultiMeshInstance2D.new()
	node.name = "GroundCover"
	node.multimesh = mm
	node.material = make_material(feed)
	return node


func _build_bands(mesh: ArrayMesh, rng: RandomNumberGenerator, k_range: Vector2) -> void:
	var edges := band_edges()
	for bi in edges.size() - 1:
		var lo := edges[bi]
		var hi := edges[bi + 1]
		var pts := PackedVector2Array()
		for p: Vector2 in positions:
			if p.y >= lo and p.y < hi:
				pts.append(p)
		if pts.is_empty():
			continue
		var origin := Vector2(0.0, lo)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		fill(mm, pts, PackedInt32Array(), origin, rng, k_range, AMP_PX)
		var node := MultiMeshInstance2D.new()
		node.name = "Band%d" % bi
		node.multimesh = mm
		node.material = _mat
		node.position = origin
		add_child(node)
		_bands.append(node)
	FrameGovernor.tier_changed.connect(_apply_tier)
	_apply_tier(FrameGovernor.tier)


## Governor tier 1+: clumps x 0.6 (thin the back-to-front order evenly by stride).
func _apply_tier(tier: int) -> void:
	for b: MultiMeshInstance2D in _bands:
		var n := b.multimesh.instance_count
		b.multimesh.visible_instance_count = n if tier == 0 else roundi(n * TIER1_KEEP)
