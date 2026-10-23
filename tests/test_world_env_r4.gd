extends GutTest
## Environment round 4 (qa/reports/round3.md env section, directive 1): the value frame reaches the
## mid meadow, the near band and both bottom corners while the focal core stays open, and the
## brook's touch ring is flattened onto the water.

const FOCAL := Vector2(540, 1123)


func _covered(p: Vector2) -> bool:
	for r: Rect2 in ValueFrame.rects():
		if r.has_point(p):
			return true
	return false


func test_value_frame_reaches_corners_and_mid_meadow() -> void:
	assert_false(_covered(FOCAL), "the sun stone stays outside the multiply mesh")
	for p: Vector2 in [Vector2(40, 1900), Vector2(1040, 1900), Vector2(540, 1700), Vector2(120, 1100),
			Vector2(960, 1100)]:
		assert_true(_covered(p), "frame covers %s" % p)


func test_value_frame_is_one_surface() -> void:
	var mesh := ValueFrame.build_mesh()
	assert_eq(mesh.get_surface_count(), 1, "one surface, one draw call")
	var verts: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), ValueFrame.rects().size() * 4)


func test_brook_ring_lies_on_the_water() -> void:
	assert_lt(BrookLayer.RING_SQUASH, 1.0, "the brook touch ring is flattened for perspective")
	assert_gt(BrookLayer.RING_SQUASH, 0.2)


# ------------------------------------------------------------------ polish: draw calls

func test_silhouette_body_is_one_surface_with_core_and_feather() -> void:
	var crest := PackedVector2Array([Vector2(0, 500), Vector2(40, 480), Vector2(80, 510), Vector2(120, 495)])
	var body := SilhouetteMesh.body(crest, 800.0, 6.0)
	assert_eq(body.get_surface_count(), 1, "one mesh surface: one draw call per silhouette")
	var core_v: PackedVector2Array = SilhouetteMesh.core(crest, 800.0).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var edge_v: PackedVector2Array = SilhouetteMesh.feather(crest, 6.0).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var n_core := core_v.size()
	var n_edge := edge_v.size()
	var arrays := body.surface_get_arrays(0)
	assert_eq((arrays[Mesh.ARRAY_VERTEX] as PackedVector2Array).size(), n_core + n_edge)
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in n_core:
		assert_eq(cols[i].a, 1.0, "the interior stays opaque under the feather's blend_mix shader")


func test_grass_uses_at_most_seven_depth_bands() -> void:
	assert_lte(GrassField.band_edges().size() - 1, 7, "grass bands are draw calls (polish budget)")
