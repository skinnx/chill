extends GutTest
## Active F3 free décor placement, the view side (docs/gdd/ACTIVE_DECOR.md §2-§11, GDD §14.1;
## DecorLayer, DecorEdit, DecorEditChrome / Tray, WorldPan additions). Pure helpers (band merging,
## carry offset, edge pan, lean, chip placement, edit hit sizes) and the live controller against a
## real sim and the real arbiter in a SubViewport: pieces stand where the layout says and render
## their turn, still pieces are prio-1 targets that wobble and report decor_tap, a long-press enters
## edit mode with the piece already carried by the same finger, a drag before it still pans, a drop
## settles (one decor_placed, never mid-drag) or floats home, tap-then-tap glides, turn / put away /
## take out / lift a pebble / undo commit, leaving edit mode settles a held piece first, the draw
## budget merges bands, and nothing changes for taps and pans outside edit mode.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")
@warning_ignore_start("unsafe_method_access")

const SCREEN := Vector2(1080, 1920)
const FRAME_S := 1.0 / 30.0

var c: GameContent
var _vp: SubViewport
var _pan: WorldPan
var _layer: DecorLayer
var _saved_sim: WorldSim
var _saved_ready: bool
var _saved_content: GameContent
var _placed: Array = []


func before_all() -> void:
	c = ContentRegistry.content


func before_each() -> void:
	_saved_sim = Game.sim
	_saved_ready = Game.is_ready
	_saved_content = Game.content
	Game.content = c
	Game.sim = WorldSim.new_game(c, 777, Clock.now_unix(), 0.0)
	GardenFixture.apply(c, Game.sim.state, GardenFixture.MID)
	Game.sim = WorldSim.new(c, Game.sim.state)  # migrates the décor from the anchors
	Game.sim.drain_events()
	Game.is_ready = true
	_placed.clear()
	Game.decor_placed.connect(_on_placed)
	_vp = SubViewport.new()
	_vp.size = Vector2i(SCREEN)
	add_child_autofree(_vp)
	_pan = WorldPan.new()
	_pan.configure({}, {"px_per_dp": 3, "width_px": 1080}, {"x0": 0.067})
	_pan.view_width = SCREEN.x
	_pan.body.set_bounds(Rect2(-300, -200, 600, 400), Rect2(-400, -300, 800, 600))
	_layer = (load("res://scenes/garden/decor_layer.tscn") as PackedScene).instantiate()
	_vp.add_child(_layer)
	_vp.add_child(_pan)


func after_each() -> void:
	if Game.decor_placed.is_connected(_on_placed):
		Game.decor_placed.disconnect(_on_placed)
	if Game.sim != null and Game.sim.active.edit_mode:
		Game.sim.active.set_edit_mode(Game.sim, false)
	Game.sim = _saved_sim
	Game.is_ready = _saved_ready
	Game.content = _saved_content
	LampRegistry.clear()


func _on_placed(set_id: StringName, piece_id: String, pos: Vector2, rot_deg: int) -> void:
	_placed.append([set_id, piece_id, pos, rot_deg])


func _tick(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		_layer._process(FRAME_S)
		_layer.edit._process(FRAME_S)
		t += FRAME_S


func _touch(at: Vector2, pressed: bool) -> void:
	var st := InputEventScreenTouch.new()
	st.index = 0
	st.pressed = pressed
	st.position = at
	_vp.push_input(st)


func _drag(at: Vector2) -> void:
	var sd := InputEventScreenDrag.new()
	sd.index = 0
	sd.position = at
	_vp.push_input(sd)


## Carries from [param from] to [param to] in canvas px in [param steps] moves (the edit
## controller steps between moves).
func _carry(from: Vector2, to: Vector2, steps: int = 8) -> void:
	for i in steps:
		_drag(from.lerp(to, float(i + 1) / float(steps)))
		_tick(FRAME_S * 2.0)


func _piece(set_id: StringName, n: int = 0) -> DecorLayer.Piece:
	var list: Array[DecorLayer.Piece] = []
	for p: DecorLayer.Piece in _layer.movable_pieces():
		if p.decor == set_id:
			list.append(p)
	list.sort_custom(func(a: DecorLayer.Piece, b: DecorLayer.Piece) -> bool: return a.index < b.index)
	return list[n] if n < list.size() else null


func _rec(id: String) -> Dictionary:
	for r: Dictionary in Game.decor_layout():
		if String(r["id"]) == id:
			return r
	return {}


func _norm(design: Vector2) -> Vector2:
	return Vector2(design.x / 1080.0, design.y / 1920.0)


func _px(n: Vector2) -> Vector2:
	return GardenRules.frame_to_px(c, n)


## A valid free spot for [param set_id] near the meadow's middle (searched with the real rules).
func _valid_spot(set_id: StringName, ignore: String) -> Vector2:
	var rules := Game.decor_rules()
	var layout := Game.sim.state.decor_layout
	var ctx := Game.decor_context()
	for yi in range(10, 60):
		for xi in range(4, 30):
			var q := Vector2(float(xi) / 33.0, 0.40 + float(yi) * 0.006)
			if rules.validate(set_id, q, layout, ctx, ignore) == DecorPlacementRules.VALID \
					and rules.snap(set_id, q, layout, ctx, ignore)["socket"] == false:
				return q
	return Vector2.INF


# ================================================================= pure helpers

func test_band_groups_merge_nearest_bands_down_to_the_budget() -> void:
	var g := DecorLayer.band_groups({&"a": [1, 2, 9, 10, 30], &"b": [4]}, 4)
	var total := 0
	var seen: Array = []
	for s: Variant in g:
		total += (g[s] as Array).size()
		for grp: Array in g[s]:
			seen.append_array(grp)
	assert_eq(total, 4, "merged down to the budget")
	seen.sort()
	assert_eq(seen, [1, 2, 4, 9, 10, 30], "every band is still drawn")
	assert_eq((g[&"a"] as Array)[0], [1, 2], "the nearest neighbours merge first")
	var none := DecorLayer.band_groups({&"a": [1, 5]}, 10)
	assert_eq((none[&"a"] as Array).size(), 2, "under the budget nothing merges")
	var floor := DecorLayer.band_groups({&"a": [1, 5], &"b": [2], &"c": [3]}, 1)
	assert_eq((floor[&"a"] as Array).size(), 1, "never fewer than one stamp per set")


func test_carry_offset_eases_the_foot_above_the_finger() -> void:
	var grab := Vector2(10.0, 30.0)
	assert_eq(DecorEdit.carry_offset(grab, 72.0, 0.0, 0.12), grab, "at the press the piece does not jump")
	assert_eq(DecorEdit.carry_offset(grab, 72.0, 0.2, 0.12), Vector2(0.0, -72.0), "then 24 dp above the contact")
	var mid := DecorEdit.carry_offset(grab, 72.0, 0.06, 0.12)
	assert_between(mid.y, -72.0, 30.0)


## Round 9: the foot rings are tessellated to a pixel tolerance instead of a flat 40 segments.
## Every ring of every movable piece is rebuilt on every frame edit mode is open, and at 40
## segments the chords sat 0.09-0.22 px from the true curve inside a 6 px stroke - invisible
## oversampling, paid for per piece per frame.
func test_ring_tessellation_follows_the_ring_size() -> void:
	for r: float in [30.0, 46.2, 71.3]:
		var n := DecorEdit.ellipse_segments(r)
		assert_between(n, DecorEdit.RING_SEGS_MIN, DecorEdit.RING_SEGS_MAX,
				"%d segments for a %d px ring" % [n, int(r)])
		var sagitta := r * (1.0 - cos(PI / float(n)))
		assert_lte(sagitta, DecorEdit.RING_TOL_PX + 1e-6, "within the tolerance at %d px" % int(r))
		var coarser := r * (1.0 - cos(PI / float(n - 1)))
		assert_true(n == DecorEdit.RING_SEGS_MIN or coarser > DecorEdit.RING_TOL_PX,
				"and no more segments than it needs")
	assert_lt(DecorEdit.ellipse_segments(30.0), 40, "the common sets cost far less than the old flat 40")
	var pts := DecorEdit._ellipse_points(Vector2.ZERO, Vector2(30.0, 12.0))
	assert_eq(pts.size(), DecorEdit.ellipse_segments(30.0) + 1, "closed ring: n + 1 points")
	assert_almost_eq(pts[0].distance_to(pts[pts.size() - 1]), 0.0, 1e-5, "and it closes")


func test_edge_pan_waits_eases_in_and_halves_under_reduce_motion() -> void:
	assert_eq(DecorEdit.edge_pan_speed(10.0, 1080.0, 120.0, 660.0, 0.1, 0.25, false), 0.0, "waits 250 ms")
	var left := DecorEdit.edge_pan_speed(10.0, 1080.0, 120.0, 660.0, 0.5, 0.25, false)
	assert_lt(left, 0.0, "toward the left edge")
	assert_gt(DecorEdit.edge_pan_speed(1075.0, 1080.0, 120.0, 660.0, 0.5, 0.25, false), 0.0)
	assert_eq(DecorEdit.edge_pan_speed(540.0, 1080.0, 120.0, 660.0, 5.0, 0.25, false), 0.0, "nothing mid-screen")
	assert_lt(absf(DecorEdit.edge_pan_speed(100.0, 1080.0, 120.0, 660.0, 0.5, 0.25, false)), absf(left),
			"slower near the zone's inner edge (ease-in)")
	assert_almost_eq(DecorEdit.edge_pan_speed(10.0, 1080.0, 120.0, 660.0, 0.5, 0.25, true), left * 0.5, 1e-4)
	assert_true(absf(left) <= 660.0)


func test_lean_is_capped_and_chip_avoids_the_hint_row() -> void:
	assert_almost_eq(DecorEdit.lean_for(10000.0, 6.0), deg_to_rad(6.0), 1e-6)
	assert_almost_eq(DecorEdit.lean_for(-10000.0, 6.0), -deg_to_rad(6.0), 1e-6)
	var above := DecorEdit.chip_rect(Vector2(540, 1200), Vector2(540, 1300), Vector2(400, 240), 36.0, 448.0,
			Vector2(24, 1056), 1480.0)
	assert_eq(above.end.y, 1200.0 - 36.0, "36 px above the piece's top")
	var below := DecorEdit.chip_rect(Vector2(540, 500), Vector2(540, 560), Vector2(400, 240), 36.0, 448.0,
			Vector2(24, 1056), 1480.0)
	assert_eq(below.position.y, 560.0 + 36.0, "under the foot when above would cross the hint row")
	var edge := DecorEdit.chip_rect(Vector2(1070, 1200), Vector2(1070, 1300), Vector2(400, 240), 36.0, 448.0,
			Vector2(24, 1056), 1480.0)
	assert_eq(edge.end.x, 1056.0, "clamped inside the side margin")
	var hit: Dictionary = c.decor_placement["hit"]
	assert_eq(DecorEdit.edit_hit_dp(0.3, hit, Vector2(0.175, 0.44)), 64.0, "64 dp in the look zone")
	assert_eq(DecorEdit.edit_hit_dp(0.6, hit, Vector2(0.175, 0.44)), 60.0, "60 dp in the tend zone")


# ================================================================= the view follows the layout

func test_pieces_stand_where_the_layout_says_and_stored_ones_leave() -> void:
	for r: Dictionary in Game.decor_layout():
		if String(r["set"]) == "pebble_cairn" and String(r["stack"]) != "":
			continue
		var p := _layer.piece(String(r["id"]))
		assert_not_null(p, "%s is drawn" % r["id"])
		if p != null:
			assert_almost_eq(p.foot.distance_to(_px(Vector2(float(r["x"]), float(r["y"])))), 0.0, 0.01)
	var tc := _piece(DecorLayer.TOADSTOOL)
	var to := _valid_spot(DecorLayer.TOADSTOOL, tc.id)
	assert_ne(to, Vector2.INF)
	var res := Game.move_decor(tc.id, to)
	assert_true(bool(res["ok"]))
	assert_almost_eq(tc.foot.distance_to(_px(res["pos"] as Vector2)), 0.0, 0.01, "the layer follows a commit")
	var stone := _piece(DecorLayer.STONES)
	var n := _layer.piece_count(DecorLayer.STONES)
	assert_true(Game.store_decor(stone.id))
	assert_null(_layer.piece(stone.id), "a stored piece leaves the hollow")
	assert_eq(_layer.piece_count(DecorLayer.STONES), n - 1)
	assert_eq(Game.sim.owned_count(&"stream_stones"), n, "and still counts as owned")


func test_turn_steps_render_flip_and_three_quarter_views() -> void:
	var pw := _piece(DecorLayer.PINWHEEL)
	assert_eq(pw.flip, 1.0)
	assert_eq(Game.turn_decor(pw.id), 1)
	assert_almost_eq(pw.squash_x, 0.72, 1e-6, "3/4 right squashes the pinwheel")
	Game.turn_decor(pw.id)
	assert_eq(pw.variant, 1, "the back face swaps the blades")
	Game.turn_decor(pw.id)
	assert_eq(pw.flip, -1.0, "3/4 left mirrors")
	assert_lt(pw.node.scale.x, 0.0, "the pinwheel's own node carries the turn")
	var lantern := _piece(DecorLayer.LANTERN)
	var hx := lantern.head_pivot.x
	Game.turn_decor(lantern.id)
	assert_almost_eq(lantern.head_pivot.x, -hx, 1e-4, "the crook faces the other way, the jar hangs on it")


func test_still_pieces_are_prio_one_targets_that_wobble_and_report_a_tap() -> void:
	var stone := _piece(DecorLayer.STONES)
	var cand := _layer.world_hit(_layer.to_canvas(stone.hit), _pan.slop_px)
	assert_eq(int(cand["prio"]), WorldPan.PRIO_STILL)
	var pw := _piece(DecorLayer.PINWHEEL)
	assert_eq(int(_layer.world_hit(_layer.to_canvas(pw.hit), _pan.slop_px)["prio"]), WorldPan.PRIO_DECOR)
	var at := _layer.to_canvas(stone.hit)
	_touch(at, true)
	assert_lt(stone.press.target, 1.0, "touch-down squash in the same frame")
	_touch(at, false)
	assert_eq(stone.press.target, 1.0, "released: it springs back (the wobble)")
	assert_false(Game.edit_mode(), "a tap never opens edit mode")


# ================================================================= long-press, carry, drop

func test_long_press_enters_edit_mode_with_the_piece_carried_by_the_same_finger() -> void:
	var tc := _piece(DecorLayer.TOADSTOOL)
	var id := tc.id
	var to := _valid_spot(DecorLayer.TOADSTOOL, id)
	var at := _layer.to_canvas(tc.hit)
	_touch(at, true)
	_tick(0.2)
	assert_false(Game.edit_mode(), "not before 450 ms")
	assert_true(_layer._fill.visible, "the ring fill runs from 150 ms")
	_tick(0.3)
	assert_true(Game.edit_mode(), "the long-press opened edit mode")
	assert_true(_pan.edit_mode, "the arbiter follows")
	assert_true(tc.held, "the piece is already lifted")
	var pan0 := _pan.offset()
	var finger_to := _layer.to_canvas(_px(to)) + Vector2(0.0, DecorEdit.CARRY_DP * 3.0)
	_carry(at, finger_to, 10)
	_tick(0.2)
	assert_eq(_pan.offset(), pan0, "carrying never pans")
	assert_eq(_placed.size(), 0, "decor_placed never fires mid-drag")
	_touch(finger_to, false)
	assert_eq(_placed.size(), 1, "one decor_placed after the drop")
	_tick(0.6)
	var rec := _rec(id)
	assert_lt(_px(Vector2(float(rec["x"]), float(rec["y"]))).distance_to(_px(to)), 3.0 * 6.0,
			"it settled where it was carried (within the jitter and magnet)")
	assert_false(tc.held, "and is set down")
	assert_true(Game.edit_mode(), "edit mode stays open until Done")


## Round 8: the carry is re-anchored on the frame it starts, exactly as the map pan is. Without
## that the piece catches up the whole 24 px slop in one frame (a visible sideways pop on every
## pick-up) and the first velocity sample divides that slop by one frame delta, slamming the lean
## to its 6 deg cap - so a slow, careful lift began with a flinch (ACTIVE_DECOR §3.3: no shake).
func test_the_carry_starts_without_a_pop_or_a_lean_kick() -> void:
	var edit: DecorEdit = _layer.edit
	edit.enter(false)
	_tick(0.1)
	var tc := _piece(DecorLayer.TOADSTOOL)
	var at := _layer.to_canvas(tc.hit)
	_touch(at, true)
	_tick(FRAME_S)
	var before: Vector2 = edit._raw_foot
	# One slow drag just past the slop: the frame the carry begins.
	var step := Vector2(_pan.threshold_px + 2.0, 0.0)
	_drag(at + step)
	_tick(FRAME_S)
	# Measured on x alone: the slop was horizontal, while the carry's own 24 dp rise is vertical.
	var slop_design: float = _layer.to_design(step).length()
	assert_lt(absf(edit._raw_foot.x - before.x), slop_design * 0.4,
			"the foot stays where it was drawn instead of catching up the swallowed slop")
	var cap := deg_to_rad(6.0)  # decor_placement.json pick.lean_max_deg
	assert_lt(absf(edit._lean.target), cap * 0.5, "and a slow lift does not slam the lean to its cap")


func test_a_drag_before_the_long_press_pans_and_never_enters_edit_mode() -> void:
	var tc := _piece(DecorLayer.TOADSTOOL)
	var at := _layer.to_canvas(tc.hit)
	_touch(at, true)
	_tick(0.1)
	for i in 6:
		_drag(at + Vector2(40.0 * (i + 1), 0.0))
	assert_true(_pan.is_dragging(), "the map pans")
	_tick(0.6)
	assert_false(Game.edit_mode(), "the cancelled press never becomes a long-press")
	_touch(at + Vector2(240, 0), false)
	assert_false(tc.held)


func test_an_invalid_drop_floats_home_and_changes_nothing() -> void:
	var edit := _layer.edit
	assert_true(edit.enter(false))
	var tc := _piece(DecorLayer.TOADSTOOL)
	var before := _rec(tc.id).duplicate()
	var at := _layer.to_canvas(_layer.visual_centre_of(tc))
	_touch(at, true)
	assert_true(tc.held, "edit press lifts at once")
	var sky := _layer.to_canvas(Vector2(540.0, 200.0))
	_carry(at, sky, 8)
	assert_false(edit._valid, "over the sky: invalid")
	_touch(sky, false)
	_tick(0.6)
	assert_eq(_rec(tc.id), before, "floated home: nothing changed")
	assert_eq(_placed.size(), 0, "and nothing was placed")
	assert_false(Game.can_undo_decor(), "nothing to undo")


func test_tap_then_tap_glides_and_undo_restores_one_step() -> void:
	var edit := _layer.edit
	edit.enter(false)
	var lantern := _piece(DecorLayer.LANTERN)
	var before := _rec(lantern.id).duplicate()
	var at := _layer.to_canvas(_layer.visual_centre_of(lantern))
	_touch(at, true)
	_touch(at, false)
	assert_eq(edit.selected, lantern.id, "a tap selects")
	_tick(FRAME_S)
	assert_false(_pan.double_tap_home, "no double-tap home while a piece is selected")
	var to := _valid_spot(DecorLayer.LANTERN, lantern.id)
	var tap := _layer.to_canvas(_px(to))
	_touch(tap, true)
	_touch(tap, false)
	assert_eq(edit.selected, "", "the selection is used")
	_tick(0.6)
	var rec := _rec(lantern.id)
	assert_lt(Vector2(float(rec["x"]), float(rec["y"])).distance_to(to), 0.05, "it glided to the tapped spot")
	assert_true(Game.can_undo_decor())
	edit._on_undo()
	_tick(0.6)
	assert_eq(_rec(lantern.id), before, "undo puts it back")
	assert_false(Game.can_undo_decor(), "one step only")


func test_turn_put_away_take_out_and_lift_a_pebble() -> void:
	var edit := _layer.edit
	edit.enter(false)
	var pw := _piece(DecorLayer.PINWHEEL)
	edit._select(pw.id)
	edit._on_turn()
	assert_eq(int(_rec(pw.id)["rot"]), 1, "Turn advances one step")
	edit._on_put_away()
	_tick(0.6)
	assert_true(bool(_rec(pw.id)["stored"]), "Put away tucks it into the tray")
	assert_null(_layer.piece(pw.id))
	edit._on_tile_tapped(DecorLayer.PINWHEEL)
	assert_eq(edit.hand_set, DecorLayer.PINWHEEL, "a tile tap puts it in hand")
	edit._on_find_spot()
	assert_false(bool(_rec(pw.id)["stored"]), "Find a spot sets it down on valid ground")
	assert_not_null(_layer.piece(pw.id))
	var cairn := _piece(DecorLayer.CAIRN)
	var n := cairn.pebbles.size()
	assert_gt(n, 1, "garden_mid has a stack")
	edit._select(cairn.id)
	edit._on_lift_pebble()
	assert_eq(cairn.pebbles.size(), n - 1, "the stack is a pebble lower")
	assert_ne(edit.selected, "", "the lifted pebble is in hand")
	assert_ne(edit.selected, cairn.id)


func test_leaving_edit_mode_settles_a_held_piece_first() -> void:
	var edit := _layer.edit
	edit.enter(false)
	var tc := _piece(DecorLayer.TOADSTOOL)
	var id := tc.id
	var to := _valid_spot(DecorLayer.TOADSTOOL, id)
	var at := _layer.to_canvas(_layer.visual_centre_of(tc))
	_touch(at, true)
	_carry(at, _layer.to_canvas(_px(to)) + Vector2(0.0, DecorEdit.CARRY_DP * 3.0), 8)
	# the app pauses mid-drag: Game leaves edit mode (its save runs after this)
	Game.sim.active.set_edit_mode(Game.sim, false)
	Game.sim_event.emit({"type": WorldSim.EV_DECOR_EDIT, "on": false})
	Game.decor_edit_exited.emit()
	assert_false(edit.active)
	assert_eq(_placed.size(), 1, "the carried piece was committed before leaving")
	assert_false(tc.held)
	_touch(at, false)


func test_the_tray_drag_takes_a_stored_piece_out() -> void:
	var edit := _layer.edit
	edit.enter(false)
	var stone := _piece(DecorLayer.STONES)
	var id := stone.id
	assert_true(Game.store_decor(id))
	_layer.refresh()
	var from := _layer.to_canvas(Vector2(540.0, 1700.0))
	edit._on_tray_drag_start(DecorLayer.STONES, from)
	assert_eq(edit._mode, DecorEdit.Mode.HELD, "a tile dragged out is a held piece")
	var water := _layer.to_canvas(_px(Vector2(0.62, 0.77))) + Vector2(0.0, DecorEdit.CARRY_DP * 3.0)
	for i in 6:
		edit._on_tray_drag_move(from.lerp(water, float(i + 1) / 6.0))
		_tick(FRAME_S * 2.0)
	edit._on_tray_drag_end(water)
	_tick(0.6)
	assert_false(bool(_rec(id)["stored"]), "set down in the water")
	assert_not_null(_layer.piece(id))


func test_full_garden_decor_stays_inside_the_draw_budget() -> void:
	GardenFixture.apply(c, Game.sim.state, GardenFixture.FULL)
	Game.sim = WorldSim.new(c, Game.sim.state)
	Game.sim.drain_events()
	_layer.refresh()
	var stamps := 0
	for n: Node in _layer.get_children():
		for m: Node in n.get_children():
			if m is MeshInstance2D:
				stamps += 1
	var cap := int(c.decor_placement["draw"]["decor_draw_calls_max"])
	assert_lte(stamps, cap, "décor stamps <= %d (pinwheels + bands + chimes)" % cap)
	var quads := 0
	for key: String in _layer._units:
		if key.begins_with("firefly_lantern|"):
			var u: DecorLayer.Unit = _layer._units[key]
			quads += (u.stamp.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector2Array).size() / 4
	assert_eq(quads, _layer.piece_count(DecorLayer.LANTERN) * 3, "every lantern is 3 quads of its band's stamp")


func test_done_leaves_edit_mode_once_and_the_world_is_plain_again() -> void:
	var edit := _layer.edit
	watch_signals(edit)
	assert_true(edit.enter(true))
	assert_true(_pan.edit_mode)
	var lantern := _piece(DecorLayer.LANTERN)
	edit._select(lantern.id)
	edit.exit()
	assert_signal_emit_count(edit, "exited", 1, "one exit")
	assert_false(Game.edit_mode())
	assert_false(_pan.edit_mode, "the arbiter asks the play targets again")
	assert_true(_pan.double_tap_home)
	assert_false(lantern.held, "the selection is set down")
	assert_true(_layer.edit.world_hit(_layer.to_canvas(lantern.hit), _pan.slop_px).is_empty(),
			"no edit targets outside edit mode")
	var at := _layer.to_canvas(lantern.hit)
	_touch(at, true)
	_touch(at, false)
	assert_true(lantern.boost_t >= 0.0, "a lantern tap brightens it as before")
