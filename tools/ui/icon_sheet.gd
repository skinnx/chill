extends SceneTree
## Contact sheet of art/icons/*.svg for review (Art Bible §9.3; QA at 200 %).
## Usage: godot --headless --path . -s res://tools/ui/icon_sheet.gd -- --out=/tmp/icons.png [--scale=2]
## Draws every icon on surface (#F0EEE9) and on the darkest glass backdrop it may meet, so both the
## duotone read and the >= 3:1 icon contrast can be judged at a glance.

const ICON_DIR := "res://art/icons"
const CANVAS := 72
const COLUMNS := 9
const PAD := 16
const BACKDROPS: Array[Color] = [Color("#F0EEE9"), Color("#FFFDF8")]


func _init() -> void:
	var out := "/tmp/icons.png"
	var scale := 2.0
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--scale="):
			scale = a.trim_prefix("--scale=").to_float()
	var names: PackedStringArray = []
	for f: String in DirAccess.get_files_at(ICON_DIR):
		if f.ends_with(".svg"):
			names.append(f)
	names.sort()
	var cell := int(CANVAS * scale) + PAD
	var rows := ceili(float(names.size()) / COLUMNS)
	var sheet := Image.create(cell * COLUMNS, cell * rows * BACKDROPS.size(), false, Image.FORMAT_RGBA8)
	for bi in BACKDROPS.size():
		sheet.fill_rect(Rect2i(0, bi * cell * rows, cell * COLUMNS, cell * rows), BACKDROPS[bi])
	for i in names.size():
		var src := FileAccess.get_file_as_string(ICON_DIR.path_join(names[i]))
		var img := Image.new()
		if img.load_svg_from_string(src, scale) != OK:
			push_error("icon_sheet: cannot rasterize %s" % names[i])
			continue
		img.convert(Image.FORMAT_RGBA8)
		for bi in BACKDROPS.size():
			var at := Vector2i((i % COLUMNS) * cell + PAD / 2, (i / COLUMNS) * cell + PAD / 2 + bi * cell * rows)
			sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
	sheet.save_png(out)
	print("icon_sheet: ", names.size(), " icons -> ", out, " ", ", ".join(names))
	quit(0)
