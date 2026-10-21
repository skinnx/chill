class_name ItemPreview
extends Control
## Live mini-renders for the UI (Art Bible §9.4 Garden item card "live mini-render well", Basket
## tiles, the dew cup): the real flower (FloraBuilder + flora_bed, a small bloom cluster), décor
## piece, gift or leaf boat (DecorKit + prop_tone), drawn by the same shaders and atlases as the
## hollow and fitted into the control's rect. No screenshots, no SubViewport. One shared builder,
## kit and material for every preview, so they batch with each other.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const FLORA_SHADER := "res://shaders/flora/flora_bed.gdshader"
## Fraction of the well the render may fill.
const FILL := 0.8
## A preview flower is a small cluster: three stems at these offsets (px at depth 1) and depths.
const CLUSTER: Array[Vector3] = [Vector3(-30, 6, 0.86), Vector3(30, 10, 0.9), Vector3(0, 16, 1.0)]
## Décor pieces as [part, x, y] at depth 1 (y up is negative), from decor_atlas.json layout.
const DECOR_PARTS := {
	&"leaf_pinwheel": [["pinwheel_stick", 0, 0], ["pinwheel_a", 0, -86], ["pinwheel_b", 0, -86]],
	&"pebble_cairn": [["pebble_0", 0, 0], ["pebble_1", 2, -22], ["pebble_2", -2, -40], ["pebble_3", 1, -55]],
	&"toadstool_seat": [["toadstool_stem", 0, 0], ["toadstool_cap", 0, -20]],
	&"stream_stones": [["stream_stone", -34, 4], ["stream_stone", 30, 0]],
	&"firefly_lantern": [["lantern_crook", 0, 0], ["lantern_jar", 30, -100], ["lantern_core", 30, -86]],
	&"wind_chime": [["chime_paper", 0, 0], ["chime_mid", -14, 18], ["chime_long", 2, 22], ["chime_short", 18, 16]],
}
const GIFT_PREFIX := "gift_"

static var _builder: FloraBuilder
static var _flora_mat: ShaderMaterial
static var _flora_atlas: Texture2D
static var _kit: DecorKit

var _stage: Node2D
var _bounds := Rect2()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	_stage = Node2D.new()
	_stage.name = "Stage"
	add_child(_stage)
	resized.connect(_fit)


## Shows [param item] (a flower or décor id from the content, "leaf_boat", "dew_drop" or a gift
## item id such as "acorn_cup").
func show_item(item: StringName) -> void:
	for c: Node in _stage.get_children():
		c.queue_free()
	var content := ContentRegistry.content
	if content.flowers_by_id.has(item):
		_build_flower(item)
	elif DECOR_PARTS.has(item):
		for p: Array in DECOR_PARTS[item]:
			_add_part(String(p[0]), Vector2(float(p[1]), float(p[2])))
	elif _kit_has(GIFT_PREFIX + String(item)):
		_add_part(GIFT_PREFIX + String(item), Vector2.ZERO)
	elif _kit_has(String(item)):
		_add_part(String(item), Vector2.ZERO)
	_fit()


func _build_flower(item: StringName) -> void:
	_ensure_flora()
	var content := ContentRegistry.content
	var f: Dictionary = content.flowers_by_id.get(item, {})
	var stems: Array[FloraBuilder.Stem] = []
	for i in CLUSTER.size():
		var c: Vector3 = CLUSTER[i]
		var st := FloraBuilder.Stem.new()
		st.flower = item
		st.form = String(f.get("form", "globe"))
		st.row = FloraBuilder.row_of(content, item)
		st.root = Vector2(c.x, c.y)
		st.depth = c.z
		st.seed = FloraBuilder.stem_seed(&"ui_preview", i, item)
		st.stage = WorldSim.STAGE_BLOOM
		st.growth = 1.0
		st.open = 1.0
		stems.append(st)
	var mi := MeshInstance2D.new()
	mi.texture = _flora_atlas
	mi.material = _flora_mat
	mi.mesh = _builder.build_mesh(stems)
	_stage.add_child(mi)
	var aabb := mi.mesh.get_aabb()
	_bounds = Rect2(aabb.position.x, aabb.position.y, aabb.size.x, aabb.size.y)


func _add_part(part: String, at: Vector2) -> void:
	_ensure_kit()
	var sp := _kit.sprite(part)
	sp.position = at
	_stage.add_child(sp)
	var r := Rect2(sp.offset * sp.scale + at, sp.region_rect.size * sp.scale)
	_bounds = r if _stage.get_child_count() == 1 else _bounds.merge(r)


func _fit() -> void:
	if _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		return
	var k := minf(size.x * FILL / _bounds.size.x, size.y * FILL / _bounds.size.y)
	_stage.scale = Vector2(k, k)
	_stage.position = size * 0.5 - _bounds.get_center() * k


static func _kit_has(part: String) -> bool:
	_ensure_kit()
	return _kit.has_part(part)


static func _ensure_kit() -> void:
	if _kit == null:
		_kit = DecorKit.new(ContentRegistry.content)


static func _ensure_flora() -> void:
	if _builder != null:
		return
	var doc := FloraBuilder.load_doc()
	_builder = FloraBuilder.new(doc, ContentRegistry.motion_tokens())
	_flora_atlas = load(String(doc.get("atlas", "res://art/flora/flora_atlas.svg"))) as Texture2D
	_flora_mat = ShaderMaterial.new()
	_flora_mat.shader = load(FLORA_SHADER) as Shader
	_flora_mat.set_shader_parameter(&"flora_lut",
			ImageTexture.create_from_image(FloraBuilder.build_lut(ContentRegistry.content)))
	_flora_mat.set_shader_parameter(&"atlas_scale", float(doc.get("scale", 2.0)))
