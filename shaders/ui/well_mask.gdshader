// Bake-time corner mask of a portrait / preview well (round 5): drawn last over the cell on the
// transparent bake page with a multiply blend, it scales colour and alpha by the rounded-box
// coverage, so a subject's contact shadow that reaches past the well's rounded corners is cut to
// the same 1 px anti-aliased curve (clip_children wrote opaque black corners on the transparent
// page). Only ever used inside a SnapshotBaker page: it costs nothing once the cell is a texture.
shader_type canvas_item;
render_mode unshaded, blend_mul;

uniform vec2 u_size = vec2(252.0, 252.0);
uniform float u_radius = 48.0;

varying vec2 v_local;

void vertex() {
	v_local = VERTEX;
}

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 half_size = u_size * 0.5;
	float r = min(u_radius, min(half_size.x, half_size.y));
	float cov = clamp(0.5 - sd_round_box(v_local - half_size, half_size, r), 0.0, 1.0);
	COLOR = vec4(vec3(cov), cov);
}
