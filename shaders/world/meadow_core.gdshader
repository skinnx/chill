// L4 meadow interior (Art Bible §4.0, §4.5): opaque (blend_disabled), the largest fragment cost
// after the sky. Shading is meadow.gdshaderinc.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

#include "res://shaders/world/meadow.gdshaderinc"

void fragment() {
	COLOR = vec4(meadow_color(UV, FRAGCOORD.xy), 1.0);
}
