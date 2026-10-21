// Shared body of the L4 meadow ground (Art Bible §4.5, round-2 directives 1 and 3): a soft FELTED
// MOSS meadow in every phase. The palette keeps a green hue identity that the light only tints.
//   1. depth gradient crest -> brook (ground_back_lit -> ground_front_lit), richer near ground;
//   2. the hollow's relief (art/fx/meadow_relief.png: a bowl, broad moss mounds, banks sloping into
//      the brook) lit by the key: sun-facing slopes catch warm light, the others sink into the
//      tinted shadow, longer and cooler when the light is low (golden, dawn);
//   3. moss cushions (art/fx/moss_tile.png, perspective-mapped onto the ground plane) lit by the
//      same key, crevices toward the shadow tint, plus fine felt fibres;
//   4. a key pool on the focal floor around the sun stone, a darker frame toward the near ground
//      and the bottom corners, a worn moss path, drifting cloud shadows, rain sheen, the backlit
//      crest, the sun veil, low mist, discrete lamp pools; grain + dither.
// meadow.gdshader (crest feather, blend_mix) and meadow_core.gdshader (blend_disabled) include it.
// Mesh contract as silhouette.gdshaderinc (VERTEX design px, UV.x depth, UV.y px below crest).
#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/lamps.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

// Palette-derived slots (PaletteFeed, OKLab exact, after the rain transform).
uniform vec4 ground_back_lit : source_color = vec4(0.502, 0.718, 0.537, 1.0);
uniform vec4 ground_front_lit : source_color = vec4(0.447, 0.686, 0.490, 1.0);
uniform vec4 path_color : source_color = vec4(0.616, 0.741, 0.612, 1.0);
uniform vec4 grass_tip : source_color = vec4(0.537, 0.729, 0.537, 1.0);
uniform vec4 grass_root : source_color = vec4(0.286, 0.576, 0.471, 1.0);
uniform sampler2D moss_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D relief_tex : filter_linear, repeat_disable;
// Path knots (design y, centre x, half width px, strength 0..1), sorted by y; count <= 10.
uniform vec4 u_path[10];
uniform int u_path_count = 0;
uniform float path_alpha = 0.40;
// Brook centre line as a linear fit y = a + b * x (spots.json stream polyline) and its half
// width incl. banks.
uniform vec2 brook_fit = vec2(1531.0, -0.0866);
uniform float brook_half_px = 44.5;
// Moss cushions: tile size at depth 1, ground-plane squash, light / crevice / fibre contrast.
uniform float moss_px = 95.0;
uniform float moss_squash = 0.6;
uniform float moss_lit_k = 0.22;
uniform float moss_shade_k = 0.20;
uniform float moss_crevice_k = 0.10;
uniform float fibre_k = 0.07;
// Relief: slope light, slope shade, bowl occlusion.
uniform float relief_lit_k = 0.22;
uniform float relief_shade_k = 0.38;
uniform float occlusion_k = 0.30;
uniform float height_tint_k = 0.16;
uniform float dapple_k = 0.03;
uniform float wet_sheen_k = 0.15;
uniform float crest_rim_px = 10.0;
uniform float crest_glow_px = 70.0;
uniform vec2 crest_band = vec2(760.0, 880.0);
uniform vec2 brook_band = vec2(1400.0, 1540.0);
uniform float mist_sigma = 40.0;
uniform float focal_pool_k = 0.55;
// Depth frame: near ground below the brook and the bottom corners sink toward the shadow tint.
uniform float near_frame_k = 0.22;
uniform float corner_k = 0.30;
uniform float far_haze_k = 0.10;

const vec2 FOCAL = vec2(540.0, 1123.0);
const float T_TOP = 760.0;
const float T_BOTTOM = 1500.0;
// Ground-plane depth scale s(y) = 0.62 + K (y - 760) (Art Bible §2.4), not clamped at 1 here:
// the near ground keeps growing toward the viewer.
const float DEPTH_S0 = 0.62;
const float DEPTH_Y0 = 760.0;
const float DEPTH_K = 0.38 / 740.0;
const float VANISH_X = 540.0;
// art/fx/meadow_relief.png covers design x -400..1488, y 700..1980 (meadow_relief.py).
const vec4 RELIEF_RECT = vec4(-400.0, 700.0, 1888.0, 1280.0);
const float MIST_DRIFT_PX_S = 6.0;
const float MIST_TILE_PX = 1800.0;

varying vec2 v_design;
varying vec2 v_canvas;

void vertex() {
	v_design = VERTEX;
	v_canvas = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float path_mask(vec2 p) {
	if (u_path_count < 2 || p.y < u_path[0].x || p.y > u_path[u_path_count - 1].x) {
		return 0.0;
	}
	vec4 a = u_path[0];
	vec4 b = u_path[1];
	for (int i = 1; i < 10; i++) {
		if (i >= u_path_count) {
			break;
		}
		b = u_path[i];
		if (p.y <= b.x) {
			break;
		}
		a = b;
	}
	float t = clamp((p.y - a.x) / max(b.x - a.x, 1.0), 0.0, 1.0);
	t = t * t * (3.0 - 2.0 * t);
	vec4 k = mix(a, b, t);
	if (abs(p.x - k.y) > k.z * 1.7 || k.w <= 0.0) {
		return 0.0;
	}
	float edge = (vnoise(p / 26.0) - 0.5) * 0.45 + (vnoise(p / 7.0) - 0.5) * 0.18;
	float dx = abs(p.x - k.y) / max(k.z, 1.0) + edge;
	return (1.0 - smoothstep(0.45, 1.0, dx)) * k.w;
}

float mist_band(vec2 p) {
	float a = (p.y - 0.5 * (crest_band.x + crest_band.y)) / mist_sigma;
	float b = (p.y - 0.5 * (brook_band.x + brook_band.y)) / mist_sigma;
	float band = exp(-0.5 * a * a) + exp(-0.5 * b * b);
	float n = vnoise_tiled(vec2((p.x - MIST_DRIFT_PX_S * g_time) / 150.0, p.y / 60.0), vec2(MIST_TILE_PX / 150.0, 4096.0));
	return band * smoothstep(0.25, 0.85, n);
}

// Ground-plane depth scale at design y.
float ground_scale(float y) {
	return max(DEPTH_S0 + DEPTH_K * (y - DEPTH_Y0), 0.3);
}

// Perspective moss UV: x converges toward the vanishing column, y is the integral of
// 1 / (squash * s(y)), so cushions shrink smoothly toward the crest with no distortion.
vec2 moss_uv(vec2 p) {
	float s = ground_scale(p.y);
	float v = log(s) / (DEPTH_K * moss_squash);
	return vec2((p.x - VANISH_X) / s, v) / moss_px;
}

vec3 meadow_color(vec2 uv, vec2 frag) {
	vec2 p = v_design;
	float t = smoothstep(T_TOP, T_BOTTOM, p.y);
	vec3 c = mix(ground_back_lit.rgb, ground_front_lit.rgb, t);
	vec2 kd = key_dir(v_canvas);
	float elev = light_elevation();
	float low = 1.0 - smoothstep(0.25, 0.85, elev);  // 1 when the light is low (long shading)
	float night = g_lights;
	vec3 shade_c = c * g_shadow.rgb * SHADE_K;

	// 2. Relief: the hollow's bowl and moss mounds, lit by the key.
	vec4 rel = texture(relief_tex, (p - RELIEF_RECT.xy) / RELIEF_RECT.zw);
	vec2 rn = rel.gb * 2.0 - 1.0;
	float rl = dot(rn, kd);
	float relief_light = (0.55 + 0.45 * low) * (1.0 - 0.5 * night);
	c = mix(c, shade_c, clamp(-rl, 0.0, 1.0) * relief_shade_k * relief_light);
	c += g_key.rgb * clamp(rl, 0.0, 1.0) * relief_lit_k * relief_light * (0.35 + g_ground_light * 2.5);
	// Higher ground leans toward the lit grass tone, hollows toward the cool root tone.
	float hh = rel.r - 0.5;
	c = mix(c, hh > 0.0 ? grass_tip.rgb : grass_root.rgb, abs(hh) * 2.0 * height_tint_k);
	c = mix(c, c * g_shadow.rgb * SHADE_K, (1.0 - rel.a) * occlusion_k);

	// 4a. The focal floor around the sun stone gathers a pool of key light; the open floor of the
	// hollow is lighter than its walls, leading the eye to the stone.
	vec2 fd = (p - FOCAL) / vec2(420.0, 260.0);
	c += g_key.rgb * (g_ground_light + 0.04) * focal_pool_k * exp(-dot(fd, fd) * 1.4) * (1.0 - 0.6 * night);

	// 4b. Worn moss path (quieter at night).
	float path = path_mask(p) * (1.0 - 0.55 * night);
	c = mix(c, path_color.rgb, path_alpha * path);

	// 3. Moss cushions + felt fibres, perspective-mapped; lit by the same key.
	vec4 m = texture(moss_tex, moss_uv(p));
	vec2 mn = m.gb * 2.0 - 1.0;
	float ml = dot(mn, kd);
	float moss_amt = (1.0 - 0.6 * path) * (1.0 - 0.45 * night) * mix(0.75, 1.15, t);
	// Lumps read through directional light only (soft lit side, soft shaded side) and a faint,
	// wide occlusion in the deepest gaps; never dark crevice lines (they read as cracked earth).
	float gap = 1.0 - smoothstep(0.0, 0.42, m.r);
	c = mix(c, c * g_shadow.rgb * SHADE_K, (gap * moss_crevice_k + clamp(-ml, 0.0, 1.0) * moss_shade_k) * moss_amt);
	c += (g_key.rgb * 0.6 + c * 0.4) * clamp(ml, 0.0, 1.0) * moss_lit_k * moss_amt * (0.6 + 0.4 * low);
	c *= 1.0 + (m.a - 0.5) * 2.0 * fibre_k * moss_amt;
	// Broad dapple so wide areas never read as one flat value.
	c *= 1.0 + (vnoise(p / vec2(140.0, 80.0)) - 0.5) * 2.0 * dapple_k;

	// Drifting cloud shadows toward the tinted shadow (off at dusk, night and in rain).
	if (g_cloud_shadow > 0.001) {
		c = mix(c, c * g_shadow.rgb * SHADE_K, cloud_shadow(p) * 1.6);
	}
	// 4c. Depth frame: the near ground below the brook and the bottom corners sink toward the
	// shadow tint (richer, darker foreground; the far meadow keeps a touch of aerial haze).
	float bank_y = brook_fit.x + brook_fit.y * p.x + brook_half_px;
	float near = smoothstep(bank_y, 1960.0, p.y);
	vec2 cq = vec2(abs(p.x - 540.0) / 620.0, (p.y - 1150.0) / 820.0);
	float corner = smoothstep(0.55, 1.35, length(cq)) * step(1150.0, p.y);
	c = mix(c, c * g_shadow.rgb * SHADE_K, clamp(near * near_frame_k + corner * corner_k, 0.0, 0.6));
	c = mix(c, g_sky_horizon.rgb, far_haze_k * (1.0 - smoothstep(T_TOP, 980.0, p.y)) * (1.0 - night));
	// Wet sheen in rain (sky reflection), stronger toward the crest.
	c += g_rain * wet_sheen_k * (g_sky_mid.rgb - c) * (1.0 - t * 0.5);
	// Backlit crest: thin rim + broad glow, both from the key.
	float below = max(uv.y, 0.0);
	float rim = 1.0 - smoothstep(0.0, crest_rim_px, below);
	float glow = 1.0 - smoothstep(0.0, crest_glow_px, below);
	c += g_key.rgb * g_backlight * (g_rim * 0.12 * rim * rim + 0.07 * glow);
	// Warm veil from the sun.
	c += sun_veil(v_canvas, 0.25);
	// Low valley mist (dawn), drawn again by the water shader.
	if (g_mist > 0.001) {
		c = mix(c, mix(g_sky_horizon.rgb, g_glow.rgb, 0.2), clamp(g_mist * mist_band(p), 0.0, 0.6));
	}
	// Lamp pools last: they light whatever is there (skipped by day: g_lights = 0).
	if (g_lights > 0.001) {
		c = apply_lamp(c, lamp_weight(p));
	}
	return finish(c, p / PX_PER_DP, frag, GRAIN_TERRAIN);
}
