// Creature feedback stamps (docs/ART_BIBLE.md §5.2 Fx, §5.7, §10.3): hearts on pet release, the
// sleepy "z", sparkles, the long-press fill ring and the rain leaf umbrella. SDF, so they stay
// crisp at any scale; one shared material, per-stamp instance uniforms (pooled nodes).
// Colours come from palettes.json fx / materials through the instance uniforms (never literals).
shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

#include "res://shaders/inc/globals.gdshaderinc"
#include "res://shaders/inc/noise.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

// One shared material per stamp kind (no instance uniforms: on GLES3 every canvas item that uses
// them reserves 16 slots of the global uniform buffer, ART_BIBLE §4.0). Per stamp: COLOR.a is
// the alpha (node modulate), COLOR.r the ring progress; size comes from the node scale.
uniform float u_kind = 0.0;                 // 0 heart, 1 z, 2 sparkle, 3 ring, 4 leaf umbrella
uniform float u_half = 24.0;                // quad half size in local px (SdfQuad rect)
uniform vec4 u_a : source_color = vec4(1.0);   // main colour (lit)
uniform vec4 u_b : source_color = vec4(1.0);   // shade colour
uniform vec4 u_c : source_color = vec4(1.0);   // detail colour

const float RING_STROKE = 0.085;   // ring stroke as a fraction of the radius
const float RING_TRACK_A = 0.28;
const float AMBIENT_MIX = 0.35;               // feedback stamps keep their colour at night (readability)
const vec2 UMB_P0 = vec2(0.55, -0.95);   // petiole foot (the pivot, at the paw)
const vec2 UMB_P1 = vec2(0.58, -0.15);
const vec2 UMB_P2 = vec2(0.44, 0.30);
const vec2 UMB_P3 = vec2(0.12, 0.44);    // attaches under the canopy
const vec2 UMB_PAW = vec2(0.53, -0.80);
const float UMB_FRINGE_PX = 3.0;    // umbrella felt fringe length (local px)

const float HEART_OUTLINE = 0.11;           // cream outline width (heart units)
const float UMB_TIP_Y = 0.0;                // canopy tips end here (no rim under the hollow)
const float UMB_TONE = 0.84;                // canopy value step below the lit leaf tone

varying vec2 v_local;

float dot2(vec2 v) {
	return dot(v, v);
}

// iq heart, bottom tip at the origin, height ~1.1 (y up)
float sd_heart(vec2 p) {
	p.x = abs(p.x);
	if (p.y + p.x > 1.0) {
		return sqrt(dot2(p - vec2(0.25, 0.75))) - sqrt(2.0) / 4.0;
	}
	return sqrt(min(dot2(p - vec2(0.0, 1.0)), dot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

float sd_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

float sd_vesica(vec2 p, float hl, float hw) {
	float r = 0.5 * (hl * hl / hw + hw);
	float d = r - hw;
	p = abs(p);
	float b = sqrt(max(r * r - d * d, 0.0));
	return ((p.y - b) * d > p.x * b) ? length(p - vec2(0.0, b)) : length(p - vec2(-d, 0.0)) - r;
}

float smin_fx(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

float sd_ellipse_fx(vec2 p, vec2 r) {
	float k0 = length(p / r);
	float k1 = length(p / (r * r));
	return k0 * (k0 - 1.0) / max(k1, 1e-4);
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float kind = u_kind;
	float alpha = COLOR.a;   // the umbrella reads COLOR.rgb as the paw (fur) colour
	float prog = COLOR.r;
	vec2 p = vec2(v_local.x, -v_local.y) / max(u_half, 1e-3);   // -1..1, y up
	float aa = max(length(fwidth(p)), 1e-3) * 0.8;
	vec3 amb = mix(vec3(1.0), g_ambient.rgb, AMBIENT_MIX);
	vec3 col = vec3(0.0);
	float a = 0.0;
	if (kind < 0.5) {
		// heart: soft felt heart with a top-left highlight
		// round 4 (QA r3 c7: hearts read small and thin over the meadow): a cream felt outline
		// keeps them legible on any background, a soft lower shade gives them a little volume
		vec2 hp = p * 1.3 + vec2(0.0, 0.66);
		float d = sd_heart(hp) - 0.06;
		float inner = 1.0 - smoothstep(-aa, aa, d);
		a = 1.0 - smoothstep(-aa, aa, d - HEART_OUTLINE);
		float hl = 1.0 - smoothstep(0.0, 0.22, length(hp - vec2(-0.3, 0.78)) - 0.06);
		float edge = smoothstep(-0.25, 0.0, d);
		col = mix(u_a.rgb, u_b.rgb, edge * 0.35 + 0.3 * (1.0 - smoothstep(0.0, 0.7, hp.y)));
		col = mix(col, u_c.rgb, hl * 0.6);
		col = mix(u_c.rgb, col, inner);
		col *= amb;
	} else if (kind < 1.5) {
		// "z": three round-capped strokes, a little italic
		vec2 zp = vec2(p.x - p.y * 0.12, p.y);
		float w = 0.14;
		float d = min(min(sd_segment(zp, vec2(-0.45, 0.48), vec2(0.42, 0.48)),
				sd_segment(zp, vec2(0.42, 0.48), vec2(-0.45, -0.48))),
				sd_segment(zp, vec2(-0.45, -0.48), vec2(0.45, -0.48))) - w;
		a = 1.0 - smoothstep(-aa, aa, d);
		float glow = (1.0 - smoothstep(0.0, 0.45, d)) * 0.25;
		a = max(a, glow);
		col = u_a.rgb * amb;
	} else if (kind < 2.5) {
		// sparkle: 4-point astroid star with a soft core
		vec2 q = abs(p);
		float d = pow(q.x, 0.55) + pow(q.y, 0.55) - 0.82;
		a = 1.0 - smoothstep(-0.06, 0.06, d);
		a = max(a, (1.0 - smoothstep(0.0, 0.5, length(p))) * 0.5);
		// gold star, cream core (round 4: white sparkles vanished over pale fur)
		col = mix(u_b.rgb, u_a.rgb, 1.0 - smoothstep(0.08, 0.42, length(p)));
	} else if (kind < 3.5) {
		// long-press fill ring: faint track + a filled arc growing clockwise from the top
		float r = length(p);
		float ring = abs(r - 0.86) - RING_STROKE;
		float ra = 1.0 - smoothstep(-aa, aa, ring);
		float ang = atan(p.x, p.y);                  // 0 at the top, clockwise positive
		ang = ang < 0.0 ? ang + TAU : ang;
		float fill = 1.0 - smoothstep(prog * TAU - 0.02, prog * TAU + 0.02, ang);
		a = ra * mix(RING_TRACK_A, 1.0, fill);
		col = u_a.rgb;
	} else {
		// leaf umbrella (QA r2: held, not floating): a felt leaf canopy seen from the side - a dome
		// whose two tips droop down (a crescent of two ellipses), radiating veins, the underside in
		// shade, a key rim on the top; a curved petiole down to the paw that grips it (the paw is
		// the creature's own fur colour, COLOR.rgb). Tone mask u_a lit / u_b shade / u_c detail.
		// geometry for a paw on the right (+x); MosslingFx mirrors the pivot for the left hand
		vec2 cq = p - vec2(0.0, 0.30);
		float d_out = sd_ellipse_fx(cq, vec2(0.95, 0.50));
		float d_in = sd_ellipse_fx(p - vec2(0.0, 0.14), vec2(0.80, 0.30));
		float dl = max(d_out, -d_in);
		// round 4: the outer ellipse dipped below the inner one, so a hairline rim closed the
		// crescent into a lens ("wireframe" in QA r3); the canopy now ends at its drooping tips
		dl = max(dl, UMB_TIP_Y - p.y);
		// a little drip tip on the far end (leaf apex), so it reads as a leaf, not a bowl
		dl = smin_fx(dl, sd_segment(p, vec2(-0.80, 0.20), vec2(-0.98, 0.04)) - 0.03, 0.05);
		// petiole: up along the body's edge from the paw, then a cane bend in to the canopy
		float r_pet = 0.032;
		float dpet = min(min(sd_segment(p, UMB_P0, UMB_P1), sd_segment(p, UMB_P1, UMB_P2)), sd_segment(p, UMB_P2, UMB_P3)) - r_pet;
		vec2 pawq = (p - UMB_PAW) / vec2(0.15, 0.125);
		float dpaw = (length(pawq) - 1.0) * 0.125;
		float px = u_half;                                   // local px per unit
		float dl_px = dl * px;
		// felt fibre fringe on the canopy edge, 2-3 px
		float ang = atan(cq.y, cq.x);
		float fib = smoothstep(0.4, 0.85, vnoise(vec2(ang * 38.0, dl_px * 0.6)));
		float fr_t = clamp(dl_px / UMB_FRINGE_PX, 0.0, 1.0);
		float fringe = dl_px > 0.0 ? fib * (1.0 - fr_t) * (1.0 - fr_t) * 0.8 : 0.0;
		float wob = (vnoise(vec2(ang * 6.0, 1.7)) - 0.5) * 1.2;
		float core_l = 1.0 - smoothstep(-aa, aa, dl + wob / px);
		float core_p = 1.0 - smoothstep(-aa, aa, dpet);
		float core_w = 1.0 - smoothstep(-aa, aa, dpaw);
		a = max(max(max(core_l, core_p), fringe), core_w);
		// canopy: lit dome, the underside (near the inner curve) in shade
		float under = smoothstep(0.10, 0.0, d_in + 0.10);
		col = mix(u_a.rgb, u_b.rgb, under * 0.7 + 0.2 * smoothstep(-0.12, 0.0, dl));
		// radiating veins from the stem's attach point + the midrib along the dome
		vec2 vq = p - vec2(0.0, 0.40);
		float va = atan(vq.x, vq.y);
		float vcell = abs(fract(va / (PI / 7.0)) - 0.5) * length(vq);
		float veins = (1.0 - smoothstep(0.008, 0.022, vcell)) * smoothstep(0.05, 0.25, length(vq));
		float rib = 1.0 - smoothstep(0.010, 0.026, abs(d_out + 0.12));
		col = mix(col, u_c.rgb, max(veins * 0.5, rib * 0.35) * core_l * (1.0 - under * 0.5));
		col *= 1.0 + (vnoise(p * 7.0) - 0.5) * 0.06;
		col = mix(col, mix(col, u_c.rgb, 0.5), fringe * (1.0 - core_l) * 0.6);
		// petiole under the canopy, the paw over the petiole
		vec3 pet_col = mix(u_b.rgb, u_a.rgb, 0.3) * (0.9 + 0.1 * smoothstep(-0.02, 0.02, dpet + r_pet * 0.5));
		col = mix(col, pet_col, core_p * (1.0 - core_l));
		vec3 fur = COLOR.rgb;
		// a felt mitten: lit on top, a soft darker rim so it separates from the same-coloured body
		vec3 paw_col = fur * (0.84 + 0.16 * smoothstep(-0.7, 0.7, pawq.y));
		paw_col *= 1.0 - 0.16 * smoothstep(0.55, 1.0, length(pawq));
		paw_col += fur * 0.08 * (1.0 - smoothstep(0.0, 0.5, length(pawq - vec2(-0.25, 0.45))));
		col = mix(col, paw_col, core_w);
		a = max(a, core_w);
		// rim from the key so the umbrella belongs to the same light as the creatures
		float top = smoothstep(-0.12, 0.0, d_out) * step(0.0, -d_in);
		float rim = top * clamp(dot(normalize(cq + 1e-4), normalize(vec2(g_sun_dir.x, -g_sun_dir.y))) * 0.6 + 0.4, 0.0, 1.0);
		// round 4 (QA r3 rain: the pale leaf read as a see-through outline): the canopy sits a step
		// darker than the misty meadow so it reads as a solid silhouette, the key rim on top
		col *= mix(1.0, UMB_TONE, core_l);
		col += g_key.rgb * rim * g_rim * 0.35 * core_l;
		col *= g_ambient.rgb;
		col = finish(col, p * px / PX_PER_DP, FRAGCOORD.xy, GRAIN_OBJECT);
	}
	a *= alpha;
	col += kind > 3.5 ? 0.0 : tpdf(FRAGCOORD.xy);
	COLOR = vec4(col * a, a);
}
