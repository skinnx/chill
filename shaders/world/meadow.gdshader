// L4 meadow crest feather (Art Bible §4.5): blend_mix, soft 3 px edge against the tree line.
// The opaque interior is meadow_core.gdshader; both share meadow.gdshaderinc.
shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://shaders/world/meadow.gdshaderinc"

void fragment() {
	COLOR = vec4(meadow_color(UV, FRAGCOORD.xy), COLOR.a);
}
