// Willow frond strips (Art Bible §6.4): every hanging frond of the willow in ONE mesh, each strip a
// chain of alternating soft lanceolate leaves on a thin stem, drawn analytically (crisp at any
// zoom). Sway is a travelling wave (phase +1.2 rad root -> tip, 10-18 px at the tip) with gusts.
// Mesh contract (PropsLayer.build_fronds): VERTEX design px; UV.x 0..1 across the strip;
// UV.y 0 root .. 1 tip (strip 24 px: the 16 px frond plus leaf overhang); COLOR.r = phase 0..1, COLOR.g = tip amplitude / 18 px, COLOR.b = length / 260,
// COLOR.a = row value (back row darker).
shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/lamps.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"
#include "res://shaders/inc/sdf.gdshaderinc"

uniform vec4 leaf_lit : source_color = vec4(0.651, 0.8, 0.584, 1.0);
uniform vec4 leaf_shade : source_color = vec4(0.439, 0.659, 0.545, 1.0);
uniform vec4 leaf_detail : source_color = vec4(0.824, 0.902, 0.761, 1.0);
uniform float strip_px = 24.0;
uniform float max_len_px = 260.0;
uniform float max_amp_px = 18.0;
uniform float leaf_spacing_px = 9.0;
uniform float sway_k = 76.0;
uniform float wave_rad = 1.2;

varying vec4 v_data;
varying vec2 v_canvas;

void vertex() {
	v_data = COLOR;
	float h = UV.y;
	float amp = COLOR.g * max_amp_px;
	vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - g_world_offset;
	float ph = TAU * COLOR.r;
	float w = sin(TAU * sway_k / LOOP_S * g_time + ph - wave_rad * h)
			+ 0.3 * sin(TAU * sway_k * 1.7 / LOOP_S * g_time + ph * 1.3 - wave_rad * 1.6 * h);
	VERTEX.x += w * amp * wind_k() * (1.0 + GUST_AMP * 1.6 * gust(world.x)) * g_motion * pow(h, 1.5);
	v_canvas = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	COLOR = vec4(1.0);
}

// Coverage (0..1) and a per-leaf light term for the leaf rooted at index i.
vec2 leaf(vec2 q, float i, float len_px, vec2 kd) {
	float side = mod(i, 2.0) < 0.5 ? -1.0 : 1.0;
	float t = clamp(i * leaf_spacing_px / max(len_px, 1.0), 0.0, 1.0);
	float size = mix(1.0, 0.62, t);
	vec2 o = vec2(0.0, i * leaf_spacing_px);
	float ang = side * mix(0.62, 0.42, t);  // hangs down and out
	vec2 lq = rot2(-ang) * (q - o);
	float L = 8.5 * size;
	float d = sd_vesica(lq - vec2(0.0, L), L, 2.7 * size);
	float cov = 1.0 - smoothstep(-0.6, 0.6, d / max(fwidth(d), 1e-3) * 0.5);
	vec2 axis = vec2(sin(ang), cos(ang));
	float light = 0.5 + 0.5 * dot(normalize(vec2(axis.y * side, -axis.x * side) + vec2(0.0, -0.6)), kd);
	return vec2(cov, light);
}

void fragment() {
	float len_px = v_data.b * max_len_px;
	vec2 q = vec2((UV.x - 0.5) * strip_px, UV.y * len_px);
	vec2 kd = key_dir(v_canvas);
	float i0 = floor(q.y / leaf_spacing_px);
	float a = 0.0;
	float light = 0.0;
	for (int k = -2; k <= 0; k++) {
		float i = i0 + float(k);
		if (i < 0.0 || i * leaf_spacing_px > len_px - 6.0) {
			continue;
		}
		vec2 lf = leaf(q, i, len_px, kd);
		if (lf.x > 0.001) {
			light = mix(light, lf.y, lf.x);
			a = max(a, lf.x);
		}
	}
	float stem = (1.0 - smoothstep(0.5, 1.2, abs(q.x))) * (1.0 - smoothstep(len_px - 10.0, len_px - 4.0, q.y));
	a = max(a, stem * 0.9);
	if (a < 0.003) {
		discard;
	}
	float h = UV.y;
	vec3 alb = mix(leaf_shade.rgb, leaf_lit.rgb, clamp(light * 0.85 + 0.1 - h * 0.15, 0.0, 1.0));
	alb = mix(alb, leaf_detail.rgb, 0.25 * smoothstep(0.75, 1.0, light));
	alb *= v_data.a;
	vec3 c = light_object(alb, 1.0 - h, 0.0);
	vec2 p_design = v_canvas - g_world_offset;
	if (g_cloud_shadow > 0.001) {
		c = mix(c, c * g_shadow.rgb * SHADE_K, cloud_shadow(p_design));
	}
	if (g_lights > 0.001) {
		c += alb * g_accent.rgb * lamp_soft(lamp_weight(p_design)) * 1.1;
	}
	c += g_key.rgb * g_rim * g_backlight * 0.18 * smoothstep(0.6, 1.0, light);
	COLOR = vec4(finish(c, q / PX_PER_DP, FRAGCOORD.xy, GRAIN_OBJECT), a);
}
