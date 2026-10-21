class_name OverlayHost
extends Control
## Everything that floats above the HUD (Art Bible §9.4, §10.3; GDD §3.4, §7.2, §7.5, §8.1):
##  * toasts: faux-glass pill h 96 centred at y 400, Label 42, auto-dismiss after 3 s;
##  * sound captions (X1 "Sound captions"): small glass bubbles beside the source of a cue;
##  * modal cards on a 0.40 scrim (surface_hi, r-l 72, e3, x 72..1008): the welcome-back recap
##    (tap or 5 s), "Leave the hollow for now?", the new-friend card (shrinks into the Album button)
##    and the postcard reader. Each modal registers a Back handler while it is open.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const TOAST_H := 96.0
const TOAST_Y := 400.0
const TOAST_PAD := 48.0
const TOAST_S := 3.0
const CAPTION_H := 78.0
const CAPTION_PAD := 30.0
const CAPTION_HOLD_S := 2.5
const CAPTION_MAX := 3
const CAPTION_LIFT := 150.0
const CARD_SIDE := 72.0
const CARD_PAD := 60
const RECAP_ICON := 72.0
const CUE_RECAP := &"S10"
const CUE_NEW_FRIEND := &"S09"
const CUE_OPEN := &"S07"
const CUE_CLOSE := &"S08"
## Recap line key -> icon (palettes icon set).
const RECAP_ICONS := {&"RECAP_NEW_FRIEND": &"heart", &"RECAP_ONE_VISITED": &"album", &"RECAP_FRIENDS_VISITED": &"album",
	&"RECAP_NAPPED": &"moon", &"RECAP_BLOOMED": &"garden", &"RECAP_GIFTS": &"basket", &"RECAP_PHOTOS": &"photo",
	&"RECAP_POSTCARD": &"postcard", &"RECAP_RAINED": &"rain"}
const PORTRAIT := 360.0
const RECAP_BAR_H := 9.0
## --qa-recap holds the card with this much of the auto-continue line left.
const RECAP_QA_LEFT := 0.62

var hud: HudController
var _toast: GlassPanel
var _toast_label: Label
var _toast_tween: Tween
var _scrim: ColorRect
var _modal: Control
## Centres the modal card; Labels wrap at the card width, then the card takes its natural height.
var _modal_wrap: CenterContainer
var _modal_back := Callable()
var _modal_kind: StringName = &""
var _captions: Array[GlassPanel] = []
var _screen: Vector2 = Vector2(1080, 1920)
var _safe := Rect2(48, 72, 48, 127)
var _recap_timer: SceneTreeTimer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_scrim = ColorRect.new()
	_scrim.name = "ModalScrim"
	_scrim.color = UiTokens.tinted(&"scrim", UiTokens.alpha(&"scrim_modal"))
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.visible = false
	_scrim.gui_input.connect(_on_scrim_input)
	add_child(_scrim)
	_toast = GlassPanel.new()
	_toast.name = "Toast"
	_toast.visible = false
	add_child(_toast)
	_toast_label = Label.new()
	_toast_label.theme_type_variation = &"StrongLabel"
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_child(_toast_label)
	_modal_back = close_modal


func layout(screen: Vector2, safe: Rect2) -> void:
	_screen = screen
	_safe = safe
	_place_toast()
	if _modal != null:
		_place_modal()


func is_modal_open() -> bool:
	return _modal != null


# ------------------------------------------------------------------ toast

## [param seconds] 0 keeps it until [method hide_toast].
func show_toast(text: String, seconds: float = TOAST_S, instant: bool = false) -> void:
	_toast_label.text = text
	_toast.visible = true
	_place_toast()
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	if instant:
		_toast.modulate.a = 1.0
	else:
		_toast_tween = Motion.fade_in(_toast, &"short")
	if seconds > 0.0:
		var t := _toast.create_tween()
		t.tween_interval(seconds)
		t.tween_callback(hide_toast)


func hide_toast() -> void:
	if not _toast.visible:
		return
	_toast_tween = Motion.fade_out(_toast, &"exit")
	_toast_tween.finished.connect(func() -> void: _toast.visible = false)


func _place_toast() -> void:
	var w := minf(_toast_label.get_combined_minimum_size().x + TOAST_PAD * 2.0, _screen.x - CARD_SIDE * 2.0)
	_toast.size = Vector2(w, TOAST_H)
	_toast.position = Vector2((_screen.x - w) * 0.5, maxf(TOAST_Y, _safe.position.y + TOAST_Y - 120.0) - TOAST_H * 0.5)
	_toast_label.size = _toast.size
	_toast_label.position = Vector2.ZERO


# ------------------------------------------------------------------ captions

func on_cue_played(_id: StringName, caption_key: StringName, world_position: Vector2) -> void:
	if caption_key == &"" or not Settings.get_bool(Settings.CAPTIONS):
		return
	var p := _screen * Vector2(0.5, 0.62)
	if world_position != Vector2.ZERO:
		p = get_viewport().get_canvas_transform() * world_position + Vector2(0.0, -CAPTION_LIFT)
	show_caption(tr(caption_key), p)


func show_caption(text: String, at: Vector2, hold: bool = false) -> void:
	for c: GlassPanel in _captions:
		if is_instance_valid(c) and c.has_meta(&"text") and String(c.get_meta(&"text")) == text:
			return
	while _captions.size() >= CAPTION_MAX:
		var old: GlassPanel = _captions.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var bubble := GlassPanel.new()
	bubble.set_meta(&"text", text)
	add_child(bubble)
	move_child(bubble, _scrim.get_index())
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"CaptionLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(l)
	var w := l.get_combined_minimum_size().x + CAPTION_PAD * 2.0
	bubble.size = Vector2(w, CAPTION_H)
	l.size = bubble.size
	var x := clampf(at.x - w * 0.5, _safe.position.x, _screen.x - _safe.size.x - w)
	bubble.position = Vector2(x, clampf(at.y, _safe.position.y + 300.0, _screen.y - 600.0))
	_captions.append(bubble)
	Motion.fade_in(bubble, &"short")
	if hold:
		return
	var t := bubble.create_tween()
	t.tween_interval(CAPTION_HOLD_S)
	t.tween_property(bubble, "modulate:a", 0.0, Motion.duration(&"exit"))
	t.tween_callback(func() -> void:
		_captions.erase(bubble)
		bubble.queue_free())


# ------------------------------------------------------------------ modal cards

func _open_modal(card: Control, kind: StringName, instant: bool) -> void:
	close_modal(true)
	_modal = card
	_modal_kind = kind
	_modal_wrap = CenterContainer.new()
	_modal_wrap.name = "Modal"
	_modal_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_modal_wrap)
	_modal_wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_wrap.add_child(card)
	_place_modal()
	_scrim.visible = true
	Game.push_back_handler(_modal_back)
	if instant:
		_scrim.modulate.a = 1.0
		return
	_scrim.modulate.a = 0.0
	Motion.tween(_scrim, "modulate:a", 1.0, &"short")
	card.pivot_offset = card.size * 0.5
	card.modulate.a = 0.0
	if Motion.reduce_motion:
		Motion.tween(card, "modulate:a", 1.0, &"short")
		return
	card.scale = Vector2(0.92, 0.92)
	card.rotation = deg_to_rad(-2.0) if kind == &"postcard" else 0.0
	Motion.tween(card, "scale", Vector2.ONE, &"emphasized")
	Motion.tween(card, "rotation", 0.0, &"emphasized")
	Motion.tween(card, "modulate:a", 1.0, &"emphasized")


func close_modal(instant: bool = false) -> void:
	if _modal == null:
		return
	var card := _modal
	var wrap := _modal_wrap
	var kind := _modal_kind
	_modal = null
	_modal_wrap = null
	_modal_kind = &""
	Game.remove_back_handler(_modal_back)
	if _recap_timer != null:
		_recap_timer = null
	if instant:
		wrap.queue_free()
		_scrim.visible = false
		return
	var st := Motion.tween(_scrim, "modulate:a", 0.0, &"exit")
	st.finished.connect(func() -> void:
		if _modal == null:
			_scrim.visible = false)
	if kind == &"new_friend" and hud != null and not Motion.reduce_motion:
		# GDD §3.4: the card shrinks into the Album button, which wakes.
		var album := hud.dock.button(&"album")
		var target := album.global_position + album.center() - card.size * 0.5
		Motion.tween(card, "position", target, &"emphasized")
		Motion.tween(card, "scale", Vector2(0.12, 0.12), &"emphasized")
		var f := Motion.tween(card, "modulate:a", 0.0, &"emphasized")
		f.finished.connect(wrap.queue_free)
		hud.dock.set_asleep(&"album", false)
		return
	var f2 := Motion.exit(card, "modulate:a", 0.0)
	f2.finished.connect(wrap.queue_free)


func _place_modal() -> void:
	_modal.custom_minimum_size = Vector2(_screen.x - CARD_SIDE * 2.0, 0.0)
	_modal.resized.connect(func() -> void: _modal.pivot_offset = _modal.size * 0.5)


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		if _modal_kind in [&"recap", &"new_friend", &"postcard"]:
			close_modal()
		_scrim.accept_event()


static func _card_shell(sep: int = 24) -> Array:
	var p := PanelContainer.new()
	var box := UiTokens.fill_box(UiTokens.color(&"surface_hi"), ThemeBuilder.R_L, UiTokens.E3)
	box.set_content_margin_all(CARD_PAD)
	p.add_theme_stylebox_override(&"panel", box)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	return [p, v]


# ------------------------------------------------------------------ recap (GDD §7.5)

func sample_recap() -> Array:
	return [{"key": &"RECAP_NEW_FRIEND", "species": &"buttonbud"}, {"key": &"RECAP_ONE_VISITED", "species": &"puffmoss"},
		{"key": &"RECAP_GIFTS", "species": &""}]


func show_recap(lines: Array, hold: bool = false) -> void:
	var shell := _card_shell(30)
	var card: PanelContainer = shell[0]
	var v: VBoxContainer = shell[1]
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and not (e as InputEventMouseButton).pressed:
			close_modal())
	var title := UiSheet.label(tr("RECAP_TITLE"), &"TitleLabel", true)
	v.add_child(title)
	for line: Variant in lines:
		var d: Dictionary = line
		var key := StringName(String(d.get("key", "")))
		var sp := StringName(String(d.get("species", "")))
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 30)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon: StringName = RECAP_ICONS.get(key, &"heart")
		var plate := _icon_plate(icon)
		row.add_child(plate)
		var text := I18n.fmt(key, {"name": Game.display_name(sp) if sp != &"" and Game.sim != null else ""})
		var l := UiSheet.label(text, &"BodyLabel", true)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(l)
		v.add_child(row)
	# The auto-continue line (5 s): a quiet primary hairline that shortens, so the card never
	# disappears by surprise (tap anywhere skips it).
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0.0, RECAP_BAR_H)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_meta(&"left", 1.0)
	bar.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, bar.size)
		bar.draw_style_box(UiTokens.fill_box(UiTokens.color(&"primary_tint"), RECAP_BAR_H * 0.5), r)
		var w := r.size.x * float(bar.get_meta(&"left"))
		if w > RECAP_BAR_H:
			bar.draw_style_box(UiTokens.fill_box(UiTokens.color(&"primary"), RECAP_BAR_H * 0.5),
					Rect2(r.position, Vector2(w, RECAP_BAR_H))))
	v.add_child(bar)
	_open_modal(card, &"recap", hold)
	AudioDirector.play_cue(CUE_RECAP)
	var auto := UiTokens.ui_float("recap_auto_dismiss_ms", 5000.0) * UiTokens.MS
	if hold:
		bar.set_meta(&"left", RECAP_QA_LEFT)
		return
	var t := bar.create_tween()
	t.tween_method(func(u: float) -> void:
		bar.set_meta(&"left", 1.0 - u)
		bar.queue_redraw(), 0.0, 1.0, auto)
	t.tween_callback(func() -> void:
		if _modal == card:
			close_modal())


func _icon_plate(icon: StringName) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(RECAP_ICON + 36.0, RECAP_ICON + 36.0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tint: Color = UiTokens.color(&"primary_tint")
	c.draw.connect(func() -> void:
		c.draw_style_box(UiTokens.fill_box(tint, c.size.y * 0.5), Rect2(Vector2.ZERO, c.size)))
	var r := Icons.rect(icon, RECAP_ICON)
	r.position = Vector2(18.0, 18.0)
	c.add_child(r)
	return c


# ------------------------------------------------------------------ leave (GDD §8.1)

func show_leave(instant: bool = false) -> void:
	if _modal_kind == &"leave":
		close_modal()
		return
	var shell := _card_shell(30)
	var card: PanelContainer = shell[0]
	var v: VBoxContainer = shell[1]
	v.add_child(UiSheet.label(tr("LEAVE_TITLE"), &"TitleLabel", true))
	v.add_child(UiSheet.label(tr("LEAVE_DESC"), &"BodyLabel", true))
	var stay := UiSheet.pill_button(tr("LEAVE_NO"), true, ThemeBuilder.BUTTON_H)
	stay.pressed.connect(func() -> void: close_modal())
	v.add_child(stay)
	var leave := UiSheet.pill_button(tr("LEAVE_YES"), false, ThemeBuilder.BUTTON_H)
	leave.pressed.connect(func() -> void:
		close_modal(true)
		Game.leave_now())
	v.add_child(leave)
	_open_modal(card, &"leave", instant)


# ------------------------------------------------------------------ new friend (GDD §3.4)

func show_new_friend(species: StringName, instant: bool = false) -> void:
	if Game.sim == null:
		return
	var shell := _card_shell(18)
	var card: PanelContainer = shell[0]
	var v: VBoxContainer = shell[1]
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var tag := _pill_tag(tr("NEWFRIEND_TITLE"), &"coral_tint")
	tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(tag)
	v.add_child(_portrait_well(species, &"happy"))
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override(&"separation", 6)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_l := UiSheet.label(I18n.fmt(&"NEWFRIEND_THIS_IS", {"name": Game.display_name(species)}), &"TitleLabel")
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_row.add_child(name_l)
	var pencil := RoundButton.new()
	pencil.plate_px = 96.0
	pencil.icon_px = 42.0
	pencil.icon_name = &"pencil"
	pencil.fill_token = &"primary_tint"
	pencil.elevation = UiTokens.E0
	pencil.custom_minimum_size = Vector2(144.0, 144.0)
	pencil.tooltip_text = tr("ALBUM_RENAME")
	PressFeedback.attach(pencil)
	pencil.pressed.connect(func() -> void:
		close_modal(true)
		if hud != null:
			hud.open_friend(species))
	name_row.add_child(pencil)
	v.add_child(name_row)
	var sp: Dictionary = ContentRegistry.content.species_by_id.get(species, {})
	var desc := UiSheet.label(tr(String(sp.get("desc_key", ""))), &"BodyLabel", true)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(desc)
	var hi := UiSheet.pill_button(tr("NEWFRIEND_SAY_HI"), true, ThemeBuilder.BUTTON_H)
	hi.pressed.connect(func() -> void: close_modal())
	v.add_child(hi)
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and not (e as InputEventMouseButton).pressed:
			close_modal())
	_open_modal(card, &"new_friend", instant)
	AudioDirector.play_cue(CUE_NEW_FRIEND)


func _portrait_well(species: StringName, pose: StringName) -> Control:
	var p := CreaturePortrait.new()
	p.setup(species, true, pose)
	return LiveWell.wrap(p, Vector2(0.0, PORTRAIT), ThemeBuilder.R_L)


static func _pill_tag(text: String, fill: StringName) -> Control:
	var p := PanelContainer.new()
	var box := UiTokens.fill_box(UiTokens.color(fill), 33.0)
	box.content_margin_left = 33
	box.content_margin_right = 33
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	p.add_theme_stylebox_override(&"panel", box)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiSheet.label(text, &"StrongLabel")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


# ------------------------------------------------------------------ postcards (GDD §7.2)

## The mailbox: the newest unread postcard, else the Album's Postcards tab.
func show_postcard_or_album() -> void:
	if Game.sim == null:
		return
	var cards := Game.sim.state.postcards
	for i in range(cards.size() - 1, -1, -1):
		var pc: Dictionary = cards[i]
		if not bool(pc.get("read", false)):
			show_postcard(pc)
			return
	if hud != null:
		hud.open_sheet(&"album")
		var a := hud.sheets.current as AlbumSheet
		if a != null:
			a.select_tab(2, false)


func show_postcard(pc: Dictionary, instant: bool = false) -> void:
	var shell := _card_shell(24)
	var card: PanelContainer = shell[0]
	var v: VBoxContainer = shell[1]
	var sp := StringName(String(pc.get("species", "")))
	if sp != &"":
		v.add_child(_portrait_well(sp, &"happy"))
	else:
		var well := PanelContainer.new()
		well.add_theme_stylebox_override(&"panel", UiTokens.fill_box(UiTokens.color(&"coral_tint"), ThemeBuilder.R_L))
		well.custom_minimum_size = Vector2(0.0, PORTRAIT * 0.6)
		var ic := Icons.rect(&"postcard", PORTRAIT * 0.4)
		ic.set_anchors_preset(Control.PRESET_CENTER)
		well.add_child(ic)
		v.add_child(well)
	var name := Game.display_name(sp) if sp != &"" else ""
	v.add_child(UiSheet.label(I18n.fmt(StringName(String(pc.get("template", ""))), {"name": name}), &"BodyLabel", true))
	var sig_text := I18n.fmt(&"POSTCARD_SIGNATURE", {"name": name}) if sp != &"" else tr("POSTCARD_SIGNATURE_HOLLOW")
	var sig := UiSheet.label(sig_text,
			&"StrongLabel", true)
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(sig)
	var keep := UiSheet.pill_button(tr("COMMON_DONE"), true, ThemeBuilder.BUTTON_H)
	keep.pressed.connect(func() -> void: close_modal())
	v.add_child(keep)
	Game.read_postcard(String(pc.get("id", "")))
	AudioDirector.play_cue(CUE_OPEN)
	_open_modal(card, &"postcard", instant)


# ------------------------------------------------------------------ bed card (long-press a bed)

func show_bed_card(bed: StringName) -> void:
	if Game.sim == null:
		return
	var b: Dictionary = {}
	for d: Dictionary in ContentRegistry.content.beds:
		if StringName(String(d["id"])) == bed:
			b = d
	var text := tr(String(b.get("name_key", String(bed))))
	var soonest := INF
	var sim := Game.sim
	for s: Dictionary in sim.state.stems:
		if StringName(String(s["bed"])) == bed and int(s["stage"]) < WorldSim.STAGE_BLOOM:
			var f: Dictionary = ContentRegistry.content.flowers_by_id.get(StringName(String(s["flower"])), {})
			var left := float(s["planted_t"]) + float(f.get("bloom_at_s", 0.0)) - sim.state.t
			soonest = minf(soonest, left)
	if soonest < INF:
		text = "%s · %s" % [text, I18n.fmt(&"GARDEN_BLOOMS_IN", {"time": I18n.duration_text(maxf(soonest, 60.0))})]
	show_toast(text)
