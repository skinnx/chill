class_name SettingsSheet
extends UiSheet
## Settings (X1, GDD §7.6; Art Bible §9.5 wireframe): one scrolling sheet, grouped Comfort /
## Sound / Touch / Language / About. Each group is a surface_hi card (iOS inset-grouped; never glass
## on glass) of rows >= 156 px with ink @ 0.10 separators; the whole row is the hit. Toggles,
## segmented choices (Music, Haptics, Language), the text-size stepper and the volume sliders
## write through Settings, whose consumers apply them (UiTheme, Motion, AudioDirector, Haptics,
## I18n). Long Vietnamese labels wrap and rows grow. No destructive action anywhere.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const ROW_H := 156.0
const ROW_PAD := 30
const ICON_PX := 60.0
## Stepper plates 36 dp in a 50 dp hit (the row itself is not the hit here).
const STEP_PLATE := 108.0
const STEP_HIT := 150.0
const GROUP_GAP := 12
## A tapped row ripples inside the row (corner radius) and the switch dips half a press.
const ROW_RIPPLE_RADIUS := 36.0
const ICONLESS_AT_TEXT := 150
const TOGGLE_PRESS_DEPTH := 0.5
const VERSION_SETTING := "application/config/version"

var _list: VBoxContainer
var _scroll: ScrollContainer


func _init() -> void:
	super._init()
	title_key = "SETTINGS_TITLE"


func build_body() -> void:
	_list = make_scroll(0.0, 18)
	_scroll = _list.get_parent().get_parent() as ScrollContainer
	_fill()
	Settings.changed.connect(_on_text_scale_changed)


func refresh_texts() -> void:
	super.refresh_texts()
	if _list != null:
		var keep := _scroll.scroll_vertical
		_fill()
		_scroll.set_deferred(&"scroll_vertical", keep)


func _on_text_scale_changed(key: StringName, _value: Variant) -> void:
	if key == Settings.TEXT_SCALE:
		refresh_texts.call_deferred()


func _fill() -> void:
	for c: Node in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_group(tr("SET_GROUP_COMFORT"), [
		_toggle_row(&"motion", "SET_REDUCE_MOTION", "SET_REDUCE_MOTION_DESC", Settings.REDUCE_MOTION),
		_toggle_row(&"transparency", "SET_REDUCE_TRANSPARENCY", "SET_REDUCE_TRANSPARENCY_DESC",
				Settings.REDUCE_TRANSPARENCY),
		_text_size_row(),
		_toggle_row(&"watch_closed", "SET_AUTO_HIDE", "", Settings.AUTO_HIDE_UI),
		_toggle_row(&"watch", "SET_KEEP_AWAKE", "", Settings.KEEP_AWAKE),
	])
	_group(tr("SET_GROUP_SOUND"), [
		_choice_row(&"music", "SET_MUSIC", ["SET_MUSIC_ON", "SET_MUSIC_AMBIENCE", "SET_MUSIC_OFF"],
				Settings.MUSIC_MODES, Settings.MUSIC),
		_slider_row("SET_VOLUME_MUSIC", Settings.VOLUME_MUSIC),
		_slider_row("SET_VOLUME_AMBIENCE", Settings.VOLUME_AMBIENCE),
		_slider_row("SET_VOLUME_EFFECTS", Settings.VOLUME_EFFECTS),
		_toggle_row(&"mono", "SET_MONO", "", Settings.MONO),
		_toggle_row(&"music", "SET_CAPTIONS", "", Settings.CAPTIONS),
	])
	_group(tr("SET_GROUP_TOUCH"), [
		_choice_row(&"haptics", "SET_HAPTICS", ["SET_HAPTICS_OFF", "SET_HAPTICS_SUBTLE", "SET_HAPTICS_FULL"],
				Settings.HAPTIC_MODES, Settings.HAPTICS),
		_toggle_row(&"hand", "SET_LEFT_HANDED", "SET_LEFT_HANDED_DESC", Settings.LEFT_HANDED),
	])
	_group(tr("SET_LANGUAGE"), [
		_choice_row(&"language", "SET_LANGUAGE", ["SET_LANGUAGE_DEVICE", "LANG_EN", "LANG_VI"], Settings.LANGUAGES,
				Settings.LANGUAGE),
	])
	var version := String(ProjectSettings.get_setting(VERSION_SETTING, ""))
	_group(tr("SET_GROUP_ABOUT"), [
		_text_row(tr("SET_PRIVACY")),
		_text_row(tr("SET_CREDITS_BODY")),
		_text_row(I18n.fmt(&"SET_VERSION", {"version": version})),
	])


func _group(caption: String, rows: Array) -> void:
	var cap := label(caption, &"CaptionLabel")
	cap.add_theme_constant_override(&"margin_left", 24)
	var m := MarginContainer.new()
	m.add_theme_constant_override(&"margin_left", 24)
	m.add_theme_constant_override(&"margin_top", GROUP_GAP)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(cap)
	_list.add_child(m)
	var c := card(0, ThemeBuilder.R_L, UiTokens.E1)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	c.add_child(v)
	for i in rows.size():
		if i > 0:
			var d := MarginContainer.new()
			d.add_theme_constant_override(&"margin_left", ROW_PAD)
			d.add_theme_constant_override(&"margin_right", ROW_PAD)
			d.mouse_filter = Control.MOUSE_FILTER_IGNORE
			d.add_child(divider())
			v.add_child(d)
		v.add_child(rows[i] as Control)
	_list.add_child(c)


## A row: [icon] [label (+ description)] [control]; returns [row, text VBox, right slot, hit].
## The row is a PanelContainer, so it grows with its content (wrapped Vietnamese labels, large
## text) and never below 156 px; [param hit] adds a flat full-row button underneath the content.
func _row(icon: StringName, key: String, desc_key: String, hit: bool) -> Array:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.custom_minimum_size = Vector2(0.0, ROW_H)
	var b: Button = null
	if hit:
		b = Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(b)
	var m := MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right"]:
		m.add_theme_constant_override(side, ROW_PAD)
	for side: StringName in [&"margin_top", &"margin_bottom"]:
		m.add_theme_constant_override(side, 18)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE if hit else Control.MOUSE_FILTER_PASS
	row.add_child(m)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 24)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE if hit else Control.MOUSE_FILTER_PASS
	m.add_child(h)
	# At large text the row icons step aside so the label keeps the width (the icons only echo
	# the label; Art Bible §9.1 "rows grow and reflow").
	if icon != &"" and Settings.get_int(Settings.TEXT_SCALE) < ICONLESS_AT_TEXT:
		var ic := Icons.rect(icon, ICON_PX)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override(&"separation", 0)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE if hit else Control.MOUSE_FILTER_PASS
	h.add_child(tv)
	if key != "":
		tv.add_child(label(tr(key), &"BodyLabel", true))
	if desc_key != "":
		tv.add_child(label(tr(desc_key), &"SecondaryLabel", true))
	var slot := HBoxContainer.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE if hit else Control.MOUSE_FILTER_PASS
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(slot)
	return [row, tv, slot, b]


func _toggle_row(icon: StringName, key: String, desc_key: String, setting: StringName) -> Control:
	var parts := _row(icon, key, desc_key, true)
	var t := UiToggle.new()
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.set_silent(Settings.get_bool(setting))
	(parts[2] as HBoxContainer).add_child(t)
	var hit := parts[3] as Button
	hit.pressed.connect(func() -> void:
		t.button_pressed = not t.button_pressed
		Settings.set_value(setting, t.button_pressed))
	hit.set_meta(PressFeedback.META_RIPPLE_RADIUS, ROW_RIPPLE_RADIUS)
	hit.set_meta(PressFeedback.META_DEPTH, 0.0)
	hit.button_down.connect(func() -> void:
		t.force_pressed = true
		PressFeedback.down(hit)
		PressFeedback.down(t, TOGGLE_PRESS_DEPTH))
	hit.button_up.connect(func() -> void:
		t.force_pressed = false
		PressFeedback.up(hit)
		PressFeedback.up(t))
	return parts[0]


func _choice_row(icon: StringName, key: String, option_keys: Array, values: Array, setting: StringName) -> Control:
	var parts := _row(icon, key, "", false)
	var tv := parts[1] as VBoxContainer
	var seg := Segmented.new()
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var texts := PackedStringArray()
	for k: Variant in option_keys:
		texts.append(tr(String(k)))
	var current := String(Settings.get_value(setting))
	var idx := maxi(0, values.find(current))
	tv.add_theme_constant_override(&"separation", 18)
	tv.add_child(seg)
	seg.setup(texts, idx)
	seg.selected.connect(func(i: int) -> void: Settings.set_value(setting, values[i]))
	return parts[0]


func _slider_row(key: String, setting: StringName) -> Control:
	var parts := _row(&"", key, "", false)
	var tv := parts[1] as VBoxContainer
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 18)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := UiSlider.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.set_value_silent(Settings.get_int(setting))
	line.add_child(s)
	var v := label(str(Settings.get_int(setting)), &"StrongLabel")
	v.custom_minimum_size = Vector2(84.0, 0.0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(v)
	tv.add_child(line)
	s.value_changed.connect(func(n: int) -> void:
		v.text = str(n)
		Settings.set_value(setting, n))
	return parts[0]


func _text_size_row() -> Control:
	var parts := _row(&"text_size", "SET_TEXT_SIZE", "", false)
	var slot := parts[2] as HBoxContainer
	slot.add_theme_constant_override(&"separation", 0)
	var scales := Settings.TEXT_SCALES
	var cur := Settings.get_int(Settings.TEXT_SCALE)
	var minus := _step_button(&"minus")
	var plus := _step_button(&"plus")
	var value := label(I18n.fmt(&"SET_TEXT_SIZE_VALUE", {"percent": cur}), &"StrongLabel")
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.custom_minimum_size = Vector2(132.0, 0.0)
	slot.add_child(minus)
	slot.add_child(value)
	slot.add_child(plus)
	var step := func(d: int) -> void:
		var i := clampi(scales.find(Settings.get_int(Settings.TEXT_SCALE)) + d, 0, scales.size() - 1)
		AudioDirector.play_cue(&"S15", {"on": d > 0})
		Settings.set_value(Settings.TEXT_SCALE, scales[i])
	minus.pressed.connect(step.bind(-1))
	plus.pressed.connect(step.bind(1))
	minus.disabled = cur <= scales[0]
	plus.disabled = cur >= scales[scales.size() - 1]
	minus.asleep = minus.disabled
	plus.asleep = plus.disabled
	return parts[0]


func _step_button(icon: StringName) -> RoundButton:
	var b := RoundButton.new()
	b.plate_px = STEP_PLATE
	b.icon_px = 42.0
	b.icon_name = icon
	b.fill_token = &"primary_tint"
	b.elevation = UiTokens.E0
	b.custom_minimum_size = Vector2(STEP_HIT, STEP_HIT)
	PressFeedback.attach(b, &"")
	return b


func _text_row(text: String) -> Control:
	var parts := _row(&"", "", "", false)
	var tv := parts[1] as VBoxContainer
	tv.add_child(label(text, &"SecondaryLabel", true))
	return parts[0]
