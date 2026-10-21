extends GutTest
## The garden view layers against a live sim (GDD §3.1, §8.2-8.3, Art Bible §6.2, §6.6): every
## planted bed gets one mesh, the tutorial seed shows until tapped and a tap plants it, a bloom the
## player watches becomes a ready bud that a tap unfurls (and that opens by itself after 20 s),
## a plain bed tap sways the stems, every owned décor copy stands at its anchor, a placement
## animates, the lantern and pinwheel taps fire their effects, and the basket shows what waits.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const SEED := 777
const FRAME_S := 1.0 / 30.0

var c: GameContent
var _saved_sim: WorldSim
var _saved_ready: bool
var _saved_content: GameContent


func before_all() -> void:
	c = ContentRegistry.content


func before_each() -> void:
	_saved_sim = Game.sim
	_saved_ready = Game.is_ready
	_saved_content = Game.content
	Game.content = c
	Game.sim = WorldSim.new_game(c, SEED, Clock.now_unix(), 0.0)
	Game.is_ready = true


func after_each() -> void:
	Game.sim = _saved_sim
	Game.is_ready = _saved_ready
	Game.content = _saved_content
	LampRegistry.clear()


func _plots() -> PlotsLayer:
	var p: PlotsLayer = (load("res://scenes/garden/plots_layer.tscn") as PackedScene).instantiate()
	add_child_autofree(p)
	return p


func _decor() -> DecorLayer:
	var d: DecorLayer = (load("res://scenes/garden/decor_layer.tscn") as PackedScene).instantiate()
	add_child_autofree(d)
	return d


func _tick(node: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		node._process(FRAME_S)
		t += FRAME_S


func _touch(node: Node2D, design: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.pressed = pressed
	ev.position = node.get_global_transform_with_canvas() * design
	node._unhandled_input(ev)


func _vertex_count(p: PlotsLayer, bed: StringName) -> int:
	var bv: PlotsLayer.BedView = p._beds[bed]
	var mesh := bv.mesh.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	return (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector2Array).size()


func test_tutorial_seed_shows_until_tapped_then_plants() -> void:
	var p := _plots()
	assert_not_null(p._seed, "the glowing seed rests on its bed (GDD §3.4)")
	var bed := StringName(c.economy["onboarding"]["tutorial_bed"])
	var centre := GardenRules.bed_position_px(c, bed)
	_touch(p, centre, true)
	_touch(p, centre, false)
	assert_true(Game.sim.state.seed_planted, "a tap on its bed plants it (Game.tap_seed)")
	assert_eq(Game.sim.state.stems.size(), 1)
	_tick(p, 0.1)
	assert_null(p._seed, "the seed hint is gone")
	var bv: PlotsLayer.BedView = p._beds[bed]
	assert_eq(bv.anim.size(), 1, "the planting animates on the small per-frame mesh")
	_tick(p, 0.6)
	assert_true(bv.anim.is_empty(), "then joins the bed's static mesh")
	assert_gt(_vertex_count(p, bed), 0, "the planted seed is drawn")


func test_watched_bloom_is_a_ready_bud_that_a_tap_unfurls() -> void:
	GardenFixture.apply(c, Game.sim.state, GardenFixture.MID)
	Game.sim = WorldSim.new(c, Game.sim.state)
	var p := _plots()
	_tick(p, FRAME_S)
	for b: Dictionary in c.beds:
		assert_gt(_vertex_count(p, StringName(b["id"])), 0, "%s is drawn" % b["id"])
	# a stem of bed_1 blooms while the player watches
	var idx := -1
	for i in Game.sim.state.stems.size():
		var s: Dictionary = Game.sim.state.stems[i]
		if String(s["bed"]) == "bed_1" and int(s["stage"]) == WorldSim.STAGE_BUD:
			idx = i
	assert_gt(idx, -1, "the fixture has a bud in bed_1")
	Game.sim.state.stems[idx]["stage"] = WorldSim.STAGE_BLOOM
	Game.sim_event.emit({"type": WorldSim.EV_STAGE, "t": Game.sim.state.t, "stem": idx, "flower": &"button_daisy",
		"stage": WorldSim.STAGE_BLOOM})
	_tick(p, FRAME_S)
	var v: PlotsLayer.StemView = p._views[idx]
	assert_true(v.ready_s >= 0.0, "a watched bloom waits as a ready bud")
	assert_true(p.claims(GardenRules.bed_position_px(c, &"bed_1")), "a bed with a ready bud outranks décor")
	var centre := GardenRules.bed_position_px(c, &"bed_1")
	_touch(p, centre, true)
	_touch(p, centre, false)
	assert_true(v.unfurl_s >= 0.0, "the tap unfurls it")
	_tick(p, 0.7)
	assert_true(v.ready_s < 0.0 and v.unfurl_s < 0.0, "open after the 600 ms unfurl")
	assert_almost_eq(v.open, 1.0, 1e-4)


func test_ready_bud_opens_by_itself_after_20_s() -> void:
	GardenFixture.apply(c, Game.sim.state, GardenFixture.MID)
	Game.sim = WorldSim.new(c, Game.sim.state)
	var p := _plots()
	var idx := 0
	var v := p._view_for(idx)
	v.ready_s = 0.0
	var auto_s := float(c.motion["flora"]["ready_bud"]["auto_unfurl_after_s"])
	_tick(p, auto_s - 0.5)
	assert_true(v.unfurl_s < 0.0, "still waiting before 20 s")
	_tick(p, 1.0)
	assert_true(v.unfurl_s >= 0.0, "unfurls by itself after 20 s")
	assert_almost_eq(v.unfurl_rate, 600.0 / 2400.0, 1e-4, "the slow 2.4 s unfurl")


func test_plain_bed_tap_sways_and_long_press_asks_for_the_card() -> void:
	GardenFixture.apply(c, Game.sim.state, GardenFixture.MID)
	Game.sim = WorldSim.new(c, Game.sim.state)
	var p := _plots()
	watch_signals(p)
	var centre := GardenRules.bed_position_px(c, &"bed_3")
	_touch(p, centre, true)
	var bv: PlotsLayer.BedView = p._beds[&"bed_3"]
	assert_lt(bv.press.target, 1.0, "touch-down squashes the bed in the same frame")
	_touch(p, centre, false)
	assert_true(bv.sway_t >= 0.0, "a tap without ready buds sways the stems")
	_touch(p, centre, true)
	_tick(p, 0.5)
	assert_signal_emitted_with_parameters(p, "bed_card_requested", [&"bed_3"])
	_touch(p, centre, false)


func test_choose_mode_emits_the_chosen_bed() -> void:
	var p := _plots()
	watch_signals(p)
	p.choose_mode = true
	var centre := GardenRules.bed_position_px(c, &"bed_4")
	_touch(p, centre, true)
	_touch(p, centre, false)
	assert_signal_emitted_with_parameters(p, "bed_chosen", [&"bed_4"])


func test_decor_pieces_follow_the_owned_counts_and_placements_animate() -> void:
	GardenFixture.apply(c, Game.sim.state, GardenFixture.MID)
	Game.sim = WorldSim.new(c, Game.sim.state)
	var d := _decor()
	for item: Dictionary in c.decor:
		var id := StringName(item["id"])
		assert_eq(d.piece_count(id), Game.sim.owned_count(id), "%s pieces = owned copies" % id)
	Game.sim.state.dew = 99999
	assert_true(Game.sim.buy_decor(&"toadstool_seat"))
	for ev: Dictionary in Game.sim.drain_events():
		Game.sim_event.emit(ev)
	assert_eq(d.piece_count(&"toadstool_seat"), Game.sim.owned_count(&"toadstool_seat"), "the new copy appears")
	var list: Array = d._pieces[&"toadstool_seat"]
	var newest: DecorLayer.Piece = list[list.size() - 1]
	assert_true(newest.appear_t >= 0.0, "a placement fades and pops in")
	_tick(d, 1.0)
	assert_true(newest.appear_t < 0.0, "and settles")
	var anchor: Array = (c.anchors_by_decor[&"toadstool_seat"]["positions"] as Array)[newest.index]
	assert_almost_eq(newest.foot.distance_to(GardenRules.frame_to_px(c, Vector2(float(anchor[0]), float(anchor[1])))),
			0.0, 0.01, "each copy stands at the next anchor")


func test_lantern_and_pinwheel_taps() -> void:
	GardenFixture.apply(c, Game.sim.state, GardenFixture.NIGHT_LANTERNS)
	Game.sim = WorldSim.new(c, Game.sim.state)
	var d := _decor()
	var lantern: DecorLayer.Piece = (d._pieces[&"firefly_lantern"] as Array)[0]
	_touch(d, lantern.hit, true)
	assert_lt(lantern.press.target, 1.0, "touch-down squash")
	_touch(d, lantern.hit, false)
	assert_true(lantern.boost_t >= 0.0, "the lantern brightens")
	assert_gt(LampRegistry.lamp_count(), 0, "lanterns light pools")
	var pw: DecorLayer.Piece = (d._pieces[&"leaf_pinwheel"] as Array)[0]
	var a0 := pw.angle
	_touch(d, pw.hit, true)
	_touch(d, pw.hit, false)
	assert_true(pw.burst_t >= 0.0, "the pinwheel spins up")
	_tick(d, 0.2)
	assert_ne(pw.angle, a0, "and turns")


func test_basket_shows_what_waits() -> void:
	GardenFixture.apply(c, Game.sim.state, GardenFixture.MID)
	Game.sim = WorldSim.new(c, Game.sim.state)
	var d := _decor()
	d.basket.refresh()
	var n := Game.sim.state.basket.size()
	assert_eq(d.basket.shown_counts(), Vector2i(mini(n, BasketFill.MAX_DEW), mini(n, BasketFill.MAX_GIFTS)))
	assert_true(d.basket._glint.visible, "the basket glints once anything waits")
	Game.sim.collect()
	d.basket.refresh()
	assert_eq(d.basket.shown_counts(), Vector2i.ZERO, "collect empties it")
	assert_false(d.basket._glint.visible)


func test_butterflies_only_with_blooms_by_day_and_never_in_rain() -> void:
	var b := Butterflies.new()
	add_child_autofree(b)
	var phase := TimeOfDay.phase
	var weather := TimeOfDay.weather
	TimeOfDay.phase = &"day"
	TimeOfDay.weather = &"clear"
	assert_eq(b._wanted(2), 0, "fewer than 3 blooms: none")
	assert_between(b._wanted(9), 1, Butterflies.MAX_COUNT, "a blooming garden by day: 1-3")
	assert_eq(b._wanted(90), Butterflies.MAX_COUNT, "never more than 3")
	TimeOfDay.weather = &"rain"
	assert_eq(b._wanted(9), 0, "never in rain")
	TimeOfDay.weather = &"clear"
	TimeOfDay.phase = &"night"
	assert_eq(b._wanted(9), 0, "not at night")
	TimeOfDay.phase = phase
	TimeOfDay.weather = weather
