class_name SkyQuad
extends Node2D
## L0 sky (Art Bible §4.3): one opaque rect from the visible top of the viewport down to just
## below the far crest, shaded by shaders/world/sky.gdshader. The 3-stop OKLab gradient lives in a
## GradientTexture1D that is rebuilt only when TimeOfDay's sky colours change (2 Hz at most).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const SHADER_PATH := "res://shaders/world/sky.gdshader"
## Art Bible §4.3: sky_top at 0, sky_mid at 0.42, sky_horizon at 1.0; 256 texels.
const MID_OFFSET := 0.42
const TEX_WIDTH := 256
## Side bleed beyond the visible rect (camera drift, intro zoom).
const BLEED_PX := 160.0
## The sky ends this far below the highest far-crest point that can show through (§4.3: + 12).
const BELOW_CREST_PX := 12.0

## Design y where the sky stops (set by the layer builder from the far crest).
var bottom_y: float = 700.0

var _gradient := Gradient.new()
var _feed := PaletteFeed.new()
var _texture := GradientTexture1D.new()
var _last := PackedColorArray()


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH) as Shader
	_gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	_gradient.interpolation_color_space = Gradient.GRADIENT_COLOR_SPACE_OKLAB
	_gradient.offsets = PackedFloat32Array([0.0, MID_OFFSET, 1.0])
	_texture.width = TEX_WIDTH
	_texture.gradient = _gradient
	mat.set_shader_parameter(&"sky_tex", _texture)
	var cel: Dictionary = ContentRegistry.palettes()["tod"]["celestial"]
	mat.set_shader_parameter(&"horizon_y", float(cel["horizon_y"]))
	mat.set_shader_parameter(&"sun_disc_px", float(cel["disc_px"]["sun"]))
	mat.set_shader_parameter(&"moon_disc_px", float(cel["disc_px"]["moon"]))
	mat.set_shader_parameter(&"moon_color", Color.html(String(cel["moon_color"])))
	mat.set_shader_parameter(&"moon_maria", Color.html(String(cel["moon_maria"])))
	mat.set_shader_parameter(&"star_color", Color.html(String(cel["star"])))
	var k: Array = ContentRegistry.motion_tokens()["loops_k"]["star_twinkle"]
	mat.set_shader_parameter(&"star_k_range", Vector2(float(k[0]), float(k[1])))
	material = mat
	_feed.bind(mat, &"cloud_lit", "cloud_lit")
	_feed.bind(mat, &"cloud_shade", "cloud_shade")
	set_bottom(TerrainMath.y_range(TerrainMath.sample_far(SilhouetteLayer.STEP_PX[0])).y)
	_apply_colors(TimeOfDay.colors)
	TimeOfDay.globals_updated.connect(func(_v: Dictionary) -> void: _apply_colors(TimeOfDay.colors))
	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	var vis := get_viewport_rect().size
	var off := TimeOfDay.world_offset
	var top := -off.y - BLEED_PX
	var left := -off.x - BLEED_PX
	draw_rect(Rect2(left, top, vis.x + 2.0 * BLEED_PX, bottom_y - top), Color.WHITE)


## [param far_crest_low_y] = the largest y of the far crest (its lowest dip): the sky must reach it.
func set_bottom(far_crest_low_y: float) -> void:
	bottom_y = far_crest_low_y + BELOW_CREST_PX
	queue_redraw()


func _apply_colors(colors: Dictionary) -> void:
	if not (colors.has("sky_top") and colors.has("sky_mid") and colors.has("sky_horizon")):
		return
	_feed.apply(colors)
	var c := PackedColorArray([colors["sky_top"], colors["sky_mid"], colors["sky_horizon"]])
	if c == _last:
		return
	_last = c
	_gradient.colors = c
