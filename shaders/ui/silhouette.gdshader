// "Not met yet" friend silhouette (Art Bible §9.4 Album: ink @ 0.10 with fuzz and no face; never a
// lock or a question mark, §11.4). A soft squircle body with two rounded ear nubs and a fibre
// fringe from value noise, so it reads as a felted friend still to come. Dithered.
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/inc/finish.gdshaderinc"
#include "res://shaders/inc/sdf.gdshaderinc"

uniform vec2 u_size = vec2(288.0, 240.0);
uniform vec4 u_ink : source_color = vec4(0.165, 0.157, 0.22, 0.1);
uniform float u_seed = 0.0;

const float FILL = 0.62;        // body height / well height
const float FEET = 0.86;        // feet line (fraction of the well height)
const float FUZZ_PX = 7.0;

varying vec2 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float h = u_size.y * FILL;
	vec2 feet = vec2(u_size.x * 0.5, u_size.y * FEET);
	vec2 p = (v_local - feet) / h;          // body units, y down, feet at 0
	p.y += 0.5;
	float ear_dx = 0.22 + 0.06 * u_seed;
	float body = sd_squircle(p, vec2(0.52, 0.5), 2.6);
	float ear_l = length((p - vec2(-ear_dx, -0.5)) / vec2(0.85, 1.0)) - 0.14;
	float ear_r = length((p - vec2(ear_dx, -0.5)) / vec2(0.85, 1.0)) - 0.14;
	float d = smin(body, min(ear_l, ear_r), 0.08) * h;
	float ang = atan(p.y, p.x);
	float fringe = (vnoise(vec2(ang * 9.0 + u_seed * 31.0, 0.0)) - 0.5) * FUZZ_PX;
	float cov = clamp(0.5 - (d + fringe) / 1.5, 0.0, 1.0);
	float halo = (1.0 - smoothstep(0.0, FUZZ_PX * 1.6, d)) * 0.35;
	float a = max(cov, halo * step(0.0, d)) * u_ink.a;
	vec3 c = finish(u_ink.rgb, v_local / PX_PER_DP, FRAGCOORD.xy, GRAIN_GLASS);
	COLOR = vec4(c, a * COLOR.a);
}
