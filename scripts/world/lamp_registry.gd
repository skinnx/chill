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
## shaders/inc/lamps.gdshaderinc falloff (keep in sync): ground-plane squash, peak alpha range,
## hot core, breath.
const POOL_SQUASH := 0.70
const PEAK_RANGE := Vector2(0.36, 0.46)
const CORE_Q := 0.16
const CORE_K := 0.22
const PLATEAU := 0.25
## Round 5 radial falloff (lamps.gdshaderinc LAMP_FALLOFF / LAMP_RIM).
const FALLOFF := 1.8
const RIM := 0.65

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


## Pool weight at a design position (0..~0.6 before g_lights), the same falloff as the shader's
## lamp_weight(): the max over lamps of peak * exp(-1.8 q^2) (faded to 0 at the rim) + core,
## q = squashed distance / radius.
static func weight_at(p_design: Vector2) -> float:
	return light_at(p_design).z


## Strongest lamp at a design position: (unit direction from p toward the lamp, weight). Creatures
## use it for i_light (warm fill on the lamp-facing side, round-2 directive 5).
static func light_at(p_design: Vector2) -> Vector3:
	var best := Vector3(0.0, -1.0, 0.0)
	for l: Vector4 in _packed():
		var d := p_design - Vector2(l.x, l.y)
		var q := Vector2(d.x, d.y / POOL_SQUASH).length() / maxf(l.z, 1.0)
		if q >= 1.0:
			continue
		var f := exp(-FALLOFF * q * q) * (1.0 - smoothstep(RIM, 1.0, q))
		var w := lerpf(PEAK_RANGE.x, PEAK_RANGE.y, clampf(l.w, 0.0, 1.0)) * f + CORE_K * exp(-(q * q) / (CORE_Q * CORE_Q))
		if w > best.z:
			var dir := (-d).normalized() if d.length_squared() > 1.0 else Vector2(0.0, -1.0)
			best = Vector3(dir.x, dir.y, w)
	return best


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
