class_name AmbientParticles
extends Node2D
## Ambient particles of the hollow (Art Bible §4.15, §7; synthesis D9): dust in the light shafts,
## pollen, dandelion seeds and petals on the breeze, fireflies at dusk and night, light rain and
## its splash rings. Each system is a GPUParticles2D with the shared wander process shader and the
## particle_draw shader; ParticleBudget keeps <= 3 systems and <= 150 particles alive. Outgoing
## systems stop emitting first; incoming ones start once there is room and fill in particle by
## particle (each fades in over >= 300 ms), so weather changes never pop. Deterministic seeds.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const PROCESS_SHADER := "res://shaders/fx/wander.gdshader"
const DRAW_SHADER := "res://shaders/fx/particle_draw.gdshader"
const FIXED_FPS := 30
const SEED_BASE := 9100
const CHECK_INTERVAL_S := 0.5
const VIS_RECT := Rect2(-700.0, -1400.0, 2500.0, 3600.0)
## Art Bible §7.1 (sizes at depth 1, 1 dp = 3 px). kind: wander.gdshader KIND_*.
const SYSTEMS := {
	&"dust": {"kind": 0, "add": true, "life": 6.0, "peak": 36, "size": Vector2(3.0, 7.5),
		"alpha": Vector2(0.15, 0.4), "speed": Vector2(6.0, 24.0), "drift": Vector2(4.0, 0.0),
		"hz": Vector2(0.2, 0.5), "rect": Rect2(60.0, 380.0, 960.0, 1120.0), "steer": 0.2},
	&"pollen": {"kind": 1, "add": true, "life": 8.0, "peak": 10, "size": Vector2(9.0, 15.0),
		"alpha": Vector2(0.45, 0.55), "speed": Vector2(6.0, 14.0), "drift": Vector2(36.0, 0.0),
		"hz": Vector2(0.15, 0.3), "rect": Rect2(-160.0, 720.0, 1100.0, 720.0), "steer": 0.0},
	&"seeds": {"kind": 2, "add": false, "life": 10.0, "peak": 12, "size": Vector2(16.0, 24.0),
		"alpha": Vector2(0.8, 0.95), "speed": Vector2(0.0, 0.0), "drift": Vector2(45.0, -6.0),
		"hz": Vector2(0.2, 0.4), "rect": Rect2(-260.0, 640.0, 1200.0, 760.0), "steer": 0.0, "spin": 30.0},
	&"petals": {"kind": 3, "add": false, "life": 7.0, "peak": 10, "size": Vector2(18.0, 30.0),
		"alpha": Vector2(0.85, 0.95), "speed": Vector2(30.0, 60.0), "drift": Vector2(24.0, 0.0),
		"hz": Vector2(0.3, 0.6), "rect": Rect2(-200.0, -300.0, 1400.0, 1200.0), "steer": 0.0},
	&"fireflies": {"kind": 4, "add": true, "life": 20.0, "peak": 18, "size": Vector2(36.0, 60.0),
		"alpha": Vector2(1.0, 1.0), "speed": Vector2(15.0, 45.0), "drift": Vector2(0.0, 0.0),
		"hz": Vector2(0.03, 0.08), "rect": Rect2(40.0, 880.0, 1000.0, 570.0), "steer": 0.35},
	&"rain": {"kind": 5, "add": false, "life": 3.6, "peak": 120, "size": Vector2(1.0, 1.0),
		"alpha": Vector2(0.25, 0.4), "speed": Vector2(360.0, 720.0), "drift": Vector2(0.0, 0.0),
		"hz": Vector2(0.0, 0.0), "rect": Rect2(-100.0, -700.0, 1280.0, 2620.0), "steer": 0.0, "fade": 0.3},
	&"splash": {"kind": 6, "add": false, "life": 1.0, "peak": 6, "size": Vector2(24.0, 48.0),
		"alpha": Vector2(1.0, 1.0), "speed": Vector2(0.0, 0.0), "drift": Vector2(0.0, 0.0),
		"hz": Vector2(0.0, 0.0), "rect": Rect2(20.0, 830.0, 1040.0, 660.0), "steer": 0.0, "fade": 0.12},
}
const FADE_IN_S := 0.4
const FIREFLY_BIAS := 0.45
const FIREFLY_POINT_R := 130.0
const MAX_POINTS := 8

## Live systems: id -> GPUParticles2D.
var systems: Dictionary = {}
## Wanted composition (id -> amount) for the current phase and weather.
var wanted: Dictionary = {}

var _stopped_at: Dictionary = {}
var _clock: float = 0.0
var _accum: float = 0.0
var _draw_mats: Dictionary = {}
var _shafts: ShaftController = null
var _fx: Dictionary = {}


func _ready() -> void:
	_fx = ContentRegistry.palettes()["fx"]
	_shafts = get_parent().get_node_or_null("Shafts") as ShaftController
	if _shafts != null:
		_shafts.rebuilt.connect(_push_shafts)
	wanted = _composition()
	for id: StringName in wanted:
		_start(id, true)
	_apply_colors()
	_push_shafts()
	TimeOfDay.phase_changed.connect(func(_p: StringName) -> void: _retarget())
	TimeOfDay.weather_changed.connect(func(_w: StringName) -> void: _retarget())
	TimeOfDay.globals_updated.connect(func(_v: Dictionary) -> void: _apply_colors())
	Motion.reduce_motion_changed.connect(func(_on: bool) -> void: _apply_ratios())
	get_viewport().size_changed.connect(_fit_rain)
	_fit_rain()


func _composition() -> Dictionary:
	var rain := roundi(TimeOfDay.current_weather_particles())
	var w := TimeOfDay.weather
	if w == &"rain" and rain <= 0:
		rain = int(SYSTEMS[&"rain"]["peak"])
	return ParticleBudget.composition(TimeOfDay.phase, w, rain)


func _process(delta: float) -> void:
	_clock += delta
	_accum += delta
	if _accum < CHECK_INTERVAL_S:
		return
	_accum = 0.0
	# Systems that stopped emitting free their budget once their last particle has lived out.
	for id: StringName in _stopped_at.keys():
		var p: GPUParticles2D = systems[id]
		if _clock - float(_stopped_at[id]) > p.lifetime:
			p.visible = false
			_stopped_at.erase(id)
	for id: StringName in wanted:
		var p: GPUParticles2D = systems.get(id)
		if p != null and p.emitting:
			continue
		if ParticleBudget.can_start(_alive_amounts(id), int(wanted[id])):
			_start(id, false)
	_apply_ratios()


func _retarget() -> void:
	wanted = _composition()
	for id: StringName in systems:
		var p: GPUParticles2D = systems[id]
		if p.emitting and not wanted.has(id):
			p.emitting = false
			_stopped_at[id] = _clock
	_accum = CHECK_INTERVAL_S


## Amounts of every system still alive (emitting or finishing), except `skip`.
func _alive_amounts(skip: StringName) -> Dictionary:
	var out := {}
	for id: StringName in systems:
		var p: GPUParticles2D = systems[id]
		if id != skip and p.visible and (p.emitting or _stopped_at.has(id)):
			out[id] = int(roundf(float(p.amount) * p.amount_ratio))
	return out


func _start(id: StringName, at_boot: bool) -> void:
	var p: GPUParticles2D = systems.get(id)
	if p == null:
		p = _make(id, at_boot)
		systems[id] = p
		add_child(p)
		if id == &"rain":
			_fit_rain()
	p.visible = true
	p.emitting = true
	_stopped_at.erase(id)
	_apply_ratios()


func _make(id: StringName, at_boot: bool) -> GPUParticles2D:
	var cfg: Dictionary = SYSTEMS[id]
	var p := GPUParticles2D.new()
	p.name = String(id).capitalize()
	p.amount = int(cfg["peak"])
	p.lifetime = float(cfg["life"])
	p.fixed_fps = FIXED_FPS
	p.local_coords = true
	p.use_fixed_seed = true
	p.seed = SEED_BASE + SYSTEMS.keys().find(id) * 101
	p.preprocess = float(cfg["life"]) if at_boot else 0.0
	p.visibility_rect = VIS_RECT
	var pm := ShaderMaterial.new()
	pm.shader = load(PROCESS_SHADER) as Shader
	var kind := int(cfg["kind"])
	pm.set_shader_parameter(&"kind", kind)
	var r: Rect2 = cfg["rect"]
	pm.set_shader_parameter(&"emit_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	pm.set_shader_parameter(&"speed", cfg["speed"])
	pm.set_shader_parameter(&"drift", cfg["drift"])
	pm.set_shader_parameter(&"size_px", cfg["size"])
	pm.set_shader_parameter(&"alpha", cfg["alpha"])
	pm.set_shader_parameter(&"wander_hz", cfg["hz"])
	pm.set_shader_parameter(&"fade_in_s", float(cfg.get("fade", FADE_IN_S)))
	pm.set_shader_parameter(&"steer", float(cfg["steer"]))
	pm.set_shader_parameter(&"spin_deg_s", float(cfg.get("spin", 0.0)))
	if id == &"fireflies":
		var k: Array = ContentRegistry.motion_tokens()["loops_k"]["firefly_cycle"]
		pm.set_shader_parameter(&"k_range", Vector2(float(k[0]), float(k[1])))
		_feed_points(pm)
	p.process_material = pm
	var dm := ShaderMaterial.new()
	dm.shader = load(DRAW_SHADER) as Shader
	dm.set_shader_parameter(&"kind", kind)
	dm.set_shader_parameter(&"additive", bool(cfg["add"]))
	dm.set_shader_parameter(&"lit_by_ambient", id == &"seeds" or id == &"petals")
	if id == &"fireflies":
		dm.set_shader_parameter(&"tint", Color.html(String(_fx["firefly_core"])))
	elif id == &"pollen":
		dm.set_shader_parameter(&"tint", Color.html(String(_fx["pollen"])))
	elif id == &"seeds":
		dm.set_shader_parameter(&"tint", Color.html(String(_fx["seed_pappus"])))
	elif id == &"petals":
		var petal: Array = ContentRegistry.palettes()["flora"]["flowers"]["fl_clover"]["petal"]
		dm.set_shader_parameter(&"tint", Color.html(String(petal[0])))
		dm.set_shader_parameter(&"tint2", Color.html(String(petal[1])))
		dm.set_shader_parameter(&"tint2_is_accent", false)
	p.material = dm
	_draw_mats[id] = dm
	return p


## Fireflies gather near lanterns and flowers (Art Bible §7.1): lamps first, then bed centres.
func _feed_points(pm: ShaderMaterial) -> void:
	var pts := PackedVector4Array()
	for v: Vector4 in LampRegistry.lamps():
		if pts.size() < MAX_POINTS:
			pts.append(Vector4(v.x, v.y - 40.0, 0.0, 0.0))
	for b: Dictionary in ContentRegistry.content.beds:
		if pts.size() < MAX_POINTS:
			var c := GardenRules.frame_to_px(ContentRegistry.content, Vector2(float(b["x"]), float(b["y"])))
			pts.append(Vector4(c.x, c.y - 60.0, 0.0, 0.0))
	var n := pts.size()
	pts.resize(MAX_POINTS)
	pm.set_shader_parameter(&"u_points", pts)
	pm.set_shader_parameter(&"u_point_count", n)
	pm.set_shader_parameter(&"point_bias", FIREFLY_BIAS)
	pm.set_shader_parameter(&"point_radius", FIREFLY_POINT_R)


## Density per system: wanted / peak, x Reduce Motion (0.3) and ambient mode (0.5).
func _apply_ratios() -> void:
	var rm: Dictionary = ContentRegistry.motion_tokens()["reduce_motion"]
	var mul := float(rm["particles_mul"]) if Motion.reduce_motion else 1.0
	if FrameGovernor.ambient_mode:
		mul *= 0.5
	for id: StringName in systems:
		var p: GPUParticles2D = systems[id]
		if wanted.has(id):
			p.amount_ratio = clampf(float(wanted[id]) / float(p.amount) * mul, 0.0, 1.0)


func _apply_colors() -> void:
	var cols := TimeOfDay.colors
	if cols.is_empty():
		return
	var white := Color.html(String(_fx["sparkle"]))
	if _draw_mats.has(&"dust"):
		(_draw_mats[&"dust"] as ShaderMaterial).set_shader_parameter(&"tint", cols["glow"])
	if _draw_mats.has(&"rain"):
		var streak := PaletteMath.mix_oklab(cols["sky_horizon"], white, 0.30)
		(_draw_mats[&"rain"] as ShaderMaterial).set_shader_parameter(&"tint", streak)
	if _draw_mats.has(&"splash"):
		var ring := PaletteMath.mix_oklab(cols["water_shallow"], white, 0.50)
		(_draw_mats[&"splash"] as ShaderMaterial).set_shader_parameter(&"tint", ring)


func _push_shafts() -> void:
	if _shafts == null or not _draw_mats.has(&"dust"):
		return
	var arr := PackedVector4Array()
	arr.resize(5)
	var n := mini(_shafts.shafts.size(), 5)
	for i in n:
		arr[i] = _shafts.shafts[i]
	var dm: ShaderMaterial = _draw_mats[&"dust"]
	dm.set_shader_parameter(&"u_shafts", arr)
	dm.set_shader_parameter(&"u_shaft_count", n)
	dm.set_shader_parameter(&"u_shaft_w", _shafts.shaft_width * 0.5)


## Rain covers the whole visible rect + 200 px above it (Art Bible §7.1), on any aspect ratio.
func _fit_rain() -> void:
	if not systems.has(&"rain"):
		return
	var vis := get_viewport_rect().size
	var off := TimeOfDay.world_offset
	var pm: ShaderMaterial = (systems[&"rain"] as GPUParticles2D).process_material
	pm.set_shader_parameter(&"emit_rect", Vector4(-off.x - 60.0, -off.y - 200.0, vis.x + 120.0, vis.y + 200.0))
