extends GutTest
## Active F3 free décor placement (GDD §14, docs/gdd/ACTIVE_DECOR.md §4-§13): the validity table
## (one reason per rule, soft hints only), soft snapping (magnet radius, family priority), the
## invalid-drop nudge and float home, beautify jitter, moves / turns / put away / take out / cairn
## merge and lift / one-step undo, auto placement of a purchase, derived spots, attraction on owned
## copies (tidying never costs a friend), decor_placed only after a settle, and the decor_near wish.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const PIN := &"leaf_pinwheel"
const VALID := DecorPlacementRules.VALID
const STONE := &"stream_stones"
const TOAD := &"toadstool_seat"

var c: GameContent
var rules: DecorPlacementRules
var ctx := {"nests": [], "tea": true}
var _open_cache := {}


func before_all() -> void:
	c = GameContent.load_from_dir()
	rules = DecorPlacementRules.new(c)


func _empty() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	return out


func _sim(owned: Dictionary = {}) -> WorldSim:
	var sim := ActiveTestUtil.quiet_sim(c)
	ActiveTestUtil.set_garden(sim, c, {&"sweet_clover": 2}, owned)
	return sim


## The first grid point of the tend zone where [param set_id] may stand everywhere within
## [param radius_dp] (an open patch of meadow for cluster tests), with no layout.
func _open(set_id: StringName, radius_dp: float) -> Vector2:
	var key := "%s/%s" % [set_id, radius_dp]
	if _open_cache.has(key):
		return _open_cache[key]
	var found := _scan_open(set_id, radius_dp)
	_open_cache[key] = found
	return found


func _scan_open(set_id: StringName, radius_dp: float) -> Vector2:
	var none := _empty()
	var socks := rules.sockets(set_id, none, ctx)
	var y := 0.4
	while y < 0.78:
		var x := 0.05
		while x < 0.95:
			var p := Vector2(x, y)
			var ok := rules.validate(set_id, p, none, ctx) == DecorPlacementRules.VALID
			for sk: Dictionary in socks:
				if ok and rules.dist_dp(p, sk["pos"]) < radius_dp + 16.0:
					ok = false  # clear of snap sockets too, so a drop there stays a free placement
			var k := 0
			while ok and k < 16:
				var a := TAU * k / 16.0
				for rr: float in [radius_dp * 0.5, radius_dp]:
					var q := rules.offset_norm(p, Vector2(cos(a), sin(a)) * rr)
					if rules.validate(set_id, q, none, ctx) != VALID:
						ok = false
				k += 1
			if ok:
				return p
			x += 0.005
		y += 0.005
	return Vector2.INF


func _events(sim: WorldSim, type: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in sim.drain_events():
		if StringName(e["type"]) == type:
			out.append(e)
	return out


# ----------------------------------------------------------------- validity (§4)

func test_validity_table_names_one_soft_reason_per_rule() -> void:
	var none := _empty()
	var open := _open(PIN, 20.0)
	assert_ne(open, Vector2.INF, "an open patch of meadow exists")
	var cases := [
		[PIN, open, DecorPlacementRules.VALID, "open meadow"],
		[PIN, Vector2(0.5, 0.2), DecorPlacementRules.R_SKY, "above the rim"],
		[PIN, Vector2(0.3, 0.79), DecorPlacementRules.R_LOW, "under the tend zone"],
		[PIN, Vector2(1.4, 0.6), DecorPlacementRules.R_EDGE, "beyond the wings"],
		[PIN, Vector2(0.62, 0.774), DecorPlacementRules.R_WATER, "a pinwheel in the brook"],
		[STONE, open, DecorPlacementRules.R_DRY, "a stone on dry ground"],
		[STONE, Vector2(0.62, 0.774), DecorPlacementRules.VALID, "a stone in the water"],
		[PIN, Vector2(0.5, 0.69), DecorPlacementRules.R_FLOWERS, "on a bed's soil"],
		[PIN, Vector2(0.35, 0.595), DecorPlacementRules.R_SPOT, "on the moss cushion"],
		[PIN, Vector2(0.5, 0.48), DecorPlacementRules.R_PROP, "on the basket"],
		[PIN, Vector2(0.9, 0.4), DecorPlacementRules.R_PROP, "under the tea nook"],
	]
	for row: Array in cases:
		assert_eq(rules.validate(row[0], row[1], none, ctx), row[2], String(row[3]))
	assert_eq(rules.validate(PIN, Vector2(0.9, 0.4), none, {"nests": [], "tea": false}), DecorPlacementRules.VALID,
		"the nook is an exclusion only when tea is on")
	var nest_ctx := {"nests": [open], "tea": true}
	assert_eq(rules.validate(PIN, rules.offset_norm(open, Vector2(0.0, 4.0)), none, nest_ctx), DecorPlacementRules.R_NEST,
		"a built nest stays visible")
	assert_eq(rules.validate(&"wind_chime", open, none, ctx), DecorPlacementRules.R_NOT_MOVABLE)
	for row: Array in cases:
		var key := rules.hint_key(row[2])
		assert_true(key == "" or key.begins_with("DECOR_HINT_"))


func test_hint_keys_exist_in_the_string_table() -> void:
	var csv := FileAccess.get_file_as_string("res://i18n/strings.csv")
	for reason: StringName in [&"sky", &"low", &"edge", &"water", &"dry", &"flowers", &"spot", &"nest", &"prop",
			&"crowded", &"stack", &"returned"]:
		assert_true(csv.contains("\n%s," % rules.hint_key(reason)), "%s in strings.csv" % rules.hint_key(reason))


func test_spacing_between_pieces() -> void:
	var o := _open(TOAD, 22.0)
	var layout: Array[Dictionary] = [DecorPlacementRules.make_piece(PIN, 0, o, true)]
	assert_eq(rules.validate(PIN, rules.offset_norm(o, Vector2(6.0, 0.0)), layout, ctx), DecorPlacementRules.R_CROWDED,
		"same set under 12 dp")
	assert_eq(rules.validate(PIN, rules.offset_norm(o, Vector2(20.0, 0.0)), layout, ctx), DecorPlacementRules.VALID)
	assert_eq(rules.validate(TOAD, rules.offset_norm(o, Vector2(8.0, 0.0)), layout, ctx), DecorPlacementRules.R_CROWDED,
		"different sets keep their footprints 4 dp apart")
	assert_eq(rules.validate(PIN, o, layout, ctx, "leaf_pinwheel#0"), DecorPlacementRules.VALID, "a piece ignores itself")


func test_cairn_drop_on_a_stack_merges_up_to_ten() -> void:
	var o := _open(DecorPlacementRules.CAIRN, 10.0)
	var layout: Array[Dictionary] = []
	for i in 10:
		var p := DecorPlacementRules.make_piece(DecorPlacementRules.CAIRN, i, o, true)
		if i > 0:
			p["stack"] = "pebble_cairn#0"
			p["level"] = i
		layout.append(p)
	assert_eq(rules.validate(DecorPlacementRules.CAIRN, o, layout, ctx), DecorPlacementRules.R_STACK,
		"a full stack takes no more")
	layout.resize(5)
	var near := rules.offset_norm(o, Vector2(5.0, 0.0))
	assert_eq(rules.validate(DecorPlacementRules.CAIRN, near, layout, ctx), VALID, "within 14 dp it merges")
	assert_eq(rules.merge_target(near, layout), "pebble_cairn#0")


# ----------------------------------------------------------------- snapping, nudge (§4.4, §5)

func test_snap_pulls_to_a_socket_in_reach_and_leaves_free_drops_alone() -> void:
	var none := _empty()
	var anchors: Array = (c.anchors_by_decor[PIN] as Dictionary)["positions"]
	var a := Vector2(float(anchors[1][0]), float(anchors[1][1]))
	var near := rules.offset_norm(a, Vector2(8.0, 0.0))
	var s := rules.snap(PIN, near, none, ctx)
	assert_true(bool(s["socket"]), "8 dp from a legacy anchor: snapped")
	assert_almost_eq(rules.dist_dp(s["pos"], a), 0.0, 0.01)
	var free := _open(PIN, 20.0)
	var f := rules.snap(PIN, free, none, ctx)
	assert_false(bool(f["socket"]), "nothing in reach: free placement is real")
	assert_eq(f["pos"], free)
	var m := rules.magnet(PIN, near, none, ctx)
	assert_true(rules.dist_dp(m, a) < rules.dist_dp(near, a) and rules.dist_dp(m, a) > 0.0,
		"the magnet pulls part of the way only")


func test_sockets_are_valid_and_family_ordered() -> void:
	var o := _open(TOAD, 20.0)
	var layout: Array[Dictionary] = [DecorPlacementRules.make_piece(TOAD, 0, o, true),
		DecorPlacementRules.make_piece(TOAD, 1, rules.offset_norm(o, Vector2(10.0, 0.0)), true),
		DecorPlacementRules.make_piece(TOAD, 2, rules.offset_norm(o, Vector2(0.0, 10.0)), true)]
	var socks := rules.sockets(TOAD, layout, ctx)
	assert_gt(socks.size(), 10)
	var fams := {}
	for s: Dictionary in socks:
		assert_eq(rules.validate(TOAD, s["pos"], layout, ctx), DecorPlacementRules.VALID)
		fams[s["family"]] = true
	assert_true(fams.has(&"ring_around_cluster"), "three toadstools form a fairy-ring socket set")
	for s: Dictionary in rules.sockets(STONE, _empty(), ctx):
		assert_true(rules.water_dist_dp(s["pos"]) <= 11.5 + 1e-3, "stone sockets lie in the water")


func test_invalid_drop_nudges_within_48_dp_or_floats_home() -> void:
	var none := _empty()
	var near_bed := Vector2(0.5, 0.69 - 15.0 / 640.0)
	var n := rules.nudge(PIN, near_bed, none, ctx)
	assert_true(bool(n["ok"]), "valid ground a few dp away")
	assert_eq(rules.validate(PIN, n["pos"], none, ctx), DecorPlacementRules.VALID)
	assert_lt(rules.dist_dp(n["pos"], near_bed), 48.0 + 1e-3)
	var far_from_water := Vector2(0.5, 0.55)
	var d := rules.resolve_drop(STONE, far_from_water, none, ctx, "stream_stones#0")
	assert_false(bool(d["ok"]), "no water within 48 dp: the stone floats home")
	assert_eq(d["reason"], DecorPlacementRules.R_DRY)


func test_beautify_jitter_is_small_seeded_and_repeatable() -> void:
	var p := _open(PIN, 10.0)
	var a := rules.jitter("leaf_pinwheel#3", p)
	assert_eq(a, rules.jitter("leaf_pinwheel#3", p), "the same drop looks the same")
	assert_lt(rules.dist_dp(a, p), 1.5 * sqrt(2.0) + 1e-3)
	assert_ne(a, rules.jitter("leaf_pinwheel#4", p))


# ----------------------------------------------------------------- operations through the sim

func test_move_settles_commits_and_emits_only_after_the_settle() -> void:
	var sim := _sim({PIN: 3})
	sim.drain_events()
	var bad := sim.active.move(sim, "leaf_pinwheel#0", Vector2(0.5, 0.48))
	assert_true(bool(bad["ok"]) == false or sim.active.decor.validate(PIN, bad["pos"], sim.state.decor_layout,
		sim.active.context(sim), "leaf_pinwheel#0") == DecorPlacementRules.VALID, "never left on an invalid spot")
	sim.drain_events()
	var home := Vector2(0.5, 0.2)
	var before := TestUtil.canonical(sim.state.decor_layout)
	var fail := sim.active.move(sim, "leaf_pinwheel#0", home)
	assert_false(bool(fail["ok"]), "the sky has no ground within 48 dp")
	assert_eq(TestUtil.canonical(sim.state.decor_layout), before, "a float home changes nothing")
	assert_true(_events(sim, WorldSim.EV_DECOR_PLACED).is_empty(), "and emits no decor_placed")
	var dest := _open(PIN, 10.0)
	var ok := sim.active.move(sim, "leaf_pinwheel#0", dest, 2)
	assert_true(bool(ok["ok"]))
	var ev := _events(sim, WorldSim.EV_DECOR_PLACED)
	assert_eq(ev.size(), 1, "one decor_placed per settle")
	assert_eq(int(ev[0]["rot_deg"]), 180)
	var rec: Dictionary = sim.state.decor_layout[DecorPlacementRules.find(sim.state.decor_layout, "leaf_pinwheel#0")]
	assert_almost_eq(rules.dist_dp(Vector2(rec["x"], rec["y"]), dest), 0.0, 2.2, "free placement, jitter only")


func test_turn_store_take_out_and_undo() -> void:
	var sim := _sim({PIN: 2, STONE: 2})
	sim.active.set_edit_mode(sim, true)
	assert_eq(sim.active.turn(sim, "leaf_pinwheel#1"), 1)
	assert_eq(sim.active.turn(sim, "stream_stones#0"), 1)
	assert_eq(sim.active.turn(sim, "stream_stones#0"), 0, "stones have two steps")
	var owned := sim.owned_count(STONE)
	var lam := sim.lambda_per_h()
	assert_true(sim.active.store(sim, "stream_stones#1"))
	assert_eq(sim.owned_count(STONE), owned, "tucked away is still owned")
	assert_eq(sim.lambda_per_h(), lam, "attraction counts owned copies: tidying never costs a friend")
	assert_eq(sim.active.decor_placed_count(sim, STONE), 1, "wish gates read placed pieces")
	assert_eq(sim.item_count(STONE), owned)
	var out := sim.active.take_out(sim, STONE, Vector2.INF)
	assert_true(bool(out["ok"]), "Find a spot")
	assert_eq(sim.active.decor_placed_count(sim, STONE), 2)
	var before := TestUtil.canonical(sim.state.decor_layout)
	assert_true(sim.active.move(sim, "leaf_pinwheel#0", _open(PIN, 10.0))["ok"])
	assert_true(sim.active.undo(sim), "one step back")
	assert_eq(TestUtil.canonical(sim.state.decor_layout), before)
	assert_false(sim.active.undo(sim), "only one step")
	sim.active.set_edit_mode(sim, false)
	assert_false(sim.active.can_undo(), "exit clears the undo step")


func test_cairn_lift_a_pebble_and_merge_back() -> void:
	var sim := _sim({DecorPlacementRules.CAIRN: 4})
	var layout := sim.state.decor_layout
	assert_eq(rules.stack_size(layout, "pebble_cairn#0"), 4)
	var top := sim.active.lift_pebble(sim, "pebble_cairn#0")
	assert_eq(top, "pebble_cairn#3")
	assert_eq(rules.stack_size(sim.state.decor_layout, "pebble_cairn#0"), 3)
	assert_true(sim.active.move(sim, top, _open(DecorPlacementRules.CAIRN, 10.0))["ok"], "a new stack of one")
	var base: Dictionary = sim.state.decor_layout[DecorPlacementRules.find(sim.state.decor_layout, "pebble_cairn#0")]
	var res := sim.active.move(sim, top, rules.offset_norm(Vector2(base["x"], base["y"]), Vector2(6.0, 0.0)))
	assert_true(bool(res["ok"]))
	assert_eq(String(res["merge"]), "pebble_cairn#0", "dropped on the stack: merged")
	assert_eq(rules.stack_size(sim.state.decor_layout, "pebble_cairn#0"), 4)
	assert_true(sim.active.store(sim, "pebble_cairn#0"), "a stack is put away whole")
	assert_eq(rules.placed_count(sim.state.decor_layout, DecorPlacementRules.CAIRN), 0)


func test_a_purchase_is_auto_placed_on_valid_ground() -> void:
	var sim := _sim({})
	sim.state.dew = 99999
	for i in 10:
		assert_true(sim.buy_decor(PIN))
	assert_true(sim.buy_decor(DecorPlacementRules.CAIRN) and sim.buy_decor(DecorPlacementRules.CAIRN))
	assert_true(sim.buy_decor(&"wind_chime"))
	var ctx2 := sim.active.context(sim)
	var pins := 0
	for p: Dictionary in sim.state.decor_layout:
		assert_false(bool(p["stored"]))
		if StringName(p["set"]) == PIN:
			pins += 1
			assert_eq(rules.validate(PIN, Vector2(p["x"], p["y"]), sim.state.decor_layout, ctx2, String(p["id"])), VALID,
				"%s on valid ground" % p["id"])
	assert_eq(pins, 10)
	assert_eq(rules.stack_size(sim.state.decor_layout, "pebble_cairn#0"), 2, "a new pebble joins the stack")
	assert_eq(DecorPlacementRules.find(sim.state.decor_layout, "wind_chime#0"), -1, "the chime is not in the layout")


func test_derived_spots_follow_the_placed_pieces() -> void:
	var sim := _sim({TOAD: 3})
	sim.active.refresh_spots(sim)
	var authored := Vector2(0.32, 0.43)
	var ring := sim.active.spot_pos(&"toadstool_ring")
	assert_lt(rules.dist_dp(ring, authored), 30.0, "the ring at its anchors stays about where it was")
	var at := _open(TOAD, 20.0)
	sim.active.move(sim, "toadstool_seat#0", at)
	sim.active.move(sim, "toadstool_seat#1", rules.offset_norm(at, Vector2(16.0, 0.0)))
	sim.active.move(sim, "toadstool_seat#2", rules.offset_norm(at, Vector2(8.0, 14.0)))
	sim.active.refresh_spots(sim)
	assert_lt(rules.dist_dp(sim.active.spot_pos(&"toadstool_ring"), rules.offset_norm(at, Vector2(8.0, 5.0))), 12.0,
		"the fairy ring forms where the toadstools now stand")
	for id: String in ["toadstool_seat#0", "toadstool_seat#1", "toadstool_seat#2"]:
		sim.active.store(sim, id)
	sim.active.refresh_spots(sim)
	assert_eq(sim.active.spot_pos(&"toadstool_ring"), authored, "everything tucked away: the authored spot")


# ----------------------------------------------------------------- Active F1 link (decor_near)

func test_decor_near_wish_is_granted_now_or_on_arrival() -> void:
	var sim := _sim({PIN: 3, DecorPlacementRules.CAIRN: 1})
	var t := 1000.0
	ActiveTestUtil.arrive(sim, &"primpip", t)
	ActiveTestUtil.give_wish(sim, &"primpip", &"cairn_nearby")
	sim.drain_events()
	var fav := sim.active.favourite_spot_pos(sim, &"primpip")
	var spot := rules.offset_norm(fav, Vector2(-40.0, 0.0))
	var res := sim.active.move(sim, "pebble_cairn#0", spot)
	assert_true(bool(res["ok"]), "a cairn beside the stump hollow")
	assert_eq(_events(sim, WorldSim.EV_WISH_GRANTED).size(), 1, "granted when the piece settles")
	# away: the piece set near the spot is remembered and the wish is granted on the next arrival
	ActiveTestUtil.arrive(sim, &"pebblepaw", t + 700.0)
	ActiveTestUtil.give_wish(sim, &"pebblepaw", &"pinwheel_nearby")
	ActiveTestUtil.depart(sim, &"pebblepaw", t + 710.0)
	var fav2 := sim.active.favourite_spot_pos(sim, &"pebblepaw")
	var res2 := sim.active.move(sim, "leaf_pinwheel#0", rules.offset_norm(fav2, Vector2(0.0, -60.0)))
	assert_true(bool(res2["ok"]))
	var w := sim.active.wishes.wish_of(sim, &"pebblepaw")
	assert_true(bool(w.get("placed", false)), "placed while away")
	sim.drain_events()
	ActiveTestUtil.arrive(sim, &"pebblepaw", t + 5000.0)
	var g := _events(sim, WorldSim.EV_WISH_GRANTED)
	assert_eq(g.size(), 1)
	assert_true(bool(g[0]["on_arrival"]))
