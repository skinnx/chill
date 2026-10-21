class_name SdfQuad
extends Node2D
## One quad for an SDF shader (Art Bible §5.2): draws [member rect] once; everything else happens
## in the material, driven by instance uniforms, so the quad never needs a redraw while animating.
## Shader code reads VERTEX (local px), so the quad needs no texture and no UVs.

var rect: Rect2 = Rect2(-8, -8, 16, 16):
	set(value):
		if value != rect:
			rect = value
			queue_redraw()


func _draw() -> void:
	draw_rect(rect, Color.WHITE)
