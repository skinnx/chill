extends Control
## Boot scene (docs/ARCHITECTURE.md §3): opaque splash in ui.surface (#F0EEE9, the same colour as
## project.godot boot_splash and the Android splash, so launch looks like one calm surface), then
##   1. start background loads (main scene, audio assets),
##   2. warm up every shader and font behind the splash (C8),
##   3. Game.boot(): load the save or start a new install, offline catch-up, recap,
##   4. switch to the main scene, which fades its own cover out of the same colour.

const MAIN_SCENE := "res://scenes/main.tscn"
const WARMUP_FRAMES := 2

@onready var _warmup: ShaderWarmup = $WarmupStage
@onready var _splash: ColorRect = $Splash


func _ready() -> void:
	var ui: Dictionary = ContentRegistry.palettes()["ui"]
	var surface: String = ui["surface"]
	_splash.color = Color.html(surface)
	ResourceLoader.load_threaded_request(MAIN_SCENE)
	AudioDirector.request_preload()
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame  # the splash is on screen before any work starts
	await _warmup.run(WARMUP_FRAMES)
	Game.boot()
	var packed := ResourceLoader.load_threaded_get(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("Boot: could not load %s" % MAIN_SCENE)
		return
	get_tree().change_scene_to_packed(packed)
