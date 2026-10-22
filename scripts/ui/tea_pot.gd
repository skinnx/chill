class_name TeaPot
extends Control
## The Tea sheet's Brew panel (Active F2, GDD §14.1, ACTIVE_TEA §3-§4): the open felt teapot with
## its spoon and stitched progress ring, the tray of cups (2 x 3) and the petal pantry (5 + 4 jars,
## the last one the dew drop). One control draws everything from the tea atlas (TeaArt), so the
## whole panel is one or two batches; labels and the Stir / Pour / Brew pills are children.
##
## Gestures (mouse path only, ARCHITECTURE §3.5; nothing here pans, scrolls or closes the sheet):
##  * drag a petal from a jar past 24 px and drop it over the pot (1.4 x the pot) - anywhere else it
##    floats back; tap a jar = one petal (the tap alternative); tap a petal or drop in the pot = it
##    goes back to its jar (a drop refunds its dew);
##  * stir: a circular drag around the pot's mouth; only motion 28-150 dp from the centre counts,
##    at most 45 deg per event, either direction, any speed; lifting keeps the progress; the Stir
##    pill adds 180 deg over 600 ms;
##  * pour: once stirred, drag the pot toward the tray: it tilts with the thumb (0-55 deg) and past
##    30 deg the pour plays to its end by itself (1.2 s); released before, it springs back; the
##    Pour pill does the same;
##  * Simple brewing (Settings, default = Reduce Motion): one Brew pill after the petals.
## Nothing times out and every press answers in the same frame (squash, S01).
##
## Every state change goes through the Game tea API (pot_add_petal, pot_stir, pot_pour, ...); the
## view only animates what the model already holds.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## A cup or treat was made (after the pour or the simple brew): the sheet shows the reveal.
signal brewed(recipe: StringName, first: bool, tray_index: int)
## A cup on the tray was tapped (the sheet opens the offer row).
signal cup_tapped(index: int)
## A short caption for the step line (pot room, tray full, jar empty, more dew).
signal note(text: String)
## The pot, pantry or tray changed (the sheet refreshes its labels).
signal changed

enum Drag { NONE, JAR, PETAL, POT_ITEM, STIR, POUR, CUP }

const DP := UiTokens.PX_PER_DP
## Pantry jars 56 dp, gaps >= 8 dp; tray cups 48 dp (ACTIVE_TEA §10).
const JAR := 56.0 * DP
const JAR_GAP_MIN := 8.0 * DP
const JAR_ROW_GAP := 10.0 * DP
const CUP := 48.0 * DP
const CUP_GAP := 8.0 * DP
const TRAY_COLS := 2
const GAP := 8.0 * DP
const BUTTON_H := 48.0 * DP
const STEP_H := 20.0 * DP
const DROP_JAR := 8
const JARS := 9
const JARS_ROW1 := 5
## Pot geometry in pot_body piece px (pivot = the foot): the mouth (stir centre), its radii, the
## body centre (drop zone) and the spout tip (pour stream).
const MOUTH := Vector2(0.0, -182.0)
const MOUTH_R := Vector2(112.0, 26.0)
const BODY := Vector2(0.0, -120.0)
const BODY_R := 160.0
const SPOUT := Vector2(204.0, -229.0)
const HANDLE := Vector2(-160.0, -126.0)
const POT_W := 460.0
const POT_H := 340.0
## Petals afloat on the tea and piled in a jar.
const FLOAT_SCALE := 0.95
const JAR_PILE_MAX := 6
const JAR_ART_SCALE := 0.78
const JAR_PETAL_SCALE := 0.62
const RING_R := Vector2(176.0, 64.0)
const RING_DOTS := 44
const RING_DOT := 0.46
## The tray rests on a felt mat (a batched surface behind the cups).
const TRAY_MAT_PAD := 8.0 * DP
const STREAM_DOTS := 22
## Press squash of a jar / cup (ui.world_touch_squash family) and its settle.
const PRESS_SQUASH := 0.92
const BOB_S := 0.36
const FLIGHT_ARC := 0.35
const HAPTIC_TICK := {"full": "TICK"}
const HAPTIC_MEDIUM := {"subtle": "MEDIUM", "full": "MEDIUM"}
const CUE_TOUCH := &"S01"
const CUE_NOT_YET := &"S11"
const CUE_PLIP := &"S29"
const CUE_STIR := &"S30"
const CUE_POUR := &"S31"

## Shown in place of the pantry (the sheet draws the friend chips there).
var offer_mode: bool = false:
	set(v):
		offer_mode = v
		_sync_children()
		queue_redraw()
## The tray cup picked for offering (-1 none).
var selected_cup: int = -1:
	set(v):
		selected_cup = v
		queue_redraw()
## Simple brewing: one Brew pill instead of stir and pour.
var simple: bool = false:
	set(v):
		simple = v
		_sync_children()
## Reduce Motion: no swirl, flights fade instead of arcing.
var calm: bool = false
## QA stills: hold the current frame of every animation.
var qa_freeze: bool = false
var jar_flowers: Array[StringName] = []

var _cfg: Dictionary = {}
var _pot: Dictionary = {}
var _pantry: Dictionary = {}
var _tray: Array[Dictionary] = []
var _teaware: Dictionary = {}
var _drag: Drag = Drag.NONE
var _drag_index: int = -1
var _press_at := Vector2.ZERO
var _drag_at := Vector2.ZERO
var _last_angle: float = 0.0
var _stir_shown: float = 0.0
var _stir_anim: float = 0.0
var _swirl: float = 0.0
var _tilt: float = 0.0
var _tilt_spring: Spring
var _pour_t: float = -1.0
var _pour_slot: int = -1
var _simple_t: float = -1.0
var _color := TeaArt.WATER
var _bob: Dictionary = {}
var _press_key: String = ""
var _flights: Array[Dictionary] = []
var _hidden_pot: int = 0
var _room_noted: bool = false
var _time: float = 0.0
var _btn_stir: Button
var _btn_pour: Button
var _btn_brew: Button
var _step: Label
var _counts: Array[Label] = []
var _drop_cost: Label
var _drop_icon: TextureRect
var _tray_mat: UiSurface
var _note_until: float = -1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_tilt_spring = Motion.spring(&"move", 0.0)
	var tea: Dictionary = ContentRegistry.content.tea
	_cfg = tea.get("brewing", {})
	var rows: Array = tea.get("petals", [])
	var ordered: Array = rows.duplicate()
	ordered.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int((a as Dictionary).get("jar_order", 0)) < int((b as Dictionary).get("jar_order", 0)))
	for r: Variant in ordered:
		jar_flowers.append(StringName(String((r as Dictionary).get("flower", ""))))
	calm = Motion.reduce_motion


func _ready() -> void:
	_step = UiSheet.label("", &"SecondaryLabel")
	_step.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_step)
	_btn_stir = _pill("TEA_BTN_STIR", false)
	_btn_stir.pressed.connect(stir_step)
	_btn_pour = _pill("TEA_BTN_POUR", true)
	_btn_pour.pressed.connect(pour)
	_btn_brew = _pill("TEA_BTN_BREW", true)
	_btn_brew.pressed.connect(brew_simple)
	for i in JARS:
		var l := UiSheet.label("", &"CaptionLabel")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		_counts.append(l)
	_drop_icon = Icons.rect(&"dew", 33.0)
	_drop_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_drop_icon)
	_drop_cost = _counts[DROP_JAR]
	_tray_mat = UiSurface.make(UiTokens.sc(&"surface_hi"), ThemeBuilder.R_M, UiTokens.E1)
	_tray_mat.name = "TrayMat"
	_tray_mat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tray_mat)
	move_child(_tray_mat, 0)
	resized.connect(_layout)
	refresh()
	_stir_shown = float(_pot.get("stir_deg", 0.0))
	_color = _target_color()
	_layout()
	_lift_z.call_deferred()


## Draw above the sheet's surfaces and icons (UiBatch layers a plain Control at its parent's z).
func _lift_z() -> void:
	var root := UiBatch._root_of(self)
	if root == null:
		return
	z_as_relative = true
	z_index = int(root.get_meta(UiBatch.META_BASE, 0)) + UiBatch.TEX + UiBatch.TEX_SLOTS - 1 - UiBatch._parent_abs(self)
	# the children were layered against the old z: layer them again (the tray mat under the cups)
	for c: Node in get_children():
		UiBatch.place(c)


func _pill(key: String, primary: bool) -> Button:
	var b := UiSheet.pill_button(tr(key), primary, BUTTON_H)
	b.custom_minimum_size.x = 0.0
	b.set_meta(&"tr_key", key)
	add_child(b)
	return b


## Re-reads the pot, pantry, tray and teaware from Game.
func refresh() -> void:
	if Game.sim == null:
		return
	_pot = Game.pot()
	_pantry = Game.pantry()
	_tray = Game.tray()
	_teaware = Game.teaware().get("in_use", {})
	if _pour_t < 0.0 and _drag != Drag.STIR and _stir_anim <= 0.0:
		_stir_shown = float(_pot.get("stir_deg", 0.0))
	_sync_children()
	queue_redraw()


func refresh_texts() -> void:
	for b: Button in [_btn_stir, _btn_pour, _btn_brew]:
		if b != null:
			b.text = tr(String(b.get_meta(&"tr_key", "")))
	_sync_children()


# ------------------------------------------------------------------ state queries (tests, sheet)

func petals_in_pot() -> Array:
	return _pot.get("petals", [])


func drops_in_pot() -> int:
	return int(_pot.get("drops", 0))


func stir_target() -> float:
	return float(_pot.get("stir_target", _cfg.get("stir_target_deg", 540.0)))


func stir_done() -> bool:
	return not petals_in_pot().is_empty() and float(_pot.get("stir_deg", 0.0)) >= stir_target()


func is_busy() -> bool:
	return _pour_t >= 0.0 or _simple_t >= 0.0


## The step the pot is at: &"add", &"stir", &"pour" (ACTIVE_TEA §4).
func step() -> StringName:
	if petals_in_pot().is_empty():
		return &"add"
	if simple:
		return &"brew"
	return &"pour" if stir_done() else &"stir"


# ------------------------------------------------------------------ layout (local px)

func pot_scale() -> float:
	var col := maxf(size.x - tray_width() - GAP * 2.0, 1.0)
	var area := maxf(pot_area().size.y, 1.0)
	return clampf(minf(col / (POT_W + 20.0), area / (POT_H + 150.0)), 0.45, 1.2)


func tray_width() -> float:
	return CUP * TRAY_COLS + CUP_GAP * (TRAY_COLS - 1) + TRAY_MAT_PAD


## The region above the step line and pills.
func pot_area() -> Rect2:
	var top_of_buttons := jars_top() - GAP - BUTTON_H - GAP * 0.5 - STEP_H
	return Rect2(0.0, 0.0, size.x, maxf(top_of_buttons - GAP, 0.0))


func jars_top() -> float:
	return size.y - JAR * 2.0 - JAR_ROW_GAP


## The pantry region (the offer row replaces it).
func jars_rect() -> Rect2:
	return Rect2(0.0, jars_top(), size.x, JAR * 2.0 + JAR_ROW_GAP)


func jar_gap() -> float:
	return maxf((size.x - JAR * JARS_ROW1) / float(JARS_ROW1 - 1), JAR_GAP_MIN)


func jar_rect(i: int) -> Rect2:
	var row := 0 if i < JARS_ROW1 else 1
	var col := i if row == 0 else i - JARS_ROW1
	return Rect2(col * (JAR + jar_gap()), jars_top() + row * (JAR + JAR_ROW_GAP), JAR, JAR)


func tray_rect(i: int) -> Rect2:
	var slots := int(TeaArt.tea_num("tray", "slots", 6))
	var rows := ceili(float(slots) / TRAY_COLS)
	var h := rows * CUP + (rows - 1) * CUP_GAP
	var y0 := maxf((pot_area().size.y - h) * 0.5, 0.0)
	var col := i % TRAY_COLS
	var row := i / TRAY_COLS
	return Rect2(size.x - tray_width() - TRAY_MAT_PAD + col * (CUP + CUP_GAP), y0 + row * (CUP + CUP_GAP), CUP, CUP)


func pot_foot() -> Vector2:
	var a := pot_area()
	var col := size.x - tray_width() - GAP
	var s := pot_scale()
	return Vector2(col * 0.5 + 10.0 * s, a.size.y * 0.5 + (POT_H * 0.5 + 24.0) * s)


func pot_xf() -> Transform2D:
	return Transform2D(deg_to_rad(_tilt), pot_foot())


## The stir centre (the pot's mouth) in local px.
func stir_centre() -> Vector2:
	return pot_foot() + MOUTH * pot_scale()


func _drop_zone_hit(p: Vector2) -> bool:
	var k := float(_cfg.get("drop_zone_scale", 1.4))
	return p.distance_to(pot_foot() + BODY * pot_scale()) <= BODY_R * pot_scale() * k


func _layout() -> void:
	if _step == null:
		return
	var col := size.x - tray_width() - GAP
	var by := jars_top() - GAP - BUTTON_H
	_step.position = Vector2(0.0, by - GAP * 0.5 - STEP_H)
	_step.size = Vector2(col, STEP_H)
	var shown: Array[Button] = []
	for b: Button in [_btn_stir, _btn_pour, _btn_brew]:
		if b.visible:
			shown.append(b)
	var w := 0.0
	for b: Button in shown:
		w += b.get_combined_minimum_size().x
	w += GAP * 3.0 * maxf(shown.size() - 1, 0)
	var x := maxf((col - w) * 0.5, 0.0)
	for b: Button in shown:
		b.size = Vector2(b.get_combined_minimum_size().x, BUTTON_H)
		b.position = Vector2(x, by)
		x += b.size.x + GAP * 3.0
	for i in JARS:
		var r := jar_rect(i)
		var l := _counts[i]
		l.size = Vector2(r.size.x, 40.0)
		l.position = Vector2(r.position.x, r.end.y - 34.0)
	_drop_icon.position = jar_rect(DROP_JAR).position + Vector2(JAR * 0.5 - 36.0, JAR - 36.0)
	_drop_cost.position.x += 18.0
	var slots := int(TeaArt.tea_num("tray", "slots", 6))
	var tr0 := tray_rect(0)
	_tray_mat.position = tr0.position - Vector2(TRAY_MAT_PAD, TRAY_MAT_PAD)
	_tray_mat.size = tray_rect(slots - 1).end - tr0.position + Vector2(TRAY_MAT_PAD, TRAY_MAT_PAD) * 2.0
	queue_redraw()


func _sync_children() -> void:
	if _step == null:
		return
	var st := step()
	# Stir and Pour both show once there is a petal (the next one waits, softly disabled)
	_btn_stir.visible = not simple and st in [&"stir", &"pour"]
	_btn_pour.visible = not simple and st in [&"stir", &"pour"]
	_btn_brew.visible = simple and st == &"brew"
	_btn_stir.disabled = st != &"stir" or is_busy()
	_btn_pour.disabled = st != &"pour" or is_busy()
	_btn_brew.disabled = is_busy()
	# the step to do now is the primary pill; the one after waits as a soft secondary
	for b: Button in [_btn_stir, _btn_pour]:
		var v := &"SecondaryButton" if b.disabled else &""
		if b.theme_type_variation != v:
			b.theme_type_variation = v
			b.queue_redraw()
	var key := "TEA_POT_EMPTY"
	match st:
		&"stir":
			key = "TEA_STEP_STIR"
		&"pour":
			key = "TEA_STEP_POUR_TREAT" if drops_in_pot() >= 2 else "TEA_STEP_POUR"
		&"brew":
			key = "TEA_STEP_ADD"
		_:
			key = "TEA_STEP_ADD" if _pantry_total() > 0 else "TEA_JAR_EMPTY"
	if _note_until < _time:
		_step.text = tr(key)
	for i in JARS:
		var l := _counts[i]
		l.visible = not offer_mode
		if i == DROP_JAR:
			l.text = str(int(TeaArt.tea_num("dew_drop", "cost_dew", 3)))
		else:
			var n := int(_pantry.get(String(jar_flowers[i]), 0)) if i < jar_flowers.size() else 0
			# an empty jar is just glass (no "0": never greyed, never locked)
			l.text = str(n) if n > 0 else ""
	_drop_icon.visible = not offer_mode
	_layout()


func _pantry_total() -> int:
	var n := 0
	for f: String in _pantry:
		n += int(_pantry[f])
	return n


## Shows [param text] on the step line for a few seconds (and emits [signal note]).
func show_note(text: String) -> void:
	if _step != null:
		_step.text = text
		_note_until = _time + 3.0
	note.emit(text)


# ------------------------------------------------------------------ tap alternatives (pills, tests)

## Tap a jar: one petal (or a dew drop) into the pot.
func tap_jar(i: int) -> bool:
	if offer_mode or is_busy() or i < 0 or i >= JARS:
		return false
	_bob_jar(i)
	var from := jar_rect(i).get_center()
	if i == DROP_JAR:
		return _add_drop(from)
	return _add_petal(jar_flowers[i], from)


func _add_petal(flower: StringName, from: Vector2) -> bool:
	if int(_pantry.get(String(flower), 0)) <= 0:
		show_note(tr("TEA_JAR_EMPTY"))
		AudioDirector.play_cue(CUE_NOT_YET)
		return false
	if petals_in_pot().size() >= int(TeaArt.tea_num("pot", "max_petals", 3)):
		_room_note()
		return false
	if not Game.pot_add_petal(flower):
		return false
	refresh()
	_fly(String(flower), from, _float_pos(petals_in_pot().size() - 1), true)
	TeaArt.cue(CUE_PLIP, {"index": petals_in_pot().size()}, HAPTIC_TICK)
	changed.emit()
	return true


func _add_drop(from: Vector2) -> bool:
	var max_drops := int(TeaArt.tea_num("pot", "max_drops", 2))
	if drops_in_pot() >= max_drops:
		_room_note()
		return false
	if not Game.pot_add_drop():
		AudioDirector.play_cue(CUE_NOT_YET)
		_bob_jar(DROP_JAR, true)
		show_note(tr("GARDEN_MORE_DEW"))
		return false
	refresh()
	_fly("drop", from, _drop_float_pos(drops_in_pot() - 1), true)
	TeaArt.cue(CUE_PLIP, {"index": drops_in_pot()}, HAPTIC_TICK)
	changed.emit()
	return true


func _room_note() -> void:
	_bob_jar(_drag_index if _drag_index >= 0 else 0)
	if not _room_noted:
		_room_noted = true
		show_note(tr("TEA_POT_ROOM"))


## Tap a petal (index) or a drop (index >= petals) in the pot: back to its jar.
func take_out(index: int) -> bool:
	if is_busy():
		return false
	var petals := petals_in_pot()
	if index < petals.size():
		var flower := StringName(String(petals[index]))
		var at := _float_pos(index)
		if not Game.pot_remove(index):
			return false
		refresh()
		var j := jar_flowers.find(flower)
		_fly(String(flower), at, jar_rect(maxi(j, 0)).get_center(), false)
	elif index - petals.size() < drops_in_pot():
		var at2 := _drop_float_pos(index - petals.size())
		if not Game.pot_remove_drop():
			return false
		refresh()
		_fly("drop", at2, jar_rect(DROP_JAR).get_center(), false)
	else:
		return false
	AudioDirector.play_cue(CUE_TOUCH)
	changed.emit()
	return true


## The Stir pill: +180 deg animated over 600 ms (three taps finish the stir).
func stir_step() -> void:
	if petals_in_pot().is_empty() or stir_done() or is_busy():
		return
	var before := float(_pot.get("stir_deg", 0.0))
	Game.pot_stir(float(_cfg.get("stir_tap_alt_deg_per_tap", 180.0)))
	refresh()
	_stir_shown = before
	_stir_anim = float(_cfg.get("stir_tap_anim_ms", 600.0)) * UiTokens.MS
	set_process(true)
	changed.emit()


## The Pour pill (or a tilt past 30 deg): the pour plays to its end by itself.
func pour() -> void:
	if not stir_done() or is_busy():
		return
	if _tray_full():
		return
	_pour_slot = _tray.size()
	_pour_t = 0.0
	TeaArt.cue(CUE_POUR, {}, {})
	FrameGovernor.hold_for(float(_cfg.get("pour_ms", 1200.0)) * UiTokens.MS + 0.3)
	_sync_children()
	set_process(true)


## Simple brewing: the petals dissolve into the cup in one cross-fade.
func brew_simple() -> void:
	if petals_in_pot().is_empty() or is_busy() or _tray_full():
		return
	_simple_t = 0.0
	_pour_slot = _tray.size()
	TeaArt.cue(CUE_POUR, {}, {})
	FrameGovernor.hold_for(float(_cfg.get("simple_brew_ms", 900.0)) * UiTokens.MS + 0.3)
	_sync_children()
	set_process(true)


func _tray_full() -> bool:
	if _tray.size() >= int(TeaArt.tea_num("tray", "slots", 6)):
		AudioDirector.play_cue(CUE_NOT_YET)
		show_note(tr("TEA_TRAY_FULL"))
		return true
	return false


func _finish_brew(simple_brew: bool) -> void:
	var before := Game.recipes_found()
	var recipe := Game.simple_brew() if simple_brew else Game.pot_pour()
	_pour_t = -1.0
	_simple_t = -1.0
	_tilt_spring = Motion.spring(&"move", _tilt)
	_tilt_spring.target = 0.0
	refresh()
	_stir_shown = 0.0
	_color = TeaArt.WATER
	if recipe != &"":
		Haptics.play_for_cue(HAPTIC_TICK, &"S31")
		brewed.emit(recipe, not before.has(String(recipe)), _tray.size() - 1)
	changed.emit()


# ------------------------------------------------------------------ input (mouse path only)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			press(mb.position)
		else:
			release(mb.position)
		accept_event()
	elif event is InputEventMouseMotion and _drag != Drag.NONE:
		move((event as InputEventMouseMotion).position)
		accept_event()


## Touch-down (public for tests and the QA states).
func press(p: Vector2) -> void:
	_press_at = p
	_drag_at = p
	_drag = Drag.NONE
	_drag_index = -1
	if is_busy():
		return
	for i in _tray.size():
		if tray_rect(i).grow(GAP * 0.5).has_point(p):
			_drag = Drag.CUP
			_drag_index = i
			_squash("cup%d" % i)
			return
	if not offer_mode:
		for i in JARS:
			if jar_rect(i).has_point(p):
				_drag = Drag.JAR
				_drag_index = i
				_squash("jar%d" % i)
				return
	var item := pot_item_at(p)
	if item >= 0:
		_drag = Drag.POT_ITEM
		_drag_index = item
		AudioDirector.play_cue(CUE_TOUCH)
		return
	if stir_done() and not simple and _pot_hit(p):
		_drag = Drag.POUR
		AudioDirector.play_cue(CUE_TOUCH)
		return
	if not petals_in_pot().is_empty() and not stir_done() and not simple:
		var d := p.distance_to(stir_centre())
		if d <= float(_cfg.get("stir_ring_outer_dp", 150.0)) * DP:
			_drag = Drag.STIR
			_last_angle = (p - stir_centre()).angle()


func move(p: Vector2) -> void:
	_drag_at = p
	var threshold := float(_cfg.get("petal_drag_threshold_px", 24.0))
	match _drag:
		Drag.JAR:
			if p.distance_to(_press_at) > threshold and _jar_can_give(_drag_index):
				_drag = Drag.PETAL
				_press_key = ""
		Drag.STIR:
			var add := stir_delta(_last_angle, p, stir_centre(), float(_cfg.get("stir_ring_inner_dp", 28.0)) * DP,
					float(_cfg.get("stir_ring_outer_dp", 150.0)) * DP, float(_cfg.get("stir_max_deg_per_event", 45.0)))
			_last_angle = (p - stir_centre()).angle()
			if absf(add) > 0.0:
				_stir_by(add)
		Drag.POUR:
			_tilt = pour_tilt(p - _press_at, float(_cfg.get("pour_drag_dp", 40.0)) * DP,
					float(_cfg.get("pour_start_tilt_deg", 30.0)), float(_cfg.get("pour_tilt_max_deg", 55.0)))
			if _tilt >= float(_cfg.get("pour_start_tilt_deg", 30.0)) and _pour_t < 0.0:
				_drag = Drag.NONE
				pour()
				if _pour_t < 0.0:
					_spring_tilt_back()
	queue_redraw()
	set_process(true)


func release(p: Vector2) -> void:
	var kind := _drag
	var i := _drag_index
	_drag = Drag.NONE
	_press_key = ""
	var tapped := p.distance_to(_press_at) <= float(_cfg.get("petal_drag_threshold_px", 24.0))
	match kind:
		Drag.JAR:
			if tapped:
				tap_jar(i)
		Drag.PETAL:
			if _drop_zone_hit(p):
				if i == DROP_JAR:
					_add_drop(p)
				else:
					_add_petal(jar_flowers[i], p)
			else:
				# not a miss: the petal simply floats home
				_fly("drop" if i == DROP_JAR else String(jar_flowers[i]), p, jar_rect(i).get_center(), false)
		Drag.POT_ITEM:
			if tapped:
				take_out(i)
		Drag.CUP:
			if tapped:
				cup_tapped.emit(i)
		Drag.POUR:
			if _pour_t < 0.0:
				_spring_tilt_back()
	queue_redraw()
	set_process(true)


func _spring_tilt_back() -> void:
	_tilt_spring = Motion.spring(&"move", _tilt)
	_tilt_spring.target = 0.0
	set_process(true)


func _jar_can_give(i: int) -> bool:
	if i == DROP_JAR:
		return true
	return i < jar_flowers.size() and int(_pantry.get(String(jar_flowers[i]), 0)) > 0


func _pot_hit(p: Vector2) -> bool:
	var s := pot_scale()
	return p.distance_to(pot_foot() + BODY * s) <= BODY_R * s * 1.2 or p.distance_to(pot_foot() + HANDLE * s) <= 70.0 * s


## The pot item under [param p]: a petal index, or petals.size() + a drop index; -1 none.
func pot_item_at(p: Vector2) -> int:
	var petals := petals_in_pot()
	var r := 30.0 * DP * 0.5 * maxf(pot_scale(), 0.8)
	for i in petals.size():
		if p.distance_to(_float_pos(i)) <= r:
			return i
	for d in drops_in_pot():
		if p.distance_to(_drop_float_pos(d)) <= r:
			return petals.size() + d
	return -1


func _stir_by(deg: float) -> void:
	var before := float(_pot.get("stir_deg", 0.0))
	var now := Game.pot_stir(absf(deg))
	_pot["stir_deg"] = now
	_stir_shown = now
	_swirl += deg
	var step_deg := float(_cfg.get("stir_haptic_every_deg", 180.0))
	if floorf(now / step_deg) > floorf(before / step_deg):
		TeaArt.cue(CUE_STIR, {"bell": true}, HAPTIC_TICK)
	if now >= stir_target() and before < stir_target():
		refresh()
		changed.emit()


## Degrees one motion event adds to the stir (signed, for the swirl): the angle swept around
## [param centre] since [param last_angle], 0 outside the ring [inner, outer] px, clamped to
## [param max_deg] so a scribble through the centre adds nothing strange (ACTIVE_TEA §4).
static func stir_delta(last_angle: float, p: Vector2, centre: Vector2, inner: float, outer: float,
		max_deg: float) -> float:
	var d := p.distance_to(centre)
	if d < inner or d > outer:
		return 0.0
	var a := (p - centre).angle()
	var delta := rad_to_deg(wrapf(a - last_angle, -PI, PI))
	return clampf(delta, -max_deg, max_deg)


## The pot's tilt (deg) for a pour drag [param drag] (toward the tray: right and down): [param
## per_px] px of travel reach [param start_deg]; at most [param max_deg].
static func pour_tilt(drag: Vector2, per_px: float, start_deg: float, max_deg: float) -> float:
	var travel := maxf(drag.dot(Vector2(0.6, 0.8)), 0.0)
	return clampf(travel / maxf(per_px, 1.0) * start_deg, 0.0, max_deg)


# ------------------------------------------------------------------ animation

func _squash(key: String) -> void:
	_press_key = key
	_bob[key] = 0.0
	AudioDirector.play_cue(CUE_TOUCH)
	set_process(true)


func _bob_jar(i: int, nudge: bool = false) -> void:
	_bob["jar%d" % i] = -1.0 if nudge else 0.0
	set_process(true)


func _fly(what: String, from: Vector2, to: Vector2, into_pot: bool) -> void:
	var dur := float(_cfg.get("petal_fly_back_ms", 320.0)) * UiTokens.MS
	_flights.append({"what": what, "from": from, "to": to, "t": 0.0, "dur": dur, "pot": into_pot})
	if into_pot:
		_hidden_pot += 1
	FrameGovernor.hold_for(dur + 0.1)
	set_process(true)


## QA: steps the animations by [param seconds] at once (then [member qa_freeze] holds them).
func qa_advance(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var dt := minf(left, 1.0 / 60.0)
		_step_anim(dt)
		left -= dt
	queue_redraw()


func _process(delta: float) -> void:
	if qa_freeze:
		return
	_step_anim(delta)


func _step_anim(delta: float) -> void:
	_time += delta
	var busy := false
	for k: String in _bob.keys():
		var v := float(_bob[k])
		v = v + delta if v >= 0.0 else v - delta
		if absf(v) >= BOB_S:
			_bob.erase(k)
		else:
			_bob[k] = v
			busy = true
	if _press_key != "":
		busy = true
	var keep: Array[Dictionary] = []
	for f: Dictionary in _flights:
		f["t"] = float(f["t"]) + delta
		if float(f["t"]) < float(f["dur"]):
			keep.append(f)
		elif bool(f["pot"]):
			_hidden_pot = maxi(_hidden_pot - 1, 0)
	_flights = keep
	busy = busy or not _flights.is_empty()
	if _stir_anim > 0.0:
		var target := float(_pot.get("stir_deg", 0.0))
		var step_deg := (target - _stir_shown) * minf(delta / maxf(_stir_anim, 1e-3), 1.0)
		var before := _stir_shown
		_stir_shown += step_deg
		_swirl += step_deg * 1.0
		_stir_anim -= delta
		var every := float(_cfg.get("stir_haptic_every_deg", 180.0))
		if floorf(_stir_shown / every + 0.001) > floorf(before / every + 0.001):
			TeaArt.cue(CUE_STIR, {"bell": true}, HAPTIC_TICK)
		if _stir_anim <= 0.0:
			_stir_shown = target
		busy = true
	if _pour_t >= 0.0:
		_pour_t += delta
		var dur := float(_cfg.get("pour_ms", 1200.0)) * UiTokens.MS
		var u := clampf(_pour_t / dur, 0.0, 1.0)
		var max_t := float(_cfg.get("pour_tilt_max_deg", 55.0))
		_tilt = lerpf(_tilt, max_t * (1.0 - smoothstep(0.82, 1.0, u)) + max_t * 0.15 * smoothstep(0.82, 1.0, u),
				minf(delta * 10.0, 1.0))
		busy = true
		if _pour_t >= dur:
			_finish_brew(false)
	elif _simple_t >= 0.0:
		_simple_t += delta
		busy = true
		if _simple_t >= float(_cfg.get("simple_brew_ms", 900.0)) * UiTokens.MS:
			_finish_brew(true)
	elif _drag != Drag.POUR and not _tilt_spring.is_at_rest():
		_tilt = _tilt_spring.step(delta)
		busy = true
	elif _drag != Drag.POUR and absf(_tilt) > 0.01 and _tilt_spring.is_at_rest():
		_tilt = 0.0
	var want := _target_color()
	if not _color.is_equal_approx(want):
		_color = _color.lerp(want, minf(delta * (8.0 if calm else 4.0), 1.0))
		busy = true
	if stir_done() or _any_full_jar():
		busy = true
	queue_redraw()
	if busy:
		FrameGovernor.poke()
	elif _drag == Drag.NONE:
		set_process(false)


func _any_full_jar() -> bool:
	for f: String in _pantry:
		if int(_pantry[f]) >= int((ContentRegistry.content.petals_by_flower.get(StringName(f), {}) as Dictionary).get(
				"pantry_cap", 24)):
			return true
	return false


## The tea colour so far: warm water blending toward the petals' colour in three steps (180,
## 360 and 540 deg; ACTIVE_TEA §4 step 2). Simple brewing shows the final colour.
func _target_color() -> Color:
	var petals := petals_in_pot()
	if petals.is_empty():
		return TeaArt.WATER
	var final := TeaArt.liquid_color(petals, drops_in_pot() >= 2)
	if simple:
		return TeaArt.WATER.lerp(final, 0.35 + 0.65 * clampf(_simple_t / 0.9, 0.0, 1.0) if _simple_t >= 0.0 else 0.35)
	var steps := floorf(_stir_shown / 180.0 + 0.001)
	return TeaArt.WATER.lerp(final, clampf(0.2 + steps / 3.0 * 0.8, 0.0, 1.0))


# ------------------------------------------------------------------ drawing

## A petal afloat on the tea (local px): a calm scatter on the liquid, turned by the swirl.
func _float_pos(i: int) -> Vector2:
	var s := pot_scale()
	var j := TeaArt.scatter(i, 7)
	var a := TAU * (float(i) / 3.0 + j.x * 0.2) + (0.0 if calm else deg_to_rad(_swirl))
	var r := 0.42 + 0.28 * j.y
	var local := MOUTH + Vector2(cos(a) * MOUTH_R.x * r, sin(a) * MOUTH_R.y * r - 4.0)
	return pot_foot() + (local * s).rotated(deg_to_rad(_tilt))


func _drop_float_pos(d: int) -> Vector2:
	var s := pot_scale()
	var a := PI * 0.5 + float(d) * 1.4 + (0.0 if calm else deg_to_rad(_swirl) * 0.8)
	var local := MOUTH + Vector2(cos(a) * MOUTH_R.x * 0.2, sin(a) * MOUTH_R.y * 0.2)
	return pot_foot() + (local * s).rotated(deg_to_rad(_tilt))


func _press_scale(key: String) -> float:
	if not _bob.has(key):
		return 1.0
	var v := float(_bob[key])
	var u := clampf(absf(v) / BOB_S, 0.0, 1.0)
	if key == _press_key:
		return PRESS_SQUASH
	return 1.0 - (1.0 - PRESS_SQUASH) * sin(PI * u) * (1.0 - u) * 2.0


func _draw() -> void:
	if Game.sim == null:
		return
	_draw_tray()
	_draw_pot()
	if not offer_mode:
		_draw_jars()
	_draw_flights()
	if _drag == Drag.PETAL and _drag_index >= 0:
		var what := "drop" if _drag_index == DROP_JAR else String(jar_flowers[_drag_index])
		# the drop zone answers softly while a petal is carried (a stitched circle; brighter over it)
		var over := _drop_zone_hit(_drag_at)
		var zr := BODY_R * pot_scale() * float(_cfg.get("drop_zone_scale", 1.4))
		_dots_ellipse(pot_foot() + BODY * pot_scale(), Vector2(zr, zr * 0.62), 0.0, TAU, 40, 0.42,
				UiTokens.sc_tinted(&"primary", 0.55 if over else 0.22))
		# the carried petal rides above the thumb with a soft shadow below it
		_draw_item("dot_shadow", _drag_at + Vector2(0.0, 26.0), 1.0, 0.18)
		_draw_item(what, _drag_at + Vector2(0.0, -48.0), 1.6, 1.0)


func _draw_item(what: String, at: Vector2, k: float, alpha: float) -> void:
	if what == "dot_shadow":
		draw_set_transform(at, 0.0, Vector2(2.2 * k, 0.8 * k))
		draw_texture_rect_region(TeaArt.texture(), Rect2(-TeaArt.pivot(&"dot"), TeaArt.region(&"dot").size),
				TeaArt.region(&"dot"), Color(0.29, 0.23, 0.2, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if what == "drop":
		TeaArt.draw(self, &"drop", at + Vector2(0.0, 30.0) * k, 0.62 * k, 0.0, Color(1, 1, 1, alpha))
	else:
		var c := TeaArt.flower_color(StringName(what))
		c.a = alpha
		TeaArt.draw(self, &"petal", at, 0.95 * k, 0.3, c)


func _dots_ellipse(centre: Vector2, r: Vector2, from_a: float, to_a: float, n: int, dot_k: float, color: Color,
		xf_rot: float = 0.0) -> void:
	for i in n:
		var u := float(i) / float(maxi(n - 1, 1))
		var a := lerpf(from_a, to_a, u)
		var p := centre + Vector2(cos(a) * r.x, sin(a) * r.y).rotated(xf_rot)
		TeaArt.draw(self, &"dot", p, dot_k, 0.0, color)


func _draw_pot() -> void:
	var s := pot_scale()
	var foot := pot_foot()
	var rot := deg_to_rad(_tilt)
	var tw := TeaArt.teaware_colors(StringName(String(_teaware.get("teapot", "acorn_teapot"))))
	var body: Color = tw["body"]
	var cap: Color = tw["cap"]
	# the lid rests beside the pot while it is open
	TeaArt.draw(self, &"pot_cap", foot + Vector2(-POT_W * 0.44, -14.0) * s, 0.4 * s, -0.12, cap)
	# the soft contact shadow under the pot (a squashed dot)
	draw_set_transform(foot + Vector2(0.0, -6.0) * s, 0.0, Vector2(9.0 * s, 1.1 * s))
	draw_texture_rect_region(TeaArt.texture(), Rect2(-TeaArt.pivot(&"dot"), TeaArt.region(&"dot").size),
			TeaArt.region(&"dot"), Color(0.29, 0.23, 0.2, 0.12))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	TeaArt.draw(self, &"pot_body", foot, s, rot, body)
	# tea in the mouth
	var mouth := foot + (MOUTH * s).rotated(rot)
	TeaArt.draw(self, &"liquid", mouth, s, rot, _color)
	var petals := petals_in_pot()
	if not petals.is_empty() and not calm:
		var swirl := Color(1, 1, 1, 0.45)
		var a0 := deg_to_rad(_swirl)
		_dots_ellipse(mouth, MOUTH_R * s * 0.62, a0, a0 + 1.9, 9, 0.28 * s, swirl, rot)
		_dots_ellipse(mouth, MOUTH_R * s * 0.34, a0 + PI, a0 + PI + 1.6, 6, 0.22 * s, swirl, rot)
	var fade := 1.0
	if _simple_t >= 0.0:
		fade = 1.0 - clampf(_simple_t / 0.9, 0.0, 1.0)
	var shown := petals.size() - _hidden_pot
	for i in petals.size():
		if i >= shown:
			continue
		var c := TeaArt.flower_color(StringName(String(petals[i])))
		c.a = fade
		TeaArt.draw(self, &"petal", _float_pos(i), FLOAT_SCALE * s * (0.85 + 0.15 * fade),
				deg_to_rad(_swirl) + float(i) * 2.1, c)
	for d in drops_in_pot():
		TeaArt.draw(self, &"drop", _drop_float_pos(d) + Vector2(0.0, 14.0) * s, 0.42 * s, 0.0, Color(1, 1, 1, fade))
	# the spoon stands in the tea once there is a petal
	if not petals.is_empty() and not simple and _pour_t < 0.0:
		var sa := deg_to_rad(_swirl) * (0.0 if calm else 1.0)
		var bowl := mouth + Vector2(cos(sa) * MOUTH_R.x * 0.5, sin(sa) * MOUTH_R.y * 0.5).rotated(rot) * s
		TeaArt.draw(self, &"spoon", bowl, s * 0.95, 0.35 + 0.12 * cos(sa), Color.WHITE)
	# the stitched progress ring around the mouth (track, then progress)
	if not petals.is_empty() and not simple and _pour_t < 0.0:
		var track := UiTokens.sc_tinted(&"ink", 0.2)
		var prog := UiTokens.sc(&"primary")
		var done := clampf(_stir_shown / maxf(stir_target(), 1.0), 0.0, 1.0)
		var start := -PI * 0.5
		_dots_ellipse(mouth, RING_R * s, start, start + TAU, RING_DOTS, RING_DOT * s, track, rot)
		var n := roundi(RING_DOTS * done)
		if n > 0:
			_dots_ellipse(mouth, RING_R * s, start, start + TAU * done, maxi(n, 2), RING_DOT * 1.25 * s, prog, rot)
	# ready to pour: the handle glows softly
	if stir_done() and _pour_t < 0.0 and not simple:
		var k := 0.5 + 0.5 * sin(_time * TAU / 2.0)
		var hp := foot + (HANDLE * s).rotated(rot)
		TeaArt.draw(self, &"sparkle", hp + Vector2(-12.0, -40.0) * s, (0.7 + 0.25 * k) * s, _time * 0.4,
				Color(1, 1, 1, 0.65 + 0.35 * k))
		TeaArt.draw(self, &"sparkle", hp + Vector2(26.0, 30.0) * s, (0.45 + 0.2 * (1.0 - k)) * s, -_time * 0.5,
				Color(1, 1, 1, 0.5 + 0.4 * (1.0 - k)))
	if _pour_t >= 0.0:
		_draw_stream()


## The pour: a stream of tea arcs from the spout into the next free cup (or the leaf mould).
func _draw_stream() -> void:
	var dur := float(_cfg.get("pour_ms", 1200.0)) * UiTokens.MS
	var u := clampf(_pour_t / dur, 0.0, 1.0)
	if u < 0.12 or u > 0.92:
		return
	var s := pot_scale()
	var spout := pot_foot() + (SPOUT * s).rotated(deg_to_rad(_tilt))
	var cell := tray_rect(clampi(_pour_slot, 0, 5))
	var to := cell.get_center() + Vector2(0.0, -CUP * 0.12)
	var reach := clampf((u - 0.12) / 0.2, 0.0, 1.0)
	var tail := clampf((u - 0.72) / 0.2, 0.0, 1.0)
	var c := _color
	c.a = 0.92
	for i in STREAM_DOTS:
		var v := float(i) / float(STREAM_DOTS - 1)
		if v > reach or v < tail:
			continue
		var p := spout.lerp(to, v) + Vector2(0.0, -sin(PI * v) * 60.0 * s)
		TeaArt.draw(self, &"dot", p, 0.55 * s * (1.0 - 0.4 * v), 0.0, c)


func _draw_tray() -> void:
	var slots := int(TeaArt.tea_num("tray", "slots", 6))
	var cup_tw := TeaArt.teaware_colors(StringName(String(_teaware.get("cup", "walnut_cup"))))
	for i in slots:
		var r := tray_rect(i)
		var c := r.get_center()
		var filling := i == _pour_slot and (_pour_t >= 0.0 or _simple_t >= 0.0)
		if i >= _tray.size() and not filling:
			# a stitched coaster marks a free slot (cups rest here, warm forever)
			_dots_ellipse(c + Vector2(0.0, CUP * 0.18), Vector2(CUP * 0.36, CUP * 0.14), 0.0, TAU, 16, 0.2,
					UiTokens.sc_tinted(&"ink", 0.18))
			continue
		if i == selected_cup:
			_dots_ellipse(c + Vector2(0.0, 8.0), Vector2(CUP * 0.56, CUP * 0.5), 0.0, TAU, 22, 0.42,
					UiTokens.sc(&"primary"))
		var k := _press_scale("cup%d" % i)
		var foot := c + Vector2(0.0, CUP * 0.36)
		var treat := false
		var col := _color
		if i < _tray.size():
			var cup: Dictionary = _tray[i]
			treat = StringName(String(cup.get("kind", "tea"))) == TeaRules.KIND_TREAT
			col = TeaArt.recipe_color(StringName(String(cup.get("recipe", ""))), cup.get("petals", []))
		else:
			treat = drops_in_pot() >= 2
		var fill := 1.0
		if filling:
			var dur := float(_cfg.get("pour_ms", 1200.0)) * UiTokens.MS if _pour_t >= 0.0 \
					else float(_cfg.get("simple_brew_ms", 900.0)) * UiTokens.MS
			fill = clampf(((_pour_t if _pour_t >= 0.0 else _simple_t) / dur - 0.3) / 0.6, 0.0, 1.0)
		if treat:
			TeaArt.draw(self, &"mould", foot, 0.78 * k, 0.0)
			var tc := col
			tc.a = fill
			TeaArt.draw(self, &"treat", foot + Vector2(0.0, -10.0), 0.82 * k * (0.6 + 0.4 * fill), 0.0, tc)
		else:
			TeaArt.draw(self, &"cup", foot, 0.86 * k, 0.0, cup_tw["body"])
			var lc := col
			lc.a = fill
			TeaArt.draw(self, &"cup_tea", foot + Vector2(-1.0, -76.0) * 0.86 * k, 0.86 * k, 0.0, lc)


func _draw_jars() -> void:
	for i in JARS:
		var r := jar_rect(i)
		var k := _press_scale("jar%d" % i)
		var nudge := 0.0
		if _bob.has("jar%d" % i) and float(_bob["jar%d" % i]) < 0.0:
			nudge = sin(absf(float(_bob["jar%d" % i])) / BOB_S * TAU * 2.0) * 2.0 * DP
		var foot := Vector2(r.get_center().x + nudge, r.end.y - 30.0)
		if i == DROP_JAR:
			TeaArt.draw(self, &"drop", foot + Vector2(0.0, -14.0), 1.15 * k)
			continue
		var flower := jar_flowers[i]
		var n := int(_pantry.get(String(flower), 0))
		var cap := int((ContentRegistry.content.petals_by_flower.get(flower, {}) as Dictionary).get("pantry_cap", 24))
		if n >= cap:
			k *= 1.0 + 0.025 * sin(_time * TAU / 2.4)
		var s := JAR_ART_SCALE * k
		TeaArt.draw(self, &"jar_back", foot, s)
		var col := TeaArt.flower_color(flower)
		var pile := mini(n, JAR_PILE_MAX)
		for p in pile:
			var j := TeaArt.scatter(p, i)
			var px := (j.x - 0.5) * 70.0 * s
			var py := -26.0 * s - float(p / 2) * 20.0 * s - j.y * 8.0 * s
			TeaArt.draw(self, &"petal", foot + Vector2(px, py), JAR_PETAL_SCALE * s * 1.3, (j.x - 0.5) * 2.2, col)
		TeaArt.draw(self, &"jar_front", foot, s)
		# the jar's tag: a felt petal of its flower on the cork band (a jar never gathered is just glass)
		TeaArt.draw(self, &"petal", foot + Vector2(0.0, -150.0 * s), 0.5 * s, 0.0, col)


func _draw_flights() -> void:
	for f: Dictionary in _flights:
		var u := clampf(float(f["t"]) / float(f["dur"]), 0.0, 1.0)
		var e := 1.0 - pow(1.0 - u, 3.0)
		var from: Vector2 = f["from"]
		var to: Vector2 = f["to"]
		var p := from.lerp(to, e)
		var alpha := 1.0
		if calm:
			p = to
			alpha = e
		else:
			p += Vector2(0.0, -sin(PI * e) * from.distance_to(to) * FLIGHT_ARC)
		_draw_item(String(f["what"]), p, 1.0 - 0.15 * e, alpha)
