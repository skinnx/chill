// Studio meadow backdrop for scenes/creatures/lineup.tscn (creature QA, Art Bible §11.2): a
// toy-shop product sweep in the live meadow colours. Every row is a soft paper sweep (a lighter
// wall curving into a slightly darker floor at the friends' feet) with a gentle key pool behind
// each friend, so the plush friends are judged like a product shot on the ground colours they
// stand on in Main, at every time of day. Grain + TPDF as every terrain surface.
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

const float BACKDROP_PEACH = 0.45;      // a warm-lit studio sweep at golden (glowing, never olive)
const float PAPER_DESAT = 0.22;          // studio paper: the meadow colour a little calmer
const float PAPER_LIFT = 1.08;
const float WALL_LIFT = 0.07;            // wall above the sweep, lighter
const float FLOOR_DARK = 0.06;           // floor below the feet, a touch darker
const float SWEEP_W = 0.16;              // sweep curve height (cell fraction)
const float POOL_K = 0.10;               // key-light pool behind each friend
const vec2 POOL_R = vec2(0.42, 0.34);    // pool radius (cell fractions)

uniform vec2 u_size = vec2(1080.0, 1920.0);
// x top px, y cell height px, z cell width px, w floor line (cell fraction of the feet)
uniform vec4 u_grid = vec4(0.0, 480.0, 270.0, 0.78);

varying vec2 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec2 uv = v_local / u_size;
	vec3 base = mix(g_ground_back.rgb, g_ground_front.rgb, smoothstep(0.0, 1.0, uv.y));
	base += g_key.rgb * g_ground_light * 0.25 * (1.0 - uv.y);
	// calmer paper by day; at golden the meadow keeps its glow (the grade below warms it)
	base = mix(base, vec3(wl_luma(base)), PAPER_DESAT * (1.0 - g_backlight)) * PAPER_LIFT;
	// per-row sweep: the wall brightens up from the previous row's floor value, curves into the
	// floor at the feet, so rows tile without a seam
	float rv = (v_local.y - u_grid.x) / max(u_grid.y, 1.0);
	float fy = fract(rv) - u_grid.w;                    // 0 at the feet line
	float sweep = smoothstep(-SWEEP_W, SWEEP_W * 0.4, fy);
	float wall = mix(1.0 - FLOOR_DARK, 1.0 + WALL_LIFT, smoothstep(-u_grid.w, -0.25, fy));
	vec3 col = base * mix(wall, 1.0 - FLOOR_DARK, sweep);
	// key pool behind the friend in this cell (soft, toward the key colour)
	float cx = fract(v_local.x / max(u_grid.z, 1.0)) - 0.5;
	vec2 pq = vec2(cx, fy + 0.3) / POOL_R;
	col += col * g_key.rgb * POOL_K * exp(-dot(pq, pq) * 2.2);
	float vig = 1.0 - 0.10 * smoothstep(0.35, 0.95, length((uv - 0.5) * vec2(1.0, 0.8)));
	// the world's golden terrain grade (gold-green lit moss, L* floor), as in Main
	col = golden_grade(col, vec2(540.0, 1200.0) + (uv - 0.5) * vec2(1080.0, 900.0), BACKDROP_PEACH);
	col *= vig;
	col = finish(col, v_local / PX_PER_DP, FRAGCOORD.xy, GRAIN_TERRAIN);
	COLOR = vec4(col, 1.0);
}
