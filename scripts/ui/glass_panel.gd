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

## Shared faux materials by "elevation|radius|fill".
static var _faux_shared: Dictionary = {}

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
	if is_live():
		if _mat == null or _shared_key(_mat) != "":
			_mat = ShaderMaterial.new()
			_mat.shader = load(LIVE_SHADER) as Shader
			_apply_common(_mat)
			var ad := UiTokens.alpha_section(&"glass_live_adaptive")
			_mat.set_shader_parameter(&"u_lod", UiTokens.alpha(&"glass_lod"))
			_mat.set_shader_parameter(&"u_saturation", UiTokens.alpha(&"backdrop_saturation"))
			_mat.set_shader_parameter(&"u_tint_min", float(ad.get("min", 0.66)))
			_mat.set_shader_parameter(&"u_tint_max", float(ad.get("max", 0.9)))
			_mat.set_shader_parameter(&"u_luma_lo", float(ad.get("backdrop_luma_lo", 0.05)))
			_mat.set_shader_parameter(&"u_luma_hi", float(ad.get("backdrop_luma_hi", 0.45)))
		_glass.material = _mat
	_refresh_shape()


## The faux-glass material shared by every surface with the same elevation, radius rule and fill
## (the shader derives each surface's size from its own quad), so consecutive faux surfaces
## batch: the HUD chips and the dock pill draw in one call (Art Bible §4.19 budget).
static func _faux_material(level: int, radius_px: float, fill: float) -> ShaderMaterial:
	var key := "%d|%.1f|%.3f" % [level, radius_px, fill]
	var hit: Variant = _faux_shared.get(key)
	if hit is ShaderMaterial:
		return hit as ShaderMaterial
	var m := ShaderMaterial.new()
	m.shader = load(FAUX_SHADER) as Shader
	m.set_meta(&"glass_key", key)
	_apply_common(m)
	var shape := UiTokens.ELEVATION_SHAPE[clampi(level, 0, UiTokens.ELEVATION_SHAPE.size() - 1)]
	m.set_shader_parameter(&"u_margin", _margin_of(level))
	m.set_shader_parameter(&"u_shadow_alpha",
			UiTokens.alpha(StringName("shadow_e%d" % level)) if level > UiTokens.E0 else 0.0)
	m.set_shader_parameter(&"u_shadow_blur", shape.x)
	m.set_shader_parameter(&"u_shadow_dy", shape.y)
	m.set_shader_parameter(&"u_radius", radius_px)
	m.set_shader_parameter(&"u_fill", fill)
	_faux_shared[key] = m
	return m


static func _shared_key(m: ShaderMaterial) -> String:
	return String(m.get_meta(&"glass_key", ""))


static func _margin_of(level: int) -> float:
	var shape := UiTokens.ELEVATION_SHAPE[clampi(level, 0, UiTokens.ELEVATION_SHAPE.size() - 1)]
	return ceilf(shape.x + shape.y) if level > UiTokens.E0 else 0.0


static func _apply_common(m: ShaderMaterial) -> void:
	m.set_shader_parameter(&"u_surface", UiTokens.color(&"surface"))
	m.set_shader_parameter(&"u_rim", UiTokens.color(&"surface_hi"))
	m.set_shader_parameter(&"u_ink", UiTokens.color(&"ink"))
	m.set_shader_parameter(&"u_rim_tl", UiTokens.alpha(&"rim_top_left"))
	m.set_shader_parameter(&"u_rim_br", UiTokens.alpha(&"rim_bottom_right"))
	m.set_shader_parameter(&"u_inner_shadow", UiTokens.alpha(&"inner_bottom_shadow"))


## Releases the shared faux materials (HUD exit).
static func release_shared() -> void:
	_faux_shared = {}


func _refresh_shape() -> void:
	var margin := _margin_of(elevation)
	_glass.position = -Vector2(margin, margin)
	_glass.size = size + Vector2(margin, margin) * 2.0
	if is_live():
		if _mat != null:
			var shape := UiTokens.ELEVATION_SHAPE[clampi(elevation, 0, UiTokens.ELEVATION_SHAPE.size() - 1)]
			_mat.set_shader_parameter(&"u_size", size)
			_mat.set_shader_parameter(&"u_radius", corner_px())
			_mat.set_shader_parameter(&"u_margin", margin)
			_mat.set_shader_parameter(&"u_shadow_alpha",
					UiTokens.alpha(StringName("shadow_e%d" % elevation)) if elevation > UiTokens.E0 else 0.0)
			_mat.set_shader_parameter(&"u_shadow_blur", shape.x)
			_mat.set_shader_parameter(&"u_shadow_dy", shape.y)
		return
	# faux: the radius rule (pill, or a fixed px radius) and the fill pick the shared material
	var opaque := Settings.get_bool(Settings.REDUCE_TRANSPARENCY) or live
	var fill := UiTokens.alpha(&"reduce_transparency_fill") if opaque else UiTokens.alpha(&"glass_faux_fill")
	var m := _faux_material(elevation, PILL if radius < 0.0 else radius, fill)
	if _mat != m:
		_mat = m
		_glass.material = m


func _on_glass_setting(key: StringName, _value: Variant) -> void:
	if key == Settings.REDUCE_TRANSPARENCY:
		_refresh_material()
