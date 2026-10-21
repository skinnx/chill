class_name LiveWell
extends ColorRect
## The rounded "window" behind every live mini-render (Art Bible §9.4 wells): shaders/ui/well
## paints the hollow's current sky and meadow, veiled toward the card surface, so live-lit flowers,
## décor and friends always sit in the light they are drawn with (day or night). Children are
## fitted to the well's rect (ItemPreview, CreaturePortrait).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const SHADER := "res://shaders/ui/well.gdshader"
## palettes tod.derived_formulas ground_back weights.
const GROUND_BACK_MID := 0.2
const GROUND_BACK_HAZE := 0.06
## Palette slots copied to the well's u_st_<slot> uniforms.
const STUDIO_SLOTS: Array[String] = ["sky_top", "sky_mid", "sky_horizon", "glow", "far", "key", "shadow"]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	# The subject's contact shadow and grass never spill out of the window (round-2 QA: a grey
	# blob under the friend portrait bled into the name row).
	clip_contents = true
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER) as Shader
	mat.set_shader_parameter(&"u_surface", UiTokens.color(&"surface_hi"))
	material = mat
	resized.connect(_on_resized)


## A well of [param min_size] with corner [param radius] holding [param content] (fitted).
static func wrap(content: Control, min_size: Vector2, radius: float) -> LiveWell:
	var w := LiveWell.new()
	w.custom_minimum_size = min_size
	(w.material as ShaderMaterial).set_shader_parameter(&"u_radius", radius)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if content is CreaturePortrait:
		w.set_studio(true)
	return w


## Studio window (round 4): the well paints the portrait's fixed studio phase (creature_rig.json
## view.studio.phase) instead of the live sky, so a friend lit by the studio key sits on a matching
## daylight diorama at any hour (QA r3: the night Album portrait was a murky blob).
func set_studio(on: bool) -> void:
	var mat := material as ShaderMaterial
	mat.set_shader_parameter(&"u_studio", 1.0 if on else 0.0)
	if not on:
		return
	var view: Dictionary = ContentRegistry.content.creature_rig.get("view", {})
	var st: Dictionary = view.get("studio", {})
	var tod: Dictionary = ContentRegistry.palettes().get("tod", {})
	var pal: Dictionary = (tod.get("palettes", {}) as Dictionary).get(String(st.get("phase", "day")), {})
	if pal.is_empty():
		return
	var near := _hex(pal, "near")
	var mid := _hex(pal, "mid")
	var hor := _hex(pal, "sky_horizon")
	for slot: String in STUDIO_SLOTS:
		mat.set_shader_parameter(StringName("u_st_" + slot), _hex(pal, slot))
	# ground_back = mix(mix(near, mid, 0.20), sky_horizon, 0.06) (palettes tod.derived_formulas)
	mat.set_shader_parameter(&"u_st_ground_back", near.lerp(mid, GROUND_BACK_MID).lerp(hor, GROUND_BACK_HAZE))
	mat.set_shader_parameter(&"u_st_ground_front", near)
	mat.set_shader_parameter(&"u_st_rim", float(st.get("rim", 0.5)))


static func _hex(pal: Dictionary, key: String) -> Color:
	return Color.html(String(pal.get(key, "#FFFFFF")))


func _on_resized() -> void:
	(material as ShaderMaterial).set_shader_parameter(&"u_size", size)
