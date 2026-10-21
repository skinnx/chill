class_name BakedWell
extends TextureRect
## A mini-render well drawn from the SnapshotBaker atlas (round 5): the same LiveWell diorama with
## its CreaturePortrait or ItemPreview, rendered once into a shared atlas page and shown as a
## rounded AtlasTexture region (shaders/ui/content.gdshader rounds it), so a grid of twelve friends
## or a list of flower cards draws its wells in one batch. The cell fades in over `micro` once it
## is baked (a frame or two after the sheet builds, hidden by the sheet's rise). Where nothing can
## be read back (headless) it holds the live well itself.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const MASK_SHADER := "res://shaders/ui/well_mask.gdshader"
## The mask draws above everything in the cell (the rig lifts its parts by a few z steps).
const MASK_Z := 64

var key: String = ""
var radius_px: float = ThemeBuilder.R_M
var _make: Callable
var _live: Control


## [param p_key] names the bake (include anything the picture depends on); [param make] builds
## the cell: make(size: Vector2) -> Control. [param min_size] is the well's minimum size.
static func create(p_key: String, min_size: Vector2, p_radius: float, make: Callable) -> BakedWell:
	var w := BakedWell.new()
	w.key = p_key
	w.custom_minimum_size = min_size
	w.radius_px = p_radius
	w._make = make
	return w


func _init() -> void:
	UiBatch.mark_well(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	resized.connect(_on_resized)


func _ready() -> void:
	_on_resized()


func _on_resized() -> void:
	if size.x < 2.0 or size.y < 2.0 or texture != null or _live != null:
		return
	if not SnapshotBaker.can_bake():
		_live = _cell(size)
		add_child(_live)
		_live.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	var px := Vector2i(roundi(size.x), roundi(size.y))
	var full := "%s@%dx%d" % [key, px.x, px.y]
	var b := SnapshotBaker.current
	var hit := b.request(full, px, _cell)
	if hit != null:
		texture = hit
		return
	modulate.a = 0.0
	b.baked.connect(func(k: String, t: Texture2D) -> void:
		if k == full and is_instance_valid(self) and texture == null:
			texture = t
			Motion.tween(self, "modulate:a", 1.0, &"micro"), CONNECT_DEFERRED)


## The cell to bake: the caller's content, rounded to [member radius_px] on a transparent page
## (a LiveWell or a UiSurface backdrop rounds itself).
func _cell(sz: Vector2) -> Control:
	var c: Control = _make.call(sz)
	if c is LiveWell:
		((c as LiveWell).material as ShaderMaterial).set_shader_parameter(&"u_radius", radius_px)
		# the subject's contact shadow is cut to the rounded window too (bake-time only; QA r5:
		# a square shadow strip at the bottom corners)
		c.add_child(_corner_mask(sz))
	elif c is UiSurface:
		(c as UiSurface).radius = radius_px
	return c


func _corner_mask(sz: Vector2) -> ColorRect:
	var m := ColorRect.new()
	m.name = "CornerMask"
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.color = Color.WHITE
	m.z_index = MASK_Z
	var mat := ShaderMaterial.new()
	mat.shader = load(MASK_SHADER) as Shader
	mat.set_shader_parameter(&"u_size", sz)
	mat.set_shader_parameter(&"u_radius", radius_px)
	m.material = mat
	m.size = sz
	return m
