// Hash and value noise (Art Bible §4.2; 05 §2.4 Hoskins hash). Pure functions, highp inputs:
// never feed time, UV or position math through mediump (§4.0).
#ifndef MM_NOISE_INC
#define MM_NOISE_INC

// Hoskins "hash without sine": [0, 1).
float h12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

// Two independent hashes from one cell (jitter, per-cell parameters).
vec2 h22(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.xx + q.yz) * q.zy);
}

// Value noise with smoothstep interpolation, [0, 1].
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = h12(i);
	float b = h12(i + vec2(1.0, 0.0));
	float c = h12(i + vec2(0.0, 1.0));
	float d = h12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Value noise whose hash cells wrap every `period` cells: seamless flow/scroll loops.
float vnoise_tiled(vec2 p, vec2 period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 i0 = mod(i, period);
	vec2 i1 = mod(i + 1.0, period);
	float a = h12(i0);
	float b = h12(vec2(i1.x, i0.y));
	float c = h12(vec2(i0.x, i1.y));
	float d = h12(i1);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 2 unrolled octaves, gain 0.5, normalised to [0, 1].
float fbm2(vec2 p) {
	return (vnoise(p) * 2.0 + vnoise(p * 2.03 + vec2(17.1, 3.7))) / 3.0;
}

// 3 unrolled octaves, gain 0.5, normalised to [0, 1].
float fbm3(vec2 p) {
	return (vnoise(p) * 4.0 + vnoise(p * 2.03 + vec2(17.1, 3.7)) * 2.0 + vnoise(p * 4.07 + vec2(-5.3, 11.9))) / 7.0;
}

#endif
