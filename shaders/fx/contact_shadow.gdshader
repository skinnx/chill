// Contact + cast shadow of a standing object (Art Bible §4.12, §8.1): a soft contact ellipse at
// the feet and a longer cast ellipse pushed away from the light (offset computed on the CPU from
// g_sun_dir and the light elevation, 2 Hz), tinted g_shadow, never black. One shared material.
// Quad contract (ContactShadow): local VERTEX px with the foot at the origin.
shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://shaders/inc/globals.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

// x contact half-width px, y contact half-height px, z object height px, w alpha multiplier.
instance uniform vec4 i_shadow = vec4(40.0, 10.0, 80.0, 1.0);
// x, y cast offset px (away from the light), z length factor (0.35..2.5), w hop height 0..1.
instance uniform vec4 i_cast = vec4(0.0, 10.0, 1.0, 0.0);

uniform float soft_px = 18.0;
uniform float cast_alpha = 1.0;
uniform float rain_fade = 0.4;
uniform float cast_fade = 0.85;
// Half length of the cast ellipse = contact half-height + |offset| x this (ContactShadow.CAST_LEN_K).
uniform float cast_len_k = 1.0;
uniform float backlight_gain = 0.5;
// The far end of a long shadow fades over this fraction of its length (soft, lost edge).
uniform vec2 cast_fade_band = vec2(0.55, 1.0);

varying vec2 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec2 p = v_local;
	vec2 hc = max(i_shadow.xy, vec2(1.0));
	// Contact core: soft ellipse, softness ~18 px at its rim.
	float e = length(p / hc);
	float core = 1.0 - smoothstep(1.0 - soft_px / hc.x, 1.0 + soft_px * 0.5 / hc.y, e);
	// Cast: an ellipse centred on the offset, elongated along it, softer as it lengthens.
	vec2 off = i_cast.xy;
	float ol = length(off);
	vec2 u = ol > 0.5 ? off / ol : vec2(0.0, 1.0);
	vec2 v = vec2(-u.y, u.x);
	vec2 q = p - off;
	float lu = hc.y + ol * cast_len_k;
	float lv = hc.x * mix(0.95, 0.7, clamp(ol / max(hc.x, 1.0), 0.0, 1.0));
	float e2 = length(vec2(dot(q, v) / max(lv, 1.0), dot(q, u) / max(lu, 1.0)));
	float soft2 = mix(soft_px, soft_px * 2.0, clamp((i_cast.z - 0.35) / 2.15, 0.0, 1.0));
	float cast = (1.0 - smoothstep(1.0 - soft2 / max(lv, 1.0), 1.0 + soft2 * 0.4 / max(lv, 1.0), e2)) * cast_alpha;
	// Long shadows thin out away from the foot (penumbra widens, contrast drops).
	float along = clamp(dot(p, u) / max(ol + lu, 1.0), 0.0, 1.0);
	// Lighter toward the far end as the penumbra widens (a long shadow is never a slab).
	cast *= mix(1.0, 0.7, along);
	cast *= 1.0 - cast_fade * smoothstep(cast_fade_band.x, cast_fade_band.y, along);
	// A low sun (golden, dawn: high backlight) throws a darker, longer cast (QA r2 #5).
	cast *= 1.0 + backlight_gain * g_backlight;
	float a = max(core, cast) * g_shadow_alpha * i_shadow.w * (1.0 - 0.6 * i_cast.w) * (1.0 - rain_fade * g_rain);
	if (a < 0.002) {
		discard;
	}
	COLOR = vec4(g_shadow.rgb + tpdf(FRAGCOORD.xy), clamp(a + tpdf(FRAGCOORD.xy + 3.1), 0.0, 1.0));
}
