// Shared finish (synthesis C6, Art Bible §4.2, 05 §2.4): luminance grain anchored to the object
// (1 dp cells in the object's own space, weighted 4L(1-L) toward the midtones) + TPDF dither of
// +-1 LSB in screen space. Every gradient, halo, fog and glass shader ends with it.
// Grain amplitudes: objects 0.020, terrain 0.016, sky 0.012, glass 0.010.
#ifndef MM_FINISH_INC
#define MM_FINISH_INC
#include "res://shaders/inc/noise.gdshaderinc"

const float GRAIN_OBJECT = 0.020;
const float GRAIN_TERRAIN = 0.016;
const float GRAIN_SKY = 0.012;
const float GRAIN_GLASS = 0.010;
const float GRAIN_WATER = 0.014;
// px per dp (spots.json frame.px_per_dp = 3; synthesis C2).
const float PX_PER_DP = 3.0;

// TPDF dither alone (sum of two uniform hashes - 1), +-1 LSB of 8-bit output.
float tpdf(vec2 frag) {
	return (h12(frag) + h12(frag + 17.17) - 1.0) / 255.0;
}

vec3 finish(vec3 c, vec2 uv_dp, vec2 frag, float grain) {
	float l = clamp(dot(c, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
	c += (h12(floor(uv_dp)) - 0.5) * 2.0 * grain * 4.0 * l * (1.0 - l);
	return c + tpdf(frag);
}

#endif
