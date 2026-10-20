# 05 — Visual & Motion Aesthetics for a 2026–27 Cozy Mobile Game

Art-direction research for the chill/idle/cozy portrait game, Godot **4.7.2-stable**, Compatibility renderer (see 01 and 02). Date: 2026-10-20.

**Evidence tags.** **[V]** = verified by me in a primary source: engine source or doc XML, official platform docs, or token source code. **[H]** = published research, or a fact reported by several secondary sources. **[J]** = our judgement.

**Units.** 1 dp ≈ 3 px on 02's 1080×1920 base (a 360-dp-wide reference phone). Colours are sRGB hex. L* is CIELAB lightness. ΔE_OK is Euclidean OKLab distance ×100 (about 2 is one just-noticeable difference: CSS Color 4 sets JND = 0.02 in OkLCh [36]; a spec convention, not a psychophysical measurement) [H].

---

## 0. Decisions at a glance

### 0.1 STYLE PROPOSAL — "Felted Diorama"

| Aspect | Decision | Basis |
|---|---|---|
| Look | A layered 2D paper-and-felt **diorama**: painterly OKLab gradients, soft light, a quiet grain anchored to each object, and fuzzy rim-lit edges on creatures. Frosted-glass UI floats over a living world. | §1, [J] |
| Shape language | Primary shapes are circles and squircles. Secondary shapes are leaves and teardrops. Tertiary shapes are rounded 4-point sparkles. Friendly objects have no interior angle under 60° (04 P7). Props are bottom-heavy. Creatures follow the baby schema: head:body 1:1–1:1.3, eyes in the lower half of the head, eye width ≥ 18 % of head width. | [H] Bar & Neta 2006 (curvature preference); Glocker 2009 (baby-schema features: round face, high forehead, large eyes) (via 04). The specific ratios (1:1–1:1.3, 18 %) are **[J]**, not from either paper |
| Corner radii (dp) | `r-xs 8`, `r-s 10`, `r-m 16`, `r-l 24`, `r-xl 32`, `r-pill`. **Concentric rule:** inner radius = outer radius − padding (min 8, per 04 P7 "UI corner radius ≥ 8 dp"; if the result is < 8, increase the outer radius). StyleBoxFlat `corner_detail` = 12–16 for r ≥ 24. | [V] Apple asks for controls concentric with their containers [1]; [V] StyleBoxFlat default `corner_detail=8` |
| Outlines | None on the world. Interactive and hero objects get a 2 dp **colour line** (fill colour at ΔL* −30, hue moved toward the shadow tint). Black lines are never used. | §4, [J] |
| Palette system | 5 time-of-day palettes (§0.4), stored as `Gradient` resources with `interpolation_color_space = GRADIENT_COLOR_SPACE_OKLAB` and sampled by a global `g_day`. The UI palette stays the same at every time of day. | [V] Gradient.xml; [25] |
| Lighting | 3-stop sky gradient, additive sun/moon halos, a per-palette ambient multiply, a key-light rim of 1.5–3 dp, and tinted (never black) contact shadows at α 0.18–0.35. Fake AO is a 15–25 % darkening gradient at the base of each object. | §2.3 |
| Texture | Static grain anchored to each object: uniform noise, peak ±2 % at mid-grey (σ ≈ 1.2 %), weighted toward midtones by 4L(1−L), 1 dp cells (matches the §2.4 snippet). **No** animated full-screen grain. | §2.4 |
| Banding | TPDF dither of ±1 LSB in every gradient, halo, fog and glass shader. | [H] Lipshitz 1992 [17]; Jimenez 2014 [18] |
| Depth | 6 layers: sky, celestial, far, mid, play, foreground frame. Scroll factors 0 / 0.02 / 0.1 / 0.3 / 1.0 / 1.3. Haze 65 % / 35 % / 0–8 %; the foreground frame is darkened and blurred instead. | §2.5; [H] O'Shea 1994 [20] |
| Particles | At most 3 systems on screen and at most 150 particles in total (the §2.6 weather rows are sized to fit this cap). Calm speeds come from real fall-speed physics (§2.6). Turbulence is avoided on mobile (engine docs warn of a high GPU cost). | [H] [27][28][29]; [V] ParticleProcessMaterial.xml:401 |
| UI material | Only **one** real blurred glass surface at a time (the sheet or modal). Everything else uses "faux glass" with no screen read. Tint is 60–72 % Cloud Dancer, with a 1 dp specular rim and a tinted soft shadow. | [V] [1]; 01 §5 (≤ 1 screen read per frame) |
| Type | **Baloo 2 Variable** (display and numbers, wght 600–800) and **Nunito Variable** (UI and body, wght 500–800). Both are OFL, both include Vietnamese, both from `@fontsource-variable/*` 5.3.0 (Baloo 2 wght axis 400–800; Nunito 200–1000). Godot imports `.woff2`. Fredoka has **no** Vietnamese subset. **Caveat:** Fontsource ships each subset as a separate `.woff2` split by `unicode-range` (e.g. `baloo-2-vietnamese-wght-normal.woff2` holds only U+0102–0103, U+1EA0–1EF9, combining marks…). Load `latin` as the base `FontFile` and add `latin-ext` + `vietnamese` to `Font.fallbacks`, or merge the subsets offline; test Vietnamese strings (NFC) for diacritic placement. | [V] npm metadata + package `index.css`; `resource_importer_dynamic_font.cpp:55`; Font.xml:367 (`fallbacks`) |
| Icons | Filled, rounded terminals, duotone (ink plus 40 % accent), drawn on a 24 dp grid. | [J] |
| Accessibility | Provide in-game **Reduce Motion** and **Reduce Transparency** toggles. On iOS and Android, 4.7.2 returns −1 from `DisplayServer.accessibility_should_reduce_animation/transparency()`: "implemented on macOS and Windows" only. | [V] DisplayServer.xml:115-127 |

### 0.2 MOTION TOKENS

**Principle: fast feedback, slow world.**

| Token | Duration | Curve | Godot 4.7 | Use |
|---|---|---|---|---|
| `instant` | 0 ms | — | set the property directly | Colour/state change on touch-down |
| `micro` | **100 ms** (80–120) | ease-out | `TRANS_QUAD`, `EASE_OUT` | Press-down to scale 0.95; toggle thumb |
| `release` | about 330 ms to settle | spring `pop` | analytic spring (01 §4.2), or `TRANS_BACK`+`EASE_OUT` (10 % overshoot) | Button release, item pickup |
| `short` | **200 ms** (150–240) | M3 standard `cubic-bezier(0.2,0,0,1)` | custom interpolator (§3.2). The best built-in is `TRANS_CUBIC`+`EASE_OUT`, but its max error is 0.13 | Fades, chips, icon swaps |
| `standard` | **320 ms** (280–360) | M3 emphasized-decelerate `(0.05,0.7,0.1,1)` | custom. The best built-in is `TRANS_EXPO`+`EASE_OUT`, max error 0.155 | Elements entering or moving; half sheet |
| `emphasized` | **500 ms** (450–600) | `(0.2,0,0,1)` or spring `move` | custom or spring | Full sheet, room change, reward reveal |
| `exit` | 0.6–0.7 × the matching enter | `(0.3,0,0.8,0.15)` | `TRANS_CUBIC`+`EASE_IN` (error 0.046) | Dismissals |
| `celebrate` | 700–1200 ms | spring `pop` plus particles | — | New creature or unlock. **Never blocks input for more than 1 s** |
| `stagger` | 30 ms per item, 240 ms cap | — | `set_delay(i*0.03)` | Lists, reward items |
| `ambient` | 3–12 s loops | `easeInOutSine` ≈ `(0.37,0,0.63,1)` | `TRANS_SINE`+`EASE_IN_OUT` (error 0.002) | Breathing, sway, glow pulse. Periods are φ-spaced: 3.0 / 4.85 / 7.85 / 12.7 s |
| `world` | 20–180 s | linear or sine | — | Cloud drift, sun travel, weather crossfade (20–40 s) |
| `tod` | device clock | OKLab lerp | `Gradient.sample(g_day)` | Palettes crossfade over 30–45 min of real time |

Basis: M3 durations of 50–1000 ms and the beziers above are **[V]** from androidx `MotionTokens.kt` [5]. The responsiveness limit of ≤ 100 ms is [H] from Nielsen (0.1 s feels instantaneous) [37]. The built-in fit errors are **[V]**: I computed them against `scene/animation/easing_equations.h`. Overshoot of the built-ins (Back 10.0 %, Spring 8.4 %, Elastic 37.3 %) is [V] and matches 01.

### 0.3 SPRING TOKENS (mass = 1)

| Token | f (Hz) | ζ | Stiffness k=(2πf)² | Damping c=2ζ·2πf | Overshoot | Settle (2 %) | SwiftUI equivalent `(duration, bounce)` | Use |
|---|---|---|---|---|---|---|---|---|
| `press` | 6.0 | 0.90 | 1421 | 67.9 | 0.2 % | 118 ms | (0.167, 0.10) | Touch-down, tracking the finger. Same as M3 standard *fast spatial* (1400 / 0.9) [5] |
| `move` | 2.4 | 0.80 | 227 | 24.1 | 1.5 % | 332 ms | (0.417, 0.20) | Panels, drag release. Close to M3 Expressive *slow spatial* (200 / 0.8) |
| `pop` | 3.2 | 0.60 | 404 | 24.1 | 9.5 % | 332 ms | (0.312, 0.40) | Rewards, release pop. Same ζ as M3 Expressive *fast spatial* (800 / 0.6) but half its stiffness (≈ 0.71× its frequency): a deliberately slower pop [J] |
| `jelly` | 2.6 | 0.40 | 267 | 13.1 | 25 % | 612 ms | (0.385, 0.60) | **Creature body only**, at amplitude ≤ 12 % |
| `follow` | 1.6 | 0.35 | 101 | 7.0 | 31 % | 1.14 s | (0.625, 0.65) | Secondary motion: ears, leaves, antennae, hanging signs |

Conversions **[V]**: Apple gives stiffness = (2π/duration)² and, for bounce ≥ 0, damping = (1−bounce)·4π/duration (mass = 1) [7]. Its own example, `Spring(duration:0.5,bounce:0.3)` → (mass, stiffness, damping) = (1.0, 157.9, 17.6), and the reverse example `Spring(mass:1, stiffness:100, damping:10)` → (0.63, 0.5), both confirm ζ = 1 − bounce. Overshoot = exp(−ζπ/√(1−ζ²)) and settling time ≈ 4/(ζω) are standard second-order-system results [16].

Apple's guidance [8] is to **start at 100 % damping** and add bounce **only when the gesture has momentum**. Its examples are 100 % for a tap-to-open and 80 % for swipe-dismiss. Animations must stay **interruptible**: the next spring starts from the current velocity. Godot's `TRANS_SPRING` is a fixed-shape curve that carries no velocity, so drags and flings use the analytic spring.

### 0.4 PALETTES (contrast and colour-vision deficiency checked with a script, §2.2)

| Slot | Dawn | Day | Golden hour | Dusk (blue hour) | Night |
|---|---|---|---|---|---|
| `sky_top` | `#8EA3D8` | `#6FB6EC` | `#7A8DCB` | `#2D3A70` | `#111938` |
| `sky_mid` | `#C8B5E0` | `#9ED2F2` | `#E8A3A1` | `#6C5C9E` | `#1D2954` |
| `sky_horizon` (= haze colour) | `#F7CBB7` | `#D6EEF6` | `#FFCB7D` | `#F0A08C` | `#3D4F8C` |
| `glow` (sun/moon halo) | `#FFE6C7` | `#FFF5D6` | `#FFE29E` | `#FFB98E` | `#DDE7FF` |
| `far` silhouette | `#C9B9D6` | `#A8D4CC` | `#DCAA8F` | `#6F6494` | `#2E3C6B` |
| `mid` silhouette | `#9E99BE` | `#7DBF91` | `#B98670` | `#4E487C` | `#222E58` |
| `near` ground | `#717FA6` | `#4FA06F` | `#7F6A72` | `#373762` | `#182246` |
| `fg` frame | `#4F5C82` | `#2F7B5B` | `#5A4A62` | `#262849` | `#0F162E` |
| `ambient` (multiply on world) | `#E2D6EE` | `#FFFFFF` | `#FFE0C2` | `#B3A3D1` | `#5D6AA0` |
| `key` (rim / key light) | `#FFD6AE` | `#FFF1C2` | `#FFC266` | `#FF9E7E` | `#9DB4FF` (moon) |
| `shadow` tint | `#5D5C8E` | `#3B6C8C` | `#6A4E80` | `#1F2244` | `#0B1130` |
| `accent` (flowers, lanterns) | `#FFB59E` | `#FFC56E` (+ `#FFB3C7`) | `#FF8C7A` | `#FFC46B` | `#FFC978` |

| UI token | Hex | Checked use |
|---|---|---|
| `surface` (Pantone 2026 Cloud Dancer) | `#F0EEE9` | Base for glass and cards |
| `surface_hi` | `#FFFDF8` | Raised cards, pressed highlight |
| `ink` | `#2A2838` | Text on surface: **12.4:1** |
| `ink_2` | `#5D596E` | Secondary text: **5.8:1** |
| `primary` (nod to WGSN 2027 "Luminous Blue", see §1.1 flag) | `#4A6FD6` | White text on it: **4.63:1** (`surface_hi` text: 4.55:1; `surface` text: 3.99:1 = **fails** AA). Non-text on surface: 3.99:1 |
| `coral` | `#FF9A7A` | Ink text on it: 6.96:1. Fill only, never text on surface (1.78:1) |
| `leaf` | `#256F5C` | White text on it: 5.99:1. On surface: 5.16:1 |
| `gold` (currency) | `#FFCB57` | Ink text on it: 9.55:1 |
| `scrim` | `#1B1A2E` @ 40 % | Dim behind modals |

The semantic set {primary, coral, leaf, gold} keeps a minimum ΔE_OK of **≥ 10** for every pair under protan, deutan and tritan simulation (Machado 2009, severity 1.0 [23], matrices applied in linear RGB; the tightest pass is coral–gold under deutan at exactly 10.0). The one exception is primary–leaf under tritan, at 8.9 (7.0 if the matrices are applied to gamma-encoded sRGB, as some tools do). Tritan defects are rare (commonly cited at ≤ 0.01 % of people; not re-verified here) [H]. Colour is still never the only cue (WCAG 1.4.1 [26]): pair it with an icon and a shape.

---

## 1. What reads as "2026–27 premium" and what reads as dated

### 1.1 Signals of the current design language (with evidence)
- **Translucent functional layer over content.** Apple's Liquid Glass (WWDC25) "forms a distinct functional layer for controls and navigation". Apple says to "avoid overusing Liquid Glass effects" and to avoid "layering Liquid Glass elements on top of each other" [1] [V].
  - The **2026 evolution** is about readability. NN/g criticised iOS 26 legibility [4] [H]. iOS 26.1 added a Clear/Tinted choice [H]. **FLAGGED:** the claim that WWDC26/iOS 27 turned this into an opacity slider rests on pre-WWDC rumour pieces and low-reliability blogs [3]; it is not in Apple's current Liquid Glass or Materials docs. Treat it as unconfirmed.
  - Apple HIG (Materials) does say: for *clear* Liquid Glass over bright content, "consider adding a dark dimming layer of 35% opacity" [V] [1b]. That supports our high-opacity choice.
  - → **Our glass is frosted and high-opacity (60–72 % tint), not clear.**
- **Expressive, springy, shape-aware motion.** Material 3 Expressive (May 2025) moved Compose to spring physics. The verified tokens: Expressive spatial springs are fast 800/0.6, default 380/0.8, slow 200/0.8; Standard springs are 1400/700/300 at ζ 0.9; effects springs use ζ 1.0 [5] [V].
  - Google cited 46 studies with more than 18,000 participants behind the move [6]. That comes from a since-deleted Google post, so it is secondhand [H].
  - Haptics are paired with springy motion [6] [H].
- **Rounder, concentric geometry.** Apple: controls "adopt rounder forms", with shapes "concentric to their containers"; sheets get larger radii [1] [V].
- **Layered depth and light, not flat fills.** App icons are now built from layers with system "reflection, refraction, shadow, blur, and highlights", designed as "solid, filled, overlapping semi-transparent shapes" [1] [V]. That brief maps directly onto SVG.
- **Calm, warm neutrals with a confident blue.** Pantone 2026 is **Cloud Dancer 11-4201**, a "calming" white, widely reported as `#F0EEE9` [10] [H]. WGSN×Coloro's 2027 colour is reported as **Luminous Blue** (Coloro 125-28-38) [11]. **FLAGGED:** the fact-checker could not reach WGSN/Coloro or any secondary source to confirm the name, code or date. Our blue is chosen on contrast grounds anyway, so nothing depends on it.
- **What gets awarded.**
  - ADA 2025 (games): *Infinity Nikki* (Visuals & Graphics), *Art of Fauna* (Inclusivity), *Balatro* (Delight & Fun), *DREDGE* (Interaction), *PBJ – The Musical* (Innovation), *Neva* (Social Impact) [12] [V].
  - ADA 2026 (games): *Is This Seat Taken?* (Delight & Fun), *Sago Mini Jinja's Garden* (Interaction), *Pine Hearts* (Inclusivity), *Blue Prince* (Innovation), *Consume Me* (Social Impact), *Cyberpunk 2077 Ultimate Edition* (Visuals & Graphics) [2] [V].
  - Google Play Best of 2025: *Pokémon TCG Pocket* (Best Game), *Chants of Sennaar* (Best Indie) [13]. **FLAGGED:** not re-verified (blog.google was unreachable).
  - Common thread [J]: one coherent, authored style, executed consistently. Most winners do not win on raw fidelity, but not all: 2026 Visuals & Graphics went to *Cyberpunk 2077*. The stylised winners (*Infinity Nikki*, *Is This Seat Taken?*, *Sago Mini*, *Pine Hearts*) are the relevant benchmark for us.
- **Apple's featuring criteria for games** include "art and animation", "technical performance", accessibility and localization [9] [V]. That is why the rubric in §5 weights consistency, performance and accessibility.

### 1.2 Premium vs dated (our filter) [J unless tagged]

| Reads 2026–27 premium | Reads dated (avoid) |
|---|---|
| Soft, local glows: additive halos on light sources | Full-screen HDR bloom, lens flares, chromatic aberration (2007–12 era) |
| Painterly OKLab gradients with dither and grain | Banded sRGB gradients; pure flat fills with hard 90° drop shadows ("flat 2014") |
| Frosted glass with a 1 dp specular rim, used sparingly | Glassmorphism-2021 at low contrast; glass on glass |
| Tactile "squishy" springs, ζ 0.6–0.9 | Linear tweens; `TRANS_ELASTIC`/bounce on everything (2015 "jelly" UI) |
| Rounded, concentric shapes, hue-shifted shadows | Leather/wood skeuomorphism; glossy "Web 2.0" gel buttons |
| Restrained palettes, warm neutrals, one blue accent | Neon synthwave/vaporwave; 100 %-saturation candy palettes |
| Diegetic UI (signposts, letters, birds), minimal HUD | HUD-heavy "casual F2P" frames: thick black outlines, bevels, red badges everywhere |
| Atmospheric perspective, parallax, live time of day and weather | Static backdrop, one global tint |
| Micro-feedback on every touch, synced with haptics | Screen shake, flash-bang "juice", hit-stop |
| Visible authored craft | An over-smooth "generated" look with incoherent detail (player backlash in 2025–26 [J]) |

---

## 2. Style proposal: details

### 2.1 Shape and silhouette rules
- **Thumbnail test.** Every creature or prop must read as a black silhouette at 32×32 px. Hero creatures must read at 48 dp.
- **Big–medium–small.** Each object has one dominant mass (~60 % of its area), 1–3 secondary masses (~30 %) and small accents (~10 %). Never use equal-sized parts.
- **Asymmetry.** Faces may be symmetric. Poses, leans (±2–4°), ears and tufts may not.
- **Landscape silhouettes** aim for a fractal dimension D ≈ 1.3–1.5 (04 P8). Build them from 4–6 octaves of 1D value noise at lacunarity 2 and **gain 0.62–0.71**. For an fBm profile, D = 2 − H with per-octave gain = 2^(−H) [38], so the commonly used gain 0.5 gives H = 1, D ≈ 1.0, a smooth line. Measure D with 04's box-counting script; with few octaves the scaling range is short.
- **SVG authoring.** Prefer filled shapes to strokes. Use `stroke-linejoin="round"` and `stroke-linecap="round"`. Give volume with one 2-stop linear gradient per shape, ΔL* 8–12, lit from the top. Reserve `feGaussianBlur` for shadows and halos only. ThorVG supports it [V] (01 §2; ThorVG 1.0.3 in `thirdparty/thorvg`: `tvgSvgLoader.cpp:2151`, `tvgSvgSceneBuilder.cpp:369`, SW engine `tvgSwPostEffect.cpp`). The blur is baked when the SVG is rasterised at import, so it costs nothing per frame.

### 2.2 Palette method and checks
- The palettes in §0.4 were tuned with a script (`/tmp/claude-research/05/pal.py`). It computes WCAG 2.x contrast, OKLCh, and ΔE_OK under Machado-2009 CVD matrices [23].
- **Layer value ladder (day).** L* runs 82 (far), 72 (mid), 60 (near), 46 (fg). Contrast against the horizon runs 1.34 → 1.79 → 2.64 → 4.24. Contrast rises toward the camera, which is atmospheric perspective. Contrast loss is a measured depth cue (O'Shea et al. 1994 [20]) [H]. Dawn and golden hour follow the same ladder.
- **Night compresses the ladder** (CR 1.36 → 2.29). That is deliberate: focal hierarchy at night comes from **warm light pools**, not from silhouettes. Night is blue-shifted to stand in for scotopic vision (Thompson, Shirley & Ferwerda 2002 [22]) [H]. Keep the minimum L* ≥ 6 (no pure black) [J].
- **Accent rule.** Any interactive or accent colour sits **≥ 15 L\*** away from its background. That way it survives CVD and the squint test.
  - Example: the original day accent `#FF8A5C` on green `#4FA06F` scored only ΔE 3.5 under protan simulation. It was replaced by marigold `#FFC56E` (ΔE 16.9).
- **Hue-shifted shadows and lights** (Gurney 2010 [21]) [H].
  - Shadow: −15 to −25 L*, hue rotated toward 240–290° (blue/violet), chroma roughly unchanged.
  - Lit side: +8 to +15 L*, hue toward 75–95°.
  - The ambient multiply colours in §0.4 do this automatically. Sample result: grass `#7DBF91` → `#2E4F5B` at night, and `#7DA86E` at golden hour.
- **Interpolate in OKLab** (Godot `Gradient` supports it [V]). An sRGB lerp from dusk to night goes muddy and grey [25] [H].

### 2.3 Lighting model (canvas_item, Compatibility-safe)
1. **Sky.** One opaque full-screen quad (`render_mode blend_disabled`). Blend `top→mid→horizon` with smoothstep, plus a horizon haze band (8–12 % of screen height), plus TPDF dither.
2. **Sun and moon.** Disc of 28–40 dp. Two additive radial halos (`GradientTexture2D.fill = FILL_RADIAL`):
   - inner halo at radius 1.5× the disc, α 0.6;
   - outer halo at 6–10× the disc, α 0.15–0.30, with falloff ≈ 1/(1+(r/r₀)²).
   - At golden hour, make the outer halo 1.5× wider and warmer.
   - This replaces `Environment` glow, which is simplified under Compatibility (01 R5) [V].
3. **Key light.** A global `g_sun_dir` drives three things: which side gets the rim, the shadow offset, and the shadow length (longer when the sun is low, clamped at 2.5× object height).
   - Rim: 1.5–3 dp, alpha 0.35 at day, 0.8 at golden hour and dusk, 0.5 for moonlight.
   - Implement the rim as an alpha-gradient offset in the shader, or as an authored inner stroke in the SVG.
4. **Shadows.** A blurred ellipse in the `shadow` tint at α 0.18–0.35, with blur 6–12 dp. Fake AO: darken the bottom 10–20 % of each object by 15–25 % toward the shadow tint.
5. **Local lights** (from dusk on). Lantern pools: additive radial gradients in `accent`, α 0.25–0.40, radius 60–120 dp, "breathing" ±5 % at 0.3–0.5 Hz. **Never more than 3 flashes in any 1 s** (WCAG 2.3.1 [26]); keep any brightness modulation below 3 Hz.
6. **Light shafts** (day and golden hour): 3–5 additive gradient quads at α 0.05–0.12, swaying ±2° over 8–12 s. Dust motes are visible only inside the shafts.
7. **Fuzzy edge signature.** On creatures, perturb the alpha/SDF edge with noise at 0.6–1.2 dp amplitude. When the sun is behind the creature (golden hour), add a backlit peach-fuzz rim in `key` colour. **This is the "fuzzy" brand look** [J].

### 2.4 Texture, grain and dithering
- **Banding is real on 8-bit output** [V, computed].
  - Day sky `#6FB6EC → #D6EEF6` across about 1100 px changes R/G/B by 103/56/10 code values, so each channel steps every 11/20/**110** px. Red and green step finely, but the blue channel is the one that bands: 110-px-wide steps of faint hue shift.
  - Night sky `#111938 → #3D4F8C` (Δ 44/54/84) steps every 25/20/13 px.
  - Under the `canvas_items` stretch mode, shaders run at native resolution, so the same code-value steps spread over more pixels on a taller screen (e.g. ≈ 290 px blue steps across 2900 px). The steps stay the same fraction of the screen.
- **Dither** with TPDF (the sum of two uniform hashes minus 1, scaled to ±1 LSB, `/255`). TPDF removes banding *and* noise modulation (Lipshitz, Wannamaker & Vanderkooy 1992 [17]). The IGN at ±0.5 LSB in 01 R6 is also acceptable [18].
- **Grain.** Use luminance-only noise, sampled in UV space so it **moves with the object**. That gives a paper/felt texture and avoids the "shower-door" effect.
  - Amplitude: `0.02 × 4L(1−L)`, i.e. strongest in the midtones, as with film (peak ±2 %, σ ≈ 1.2 % at L = 0.5).
  - Cell size: 1 dp. `uv_px` must therefore be in **dp** units (`UV * size_dp`), because `floor()` makes 1-unit cells.
  - Bake it into existing large-area shaders (sky, ground, glass) instead of adding a full-screen pass. Fill rate is the mobile bottleneck (01 §5).
- The snippet below uses Hoskins's sine-free hash [32] [J]:
  ```glsl
  float h12(vec2 p){ vec3 q=fract(vec3(p.xyx)*.1031); q+=dot(q,q.yzx+33.33); return fract((q.x+q.y)*q.z); }
  vec3 finish(vec3 c, vec2 uv_px, vec2 frag){
      float L = dot(c, vec3(.2126,.7152,.0722));
      c += (h12(floor(uv_px)) - .5) * 2. * u_grain * 4. * L * (1. - L);   // u_grain = 0.02
      return c + (h12(frag) + h12(frag + 17.17) - 1.) / 255.;              // TPDF ±1 LSB
  }
  ```

### 2.5 Depth layers

| # | Layer | `Parallax2D.scroll_scale` | Haze toward `sky_horizon` | Detail / edges | Notes |
|---|---|---|---|---|---|
| L0 | Sky | 0 | — | gradient only | opaque, `blend_disabled` |
| L1 | Sun/moon, stars | 0.02 | — | halos | stars twinkle 0.2–0.5 Hz with random phases |
| L2 | Far (mountains, clouds) | 0.10 | **55–70 %** | pre-blurred 1–2 dp | clouds drift 2–6 dp/s |
| L3 | Mid (hills, tree line) | 0.30 | **25–40 %** | soft | fractal silhouettes |
| L4 | Play diorama | 1.00 | 0–8 % | crisp; outlines on interactive objects only | the only layer that carries focal detail |
| L5 | Foreground frame (leaves, grass) | 1.25–1.5 | darkened −15 L* | blurred 2–4 dp | covers ≤ 12 % of the screen and never the interactive zone |

- **Parallax sources:**
  - slow camera drift (§3.6);
  - optional device tilt (`Input.get_gravity()` [V], Android and iOS only; on Android it needs `input_devices/sensors/enable_gravity=true`, default `false` [V] Input.xml:106-111, `core/input/input.cpp:2371`), max 2 dp on L2 and 8 dp on L5;
  - both turn off with Reduce Motion.

### 2.6 Particles (calm-reading values) [J, anchored to physics]

Scale assumption: a 1 m creature is about 60 dp tall.

| Effect | When | Count | Size | Speed | Motion character | Basis |
|---|---|---|---|---|---|---|
| Dust motes | day, inside light shafts | 15–40 | 1–2.5 dp, α 0.15–0.4 | 2–8 dp/s | shader sine wander (not turbulence, see below); no gravity | [J] |
| Pollen / dandelion seeds | day, golden hour | 5–12 | 3–6 dp | 8–20 dp/s along the wind | slow vertical bob at 0.2 Hz | [J] |
| Petals / leaves | spring, autumn | 8–20 | 6–12 dp | fall at 20–40 dp/s | flutter: sway 10–20 dp at 0.3–0.6 Hz, roll 30–90°/s (falling plates flutter or tumble [29]) | [H] |
| Fireflies | dusk, night | 8–20 | 2–3 dp core plus 12–20 dp halo | 5–15 dp/s wander | glow 0.3–0.6 s with random phases. *P. pyralis* repeats about every 5–7 s [30]; we widen this to 3–7 s for variety [J] | [H] / [J] |
| Snow | winter | 60–130 in total, as 3 depth bands across ≤ 2 systems (scale and speed randomised per particle), plus 5–10 blurred 8–12 dp foreground flakes | 2 / 3.5 / 5 dp | 30 / 45 / 60 dp/s (aggregate snowflakes fall at about 0.5–1.5 m/s [27]) | sway 6–14 dp at 0.2–0.5 Hz | [H] |
| Rain (gentle) | weather | 80–140 streaks (fits the 150 cap) | 1 × 10–18 dp, α 0.25–0.4, tilted 5–10° | 120–240 dp/s (= 2–4 m/s: light-rain drops of 0.5–1 mm. True drizzle, < 0.5 mm, falls below about 2 m/s [28]) | 4–8 splash ripples per second on the ground | [H] |

- **Godot implementation:**
  - `GPUParticles2D` with `ParticleProcessMaterial`. **Do not rely on `turbulence_enabled`.** The engine docs say it "has a high performance cost on the GPU… consider disabling it when targeting mobile/web platforms" [V] ParticleProcessMaterial.xml:399-401. Get wander from a custom particle shader (sum of 2–3 sines per particle, seeded by `INDEX`) [J], or allow turbulence on at most one small system after profiling.
  - Fade density with `amount_ratio`. Changing `amount` restarts the system (01) [V]. Lowering `amount_ratio` saves **no** GPU time, because the full `amount` is still processed (GPUParticles2D.xml:64-70), so size `amount` for the real peak.
  - Use `preprocess` so no system starts empty. Keep it at about 1 lifetime: the cost is `fixed_fps` (or 30) shader passes per preprocessed second, all in one frame (GPUParticles2D.xml:109-111) [V].
  - Never let a particle **pop in**. A sudden onset of motion captures attention (Abrams & Christ 2003 [35]) [H]. Fade in over ≥ 300 ms.

### 2.7 Glass UI recipe
- **Real glass (one surface at a time):**
  - `hint_screen_texture, filter_linear_mipmap` sampled with `textureLod(…, 3.0–4.0)`. This works in Compatibility: the GLES3 canvas renderer builds the back-buffer mip chain with a Gaussian blur, down to about 32 px [V] `drivers/gles3/rasterizer_canvas_gles3.cpp:433-541`, `drivers/gles3/storage/texture_storage.cpp:2770-2777, 3719-3741`. The snippet in §2.4 compiled without errors under `opengl3` on 4.7.2;
  - backdrop saturation ×1.15;
  - `mix(backdrop, surface, 0.60–0.72)`;
  - top-left inner rim of 1 dp, white α 0.6, fading to 0.1 at the bottom-right;
  - bottom inner shadow of 2 dp at α 0.06;
  - outer shadow of 16–24 dp blur, y +6–8 dp, α 0.10–0.16 in `shadow` tint;
  - dither.
- **Faux glass** (HUD chips, cards): no screen read. 80–88 % surface fill, the same rim and the same shadow.
- **Reduce Transparency:** 100 % surface fill.
- Glass is the topmost layer only, never stacked [1].

---

## 3. Motion language

### 3.1 Principles (Disney → UI)
- Thomas & Johnston's 12 principles [14] were carried into UI by Chang & Ungar 1993 (UIST): slow-in/slow-out, anticipation, follow-through and arcs make change "easy to follow" [15] [H].
- Our rules:
  1. **Every spatial move eases.** No linear tweens except loops that run at constant speed.
  2. **Feedback within 100 ms, transitions 200–500 ms, nothing blocking beyond 1 s** (01 and 02 agree).
  3. **Overshoot only with momentum or reward** [8].
  4. **Everything is interruptible.** Retarget from the current value and velocity.
  5. **Continuous ambient motion, never abrupt onsets** [35].

### 3.2 Exact easing in Godot
For M3 curves, use `PropertyTweener.set_custom_interpolator(Callable)` [V] and keep the tweener `TRANS_LINEAR`. The docs note that the callable's input "is still subject to the tweener's own easing":
```gdscript
static func bezier(x1: float, y1: float, x2: float, y2: float) -> Callable:
    return func(x: float) -> float:
        var lo := 0.0; var hi := 1.0; var t := x
        for _i in 16:                                 # bisection on x(t); precision ≈1.5e-5
            t = (lo + hi) * 0.5
            var w := 1.0 - t
            if 3.0*w*w*t*x1 + 3.0*w*t*t*x2 + t*t*t < x: lo = t
            else: hi = t
        var u := 1.0 - t
        return 3.0*u*u*t*y1 + 3.0*u*t*t*y2 + t*t*t
# build once and cache: var EMPH_DECEL := bezier(0.05, 0.7, 0.1, 1.0)
# tween.tween_property(n, "position", p, 0.32).set_custom_interpolator(EMPH_DECEL)
```
For a `Control` pop, set `offset_transform_enabled = true` and tween `offset_transform_scale`. The default `offset_transform_pivot_ratio` is (0.5, 0.5). The offset is applied on top of the layout rect, so containers do not reflow. With `offset_transform_visual_only = true` (the default), input still hits the untransformed rect [V] Control.xml:1161-1196, `scene/gui/control.cpp:748-765`. The `bezier()` helper above runs as written on 4.7.2 (headless test: `bezier(0.05,0.7,0.1,1)(0.5)` = 0.950).

### 3.3 Squash & stretch, anticipation, follow-through
- **Area-preserving scale:** `Vector2(1/s, s)`.

| Action | Anticipation | Main | Follow-through |
|---|---|---|---|
| Button press | — | scale 0.95 in `micro` | release with spring `pop` → 1.0 |
| Tap a creature | — | squash s = 0.88 (12 %) in 80 ms | spring `jelly` back; ears on `follow`, lagging 40–80 ms |
| Creature hop | crouch s = 0.92 over 90–120 ms | stretch s = 1.10 during the rise; arc path | land at s = 0.88, `jelly` |
| Reward pop-in | scale to 0.9 over 60 ms | 0.6 → 1.0 on `pop` (9.5 % overshoot) | sparkles 4–6, 400 ms |
| Plant growth step | — | stretch y 1.0 → 1.08 → 1.0 with spring `move` | leaves on `follow` |

- **Amplitudes:**
  - UI: 4–6 %.
  - Creatures: 8–15 %.
  - Never above 20 %.
  - Squash ratios above about 1.2 read as "cartoon slapstick", not cozy [J].

### 3.4 Idle "breathing" and ambient life
- **Awake creature:** period **3.5–4.5 s**, i.e. 13–17 breaths/min, inside the adult resting range of 12–20 [33] [H].
  - Inhale:exhale ≈ 1:1.5. Physiological I:E at rest is about 1:2 [H].
  - Scale (0.99, 1.025), pivot at the feet. Randomise the period ±10 % and the phase per creature.
- **Asleep:** 5–6 s with a deeper amplitude of 3.5 %. This is inside 04 P9's 4–6 s and equals 10–12 breaths/min, the slow end of the normal resting range. It is **not** slow-paced or resonance breathing (about 6/min, 10 s), so we claim no calming entrainment (04 already corrected this point) [H].
- ```gdscript
  var t := create_tween().set_loops()
  t.tween_property(body, "scale", Vector2(0.99, 1.025), 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
  t.tween_property(body, "scale", Vector2.ONE, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
  ```
- **Blinks:** 120–160 ms each, at random intervals of 2.5–7 s, with a double blink 15 % of the time [J, stylised].
- **Plant sway:** use 01's vertex shader at 0.2–0.5 Hz with 4–8 dp amplitude at the tip. Wind gusts travel at 40–80 dp/s, every 6–15 s.
- **Keep ≥ 3 ambient layers** with φ-ratio periods, so no repeat is noticeable within 20 s (04 P5).

### 3.5 Micro-interactions on every touch
- **Touch-down:** at frame 0, `instant` tint (+6 L*) and `micro` press.
- **Release:** `pop`, a soft ring growing to 36 dp radius over 380 ms with α 0.35 → 0, 3–5 sparkles, and a 10–20 ms haptic tick (02 R8).
- **Long-press:** a radial fill starts at 150 ms (02).

### 3.6 Camera rules
- **No shake, ever.**
- Idle drift ≤ 4 dp/s on a sine path with a 30–60 s period.
- Zoom changes ≤ 5 % over ≥ 1.2 s, with `TRANS_SINE`+`EASE_IN_OUT`.
- Pans between rooms use `emphasized` (500 ms).
- Under Reduce Motion: no drift or tilt parallax, and cross-fades replace pans and zooms (WCAG 2.3.3 [26]).

---

## 4. Not looking like programmer art
- **Composition.**
  - Put the focal object (home or creature) on the lower-third band, at y ≈ 55–66 % of screen height. The top 15 % and bottom 20 % hold UI and the thumb zone (02).
  - One focal point per screen.
  - Leave 30–40 % of the frame low-detail (sky, ground) as a rest area.
- **Value first.**
  - Use 3–4 value groups. Area ratio ≈ 60 % light, 30 % mid, 10 % dark-or-accent [J].
  - **Squint test:** blur the screenshot by 2 % of its width and convert to greyscale. The focal object must be the highest local-contrast region.
- **Limited palette.** Every colour comes from §0.4 tokens through global shader uniforms. Never hard-code colours outside the palette in SVGs.
  - For environment props, use an **RGB tone-mask pipeline**: the SVG paints R = lit tone, G = shadow tone, B = detail tone. The shader composes `R·lit + G·shade + B·detail` from per-material, per-time-of-day tokens.
  - This gives hue-shifted shadows and re-lighting for every time of day without extra art. Because the composition is linear, anti-aliased edges stay smooth [J].
  - Import mask textures **lossless** (no VRAM/ETC2/ASTC compression, no sRGB→linear conversion), or block compression will bleed one channel into another [J].
- **Organic irregularity.** On repeated instances, vary:
  - scale ±8–15 %;
  - rotation ±3–6°;
  - hue ±4°;
  - L* ±3;
  - vertices jittered by 1–3 % of object size.

  Place them with Poisson-disk sampling (Bridson 2007 [31]) in odd-numbered clusters (3/5/7). Never on a grid, never uniform random.
- **Detail at 3 scales.**
  - Macro: silhouettes, readable at 64 px.
  - Meso: features of 8–24 dp, such as windows and leaf clusters.
  - Micro: 1–4 dp grain and speckles.
  - Detail density peaks at the focal point. Edges are crisp at the focus and lost further away.
- **Outline policy.** Colour lines on interactive objects only, so outline = "touchable" is an affordance. Black outlines flatten atmospheric depth [J].
- **Avoid:** pure `#000`/`#FFF` in art (exceptions: the identity `ambient #FFFFFF` multiply, and text on `primary`, where `surface_hi #FFFDF8` passes at 4.55:1 but `surface` fails); saturated sRGB primaries (C_OK > 0.2; every §0.4 token is ≤ 0.163 [V, computed]); perfect symmetry; uniform stroke widths across scales; untextured flats over 15 % of the screen.

---

## 5. Visual QA rubric (score 1–10 each; 100 total)

**Protocol.**
- Fixed capture set: 5 times of day × 2 screens (home, a sheet open), plus one 30 s idle video at 60 fps.
- Rendered on Xvfb at 1080×1920 with `--rendering-driver opengl3 --resolution 1080x1920`. **Not** with `--headless`, which selects the headless display driver and does no rendering (`main/main.cpp:626, 1505-1508`). Video: `--write-movie qa.avi --fixed-fps 60 --quit-after 1800` (Movie Maker; `main/main.cpp:629-632`) [V].
- 3 raters score independently. Use the **median**. A spread of more than 2 points triggers a review.

| # | Criterion | 4 = prototype | 7 = solid | 10 = feature-worthy | Objective check |
|---|---|---|---|---|---|
| 1 | Value structure & focal hierarchy | flat, competing focal points | clear focal, some noise | instant read at a squint | blurred greyscale: focal = top local contrast; L* p5–p95 ≥ 55 (day) |
| 2 | Palette harmony | ad-hoc colours | token palette, a few clashes | rich yet restrained; warm/cool split | k-means(8) colours within ΔE_OK ≤ 6 of a token; high-chroma area ≤ 10 % |
| 3 | Edge quality & AA | jaggies, fringes, blurry text | clean at 100 % | crisp at 200 % zoom, with intentional soft/lost edges | no stair-steps or halos at 200 %; text is MSDF or rasterised at the right oversampling |
| 4 | Depth & atmosphere | 1–2 planes | 4 planes with haze | 6 planes, convincing air | contrast to `sky_horizon` rises monotonically far → near |
| 5 | Lighting coherence | none, or contradictory | consistent direction | rims, tinted shadows, light pools that tell the time | shadow offsets agree with `g_sun_dir`; no neutral-grey shadows |
| 6 | Motion quality | linear, jerky, pops | eased; ≥ 3 ambient layers | springy, interruptible, alive yet calm | p95 frame time ≤ 16.7 ms; no linear spatial tweens; no onset without a fade; no *composite* scene repeat < 20 s (single ambient layers may loop in 3–12 s, per §0.2 and 04 P5) |
| 7 | Touch feedback | missing on some controls | every control responds | every touch delights (visual + haptic) | first visual change ≤ 100 ms (≤ 6 frames at 60 fps) on 100 % of taps |
| 8 | UI clarity & accessibility | low contrast, cramped | WCAG AA | effortless; glass legible over the worst background | text ≥ 4.5:1, icons ≥ 3:1, targets ≥ 48 dp, idle HUD ≤ 20 % of area; Reduce Motion/Transparency work |
| 9 | Consistency | mixed styles | one style, small drift | every asset looks from one hand | radii from tokens; one light direction; grain everywhere; same line rule |
| 10 | Polish & "Today tab" test | placeholders | complete | a random 1:1 crop works as key art | blind A/B: rater picks it as a "store screenshot" against a 2026 store page from memory |

**Thresholds** [J]:
- **< 60:** prototype.
- **70–79:** soft-launch quality.
- **Ship-worthy 2026–27:** **≥ 80**, with no criterion below 7 and #1, #6 and #8 at ≥ 8.
- **Feature-worthy:** ≥ 88 with every criterion ≥ 8.

---

## 6. Risks / to validate in engine
- The cost of a glass screen read, plus mip blur, on low-end GLES3 devices. Fall back to faux glass if frame time is over 2 ms.
- Grain and dither are invisible on PNG captures that get downscaled. Score them at 1:1.
- The tone-mask SVG pipeline needs a proof of concept: ThorVG blending of pure-channel fills at edges.
- CVD and contrast numbers are sRGB. **FLAGGED, needs a device check.**
  - In 4.7.2 the iOS Metal path tags its layer `kCGColorSpaceSRGB` (`drivers/metal/rendering_context_driver_metal.cpp:168`) [V].
  - The Compatibility (GLES) path we use creates a plain `kEAGLColorFormatRGBA8` layer with no colour space set (`platform/ios/display_layer_ios.mm:91`). That iOS colour-matches it as sRGB is assumed, not verified.
  - Many Android phones ship a "vivid" display mode that stretches sRGB to the panel gamut, so expect more saturation than the numbers predict [J].

---

## References
1. Apple. *Adopting Liquid Glass.* developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass (read 2026-10-20) [V].
   1b. Apple. *Human Interface Guidelines: Materials.* developer.apple.com/design/human-interface-guidelines/materials (read 2026-10-20) [V].
2. Apple. *Apple Design Awards* (2026 winners). developer.apple.com/design/awards/ (read 2026-10-20) [V]. The newsroom date of 2026-06-02 was not re-verified.
3. AppleInsider, 2026-03-26, "Stop holding out hope Liquid Glass will be mandatory in iOS 27"; iGeeksBlog, "iOS 27 … customization slider"; macmyths, "WWDC 2026 Apple refines Liquid Glass". **Rumour-grade; not re-verified** [FLAGGED].
4. Budiu, R. (2025). *Liquid Glass Is Cracked, and Usability Suffers in iOS 26.* NN/g (via anderegg.ca, 2025-10-12) [H].
5. AOSP androidx, `compose/material3/…/tokens/{MotionTokens,StandardMotionTokens,ExpressiveMotionTokens}.kt`, `MotionScheme.kt`. Re-verified at github.com/androidx/androidx `androidx-main` commit 42a64764 (2026-10-20). The originally cited a2c62f41 could not be resolved from a shallow clone [V].
6. 9to5Google (2025-05-13), "Android 16 Material 3 Expressive redesign"; Chrome Unboxed, recovery of the research post (46 studies, 18k participants) [H].
7. Apple WWDC23 session 10158, *Animate with springs*; SwiftUI `Spring` docs (developer.apple.com/documentation/swiftui/spring) [V].
8. Apple WWDC18 session 803, *Designing Fluid Interfaces* [V].
9. Apple. *Getting featured on the App Store.* developer.apple.com/app-store/getting-featured/ [V].
10. Pantone Color Institute, Color of the Year 2026: PANTONE 11-4201 Cloud Dancer (2025-12-04). Hex #F0EEE9 per Vistaprint and W3Schools [H].
11. WGSN & Coloro, press release 2025-04-29: Colour of the Year 2027, Luminous Blue (125-28-38). **Not re-verified** [FLAGGED].
12. Apple. *2025 Apple Design Award winners.* developer.apple.com/design/awards/2025/ (read 2026-10-20) [V]; also 9to5Mac, 2025-06-03.
13. Google, *Google Play's best of 2025* (blog.google); PocketGamer.biz summary. **Not re-verified: host unreachable** [FLAGGED].
14. Thomas, F., & Johnston, O. (1981). *The Illusion of Life: Disney Animation.* Abbeville.
15. Chang, B.-W., & Ungar, D. (1993). Animation: From cartoons to the user interface. *UIST '93*, 45–55. doi:10.1145/168642.168647.
16. Ogata, K. (2010). *Modern Control Engineering* (5th ed.), §5-3 (second-order transient response).
17. Lipshitz, S. P., Wannamaker, R. A., & Vanderkooy, J. (1992). Quantization and dither: A theoretical survey. *J. Audio Eng. Soc.* 40(5), 355–375.
18. Jimenez, J. (2014). Next generation post processing in *Call of Duty: Advanced Warfare*. SIGGRAPH Advances in Real-Time Rendering.
19. Gjøl, M., & Svendsen, M. (2016). *The Rendering of INSIDE.* GDC.
20. O'Shea, R. P., Blackburn, S. G., & Ono, H. (1994). Contrast as a depth cue. *Vision Research* 34(12), 1595–1604. doi:10.1016/0042-6989(94)90116-3.
21. Gurney, J. (2010). *Color and Light: A Guide for the Realist Painter.* Andrews McMeel.
22. Thompson, W. B., Shirley, P., & Ferwerda, J. A. (2002). A spatial post-processing algorithm for images of night scenes. *J. Graphics Tools* 7(1), 1–12.
23. Machado, G. M., Oliveira, M. M., & Fernandes, L. A. F. (2009). A physiologically-based model for simulation of color vision deficiency. *IEEE TVCG* 15(6), 1291–1298. doi:10.1109/TVCG.2009.113.
24. Okabe, M., & Ito, K. (2008). *Color Universal Design.* jfly.uni-koeln.de/color/.
25. Ottosson, B. (2020). *A perceptual color space for image processing (Oklab).* bottosson.github.io/posts/oklab/.
26. W3C. *WCAG 2.2*: SC 1.4.1, 1.4.3, 1.4.11, 2.2.2, 2.3.1, 2.3.3.
27. Locatelli, J. D., & Hobbs, P. V. (1974). Fall speeds and masses of solid precipitation particles. *JGR* 79(15), 2185–2197. doi:10.1029/JC079i015p02185.
28. Gunn, R., & Kinzer, G. D. (1949). The terminal velocity of fall for water droplets in stagnant air. *J. Meteorology* 6(4), 243–248.
29. Field, S. B., Klaus, M., Moore, M. G., & Nori, F. (1997). Chaotic dynamics of falling disks. *Nature* 388, 252–254. doi:10.1038/40817.
30. Lloyd, J. E. (1966). Studies on the flash communication system in *Photinus* fireflies. *Misc. Publ. Mus. Zool. Univ. Michigan* 130. Summarised in Wikipedia, "Photinus pyralis" (flash 0.3–0.6 s; period about 5–7 s, temperature-dependent).
31. Bridson, R. (2007). Fast Poisson disk sampling in arbitrary dimensions. *SIGGRAPH Sketches.* doi:10.1145/1278780.1278807.
32. Hoskins, D. *Hash without Sine.* Shadertoy 4djSRW (MIT).
33. Cretikos, M. A., et al. (2008). Respiratory rate: the neglected vital sign. *Med. J. Aust.* 188(11), 657–659 (adult resting rate 12–20/min).
34. Godot 4.7.2-stable source: `scene/animation/easing_equations.h` (Back/Spring/Elastic); `doc/classes/{Tween,PropertyTweener,Gradient,GradientTexture2D,StyleBoxFlat,Parallax2D,Control,DisplayServer,GPUParticles2D,ParticleProcessMaterial,Input}.xml` [V].
35. Abrams, R. A., & Christ, S. E. (2003). Motion onset captures attention. *Psychological Science* 14(5), 427–432. doi:10.1111/1467-9280.01458.
36. W3C. *CSS Color Module Level 4*, "CSS gamut mapping" (#css-gamut-mapping): "For the OkLCh color space, one JND is … an OkLCh difference of 0.02" (source `css-color-4/Overview.bs:6516-6527`, w3c/csswg-drafts main, 2026-10-20) [V].
37. Nielsen, J. (1993). *Usability Engineering*, ch. 5 (response-time limits of 0.1 s, 1 s and 10 s). Academic Press.
38. Voss, R. F. (1988). Fractals in nature: from characterization to simulation. In Peitgen & Saupe (eds.), *The Science of Fractal Images*, 21–70. Springer. (For an fBm trace, D = E + 1 − H.)

Note: [19] and [24] are background reading and are not cited in the body.

Cross-references: 01-godot-4.7-engine.md (R5, R6, R7, §4–5), 02-mobile-ux-performance.md (R1, R8, R9), 04-cozy-idle-design-science.md (P5, P7, P8, P9; refs for Bar & Neta, Glocker, Valdez & Mehrabian, Kaplan).

---

## Verification log

Fact-check done 2026-10-20 against the 4.7.2-stable source (`/home/user/godotengine/godot`) and the 4.7.2 editor binary. Headless runs and `opengl3` runs on Xvfb used the scripts in `/tmp/claude-verify-art/`.

**Network limits on this check.**
- Reachable: developer.apple.com, and anonymous git clones of `androidx/androidx` and `w3c/csswg-drafts`.
- Unreachable: WebSearch (the session budget was exhausted), doi.org, w3.org, blog.google, Wikipedia and news sites.

**Verdicts.**
- **OK**: verified, with the evidence given.
- **OK\***: bibliographic details or claims match the checker's own knowledge, but could not be re-fetched. Re-check them when the network allows.
- **FIXED**: the text has been corrected.
- **FLAGGED**: unverifiable or doubtful, and marked as such in the text.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | `StyleBoxFlat.corner_detail` default 8 | OK | StyleBoxFlat.xml:126; runtime print = 8 |
| 2 | `Gradient.interpolation_color_space`, `GRADIENT_COLOR_SPACE_OKLAB`; `Gradient.sample()` | OK | Gradient.xml:55, 84, 112 |
| 3 | `GradientTexture2D.fill = FILL_RADIAL` | OK | GradientTexture2D.xml:13, 43 |
| 4 | Godot imports `.woff2` | OK | editor/import/resource_importer_dynamic_font.cpp:55 |
| 5 | `accessibility_should_reduce_animation/transparency` return −1 on iOS/Android ("macOS and Windows") | OK | DisplayServer.xml:115-127; servers/display/display_server.h:552-553 (base returns −1); only platform/windows and platform/macos override; runtime returned −1 on Linux |
| 6 | Built-in fit errors 0.13 / 0.155 / 0.046 / 0.002, each "best built-in" | OK | Recomputed from scene/animation/easing_equations.h. Also checked quad/quart/quint/circ/sine/expo: none beats the cited pick |
| 7 | Overshoot: Back 10.0 %, Spring 8.4 %, Elastic 37.3 % | OK | easing_equations.h:381-444; computed 10.00 / 8.42 / 37.31 % |
| 8 | `TRANS_*`/`EASE_*` names, `Tween.set_loops`, `PropertyTweener.set_delay` | OK | Tween.xml (constants, :252); PropertyTweener.xml:102 |
| 9 | `set_custom_interpolator` quote "still subject to the tweener's own easing" | OK | PropertyTweener.xml:65-69 |
| 10 | GDScript `bezier()` helper runs | OK | 4.7.2 headless run: (0.05,0.7,0.1,1) at 0.5 → 0.950 |
| 11 | `offset_transform_*` defaults; "visual-only, layout does not reflow" | FIXED (wording: `visual_only` is about input) | Control.xml:1161-1196; scene/gui/control.cpp:748-765 |
| 12 | canvas_item `render_mode blend_disabled` exists in Compatibility | OK | drivers/gles3/storage/material_storage.cpp:2685 (CanvasShaderData) |
| 13 | §2.4 grain/TPDF shader compiles (incl. `.1031`, `2.` literals) | OK | Compiled clean under `--rendering-driver opengl3`; a deliberately broken copy reported `SHADER ERROR`; tokenizer servers/rendering/shader_language.cpp:723-850 |
| 14 | Screen-texture mipmaps and `textureLod` in Compatibility 2D | OK (evidence added) | drivers/gles3/rasterizer_canvas_gles3.cpp:433-541; drivers/gles3/storage/texture_storage.cpp:2770-2777, 3719-3741 |
| 15 | Environment glow simplified in Compatibility | OK | Environment.xml:131, 139 |
| 16 | `Parallax2D.scroll_scale` | OK | Parallax2D.xml:43 |
| 17 | `Input.get_gravity()` for tilt | FIXED (needs `input_devices/sensors/enable_gravity=true` on Android; mobile only) | Input.xml:106-111; core/input/input.cpp:2371 |
| 18 | `amount` change restarts; use `amount_ratio` | OK, plus FIXED (lowering `amount_ratio` saves no GPU time) | GPUParticles2D.xml:64-70 |
| 19 | `preprocess` so no system starts empty | FIXED (cost warning added) | GPUParticles2D.xml:109-111 |
| 20 | Recommend `turbulence_enabled` on mobile | FIXED (docs advise against it on mobile/web) | ParticleProcessMaterial.xml:399-401 |
| 21 | ThorVG supports `feGaussianBlur` | OK | thirdparty/README.md:1086-1090 (ThorVG 1.0.3); thorvg/src/loaders/svg/tvgSvgLoader.cpp:2151; tvgSvgSceneBuilder.cpp:369; sw_engine/tvgSwPostEffect.cpp |
| 22 | Baloo 2 / Nunito variable 5.3.0, OFL, Vietnamese; Fredoka has none | OK | `npm view`; package metadata.json (subsets and axes) |
| 23 | One `.woff2` gives full Vietnamese | FIXED (subsets are split by unicode-range; use `Font.fallbacks` or merge) | package index.css unicode-range; Font.xml:367 |
| 24 | MSDF text option | OK | FontFile.xml:646 |
| 25 | QA "rendered headless on Xvfb" | FIXED (`--headless` disables rendering; Movie Maker flags added) | main/main.cpp:573, 626, 629-632, 1505-1508 |
| 26 | iPhone P3 shows our sRGB correctly, so the numbers hold | FLAGGED | drivers/metal/rendering_context_driver_metal.cpp:168 (Metal is tagged sRGB); platform/ios/display_layer_ios.mm:91 (GLES layer has no colour space) |
| 27 | M3 durations 50–1000 ms; beziers (0.2,0,0,1), (0.05,0.7,0.1,1), (0.3,0,0.8,0.15) | OK | androidx `MotionTokens.kt` @42a64764 |
| 28 | M3 springs: Standard 1400/700/300 @0.9; Expressive 800/0.6, 380/0.8, 200/0.8; effects ζ 1.0 | OK | androidx `StandardMotionTokens.kt`, `ExpressiveMotionTokens.kt` @42a64764 |
| 29 | androidx commit a2c62f41 | FIXED (replaced with the commit actually verified) | shallow clone of androidx-main |
| 30 | Spring table: k, c, overshoot, 2 % settle, (duration, bounce) for all 5 tokens | OK | Recomputed: e.g. pop k = 404.3, c = 24.1, OS 9.5 %, 332 ms |
| 31 | `pop` "close to M3 Expressive fast spatial" | FIXED (same ζ, half the stiffness) | ExpressiveMotionTokens.kt (800 / 0.6) |
| 32 | SwiftUI duration/bounce ↔ stiffness/damping; example → 17.6 | OK | SwiftUI `Spring` docs (157.9, 17.6; reverse example (0.63, 0.5)); WWDC23 10158 page |
| 33 | WWDC18 803: start at 100 % damping; 100 % for tap, 80 % for swipe-dismiss | OK | developer.apple.com/videos/play/wwdc2018/803 transcript (Music app example) |
| 34 | easeInOutSine ≈ (0.37,0,0.63,1); φ periods 3.0 / 4.85 / 7.85 / 12.7 s | OK | Computed (max error 0.002; 3·φⁿ) |
| 35 | 9 UI contrast ratios (12.4, 5.8, 4.63, 3.99, 6.96, 1.78, 5.99, 5.16, 9.55) | OK | Recomputed (WCAG 2.x relative luminance) |
| 36 | Day ladder L* 82/72/60/46, CR 1.34→4.24; night 1.36→2.29; dawn and golden monotonic | OK | Recomputed (dawn 1.24→4.45, golden 1.38→5.44) |
| 37 | CVD: min ΔE_OK ≥ 10 except primary–leaf tritan 8.9; accent 3.5 → 16.9 | OK (convention added: linear RGB; gamma-space gives 7.0) | Machado 2009 matrices, OKLab, recomputed |
| 38 | Grass multiply → `#2E4F5B` / `#7DA86E`; night min L* ≥ 6 | OK | Computed (6.2) |
| 39 | All tokens below C_OK 0.2 | OK | Computed max 0.163 (`#4A6FD6`) |
| 40 | ΔE_OK JND ≈ 2 attributed to Ottosson [25] | FIXED (source is CSS Color 4) | csswg-drafts css-color-4/Overview.bs:6516-6527 |
| 41 | Day sky "110 px bands" | FIXED (per-channel 11/20/110 px; only blue bands) | Computed from hex deltas 103/56/10 |
| 42 | Grain "σ ≈ 1.5 %, peak ±3 %" vs the snippet | FIXED (peak ±2 %, σ ≈ 1.2 %; dp-unit note) | Snippet arithmetic |
| 43 | Tritanopia "about 0.01 %" | FLAGGED (softened to ≤ 0.01 %, not re-verified) | — |
| 44 | "Avoid #FFF" vs white text on primary | FIXED (`surface_hi` 4.55:1 passes; `surface` 3.99:1 fails) | Computed |
| 45 | Value-noise gain 0.5 gives D 1.3–1.5 | FIXED (gain 0.62–0.71; D = 2 − H) | Voss 1988 [38]; arithmetic |
| 46 | `r-xs 6` dp, concentric min 4 | FIXED (8 dp, per 04 P7) | 04-cozy-idle-design-science.md:28 |
| 47 | Apple Liquid Glass quotes (functional layer, overuse, layering, rounder, concentric, sheet radius, icon layers) | OK | Apple doc JSON (read 2026-10-20) |
| 48 | HIG: 35 % dimming under clear glass | OK (added) | HIG Materials JSON |
| 49 | Featuring criteria incl. "Art and animation", "Technical performance" | OK | developer.apple.com/app-store/getting-featured/ |
| 50 | ADA 2025 game winners | FIXED (categories completed; DREDGE = Interaction) | developer.apple.com/design/awards/2025/ |
| 51 | ADA 2026 game winners; "none wins on raw fidelity" | FIXED (added *Consume Me*, *Cyberpunk 2077* Visuals & Graphics; claim corrected) | developer.apple.com/design/awards/ |
| 52 | Google Play Best of 2025 winners | FLAGGED | blog.google unreachable |
| 53 | iOS 27 opacity slider | FLAGGED | Only rumour sources; not in Apple docs |
| 54 | WGSN×Coloro 2027 "Luminous Blue" 125-28-38 | FLAGGED | No source reachable |
| 55 | Pantone 2026 Cloud Dancer 11-4201, `#F0EEE9`; iOS 26.1 Clear/Tinted; NN/g Budiu article; Google "46 studies / 18,000" | OK\* | Checker's knowledge; not re-fetched |
| 56 | Bibliographic data for [14]–[18], [20]–[23], [27]–[33], [35] (authors, venues, pages, DOIs) | OK\* | Checker's knowledge; doi.org unreachable. Hoskins `hash12` matches the snippet exactly |
| 57 | Rain "drizzle 2–4 m/s" | FIXED (2–4 m/s = 0.5–1 mm drops; drizzle < about 2 m/s) | Gunn & Kinzer 1949 [28] terminal-velocity table |
| 58 | Firefly period 2–7 s "from *Photinus* data" (the ref says 5–7 s) | FIXED (5–7 s data; widening to 3–7 s is [J]) | [30] as cited |
| 59 | Snow 0.5–1.5 m/s | OK\* | Locatelli & Hobbs 1974 [27] (aggregates) |
| 60 | Breathing 13–17/min inside 12–20 | OK | Arithmetic; [33] |
| 61 | Asleep 5–6 s "leans toward slow-paced breathing" | FIXED (10–12/min is normal pace; consistent with 04's own fix) | 04-cozy-idle-design-science.md:30, 425 |
| 62 | Baby-schema ratios attributed to Bar & Neta / Glocker | FIXED (ratios are [J]) | 04:113-114 (Glocker manipulated features, not ratios) |
| 63 | Particle cap 3 systems / 150 vs snow (3 bands, ≤ 160) and rain (≤ 200) | FIXED (rows resized to fit the cap) | Internal consistency |
| 64 | Rubric "no loop < 20 s" vs 3–12 s ambient loops | FIXED (composite repeat) | §0.2; 04 P5 |
| 65 | "No flicker above 3 Hz (WCAG 2.3.1)" | FIXED (≤ 3 flashes per 1 s) | WCAG 2.3.1 wording |
| 66 | canvas_items stretch "bands scale up" | FIXED (clarified: same screen fraction, more px) | Reasoning |

**Totals:** 66 rows covering 90+ individual claims. 33 OK, 3 OK\*, 25 FIXED, 5 FLAGGED.
