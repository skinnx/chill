// L2/L3 silhouette interior (Art Bible §4.0, §4.4): blend_disabled so tile GPUs with hidden-surface
// removal can skip the covered sky. Same shading as the feather strip (silhouette.gdshaderinc).
shader_type canvas_item;
render_mode blend_disabled, unshaded;

#include "res://shaders/world/silhouette.gdshaderinc"

void fragment() {
	COLOR = vec4(silhouette_color(UV, FRAGCOORD.xy), 1.0);
}
