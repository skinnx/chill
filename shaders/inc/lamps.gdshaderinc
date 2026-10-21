// Warm local light pools (Art Bible §4.1 u_lamps, §4.5 step 8, §8.3). Material uniforms set by
// LampRegistry (scripts/world/lamp_registry.gd) only when a lamp changes.
//   u_lamps[i] = (design x, design y, radius px, intensity 0..1); u_lamp_count active entries.
// lamp_weight(p) = sum of pool alphas at p (alpha 0.25..0.40 by intensity, breathing +-5 % at
// k 181), already x g_lights; apply_lamp(c, w) lights a colour with the shared g_accent.
#ifndef MM_LAMPS_INC
#define MM_LAMPS_INC
#include "res://shaders/inc/globals.gdshaderinc"

const int MAX_LAMPS = 12;
const float LAMP_BREATH_K = 181.0;
const float LAMP_BREATH_AMP = 0.05;

uniform vec4 u_lamps[12];
uniform int u_lamp_count = 0;

float lamp_weight(vec2 p_design) {
	float w = 0.0;
	for (int i = 0; i < MAX_LAMPS; i++) {
		if (i >= u_lamp_count) {
			break;
		}
		vec4 l = u_lamps[i];
		float d = distance(p_design, l.xy);
		float r = max(l.z, 1.0);
		float q = d / r;
		float breath = sin(TAU * LAMP_BREATH_K / 600.0 * g_time + float(i) * 1.7);
		float a = (0.25 + 0.15 * clamp(l.w, 0.0, 1.0)) * (1.0 + LAMP_BREATH_AMP * breath);
		w += a * exp(-q * q * 1.25);
	}
	return w * g_lights * (1.0 + 0.2 * g_rain);
}

// Overlapping pools add up softly (a row of lanterns makes a warm band, never a flat blob).
float lamp_soft(float w) {
	return 0.6 * (1.0 - exp(-w * 2.5));
}

// Warm pool over a (dark) surface colour: shifts hue toward the lamp and lifts value without
// clipping to white (§4.5 acceptance).
vec3 apply_lamp(vec3 c, float w) {
	vec3 warm = g_accent.rgb;
	float e = lamp_soft(w);
	vec3 lit = mix(c, warm * 0.7, e * 1.2);
	return lit + warm * e * 0.18 * (1.0 - lit * 0.5);
}

#endif
