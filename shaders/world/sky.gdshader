// L0 sky + L1 celestial (Art Bible §4.3): exact OKLab gradient from a baked texture (top ->
// mid at 42 % -> horizon), a horizon haze band, the sun and moon discs with soft additive halos on
// their celestial paths, and twinkling stars at night. Opaque, the only full-width opaque layer.
// Vertex positions are design px of the bottom-anchored 1080x1920 frame (SkyQuad draws them).
shader_type canvas_item;
render_mode blend_disabled, unshaded;

#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

uniform sampler2D sky_tex : filter_linear, repeat_disable;
uniform float horizon_y = 690.0;
uniform float haze_center = 700.0;
uniform float haze_sigma = 45.0;
uniform float haze_amp = 0.18;
// A second, wider glow just above the crests so the haze reads above the hills [J].
uniform float haze_wide_sigma = 150.0;
uniform float haze_wide_amp = 0.10;
uniform float sun_disc_px = 96.0;
uniform float moon_disc_px = 84.0;
uniform vec4 moon_color : source_color = vec4(0.867, 0.906, 1.0, 1.0);
uniform vec4 moon_maria : source_color = vec4(0.765, 0.804, 0.922, 1.0);
uniform vec4 star_color : source_color = vec4(0.957, 0.945, 1.0, 1.0);
uniform float star_cell_px = 54.0;
uniform float star_density = 0.18;
uniform vec2 star_k_range = vec2(120.0, 300.0);
uniform vec2 star_radius_px = vec2(1.2, 2.6);
// Overcast banks for rain (and a little for breeze): palette cloud slots via PaletteFeed.
uniform vec4 cloud_lit : source_color = vec4(0.937, 0.949, 0.890, 1.0);
uniform vec4 cloud_shade : source_color = vec4(0.545, 0.749, 0.875, 1.0);
uniform float overcast_rain = 0.92;
uniform float overcast_cloud = 0.25;
// L1 parallax: the celestial bodies and stars shift by 0.02 x the camera offset.
uniform vec2 u_cam_offset = vec2(0.0);

const float LIMB_PX = 3.0;
const float LIMB_DARKEN = 0.04;
const float DISC_AA_PX = 1.5;
const float SUN_INNER_ALPHA = 0.6;
// The disc is the glow colour lifted toward white, never darker than its own halo [J].
const float SUN_WHITE = 0.7;
const float MOON_INNER_ALPHA = 0.22;
// The moon is a quiet light (QA round 1: it outranked the warm night focal): disc near L* 80.
const float MOON_DIM = 0.88;
const float MOON_OUTER_MUL = 0.6;
const float MARIA_SCALE_PX = 18.0;
const float MARIA_THRESHOLD = 0.62;
const float STAR_FADE_PX = 200.0;
const float STAR_CLOUD_DIM = 0.9;
const float HERO_SHARE = 0.14;
// Milky band: canvas-px line through MILKY_CENTRE with this normal, Gaussian width, strength.
const vec2 MILKY_CENTRE = vec2(620.0, 120.0);
const vec2 MILKY_NORMAL = vec2(0.48, 0.877);
const float MILKY_WIDTH_PX = 210.0;
const float MILKY_K = 0.1;
// Overcast drift: 16 px/s (palettes weather.cloud_autoscroll_px_s.rain) over a 1920 px tile.
const float OVERCAST_SPEED = 16.0;
const float OVERCAST_CELL = 240.0;
// Overcast shape: y scale (1.3 = masses only slightly wider than tall) and domain-warp strength.
const float OVERCAST_ASPECT = 1.3;
const float OVERCAST_WARP = 0.9;
const float OVERCAST_TILE = 1920.0;

varying vec2 v_design;

void vertex() {
	v_design = VERTEX;
}

// Overcast fBm: 3 octaves, the finer two offset off the lattice so no grid shows; the coarse
// octave tiles in x for a seamless drift.
float overcast_noise(vec2 q, vec2 per) {
	float a = vnoise_tiled(q, per);
	float b = vnoise_tiled(q * 2.0 + vec2(0.37, 3.31), per * 2.0);
	float c = vnoise_tiled(q * 4.0 + vec2(0.71, 1.73), per * 4.0);
	return (4.0 * a + 2.0 * b + c) / 7.0;
}

// Soft disc coverage with an AA edge of `aa` px.
float disc(float r, float radius, float aa) {
	return 1.0 - smoothstep(radius - aa, radius + aa * 0.5, r);
}

void fragment() {
	vec2 p = v_design;
	float top = -g_world_offset.y;
	float t = clamp((p.y - top) / max(horizon_y - top, 1.0), 0.0, 1.0);
	vec3 c = texture(sky_tex, vec2(t, 0.5)).rgb;

	// Haze band at the horizon (glow-tinted), plus a wide soft lift above the crests.
	vec3 haze = mix(g_sky_horizon.rgb, g_glow.rgb, 0.25);
	float hy = (p.y - haze_center) / haze_sigma;
	float hw = (p.y - haze_center) / haze_wide_sigma;
	c = mix(c, haze, haze_amp * exp(-hy * hy) + haze_wide_amp * exp(-hw * hw) * (1.0 - g_rain * 0.5));

	vec2 pc = p + g_world_offset + u_cam_offset * 0.02;  // canvas px of this fragment (L1)

	// Sun: disc + inner halo + wide outer halo (1 / (1 + (r / r0)^2)), additive, clamped.
	if (g_celestial.x > 0.001) {
		float R = sun_disc_px * 0.5;
		float r = distance(pc, g_sun_pos);
		float r0 = 3.2 * R * g_halo.x;
		float inner = SUN_INNER_ALPHA * exp(-(r * r) / (2.25 * R * R));
		float outer = g_halo.y / (1.0 + (r / r0) * (r / r0));
		vec3 sun_col = mix(g_glow.rgb, vec3(1.0), SUN_WHITE);
		float limb = 1.0 - LIMB_DARKEN * smoothstep(R - LIMB_PX, R, r);
		float d = disc(r, R, DISC_AA_PX);
		// Screen-blend the halo so it never clips to white; the disc sits on top of it.
		vec3 halo = g_glow.rgb * clamp((inner + outer) * g_celestial.x, 0.0, 1.0);
		c = c + halo * (1.0 - c);
		c = mix(c, max(c, sun_col * limb), d * g_celestial.x);
	}

	// Moon: disc with soft maria, small cool halo.
	if (g_celestial.y > 0.001) {
		float R = moon_disc_px * 0.5;
		vec2 dm = pc - g_moon_pos;
		float r = length(dm);
		float r0 = 3.2 * R * g_halo.x;
		float inner = MOON_INNER_ALPHA * exp(-(r * r) / (2.25 * R * R));
		float outer = g_halo.y * MOON_OUTER_MUL / (1.0 + (r / r0) * (r / r0));
		float d = disc(r, R, DISC_AA_PX);
		float mn = vnoise(dm / MARIA_SCALE_PX + 3.1) * 0.6 + vnoise(dm / (MARIA_SCALE_PX * 0.45) + 8.7) * 0.4;
		float m = smoothstep(MARIA_THRESHOLD - 0.12, MARIA_THRESHOLD + 0.12, mn);
		vec3 mc = mix(moon_color.rgb, moon_maria.rgb, 0.4 * m);
		mc *= (1.0 - LIMB_DARKEN * smoothstep(R - LIMB_PX, R, r)) * MOON_DIM;
		vec3 mhalo = g_glow.rgb * clamp((inner + outer) * g_celestial.y, 0.0, 1.0);
		c = c + mhalo * (1.0 - c);
		c = mix(c, mc, d * g_celestial.y);
	}

	// Stars: one candidate per cell, jittered away from the cell border, soft core + faint glow;
	// the brightest few carry a soft 4-point glint. A faint milky band crosses the night sky [J].
	float star_vis = g_stars * (1.0 - STAR_CLOUD_DIM * g_cloud) * smoothstep(horizon_y, horizon_y - STAR_FADE_PX, p.y);
	if (star_vis > 0.001) {
		vec2 mp = p + g_world_offset;
		float md = dot(mp - MILKY_CENTRE, MILKY_NORMAL) / MILKY_WIDTH_PX;
		float mn = vnoise(mp / 70.0) * 0.6 + vnoise(mp / 23.0 + 4.1) * 0.4;
		c = mix(c, star_color.rgb, exp(-md * md) * (0.3 + 0.7 * mn) * MILKY_K * star_vis);
		vec2 sp = pc - g_world_offset;
		vec2 cell = floor(sp / star_cell_px);
		float h = h12(cell + vec2(71.3, 19.7));
		if (h < star_density) {
			vec2 j = h22(cell + vec2(5.1, 3.3));
			vec2 centre = (cell + 0.15 + 0.7 * j) * star_cell_px;
			float rr = mix(star_radius_px.x, star_radius_px.y, h12(cell + vec2(2.2, 9.1)));
			float dist = distance(sp, centre);
			float k = floor(mix(star_k_range.x, star_k_range.y + 1.0, h12(cell + vec2(8.4, 1.7))));
			float tw = 0.75 + 0.25 * sin(TAU * k / LOOP_S * g_time + h * 40.0);
			float hero = step(h, star_density * HERO_SHARE);
			rr *= 1.0 + 0.5 * hero;
			float core = 1.0 - smoothstep(rr * 0.35, rr, dist);
			float glow = 0.18 / (1.0 + (dist / rr) * (dist / rr) * 1.5);
			vec2 dd = abs(sp - centre);
			float cross = (exp(-dd.y * dd.y / 1.1) * exp(-dd.x / 3.2) + exp(-dd.x * dd.x / 1.1) * exp(-dd.y / 3.2)) * 0.4 * hero;
			c = mix(c, star_color.rgb, clamp((core + glow + cross) * tw * star_vis, 0.0, 1.0));
		}
	}

	// Overcast (rain): soft felt-grey wool. Near-isotropic, domain-warped fBm grouped into large
	// banks by a low-frequency mask; lit along upper edges with a small value range; never darker
	// than the clear sky it covers at night (QA round 1). Drifts left at 16 px/s (1920 px tile).
	float oc = clamp(overcast_rain * g_rain + overcast_cloud * max(g_cloud - 0.3, 0.0), 0.0, 1.0);
	if (oc > 0.01) {
		vec2 q = vec2(p.x + OVERCAST_SPEED * g_time, p.y * OVERCAST_ASPECT) / OVERCAST_CELL;
		vec2 per = vec2(OVERCAST_TILE / OVERCAST_CELL, 4096.0);
		vec2 warp = vec2(vnoise_tiled(q * 0.5 + vec2(3.1, 0.0), per * 0.5), vnoise_tiled(q * 0.5 + vec2(7.7, 5.3), per * 0.5));
		vec2 wq = q + (warp - 0.5) * OVERCAST_WARP;
		float n = overcast_noise(wq, per);
		float n_up = overcast_noise(wq + vec2(0.0, -0.14), per);
		float banks = vnoise_tiled(q * 0.25 + vec2(1.7, 2.9), per * 0.25);
		float lift = (1.0 - t) * 0.16;
		float bank = smoothstep(0.30, 0.58, n * 0.7 + banks * 0.3 + lift) * oc;
		float lit = clamp((n - n_up) * 3.0 + 0.5, 0.0, 1.0);
		vec3 cc = mix(cloud_shade.rgb, cloud_lit.rgb, 0.42 + 0.30 * lit + 0.12 * (n - 0.5));
		cc = max(cc, c + vec3(0.04) * g_stars);
		c = mix(c, cc, bank * 0.88);
	}

	COLOR = vec4(finish(c, p / PX_PER_DP, FRAGCOORD.xy, GRAIN_SKY), 1.0);
}
