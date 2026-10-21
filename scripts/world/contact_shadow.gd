class_name ContactShadow
extends Node2D
## A soft contact + cast shadow at this node's origin (the object's foot), shaded by
## shaders/fx/contact_shadow.gdshader. The rect is fitted to the current cast offset whenever the
## light moves (PropsLayer calls [method set_light] at the TimeOfDay push rate, 2 Hz).

const SHADER_PATH := "res://shaders/fx/contact_shadow.gdshader"
const MARGIN_PX := 40.0
## contact_shadow.gdshader: the cast ellipse's half length = half_h + |offset| * 0.75.
const CAST_LEN_K := 0.75

static var _material: ShaderMaterial = null

var half_size := Vector2(40.0, 10.0)
var height_px: float = 80.0
var alpha_mul: float = 1.0

var _offset := Vector2.ZERO


static func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER_PATH) as Shader
	return _material


func _init(p_half: Vector2 = Vector2(40, 10), p_height: float = 80.0, p_alpha: float = 1.0) -> void:
	half_size = p_half
	height_px = p_height
	alpha_mul = p_alpha
	material = shared_material()


func _ready() -> void:
	set_instance_shader_parameter(&"i_shadow", Vector4(half_size.x, half_size.y, height_px, alpha_mul))


func set_light(values: Dictionary) -> void:
	var off := ShadowMath.cast_offset(values, height_px)
	if off.is_equal_approx(_offset):
		return
	_offset = off
	set_instance_shader_parameter(&"i_cast", Vector4(off.x, off.y, ShadowMath.length_factor(values), 0.0))
	queue_redraw()


## Bounds of the contact ellipse and the cast ellipse (same extents as the shader's), + margin.
func _draw() -> void:
	var ol := _offset.length()
	var u := _offset / ol if ol > 0.5 else Vector2(0, 1)
	var lu := half_size.y + ol * CAST_LEN_K
	var lv := half_size.x
	var ext := Vector2(absf(u.x) * lu + absf(u.y) * lv, absf(u.y) * lu + absf(u.x) * lv)
	var lo := (-half_size).min(_offset - ext) - Vector2(MARGIN_PX, MARGIN_PX)
	var hi := half_size.max(_offset + ext) + Vector2(MARGIN_PX, MARGIN_PX)
	draw_rect(Rect2(lo, hi - lo), Color.WHITE)
