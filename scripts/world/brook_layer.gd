class_name BrookLayer
extends Node2D
## The brook (Art Bible §2.4, §4.7, §6.8): a triangle strip along the Catmull-Rom of the
## spots.json stream polyline (one segment per 12 px of arc, 69 px of water + 10 px damp banks),
## shaded by shaders/world/water.gdshader. Owns the stream tap (GDD §3.1, through WorldPan):
## touch-down inside the tap band -> touch ring + S01 (world); the tap (release) -> eased ripple
## ring to 36 dp in 380 ms + bubbles, S06, and the [signal tapped] signal so nearby awake
## mosslings can glance. Stones (décor) register riffles.
##
## Other roles: find the brook with BrookLayer.current (null when no main scene is loaded).
##   BrookLayer.current.add_ripple(design_pos, 1.0)       # leaf boat wake, a creature pawing water
##   BrookLayer.current.set_stone(&"stone_3", design_pos, 27.0) / remove_stone(&"stone_3")
##
## QA user arg: --qa-brook-tap=<x>[@<ms>] taps the brook at design x as a touch would (ripple +
## flattened TouchRing), both held <ms> into their life (default 150 ms of 380 ms) for a
## frozen-time still (tools/qa/capture.sh). --debug-ripple=<x> is the older alias (ripple only).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## Design px of the tap, after it is clamped onto the water.
signal tapped(design_pos: Vector2)

const SHADER_PATH := "res://shaders/world/water.gdshader"
## Art Bible §4.7: one segment per 12 px of arc length; 10 px damp banks.
const SEGMENT_PX := 12.0
const BANK_PX := 22.0
## Wide-screen bleed on the left (the brook leaves at the left edge, Art Bible §2.1).
const LEFT_BLEED_X := -420.0
const MAX_RIPPLES := 4
const WIDTH_VAR := 0.16
const WIDTH_PERIOD_PX := 260.0
const WIDTH_SEED := 77
const MAX_STONES := 10
## Taps this close to the water outside the band still count (a generous hit, I2).
const HIT_SLACK_PX := 18.0
## Ripples land on the water: their centre is clamped to this fraction of the half width.
const RIPPLE_CLAMP := 0.6
const RIPPLE_MIX := 0.5
const CUE_TOUCH := &"S01"
const CUE_STREAM := &"S06"
const ARG_DEBUG_RIPPLE := "--debug-ripple="
const DEBUG_RIPPLE_AGE_S := 0.15
const ARG_QA_TAP := "--qa-brook-tap="
## The touch ring lies on the water: flattened like the ripple (water.gdshader RIPPLE_SQUASH x 1.3).
const RING_SQUASH := 0.45

static var current: BrookLayer = null

var centre := PackedVector2Array()
var half_width: float = 34.5

var _mat: ShaderMaterial
var _ripples := PackedVector4Array()
var _next_ripple: int = 0
var _stones: Dictionary = {}
var _band := Vector2(1436.0, 1505.0)
var _feed := PaletteFeed.new()
var _ripple_s: float = 0.38


static func polyline_px(content: GameContent) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Variant in content.spots_doc["stream"]["polyline"]:
		var a := PackedFloat64Array(p as Array)
		out.append(GardenRules.frame_to_px(content, Vector2(a[0], a[1])))
	return out


## Half the water width in px: water_width is a fraction of the frame HEIGHT (U4).
static func half_width_px(content: GameContent) -> float:
	var frame: Dictionary = content.spots_doc["frame"]
	return float(content.spots_doc["stream"]["water_width"]) * float(frame["height_px"]) * 0.5


## Least-squares line y = a + b x through the polyline (the meadow's near-bank term).
static func centre_fit(content: GameContent) -> Vector2:
	var pts := polyline_px(content)
	var n := float(pts.size())
	var sx := 0.0
	var sy := 0.0
	var sxx := 0.0
	var sxy := 0.0
	for p: Vector2 in pts:
		sx += p.x
		sy += p.y
		sxx += p.x * p.x
		sxy += p.x * p.y
	var b := (n * sxy - sx * sy) / maxf(n * sxx - sx * sx, 1e-6)
	return Vector2((sy - b * sx) / n, b)


func _ready() -> void:
	current = self
	add_to_group(WorldPan.GROUP_HIT)
	var content := ContentRegistry.content
	var pts := polyline_px(content)
	var last := pts[pts.size() - 1]
	var prev := pts[pts.size() - 2]
	var slope := (last.y - prev.y) / minf(last.x - prev.x, -1.0)
	pts.append(Vector2(LEFT_BLEED_X, last.y + slope * (LEFT_BLEED_X - last.x)))
	centre = TerrainMath.resample_catmull_rom(pts, SEGMENT_PX)
	half_width = half_width_px(content)
	var stream: Dictionary = content.spots_doc["stream"]
	var frame: Dictionary = content.spots_doc["frame"]
	_band = Vector2(float(stream["tap_band_y0"]), float(stream["tap_band_y1"])) * float(frame["height_px"])
	var ui: Dictionary = ContentRegistry.motion_tokens()["ui"]
	_ripple_s = float(ui["stream_ripple_ms"]) / 1000.0
	var ring_px := float(ui["ring"]["radius_dp"]) * float(frame["px_per_dp"])
	_ripples.resize(MAX_RIPPLES)
	_build(ring_px)
	tree_exiting.connect(_on_exit)
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(ARG_DEBUG_RIPPLE):
			var x := a.trim_prefix(ARG_DEBUG_RIPPLE).to_float()
			add_ripple(Vector2(x, centre_y_at(x)), 1.0)
			_ripples[(_next_ripple + MAX_RIPPLES - 1) % MAX_RIPPLES].z = Clock.g_time - DEBUG_RIPPLE_AGE_S
			_mat.set_shader_parameter(&"u_ripples", _ripples)
		elif a.begins_with(ARG_QA_TAP):
			_qa_tap(a.trim_prefix(ARG_QA_TAP))


## QA: "<x>[@<ms>]" -> ripple + touch ring at the brook centre line, frozen <ms> into their life.
func _qa_tap(spec: String) -> void:
	var parts := spec.split("@")
	var x := parts[0].to_float()
	var age := (parts[1].to_float() / 1000.0) if parts.size() > 1 else DEBUG_RIPPLE_AGE_S
	var hit := Vector2(x, centre_y_at(x))
	add_ripple(hit, 1.0)
	_ripples[(_next_ripple + MAX_RIPPLES - 1) % MAX_RIPPLES].z = Clock.g_time - age
	_mat.set_shader_parameter(&"u_ripples", _ripples)
	TouchRing.spawn(self, hit, RING_SQUASH).freeze_at(age)


func _build(ring_px: float) -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH) as Shader
	_mat.set_shader_parameter(&"water_px", half_width * 2.0)
	_mat.set_shader_parameter(&"bank_v", BANK_PX / (half_width * 2.0))
	_mat.set_shader_parameter(&"ripple_s", _ripple_s)
	_mat.set_shader_parameter(&"ripple_radius_px", ring_px)
	var lk: Dictionary = ContentRegistry.motion_tokens()["loops_k"]
	var gk: Array = lk["water_glint"]
	_mat.set_shader_parameter(&"glint_k", Vector2(float(gk[0]), float(gk[1])))
	_mat.set_shader_parameter(&"u_ripples", _ripples)
	_push_stones()
	_feed.bind(_mat, &"water_bank", "water_bank")
	_apply_colors()
	TimeOfDay.globals_updated.connect(func(_v: Dictionary) -> void: _apply_colors())
	LampRegistry.bind_material(_mat)
	var mi := MeshInstance2D.new()
	mi.name = "Water"
	mi.mesh = _strip_mesh()
	mi.material = _mat
	add_child(mi)


## Map pan (ARCHITECTURE §3.4): the water continues straight past its right end (x 1.04 of the
## frame) to the geometry's x_max, so a pan to the right never shows where it stops. Mesh only: the
## centre line (taps, boats, ripples) and the arc length of the original points are unchanged.
func _right_bleed() -> PackedVector2Array:
	var out := PackedVector2Array()
	var dir := (centre[0] - centre[1]).normalized()
	if dir.x <= 0.01:
		return out
	var n := ceili((TerrainMath.X_MAX + BANK_PX + half_width - centre[0].x) / (dir.x * SEGMENT_PX))
	for j in range(n, 0, -1):
		out.append(centre[0] + dir * SEGMENT_PX * float(j))
	return out


func _strip_mesh() -> ArrayMesh:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var bank_v := BANK_PX / (half_width * 2.0)
	var line := _right_bleed()
	var arc := -SEGMENT_PX * float(line.size())
	line.append_array(centre)
	var n := line.size()
	for i in n:
		if i > 0:
			arc += line[i].distance_to(line[i - 1])
		var a := line[maxi(i - 1, 0)]
		var b := line[mini(i + 1, n - 1)]
		var t := (b - a).normalized()
		var nrm := Vector2(-t.y, t.x)
		if nrm.y < 0.0:
			nrm = -nrm  # toward the near (lower) bank
		# The brook breathes in width (+-WIDTH_VAR) so it reads as a natural stream, not a ribbon.
		var wk := 1.0 + WIDTH_VAR * TerrainMath.fbm1(arc / WIDTH_PERIOD_PX, 1.0, 3, 0.5, WIDTH_SEED)
		var far_r := half_width * wk + BANK_PX
		var near_r := half_width * (2.0 - wk) * 0.35 + half_width * wk * 0.65 + BANK_PX
		verts.append(line[i] - nrm * far_r)
		uvs.append(Vector2(arc, -bank_v))
		verts.append(line[i] + nrm * near_r)
		uvs.append(Vector2(arc, 1.0 + bank_v))
	for i in n - 1:
		var k := i * 2
		idx.append_array(PackedInt32Array([k, k + 2, k + 1, k + 1, k + 2, k + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _apply_colors() -> void:
	var cols := TimeOfDay.colors
	_feed.apply(cols)
	if cols.has("water_shallow"):
		# palettes.json fx.ripple = oklab_mix(water_shallow, #FFFDF8 (fx.sparkle), 0.50).
		var white := Color.html(String(ContentRegistry.palettes()["fx"]["sparkle"]))
		_mat.set_shader_parameter(&"ripple_color", PaletteMath.mix_oklab(cols["water_shallow"], white, RIPPLE_MIX))


## Centre-line y of the water at design x (linear between resampled points).
func centre_y_at(x: float) -> float:
	for i in centre.size() - 1:
		var a := centre[i]
		var b := centre[i + 1]
		if (x <= a.x and x >= b.x) or (x >= a.x and x <= b.x):
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x) if absf(b.x - a.x) > 0.001 else 0.0)
	return centre[centre.size() - 1].y if x < centre[centre.size() - 1].x else centre[0].y


## Starts a ripple ring at a design position (tap, leaf boat wake, a creature pawing the water).
func add_ripple(design_pos: Vector2, amplitude: float = 1.0) -> void:
	_ripples[_next_ripple] = Vector4(design_pos.x, design_pos.y, Clock.g_time, amplitude)
	_next_ripple = (_next_ripple + 1) % MAX_RIPPLES
	_mat.set_shader_parameter(&"u_ripples", _ripples)
	FrameGovernor.hold_for(_ripple_s)


func set_stone(key: StringName, design_pos: Vector2, radius_px: float) -> void:
	_stones[key] = Vector3(design_pos.x, design_pos.y, radius_px)
	_push_stones()


func remove_stone(key: StringName) -> void:
	if _stones.erase(key):
		_push_stones()


func _push_stones() -> void:
	if _mat == null:
		return
	var arr := PackedVector3Array()
	arr.resize(MAX_STONES)
	var keys := _stones.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	var n := mini(keys.size(), MAX_STONES)
	for i in n:
		arr[i] = _stones[keys[i]]
	_mat.set_shader_parameter(&"u_stones", arr)
	_mat.set_shader_parameter(&"u_stone_count", n)


## WorldPan (the world input arbiter, ARCHITECTURE §3.5): the water (the tap band, or the water
## +- HIT_SLACK_PX, + slop) is the lowest-priority world target. Touch-down: the touch ring and S01
## in the same frame; the ripple, S06 and [signal tapped] on release (a pan never ripples).
func world_hit(canvas_pos: Vector2, slop: float) -> Dictionary:
	var pos := get_global_transform_with_canvas().affine_inverse() * canvas_pos
	var cy := centre_y_at(pos.x)
	var dy := absf(pos.y - cy)
	var in_band := pos.y >= _band.x and pos.y <= _band.y
	var inside := in_band or dy <= half_width + HIT_SLACK_PX
	if not inside and dy > half_width + HIT_SLACK_PX + slop:
		return {}
	# the water itself is the core; the rest of the tap band is a generous ring (WorldPan.tier)
	return {"prio": WorldPan.PRIO_STREAM, "inside": inside, "core": dy <= half_width, "d": dy, "key": &"stream"}


func world_press(_key: Variant, canvas_pos: Vector2) -> void:
	var hit := _on_water(get_global_transform_with_canvas().affine_inverse() * canvas_pos)
	TouchRing.spawn(self, hit, RING_SQUASH)
	AudioDirector.play_cue(CUE_TOUCH, {"world": true, "position": get_global_transform() * hit})


func world_release(_key: Variant, canvas_pos: Vector2, act: bool) -> void:
	if not act:
		return
	var hit := _on_water(get_global_transform_with_canvas().affine_inverse() * canvas_pos)
	add_ripple(hit, 1.0)
	var canvas_pos2 := get_global_transform() * hit  # canvas px; captions apply the camera
	AudioDirector.play_cue(CUE_STREAM, {"position": canvas_pos2})
	tapped.emit(hit)


## Debug overlay (--debug-hits): the tap band and the water strip, in canvas px.
func world_hit_shapes() -> Array:
	var xf := get_global_transform_with_canvas()
	var pts := PackedVector2Array()
	for p: Vector2 in centre:
		pts.append(xf * p)
	var r := Rect2(xf * Vector2(TerrainMath.X_MIN, _band.x),
			Vector2(TerrainMath.X_MAX - TerrainMath.X_MIN, _band.y - _band.x))
	return [{"kind": "band", "rect": r, "line": pts, "half": (half_width + HIT_SLACK_PX) * xf.get_scale().y,
		"prio": WorldPan.PRIO_STREAM, "name": "stream"}]


## The touch point clamped onto the water (ripples land on the water).
func _on_water(pos: Vector2) -> Vector2:
	var cy := centre_y_at(pos.x)
	return Vector2(pos.x, clampf(pos.y, cy - half_width * RIPPLE_CLAMP, cy + half_width * RIPPLE_CLAMP))


func _on_exit() -> void:
	LampRegistry.unbind_material(_mat)
	if current == self:
		current = null
