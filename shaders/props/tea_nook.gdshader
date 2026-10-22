// Active F2 tea nook (GDD §14, ACTIVE_TEA §10): the felt teapot, jar, cups and cloth on the stump,
// drawn from art/tea/tea_atlas.svg in full colour (COLOR = atlas texel x the teaware tint) and lit
// like every world object (ambient multiply, AO at the base, key on top, lamp fill, cloud shadow,
// grain) so the nook sits in the hollow's light at every time of day. One shared material for the
// nook (TeaNook draws every piece into ONE canvas item, tints as vertex colours: one draw call);
// i_box gives the lighting its height frame; i_fx.x lets the moon kettle glow at night.
shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/lamps.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

// The nook's local box (x, y top, w, h) in the item's own px: height for the key / AO.
instance uniform vec4 i_box = vec4(-100.0, -150.0, 200.0, 160.0);
// x night glow 0..1 (moon kettle, moon cups), y lighting 0..1, z tap tint.
instance uniform vec4 i_fx = vec4(0.0, 1.0, 0.0, 0.0);

uniform float lamp_fill_k = 1.1;
uniform float tap_tint = 0.06;

varying vec2 v_canvas;
varying vec2 v_luv;
varying vec2 v_size;

void vertex() {
	v_size = i_box.zw;
	v_luv = (VERTEX - i_box.xy) / max(i_box.zw, vec2(1.0));
	v_canvas = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 t = COLOR;
	if (t.a < 0.002) {
		discard;
	}
	vec3 alb = t.rgb;
	vec3 c = mix(alb * mix(vec3(1.0), g_ambient.rgb, 0.6), light_object(alb, 1.0 - v_luv.y,
			smoothstep(0.82, 1.0, v_luv.y)), i_fx.y);
	vec2 p_design = v_canvas - g_world_offset;
	if (g_cloud_shadow > 0.001) {
		c = mix(c, c * shadow_tint() * SHADE_K, cloud_shadow(p_design) * i_fx.y);
	}
	if (g_lights > 0.001) {
		c += alb * g_accent.rgb * lamp_soft(lamp_weight(p_design)) * lamp_fill_k;
		c = mix(c, alb * 1.08, i_fx.x * g_lights * 0.6);
	}
	c += vec3(tap_tint) * i_fx.z;
	COLOR = vec4(finish(c, v_luv * v_size / PX_PER_DP, FRAGCOORD.xy, GRAIN_OBJECT), t.a);
}
