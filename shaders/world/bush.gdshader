// Felted shrubs and distant trees (round-2 directive 3, "cozy enclosure"): the soft hedge and tree
// line hugging the meadow crest and the shrubs at the hollow's left/right edges. Each instance is
// one rounded canopy (5-8 felted lobes, smooth-unioned) drawn analytically on a quad, lit by the
// time-of-day key (lobes catch the light on their sun-facing side; backlit rims at golden and
// dawn), with the felt cushion texture (art/fx/moss_tile.png), a fuzzy fibre fringe, a darker
// base and, for trees, a short trunk. Colours come from the terrain globals by depth:
//   depth 0 = hedge behind the crest (between g_mid and g_near, a touch of aerial haze),
//   depth 1 = shrubs on the meadow edges (g_near family).
// Quad contract (BushLayer / BushSprite): local VERTEX in canopy units, root at (0, 0), y up
// negative, quad x -1.15..1.15, y -QUAD_TOP..0.12; the instance transform scales by the radius px.
// Instance data (MultiMesh COLOR / BushSprite i_bush): r seed 0..1, g depth 0..1, b tree 0/1,
// a height k 0.8..1.3. MultiMesh CUSTOM / i_sway: x sway k, y amplitude px, z phase, w radius px.
shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/lamps.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"
#include "res://shaders/inc/sdf.gdshaderinc"

uniform sampler2D moss_tex : filter_linear_mipmap, repeat_enable;
// Set on the BushSprite material (no MultiMesh): instance data comes from instance uniforms.
uniform bool use_instance_uniforms = false;
instance uniform vec4 i_bush = vec4(0.5, 1.0, 0.0, 1.0);
instance uniform vec4 i_sway = vec4(120.0, 2.0, 0.0, 60.0);
// Object mode (BushSprite only, a = 1): the canopy is a lit object with this day albedo (the
// willow crown, palettes.json materials), multiplied by g_ambient like every object (§3.1).
instance uniform vec4 i_albedo : source_color = vec4(0.651, 0.8, 0.584, 0.0);
uniform float haze_k = 0.16;
uniform float trunk_k = 0.55;
uniform float moss_px = 34.0;

varying vec4 v_inst;
varying vec4 v_custom;
varying vec2 v_local;
varying vec2 v_canvas;

void vertex() {
	v_inst = use_instance_uniforms ? i_bush : COLOR;
	v_custom = use_instance_uniforms ? i_sway : INSTANCE_CUSTOM;
	v_local = VERTEX;
	float h = clamp(-VERTEX.y, 0.0, 2.0);
	vec2 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy - g_world_offset;
	float k = v_custom.x;
	float s = sin(TAU * k / LOOP_S * g_time + v_custom.z) + 0.3 * sin(TAU * k * 1.7 / LOOP_S * g_time + v_custom.z * 1.3);
	float r_px = max(v_custom.w, 1.0);
	VERTEX.x += s * v_custom.y / r_px * wind_k() * (1.0 + GUST_AMP * gust(world.x)) * g_motion * h * h * 0.5;
	v_canvas = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	COLOR = vec4(1.0);
}

float hs(float seed, float i, float salt) {
	return h12(vec2(seed * 211.0 + i * 5.17, salt));
}

void fragment() {
	vec2 p = v_local;
	float seed = v_inst.r;
	float depth = v_inst.g;
	bool tree = v_inst.b > 0.5;
	float hk = v_inst.a;
	float r_px = max(v_custom.w, 1.0);
	vec2 kd = key_dir(v_canvas);
	float fw = max(fwidth(p.x) + fwidth(p.y), 0.002);

	// Canopy: lobes along a soft arch (trees: a taller crown above a trunk).
	float n = 5.0 + floor(hs(seed, 0.0, 1.0) * 3.99);
	float d = 1e3;
	vec2 lob_n = vec2(0.0, -1.0);
	float lob_d = 1e3;
	float crown_y = tree ? -0.75 * hk : 0.0;
	for (int i = 0; i < 8; i++) {
		float fi = float(i);
		if (fi >= n) {
			break;
		}
		float u = fi / max(n - 1.0, 1.0) * 2.0 - 1.0;
		float r = mix(0.34, 0.52, hs(seed, fi, 2.0)) * (1.0 - 0.25 * abs(u));
		float x = u * (tree ? 0.55 : 0.72) + (hs(seed, fi, 3.0) - 0.5) * 0.16;
		float top = tree ? 0.62 : 0.55;
		float y = crown_y - r - (top * hk) * (1.0 - u * u) * mix(0.65, 1.0, hs(seed, fi, 4.0));
		vec2 c = vec2(x, y);
		float dl = length(p - c) - r;
		if (dl < lob_d) {
			lob_d = dl;
			lob_n = (p - c) / r;
		}
		d = smin(d, dl, 0.12);
	}
	// A low skirt joins the lobes to the ground (bushes) or to the trunk (trees).
	float skirt = sd_ellipse(p - vec2(0.0, crown_y - 0.16), vec2(tree ? 0.55 : 0.82, 0.24));
	d = smin(d, skirt, 0.14);
	float trunk = 1e3;
	if (tree) {
		trunk = sd_capsule(p, vec2(0.0, 0.0), vec2(0.0, crown_y - 0.1), 0.085 + 0.04 * (1.0 + p.y / max(-crown_y, 0.1)));
	}
	// Felt fringe: fibres in canopy units so the fuzz is a constant ~1.5 px at any size.
	float fuzz = (vnoise(p * r_px / 1.3 + seed * 37.0) - 0.5) * 1.6 / r_px;
	float dc = d + fuzz;
	float a_c = 1.0 - smoothstep(-0.7 * fw, 0.7 * fw, dc);
	float a_t = 1.0 - smoothstep(-0.7 * fw, 0.7 * fw, trunk);
	float a = max(a_c, a_t);
	if (a < 0.004) {
		discard;
	}

	// Colours by depth: hedge (between mid and near, hazed) .. edge shrubs (near family); objects
	// (the willow crown) use their albedo x ambient.
	vec3 base = mix(mix(g_mid.rgb, g_near.rgb, 0.55), g_near.rgb * 1.04, depth);
	base = mix(base, g_sky_horizon.rgb, haze_k * (1.0 - depth));
	bool object = use_instance_uniforms && i_albedo.a > 0.5;
	if (object) {
		base = i_albedo.rgb * g_ambient.rgb;
	}
	base *= 1.0 + (hs(seed, 9.0, 9.0) - 0.5) * 0.10;
	vec3 shade = base * g_shadow.rgb * SHADE_K;
	// Lobe light: the lobe's own normal toward the key plus a top-lit bias for the whole canopy.
	float lit = dot(normalize(lob_n + vec2(0.0, -0.35)), kd);
	// Contre-jour: with the light behind the hedge the viewer sees its shaded side; only the rims
	// glow (below). Front light lights the lobes.
	float back = g_backlight * g_celestial.x;
	vec3 c = mix(base, shade, clamp(-lit, 0.0, 1.0) * 0.45 + back * 0.32);
	c += (g_key.rgb * 0.65 + base * 0.35) * clamp(lit, 0.0, 1.0) * 0.18 * (0.5 + g_ground_light * 2.5) * (1.0 - 0.7 * back);
	// Crevices between lobes and the base sink into shade (felted masses, not one blob).
	float crease = smoothstep(0.0, 0.07, lob_d - d);
	c = mix(c, shade, crease * 0.35);
	c = mix(c, shade, smoothstep(crown_y - 0.35, crown_y + 0.05, p.y) * 0.45);
	// Felt cushion texture.
	vec4 m = texture(moss_tex, p * r_px / moss_px + seed * 5.0);
	float ml = dot(m.gb * 2.0 - 1.0, kd);
	c = mix(c, shade, clamp(-ml, 0.0, 1.0) * 0.16);
	c += g_key.rgb * clamp(ml, 0.0, 1.0) * m.r * 0.06;
	c *= 1.0 + (m.a - 0.5) * 0.10;
	// Contre-jour rim on the silhouette (golden, dawn): a thin glowing edge on the lit side.
	float edge = smoothstep(-3.0 * fw, 0.0, dc) * a_c;
	float facing = clamp(dot(normalize(lob_n), kd) * 0.7 + 0.3, 0.0, 1.0);
	c += g_key.rgb * g_rim * g_backlight * 0.55 * edge * facing;
	// Trunk: bark-dark, tinted by the canopy's shade.
	vec3 bark = mix(shade, base * vec3(0.78, 0.66, 0.58), 0.45) * trunk_k / 0.55;
	c = mix(c, bark, a_t * (1.0 - a_c));
	vec2 p_design = v_canvas - g_world_offset;
	if (g_cloud_shadow > 0.001) {
		c = mix(c, c * g_shadow.rgb * SHADE_K, cloud_shadow(p_design) * 1.4);
	}
	c += sun_veil(v_canvas, mix(0.6, 0.25, depth));
	c = mix(c, mix(g_sky_horizon.rgb, g_glow.rgb, 0.2), g_mist * 0.3 * (1.0 - depth));
	if (g_lights > 0.001) {
		c = apply_lamp(c, lamp_weight(p_design) * 0.7);
	}
	COLOR = vec4(finish(c, p * r_px / PX_PER_DP + seed * 17.0, FRAGCOORD.xy, GRAIN_TERRAIN), a);
}
