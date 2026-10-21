class_name DecorKit
extends RefCounted
## Sprite and stamp factory for the décor atlas (art/decor/decor_atlas.svg + .json, Art Bible §4.9, §6.6-6.8):
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
## World décor stamps: one MeshInstance2D per piece / static group, per-quad data in the vertices
## (shaders/flora/decor_stamp.gdshader). No Sprite2D-per-part: each instance-uniform item takes
## 16 of the 4096 uniform-buffer entries, and a full garden's sprites overflowed it (round 3).
const STAMP_SHADER_PATH := "res://shaders/flora/decor_stamp.gdshader"
const STAMP_LUT_ROWS := 4
## decor_stamp CUSTOM1.w: quads that turn about i_head (pinwheel blades, lantern jar).
const GROUP_STATIC := 0
const GROUP_HEAD := 1
## decor_stamp CUSTOM1.w = GROUP_TUBE + n: chime tube n swings about i_tube<n> (n < MAX_TUBES).
const GROUP_TUBE := 2
const MAX_TUBES := 10
const TUBE_PARAMS: Array[StringName] = [&"i_tube0", &"i_tube1", &"i_tube2", &"i_tube3", &"i_tube4", &"i_tube5",
	&"i_tube6", &"i_tube7", &"i_tube8", &"i_tube9"]
## prop_tone i_fx: x tap tint, y squash, z rim on, w ground cover.
const FX_REST := Vector4(0.0, 1.0, 1.0, 0.0)
## Round 5 (plush play-set): how much of the stuffed-felt look (inflation shading, pile, fuzzy
## edge) each décor material takes in decor_stamp.gdshader. Everything is felt / minky by default;
## glass, the lantern light and the glazed chime tubes stay smooth and crisp.
const PLUSH_DEFAULT := 1.0
const PLUSH_BY_MATERIAL: Dictionary = {
	"lantern_jar": 0.2,
	"lantern_light": 0.0,
	"chime_ceramic": 0.4,
}

var parts: Dictionary = {}
var layout: Dictionary = {}
var atlas: Texture2D
var material: ShaderMaterial
var atlas_scale: float = 2.0

## The shared decor_stamp material (every stamp of this kit batches state with it).
var stamp_material: ShaderMaterial

var _mats: Dictionary = {}
var _mat_index: Dictionary = {}      # material id -> decor_lut column
var _atlas_size := Vector2(1024, 512)


## Quads waiting to become one stamp mesh ([method add_quad], [method commit]).
class Quads:
	extends RefCounted
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var idx := PackedInt32Array()

	func is_empty() -> bool:
		return verts.is_empty()


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
	stamp_material = ShaderMaterial.new()
	stamp_material.shader = load(STAMP_SHADER_PATH) as Shader
	stamp_material.set_shader_parameter(&"decor_lut", ImageTexture.create_from_image(_build_lut()))
	LampRegistry.bind_material(stamp_material)


func release() -> void:
	LampRegistry.unbind_material(material)
	LampRegistry.unbind_material(stamp_material)


## decor_lut: row 0 r = plush amount (PLUSH_BY_MATERIAL), rows 1-3 = material lit / shade / detail
## by column.
func _build_lut() -> Image:
	var ids: Array = _mats.keys()
	ids.sort()
	var img := Image.create_empty(maxi(1, ids.size()), STAMP_LUT_ROWS, false, Image.FORMAT_RGBAF)
	for j in ids.size():
		_mat_index[String(ids[j])] = j
		var m: Dictionary = _mats[ids[j]]
		var plush := float(PLUSH_BY_MATERIAL.get(String(ids[j]), PLUSH_DEFAULT))
		img.set_pixel(j, 0, Color(plush, 0.0, 0.0, 1.0))
		img.set_pixel(j, 1, Color.html(String(m.get("lit", "#CCCCCC"))))
		img.set_pixel(j, 2, Color.html(String(m.get("shade", "#999999"))))
		img.set_pixel(j, 3, Color.html(String(m.get("detail", "#EEEEEE"))))
	return img


## Appends part [param id] to [param q] like [method sprite] would place it: its pivot at
## [param pos] (stamp-local px), [param depth] x its depth-1 size, turned by [param rot].
## [param group] GROUP_HEAD quads turn about the stamp's i_head pivot.
func add_quad(q: Quads, id: String, pos: Vector2, depth: float = 1.0, rot: float = 0.0, material_id: String = "",
		emission: float = -1.0, group: int = GROUP_STATIC) -> void:
	var p: Dictionary = parts.get(id, {})
	if p.is_empty():
		push_warning("DecorKit: unknown part %s" % id)
		return
	var r: Array = p["region"]
	var region := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	var pv: Array = p["pivot"]
	var pivot := Vector2(float(pv[0]), float(pv[1]))
	var k := depth / atlas_scale
	var mid := material_id if material_id != "" else String(p.get("material", "stone_cool"))
	if not _mat_index.has(mid):
		push_warning("DecorKit: unknown material %s" % mid)
	var em := emission if emission >= 0.0 else float(p.get("emission", 0.0))
	var rim := 1.0 if int(p.get("rim", 0)) > 0 else 0.0
	var base := q.verts.size()
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		var local := (corner - pivot) * region.size * k
		q.verts.append(pos + local.rotated(rot))
		q.uvs.append((region.position + corner * region.size) / _atlas_size)
		q.c0.append_array([corner.x, corner.y, region.size.x, region.size.y])
		q.c1.append_array([float(_mat_index.get(mid, 0)), em, rim, float(group)])
	q.idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


## The mesh of [param q] (null when empty).
static func build_mesh(q: Quads) -> ArrayMesh:
	if q.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = q.verts
	arrays[Mesh.ARRAY_TEX_UV] = q.uvs
	arrays[Mesh.ARRAY_CUSTOM0] = q.c0
	arrays[Mesh.ARRAY_CUSTOM1] = q.c1
	arrays[Mesh.ARRAY_INDEX] = q.idx
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
	return mesh


## A new stamp node drawing [param q] (or an empty one to fill later with [method build_mesh]).
func stamp(q: Quads = null) -> MeshInstance2D:
	var mi := MeshInstance2D.new()
	mi.texture = atlas
	mi.material = stamp_material
	if q != null:
		mi.mesh = build_mesh(q)
	return mi


## Touch-down feedback and lantern brighten on a stamp: tint, squash about the foot, emission k.
static func set_stamp_fx(mi: MeshInstance2D, tint: float, squash: float, emission_k: float = 1.0) -> void:
	mi.set_instance_shader_parameter(&"i_fx", Vector4(tint, squash, emission_k, 0.0))


## Swings chime tube [param n] (GROUP_TUBE + n quads) by [param angle] about [param pivot].
static func set_stamp_tube(mi: MeshInstance2D, n: int, pivot: Vector2, angle: float) -> void:
	if n >= 0 and n < MAX_TUBES:
		mi.set_instance_shader_parameter(TUBE_PARAMS[n], Vector4(pivot.x, pivot.y, angle, 0.0))


## Turns the stamp's GROUP_HEAD quads by [param angle] about [param pivot] (stamp-local px).
static func set_stamp_head(mi: MeshInstance2D, pivot: Vector2, angle: float) -> void:
	mi.set_instance_shader_parameter(&"i_head", Vector4(pivot.x, pivot.y, angle, 0.0))


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
