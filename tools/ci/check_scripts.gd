extends SceneTree
## Compiles every project GDScript with the autoloads registered (report 03 §6.3: --check-only
## cannot resolve autoload names, so it fails every script that uses one). Prints one line per
## script that fails to compile and exits 1 if any did. Analyzer warnings are printed by the
## engine during the reload (debug/gdscript/warnings/* in project.godot).
## Usage: godot --headless --path . -s res://tools/ci/check_scripts.gd

const ROOTS: Array[String] = ["res://scripts", "res://tests", "res://tools"]


var _done: bool = false


## Runs on the first frame: autoload singletons are only registered once the tree is running.
func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return false


func _run() -> void:
	var files := PackedStringArray()
	for root: String in ROOTS:
		_collect(root, files)
	var failed := 0
	for path: String in files:
		# A script that fails to parse or compile loads as null (the engine prints the error).
		var script := load(path) as GDScript
		if script == null:
			failed += 1
			print("FAIL ", path)
	print("check_scripts: %d scripts, %d failed" % [files.size(), failed])
	quit(1 if failed > 0 else 0)


func _collect(dir: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var path := dir.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				_collect(path, out)
		elif name.get_extension() == "gd":
			out.append(path)
		name = d.get_next()
	d.list_dir_end()
