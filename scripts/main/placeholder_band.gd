class_name PlaceholderBand
extends Node2D
## DEV PLACEHOLDER for one composition layer (Art Bible §2.3): a flat band, or the stream
## polyline from data/spots.json, coloured live by shaders/dev/placeholder_band.gdshader from the
## time-of-day globals. The Technical Artist replaces each one with the real layer node; nothing
## else references these. See docs/ARCHITECTURE.md §12 (placeholders register).

enum Slot { SKY, FAR, MID, GROUND, WATER, FOREGROUND }

const SHADER_PATH := "res://shaders/dev/placeholder_band.gdshader"

@export var slot: Slot = Slot.SKY
## Band in design px of the bottom-anchored 1080x1920 frame (x extends to the wide-screen bleed).
@export var rect: Rect2 = Rect2(-400, 0, 1880, 700)
## When true, draws the stream polyline of spots.json instead of [member rect].
@export var stream: bool = false

var _points := PackedVector2Array()
var _width: float = 0.0


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH) as Shader
	var slot_index: int = slot
	mat.set_shader_parameter(&"slot", slot_index)
	mat.set_shader_parameter(&"band_y", Vector2(rect.position.y, rect.end.y))
	material = mat
	if stream:
		var c := ContentRegistry.content
		var s: Dictionary = c.spots_doc["stream"]
		var frame: Dictionary = c.spots_doc["frame"]
		var height_px: float = frame["height_px"]
		var water_width: float = s["water_width"]
		for p: Variant in s["polyline"]:
			var pair: Array = p
			var a := PackedFloat64Array(pair)
			_points.append(GardenRules.frame_to_px(c, Vector2(a[0], a[1])))
		_width = water_width * height_px
	queue_redraw()


func _draw() -> void:
	if stream and _points.size() >= 2:
		draw_polyline(_points, Color.WHITE, _width, true)
	else:
		draw_rect(rect, Color.WHITE)
