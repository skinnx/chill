// Signed distance helpers (Art Bible §4.2). Distances are in the caller's units; d_px() turns a
// field into screen px through its gradient so AA edges stay 1 px wide at any scale.
#ifndef MM_SDF_INC
#define MM_SDF_INC

mat2 rot2(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

// Polynomial smooth minimum (k = blend radius).
float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// Superellipse |x/rx|^n + |y/ry|^n = 1 (approximate distance, scaled by the short radius).
float sd_squircle(vec2 p, vec2 r, float n) {
	vec2 q = abs(p) / r;
	float m = pow(pow(q.x, n) + pow(q.y, n), 1.0 / n);
	return (m - 1.0) * min(r.x, r.y);
}

// Ellipse (approximate, good near the boundary).
float sd_ellipse(vec2 p, vec2 r) {
	float k0 = length(p / r);
	float k1 = length(p / (r * r));
	return k1 > 1e-6 ? k0 * (k0 - 1.0) / k1 : -min(r.x, r.y);
}

float sd_capsule(vec2 p, vec2 a, vec2 b, float r) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

// Vesica (leaf / lens) along y: half length `len`, half width `w`.
float sd_vesica(vec2 p, float len, float w) {
	p = abs(p);
	float r = (len * len + w * w) / (2.0 * w);
	float b = r - w;
	return ((p.y - len) * b > p.x * len) ? length(p - vec2(0.0, len)) : length(p - vec2(-b, 0.0)) - r;
}

// Arc of radius r and half thickness th between angles a0 and a1 (radians, a0 < a1).
float sd_arc(vec2 p, float r, float th, float a0, float a1) {
	float a = atan(p.y, p.x);
	float mid = 0.5 * (a0 + a1);
	float half_span = 0.5 * (a1 - a0);
	float da = abs(mod(a - mid + PI, TAU) - PI);
	if (da <= half_span) {
		return abs(length(p) - r) - th;
	}
	vec2 e0 = r * vec2(cos(a0), sin(a0));
	vec2 e1 = r * vec2(cos(a1), sin(a1));
	return min(length(p - e0), length(p - e1)) - th;
}

// Rounded isosceles triangle, apex up: height h, base half-width b, rounding rr.
float sd_round_tri(vec2 p, float h, float b, float rr) {
	p.x = abs(p.x);
	vec2 q = vec2(b, h);
	vec2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
	vec2 c = p - q * vec2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
	float s = -sign(q.y);
	vec2 d = min(vec2(dot(a, a), s * (p.x * q.y - p.y * q.x)), vec2(dot(c, c), s * (p.y - q.y)));
	return -sqrt(d.x) * sign(d.y) - rr;
}

// Distance field -> screen px via its gradient (1 px AA at any zoom).
float d_px(float f) {
	return f / max(length(vec2(dFdx(f), dFdy(f))), 1e-6);
}

#endif
