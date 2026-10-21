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
const float AMBIENT_MIX = 0.35;
const float UMB_FRINGE_PX = 3.0;    // umbrella felt fringe length (local px)    // feedback stamps keep their colour at night (readability)

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

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float kind = u_kind;
	float alpha = COLOR.a;
	float prog = COLOR.r;
	vec2 p = vec2(v_local.x, -v_local.y) / max(u_half, 1e-3);   // -1..1, y up
	float aa = max(length(fwidth(p)), 1e-3) * 0.8;
	vec3 amb = mix(vec3(1.0), g_ambient.rgb, AMBIENT_MIX);
	vec3 col = vec3(0.0);
	float a = 0.0;
	if (kind < 0.5) {
		// heart: soft felt heart with a top-left highlight
		vec2 hp = p * 1.18 + vec2(0.0, 0.62);
		float d = sd_heart(hp) - 0.06;
		a = 1.0 - smoothstep(-aa, aa, d);
		float hl = 1.0 - smoothstep(0.0, 0.22, length(hp - vec2(-0.3, 0.78)) - 0.06);
		float edge = smoothstep(-0.25, 0.0, d);
		col = mix(u_a.rgb, u_b.rgb, edge * 0.35);
		col = mix(col, u_c.rgb, hl * 0.55);
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
		col = u_a.rgb;
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
		// leaf umbrella (QA round 1: same felt hand as the creatures): a round leaf in the tone mask
		// (lit / shade / detail), midrib and veins, a short petiole; felted fibre fringe on the leaf
		// edge, the underside in shade, key rim, ambient multiply and object-anchored grain.
		vec2 lp = p - vec2(0.0, 0.18);
		float dl = sd_vesica(vec2(lp.x * 0.62, lp.y * 1.55 + 0.02), 0.62, 0.5) - 0.02;
		float dpet = sd_segment(p, vec2(0.0, 0.05), vec2(0.03, -0.95)) - mix(0.022, 0.034, smoothstep(-0.95, 0.0, p.y));
		float px = u_half;                                   // local px per unit
		float dl_px = dl * px;
		// fibre fringe: anisotropic noise along the edge, 2-3 px long
		float ang = atan(lp.y, lp.x);
		float fib = smoothstep(0.4, 0.85, vnoise(vec2(ang * 38.0, dl_px * 0.6)));
		float fr_t = clamp(dl_px / UMB_FRINGE_PX, 0.0, 1.0);
		float fringe = dl_px > 0.0 ? fib * (1.0 - fr_t) * (1.0 - fr_t) * 0.8 : 0.0;
		float wob = (vnoise(vec2(ang * 6.0, 1.7)) - 0.5) * 1.2;
		float core_l = 1.0 - smoothstep(-aa, aa, dl + wob / px);
		float core_p = 1.0 - smoothstep(-aa, aa, dpet);
		a = max(max(core_l, core_p), fringe);
		float under = smoothstep(0.05, -0.2, lp.y);       // the underside reads in shade
		col = mix(u_a.rgb, u_b.rgb, under * 0.6 + 0.25 * smoothstep(-0.2, 0.0, dl));
		float rib = 1.0 - smoothstep(0.012, 0.03, abs(lp.x));
		float veins = 1.0 - smoothstep(0.015, 0.035, abs(fract((lp.y + abs(lp.x) * 0.7) * 3.2) - 0.5) * 0.3);
		veins *= step(0.0, -dl) * smoothstep(0.05, 0.2, abs(lp.x));
		col = mix(col, u_c.rgb, max(rib * step(dl, 0.0), veins * 0.35) * 0.6);
		col = mix(col, u_b.rgb * 0.92, core_p * (1.0 - core_l) * 0.6);
		// felt mottling + lighter fibre tips in the fringe
		col *= 1.0 + (vnoise(lp * 7.0) - 0.5) * 0.06;
		col = mix(col, mix(col, u_c.rgb, 0.5), (1.0 - core_l) * core_p * 0.0 + fringe * (1.0 - core_l) * 0.6);
		// rim from the key so the umbrella belongs to the same light as the creatures
		float rim = smoothstep(-0.12, 0.0, dl) * clamp(dot(normalize(lp + 1e-4), normalize(vec2(g_sun_dir.x, -g_sun_dir.y))), 0.0, 1.0);
		col += g_key.rgb * rim * g_rim * 0.35;
		col *= g_ambient.rgb;
		col = finish(col, p * px / PX_PER_DP, FRAGCOORD.xy, GRAIN_OBJECT);
	}
	a *= alpha;
	col += kind > 3.5 ? 0.0 : tpdf(FRAGCOORD.xy);
	COLOR = vec4(col * a, a);
}
