extends Node
## FrameGovernor (autoload): synthesis C21 frame-rate policy + 02 §4.4 quality governor.
##
##  * 60 fps while the player interacts or a UI tween/spring runs; 30 fps after
##    motion_tokens world.idle_fps_after_s (8 s) with no input and no UI motion; always 30 fps in
##    Ambient mode. Rates are refresh divisors (active/idle: 60 Hz 60/30, 90 Hz 45/30, 120 Hz 60/30;
##    02 §4.4.1).
##  * If the idle 30 fps cadence itself is unstable (p95 frame delta > 40 ms), idle-30 is turned
##    off for the session and the content tier drops instead (C21 fallback, R2).
##  * Quality tier 0 (full) / 1 / 2: step down when > 5 % of frames in a 3 s window exceed 1.5x
##    the target interval; step back up after 30 s clean. Views read [member tier] and listen to
##    [signal tier_changed] (Art Bible §4.19 tier 1: no shafts, no L5, fewer clouds and grass).
##    A tier change takes art off the screen, so it is held back while a finger is down or the map
##    is still moving (round 8): panning is the heaviest render path in the game and so the most
##    likely thing to trip the slow-frame test, which made the pop land exactly when the player was
##    touching the glass and looking hardest. The frames are already slow; a few hundred ms of
##    delay costs nothing and the startle is what breaks the calm.
##  * A pointer resting on the glass counts as activity: a thumb that is down but still generates
##    no events (accumulation merges nothing when nothing moves), so without this the session drops
##    to 30 fps mid-gesture and the next drag frame applies two frames of travel at once.
##  * Counts hitches (> 2x target interval after warm-up) for QA (02 §4.3).

signal tier_changed(tier: int)
signal idle_changed(idle: bool)

const ACTIVE_FPS := 60
const IDLE_FPS := 30
const MAX_TIER := 2
const WINDOW_S := 3.0
const SLOW_FRAME_FACTOR := 1.5
const SLOW_FRAME_SHARE := 0.05
const RECOVER_AFTER_S := 30.0
const IDLE_P95_LIMIT_S := 0.040
const HITCH_FACTOR := 2.0
## Ignore the first seconds after boot/resume (loading, catch-up, first-use compiles).
const GRACE_S := 3.0
## A pointer that has produced no event at all for this long is treated as gone. A resting thumb
## really does generate nothing (accumulation merges nothing when nothing moves), so this is also
## the guard against a release that never arrives - an OS gesture stealing the touch, a dropped
## event - pinning the session at 60 fps for ever.
const POINTER_STALE_S := 16.0

var tier: int = 0
var idle: bool = false
## Set by the UI when the player enters "just watch" mode (GDD §1.5). Also applies the
## "Keep the screen on while I watch" setting: the screen stays on only in ambient mode (02 R12).
var ambient_mode: bool = false:
	set(v):
		ambient_mode = v
		_update_rate()
		_apply_keep_on()
var idle_30_allowed: bool = true
var hitch_count: int = 0
## Disable all governing (QA captures with --fixed-fps).
var enabled: bool = true

var _idle_after_s: float = 8.0
var _last_activity_s: float = 0.0
var _busy_until_s: float = 0.0
var _deltas := PackedFloat32Array()
var _window_t: float = 0.0
var _clean_s: float = 0.0
var _grace_left: float = GRACE_S
var _refresh_hz: float = 60.0
## A pointer is on the glass (set from the press, cleared on release / focus loss).
var _pointer_down: bool = false
## A tier step decided while the player was busy, applied once they are not. MAX_TIER + 1 = none.
var _pending_tier: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var w: Dictionary = ContentRegistry.motion_tokens().get("world", {})
	_idle_after_s = w.get("idle_fps_after_s", _idle_after_s)
	var hz := DisplayServer.screen_get_refresh_rate()
	_refresh_hz = hz if hz > 0.0 else float(ACTIVE_FPS)
	for a: String in OS.get_cmdline_user_args():
		if a == "--no-governor":
			enabled = false
	if Engine.get_write_movie_path() != "" or DisplayServer.get_name() == "headless":
		enabled = false
	poke()
	_update_rate()
	Settings.changed.connect(func(key: StringName, _v: Variant) -> void:
		if key == Settings.KEEP_AWAKE:
			_apply_keep_on())


func _input(event: InputEvent) -> void:
	var st := event as InputEventScreenTouch
	if st != null and st.index == 0:
		_pointer_down = st.pressed
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.device != InputEvent.DEVICE_ID_EMULATION:
		_pointer_down = mb.pressed
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton \
			or event is InputEventKey or (event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask != 0):
		poke()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_grace_left = GRACE_S
		_deltas.clear()
		poke()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_pointer_down = false  # no release arrives when the app goes away under a finger


func _process(delta: float) -> void:
	if not enabled:
		return
	var now := Clock.ticks_s()
	if _pointer_down and now - _last_activity_s > POINTER_STALE_S:
		_pointer_down = false
	var was_idle := idle
	idle = ambient_mode or (idle_30_allowed and not _pointer_down and now - _last_activity_s >= _idle_after_s \
			and now >= _busy_until_s)
	if idle != was_idle:
		_update_rate()
		idle_changed.emit(idle)
		_deltas.clear()
		_window_t = 0.0
	if _pending_tier >= 0 and not is_busy_with_the_world():
		_set_tier(_pending_tier)
	if _grace_left > 0.0:
		_grace_left -= delta
		return
	_track(delta)


## Marks player activity (input handlers call this implicitly via _input).
func poke() -> void:
	_last_activity_s = Clock.ticks_s()
	if idle and not ambient_mode:
		idle = false
		_update_rate()
		idle_changed.emit(false)


## Keeps 60 fps for at least [param seconds] (UI tweens, springs, sheet drags).
func hold_for(seconds: float) -> void:
	_busy_until_s = maxf(_busy_until_s, Clock.ticks_s() + seconds)
	if idle and not ambient_mode:
		poke()


func _apply_keep_on() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.screen_set_keep_on(ambient_mode and Settings.get_bool(Settings.KEEP_AWAKE))


func target_fps() -> int:
	return _divisor_rate(IDLE_FPS if idle else ACTIVE_FPS)


func _update_rate() -> void:
	if not enabled:
		return
	Engine.max_fps = target_fps()


## The refresh divisor closest to [param desired] (02 §4.4.1).
func _divisor_rate(desired: int) -> int:
	var div := maxi(1, roundi(_refresh_hz / float(desired)))
	return roundi(_refresh_hz / float(div))


func _track(delta: float) -> void:
	var interval := 1.0 / float(target_fps())
	if delta > HITCH_FACTOR * interval:
		hitch_count += 1
	_deltas.append(delta)
	_window_t += delta
	if _window_t < WINDOW_S:
		return
	var slow := 0
	for d: float in _deltas:
		if d > SLOW_FRAME_FACTOR * interval:
			slow += 1
	var share := float(slow) / float(maxi(1, _deltas.size()))
	if idle and idle_30_allowed and not ambient_mode and _p95(_deltas) > IDLE_P95_LIMIT_S:
		idle_30_allowed = false  # 30 fps jitters on this device: stay at 60 with lighter content
		_set_tier(tier + 1)
	elif share > SLOW_FRAME_SHARE:
		_set_tier(tier + 1)
		_clean_s = 0.0
	else:
		_clean_s += _window_t
		if _clean_s >= RECOVER_AFTER_S and tier > 0:
			_set_tier(tier - 1)
			_clean_s = 0.0
	_deltas.clear()
	_window_t = 0.0


## True while the player would see a tier pop land on top of their own gesture: a finger on the
## glass, or the map still gliding or springing back from one.
func is_busy_with_the_world() -> bool:
	if _pointer_down:
		return true
	var pan := WorldPan.current
	return pan != null and (pan.is_dragging() or pan.body.is_active())


func _set_tier(t: int) -> void:
	var clamped := clampi(t, 0, MAX_TIER)
	if clamped == tier:
		_pending_tier = -1
		return
	if is_busy_with_the_world():
		_pending_tier = clamped  # hold it: see the note in the header
		return
	_pending_tier = -1
	tier = clamped
	tier_changed.emit(tier)


static func _p95(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size() - 1, floori(0.95 * sorted.size()))]
