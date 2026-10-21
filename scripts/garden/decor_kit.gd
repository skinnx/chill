class_name DecorKit
extends RefCounted
## Sprite factory for the décor atlas (art/decor/decor_atlas.svg + .json, Art Bible §4.9, §6.6-6.8):
## every décor piece, gift, dew drop and leaf boat is a region of ONE tone-mask atlas drawn with ONE
## shared prop_tone material (so pieces batch wherever y-sort lets them), recoloured from the
## palettes.json material named in the atlas JSON. Sprites are placed by their pivot (the ground
## contact or hanging point) at the node origin, at design px x depth scale.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const ATLAS_JSON := "res://art/decor/decor_atlas.json"
const SHADER_PATH := "res://shaders/props/prop_tone.gdshader"
## prop_tone i_fx: x tap tint, y squash, z rim on, w ground cover.
const FX_REST := Vector4(0.0, 1.0, 1.0, 0.0)

var parts: Dictionary = {}
var layout: Dictionary = {}
var atlas: Texture2D
var material: ShaderMaterial
var atlas_scale: float = 2.0

var _mats: Dictionary = {}
var _atlas_size := Vector2(1024, 512)


func _init(content: GameContent) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_JSON))
	var doc: Dictionary = parsed if parsed is Dictionary else {}
	parts = doc.get("parts", {})
	layout = doc.get("layout", {})
	atlas_scale = float(doc.get("scale", 2.0))
	var size: Array = doc.get("size", [1024, 512])
	_atlas_size = Vector2(float(size[0]), float(size[1]))
	atlas = load(String(doc.get("atlas", "res://art/decor/decor_atlas.svg"))) as Texture2D
	material = ShaderMaterial.new()
	material.shader = load(SHADER_PATH) as Shader
	LampRegistry.bind_material(material)
	_mats = content.palettes.get("materials", {})


func release() -> void:
	LampRegistry.unbind_material(material)


func has_part(id: String) -> bool:
	return parts.has(id)


## Size of a part at depth 1 (design px).
func size_of(id: String) -> Vector2:
	var p: Dictionary = parts.get(id, {})
	var s: Array = p.get("size", [0, 0])
	return Vector2(float(s[0]), float(s[1]))


## Offset from a part's pivot to a point given in its own authored frame (design px, depth 1).
func frame_point(id: String, local: Vector2) -> Vector2:
	var p: Dictionary = parts.get(id, {})
	var pv: Array = p.get("pivot", [0.5, 0.5])
	return local - Vector2(float(pv[0]), float(pv[1])) * size_of(id)


## A Sprite2D of part [param id] whose pivot sits at its origin, at [param depth] x its depth-1 size.
## [param material_id] overrides the part's palettes.json material ("" = the atlas default).
func sprite(id: String, depth: float = 1.0, material_id: String = "", emission: float = -1.0) -> Sprite2D:
	var p: Dictionary = parts.get(id, {})
	var sp := Sprite2D.new()
	if p.is_empty():
		push_warning("DecorKit: unknown part %s" % id)
		return sp
	var r: Array = p["region"]
	var region := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	var pv: Array = p["pivot"]
	sp.texture = atlas
	sp.region_enabled = true
	sp.region_rect = region
	sp.centered = false
	sp.offset = -Vector2(float(pv[0]), float(pv[1])) * region.size
	sp.scale = Vector2.ONE * depth / atlas_scale
	sp.material = material
	var mid := material_id if material_id != "" else String(p.get("material", "stone_cool"))
	var m: Dictionary = _mats.get(mid, {})
	if m.is_empty():
		push_warning("DecorKit: unknown material %s" % mid)
	sp.set_instance_shader_parameter(&"i_lit", Color.html(String(m.get("lit", "#CCCCCC"))))
	sp.set_instance_shader_parameter(&"i_shade", Color.html(String(m.get("shade", "#999999"))))
	var detail := Color.html(String(m.get("detail", "#EEEEEE")))
	detail.a = emission if emission >= 0.0 else float(p.get("emission", 0.0))
	sp.set_instance_shader_parameter(&"i_detail", detail)
	sp.set_instance_shader_parameter(&"i_region", Vector4(region.position.x / _atlas_size.x,
			region.position.y / _atlas_size.y, region.size.x / _atlas_size.x, region.size.y / _atlas_size.y))
	var fx := FX_REST
	fx.z = 1.0 if int(p.get("rim", 0)) > 0 else 0.0
	sp.set_instance_shader_parameter(&"i_fx", fx)
	return sp


## Touch-down feedback on a sprite: i_fx.x tint and i_fx.y squash (prop_tone squashes about the base).
static func set_press(sp: Sprite2D, tint: float, squash: float) -> void:
	var fx: Vector4 = sp.get_instance_shader_parameter(&"i_fx")
	sp.set_instance_shader_parameter(&"i_fx", Vector4(tint, squash, fx.z, fx.w))


## Detail emission (lantern core, candle): i_detail.a, x g_lights in the shader.
static func set_emission(sp: Sprite2D, emission: float) -> void:
	var d: Color = sp.get_instance_shader_parameter(&"i_detail")
	d.a = clampf(emission, 0.0, 1.0)
	sp.set_instance_shader_parameter(&"i_detail", d)
