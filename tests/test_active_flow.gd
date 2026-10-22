extends GutTest
## Active Play v1 integration: one session across F1 Wishes, F2 Tea & Treats and F3 free décor
## through the Game API and the real DecorLayer + WorldPan arbiter in a SubViewport. A wish
## appears from the foreground clock; petals are harvested without harming a stem; the wished tea
## is brewed (petals, stir, pour) and offered; the wish is granted once with affection and a gift
## petal; then a long-press opens edit mode, a pinwheel is carried and set down, Done leaves; map
## pan, a pinwheel tap (a world wish) and petting still behave; no signal fires twice; the save
## round-trips every active field.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only these analyzer warnings are silenced here (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")
@warning_ignore_start("unsafe_method_access")

const SCREEN := Vector2(1080, 1920)
const FRAME_S := 1.0 / 30.0
const WISHER := &"buttonbud"
const TEA_FRIEND := &"puffmoss"
const BED := &"bed_1"

var c: GameContent
var _vp: SubViewport
var _pan: WorldPan
var _layer: DecorLayer
var _saved_sim: WorldSim
var _saved_ready: bool
var _saved_content: GameContent
var _saved_persist: bool
var _count: Dictionary = {}


func before_all() -> void:
	c = ContentRegistry.content


func before_each() -> void:
	_saved_sim = Game.sim
	_saved_ready = Game.is_ready
	_saved_content = Game.content
	_saved_persist = Settings.persist
	Settings.persist = false
	Game.content = c
	var sim := WorldSim.new_game(c, 4242, Clock.now_unix(), 0.0)
	GardenFixture.apply(c, sim.state, GardenFixture.MID)
	sim = WorldSim.new(c, sim.state)  # migrates the décor from the anchors
	var st := sim.state
	st.tea_unlocked = true
	st.seed_planted = true
	st.wish_tutorial_done = true
	st.present.clear()
	for sp: StringName in [WISHER, TEA_FRIEND]:
		st.met[String(sp)] = sim.unix_at(st.t - 86400.0)
	# petals ready on bed_1's bloomed stems (three regrow periods ago)
	for stem: Dictionary in st.stems:
		if String(stem["bed"]) == String(BED) and int(stem["stage"]) >= WorldSim.STAGE_BLOOM:
			st.petal_from_t[TeaRules.stem_key(stem)] = st.t - 3.0 * sim.active.tea.regrow_s(StringName(stem["flower"]))
	ActiveTestUtil.arrive(sim, WISHER, st.t)
	sim.drain_events()
	Game.sim = sim
	Game.is_ready = true
	Game._world_base_t = sim.state.t
	Game._ticks_base_s = Clock.ticks_s()
	_count.clear()
	for s: String in ["wish_opened", "wish_granted", "tea_offered", "recipe_found", "petals_harvested",
			"decor_placed", "decor_edit_entered", "decor_edit_exited"]:
		Game.connect(s, _bump.bind(s))
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
	for s: String in _count.keys() + ["wish_opened", "wish_granted", "tea_offered", "recipe_found",
			"petals_harvested", "decor_placed", "decor_edit_entered", "decor_edit_exited"]:
		for conn: Dictionary in Game.get_signal_connection_list(s):
			if (conn["callable"] as Callable).get_object() == self:
				Game.disconnect(s, conn["callable"])
	if Game.sim != null and Game.sim.active.edit_mode:
		Game.sim.active.set_edit_mode(Game.sim, false)
	Settings.persist = _saved_persist
	Game.sim = _saved_sim
	Game.is_ready = _saved_ready
	Game.content = _saved_content
	LampRegistry.clear()


func _bump(a0: Variant = null, a1: Variant = null, a2: Variant = null, a3: Variant = null,
		a4: Variant = null, a5: Variant = null, name: String = "") -> void:
	# signals carry 0-6 args; the bound name is always the last one passed
	var args := [a0, a1, a2, a3, a4, a5, name]
	var key := ""
	for i in range(args.size() - 1, -1, -1):
		if args[i] is String and String(args[i]) != "":
			key = String(args[i])
			break
	_count[key] = int(_count.get(key, 0)) + 1


func _pin_clock() -> void:
	Game._world_base_t = Game.sim.state.t
	Game._ticks_base_s = Clock.ticks_s()


func _n(sig: String) -> int:
	return int(_count.get(sig, 0))


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


func _px(n: Vector2) -> Vector2:
	return GardenRules.frame_to_px(c, n)


func _rec(id: String) -> Dictionary:
	for r: Dictionary in Game.decor_layout():
		if String(r["id"]) == id:
			return r
	return {}


func _pinwheel() -> DecorLayer.Piece:
	for p: DecorLayer.Piece in _layer.movable_pieces():
		if p.decor == DecorLayer.PINWHEEL:
			return p
	return null


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


func _stems_snapshot() -> Array:
	var out: Array = []
	for s: Dictionary in Game.sim.state.stems:
		out.append([String(s["flower"]), String(s["bed"]), int(s["slot"]), int(s["stage"])])
	return out


func test_one_session_wish_tea_offer_then_arrange_decor() -> void:
	var sim := Game.sim
	# --- F1: a wish appears from the foreground clock (never in edit mode, never by itself offline)
	var waited := 0.0
	while Game.wishes().is_empty() and waited < 1800.0:
		sim.advance(sim.state.t + 5.0)  # Game syncs the world every frame in play
		Game.wish_foreground_tick(5.0)
		waited += 5.0
	_pin_clock()
	assert_false(Game.wishes().is_empty(), "a wish appeared within 30 foreground minutes")
	assert_eq(_n("wish_opened"), 1, "exactly one wish_opened")
	if Game.wishes().is_empty():
		return
	var first := StringName(Game.wishes()[0]["species"])
	assert_ne(first, TEA_FRIEND)
	# the tea friend arrives and craves clover tea (the second open wish, the cap is 2)
	ActiveTestUtil.arrive(sim, TEA_FRIEND, sim.state.t)
	ActiveTestUtil.give_wish(sim, TEA_FRIEND, &"clover_tea")
	sim.drain_events()
	assert_eq(StringName(Game.wish_of(TEA_FRIEND)["wish"]), &"clover_tea")
	var aff0 := int(sim.state.affection.get(String(TEA_FRIEND), 0))
	# --- F2: harvest petals; the flowers are untouched
	var stems0 := _stems_snapshot()
	var jar0 := int(Game.pantry().get("sweet_clover", 0))
	var got := Game.harvest_bed(BED)
	Game.world_action(&"bed_tap", {"bed": BED})
	assert_gt(int(got.get("sweet_clover", got.get(&"sweet_clover", 0))), 0, "clover petals gathered")
	assert_eq(_stems_snapshot(), stems0, "harvesting never harms or removes a flower")
	assert_eq(_n("petals_harvested"), 1, "one harvest event")
	assert_false(Game.wish_of(TEA_FRIEND).is_empty(), "a bed tap does not grant a tea wish")
	assert_gt(int(Game.pantry().get("sweet_clover", 0)), jar0)
	assert_true(Game.harvest_bed(BED).is_empty(), "a second tap gathers nothing new (no double gather)")
	# brew: two clover petals in, a gentle stir to the target, pour
	while not (Game.pot()["petals"] as Array).is_empty():
		Game.pot_remove(0)
	assert_true(Game.pot_add_petal(&"sweet_clover"))
	assert_true(Game.pot_add_petal(&"sweet_clover"))
	assert_eq(StringName(Game.pot()["recipe"]), &"clover_tea", "the pot knows what it makes")
	var target := float(Game.pot()["stir_target"])
	var guard := 0
	while Game.pot_stir(30.0) < target and guard < 200:
		guard += 1
	assert_lt(guard, 200, "the stir reaches its target (either way, no timing)")
	assert_gt(target, 0.0)
	var tray0 := Game.tray().size()
	assert_eq(Game.pot_pour(), &"clover_tea")
	assert_eq(Game.tray().size(), tray0 + 1, "one cup on the tray")
	# offer: the wish is granted once, affection rises, a gift petal comes back
	var res := Game.offer_cup(Game.tray().size() - 1, TEA_FRIEND)
	assert_eq(StringName(res.get("wish_granted", "")), &"clover_tea", "the cup grants the wish")
	assert_eq(StringName(res.get("reaction", "")), &"loved", "puffmoss loves clover tea")
	assert_eq(_n("wish_granted"), 1, "one wish_granted")
	assert_eq(_n("tea_offered"), 1, "one tea_offered")
	assert_true(Game.wish_of(TEA_FRIEND).is_empty(), "the wish left by its grant")
	assert_gt(int(sim.state.affection.get(String(TEA_FRIEND), 0)), aff0, "affection toward the hearts")
	assert_true(Game.wish_stamps(TEA_FRIEND).has(&"clover_tea"), "a stamp in the Album")
	assert_gt(int(res.get("petals_back", 0)), 0, "a gift of petals")
	assert_false(Game.wish_of(first).is_empty(), "the other friend's wish waits, never expires")
	# --- F3: long-press a pinwheel, carry it, set it down, Done
	var pw := _pinwheel()
	assert_not_null(pw, "a pinwheel in the garden")
	var id := pw.id
	var to := _valid_spot(DecorLayer.PINWHEEL, id)
	assert_ne(to, Vector2.INF)
	var fg0 := sim.state.wish_fg_s
	var at := _layer.to_canvas(pw.hit)
	_touch(at, true)
	_tick(0.5)
	assert_true(Game.edit_mode(), "a long-press opened edit mode")
	assert_eq(_n("decor_edit_entered"), 1)
	Game.wish_foreground_tick(120.0)
	assert_eq(sim.state.wish_fg_s, fg0, "the wish clock rests in edit mode")
	var pan0 := _pan.offset()
	var finger := _layer.to_canvas(_px(to)) + Vector2(0.0, DecorEdit.CARRY_DP * 3.0)
	for i in 10:
		_drag(at.lerp(finger, float(i + 1) / 10.0))
		_tick(FRAME_S * 2.0)
	assert_eq(_pan.offset(), pan0, "carrying never pans")
	assert_eq(_n("decor_placed"), 0, "nothing placed mid-drag")
	_touch(finger, false)
	_tick(0.6)
	assert_eq(_n("decor_placed"), 1, "one decor_placed on the drop")
	var rec := _rec(id)
	assert_lt(_px(Vector2(float(rec["x"]), float(rec["y"]))).distance_to(_px(to)), 18.0, "it stands where it was set")
	_layer.edit.exit()
	assert_false(Game.edit_mode())
	assert_eq(_n("decor_edit_exited"), 1, "one exit")
	assert_false(_pan.edit_mode)
	# --- after edit mode: map pan, a pinwheel tap (one world wish grant), petting
	var empty := Vector2(SCREEN.x * 0.5, 120.0)
	_touch(empty, true)
	for i in 6:
		_drag(empty + Vector2(30.0 * (i + 1), 0.0))
	assert_true(_pan.is_dragging(), "the map pans again")
	_touch(empty + Vector2(180.0, 0.0), false)
	assert_false(Game.edit_mode(), "a pan never opens edit mode")
	ActiveTestUtil.give_wish(sim, TEA_FRIEND, &"pinwheel_spin")
	sim.drain_events()
	var granted0 := _n("wish_granted")
	pw = _pinwheel()
	_tick(1.0)
	var tap_at := _layer.to_canvas(pw.hit)
	_touch(tap_at, true)
	_tick(0.1)
	_touch(tap_at, false)
	assert_true(pw.burst_t >= 0.0, "the pinwheel spins as before")
	assert_eq(_n("wish_granted"), granted0 + 1, "one tap, one grant")
	assert_false(Game.edit_mode(), "a short tap never opens edit mode")
	var aff1 := int(sim.state.affection.get(String(WISHER), 0))
	assert_true(Game.pet(WISHER), "petting credits once per visit")
	assert_false(Game.pet(WISHER), "a second pet is soft feedback only")
	assert_eq(int(sim.state.affection.get(String(WISHER), 0)), aff1 + int(sim._eco["affection_per_pet"]),
			"affection from petting counted once")
	# --- save round-trip
	var d := sim.state.to_dict()
	var path := "user://test_active_flow.save"
	var store := SaveStore.new(path, func(w: Dictionary) -> Dictionary: return WorldState.from_dict(w).to_dict())
	assert_eq(store.write(d, Clock.now_unix(), "test"), OK)
	var back := store.read()
	assert_true(bool(back["ok"]), "the save reads back")
	var w: Dictionary = back["world"]
	# the store normalises on read (e.g. the fixture's basket rows gain their default "signature")
	assert_eq(TestUtil.canonical(w), TestUtil.canonical(WorldState.from_dict(d).to_dict()),
			"every field round-trips")
	var st2 := WorldState.from_dict(w)
	assert_eq(st2.pantry, sim.state.pantry)
	assert_true(st2.recipes_found.has("clover_tea"))
	var moved: Dictionary = {}
	for r: Dictionary in st2.decor_layout:
		if String(r["id"]) == id:
			moved = r
	assert_almost_eq(float(moved.get("x", -1.0)), float(rec["x"]), 1e-6, "the pinwheel stays put")
	assert_almost_eq(float(moved.get("y", -1.0)), float(rec["y"]), 1e-6)
	assert_eq(st2.wishes.size(), sim.state.wishes.size(), "the waiting wish is kept")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))
