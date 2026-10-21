// Neutral meadow backdrop for scenes/creatures/lineup.tscn (creature QA, Art Bible §11.2): the
// live meadow colours (g_ground_back -> g_ground_front) with a soft vignette, grain and TPDF, so
// creatures are judged against the ground they will stand on at every time of day.
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/inc/globals.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

uniform vec2 u_size = vec2(1080.0, 1920.0);

varying vec2 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec2 uv = v_local / u_size;
	vec3 col = mix(g_ground_back.rgb, g_ground_front.rgb, smoothstep(0.0, 1.0, uv.y));
	col += g_key.rgb * g_ground_light * 0.25 * (1.0 - uv.y);
	float vig = 1.0 - 0.10 * smoothstep(0.35, 0.95, length((uv - 0.5) * vec2(1.0, 0.8)));
	col *= vig;
	col = finish(col, v_local / PX_PER_DP, FRAGCOORD.xy, GRAIN_TERRAIN);
	COLOR = vec4(col, 1.0);
}
