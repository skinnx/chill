class_name WishBubble
extends Node2D
## The in-world thought bubble of a friend's wish (ACTIVE_WISHES §7.1; GDD §14.11 b FE-W).
##
## A felt cloud (44 dp) with two trailing dots toward the head and the wish icon (28 dp), both
## regions of the one WishIcons atlas drawn by this one CanvasItem: ONE draw call per bubble, at
## most two on screen. It is part of the mossling's visual, NOT a world hit target (§8.1): it never
## takes a press; reading the wish is a tap on the friend.
##
##  * In: fade + rise over presentation.bubble_in_ms (600 ms; Reduce Motion: a 150 ms cross-fade).
##  * Idle: a 3 dp bob on a 600/k loop (motion_tokens loops_k.seed_bob), none under Reduce Motion.
##  * Waiting (napping friend, Active F3 edit mode): presentation.napping_bubble_alpha (45 %); a
##    tiny "z" rides on the cloud while the friend naps.
##  * Out on grant: the cloud pops into 5 petals over bubble_out_ms (400 ms; Reduce Motion x0.3),
##    then the node frees itself. A plain hide (the friend leaves) fades it out.
##  * Night: the cream felt takes the night chrome tint (palettes ui_derived.hud_night_tint).
##
## The bubble draws in design px around its own origin (the creature places the origin at its head
## anchor + bubble_offset_dp); [member mirrored] flips the cloud to the friend's left near the right
## edge (the icon never mirrors).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## Popped and faded out (the creature drops its reference).
signal finished(b: WishBubble)

enum Phase { IN, IDLE, POP, OUT, GONE }

const MS := 0.001
## Above the y-sorted Play layer, so a friend walking in front never hides a wish (ACTIVE_WISHES
## §7.1 "follows the creature like the name tag", drawn over the hollow).
const BUBBLE_Z := 1
## The cloud's rise while it fades in (design px; 4 dp).
const RISE_PX := 12.0
## The cloud's scale as it appears (a soft swell to 1).
const IN_SCALE := 0.82
## Grant pop: the cloud swells to this scale while it fades over the first POP_CLOUD_K of the pop.
const POP_SCALE := 1.16
const POP_CLOUD_K := 0.55
## Petals fly this far from the cloud's centre (design px) and spin this much (rad) over the pop.
const PETAL_TRAVEL_PX := 96.0
const PETAL_SPIN := 2.4
const PETAL_PX := 42.0
const PETALS := 5
## The icon's draw size inside the cloud (28 dp = 84 design px) and the "z"'s.
const ICON_DRAW_PX := 84.0
const Z_DRAW_PX := 30.0
## Bob loop k when motion_tokens has no seed_bob (600 / k s).
const DEFAULT_BOB_K := 120.0
## spots.json frame.px_per_dp (design px per dp).
const PX_PER_DP := 3.0

var icon: StringName = &""
var mirrored: bool = false:
	set(v):
		if v != mirrored:
			mirrored = v
			queue_redraw()
## Waiting dim (napping friend or edit mode) and the sleepy "z".
var waiting: bool = false
var sleepy: bool = false:
	set(v):
		if v != sleepy:
			sleepy = v
			queue_redraw()
## Tucked away while the friend's name tag carries the wish (the tag reads over the hollow).
var tucked: bool = false
var phase: int = Phase.IN

var _t: float = 0.0
var _in_s: float = 0.6
var _out_s: float = 0.4
var _fade_s: float = 0.32
var _bob_px: float = 9.0
var _bob_k: float = DEFAULT_BOB_K
var _seed: float = 0.0
var _wait_alpha: float = 0.45
var _alpha: float = 0.0
var _dim: float = 1.0
var _rm: bool = false
var _petal_n: int = PETALS
var _petal_tint: Color = Color.WHITE
var _night_k: float = 0.0
var _night_tint: Color = Color.WHITE
var _frozen: bool = false
var _base_y: float = 0.0


## [param p_icon]: wishes.json icon id; [param seed01] staggers the bob; [param instant] skips the
## fade in (the world loaded with the wish already open).
func setup(p_icon: StringName, seed01: float, instant: bool = false) -> void:
	icon = p_icon
	_seed = seed01
	z_index = BUBBLE_Z
	z_as_relative = true
	var content := ContentRegistry.content
	var pres: Dictionary = (content.wishes_doc.get("presentation", {}) as Dictionary) if content != null else {}
	_in_s = float(pres.get("bubble_in_ms", 600.0)) * MS
	_out_s = float(pres.get("bubble_out_ms", 400.0)) * MS
	_bob_px = float(pres.get("bubble_bob_dp", 3.0)) * PX_PER_DP
	_wait_alpha = float(pres.get("napping_bubble_alpha", 0.45))
	var motion: Dictionary = content.motion if content != null else {}
	var loops: Dictionary = motion.get("loops_k", {})
	var k: Array = loops.get("seed_bob", [DEFAULT_BOB_K, DEFAULT_BOB_K])
	_bob_k = float(k[0])
	var dur: Dictionary = motion.get("durations_ms", {})
	_fade_s = float(dur.get("standard", 320.0)) * MS
	_rm = Motion.reduce_motion
	if _rm:
		var rm: Dictionary = motion.get("reduce_motion", {})
		var cross := float(dur.get("reduce_motion_crossfade", 150.0)) * MS
		_in_s = cross
		_fade_s = cross
		_petal_n = maxi(1, roundi(PETALS * float(rm.get("particles_mul", 0.3))))
	_night_tint = UiTokens.color(&"hud_night_tint")
	phase = Phase.IDLE if instant else Phase.IN
	_t = _in_s if instant else 0.0
	_alpha = 1.0 if instant else 0.0
	_apply()
	queue_redraw()


## Grant: pop into petals (tinted [param tint], the gift petal's colour) and free.
func pop(tint: Color = Color.WHITE) -> void:
	if phase == Phase.POP or phase == Phase.GONE:
		return
	_petal_tint = tint
	phase = Phase.POP
	_t = 0.0
	queue_redraw()


## A plain hide (the friend left, the wish was held): fade out and free.
func dismiss() -> void:
	if phase == Phase.POP or phase == Phase.OUT or phase == Phase.GONE:
		return
	phase = Phase.OUT
	_t = 0.0


## QA: holds the bubble exactly where it is (a still of the pop mid-way).
func freeze(on: bool) -> void:
	_frozen = on


func is_leaving() -> bool:
	return phase == Phase.POP or phase == Phase.OUT or phase == Phase.GONE


## 0..1 progress of the grant pop (tests, QA).
func pop_progress() -> float:
	return clampf(_t / maxf(_out_s, 1e-3), 0.0, 1.0) if phase == Phase.POP else 0.0


func _process(delta: float) -> void:
	if _frozen:
		return
	_t += delta
	var dim_to := 0.0 if tucked else (_wait_alpha if waiting else 1.0)
	_dim = move_toward(_dim, dim_to, delta / maxf(_fade_s, 0.05))
	var want := _night_target()
	if not is_equal_approx(want, _night_k):
		_night_k = move_toward(_night_k, want, delta / maxf(_fade_s * 2.0, 0.05))
		queue_redraw()
	match phase:
		Phase.IN:
			if _t >= _in_s:
				phase = Phase.IDLE
		Phase.POP:
			queue_redraw()
			if _t >= _out_s:
				_finish()
				return
		Phase.OUT:
			if _t >= _fade_s:
				_finish()
				return
	_apply()


func _finish() -> void:
	phase = Phase.GONE
	visible = false
	finished.emit(self)
	queue_free()


## Alpha, rise and bob (node properties only: no redraw while idle).
func _apply() -> void:
	var a := 1.0
	var rise := 0.0
	var s := 1.0
	match phase:
		Phase.IN:
			var u := clampf(_t / maxf(_in_s, 1e-3), 0.0, 1.0)
			var e := 1.0 - pow(1.0 - u, 3.0)
			# fade >= 300 ms (V5), the rise and swell ride the same ease
			a = clampf(_t / maxf(minf(_in_s, maxf(_fade_s, 0.3)), 1e-3), 0.0, 1.0)
			if not _rm:
				rise = (1.0 - e) * RISE_PX
				s = lerpf(IN_SCALE, 1.0, e)
		Phase.OUT:
			a = 1.0 - clampf(_t / maxf(_fade_s, 1e-3), 0.0, 1.0)
	_alpha = a
	modulate.a = a * _dim
	var bob := 0.0
	if not _rm and phase != Phase.POP:
		bob = sin(TAU * (Clock.g_time * _bob_k / maxf(Clock.g_time_wrap_s, 1.0) + _seed)) * _bob_px * Clock.g_motion
	position.y = _base_y + rise + bob
	scale = Vector2(s, s)


## The bubble origin in the parent's space (the creature calls this every frame it moves).
func place(at: Vector2) -> void:
	position.x = at.x
	_base_y = at.y
	_apply()


func _night_target() -> float:
	return 1.0 if UiTokens.night_scheme else 0.0


func _draw() -> void:
	var tex := WishIcons.texture()
	if tex == null:
		return
	var felt := Color.WHITE.lerp(_night_tint, _night_k)
	var cloud := WishIcons.region(WishIcons.BUBBLE)
	var k := 1.0 / WishIcons.RASTER_K
	var size := cloud.size * k
	# the cloud's body centre sits on the origin; mirrored flips it to the left (dots to the right)
	var c := WishIcons.CLOUD_CENTRE
	var pop_u := pop_progress()
	var cloud_a := 1.0
	var cloud_s := 1.0
	if phase == Phase.POP:
		var cu := clampf(pop_u / POP_CLOUD_K, 0.0, 1.0)
		cloud_a = 1.0 - cu
		cloud_s = lerpf(1.0, POP_SCALE, 1.0 - pow(1.0 - cu, 2.0)) if not _rm else 1.0
	if cloud_a > 0.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-cloud_s if mirrored else cloud_s, cloud_s))
		draw_texture_rect_region(tex, Rect2(-c, size), cloud, Color(felt, cloud_a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(cloud_s, cloud_s))
		var ic := WishIcons.region(WishIcons.resolve(icon))
		var ip := ICON_DRAW_PX
		draw_texture_rect_region(tex, Rect2(Vector2(-ip * 0.5, -ip * 0.5), Vector2(ip, ip)), ic,
			Color(Color.WHITE.lerp(_night_tint, _night_k * 0.35), cloud_a))
		if sleepy:
			var zr := WishIcons.region(WishIcons.SLEEP_Z)
			var zx := (-1.0 if mirrored else 1.0) * (size.x * 0.5 - Z_DRAW_PX * 0.2)
			draw_texture_rect_region(tex, Rect2(Vector2(zx - Z_DRAW_PX * 0.5, -size.y * 0.5 - Z_DRAW_PX * 0.1),
				Vector2(Z_DRAW_PX, Z_DRAW_PX)), zr, Color(1, 1, 1, cloud_a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if phase == Phase.POP:
		_draw_petals(tex, pop_u)


## Five petals burst from the cloud, ease out, spin and fade (one atlas region, same draw call).
func _draw_petals(tex: Texture2D, u: float) -> void:
	var pr := WishIcons.region(WishIcons.PETAL)
	var e := 1.0 - pow(1.0 - u, 2.5)
	var a := 1.0 - u * u
	for i in _petal_n:
		var ang := -PI * 0.5 + TAU * (float(i) + _seed) / float(_petal_n)
		var d := Vector2(cos(ang), sin(ang) * 0.8) * PETAL_TRAVEL_PX * e
		d.y += 24.0 * u * u  # they drift down a little as they slow (petals, not sparks)
		var rot := ang + PI * 0.5 + PETAL_SPIN * e * (1.0 if i % 2 == 0 else -1.0)
		draw_set_transform(d, rot, Vector2.ONE)
		var px := PETAL_PX * lerpf(1.0, 0.7, u)
		draw_texture_rect_region(tex, Rect2(Vector2(-px * 0.5, -px * 0.5), Vector2(px, px)), pr,
			Color(_petal_tint, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
