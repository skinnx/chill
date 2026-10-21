// Décor stamps (Art Bible §4.9, §6.6-6.8): a whole décor piece (pinwheel stick + blades, lantern
// crook + jar + core) or a whole static group (the cairn, each half of the toadstool ring, the
// stepping stones, the dew drops in the basket) as ONE MeshInstance2D of tone-mask quads from the
// décor atlas, with the prop_tone look: R lit, G shade, B detail, black = colour-line tone, alpha =
// coverage; ambient multiply, tinted AO at each quad's base, key on top, contre-jour, a rim toward
// the light, cloud shadows, warm lamp fill and night emission.
//
// Why a mesh and not Sprite2Ds: every item with instance uniforms takes 16 entries of the 4096-entry
// global/instance uniform buffer (a 64 KB UBO on GLES3 phones too), and a full garden's ~170 décor
// sprites overflowed it in round 3. One stamp = one item; per-quad data rides in the vertices:
//   CUSTOM0 = (local uv x, y, quad size in atlas px x, y)
//   CUSTOM1 = (material LUT column, emission, rim 0/1, group: 0 static, 1 head, 2 + n chime tube n)
// Per item: i_fx = (tap tint 0..1, squash about the foot (1 = rest), emission k, unused);
//           i_head = (pivot x, y in local px, angle rad, unused): group-1 quads turn about it
//           (the pinwheel blades spin, the lantern jar sways on its hook);
//           i_tube0..9 = (pivot x, y, angle, unused): the wind chime is ONE stamp whose tubes swing
//           as separate pendulums about their own hanging points (12 of the 16 instance slots).
// decor_lut rows (texelFetch): 0 r = plush amount (DecorKit.PLUSH_BY_MATERIAL), 1 lit, 2 shade,
// 3 detail (palettes.json materials).
// Round 5 (studio direction: a plush play-set): every felt / minky piece is shaded as a stuffed
// toy, the blurred alpha being its inflation height: a lit slope toward the scene key, a rolled
// edge into the tinted shade, a pillowy core, a soft sheen on the lit rim, a fine directional pile
// (smooth value noise anchored to the piece, faded below 1 screen px per fibre) and fuzzy fibres
// just past the cut edge. Glass and light stay crisp (plush 0).
shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/lamps.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

instance uniform vec4 i_fx = vec4(0.0, 1.0, 1.0, 0.0);
instance uniform vec4 i_head = vec4(0.0);
instance uniform vec4 i_tube0 = vec4(0.0);
instance uniform vec4 i_tube1 = vec4(0.0);
instance uniform vec4 i_tube2 = vec4(0.0);
instance uniform vec4 i_tube3 = vec4(0.0);
instance uniform vec4 i_tube4 = vec4(0.0);
instance uniform vec4 i_tube5 = vec4(0.0);
instance uniform vec4 i_tube6 = vec4(0.0);
instance uniform vec4 i_tube7 = vec4(0.0);
instance uniform vec4 i_tube8 = vec4(0.0);
instance uniform vec4 i_tube9 = vec4(0.0);

uniform sampler2D decor_lut : filter_nearest;
uniform float rim_px = 3.5;
uniform float rim_k = 0.6;
uniform float line_k = 0.72;
uniform float lamp_fill_k = 1.1;
// Touch-down brighten (GDD §8.3 tint): a little stronger than props so a still shows the press.
uniform float tap_tint = 0.10;
uniform float backlight_k = 0.38;
// Round 4 (QA r3 c1: the cairn and edge décor out-shouted the sun stone): pieces outside the focal
// ellipse (spots.json sun_stone, the ValueFrame ellipse) sit back, darker and less saturated.
// The focal pool: the sun stone and its nappers (spots.json sun_stone 0.5, 0.565 of the 1080 x 1920
// frame, lifted to the creatures' bodies), a little tighter than the ValueFrame ellipse.
uniform vec2 focal_centre = vec2(540.0, 1100.0);
uniform vec2 focal_radii = vec2(260.0, 180.0);
uniform vec2 calm_from_to = vec2(0.9, 1.6);
uniform float calm_dark = 0.08;
uniform float calm_desat = 0.16;
// Atlas px per design px (decor_atlas.json "scale").
uniform float atlas_scale = 2.0;
uniform float puff_px = 3.0;
uniform float puff_gain = 2.4;
uniform float puff_light = 0.20;
uniform float puff_roll = 0.24;
uniform float puff_core = 0.06;
uniform float sheen_k = 0.28;
uniform float puff_lod = 2.5;
uniform vec2 pile_freq = vec2(0.6, 1.8);
uniform float pile_k = 0.05;
uniform float fuzz_out_k = 0.5;
uniform float fringe_k = 0.45;

varying vec2 v_canvas;
varying vec2 v_size;
varying vec2 v_luv;
varying flat vec3 v_lit;
varying flat vec3 v_shade;
varying flat vec3 v_detail;
varying flat float v_emit;
varying flat float v_rim;
varying flat float v_plush;

void vertex() {
	int mat_i = int(CUSTOM1.x + 0.5);
	v_lit = texelFetch(decor_lut, ivec2(mat_i, 1), 0).rgb;
	v_shade = texelFetch(decor_lut, ivec2(mat_i, 2), 0).rgb;
	v_detail = texelFetch(decor_lut, ivec2(mat_i, 3), 0).rgb;
	v_emit = clamp(CUSTOM1.y * i_fx.z, 0.0, 1.0);
	v_rim = CUSTOM1.z;
	v_plush = texelFetch(decor_lut, ivec2(mat_i, 0), 0).r;
	v_luv = CUSTOM0.xy;
	v_size = CUSTOM0.zw;
	vec2 v = VERTEX;
	int group = int(CUSTOM1.w + 0.5);
	if (group > 0) {
		vec4 turn = i_head;
		if (group >= 2) {
			vec4 tubes[10] = vec4[](i_tube0, i_tube1, i_tube2, i_tube3, i_tube4, i_tube5, i_tube6, i_tube7,
					i_tube8, i_tube9);
			turn = tubes[clamp(group - 2, 0, 9)];
		}
		vec2 d = v - turn.xy;
		float c = cos(turn.z);
		float s = sin(turn.z);
		v = turn.xy + vec2(c * d.x - s * d.y, s * d.x + c * d.y);
	}
	// Squash about the foot (local y = 0), volume-preserving widen.
	float sq = max(i_fx.y, 0.5);
	v = vec2(v.x / sq, v.y * sq);
	VERTEX = v;
	v_canvas = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 m = texture(TEXTURE, UV);
	vec2 texel = UV / TEXTURE_PIXEL_SIZE;
	float b1 = textureLod(TEXTURE, UV, 1.0).a;
	float fuzz = vnoise(texel * 0.8);
	float cover = max(m.a, max(b1 - m.a, 0.0) * fuzz_out_k * fuzz * v_plush);
	if (cover < 0.004) {
		discard;
	}
	float o = clamp(1.0 - (m.r + m.g + m.b), 0.0, 1.0);
	vec3 alb = m.r * v_lit + m.g * v_shade + m.b * v_detail + o * v_shade * line_k;
	// Plush volume (see the header): slope of the blurred alpha along the key, canvas px -> UV via
	// the exact per-triangle derivatives.
	float facing = 0.0;
	float vol = 1.0;
	float hb = textureLod(TEXTURE, UV, puff_lod).a;
	if (v_plush > 0.001) {
		mat2 jc = mat2(dFdx(v_canvas), dFdy(v_canvas));
		mat2 ju = mat2(dFdx(UV), dFdy(UV));
		vec2 du = abs(determinant(jc)) > 1e-6 ? ju * (inverse(jc) * key_dir(v_canvas)) : vec2(0.0);
		float hp = textureLod(TEXTURE, UV + du * puff_px, puff_lod).a;
		float hm = textureLod(TEXTURE, UV - du * puff_px, puff_lod).a;
		facing = clamp((hm - hp) * puff_gain, -1.0, 1.0) * v_plush;
		vol = mix(1.0, smoothstep(0.05, 0.9, hb), v_plush);
		vec2 pd = v_luv * v_size / atlas_scale;
		float px_per_design = 1.0 / max(length(dFdx(pd)), 1e-4);
		float pile_fade = smoothstep(0.6, 1.4, px_per_design / pile_freq.y);
		float pile = fbm2(pd * pile_freq) - 0.5;
		alb *= 1.0 + pile * 2.0 * pile_k * pile_fade * v_plush;
	}
	vec2 p_design = v_canvas - g_world_offset;
	float calm = smoothstep(calm_from_to.x, calm_from_to.y, length((p_design - focal_centre) / focal_radii));
	alb = mix(alb, vec3(wl_luma(alb)), calm_desat * calm) * (1.0 - calm_dark * calm);
	vec3 c = light_object(alb, 1.0 - v_luv.y, smoothstep(0.80, 1.0, v_luv.y));
	c = mix(c, c * g_shadow.rgb * SHADE_K, backlight_k * g_backlight * (0.45 + 0.55 * smoothstep(0.1, 0.9, v_luv.y)));
	c *= 1.0 + puff_light * facing + puff_core * (vol - 0.5) * v_plush;
	c = mix(c, c * shadow_tint() * SHADE_K, puff_roll * (1.0 - vol) * (0.15 + 0.85 * max(-facing, 0.0)));
	c += g_key.rgb * alb * sheen_k * max(facing, 0.0) * (1.0 - vol) * (1.0 - 0.5 * g_rain);
	if (v_rim > 0.5) {
		vec2 kd = key_dir(v_canvas);
		float ahead = textureLod(TEXTURE, UV + kd * rim_px * TEXTURE_PIXEL_SIZE, 0.75).a;
		c += g_key.rgb * g_rim * rim_k * m.a * (1.0 - ahead) * (1.0 - o);
	}
	if (g_cloud_shadow > 0.001) {
		c = mix(c, c * g_shadow.rgb * SHADE_K, cloud_shadow(p_design));
	}
	if (g_lights > 0.001) {
		c += alb * g_accent.rgb * lamp_soft(lamp_weight(p_design)) * lamp_fill_k;
	}
	float em = v_emit * g_lights;
	c = mix(c, v_detail * 1.1, em * (0.55 + 0.45 * m.b));
	c += vec3(tap_tint) * i_fx.x;
	float edge = clamp(m.a - hb, 0.0, 1.0);
	float a = cover * (1.0 - fringe_k * v_plush * edge * fuzz);
	COLOR = vec4(finish(c, v_luv * v_size / PX_PER_DP, FRAGCOORD.xy, GRAIN_OBJECT * (1.0 - v_plush)), a * COLOR.a);
}
