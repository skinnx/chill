// Live-render well (Art Bible §9.4: the Garden card's mini-render well, the Album portrait well,
// the new-friend and postcard portraits). The things drawn in it are live, lit by the hollow's
// current palette, so the well is a small window into that same light: the sky horizon above a
// soft rise of the meadow, both veiled toward the UI surface so a card stays calm, plus a tinted
// ground-contact pool under the subject. At night the well darkens with the world, so a night-lit
// flower or friend never sits as a muddy shape on a bright card. Rounded box, 1 px AA, dithered.
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/inc/globals.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

uniform vec2 u_size = vec2(252.0, 252.0);
uniform float u_radius = 48.0;
uniform vec4 u_surface : source_color = vec4(1.0, 0.992, 0.973, 1.0);   // ui.surface_hi
uniform float u_veil_sky = 0.42;        // how much of the UI surface veils the sky part
uniform float u_veil_ground = 0.3;      // ... and the meadow part
uniform float u_horizon = 0.6;          // horizon line (fraction of the height)
uniform float u_ground_y = 0.84;        // centre of the contact pool (fraction of the height)
uniform float u_glow = 0.85;            // night lantern pool strength (x g_lights)
uniform float u_glow_y = 0.58;          // its centre (fraction of the height)
uniform float u_night_veil = 0.22;      // extra veil toward the card after dark (x g_lights)
// Round 4 studio well (portraits: CreaturePortrait draws its friend in the fixed studio light,
// creature_rig.json view.studio): the window paints that same studio phase instead of the live
// sky, so the friend never sits on a night-dark backdrop; the time of day shows only as a soft
// tint toward the live sky (u_studio_tint x g_lights).
uniform float u_studio = 0.0;
uniform vec4 u_st_sky_top : source_color = vec4(0.62, 0.78, 0.92, 1.0);
uniform vec4 u_st_sky_mid : source_color = vec4(0.75, 0.86, 0.94, 1.0);
uniform vec4 u_st_sky_horizon : source_color = vec4(0.93, 0.92, 0.86, 1.0);
uniform vec4 u_st_glow : source_color = vec4(1.0, 0.95, 0.80, 1.0);
uniform vec4 u_st_far : source_color = vec4(0.62, 0.74, 0.74, 1.0);
uniform vec4 u_st_ground_back : source_color = vec4(0.55, 0.71, 0.55, 1.0);
uniform vec4 u_st_ground_front : source_color = vec4(0.49, 0.68, 0.51, 1.0);
uniform vec4 u_st_key : source_color = vec4(1.0, 0.945, 0.761, 1.0);
uniform vec4 u_st_shadow : source_color = vec4(0.231, 0.424, 0.549, 1.0);
uniform float u_st_rim = 0.5;
uniform float u_studio_tint = 0.2;

varying vec2 v_local;

void vertex() {
	v_local = VERTEX;
}

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 half_size = u_size * 0.5;
	float r = min(u_radius, min(half_size.x, half_size.y));
	float d = sd_round_box(v_local - half_size, half_size, r);
	float cov = clamp(0.5 - d, 0.0, 1.0);
	vec2 uv = v_local / max(u_size, vec2(1.0));
	float aspect = u_size.x / max(u_size.y, 1.0);
	// Round 3 (QA: "flat vector sky and hill"): a small diorama of the hollow in the current light:
	// sky gradient with the key glow low behind the subject, a soft far hill band in aerial haze,
	// the near meadow rising in front, felt grain at the object amount. Edges are soft (out of
	// focus), never a hard horizon line.
	float far_y = u_horizon - 0.12 + 0.035 * sin(uv.x * aspect * 4.2 + 1.3) + 0.02 * sin(uv.x * aspect * 9.0);
	float near_y = u_horizon + 0.05 * sin(uv.x * 3.1 + 0.6) - 0.03 * uv.x;
	float soft = 0.035;
	float far_m = smoothstep(far_y - soft, far_y + soft, uv.y);
	float near_m = smoothstep(near_y - soft * 0.8, near_y + soft * 0.8, uv.y);
	float st = u_studio;
	mediump vec3 w_sky_top = mix(g_sky_top.rgb, u_st_sky_top.rgb, st);
	mediump vec3 w_sky_mid = mix(g_sky_mid.rgb, u_st_sky_mid.rgb, st);
	mediump vec3 w_sky_hor = mix(g_sky_horizon.rgb, u_st_sky_horizon.rgb, st);
	mediump vec3 w_glow = mix(g_glow.rgb, u_st_glow.rgb, st);
	mediump vec3 w_far = mix(g_far.rgb, u_st_far.rgb, st);
	mediump vec3 w_gb = mix(g_ground_back.rgb, u_st_ground_back.rgb, st);
	mediump vec3 w_gf = mix(g_ground_front.rgb, u_st_ground_front.rgb, st);
	mediump vec3 w_key = mix(g_key.rgb, u_st_key.rgb, st);
	mediump vec3 w_shadow = mix(g_shadow.rgb, u_st_shadow.rgb, st);
	float w_rim = mix(g_rim, u_st_rim, st);
	float w_lights = g_lights * (1.0 - st);
	mediump vec3 sky = mix(w_sky_top, w_sky_mid, smoothstep(-0.2, 0.45, uv.y));
	sky = mix(sky, w_sky_hor, smoothstep(0.25, near_y, uv.y));
	// the key's glow sits low behind the subject (sun or moon light; strongest at golden)
	vec2 gq = (uv - vec2(0.5, u_horizon - 0.06)) * vec2(aspect, 1.0) / vec2(0.62, 0.5);
	sky = mix(sky, w_glow, (1.0 - smoothstep(0.0, 1.0, length(gq))) * 0.55);
	// after dark the window is a little lighter than the night, so a moonlit friend reads as a
	// silhouette against soft light, never dark-on-dark (round-3 night portrait check)
	float veil_k = w_lights * u_night_veil;
	sky = mix(sky, u_surface.rgb, u_veil_sky + veil_k);
	mediump vec3 far = mix(w_far, w_sky_hor, 0.45);
	far = mix(far, u_surface.rgb, u_veil_sky * 0.6);
	mediump vec3 meadow = mix(w_gb, w_gf, smoothstep(near_y, 1.0, uv.y));
	// the crest of the near rise catches the key light
	meadow = mix(meadow, w_key * meadow * 1.35, (1.0 - smoothstep(0.0, 0.08, uv.y - near_y)) * 0.35 * w_rim);
	meadow = mix(meadow, u_surface.rgb, u_veil_ground + veil_k * 0.5);
	mediump vec3 c = mix(sky, far, far_m * (1.0 - near_m));
	c = mix(c, meadow, near_m);
	// contact pool under the subject, tinted by the palette shadow (never grey)
	vec2 q = (uv - vec2(0.5, u_ground_y)) / vec2(0.34, 0.07);
	float pool = (1.0 - smoothstep(0.4, 1.0, length(q))) * 0.22;
	c = mix(c, w_shadow * c, pool);
	// After dark the window keeps a small lantern-warm pool behind the subject (w_lights is the
	// palette's lantern level), so a night-lit friend or flower reads as a silhouette against light
	// instead of dark-on-dark.
	vec2 g = (uv - vec2(0.5, u_glow_y)) * vec2(aspect, 1.0) / vec2(0.75, 0.5);
	float glow = (1.0 - smoothstep(0.0, 1.0, length(g))) * w_lights * u_glow;
	c = mix(c, w_glow, glow);
	// a whisper of vignette toward the corners: the window has depth
	float vig = smoothstep(0.55, 1.1, length((uv - 0.5) * vec2(aspect, 1.0) / max(aspect, 1.0) * 1.6));
	c *= 1.0 - vig * 0.08;
	// studio: the hour shows only as a soft tint toward the live sky
	c = mix(c, c * mix(vec3(1.0), g_sky_mid.rgb * 1.6, 0.5), st * u_studio_tint * g_lights);
	c = finish(c, v_local / PX_PER_DP, FRAGCOORD.xy, GRAIN_OBJECT);
	COLOR = vec4(c, cov * COLOR.a);
}
