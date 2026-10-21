extends Node
## Haptics (autoload #7): AUDIO_BIBLE §7, synthesis C3/D11, 06 §0.6 and §5.
##
##  * Kinds TICK / DOUBLE / MEDIUM (StringName). Modes off / subtle (default) / full; Subtle never
##    plays TICK; Full plays everything. [member mode] is persisted through Settings.
##  * At least min_gap_ms (60) between events; a DOUBLE's second pulse is android_gap_ms later.
##  * Android: View.performHapticFeedback on the decor view, posted with
##    AndroidRuntime.getActivity().runOnUiThread(...). The feedback constants are read from
##    android.view.HapticFeedbackConstants through JavaClassWrapper by the names the manifest
##    gives (never hard-coded), and CONFIRM falls back to CLOCK_TICK below API 30
##    (Build$VERSION.SDK_INT). It needs no VIBRATE permission and honours the system
##    touch-feedback setting. Input.vibrate_handheld is never used on Android (it maps to the
##    "buzzy" createOneShot): on any failure we play nothing. "No haptics over buzzy haptics."
##  * iOS: Input.vibrate_handheld(ms, amplitude) per pulse, amplitude x0.7 in Subtle.
##  * Web / desktop: none (diagnostics still count, so tests run everywhere).
## Fire in the same frame as the visual change (I1). AudioDirector.play_cue does this for cues.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const TICK := &"TICK"
const DOUBLE := &"DOUBLE"
const MEDIUM := &"MEDIUM"
const OFF := &"off"
const SUBTLE := &"subtle"
const FULL := &"full"
const ANDROID_FEEDBACK_CLASS := "android.view.HapticFeedbackConstants"
const ANDROID_FALLBACK_KEY := "android_fallback_below_api30"
const ANDROID_CONFIRM_MIN_API := 30
const MS_PER_S := 1000.0
## 06 §5.3; used only when audio/manifest.json has no "haptics" table.
const DEFAULT_TABLE := {
	"min_gap_ms": 60,
	"subtle_amplitude_mult": 0.7,
	"kinds": {
		"TICK": {"android": ["CLOCK_TICK"], "android_gap_ms": 0, "ios": [[12, 0.30]]},
		"DOUBLE": {"android": ["CLOCK_TICK", "CLOCK_TICK"], "android_gap_ms": 70,
			"ios": [[12, 0.42], [12, 0.294]]},
		"MEDIUM": {"android": ["CONFIRM"], ANDROID_FALLBACK_KEY: "CLOCK_TICK", "ios": [[24, 0.60]]},
	},
}

## off / subtle / full. Assigning validates and persists through Settings.
var mode: StringName:
	get:
		return _mode
	set(value):
		_mode = StringName(String(Settings.set_value(Settings.HAPTICS, String(value))))

## Diagnostics for tests and QA (what would have played, on every platform).
var played_count: int = 0
var last_kind: StringName = &""

var _mode: StringName = SUBTLE
var _last_ms: int = -1000000
var _min_gap_ms: int = 60
var _subtle_mult: float = 0.7
var _kinds: Dictionary = {}
## kind -> Array[int] of Android feedback constants (resolved once; empty = play nothing).
var _android_pulses: Dictionary = {}
var _android_gap_s: Dictionary = {}
var _runtime: Object = null
var _activity: Object = null
var _repeat: Timer
var _repeat_kind: StringName = &""
var _once_played: Dictionary = {}


func _ready() -> void:
	_load_table()
	_mode = StringName(Settings.get_string(Settings.HAPTICS))
	Settings.changed.connect(_on_setting_changed)
	_repeat = Timer.new()
	_repeat.one_shot = false
	_repeat.timeout.connect(_on_repeat)
	add_child(_repeat)
	if Platform.is_android():
		_resolve_android()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		_once_played.clear()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		stop_repeat()


## Plays one haptic of [param kind] (TICK, DOUBLE or MEDIUM) if the mode allows it.
func play(kind: StringName) -> void:
	if not _allowed(kind):
		return
	var now := Time.get_ticks_msec()
	if now - _last_ms < _min_gap_ms:
		return
	_last_ms = now
	played_count += 1
	last_kind = kind
	if Platform.is_android():
		_play_android(kind)
	elif Platform.is_ios():
		_play_ios(kind)


## Plays [param kind] now and then every [param interval_ms] until [method stop_repeat]
## (S03 purr: TICK every 120 ms while held, Full only).
func start_repeat(kind: StringName, interval_ms: int) -> void:
	stop_repeat()
	if interval_ms <= 0 or not _allowed(kind):
		return
	_repeat_kind = kind
	play(kind)
	_repeat.start(float(interval_ms) / MS_PER_S)


func stop_repeat() -> void:
	_repeat_kind = &""
	if _repeat != null:
		_repeat.stop()


func is_repeating() -> bool:
	return _repeat_kind != &""


## Plays the haptic of a manifest cue: {"subtle": kind | null, "full": kind | null} with the
## optional extras "<mode>_delay_ms" (S04: TICK 600 ms later) and "once" (S10: at most once
## per foreground session). [param cue_id] keys the "once" bookkeeping.
func play_for_cue(haptic: Variant, cue_id: StringName = &"") -> void:
	if _mode == OFF or not haptic is Dictionary:
		return
	var h: Dictionary = haptic
	var name: Variant = h.get(String(_mode))
	if name == null:
		return
	var kind := StringName(String(name))
	if not _kinds.has(String(kind)):
		return
	if bool(h.get("once", false)):
		if _once_played.has(cue_id):
			return
		_once_played[cue_id] = true
	var delay: Variant = h.get("%s_delay_ms" % String(_mode))
	if delay != null and int(delay) > 0:
		get_tree().create_timer(float(int(delay)) / MS_PER_S).timeout.connect(play.bind(kind))
	else:
		play(kind)


func _allowed(kind: StringName) -> bool:
	if _mode == OFF or not _kinds.has(String(kind)):
		return false
	return not (_mode == SUBTLE and kind == TICK)


func _on_repeat() -> void:
	if _repeat_kind == &"" or not _allowed(_repeat_kind):
		stop_repeat()
		return
	play(_repeat_kind)


# --- Android ---------------------------------------------------------------------------------

func _resolve_android() -> void:
	_runtime = Platform.android_runtime()
	_activity = Platform.android_activity()
	if _runtime == null or _activity == null:
		return  # no bridge: no haptic, never a buzz (R7)
	var constants: Object = JavaClassWrapper.wrap(ANDROID_FEEDBACK_CLASS)
	if constants == null:
		return
	var sdk := Platform.android_sdk_int()
	for k: String in _kinds:
		var spec: Dictionary = _kinds[k]
		var fallback: Variant = spec.get(ANDROID_FALLBACK_KEY)
		var pulses: Array[int] = []
		for n: Variant in spec.get("android", []):
			var field := String(n)
			if fallback != null and sdk < ANDROID_CONFIRM_MIN_API:
				field = String(fallback)
			var v: Variant = constants.get(field)
			if v == null and fallback != null:
				v = constants.get(String(fallback))
			if v == null:
				pulses.clear()
				break
			pulses.append(int(v))
		_android_pulses[k] = pulses
		_android_gap_s[k] = float(spec.get("android_gap_ms", 0)) / MS_PER_S


func _play_android(kind: StringName) -> void:
	var pulses: Array[int] = _android_pulses.get(String(kind), [] as Array[int])
	var gap: float = _android_gap_s.get(String(kind), 0.0)
	for i in pulses.size():
		if i == 0:
			_android_feedback(pulses[i])
		else:
			get_tree().create_timer(gap * i).timeout.connect(_android_feedback.bind(pulses[i]))


func _android_feedback(constant: int) -> void:
	if _activity == null or _runtime == null:
		return
	var act := _activity
	var cb := func() -> void:
		var window: Object = act.call("getWindow")
		if window == null:
			return
		var decor: Object = window.call("getDecorView")
		if decor != null:
			decor.call("performHapticFeedback", constant)
	_activity.call("runOnUiThread", _runtime.call("createRunnableFromGodotCallable", cb))


# --- iOS -------------------------------------------------------------------------------------

func _play_ios(kind: StringName) -> void:
	var spec: Dictionary = _kinds.get(String(kind), {})
	var pulses: Array = spec.get("ios", [])
	var gap := float(spec.get("android_gap_ms", 0)) / MS_PER_S
	var mult := _subtle_mult if _mode == SUBTLE else 1.0
	for i in pulses.size():
		var p: Array = pulses[i]
		var ms := int(p[0])
		var amp := clampf(float(p[1]) * mult, 0.0, 1.0)
		if i == 0:
			Input.vibrate_handheld(ms, amp)
		else:
			get_tree().create_timer(gap * i).timeout.connect(Input.vibrate_handheld.bind(ms, amp))


func _load_table() -> void:
	var table: Dictionary = ContentRegistry.audio_manifest().get("haptics", {})
	if table.is_empty() or not table.has("kinds"):
		table = DEFAULT_TABLE
	_min_gap_ms = int(table.get("min_gap_ms", DEFAULT_TABLE["min_gap_ms"]))
	_subtle_mult = float(table.get("subtle_amplitude_mult", DEFAULT_TABLE["subtle_amplitude_mult"]))
	_kinds = (table["kinds"] as Dictionary).duplicate(true)


func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key == Settings.HAPTICS:
		_mode = StringName(String(value))
		if not _allowed(_repeat_kind):
			stop_repeat()
