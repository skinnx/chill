extends GutTest
## Active F2 Tea & Treats front end (GDD §14.11 FE-T, ACTIVE_TEA §2-§10): the stir and pour gesture
## maths, the Brew panel's touch targets (jars 56 dp, cups 48 dp, pills 48 dp, gaps >= 8 dp), tap
## and drag petals in (a drag released off the pot floats home, nothing lost), drops charged and
## refunded, the stir drag counting both directions inside the ring only, pour and Simple brewing
## filling the tray, the offer row and an offering, the recipe book and "Fill the pot", the bed's
## petal branch (priority 5, gather, world_action), the glints and the bed card's tea line.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const DP := 3.0
const PANEL := Vector2(936.0, 1250.0)
const GARDEN := {&"sweet_clover": 2, &"button_daisy": 2, &"buttercup": 1, &"moonbloom": 2, &"primrose": 1}
const CLOVER := &"sweet_clover"
const FRIEND := &"puffmoss"
const T0 := 1000.0
## The stir annulus in ring-space px (tea.json 28 / 150 dp at 3 px per dp).
const INNER := 84.0
const OUTER := 450.0
## The Brew panel at the sheet's large detent on a 1080x1920 frame (ui_sheet detents and
## tea_sheet's tab offsets), which is what makes the drawn ring flatter than the dead radius.
const REAL_PANEL := Vector2(936.0, 1092.0)
## RING_R.x / RING_R.y: how flat the drawn progress ring is.
const RING_ASPECT := 176.0 / 64.0
const PLOTS := preload("res://scenes/garden/plots_layer.tscn")

var c: GameContent
var _saved_sim: WorldSim
var _saved_ready: bool
var _saved_content: GameContent
var _saved_persist: bool


func before_all() -> void:
	c = ContentRegistry.content


func before_each() -> void:
	_saved_sim = Game.sim
	_saved_ready = Game.is_ready
	_saved_content = Game.content
	_saved_persist = Settings.persist
	Settings.persist = false
	Game.content = c
	var sim := ActiveTestUtil.quiet_sim(c)
	ActiveTestUtil.set_garden(sim, c, GARDEN, {}, -1.0e5)
	sim.advance(T0)
	sim.state.tea_unlocked = true
	sim.state.seed_planted = true
	sim.state.dew = 100
	sim.state.pantry = {"sweet_clover": 5, "button_daisy": 3, "buttercup": 2}
	sim.state.met[String(FRIEND)] = sim.unix_at(T0 - 86400.0)
	ActiveTestUtil.arrive(sim, FRIEND, T0)
	sim.drain_events()
	Game.sim = sim
	# no world clock: Game's tea API acts on the sim as it stands
	Game.is_ready = false


func after_each() -> void:
	Settings.persist = _saved_persist
	Game.sim = _saved_sim
	Game.is_ready = _saved_ready
	Game.content = _saved_content


func _pot() -> TeaPot:
	var p := TeaPot.new()
	p.theme = UiTheme.theme
	p.size = PANEL
	add_child_autofree(p)
	p.calm = true
	return p


func _jar(p: TeaPot, flower: StringName) -> int:
	return p.jar_flowers.find(flower)


# ------------------------------------------------------------------ gesture maths

## A point on the drawn (flat) ring at [param deg] of ring-space angle, [param rx] px wide.
func _on_ring(deg: float, rx: float) -> Vector2:
	var a := deg_to_rad(deg)
	return Vector2(cos(a) * rx, sin(a) * rx / RING_ASPECT)


## Walks a circle of [param radius] px around the mouth; returns the degrees the pot credited.
func _walk_ring(radius: float, total_deg: float, steps: int) -> float:
	var total := 0.0
	var last := Vector2(radius, 0.0)
	for i in range(1, steps + 1):
		var q := Vector2.from_angle(deg_to_rad(total_deg * float(i) / float(steps))) * radius
		total += TeaPot.stir_delta(last, q, INNER, OUTER)
		last = q
	return total


func test_stir_counts_motion_around_the_mouth_in_either_direction() -> void:
	assert_almost_eq(_walk_ring(200.0, 180.0, 18), 180.0, 0.01, "half a turn clockwise = 180 deg")
	var back := TeaPot.stir_delta(Vector2.from_angle(deg_to_rad(90.0)) * 200.0,
			Vector2.from_angle(deg_to_rad(60.0)) * 200.0, INNER, OUTER)
	assert_true(absf(back) > 0.0 and back < 0.0, "the other way counts too (the pot adds |deg|)")
	assert_almost_eq(_walk_ring(200.0, -360.0, 36), -360.0, 0.01, "a full turn anticlockwise = -360 deg")


func test_stir_ignores_the_centre_and_far_away_and_caps_a_wrap() -> void:
	assert_eq(TeaPot.stir_delta(Vector2(200, 0), Vector2(20, 20), INNER, OUTER), 0.0,
			"inside the dead middle: a scribble")
	assert_eq(TeaPot.stir_delta(Vector2(200, 0), Vector2(600, 0).rotated(1.0), INNER, OUTER), 0.0, "past 150 dp")
	assert_eq(TeaPot.stir_delta(Vector2.from_angle(deg_to_rad(5.0)) * 200.0,
			Vector2.from_angle(deg_to_rad(183.0)) * 200.0, INNER, OUTER), 0.0,
			"a near-diameter sample is a line across the pot, so the chord test already refuses it")
	# With no dead middle the chord test cannot fire, and the wrap guard is what is left: wrapf
	# keeps |delta| <= 180, so the cap has to bite below that or a thumb that jumps half the pot
	# would read as a sweep the other way.
	assert_almost_eq(TeaPot.stir_delta(Vector2.from_angle(deg_to_rad(5.0)) * 200.0,
			Vector2.from_angle(deg_to_rad(183.0)) * 200.0, 0.0, OUTER), TeaPot.STIR_MAX_DEG, 0.5,
			"one sample never carries a near-half turn")


## Both ends of a sample must be in the ring, AND the line between them must miss the dead middle,
## or press-on-the-liquid-and-flick-outwards (or straight across the pot) would finish the stir
## with no circle at all. ACTIVE_TEA §4: "a scribble through the centre adds nothing strange".
func test_a_pull_or_a_flick_through_the_middle_is_not_a_stir() -> void:
	assert_eq(TeaPot.stir_delta(Vector2(10, 0), Vector2(0, 150), INNER, OUTER), 0.0,
			"the previous end was in the dead middle: nothing is credited")
	assert_eq(TeaPot.stir_delta(Vector2(0, 150), Vector2(10, 0), INNER, OUTER), 0.0, "and neither way round")
	assert_eq(TeaPot.stir_delta(Vector2(-200, 0), Vector2(200, 0), INNER, OUTER), 0.0,
			"straight across the pot: both ends in the ring, but the line goes through the middle")
	assert_almost_eq(TeaPot.stir_delta(_on_ring(90.0, 180.0), _on_ring(110.0, 180.0), INNER, OUTER),
			20.0, 0.01, "once the thumb is on the ring it counts again, with no jump")


## Nothing about the stir may depend on the frame rate: with Godot's input accumulation on, a
## handler sees one motion event per rendered frame, so the old flat 45°-per-EVENT ceiling counted
## a brisk circle for half as much at 30 fps. The same stroke now reads the same at any sampling
## rate - coarse chords and fine ones alike.
func test_the_same_stroke_counts_the_same_at_any_sampling_rate() -> void:
	# 1.5 turns, sampled as it would be at 30 fps (9 chords), at 60 fps (18) and raw (72).
	assert_almost_eq(_walk_ring(200.0, 540.0, 9), 540.0, 0.01, "coarse chords: the whole stroke counts")
	assert_almost_eq(_walk_ring(200.0, 540.0, 18), 540.0, 0.01, "60 fps")
	assert_almost_eq(_walk_ring(200.0, 540.0, 72), 540.0, 0.01, "a raw 240 Hz pointer agrees exactly")


## The outer bound stays a plain circle: a player who stirs a wide round circle rather than
## following the flat drawn ring keeps every degree of it.
func test_a_wide_round_stir_still_counts_in_full() -> void:
	assert_almost_eq(_walk_ring(210.0, 540.0, 54), 540.0, 0.01, "a 70 dp circle: 1.5 turns")


## The regression this ring-space work exists for: the progress ring is drawn as a flat ellipse
## (RING_R 176 x 64), so a circular dead zone swallowed its top and bottom. Tracing the ring the
## game drew has to credit a full turn, at the real panel size of the large detent.
func test_tracing_the_drawn_progress_ring_credits_a_whole_turn() -> void:
	var pot := TeaPot.new()
	autofree(pot)
	pot.size = REAL_PANEL
	var s: float = pot.pot_scale()
	var rx: float = TeaPot.RING_R.x * s
	var ry: float = TeaPot.RING_R.y * s
	assert_true(ry < pot.stir_inner_px(), "premise: the drawn ring's short radius is inside the dead radius")
	var total := 0.0
	var steps := 72
	var last := Vector2(rx, 0.0)
	for i in range(1, steps + 1):
		var a := TAU * float(i) / float(steps)
		var on_ring := Vector2(cos(a) * rx, sin(a) * ry)
		total += TeaPot.stir_delta(last, on_ring, pot.stir_inner_px(), pot.stir_outer_px())
		last = on_ring
	assert_almost_eq(absf(total), 360.0, 0.5, "every part of the drawn ring counts")


func test_pour_tilt_follows_the_thumb_toward_the_tray() -> void:
	var per := 40.0 * DP
	assert_almost_eq(TeaPot.pour_tilt(Vector2(0.6, 0.8) * per, per, 30.0, 55.0), 30.0, 0.01, "40 dp of travel = 30 deg")
	assert_eq(TeaPot.pour_tilt(Vector2(0.6, 0.8) * per * 4.0, per, 30.0, 55.0), 55.0, "at most 55 deg")
	assert_eq(TeaPot.pour_tilt(Vector2(0.0, -200.0), per, 30.0, 55.0), 0.0, "dragging away never tilts")


# ------------------------------------------------------------------ targets (I2)

func test_brew_panel_targets_and_gaps() -> void:
	var p := _pot()
	var min_play := 48.0 * DP
	var gap := 8.0 * DP
	for i in TeaPot.JARS:
		var r := p.jar_rect(i)
		assert_true(r.size.x >= min_play and r.size.y >= min_play, "jar %d >= 48 dp" % i)
		assert_true(Rect2(Vector2.ZERO, p.size).encloses(r), "jar %d inside the panel" % i)
		for j in range(i + 1, TeaPot.JARS):
			assert_false(r.grow(gap * 0.5 - 0.01).intersects(p.jar_rect(j).grow(gap * 0.5 - 0.01)),
					"jars %d / %d >= 8 dp apart" % [i, j])
	for i in 6:
		var t := p.tray_rect(i)
		assert_true(t.size.x >= min_play, "cup %d >= 48 dp" % i)
		assert_true(t.position.x >= 0.0 and t.end.x <= p.size.x, "cup %d inside" % i)
		for j in range(i + 1, 6):
			assert_false(t.grow(gap * 0.5 - 0.01).intersects(p.tray_rect(j).grow(gap * 0.5 - 0.01)), "cups apart")
	assert_true(p.pot_area().end.y <= p.jars_top(), "the pot area stays above the pantry")


# ------------------------------------------------------------------ petals in and out

func test_tap_a_jar_adds_one_petal_and_the_pot_holds_three() -> void:
	var p := _pot()
	var j := _jar(p, CLOVER)
	assert_true(p.tap_jar(j))
	assert_eq(p.petals_in_pot().size(), 1)
	assert_eq(int(Game.pantry()[String(CLOVER)]), 4, "taken from its jar")
	p.tap_jar(j)
	p.tap_jar(j)
	assert_false(p.tap_jar(j), "a 4th petal: the jar bobs, nothing moves")
	assert_eq(p.petals_in_pot().size(), 3)
	assert_eq(int(Game.pantry()[String(CLOVER)]), 2, "nothing charged for the refused petal")


func test_tap_a_petal_in_the_pot_returns_it() -> void:
	var p := _pot()
	p.tap_jar(_jar(p, CLOVER))
	assert_true(p.take_out(0))
	assert_true(p.petals_in_pot().is_empty())
	assert_eq(int(Game.pantry()[String(CLOVER)]), 5, "back in its jar")


func test_a_drop_is_charged_and_refunded() -> void:
	var p := _pot()
	p.tap_jar(_jar(p, CLOVER))
	assert_true(p.tap_jar(TeaPot.DROP_JAR))
	assert_eq(Game.sim.state.dew, 97, "3 dew when the drop goes in")
	assert_true(p.take_out(p.petals_in_pot().size()))
	assert_eq(Game.sim.state.dew, 100, "refunded when taken out")


func test_drag_a_petal_into_the_pot_or_let_it_float_home() -> void:
	var p := _pot()
	var j := _jar(p, CLOVER)
	var from := p.jar_rect(j).get_center()
	p.press(from)
	p.move(from + Vector2(0, -60))
	p.release(p.pot_foot() + TeaPot.BODY * p.pot_scale())
	assert_eq(p.petals_in_pot().size(), 1, "dropped over the pot: in")
	p.press(from)
	p.move(from + Vector2(0, -60))
	p.release(Vector2(10, 10))
	assert_eq(p.petals_in_pot().size(), 1, "released elsewhere: it floats home")
	assert_eq(int(Game.pantry()[String(CLOVER)]), 4, "nothing lost")


# ------------------------------------------------------------------ stir, pour, simple brew

func test_the_stir_drag_then_the_pour_fills_a_cup() -> void:
	var p := _pot()
	p.tap_jar(_jar(p, CLOVER))
	p.tap_jar(_jar(p, CLOVER))
	assert_eq(p.step(), &"stir")
	var centre := p.stir_centre()
	var r := 70.0 * DP
	p.press(centre + Vector2(r, 0))
	for k in 60:
		# counter-clockwise, small steps: one and a half turns and a bit
		p.move(centre + Vector2.from_angle(-TAU * float(k + 1) / 36.0) * r)
	p.release(centre + Vector2.from_angle(-TAU * 60.0 / 36.0) * r)
	assert_almost_eq(float(Game.pot()["stir_deg"]), 540.0, 0.01, "1.5 turns, either direction")
	assert_eq(p.step(), &"pour")
	watch_signals(p)
	p.pour()
	assert_true(p.is_busy(), "the pour plays to its end by itself")
	p.qa_advance(1.3)
	assert_signal_emitted(p, "brewed")
	var tray := Game.tray()
	assert_eq(tray.size(), 1)
	assert_eq(StringName(String(tray[0]["recipe"])), &"clover_tea")
	assert_true(Game.recipes_found().has("clover_tea"), "into the book")


func test_a_short_tilt_springs_back_and_pours_nothing() -> void:
	var p := _pot()
	p.tap_jar(_jar(p, CLOVER))
	for k in 3:
		p.stir_step()
	assert_eq(p.step(), &"pour")
	var at := p.pot_foot() + TeaPot.BODY * p.pot_scale()
	p.press(at)
	p.move(at + Vector2(0.6, 0.8) * 20.0 * DP)
	p.release(at + Vector2(0.6, 0.8) * 20.0 * DP)
	p.qa_advance(1.5)
	assert_true(Game.tray().is_empty(), "released before 30 deg: nothing spills")
	assert_eq(p.petals_in_pot().size(), 1, "the pot keeps its petal")


func test_simple_brewing_is_one_tap() -> void:
	var p := _pot()
	p.simple = true
	p.tap_jar(_jar(p, CLOVER))
	p.tap_jar(_jar(p, CLOVER))
	assert_eq(p.step(), &"brew")
	p.brew_simple()
	p.qa_advance(1.0)
	assert_eq(Game.tray().size(), 1, "brewed without stirring")


func test_a_full_tray_keeps_the_pot() -> void:
	var p := _pot()
	for i in 6:
		Game.sim.state.tray.append({"recipe": "meadow_tea", "made_unix": 0.0, "drops": 0, "petals": ["sweet_clover"]})
	p.refresh()
	p.tap_jar(_jar(p, CLOVER))
	p.brew_simple()
	assert_false(p.is_busy(), "no brew with the tray full")
	assert_eq(p.petals_in_pot().size(), 1)


# ------------------------------------------------------------------ the sheet

func _sheet() -> TeaSheet:
	var s := TeaSheet.new()
	s.theme = UiTheme.theme
	s.size = Vector2(1032.0, 1700.0)
	s.position = Vector2(24.0, 300.0)
	add_child_autofree(s)
	return s


func test_the_offer_row_lists_visitors_and_an_offering_reacts() -> void:
	Game.sim.state.tray.append({"recipe": "clover_tea", "made_unix": 0.0, "drops": 0,
		"petals": ["sweet_clover", "sweet_clover"]})
	var s := _sheet()
	assert_eq(TeaSheet.offer_order(), [FRIEND] as Array[StringName])
	s.open_offer(0)
	assert_true(s.pot.offer_mode, "the pantry rows give way to the friends")
	var chip := s.find_child("Chip_%s" % FRIEND, true, false) as Button
	assert_not_null(chip)
	assert_true(chip.custom_minimum_size.x >= 64.0 * DP, "64 dp chips")
	var aff := Game.sim.affection_of(FRIEND)
	s.offer_to(0, FRIEND)
	assert_true(Game.tray().is_empty(), "the cup went to the friend")
	assert_gt(Game.sim.affection_of(FRIEND), aff, "puffmoss loves clover tea")
	var text := TeaSheet.reaction_text({"reaction": "loved", "petals_back": 0}, "Bơ", "Trà")
	assert_false(text.is_empty())
	await get_tree().process_frame


func test_the_recipe_book_and_fill_the_pot() -> void:
	var s := _sheet()
	s.select_tab(TeaSheet.TAB_RECIPES, false)
	var cards := 0
	for n: Node in s.find_children("*", "GridContainer", true, false):
		cards += n.get_child_count()
	assert_eq(cards, c.recipes.size(), "every recipe has a card (secrets included)")
	assert_true(TeaSheet.can_fill(&"clover_tea"))
	assert_false(TeaSheet.can_fill(&"moonlight_tea"), "no moonbloom petals yet")
	assert_true(s.fill_pot(&"clover_tea"))
	assert_eq(s.current_tab(), TeaSheet.TAB_BREW)
	assert_eq(c.match_recipe(Game.pot()["petals"], int(Game.pot()["drops"])), &"clover_tea")
	await get_tree().process_frame


func test_teaware_tab_opens_after_the_first_brew() -> void:
	assert_false(TeaSheet.teaware_open())
	Game.sim.state.recipes_found["meadow_tea"] = 1.0
	assert_true(TeaSheet.teaware_open())


# ------------------------------------------------------------------ beds and the world

func test_a_bed_with_petals_ranks_like_a_ready_bud_and_gathers() -> void:
	Game.is_ready = true
	var p: PlotsLayer = PLOTS.instantiate()
	add_child_autofree(p)
	p._sync_all()
	var bed := &"bed_1"
	assert_gt(Game.petals_ready(bed), 0, "bloomed long ago: full stems")
	var bv: PlotsLayer.BedView = p._beds[bed]
	assert_eq(p._prio(bv), WorldPan.PRIO_PETAL_BED)
	assert_false(p._glint_extras(bv).is_empty(), "glints rest on the leaves")
	var before := 0
	for f: String in Game.pantry():
		before += int(Game.pantry()[f])
	watch_signals(p)
	p._tap_bed(bv)
	var after := 0
	for f: String in Game.pantry():
		after += int(Game.pantry()[f])
	assert_gt(after, before, "petals into the pantry")
	assert_signal_emitted(p, "petals_gathered")
	assert_true(p._flight.is_flying(), "they arc to the nook")
	assert_not_null(TeaNook.current)
	assert_true(TeaNook.current.visible, "the nook is awake")


func test_the_nook_is_a_prio_4_target_that_opens_the_sheet() -> void:
	Game.is_ready = true
	var p: PlotsLayer = PLOTS.instantiate()
	add_child_autofree(p)
	var nook := TeaNook.current
	assert_not_null(nook)
	var canvas := p.get_global_transform_with_canvas() * nook.hit_centre
	var hit := nook.world_hit(canvas, 27.0)
	assert_eq(int(hit.get("prio", -1)), WorldPan.PRIO_TEA_NOOK)
	watch_signals(nook)
	nook.world_press(hit["key"], canvas)
	nook.world_release(hit["key"], canvas, true)
	assert_signal_emitted(nook, "open_requested")
	nook.world_press(hit["key"], canvas)
	nook.world_release(hit["key"], canvas, false)
	assert_signal_emit_count(nook, "open_requested", 1, "a cancelled press never opens")


func test_the_bed_card_names_spare_petals() -> void:
	var text := TeaSheet.bed_card_text(&"bed_1", "Bed")
	assert_true(text.begins_with("Bed · "), text)
