class_name FloraBuilder
extends RefCounted
## Builds the flower-bed meshes (Art Bible A3, §4.10, §6.1-6.3): every planted stem of a bed is
## tapered stem strips + leaf, petal, bud and head stamps from the tone-mask atlas
## (art/flora/flora_atlas.svg; regions, pivots and the per-form grammar in flora_atlas.json),
## written into ONE ArrayMesh per bed (one draw call). Pure apart from reading the atlas JSON: the
## same stems give the same mesh after every load (seed = hash(bed, slot, flower)).
##
## Vertex layout (shaders/flora/flora_bed.gdshader reads it):
##   COLOR    r = LUT row / 15, g = part kind / 15, b = height on the stem 0..1, a = part alpha
##   CUSTOM0  x = sway amplitude at the tip px, y = sway loop k, z = bloom mix 0..1, w = jitter -1..1
##   CUSTOM1  xy = attach point (local px), z = stem length px, w = phase rad
## Stems are drawn back to front (by root y); inside a stem: foliage at the foot, rosette leaves,
## the stem strip, stem leaves, then the bud or the head, so nothing z-fights (§4.10 acceptance).
##
## Stage visuals (§6.2): seed = soil mound + a twinkling glint; sprout = stem 30->60 % with two
## cotyledons; bud = all leaves, stem 85->100 %, the bud swelling 0.6->1; bloom = the full head.
## The unfurl (§6.2) is driven by [member Stem.unfurl_s]: 60 ms anticipation (bud swell 1.08),
## petals open from 15 % of their angle at scale 0.55 over 420 ms on emphasized_decel, staggered
## 30 ms in angular order, colour bud -> petal, 3-5 sparkles over 400 ms.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const ATLAS_JSON := "res://art/flora/flora_atlas.json"
## Part kinds (shaders/flora/flora_bed.gdshader PART_*; keep in sync).
const PART_STEM := 0
const PART_LEAF := 1
const PART_PETAL := 2
const PART_BUD := 3
const PART_CENTRE := 4
const PART_SOIL := 5
const PART_MOSS := 6
const PART_SPARKLE := 7
const PART_BELL := 8
const PART_FOLIAGE := 9
const PART_STAMEN := 10
## Seed glints and dew beads: twinkle every 600/76 s in the shader (Art Bible §6.2).
const PART_GLINT := 11
const PART_DIV := 15.0
## LUT layout (8 x 10): rows 0-7 flowers in garden_order, 8 ground materials, 9 FX colours.
const LUT_COLS := 8
const LUT_ROWS := 10
const ROW_GROUND := 8
const ROW_FX := 9
## Art Bible §6.1: stem strips have 6 segments.
const STEM_SEGMENTS := 6
## Pedicel / petiole strips are shorter.
const SHORT_SEGMENTS := 3
const UP := -PI * 0.5
## Art Bible §6.2: petals open from 15 % of their open angle at scale 0.55.
const FOLD_ANGLE := 0.15
const FOLD_SCALE := 0.55
## A stamp whose pivot is this far from its centre has a forward axis (pivot -> centre).
const PIVOT_AXIS_MIN := 0.2
## Sparkles: radius around the head, size at depth 1 (px).
const SPARKLE_RING := 0.75
## Round 3: unfurl sparkles read at 1:1 on a phone (14 px vanished in the touch-strip stills).
const SPARKLE_PX := 22.0
## Back petals of the 3/4 cup sit in the cup's shadow (lightness jitter units).
const BACK_PETAL_DARK := 0.8
## Clusters: golden-angle spiral, slightly squashed for the 3/4 view.
const GOLDEN_ANGLE := 2.39996
const CLUSTER_SQUASH := 0.85
## Folded petals fade in over the first 15 % of their opening (a closed head is just the bud).
const PETAL_FADE_IN := 0.15

## One planted stem as the view sees it now. Positions are local px of the bed node.
class Stem:
	extends RefCounted
	var flower: StringName = &""
	var form: String = "globe"
	var row: int = 0
	var root := Vector2.ZERO
	var depth: float = 1.0
	var seed: int = 0
	## 0 seed, 1 sprout, 2 bud, 3 bloom (visual stage: a ready bud is stage 2 with ready = true).
	var stage: int = 3
	## Progress 0..1 inside the sprout and bud stages (time-lerped growth, §6.2).
	var growth: float = 1.0
	## Bloom openness when not animating (moonbloom closes by day: 0).
	var open: float = 1.0
	## Seconds since the unfurl began (>= 0 animates; -1 = use [member open]).
	var unfurl_s: float = -1.0
	## 1 = the tapped 600 ms unfurl, 0.25 = the slow 2.4 s auto unfurl.
	var unfurl_rate: float = 1.0
	var swell: float = 1.0
	var stretch: float = 1.0
	## New parts after a watched growth step: scale 0.6 -> 1 and fade (0..1).
	var pop: float = 1.0
	var alpha: float = 1.0
	var ready: bool = false

var atlas_size := Vector2(1024, 256)
var stamps: Dictionary = {}
var forms: Dictionary = {}
var growth_rules: Dictionary = {}
## Head (or bud / seed) position of each stem of the last build, by index in the input array.
var tips: Dictionary = {}

var _unfurl: Dictionary = {}
var _petal_curve: CubicBezier
var _sway_amp := Vector2(12.0, 24.0)
var _sway_k := Vector2i(120, 270)
var _max_stem_len: float = 120.0
## flora_atlas.json bed_scale: stem, head, leaf, base, stem_w multipliers.
var _k_stem: float = 1.0
var _k_head: float = 1.0
var _k_leaf: float = 1.0
var _k_base: float = 1.0
var _k_stem_w: float = 1.0
# Mesh buffers of the build in progress.
var _v := PackedVector2Array()
var _uv := PackedVector2Array()
var _col := PackedColorArray()
var _c0 := PackedFloat32Array()
var _c1 := PackedFloat32Array()
var _idx := PackedInt32Array()
# Context of the stem being emitted.
var _row: int = 0
var _amp: float = 0.0
var _k: float = 120.0
var _jit: float = 0.0
var _phase: float = 0.0
var _alpha: float = 1.0
var _len: float = 1.0
var _root := Vector2.ZERO


func _init(doc: Dictionary, motion_tokens: Dictionary) -> void:
	var size: Array = doc.get("size", [1024, 256])
	atlas_size = Vector2(float(size[0]), float(size[1]))
	stamps = doc.get("stamps", {})
	forms = doc.get("forms", {})
	growth_rules = doc.get("growth", {})
	var bs: Dictionary = doc.get("bed_scale", {})
	_k_stem = float(bs.get("stem", 1.0))
	_k_head = float(bs.get("head", 1.0))
	_k_leaf = float(bs.get("leaf", 1.0))
	_k_base = float(bs.get("base", 1.0))
	_k_stem_w = float(bs.get("stem_w", 1.0))
	for f: Dictionary in forms.values():
		_max_stem_len = maxf(_max_stem_len, float(f.get("stem_len", 0.0)))
	var flora: Dictionary = motion_tokens.get("flora", {})
	_unfurl = flora.get("unfurl", {})
	var sway: Dictionary = flora.get("sway", {})
	var amp: Array = sway.get("amp_tip_px", [12, 24])
	_sway_amp = Vector2(float(amp[0]), float(amp[1]))
	var lk: Dictionary = motion_tokens.get("loops_k", {})
	var fk: Array = lk.get("flower_sway", [120, 270])
	_sway_k = Vector2i(int(fk[0]), int(fk[1]))
	var curves: Dictionary = motion_tokens.get("curves", {})
	var pc: Dictionary = curves.get(String(_unfurl.get("petal_curve", "emphasized_decel")), {})
	_petal_curve = CubicBezier.from_array(pc.get("bezier", [0.05, 0.7, 0.1, 1.0]))


static func load_doc() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_JSON))
	return parsed if parsed is Dictionary else {}


## Deterministic per-stem seed (Art Bible §6.1: hash(bed id, stem index, flower id)).
static func stem_seed(bed_id: StringName, slot: int, flower_id: StringName) -> int:
	return hash([String(bed_id), slot, String(flower_id)])


## The 8 x 10 flora LUT (§4.10) from palettes.json; petal-lit alpha = night emission.
static func build_lut(content: GameContent) -> Image:
	var img := Image.create(LUT_COLS, LUT_ROWS, false, Image.FORMAT_RGBA8)
	var pal: Dictionary = content.palettes
	var flowers: Dictionary = pal["flora"]["flowers"]
	for i in mini(content.flowers.size(), ROW_GROUND):
		var tok: Dictionary = flowers.get(String(content.flowers[i]["petal_token"]), {})
		if tok.is_empty():
			continue
		var petal: Array = tok["petal"]
		var leaf: Array = tok["leaf"]
		var cols := [petal[0], petal[1], petal[2], leaf[0], leaf[1], leaf[2], tok["stem"], tok["bud"]]
		for c in LUT_COLS:
			var colr := Color.html(String(cols[c]))
			if c == 0:
				colr.a = float(tok.get("night_emission", 0.0))
			img.set_pixel(c, i, colr)
	var mats: Dictionary = pal["materials"]
	var soil: Dictionary = mats["soil"]
	var moss: Dictionary = mats["moss"]
	var ground := [soil["lit"], soil["shade"], soil["detail"], moss["lit"], moss["shade"], moss["detail"],
		moss["lit"], moss["shade"]]
	for c in LUT_COLS:
		img.set_pixel(c, ROW_GROUND, Color.html(String(ground[c])))
	var fx: Dictionary = pal["fx"]
	var fxc := [fx["sparkle"], fx["pollen"], fx["firefly_core"]]
	for c in fxc.size():
		img.set_pixel(c, ROW_FX, Color.html(String(fxc[c])))
	return img


## LUT row of a flower id (its garden_order index), 0 if unknown.
static func row_of(content: GameContent, flower_id: StringName) -> int:
	for i in content.flowers.size():
		if StringName(content.flowers[i]["id"]) == flower_id:
			return i
	return 0


func build_mesh(stems: Array[Stem], extras: Array[Dictionary] = []) -> ArrayMesh:
	return _mesh_of(build_arrays(stems, extras))


## Mesh arrays (Mesh.ARRAY_MAX entries) for the stems, back to front, then loose stamps on top
## ([param extras]: {stamp, pos, scale, part, row, alpha}; the planting seed arc and soil puff).
func build_arrays(stems: Array[Stem], extras: Array[Dictionary] = []) -> Array:
	begin()
	tips.clear()
	var order: Array[int] = []
	for i in stems.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ra := stems[a].root
		var rb := stems[b].root
		return ra.y < rb.y or (ra.y == rb.y and ra.x < rb.x))
	for i in order:
		_emit_cushion(stems[i])
	for i in order:
		_emit_stem(stems[i], i)
	for e: Dictionary in extras:
		var sc := float(e.get("scale", 1.0))
		add_stamp(String(e["stamp"]), e["pos"] as Vector2, 0.0, Vector2(sc, sc), int(e.get("part", PART_SOIL)),
				int(e.get("row", 0)), float(e.get("alpha", 1.0)))
	return _arrays()


## Loose stamps outside any stem (butterflies, the planting seed and soil puff): begin(),
## add_stamp() per stamp (pivot at [param pos], rotation, signed scale), then end_mesh().
func begin() -> void:
	_v = PackedVector2Array()
	_uv = PackedVector2Array()
	_col = PackedColorArray()
	_c0 = PackedFloat32Array()
	_c1 = PackedFloat32Array()
	_idx = PackedInt32Array()


func add_stamp(stamp: String, pos: Vector2, rot: float, sc: Vector2, part: int, row: int, alpha: float = 1.0,
		bloom: float = 1.0) -> void:
	_row = row
	_alpha = alpha
	_amp = 0.0
	_jit = 0.0
	_root = pos
	_len = 1.0
	_part_at(stamp, pos, rot, sc, part, 0.0, pos, bloom)


func end_mesh() -> ArrayMesh:
	return _mesh_of(_arrays())


func _arrays() -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_COLOR] = _col
	arrays[Mesh.ARRAY_CUSTOM0] = _c0
	arrays[Mesh.ARRAY_CUSTOM1] = _c1
	arrays[Mesh.ARRAY_INDEX] = _idx
	return arrays


static func _mesh_of(arrays: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if (arrays[Mesh.ARRAY_VERTEX] as PackedVector2Array).is_empty():
		return mesh
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return mesh


# ================================================================= one stem

## The bed's moss cushion: a felted pad under every planted stem, drawn before all stems so the
## pads merge into one tended mound that the flowers grow out of.
func _emit_cushion(st: Stem) -> void:
	var stamp := String(growth_rules.get("cushion", ""))
	if stamp == "" or not stamps.has(stamp):
		return
	_row = ROW_GROUND
	_alpha = st.alpha
	_amp = 0.0
	_jit = 0.0
	_phase = 0.0
	_root = st.root
	_len = 1.0
	var sc := float(growth_rules.get("cushion_scale", 0.7)) * st.depth * _k_base
	var p := st.root + Vector2(0.0, float(growth_rules.get("cushion_dy", 4.0)) * st.depth)
	_part_at(stamp, p, 0.0, Vector2(sc, sc * 0.9), PART_MOSS, 0.0, p)


func _emit_stem(st: Stem, index: int) -> void:
	var form: Dictionary = forms.get(st.form, {})
	if form.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = st.seed
	var jit: Dictionary = growth_rules.get("jitter", {})
	var s_j := 1.0 + rng.randf_range(-1.0, 1.0) * float(jit.get("scale", 0.1))
	var rot_j := deg_to_rad(rng.randf_range(-1.0, 1.0) * float(jit.get("rot_deg", 5.0)))
	_row = st.row
	_jit = rng.randf_range(-1.0, 1.0) * float(jit.get("lightness", 1.0))
	_phase = rng.randf() * TAU
	_k = float(rng.randi_range(_sway_k.x, _sway_k.y))
	_alpha = st.alpha
	_root = st.root
	var scale := st.depth * s_j
	var hscale := scale * _k_head
	var lscale := scale * _k_leaf
	var full_len := float(form["stem_len"]) * scale * _k_stem
	_amp = lerpf(_sway_amp.x, _sway_amp.y, clampf(float(form["stem_len"]) / _max_stem_len, 0.0, 1.0)) * st.depth
	# Foot: a felted cushion of small leaves sinks the stem into the meadow (grounding).
	var base := String(form.get("base", ""))
	if st.stage == WorldSim.STAGE_SEED:
		_amp = 0.0
		_len = 1.0
		var seed_scale := float(growth_rules.get("seed_scale", 0.8)) * scale
		_part_at(String(growth_rules.get("seed_stamp", "soil_mound")), st.root, 0.0, Vector2.ONE * seed_scale * st.pop,
				PART_SOIL, 0.0, st.root)
		var glint_pos := st.root + Vector2(rng.randf_range(-6.0, 6.0), -6.0) * scale
		_glint(glint_pos, scale, 0.0)
		tips[index] = st.root + Vector2(0.0, -4.0) * scale
		return
	if base != "":
		var bs := float(form.get("base_scale", 1.0)) * scale * _k_base * lerpf(0.55, 1.0, _stage_mix(st))
		_part_at(base, st.root + Vector2(0.0, 2.0) * scale, 0.0, Vector2(bs, bs), PART_FOLIAGE, 0.0, st.root)
	# Stem length by stage (§6.2) and lean (seeded ±lean, ±5° jitter).
	var gr: Dictionary = growth_rules
	var len_f := 1.0
	if st.stage == WorldSim.STAGE_SPROUT:
		var r: Array = gr.get("sprout_stem", [0.3, 0.6])
		len_f = lerpf(float(r[0]), float(r[1]), st.growth)
	elif st.stage == WorldSim.STAGE_BUD:
		var r2: Array = gr.get("bud_stem", [0.85, 1.0])
		len_f = lerpf(float(r2[0]), float(r2[1]), st.growth)
	var lean := deg_to_rad(rng.randf_range(-1.0, 1.0) * float(form.get("lean_deg", 8.0))) + rot_j
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var head: Dictionary = form.get("head", {})
	var kind := String(head.get("kind", ""))
	var leaf_pop := st.pop if st.stage <= WorldSim.STAGE_BUD else 1.0
	# Rosette leaves (bluebell, primrose, dandelion, moonbloom) fan from the foot.
	if st.stage >= WorldSim.STAGE_BUD:
		for lf: Dictionary in form.get("rosette", []):
			var a := deg_to_rad(float(lf["angle"])) * (side if absf(float(lf["angle"])) > 10.0 else 1.0)
			var sc := float(lf["scale"]) * lscale * leaf_pop * lerpf(0.75, 1.0, _stage_mix(st))
			_len = full_len
			_leaf(String(lf["stamp"]), st.root + Vector2(0.0, -1.0) * scale, UP + a + rot_j * 0.5, sc, 0.0)
	if kind == "primrose" and st.stage == WorldSim.STAGE_BLOOM:
		_emit_primrose(st, head, hscale, scale * _k_stem, rng, index)
		return
	var length := full_len * len_f * st.stretch
	_len = maxf(length, 1.0)
	var curve := _stem_curve(st.root, length, lean, side, form)
	_strip(curve, float((form["stem_w"] as Array)[0]) * scale * _k_stem_w,
			float((form["stem_w"] as Array)[1]) * scale * _k_stem_w, STEM_SEGMENTS, -1.0)
	var tip: Vector2 = curve[2]
	if st.stage == WorldSim.STAGE_SPROUT:
		var cot := String(gr.get("cotyledon", "cotyledon"))
		var cs := float(gr.get("cotyledon_scale", 1.0)) * lscale * st.pop
		_part_at(cot, tip, UP - deg_to_rad(40.0), Vector2(cs, -cs), PART_LEAF, 1.0, tip)
		_part_at(cot, tip, UP + deg_to_rad(40.0), Vector2(cs, cs), PART_LEAF, 1.0, tip)
		tips[index] = tip
		return
	for lf: Dictionary in form.get("leaves", []):
		var at := float(lf["at"])
		var p := _bez(curve, at)
		var ls := float(lf["side"]) * side
		var dir := UP + ls * deg_to_rad(float(lf["angle"])) + rot_j
		var sc := float(lf["scale"]) * lscale * leaf_pop
		var petiole := float(lf.get("petiole", 0.0)) * scale * _k_stem
		if petiole > 0.0:
			var end := p + Vector2.from_angle(dir) * petiole
			_strip([p, (p + end) * 0.5, end], 1.6 * scale, 1.2 * scale, SHORT_SEGMENTS, at)
			_leaf(String(lf["stamp"]), end, dir, sc, at, p)
		else:
			_leaf(String(lf["stamp"]), p, dir, sc, at, p)
	tips[index] = tip
	var bloom := st.stage == WorldSim.STAGE_BLOOM and not st.ready
	var bud: Dictionary = form.get("bud", {})
	var bud_scale := float(bud.get("scale", 1.0)) * hscale
	if not bloom:
		var swell_r: Array = gr.get("bud_swell", [0.6, 1.0])
		var growing := st.stage == WorldSim.STAGE_BUD and not st.ready
		var g := lerpf(float(swell_r[0]), float(swell_r[1]), st.growth) if growing else 1.0
		_bud(String(bud.get("stamp", "bud_round")), tip, curve, bud_scale * g * st.swell * st.pop, 0.0)
		return
	var opens := _openness(st)
	var mean_open := _mean(opens)
	if mean_open < 1.0:
		var bud_alpha := 1.0 - smoothstep(0.0, 0.45, mean_open)
		if bud_alpha > 0.0:
			var saved := _alpha
			_alpha *= bud_alpha
			_bud(String(bud.get("stamp", "bud_round")), tip, curve, bud_scale * _anticipation(st) * st.swell, mean_open)
			_alpha = saved
	match kind:
		"globe", "puff":
			_emit_ball(head, tip, hscale, mean_open)
		"radial", "lily":
			_emit_radial(head, tip, hscale, opens, rng)
		"cup":
			_emit_cup(head, tip, hscale, opens)
		"cluster":
			_emit_cluster(head, tip, curve, hscale, opens, rng, side)
		"bells":
			_emit_bells(head, curve, hscale, opens, rng, side)
	if mean_open > 0.6:
		_glint(tip + Vector2(rng.randf_range(-8.0, 8.0), rng.randf_range(-6.0, 2.0)) * hscale, scale, 1.0)
	_sparkles(st, tip, hscale, rng)


func _stage_mix(st: Stem) -> float:
	match st.stage:
		WorldSim.STAGE_SPROUT:
			return 0.0
		WorldSim.STAGE_BUD:
			return 0.5 + 0.5 * st.growth
	return 1.0


## Per-petal openness 0..1 (unfurl stagger in angular order) for up to 16 petals.
func _openness(st: Stem) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(16)
	if st.unfurl_s < 0.0:
		out.fill(clampf(st.open, 0.0, 1.0))
		return out
	var t := st.unfurl_s * 1000.0 * st.unfurl_rate
	var antic := float(_unfurl.get("anticipation_ms", 60))
	var dur := float(_unfurl.get("petal_open_ms", 420))
	var stag := float(_unfurl.get("petal_stagger_ms", 30))
	# Stagger steps wrap so the last petal still lands inside total_ms (60 + 4 x 30 + 420 = 600).
	var total := float(_unfurl.get("total_ms", 600))
	var steps := maxi(1, int(floor((total - antic - dur) / maxf(stag, 1.0))) + 1)
	for i in out.size():
		out[i] = _petal_curve.progress(clampf((t - antic - stag * float(i % steps)) / dur, 0.0, 1.0))
	return out


func _anticipation(st: Stem) -> float:
	if st.unfurl_s < 0.0:
		return 1.0
	var t := st.unfurl_s * 1000.0 * st.unfurl_rate
	var antic := float(_unfurl.get("anticipation_ms", 60))
	var sw := float(_unfurl.get("bud_swell", 1.08))
	return lerpf(1.0, sw, clampf(t / antic, 0.0, 1.0))


static func _mean(a: PackedFloat32Array) -> float:
	var s := 0.0
	for v: float in a:
		s += v
	return s / maxf(1.0, float(a.size()))


# ================================================================= heads

func _emit_ball(head: Dictionary, tip: Vector2, scale: float, o: float) -> void:
	var sc := float(head.get("scale", 1.0)) * scale * lerpf(FOLD_SCALE, 1.0, o)
	_part_at(String(head["stamp"]), tip, 0.0, Vector2(sc, sc), PART_PETAL, 1.0, tip, o)


func _emit_radial(head: Dictionary, tip: Vector2, scale: float, opens: PackedFloat32Array,
		rng: RandomNumberGenerator) -> void:
	var n := int(head.get("count", 8))
	var squash := float(head.get("squash", 1.0))
	var radius := float(head.get("radius", 0.0)) * scale
	var ps := float(head.get("petal_scale", 1.0)) * scale
	var tilt := deg_to_rad(float(head.get("tilt_deg", 0.0)))
	var off := rng.randf() * TAU
	var centre := tip + Vector2(0.0, -2.0 * scale)
	# Back (upper) petals first, then front ones over them.
	var order: Array[int] = []
	for i in n:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return sin(off + TAU * float(a) / float(n)) < sin(off + TAU * float(b) / float(n)))
	var mean := _mean(opens)
	for i in order:
		var th := off + TAU * float(i) / float(n) + deg_to_rad(rng.randf_range(-6.0, 6.0))
		var o := opens[i % opens.size()]
		var d := Vector2(cos(th), sin(th) * squash)
		var fore := d.length()
		var dir := d.angle() + tilt
		var a := _fold_angle(dir, o)
		var sc := lerpf(FOLD_SCALE, 1.0, o)
		var pos := centre + Vector2.from_angle(a) * radius * lerpf(0.3, 1.0, o)
		var sv := Vector2(ps * sc * lerpf(1.0, fore, o), ps * sc)
		if cos(a) < 0.0:
			sv.y = -sv.y
		var saved_a := _alpha
		_alpha *= _petal_fade(o)
		_part_at(String(head["petal"]), pos, a, sv, PART_PETAL, 1.0, tip, o, true)
		_alpha = saved_a
	if head.has("centre"):
		var cs := float(head.get("centre_scale", 1.0)) * scale * lerpf(0.4, 1.0, mean)
		var kind := PART_STAMEN if String(head["centre"]) == "stamens" else PART_CENTRE
		var c_alpha := smoothstep(0.15, 0.6, mean)
		var saved := _alpha
		_alpha *= c_alpha
		_part_at(String(head["centre"]), centre, tilt, Vector2(cs, cs * (1.0 if kind == PART_STAMEN else squash)),
				kind, 1.0, tip, mean, false)
		_alpha = saved


func _emit_cup(head: Dictionary, tip: Vector2, scale: float, opens: PackedFloat32Array) -> void:
	var ps := float(head.get("petal_scale", 1.0)) * scale
	var petals: Array = head.get("petals", [])
	for i in petals.size():
		var pdef: Array = petals[i]
		var o := opens[i]
		var a := UP + deg_to_rad(float(pdef[0])) * lerpf(FOLD_ANGLE, 1.0, o)
		var sc := float(pdef[1]) * ps * lerpf(FOLD_SCALE + 0.2, 1.0, o)
		var saved := _alpha
		var saved_jit := _jit
		_alpha *= _petal_fade(o)
		if int(pdef[2]) == 0:
			_jit -= BACK_PETAL_DARK
		_part_at(String(head["petal"]), tip, a, Vector2(sc, sc), PART_PETAL, 1.0, tip, o, true)
		_jit = saved_jit
		_alpha = saved


func _emit_cluster(head: Dictionary, tip: Vector2, curve: Array, scale: float, opens: PackedFloat32Array,
		rng: RandomNumberGenerator, side: float) -> void:
	# A rounded bunch (phyllotaxis: golden-angle spiral, r ~ sqrt) that leans with the curling tip;
	# at this scale it reads better than a strict scorpioid curl, and keeps the curl's lean.
	var n := int(head.get("count", 7))
	var r := float(head.get("curl_r", 9.0)) * scale
	var bs: Array = head.get("bloom_scale", [0.6, 0.75])
	var tan := (_bez_tangent(curve, 1.0)).normalized()
	var perp := Vector2(-tan.y, tan.x) * side
	var c := tip + perp * r * 0.35 + tan * r * 0.45
	var a0 := rng.randf() * TAU
	for j in n:
		var a := a0 + GOLDEN_ANGLE * float(j)
		var rr := r * sqrt((float(j) + 0.5) / float(n))
		var p := c + Vector2(cos(a), sin(a) * CLUSTER_SQUASH) * rr
		var o := opens[j % opens.size()]
		var sc := rng.randf_range(float(bs[0]), float(bs[1])) * scale * lerpf(0.35, 1.0, o)
		var saved := _alpha
		_alpha *= _petal_fade(o)
		_part_at(String(head["stamp"]), p, rng.randf_range(-0.4, 0.4), Vector2(sc, sc), PART_PETAL, 1.0, tip, o)
		_alpha = saved
	var nb := int(head.get("buds", 0))
	for j in nb:
		var a2 := tan.angle() + side * (0.5 + 0.7 * float(j))
		var p2 := c + Vector2.from_angle(a2) * r * 1.05
		var sc2 := float(head.get("bud_scale", 0.4)) * scale
		_part_at(String(head.get("bud_stamp", "bud_round")), p2, a2 + PI * 0.5, Vector2(sc2, sc2), PART_BUD, 1.0, tip,
				0.6)


func _emit_bells(head: Dictionary, curve: Array, scale: float, opens: PackedFloat32Array,
		rng: RandomNumberGenerator, side: float) -> void:
	var cr: Array = head.get("count", [4, 6])
	var n := rng.randi_range(int(cr[0]), int(cr[1]))
	var from := float(head.get("from", 0.5))
	var bsr: Array = head.get("bell_scale", [1.0, 1.2])
	for j in n:
		var t := lerpf(from, 1.0, float(j) / float(maxi(n - 1, 1)))
		var p := _bez(curve, t)
		var tan := _bez_tangent(curve, t).normalized()
		var outward := Vector2(-tan.y, tan.x) * side
		var hang := p + outward * 2.5 * scale
		var o := opens[j % opens.size()]
		var sc := rng.randf_range(float(bsr[0]), float(bsr[1])) * scale * lerpf(FOLD_SCALE, 1.0, o) * lerpf(0.85, 1.0, t)
		var nod := deg_to_rad(rng.randf_range(-12.0, 12.0)) + side * deg_to_rad(10.0) * (1.0 - t)
		var saved := _alpha
		_alpha *= _petal_fade(o)
		_part_at(String(head["stamp"]), hang, PI * 0.5 + nod, Vector2(sc, sc), PART_BELL, t, hang, o, false, true)
		_alpha = saved


func _emit_primrose(st: Stem, head: Dictionary, scale: float, len_scale: float, rng: RandomNumberGenerator,
		index: int) -> void:
	var fr: Array = head.get("flowers", [3, 5])
	var n := rng.randi_range(int(fr[0]), int(fr[1]))
	var spread := deg_to_rad(float(head.get("spread_deg", 30.0)))
	var pr: Array = head.get("pedicel", [0.6, 1.0])
	var form: Dictionary = forms[st.form]
	var base_len := float(form["stem_len"]) * len_scale * st.stretch
	var opens := _openness(st)
	var squash := float(head.get("squash", 1.0))
	var ps := float(head.get("petal_scale", 1.0)) * scale
	var sw: Array = form["stem_w"]
	var top := st.root
	for f in n:
		var a := UP + lerpf(-spread, spread, (float(f) + 0.5) / float(n)) + deg_to_rad(rng.randf_range(-6.0, 6.0))
		var l := base_len * rng.randf_range(float(pr[0]), float(pr[1]))
		_len = maxf(l, 1.0)
		var tip := st.root + Vector2.from_angle(a) * l
		var mid := st.root + Vector2.from_angle(a) * l * 0.5 + Vector2(sin(a) * 4.0, 0.0) * scale
		_strip([st.root, mid, tip], float(sw[0]) * st.depth * _k_stem_w, float(sw[1]) * st.depth * _k_stem_w,
				SHORT_SEGMENTS, -1.0)
		var off := rng.randf() * TAU
		var mean := 0.0
		for i in 5:
			var th := off + TAU * float(i) / 5.0
			var o := opens[(i + f * 2) % opens.size()]
			mean += o * 0.2
			var d := Vector2(cos(th), sin(th) * squash)
			var dir := d.angle()
			var aa := _fold_angle(dir, o)
			var sc := ps * lerpf(FOLD_SCALE, 1.0, o)
			_part_at(String(head["petal"]), tip, aa, Vector2(sc, sc * lerpf(1.0, d.length(), o)), PART_PETAL, 1.0,
					tip, o)
		var saved := _alpha
		_alpha *= smoothstep(0.2, 0.7, mean)
		var cs := float(head.get("centre_scale", 1.0)) * scale
		_part_at(String(head["centre"]), tip, 0.0, Vector2(cs, cs * squash), PART_CENTRE, 1.0, tip, mean)
		_alpha = saved
		if f == 0:
			tips[index] = tip
			top = tip
	_sparkles(st, top, scale, rng)


func _petal_fade(o: float) -> float:
	return smoothstep(0.0, PETAL_FADE_IN, o)


func _fold_angle(dir: float, o: float) -> float:
	var diff := wrapf(dir - UP, -PI, PI)
	return UP + diff * lerpf(FOLD_ANGLE, 1.0, o)


func _bud(stamp: String, tip: Vector2, curve: Array, sc: float, bloom: float) -> void:
	var tan := _bez_tangent(curve, 1.0)
	var a := tan.angle() - UP
	_part_at(stamp, tip, a, Vector2(sc, sc), PART_BUD, 1.0, tip, bloom)


func _glint(pos: Vector2, scale: float, h: float) -> void:
	_part_at("glint", pos, 0.0, Vector2.ONE * scale, PART_GLINT, h, pos)


## Unfurl sparkles: 3-5 over sparkle_ms around the head.
func _sparkles(st: Stem, tip: Vector2, scale: float, rng: RandomNumberGenerator) -> void:
	if st.unfurl_s < 0.0:
		return
	var t := st.unfurl_s * 1000.0 * st.unfurl_rate
	var dur := float(_unfurl.get("sparkle_ms", 400))
	var antic := float(_unfurl.get("anticipation_ms", 60))
	var sr: Array = _unfurl.get("sparkles", [3, 5])
	var n := rng.randi_range(int(sr[0]), int(sr[1]))
	var size := SPARKLE_PX / float((stamps.get("sparkle", {"size": [16, 16]}) as Dictionary)["size"][0])
	for i in n:
		var t0 := antic + dur * 0.5 * float(i) / float(n)
		var u := (t - t0) / (dur * 0.5)
		if u <= 0.0 or u >= 1.0:
			continue
		var a := TAU * float(i) / float(n) + rng.randf() * 0.6
		var p := tip + Vector2.from_angle(a) * SPARKLE_RING * 30.0 * scale * (0.6 + 0.5 * u)
		var sc := size * scale * sin(PI * u)
		var saved := _alpha
		_alpha = sin(PI * u)
		var saved_amp := _amp
		_amp = 0.0
		_part_at("sparkle", p, u * 0.6, Vector2(sc, sc), PART_SPARKLE, 1.0, p, 1.0)
		_amp = saved_amp
		_alpha = saved


# ================================================================= geometry

## Quadratic Bézier [root, control, tip] for a stem of [param length] leaning [param lean] rad.
func _stem_curve(root: Vector2, length: float, lean: float, side: float, form: Dictionary) -> Array:
	var arch := float(form.get("arch", 0.0))
	var tip: Vector2
	var ctrl: Vector2
	if arch > 0.0:
		tip = root + Vector2(side * arch * length + sin(lean) * length * 0.2, -length * 0.8)
		ctrl = root + Vector2(side * arch * length * 0.15, -length * 1.05)
	else:
		tip = root + Vector2(sin(lean), -cos(lean)) * length
		var mid := (root + tip) * 0.5
		var perp := Vector2(cos(lean), sin(lean))
		ctrl = mid + perp * float(form.get("s_curve", 0.1)) * length * side
	return [root, ctrl, tip]


static func _bez(c: Array, t: float) -> Vector2:
	var p0: Vector2 = c[0]
	var p1: Vector2 = c[1]
	var p2: Vector2 = c[2]
	var u := 1.0 - t
	return p0 * u * u + p1 * 2.0 * u * t + p2 * t * t


static func _bez_tangent(c: Array, t: float) -> Vector2:
	var p0: Vector2 = c[0]
	var p1: Vector2 = c[1]
	var p2: Vector2 = c[2]
	var d := (p1 - p0) * 2.0 * (1.0 - t) + (p2 - p1) * 2.0 * t
	return d if d.length_squared() > 1e-6 else Vector2(0.0, -1.0)


## A tapered strip along the curve. fixed_h < 0: each ring takes its own height t (a bending stem);
## otherwise every vertex takes fixed_h (a petiole rides its stem rigidly).
func _strip(curve: Array, w0: float, w1: float, segments: int, fixed_h: float) -> void:
	var st: Dictionary = stamps.get("stem", {})
	if st.is_empty():
		return
	var reg: Array = st["region"]
	var u0 := float(reg[0]) / atlas_size.x
	var u1 := (float(reg[0]) + float(reg[2])) / atlas_size.x
	var v0 := float(reg[1]) / atlas_size.y
	var v1 := (float(reg[1]) + float(reg[3])) / atlas_size.y
	var base := _v.size()
	var attach: Vector2 = curve[0]
	for s in segments + 1:
		var t := float(s) / float(segments)
		var p := _bez(curve, t)
		var d := _bez_tangent(curve, t).normalized()
		var n := Vector2(-d.y, d.x)
		var w := lerpf(w0, w1, t) * 0.5
		var h := t if fixed_h < 0.0 else fixed_h
		var v := lerpf(v1, v0, t)
		_vertex(p - n * w, Vector2(u0, v), PART_STEM, h, attach, -1.0, fixed_h >= 0.0)
		_vertex(p + n * w, Vector2(u1, v), PART_STEM, h, attach, -1.0, fixed_h >= 0.0)
	for s in segments:
		var k := base + s * 2
		_idx.append_array(PackedInt32Array([k, k + 2, k + 1, k + 1, k + 2, k + 3]))


func _leaf(stamp: String, pos: Vector2, dir: float, sc: float, h: float, attach: Variant = null) -> void:
	var sv := Vector2(sc, sc)
	if cos(dir) < 0.0 and _forward_is_x(stamp):
		sv.y = -sv.y
	var at: Vector2 = pos if attach == null else (attach as Vector2)
	_part_at(stamp, pos, dir, sv, PART_LEAF, h, at, 1.0, true)


func _forward_is_x(stamp: String) -> bool:
	var s: Dictionary = stamps.get(stamp, {})
	var pv: Array = s.get("pivot", [0.5, 0.5])
	return absf(0.5 - float(pv[0])) >= absf(0.5 - float(pv[1]))


## Places a stamp with its pivot at [param pos]. With [param directed], [param angle] is the
## direction the stamp points (pivot -> centre); otherwise it is a plain rotation.
## hang = true: the stamp's forward axis is "down" (bells).
func _part_at(stamp: String, pos: Vector2, angle: float, sc: Vector2, part: int, h: float, attach: Vector2,
		bloom: float = 1.0, directed: bool = false, hang: bool = false) -> void:
	var s: Dictionary = stamps.get(stamp, {})
	if s.is_empty():
		return
	var size_a: Array = s["size"]
	var pv: Array = s["pivot"]
	var size := Vector2(float(size_a[0]), float(size_a[1]))
	var pivot := Vector2(float(pv[0]), float(pv[1]))
	var rot := angle
	if directed or hang:
		var fwd := Vector2(0.5, 0.5) - pivot
		if fwd.length() >= PIVOT_AXIS_MIN or hang:
			rot = angle - fwd.angle()
	var reg: Array = s["region"]
	var uv0 := Vector2(float(reg[0]), float(reg[1])) / atlas_size
	var uv1 := Vector2(float(reg[0]) + float(reg[2]), float(reg[1]) + float(reg[3])) / atlas_size
	var corners := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var base := _v.size()
	for c: Vector2 in corners:
		var local := (c - pivot) * size * sc
		var p := pos + local.rotated(rot)
		_vertex(p, Vector2(lerpf(uv0.x, uv1.x, c.x), lerpf(uv0.y, uv1.y, c.y)), part, h, attach, bloom, true)
	_idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


func _vertex(p: Vector2, uv: Vector2, part: int, h: float, attach: Vector2, bloom: float, rigid: bool) -> void:
	_v.append(p)
	_uv.append(uv)
	_col.append(Color(float(_row) / PART_DIV, float(part) / PART_DIV, clampf(h, 0.0, 1.0), clampf(_alpha, 0.0, 1.0)))
	var b := 1.0 if bloom < 0.0 else clampf(bloom, 0.0, 1.0)
	_c0.append_array(PackedFloat32Array([_amp, _k, b, _jit]))
	var a := attach if rigid else _root
	_c1.append_array(PackedFloat32Array([a.x, a.y, _len, _phase]))
