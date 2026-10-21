class_name TouchRing
extends Node2D
## World touch flourish (round-3 directive 1): bloom + eased ring (motion_tokens ui.ring: 36 dp in
## 380 ms, alpha 0.35 -> 0) + ui.sparkles four-point sparkles, drawn by
## shaders/fx/touch_ring.gdshader on one additive quad. Visible on the first frame of the touch.
## Any world layer can use it:
##   var ring := TouchRing.spawn(self, design_pos)          # plays once, frees itself
##   ring.freeze_at(0.12)                                     # QA: hold the frame 120 ms in

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const SHADER_PATH := "res://shaders/fx/touch_ring.gdshader"
const QUAD_K := 1.35
const BLOOM := 0.32
## The ground squash of a ring that lies on the meadow / water (props use 1 = round).
const ROUND := 1.0

static var _material: ShaderMaterial = null

var duration_s: float = 0.38
var radius_px: float = 108.0
var squash: float = ROUND

var _age: float = 0.0
var _frozen: bool = false


static func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER_PATH) as Shader
	return _material


## Adds a ring under `parent` at `pos` (parent-local px) and starts it.
static func spawn(parent: Node, pos: Vector2, p_squash: float = ROUND) -> TouchRing:
	var r := TouchRing.new()
	r.position = pos
	r.squash = p_squash
	parent.add_child(r)
	return r


func _ready() -> void:
	var ui: Dictionary = ContentRegistry.motion_tokens()["ui"]
	var ring: Dictionary = ui["ring"]
	var px_per_dp := float(ContentRegistry.content.spots_doc["frame"]["px_per_dp"])
	duration_s = float(ring["ms"]) / 1000.0
	radius_px = float(ring["radius_dp"]) * px_per_dp
	var alpha: Array = ring["alpha"]
	var sp: Array = ui["sparkles"]
	var seed := TerrainMath.hash01(int(position.x * 7.0 + position.y * 13.0), 41)
	var count := floorf(lerpf(float(sp[0]), float(sp[1]) + 0.999, seed))
	material = shared_material()
	set_instance_shader_parameter(&"i_ring", Vector4(0.0, radius_px, float(alpha[0]), count))
	set_instance_shader_parameter(&"i_ring2", Vector4(squash, seed, BLOOM, 0.0))
	FrameGovernor.hold_for(duration_s)
	queue_redraw()


## QA: shows the ring `age_s` into its life and holds it there (frozen-time stills).
func freeze_at(age_s: float) -> void:
	_frozen = true
	_age = age_s
	_push()


func _process(delta: float) -> void:
	if _frozen:
		return
	_age += delta
	if _age >= duration_s:
		queue_free()
		return
	_push()


func _push() -> void:
	var v: Vector4 = get_instance_shader_parameter(&"i_ring")
	v.x = clampf(_age / maxf(duration_s, 0.001), 0.0, 1.0)
	set_instance_shader_parameter(&"i_ring", v)


func _draw() -> void:
	var h := radius_px * QUAD_K
	draw_rect(Rect2(-h, -h * squash, h * 2.0, h * 2.0 * squash), Color.WHITE)
