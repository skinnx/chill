// L5 foreground frame (Art Bible §4.16; QA round 1): dark, out-of-focus corner foliage framing the
// hollow like an intentional depth-of-field vignette. The tone masks are blurred inside the SVG
// (props_svg.py FG_BLUR), so the texture is sampled at mip 0: smooth, never blocky. Colour is
// pulled strongly toward g_fg (the darkest value of the frame, Art Bible §1.2 "darkest are the L5
// corners"), keeps a little of its material through the ambient multiply, and catches a soft
// backlit glow on the side facing the light. Gentle shear sway (k from flower_sway); grain + dither.
shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

instance uniform vec4 i_lit : source_color = vec4(0.651, 0.8, 0.584, 0.0);
instance uniform vec4 i_shade : source_color = vec4(0.439, 0.659, 0.545, 0.0);
instance uniform vec4 i_detail : source_color = vec4(0.824, 0.902, 0.761, 0.0);
// x amp px, y k, z pivot UV.y (sways above it; 0 = hangs: sways below), w phase.
instance uniform vec4 i_sway = vec4(6.0, 120.0, 1.0, 0.0);
instance uniform vec4 i_region = vec4(0.0, 0.0, 1.0, 1.0);

uniform float fg_mix = 0.84;
// The frame is the darkest value of the picture (Art Bible §1.2, §2.5 value plan).
uniform float fg_dark = 0.60;
uniform float rim_k = 0.85;
uniform float rim_px = 12.0;
uniform float glow_k = 0.10;
uniform float max_alpha = 0.96;
uniform float lavender_k = 0.55;

varying vec2 v_luv;
varying vec2 v_canvas;

void vertex() {
	vec2 luv = (UV - i_region.xy) / max(i_region.zw, vec2(1e-6));
	v_luv = luv;
	float h = i_sway.z > 0.0 ? clamp((i_sway.z - luv.y) / i_sway.z, 0.0, 1.0) : luv.y;
	float s = sin(TAU * i_sway.y / LOOP_S * g_time + i_sway.w) + 0.3 * sin(TAU * i_sway.y * 1.9 / LOOP_S * g_time + i_sway.w);
	VERTEX.x += s * i_sway.x * wind_k() * g_motion * h * h;
	v_canvas = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 m = texture(TEXTURE, UV);
	if (m.a < 0.004) {
		discard;
	}
	// Blurred masks carry premultiplied-looking edges: renormalise the tones by coverage.
	vec3 w = m.rgb / max(m.r + m.g + m.b, 1e-3) * clamp(m.r + m.g + m.b, 0.0, 1.0);
	float o = clamp(1.0 - (w.r + w.g + w.b), 0.0, 1.0);
	vec3 alb = w.r * i_lit.rgb + w.g * i_shade.rgb + w.b * i_detail.rgb + o * i_shade.rgb * 0.72;
	vec3 c = mix(alb * g_ambient.rgb, g_fg.rgb, fg_mix);
	// Round 5: with the light behind, the out-of-focus frame leans lavender (Director: shadows and
	// vignette cool lavender, never brown-grey): the shadow token at the frame's own luminance.
	vec3 lav = mix(g_shadow.rgb, g_sky_mid.rgb, 0.25);
	c = mix(c, lav / max(wl_luma(lav), 1e-3) * wl_luma(c), lavender_k * g_backlight * (1.0 - g_lights));
	// Lit tone reads a little lighter (leaf volume survives the blur).
	c *= (0.92 + 0.16 * w.r) * fg_dark;
	vec2 kd = key_dir(v_canvas);
	float ahead = texture(TEXTURE, UV + kd * rim_px * TEXTURE_PIXEL_SIZE).a;
	float rim = clamp(m.a - ahead, 0.0, 1.0);
	c += g_key.rgb * (g_rim * rim_k * rim + g_backlight * glow_k * w.r * m.a);
	COLOR = vec4(finish(c, v_luv / TEXTURE_PIXEL_SIZE * i_region.zw / PX_PER_DP, FRAGCOORD.xy, GRAIN_OBJECT), m.a * max_alpha);
}
