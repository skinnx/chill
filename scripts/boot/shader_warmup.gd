class_name ShaderWarmup
extends Node2D
## Shader warm-up (synthesis C8, Art Bible §4.19): every canvas_item and particles shader, every
## registered material and every UI font is drawn once INSIDE the viewport, behind the opaque
## splash, at a combined alpha >= 0.01. Off-screen items and items below alpha 0.007 are culled
## (renderer_canvas_cull.cpp:329) and would never compile, so this node must sit in the visible
## rect and under an opaque cover. GLES3 has no pipeline-compilation counter
## (PIPELINE_COMPILATIONS_* reads 0), so QA detects hitches by frame time (FrameGovernor).
##
## Shaders are discovered by scanning res://shaders recursively; code-made materials (particle
## process materials, generated ShaderMaterials) call [method register] before boot.

const SHADER_ROOT := "res://shaders"
const FONT_ROOT := "res://fonts"
## Combined modulate alpha of the stage (C8: >= 0.01, culled below 0.007).
const STAGE_ALPHA := 0.02
const QUAD_PX := 8.0
const GRID_COLUMNS := 16
const FONT_SAMPLE := "Mossling Meadow Thung lũng Ẫ Ỗ Ữ Ặ Ỵ đ — 0123456789 +−×"
const FONT_SAMPLE_SIZES: Array[int] = [36, 42, 48, 66, 84]

static var _registered: Array[Material] = []

## Number of items drawn by the last run (QA / tests).
var drawn: int = 0


static func register(material: Material) -> void:
	if material != null and not _registered.has(material):
		_registered.append(material)


## Draws everything for [param frames] rendered frames, then frees the stage's children.
func run(frames: int = 2) -> void:
	modulate.a = STAGE_ALPHA
	position = Vector2.ZERO
	var i := 0
	for path: String in find_shaders(SHADER_ROOT):
		var shader := load(path) as Shader
		if shader == null:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = shader
		if _add_for_material(mat, i):
			i += 1
	for mat: Material in _registered:
		if _add_for_material(mat, i):
			i += 1
	for path: String in find_files(FONT_ROOT, ["woff2", "ttf", "otf"]):
		var font := load(path) as Font
		if font == null:
			continue
		for size: int in FONT_SAMPLE_SIZES:
			var l := Label.new()
			l.text = FONT_SAMPLE
			l.add_theme_font_override(&"font", font)
			l.add_theme_font_size_override(&"font_size", size)
			l.position = _slot(i)
			add_child(l)
			i += 1
	drawn = i
	for _f in frames:
		await _frame()
	for c: Node in get_children():
		c.queue_free()


func _add_for_material(mat: Material, index: int) -> bool:
	if mat is ParticleProcessMaterial or (mat is ShaderMaterial and (mat as ShaderMaterial).shader != null \
			and (mat as ShaderMaterial).shader.get_mode() == Shader.MODE_PARTICLES):
		var p := GPUParticles2D.new()
		p.amount = 1
		p.process_material = mat
		p.position = _slot(index)
		p.emitting = true
		add_child(p)
		return true
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null \
			and (mat as ShaderMaterial).shader.get_mode() != Shader.MODE_CANVAS_ITEM:
		return false  # spatial / sky / fog shaders are not used in this 2D game
	var r := ColorRect.new()
	r.size = Vector2(QUAD_PX, QUAD_PX)
	r.position = _slot(index)
	r.material = mat
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return true


func _slot(index: int) -> Vector2:
	return Vector2((index % GRID_COLUMNS) * QUAD_PX * 2.0, floorf(float(index) / GRID_COLUMNS) * QUAD_PX * 2.0)


func _frame() -> void:
	# The dummy (headless) renderer never draws, so frame_post_draw would never fire there.
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw


static func find_shaders(root: String) -> PackedStringArray:
	return find_files(root, ["gdshader"])


## Recursive listing through ResourceLoader (works on exported .pck files and remaps).
static func find_files(root: String, extensions: Array[String]) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(root):
		return out
	for entry: String in ResourceLoader.list_directory(root):
		var path := root.path_join(entry)
		if entry.ends_with("/"):
			out.append_array(find_files(path.trim_suffix("/"), extensions))
		elif extensions.has(entry.get_extension()):
			out.append(path)
	return out
