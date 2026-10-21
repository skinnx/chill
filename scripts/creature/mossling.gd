class_name Mossling
extends Node2D
## One mossling in the hollow (docs/ART_BIBLE.md §5.2, §5.7, §10; GDD §3.1, §4.1.3).
##
## Node: Mossling (origin = sort point) -> Visual (feet; offset by the perch sort bias, depth
## scaled) -> Shadow (contact/cast shadow), Body (SDF quad, mossling_fur), Fx (hearts, z's, ring,
## umbrella), NameTag. Everything is analytic springs (scripts/motion/spring.gd) and data from
## creature_rig.json view.behaviour + motion_tokens.json creature; nothing is a linear tween.
##
## The creature layer drives it: [method enter_from] / [method perform] (a bout from the
## CreatureBrain) / [method leave_to]; touches arrive through [method touch_down],
## [method touch_move] and [method touch_up]. Every intent that changes the world goes through
## Game (pet) via the layer's signals; nothing here touches the sim.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## Reached the end of the current walk.
signal walk_finished
## Faded out at the exit after [method leave_to].
signal left_hollow(m: Mossling)
## A tap (short press) landed: the layer shows the name tag / opens the card on a second tap.
signal tapped(m: Mossling)
## Long-press or stroke completed and released (hearts are already rising).
signal petted(m: Mossling)
## Touch-down on this mossling (the layer plays the chirp / snore cue at once, I1).
signal touched(m: Mossling)
## Pet hold started (purr on) / ended (purr off).
signal pet_started(m: Mossling)
signal pet_ended(m: Mossling)

enum Act { IDLE, NAP, NIBBLE, PLAY, WANDER, STREAM, PEEK }
enum Hop { NONE, ANTIC, AIR, GAP }

const B_NAP := &"nap"
const B_NIBBLE := &"nibble"
const B_PLAY := &"play"
const B_WANDER := &"wander"
const B_STREAM := &"sit_by_stream"
const MS := 0.001
## Hop / waddle gait parameters not in the data files (structural, §5.7 "soft hop/waddle").
const WADDLE_STEP_S := 0.34
const WADDLE_STEP_PX := 26.0
const WADDLE_LEAN := 0.05
const WADDLE_BOB_BU := 0.035
const WADDLE_SQUASH := 0.035
const SOFT_HOP_HEIGHT_K := 0.55
const SOFT_HOP_SQUASH_K := 0.6
const TAKEOFF_S := 0.05
const LID_DOUBLE_P_KEY := "double_p"
const STROKE_TIME_MIN_S := 0.06
const TAP_MAX_MOVE_PX := 18.0
## Per-frame write threshold for animated uniforms (skip invisible changes).
const UNIFORM_EPS := 1e-4
const NAP_SETTLE_EASE := 2.0
const HEAD_BU := 1.05
## Sheltered spots (under the willow, in the stump) halve the shadow (§4.12).
const SHELTER_SHADOW_K := 0.5
## mossling_fur.gdshader packing (UMB_CODE, LEAF_STEPS): keep in sync.
const UMB_CODE := 0.4
const LEAF_STEPS := 8.0
## Shadow quad in body units (x body widths, y body heights from the feet): room for the 2.5x
## golden-hour cast toward the viewer and its sideways offset (creature_shadow.gdshader).
const SHADOW_RECT_BU := Rect2(-2.4, -0.5, 4.8, 3.0)

var species_id: StringName = &""
var seed01: float = 0.0
var voice_step: int = 0
var rig: MosslingRig
var rng := RandomNumberGenerator.new()
## Current behaviour id (B_*), the spot id it happens at, and the world point it is anchored to.
var behaviour: StringName = &""
var spot_id: StringName = &""
var anchor: Vector2 = Vector2.ZERO
var leaving: bool = false
var is_greeter: bool = false
## Depth scale of the visual (Art Bible §2.4), updated while moving.
var depth: float = 1.0
## Napping right now (asleep enough that taps only stir).
var asleep: bool = false

var _visual: Node2D
var _shadow: SdfQuad
var _body: SdfQuad
var _fx: MosslingFx
var _tag: PanelContainer
var _tag_label: Label
var _b: Dictionary = {}
var _cr: Dictionary = {}
var _s_px: float = 150.0
var _w_px: float = 150.0
var _sort_bias: float = 0.0

# springs (Art Bible §10.2): squash on jelly, lean on move, ears/antenna/tail on follow
var _squash: Spring
var _lean: Spring
var _ear: Spring
var _ant: Spring
var _tail: Spring
var _rest_squash: float = 1.0
var _lean_base: float = 0.0
var _act_lean: float = 0.0
var _ear_rest: float = 0.0
var _ant_rest: float = 0.0
var _tail_rest: float = 0.0
var _hop_f: float = 1.0
var _chew_f: float = 1.0
var _turn_f: float = 1.0
var _wiggle: float = 0.0

# face / state
var _look: float = 0.0
var _look_from: float = 0.0
var _look_to: float = 0.0
var _look_t: float = 1.0
var _look_dur: float = 0.2
var _facing: float = 1.0
var _facing_to: float = 1.0
var _sleep: float = 0.0
var _sleep_to: float = 0.0
var _sleep_rate: float = 1.0 / 1.2
var _happy: float = 0.0
var _happy_to: float = 0.0
var _closed: int = MosslingRig.CLOSED_OPEN
var _lid: float = 0.0
var _blink_t: float = 0.0
var _blink_next: float = 3.0
var _blink_double: bool = false
var _blink_phase: int = 0
var _breath_k: float = 150.0
var _breath_off: float = 0.0
var _alpha: float = 1.0
var _alpha_to: float = 1.0
var _alpha_rate: float = 2.5
var _rain: bool = false
var _sheltered: bool = false
var _wants_umbrella: bool = true
var _umbrella_back: Node2D

# walking
var _path: PackedVector2Array = PackedVector2Array()
var _path_i: int = 0
var _walking: bool = false
var _bouncy: bool = false
var _hop_state: int = Hop.NONE
var _hop_t: float = 0.0
var _hop_dur: float = 0.3
var _hop_from: Vector2 = Vector2.ZERO
var _hop_to: Vector2 = Vector2.ZERO
var _hop_h: float = 0.0
var _hop_height_px: float = 30.0
var _waddle_phase: float = 0.0
var _speed_px: float = 78.0
var _feet: Vector2 = Vector2.ZERO
var _prev_body_y: float = 0.0
var _prev_body_vy: float = 0.0
var _vel_x: float = 0.0
var _on_arrive: Callable = Callable()

# behaviour
var _act: int = Act.IDLE
var _act_t: float = 0.0
var _act_next: float = 0.0
var _act_step: int = 0
var _act_dir: float = 1.0
var _zzz_t: float = 0.0
var _zzz_pause: float = 0.0
var _fidget_next: float = 3.0
var _look_next: float = 2.0
var _play_partner: Mossling = null
var _play_offset: float = 0.0
var _stream_t: float = 0.0
var _nap_settle: float = 0.0
var _tag_t: float = 0.0

# touch
var _touching: bool = false
var _touch_t: float = 0.0
var _touch_from: Vector2 = Vector2.ZERO
var _touch_at: Vector2 = Vector2.ZERO
var _petting: bool = false
var _pet_t: float = 0.0
var _pet_heart_t: float = 0.0
var _frozen: bool = false
var _last_tap_s: float = -INF
var _reopen_t: float = -1.0
var _overshoot_hold: float = 0.0
var _exit_path_cache: PackedVector2Array = PackedVector2Array()
var _scale_override: float = 0.0
var _still: bool = false

# uniform mirrors (write only on change, §5.5)
var _u_anim: Vector4 = Vector4(-1, 0, 0, 0)
var _u_follow: Vector4 = Vector4(-1, 0, 0, 0)
var _u_state: Vector4 = Vector4(-1, 0, 0, 0)
var _u_misc: Vector4 = Vector4.ZERO
var _u_shadow: Vector4 = Vector4(-1, 0, 0, 0)
var _u_light: Vector4 = Vector4(-1, 0, 0, 0)
var _light: Vector4 = Vector4.ZERO
var _lamp_t: float = 0.0
var _nestle: float = 0.0
var _shadow_host: Node2D = null
var _feet_nubs: bool = false
var _leaf: float = 0.0
var _focal: float = 0.0


## Builds the node tree for [param p_species]. Materials are shared across all mosslings.
func setup(p_rig: MosslingRig, p_species: StringName, p_seed01: float, fur: ShaderMaterial,
		shadow_mat: ShaderMaterial, fx_mats: Dictionary) -> void:
	rig = p_rig
	species_id = p_species
	seed01 = clampf(p_seed01, 0.0, 0.9999)
	rng.seed = hash([String(p_species), seed01])
	_b = rig.behaviour()
	_cr = rig.content.motion.get("creature", {})
	var sp: Dictionary = rig.content.species_by_id.get(p_species, {})
	voice_step = int(sp.get("voice_step", 0))
	var bouncy: Array = _b.get("bouncy_species", [])
	_bouncy = bouncy.has(String(p_species))
	_s_px = rig.body_px(p_species)
	_w_px = _s_px * rig.body_width_bu(p_species)
	name = "Mossling_%s" % p_species
	_visual = Node2D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_shadow = SdfQuad.new()
	_shadow.name = "Shadow"
	_shadow.material = shadow_mat
	# body units (creature_shadow.gdshader): the node scale carries the body size in px
	_shadow.rect = SHADOW_RECT_BU
	_shadow.scale = Vector2(_w_px, _s_px)
	_visual.add_child(_shadow)
	_body = SdfQuad.new()
	_body.name = "Body"
	_body.material = fur
	_body.rect = rig.quad_rect(p_species)
	_visual.add_child(_body)
	# the leaf umbrella is HELD (QA r2): drawn over the body, its stem gripped by a paw on the
	# front side at the body's edge, the canopy over the crown (never across the face)
	_umbrella_back = Node2D.new()
	_umbrella_back.name = "UmbrellaHeld"
	_visual.add_child(_umbrella_back)
	_fx = MosslingFx.new()
	_fx.name = "Fx"
	_visual.add_child(_fx)
	_fx.setup(rig, fx_mats, _umbrella_back)
	_build_tag()
	# springs
	_squash = Motion.spring(&"jelly", 1.0)
	_lean = Motion.spring(&"move", 0.0)
	_ear = Motion.spring(&"follow", 0.0)
	_ant = Motion.spring(&"follow", 0.0)
	_tail = Motion.spring(&"follow", 0.0)
	var leans: Array = _b.get("lean_deg", [2.0, 4.0])
	var lean_mag := deg_to_rad(rng.randf_range(float(leans[0]), float(leans[1])))
	_lean_base = lean_mag * (1.0 if rng.randf() < 0.5 else -1.0)
	_lean.snap(_lean_base)
	var walk: Array = _b.get("walk_speed_dp_s", [20, 30])
	_speed_px = rng.randf_range(float(walk[0]), float(walk[1])) * 3.0
	_breath_k = rig.breath_k(false, rng.randf())
	_facing = 1.0 if rng.randf() < 0.5 else -1.0
	_facing_to = _facing
	_look_dur = float(_b.get("look_turn_ms", 200.0)) * MS
	var enter_ms := float((_cr.get("sleep", {}) as Dictionary).get("enter_ms", 1200.0))
	_sleep_rate = 1.0 / maxf(enter_ms * MS, 0.05)
	_alpha_rate = 1.0 / maxf(float(_b.get("enter_fade_ms", 400.0)) * MS, 0.05)
	_schedule_blink()
	_fidget_next = _rand_range("fidget_s")
	_look_next = _rand_range("look_s")
	var params := rig.static_params(p_species, seed01)
	for k: StringName in params:
		_body.set_instance_shader_parameter(k, params[k])
	_u_misc = params[MosslingRig.I_MISC]
	_fx.set_paw_colour(params[MosslingRig.I_FUR])
	_feet_nubs = _u_misc.z > 0.5
	_push_uniforms(true)


# ================================================================= placement and movement

func feet() -> Vector2:
	return _feet


## Teleports the feet to [param p] (no motion).
func place_at(p: Vector2) -> void:
	_feet = p
	_walking = false
	_hop_state = Hop.NONE
	_hop_h = 0.0
	_apply_position()


## Draws the contact / cast shadow from [param host] (a plain Node2D in the layer's space that
## sorts before every prop and creature) instead of from this creature's own subtree, so all the
## shadows on the meadow share one draw batch (Art Bible §4.19). null puts it back in the
## subtree (creatures on props or behind the crest, where the shadow must sort with the body).
func set_shadow_host(host: Node2D) -> void:
	if host == _shadow_host or _shadow == null:
		return
	_shadow_host = host
	if host != null:
		_shadow.reparent(host, false)
	else:
		_shadow.reparent(_visual, false)
		_visual.move_child(_shadow, 0)
		_shadow.position = Vector2.ZERO
	_apply_position()
	_push_uniforms(true)


func shadow_host() -> Node2D:
	return _shadow_host


func sort_bias() -> float:
	return _sort_bias


## The focal friend (the one on the sun stone, Art Bible §2.5): a stronger rim and a warm lift.
func set_focal(on: bool) -> void:
	_focal = 1.0 if on else 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _shadow_host != null and is_instance_valid(_shadow):
		_shadow.queue_free()


## Sort bias (px): the node sorts at feet.y + bias, so a creature on a prop's top draws in front of
## that prop (props sort by their base).
func set_sort_bias(px: float) -> void:
	_sort_bias = px
	_apply_position()


## Walks (hops or waddles) along [param path] (design px) and calls [param on_arrive] at the end.
func walk(path: PackedVector2Array, on_arrive: Callable = Callable()) -> void:
	_path = path
	_path_i = 0
	_on_arrive = on_arrive
	_walking = not path.is_empty()
	if _walking:
		_wake()
		_set_act(Act.IDLE)
	elif on_arrive.is_valid():
		on_arrive.call()


func is_walking() -> bool:
	return _walking


## Fade in at [param entry] (never pops in, V5), then walk the path to the first spot.
func enter_from(entry: Vector2, path: PackedVector2Array, on_arrive: Callable) -> void:
	place_at(entry)
	_alpha = 0.0
	_alpha_to = 1.0
	modulate.a = 0.0
	walk(path, on_arrive)


## Wake, stretch, wave, walk to the exit and fade out (GDD §4.1.3 LEAVE).
func leave_to(path: PackedVector2Array) -> void:
	leaving = true
	_end_pet(false)
	_wake()
	_set_act(Act.IDLE)
	look_at_camera()
	_squash.value = 1.06
	_fx.hearts(_head_local(), 1, 0.0)
	walk(path, func() -> void:
		_alpha_to = 0.0
		_alpha_rate = 1.0 / maxf(float(_b.get("leave_fade_ms", 400.0)) * MS, 0.05))


## A peek visit (GDD §4.1.3): waves from the rim for peek_wave_s, then leaves.
func peek(at: Vector2, entry_path: PackedVector2Array, exit_path: PackedVector2Array) -> void:
	enter_from(at, entry_path, func() -> void:
		_set_act(Act.PEEK)
		_act_next = float(_b.get("peek_wave_s", 4.0))
		_act_step = 0
		_exit_path_cache = exit_path)


# ================================================================= behaviours

## Starts [param p_behaviour] at the current position (the layer walks the creature there first).
## [param params]: "look" (float), "lean_dir" (float, nibble), "partner" (Mossling, play),
## "shelter" (bool).
func perform(p_behaviour: StringName, p_spot: StringName, params: Dictionary = {}) -> void:
	behaviour = p_behaviour
	spot_id = p_spot
	anchor = _feet
	_sheltered = bool(params.get("shelter", false))
	match p_behaviour:
		B_NAP:
			_start_nap()
		B_NIBBLE:
			_set_act(Act.NIBBLE)
			_act_dir = float(params.get("lean_dir", 1.0))
			turn_to(_act_dir * 0.55)
			_act_next = 0.4
		B_PLAY:
			_set_act(Act.PLAY)
			var partner: Variant = params.get("partner")
			_play_partner = partner as Mossling if partner is Mossling else null
			_play_offset = float(params.get("offset_s", 0.0))
			_act_next = 0.5 + _play_offset
		B_WANDER:
			_set_act(Act.WANDER)
			_act_next = _rand_range("wander_rest_s") * 0.4
		B_STREAM:
			_set_act(Act.STREAM)
			turn_to(float(params.get("look", -float(_b.get("stream_look", 0.6)))))
			_stream_t = rng.randf_range(2.0, float(_b.get("stream_paw_s", 12.8)))
		_:
			_set_act(Act.IDLE)
	_update_rest_pose()


## Greeter hello (GDD §5.6): a happy squash, happy eyes and a heart, over whatever it is doing.
func greet() -> void:
	look_at_camera()
	_happy_to = 1.0
	if not asleep:
		_closed = MosslingRig.CLOSED_HAPPY
	_squash.value = _sq(float(_b.get("greeter_wave_squash", 0.92))) * _rest_squash
	_fx.hearts(_head_local(), 1, 0.0)
	_reopen_t = float(_b.get("greet_hold_s", 1.2))


## [param umbrella]: the bout wants a leaf umbrella (false for rain lovers and under shelter).
func set_rain(on: bool, sheltered: bool, umbrella: bool = true) -> void:
	_rain = on
	_sheltered = sheltered
	_wants_umbrella = umbrella
	_update_rest_pose()


func look_at_camera() -> void:
	turn_to(0.0)


## Crossfades the look to [param target] (-1 left .. +1 right) over look_turn_ms with a dip;
## the tail swaps sides only when the look crosses zero (never a mirror flip).
func turn_to(target: float) -> void:
	target = clampf(target, -1.0, 1.0)
	if is_equal_approx(target, _look_to):
		return
	_look_from = _look
	_look_to = target
	_look_t = 0.0
	if absf(target) > 0.1:
		_facing_to = signf(target)


func show_name(text: String) -> void:
	_tag_label.text = text
	_tag.reset_size()
	_tag.position = Vector2(-_tag.size.x * 0.5, -(_s_px * (1.0 + rig.top_extent_bu(species_id)) + _tag.size.y + 12.0))
	_tag_t = float(_b.get("name_tag_ms", 2000.0)) * MS


func sparkle(count: int) -> void:
	_fx.sparkles(_head_local() + Vector2(0.0, _s_px * 0.3), count)


# ================================================================= touch (GDD §3.1, §10.3)

## Hit test in the creature layer's space (design px). Radius >= view.hit.radius_px x depth,
## never under 90 px (60 dp target, I2).
func hit_test(point: Vector2) -> bool:
	if leaving or _alpha < 0.5:
		return false
	var hit: Dictionary = rig.view().get("hit", {})
	var c := _feet - Vector2(0.0, (float(hit.get("centre_bu", 0.5)) * _s_px + _hop_h) * depth)
	var r := maxf(float(hit.get("radius_px", 96.0)) * maxf(depth, 1.0), 90.0)
	return point.distance_to(c) <= r


func touch_down(point: Vector2) -> void:
	_touching = true
	_touch_t = 0.0
	_touch_from = point
	_touch_at = point
	# first visual answer this frame: squash 0.94 (stir 0.97 when napping)
	var tap: Dictionary = _cr.get("tap", {})
	_squash.target = float(_b.get("stir_squash", 0.97)) if asleep else float(tap.get("squash", 0.94))
	_squash.velocity -= float(_b.get("touch_kick", 2.4))
	# seen on the first frame: a soft ripple round the body and the ears flick back
	_fx.ripple(_ring_center(), _ring_radius(), float(_b.get("stir_ripple_k", 0.55)) if asleep else 1.0)
	_ear.kick(-0.9)
	touched.emit(self)


func touch_move(point: Vector2) -> void:
	if not _touching:
		return
	_touch_at = point
	var stroke := float((_cr.get("pet", {}) as Dictionary).get("stroke_drag_px", 24.0))
	if not _petting and _touch_t > STROKE_TIME_MIN_S and point.distance_to(_touch_from) >= stroke:
		_begin_pet()


func touch_up(_point: Vector2) -> void:
	if not _touching:
		return
	_touching = false
	_fx.set_ring(_ring_center(), _ring_radius(), 0.0, false)
	if _petting:
		_end_pet(true)
		return
	_squash.target = _rest_squash
	if _touch_at.distance_to(_touch_from) <= TAP_MAX_MOVE_PX:
		_on_tap()


func cancel_touch() -> void:
	if _petting:
		_end_pet(false)
	_touching = false
	_squash.target = _rest_squash
	_fx.set_ring(_ring_center(), _ring_radius(), 0.0, false)


func _on_tap() -> void:
	if asleep:
		# a napping mossling only stirs: ear twitch, z's pause (never wakes abruptly)
		_ear.kick(1.6)
		_zzz_pause = float(_b.get("stir_zzz_pause_s", 2.0))
		_fx.sparkles(_head_local() + Vector2(_facing * _w_px * 0.3, _s_px * 0.15), 1)
	else:
		look_at_camera()
		_ear.kick(-1.2)
		_ant.kick(1.5 * (1.0 if rng.randf() < 0.5 else -1.0))
		_act_next = maxf(_act_next, 1.5)
		_look_next = maxf(_look_next, 2.5)
		# a happy "^ ^" beat and a little burst of sparkles (delight, GDD §3.1)
		_happy_to = 1.0
		_closed = MosslingRig.CLOSED_HAPPY
		_reopen_t = float(_b.get("tap_happy_ms", 650.0)) * MS
		_fx.sparkles(_head_local() + Vector2(0.0, _s_px * 0.25), int(_b.get("tap_sparkles", 4)))
	tapped.emit(self)


func _begin_pet() -> void:
	_petting = true
	_pet_t = 0.0
	_pet_heart_t = float(_b.get("pet_first_heart_s", 0.25))
	var pet: Dictionary = _cr.get("pet", {})
	_squash.target = float(pet.get("hold_squash", 0.88))
	_happy_to = 1.0
	if not asleep:
		_closed = MosslingRig.CLOSED_HAPPY
		look_at_camera()
	_reopen_t = -1.0
	pet_started.emit(self)


func _end_pet(released: bool) -> void:
	if not _petting:
		return
	_petting = false
	var pet: Dictionary = _cr.get("pet", {})
	_wiggle = 0.0
	_squash.target = float(pet.get("release_overshoot_target", 1.04))
	_overshoot_hold = 0.12
	pet_ended.emit(self)
	if released:
		_fx.hearts(_head_local(), int(pet.get("hearts_on_release", 3)), float(_b.get("heart_stagger_ms", 120.0)) * MS)
		_reopen_t = float(_b.get("pet_reopen_ms", 300.0)) * MS
		petted.emit(self)
	else:
		_reopen_t = 0.0



# ================================================================= QA helpers (lineup, fixtures)

## Fixed visual scale instead of the depth scale (lineup).
func scale_override(k: float) -> void:
	_scale_override = k
	_apply_position()


## QA: holds the creature and its stamps exactly where they are (a touch-feedback still).
func freeze(on: bool) -> void:
	_frozen = on
	_fx.set_process(not on)


## No blinks or fidgets (deterministic close-up stills).
func set_still(on: bool) -> void:
	_still = on


## Snaps to a settled pose: &"awake", &"asleep" (nap settled) or &"happy" (petted face).
func debug_pose(kind: StringName) -> void:
	match kind:
		&"asleep":
			_start_nap()
			_nap_settle = 1.0
			_sleep = 1.0
			_lid = 1.0
			_closed = MosslingRig.CLOSED_SLEEP
			_act_lean = deg_to_rad(float(_b.get("nap_lean_deg", -3.0))) * signf(_lean_base)
		&"happy":
			_happy = 1.0
			_happy_to = 1.0
			_closed = MosslingRig.CLOSED_HAPPY
		_:
			_set_act(Act.IDLE)
	_update_rest_pose()
	_squash.snap(_rest_squash)
	_lean.snap(_lean_base + _act_lean)
	_ear.snap(_ear_rest)
	_ant.snap(_ant_rest)
	_tail.snap(_tail_rest)
	_push_uniforms(true)


# ================================================================= frame

func _process(delta: float) -> void:
	if rig == null or _frozen:
		return
	delta = minf(delta, 0.1)
	_update_touch(delta)
	_update_walk(delta)
	_update_act(delta)
	_update_face(delta)
	_update_springs(delta)
	_update_fx(delta)
	_update_light(delta)
	if _alpha != _alpha_to:
		_alpha = move_toward(_alpha, _alpha_to, delta * _alpha_rate)
		modulate.a = _alpha
		if _alpha <= 0.0 and leaving:
			left_hollow.emit(self)
	_push_uniforms(false)


func _update_touch(delta: float) -> void:
	if not _touching:
		return
	_touch_t += delta
	var pet: Dictionary = _cr.get("pet", {})
	var fill0 := float(pet.get("fill_start_ms", 150.0)) * MS
	var trig := float(pet.get("trigger_ms", 450.0)) * MS
	if not _petting:
		var prog := clampf((_touch_t - fill0) / maxf(trig - fill0, 0.01), 0.0, 1.0)
		_fx.set_ring(_ring_center(), _ring_radius(), prog, _touch_t >= fill0)
		if _touch_t >= trig:
			_begin_pet()
	else:
		_pet_t += delta
		_fx.set_ring(_ring_center(), _ring_radius(), 1.0, false)
		var hz := float(pet.get("wiggle_hz", 1.6))
		_wiggle = deg_to_rad(float(pet.get("wiggle_deg", 2.0))) * sin(TAU * hz * _pet_t) * _motion_k()
		# little hearts float up while the friend is being petted (the big bouquet is on release)
		_pet_heart_t -= delta
		if _pet_heart_t <= 0.0:
			_pet_heart_t = float(_b.get("pet_heart_every_s", 0.8))
			var side := 1.0 if int(_pet_t / maxf(_pet_heart_t, 0.1)) % 2 == 0 else -1.0
			_fx.hearts(_head_local() + Vector2(side * _w_px * 0.28, 0.0), 1, 0.0, float(_b.get("pet_heart_scale", 0.7)))


func _update_walk(delta: float) -> void:
	var prev_feet := _feet
	if _walking:
		if _bouncy:
			_step_hop(delta)
		else:
			_step_waddle(delta)
	else:
		_hop_f = move_toward(_hop_f, 1.0, delta * 4.0)
	_vel_x = (_feet.x - prev_feet.x) / maxf(delta, 1e-4)
	# body vertical acceleration drives the follow-through (Art Bible §5.7)
	var body_y := -_hop_h
	var vy := (body_y - _prev_body_y) / maxf(delta, 1e-4)
	var ay := (vy - _prev_body_vy) / maxf(delta, 1e-4)
	_prev_body_y = body_y
	_prev_body_vy = vy
	var acc_gain := float(_b.get("follow_accel_gain", 0.0009))
	var a_up := clampf(-ay, -6000.0, 6000.0)
	_ear.velocity += a_up * acc_gain * delta * 60.0 * 0.5
	_tail.velocity -= a_up * acc_gain * delta * 60.0 * 0.3
	_apply_position()


## Bouncy gait (Buttonbud, Capling, Puddlewump): crouch -> stretch in the air -> land squash ->
## jelly, 40-70 px per hop, 180-420 ms gaps (§5.7 Hop).
func _step_hop(delta: float) -> void:
	var hop: Dictionary = _cr.get("hop", {})
	var rm := Motion.reduce_motion
	_hop_t += delta
	match _hop_state:
		Hop.NONE:
			if not _next_hop_target():
				_finish_walk()
				return
			_hop_state = Hop.ANTIC
			_hop_t = 0.0
			var am: Array = hop.get("anticipation_ms", [90, 120])
			_hop_dur = rng.randf_range(float(am[0]), float(am[1])) * MS
		Hop.ANTIC:
			var u := clampf(_hop_t / _hop_dur, 0.0, 1.0)
			_hop_f = lerpf(1.0, _sq(float(hop.get("anticipation_squash", 0.92))), 1.0 - (1.0 - u) * (1.0 - u))
			if u >= 1.0:
				_hop_state = Hop.AIR
				_hop_t = 0.0
				_hop_dur = float(hop.get("air_ms", 300.0)) * MS
				var hb: Array = hop.get("height_bu", [0.18, 0.3])
				_hop_height_px = rng.randf_range(float(hb[0]), float(hb[1])) * _s_px
				_ear.kick(0.9)
				if absf(_hop_to.x - _hop_from.x) > 4.0:
					turn_to(signf(_hop_to.x - _hop_from.x) * 0.7)
		Hop.AIR:
			var u := clampf(_hop_t / _hop_dur, 0.0, 1.0)
			var e := u * u * (3.0 - 2.0 * u) if rm else u
			_feet = _hop_from.lerp(_hop_to, e)
			_hop_h = 0.0 if rm else 4.0 * _hop_height_px * u * (1.0 - u)
			var stretch := _sq(float(hop.get("air_stretch", 1.1)))
			var to := clampf(_hop_t / TAKEOFF_S, 0.0, 1.0)
			_hop_f = lerpf(_hop_f, lerpf(stretch, 1.0 + (stretch - 1.0) * 0.35, u), to)
			if u >= 1.0:
				_hop_h = 0.0
				_hop_state = Hop.GAP
				_hop_t = 0.0
				var gm: Array = hop.get("gap_ms", [180, 420])
				_hop_dur = rng.randf_range(float(gm[0]), float(gm[1])) * MS
				_hop_f = 1.0
				_squash.value = _sq(float(hop.get("land_squash", 0.88))) * _rest_squash
				_squash.velocity = 0.0
				_ear.kick(-1.4)
		Hop.GAP:
			if _hop_t >= _hop_dur:
				_hop_state = Hop.NONE


## Soft waddle for everyone else: a continuous shuffle with an alternating lean, a little bob and
## squash per step (calm, never linear-looking; GDD 20-30 dp/s).
func _step_waddle(delta: float) -> void:
	if _hop_state == Hop.NONE:
		if not _next_hop_target():
			_finish_walk()
			return
		_hop_state = Hop.AIR
		_hop_t = 0.0
		var dist := _hop_from.distance_to(_hop_to)
		_hop_dur = maxf(dist / maxf(_speed_px * depth, 1.0), 0.05)
		if absf(_hop_to.x - _hop_from.x) > 4.0:
			turn_to(signf(_hop_to.x - _hop_from.x) * 0.6)
	_hop_t += delta
	var u := clampf(_hop_t / _hop_dur, 0.0, 1.0)
	_feet = _hop_from.lerp(_hop_to, u)
	_waddle_phase += delta / WADDLE_STEP_S
	var step := fposmod(_waddle_phase, 1.0)
	var bob := sin(step * PI)
	var k := _motion_k()
	_hop_h = WADDLE_BOB_BU * _s_px * bob * k * SOFT_HOP_HEIGHT_K * 2.0
	_hop_f = 1.0 - WADDLE_SQUASH * (1.0 - bob) * k
	_act_lean = WADDLE_LEAN * sin(_waddle_phase * PI) * k
	if u >= 1.0:
		_hop_state = Hop.NONE
		if _path_i >= _path.size():
			_hop_h = 0.0
			_act_lean = 0.0


func _next_hop_target() -> bool:
	if _path_i >= _path.size():
		return false
	var hop: Dictionary = _cr.get("hop", {})
	var dm: Array = hop.get("distance_px", [40, 70])
	var max_step := (rng.randf_range(float(dm[0]), float(dm[1])) if _bouncy else WADDLE_STEP_PX * 3.0) * maxf(depth, 0.62)
	var target := _path[_path_i]
	var to := target - _feet
	_hop_from = _feet
	if to.length() <= max_step * 1.25:
		_hop_to = target
		_path_i += 1
	else:
		_hop_to = _feet + to.normalized() * max_step
	return true


func _finish_walk() -> void:
	_walking = false
	_hop_state = Hop.NONE
	_hop_h = 0.0
	_act_lean = 0.0
	walk_finished.emit()
	if _on_arrive.is_valid():
		var cb := _on_arrive
		_on_arrive = Callable()
		cb.call()


func _set_act(a: int) -> void:
	if _act == Act.NAP and a != Act.NAP:
		_wake()
	_act = a
	_act_t = 0.0
	_act_step = 0
	_act_lean = 0.0
	_chew_f = 1.0
	_update_rest_pose()


func _start_nap() -> void:
	_set_act(Act.NAP)
	_sleep_to = 1.0
	_nap_settle = 0.0
	_zzz_t = rng.randf_range(1.0, 3.0)
	asleep = true
	_set_breath(true)
	look_at_camera()


func _wake() -> void:
	if _sleep_to <= 0.0 and not asleep:
		return
	_sleep_to = 0.0
	asleep = false
	_closed = MosslingRig.CLOSED_OPEN
	_set_breath(false)
	_ear.kick(-0.8)


## Switches the breathing k (awake 3.5-4.5 s, asleep 5-6 s) keeping the phase continuous, so
## the breath never jumps (the shader adds fract(i_follow.w) to its phase).
func _set_breath(sleeping: bool) -> void:
	var k_new := rig.breath_k(sleeping, rng.randf())
	var g := Clock.g_time
	var wrap := Clock.g_time_wrap_s
	var ph := fposmod(g * _breath_k / wrap + seed01 + _breath_off, 1.0)
	_breath_k = k_new
	_breath_off = fposmod(ph - g * _breath_k / wrap - seed01, 1.0)


func _update_rest_pose() -> void:
	var b := _b
	var nap := _act == Act.NAP
	_rest_squash = float((_cr.get("sleep", {}) as Dictionary).get("squash_rest", 0.94)) if nap else 1.0
	if _rain and _sheltered and not nap:
		_rest_squash = float(b.get("rain_tuck_squash", 0.95))
	var ear_rest := rig.sleep_ear_droop(species_id) if nap else 0.0
	if _rain:
		ear_rest += float(b.get("rain_ear_flatten", 0.2))
	_ear_rest = ear_rest
	_tail_rest = -float(b.get("nap_tail_wrap", 0.6)) if nap else 0.0
	_ant_rest = float(b.get("nap_antenna_droop", 0.3)) * _facing if nap else 0.0
	if not _touching:
		_squash.target = _rest_squash


func _update_act(delta: float) -> void:
	_act_t += delta
	match _act:
		Act.NAP:
			_tick_nap(delta)
		Act.NIBBLE:
			_tick_nibble(delta)
		Act.PLAY:
			_tick_play(delta)
		Act.WANDER:
			_tick_wander(delta)
		Act.STREAM:
			_tick_stream(delta)
		Act.PEEK:
			_tick_peek(delta)
	if _act != Act.NAP and not _walking and not _petting and not _still:
		_tick_fidget(delta)
	# a clover in the mouth while nibbling (grows in / is eaten over nibble_leaf_ms)
	var leaf_to := 1.0 if _act == Act.NIBBLE and not _walking else 0.0
	_leaf = move_toward(_leaf, leaf_to, delta * 1000.0 / maxf(float(_b.get("nibble_leaf_ms", 320.0)), 1.0))


func _tick_nap(delta: float) -> void:
	_nap_settle = minf(_nap_settle + delta * _sleep_rate, 1.0)
	var e := 1.0 - pow(1.0 - _nap_settle, NAP_SETTLE_EASE)
	_act_lean = deg_to_rad(float(_b.get("nap_lean_deg", -3.0))) * signf(_lean_base) * e
	if _lid < 1.0 and _nap_settle < 1.0:
		_lid = maxf(_lid, smoothstep(0.0, 0.5, _nap_settle))
	if _nap_settle > 0.45 and not _petting:
		_closed = MosslingRig.CLOSED_SLEEP
	if _zzz_pause > 0.0:
		_zzz_pause -= delta
		return
	_zzz_t -= delta
	if _zzz_t <= 0.0 and _nap_settle >= 1.0:
		var k := float(_b.get("zzz_k", 124))
		_zzz_t = Clock.g_time_wrap_s / maxf(k, 1.0)
		if _fx.zzz_alive() < int(_b.get("zzz_max", 2)):
			var zs: Dictionary = rig.view().get("zzz_spawn", {})
			var side := -_facing
			var at := Vector2(side * _w_px * float(zs.get("side_bu", 0.5)), -_s_px * (0.85 + float(zs.get("up_bu", 0.1))))
			_fx.zzz(at, side * float(zs.get("drift_px", 34.0)))


## Nibble: lean toward the bed, chew bobs at 2 Hz for 1.5 s, pause 2-4 s, repeat (§5.7).
func _tick_nibble(delta: float) -> void:
	_act_next -= delta
	var lean := deg_to_rad(float(_b.get("nibble_lean_deg", 6.0))) * _act_dir
	if _act_step % 2 == 1:
		var hz := float(_b.get("nibble_chew_hz", 2.0))
		var chew := 0.5 - 0.5 * cos(TAU * hz * _act_t)
		_chew_f = lerpf(1.0, _sq(float(_b.get("nibble_chew_squash", 0.97))), chew)
		_act_lean = lean * (0.85 + 0.15 * chew)
	else:
		_chew_f = move_toward(_chew_f, 1.0, delta * 2.0)
		_act_lean = lerpf(_act_lean, lean * 0.35, minf(delta * 3.0, 1.0))
	if _act_next <= 0.0:
		_act_step += 1
		_act_t = 0.0
		if _act_step % 2 == 1:
			_act_next = float(_b.get("nibble_chew_s", 1.5))
			turn_to(_act_dir * 0.55)
		else:
			var pr: Array = _b.get("nibble_pause_s", [2.0, 4.0])
			_act_next = rng.randf_range(float(pr[0]), float(pr[1]))
			if rng.randf() < 0.5:
				turn_to(rng.randf_range(-0.3, 0.3))


## Play: small in-place hops (0.12 bu), facing the partner when there is one (§5.7).
func _tick_play(delta: float) -> void:
	_act_next -= delta
	if _play_partner != null and is_instance_valid(_play_partner):
		var dx := _play_partner.feet().x - _feet.x
		if absf(dx) > 2.0 and _hop_state == Hop.NONE:
			turn_to(signf(dx) * 0.8)
	if _hop_state == Hop.AIR:
		_hop_t += delta
		var u := clampf(_hop_t / _hop_dur, 0.0, 1.0)
		_hop_h = 4.0 * _hop_height_px * u * (1.0 - u) * _motion_k()
		_hop_f = lerpf(_sq(1.06), 1.0, u)
		if u >= 1.0:
			_hop_state = Hop.NONE
			_hop_h = 0.0
			_hop_f = 1.0
			_squash.value = _sq(0.92) * _rest_squash
			_ear.kick(-1.2)
	elif _act_next <= 0.0:
		_act_step += 1
		if _act_step % 4 == 0:
			var rr: Array = _b.get("play_rest_s", [1.5, 4.0])
			_act_next = rng.randf_range(float(rr[0]), float(rr[1]))
			if _play_partner == null and rng.randf() < 0.5:
				turn_to(-_look_to if absf(_look_to) > 0.1 else 0.6)
			_happy_to = 0.0
			_closed = MosslingRig.CLOSED_OPEN
		else:
			var gr: Array = _b.get("play_gap_s", [0.35, 0.9])
			_act_next = rng.randf_range(float(gr[0]), float(gr[1]))
			_hop_state = Hop.AIR
			_hop_t = 0.0
			_hop_dur = float((_cr.get("hop", {}) as Dictionary).get("air_ms", 300.0)) * MS * 0.85
			_hop_height_px = float(_b.get("play_hop_bu", 0.12)) * _s_px
			_ear.kick(0.8)
			if _act_step % 4 == 2:
				_happy_to = 1.0
				_closed = MosslingRig.CLOSED_HAPPY


## Wander: 1-3 hops to a random point within wander_radius_px of the anchor, then rest 3-8 s.
func _tick_wander(delta: float) -> void:
	if _walking:
		return
	_act_next -= delta
	if _act_next <= 0.0:
		var r := float(_b.get("wander_radius_px", 120.0)) * depth
		var a := rng.randf() * TAU
		var p := anchor + Vector2(cos(a), sin(a) * 0.45) * r * rng.randf_range(0.4, 1.0)
		var zone: Dictionary = _b.get("tend_zone_px", {})
		var zx: Array = zone.get("x", [110, 970])
		p.x = clampf(p.x, float(zx[0]), float(zx[1]))
		var path := PackedVector2Array([p])
		_walking = true
		_path = path
		_path_i = 0
		_on_arrive = func() -> void:
			_act_next = _rand_range("wander_rest_s")
			if rng.randf() < 0.4:
				look_at_camera()
			else:
				turn_to(rng.randf_range(-0.6, 0.6))


## Sit by the stream: watch the water, paw it now and then (every stream_paw_s, 12.8 s = k 47).
func _tick_stream(delta: float) -> void:
	_stream_t -= delta
	if _stream_t <= 0.0:
		_stream_t = float(_b.get("stream_paw_s", 12.766))
		_squash.value = _sq(0.95) * _rest_squash
		_lean.velocity += 0.25 * signf(_look_to + 1e-3)
		_ear.kick(0.6)


func _tick_peek(delta: float) -> void:
	_act_next -= delta
	if _act_step == 0:
		look_at_camera()
		_happy_to = 1.0
		_closed = MosslingRig.CLOSED_HAPPY
		_act_step = 1
	_wiggle = deg_to_rad(4.0) * sin(TAU * 1.2 * _act_t) * _motion_k()
	if _act_next <= 0.0:
		_wiggle = 0.0
		_happy_to = 0.0
		_closed = MosslingRig.CLOSED_OPEN
		leave_to(_exit_path_cache)


## Idle life for awake creatures: glances, ear twitches, little bloops and head tilts.
func _tick_fidget(delta: float) -> void:
	_look_next -= delta
	if _look_next <= 0.0:
		_look_next = _rand_range("look_s")
		if _act == Act.IDLE or _act == Act.WANDER or _act == Act.PLAY:
			var r := rng.randf()
			if r < 0.35:
				look_at_camera()
			else:
				turn_to(rng.randf_range(-0.75, 0.75))
	_fidget_next -= delta
	if _fidget_next <= 0.0:
		_fidget_next = _rand_range("fidget_s")
		match rng.randi_range(0, 3):
			0:
				_ear.kick(rng.randf_range(-1.6, 1.6))
			1:
				_squash.value = _rest_squash * _sq(0.965)
			2:
				_lean.velocity += rng.randf_range(-0.35, 0.35)
			3:
				_ant.kick(rng.randf_range(-1.8, 1.8))
				_tail.kick(rng.randf_range(-1.5, 1.5))


func _update_face(delta: float) -> void:
	# look crossfade (short, 200 ms) with a 0.97 dip at mid-turn
	if _look_t < 1.0:
		_look_t = minf(_look_t + delta / maxf(_look_dur, 0.01), 1.0)
		var e := _look_t * _look_t * (3.0 - 2.0 * _look_t)
		_look = lerpf(_look_from, _look_to, e)
		var dip := float(_b.get("look_turn_dip", 0.97))
		_turn_f = lerpf(1.0, _sq(dip), sin(_look_t * PI)) if absf(_look_to - _look_from) > 0.5 else 1.0
	else:
		_turn_f = 1.0
	_facing = move_toward(_facing, _facing_to, delta / maxf(_look_dur, 0.01) * 2.0)
	_sleep = move_toward(_sleep, _sleep_to, delta * _sleep_rate)
	_happy = move_toward(_happy, _happy_to, delta * 5.0)
	if _reopen_t >= 0.0:
		_reopen_t -= delta
		if _reopen_t < 0.0:
			_happy_to = 0.0
			_closed = MosslingRig.CLOSED_SLEEP if asleep else MosslingRig.CLOSED_OPEN
	if _overshoot_hold > 0.0:
		_overshoot_hold -= delta
		if _overshoot_hold <= 0.0:
			_squash.target = _rest_squash
	_update_blink(delta)
	if _tag_t > 0.0:
		_tag_t -= delta
		var fade := float((rig.content.motion.get("durations_ms", {}) as Dictionary).get("standard", 320.0)) * MS
		var total := float(_b.get("name_tag_ms", 2000.0)) * MS
		var shown := total - _tag_t
		_tag.modulate.a = clampf(minf(shown / fade, _tag_t / fade), 0.0, 1.0)
		_tag.visible = _tag_t > 0.0
		_tag.position.y = -(_s_px * (1.0 + rig.top_extent_bu(species_id)) + _tag.size.y + 12.0) \
			- float(_b.get("name_tag_rise_px", 18.0)) * (1.0 - pow(1.0 - clampf(shown / fade, 0.0, 1.0), 3.0)) - _hop_h


## Random blinks every 2-6 s, 15 % doubles; close 50 / hold 20 / open 70 ms. Suppressed asleep,
## while petted and in the air (motion_tokens creature.blink).
func _update_blink(delta: float) -> void:
	if asleep or _petting or _hop_h > 1.0 or _closed != MosslingRig.CLOSED_OPEN or _still:
		if not asleep:
			_lid = move_toward(_lid, 0.0, delta * 8.0)
		return
	var bl: Dictionary = _cr.get("blink", {})
	var close_s := float(bl.get("close_ms", 50.0)) * MS
	var hold_s := float(bl.get("hold_ms", 20.0)) * MS
	var open_s := float(bl.get("open_ms", 70.0)) * MS
	_blink_t += delta
	match _blink_phase:
		0:
			_lid = move_toward(_lid, 0.0, delta * 6.0)
			if _blink_t >= _blink_next:
				_blink_phase = 1
				_blink_t = 0.0
		1:
			_lid = clampf(_blink_t / close_s, 0.0, 1.0)
			if _blink_t >= close_s:
				_blink_phase = 2
				_blink_t = 0.0
		2:
			_lid = 1.0
			if _blink_t >= hold_s:
				_blink_phase = 3
				_blink_t = 0.0
		3:
			var u := clampf(_blink_t / open_s, 0.0, 1.0)
			_lid = 1.0 - (1.0 - (1.0 - u) * (1.0 - u))
			if u >= 1.0:
				if _blink_double:
					_blink_double = false
					_blink_phase = 4
				else:
					_blink_phase = 0
					_schedule_blink()
				_blink_t = 0.0
		4:
			_lid = 0.0
			if _blink_t >= float(bl.get("double_gap_ms", 110.0)) * MS:
				_blink_phase = 1
				_blink_t = 0.0


func _schedule_blink() -> void:
	var bl: Dictionary = _cr.get("blink", {})
	var iv: Array = bl.get("interval_s", [2.0, 6.0])
	_blink_next = rng.randf_range(float(iv[0]), float(iv[1]))
	_blink_double = rng.randf() < float(bl.get(LID_DOUBLE_P_KEY, 0.15))
	_blink_t = 0.0


func _update_springs(delta: float) -> void:
	var pet: Dictionary = _cr.get("pet", {})
	var lean_t := _lean_base + _act_lean
	if _petting:
		var lean_max := deg_to_rad(float(pet.get("lean_deg_max", 4.0)))
		var dx := (_touch_at.x - _feet.x) / maxf(_w_px * depth, 1.0)
		lean_t = clampf(dx, -1.0, 1.0) * lean_max
		_ear.target = _ear_rest + float(_b.get("pet_ear_flatten", 0.15))
	else:
		_ear.target = _ear_rest
	_lean.target = lean_t
	var vel_gain := float(_b.get("follow_vel_gain", 0.0006))
	_ant.target = _ant_rest - _vel_x * vel_gain
	_tail.target = _tail_rest
	_squash.step(delta)
	_lean.step(delta)
	_ear.step(delta)
	_ant.step(delta)
	_tail.step(delta)


func _update_fx(_delta: float) -> void:
	var show_umbrella := _rain and _wants_umbrella and not _sheltered and not leaving
	var u: Dictionary = rig.view().get("umbrella", {})
	# rooted at the paw on the front-facing side, held up behind the head
	var side := _facing
	var base := Vector2(side * _w_px * float(u.get("paw_x_bu", 0.42)), -_s_px * float(u.get("paw_y_bu", 0.5)) - _hop_h)
	# sized by the body height, so the canopy always clears the crown (and ears)
	var tall := 1.0 + rig.top_extent_bu(species_id) * float(u.get("top_k", 0.5))
	var size_k := _s_px * tall / float(u.get("ref_height_px", 170.0))
	_fx.set_umbrella(show_umbrella, base, _ear.value * 0.6 + _lean.value, side, size_k)


## Lantern light at the feet (LampRegistry, the same falloff as the ground pools), refreshed at
## view.lamp_refresh_s (2 Hz, Art Bible §5.5 slot 14). i_light.xy is local (y up).
func _update_light(delta: float) -> void:
	_lamp_t -= delta
	if _lamp_t > 0.0:
		return
	_lamp_t = float(rig.view().get("lamp_refresh_s", 0.5))
	_light = lamp_light(_feet, rig.view().get("lamp", {}))


## Strongest lamp on a creature at [param feet] (design px): (dir x, dir y up, weight, 0). A body
## stands up out of the pool, so it catches a lantern from further away than the ground does:
## reach = reach_mul x pool radius, weight = peak x (1 - q)^falloff_pow (Art Bible §5.5 slot 14).
static func lamp_light(feet_design: Vector2, cfg: Dictionary) -> Vector4:
	var reach := float(cfg.get("reach_mul", 2.2))
	var peak := float(cfg.get("peak", 0.45))
	var fpow := float(cfg.get("falloff_pow", 2.0))
	var best := Vector4.ZERO
	for l: Vector4 in LampRegistry.lamps():
		var d := Vector2(l.x, l.y) - feet_design
		var q := d.length() / maxf(l.z * reach, 1.0)
		if q >= 1.0:
			continue
		var w := peak * clampf(l.w, 0.0, 1.0) * pow(1.0 - q, fpow)
		if w > best.z:
			var dir := d.normalized() if d.length_squared() > 1.0 else Vector2(0.0, -1.0)
			best = Vector4(dir.x, -dir.y, w, 0.0)
	return best


## Grass nestle (i_misc.y): on the meadow, off on props and while hopping.
func _nestle_now() -> float:
	var base := 1.0
	if not _walking and _hop_state == Hop.NONE:
		base = rig.nestle_at(spot_id)
	elif _sort_bias != 0.0:
		base = 0.0
	return base * (1.0 - smoothstep(0.0, rig.nestle_hop_fade_px(), _hop_h))


func _apply_position() -> void:
	depth = _scale_override if _scale_override > 0.0 else _depth_at(_feet.y)
	position = Vector2(_feet.x, _feet.y + _sort_bias)
	if _visual != null:
		_visual.position = Vector2(0.0, -_sort_bias)
		_visual.scale = Vector2.ONE * depth
		_body.position = Vector2(0.0, -_hop_h)
		if _shadow_host != null:
			_shadow.position = _feet - _shadow_host.position
			_shadow.scale = Vector2(_w_px, _s_px) * depth


func _depth_at(y: float) -> float:
	var ds: Dictionary = rig.view().get("depth_scale", {}) if rig != null else {}
	var y0 := float(ds.get("y0", 760.0))
	var span := float(ds.get("span", 740.0))
	var lo := float(ds.get("min", 0.62))
	var hi := float(ds.get("max", 1.0))
	return clampf(lo + (hi - lo) * (y - y0) / span, lo, hi)


## Writes the animated instance uniforms (slots 11-13) and the shadow, only when they change.
func _push_uniforms(force: bool) -> void:
	var squash := _squash.value * _hop_f * _chew_f * _turn_f
	var lean := _lean.value + _wiggle
	var anim := Vector4(squash, lean, _lid, _look)
	if force or not _vec_eq(anim, _u_anim):
		_u_anim = anim
		_body.set_instance_shader_parameter(MosslingRig.I_ANIM, anim)
	var follow := Vector4(_ear.value, _ant.value, _tail.value, _breath_k + _breath_off)
	if force or not _vec_eq(follow, _u_follow):
		_u_follow = follow
		_body.set_instance_shader_parameter(MosslingRig.I_FOLLOW, follow)
	var state := Vector4(_sleep, _happy, _facing, seed01)
	if force or not _vec_eq(state, _u_state):
		_u_state = state
		_body.set_instance_shader_parameter(MosslingRig.I_STATE, state)
	# i_misc.z = feet + UMB_CODE x umbrella alpha; i_misc.w = closed id + 3 x leaf step
	# (mossling_fur.gdshader decodes both)
	var feet_flag := 1.0 if _feet_nubs else 0.0
	var misc := Vector4(_u_misc.x, _nestle_now(), feet_flag + UMB_CODE * _fx.umbrella_alpha(),
		float(_closed) + 3.0 * roundf(_leaf * LEAF_STEPS))
	if force or misc != _u_misc:
		_u_misc = misc
		_body.set_instance_shader_parameter(MosslingRig.I_MISC, misc)
	var light := Vector4(_light.x, _light.y, _light.z, -_focal)
	if force or not _vec_eq(light, _u_light):
		_u_light = light
		_body.set_instance_shader_parameter(MosslingRig.I_LIGHT, light)
	# shadow (creature_shadow.gdshader): hop, squash, lean, alpha in one instance uniform; the
	# modulate stays white so the meadow shadows batch (the host shadow carries the fade here)
	var hop_n := clampf(_hop_h / maxf(_s_px * 0.3, 1.0), 0.0, 1.0)
	var sh_a := (1.0 - SHELTER_SHADOW_K * (1.0 if _sheltered else 0.0)) * (_alpha if _shadow_host != null else 1.0)
	var sh := Vector4(hop_n, squash, lean, sh_a)
	if force or not _vec_eq(sh, _u_shadow):
		_u_shadow = sh
		_shadow.set_instance_shader_parameter(&"i_shadow", sh)
	if _shadow_host != null:
		_shadow.visible = is_visible_in_tree()


func _build_tag() -> void:
	_tag = PanelContainer.new()
	_tag.name = "NameTag"
	_tag.theme_type_variation = &"Chip"
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.visible = false
	_tag_label = Label.new()
	_tag_label.theme_type_variation = &"StrongLabel"
	_tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.add_child(_tag_label)
	_visual.add_child(_tag)
	# theme propagation stops at the world's Node2Ds: attach the UI theme (rebuilt with text size)
	UiTheme.attach(_tag)


func _head_local() -> Vector2:
	return Vector2(0.0, -_s_px * HEAD_BU - _hop_h)


func _ring_center() -> Vector2:
	return Vector2(0.0, -_s_px * 0.5 - _hop_h)


func _ring_radius() -> float:
	return maxf(_w_px, _s_px) * 0.62


## Squash deviations scale by reduce_motion.squash_mul under Reduce Motion (§10.4).
func _sq(s: float) -> float:
	if not Motion.reduce_motion:
		return s
	var rm: Dictionary = rig.content.motion.get("reduce_motion", {})
	return 1.0 + (s - 1.0) * float(rm.get("squash_mul", 0.5))


func _motion_k() -> float:
	return Clock.g_motion


func _rand_range(key: String) -> float:
	var r: Array = _b.get(key, [1.0, 2.0])
	return rng.randf_range(float(r[0]), float(r[1]))


static func _vec_eq(a: Vector4, b: Vector4) -> bool:
	return absf(a.x - b.x) < UNIFORM_EPS and absf(a.y - b.y) < UNIFORM_EPS and absf(a.z - b.z) < UNIFORM_EPS \
		and absf(a.w - b.w) < UNIFORM_EPS
