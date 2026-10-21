class_name Platform
extends RefCounted
## Platform queries that need native bridges (02 §2.3, §5). Every call degrades gracefully: on
## desktop, in headless runs and when a bridge is missing it returns "unknown" instead of failing.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const ANDROID_RUNTIME := "AndroidRuntime"
const UNKNOWN := -1


static func is_android() -> bool:
	return OS.get_name() == "Android"


static func is_ios() -> bool:
	return OS.get_name() == "iOS"


static func is_web() -> bool:
	return OS.has_feature("web")


static func is_mobile() -> bool:
	return is_android() or is_ios()


## The Android Activity through the AndroidRuntime plugin, or null.
static func android_activity() -> Object:
	if not is_android() or not Engine.has_singleton(ANDROID_RUNTIME):
		return null
	var rt: Object = Engine.get_singleton(ANDROID_RUNTIME)
	if rt == null:
		return null
	return rt.call("getActivity")


static func android_runtime() -> Object:
	if not is_android() or not Engine.has_singleton(ANDROID_RUNTIME):
		return null
	return Engine.get_singleton(ANDROID_RUNTIME)


## android.os.Build.VERSION.SDK_INT, or UNKNOWN.
static func android_sdk_int() -> int:
	if not is_android():
		return UNKNOWN
	var version: Object = JavaClassWrapper.wrap("android.os.Build$VERSION")
	if version == null:
		return UNKNOWN
	var v: Variant = version.get("SDK_INT")
	return int(v) if v != null else UNKNOWN


## OS "reduce motion" preference: 1 on, 0 off, UNKNOWN when unreadable (GDD §7.6, 02 §5).
## Android: ValueAnimator.areAnimatorsEnabled() (API 26) is false under "Remove animations".
## Web: prefers-reduced-motion. iOS and desktop: unknown (in-game toggle only).
static func os_reduce_motion() -> int:
	if is_android():
		var va: Object = JavaClassWrapper.wrap("android.animation.ValueAnimator")
		if va != null and va.call("has_java_method", "areAnimatorsEnabled"):
			return 0 if bool(va.call("areAnimatorsEnabled")) else 1
		return UNKNOWN
	if is_web():
		var r: Variant = JavaScriptBridge.eval("window.matchMedia('(prefers-reduced-motion: reduce)').matches", true)
		return UNKNOWN if r == null else (1 if bool(r) else 0)
	if DisplayServer.get_name() != "headless" and DisplayServer.has_method("accessibility_should_reduce_animation"):
		return 1 if bool(DisplayServer.call("accessibility_should_reduce_animation")) else 0
	return UNKNOWN


## Android system font scale (Settings.System "font_scale"), or -1.0 when unknown.
static func os_font_scale() -> float:
	var act := android_activity()
	if act == null:
		return -1.0
	var sys: Object = JavaClassWrapper.wrap("android.provider.Settings$System")
	if sys == null:
		return -1.0
	var v: Variant = sys.call("getFloat", act.call("getContentResolver"), "font_scale", 1.0)
	return float(v) if v != null else -1.0


## "Leave for now" on Android: send the task to the back (keeps the process, no restart cost).
## Returns false where unsupported; the caller then quits normally.
static func move_task_to_back() -> bool:
	var act := android_activity()
	if act == null:
		return false
	act.call("moveTaskToBack", true)
	return true


## Safe area in canvas units (02 §1.3): the OS rect scaled by visible-rect / window size.
static func safe_area_canvas(viewport: Viewport) -> Rect2:
	var visible := viewport.get_visible_rect()
	if DisplayServer.get_name() == "headless":
		return visible
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return visible
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var screen := Vector2(win)
	if safe.size.x <= 0.0 or safe.size.y <= 0.0 or not is_mobile():
		return visible
	var k := visible.size / screen
	return Rect2(safe.position * k, safe.size * k)
