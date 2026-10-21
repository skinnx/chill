// Meadow grass tufts (Art Bible §4.6, §6.4): MultiMesh instances of a 3-blade tuft, coloured as
// terrain (grass_root -> grass_tip), swaying at k/600 Hz with the travelling gust (phase from the
// tuft's world x, so fronts visibly cross the meadow every ~9.7 s), cloud shadows, lamp pools.
// Mesh contract (GrassField): VERTEX px from the root, UV.x 0..1 across a blade, UV.y 1 root -> 0 tip.
// INSTANCE_CUSTOM: x sway k (absolute), y height px, z phase rad, w lean (px at the tip).
// Instance COLOR: r tint -1..1 mapped to 0..1, g light (0 shade-side .. 1 lit), b blade alpha mul.
shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/lamps.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

uniform vec4 grass_tip : source_color = vec4(0.624, 0.8, 0.616, 1.0);
uniform vec4 grass_root : source_color = vec4(0.286, 0.576, 0.471, 1.0);
// The ground under the tuft (same slots as the meadow): roots grow out of it instead of
// speckling the meadow with dark marks [J].
uniform vec4 ground_back_lit : source_color = vec4(0.522, 0.733, 0.553, 1.0);
uniform vec4 ground_front_lit : source_color = vec4(0.447, 0.686, 0.490, 1.0);
uniform float root_ground_mix = 0.5;
uniform float amp_px = 6.0;
uniform float tint_l = 0.03;

varying vec4 v_inst;
varying vec2 v_canvas;
varying float v_h;

void vertex() {
	float h = 1.0 - UV.y;
	v_h = h;
	v_inst = COLOR;
	vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - g_world_offset;
	float k = INSTANCE_CUSTOM.x;
	float ph = INSTANCE_CUSTOM.z;
	float sway = sin(TAU * k / LOOP_S * g_time + ph) + 0.35 * sin(TAU * k * 2.13 / LOOP_S * g_time + ph + 1.7);
	float g = gust(world.x);
	// Lean in px at the tip (authored), plus sway; both grow with h^2 so roots stay planted.
	VERTEX.x += (INSTANCE_CUSTOM.w + (sway * amp_px * (1.0 + GUST_AMP * g) + g * amp_px * 0.8) * wind_k() * g_motion) * h * h;
	v_canvas = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	COLOR = vec4(1.0);
}

void fragment() {
	float d = abs(UV.x * 2.0 - 1.0);
	float fw = max(fwidth(d) * 1.2, 0.02);
	float a = (1.0 - smoothstep(1.0 - fw, 1.0, d)) * v_inst.b;
	if (a < 0.003) {
		discard;
	}
	float h = v_h;
	vec2 p_design = v_canvas - g_world_offset;
	vec3 ground = mix(ground_back_lit.rgb, ground_front_lit.rgb, smoothstep(760.0, 1500.0, p_design.y));
	vec3 root = mix(grass_root.rgb, ground, root_ground_mix);
	vec3 c = mix(root, grass_tip.rgb, smoothstep(0.0, 0.8, h));
	c *= 1.0 + (v_inst.r * 2.0 - 1.0) * tint_l * 3.0;
	// One side of each blade is a touch darker: soft volume without a texture.
	c *= mix(0.92, 1.04, mix(v_inst.g, 1.0 - UV.x, 0.5));
	if (g_cloud_shadow > 0.001) {
		c = mix(c, c * g_shadow.rgb * SHADE_K, cloud_shadow(p_design));
	}
	c += g_key.rgb * g_rim * g_backlight * 0.22 * h * h;
	if (g_lights > 0.001) {
		c = apply_lamp(c, lamp_weight(p_design) * 0.6);
	}
	COLOR = vec4(finish(c, p_design / PX_PER_DP, FRAGCOORD.xy, GRAIN_TERRAIN), a);
}
