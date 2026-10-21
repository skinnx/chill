// Props, décor, gifts, dressing (Art Bible §4.9): lossless SVG tone masks (R lit, G shade, B detail,
// black = colour-line tone, alpha = coverage) recoloured per time of day from material instance
// uniforms, then lit like every object: ambient multiply, tinted AO at the base, key on top, a
// rim toward the light, cloud shadows, warm lamp fill, optional night emission and sway.
// One shared ShaderMaterial for every prop sprite (instance uniforms keep batching).
shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/lamps.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

// palettes.json materials: rgb = lit / shade / detail; i_detail.a = detail emission x g_lights.
instance uniform vec4 i_lit : source_color = vec4(0.863, 0.827, 0.784, 0.0);
instance uniform vec4 i_shade : source_color = vec4(0.718, 0.675, 0.651, 0.0);
instance uniform vec4 i_detail : source_color = vec4(0.914, 0.875, 0.788, 0.0);
// x amp px at the top, y k (k/600 Hz), z pivot UV.y (sways above it), w phase.
instance uniform vec4 i_sway = vec4(0.0, 120.0, 1.0, 0.0);
// x tap pulse 0..1 (+tint), y squash (1 = rest), z rim on (1) / off (0), w ground cover 0..1
// (moss, clover, ferns sit in the grass: they take the meadow's shade so they never read as stickers).
instance uniform vec4 i_fx = vec4(0.0, 1.0, 1.0, 0.0);
// The sprite's atlas region in UV (x, y, w, h): local UV = (UV - xy) / zw.
instance uniform vec4 i_region = vec4(0.0, 0.0, 1.0, 1.0);
// x focal 0..1 (the sun stone: its lit top plane catches every key light, Art Bible §2.5, §6.5).
instance uniform vec4 i_focal = vec4(0.0);

uniform float rim_px = 3.5;
uniform float rim_k = 0.6;
uniform float line_k = 0.72;
uniform float lamp_fill_k = 1.1;
uniform float tap_tint = 0.06;
uniform float backlight_k = 0.38;
uniform float ground_k = 0.18;
uniform float ground_backlight_k = 0.3;
uniform float focal_k = 0.08;
uniform float focal_front_k = 0.62;
// Round 4: the focal's front face sinks toward a near-neutral cool grey (not the teal of the raw day
// shadow token), so the stone reads as warm stone with a lit top and a shaded front.
uniform vec3 focal_front_tint = vec3(0.66, 0.68, 0.76);
uniform float focal_back_k = 0.12;
// Round 5 (QA r4: the stone top was the value of the haze-washed ground): at golden the focal's lit
// top warms toward a sun-warmed stone (#DCB998) and lifts, with a stronger key rim on its sun edge.
uniform vec3 focal_golden = vec3(0.863, 0.725, 0.596);
uniform float focal_golden_k = 0.8;
uniform float focal_golden_lift = 1.12;
uniform float focal_rim_boost = 1.8;

varying vec2 v_canvas;
varying vec2 v_size;
varying vec2 v_luv;

void vertex() {
	v_size = i_region.zw / TEXTURE_PIXEL_SIZE;
	vec2 luv = (UV - i_region.xy) / max(i_region.zw, vec2(1e-6));
	v_luv = luv;
	// Squash about the base (tap 0.94), volume-preserving widen.
	float sq = i_fx.y;
	VERTEX.y += (1.0 - luv.y) * v_size.y * (1.0 - sq);
	VERTEX.x += (luv.x - 0.5) * v_size.x * (1.0 / max(sq, 0.5) - 1.0);
	// Sway: shear above the pivot, k/600 Hz with the travelling gust.
	if (i_sway.x > 0.0) {
		float h = clamp((i_sway.z - luv.y) / max(i_sway.z, 0.001), 0.0, 1.0);
		vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - g_world_offset;
		float s = sin(TAU * i_sway.y / LOOP_S * g_time + i_sway.w) + 0.35 * sin(TAU * i_sway.y * 2.13 / LOOP_S * g_time + 1.7 + i_sway.w);
		VERTEX.x += s * i_sway.x * wind_k() * (1.0 + GUST_AMP * gust_at(world)) * g_motion * h * h;
	}
	v_canvas = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 m = texture(TEXTURE, UV);
	if (m.a < 0.002) {
		discard;
	}
	float o = clamp(1.0 - (m.r + m.g + m.b), 0.0, 1.0);
	vec3 alb = m.r * i_lit.rgb + m.g * i_shade.rgb + m.b * i_detail.rgb + o * i_shade.rgb * line_k;
	vec3 c = light_object(alb, 1.0 - v_luv.y, smoothstep(0.80, 1.0, v_luv.y));
	// Contre-jour: with the light behind (golden, dusk) the viewer sees the shaded faces; tops
	// stay lit, sides and fronts sink toward the tinted shadow (Art Bible §8.1) [J].
	c = mix(c, c * shadow_tint() * SHADE_K, backlight_k * g_backlight * (0.45 + 0.55 * smoothstep(0.1, 0.9, v_luv.y))
			* (1.0 - 0.7 * i_focal.x * m.r));
	// The focal's lit top plane: a warm key wash (strongest at golden), a cooler front face.
	c += (g_key.rgb * 0.75 + alb * 0.25) * i_focal.x * m.r * (focal_k + focal_back_k * g_backlight) * (1.0 - 0.6 * g_lights);
	// Round 3 (QA r2: the stone barely separated from the meadow): the focal's front / shade faces
	// sink toward the tinted shadow, so its lit top reads as the highest local contrast.
	float fg_w = i_focal.x * m.r * g_backlight * (1.0 - g_lights);
	vec3 warm_top = focal_golden / wl_luma(focal_golden) * max(wl_luma(c) * focal_golden_lift, wl_luma(focal_golden));
	c = mix(c, min(warm_top, vec3(1.0)), fg_w * focal_golden_k);
	vec3 front_t = mix(focal_front_tint, shadow_tint() * SHADE_K, 0.35);
	c = mix(c, c * front_t, i_focal.x * clamp(m.g + 0.5 * smoothstep(0.45, 0.9, v_luv.y), 0.0, 1.0) * focal_front_k);
	c = mix(c, c * shadow_tint() * SHADE_K, i_fx.w * (ground_k + ground_backlight_k * g_backlight));
	// Rim: inside the shape, with empty space toward the light (one extra, slightly blurred read).
	if (i_fx.z > 0.5) {
		vec2 kd = key_dir(v_canvas);
		float ahead = textureLod(TEXTURE, UV + kd * rim_px * TEXTURE_PIXEL_SIZE, 0.75).a;
		float rim = m.a * (1.0 - ahead);
		c += g_key.rgb * g_rim * rim_k * rim * (1.0 - o) * (1.0 + focal_rim_boost * i_focal.x * g_backlight);
	}
	vec2 p_design = v_canvas - g_world_offset;
	// Ground cover pieces (moss, clover, ferns) take the meadow's golden grade (round 5).
	c = mix(c, golden_grade(c, p_design, 0.0), i_fx.w);
	if (g_cloud_shadow > 0.001) {
		c = mix(c, c * shadow_tint() * SHADE_K, cloud_shadow(p_design));
	}
	if (g_lights > 0.001) {
		c += alb * g_accent.rgb * lamp_soft(lamp_weight(p_design)) * lamp_fill_k;
	}
	// Night emission (lantern core, glow mushrooms): the detail tone glows, the rest warms.
	float em = i_detail.a * g_lights;
	c = mix(c, i_detail.rgb * 1.1, em * (0.55 + 0.45 * m.b));
	c += vec3(tap_tint) * i_fx.x;
	COLOR = vec4(finish(c, v_luv * v_size / PX_PER_DP, FRAGCOORD.xy, GRAIN_OBJECT), m.a * COLOR.a);
}
