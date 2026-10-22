// Additive soft halo (Art Bible §4.13): lantern heads, glow mushrooms, ready buds, the debut
// spotlight. c = colour x alpha / (1 + (r / r0)^2), faded to 0 before the quad edge (no visible
// quad), breathing +-5 % at k 181, optionally x g_lights (night-only uses), then TPDF dither.
// Quad contract (HaloSprite): local VERTEX px with the halo centre at the origin.
shader_type canvas_item;
render_mode blend_add, unshaded;

#include "res://shaders/inc/globals.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

// rgb colour (ignored when i_halo.w >= 2: uses g_accent), a = strength.
instance uniform vec4 i_color : source_color = vec4(1.0, 0.79, 0.47, 0.5);
// x r0 px, y quad radius px, z breath k (0 = steady), w flags: 1 = x g_lights, 2 = accent colour, 3 = both.
instance uniform vec4 i_halo = vec4(10.0, 60.0, 181.0, 3.0);
instance uniform float i_phase = 0.0;

const float BREATH_AMP = 0.05;

varying vec2 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float r = length(v_local);
	float r0 = max(i_halo.x, 0.5);
	float rq = max(i_halo.y, 1.0);
	float flags = i_halo.w;
	vec3 col = flags >= 2.0 ? g_accent.rgb : i_color.rgb;
	float k = mod(flags, 2.0) >= 1.0 ? g_lights : 1.0;
	float breath = i_halo.z > 0.0 ? 1.0 + BREATH_AMP * sin(TAU * i_halo.z / 600.0 * g_time + i_phase) : 1.0;
	float f = (1.0 / (1.0 + (r / r0) * (r / r0))) * (1.0 - smoothstep(0.7, 1.0, r / rq));
	vec3 c = col * i_color.a * f * breath * k;
	if (max(c.r, max(c.g, c.b)) < 0.0015) {
		discard;
	}
	COLOR = vec4(max(c + tpdf(FRAGCOORD.xy), vec3(0.0)), 1.0);
}
