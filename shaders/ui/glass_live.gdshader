// Live glass (Art Bible §4.17 C7): exactly one surface at a time, the open sheet. A BackBufferCopy
// (rect = the sheet) precedes the scrim, so this reads the world without the scrim. The blur is
// the mip chain (filter_linear_mipmap at LOD ~3.5) with a small rotated 4-tap kernel on top so the
// mip blocks never show; saturation x1.15; adaptive tint: tint = mix(max, min,
// smoothstep(lo, hi, luma)) so bright skies get the light 0.66 veil and dark nights the 0.90 one,
// which keeps ink >= 8.9:1 over any backdrop (palettes.json ui_alpha.glass_live_adaptive).
// Reduce Transparency and the low tier never use this shader (the sheet falls back to glass_faux
// at fill 1.0 and the BackBufferCopy is disabled).
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/ui/glass.gdshaderinc"

uniform vec2 u_size = vec2(120.0, 120.0);          // the sheet's size, px (one live surface)

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float u_lod = 3.5;              // ui_alpha.glass_lod
uniform float u_saturation = 1.15;      // ui_alpha.backdrop_saturation
uniform float u_tint_min = 0.66;        // ui_alpha.glass_live_adaptive.min
uniform float u_tint_max = 0.9;         // ui_alpha.glass_live_adaptive.max
uniform float u_luma_lo = 0.05;
uniform float u_luma_hi = 0.45;
// After dark the sheet's veil is held at u_night_tint (ui_alpha.night_chrome.live_tint) whatever
// the local backdrop, so the moon disc and the lantern halos never shine through (QA r3 #19).
uniform float u_live_night = 0.0;
uniform float u_night_tint = 0.94;

const float TAP_SPREAD_PX = 9.0;

void vertex() {
	v_local = VERTEX - vec2(u_margin);
}

void fragment() {
	float d = glass_sd(u_size);
	float cov = clamp(0.5 - d, 0.0, 1.0);
	vec2 px = SCREEN_PIXEL_SIZE * TAP_SPREAD_PX;
	vec3 b = textureLod(screen_tex, SCREEN_UV + vec2(px.x, px.y * 0.35), u_lod).rgb;
	b += textureLod(screen_tex, SCREEN_UV + vec2(-px.x * 0.35, px.y), u_lod).rgb;
	b += textureLod(screen_tex, SCREEN_UV + vec2(-px.x, -px.y * 0.35), u_lod).rgb;
	b += textureLod(screen_tex, SCREEN_UV + vec2(px.x * 0.35, -px.y), u_lod).rgb;
	b *= 0.25;
	float l = dot(b, vec3(0.2126, 0.7152, 0.0722));
	b = clamp(mix(vec3(l), b, u_saturation), 0.0, 1.0);
	float tint = mix(u_tint_max, u_tint_min, smoothstep(u_luma_lo, u_luma_hi, l));
	tint = mix(tint, max(tint, u_night_tint), u_live_night);
	vec3 c = mix(b, u_surface.rgb, tint);
	vec4 g = glass_dress(c, 1.0, d, u_size);
	vec4 o = over_shadow(g.rgb, cov, glass_shadow(u_size));
	c = finish(o.rgb, v_local / PX_PER_DP, FRAGCOORD.xy, GRAIN_GLASS);
	COLOR = vec4(c, o.a * COLOR.a);
}
