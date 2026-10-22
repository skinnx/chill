class_name SilhouetteLayer
extends Node2D
## L2 far hills or L3 mid tree line (Art Bible §2.3, §4.4): fBm crest from TerrainMath, an opaque
## interior (silhouette_core.gdshader) and a soft feather strip (silhouette.gdshader). Built once.

enum Kind { FAR, MID }

const CORE_SHADER := "res://shaders/world/silhouette_core.gdshader"
const FEATHER_SHADER := "res://shaders/world/silhouette.gdshader"
## Art Bible §4.4: vertex every 6 px (far) / 4 px (mid); feather 6 / 3 px; body bottoms 790 / 800.
const STEP_PX: Array[float] = [6.0, 4.0]
const FEATHER_PX: Array[float] = [6.0, 3.0]
const BOTTOM_Y: Array[float] = [790.0, 800.0]
## Valley fog toward sky_horizon (palettes.json derived far_haze 0.30, mid_haze 0.15); veil 1.0 / 0.6.
const FOG_K: Array[float] = [0.30, 0.15]
const VEIL_K: Array[float] = [1.0, 0.6]
const CREST_RIM_PX := 3.0
const MID_MOTTLE := 0.035

@export var kind: Kind = Kind.FAR

## Sampled crest (design px), available after _ready (the sky reads the far crest's lowest point).
var crest := PackedVector2Array()


func _ready() -> void:
	var k := int(kind)
	crest = TerrainMath.sample_far(STEP_PX[k]) if kind == Kind.FAR else TerrainMath.sample_mid(STEP_PX[k])
	var core_mat := _material(CORE_SHADER, k)
	var feather_mat := _material(FEATHER_SHADER, k)
	var core := MeshInstance2D.new()
	core.name = "Core"
	core.mesh = SilhouetteMesh.core(crest, BOTTOM_Y[k])
	core.material = core_mat
	add_child(core)
	var edge := MeshInstance2D.new()
	edge.name = "Feather"
	edge.mesh = SilhouetteMesh.feather(crest, FEATHER_PX[k])
	edge.material = feather_mat
	add_child(edge)


func _material(path: String, k: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(path) as Shader
	mat.set_shader_parameter(&"layer", k)
	mat.set_shader_parameter(&"fog_k", FOG_K[k])
	mat.set_shader_parameter(&"veil_k", VEIL_K[k])
	mat.set_shader_parameter(&"crest_rim_px", CREST_RIM_PX)
	mat.set_shader_parameter(&"mottle_k", MID_MOTTLE if kind == Kind.MID else 0.0)
	return mat
