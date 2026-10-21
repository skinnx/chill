// Shared body of the L2/L3 silhouette shaders (Art Bible §4.4). silhouette.gdshader (feather strip,
// blend_mix) and silhouette_core.gdshader (opaque interior, blend_disabled) both include it.
// Mesh contract (SilhouetteLayer): VERTEX = design px; UV.x = depth 0 (crest) .. 1 (body bottom);
// UV.y = px below the crest (negative inside the feather); COLOR.a = feather coverage.
#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

// 0 = far (g_far, fog toward far_haze), 1 = mid (g_mid, fog toward mid_haze).
uniform int layer = 0;
// Valley-fog mix toward g_sky_horizon at the body bottom: far 0.30, mid 0.15 (palettes derived).
uniform float fog_k = 0.30;
// Extra fog in rain (overcast flattens depth further) [J].
uniform float rain_fog_k = 0.22;
uniform float veil_k = 1.0;
uniform float crest_rim_px = 3.0;
// Soft canopy mottling of the tree line (mid only), +- this fraction of value [J].
uniform float mottle_k = 0.0;

varying vec2 v_design;
varying vec2 v_canvas;

void vertex() {
	v_design = VERTEX;
	v_canvas = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

vec3 silhouette_color(vec2 uv, vec2 frag) {
	vec3 base = layer == 0 ? g_far.rgb : g_mid.rgb;
	float k = fog_k + rain_fog_k * g_rain;
	vec3 c = mix(base, mix(base, g_sky_horizon.rgb, k), smoothstep(0.0, 1.0, uv.x));
	if (mottle_k > 0.0) {
		float m = vnoise(v_design * vec2(1.0 / 34.0, 1.0 / 22.0)) * 0.65 + vnoise(v_design / 9.0) * 0.35;
		c *= 1.0 + (m - 0.5) * 2.0 * mottle_k * (1.0 - uv.x);
	}
	float rim = 1.0 - smoothstep(0.0, crest_rim_px, max(uv.y, 0.0));
	c += g_key.rgb * (g_rim * g_backlight * 0.25 * rim);
	c += sun_veil(v_canvas, veil_k);
	c = mix(c, mix(g_sky_horizon.rgb, g_glow.rgb, 0.2), g_mist * 0.35 * smoothstep(0.2, 1.0, uv.x));
	return finish(c, v_design / PX_PER_DP, frag, GRAIN_TERRAIN);
}
