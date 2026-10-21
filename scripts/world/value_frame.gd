class_name ValueFrame
extends Node2D
## Value frame (round-3 directive 2): one multiply mesh over the near band and the side wedges of
## the hollow, shaded by shaders/world/value_frame.gdshader. (An additive focal pool was tried and
## dropped: it veiled the creatures, the exact "milky" read QA r2 flagged.) It sits in
## Ground/Particles/Air, so it draws after every Play object and before the additive shafts and
## particles. The mesh only covers where the shader darkens (the focal ellipse is left out),
## keeping the fill to about a third of the screen. Governor tier 1+ drops it with the other
## atmosphere layers (Art Bible §4.19). With --qa-draw-audit it also adds a DrawAudit.

const SHADER_PATH := "res://shaders/world/value_frame.gdshader"
## Design px: the hollow's side wedges (x width, y from..to) and the near band (y from..bottom).
const SIDE_W := 300.0
const SIDE_Y := Vector2(760.0, 1400.0)
const BAND_Y := 1400.0
const BOTTOM_Y := 2040.0
## Bleed past the 1080 px design width for wide screens and the camera drift.
const BLEED_X := 420.0
const DESIGN_W := 1080.0

var _mi: MeshInstance2D


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH) as Shader
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


## Three rects: left wedge, right wedge, near band (design px).
static func rects() -> Array[Rect2]:
	return [
		Rect2(-BLEED_X, SIDE_Y.x, BLEED_X + SIDE_W, SIDE_Y.y - SIDE_Y.x),
		Rect2(DESIGN_W - SIDE_W, SIDE_Y.x, SIDE_W + BLEED_X, SIDE_Y.y - SIDE_Y.x),
		Rect2(-BLEED_X, BAND_Y, DESIGN_W + 2.0 * BLEED_X, BOTTOM_Y - BAND_Y),
	]


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
