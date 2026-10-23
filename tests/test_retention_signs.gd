extends GutTest
## Mystery signs in the hollow (Retention v1 F2, GDD §13.3.2-13.3.3) — the view layer added in
## round 10. The sim side has been tested since P1; these cases pin the half that was missing:
## the signs are drawn, they are tappable at the right priority, tapping one takes its clue, and
## the Album can read the clues back.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const SIGNS_SCENE := "res://scenes/world/signs.tscn"
const SEED := 4242

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


## The retention_mid world: hearts, nests, and two open mysteries with a visible sign each.
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


func _layer() -> SignLayer:
	var l: SignLayer = (load(SIGNS_SCENE) as PackedScene).instantiate()
	add_child_autofree(l)
	l.sync()
	return l


# ------------------------------------------------------------------ the ladder

## GDD §13.3.2 extends §2.5: mossling > sign > ready bud > prop > décor > bed > stream. A clue is
## there to be found, so it outranks anything a tap could do to the ground it sits on.
func test_a_sign_outranks_the_ground_it_sits_on_but_never_a_friend() -> void:
	assert_gt(WorldPan.PRIO_SIGN, WorldPan.PRIO_READY_BED, "a sign beats a ready bud")
	assert_gt(WorldPan.PRIO_SIGN, WorldPan.PRIO_PROP)
	assert_gt(WorldPan.PRIO_SIGN, WorldPan.PRIO_BED)
	assert_gt(WorldPan.PRIO_SIGN, WorldPan.PRIO_STREAM)
	assert_lt(WorldPan.PRIO_SIGN, WorldPan.PRIO_MOSSLING, "but a friend always comes first")
	assert_lt(WorldPan.PRIO_MOSSLING, WorldPan.PRIO_CHOOSE_BED, "choose-a-bed still lifts beds above all")
	assert_lt(WorldPan.PRIO_CHOOSE_BED, WorldPan.PRIO_EDIT, "and edit mode above everything in play")


func test_the_edit_priorities_still_match_their_data() -> void:
	var hit: Dictionary = c.decor_placement["hit"]
	assert_eq(WorldPan.PRIO_EDIT, int(hit["prio_edit_piece"]), "the renumber kept data and code together")
	assert_eq(WorldPan.PRIO_EDIT_SELECTED, WorldPan.PRIO_EDIT + int(hit["prio_edit_selected_bonus"]))
	assert_eq(WorldPan.PRIO_STILL, int(hit["prio_still_piece_play"]))


# ------------------------------------------------------------------ the layer

func test_the_layer_shows_exactly_the_signs_the_sim_says_are_visible() -> void:
	var sim := _world()
	var l := _layer()
	var want: Array[Dictionary] = Game.visible_signs()
	assert_false(want.is_empty(), "premise: retention_mid has signs out")
	assert_lte(want.size(), int(c.mysteries["max_visible"]), "never more than max_visible at once")
	assert_eq(l._live.size(), want.size(), "the view holds one entry per visible sign")
	for s: Dictionary in want:
		assert_true(l._live.has(String(s["key"])), "%s is drawn" % s["key"])
	assert_not_null(sim)


func test_a_sign_is_a_world_target_at_its_anchor() -> void:
	_world()
	var l := _layer()
	var s: Dictionary = Game.visible_signs()[0]
	var centre: Vector2 = l._centre(s)
	assert_gt(centre.length(), 0.0, "the anchor resolves to a place in the frame")
	var hit := l.world_hit(l.get_global_transform_with_canvas() * centre, 27.0)
	assert_false(hit.is_empty(), "the sign can be pressed")
	assert_eq(int(hit["prio"]), WorldPan.PRIO_SIGN)
	assert_eq(String(hit["key"]), String(s["key"]))
	var far := l.get_global_transform_with_canvas() * (centre + Vector2(600.0, 0.0))
	assert_true(l.world_hit(far, 27.0).is_empty(), "and only near its anchor")


## The whole loop, as a player does it: press the sign, lift the finger, the clue is yours.
func test_tapping_a_sign_takes_its_clue_and_lifts_it_away() -> void:
	var sim := _world()
	var l := _layer()
	var s: Dictionary = Game.visible_signs()[0]
	var key := String(s["key"])
	var mystery := StringName(String(s["mystery"]))
	var before := int(Game.clues_for(mystery)["found"])
	var canvas: Vector2 = l.get_global_transform_with_canvas() * l._centre(s)
	watch_signals(l)
	l.world_press(key, canvas)
	assert_eq(int(Game.clues_for(mystery)["found"]), before, "touch-down takes nothing")
	l.world_release(key, canvas, true)
	assert_eq(int(Game.clues_for(mystery)["found"]), before + 1, "the clue is found on release")
	assert_signal_emitted(l, "sign_tapped")
	# It is on its way to the Album, so it is no longer something to press.
	assert_true(l.world_hit(canvas, 27.0).is_empty(), "a lifting sign is not a target")
	l._process(SignLayer.LIFT_S + 0.1)
	assert_false(l._live.has(key), "and it is gone once the lift ends")
	assert_not_null(sim)


func test_a_cancelled_press_takes_nothing() -> void:
	_world()
	var l := _layer()
	var s: Dictionary = Game.visible_signs()[0]
	var key := String(s["key"])
	var mystery := StringName(String(s["mystery"]))
	var before := int(Game.clues_for(mystery)["found"])
	var canvas: Vector2 = l.get_global_transform_with_canvas() * l._centre(s)
	l.world_press(key, canvas)
	l.world_release(key, canvas, false)  # the finger moved off: a pan, not a tap
	assert_eq(int(Game.clues_for(mystery)["found"]), before, "nothing is taken")
	assert_true(l._live.has(key), "and the sign stays where it is - it never expires")


## A sign that is never tapped waits for ever (G2: nothing is missable).
func test_a_sign_left_alone_stays() -> void:
	_world()
	var l := _layer()
	var key := String(Game.visible_signs()[0]["key"])
	for i in 200:
		l._process(1.0)
	assert_true(l._live.has(key), "200 s later it is still there to be found")


## Three bushes shaking in step would read as one animation, so the phase is per sign and stable.
func test_the_rustle_phase_is_deterministic_and_decorrelated() -> void:
	assert_eq(SignLayer.phase_of("a|0"), SignLayer.phase_of("a|0"), "stable for one sign")
	var seen := {}
	for k: String in ["honeyhum|0", "honeyhum|1", "bellkin|0", "capling|2"]:
		var p := SignLayer.phase_of(k)
		assert_between(p, 0.0, 1.0)
		seen[snappedf(p, 0.01)] = true
	assert_gt(seen.size(), 1, "different signs do not shake together")


func test_hit_shapes_are_reported_for_the_debug_overlay() -> void:
	_world()
	var l := _layer()
	var shapes := l.world_hit_shapes()
	assert_eq(shapes.size(), l._live.size(), "--debug-hits sees every sign")
	for sh: Dictionary in shapes:
		assert_eq(int(sh["prio"]), WorldPan.PRIO_SIGN)
		assert_gt(float(sh["r"]), 0.0)


# ------------------------------------------------------------------ Album › Clues

func test_the_album_reads_the_clues_back() -> void:
	_world()
	var cards := Game.clue_cards()
	assert_false(cards.is_empty(), "retention_mid has mysteries open")
	for card: Dictionary in cards:
		assert_true(bool(card.get("open", false)), "only opened mysteries get a card")
		assert_gt(int(card["total"]), 0, "and each has clues to find")
		assert_between(int(card["found"]), 0, int(card["total"]))


func test_the_clues_tab_sits_between_friends_and_photos() -> void:
	assert_eq(AlbumSheet.TAB_FRIENDS, 0)
	assert_eq(AlbumSheet.TAB_CLUES, 1)
	assert_eq(AlbumSheet.TAB_PHOTOS, 2)
	assert_eq(AlbumSheet.TAB_POSTCARDS, 3)
	for k: String in ["ALBUM_TAB_CLUES", "CLUES_EMPTY", "CLUES_SOMEONE", "CLUES_SOLVED", "CLUES_COUSIN",
			"CLUES_COUNT", "CLUE_FOUND_TITLE", "CLUE_ADDED"]:
		assert_ne(tr(k), k, "%s is translated" % k)
