class_name BushSprite
extends Node2D
## One felted shrub standing on the meadow (shaders/world/bush.gdshader with instance uniforms):
## the shrubs hugging the hollow's left/right edges, y-sorted with creatures at their root.

static var _material: ShaderMaterial = null

var radius_px: float = 60.0
var tree: bool = false


static func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = BushLayer.make_material(true)
	return _material


## Root at this node's origin; radius px; seed 0..1; depth 0 (hedge) .. 1 (near shrub); height k.
func setup(radius: float, seed01: float, depth: float, height_k: float, p_tree: bool, sway_k: float,
		phase: float) -> BushSprite:
	radius_px = radius
	tree = p_tree
	material = shared_material()
	set_instance_shader_parameter(&"i_bush", Vector4(seed01, depth, 1.0 if p_tree else 0.0, height_k))
	set_instance_shader_parameter(&"i_sway", Vector4(sway_k, BushLayer.SWAY_AMP_PX * 1.5, phase, radius))
	# The quad is drawn in canopy units; the node's scale turns them into px (y-sort uses position).
	scale = Vector2(radius, radius)
	queue_redraw()
	return self


func _draw() -> void:
	var top := BushLayer.TREE_TOP if tree else BushLayer.SHRUB_TOP
	draw_rect(Rect2(-BushLayer.QUAD_HW, -top, BushLayer.QUAD_HW * 2.0, top + BushLayer.QUAD_BOTTOM), Color.WHITE)
