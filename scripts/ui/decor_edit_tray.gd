class_name DecorEditTray
extends Control
## Active F3 storage tray (docs/gdd/ACTIVE_DECOR.md §8; Art Bible §9.2; decor_placement.json storage):
## it replaces the dock while editing. HUD faux glass (r-xl 96, e2) 936 x 252 px at H 1920, its
## bottom 36 px above max(safe bottom, 127) like the dock; the caption "Tucked away" above its left
## shoulder. One 216 x 216 tile (72 dp, surface_hi, r-m 48) per set with pieces stored, 24 px gaps,
## each with a live mini-render (ItemPreview) and a "×3" count pill (Caption on leaf_tint; never a
## badge, never red). More tiles than fit scroll sideways (a partly visible tile shows there is more).
## Empty: one dashed well (2 dp ink @ 0.10) with "Pieces you put away rest here."
##
## Input (the mouse path, ARCHITECTURE §3.5 custom controls): a tile press that travels past 10 dp
## pops one piece out under the finger as a held piece ([signal drag_out_started], then moves and
## the release arrive here and are forwarded); a mostly horizontal drag scrolls the tray instead
## while there is more to see, until the finger leaves the tray. A tap toggles "in hand" (the tile
## rises 12 px with a 3 dp primary ring). While a held piece hovers over the tray (grown 12 dp)
## it lifts 6 px on pop and glows (basket_glow).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

signal tile_tapped(set_id: StringName)
signal drag_out_started(set_id: StringName, canvas_pos: Vector2)
signal drag_out_moved(canvas_pos: Vector2)
signal drag_out_ended(canvas_pos: Vector2)

## Art Bible §9.4 dock geometry (px at H 1920): 936 x 252, bottom 36 px above the inset.
const W := 936.0
const H := 252.0
const SIDE := 72.0
const BOTTOM_GAP := 36.0
const INSET_MIN := 127.0
const RADIUS := 96.0
const TILE := 216.0
const TILE_GAP := 24.0
const TILE_PAD := 18.0
const TILE_RADIUS := 48.0
const STAMP := 144.0
const PILL_H := 54.0
const PILL_PAD := 15.0
const RAISE := 12.0
const RING_DP := 3.0
const HOVER_LIFT := 6.0
const GLOW_SPREAD := 30.0
const EDGE_FADE := 48.0
const CAPTION_GAP := 12.0
const DASH := 18.0
## Text size >= 150 %: tiles grow to 84 dp (§10).
const TILE_LARGE := 252.0
const LARGE_TEXT := 150
## Labels draw above the plates in one z layer so they batch (DecorEditChrome.Z_LABEL).
const Z_LABEL := 3

var hovering: bool = false
var hand: StringName = &""

var _glass: GlassPanel
var _clip: Control
var _row: Control
var _caption: Label
var _empty: Label
var _tiles: Dictionary = {}   # set id -> Control
var _counts: Dictionary = {}
var _order: Array[StringName] = []
var _scroll: float = 0.0
var _press_set: StringName = &""
var _press_at := Vector2.ZERO
var _press_scroll: float = 0.0
var _scrolling: bool = false
var _out: bool = false
var _base_y: float = 0.0
var _tile_px: float = TILE
var _night_k: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false


func _ready() -> void:
	_glass = GlassPanel.new()
	_glass.name = "Glass"
	_glass.night_aware = true
	_glass.radius = RADIUS
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glass)
	_caption = UiSheet.label(tr("DECOR_TRAY_TITLE"), &"CaptionLabel")
	_caption.z_index = Z_LABEL
	add_child(_caption)
	_clip = Control.new()
	_clip.name = "Clip"
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	_row = Control.new()
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_row)
	_empty = UiSheet.label(tr("DECOR_TRAY_EMPTY"), &"StrongLabel")
	_empty.z_index = Z_LABEL
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_empty)
	draw.connect(_draw_tray)


## Places the tray for a [param screen] with a bottom OS inset of [param safe_bottom].
func layout(screen: Vector2, safe_bottom: float) -> void:
	var w := minf(W, screen.x - 2.0 * (SIDE - 48.0))
	var bottom := screen.y - maxf(safe_bottom, INSET_MIN) - BOTTOM_GAP
	_base_y = bottom - H
	size = Vector2(w, H)
	position = Vector2((screen.x - w) * 0.5, _base_y - (HOVER_LIFT if hovering else 0.0))
	_glass.position = Vector2.ZERO
	_glass.size = size
	_caption.position = Vector2(RADIUS * 0.5, -_caption.get_combined_minimum_size().y - CAPTION_GAP)
	_tile_px = TILE_LARGE if Settings.get_int(Settings.TEXT_SCALE) >= LARGE_TEXT else TILE
	var pad := (H - _tile_px) * 0.5
	_clip.position = Vector2(TILE_PAD, 0.0)
	_clip.size = Vector2(w - TILE_PAD * 2.0, H)
	_row.position = Vector2(-_scroll, pad)
	_empty.position = Vector2(TILE_PAD * 2.0, TILE_PAD)
	_empty.size = size - Vector2(TILE_PAD * 4.0, TILE_PAD * 2.0)
	_place_tiles()
	queue_redraw()


## Rebuilds the tiles from the layout's stored pieces (one per set, in Garden order).
func refresh(pop_set: StringName = &"") -> void:
	var counts := {}
	if Game.sim != null:
		for rec: Dictionary in Game.decor_layout():
			if bool(rec.get("stored", false)):
				var s := StringName(String(rec["set"]))
				counts[s] = int(counts.get(s, 0)) + 1
	var order: Array[StringName] = []
	var rows: Array[Dictionary] = []
	rows.assign(ContentRegistry.content.decor.duplicate())
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["garden_order"]) < int(b["garden_order"]))
	for d: Dictionary in rows:
		var s := StringName(String(d["id"]))
		if int(counts.get(s, 0)) > 0:
			order.append(s)
	for s: StringName in _tiles.keys():
		if not order.has(s):
			(_tiles[s] as Control).queue_free()
			_tiles.erase(s)
	for s: StringName in order:
		if not _tiles.has(s):
			_tiles[s] = _make_tile(s)
		_set_count(s, int(counts[s]))
	_order = order
	_counts = counts
	if hand != &"" and not _tiles.has(hand):
		hand = &""
	_empty.visible = order.is_empty()
	_place_tiles()
	if pop_set != &"" and _tiles.has(pop_set):
		var t: Control = _tiles[pop_set]
		t.pivot_offset = t.size * 0.5
		t.scale = Vector2.ONE * 1.12
		Motion.spring_to(t, "scale", Vector2.ONE, &"pop")
	queue_redraw()


func _make_tile(s: StringName) -> Control:
	var t := Control.new()
	t.name = String(s)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.tooltip_text = ""
	var plate := UiSurface.make(UiTokens.color(&"surface_hi"), TILE_RADIUS, UiTokens.E1)
	plate.name = "Plate"
	t.add_child(plate)
	var prev := ItemPreview.new()
	prev.name = "Preview"
	t.add_child(prev)
	prev.show_item(s)
	var pill := UiSurface.make(UiTokens.color(&"leaf_tint"), UiSurface.PILL)
	pill.name = "Pill"
	t.add_child(pill)
	var l := UiSheet.label("", &"CaptionLabel")
	l.z_index = Z_LABEL
	l.name = "Count"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.add_child(l)
	_row.add_child(t)
	_night_tile(t)
	return t


func _set_count(s: StringName, n: int) -> void:
	var t: Control = _tiles[s]
	var l := t.get_node(^"Count") as Label
	l.text = I18n.fmt(&"DECOR_TRAY_COUNT", {"count": n})
	var name_key := String((ContentRegistry.content.decor_by_id.get(s, {}) as Dictionary).get("name_key", ""))
	t.set_meta(&"a11y", I18n.fmt(&"A11Y_TRAY_TILE", {"decor": tr(name_key), "count": n}))


func _place_tiles() -> void:
	var x := 0.0
	for s: StringName in _order:
		var t: Control = _tiles[s]
		t.size = Vector2(_tile_px, _tile_px)
		t.position = Vector2(x, -RAISE if s == hand else 0.0)
		(t.get_node(^"Plate") as Control).size = t.size
		var prev := t.get_node(^"Preview") as Control
		var st := STAMP * _tile_px / TILE
		prev.size = Vector2(st, st)
		prev.position = Vector2((_tile_px - st) * 0.5, (_tile_px - st) * 0.5 - PILL_H * 0.25)
		var l := t.get_node(^"Count") as Label
		var pw := l.get_combined_minimum_size().x + PILL_PAD * 2.0
		var pill := t.get_node(^"Pill") as Control
		pill.size = Vector2(pw, PILL_H)
		pill.position = Vector2(_tile_px - pw - PILL_PAD * 0.6, _tile_px - PILL_H - PILL_PAD * 0.6)
		l.size = pill.size
		l.position = pill.position
		x += _tile_px + TILE_GAP
	_scroll = clampf(_scroll, 0.0, _max_scroll())
	_row.position.x = -_scroll
	queue_redraw()


func _content_w() -> float:
	return maxf(0.0, float(_order.size()) * (_tile_px + TILE_GAP) - TILE_GAP)


func _max_scroll() -> float:
	return maxf(0.0, _content_w() - _clip.size.x)


## The tile of a set in canvas px (its centre; the tray's centre when the set has none yet).
func tile_centre(s: StringName) -> Vector2:
	if _tiles.has(s):
		var t: Control = _tiles[s]
		return t.get_global_rect().get_center()
	if not _order.is_empty():
		var last: Control = _tiles[_order.back()]
		var r := last.get_global_rect()
		var next := r.get_center() + Vector2(_tile_px + TILE_GAP, 0.0)
		return Vector2(minf(next.x, get_global_rect().end.x - _tile_px * 0.5), next.y)
	return get_global_rect().get_center()


## The put-away drop target: the tray grown 12 dp (canvas px).
func drop_rect() -> Rect2:
	var dp := float(_storage().get("drop_target_grow_dp", 12))
	var r := Rect2(Vector2(position.x, _base_y), size)
	return r.grow(dp * UiTokens.PX_PER_DP)


func set_hover(on: bool) -> void:
	if hovering == on:
		return
	hovering = on
	Motion.spring_to(self, "position", Vector2(position.x, _base_y - (HOVER_LIFT if on else 0.0)), &"pop")
	queue_redraw()


func set_hand(s: StringName) -> void:
	hand = s
	_place_tiles()


func set_night(k: float) -> void:
	_night_k = k
	var ink := UiTokens.color(&"ink").lerp(UiTokens.color(&"night_ink"), k)
	_caption.add_theme_color_override(&"font_color", ink)
	_empty.add_theme_color_override(&"font_color", ink)
	for t: Control in _tiles.values():
		_night_tile(t)
	queue_redraw()


func _night_tile(t: Control) -> void:
	var k := _night_k
	(t.get_node(^"Plate") as UiSurface).color = UiTokens.color(&"surface_hi").lerp(UiTokens.color(&"night_capsule"), k)
	var n: Dictionary = ContentRegistry.palettes().get("ui_night", {})
	var night_pill := Color.html(String(n.get("leaf_tint", "#2E4C46")))
	(t.get_node(^"Pill") as UiSurface).color = UiTokens.color(&"leaf_tint").lerp(night_pill, k)
	(t.get_node(^"Count") as Label).add_theme_color_override(&"font_color",
			UiTokens.color(&"ink").lerp(UiTokens.color(&"night_ink"), k))


func _draw_tray() -> void:
	if hovering:
		var glow := UiTokens.color(&"basket_glow")
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(glow, 0.0)
		sb.shadow_color = Color(glow, 0.55)
		sb.shadow_size = int(GLOW_SPREAD)
		sb.set_corner_radius_all(int(RADIUS))
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
	var ink := UiTokens.color(&"ink").lerp(UiTokens.color(&"night_ink"), _night_k)
	if _order.is_empty():
		_dashed_round_rect(Rect2(Vector2(TILE_PAD, TILE_PAD), size - Vector2(TILE_PAD, TILE_PAD) * 2.0), RADIUS - TILE_PAD,
				Color(ink, 0.10), 2.0 * UiTokens.PX_PER_DP)
	if hand != &"" and _tiles.has(hand):
		var t: Control = _tiles[hand]
		var r := Rect2(_clip.position + _row.position + t.position, t.size).grow(RING_DP * UiTokens.PX_PER_DP * 0.5)
		var sb2 := StyleBoxFlat.new()
		sb2.draw_center = false
		sb2.border_color = UiTokens.color(&"primary")
		sb2.set_border_width_all(int(RING_DP * UiTokens.PX_PER_DP))
		sb2.set_corner_radius_all(int(TILE_RADIUS + RING_DP))
		sb2.anti_aliasing = true
		draw_style_box(sb2, r)
	# the scroll affordance: a soft fade at an edge with more beyond it
	if _max_scroll() > 0.5:
		var fill := UiTokens.color(&"surface").lerp(UiTokens.color(&"night_capsule"), _night_k)
		if _scroll < _max_scroll() - 0.5:
			var band := Vector2(EDGE_FADE, size.y - TILE_PAD * 2.0)
			_fade(Rect2(Vector2(size.x - TILE_PAD - EDGE_FADE, TILE_PAD), band), fill, false)
		if _scroll > 0.5:
			_fade(Rect2(Vector2(TILE_PAD, TILE_PAD), Vector2(EDGE_FADE, size.y - TILE_PAD * 2.0)), fill, true)


func _fade(r: Rect2, c: Color, left: bool) -> void:
	var a := Color(c, 0.0)
	var b := Color(c, 0.85)
	var cols := PackedColorArray([b, a, a, b]) if left else PackedColorArray([a, b, b, a])
	var quad := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	draw_polygon(quad, cols)


func _dashed_round_rect(r: Rect2, radius: float, c: Color, width: float) -> void:
	var pts := PackedVector2Array()
	var rad := minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var corners := [r.position + Vector2(rad, rad), Vector2(r.end.x - rad, r.position.y + rad), r.end - Vector2(rad, rad),
		Vector2(r.position.x + rad, r.end.y - rad)]
	for i in 4:
		var c0: Vector2 = corners[i]
		for k in 9:
			var a := PI + PI * 0.5 * float(i) + PI * 0.5 * float(k) / 8.0
			pts.append(c0 + Vector2(cos(a), sin(a)) * rad)
	pts.append(pts[0])
	var acc := 0.0
	var on := true
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var t := 0.0
		while t < seg:
			var step := minf(DASH - acc, seg - t)
			if on:
				draw_line(a.lerp(b, t / seg), a.lerp(b, (t + step) / seg), c, width, true)
			t += step
			acc += step
			if acc >= DASH - 1e-3:
				acc = 0.0
				on = not on


# ------------------------------------------------------------------ input (mouse path)

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_press_set = _tile_at(mb.position)
			_press_at = mb.global_position
			_press_scroll = _scroll
			_scrolling = false
			_out = false
			if _press_set != &"":
				var t: Control = _tiles[_press_set]
				PressFeedback.down(t, 1.0, t.get_local_mouse_position())
				AudioDirector.play_cue(&"S01")
		else:
			_release(mb.global_position)
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_move(mm.global_position)
		accept_event()


func _move(at: Vector2) -> void:
	if _out:
		drag_out_moved.emit(at)
		return
	var d := at - _press_at
	var slop := float(_storage().get("drag_out_threshold_dp", 10)) \
			* UiTokens.PX_PER_DP
	if not _scrolling and d.length() <= slop:
		return
	var horizontal := absf(d.x) > absf(d.y)
	if not _scrolling and horizontal and _max_scroll() > 0.5:
		_scrolling = true
	if _scrolling:
		_scroll = clampf(_press_scroll - d.x, 0.0, _max_scroll())
		_row.position.x = -_scroll
		queue_redraw()
		if get_global_rect().has_point(at) or _press_set == &"":
			return
	if _press_set != &"":
		_out = true
		PressFeedback.up(_tiles[_press_set] as Control)
		drag_out_started.emit(_press_set, at)


func _release(at: Vector2) -> void:
	if _out:
		_out = false
		drag_out_ended.emit(at)
		_press_set = &""
		return
	if _press_set != &"":
		PressFeedback.up(_tiles[_press_set] as Control)
		if not _scrolling:
			tile_tapped.emit(_press_set)
	_press_set = &""
	_scrolling = false


func _tile_at(local: Vector2) -> StringName:
	for s: StringName in _order:
		var t: Control = _tiles[s]
		var r := Rect2(_clip.position + _row.position + t.position, t.size)
		if r.has_point(local) and Rect2(_clip.position, _clip.size).has_point(local):
			return s
	return &""


func _storage() -> Dictionary:
	return ContentRegistry.content.decor_placement.get("storage", {})


func tile_count() -> int:
	return _order.size()


func count_of(s: StringName) -> int:
	return int(_counts.get(s, 0))
