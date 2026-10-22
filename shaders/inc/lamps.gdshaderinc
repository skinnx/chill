// Warm local light pools (Art Bible §4.1 u_lamps, §4.5 step 8, §8.3). Material uniforms set by
// LampRegistry (scripts/world/lamp_registry.gd) only when a lamp changes.
//   u_lamps[i] = (design x, design y, radius px, intensity 0..1); u_lamp_count active entries.
//
// Each lamp lights a DISCRETE pool on the ground: a flattened ellipse (ground plane, y / 0.70)
// whose alpha holds a broad plateau and falls as peak * (1 - smoothstep(0.25, 1, d / r)) (round 3:
// QA r2 read the old (1 - q^2)^2 pools as faint smudges) plus a small hot core at the source,
// breathing +-5 % at k 181. Pools combine with max(), never a sum, so a row of lanterns
// reads as separate pools with darker gaps between them, never one flat slab (QA round 1).
// LampRegistry.weight_at() mirrors this falloff on the CPU (creatures light themselves with it).
//
//   lamp_weight(p)      0..~0.5 pool alpha at design px p, already x g_lights
//   apply_lamp(c, w)    screen-blends g_accent over c: lifts value and warms the hue, never
//                       passes through brown and never clips to white
//   lamp_fill(alb, w)   additive warm fill for lit objects (props, fronds, grass)
#ifndef MM_LAMPS_INC
#define MM_LAMPS_INC
#include "res://shaders/inc/globals.gdshaderinc"

const int MAX_LAMPS = 12;
const float LAMP_BREATH_K = 181.0;
const float LAMP_BREATH_AMP = 0.05;
// Ground-plane squash of a pool (matches the 0.62 depth foreshortening of the meadow).
const float LAMP_POOL_SQUASH = 0.70;
const float LAMP_PEAK_MIN = 0.36;
const float LAMP_PEAK_MAX = 0.46;
const float LAMP_CORE_Q = 0.16;
const float LAMP_CORE_K = 0.22;
// Pool plateau: full strength out to this fraction of the radius, then a smooth falloff to 0.
const float LAMP_PLATEAU = 0.25;
// Round 5 (QA r4: a row of lanterns read as one flat strip with a hard top): each pool is a soft
// radial glow, peak * exp(-LAMP_FALLOFF q^2) faded to 0 at the rim, so neighbours keep darker gaps.
const float LAMP_FALLOFF = 1.8;
const float LAMP_RIM = 0.65;
// The pool also lifts the albedo it lands on (adds light, not just a warm veil).
const float LAMP_LIFT = 0.8;
const float LAMP_TINT = 1.2;
// Rain: pools read better on wet ground (Art Bible §8.4, +0.05).
const float LAMP_RAIN_ADD = 0.05;

uniform vec4 u_lamps[12];
uniform int u_lamp_count = 0;

float lamp_weight(vec2 p_design) {
	float w = 0.0;
	for (int i = 0; i < MAX_LAMPS; i++) {
		if (i >= u_lamp_count) {
			break;
		}
		vec4 l = u_lamps[i];
		vec2 d = p_design - l.xy;
		d.y /= LAMP_POOL_SQUASH;
		float r = max(l.z, 1.0);
		float q = length(d) / r;
		if (q >= 1.0) {
			continue;
		}
		float breath = 1.0 + LAMP_BREATH_AMP * sin(TAU * LAMP_BREATH_K / 600.0 * g_time + float(i) * 1.7);
		float peak = mix(LAMP_PEAK_MIN, LAMP_PEAK_MAX, clamp(l.w, 0.0, 1.0)) + LAMP_RAIN_ADD * g_rain;
		float f = exp(-LAMP_FALLOFF * q * q) * (1.0 - smoothstep(LAMP_RIM, 1.0, q));
		float core = LAMP_CORE_K * exp(-(q * q) / (LAMP_CORE_Q * LAMP_CORE_Q));
		w = max(w, (peak * f + core) * breath);
	}
	return w * g_lights;
}

// Kept for older call sites: the pool alpha is already soft, so this is identity
// with a ceiling.
float lamp_soft(float w) {
	return min(w, 0.6);
}

vec3 apply_lamp(vec3 c, float w) {
	vec3 a = g_accent.rgb * clamp(w, 0.0, 0.6);
	// Albedo lift (light falling on the surface), then a screen blend 1 - (1 - c)(1 - a): warm,
	// value-lifting, cannot exceed 1.
	c = min(c + c * a * LAMP_LIFT, vec3(1.0));
	c = 1.0 - (1.0 - c) * (1.0 - a);
	// Warm the hue inside the pool at the same luminance (a teal meadow under a candle-warm lamp
	// must read amber, not olive).
	const vec3 LUM = vec3(0.2126, 0.7152, 0.0722);
	vec3 warm = g_accent.rgb * (dot(c, LUM) / max(dot(g_accent.rgb, LUM), 1e-3));
	return mix(c, min(warm, vec3(1.0)), clamp(w, 0.0, 0.6) * LAMP_TINT);
}

vec3 lamp_fill(vec3 albedo, float w) {
	return albedo * g_accent.rgb * clamp(w, 0.0, 0.6) * 1.6;
}

#endif
