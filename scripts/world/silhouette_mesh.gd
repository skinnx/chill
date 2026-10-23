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


## Interior + feather strip as ONE mesh (polish, draw calls: one call per silhouette instead of
## two). Drawn with the blend_mix feather shader; the interior's vertex alpha is 1, so it looks the
## same as the opaque core (only the tile-GPU hidden-surface skip of blend_disabled is given up).
static func body(crest: PackedVector2Array, bottom_y: float, width: float) -> ArrayMesh:
	var a := core(crest, bottom_y).surface_get_arrays(0)
	var b := feather(crest, width).surface_get_arrays(0)
	var verts: PackedVector2Array = a[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var cols: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var base := verts.size()
	verts.append_array(b[Mesh.ARRAY_VERTEX] as PackedVector2Array)
	uvs.append_array(b[Mesh.ARRAY_TEX_UV] as PackedVector2Array)
	cols.append_array(b[Mesh.ARRAY_COLOR] as PackedColorArray)
	for i: int in b[Mesh.ARRAY_INDEX] as PackedInt32Array:
		idx.append(base + i)
	return _mesh(verts, uvs, cols, idx)


## Skirt below a flat body bottom (map pan, ARCHITECTURE §3.4): a rect from [param top_y] to
## [param bottom_y] over [x0, x1] shaded as the body bottom (UV.x 1, far below the crest).
static func skirt(x0: float, x1: float, top_y: float, bottom_y: float) -> ArrayMesh:
	var verts := PackedVector2Array([Vector2(x0, top_y), Vector2(x1, top_y), Vector2(x0, bottom_y), Vector2(x1, bottom_y)])
	var deep := Vector2(1.0, bottom_y - top_y + 1000.0)
	var uvs := PackedVector2Array([deep, deep, deep, deep])
	var cols := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	return _mesh(verts, uvs, cols, PackedInt32Array([0, 1, 2, 2, 1, 3]))


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
