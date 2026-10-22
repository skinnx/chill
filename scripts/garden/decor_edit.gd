class_name DecorEdit
extends Node2D
## Active F3 edit mode (GDD §14.1, docs/gdd/ACTIVE_DECOR.md §2-§11; data/decor_placement.json): the
## controller between the arbiter (WorldPan, ARCHITECTURE §3.5), the décor view ([DecorLayer]), the
## pure placement rules (Game.decor_rules()) and the edit chrome ([DecorEditChrome] with its tray).
## A child of DecorLayer, drawn on the ground under every piece (rings, halos, sockets).
##
## Enter: a 450 ms long-press on a piece in play (the piece is already lifted, so one gesture
## carries it), or Garden › Décor › "Arrange your décor" (nothing selected, the hint for 4 s).
## While on, WorldPan asks only this node for targets (group world_hit_edit): every placed piece
## at prio 8 (+1 selected), a 60 dp circle (64 dp in the look zone) round its visual centre, clipped
## above the dock; a press within 24 dp of a side edge selects only (no drag). Everything else is
## ground: a drag pans, a tap is a destination.
##
## Feel (§3.3): press = the piece lifts in the same frame (x1.08, rise 6 dp on `press`, shadow
## x1.25, S35 + TICK); past the 24 px slop it is HELD: its foot eases to 24 dp above the finger over
## 120 ms, it leans up to 6 deg into its motion on `follow`, the magnet pulls it (<= 70 %) toward a
## snap socket within 14 dp (S36 + TICK on entering one, <= 1 per 150 ms), the foot ring is `leaf`
## 3 dp on valid ground and a dashed ink_2 ring with the piece at alpha 0.8 on invalid ground (a soft
## lift shadow and a cream glow keep it readable over flowers), and
## after 150 ms one soft hint names the reason. Never red, never a buzz. Beds, spots and built
## nests show soft keep-clear halos; a held stone lights the water line. Near a side edge the map
## pans (after 250 ms, up to 220 dp/s, eased in, half under Reduce Motion).
## Release: snap, nudge (48 dp) or float home (§4.4); a settle commits (Game.move_decor), puffs,
## plays S05 + TICK and auto-saves. Tap a piece = select (chip: Turn · Put away [· Lift a pebble]),
## then tap the ground = glide there. The tray (§8): drag a piece onto it = put away (S38); drag a
## tile out = a held piece from storage; tap a tile = in hand (tap the ground or "Find a spot").
## Undo (one step), Done / Back / pause = back to play (everything is already saved).
##
## QA (tools/qa/capture.sh still --fixture=active_mid --qa-decor-edit=<state>):
##   enter         edit mode just opened from the Garden sheet (hint, tray, Undo greyed)
##   hold_valid    a pinwheel carried over valid ground near a socket (magnet, sparkles, leaf ring)
##   hold_invalid  a toadstool carried over a flower bed (dashed ring, alpha 0.8, glow, the hint)
##   tray          a piece dragged over the tray (put-away glow and hint)
##   chip          a lantern selected (the selection chip, Undo live after a turn)
##   long_press    the long-press ring fill mid-way in play (the edit chrome has not risen yet)

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

signal entered
signal exited
## A piece settled after a move, glide, turn, take-out or undo (QA, tests).
signal settled(piece_id: String, ok: bool)
signal selection_changed(piece_id: String)

enum Mode { NONE, PRESSED, HELD, GLIDE }

const ARG_QA := "--qa-decor-edit="
const QA_STATES: Array[String] = ["enter", "hold_valid", "hold_invalid", "tray", "chip", "long_press"]
const QA_AT_S := 1.0
const QA_FREEZE_S := 0.9
## The ground overlay sorts before every piece of the play layer (it draws rings on the meadow).
const SORT_Y := -100000.0
## Cue ids (decor_placement.json audio; S35-S38 by GDD §14.8 D1).
const CUE_LIFT := &"S35"
const CUE_SNAP := &"S36"
const CUE_TURN := &"S37"
const CUE_TUCK := &"S38"
const CUE_SETTLE := &"S05"
const CUE_IN := &"S07"
const CUE_OUT := &"S08"
const CUE_NOT_YET := &"S11"
## ACTIVE_DECOR §3.3: the foot eases 24 dp above the contact over 120 ms.
const CARRY_DP := 24.0
const CARRY_EASE_S := 0.12
## Lean: degrees per (dp/s) of horizontal finger speed before the cap (decor_placement lean_max_deg).
const LEAN_DEG_PER_DPS := 0.02
## A selected piece is raised 3 dp (§11 piece states).
const SELECT_RISE_DP := 3.0
const TURN_HOP_DP := 2.0
## The invalid hint waits this long (no flicker) and a socket cue at most this often.
const HINT_DELAY_S := 0.15
const SNAP_CUE_GAP_S := 0.15
## §11: at most 8 nearest sockets shown at alpha 0.35, the active one at 1.0, 12 px dots.
const MARKERS_MAX := 8
const MARKER_ALPHA := 0.35
const MARKER_PX := 12.0
## Foot rings (dp): valid leaf 3 dp, invalid dashed ink_2, the selection 3 dp primary @ 0.7, the
## idle affordance line 2 dp @ 0.5 breathing at k 200 (Art Bible §9.2 colour-line rule).
const RING_VALID_DP := 3.0
const RING_INVALID_DP := 2.5
const RING_SELECT_DP := 3.0
const RING_SELECT_ALPHA := 0.7
const IDLE_LINE_DP := 2.0
const IDLE_ALPHA := 0.5
const IDLE_K := 200.0
## Foot rings hug the footprint: half width = footprint x FOOT_RING_K (at least FOOT_RING_MIN_DP),
## squashed to FOOT_RING_SQUASH on the ground, at the piece's depth.
const FOOT_RING_K := 2.2
const FOOT_RING_MIN_DP := 10.0
const FOOT_RING_SQUASH := 0.4
const DASHES := 14
## A held piece over invalid ground (§3.3). Polish: 0.8 (0.7 hid a toadstool among flowers), with
## the lift glow below carrying the rest of the contrast.
const INVALID_ALPHA := 0.8
## The lift shadow (x the foot ring): solid core, feathered spread, ink alpha at full lift.
const LIFT_SHADOW_CORE := 0.55
const LIFT_SHADOW_SPREAD := 1.25
const LIFT_SHADOW_ALPHA := 0.34
## The outline glow behind the lifted piece (surface_hi): alpha on a valid / invalid spot, and
## how far it feathers out past the piece's ellipse.
const GLOW_ALPHA_VALID := 0.32
const GLOW_ALPHA_INVALID := 0.6
const GLOW_SPREAD := 1.7
const INVALID_LEAN_DEG := -3.0
## The glide home / to a tapped spot: the `move` spring's settle time (ACTIVE_DECOR §4.4, 332 ms)
## on the standard curve; a put-away shrinks to this scale.
const GLIDE_S := 0.332
const TUCK_SCALE := 0.3
## Water line glow while a stone is held (dp wide, alpha).
const WATER_GLOW_DP := 14.0
const WATER_GLOW_ALPHA := 0.16
## Reference loop period (Art Bible loops: k ticks of a 600 s loop).
const LOOP_S := 600.0
## Arrow keys move the selection this far (ACTIVE_DECOR §10).
const ARROW_STEP_DP := 8.0

static var current: DecorEdit = null

var active: bool = false
var selected: String = ""
## A tray piece "in hand" (tap a tile): its set, set down by the next ground tap.
var hand_set: StringName = &""
var chrome: DecorEditChrome
var changed_this_session: bool = false

var _layer: DecorLayer
var _content: GameContent
var _dp: float = 3.0
var _mode: Mode = Mode.NONE
var _id: String = ""
var _set: StringName = &""
var _from_tray: bool = false
var _origin := Vector2.ZERO          # design px foot where the piece came from
var _press_canvas := Vector2.ZERO
var _finger := Vector2.ZERO          # canvas px
var _grab := Vector2.ZERO            # foot - finger at the press (design px)
var _carry_t: float = 0.0
var _foot := Vector2.ZERO            # drawn foot (design px)
var _raw_foot := Vector2.ZERO        # the finger's foot before the magnet (design px)
var _lift: Spring
var _lean: Spring
var _hop: Spring
var _alpha: float = 1.0
var _valid: bool = true
var _reason: StringName = &""
var _invalid_t: float = 0.0
var _hint_reason: StringName = &""
var _socket := Vector2.INF
var _snap_cue_t: float = -1.0
var _edge_t: float = 0.0
var _last_finger := Vector2.ZERO
var _layout: Array[Dictionary] = []
var _ctx: Dictionary = {}
var _sockets: Array[Dictionary] = []
var _halos: Array[Rect2] = []
var _water: PackedVector2Array = PackedVector2Array()
var _over_tray: bool = false
var _ghost: Node2D
var _glide_from := Vector2.ZERO
var _glide_to := Vector2.ZERO
var _glide_t: float = 0.0
var _glide_s: float = GLIDE_S
var _glide_scale := Vector2.ONE      # x from, y to
var _glide_ok: bool = true
var _glide_tuck: bool = false
var _time: float = 0.0
var _back := Callable()
var _qa: String = ""
var _qa_t: float = -1.0
var _qa_frozen: bool = false
var _em: Dictionary = {}
## The overlay drawn above beds and friends (z 1) but under the lifted piece.
var _top: Node2D


func setup(layer: DecorLayer) -> void:
	_layer = layer
	_content = ContentRegistry.content
	_dp = layer.px_per_dp()
	_em = _content.decor_placement.get("edit_mode", {})
	position = Vector2(0.0, SORT_Y)
	_lift = Motion.spring(&"press", 0.0)
	_lean = Motion.spring(StringName(String((_em.get("pick_up", {}) as Dictionary).get("lean_spring", "follow"))), 0.0)
	_hop = Motion.spring(&"pop", 0.0)
	var stream: Dictionary = _content.spots_doc.get("stream", {})
	for q: Variant in stream.get("polyline", []):
		_water.append(GardenRules.frame_to_px(_content, Vector2(float(q[0]), float(q[1]))))
	_back = func() -> void: exit()
	_top = Node2D.new()
	_top.name = "Top"
	_top.z_index = 1
	_top.draw.connect(_draw_top)
	add_child(_top)
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(ARG_QA) and QA_STATES.has(a.trim_prefix(ARG_QA)):
			_qa = a.trim_prefix(ARG_QA)
			_qa_t = 0.0


func _ready() -> void:
	current = self
	add_to_group(WorldPan.GROUP_HIT_EDIT)
	Game.decor_edit_exited.connect(_on_game_exited)
	if WorldPan.current != null:
		WorldPan.current.empty_tapped.connect(_on_empty_tapped)
	else:
		_connect_pan.call_deferred()


func _connect_pan() -> void:
	if WorldPan.current != null and not WorldPan.current.empty_tapped.is_connected(_on_empty_tapped):
		WorldPan.current.empty_tapped.connect(_on_empty_tapped)


func _exit_tree() -> void:
	Game.remove_back_handler(_back)
	if current == self:
		current = null
	if chrome != null and is_instance_valid(chrome):
		chrome.queue_free()


# ================================================================= pure helpers (tested)

## The held foot relative to the finger: the grab offset eases to [param carry_px] above the
## contact over [param ease_s] (smoothstep), so the thumb never hides the foot ring (§3.3).
static func carry_offset(grab: Vector2, carry_px: float, t: float, ease_s: float) -> Vector2:
	var k := smoothstep(0.0, 1.0, clampf(t / maxf(ease_s, 1e-3), 0.0, 1.0))
	return grab.lerp(Vector2(0.0, -carry_px), k)


## Edge pan speed in canvas px/s (signed: + toward the right) for a finger at [param x] on a view
## [param view_w] wide: zero outside the [param zone_px] side bands and before [param delay_s] in
## them; then up to [param max_px_s] growing with depth into the zone (ease-in quad), halved under
## Reduce Motion.
static func edge_pan_speed(x: float, view_w: float, zone_px: float, max_px_s: float, held_s: float, delay_s: float,
		reduce: bool, reduce_k: float = 0.5) -> float:
	if held_s < delay_s or zone_px <= 0.0:
		return 0.0
	var depth := 0.0
	var dir := 0.0
	if x < zone_px:
		depth = (zone_px - x) / zone_px
		dir = -1.0
	elif x > view_w - zone_px:
		depth = (x - (view_w - zone_px)) / zone_px
		dir = 1.0
	depth = clampf(depth, 0.0, 1.0)
	return dir * max_px_s * depth * depth * (reduce_k if reduce else 1.0)


## The lean (rad) for a horizontal finger speed [param vx_dp_s], capped at [param max_deg].
static func lean_for(vx_dp_s: float, max_deg: float) -> float:
	return deg_to_rad(clampf(vx_dp_s * LEAN_DEG_PER_DPS, -max_deg, max_deg))


## Where the selection chip goes (§11): [param gap] above the piece's top, or below its foot if
## that would cross [param min_y]; clamped to [param x_range] and kept above [param bottom_y].
static func chip_rect(top: Vector2, foot: Vector2, size: Vector2, gap: float, min_y: float, x_range: Vector2,
		bottom_y: float) -> Rect2:
	var y := top.y - gap - size.y
	if y < min_y:
		y = foot.y + gap
	y = minf(y, bottom_y - size.y)
	var x := clampf(top.x - size.x * 0.5, x_range.x, x_range.y - size.x)
	return Rect2(Vector2(x, y), size)


## Edit hit radius (dp) at a visual centre [param y_norm]: 64 dp in the look zone, else 60 (§3.2).
static func edit_hit_dp(y_norm: float, hit: Dictionary, look: Vector2) -> float:
	if y_norm >= look.x and y_norm < look.y:
		return float(hit.get("edit_piece_hit_dp_look_zone", 64))
	return float(hit.get("edit_piece_hit_dp", 60))


# ================================================================= enter / exit

## Opens edit mode (Garden sheet "Arrange", or the long-press). [param hint]: show DECOR_EDIT_HINT.
func enter(hint: bool = true) -> bool:
	if active:
		return true
	if Game.sim == null or not Game.feature_on(DecorLayer.FREE_DECOR):
		return false
	_connect_pan()
	if not Game.set_edit_mode(true):
		if not Game.edit_mode():
			return false
	active = true
	changed_this_session = false
	selected = ""
	hand_set = &""
	_ensure_chrome()
	if chrome != null:
		chrome.open(hint)
	Game.push_back_handler(_back)
	_cue(CUE_IN, false)
	FrameGovernor.hold_for(Motion.duration(&"standard"))
	queue_redraw()
	entered.emit()
	return true


## Back to play: whatever is held settles first (or floats home), Undo clears, the chrome exits,
## the HUD returns. The app always resumes in play mode.
func exit() -> void:
	if not active:
		return
	_finish_all()
	if Game.edit_mode():
		Game.set_edit_mode(false)  # decor_edit_exited -> _on_game_exited closes the chrome
	if active:
		_closed()


func _on_game_exited() -> void:
	# Game left edit mode (the app pausing): settle first, then the save runs (ACTIVE_DECOR §9)
	if active:
		_finish_all()
		_closed()


func _closed() -> void:
	active = false
	Game.remove_back_handler(_back)
	if chrome != null:
		chrome.close()
		if changed_this_session:
			chrome.toast(tr("DECOR_EDIT_DONE_TOAST"))
	_cue(CUE_OUT, false)
	_layer.refresh()
	queue_redraw()
	exited.emit()


## Settles every held / gliding / selected piece immediately (exit, pause, a card rising).
func _finish_all() -> void:
	if _mode == Mode.HELD or _mode == Mode.PRESSED:
		_drop(_mode == Mode.HELD)
	if _mode == Mode.GLIDE:
		_glide_t = _glide_s
		_end_glide()
	_deselect()
	hand_set = &""
	if chrome != null:
		chrome.set_hand(&"")


func _ensure_chrome() -> void:
	if chrome != null and is_instance_valid(chrome):
		return
	var hud := _hud()
	if hud == null:
		return
	chrome = DecorEditChrome.new()
	chrome.name = "DecorEditChrome"
	chrome.edit = self
	chrome.hud = hud
	hud.edit_chrome_host().add_child(chrome)
	chrome.done_pressed.connect(exit)
	chrome.undo_pressed.connect(_on_undo)
	chrome.turn_pressed.connect(_on_turn)
	chrome.put_away_pressed.connect(_on_put_away)
	chrome.lift_pebble_pressed.connect(_on_lift_pebble)
	chrome.find_spot_pressed.connect(_on_find_spot)
	chrome.tray.tile_tapped.connect(_on_tile_tapped)
	chrome.tray.drag_out_started.connect(_on_tray_drag_start)
	chrome.tray.drag_out_moved.connect(_on_tray_drag_move)
	chrome.tray.drag_out_ended.connect(_on_tray_drag_end)


func _hud() -> HudController:
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene == null:
		return null
	return scene.get_node_or_null(^"HUD/HudRoot") as HudController


## The long-press fired on piece [param id] in play: edit mode opens with that piece lifted under
## the finger ([param carrying]: the same finger now drags it; else it is just selected).
func begin_from_long_press(id: String, canvas_pos: Vector2, carrying: bool) -> void:
	if not enter(false):
		return
	if carrying:
		_begin_press(id, canvas_pos)
	else:
		_select(id)


# ================================================================= arbiter (GROUP_HIT_EDIT)

func world_hit(canvas_pos: Vector2, slop: float) -> Dictionary:
	if not active or _layer == null:
		return {}
	var pos := _layer.to_design(canvas_pos)
	var hit: Dictionary = _content.decor_placement.get("hit", {})
	var frame_h := float(_content.spots_doc["frame"]["height_px"])
	if pos.y > float(hit.get("edit_hit_clip_above_y", 0.797)) * frame_h:
		return {}
	var look := _zone(&"look")
	var prio := int(hit.get("prio_edit_piece", WorldPan.PRIO_EDIT))
	var bonus := int(hit.get("prio_edit_selected_bonus", 1))
	var pan := WorldPan.current
	var edge := pan != null and (canvas_pos.x < pan.edge_px or canvas_pos.x > pan.view_width - pan.edge_px)
	var best := {}
	for p: DecorLayer.Piece in _layer.movable_pieces():
		if _mode == Mode.GLIDE and p.id == _id:
			continue
		var c := _layer.visual_centre_of(p)
		var r := edit_hit_dp(c.y / frame_h, hit, look) * _dp * 0.5
		var cand := WorldPan.circle_hit(pos, c, r, slop, prio + (bonus if p.id == selected else 0), p.id)
		if cand.is_empty():
			continue
		cand["drag"] = not edge
		if best.is_empty() or WorldPan.better(cand, best):
			best = cand
	return best


func world_press(key: Variant, canvas_pos: Vector2) -> void:
	if _mode == Mode.GLIDE:
		_glide_t = _glide_s
		_end_glide()
	_begin_press(String(key), canvas_pos)


func world_drag(key: Variant, canvas_pos: Vector2) -> void:
	if String(key) != _id:
		return
	_finger = canvas_pos
	if _mode == Mode.PRESSED and canvas_pos.distance_to(_press_canvas) > _threshold():
		_to_held()


func world_release(key: Variant, canvas_pos: Vector2, act: bool) -> void:
	if String(key) != _id:
		return
	_finger = canvas_pos
	if _mode == Mode.HELD:
		_drop(true)
	elif _mode == Mode.PRESSED:
		_mode = Mode.NONE
		if act:
			if selected == _id:
				_deselect()
			else:
				_select(_id)
		else:
			_settle_in_place()


## Debug overlay (--debug-hits): the edit targets in canvas px.
func world_hit_shapes() -> Array:
	var out: Array = []
	if not active:
		return out
	var hit: Dictionary = _content.decor_placement.get("hit", {})
	var frame_h := float(_content.spots_doc["frame"]["height_px"])
	var k := _layer.get_global_transform_with_canvas().get_scale().x
	for p: DecorLayer.Piece in _layer.movable_pieces():
		var c := _layer.visual_centre_of(p)
		var r := edit_hit_dp(c.y / frame_h, hit, _zone(&"look")) * _dp * 0.5 * k
		out.append({"kind": "circle", "c": _layer.to_canvas(c), "r": r,
			"prio": WorldPan.PRIO_EDIT_SELECTED if p.id == selected else WorldPan.PRIO_EDIT, "name": "edit " + String(p.decor)})
	return out


func _threshold() -> float:
	return float(ProjectSettings.get_setting("gui/common/drag_threshold", 24))


func _zone(id: StringName) -> Vector2:
	for z: Variant in _content.spots_doc.get("zones", []):
		if z is Dictionary and StringName(String((z as Dictionary)["id"])) == id:
			return Vector2(float((z as Dictionary)["y0"]), float((z as Dictionary)["y1"]))
	return Vector2(0.175, 0.44)


# ================================================================= press, hold, drop

func _begin_press(id: String, canvas_pos: Vector2) -> void:
	var p := _layer.piece(id)
	if p == null:
		return
	if selected != "" and selected != p.id:
		_deselect()
	hand_set = &""
	if chrome != null:
		chrome.set_hand(&"")
	_id = p.id
	_set = p.decor
	_from_tray = false
	_origin = p.foot
	_press_canvas = canvas_pos
	_finger = canvas_pos
	_last_finger = canvas_pos
	_grab = p.foot - _layer.to_design(canvas_pos)
	_foot = p.foot
	_raw_foot = p.foot
	_carry_t = 0.0
	_alpha = 1.0
	_valid = true
	_reason = &""
	_invalid_t = 0.0
	_edge_t = 0.0
	_over_tray = false
	_layer.hold(_id)
	_lift = Motion.spring(&"press", _lift.value if selected == _id else 0.0)
	_lift.target = 1.0
	_mode = Mode.PRESSED
	_cue(CUE_LIFT, true)
	if chrome != null:
		chrome.hide_chip()
	_pose()
	FrameGovernor.hold_for(Motion.duration(&"short"))
	queue_redraw()


## Past the slop: the piece follows the finger; sockets, halos and the ghost are built once.
func _to_held() -> void:
	_mode = Mode.HELD
	if selected == _id:
		selected = ""
		selection_changed.emit("")
	_layout = Game.sim.state.decor_layout
	_ctx = Game.decor_context()
	var rules := Game.decor_rules()
	_sockets = rules.sockets(_set, _layout, _ctx, _rules_id())
	_halos = _keep_clear()
	if not _from_tray:
		_ghost = _layer.make_ghost(_id)
	if chrome != null:
		chrome.hide_chip()
		chrome.set_hint(&"")
	queue_redraw()


## The id the rules ignore while this piece moves (a tray piece is not placed: nothing to ignore).
func _rules_id() -> String:
	return "" if _from_tray else _id


func _drop(act: bool) -> void:
	var was_held := _mode == Mode.HELD
	_mode = Mode.NONE
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	if chrome != null:
		chrome.set_tray_hover(false)
		chrome.set_hint(&"")
	if not was_held:
		_settle_in_place()
		return
	if _over_tray and act:
		_put_away_held()
		return
	var pos := _norm(_raw_foot)
	var res := {}
	if _from_tray:
		res = Game.take_out_decor(_set, pos)
	else:
		res = Game.move_decor(_id, pos)
	if bool(res.get("ok", false)):
		changed_this_session = true
		var to := GardenRules.frame_to_px(_content, res["pos"] as Vector2)
		if String(res.get("merge", "")) != "":
			to = _layer.foot_of(String(res["merge"]))
		_start_glide(_foot, to, true, false)
	else:
		_show_hint(DecorPlacementRules.R_RETURNED)
		if _from_tray:
			_start_glide(_foot, _tray_point(), false, true)
		else:
			_start_glide(_foot, _origin, false, false)


func _put_away_held() -> void:
	if _from_tray:
		_start_glide(_foot, _tray_point(), false, true)
		return
	if Game.store_decor(_id):
		changed_this_session = true
		_cue(CUE_TUCK, true)
		_start_glide(_foot, _tray_point(), true, true)
	else:
		_start_glide(_foot, _origin, false, false)


## A press released without a drag (or cancelled): the piece sinks back where it stands.
func _settle_in_place() -> void:
	if selected == _id:
		_lift.target = SELECT_RISE_DP / _rise_dp()
		_pose()
		return
	_lift.target = 0.0
	_mode = Mode.GLIDE
	_glide_from = _layer.foot_of(_id)
	_glide_to = _glide_from
	_glide_t = 0.0
	_glide_ok = true
	_glide_tuck = false
	_glide_scale = Vector2.ONE


func _start_glide(from: Vector2, to: Vector2, ok: bool, tuck: bool) -> void:
	_mode = Mode.GLIDE
	_glide_from = from
	_glide_to = to
	_glide_t = 0.0
	_glide_ok = ok
	_glide_tuck = tuck
	_glide_scale = Vector2(1.0, TUCK_SCALE if tuck else 1.0)
	_lift.target = 0.0
	_lean.target = 0.0
	FrameGovernor.hold_for(_glide_s + Motion.duration(&"short"))


func _end_glide() -> void:
	var id := _id
	var landed := _glide_to
	var ok := _glide_ok
	var tuck := _glide_tuck
	_mode = Mode.NONE
	_lift = Motion.spring(&"press", 0.0)
	_lean = Motion.spring(&"follow", 0.0)
	_alpha = 1.0
	_layer.unhold(id)
	if tuck:
		if chrome != null:
			chrome.refresh_tray(_set)
	elif ok and landed.distance_to(_origin) > 0.5:
		_layer.puff(landed)
		_cue(CUE_SETTLE, true)
	if chrome != null:
		chrome.refresh()
	_id = ""
	settled.emit(id, ok)
	queue_redraw()


# ================================================================= selection and chip

func _select(id: String) -> void:
	var p := _layer.piece(id)
	if p == null:
		return
	if selected != "" and selected != p.id:
		_deselect()
	selected = p.id
	_id = p.id
	_set = p.decor
	_layer.hold(p.id)
	_foot = p.foot
	_lift = Motion.spring(&"press", _lift.value)
	_lift.target = SELECT_RISE_DP / _rise_dp()
	_alpha = 1.0
	_pose()
	if chrome != null:
		chrome.show_chip(p)
		chrome.set_hint(&"selected", p.decor)
	selection_changed.emit(selected)
	queue_redraw()


func _deselect() -> void:
	if selected == "":
		return
	var id := selected
	selected = ""
	if _mode == Mode.NONE:
		_layer.unhold(id)
		if _id == id:
			_id = ""
	if chrome != null:
		chrome.hide_chip()
		chrome.set_hint(&"")
	selection_changed.emit("")
	queue_redraw()


func _on_turn() -> void:
	if selected == "":
		return
	var r := Game.turn_decor(selected)
	if r < 0:
		return
	changed_this_session = true
	_hop = Motion.spring(&"pop", 1.0)
	_hop.target = 0.0
	_cue(CUE_TURN, true)
	_layer.refresh()
	if chrome != null:
		chrome.refresh()
	FrameGovernor.hold_for(Motion.duration(&"standard"))


func _on_put_away() -> void:
	if selected == "":
		return
	var id := selected
	selected = ""
	if chrome != null:
		chrome.hide_chip()
		chrome.set_hint(&"")
	if not Game.store_decor(id):
		_layer.unhold(id)
		return
	changed_this_session = true
	_id = id
	_cue(CUE_TUCK, true)
	_foot = _layer.foot_of(id)
	_start_glide(_foot, _tray_point(), true, true)
	selection_changed.emit("")


func _on_lift_pebble() -> void:
	if selected == "":
		return
	var stack := selected
	_deselect()
	var pebble := Game.lift_pebble(stack)
	if pebble == "":
		return
	changed_this_session = true
	_layer.refresh()
	_cue(CUE_LIFT, true)
	_select(pebble)


func _on_find_spot() -> void:
	if hand_set == &"":
		return
	var res := Game.take_out_decor(hand_set, Vector2.INF)
	_after_take_out(res)


func _on_tile_tapped(set_id: StringName) -> void:
	_deselect()
	hand_set = &"" if hand_set == set_id else set_id
	if chrome != null:
		chrome.set_hand(hand_set)
		chrome.set_hint(&"tray" if hand_set != &"" else &"", hand_set)


func _after_take_out(res: Dictionary) -> void:
	hand_set = &""
	if chrome != null:
		chrome.set_hand(&"")
		chrome.set_hint(&"")
	if not bool(res.get("ok", false)):
		_show_hint(StringName(String(res.get("reason", DecorPlacementRules.R_RETURNED))))
		return
	changed_this_session = true
	_layer.refresh()
	_layer.pop_in(String(res.get("piece", "")))
	_cue(CUE_LIFT, true)
	if chrome != null:
		chrome.refresh()


## A tap on the ground: the selected piece glides there, a tray piece in hand is set down there.
func _on_empty_tapped(canvas_pos: Vector2) -> void:
	if not active or _layer == null:
		return
	var at := _layer.to_design(canvas_pos)
	if hand_set != &"":
		_after_take_out(Game.take_out_decor(hand_set, _norm(at)))
		return
	if selected == "":
		_layer.ring(at)
		if chrome != null:
			chrome.set_hint(&"enter")
		return
	var id := selected
	var p := _layer.piece(id)
	var from := p.foot if p != null else at
	var res := Game.move_decor(id, _norm(at))
	selected = ""
	if chrome != null:
		chrome.hide_chip()
		chrome.set_hint(&"")
	selection_changed.emit("")
	_id = id
	_origin = from
	if bool(res.get("ok", false)):
		changed_this_session = true
		var to := GardenRules.frame_to_px(_content, res["pos"] as Vector2)
		if String(res.get("merge", "")) != "":
			to = _layer.foot_of(String(res["merge"]))
		_start_glide(from, to, true, false)
	else:
		_show_hint(DecorPlacementRules.R_RETURNED if String(res.get("reason", "")) == "" else StringName(res["reason"]))
		_start_glide(from, from, false, false)


func _on_undo() -> void:
	if not Game.can_undo_decor():
		_cue(CUE_NOT_YET, false)
		return
	_finish_all()
	var before := {}
	for p: DecorLayer.Piece in _layer.movable_pieces():
		before[p.id] = p.foot
	if not Game.undo_decor():
		return
	_layer.refresh()
	for p: DecorLayer.Piece in _layer.movable_pieces():
		var was: Vector2 = before.get(p.id, p.foot)
		if was.distance_to(p.foot) > 0.5 and _mode == Mode.NONE:
			_id = p.id
			_origin = was
			_layer.hold(p.id)
			_start_glide(was, p.foot, true, false)
			break
	if chrome != null:
		chrome.refresh()
		chrome.announce(tr("A11Y_DECOR_UNDONE"))


## Desktop and web (§10): arrows move the selection 8 dp, R turns, Backspace puts away,
## Ctrl/Cmd+Z undoes, Esc means Done. Optional; the pointer path stays the only world input.
func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if not active or k == null or not k.pressed or k.echo:
		return
	var handled := true
	var step := ARROW_STEP_DP * _dp
	match k.keycode:
		KEY_ESCAPE:
			exit()
		KEY_Z:
			if k.is_command_or_control_pressed():
				_on_undo()
			else:
				handled = false
		KEY_R:
			_on_turn()
		KEY_BACKSPACE, KEY_DELETE:
			_on_put_away()
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			var dir := {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT, KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}
			if selected != "" and _mode == Mode.NONE:
				_on_empty_tapped(_layer.to_canvas(_layer.foot_of(selected) + (dir[k.keycode] as Vector2) * step))
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


# ================================================================= tray drags

func _on_tray_drag_start(set_id: StringName, canvas_pos: Vector2) -> void:
	if _mode != Mode.NONE:
		return
	_deselect()
	hand_set = &""
	var id := ""
	for rec: Dictionary in Game.decor_layout():
		if StringName(String(rec["set"])) == set_id and bool(rec.get("stored", false)):
			id = String(rec["id"])
			break
	if id == "":
		return
	var at := _layer.to_design(canvas_pos)
	if not _layer.hold(id, set_id, at):
		return
	_id = id
	_set = set_id
	_from_tray = true
	_origin = at
	_press_canvas = canvas_pos
	_finger = canvas_pos
	_last_finger = canvas_pos
	_grab = Vector2.ZERO
	_foot = at
	_raw_foot = at
	_carry_t = 0.0
	_lift = Motion.spring(&"press", 0.6)
	_lift.target = 1.0
	_mode = Mode.PRESSED
	_cue(CUE_LIFT, true)
	_to_held()
	_pose()


func _on_tray_drag_move(canvas_pos: Vector2) -> void:
	if _from_tray and _mode == Mode.HELD:
		_finger = canvas_pos


func _on_tray_drag_end(canvas_pos: Vector2) -> void:
	if _from_tray and _mode == Mode.HELD:
		_finger = canvas_pos
		_step_held(0.0)
		_drop(true)


## The tray tile of the held set (design px) for a put-away or a float back.
func _tray_point() -> Vector2:
	if chrome == null:
		return _foot + Vector2(0.0, 200.0)
	return _layer.to_design(chrome.tray_target(_set))


# ================================================================= frame

func _process(delta: float) -> void:
	if _qa != "" and not _qa_frozen:
		_step_qa(delta)
	if _qa_frozen:
		return
	_time += delta
	if not active and _mode == Mode.NONE:
		return
	if WorldPan.current != null:
		WorldPan.current.double_tap_home = selected == "" and hand_set == &""
	match _mode:
		Mode.HELD:
			_step_held(delta)
		Mode.GLIDE:
			_step_glide(delta)
	if _mode != Mode.NONE or selected != "":
		_lift.step(delta)
		_lean.step(delta)
		_hop.step(delta)
		_pose()
	queue_redraw()


func _step_held(delta: float) -> void:
	var rules := Game.decor_rules()
	_carry_t += delta
	var finger_d := _layer.to_design(_finger)
	_raw_foot = finger_d + carry_offset(_grab, CARRY_DP * _dp, _carry_t, CARRY_EASE_S)
	var raw_n := _norm(_raw_foot)
	var ignore := _rules_id()
	var snap := rules.snap(_set, raw_n, _layout, _ctx, ignore, _sockets)
	var shown := raw_n
	if bool(snap["socket"]):
		shown = snap["pos"] as Vector2
		if not Motion.reduce_motion:
			shown = rules.magnet(_set, raw_n, _layout, _ctx, ignore, _sockets)
		var sp: Vector2 = snap["pos"]
		if sp.distance_to(_socket) > 1e-5 and (_snap_cue_t < 0.0 or _time - _snap_cue_t >= SNAP_CUE_GAP_S):
			_snap_cue_t = _time
			_cue(CUE_SNAP, true)
		_socket = sp
	else:
		_socket = Vector2.INF
	_foot = GardenRules.frame_to_px(_content, shown)
	var reason := rules.validate(_set, shown, _layout, _ctx, ignore)
	if bool(snap["socket"]):
		reason = DecorPlacementRules.VALID
	_over_tray = chrome != null and chrome.tray_drop_rect().has_point(_finger)
	if chrome != null:
		chrome.set_tray_hover(_over_tray)
	_valid = reason == DecorPlacementRules.VALID or _over_tray
	_reason = reason
	if _valid:
		_invalid_t = 0.0
		if chrome != null:
			chrome.set_hint(&"tray_drop" if _over_tray else &"")
	else:
		_invalid_t += delta
		if _invalid_t >= HINT_DELAY_S:
			_show_hint(reason)
	_alpha = 1.0 if _valid else INVALID_ALPHA
	var pick: Dictionary = _em.get("pick_up", {})
	var vx := 0.0
	if delta > 0.0:
		vx = (_finger.x - _last_finger.x) / delta / _dp
	_last_finger = _finger
	var lean := 0.0 if Motion.reduce_motion else lean_for(vx, float(pick.get("lean_max_deg", 6.0)))
	if not _valid:
		lean += deg_to_rad(INVALID_LEAN_DEG)
	_lean.target = lean
	_step_edge_pan(delta)
	FrameGovernor.poke()


func _step_edge_pan(delta: float) -> void:
	var pan := WorldPan.current
	if pan == null:
		return
	var ep: Dictionary = _em.get("edge_autopan", {})
	var zone := float(ep.get("zone_dp", 40)) * _dp
	if _finger.x < zone or _finger.x > pan.view_width - zone:
		_edge_t += delta
	else:
		_edge_t = 0.0
	var v := edge_pan_speed(_finger.x, pan.view_width, zone, float(ep.get("max_speed_dp_s", 220)) * _dp, _edge_t,
			float(ep.get("start_delay_ms", 250)) / 1000.0, Motion.reduce_motion, float(ep.get("reduce_motion_factor", 0.5)))
	if v != 0.0:
		pan.nudge(Vector2(v * delta, 0.0))


func _step_glide(delta: float) -> void:
	_glide_t += delta
	var u := clampf(_glide_t / maxf(_glide_s, 1e-3), 0.0, 1.0)
	var e := UiTokens.ease(&"standard", u) if not Motion.reduce_motion else u
	_foot = _glide_from.lerp(_glide_to, e)
	if _glide_tuck:
		_alpha = 1.0 - u
	elif not _glide_ok:
		_alpha = lerpf(INVALID_ALPHA, 1.0, u)
	if _glide_t >= _glide_s:
		_end_glide()


## Applies lift, lean, hop and alpha to the held / selected piece.
func _pose() -> void:
	var id := _id if _id != "" else selected
	if id == "":
		return
	var pick: Dictionary = _em.get("pick_up", {})
	var lift := clampf(_lift.value, 0.0, 1.2)
	var rise := lift * _rise_dp() * _dp + _hop.value * TURN_HOP_DP * _dp
	var scale_k := 1.0 + (float(pick.get("scale", 1.08)) - 1.0) * lift
	if _mode == Mode.GLIDE:
		scale_k *= lerpf(_glide_scale.x, _glide_scale.y, clampf(_glide_t / maxf(_glide_s, 1e-3), 0.0, 1.0))
	var foot := _foot
	if _mode == Mode.NONE and selected != "":
		foot = _layer.foot_of(selected)
	_layer.pose(id, foot, rise, scale_k, _alpha, _lean.value, lift)


func _rise_dp() -> float:
	return float((_em.get("pick_up", {}) as Dictionary).get("rise_dp", 6.0))


func _norm(design: Vector2) -> Vector2:
	var f: Dictionary = _content.spots_doc["frame"]
	return Vector2(design.x / float(f["width_px"]), design.y / float(f["height_px"]))


func _show_hint(reason: StringName) -> void:
	if chrome == null or reason == DecorPlacementRules.VALID:
		return
	var key := Game.decor_rules().hint_key(reason)
	var text := tr(key)
	if reason == DecorPlacementRules.R_NEST:
		text = I18n.fmt(StringName(key), {"name": _nearest_nest_name()})
	chrome.show_reason(text)


func _nearest_nest_name() -> String:
	var best := ""
	var best_d := INF
	var at := _norm(_foot)
	var nests := Game.nests()
	for sp: Variant in nests:
		var n: Dictionary = nests[sp]
		if n.is_empty():
			continue
		var d := at.distance_to(Vector2(float(n.get("x", 0.0)), float(n.get("y", 0.0))))
		if d < best_d:
			best_d = d
			best = Game.display_name(StringName(sp))
	return best


## Soft keep-clear halos while a piece is held (§3.3): bed soil, always-on spots, built nests.
func _keep_clear() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var cl: Dictionary = _content.decor_placement["clearances"]
	var soil: Dictionary = cl["bed_soil"]
	var r := float(_content.placement_set(_set).get("footprint_r_dp", 4.0))
	var gap := float(cl.get("gap_dp", 4))
	for b: Dictionary in _content.beds:
		var c := GardenRules.frame_to_px(_content, Vector2(float(b["x"]), float(b["y"])))
		var half := Vector2(float(soil["rx_dp"]) + r + gap, float(soil["ry_dp"]) + r + gap) * _dp
		out.append(Rect2(c - half, half * 2.0))
	for s: Dictionary in _content.spots:
		if String(s.get("requires_item", "")) != "":
			continue
		var c := GardenRules.frame_to_px(_content, Vector2(float(s["x"]), float(s["y"])))
		var rr := (float(cl.get("spot_clear_dp", 10)) + r) * _dp
		out.append(Rect2(c - Vector2(rr, rr * 0.5), Vector2(rr, rr * 0.5) * 2.0))
	for n: Variant in _ctx.get("nests", []):
		var c := GardenRules.frame_to_px(_content, n as Vector2)
		var rr := float((cl["nest"] as Dictionary).get("centre_clear_dp", 12)) * _dp
		out.append(Rect2(c - Vector2(rr, rr * 0.5), Vector2(rr, rr * 0.5) * 2.0))
	return out


func _cue(id: StringName, tick: bool) -> void:
	var at := _layer.to_canvas(_foot) if _layer != null else Vector2.ZERO
	AudioDirector.play_cue(id, {"world": true, "position": at})
	var cues: Dictionary = AudioDirector.manifest.get("cues", {})
	if tick and not cues.has(String(id)):
		Haptics.play_for_cue({"subtle": null, "full": "TICK"}, id)  # cue not authored yet: keep the TICK


# ================================================================= ground overlay

func _draw() -> void:
	if _top != null:
		_top.queue_redraw()
	if not active and _mode == Mode.NONE:
		return
	var t := Tris.new(Vector2(0.0, -SORT_Y))
	var ink := UiTokens.color(&"ink")
	if _mode == Mode.HELD:
		for h: Rect2 in _halos:
			t.ellipse(h.get_center(), h.size * 0.5, Color(ink, float(_em.get("keep_clear_halo_alpha", 0.1))))
		if _set == DecorLayer.STONES and _water.size() > 1:
			t.line(_water, WATER_GLOW_DP * _dp, Color(UiTokens.color(&"surface_hi"), WATER_GLOW_ALPHA))
	var breath := 0.5 + 0.5 * sin(TAU * _time * IDLE_K / LOOP_S)
	if active:
		var line := Color(UiTokens.color(&"surface_hi"), IDLE_ALPHA * (0.6 + 0.4 * breath))
		for p: DecorLayer.Piece in _layer.movable_pieces():
			if p.id == _id or p.id == selected:
				continue
			t.line(_ellipse_points(p.foot, _ring_half(p.decor, p.depth)), IDLE_LINE_DP * _dp, line)
	t.flush(self)


## Above the beds and friends but under the lifted piece (z 1, sorted first): the selection
## ring, the held piece's foot ring and the snap sparkles, never hidden by flowers.
func _draw_top() -> void:
	if not active and _mode == Mode.NONE:
		return
	var t := Tris.new(Vector2(0.0, -SORT_Y))
	if selected != "" and _mode == Mode.NONE:
		var sp := _layer.piece(selected)
		if sp != null:
			t.line(_ellipse_points(sp.foot, _ring_half(sp.decor, sp.depth) * 1.15), RING_SELECT_DP * _dp,
					Color(UiTokens.color(&"primary"), RING_SELECT_ALPHA))
	if _mode == Mode.HELD or _mode == Mode.PRESSED:
		_draw_lift(t)
	if _mode == Mode.HELD:
		_draw_sockets(t)
	if _mode == Mode.HELD or _mode == Mode.PRESSED:
		var size := _ring_half(_set, DecorLayer.depth_scale(_foot.y))
		if _valid:
			t.line(_ellipse_points(_foot, size), RING_VALID_DP * _dp, UiTokens.color(&"leaf"))
		else:
			for k in DASHES:
				var a0 := TAU * float(k) / float(DASHES)
				var seg := PackedVector2Array()
				for j in 5:
					var a := a0 + TAU / float(DASHES) * 0.55 * float(j) / 4.0
					seg.append(_foot + Vector2(cos(a) * size.x, sin(a) * size.y))
				t.line(seg, RING_INVALID_DP * _dp, UiTokens.color(&"ink_2"))
	t.flush(_top)


## The carried piece reads over anything (QA: a toadstool over a bed vanished into the flowers):
## a soft ink lift shadow on the ground that deepens with the lift, and a warm cream glow behind
## the lifted piece, stronger over an invalid spot where the piece itself is faded. Calm: no red,
## no pulse; drawn in the top overlay under the lifted piece, inside its one draw call.
func _draw_lift(t: Tris) -> void:
	var lift := clampf(_lift.value, 0.0, 1.0)
	if lift <= 0.01:
		return
	var depth := DecorLayer.depth_scale(_foot.y)
	var ring := _ring_half(_set, depth)
	var ink := UiTokens.color(&"ink")
	t.soft(_foot, ring * LIFT_SHADOW_CORE, ring * LIFT_SHADOW_SPREAD, Color(ink, LIFT_SHADOW_ALPHA * lift))
	var dy := float(_content.placement_set(_set).get("visual_centre_dy_dp", 0.0)) * _dp * depth
	var rise := lift * _rise_dp() * _dp
	var centre := _foot + Vector2(0.0, dy * 1.1 - rise)
	var half := Vector2(ring.x * 0.95, maxf(ring.x * 0.85, absf(dy) * 1.35))
	var a := (GLOW_ALPHA_VALID if _valid else GLOW_ALPHA_INVALID) * lift
	t.soft(centre, half, half * GLOW_SPREAD, Color(UiTokens.color(&"surface_hi"), a))


## The foot ring's half size (design px) for a set at [param depth].
func _ring_half(set_id: StringName, depth: float) -> Vector2:
	var r := maxf(float(_content.placement_set(set_id).get("footprint_r_dp", 4.0)) * FOOT_RING_K, FOOT_RING_MIN_DP)
	return Vector2(r, r * FOOT_RING_SQUASH) * _dp * depth


func _draw_sockets(t: Tris) -> void:
	var near: Array[Vector2] = []
	for s: Dictionary in _sockets:
		near.append(GardenRules.frame_to_px(_content, s["pos"] as Vector2))
	var at := _raw_foot
	near.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(at) < b.distance_squared_to(at))
	var dot := UiTokens.color(&"surface_hi")
	var active_px := GardenRules.frame_to_px(_content, _socket) if _socket != Vector2.INF else Vector2.INF
	for i in mini(MARKERS_MAX, near.size()):
		var q := near[i]
		var on := active_px != Vector2.INF and q.distance_to(active_px) < 1.0
		var col := Color(dot, 1.0 if on else MARKER_ALPHA)
		var r := MARKER_PX * (1.4 if on else 1.0) * 0.5
		t.ellipse(q, Vector2(r, r) * 1.6, Color(col, col.a * 0.22))
		var star := PackedVector2Array()
		for k in 8:
			var a := TAU * float(k) / 8.0
			star.append(q + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.38))
		t.fan(q, star, col)


static func _ellipse_points(c: Vector2, half: Vector2, n: int = 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n + 1:
		var a := TAU * float(k) / float(n)
		pts.append(c + Vector2(cos(a) * half.x, sin(a) * half.y))
	return pts


## Every ring, halo, line and sparkle of one overlay as ONE triangle array (one draw call instead
## of one per polyline / polygon; the edit chrome budget, decor_placement.json draw).
class Tris:
	extends RefCounted
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var offset := Vector2.ZERO

	func _init(p_offset: Vector2 = Vector2.ZERO) -> void:
		offset = p_offset

	## A thick polyline (one quad per segment; no overlap, so translucent lines stay even).
	func line(path: PackedVector2Array, width: float, col: Color) -> void:
		var hw := width * 0.5
		for i in path.size() - 1:
			var a := path[i]
			var b := path[i + 1]
			var d := b - a
			if d.length_squared() < 1e-6:
				continue
			var n := Vector2(-d.y, d.x).normalized() * hw
			_quad(a + n, b + n, b - n, a - n, col)

	## A filled ellipse.
	func ellipse(c: Vector2, half: Vector2, col: Color, n: int = 28) -> void:
		var ring := PackedVector2Array()
		for k in n:
			var a := TAU * float(k) / float(n)
			ring.append(c + Vector2(cos(a) * half.x, sin(a) * half.y))
		fan(c, ring, col)

	## A star-shaped polygon around [param c] (a triangle fan).
	func fan(c: Vector2, ring: PackedVector2Array, col: Color) -> void:
		var base := pts.size()
		pts.append(c + offset)
		cols.append(col)
		for q: Vector2 in ring:
			pts.append(q + offset)
			cols.append(col)
		for k in ring.size():
			idx.append_array([base, base + 1 + k, base + 1 + (k + 1) % ring.size()])

	## A soft ellipse: [param col] inside [param inner], fading to transparent at [param outer]
	## (vertex colours: one fan + one feathered band, no texture, same draw call).
	func soft(c: Vector2, inner: Vector2, outer: Vector2, col: Color, n: int = 32) -> void:
		var base := pts.size()
		pts.append(c + offset)
		cols.append(col)
		var clear := Color(col, 0.0)
		for k in n:
			var a := TAU * float(k) / float(n)
			var u := Vector2(cos(a), sin(a))
			pts.append(c + u * inner + offset)
			cols.append(col)
			pts.append(c + u * outer + offset)
			cols.append(clear)
		for k in n:
			var i0 := base + 1 + 2 * k
			var i1 := base + 1 + 2 * ((k + 1) % n)
			idx.append_array([base, i0, i1, i0, i0 + 1, i1 + 1, i0, i1 + 1, i1])

	func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
		var base := pts.size()
		for q: Vector2 in [a, b, c, d]:
			pts.append(q + offset)
			cols.append(col)
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	func flush(ci: CanvasItem) -> void:
		if not idx.is_empty():
			RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)


# ================================================================= QA

## --qa-decor-edit timeline: build the state QA_AT_S after the world is ready, freeze QA_FREEZE_S
## later (mid-carry, glide settled, chip risen).
func _step_qa(delta: float) -> void:
	if _qa_t < 0.0 or not Game.is_ready or Game.sim == null:
		return
	_qa_t += delta
	if _qa_t < QA_AT_S:
		return
	if _qa_t - delta < QA_AT_S:
		_qa_start()
	elif _qa == "long_press" or _qa_t < QA_AT_S + QA_FREEZE_S:
		_qa_drive()
	else:
		_qa_frozen = true
		_layer.set_process(false)
		if chrome != null:
			chrome.freeze()


func _qa_start() -> void:
	match _qa:
		"long_press":
			var p := _qa_piece(DecorLayer.TOADSTOOL)
			if p != null:
				_layer.world_press(p, _layer.to_canvas(p.hit))
		"enter":
			enter(true)
		"chip":
			enter(false)
			var p := _qa_piece(DecorLayer.LANTERN)
			if p != null:
				_select(p.id)
				_on_turn()
		"hold_valid", "hold_invalid", "tray":
			enter(false)
			var p := _qa_piece(DecorLayer.PINWHEEL if _qa == "hold_valid" else DecorLayer.TOADSTOOL)
			if p != null:
				_begin_press(p.id, _layer.to_canvas(p.foot))


## Carries the QA piece along a short path to its target so the lean, magnet and hint are live.
func _qa_drive() -> void:
	if _qa == "long_press":
		if _qa_t >= QA_AT_S + 0.3:
			_qa_frozen = true
			_layer._qa_frozen = true
		return
	if _mode != Mode.PRESSED and _mode != Mode.HELD:
		return
	var u := clampf((_qa_t - QA_AT_S) / (QA_FREEZE_S * 0.8), 0.0, 1.0)
	var to := _qa_target()
	var from := _layer.to_canvas(_origin)
	world_drag(_id, from.lerp(to, smoothstep(0.0, 1.0, u)))


func _qa_target() -> Vector2:
	match _qa:
		"hold_valid":
			# beside the second pinwheel on the crest: a same-set ring socket in reach
			var p := _qa_piece(DecorLayer.PINWHEEL, 1)
			var at := p.foot + Vector2(66.0 + 10.0, -6.0) if p != null else _origin
			return _layer.to_canvas(at - Vector2(0.0, -CARRY_DP * _dp))
		"hold_invalid":
			var b: Dictionary = _content.beds[0]
			var c := GardenRules.frame_to_px(_content, Vector2(float(b["x"]), float(b["y"])))
			return _layer.to_canvas(c + Vector2(0.0, CARRY_DP * _dp))
		"tray":
			if chrome != null:
				return chrome.tray_drop_rect().get_center() + Vector2(0.0, -30.0)
	return _layer.to_canvas(_origin)


func _qa_piece(set_id: StringName, n: int = 0) -> DecorLayer.Piece:
	var list: Array[DecorLayer.Piece] = []
	for p: DecorLayer.Piece in _layer.movable_pieces():
		if p.decor == set_id:
			list.append(p)
	list.sort_custom(func(a: DecorLayer.Piece, b: DecorLayer.Piece) -> bool: return a.index < b.index)
	if list.is_empty():
		push_warning("--qa-decor-edit: no %s placed (use --fixture=active_mid)" % set_id)
		return null
	return list[mini(n, list.size() - 1)]
