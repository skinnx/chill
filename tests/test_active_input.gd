extends GutTest
## Active Play v1 input arbiter additions (GDD §14.11 a6, docs/ARCHITECTURE.md §3.5): a pressed
## target may claim the drag mid-press (the décor long-press: the same finger carries the piece, no
## pan starts), empty taps report their position (Active F3 destinations), edit mode asks only the
## world_hit_edit group (everything else is ground), Game's edit signals drive it, and nudge() pans
## inside the rest bounds. Driven through real input dispatch in a SubViewport.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")
@warning_ignore_start("unsafe_method_access")

const SCREEN := Vector2(1080, 2400)
const PIECE_AT := Vector2(540, 1200)


## A world target in a group, with a 90 px circle at [member at].
class Target:
	extends Node
	var at := PIECE_AT
	var prio: int = WorldPan.PRIO_STILL
	var presses: int = 0
	var acts: int = 0
	var drags: int = 0
	var released: int = 0

	func world_hit(p: Vector2, slop: float) -> Dictionary:
		return WorldPan.circle_hit(p, at, 90.0, slop, prio, &"piece")

	func world_press(_key: Variant, _p: Vector2) -> void:
		presses += 1

	func world_drag(_key: Variant, _p: Vector2) -> void:
		drags += 1

	func world_release(_key: Variant, _p: Vector2, act: bool) -> void:
		released += 1
		if act:
			acts += 1


var _vp: SubViewport
var _pan: WorldPan
var _play: Target
var _edit: Target
var _saved_sim: WorldSim
var _saved_ready: bool
var _saved_content: GameContent


func before_each() -> void:
	_saved_sim = Game.sim
	_saved_ready = Game.is_ready
	_saved_content = Game.content
	Game.content = ContentRegistry.content
	Game.sim = WorldSim.new_game(ContentRegistry.content, 4711, Clock.now_unix(), 0.0)
	Game.is_ready = true
	_vp = SubViewport.new()
	_vp.size = Vector2i(SCREEN)
	add_child_autofree(_vp)
	_pan = WorldPan.new()
	_pan.configure({}, {"px_per_dp": 3, "width_px": 1080}, {"x0": 0.067})
	_pan.view_width = SCREEN.x
	_pan.body.set_bounds(Rect2(-300, -200, 600, 400), Rect2(-400, -300, 800, 600))
	_play = Target.new()
	_play.add_to_group(WorldPan.GROUP_HIT)
	add_child_autofree(_play)
	_edit = Target.new()
	_edit.prio = WorldPan.PRIO_EDIT
	_edit.at = PIECE_AT + Vector2(300, 0)
	_edit.add_to_group(WorldPan.GROUP_HIT_EDIT)
	add_child_autofree(_edit)
	_vp.add_child(_pan)


func after_each() -> void:
	Game.sim.active.edit_mode = false
	Game.sim = _saved_sim
	Game.is_ready = _saved_ready
	Game.content = _saved_content


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


func test_claim_drag_mid_press_carries_the_piece_and_never_pans() -> void:
	_touch(PIECE_AT, true)
	assert_eq(_play.presses, 1)
	assert_true(_pan.claim_drag(), "the long-press fired while the finger was still in the slop")
	var pan0 := _pan.offset()
	for i in 6:
		_drag(PIECE_AT + Vector2(40.0 * (i + 1), 10.0 * i))
	assert_gt(_play.drags, 4, "later motion arrives as world_drag")
	assert_false(_pan.is_dragging(), "no pan starts")
	assert_eq(_pan.offset(), pan0)
	_touch(PIECE_AT + Vector2(240, 50), false)
	assert_eq(_play.acts, 1, "the release fires (the drop)")
	assert_false(_pan.claim_drag(), "nothing to claim without a press")


func test_without_a_claim_a_drag_cancels_the_tap_and_pans() -> void:
	_touch(PIECE_AT, true)
	for i in 6:
		_drag(PIECE_AT + Vector2(40.0 * (i + 1), 0.0))
	assert_true(_pan.is_dragging(), "a drag before the long-press still pans")
	assert_eq(_play.drags, 0)
	_touch(PIECE_AT + Vector2(240, 0), false)
	assert_eq(_play.acts, 0, "no action after a drag")


func test_empty_taps_report_their_position() -> void:
	watch_signals(_pan)
	var at := Vector2(200, 600)
	_touch(at, true)
	_touch(at, false)
	assert_signal_emitted_with_parameters(_pan, "empty_tapped", [at])
	_touch(PIECE_AT, true)
	_touch(PIECE_AT, false)
	assert_signal_emit_count(_pan, "empty_tapped", 1, "a target tap is not an empty tap")


func test_edit_mode_asks_only_the_edit_group() -> void:
	assert_eq(_pan.resolve(PIECE_AT).get("layer"), _play)
	assert_true(_pan.resolve(_edit.at).is_empty(), "edit targets are not play targets")
	Game.set_edit_mode(true)
	assert_true(_pan.edit_mode, "Game's decor_edit_entered drives the arbiter")
	assert_true(_pan.resolve(PIECE_AT).is_empty(), "in edit mode everything else is ground")
	assert_eq(_pan.resolve(_edit.at).get("layer"), _edit)
	Game.set_edit_mode(false)
	assert_false(_pan.edit_mode)
	assert_eq(_pan.resolve(PIECE_AT).get("layer"), _play)


func test_nudge_pans_inside_the_rest_bounds() -> void:
	_pan.nudge(Vector2(100, 0))
	assert_eq(_pan.offset(), Vector2(100, 0))
	_pan.nudge(Vector2(10000, 0))
	assert_eq(_pan.offset().x, 300.0, "never past the rest bounds (no rubber band)")


func test_priorities_of_the_active_targets() -> void:
	assert_eq(WorldPan.PRIO_PETAL_BED, WorldPan.PRIO_READY_BED, "a bed with petals ranks like a ready bud")
	assert_eq(WorldPan.PRIO_TEA_NOOK, WorldPan.PRIO_PROP)
	assert_eq(WorldPan.PRIO_STILL, WorldPan.PRIO_STREAM, "still pieces never outrank a bed, a prop or a friend")
	assert_gt(WorldPan.PRIO_EDIT, WorldPan.PRIO_CHOOSE_BED, "edit pieces outrank every play target")
	var dp: Dictionary = ContentRegistry.content.decor_placement["hit"]
	assert_eq(WorldPan.PRIO_EDIT, int(dp["prio_edit_piece"]))
	assert_eq(WorldPan.PRIO_EDIT_SELECTED, WorldPan.PRIO_EDIT + int(dp["prio_edit_selected_bonus"]))
	assert_eq(WorldPan.PRIO_STILL, int(dp["prio_still_piece_play"]))
	assert_eq(WorldPan.PRIO_PETAL_BED, int(ContentRegistry.content.tea["harvest"]["bed_hit_prio_with_petals"]))
	assert_eq(WorldPan.PRIO_TEA_NOOK, int(ContentRegistry.content.tea["nook"]["hit_prio"]))
