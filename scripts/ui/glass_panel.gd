class_name GlassPanel
extends Control
## A glass surface (Art Bible §4.17, §9.2 C7): an internal ColorRect running glass_faux (HUD
## chips, dock, toasts) or glass_live (the one open sheet), grown on every side so the same draw
## also paints the panel's elevation shadow (e1-e3 in ink; one draw call per surface instead of a
## StyleBoxFlat shadow + an overlay). Children added to the panel draw on top.
##
## Reduce Transparency (X1) turns every glass opaque (fill 1.0) and the live glass into faux; the
## live glass also falls back to faux on a degraded quality tier (FrameGovernor, §4.17 governor).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const FAUX_SHADER := "res://shaders/ui/glass_faux.gdshader"
const LIVE_SHADER := "res://shaders/ui/glass_live.gdshader"
## A radius below 0 means a pill / circle (half the short side).
const PILL := -1.0
## FrameGovernor tier from which live glass is replaced by faux.
const LIVE_MAX_TIER := 0

## Corner radius in px (PILL = h/2).
var radius: float = PILL:
	set(v):
		radius = v
		_refresh_shape()
## Elevation level (UiTokens.E0..E3).
var elevation: int = UiTokens.E2:
	set(v):
		elevation = v
		_refresh_shape()
## Live glass (screen read) instead of faux. Only the open sheet sets this.
var live: bool = false:
	set(v):
		live = v
		_refresh_material()

var _glass: ColorRect
var _mat: ShaderMaterial


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass = ColorRect.new()
	_glass.name = "Glass"
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass.color = Color.WHITE
	add_child(_glass, false, Node.INTERNAL_MODE_FRONT)
	resized.connect(_refresh_shape)


func _ready() -> void:
	_refresh_material()
	Settings.changed.connect(_on_glass_setting)
	FrameGovernor.tier_changed.connect(func(_t: int) -> void: _refresh_material())


## The effective corner radius in px.
func corner_px() -> float:
	return minf(size.x, size.y) * 0.5 if radius < 0.0 else minf(radius, minf(size.x, size.y) * 0.5)


func is_live() -> bool:
	return live and not Settings.get_bool(Settings.REDUCE_TRANSPARENCY) and FrameGovernor.tier <= LIVE_MAX_TIER


func _refresh_material() -> void:
	if _glass == null:
		return
	var want_live := is_live()
	var path := LIVE_SHADER if want_live else FAUX_SHADER
	if _mat == null or _mat.shader == null or _mat.shader.resource_path != path:
		_mat = ShaderMaterial.new()
		_mat.shader = load(path) as Shader
		_glass.material = _mat
	_mat.set_shader_parameter(&"u_surface", UiTokens.color(&"surface"))
	_mat.set_shader_parameter(&"u_rim", UiTokens.color(&"surface_hi"))
	_mat.set_shader_parameter(&"u_ink", UiTokens.color(&"ink"))
	_mat.set_shader_parameter(&"u_rim_tl", UiTokens.alpha(&"rim_top_left"))
	_mat.set_shader_parameter(&"u_rim_br", UiTokens.alpha(&"rim_bottom_right"))
	_mat.set_shader_parameter(&"u_inner_shadow", UiTokens.alpha(&"inner_bottom_shadow"))
	if want_live:
		var ad := UiTokens.alpha_section(&"glass_live_adaptive")
		_mat.set_shader_parameter(&"u_lod", UiTokens.alpha(&"glass_lod"))
		_mat.set_shader_parameter(&"u_saturation", UiTokens.alpha(&"backdrop_saturation"))
		_mat.set_shader_parameter(&"u_tint_min", float(ad.get("min", 0.66)))
		_mat.set_shader_parameter(&"u_tint_max", float(ad.get("max", 0.9)))
		_mat.set_shader_parameter(&"u_luma_lo", float(ad.get("backdrop_luma_lo", 0.05)))
		_mat.set_shader_parameter(&"u_luma_hi", float(ad.get("backdrop_luma_hi", 0.45)))
	else:
		var opaque := Settings.get_bool(Settings.REDUCE_TRANSPARENCY) or live
		_mat.set_shader_parameter(&"u_fill",
				UiTokens.alpha(&"reduce_transparency_fill") if opaque else UiTokens.alpha(&"glass_faux_fill"))
	_refresh_shape()


func _refresh_shape() -> void:
	var r := corner_px()
	var shape := UiTokens.ELEVATION_SHAPE[clampi(elevation, 0, UiTokens.ELEVATION_SHAPE.size() - 1)]
	var margin := ceilf(shape.x + shape.y) if elevation > UiTokens.E0 else 0.0
	_glass.position = -Vector2(margin, margin)
	_glass.size = size + Vector2(margin, margin) * 2.0
	if _mat != null:
		_mat.set_shader_parameter(&"u_size", size)
		_mat.set_shader_parameter(&"u_radius", r)
		_mat.set_shader_parameter(&"u_margin", margin)
		_mat.set_shader_parameter(&"u_shadow_alpha",
				UiTokens.alpha(StringName("shadow_e%d" % elevation)) if elevation > UiTokens.E0 else 0.0)
		_mat.set_shader_parameter(&"u_shadow_blur", shape.x)
		_mat.set_shader_parameter(&"u_shadow_dy", shape.y)


func _on_glass_setting(key: StringName, _value: Variant) -> void:
	if key == Settings.REDUCE_TRANSPARENCY:
		_refresh_material()
