class_name PaletteDriver
extends RefCounted
## Palette contract of Art Bible §3.3 / palettes.json: one OKLab gradient per colour slot keyed by
## g_day (0.0 night, 0.2 dawn, 0.4 day, 0.6 golden, 0.8 dusk, 1.0 night), scalars lerped linearly
## on the same keys, then the rain transform scaled by g_rain (§3.4). Pure: returns values, the
## TimeOfDay autoload pushes them to shader globals.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## palette colour slot -> shader global (Art Bible §4.1).
const COLOR_GLOBALS := {
	"sky_top": &"g_sky_top", "sky_mid": &"g_sky_mid", "sky_horizon": &"g_sky_horizon",
	"glow": &"g_glow", "far": &"g_far", "mid": &"g_mid", "near": &"g_near", "fg": &"g_fg",
	"ambient": &"g_ambient", "key": &"g_key", "shadow": &"g_shadow", "accent": &"g_accent",
	"ground_back": &"g_ground_back", "ground_front": &"g_ground_front",
	"water_deep": &"g_water_deep", "water_shallow": &"g_water_shallow",
}
## scalar -> float shader global (halo_scale/halo_alpha are packed into g_halo).
const SCALAR_GLOBALS := {
	"rim": &"g_rim", "backlight": &"g_backlight", "ground_light": &"g_ground_light",
	"shadow_alpha": &"g_shadow_alpha", "stars": &"g_stars", "lights": &"g_lights",
	"shafts": &"g_shafts", "cloud_shadow": &"g_cloud_shadow", "mist": &"g_mist",
}
const SKY_SLOTS: Array[String] = ["sky_top", "sky_mid", "sky_horizon"]
## Optional slots are null in palettes that do not define them (accent_2 is day-only); they
## interpolate from this slot of the same palette instead.
const SLOT_FALLBACK := {"accent_2": "accent"}

var _keys := PackedFloat64Array()
## slot -> Array[Vector3] OKLab per key (alpha kept separately as 1.0: palettes are opaque).
var _lab: Dictionary = {}
## scalar -> PackedFloat64Array per key.
var _scalars: Dictionary = {}
var _rain: Dictionary = {}


func _init(palettes: Dictionary) -> void:
	var tod: Dictionary = palettes["tod"]
	var pals: Dictionary = tod["palettes"]
	var keys: Array = (tod["gradient_keys"] as Array).duplicate()
	keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["g_day"]) < float(b["g_day"]))
	var slot_names: Array = (pals[keys[0]["palette"]] as Dictionary).keys()
	for slot: String in slot_names:
		_lab[slot] = []
	for k: Dictionary in keys:
		_keys.append(float(k["g_day"]))
		var pal: Dictionary = pals[k["palette"]]
		for slot: String in slot_names:
			(_lab[slot] as Array).append(PaletteMath.to_oklab(Color.html(_hex(pal, slot))))
		var sc: Dictionary = tod["scalars"][k["palette"]]
		for name: String in sc:
			# Packed arrays are values (copy-on-write): append to the stored one by reassigning.
			var arr: PackedFloat64Array = _scalars.get(name, PackedFloat64Array())
			arr.append(float(sc[name]))
			_scalars[name] = arr
	_rain = palettes["weather"]["rain_transform"]


static func _hex(pal: Dictionary, slot: String) -> String:
	var v: Variant = pal.get(slot)
	if v == null and SLOT_FALLBACK.has(slot):
		v = pal.get(SLOT_FALLBACK[slot])
	return String(v) if v is String else "#000000"


func slots() -> PackedStringArray:
	return PackedStringArray(_lab.keys())


## Every colour slot at [param g_day], before weather.
func sample_colors(g_day: float) -> Dictionary:
	var seg := _segment(g_day)
	var i: int = seg[0]
	var f: float = seg[1]
	var out := {}
	for slot: String in _lab:
		var arr: Array = _lab[slot]
		var a: Vector3 = arr[i]
		var b: Vector3 = arr[i + 1]
		out[slot] = PaletteMath.from_oklab(a.lerp(b, f))
	return out


func sample_scalars(g_day: float) -> Dictionary:
	var seg := _segment(g_day)
	var i: int = seg[0]
	var f: float = seg[1]
	var out := {}
	for name: String in _scalars:
		var arr: PackedFloat64Array = _scalars[name]
		out[name] = lerpf(arr[i], arr[i + 1], f)
	return out


## Rain transform (Art Bible §3.4) scaled by [param r] = g_rain in [0, 1], in place.
func apply_rain(colors: Dictionary, scalars: Dictionary, r: float) -> void:
	if r <= 0.0:
		return
	var chroma := 1.0 - (1.0 - float(_rain["chroma_mul"])) * r
	var sky_l := float(_rain["sky_L_add"]) * r
	for slot: Variant in _rain["applies_to"]:
		var key := String(slot)
		if colors.has(key):
			var c: Color = colors[key]
			colors[key] = PaletteMath.adjust(c, chroma, sky_l if SKY_SLOTS.has(key) else 0.0)
	if colors.has("key"):
		var k: Color = colors["key"]
		colors["key"] = PaletteMath.adjust(k, 1.0 - (1.0 - float(_rain["key_chroma_mul"])) * r,
			float(_rain["key_L_add"]) * r)
	_mul_scalar(scalars, "rim", float(_rain["rim_mul"]), r)
	_mul_scalar(scalars, "backlight", float(_rain["backlight_mul"]), r)
	_mul_scalar(scalars, "shafts", float(_rain["shafts_mul"]), r)
	_mul_scalar(scalars, "ground_light", float(_rain["ground_light_mul"]), r)
	_mul_scalar(scalars, "halo_alpha", float(_rain["halo_alpha_mul"]), r)
	_mul_scalar(scalars, "cloud_shadow", float(_rain["cloud_shadow_mul"]), r)
	if scalars.has("mist"):
		scalars["mist"] = float(scalars["mist"]) + float(_rain["mist_add"]) * r


## A Gradient for one slot (e.g. the sky texture), OKLab-interpolated like the globals.
func make_gradient(slot: String) -> Gradient:
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	g.interpolation_color_space = Gradient.GRADIENT_COLOR_SPACE_OKLAB
	var arr: Array = _lab[slot]
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in _keys.size():
		offsets.append(_keys[i])
		var lab: Vector3 = arr[i]
		colors.append(PaletteMath.from_oklab(lab))
	g.offsets = offsets
	g.colors = colors
	return g


func _segment(g_day: float) -> Array:
	var x := clampf(g_day, _keys[0], _keys[_keys.size() - 1])
	for i in _keys.size() - 1:
		if x <= _keys[i + 1]:
			var span := _keys[i + 1] - _keys[i]
			return [i, (x - _keys[i]) / span if span > 0.0 else 0.0]
	return [_keys.size() - 2, 1.0]


static func _mul_scalar(scalars: Dictionary, name: String, mul_at_full: float, r: float) -> void:
	if scalars.has(name):
		scalars[name] = float(scalars[name]) * (1.0 - (1.0 - mul_at_full) * r)
