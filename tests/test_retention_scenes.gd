extends GutTest
## Away scenes on stage (Retention v1 F3, GDD §13.4) - round 11. The sim has picked, cast,
## staged, lingered and archived scenes since P1; these cases pin the view: the cast reaches its
## slots (present friends walk, absent ones are summoned), the props are drawn and tappable, a tap
## on either archives the scene, and everyone goes back to their day.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const PROPS_SCENE := "res://scenes/world/scene_props.tscn"
const LAYER_SCENE := "res://scenes/creatures/creature_layer.tscn"
const SEED := 4242
const SCREEN := Vector2(1080, 1920)
const DP := 3.0

var c: GameContent
var _saved_sim: WorldSim
var _saved_ready: bool
var _saved_content: GameContent


func before_all() -> void:
	c = GameContent.load_from_dir()


func before_each() -> void:
	_saved_sim = Game.sim
	_saved_ready = Game.is_ready
	_saved_content = Game.content
	Game.content = c


func after_each() -> void:
	Game.sim = _saved_sim
	Game.is_ready = _saved_ready
	Game.content = _saved_content


## The retention_mid world with [param scene] pending (cast by the real casting rule).
func _world(scene: StringName) -> WorldSim:
	var st := WorldSim.new_game(c, SEED, Clock.now_unix(), 0.0).state
	GardenFixture.apply(c, st, GardenFixture.MID)
	var sim := WorldSim.new(c, st)
	RetentionFixture.apply(sim, scene)
	sim = WorldSim.new(c, st)
	sim.drain_events()
	Game.sim = sim
	Game.is_ready = true
	return sim


func _props() -> SceneLayer:
	var l: SceneLayer = (load(PROPS_SCENE) as PackedScene).instantiate()
	add_child_autofree(l)
	l.sync()
	return l


func _canvas(l: Node2D, p: Vector2) -> Vector2:
	return l.get_global_transform_with_canvas() * p


# ------------------------------------------------------------------ geometry

func test_anchors_and_slots_follow_the_data() -> void:
	var sun: Dictionary = c.spots_by_id[&"sun_stone"]
	assert_eq(SceneLayer.anchor_px(c, &"nap_pile", []), Vector2(float(sun["x"]) * SCREEN.x, float(sun["y"]) * SCREEN.y),
			"a spot anchor is the spot")
	var tower: Dictionary = c.scenes_by_id[&"pebble_tower"]
	var a: Dictionary = tower["anchor"]
	var ap := Vector2(float(a["x"]) * SCREEN.x, float(a["y"]) * SCREEN.y)
	assert_eq(SceneLayer.anchor_px(c, &"pebble_tower", []), ap, "a frame anchor is the frame point")
	var off: Array = (tower["roles"][1] as Dictionary)["slot_dp"]
	assert_eq(SceneLayer.slot_px(c, &"pebble_tower", 1, []), ap + Vector2(float(off[0]), float(off[1])) * DP,
			"a role's slot is anchor + slot_dp at 3 px/dp")
	var poff: Array = (tower["props"][0] as Dictionary)["slot_dp"]
	assert_eq(SceneLayer.prop_px(c, &"pebble_tower", 0, []), ap + Vector2(float(poff[0]), float(poff[1])) * DP)


func test_the_pair_nap_sits_at_the_leads_nest() -> void:
	_world(&"pair_nap")
	var cast: Array = Game.pending_scene()["cast"]
	assert_eq(cast.size(), 2, "premise: a pair")
	var lead := StringName(String(cast[0]))
	var nest := Game.nest_state(lead)
	var want: Vector2
	if nest.is_empty():
		var fav: Dictionary = c.spots_by_id[StringName(String(c.species_by_id[lead]["favourite_spot"]))]
		want = Vector2(float(fav["x"]) * SCREEN.x, float(fav["y"]) * SCREEN.y)
	else:
		want = Vector2(float(nest["x"]) * SCREEN.x, float(nest["y"]) * SCREEN.y)
	assert_eq(SceneLayer.anchor_px(c, &"pair_nap", cast), want, "the lead's nest, else its favourite spot")


func test_every_scene_pose_maps_to_something_a_mossling_can_do() -> void:
	var seen := {}
	for sc: Dictionary in c.scenes:
		var anchor := Vector2(500.0, 1000.0)
		for r: Dictionary in sc["roles"]:
			var off: Array = r["slot_dp"]
			var slot := anchor + Vector2(float(off[0]), float(off[1])) * DP
			var pose := SceneLayer.scene_pose(StringName(String(r["pose"])), slot, anchor)
			var beh := StringName(String(pose["behaviour"]))
			assert_true(beh in [Mossling.B_NAP, Mossling.B_STREAM, SceneLayer.IDLE], "%s -> %s" % [r["pose"], beh])
			seen[beh] = true
	assert_eq(seen.size(), 3, "the three kinds are all used: sleep, sit by the brook, stand and beam")
	assert_eq(StringName(String(SceneLayer.scene_pose(&"scene_pile_top", Vector2.ZERO, Vector2.ZERO)["behaviour"])),
			Mossling.B_NAP, "the pile sleeps")
	var proud := SceneLayer.scene_pose(&"scene_tower_proud", Vector2(100.0, 0.0), Vector2.ZERO)
	assert_eq(float(proud["params"]["look"]), 0.0, "the proud builder looks at you")
	var admirer := SceneLayer.scene_pose(&"scene_tower_admire", Vector2(100.0, 0.0), Vector2.ZERO)
	assert_lt(float(admirer["params"]["look"]), 0.0, "the admirer looks at the tower (to its left)")
	assert_gt(float(admirer["params"]["happy_s"]), 0.0, "and beams")


func test_a_scene_prop_ranks_with_a_sign_below_a_friend() -> void:
	assert_eq(WorldPan.PRIO_SCENE, WorldPan.PRIO_SIGN)
	assert_lt(WorldPan.PRIO_SCENE, WorldPan.PRIO_MOSSLING)
	assert_gt(WorldPan.PRIO_SCENE, WorldPan.PRIO_READY_BED)


# ------------------------------------------------------------------ the props layer

func test_props_appear_with_the_scene_and_a_tap_on_one_archives_it() -> void:
	var sim := _world(&"pebble_tower")
	var before := sim.state.memories.size()
	var l := _props()
	assert_eq(l.scene_id(), &"pebble_tower")
	assert_eq(l._props.size(), 1, "the tower")
	assert_eq(l.a11y_label(), tr("A11Y_SCENE"))
	var foot: Vector2 = l._props[0]["pos"]
	var hit := l.world_hit(_canvas(l, foot + Vector2(0.0, -SceneLayer.HIT_DP * DP * 0.5)), 27.0)
	assert_false(hit.is_empty(), "the prop is a target")
	assert_eq(int(hit["prio"]), WorldPan.PRIO_SCENE)
	assert_true(l.world_hit(_canvas(l, foot + Vector2(900.0, 0.0)), 27.0).is_empty(), "only near it")
	assert_eq(l.world_hit_shapes().size(), 1)
	watch_signals(Game)
	l.world_press(0, _canvas(l, foot))
	assert_false(Game.pending_scene().is_empty(), "touch-down archives nothing")
	l.world_release(0, _canvas(l, foot), false)
	assert_false(Game.pending_scene().is_empty(), "a cancelled press archives nothing")
	l.world_press(0, _canvas(l, foot))
	l.world_release(0, _canvas(l, foot), true)
	assert_true(Game.pending_scene().is_empty(), "the tap archives the scene")
	assert_eq(sim.state.memories.size(), before + 1, "it is a memory now")
	assert_signal_emitted(Game, "scene_archived")
	assert_true(l.is_leaving(), "the props fade out")
	assert_true(l.world_hit(_canvas(l, foot), 27.0).is_empty(), "and are no longer a target")
	l._process(SceneLayer.FADE_OUT_S + 0.1)
	assert_eq(l.scene_id(), &"", "gone")
	assert_true(l._props.is_empty())


func test_a_scene_without_props_offers_no_prop_target() -> void:
	_world(&"nap_pile")
	var l := _props()
	assert_eq(l.scene_id(), &"nap_pile")
	assert_true(l._props.is_empty())
	assert_true(l.world_hit(_canvas(l, SceneLayer.anchor_px(c, &"nap_pile", [])), 27.0).is_empty(),
			"the pile is tapped on a friend, not on the ground")
	assert_true(l.world_hit_shapes().is_empty())


func test_the_same_scene_is_not_restaged_and_a_fresh_world_clears_it() -> void:
	_world(&"leaf_fort")
	var l := _props()
	l._process(1.0)
	var t := l._t
	l.sync()
	assert_eq(l._t, t, "syncing the same scene does not restart its fade")
	Game.sim = WorldSim.new_game(c, SEED, Clock.now_unix(), 0.0)
	l.sync()
	assert_true(l.is_leaving(), "no scene pending: the props leave")


# ------------------------------------------------------------------ the cast

func _layer() -> CreatureLayer:
	var l: CreatureLayer = (load(LAYER_SCENE) as PackedScene).instantiate()
	add_child_autofree(l)
	return l


## nap_pile with one of its three in the hollow already and two away: the visitor walks over
## under an override, the two others are summoned as extras; a tap on any of them archives the
## scene, the visitor goes back to its bouts and the extras walk off.
func test_the_cast_takes_its_slots_and_a_tap_on_a_participant_ends_the_scene() -> void:
	var sim := _world(&"nap_pile")
	var cast: Array = sim.state.pending_scene["cast"]
	assert_eq(cast.size(), 3, "premise")
	var here := StringName(String(cast[0]))
	if not sim.is_present(here):
		sim.state.present.append({"species": String(here), "arrive_t": sim.state.t, "depart_t": INF, "gift_dew": 0,
			"gift_item": "", "boat_credit": true, "pet_credit": true, "scripted": false, "greeter": false, "cousin": ""})
	for i in range(1, cast.size()):
		assert_false(sim.is_present(StringName(String(cast[i]))), "premise: the other two are away")
	var l := _layer()
	l._on_world_ready([])
	assert_eq(l.staged_scene(), &"nap_pile", "the pending scene is on stage at world_ready")
	assert_eq(l._scene_cast.size(), 3, "every role is filled")
	var visitor: Mossling = l._mosslings[here]
	assert_true(l.is_in_scene(visitor), "the visitor is in it")
	assert_eq(float(l._override_until[here]), INF, "and held there, away from the brain")
	assert_eq(l._scene_extras.size(), 2, "the two away friends were summoned")
	for m: Mossling in l._scene_extras:
		assert_true(l._extras.has(m), "an extra, like a greeter: never a visitor")
		assert_false(l._mosslings.values().has(m))
	# A second stage call for the same scene is a no-op (scene_ready after world_ready).
	l._stage_scene(Game.pending_scene())
	assert_eq(l._scene_cast.size(), 3)
	# The player looks.
	var before := sim.state.memories.size()
	l._on_tapped(visitor)
	assert_true(Game.pending_scene().is_empty(), "a tap on a participant archives the scene")
	assert_eq(sim.state.memories.size(), before + 1)
	assert_eq(l.staged_scene(), &"", "the stage is cleared through Game.scene_archived")
	assert_false(l._override_until.has(here), "the visitor is the brain's again")
	assert_false(l._commanded.has(here), "and gets a fresh command")
	assert_true(l._scene_cast.is_empty() and l._scene_extras.is_empty())
	var leaving := 0
	for m: Mossling in l._extras:
		if m.leaving:
			leaving += 1
	assert_eq(leaving, 2, "the summoned friends walk off")


func test_a_tap_on_a_friend_outside_the_scene_archives_nothing() -> void:
	var sim := _world(&"nap_pile")
	var cast: Array = sim.state.pending_scene["cast"]
	var bystander := &""
	for s: Dictionary in c.species:
		var sp := StringName(String(s["id"]))
		if not cast.has(String(sp)) and sim.is_met(sp):
			bystander = sp
			break
	assert_ne(bystander, &"", "premise")
	sim.state.present.append({"species": String(bystander), "arrive_t": sim.state.t, "depart_t": INF, "gift_dew": 0,
		"gift_item": "", "boat_credit": true, "pet_credit": true, "scripted": false, "greeter": false, "cousin": ""})
	var l := _layer()
	l._on_world_ready([])
	var m: Mossling = l._mosslings[bystander]
	assert_false(l.is_in_scene(m))
	l._on_tapped(m)
	assert_false(Game.pending_scene().is_empty(), "the scene waits for a look at the scene")
	assert_eq(l.staged_scene(), &"nap_pile")
