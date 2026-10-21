class_name CloudLayer
extends Node2D
## L2 clouds (Art Bible §2.3, §4.8): three soft cumulus quads (plus two rain clouds that fade in
## with g_rain) drifting left at the weather's autoscroll speed (palettes.json
## weather.cloud_autoscroll_px_s), wrapping fully off screen (even on the x -400..1480 wide-screen
## bleed plus camera drift) so the drift never pops. The drift
## follows Clock.time_scale, so frozen QA captures stay still and deterministic.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const SHADER_PATH := "res://shaders/world/cloud.gdshader"
## Art Bible §4.8: 600x220 px quads. The wrap span (2700 px from x -800) keeps a 1.25x cloud fully
## outside x -400..1480 at both ends (the §4.8 1800 px repeat would pop on wide screens).
const REPEAT_PX := 2700.0
const WRAP_X0 := -800.0
## (x, y, scale, seed, alpha, flatten, rain_only): design px. Sparse by day (the sky above y 330 is
## a rest area, §2.5); the two rain clouds sit low and wide.
const CLOUDS: Array[Array] = [
	[60.0, 300.0, 0.95, 3.0, 0.95, 0.6, 0.0],
	[720.0, 170.0, 0.70, 11.0, 0.80, 0.4, 0.0],
	[1330.0, 470.0, 0.80, 5.0, 0.90, 0.7, 0.0],
	[380.0, 520.0, 1.15, 17.0, 1.0, 0.8, 1.0],
	[1080.0, 60.0, 1.25, 23.0, 1.0, 0.6, 1.0],
]
const QUAD := Vector2(600.0, 220.0)

var _speed_by_weather: Dictionary = {}
var _quads: Array[Node2D] = []
var _base_x := PackedFloat64Array()
var _offset: float = 0.0
var _feed := PaletteFeed.new()


func _ready() -> void:
	var scroll: Dictionary = ContentRegistry.palettes()["weather"]["cloud_autoscroll_px_s"]
	for k: String in scroll:
		_speed_by_weather[StringName(k)] = float(scroll[k])
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH) as Shader
	_feed.bind(mat, &"cloud_lit", "cloud_lit")
	_feed.bind(mat, &"cloud_shade", "cloud_shade")
	_feed.apply(TimeOfDay.colors)
	TimeOfDay.globals_updated.connect(func(_v: Dictionary) -> void: _feed.apply(TimeOfDay.colors))
	for c: Array in CLOUDS:
		var q := CloudQuad.new()
		q.size = QUAD * float(c[2])
		q.material = mat
		q.position = Vector2(float(c[0]), float(c[1]))
		add_child(q)
		q.set_instance_shader_parameter(&"i_cloud", Vector4(float(c[3]), float(c[4]), float(c[5]), float(c[6])))
		q.set_instance_shader_parameter(&"i_size", q.size)
		_quads.append(q)
		_base_x.append(float(c[0]))
	FrameGovernor.tier_changed.connect(_apply_tier)
	_apply_tier(FrameGovernor.tier)


## Governor tier 1+: clouds 3 -> 1 (the rain clouds stay, they carry the weather).
func _apply_tier(tier: int) -> void:
	for i in _quads.size():
		var rain_only := float(CLOUDS[i][6]) > 0.0
		_quads[i].visible = tier == 0 or i == 0 or rain_only


func _process(delta: float) -> void:
	var v := 0.0
	for w: StringName in _speed_by_weather:
		v += float(_speed_by_weather[w]) * TimeOfDay.weather_driver.weight(w)
	_offset = fposmod(_offset + v * delta * Clock.time_scale, REPEAT_PX)
	for i in _quads.size():
		_quads[i].position.x = WRAP_X0 + fposmod(_base_x[i] + _offset - WRAP_X0, REPEAT_PX)


## One cloud quad (draws its rect; the shader shapes it).
class CloudQuad:
	extends Node2D
	var size := Vector2(600.0, 220.0)

	func _draw() -> void:
		draw_rect(Rect2(-size * 0.5, size), Color.WHITE)
