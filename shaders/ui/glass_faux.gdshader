// Faux glass (Art Bible §4.17 C7): HUD chips, the dock, toasts. No screen read: a surface fill at
// u_fill (ui_alpha.glass_faux_fill; 1.0 under Reduce Transparency) dressed with the shared rim,
// lens, sheen and inner shadow, dithered, over its own elevation shadow.
//
// Batching (round 3, Art Bible §4.19 budget): the surface size is NOT a uniform. A ColorRect's
// local VERTEX and its UV are both linear across the quad and meet at the origin, so in the
// fragment VERTEX / UV is the drawn quad's size exactly; the elevation margin (a uniform) gives the
// surface size. Every faux surface with the same elevation, radius rule and fill therefore shares
// one material (scripts/ui/glass_panel.gd), and consecutive ones batch into a single draw call:
// the dew chip, time chip, eye and dock pill cost one call together. No instance uniforms (that
// buffer belongs to the world).
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/ui/glass.gdshaderinc"

uniform float u_fill = 0.84;        // ui_alpha.glass_faux_fill / reduce_transparency_fill
uniform float u_fill_night = 0.88;  // ui_alpha.night_chrome.fill (1.0 under Reduce Transparency)

varying vec2 v_quad;

void vertex() {
	v_quad = VERTEX;
	v_local = VERTEX - vec2(u_margin);
}

void fragment() {
	// quad size = VERTEX / UV (exact for a rect; UV > 0 away from the very first texel row)
	vec2 quad = v_quad / max(UV, vec2(1e-6));
	vec2 sz = max(quad - vec2(2.0 * u_margin), vec2(1.0));
	float d = glass_sd(sz);
	float cov = clamp(0.5 - d, 0.0, 1.0);
	vec4 g = glass_dress(mix(u_surface.rgb, u_surface_night.rgb, u_night), mix(u_fill, u_fill_night, u_night), d, sz);
	vec4 o = over_shadow(g.rgb, g.a * cov, glass_shadow(sz));
	vec3 c = finish(o.rgb, v_local / PX_PER_DP, FRAGCOORD.xy, GRAIN_GLASS);
	COLOR = vec4(c, o.a * COLOR.a);
}
