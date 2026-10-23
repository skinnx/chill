extends GutTest
## Nests in the hollow (Retention v1 F1, GDD §13.2.3) - round 11. The sim has built and grown
## nests since P1; these cases pin the half that was missing: the brain naps a friend in its own
## nest, the layer draws every nest the sim has, and the recap can name one.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const NESTS_SCENE := "res://scenes/world/nests.tscn"
const SEED := 4242
const HOUR := 3600.0
const SCREEN := Vector2(1080, 1920)

var c: GameContent
var _saved_sim: WorldSim
var _saved_ready: bool
var _saved_content: GameContent
var _saved_rm: Variant
var _saved_persist: bool


func before_all() -> void:
	c = GameContent.load_from_dir()


func before_each() -> void:
	_saved_sim = Game.sim
	_saved_ready = Game.is_ready
	_saved_content = Game.content
	_saved_persist = Settings.persist
	Settings.persist = false
	_saved_rm = Settings.get_value(Settings.REDUCE_MOTION)
	Game.content = c


func after_each() -> void:
	Settings.set_value(Settings.REDUCE_MOTION, _saved_rm)
	Settings.persist = _saved_persist
	Game.sim = _saved_sim
	Game.is_ready = _saved_ready
	Game.content = _saved_content


## The retention_mid world: three nests at the three stages (puffmoss canopy, buttonbud moss bed,
## pebblepaw twigs).
func _world() -> WorldSim:
	var st := WorldSim.new_game(c, SEED, Clock.now_unix(), 0.0).state
	GardenFixture.apply(c, st, GardenFixture.MID)
	var sim := WorldSim.new(c, st)
	RetentionFixture.apply(sim, StringName(c.scenes[0]["id"]))
	sim = WorldSim.new(c, st)
	sim.drain_events()
	Game.sim = sim
	Game.is_ready = true
	return sim


## A brain where [param nested] friends have a nest at their anchor and nobody else does.
func _brain(seed_v: int, nested: Array[StringName], phase: StringName = &"day") -> CreatureBrain:
	var b := CreatureBrain.new(c, seed_v)
	b.env = func(_t: float) -> Dictionary: return {"phase": phase, "weather": &"clear"}
	b.owned = func(_item: StringName) -> int: return 10
	b.bed_flowers = func(_bed: StringName) -> Array: return []
	b.nests = func(sp: StringName) -> Dictionary:
		if not nested.has(sp):
			return {}
		var a: Dictionary = c.nest_anchor_by_species[sp]
		return {"species": sp, "style": &"moss_bowl", "stage": 1, "x": float(a["x"]), "y": float(a["y"])}
	return b


func _signature(b: CreatureBrain) -> PackedStringArray:
	var out := PackedStringArray()
	for v: CreatureBrain.Visit in b.visits():
		for bout: CreatureBrain.Bout in v.bouts:
			out.append("%s %s %s %.1f %.1f %s" % [v.species, bout.behaviour, bout.spot, bout.start_t, bout.end_t, bout.pos])
	return out


# ------------------------------------------------------------------ the brain

func test_a_friend_with_a_nest_naps_in_it_most_of_the_time() -> void:
	var naps := 0
	var in_nest := 0
	var nest_spot := CreatureBrain.nest_spot(&"puffmoss")
	for seed_v in 6:
		var b := _brain(SEED + seed_v, [&"puffmoss"], &"night")
		b.add_visit(&"puffmoss", 100.0, 100.0 + 12.0 * HOUR)
		b.advance(100.0 + 12.0 * HOUR)
		for bout: CreatureBrain.Bout in b.visit(&"puffmoss").bouts:
			if bout.behaviour == CreatureBrain.NAP:
				naps += 1
				if bout.spot == nest_spot:
					in_nest += 1
					var a: Dictionary = c.nest_anchor_by_species[&"puffmoss"]
					assert_eq(bout.pos, Vector2(float(a["x"]) * SCREEN.x, float(a["y"]) * SCREEN.y),
							"the nest nap happens at the nest anchor")
					assert_false(bout.shelter, "a nest is not a shelter spot")
	assert_gt(naps, 20, "premise: a 12 h night visit naps a lot (%d)" % naps)
	var share := float(in_nest) / float(naps)
	# p = 0.7 per nap, less the no-repeat rule (two naps in a row never both in the nest).
	assert_between(share, 0.4, 0.75, "nest naps are the common case but not every time (%.2f)" % share)


func test_two_naps_in_a_row_are_never_both_in_the_nest() -> void:
	for seed_v in 6:
		var b := _brain(SEED + 50 + seed_v, [&"puffmoss"], &"night")
		b.add_visit(&"puffmoss", 100.0, 100.0 + 12.0 * HOUR)
		b.advance(100.0 + 12.0 * HOUR)
		var prev := ""
		for bout: CreatureBrain.Bout in b.visit(&"puffmoss").bouts:
			assert_ne(bout.key(), prev, "the (behaviour, spot) pair never repeats, the nest included")
			prev = bout.key()


func test_a_nest_is_only_ever_its_owners() -> void:
	var b := _brain(SEED, [&"puffmoss"], &"night")
	for sp: StringName in [&"puffmoss", &"buttonbud", &"pebblepaw", &"honeyhum"]:
		b.add_visit(sp, 100.0, 100.0 + 12.0 * HOUR)
	b.advance(100.0 + 12.0 * HOUR)
	var puff_nest := CreatureBrain.nest_spot(&"puffmoss")
	for v: CreatureBrain.Visit in b.visits():
		for bout: CreatureBrain.Bout in v.bouts:
			if v.species != &"puffmoss":
				assert_false(CreatureBrain.is_nest_spot(bout.spot), "%s never uses a nest it does not have" % v.species)
			else:
				assert_true(bout.spot != puff_nest or bout.behaviour == CreatureBrain.NAP, "the nest is for napping only")


## A friend without a nest plans exactly as before the nests existed: the extra draw only happens
## for a friend with one, so reloads of old saves still replay the same bouts. (Sharing the hollow
## with a nester can still shift its spots, because the nester leaves a shared spot free - that is
## the world changing, not the plan.)
func test_a_friend_without_a_nest_plans_exactly_as_before() -> void:
	var plain := CreatureBrain.new(c, SEED)
	plain.env = func(_t: float) -> Dictionary: return {"phase": &"night", "weather": &"clear"}
	plain.owned = func(_item: StringName) -> int: return 10
	plain.bed_flowers = func(_bed: StringName) -> Array: return []
	var nested := _brain(SEED, [&"puffmoss"], &"night")
	for b: CreatureBrain in [plain, nested]:
		b.add_visit(&"buttonbud", 100.0, 100.0 + 8.0 * HOUR)
		b.advance(100.0 + 8.0 * HOUR)
	assert_eq(_signature(nested), _signature(plain),
			"buttonbud (no nest) is bout-for-bout identical with nests in the world")
	assert_gt(_signature(plain).size(), 10)


func test_the_absence_replan_knows_about_nests() -> void:
	var sim := _world()
	var t := sim.state.t
	var found_nest := false
	for k in 8:
		var arrive := t - 9.0 * HOUR + float(k) * 7.0
		var events: Array[Dictionary] = [{"type": WorldSim.EV_ARRIVED, "species": &"puffmoss", "t": arrive,
			"depart_t": arrive + 8.0 * HOUR, "from_greeter": false}]
		var nap := CreatureBrain.nap_during(c, sim, events, t - 9.0 * HOUR, t)
		if CreatureBrain.is_nest_spot(StringName(String(nap.get("spot", "")))):
			found_nest = true
			break
	assert_true(found_nest, "with a nest, an absence's longest nap can be in it (the recap names it)")


# ------------------------------------------------------------------ the layer

func _layer() -> NestLayer:
	var l: NestLayer = (load(NESTS_SCENE) as PackedScene).instantiate()
	add_child_autofree(l)
	l.sync()
	return l


func test_the_layer_draws_every_nest_the_sim_has() -> void:
	_world()
	var l := _layer()
	var nests := Game.nests()
	assert_eq(nests.size(), 3, "premise: retention_mid has three nests")
	assert_eq(l._live.size(), 3, "one entry per nest")
	var stages := {}
	for sp: StringName in nests:
		var r := l.nest_rect(sp)
		var a: Dictionary = c.nest_anchor_by_species[sp]
		assert_lt(r.get_center().distance_to(Vector2(float(a["x"]) * SCREEN.x, float(a["y"]) * SCREEN.y)), 0.01,
				"%s sits on its anchor" % sp)
		assert_eq(r.size, Vector2(144.0, 72.0), "48 x 24 dp at 3 px/dp")
		stages[int(nests[sp]["stage"])] = true
		assert_string_contains(l.a11y_label(sp), Game.display_name(sp))
	assert_eq(stages.size(), 3, "the fixture shows twigs, moss bed and canopy at once")
	assert_false(l.is_in_group(WorldPan.GROUP_HIT), "a nest is not a tap target - the mossling in it is")
	assert_eq(l.nest_rect(&"moonpuff"), Rect2(), "no nest, no rect")
	assert_eq(l.a11y_label(&"moonpuff"), "")


func test_a_stage_reached_while_watching_pops_and_offline_growth_does_not() -> void:
	_world()
	var l := _layer()
	Game.nest_grew.emit(&"puffmoss", 2, true)
	assert_eq(float(l._live[&"puffmoss"]["pop"]), -1.0, "offline growth arrives with the recap, no pop")
	Game.nest_grew.emit(&"puffmoss", 2, false)
	assert_eq(float(l._live[&"puffmoss"]["pop"]), 0.0, "a stage reached while watching pops")
	l._process(NestLayer.POP_S + 0.1)
	assert_eq(float(l._live[&"puffmoss"]["pop"]), -1.0, "and settles")
	Settings.set_value(Settings.REDUCE_MOTION, true)
	Game.nest_grew.emit(&"buttonbud", 1, false)
	assert_eq(float(l._live[&"buttonbud"]["pop"]), -1.0, "Reduce Motion: no pop")


func test_nothing_disappears_and_a_new_world_is_taken_whole() -> void:
	_world()
	var l := _layer()
	for i in 20:
		l._process(1.0)
	assert_eq(l._live.size(), 3, "nests never go away")
	Game.sim = WorldSim.new_game(c, SEED, Clock.now_unix(), 0.0)
	l.sync()
	assert_eq(l._live.size(), 0, "a fresh world has none yet")


# ------------------------------------------------------------------ the recap line

func test_the_recap_names_a_nap_in_the_nest_by_its_style() -> void:
	_world()
	var o := OverlayHost.new()
	add_child_autofree(o)
	o.layout(SCREEN, Rect2(48, 72, 48, 127))
	var nest := Game.nest_state(&"puffmoss")
	var want := tr(String(nest["style_key"]))
	assert_ne(want, String(nest["style_key"]), "the style has a name")
	assert_eq(String(o._spot_name(CreatureBrain.nest_spot(&"puffmoss"))), want, "napped at the Moss bowl")
	assert_eq(String(o._spot_name(&"sun_stone")), tr(String(c.spots_by_id[&"sun_stone"]["name_key"])), "spots unchanged")
	assert_eq(o._spot_name(CreatureBrain.nest_spot(&"moonpuff")), &"", "no nest, no name")
