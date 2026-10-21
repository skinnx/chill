extends Node
## Clock (autoload #3) = the Art Bible's TimeDriver: the one place that reads wall time.
##
##  * now_unix() / tz_offset_s() / now_local(): device wall clock (UTC + local offset). Everything
##    else (sim, TimeOfDay, save) receives time from here, so QA can pin or shift it.
##  * ticks_s(): monotonic seconds for in-session timing (live world clock, rate limits).
##  * g_time: the shader clock, wrapped at motion_tokens time.g_time_wrap_s (600 s, synthesis C4);
##    every loop is k/600 Hz, so the wrap is seamless. g_motion: 1.0, or the Reduce Motion scale.
##
## QA / debug user args (after `--`): --now=<unix seconds>  --clock=HH:MM (local, today)
##   --tz=<minutes east of UTC>  --freeze-time (g_time stops; deterministic captures)
##   --g-time=<seconds> (start value of g_time)
##   --frame-clock: wall time and ticks advance by the frame delta instead of the system clock, so
##   a run under --fixed-fps replays identically (tools/qa/capture.gd, docs/QA.md). Always on in
##   Movie Maker mode, where frames are rendered slower or faster than real time and the recorded
##   audio advances exactly one frame per frame: the world and the music must follow the frames.

signal time_overridden

const G_TIME := &"g_time"
const G_MOTION := &"g_motion"
const TZ_REFRESH_S := 60.0
const ARG_FRAME_CLOCK := "--frame-clock"

var g_time: float = 0.0
## Multiplies the advance of g_time (0 freezes the world's shader motion; QA only).
var time_scale: float = 1.0
var g_time_wrap_s: float = 600.0
var g_motion: float = 1.0
## True when wall time and ticks are driven by frame deltas (see --frame-clock above). May be set
## before _ready (tools/qa/capture.gd does so in its _initialize); it cannot be turned off later.
var frame_clock: bool = false

var _offset_s: float = 0.0
## Frame clock: seconds of frame time since start, the system wall time at start, and the wall
## time at frame time 0 (the epoch, or what --now / override_now() asked for). now = anchor + frame,
## so a pinned --now replays bit-identically whatever the system clock reads.
var _frame_s: float = 0.0
var _frame_epoch_unix: float = 0.0
var _frame_anchor_unix: float = 0.0
var _tz_override_s: float = NAN
var _tz_cache_s: float = 0.0
var _tz_age_s: float = INF


func _ready() -> void:
	process_priority = -100  # before anything that reads g_time this frame
	var t: Dictionary = ContentRegistry.motion_tokens().get("time", {})
	g_time_wrap_s = t.get("g_time_wrap_s", g_time_wrap_s)
	var args := OS.get_cmdline_user_args()
	if frame_clock or args.has(ARG_FRAME_CLOCK) or OS.has_feature("movie"):
		_start_frame_clock()
	_parse_args(args)
	Settings.changed.connect(_on_setting_changed)
	_apply_motion()
	RenderingServer.global_shader_parameter_set(G_TIME, g_time)


func _process(delta: float) -> void:
	_frame_s += delta
	g_time = fposmod(g_time + delta * time_scale, g_time_wrap_s)
	RenderingServer.global_shader_parameter_set(G_TIME, g_time)
	_tz_age_s += delta


func now_unix() -> float:
	if frame_clock:
		return _frame_anchor_unix + _frame_s
	return Time.get_unix_time_from_system() + _offset_s


## Local offset from UTC in seconds (DST-aware; refreshed every minute).
func tz_offset_s() -> float:
	if not is_nan(_tz_override_s):
		return _tz_override_s
	if _tz_age_s >= TZ_REFRESH_S:
		var tz: Dictionary = Time.get_time_zone_from_system()
		var bias_min: int = tz.get("bias", 0)
		_tz_cache_s = bias_min * 60.0
		_tz_age_s = 0.0
	return _tz_cache_s


func now_local() -> float:
	return now_unix() + tz_offset_s()


func ticks_s() -> float:
	if frame_clock:
		return _frame_s
	return Time.get_ticks_usec() / 1000000.0


## Shifts the wall clock so that "now" reads [param unix] (time keeps flowing).
func override_now(unix: float) -> void:
	if frame_clock:
		_frame_anchor_unix = unix - _frame_s
	else:
		_offset_s = unix - Time.get_unix_time_from_system()
	time_overridden.emit()


func override_timezone(offset_s: float) -> void:
	_tz_override_s = offset_s
	time_overridden.emit()


func clear_overrides() -> void:
	_offset_s = 0.0
	_frame_anchor_unix = _frame_epoch_unix
	_tz_override_s = NAN
	_tz_age_s = INF
	time_overridden.emit()


func _start_frame_clock() -> void:
	frame_clock = true
	_frame_s = 0.0
	_frame_epoch_unix = Time.get_unix_time_from_system()
	_frame_anchor_unix = _frame_epoch_unix


func _parse_args(args: PackedStringArray) -> void:
	for a: String in args:
		if a.begins_with("--now="):
			override_now(a.get_slice("=", 1).to_float())
		elif a.begins_with("--tz="):
			override_timezone(a.get_slice("=", 1).to_float() * 60.0)
		elif a.begins_with("--g-time="):
			g_time = fposmod(a.get_slice("=", 1).to_float(), g_time_wrap_s)
		elif a == "--freeze-time":
			time_scale = 0.0
	for a: String in args:
		if a.begins_with("--clock="):
			var hm := a.get_slice("=", 1).split(":")
			var sod := hm[0].to_float() * 3600.0 + (hm[1].to_float() * 60.0 if hm.size() > 1 else 0.0)
			var local := now_local()
			var today := floorf(local / TodMath.SECONDS_PER_DAY) * TodMath.SECONDS_PER_DAY
			override_now(today + sod - tz_offset_s())


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key == Settings.REDUCE_MOTION:
		_apply_motion()


func _apply_motion() -> void:
	var rm: Dictionary = ContentRegistry.motion_tokens().get("reduce_motion", {})
	var reduced: float = rm.get("g_motion", 1.0)
	g_motion = reduced if Settings.get_bool(Settings.REDUCE_MOTION) else 1.0
	RenderingServer.global_shader_parameter_set(G_MOTION, g_motion)
