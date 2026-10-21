class_name MosslingFx
extends Node2D
## Feedback stamps above one mossling (Art Bible §5.2 Fx, §5.7, §10.3): hearts on pet release,
## the sleepy "z", sparkles, the long-press fill ring and the rain leaf umbrella. Every stamp is a
## pooled SdfQuad on one of five shared creature_fx materials (MosslingRig.make_fx_materials);
## per-stamp alpha (and the ring's progress) ride on self_modulate, so the stamps use no instance
## uniforms (GLES3 reserves 16 global-buffer slots per item that does). Nothing is allocated after
## setup; all timings come from creature_rig.json view.behaviour and motion_tokens.json creature.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const KIND_HEART := 0
const KIND_Z := 1
const KIND_SPARKLE := 2
const KIND_RING := 3
const KIND_UMBRELLA := 4
const HEART_POOL := 5
const Z_POOL := 2
const SPARKLE_POOL := 6
const HEART_HALF_PX := 22.0
const Z_HALF_PX := 15.0
const SPARKLE_HALF_PX := 12.0
const UMBRELLA_HALF_PX := 92.0
const SPARKLE_LIFE_S := 0.45
const SPARKLE_RADIUS_PX := 70.0
## Heart x offsets and sideways sway (px) so three hearts read as a little bouquet.
const HEART_SPREAD_PX := 26.0
const HEART_SWAY_PX := 6.0
const HEART_POP_S := 0.22
const Z_WOBBLE_PX := 3.0
const MS := 0.001


## Stamp state (pooled; inactive stamps are hidden).
class Stamp:
	var quad: SdfQuad
	var kind: int = 0
	var active: bool = false
	var t: float = 0.0
	var life: float = 1.0
	var delay: float = 0.0
	var from: Vector2 = Vector2.ZERO
	var travel: Vector2 = Vector2.ZERO
	var scale_from: float = 1.0
	var scale_to: float = 1.0
	var peak_alpha: float = 1.0
	var phase: float = 0.0


var _hearts: Array[Stamp] = []
var _zs: Array[Stamp] = []
var _sparkles: Array[Stamp] = []
var _ring: SdfQuad
var _umbrella: SdfQuad
var _ring_alpha: float = 0.0
var _ring_target: float = 0.0
var _ring_progress: float = 0.0
var _umbrella_alpha: float = 0.0
var _umbrella_target: float = 0.0
var _umbrella_fade_s: float = 0.4
var _umbrella_tilt: float = 0.0
var _heart_rise_px: float = 70.0
var _heart_life_s: float = 1.1
var _zzz_rise_px: float = 40.0
var _zzz_drift_px: float = 16.0
var _zzz_life_s: float = 3.0
var _zzz_scale: Vector2 = Vector2(0.8, 1.1)
var _zzz_alpha: float = 0.8
var _ring_fade_s: float = 0.2


## [param materials]: MosslingRig.make_fx_materials() (shared by every mossling).
func setup(rig: MosslingRig, materials: Dictionary) -> void:
	var b := rig.behaviour()
	var sleep: Dictionary = (rig.content.motion.get("creature", {}) as Dictionary).get("sleep", {})
	_heart_rise_px = float(b.get("heart_rise_px", _heart_rise_px))
	_heart_life_s = float(b.get("heart_life_s", _heart_life_s))
	_zzz_rise_px = float(sleep.get("zzz_rise_px", _zzz_rise_px))
	_zzz_life_s = float(sleep.get("zzz_life_s", _zzz_life_s))
	_zzz_drift_px = float(b.get("zzz_drift_px", _zzz_drift_px))
	var zs: Array = b.get("zzz_scale", [0.8, 1.1])
	_zzz_scale = Vector2(float(zs[0]), float(zs[1]))
	_zzz_alpha = float(b.get("zzz_alpha", _zzz_alpha))
	_umbrella_fade_s = float(b.get("umbrella_fade_ms", 400.0)) * MS
	_umbrella_tilt = deg_to_rad(float(b.get("umbrella_tilt_deg", 12.0)))
	_ring_fade_s = float((rig.content.motion.get("durations_ms", {}) as Dictionary).get("short", 200.0)) * MS
	# the umbrella first, so hearts and z's draw over it
	_umbrella = _make_quad(materials[KIND_UMBRELLA], UMBRELLA_HALF_PX)
	for i in HEART_POOL:
		_hearts.append(_make_stamp(materials[KIND_HEART], KIND_HEART, HEART_HALF_PX))
	for i in Z_POOL:
		_zs.append(_make_stamp(materials[KIND_Z], KIND_Z, Z_HALF_PX))
	for i in SPARKLE_POOL:
		_sparkles.append(_make_stamp(materials[KIND_SPARKLE], KIND_SPARKLE, SPARKLE_HALF_PX))
	_ring = _make_quad(materials[KIND_RING], 1.0)


## [param count] hearts rise from [param head] (local px), staggered (pet release, §5.7).
func hearts(head: Vector2, count: int, stagger_s: float) -> void:
	var n := 0
	for s: Stamp in _hearts:
		if n >= count:
			break
		if s.active:
			continue
		var side := float(n) - float(count - 1) * 0.5
		_start(s, head + Vector2(side * HEART_SPREAD_PX, 0.0), Vector2(side * HEART_SWAY_PX, -_heart_rise_px),
			_heart_life_s, float(n) * stagger_s, 0.6, 1.0, 1.0)
		s.phase = float(n) * 1.7
		n += 1


## One sleepy "z" (rises and drifts right over zzz_life_s; at most Z_POOL alive).
func zzz(head: Vector2) -> bool:
	for s: Stamp in _zs:
		if not s.active:
			_start(s, head, Vector2(_zzz_drift_px, -_zzz_rise_px), _zzz_life_s, 0.0, _zzz_scale.x, _zzz_scale.y,
				_zzz_alpha)
			return true
	return false


func sparkles(center: Vector2, count: int) -> void:
	var n := 0
	for s: Stamp in _sparkles:
		if n >= count:
			break
		if s.active:
			continue
		var a := TAU * float(n) / float(maxi(count, 1)) + 0.4
		_start(s, center, Vector2(cos(a), sin(a)) * SPARKLE_RADIUS_PX, SPARKLE_LIFE_S, float(n) * 0.03, 0.4, 1.0, 1.0)
		n += 1


func zzz_alive() -> int:
	var n := 0
	for s: Stamp in _zs:
		if s.active:
			n += 1
	return n


func hearts_alive() -> int:
	var n := 0
	for s: Stamp in _hearts:
		if s.active:
			n += 1
	return n


## Long-press fill ring around the body: radius px, progress 0..1, on/off (fades over `short`).
func set_ring(center: Vector2, radius: float, progress: float, visible_on: bool) -> void:
	_ring.position = center
	_ring.scale = Vector2.ONE * maxf(radius, 1.0)
	_ring_progress = clampf(progress, 0.0, 1.0)
	_ring_target = 1.0 if visible_on else 0.0
	_ring.self_modulate = Color(_ring_progress, 1.0, 1.0, _ring_alpha)


## Rain leaf umbrella over the head (fades over umbrella_fade_ms; sways with [param sway] rad).
func set_umbrella(on: bool, head: Vector2, sway: float) -> void:
	_umbrella_target = 1.0 if on else 0.0
	_umbrella.position = head + Vector2(0.0, -UMBRELLA_HALF_PX * 0.4)
	_umbrella.rotation = -_umbrella_tilt + sway


func umbrella_visible() -> bool:
	return _umbrella_alpha > 0.0


func _process(delta: float) -> void:
	for s: Stamp in _hearts:
		_tick_heart(s, delta)
	for s: Stamp in _zs:
		_tick_float(s, delta)
	for s: Stamp in _sparkles:
		_tick_float(s, delta)
	if _ring_alpha != _ring_target:
		_ring_alpha = move_toward(_ring_alpha, _ring_target, delta / maxf(_ring_fade_s, 0.01))
	_ring.visible = _ring_alpha > 0.0
	_ring.self_modulate = Color(_ring_progress, 1.0, 1.0, _ring_alpha)
	if _umbrella_alpha != _umbrella_target:
		_umbrella_alpha = move_toward(_umbrella_alpha, _umbrella_target, delta / maxf(_umbrella_fade_s, 0.01))
		_umbrella.visible = _umbrella_alpha > 0.0
		_umbrella.self_modulate = Color(1.0, 1.0, 1.0, _umbrella_alpha)


func _make_stamp(material: ShaderMaterial, kind: int, half: float) -> Stamp:
	var s := Stamp.new()
	s.kind = kind
	s.quad = _make_quad(material, half)
	return s


func _make_quad(material: ShaderMaterial, half: float) -> SdfQuad:
	var q := SdfQuad.new()
	q.material = material
	q.rect = Rect2(-half, -half, 2.0 * half, 2.0 * half)
	q.visible = false
	q.self_modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(q)
	return q


func _start(s: Stamp, from: Vector2, travel: Vector2, life: float, delay: float, s0: float, s1: float,
		peak: float) -> void:
	s.active = true
	s.t = 0.0
	s.delay = delay
	s.life = maxf(life, 0.05)
	s.from = from
	s.travel = travel
	s.scale_from = s0
	s.scale_to = s1
	s.peak_alpha = peak
	s.quad.position = from
	s.quad.visible = false


## Hearts pop in, rise on an ease-out curve with a gentle sway and fade at the end (never pop-in:
## alpha ramps over the first 12 % of the life).
func _tick_heart(s: Stamp, delta: float) -> void:
	if not s.active:
		return
	if s.delay > 0.0:
		s.delay -= delta
		return
	s.t += delta
	var u := clampf(s.t / s.life, 0.0, 1.0)
	var rise := 1.0 - pow(1.0 - u, 2.2)
	var pop := clampf(s.t / HEART_POP_S, 0.0, 1.0)
	var pop_s := 1.0 + 0.18 * sin(pop * PI) * (1.0 - pop * 0.5)
	var sc := lerpf(s.scale_from, s.scale_to, 1.0 - pow(1.0 - pop, 3.0)) * pop_s
	var alpha := smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.62, 1.0, u)) * s.peak_alpha
	s.quad.position = s.from + Vector2(s.travel.x * rise + sin(u * TAU * 0.9 + s.phase) * HEART_SWAY_PX * 0.5,
		s.travel.y * rise)
	s.quad.scale = Vector2.ONE * sc
	s.quad.visible = true
	s.quad.self_modulate = Color(1.0, 1.0, 1.0, alpha)
	if u >= 1.0:
		s.active = false
		s.quad.visible = false


## z's and sparkles: eased travel, scale ramp, alpha 0 -> peak -> 0 (V5: no pop-in).
func _tick_float(s: Stamp, delta: float) -> void:
	if not s.active:
		return
	if s.delay > 0.0:
		s.delay -= delta
		return
	s.t += delta
	var u := clampf(s.t / s.life, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - u, 1.6)
	var alpha := smoothstep(0.0, 0.25, u) * (1.0 - smoothstep(0.55, 1.0, u)) * s.peak_alpha
	var wobble := sin(u * TAU) * Z_WOBBLE_PX if s.kind == KIND_Z else 0.0
	s.quad.position = s.from + s.travel * e + Vector2(0.0, wobble)
	s.quad.scale = Vector2.ONE * lerpf(s.scale_from, s.scale_to, e)
	s.quad.rotation = (u - 0.5) * 0.25 if s.kind == KIND_Z else u * 1.2
	s.quad.visible = true
	s.quad.self_modulate = Color(1.0, 1.0, 1.0, alpha)
	if u >= 1.0:
		s.active = false
		s.quad.visible = false
