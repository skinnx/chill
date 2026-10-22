class_name BushLayer
extends Node2D
## The soft hedge and distant tree line hugging the meadow crest (round-2 directive 3, "refuge with
## prospect"): felted shrubs and a few round trees between the mid tree line and the meadow, drawn
## before the meadow so the crest overlaps their feet. Tall on the left (behind the willow) and the
## right (behind the stump), low in the gap where the sun sets (Art Bible §1.2: the sun sits in the
## gap above the crest). shaders/world/bush.gdshader, two MultiMeshes (trees behind, shrubs in
## front). Edge shrubs on the meadow itself are BushSprite nodes in the y-sorted play layer.

const SHADER_PATH := "res://shaders/world/bush.gdshader"
const MOSS_TEX := "res://art/fx/moss_tile.png"
const SEED := 6161
## Quad in canopy units (x half width, top for shrubs / trees, bottom).
const QUAD_HW := 1.15
const SHRUB_TOP := 1.95
const TREE_TOP := 2.9
const QUAD_BOTTOM := 0.12
## Hedge run along the crest (design px) and spacing as a fraction of the radius.
const X_RANGE := Vector2(-380.0, 1460.0)
const SPACING_K := 1.05
const ROOT_BELOW_CREST := 10.0
## Radius (px) by x: the sun gap stays low; (x, radius) knots, linear between them.
const RADIUS_KNOTS: Array[Vector2] = [Vector2(-380, 52), Vector2(150, 50), Vector2(380, 38), Vector2(470, 22),
		Vector2(560, 14), Vector2(650, 20), Vector2(760, 34), Vector2(960, 46), Vector2(1460, 56)]
## Trees: (x, crown radius px, height k).
const TREES: Array[Vector3] = [Vector3(-170, 74, 1.15), Vector3(250, 58, 1.05), Vector3(420, 40, 1.0),
		Vector3(790, 46, 1.1), Vector3(1080, 70, 1.2), Vector3(1290, 64, 1.1)]
const SWAY_K := Vector2(36.0, 52.0)
const SWAY_AMP_PX := 2.0

var _feed := PaletteFeed.new()


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var crest := TerrainMath.sample_meadow(4.0)
	var trees := MultiMesh.new()
	_setup(trees, TREE_TOP)
	trees.instance_count = TREES.size()
	for i in TREES.size():
		var t: Vector3 = TREES[i]
		var root := Vector2(t.x, TerrainMath.crest_at(crest, t.x) + ROOT_BELOW_CREST)
		_place(trees, i, root, t.y, rng, 1.0, t.z, 0.0)
	var shrubs := MultiMesh.new()
	_setup(shrubs, SHRUB_TOP)
	var pts: Array[Vector3] = []
	var x := X_RANGE.x
	while x < X_RANGE.y:
		var r := radius_at(x) * rng.randf_range(0.85, 1.15)
		pts.append(Vector3(x + rng.randf_range(-0.2, 0.2) * r, r, rng.randf_range(0.85, 1.25)))
		x += r * SPACING_K * rng.randf_range(0.8, 1.2)
	shrubs.instance_count = pts.size()
	for i in pts.size():
		var q: Vector3 = pts[i]
		var root := Vector2(q.x, TerrainMath.crest_at(crest, q.x) + ROOT_BELOW_CREST * rng.randf_range(0.6, 1.4))
		_place(shrubs, i, root, q.y, rng, 0.0, q.z, 0.0)
	var mat := make_material(false)
	for mm: MultiMesh in [trees, shrubs]:
		var node := MultiMeshInstance2D.new()
		node.multimesh = mm
		node.material = mat
		add_child(node)


static func radius_at(x: float) -> float:
	for i in RADIUS_KNOTS.size() - 1:
		var a := RADIUS_KNOTS[i]
		var b := RADIUS_KNOTS[i + 1]
		if x <= b.x:
			return lerpf(a.y, b.y, clampf((x - a.x) / (b.x - a.x), 0.0, 1.0))
	return RADIUS_KNOTS[RADIUS_KNOTS.size() - 1].y


## Bush material: shared moss texture, lamps; `sprites` = instance uniforms instead of MultiMesh data.
static func make_material(sprites: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH) as Shader
	mat.set_shader_parameter(&"moss_tex", load(MOSS_TEX) as Texture2D)
	mat.set_shader_parameter(&"use_instance_uniforms", sprites)
	LampRegistry.bind_material(mat)
	return mat


static func quad_mesh(top: float) -> ArrayMesh:
	var verts := PackedVector2Array([Vector2(-QUAD_HW, -top), Vector2(QUAD_HW, -top), Vector2(QUAD_HW, QUAD_BOTTOM),
			Vector2(-QUAD_HW, QUAD_BOTTOM)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _setup(mm: MultiMesh, top: float) -> void:
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad_mesh(top)


func _place(mm: MultiMesh, i: int, root: Vector2, r: float, rng: RandomNumberGenerator, tree: float, hk: float,
		depth: float) -> void:
	var flip := -1.0 if rng.randf() < 0.5 else 1.0
	mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2(r * flip, r), 0.0, root))
	mm.set_instance_color(i, Color(rng.randf(), depth, tree, hk))
	mm.set_instance_custom_data(i, Color(floorf(rng.randf_range(SWAY_K.x, SWAY_K.y + 1.0)), SWAY_AMP_PX,
			rng.randf() * TAU, r))
