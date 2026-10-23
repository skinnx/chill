class_name SignLayer
extends Node2D
## Mystery signs in the hollow (Retention v1 F2, GDD §13.3.2, `mysteries.json`).
##
## Someone has been here. A few paw prints by the fern, a dropped petal on the sun stone, a bush
## that shakes on its own, a folded leaf with a riddle on it. Tap one and it lifts away into the
## Album as a clue; collect a mystery's clues and you learn who has been visiting before they ever
## show up. This is the game's depth layer and it asks nothing of the player: one tap, no timer,
## nothing to manage, and a sign that is never tapped simply waits for ever (G2).
##
## The whole system - when a sign is due, which anchor it takes, what it looks like, what tapping
## it awards - has been simulated, saved, translated and tested since Retention v1 P1. Nothing ever
## drew it. This layer is that missing view, and only that: it reads [method Game.visible_signs]
## and calls [method Game.tap_sign], and holds no state of its own beyond the fade and the shake.
##
## Drawing: every sign of every type is accumulated into ONE triangle array and issued as a single
## [method CanvasItem.draw_polygon], so the whole layer costs one draw call however many signs are
## up (≤ `max_visible` = 3). The art is procedural - the project authors no sign textures.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## A sign was tapped and the clue taken (the view's own beat; the award arrives as Game.clue_found).
signal sign_tapped(key: String, sign: StringName)

const CUE_TOUCH := &"S01"
## GDD §13.3.2: a sign fades in over 600 ms and, when tapped, lifts into the Album over 600 ms.
const LIFT_S := 0.6
## The lift rises this far in dp as it fades.
const LIFT_DP := 44.0
## A rustle bush shakes for this long, this far (dp), every rustle_every_* seconds.
const SHAKE_S := 0.9
const SHAKE_DP := 3.0
## Press feedback: the sign dips by this much of its size.
const PRESS_SQUASH := 0.92
const PRESS_S := 0.12

static var current: SignLayer = null

var _content: GameContent
var _dp: float = 3.0
var _doc: Dictionary = {}
var _types: Dictionary = {}
var _anchors: Dictionary = {}
var _fade_s: float = 0.6
## key -> {sign record, t (seconds on screen), lift (-1 = not lifting), press (-1 = not pressed)}.
var _live: Dictionary = {}
var _time: float = 0.0


func _ready() -> void:
	current = self
	add_to_group(WorldPan.GROUP_HIT)
	_content = ContentRegistry.content
	_doc = _content.mysteries if _content != null else {}
	_dp = float((_content.spots_doc["frame"] as Dictionary)["px_per_dp"]) if _content != null else 3.0
	for t: Variant in _doc.get("sign_types", []):
		_types[StringName((t as Dictionary)["id"])] = t
	for a: Variant in _doc.get("anchors", []):
		_anchors[StringName((a as Dictionary)["id"])] = a
	_fade_s = float(_doc.get("fade_in_ms", 600.0)) * 0.001
	if Game.world_ready.is_connected(_on_world_ready):
		return
	Game.world_ready.connect(_on_world_ready)
	Game.sign_appeared.connect(func(_s: Dictionary) -> void: sync())


func _exit_tree() -> void:
	if current == self:
		current = null


func _on_world_ready(_recap: Array) -> void:
	sync()


## Takes the sim's list of signs on screen (≤ 3) as the truth. A sign that is new here starts its
## 600 ms fade; one that has gone (tapped, or the mystery solved) is dropped once its lift ends.
func sync() -> void:
	if not Game.is_ready or Game.sim == null:
		return
	var seen := {}
	for s: Dictionary in Game.visible_signs():
		var key := String(s["key"])
		seen[key] = true
		if _live.has(key):
			(_live[key] as Dictionary)["sign"] = s
		else:
			_live[key] = {"sign": s, "t": 0.0, "lift": -1.0, "press": -1.0}
	for key: String in _live.keys():
		var e: Dictionary = _live[key]
		if not seen.has(key) and float(e["lift"]) < 0.0:
			e["lift"] = 0.0  # it went away without a tap (solved offline): lift it out quietly
	set_process(not _live.is_empty())
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	var busy := false
	for key: String in _live.keys():
		var e: Dictionary = _live[key]
		e["t"] = float(e["t"]) + delta
		if float(e["press"]) >= 0.0:
			e["press"] = float(e["press"]) + delta
		if float(e["lift"]) >= 0.0:
			e["lift"] = float(e["lift"]) + delta
			if float(e["lift"]) >= LIFT_S:
				_live.erase(key)
				continue
		busy = true
	set_process(busy)
	queue_redraw()


# ------------------------------------------------------------------ world target

func world_hit(canvas_pos: Vector2, slop: float) -> Dictionary:
	if _live.is_empty():
		return {}
	var pos := get_global_transform_with_canvas().affine_inverse() * canvas_pos
	var best := {}
	for key: String in _live:
		var e: Dictionary = _live[key]
		if float(e["lift"]) >= 0.0:
			continue  # already on its way to the Album
		var cand := WorldPan.circle_hit(pos, _centre(e["sign"]), _hit_px(e["sign"]), slop,
				WorldPan.PRIO_SIGN, key)
		if not cand.is_empty() and (best.is_empty() or WorldPan.better(cand, best)):
			best = cand
	return best


func world_press(key: Variant, _canvas_pos: Vector2) -> void:
	var e: Variant = _live.get(String(key))
	if e == null or float((e as Dictionary)["lift"]) >= 0.0:
		return
	(e as Dictionary)["press"] = 0.0
	AudioDirector.play_cue(CUE_TOUCH, {"world": true,
		"position": get_global_transform() * _centre((e as Dictionary)["sign"])})
	queue_redraw()


func world_release(key: Variant, _canvas_pos: Vector2, act: bool) -> void:
	var id := String(key)
	var e: Variant = _live.get(id)
	if e == null:
		return
	var rec: Dictionary = e as Dictionary
	rec["press"] = -1.0
	if not act or float(rec["lift"]) >= 0.0:
		queue_redraw()
		return
	# The sim awards the clue and emits EV_CLUE; the HUD toasts from Game.clue_found. All this
	# layer owns is the lift (GDD §13.3.2 `clue_lift`).
	if Game.tap_sign(id):
		rec["lift"] = 0.0
		set_process(true)
		sign_tapped.emit(id, StringName((rec["sign"] as Dictionary)["sign"]))
	queue_redraw()


## Debug overlay (--debug-hits).
func world_hit_shapes() -> Array:
	var out: Array = []
	var xf := get_global_transform_with_canvas()
	for key: String in _live:
		var e: Dictionary = _live[key]
		if float(e["lift"]) >= 0.0:
			continue
		out.append({"kind": "circle", "c": xf * _centre(e["sign"]), "r": _hit_px(e["sign"]) * xf.get_scale().x,
			"prio": WorldPan.PRIO_SIGN, "name": key})
	return out


## The a11y label of the sign at [param key] (A11Y_SIGN_*, filled with the anchor's name).
func a11y_label(key: String) -> String:
	var e: Variant = _live.get(key)
	if e == null:
		return ""
	var t: Dictionary = _types.get(StringName((e as Dictionary)["sign"]["sign"]), {})
	return tr(String(t.get("a11y_key", "")))


# ------------------------------------------------------------------ geometry

func _anchor_of(sign: Dictionary) -> Dictionary:
	return _anchors.get(StringName(sign.get("anchor", "")), {})


func _centre(sign: Dictionary) -> Vector2:
	var a := _anchor_of(sign)
	if a.is_empty() or _content == null:
		return Vector2.ZERO
	return GardenRules.frame_to_px(_content, Vector2(float(a["x"]), float(a["y"])))


func _hit_px(sign: Dictionary) -> float:
	var a := _anchor_of(sign)
	return float(a.get("hit_dp", 60.0)) * _dp * 0.5


## The drawn size of a sign in px (sign_types[].visual_dp).
func _visual_px(sign: Dictionary) -> float:
	var t: Dictionary = _types.get(StringName(sign.get("sign", "")), {})
	return float(t.get("visual_dp", 32.0)) * _dp


## A sign's own colour: the species tint (`cr_*`), or a cousin's fur.
func _tint(sign: Dictionary) -> Color:
	var tokens: Dictionary = (_content.palettes.get("creatures", {}) as Dictionary).get("tokens", {})
	var id := String(sign.get("tint", ""))
	return Color.html(String(tokens[id])) if tokens.has(id) else Color(0.95, 0.89, 0.78)


## Deterministic per-sign phase so three bushes never shake together.
static func phase_of(key: String) -> float:
	return float(hash(key) & 0xFFFF) / 65535.0


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if _live.is_empty():
		return
	var tris := WorldTris.new()
	for key: String in _live:
		_draw_sign(tris, key, _live[key])
	tris.flush(self)


func _draw_sign(tris: WorldTris, key: String, e: Dictionary) -> void:
	var sign: Dictionary = e["sign"]
	var t := float(e["t"])
	var lift := float(e["lift"])
	var a := clampf(t / maxf(_fade_s, 0.001), 0.0, 1.0)
	var centre := _centre(sign)
	if lift >= 0.0:
		var u := clampf(lift / LIFT_S, 0.0, 1.0)
		a *= 1.0 - u
		centre.y -= LIFT_DP * _dp * u * u  # eases up as it fades, toward the Album button
	if a <= 0.004:
		return
	var scale := 1.0
	var press := float(e["press"])
	if press >= 0.0:
		scale = lerpf(PRESS_SQUASH, 1.0, clampf(press / PRESS_S, 0.0, 1.0))
	var size := _visual_px(sign) * scale
	var col := _tint(sign)
	col.a *= a
	match StringName(sign.get("sign", "")):
		&"footprints":
			_draw_footprints(tris, centre, size, col, String(sign.get("footprint", "tiny_paw")))
		&"dropped":
			_draw_dropped(tris, centre, size, col)
		&"rustle":
			_draw_rustle(tris, centre, size, col, key)
		&"note":
			_draw_note(tris, centre, size, col)


## A short trail of prints walking into the hollow. The style only changes the rhythm: how many
## prints, how far apart, how they stagger (GDD §13.3.1 per species).
func _draw_footprints(tris: WorldTris, c: Vector2, size: float, col: Color, style: String) -> void:
	var n := 4
	var stagger := 0.35
	var step := size * 0.3
	var r := size * 0.11
	match style:
		"tiptoe":
			n = 5
			r = size * 0.08
			step = size * 0.24
		"skip_dots", "hop_dots":
			n = 3
			step = size * 0.4
			stagger = 0.55
		"neat_row":
			stagger = 0.12
		"splash_paw":
			n = 3
			r = size * 0.14
		"sleepy_drag":
			n = 3
			step = size * 0.26
			stagger = 0.2
	for i in n:
		var side := 1.0 if i % 2 == 0 else -1.0
		var p := c + Vector2(float(i) * step - float(n - 1) * step * 0.5, side * size * stagger * 0.4)
		tris.blob(p, Vector2(r, r * 0.8), col)
		if style != "skip_dots" and style != "hop_dots":
			# the toe pad, a touch ahead of the pad
			tris.blob(p + Vector2(r * 0.9, -r * 0.7), Vector2(r * 0.42, r * 0.36), col)


## A small something left behind: a petal, a frond, a pebble, a feather.
func _draw_dropped(tris: WorldTris, c: Vector2, size: float, col: Color) -> void:
	var r := size * 0.42
	tris.blob(c, Vector2(r, r * 0.62), col)
	var hi := col
	hi.r = minf(hi.r + 0.06, 1.0)
	hi.g = minf(hi.g + 0.06, 1.0)
	hi.b = minf(hi.b + 0.06, 1.0)
	tris.blob(c + Vector2(-r * 0.22, -r * 0.2), Vector2(r * 0.5, r * 0.3), hi)


## A low bush that shakes on its own every 6-14 s. The shake is the whole tell, so it is the one
## thing here that moves; its phase comes from the sign's key so three bushes never shake together.
func _draw_rustle(tris: WorldTris, c: Vector2, size: float, col: Color, key: String) -> void:
	var t: Dictionary = _types.get(&"rustle", {})
	var lo := float(t.get("rustle_every_min_s", 6.0))
	var hi := float(t.get("rustle_every_max_s", 14.0))
	var period := lerpf(lo, hi, phase_of(key))
	var u := fposmod(_time + period * phase_of(key), period)
	var shake := 0.0
	if u < SHAKE_S and not Motion.reduce_motion:
		shake = sin(u / SHAKE_S * TAU * 3.0) * (1.0 - u / SHAKE_S) * SHAKE_DP * _dp
	var leaf: Dictionary = (_content.palettes.get("creatures", {}) as Dictionary).get("tokens", {})
	var green := Color.html(String(leaf.get("cr_fern", "#A7CB93")))
	green.a = col.a
	var r := size * 0.5
	tris.blob(c + Vector2(shake * 0.4, 0.0), Vector2(r, r * 0.72), green)
	tris.blob(c + Vector2(-r * 0.5 + shake, -r * 0.18), Vector2(r * 0.58, r * 0.5), green)
	tris.blob(c + Vector2(r * 0.52 + shake, -r * 0.1), Vector2(r * 0.52, r * 0.46), green)
	# one leaf in the species' own colour, so the bush still says who
	tris.blob(c + Vector2(shake * 1.2, -r * 0.62), Vector2(r * 0.3, r * 0.18), col)


## A folded leaf with the riddle on it.
func _draw_note(tris: WorldTris, c: Vector2, size: float, col: Color) -> void:
	var w := size * 0.46
	var h := size * 0.36
	var pale := Color(0.97, 0.95, 0.89, col.a)
	tris.quad(c + Vector2(-w, -h), c + Vector2(w, -h * 0.7), c + Vector2(w, h), c + Vector2(-w, h * 0.7), pale)
	var fold := col
	fold.a *= 0.8
	tris.quad(c + Vector2(-w, h * 0.1), c + Vector2(w, h * 0.3), c + Vector2(w, h), c + Vector2(-w, h * 0.7), fold)
