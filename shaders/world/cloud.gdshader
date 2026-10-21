// L2 clouds (Art Bible §4.8): a soft cumulus per quad = smooth union of 5 circles (flat-bottomed)
// with an fBm billow, lit from the light side per puff (dawn/golden clouds glow on their
// sun-facing undersides), 8 px soft edge, alpha 0.85 x (0.6 + 0.4 g_cloud). Rain clouds
// (i_cloud.w = 1) only appear with g_rain. One shared material; per-quad instance uniforms.
// Quad contract (CloudLayer): local VERTEX in px, quad = (-0.5..0.5) x (-0.5..0.5) of i_size.
shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"
#include "res://shaders/inc/sdf.gdshaderinc"

uniform vec4 cloud_lit : source_color = vec4(0.937, 0.949, 0.890, 1.0);
uniform vec4 cloud_shade : source_color = vec4(0.545, 0.749, 0.875, 1.0);
uniform float edge_px = 8.0;
uniform float base_alpha = 0.85;
uniform float billow = 0.08;
uniform float rain_edge_px = 56.0;
uniform float rain_alpha_max = 0.55;
// Night: clouds sit at least this much above the local sky value (about +6 L* on the navy sky).
uniform float night_lift = 0.05;
// sky.gdshader overcast colour: mean lit mix and its night dimming.
const float OVERCAST_MIX = 0.57;
const float OVERCAST_NIGHT_DIM = 0.45;

// x seed, y alpha multiplier, z flatten (0..1), w 1 = rain-only cloud.
instance uniform vec4 i_cloud = vec4(0.0, 1.0, 0.5, 0.0);
// Quad size in px.
instance uniform vec2 i_size = vec2(600.0, 220.0);

// Puff layout in quad units (x, y, radius): a low left puff, a tall middle pair, a tail [J].
const vec3 PUFFS[5] = vec3[](vec3(-1.45, 0.22, 0.42), vec3(-0.58, -0.04, 0.60), vec3(0.40, -0.18, 0.70),
		vec3(1.30, 0.10, 0.50), vec3(1.98, 0.30, 0.30));
const float BASE_Y = 0.55;

varying vec2 v_local;
varying vec2 v_canvas;

void vertex() {
	v_local = VERTEX;
	v_canvas = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float rain_only = i_cloud.w;
	float vis = mix(1.0, g_rain, rain_only) * i_cloud.y * base_alpha * (0.6 + 0.4 * g_cloud);
	if (vis < 0.002) {
		discard;
	}
	vec2 q = v_local / (i_size.y * 0.5);  // x ~ -2.7..2.7, y -1 (top) .. 1 (bottom)
	float seed = i_cloud.x;
	float d = 1e3;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		vec2 h = h22(vec2(seed * 7.13 + fi * 1.37, fi * 3.1 + seed)) - 0.5;
		vec3 pf = PUFFS[i];
		vec2 c = pf.xy + h * vec2(0.24, 0.12);
		float r = pf.z * (0.92 + 0.16 * h.y);
		d = smin(d, length(q - c) - r, 0.3);
	}
	// Flat bottom (cumulus base), softened by the per-cloud flatten amount.
	d = -smin(-d, -(q.y - BASE_Y) * (0.6 + i_cloud.z), 0.12);
	d += (fbm2(q * 3.0 + seed * 3.0) - 0.5) * 2.0 * billow;
	float px = d * i_size.y * 0.5;
	// Rain clouds are soft felt-grey masses that dissolve into the overcast (QA round 1: never
	// hard-edged "boulders").
	float edge = mix(edge_px, rain_edge_px, rain_only);
	float a = 1.0 - smoothstep(-edge, edge * 0.25, px);
	vis = min(vis, mix(1.0, rain_alpha_max, rain_only));
	if (a <= 0.0) {
		discard;
	}
	// Outward normal from the distance field; Lambert toward the light + a top-lit bias.
	vec2 g = vec2(dFdx(d), dFdy(d));
	vec2 n = dot(g, g) > 1e-12 ? normalize(g) : vec2(0.0, -1.0);
	vec2 l = key_dir(v_canvas);
	// Puff normals give the bumps; the cloud as a whole is lit from the light side too, so the lobes
	// read as one volume rather than separate scales.
	vec2 whole = normalize(q * vec2(0.45, 1.0) + vec2(0.0, -0.2) + vec2(0.0, 1e-4));
	float lam = smoothstep(-0.5, 0.9, mix(dot(whole, l), dot(n, l), 0.45));
	float top = smoothstep(BASE_Y, -0.9, q.y);
	float depth = smoothstep(0.0, -0.45, d);
	float lit = clamp(lam * 0.55 + top * 0.45 - (1.0 - depth) * 0.08, 0.0, 1.0);
	vec3 col = mix(cloud_shade.rgb, cloud_lit.rgb, lit);
	col += sun_veil(v_canvas, 0.8);
	// In rain every cloud melts into the overcast's felt-grey (same mix as sky.gdshader), a touch
	// lighter so the masses still read in front of it.
	vec3 overcast = mix(cloud_shade.rgb, cloud_lit.rgb, OVERCAST_MIX * (1.0 - OVERCAST_NIGHT_DIM * g_stars)) + 0.03;
	col = mix(col, overcast, g_rain * mix(0.6, 0.85, rain_only));
	// A cloud is never darker than the sky behind it (night clouds are moonlit wool, not holes).
	vec2 p_design = v_canvas - g_world_offset;
	vec3 sky_local = mix(g_sky_mid.rgb, g_sky_top.rgb, clamp((560.0 - p_design.y) / 700.0, 0.0, 1.0));
	col = max(col, sky_local + vec3(night_lift) * g_stars);
	COLOR = vec4(finish(col, v_local / PX_PER_DP, FRAGCOORD.xy, GRAIN_SKY), a * vis);
}
