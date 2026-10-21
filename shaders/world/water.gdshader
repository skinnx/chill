// The brook (Art Bible §4.7): a ribbon along the spots.json stream polyline with damp banks, a
// shallow -> deep profile, a mirrored sky band, two tiled flow layers (seamless at the 600 s wrap),
// sparse glints (< 3 onsets/s), stone riffles, lantern reflection streaks, tap ripples (380 ms),
// rain rings and low mist. Mesh contract (BrookLayer): VERTEX = design px; UV.x = arc length px
// from the spring (flow runs toward +UV.x, right -> left on screen); UV.y = 0 far edge .. 1 near
// edge of the water, < 0 / > 1 on the banks.
shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/lamps.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

uniform vec4 water_bank : source_color = vec4(0.282, 0.569, 0.478, 1.0);
uniform vec4 ripple_color : source_color = vec4(0.871, 0.941, 0.976, 1.0);
uniform float bank_v = 0.145;
uniform float water_px = 69.0;
uniform float edge_foam = 0.35;
uniform float glint_cell_px = 70.0;
uniform vec2 glint_k = vec2(76.0, 124.0);
uniform float spring_foam_px = 220.0;
// u_stones[i] = (design x, y, radius px); riffles trail downstream (to the left).
uniform vec3 u_stones[10];
uniform int u_stone_count = 0;
// u_ripples[i] = (design x, y, start g_time, amplitude); 380 ms rings from taps / boats.
uniform vec4 u_ripples[4];
uniform float ripple_s = 0.38;
uniform float ripple_radius_px = 108.0;
uniform float rain_cell_px = 48.0;
uniform float rain_ring_k = 76.0;

const float FLOW_A_SPEED = 54.0;
const float FLOW_A_TILE = 540.0;
const float FLOW_A_CELL = 90.0;
const float FLOW_B_SPEED = 30.0;
const float FLOW_B_TILE = 360.0;
const float FLOW_B_CELL = 60.0;
const float GLINT_FADE_S = 0.4;
const float RIPPLE_SQUASH = 0.35;
const float RIPPLE_WIDTH_PX = 3.0;
const float RIPPLE_ALPHA = 0.6;
const float RIPPLE_BEND_PX = 4.0;
const float RAIN_RING_LIFE_S = 1.1;
const float RAIN_RING_R_PX = 20.0;
const float MIST_DRIFT_PX_S = 6.0;
const float MIST_TILE_PX = 1800.0;
const float MIST_Y = 1470.0;

varying vec2 v_design;
varying vec2 v_canvas;

void vertex() {
	v_design = VERTEX;
	v_canvas = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// A flattened ring of radius r around c (perspective squash), width w px; returns 0..1.
float ring(vec2 p, vec2 c, float r, float w) {
	vec2 d = p - c;
	d.y /= RIPPLE_SQUASH;
	return 1.0 - smoothstep(0.0, w, abs(length(d) - r));
}

void fragment() {
	vec2 p = v_design;
	float s = UV.x;
	float v = UV.y;
	float water = smoothstep(-0.02, 0.02, v) * (1.0 - smoothstep(0.98, 1.02, v));
	float y_px = v * water_px;

	// Flow: two elongated tiled noise layers scrolling downstream (seamless at the 600 s wrap).
	float fa = vnoise_tiled(vec2((s - FLOW_A_SPEED * g_time) / FLOW_A_CELL, y_px / 7.0),
			vec2(FLOW_A_TILE / FLOW_A_CELL, 4096.0));
	float fb = vnoise_tiled(vec2((s - FLOW_B_SPEED * g_time) / FLOW_B_CELL + 3.1, y_px / 5.0 + 5.0),
			vec2(FLOW_B_TILE / FLOW_B_CELL, 4096.0));
	float flow = fa * 0.6 + fb * 0.4;

	// Ripples first: they refract (bend) what the surface shows inside their ring.
	float rip = 0.0;
	float bendv = 0.0;
	for (int i = 0; i < 4; i++) {
		vec4 r = u_ripples[i];
		if (r.w <= 0.0) {
			continue;
		}
		float age = mod(g_time - r.z + LOOP_S, LOOP_S);
		float u = age / ripple_s;
		if (u >= 1.0) {
			continue;
		}
		float ease = 1.0 - (1.0 - u) * (1.0 - u);
		float rad = ripple_radius_px * ease;
		float fade = (1.0 - u) * (1.0 - u) * r.w;
		for (int k = 0; k < 3; k++) {
			float rk = rad * (1.0 - 0.28 * float(k));
			rip += ring(p, r.xy, rk, RIPPLE_WIDTH_PX) * RIPPLE_ALPHA * fade * (1.0 - 0.3 * float(k));
		}
		vec2 dd = p - r.xy;
		dd.y /= RIPPLE_SQUASH;
		float inside = 1.0 - smoothstep(rad * 0.9, rad, length(dd));
		bendv += sin(length(dd) * 0.35 - age * 40.0) * inside * fade * RIPPLE_BEND_PX / water_px;
	}
	float vr = clamp(v + bendv + (flow - 0.5) * 2.0 * 2.5 / water_px, 0.0, 1.0);

	// Surface: the far half mirrors the sky (grazing view, bright), the near half looks down into
	// the cooler, deeper water (Fresnel-like ramp across the channel).
	float fres = 1.0 - smoothstep(0.0, 0.85, vr);
	vec3 sky = mix(mix(g_sky_mid.rgb, g_sky_horizon.rgb, 0.65), g_water_shallow.rgb, 0.45);
	vec3 deep = mix(g_water_deep.rgb, g_sky_top.rgb, 0.18);
	// Low light (golden, dawn) grazes the surface: more of the warm sky is mirrored.
	float refl = mix(0.18 + 0.72 * fres * fres, 0.50 + 0.45 * fres, g_backlight * g_celestial.x);
	vec3 c = mix(deep, sky, refl);
	// The far bank mirrored: a soft darker band just under the far edge, broken by the flow.
	float mirror = (1.0 - smoothstep(0.0, 0.22, vr)) * smoothstep(0.0, 0.05, vr);
	c = mix(c, c * g_shadow.rgb * SHADE_K, 0.38 * mirror * (0.7 + 0.3 * fb));
	// Flow streaks: light dashes aligned with the current, stronger where the sky is mirrored.
	float dash_a = smoothstep(0.66, 0.86, fa) * (1.0 - smoothstep(0.0, 0.08, abs(fract(y_px / 9.0 + fb * 0.6) - 0.5) - 0.22));
	float dash_b = smoothstep(0.70, 0.90, fb);
	float streak = clamp(dash_a * 0.7 + dash_b * 0.45, 0.0, 1.0);
	vec3 hi = mix(g_water_shallow.rgb, g_glow.rgb, 0.5);
	c = mix(c, hi, streak * (0.22 + 0.25 * fres) * (1.0 - 0.5 * g_lights));
	c *= 1.0 + (flow - 0.5) * 0.10;

	// Light path on the water under the low sun / the moon: a bright column with sparkles.
	vec2 body = light_body();
	float vis = max(g_celestial.x, g_celestial.y * 0.6) * (1.0 - g_rain);
	float colx = (v_canvas.x - body.x) / (60.0 + 40.0 * g_backlight);
	float column = exp(-colx * colx) * (0.35 + 0.65 * g_backlight);
	c = mix(c, mix(g_glow.rgb, g_water_shallow.rgb, 0.3), column * vis * 0.42 * (0.55 + 0.45 * flow));
	float glint_light = (g_celestial.x * (0.35 + 0.65 * g_backlight) + g_celestial.y * 0.55) * (1.0 - g_rain * 0.7);
	// Column sparkles: small cells inside the light path, each breathing softly (never off/on).
	vec2 sc = vec2(s, y_px) / vec2(16.0, 9.0);
	vec2 sci = floor(sc);
	vec2 sj = h22(sci + 3.7);
	float sk = floor(mix(glint_k.x, glint_k.y + 1.0, sj.x));
	float sph = fract(g_time * sk / LOOP_S + sj.y);
	float dt_s = (sph - 0.5) * LOOP_S / sk;
	float bell = exp(-(dt_s * dt_s) / (0.45 * 0.45));
	vec2 sp = (sci + 0.25 + 0.5 * h22(sci + 9.1)) * vec2(16.0, 9.0);
	vec2 sd = vec2(s, y_px) - sp;
	float spark = exp(-dot(sd, sd) / 2.2) + 0.35 * exp(-sd.y * sd.y / 0.8) * exp(-sd.x * sd.x / 30.0);
	float sparkle_mask = column * step(0.55, h12(sci + 1.3));
	c += g_glow.rgb * spark * (0.25 + 0.75 * bell) * sparkle_mask * glint_light * 0.9 * water;

	// Edge foam and the spring's churn.
	float edge = 1.0 - smoothstep(0.0, 0.12, min(v, 1.0 - v));
	float spring = 1.0 - smoothstep(0.0, spring_foam_px, s);
	float w = 1.0 - abs(v * 2.0 - 1.0);
	float foam = (edge_foam * edge * 0.6 + 0.45 * spring * (1.0 - w * 0.4)) * smoothstep(0.35, 0.75, fb + fa * 0.5);

	// Stone riffles: a foam wedge trailing 40 px downstream (left) of each stone.
	for (int i = 0; i < 10; i++) {
		if (i >= u_stone_count) {
			break;
		}
		vec3 st = u_stones[i];
		float behind = st.x - p.x;
		float spread = st.z * (0.6 + behind / 40.0 * 0.6);
		float wedge = smoothstep(-4.0, 6.0, behind) * (1.0 - smoothstep(20.0, 48.0, behind))
				* (1.0 - smoothstep(spread * 0.4, spread, abs(p.y - st.y)));
		foam += wedge * 0.55 * smoothstep(0.3, 0.7, fa);
	}
	vec3 foam_col = mix(ripple_color.rgb, g_glow.rgb, 0.25);
	c = mix(c, foam_col, clamp(foam, 0.0, 0.8) * water);

	// Lantern reflections: vertical streaks under lamps on the far bank, broken by the flow.
	if (g_lights > 0.001) {
		float lw = 0.0;
		for (int i = 0; i < MAX_LAMPS; i++) {
			if (i >= u_lamp_count) {
				break;
			}
			vec4 l = u_lamps[i];
			float near = 1.0 - smoothstep(60.0, 160.0, abs(p.y - l.y));
			lw += exp(-pow((p.x - l.x) / 12.0, 2.0)) * near * l.w * smoothstep(0.25, 0.75, fa + 0.3 * fb);
		}
		c = mix(c, g_accent.rgb, clamp(lw * g_lights * 0.5, 0.0, 0.7) * water);
	}

	// Sparse glints along the whole brook: one cell per 70 px, each flashes once per 600/k s.
	float gcell = floor(s / glint_cell_px);
	float gk = floor(mix(glint_k.x, glint_k.y + 1.0, h12(vec2(gcell, 7.0))));
	float gph = fract(g_time * gk / LOOP_S + h12(vec2(gcell, 13.0)));
	float gt = gph * LOOP_S / gk;
	float gamp = smoothstep(0.0, GLINT_FADE_S * 0.5, gt) * (1.0 - smoothstep(GLINT_FADE_S * 0.5, GLINT_FADE_S, gt));
	vec2 gpos = vec2((gcell + 0.25 + 0.5 * h12(vec2(gcell, 3.0))) * glint_cell_px,
			(0.15 + 0.4 * h12(vec2(gcell, 5.0))) * water_px);
	vec2 gd = vec2(s, y_px) - gpos;
	float sparkle = exp(-dot(gd, gd) / 5.0) + 0.45 * exp(-gd.y * gd.y / 1.2) * exp(-gd.x * gd.x / 60.0)
			+ 0.3 * exp(-gd.x * gd.x / 1.2) * exp(-gd.y * gd.y / 18.0);
	c += g_glow.rgb * sparkle * gamp * glint_light * water;

	// Rain rings: one 48 px cell each, a ring every 600/76 s per cell.
	if (g_rain > 0.01) {
		vec2 rc = floor(vec2(s, y_px) / rain_cell_px);
		float rph = fract(g_time * rain_ring_k / LOOP_S + h12(rc + 4.4));
		float rage = rph * (LOOP_S / rain_ring_k);
		if (rage < RAIN_RING_LIFE_S) {
			vec2 centre = (rc + 0.2 + 0.6 * h22(rc + 1.9)) * rain_cell_px;
			vec2 d = vec2(s, y_px) - centre;
			d.y /= RIPPLE_SQUASH;
			float ur = rage / RAIN_RING_LIFE_S;
			float rr = RAIN_RING_R_PX * (1.0 - (1.0 - ur) * (1.0 - ur));
			rip += (1.0 - smoothstep(0.0, 1.6, abs(length(d) - rr))) * 0.3 * (1.0 - ur) * g_rain;
		}
	}
	c = mix(c, ripple_color.rgb, clamp(rip, 0.0, 0.85) * water);

	// Banks: a dark wet lip just outside the water on both sides, fading into the meadow; a thin
	// bright rim where the far edge catches the sky and a lit lip on the near edge.
	float bank_a = v < 0.0 ? smoothstep(-bank_v, 0.0, v) : 1.0 - smoothstep(1.0, 1.0 + bank_v, v);
	vec3 bank = water_bank.rgb * (1.0 + (vnoise(p / 6.0) - 0.5) * 0.08);
	bank = mix(bank, bank * g_shadow.rgb * SHADE_K, 0.35);
	c = mix(bank, c, water);
	// Inner wet shadow under the far bank (the bank overhangs the water).
	c = mix(c, c * g_shadow.rgb * SHADE_K, (1.0 - smoothstep(0.0, 0.10, v)) * 0.30 * water);
	float far_rim = (1.0 - smoothstep(0.0, 2.0 / water_px, abs(v - 0.035))) * water;
	c = mix(c, mix(hi, vec3(1.0), 0.25), far_rim * (0.45 + 0.25 * fres) * (1.0 - 0.6 * g_lights));
	float near_rim = (1.0 - smoothstep(0.0, 2.5 / water_px, abs(v - 0.975))) * water;
	c = mix(c, mix(g_water_shallow.rgb, ripple_color.rgb, 0.4), near_rim * 0.35);
	float alpha = max(water, bank_a * 0.9);

	// Mist over the brook (dawn).
	float mn = g_mist <= 0.001 ? 0.0 : vnoise_tiled(vec2((p.x - MIST_DRIFT_PX_S * g_time) / 150.0, p.y / 60.0), vec2(MIST_TILE_PX / 150.0, 4096.0));
	float mband = exp(-0.5 * pow((p.y - MIST_Y) / 40.0, 2.0)) * smoothstep(0.25, 0.85, mn);
	c = mix(c, mix(g_sky_horizon.rgb, g_glow.rgb, 0.2), clamp(g_mist * mband, 0.0, 0.6));
	c += sun_veil(v_canvas, 0.25);

	COLOR = vec4(finish(c, p / PX_PER_DP, FRAGCOORD.xy, GRAIN_WATER), alpha);
}
