extends SceneTree
## Writes res://ui/theme/base_theme.tres from the design tokens (scripts/ui/theme_builder.gd).
## Usage: godot --headless --path . -s res://tools/ui/build_theme.gd
## Re-run after changing data/palettes.json ui tokens or the ThemeBuilder tables.

const OUT := "res://ui/theme/base_theme.tres"


func _init() -> void:
	var text := FileAccess.get_file_as_string("res://data/palettes.json")
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("build_theme: cannot read data/palettes.json")
		quit(1)
		return
	var palettes: Dictionary = parsed
	var theme := ThemeBuilder.build(palettes)
	var err := ResourceSaver.save(theme, OUT)
	if err != OK:
		push_error("build_theme: save failed: %s" % error_string(err))
		quit(1)
		return
	print("build_theme: wrote ", OUT)
	quit(0)
