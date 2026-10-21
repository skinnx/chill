// Live-render well (Art Bible §9.4: the Garden card's mini-render well, the Album portrait well,
// the new-friend and postcard portraits). The things drawn in it are live, lit by the hollow's
// current palette, so the well is a small window into that same light: the sky horizon above a
// soft rise of the meadow, both veiled toward the UI surface so a card stays calm, plus a tinted
// ground-contact pool under the subject. At night the well darkens with the world, so a night-lit
// flower or friend never sits as a muddy shape on a bright card. Rounded box, 1 px AA, dithered.
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/inc/globals.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

uniform vec2 u_size = vec2(252.0, 252.0);
uniform float u_radius = 48.0;
uniform vec4 u_surface : source_color = vec4(1.0, 0.992, 0.973, 1.0);   // ui.surface_hi
uniform float u_veil_sky = 0.42;        // how much of the UI surface veils the sky part
uniform float u_veil_ground = 0.3;      // ... and the meadow part
uniform float u_horizon = 0.6;          // horizon line (fraction of the height)
uniform float u_ground_y = 0.84;        // centre of the contact pool (fraction of the height)

varying vec2 v_local;

void vertex() {
	v_local = VERTEX;
}

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 half_size = u_size * 0.5;
	float r = min(u_radius, min(half_size.x, half_size.y));
	float d = sd_round_box(v_local - half_size, half_size, r);
	float cov = clamp(0.5 - d, 0.0, 1.0);
	vec2 uv = v_local / max(u_size, vec2(1.0));
	// a gentle hill line, higher at the left like the hollow's crest
	float hill = u_horizon + 0.05 * sin(uv.x * 3.1 + 0.6) - 0.03 * uv.x;
	float edge = fwidth(uv.y) * 1.5;
	float ground = smoothstep(hill - edge, hill + edge, uv.y);
	mediump vec3 sky = mix(g_sky_mid.rgb, g_sky_horizon.rgb, smoothstep(0.0, hill, uv.y));
	sky = mix(sky, u_surface.rgb, u_veil_sky);
	mediump vec3 meadow = mix(g_ground_back.rgb, g_ground_front.rgb, smoothstep(hill, 1.0, uv.y));
	meadow = mix(meadow, u_surface.rgb, u_veil_ground);
	mediump vec3 c = mix(sky, meadow, ground);
	// contact pool under the subject, tinted by the palette shadow (never grey)
	vec2 q = (uv - vec2(0.5, u_ground_y)) / vec2(0.34, 0.07);
	float pool = (1.0 - smoothstep(0.4, 1.0, length(q))) * 0.22;
	c = mix(c, g_shadow.rgb * c, pool);
	c = finish(c, v_local / PX_PER_DP, FRAGCOORD.xy, GRAIN_GLASS);
	COLOR = vec4(c, cov * COLOR.a);
}
