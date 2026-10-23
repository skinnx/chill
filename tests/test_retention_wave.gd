extends GutTest
## Retention v1 ♥1 "waves hello on open" (GDD §13.2, friendship.json wave_on_open): the one beat
## designed to make a RETURN feel personal. The plan has been in the sim and tested since P1, but
## nothing in the view ever ran it - these cases pin the wiring.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const LAYER_SCENE := "res://scenes/creatures/creature_layer.tscn"
const SEED := 1234

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


## The retention_mid world (hearts 1-5, friends in the hollow) as Game.sim.
func _world() -> WorldSim:
	var st := WorldSim.new_game(c, SEED, Clock.now_unix(), 0.0).state
	GardenFixture.apply(c, st, GardenFixture.MID)
	var sim := WorldSim.new(c, st)
	RetentionFixture.apply(sim, StringName(c.scenes[0]["id"]))
	sim = WorldSim.new(c, st)
	# Two friends who know you, in the hollow: wave_plan only ever looks at state.present.
	for sp: StringName in [&"puffmoss", &"buttonbud"]:
		if not sim.is_present(sp):
			st.present.append({"species": String(sp), "arrive_t": st.t, "depart_t": INF, "gift_dew": 0,
				"gift_item": "", "boat_credit": true, "pet_credit": true, "scripted": false,
				"greeter": false, "cousin": ""})
	sim = WorldSim.new(c, st)
	sim.drain_events()
	Game.sim = sim
	Game.is_ready = true
	return sim


func _layer() -> CreatureLayer:
	var l: CreatureLayer = (load(LAYER_SCENE) as PackedScene).instantiate()
	add_child_autofree(l)
	return l


## The pose has to be a real motion, not a silent no-op: friendship.json names it "wave", and
## DelightPose is what turns a pose id into movement.
func test_the_wave_pose_is_a_real_motion() -> void:
	assert_eq(DelightPose.motion_of(&"wave"), DelightPose.SWAY,
			"the friend turns to the camera and rocks (GDD §13.2)")


func test_world_ready_arms_the_plan_the_sim_already_computes() -> void:
	var sim := _world()
	var l := _layer()
	l._on_world_ready([])
	var plan: Array[Dictionary] = Game.wave_plan()
	assert_eq(l._waves.size(), plan.size(), "the view runs exactly the sim's plan")
	assert_lte(l._waves.size(), int(c.friendship["wave_on_open"]["max_wavers"]), "at most 3 friends")
	for w: Dictionary in l._waves:
		assert_gte(sim.hearts_of(StringName(w["species"])), int(c.friendship["wave_on_open"]["min_hearts"]),
				"only friends who know you")


## "when the app opens or resumes and the recap closes": a hello is for the player, not for the
## back of the welcome-back card.
func test_nobody_waves_while_a_card_is_covering_the_hollow() -> void:
	_world()
	var l := _layer()
	l._on_world_ready([])
	assert_false(l._waves.is_empty(), "premise: somebody is ready to wave")
	var pan := WorldPan.new()
	add_child_autofree(pan)
	pan.blocked = func() -> bool: return true
	l._wave_tick(5.0)
	assert_false(l._waves.is_empty(), "the plan waits for the card")
	pan.blocked = func() -> bool: return false
	l._wave_tick(5.0)
	assert_true(l._waves.is_empty(), "and runs once the hollow is clear")


func test_each_friend_waves_after_its_own_delay_and_only_once() -> void:
	_world()
	var l := _layer()
	l._on_world_ready([])
	var pan := WorldPan.new()
	add_child_autofree(pan)
	pan.blocked = func() -> bool: return false
	var first := float(l._waves[0]["delay_s"])
	assert_gte(first, float(c.friendship["wave_on_open"]["delay_min_s"]), "a beat before the first hello")
	l._wave_tick(first * 0.5)
	assert_false(l._waves.is_empty(), "not yet")
	l._wave_tick(first)
	for w: Dictionary in l._waves:
		assert_gt(float(w["delay_s"]), first, "only the ones whose turn has not come are left")
	l._wave_tick(100.0)
	assert_true(l._waves.is_empty())
	l._wave_tick(100.0)
	assert_true(l._waves.is_empty(), "an empty plan is a no-op, not a repeat")
