class_name WishView
extends Node
## Active F1 Wishes in the hollow (ACTIVE_WISHES §5, §7, §9; GDD §14.11 b FE-W): the creature
## layer's child that shows each open wish as a WishBubble over its friend and turns the sim's wish
## events into delight. It never decides anything: Game.wishes() and the Game wish signals are the
## truth, this view only mirrors them.
##
##  * Bubbles: one per OPEN wish whose friend is here (<= 2), following the head anchor and the pan;
##    45 % with a "z" while the friend naps, 45 % in Active F3 edit mode, hidden while the friend is
##    cast in a staged scene; S26 + CAPTION_WISH when one appears live.
##  * Reading: a tap on a friend holding a wish shows "{name} · {wish}" and the hint for
##    caption_chip_s (the tap still chirps and still counts for play_taps).
##  * Fulfilling rides existing taps only: the layer's mossling taps report
##    Game.world_action(&"tap_creature"); the brook's [signal BrookLayer.tapped] reports
##    &"stream_tap" and the willow branch (PropsLayer prop_tapped ring_chime) &"ring_chime" (both are
##    release-with-act signals, so a pan never grants). Beds and décor report from their own layers.
##  * Grant (<= 1 s, never blocks input): the bubble pops into 5 petals of the gift flower's colour,
##    the friend plays its granted_pose (walking to the bed, the piece or the bank first when the
##    wish is about one), S27 120 ms after the action's cue, then the WISH_GRANTED toast unless a
##    heart-up toast takes the moment (§6.1). play_taps progress: a small hop aside and a look back.
##  * Busy report (Game.report_wish_busy): napping, petted, entering or leaving friends start no wish.
##
## QA user arg --qa-wish=<mode>[:<species>][@<ms>] (with --fixture=active_mid; QA_AT_S after the world
## is ready): caption (tap the friend: the wish caption), grant (fulfil its wish through the real
## action and freeze <ms> later, default 320: petals mid-pop and the pose), nap (the friend naps: 45 %
## + "z"), edit (Active F3 edit mode: every bubble at 45 %), progress (one play_taps tap: the hop).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const ARG_QA := "--qa-wish="
const QA_AT_S := 1.0
const QA_FREEZE_MS := 320.0
const MS := 0.001
## S27 follows the fulfilling action's own cue by this much so they never mask (ACTIVE_WISHES §9).
const GRANTED_CUE_DELAY_S := 0.12
const CUE_APPEAR := &"S26"
const CUE_GRANTED := &"S27"
## Until the manifest has S26/S27 (Sound Designer, GDD §14.8): S27's first layer is the species'
## chirp (S13) and its haptic DOUBLE in Full; S26 has no haptic (a wish never buzzes the hand).
const CUE_FALLBACK_GRANTED := &"S13"
const FALLBACK_GRANTED_HAPTIC := {"subtle": null, "full": "DOUBLE"}
const CAPTION_APPEAR := &"CAPTION_WISH"
const CAPTION_GRANTED := &"CAPTION_WISH_GRANTED"
## Side choice (design px): the cloud's radius (44 dp / 2), the frame margin it keeps, the cost of
## leaving the frame and the margin before it changes sides.
const BUBBLE_R_PX := 66.0
const EDGE_PX := 24.0
const OFFSCREEN_COST := 1000.0
const SIDE_HYSTERESIS := 40.0
## play_taps: the friend hops ~40 dp aside within the tend zone (ACTIVE_WISHES §5).
const TAG_HOP_DP := 40.0
const PX_PER_DP := 3.0
## A walk to a wish's place (bed, piece, bank) is held this long before the brain takes over again.
const VISIT_HOLD_S := 12.0
## The decor_near friend stands this far (design px) beside the piece, not on it.
const BESIDE_PX := 70.0
const TOAST_S := 3.0

## The first-ever wish tip shows once per run (and only while nothing was granted yet).
static var _tip_shown: bool = false

## The CreatureLayer this view serves (mossling lookup, walks, the frame).
var layer: CreatureLayer

var _shown: Dictionary = {}            # species -> WishBubble
var _busy: PackedStringArray = PackedStringArray()
var _edit: bool = false
var _hearts_now: Dictionary = {}       # species -> process frame of its last live heart-up
var _caption_s: float = 2.5
var _qa: PackedStringArray = PackedStringArray()
var _qa_ms: float = QA_FREEZE_MS
var _qa_t: float = -1.0
var _qa_done: bool = false
var _wired_world: bool = false


func _ready() -> void:
	var pres: Dictionary = ContentRegistry.content.wishes_doc.get("presentation", {})
	_caption_s = float(pres.get("caption_chip_s", 2.5))
	Game.world_ready.connect(func(_r: Array) -> void: sync())
	Game.wish_opened.connect(_on_opened)
	Game.wish_shown.connect(func(_sp: StringName, _w: StringName) -> void: sync(true))
	Game.wish_held.connect(func(_sp: StringName, _w: StringName) -> void: sync())
	Game.wish_granted.connect(_on_granted)
	Game.heart_up.connect(_on_heart_up)
	Game.sim_event.connect(_on_sim_event)
	Game.decor_edit_entered.connect(func() -> void: _edit = true)
	Game.decor_edit_exited.connect(func() -> void: _edit = false)
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(ARG_QA):
			var spec := a.trim_prefix(ARG_QA)
			if spec.contains("@"):
				_qa_ms = spec.get_slice("@", 1).to_float()
				spec = spec.get_slice("@", 0)
			_qa = spec.split(":")
	_wire_world.call_deferred()
	if Game.is_ready:
		sync.call_deferred()


func _exit_tree() -> void:
	WishIcons.release()


## The brook and the willow-branch chime report their release taps as wish actions.
func _wire_world() -> void:
	if _wired_world:
		return
	_wired_world = true
	if BrookLayer.current != null and not BrookLayer.current.tapped.is_connected(_on_stream_tapped):
		BrookLayer.current.tapped.connect(_on_stream_tapped)
	var props := layer.get_node_or_null(^"../../Props/PropsLayer") if layer != null else null
	if props != null and props.has_signal(&"prop_tapped"):
		props.connect(&"prop_tapped", _on_prop_tapped)


func _on_stream_tapped(design_pos: Vector2) -> void:
	if Game.is_ready:
		Game.world_action(&"stream_tap", {"pos": design_pos})


func _on_prop_tapped(_prop: StringName, action: StringName, _pos: Vector2) -> void:
	if action == &"ring_chime" and Game.is_ready:
		Game.world_action(&"ring_chime")


# ================================================================= bubbles

## Mirrors Game.wishes(): a bubble for every open wish whose friend is in the hollow, none for the
## rest. [param live_appear]: a bubble that appears now plays S26 (a wish_shown slot refill).
func sync(live_appear: bool = false) -> void:
	if not Game.is_ready or Game.sim == null or layer == null:
		return
	var want := visible_wishes()
	for sp: StringName in _shown.keys():
		var b: WishBubble = _shown[sp]
		if not want.has(sp) or not is_instance_valid(b) or b.is_leaving():
			if is_instance_valid(b) and not b.is_leaving():
				b.dismiss()
			_shown.erase(sp)
	for sp: StringName in want:
		var v: Dictionary = want[sp]
		var m := layer.mossling(sp)
		if m == null or m.leaving:
			continue
		var b: WishBubble = _shown.get(sp)
		if b != null and is_instance_valid(b) and not b.is_leaving():
			if b.icon != StringName(v["icon"]):
				b.icon = StringName(v["icon"])
				b.queue_redraw()
			continue
		_shown[sp] = _attach(m, StringName(v["icon"]), not live_appear)
		if live_appear:
			_cue_appear(m)


## species -> wish view of the wishes that show a bubble now (open and present, at most 2).
static func visible_wishes() -> Dictionary:
	var out := {}
	for w: Dictionary in Game.wishes():
		if StringName(w["state"]) == &"open" and bool(w["present"]):
			out[StringName(w["species"])] = w
	return out


func bubble_of(species: StringName) -> WishBubble:
	var b: WishBubble = _shown.get(species)
	return b if b != null and is_instance_valid(b) and not b.is_leaving() else null


func bubble_count() -> int:
	var n := 0
	for sp: StringName in _shown:
		if bubble_of(sp) != null:
			n += 1
	return n


func _attach(m: Mossling, icon: StringName, instant: bool) -> WishBubble:
	var b := WishBubble.new()
	b.name = "WishBubble"
	m.add_child(b)
	b.setup(icon, m.seed01, instant)
	_place(m, b)
	return b


func _place(m: Mossling, b: WishBubble) -> void:
	var pres: Dictionary = ContentRegistry.content.wishes_doc.get("presentation", {})
	var off_a: Array = pres.get("bubble_offset_dp", [18, -56])
	var off := Vector2(float(off_a[0]), float(off_a[1])) * PX_PER_DP
	var mirror := choose_side(m, b, off)
	if mirror:
		off.x = -off.x
	b.mirrored = mirror
	b.sleepy = m.asleep
	b.waiting = m.asleep or _edit
	b.tucked = not m.name_tag_text().is_empty()
	b.visible = not _in_scene(m.species_id)
	b.place(m.head_anchor() + off)


## The bubble's side: right of the head by default, left near the right edge of the frame or when
## the right side would cover another friend or another bubble clearly more than the left (with a
## margin, so a bubble never flickers between sides while friends move).
func choose_side(m: Mossling, b: WishBubble, off: Vector2) -> bool:
	var head := m.position + m.head_anchor()
	var right := head + off
	var left := head + Vector2(-off.x, off.y)
	var r := BUBBLE_R_PX
	var cost_r := _cover(m, right, r) + (OFFSCREEN_COST if right.x + r > layer.frame_size().x - EDGE_PX else 0.0)
	var cost_l := _cover(m, left, r) + (OFFSCREEN_COST if left.x - r < EDGE_PX else 0.0)
	if b.mirrored:
		return cost_l <= cost_r + SIDE_HYSTERESIS
	return cost_l + SIDE_HYSTERESIS < cost_r


## How much a bubble at [param c] (layer px) would cover other friends' bodies and other bubbles.
func _cover(owner: Mossling, c: Vector2, r: float) -> float:
	var cost := 0.0
	for o: Mossling in layer.visitors():
		if o == owner:
			continue
		var hc := o.hit_circle()
		if hc.z > 0.0:
			cost += maxf(0.0, r + hc.z * 0.8 - c.distance_to(Vector2(hc.x, hc.y)))
	for sp: StringName in _shown:
		var ob := bubble_of(sp)
		if ob != null and sp != owner.species_id:
			var oc := (ob.get_parent() as Node2D).position + ob.position
			cost += maxf(0.0, r * 2.0 - c.distance_to(oc))
	return cost


func _process(delta: float) -> void:
	if layer == null:
		return
	for sp: StringName in _shown:
		var b := bubble_of(sp)
		var m := layer.mossling(sp)
		if b != null and m != null:
			_place(m, b)
	_report_busy()
	if not _qa.is_empty():
		_qa_tick(delta)


func _report_busy() -> void:
	var busy := PackedStringArray()
	for m: Mossling in layer.visitors():
		if m.is_wish_busy():
			busy.append(String(m.species_id))
	if busy != _busy:
		_busy = busy
		Game.report_wish_busy(busy)


func _in_scene(sp: StringName) -> bool:
	var scene := Game.pending_scene() if Game.is_ready else {}
	return not scene.is_empty() and (scene.get("cast", []) as Array).has(String(sp))


# ================================================================= events

func _on_opened(species: StringName, wish: StringName, visible: bool) -> void:
	if visible:
		sync(true)
	var tuning: Dictionary = ContentRegistry.content.wishes_doc.get("tuning", {})
	var first_wish: Dictionary = tuning.get("first_wish", {})
	var first := StringName(String(first_wish.get("wish", "cuddle")))
	if visible and not _tip_shown and wish == first and Game.sim.state.wishes_granted == 0 and species != &"":
		_tip_shown = true
		_toast(tr("WISH_TIP_FIRST"))


func _on_heart_up(species: StringName, _hearts: int, offline: bool) -> void:
	if not offline:
		_hearts_now[species] = Engine.get_process_frames()


func _on_sim_event(ev: Dictionary) -> void:
	if bool(ev.get("catch_up", false)):
		return
	if StringName(ev["type"]) == WorldSim.EV_WISH_PROGRESS:
		var m := layer.mossling(StringName(ev["species"])) if layer != null else null
		if m != null and not m.asleep:
			layer.hop_aside(m, TAG_HOP_DP * PX_PER_DP)
	elif StringName(ev["type"]) == WorldSim.EV_TEA_OFFERED and String(ev.get("wish_granted", "")) == "":
		# integration: a cup that grants no wish still gets its sip once the cup lands (FE-T's arc)
		var sp := StringName(ev["species"])
		var arc := float((ContentRegistry.content.tea.get("offering", {}) as Dictionary).get("cup_arc_ms", 320.0))
		get_tree().create_timer(arc * 0.001).timeout.connect(func() -> void:
			var m2 := layer.mossling(sp) if is_instance_valid(layer) else null
			if m2 != null:
				m2.play_pose(&"sip_tea"))


## A tap landed on [param m] (the layer calls this from its tap handler): report it for play_taps
## and, if the friend holds a wish, show "{name} · {wish}" with the hint. Returns true when the wish
## caption replaced the plain name tag.
func on_tapped(m: Mossling) -> bool:
	if not Game.is_ready:
		return false
	var w := Game.wish_of(m.species_id)
	var shows := not w.is_empty() and StringName(w["state"]) == &"open"
	if shows:
		var c := ContentRegistry.content
		var names := func(sp: StringName) -> String: return Game.display_name(sp)
		var wish := StringName(w["wish"])
		m.show_name(WishText.tag(c, wish, m.species_id, names), WishText.hint(c, wish, m.species_id, names),
			_caption_s)
	Game.world_action(&"tap_creature", {"species": m.species_id})
	return shows


func _on_granted(species: StringName, wish: StringName, affection: int, gift_flower: StringName,
		_first_stamp: bool, on_arrival: bool) -> void:
	var m := layer.mossling(species) if layer != null else null
	var b: WishBubble = _shown.get(species)
	_shown.erase(species)
	if b != null and is_instance_valid(b):
		b.pop(petal_tint(gift_flower))
	var def: Dictionary = ContentRegistry.content.wishes_by_id.get(wish, {})
	var pose := StringName(String(def.get("granted_pose", "delight_snuggle")))
	if m != null:
		_delight(m, wish, pose)
		var cue_m := m
		get_tree().create_timer(GRANTED_CUE_DELAY_S).timeout.connect(func() -> void:
			if is_instance_valid(cue_m):
				_cue_granted(cue_m))
	# one toast per grant; a heart-up from this grant takes the moment (§6.1), checked a frame later
	var names := func(sp: StringName) -> String: return Game.display_name(sp)
	var args := WishText.args(ContentRegistry.content, species, names)
	_toast_grant.call_deferred(species, affection, gift_flower, on_arrival, args, Engine.get_process_frames())
	sync()


func _toast_grant(species: StringName, affection: int, gift_flower: StringName, on_arrival: bool,
		args: Dictionary, frame: int) -> void:
	if affection > 0 and int(_hearts_now.get(species, -1)) >= frame:
		return
	_toast(grant_toast_text(species, gift_flower, on_arrival, args))


## The granted toast (the one-line HUD toast pill): "{name} is delighted.", or the gift line when a
## petal came with it (WISH_GIFT_PETAL names the friend too), or the arrival line. WISH_GRANTED_TITLE
## is left for a two-line toast (OverlayHost has one line today).
static func grant_toast_text(_species: StringName, gift_flower: StringName, on_arrival: bool,
		args: Dictionary) -> String:
	if on_arrival:
		return I18n.fmt(&"WISH_GRANTED_ARRIVAL", args)
	var body := I18n.fmt(&"WISH_GRANTED_BODY", args)
	if gift_flower != &"":
		var f: Dictionary = ContentRegistry.content.flowers_by_id.get(gift_flower, {})
		var a := args.duplicate()
		a["flower"] = TranslationServer.translate(String(f.get("name_key", ""))).to_lower()
		body = I18n.fmt(&"WISH_GIFT_PETAL", a)
	return body


## The friend's delight: in place, or after a short walk to what the wish was about.
func _delight(m: Mossling, wish: StringName, pose: StringName) -> void:
	var tg: Dictionary = ContentRegistry.content.wish_targets.get(wish, {})
	var kind := StringName(tg.get("kind", ""))
	var arg := String(tg.get("arg", ""))
	var to := Vector2.INF
	var then := Callable()
	match kind:
		&"bed_invite":
			to = _bed_point(m, StringName(arg))
			var nap := pose == &"delight_nap"
			then = func() -> void:
				m.play_pose(pose)
				m.perform(Mossling.B_NAP if nap else Mossling.B_NIBBLE, &"", {"lean_dir": 1.0})
			var names := func(sp: StringName) -> String: return Game.display_name(sp)
			m.show_name(I18n.fmt(&"WISH_INVITE", WishText.args(ContentRegistry.content, m.species_id, names)))
		&"decor_near":
			to = _piece_point(m, StringName(arg))
		&"stream_tap":
			to = layer.bank_point(m.feet().x)
			then = func() -> void:
				m.play_pose(pose)
				if BrookLayer.current != null:
					BrookLayer.current.add_ripple(Vector2(m.feet().x, m.feet().y + 60.0), 1.0)
	if to == Vector2.INF or m.asleep or m.feet().distance_to(to) < 12.0:
		m.play_pose(pose)
		if then.is_valid() and kind == &"bed_invite":
			m.perform(Mossling.B_NAP if pose == &"delight_nap" else Mossling.B_NIBBLE, &"", {"lean_dir": 1.0})
		return
	# a little hello right away (the grant answers within 100 ms), then the walk and the pose there
	m.sparkle(4)
	layer.walk_for_wish(m, to, VISIT_HOLD_S, then if then.is_valid() else func() -> void: m.play_pose(pose))


func _bed_point(m: Mossling, flower: StringName) -> Vector2:
	var content := ContentRegistry.content
	var best := Vector2.INF
	for bed: Dictionary in content.beds:
		var has := false
		for st: Dictionary in Game.sim.state.stems:
			if String(st["bed"]) == String(bed["id"]) and StringName(st["flower"]) == flower \
					and int(st["stage"]) >= WorldSim.STAGE_BLOOM:
				has = true
				break
		if not has:
			continue
		for p: Array in bed.get("nibble_points", []):
			var q := Vector2(float(p[0]), float(p[1])) * layer.frame_size()
			if best == Vector2.INF or q.distance_to(m.feet()) < best.distance_to(m.feet()):
				best = q
	return best


func _piece_point(m: Mossling, set_id: StringName) -> Vector2:
	var best := Vector2.INF
	for p: Dictionary in Game.decor_layout():
		if StringName(String(p.get("set", ""))) != set_id or bool(p.get("stored", false)):
			continue
		var q := Vector2(float(p["x"]), float(p["y"])) * layer.frame_size()
		if best == Vector2.INF or q.distance_to(m.feet()) < best.distance_to(m.feet()):
			best = q
	if best == Vector2.INF:
		return best
	var side := -1.0 if best.x > m.feet().x else 1.0
	return best + Vector2(side * BESIDE_PX, 6.0)


## The gift petal's colour (palettes flora petal lit), cream when no gift came.
static func petal_tint(flower: StringName) -> Color:
	if flower == &"":
		return UiTokens.color(&"surface_hi")
	var fl: Dictionary = (ContentRegistry.palettes().get("flora", {}) as Dictionary).get("flowers", {})
	for k: String in fl:
		var e: Dictionary = fl[k]
		if StringName(String(e.get("flower_id", ""))) == flower:
			return Color.html(String((e.get("petal", ["#FFFFFF"]) as Array)[0]))
	return UiTokens.color(&"surface_hi")


# ================================================================= audio, toasts

func _cue_appear(m: Mossling) -> void:
	var pos := m.get_global_transform_with_canvas() * m.head_anchor()
	if _has_cue(CUE_APPEAR):
		AudioDirector.play_cue(CUE_APPEAR, {"voice_step": m.voice_step, "position": pos})
	else:
		AudioDirector.cue_played.emit(CUE_APPEAR, CAPTION_APPEAR, pos)


func _cue_granted(m: Mossling) -> void:
	var pos := m.get_global_transform_with_canvas() * m.head_anchor()
	if _has_cue(CUE_GRANTED):
		AudioDirector.play_cue(CUE_GRANTED, {"voice_step": m.voice_step, "position": pos})
		return
	AudioDirector.play_cue(CUE_FALLBACK_GRANTED, {"voice_step": m.voice_step, "position": pos, "haptic": false})
	Haptics.play_for_cue(FALLBACK_GRANTED_HAPTIC, CUE_GRANTED)
	AudioDirector.cue_played.emit(CUE_GRANTED, CAPTION_GRANTED, pos)


static func _has_cue(id: StringName) -> bool:
	return (AudioDirector.manifest.get("cues", {}) as Dictionary).has(String(id))


func _toast(text: String) -> void:
	var hud := _hud()
	if hud != null and text != "":
		hud.overlays.show_toast(text, TOAST_S)


func _hud() -> HudController:
	var main := layer.owner if layer != null else null
	if main == null:
		return null
	return main.get_node_or_null(^"HUD/HudRoot") as HudController


# ================================================================= Album "Say hello"

## Glides the camera to [param species] and the friend waves (ACTIVE_WISHES §7.3 WISH_LIST_VISIT).
func visit(species: StringName) -> bool:
	var m := layer.mossling(species) if layer != null else null
	if m == null:
		return false
	var pan := WorldPan.current
	if pan != null and is_instance_valid(pan):
		var vp := layer.get_viewport()
		var screen := m.get_global_transform_with_canvas() * Vector2.ZERO
		var centre := vp.get_visible_rect().size * 0.5
		var k := maxf(vp.get_canvas_transform().get_scale().x, 1e-3)
		pan.motion_started.emit()
		pan.body.glide_to(pan.offset() + (screen - centre) / k)
	m.greet()
	return true


# ================================================================= QA

func _qa_tick(delta: float) -> void:
	if _qa_done or not Game.is_ready:
		return
	if _qa_t < 0.0:
		_qa_t = 0.0
	_qa_t += delta
	if _qa_t < QA_AT_S:
		return
	_qa_done = true
	var mode := _qa[0]
	var sp := StringName(_qa[1]) if _qa.size() > 1 else _first_holder()
	var m := layer.mossling(sp)
	match mode:
		"caption":
			if m != null:
				on_tapped(m)
				m.touch_down(m.feet() - Vector2(0.0, 60.0))
				m.cancel_touch()
		"grant":
			qa_fulfil(sp)
			get_tree().create_timer(maxf(_qa_ms, 0.0) * MS).timeout.connect(_qa_freeze.bind(sp))
		"nap":
			if m != null:
				m.debug_pose(&"asleep")
		"edit":
			_edit = true
		"progress":
			if m != null:
				on_tapped(m)
		_:
			push_warning("--qa-wish=<caption|grant|nap|edit|progress>[:<species>][@<ms>]")


func _first_holder() -> StringName:
	var v := visible_wishes()
	return StringName(v.keys()[0]) if not v.is_empty() else &""


func _qa_freeze(sp: StringName) -> void:
	var m := layer.mossling(sp)
	if m != null:
		m.freeze(true)
		for c: Node in m.get_children():
			if c is WishBubble:
				(c as WishBubble).freeze(true)


## QA / tests: fulfils [param species]'s open wish through the action it asks for (the real Game
## API: a pet, a bed tap, a cup from the tray, a stream tap ...). Returns the species granted.
func qa_fulfil(species: StringName) -> Array[StringName]:
	var w := Game.wish_of(species)
	var none: Array[StringName] = []
	var me: Array[StringName] = [species]
	if w.is_empty():
		return none
	var kind := StringName(w["kind"])
	var arg := String(w["arg"])
	match kind:
		&"pet":
			Game.pet(species)
			return me
		&"play_taps":
			var out: Array[StringName] = []
			for i in maxi(1, int(w["taps_needed"]) - int(w["taps"])):
				out = Game.world_action(&"tap_creature", {"species": species})
			return out
		&"bed_invite":
			for bed: Dictionary in ContentRegistry.content.beds:
				var got := Game.world_action(&"bed_tap", {"bed": StringName(String(bed["id"]))})
				if got.has(species):
					return got
		&"chime_tap":
			return Game.world_action(&"ring_chime")
		&"decor_tap":
			return Game.world_action(&"decor_tap", {"set": StringName(arg)})
		&"stream_tap":
			return Game.world_action(&"stream_tap", {"pos": Vector2.ZERO})
		&"boat":
			Game.float_boat()
			return me
		_:
			# the first tray cup that satisfies the wish (a mismatched cup is never offered here)
			var tray := Game.tray()
			for i in tray.size():
				var cup: Dictionary = tray[i]
				if Game.sim.active.tea.satisfies(Game.sim, StringName(w["wish"]), species,
						StringName(String(cup.get("recipe", ""))), cup.get("petals", [])):
					var r := Game.offer_cup(i, species)
					return me if String(r.get("wish_granted", "")) != "" else none
	return none
