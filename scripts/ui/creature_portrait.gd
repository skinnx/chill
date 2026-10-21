class_name CreaturePortrait
extends Control
## A live mossling portrait for the UI (Album friend cards, friend detail, new-friend card, postcard
## stamp; Art Bible §9.4, GDD §7.1): the real rig drawn by mossling_fur (no screenshots, no
## SubViewport), idle-breathing and blinking at the current palette, fitted into the control's
## rect with its feet on a soft contact shadow. Unknown friends get a soft fuzzy silhouette in ink
## @ 0.10 with no face (never a lock, never a question mark).
##
## The rig and its materials are shared by every portrait (one fur material, so the portraits
## batch with each other like the hollow's mosslings do).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const SILHOUETTE_SHADER := "res://shaders/ui/silhouette.gdshader"
## Fraction of the well the tallest point of the creature may fill.
const FILL := 0.78
## Feet sit this far up from the bottom of the well (fraction of its height).
const FEET_FRAC := 0.14
const SILHOUETTE_ALPHA := 0.10
## Magnified portraits keep the fur's felt grain at 1 screen dp (mossling_fur u_grain_density =
## the magnification): one fur material per density step, so same-size portraits still batch.
const GRAIN_PARAM := &"u_grain_density"
const GRAIN_STEP := 0.25

static var _rig: MosslingRig
static var _fur: ShaderMaterial
static var _shadow: ShaderMaterial
static var _fx: Dictionary = {}
## Fur materials by grain density step (1.0 = the shared _fur).
static var _fur_by_density: Dictionary = {}

var species: StringName = &""
var known: bool = true
var pose: StringName = &"awake"
var live: bool = true
var mossling: Mossling
var _silhouette: ColorRect


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_fit)


## [param p_known] false draws the silhouette. [param p_pose] awake / asleep / happy.
func setup(p_species: StringName, p_known: bool, p_pose: StringName = &"awake", p_live: bool = true) -> void:
	species = p_species
	known = p_known
	pose = p_pose
	live = p_live
	if is_inside_tree():
		_build()


func _ready() -> void:
	if species != &"":
		_build()


func _build() -> void:
	if mossling != null:
		mossling.queue_free()
		mossling = null
	if _silhouette != null:
		_silhouette.queue_free()
		_silhouette = null
	if known:
		_ensure_rig()
		mossling = Mossling.new()
		add_child(mossling)
		var seed01 := fposmod(float(hash(String(species)) % 1000) * 0.001 + 0.13, 1.0)
		mossling.setup(_rig, species, seed01, _fur, _shadow, _fx)
		mossling.set_still(not live)
		mossling.debug_pose(pose)
	else:
		_silhouette = ColorRect.new()
		_silhouette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = load(SILHOUETTE_SHADER) as Shader
		mat.set_shader_parameter(&"u_ink", UiTokens.tinted(&"ink", SILHOUETTE_ALPHA))
		mat.set_shader_parameter(&"u_seed", float(hash(String(species)) % 997) / 997.0)
		_silhouette.material = mat
		add_child(_silhouette)
	_fit()


func _fit() -> void:
	if mossling != null and _rig != null:
		var tall := _rig.body_px(species) * (1.0 + _rig.top_extent_bu(species))
		var wide := _rig.body_px(species) * _rig.body_width_bu(species) * 1.35
		var k := minf(size.y * FILL / maxf(tall, 1.0), size.x * FILL / maxf(wide, 1.0))
		mossling.place_at(Vector2(size.x * 0.5, size.y * (1.0 - FEET_FRAC)))
		mossling.scale_override(k)
		var body := mossling.get_node_or_null(^"Visual/Body") as CanvasItem
		if body != null:
			body.material = _fur_for(k)
	if _silhouette != null:
		_silhouette.position = Vector2.ZERO
		_silhouette.size = size
		(_silhouette.material as ShaderMaterial).set_shader_parameter(&"u_size", size)


## Frees the shared rig and materials (HUD exit).
static func release_shared() -> void:
	_rig = null
	_fur = null
	_fur_by_density = {}
	_shadow = null
	_fx = {}


## The fur material whose grain density matches a magnification of [param k] (k <= 1: shared).
static func _fur_for(k: float) -> ShaderMaterial:
	var step := maxf(1.0, snappedf(k, GRAIN_STEP))
	if is_equal_approx(step, 1.0):
		return _fur
	if not _fur_by_density.has(step):
		var m := _fur.duplicate() as ShaderMaterial
		m.set_shader_parameter(GRAIN_PARAM, step)
		_fur_by_density[step] = m
	return _fur_by_density[step] as ShaderMaterial


static func _ensure_rig() -> void:
	if _rig != null:
		return
	_rig = MosslingRig.new(ContentRegistry.content)
	_fur = _rig.make_fur_material()
	_shadow = _rig.make_shadow_material()
	_fx = _rig.make_fx_materials()
