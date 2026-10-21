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
const float RIPPLE_ALPHA = 0.35;
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

	// Flow streaks: elongated tiled noise scrolling downstream.
	float fa = vnoise_tiled(vec2((s - FLOW_A_SPEED * g_time) / FLOW_A_CELL, y_px / 14.0),
			vec2(FLOW_A_TILE / FLOW_A_CELL, 4096.0));
	float fb = vnoise_tiled(vec2((s - FLOW_B_SPEED * g_time) / FLOW_B_CELL + 3.1, y_px / 9.0 + 5.0),
			vec2(FLOW_B_TILE / FLOW_B_CELL, 4096.0));
	float flow = fa * 0.6 + fb * 0.4;

	// Depth across (deeper, cooler centre), the mirrored sky band (stronger toward the far side,
	// where the view grazes the surface), bent +-2 px by the flow; the far bank shades the water.
	float w = 1.0 - abs(v * 2.0 - 1.0);
	vec3 c = mix(g_water_shallow.rgb, g_water_deep.rgb, smoothstep(0.05, 0.75, w) * 0.85);
	float refl_t = clamp(v + (flow - 0.5) * 2.0 * 2.0 / water_px, 0.0, 1.0);
	vec3 sky = mix(g_sky_horizon.rgb, g_sky_mid.rgb, refl_t);
	c = mix(c, sky, 0.18 + 0.2 * (1.0 - v));
	// The far bank mirrored in the water: a soft darker band under the far edge.
	c = mix(c, c * g_shadow.rgb * SHADE_K, 0.32 * (1.0 - smoothstep(0.0, 0.3, v)) * (0.7 + 0.3 * fb));
	// Flow: soft dark troughs and light streaks elongated along the current.
	float streak = smoothstep(0.58, 0.82, fa) * 0.6 + smoothstep(0.62, 0.86, fb) * 0.4;
	c *= 1.0 + (flow - 0.5) * 0.12;
	c = mix(c, mix(g_water_shallow.rgb, g_glow.rgb, 0.45), streak * 0.32 * (0.4 + 0.6 * w));

	// Low sun / moon path on the water: a soft bright column under the body [J].
	vec2 body = light_body();
	float col = exp(-pow((v_canvas.x - body.x) / 70.0, 2.0)) * (0.3 + 0.7 * g_backlight);
	float vis = max(g_celestial.x, g_celestial.y * 0.6);
	c = mix(c, g_glow.rgb, col * vis * 0.28 * (0.6 + 0.4 * flow) * (1.0 - g_rain));

	// Edge foam and the spring's churn.
	float edge = 1.0 - smoothstep(0.0, 0.12, min(v, 1.0 - v));
	float spring = 1.0 - smoothstep(0.0, spring_foam_px, s);
	float foam = (edge_foam * edge + 0.45 * spring * (1.0 - w * 0.4)) * smoothstep(0.35, 0.75, fb + fa * 0.5);

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

	// Glints: one cell per 70 px of length, each flashes once per 600/k s (k 76..124).
	float gcell = floor(s / glint_cell_px);
	float gk = floor(mix(glint_k.x, glint_k.y + 1.0, h12(vec2(gcell, 7.0))));
	float gph = fract(g_time * gk / LOOP_S + h12(vec2(gcell, 13.0)));
	float gperiod = LOOP_S / gk;
	float gt = gph * gperiod;
	float gamp = smoothstep(0.0, GLINT_FADE_S * 0.5, gt) * (1.0 - smoothstep(GLINT_FADE_S * 0.5, GLINT_FADE_S, gt));
	vec2 gpos = vec2((gcell + 0.25 + 0.5 * h12(vec2(gcell, 3.0))) * glint_cell_px,
			(0.25 + 0.5 * h12(vec2(gcell, 5.0))) * water_px);
	vec2 gd = vec2(s, y_px) - gpos;
	float sparkle = exp(-dot(gd, gd) / 5.0) + 0.45 * exp(-gd.y * gd.y / 1.2) * exp(-gd.x * gd.x / 60.0)
			+ 0.3 * exp(-gd.x * gd.x / 1.2) * exp(-gd.y * gd.y / 18.0);
	float glint_k_light = g_celestial.x * (0.3 + 0.7 * g_backlight) + g_celestial.y * 0.5;
	c += g_glow.rgb * sparkle * gamp * glint_k_light * water * (1.0 - g_rain * 0.7);

	// Tap / boat ripples: eased-out ring (36 dp in 380 ms) + a few popping bubbles.
	float rip = 0.0;
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
		float rad = ripple_radius_px * (1.0 - (1.0 - u) * (1.0 - u));
		rip += ring(p, r.xy, rad, RIPPLE_WIDTH_PX) * RIPPLE_ALPHA * (1.0 - u) * r.w;
		rip += ring(p, r.xy, rad * 0.55, RIPPLE_WIDTH_PX * 0.8) * RIPPLE_ALPHA * 0.6 * (1.0 - u) * r.w;
		for (int b = 0; b < 4; b++) {
			vec2 o = (h22(vec2(float(b), r.z)) - 0.5) * vec2(60.0, 14.0);
			float bt = u * 1.6 - float(b) * 0.15;
			float br = 2.5 + 1.5 * float(b % 2);
			rip += (1.0 - smoothstep(br * 0.6, br, length(p - r.xy - o))) * step(0.0, bt) * (1.0 - smoothstep(0.6, 1.0, bt)) * 0.5;
		}
	}

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

	// Damp banks outside the water: water_bank fading out into the meadow.
	float bank_a = v < 0.0 ? smoothstep(-bank_v, 0.0, v) : 1.0 - smoothstep(1.0, 1.0 + bank_v, v);
	vec3 bank = water_bank.rgb * (1.0 + (vnoise(p / 6.0) - 0.5) * 0.08);
	c = mix(bank, c, water);
	// A thin lit lip on the near bank where the water meets it.
	c = mix(c, mix(g_water_shallow.rgb, ripple_color.rgb, 0.4), (1.0 - smoothstep(0.0, 0.05, abs(v - 1.0))) * 0.35);
	float alpha = max(water, bank_a * 0.85);

	// Mist over the brook (dawn).
	float mn = g_mist <= 0.001 ? 0.0 : vnoise_tiled(vec2((p.x - MIST_DRIFT_PX_S * g_time) / 150.0, p.y / 60.0), vec2(MIST_TILE_PX / 150.0, 4096.0));
	float mband = exp(-0.5 * pow((p.y - MIST_Y) / 40.0, 2.0)) * smoothstep(0.25, 0.85, mn);
	c = mix(c, mix(g_sky_horizon.rgb, g_glow.rgb, 0.2), clamp(g_mist * mband, 0.0, 0.6));
	c += sun_veil(v_canvas, 0.25);

	COLOR = vec4(finish(c, p / PX_PER_DP, FRAGCOORD.xy, GRAIN_WATER), alpha);
}
