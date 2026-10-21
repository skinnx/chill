class_name PaletteFeed
extends RefCounted
## Feeds palette-derived colour slots (ground_back_lit, grass_tip, water_bank, cloud_lit ...) into
## material uniforms. TimeOfDay already samples every slot of palettes.json in OKLab and applies the
## rain transform (TimeOfDay.colors), so materials get the exact token instead of an sRGB re-mix.
## Pure: the owning node calls [method apply] with TimeOfDay.colors on globals_updated (2 Hz).

var _bindings: Array[Array] = []
var _last: Dictionary = {}


## Binds `uniform` of `mat` to palette slot `slot` (e.g. &"grass_tip").
func bind(mat: ShaderMaterial, uniform: StringName, slot: String) -> void:
	_bindings.append([mat, uniform, slot])


## Pushes every bound slot that changed since the last call.
func apply(colors: Dictionary) -> void:
	for b: Array in _bindings:
		var slot: String = b[2]
		if not colors.has(slot):
			continue
		var c: Color = colors[slot]
		var key := "%d:%s" % [(b[0] as ShaderMaterial).get_instance_id(), b[1]]
		if _last.has(key) and (_last[key] as Color).is_equal_approx(c):
			continue
		_last[key] = c
		(b[0] as ShaderMaterial).set_shader_parameter(b[1] as StringName, c)
