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


## A world layer offering one circular target (the WorldPan hit interface, ARCHITECTURE §3.5).
class TargetStub:
	extends Node
	var centre := Vector2(540, 1200)
	var radius: float = 90.0
	var prio: int = WorldPan.PRIO_BED
	var drag: bool = false
	var presses: int = 0
	var acts: int = 0
	var cancels: int = 0
	var drags: int = 0

	func world_hit(p: Vector2, slop: float) -> Dictionary:
		var c := WorldPan.circle_hit(p, centre, radius, slop, prio, name)
		if not c.is_empty() and drag:
			c["drag"] = true
		return c

	func world_press(_key: Variant, _p: Vector2) -> void:
		presses += 1

	func world_drag(_key: Variant, _p: Vector2) -> void:
		drags += 1

	func world_release(_key: Variant, _p: Vector2, act: bool) -> void:
		if act:
			acts += 1
		else:
			cancels += 1


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


func _drag(p: WorldPan, to: Vector2) -> void:
	var sd := InputEventScreenDrag.new()
	sd.index = 0
	sd.position = to
	p._input(sd)


func _stub(at: Vector2 = Vector2(540, 1200), prio: int = WorldPan.PRIO_BED, radius: float = 90.0) -> TargetStub:
	var s := TargetStub.new()
	s.centre = at
	s.prio = prio
	s.radius = radius
	add_child_autofree(s)
	s.add_to_group(WorldPan.GROUP_HIT)
	return s


func test_threshold_comes_from_the_project_setting() -> void:
	var p := _pan()
	var setting: int = ProjectSettings.get_setting("gui/common/drag_threshold")
	assert_eq(p.threshold_px, float(setting))
	assert_almost_eq(p.edge_px, 0.067 * 1080.0, 0.01, "24 dp edge band (spots safe_x)")
	assert_almost_eq(p.slop_px, WorldPan.SLOP_DP * 3.0, 0.01, "fat-finger slop ~9 dp")


func test_small_moves_stay_a_tap_that_fires_on_release() -> void:
	var p := _pan()
	var stub := _stub()
	watch_signals(p)
	_press(p, Vector2(540, 1200))
	assert_eq(stub.presses, 1, "touch-down feedback at once")
	assert_eq(stub.acts, 0, "the action waits for the release")
	_move(p, Vector2(540 + p.threshold_px - 2.0, 1200))
	assert_false(p.is_dragging(), "under the drag threshold")
	assert_eq(p.offset(), Vector2.ZERO, "the map has not moved")
	_press(p, Vector2(540 + p.threshold_px - 2.0, 1200), false)
	assert_signal_not_emitted(p, "drag_started")
	assert_eq(stub.acts, 1, "the tap fires on release")
	assert_eq(stub.cancels, 0)


## With input accumulated once per rendered frame, the first motion event of a flick reports a
## bigger step at 30 fps than at 60, so any pan that began at the slop boundary snapped ahead of
## the thumb by v * dt. The pan now begins where the finger is, so the first frame moves the map
## by nothing at all whatever the step, and the rest of the gesture is 1:1 either way.
func test_the_pan_never_jumps_at_the_start_whatever_the_first_step() -> void:
	for first: float in [30.0, 60.0, 100.0]:
		var p := _pan()
		_stub()
		_press(p, Vector2(540, 1200))
		_move(p, Vector2(540 - first, 1200))
		assert_true(p.is_dragging(), "a %d px first step starts the pan" % int(first))
		assert_almost_eq(p.offset().x, 0.0, 0.01, "and moves the map by nothing on that frame")
		_move(p, Vector2(540 - first - 50.0, 1200))
		assert_almost_eq(p.offset().x, 50.0, 0.01, "from there it is 1:1")


## Round 8: Android sends a cancelled touch as a release with canceled = true. Reading it as an
## ordinary release let a system gesture - the notification shade, the back swipe, an incoming
## call - fire a real world action as the finger was dragged off the screen.
func test_a_touch_the_os_cancels_fires_nothing() -> void:
	var p := _pan()
	var stub := _stub()
	_touch(p, Vector2(540, 1200), true)  # the touch path: a cancel only ever arrives there
	assert_eq(stub.presses, 1, "the press was taken as usual")
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.canceled = true
	up.position = Vector2(540, 1200)
	p._input(up)
	assert_eq(stub.acts, 0, "a cancelled touch is not a tap")
	assert_eq(stub.cancels, 1, "the pending tap is dropped")
	assert_false(p.is_dragging())


func test_drag_past_threshold_pans_and_cancels_the_tap() -> void:
	var p := _pan()
	var stub := _stub()
	watch_signals(p)
	_press(p, Vector2(540, 1200))
	_move(p, Vector2(540 - 40, 1200))
	assert_true(p.is_dragging())
	assert_signal_emitted(p, "drag_started")
	assert_eq(stub.cancels, 1, "the pending tap is dropped once")
	assert_almost_eq(p.offset().x, 0.0, 0.01, "the pan starts where the finger is: no jump")
	_move(p, Vector2(540 - 140, 1200))
	assert_almost_eq(p.offset().x, 100.0, 0.01, "then follows the finger 1:1")
	_press(p, Vector2(540, 1200), false)
	assert_false(p.is_dragging())
	assert_eq(stub.acts, 0, "no action after a drag, even released back on the target")
	assert_eq(stub.cancels, 1)


func test_a_stroke_on_a_drag_claiming_target_never_pans() -> void:
	var p := _pan()
	var stub := _stub(Vector2(540, 1200), WorldPan.PRIO_MOSSLING)
	stub.drag = true
	_press(p, Vector2(540, 1200))
	_move(p, Vector2(540 + 200, 1200))
	assert_false(p.is_dragging(), "the stroke pets, the map stays")
	assert_eq(p.offset(), Vector2.ZERO)
	assert_gt(stub.drags, 0, "the mossling follows the stroke")
	_press(p, Vector2(740, 1200), false)
	assert_eq(stub.acts, 1, "its release ends the pet (the mossling decides tap or pet)")
	_press(p, Vector2(300, 1200))
	_move(p, Vector2(300 + 200, 1200))
	assert_true(p.is_dragging(), "the claim ends with its pointer: empty ground pans")


func test_one_target_per_press_priority_then_nearest() -> void:
	var p := _pan()
	var bed := _stub(Vector2(540, 1200), WorldPan.PRIO_BED, 120.0)
	var prop := _stub(Vector2(600, 1200), WorldPan.PRIO_PROP, 96.0)
	var mossling := _stub(Vector2(470, 1200), WorldPan.PRIO_MOSSLING, 90.0)
	_press(p, Vector2(540, 1200))
	_press(p, Vector2(540, 1200), false)
	assert_eq(mossling.acts + prop.acts + bed.acts, 1, "exactly one target per press")
	assert_eq(mossling.acts, 1, "inside all three: the mossling outranks prop and bed (GDD §2.5)")
	# outside the mossling: the prop outranks the bed
	_press(p, Vector2(640, 1200))
	_press(p, Vector2(640, 1200), false)
	assert_eq(prop.acts, 1)
	assert_eq(bed.acts, 0)
	assert_eq(bed.presses + prop.presses + mossling.presses, 2, "losers never even get the press")
	# same priority: the nearer centre wins
	var lantern_a := _stub(Vector2(200, 800), WorldPan.PRIO_DECOR, 96.0)
	var lantern_b := _stub(Vector2(300, 800), WorldPan.PRIO_DECOR, 96.0)
	_press(p, Vector2(260, 800))
	_press(p, Vector2(260, 800), false)
	assert_eq(lantern_b.acts, 1, "nearest centre wins among overlapping pieces")
	assert_eq(lantern_a.acts, 0)


func test_a_direct_hit_beats_a_slop_hit_and_slop_reaches_small_misses() -> void:
	var p := _pan()
	var bed := _stub(Vector2(540, 1200), WorldPan.PRIO_BED, 60.0)
	var mossling := _stub(Vector2(540 + 60 + 90 + 15, 1200), WorldPan.PRIO_MOSSLING, 90.0)
	# 50 px right of the bed centre: inside the bed, 15 px outside the mossling (within slop)
	_press(p, Vector2(590, 1200))
	_press(p, Vector2(590, 1200), false)
	assert_eq(bed.acts, 1, "a target that contains the point beats a higher one reached by slop")
	assert_eq(mossling.acts, 0)
	# a fat-finger miss just outside every target still lands on the nearest
	var lone := _stub(Vector2(300, 600), WorldPan.PRIO_PROP, 96.0)
	_press(p, Vector2(300 + 96 + p.slop_px - 4.0, 600))
	_press(p, Vector2(300 + 96 + p.slop_px - 4.0, 600), false)
	assert_eq(lone.acts, 1, "within the slop ring")
	_press(p, Vector2(300 + 96 + p.slop_px + 6.0, 600))
	_press(p, Vector2(300 + 96 + p.slop_px + 6.0, 600), false)
	assert_eq(lone.acts, 1, "beyond the slop: empty ground")


func test_touch_aim_sits_a_little_above_the_contact() -> void:
	var p := _pan()
	var stub := _stub(Vector2(540, 1200), WorldPan.PRIO_PROP, 60.0)
	var below := 1200.0 + 60.0 + p.slop_px + p.aim_up_px - 2.0
	_touch(p, Vector2(540, below), true)
	_touch(p, Vector2(540, below), false)
	assert_eq(stub.acts, 1, "a touch that lands low still reaches the target above it")
	_press(p, Vector2(540, below))
	_press(p, Vector2(540, below), false)
	assert_eq(stub.acts, 1, "the mouse aims exactly where it points")


func test_touch_path_and_its_emulated_mouse_are_one_pointer() -> void:
	var p := _pan()
	var stub := _stub()
	# Input dispatches the emulated mouse twin BEFORE the touch itself
	var emu_down := InputEventMouseButton.new()
	emu_down.device = InputEvent.DEVICE_ID_EMULATION
	emu_down.button_index = MOUSE_BUTTON_LEFT
	emu_down.pressed = true
	emu_down.position = Vector2(540, 1200)
	p._unhandled_input(emu_down)
	assert_eq(stub.presses, 0, "the emulated twin is ignored")
	_touch(p, Vector2(540, 1200), true)
	assert_eq(stub.presses, 1)
	var emu_up := emu_down.duplicate() as InputEventMouseButton
	emu_up.pressed = false
	p._input(emu_up)
	assert_eq(stub.acts, 0, "the emulated release does not end the touch")
	_touch(p, Vector2(540, 1200), false)
	assert_eq(stub.acts, 1, "one action for the touch and its twin")
	assert_eq(stub.presses, 1)


func test_touch_drag_pans_and_ignores_the_emulated_motion_and_a_second_finger() -> void:
	var p := _pan()
	_touch(p, Vector2(540, 1200), true)
	var emu := InputEventMouseMotion.new()
	emu.device = InputEvent.DEVICE_ID_EMULATION
	emu.button_mask = MOUSE_BUTTON_MASK_LEFT
	emu.position = Vector2(540, 1500)
	p._input(emu)
	assert_false(p.is_dragging(), "emulated mouse events are ignored")
	_drag(p, Vector2(540, 1260))
	assert_true(p.is_dragging(), "the touch drag pans")
	assert_almost_eq(p.offset().y, 0.0, 0.01, "the pan starts where the finger is: no jump")
	_drag(p, Vector2(540, 1320))
	assert_almost_eq(p.offset().y, -60.0, 0.01, "dragging down rises into the sky, 1:1")
	var second := InputEventScreenDrag.new()
	second.index = 1
	second.position = Vector2(100, 100)
	p._input(second)
	assert_almost_eq(p.offset().y, -60.0, 0.01, "a second finger is ignored")
	_touch(p, Vector2(540, 1260), false)
	assert_false(p.is_dragging())


func test_no_pan_from_the_side_edges_but_taps_there_work() -> void:
	var p := _pan()
	var cairn := _stub(Vector2(40, 1300), WorldPan.PRIO_DECOR, 60.0)
	_press(p, Vector2(30, 1200))
	_move(p, Vector2(300, 1200))
	assert_false(p.is_dragging(), "24 dp edge band belongs to the OS back gesture")
	_press(p, Vector2(300, 1200), false)
	_press(p, Vector2(40, 1300))
	_press(p, Vector2(40, 1300), false)
	assert_eq(cairn.acts, 1, "a target in the edge band still takes its tap")
	_press(p, Vector2(40, 1300))
	_move(p, Vector2(140, 1300))
	_press(p, Vector2(140, 1300), false)
	assert_eq(cairn.acts, 1, "and a slide from it is no tap")


func test_nothing_through_an_open_sheet_or_card() -> void:
	var p := _pan()
	var stub := _stub()
	var sheet_open: Array[bool] = [true]
	p.blocked = func() -> bool: return sheet_open[0]
	_press(p, Vector2(540, 1200))
	_move(p, Vector2(300, 1200))
	assert_false(p.is_dragging(), "no panning while a sheet is open")
	_press(p, Vector2(300, 1200), false)
	assert_eq(stub.presses, 0, "no world tap through a sheet")
	sheet_open[0] = false
	_press(p, Vector2(540, 1200))
	sheet_open[0] = true  # a card rose during the press (new friend, recap)
	_press(p, Vector2(540, 1200), false)
	assert_eq(stub.acts, 0, "a card that opened mid-press takes the tap")
	assert_eq(stub.cancels, 1)
	sheet_open[0] = false
	_press(p, Vector2(540, 1200))
	_move(p, Vector2(300, 1200))
	assert_true(p.is_dragging())


func test_a_press_on_a_gliding_map_only_catches_it() -> void:
	var p := _pan()
	var stub := _stub()
	p.body.glide_to(Vector2(-200, 0))
	assert_true(p.body.is_moving(), "the map glides (after a fling or a home glide)")
	_press(p, Vector2(540, 1200))
	assert_false(p.body.is_moving(), "the press stops the glide")
	_press(p, Vector2(540, 1200), false)
	assert_eq(stub.presses + stub.acts, 0, "and does nothing else: no tap after a fling")
	_press(p, Vector2(540, 1200))
	_press(p, Vector2(540, 1200), false)
	assert_eq(stub.acts, 1, "the next tap on the resting map works")


func test_long_press_target_keeps_its_press_and_cancel_drops_it() -> void:
	var p := _pan()
	var stub := _stub()
	_press(p, Vector2(540, 1200))
	assert_eq(p.target(), stub)
	p.cancel()  # a sheet opened / the app was suspended
	assert_eq(stub.cancels, 1)
	_press(p, Vector2(540, 1200), false)
	assert_eq(stub.acts, 0, "nothing fires after the cancel")


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
		_press(p, Vector2(540, 1200), false)
	assert_true(p.body.is_moving(), "gliding home")
	var t := 0.0
	while p.body.step(DT) and t < 5.0:
		t += DT
	assert_almost_eq(p.offset().length(), 0.0, 0.5)
	# taps on objects never count
	var stub := _stub()
	p.body.snap(Vector2(200, -300))
	for i in 2:
		_press(p, Vector2(540, 1200))
		_press(p, Vector2(540, 1200), false)
	assert_false(p.body.is_moving())
	assert_eq(stub.acts, 2)
