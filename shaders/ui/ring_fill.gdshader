// Arc with round caps (Art Bible §4.18): the dock Basket fill ring (count / 24, gold on gold_tint,
// 3 dp) and the long-press radial fill. Starts at 12 o'clock and runs clockwise. Dithered.
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/inc/finish.gdshaderinc"

uniform vec2 u_size = vec2(120.0, 120.0);
uniform float u_progress : hint_range(0.0, 1.0) = 0.0;
uniform float u_stroke = 9.0;                         // px (3 dp)
uniform vec4 u_color : source_color = vec4(1.0, 0.796, 0.341, 1.0);   // gold
uniform vec4 u_track : source_color = vec4(1.0, 0.953, 0.847, 0.0);   // gold_tint (alpha 0 = none)

varying vec2 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec2 c = u_size * 0.5;
	vec2 p = v_local - c;
	float r = min(c.x, c.y) - u_stroke * 0.5 - 1.0;
	float hw = u_stroke * 0.5;
	float ring = abs(length(p) - r) - hw;
	// angle from 12 o'clock, clockwise, 0..1
	float ang = fract(atan(p.x, -p.y) / TAU + 1.0);
	float span = clamp(u_progress, 0.0, 1.0);
	// distance to the arc: inside the angular span use the ring distance, else the nearer cap
	vec2 a0 = vec2(0.0, -r);
	float e = TAU * span;
	vec2 a1 = vec2(sin(e), -cos(e)) * r;
	float caps = min(length(p - a0), length(p - a1)) - hw;
	float arc = ang <= span ? ring : caps;
	arc = span <= 0.0 ? 1e4 : arc;
	float fw = max(fwidth(length(p)), 1e-3);
	float arc_cov = clamp(0.5 - arc / fw, 0.0, 1.0);
	float track_cov = clamp(0.5 - ring / fw, 0.0, 1.0) * u_track.a;
	vec3 col = mix(u_track.rgb, u_color.rgb, arc_cov);
	float a = max(arc_cov * u_color.a, track_cov);
	col = finish(col, v_local / PX_PER_DP, FRAGCOORD.xy, GRAIN_GLASS);
	COLOR = vec4(col, a * COLOR.a);
}
