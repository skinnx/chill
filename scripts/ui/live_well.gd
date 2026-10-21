class_name LiveWell
extends ColorRect
## The rounded "window" behind every live mini-render (Art Bible §9.4 wells): shaders/ui/well
## paints the hollow's current sky and meadow, veiled toward the card surface, so live-lit flowers,
## décor and friends always sit in the light they are drawn with (day or night). Children are
## fitted to the well's rect (ItemPreview, CreaturePortrait).

const SHADER := "res://shaders/ui/well.gdshader"


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
	return w


func _on_resized() -> void:
	(material as ShaderMaterial).set_shader_parameter(&"u_size", size)
