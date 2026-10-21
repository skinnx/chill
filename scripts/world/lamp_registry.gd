class_name LampRegistry
extends RefCounted
## Warm local lights of the hollow (Art Bible §4.1 u_lamps, §8.3): firefly lanterns (décor owner),
## the glow-mushroom cluster at the sun stone (always present), leaf-boat candles. Every material
## that includes shaders/inc/lamps.gdshaderinc binds here and receives u_lamps / u_lamp_count only
## when a lamp changes. Positions are DESIGN px of the 1080x1920 frame (not canvas px).
##
##   LampRegistry.set_lamp(&"lantern_3", Vector2(767, 1394), 150.0, 1.0)
##   LampRegistry.remove_lamp(&"lantern_3")

const MAX_LAMPS := 12

static var _lamps: Dictionary = {}
static var _materials: Array[ShaderMaterial] = []


## Adds or moves a lamp: design px position, pool radius px, intensity 0..1 (pool alpha 0.25..0.40).
static func set_lamp(key: StringName, pos_design: Vector2, radius_px: float, intensity: float) -> void:
	var v := Vector4(pos_design.x, pos_design.y, radius_px, clampf(intensity, 0.0, 1.0))
	if _lamps.get(key) == v:
		return
	_lamps[key] = v
	_push()


static func remove_lamp(key: StringName) -> void:
	if _lamps.erase(key):
		_push()


## Active lamps (design x, y, radius, intensity) in their stable shader order.
static func lamps() -> Array[Vector4]:
	return _packed()


static func lamp_count() -> int:
	return mini(_lamps.size(), MAX_LAMPS)


static func bind_material(mat: ShaderMaterial) -> void:
	if mat != null and not _materials.has(mat):
		_materials.append(mat)
		_push_one(mat, _packed())


static func unbind_material(mat: ShaderMaterial) -> void:
	_materials.erase(mat)


## Tests and scene teardown.
static func clear() -> void:
	_lamps.clear()
	_materials.clear()


static func _packed() -> Array[Vector4]:
	var out: Array[Vector4] = []
	var keys := _lamps.keys()
	# Stable order (deterministic breath phases). StringNames compare by identity, so sort as text.
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	for k: Variant in keys:
		if out.size() >= MAX_LAMPS:
			break
		out.append(_lamps[k] as Vector4)
	return out


static func _push() -> void:
	var packed := _packed()
	for m: ShaderMaterial in _materials:
		_push_one(m, packed)


static func _push_one(mat: ShaderMaterial, packed: Array[Vector4]) -> void:
	var arr := PackedVector4Array()
	arr.resize(MAX_LAMPS)
	for i in packed.size():
		arr[i] = packed[i]
	mat.set_shader_parameter(&"u_lamps", arr)
	mat.set_shader_parameter(&"u_lamp_count", packed.size())
