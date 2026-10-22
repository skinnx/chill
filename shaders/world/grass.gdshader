// Meadow dressing (Art Bible §4.6, §6.4; round-2 directive 2): soft, rounded, FELTED clumps drawn
// analytically on small MultiMesh quads, so they stay crisp at any zoom and batch per band.
//   kind 0  grass clump: 4-6 tapered blades with rounded tips fanning from a felted base, a dark
//           root, lit tips, the side facing the light lighter, a fuzzy fibre fringe and a soft
//           contact shadow that grounds it (never a hay stamp);
//   kind 1  clover patch: 2-4 trefoils of rounded leaflets with pale chevrons on thin stems;
//   kind 2  moss mound: a small felted dome with cushion texture (art/fx/moss_tile.png);
//   kind 3  wild micro-flowers: 2-4 tiny 5-petal heads (flora tokens) on stems over a few blades;
//   kind 4  pebble (round 5, near bank): a smooth domed stone (materials pebble_alt / stone_warm),
//           key-lit top, tinted underside, a moss fleck, sitting in the ground's contact shadow.
// Grass, clover and moss are terrain (palette slots); flower petals are objects (x g_ambient).
// Every kind sways at k/600 Hz with the travelling gust (rooted: amplitude grows with height).
//
// Mesh contract (GrassField.quad_mesh): local VERTEX px at depth 1, root at (0, 0), y up negative,
// quad x -QUAD_HW..QUAD_HW, y -QUAD_TOP..QUAD_BOTTOM.
// Instance COLOR: r tint 0..1, g seed 0..1, b kind / 4, a height k (0.7..1.3).
// INSTANCE_CUSTOM: x sway k (absolute), y sway amplitude px at the top, z phase rad, w lean px.
shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/lamps.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"
#include "res://shaders/inc/sdf.gdshaderinc"

uniform vec4 grass_tip : source_color = vec4(0.537, 0.729, 0.537, 1.0);
uniform vec4 grass_root : source_color = vec4(0.286, 0.576, 0.471, 1.0);
// The ground under the dressing (same slots as the meadow): roots and shadows sit in it.
uniform vec4 ground_back_lit : source_color = vec4(0.502, 0.718, 0.537, 1.0);
uniform vec4 ground_front_lit : source_color = vec4(0.447, 0.686, 0.490, 1.0);
// Wild flower petals (palettes.json flora tokens): daisy, buttercup, forget-me-not, clover.
uniform vec4 petal_a : source_color = vec4(0.984, 0.953, 0.894, 1.0);
uniform vec4 petal_b : source_color = vec4(1.0, 0.847, 0.467, 1.0);
uniform vec4 petal_c : source_color = vec4(0.737, 0.831, 0.969, 1.0);
uniform vec4 petal_d : source_color = vec4(0.957, 0.776, 0.827, 1.0);
uniform vec4 flower_eye : source_color = vec4(1.0, 0.784, 0.431, 1.0);
// Pebbles (palettes.json materials pebble_alt and stone_warm: lit, shade).
uniform vec4 pebble_lit_a : source_color = vec4(0.765, 0.788, 0.847, 1.0);
uniform vec4 pebble_shade_a : source_color = vec4(0.624, 0.639, 0.686, 1.0);
uniform vec4 pebble_lit_b : source_color = vec4(0.863, 0.827, 0.784, 1.0);
uniform vec4 pebble_shade_b : source_color = vec4(0.718, 0.675, 0.651, 1.0);
uniform sampler2D moss_tex : filter_linear_mipmap, repeat_enable;
uniform float fringe_px = 1.5;
// Round 5 (Director: "felted, fibre fringe, soft lost edges, not flat vector stickers"): a fine
// fibre layer (high-frequency noise across the edge), an edge that softens toward the tips and on
// the side turned from the light, a translucent halo of loose fibres outside the silhouette (lit by
// the key at golden), and a gentle inner value drift.
uniform float fibre_px = 1.3;
uniform vec2 lost_edge_px = vec2(0.4, 2.0);
uniform float halo_px = 2.6;
uniform float halo_alpha = 0.42;
uniform float drift_k = 0.07;
uniform float shadow_alpha = 0.30;
uniform float tint_l = 0.05;
// Round 5b (Director: "soft out-of-focus ferns / clover / flowers below the brook"): a shallow
// depth of field on the near bank. Below dof_band.x the dressing's edges widen up to dof_px (an
// out-of-focus disc, never a hard sticker) and its local contrast relaxes toward the ground.
uniform vec2 dof_band = vec2(1700.0, 1990.0);
uniform float dof_px = 4.5;
uniform float dof_flatten = 0.22;

const int KIND_CLUMP = 0;
const int KIND_CLOVER = 1;
const int KIND_MOSS = 2;
const int KIND_FLOWERS = 3;
const int KIND_PEBBLE = 4;
const float BLADE_H = 30.0;
const float TIP_R = 1.9;
const float MOSS_TEX_PX = 46.0;
// Clumps lean a touch greener than the ground they grow from (lush, never straw).
const vec3 GREEN_SHIFT = vec3(0.93, 1.0, 0.92);

varying vec4 v_inst;
varying vec2 v_local;
varying vec2 v_canvas;
varying float v_flip;

void vertex() {
	v_inst = COLOR;
	v_local = VERTEX;
	// Height above the root, 0..1 over the blade height, for a rooted sway.
	float h = clamp(-VERTEX.y / BLADE_H, 0.0, 1.4);
	vec2 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy - g_world_offset;
	float k = INSTANCE_CUSTOM.x;
	float ph = INSTANCE_CUSTOM.z;
	float sway = sin(TAU * k / LOOP_S * g_time + ph) + 0.35 * sin(TAU * k * 2.13 / LOOP_S * g_time + ph + 1.7);
	float g = gust_at(world);
	float amp = INSTANCE_CUSTOM.y;
	// MODEL_MATRIX may mirror x: sway and lean are applied in local space, so undo the flip.
	v_flip = sign(MODEL_MATRIX[0].x);
	VERTEX.x += v_flip * (INSTANCE_CUSTOM.w + (sway * amp * (1.0 + GUST_AMP * g) + g * amp * 0.9) * wind_k() * g_motion) * h * h;
	v_canvas = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	COLOR = vec4(1.0);
}

float hs(float seed, float i, float salt) {
	return h12(vec2(seed * 173.0 + i * 7.31, salt));
}

// One tapered blade with a rounded tip: root r, tip direction ang (rad from vertical), length L,
// root half-width w0, outward bend at the tip. Returns (distance, t along the blade, side -1..1).
vec3 blade(vec2 p, vec2 root, float ang, float L, float w0, float bend) {
	vec2 dir = vec2(sin(ang), -cos(ang));
	vec2 perp = vec2(cos(ang), sin(ang));
	vec2 q = p - root;
	float y = dot(q, dir);
	float x = dot(q, perp);
	float t = clamp(y / L, 0.0, 1.0);
	x -= bend * t * t;
	float r = mix(w0, TIP_R, pow(t, 0.85));
	float d = length(vec2(x, y - t * L)) - r;
	return vec3(d, t, clamp(x / max(r, 0.5), -1.0, 1.0));
}

void fragment() {
	vec2 p = v_local;
	float seed = v_inst.g;
	int kind = int(floor(v_inst.b * 4.0 + 0.5));
	float hk = v_inst.a;
	vec2 kd = key_dir(v_canvas);
	// Light direction in the quad's local frame (mirrored quads see it mirrored).
	vec2 kl = vec2(kd.x * v_flip, kd.y);
	vec2 p_design = v_canvas - g_world_offset;
	float depth_t = smoothstep(760.0, 1500.0, p_design.y);
	vec3 ground = mix(ground_back_lit.rgb, ground_front_lit.rgb, depth_t);
	float dof = smoothstep(dof_band.x, dof_band.y, p_design.y);
	float fw = max(fwidth(p.x) + fwidth(p.y), 0.35) + dof_px * dof;
	float fuzz = (vnoise(p * 0.85 + seed * 41.0) - 0.5) * fringe_px;

	vec3 col = vec3(0.0);
	float a = 0.0;
	// Soft contact shadow: a small ellipse under the root, pushed away from the light.
	vec2 sh_off = vec2(-kd.x * 3.0 * v_flip, 2.0 + 2.0 * g_backlight);
	float sh_r = kind == KIND_MOSS ? 20.0 : (kind == KIND_CLOVER ? 18.0 : (kind == KIND_PEBBLE ? 15.0 : 13.0));
	float sh = 1.0 - smoothstep(0.35, 1.0, length((p - sh_off) / vec2(sh_r, sh_r * 0.32)));
	float sh_a = sh * shadow_alpha * g_shadow_alpha / 0.3 * (1.0 - 0.5 * g_rain);

	if (kind == KIND_CLUMP) {
		float n = 4.0 + floor(hs(seed, 0.0, 1.0) * 2.99);
		float d = 1e3;
		float bt = 0.0;
		float bs = 0.0;
		float bi = 0.0;
		for (int i = 0; i < 6; i++) {
			float fi = float(i);
			if (fi >= n) {
				break;
			}
			float u = (fi + 0.5) / n - 0.5;
			float ang = u * 1.35 + (hs(seed, fi, 2.0) - 0.5) * 0.3;
			float L = BLADE_H * hk * mix(0.62, 1.0, hs(seed, fi, 3.0)) * (1.0 - 0.3 * abs(u) * 2.0);
			float w0 = mix(4.2, 6.0, hs(seed, fi, 4.0));
			float bend = sign(ang) * mix(1.5, 5.0, hs(seed, fi, 5.0));
			vec2 root = vec2(u * 9.0 + (hs(seed, fi, 6.0) - 0.5) * 3.0, 0.0);
			vec3 b = blade(p, root, ang, L, w0, bend);
			if (b.x < d) {
				bt = b.y;
				bs = b.z;
				bi = fi;
			}
			d = smin(d, b.x, 1.2);
		}
		// The felted base the blades grow from.
		float base = sd_ellipse(p - vec2(0.0, -1.5), vec2(9.5, 4.5));
		if (base < d) {
			bt = 0.0;
		}
		float fib = (vnoise(p * vec2(2.6, 1.4) + seed * 23.0) - 0.5) * fibre_px;
		d = smin(d, base, 3.0) + fuzz + fib;
		// Lost edges: soft toward the tips and on the side turned away from the light.
		float away = clamp(-dot(normalize(vec2(bs, -0.35)), kl), 0.0, 1.0);
		float soft = mix(lost_edge_px.x, lost_edge_px.y, bt * bt) * (0.6 + 0.7 * away);
		a = 1.0 - smoothstep(-0.6 * fw - soft * 0.5, 0.6 * fw + soft, d);
		// Loose fibres beyond the silhouette (felt halo).
		float hair = smoothstep(0.52, 0.86, vnoise(p * vec2(3.4, 1.1) + seed * 31.0));
		float halo = (1.0 - smoothstep(0.0, halo_px, d)) * step(0.0, d) * hair * halo_alpha * smoothstep(0.15, 0.6, bt);
		a = max(a, halo);
		float tint = 1.0 + (v_inst.r - 0.5) * 2.0 * tint_l;
		// Felted green body: ground-coloured at the root (no dark "pot"), lighter and a touch warmer
		// toward the tips; the key only glows on the tip edges (contre-jour), never a straw fill.
		vec3 body_c = ground * tint * GREEN_SHIFT;
		vec3 tip_c = mix(body_c * 1.10, grass_tip.rgb * tint * GREEN_SHIFT, 0.35);
		col = mix(body_c * 0.90, tip_c, smoothstep(0.1, 0.95, bt));
		// Blade volume: the side facing the light catches it, the other turns to the tint.
		vec2 perp_side = vec2(bs, -0.35);
		float lit = dot(normalize(perp_side), kl);
		col = mix(col, shade_of(col), clamp(-lit, 0.0, 1.0) * 0.28);
		col += g_key.rgb * clamp(lit, 0.0, 1.0) * 0.08 * (0.4 + g_ground_light * 3.0);
		// Overlap: alternate blades a touch darker so the clump reads as a felted mass.
		col *= 1.0 - 0.07 * mod(bi, 2.0);
		// Soft occlusion only at the very root, and a contre-jour rim on the tip edges.
		col = mix(col, shade_of(col), (1.0 - smoothstep(0.0, 0.25, bt)) * 0.18);
		float edge = smoothstep(-2.2 * fw, 0.0, d);
		col += g_key.rgb * g_backlight * g_rim * (0.03 + 0.32 * edge) * bt * bt;
		// Fibre halo picks up the light (lighter, warmer); inner value drift breaks flat fills.
		col = mix(col, col * 1.12 + g_key.rgb * 0.10 * (0.3 + g_backlight), smoothstep(0.0, 1.0, d / halo_px + 0.5) * 0.6);
		col *= 1.0 + (vnoise(p * 0.18 + seed * 5.0) - 0.5) * 2.0 * drift_k;
	} else if (kind == KIND_CLOVER) {
		float n = 2.0 + floor(hs(seed, 0.0, 11.0) * 2.99);
		float d = 1e3;
		float chev = 0.0;
		float lit_n = 0.0;
		float edge_n = 0.0;
		float stem = 1e3;
		for (int j = 0; j < 4; j++) {
			float fj = float(j);
			if (fj >= n) {
				break;
			}
			vec2 c = vec2((hs(seed, fj, 12.0) - 0.5) * 22.0, -5.0 - hs(seed, fj, 13.0) * 8.0 * hk);
			float r = mix(5.6, 7.6, hs(seed, fj, 14.0));
			float rot = hs(seed, fj, 15.0) * TAU;
			stem = min(stem, sd_capsule(p, vec2(c.x * 0.7, 0.0), c, 0.7));
			for (int k = 0; k < 3; k++) {
				float ang = rot + float(k) * TAU / 3.0;
				vec2 dir = vec2(cos(ang), sin(ang) * 0.62);
				vec2 lc = c + dir * r * 0.82;
				vec2 lq = rot2(-atan(dir.y, dir.x)) * (p - lc);
				float dl = sd_ellipse(lq, vec2(r * 0.95, r * 0.72));
				// Heart notch at the outer end.
				dl = max(dl, -(length(lq - vec2(r * 0.98, 0.0)) - r * 0.22));
				if (dl < d) {
					lit_n = dot(normalize(dir + vec2(0.0, -0.5)), kd);
					float rr = length(lq / vec2(r * 0.95, r * 0.72));
					chev = (1.0 - smoothstep(0.05, 0.16, abs(rr - 0.48))) * step(0.0, -lq.x + r * 0.2);
					edge_n = smoothstep(0.75, 1.0, rr);
				}
				d = min(d, dl);
			}
		}
		float ds = stem;
		d = min(d, ds) + fuzz * 0.5 + (vnoise(p * 2.4 + seed * 19.0) - 0.5) * fibre_px * 0.8;
		a = 1.0 - smoothstep(-0.6 * fw - 0.3, 0.6 * fw + lost_edge_px.y * 0.5 * (0.5 + edge_n), d);
		// Clover reads a little cooler and lighter than the meadow, each leaflet domed.
		// Round 5: a deeper, cooler green than the moss (it read as a pale ghost on the ground), each
		// leaflet domed by the key with a soft pale chevron.
		vec3 leaf = mix(mix(ground, grass_root.rgb, 0.30), grass_tip.rgb, 0.12) * vec3(0.92, 1.04, 1.04);
		col = leaf;
		col = mix(col, shade_of(col), clamp(-lit_n, 0.0, 1.0) * 0.32);
		col += (g_key.rgb * 0.7 + col * 0.3) * clamp(lit_n, 0.0, 1.0) * 0.20;
		col = mix(col, mix(col, vec3(1.0), 0.30), chev * 0.35);
		col = mix(col, shade_of(col), step(ds, d + 0.01) * 0.25 + edge_n * 0.22);
	} else if (kind == KIND_MOSS) {
		vec2 r = vec2(mix(14.0, 20.0, hs(seed, 0.0, 21.0)), mix(7.5, 10.5, hs(seed, 0.0, 22.0)) * hk);
		vec2 c = vec2(0.0, -r.y * 0.62);
		vec2 q = (p - c) / r;
		float d = sd_ellipse(p - c, r);
		d = max(d, p.y - 1.5);
		vec4 m = texture(moss_tex, p / MOSS_TEX_PX + seed * 7.0);
		d += fuzz * 1.2 - (m.r - 0.5) * 1.6;
		a = 1.0 - smoothstep(-0.6 * fw, 0.6 * fw, d);
		vec2 nrm = q;
		float lit = dot(nrm, kl) * 0.7 + dot(m.gb * 2.0 - 1.0, kl) * 0.5;
		vec3 moss = mix(grass_tip.rgb, ground, 0.35) * 1.04;
		col = moss;
		col = mix(col, shade_of(col), clamp(-lit, 0.0, 1.0) * 0.30 + smoothstep(0.1, 1.0, q.y) * 0.28);
		col += (g_key.rgb * 0.6 + col * 0.4) * clamp(lit, 0.0, 1.0) * 0.22;
		col *= 1.0 + (m.a - 0.5) * 0.14;
		col += g_key.rgb * g_backlight * g_rim * 0.22 * smoothstep(0.2, -0.9, q.y);
	} else if (kind == KIND_PEBBLE) {
		vec2 r = vec2(mix(9.0, 13.5, hs(seed, 0.0, 41.0)), mix(5.0, 7.0, hs(seed, 0.0, 42.0)) * hk);
		vec2 c = vec2(0.0, -r.y * 0.55);
		vec2 q = (p - c) / r;
		float d = sd_ellipse(p - c, r) + (vnoise(p * 0.9 + seed * 9.0) - 0.5) * 0.8;
		d = max(d, p.y - 1.0);
		a = 1.0 - smoothstep(-0.8 * fw - 0.4, 0.8 * fw + 0.6, d);
		bool warm = hs(seed, 0.0, 43.0) > 0.55;
		vec3 lit_c = warm ? pebble_lit_b.rgb : pebble_lit_a.rgb;
		vec3 sh_cc = warm ? pebble_shade_b.rgb : pebble_shade_a.rgb;
		float up = clamp(-q.y * 0.8 + 0.3, 0.0, 1.0);
		float lit = dot(normalize(q + vec2(0.0, -0.6)), kl);
		vec3 alb = mix(sh_cc, lit_c, smoothstep(-0.4, 0.6, lit) * 0.7 + up * 0.3);
		col = light_object(alb, up, smoothstep(0.1, 1.0, q.y) * 0.8);
		// Felted moss fleck on the crown of some pebbles.
		float fleck = smoothstep(0.55, 0.75, vnoise(p * 0.5 + seed * 3.0)) * step(0.4, hs(seed, 0.0, 44.0)) * smoothstep(0.0, -0.6, q.y);
		col = mix(col, mix(grass_tip.rgb, ground, 0.3), fleck * 0.8);
		col += g_key.rgb * g_backlight * g_rim * 0.35 * smoothstep(0.55, 1.0, length(q)) * clamp(lit, 0.0, 1.0);
	} else {
		// Wild micro-flowers over a few short blades.
		float n = 2.0 + floor(hs(seed, 0.0, 31.0) * 2.99);
		float dl = 1e3;
		float lt = 0.0;
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float ang = (fi - 1.0) * 0.55 + (hs(seed, fi, 32.0) - 0.5) * 0.3;
			vec3 b = blade(p, vec2((fi - 1.0) * 4.0, 0.0), ang, 13.0 * mix(0.7, 1.0, hs(seed, fi, 33.0)), 3.2, sign(ang) * 2.0);
			if (b.x < dl) {
				lt = b.y;
			}
			dl = min(dl, b.x);
		}
		float dstem = 1e3;
		float dpet = 1e3;
		float deye = 1e3;
		float pick = 0.0;
		float pr = 0.0;
		for (int j = 0; j < 4; j++) {
			float fj = float(j);
			if (fj >= n) {
				break;
			}
			vec2 hc = vec2((hs(seed, fj, 34.0) - 0.5) * 22.0, -(9.0 + hs(seed, fj, 35.0) * 13.0) * hk);
			dstem = min(dstem, sd_capsule(p, vec2(hc.x * 0.5, 0.0), hc, 0.65));
			float rp = mix(2.0, 2.8, hs(seed, fj, 36.0));
			float rot = hs(seed, fj, 37.0) * TAU;
			vec2 q = p - hc;
			float dp = 1e3;
			for (int k = 0; k < 5; k++) {
				float ang = rot + float(k) * TAU / 5.0;
				vec2 pc = vec2(cos(ang), sin(ang) * 0.8) * rp * 1.05;
				dp = min(dp, length(q - pc) - rp);
			}
			if (dp < dpet) {
				pick = hs(seed, fj, 38.0);
				pr = length(q) / (rp * 2.1);
			}
			dpet = min(dpet, dp);
			deye = min(deye, length(q) - rp * 0.55);
		}
		float a_leaf = 1.0 - smoothstep(-0.6 * fw, 0.6 * fw, min(dl, dstem) + fuzz * 0.4);
		float a_pet = 1.0 - smoothstep(-0.6 * fw, 0.6 * fw, dpet + fuzz * 0.25);
		float a_eye = 1.0 - smoothstep(-0.6 * fw, 0.6 * fw, deye);
		vec3 leaf = mix(mix(grass_root.rgb, ground, 0.4), grass_tip.rgb, smoothstep(0.0, 0.8, lt));
		vec3 petal = pick < 0.34 ? petal_a.rgb : (pick < 0.58 ? petal_b.rgb : (pick < 0.8 ? petal_c.rgb : petal_d.rgb));
		petal = light_object(petal, 1.0 - pr * 0.5, 0.0);
		petal = mix(petal, shade_of(petal), smoothstep(0.4, 1.0, pr) * 0.25);
		vec3 eye = light_object(flower_eye.rgb, 1.0, 0.0);
		leaf = golden_grade(leaf, p_design, 0.0);
		col = mix(leaf, petal, a_pet);
		col = mix(col, eye, a_eye * a_pet);
		a = max(a_leaf, a_pet);
	}
	// Round 5: the same golden grade as the meadow (no grey-green tufts on a glowing ground).
	if (kind != KIND_FLOWERS && kind != KIND_PEBBLE) {
		col = golden_grade(col, p_design, 0.0);
	}
	if (g_cloud_shadow > 0.001) {
		col = mix(col, shade_of(col), cloud_shadow(p_design) * 1.6);
	}
	if (g_lights > 0.001) {
		col = apply_lamp(col, lamp_weight(p_design) * 0.8);
	}
	col = mix(col, golden_grade(ground, p_design, 0.0), dof_flatten * dof);
	col = finish(col, p / PX_PER_DP + seed * 13.0, FRAGCOORD.xy, GRAIN_TERRAIN);
	// Composite the dressing over its contact shadow.
	float out_a = a + sh_a * (1.0 - a);
	if (out_a < 0.004) {
		discard;
	}
	vec3 sh_c = shade_of(golden_grade(ground, p_design, 0.0));
	vec3 rgb = (col * a + sh_c * sh_a * (1.0 - a)) / out_a;
	COLOR = vec4(rgb, out_a);
}
