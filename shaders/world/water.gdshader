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
uniform float rain_ring_k = 104.0;
// Body and reflection balance (round 3: a darker body with bright reflection streaks).
uniform float body_dark = 0.80;
uniform float body_shadow_k = 0.22;
uniform float shallow_k = 0.22;
uniform float refl_base = 0.16;
uniform float refl_far = 0.82;
uniform float refl_streak_k = 0.30;
// Round 4 (QA r3: golden brook read lilac-grey): with a low sun the whole ribbon mirrors the warm
// horizon, the bottom anchor of the eye path (reference frame A).
uniform float refl_backlight_k = 0.38;
uniform float mirror_k = 0.72;
uniform float column_px = 46.0;
uniform float column_k = 1.0;
uniform float lamp_streak_px = 9.0;
uniform float lamp_streak_k = 1.0;
uniform float bank_edge_k = 0.25;

const float FLOW_A_SPEED = 54.0;
const float FLOW_A_TILE = 540.0;
const float FLOW_A_CELL = 90.0;
const float FLOW_B_SPEED = 30.0;
const float FLOW_B_TILE = 360.0;
const float FLOW_B_CELL = 60.0;
// Round 4 (QA r3: ~11 Hz shimmer): every glint lives >= 0.9 s with a sin^2 envelope (smooth onset,
// no per-frame threshold) and the light-path sparkles sit on coarser, sparser cells.
const float GLINT_FADE_S = 0.9;
const vec2 SPARK_CELL_PX = vec2(22.0, 11.0);
const float SPARK_LIFE_S = 1.1;
const float SPARK_SHARE = 0.55;
// Sky-reflection streak cells (px along the flow, px across): long, thin, anisotropic.
const float REFL_CELL_X = 108.0;
const float REFL_CELL_Y = 9.0;
// Lantern streak wobble loop (k per 600 s) - a slow sin ripple, well under 3 Hz.
const float LAMP_WOBBLE_K = 420.0;
const float RIPPLE_SQUASH = 0.35;
const float RIPPLE_WIDTH_PX = 3.0;
const float RIPPLE_ALPHA = 0.75;
const float RIPPLE_BEND_PX = 4.0;
const float RAIN_RING_LIFE_S = 1.1;
// Round 4 (QA r3: rings barely showed): twice the ring strength, slightly wider.
const float RAIN_RING_ALPHA = 0.85;
const float RAIN_RING_R_PX = 20.0;
const float MIST_DRIFT_PX_S = 6.0;
const float MIST_TILE_PX = 1800.0;
const float MIST_Y = 1470.0;
// Night floor (Art Bible §1.3 "no pixel crushed under L* 6"): the darkest water keeps luminance >= this.
const float WATER_LUMA_FLOOR = 0.11;

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

	// Surface (round-3 directive 2: it must read unmistakably as WATER at every hour): a dark,
	// cool body (deep water darkened toward the shadow tint) carrying a thin mirrored sky band under
	// the far bank and long anisotropic sky-reflection streaks (x:y about 10:1) that drift with the
	// flow; the bright reflections are streaks ON a dark body, never a pale flat ribbon.
	float fres = 1.0 - smoothstep(0.0, 0.9, vr);
	vec3 body = mix(g_water_deep.rgb, g_shadow.rgb, body_shadow_k) * body_dark;
	// The near half looks down into the water: slightly lighter and greener (shallows over moss).
	body = mix(body, mix(g_water_deep.rgb, g_near.rgb, 0.35), shallow_k * smoothstep(0.55, 1.0, vr));
	// What the surface mirrors: the sky, flipped. Under the far bank it shows the band just above
	// the horizon (warm and bright at golden / dawn), toward the near bank the higher, cooler sky;
	// the reflectance falls toward the viewer (Fresnel), so the near half shows the dark body.
	float vs = smoothstep(0.04, 0.98, vr);
	vec3 sky_low = mix(g_sky_horizon.rgb, g_glow.rgb, 0.45 * g_celestial.x * g_backlight);
	vec3 sky_high = mix(g_sky_mid.rgb, g_sky_top.rgb, 0.45);
	vec3 sky = mix(sky_low, mix(g_sky_mid.rgb, sky_high, vs), smoothstep(0.22, 0.85, vs) * (1.0 - 0.75 * g_backlight * g_celestial.x));
	float rs_a = vnoise_tiled(vec2((s - FLOW_A_SPEED * g_time) / REFL_CELL_X + 1.7, y_px / REFL_CELL_Y),
			vec2(FLOW_A_TILE / REFL_CELL_X, 4096.0));
	float rs_b = vnoise_tiled(vec2((s - FLOW_B_SPEED * g_time) / (REFL_CELL_X * 0.6) + 9.2, y_px / (REFL_CELL_Y * 0.7) + 2.0),
			vec2(FLOW_B_TILE / (REFL_CELL_X * 0.6), 4096.0));
	float refl_streak = smoothstep(0.50, 0.80, rs_a * 0.65 + rs_b * 0.35);
	float refl = mix(refl_far, refl_base + refl_backlight_k * g_backlight * g_celestial.x, vs) + refl_streak * refl_streak_k * (1.0 - 0.4 * vs);
	refl *= 1.0 - 0.35 * g_rain;
	vec3 c = mix(body, sky, clamp(refl, 0.0, 0.94));
	// The far bank mirrored: a darker band of moss + grass just under the far edge, its lower edge
	// rippled and broken by the flow (the strongest single "this is water" cue).
	float mband_edge = 0.20 + 0.06 * (rs_b - 0.5) + 0.03 * sin(s * 0.09 + g_time * TAU * 31.0 / LOOP_S);
	float mirror = (1.0 - smoothstep(mband_edge - 0.05, mband_edge, vr)) * smoothstep(0.0, 0.035, vr);
	vec3 bank_ref = mix(g_near.rgb, g_shadow.rgb, 0.45) * mix(vec3(1.0), g_ambient.rgb, 0.5);
	c = mix(c, bank_ref, mirror_k * mirror * (0.75 + 0.25 * fb));
	// Fine flow dashes: thin light lines aligned with the current.
	float dash_a = smoothstep(0.66, 0.86, fa) * (1.0 - smoothstep(0.0, 0.08, abs(fract(y_px / 9.0 + fb * 0.6) - 0.5) - 0.22));
	float dash_b = smoothstep(0.72, 0.92, fb);
	float streak = clamp(dash_a * 0.7 + dash_b * 0.45, 0.0, 1.0);
	vec3 hi = mix(sky_low, vec3(1.0), 0.45);
	c = mix(c, hi, streak * (0.20 + 0.25 * fres) * (1.0 - 0.6 * g_lights));
	c *= 1.0 + (flow - 0.5) * 0.10;

	// The light path under the low sun / the moon: a bright vertical glint column built from the
	// same flow streaks (broken, shimmering), the signature of water at golden hour.
	vec2 body_pos = light_body();
	float vis = max(g_celestial.x, g_celestial.y * 0.7) * (1.0 - g_rain);
	float colx = (v_canvas.x - body_pos.x) / (column_px + 40.0 * g_backlight);
	// (At night with lanterns lit the moon path steps back so the warm streaks lead, §1.3.)
	float column = exp(-colx * colx) * (0.30 + 0.70 * max(g_backlight, g_celestial.y)) * (1.0 - 0.45 * g_lights * g_celestial.y);
	float col_break = smoothstep(0.35, 0.75, rs_a * 0.5 + fa * 0.5);
	vec3 col_c = mix(g_glow.rgb, vec3(1.0), 0.30);
	c = mix(c, col_c, clamp(column * vis * (0.25 + 0.75 * col_break) * column_k, 0.0, 0.9));
	float glint_light = (g_celestial.x * (0.35 + 0.65 * g_backlight) + g_celestial.y * 0.55) * (1.0 - g_rain * 0.7);
	// Column sparkles: small cells inside the light path (3x denser there), each breathing softly.
	vec2 sc = vec2(s, y_px) / SPARK_CELL_PX;
	vec2 sci = floor(sc);
	vec2 sj = h22(sci + 3.7);
	float sk = floor(mix(glint_k.x, glint_k.y + 1.0, sj.x));
	float st_s = fract(g_time * sk / LOOP_S + sj.y) * LOOP_S / sk;
	float life = clamp(st_s / SPARK_LIFE_S, 0.0, 1.0);
	float bell = st_s < SPARK_LIFE_S ? pow(sin(PI * life), 2.0) : 0.0;
	vec2 sp = (sci + 0.25 + 0.5 * h22(sci + 9.1)) * SPARK_CELL_PX;
	vec2 sd = vec2(s, y_px) - sp;
	float spark = exp(-dot(sd, sd) / 2.2) + 0.45 * exp(-sd.y * sd.y / 0.8) * exp(-sd.x * sd.x / 40.0);
	float sparkle_mask = column * step(1.0 - SPARK_SHARE, h12(sci + 1.3));
	c += mix(g_glow.rgb, vec3(1.0), 0.4) * spark * (0.35 + 0.65 * bell) * sparkle_mask * glint_light * 1.1 * water;

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

	// Lantern reflections (Art Bible §1.3, §4.7 step 7): each lamp near the water doubles as a long
	// vertical streak (about 12 px wide, spanning the water) wobbled by a sin ripple and broken by
	// the flow, breathing with its pool (+-5 %, 3.3 s); a hot core near the far edge.
	if (g_lights > 0.001) {
		float lw = 0.0;
		for (int i = 0; i < MAX_LAMPS; i++) {
			if (i >= u_lamp_count) {
				break;
			}
			vec4 l = u_lamps[i];
			float near = 1.0 - smoothstep(90.0, 200.0, abs(p.y - l.y));
			float wob = sin(y_px * 0.55 + g_time * TAU * LAMP_WOBBLE_K / LOOP_S + float(i) * 2.3) * 2.2;
			float xs = (p.x + wob - l.x) / lamp_streak_px;
			float breath = 1.0 + LAMP_BREATH_AMP * sin(TAU * LAMP_BREATH_K / LOOP_S * g_time + float(i) * 1.7);
			float brk = 0.45 + 0.55 * smoothstep(0.30, 0.70, rs_a * 0.6 + fa * 0.4);
			float fall = 1.0 - 0.55 * smoothstep(0.0, 1.0, vr);
			lw += exp(-xs * xs) * near * clamp(l.w, 0.0, 1.0) * brk * fall * breath;
		}
		float la = clamp(lw * g_lights * lamp_streak_k, 0.0, 0.85) * water;
		c = mix(c, mix(g_accent.rgb, vec3(1.0, 0.97, 0.88), 0.25 * clamp(lw - 0.6, 0.0, 1.0)), la);
	}

	// Sparse glints along the whole brook: one cell per 70 px, each flashes once per 600/k s.
	float gcell = floor(s / glint_cell_px);
	float gk = floor(mix(glint_k.x, glint_k.y + 1.0, h12(vec2(gcell, 7.0))));
	float gph = fract(g_time * gk / LOOP_S + h12(vec2(gcell, 13.0)));
	float gt = gph * LOOP_S / gk;
	float gamp = gt < GLINT_FADE_S ? pow(sin(PI * gt / GLINT_FADE_S), 2.0) : 0.0;
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
			rip += (1.0 - smoothstep(0.0, 2.2, abs(length(d) - rr))) * RAIN_RING_ALPHA * (1.0 - ur) * g_rain;
		}
	}
	c = mix(c, ripple_color.rgb, clamp(rip, 0.0, 0.85) * water);

	// Banks: a dark wet lip just outside the water on both sides, fading into the meadow; a thin
	// bright rim where the far edge catches the sky and a lit lip on the near edge.
	// Round 4 (QA r3 "plastic strip"): the shoreline is feathered over the whole damp bank and
	// broken by a slow noise along the arc, so the bank melts into the moss with an irregular edge.
	float shore_n = (vnoise(vec2(s / 23.0, v < 0.5 ? 1.0 : 7.0)) - 0.5) * 0.9 + (vnoise(vec2(s / 7.0, 3.0)) - 0.5) * 0.35;
	float bank_t = v < 0.0 ? -v / bank_v : (v - 1.0) / bank_v;
	float bank_a = v < 0.0 || v > 1.0 ? 1.0 - smoothstep(0.15, 0.95, bank_t + shore_n * 0.35) : 1.0;
	vec3 bank = water_bank.rgb * (1.0 + (vnoise(p / 6.0) - 0.5) * 0.08);
	bank = mix(bank, bank * g_shadow.rgb * SHADE_K, 0.35);
	c = mix(bank, c, water);
	// Inner wet shadow under the far bank (the bank overhangs the water).
	c = mix(c, c * g_shadow.rgb * SHADE_K, (1.0 - smoothstep(0.0, 0.10, v)) * 0.30 * water);
	// Both bank edges: a 6-8 px band of water darkened by ~25 % (wet moss overhang, shadowed shallows).
	float edge_px = min(v, 1.0 - v) * water_px;
	c *= 1.0 - bank_edge_k * (1.0 - smoothstep(2.0, 8.0, edge_px)) * water;
	// Round 4: soft, broken rims (QA r3: hard light outlines made the brook read as a plastic strip).
	float rim_brk = 0.55 + 0.45 * smoothstep(0.3, 0.7, fa);
	float far_rim = (1.0 - smoothstep(0.0, 4.0 / water_px, abs(v - 0.04))) * water * rim_brk;
	c = mix(c, mix(hi, vec3(1.0), 0.25), far_rim * (0.26 + 0.16 * fres) * (1.0 - 0.6 * g_lights));
	float near_rim = (1.0 - smoothstep(0.0, 5.0 / water_px, abs(v - 0.965))) * water * rim_brk;
	c = mix(c, mix(g_water_shallow.rgb, ripple_color.rgb, 0.4), near_rim * 0.14);
	float alpha = max(water, bank_a * 0.9);

	// Mist over the brook (dawn).
	float mn = g_mist <= 0.001 ? 0.0 : vnoise_tiled(vec2((p.x - MIST_DRIFT_PX_S * g_time) / 150.0, p.y / 60.0), vec2(MIST_TILE_PX / 150.0, 4096.0));
	float mband = exp(-0.5 * pow((p.y - MIST_Y) / 40.0, 2.0)) * smoothstep(0.25, 0.85, mn);
	c = mix(c, mix(g_sky_horizon.rgb, g_glow.rgb, 0.2), clamp(g_mist * mband, 0.0, 0.6));
	c += sun_veil(v_canvas, 0.25);

	float lw = wl_luma(c);
	c += max(WATER_LUMA_FLOOR - lw, 0.0) * normalize(g_water_deep.rgb + vec3(0.05)) * 1.6;
	COLOR = vec4(finish(c, p / PX_PER_DP, FRAGCOORD.xy, GRAIN_WATER), alpha);
}
