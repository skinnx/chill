// Feasibility spike for docs/ART_BIBLE.md §4.5 / §5 — reference only, NOT production code.
// Verified 2026-10-20: compiles and renders on 4.7.2 opengl3_es (llvmpipe) with 16 instance uniforms,
// blend_premul_alpha, global uniforms and dFdx/fwidth. Render: fur_spike_golden.png (golden-hour globals).
// Production shader = shaders/creature/mossling_fur.gdshader per ART_BIBLE §4.5 (adds ears/tails/antennae
// variants, patterns, eye types, lamp light, wind follow, LOD). Numbers here are the tuned starting values.
shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

global uniform float g_time;
global uniform float g_wind;
global uniform float g_motion;
global uniform vec2 g_sun_dir;
global uniform vec2 g_sun_pos;
global uniform vec4 g_ambient;
global uniform vec4 g_key;
global uniform vec4 g_shadow;
global uniform float g_rim;
global uniform float g_backlight;
global uniform float g_lights;
global uniform vec4 g_lamp0;

instance uniform vec4 i_fur : source_color = vec4(0.949, 0.890, 0.804, 0.5);
instance uniform vec4 i_belly : source_color = vec4(0.984, 0.953, 0.906, 1.0);
instance uniform vec4 i_tip : source_color = vec4(0.973, 0.925, 0.863, 0.45);
instance uniform vec4 i_blush : source_color = vec4(0.941, 0.639, 0.627, 0.5);
instance uniform vec4 i_eye : source_color = vec4(0.227, 0.180, 0.247, 0.20);
instance uniform vec4 i_pattern : source_color = vec4(0.914, 0.812, 0.663, 0.0);
instance uniform vec4 i_part : source_color = vec4(0.969, 0.851, 0.788, 0.0);
instance uniform vec4 i_body = vec4(1.18, 2.6, 1.0, 150.0);
instance uniform vec4 i_ears = vec4(1.0, 0.19, 0.62, 0.0);
instance uniform vec4 i_tail = vec4(1.0, 0.15, 0.0, 1.0);
instance uniform vec4 i_antenna = vec4(0.0, 0.0, 0.0, 0.0);
instance uniform vec4 i_face = vec4(1.0, 0.40, 0.42, 1.0);
instance uniform vec4 i_pattern_p = vec4(0.0, 1.0, 0.0, 0.0);
instance uniform vec4 i_anim = vec4(1.0, 0.0, 0.0, 0.0);
instance uniform vec4 i_follow = vec4(0.0, 0.0, 0.0, 150.0);
instance uniform vec4 i_state = vec4(0.0, 0.0, 1.0, 0.37);

const vec2 QUAD_BU = vec2(2.2, 2.0);
const float FEET_PAD_BU = 0.1;
const float BOTTOM_EXTRA_N = 1.2;

float h12(vec2 p) { vec3 q = fract(vec3(p.xyx) * .1031); q += dot(q, q.yzx + 33.33); return fract((q.x + q.y) * q.z); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h12(i), h12(i + vec2(1, 0)), u.x), mix(h12(i + vec2(0, 1)), h12(i + vec2(1, 1)), u.x), u.y);
}
float smin(float a, float b, float k) { float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }
float sd_squircle(vec2 p, vec2 r, float n) {
	vec2 q = abs(p) / r;
	float m = pow(pow(q.x, n) + pow(q.y, n), 1.0 / n);
	return (m - 1.0) * min(r.x, r.y);
}
float sd_ellipse_approx(vec2 p, vec2 r) { float k = length(p / r); return (k - 1.0) * min(r.x, r.y); }

void fragment() {
	float S = i_body.w;                                   // body height in px
	vec2 p = vec2((UV.x - 0.5) * QUAD_BU.x, (1.0 - UV.y) * QUAD_BU.y - FEET_PAD_BU);   // bu, y up, feet at 0
	// breathing (in shader, from g_time) + squash about the feet
	float k_b = i_follow.w;
	float ph = fract(g_time * k_b / 600.0 + i_state.w);
	float br = ph < 0.4 ? smoothstep(0.0, 0.4, ph) : 1.0 - smoothstep(0.4, 1.0, ph);
	float amp = mix(1.0, 1.4, i_state.x) * g_motion;
	vec2 sc = vec2((1.0 / i_anim.x) * (1.0 - 0.01 * br * amp), i_anim.x * (1.0 + 0.025 * br * amp));
	vec2 ps = p / sc;
	float facing = i_state.z;
	// body
	float wh = i_body.x;
	vec2 c = vec2(0.0, 0.5);
	vec2 r = vec2(0.5 * wh, 0.5);
	vec2 q = ps - c;
	float n = i_body.y + (q.y < 0.0 ? BOTTOM_EXTRA_N * smoothstep(0.0, -0.5, q.y) : 0.0);
	float d = sd_squircle(q, r, n);
	// round ears
	float ear_a = i_ears.z + i_follow.x + 0.06 * sin(g_time * TAU * 124.0 / 600.0 + i_state.w * 6.0) * g_wind * g_motion;
	if (i_ears.x > 0.5 && i_ears.x < 1.5) {
		for (int s = -1; s <= 1; s += 2) {
			float a = float(s) * ear_a;
			vec2 ec = c + vec2(sin(a) * r.x * 0.86, cos(a) * r.y * 0.92);
			float de = length(ps - ec) - i_ears.y;
			d = smin(d, de, 0.06);
		}
	}
	// puff tail
	if (i_tail.x > 0.5 && i_tail.x < 1.5) {
		vec2 tc = vec2(-facing * r.x * 0.98, 0.24);
		d = smin(d, length(ps - tc) - i_tail.y, 0.04);
	}
	// fuzz: (a) low-amplitude silhouette wobble, (b) semi-transparent fibre fringe outside the silhouette
	vec2 pc = ps - c;
	float ang = atan(pc.y, pc.x);
	float perim_px = 3.1416 * (r.x + r.y) * S;
	float N = floor(perim_px / 3.6);                       // one fibre per ~1.2 dp
	float d_px = d * S;
	float wob = (vnoise(vec2(ang * N / (TAU * 6.0), 0.5)) - 0.5) * 2.0 * 1.8;   // ±0.6 dp
	float d_s = d_px - wob;
	float fuzz_px = mix(3.0, 9.0, i_fur.a);                // 1.0..3.0 dp
	float fib_a = vnoise(vec2(ang * N / TAU, length(pc) * 1.5));
	float fib_b = vnoise(vec2(ang * N * 1.7 / TAU + 11.0, length(pc) * 2.5));
	float fib = smoothstep(0.45, 0.85, fib_a * 0.6 + fib_b * 0.4);
	float len_j = 0.55 + 0.45 * h12(vec2(floor(ang * N / TAU), 9.0));
	float fringe_t = clamp(d_s / (fuzz_px * len_j), 0.0, 1.0);    // 0 at silhouette, 1 at fibre tip
	float aa = max(fwidth(d_px), 0.75);
	float core = 1.0 - smoothstep(-aa, aa, d_s);
	float fringe_a = (d_s > 0.0 ? fib * (1.0 - fringe_t) * (1.0 - fringe_t) * 0.85 : 0.0);
	float cover = clamp(core + fringe_a * (1.0 - core), 0.0, 1.0);
	if (cover <= 0.002) { COLOR = vec4(0.0); }
	else {
		vec2 nrm = normalize(vec2(dFdx(d_px), -dFdy(d_px)) + 1e-5);
		float depth_in = clamp(-d_px / (0.35 * S), 0.0, 1.0);      // 0 at edge -> 1 deep inside
		vec3 alb = i_fur.rgb;
		float belly = 1.0 - smoothstep(-0.05, 0.05, sd_ellipse_approx(ps - vec2(0.0, 0.27), vec2(0.62 * r.x, 0.48 * 0.5)));
		alb = mix(alb, i_belly.rgb, belly * 0.85);
		alb *= 1.0 + (vnoise(ps * 9.0) * 0.05 - 0.025) + (vnoise(ps * 31.0) * 0.03 - 0.015);
		float fringe = 1.0 - depth_in;
		alb = mix(alb, i_tip.rgb, smoothstep(0.6, 1.0, fringe) * i_tip.a);
		vec3 col = alb * g_ambient.rgb;
		// volume: top light, soft core lift, edge falloff, bottom AO toward shadow tint
		float top = smoothstep(0.05, 0.95, ps.y);
		col = mix(col, col + g_key.rgb * 0.09, top);
		col *= mix(0.93, 1.03, smoothstep(0.0, 0.6, depth_in));
		float ao = 1.0 - smoothstep(0.0, 0.25, ps.y);
		col = mix(col, col * g_shadow.rgb * 1.85, ao * 0.25);
		// rim light: toward the key; under backlight the top and sun-side light up, the bottom never does
		vec2 Ld = normalize(vec2(g_sun_dir.x, -g_sun_dir.y));
		float lam = clamp(dot(nrm, Ld), 0.0, 1.0);
		float up = smoothstep(-0.35, 0.75, nrm.y);
		float rim_w = mix(4.5, 9.0, g_backlight);
		float rim_band = smoothstep(-rim_w, -1.0, d_s);
		float rim = rim_band * mix(lam * lam, up * (0.35 + 0.65 * lam), g_backlight) * g_rim;
		col += g_key.rgb * rim * 0.45;
		// peach fuzz: fibres outside the silhouette glow in key colour when backlit
		col = mix(col, mix(col, g_key.rgb, 0.85) * 1.12, clamp((fringe_a + rim_band * 0.35 * up) * g_backlight * up, 0.0, 1.0) * smoothstep(-3.0, 0.0, d_s));
		// face
		float ex = i_face.y * 0.5 * wh;
		float ey = 1.0 - i_face.z;   // eye centre height (bu above feet) — i_face.z = from top
		float ew = 0.5 * 0.20 * wh;  // eye half-width (20 % of body width)
		vec2 look = vec2(facing * 0.05, 0.0);
		float lid = i_anim.z;
		float eyes = 0.0; float shine = 0.0;
		for (int s = -1; s <= 1; s += 2) {
			vec2 ep = ps - (vec2(float(s) * ex, ey) + look);
			vec2 er = vec2(ew, ew * 1.18 * max(1.0 - lid, 0.08));
			float de = sd_ellipse_approx(ep, er) * S;
			eyes = max(eyes, 1.0 - smoothstep(-0.8, 0.8, de));
			float ds = (length(ep - vec2(-0.30, 0.38) * ew) - ew * 0.36) * S;
			float ds2 = (length(ep - vec2(0.38, -0.42) * ew) - ew * 0.14) * S;
			shine = max(shine, (1.0 - smoothstep(-0.8, 0.8, min(ds, ds2))) * (1.0 - lid));
			// blush
			vec2 bp = ps - (vec2(float(s) * (ex + 0.07), ey - 0.12) + look);
			float bl = exp(-dot(bp / vec2(0.085, 0.045), bp / vec2(0.085, 0.045)));
			col = mix(col, i_blush.rgb * g_ambient.rgb, bl * (i_blush.a + 0.25 * i_state.y));
		}
		col = mix(col, i_eye.rgb * g_ambient.rgb, eyes);
		col = mix(col, vec3(1.0, 0.992, 0.973), shine * eyes);
		// mouth: small smile arc
		vec2 mp = ps - (vec2(0.0, ey - 0.075) + look);
		float md = abs(length(mp - vec2(0.0, 0.035)) - 0.035) * S;
		float marc = (1.0 - smoothstep(0.9, 1.9, md)) * step(mp.y, 0.02);
		col = mix(col, i_eye.rgb * g_ambient.rgb, marc * 0.85);
		// grain + TPDF
		vec2 uv_dp = ps * S / 3.0;
		float Lm = dot(col, vec3(0.2126, 0.7152, 0.0722));
		col += (h12(floor(uv_dp)) - 0.5) * 2.0 * 0.02 * 4.0 * Lm * (1.0 - Lm);
		col += (h12(FRAGCOORD.xy) + h12(FRAGCOORD.xy + 17.17) - 1.0) / 255.0;
		COLOR = vec4(col * cover, cover);   // premultiplied output
	}
}
