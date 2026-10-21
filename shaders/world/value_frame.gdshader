// Value frame (round-3 directive 2, Art Bible §1.2 "darkest are the L5 corners", §2.5 focal): a
// multiply pass over the near ground band and the side wedges of the hollow, drawn after every
// object of the Play layer (creatures, beds, décor included) and before the additive air (shafts,
// fireflies). It sinks the foreground and the corners toward a COOL, darker tint of the shadow
// token and leaves the focal ellipse around the sun stone untouched, so at a squint the eye lands
// on the warm, bright stone + creatures. Night keeps half the strength (it is already dark).
// Mesh contract (ValueFrame): VERTEX = design px of the Ground layer.
shader_type canvas_item;
render_mode blend_mul, unshaded;

#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/lamps.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

// Focal ellipse centre and radii (design px): no darkening inside 0.75 of it (Art Bible §2.5).
uniform vec2 focal_centre = vec2(540.0, 1150.0);
uniform vec2 focal_radii = vec2(500.0, 420.0);
uniform vec2 focal_ramp = vec2(0.7, 1.55);
// Strength away from the focal (corners, sides) and in the near band below the brook.
uniform float frame_k = 0.42;
uniform float bottom_k = 0.10;
uniform vec2 bottom_band = vec2(1480.0, 1960.0);
uniform float max_k = 0.5;
// The frame starts below the crest (the mesh's top edge, ValueFrame.SIDE_Y.x): no visible seam.
uniform vec2 top_fade = vec2(760.0, 960.0);
// The multiply target: the shadow token lifted (x lift) and pulled toward a neutral grey.
uniform float shade_lift = 1.6;
uniform float shade_grey = 0.62;
uniform float shade_grey_mix = 0.5;
uniform float night_k = 0.5;
uniform float rain_k = 0.75;
// Lamp pools stay lit: the frame lets go inside them (night focal system, Art Bible §8.3).
uniform float lamp_release_k = 3.0;

varying vec2 v_design;

void vertex() {
	v_design = VERTEX;
}

float frame_amount(vec2 p) {
	float d = length((p - focal_centre) / focal_radii);
	float a = frame_k * smoothstep(focal_ramp.x, focal_ramp.y, d)
			+ bottom_k * smoothstep(bottom_band.x, bottom_band.y, p.y);
	a *= smoothstep(top_fade.x, top_fade.y, p.y);
	return clamp(a, 0.0, max_k) * (1.0 - night_k * g_lights) * mix(1.0, rain_k, g_rain);
}

void fragment() {
	float a = frame_amount(v_design);
	if (g_lights > 0.001) {
		a *= 1.0 - clamp(lamp_weight(v_design) * lamp_release_k, 0.0, 1.0);
	}
	vec3 target = mix(vec3(shade_grey), clamp(g_shadow.rgb * shade_lift, 0.0, 1.0), shade_grey_mix);
	vec3 m = mix(vec3(1.0), target, a);
	COLOR = vec4(m + tpdf(FRAGCOORD.xy), 1.0);
}
