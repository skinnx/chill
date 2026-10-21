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

// Focal ellipse centre and radii (design px; ValueFrame sets them): no darkening inside
// focal_ramp.x of it (Art Bible §2.5). Round 4: a tighter ellipse and a longer ramp, so the open
// meadow steps down gently and the near band + bottom corners sink clearly darker and cooler.
uniform vec2 focal_centre = vec2(540.0, 1150.0);
uniform vec2 focal_radii = vec2(380.0, 300.0);
uniform vec2 focal_ramp = vec2(0.72, 2.1);
// Strength away from the focal (mid meadow, sides, corners) and in the near band below the brook.
uniform float frame_k = 0.50;
uniform float bottom_k = 0.22;
uniform vec2 bottom_band = vec2(1460.0, 1980.0);
// Corner vignette (foliage shadow from the L5 frame): extra weight toward the bottom corners.
uniform float corner_k = 0.22;
uniform vec2 corner_radii = vec2(640.0, 820.0);
uniform vec2 corner_ramp = vec2(0.75, 1.3);
uniform float max_k = 0.60;
// The frame starts below the crest (the mesh's top edge, ValueFrame.TOP_Y): no visible seam.
uniform vec2 top_fade = vec2(760.0, 980.0);
// The multiply target: the shadow token lifted (x lift) and pulled toward a neutral grey.
uniform float shade_lift = 1.45;
uniform float shade_grey = 0.56;
uniform float shade_grey_mix = 0.62;
uniform float night_k = 0.72;
// Low-sun phases already carry long shadows and contre-jour shade: the frame relaxes with backlight
// (keeps golden / dawn inside the V2 calm budget, ADR 0001 #1).
uniform float backlight_relief_k = 0.52;
uniform float rain_k = 0.8;
// Lamp pools stay lit: the frame lets go inside them (night focal system, Art Bible §8.3).
uniform float lamp_release_k = 3.0;

varying vec2 v_design;

void vertex() {
	v_design = VERTEX;
}

float frame_amount(vec2 p) {
	float d = length((p - focal_centre) / focal_radii);
	float r = smoothstep(focal_ramp.x, focal_ramp.y, d);
	vec2 cq = vec2(abs(p.x - focal_centre.x), p.y - focal_centre.y) / corner_radii;
	float corner = smoothstep(corner_ramp.x, corner_ramp.y, length(cq)) * step(focal_centre.y, p.y);
	float a = frame_k * r * (2.0 - r) + bottom_k * smoothstep(bottom_band.x, bottom_band.y, p.y) + corner_k * corner;
	a *= smoothstep(top_fade.x, top_fade.y, p.y);
	return clamp(a, 0.0, max_k) * (1.0 - night_k * g_lights) * (1.0 - backlight_relief_k * g_backlight) * mix(1.0, rain_k, g_rain);
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
