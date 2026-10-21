// Ambient particle process (Art Bible §4.15, §7; synthesis D9): seeded sine wander, wind drift,
// age-based fade-in >= 300 ms and fade-out over the last 20 % of life (no pop-in, V5); no
// turbulence, trails or sub-emitters. One shader, one material per system, `kind` picks the motion.
// Positions are local to the emitter (local_coords = true) = design px of the 1080x1920 frame.
// Output to particle_draw.gdshader: COLOR.a = alpha, CUSTOM = (phase 0..1, age 0..1, size px, k).
shader_type particles;
render_mode disable_velocity, disable_force;

#include "res://shaders/inc/globals.gdshaderinc"

const int KIND_DUST = 0;
const int KIND_POLLEN = 1;
const int KIND_SEEDS = 2;
const int KIND_PETALS = 3;
const int KIND_FIREFLIES = 4;
const int KIND_RAIN = 5;
const int KIND_SPLASH = 6;

uniform int kind = 0;
// Spawn box (x, y, w, h) in design px.
uniform vec4 emit_rect = vec4(0.0, 700.0, 1080.0, 800.0);
// Wander speed range px/s, base drift px/s (x is scaled by the wind), sizes px, alpha range.
uniform vec2 speed = vec2(6.0, 24.0);
uniform vec2 drift = vec2(0.0, 0.0);
uniform vec2 size_px = vec2(3.0, 7.5);
uniform vec2 alpha = vec2(0.15, 0.4);
uniform vec2 wander_hz = vec2(0.2, 0.5);
uniform float fade_in_s = 0.4;
uniform float spin_deg_s = 0.0;
uniform float tilt_deg = 8.0;
// Rain streak size (w, h) px; splash squash (perspective).
uniform vec2 streak_px = vec2(3.0, 36.0);
uniform float squash = 0.35;
// Firefly lantern / flower bias: points in design px, fraction of spawns near them.
uniform vec4 u_points[8];
uniform int u_point_count = 0;
uniform float point_bias = 0.0;
uniform float point_radius = 120.0;
// Firefly pulse k range (period 600/k s), carried to the draw shader.
uniform vec2 k_range = vec2(86.0, 100.0);
// Soft bound: particles drifting out of the box are steered back (fireflies, dust).
uniform float steer = 0.0;

float rnd(uint n, uint salt) {
	uint s = n * 747796405u + salt * 2891336453u + 1442695041u;
	s = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	s = (s >> 22u) ^ s;
	return float(s) / 4294967295.0;
}

mat4 place(vec2 pos, float rot, vec2 scale) {
	float c = cos(rot);
	float s = sin(rot);
	return mat4(vec4(c * scale.x, s * scale.x, 0.0, 0.0), vec4(-s * scale.y, c * scale.y, 0.0, 0.0),
			vec4(0.0, 0.0, 1.0, 0.0), vec4(pos, 0.0, 1.0));
}

float wind_k() {
	return (0.5 + g_wind) / 0.85;
}

void start() {
	uint n = NUMBER + RANDOM_SEED * 7919u;
	vec2 pos = emit_rect.xy + vec2(rnd(n, 1u), rnd(n, 2u)) * emit_rect.zw;
	if (u_point_count > 0 && rnd(n, 3u) < point_bias) {
		int i = int(floor(rnd(n, 4u) * float(u_point_count))) % u_point_count;
		float a = rnd(n, 5u) * TAU;
		pos = u_points[i].xy + vec2(cos(a), sin(a) * 0.6) * sqrt(rnd(n, 6u)) * point_radius;
	}
	float size = mix(size_px.x, size_px.y, rnd(n, 7u));
	float k = floor(mix(k_range.x, k_range.y + 1.0, rnd(n, 8u)));
	CUSTOM = vec4(rnd(n, 9u), 0.0, size, k);
	float rot = kind == KIND_RAIN ? radians(tilt_deg) * clamp(wind_k(), 0.5, 2.0) : rnd(n, 10u) * TAU;
	TRANSFORM = place(pos, rot, vec2(size));
	VELOCITY = vec3(0.0);
	COLOR = vec4(1.0, 1.0, 1.0, 0.0);
}

void process() {
	uint n = NUMBER + RANDOM_SEED * 7919u;
	CUSTOM.y = min(CUSTOM.y + DELTA / LIFETIME, 1.0);
	float age = CUSTOM.y;
	float t = age * LIFETIME;
	vec2 pos = TRANSFORM[3].xy;
	float size = CUSTOM.z;
	float sp = mix(speed.x, speed.y, rnd(n, 11u));
	float f1 = mix(wander_hz.x, wander_hz.y, rnd(n, 12u));
	float f2 = mix(wander_hz.x, wander_hz.y, rnd(n, 13u)) * 1.37;
	float p1 = rnd(n, 14u) * TAU;
	float p2 = rnd(n, 15u) * TAU;
	float wk = wind_k();
	vec2 vel = vec2(drift.x * wk, drift.y);
	float rot = atan(TRANSFORM[0].y, TRANSFORM[0].x);
	vec2 scale = vec2(size);
	if (kind == KIND_RAIN) {
		float fall = sp;
		float a = radians(tilt_deg) * clamp(wk, 0.5, 2.0);
		vel = vec2(sin(a), cos(a)) * fall;
		rot = -a;
		scale = streak_px;
	} else if (kind == KIND_SPLASH) {
		vel = vec2(0.0);
		rot = 0.0;
		scale = vec2(size, size * squash);
	} else if (kind == KIND_PETALS) {
		vel = vec2(drift.x * wk + sin(TAU * f1 * t + p1) * sp * 0.6, mix(60.0, 120.0, rnd(n, 16u)) * 0.5 + drift.y);
		rot += radians(mix(30.0, 90.0, rnd(n, 17u))) * DELTA * (rnd(n, 18u) < 0.5 ? -1.0 : 1.0);
		scale = vec2(size * (0.35 + 0.65 * abs(cos(TAU * f2 * t + p2))), size * 0.62);
	} else if (kind == KIND_SEEDS) {
		vel = vec2(drift.x * wk * mix(0.7, 1.2, rnd(n, 19u)), drift.y + sin(TAU * 0.2 * t + p1) * 8.0);
		rot = sin(TAU * f1 * 0.5 * t + p2) * radians(spin_deg_s);
	} else if (kind == KIND_POLLEN) {
		vel += vec2(sin(TAU * f1 * t + p1) * sp * 0.25, cos(TAU * 0.2 * t + p2) * 10.0);
	} else {
		vel += vec2(sin(TAU * f1 * t + p1), cos(TAU * f2 * t + p2) * 0.8) * sp;
	}
	if (steer > 0.0) {
		vec2 c = emit_rect.xy + emit_rect.zw * 0.5;
		vec2 h = emit_rect.zw * 0.5;
		vec2 out_d = max(abs(pos - c) - h, vec2(0.0)) * sign(c - pos);
		vel += out_d * steer;
	}
	pos += vel * DELTA;
	float fade = smoothstep(0.0, fade_in_s / LIFETIME, age) * (1.0 - smoothstep(0.8, 1.0, age));
	COLOR.a = mix(alpha.x, alpha.y, rnd(n, 20u)) * fade;
	TRANSFORM = place(pos, rot, scale);
	if (age >= 1.0) {
		ACTIVE = false;
	}
}
