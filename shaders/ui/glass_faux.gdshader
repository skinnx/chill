// Faux glass (Art Bible §4.17 C7): HUD chips, the dock, toasts. No screen read: a surface fill at
// ui_alpha.glass_faux_fill (1.0 under Reduce Transparency) dressed with the shared rim, sheen and
// inner shadow, dithered, over its own e2 elevation shadow (one draw call per surface).
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/ui/glass.gdshaderinc"

uniform float u_fill = 0.84;        // ui_alpha.glass_faux_fill / reduce_transparency_fill

void vertex() {
	v_local = VERTEX - vec2(u_margin);
}

void fragment() {
	float d = glass_sd();
	float cov = clamp(0.5 - d, 0.0, 1.0);
	vec4 g = glass_dress(u_surface.rgb, u_fill, d);
	vec4 o = over_shadow(g.rgb, g.a * cov, glass_shadow());
	vec3 c = finish(o.rgb, v_local / PX_PER_DP, FRAGCOORD.xy, GRAIN_GLASS);
	COLOR = vec4(c, o.a * COLOR.a);
}
