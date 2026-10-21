class_name PressFeedback
extends RefCounted
## Touch feedback for every UI control (Art Bible §10.3, GDD §8.2-8.3, I1): on touch-down, in the
## same frame, the control lightens (+6 L*, `instant`) and starts scaling to ui.press_scale (0.96)
## over ui.press_ms (80 ms, `micro` ease-out) with the S01 touch cue (+ TICK haptic in Full); on
## release it springs back on `pop` (interruptible: the spring keeps its velocity). The action
## itself fires on release inside the target (BaseButton action mode), so sliding off cancels.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const META_TWEEN := &"_press_tween"
const META_NUDGE_BASE := &"_nudge_base"
const CUE_TOUCH := &"S01"


## Wires [param button]. [param cue] plays on touch-down (&"" = none, e.g. toggles play S15 on
## change instead). [param depth] scales the press: 1.0 = ui.press_scale.
static func attach(button: BaseButton, cue: StringName = CUE_TOUCH, depth: float = 1.0) -> void:
	button.button_down.connect(_down.bind(button, cue, depth))
	button.button_up.connect(_up.bind(button))
	button.resized.connect(func() -> void: button.pivot_offset = button.size * 0.5)


## The visual half of a press for controls that handle input themselves.
static func down(c: Control, depth: float = 1.0) -> void:
	c.pivot_offset = c.size * 0.5
	Motion.stop_springs(c)
	_kill(c)
	var u := UiTokens.ui()
	var lift := 1.0 + float(u.get("press_tint_dL", 0.06))
	c.modulate = Color(lift, lift, lift, c.modulate.a)
	var target := 1.0 - (1.0 - float(u.get("press_scale", 0.96))) * depth
	var t := c.create_tween()
	t.tween_property(c, "scale", Vector2(target, target), float(u.get("press_ms", 80.0)) * UiTokens.MS) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	c.set_meta(META_TWEEN, t)
	FrameGovernor.hold_for(Motion.duration(&"release_settle"))


static func up(c: Control) -> void:
	_kill(c)
	Motion.spring_to(c, "scale", Vector2.ONE, StringName(String(UiTokens.ui().get("release", "pop"))))
	var t := c.create_tween()
	t.tween_property(c, "modulate", Color(1, 1, 1, c.modulate.a), Motion.duration(&"short"))
	FrameGovernor.hold_for(Motion.duration(&"release_settle"))


## A soft lateral nudge (not affordable: ±2 dp on `follow`, GDD §8.1; never a shake of the screen).
static func nudge(c: Control) -> void:
	var dx := UiTokens.ui_float("not_affordable_wiggle_dp", 2.0) * UiTokens.PX_PER_DP
	var spring := StringName(String(UiTokens.ui().get("not_affordable_spring", "follow")))
	if not c.has_meta(META_NUDGE_BASE):
		c.set_meta(META_NUDGE_BASE, c.position)
	var base: Vector2 = c.get_meta(META_NUDGE_BASE)
	c.position = base + Vector2(dx, 0.0)
	Motion.spring_to(c, "position", base, spring)


static func _down(button: BaseButton, cue: StringName, depth: float) -> void:
	down(button, depth)
	if cue != &"":
		AudioDirector.play_cue(cue)


static func _up(button: BaseButton) -> void:
	up(button)


static func _kill(c: Control) -> void:
	if c.has_meta(META_TWEEN):
		var t: Variant = c.get_meta(META_TWEEN)
		if t is Tween and (t as Tween).is_valid():
			(t as Tween).kill()
		c.remove_meta(META_TWEEN)
