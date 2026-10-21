extends Node2D
## Creature lineup for close inspection (Art Bible §11.2, §5.6 acceptance): every species awake
## (top) and asleep (bottom) on the live meadow colours, so raters can crop at 1:1 / 200 % and the
## 32 px thumbnail test can be run on one frame. Globals come from the TimeOfDay autoload, so
## --tod / --weather work as in the game.
##
##   tools/qa/capture.sh still --scene=res://scenes/creatures/lineup.tscn --size=1080x1920 --tod=0.6 \
##       --seed=7 --out=qa/out/lineup_golden.png
## User args: --lineup-pose=both|awake|asleep|happy   --lineup-only=<id,id,...>
##   --lineup-scale=<f> (creature scale, default fits the cell)   --lineup-live (blinks/fidgets on)
##   --lineup-labels=0 (hide species names)

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const ARG_POSE := "--lineup-pose="
const ARG_ONLY := "--lineup-only="
const ARG_SCALE := "--lineup-scale="
const ARG_LIVE := "--lineup-live"
const ARG_LABELS := "--lineup-labels="
const BACKDROP_SHADER := "res://shaders/creature/lineup_backdrop.gdshader"
const COLUMNS := 4
## Fraction of a cell the tallest creature may fill.
const FILL := 0.7
const LABEL_GAP_PX := 18.0
const LABEL_SCALE := 0.78
const LABEL_MAX_W := 0.7
## Tallest cell height as a multiple of its width (keeps close-ups large and centred).
const MAX_CELL_ASPECT := 1.5
## Fraction of a cell the widest creature (body + tail / ears allowance) may fill.
const FILL_W := 0.92
const WIDTH_PAD_BU := 0.35

var _rig: MosslingRig
var _mosslings: Array[Mossling] = []
var _feed := PaletteFeed.new()


func _ready() -> void:
	var content := ContentRegistry.content
	_rig = MosslingRig.new(content)
	var pose := "both"
	var only: PackedStringArray = PackedStringArray()
	var user_scale := 0.0
	var live := false
	var labels := true
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(ARG_POSE):
			pose = a.trim_prefix(ARG_POSE)
		elif a.begins_with(ARG_ONLY):
			only = a.trim_prefix(ARG_ONLY).split(",", false)
		elif a.begins_with(ARG_SCALE):
			user_scale = a.trim_prefix(ARG_SCALE).to_float()
		elif a == ARG_LIVE:
			live = true
		elif a.begins_with(ARG_LABELS):
			labels = a.trim_prefix(ARG_LABELS) != "0"
	var ids: Array[StringName] = []
	for s: Dictionary in content.species:
		var id := StringName(s["id"])
		if only.is_empty() or only.has(String(id)):
			ids.append(id)
	var size := get_viewport().get_visible_rect().size
	_backdrop(size)
	var poses: Array[String] = []
	if pose == "both":
		poses = ["awake", "asleep"]
	else:
		poses = [pose]
	var cols := mini(COLUMNS, maxi(ids.size(), 1))
	var rows_per := ceili(float(ids.size()) / float(cols))
	var rows := rows_per * poses.size()
	var cell := Vector2(size.x / float(cols), size.y / float(rows))
	# few species (close-ups): square-ish cells, the grid centred vertically
	cell.y = minf(cell.y, cell.x * MAX_CELL_ASPECT)
	var top := (size.y - cell.y * float(rows)) * 0.5
	var tallest := 0.0
	for id: StringName in ids:
		tallest = maxf(tallest, _rig.body_px(id) * (1.0 + _rig.top_extent_bu(id)))
	var widest := 0.0
	for id: StringName in ids:
		widest = maxf(widest, _rig.body_px(id) * (_rig.body_width_bu(id) + WIDTH_PAD_BU))
	var fit := minf(cell.y * FILL / maxf(tallest, 1.0), cell.x * FILL_W / maxf(widest, 1.0))
	var k := user_scale if user_scale > 0.0 else fit
	var fur := _rig.make_fur_material()
	MosslingRig.bind_palette(fur, _feed)
	_feed.apply(TimeOfDay.colors)
	TimeOfDay.globals_updated.connect(func(_v: Dictionary) -> void: _feed.apply(TimeOfDay.colors))
	var shadow := _rig.make_shadow_material()
	var fx := _rig.make_fx_materials()
	for pi in poses.size():
		for i in ids.size():
			var id := ids[i]
			var col := i % cols
			var row := pi * rows_per + int(float(i) / float(cols))
			var feet := Vector2((float(col) + 0.5) * cell.x, top + (float(row) + 0.78) * cell.y)
			var m := Mossling.new()
			add_child(m)
			m.setup(_rig, id, fposmod(float(i) * 0.618 + 0.13, 1.0), fur, shadow, fx)
			m.place_at(feet)
			m.scale_override(k)
			m.set_still(not live)
			match poses[pi]:
				"asleep":
					m.debug_pose(&"asleep")
				"happy":
					m.debug_pose(&"happy")
				_:
					m.debug_pose(&"awake")
			_mosslings.append(m)
			if labels:
				_label(content, id, feet, cell)


func _backdrop(size: Vector2) -> void:
	var quad := SdfQuad.new()
	quad.name = "Backdrop"
	quad.rect = Rect2(Vector2.ZERO, size)
	var mat := ShaderMaterial.new()
	mat.shader = load(BACKDROP_SHADER) as Shader
	mat.set_shader_parameter(&"u_size", size)
	quad.material = mat
	quad.z_index = -10
	add_child(quad)


func _label(content: GameContent, id: StringName, feet: Vector2, cell: Vector2) -> void:
	var sp: Dictionary = content.species_by_id.get(id, {})
	# the name on a light chip (the in-game name tag style), legible over any meadow colour
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"Chip"
	var l := Label.new()
	l.text = tr(String(sp.get("name_key", String(id))))
	l.theme_type_variation = &"CaptionLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(l)
	add_child(chip)
	UiTheme.attach(chip)
	chip.reset_size()
	# a small caption chip: at most LABEL_MAX_W of the cell, so the friend stays the subject
	chip.scale = Vector2.ONE * minf(LABEL_SCALE, cell.x * LABEL_MAX_W / maxf(chip.size.x, 1.0))
	chip.position = Vector2(feet.x - chip.size.x * chip.scale.x * 0.5, feet.y + LABEL_GAP_PX)
