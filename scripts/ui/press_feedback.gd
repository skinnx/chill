class_name PressFeedback
extends RefCounted
## Touch feedback for every UI control (Art Bible §10.3, GDD §8.2-8.3, I1). On touch-down, in the
## same frame:
##  * the control lightens (+6 L*, `instant`) and starts scaling to ui.press_scale (0.96) over
##    ui.press_ms (80 ms, ease-out); [param depth] deepens it (the dock uses 2 = 0.92) and
##    [param squash] makes it M3-Expressive squashy (wider than tall at the bottom of the press);
##  * a ripple (shaders/ui/ripple) grows from the touch point over ui.ring.ms, clipped to the
##    control's own shape (pill, card, round plate), white on dark fills and primary on light ones;
##  * S01 plays (+ TICK haptic in Full).
## On release it springs back on `pop` (interruptible: the spring keeps its velocity). The action
## fires on release inside the target (BaseButton action mode), so sliding off cancels.
##
## QA stills (--qa-press, --qa-press-t): [method pose] freezes a control at a given time after
## touch-down (deterministic, no tweens), so the touch strip can show the peak of every press.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const META_TWEEN := &"_press_tween"
const META_RIPPLE := &"_press_ripple"
const META_NUDGE_BASE := &"_nudge_base"
const META_DEPTH := &"_press_depth"
const META_SQUASH := &"_press_squash"
## Optional per-control overrides: a Rect2 clip shape (local px), its corner radius, and
## whether the fill under the ripple is dark (white ripple).
const META_RIPPLE_RECT := &"ripple_rect"
const META_RIPPLE_RADIUS := &"ripple_radius"
const META_RIPPLE_ON_DARK := &"ripple_on_dark"
## Optional light-fill ripple colour (round 6: each dock tab splashes in its own warm accent, a
## primary ripple over a gold bubble read grey).
const META_RIPPLE_COLOR := &"ripple_color"
const CUE_TOUCH := &"S01"
const RIPPLE_SHADER := "res://shaders/ui/ripple.gdshader"
## Light-fill ripple: primary at this share of ui.ring.alpha[0] (a white ripple on cream is
## invisible; a full-strength primary one is loud).
const LIGHT_RIPPLE_SHARE := 0.8
## Light ripple on dark glass (night dock): white capped at this alpha so the light labels keep
## >= 4.5:1 under it (QA r3: a 0.35 white ripple took a label to 2.8:1).
const ON_DARK_RIPPLE_MAX := 0.12
## Primary pills (pressed fill primary_deep) splash in the lighter primary at this share of
## ui.ring.alpha[0]: the fill under the white label stays darker than primary_pressed even at the
## ripple's crest (>= 5.2:1; QA r3: a white ripple took the label to 2.8:1).
const PILL_RIPPLE_SHARE := 1.5
## Squash: the width gives back this share of the height's press (1.0 + k x (1 - scale_y)).
const SQUASH_WIDTH_K := 0.5

## A Button's text colours (hidden while a ripple carries the label, see _label_over).
const FONT_COLOR_KEYS: Array[StringName] = [&"font_color", &"font_hover_color", &"font_pressed_color",
	&"font_hover_pressed_color", &"font_focus_color"]

static var _ripple_shader: Shader


## Wires [param button]. [param cue] plays on touch-down (&"" = none, e.g. toggles play S15 on
## change instead). [param depth] scales the press: 1.0 = ui.press_scale.
static func attach(button: BaseButton, cue: StringName = CUE_TOUCH, depth: float = 1.0, squash: bool = false) -> void:
	button.set_meta(META_DEPTH, depth)
	button.set_meta(META_SQUASH, squash)
	button.button_down.connect(_down.bind(button, cue))
	button.button_up.connect(_up.bind(button))
	button.resized.connect(func() -> void: button.pivot_offset = _pivot(button))


## The visual half of a press for controls that handle input themselves. [param at] is the touch
## point in local px (default: the current pointer).
static func down(c: Control, depth: float = -1.0, at: Vector2 = Vector2(-1, -1)) -> void:
	if depth < 0.0:
		depth = float(c.get_meta(META_DEPTH, 1.0))
	c.pivot_offset = _pivot(c)
	Motion.stop_springs(c)
	_kill(c)
	var u := UiTokens.ui()
	var lift := 1.0 + float(u.get("press_tint_dL", 0.06))
	c.modulate = Color(lift, lift, lift, c.modulate.a)
	var t := c.create_tween()
	t.tween_property(c, "scale", _press_scale(c, depth, 1.0), float(u.get("press_ms", 80.0)) * UiTokens.MS) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	c.set_meta(META_TWEEN, t)
	var p := at if at.x >= 0.0 else c.get_local_mouse_position()
	var rip := _ripple(c, p)
	if rip != null:
		var rt := rip.create_tween()
		rt.tween_method(func(v: float) -> void:
			(rip.material as ShaderMaterial).set_shader_parameter(&"u_progress", v), 0.0, 1.0, _ring_s())
		rt.tween_callback(rip.queue_free)
	FrameGovernor.hold_for(maxf(Motion.duration(&"release_settle"), _ring_s()))


static func up(c: Control) -> void:
	_kill(c)
	Motion.spring_to(c, "scale", Vector2.ONE, StringName(String(UiTokens.ui().get("release", "pop"))))
	var t := c.create_tween()
	t.tween_property(c, "modulate", Color(1, 1, 1, c.modulate.a), Motion.duration(&"short"))
	FrameGovernor.hold_for(Motion.duration(&"release_settle"))


## QA: the control exactly [param t_s] seconds after a touch-down at [param at] (local px; default
## the centre), held there (no tweens): press scale on its ease-out, the tint lift and the ripple.
static func pose(c: Control, t_s: float, at: Vector2 = Vector2(-1, -1)) -> void:
	_kill(c)
	Motion.stop_springs(c)
	c.pivot_offset = _pivot(c)
	var u := UiTokens.ui()
	var press_s := float(u.get("press_ms", 80.0)) * UiTokens.MS
	var k := clampf(t_s / maxf(press_s, 1e-3), 0.0, 1.0)
	k = 1.0 - (1.0 - k) * (1.0 - k)
	c.scale = _press_scale(c, float(c.get_meta(META_DEPTH, 1.0)), k)
	var lift := 1.0 + float(u.get("press_tint_dL", 0.06))
	c.modulate = Color(lift, lift, lift, c.modulate.a)
	var p := at if at.x >= 0.0 else _shape(c).get_center()
	var rip := _ripple(c, p)
	if rip != null:
		(rip.material as ShaderMaterial).set_shader_parameter(&"u_progress", clampf(t_s / _ring_s(), 0.0, 1.0))


## A soft lateral nudge (not affordable: ±2 dp on `follow`, GDD §8.1; never a shake of the screen).
static func nudge(c: Control) -> void:
	var dx := UiTokens.ui_float("not_affordable_wiggle_dp", 2.0) * UiTokens.PX_PER_DP
	var spring := StringName(String(UiTokens.ui().get("not_affordable_spring", "follow")))
	if not c.has_meta(META_NUDGE_BASE):
		c.set_meta(META_NUDGE_BASE, c.position)
	var base: Vector2 = c.get_meta(META_NUDGE_BASE)
	c.position = base + Vector2(dx, 0.0)
	Motion.spring_to(c, "position", base, spring)


static func _down(button: BaseButton, cue: StringName) -> void:
	down(button)
	if cue != &"":
		AudioDirector.play_cue(cue)


static func _up(button: BaseButton) -> void:
	up(button)


static func _press_scale(c: Control, depth: float, k: float) -> Vector2:
	var sy := 1.0 - (1.0 - float(UiTokens.ui().get("press_scale", 0.96))) * depth * k
	var sx := sy
	if bool(c.get_meta(META_SQUASH, false)):
		sx = 1.0 - (1.0 - sy) * SQUASH_WIDTH_K
	return Vector2(sx, sy)


## Presses scale about the shape's centre, squashing toward its bottom edge when squashy.
static func _pivot(c: Control) -> Vector2:
	var r := _shape(c)
	if bool(c.get_meta(META_SQUASH, false)):
		return Vector2(r.get_center().x, r.end.y)
	return r.get_center()


static func _shape(c: Control) -> Rect2:
	if c.has_meta(META_RIPPLE_RECT):
		var v: Variant = c.get_meta(META_RIPPLE_RECT)
		if v is Rect2:
			return v as Rect2
	return Rect2(Vector2.ZERO, c.size)


static func _ring_s() -> float:
	return float(UiTokens.ui_block("ring").get("ms", 380.0)) * UiTokens.MS


## The ripple node for a press at [param p] (local px), clipped to the control's shape.
static func _ripple(c: Control, p: Vector2) -> ColorRect:
	if Motion.reduce_motion or c.size.x <= 1.0:
		return null
	if _ripple_shader == null:
		_ripple_shader = load(RIPPLE_SHADER) as Shader
	var shape := _shape(c)
	var radius := float(c.get_meta(META_RIPPLE_RADIUS, minf(shape.size.x, shape.size.y) * 0.5))
	var pill := _is_dark_button(c)
	var dark := bool(c.get_meta(META_RIPPLE_ON_DARK, false))
	var alphas: Array = UiTokens.ui_block("ring").get("alpha", [0.35, 0.0])
	var a0 := float(alphas[0]) if alphas.size() > 0 else 0.35
	var rip := ColorRect.new()
	rip.name = "Ripple"
	rip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rip.color = Color.WHITE
	rip.position = shape.position
	rip.size = shape.size
	var mat := ShaderMaterial.new()
	mat.shader = _ripple_shader
	mat.set_shader_parameter(&"u_size", shape.size)
	mat.set_shader_parameter(&"u_radius", radius)
	mat.set_shader_parameter(&"u_center", p - shape.position)
	var corners := [Vector2.ZERO, Vector2(shape.size.x, 0.0), Vector2(0.0, shape.size.y), shape.size]
	var reach := 0.0
	for k: Vector2 in corners:
		reach = maxf(reach, (p - shape.position).distance_to(k))
	mat.set_shader_parameter(&"u_reach", reach)
	var col := UiTokens.color(&"primary")
	var alpha := a0 * LIGHT_RIPPLE_SHARE
	if c.has_meta(META_RIPPLE_COLOR):
		col = c.get_meta(META_RIPPLE_COLOR) as Color
	if pill:
		col = UiTokens.color(&"primary")
		alpha = a0 * PILL_RIPPLE_SHARE
	elif dark:
		col = UiTokens.color(&"surface_hi")
		alpha = minf(a0, ON_DARK_RIPPLE_MAX)
	mat.set_shader_parameter(&"u_color", col)
	mat.set_shader_parameter(&"u_alpha", alpha)
	mat.set_shader_parameter(&"u_progress", 0.0)
	rip.material = mat
	if c.has_meta(META_RIPPLE):
		var old: Variant = c.get_meta(META_RIPPLE)
		if is_instance_valid(old) and old is Node:
			(old as Node).queue_free()
	c.add_child(rip, false, Node.INTERNAL_MODE_FRONT)
	c.set_meta(META_RIPPLE, rip)
	if c is Button and (c as Button).text != "" and not (c as Button).flat:
		_label_over(c as Button, rip)
	return rip


## A Button draws its text in its own draw, under every child, so a ripple would wash over the
## label (QA r3: 2.8:1 mid-press). While the ripple lives, the button's text is hidden and the
## same text is drawn by a Label riding above the ripple: the splash always sits UNDER the label.
static func _label_over(b: Button, rip: Control) -> void:
	var l := Label.new()
	l.name = "RippleLabel"
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = b.text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override(&"font", b.get_theme_font(&"font"))
	l.add_theme_font_size_override(&"font_size", b.get_theme_font_size(&"font_size"))
	var col := b.get_theme_color(&"font_pressed_color")
	l.add_theme_color_override(&"font_color", col)
	l.position = -rip.position
	l.size = b.size
	rip.add_child(l)
	for key: StringName in FONT_COLOR_KEYS:
		b.add_theme_color_override(key, Color(col, 0.0))
	rip.tree_exiting.connect(func() -> void:
		if is_instance_valid(b):
			for key: StringName in FONT_COLOR_KEYS:
				b.remove_theme_color_override(key))


## A default-variation, non-flat Button is a primary (dark) pill.
static func _is_dark_button(c: Control) -> bool:
	if c is Button:
		var b := c as Button
		return not b.flat and b.theme_type_variation == &"" and not b.disabled
	return false


static func _kill(c: Control) -> void:
	if c.has_meta(META_TWEEN):
		var t: Variant = c.get_meta(META_TWEEN)
		if t is Tween and (t as Tween).is_valid():
			(t as Tween).kill()
		c.remove_meta(META_TWEEN)
