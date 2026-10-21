// Flower beds (Art Bible §4.10, §6.1-6.3): one MeshInstance2D per bed, rebuilt by FloraBuilder
// (scripts/flora/flora_builder.gd) only when a stem changes stage or unfurls. Every stamp is a
// region of the tone-mask atlas (art/flora/flora_atlas.svg: R lit, G shade, B detail, black =
// colour-line tone, alpha = coverage) recoloured from the flora LUT (rows 0-7 = flowers in
// garden_order: petal lit/shade/detail, leaf lit/shade/detail, stem, bud; row 8 = soil + moss
// materials; row 9 = FX), then lit like every object (ambient, tinted AO at the root, key on
// top, contre-jour, cloud shadows, lamp pools, moonbloom emission), with a felted fibre fringe
// on every edge and a warm translucent rim when the light is behind (golden hour).
//
// Vertex data (FloraBuilder.ATTR_*):
//   COLOR    r = LUT row / 15, g = part kind / 15, b = height on the stem 0 (root) .. 1 (tip),
//            a = part alpha (fades). Modulate the node's alpha only (rgb carries data).
//   CUSTOM0  x = sway amplitude at the tip (px), y = sway loop k (k/600 Hz, integer),
//            z = bloom mix (0 bud colour .. 1 petal colours), w = per-stem lightness jitter -1..1.
//   CUSTOM1  xy = attach point (local px: stem root for the stem strip, the attach point on the stem
//            for rigid parts), z = stem length px, w = phase (rad).
// Sway: the stem strip bends with h^2; rigid parts (leaves, petals, heads) translate with the
// stem at their attach height and rotate with its tangent there, so they stay attached at full
// sway (§4.10 acceptance). Leaves flutter and bells swing a little on top.
shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/lamps.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

// FloraBuilder.PART_* (keep in sync).
const int PART_STEM = 0;
const int PART_LEAF = 1;
const int PART_PETAL = 2;
const int PART_BUD = 3;
const int PART_CENTRE = 4;
const int PART_SOIL = 5;
const int PART_MOSS = 6;
const int PART_SPARKLE = 7;
const int PART_BELL = 8;
const int PART_FOLIAGE = 9;
const int PART_STAMEN = 10;
const int PART_GLINT = 11;
// Glints twinkle every 600/76 s (Art Bible §6.2); dew beads are brightest at dawn (g_day 0.2).
const float GLINT_K = 76.0;
const float DAWN_KEY = 0.2;
const float PART_DIV = 15.0;
const int ROW_GROUND = 8;
const int ROW_FX = 9;

// 8 x 10 RGBA8, nearest; built at boot from palettes.json (FloraBuilder.build_lut).
// Per bed (PlotsLayer): x = tap sway impulse px at the tip, z = touch-down tint 0..1.
instance uniform vec4 i_bed = vec4(0.0);
uniform float tap_tint = 0.06;

uniform sampler2D flora_lut : filter_nearest, repeat_disable;
// Atlas px per design px (flora_atlas.json "scale").
uniform float atlas_scale = 2.0;
uniform float line_k = 0.72;
uniform float backlight_k = 0.34;
uniform float translucency_k = 0.55;
uniform float rim_k = 0.9;
// Leaves and foliage clumps take a softer rim than petals (petals are the backlit stars).
uniform float leaf_rim = 0.55;
uniform float fringe_k = 0.55;
uniform float lamp_fill_k = 1.1;
uniform float gust_lean = 0.55;
uniform float leaf_flutter = 0.07;
uniform float bell_swing = 0.12;
uniform float tilt_k = 0.8;
uniform float jitter_l = 0.045;
uniform float root_ao = 0.9;
// Felt fringe and rim: blurred-alpha mip level (a 1-2 design px band inside every edge).
uniform float edge_lod = 2.0;

varying flat vec3 v_lit;
varying flat vec3 v_shade;
varying flat vec3 v_detail;
varying flat float v_kind;
varying flat float v_emit;
varying flat float v_phase;
varying float v_h;
varying float v_alpha;
varying float v_jitter;
varying vec2 v_canvas;

vec3 lut(int col, int row) {
	return texelFetch(flora_lut, ivec2(col, row), 0).rgb;
}

vec2 rot2v(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

void vertex() {
	int row = int(round(COLOR.r * PART_DIV));
	int kind = int(round(COLOR.g * PART_DIV));
	float h = COLOR.b;
	v_alpha = COLOR.a;
	v_h = h;
	v_kind = float(kind);
	v_jitter = CUSTOM0.w;
	v_phase = CUSTOM1.w;
	float bloom = CUSTOM0.z;

	vec3 p_lit = lut(0, row);
	vec3 p_shade = lut(1, row);
	vec4 p_det4 = texelFetch(flora_lut, ivec2(2, row), 0);
	vec3 l_lit = lut(3, row);
	vec3 l_shade = lut(4, row);
	vec3 l_det = lut(5, row);
	vec3 stem_c = lut(6, row);
	vec3 bud_c = lut(7, row);
	float emission = texelFetch(flora_lut, ivec2(0, row), 0).a;
	vec3 bud_shade = mix(bud_c, l_shade, 0.55);
	v_emit = 0.0;
	if (kind == PART_STEM) {
		v_lit = stem_c; v_shade = l_shade; v_detail = l_det;
	} else if (kind == PART_LEAF || kind == PART_FOLIAGE) {
		v_lit = l_lit; v_shade = l_shade; v_detail = l_det;
	} else if (kind == PART_PETAL || kind == PART_BELL) {
		v_lit = mix(bud_c, p_lit, bloom);
		v_shade = mix(bud_shade, p_shade, bloom);
		v_detail = mix(bud_c, p_det4.rgb, bloom);
		v_emit = emission * bloom;
	} else if (kind == PART_BUD) {
		v_lit = bud_c; v_shade = bud_shade; v_detail = mix(bud_c, p_lit, 0.35 + 0.65 * bloom);
	} else if (kind == PART_CENTRE || kind == PART_STAMEN) {
		vec3 ratio = p_shade / max(p_lit, vec3(0.05));
		v_lit = p_det4.rgb; v_shade = p_det4.rgb * ratio; v_detail = p_lit;
		v_emit = emission * 2.0 * bloom;
	} else if (kind == PART_SOIL) {
		v_lit = lut(0, ROW_GROUND); v_shade = lut(1, ROW_GROUND); v_detail = lut(2, ROW_GROUND);
	} else if (kind == PART_MOSS) {
		v_lit = lut(3, ROW_GROUND); v_shade = lut(4, ROW_GROUND); v_detail = lut(5, ROW_GROUND);
	} else {
		v_lit = lut(0, ROW_FX); v_shade = lut(1, ROW_FX); v_detail = lut(2, ROW_FX);
	}

	// Sway (k/600 Hz with an integer harmonic, so it loops at the 600 s wrap) + travelling gust lean.
	float k = CUSTOM0.y;
	float ph = CUSTOM1.w;
	float k2 = floor(k * 2.13 + 0.5);
	float s = sin(TAU * k / LOOP_S * g_time + ph) + 0.35 * sin(TAU * k2 / LOOP_S * g_time + ph * 1.7 + 1.3);
	vec2 root_design = (MODEL_MATRIX * vec4(CUSTOM1.xy, 0.0, 1.0)).xy - g_world_offset;
	float wk = wind_k();
	float dx = CUSTOM0.x * g_motion * wk * (0.8 * s + gust_lean * gust(root_design.x));
	dx += i_bed.x * g_motion * (0.6 + 0.4 * sin(ph)) * step(0.001, CUSTOM0.x);
	float len = max(CUSTOM1.z, 1.0);
	if (kind == PART_STEM) {
		VERTEX.x += dx * h * h;
	} else if (CUSTOM0.x > 0.0) {
		float a = atan(2.0 * dx * h / len) * tilt_k;
		if (kind == PART_LEAF) {
			a += leaf_flutter * g_motion * wk * sin(TAU * (k + 37.0) / LOOP_S * g_time + ph * 2.3 + VERTEX.x * 0.01);
		} else if (kind == PART_BELL) {
			a += bell_swing * g_motion * wk * sin(TAU * (k + 19.0) / LOOP_S * g_time + ph * 3.1 + CUSTOM1.x * 0.13);
		}
		VERTEX = CUSTOM1.xy + rot2v(VERTEX - CUSTOM1.xy, a) + vec2(dx * h * h, 0.0);
	}
	v_canvas = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 m = texture(TEXTURE, UV);
	float cover = m.a * v_alpha;
	if (cover < 0.004) {
		discard;
	}
	int kind = int(v_kind + 0.5);
	float o = clamp(1.0 - (m.r + m.g + m.b), 0.0, 1.0);
	vec3 alb = m.r * v_lit + m.g * v_shade + m.b * v_detail + o * v_shade * line_k;
	alb *= 1.0 + jitter_l * v_jitter;
	vec3 c;
	float blurred = textureLod(TEXTURE, UV, edge_lod).a;
	float edge = clamp(m.a - blurred, 0.0, 1.0);
	if (kind == PART_SPARKLE || kind == PART_GLINT) {
		// Emissive specks, dimmed by the ambient at night so they never outshine the lamps.
		c = mix(alb * g_ambient.rgb, alb, 0.6);
		if (kind == PART_GLINT) {
			float tw = pow(max(0.0, sin(TAU * GLINT_K / LOOP_S * g_time + v_phase * 5.0)), 10.0);
			float dawn = 1.0 - smoothstep(0.04, 0.14, abs(g_day - DAWN_KEY));
			cover *= (0.22 + 0.5 * dawn + 0.6 * tw) * (1.0 - 0.6 * g_rain);
		}
	} else {
		// Root AO: everything near the ground sinks into the meadow's tinted shade (grounding).
		float ao = (kind == PART_FOLIAGE || kind == PART_SOIL || kind == PART_MOSS) ? 0.55
				: (kind == PART_STEM ? 1.0 - smoothstep(0.0, 0.25, v_h) : 0.3 * (1.0 - smoothstep(0.0, 0.3, v_h)));
		c = light_object(alb, v_h, ao * root_ao);
		// Contre-jour: the side we see is the shaded one (golden, dusk) [J, Art Bible §8.1].
		c = mix(c, c * g_shadow.rgb * SHADE_K, backlight_k * g_backlight);
		// Thin petals and leaves glow when the light is behind them, strongest at their edges.
		bool thin = kind == PART_PETAL || kind == PART_BELL || kind == PART_LEAF || kind == PART_STAMEN;
		float glow = g_backlight * g_rim * (thin ? translucency_k * (0.35 + 0.65 * m.r) : 0.0);
		float rim_part = (kind == PART_FOLIAGE || kind == PART_LEAF) ? leaf_rim : 1.0;
		c += g_key.rgb * (glow * 0.35 + rim_k * rim_part * g_rim * g_backlight * edge) * alb;
		vec2 p_design = v_canvas - g_world_offset;
		if (g_cloud_shadow > 0.001) {
			c = mix(c, c * g_shadow.rgb * SHADE_K, cloud_shadow(p_design));
		}
		if (g_lights > 0.001) {
			c += alb * g_accent.rgb * lamp_soft(lamp_weight(p_design)) * lamp_fill_k;
		}
		// Moonbloom petals 0.25 and stamens 0.5 x g_lights (Art Bible §3.7).
		float em = v_emit * g_lights;
		c = mix(c, alb * 1.08, clamp(em, 0.0, 1.0));
	}
	c += vec3(tap_tint) * i_bed.z;
	// Felted fringe: fibres thin the outermost px of every edge (anchored to the stamp).
	vec2 texel = UV / TEXTURE_PIXEL_SIZE;
	float fib = h12(floor(texel * 0.5));
	float a = cover * (1.0 - fringe_k * edge * fib);
	vec2 uv_dp = texel / (atlas_scale * PX_PER_DP);
	COLOR = vec4(finish(c, uv_dp, FRAGCOORD.xy, GRAIN_OBJECT), clamp(a, 0.0, 1.0));
}
