extends SceneTree
## Deterministic still capture for visual QA (synthesis C9, C10, D13; docs/QA.md §3).
##
## Normally run through tools/qa/capture.sh, which also sizes the window, isolates user:// and
## supplies the defaults below. Direct use (Xvfb, Compatibility renderer on the GLES path):
##   xvfb-run -a -s "-screen 0 1280x2560x24" godot --path . --rendering-driver opengl3_es \
##     --audio-driver Dummy --resolution 1080x1920 --fixed-fps 30 -s res://tools/qa/capture.gd -- \
##     --tod=0.62 --weather=clear --seed=7 --frames=90 --out=qa/out/golden.png --size=1080x1920
##
## User args (after `--`; the game's own QA args such as --seed, --tod, --weather, --g-time,
## --debug-layout, --debug-hud are read by the autoloads themselves and simply pass through):
##   --out=<png>         output path; relative paths resolve against the project root
##                       (default qa/out/capture.png). A <png>.json sidecar is written next to it.
##                       --out=none takes no still: the run only drives the game for --frames and
##                       quits cleanly (Movie Maker video, tools/qa/capture.sh video).
##   --frames=<n>        frames to run after the first scene is entered (default 90 = 3 s at 30 fps)
##   --size=<WxH>        expected window size in px; the run fails if the window differs
##   --scene=<res path>  scene to enter (default the real boot scene, so boot -> main runs as in play)
##   --tod=<0..1>        pins g_day (default 0.4 = day, unless --clock or --now drive the palette)
##   --weather=<id>      pins the weather (default clear; "plan" keeps the seeded day plan)
##   --date=<YYYY-MM-DD> --clock=<HH:MM> --tz=<minutes>  fixed wall clock (defaults 2026-04-18,
##                       10:00, UTC); --now=<unix> overrides all three
##   --g-time=<s>        shader clock value (default 0); --animate lets it run (default frozen)
##   --hide-ui           hides every CanvasLayer of the scene: a world-only frame (V2, V4)
##   --set=<key>:<value> applies a Settings key for this run only (language:vi, text_scale:200,
##                       reduce_motion:true, reduce_transparency:true ...); repeatable
##
## Determinism (docs/QA.md §3.2): the run uses the frame clock (Clock.frame_clock: wall time and
## ticks advance by the fixed frame delta), the global RNG is seeded, the frame governor is off,
## settings are not persisted, and every input above has a fixed default. The sidecar records
## everything that went into the frame plus "deterministic": false with reasons when an input was
## left to the system (no --fixed-fps, no --seed, a save already present in user://).

const DEFAULTS: Dictionary[String, String] = {
	"out": "qa/out/capture.png",
	"frames": "90",
	"scene": "res://scenes/boot.tscn",
	"tod": "0.4",
	"weather": "clear",
	"date": "2026-04-18",
	"clock": "10:00",
	"tz": "0",
	"g-time": "0",
}
## --out value for runs that only drive the game (Movie Maker video: capture.sh video).
const NO_STILL := "none"
## Weather value that keeps the deterministic per-install weather plan instead of pinning one.
const WEATHER_PLAN := "plan"
const GLOBAL_RNG_SEED := 12345
const EXIT_OK := 0
const EXIT_FAILED := 1
const SECONDS_PER_DAY := 86400.0
const SECONDS_PER_HOUR := 3600.0
const SECONDS_PER_MINUTE := 60.0
## Fixed delta tolerance: --fixed-fps gives the same double every frame.
const DELTA_EPSILON := 1e-9

var _args: Dictionary[String, String] = {}
var _flags: PackedStringArray = PackedStringArray()
var _settings: Array[PackedStringArray] = []
var _left: int = 0
var _started: bool = false
var _first_delta: float = -1.0
var _fixed_delta: bool = true
var _warnings: PackedStringArray = PackedStringArray()
var _save_present: bool = false


func _initialize() -> void:
	_parse(OS.get_cmdline_user_args())
	seed(GLOBAL_RNG_SEED)
	_left = maxi(1, _arg_i("frames"))
	# Autoload nodes exist here but have not run _ready yet (SceneTree.initialize calls this first).
	var clock := root.get_node_or_null("Clock")
	if clock != null:
		clock.set("frame_clock", true)
	var governor := root.get_node_or_null("FrameGovernor")
	if governor != null:
		governor.set("enabled", false)


func _process(delta: float) -> bool:
	if not _started:
		_started = true
		_apply_overrides()
		change_scene_to_file(_args["scene"])
		return false
	if _first_delta < 0.0:
		_first_delta = delta
	elif absf(delta - _first_delta) > DELTA_EPSILON:
		_fixed_delta = false
	_left -= 1
	if _left == 0:
		_capture.call_deferred()
	return false


func _parse(args: PackedStringArray) -> void:
	_args = DEFAULTS.duplicate()
	for raw: String in args:
		var a := raw.trim_prefix("--")
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			if kv[0] == "set":
				var pair := kv[1].split(":", true, 1)
				if pair.size() == 2:
					_settings.append(pair)
				else:
					_warnings.append("ignored --set=%s (expected key:value)" % kv[1])
			else:
				_args[kv[0]] = kv[1]
		else:
			_flags.append(a)


## Runs on the first frame, after every autoload's _ready and before the boot scene loads the save.
func _apply_overrides() -> void:
	var clock := root.get_node("Clock")
	clock.call("override_timezone", _arg_f("tz") * SECONDS_PER_MINUTE)
	clock.call("override_now", _fixed_now())
	var wrap_s: float = clock.get("g_time_wrap_s")
	clock.set("g_time", fposmod(_arg_f("g-time"), wrap_s))
	if not _flags.has("animate"):
		clock.set("time_scale", 0.0)
	var settings := root.get_node("Settings")
	settings.set("persist", false)
	for pair: PackedStringArray in _settings:
		settings.call("set_value", StringName(pair[0]), _parse_value(pair[1]))
	var pin_tod := not (_args.has("now") or _has_user_arg("clock")) or _has_user_arg("tod")
	var g_day := clampf(_arg_f("tod"), 0.0, 1.0) if pin_tod else NAN
	var weather := StringName(_args["weather"])
	root.get_node("TimeOfDay").call("set_overrides", g_day, &"" if weather == StringName(WEATHER_PLAN) else weather)
	_save_present = root.get_node("SaveService").call("has_save") == true
	if _save_present:
		_warnings.append("a save exists in user:// and will be loaded (capture.sh isolates user://)")
	if not _has_user_arg("seed"):
		_warnings.append("no --seed: the new install gets a random seed")


func _fixed_now() -> float:
	if _args.has("now"):
		return _arg_f("now")
	var d := _args["date"].split("-")
	var hm := _args["clock"].split(":")
	var date := {"year": int(d[0]), "month": int(d[1]), "day": int(d[2]), "hour": 0, "minute": 0, "second": 0}
	var midnight := float(Time.get_unix_time_from_datetime_dict(date))
	var sod := float(hm[0]) * SECONDS_PER_HOUR + (float(hm[1]) * SECONDS_PER_MINUTE if hm.size() > 1 else 0.0)
	# --date/--clock are local wall time; unix = local - tz offset.
	return midnight + fposmod(sod, SECONDS_PER_DAY) - _arg_f("tz") * SECONDS_PER_MINUTE


func _arg_f(key: String) -> float:
	return _args[key].to_float()


func _arg_i(key: String) -> int:
	return _args[key].to_int()


func _has_user_arg(key: String) -> bool:
	for a: String in OS.get_cmdline_user_args():
		if a.trim_prefix("--").begins_with(key + "="):
			return true
	return false


static func _parse_value(s: String) -> Variant:
	if s == "true" or s == "false":
		return s == "true"
	if s.is_valid_int():
		return s.to_int()
	if s.is_valid_float():
		return s.to_float()
	return s


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var ok := true
	if _flags.has("hide-ui"):
		_hide_canvas_layers(current_scene)
		await process_frame
		await RenderingServer.frame_post_draw
	var win := DisplayServer.window_get_size()
	if _args.has("size"):
		var want := _args["size"].split("x")
		if want.size() != 2 or Vector2i(int(want[0]), int(want[1])) != win:
			push_error("capture: window is %dx%d, --size=%s (pass --resolution %s)"
					% [win.x, win.y, _args["size"], _args["size"]])
			ok = false
	if not _fixed_delta:
		_warnings.append("frame delta varied: run with --fixed-fps 30")
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var meta := _metadata(img.get_size())
	var err := OK
	var path := ""
	if _args["out"] != NO_STILL:
		path = _resolve(_args["out"])
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		err = img.save_png(path) if ok else ERR_INVALID_PARAMETER
		ok = ok and err == OK
		var f := FileAccess.open(path + ".json", FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(meta, "\t", false))
			f.close()
	for w: String in _warnings:
		push_warning("capture: " + w)
	print("capture: %s %s (%s, %dx%d, %d frames, deterministic=%s) err=%d" % [
		"saved" if ok else "FAILED", path if path != "" else "(no still)", meta["driver"], img.get_width(),
		img.get_height(), _arg_i("frames"), meta["deterministic"], err])
	var game := root.get_node_or_null("Game")
	if game != null:
		game.call("quit_cleanly", EXIT_OK if ok else EXIT_FAILED)
	else:
		quit(EXIT_OK if ok else EXIT_FAILED)


func _resolve(p: String) -> String:
	if p.begins_with("res://") or p.begins_with("user://"):
		return ProjectSettings.globalize_path(p)
	if p.is_absolute_path():
		return p
	return ProjectSettings.globalize_path("res://").path_join(p)


func _hide_canvas_layers(node: Node) -> void:
	if node == null:
		return
	for c: Node in node.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
		else:
			_hide_canvas_layers(c)


func _metadata(size: Vector2i) -> Dictionary:
	var tod := root.get_node("TimeOfDay")
	var clock := root.get_node("Clock")
	var game := root.get_node("Game")
	var sim: Object = game.get("sim")
	var install_seed := ""
	if sim != null:
		var state: Object = sim.get("state")
		install_seed = str(state.get("install_seed"))
	var deterministic := _fixed_delta and not _save_present and _has_user_arg("seed")
	return {
		"tool": "tools/qa/capture.gd",
		"engine": Engine.get_version_info()["string"],
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"method": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"adapter_version": RenderingServer.get_video_adapter_api_version(),
		"image_size": [size.x, size.y],
		"viewport_size": [root.get_visible_rect().size.x, root.get_visible_rect().size.y],
		"frames": _arg_i("frames"),
		"frame_delta": _first_delta,
		"args": Array(OS.get_cmdline_user_args()),
		"now_unix": clock.call("now_unix"),
		"tz_offset_s": clock.call("tz_offset_s"),
		"g_time": clock.get("g_time"),
		"g_day": tod.get("g_day"),
		"phase": str(tod.get("phase")),
		"weather": str(tod.get("weather")),
		"install_seed": install_seed,
		"hide_ui": _flags.has("hide-ui"),
		"deterministic": deterministic,
		"warnings": Array(_warnings),
		"text_regions": [] if _flags.has("hide-ui") else _text_regions(),
	}


## Screen-space rects of every visible text control, with its declared font colour, so
## tools/qa/metrics.py can check contrast against the pixels actually behind it (X2).
func _text_regions() -> Array:
	var out: Array = []
	var xf := root.get_final_transform()
	_collect_text(current_scene, xf, out)
	return out


func _collect_text(node: Node, final_xf: Transform2D, out: Array) -> void:
	if node == null:
		return
	for c: Node in node.get_children():
		_collect_text(c, final_xf, out)
	var ctl := node as Control
	if ctl == null or not ctl.is_visible_in_tree() or ctl.modulate.a <= 0.0:
		return
	var text := ""
	if ctl is Label:
		text = (ctl as Label).text
	elif ctl is Button:
		text = (ctl as Button).text
	elif ctl is RichTextLabel:
		text = (ctl as RichTextLabel).get_parsed_text()
	elif ctl is LineEdit:
		text = (ctl as LineEdit).text
	if text.strip_edges().is_empty():
		return
	var r := final_xf * ctl.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, ctl.size)
	var col := Color(0, 0, 0, 0)
	if ctl is Label or ctl is Button:
		col = ctl.get_theme_color(&"font_color") * _tree_modulate(ctl)
	out.append({
		"path": str(ctl.get_path()),
		"type": ctl.get_class(),
		"rect": [r.position.x, r.position.y, r.size.x, r.size.y],
		"font_color": [col.r, col.g, col.b, col.a],
		"font_size": ctl.get_theme_font_size(&"font_size"),
		"chars": text.length(),
	})


## modulate is inherited down a chain of CanvasItems (it stops at a non-CanvasItem parent).
static func _tree_modulate(item: CanvasItem) -> Color:
	var m := item.self_modulate
	var n: Node = item
	while n is CanvasItem:
		m *= (n as CanvasItem).modulate
		n = n.get_parent()
	return m
