class_name ShaftController
extends Node2D
## Light shafts in the hollow's air (Art Bible §4.14, §8.1): 3 slanting shafts by day, 4 radiating
## from the low sun at golden hour (fanning +-25 deg toward the viewer), 3 dappled shafts through
## the willow at dawn; none at dusk / night / in rain. One additive mesh, rebuilt only when the sun
## moves more than 20 px or the phase changes; hidden when its strength is ~0 (no fill cost).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## The shaft set changed (the dust mask follows it).
signal rebuilt

const SHADER_PATH := "res://shaders/fx/light_shaft.gdshader"
const REBUILD_PX := 20.0
const MIN_STRENGTH := 0.01
## Aim point of the fans: the focal sun stone (spots.json), Art Bible §2.5 light axis.
const FOCAL := Vector2(540.0, 1123.0)
## Per phase: [count, fan half-angle deg, start offset px, length px, width near px, width far px,
## dapple, alpha scale]. Round 3: day shafts are quieter (QA r2: a milky veil over the stone), golden
## shafts carry the signature backlit air through the willow / stump gap.
const PLANS := {
	&"day": [3, 14.0, 120.0, 1000.0, Vector2(90, 160), Vector2(200, 260), 0.0, 0.4],
	&"golden": [4, 25.0, 70.0, 820.0, Vector2(50, 70), Vector2(170, 230), 0.0, 1.3],
	&"dawn": [3, 18.0, 100.0, 950.0, Vector2(80, 120), Vector2(200, 240), 1.0, 1.1],
}
const ALPHA_RANGE := Vector2(0.07, 0.10)
const SEGMENTS := 8

## Shaft geometry for the dust mask: (origin x, y, angle rad, length) in design px.
var shafts: Array[Vector4] = []
var shaft_width := Vector2(100.0, 230.0)

var _mesh_node := MeshInstance2D.new()
var _built_sun := Vector2(INF, INF)
var _built_phase: StringName = &""
var _k_range := Vector2(50.0, 72.0)


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH) as Shader
	_mesh_node.material = mat
	_mesh_node.name = "Shafts"
	add_child(_mesh_node)
	var k: Array = ContentRegistry.motion_tokens()["loops_k"]["light_shaft_sway"]
	_k_range = Vector2(float(k[0]), float(k[1]))
	TimeOfDay.globals_updated.connect(_on_globals)
	FrameGovernor.tier_changed.connect(func(_t: int) -> void: _on_globals(PropsLayer.current_light()))
	_on_globals(PropsLayer.current_light())


func _on_globals(values: Dictionary) -> void:
	if values.is_empty():
		return
	var strength := float(values.get(&"g_shafts", 0.0)) * (1.0 - float(values.get(&"g_rain", 0.0)))
	var cel: Vector2 = values.get(&"g_celestial", Vector2.ZERO)
	# Governor tier 1+ drops the shafts (Art Bible §4.19 mitigation).
	visible = strength * cel.x > MIN_STRENGTH and FrameGovernor.tier == 0
	if not visible:
		return
	var off: Vector2 = values.get(&"g_world_offset", TimeOfDay.world_offset)
	var sun: Vector2 = (values.get(&"g_sun_pos", Vector2.ZERO) as Vector2) - off
	var phase := _plan_for(float(values.get(&"g_day", 0.4)))
	if phase == _built_phase and sun.distance_to(_built_sun) < REBUILD_PX:
		return
	_built_phase = phase
	_built_sun = sun
	_rebuild(sun, PLANS[phase])


## Nearest shaft plan for the palette key (dawn 0.2, day 0.4, golden 0.6).
static func _plan_for(g_day: float) -> StringName:
	if g_day < 0.3:
		return &"dawn"
	if g_day < 0.5:
		return &"day"
	return &"golden"


func _rebuild(sun: Vector2, plan: Array) -> void:
	var count := int(plan[0])
	var fan := deg_to_rad(float(plan[1]))
	var start := float(plan[2])
	var length := float(plan[3])
	var w0: Vector2 = plan[4]
	var w1: Vector2 = plan[5]
	var dapple := float(plan[6])
	var alpha_k := float(plan[7])
	var base := (FOCAL - sun).angle()
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	shafts.clear()
	shaft_width = Vector2((w0.x + w0.y) * 0.5, (w1.x + w1.y) * 0.5)
	for i in count:
		var u := (float(i) / maxf(count - 1, 1) - 0.5) * 2.0
		var a := base + u * fan + (TerrainMath.hash01(i, 71) - 0.5) * 0.08
		var dir := Vector2.from_angle(a)
		var n := Vector2(-dir.y, dir.x)
		var near := lerpf(w0.x, w0.y, TerrainMath.hash01(i, 72)) * 0.5
		var far := lerpf(w1.x, w1.y, TerrainMath.hash01(i, 73)) * 0.5
		var ln := length * lerpf(0.85, 1.05, TerrainMath.hash01(i, 74))
		var p0 := sun + dir * start
		var p1 := sun + dir * (start + ln)
		var alpha := lerpf(ALPHA_RANGE.x, ALPHA_RANGE.y, TerrainMath.hash01(i, 75)) * alpha_k
		var k := floorf(lerpf(_k_range.x, _k_range.y + 1.0, TerrainMath.hash01(i, 76)))
		var col := Color(alpha, dapple, TerrainMath.hash01(i, 77), k / 100.0)
		# Subdivided along the length so UV.x stays smooth across the trapezoid (no diagonal seam).
		var b := verts.size()
		for s in SEGMENTS + 1:
			var t := float(s) / SEGMENTS
			var c := p0.lerp(p1, t)
			var hw := lerpf(near, far, t)
			verts.append_array(PackedVector2Array([c - n * hw, c + n * hw]))
			uvs.append_array(PackedVector2Array([Vector2(0, t), Vector2(1, t)]))
			cols.append(col)
			cols.append(col)
		for s in SEGMENTS:
			var q := b + s * 2
			idx.append_array(PackedInt32Array([q, q + 2, q + 1, q + 1, q + 2, q + 3]))
		shafts.append(Vector4(p0.x, p0.y, a, ln))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_node.mesh = mesh
	rebuilt.emit()
