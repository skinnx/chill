// Ambient particle drawing (Art Bible §4.15, §7.1): one canvas shader for every system; `kind`
// picks the look. Premultiplied output, so additive systems (dust, pollen, fireflies) write
// alpha 0 and mixed ones (seeds, petals, rain, splash) write coverage, with one blend mode.
// Per particle (from wander.gdshader): COLOR.a alpha, INSTANCE_CUSTOM = (phase, age, size px, k).
shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

#include "res://shaders/inc/globals.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

const int KIND_DUST = 0;
const int KIND_POLLEN = 1;
const int KIND_SEEDS = 2;
const int KIND_PETALS = 3;
const int KIND_FIREFLIES = 4;
const int KIND_RAIN = 5;
const int KIND_SPLASH = 6;
const float HALO_GAIN = 0.9;
const float SPLASH_ALPHA = 0.8;
const float RAIN_SHEATH_A = 0.45;
const float RAIN_SHEATH_DARK = 0.55;

uniform int kind = 0;
uniform bool additive = true;
uniform vec4 tint : source_color = vec4(1.0, 0.945, 0.761, 1.0);
// Fireflies: tint = core, tint2 = halo (g_accent unless set). Petals: tint2 = shade.
uniform vec4 tint2 : source_color = vec4(1.0, 0.789, 0.471, 1.0);
uniform bool tint2_is_accent = true;
// Objects (seeds, petals) are lit by the ambient multiply; lights (dust, fireflies) are not.
uniform bool lit_by_ambient = false;
// Fireflies: core diameter as a fraction of the quad (halo) size; pulse shape (Art Bible §7.1).
uniform float core_frac = 0.17;
uniform float pulse_base = 0.35;
uniform vec3 pulse_shape = vec3(0.25, 0.15, 0.45);
// Dust lives only inside the light shafts (ShaftController): (x, y, angle, length) design px.
uniform vec4 u_shafts[5];
uniform int u_shaft_count = 0;
uniform vec2 u_shaft_w = vec2(50.0, 115.0);
uniform float visibility = 1.0;

varying vec4 v_custom;
varying float v_alpha;
varying float v_mask;

float shaft_mask(vec2 p) {
	float m = 0.0;
	for (int i = 0; i < 5; i++) {
		if (i >= u_shaft_count) {
			break;
		}
		vec4 s = u_shafts[i];
		vec2 dir = vec2(cos(s.z), sin(s.z));
		vec2 d = p - s.xy;
		float along = dot(d, dir) / max(s.w, 1.0);
		float across = abs(dot(d, vec2(-dir.y, dir.x)));
		float w = mix(u_shaft_w.x, u_shaft_w.y, clamp(along, 0.0, 1.0));
		float inside = (1.0 - smoothstep(w * 0.45, w, across)) * smoothstep(0.0, 0.15, along) * (1.0 - smoothstep(0.6, 1.0, along));
		m = max(m, inside);
	}
	return m;
}

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_alpha = COLOR.a;
	v_mask = 1.0;
	if (kind == KIND_DUST) {
		vec2 centre = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy - g_world_offset;
		v_mask = shaft_mask(centre) * g_shafts * (1.0 - g_rain) * g_celestial.x;
	}
}

float firefly_pulse(float phase, float k) {
	float period = 600.0 / max(k, 1.0);
	float t = fract(g_time / period + phase) * period;
	float rise = pulse_shape.x;
	float hold = pulse_shape.y;
	float fall = pulse_shape.z;
	float up = smoothstep(0.0, rise, t);
	float down = 1.0 - smoothstep(rise + hold, rise + hold + fall, t);
	return mix(pulse_base, 1.0, up * down);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;  // -1..1 across the quad
	float r = length(q);
	float a = 0.0;
	vec3 c = tint.rgb;
	bool glow = false;
	if (kind == KIND_DUST || kind == KIND_POLLEN) {
		a = exp(-r * r * 4.5) * (1.0 - smoothstep(0.8, 1.0, r));
	} else if (kind == KIND_FIREFLIES) {
		float pulse = firefly_pulse(v_custom.x, v_custom.w);
		float core = 1.0 - smoothstep(core_frac * 0.6, core_frac, r);
		float r0 = core_frac * 1.8;
		float halo = (1.0 / (1.0 + (r / r0) * (r / r0)) - 0.03) * (1.0 - smoothstep(0.6, 1.0, r));
		vec3 halo_c = tint2_is_accent ? g_accent.rgb : tint2.rgb;
		// Already premultiplied light: core + halo, both breathing with the pulse.
		c = (tint.rgb * core + halo_c * max(halo, 0.0) * HALO_GAIN * (1.0 - core)) * pulse * g_lights;
		a = 1.0;
		glow = true;
	} else if (kind == KIND_RAIN) {
		float across = abs(q.x);
		// A bright ~3 px core (of the 7 px quad), brightest at its leading (lower) end and fading up
		// its tail, inside a faint darker sheath so a streak reads on light skies and dark ground
		// alike (round 3: QA r2 could not see the rain).
		float len = mix(0.35, 1.0, smoothstep(-0.9, 0.7, q.y)) * (1.0 - smoothstep(0.88, 1.0, abs(q.y)));
		float core = 1.0 - smoothstep(0.22, 0.45, across);
		float sheath = (1.0 - smoothstep(0.45, 1.0, across)) * (1.0 - core);
		a = (core + sheath * RAIN_SHEATH_A) * len;
		c = mix(tint.rgb * RAIN_SHEATH_DARK, tint.rgb, core / max(core + sheath * RAIN_SHEATH_A, 1e-4));
	} else if (kind == KIND_SPLASH) {
		float u = clamp(v_custom.y / 0.6, 0.0, 1.0);
		float rad = 0.25 + 0.7 * (1.0 - (1.0 - u) * (1.0 - u));
		a = (1.0 - smoothstep(0.0, 0.16, abs(r - rad))) * (1.0 - u) * SPLASH_ALPHA;
	} else if (kind == KIND_SEEDS) {
		// Pappus: a fluffy umbrella of fine filaments over a thin stalk and a tiny seed (y up = -q.y).
		vec2 p = vec2(q.x, -q.y);
		float stalk = (1.0 - smoothstep(0.03, 0.08, abs(p.x))) * step(-0.75, p.y) * step(p.y, 0.25);
		float seed = 1.0 - smoothstep(0.08, 0.14, length((p - vec2(0.0, -0.8)) * vec2(1.6, 0.8)));
		vec2 u = p - vec2(0.0, 0.2);
		float ang = atan(u.x, u.y);
		float fil = step(abs(ang), 1.45) * (1.0 - smoothstep(0.55, 0.75, length(u)))
				* (0.45 + 0.55 * smoothstep(0.6, 0.95, abs(cos(ang * 9.0))));
		a = max(max(stalk, seed), fil * 0.75);
	} else if (kind == KIND_PETALS) {
		float e = length(q * vec2(1.0, 1.3));
		float notch = 1.0 - smoothstep(0.0, 0.18, length(q - vec2(0.0, -0.9)));
		a = (1.0 - smoothstep(0.82, 1.0, e)) * (1.0 - notch);
		c = mix(tint2.rgb, tint.rgb, smoothstep(-0.8, 0.6, -q.y));
	}
	if (lit_by_ambient) {
		c *= g_ambient.rgb;
	}
	a *= v_alpha * v_mask * visibility;
	if (glow) {
		vec3 lit = c * a;
		if (max(lit.r, max(lit.g, lit.b)) < 0.002) {
			discard;
		}
		COLOR = vec4(max(lit + tpdf(FRAGCOORD.xy), vec3(0.0)), 0.0);
	} else {
		if (a < 0.002) {
			discard;
		}
		vec3 rgb = c * a + tpdf(FRAGCOORD.xy);
		COLOR = vec4(max(rgb, vec3(0.0)), additive ? 0.0 : a);
	}
}
