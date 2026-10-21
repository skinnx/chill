class_name Segmented
extends Control
## Segmented control (Art Bible §9.5: Garden tabs, Album tabs, Music, Haptics, Language). A
## surface_hi track (never glass on glass) with a primary selection pill that glides on the `move`
## spring; the selected label is surface_hi on primary_pressed (5.86:1), the others ink. Every segment is a
## full-height hit; touch-down presses that segment (PressFeedback), the change plays S15 + TICK.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

signal selected(index: int)

const HEIGHT := 120.0
const INSET := 9.0
const HAIRLINE_DP := 1.0
const CUE_SELECT := &"S15"
## Art Bible §9.5: the 120 px control's hit runs 24 px above and below it (168 = 56 dp).
const HIT_GROW := 24.0

var index: int = 0
var _labels: Array[Label] = []
var _hits: Array[BaseButton] = []
var _pill_x: float = 0.0
var _spring: Spring


func _init() -> void:
	custom_minimum_size = Vector2(0.0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_relayout)


func _process(delta: float) -> void:
	if _spring == null:
		set_process(false)
		return
	_pill_x = _spring.step(delta)
	queue_redraw()
	if _spring.is_at_rest():
		set_process(false)


## [param texts] are already translated.
func setup(texts: PackedStringArray, start: int = 0) -> void:
	for c: Node in get_children():
		c.queue_free()
	_labels.clear()
	_hits.clear()
	index = clampi(start, 0, maxi(texts.size() - 1, 0))
	for i in texts.size():
		var hit := Button.new()
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.pressed.connect(_pick.bind(i))
		PressFeedback.attach(hit, &"", 0.5)
		add_child(hit)
		_hits.append(hit)
		var l := Label.new()
		l.text = texts[i]
		l.theme_type_variation = &"StrongLabel"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hit.add_child(l)
		_labels.append(l)
	_relayout()
	_pill_x = _seg_x(index)
	_recolor()


func set_texts(texts: PackedStringArray) -> void:
	for i in mini(texts.size(), _labels.size()):
		_labels[i].text = texts[i]
	_relayout()


func select(i: int, animate: bool = true) -> void:
	if i == index or i < 0 or i >= _hits.size():
		return
	index = i
	_recolor()
	if animate:
		if _spring == null:
			_spring = Motion.spring(&"move", _pill_x)
		_spring.target = _seg_x(i)
		set_process(true)
		FrameGovernor.hold_for(Motion.duration(&"standard"))
	else:
		_pill_x = _seg_x(i)
		queue_redraw()


func _pick(i: int) -> void:
	if i == index:
		return
	AudioDirector.play_cue(CUE_SELECT, {"on": true})
	select(i)
	selected.emit(i)


func _seg_w() -> float:
	return (size.x - INSET * 2.0) / float(maxi(_hits.size(), 1))


func _seg_x(i: int) -> float:
	return INSET + _seg_w() * float(i)


func _relayout() -> void:
	var w := _seg_w()
	for i in _hits.size():
		_hits[i].position = Vector2(_seg_x(i), -HIT_GROW)
		_hits[i].size = Vector2(w, size.y + HIT_GROW * 2.0)
		_hits[i].pivot_offset = _hits[i].size * 0.5
		_labels[i].position = Vector2(0.0, HIT_GROW)
		_labels[i].size = Vector2(w, size.y)
	if _spring == null or _spring.is_at_rest():
		_pill_x = _seg_x(index)
	queue_redraw()


func _recolor() -> void:
	for i in _labels.size():
		_labels[i].add_theme_color_override(&"font_color",
				UiTokens.color(&"surface_hi") if i == index else UiTokens.color(&"ink"))


func _draw() -> void:
	var track := UiTokens.fill_box(UiTokens.color(&"surface_hi"), size.y * 0.5, UiTokens.E1)
	track.border_color = UiTokens.tinted(&"ink", UiTokens.alpha(&"divider"))
	track.set_border_width_all(roundi(HAIRLINE_DP * UiTokens.PX_PER_DP))
	draw_style_box(track, Rect2(Vector2.ZERO, size))
	var ph := size.y - INSET * 2.0
	var pill := UiTokens.fill_box(UiTokens.color(&"primary_pressed"), ph * 0.5, UiTokens.E1)
	draw_style_box(pill, Rect2(Vector2(_pill_x, INSET), Vector2(_seg_w(), ph)))
