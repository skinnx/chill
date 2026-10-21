// Shared glass look (Art Bible §4.17, §9.2, palettes.json ui_alpha): rounded-box coverage with a
// 1 px AA edge, a 1 dp inner rim (light, alpha rim_top_left at the top-left fading to
// rim_bottom_right at the bottom-right), a soft top sheen, a 2 dp inner bottom shadow in ink, and
// the glass finish (grain 0.010 anchored to the panel + TPDF dither). Used by glass_faux and
// glass_live; everything is in local px of the drawn rect (v_local, from VERTEX).
#ifndef MM_GLASS_INC
#define MM_GLASS_INC
#include "res://shaders/inc/finish.gdshaderinc"

uniform vec2 u_size = vec2(120.0, 120.0);          // rect size, px
uniform float u_radius = 60.0;                      // corner radius, px (clamped to half the short side)
uniform vec4 u_surface : source_color = vec4(0.941, 0.933, 0.914, 1.0);   // ui.surface
uniform vec4 u_rim : source_color = vec4(1.0, 0.992, 0.973, 1.0);        // ui.surface_hi
uniform vec4 u_ink : source_color = vec4(0.165, 0.157, 0.22, 1.0);       // ui.ink
uniform float u_rim_tl = 0.6;                       // ui_alpha.rim_top_left
uniform float u_rim_br = 0.1;                       // ui_alpha.rim_bottom_right
uniform float u_inner_shadow = 0.06;                // ui_alpha.inner_bottom_shadow

const float RIM_PX = 3.0;          // 1 dp rim
const float RIM_SOFT_PX = 1.5;
const float SHADOW_PX = 6.0;       // 2 dp inner bottom shadow
const float SHEEN = 0.07;          // top-half lift toward surface_hi (glass curvature read)
const float SHEEN_END = 0.55;

varying vec2 v_local;

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Signed distance (px) of the panel edge at v_local; negative inside.
float glass_sd() {
	vec2 half_size = u_size * 0.5;
	float r = min(u_radius, min(half_size.x, half_size.y));
	return sd_round_box(v_local - half_size, half_size, r);
}

// Applies sheen, rim and inner shadow over the base colour c (alpha a). Returns premultiplied-free
// rgba (straight alpha) before coverage.
vec4 glass_dress(vec3 c, float a, float d) {
	vec2 half_size = u_size * 0.5;
	vec2 n = (v_local - half_size) / max(half_size, vec2(1.0));
	float inside = -d;
	float ty = v_local.y / max(u_size.y, 1.0);
	c = mix(c, u_rim.rgb, SHEEN * (1.0 - smoothstep(0.0, SHEEN_END, ty)));
	// inner bottom shadow: a 2 dp band along the lower edge
	float sh = (1.0 - smoothstep(0.0, SHADOW_PX, inside)) * smoothstep(0.15, 0.85, n.y) * u_inner_shadow;
	c = mix(c, u_ink.rgb, sh);
	a = a + (1.0 - a) * sh;
	// rim: 1 dp light band just inside the edge, strongest at the top-left
	float t = clamp(0.5 + 0.35 * (n.x + n.y), 0.0, 1.0);
	float rim = (1.0 - smoothstep(RIM_PX - RIM_SOFT_PX, RIM_PX + RIM_SOFT_PX, inside)) * mix(u_rim_tl, u_rim_br, t);
	c = mix(c, u_rim.rgb, rim);
	a = a + (1.0 - a) * rim;
	return vec4(c, a);
}

#endif
