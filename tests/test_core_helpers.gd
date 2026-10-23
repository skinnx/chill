extends GutTest
## Smaller contracts: name input rules (GDD §7.3), weather plan determinism and share (GDD §6.2),
## locale policy (GDD §7.6), settings validation (X1), recap ordering (GDD §7.5), audio pitch
## helpers, frame-rate divisors (C21).

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

var c: GameContent


func before_all() -> void:
	c = GameContent.load_from_dir()


func test_names_are_nfc_and_filtered() -> void:
	var decomposed := "Bế Bờ"  # "Bế Bờ" typed as base + combining marks
	assert_eq(NameRules.nfc(decomposed), "Bế Bờ")
	assert_eq(NameRules.nfc("ợ"), "ợ", "marks are reordered canonically before composing")
	assert_eq(NameRules.sanitize("  Pip  🌱 the   Great!!  "), "Pip the Grea",
			"emoji and ! dropped, spaces collapsed, 12 chars")
	assert_eq(NameRules.sanitize("🌱🌱"), "", "nothing usable -> default name")
	assert_eq(NameRules.sanitize("Đóm-đóm's."), "Đóm-đóm's.")


func test_weather_plan_is_deterministic_and_mostly_clear() -> void:
	var a := WeatherPlan.new(c, 1234)
	var b := WeatherPlan.new(c, 1234)
	var counts := {&"clear": 0, &"breeze": 0, &"rain": 0}
	var t := 0.0
	var day := 86400.0
	while t < 60.0 * day:
		var w := a.weather_at(1792454400.0 + t)
		assert_eq(w, b.weather_at(1792454400.0 + t))
		counts[w] = int(counts[w]) + 1
		t += 1800.0
	var n := float(int(counts[&"clear"]) + int(counts[&"breeze"]) + int(counts[&"rain"]))
	assert_between(int(counts[&"rain"]) / n, 0.02, 0.18, "soft rain ~8 % of the time (GDD §6.2)")
	assert_gt(int(counts[&"clear"]) / n, 0.6, "mostly clear")
	assert_ne(WeatherPlan.plan_seed(1234, 1), WeatherPlan.plan_seed(1234, 2))


func test_locale_policy() -> void:
	assert_eq(I18n.resolve("auto", "vi_VN"), "vi")
	assert_eq(I18n.resolve("auto", "en_US"), "en")
	assert_eq(I18n.resolve("auto", "fr_FR"), "en")
	assert_eq(I18n.resolve("vi", "en_US"), "vi")
	I18n.apply("vi")
	assert_eq(tr("DOCK_GARDEN"), "Khu vườn", "Vietnamese strings load from the CSV import")
	I18n.apply("en")
	assert_eq(tr("DOCK_GARDEN"), "Garden")
	assert_eq(I18n.fmt(&"GARDEN_OWNED", {"owned": 3, "max": 10}), "3 of 10")
	assert_eq(I18n.duration_text(2400.0), "40 min")
	assert_eq(I18n.duration_text(5400.0), "1 h 30 min")
	I18n.apply(Settings.get_string(Settings.LANGUAGE))


func test_settings_validation() -> void:
	assert_eq(Settings.validate(Settings.TEXT_SCALE, 140), 130)
	assert_eq(Settings.validate(Settings.TEXT_SCALE, 999), 200)
	assert_eq(Settings.validate(Settings.VOLUME_MUSIC, 47), 50)
	assert_eq(Settings.validate(Settings.VOLUME_MUSIC, -3), 0)
	assert_eq(Settings.validate(Settings.HAPTICS, "buzz"), "subtle")
	assert_eq(Settings.validate(Settings.MUSIC, "ambience"), "ambience")
	assert_eq(Settings.DEFAULTS[Settings.HAPTICS], "subtle", "GDD §7.6 default")


func test_recap_orders_lines_by_priority() -> void:
	var sim := WorldSim.new_game(c, 5, 1792454400.0, 0.0)
	var events: Array[Dictionary] = [
		{"type": WorldSim.EV_PHOTO, "species": &"puffmoss", "new": true, "t": 1.0},
		{"type": WorldSim.EV_STAGE, "stage": WorldSim.STAGE_BLOOM, "t": 2.0},
		{"type": WorldSim.EV_ARRIVED, "species": &"buttonbud", "debut": false, "t": 3.0},
		{"type": WorldSim.EV_MET, "species": &"bellkin", "t": 4.0},
	]
	var lines := Recap.build(sim, events, 0.0, 0.0)
	assert_eq(lines.size(), Recap.MAX_LINES)
	assert_eq(lines[0]["key"], &"RECAP_NEW_FRIEND")
	assert_eq(lines[1]["key"], &"RECAP_ONE_VISITED")
	assert_eq(lines[2]["key"], &"RECAP_BLOOMED")
	assert_false(Recap.should_show(c, 60.0, events), "short gaps show no recap")
	assert_true(Recap.should_show(c, 3600.0, events))


## Round 8 (GDD §7.5, §13.5.3): "{name} napped at the {spot}" takes the visitors slot when the
## absence had a nap in it - it says what a friend did, not just that somebody came.
func test_the_nap_line_takes_the_visitors_slot() -> void:
	var sim := WorldSim.new_game(c, 5, 1792454400.0, 0.0)
	var events: Array[Dictionary] = [
		{"type": WorldSim.EV_STAGE, "stage": WorldSim.STAGE_BLOOM, "t": 2.0},
		{"type": WorldSim.EV_ARRIVED, "species": &"buttonbud", "debut": false, "t": 3.0},
	]
	var without := Recap.build(sim, events, 0.0, 0.0)
	assert_eq(without[0]["key"], &"RECAP_ONE_VISITED", "no nap: the visitors line as before")
	var nap := {"species": &"buttonbud", "spot": &"sun_stone", "seconds": 900.0}
	var with_nap := Recap.build(sim, events, 0.0, 0.0, nap)
	assert_eq(with_nap[0]["key"], &"RECAP_NAPPED")
	assert_eq(StringName(with_nap[0]["species"]), &"buttonbud")
	assert_eq(StringName(with_nap[0]["spot"]), &"sun_stone", "the spot rides along for the UI to name")
	assert_false(_has_key(with_nap, &"RECAP_ONE_VISITED"), "it replaces the visitors line, never doubles it")


## A friend who kept a wish is the warmest no-FOMO reason to come back the game has, and until
## now the welcome-back card never mentioned it. A wish never expires, so this is an offer and
## can never become a deadline (GDD §14.0 AP3).
func test_a_waiting_wish_is_offered_on_the_welcome_back_card() -> void:
	var sim := WorldSim.new_game(c, 5, 1792454400.0, 0.0)
	var events: Array[Dictionary] = [{"type": WorldSim.EV_STAGE, "stage": WorldSim.STAGE_BLOOM, "t": 2.0}]
	assert_eq(Recap.wish_waiting(sim), &"", "nothing pending: no line")
	sim.state.wishes.append({"species": &"puffmoss", "wish": &"cuddle", "opened_t": 50.0,
		"state": WorldState.WISH_HELD, "taps": 0, "placed": false})
	sim.state.wishes.append({"species": &"bellkin", "wish": &"cuddle", "opened_t": 10.0,
		"state": WorldState.WISH_OPEN, "taps": 0, "placed": false})
	assert_eq(Recap.wish_waiting(sim), &"bellkin", "the oldest wish still waiting")
	var lines := Recap.build(sim, events, 0.0, 0.0)
	assert_true(_has_key(lines, &"RECAP_WISH_WAITING"))
	assert_eq(StringName(_line(lines, &"RECAP_WISH_WAITING")["species"]), &"bellkin")


## The grant line and the waiting line are two halves of the same thought: never both.
func test_a_granted_wish_suppresses_the_waiting_line() -> void:
	var sim := WorldSim.new_game(c, 5, 1792454400.0, 0.0)
	sim.state.wishes.append({"species": &"bellkin", "wish": &"cuddle", "opened_t": 10.0,
		"state": WorldState.WISH_OPEN, "taps": 0, "placed": false})
	var events: Array[Dictionary] = [
		{"type": WorldSim.EV_WISH_GRANTED, "species": &"puffmoss", "wish": &"cuddle", "on_arrival": true, "t": 5.0}]
	var lines := Recap.build(sim, events, 0.0, 0.0)
	assert_true(_has_key(lines, &"RECAP_WISH"))
	assert_false(_has_key(lines, &"RECAP_WISH_WAITING"))


func _has_key(lines: Array[Dictionary], key: StringName) -> bool:
	for l: Dictionary in lines:
		if StringName(l["key"]) == key:
			return true
	return false


func _line(lines: Array[Dictionary], key: StringName) -> Dictionary:
	for l: Dictionary in lines:
		if StringName(l["key"]) == key:
			return l
	return {}


func test_harmony_helpers_match_theory_py() -> void:
	var fmaj9 := [5, 7, 9, 0, 2]
	assert_eq(Harmony.snap(64, fmaj9), 65, "E snaps up to F (ties prefer +1 before -1)")
	assert_eq(Harmony.snap(66, fmaj9), 67)
	assert_eq(Harmony.pent_step(65, 2, fmaj9), 69)
	assert_eq(Harmony.pent_step(65, -1, fmaj9), 62)
	var from_json: Array = JSON.parse_string("[5, 7, 9, 0, 2]")
	assert_eq(Harmony.pent_step(65, 2, from_json), 69, "JSON float sets work (Array.has is type-strict)")
	assert_eq(Harmony.pc_list(from_json), fmaj9)
	assert_eq(Harmony.wrap_into(40, 53, 64), 64)
	assert_eq(Harmony.place_pc(5, 53, 64), 53)
	assert_eq(Harmony.nearest_rendered({53: "a", 55: "b"}, 54), 53)
	assert_almost_eq(Harmony.pitch_scale(54, 53), pow(2.0, 1.0 / 12.0), 1e-9)
	assert_almost_eq(AudioDirector.slider_to_db(80), 0.0, 1e-9)
	assert_almost_eq(AudioDirector.slider_to_db(40), 30.0 * log(0.5) / log(10.0), 1e-9)


func test_audio_buses_follow_the_bus_graph() -> void:
	for name: String in ["Music", "Ambience", "SFX", "UI"]:
		assert_true(AudioServer.get_bus_index(name) > 0, "%s bus exists" % name)
	var master := AudioServer.get_bus_index("Master")
	var has_limiter := false
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			has_limiter = true
			assert_almost_eq((AudioServer.get_bus_effect(master, i) as AudioEffectHardLimiter).ceiling_db, -1.5, 1e-6)
	assert_true(has_limiter, "Master has the -1.5 dB hard limiter (06 §0.2)")
	var music := AudioServer.get_bus_index("Music")
	var lpf := AudioServer.get_bus_effect(music, 0) as AudioEffectLowPassFilter
	assert_not_null(lpf)
	assert_almost_eq(lpf.resonance, 0.5, 1e-6, "never 0 (06 §2.5 gotcha 4)")


func test_frame_rate_divisors() -> void:
	assert_eq(FrameGovernor._divisor_rate(30), 30)
	assert_true(FrameGovernor.target_fps() == 30 or FrameGovernor.target_fps() == 60)


func test_haptics_modes_filter_tick() -> void:
	Settings.persist = false  # never write the developer's settings.cfg
	var was := Haptics.mode
	Haptics.mode = Haptics.SUBTLE
	assert_eq(Settings.get_string(Settings.HAPTICS), "subtle", "mode persists through Settings")
	var n := Haptics.played_count
	Haptics.play(Haptics.TICK)
	assert_eq(Haptics.played_count, n, "Subtle never plays TICK")
	Haptics.start_repeat(Haptics.TICK, 120)
	assert_false(Haptics.is_repeating(), "Subtle never repeats TICK")
	Haptics.play_for_cue({"subtle": null, "full": "TICK"})
	assert_eq(Haptics.played_count, n, "a Full-only cue is silent in Subtle")
	Haptics.mode = Haptics.OFF
	Haptics.play(Haptics.MEDIUM)
	assert_eq(Haptics.played_count, n, "Off plays nothing")
	Haptics.mode = &"loud"
	assert_true(Haptics.mode in [Haptics.OFF, Haptics.SUBTLE, Haptics.FULL], "invalid mode is coerced")
	Haptics.mode = Haptics.FULL
	Haptics.start_repeat(Haptics.TICK, 120)
	assert_true(Haptics.is_repeating(), "Full repeats TICK (S03)")
	Haptics.stop_repeat()
	assert_false(Haptics.is_repeating())
	Haptics.mode = was
	Settings.persist = true
