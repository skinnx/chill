extends GutTest
## One-finger map drag (docs/ARCHITECTURE.md §3.4): bounds per aspect, rubber band and spring
## settle, Reduce Motion, the drag threshold and the tap-vs-drag arbitration with world layers.

const FRAME := Vector2(1080, 1920)
const X_RANGE := Vector2(TerrainMath.X_MIN, TerrainMath.X_MAX)
## Full-width layer scroll factors (Art Bible §2.3: far, mid, ground).
const SCALES: Array[float] = [0.1, 0.3, 1.0]
const UP := 600.0
const ROOM := 48.0
const DT := 1.0 / 60.0


class PressStub:
	extends Node
	var cancelled: int = 0

	func cancel_world_press() -> void:
		cancelled += 1


func _scales() -> PackedFloat64Array:
	return PackedFloat64Array(SCALES)


func _hard(vis: Vector2) -> Rect2:
	return PanMath.hard_bounds(vis, FRAME, X_RANGE, _scales(), UP, ROOM)


func _body(vis: Vector2 = Vector2(1080, 2400), rm: bool = false) -> PanBody:
	var b := PanBody.new()
	var hard := _hard(vis)
	b.set_bounds(PanMath.rest_bounds(hard, ROOM), hard)
	var sp := Motion.spring_params(&"move")
	b.spring_hz = sp.x
	b.spring_zeta = 0.8
	b.reduce_motion = rm
	return b


## Visible local x range of a layer at scroll s for a pan d (see PanMath).
func _visible_x(vis: Vector2, s: float, d: float) -> Vector2:
	var ox := roundf((vis.x - FRAME.x) * 0.5)
	return Vector2(s * d - ox, s * d - ox + vis.x)


# ------------------------------------------------------------------ bounds

func test_bounds_on_a_phone_follow_the_ground_geometry() -> void:
	for vis: Vector2 in [Vector2(1080, 1920), Vector2(1080, 2400), Vector2(1080, 2600)]:
		var hard := _hard(vis)
		assert_almost_eq(hard.position.x, X_RANGE.x, 0.01, "left: the ground's x_min reaches the screen edge (%s)" % vis)
		assert_almost_eq(hard.end.x, X_RANGE.y - FRAME.x, 0.01, "right: x_max (%s)" % vis)
		assert_almost_eq(hard.end.y, 0.0, 0.001, "never below the home view: the ground's bottom")
		assert_almost_eq(hard.position.y, -(UP + ROOM), 0.001, "up into the sky + the rubber room")
		var rest := PanMath.rest_bounds(hard, ROOM)
		assert_almost_eq(rest.position.x, X_RANGE.x + ROOM, 0.01)
		assert_almost_eq(rest.position.y, -UP, 0.01)
		assert_almost_eq(rest.end.y, 0.0, 0.001, "no rubber band below the ground")


func test_bounds_adapt_to_wide_screens() -> void:
	var tablet := _hard(Vector2(1440, 1920))
	assert_almost_eq(tablet.position.x, X_RANGE.x + 180.0, 0.01, "the centred column shifts the limit")
	assert_almost_eq(tablet.end.x, X_RANGE.y + 180.0 - 1440.0, 0.01)
	assert_lt(tablet.size.x, _hard(Vector2(1080, 1920)).size.x, "wider screen, less to pan")
	var huge := _hard(Vector2(2000, 1920))
	assert_eq(huge.size.x, 0.0, "a screen wider than the geometry does not pan sideways")
	assert_eq(PanMath.rest_bounds(huge, ROOM).size.x, 0.0)


func test_every_layer_stays_inside_its_geometry_at_the_hard_bounds() -> void:
	for vis: Vector2 in [Vector2(1080, 1920), Vector2(1080, 2400), Vector2(1240, 1920), Vector2(1440, 1920)]:
		var hard := _hard(vis)
		for s: float in SCALES:
			for d: float in [hard.position.x, hard.end.x]:
				var v := _visible_x(vis, s, d)
				assert_true(v.x >= X_RANGE.x - 0.01 and v.y <= X_RANGE.y + 0.01,
						"layer %.1f at pan %.0f on %s shows %s" % [s, d, vis, v])


# ------------------------------------------------------------------ rubber band and settle

func test_rubber_band_is_identity_inside_and_never_passes_the_hard_bounds() -> void:
	var b := _body()
	b.drag_to(Vector2(120, -200))
	assert_eq(b.offset(), Vector2(120, -200), "1:1 inside the bounds")
	for far: float in [60.0, 300.0, 5000.0, 1e6]:
		b.drag_to(Vector2(b.rest.end.x + far, b.rest.position.y - far))
		var o := b.offset()
		assert_gt(o.x, b.rest.end.x, "resistance, not a wall")
		assert_lt(o.x, b.hard.end.x + 0.001, "never past the authored geometry")
		assert_gte(o.y, b.hard.position.y - 0.001)
	b.drag_to(Vector2(0, 500))
	assert_eq(b.offset().y, 0.0, "hard clamp below the ground")
	var r1 := PanMath.rubber(110.0, 0.0, 100.0, 48.0, 48.0, 0.55) - 100.0
	var r2 := PanMath.rubber(140.0, 0.0, 100.0, 48.0, 48.0, 0.55) - 100.0
	assert_lt(r2 - r1, 30.0, "past the edge the map moves less than the finger")


func test_release_past_the_bounds_springs_back_inside() -> void:
	var b := _body()
	b.begin_drag()
	b.drag_to(Vector2(b.rest.end.x + 400.0, b.rest.position.y - 300.0))
	b.release(Vector2(900, -700))
	var t := 0.0
	while b.step(DT) and t < 5.0:
		var o := b.offset()
		assert_true(b.hard.has_point(o) or o.y == b.hard.end.y, "inside the hard bounds while settling: %s" % o)
		t += DT
	assert_false(b.is_moving(), "settles")
	assert_lt(t, 2.0, "with the move spring, quickly")
	assert_almost_eq(b.offset().x, b.rest.end.x, 0.5)
	assert_almost_eq(b.offset().y, b.rest.position.y, 0.5)


func test_fling_glides_with_friction_and_stops_at_an_edge() -> void:
	var b := _body()
	b.begin_drag()
	b.drag_to(Vector2.ZERO)
	b.release(Vector2(-300, 0))
	var prev := 0.0
	var t := 0.0
	while b.step(DT) and t < 5.0:
		var x := b.offset().x
		assert_lte(x, prev + 0.001, "keeps its direction")
		prev = x
		t += DT
	assert_false(b.is_moving())
	assert_lt(b.offset().x, -20.0, "inertia carried it")
	assert_gt(b.offset().x, b.rest.position.x, "friction stopped it inside")
	# a hard fling hits the edge, overshoots into the rubber band and settles on the edge
	b.release(Vector2(-6000, 0))
	var overshoot := false
	t = 0.0
	while b.step(DT) and t < 5.0:
		overshoot = overshoot or b.offset().x < b.rest.position.x - 1.0
		assert_gte(b.offset().x, b.hard.position.x - 0.001)
		t += DT
	assert_true(overshoot, "the edge gives a little")
	assert_almost_eq(b.offset().x, b.rest.position.x, 0.5, "and settles on it")


func test_home_glide_springs_back_to_the_centre() -> void:
	var b := _body()
	b.snap(Vector2(300, -400))
	b.glide_to(Vector2.ZERO)
	var t := 0.0
	while b.step(DT) and t < 5.0:
		t += DT
	assert_almost_eq(b.offset().length(), 0.0, 0.5)


func test_reduce_motion_has_no_inertia_and_no_overshoot() -> void:
	var b := _body(Vector2(1080, 2400), true)
	b.begin_drag()
	b.drag_to(Vector2(b.rest.end.x + 300.0, 0))
	assert_eq(b.offset().x, b.rest.end.x, "clamped, no rubber band")
	b.release(Vector2(-3000, 0))
	assert_false(b.is_moving(), "no glide")
	assert_eq(b.offset().x, b.rest.end.x)
	b.drag_to(Vector2(10, -50))
	b.release(Vector2(4000, 4000))
	assert_false(b.step(DT))
	assert_eq(b.offset(), Vector2(10, -50), "stops where the finger lifted")
	b.glide_to(Vector2.ZERO)
	assert_eq(b.offset(), Vector2.ZERO, "home is a cut, not a glide")


# ------------------------------------------------------------------ helpers of the view

func test_soft_limit_and_reveal() -> void:
	assert_eq(PanMath.soft_limit(50.0, 160.0, 160.0, 0.75), 50.0, "identity under the knee (idle drift)")
	assert_lte(PanMath.soft_limit(5000.0, 160.0, 160.0, 0.75), 160.0, "never past the room")
	assert_lt(PanMath.soft_limit(150.0, 160.0, 160.0, 0.75), 150.0, "eases in past the knee")
	assert_gte(PanMath.soft_limit(-5000.0, 110.0, 0.0, 0.75), -110.0)
	assert_eq(PanMath.soft_limit(30.0, 50.0, 0.0, 0.75), 0.0, "no room, no shift")
	assert_eq(PanMath.reveal(0.0, 0.1, 0.3), 0.0, "home view reveals nothing")
	assert_almost_eq(PanMath.reveal(-600.0, 0.3, 1.0), 420.0, 0.01, "rising 600 px parts mid and ground by 420")


func test_foreground_room_comes_from_the_cut_pieces() -> void:
	var pieces: Array[Sprite2D] = []
	for r: Rect2 in [Rect2(-170, 1400, 640, 540), Rect2(650, 1410, 620, 540), Rect2(740, -110, 560, 380)]:
		var sp := Sprite2D.new()
		sp.region_enabled = true
		sp.region_rect = Rect2(Vector2.ZERO, r.size)
		sp.position = r.position
		pieces.append(sp)
	var room := ForegroundFrame.frame_room(pieces, Vector2.ZERO, FRAME)
	assert_eq(room.z, 170.0, "may slide right until the left piece's cut edge")
	assert_eq(room.x, 190.0, "left: the right pieces bleed 190")
	assert_eq(room.w, 110.0, "down: the bough hangs 110 above the top")
	assert_eq(room.y, 20.0, "up: the reeds end 20 below the bottom")
	for sp: Sprite2D in pieces:
		sp.free()


# ------------------------------------------------------------------ input arbitration

func _pan() -> WorldPan:
	var p := WorldPan.new()
	add_child_autofree(p)
	p.configure({"rubber_k": 0.55}, {"px_per_dp": 3, "width_px": 1080}, {"x0": 0.067})
	p.view_width = 1080.0
	var hard := _hard(Vector2(1080, 2400))
	p.body.set_bounds(PanMath.rest_bounds(hard, ROOM), hard)
	p.body.reduce_motion = false
	return p


func _press(p: WorldPan, at: Vector2, down: bool = true) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = at
	if down:
		p._unhandled_input(ev)
	else:
		p._input(ev)


func _move(p: WorldPan, to: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.position = to
	p._input(ev)


func _touch(p: WorldPan, at: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = down
	ev.position = at
	if down:
		p._unhandled_input(ev)
	else:
		p._input(ev)


func _stub() -> PressStub:
	var s := PressStub.new()
	add_child_autofree(s)
	s.add_to_group(WorldPan.GROUP_PRESS)
	return s


func test_threshold_comes_from_the_project_setting() -> void:
	var p := _pan()
	var setting: int = ProjectSettings.get_setting("gui/common/drag_threshold")
	assert_eq(p.threshold_px, float(setting))
	assert_almost_eq(p.edge_px, 0.067 * 1080.0, 0.01, "24 dp edge band (spots safe_x)")


func test_small_moves_stay_a_tap() -> void:
	var p := _pan()
	var stub := _stub()
	watch_signals(p)
	_press(p, Vector2(540, 1200))
	_move(p, Vector2(540 + p.threshold_px - 2.0, 1200))
	assert_false(p.is_dragging(), "under the drag threshold")
	assert_eq(p.offset(), Vector2.ZERO, "the map has not moved")
	_press(p, Vector2(540 + p.threshold_px - 2.0, 1200), false)
	assert_signal_not_emitted(p, "drag_started")
	assert_eq(stub.cancelled, 0, "the world tap stands")


func test_drag_past_threshold_pans_and_cancels_pending_taps() -> void:
	var p := _pan()
	var stub := _stub()
	watch_signals(p)
	_press(p, Vector2(540, 1200))
	_move(p, Vector2(540 - 40, 1200))
	assert_true(p.is_dragging())
	assert_signal_emitted(p, "drag_started")
	assert_eq(stub.cancelled, 1, "pending bed / décor presses are dropped once")
	assert_almost_eq(p.offset().x, 40.0 - p.threshold_px, 0.01, "starts from the slop edge: no jump")
	_move(p, Vector2(540 - 140, 1200))
	assert_almost_eq(p.offset().x, 140.0 - p.threshold_px, 0.01, "then follows the finger 1:1")
	assert_eq(stub.cancelled, 1)
	_press(p, Vector2(540 - 140, 1200), false)
	assert_false(p.is_dragging())


func test_a_stroke_on_a_mossling_never_pans() -> void:
	var p := _pan()
	var stub := _stub()
	_press(p, Vector2(540, 1200))
	WorldPan.claim_pointer()  # CreatureLayer: the press landed on a mossling
	_move(p, Vector2(540 + 200, 1200))
	assert_false(p.is_dragging(), "the stroke pets, the map stays")
	assert_eq(p.offset(), Vector2.ZERO)
	assert_eq(stub.cancelled, 0, "the petting press is not cancelled")
	_press(p, Vector2(740, 1200), false)
	_press(p, Vector2(540, 1200))
	_move(p, Vector2(540 + 200, 1200))
	assert_true(p.is_dragging(), "the claim ends with its pointer")


func test_touch_path_and_its_emulated_mouse_are_one_pointer() -> void:
	var p := _pan()
	_touch(p, Vector2(540, 1200), true)
	var emu := InputEventMouseMotion.new()
	emu.device = InputEvent.DEVICE_ID_EMULATION
	emu.button_mask = MOUSE_BUTTON_MASK_LEFT
	emu.position = Vector2(540, 1500)
	p._input(emu)
	assert_false(p.is_dragging(), "emulated mouse events are ignored")
	var sd := InputEventScreenDrag.new()
	sd.index = 0
	sd.position = Vector2(540, 1260)
	p._input(sd)
	assert_true(p.is_dragging(), "the touch drag pans")
	assert_almost_eq(p.offset().y, -(60.0 - p.threshold_px), 0.01, "dragging down rises into the sky")
	var second := InputEventScreenDrag.new()
	second.index = 1
	second.position = Vector2(100, 100)
	p._input(second)
	assert_almost_eq(p.offset().y, -(60.0 - p.threshold_px), 0.01, "a second finger is ignored")
	_touch(p, Vector2(540, 1260), false)
	assert_false(p.is_dragging())


func test_no_drag_from_the_side_edges_or_through_a_sheet() -> void:
	var p := _pan()
	_press(p, Vector2(30, 1200))
	_move(p, Vector2(300, 1200))
	assert_false(p.is_dragging(), "24 dp edge band belongs to the OS back gesture")
	_press(p, Vector2(300, 1200), false)
	var sheet_open: Array[bool] = [true]
	p.blocked = func() -> bool: return sheet_open[0]
	_press(p, Vector2(540, 1200))
	_move(p, Vector2(300, 1200))
	assert_false(p.is_dragging(), "no panning while a sheet is open")
	_press(p, Vector2(300, 1200), false)
	sheet_open[0] = false
	_press(p, Vector2(540, 1200))
	_move(p, Vector2(300, 1200))
	assert_true(p.is_dragging())


func test_reduce_motion_drag_clamps_and_stops() -> void:
	var p := _pan()
	p.body.reduce_motion = true
	_press(p, Vector2(540, 1200))
	_move(p, Vector2(1000, 1200))
	_move(p, Vector2(1060, 1200))
	assert_true(p.is_dragging())
	_press(p, Vector2(1060, 1200), false)
	assert_false(p.body.is_moving(), "no inertia under Reduce Motion")
	assert_gte(p.offset().x, p.body.rest.position.x)


func test_double_tap_on_empty_ground_glides_home() -> void:
	var p := _pan()
	p.body.snap(Vector2(200, -300))
	for i in 2:
		_press(p, Vector2(540, 1200))
		p.mark_empty_press()  # Main: nothing in the world took the press
		_press(p, Vector2(540, 1200), false)
	assert_true(p.body.is_moving(), "gliding home")
	var t := 0.0
	while p.body.step(DT) and t < 5.0:
		t += DT
	assert_almost_eq(p.offset().length(), 0.0, 0.5)
	# taps on objects (no mark) never count
	p.body.snap(Vector2(200, -300))
	for i in 2:
		_press(p, Vector2(540, 1200))
		_press(p, Vector2(540, 1200), false)
	assert_false(p.body.is_moving())
