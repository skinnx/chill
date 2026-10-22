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
// Round 5 product sweep (studio owner: the friends are premium plush toys, the Album is a toy-shop
// product shot): a seamless paper cyclorama instead of the meadow diorama. A warm cream wall tinted
// toward the friend's accent colour bends into the floor with no horizon line, a soft key pool
// sits up-left behind the toy (creature_rig.json view.studio.key_dir: light from the upper left),
// and the toy sits on a little stitched felt moss cushion whose soft shadow falls down-right, the
// same way every shadow in the hollow falls.
uniform float u_product = 0.0;
uniform vec4 u_pr_tint : source_color = vec4(0.93, 0.62, 0.65, 1.0);
uniform vec4 u_pr_paper : source_color = vec4(0.976, 0.953, 0.918, 1.0);
uniform vec4 u_pr_felt : source_color = vec4(0.655, 0.796, 0.576, 1.0);
uniform float u_pr_tint_k = 0.22;       // how much of the accent the wall takes
uniform float u_pr_sweep = 0.64;        // where the wall bends into the floor (fraction of height)
uniform vec2 u_pr_key = vec2(-0.55, 0.83);
uniform vec2 u_pr_pad = vec2(0.33, 0.075); // felt cushion radii (fractions of width, height)
uniform float u_pr_stitch_dp = 5.0;     // stitch dash period along the cushion rim, dp
uniform float u_pr_ao_w = 0.22;
uniform float u_pr_wide = 1.35;        // a wide (detail) well's cushion: a little roomier
uniform float u_pr_thick = 0.04;        // the cushion's stuffed side band (fraction of height)         // the toy's contact occlusion on the cushion (x width)

varying vec2 v_local;

void vertex() {
	v_local = VERTEX;
}

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// The product sweep (see u_product). uv is 0..1 in the well, y down.
mediump vec3 product_sweep(vec2 uv, float aspect) {
	mediump vec3 paper = u_pr_paper.rgb;
	// the cushion keeps the toy's footprint in a wide well (its width is in height units)
	vec2 pad = vec2(u_pr_pad.x / max(aspect, 1.0) * mix(1.0, u_pr_wide, step(1.2, aspect)), u_pr_pad.y);
	mediump vec3 tint = mix(paper, u_pr_tint.rgb, u_pr_tint_k);
	// wall: a touch deeper at the top, the sweep bend the lightest (the light pools there), the floor
	// falling off gently toward the camera; one smooth curve, never a line
	float bend = smoothstep(u_pr_sweep - 0.22, u_pr_sweep + 0.10, uv.y);
	mediump vec3 wall = mix(tint * 0.955, tint, smoothstep(0.0, u_pr_sweep, uv.y));
	mediump vec3 floor_c = mix(mix(tint, paper, 0.35), tint * 0.965, smoothstep(u_pr_sweep, 1.05, uv.y));
	mediump vec3 c = mix(wall, floor_c, bend);
	// soft key pool behind the toy, offset toward the light (upper left)
	vec2 key = normalize(u_pr_key);
	vec2 kc = vec2(0.5 + key.x * 0.22, 0.42 - key.y * 0.12);
	float kd = length((uv - kc) * vec2(aspect, 1.0) / vec2(0.62, 0.52));
	c = mix(c, mix(c, vec3(1.0, 0.992, 0.965), 0.85), (1.0 - smoothstep(0.0, 1.0, kd)) * 0.5);
	// felt moss cushion: an ellipse whose top face is lit from the key side, a darker rim below
	vec2 pc = vec2(0.5, u_ground_y);
	vec2 pq = (uv - pc) * vec2(1.0, 1.0) / pad;
	float pr = length(pq);
	float px_w = 1.5 / max(u_size.y * pad.y, 1.0);
	// its cast shadow first: a soft ellipse pushed down-right, away from the key
	vec2 sq = (uv - pc - vec2(-key.x * 0.06, u_pr_thick + 0.02)) / (pad * vec2(1.15, 1.35));
	float sh = (1.0 - smoothstep(0.45, 1.15, length(sq))) * 0.30;
	// lavender-tinted, never grey (Art Bible shadow rule)
	c = mix(c, c * vec3(0.78, 0.76, 0.88), sh);
	// the stuffed side band: the same ellipse swept down by the cushion's thickness, a little
	// darker and rounder toward its bottom edge (a pouf, not a flat coaster)
	vec2 sp = uv - pc - vec2(0.0, clamp(uv.y - pc.y, 0.0, u_pr_thick));
	float side_r = length(sp / pad);
	float side_m = 1.0 - smoothstep(1.0 - px_w, 1.0 + px_w, side_r);
	float side_t = clamp((uv.y - pc.y) / max(u_pr_thick + pad.y, 1e-3), 0.0, 1.0);
	mediump vec3 side = mix(u_pr_felt.rgb, paper, 0.1) * mix(0.86, 0.70, side_t);
	// the key side of the band catches a little light
	side *= 1.0 + clamp(-sp.x / pad.x * key.x, -1.0, 1.0) * 0.06;
	c = mix(c, side, side_m);
	float pad_m = 1.0 - smoothstep(1.0 - px_w, 1.0 + px_w, pr);
	mediump vec3 felt = mix(u_pr_felt.rgb, paper, 0.18);
	// pillowy: lighter toward the key-side top, rolling off at the rim (stuffed volume), with a
	// soft lit lip along the far edge where the cushion's top face turns over
	float lit = clamp(0.55 - pq.y * 0.35 + pq.x * key.x * 0.18, 0.0, 1.0);
	felt *= mix(0.86, 1.05, lit) * mix(1.0, 0.84, smoothstep(0.6, 1.0, pr) * step(0.0, pq.y));
	felt = mix(felt, felt * 1.12, smoothstep(0.7, 0.95, pr) * smoothstep(0.0, -0.6, pq.y) * 0.6);
	// one running stitch just inside the rim: short cream dashes along the ellipse
	float ang = atan(pq.y, pq.x);
	float rim_len = 3.14159 * (pad.x * u_size.x + pad.y * u_size.y) / PX_PER_DP;
	float dash_t = fract(ang / 6.28318 * rim_len / u_pr_stitch_dp);
	float dash = smoothstep(0.08, 0.16, dash_t) * (1.0 - smoothstep(0.52, 0.6, dash_t));
	float ring_px = abs(pr - 0.82) * u_size.y * pad.y;
	float ring = 1.0 - smoothstep(0.6, 1.6, ring_px);
	felt = mix(felt, vec3(1.0, 0.975, 0.92), ring * dash * 0.7);
	// the toy presses into the cushion: a soft occlusion right under it
	vec2 aq = (uv - pc - vec2(0.0, -0.012)) / vec2(u_pr_ao_w * pad.x / u_pr_pad.x, pad.y * 0.55);
	felt *= 1.0 - (1.0 - smoothstep(0.2, 1.0, length(aq))) * 0.28;
	c = mix(c, felt, pad_m);
	// a whisper of vignette: the sweep has depth
	float vig = smoothstep(0.5, 1.15, length((uv - vec2(0.5, 0.45)) * vec2(aspect, 1.0) * 1.3));
	return c * (1.0 - vig * 0.06);
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
	if (u_product > 0.5) {
		c = product_sweep(uv, aspect);
	}
	c = finish(c, v_local / PX_PER_DP, FRAGCOORD.xy, mix(GRAIN_OBJECT, GRAIN_SKY, u_product));
	COLOR = vec4(c, cov * COLOR.a);
}
