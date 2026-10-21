class_name HaloSprite
extends Node2D
## One additive halo quad (shaders/fx/halo_add.gdshader) centred on this node. Shared material;
## everything per halo is an instance uniform, so halos batch.

const SHADER_PATH := "res://shaders/fx/halo_add.gdshader"
## i_halo.w flags.
const FLAG_NIGHT := 1.0
const FLAG_ACCENT := 2.0

static var _material: ShaderMaterial = null

var radius_px: float = 60.0


static func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER_PATH) as Shader
	return _material


## r0 = falloff radius, quad = outer radius (px); colour alpha = strength; flags as above.
func setup(r0: float, quad: float, color: Color, breath_k: float, flags: float, phase: float = 0.0) -> HaloSprite:
	radius_px = quad
	material = shared_material()
	set_instance_shader_parameter(&"i_color", color)
	set_instance_shader_parameter(&"i_halo", Vector4(r0, quad, breath_k, flags))
	set_instance_shader_parameter(&"i_phase", phase)
	queue_redraw()
	return self


func _draw() -> void:
	draw_rect(Rect2(-radius_px, -radius_px, radius_px * 2.0, radius_px * 2.0), Color.WHITE)
