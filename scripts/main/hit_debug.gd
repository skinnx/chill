class_name HitDebug
extends CanvasLayer
## QA overlay of every hit area (user arg --debug-hits; docs/ARCHITECTURE.md §3.5, docs/QA.md):
##  * World: what WorldPan resolves - each GROUP_HIT layer's world_hit_shapes() (mosslings, beds,
##    props, décor, the brook band), outlined in its priority colour with the fat-finger slop as a
##    faint outer ring, labelled with its name and size in dp. In Active F3 edit mode it shows the
##    GROUP_HIT_EDIT targets instead (pieces at prio 8, the selected one 9).
##  * UI: every visible Control that takes presses, in screen px - targets (buttons, sliders,
##    fields: green, or red when under 48 dp; dock tabs must reach 76 dp, HUD 72 dp) and consumers
##    (sheets, scrims, bands, the dock pebble, the toast: grey hatch-free fill), with the overlap
##    of any two targets in magenta and a gap under 8 dp in orange.
## Prints a "debug-hits:" summary every 30 frames (targets, too small, overlaps) for scripted QA.
## Never shipped on; it costs nothing without the flag (the node is not created).

# Data boundary: values read from metadata / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const ARG := "--debug-hits"
const LAYER := 100
const LINE := 3.0
const MIN_UI_DP := 48.0
const GAP_DP := 8.0
const PRINT_EVERY := 30
const PRIO_COLORS := {
	9: Color(1.0, 1.0, 1.0), 8: Color(0.9, 0.95, 0.6),
	7: Color(0.0, 0.9, 0.9), 6: Color(1.0, 0.35, 0.55), 5: Color(1.0, 0.85, 0.1), 4: Color(1.0, 0.55, 0.1),
	3: Color(0.55, 0.4, 1.0), 2: Color(0.2, 0.5, 1.0), 1: Color(0.1, 0.8, 1.0),
}
const TARGET := Color(0.1, 0.85, 0.3)
const SMALL := Color(1.0, 0.1, 0.1)
const CONSUMER := Color(0.2, 0.2, 0.25, 0.10)
const CONSUMER_LINE := Color(0.15, 0.15, 0.2, 0.55)
const OVERLAP := Color(1.0, 0.0, 1.0, 0.45)
const TIGHT := Color(1.0, 0.5, 0.0, 0.9)

var hud: Control
var pan: WorldPan
var last_summary: Dictionary = {}
var _canvas: Control
var _frames: int = 0


static func wanted() -> bool:
	return OS.get_cmdline_user_args().has(ARG)


func _ready() -> void:
	layer = LAYER
	_canvas = Control.new()
	_canvas.name = "HitCanvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_all)
	add_child(_canvas)


func _process(_delta: float) -> void:
	_canvas.queue_redraw()
	_frames += 1
	if _frames % PRINT_EVERY == 0:
		print("debug-hits: ", JSON.stringify(last_summary))


## Every UI control that takes presses (visible, effective filter not IGNORE) under [param root].
static func ui_controls(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var c := n as Control
		if c != null:
			if not c.is_visible_in_tree():
				continue
			if c.get_mouse_filter_with_override() != Control.MOUSE_FILTER_IGNORE:
				out.append(c)
		for ch: Node in n.get_children():
			stack.append(ch)
	return out


static func is_target(c: Control) -> bool:
	return (c is BaseButton and not (c as BaseButton).disabled) or c is UiSlider or c is LineEdit


## The rect a control takes presses in, in screen px (its visible rect clipped by scroll windows).
static func screen_rect(c: Control) -> Rect2:
	var r := c.get_global_rect()
	var sc := TapGuard.scroll_of(c)
	if sc != null:
		r = r.intersection(sc.get_global_rect())
	return r


func _draw_all() -> void:
	var dp := UiTokens.PX_PER_DP
	var font := ThemeDB.fallback_font
	var summary := {"world": 0, "ui_targets": 0, "ui_small": [], "ui_overlaps": [], "ui_tight": []}
	# while a sheet or card is open the world takes nothing (WorldPan.blocked): its areas are not drawn
	var world_live := pan != null and pan.is_inside_tree() and not (pan.blocked.is_valid() and bool(pan.blocked.call()))
	summary["world_blocked"] = not world_live
	if world_live:
		var group := WorldPan.GROUP_HIT_EDIT if pan.edit_mode else WorldPan.GROUP_HIT  # Active F3 edit targets
		for n: Node in pan.get_tree().get_nodes_in_group(group):
			if not n.has_method(&"world_hit_shapes") or (n is CanvasItem and not (n as CanvasItem).is_visible_in_tree()):
				continue
			for sh: Variant in n.call(&"world_hit_shapes"):
				_draw_world(sh as Dictionary, pan.slop_px, dp, font)
				summary["world"] = int(summary["world"]) + 1
	if hud == null:
		last_summary = summary
		return
	var targets: Array[Control] = []
	var rects: Array[Rect2] = []
	for c: Control in ui_controls(hud):
		var r := screen_rect(c)
		if r.size.x < 1.0 or r.size.y < 1.0:
			continue
		if is_target(c):
			targets.append(c)
			rects.append(r)
		else:
			_canvas.draw_rect(r, CONSUMER)
			_canvas.draw_rect(r, CONSUMER_LINE, false, 1.0)
	for i in targets.size():
		var r := rects[i]
		var w_dp := r.size.x / dp
		var h_dp := r.size.y / dp
		# the size floor is the control's own rect (a row half scrolled out is not "small")
		var full := targets[i].get_global_rect().size / dp
		var small := minf(full.x, full.y) < MIN_UI_DP - 0.5
		var col := SMALL if small else TARGET
		_canvas.draw_rect(r, Color(col, 0.12))
		_canvas.draw_rect(r, col, false, LINE)
		_canvas.draw_string(font, r.position + Vector2(6, 26), "%s %.0fx%.0f" % [targets[i].name, w_dp, h_dp],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
		if small:
			(summary["ui_small"] as Array).append("%s %.0fx%.0f" % [targets[i].name, full.x, full.y])
		for j in range(i + 1, targets.size()):
			if targets[j].is_ancestor_of(targets[i]) or targets[i].is_ancestor_of(targets[j]):
				continue
			var o := rects[i].intersection(rects[j])
			if o.size.x > 0.5 and o.size.y > 0.5:
				_canvas.draw_rect(o, OVERLAP)
				(summary["ui_overlaps"] as Array).append("%s/%s" % [targets[i].name, targets[j].name])
			elif rects[i].grow(GAP_DP * dp - 0.5).intersects(rects[j]) and not rects[i].grow(1.0).intersects(rects[j]) \
					and not _list_rows(rects[i], rects[j]):
				var g := rects[i].grow(GAP_DP * dp).intersection(rects[j])
				_canvas.draw_rect(g, TIGHT, false, 2.0)
				(summary["ui_tight"] as Array).append("%s/%s" % [targets[i].name, targets[j].name])
	summary["ui_targets"] = targets.size()
	last_summary = summary


## Full-width list rows stacked under a hairline (Settings) are one list, not two buttons: the
## 8 dp gap rule is for discrete targets (ARCHITECTURE §3.5).
static func _list_rows(a: Rect2, b: Rect2) -> bool:
	return absf(a.position.x - b.position.x) < 1.0 and absf(a.size.x - b.size.x) < 1.0 and a.size.x >= 600.0


func _draw_world(sh: Dictionary, slop: float, dp: float, font: Font) -> void:
	var col: Color = PRIO_COLORS.get(int(sh.get("prio", 0)), Color.WHITE)
	var name := String(sh.get("name", ""))
	match String(sh.get("kind", "")):
		"circle":
			var c: Vector2 = sh["c"]
			var r := float(sh["r"])
			_canvas.draw_circle(c, r, Color(col, 0.10))
			_canvas.draw_arc(c, r, 0.0, TAU, 48, col, LINE)
			_canvas.draw_arc(c, r + slop, 0.0, TAU, 48, Color(col, 0.35), 1.5)
			if sh.has("core"):
				_canvas.draw_arc(c, float(sh["core"]), 0.0, TAU, 32, col, 1.5)
			_canvas.draw_string(font, c + Vector2(-r * 0.7, 8), "%s %.0f" % [name, r * 2.0 / dp],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
		"rect":
			var rr: Rect2 = sh["rect"]
			_canvas.draw_rect(rr, Color(col, 0.10))
			_canvas.draw_rect(rr, col, false, LINE)
			_canvas.draw_rect(rr.grow(slop), Color(col, 0.35), false, 1.5)
			_canvas.draw_string(font, rr.position + Vector2(6, 26), "%s %.0fx%.0f" % [name, rr.size.x / dp, rr.size.y / dp],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
		"band":
			var br: Rect2 = sh["rect"]
			_canvas.draw_rect(br, Color(col, 0.08))
			_canvas.draw_rect(br, Color(col, 0.6), false, 1.5)
			var pts: PackedVector2Array = sh["line"]
			var half := float(sh["half"])
			if pts.size() >= 2:
				var up := PackedVector2Array()
				var dn := PackedVector2Array()
				for p: Vector2 in pts:
					up.append(p - Vector2(0.0, half))
					dn.append(p + Vector2(0.0, half))
				_canvas.draw_polyline(up, col, 2.0)
				_canvas.draw_polyline(dn, col, 2.0)
			_canvas.draw_string(font, br.position + Vector2(maxf(-br.position.x, 0.0) + 8.0, 22), name,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
