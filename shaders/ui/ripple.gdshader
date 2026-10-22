// Touch ripple (Art Bible §10.3 touch-down feedback, motion_tokens ui.ring): a soft disc that grows
// from the touch point over ui.ring.ms and fades from ui.ring.alpha[0] to [1], clipped to the
// control's rounded shape (pill, card or round plate) so it never spills past the control. A thin
// bright crest rides the expanding edge (the "splash" read in a still). Drawn only while a press
// is in flight (no idle cost). Dithered like every gradient.
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/inc/finish.gdshaderinc"

uniform vec2 u_size = vec2(300.0, 132.0);      // the clip shape, px
uniform float u_radius = 66.0;                 // its corner radius, px
uniform vec2 u_center = vec2(150.0, 66.0);     // touch point, px
uniform float u_progress : hint_range(0.0, 1.0) = 0.0;
uniform float u_reach = 300.0;                 // final disc radius, px
uniform vec4 u_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float u_alpha = 0.35;                  // ui.ring.alpha[0] (fades to 0)

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
	float d = sd_round_box(v_local - half_size, half_size, r);
	float clip = clamp(0.5 - d, 0.0, 1.0);
	// ease-out growth: fast at touch-down, settling as it fills
	float t = clamp(u_progress, 0.0, 1.0);
	float grow = 1.0 - (1.0 - t) * (1.0 - t);
	float rad = mix(u_reach * 0.18, u_reach, grow);
	float dist = length(v_local - u_center);
	float soft = max(rad * 0.18, 3.0);
	float disc = 1.0 - smoothstep(rad - soft, rad, dist);
	float crest = (1.0 - smoothstep(0.0, soft, abs(dist - rad + soft * 0.6))) * 0.6;
	float fade = u_alpha * (1.0 - smoothstep(0.35, 1.0, t));
	float a = clamp(disc * 0.7 + crest, 0.0, 1.0) * fade * clip;
	vec3 c = finish(u_color.rgb, v_local / PX_PER_DP, FRAGCOORD.xy, GRAIN_GLASS);
	COLOR = vec4(c, a * COLOR.a);
}
