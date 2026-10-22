extends SceneTree
## Audio smoke run (AUDIO_BIBLE §8.10): boots the game, then plays every manifest cue with each
## context the pitch rules read, the purr loop, weather/phase/sheet/music-mode changes, and quits
## through Game.quit_cleanly. Needs a real display server (Xvfb) so the AudioDirector plays:
##   xvfb-run -a godot --path . --rendering-driver opengl3_es --audio-driver Dummy \
##     --resolution 270x480 --fixed-fps 30 -s res://tools/qa/audio_smoke.gd -- --no-save
## Exit code 0 = every step ran; check stderr for SCRIPT ERROR lines.

const BOOT_SCENE := "res://scenes/boot.tscn"
const WARM_FRAMES := 240
const STEP_FRAMES := 6
const FINAL_FRAMES := 90

var _frame: int = 0
var _steps: Array[Callable] = []
var _next_step_at: int = 0
var _quitting: bool = false


func _initialize() -> void:
	change_scene_to_file(BOOT_SCENE)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == WARM_FRAMES:
		_build_steps()
		_next_step_at = _frame
	if _frame >= WARM_FRAMES and not _quitting and _frame >= _next_step_at:
		if _steps.is_empty():
			_quitting = true
			_next_step_at = _frame + FINAL_FRAMES
			print("audio_smoke: all steps ran; chord=%s" % _director().call("current_chord"))
		else:
			var step: Callable = _steps.pop_front()
			step.call()
			_next_step_at = _frame + STEP_FRAMES
	elif _quitting and _frame >= _next_step_at:
		root.get_node("Game").call("quit_cleanly", 0)
	return false


func _director() -> Node:
	return root.get_node("AudioDirector")


func _build_steps() -> void:
	var ad := _director()
	var cues: Dictionary = (ad.get("manifest") as Dictionary).get("cues", {})
	var ids: Array = cues.keys()
	ids.sort()
	for id: Variant in ids:
		var cue_id := StringName(str(id))
		_steps.append(Callable(ad, &"play_cue").bind(cue_id, {"voice_step": 2, "shells": 3, "position": Vector2(100, 200)}))
	_steps.append(Callable(ad, &"play_cue").bind(&"S01", {"world": true}))
	_steps.append(Callable(ad, &"play_cue").bind(&"S12", {"voice_step": -2, "nap": true}))
	_steps.append(Callable(ad, &"play_cue").bind(&"S15", {"on": false}))
	_steps.append(Callable(ad, &"play_cue").bind(&"S21", {"gust": true, "shells": 5, "haptic": false}))
	for _i in 8:
		_steps.append(Callable(ad, &"play_cue").bind(&"S02"))
	_steps.append(Callable(ad, &"start_purr").bind(2))
	_steps.append(Callable(ad, &"stop_purr"))
	_steps.append(Callable(ad, &"set_world_state").bind(4, PackedInt32Array([0, 2, -2]), 1))
	_steps.append(Callable(ad, &"set_weather").bind(&"rain", true))
	_steps.append(Callable(ad, &"set_phase").bind(&"night", false))
	_steps.append(Callable(ad, &"set_sheet_open").bind(true))
	_steps.append(Callable(ad, &"set_sheet_open").bind(false))
	_steps.append(Callable(ad, &"set_music_mode").bind(&"ambience"))
	_steps.append(Callable(ad, &"set_music_mode").bind(&"off"))
	_steps.append(Callable(ad, &"set_music_mode").bind(&"on"))
	_steps.append(Callable(ad, &"debug_set_clock").bind(&"dusk", &"breeze"))
	_steps.append(Callable(ad, &"set_mono").bind(true))
	_steps.append(Callable(ad, &"set_mono").bind(false))
