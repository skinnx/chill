extends GutTest
## Round-6 sheet contracts (device QA on a 720x1600 Vietnamese phone, "the sheets are unfriendly"):
## every label lays out inside its own control (segmented options inside their segment, the
## selected one inside the thumb) at rest and after scrolling; nothing in a sheet draws outside
## the sheet's clip (scroll content only under the scroll's clip, chrome inside the sheet); the
## scroll culling never hides a row in view; two detents with a drag; the sheet rises above the
## on-screen keyboard while a field is edited; friends not met yet stand on a real studio well.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const SEED := 4242
## 720x1600 and 1080x2400 phones both run the 1080 x 2400 canvas (stretch canvas_items, expand).
const TALL := Vector2(1080, 2400)
const DOCK_TOP_TALL := 2021.0
const TOP_LIMIT_TALL := 264.0
const SHEET_W := 1032.0
const MEDIUM_TALL := 1584.0
const EPS := 1.0
const MIN_TARGET_PX := 144.0
const SCALES: Array[int] = [100, 150]
## Extra _sheet() kinds: the album opened straight onto one of its other tabs, so the layout
## sweeps below cover all four and not just Friends.
const ALBUM_TABS := {"clues": AlbumSheet.TAB_CLUES, "photos": AlbumSheet.TAB_PHOTOS,
	"postcards": AlbumSheet.TAB_POSTCARDS}
const LOCALES: Array[String] = ["vi", "en"]

var c: GameContent
var _saved_sim: WorldSim
var _saved_ready: bool
var _saved_content: GameContent
var _saved_persist: bool
var _saved_scale: Variant
var _saved_locale: String


func before_all() -> void:
	c = ContentRegistry.content


func before_each() -> void:
	_saved_sim = Game.sim
	_saved_ready = Game.is_ready
	_saved_content = Game.content
	_saved_locale = TranslationServer.get_locale()
	Game.content = c
	_saved_persist = Settings.persist
	Settings.persist = false
	_saved_scale = Settings.get_value(Settings.TEXT_SCALE)
	Game.sim = WorldSim.new_game(c, SEED, Clock.now_unix(), 0.0)
	Game.is_ready = true
	for i in 3:
		Game.sim.state.met[String(c.species[i]["id"])] = Clock.now_unix() - 86400.0 * float(3 - i)


func after_each() -> void:
	TranslationServer.set_locale(_saved_locale)
	Settings.set_value(Settings.TEXT_SCALE, _saved_scale)
	Settings.persist = _saved_persist
	Game.sim = _saved_sim
	Game.is_ready = _saved_ready
	Game.content = _saved_content


func _sheet(kind: String, h: float = MEDIUM_TALL) -> UiSheet:
	var s: UiSheet
	match kind:
		"settings":
			s = SettingsSheet.new()
		"garden":
			s = GardenSheet.new()
		"basket":
			s = BasketSheet.new()
		_:
			s = AlbumSheet.new()
	s.theme = UiTheme.theme
	s.size = Vector2(SHEET_W, h)
	s.position = Vector2(24.0, 400.0)
	add_child_autofree(s)
	if ALBUM_TABS.has(kind):
		(s as AlbumSheet).select_tab(int(ALBUM_TABS[kind]), false)
	return s


## The rect the text of [param l] really occupies (its lines, aligned in the label's rect).
static func _text_rect(l: Label) -> Rect2:
	var r := l.get_global_rect()
	var h := minf(l.get_minimum_size().y, r.size.y) if l.autowrap_mode != TextServer.AUTOWRAP_OFF \
			else l.get_minimum_size().y
	var y := r.position.y
	if l.vertical_alignment == VERTICAL_ALIGNMENT_CENTER:
		y += (r.size.y - h) * 0.5
	elif l.vertical_alignment == VERTICAL_ALIGNMENT_BOTTOM:
		y += r.size.y - h
	return Rect2(Vector2(r.position.x, y), Vector2(r.size.x, h))


static func _inside(inner: Rect2, outer: Rect2, eps: float = EPS) -> bool:
	return outer.grow(eps).encloses(inner)


func _check_segments(s: UiSheet, what: String) -> int:
	var n := 0
	for node: Node in s.find_children("*", "Segmented", true, false):
		var seg := node as Segmented
		if not seg.is_visible_in_tree():
			continue
		var g := seg.get_global_transform()
		for i in seg._labels.size():
			var l := seg.label_of(i)
			var box := g * seg.segment_rect(i)
			assert_true(seg.is_ancestor_of(l), "%s: option label is a real child of its control" % what)
			assert_true(_inside(l.get_global_rect(), box),
					"%s: '%s' label rect %s inside its segment %s" % [what, l.text, l.get_global_rect(), box])
			assert_true(_inside(_text_rect(l), box),
					"%s: '%s' text %s inside its segment %s" % [what, l.text, _text_rect(l), box])
			assert_true(l.get_minimum_size().y <= l.size.y + EPS,
					"%s: '%s' wrapped text fits its box (%s > %s)" % [what, l.text, l.get_minimum_size(), l.size])
			var f := l.get_theme_font(&"font")
			var fs := l.get_theme_font_size(&"font_size")
			for word: String in l.text.split(" ", false):
				assert_true(f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= l.size.x + EPS,
						"%s: '%s' never breaks inside a word" % [what, word])
			n += 1
		var sel := seg.label_of(seg.index)
		var thumb := g * seg.thumb_rect()
		assert_true(_inside(_text_rect(sel), thumb), "%s: the selected '%s' sits inside the thumb" % [what, sel.text])
		var w0 := seg.segment_rect(0).size.x
		for i in seg._labels.size():
			assert_almost_eq(seg.segment_rect(i).size.x, w0, 0.01, "%s: the options divide the track evenly" % what)
			assert_true(seg._hits[i].size.y >= MIN_TARGET_PX, "%s: segment hit >= 48 dp" % what)
	return n


# ------------------------------------------------------------------ blocker: labels in their controls

func test_segment_labels_sit_inside_their_segments_in_every_language_and_size() -> void:
	for loc: String in LOCALES:
		for sc: int in SCALES:
			TranslationServer.set_locale(loc)
			Settings.set_value(Settings.TEXT_SCALE, sc)
			var s := _sheet("settings")
			await wait_process_frames(4)
			var n := _check_segments(s, "%s %d%%" % [loc, sc])
			assert_eq(n, 9, "%s %d%%: music, haptics and language options checked" % [loc, sc])
			s.free()


func test_segment_labels_move_and_clip_with_the_scroll() -> void:
	TranslationServer.set_locale("vi")
	var s := _sheet("settings")
	await wait_process_frames(4)
	var sc := s.scroll_list()
	var bar := sc.get_v_scroll_bar()
	var segs: Array[Node] = s.find_children("*", "Segmented", true, false)
	var lang := segs[segs.size() - 1] as Segmented
	var before := lang.label_of(0).get_global_rect().position.y
	var seg_before := lang.get_global_rect().position.y
	for frac: float in [0.5, 1.0]:
		sc.scroll_vertical = roundi(frac * (bar.max_value - bar.page))
		await wait_process_frames(2)
		_check_segments(s, "scrolled %.1f" % frac)
		var moved := lang.get_global_rect().position.y - seg_before
		assert_almost_eq(lang.label_of(0).get_global_rect().position.y - before, moved, 0.5,
				"the label moves exactly with its control (%.1f)" % frac)
		assert_lt(moved, -1.0, "the content really scrolled")
	_check_clip(s, "settings scrolled")


func test_every_label_lies_inside_its_parent_control() -> void:
	for combo: int in 4:
		TranslationServer.set_locale(LOCALES[combo % 2])
		Settings.set_value(Settings.TEXT_SCALE, SCALES[combo >> 1])
		await _check_labels_in_parents()


func _check_labels_in_parents() -> void:
	for kind: String in ["settings", "garden", "basket", "album", "clues", "photos", "postcards"]:
		var s := _sheet(kind)
		await wait_process_frames(4)
		var count := 0
		for node: Node in s.find_children("*", "Label", true, false):
			var l := node as Label
			if not l.is_visible_in_tree() or UiBatch._is_opaque_scene(l.get_parent()):
				continue
			var parent := l.get_parent() as Control
			if parent == null:
				continue
			var owner_rect := parent.get_global_rect()
			var seg := parent.get_parent() as Segmented
			if seg != null:
				owner_rect = seg.get_global_transform() * seg.segment_rect(seg._hits.find(parent))
			assert_true(_inside(l.get_global_rect(), owner_rect),
					"%s: '%s' %s inside %s %s" % [kind, l.text.left(24), l.get_global_rect(), parent.name, owner_rect])
			if l.autowrap_mode != TextServer.AUTOWRAP_OFF and l.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
				assert_eq(l.get_visible_line_count(), l.get_line_count(),
						"%s: '%s' shows all its lines (nothing cut mid-sentence)" % [kind, l.text.left(24)])
			count += 1
		assert_gt(count, 3, "%s: labels checked" % kind)
		s.free()


func test_nothing_draws_outside_the_sheet_clip() -> void:
	TranslationServer.set_locale("vi")
	for kind: String in ["settings", "garden", "basket", "album", "clues", "photos", "postcards"]:
		var s := _sheet(kind)
		await wait_process_frames(4)
		_check_clip(s, kind)
		var sc := s.scroll_list()
		if sc != null:
			sc.scroll_vertical = roundi(sc.get_v_scroll_bar().max_value)
			await wait_process_frames(2)
			_check_clip(s, kind + " at the end")
		s.free()


## Scroll content sits under the scroll's clip (no top-level, canvas layer or absolute-z escape
## hatch on the way), and every chrome leaf lies inside the sheet.
func _check_clip(s: UiSheet, what: String) -> void:
	var sc := s.scroll_list()
	if sc != null:
		assert_true(sc.clip_contents, "%s: the scroll window clips" % what)
	var sheet_rect := s.get_global_rect()
	for node: Node in s.find_children("*", "CanvasItem", true, false):
		var ci := node as CanvasItem
		if not ci.is_visible_in_tree() or UiBatch._is_opaque_scene(ci.get_parent()):
			continue
		assert_false(ci.top_level, "%s: %s is not top-level (it would leave the clip)" % [what, s.get_path_to(ci)])
		assert_true(ci.z_as_relative, "%s: %s keeps a relative z" % [what, s.get_path_to(ci)])
		assert_eq(ci.clip_children, CanvasItem.CLIP_CHILDREN_DISABLED)
		if not (ci is Control):
			continue
		var ctl := ci as Control
		if sc != null and sc.is_ancestor_of(ctl):
			continue
		if ctl is BaseButton and ctl.get_parent() is Segmented:
			continue  # the segment's hit grows 24 px past the track by design (it draws nothing)
		if ctl.name == &"Glass" or ctl is ScrollContainer or ctl == s.body:
			continue
		assert_true(_inside(ctl.get_global_rect(), sheet_rect),
				"%s: chrome %s %s inside the sheet %s" % [what, s.get_path_to(ctl), ctl.get_global_rect(), sheet_rect])


func test_scroll_culling_never_hides_a_row_in_view() -> void:
	var s := _sheet("settings")
	await wait_process_frames(4)
	var sc := s.scroll_list()
	var window := sc.get_global_rect()
	sc.scroll_vertical = roundi(sc.get_v_scroll_bar().max_value)
	await wait_process_frames(2)
	var list := sc.get_child(0).get_child(0) as Control
	var shown := 0
	for row: Node in list.get_children():
		var r := (row as Control).get_global_rect()
		if r.intersects(window):
			assert_eq((row as Control).modulate.a, 1.0, "a row in the window draws (%s)" % r)
			shown += 1
	assert_gt(shown, 1, "rows in view after a long jump")


# ------------------------------------------------------------------ sheet height and detents

func _host(kind: String) -> SheetHost:
	var host := SheetHost.new()
	host.factory = func(_id: StringName) -> UiSheet:
		var s: UiSheet = SettingsSheet.new() if kind == "settings" else AlbumSheet.new()
		s.theme = UiTheme.theme
		return s
	host.top_limit = TOP_LIMIT_TALL
	add_child_autofree(host)
	host.layout(TALL, DOCK_TOP_TALL)
	return host


func test_tall_phone_sheet_opens_taller_and_drags_to_a_large_detent() -> void:
	var host := _host("settings")
	var med := host.sheet_rect()
	assert_eq(med.size.y, MEDIUM_TALL, "20:9: the medium detent is 0.66 H")
	assert_eq(med.end.y, DOCK_TOP_TALL - SheetHost.DOCK_GAP, "bottom = dock top - 24")
	var large := host.large_rect()
	assert_eq(large.position.y, TOP_LIMIT_TALL + SheetHost.DOCK_GAP, "large reaches the top bar + 24")
	assert_true(large.size.y <= SheetHost.LARGE_FRAC * TALL.y, "large <= 0.80 H")
	host.open(&"settings", true)
	var s := host.current
	await wait_process_frames(3)
	assert_eq(s.get_global_rect(), med, "opens at the medium detent")
	var sc_h := s.scroll_list().size.y
	s.drag_begin(1000.0, 0.0)
	s.drag_to(1000.0 - (large.size.y - med.size.y), 0.2)
	s.drag_end(0.2)
	await wait_seconds(1.2)
	assert_true(s.expanded, "a drag up reaches the large detent")
	assert_almost_eq(s.size.y, large.size.y, 2.0, "large height")
	assert_almost_eq(s.position.y + s.size.y, med.end.y, 0.5, "the bottom stays put")
	assert_almost_eq(s.scroll_list().size.y - sc_h, large.size.y - med.size.y, 2.0, "the scroll window follows")
	s.drag_begin(500.0, 0.0)
	s.drag_to(500.0 + (large.size.y - med.size.y), 0.2)
	s.drag_end(0.2)
	await wait_seconds(1.2)
	assert_false(s.expanded, "back down to medium")
	assert_true(host.is_open(), "still open at the medium detent")
	s.drag_begin(500.0, 0.0)
	s.drag_to(500.0 + med.size.y * 0.4, 0.2)
	s.drag_end(0.2)
	assert_false(host.is_open(), "below the medium detent the drag dismisses")


## Round 8: the dismiss velocity is measured over a 100 ms window and is ZERO once the finger has
## rested, so "pull the sheet down a little, hold it there to look at the world behind it, lift"
## springs back instead of closing. It used to carry the speed of a pull that had finished a
## second ago. The same change makes the threshold mean the same thing at 30 and at 60 fps,
## because a per-event average's time constant is the frame interval (ARCHITECTURE §3.5).
func test_swipe_velocity_is_windowed_and_goes_stale() -> void:
	var host := _host("settings")
	host.open(&"settings", true)
	var s := host.current
	await wait_process_frames(3)
	# A real flick: 300 px over 100 ms = 3000 px/s, well past the 1000 px/s dismiss speed.
	s.drag_begin(500.0, 0.0)
	s.drag_to(600.0, 0.033)
	s.drag_to(700.0, 0.066)
	s.drag_to(800.0, 0.1)
	assert_gt(s.drag_velocity(0.1), 1000.0, "the flick reads as a flick")
	# The same samples, read a quarter of a second later: the finger has stopped.
	assert_eq(s.drag_velocity(0.35), 0.0, "a finger that rested carries no speed")


func test_the_same_flick_reads_the_same_at_30_and_60_fps() -> void:
	var host := _host("settings")
	host.open(&"settings", true)
	var s := host.current
	await wait_process_frames(3)
	var speeds: Array[float] = []
	for dt: float in [1.0 / 60.0, 1.0 / 30.0]:
		# 1200 px/s for 100 ms, sampled once per rendered frame as accumulation delivers it.
		var steps := int(roundf(0.1 / dt))
		s.drag_begin(500.0, 0.0)
		for i in range(1, steps + 1):
			s.drag_to(500.0 + 1200.0 * dt * float(i), dt * float(i))
		speeds.append(s.drag_velocity(dt * float(steps)))
	assert_almost_eq(speeds[0], 1200.0, 1.0, "60 fps")
	assert_almost_eq(speeds[1], 1200.0, 1.0, "30 fps agrees")


## Round 9: the sheet follows the finger anywhere in the list, not only in its 76 dp header.
## On a 1080x2400 phone the header zone sits in the top quarter of the screen, so every way to
## resize or dismiss a sheet was out of the thumb's reach while the part under the thumb did
## nothing. Helper: one press, then drags, on the list itself.
func _list_press(sc: ScrollContainer, at: Vector2) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.global_position = at
	mb.position = at
	sc.gui_input.emit(mb)


func _list_move(sc: ScrollContainer, at: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	mm.global_position = at
	mm.position = at
	sc.gui_input.emit(mm)


func _list_release(sc: ScrollContainer, at: Vector2) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = false
	mb.global_position = at
	mb.position = at
	sc.gui_input.emit(mb)


func test_pulling_down_in_the_list_drags_the_sheet() -> void:
	var host := _host("settings")
	host.open(&"settings", true)
	var s := host.current
	await wait_process_frames(3)
	s.expand(true)
	await wait_seconds(0.8)
	assert_true(s.expanded, "start at the large detent")
	var sc := s.scroll_list()
	assert_eq(sc.scroll_vertical, 0, "premise: the list is at its top")
	var h0 := s.sheet_h
	var at := sc.get_global_rect().get_center()
	_list_press(sc, at)
	# The claiming event anchors the drag where the finger is and moves nothing (the no-jump rule).
	_list_move(sc, at + Vector2(0.0, UiSheet.LIST_HANDOFF_PX + 1.0))
	assert_almost_eq(s.sheet_h, h0, 0.5, "the handoff itself costs no jump")
	_list_move(sc, at + Vector2(0.0, 120.0))
	assert_lt(s.sheet_h, h0, "from there the sheet follows the finger toward medium")
	_list_move(sc, at + Vector2(0.0, 400.0))
	assert_almost_eq(s.sheet_h, s.h_medium, 1.0, "past medium the height clamps")
	assert_gt(s.rise, 0.0, "and the whole sheet rides down with the finger")
	# What the release then decides - settle at a detent or dismiss - is the header drag's own
	# rule, already covered by test_tall_phone_sheet_opens_taller_and_drags_to_a_large_detent.
	_list_release(sc, at + Vector2(0.0, 400.0))


func test_a_small_or_sideways_or_upward_drag_leaves_the_list_alone() -> void:
	var host := _host("settings")
	host.open(&"settings", true)
	var s := host.current
	await wait_process_frames(3)
	s.expand(true)
	await wait_seconds(0.8)
	var sc := s.scroll_list()
	var h0 := s.sheet_h
	var at := sc.get_global_rect().get_center()
	for d: Vector2 in [Vector2(0.0, UiSheet.LIST_HANDOFF_PX - 2.0), Vector2(200.0, 10.0),
			Vector2(0.0, -200.0)]:
		_list_press(sc, at)
		_list_move(sc, at + d)
		_list_release(sc, at + d)
		assert_almost_eq(s.sheet_h, h0, 0.5, "the sheet is untouched by %s" % d)


## Content above the window means the list scrolls first; the sheet only takes a pull from the top.
func test_a_scrolled_list_keeps_its_own_drag() -> void:
	var host := _host("settings")
	host.open(&"settings", true)
	var s := host.current
	await wait_process_frames(3)
	s.expand(true)
	await wait_seconds(0.8)
	var sc := s.scroll_list()
	sc.scroll_vertical = 120
	await wait_process_frames(2)
	var h0 := s.sheet_h
	var at := sc.get_global_rect().get_center()
	_list_press(sc, at)
	_list_move(sc, at + Vector2(0.0, 200.0))
	_list_release(sc, at + Vector2(0.0, 200.0))
	assert_almost_eq(s.sheet_h, h0, 0.5, "the list scrolls, the sheet stays put")


## Round 9: a gift landing, a bloom, a heart - each fires a sim event whose refresh rebuilds the
## sheet's rows. Doing that under a thumb frees the control the press belongs to, so the tap it
## was going to be never happens. The news waits for the finger to leave.
func test_a_refresh_waits_for_the_finger_to_leave() -> void:
	var host := _host("settings")
	host.open(&"settings", true)
	var s := host.current
	await wait_process_frames(3)
	var sc := s.scroll_list()
	var at := sc.get_global_rect().get_center()
	assert_false(s.is_touched(), "nothing is touching it yet")
	_list_press(sc, at)
	_list_move(sc, at + Vector2(0.0, UiSheet.LIST_HANDOFF_PX + 1.0))
	assert_true(s.is_touched(), "a finger has the sheet")
	host.refresh()
	assert_true(host._refresh_pending, "the rebuild is held, not run under the thumb")
	_list_release(sc, at + Vector2(0.0, UiSheet.LIST_HANDOFF_PX + 1.0))
	assert_false(s.is_touched())
	await wait_process_frames(2)
	assert_false(host._refresh_pending, "and lands once the finger is gone")


func test_16_9_keeps_the_art_bible_sheet() -> void:
	var host := SheetHost.new()
	add_child_autofree(host)
	host.top_limit = TOP_LIMIT_TALL
	host.layout(Vector2(1080, 1920), 1541.0)
	assert_eq(host.sheet_rect(), Rect2(24, 442, 1032, 1075), "sheet 24..1056 x 442..1517 at H 1920")


func test_last_item_clears_the_bottom_edge() -> void:
	var s := _sheet("settings")
	await wait_process_frames(4)
	var sc := s.scroll_list()
	sc.scroll_vertical = roundi(sc.get_v_scroll_bar().max_value)
	await wait_process_frames(2)
	var list := sc.get_child(0).get_child(0) as Control
	var last := list.get_child(list.get_child_count() - 1) as Control
	var gap := sc.get_global_rect().end.y - last.get_global_rect().end.y
	assert_true(gap >= UiSheet.LIST_END_PAD - EPS, "the last card ends %.0f px above the window's edge" % gap)
	s._process(0.0)
	assert_true(UiBatch._bands.y <= 1.0 + EPS, "no bottom fade at the end of the list")
	sc.scroll_vertical = 0
	await wait_process_frames(2)
	s._process(0.0)
	assert_true(UiBatch._bands.x <= 1.0 + EPS, "no top fade at the top")
	assert_almost_eq(UiBatch._bands.y, UiBatch.FADE_BOTTOM_PX, 0.5, "a full bottom fade while more waits below")


# ------------------------------------------------------------------ rename + keyboard

func test_rename_raises_the_sheet_above_the_keyboard() -> void:
	var host := _host("album")
	host.open(&"album", true)
	var s := host.current as AlbumSheet
	s.show_friend(StringName(String(c.species[0]["id"])))
	await wait_process_frames(3)
	var kb := 1000.0
	host.qa_keyboard_px = kb
	s.begin_rename()
	await wait_seconds(1.2)
	var field := s._name_edit
	assert_true(field.has_focus(), "the name field is being edited")
	var kb_top := TALL.y - kb
	assert_true(s.get_global_rect().end.y <= kb_top + EPS, "the sheet's bottom clears the keyboard")
	assert_true(s.get_global_rect().position.y >= TOP_LIMIT_TALL + SheetHost.DOCK_GAP - EPS, "never over the top bar")
	var fr := field.get_global_rect()
	assert_true(fr.end.y <= kb_top and s.scroll_list().get_global_rect().encloses(fr),
			"the field is in view above the keys")
	var done := s.find_child("Done", true, false) as Button
	assert_true(done != null and done.visible, "a Done pill while editing")
	assert_true(done.size.y >= MIN_TARGET_PX, "Done >= 48 dp")
	assert_eq(field.get_theme_color(&"font_selected_color"), UiTokens.sc(&"ink"), "selected text stays ink")
	field.text = "Mochi"
	field.text_submitted.emit(field.text)
	await wait_seconds(1.2)
	assert_false(field.has_focus(), "Enter / Done ends the edit")
	assert_eq(Game.display_name(StringName(String(c.species[0]["id"]))), "Mochi", "renamed")
	host.qa_keyboard_px = 0.0
	await wait_seconds(1.2)
	assert_almost_eq(s.lift, 0.0, 1.0, "the sheet settles back when the keyboard goes")


# ------------------------------------------------------------------ not met yet

func test_album_cards_hug_their_content_in_every_language_and_size() -> void:
	for combo: int in 4:
		TranslationServer.set_locale(LOCALES[combo % 2])
		Settings.set_value(Settings.TEXT_SCALE, SCALES[combo >> 1])
		var s := _sheet("album")
		await wait_process_frames(4)
		var grid := s.find_children("*", "GridContainer", true, false)[0] as GridContainer
		var tallest := 0.0
		for n: Node in grid.get_children():
			var b := n as Control
			var cardp := b.get_child(0) as Control
			tallest = maxf(tallest, cardp.get_combined_minimum_size().y)
		for n: Node in grid.get_children():
			var b := n as Control
			assert_true(b.size.y <= tallest + EPS, "%s: a friend card is no taller than the row's content (%.0f > %.0f)"
					% [LOCALES[combo % 2], b.size.y, tallest])
		assert_true(tallest < 900.0, "cards stay card-sized (%.0f)" % tallest)
		s.free()


func test_friends_not_met_yet_stand_on_a_studio_well() -> void:
	var sp := StringName(String(c.species[c.species.size() - 1]["id"]))
	var cell := AlbumSheet.portrait_cell(sp, false, &"awake")
	add_child_autofree(cell)
	assert_true(cell is LiveWell, "the same studio sweep and cushion as a met friend")
	var p := cell.find_children("*", "CreaturePortrait", true, false)[0] as CreaturePortrait
	await wait_process_frames(1)
	assert_false(p.known)
	assert_true(CreaturePortrait.SILHOUETTE_ALPHA >= 0.2, "the silhouette reads on a phone (>= ink 0.20)")
	assert_eq(p.find_children("*", "Mossling", true, false).size(), 0, "no face, no rig: a silhouette only")


# ------------------------------------------------------------------ album > clues (round 10)

## The retention_mid world, where two mysteries are open and clues have been found.
func _mysteries_open() -> void:
	var st := WorldSim.new_game(c, SEED, Clock.now_unix(), 0.0).state
	GardenFixture.apply(c, st, GardenFixture.MID)
	var sim := WorldSim.new(c, st)
	RetentionFixture.apply(sim, StringName(c.scenes[0]["id"]))
	sim = WorldSim.new(c, st)
	sim.drain_events()
	Game.sim = sim


func test_the_clues_tab_is_reachable_and_reads_empty_before_anyone_is_on_the_way() -> void:
	var s := _sheet("album") as AlbumSheet
	for tab: int in [AlbumSheet.TAB_CLUES, AlbumSheet.TAB_PHOTOS, AlbumSheet.TAB_POSTCARDS]:
		s.select_tab(tab, false)
		assert_eq(s.current_tab(), tab, "tab %d is reachable (the clamp covers all four)" % tab)
	s.select_tab(AlbumSheet.TAB_CLUES, false)
	await wait_process_frames(4)
	var texts: Array[String] = []
	for n: Node in s.find_children("*", "Label", true, false):
		texts.append((n as Label).text)
	assert_true(texts.has(tr("CLUES_EMPTY")), "a fresh world says clues will gather here: %s" % [texts])


## GDD §13.3.3: "dots, never a number" - the tab says what you have, not what you owe. The count
## is only a tooltip, so the dots are the thing that has to be right.
func test_a_clue_card_counts_in_dots_and_names_the_state_it_is_in() -> void:
	_mysteries_open()
	var cards := Game.clue_cards()
	assert_false(cards.is_empty(), "premise: retention_mid has mysteries open")
	for combo: int in 4:
		TranslationServer.set_locale(LOCALES[combo % 2])
		Settings.set_value(Settings.TEXT_SCALE, SCALES[combo >> 1])
		var s := _sheet("clues")
		await wait_process_frames(4)
		var rows: Array[Node] = []
		for n: Node in s.find_children("*", "HBoxContainer", true, false):
			if not (n as Control).get_children().is_empty() and ((n as Control).get_child(0) as Label) != null \
					and ((n as Control).get_child(0) as Label).text in ["\u25CF", "\u25CB"]:
				rows.append(n)
		assert_eq(rows.size(), cards.size(), "one dot row per open mystery")
		for i in cards.size():
			var full := 0
			var dots := (rows[i] as Control).get_children()
			for d: Node in dots:
				if (d as Label).text == "\u25CF":
					full += 1
			assert_eq(dots.size(), int(cards[i]["total"]), "a dot for every clue of the mystery")
			assert_eq(full, int(cards[i]["found"]), "filled dots = clues found")
			assert_eq((rows[i] as Control).tooltip_text,
					I18n.fmt(&"CLUES_COUNT", {"count": cards[i]["found"], "total": cards[i]["total"]}),
					"the number is there for a screen reader, not on the card")
		var texts: Array[String] = []
		for n: Node in s.find_children("*", "Label", true, false):
			texts.append((n as Label).text)
		for card_i: Dictionary in cards:
			var sp: StringName = StringName(String(card_i["species"]))
			var want := tr("CLUES_SOMEONE")
			if bool(card_i["solved"]):
				want = I18n.fmt(&"CLUES_SOLVED", {"name": Game.display_name(sp)})
			elif String(card_i["variant"]) != "":
				want = I18n.fmt(&"CLUES_COUSIN", {"name": Game.display_name(sp)})
			assert_true(texts.has(want), "%s: the card is titled '%s'" % [LOCALES[combo % 2], want])
		s.free()
