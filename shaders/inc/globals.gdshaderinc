// Every project shader global (project.godot [shader_globals], Art Bible §4.1), declared once.
// Writers: TimeOfDay (palette, weather, celestial), Clock (g_time, g_motion), Main via TimeOfDay
// (g_world_offset, g_cam_pan). Shaders only READ them (ARCHITECTURE §12).
//
// Rule for every shader in the project: never declare a `global uniform g_*` yourself; include
// this file (world_light.gdshaderinc, lamps.gdshaderinc and finish users get it automatically).
// The include guard makes repeated includes harmless. Unused declarations cost nothing: GLES3
// reads globals from one shared buffer only where a shader references them.
#ifndef MM_GLOBALS_INC
#define MM_GLOBALS_INC

// Time driver (Clock): wrapped at 600 s; every loop is k/600 Hz (C4).
global uniform float g_time;
global uniform float g_motion;
// Palette key (0 night, .2 dawn, .4 day, .6 golden, .8 dusk, 1 night) and weather.
global uniform float g_day;
global uniform float g_wind;
global uniform float g_cloud;
global uniform float g_rain;
// Celestial (canvas px; add nothing, they already include g_world_offset).
global uniform vec2 g_sun_dir;
global uniform vec2 g_sun_pos;
global uniform vec2 g_moon_pos;
global uniform vec2 g_celestial;
global uniform vec2 g_halo;
global uniform vec2 g_world_offset;
// Map pan (canvas px, ARCHITECTURE §3.4): the camera's offset from its home view, idle drift
// excluded. g_sun_pos / g_moon_pos stay pinned to the world (lighting and shadows never change
// with the view); the sun and moon DISCS sit on L1 (scroll 0.02), so anything drawn around a disc
// (sky body, sun veil, light shafts) adds celestial_shift() = g_cam_pan * (1 - L1).
global uniform vec2 g_cam_pan;
const float CELESTIAL_SCROLL = 0.02;
vec2 celestial_shift() {
	return g_cam_pan * (1.0 - CELESTIAL_SCROLL);
}
// Palette colours (sRGB, as stored in palettes.json).
global uniform vec4 g_sky_top;
global uniform vec4 g_sky_mid;
global uniform vec4 g_sky_horizon;
global uniform vec4 g_glow;
global uniform vec4 g_far;
global uniform vec4 g_mid;
global uniform vec4 g_near;
global uniform vec4 g_fg;
global uniform vec4 g_ambient;
global uniform vec4 g_key;
global uniform vec4 g_shadow;
global uniform vec4 g_accent;
global uniform vec4 g_ground_back;
global uniform vec4 g_ground_front;
global uniform vec4 g_water_deep;
global uniform vec4 g_water_shallow;
// Palette scalars.
global uniform float g_rim;
global uniform float g_backlight;
global uniform float g_ground_light;
global uniform float g_shadow_alpha;
global uniform float g_stars;
global uniform float g_lights;
global uniform float g_shafts;
global uniform float g_cloud_shadow;
global uniform float g_mist;

#endif
