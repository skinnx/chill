class_name SilhouetteLayer
extends Node2D
## L2 far hills or L3 mid tree line (Art Bible §2.3, §4.4): fBm crest from TerrainMath, an opaque
## interior and a soft feather strip, one mesh drawn with silhouette.gdshader (one draw call; the
## skirt keeps the opaque silhouette_core.gdshader). Built once.

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
## Skirt heights grow in steps of this many px (the mesh is rebuilt only when a taller one is needed).
const SKIRT_STEP_PX := 64.0

@export var kind: Kind = Kind.FAR

## Sampled crest (design px), available after _ready (the sky reads the far crest's lowest point).
var crest := PackedVector2Array()

var _skirt: MeshInstance2D
var _skirt_h: float = 0.0


func _ready() -> void:
	var k := int(kind)
	crest = TerrainMath.sample_far(STEP_PX[k]) if kind == Kind.FAR else TerrainMath.sample_mid(STEP_PX[k])
	var core_mat := _material(CORE_SHADER, k)
	var feather_mat := _material(FEATHER_SHADER, k)
	# interior + feather in one mesh and one draw call (the feather's blend_mix shader)
	var body := MeshInstance2D.new()
	body.name = "Body"
	body.mesh = SilhouetteMesh.body(crest, BOTTOM_Y[k], FEATHER_PX[k])
	body.material = feather_mat
	add_child(body)
	_skirt = MeshInstance2D.new()
	_skirt.name = "Skirt"
	_skirt.material = core_mat
	_skirt.visible = false
	add_child(_skirt)
	add_to_group(&"world_pan_view")


## Map pan (Main, ARCHITECTURE §3.4): when the camera rises, the layer in front slides down faster
## than this one and would show below the body bottom; a skirt in the bottom colour covers
## [param reveal_px] (hidden at rest, so the home view costs nothing).
func on_world_pan(_pan: Vector2, _cam: Vector2, reveal_px: float) -> void:
	var need := reveal_px > 0.5
	_skirt.visible = need
	if not need or reveal_px <= _skirt_h:
		return
	_skirt_h = ceilf(reveal_px / SKIRT_STEP_PX) * SKIRT_STEP_PX
	var bottom := BOTTOM_Y[int(kind)]
	_skirt.mesh = SilhouetteMesh.skirt(crest[0].x, crest[crest.size() - 1].x, bottom - 1.0, bottom + _skirt_h)


func _material(path: String, k: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(path) as Shader
	mat.set_shader_parameter(&"layer", k)
	mat.set_shader_parameter(&"fog_k", FOG_K[k])
	mat.set_shader_parameter(&"veil_k", VEIL_K[k])
	mat.set_shader_parameter(&"crest_rim_px", CREST_RIM_PX)
	mat.set_shader_parameter(&"mottle_k", MID_MOTTLE if kind == Kind.MID else 0.0)
	return mat
