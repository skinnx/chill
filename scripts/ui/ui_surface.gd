class_name UiSurface
extends ColorRect
## A batched opaque UI surface (round 5; shaders/ui/surface.gdshader): cards, chips, plates,
## tracks, thumbs and pills in the sheets and modal cards. Every UiSurface shares ONE material and
## keeps its shape in instance uniforms, so all of them draw in one call (QA r4 blocker: an open
## sheet's StyleBoxFlat polygons cost one draw call each). The fill is [member color]; the
## elevation shadow, border and top lip are painted by the same quad (grown by the shadow margin).
##
## Use [method UiSurface.panel] for a PanelContainer card with a surface behind its content, or
## add a UiSurface as a child and size it yourself.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const SHADER := "res://shaders/ui/surface.gdshader"
## Pill / circle radius (half the short side).
const PILL := -1.0
## The panel that owns a surface carries this meta (UiBatch counts surface nesting with it).
const META_OWNER := &"ui_surface"

## [chrome material, scroll (fading) material]
static var _materials: Array[ShaderMaterial] = []

var radius: float = 0.0:
	set(v):
		radius = v
		_sync()
var elevation: int = UiTokens.E0:
	set(v):
		elevation = v
		_sync()
var border_px: float = 0.0:
	set(v):
		border_px = v
		_sync()
var border_color: Color = Color(0, 0, 0, 0):
	set(v):
		border_color = v
		_sync()
var lip_alpha: float = 0.0:
	set(v):
		lip_alpha = v
		_sync()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = shared_material()


func _ready() -> void:
	_sync()


## The shared surface material (tokens applied once); [param fading] = the scroll band's variant.
static func shared_material(fading: bool = false) -> ShaderMaterial:
	if _materials.is_empty():
		for f: float in [0.0, 1.0]:
			var m := ShaderMaterial.new()
			m.shader = load(SHADER) as Shader
			m.set_shader_parameter(&"u_ink", UiTokens.color(&"ink"))
			m.set_shader_parameter(&"u_lip", UiTokens.color(&"surface_hi"))
			m.set_shader_parameter(&"u_shadow_alpha", Vector3(UiTokens.alpha(&"shadow_e1"),
					UiTokens.alpha(&"shadow_e2"), UiTokens.alpha(&"shadow_e3")))
			m.set_shader_parameter(&"u_fade", f)
			_materials.append(m)
	return _materials[1 if fading else 0]


static func shared_materials() -> Array[ShaderMaterial]:
	shared_material()
	return _materials


static func release_shared() -> void:
	_materials.clear()


## A surface of [param fill], corner [param p_radius] (PILL for a capsule), elevation [param level].
static func make(fill: Color, p_radius: float, level: int = UiTokens.E0) -> UiSurface:
	var s := UiSurface.new()
	s.color = fill
	s.radius = p_radius
	s.elevation = level
	return s


## A PanelContainer whose background is a UiSurface (internal child, always behind the content and
## always the panel's full rect) with content padding [param pad] (Vector4: l, t, r, b; or all).
static func panel(fill: Color, p_radius: float, level: int = UiTokens.E0, pad: Variant = 0) -> PanelContainer:
	var p := PanelContainer.new()
	var box := StyleBoxEmpty.new()
	if pad is Vector4:
		var v4 := pad as Vector4
		box.content_margin_left = v4.x
		box.content_margin_top = v4.y
		box.content_margin_right = v4.z
		box.content_margin_bottom = v4.w
	else:
		box.set_content_margin_all(float(pad))
	p.add_theme_stylebox_override(&"panel", box)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	attach_to(p, make(fill, p_radius, level))
	return p


## Puts [param s] behind [param owner]'s children, filling its rect.
static func attach_to(owner: Control, s: UiSurface) -> UiSurface:
	s.name = "Surface"
	owner.add_child(s, false, Node.INTERNAL_MODE_FRONT)
	owner.set_meta(META_OWNER, s)
	# kept over the owner's whole rect by hand (a Container would fit an internal child into its
	# content rect; anchors would fight the explicit size)
	var fit := func() -> void:
		if is_instance_valid(s) and is_instance_valid(owner):
			s.position = Vector2.ZERO
			s.size = owner.size
	owner.resized.connect(fit)
	if owner is Container:
		(owner as Container).sort_children.connect(fit)
	fit.call()
	return s


## The surface behind [param owner] (from [method panel] / [method attach_to]), or null.
static func of(owner: Control) -> UiSurface:
	var v: Variant = owner.get_meta(META_OWNER, null)
	return v as UiSurface if v is UiSurface else null


func _sync() -> void:
	set_instance_shader_parameter(&"i_shape", Vector4(radius, float(clampi(elevation, 0, 3)), border_px,
			lip_alpha))
	set_instance_shader_parameter(&"i_border", border_color)
