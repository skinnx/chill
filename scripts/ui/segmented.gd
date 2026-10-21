class_name Segmented
extends Control
## Segmented control (Art Bible §9.5: Garden tabs, Album tabs, Music, Haptics, Language). Round 4
## (QA r3: saturated blue thumbs flooded the sheets, V2): a recessed primary_tint track with a
## raised surface_hi thumb (e1, 1 dp primary hairline, a light top lip) that glides on the `pop`
## spring with a small M3-Expressive overshoot; the selected label is primary_deep (7.0:1 on
## surface_hi), the others ink_soft (8.6:1 on primary_tint). Every segment is a full-height hit;
## touch-down presses that segment (PressFeedback), the change plays S15 + TICK.

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
const THUMB_LINE_ALPHA := 0.18
const SPRING := &"pop"

var index: int = 0
var _labels: Array[Label] = []
var _hits: Array[BaseButton] = []
var _pill_x: float = 0.0
var _spring: Spring
## Round 5: the recessed track and the raised thumb are batched UiSurfaces (Art Bible §4.19).
var _track: UiSurface
var _thumb: UiSurface


func _init() -> void:
	custom_minimum_size = Vector2(0.0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_relayout)
	_track = UiSurface.new()
	_track.name = "Track"
	_track.radius = UiSurface.PILL
	add_child(_track, false, Node.INTERNAL_MODE_FRONT)
	set_meta(UiSurface.META_OWNER, _track)
	# the thumb sits one nesting level above the track (UiBatch orders surfaces by depth)
	var holder := Control.new()
	holder.name = "ThumbLayer"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_meta(UiSurface.META_OWNER, true)
	add_child(holder, false, Node.INTERNAL_MODE_FRONT)
	_thumb = UiSurface.new()
	_thumb.name = "Thumb"
	_thumb.radius = UiSurface.PILL
	_thumb.elevation = UiTokens.E1
	holder.add_child(_thumb)


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
			_spring = Motion.spring(SPRING, _pill_x)
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
		# the ripple stays inside the visible segment (the hit grows past the track)
		var seg := Rect2(Vector2(0.0, HIT_GROW), Vector2(w, size.y)).grow(-INSET)
		_hits[i].set_meta(PressFeedback.META_RIPPLE_RECT, seg)
		_hits[i].set_meta(PressFeedback.META_RIPPLE_RADIUS, seg.size.y * 0.5)
		_labels[i].position = Vector2(0.0, HIT_GROW)
		_labels[i].size = Vector2(w, size.y)
	if _spring == null or _spring.is_at_rest():
		_pill_x = _seg_x(index)
	queue_redraw()


func _recolor() -> void:
	for i in _labels.size():
		_labels[i].add_theme_color_override(&"font_color",
				UiTokens.sc(&"primary_deep") if i == index else UiTokens.sc(&"ink_soft"))


func _draw() -> void:
	_track.color = UiTokens.sc(&"primary_tint")
	_track.border_color = UiTokens.sc_tinted(&"ink", UiTokens.alpha(&"divider"))
	_track.border_px = HAIRLINE_DP * UiTokens.PX_PER_DP
	_track.position = Vector2.ZERO
	_track.size = size
	var ph := size.y - INSET * 2.0
	_thumb.color = UiTokens.sc(&"raised")
	_thumb.border_color = UiTokens.sc_tinted(&"primary", THUMB_LINE_ALPHA)
	_thumb.border_px = HAIRLINE_DP * UiTokens.PX_PER_DP
	_thumb.position = Vector2(_pill_x, INSET)
	_thumb.size = Vector2(_seg_w(), ph)
