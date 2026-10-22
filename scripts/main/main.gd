extends Node2D
## Main scene: the hollow and its HUD (docs/ARCHITECTURE.md §3, Art Bible §2).
##
## Owns layout only: the bottom-anchored 1080x1920 design frame (Art Bible A1: World.position =
## (centring x, H - 1920), mirrored into g_world_offset), the camera (home view, the one-finger map
## pan stepped through WorldPan, the slow idle drift), and the intro (cover fade from the splash
## colour + camera settle, GDD §3.4). Layer content is built by the art/gameplay/UI owners inside
## the named nodes; this script only forwards lifecycle hooks to them.
##
## Map pan (docs/ARCHITECTURE.md §3.4): pan bounds come from the layer geometry and the viewport
## size; every frame the camera sits at home + pan + drift, TimeOfDay gets the pan (g_cam_pan) and
## nodes in GROUP_VIEW get on_world_pan(pan, cam, reveal_px) when the view moves.
##
## Debug user args: --debug-layout (gameplay layout overlay), --debug-hits (every world and UI hit
## area, HitDebug), --debug-hud (live sim readout),
## --log-events (print every sim event), --qa-pan=x,y (start panned by x,y canvas px, clamped to
## the rest bounds: a QA still of a panned view).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## GDD §3.4: "the camera settles from 103 % to 100 % over 2.5 s (emphasized)".
const INTRO_ZOOM := 1.03
const INTRO_SETTLE_S := 2.5
const ARG_DEBUG_HUD := "--debug-hud"
const ARG_LOG_EVENTS := "--log-events"
const ARG_QA_PAN := "--qa-pan="
## Nodes that follow the pan implement on_world_pan(pan: Vector2, cam: Vector2, reveal_px: float).
const GROUP_VIEW := &"world_pan_view"

var _frame_size := Vector2(1080, 1920)
var _drift_amp_px: float = 0.0
var _drift_period_s: float = 45.0
var _drift_t: float = 0.0
var _log_events: bool = false
## Map pan: tokens, bounds, idle-drift resume ramp and the last broadcast view.
var _pan_cfg: Dictionary = {}
var _rest := Rect2()
var _hard := Rect2()
var _home := Vector2(540, 960)
var _drift_x: float = 0.0
var _drift_ramp: float = 1.0
var _drift_cap: float = INF
var _was_active: bool = false
var _view_pan := Vector2(INF, INF)
var _view_cam := Vector2(INF, INF)
var _layer_scales := PackedFloat64Array()
var _listeners: Array[Node] = []

@onready var camera: Camera2D = $Camera2D
@onready var world: Node2D = $World
@onready var hud_root: Control = $HUD/HudRoot
@onready var boot_cover: ColorRect = $HUD/HudRoot/BootCover
@onready var debug_readout: Label = $HUD/HudRoot/DebugReadout
@onready var pan: WorldPan = $WorldPan


func _ready() -> void:
	var frame: Dictionary = ContentRegistry.content.spots_doc["frame"]
	_frame_size = Vector2(float(frame["width_px"]), float(frame["height_px"]))
	_setup_drift(float(frame["px_per_dp"]))
	_setup_pan(frame)
	var args := OS.get_cmdline_user_args()
	_log_events = args.has(ARG_LOG_EVENTS)
	debug_readout.visible = args.has(ARG_DEBUG_HUD)
	boot_cover.color = Color.html(String(ContentRegistry.palettes()["ui"]["surface"]))
	UiTheme.attach(hud_root)
	get_viewport().size_changed.connect(_layout)
	Game.sim_event.connect(_on_sim_event)
	Game.world_ready.connect(_on_world_ready)
	_layout()
	for a: String in args:
		if a.begins_with(ARG_QA_PAN):
			var xy := a.trim_prefix(ARG_QA_PAN).split(",")
			if xy.size() == 2:
				pan.body.snap(Vector2(xy[0].to_float(), xy[1].to_float()))
				_was_active = true  # the drift restarts from zero, capped by the rest bounds
	if HitDebug.wanted():
		var hits := HitDebug.new()
		hits.name = "HitDebug"
		hits.hud = hud_root
		hits.pan = pan
		add_child(hits)
	_apply_camera(0.0)
	_intro()


func _process(delta: float) -> void:
	_apply_camera(delta)
	if debug_readout.visible and Game.sim != null:
		debug_readout.text = _readout()


## Bottom-anchored frame: extra height on tall phones is sky above y = 0; wide screens centre
## the 1080 column (Art Bible §2.1).
func _layout() -> void:
	var vis := get_viewport().get_visible_rect().size
	var offset := Vector2(roundf((vis.x - _frame_size.x) * 0.5), vis.y - _frame_size.y)
	world.position = offset
	TimeOfDay.set_world_offset(offset)
	_home = vis * 0.5
	var cfg := _pan_cfg
	var room := float(cfg.get("rubber_room_dp", 16.0)) * float(ContentRegistry.content.spots_doc["frame"]["px_per_dp"])
	_hard = PanMath.hard_bounds(vis, _frame_size, Vector2(TerrainMath.X_MIN, TerrainMath.X_MAX), _bound_scales(),
			float(cfg.get("sky_up_px", 0.0)), room)
	_rest = PanMath.rest_bounds(_hard, room)
	pan.view_width = vis.x
	pan.body.set_bounds(_rest, _hard)
	_view_pan = Vector2(INF, INF)
	camera.position = _home + pan.offset()


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


func _setup_pan(frame: Dictionary) -> void:
	_pan_cfg = (ContentRegistry.motion_tokens()["world"] as Dictionary).get("pan", {})
	pan.configure(_pan_cfg, frame, ContentRegistry.content.spots_doc.get("safe_x", {}))
	pan.motion_started.connect(_fold_drift)
	var hud := hud_root as HudController
	if hud != null:
		pan.blocked = func() -> bool:
			return (hud.sheets != null and hud.sheets.is_open()) or (hud.overlays != null and hud.overlays.is_modal_open())
	Motion.reduce_motion_changed.connect(func(on: bool) -> void:
		pan.body.reduce_motion = on
		pan.body.set_bounds(_rest, _hard))
	Game.suspended.connect(pan.cancel)
	# full-width layers (non-empty, scroll <= 1) in depth order: bounds and the reveal of hill bottoms
	var scales: Array[float] = []
	for c: Node in world.get_children():
		var p := c as Parallax2D
		if p != null and p.get_child_count() > 0 and p.scroll_scale.y <= 1.0:
			scales.append(p.scroll_scale.y)
	scales.sort()
	_layer_scales = PackedFloat64Array(scales)
	for n: Node in get_tree().get_nodes_in_group(GROUP_VIEW):
		_listeners.append(n)


func _bound_scales() -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for c: Node in world.get_children():
		var p := c as Parallax2D
		if p != null and p.get_child_count() > 0 and p.scroll_scale.x > 0.0 and p.scroll_scale.x <= 1.0:
			out.append(p.scroll_scale.x)
	return out


## Camera = home + pan + drift. The drift pauses (folded into the pan) while the map is dragged or
## gliding, and resumes from zero over drift_resume_s, never carrying the view past the rest bounds.
func _apply_camera(delta: float) -> void:
	pan.zoom = camera.zoom.x
	pan.body.step(delta)
	var active := pan.body.is_active()
	var p := pan.offset()
	if _drift_amp_px > 0.0 and not Motion.reduce_motion and not active:
		if _was_active:
			_drift_t = 0.0
			_drift_ramp = 0.0
			_drift_cap = maxf(0.0, minf(p.x - _rest.position.x, _rest.end.x - p.x))
		_drift_t = fposmod(_drift_t + delta, _drift_period_s)
		_drift_ramp = minf(1.0, _drift_ramp + delta / maxf(float(_pan_cfg.get("drift_resume_s", 4.0)), 0.01))
		var amp := minf(_drift_amp_px, _drift_cap)
		_drift_x = smoothstep(0.0, 1.0, _drift_ramp) * amp * sin(TAU * _drift_t / _drift_period_s)
	elif not active:
		_drift_x = 0.0
	_was_active = active
	camera.position = _home + p
	camera.offset.x = _drift_x
	var cam := p + Vector2(_drift_x, 0.0)
	if p == _view_pan and cam == _view_cam:
		return
	if p != _view_pan:
		TimeOfDay.set_camera_pan(p)
	_view_pan = p
	_view_cam = cam
	for n: Node in _listeners:
		if is_instance_valid(n):
			n.call(&"on_world_pan", p, cam, _reveal_for(n, p.y))


## The drift offset becomes part of the pan when a drag or a home glide starts (no jump).
func _fold_drift() -> void:
	if _drift_x != 0.0:
		pan.body.raw.x += _drift_x
		_drift_x = 0.0
		camera.offset.x = 0.0
	_drift_cap = INF


## How far below its authored bottom the listener's layer is revealed at this rise (PanMath.reveal
## against the next full-width layer in front).
func _reveal_for(n: Node, pan_y: float) -> float:
	var par := n.get_parent()
	while par != null and not par is Parallax2D:
		par = par.get_parent()
	if par == null:
		return 0.0
	var s := (par as Parallax2D).scroll_scale.y
	for f: float in _layer_scales:
		if f > s:
			return PanMath.reveal(pan_y, s, f)
	return 0.0


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
