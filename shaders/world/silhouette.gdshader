// L2 far hills / L3 mid tree line, feather strip (Art Bible §4.4): blend_mix, vertex alpha falls
// to 0 at the outer row (6 px far, 3 px mid). The opaque interior is silhouette_core.gdshader.
shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://shaders/world/silhouette.gdshaderinc"

void fragment() {
	COLOR = vec4(silhouette_color(UV, FRAGCOORD.xy), COLOR.a);
}
