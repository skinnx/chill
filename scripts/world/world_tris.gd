class_name WorldTris
extends RefCounted
## One triangle array for a whole procedural world layer: every blob and quad of every piece is
## appended here and the layer issues ONE [method CanvasItem.draw_polygon], so signs, nests and
## scene props each cost a single draw call however many are up (Art Bible §4.19 batching).
## Round 11: lifted out of SignLayer (where it was SignTris) so the nest and scene layers share it.

## Segments of a round blob. The blobs are 8-48 dp wide, so twelve is already finer than a pixel.
const BLOB_SEGS := 12

var pts := PackedVector2Array()
var cols := PackedColorArray()


func tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	pts.append(a)
	pts.append(b)
	pts.append(c)
	cols.append(col)
	cols.append(col)
	cols.append(col)


## A soft round blob with [param half] radii.
func blob(centre: Vector2, half: Vector2, col: Color, segs: int = BLOB_SEGS) -> void:
	var prev := centre + Vector2(half.x, 0.0)
	for k in range(1, segs + 1):
		var ang := TAU * float(k) / float(segs)
		var p := centre + Vector2(cos(ang) * half.x, sin(ang) * half.y)
		tri(centre, prev, p, col)
		prev = p


## A blob turned by [param rot] radians about its centre (leaves, petals).
func blob_rot(centre: Vector2, half: Vector2, rot: float, col: Color, segs: int = BLOB_SEGS) -> void:
	var prev := centre + Vector2(half.x, 0.0).rotated(rot)
	for k in range(1, segs + 1):
		var ang := TAU * float(k) / float(segs)
		var p := centre + Vector2(cos(ang) * half.x, sin(ang) * half.y).rotated(rot)
		tri(centre, prev, p, col)
		prev = p


func quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	tri(a, b, c, col)
	tri(a, c, d, col)


## A thick line from [param a] to [param b] (twigs, stems).
func stroke(a: Vector2, b: Vector2, width: float, col: Color) -> void:
	var n := (b - a).normalized().orthogonal() * width * 0.5
	quad(a + n, b + n, b - n, a - n, col)


func is_empty() -> bool:
	return pts.is_empty()


func flush(on: CanvasItem) -> void:
	if pts.is_empty():
		return
	on.draw_polygon(pts, cols)
