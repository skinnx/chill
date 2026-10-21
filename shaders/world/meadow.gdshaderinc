// Shared body of the L4 meadow ground (Art Bible §4.5): crest -> brook value gradient lit by the
// key, a soft path, felt dapple, drifting cloud shadows, the darker near bank, rain sheen, warm
// lamp pools, the sun veil, low mist bands, a backlit crest, then grain + dither.
// meadow.gdshader (feather strip, blend_mix) and meadow_core.gdshader (blend_disabled) include it.
// Mesh contract as silhouette.gdshaderinc (VERTEX design px, UV.x depth, UV.y px below crest).
#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/lamps.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

// Palette-derived slots (PaletteFeed, OKLab exact, after the rain transform).
uniform vec4 ground_back_lit : source_color = vec4(0.522, 0.733, 0.553, 1.0);
uniform vec4 ground_front_lit : source_color = vec4(0.447, 0.686, 0.490, 1.0);
uniform vec4 path_color : source_color = vec4(0.627, 0.749, 0.624, 1.0);
uniform vec4 grass_tip : source_color = vec4(0.624, 0.800, 0.616, 1.0);
uniform vec4 grass_root : source_color = vec4(0.286, 0.576, 0.471, 1.0);
// Path knots (design y, centre x, half width px, strength 0..1), sorted by y; count <= 10.
uniform vec4 u_path[10];
uniform int u_path_count = 0;
uniform float path_alpha = 0.42;
// Brook centre line as a linear fit y = a + b * x (spots.json stream polyline) and its half
// width incl. banks: the near bank below it is mixed 10 % toward g_shadow.
uniform vec2 brook_fit = vec2(1531.0, -0.0866);
uniform float brook_half_px = 44.5;
uniform float dapple_k = 0.035;
uniform float fine_k = 0.015;
uniform float fibre_k = 0.012;
uniform float tint_k = 0.10;
uniform float near_bank_k = 0.10;
uniform float wet_sheen_k = 0.15;
uniform float crest_rim_px = 10.0;
uniform float crest_glow_px = 70.0;
uniform vec2 crest_band = vec2(760.0, 880.0);
uniform vec2 brook_band = vec2(1400.0, 1540.0);
uniform float mist_sigma = 40.0;
uniform float hollow_shade_k = 0.12;
uniform float relief_k = 1.6;
uniform float focal_pool_k = 0.35;

const vec2 FOCAL = vec2(540.0, 1123.0);
const float RELIEF_STEP = 40.0;
const float T_TOP = 760.0;
const float T_BOTTOM = 1500.0;
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

// Gentle hummocks: a soft height field whose slopes facing the key light read lighter and the
// others sink toward the tinted shadow, so the meadow has relief instead of a flat gradient [J].
float relief(vec2 p) {
	return vnoise(p / vec2(300.0, 165.0));
}

float mist_band(vec2 p) {
	float a = (p.y - 0.5 * (crest_band.x + crest_band.y)) / mist_sigma;
	float b = (p.y - 0.5 * (brook_band.x + brook_band.y)) / mist_sigma;
	float band = exp(-0.5 * a * a) + exp(-0.5 * b * b);
	float n = vnoise_tiled(vec2((p.x - MIST_DRIFT_PX_S * g_time) / 150.0, p.y / 60.0), vec2(MIST_TILE_PX / 150.0, 4096.0));
	return band * smoothstep(0.25, 0.85, n);
}

vec3 meadow_color(vec2 uv, vec2 frag) {
	vec2 p = v_design;
	float t = smoothstep(T_TOP, T_BOTTOM, p.y);
	vec3 c = mix(ground_back_lit.rgb, ground_front_lit.rgb, t);
	// Relief: one soft height field, lit by the key direction (screen space), softer at night; the
	// same field gives the grass-tone drifts (lighter/warmer tips vs cooler roots) [J].
	float h0 = relief(p);
	float drift = h0 - 0.5;
	c = mix(c, drift > 0.0 ? grass_tip.rgb : grass_root.rgb, abs(drift) * 2.0 * tint_k);
	vec2 kd = key_dir(v_canvas);
	float slope = (relief(p + kd * RELIEF_STEP) - h0) * relief_k * (0.45 + 0.55 * (1.0 - g_lights));
	c = mix(c, c * g_shadow.rgb * SHADE_K, clamp(-slope, 0.0, 0.08));
	c += g_key.rgb * clamp(slope, 0.0, 0.12) * 0.5;
	// The hollow: its sides fall into soft tinted shade, the floor around the sun stone (the focal)
	// gathers a gentle pool of key light by day (Art Bible §1.1 "sunlit hollow", §2.5) [J].
	float side = smoothstep(260.0, 660.0, abs(p.x - FOCAL.x)) * (0.6 + 0.4 * t);
	c = mix(c, c * g_shadow.rgb * SHADE_K, side * hollow_shade_k);
	vec2 fd = (p - FOCAL) / vec2(430.0, 300.0);
	c += g_key.rgb * g_ground_light * focal_pool_k * exp(-dot(fd, fd) * 1.6);
	// Path.
	// The path is quieter at night: value contrast is compressed after dark (Art Bible §3.9) [J].
	c = mix(c, path_color.rgb, path_alpha * path_mask(p) * (1.0 - 0.55 * g_lights));
	// Felt dapple: a broad and a fine octave (the fine one slightly elongated, like fibres).
	float dap = (vnoise(p / 90.0) - 0.5) * 2.0 * dapple_k
			+ (vnoise(p * vec2(1.0 / 14.0, 1.0 / 26.0) + 9.2) - 0.5) * 2.0 * (fine_k + fibre_k);
	c *= 1.0 + dap;
	// Drifting cloud shadows toward the tinted shadow (off at dusk, night and in rain).
	if (g_cloud_shadow > 0.001) {
		c = mix(c, c * g_shadow.rgb * SHADE_K, cloud_shadow(p));
	}
	// Near bank, below the brook: 10 % toward the shadow tint.
	float bank_y = brook_fit.x + brook_fit.y * p.x + brook_half_px;
	c = mix(c, g_shadow.rgb, near_bank_k * smoothstep(bank_y - 10.0, bank_y + 40.0, p.y));
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
