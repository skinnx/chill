# 00 — Research Synthesis & Final Decisions

*Lead Researcher · 2026-10-20 · Godot `4.7.2-stable` (ed1daf0) · inputs: reports 01–06 (all fact-checked) and `docs/TEAM.md`*

**Tags.** **[V]** verified (engine source path, measured run, or official doc, as cited in the source report or re-checked here) · **[H]** well-supported heuristic · **[J]** Lead judgement. Section refs such as "02 §1.2" point into the reports. New checks made for this synthesis are marked **[V-00]**.

**Status.** Binding for design and implementation. A later ADR may change a decision, but only with new evidence.

---

## 1. Conflicts resolved

| # | Topic | Positions | Resolution | Why |
|---|---|---|---|---|
| C1 | Base resolution | 01: 720×1280 · 02/05: 1080×1920 | **1080×1920** | `canvas_items` renders at native resolution either way, so fill cost is the same. The base only sets units and SVG raster scale. 1080 equals most phones 1:1 and makes `svg/scale=1.0` correct without node-scale tricks [J] |
| C2 | dp unit | 02: 2.625 px/dp (412-dp reference) · 05: 3 px/dp | **1 design dp = 3 px**. 02's px values become floors | 3 px is ≥ 1 real dp on every phone ≥ 360 dp wide, so sizes err large [J, arithmetic] |
| C3 | Android haptics | 01 R11, 03: `vibrate_handheld` + VIBRATE · 02 R7, 06: `performHapticFeedback` | **`performHapticFeedback` via `JavaClassWrapper`; `permissions/vibrate=false`; no buzz fallback** | Godot's path is `createOneShot`, which Android says to avoid for touch. "Choose no haptics" over buzzy (02 §2.3, 06 §5.1) |
| C4 | Shader time | 01: `global uniform g_time`, 600 s wrap · 02: built-in `TIME`, periods dividing 3600 | **`g_time`, wrapped at 600 s** | Lets Reduce Motion slow or freeze the world and keeps QA deterministic. Both schemes are seamless [J] |
| C5 | Ambient period ratios | 04 P9: "irrational (φ) ratios" · 01: frequencies k/600 Hz | **k = 200 / 124 / 76 / 47 → 3.00 / 4.84 / 7.89 / 12.77 s** | Neighbour ratios are 1.61–1.63 (≈ φ). gcd = 1, so the composite repeats only every 600 s, which meets P5. Truly irrational ratios are impossible under any wrap [V-00, arithmetic] |
| C6 | Dither | 01: IGN ±0.5 LSB · 05: TPDF ±1 LSB | **TPDF ±1 LSB** in every gradient, halo, fog and glass shader | Removes banding *and* noise modulation (Lipshitz 1992, 05 §2.4) |
| C7 | Glass | 05: live screen-texture glass · 02: snapshot only; 0 screen reads per frame on low tier | **Live `hint_screen_texture` on exactly one surface, only while a sheet is open, bounded by `BackBufferCopy` `COPY_MODE_RECT`. Faux glass otherwise and on low tier** | Idle frames (most play time) do 0 reads, so 02's budget holds. The governor drops to faux glass if the sheet costs more than 2 ms (05 §6) |
| C8 | Shader warm-up | 02 §4.4.6: "off-screen" · 01 R13: in viewport | **Draw once inside the viewport, behind the opaque splash, with combined `modulate.a ≥ 0.01`** | Off-screen items and items with α < 0.007 are culled and never compile (`renderer_canvas_cull.cpp:329`, 01) |
| C9 | QA driver | 03/05: `opengl3` · 01: `opengl3_es` | **`opengl3_es`** (GLES 3.2 on llvmpipe) | Same code path as phones and closest to WebGL2. Day-1 task: re-run 03's determinism test on it. If it fails, fall back to `opengl3` |
| C10 | Capture size | 03/05: `--resolution` · 01: movie size comes from the override | **Both.** Stills: `capture.gd` + `--resolution` · videos: `--write-movie` + `.movie` overrides | `--resolution` sets `force_res`, which skips the window override (`main/main.cpp:1461, 2685`). The movie writer reads the override (`:4841-4853`) [V-00] |
| C11 | SVG import | 01: `svg/scale=2` + node scale 0.5 · 03: DPITexture for crisp art | **`texture` importer at `svg/scale=1.0` with mipmaps for props. DPITexture (experimental) for UI icons only. Creatures are SDF shaders, not SVG rasters** | Keeps the experimental class off the critical path. Creatures stay crisp under squash at any scale |
| C12 | Font source | 03: google/fonts git clone · 05: fontsource subsets + fallbacks · TEAM.md: "OFL from npm" | **npm `@expo-google-fonts/nunito@0.4.2` and `@expo-google-fonts/baloo-2@0.4.2`** (full static TTFs, OFL) | [V-00]: 0 of 147 Vietnamese letters missing, GPOS present. Subset WOFF2 files are 21.9–27.9 KB. Avoids splitting kerning across files and meets the charter |
| C13 | Font weights | 03: Nunito 400/600/800 · 05: 500–800 | **Nunito 500/700/800, Baloo 2 700** | 500 keeps strokes sturdy below 16 dp (03 Quicksand note, 05) [J] |
| C14 | Offline cap | 01/02: 12 h · 04: 7 d at 100 % | **Clamp delta to [0, 7 d]; yield saturates at the 24-slot basket (≈ 12 h); after that, photos** | Both are satisfied: abundance is bounded, and absence is never wasted |
| C15 | Bus gains / limiter | 03: Music −6, Amb −9 · 06: −3 / −6, HardLimiter −1.5 dB | **06** | Measured mixes and a verified limiter rationale (06 §0.2, gotcha 3) |
| C16 | SFX pitch variation | 03: `random_pitch_semitones=1.0` · 06: ≤ 0.1 + pentatonic snap | **06** | Randomizer pitch is log-uniform and ignores the scale (`audio_stream.cpp:798-801`) |
| C17 | Live reverb | 02: none · 06: one SFX reverb | **One SFX reverb (wet 0.15); beds baked** | ≈ 30 MAC/sample, and buses sleep at −60 dB (06 §2.5) |
| C18 | Tempo | 06: 66 BPM · 03: BPM with an integer number of samples per beat | **70 BPM** | 44100·60/70 = 37 800 = 168 × 225, so 8 bars = 1 209 600 samples, exactly block-aligned for 06's `mod_filter`. 66 BPM gives 40 090.9 samples/beat [V-00] |
| C19 | Loudness tolerance | 03: ±2 LU · 06: ±1 LU | **Target ±1 LU; CI fails beyond ±2 LU** | [J] |
| C20 | HDR-2D, particle SDF collision | Docs say unsupported in Compatibility; source partly disagrees (01, 02) | **Use neither** | Unverified on mobile GLES (02 §7.5) |
| C21 | Idle frame rate | 01: 30 fps after 8 s with no input · 02: 30 fps only in Ambient mode | **30 fps after 8 s with no input and no UI tween, and always in Ambient mode** (refresh divisor) | Most play time is watching. If device p95 frame delta exceeds 40 ms, revert to 60 fps with lighter content (02 §7.1) |
| C22 | Android ABI | 03: add armeabi-v7a optionally | **arm64-v8a only in v1** | Play requires 64-bit. The Web demo covers reach [J] |

---

## 2. Final decisions

| # | Area | Decision | Source |
|---|---|---|---|
| D1 | Renderer | `gl_compatibility` on Android, iOS and Web (`rendering_method.mobile="gl_compatibility"`). Shaders stay Mobile-portable, so `mobile` is a one-line A/B. | 01 §1.3; 02 R9 |
| D2 | 2D/3D | Layered 2D "Felted Diorama": 6 `Parallax2D` layers (scroll 0 / 0.02 / 0.1 / 0.3 / 1 / 1.3). No 3D, SubViewports or Light2D; lighting is faked in shaders from globals. | 01 §2; 05 §2.3–2.5 |
| D3 | Resolution | 1080×1920, `canvas_items` + `expand`, portrait. 1 dp = 3 px. Zones per 02 §1.2. Margins from `get_display_safe_area()` with a 24 dp floor. | C1, C2 |
| D4 | Settings | The §3 block: 60 fps (30 when idle), physics 30 Hz, `keep_screen_on=false`, `quit_on_go_back=false`, `drag_threshold=24`, Linear Mipmap, `import_etc2_astc=true`, `.movie` overrides. | 01 §6; 02 §4 |
| D5 | Addons | Only **GUT `v9.7.1` @ `aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605`** (vendored, dev-only, excluded from exports) and **`gdtoolkit==4.5.0`** (CI). Everything else is rejected, including any GDExtension. | 03 §0, §2 |
| D6 | Fonts | Nunito 500/700/800 and Baloo 2 700 from npm `@expo-google-fonts/{nunito,baloo-2}@0.4.2`, subset into one Latin+Vietnamese WOFF2 per weight. Hinting None, no system fallback, MSDF for tweened numerals. | C12, C13; 03 §3 |
| D7 | Art | Hand-written SVG (round joins, no `<text>`, only `feGaussianBlur`), `texture` importer at `svg/scale=1.0` with mipmaps. Props are lossless RGB tone masks recoloured per time of day. Silhouettes are fBm `Polygon2D` (D ≈ 1.3–1.5); the sky is a shader. **Creatures are SDF quads** (one material, `instance uniform`s) with a fur rim. DPITexture is for icons only. | C11; 05 §2, §4 |
| D8 | Shaders | Shared grain + TPDF dither include. `g_time` wraps at 600 s, and loops run at k/600 Hz. Five OKLab palettes are sampled by `g_day`. Glass per C7. ≤ 3 full-screen alpha layers. | C4–C7; 05 §2 |
| D9 | Particles & motion | ≤ 3 GPUParticles2D systems, ≤ 150 particles; no turbulence, trails or sub-emitters; fade-in ≥ 300 ms; CPU fallback on Adreno 3xx. Motion and spring tokens from 05 §0.2–0.3. | 01 §3; 05 §2.6, §3 |
| D10 | Audio | Offline numpy/scipy synthesis at 44.1 kHz. OGG q4 beds and pads; QOA SFX. −18 LUFS-I, TP ≤ −1 dBTP. Buses per 06 §0.2. F Lydian at **70 BPM**: `AudioStreamInteractive` pads plus `AudioStreamPolyphonic` Eno voices. | C15–C19; 06 §0 |
| D11 | Haptics | Off / **Subtle (default)** / Full, ≥ 60 ms apart. Android: `performHapticFeedback`. iOS: `vibrate_handheld` (12, 0.30) / (12, 0.42) / (24, 0.60). | C3; 06 §5 |
| D12 | Save | JSON (`from_native`) with a `schema` field. Write tmp, rename, keep a `.bak`. Save on `FOCUS_OUT`, on `PAUSED` and every 30 s. Offline per C14. | 01 §7 |
| D13 | QA | GUT headless; `--check-only` gate. `opengl3_es` stills and video under Xvfb, seeded, at 30 fps. Goldens 540×1200 / 540×960 / 720×960 (fuzz 2 %, fail > 0.1 %). 3-rater rubric at 1080×2400: ship at ≥ 80 with every criterion ≥ 7. | C9, C10; 03 §6; 05 §5 |
| D14 | CI | GitHub Actions per 03 §7: SHA512-verified 4.7.2, then lint → tests + snapshots → debug APK (arm64) + Web. AAB and iOS deferred. | 03 §7 |

---

## 3. Reference configuration

```ini
config_version=5
[application]
config/name="Mossling Meadow"
config/features=PackedStringArray("4.7", "GL Compatibility")
config/icon="res://icon.svg"                 ; else APK export logs an error (03 §7)
config/quit_on_go_back=false                 ; handle NOTIFICATION_WM_GO_BACK_REQUEST
run/main_scene="res://scenes/boot.tscn"
run/max_fps=60
boot_splash/bg_color=Color(0.941, 0.933, 0.914, 1)   ; surface #F0EEE9
[debug]
gdscript/warnings/untyped_declaration=1
gdscript/warnings/unsafe_call_argument=1
gdscript/warnings/unsafe_method_access=1
gdscript/warnings/unsafe_property_access=1
[display]
window/size/viewport_width=1080
window/size/viewport_height=1920
window/size/window_width_override=540        ; desktop preview only
window/size/window_height_override=960
window/size/window_width_override.movie=1080 ; Movie Maker size (main.cpp:4841-4853)
window/size/window_height_override.movie=2400
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/handheld/orientation=1
window/energy_saving/keep_screen_on=false    ; engine default is true
window/ios/suppress_ui_gesture=false
[gui]
common/drag_threshold=24
[physics]
common/physics_ticks_per_second=30
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/canvas_textures/default_texture_filter=2
textures/vram_compression/import_etc2_astc=true   ; Android/iOS/Web export refuse without it
environment/defaults/default_clear_color=Color(0.941, 0.933, 0.914, 1)
[shader_globals]
g_time={"type":"float","value":0.0}
g_day={"type":"float","value":0.4}
g_wind={"type":"float","value":0.5}
g_motion={"type":"float","value":1.0}        ; 0.3 under Reduce Motion
g_sun_dir={"type":"vec2","value":Vector2(0.6, -0.8)}
g_sky_top={"type":"color","value":Color(0.435, 0.714, 0.925, 1)}
g_sky_mid={"type":"color","value":Color(0.620, 0.824, 0.949, 1)}
g_sky_horizon={"type":"color","value":Color(0.839, 0.933, 0.965, 1)}
g_ambient={"type":"color","value":Color(1, 1, 1, 1)}
g_key={"type":"color","value":Color(1.000, 0.945, 0.761, 1)}
g_shadow={"type":"color","value":Color(0.231, 0.424, 0.549, 1)}
```

The engine defaults `low_processor_mode=false`, `physics_interpolation=false`, `snap_2d_transforms_to_pixel=false`, `snap_controls_to_pixels=true`, `audio/general/ios/session_category=0` and `emulate_mouse_from_touch=true` are all **kept** (01 §6, 02, 06). `vec2` and `color` are valid global types (`drivers/gles3/storage/material_storage.cpp:2023-2058`), and `Color(...)` in config files takes exactly 4 floats, so hex strings are not allowed (`core/variant/variant_parser.cpp:908-920`) [V-00].

**Export presets.**
- Android: `gradle_build/use_gradle_build=false`, `architectures/arm64-v8a=true`, `screen/immersive_mode=true`, `screen/edge_to_edge=false`, `permissions/vibrate=false`, `package/app_category` = Game (default), `splash_screen/background_color=#F0EEE9`.
- Web: `variant/thread_support=false`, `vram_texture_compression/for_mobile=true`, `html/canvas_resize_policy=2`.
- Both: `include_filter=""` and the exclude filter from D5. Commit an empty `build/.gdignore` and `qa/.gdignore` (03 §7).

**Type scale (1 dp = 3 px).** Caption 36 px · Label 42 · Body 48 · HUD numerals 66 · Title 84. Vietnamese lines get +12 % line spacing.

**Budgets (low tier: Mali-G52 / Adreno 610).** ≤ 100 draw calls, overdraw ≤ 2.5×, ≤ 150 particles, ≤ 96 MB texture memory, ≤ 300 MB PSS. Idle frames do 0 screen reads. Cold start ≤ 3 s. After warm-up, no frame exceeds 2× the target interval (02 §4.3). `PIPELINE_COMPILATIONS_*` always reads 0 on GLES3, so detect hitches from frame time instead.

---

## 4. Design Principles checklist

Every row needs an automated or audited pass before any build is called "ship" (TEAM.md gate 4).

| # | Principle | Pass test | Source |
|---|---|---|---|
| E1 | No fail state, decay or negatives | Headless sim of 30 days away: every entity and currency ≥ its saved value; no decay branch in the code | 04 P1 |
| E2 | Timers only announce good news | Audit of timer labels; none ends in a loss | 04 P2 |
| E3 | Return without guilt | No "neglect" assets; screenshot diff after a 30-day sim shows ≥ the saved state | 04 P3 |
| E4 | Player-paced | A scripted 30 s session produces visible progress on the next launch | 04 P4 |
| E5 | Abundance | Economy sim over 10 k random schedules: 0 sessions with nothing affordable | 04 P10 |
| E6 | Small numbers | No displayed value above 99 999; one spendable currency plus non-decaying affection | 04 P11 |
| E7 | Relatedness, not competition | Named creatures that remember favourite spots; no leaderboards; no guilt copy | 04 P13 |
| E8 | No streaks or FOMO | No consecutive-day counters; seasonal content recurs; urgency words banned | 04 P14 |
| E9 | Ethical v1 | No loot boxes, premium currency, pay-to-skip, ads or notifications. No accounts, no network | 04 P15; 02 R15 |
| I1 | Instant, synced feedback | Visual change on touch-down within ≤ 100 ms (≤ 6 frames) on 100 % of taps; sound and haptic in the same frame | 04 P12; 02 §2.2 |
| I2 | Thumb-safe targets | Hit areas ≥ 60 dp (play), ≥ 72 dp (top), ≥ 76 dp (dock), gaps ≥ 8 dp. No required targets in Z0, Z1 or Z5. No drag start within 24 dp of side edges | 02 §1.2 |
| I3 | Simple gestures | Tap, long-press at 450 ms, drag. No timed, rapid or multi-touch requirement. Back closes the top sheet | 02 §2; WCAG 2.5.1 |
| V1 | Soft fascination | ≥ 3 independent ambient layers; composite repeat ≥ 20 s (600 s by construction) | 04 P5; C5 |
| V2 | Low-arousal colour | ≥ 85 % of area has HSV S ≤ 0.45 and V ≥ 0.45; accents ≤ 10 %; token colours only, C_OK ≤ 0.2 | 04 P6; 05 §4 |
| V3 | Curves | Radius ≥ 8 dp; no interior angle < 60° on friendly shapes | 04 P7 |
| V4 | Fractal scenery | Box-counting D of silhouettes in 1.3–1.5 | 04 P8; 05 §2.1 |
| V5 | Calm motion | No shake; ≤ 3 flashes/s; no linear spatial tweens; no pop-in (fade ≥ 300 ms); squash ≤ 20 %; breathing 3.5–4.5 s awake, 5–6 s asleep | 04 P9; 05 §3 |
| V6 | Clean gradients | All gradients dithered; no full-screen bloom, lens flare or chromatic aberration | 05 §1.2, §2.4 |
| V7 | Aesthetic bar | Rubric ≥ 80, each criterion ≥ 7, #1/#6/#8 ≥ 8 | 05 §5 |
| A1 | Loudness contract | −18 ±1 LUFS-I over ≥ 10 min of capture; TP ≤ −1 dBTP; short-term ≤ −14 LUFS-S | 06 §0.1 |
| A2 | Gentle spectrum | Energy > 10 kHz ≤ 0.5 %; 2–5 kHz ≤ 5 % (≤ 20 % for water); birds ≥ 15 dB under the bed; no 1–16 Hz AM on bright noise | 06 §1.4 |
| A3 | No negative sounds | No error buzz; pitches snap to the chord pentatonic | 06 §3 |
| A4 | Complete when muted | Every meaningful sound has a visual twin, and every reward has a sound | 02 §5; 06 §1.4 |
| X1 | Settings | Reduce Motion, Reduce Transparency, Text 100–200 %, Haptics Off/Subtle/Full, Mono, Left-handed, Music On/Ambience/Off | 02 R16; 05; 06 |
| X2 | Contrast & CVD | Text ≥ 4.5:1, UI ≥ 3:1, dark text on pastels; semantic colours ΔE_OK ≥ 10 under CVD simulation; colour never the only cue | 02 §5; 05 §0.4 |
| F1 | Performance | §3 budgets hold on the governor's low tier | 02 §4.3 |

---

## 5. Concept ranking & recommendation

### 5.1 Re-scoring with all reports

04's weights were re-cut. Criterion (d) was split into **d1**, the art ceiling from code (05), and **d2**, fit to the Compatibility/performance budget (01, 02). Criterion **j**, audio fit (06), was added. Scores are 1–5 [J].

| Criterion (weight) | A Lantern Pond | B Mossling Meadow | C Drizzle & Fern |
|---|---|---|---|
| a No stress (12) | 5 | 5 | 5 |
| b Idle progress (10) | 4 | 5 | 4 |
| c One-thumb (6) | 5 | 5 | 5 |
| d1 Code-only art ceiling (14) | 3: water is the hardest Compatibility shader | 4: fuzz shader is the main risk | 4: L-systems are code-friendly |
| d2 Budget fit (10) | 3: ripple heightfield needs an extra render target | 5: SDF creatures plus particles, 0 idle screen reads | 2: rain-on-glass refraction reads the screen every frame |
| e Soft fascination (10) | 5 | 5 (with A's stream) | 5 |
| f Relatedness (10) | 3 | 5 | 3 |
| g Return hook (8) | 4 | 5 | 3 |
| h Content scale (6) | 4 | 5 (parametric rig) | 4 |
| i Differentiation (6) | 2 | 3 | 4 |
| j Audio fit (8) | 4 | 5 (06 is written for it) | 3: a constant rain bed has high 2–5 kHz energy |
| **Total /100** | **76.4** | **94.8** | **76.4** |

Sensitivity [V-00, recomputed]:
- If the fuzz shader underdelivers (B d1 = 3), B still leads at 4.60 against 3.82 for both rivals.
- With differentiation weighted ×3, B scores 4.55, C 3.84 and A 3.62.

B wins under every weighting tried, as it did in 04's own sensitivity check.

### 5.2 Recommended concept: "Mossling Meadow" (B, merged with the best of A and C)

**Fantasy.** A sun-dappled hollow under an open sky (refuge with prospect), where round, felted *mosslings* nap, nibble and play in the garden you grow.

**Loops.**
- *Seconds:* tap a bud and it unfurls in 600 ms. Long-press 450 ms to pet (12 % squash, purr chime, TICK). Tap the stream for a ripple ring.
- *Minutes (30 s–5 min):* empty the 24-slot dew basket, plant 1–2 flowers or place one décor piece, read a postcard.
- *Days:* flower + décor combos attract species (Poisson λ ≈ 2/h). Growth takes 10 min / 1 h / 4 h. Weather, plus Seasons every ~14 in-game days that recur and remove nothing.

**Economy.** One currency (dew) plus affection that never decays. Displayed values ≤ 99 999. 10–12 copies per item at r = 1.10–1.12. The next purchase costs about 30–90 min of passive income. The first visitor arrives at 20–40 s.

**Merged in.**
- From A: a quiet, trickling stream, dusk lanterns and fireflies.
- From C: procedural L-system flora and rain weather, with mosslings sheltering under leaves (no rain-on-glass).
- From Townscaper: every placement auto-beautifies (Poisson clusters of 3, 5 or 7).

**Signature look.** SDF fur-rim creatures with backlit peach fuzz at golden hour. One parametric rig gives ~48 species plus variants.

**MVP slice.** One hollow, Spring, 5 palettes, clear/breeze/rain, 12 species, 8 flowers, 6 décor pieces, album, postcards, settings, vi/en.

**Why B.** It scores highest under every weighting (94.8 against 76.4 for both A and C). It is the only concept whose hero effect fits the Compatibility budget with no per-frame screen reads or extra render targets. It also has the best audio fit and the strongest relatedness (SDT).

---

## 6. Open risks & mitigations

| # | Risk | Impact | Mitigation / trigger |
|---|---|---|---|
| R1 | Fuzz shader reads as cheap | Kills the hook | **Spike first** (sky + 1 creature + grass). Gate: rubric #3, #5, #6 and #9 ≥ 7 before any content work. Fallback: SVG-layered fur tufts with the same rim shader |
| R2 | No Swappy on Compatibility/Android, so 30 fps may jitter | Feels janky | Measure frame-delta p95 on device. If > 40 ms, keep 60 fps with lighter content. If 120 Hz jitter exceeds 2 ms, A/B the `mobile` renderer (D1 keeps that one line) |
| R3 | iOS GLES is deprecated; untested gamma (no colour space on the EAGL layer) | Future breakage, colour shift | Keep shaders Mobile-portable. Run a Metal A/B on the first Mac/TestFlight pass; do a device colour check (05 §6) |
| R4 | llvmpipe is not a phone GPU | Perf surprises | CI asserts the proxy budgets (draw calls, particles, texture memory, layer count). A device checklist runs before every milestone (02 §7) |
| R5 | `opengl3_es` determinism unproven | Flaky goldens | Day-1 double-render test. Fall back to `opengl3`. Keep goldens per driver |
| R6 | DPITexture is experimental | UI icon breakage | Icons only. Fallback: `texture` importer at `svg/scale=1.5` with node scale 1/1.5 |
| R7 | `JavaClassWrapper` haptics and the iOS haptic feel are untested on device | Missing or odd haptics | Subtle by default, toggle in settings, ≥ 60 ms rate limit. On failure: no haptic, never a buzz |
| R8 | Android audio adds ≥ 46 ms latency | Taps feel late | Trigger SFX on touch-down, use soft attacks, test against I1 |
| R9 | Crowded niche (Neko Atsume, Usagi Shima, Cats & Soup) | Weak pull | Differentiate with the felted look, a generative Lydian score and a no-numbers economy. Target the "Today tab" rubric item ≥ 8 |
| R10 | Content volume | Thin album | Parametric rig plus procedural flora; MVP at 12 species, growing to 48 |
| R11 | No native plugins, so no billing or notifications | No revenue path in v1 | v1 is free. A one-time unlock (04 §5) is a later business decision with a native billing plugin and a new ADR |
| R12 | iOS builds and AAB release need a Mac and Gradle/SDK | Store delivery blocked here | Container deliverables are the debug APK and the Web demo. The project stays iOS- and AAB-ready (02 §6) |
| R13 | Flagged science (PH17 verbatim quotes, the W&B typology, Buxton effect sizes, WGSN 2027 colour, sound-on rates) | Credibility | Internal use only. **No health or therapeutic claims** in store copy (04 §3.1, 06 §1.1) |
| R14 | Web build drops bus effects | Dry SFX on Web | Bake wet SFX variants for `web` (06 §2.5) |
| R15 | Vivid display modes over-saturate | Breaks the palette | Palette chroma ≤ 0.163; device check on Samsung "Vivid" |

---

## 7. Build order (next workflow)

1. **Skeleton.** The §3 `project.godot`, export presets, `tools/vendor_addons.sh` (GUT), `tools/qa/capture.gd`, CI, and the `opengl3_es` determinism check.
2. **Look spike (R1 gate).** Sky, palettes, `g_time`, fBm silhouettes, one SDF mossling, grass sway, dust motes. Then a 3-rater rubric pass.
3. **Audio toolchain, in parallel.** Port `synth.py`, add the loudness and spectral gates (A1, A2), render beds, pads at 70 BPM and SFX S01–S12.
4. **Systems.** Sim, economy, save, offline progress, visitors, plus headless tests for E1, E3, E5 and E6.
5. **UI.** Dock, sheets, glass, safe area, settings (X1), i18n vi/en.
6. **Visual QA loop** until V7 passes. Then write the docs (`GDD.md`, `ART_BIBLE.md`, `AUDIO_BIBLE.md`, `ARCHITECTURE.md`).
