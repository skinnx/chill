// Warm local light pools (Art Bible §4.1 u_lamps, §4.5 step 8, §8.3). Material uniforms set by
// LampRegistry (scripts/world/lamp_registry.gd) only when a lamp changes.
//   u_lamps[i] = (design x, design y, radius px, intensity 0..1); u_lamp_count active entries.
//
// Each lamp lights a DISCRETE pool on the ground: a flattened ellipse (ground plane, y / 0.70)
// whose alpha falls as peak * (1 - (d / r)^2)^2 plus a small hot core at the
// source, breathing +-5 % at k 181. Pools combine with max(), never a sum, so a row of lanterns
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
const float LAMP_PEAK_MIN = 0.30;
const float LAMP_PEAK_MAX = 0.40;
const float LAMP_CORE_Q = 0.16;
const float LAMP_CORE_K = 0.22;
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
		float f = 1.0 - q * q;
		float core = LAMP_CORE_K * exp(-(q * q) / (LAMP_CORE_Q * LAMP_CORE_Q));
		w = max(w, (peak * f * f + core) * breath);
	}
	return w * g_lights;
}

// Kept for older call sites: the pool alpha is already soft (no plateau), so this is identity
// with a ceiling.
float lamp_soft(float w) {
	return min(w, 0.6);
}

vec3 apply_lamp(vec3 c, float w) {
	vec3 a = g_accent.rgb * clamp(w, 0.0, 0.6);
	// Screen blend: 1 - (1 - c)(1 - a). Warm, value-lifting, cannot exceed 1.
	return 1.0 - (1.0 - c) * (1.0 - a);
}

vec3 lamp_fill(vec3 albedo, float w) {
	return albedo * g_accent.rgb * clamp(w, 0.0, 0.6) * 1.6;
}

#endif
