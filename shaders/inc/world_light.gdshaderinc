// Faked world lighting from the time-of-day globals (Art Bible §4.2, synthesis D2: no Light2D).
// Includes globals.gdshaderinc (every g_* global) and noise.gdshaderinc.
//
//   light_object(albedo, up, ao)  ambient multiply, tinted AO toward g_shadow, key on top
//   shade_of(c)                   terrain shade: darker, hue leaning toward the shadow token but
//                                 keeping the surface's own hue (green moss stays green; no pixel
//                                 crushed under L* 6 at night)
//   light_body()                  canvas px of the brighter body (sun unless the moon wins)
//   key_dir(p_canvas)             unit vector toward the light; turns toward the body with backlight
//   light_elevation()             clamp((horizon_y - body_y) / 400, 0.05, 1) in design px
//   shadow_length()               clamp(0.35 / elev, 0.35, 2.5): cast-shadow length factor
//   cast_offset_k(kd)             cast-shadow offset per (height / 2) px, same as ShadowMath.cast_offset
//                                 (away from the light, toward the viewer, longer with backlight)
//   cloud_shadow(p_design)        0..~0.12 darkening from drifting fBm cloud shadows (§8.2)
//   wind_k()                      sway amplitude factor (0.5 + g_wind) / 0.85
//   gust(x_design)                travelling gust envelope 0..1 (k 62, 1742 px spacing, §3.4)
//   gust_at(p_design)             the same front, diagonal: lags with depth (round 4)
//   sun_veil(p_canvas, layer_k)   additive warm veil around the sun (far 1.0, mid 0.6, meadow 0.25)
#ifndef MM_WORLD_LIGHT_INC
#define MM_WORLD_LIGHT_INC
#include "res://shaders/inc/globals.gdshaderinc"
#include "res://shaders/inc/noise.gdshaderinc"

const float SHADE_K = 1.85;
const float AO_MAX = 0.22;
const float KEY_TOP = 0.09;
// palettes.json tod.celestial: horizon_y 690, scene_center (540, 1150), sun disc 96 px.
const float HORIZON_Y = 690.0;
const vec2 SCENE_CENTER = vec2(540.0, 1150.0);
const float SUN_RADIUS_PX = 48.0;
const float ELEVATION_SPAN_PX = 400.0;
// Art Bible §8.2 / motion_tokens loops_spatial.cloud_shadow_drift: 15 px/s, 1800 px tile, 300 px blobs.
const float CLOUD_SHADOW_SPEED = 15.0;
// Round 4 (QA r3: readable blob columns): blobs twice as large, with a wide soft edge.
const float CLOUD_SHADOW_SCALE = 600.0;
const vec2 CLOUD_SHADOW_EDGE = vec2(0.48, 0.80);
const float CLOUD_SHADOW_TILE_CELLS = 6.0;
// palettes.json weather.gust / wind_k.
const float GUST_K = 62.0;
const float GUST_SPACING_PX = 1742.0;
const float GUST_AMP = 0.35;
const float WIND_K_BASE = 0.5;
const float WIND_K_NORM = 0.85;
const float LOOP_S = 600.0;

// Terrain shade keeps the surface's own hue (the moss stays green in shadow, round-2 directive 1):
// darken, then lean TERRAIN_SHADE_TINT of the way toward the shadow token's hue at the same luminance.
const float TERRAIN_SHADE_DARK = 0.58;
const float TERRAIN_SHADE_TINT = 0.32;

float wl_luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Round 4 (QA r3: golden shadows read as a lavender wash): with the light behind (golden, dusk)
// the shadow tint loses part of its chroma, a warm-cool grey-mauve instead of violet.
const float SHADOW_TINT_DESAT = 0.45;

vec3 shadow_tint() {
	vec3 s = g_shadow.rgb;
	return mix(s, vec3(dot(s, vec3(0.2126, 0.7152, 0.0722))), SHADOW_TINT_DESAT * g_backlight);
}

vec3 shade_of(vec3 c) {
	vec3 d = c * TERRAIN_SHADE_DARK;
	vec3 tint = shadow_tint() / max(wl_luma(g_shadow.rgb), 1e-3) * wl_luma(d);
	return mix(d, min(tint, vec3(1.0)), TERRAIN_SHADE_TINT);
}

vec3 light_object(vec3 albedo, float up, float ao) {
	vec3 c = albedo * g_ambient.rgb;
	c = mix(c, c * shadow_tint() * SHADE_K, ao * AO_MAX);
	c += g_key.rgb * KEY_TOP * up;
	return c;
}

vec2 light_body() {
	return g_celestial.x >= g_celestial.y ? g_sun_pos : g_moon_pos;
}

vec2 key_dir(vec2 p_canvas) {
	vec2 to_body = light_body() - p_canvas;
	vec2 b = dot(to_body, to_body) > 1.0 ? normalize(to_body) : g_sun_dir;
	vec2 d = mix(g_sun_dir, b, 0.5 * g_backlight);
	return dot(d, d) > 1e-6 ? normalize(d) : vec2(0.0, -1.0);
}

float light_elevation() {
	vec2 body = light_body() - g_world_offset;
	return clamp((HORIZON_Y - body.y) / ELEVATION_SPAN_PX, 0.05, 1.0);
}

float shadow_length() {
	return clamp(0.35 / light_elevation(), 0.35, 2.5);
}

// scripts/world/shadow_math.gd SIDE_K / TOWARD_VIEWER / BACKLIGHT_K (keep in sync).
const float CAST_SIDE_K = 0.8;
const float CAST_TOWARD_VIEWER = 0.10;
const float CAST_BACKLIGHT_K = 0.60;

vec2 cast_offset_k(vec2 kd) {
	return vec2(-kd.x * CAST_SIDE_K, CAST_TOWARD_VIEWER + CAST_BACKLIGHT_K * g_backlight) * shadow_length();
}

float cloud_shadow(vec2 p_design) {
	vec2 q = (p_design + vec2(CLOUD_SHADOW_SPEED * g_time, 0.0)) / CLOUD_SHADOW_SCALE;
	float n = (2.0 * vnoise_tiled(q, vec2(CLOUD_SHADOW_TILE_CELLS, 4096.0))
			+ vnoise_tiled(q * 2.0 + vec2(0.0, 7.3), vec2(CLOUD_SHADOW_TILE_CELLS * 2.0, 8192.0))) / 3.0;
	return smoothstep(CLOUD_SHADOW_EDGE.x, CLOUD_SHADOW_EDGE.y, n) * g_cloud_shadow * (0.4 + 0.6 * g_cloud);
}

float wind_k() {
	return (WIND_K_BASE + g_wind) / WIND_K_NORM;
}

float gust(float x_design) {
	float ph = fract(g_time * GUST_K / LOOP_S - x_design / GUST_SPACING_PX);
	return smoothstep(0.0, 0.25, ph) * (1.0 - smoothstep(0.25, 0.6, ph));
}

// Round 4 (QA r3: layers swayed in lockstep): the gust front is diagonal, so it reaches the far
// hedge, the willow, the beds and the near grass at different moments (about 0.5 s per 100 px of
// depth at 180 px/s); per-layer phase lags come for free from each object's own position.
const float GUST_DEPTH_LAG = 0.9;
const float GUST_DEPTH_Y0 = 1150.0;

float gust_at(vec2 p_design) {
	return gust(p_design.x - (p_design.y - GUST_DEPTH_Y0) * GUST_DEPTH_LAG);
}

vec3 sun_veil(vec2 p_canvas, float layer_k) {
	float r0 = SUN_RADIUS_PX * 3.2 * g_halo.x;
	float d = distance(p_canvas, g_sun_pos) / (1.4 * r0);
	return g_glow.rgb * (g_halo.y * 0.6 * layer_k * g_celestial.x / (1.0 + d * d));
}

#endif
