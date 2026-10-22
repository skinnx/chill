extends GutTest
## Input & hit-testing contract (docs/ARCHITECTURE.md §3.5, GDD §8.2, §8.4). Round 7: the owner,
## on a 720x1600 Android phone, "often mis-taps" in the world, on the dock, inside sheets, and
## sees taps go THROUGH sheets and the top bar into the world. Every test drives real GUI dispatch
## in a SubViewport with the pair a phone sends for one finger (the emulated mouse twin first, then
## the InputEventScreenTouch), so double handling, through-taps and missed cancels show up here.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")
@warning_ignore_start("unsafe_method_access")

const SCREEN := Vector2(1080, 2400)
const SAFE_TOP := 72.0
const SAFE_BOTTOM := 127.0
const SEED := 2207


## A world layer whose one target covers the whole screen: anything that reaches the world lands.
class WorldStub:
	extends Node
	var presses: int = 0
	var acts: int = 0

	func world_hit(_p: Vector2, _slop: float) -> Dictionary:
		return {"prio": WorldPan.PRIO_BED, "inside": true, "d": 0.0, "key": &"all"}

	func world_press(_key: Variant, _p: Vector2) -> void:
		presses += 1

	func world_release(_key: Variant, _p: Vector2, act: bool) -> void:
		if act:
			acts += 1


var c: GameContent
var _saved_sim: WorldSim
var _saved_ready: bool
var _saved_content: GameContent
var _saved_persist: bool
var _vp: SubViewport
var _root: Control
var _pan: WorldPan
var _world: WorldStub
var _sheets: SheetHost
var _dock: DockView
var _top: TopBarView
var _overlays: OverlayHost


func before_all() -> void:
	c = ContentRegistry.content


func before_each() -> void:
	_saved_sim = Game.sim
	_saved_ready = Game.is_ready
	_saved_content = Game.content
	_saved_persist = Settings.persist
	Settings.persist = false
	Game.content = c
	Game.sim = WorldSim.new_game(c, SEED, Clock.now_unix(), 0.0)
	Game.sim.state.dew = 500
	Game.is_ready = true


func after_each() -> void:
	Settings.persist = _saved_persist
	Game.sim = _saved_sim
	Game.is_ready = _saved_ready
	Game.content = _saved_content


# ------------------------------------------------------------------ harness

## A phone-sized SubViewport with the real HUD pieces (top bar, dock, sheet host, overlays) wired as
## HudController wires them, and WorldPan + a whole-screen world target behind them.
func _hud() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SCREEN)
	_vp.gui_disable_input = false
	add_child_autofree(_vp)
	_pan = WorldPan.new()
	_pan.configure({}, {"px_per_dp": 3, "width_px": 1080}, {"x0": 0.067})
	_pan.view_width = SCREEN.x
	_world = WorldStub.new()
	_world.add_to_group(WorldPan.GROUP_HIT)
	add_child_autofree(_world)
	var layer := CanvasLayer.new()
	layer.layer = 10
	_vp.add_child(layer)
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.theme
	_root.size = SCREEN
	layer.add_child(_root)
	_sheets = SheetHost.new()
	_sheets.factory = func(id: StringName) -> UiSheet:
		match id:
			&"garden":
				return GardenSheet.new()
			&"basket":
				return BasketSheet.new()
			&"settings":
				return SettingsSheet.new()
		return AlbumSheet.new()
	_root.add_child(_sheets)
	_top = TopBarView.new()
	_sheets.chrome.add_child(_top)
	_dock = DockView.new()
	_sheets.chrome.add_child(_dock)
	_overlays = OverlayHost.new()
	_root.add_child(_overlays)
	_dock.button_pressed.connect(func(id: StringName) -> void: _sheets.toggle(id))
	# as HudController._sync_band: the top bar's band yields to the scrim under an open sheet
	_sheets.sheet_changed.connect(func(_id: StringName) -> void:
		_top.band.mouse_filter = Control.MOUSE_FILTER_IGNORE if _sheets.is_open() else Control.MOUSE_FILTER_STOP)
	_top.layout(SCREEN, SAFE_TOP)
	_dock.layout(SCREEN, SAFE_BOTTOM)
	_sheets.top_limit = _top.bottom()
	_sheets.layout(SCREEN, _dock.top())
	_overlays.layout(SCREEN, Rect2(48, SAFE_TOP, 48, SAFE_BOTTOM))
	_pan.blocked = func() -> bool: return _sheets.is_open() or _overlays.is_modal_open()
	# WorldPan is the LAST child (its _unhandled_input runs first among the world handlers)
	_vp.add_child(_pan)


## One finger, as a phone sends it: the emulated mouse twin is dispatched first, then the touch.
func _down(at: Vector2) -> void:
	var mb := InputEventMouseButton.new()
	mb.device = InputEvent.DEVICE_ID_EMULATION
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT
	mb.pressed = true
	mb.position = at
	mb.global_position = at
	_vp.push_input(mb)
	var st := InputEventScreenTouch.new()
	st.index = 0
	st.pressed = true
	st.position = at
	_vp.push_input(st)


func _move(from: Vector2, to: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.device = InputEvent.DEVICE_ID_EMULATION
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	mm.position = to
	mm.global_position = to
	mm.relative = to - from
	_vp.push_input(mm)
	var sd := InputEventScreenDrag.new()
	sd.index = 0
	sd.position = to
	sd.relative = to - from
	_vp.push_input(sd)


func _up(at: Vector2) -> void:
	var mb := InputEventMouseButton.new()
	mb.device = InputEvent.DEVICE_ID_EMULATION
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = false
	mb.position = at
	mb.global_position = at
	_vp.push_input(mb)
	var st := InputEventScreenTouch.new()
	st.index = 0
	st.pressed = false
	st.position = at
	_vp.push_input(st)


func _tap(at: Vector2) -> void:
	_down(at)
	_up(at)


## Taps far enough apart in time that the 350 ms debounce never merges them.
func _settle() -> void:
	await get_tree().create_timer(float(TapGuard.DEBOUNCE_MS + 30) / 1000.0).timeout


func _frames(n: int = 4) -> void:
	for i in n:
		await get_tree().process_frame


func _centre(ctl: Control) -> Vector2:
	return ctl.get_global_rect().get_center()


func _first_pill(n: Node) -> Button:
	for ch: Node in n.get_children():
		if ch is Button and not (ch as Button).flat and not (ch as Button).disabled:
			return ch as Button
		var b := _first_pill(ch)
		if b != null:
			return b
	return null


func _a_button(parent: Control, at: Vector2, sz: Vector2 = Vector2(360, 144)) -> Button:
	var b := Button.new()
	b.text = "Trồng"
	b.position = at
	b.size = sz
	PressFeedback.attach(b)
	parent.add_child(b)
	return b


# ------------------------------------------------------------------ world: one path, one target

func test_world_reads_one_path_only() -> void:
	_hud()
	_tap(Vector2(540, 1200))
	assert_eq(_world.presses, 1, "a touch and its emulated twin are ONE world press")
	assert_eq(_world.acts, 1, "... and one action, on release")


func test_world_tap_fires_on_release_within_the_slop_and_a_drag_cancels_it() -> void:
	_hud()
	_down(Vector2(540, 1200))
	assert_eq(_world.presses, 1, "touch-down feedback in the same frame")
	assert_eq(_world.acts, 0, "no action on touch-down")
	_move(Vector2(540, 1200), Vector2(540 + 20, 1200))
	_up(Vector2(560, 1200))
	assert_eq(_world.acts, 1, "a 20 px wobble is still a tap")
	_down(Vector2(540, 1200))
	_move(Vector2(540, 1200), Vector2(540 + 80, 1200))
	assert_true(_pan.is_dragging(), "past 24 px the map pans")
	_move(Vector2(620, 1200), Vector2(540, 1200))
	_up(Vector2(540, 1200))
	assert_eq(_world.acts, 1, "no action after a drag, even released where it started")


func test_props_act_on_release_not_on_touch_down() -> void:
	var props: PropsLayer = (load("res://scenes/world/props.tscn") as PackedScene).instantiate()
	add_child_autofree(props)
	watch_signals(props)
	var at := Vector2.ZERO
	for id: StringName in props._touchables:
		at = props._touchables[id]["centre"]
		break
	var canvas := props.get_global_transform_with_canvas() * at
	var hit := props.world_hit(canvas, 27.0)
	assert_false(hit.is_empty(), "a touchable prop is a world target")
	assert_eq(int(hit["prio"]), WorldPan.PRIO_PROP)
	props.world_press(hit["key"], canvas)
	assert_signal_not_emitted(props, "prop_tapped", "touch-down: squash + ring + S01 only (no sheet opens)")
	props.world_release(hit["key"], canvas, false)
	assert_signal_not_emitted(props, "prop_tapped", "a pan that started on the basket opens nothing")
	props.world_press(hit["key"], canvas)
	props.world_release(hit["key"], canvas, true)
	assert_signal_emit_count(props, "prop_tapped", 1, "the tap acts on release")


func test_bed_priority_follows_gdd_2_5_and_choose_mode() -> void:
	var plots: PlotsLayer = (load("res://scenes/garden/plots_layer.tscn") as PackedScene).instantiate()
	add_child_autofree(plots)
	Game.sim.state.seed_planted = true
	plots._seed = null
	var centre := GardenRules.bed_position_px(c, &"bed_4")
	var canvas := plots.get_global_transform_with_canvas() * centre
	assert_eq(int(plots.world_hit(canvas, 27.0)["prio"]), WorldPan.PRIO_BED, "a plain bed ranks below props and décor")
	plots.choose_mode = true
	assert_eq(int(plots.world_hit(canvas, 27.0)["prio"]), WorldPan.PRIO_CHOOSE_BED,
			"choose-a-bed: beds with room outrank even a mossling standing on them")
	plots.choose_mode = false


func test_candidate_order_tier_priority_distance() -> void:
	var stub := {"prio": WorldPan.PRIO_MOSSLING, "inside": true, "d": 0.0, "key": null, "drag": true}
	var prop := {"prio": WorldPan.PRIO_PROP, "inside": true, "d": 0.0, "key": null}
	assert_true(WorldPan.better(stub, prop), "mossling > prop")
	var slop_mossling := {"prio": WorldPan.PRIO_MOSSLING, "inside": false, "d": 100.0}
	var bed := {"prio": WorldPan.PRIO_BED, "inside": true, "d": 50.0}
	assert_true(WorldPan.better(bed, slop_mossling), "a direct hit beats a slop-only hit of any priority")
	var lantern_ring := {"prio": WorldPan.PRIO_DECOR, "inside": true, "core": false, "d": 80.0}
	var lantern_core := {"prio": WorldPan.PRIO_DECOR, "inside": true, "core": true, "d": 20.0}
	assert_true(WorldPan.better(bed, lantern_ring), "a lantern's generous ring never steals a press squarely on a bed")
	assert_true(WorldPan.better(lantern_core, bed), "the lantern itself outranks the plain bed (GDD §2.5)")
	var bank := {"prio": WorldPan.PRIO_STREAM, "inside": true, "core": false, "d": 40.0}
	var water := {"prio": WorldPan.PRIO_STREAM, "inside": true, "core": true, "d": 0.0}
	assert_true(WorldPan.better(lantern_ring, bank), "the ring still beats the brook's generous tap band")
	assert_true(WorldPan.better(water, lantern_ring), "... but not a tap squarely on the water")


# ------------------------------------------------------------------ through-taps: the HUD consumes

func test_hud_chrome_consumes_its_presses_and_gaps() -> void:
	_hud()
	var pill := _dock.pill_rect()
	var tabs: Array[Rect2] = []
	for i in DockView.ORDER.size():
		var b := _dock.button(_dock._id_at(i))
		tabs.append(Rect2(b.position, b.size))
	var spots := {
		"top bar: between the chips": Vector2(700, _top.dew_chip.position.y + 40.0),
		"top bar: the dew chip": _centre(_top.dew_chip),
		"top bar: the time chip": _centre(_top.time_chip),
		"top bar: under the gear's glass": Vector2(_top.gear.position.x + 20.0, _top.gear.position.y + 200.0),
		"dock: the seam between two tabs": Vector2(tabs[0].end.x, pill.get_center().y),
		"dock: the pebble's round left end": Vector2(pill.position.x + 4.0, pill.get_center().y),
		"dock: the pebble's round right end": Vector2(pill.end.x - 4.0, pill.get_center().y),
		"dock: under the pebble (the tab reaches down)": Vector2(540, pill.end.y + 20.0),
		"gesture bar inset": Vector2(540, SCREEN.y - 30.0),
		"gesture bar inset, beside the dock": Vector2(40, SCREEN.y - 60.0),
	}
	for what: String in spots:
		var before := _world.presses
		_tap(spots[what] as Vector2)
		assert_eq(_world.presses, before, "%s never reaches the world" % what)
		if _sheets.is_open():
			_sheets.close()  # a dock tab took the tap
			await get_tree().create_timer(0.5).timeout
		await _settle()
	_tap(Vector2(540, 1200))
	assert_eq(_world.presses, 1, "an open stretch of meadow still does")


func test_toast_consumes_presses_while_shown_and_fading() -> void:
	_hud()
	_overlays.show_toast("Chọn một luống hoa nhé", 0.0, true)
	var at := _centre(_overlays.toast())
	_tap(at)
	assert_eq(_world.presses, 0, "a tap on the toast stays on the toast")
	_overlays.hide_toast()
	_tap(at)
	assert_eq(_world.presses, 0, "... also while it fades out")


func test_open_sheet_consumes_its_whole_rect_and_the_scrim_closes_without_a_world_tap() -> void:
	_hud()
	_sheets.open(&"garden", true)
	await _frames()
	var s := _sheets.current
	var r := s.get_global_rect()
	for at: Vector2 in [r.position + Vector2(10, 10), Vector2(r.get_center().x, r.position.y + 22.0),
			r.end - Vector2(12, 12), Vector2(r.position.x + 6.0, r.get_center().y)]:
		_tap(at)
		await _settle()
	assert_eq(_world.presses, 0, "sheet padding, grabber, corners: nothing reaches the world")
	assert_true(_sheets.is_open(), "taps on the sheet's own padding never close it")
	# a drag over the dimmed world does not dismiss
	_down(Vector2(540, r.position.y - 60.0))
	_move(Vector2(540, r.position.y - 60.0), Vector2(800, r.position.y - 60.0))
	_up(Vector2(800, r.position.y - 60.0))
	assert_true(_sheets.is_open(), "a drag on the scrim is not a tap")
	assert_eq(_world.presses, 0)
	_tap(Vector2(540, r.position.y - 60.0))
	assert_false(_sheets.is_open(), "a tap on the scrim closes the sheet")
	assert_eq(_world.presses, 0, "... and does not also hit the world (both twins stop at the scrim)")


func test_a_closing_sheet_still_consumes_and_never_acts_twice() -> void:
	_hud()
	_sheets.open(&"garden", true)
	await _frames()
	var collect := _first_pill(_sheets.current.scroll_list())
	assert_not_null(collect, "Plant")
	var fired: Array[int] = [0]
	collect.pressed.connect(func() -> void: fired[0] += 1)
	var at := _centre(collect)
	_sheets.close()
	_tap(at)
	assert_eq(fired[0], 0, "a button of a sheet on its way out does nothing")
	assert_eq(_world.presses, 0, "and the tap does not fall through to the world")
	await get_tree().create_timer(0.5).timeout
	_tap(at)
	assert_eq(_world.presses, 1, "once the sheet has gone, the world is back")


func test_modal_scrim_consumes_and_only_a_tap_dismisses() -> void:
	_hud()
	_overlays.show_recap(_overlays.sample_recap(), true)
	var away := Vector2(540, 300)
	_down(away)
	_move(away, away + Vector2(200, 0))
	_up(away + Vector2(200, 0))
	assert_true(_overlays.is_modal_open(), "a drag on the modal scrim does not dismiss")
	_tap(away)
	assert_false(_overlays.is_modal_open(), "a tap does")
	assert_eq(_world.presses, 0, "neither reached the world")


func test_the_ambient_wake_gesture_is_swallowed_whole() -> void:
	var gate := PointerGate.new()
	var emu := InputEventMouseButton.new()
	emu.device = InputEvent.DEVICE_ID_EMULATION
	emu.button_index = MOUSE_BUTTON_LEFT
	emu.pressed = true
	assert_true(PointerGate.is_press(emu))
	gate.begin(emu)
	var st := InputEventScreenTouch.new()
	st.pressed = true
	assert_true(gate.swallow(st), "the touch twin of the waking press")
	var sd := InputEventScreenDrag.new()
	assert_true(gate.swallow(sd), "its drag")
	var emu_up := emu.duplicate() as InputEventMouseButton
	emu_up.pressed = false
	assert_true(gate.swallow(emu_up), "the emulated release (dispatched first)")
	assert_true(gate.active, "still waiting for the touch's own release")
	var st_up := InputEventScreenTouch.new()
	st_up.pressed = false
	assert_true(gate.swallow(st_up), "the touch release ends the gesture")
	assert_false(gate.active)
	assert_false(gate.swallow(st), "the next tap is a normal tap")
	var key := InputEventKey.new()
	gate.begin(emu)
	assert_false(gate.swallow(key), "keys (Back) are never swallowed")


# ------------------------------------------------------------------ buttons: slop, scroll, debounce

func test_a_button_fires_once_for_a_touch_and_its_emulated_twin() -> void:
	_hud()
	var b := _a_button(_root, Vector2(300, 900))
	var n: Array[int] = [0]
	b.pressed.connect(func() -> void: n[0] += 1)
	_tap(_centre(b))
	assert_eq(n[0], 1, "one action per tap on the two input paths")
	assert_eq(_world.presses, 0, "the button consumed both twins")


func test_press_slop_cancels_a_sliding_finger() -> void:
	_hud()
	var b := _a_button(_root, Vector2(300, 900), Vector2(480, 180))
	var n: Array[int] = [0]
	b.pressed.connect(func() -> void: n[0] += 1)
	var at := _centre(b)
	_down(at)
	_move(at, at + Vector2(0, 18))
	_up(at + Vector2(0, 18))
	assert_eq(n[0], 1, "a 6 dp wobble is still a tap")
	await _settle()
	_down(at)
	_move(at, at + Vector2(0, 45))
	_up(at + Vector2(0, 45))
	assert_eq(n[0], 1, "a 15 dp slide (a scroll attempt) is cancelled, still inside the button")
	await _settle()
	_down(at)
	_move(at, at + Vector2(400, 0))
	_up(at + Vector2(400, 0))
	assert_eq(n[0], 1, "sliding off cancels")


func test_buttons_in_a_scroll_list_pass_presses_on_and_the_list_has_the_slop_deadzone() -> void:
	_hud()
	_sheets.open(&"garden", true)
	await _frames()
	var sc := _sheets.current.scroll_list()
	assert_not_null(sc)
	assert_eq(sc.scroll_deadzone, roundi(TapGuard.slop_px()), "the list starts scrolling at the 10 dp slop")
	assert_eq(int(ProjectSettings.get_setting("gui/common/default_scroll_deadzone")), 30, "every list does")
	var pill := _first_pill(sc)
	assert_not_null(pill, "a Plant button in the list")
	assert_eq(pill.mouse_filter, Control.MOUSE_FILTER_PASS, "a drag that starts on Plant scrolls the list")
	var n: Array[int] = [0]
	pill.pressed.connect(func() -> void: n[0] += 1)
	var at := _centre(pill)
	_down(at)
	pill.notification(Control.NOTIFICATION_SCROLL_BEGIN)  # the list began to scroll
	_up(at)
	assert_eq(n[0], 0, "once the list scrolls, the button under the finger never fires")


func test_a_press_during_a_fling_only_catches_the_list() -> void:
	_hud()
	_sheets.open(&"garden", true)
	await _frames()
	var sc := _sheets.current.scroll_list()
	var pill := _first_pill(sc)
	var n: Array[int] = [0]
	pill.pressed.connect(func() -> void: n[0] += 1)
	sc.set_meta(TapGuard.META_SCROLL_MS, Time.get_ticks_msec())  # the list is gliding
	var at := _centre(pill)
	_down(at)
	await get_tree().process_frame
	_up(at)
	assert_eq(n[0], 0, "the press stopped the fling and did nothing else")
	await _settle()
	_tap(at)
	assert_eq(n[0], 1, "the next tap on the resting list works")


func test_fast_double_taps_act_once() -> void:
	_hud()
	var b := _a_button(_root, Vector2(300, 900))
	var n: Array[int] = [0]
	b.pressed.connect(func() -> void: n[0] += 1)
	_tap(_centre(b))
	_tap(_centre(b))
	assert_eq(n[0], 1, "a double tap within 350 ms is one purchase")
	assert_eq(_world.presses, 0, "the swallowed second tap never falls through")
	await _settle()
	_tap(_centre(b))
	assert_eq(n[0], 2, "a deliberate second tap later counts")


func test_dock_selects_on_release_slides_off_cancel_and_the_active_tab_closes() -> void:
	_hud()
	var garden := _dock.button(&"garden")
	var basket := _dock.button(&"basket")
	_down(_centre(garden))
	assert_false(_sheets.is_open(), "nothing opens on touch-down")
	_up(_centre(garden))
	assert_eq(_sheets.current_id, &"garden", "the tab opens its sheet on release")
	await _settle()
	_tap(_centre(garden))
	assert_false(_sheets.is_open(), "tapping the active tab closes its sheet (GDD §8.1)")
	await get_tree().create_timer(0.5).timeout
	_down(_centre(garden))
	_move(_centre(garden), _centre(basket))
	_up(_centre(basket))
	assert_false(_sheets.is_open(), "press Garden, slide onto Basket: nothing opens")
	assert_eq(_world.presses, 0)


# ------------------------------------------------------------------ sliders

func test_slider_moves_only_on_a_horizontal_drag() -> void:
	_hud()
	var s := UiSlider.new()
	s.position = Vector2(100, 900)
	s.size = Vector2(800, 144)
	s.set_value_silent(50)
	_root.add_child(s)
	assert_eq(s.mouse_filter, Control.MOUSE_FILTER_PASS, "a vertical drag over it reaches the scroll list")
	var at := s.get_global_rect().get_center() + Vector2(200, 0)
	_down(at)
	_move(at, at + Vector2(6, 40))
	_move(at + Vector2(6, 40), at + Vector2(10, 160))
	_up(at + Vector2(10, 160))
	assert_eq(s.value, 50, "a vertical scroll gesture over the slider never moves it")
	_down(at)
	_move(at, at + Vector2(30, 2))
	_move(at + Vector2(30, 2), at + Vector2(-300, 4))
	_up(at + Vector2(-300, 4))
	assert_ne(s.value, 50, "a horizontal drag moves it")
	var v := s.value
	_down(s.get_global_rect().get_center() + Vector2(-380, 0))
	s.notification(Control.NOTIFICATION_SCROLL_BEGIN)
	_up(s.get_global_rect().get_center() + Vector2(-380, 0))
	assert_eq(s.value, v, "a press the list took over for scrolling changes nothing")
	_tap(s.get_global_rect().get_center() + Vector2(390, 0))
	assert_eq(s.value, 100, "a tap jumps to the nearest detent")


# ------------------------------------------------------------------ sizes

func test_targets_meet_the_floors() -> void:
	_hud()
	var dp := UiTokens.PX_PER_DP
	for id: StringName in DockView.ORDER:
		var b := _dock.button(id)
		assert_true(b.size.x >= 76.0 * dp and b.size.y >= 76.0 * dp, "dock %s >= 76 dp" % id)
	for b: Control in [_top.gear, _top.eye]:
		assert_true(b.size.x >= 72.0 * dp and b.size.y >= 72.0 * dp, "HUD %s >= 72 dp" % b.name)
	_sheets.open(&"settings", true)
	await _frames()
	var close := _sheets.current.close_button
	assert_true(close.size.x >= 60.0 * dp, "the sheet close is >= 60 dp")
	for ctl: Control in HitDebug.ui_controls(_sheets.current):
		if HitDebug.is_target(ctl):
			var r := HitDebug.screen_rect(ctl)
			if r.size.y >= 1.0 and r.size.y == ctl.size.y:
				assert_true(minf(ctl.size.x, ctl.size.y) >= 48.0 * dp - 0.5, "%s >= 48 dp (%s)" % [ctl.name, ctl.size])
