// Light shafts (Art Bible §4.14, §8.1): additive soft trapezoids radiating from the sun through the
// hollow's air, alpha (0.05..0.12) x g_shafts x (1 - 0.8 g_cloud) x (1 - g_rain), faded over the
// first 15 % and last 40 % of their length with soft sides; dappled by leaf gaps at dawn; swaying
// +-2 deg about the sun at k 50..72. All shafts are one mesh (ShaftController).
// Mesh contract: VERTEX design px; UV.x 0..1 across, UV.y 0 (sun end) .. 1 (far end);
// COLOR.r = alpha 0.05..0.12, COLOR.g = dapple 0..1, COLOR.b = sway phase 0..1, COLOR.a = k / 100.
shader_type canvas_item;
render_mode blend_add, unshaded;

#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

uniform float sway_deg = 2.0;
uniform float cloud_k = 0.8;
uniform float streak_k = 0.45;
uniform float streak_cells = 6.0;
// Round 5b (QA: golden air read milky): the shafts are warm key-tinted light, not a white veil.
uniform float key_tint_k = 0.45;
uniform float shaft_gain = 0.8;

varying vec4 v_data;
varying vec2 v_design;

void vertex() {
	v_data = COLOR;
	// the shafts leave the sun disc, which sits on L1: follow it when the map is panned
	vec2 shift = celestial_shift();
	vec2 o = g_sun_pos + shift - g_world_offset;
	VERTEX += shift;
	float k = COLOR.a * 100.0;
	float a = radians(sway_deg) * sin(TAU * k / LOOP_S * g_time + COLOR.b * TAU) * g_motion;
	vec2 d = VERTEX - o;
	VERTEX = o + vec2(cos(a) * d.x - sin(a) * d.y, sin(a) * d.x + cos(a) * d.y);
	v_design = VERTEX;
	COLOR = vec4(1.0);
}

void fragment() {
	float along = UV.y;
	float across = abs(UV.x * 2.0 - 1.0);
	float shape = smoothstep(0.0, 0.15, along) * (1.0 - smoothstep(0.6, 1.0, along)) * (1.0 - smoothstep(0.4, 1.0, across));
	float dapple = mix(1.0, smoothstep(0.35, 0.75, vnoise(vec2(UV.x * 7.0, along * 2.0) + 3.7)), v_data.g);
	// Rays within the ray: soft lengthwise streaks so a shaft reads as lit air, never a flat band.
	float rays = 1.0 - streak_k + streak_k * smoothstep(0.2, 0.8, vnoise(vec2(UV.x * streak_cells + v_data.b * 17.0, along * 0.8)));
	float a = v_data.r * g_shafts * (1.0 - cloud_k * g_cloud) * (1.0 - g_rain) * g_celestial.x;
	vec3 c = mix(g_glow.rgb, g_key.rgb, key_tint_k) * (a * shaft_gain) * shape * dapple * rays;
	COLOR = vec4(max(c + tpdf(FRAGCOORD.xy), vec3(0.0)), 1.0);
}
