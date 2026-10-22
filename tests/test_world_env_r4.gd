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
