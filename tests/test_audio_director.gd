extends GutTest
## AudioDirector and Haptics rules that need no audio device (AUDIO_BIBLE §7, §8.6, §8.7,
## §8.10). Headless runs use the Dummy driver: nothing is heard, but every rule still runs.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const SAMPLES := 200
const MIDI_OCTAVE := 12
const CUE_COLLECT := "S02"
const CUE_TAP := "S01"
const CUE_WATER := "S06"
const CUE_WELCOME := "S10"

var _captions: Array[Dictionary] = []
var _haptics_was: StringName


func before_all() -> void:
	Settings.persist = false  # mode changes below must not reach the developer's settings.cfg


func after_all() -> void:
	Settings.persist = true


func before_each() -> void:
	_captions.clear()
	_haptics_was = Haptics.mode


func after_each() -> void:
	Haptics.mode = _haptics_was
	if AudioDirector.cue_played.is_connected(_on_cue_played):
		AudioDirector.cue_played.disconnect(_on_cue_played)


func _on_cue_played(cue_id: StringName, caption_key: StringName, world_position: Vector2) -> void:
	_captions.append({"id": cue_id, "caption": caption_key, "position": world_position})


func _cue(id: String) -> Dictionary:
	return (AudioDirector.manifest["cues"] as Dictionary)[id]


func _layer(id: String) -> Dictionary:
	return (_cue(id)["layers"] as Array)[0]


func _bank_of(id: String) -> Dictionary:
	return (AudioDirector.manifest["banks"] as Dictionary)[String(_layer(id)["bank"])]


func _range_of(bank: Dictionary) -> Vector2i:
	var r: Array = bank["range"]
	return Vector2i(int(r[0]), int(r[1]))


func _in_set(midi: int) -> bool:
	return AudioDirector.current_pcs().has(posmod(midi, MIDI_OCTAVE))


func test_manifest_is_loaded_with_rendered_assets() -> void:
	assert_false(AudioDirector.manifest.is_empty(), "res://audio/manifest.json parsed")
	assert_true(AudioDirector.has_audio, "the manifest lists rendered assets")
	assert_ne(AudioDirector.current_chord(), &"", "a chord is sounding from the start")


func test_ladder_climbs_caps_and_resets() -> void:
	var layer := _layer(CUE_COLLECT)
	var bank := _bank_of(CUE_COLLECT)
	var r := _range_of(bank)
	var pitch: Dictionary = layer["pitch"]
	var cap := int(pitch["cap"])
	AudioDirector._state(CUE_COLLECT).clear()
	var notes: Array[int] = []
	for i in cap + 3:
		notes.append(AudioDirector._pick_note(CUE_COLLECT, layer, bank, {}))
	for i in range(1, cap + 1):
		assert_gt(notes[i], notes[i - 1], "each collect in a burst steps up the set")
	assert_eq(notes[cap + 1], notes[cap], "the ladder stops at %d steps" % cap)
	for n: int in notes:
		assert_true(n >= r.x and n <= r.y and _in_set(n), "ladder note %d in range and set" % n)
	AudioDirector._state(CUE_COLLECT)["last_t"] = Clock.ticks_s() - float(pitch["reset_s"]) - 1.0
	assert_eq(AudioDirector._pick_note(CUE_COLLECT, layer, bank, {}), notes[0], "resets after reset_s")


func test_walk_reflects_at_the_bank_range_and_stays_in_the_set() -> void:
	var layer := _layer(CUE_TAP)
	var bank := _bank_of(CUE_TAP)
	var r := _range_of(bank)
	AudioDirector._state(CUE_TAP).clear()
	var first := AudioDirector._pick_note(CUE_TAP, layer, bank, {})
	assert_eq(first, Harmony.snap(int((layer["pitch"] as Dictionary)["start"]), AudioDirector.current_pcs()))
	var outside := 0
	var repeats := 0
	var last := first
	for i in SAMPLES:
		var n := AudioDirector._pick_note(CUE_TAP, layer, bank, {})
		if n < r.x or n > r.y or not _in_set(n):
			outside += 1
		if n == last:
			repeats += 1
		last = n
	assert_eq(outside, 0, "every walk note is in the bank range and the chord set")
	assert_eq(repeats, 0, "a walk always moves one set member")


func test_variants_never_repeat_back_to_back() -> void:
	var bank := _bank_of(CUE_WATER)
	AudioDirector._state(CUE_WATER).clear()
	var last: Variant = null
	var seen := {}
	var repeats := 0
	for i in SAMPLES:
		var stream := AudioDirector._pick_variant(CUE_WATER, bank, false)
		assert_not_null(stream)
		var k: Variant = AudioDirector._state(CUE_WATER)["last_variant"]
		if k == last:
			repeats += 1
		seen[k] = true
		last = k
	assert_eq(repeats, 0)
	assert_eq(seen.size(), (bank["variants"] as Dictionary).size(), "every variant is used")


func test_chord_hold_stays_in_range() -> void:
	var hold: Array = (AudioDirector.manifest["music_flow"] as Dictionary)["chord_hold_bars"]
	var seen := {}
	for i in SAMPLES:
		var bars := AudioDirector._hold_bars()
		assert_between(bars, int(hold[0]), int(hold[1]))
		seen[bars] = true
	assert_true(seen.has(int(hold[0])) and seen.has(int(hold[1])), "both ends of the range occur")


func test_bed_targets_follow_profile_and_weather() -> void:
	var clear := AudioDirector._bed_targets(&"day", &"clear")
	var rain := AudioDirector._bed_targets(&"day", &"rain")
	var night := AudioDirector._bed_targets(&"night", &"clear")
	var night_rain := AudioDirector._bed_targets(&"night", &"rain")
	assert_gt(float(clear["amb_stream"]), 0.0)
	assert_almost_eq(float(clear["amb_rain"]), 0.0, 1e-9, "no rain bed when dry")
	assert_almost_eq(float(rain["amb_stream"]), 0.0, 1e-9, "rain replaces the stream")
	assert_almost_eq(float(rain["amb_rain"]), float(clear["amb_stream"]), 1e-6, "at the stream's level")
	assert_lt(float(rain["amb_breeze"]), float(clear["amb_breeze"]), "rain adds -4 dB on the breeze")
	assert_almost_eq(float(clear["amb_crickets"]), 0.0, 1e-9, "no crickets by day")
	assert_gt(float(night["amb_crickets"]), 0.0, "crickets at night")
	assert_almost_eq(float(night_rain["amb_crickets"]), 0.0, 1e-9, "rain silences the crickets")


func test_volume_slider_curve() -> void:
	assert_almost_eq(AudioDirector.slider_to_db(100), 2.907, 1e-3)
	assert_almost_eq(AudioDirector.slider_to_db(50), -6.124, 1e-3)
	assert_almost_eq(AudioDirector.slider_to_db(10), -27.093, 1e-3)
	assert_eq(AudioDirector.slider_to_db(0), AudioDirector.MIN_DB, "0 mutes")


func test_play_cue_reports_its_caption() -> void:
	AudioDirector.cue_played.connect(_on_cue_played)
	var at := Vector2(120, 340)
	AudioDirector.play_cue(StringName(CUE_WATER), {"position": at, "haptic": false})
	AudioDirector.play_cue(&"S99", {})
	assert_eq(_captions.size(), 1, "unknown cues are ignored")
	assert_eq(_captions[0]["caption"], StringName(String(_cue(CUE_WATER)["caption"])))
	assert_eq(_captions[0]["position"], at)


func test_collect_burst_plays_one_double() -> void:
	Haptics.mode = Haptics.FULL
	_clear_min_gap()
	var n := Haptics.played_count
	AudioDirector.play_cue(StringName(CUE_COLLECT))
	_clear_min_gap()
	AudioDirector.play_cue(StringName(CUE_COLLECT))
	assert_eq(Haptics.played_count, n + 1, "one DOUBLE per Collect-all burst (S02)")
	assert_eq(Haptics.last_kind, Haptics.DOUBLE)


func test_welcome_haptic_plays_once() -> void:
	Haptics.mode = Haptics.SUBTLE
	Haptics._once_played.clear()
	_clear_min_gap()
	var n := Haptics.played_count
	var hap: Dictionary = _cue(CUE_WELCOME)["haptic"]
	Haptics.play_for_cue(hap, StringName(CUE_WELCOME))
	_clear_min_gap()
	Haptics.play_for_cue(hap, StringName(CUE_WELCOME))
	assert_eq(Haptics.played_count, n + 1, "S10 MEDIUM once per session")
	assert_eq(Haptics.last_kind, Haptics.MEDIUM)


## The 60 ms minimum gap is wall-clock; GUT's waits count physics deltas, which can run ahead of
## wall time while the engine catches up after a slow frame, so tests reset the gap instead.
func _clear_min_gap() -> void:
	Haptics._last_ms = -Haptics._min_gap_ms - 1
