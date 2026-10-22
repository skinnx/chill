class_name SilhouetteMesh
extends RefCounted
## Builds the two meshes of a landscape silhouette (Art Bible §4.0, §4.4): an opaque interior from
## the crest down to the body bottom, and a feather strip whose outer row (offset along the crest
## normal) has vertex alpha 0. Pure: returns ArrayMeshes; SilhouetteLayer / MeadowLayer own nodes.
##
## Vertex contract (shaders/world/silhouette.gdshaderinc, meadow.gdshaderinc):
##   VERTEX = design px · UV.x = depth 0 (crest) .. 1 (bottom) · UV.y = px below the crest (< 0 in
##   the feather) · COLOR.a = feather coverage (1 on the crest, 0 on the outer row).

## Normal offsets are clamped so tight concave corners between bumps do not fold the strip.
const MAX_NORMAL_TILT := 0.85


## Interior: two vertex rows (crest, bottom) and two triangles per column.
static func core(crest: PackedVector2Array, bottom_y: float) -> ArrayMesh:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for p: Vector2 in crest:
		var depth := maxf(bottom_y - p.y, 1.0)
		verts.append(p)
		uvs.append(Vector2(0.0, 0.0))
		cols.append(Color.WHITE)
		verts.append(Vector2(p.x, bottom_y))
		uvs.append(Vector2(1.0, depth))
		cols.append(Color.WHITE)
	for i in crest.size() - 1:
		var a := i * 2
		idx.append_array(PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3]))
	return _mesh(verts, uvs, cols, idx)


## Feather strip of `width` px above the crest, offset along the smoothed crest normal.
static func feather(crest: PackedVector2Array, width: float) -> ArrayMesh:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var n := crest.size()
	for i in n:
		var a := crest[maxi(i - 1, 0)]
		var b := crest[mini(i + 1, n - 1)]
		var tangent := (b - a).normalized()
		var normal := Vector2(tangent.y, -tangent.x)  # points up (toward smaller y) for a left->right crest
		if normal.y > 0.0:
			normal = -normal
		normal.x = clampf(normal.x, -MAX_NORMAL_TILT, MAX_NORMAL_TILT)
		normal = normal.normalized()
		verts.append(crest[i])
		uvs.append(Vector2(0.0, 0.0))
		cols.append(Color(1, 1, 1, 1))
		verts.append(crest[i] + normal * width)
		uvs.append(Vector2(0.0, -width))
		cols.append(Color(1, 1, 1, 0))
	for i in n - 1:
		var a := i * 2
		idx.append_array(PackedInt32Array([a, a + 1, a + 2, a + 2, a + 1, a + 3]))
	return _mesh(verts, uvs, cols, idx)


static func _mesh(verts: PackedVector2Array, uvs: PackedVector2Array, cols: PackedColorArray,
		idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
