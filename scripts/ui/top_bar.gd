class_name TopBarView
extends Control
## The passive HUD row (Art Bible §9.4-9.5, GDD §8.1, I2): the dew chip (top-left, appears after
## the first collect), the time/weather chip and the "just watch" eye (top-right; mirrored when
## left-handed). Chips are faux glass (C7); only the eye is a target (hit 216 x 216 = 72 dp).
## Positions are px in screen space: chips at y = max(safe top, T 120) + 24, 48 px side margin.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

signal watch_pressed

## Art Bible §2.6: chips are 120 tall at T + 24 (T = 120 px at H 1920), 48 px side margin.
const CHIP_H := 120.0
const T_MIN := 120.0
const TOP_GAP := 24.0
const SIDE := 48.0
const GAP := 24.0
## The eye's hit grows 48 px sideways and 96 px down from its 120 px circle (216 x 216).
const EYE_HIT := Vector2(216, 216)
const EYE_HIT_PAD_X := 48.0
const ICON_PX := 72.0
## Dew chip: icon at x + 30, numerals at x + 120, width 264-420 (§9.4).
const DEW_ICON_X := 30.0
const DEW_TEXT_X := 120.0
const DEW_PAD_R := 42.0
const DEW_W_MIN := 264.0
const DEW_W_MAX := 420.0
## Time chip label peek: widens leftward to 408 px (x 480 at the 1080 frame).
const PEEK_W := 408.0
const PEEK_LABEL_PAD := 36.0
const BADGE_PX := 48.0
const BADGE_ICON_PX := 36.0
const PHASE_ICONS := {&"dawn": &"dawn", &"day": &"sun", &"golden": &"golden", &"dusk": &"dusk", &"night": &"moon"}
const WEATHER_ICONS := {&"breeze": &"breeze", &"rain": &"rain"}
const PHASE_KEYS := {&"dawn": "TIME_DAWN", &"day": "TIME_DAY", &"golden": "TIME_GOLDEN", &"dusk": "TIME_DUSK",
	&"night": "TIME_NIGHT"}
const WEATHER_KEYS := {&"clear": "WEATHER_CLEAR", &"breeze": "WEATHER_BREEZE", &"rain": "WEATHER_RAIN"}

var left_handed: bool = false
var dew_chip: GlassPanel
var time_chip: GlassPanel
var eye: BaseButton

var _dew_icon: TextureRect
var _dew_label: Label
var _dew_shown: int = -1
var _dew_target: int = 0
var _dew_step_t: float = 0.0
var _dew_step: int = 1
var _dew_visible: bool = false
var _time_icon: TextureRect
var _badge: Control
var _badge_icon: TextureRect
var _time_label: Label
var _peek_w: float = 0.0
var _peek_tween: Tween
var _eye_glass: GlassPanel
var _eye_icon: TextureRect
var _phase: StringName = &""
var _weather: StringName = &""
var _ambient_icon: bool = false
var _screen: Vector2 = Vector2(1080, 1920)
var _safe_top: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_build_dew()
	_build_time()
	_build_eye()
	TimeOfDay.phase_changed.connect(func(p: StringName) -> void: _set_time(p, _weather, true))
	TimeOfDay.weather_changed.connect(func(w: StringName) -> void: _set_time(_phase, w, true))
	Game.wallet_changed.connect(_on_wallet)
	_set_time(TimeOfDay.phase, TimeOfDay.weather, false)
	if Game.sim != null:
		_dew_target = Game.sim.state.dew
		_dew_shown = _dew_target
		_dew_visible = _dew_target > 0 or Game.sim.state.last_collect_t > 0.0
		_dew_label.text = format_dew(_dew_shown)
	dew_chip.visible = _dew_visible
	set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _time_label != null:
		_time_label.text = _peek_text()
		if _dew_label != null and _dew_shown >= 0:
			_dew_label.text = format_dew(_dew_shown)
		relayout()


## Places the chips for a screen of [param screen] px with an OS top inset of [param safe_top].
func layout(screen: Vector2, safe_top: float) -> void:
	_screen = screen
	_safe_top = safe_top
	var y := maxf(safe_top, T_MIN) + TOP_GAP
	var w := screen.x
	var dew_w := _dew_width()
	var eye_x := SIDE if left_handed else w - SIDE - CHIP_H
	var time_x := SIDE + CHIP_H + GAP if left_handed else eye_x - GAP - CHIP_H
	var time_w := CHIP_H + _peek_w
	dew_chip.position = Vector2(w - SIDE - dew_w if left_handed else SIDE, y)
	dew_chip.size = Vector2(dew_w, CHIP_H)
	time_chip.position = Vector2(time_x if left_handed else time_x - _peek_w, y)
	time_chip.size = Vector2(time_w, CHIP_H)
	var icon_x := 0.0 if left_handed else _peek_w
	_time_icon.position = Vector2(icon_x + (CHIP_H - ICON_PX) * 0.5, (CHIP_H - ICON_PX) * 0.5)
	_badge.position = Vector2(icon_x + CHIP_H - BADGE_PX * 0.8, CHIP_H - BADGE_PX * 0.8)
	var lx := CHIP_H - PEEK_LABEL_PAD * 0.25 if left_handed else PEEK_LABEL_PAD
	_time_label.position = Vector2(lx, 0.0)
	_time_label.size = Vector2(maxf(_peek_w - PEEK_LABEL_PAD, 0.0), CHIP_H)
	_time_label.visible = _peek_w > PEEK_LABEL_PAD
	_time_label.modulate.a = clampf((_peek_w - PEEK_LABEL_PAD) / (PEEK_W - CHIP_H - PEEK_LABEL_PAD), 0.0, 1.0)
	var pad := EYE_HIT_PAD_X
	eye.position = Vector2(eye_x - pad, y)
	eye.size = EYE_HIT
	_eye_glass.position = Vector2(pad, 0.0)
	_eye_glass.size = Vector2(CHIP_H, CHIP_H)
	eye.pivot_offset = Vector2(pad + CHIP_H * 0.5, CHIP_H * 0.5)


## Ambient watch: the eye shows its closed-lid variant (Art Bible §9.3).
func set_ambient_icon(on: bool) -> void:
	_ambient_icon = on
	_eye_icon.texture = Icons.texture(&"watch_closed" if on else &"watch", ICON_PX)


## Expands the time chip with the phase or weather label for ui label_peek_hold (QA: forever).
func peek(hold: bool = false) -> void:
	_time_label.text = _peek_text()
	if _peek_tween != null and _peek_tween.is_valid():
		_peek_tween.kill()
	var target := PEEK_W - CHIP_H
	var font_w := _time_label.get_theme_font(&"font").get_string_size(_time_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			_time_label.get_theme_font_size(&"font_size")).x
	target = maxf(target, font_w + PEEK_LABEL_PAD * 2.0)
	_peek_tween = create_tween()
	if Motion.reduce_motion:
		_peek_tween.tween_method(_set_peek, _peek_w, target, Motion.duration(&"reduce_motion_crossfade"))
	else:
		var from := _peek_w
		_peek_tween.tween_method(func(u: float) -> void:
			_set_peek(lerpf(from, target, UiTokens.ease(&"standard", u))), 0.0, 1.0, Motion.duration(&"standard"))
	if hold:
		return
	_peek_tween.tween_interval(UiTokens.seconds("label_peek_hold"))
	_peek_tween.tween_method(func(u: float) -> void:
		_set_peek(lerpf(target, 0.0, UiTokens.ease(&"exit", u))), 0.0, 1.0, Motion.duration(&"exit"))
	FrameGovernor.hold_for(Motion.duration(&"standard"))


func _set_peek(v: float) -> void:
	_peek_w = v
	relayout()


func relayout() -> void:
	layout(_screen, _safe_top)


func _peek_text() -> String:
	var t := tr(String(PHASE_KEYS.get(_phase, "TIME_DAY")))
	if _weather != &"clear" and _weather != &"":
		t = "%s · %s" % [t, tr(String(WEATHER_KEYS.get(_weather, "WEATHER_CLEAR")))]
	return t


func _set_time(phase: StringName, weather: StringName, announce: bool) -> void:
	var changed := phase != _phase or weather != _weather
	_phase = phase
	_weather = weather
	var icon: StringName = PHASE_ICONS.get(phase, &"sun")
	_time_icon.texture = Icons.texture(icon, ICON_PX)
	var wx: StringName = WEATHER_ICONS.get(weather, &"")
	_badge.visible = wx != &""
	if wx != &"":
		_badge_icon.texture = Icons.texture(wx, BADGE_ICON_PX)
	if announce and changed and is_inside_tree():
		peek()


# ------------------------------------------------------------------ dew counter

static func format_dew(n: int) -> String:
	var s := str(absi(n))
	var sep := "." if I18n.is_vietnamese() else ","
	var out := ""
	while s.length() > 3:
		out = sep + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


func _dew_width() -> float:
	if _dew_label == null:
		return DEW_W_MIN
	var tw := _dew_label.get_combined_minimum_size().x
	return clampf(DEW_TEXT_X + tw + DEW_PAD_R, DEW_W_MIN, DEW_W_MAX)


func _on_wallet(dew: int) -> void:
	_dew_target = dew
	if not _dew_visible and dew > 0:
		_dew_visible = true
		dew_chip.visible = true
		Motion.fade_in(dew_chip, &"short")
		dew_chip.pivot_offset = dew_chip.size * 0.5
		dew_chip.scale = Vector2.ONE * float(UiTokens.ui_block("counter_tick").get("scale", 1.08))
		Motion.spring_to(dew_chip, "scale", Vector2.ONE, &"pop")
	if _dew_shown < 0:
		_dew_shown = dew
	var tick := UiTokens.ui_block("counter_tick")
	var per := float(tick.get("per_step_ms", 40.0))
	var steps := maxf(1.0, floorf(float(tick.get("max_ms", 600.0)) / per))
	_dew_step = maxi(1, ceili(absf(float(dew - _dew_shown)) / steps))
	if Motion.reduce_motion:
		_dew_shown = dew
		_dew_label.text = format_dew(dew)
		Motion.fade_in(_dew_label, &"short")
		_relayout_dew()
		return
	set_process(true)


func _process(delta: float) -> void:
	if _dew_shown == _dew_target:
		set_process(false)
		return
	_dew_step_t -= delta
	if _dew_step_t > 0.0:
		return
	var tick := UiTokens.ui_block("counter_tick")
	_dew_step_t = float(tick.get("per_step_ms", 40.0)) * UiTokens.MS
	var d := _dew_target - _dew_shown
	_dew_shown += signi(d) * mini(absi(d), _dew_step)
	_dew_label.text = format_dew(_dew_shown)
	_dew_label.pivot_offset = _dew_label.size * 0.5
	_dew_label.scale = Vector2.ONE * float(tick.get("scale", 1.08))
	Motion.spring_to(_dew_label, "scale", Vector2.ONE, StringName(String(tick.get("pop", "pop"))))
	_relayout_dew()


func _relayout_dew() -> void:
	var w := _dew_width()
	if not is_equal_approx(w, dew_chip.size.x):
		relayout()


## Screen-space centre of the dew icon (collect-all flights land here).
func dew_target_point() -> Vector2:
	return dew_chip.global_position + Vector2(DEW_ICON_X + ICON_PX * 0.5, CHIP_H * 0.5)


# ------------------------------------------------------------------ build

func _build_dew() -> void:
	dew_chip = GlassPanel.new()
	dew_chip.name = "DewChip"
	add_child(dew_chip)
	_dew_icon = Icons.rect(&"dew", ICON_PX)
	_dew_icon.position = Vector2(DEW_ICON_X, (CHIP_H - ICON_PX) * 0.5)
	dew_chip.add_child(_dew_icon)
	_dew_label = Label.new()
	_dew_label.theme_type_variation = &"HudNumeral"
	_dew_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dew_label.position = Vector2(DEW_TEXT_X, 0.0)
	_dew_label.size = Vector2(DEW_W_MAX - DEW_TEXT_X, CHIP_H)
	_dew_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dew_label.text = "0"
	dew_chip.add_child(_dew_label)


func _build_time() -> void:
	time_chip = GlassPanel.new()
	time_chip.name = "TimeChip"
	time_chip.clip_contents = false
	add_child(time_chip)
	_time_label = Label.new()
	_time_label.theme_type_variation = &"StrongLabel"
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_time_label.clip_text = true
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_time_label.visible = false
	time_chip.add_child(_time_label)
	_time_icon = Icons.rect(&"sun", ICON_PX)
	time_chip.add_child(_time_icon)
	_badge = Control.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.size = Vector2(BADGE_PX, BADGE_PX)
	_badge.draw.connect(func() -> void:
		_badge.draw_style_box(UiTokens.fill_box(UiTokens.color(&"surface_hi"), BADGE_PX * 0.5, UiTokens.E1),
				Rect2(Vector2.ZERO, Vector2(BADGE_PX, BADGE_PX))))
	time_chip.add_child(_badge)
	_badge_icon = Icons.rect(&"breeze", BADGE_ICON_PX)
	_badge_icon.position = Vector2((BADGE_PX - BADGE_ICON_PX) * 0.5, (BADGE_PX - BADGE_ICON_PX) * 0.5)
	_badge.add_child(_badge_icon)


func _build_eye() -> void:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.name = "Eye"
	eye = b
	add_child(eye)
	_eye_glass = GlassPanel.new()
	eye.add_child(_eye_glass)
	_eye_icon = Icons.rect(&"watch", ICON_PX)
	_eye_icon.position = Vector2((CHIP_H - ICON_PX) * 0.5, (CHIP_H - ICON_PX) * 0.5)
	_eye_glass.add_child(_eye_icon)
	PressFeedback.attach(eye)
	eye.pressed.connect(func() -> void: watch_pressed.emit())
