// Creature contact + cast shadow (docs/ART_BIBLE.md §4.12), drawn by Mossling/Shadow before the
// body. Lives with the creature shaders so the creature team can tune it with the fur; props use
// fx/contact_shadow.gdshader with the same algorithm.
//   1. contact core at the feet (a tight occlusion and a soft core, widened by squash);
//   2. cast ellipse pushed away from the light, len = clamp(0.35 / elev, 0.35, 2.5);
//   3. a = max(core, cast * 0.6) * g_shadow_alpha * (1 - 0.6 hop) * (1 - 0.4 g_rain);
//   4. tinted with g_shadow (never black), TPDF dithered.
shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

// x: body width px, y: body height px, z: hop 0..1 (apex = 1), w: alpha multiplier (fade in/out)
instance uniform vec4 i_shadow = vec4(150.0, 150.0, 0.0, 1.0);
// x: squash (1 = rest), y: lean rad, z: in-shade 0..1 (sheltered spots), w: unused
instance uniform vec4 i_shadow2 = vec4(1.0, 0.0, 0.0, 0.0);

const float CORE_W = 0.55;         // §4.12 contact core half-width (x body width, / squash)
const float CORE_H = 0.13;         // half-height (x body width)
const float CORE_SOFT_PX = 18.0;
const float CAST_ALPHA = 0.6;
const float CAST_FADE = 0.85;      // long cast shadows fade toward their far end
const float OCC_W = 0.40;          // tight occlusion right under the body
const float OCC_H = 0.05;
const float OCC_SOFT_PX = 7.0;

varying vec2 v_local;
varying flat vec3 v_cast;          // xy: cast offset direction (screen, y down) * len; z: len

void vertex() {
	v_local = VERTEX;
	// world_light: the same key direction and shadow length as every prop shadow (rubric #5)
	vec2 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	vec2 l = key_dir(origin);
	float len = shadow_length();
	v_cast = vec3(vec2(-l.x * 0.8, 0.10 + 0.30 * g_backlight) * len, len);
}

float soft_ellipse(vec2 p, vec2 r, float soft) {
	float k = length(p / r);
	float d = (k - 1.0) * min(r.x, r.y);
	return 1.0 - smoothstep(-soft * 0.5, soft, d);
}

void fragment() {
	float W = i_shadow.x;
	float H = i_shadow.y;
	float hop = clamp(i_shadow.z, 0.0, 1.0);
	float squash = max(i_shadow2.x, 0.5);
	vec2 p = v_local;
	// the shadow shrinks to 70 % at the hop apex (§5.7 hop)
	float shrink = mix(1.0, 0.7, hop);
	vec2 core_r = vec2(CORE_W * W / squash, CORE_H * W) * shrink;
	float core = soft_ellipse(p - vec2(i_shadow2.y * H * 0.15, 0.0), core_r, CORE_SOFT_PX);
	float occ = soft_ellipse(p - vec2(0.0, -0.01 * W), vec2(OCC_W * W / squash, OCC_H * W) * shrink, OCC_SOFT_PX);
	// cast shadow: elongated along its offset, softer with length
	vec2 off = v_cast.xy * H * 0.5;
	float len = v_cast.z;
	vec2 cdir = length(off) > 1e-3 ? normalize(off) : vec2(0.0, 1.0);
	vec2 rel = p - off * 0.6;
	vec2 q = vec2(dot(rel, vec2(cdir.y, -cdir.x)), dot(rel, cdir));
	vec2 cast_r = vec2(CORE_W * W * 0.85, max(CORE_H * W, length(off) * 0.75 + CORE_H * W)) * shrink;
	float cast = soft_ellipse(q, cast_r, mix(18.0, 36.0, clamp((len - 0.35) / 2.15, 0.0, 1.0)));
	// a long shadow thins out away from the feet (its penumbra grows with distance)
	float along = clamp((dot(p, cdir) + CORE_H * W) / max(2.0 * cast_r.y, 1.0), 0.0, 1.0);
	cast *= 1.0 - CAST_FADE * smoothstep(0.15, 1.0, along);
	float a = max(max(core, occ * 1.35), cast * CAST_ALPHA);
	a *= g_shadow_alpha * (1.0 - 0.6 * hop) * (1.0 - 0.4 * g_rain) * i_shadow.w;
	a *= 1.0 - 0.5 * i_shadow2.z;
	a *= COLOR.a;                                            // node modulate (arrive / leave fades)
	a += tpdf(FRAGCOORD.xy);
	COLOR = vec4(g_shadow.rgb, clamp(a, 0.0, 1.0));
}
