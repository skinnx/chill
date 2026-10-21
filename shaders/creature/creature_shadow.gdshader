// Creature contact + cast shadow (docs/ART_BIBLE.md §4.12), one SdfQuad per mossling, drawn under
// the bodies. Same algorithm and light as the prop shadows (fx/contact_shadow.gdshader +
// world_light cast_offset_k), so creatures and props throw one family of shadows (rubric #5, #9):
//   1. contact core at the feet (a tight occlusion and a soft core, widened by squash);
//   2. cast ellipse pushed away from the light: offset = cast_offset_k(key) x height / 2, i.e.
//      2.5x long toward the viewer at golden hour, darker with backlight;
//   3. a = max(core, cast) * g_shadow_alpha * (1 - 0.6 hop) * (1 - 0.4 g_rain);
//   4. tinted with g_shadow (never black), TPDF dithered.
// Batching (Art Bible §4.19, <= 100 draw calls): the quad's rect is in body units (x in body
// widths, y in body heights) and the node scale carries the body size in px; the per-shadow state
// rides on one instance uniform and the node modulate stays white (the GLES3 canvas renderer
// breaks a batch on any modulate change, never on instance uniforms), so every meadow shadow,
// drawn consecutively from the layer's shadow host, shares one batch.
shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

const float CORE_W = 0.55;         // §4.12 contact core half-width (x body width, / squash)
const float CORE_H = 0.13;         // half-height (x body width)
const float CORE_SOFT_PX = 18.0;
const float CAST_ALPHA = 0.72;
const float CAST_FADE = 0.85;      // long cast shadows fade toward their far end
const float CAST_BACKLIGHT_GAIN = 0.5;   // fx/contact_shadow backlight_gain
const float OCC_W = 0.40;          // tight occlusion right under the body
const float OCC_H = 0.05;
const float OCC_SOFT_PX = 7.0;
const float RAIN_FADE = 0.4;

// x hop 0..1 (apex = 1), y squash (1 = rest), z lean rad, w alpha (fade x shelter)
instance uniform vec4 i_shadow = vec4(0.0, 1.0, 0.0, 1.0);

varying vec2 v_px;                 // px from the feet (y down), depth-scaled
varying flat vec4 v_size;          // x body width px, y body height px, zw cast offset px
varying flat float v_len;

void vertex() {
	vec2 sx = MODEL_MATRIX[0].xy;
	vec2 sy = MODEL_MATRIX[1].xy;
	vec2 size = vec2(length(sx), length(sy));
	v_px = VERTEX * size;
	// world_light: the same key direction and shadow length as every prop shadow (rubric #5)
	vec2 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	vec2 off = cast_offset_k(key_dir(origin)) * size.y * 0.5;
	v_size = vec4(size, off);
	v_len = shadow_length();
}

float soft_ellipse(vec2 p, vec2 r, float soft) {
	float k = length(p / r);
	float d = (k - 1.0) * min(r.x, r.y);
	return 1.0 - smoothstep(-soft * 0.5, soft, d);
}

void fragment() {
	float W = v_size.x;
	float H = v_size.y;
	float hop = clamp(i_shadow.x, 0.0, 1.0);
	float squash = max(i_shadow.y, 0.5);
	float lean = i_shadow.z;
	vec2 p = v_px;
	// the shadow shrinks to 70 % at the hop apex (§5.7 hop)
	float shrink = mix(1.0, 0.7, hop);
	vec2 core_r = vec2(CORE_W * W / squash, CORE_H * W) * shrink;
	float core = soft_ellipse(p - vec2(lean * H * 0.15, 0.0), core_r, CORE_SOFT_PX);
	float occ = soft_ellipse(p - vec2(0.0, -0.01 * W), vec2(OCC_W * W / squash, OCC_H * W) * shrink, OCC_SOFT_PX);
	// cast shadow: an ellipse centred on the offset, elongated along it, softer as it lengthens
	vec2 off = v_size.zw;
	float ol = length(off);
	vec2 u = ol > 0.5 ? off / ol : vec2(0.0, 1.0);
	vec2 v = vec2(-u.y, u.x);
	vec2 q = p - off;
	float lu = CORE_H * W + ol;
	float lv = CORE_W * W * mix(0.9, 0.7, clamp(ol / max(W, 1.0), 0.0, 1.0)) * shrink;
	float soft = mix(CORE_SOFT_PX, CORE_SOFT_PX * 2.0, clamp((v_len - 0.35) / 2.15, 0.0, 1.0));
	float cast = soft_ellipse(vec2(dot(q, v), dot(q, u)), vec2(lv, lu), soft);
	// a long shadow thins out away from the feet (its penumbra grows with distance)
	float along = clamp(dot(p, u) / max(ol + lu, 1.0), 0.0, 1.0);
	cast *= mix(1.0, 0.7, along);
	cast *= 1.0 - CAST_FADE * smoothstep(0.55, 1.0, along);
	cast *= CAST_ALPHA * (1.0 + CAST_BACKLIGHT_GAIN * g_backlight) * (1.0 - 0.5 * hop);
	float a = max(max(core, occ * 1.35), cast);
	a *= g_shadow_alpha * (1.0 - 0.6 * hop) * (1.0 - RAIN_FADE * g_rain) * i_shadow.w * COLOR.a;
	if (a < 0.002) {
		discard;
	}
	COLOR = vec4(g_shadow.rgb + tpdf(FRAGCOORD.xy), clamp(a + tpdf(FRAGCOORD.xy + 3.1), 0.0, 1.0));
}
