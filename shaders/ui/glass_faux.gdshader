// Faux glass (Art Bible §4.17 C7): HUD chips, the dock, toasts. No screen read: a surface fill at
// ui_alpha.glass_faux_fill (1.0 under Reduce Transparency) dressed with the shared rim, sheen and
// inner shadow, dithered. The e2 shadow is drawn underneath by the owning GlassPanel's StyleBoxFlat.
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/ui/glass.gdshaderinc"

uniform float u_fill = 0.84;        // ui_alpha.glass_faux_fill / reduce_transparency_fill

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float d = glass_sd();
	float cov = clamp(0.5 - d, 0.0, 1.0);
	vec4 g = glass_dress(u_surface.rgb, u_fill, d);
	vec3 c = finish(g.rgb, v_local / PX_PER_DP, FRAGCOORD.xy, GRAIN_GLASS);
	COLOR = vec4(c, g.a * cov * COLOR.a);
}
