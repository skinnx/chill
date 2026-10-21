extends GutTest
## Flower beds (Art Bible A3, §4.10, §6.1-6.3): the flora atlas covers every stamp the grammar
## uses, the builder is deterministic (same stems -> same mesh), every flower form builds at every
## stage with the vertex contract the shader decodes (part kinds, rows, heights, alpha), petals
## stay attached to their stem tip, the unfurl opens petals in order over 600 ms, a ready bud is a
## bud, the LUT carries every flower's colours, and the bed meshes stay a few thousand vertices.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

## 16 stems x ~45 quads x 4 vertices: a full bed must stay well under this.
const MAX_BED_VERTICES := 6000

var c: GameContent
var doc: Dictionary


func before_all() -> void:
	c = GameContent.load_from_dir()
	doc = FloraBuilder.load_doc()


func _builder() -> FloraBuilder:
	return FloraBuilder.new(doc, c.motion)


func _stem(flower: StringName, stage: int, slot: int = 0) -> FloraBuilder.Stem:
	var f: Dictionary = c.flowers_by_id[flower]
	var st := FloraBuilder.Stem.new()
	st.flower = flower
	st.form = String(f["form"])
	st.row = FloraBuilder.row_of(c, flower)
	st.root = Vector2(float(slot) * 30.0 - 100.0, float(slot % 3) * 12.0)
	st.depth = 0.88
	st.seed = FloraBuilder.stem_seed(&"bed_1", slot, flower)
	st.stage = stage
	st.growth = 0.5
	return st


func _all_flowers() -> Array[StringName]:
	var out: Array[StringName] = []
	for f: Dictionary in c.flowers:
		out.append(StringName(f["id"]))
	return out


func test_atlas_has_every_stamp_the_grammar_uses() -> void:
	var stamps: Dictionary = doc["stamps"]
	var forms: Dictionary = doc["forms"]
	for f: Dictionary in c.flowers:
		assert_true(forms.has(String(f["form"])), "form %s of %s has a grammar" % [f["form"], f["id"]])
	var used: Array[String] = ["stem", "glint", "sparkle", "seed_glow"]
	for form: Dictionary in forms.values():
		used.append(String((form["bud"] as Dictionary)["stamp"]))
		used.append(String(form.get("base", "foliage_tuft")))
		for lf: Dictionary in form.get("leaves", []):
			used.append(String(lf["stamp"]))
		for lf2: Dictionary in form.get("rosette", []):
			used.append(String(lf2["stamp"]))
		var head: Dictionary = form["head"]
		for k: String in ["stamp", "petal", "centre", "bud_stamp"]:
			if head.has(k):
				used.append(String(head[k]))
	var gr: Dictionary = doc["growth"]
	used.append(String(gr["seed_stamp"]))
	used.append(String(gr["cotyledon"]))
	used.append(String(gr["cushion"]))
	var size: Array = doc["size"]
	for id: String in used:
		assert_true(stamps.has(id), "stamp %s exists" % id)
		if not stamps.has(id):
			continue
		var r: Array = (stamps[id] as Dictionary)["region"]
		assert_true(float(r[0]) + float(r[2]) <= float(size[0]) and float(r[1]) + float(r[3]) <= float(size[1]),
				"stamp %s inside the atlas" % id)
		var pv: Array = (stamps[id] as Dictionary)["pivot"]
		assert_between(float(pv[0]), 0.0, 1.0)
		assert_between(float(pv[1]), 0.0, 1.0)


func test_atlas_is_a_lossless_tone_mask() -> void:
	var imp := ConfigFile.new()
	assert_eq(imp.load("res://art/flora/flora_atlas.svg.import"), OK)
	assert_eq(int(imp.get_value("params", "compress/mode")), 0, "lossless (Art Bible §6.1)")
	assert_true(bool(imp.get_value("params", "mipmaps/generate")), "mipmaps on")
	assert_true(bool(imp.get_value("params", "process/fix_alpha_border")), "fix alpha border")


func test_builder_is_deterministic() -> void:
	var stems: Array[FloraBuilder.Stem] = []
	var i := 0
	for f: StringName in _all_flowers():
		stems.append(_stem(f, WorldSim.STAGE_BLOOM, i))
		i += 1
	var a := _builder().build_arrays(stems)
	var b := _builder().build_arrays(stems)
	assert_eq(a[Mesh.ARRAY_VERTEX], b[Mesh.ARRAY_VERTEX], "same stems, same vertices")
	assert_eq(a[Mesh.ARRAY_CUSTOM0], b[Mesh.ARRAY_CUSTOM0])
	assert_eq(a[Mesh.ARRAY_INDEX], b[Mesh.ARRAY_INDEX])


func test_every_form_builds_at_every_stage_with_the_vertex_contract() -> void:
	var bld := _builder()
	for f: StringName in _all_flowers():
		for stage: int in [WorldSim.STAGE_SEED, WorldSim.STAGE_SPROUT, WorldSim.STAGE_BUD, WorldSim.STAGE_BLOOM]:
			var stems: Array[FloraBuilder.Stem] = [_stem(f, stage)]
			var arr := bld.build_arrays(stems)
			var v: PackedVector2Array = arr[Mesh.ARRAY_VERTEX]
			var col: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			var c0: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
			var c1: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM1]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			assert_gt(v.size(), 0, "%s stage %d builds" % [f, stage])
			assert_eq(col.size(), v.size())
			assert_eq(c0.size(), v.size() * 4, "CUSTOM0 is RGBA float")
			assert_eq(c1.size(), v.size() * 4, "CUSTOM1 is RGBA float")
			assert_eq(idx.size() % 3, 0)
			for k in idx:
				assert_true(k >= 0 and k < v.size())
			var kinds := {}
			for cc: Color in col:
				var kind := int(round(cc.g * FloraBuilder.PART_DIV))
				kinds[kind] = true
				assert_true(cc.b >= 0.0 and cc.b <= 1.0)
				assert_true(int(round(cc.r * FloraBuilder.PART_DIV)) <= FloraBuilder.ROW_FX)
			if stage == WorldSim.STAGE_SEED:
				assert_true(kinds.has(FloraBuilder.PART_SOIL), "%s seed is a soil mound" % f)
				assert_false(kinds.has(FloraBuilder.PART_STEM), "a seed has no stem")
			else:
				assert_true(kinds.has(FloraBuilder.PART_STEM), "%s stage %d has a stem" % [f, stage])
			if stage == WorldSim.STAGE_BUD:
				assert_true(kinds.has(FloraBuilder.PART_BUD), "%s bud stage shows the bud" % f)
			if stage == WorldSim.STAGE_BLOOM:
				assert_true(kinds.has(FloraBuilder.PART_PETAL) or kinds.has(FloraBuilder.PART_BELL),
						"%s bloom shows its head" % f)


func test_rigid_parts_attach_inside_the_plant() -> void:
	# Every rigid part's attach point lies within its stem's reach from the root, so the sway
	# (translate + rotate about the attach point) keeps petals on their stem (§4.10 acceptance).
	var bld := _builder()
	for f: StringName in _all_flowers():
		var st := _stem(f, WorldSim.STAGE_BLOOM)
		var stems: Array[FloraBuilder.Stem] = [st]
		var arr := bld.build_arrays(stems)
		var c1: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM1]
		var col: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		for i in col.size():
			var attach := Vector2(c1[i * 4], c1[i * 4 + 1])
			var reach := c1[i * 4 + 2]
			assert_true(attach.distance_to(st.root) <= reach * 1.6 + 40.0,
					"%s vertex %d attaches within its stem's reach" % [f, i])


func test_ready_bud_is_a_bud_and_unfurl_opens_in_order() -> void:
	var bld := _builder()
	var st := _stem(&"button_daisy", WorldSim.STAGE_BLOOM)
	st.ready = true
	var stems: Array[FloraBuilder.Stem] = [st]
	var arr := bld.build_arrays(stems)
	var has_petal := false
	for cc: Color in arr[Mesh.ARRAY_COLOR] as PackedColorArray:
		if int(round(cc.g * FloraBuilder.PART_DIV)) == FloraBuilder.PART_PETAL:
			has_petal = true
	assert_false(has_petal, "a ready bud shows no petals yet")
	st.ready = false
	st.unfurl_s = 0.0
	var o0 := bld._openness(st)
	st.unfurl_s = 0.2
	var o1 := bld._openness(st)
	st.unfurl_s = 0.6
	var o2 := bld._openness(st)
	assert_almost_eq(o0[0], 0.0, 1e-4, "petals start folded")
	assert_gt(o1[0], o1[4], "the 30 ms stagger opens petals in angular order")
	for i in o2.size():
		assert_almost_eq(o2[i], 1.0, 1e-3, "petal %d open by 600 ms" % i)
	st.unfurl_rate = 0.25
	st.unfurl_s = 0.6
	var slow := bld._openness(st)
	assert_lt(slow[4], 1.0, "the auto unfurl is slower (2.4 s)")
	st.unfurl_s = 2.4
	for v: float in bld._openness(st):
		assert_almost_eq(v, 1.0, 1e-3, "the auto unfurl is open by 2.4 s")


func test_full_bed_stays_small() -> void:
	var bed: Dictionary = c.beds_by_id[&"bed_1"]
	var stems: Array[FloraBuilder.Stem] = []
	var flowers := _all_flowers()
	for slot in int(bed["capacity"]):
		var st := _stem(flowers[slot % flowers.size()], WorldSim.STAGE_BLOOM, slot)
		stems.append(st)
	var arr := _builder().build_arrays(stems)
	assert_lt((arr[Mesh.ARRAY_VERTEX] as PackedVector2Array).size(), MAX_BED_VERTICES)
	var mesh := _builder().build_mesh(stems)
	assert_eq(mesh.get_surface_count(), 1, "one surface = one draw call per bed")


func test_lut_carries_every_flower() -> void:
	var img := FloraBuilder.build_lut(c)
	assert_eq(img.get_width(), FloraBuilder.LUT_COLS)
	assert_eq(img.get_height(), FloraBuilder.LUT_ROWS)
	var pal: Dictionary = c.palettes["flora"]["flowers"]
	for i in c.flowers.size():
		var tok: Dictionary = pal[String(c.flowers[i]["petal_token"])]
		var lit := Color.html(String((tok["petal"] as Array)[0]))
		var got := img.get_pixel(0, i)
		assert_almost_eq(got.r, lit.r, 0.003, "row %d petal lit" % i)
		assert_almost_eq(got.a, float(tok["night_emission"]), 0.003, "row %d night emission" % i)
		var leaf := Color.html(String((tok["leaf"] as Array)[0]))
		assert_almost_eq(img.get_pixel(3, i).g, leaf.g, 0.003, "row %d leaf lit" % i)
	var soil := Color.html(String(c.palettes["materials"]["soil"]["lit"]))
	assert_almost_eq(img.get_pixel(0, FloraBuilder.ROW_GROUND).r, soil.r, 0.003)


func test_stem_seed_is_stable() -> void:
	assert_eq(FloraBuilder.stem_seed(&"bed_2", 3, &"bluebell"), FloraBuilder.stem_seed(&"bed_2", 3, &"bluebell"))
	assert_ne(FloraBuilder.stem_seed(&"bed_2", 3, &"bluebell"), FloraBuilder.stem_seed(&"bed_2", 4, &"bluebell"))


func test_depth_scale_matches_the_art_bible() -> void:
	assert_almost_eq(PlotsLayer.depth_scale(760.0), 0.62, 1e-4)
	assert_almost_eq(PlotsLayer.depth_scale(1500.0), 1.0, 1e-4)
	assert_almost_eq(PlotsLayer.depth_scale(1325.0), 0.62 + 0.38 * 565.0 / 740.0, 1e-4)


## Round 5 (plush play-set): the shader puffs every stamp up from its blurred alpha, so no stamp
## may be cut flat by its atlas cell (the clipped blurs drew hard bars under the clumps in round 4).
## Only the tiling stem strip and the butterfly wing (hinged at its cell edge) touch their edges.
func test_stamps_are_not_cut_by_their_atlas_cell() -> void:
	var tex := load(String(doc["atlas"])) as Texture2D
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var exempt: Array[String] = ["stem", "wing"]
	var stamps: Dictionary = doc["stamps"]
	for id: String in stamps:
		if id in exempt:
			continue
		var r: Array = (stamps[id] as Dictionary)["region"]
		var x0 := int(r[0])
		var y0 := int(r[1])
		var w := int(r[2])
		var h := int(r[3])
		var worst := 0.0
		for i in w:
			worst = maxf(worst, maxf(img.get_pixel(x0 + i, y0).a, img.get_pixel(x0 + i, y0 + h - 1).a))
		for j in h:
			worst = maxf(worst, maxf(img.get_pixel(x0, y0 + j).a, img.get_pixel(x0 + w - 1, y0 + j).a))
		assert_true(worst < 0.08, "stamp %s stays inside its cell (edge alpha %.2f)" % [id, worst])
