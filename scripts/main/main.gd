extends Node2D
## Main scene: the hollow and its HUD (docs/ARCHITECTURE.md §3, Art Bible §2).
##
## Owns layout only: the bottom-anchored 1080x1920 design frame (Art Bible A1: World.position =
## (centring x, H - 1920), mirrored into g_world_offset), the static camera with its slow idle
## drift, and the intro (cover fade from the splash colour + camera settle, GDD §3.4). Layer
## content is built by the art/gameplay/UI owners inside the named nodes; this script only
## forwards lifecycle hooks to them.
##
## Debug user args: --debug-layout (gameplay layout overlay), --debug-hud (live sim readout),
## --log-events (print every sim event).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## GDD §3.4: "the camera settles from 103 % to 100 % over 2.5 s (emphasized)".
const INTRO_ZOOM := 1.03
const INTRO_SETTLE_S := 2.5
const ARG_DEBUG_HUD := "--debug-hud"
const ARG_LOG_EVENTS := "--log-events"

var _frame_size := Vector2(1080, 1920)
var _drift_amp_px: float = 0.0
var _drift_period_s: float = 45.0
var _drift_t: float = 0.0
var _log_events: bool = false

@onready var camera: Camera2D = $Camera2D
@onready var world: Node2D = $World
@onready var hud_root: Control = $HUD/HudRoot
@onready var boot_cover: ColorRect = $HUD/HudRoot/BootCover
@onready var debug_readout: Label = $HUD/HudRoot/DebugReadout


func _ready() -> void:
	var frame: Dictionary = ContentRegistry.content.spots_doc["frame"]
	_frame_size = Vector2(float(frame["width_px"]), float(frame["height_px"]))
	_setup_drift(float(frame["px_per_dp"]))
	var args := OS.get_cmdline_user_args()
	_log_events = args.has(ARG_LOG_EVENTS)
	debug_readout.visible = args.has(ARG_DEBUG_HUD)
	boot_cover.color = Color.html(String(ContentRegistry.palettes()["ui"]["surface"]))
	UiTheme.attach(hud_root)
	get_viewport().size_changed.connect(_layout)
	Game.sim_event.connect(_on_sim_event)
	Game.world_ready.connect(_on_world_ready)
	_layout()
	_intro()


func _process(delta: float) -> void:
	if _drift_amp_px > 0.0 and not Motion.reduce_motion:
		_drift_t = fposmod(_drift_t + delta, _drift_period_s)
		camera.offset.x = _drift_amp_px * sin(TAU * _drift_t / _drift_period_s)
	elif camera.offset.x != 0.0:
		camera.offset.x = 0.0
	if debug_readout.visible and Game.sim != null:
		debug_readout.text = _readout()


## Bottom-anchored frame: extra height on tall phones is sky above y = 0; wide screens centre
## the 1080 column (Art Bible §2.1).
func _layout() -> void:
	var vis := get_viewport().get_visible_rect().size
	var offset := Vector2(roundf((vis.x - _frame_size.x) * 0.5), vis.y - _frame_size.y)
	world.position = offset
	TimeOfDay.set_world_offset(offset)
	camera.position = vis * 0.5


func _intro() -> void:
	boot_cover.visible = true
	boot_cover.modulate.a = 1.0
	if not Motion.reduce_motion:
		camera.zoom = Vector2.ONE * INTRO_ZOOM
		var t := camera.create_tween()
		Motion.apply_curve(t.tween_property(camera, "zoom", Vector2.ONE, INTRO_SETTLE_S), Motion.curve_of(&"emphasized"))
	var fade := Motion.fade_out(boot_cover, &"emphasized")
	fade.finished.connect(func() -> void:
		boot_cover.visible = false
		Game.notify_world_visible())
	AudioDirector.start_world_audio()


## Art Bible §2.3: camera drift <= motion_tokens world.camera_drift_max_dp_s on a slow sine.
func _setup_drift(px_per_dp: float) -> void:
	var w: Dictionary = ContentRegistry.motion_tokens()["world"]
	var periods: Array = w.get("camera_drift_period_s", [45, 45])
	_drift_period_s = (float(periods[0]) + float(periods[1])) * 0.5
	var max_speed_px := float(w.get("camera_drift_max_dp_s", 0.0)) * px_per_dp
	# Peak speed of A*sin(2*pi*t/P) is A*2*pi/P.
	_drift_amp_px = max_speed_px * _drift_period_s / TAU


func _on_world_ready(recap: Array) -> void:
	if _log_events and not recap.is_empty():
		print("[main] recap: ", recap)


func _on_sim_event(ev: Dictionary) -> void:
	if _log_events:
		print("[sim %.1f] %s %s" % [float(ev["t"]), ev["type"], _brief(ev)])


func _readout() -> String:
	var s := Game.sim
	var present := PackedStringArray()
	for p: Dictionary in s.state.present:
		present.append(String(p["species"]) + ("*" if p["greeter"] else ""))
	return "t %.0f  %s/%s  g_day %.2f\ndew %d  basket %d (%d)  cup %.1f\nhere: %s\nmet %d  fps %d tier %d" % [
		s.state.t, TimeOfDay.phase, TimeOfDay.weather, TimeOfDay.g_day, s.state.dew, s.state.basket.size(),
		s.basket_dew(), s.cup_value(), ", ".join(present), s.met_count(), Engine.get_frames_per_second(),
		FrameGovernor.tier]


static func _brief(ev: Dictionary) -> String:
	var parts := PackedStringArray()
	for k: Variant in ev:
		if k != "type" and k != "t":
			parts.append("%s=%s" % [k, ev[k]])
	return " ".join(parts)
