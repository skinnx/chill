// Neutral meadow backdrop for scenes/creatures/lineup.tscn (creature QA, Art Bible §11.2): the
// live meadow colours (g_ground_back -> g_ground_front) with a soft vignette, grain and TPDF, so
// creatures are judged against the ground they will stand on at every time of day.
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

const float BACKDROP_PEACH = 0.15;

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
	// round 5: the world's golden terrain grade (gold-green lit moss, L* floor), so the lineup
	// judges the friends on the glowing meadow they stand on in Main, not an olive card
	col = golden_grade(col, vec2(540.0, 1200.0) + (uv - 0.5) * vec2(1080.0, 900.0), BACKDROP_PEACH);
	col *= vig;
	col = finish(col, v_local / PX_PER_DP, FRAGCOORD.xy, GRAIN_TERRAIN);
	COLOR = vec4(col, 1.0);
}
