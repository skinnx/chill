class_name Segmented
extends Container
## Segmented control (Art Bible §9.5: Garden tabs, Album tabs, Music, Haptics, Language). Round 4
## (QA r3: saturated blue thumbs flooded the sheets, V2): a recessed primary_tint track with a
## raised surface_hi thumb (e1, 1 dp primary hairline) that glides on the `pop` spring with a small
## M3-Expressive overshoot; the selected label is primary_deep (7.0:1 on surface_hi), the others
## ink_soft (8.6:1 on primary_tint). Every segment is a full-height hit; touch-down presses that
## segment (PressFeedback), the change plays S15 + TICK.
##
## Round 6 (device QA, 720x1600 vi: option labels floated under the track and over the next row):
## the control is a Container. Each option's label is a child of its segment's hit and is laid out
## INSIDE the visible segment on every sort, at the segment's real width; the track grows when a
## long option wraps (Vietnamese "Chỉ tiếng thiên nhiên", large text), so the label always sits
## centred in its segment and the selected one inside the thumb. (Before, the labels were sized
## once while the row was still 0 px wide: autowrap gave them a 200-1000 px minimum height that
## nothing ever shrank back, so the text was centred far below the track.)

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

signal selected(index: int)

## Track height for one line of text; it grows when an option wraps.
const HEIGHT := 120.0
const INSET := 9.0
## Text padding inside a segment (each side), so a label never touches the thumb's rounded ends.
const LABEL_PAD_X := 18.0
const LABEL_PAD_Y := 12.0
## Large text: the options may shrink to this share of their size to stay on one line.
const SHRINK_FLOOR := 0.85
## ... and further, when one word alone is wider than a segment (never break inside a word).
const WORD_FLOOR := 0.6
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


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_SORT_CHILDREN:
			_relayout()
		NOTIFICATION_RESIZED:
			# the wrapped height depends on the segment width
			update_minimum_size()
		NOTIFICATION_THEME_CHANGED:
			update_minimum_size()
			queue_sort()


func _process(delta: float) -> void:
	if _spring == null:
		set_process(false)
		return
	_pill_x = _spring.step(delta)
	_place_thumb()
	if _spring.is_at_rest():
		set_process(false)


## [param texts] are already translated.
func setup(texts: PackedStringArray, start: int = 0) -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	_labels.clear()
	_hits.clear()
	index = clampi(start, 0, maxi(texts.size() - 1, 0))
	for i in texts.size():
		var hit := Button.new()
		hit.name = "Segment%d" % i
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.pressed.connect(_pick.bind(i))
		PressFeedback.attach(hit, &"", 0.5)
		add_child(hit)
		_hits.append(hit)
		var l := Label.new()
		l.name = "Text"
		l.text = texts[i]
		l.theme_type_variation = &"StrongLabel"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hit.add_child(l)
		# the label lives inside the hit (it dips with the press), so the Container is told
		# itself when a label's wrapped height changes
		l.minimum_size_changed.connect(_on_label_min)
		_labels.append(l)
	update_minimum_size()
	queue_sort()
	_pill_x = _seg_x(index)
	_recolor()


func set_texts(texts: PackedStringArray) -> void:
	for i in mini(texts.size(), _labels.size()):
		_labels[i].text = texts[i]
	update_minimum_size()
	queue_sort()


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
		_place_thumb()


## The visible rect of segment [param i] (local px): the track's inner band, an even share.
func segment_rect(i: int) -> Rect2:
	return Rect2(Vector2(_seg_x(i), INSET), Vector2(_seg_w(), maxf(size.y - INSET * 2.0, 0.0)))


func label_of(i: int) -> Label:
	return _labels[i] if i >= 0 and i < _labels.size() else null


func thumb_rect() -> Rect2:
	return Rect2(_thumb.position, _thumb.size)


func _pick(i: int) -> void:
	if i == index:
		return
	AudioDirector.play_cue(CUE_SELECT, {"on": true})
	select(i)
	selected.emit(i)


func _on_label_min() -> void:
	update_minimum_size()
	queue_sort()


func _get_minimum_size() -> Vector2:
	var h := HEIGHT
	var box_w := _seg_w() - LABEL_PAD_X * 2.0
	for l: Label in _labels:
		var text_h := _text_h(l, box_w)
		# once the label has its real width its own minimum is exact (same shaper, same spacing)
		if absf(l.size.x - box_w) < 0.5:
			text_h = maxf(text_h, l.get_minimum_size().y)
		h = maxf(h, text_h + (INSET + LABEL_PAD_Y) * 2.0)
	# no minimum width: long options wrap (AUTOWRAP_WORD_SMART breaks a word that cannot fit)
	return Vector2(0.0, ceilf(h))


## Height of [param l]'s text wrapped at [param width] px (font metrics + the theme's line spacing).
static func _text_h(l: Label, width: float) -> float:
	var font := l.get_theme_font(&"font")
	var fs := l.get_theme_font_size(&"font_size")
	if font == null:
		return float(fs)
	var spacing := float(l.get_theme_constant(&"line_spacing"))
	var lines := 1
	if width > 1.0:
		var flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		var ts := TextServerManager.get_primary_interface()
		var rid := ts.create_shaped_text()
		ts.shaped_text_add_string(rid, l.text, font.get_rids(), fs, {}, TranslationServer.get_locale())
		lines = maxi(ts.shaped_text_get_line_breaks(rid, width, 0, flags).size() >> 1, 1)
		ts.free_rid(rid)
	return float(lines) * (font.get_height(fs) + spacing) - spacing


func _seg_w() -> float:
	return maxf(size.x - INSET * 2.0, 0.0) / float(maxi(_hits.size(), 1))


func _seg_x(i: int) -> float:
	return INSET + _seg_w() * float(i)


func _relayout() -> void:
	var w := _seg_w()
	_fit_font(w - LABEL_PAD_X * 2.0)
	var inner := maxf(size.y - INSET * 2.0, 0.0)
	for i in _hits.size():
		var hit := _hits[i]
		hit.position = Vector2(_seg_x(i), -HIT_GROW)
		hit.size = Vector2(w, size.y + HIT_GROW * 2.0)
		hit.pivot_offset = hit.size * 0.5
		# the ripple stays inside the visible segment (the hit grows past the track)
		var seg := Rect2(Vector2(0.0, HIT_GROW + INSET), Vector2(w, inner))
		hit.set_meta(PressFeedback.META_RIPPLE_RECT, seg)
		hit.set_meta(PressFeedback.META_RIPPLE_RADIUS, inner * 0.5)
		# the label fills the segment's text box. It is sized twice: an autowrap Label clamps a
		# new size to the minimum height of its PREVIOUS width, so the first call fixes the width
		# (and refreshes that minimum), the second sets the real height.
		var l := _labels[i]
		var box := seg.grow_individual(-LABEL_PAD_X, -LABEL_PAD_Y, -LABEL_PAD_X, -LABEL_PAD_Y)
		l.position = box.position
		l.size = Vector2(box.size.x, 0.0)
		l.size = box.size
		l.position = box.position
	if _spring == null or _spring.is_at_rest():
		_pill_x = _seg_x(index)
	_draw_track()
	_place_thumb()


## One size for every option of the control: the theme size, or down to SHRINK_FLOOR of it when
## that keeps every option on one line (large text); below that the options wrap instead.
func _fit_font(box_w: float) -> void:
	if _labels.is_empty() or box_w <= 1.0:
		return
	# the theme's size, looked up past the labels' own overrides (changing an override re-sorts)
	var font := get_theme_font(&"font", &"StrongLabel")
	var fs := get_theme_font_size(&"font_size", &"StrongLabel")
	if font == null:
		return
	var widest := 0.0
	var word := 0.0
	for l: Label in _labels:
		widest = maxf(widest, font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		for part: String in l.text.split(" ", false):
			word = maxf(word, font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var k := 1.0
	if widest > box_w and widest * SHRINK_FLOOR <= box_w:
		k = box_w / widest  # one line at >= 85 %
	elif word > box_w:
		k = maxf(box_w / word, WORD_FLOOR)  # wrap, but never inside a word
	for l: Label in _labels:
		if k < 1.0:
			var want := floori(float(fs) * k)
			if not l.has_theme_font_size_override(&"font_size") or l.get_theme_font_size(&"font_size") != want:
				l.add_theme_font_size_override(&"font_size", want)
		elif l.has_theme_font_size_override(&"font_size"):
			l.remove_theme_font_size_override(&"font_size")


func _recolor() -> void:
	for i in _labels.size():
		_labels[i].add_theme_color_override(&"font_color",
				UiTokens.sc(&"primary_deep") if i == index else UiTokens.sc(&"ink_soft"))


func _draw_track() -> void:
	_track.color = UiTokens.sc(&"primary_tint")
	_track.border_color = UiTokens.sc_tinted(&"ink", UiTokens.alpha(&"divider"))
	_track.border_px = HAIRLINE_DP * UiTokens.PX_PER_DP
	_track.position = Vector2.ZERO
	_track.size = size
	_thumb.color = UiTokens.sc(&"raised")
	_thumb.border_color = UiTokens.sc_tinted(&"primary", THUMB_LINE_ALPHA)
	_thumb.border_px = HAIRLINE_DP * UiTokens.PX_PER_DP


func _place_thumb() -> void:
	_thumb.position = Vector2(_pill_x, INSET)
	_thumb.size = Vector2(_seg_w(), maxf(size.y - INSET * 2.0, 0.0))
