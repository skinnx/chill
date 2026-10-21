// DEV PLACEHOLDER (Tech Lead skeleton). Flat bands that read the time-of-day globals so the
// clock -> TimeOfDay -> shader-global pipeline is visible before the real art lands.
// Replaced layer by layer by the Art Bible shaders (world/sky, silhouette, meadow, water ...);
// delete this file when the last PlaceholderBand is gone (docs/ARCHITECTURE.md §12).
shader_type canvas_item;
render_mode unshaded;

global uniform vec4 g_sky_top;
global uniform vec4 g_sky_mid;
global uniform vec4 g_sky_horizon;
global uniform vec4 g_far;
global uniform vec4 g_mid;
global uniform vec4 g_ground_back;
global uniform vec4 g_ground_front;
global uniform vec4 g_water_deep;
global uniform vec4 g_water_shallow;
global uniform vec4 g_fg;
global uniform vec2 g_world_offset;
global uniform float g_time;

// 0 sky gradient, 1 far, 2 mid, 3 ground gradient, 4 water, 5 foreground.
uniform int slot = 0;
// Design-px y range of the vertical gradient (sky: the top is the visible top instead).
uniform vec2 band_y = vec2(0.0, 700.0);

varying vec2 v_design;

void vertex() {
	v_design = VERTEX;
}

// TPDF dither, +-1 LSB (synthesis C6), so even placeholders never band.
float tpdf(vec2 p) {
	float a = fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
	float b = fract(sin(dot(p + 17.0, vec2(39.3468, 11.135))) * 24634.6345);
	return (a + b - 1.0) / 255.0;
}

void fragment() {
	vec3 c;
	float y0 = band_y.x;
	if (slot == 0) {
		y0 = -g_world_offset.y;  // the sky gradient always starts at the visible top (Art Bible §4.3)
	}
	float t = clamp((v_design.y - y0) / max(band_y.y - y0, 1.0), 0.0, 1.0);
	if (slot == 0) {
		c = t < 0.42 ? mix(g_sky_top.rgb, g_sky_mid.rgb, t / 0.42) : mix(g_sky_mid.rgb, g_sky_horizon.rgb, (t - 0.42) / 0.58);
	} else if (slot == 1) {
		c = g_far.rgb;
	} else if (slot == 2) {
		c = g_mid.rgb;
	} else if (slot == 3) {
		c = mix(g_ground_back.rgb, g_ground_front.rgb, t);
	} else if (slot == 4) {
		float w = 0.5 + 0.5 * sin(6.2831853 * (g_time * 60.0 / 600.0) + v_design.x * 0.02);
		c = mix(g_water_deep.rgb, g_water_shallow.rgb, 0.35 + 0.15 * w);
	} else {
		c = g_fg.rgb;
	}
	COLOR = vec4(c + tpdf(FRAGCOORD.xy), 1.0);
}
