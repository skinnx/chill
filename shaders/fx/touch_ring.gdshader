// World touch flourish (round-3 directive 1; motion_tokens ui.ring, ui.sparkles): on touch-down a
// soft warm bloom at the touch, an eased ring that grows to 36 dp in 380 ms (alpha 0.35 -> 0,
// radius ease-out, never linear) and 3-5 four-point sparkles that ride out with it and twinkle off.
// Additive so it reads on any phase; one quad per touch (TouchRing), shared material.
// Quad contract: local VERTEX px, centre at the origin, quad half size = i_ring.y * 1.35.
shader_type canvas_item;
render_mode blend_add, unshaded;

#include "res://shaders/inc/globals.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

// x progress 0..1, y ring radius px at the end, z peak alpha, w sparkle count.
instance uniform vec4 i_ring = vec4(0.0, 108.0, 0.35, 4.0);
// x y squash (1 = round, < 1 flattened onto the ground), y seed, z bloom strength, w unused.
instance uniform vec4 i_ring2 = vec4(1.0, 0.0, 0.5, 0.0);
instance uniform vec4 i_tint : source_color = vec4(1.0, 0.957, 0.839, 1.0);

uniform float ring_w_px = 3.5;
uniform float sparkle_px = 10.0;
uniform float bloom_r = 0.32;

varying vec2 v_local;

void vertex() {
	v_local = VERTEX;
}

float star4(vec2 d, float s) {
	vec2 a = abs(d) / max(s, 0.5);
	float core = exp(-dot(a, a) * 6.0);
	float rays = exp(-a.y * a.y * 40.0) * exp(-a.x * 2.2) + exp(-a.x * a.x * 40.0) * exp(-a.y * 2.2);
	return core + 0.6 * rays;
}

void fragment() {
	float u = clamp(i_ring.x, 0.0, 1.0);
	float R = i_ring.y;
	vec2 p = v_local;
	p.y /= max(i_ring2.x, 0.2);
	float r = length(p);
	float ease = 1.0 - (1.0 - u) * (1.0 - u);
	float rad = R * ease;
	float fade = (1.0 - u);
	// Ring: a soft line plus a faint inner fill that trails it.
	float ring = 1.0 - smoothstep(0.0, ring_w_px, abs(r - rad));
	float trail = smoothstep(rad * 0.55, rad, r) * (1.0 - smoothstep(rad, rad + ring_w_px, r)) * 0.25;
	float a = (ring + trail) * i_ring.z * fade;
	// Bloom at the touch: strongest on touch-down, gone by the ring's end.
	float b = exp(-(r * r) / max(R * R * bloom_r * bloom_r, 1.0)) * i_ring2.z * (1.0 - smoothstep(0.0, 0.8, u));
	// Sparkles ride just outside the ring, twinkling off over the second half.
	float sp = 0.0;
	int n = int(i_ring.w);
	for (int i = 0; i < 5; i++) {
		if (i >= n) {
			break;
		}
		float h = h12(vec2(float(i) * 7.13, i_ring2.y * 31.7 + 3.1));
		float ang = TAU * (float(i) + 0.35 * h) / float(max(n, 1)) + i_ring2.y * TAU;
		vec2 c = vec2(cos(ang), sin(ang)) * (rad + 6.0 + 10.0 * h * ease);
		float tw = smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.55 + 0.3 * h, 1.0, u));
		sp += star4(p - c, sparkle_px * (0.7 + 0.5 * h)) * tw;
	}
	vec3 c = i_tint.rgb * (a + b + sp * 1.1);
	if (max(c.r, max(c.g, c.b)) < 0.0015) {
		discard;
	}
	COLOR = vec4(max(c + tpdf(FRAGCOORD.xy), vec3(0.0)), 1.0);
}
