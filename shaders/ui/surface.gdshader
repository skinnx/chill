// Batched opaque UI surface (round 5, Art Bible §4.19 budget, §9.2 elevation; QA r4 blocker: an
// open sheet cost 30-57 draw calls because every StyleBoxFlat card, chip, plate and pill is its own
// polygon draw). Every card, chip, plate, track, thumb and pill in the sheets and modal cards is a
// ColorRect drawn by ONE shared material (scripts/ui/ui_surface.gd): the per-surface shape lives
// in instance uniforms (per-instance data in the GLES3 canvas batcher, so it never breaks a batch)
// and the fill is the rect's vertex colour, so every surface on screen draws in a single call.
//
// The quad is grown in vertex() by the shadow margin, so the elevation shadow (in ink, never black)
// is painted by the same draw; the rounded edge is a 1 screen-px AA ramp (fwidth); an optional
// 1-3 dp border and a top lip (the primary pill's inner highlight). Scroll content fades out at
// the scroll window's edges (u_window, the sheet's list rect in canvas px) on the u_fade material.
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/inc/finish.gdshaderinc"

uniform vec4 u_ink : source_color = vec4(0.165, 0.157, 0.22, 1.0);   // ui.ink (shadow tint)
uniform vec4 u_lip : source_color = vec4(1.0, 0.992, 0.973, 1.0);   // ui.surface_hi
// ui_alpha.shadow_e1 / e2 / e3
uniform vec3 u_shadow_alpha = vec3(0.06, 0.12, 0.16);
// Scroll window (canvas px: x0, y0, x1, y1) and its fade bands (top px, bottom px); the scroll
// band's material has u_fade = 1 (UiBatch), the chrome's 0.
uniform vec4 u_window = vec4(-1e6, -1e6, 1e6, 1e6);
uniform vec2 u_band = vec2(24.0, 96.0);
uniform float u_fade = 0.0;

// Instance data is TWO slots per surface (the global instance buffer is shared with the world and
// capped at 4096 slots on GLES3): radius px (< 0 pill), elevation level 0..3, border px, lip alpha.
instance uniform vec4 i_shape = vec4(0.0);
instance uniform vec4 i_border : source_color = vec4(0.0);

// Art Bible §9.2 elevation shapes (blur px, y offset px) for e1..e3 (UiTokens.ELEVATION_SHAPE).
const vec2 E1 = vec2(24.0, 6.0);
const vec2 E2 = vec2(48.0, 18.0);
const vec2 E3 = vec2(72.0, 24.0);
const float LIP_PX = 15.0;

varying vec2 v_quad;
varying vec2 v_local;
varying vec2 v_world;
varying vec3 v_elev;

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float window_alpha(vec2 w) {
	float top = smoothstep(u_window.y, u_window.y + u_band.x, w.y);
	float bottom = 1.0 - smoothstep(u_window.w - u_band.y, u_window.w, w.y);
	float inside_x = step(u_window.x, w.x) * step(w.x, u_window.z);
	return top * bottom * inside_x;
}

void vertex() {
	// a ColorRect quad (UV 0..1 across it), grown on every side by the shadow margin; UV stays
	// 0..1 over the grown quad, so the original VERTEX / UV is the surface size in fragment()
	float level = i_shape.y;
	vec2 shape = level > 2.5 ? E3 : (level > 1.5 ? E2 : (level > 0.5 ? E1 : vec2(0.0)));
	float sa = level > 2.5 ? u_shadow_alpha.z : (level > 1.5 ? u_shadow_alpha.y : (level > 0.5 ? u_shadow_alpha.x : 0.0));
	float margin = ceil(shape.x + shape.y);
	v_quad = VERTEX;
	v_elev = vec3(sa, shape.x, shape.y);
	v_local = (UV - 0.5) * 2.0 * margin + VERTEX;
	VERTEX = v_local;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 size = max(v_quad / max(UV, vec2(1e-6)), vec2(1.0));
	vec2 half_size = size * 0.5;
	float r = i_shape.x < 0.0 ? min(half_size.x, half_size.y) : min(i_shape.x, min(half_size.x, half_size.y));
	float d = sd_round_box(v_local - half_size, half_size, r);
	float aa = max(fwidth(d), 1e-3);
	float cov = clamp(0.5 - d / aa, 0.0, 1.0);
	vec4 fill = COLOR;
	vec3 c = fill.rgb;
	float a = fill.a;
	// border (inside the edge)
	float bw = i_shape.z;
	if (bw > 0.0) {
		float band = clamp(0.5 - (-d - bw) / aa, 0.0, 1.0);
		c = mix(c, i_border.rgb, band * i_border.a);
		a = mix(a, 1.0, band * i_border.a);
	}
	// top lip: the primary pill's inner highlight, fading down over LIP_PX
	if (i_shape.w > 0.0) {
		float lip = (1.0 - smoothstep(0.0, LIP_PX, v_local.y)) * step(0.0, -d);
		c = mix(c, u_lip.rgb, lip * i_shape.w);
	}
	// elevation shadow (StyleBoxFlat-like falloff, offset down), in ink
	float sa = 0.0;
	if (v_elev.x > 0.0) {
		float ds = sd_round_box(v_local - half_size - vec2(0.0, v_elev.z), half_size, r);
		float t = clamp(1.0 - ds / max(v_elev.y, 1.0), 0.0, 1.0);
		sa = v_elev.x * t * t * (3.0 - 2.0 * t);
	}
	float fa = a * cov;
	float out_a = fa + sa * (1.0 - fa);
	vec3 rgb = (c * fa + u_ink.rgb * sa * (1.0 - fa)) / max(out_a, 1e-4);
	rgb += tpdf(FRAGCOORD.xy);
	if (u_fade > 0.5) {
		out_a *= window_alpha(v_world);
	}
	COLOR = vec4(rgb, out_a);
}
