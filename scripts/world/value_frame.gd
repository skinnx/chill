class_name ValueFrame
extends Node2D
## Value frame (round-3 directive 2, round-4 directive 1): one multiply mesh over the play area
## around the focal (a grid with the focal core cut out), shaded by
## shaders/world/value_frame.gdshader. (An additive focal pool was tried and dropped: it veiled the
## creatures, the exact "milky" read QA r2 flagged.) It sits in Ground/Particles/Air, so it draws
## after every Play object and before the additive shafts and particles. The mesh only covers where
## the shader darkens, keeping the fill under half the screen. Governor tier 1+ drops it with the other
## atmosphere layers (Art Bible §4.19). With --qa-draw-audit it also adds a DrawAudit.

const SHADER_PATH := "res://shaders/world/value_frame.gdshader"
## Round 4 (directive 1): the frame now covers the whole play area below the crest as a grid of
## cells with the focal ellipse cut out (cells whose every corner lies inside FOCAL_CLEAR of the
## ellipse are skipped: the shader is exactly 1.0 there). Focal ellipse in design px (spots.json
## sun_stone); the shader receives the same values from here.
const FOCAL := Vector2(540.0, 1150.0)
const FOCAL_RADII := Vector2(380.0, 300.0)
const FOCAL_CLEAR := 0.72
const TOP_Y := 760.0
const BOTTOM_Y := 2040.0
const CELL := 80.0
## The grid spans the layer geometry's x range (TerrainMath.X_MIN .. X_MAX, Art Bible §2.1), so the
## map pan never reaches its edge. Cells keep their CELL alignment to x = 0.

var _mi: MeshInstance2D


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH) as Shader
	mat.set_shader_parameter(&"focal_centre", FOCAL)
	mat.set_shader_parameter(&"focal_radii", FOCAL_RADII)
	_mi = MeshInstance2D.new()
	_mi.name = "ValueFrameMesh"
	_mi.mesh = build_mesh()
	_mi.material = mat
	add_child(_mi)
	LampRegistry.bind_material(mat)
	tree_exiting.connect(func() -> void: LampRegistry.unbind_material(mat))
	FrameGovernor.tier_changed.connect(func(t: int) -> void: visible = t == 0)
	visible = FrameGovernor.tier == 0
	if DrawAudit.requested():
		add_child(DrawAudit.new())


## The frame's cells (design px): every CELL square of the play area that is not entirely inside
## the clear core of the focal ellipse.
static func rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var x0 := floorf(TerrainMath.X_MIN / CELL) * CELL
	var y := TOP_Y
	while y < BOTTOM_Y:
		var x := x0
		while x < TerrainMath.X_MAX:
			var r := Rect2(x, y, CELL, CELL)
			if not _inside_focal(r):
				out.append(r)
			x += CELL
		y += CELL
	return out


static func _inside_focal(r: Rect2) -> bool:
	for p: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		if ((p - FOCAL) / FOCAL_RADII).length() >= FOCAL_CLEAR:
			return false
	return true


static func build_mesh() -> ArrayMesh:
	var verts := PackedVector2Array()
	var idx := PackedInt32Array()
	for r: Rect2 in rects():
		var k := verts.size()
		verts.append_array(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
				Vector2(r.position.x, r.end.y)]))
		idx.append_array(PackedInt32Array([k, k + 1, k + 2, k, k + 2, k + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
