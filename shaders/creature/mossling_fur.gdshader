// Production mossling shader (docs/ART_BIBLE.md §4.11, §5.4-5.6; started from
// docs/art/reference/fur_spike.gdshader). One SDF quad per creature: body, ears, tail, antennae,
// pattern, belly and face in one fragment, so the felt fringe and rim run continuously over every
// join. All per-creature parameters are the 16 instance uniforms of §5.5 (written by
// scripts/creature/mossling.gd from data/creature_rig.json + palettes.json); the shared material
// uniforms (u_*) come from the same data, set once by MosslingRig.make_material().
//
// Space: p in bu (body heights), y up, feet at the origin (v_local = VERTEX / S, y flipped).
// Units: *_px are local px (pre depth-scale, so fibres and grain thin with distance), *_dp = 3 px.
// Compatibility / GLES3: highp for every position and time value, no TIME (g_time only, k/600
// loops), derivatives are taken before any non-uniform branch, constant loop bounds.
shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

// ------------------------------------------------------------------ shared includes (Art Bible §4.2)
// world_light: every g_* global, noise (h12, vnoise, vnoise_tiled), key_dir(), light_elevation(),
// gust(), wind_k(), cloud_shadow(), SHADE_K / AO_MAX / KEY_TOP / LOOP_S; finish: finish(),
// tpdf(), PX_PER_DP, GRAIN_OBJECT. The creatures share one light and one wind with the world.
#include "res://shaders/inc/world_light.gdshaderinc"
#include "res://shaders/inc/finish.gdshaderinc"

// ------------------------------------------------------------------ shared material (data-driven)
uniform vec4 u_leaf : source_color = vec4(1.0);      // palettes creatures.tokens.cr_leaf
uniform vec4 u_shine : source_color = vec4(1.0);     // cr_eye_shine
// motion_tokens creature.breathe: xy awake (1 - x scale, y scale - 1), zw asleep.
uniform vec4 u_breath = vec4(0.010, 0.025, 0.015, 0.035);
// motion_tokens loops_k: x ear_wind, y antenna_bob, z gust; w gust spacing px (loops_spatial).
uniform vec4 u_wind_k = vec4(124.0, 76.0, 62.0, 1742.0);
uniform float u_lod = 0.0;                           // FrameGovernor tier >= 1: drop fine detail
// UI portraits (scripts/ui/creature_portrait.gd) draw a mossling magnified k x: k grain cells per
// local dp keep the felt grain at 1 screen dp instead of 3k-px blocks. 1.0 in the world.
uniform float u_grain_density = 1.0;
// palette grass slots (PaletteFeed, 2 Hz): the nestle blades match the meadow dressing
uniform vec4 u_grass_tip : source_color = vec4(0.565, 0.722, 0.549, 1.0);
uniform vec4 u_grass_root : source_color = vec4(0.286, 0.576, 0.471, 1.0);
uniform vec4 u_ground : source_color = vec4(0.486, 0.675, 0.506, 1.0);
// Studio light for UI portraits (MosslingRig.apply_studio, creature_rig.json view.studio + the
// day palette): 0 in the world.
uniform float u_studio = 0.0;
uniform vec4 u_studio_ambient : source_color = vec4(1.0);
uniform vec4 u_studio_key : source_color = vec4(1.0, 0.945, 0.761, 1.0);
uniform vec4 u_studio_shadow : source_color = vec4(0.231, 0.424, 0.549, 1.0);
uniform vec4 u_studio_light = vec4(0.1, 0.45, -0.55, 0.83);   // backlight, rim, key dir xy (y up)
uniform float u_studio_elev = 0.8;
// world.json weather rain ambient_mult: the fur divides it back out so friends keep their
// clear-day lightness in the rain (QA r3 rain: creatures are the light in a grey frame).
uniform float u_rain_amb = 0.92;

// ------------------------------------------------------------------ instance uniforms (§5.5, 16/16)
instance uniform vec4 i_fur : source_color = vec4(1.0, 1.0, 1.0, 0.5);    // rgb fur; a = fuzz_dp / 2
instance uniform vec4 i_fur2 : source_color = vec4(1.0, 1.0, 1.0, 1.0);   // rgb pattern ink; a = strength
instance uniform vec4 i_belly : source_color = vec4(1.0, 1.0, 1.0, 0.6);  // rgb belly; a = belly size
instance uniform vec4 i_accent : source_color = vec4(1.0, 1.0, 1.0, 0.0); // rgb accent; a = emission
instance uniform vec4 i_tip : source_color = vec4(1.0, 1.0, 1.0, 0.45);   // rgb fibre tip; a = tip mix
instance uniform vec4 i_cheek : source_color = vec4(1.0, 1.0, 1.0, 0.5);  // rgb blush; a = blush alpha
instance uniform vec4 i_eye : source_color = vec4(0.2, 0.2, 0.2, 0.2);    // rgb eye ink; a = eye width
instance uniform vec4 i_body = vec4(1.0, 2.4, 150.0, 1.2);    // w/h, squircle n, S px, bottom n add
instance uniform vec4 i_parts = vec4(0.0);                     // ear, tail, antenna, pattern ids
instance uniform vec4 i_part_p = vec4(0.0);                    // ear size, ear spread, tail size, antenna len
instance uniform vec4 i_face = vec4(0.0, 0.4, 0.58, 1.0);      // eye id, spacing, height from top, mouth id
instance uniform vec4 i_anim = vec4(1.0, 0.0, 0.0, 0.0);       // squash, lean rad, blink lid, look
instance uniform vec4 i_follow = vec4(0.0, 0.0, 0.0, 150.0);   // ear, antenna, tail offset rad; breath k
instance uniform vec4 i_state = vec4(0.0, 0.0, 1.0, 0.0);      // sleep, happy, facing, phase seed
instance uniform vec4 i_light = vec4(0.0);                     // lamp dir xy (local, y up), lamp, cloud
instance uniform vec4 i_misc = vec4(0.0, 0.0, 0.0, 0.0);       // pattern seed, nestle 0..1, feet, closed eyes

// ------------------------------------------------------------------ structural constants
const vec2 BODY_C = vec2(0.0, 0.5);          // §5.3: squircle centred at (0, 0.5), half-height 0.5
const float INHALE = 0.4;                    // creature.breathe.inhale_fraction (I:E = 1:1.5)
const float FRINGE_MUL = 2.5;                // creature_rig defaults.fringe_len_mul
const float FIBRE_PITCH_PX = 3.6;            // §5.6.3: one fibre per 1.2 dp of perimeter
const float STRAY_SHARE = 0.08;              // §5.6.3: 8 % stray fibres at 1.6x length
const float STRAY_LEN = 1.45;
const float FRINGE_ALPHA = 0.85;
const float WOBBLE_DP = 0.6;                 // ± silhouette wobble per fuzz dp
const float PILLOW_R = 0.42;                 // bu: depth of the felt "pillow" dome
const float DOME_N = 0.82;                   // the top half is rounder than the seat (mochi dome)
const float BASE_FLARE = 0.05;               // the seat is a touch wider than the crown
const float BOTTOM_FRINGE = 0.15;
const float FEET_X = 0.23;                   // feet centres at ±0.23 w_h
const float FEET_W = 0.085;                  // bump half-width (bu, x min(w_h, 1.15))
const float FEET_DROP = 0.034;               // how far the feet push the seat outline down (bu)            // fibres pressed flat where the body meets the ground
const float SHADE_MIX = 0.62;                // how far the unlit side leans to the shadow tint
const float WRAP = 0.42;                     // wrapped diffuse: felt scatters light round the edge
const float SHADE_DARK = 0.72;               // the turned-away side is darker, not only cooler
const float CREATURE_AO = 0.6;               // share of AO_MAX at the seat (pale felt goes blue fast)
const float EAR_WIND_AMP = 0.05;             // §5.6.2 ear sway rad
const float STEM_WIND_AMP = 0.12;            // §5.6.2 sprouts and dandelion stems
const float LOOK_SHIFT = 0.05;               // §5.6.8 features shift by look * 0.05 * w_h
const float FAR_EYE = 0.92;                  // far eye narrows when |look| > 0.5
const float EYE_ASPECT = 1.18;               // §5.3 eye height = 1.18 x width
const float LINE_BU = 0.028;                 // §5.4 closed-eye / mouth stroke
const float LOD_PX = 90.0;                   // §5.6 LOD when the body is under 90 screen px
const float BLEND_BU = 0.018;                // colour hand-over between parts across a join
const float NIGHT_SHINE = 0.85;              // §5.4 highlights dim only x0.85 at night
const float RIM_GAIN = 0.7;                  // §5.6.6 rim weight (0.45 in the spike; felt needs a bit more)
const float RIM_BACKLIT_GAIN = 1.5;          // golden hour: the rim reaches L* >= 90 (QA round 1)
const float MOON_RIM_MAX = 0.85;            // moon rim alpha ceiling (QA r3: still too faint at 0.75)
const float BOUNCE_K = 0.16;                 // ground bounce on the lower shadow-side edge (form)
const float SHEEN_K = 0.10;                  // the felt crown's soft key sheen on the lit side
const float KEY_Z_DAY = 0.42;                // key elevation toward the viewer at low backlight
                                             // (0.62 lit every front face: no directional form)
const float LOWER_DARK = 0.09;               // seat-half value drop under the top light
const float KEY_Z_BACKLIT = 0.28;            // golden: the low sun still lifts the front a little
const float SHADE_DARK_BACKLIT = 0.86;       // backlit fronts sit in a luminous shade (L* 75-80)
const float NIGHT_AMB_LIFT = 0.20;           // night fur stays >= L* 45 (QA r3)
const float GOLDEN_AMB_LIFT = 0.3;           // fur ambient lifted toward white at full backlight
const float NIGHT_RIM = 1.4;                 // extra rim when the ambient is dark
const float MOON_RIM_A = 0.78;               // §1.3 B: moon rim alpha on the moon-facing edge (QA r2: 0.5 read too faint)
const float MOON_RIM_PX = 5.0;               // moon rim band (local px; x2 soft inner edge)
const float MOON_RIM_GLOW = 0.32;            // additive lift so the moonlit edge reads luminous, not grey
const float NIGHT_TIP = 0.4;                 // QA r2: the omnidirectional light fibre tips fade to 40 % at night
const float NIGHT_GRAIN = 0.7;               // QA r2: felt grain -30 % at low ambient (dark values stay clean)
// Near-camera creatures (depth scale > 0.9): round 4 hands the "sit back" job to the env value
// frame and creature_rig depth_scale.near_cap, so they keep their own value (QA r3: the near
// friend went muddy grey-mauve) and the full golden peach rim.
const float NEAR_ALBEDO = 0.97;
const float NEAR_RIM = 1.0;
const vec2 NEAR_DEPTH = vec2(0.9, 1.0);      // depth-scale ramp; > 1.05 = lineup / UI portrait (off)
// Focal creature (the sun-stone friend, i_light.w < 0): a stronger rim and a warm lift (§2.5).
const float FOCAL_RIM = 0.45;
const float FOCAL_LIFT = 0.06;
const float FOCAL_CHROMA = 0.25;
// Leaf umbrella (i_misc.z fraction): its soft shade on the crown, α 0.25 (QA r2).
const float UMB_SHADE_A = 0.25;
const float UMB_CODE = 0.4;                  // i_misc.z = feet (0 / 1) + UMB_CODE x umbrella alpha
// Nibble leaf (i_misc.w = closed id + 3 x round(leaf x 8)): a clover leaf held at the mouth.
const float LEAF_STEPS = 8.0;
// Species identity survives the ambient tint: this share of the light keeps the fur's own hue at
// its lit value (day / golden), more at night so friends stay tellable apart (QA round 1).
const float HUE_KEEP_DAY = 0.26;
const float HUE_KEEP_NIGHT = 0.55;
const float FRONT_DARK = 0.07;               // backlit: the front face sits 8-12 % darker
const float LAMP_FILL_MAX = 0.55;            // lantern screen fill ceiling
const float LAMP_FILL_K = 1.3;
const float LAMP_RIM_A = 0.55;               // §8.3: warm rim on the lamp-facing edge (α 0.4 x weight, felt needs more)
const float LAMP_RIM_PX = 5.0;
// Nestle: a few soft grass blades in front of the feet (palette grass slots), so a creature on
// the meadow sits IN the grass rather than on top of it; off on props and in the air.
const float NESTLE_H_BU = 0.16;              // blade height (bu)
const float NESTLE_PITCH_BU = 0.12;          // clump spacing along x (bu)
const float NESTLE_SPAN = 0.62;              // blades cover |x| < span * w_h / 2 ... plus a margin
const float EYE_WH_CAP = 1.08;               // eye width follows w_h only up to this
const float LID_AWAKE = 0.14;                // sleepy eye: upper-lid coverage awake (<= 15 %)
const float LID_DROWSY = 0.42;               // ... while drifting off

varying vec2 v_local;
varying flat vec3 v_key;   // xy: key direction in local space (y up); z: light elevation 0..1
varying flat vec2 v_env;   // x: travelling gust 0..1 at the creature, y: cloud shadow at its origin
varying flat float v_near; // 0..1: near-camera value compression (depth scale from the model matrix)

// ------------------------------------------------------------------ creature SDF helpers
// Value noise whose x cells wrap with an integer period (seamless fibres around a contour).
float vnoise_px(vec2 p, float per) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float x0 = mod(i.x, per);
	float x1 = mod(i.x + 1.0, per);
	return mix(mix(h12(vec2(x0, i.y)), h12(vec2(x1, i.y)), u.x),
			mix(h12(vec2(x0, i.y + 1.0)), h12(vec2(x1, i.y + 1.0)), u.x), u.y);
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x + s * v.y, -s * v.x + c * v.y);   // clockwise by a (a > 0 tips +y toward +x)
}

// Direction at angle a from vertical (a > 0 leans toward +x).
vec2 dir_a(float a) {
	return vec2(sin(a), cos(a));
}

// Squircle |x/rx|^n + |y/ry|^n = 1, first-order distance (gradient normalised) in bu.
float sd_squircle(vec2 q, vec2 r, float n) {
	vec2 a = max(abs(q) / r, vec2(1e-4));
	vec2 an = pow(a, vec2(n));
	float s = an.x + an.y;
	float m = pow(s, 1.0 / n);
	vec2 g = pow(s, 1.0 / n - 1.0) * (an / a) / r;
	return (m - 1.0) / max(length(g), 1e-3);
}

// Distance from the squircle centre to its outline along direction d (unit).
float squircle_radius(vec2 d, vec2 r, float n) {
	vec2 a = max(abs(d) / r, vec2(1e-4));
	return 1.0 / pow(pow(a.x, n) + pow(a.y, n), 1.0 / n);
}

float sd_capsule(vec2 p, vec2 a, vec2 b, float r) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

// Tapered capsule: radius ra at a, rb at b (approximate, exact enough for small tapers).
float sd_taper(vec2 p, vec2 a, vec2 b, float ra, float rb, out float h) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - mix(ra, rb, h);
}

// Vesica (leaf) along +y, half-length hl, half-width hw, centred at the origin; rounded tips tr.
float sd_vesica(vec2 p, float hl, float hw, float tr) {
	hl -= tr;
	hw -= tr;
	float r = 0.5 * (hl * hl / hw + hw);
	float d = r - hw;
	p = abs(p);
	float b = sqrt(max(r * r - d * d, 0.0));
	float v = ((p.y - b) * d > p.x * b) ? length(p - vec2(0.0, b)) : length(p - vec2(-d, 0.0)) - r;
	return v - tr;
}

float sd_ellipse(vec2 p, vec2 r) {
	float k0 = length(p / r);
	float k1 = length(p / (r * r));
	return k0 * (k0 - 1.0) / max(k1, 1e-4);
}

// Arc of radius ra, half-aperture given by sc = (sin, cos), symmetric about +y; stroke rb.
float sd_arc(vec2 p, vec2 sc, float ra, float rb) {
	p.x = abs(p.x);
	return ((sc.y * p.x > sc.x * p.y) ? length(p - sc * ra) : abs(length(p) - ra)) - rb;
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// ------------------------------------------------------------------ vertex: light at the origin
void vertex() {
	v_local = VERTEX;
	// one light, wind gust and cloud shadow per creature, evaluated at its origin (Art Bible §5.6.6)
	vec2 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	vec2 l = key_dir(origin);
	v_key = vec3(l.x, -l.y, light_elevation());
	vec2 design = origin - g_world_offset;
	v_env = vec2(gust(design.x), cloud_shadow(design));
	float k = length(MODEL_MATRIX[0].xy);
	v_near = smoothstep(NEAR_DEPTH.x, NEAR_DEPTH.y, k) * (1.0 - step(1.05, k));
}

// ------------------------------------------------------------------ fragment
void fragment() {
	// UI portraits (u_studio = 1): a fixed "studio" light from the day palette whatever the world
	// time, so a friend admired in the Album never turns into a night blob (QA r3 #19 / #13).
	float st = u_studio;
	vec4 l_ambient = mix(g_ambient, u_studio_ambient, st);
	vec4 l_key = mix(g_key, u_studio_key, st);
	vec4 l_shadow = mix(g_shadow, u_studio_shadow, st);
	vec4 l_glow = mix(g_glow, u_studio_key, st);
	float l_backlight = mix(g_backlight, u_studio_light.x, st);
	float l_rim = mix(g_rim, u_studio_light.y, st);
	float l_lights = g_lights * (1.0 - st);
	float l_rain = g_rain * (1.0 - st);
	vec3 l_keyv = mix(v_key, vec3(normalize(u_studio_light.zw), u_studio_elev), st);
	float fade = COLOR.a;                                     // node modulate (arrive / leave fades)
	float S = i_body.z;
	float wh = i_body.x;
	vec2 rb = vec2(0.5 * wh, 0.5);
	float facing = i_state.z;
	float sleep = i_state.x;
	float happy = i_state.y;
	float seed = i_state.w;
	float fuzz_dp = i_fur.a * 2.0;
	int ear_id = int(i_parts.x + 0.5);
	int tail_id = int(i_parts.y + 0.5);
	int ant_id = int(i_parts.z + 0.5);
	int pat_id = int(i_parts.w + 0.5);

	// 1. pose: lean about the feet, breathing (in-shader) and squash (area-preserving about the feet)
	vec2 p = rot(vec2(v_local.x, -v_local.y) / S, -i_anim.y);
	// i_follow.w = integer breath k + a phase offset in its fraction (k switches stay continuous)
	float ph = fract(g_time * floor(i_follow.w) / LOOP_S + seed + fract(i_follow.w));
	float br = ph < INHALE ? smoothstep(0.0, INHALE, ph) : 1.0 - smoothstep(INHALE, 1.0, ph);
	vec2 amp = mix(u_breath.xy, u_breath.zw, sleep) * g_motion;
	float sq = i_anim.x;
	// Jelly squash: the lower half spreads a little more than the top (a soft sitting mochi).
	float spread = 1.0 + (1.0 / sq - 1.0) * 0.35 * (1.0 - smoothstep(0.0, 1.0, p.y));
	vec2 sc = vec2((1.0 / sq) * spread * (1.0 - amp.x * br), sq * (1.0 + amp.y * br));
	vec2 ps = p / sc;

	// wind (shared by ears, stems, bells): travelling gust along x in canvas px
	float wk = wind_k() * (1.0 + GUST_AMP * v_env.x) * g_motion;
	float sway = sin(TAU * u_wind_k.x / LOOP_S * g_time + seed * 6.0) * wk;
	float stem_sway = sin(TAU * u_wind_k.y / LOOP_S * g_time + seed * 5.0) * wk;

	// 2. silhouette ---------------------------------------------------------------------------
	// body squircle, flatter on the lower half (a sitting mochi)
	// mochi: a rounder dome on top, the flat "sitting" seat below (+1.2 n), a touch wider at the base
	vec2 qb = ps - BODY_C;
	float n_dome = max(2.0, i_body.y * DOME_N);
	float n = qb.y < 0.0 ? i_body.y + i_body.w * smoothstep(0.0, -0.5, qb.y)
			: mix(i_body.y, n_dome, smoothstep(0.0, 0.5, qb.y));
	vec2 rbt = vec2(rb.x * (1.0 - BASE_FLARE * qb.y / rb.y), rb.y);
	float d_body = sd_squircle(qb, rbt, n);
	// feet nubs: two soft bumps of the seat outline itself (no interior edge, so no crease
	// artefacts in the normal field)
	float w_feet = 0.0;
	float feet_on = step(0.7, i_misc.z);
	float umb = clamp((i_misc.z - feet_on) / UMB_CODE, 0.0, 1.0);
	float misc_w = i_misc.w + 0.25;
	float leaf_k = floor(misc_w / 3.0) / LEAF_STEPS;
	float closed_id = floor(mod(misc_w, 3.0));
	float focal = clamp(-i_light.w, 0.0, 1.0);
	if (feet_on > 0.5) {
		float fx = (abs(qb.x) - FEET_X * wh) / (FEET_W * min(wh, 1.15));
		float bump = exp(-fx * fx * 2.2);
		float low = 1.0 - smoothstep(0.0, 0.16, ps.y);
		d_body -= FEET_DROP * bump * low;
		w_feet = bump * (1.0 - smoothstep(0.0, 0.05, ps.y));
	}
	if (pat_id == 6) {
		// toadstool cap: the brim overhangs the body a little (identity cue in silhouette)
		float brim_y = 0.66 - 0.05 * (qb.x / rb.x) * (qb.x / rb.x);
		float overhang = smoothstep(brim_y - 0.03, brim_y + 0.05, ps.y) * (1.0 - smoothstep(brim_y + 0.12, 0.98, ps.y));
		d_body -= 0.03 * overhang * smoothstep(0.4, 0.9, abs(qb.x) / rb.x);
	}
	float d = d_body;
	vec3 alb_part = vec3(0.0);     // albedo of the dominant part (when w_part > 0)
	float w_part = 0.0;            // 0 = body, 1 = some part dominates this pixel
	float fz_part = 1.0;           // fringe multiplier of that part
	vec2 fc_part = BODY_C;         // fibre centre of that part
	float fr_part = 0.5;           // nominal radius of that part (fibre count)
	float pr_part = PILLOW_R;      // pillow bevel depth for that part
	float halo = 0.0;              // additive bobble glow (premultiplied, alpha 0)
	float emit_mask = 0.0;
	float asym = (fract(seed * 7.31) - 0.5) * 0.12;   // §5.3 ears differ by ±0.06 rad

	// ears ----------------------------------------------------------------
	if (ear_id > 0) {
		float es = i_part_p.x;
		float d_e = 1e3;
		vec3 a_e = i_fur.rgb;
		vec2 c_e = BODY_C;
		for (int s = -1; s <= 1; s += 2) {
			float fs = float(s);
			float a = fs * (i_part_p.y + i_follow.x + fs * asym) + EAR_WIND_AMP * sway;
			vec2 dr = dir_a(a);
			vec2 edge = BODY_C + dr * squircle_radius(dr, vec2(rb.x * (1.0 - BASE_FLARE * dr.y), rb.y), n_dome);
			float de = 1e3;
			vec3 col = i_fur.rgb;
			if (ear_id == 1) {                                   // round
				vec2 ec = edge - dr * es * 0.35;
				de = length(ps - ec) - es;
				float inner = 1.0 - smoothstep(0.50 * es, 0.62 * es, length(ps - (ec + dr * es * 0.18)));
				col = mix(i_fur.rgb, i_accent.rgb, 0.35 * inner);
				if (de < d_e) { c_e = ec; }
			} else if (ear_id == 2) {                            // tuft: soft cowlick of 3 flames
				if (s > 0) {
					float tw = EAR_WIND_AMP * sway * 1.5;
					vec2 top = BODY_C + vec2(0.0, rb.y) - vec2(0.0, 0.03);
					// a soft cowlick: the centre flame leans and curls over, two smaller flames beside it
					float lean_t = (fract(seed * 3.7) < 0.5 ? -1.0 : 1.0) * 0.38;
					vec2 q0 = rot(ps - top, tw + lean_t);
					float d0 = sd_vesica(q0 - vec2(0.0, es * 0.42), es * 0.46, 0.07, 0.035);
					vec2 hook = top + rot(vec2(0.0, es * 0.78), -(tw + lean_t)) + vec2(sign(lean_t) * 0.03, -0.012);
					d0 = smin(d0, length(ps - hook) - 0.034, 0.03);
					vec2 q1 = rot(ps - (top + vec2(-0.085, -0.025)), -(tw - 0.62 - i_follow.x));
					float d1 = sd_vesica(q1 - vec2(0.0, 0.075), 0.088, 0.055, 0.026);
					vec2 q2 = rot(ps - (top + vec2(0.085, -0.025)), -(tw + 0.62 + i_follow.x));
					float d2 = sd_vesica(q2 - vec2(0.0, 0.075), 0.088, 0.055, 0.026);
					de = smin(d0, smin(d1, d2, 0.03), 0.03);
					float tipness = smoothstep(top.y + 0.02, top.y + es, ps.y);
					col = mix(i_fur.rgb, i_tip.rgb, 0.55 * tipness);
					c_e = top + vec2(0.0, 0.08);
				}
			} else if (ear_id == 3) {                            // pointed_soft: rounded cone
				vec2 base = edge - dr * 0.06;
				vec2 tipp = base + dir_a(a + fs * 0.10) * es;
				float h;
				de = sd_taper(ps, base, tipp, 0.11, 0.05, h);
				float hi;
				float di = sd_taper(ps, base + (tipp - base) * 0.22, tipp - (tipp - base) * 0.12, 0.055, 0.022, hi);
				float inner = 1.0 - smoothstep(-0.012, 0.012, di);
				col = mix(i_fur.rgb, i_accent.rgb, 0.40 * inner);
				if (de < d_e) { c_e = base + (tipp - base) * 0.45; }
			} else if (ear_id == 4) {                            // bell: curved stalk + bluebell
				float swing = EAR_WIND_AMP * 2.0 * sway + i_follow.x * 1.5 * fs;
				float bs = es * 1.3;
				vec2 b0 = edge - dr * 0.03;
				vec2 b1 = b0 + vec2(fs * 0.12, 0.085);
				vec2 bell_c = b1 + rot(vec2(fs * 0.055, -0.15), swing);
				float dst = min(sd_capsule(ps, b0, b1, 0.026), sd_capsule(ps, b1, bell_c + vec2(0.0, bs * 0.7), 0.022));
				vec2 bq = rot(ps - bell_c, swing);
				// bluebell: a dome that flares into a five-lobed, slightly curled rim
				float flare = smoothstep(0.02, -0.11, bq.y);
				vec2 bqs = vec2(bq.x / (1.0 + 0.45 * flare), bq.y);
				float lobes = 0.018 * (0.5 + 0.5 * cos(bqs.x / bs * PI * 2.5)) * flare;
				float dbell = sd_ellipse(bqs - vec2(0.0, -0.01), vec2(bs * 0.8, bs)) - lobes;
				de = smin(dst, dbell, 0.02);
				float mouth = smoothstep(-0.03, -0.11, bq.y) * (1.0 - smoothstep(-0.03, 0.0, dbell + 0.012));
				col = mix(i_fur2.rgb, i_accent.rgb, 0.7 * mouth);
				col = mix(col, mix(i_fur2.rgb, u_leaf.rgb, 0.55), 1.0 - smoothstep(-0.012, 0.004, dst - dbell));
				if (de < d_e) { c_e = bell_c; }
			} else if (ear_id == 5) {                            // leaf
				vec2 base = edge - dr * 0.05;
				vec2 lq = rot(ps - base, -(a + fs * 0.08));   // leaf axis along dir_a(a)
				de = sd_vesica(lq - vec2(0.0, es * 0.5), es * 0.5, 0.08, 0.025);
				float along = clamp(lq.y / es, 0.0, 1.0);
				col = mix(i_fur.rgb, i_accent.rgb, smoothstep(0.15, 0.95, along));
				float rib = (1.0 - smoothstep(0.004, 0.012, abs(lq.x))) * smoothstep(0.02, 0.2, along) * (1.0 - smoothstep(0.75, 0.95, along));
				col *= 1.0 - 0.08 * rib;
				if (de < d_e) { c_e = base + dr * es * 0.5; }
			} else if (ear_id == 6) {                            // nub
				vec2 ec = edge - dr * es * 0.40;
				de = length(ps - ec) - es;
				if (de < d_e) { c_e = ec; }
			}
			if (de < d_e) {
				a_e = col;
			} else {
				a_e = mix(col, a_e, clamp(0.5 + (de - d_e) / (2.0 * BLEND_BU), 0.0, 1.0));
			}
			d_e = min(d_e, de);
		}
		float k_e = ear_id == 4 ? 0.02 : (ear_id == 2 ? 0.03 : 0.05);
		float w = clamp(0.5 + (d - d_e) / (2.0 * BLEND_BU), 0.0, 1.0);
		alb_part = a_e;
		w_part = w;
		fz_part = (ear_id == 4 || ear_id == 5) ? 0.35 : 1.0;
		fc_part = c_e;
		fr_part = max(es, 0.08);
		pr_part = min(PILLOW_R, es * 0.9);
		d = smin(d, d_e, k_e);
	}

	// tail -----------------------------------------------------------------
	if (tail_id > 0) {
		// the tail sits opposite the facing; while a turn crosses zero it tucks behind the body
		float tvis = smoothstep(0.05, 0.6, abs(facing));
		float ts = i_part_p.z;
		float side = facing >= 0.0 ? -1.0 : 1.0;
		float ta = i_follow.z;   // follow offset: + swings up / back
		float d_t = 1e3;
		vec3 a_t = i_tip.rgb;
		vec2 c_t = BODY_C;
		float fz_t = 1.0;
		if (tail_id == 1) {                                      // puff
			vec2 tc = vec2(side * 0.98 * rb.x, 0.24) + vec2(side * sin(ta), cos(ta) - 1.0) * 0.08;
			d_t = length(ps - tc) - ts;
			a_t = mix(i_fur.rgb, i_tip.rgb, 0.7);
			c_t = tc;
		} else if (tail_id == 2) {                               // curl: 270° ring
			vec2 tc = vec2(side * (rb.x + 0.075), 0.30);
			vec2 tq = rot(ps - tc, side * (0.6 + ta) + PI);
			tq.x *= side;
			d_t = sd_arc(tq, vec2(sin(0.75 * PI), cos(0.75 * PI)), ts * 0.78, 0.034);
			a_t = mix(i_fur.rgb, i_fur2.rgb, 0.3);
			c_t = tc;
			fz_t = 0.7;
		} else if (tail_id == 3) {                               // brush: big fluffy vesica
			vec2 anchor = vec2(side * 0.95 * rb.x, 0.16);
			float a = side * (1.05 + ta);
			vec2 tq = rot(ps - anchor, -a);
			d_t = sd_vesica(tq - vec2(0.0, ts * 0.42), ts * 0.5, 0.11, 0.05);
			float along = clamp(tq.y / ts, 0.0, 1.0);
			a_t = mix(i_fur.rgb, i_fur2.rgb, smoothstep(0.45, 0.95, along));
			c_t = anchor + dir_a(a) * ts * 0.42;
			fz_t = 1.6;
		} else if (tail_id == 4) {                               // leaf
			vec2 anchor = vec2(side * 0.95 * rb.x, 0.22);
			vec2 tq = rot(ps - anchor, -side * (0.8 + ta));
			d_t = sd_vesica(tq - vec2(0.0, ts * 0.45), ts * 0.5, 0.075, 0.025);
			float along = clamp(tq.y / ts, 0.0, 1.0);
			float rib = (1.0 - smoothstep(0.004, 0.012, abs(tq.x))) * smoothstep(0.05, 0.25, along) * (1.0 - smoothstep(0.7, 0.92, along));
			a_t = mix(i_accent.rgb, i_fur.rgb, 0.15 * (1.0 - along)) * (1.0 - 0.08 * rib);
			c_t = anchor + dir_a(side * (0.8 + ta)) * ts * 0.45;
			fz_t = 0.35;
		} else if (tail_id == 5) {                               // sprout from the rear top
			vec2 base = vec2(side * 0.80 * rb.x, 0.78);
			float a = side * (0.75 + ta) + STEM_WIND_AMP * 0.5 * stem_sway;
			vec2 tipp = base + dir_a(a) * ts;
			float dst = sd_capsule(ps, base, tipp, 0.018);
			vec2 l1q = rot(ps - tipp, -(a - 0.9));
			vec2 l2q = rot(ps - tipp, -(a + 0.9));
			float dl = min(sd_vesica(l1q - vec2(0.0, 0.05), 0.05, 0.026, 0.012),
					sd_vesica(l2q - vec2(0.0, 0.05), 0.05, 0.026, 0.012));
			float dbud = length(ps - (tipp + dir_a(a) * 0.025)) - 0.028;
			d_t = min(min(dst, dl), dbud);
			a_t = dbud < min(dst, dl) ? i_accent.rgb : u_leaf.rgb;
			c_t = tipp;
			fz_t = 0.0;
		}
		d_t += (1.0 - tvis) * 0.3;
		float w = clamp(0.5 + (d - d_t) / (2.0 * BLEND_BU), 0.0, 1.0);
		alb_part = mix(alb_part, a_t, w);
		fz_part = mix(fz_part, fz_t, w);
		fc_part = mix(fc_part, c_t, w);
		fr_part = mix(fr_part, max(ts, 0.08), w);
		pr_part = mix(pr_part, tail_id == 2 ? 0.036 : min(PILLOW_R, ts * 0.9), w);   // thin curl: round across its width
		w_part = max(w_part, w);
		d = smin(d, d_t, tail_id == 5 ? 0.015 : 0.04);
	}

	// antennae ------------------------------------------------------------
	if (ant_id > 0) {
		float al = i_part_p.w;
		float a0 = i_follow.y + STEM_WIND_AMP * 0.6 * stem_sway;
		vec2 top = vec2(0.0, 1.0 - 0.02);
		float d_a = 1e3;
		vec3 a_a = i_fur2.rgb;
		vec2 c_a = top;
		float fz_a = 0.0;
		float r_a = 0.06;
		if (ant_id == 2) {                                       // double bobble
			for (int s = -1; s <= 1; s += 2) {
				float fs = float(s);
				vec2 b0 = vec2(fs * 0.12 * wh, 0.985 - 0.02 * abs(fs));
				float a = fs * 0.30 + a0;
				vec2 b1 = b0 + dir_a(a * 0.7) * al * 0.55;
				vec2 b2 = b1 + dir_a(a * 1.25) * al * 0.45;
				float dst = min(sd_capsule(ps, b0, b1, 0.020), sd_capsule(ps, b1, b2, 0.018));
				float dbo = length(ps - b2) - 0.065;
				float dd = min(dst, dbo);
				if (dd < d_a) {
					a_a = dbo < dst ? i_accent.rgb : i_fur2.rgb;
					c_a = b2;
					fz_a = dbo < dst ? 0.55 : 0.0;
				}
				d_a = smin(d_a, dd, 0.004);
			}
			r_a = 0.065;
		} else {
			vec2 b0 = top;
			vec2 b1 = b0 + dir_a(a0 * 0.6) * al * 0.55;
			vec2 b2 = b1 + dir_a(a0 * 1.4) * al * 0.45;
			float thick = ant_id == 4 ? 0.016 : (ant_id == 3 ? 0.025 : 0.022);
			float dst = min(sd_capsule(ps, b0, b1, thick), sd_capsule(ps, b1, b2, thick * 0.9));
			vec3 stalk_col = (ant_id == 1 || ant_id == 4) ? u_leaf.rgb : (ant_id == 3 ? i_accent.rgb : i_fur2.rgb);
			d_a = dst;
			a_a = stalk_col;
			c_a = b2;
			float at = a0 * 1.4;
			if (ant_id == 1) {                                   // sprout: two leaves + button bud
				vec2 lb = b1 + (b2 - b1) * 0.55;
				vec2 l1q = rot(ps - lb, at - 0.9);
				vec2 l2q = rot(ps - lb, at + 0.9);
				float dl1 = sd_vesica(l1q - vec2(0.0, 0.065), 0.065, 0.0325, 0.014);
				float dl2 = sd_vesica(l2q - vec2(0.0, 0.065), 0.065, 0.0325, 0.014);
				float dl = min(dl1, dl2);
				vec2 lq = dl1 < dl2 ? l1q : l2q;
				float rib = 1.0 - smoothstep(0.003, 0.008, abs(lq.x));
				float dbud = length(ps - (b2 + dir_a(at) * 0.02)) - 0.05;
				if (dl < d_a) { a_a = u_leaf.rgb * (1.0 - 0.08 * rib); }
				d_a = smin(d_a, dl, 0.01);
				if (dbud < d_a) { a_a = i_accent.rgb; fz_a = 0.5; }
				d_a = smin(d_a, dbud, 0.012);
				c_a = b2;
				r_a = 0.05;
			} else if (ant_id == 3) {                            // fern fiddlehead
				vec2 cc = b2 + vec2(0.055, 0.0);
				vec2 fq = rot(ps - cc, at);
				float ang = atan(fq.y, -fq.x);                  // 0 at the stem join, grows inward
				ang = ang < 0.0 ? ang + TAU : ang;
				float rr = length(fq);
				float best = 1e3;
				for (int k = 0; k < 2; k++) {
					float th = ang + TAU * float(k);
					float turns = th / TAU;
					if (turns <= 1.25) {
						float rad = 0.055 * (1.0 - 0.62 * turns / 1.25);
						float w2 = mix(0.022, 0.011, turns / 1.25);
						best = min(best, abs(rr - rad) - w2);
					}
				}
				float dcurl = best;
				d_a = smin(d_a, dcurl, 0.01);
				c_a = cc;
				r_a = 0.06;
			} else if (ant_id == 4) {                            // dandelion seed puff
				vec2 pc = b2 + dir_a(at) * 0.12;
				vec2 pq = ps - pc;
				float pr = length(pq);
				float pa = atan(pq.x, pq.y) - at;
				float cell = TAU / 14.0;
				float idx = floor(pa / cell + 0.5);
				float pa_c = idx * cell + (h12(vec2(idx, 3.1)) - 0.5) * 0.12;
				float off = pa - pa_c;
				float fil = abs(sin(off)) * pr - 0.0045;
				float rlen = 0.13 * (0.92 + 0.1 * h12(vec2(idx, 7.7)));
				fil = max(fil, pr - rlen);
				float dot_tip = length(pq - dir_a(pa_c + at) * rlen) - 0.016;
				float core_ = pr - 0.035;
				float dpuff = min(min(fil, dot_tip), core_);
				if (dpuff < d_a) { a_a = mix(i_tip.rgb, i_fur.rgb, 0.3); fz_a = 0.0; }
				d_a = min(d_a, dpuff);
				c_a = pc;
				r_a = 0.13;
				// a soft seed-fluff halo (felt) around the filaments
				halo = 0.0;
			} else if (ant_id == 5 || ant_id == 6) {             // glow bobble
				float rbo = 0.075;
				vec2 bc = b2 + dir_a(at) * (rbo * 0.6);
				float dbo = length(ps - bc) - rbo;
				if (dbo < d_a) { a_a = i_accent.rgb; fz_a = 0.45; emit_mask = 1.0; }
				d_a = smin(d_a, dbo, 0.015);
				c_a = bc;
				r_a = rbo;
				float hr = length(ps - bc) / (rbo * 1.1);
				halo = i_accent.a * l_lights * mix(1.0, 0.4, sleep) / (1.0 + hr * hr * 2.2) * (1.0 - smoothstep(2.2, 3.0, hr));
			}
		}
		float w = clamp(0.5 + (d - d_a) / (2.0 * BLEND_BU), 0.0, 1.0);
		alb_part = mix(alb_part, a_a, w);
		fz_part = mix(fz_part, fz_a, w);
		fc_part = mix(fc_part, c_a, w);
		fr_part = mix(fr_part, r_a, w);
		pr_part = mix(pr_part, 0.03, w);
		w_part = max(w_part, w);
		d = smin(d, d_a, 0.012);
	}

	// 3. derivatives (before any branch): local gradient via the chain rule (robust to y flips)
	vec2 dpx = dFdx(p);
	vec2 dpy = dFdy(p);
	float ddx = dFdx(d);
	float ddy = dFdy(d);
	float det = dpx.x * dpy.y - dpx.y * dpy.x;
	vec2 grad = abs(det) > 1e-12 ? vec2(ddx * dpy.y - dpx.y * ddy, dpx.x * ddy - ddx * dpy.x) / det : vec2(0.0, 1.0);
	vec2 n2 = length(grad) > 1e-5 ? normalize(grad) : vec2(0.0, 1.0);
	float bu_per_px = max(length(dpx), length(dpy));        // bu per screen pixel
	float screen_px = 1.0 / max(bu_per_px, 1e-5);            // screen px per bu
	float lod = max(u_lod, step(screen_px, LOD_PX));
	float d_px = d * S;
	float aa = max(bu_per_px * S, 0.6);                      // local px per screen px

	// 4. fuzz: wobble + fibre fringe outside the silhouette
	float fz = mix(1.0, fz_part, w_part) * (1.0 - 0.3 * l_rain);
	vec2 pcb = ps - BODY_C;
	float ang_b = atan(pcb.y, pcb.x);
	float n_b = max(floor(PI * (rb.x + rb.y) * S / FIBRE_PITCH_PX), 8.0);
	vec2 pcp = ps - fc_part;
	float ang_p = atan(pcp.y, pcp.x);
	float n_p = max(floor(TAU * fr_part * S / FIBRE_PITCH_PX), 8.0);
	float wob_b = vnoise_px(vec2(ang_b / TAU * n_b / 6.0, 0.5), max(floor(n_b / 6.0), 1.0));
	float wob = (wob_b - 0.5) * 2.0 * WOBBLE_DP * PX_PER_DP * fuzz_dp * fz;
	float d_s = d_px - wob;
	float fringe_px = max(fuzz_dp * FRINGE_MUL * PX_PER_DP * fz, 0.01);
	// fibres: two anisotropic octaves in (angle * N, radius), body field and part field blended
	float rad_k = S / 6.0;
	float curl = (vnoise(vec2(ang_b * 3.0, d_px * 0.35)) - 0.5) * 0.9;     // fibres wave a little
	float fa_b = vnoise_px(vec2(ang_b / TAU * n_b + curl, length(pcb) * rad_k * 0.25), n_b);
	float fb_b = lod > 0.5 ? 0.5 : vnoise_px(vec2(ang_b / TAU * n_b * 1.7 + 11.0, length(pcb) * rad_k * 0.42), floor(n_b * 1.7));
	float fa_p = vnoise_px(vec2(ang_p / TAU * n_p, length(pcp) * rad_k * 0.25), n_p);
	float fb_p = lod > 0.5 ? 0.5 : vnoise_px(vec2(ang_p / TAU * n_p * 1.7 + 11.0, length(pcp) * rad_k * 0.42), floor(n_p * 1.7));
	float fib = mix(fa_b * 0.6 + fb_b * 0.4, fa_p * 0.6 + fb_p * 0.4, w_part);
	fib = smoothstep(0.42, 0.82, fib);
	float cid_b = floor(ang_b / TAU * n_b);
	float cid_p = floor(ang_p / TAU * n_p);
	float len_j = 0.55 + 0.45 * h12(vec2(mix(cid_b, cid_p + 101.0, step(0.5, w_part)), 9.0));
	float stray = lod > 0.5 ? 0.0 : step(1.0 - STRAY_SHARE, h12(vec2(mix(cid_b, cid_p + 101.0, step(0.5, w_part)), 4.0)));
	len_j = mix(len_j, STRAY_LEN, stray);
	float fringe_t = clamp(d_s / (fringe_px * len_j), 0.0, 1.0);
	float core = 1.0 - smoothstep(-aa, aa, d_s);
	float fringe_a = d_s > 0.0 ? fib * (1.0 - fringe_t) * (1.0 - fringe_t) * FRINGE_ALPHA : 0.0;
	fringe_a *= step(0.02, fz) * mix(BOTTOM_FRINGE, 1.0, smoothstep(-0.95, -0.35, n2.y));
	// a faint uniform haze in the fibre band reads as felt even where fibres thin out
	fringe_a = max(fringe_a, (1.0 - smoothstep(0.0, fringe_px * 0.55, d_s)) * 0.16 * step(0.02, fz) * step(0.0, d_s));
	float cover = clamp(core + fringe_a * (1.0 - core), 0.0, 1.0);

	vec3 halo_rgb = mix(i_accent.rgb, g_accent.rgb, 0.35) * halo;

	// nestle blades in front of the feet (unposed local space: they belong to the ground)
	float nest_a = 0.0;
	vec3 nest_col = vec3(0.0);
	float nestle = i_misc.y;
	if (nestle > 0.01) {
		vec2 q = vec2(v_local.x, -v_local.y) / S;
		float half_span = 0.5 * wh * NESTLE_SPAN + 0.08;
		if (abs(q.x) < half_span + NESTLE_PITCH_BU * 2.0 && q.y < NESTLE_H_BU * 1.5 && q.y > -0.1) {
			float aa_bu = max(bu_per_px, 1e-4) * 0.9;
			float best_t = 0.0;
			float cell0 = floor(q.x / NESTLE_PITCH_BU);
			// soft clumps (3 rounded blades fanning from one root), like the meadow dressing
			for (int k = -1; k <= 1; k++) {
				float cell = cell0 + float(k);
				vec4 h = vec4(h12(vec2(cell, seed * 17.0)), h12(vec2(cell + 31.0, seed * 7.0)),
						h12(vec2(cell + 57.0, seed * 3.0)), h12(vec2(cell + 83.0, seed * 11.0)));
				float rx = (cell + 0.5 + (h.x - 0.5) * 0.5) * NESTLE_PITCH_BU;
				float edge = 1.0 - smoothstep(0.6, 1.0, abs(rx) / half_span);
				if (h.w < 0.3 || edge <= 0.0) {
					continue;
				}
				vec2 root = vec2(rx, -0.02 - 0.04 * h.y);
				float hgt = NESTLE_H_BU * (0.6 + 0.55 * h.z) * (0.5 + 0.5 * edge) * nestle;
				float sway_b = sin(TAU * u_wind_k.x / LOOP_S * g_time + cell * 1.3) * wk * 0.25;
				float lean = (h.x - 0.5) * 0.5 + sign(rx) * 0.15 + sway_b;
				for (int j = -1; j <= 1; j++) {
					float fj = float(j);
					float ang = lean + fj * (0.36 + 0.12 * h.y);
					float hj = hgt * (1.0 - 0.28 * abs(fj)) * (0.9 + 0.2 * h12(vec2(cell, fj + 4.0)));
					vec2 tipp = root + vec2(sin(ang), cos(ang)) * hj;
					vec2 mid = mix(root, tipp, 0.5) + vec2(-cos(ang), sin(ang)) * hj * 0.06 * sign(fj + 0.01);
					float ht;
					float db = min(sd_taper(q, root, mid, 0.022, 0.017, ht), sd_taper(q, mid, tipp, 0.017, 0.009, ht));
					float cov = 1.0 - smoothstep(-aa_bu, aa_bu, db);
					if (cov > nest_a) {
						nest_a = cov;
						best_t = clamp(dot(q - root, tipp - root) / max(hj * hj, 1e-5), 0.0, 1.0);
					}
				}
			}
			nest_col = mix(mix(u_grass_root.rgb, u_ground.rgb, 0.6), u_grass_tip.rgb * 1.04, smoothstep(0.0, 0.85, best_t));
			nest_col += l_key.rgb * l_backlight * l_rim * 0.25 * best_t * best_t;
			nest_col = 1.0 - (1.0 - nest_col) * (1.0 - g_accent.rgb * clamp(i_light.z * l_lights * LAMP_FILL_K * 0.6, 0.0, LAMP_FILL_MAX));
			nest_col = finish(nest_col, q * S / PX_PER_DP * u_grain_density, FRAGCOORD.xy, GRAIN_OBJECT);
			nest_a *= nestle;
		}
	}

	if (cover < 0.002) {
		COLOR = vec4((halo_rgb * (1.0 - nest_a) + nest_col * nest_a) * fade, nest_a * fade);
	} else {
		// 5. albedo: fur -> belly -> pattern -> part colours; felt mottling; fibre tips
		float lx = i_anim.w * LOOK_SHIFT * wh;                       // face/pattern parallax
		vec3 alb = i_fur.rgb;
		vec2 fp = ps - vec2(lx * 0.6, 0.0);                          // pattern space follows the look
		// belly: big (pattern 1, ink = belly) or the subtle default on every other species
		float big = pat_id == 1 ? 1.0 : 0.0;
		float bsize = i_belly.a;
		vec2 bel_r = vec2(0.62 * rb.x, 0.24) * mix(1.0, 1.0, big) * (0.55 + 0.45 * bsize);
		float bn = (vnoise(fp * 24.0 + seed * 9.0) - 0.5) * 0.012;
		float bel = 1.0 - smoothstep(-0.03, 0.03, sd_ellipse(fp - vec2(0.0, 0.27 * (0.8 + 0.2 * bsize)), bel_r) + bn);
		if (pat_id == 1) {
			// big belly = a deliberate "face + tummy" mask (QA r2: a straight edge just over the eyes
			// read as a seam): two soft lobes over the eyes with a dip between them (a hamster face),
			// widening into the tummy, feathered >= 0.08 so it reads as felt, never as a step
			float ey_m = 1.0 - i_face.z;
			float exm = i_face.y * 0.5 * wh;
			vec2 lob_r = vec2(exm + 0.11, 0.16);
			float d_l = min(sd_ellipse(fp - vec2(-exm * 0.95, ey_m + 0.005), lob_r),
					sd_ellipse(fp - vec2(exm * 0.95, ey_m + 0.005), lob_r));
			float d_t = sd_ellipse(fp - vec2(0.0, 0.22), vec2(0.66 * rb.x, 0.26));
			float d_m = smin(d_l, d_t, 0.10) + bn * 1.5;
			bel = 1.0 - smoothstep(-0.045, 0.045, d_m);
		}
		vec3 bel_col = pat_id == 1 ? i_fur2.rgb : i_belly.rgb;
		alb = mix(alb, bel_col, bel * (pat_id == 1 ? i_fur2.a : 0.55));
		// face anchors (shared by patterns and face)
		float ey = 1.0 - i_face.z;
		float ex = i_face.y * 0.5 * wh;
		float ew = 0.5 * i_eye.a * min(wh, EYE_WH_CAP);              // wide bodies keep baby-sized eyes
		float pn = vnoise(fp * 18.0 + seed * 3.0);
		if (pat_id == 2) {                                           // freckles
			float fr = 0.0;
			for (int s = -1; s <= 1; s += 2) {
				for (int k = 0; k < 3; k++) {
					float fk = float(k);
					vec2 jit = (vec2(h12(vec2(fk, i_misc.x * 31.0 + float(s))), h12(vec2(fk + 5.0, i_misc.x * 17.0))) - 0.5) * 0.02;
					vec2 fc = vec2(float(s) * (ex + 0.035 + 0.035 * fk - 0.02 * floor(fk * 0.5)), ey - 0.085 - 0.03 * mod(fk, 2.0)) + jit;
					fr = max(fr, 1.0 - smoothstep(0.012, 0.022, length(ps - fc - vec2(lx, 0.0))));
				}
			}
			alb = mix(alb, i_accent.rgb, fr * 0.85);
		} else if (pat_id == 3) {                                    // socks
			float edge = 0.16 + 0.02 * sin(fp.x / (0.5 * wh) * PI * 3.0 + seed * 4.0) + (pn - 0.5) * 0.015;
			// QA r2: a soft cuff, lighter toward the belly tone and feathered >= 6 px (never a stain)
			float sock = 1.0 - smoothstep(edge - 0.035, edge + 0.035, ps.y);
			alb = mix(alb, mix(i_fur2.rgb, i_belly.rgb, 0.35), sock * i_fur2.a);
		} else if (pat_id == 4) {                                    // back stripes over the head
			vec2 a2 = max(abs(qb) / rb, vec2(1e-4));
			float m = pow(pow(a2.x, n) + pow(a2.y, n), 1.0 / n);
			float stripes = 0.0;
			for (int k = 0; k < 3; k++) {
				float mk = 0.46 + 0.24 * float(k);
				stripes = max(stripes, 1.0 - smoothstep(0.045, 0.075, abs(m - mk) + (pn - 0.5) * 0.02));
			}
			stripes *= smoothstep(0.05, 0.3, qb.y) * (1.0 - smoothstep(0.55, 0.85, abs(qb.x) / rb.x));
			alb = mix(alb, i_fur2.rgb, stripes * i_fur2.a);
		} else if (pat_id == 5 || pat_id == 6) {                     // knitted cap / toadstool cap
			float edge_y = pat_id == 5 ? 0.70 : 0.66;
			float wave = pat_id == 6 ? 0.025 * sin(fp.x * 26.0 + seed * 3.0) * 0.4 : 0.0;
			float edge = edge_y + 0.012 * (vnoise(vec2(fp.x * 9.0 + seed * 7.0, 0.0)) - 0.5) * 2.0 + wave
					- 0.05 * (fp.x / rb.x) * (fp.x / rb.x);
			float cap = smoothstep(edge - 0.01, edge + 0.01, ps.y);
			float brim = (1.0 - smoothstep(0.0, 0.035, abs(ps.y - edge + 0.012))) * (1.0 - cap);
			alb *= 1.0 - 0.07 * brim;
			vec3 cap_col = i_fur2.rgb;
			if (pat_id == 5) {
				// knit rib texture: faint vertical ribs
				cap_col *= 1.0 - 0.04 * (0.5 + 0.5 * sin(fp.x * S * 0.35));
			}
			alb = mix(alb, cap_col, cap * i_fur2.a);
			float dome_hl = exp(-dot((fp - vec2(-0.12 * rb.x, 0.88)) / vec2(0.28, 0.09), (fp - vec2(-0.12 * rb.x, 0.88)) / vec2(0.28, 0.09)));
			alb = mix(alb, mix(alb, i_tip.rgb, 0.6), dome_hl * cap * 0.35);
			if (pat_id == 6) {
				float spots = 0.0;
				for (int k = 0; k < 6; k++) {
					float fk = float(k);
					float hx = h12(vec2(fk * 3.7, i_misc.x * 13.0 + 1.0));
					float hy = h12(vec2(fk * 5.1, i_misc.x * 7.0 + 2.0));
					float hr = h12(vec2(fk * 1.3, i_misc.x * 3.0 + 4.0));
					vec2 sc_ = vec2((hx - 0.5) * 1.6 * rb.x, edge_y + 0.07 + hy * (0.30 - 0.07));
					float rr = mix(0.04, 0.07, hr);
					spots = max(spots, 1.0 - smoothstep(rr - 0.01, rr + 0.008, length(fp - sc_)));
				}
				alb = mix(alb, i_accent.rgb, spots * cap);
			}
		} else if (pat_id == 7) {                                    // soft spots on back and sides
			float spots = 0.0;
			for (int k = 0; k < 8; k++) {
				float fk = float(k);
				float ha = h12(vec2(fk * 2.3, i_misc.x * 11.0 + 3.0));
				float hb = h12(vec2(fk * 4.9, i_misc.x * 5.0 + 6.0));
				float hr = h12(vec2(fk * 7.1, i_misc.x * 9.0 + 8.0));
				float side = mod(fk, 2.0) * 2.0 - 1.0;
				vec2 sc_ = vec2(side * (0.55 + 0.4 * ha) * rb.x, 0.2 + hb * 0.7);
				float rr = mix(0.05, 0.09, hr);
				spots = max(spots, 1.0 - smoothstep(rr - 0.02, rr + 0.01, length(fp - sc_) + (pn - 0.5) * 0.02));
			}
			float face_mask = smoothstep(0.08, 0.2, length((fp - vec2(0.0, ey - 0.02)) / vec2(ex + ew + 0.06, 0.18)) - 0.7);
			alb = mix(alb, i_fur2.rgb, spots * face_mask * (1.0 - bel) * i_fur2.a);
		}
		// felt mottling (object anchored) + a fine fibre sheen
		vec2 dp = ps * S / PX_PER_DP;
		float mot = (vnoise(ps * 9.0 + seed * 13.0) * 0.05 - 0.025);
		mot += lod > 0.5 ? 0.0 : (vnoise(ps * 31.0) * 0.03 - 0.015);
		float hair = lod > 0.5 ? 0.0 : (vnoise(rot(dp, seed * 6.0) * vec2(1.6, 0.35)) - 0.5) * 0.035;
		float noise_k = mix(1.0, NIGHT_GRAIN, 1.0 - smoothstep(0.35, 0.8, luma(l_ambient.rgb)));
		vec3 body_alb = alb * (1.0 + (mot + hair) * noise_k);
		alb = mix(body_alb, alb_part * (1.0 + mot * 0.8), w_part);
		// fibre tips are lighter (outer band and fringe)
		float depth_in = clamp(-d_px / (0.35 * S), 0.0, 1.0);
		float night_k = 1.0 - smoothstep(0.35, 0.8, luma(l_ambient.rgb));
		float tip_k = mix(1.0, NIGHT_TIP, night_k);
		float tipband = smoothstep(0.55, 1.0, 1.0 - depth_in) * i_tip.a * smoothstep(-0.85, 0.1, n2.y) * tip_k;
		vec3 tip_col = mix(alb, mix(i_tip.rgb, alb, w_part * 0.6), 0.85);
		alb = mix(alb, tip_col, tipband * fz);
		float in_fringe = 1.0 - core;
		alb = mix(alb, tip_col, in_fringe * 0.7 * smoothstep(-0.9, -0.2, n2.y) * tip_k);
		alb *= mix(1.0, NEAR_ALBEDO, v_near);
		alb = max(mix(vec3(luma(alb)), alb, 1.0 + FOCAL_CHROMA * focal), vec3(0.0));

		// 6. light: ambient multiply, felt pillow volume, wrapped key, hue-shifted shade, top light, AO
		vec2 L2 = normalize(l_keyv.xy);
		float lz = mix(KEY_Z_DAY, KEY_Z_BACKLIT, l_backlight) * (0.6 + 0.4 * l_keyv.z);
		vec3 L3 = normalize(vec3(L2 * sqrt(max(1.0 - lz * lz, 0.0)), lz));
		float pr = mix(PILLOW_R, pr_part, w_part);
		float t = clamp(-d / pr, 0.0, 1.0);
		float tz = 1.0 - t;
		vec3 n3 = normalize(vec3(n2 * tz, sqrt(max(1.0 - tz * tz, 0.0)) + 0.02));
		float diff = clamp((dot(n3, L3) + WRAP) / (1.0 + WRAP), 0.0, 1.0);
		float up = smoothstep(0.05, 0.95, ps.y);
		float ao = 1.0 - smoothstep(0.0, 0.25, ps.y);
		float dark = 1.0 - smoothstep(0.35, 0.8, luma(l_ambient.rgb));
		// the fur's own ambient: lifted toward white under the low golden sun (cream stays >= L* 78,
		// cool fur never turns grey-mauve; QA r3) and the rain's ambient_mult divided back out
		vec3 amb = mix(l_ambient.rgb, vec3(1.0), GOLDEN_AMB_LIFT * l_backlight * (1.0 - dark) + NIGHT_AMB_LIFT * dark);
		amb /= mix(1.0, u_rain_amb, l_rain);
		float amb_l = luma(amb);
		// ambient multiply that keeps part of the fur's own hue (species identity at night)
		vec3 col = mix(alb * amb, alb * amb_l, mix(HUE_KEEP_DAY, HUE_KEEP_NIGHT, dark));
		vec3 shade = col * mix(vec3(1.0), l_shadow.rgb * SHADE_K, SHADE_MIX * (1.0 - 0.5 * dark)) * mix(SHADE_DARK, SHADE_DARK_BACKLIT, l_backlight);
		col = mix(shade, col, 0.08 + 0.92 * diff);
		// form (QA r3 c1): lit crown -> core shadow on the turned-away side -> a little ground
		// bounce on the lower shadow-side edge -> rim. The bounce keeps the core band the darkest
		// value, so the body reads round at 48 dp instead of a flat pastel disc.
		float edge_k = 1.0 - smoothstep(0.0, 0.5, t);
		float away = 1.0 - smoothstep(0.05, 0.55, diff);
		float low_side = smoothstep(0.45, -0.6, n2.y);
		col += alb * mix(u_ground.rgb, amb, 0.35) * BOUNCE_K * away * edge_k * (0.35 + 0.65 * low_side) * (1.0 - 0.6 * dark);
		col += alb * l_key.rgb * SHEEN_K * diff * diff * diff * up * (1.0 - 0.7 * l_backlight) * (1.0 - dark);
		// felt scatters light: a faint warm glow where light turns into shade
		col += alb * l_key.rgb * amb * 0.05 * diff * (1.0 - diff) * 4.0;
		col = mix(col, col * l_shadow.rgb * SHADE_K * SHADE_DARK, ao * AO_MAX * CREATURE_AO * (1.0 - 0.6 * w_feet));
		col += l_key.rgb * KEY_TOP * up * (0.5 + 0.5 * diff) * (1.0 - 0.6 * l_backlight);
		col *= mix(0.94, 1.03, smoothstep(0.0, 0.6, depth_in));
		// the seat half sits in its own soft occlusion (top-lit felt, value step crown -> base)
		col *= mix(1.0 - LOWER_DARK * (1.0 - 0.5 * dark), 1.0, smoothstep(0.05, 0.62, ps.y));
		// backlit (golden hour): the sun is behind, so the face toward us sits in its own shade
		float front = FRONT_DARK * l_backlight * smoothstep(0.05, 0.45, depth_in);
		col = mix(col * (1.0 - front), col * l_shadow.rgb * SHADE_K, front * 0.5);
		col = mix(col, col * l_shadow.rgb * SHADE_K, max(v_env.y * (1.0 - st), i_light.w));   // passing cloud shadows
		// the leaf umbrella's soft shade on the crown (offset to the side it is held on)
		vec2 uq = (ps - vec2(facing * 0.12 * wh, 1.02)) / vec2(0.42 * wh, 0.26);
		col = mix(col, col * l_shadow.rgb * SHADE_K, UMB_SHADE_A * umb * exp(-dot(uq, uq) * 1.6));

		// rim and backlit peach fuzz (§5.6.6); the bottom edge never lights up
		float lam = clamp(dot(n2, L2), 0.0, 1.0);
		float rup = smoothstep(-0.35, 0.75, n2.y);
		float rim_w = mix(4.5, 9.0, l_backlight);
		// thin parts: the rim fades toward the medial line, so it never flips edge to edge
		// crisp: the band rises steeply at the silhouette and falls off fast inside (QA r3 c3/c1)
		float band_in = smoothstep(-rim_w, -1.0, d_s);
		float band = band_in * band_in * (1.0 - smoothstep(0.55, 1.0, t));
		// backlit: the whole upper and side contour catches the sun (peach fuzz), lit side strongest
		float rim = band * mix(lam * lam, mix(rup, 1.0, 0.3) * (0.4 + 0.6 * lam), l_backlight) * l_rim
				* smoothstep(-0.8, -0.1, n2.y);
		// peach: the key warmed toward the glow of the sky around the sun
		vec3 rim_col = mix(l_key.rgb, max(l_glow.rgb, l_key.rgb), 0.45 * l_backlight);
		float rim_k = mix(1.0, NEAR_RIM, v_near) * (1.0 + FOCAL_RIM * focal);
		col += rim_col * rim * RIM_GAIN * (1.0 + RIM_BACKLIT_GAIN * l_backlight) * (1.0 - dark) * rim_k;
		col += l_key.rgb * amb * FOCAL_LIFT * focal * up;
		float fuzz_glow = clamp((fringe_a * in_fringe + band * 0.35 * rup) * l_backlight * rup, 0.0, 1.0) * rim_k;
		col = mix(col, mix(col, rim_col, 0.85) * 1.12, fuzz_glow * smoothstep(-3.0, 0.0, d_s) + fuzz_glow * 0.35 * band);
		// night: a thin cool moon rim on the key-facing fringe separates friends from the navy meadow
		// masked to the moon-facing (upper-right) edges, so the moonlight has a direction
		float mface = smoothstep(0.05, 0.7, dot(n2, L2) * 0.9 + n2.y * 0.25);
		float mband = smoothstep(-MOON_RIM_PX * 2.0, -0.5, d_s) * mface * (1.0 - smoothstep(0.6, 1.0, t));
		float ma = clamp(mband * MOON_RIM_A * dark * (1.0 + 0.4 * NIGHT_RIM * lam), 0.0, MOON_RIM_MAX);
		col = mix(col, l_key.rgb * mix(0.85, 1.0, lam), ma);
		col += l_key.rgb * MOON_RIM_GLOW * ma * mface;

		// 7. lantern light (Mossling writes i_light from LampRegistry at 2 Hz): a warm screen fill
		// stronger on the lamp-facing side, plus a warm rim on that edge (QA round 1)
		float lampw = i_light.z * l_lights * (1.0 - lod * 0.5);
		float lface = clamp(dot(n2, normalize(i_light.xy + vec2(0.0, 0.35))), 0.0, 1.0);
		vec3 lamp_a = g_accent.rgb * clamp(lampw * LAMP_FILL_K * (0.3 + 0.7 * lface) * (0.6 + 0.4 * up), 0.0, LAMP_FILL_MAX);
		col = 1.0 - (1.0 - col) * (1.0 - lamp_a);
		float lband = smoothstep(-LAMP_RIM_PX * 2.0, -0.5, d_s) * lface * lface;
		col = mix(col, g_accent.rgb, clamp(lband * LAMP_RIM_A * min(lampw * 2.5, 1.0), 0.0, LAMP_RIM_A));

		// 9. emission: the glow bobble warms toward its accent at night
		col = mix(col, i_accent.rgb * 1.1, emit_mask * i_accent.a * l_lights * mix(1.0, 0.4, sleep) * w_part);

		// 8. face (body only, never on parts) ----------------------------------------------
		float on_body = (1.0 - w_part) * core;
		float look = i_anim.w;
		vec3 ink = i_eye.rgb * mix(vec3(1.0), l_ambient.rgb, 0.5);
		float night = 1.0 - smoothstep(0.35, 0.8, luma(l_ambient.rgb));
		vec3 shine_col = u_shine.rgb * mix(1.0, NIGHT_SHINE, night) * mix(vec3(1.0), l_ambient.rgb, 0.25);
		float lid = clamp(i_anim.z, 0.0, 1.0);
		float closed = closed_id;
		float hl_side = sign(L2.x + 1e-3);
		float eye_id = i_face.x;
		float eyes = 0.0;
		float shine = 0.0;
		float lift = 0.0;
		float lash = 0.0;
		float stroke = 0.0;
		float lw = LINE_BU * S;
		for (int s = -1; s <= 1; s += 2) {
			float fs = float(s);
			float far_k = (abs(look) > 0.5 && fs * look < 0.0) ? mix(1.0, FAR_EYE, (abs(look) - 0.5) * 2.0) : 1.0;
			vec2 ec = vec2(fs * ex * mix(1.0, 0.94, abs(look)) + lx, ey);
			vec2 ep = ps - ec;
			float eww = ew * far_k;
			if (closed > 0.5 || lid > 0.85) {
				// closed arcs: 1 = sleep (convex down), 2 = happy (convex up); a blink ends as a sleep arc
				float ra = eww * 1.31;                               // chord = 1.1 x eye width
				float da;
				if (closed > 1.5) {
					vec2 aq = ep - vec2(0.0, 0.15 * eww - ra);
					da = sd_arc(aq, vec2(sin(1.0), cos(1.0)), ra, LINE_BU * 0.5) * S;
				} else {
					vec2 aq = ep - vec2(0.0, ra - 0.25 * eww);
					da = sd_arc(vec2(aq.x, -aq.y), vec2(sin(1.0), cos(1.0)), ra, LINE_BU * 0.5) * S;
				}
				stroke = max(stroke, 1.0 - smoothstep(-aa * 0.7, aa * 0.7, da));
			} else {
				float open_k = max(1.0 - lid, 0.08);
				vec2 er = vec2(eww, eww * EYE_ASPECT);
				// the lid closes from the top: scale about a point below the centre
				vec2 eq = vec2(ep.x, (ep.y + er.y * 0.35) / open_k - er.y * 0.35);
				float de = sd_ellipse(eq, er) * S;
				float e = 1.0 - smoothstep(-aa * 0.8, aa * 0.8, de);
				// sleepy eye: the upper 40 % is a fur-coloured lid with a soft lash line
				// relaxed lid: its edge arcs over the eye (convex up), never a flat "bored" cut
				float ux = eq.x / er.x;
				// drowsy lid: a soft felt eyelid over the top of the eye that follows the eye's own
				// curve (no dark lash line: a lash reads as a frowning brow at this size)
				float lid_y = er.y * (1.0 - 2.0 * mix(LID_AWAKE, LID_DROWSY, smoothstep(0.0, 0.6, sleep))) - 0.22 * er.y * ux * ux;
				float sl = eye_id > 0.5 ? smoothstep(-aa * 0.9, aa * 0.9, (eq.y - lid_y) * S) : 0.0;
				lash = max(lash, e * sl);
				eyes = max(eyes, e * (1.0 - sl));
				lift = max(lift, e * smoothstep(-0.1 * er.y, -0.8 * er.y, eq.y));
				// highlights on the light side
				vec2 h1 = vec2(-0.30 * -hl_side, 0.38) * er.x;
				float r1 = eye_id > 0.5 ? 0.22 : 0.36;
				vec2 h1p = eye_id > 0.5 ? vec2(0.25 * hl_side, 0.05) * er.x : h1;
				float ds1 = (length(eq - h1p) - er.x * r1) * S;
				float ds2 = (length(eq - vec2(-0.38 * hl_side, -0.42) * er.x) - er.x * 0.14) * S;
				float sh = 1.0 - smoothstep(-aa * 0.7, aa * 0.7, ds1);
				sh = max(sh, eye_id > 0.5 ? 0.0 : (1.0 - smoothstep(-aa * 0.7, aa * 0.7, ds2)) * 0.9);
				shine = max(shine, sh * e * (1.0 - sl) * smoothstep(0.85, 0.5, lid));
			}
		}
		// cheeks: small blush, or the big cheek patches of the "cheeks" pattern
		float blush = 0.0;
		for (int s = -1; s <= 1; s += 2) {
			vec2 bc = vec2(float(s) * (ex + 0.07) + lx, ey - 0.12 + 0.02);
			vec2 bp = (ps - bc) / vec2(0.085, 0.048);
			blush = max(blush, exp(-dot(bp, bp)));
			if (pat_id == 8) {
				float dc = length(ps - (bc + vec2(float(s) * 0.01, 0.02))) - 0.11;
				float patch_ = 1.0 - smoothstep(-0.025, 0.02, dc + (pn - 0.5) * 0.015);
				col = mix(col, i_fur2.rgb * l_ambient.rgb * (0.94 + 0.06 * diff), patch_ * on_body * i_fur2.a);
			}
		}
		float cheek_a = (i_cheek.a + 0.25 * happy) * (pat_id == 8 ? 0.55 : 1.0);
		col = mix(col, i_cheek.rgb * l_ambient.rgb, blush * cheek_a * on_body);
		// eyes
		vec3 eye_col = mix(ink, mix(ink, shine_col, 0.12), lift);
		col = mix(col, eye_col, eyes * on_body);
		col = mix(col, col * mix(vec3(1.0), l_shadow.rgb * SHADE_K, 0.08) * 0.9, lash * on_body);
		col = mix(col, shine_col, shine * on_body);
		col = mix(col, ink, stroke * on_body);
		// mouth: 1 smile, 2 "w"; a happy creature opens a tiny smile
		float mouth_id = i_face.w;
		vec2 mp = ps - vec2(lx * 1.1, ey - 0.075);
		float mline = 0.0;
		float mfill = 0.0;
		if (happy > 0.5) {
			vec2 mq = mp - vec2(0.0, 0.006);
			float dm = max(sd_ellipse(mq, vec2(0.042, 0.038)), mq.y) * S;
			mfill = 1.0 - smoothstep(-aa * 0.8, aa * 0.8, dm);
		} else if (mouth_id > 1.5) {
			float mr = 0.026;
			vec2 mq = vec2(abs(mp.x) - mr, mp.y + mr * 0.15);
			float dm = sd_arc(vec2(mq.x, -mq.y + mr * 0.2), vec2(sin(1.25), cos(1.25)), mr, LINE_BU * 0.4) * S;
			mline = 1.0 - smoothstep(-aa * 0.7, aa * 0.7, dm);
		} else if (mouth_id > 0.5) {
			float mr = 0.035;
			float dm = sd_arc(vec2(mp.x, -mp.y + mr * 0.55), vec2(sin(0.95), cos(0.95)), mr, LINE_BU * 0.4) * S;
			mline = 1.0 - smoothstep(-aa * 0.7, aa * 0.7, dm);
		}
		col = mix(col, ink, mline * 0.85 * on_body);
		vec3 tongue = mix(ink, i_cheek.rgb * l_ambient.rgb, smoothstep(0.0, -0.025, mp.y));
		col = mix(col, tongue, mfill * on_body);
		// nibble: a little clover held in the mouth (a stem to a three-lobed leaf on the facing
		// side), grows in with leaf_k; drawn over the tummy so it never leaves the silhouette
		if (leaf_k > 0.01) {
			float side = facing >= 0.0 ? 1.0 : -1.0;
			float lk = leaf_k;
			vec2 m0 = vec2(lx * 1.1, ey - 0.085);
			vec2 lc = m0 + vec2(side * 0.15, -0.12) * lk;
			float dstem = sd_capsule(ps, m0, lc, 0.012 * lk);
			float dclov = 1e3;
			for (int k = 0; k < 3; k++) {
				float a = (float(k) - 1.0) * 2.1 + side * 0.5;
				vec2 lob = lc + vec2(sin(a), cos(a)) * 0.046 * lk;
				dclov = min(dclov, length(ps - lob) - 0.044 * lk);
			}
			float dl = min(dstem, dclov) * S;
			float lcov = (1.0 - smoothstep(-aa * 0.8, aa * 0.8, dl)) * on_body;
			float ledge = smoothstep(-2.2, 0.0, dl);
			vec3 leaf_c = u_leaf.rgb * l_ambient.rgb * mix(1.0, 0.82, ledge);
			leaf_c += l_key.rgb * l_ambient.rgb * 0.12 * smoothstep(0.0, 0.03, dot(ps - lc, vec2(-side, 1.0)));
			col = mix(col, leaf_c, lcov);
		}

		// 10. finish: grain anchored to the creature + TPDF dither; premultiplied output + halo
		col = finish(col, dp * u_grain_density, FRAGCOORD.xy, GRAIN_OBJECT * mix(1.0, NIGHT_GRAIN, night));
		COLOR = vec4((col * cover + halo_rgb) * (1.0 - nest_a) + nest_col * nest_a, cover + nest_a * (1.0 - cover)) * fade;
	}
}
