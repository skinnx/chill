class_name PlotsLayer
extends Node2D
## The five flower beds (scenes/garden/plots_layer.tscn at World/Ground/Play/Plots; GDD §2.4,
## §3.1, Art Bible §4.10, §6.1-6.3). One MeshInstance2D per bed, rebuilt by [FloraBuilder] only
## when a stem changes (stage, unfurl, grow step, the slow in-stage growth every few seconds).
##
##  * Binds to Game.sim: planted stems at their slots, stage by the sim, growth time-lerped inside
##    the sprout and bud stages so a returning player sees growth (§6.2).
##  * A stem that blooms while the player watches becomes a READY bud (swells 1.04, a warm halo
##    breathing at k 76); tapping its bed unfurls every ready bud there (600 ms, 30 ms stagger,
##    sparkles, S04); un-tapped ready buds open by themselves after 20 s with a 2.4 s unfurl.
##  * Watched growth steps stretch the stem (spring move) and pop the new parts in (spring pop).
##  * Planting: a seed arcs in from the Garden button (320 ms), a soil puff, S05.
##  * Moonbloom opens at dusk/night in a wave (each stem 0-20 s late) and closes over 2 s at dawn.
##  * Touch (GDD §8.2-8.3): touch-down on a bed = squash 0.94 + tint + S01 (+ TICK haptic) in the
##    same frame; the action fires on release inside the bed: ready buds unfurl, else the stems
##    sway (S18); long-press 450 ms = [signal bed_card_requested]. The tutorial seed (GDD §3.4)
##    glows on its bed until tapped (Game.tap_seed), with a hint ring from 6.5 s every 3 s.
##  * Choose-a-bed mode (GDD §2.4 rule 1): the UI sets [member choose_mode]; beds with room glow
##    and a tap emits [signal bed_chosen].
##
## QA user args: --fixture=<garden_mid|night_lanterns|garden_full> (GardenFixture) plants a
## deterministic mid-game garden before the world layers bind; --qa-ready=<bed_id> turns that bed's
## bloomed stems into ready buds (glow, swell); --qa-unfurl=<s> taps every ready bud that many
## seconds after the layer is ready (e.g. 2.7 with the default 90 frames = a still 0.3 s into the
## 600 ms unfurl; with tools/qa/capture.sh video, the whole unfurl).
## Touch strip (Director R3 #1): --qa-garden=<kind>:<ms> touches a bed QA_TOUCH_AT_S after the world
## is ready and FREEZES the garden <ms> later (needs the default --frames=90; ms <= 1500), so a
## still proves the feedback. Kinds here: bed (touch-down held: squash 0.94 + tint + touch ring),
## unfurl (the bed's blooms become ready buds, then a tap: <ms> after the release the 600 ms
## unfurl with its sparkles), ready (ready buds glowing and swelling, no touch). The bed is
## --qa-ready=<bed_id> (default QA_BED). DecorLayer handles the décor kinds (lantern, pinwheel,
## chime, place).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## Long-press on a bed (GDD §3.1: the bed card, "Blooms in about 40 min").
signal bed_card_requested(bed_id: StringName)
## A tap on a bed with room while [member choose_mode] is on.
signal bed_chosen(bed_id: StringName)

const SHADER_PATH := "res://shaders/flora/flora_bed.gdshader"
const CUE_TOUCH := &"S01"
const CUE_UNFURL := &"S04"
const CUE_PLANT := &"S05"
const CUE_RUSTLE := &"S18"
## Art Bible §2.4 depth scale: s(y) = clamp(0.62 + 0.38 (y - 760) / 740, 0.62, 1).
const DEPTH := Vector3(0.62, 760.0, 740.0)
## GDD §8.4: world hit areas extend 4 dp downward.
const HIT_EXTEND_DP := 4.0
## GDD §8.2: long-press 450 ms; a move beyond the drag threshold cancels.
const LONG_PRESS_S := 0.45
const DRAG_CANCEL_PX := 24.0
## Slow in-stage growth refresh: stages last minutes to hours, so a static rebuild of each growing
## bed every 30 s shows the growth without a per-frame cost.
const GROWTH_REFRESH_S := 30.0
## Moonbloom wave: each stem opens up to this late after dusk begins (Art Bible §6.2).
const MOON_WAVE_S := 20.0
const MOON_CLOSE_S := 2.0
const MOON_OPEN_RATE := 0.25
const OPENS_DUSK_NIGHT := "dusk_night"
const PHASES_OPEN: Array[StringName] = [&"dusk", &"night"]
## Bed tap sway: impulse px at the tip, decay s, frequency Hz (stems sway, GDD §3.1).
const TAP_SWAY_PX := 9.0
const TAP_SWAY_DECAY_S := 0.55
const TAP_SWAY_HZ := 2.2
## Ready-bud and tutorial-seed halos (Art Bible §6.2: r0 14 px, alpha 0.25).
const HALO_QUAD_K := 3.2
## QA r2: the ready-bud glow was invisible at full scale. The halo is 1.6x the bud, alpha 0.25 x 1.6
## = 0.4, and pulses every 2 s (k 300) instead of breathing with the slow k 76 loop.
const READY_HALO_SCALE := 1.6
const READY_HALO_ALPHA_K := 1.6
const READY_PULSE_K := 300.0
## Round 4 (QA r3 c7): the ready glow no longer vanishes on the tap; it flares and widens with the
## opening petals (peak x UNFURL_FLARE alpha at mid-unfurl, UNFURL_GROW x size), then fades out.
const UNFURL_FLARE := 0.7
const UNFURL_GROW := 0.45
## Touch ring alpha on the busy beds (motion_tokens ui.ring 0.35 is too faint over flowers).
const RING_ALPHA := 0.6
## --qa-ready / --qa-garden: at most this many stems of the bed become ready buds (in play a bed
## rarely has more; a dozen stacked halos read as one white blob).
const QA_READY_MAX := 3
## Garden dock button (Art Bible §2.6 dock centres x 405, pill y 1541-1781): where seeds come from.
const SEED_FROM := Vector2(405.0, 1661.0)
const SEED_ARC_LIFT := 160.0
const SOIL_PUFF_DOTS := 4
## The tutorial seed and its mound (x depth scale).
const SEED_SCALE := 2.8
## The tutorial seed glows brighter than a ready bud: it is the only thing asking for a tap.
const SEED_GLOW_K := 2.2
const SEED_MOUND_SCALE := 0.62
const SOIL_PUFF_PX := 22.0
## The node sorts against creatures at the bed centre (creatures at the nibble points stand in front).
const SORT_OFFSET_Y := 0.0
const ARG_QA_READY := "--qa-ready="
const ARG_QA_UNFURL := "--qa-unfurl="
const ARG_QA_GARDEN := "--qa-garden="
const QA_BED := &"bed_2"
## Touch strip timeline: touch this long after the world is ready; a tap releases after QA_TAP_S.
const QA_TOUCH_AT_S := 1.2
const QA_TAP_S := 0.08
## Touch rings on beds lie on the ground (flattened ellipse).
const RING_SQUASH := 0.55

static var current: PlotsLayer = null

## UI: choose-a-bed mode (beds with room glow; a tap emits bed_chosen).
var choose_mode: bool = false:
	set(v):
		choose_mode = v
		_refresh_choose_glow()

var _content: GameContent
var _builder: FloraBuilder
var _mat: ShaderMaterial
var _atlas: Texture2D
var _beds: Dictionary = {}        # bed id -> BedView
var _views: Dictionary = {}       # stem index -> StemView
var _flora_tokens: Dictionary = {}
var _dp: float = 3.0
var _growth_t: float = 0.0
var _phase: StringName = &""
var _press_bed: StringName = &""
var _press_pos := Vector2.ZERO
var _press_t: float = 0.0
var _press_long_sent: bool = false
var _seed: SeedHint
var _bezier_decel: CubicBezier
var _seed_arc_s: float = 0.32
var _puff_s: float = 0.12
var _ready_cfg: Dictionary = {}
var _grow_cfg: Dictionary = {}
var _unfurl_total_s: float = 0.6
var _bloom_tips: Dictionary = {}   # stem index -> design px of an open flower head
var _butterflies: Butterflies
var _qa_ready: StringName = &""
var _qa_unfurl_s: float = -1.0
var _qa_kind: String = ""
var _qa_ms: float = 0.0
var _qa_t: float = -1.0
var _qa_step: int = 0
var _qa_frozen: bool = false
var _qa_ring: TouchRing


class BedView:
	extends RefCounted
	var id: StringName
	var node: Node2D
	var mesh: MeshInstance2D
	## Stems mid-animation (unfurl, grow step, planting, moonbloom open/close) are drawn by a second
	## small mesh rebuilt every frame, so a 16-stem bed is never rebuilt per frame (its static mesh
	## changes only when a stem starts or stops animating, on events and on the slow refresh).
	var anim_mesh: MeshInstance2D
	var anim: Array[int] = []
	var centre := Vector2.ZERO
	var hit := Rect2()
	var dirty: bool = true
	var growing: bool = false
	var press: Spring
	var tint: float = 0.0
	var sway_t: float = -1.0
	var halos: Dictionary = {}    # stem index -> HaloSprite
	var choose_halo: HaloSprite


class StemView:
	extends RefCounted
	var index: int
	var bed: StringName
	var ready_s: float = -1.0       # seconds the bud has been ready (>= 0 = ready)
	var unfurl_s: float = -1.0
	var unfurl_rate: float = 1.0
	var unfurl_delay: float = 0.0
	var stretch: Spring
	var pop: Spring
	var plant_s: float = -1.0       # seconds since the planting arc began
	var open: float = 1.0           # moonbloom openness
	var open_target: float = 1.0
	var open_delay: float = 0.0


## The glowing tutorial seed and its hint ring (GDD §3.4).
class SeedHint:
	extends Node2D
	var halo: HaloSprite
	var t: float = 0.0
	var ring_after_s: float = 6.5
	var ring_period_s: float = 3.0
	var ring_expand_s: float = 1.2
	var ring_radius: float = 108.0
	var ring_alpha: float = 0.8
	var ring_width: float = 6.0
	var ring_color := Color.WHITE
	var breathe_hz: float = 0.2066
	var base_alpha: float = 0.3

	func _process(delta: float) -> void:
		t += delta
		if halo != null:
			var c: Color = halo.get_instance_shader_parameter(&"i_color")
			c.a = base_alpha * (0.65 + 0.35 * sin(TAU * breathe_hz * t))
			halo.set_instance_shader_parameter(&"i_color", c)
		if t >= ring_after_s:
			queue_redraw()

	func _draw() -> void:
		if t < ring_after_s:
			return
		var u := fposmod(t - ring_after_s, ring_period_s) / ring_expand_s
		if u >= 1.0:
			return
		var e := 1.0 - pow(1.0 - u, 3.0)
		var c := ring_color
		c.a = ring_alpha * (1.0 - u)
		draw_arc(Vector2.ZERO, ring_radius * (0.35 + 0.65 * e), 0.0, TAU, 48, c, ring_width, true)


func _ready() -> void:
	current = self
	add_to_group(WorldPan.GROUP_PRESS)
	_content = ContentRegistry.content
	GardenFixture.apply_from_args(_content)
	var frame: Dictionary = _content.spots_doc["frame"]
	_dp = float(frame["px_per_dp"])
	var doc := FloraBuilder.load_doc()
	_builder = FloraBuilder.new(doc, ContentRegistry.motion_tokens())
	_atlas = load(String(doc.get("atlas", "res://art/flora/flora_atlas.svg"))) as Texture2D
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH) as Shader
	_mat.set_shader_parameter(&"flora_lut", ImageTexture.create_from_image(FloraBuilder.build_lut(_content)))
	_mat.set_shader_parameter(&"atlas_scale", float(doc.get("scale", 2.0)))
	LampRegistry.bind_material(_mat)
	var mt := ContentRegistry.motion_tokens()
	var flora: Dictionary = mt["flora"]
	_ready_cfg = flora["ready_bud"]
	_grow_cfg = flora["grow_step"]
	_unfurl_total_s = float(flora["unfurl"]["total_ms"]) / 1000.0
	var plant: Dictionary = flora["plant"]
	_seed_arc_s = float(plant["seed_arc_ms"]) / 1000.0
	_puff_s = float(plant["soil_puff_ms"]) / 1000.0
	var curves: Dictionary = mt["curves"]
	_bezier_decel = CubicBezier.from_array((curves[String(plant["seed_arc_curve"])] as Dictionary)["bezier"])
	for b: Dictionary in _content.beds:
		_make_bed(b)
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(ARG_QA_READY):
			_qa_ready = StringName(a.trim_prefix(ARG_QA_READY))
		elif a.begins_with(ARG_QA_UNFURL):
			_qa_unfurl_s = maxf(0.0, a.trim_prefix(ARG_QA_UNFURL).to_float())
		elif a.begins_with(ARG_QA_GARDEN):
			var kv := a.trim_prefix(ARG_QA_GARDEN).split(":")
			_qa_kind = kv[0]
			_qa_ms = kv[1].to_float() if kv.size() > 1 else 0.0
	if _qa_kind in ["bed", "unfurl", "ready"]:
		if _qa_ready == &"":
			_qa_ready = QA_BED
		_qa_t = 0.0
	else:
		_qa_kind = ""
	_butterflies = Butterflies.new()
	_butterflies.name = "Butterflies"
	add_child(_butterflies)
	_phase = TimeOfDay.phase
	TimeOfDay.phase_changed.connect(_on_phase_changed)
	Game.sim_event.connect(_on_sim_event)
	Game.world_ready.connect(func(_recap: Array) -> void: _sync_all())
	tree_exiting.connect(_on_exit)
	if Game.is_ready:
		_sync_all()


func _setup_butterflies() -> void:
	if Game.sim == null or _butterflies == null or _butterflies.get_child_count() > 0:
		return
	_butterflies.setup(FloraBuilder.new(FloraBuilder.load_doc(), ContentRegistry.motion_tokens()), _mat, _atlas,
			_content, func() -> Array: return _bloom_tips.values(), Game.sim.state.install_seed)


func _on_exit() -> void:
	LampRegistry.unbind_material(_mat)
	if current == self:
		current = null


func _make_bed(b: Dictionary) -> void:
	var v := BedView.new()
	v.id = StringName(b["id"])
	v.centre = GardenRules.bed_position_px(_content, v.id)
	var half := Vector2(float(b["hit_w_dp"]), float(b["hit_h_dp"])) * _dp * 0.5
	v.hit = Rect2(v.centre - half, half * 2.0 + Vector2(0.0, HIT_EXTEND_DP * _dp))
	v.node = Node2D.new()
	v.node.name = String(v.id)
	v.node.position = v.centre + Vector2(0.0, SORT_OFFSET_Y)
	add_child(v.node)
	v.mesh = MeshInstance2D.new()
	v.mesh.texture = _atlas
	v.mesh.material = _mat
	v.node.add_child(v.mesh)
	v.anim_mesh = MeshInstance2D.new()
	v.anim_mesh.texture = _atlas
	v.anim_mesh.material = _mat
	v.node.add_child(v.anim_mesh)
	v.press = Motion.spring(&"press", 1.0)
	_beds[v.id] = v


# ================================================================= sim binding

func _sync_all() -> void:
	var sim := Game.sim
	if sim == null:
		return
	_views.clear()
	_bloom_tips.clear()
	for bv: BedView in _beds.values():
		for h: HaloSprite in bv.halos.values():
			h.queue_free()
		bv.halos.clear()
		bv.dirty = true
	var qa_pick: Array[int] = []
	for i in sim.state.stems.size():
		var v := _view_for(i)
		if v.bed == _qa_ready and _qa_kind != "bed" and int(sim.state.stems[i]["stage"]) == WorldSim.STAGE_BLOOM \
				and v.open_target > 0.0:
			qa_pick.append(i)
	# The front-most stems (largest on screen) are the ones a still should show.
	qa_pick.sort_custom(func(a: int, b: int) -> bool: return _stem_root(a).y > _stem_root(b).y)
	for k in mini(QA_READY_MAX, qa_pick.size()):
		(_views[qa_pick[k]] as StemView).ready_s = 0.0
	_update_seed_hint()
	_refresh_choose_glow()
	_setup_butterflies()
	set_process(true)


func _view_for(i: int) -> StemView:
	if _views.has(i):
		return _views[i]
	var s: Dictionary = Game.sim.state.stems[i]
	var v := StemView.new()
	v.index = i
	v.bed = StringName(s["bed"])
	v.stretch = Motion.spring(&"move", 1.0)
	v.pop = Motion.spring(&"pop", 1.0)
	var f: Dictionary = _content.flowers_by_id.get(StringName(s["flower"]), {})
	if String(f.get("opens_at", "any")) == OPENS_DUSK_NIGHT:
		v.open = 1.0 if PHASES_OPEN.has(TimeOfDay.phase) else 0.0
		v.open_target = v.open
	_views[i] = v
	return v


func _on_sim_event(ev: Dictionary) -> void:
	var catch_up := bool(ev.get("catch_up", false))
	match StringName(ev["type"]):
		WorldSim.EV_PLANTED:
			var i := int(ev["stem"])
			var v := _view_for(i)
			if not catch_up:
				v.plant_s = 0.0
				AudioDirector.play_cue(CUE_PLANT, {"world": true, "position": _canvas_of(_stem_root(i))})
				FrameGovernor.hold_for(_seed_arc_s + _puff_s + Motion.duration(&"standard"))
			_mark(v.bed)
			_update_seed_hint()
			_refresh_choose_glow()
		WorldSim.EV_STAGE:
			var i2 := int(ev["stem"])
			var v2 := _view_for(i2)
			if not catch_up:
				if int(ev["stage"]) != WorldSim.STAGE_BLOOM:
					_grow_step(v2)
				elif v2.open_target > 0.0:
					v2.ready_s = 0.0  # a closed moonbloom by day simply stays a closed bud
			_mark(v2.bed)


func _grow_step(v: StemView) -> void:
	v.stretch = Motion.spring(&"move", float(_grow_cfg["stretch_y"]))
	v.stretch.target = 1.0
	v.pop = Motion.spring(&"pop", float(_grow_cfg["new_part_from_scale"]))
	v.pop.target = 1.0


func _mark(bed: StringName) -> void:
	var bv: BedView = _beds.get(bed)
	if bv != null:
		bv.dirty = true
	set_process(true)


func _on_phase_changed(phase: StringName) -> void:
	_phase = phase
	if Game.sim == null:
		return
	var open := PHASES_OPEN.has(phase)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.sim.state.install_seed, String(phase)])
	for i in Game.sim.state.stems.size():
		var s: Dictionary = Game.sim.state.stems[i]
		var f: Dictionary = _content.flowers_by_id.get(StringName(s["flower"]), {})
		if String(f.get("opens_at", "any")) != OPENS_DUSK_NIGHT:
			continue
		var v := _view_for(i)
		v.open_target = 1.0 if open else 0.0
		v.open_delay = rng.randf_range(0.0, MOON_WAVE_S) if open else 0.0
	set_process(true)


# ================================================================= frame

func _process(delta: float) -> void:
	if Game.sim == null or _qa_frozen:
		return
	if _qa_kind != "":
		_step_qa(delta)
		if _qa_frozen:
			return
	var busy := false
	_growth_t += delta
	var refresh := _growth_t >= GROWTH_REFRESH_S
	if refresh:
		_growth_t = 0.0
	var auto_after := float(_ready_cfg["auto_unfurl_after_s"])
	var auto_rate := _unfurl_total_s * 1000.0 / float(_ready_cfg["auto_unfurl_ms"])
	var anim_by_bed: Dictionary = {}
	for v: StemView in _views.values():
		var animating := false
		if v.ready_s >= 0.0 and v.unfurl_s < 0.0:
			v.ready_s += delta
			if v.ready_s >= auto_after:
				_start_unfurl(v, auto_rate, 0.0, false)
		if v.unfurl_s >= 0.0 or v.unfurl_delay > 0.0:
			if v.unfurl_delay > 0.0:
				v.unfurl_delay -= delta
			else:
				v.unfurl_s += delta
				_flare_halo(v)
				if v.unfurl_s * v.unfurl_rate >= _unfurl_total_s:
					v.unfurl_s = -1.0
					v.ready_s = -1.0
					v.open = 1.0
					_remove_halo(v)
			animating = true
		if not v.stretch.is_at_rest() or not v.pop.is_at_rest():
			v.stretch.step(delta)
			v.pop.step(delta)
			animating = true
		if v.plant_s >= 0.0:
			v.plant_s += delta
			if v.plant_s >= _seed_arc_s + _puff_s:
				v.plant_s = -1.0
			animating = true
		if v.open != v.open_target:
			animating = _step_open(v, delta) or animating
		if animating:
			var list: Array[int] = anim_by_bed.get(v.bed, [] as Array[int])
			list.append(v.index)
			anim_by_bed[v.bed] = list
			busy = true
	for bv: BedView in _beds.values():
		if bv.growing and refresh:
			bv.dirty = true
		if _step_press(bv, delta):
			busy = true
		var anim: Array[int] = anim_by_bed.get(bv.id, [] as Array[int])
		anim.sort()
		if anim != bv.anim:
			bv.anim = anim
			bv.dirty = true
		if bv.dirty:
			_rebuild(bv)
		if not bv.anim.is_empty():
			_build_into(bv, bv.anim_mesh, bv.anim, true)
		elif bv.anim_mesh.mesh != null:
			bv.anim_mesh.mesh = null
	if _press_bed != &"" and not _press_long_sent:
		_press_t += delta
		if _press_t >= LONG_PRESS_S:
			_press_long_sent = true
			bed_card_requested.emit(_press_bed)
		busy = true
	if _qa_unfurl_s >= 0.0:
		_qa_unfurl_s -= delta
		if _qa_unfurl_s < 0.0 and _beds.has(_qa_ready):
			_tap_bed(_beds[_qa_ready])
	if busy:
		FrameGovernor.poke()


## Moonbloom open/close (open: the slow unfurl after a wave delay; close: 2 s back to the bud).
func _step_open(v: StemView, delta: float) -> bool:
	if v.open_target > v.open:
		if v.open_delay > 0.0:
			v.open_delay -= delta
			return false
		if v.unfurl_s < 0.0:
			_start_unfurl(v, MOON_OPEN_RATE, 0.0, false)
		return true
	v.open = maxf(v.open_target, v.open - delta / MOON_CLOSE_S)
	return true


func _start_unfurl(v: StemView, rate: float, delay: float, sound: bool) -> void:
	# A ready bud's glow stays and flares with the petals (_flare_halo); removed when they settle.
	v.unfurl_s = 0.0
	v.unfurl_rate = rate
	v.unfurl_delay = delay
	v.open = 0.0
	v.open_target = 1.0
	if sound:
		AudioDirector.play_cue(CUE_UNFURL, {"position": _canvas_of(_stem_root(v.index))})
	FrameGovernor.hold_for(delay + _unfurl_total_s / rate)
	set_process(true)


## The ready glow flares with the opening petals and fades as they settle (removed at the end).
func _flare_halo(v: StemView) -> void:
	var bv: BedView = _beds.get(v.bed)
	if bv == null or not bv.halos.has(v.index):
		return
	var h: HaloSprite = bv.halos[v.index]
	var u := clampf(v.unfurl_s * v.unfurl_rate / _unfurl_total_s, 0.0, 1.0)
	var c: Color = h.get_instance_shader_parameter(&"i_color")
	c.a = float(_ready_cfg["glow_alpha"]) * READY_HALO_ALPHA_K * (1.0 + UNFURL_FLARE * sin(PI * minf(u * 1.6, 1.0))) \
			* (1.0 - u * u)
	h.set_instance_shader_parameter(&"i_color", c)
	h.scale = Vector2.ONE * (1.0 + UNFURL_GROW * (1.0 - pow(1.0 - u, 3.0)))


func _step_press(bv: BedView, delta: float) -> bool:
	var busy := false
	if not bv.press.is_at_rest() or bv.press.target != 1.0:
		var s := bv.press.step(delta)
		bv.node.scale = Vector2(1.0 / maxf(s, 0.5), s)
		busy = true
	elif bv.node.scale != Vector2.ONE:
		bv.node.scale = Vector2.ONE
	var x := 0.0
	if bv.sway_t >= 0.0:
		bv.sway_t += delta
		x = TAP_SWAY_PX * exp(-bv.sway_t / TAP_SWAY_DECAY_S) * sin(TAU * TAP_SWAY_HZ * bv.sway_t)
		if bv.sway_t > TAP_SWAY_DECAY_S * 6.0:
			bv.sway_t = -1.0
			x = 0.0
		busy = true
	if bv.tint > 0.0:
		bv.tint = maxf(0.0, bv.tint - delta / Motion.duration(&"short"))
		busy = true
	bv.mesh.set_instance_shader_parameter(&"i_bed", Vector4(x, 0.0, bv.tint, 0.0))
	return busy


## The bed's static mesh: every stem of the bed that is not mid-animation.
func _rebuild(bv: BedView) -> void:
	bv.dirty = false
	bv.growing = false
	var index_of: Array[int] = []
	for i in Game.sim.state.stems.size():
		if StringName(Game.sim.state.stems[i]["bed"]) == bv.id and not bv.anim.has(i):
			index_of.append(i)
	_build_into(bv, bv.mesh, index_of, false)


## The glowing tutorial seed resting on its bed (GDD §3.4): a little tended mound and the seed.
func _seed_extras(bv: BedView) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _seed == null or not bv.hit.has_point(_seed.position):
		return out
	var d := depth_scale(_seed.position.y)
	var p := _seed.position - bv.node.position
	out.append({"stamp": "moss_pad", "pos": p + Vector2(0.0, 4.0) * d, "scale": d * SEED_MOUND_SCALE,
		"part": FloraBuilder.PART_MOSS, "row": FloraBuilder.ROW_GROUND})
	out.append({"stamp": "seed_glow", "pos": p, "scale": d * SEED_SCALE, "part": FloraBuilder.PART_SPARKLE,
		"row": FloraBuilder.ROW_FX})
	return out


func _build_into(bv: BedView, mi: MeshInstance2D, index_of: Array[int], with_extras: bool) -> void:
	var sim := Game.sim
	var stems: Array[FloraBuilder.Stem] = []
	var t := sim.state.t
	for i in index_of:
		stems.append(_stem_spec(i, sim.state.stems[i], t, bv))
	var extras: Array[Dictionary] = []
	if not with_extras:
		extras = _seed_extras(bv)
	else:
		for i in index_of:
			var v: StemView = _views.get(i)
			if v != null and v.plant_s >= 0.0:
				_plant_extras(v, extras, bv)
	mi.mesh = _builder.build_mesh(stems, extras)
	# Ready-bud halos follow the tips; open heads are where butterflies land.
	for k in index_of.size():
		var i := index_of[k]
		var st2 := stems[k]
		if st2.stage == WorldSim.STAGE_BLOOM and not st2.ready and st2.open > 0.9 and _builder.tips.has(k):
			_bloom_tips[i] = (_builder.tips[k] as Vector2) + bv.node.position
		else:
			_bloom_tips.erase(i)
		var v: StemView = _views.get(i)
		if v != null and v.ready_s >= 0.0 and v.unfurl_s < 0.0 and _builder.tips.has(k):
			_ensure_halo(bv, v, _builder.tips[k])


func _stem_spec(i: int, s: Dictionary, t: float, bv: BedView) -> FloraBuilder.Stem:
	var flower := StringName(s["flower"])
	var f: Dictionary = _content.flowers_by_id.get(flower, {})
	var st := FloraBuilder.Stem.new()
	st.flower = flower
	st.form = String(f.get("form", "globe"))
	st.row = FloraBuilder.row_of(_content, flower)
	var root := _stem_root(i)
	st.root = root - bv.node.position
	st.depth = depth_scale(root.y)
	st.seed = FloraBuilder.stem_seed(bv.id, int(s["slot"]), flower)
	st.stage = int(s["stage"])
	var times := _stage_times(s, f)
	var age := t - float(s["planted_t"])
	if st.stage == WorldSim.STAGE_SPROUT:
		st.growth = clampf((age - times[0]) / maxf(times[1] - times[0], 1.0), 0.0, 1.0)
		bv.growing = true
	elif st.stage == WorldSim.STAGE_BUD:
		st.growth = clampf((age - times[1]) / maxf(times[2] - times[1], 1.0), 0.0, 1.0)
		bv.growing = true
	var v: StemView = _views.get(i)
	if v == null:
		return st
	st.stretch = v.stretch.value
	st.pop = clampf(v.pop.value, 0.0, 1.2)
	if v.plant_s >= 0.0:
		var u := clampf(v.plant_s / _seed_arc_s, 0.0, 1.0)
		st.alpha = 0.0 if u < 1.0 else 1.0
		st.pop = lerpf(float(_grow_cfg["new_part_from_scale"]), 1.0, clampf((v.plant_s - _seed_arc_s) / _puff_s, 0.0, 1.0))
	if st.stage == WorldSim.STAGE_BLOOM:
		if v.ready_s >= 0.0 and v.unfurl_s < 0.0:
			st.ready = true
			st.swell = lerpf(1.0, float(_ready_cfg["swell"]), 0.5 + 0.5 * sin(TAU * float(_ready_cfg["glow_k"]) / 600.0
					* v.ready_s))
			bv.growing = true
		elif v.unfurl_s >= 0.0 and v.unfurl_delay <= 0.0:
			st.unfurl_s = v.unfurl_s
			st.unfurl_rate = v.unfurl_rate
		elif v.unfurl_delay > 0.0:
			st.ready = true
		else:
			st.open = v.open
	return st


func _plant_extras(v: StemView, extras: Array[Dictionary], bv: BedView) -> void:
	var root := _stem_root(v.index)
	var u := clampf(v.plant_s / _seed_arc_s, 0.0, 1.0)
	var scale := depth_scale(root.y)
	if u < 1.0:
		var e := _bezier_decel.progress(u)
		var p := SEED_FROM.lerp(root, e) + Vector2(0.0, -SEED_ARC_LIFT * sin(PI * e))
		extras.append({"stamp": "seed_glow", "pos": p - bv.node.position, "scale": scale * 1.4, "part": FloraBuilder.PART_BUD,
			"row": FloraBuilder.row_of(_content, StringName(Game.sim.state.stems[v.index]["flower"])), "alpha": 1.0})
		return
	var w := clampf((v.plant_s - _seed_arc_s) / _puff_s, 0.0, 1.0)
	for d in SOIL_PUFF_DOTS:
		var a := PI + PI * (float(d) + 0.5) / float(SOIL_PUFF_DOTS)
		var p2 := root + Vector2.from_angle(a) * SOIL_PUFF_PX * scale * (0.4 + 0.6 * w)
		extras.append({"stamp": "glint", "pos": p2 - bv.node.position, "scale": scale * 1.2 * (1.0 - 0.5 * w),
			"part": FloraBuilder.PART_SOIL, "row": FloraBuilder.ROW_GROUND, "alpha": 1.0 - w})


func _stage_times(s: Dictionary, f: Dictionary) -> PackedFloat64Array:
	if bool(s["tutorial"]):
		var ob: Dictionary = _content.economy["onboarding"]
		return PackedFloat64Array([float(ob["tutorial_sprout_at_s"]), float(ob["tutorial_bud_at_s"]),
			float(ob["tutorial_bloom_at_s"])])
	return PackedFloat64Array([float(f.get("sprout_at_s", 0.0)), float(f.get("bud_at_s", 0.0)),
		float(f.get("bloom_at_s", 0.0))])


func _stem_root(i: int) -> Vector2:
	var s: Dictionary = Game.sim.state.stems[i]
	var bed: Dictionary = _content.beds_by_id.get(StringName(s["bed"]), {})
	if bed.is_empty():
		return Vector2.ZERO
	var off: Array = (bed["stems"] as Array)[int(s["slot"])]
	return GardenRules.bed_position_px(_content, StringName(s["bed"])) \
			+ GardenRules.frame_to_px(_content, Vector2(float(off[0]), float(off[1])))


static func depth_scale(y: float) -> float:
	return clampf(DEPTH.x + (1.0 - DEPTH.x) * (y - DEPTH.y) / DEPTH.z, DEPTH.x, 1.0)


func _canvas_of(design: Vector2) -> Vector2:
	# canvas (world) px: the caption host applies the camera (map pan) itself
	return get_global_transform() * design


# ================================================================= halos

func _ensure_halo(bv: BedView, v: StemView, tip: Vector2) -> void:
	var h: HaloSprite = bv.halos.get(v.index)
	if h == null:
		var r0 := 14.0 * READY_HALO_SCALE * depth_scale(bv.centre.y)
		h = HaloSprite.new().setup(r0, r0 * HALO_QUAD_K,
				Color(1, 1, 1, float(_ready_cfg["glow_alpha"]) * READY_HALO_ALPHA_K), READY_PULSE_K,
				HaloSprite.FLAG_ACCENT, float(v.index))
		bv.node.add_child(h)
		bv.halos[v.index] = h
	h.position = tip


func _remove_halo(v: StemView) -> void:
	var bv: BedView = _beds.get(v.bed)
	if bv == null:
		return
	var h: HaloSprite = bv.halos.get(v.index)
	if h != null:
		h.queue_free()
		bv.halos.erase(v.index)


func _refresh_choose_glow() -> void:
	if _content == null:
		return
	var rooms: Array[StringName] = []
	if choose_mode and Game.sim != null:
		rooms = GardenRules.beds_with_room(_content, Game.sim.state.stems)
	for bv: BedView in _beds.values():
		var want := rooms.has(bv.id)
		if want and bv.choose_halo == null:
			bv.choose_halo = HaloSprite.new().setup(bv.hit.size.x * 0.22, bv.hit.size.x * 0.6, Color(1, 1, 1, 0.35),
					float(_ready_cfg["glow_k"]), HaloSprite.FLAG_ACCENT)
			bv.node.add_child(bv.choose_halo)
		elif not want and bv.choose_halo != null:
			bv.choose_halo.queue_free()
			bv.choose_halo = null


func _update_seed_hint() -> void:
	var show := Game.sim != null and not Game.sim.state.seed_planted
	if show and _seed == null:
		var ob: Dictionary = _content.economy["onboarding"]
		var bed := StringName(ob["tutorial_bed"])
		var flower := StringName(ob["tutorial_flower"])
		var slot := GardenRules.choose_slot(_content, Game.sim.state.stems, bed, flower)
		var bd: Dictionary = _content.beds_by_id[bed]
		var off: Array = (bd["stems"] as Array)[maxi(slot, 0)]
		var pos := GardenRules.bed_position_px(_content, bed) + GardenRules.frame_to_px(_content,
				Vector2(float(off[0]), float(off[1])))
		_seed = SeedHint.new()
		_seed.name = "TutorialSeed"
		_seed.position = pos
		var ring: Dictionary = _content.motion["ui"]["tutorial_hint_ring"]
		_seed.ring_after_s = float(ring["seed_after_s"])
		_seed.ring_period_s = float(ring["period_s"])
		_seed.ring_expand_s = float(ring["expand_ms"]) / 1000.0
		_seed.ring_radius = float(ring["radius_dp"]) * _dp
		_seed.ring_alpha = float(ring["alpha"])
		_seed.ring_width = float(ring["stroke_dp"]) * _dp
		_seed.ring_color = Color.html(String(_content.palettes["ui"]["surface"]))
		_seed.breathe_hz = float((_content.motion["loops_k"]["zzz_emit"] as Array)[0]) / 600.0
		_seed.base_alpha = float(_ready_cfg["glow_alpha"]) * SEED_GLOW_K
		var r0 := 14.0 * depth_scale(pos.y)
		_seed.halo = HaloSprite.new().setup(r0, r0 * HALO_QUAD_K, Color(1, 1, 1, _seed.base_alpha), 0.0,
				HaloSprite.FLAG_ACCENT)
		_seed.add_child(_seed.halo)
		add_child(_seed)
		var bv: BedView = _beds[bed]
		bv.dirty = true
	elif not show and _seed != null:
		_seed.queue_free()
		_seed = null
	for bv2: BedView in _beds.values():
		bv2.dirty = true


# ================================================================= touch

func _unhandled_input(event: InputEvent) -> void:
	var pressed := false
	var released := false
	var moved := false
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		pressed = st.pressed
		released = not st.pressed
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or mb.device == InputEvent.DEVICE_ID_EMULATION:
			return
		pressed = mb.pressed
		released = not mb.pressed
	elif event is InputEventScreenDrag or event is InputEventMouseMotion:
		moved = true
	else:
		return
	var local := make_input_local(event)
	var pos: Vector2 = local.get("position")
	if pressed:
		var bed := _bed_at(pos)
		if bed == &"":
			return
		_press_bed = bed
		_press_pos = pos
		_press_t = 0.0
		_press_long_sent = false
		_touch_down(_beds[bed], pos)
		get_viewport().set_input_as_handled()
	elif moved and _press_bed != &"":
		if pos.distance_to(_press_pos) > DRAG_CANCEL_PX:
			_release_press(false)
	elif released and _press_bed != &"":
		var bv: BedView = _beds[_press_bed]
		var inside := bv.hit.has_point(pos) and pos.distance_to(_press_pos) <= DRAG_CANCEL_PX
		_release_press(inside and not _press_long_sent)
		get_viewport().set_input_as_handled()


## WorldPan: a map drag started; the pending bed tap / long-press is dropped (no action).
func cancel_world_press() -> void:
	if _press_bed != &"":
		_release_press(false)


func _bed_at(pos: Vector2) -> StringName:
	var best: StringName = &""
	var best_d := INF
	for bv: BedView in _beds.values():
		if bv.hit.has_point(pos):
			var d := pos.distance_squared_to(bv.centre)
			if d < best_d:
				best_d = d
				best = bv.id
	return best


func _touch_down(bv: BedView, pos: Vector2) -> void:
	_qa_ring = TouchRing.spawn(self, pos, RING_SQUASH)
	_qa_ring.z_index = 1
	var rv: Vector4 = _qa_ring.get_instance_shader_parameter(&"i_ring")
	rv.z = RING_ALPHA
	_qa_ring.set_instance_shader_parameter(&"i_ring", rv)
	bv.press = Motion.spring(&"press", bv.press.value)
	bv.press.target = float(_content.motion["ui"]["world_touch_squash"])
	bv.tint = 1.0
	AudioDirector.play_cue(CUE_TOUCH, {"world": true, "position": _canvas_of(bv.centre)})
	FrameGovernor.hold_for(Motion.duration(&"short"))
	set_process(true)


func _release_press(act: bool) -> void:
	var bv: BedView = _beds.get(_press_bed)
	_press_bed = &""
	if bv == null:
		return
	var pop := Motion.spring(&"pop", bv.press.value)
	pop.velocity = bv.press.velocity
	pop.target = 1.0
	bv.press = pop
	if act:
		_tap_bed(bv)
	set_process(true)


func _tap_bed(bv: BedView) -> void:
	if choose_mode:
		if GardenRules.has_room(_content, Game.sim.state.stems, bv.id):
			bed_chosen.emit(bv.id)
		return
	if _seed != null and bv.hit.has_point(_seed.position):
		Game.tap_seed()
		return
	var stagger := Motion.stagger_delay(1)
	var n := 0
	for v: StemView in _views.values():
		if v.bed == bv.id and v.ready_s >= 0.0 and v.unfurl_s < 0.0:
			_start_unfurl(v, 1.0, stagger * float(n), n == 0)
			n += 1
	if n == 0:
		bv.sway_t = 0.0
		AudioDirector.play_cue(CUE_RUSTLE, {"position": _canvas_of(bv.centre)})
		FrameGovernor.hold_for(TAP_SWAY_DECAY_S * 3.0)


## True when a touch at [param pos] belongs to a bed that outranks décor (GDD §2.5 hit priority:
## a bed with a ready bud, or the tutorial seed's bed).
func claims(pos: Vector2) -> bool:
	var bed := _bed_at(pos)
	if bed == &"":
		return false
	var bv: BedView = _beds[bed]
	if _seed != null and bv.hit.has_point(_seed.position):
		return true
	for v: StemView in _views.values():
		if v.bed == bed and v.ready_s >= 0.0 and v.unfurl_s < 0.0:
			return true
	return false


## Design-px hit rect of a bed (UI: the bed card anchor).
func bed_rect(bed_id: StringName) -> Rect2:
	var bv: BedView = _beds.get(bed_id)
	return bv.hit if bv != null else Rect2()


# ================================================================= QA touch strip

## --qa-garden timeline: touch at QA_TOUCH_AT_S, (tap: release after QA_TAP_S), freeze <ms> after
## the touch (bed) or the release (unfurl). ready only waits for the glow.
func _step_qa(delta: float) -> void:
	if _qa_t < 0.0 or not Game.is_ready:
		return
	_qa_t += delta
	var bv: BedView = _beds.get(_qa_ready)
	if bv == null:
		_qa_kind = ""
		return
	var touch_at := QA_TOUCH_AT_S
	var release_at := touch_at + QA_TAP_S
	if _qa_kind == "ready":
		return
	if _qa_step == 0 and _qa_t >= touch_at:
		_qa_step = 1
		_press_bed = bv.id
		_press_pos = bv.centre
		_press_t = 0.0
		_press_long_sent = true  # a held QA touch never opens the bed card
		_touch_down(bv, bv.centre)
	if _qa_kind == "unfurl" and _qa_step == 1 and _qa_t >= release_at:
		_qa_step = 2
		_release_press(true)
	var freeze_at := (release_at if _qa_kind == "unfurl" else touch_at) + _qa_ms / 1000.0
	if _qa_step >= 1 and _qa_t >= freeze_at:
		_qa_frozen = true
		if is_instance_valid(_qa_ring):
			_qa_ring.freeze_at(_qa_ms / 1000.0 if _qa_kind == "bed" else _qa_t - touch_at)
