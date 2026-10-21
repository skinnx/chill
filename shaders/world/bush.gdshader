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
// Round 4 (QA r3: the willow canopy out-contrasted the focal): object canopies (the willow crown,
// mid-ground) keep a softer lit/shade split and a breath of aerial haze, so they sit back.
uniform float object_shade_mix = 0.62;
uniform float object_haze_k = 0.07;

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
	VERTEX.x += s * v_custom.y / r_px * wind_k() * (1.0 + GUST_AMP * gust_at(world)) * g_motion * h * h * 0.5;
	v_canvas = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	COLOR = vec4(1.0);
}

float hs(float seed, float i, float salt) {
	return h12(vec2(seed * 211.0 + i * 5.17, salt));
}

// Lobe k of the canopy (0..7, back to front): centre and radius in canopy units. Rows: one top
// lobe, an upper row of three, a lower (front) row of four, jittered per seed.
vec3 lobe(float seed, int k, float crown_y, float hk, bool tree) {
	float fk = float(k);
	vec2 j = vec2(hs(seed, fk, 2.0), hs(seed, fk, 3.0)) - 0.5;
	float w = tree ? 0.78 : 1.0;
	if (k == 0) {
		return vec3(j.x * 0.18 * w, crown_y - 1.12 * hk - 0.04 * j.y, mix(0.27, 0.34, hs(seed, fk, 4.0)));
	}
	if (k < 4) {
		float u = (fk - 2.0) * 0.42;
		return vec3((u + j.x * 0.12) * w, crown_y - 0.76 * hk - 0.08 * j.y - 0.1 * (1.0 - abs(u)), mix(0.30, 0.40, hs(seed, fk, 4.0)));
	}
	float u = (fk - 5.5) / 1.5 * 0.62;
	return vec3((u + j.x * 0.10) * w, crown_y - 0.36 - 0.06 * j.y, mix(0.34, 0.44, hs(seed, fk, 4.0)) * (1.0 - 0.18 * abs(u)));
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
	float crown_y = tree ? -0.75 * hk : 0.0;
	// Felt fringe: fibres in canopy units so the fuzz is a constant ~1.5 px at any size.
	float fuzz = (vnoise(p * r_px / 1.3 + seed * 37.0) - 0.5) * 1.6 / r_px;

	// Colours by depth: hedge (between mid and near, hazed) .. edge shrubs (near family); objects
	// (the willow crown) use their albedo x ambient.
	vec3 base = mix(mix(g_mid.rgb, g_near.rgb, 0.55), g_near.rgb * 1.04, depth);
	base = mix(base, g_sky_horizon.rgb, haze_k * (1.0 - depth));
	bool object = use_instance_uniforms && i_albedo.a > 0.5;
	if (object) {
		base = i_albedo.rgb * g_ambient.rgb;
	}
	base *= 1.0 + (hs(seed, 9.0, 9.0) - 0.5) * 0.10;
	vec3 shade = shade_of(base);
	if (object) {
		shade = mix(base, shade, object_shade_mix);
	}
	float back = g_backlight * g_celestial.x;
	vec4 m = texture(moss_tex, p * r_px / moss_px + seed * 5.0);
	vec2 mn = m.gb * 2.0 - 1.0;
	vec2 dome_c = vec2(0.0, crown_y - 0.62 * hk);

	// Painter's order, back to front: each lobe is a felted ball (lit toward the key, soft shade
	// below) and casts a soft contact shadow on the lobes behind it, so the canopy reads as a pile
	// of felt cushions rather than one blob.
	vec3 c = shade;
	float a_c = 0.0;
	float union_d = 1e3;
	float front_n = 0.0;
	for (int k = 0; k < 8; k++) {
		vec3 L = lobe(seed, k, crown_y, hk, tree);
		float dl = length(p - L.xy) - L.z;
		union_d = smin(union_d, dl, 0.08);
		// Contact shadow of this lobe on what is already drawn behind it.
		float ring = (1.0 - smoothstep(0.0, 0.11, dl)) * step(0.0, dl);
		c = mix(c, shade, ring * 0.32 * a_c);
		float cov = 1.0 - smoothstep(-0.7 * fw, 0.7 * fw, dl + fuzz);
		vec2 nl = (p - L.xy) / L.z;
		vec2 nd = (p - dome_c) / vec2(0.95, 0.8);
		float lit = dot(normalize(nl * 0.55 + nd * 0.45 + mn * 0.25 + vec2(0.0, -0.25)), kd);
		vec3 lc = mix(base, shade, clamp(-lit, 0.0, 1.0) * 0.48 + back * 0.30);
		lc += (g_key.rgb * 0.65 + base * 0.35) * clamp(lit, 0.0, 1.0) * 0.20 * (0.5 + g_ground_light * 2.5) * (1.0 - 0.7 * back);
		// The underside of each ball turns away from the sky.
		lc = mix(lc, shade, smoothstep(0.2, 1.0, nl.y) * 0.30);
		lc *= 1.0 + (hs(seed, float(k), 7.0) - 0.5) * 0.08;
		c = mix(c, lc, cov);
		if (cov > 0.5) {
			front_n = dot(normalize(nl), kd);
		}
		a_c = max(a_c, cov);
	}
	// A low skirt joins the lobes to the ground (bushes) or to the trunk (trees).
	float skirt = sd_ellipse(p - vec2(0.0, crown_y - 0.18), vec2(tree ? 0.5 : 0.86, 0.22));
	float a_s = (1.0 - smoothstep(-0.7 * fw, 0.7 * fw, skirt + fuzz)) * (1.0 - a_c);
	c = mix(c, mix(shade, base, 0.35), a_s);
	a_c = max(a_c, a_s);
	union_d = min(union_d, skirt);
	float trunk = 1e3;
	if (tree) {
		trunk = sd_capsule(p, vec2(0.0, 0.0), vec2(0.0, crown_y - 0.1), 0.085 + 0.04 * (1.0 + p.y / max(-crown_y, 0.1)));
	}
	float a_t = 1.0 - smoothstep(-0.7 * fw, 0.7 * fw, trunk);
	float a = max(a_c, a_t);
	if (a < 0.004) {
		discard;
	}
	// The base of the canopy sinks into shade (it meets the ground or the trunk).
	c = mix(c, shade, smoothstep(crown_y - 0.32, crown_y + 0.05, p.y) * 0.40 * a_c);
	// Felt cushion texture.
	float ml = dot(mn, kd);
	c = mix(c, shade, clamp(-ml, 0.0, 1.0) * 0.12);
	c *= 1.0 + (m.a - 0.5) * 0.10;
	// Contre-jour rim on the silhouette (golden, dawn): a thin glowing edge on the lit side.
	float edge = smoothstep(-3.0 * fw, 0.0, union_d + fuzz) * a_c;
	float facing = clamp(front_n * 0.7 + 0.3, 0.0, 1.0);
	c += g_key.rgb * g_rim * g_backlight * 0.55 * edge * facing;
	// Trunk: bark-dark, tinted by the canopy's shade.
	vec3 bark = mix(shade, base * vec3(0.78, 0.66, 0.58), 0.45) * trunk_k / 0.55;
	c = mix(c, bark, a_t * (1.0 - a_c));
	vec2 p_design = v_canvas - g_world_offset;
	if (g_cloud_shadow > 0.001) {
		c = mix(c, shade_of(c), cloud_shadow(p_design) * 1.4);
	}
	if (object) {
		c = mix(c, g_sky_horizon.rgb, object_haze_k * (1.0 - g_lights));
	}
	c += sun_veil(v_canvas, mix(0.6, 0.25, depth));
	c = mix(c, mix(g_sky_horizon.rgb, g_glow.rgb, 0.2), g_mist * 0.3 * (1.0 - depth));
	if (g_lights > 0.001) {
		c = apply_lamp(c, lamp_weight(p_design) * 0.7);
	}
	COLOR = vec4(finish(c, p * r_px / PX_PER_DP + seed * 17.0, FRAGCOORD.xy, GRAIN_TERRAIN), a);
}
