// Shared glass look (Art Bible §4.17, §9.2, palettes.json ui_alpha): rounded-box coverage with a
// 1 px AA edge, a 1 dp inner rim (light, alpha rim_top_left at the top-left fading to
// rim_bottom_right at the bottom-right), a soft top sheen, a 2 dp inner bottom shadow in ink, and
// the glass finish (grain 0.010 anchored to the panel + TPDF dither). Used by glass_faux and
// glass_live; everything is in local px of the drawn rect (v_local, from VERTEX).
#ifndef MM_GLASS_INC
#define MM_GLASS_INC
#include "res://shaders/inc/finish.gdshaderinc"

uniform vec4 u_surface : source_color = vec4(0.941, 0.933, 0.914, 1.0);   // ui.surface
uniform vec4 u_rim : source_color = vec4(1.0, 0.992, 0.973, 1.0);        // ui.surface_hi
uniform vec4 u_ink : source_color = vec4(0.165, 0.157, 0.22, 1.0);       // ui.ink
uniform float u_rim_tl = 0.6;                       // ui_alpha.rim_top_left
uniform float u_rim_br = 0.1;                       // ui_alpha.rim_bottom_right
uniform float u_inner_shadow = 0.06;                // ui_alpha.inner_bottom_shadow
// Elevation shadow drawn in the same pass (one draw call per glass surface): the quad is grown by
// u_margin on every side; ink at u_shadow_alpha, falling off over u_shadow_blur px, offset down.
uniform float u_margin = 0.0;
uniform float u_shadow_alpha = 0.0;                 // ui_alpha.shadow_e<n>
// Shadow colour: ink, or for the HUD chrome (round 6) a soft meadow-tinted hud_shadow.
uniform vec4 u_shadow_tint : source_color = vec4(0.165, 0.157, 0.22, 1.0);
uniform float u_shadow_blur = 48.0;
uniform float u_shadow_dy = 18.0;
// Corner radius px; below 0 = a pill / circle (half the short side, resolved per surface).
uniform float u_radius = 60.0;
// Night chrome (round 4, palettes ui_alpha.night_chrome): the HUD chips and the dock blend to a
// dim warm-navy glass after dark (u_night 0..1, crossfaded by the HUD); its rim and sheen lift
// toward u_rim_night instead of the cream surface_hi. Sheets never set it (they stay light).
uniform float u_night = 0.0;
uniform vec4 u_surface_night : source_color = vec4(0.208, 0.227, 0.337, 1.0);   // ui.night_glass
uniform vec4 u_rim_night : source_color = vec4(0.478, 0.502, 0.659, 1.0);       // ui.night_glass_rim

const float RIM_PX = 4.5;          // 1.5 dp rim (round 3: a visible specular edge)
const float RIM_SOFT_PX = 1.5;
const float SHADOW_PX = 6.0;       // 2 dp inner bottom shadow
const float SHEEN = 0.07;          // top-half lift toward surface_hi (glass curvature read)
const float SHEEN_END = 0.55;
// Round 3 (Liquid-Glass-era depth): the glass edge is a thick lens: a soft bright band just inside
// the rim (light gathered by the bevel), and the rim's specular comes back on the far, bottom-right
// edge as a weaker counter-glint (light passing through the slab).
const float LENS_PX = 10.0;
const float LENS_LIFT = 0.14;
const float COUNTER_GLINT = 0.32;

varying vec2 v_local;

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// The corner radius of a surface of size sz (pill when u_radius < 0).
float glass_radius(vec2 sz) {
	float half_min = min(sz.x, sz.y) * 0.5;
	return u_radius < 0.0 ? half_min : min(u_radius, half_min);
}

// Signed distance (px) of the panel edge at v_local; negative inside. sz = the surface size, px.
float glass_sd(vec2 sz) {
	vec2 half_size = sz * 0.5;
	return sd_round_box(v_local - half_size, half_size, glass_radius(sz));
}

// Elevation shadow alpha at v_local (StyleBoxFlat-like falloff, smoothed), in ink.
float glass_shadow(vec2 sz) {
	vec2 half_size = sz * 0.5;
	float d = sd_round_box(v_local - half_size - vec2(0.0, u_shadow_dy), half_size, glass_radius(sz));
	float t = clamp(1.0 - d / max(u_shadow_blur, 1.0), 0.0, 1.0);
	return u_shadow_alpha * t * t * (3.0 - 2.0 * t);
}

// Straight-alpha "over": glass (c, a) over the shadow (u_shadow_tint, sa).
vec4 over_shadow(vec3 c, float a, float sa) {
	float out_a = a + sa * (1.0 - a);
	vec3 rgb = (c * a + u_shadow_tint.rgb * sa * (1.0 - a)) / max(out_a, 1e-4);
	return vec4(rgb, out_a);
}

// Applies sheen, rim and inner shadow over the base colour c (alpha a). Returns premultiplied-free
// rgba (straight alpha) before coverage.
vec4 glass_dress(vec3 c, float a, float d, vec2 sz) {
	vec2 half_size = sz * 0.5;
	vec2 n = (v_local - half_size) / max(half_size, vec2(1.0));
	float inside = -d;
	vec3 rim_c = mix(u_rim.rgb, u_rim_night.rgb, u_night);
	float ty = v_local.y / max(sz.y, 1.0);
	c = mix(c, rim_c, SHEEN * (1.0 - smoothstep(0.0, SHEEN_END, ty)));
	// inner bottom shadow: a 2 dp band along the lower edge
	float sh = (1.0 - smoothstep(0.0, SHADOW_PX, inside)) * smoothstep(0.15, 0.85, n.y) * u_inner_shadow;
	c = mix(c, u_ink.rgb, sh);
	a = a + (1.0 - a) * sh;
	// rim: 1 dp light band just inside the edge, strongest at the top-left
	float t = clamp(0.5 + 0.35 * (n.x + n.y), 0.0, 1.0);
	float lens = (1.0 - smoothstep(0.0, LENS_PX, inside)) * LENS_LIFT * (1.0 - 0.6 * t);
	c = mix(c, rim_c, lens);
	float spec = max(mix(u_rim_tl, u_rim_br, t), COUNTER_GLINT * u_rim_tl * smoothstep(0.78, 1.0, t));
	float rim = (1.0 - smoothstep(RIM_PX - RIM_SOFT_PX, RIM_PX + RIM_SOFT_PX, inside)) * spec;
	c = mix(c, rim_c, rim);
	a = a + (1.0 - a) * rim;
	return vec4(c, a);
}

#endif
