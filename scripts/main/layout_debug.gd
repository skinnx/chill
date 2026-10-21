class_name LayoutDebug
extends Node2D
## Debug overlay of the gameplay layout contract (data/spots.json, GDD §2): zones, bed hit areas
## and stem slots, spots, props with hit circles, décor anchors, stream tap band and live stems.
## Enabled with the user arg --debug-layout (QA, gameplay and UI engineers). Never shipped on.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const ARG := "--debug-layout"
const LINE_PX := 3.0
const DOT_PX := 6.0
const ZONE_COLOR := Color(0.16, 0.16, 0.22, 0.5)
const BED_COLOR := Color(0.29, 0.44, 0.84, 0.8)
const SPOT_COLOR := Color(1.0, 0.6, 0.48, 0.9)
const PROP_COLOR := Color(1.0, 0.8, 0.34, 0.9)
const ANCHOR_COLOR := Color(0.15, 0.44, 0.36, 0.9)
const STEM_COLOR := Color(1.0, 0.99, 0.97, 0.95)
## GDD §4.1.2: rig size 1.0 = a 50 dp tall mossling; spots are drawn at that size.
const SPOT_DIAMETER_DP := 50.0

var _content: GameContent


func _ready() -> void:
	visible = OS.get_cmdline_user_args().has(ARG)
	if not visible:
		set_process(false)
		return
	_content = ContentRegistry.content
	Game.sim_event.connect(func(_e: Dictionary) -> void: queue_redraw())


func _draw() -> void:
	if _content == null:
		return
	var frame: Dictionary = _content.spots_doc["frame"]
	var w := float(frame["width_px"])
	var h := float(frame["height_px"])
	var dp := float(frame["px_per_dp"])
	for z: Dictionary in _content.spots_doc["zones"]:
		draw_line(Vector2(0, float(z["y0"]) * h), Vector2(w, float(z["y0"]) * h), ZONE_COLOR, LINE_PX)
	var s: Dictionary = _content.spots_doc["stream"]
	draw_rect(Rect2(0, float(s["tap_band_y0"]) * h, w, (float(s["tap_band_y1"]) - float(s["tap_band_y0"])) * h),
			Color(BED_COLOR, 0.15))
	for b: Dictionary in _content.beds:
		var c := _px(float(b["x"]), float(b["y"]))
		var size := Vector2(float(b["hit_w_dp"]), float(b["hit_h_dp"])) * dp
		draw_rect(Rect2(c - size * 0.5, size), BED_COLOR, false, LINE_PX)
		for off: Variant in b["stems"]:
			var o: Array = off
			draw_circle(c + _px(float(o[0]), float(o[1])), DOT_PX * 0.5, Color(BED_COLOR, 0.5))
	for sp: Dictionary in _content.spots:
		draw_arc(_px(float(sp["x"]), float(sp["y"])), SPOT_DIAMETER_DP * dp * 0.5, 0.0, TAU, 32, SPOT_COLOR, LINE_PX)
	for p: Dictionary in _content.props_by_id.values():
		var hit := float(p["hit_dp"]) * dp
		if hit > 0.0:
			draw_arc(_px(float(p["x"]), float(p["y"])), hit * 0.5, 0.0, TAU, 32, PROP_COLOR, LINE_PX)
	for a: Dictionary in _content.anchors_by_decor.values():
		for pos: Variant in a["positions"]:
			var q: Array = pos
			draw_circle(_px(float(q[0]), float(q[1])), DOT_PX, ANCHOR_COLOR)
	if Game.sim != null:
		for st: Dictionary in Game.sim.state.stems:
			var bed: Dictionary = _content.beds_by_id[StringName(st["bed"])]
			var o: Array = (bed["stems"] as Array)[int(st["slot"])]
			var pos := _px(float(bed["x"]), float(bed["y"])) + _px(float(o[0]), float(o[1]))
			draw_circle(pos, DOT_PX * (1.0 + int(st["stage"])), STEM_COLOR)


func _px(x: float, y: float) -> Vector2:
	return GardenRules.frame_to_px(_content, Vector2(x, y))
