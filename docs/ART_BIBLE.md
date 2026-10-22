# ART BIBLE — "Felted Diorama"

*Art Director + Technical Artist · 2026-10-20 · Godot 4.7.2-stable, Compatibility renderer · status: **binding** for art, shaders, VFX, UI visuals and motion.*

This document turns `docs/research/00-SYNTHESIS.md` (D2, D7, D8, D9 binding) and `docs/research/05-visual-motion-aesthetics-2026.md` into an implementable spec. A technical artist should be able to build every shader, stamp, particle system and UI surface from it without making a new decision. Where the GDD role had already written data (`data/spots.json`, `species.json`, `flora.json`, `decor.json`, `world.json`, `economy.json`), this bible **adopts the GDD's positions, ids and timings** and specifies how they look.

**Tags.** **[V]** verified in 4.7.2 source/docs or measured here · **[05]**/**[00]** taken from the research · **[J]** Art Director judgement (binding until an ADR changes it).

**Single sources of truth (do not duplicate numbers elsewhere).**

| File | Owner | What it holds |
|---|---|---|
| `data/palettes.json` | Art | All colours: 5 time-of-day palettes (12 base slots from 05 + 14 derived), scalars, celestial path, rain transform, UI tokens, `cr_*` creature tokens + resolved species colours, `fl_*` flower tokens, materials, FX colours |
| `data/motion_tokens.json` | Art/Motion | Durations, curves, springs, `k/600` loop table, creature/flora/UI motion parameters, Reduce Motion rules |
| `data/creature_rig.json` | Art | SDF part catalog (ids + parameters), instance-uniform layout, per-species art overrides, resolved rig per species |
| `data/spots.json`, `species.json`, `flora.json`, `decor.json`, `world.json`, `economy.json` | GDD | Layout, species rig vocabulary + token names, flowers, décor, time-of-day phases, weather, economy |
| `tools/art/art_data.py` | Art/QA | `resolve` regenerates the derived sections; `check` asserts 412 colour/contrast/CVD/identity rules (exit 1 on failure). Run in CI after lint |
| `docs/art/hollow_layout_guide.png` | Art | Annotated 540×960 guide of zones, beds, spots, décor anchors, props, stream, HUD/dock (generated from `spots.json`; a layout guide, **not** art) |
| `docs/art/reference/fur_spike.gdshader` + `fur_spike_golden.png` | Art | Verified feasibility spike of the fur shader (compiles and renders on `opengl3_es`) |

---

## 0. Decisions made in this bible (summary for other roles)

| # | Decision | Why |
|---|---|---|
| A1 | **World coordinates = the GDD's 1080×1920 design frame, bottom-anchored.** `World` root is translated by `g_world_offset = (round((viewport_w − 1080)/2), viewport_h − 1920)`; taller phones get more sky above y = 0, wider screens centre the 1080 column | Matches `spots.json` (`anchor: bottom`) and 02 §1.3 (Z2 absorbs slack) |
| A2 | **Creatures = one SDF quad per creature** (body, ears, tail, antennae, pattern, face in one `mossling_fur.gdshader`, 16 instance uniforms) + a separate contact-shadow quad. Feasibility verified on `opengl3_es` [V] | Seamless felt silhouette (smooth-union of parts), 1–2 draw calls per creature, crisp under squash, no SVG rasters (C11) |
| A3 | **Flora = tone-mask SVG stamp atlas + procedurally built bed meshes** (one `MeshInstance2D` per bed, stems as tapered strips, petals/leaves as atlas quads); sway in the vertex shader; unfurl rebuilds the mesh for 600 ms | Hand-authored shapes, procedural variety, 1 draw call per bed |
| A4 | **Palette gradient keyed by `g_day`** at 0.0/0.2/0.4/0.6/0.8/1.0 = night/dawn/day/golden/dusk/night; `world.json` owns how clock time drives `g_day` | The GDD already defined `g_day` per phase; one owner per fact |
| A5 | **26 new global shader uniforms** (§4.1). The Director must add the `[shader_globals]` block in §4.1 to `project.godot` | Lighting is faked from globals (D2); shaders stay data-free |
| A6 | **V2 measurement protocol amended** for dusk/night (HSV V ≥ 0.45 is impossible by design at night): dusk/night use OKLCh C ≤ 0.10 on ≥ 85 % of the area (§11.3). **Needs Director ratification** | The binding night palette (05 §0.4) has V < 0.45 by construction |
| A7 | **Live glass tint is adaptive** (0.66 → 0.90 over dark backdrops) and `ink_2` is never drawn directly on glass | Measured: at a fixed 66 % tint, `ink_2` over the night sky is 2.77:1 (fails); adaptive ≥ 4.7:1 everywhere [V, §4.17] |
| A8 | Silhouettes measure D ≈ 1.15 alone; **V4 is measured on the whole edge-detected world frame** (04 P8 wording), which reaches D ≈ 1.30 only with ≥ 260 grass tufts, the willow canopy and clouds [V, §4.4] | A cozy single ridgeline with D 1.3–1.5 would read jagged |
| A9 | The GDD's 6 décor sets (pinwheel, cairn, toadstool, stream stones, firefly lantern, wind chime) are the MVP set; the brief's bridge and blanket are kept as reserve designs (§6.9) | `decor.json` exists |
| A10 | **UI behaviour and feedback values follow `docs/GDD.md` §3.1, §8.1 and §8.3**: dock order [Settings][Garden][Basket][Album] at x 135/405/675/945; sheets above a visible dock; HUD dew chip, time chip and "just watch" eye; touch-down 0.96 in 80 ms (world 0.94); pet squash 0.88 with hearts on release; ready-bud tap → 600 ms unfurl (auto after 20 s); 380 ms stream ripple. This bible specifies how those look | The GDD owns UX; one owner per fact |

---

## 1. Look statement and reference frames

### 1.1 Look statement
**A needle-felted diorama at the bottom of a sunlit hollow.** Every object is a soft, rounded mass with a fine fringe of fibres; light is warm, directional and always tells the time; air has depth (six planes, haze, halos); colours are pastel, warm-neutral and low-chroma, with one confident blue in the UI. The world never stops moving, but nothing moves fast: grass leans in travelling gusts, mosslings breathe, the brook glints. UI is a frosted, high-opacity layer that floats over the world and gets out of the way.

Five words for every review: **soft · lit · deep · calm · handmade.**

What makes it ours (signature): **backlit peach-fuzz rims on felted creatures at golden hour**, a warm sun sitting in the gap above the hill crest, and lantern pools doubling in the brook at night.

### 1.2 Reference frame A — Golden hour, clear, 17:40 (signature frame)
- **Sky** (top 36 % of the 1920 frame): OKLab gradient `#7A8DCB` (top) → `#E8A3A1` (42 %) → `#FFCB7D` at the horizon (y 690), with a soft haze band glowing at y 640–760. The sun disc (96 px) sits at **(560, 640)**, its lower edge just touching the far-hill crest. Inner halo 1.5× disc; outer halo 1.5× wider than by day (`halo_scale` 1.5, α 0.30), spilling a warm veil over the far and mid hills.
- **Hills:** far `#DCAA8F`, mid tree line `#B98670` whose crest has a thin `key`-coloured rim; the meadow crest (y 742–805) is the brightest ridge line because it is backlit.
- **Meadow:** `#AD8773` at the crest → `#977B73` at the brook. Grass tips `#CA956F` catch the light. All shadows are long (2.5× object height, clamped), fall **toward the viewer** and fan away from the sun.
- **Focal:** the sun stone (540, 1123) reads `#DCB998`. Puffmoss naps on it (fur `#D3C894` after the ambient multiply), with a **peach-fuzz rim** in `#FFC266` along its top and sun-facing edges (rim 0.8, backlight 1.0). Its fibre fringe glows, and it is the highest local contrast on the ground.
- **Air:** 4 light shafts radiate from the sun down through the gap between the willow and the stump (α ≤ 0.12). 36 dust motes are visible only inside the shafts; 10 pollen grains drift left to right.
- **Brook (y 1425–1526):** a bright ribbon reflecting `#F5B98F` with sparse glints. It is the bottom anchor of the frame.
- **Eye path:** sun → backlit crest → sun stone and napping creature → brook glints → back up along the lit willow edge. Values: halo and rims at L* 90+, creatures at L* 80+, meadow at L* 54–60, darkest are the L5 corners (`#5A4A62`) and the willow shade side.

### 1.3 Reference frame B — Night with fireflies, 23:00, clear
- **Sky:** `#111938` → `#1D2954` → `#3D4F8C`. About 70 stars, twinkling at 0.2–0.5 Hz, fade out toward the horizon. The moon (84 px) at **(820, 380)** has a small cool halo (`#DDE7FF`, scale 0.8, α 0.15).
- **Land:** far `#2E3C6B`, mid `#222E58`, meadow `#212D56` → `#1C274D`. The value ladder is deliberately compressed (05 §2.2).
- **Creatures** are multiplied by ambient `#5D6AA0` (cream fur → `#585E81`) and carry a moon rim in `#9DB4FF` (α 0.5) on their upper-right edges. Sleeping mosslings breathe slowly (5–6 s) and a soft "z" rises every 4.84 s.
- **Warm light pools — the night focal system:**
  - 3 glow mushrooms at the sun stone's foot are always present, so night has a focal from minute one;
  - firefly lanterns along the far bank (when owned) cast pools of radius 150 px in `#FFC978` at α 0.25–0.40, breathing ±5 % with a 3.3 s period;
  - each lantern is mirrored as a vertical streak in the brook;
  - moonblooms (when planted) glow pale blue-white.
- **18 fireflies** drift through y 900–1450, biased toward lanterns and flowers. Each has a 6–9 px core and a 36–60 px halo, with a soft 0.85 s glow every 6–7 s. They never fully switch off (35 % base glow) and fewer than 3 begin a glow per second.
- **Eye path:** lantern pools and their reflections → glow mushrooms at the sun stone with a sleeping creature → moon.

### 1.4 Reference frame C — Light rain, 11:00
- **Palette:** day palette after the rain transform (§3.4): sky `#82A7C4` → `#A6C2D3` → `#D2DFE3`, key flattened to `#E3DDCB`, meadow `#97B49B` → `#88A88C`. There is no sun disc, no shafts and no dust.
- **Sky:** soft cloud banks (cloud cover 0.85 from `world.json`) drift left at ≈ 5 dp/s (`palettes.json weather.cloud_autoscroll_px_s.rain` −16 px/s) and cover most of the sky.
- **Rain:** 120 streaks (1×12 dp, α 0.25–0.40, tilted 8° downwind) fall at 360–720 px/s. 6 splash rings per second bloom on the meadow (flattened ×0.35 for perspective). The brook shows procedural rain rings, and the meadow gets a faint wet sheen (+15 % sky reflection).
- **Creatures:**
  - Those at shelter spots (`fern_shade`, `willow_root`, `stump_hollow`, `toadstool_ring` with ≥ 3 toadstools) tuck in with ears flattened.
  - Anyone in the open holds a **leaf umbrella** (a big round leaf stamp, tilted 12°, swaying on the `follow` spring).
- **Eye path:** pale creatures under green umbrellas → rippling brook → the willow's swaying fronds.
- Contrast is softer than by day, but the creatures still clear the meadow: ΔL* ≥ 9 in every clear palette (§3.6), and rain lowers chroma, not lightness.

---

## 2. Composition of the main hollow (1080×1920 portrait)

### 2.1 Coordinate system and aspect behaviour
- **Units:**
  - design px in a 1080×1920 frame, x right, y down; 1 dp = 3 px (C2);
  - normalised GDD values are converted as `px = (x·1080, y·1920)`.
- **Bottom-anchored world:** `World.position = (round((W − 1080)/2), H − 1920)` with W, H = viewport size (W = 1080 and H = 1920–2600 on phones; `scripts/main/main.gd _layout`). Shaders receive the same offset as `g_world_offset`. All positions in this document are design px; add the offset to get canvas px.
- **Taller screens (20:9 to 23:9):**
  - the extra 480–680 px are sky;
  - the sky gradient always spans from the *visible* top to the horizon (§4.3);
  - the HUD anchors to the top safe area and the dock to the bottom.
- **Wider screens (tablets, foldables, ≈ 1440–1600 px wide at H = 1920):**
  - the 1080 playfield column is centred;
  - sky, far, mid and meadow geometry are generated for x ∈ [−400, 1480] and extend to the sides (no bars);
  - props stay at their design positions;
  - the HUD anchors to the safe-area corners, not to the column.

### 2.2 Interaction zones (from `data/spots.json`, at H = 1920)

| Zone | y (px) | Rules (02 §1.2, I2) |
|---|---|---|
| Z0 system | 0–144 | Nothing interactive; sky bleeds under the status bar/cutout. Runtime top inset T = max(safe-area top, 72 px) |
| Z1 HUD | 144–336 (eye hit reaches 360) | Passive dew and time chips. The only HUD target is the "just watch" eye (72 dp = 216 px hit, y 144–360). Nothing else occupies 336–360 |
| Z2 look | 336–845 | Optional delight taps only (wind chime branch, mailbox, pinwheels), hit ≥ 64 dp = 192 px |
| Z3 tend | 845–1507 | Core targets: beds (hit 270×189), creatures (hit ≥ 180 px), basket, stream tap band (`spots.json`, currently 1436–1505). Hit priority (GDD): mossling > bed with a ready bud > prop > bed > stream > background |
| buffer | 1507–1530 | Nothing |
| Z4 dock | 1530–1793 | Dock pill 1541–1781; button hit rects 228×228 at y 1547–1775 |
| Z5 gesture | 1793–1920 | Nothing interactive. Runtime: max(safe-area bottom, 127 px) |

- **Side margins:** targets keep ≥ 16 dp (48 px) from the edges.
- **No drag start** within 24 dp (72 px) of either side (`spots.json safe_x` 0.067–0.933).

### 2.3 Art layers and y-bands (D2: 6 `Parallax2D` layers)

| Layer | Node / `scroll_scale` | Content | y band at H = 1920 (crest → body bottom) | Notes |
|---|---|---|---|---|
| **L0 Sky** | `Parallax2D` 0 → `SkyQuad` | Opaque gradient, haze band, sun/moon disc + halos, stars (all in one shader) | visible top → `max(far crest) + 12` (≈ 700) | `blend_disabled`, the only opaque full-width layer |
| **L1 Celestial** | `Parallax2D` 0.02 | Empty marker node. The sky shader shifts stars, sun and moon by 0.02 × the map pan (global `g_cam_pan`; the idle drift is ignored, ≤ 2 px); the sun veil and light shafts follow the disc (`celestial_shift()`) | — | Keeps the 6-layer parallax contract at no fill cost |
| **L2 Far** | `Parallax2D` 0.10 | Far hills polygon + 2–3 cloud quads (autoscroll −4 dp/s, `repeat_size` 1800) | crest 610–670 → 790 | Feather 6 px; crest→bottom `far` → `far_haze` |
| **L3 Mid** | `Parallax2D` 0.30 | Tree-line polygon (fBm ridge + canopy bumps) | crest 560–705 → 800 | Feather 3 px; `mid` → `mid_haze`; crest rim at backlight |
| **L4 Play** | `Parallax2D` 1.0 | Meadow polygon, path, brook, grass bands, `YSort` (props, beds, décor, creatures), lamp pools, `Air` (shafts, particles) | crest 742–805 → 1920 | The only layer with focal detail and outlines |
| **L5 Frame** | `Parallax2D` 1.3 | Bottom-left reeds (x 0–300, y 1690–1920), bottom-right clover (x 840–1080, y 1720–1920), top-right leafy bough (x 820–1080, y 0–300) | as listed | ≤ 8 % of screen area (05 cap 12 %); darker (fg token) and blurred (mip LOD 2) |

Camera: a static `Camera2D` with idle drift ≤ 4 dp/s on a 45 s sine path (`motion_tokens.world`), disabled under Reduce Motion.

### 2.4 The hollow map (design px; all from `data/spots.json` unless marked *art dressing*)

**Landscape.**
- **Far crest:**
  - `640 + 26·fbm(x; f0 2.2, 7 octaves, gain 0.68, seed 11)`;
  - minus two broad Gaussian rises (−34 px at x 380 with σ 90; −22 px at x 820 with σ 70).
  - Visible mainly in the window between the willow (x < 340) and the stump trees (x > 880).
- **Mid tree line:**
  - ridge base through (0, 600), (300, 640), (520, 700), (700, 705), (900, 650), (1080, 610), plus `18·fbm(f0 6, 7 oct, gain 0.70, seed 23)`;
  - topped with 120 canopy circles, radius 10–46 px (power law α 2.0), centres sunk 0.15–0.6 r below the ridge;
  - upper envelope sampled every 4 px.
- **Meadow crest** (the walkable hill top):
  - through (0, 800), (300, 790), (600, 758), (800, 742), (1000, 790), (1080, 805), plus `6·fbm(f0 4, 6 oct, 0.68, seed 31)`;
  - plus a grass fringe of 140 bumps, radius 3–10 px.
  - Creatures whose feet are above the crest line (`entry_hill` 605,682) are parented to `L4/BehindCrest` (a node the creature owner adds under `World/Ground`, drawn before `Meadow`), so they rise into view as they hop over.
- **Brook:**
  - centre line = `spots.json stream.polyline`, (1123,1425) → (972,1444) → (821,1471) → (670,1486) → (540,1482) → (389,1494) → (238,1509) → (86,1517) → (−43,1526), Catmull-Rom;
  - water ribbon 69 px tall (`water_width` 0.036 read as a fraction of frame height; see §12);
  - 10 px damp banks (`water_bank`);
  - it springs from `spring_rock` at the right and leaves at the left edge.
- **Near bank:** y ≈ 1500–1920. Lit meadow (`ground_front_lit` mixed 10 % toward `shadow`), not fg-dark: this is what keeps day V2 at 89 % (§3.9).

**Props** (from `spots.json props`; centre = `pos`).

| Prop | Centre | Size (px) | Tap | Art notes |
|---|---|---|---|---|
| `willow` | (130, 576) | 420×510 | — | Weeping willow, trunk at x ≈ 120, canopy y 321–831, 11 hanging frond strips. Frames the top-left (refuge) |
| `wind_chime_branch` | (324, 645) | 120×180 | ring_chime | Low branch of the willow; chimes hang from it |
| `mailbox` | (97, 758) | 90×144 | open_postcards | Flag rises and glows softly when a postcard is unread |
| `stump` | (972, 854) | 210×180 | — | Old stump with a front hollow (`stump_hollow` spot), moss, a fern |
| `basket` | (540, 922) | 132×108 | open_basket | Wicker basket; visibly fills with dew drops and gifts |
| `sun_stone_rock` | (540, 1123) | 261×120 | — | **FOCAL**: broad warm flat stone; `sun_stone` spot on top (540, 1085) |
| `spring_rock` | (1026, 1411) | 180×120 | — | Mossy rock where the brook springs |

**Beds** (hit 90×63 dp = 270×189 px; up to 16 stems each at the offsets in `spots.json`): `bed_1` (540, 1325), `bed_2` (216, 1267), `bed_3` (864, 1267), `bed_4` (238, 989), `bed_5` (842, 989).

**Spots** (creature feet):

| Spot | Feet (x, y) | Depth scale |
|---|---|---|
| sun_stone | (540, 1085) | 0.79 |
| moss_cushion | (378, 1142) | 0.82 |
| clover_bank | (702, 1142) | 0.82 |
| fern_shade | (86, 1123) | 0.81 |
| stream_bend | (356, 1444) | 0.97 |
| willow_root | (140, 826) | 0.65 |
| hill_crest | (605, 778) | 0.63 |
| stump_hollow | (972, 839) | 0.66 |
| moon_rock | (799, 739) | 0.62 |
| toadstool_ring | (346, 826) | 0.65 |
| stream_stones | (713, 1478) | 0.99 |
| lantern_nook | (977, 1417) | 0.96 |
| cairn_side | (162, 1425) | 0.96 |

`moss_cushion` and `clover_bank` get small art-dressing mounds (moss cushion, clover patch) so the spot reads.

**Décor anchors** (each copy takes the next position; see `spots.json decor_anchors`):

| Décor | Layout | Positions |
|---|---|---|
| `firefly_lantern` | path | Along the far bank, y 1344–1453 |
| `stream_stones` | path | In the water, x 540–929, y 1459–1485 |
| `leaf_pinwheel` | scatter | On the slope below the crest, y 714–839 |
| `toadstool_seat` | ring | Ring around (346, 826) |
| `pebble_cairn` | stack | Upward at x 49, y 1398 → 1251 |
| `wind_chime` | string | Along the branch, (280–368, 645–657) |

**Entries:** `entry_fern_gap` (−86, 1123), `entry_stump` (1166, 874), `entry_hill` (605, 682, over the crest), `entry_streamside` (−86, 1430).

***Art dressing*** (non-interactive, `mouse_filter` ignore; never covers more than 30 % of any hit area):
- 3 glow mushrooms at the sun stone's left foot (470–505, 1165–1180);
- a fern clump framing the fern gap (x 0–130, y 1050–1170);
- cattails/reeds at the spring rock (980–1080, 1350–1430);
- 3 clover patches at (430, 1290), (700, 1225) and (905, 1385);
- 5 bank pebbles;
- the moss mound at `moss_cushion` and the clover patch at `clover_bank`.

**Depth scale** for everything standing on the meadow:
- `s(y) = clamp(0.62 + 0.38·(y − 760) / 740, 0.62, 1.0)`;
- applied as `Node2D.scale` from the feet y, and updated while a creature moves.

### 2.5 Focal point, leading lines, rest areas
- **One focal: the sun stone** (centre 540, 1123 = 58.5 % of height, inside 05's 55–66 % band). It is the brightest ground prop (stone_warm L* 85), carries the most-visited spot (`sun_stone`, capacity 2), and sits on the vertical light axis sun → crest → stone at golden hour.
- **Leading lines:**
  1. **The path** (`ground_path`, α 0.55, noisy soft edges):
     - runs from the crest gap (605, 760) down behind the stone to (560, 1060);
     - continues from the stone's front (540, 1180) down to the stream stones at (560, 1470);
     - width 60 px at the crest, widening to 150 px at the brook.
     - It is the route creatures take from `entry_hill`.
  2. **The brook:** a bright horizontal base line.
  3. **The willow:** its frond curtain curves toward the stone.
- **Rest areas** (low detail): the sky above y 330 (30–40 % of the frame on 20:9) and the open meadow between the beds. Grass density there is 40 % of the edge density.
- **Detail density** peaks around the focal (stone lichen, mushrooms, creature) and falls off toward the edges, where edges are softer.
- **Value plan by day** (squint test):
  - light 60 %: sky, brook, creatures, stone, glass UI;
  - mid 30 %: meadow, hills;
  - dark 10 %: L5 corners, bed soil, shadows, willow shade side.
- **At night** the hierarchy comes from warm light pools (§8.3), not from silhouettes.

### 2.6 Safe areas for HUD and dock (02 §1.2, I2) — exact px at H = 1920, T = 120 px inset
- **Top bar:** chips are 120 px tall at y = T + 24 = 144 (→ 264): dew chip from x 48, time chip x 768–888, eye x 912–1032 (eye hit 216×216, 144–360). Side margin 48 px.
- **Dock:** pill x 24–1056, y 1541–1781 (240 tall), anchored `bottom = H − max(safe_bottom, 127) − 12`. Button centres x 135/405/675/945 (GDD); hit rects 228×228 at y 1547–1775.
- **Sheets:** bottom = dock top − 24 (1517), height = round(0.56·H) (1075 → top 442), x 24–1056. The dock stays visible.

The annotated guide is `docs/art/hollow_layout_guide.png`. It predates the 2026-10-21 I2 nudge (U6: mailbox and wind-chime branch +0.02 = +21.6 px to the right); `spots.json` wins, and `docs/gdd/hollow_layout.png` (`tools/sim/layout_preview.py`) is regenerated from the data.

---

## 3. Palettes (`data/palettes.json` is the single source of truth)

### 3.1 The five time-of-day palettes (verbatim from 05 §0.4)

| Slot | Dawn | Day | Golden hour | Dusk (blue hour) | Night | Shader global |
|---|---|---|---|---|---|---|
| `sky_top` | `#8EA3D8` | `#6FB6EC` | `#7A8DCB` | `#2D3A70` | `#111938` | `g_sky_top` |
| `sky_mid` | `#C8B5E0` | `#9ED2F2` | `#E8A3A1` | `#6C5C9E` | `#1D2954` | `g_sky_mid` |
| `sky_horizon` (= haze) | `#F7CBB7` | `#D6EEF6` | `#FFCB7D` | `#F0A08C` | `#3D4F8C` | `g_sky_horizon` |
| `glow` (sun/moon halo) | `#FFE6C7` | `#FFF5D6` | `#FFE29E` | `#FFB98E` | `#DDE7FF` | `g_glow` |
| `far` silhouette | `#C9B9D6` | `#A8D4CC` | `#DCAA8F` | `#6F6494` | `#2E3C6B` | `g_far` |
| `mid` silhouette | `#9E99BE` | `#7DBF91` | `#B98670` | `#4E487C` | `#222E58` | `g_mid` |
| `near` ground | `#717FA6` | `#4FA06F` | `#7F6A72` | `#373762` | `#182246` | `g_near` |
| `fg` frame | `#4F5C82` | `#2F7B5B` | `#5A4A62` | `#262849` | `#0F162E` | `g_fg` |
| `ambient` (multiply on objects) | `#E2D6EE` | `#FFFFFF` | `#FFE0C2` | `#B3A3D1` | `#5D6AA0` | `g_ambient` |
| `key` (rim / key light) | `#FFD6AE` | `#FFF1C2` | `#FFC266` | `#FF9E7E` | `#9DB4FF` | `g_key` |
| `shadow` tint | `#5D5C8E` | `#3B6C8C` | `#6A4E80` | `#1F2244` | `#0B1130` | `g_shadow` |
| `accent` | `#FFB59E` | `#FFC56E` (+ `accent_2` `#FFB3C7`) | `#FF8C7A` | `#FFC46B` | `#FFC978` | `g_accent` |

**Rule — the 05 haze percentages are already baked into `far`/`mid`.** Shaders add only a vertical "valley fog" term from crest to body bottom (`far` → `far_haze`, `mid` → `mid_haze`) plus the sun veil (§4.4). They never re-haze the crest colour, which keeps the measured ladder (day CR vs horizon 1.34 → 1.79 → 2.64 → 4.24) intact.

**Terrain vs objects:**
- *Terrain* (sky, hills, meadow, grass, brook, L5) uses the slots directly.
- *Objects* (props, décor, flowers, creatures) are authored in day colours and lit at runtime as `albedo × g_ambient`, plus key/shadow (§4.2).
- Never multiply terrain by ambient: it is already per-time-of-day.

### 3.2 Derived slots (exact values; formulas in `palettes.json tod.derived_formulas`, all OKLab mixes)

| Derived slot | Dawn | Day | Golden | Dusk | Night | Formula |
|---|---|---|---|---|---|---|
| `ground_back` | `#888CAF` | `#67AF82` | `#997973` | `#49436E` | `#1D2850` | mix(mix(near, mid, .35), sky_horizon, .06) |
| `ground_front` | `#717FA6` | `#4FA06F` | `#7F6A72` | `#373762` | `#182246` | near |
| `ground_back_lit` | `#9695B0` | `#85BB8D` | `#AD8773` | `#534970` | `#212D56` | mix(ground_back, key, ground_light) |
| `ground_front_lit` | `#818AA8` | `#72AF7D` | `#977B73` | `#423D65` | `#1C274D` | mix(ground_front, key, ground_light) |
| `ground_path` | `#AEA2AD` | `#A0BF9F` | `#BE997E` | `#806B7F` | `#464D6E` | mix(mix(ground_back_lit, sky_horizon, .18), soil.detail, .22) |
| `grass_tip` | `#B5A9BC` | `#9FCC9D` | `#CA956F` | `#775F81` | `#3E4D7F` | mix(mid, key, .25) |
| `grass_root` | `#6C76A0` | `#499378` | `#7A6376` | `#31325A` | `#151E40` | mix(near, shadow, .25) |
| `water_deep` | `#7480AE` | `#52999E` | `#786D90` | `#2D325E` | `#121A3B` | mix(mix(near, shadow, .40), sky_top, .30) |
| `water_shallow` | `#E2C2CB` | `#BDE1F4` | `#F5B98F` | `#B28398` | `#2E3D72` | mix(sky_mid, sky_horizon, .55) |
| `water_bank` | `#6B749F` | `#48917A` | `#786277` | `#303159` | `#141D3F` | mix(near, shadow, .30) |
| `cloud_lit` | `#FCDBC1` | `#EFF2E3` | `#FFD991` | `#F9AF8D` | `#99A8D1` | mix(sky_horizon, glow, .60) |
| `cloud_shade` | `#B4A4D1` | `#8BBFDF` | `#D0939C` | `#5D518D` | `#1A254D` | mix(sky_mid, shadow, .18) |
| `far_haze` | `#D7BFCD` | `#B6DCD8` | `#E6B48B` | `#947794` | `#324275` | mix(far, sky_horizon, .30) |
| `mid_haze` | `#ABA1BE` | `#8BC6A0` | `#C39072` | `#645680` | `#263360` | mix(mid, sky_horizon, .15) |

**Scalars per palette** (interpolated linearly on the same `g_day` keys):

| Scalar → global | Dawn | Day | Golden | Dusk | Night |
|---|---|---|---|---|---|
| `rim` → `g_rim` | 0.60 | 0.35 | 0.80 | 0.80 | 0.50 |
| `backlight` → `g_backlight` | 0.35 | 0.10 | 1.00 | 0.60 | 0.20 |
| `ground_light` → `g_ground_light` | 0.12 | 0.18 | 0.20 | 0.06 | 0.04 |
| `halo_scale`, `halo_alpha` → `g_halo` | 1.0, 0.22 | 1.0, 0.18 | 1.5, 0.30 | 1.3, 0.26 | 0.8, 0.15 |
| `stars` → `g_stars` | 0.15 | 0 | 0 | 0.45 | 1.0 |
| `lights` → `g_lights` | 0.15 | 0 | 0.10 | 0.75 | 1.0 |
| `shafts` → `g_shafts` | 0.5 | 0.7 | 1.0 | 0 | 0 |
| `shadow_alpha` → `g_shadow_alpha` | 0.26 | 0.30 | 0.35 | 0.18 | 0.22 |
| `cloud_shadow` → `g_cloud_shadow` | 0.10 | 0.12 | 0.10 | 0 | 0 |
| `mist` → `g_mist` (low valley mist, GDD §6.1) | 0.20 | 0 | 0.04 | 0.08 | 0.06 |

### 3.3 Time → palette (PaletteDriver contract)
1. **Clock to `g_day`:** `world.json` maps the local clock to `g_day`: dawn 05:00 → 0.2, day 08:00 → 0.4, golden 16:30 → 0.6, dusk 18:30 → 0.8, night 20:30 → 1.0. Each change crossfades over 2400 s (`phase_crossfade_s`). `g_day` jumps 1.0 → 0.0 at midnight, which is seamless because both ends are night.
2. **Gradients:** build one `Gradient` per colour slot, with points at offsets 0.0/0.2/0.4/0.6/0.8/1.0, `interpolation_mode = GRADIENT_INTERPOLATE_LINEAR` and `interpolation_color_space = GRADIENT_COLOR_SPACE_OKLAB` [V Gradient.xml:84, 112]. Sample at `g_day`.
3. **Weather transform:** apply the rain transform (§3.4) scaled by `g_rain`, then `g_ambient *= world.json weather.ambient_mult`.
4. **Push globals** with `RenderingServer.global_shader_parameter_set()` at 2 Hz in steady state, and every frame only while a crossfade is running.
   - Never call `global_shader_parameter_get()` during play (sync penalty, RenderingServer.xml:1774); keep a CPU mirror instead.
5. **Celestial:** `g_sun_pos`/`g_moon_pos` follow the hour-keyed Catmull-Rom paths in `palettes.json tod.celestial` (design px + `g_world_offset`). `g_celestial` holds the bodies' visibility (fade 30 min at path ends; sun visibility × (1 − 0.85·g_cloud)).
   - `g_sun_dir = normalize(body − (540, 1150))` of the brighter body.
   - Elevation `elev = clamp((690 − body_y)/400, 0.05, 1)`.
   - Examples: dawn (200, 540) → (−0.49, −0.87); day 12:30 (780, 380) → (0.30, −0.95); golden (560, 640) → (0.04, −1.00); night moon (820, 380) → (0.34, −0.94).
   - The synthesis default `(0.6, −0.8)` is only the boot value.
6. **Overrides:** the QA/debug override `--tod=<0..1> --weather=<id>` sets `g_day` and `g_rain` directly (deterministic captures).

### 3.4 Weather (the art half; wind, cloud cover and particle counts live in `world.json`)
`palettes.json weather.rain_transform`, scaled by `r = g_rain`:
- **Colour slots:** chroma × (1 − 0.45 r) for all sky, terrain and ambient slots; sky lightness −0.04 r.
- **Key:** chroma × (1 − 0.60 r), lightness −0.06 r.
- **Scalars:** rim × (1 − 0.5 r), backlight × (1 − 0.8 r), shafts × (1 − r), ground light × (1 − 0.7 r), halo α × (1 − 0.6 r) (GDD: sun halo ×0.4), cloud shadow × (1 − r), mist + 0.10 r.
- **Wet sheen:** the meadow adds a 0.15 r sky reflection.
- **Breeze:** changes no colours; only `g_wind` (world.json 0.85), clouds drift ×2 (autoscroll −24 px/s instead of −12; −16 in rain) and the extra particles.
- **Sway amplitude** everywhere scales with `wind_k = (0.5 + g_wind) / 0.85`: clear 1.0, rain 1.24, breeze 1.59 (GDD "sway ×1.6").
- **Travelling gusts:** shader-side on top of `g_wind`: phase = `fract(g_time·62/600 − x/1742)`, so a gust front crosses the screen at 180 px/s every 9.68 s, at amplitude 0.35.

### 3.5 UI tokens (constant at every time of day; 05 §0.4)

| Token | Hex | Use / checked contrast |
|---|---|---|
| `surface` (Cloud Dancer) | `#F0EEE9` | Glass and card base |
| `surface_hi` | `#FFFDF8` | Raised cards, text on `primary`/`leaf` (4.55:1 / 5.89:1) |
| `ink` | `#2A2838` | All text on glass and surfaces: 12.4:1 on surface, ≥ 8.9:1 on any glass |
| `ink_2` | `#5D596E` | Secondary text **on opaque surfaces only**: 5.8:1 |
| `primary` | `#4A6FD6` | Primary buttons (surface_hi text), selection |
| `coral` | `#FF9A7A` | Hearts, "new" dots, fills only (ink text 6.96:1) |
| `leaf` | `#256F5C` | Toggles on, owned/check, Garden accent (white text 5.99:1) |
| `gold` | `#FFCB57` | Dew currency (ink text 9.55:1) |
| `scrim` | `#1B1A2E` | α 0.24 behind sheets, α 0.40 behind modals |

**Derived UI tokens:** `primary_pressed` `#3A5DC2` (surface_hi text 5.86:1), `leaf_pressed` `#11614E`, `primary_tint` `#E8ECF6`, `leaf_tint` `#E5EBE4`, `coral_tint` `#FFECE1`, `gold_tint` `#FFF3D8`, `toggle_off_track` `#C4C2C5` with `toggle_off_border` = ink_2 (5.8:1, WCAG 1.4.11).

**Alphas** (`ui_alpha`):
- live glass tint 0.66, adaptive to 0.90 (§4.17);
- faux glass fill 0.84;
- Reduce Transparency fill 1.0;
- rim 0.6 → 0.1;
- inner bottom shadow 0.06;
- elevation shadows e1/e2/e3 = 0.06/0.12/0.16 in ink;
- divider ink @ 0.10;
- icon duotone secondary 0.40;
- glass backdrop saturation ×1.15 at LOD 3.5.

**Icon accents:** garden → leaf, album → coral, basket → gold, settings → primary, dew → gold, heart → coral, time → gold, weather → primary, watch → primary.

### 3.6 Creature palette (`cr_*` tokens named by `data/species.json`)

| Group | Tokens |
|---|---|
| Fur (L* ≥ 82) | `cr_cream` `#F2E3CD` · `cr_snow` `#F2F1EC` · `cr_oat` `#E6D5AD` · `cr_honey` `#F6DB96` · `cr_peach` `#F7CDB4` · `cr_mist` `#D5DEE8` · `cr_moss` `#D3E4C3` · `cr_sage` `#D2DBC6` · `cr_lilac` `#DCD1E6` |
| Night fur (dusk/night-only species) | `cr_dusk` `#A9A8D4` |
| Pattern / secondary (`fur_2`) | `cr_fern` `#A7CB93` · `cr_slate` `#9FA9BE` · `cr_cocoa` `#B39380` · `cr_blush` `#F2B7B0` |
| Accents (bobbles, buds, inner ears, freckles) | `cr_rose` `#EE9FA6` · `cr_berry` `#DA8CA8` · `cr_sun` `#FFD27A` · `cr_sky` `#A9D3EC` · `cr_leaf` `#86B97B` · `cr_glow` `#FFE3A3` (emissive at night) |
| Face | `cr_eye` `#3A2E3F` (never black) · `cr_eye_shine` `#FFFDF8` · `cr_cheek` `#EF9F9F` at α 0.50 |

**Resolved per species** (`palettes.json creatures.species_resolved`; `tip` = mix(fur, `#FFF8EE`, 0.45); pattern ink is darkened by L −0.05 when ΔE_OK to fur < 6):

| Species | Fur | Fur 2 | Belly | Accent | Tip | Pattern ink |
|---|---|---|---|---|---|---|
| puffmoss | cr_moss `#D3E4C3` | cr_fern `#A7CB93` | cr_cream `#F2E3CD` | cr_rose `#EE9FA6` | `#E7EDD6` | belly `#F2E3CD` |
| buttonbud | cr_cream | cr_oat | cr_snow | cr_sun | `#F8ECDC` | freckles in accent `#FFD27A` |
| pebblepaw | cr_mist | cr_slate | cr_snow | cr_sky | `#E8EAEB` | socks `#9FA9BE` |
| honeyhum | cr_honey | cr_cocoa | cr_cream | cr_sun | `#FAE8BF` | back stripes `#B39380` |
| fernwhisk | cr_sage | cr_fern | cr_cream | cr_leaf | `#E6E8D8` | cap `#A7CB93` |
| dandelfluff | cr_snow | cr_cream | cr_snow | cr_sky | `#F8F4ED` | (none) `#E1D3BD` |
| bellkin | cr_mist | cr_lilac (bell ears) | cr_snow | cr_berry | `#E8EAEB` | belly `#F2F1EC` |
| primpip | cr_peach | cr_blush | cr_cream | cr_rose | `#FBE0CE` | cheeks `#E1A7A0` |
| capling | cr_oat | cr_rose (cap) | cr_cream | cr_snow (spots) | `#F1E5CA` | cap_spots `#EE9FA6` |
| puddlewump | cr_mist | cr_sage | cr_snow | cr_sky | `#E8EAEB` | spots `#C2CBB6` |
| glowmote | cr_dusk | cr_slate | cr_lilac | cr_glow | `#CFCCE1` | (none) `#909AAE` |
| moonpuff | cr_lilac | cr_snow | cr_snow | cr_glow | `#ECE2EA` | cap `#F2F1EC` |

**Verified** (`tools/art/art_data.py check`, Machado 2009 severity 1.0 in linear RGB, OKLab):
- Every species, multiplied by ambient, against `ground_back_lit` and `ground_front_lit` in every phase it can appear and under every CVD simulation: worst ΔE_OK ≥ 9.6 and worst ΔL* ≥ 11.8 (thresholds 8 and 9). Worst case: primpip at day under protan.
- Eye contrast ≥ 5.6:1 (glowmote) and ≥ 8.7:1 for the rest.
- Cheek ΔE_OK ≥ 11.2.
- Fur chroma ≤ 0.13.

**Identity:**
- Species differ by ≥ 2 of (ear, tail, antenna, body class, pattern), so colour is never the only cue (WCAG 1.4.1).
- Three pairs differ by only one *part*, so pattern, size and eyes carry them: puffmoss/pebblepaw, puffmoss/moonpuff, honeyhum/dandelfluff (see §12).

**Variants** (for future colour/pattern variants, 04 §6.2): OKLCh hue ±12°, L ±0.03, pattern seed. Re-run `check` after adding any.

### 3.7 Flora palette (`fl_*` tokens named by `data/flora.json petal_token`)
Petal and leaf are tone-mask triples **[lit, shade, detail]**. Shade = Gurney rule: L −0.12, hue rotated 30 % (max 25°) toward 275°, chroma ×0.85.

| Token | Flower (form) | Petal lit / shade / detail | Leaf lit / shade / detail | Stem | Bud | Night emission |
|---|---|---|---|---|---|---|
| `fl_clover` | sweet_clover (globe) | `#F4C6D3` / `#C1A3BA` / `#FCE6EE` | `#6FAE74` / `#348971` / `#A2C89E` | `#68A678` | `#A1B895` | 0 |
| `fl_daisy` | button_daisy (daisy) | `#FBF3E4` / `#D6CAC1` / `#FFC86E` (centre) | `#72AA6E` / `#37866B` / `#A3C59A` | `#6BA373` | `#A2C497` | 0 |
| `fl_buttercup` | buttercup (cup) | `#FFD877` / `#E6A76D` / `#FFF3C4` (gloss) | `#74AB70` / `#3A876D` / `#A5C69B` | `#6DA475` | `#A7BB73` | 0 |
| `fl_forget_me_not` | forget_me_not (cluster) | `#BCD4F7` / `#9CACCA` / `#FFE08A` (eye) | `#7AAF7C` / `#468A74` / `#A9C8A3` | `#72A77F` | `#91BDA8` | 0 |
| `fl_bluebell` | bluebell (bell) | `#CBC7F3` / `#A3A3C7` / `#ECE9FC` (rim) | `#78AE80` / `#468977` / `#A7C8A6` | `#70A683` | `#96B8A9` | 0 |
| `fl_primrose` | primrose (primrose) | `#FBE6A6` / `#E0B88F` / `#F6C76E` (star) | `#86B886` / `#53937D` / `#B0CEAA` | `#7CAF88` | `#B0C891` | 0 |
| `fl_dandelion` | dandelion (puff) | `#F7F5EE` / `#D1CDC8` / `#CFD8C2` (seeds) | `#7FB077` / `#488C71` / `#ACC9A0` | `#76A87B` | `#A9C8A0` | 0 |
| `fl_moonbloom` | moonbloom (lily) | `#DCEAFA` / `#B9C2D0` / `#FFF1C2` (stamens) | `#7FB2A0` / `#5C8B8B` / `#ACCABB` | `#76A99E` | `#A0C5BF` | 0.25 petals, 0.5 stamens |

Verified:
- every petal sits ≥ 15.5 L* above its own leaf (accent rule, 05 §2.2);
- CVD ΔE_OK to its leaf ≥ 15.5;
- petal chroma ≤ 0.124.

**Grass is terrain:** `grass_root` → `grass_tip` per palette.

### 3.8 Materials (props, décor, gifts; tone-mask lit / shade / detail)

| Material | Lit | Shade | Detail | Used by |
|---|---|---|---|---|
| `stone_warm` | `#DCD3C8` | `#B7ACA6` | `#E9DFC9` (lichen) | sun stone, cairn pebbles |
| `stone_cool` | `#CFCAD8` | `#A7A5B1` | `#A8C98F` (moss cap) | spring rock, stream stones, cairn |
| `pebble_alt` | `#C3C9D8` | `#9FA3AF` | `#E4E0EA` | cairn, bank pebbles |
| `wood_bark` | `#B9957D` | `#936F69` | `#D7BCA6` (grain) | willow trunk, stump sides, lantern crook |
| `wood_cut` | `#E6CFB1` | `#C3A696` | `#C9A487` (rings) | stump top, chime bar, pinwheel stick |
| `wicker` | `#DDBB8E` | `#BB917B` | `#F0DDBA` | basket |
| `wood_painted` | `#E7B9A3` | `#BD9290` | `#FFF3E6` (emblem) | mailbox body |
| `roof_slate` | `#9FA9BE` | `#7D8495` | `#C9D0DE` | mailbox roof |
| `willow_leaf` | `#A6CC95` | `#70A88B` | `#D2E6C2` | willow canopy and fronds |
| `moss` | `#A8D08A` | `#6BAD87` | `#D9EBC0` | mounds, stone/stump moss |
| `toadstool_cap` | `#F1B9A6` | `#C59396` | `#FFF6EA` (spots) | toadstool seat |
| `toadstool_stem` | `#F4EBDD` | `#CFC2BB` | `#E6C9AE` (gills) | toadstool seat |
| `pinwheel_a` / `pinwheel_b` | `#9CC88A` / `#F6D58C` | `#63A484` / `#DAA77B` | `#D9EBC0` / `#FFF1C2` | leaf pinwheel blades |
| `lantern_jar` | `#DCEFF0` | `#B8C6CC` | `#F4FAFF` (gloss) | firefly lantern glass |
| `lantern_light` | `#FFE9C8` | `#DCBEAD` | `#FFC978` | lantern core (night emission 0.85) |
| `chime_ceramic` | `#D6E4EA` | `#B3BCC3` | `#F7D7E0` (paper strip) | wind chime tubes |
| `string` | `#CBBBA8` | `#A7948A` | `#E8DCCB` | chime strings, lantern wire |
| `soil` | `#A48978` | `#7F6560` | `#C7AE9A` | beds, seed mounds |
| `glow_mushroom` | `#FFE7AE` | `#E2BA97` | `#FFF6DA` | dressing (night emission 0.55) |
| `leaf_boat` | `#8FC07C` | `#539C7A` | `#D2E6C2` | leaf boat on the brook |

**FX colours** (`palettes.json fx`):
- firefly core `#FFE7A6` with an `accent` halo;
- dust = `glow`;
- pollen `#FFF1C2`;
- seed pappus `#FFFDF8`;
- falling petals = `fl_clover` lit;
- rain streak = mix(sky_horizon, `#FFFDF8`, 0.30) at α 0.25–0.40;
- ripples = mix(water_shallow, `#FFFDF8`, 0.5);
- sparkles `#FFFDF8`, hearts `coral`, "z" glyphs `#FFFDF8`.

### 3.9 Verification summary and rules for adding colours
- **TOD tokens:** all OKLCh C ≤ 0.163. The value ladder rises monotonically far → fg in every palette (dawn 1.24 → 4.45, day 1.34 → 4.24, golden 1.38 → 5.44, dusk 2.58 → 6.82, night 1.36 → 2.29). Night minimum L* is 6.2 (shadow).
- **UI:** all pairs in §3.5 pass AA. Semantic set under CVD: min ΔE_OK 9.9 (coral–gold, deutan) and 8.9 (primary–leaf, tritan, the documented exception).
- **V2 colour budget** (crude numpy mock of this layout, UI included, 50 % scale): dawn 99.9 %, day 89.0 %, golden 90.6 % of the area at HSV S ≤ 0.45 and V ≥ 0.45 (need ≥ 85 %). Day passes only because the near bank is lit meadow (not fg-dark), L5 stays ≤ 8 % and `sky_mid` sits at 42 % of the sky gradient. Dusk/night: see §11.3.
- **Adding a colour:** never hard-code a colour in a shader or SVG. Add a token to `palettes.json`, keep C_OK ≤ 0.163 (fur ≤ 0.13), keep ≥ 15 L* from the background it sits on (accents) or ≥ 9 L* (creatures on the meadow), run `python3 tools/art/art_data.py check`, and quote the result in the PR.

---

## 4. Shader inventory (Compatibility / GLES3; mobile-portable)

### 4.0 Rules for every shader
- **Language and units:**
  - `shader_type canvas_item` everywhere except particle process shaders.
  - Static typing; constants in `UPPER_SNAKE`; no magic colours (everything comes from globals or instance uniforms).
  - Units are px unless a name says `_dp` or `_bu`.
- **Precision:**
  - GLES3 defaults to `highp` [V `drivers/gles3/shader_gles3.cpp:219`].
  - Declare colour temporaries `mediump vec3`/`mediump float`.
  - **Never** do time, UV or position math in `mediump`.
- **Time:** all motion reads `g_time` (wrapped at 600 s by the TimeDriver = the `Clock` autoload, C4). Every loop frequency is `k/600` Hz with an integer `k` (table in `motion_tokens.json loops_k`); spatial loops tile so that speed × 600 s is a whole number of tiles (`loops_spatial`). **Never** read `TIME`.
- **Finish:** every gradient, halo, fog or glass shader ends with `finish()` (grain + TPDF ±1 LSB, C6).
- **Texture reads:** at most 2 per world fragment and 1 for glass (the mip LOD gives the blur).
- **Branching:** branches only on uniforms or instance uniforms (coherent per draw) or on inside/outside tests (coherent regions).
- **Instance uniforms:** max 16 per shader [V `servers/rendering/shader_language.h:351`, `MAX_INSTANCE_UNIFORM_INDICES = 16`]. Canvas instance uniforms keep batching [V `rasterizer_canvas_gles3.cpp:908`]. Prefer one shared `ShaderMaterial` per shader across all instances.
- **Full-screen alpha layers:** ≤ 3 (D8). Only the sky is opaque full width.
- **Opaque interiors:** large opaque polygons (hill bodies, meadow interior) use `render_mode blend_disabled` for their interior mesh; their soft edges are separate 3–6 px feather strips with vertex alpha. This lets tile-based GPUs with hidden-surface removal (Mali FPK, Apple, PowerVR) skip the covered sky fragments [J].

### 4.1 Global uniforms
The synthesis set is unchanged: `g_time, g_day, g_wind, g_motion, g_sun_dir, g_sky_top, g_sky_mid, g_sky_horizon, g_ambient, g_key, g_shadow`.

**This bible adds 26** (`vec2` and `color` are valid global types, `Color(...)` needs 4 floats [V 00 §3]). The Director must append this block to `[shader_globals]` (day defaults):

```ini
g_glow={"type":"color","value":Color(1.000, 0.961, 0.839, 1)}          ; sun/moon halo (palette glow)
g_far={"type":"color","value":Color(0.659, 0.831, 0.800, 1)}           ; L2 silhouette
g_mid={"type":"color","value":Color(0.490, 0.749, 0.569, 1)}           ; L3 silhouette
g_near={"type":"color","value":Color(0.310, 0.627, 0.435, 1)}          ; near ground
g_fg={"type":"color","value":Color(0.184, 0.482, 0.357, 1)}            ; L5 frame
g_accent={"type":"color","value":Color(1.000, 0.773, 0.431, 1)}        ; lantern pools, firefly halos
g_ground_back={"type":"color","value":Color(0.404, 0.686, 0.510, 1)}   ; meadow at the crest
g_ground_front={"type":"color","value":Color(0.310, 0.627, 0.435, 1)}  ; meadow at the brook
g_water_deep={"type":"color","value":Color(0.322, 0.600, 0.620, 1)}    ; brook centre
g_water_shallow={"type":"color","value":Color(0.741, 0.882, 0.957, 1)} ; brook edges / sky reflection
g_rim={"type":"float","value":0.35}                                    ; rim alpha
g_backlight={"type":"float","value":0.1}                               ; 0 front light .. 1 contre-jour
g_ground_light={"type":"float","value":0.18}                           ; key wash on the ground
g_shadow_alpha={"type":"float","value":0.3}                            ; contact shadow alpha
g_sun_pos={"type":"vec2","value":Vector2(780, 380)}                    ; canvas px of the sun
g_moon_pos={"type":"vec2","value":Vector2(820, 380)}                   ; canvas px of the moon
g_celestial={"type":"vec2","value":Vector2(1, 0)}                      ; x sun visibility, y moon visibility
g_halo={"type":"vec2","value":Vector2(1, 0.18)}                        ; x outer-halo scale, y outer-halo alpha
g_stars={"type":"float","value":0.0}                                   ; star visibility
g_lights={"type":"float","value":0.0}                                  ; local lights 0..1
g_shafts={"type":"float","value":0.7}                                  ; light-shaft strength
g_cloud={"type":"float","value":0.15}                                  ; cloud cover (world.json)
g_cloud_shadow={"type":"float","value":0.12}                           ; cloud-shadow darkening
g_rain={"type":"float","value":0.0}                                    ; rain 0..1 (weather crossfade)
g_mist={"type":"float","value":0.0}                                    ; low valley mist 0..1
g_world_offset={"type":"vec2","value":Vector2(0, 0)}                   ; (round((viewport_w - 1080)/2), viewport_h - 1920)
```

Writers:
- **PaletteDriver:** colours, scalars, celestial values.
- **WeatherDriver:** `g_wind`, `g_cloud`, `g_rain`.
- **TimeDriver:** `g_time`, `g_motion`.
- **Root layout:** `g_world_offset`, on `size_changed`.
- As built (ARCHITECTURE §7): the `TimeOfDay` autoload runs the PaletteDriver, WeatherDriver and celestial paths and is the only writer of those globals; the `Clock` autoload is the TimeDriver; `Main._layout()` passes the offset through `TimeOfDay.set_world_offset()`. `test_palette.gd` checks that every declared global has exactly one writer.

Material (non-global) uniform sets:
- `u_lamps[12]` (`vec4`: canvas x, y, radius px, intensity) + `u_lamp_count`, on meadow, grass and water.
- `u_stones[10]` (`vec3` x, y, r) + `u_stone_count` on water.
- `u_ripples[4]` (`vec4` x, y, start `g_time`, amplitude) on water.
- `u_shafts[5]` (`vec4` origin.xy, angle, length) + `u_shaft_w` (`vec2`) on light shafts and dust.

The LampRegistry, StoneRegistry and ShaftController set these only when they change.

### 4.2 Shared includes (`res://shaders/inc/`)

| File | Contents |
|---|---|
| `noise.gdshaderinc` | `h12(vec2)` (Hoskins hash, 05 §2.4) · `vnoise(vec2)` value noise with smoothstep interpolation · `vnoise_tiled(vec2 p, vec2 period)` (wraps hash cells, used for seamless flow loops) · `fbm2(vec2)` = 2 unrolled octaves (gain 0.5) · `fbm3(vec2)` |
| `finish.gdshaderinc` | `vec3 finish(vec3 c, vec2 uv_dp, vec2 frag, float grain)`, exactly the 05 §2.4 snippet with the grain amplitude as a parameter. Defaults: objects 0.020, terrain 0.016, sky 0.012, glass 0.010. `uv_dp` must be in dp of the object's own space (1 dp cells move with the object) |
| `world_light.gdshaderinc` | Declares the lighting globals. `const float SHADE_K = 1.85; const float AO_MAX = 0.22; const float KEY_TOP = 0.09;` |
| `lamps.gdshaderinc` | `uniform vec4 u_lamps[12]; uniform int u_lamp_count;` and `lamp_pool(p)` |
| `sdf.gdshaderinc` | `smin(a, b, k)` polynomial · `sd_squircle(p, r, n)` · `sd_ellipse(p, r)` (approx) · `sd_capsule(p, a, b, r)` · `sd_vesica(p, len, w)` (leaf) · `sd_arc(p, r, th, a0, a1)` · `sd_round_tri(p, h, b, rr)` · `rot2(a)` · `d_px(f) = f / length(vec2(dFdx(f), dFdy(f)))` (gradient-normalised distance) |

`world_light.gdshaderinc` functions:
- **`vec3 light_object(vec3 albedo, float up, float ao)`:**
  - `c = albedo * g_ambient.rgb`
  - `c = mix(c, c * g_shadow.rgb * SHADE_K, ao * AO_MAX)`
  - `c += g_key.rgb * KEY_TOP * up`
  - Hue-shifted shadows and lights come out of the tokens (05 §2.2).
- **`vec2 key_dir(vec2 p_canvas)`:** screen-space unit vector toward the light, `normalize(mix(g_sun_dir, normalize(body − p_canvas), 0.5·g_backlight))`. `body` is `g_sun_pos` when `g_celestial.x ≥ g_celestial.y`, otherwise `g_moon_pos`. Contre-jour rims therefore turn toward the sun.
- **`float cloud_shadow(vec2 p_design)`:**
  - `smoothstep(0.55, 0.75, fbm2((p_design + vec2(15·g_time, 0)) / 300))` with x tiled at 1800 px;
  - × `g_cloud_shadow · (0.4 + 0.6·g_cloud)`;
  - 15 px/s × 600 s = 5 tiles, so the loop is seamless.
- **`float wind_k()`:** `(0.5 + g_wind) / 0.85` — the sway amplitude factor used by grass, flora, fronds, ears and chimes (clear 1.0, breeze 1.59).
- **`vec3 sun_veil(vec2 p_canvas, float layer_k)`:**
  - `g_glow.rgb · g_halo.y · 0.6 · layer_k · g_celestial.x / (1 + (d / (1.4·r0))²)` with `r0 = 48·3.2·g_halo.x`;
  - `layer_k`: far 1.0, mid 0.6, meadow 0.25.

### 4.3 `world/sky.gdshader` (L0 + L1)
- **Node:** `SkyQuad` (Node2D, `_draw()` draws one rect from the viewport top (`−g_world_offset.y`) to `max(far crest)+12` ≈ 700, full viewport width) under `Parallax2D` scroll 0. Material uniform `sky_tex: GradientTexture1D` (width 256, OKLab `Gradient` of sky_top / sky_mid / sky_horizon at 0 / 0.42 / 1.0, rebuilt by the PaletteDriver when those colours change).
- **Render mode:** `blend_disabled, unshaded`.
- **Globals:** `g_time, g_glow, g_sun_pos, g_moon_pos, g_celestial, g_halo, g_stars, g_cloud, g_rain, g_world_offset, g_motion, g_sky_horizon`.
- **Uniforms:** `horizon_y = 690`, `haze_center = 700`, `haze_sigma = 45`, `haze_amp = 0.18`, `sun_disc_px = 96`, `moon_disc_px = 84`, `moon_color`, `moon_maria`, `star_color` (from `palettes.tod.celestial`), `star_cell_px = 54`, `star_density = 0.18`, `star_k_range = (120, 300)`.

Algorithm:
1. **Gradient:** `t = (y − top_visible) / (horizon_y − top_visible)`; `c = texture(sky_tex, vec2(t, 0.5)).rgb` (exact OKLab path, no shader cbrt).
2. **Haze band:** `c = mix(c, mix(g_sky_horizon, g_glow, 0.25), haze_amp·exp(−((y − 700)/45)²))`.
3. **Sun** (× `g_celestial.x`):
   - disc with 1.5 px AA edge and 3 px limb darkening (−4 %);
   - inner halo `0.6·exp(−(r/(1.5R))²)`;
   - outer halo `g_halo.y / (1 + (r/r0)²)` with `r0 = 3.2·R·g_halo.x`;
   - added, clamped to 1.
4. **Moon** (× `g_celestial.y`): disc `moon_color` with maria (`vnoise(p/18) > 0.62` → mix `moon_maria` 0.5); inner halo 0.35; outer halo × 0.6.
5. **Stars:**
   - one candidate per 54 px cell, kept if `h12(cell) < 0.18`, jittered inside the cell, radius 1.2–2.6 px (hash);
   - twinkle `0.75 + 0.25·sin(TAU·k/600·g_time + phase)` with k from the hash in [120, 300];
   - × `g_stars · (1 − 0.9·g_cloud) · smoothstep(horizon_y, horizon_y − 200, y)`.
6. `finish(c, uv_dp, FRAGCOORD.xy, 0.012)`.

- **Cost:** 1 texture read + ≈ 90 ALU over ≈ 0.36 of the screen (0.55 on 20:9). Opaque, so no blending.
- **Acceptance:**
  - no visible band at 200 % zoom in any palette (night is the hardest);
  - halos have no rings;
  - the disc edge is clean;
  - star twinkle ≤ 0.5 Hz and never on/off;
  - on 1080×2400 the gradient still spans top → horizon (no flat band at the top).

### 4.4 `world/silhouette.gdshader` (L2 far, L3 mid)
- **Node:** `Polygon2D` (D7) built once by `SilhouetteBuilder` from the §2.4 recipes (vertex every 6 px for far, 4 px for mid; x from −400 to 1480 for wide screens):
  - interior polygon (`blend_disabled` material variant via uniform `opaque_core = true`);
  - plus a feather strip (6 px far, 3 px mid) whose outer row has vertex alpha 0.
  - Polygon UV.y = 0 at the crest, 1 at the body bottom.
- **Render mode:** `blend_mix, unshaded` (core: `blend_disabled`).
- **Globals:** `g_far` or `g_mid` (by `layer`), `g_sky_horizon, g_glow, g_key, g_sun_pos, g_celestial, g_halo, g_backlight, g_rim, g_world_offset`.
- **Uniforms:**
  - `layer` (0 far, 1 mid);
  - `fog_color_mix` (far: target `far_haze`; mid: `mid_haze`, computed as `mix(layer, g_sky_horizon, k)` with k 0.30 / 0.15);
  - `veil_k` (1.0 / 0.6);
  - `crest_rim_px` (3).

Algorithm:
1. `c = mix(layer_color, mix(layer_color, g_sky_horizon, k), smoothstep(0, 1, UV.y))` — valley fog.
2. Add `key·g_rim·g_backlight·0.25·(1 − smoothstep(0, crest_rim_px, dist_to_crest))` (crest glow at dawn and golden; `dist_to_crest` = UV.y·body_height).
3. `c += sun_veil(p, veil_k)`.
4. `finish(c, …, 0.016)`.
5. Pre-blur look: the feather does the work (05 asks for 1–2 dp). Do not sample textures.

- **Cost:** ≈ 30 ALU; ≈ 0.06 (far) + 0.10 (mid) of the screen visible.
- **Fractal target (V4):**
  - Measured [V, `fbm`/`canopy` scripts]: the far ridge alone D ≈ 1.05–1.15; the mid ridge with canopy bumps ≈ 1.15; far + mid + crest + willow ≈ 1.22; **+ ≥ 260 grass tufts + 3 clouds ≈ 1.30** (box sizes 4–128 px, 1080×1920 edge map).
  - So V4 passes only with the full scene and ≥ 260 tufts (§4.6). Keep the ridges themselves soft (cozy); detail lives in the canopy, the grass and the willow.
- **Acceptance:** the ladder holds (contrast vs horizon rises far → mid → meadow); the crest glow is visible at golden hour but under 3 px; no polygon stair-stepping at 200 %.

### 4.5 `world/meadow.gdshader` (L4 ground)
- **Node:** `Polygon2D` meadow from the crest line down to y 1940 (opaque core + 3 px feather at the crest), UV in design px (`uv_design`).
- **Globals:** `g_ground_back, g_ground_front, g_key, g_shadow, g_ground_light, g_cloud_shadow, g_cloud, g_rain, g_sky_mid, g_sun_pos, g_celestial, g_halo, g_glow, g_lights, g_accent, g_time, g_world_offset`.
- **Uniforms:**
  - lamps (`lamps.gdshaderinc`);
  - `path_tex` (R8 mask, 270×480, painted once at build from the §2.5 path polyline with blur 12 px);
  - `path_color` (from `ground_path`);
  - `dapple_k` = 0.06;
  - `bank_y` (design y of the far bank per x as a `Curve`-baked 1D texture, or the brook polyline evaluated in the vertex stage).

Algorithm:
1. `t = smoothstep(760, 1500, y)`.
2. `c = mix(mix(g_ground_back, g_key, g_ground_light), mix(g_ground_front, g_key, g_ground_light), t)`.
3. **Path:** `c = mix(c, path_color, 0.55·path_mask)`.
4. **Dapple:** `vnoise(p/90)` ±6 % brightness, finer by `vnoise(p/23)` ±2 % (felt texture).
5. **Cloud shadow:** `c = mix(c, c·g_shadow·SHADE_K, cloud_shadow(p))`.
6. **Near bank** (y > bank): mix 10 % toward `g_shadow`.
7. **Wet sheen:** `+ g_rain·0.15·(g_sky_mid − c)·(1 − t·0.5)`.
8. **Lamp pools:** `Σ g_accent·intensity·(0.25 + 0.15·breath)·1/(1 + (d/r)²)·(1 − smoothstep(r·1.6, r·2.0, d))` with `breath = sin(TAU·181/600·g_time + i)` (±5 %), × `g_lights`.
9. `c += sun_veil(p, 0.25)`.
10. **Mist:** `c = mix(c, mix(g_sky_horizon, g_glow, 0.2), g_mist·band)` where `band` = two soft horizontal bands (crest 760–880 and over the brook 1400–1540, Gaussian σ 40 px) broken by `vnoise` drifting at 6 px/s (tile 1800 px, k 2). Also drawn by the water shader.
11. `finish(c, …, 0.016)`.

- **Cost:** 1 texture read + ≈ 70 ALU + 12 × 8 for lamps (only `u_lamp_count` iterations; the loop bound is a uniform), over ≈ 0.61 of the screen. This is the largest fragment cost after the sky: keep it opaque.
- **Acceptance:**
  - day V2 ≥ 85 % (§3.9);
  - the path is readable but soft;
  - cloud shadows drift slowly with no visible edge;
  - lamp pools never clip to white;
  - rain sheen is subtle (≤ 15 %).

### 4.6 `world/grass.gdshader` (meadow tufts)
- **Node:** 4 `MultiMeshInstance2D` depth bands inside `L4/YSort` (= the y-sorted `World/Ground/Play` node of `scenes/main.tscn`), each `origin.y` at its band centre (crest–1000, 1000–1200, 1200–1380, 1380–1500), so creatures sort against grass to ±90 px.
- **Mesh:** a tuft = `ArrayMesh` strip, 3 blades × 4 segments (UV.y 1 at the root → 0 at the tip; 26 verts).
- **Counts:** ≥ 260 tufts in total (V4), Poisson-disk placed (Bridson, r = 22 px × depth scale), 2.5× denser at the meadow edges and around props than in the open (rest areas). None inside bed ellipses or within 60 px of the path centre.
- **Per instance:** transform with scale = depth scale × (0.85–1.15) and rotation ±4°; `use_colors = true` (rgb = tint t, phase, type); `use_custom_data = true` (x = sway k index, y = height 18–36 px, z = gust offset, w = lean). INSTANCE_CUSTOM is half-float in GLES3 canvas [V `drivers/gles3/shaders/canvas.glsl:192`]; 11-bit precision is fine for these.
- **Globals:** `g_time, g_wind, g_motion, g_near, g_mid, g_key, g_shadow, g_cloud_shadow, g_lights, g_accent`, lamps. `grass_root = mix(g_near, g_shadow, 0.25)` and `grass_tip = mix(g_mid, g_key, 0.25)` are mixed in sRGB in the shader. That is within ΔE_OK 1.1 of the OKLab tokens in every palette [V], so no extra globals are needed.

Algorithm:
- **Vertex:**
  - `h = 1 − UV.y`;
  - `gust = smoothstep(0.0, 0.25, ph)·(1 − smoothstep(0.25, 0.6, ph))` with `ph = fract(g_time·62/600 − world_x/1742)`;
  - `VERTEX.x += (sin(TAU·k/600·g_time + phase) + 0.35·sin(2.13·…+1.7))·amp·wind_k()·(1 + 0.35·gust)·g_motion·h²`, with amp 4–8 dp at the tip and k from `loops_k.grass_sway`.
- **Fragment:**
  - `c = mix(grass_root, grass_tip, h)` with tint variation ±L 0.03;
  - blade alpha from the atlas stamp `grass_tuft_*` (3 variants);
  - cloud shadow; lamp pools ×0.6;
  - `finish(…, 0.016)`.
- **Cost:** ≈ 0.06 of the screen, 4 draw calls, ≈ 40 ALU.
- **Acceptance:** gust fronts visibly travel left → right every ≈ 9.7 s; no two neighbouring tufts in phase; tips never cross the creature faces in front of them.

### 4.7 `world/water.gdshader` (the brook)
- **Node:** `MeshInstance2D` triangle strip along the Catmull-Rom centre line (one segment per 12 px of arc length):
  - UV.x = arc length px;
  - UV.y = 0 (far edge) → 1 (near edge);
  - ribbon height 69 px plus a 10 px bank on each side;
  - drawn after the meadow and before `YSort`.
- **Globals:** `g_time, g_water_deep, g_water_shallow, g_sky_mid, g_sky_horizon, g_glow, g_key, g_celestial, g_sun_pos, g_moon_pos, g_lights, g_accent, g_rain, g_wind, g_motion`.
- **Uniforms:** `u_lamps`, `u_stones`, `u_ripples`, `flow_dir = −1` (right → left), `glint_cells = 16`, `edge_foam = 0.35`. The bank colour is computed in-shader as `water_bank = mix(g_near, g_shadow, 0.30)` (sRGB).

Algorithm:
1. **Depth across:** `w = 1 − abs(UV.y·2 − 1)`; `c = mix(g_water_shallow, g_water_deep, smoothstep(0.1, 0.9, w)·0.75)`.
2. **Sky reflection:** mix 35 % toward `g_sky_mid` → `g_sky_horizon` (screen-y based: water mirrors the band just above the horizon).
3. **Flow:** two `vnoise_tiled` layers scrolled along UV.x at 54 px/s (tile 540) and 30 px/s (tile 360) in the flow direction, with scale (1/90, 1/14) (elongated streaks). They brighten ±6 % and bend the reflection ±2 px.
4. **Glints:**
   - 16 glint cells along the brook (one per 70 px of length);
   - each cell flashes a soft 1–2 px sparkle once per period 600/k, k ∈ [76, 124] (4.8–7.9 s), fading in and out over 0.4 s, positioned by the flow noise;
   - this gives ≈ 2.6 onsets per second across the whole brook (WCAG 2.3.1 ≤ 3);
   - brightness × `(g_celestial.x·(0.3 + 0.7·g_backlight) + g_celestial.y·0.5)` × `g_glow`.
5. **Edges:** foam line `edge_foam·(1 − smoothstep(0, 0.12, min(UV.y, 1 − UV.y)))` × noise; banks darken toward `water_bank`.
6. **Stones** (`u_stones`): a riffle downstream (to the left) of each stone: foam wedge 40 px, noise-broken.
7. **Lamp reflections** (`u_lamps`): a vertical streak `exp(−((x − lamp_x)/12)²)` × flow-noise breakup × `g_accent` × `g_lights` × 0.5.
8. **Ripples** (`u_ripples`, tap or leaf boat): ring `radius = 108·(1 − (1 − u)²)` with `u = age/0.38 s` (GDD: 36 dp in 380 ms; eased out, never linear), flattened ×0.35 in y, width 3 px, `α = 0.35·(1 − u)`. A slower, fainter wake (u over 1.2 s, α 0.15) trails each leaf boat.
9. **Rain rings:** cells of 48 px (≈ 32 over the brook), each with a seeded start and k = 76 — a ring every 7.9 s per cell, ≈ 4 per second in total, × `g_rain`. Rings are low-contrast (α ≤ 0.3).
10. `finish(…, 0.014)`.

- **Cost:** ≈ 0.04 of the screen; 2 noise layers + 12 lamps + 10 stones ≈ 150 ALU (small area).
- **Acceptance:**
  - reads as flowing water in a still frame (streaks aligned with the flow);
  - loops seamlessly at the 600 s wrap;
  - glints never strobe;
  - lantern reflections line up with their lanterns within 2 px.

### 4.8 `world/cloud.gdshader` (L2 clouds)
- **Node:** 3 cloud quads, 600×220 px each (in L2, autoscroll −12 px/s (4 dp/s), `repeat_size` 1800). Shape = 5-circle union SDF plus `fbm2` billow at 0.08 amplitude.
- **Algorithm:**
  - `c = mix(cloud_shade, cloud_lit, smoothstep(−0.2, 0.6, local_up + 0.4·key_dir.y))` (lit from the sun side);
  - soft edge 8 px;
  - α 0.85, × `(0.6 + 0.4·g_cloud)`;
  - in rain, 2 extra rain clouds fade in with `g_rain`;
  - `sun_veil`; `finish(…, 0.012)`.
- **Cost:** ≈ 0.10 of the screen at most.
- **Acceptance:** clouds read as lit volumes, never as flat ovals; they drift continuously (no wrap pop, thanks to `repeat_size`).

### 4.9 `props/prop_tone.gdshader` (props, décor, gifts, leaf boat, leaf umbrella)
- **Node:** `Sprite2D` per piece (texture = SVG raster from the `texture` importer at `svg/scale = 1.0`, `compress/mode = Lossless`, mipmaps on, `fix_alpha_border` on, filter Linear Mipmap; D7, C11). Origin at the ground contact point; y-sorted. One shared `ShaderMaterial`.
- **Tone mask:**
  - SVG paints pure **R = lit**, **G = shade**, **B = detail**; channel gradients only between pure channels, so R+G+B = 1 inside;
  - alpha = coverage;
  - masks must never be VRAM-compressed (05 §4).
- **Instance uniforms:**
  - `i_lit, i_shade, i_detail` (`vec4`, rgb from `materials`, a = detail emission 0..1);
  - `i_sway` (x amp px, y k, z pivot y in UV, w phase);
  - `i_fx` (x tap pulse 0..1, y squash, z lamp intensity, w cloud shadow).
  - Multi-material props (stump: bark + cut top + moss) use **2 sprites** (back/front parts) or a second mask texture. Never more than 2 materials per sprite.

Algorithm:
1. `m = texture(TEXTURE, UV)`; `o = 1 − (m.r + m.g + m.b)` (colour-line weight); `alb = m.r·lit + m.g·shade + m.b·detail + o·shade·0.72`.
2. `c = light_object(alb, up = 1 − UV.y, ao = 1 − smoothstep(0.80, 1.0, UV.y))` — bottom 20 % darkened 15–25 %.
3. Rim: `rim = m.a·(1 − texture(TEXTURE, UV + key_dir·1.5·TEXTURE_PIXEL_SIZE).a)` (inside, with empty space toward the light), × `g_key·g_rim·0.6`. One extra texture read; skip it for pieces < 40 px.
4. Emission: `c = mix(c, detail·1.1, i_lit.a·g_lights)` for the lantern core and glow mushrooms.
5. Cloud shadow; lamp fill `+ g_accent·0.12·i_fx.z`.
6. `finish(…, 0.020)`; `COLOR = vec4(c, m.a·COLOR.a)`.
7. Vertex: optional sway (shear above the pivot), for the chime, pinwheel stick, lantern jar and reeds.

- **Outline policy:** interactive pieces (basket, mailbox, chime branch, lantern jar) get a 2 dp **colour line** ≈ ΔL* −30 from the fill, hue toward the shadow tint (05 §0.1). It is authored in the SVG as a 6 px stroke painted **mask-black** (R = G = B = 0, α = 1), which the shader turns into `shade·0.72`. The line is never drawn as screen black. Beds get their line from the soil mound stamp.
- **Cost:** 1–2 reads, ≈ 40 ALU; ≈ 0.14 of the screen in total (the willow is 0.10).
- **Acceptance:** every prop recolours correctly across the 5 palettes with no new art; edges show no channel fringes (lossless import); shadow sides are hue-shifted, never grey.

### 4.10 `flora/flora_bed.gdshader` (beds)
- **Node:** one `MeshInstance2D` per bed (5), with an `ArrayMesh` rebuilt by `FloraBuilder` (§6.2).
- **Vertex COLOR encodes data:** r = palette row/7, g = part/4 (0 stem, 1 leaf, 2 petal, 3 bud, 4 centre), b = sway weight h (0 root → 1 tip), a = phase. After decoding, the shader sets `COLOR = vec4(1)`.
- **Colours:** `texelFetch(flora_lut, ivec2(slot, row), 0)` in `vertex()`, passed as `varying flat` lit/shade/detail.
  - `flora_lut` is an RGBA8 `ImageTexture` of 8 columns × 10 rows built at boot from `palettes.json flora.flowers`.
  - Rows 0–7 follow `garden_order`; rows 8–9 are dynamic (unfurl colour lerp, §6.2). Columns are petal lit/shade/detail, leaf lit/shade/detail, stem, bud.
- **Texture:** `flora_atlas` (tone-mask stamps, §6.1).
- **Globals:** lighting set + `g_time, g_wind, g_motion, g_lights, g_cloud_shadow`.

Algorithm:
- **Vertex sway:** as grass, with amp 12–24 px at the tip and k from `loops_k.flower_sway`.
- **Fragment:** tone-mask compose → `light_object` → night emission (`fl_moonbloom` petals 0.25 and stamens 0.5 × `g_lights`) → `finish`.

- **Cost:** 5 draw calls, ≈ 0.03 of the screen.
- **Acceptance:** flowers sway with the same gusts as the grass; petals stay attached to stems at full sway (same function at the attach point); there is no z-fighting inside a bed (stems sorted by y at build).

### 4.11 `creature/mossling_fur.gdshader`
Fully specified in §5.5–5.7.
- **Render mode:** `blend_premul_alpha, unshaded`, so additive bulb halos can be emitted with α = 0.
- **Feasibility verified** on 4.7.2 `opengl3_es` (llvmpipe): compiles with 16 instance uniforms, globals, `dFdx`/`fwidth`; two runs gave AE = 0 [V, `docs/art/reference/`].
- **Cost:** ≈ 60 ALU (outside the silhouette, early out) to ≈ 250 ALU (fur and face pixels); a quad ≈ 3.6·S² px. With ≤ 5 creatures present (`economy.max_present`) that is ≈ 0.10–0.19 of the screen.

### 4.12 `fx/contact_shadow.gdshader`
- **Node:** `Shadow` child of every creature and of standing props, drawn before the body; shared material.
- **Instance uniforms:**
  - `i_shadow` (x half-width px, y half-height px, z length factor, w alpha mul);
  - `i_dir` (x, y: screen direction away from the light).
- **Algorithm:**
  1. Contact core ellipse at the feet: half-width 0.55·W·(1/squash), half-height 0.13·W, edge softness 18 px.
  2. Cast shadow ellipse offset by `vec2(−L.x·0.8, 0.10 + 0.30·g_backlight)·len·H/2`:
     - `len = clamp(0.35/elev, 0.35, 2.5)`, elongated along the offset;
     - edge softness 18 → 36 px with length;
     - α × 0.6.
  3. `a = max(core, cast)` × `g_shadow_alpha` × `(1 − 0.6·hop_height_norm)` × `(1 − 0.4·g_rain)`.
  4. `COLOR = vec4(g_shadow.rgb, a)` — tinted, never black.
  5. TPDF dither.
- **Acceptance:** shadow direction agrees with `g_sun_dir` for every object in a frame (rubric #5); shadows shrink and fade during hops.

### 4.13 `fx/halo_add.gdshader`
- **Render mode:** `blend_add`.
- **Uses:** lantern head halo (r0 18 px, quad 108 px), glow-mushroom halos (r0 10 px), basket glint, bulb halos for props, "debut" spotlight (r0 120 px, α 0.18).
- **Formula:** `c = i_color.rgb·i_color.a·1/(1 + (r/r0)²)·(1 − smoothstep(0.7, 1.0, r/r_quad))` × breath (k 181, ±5 %) × `g_lights` (for night-only uses), then TPDF.
- **Acceptance:** no visible quad edge; ≤ 3 brightness onsets per second scene-wide.

### 4.14 `fx/light_shaft.gdshader` (L4 `Air`)
- **Node:** 3–5 additive trapezoid quads (`blend_add`) from `ShaftController`, recomputed when the sun moves more than 20 px.

| Time | Shafts | Origin | Shape |
|---|---|---|---|
| Day | 3 | Upper right (sun side) | Slanting down-left; width 90–160 → 200–260 px over 1000 px |
| Golden | 4 | Radiating from the sun (560, 640), fanning ±25° toward the viewer | Width 60 → 260 px over 900 px |
| Dawn | 3 | Through the willow canopy | Modulated across their width by `vnoise` (leaf gaps) |

- **Algorithm:**
  - α = `(0.05–0.12)·g_shafts·(1 − 0.8·g_cloud)·(1 − g_rain)`;
  - fades over the first 15 % and the last 40 % of the length; soft sides (smoothstep over 30 % of the width);
  - sway ±2° about the origin with k ∈ [50, 72];
  - colour `g_glow`; `finish`.
- **Acceptance:** shafts read as air, never as stripes; dust motes are visible only inside them.

### 4.15 Particles (`fx/wander.gdshader` process + `fx/particle_draw.gdshader`)
- **Process** (`shader_type particles`): emission from a uniform rect or from `u_points` (lantern positions for fireflies). `CUSTOM` holds k (cycle), phase, size, seed, from `INDEX`/`RANDOM_SEED` [V built-ins `shader_types.cpp:376-422`].
  - `VELOCITY` = drift (wind, ×`g_wind`) + 2–3 seeded sines (no turbulence, 05 §2.6).
  - Age-based fade-in ≥ 300 ms and fade-out over the last 20 % of life (no pop-in, V5).
- **Draw** (`canvas_item`, `blend_add` or `blend_mix` by system), with one `kind` uniform: 0 soft dot, 1 firefly (core + halo + pulse), 2 rain streak, 3 ring, 4 atlas stamp (seed, petal).
- **Rules:** `fixed_fps = 30`; `preprocess` = one lifetime; size `amount` for the peak and fade with `amount_ratio` (no GPU saving, [V GPUParticles2D.xml:64-70]). Use `CPUParticles2D` on Adreno 3xx (GPU particles disabled by the driver workaround, 01).

### 4.16 `world/fg_frame.gdshader` (L5)
- **Node:** `Sprite2D` tone masks for the reeds, clover and bough (`willow_leaf`/`moss` materials).
- **Algorithm:**
  - sample at `textureLod(TEXTURE, UV, 2.0)` — the 2–4 dp blur comes from the mip;
  - multiply toward `g_fg` (`c = mix(alb·g_ambient, g_fg, 0.55)`), which gives ΔL* ≈ −15;
  - rim from `key_dir` at 0.3;
  - sway via a vertex shear (k from `flower_sway`), amplitude 6 px;
  - `finish`.
- **Acceptance:** ≤ 8 % of the screen area; never overlaps a Z3 target; reads as out-of-focus foreground.

### 4.17 `ui/glass_faux.gdshader` and `ui/glass_live.gdshader` (C7)
- **Faux glass** (HUD chips, dock, cards over the world, toasts): no screen read.
  - `StyleBoxFlat`: `bg_color` = surface @ 0.84, corner radii from tokens, `corner_detail` 16, `anti_aliasing` on, shadow e2 (ink @ 0.12, size 48, offset (0, 18)). The shadow is drawn even with a transparent fill [V `scene/resources/style_box_flat.cpp:527-544`].
  - Plus a full-rect `ColorRect` overlay (`mouse_filter` IGNORE) with `glass_faux.gdshader`: rounded-box SDF (same radius); 1 dp inner rim, white α 0.6 at the top-left fading to 0.1 at the bottom-right; 2 dp inner bottom shadow α 0.06; `finish(…, 0.010)`.
- **Live glass** (exactly one surface at a time: the open sheet; never on the low tier):
  - In the UI `CanvasLayer`, order is `BackBufferCopy` (`copy_mode = COPY_MODE_RECT`, rect = the sheet rect, moved with the sheet) → `Scrim` → `Sheet`. The copy happens at the BBC item, so the glass sees the world **without** the scrim. After a back-buffer copy the screen texture makes no further copies, and the first mipmap user generates the rect's mip chain [V `rasterizer_canvas_gles3.cpp:414-433, 519-536`].
  - Shader: `uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;`
    - `b = textureLod(screen_tex, SCREEN_UV, 3.5).rgb`;
    - saturation ×1.15;
    - `a = mix(0.90, 0.66, smoothstep(0.05, 0.45, luma(b)))` (adaptive, §3.5);
    - `c = mix(b, surface, a)`;
    - same rim and inner shadow;
    - `finish(…, 0.010)`;
    - α = rounded-box coverage (1 px AA). The output is opaque inside, so it hides its own e3 shadow fill.
  - The sheet panel's `StyleBoxFlat` draws only the e3 shadow (ink @ 0.16, size 72, offset (0, 24)).
- **Reduce Transparency:** fill 1.0 everywhere, BBC `copy_mode = DISABLED`.
- **Governor:** if sheet-open frames cost > 2 ms over the idle baseline (frame-delta statistics), switch the sheet to faux.
- **Acceptance:** ink ≥ 4.5:1 over the worst backdrop (verified ≥ 8.9:1); never glass on glass; idle frames do 0 screen reads.

### 4.18 `ui/ring_fill.gdshader`
Arc SDF with round caps, used for:
- the long-press radial fill (starts at 150 ms, full at 450 ms, 6 dp stroke, `primary` at 0.9, radius 48 dp around the touch point);
- the dock Basket fill ring (count/24, `gold` on `gold_tint`, 3 dp).

### 4.19 Warm-up, draw calls and fill budget
- **Warm-up (C8):** draw once, behind the opaque splash, inside the viewport at α ≥ 0.01:
  - sky, silhouette (core and feather variants), meadow, grass, water, cloud, prop_tone, flora_bed, mossling_fur, contact_shadow, halo_add, light_shaft;
  - every GPUParticles2D process material and its draw material;
  - fg_frame, glass_faux, glass_live (with a BBC, to also warm the mip path), ring_fill;
  - the MSDF numeral font.

**Budget at H = 1920** (fraction of screen = fragments shaded / screen):

| Item | Fill | Draw calls |
|---|---|---|
| Sky (opaque) | 0.36 | 1 |
| Far + mid (cores opaque) + feathers | 0.16 | 4 |
| Clouds | ≤ 0.10 | 3 |
| Meadow (core opaque) | 0.61 | 2 |
| Brook | 0.04 | 1 |
| Grass (4 bands) | 0.06 | 4 |
| Props + décor (willow 0.10) | 0.17 | ≈ 20 |
| Beds | 0.03 | 5 |
| Creatures (≤ 5) + shadows | 0.19 | ≤ 10 |
| Shafts (day/golden only) | 0.08 | 4 |
| Particles | 0.02 | ≤ 3 |
| L5 frame | 0.08 | 3 |
| HUD + dock (faux glass + plates) | 0.16 | ≈ 14 |
| **Total** | **≈ 2.0** | **≈ 74** |

- **Read:** draw calls fit the ≤ 100 budget. Content fill is ≈ 1.9–2.0, plus the Compatibility root-viewport blit (≈ 1.0, 02 §4.2), giving **≈ 2.9–3.0 against the 2.5× low-tier budget**.
- **Mitigation:**
  - opaque cores (§4.0) are expected to recover 0.3–0.5 on HSR GPUs [J, to measure];
  - governor tier 1 drops shafts, L5, clouds 3 → 1, grass ×0.6, and creature fibre detail.
- This is risk **F1** in §12 and must be measured on the reference devices.

---

## 5. Creature rig — the parametric mossling

### 5.1 Approach (decision A2) and why
**One SDF quad per creature** renders body, ears, tail, antennae, pattern, belly and face in a single fragment shader (`mossling_fur.gdshader`), with all per-creature parameters in **16 instance uniforms**. A separate tiny quad draws the contact shadow, and pooled sprites draw FX (z's, hearts).

| Option | Verdict | Reason |
|---|---|---|
| **A. Single-shader SDF quad (chosen)** | ✔ | Parts merge by smooth-union into **one** felt silhouette, so the fuzz fringe and rim run continuously over ear joins (the look that sells "needle felt"). 1 draw call per creature (+1 shadow); instances share one material. Crisp at any scale and under squash (C11). Rim from `g_sun_dir`/backlight per pixel. Every species is data (`creature_rig.json`) |
| B. Node per part (body quad + ear/tail sprites + face sprite) | ✘ | Double fuzz rims and seams at every joint; 5–8 draw calls per creature; shading mismatches between parts |
| C. Layered SVG rasters | Fallback only (R1) | Blurs under squash, no per-pixel rim, violates C11. Kept as the R1 fallback behind the same node API |
| D. Skeleton2D + Polygon2D deformation | ✘ | `SkeletonModification2D` is experimental (01 §4.3); no fur |

**Evidence:** `docs/art/reference/fur_spike.gdshader` renders the target look at golden hour on 4.7.2 `opengl3_es`. It confirms 16 instance uniforms, `blend_premul_alpha`, globals and `dFdx`/`fwidth`, and was deterministic across two runs (AE 0). Start the production shader from it.

### 5.2 Node structure
```
Mossling (Node2D, scripts/creature/mossling.gd)       origin = feet on the ground; child of World/Ground/Play/Creatures (or L4/BehindCrest)
├─ Shadow   (Node2D + contact_shadow material)         drawn first; stays on the ground during hops
├─ Body     (SdfQuad: Node2D, _draw() → draw_texture_rect(WHITE_4x4, quad_rect))
│            material = shared mossling_fur ShaderMaterial; position.y = −hop_height
├─ Held     (Node2D) LeafUmbrella (Sprite2D prop_tone), visible only in rain away from shelter
└─ Fx       (Node2D) pooled: Zzz ×2, Heart ×3, Sparkle burst (halo_add / particle stamps)
```
- **Quad rect** (local px, feet at 0): x ∈ [−(0.5·w_h + 0.45)·S, +(0.5·w_h + 0.45)·S], y ∈ [−(1.0 + top_extent + 0.12)·S, +0.10·S].
  - `top_extent` = max(ear extent, antenna extent): round 0.17, tuft 0.22, pointed_soft 0.26, bell 0.10, leaf 0.30, nub 0.07; antenna sprout 0.33, double_bobble 0.37, fern_curl 0.30, dandelion_puff 0.55, glow_bobble 0.42.
  - Compute it once per species and `queue_redraw()` only when it changes.
- **Size:** S = body height = 150 px × `species.rig.size`. `Mossling.scale = depth_scale(feet_y)` (§2.4), so fibres, grain and rim thin naturally with distance.
- **Shader coordinates:** a `varying vec2 v_local = VERTEX` from `vertex()` (local, pre-transform), then `p = vec2(v_local.x, −v_local.y) / S` in **bu** (y up, feet at the origin). The quad size never has to be passed in.

### 5.3 Proportions (baby schema, 05 §0.1; 04 §3.2)
- **Body:**
  - one mass that is head and body at once (a mochi);
  - squircle with half-size (0.5·w_h, 0.5) centred at (0, 0.5), w_h 0.85–1.30;
  - exponent n 2.2–3.0 (`art_overrides`), plus +1.2 on the lower half (flat-bottomed "sitting" mochi).
- **Eyes:**
  - centres at 0.58 of body height from the top (y = 0.42 bu: lower half ✔);
  - spacing 0.40·w_h;
  - eye width **0.20·w_h** (≥ 18 % ✔), height 1.18× width.
- **Face:** cheeks sit 0.07 bu outside and 0.12 bu below each eye; the mouth sits 0.075 bu below the eye line. The face stays small and low, with a high "forehead".
- **Big–medium–small:** the body is ≈ 60 % of the silhouette, ears/tail ≈ 30 %, antennae/bobbles ≈ 10 % (05 §2.1).
- **Thumbnail test:** every species must read as a silhouette at 32×32 px. The smallest on-screen case is buttonbud on the crest: S = 150 × 0.85 × 0.62 = 79 px.
- **Asymmetry:**
  - the face is symmetric; the pose is not: lean ±2–4° per creature (seeded);
  - ears differ by ±0.06 rad;
  - the tail sits on the side opposite `facing`.

### 5.4 Part catalog (`data/creature_rig.json catalog`; GDD vocabulary → SDF)
All sizes are in bu; all joins use `smin` with the listed k; every tip is rounded (no interior angle < 60°, 04 P7).

**Ears:**

| id | Type | Recipe |
|---|---|---|
| 0 | none | — |
| 1 | round | Circles r 0.17 on the outline at ±0.62 rad, k 0.06; inner ear = accent @ 35 % inside 0.6 r |
| 2 | tuft | Centre vesica 0.22×0.12 + two side tufts 0.14 at ±0.30 rad, k 0.03 (a soft cowlick) |
| 3 | pointed_soft | Rounded triangles h 0.26, base 0.22, tip radius 0.05, at ±0.55 rad; inner = accent @ 40 % |
| 4 | bell | Stalk 0.20 curving outward and down, ending in an inverted bell (r 0.11, 5-lobed rim) in fur_2 — bluebell ears that swing on `follow` |
| 5 | leaf | Vesica 0.34×0.16 at ±0.70 rad, tip radius 0.025; colour gradient fur → accent toward the tip; midrib 0.012 at −8 % L |
| 6 | nub | Circles r 0.07 at ±0.45 rad, k 0.04 |
| 7 | long (reserve) | Capsule 0.50, r 0.075 → 0.06; upright at 0.25 rad or lop at 1.9 rad |

**Tails** (anchor x is multiplied by −facing, so the tail is on the back side):

| id | Type | Recipe |
|---|---|---|
| 0 | none | — |
| 1 | puff | Circle r 0.15 at (0.98·w/2, 0.24), tip colour |
| 2 | curl | Ring arc r 0.12, thickness 0.06, 270° sweep, round caps; fur with fur_2 @ 30 % |
| 3 | brush | Vesica 0.42×0.22 angled 0.9 rad up and back from (0.92·w/2, 0.18); fuzz ×1.6; tip in fur_2 |
| 4 | leaf | Vesica 0.32×0.15 at 0.8 rad, accent colour |
| 5 | sprout | Stem 0.12 + two leaves 0.10 from the rear top (0.80·w/2, 0.78); `cr_leaf` with an accent bud |

**Antennae** (from the head top; stalk thickness ≥ 0.016 bu, i.e. ≥ 1.2 px at the smallest S):

| id | Type | Recipe |
|---|---|---|
| 0 | none | — |
| 1 | sprout | Stem 0.20 + two leaves 0.13×0.065 at ±0.9 rad (`cr_leaf`) + a bud r 0.05 in accent (buttonbud's "button bud") |
| 2 | double_bobble | Two stalks 0.30 from ±0.12 at ±0.30 rad, bobbles r 0.065 in accent |
| 3 | fern_curl | Stem 0.18 rising into a 1.25-turn fiddlehead (max r 0.07, taper 0.025 → 0.012) in accent |
| 4 | dandelion_puff | Stem 0.28 (`cr_leaf`) topped by a seed puff r 0.13: 14 filaments with dot tips, alpha 0.85, fuzz ×2. In breeze it sheds a seed into the seeds system at most every 6 s |
| 5 | glow_bobble | Stalk 0.34 + bobble r 0.075 with emission `i_accent.a = 1`: at `g_lights > 0` the bobble glows (mix to accent ×1.1) with an additive halo of 3× radius emitted with α = 0 (premultiplied) |
| 6 | single_bobble (reserve) | As 5 without emission |

**Patterns** (inside the body only, under the face; ink per `palettes.creatures.pattern_ink_source`):

| id | Type | Recipe |
|---|---|---|
| 0 | none | — |
| 1 | belly | Large belly ellipse 0.62·r.x × 0.24 at y 0.27, size 1.0, strength 0.85. Every other species draws a subtle belly at size 0.60, strength 0.55 |
| 2 | freckles | 6 dots r 0.018 (3 per cheek, jittered), accent ink |
| 3 | socks | Band y < 0.16 with a wavy edge (amplitude 0.02, 3 waves), fur_2; feet nubs tinted |
| 4 | back_stripes | 3 curved bands across the head top (from y 0.72, width 0.05, spacing 0.12, following the squircle), fur_2 |
| 5 | cap | Top region y > 0.70 + 0.03·noise in fur_2 (a knitted hood) |
| 6 | cap_spots | Cap with edge 0.66 + 4–6 round spots r 0.04–0.07 in accent (toadstool look) |
| 7 | spots | 5–8 soft spots r 0.05–0.09 on back and sides, masked out of the face and belly |
| 8 | cheeks | Large cheek patches r 0.11 in fur_2, replacing the small blush |
| 9–11 | patch / stripe / gradient | Reserve |

**Eyes:**

| id | Type | Recipe |
|---|---|---|
| 0 | round | Ellipse in `cr_eye` + main highlight (r 0.36·eye, offset (−0.30, 0.38)·eye toward the light) + secondary highlight (0.14, (0.38, −0.42)); lower 40 % of the eye lifted 12 % (iris glow) |
| 1 | sleepy | Upper 40 % covered by a fur-coloured lid with a soft lash line (ink 30 %); one highlight 0.22 |
| 2 | dot (reserve) | — |

- **Closed styles** (`i_misc.w`): 1 = sleep arc ‿ (convex down), 2 = happy arc ∩ (convex up). Width 1.1× eye width, thickness 0.028 bu (≥ 1 dp at S ≥ 107 px), round caps.
- **Mouth:** 0 none, 1 small smile ‿ (0.07 wide), 2 "w" (0.10 wide), all at 0.028 bu thickness.
- **Highlights:** always on the light side (x mirrored by `sign(key_dir.x)`). At night they are dimmed only ×0.85, so eyes still sparkle.

### 5.5 Instance uniforms (exact layout, 16 of 16)

| # | Name | Contents |
|---|---|---|
| 0 | `i_fur` | rgb fur; a = fuzz_dp / 2 |
| 1 | `i_fur2` | rgb pattern ink; a = pattern strength |
| 2 | `i_belly` | rgb belly; a = belly size |
| 3 | `i_accent` | rgb accent; a = emission (glow_bobble 1, else 0) |
| 4 | `i_tip` | rgb fibre-tip colour; a = 0.45 |
| 5 | `i_cheek` | rgb `cr_cheek`; a = 0.50 (+0.25 when happy) |
| 6 | `i_eye` | rgb `cr_eye`; a = eye width (0.20) |
| 7 | `i_body` | w_h, n, S px, bottom n add (1.2) |
| 8 | `i_parts` | ear id, tail id, antenna id, pattern id |
| 9 | `i_part_p` | ear size, ear spread, tail size, antenna length |
| 10 | `i_face` | eye id, spacing, height from top, mouth id |
| 11 | `i_anim` | squash s, lean rad, blink lid 0..1, look −1..1 |
| 12 | `i_follow` | ear offset rad, antenna offset rad, tail offset rad, breath k |
| 13 | `i_state` | sleep 0..1, happy 0..1, facing ±1, seed 0..1 |
| 14 | `i_light` | nearest lit lantern direction xy, lamp intensity, cloud shadow at the feet |
| 15 | `i_misc` | pattern seed, pattern scale, feet nubs 0/1, closed-eye style |

- **Static per creature** (set on spawn): slots 0–10 and 15.
- **Animated** (set only while animating; ≤ 3 calls per frame per creature): slots 11, 12, 13, 14. Instance uniforms are written as whole `vec4`s, so keep the static parts in a CPU mirror (12.w breath k, 13.w seed) and rewrite them unchanged.
- **Asleep and still:** writes nothing except `i_light` at 2 Hz. Breathing and wind sway are computed in-shader from `g_time`.
- **Slot 14** is computed by `LampRegistry` at 2 Hz: the nearest lit lantern within 2.2× its pool radius, plus `cloud_shadow()` evaluated on the CPU.

### 5.6 Fragment algorithm (production version of the spike)
1. **Pose:**
   - `p` (bu) → rotate about the feet by −lean;
   - breathing `b(t)` = asymmetric smoothstep wave on `ph = fract(g_time·k/600 + seed)` with inhale 40 % of the period (I:E = 1:1.5);
   - `sc = vec2((1/s)·(1 − ax·b), s·(1 + ay·b))` with (ax, ay) = (0.010, 0.025) awake and (0.015, 0.035) asleep, × `g_motion`;
   - `ps = p / sc` (area-preserving squash about the feet, 05 §3.3).
2. **Silhouette SDF:**
   - body squircle;
   - `smin` ears (angle = spread + `i_follow.x` + wind term `0.05·sin(TAU·124/600·g_time + seed·6)·wind_k()·(1 + 0.35·gust)·g_motion`; sprouts and dandelion stems use 0.12);
   - tail (+ `i_follow.z`); antennae (+ `i_follow.y`).
   - Keep the region id of the dominant part (for part colours).
3. **Fuzz:**
   - `d_px = d·S` (or the gradient-normalised `d_px(f)` for squircle accuracy);
   - wobble ±`fuzz_dp`·3 px (low-frequency angular noise);
   - fibre fringe outside the silhouette, length `fringe_dp`·3 px (= 2.5 × fuzz_dp dp), N = perimeter_px / 3.6 fibres per turn, two anisotropic noise octaves in (angle·N, radius);
   - 8 % stray fibres at 1.6× length;
   - fringe alpha = `fib·(1 − t)²·0.85`;
   - `cover = core + fringe·(1 − core)`.
   - **Early out** when `cover < 0.002` (but still evaluate the bobble halo).
4. **Albedo:**
   - fur → belly → pattern (by id) → part colours (leaf/bell/bud/bobble by region);
   - felt mottling: `vnoise(ps·9)` ±2.5 % and `vnoise(ps·31)` ±1.5 %;
   - toward `i_tip` in the outer 40 % of the depth band.
5. **Light:**
   - `light_object(alb, up = smoothstep(0.05, 0.95, ps.y), ao = 1 − smoothstep(0, 0.25, ps.y))`;
   - core lift ×(0.93 → 1.03 by inner depth);
   - × (1 − 0.12·cloud shadow).
6. **Rim:**
   - L = `key_dir` evaluated once in `vertex()` at the creature origin (`MODEL_MATRIX[3].xy`), y flipped into local space, passed as a `flat` varying; `lam = max(dot(n, L), 0)`; `up = smoothstep(−0.35, 0.75, n.y)`;
   - band width `mix(4.5, 9, g_backlight)` px (1.5–3 dp, 05);
   - `rim = band·mix(lam², up·(0.35 + 0.65·lam), g_backlight)·g_rim`;
   - `col += g_key·rim·0.45`.
   - **Peach fuzz:** fringe fibres (and the outer 3 px of the band) blend toward `mix(col, key, 0.85)·1.12` by `(fringe + band·0.35·up)·g_backlight·up`. The bottom edge never lights up.
7. **Lantern light:** `col += g_accent·i_light.z·g_lights·(0.12 + 0.35·band·max(dot(n, i_light.xy), 0))`.
8. **Face:**
   - eyes by type; blink lid (eye height × (1 − lid), arc when lid > 0.85); closed styles; highlights on the light side; cheeks or `cheeks` pattern; mouth;
   - features shift by `look·0.05·w_h`, and the far eye narrows ×0.92 when |look| > 0.5;
   - eye ink × mix(1, ambient, 0.5), so eyes stay readable at night.
9. **Emission:** glow bobble (§5.4).
10. **Finish:** `finish(col, ps·S/3, FRAGCOORD.xy, 0.020)`; `COLOR = vec4(col·cover, cover)` + additive halo.

**LOD:** when `S·scale < 90 px` (crest creatures) and on governor tier ≥ 1, drop the second fibre octave, the stray fibres, the second mottling octave and the lantern term.

**Acceptance (R1 gate, with rubric #3, #5, #6, #9 ≥ 7):**
- at 200 % zoom the edge reads as soft felt (fibre fringe visible, no stair-steps, no hard sticker outline);
- at golden hour the top and sun-side edges glow, and the bottom edge never does;
- squash 0.88 shows no stretched-texture look;
- every one of the 12 species is recognisable at 32 px in silhouette.

### 5.7 Animation (springs from §10.2; numbers in `data/motion_tokens.json creature` win, and the rows not yet there — nap pose, nibble, play, wander, rain, facing — move into that block with the creature brain)

| Behaviour | Spec |
|---|---|
| **Breathing** | In-shader. Awake k ∈ [134, 171] → 3.51–4.48 s; asleep k ∈ [100, 120] → 5.0–6.0 s. Inhale 40 %. Awake scale (0.99, 1.025), asleep (0.985, 1.035), pivot at the feet. Per-creature k and phase seeded. Reduce Motion: amplitude × `g_motion` (0.3) and k ≤ 150 (≥ 4 s) |
| **Blink** | GDScript timer, interval uniform 2–6 s (seeded RNG for QA), 15 % double blink (110 ms gap). Close 50 ms, hold 20, open 70 (`micro`-like ease out). Suppressed while asleep, while being petted, and in the air |
| **Follow-through** | Ears, antennae and tail run on spring `follow` (1.6 Hz, ζ 0.35) driven by −(body vertical acceleration)·0.0009 rad/(px/s²) and horizontal velocity·0.0006. They lag the body by 40–80 ms. The spring sleeps when \|x\| < 0.0005 and \|v\| < 0.002, after which only the in-shader wind term runs (zero CPU) |
| **Tap (short)** (GDD §3.1) | Touch-down squash s → 0.94 in 80 ms, then spring `jelly` (2.6 Hz, ζ 0.4) back to 1. Ears lag via `follow`. It turns to look at you (`standard` 320 ms), chirps (S13) with a caption bubble, and its name tag (Label 42 on a faux-glass pill above the head) fades in for 2 s. A second tap within 2 s opens its card. A sleeping creature only *stirs* (s 0.97, ear twitch, z's pause 2 s; S14) and never wakes abruptly |
| **Long-press or stroke → pet** (GDD §3.1) | Radial fill ring from 150 ms. At 450 ms (or a ≥ 24 px stroke starting on the creature): squash to 0.88 on `jelly`; lean toward the finger ≤ 4° (`move`); eyes → happy arc; cheek α +0.25; ears flatten −0.15 rad (`follow`); a 1.6 Hz ±2° wiggle (lean modulation); S03 purr loops while held. **Release:** spring `jelly` toward 1.0 with a 1.04 overshoot target, **3 hearts rise** (stagger 120 ms), eyes reopen after 300 ms, +1 affection (`celebrate` when a heart threshold is crossed) |
| **Hop** (move between points) | Crouch s 0.92 for 90–120 ms → stretch s 1.10 in the air (300 ms parabola, height 0.18–0.30 bu, 40–70 px per hop) → land s 0.88 → `jelly`. Gaps of 180–420 ms between hops. The shadow stays on the ground, shrinking to 70 % and fading to 40 % at the apex. Under Reduce Motion: a glide with no stretch, plus a 300 ms position fade |
| **Arrive / leave** | Fade in over 400 ms at the entry (never pop-in), then 2–4 hops to the spot, then S12. Over the crest: parented to `BehindCrest` until the feet cross the crest line. Leaving mirrors this |
| **Nap** (sleeping pose) | 1200 ms settle into the pose: squash rest 0.94, lean −3° toward the surface, eyes sleep-arc, ears droop (round 0, tuft 0.26, pointed 0.26, bell 0.20, leaf 0.44 rad), tail wraps 0.6 rad forward, antenna droops 0.3 rad, glow bobble dims to 40 %. A soft "z" stamp every 4.84 s (k 124) rises 40 px and drifts 16 px right over 3 s (scale 0.8 → 1.1, α 0 → 0.8 → 0), at most 2 alive |
| **Nibble** | At a bed nibble point: lean 6° toward the bed, chew bobs (s 0.97) at 2 Hz for 1.5 s, pause 2–4 s, repeat |
| **Play** | Small in-place hops (height 0.12 bu) in pairs at `sun_stone` (capacity 2), facing each other, with a 0.8 s offset |
| **Wander** | 1–3 hops to a random point within 120 px, then a 3–8 s rest |
| **Sit by stream** | Face the brook (look 0.6 down-side), with an occasional ripple at its feet every 12.8 s (k 47) |
| **Boat watching** (GDD §4.1) | When a leaf boat launches, awake creatures turn to watch (look follows the boat); those within 300 px hop to the bank and sit by the stream until it passes |
| **Rain** | Away from shelter: LeafUmbrella appears (fade 400 ms), tilted 12°, sways on `follow`; ears flatten 0.2 rad. At shelter spots: tuck pose (squash 0.95) |
| **Facing turn** | Look crossfades −1 ↔ +1 over 200 ms (`short`) with a 0.97 dip. The tail side changes when look crosses 0. Never a mirror flip |
| **Debut** (new species) | A spotlight halo (r0 120 px, α 0.18) fades in for 900 ms, a sparkle burst of 5, S09; the album card pops later |
| **Greeter** (GDD §5.6; economy `greeter_delay_*` 4–10 s, `greeter_stay_s` 300) | When the app opens or resumes and nothing happened (or nobody is present), an already-met mossling that is **not** present strolls in from its `entry` like an arrival (400 ms fade, hops, S12), says hello with a happy squash and a heart, stays up to 5 min, then leaves like a visitor. It brings no gift |

### 5.8 Species notes (visual intent; data in `species.json` + `creature_rig.json`)

| Species | Look |
|---|---|
| puffmoss | Wide moss-green mochi; round ears; puff tail; big cream belly; sleepy eyes. The first friend, and the hero of frame A |
| buttonbud | Small cream sprout-child: a tuft plus a sprout antenna with a yellow "button" bud; pollen freckles; "w" mouth |
| pebblepaw | Widest misty-blue pebble shape; slate socks; curl tail; round ears |
| honeyhum | Honey bee-ish: double bobble antennae, three cocoa back stripes, puff tail, no ears |
| fernwhisk | Tall sage-green; soft pointed ears; brush tail; fern fiddlehead antenna; fern cap. Fluffiest fringe (3 dp) |
| dandelfluff | Snow-white with a dandelion-puff antenna that sheds a seed in breeze; puff tail; very fuzzy |
| bellkin | Misty blue; lilac bluebell ears that swing; berry-pink inner accents |
| primpip | Peach with leaf ears, a leaf tail and big blush cheeks |
| capling | Oat body under a rose toadstool cap with snow spots; a sprout tail. Plays in the toadstool ring |
| puddlewump | The widest (1.30) misty creature; tiny nubs; sage spots; "w" mouth. Loves rain |
| glowmote | Twilight periwinkle (dusk/night only); pointed ears; curl tail; a glowing bobble. Its own warm light at night |
| moonpuff | Big lilac (size 1.15); tuft; snowy cap; sleepy eyes. Night-only, rests on the moon rock |

---

## 6. Flora, décor and props

### 6.1 How flora is drawn (decision A3)
- **Stamps:**
  - One hand-written SVG atlas, `res://art/flora/flora_atlas.svg` (1024×1024 design px), rasterised once by the `texture` importer (`svg/scale = 1.0`, `compress/mode = Lossless`, mipmaps on, `fix_alpha_border` on).
  - Each stamp is a **tone mask** (R lit, G shade, B detail; R+G+B = 1 inside; black inside = colour-line tone; alpha = coverage).
  - Region rects are listed in `art/flora/flora_atlas.json`.
- **Stamp list** (w×h px at depth scale 1):

| Group | Stamps |
|---|---|
| Petals | `petal_round` 24×12 · `petal_long` 30×12 · `petal_heart` 16×16 (notch rounded) · `petal_cup` 20×18 · `bell` 14×16 (5-lobed flared rim) · `floret` 6×10 · `forget_bloom` 14 (5 lobes) |
| Centres | `daisy_center` 14 · `star_center` 10 |
| Seeds and buds | `pappus` 10×18 · `seed_puff` 44 · `bud_round` 14 · `bud_long` 10×18 |
| Leaves | `leaf_spoon` 28×12 · `leaf_strap` 60×10 · `leaf_trifoliate` 30 · `leaf_lobed` 30 · `leaf_rosette` 40×18 · `leaf_toothed` 44×14 (rounded lobes only) · `leaf_broad` 50×16 · `cotyledon` 12×8 |
| Ground | `grass_tuft_a/b/c` 40×36 · `clover_leaf` 22 · `soil_mound` 40×16 · `moss_mound` 90×40 · `fern_frond` 30×110 · `reed` 12×140 |
| Willow | `willow_frond` 16×120 (tileable along its length) |
| Props and FX | `leaf_umbrella` 90×60 · `leaf_boat` 48×20 |

- **Authoring:**
  - filled shapes;
  - the 2-stop "volume" gradient (ΔL* 8–12, lit from the top) is an R → G channel gradient;
  - `stroke-linejoin`/`linecap` round; minimum stroke 3 px;
  - no `<text>`, no filters except `feGaussianBlur`;
  - every tip rounded (no interior angle < 60°).
- **Beds:**
  - `FloraBuilder` (`scripts/flora/flora_builder.gd`) builds one `ArrayMesh` per bed (`MeshInstance2D`, `flora_bed.gdshader`, §4.10).
  - For each planted stem, in `spots.json` fill order and sorted back → front by y:
    - a **stem strip**: 6 segments, tapering 4 → 2 px × depth, a quadratic-Bézier curve with seeded lean ±8° and a slight S;
    - **leaves** placed by a tiny per-form grammar (L-system-lite, §6.3);
    - **head stamps** at the tip.
  - Seed = hash(bed id, stem index, flower id), so it is deterministic and the same after every load.
  - Rebuild a bed only when a stem changes stage or during its 600 ms unfurl.
- **Palette LUT:** `flora_lut` (8 flower rows in `garden_order` + 2 dynamic rows for unfurl colour interpolation) × 8 slots, built from `palettes.json` at boot.

### 6.2 Growth stages (timings are the GDD's `flora.json sprout_at_s / bud_at_s / bloom_at_s`)

| Stage | Visual (at depth 1) |
|---|---|
| **Seed** (0 → sprout_at) | `soil_mound` (soil tones) with a single 1 dp glint that twinkles every 7.9 s (k 76) |
| **Sprout** | Stem grows continuously from 30 % to 60 % of its final height across the stage (time-lerped, so a returning player sees growth); 2 `cotyledon` leaves |
| **Bud** | All leaves; stem 85 → 100 %; the bud (`bud_round` or `bud_long`, colour `bud`) swells 0.6 → 1.0 across the stage |
| **Bloom** | The full head (§6.3). `moonbloom` blooms only in dusk/night (`opens_at`): by day it is a closed `bud_long`. It opens on the phase change in a wave (each stem delayed 0–20 s at random) and closes back over 2 s at dawn |

**Transitions:**
- **Watched growth step:** stem stretch y 1.0 → 1.08 → 1.0 on spring `move`; new parts scale 0.6 → 1.0 on `pop` with a 300 ms fade (never pop-in).
- **Unfurl** (bud → bloom), 600 ms total (`motion_tokens.flora.unfurl`):
  - 60 ms anticipation: bud swells 1.08, `micro`;
  - petals open from a folded pose (15 % of their open angle, scale 0.55) over 420 ms on `emphasized_decel`, staggered 30 ms in angular order;
  - petal colour lerps `bud` → petal lit through the dynamic LUT row;
  - stem stretch 1.06 → 1 on `move`; leaves kicked 0.08 rad on `follow`;
  - 3–5 sparkles over 400 ms; S04.
  - **Trigger (GDD §3.1):**
    - when `bloom_at_s` arrives while the player is watching, the stem becomes a **ready bud**: the bud swells 1.04 and glows (`halo_add` r0 14 px, α 0.25, breathing k 76);
    - tapping the bed unfurls all its ready buds with a 30 ms stagger;
    - un-tapped ready buds open by themselves after 20 s with a slow 2.4 s unfurl;
    - in the tutorial a hint ring appears around the bud after 3 s (§9.4).
- **Bloomed while away:** shown open on return (no ready state). On first sight, at most 3 stems scene-wide get one soft glint each.

### 6.3 The eight MVP flowers (ids and forms from `flora.json`; colours `fl_*` §3.7)

| Flower (form) | Grammar | Visual |
|---|---|---|
| **sweet_clover** (globe) | `S L3@30% H(globe)` | Stem 70 px. One trifoliate leaf with a pale chevron (detail). Head: a Ø 30 globe of 16 `floret` stamps in 2 radial rings, pink-white, tips lighter. Bud: a closed green-pink ball Ø 9. The tutorial flower, so it must read instantly |
| **button_daisy** (daisy) | `S L@15% L@35% H(daisy)` | Stem 90 px, 2 alternating spoon leaves. Head Ø 40: 13 `petal_round` cream petals (one tilted 6° per petal for life) around a domed golden `daisy_center` with a dot texture (detail) |
| **buttercup** (cup) | `S [L] S [L] H(cup)` | Stem 95 px, branched, 2 rounded 3-lobed leaves. Head Ø 36: a 3/4-view cup of 5 glossy petals (3 front overlapping, 2 back) with a gloss highlight on each front petal (detail). The most saturated flower (C 0.124), kept small |
| **forget_me_not** (cluster) | `S L S L C(7)` | Stem 75 px; the tip curls (scorpioid) carrying 7 `forget_bloom` sky-blue flowers Ø 7–9 with yellow eyes (detail) and 2 pink-blue buds at the curl's end. Narrow leaves |
| **bluebell** (bell) | `R(strap×3) S(arch) B(4..6)` | 3 long strap leaves at the base. An arched stem of 105 px carries 4–6 nodding `bell` flowers (18–24 px) hanging along the outside of the arch, rims lighter (detail). Bells sway on `follow` |
| **primrose** (primrose) | `R(rosette×5) P(3..5)` | A low cushion of 5 crinkled rosette leaves; 3–5 short (45 px) pedicels with Ø 28 flowers of 5 `petal_heart` petals and a deeper-yellow star centre. The lowest, roundest silhouette in a bed |
| **dandelion** (puff) | `R(toothed×4) S(tall) H(puff)` | Rounded-lobed rosette; a tall stem of 120 px. Bloom = the seed clock: `seed_puff` Ø 44 of 30 `pappus` filaments, semi-transparent white. In breeze, bloomed dandelions feed the seeds system (one seed per stem at most every 6 s, within budget). Bud: closed with a yellow tip |
| **moonbloom** (lily) | `R(broad×3) S H(lily)` | 3 broad blue-green leaves; stem 110 px; an open lily of 6 `petal_long` petals (Ø 56) that are slightly recurved, ice-blue white, with glowing stamens (petals emit 0.25, stamens 0.5 × `g_lights`). The night's flower |

**Bed composition** (Townscaper rule):
- because stems fill the bed's Poisson offsets, mixed flowers form natural drifts;
- the builder varies scale ±10 %, rotation ±5°, hue ±4° and L* ±3 per stem (05 §4).

### 6.4 Grass, meadow dressing, willow
- **Grass:** ≥ 260 tufts (§4.6) from `grass_tuft_a/b/c`, plus 3 clover patches of 6–9 `clover_leaf` (prop_tone with `moss` and `willow_leaf` tones).
- **Willow:**
  - canopy SVG 420×400: overlapping rounded leaf masses (`willow_leaf`) with speckled leaf detail; trunk SVG (`wood_bark`, grooves in detail);
  - 11 frond strips: `MeshInstance2D` strips 16 px wide, 120–260 px long, textured with `willow_frond`, hanging from the canopy's lower edge;
  - frond sway = a travelling wave, phase increasing 1.2 rad from root to tip, amplitude 10–18 px at the tip, plus gusts;
  - the chime branch extends right from the trunk at y ≈ 640.
- **Stump** (210×180): bark sides (`wood_bark`), cut top with rings (`wood_cut`), a dark front hollow (shade tone + contact-shadow tint), a moss cap and one fern.
- **Fern clump** (fern gap) and **reeds** (spring rock): `fern_frond`/`reed` stamps with sway, partly overlapping the frame edge.

### 6.5 Props (GDD `spots.json props`)

| Prop | Visual |
|---|---|
| **sun_stone_rock** (FOCAL, 261×120) | A broad, smooth, slightly tilted flat stone, `stone_warm`. The large top plane is all lit tone (it catches every key light). Lichen speckles (detail) toward the back; soft moss at the base; 3 glow mushrooms at its left foot (art dressing). Its contact shadow is the darkest on the meadow (α × 1.2) |
| **basket** (132×108) | Woven wicker (`wicker`) with a soft cloth liner. **Fill states:** visible dew-drop stamps = min(slots used, 12), plus up to 3 gift items peeking; a gentle gold glint (`halo_add` r0 10 px, k 76) once ≥ 1 item. 2 dp colour line (interactive) |
| **mailbox** (90×144) | A small post mailbox (`wood_painted` body, `roof_slate` roof, a little leaf emblem in detail). The flag (toadstool_cap colour) raises on an unread postcard with `pop`, plus a soft glow pulse (k 76, α ≤ 0.15). 2 dp colour line |
| **wind_chime_branch** | Part of the willow. Its hit area covers the branch and the hung chimes |
| **stump** (210×180) | §6.4 |
| **spring_rock** (180×120) | Mossy `stone_cool` boulder. The brook springs from a cleft at its left: water shader foam is strongest here, and a 2 px trickle sheet runs over the lip |
| **willow** (420×510) | §6.4 |

### 6.6 The six décor sets (GDD `decor.json`; each copy fills the next anchor position)

| Décor | Copy (px at depth 1) | Animation and effects |
|---|---|---|
| **leaf_pinwheel** (scatter on the slope) | A 4-blade pinwheel, Ø 60 head of leaf-shaped blades alternating `pinwheel_a`/`pinwheel_b` with a wooden centre pin, on a 90 px `wood_cut` stick | `spin_with_wind`: ω = (0.3 + 0.9·g_wind·(1 + 0.35·gust)) rev/s, idle spin capped at 1.2 rev/s. Tap `spin_burst`: ω peaks at 2.5 rev/s (below the 3.75 rev/s wagon-wheel limit of 4 blades at 30 fps), exponential decay τ 1.2 s, 3 leaf sparkles, S19 |
| **pebble_cairn** (stack at x 49) | Each copy adds one flat rounded pebble on top: width 56 → 34 px going up, height 22 → 14, alternating `stone_cool`/`pebble_alt`/`stone_warm`, offset ±4 px, tilt ±5°, moss on pebbles 2 and 6 | New pebble drops 40 px with a 300 ms fade + `pop`, S05. Otherwise still (stillness is its charm) except a dew glint every 12.8 s |
| **toadstool_seat** (ring) | A toadstool: domed cap Ø 48×28 in `toadstool_cap` with cream spots (detail), gills under the rim, a stout 20×24 stem in `toadstool_stem` | `ring_forms` (≥ 3): at dusk/night a faint ring of 6 static glow motes (`halo_add` r0 6 px, k 76 breathing) joins the caps. `rain_shelter`: creatures tuck under. Placement fade + `pop` |
| **stream_stones** (path in the brook) | A flat stepping stone 54×22 in `stone_cool` with a moss cap (detail) and a wet darker band at the waterline | `water_riffle`: the water shader adds a foam wedge downstream (`u_stones`). Creatures can sit on the `stream_stones` spot |
| **firefly_lantern** (path along the far bank) | A shepherd's-crook stick (150 px, `wood_bark`) holding a glass jar lantern (36×44, `lantern_jar` faux glass with a vertical gloss, `string` wire handle, a leaf-shaped lid). Inside: a `lantern_light` core and 2–3 tiny firefly dots drifting slowly (in-shader) | `glow_golden_dusk_night`: the core emits by `g_lights` (0.10 at golden, 1.0 at night); head halo `halo_add` r0 18 px; meadow pool r 150 px (`u_lamps`); brook reflection streak. Breath ±5 % at k 181. `fireflies_gather`: firefly emission is biased toward lantern positions. Tap `lantern_brighten`: +60 % over 200 ms, hold 2 s, back over 1.2 s, plus 2–3 fireflies released, S20. 2 dp colour line on the jar |
| **wind_chime** (string along the branch) | Each copy hangs one celadon ceramic tube (10 × 46–70 px, `chime_ceramic`) on a 30–40 px `string`. Copy 1 adds a paper wind strip (detail pink) | `rings_with_wind`: each tube is a pendulum on spring `follow`, forced by `g_wind`·gust (2–6°). Tap `ring_chime`: impulse 8° per tube, staggered 40 ms, S21. `adds_chime_note` is the audio twin |

**Placement rule for all décor:**
- appear with a 300 ms fade + `pop` scale 0.6 → 1.0 + a 4-sparkle dust puff + S05;
- depth scale from the anchor y;
- y-sorted;
- contact shadow (props with height ≥ 40 px).

### 6.7 Gifts, dew and small stamps (`art/fx/fx_atlas.svg`, tone masks unless noted)
- **Dew drop** (UI and basket): a rounded drop with a highlight, gold duotone in UI; in the world a gold-tinted glass drop.
- **Gifts** (`economy.gift_items`):
  - **acorn_cup**: an acorn cap holding a dew bead;
  - **petal_bundle**: 3 petals tied with string;
  - **shiny_pebble**: a polished `stone_cool` pebble with a strong highlight;
  - **seed_pouch**: a tiny cloth pouch with a leaf tie;
  - **moon_drop**: a pale blue glass bead that faintly emits at night (0.3).
- **Photos:** a polaroid frame (`surface_hi`, r-xs) whose picture is the live fur shader in a UI `Control` (no SubViewport).
- **FX stamps:** sparkle (rounded 4-point, 16 px), heart (24 px, coral), "z" (rounded, 20 px), dust puff (3 soft dots), ripple ring.

### 6.8 Leaf boat, leaf umbrella, dandelion seeds
- **Leaf boat** (GDD §4.4; bought from the last row of Garden → Décor for 1 dew):
  - a 48×20 `leaf_boat` appears at the spring rock (fade 300 ms + `pop`) and drifts the brook polyline right → left in 40 s (`leaf_boat_drift_s`), bobbing ±4° (k 124), with a faint wake;
  - from golden hour to dawn it carries a tiny candle (`lantern_light` emission + `halo_add` r0 8 px, breath k 181);
  - up to 3 on the water (extra taps queue 4 s apart);
  - it leaves at the left edge with a 300 ms fade.
- **Stream tap:** a ripple ring to 36 dp in 380 ms plus bubbles (water shader `u_ripples`).
- **Leaf umbrella:** see §5.7.
- **Seeds:** see §7.

### 6.9 Reserve designs (not in MVP data; keep for later sets)
- **Tiny bridge:** an arched 220×70 plank bridge (`wood_cut` planks with gaps, `string` rope rails, moss on the posts) spanning the brook at x ≈ 300.
- **Picnic blanket:** a soft knitted blanket 220×90 in perspective (`toadstool_cap` coral with cream gingham detail, gentle folds, a fringe), a 2-creature nap spot.
- Both follow §6.6's placement rule.

---

## 7. Particles (D9: ≤ 3 `GPUParticles2D` systems on screen, ≤ 150 particles, no turbulence/trails/sub-emitters, fade-in ≥ 300 ms)

### 7.1 Systems (all use `wander` process + `particle_draw`; sizes at depth 1; 1 dp = 3 px)

| System | Draw kind / blend | Amount | Size | Speed | Lifetime | Motion and look |
|---|---|---|---|---|---|---|
| `dust` | soft dot, add | 24–36 | 3–7.5 px, α 0.15–0.4 | 6–24 px/s | 6 s | Sine wander (2 sines, 0.2–0.5 Hz); **visible only inside light shafts** (`u_shafts` mask in the draw shader); colour `glow` |
| `pollen` | soft dot, add | 6–10 | 9–15 px, α 0.5 | 24–60 px/s along +x | 8 s | Vertical bob at 0.2 Hz (k 120); colour `#FFF1C2` |
| `seeds` (breeze) | stamp `pappus`, mix | 12 | 12–18 px | 30–60 px/s downwind, rising 6 px/s | 10 s | Slow spin ±30°/s, bob k 120. Also emitted from dandelion antennae and bloomed dandelions |
| `petals` (breeze, spring) | stamp `petal_round`, mix | 10–12 | 18–36 px | Fall 60–120 px/s | 7 s | Flutter: sway 30–60 px at 0.3–0.6 Hz, roll 30–90°/s (05 §2.6). Colour `fl_clover` |
| `fireflies` (dusk, night) | firefly, add | 10 (dusk) / 18 (night) | Core 6–9 px + halo 36–60 px | 15–45 px/s wander | 20 s | Pulse: base 35 %, rise 0.25 s, hold 0.15 s, fall 0.45 s, period 600/k with k ∈ [86, 100] (6.0–7.0 s) → < 3 onsets/s scene-wide. Emission y 900–1450, biased to lanterns and flowers. Colour core `#FFE7A6`, halo `accent` |
| `rain` | streak, mix | 120 (`world.json rain_particles`) | 3×36 px (1×12 dp), α 0.25–0.4 | 360–720 px/s (2–4 m/s) | 3.6 s | Tilt 8° downwind (with `g_wind`). Emission box = the whole viewport + 200 px above it, so density is uniform; each streak fades in over 300 ms (V5) |
| `splash` | ring, mix | 6 | 24–48 px rings, flattened ×0.35 | — | 1.0 s (ring visible for the first 0.6 s) | 6 per second on the meadow (y 820–1500; rate = amount / lifetime), α 0.3 → 0, radius ease-out |

**Not particles:**
- **Butterflies:** 0–3 `Node2D` boids by day and golden hour (clear or breeze) when ≥ 3 stems have bloomed.
  - Two wing stamps on one body, wing scale.x flap at 2.4 Hz with glides.
  - Speed 90–150 px/s; seek bloomed stems; stay ≥ 60 px from creatures and within y 700–1450.
  - Land on a flower for 3–8 s (wings open/close at 0.5 Hz).
  - Colours from flower petals (`fl_buttercup`, `fl_forget_me_not`) with an ink body.
- **Brook ripples and rain rings:** in the water shader.
- **Reward sparkles, hearts, z's:** pooled sprites.

### 7.2 Composition per state (the ≤ 3 / ≤ 150 rule)

| State | Systems (amount) | Total |
|---|---|---|
| Dawn clear | dust 24, pollen 8 | 32 |
| Day clear | dust 30, pollen 10 | 40 |
| Day breeze | dust 24, seeds 12, petals 10 | 46 |
| Golden clear | dust 36, pollen 10 | 46 |
| Golden breeze | dust 30, seeds 12, petals 10 | 52 |
| Dusk | fireflies 10, pollen 6 (+ seeds 8 in breeze) | 16–24 |
| Night | fireflies 18 | 18 |
| Rain (any time) | rain 120, splash 6 | 126 |
| Reduce Motion | every amount × 0.3 (`amount_ratio`) | — |
| Ambient mode | × 0.5 (02 §3) | — |

**`ParticleBudget` rule:**
- a system may start (`emitting = true`) only if Σ `amount` of all not-yet-finished systems + its `amount` ≤ 150 and the active count ≤ 3;
- `amount_ratio` fades density but still costs (§4.15), so on weather changes the outgoing system stops emitting first and the incoming one starts (with `preprocess` = 1 lifetime) once there is room;
- each system's `visible` turns off when it finishes.

---

## 8. Lighting by time of day

### 8.1 What each global does

| Global | Dawn | Day | Golden | Dusk | Night |
|---|---|---|---|---|---|
| Key light (`g_key`, `g_sun_dir`) | Peach `#FFD6AE` from the upper left, low (elev 0.40). Shadows long, to the lower right | Warm white `#FFF1C2` from the upper right (elev 0.80). Short, crisp shadows to the lower left | Amber `#FFC266` straight from the sun in the crest gap. **Contre-jour** (backlight 1.0): rims on top and sun-facing edges, shadows 2.5× long toward the viewer | Coral `#FF9E7E` glow from below the crest (sun set). Soft, faint shadows (α 0.18) | Moon `#9DB4FF` from the upper right (elev 0.80), rim 0.5 |
| Ambient (`g_ambient`) | Lavender `#E2D6EE` | Identity `#FFFFFF` | Peach `#FFE0C2` | Violet `#B3A3D1` | Blue `#5D6AA0` (scotopic shift) |
| Rim / backlight | 0.60 / 0.35 | 0.35 / 0.10 | 0.80 / 1.00 | 0.80 / 0.60 | 0.50 / 0.20 |
| Ground light | 0.12 | 0.18 | 0.20 | 0.06 | 0.04 |
| Halos | Sun rising behind the willow; halo 1.0, α 0.22 | Halo 1.0, α 0.18 | Halo 1.5 (wider, warmer), α 0.30 | Horizon glow only | Moon halo 0.8, α 0.15 |
| Shafts | 3 through the willow canopy (dappled) | 3 slanting from the upper right | 4 radiating from the sun | 0 | 0 |
| Stars | 0.15 (last few) | 0 | 0 | 0.45 | 1.0 |
| Local lights (`g_lights`) | 0.15 (fading out) | 0 | 0.10 (lanterns begin) | 0.75 | 1.0 |
| Cloud shadows | 0.10 | 0.12 | 0.10 | 0 | 0 |
| Mist (`g_mist`) | 0.20: low mist over the crest and the brook | 0 | 0.04 | 0.08 | 0.06 |

### 8.2 Cloud shadows crossing the ground
- `cloud_shadow()` (§4.2): soft fBm blobs 300 px across, drifting right at 15 px/s (tile 1800 px, k 5 → seamless at 600 s).
- Strength `g_cloud_shadow·(0.4 + 0.6·g_cloud)`: ≈ 12 % darkening toward the shadow tint at most.
- Applied in the meadow, grass, flora and props (at the prop origin), and on creatures (`i_light.w`, CPU at 2 Hz), so a passing shadow dims a napping creature too.
- Off at dusk and night and in rain (overcast is already flat).

### 8.3 Lanterns, fireflies and the night focal plan
- **Night hierarchy** (05 §2.2): warm pools first, silhouettes second.
  - The sun stone always has 3 glow mushrooms (`glow_mushroom`, emission 0.55, halos r0 10 px) → the focal holds at night with zero décor.
  - Each firefly lantern adds a meadow pool (r 150 px, α 0.25–0.40 in `accent`), a head halo, warm fill and rim on creatures within range (`i_light`), and a brook reflection.
  - Glowmote's bobble and moonbloom petals are moving or soft secondary lights.
- **Flash safety:** brightness modulation everywhere < 3 Hz (lantern breath 0.30 Hz, mushrooms 0.13 Hz, fireflies 0.14–0.17 Hz per firefly), and < 3 onsets per second scene-wide (WCAG 2.3.1).

### 8.4 Rain lighting
Flattened key and lower chroma (§3.4), no shafts, no dust, halo α ×0.4, rim ×0.5, and a wet sheen on the meadow. Lanterns, if lit by time of day, glow normally: their pools read even better on the wet ground (pool α +0.05 under rain).

---

## 9. UI visual spec

### 9.1 Type scale (synthesis §3; 1 dp = 3 px; fonts per D6)

| Style | px | Font | Use |
|---|---|---|---|
| Title | 84 | Baloo 2 700 | Sheet titles, postcard headings |
| HUD numerals | 66 | Baloo 2 700, **MSDF** import (`msdf_pixel_range 8`, `msdf_size 48`) for tweened counters; `tnum` feature when available | Dew counter, big counts |
| Body | 48 | Nunito 500 | Settings rows, postcard text, descriptions |
| Label | 42 | Nunito 700 | Buttons, card names, chip labels, prices (prices: Baloo 2 700 48) |
| Caption | 36 | Nunito 700 (minimum size anywhere) | Dock labels, hints, group captions |

- **Line height:** 1.25 (en), 1.40 (vi, +12 %). Strings are NFC. Godot's `line_spacing` is extra px on top of the font's ascent + descent (Nunito 1.36, Baloo 2 1.60), so `ThemeBuilder` derives it per style from the font (negative for en).
- **Text scale:** 100 / 115 / 130 / 150 / 200 % (02 §5) rebuilds the Theme font sizes. Dock labels cap at 130 % (icons carry the meaning above that); everything in sheets scales fully and reflows (rows grow, cards grow taller, grids drop to 2 columns at ≥ 150 %).
- **Colours:** text on glass is always `ink`. `ink_2` only on opaque `surface`/`surface_hi`. Never white text except `surface_hi` on `primary`/`leaf`.

### 9.2 Shape, elevation, glass
- **Radii** (05 §0.1): r-xs 24 px · r-s 30 · r-m 48 · r-l 72 · r-xl 96 · r-pill (h/2).
  - Concentric rule: inner = outer − padding, minimum 24 px (8 dp).
  - `corner_detail` 12 for r ≤ 48, 16 above.
- **Elevation** (shadows in `ink`, never black):
  - e0 flat;
  - e1 cards on glass: α 0.06, size 24, offset (0, 6);
  - e2 floating chips and dock: α 0.12, size 48, offset (0, 18);
  - e3 sheet and modal: α 0.16, size 72, offset (0, 24).
- **Glass (C7):**
  - Faux glass for everything except the open sheet.
  - Live glass for the open sheet only, never on the low tier.
  - Never glass on glass: controls inside a glass sheet are `surface_hi` cards or plain ink.
  - Reduce Transparency → fill 1.0.
- **Colour lines:** 2 dp lines (fill colour at ΔL* −30) appear only on interactive world objects, never on UI. UI uses fills and elevation.

### 9.3 Icons
- **Grid:** 24 dp = 72 px canvas, 2 dp padding (60 px live area), filled shapes, rounded terminals (radius ≥ 3 px), no interior angle < 60°.
- **Duotone:** primary shape `ink`, secondary shape the icon's accent (`palettes.icon_accent`) at α 0.40.
- **Import:** DPITexture (`svg` importer, `fix_alpha_border = true`), icons only (C11, R6).
- **Set:** dew (drop + highlight), watch (rounded almond eye, plus a closed-lid variant for ambient), garden (sprout in a pot), album (book with a paw-print leaf), basket (round basket), settings (**two slider knobs** — no cog teeth), close (soft ×, round caps), back (rounded chevron), heart, sun, moon, dawn (half sun), golden (sun on horizon), dusk (sun under horizon), cloud, breeze (three curved lines), rain (cloud + drops), postcard (envelope with heart seal), check, plus, minus, music, haptics, motion, transparency, text size (Aa), mono (single ear), hand (left-handed), language (speech bubble "vi/en" as paths, no `<text>`), photo, lock — the lock is **never used** (nothing is "locked"; use the "not met yet" style).

### 9.4 Components (behaviour per GDD §8; visuals here)

| Component | Spec (px at H = 1920, T = 120) |
|---|---|
| **Dew chip** (passive) | Faux glass, r-pill, h 120, x 48 → 48 + w (w 264–420), y 144–264. Contents: dew icon 72 at x+30, numeral HUD 66 ink at x+120. Appears after the first collect (`short` fade + `pop`). On change the count rolls 600 ms (40 ms per step) with `pop` 1.08 per S02 step. Not a target |
| **Time/weather chip** (passive) | Faux glass circle Ø 120 at x 768–888, y 144; composite icon (phase + weather). On a phase or weather change the label (Label 42) **peeks**: the chip widens leftward to x ≈ 480 (`standard`), holds 4 s, collapses (`exit`). Not a target |
| **"Just watch" eye** | Faux glass circle Ø 120 at x 912–1032, y 144; eye icon (rounded almond, closed-lid variant while ambient). Hit 216×216 (x 864–1080, y 144–360), the only HUD target (72 dp). `HUD_WATCH_A11Y` label. Tap → ambient watch (HUD and dock fade out over 600 ms) |
| **Left-handed** | Eye at x 48–168, time chip at x 192–312, dew chip right-aligned to x 1032 |
| **Dock** | Faux glass pill x 24–1056, y 1541–1781 (240 tall, r 120), e2. Order **[Settings] [Garden] [Basket] [Album]** (left-handed: [Album] [Basket] [Garden] [Settings]), centres x 135 / 405 / 675 / 945, centre y 1661. **Plates** (`surface_hi`, e1, not glass): Garden and Basket Ø 216 (72 dp), icon 84 + label Caption 36; Settings and Album Ø 168 (56 dp), icon 72 + label. Hit 228×228 per button (y 1547–1775). **Active** (its sheet open): plate `primary_tint` + 3 dp `primary` ring + icon accent at 100 %. **Basket badge**: coral pill (min Ø 48) at the plate's top-right with the gift count (Caption 36 ink, 6.96:1); a brim sparkle (3 sparkles every 7.9 s) when full; plus the gold ring_fill (count/24) around the icon. **Asleep** (onboarding): 50 % opacity, still tappable |
| **Sheet** | Live glass, x 24–1056, bottom = dock top − 24 (**1517**), height = round(0.56·H) (**1075 → top 442**; at H 2400: 653–1997). r-xl 96 on all corners (floating above the dock), e3. The dock stays visible below it. Grabber 120×12 `ink` @ 0.25 at y 464 (swipe zone 442–574). Header 490–670: Title at x 72; close button Ø 108 `surface_hi` + × icon at x 900–1008, y 526–634 (hit 864–1044 × 490–670). Content scrolls with a 72 px fade mask at the bottom edge. **In:** rise 96 px + fade over `standard` 320 ms. **Out:** `exit` (≈ 210 ms). **Swap:** 200 ms crossfade. Scrim 0.24 covers the world only (HUD and dock stay crisp) |
| **Scrim** | `scrim` @ 0.24 under sheets (fades with `short`), @ 0.40 under modal cards. Tap on the scrim closes |
| **Primary button** | Pill, h 156 (52 dp; 132 inside cards, whose hit rect extends 12 px into the card padding to 156), `primary` fill, Label 42 / Nunito 800 in `surface_hi`, e1. **Pressed:** instant `primary_pressed` + scale 0.96 in 80 ms; release `pop` |
| **Secondary button** | Pill, `surface_hi` fill, `ink` label, 1 dp `ink` @ 0.10 border. Also used for the not-yet-affordable state (below) |
| **Garden item card** | A row card 936×300 (x 72–1008), `surface_hi`, r-l 72, e1, padding 24. Contents (GDD §8.1): **live mini-render** well 252×252 (`leaf_tint` backdrop; the real flower, décor piece or leaf boat drawn by its shader), name (Label 42), "{owned} of {max}" (Caption, `ink_2`), price chip (dew icon 48 + Baloo 48), dew-yield drops (1–3 small drops), bloom time (Caption `ink_2`), "Loved by {names}" (Caption `ink_2`). Primary **Plant / Place** 300×132 at the card's bottom-right. **Not affordable:** secondary style, label "A little more dew", price chip in `ink_2`; a press gives S11 and a ±2 dp lateral nudge on `follow` (never red, never a shake of the screen) |
| **Choose-a-bed mode** (first copy) | The sheet exits; a toast "Choose a bed" sits at y 400; every bed with free stems shows a breathing ring (`primary` @ 0.5, 3 dp, its hit ellipse, k 124) and the rest of the world dims 10 %. Tap a bed → seed arc → planted. Back cancels |
| **Basket tile** | 108×108 `surface_hi`, r-xs 24, item stamp 84. Empty: 2 dp ring `ink` @ 0.10 + centre dot. Display only |
| **Dew cup widget** | Acorn-cup stamp 132 px with a gold liquid level (fill = cup/brim), "Dew cup" (Label) + amount (Baloo 48). Brimming: 3 sparkles + Caption "The dew cup is brimming." |
| **Album friend card** | 288×372: portrait well 288×240 (live fur shader, S 150, idle at 30 fps), name Label 42, hearts row (5 × 36 px, coral filled / `ink` @ 0.25 outline). Unknown: silhouette in `ink` @ 0.10 with fuzz and no face, "Not met yet" (Label, ink) + hint (Caption, `ink_2` on `surface_hi`) |
| **Friend detail** (pushed with `standard`) | Portrait 600 px well, name (Title) with a rename pencil button (hit 180), **Pet** button (the tap alternative to long-press), favourite spot, hearts, photos strip |
| **Modal cards** (postcard reader, new friend, recap, "Leave the hollow for now?") | `surface_hi` with paper grain 0.02, r-l 72, e3, scrim 0.40, x 72–1008. Postcard 936×1176 at y 372 (stamp illustration 360×360 = live creature portrait, text Body 48 ink, primary "Keep"). New friend: rises with `emphasized` 500 ms and shrinks into the Album button on close. Recap: 936×720, three rows (dew, visitors, blooms); tap or 5 s auto-dismiss. Leave: 936×560, [Stay a while] (primary) [Leave for now] (secondary) |
| **Toast** | Faux glass pill h 96, Label 42, centred at y 400, auto-dismiss after 3 s |
| **Long-press ring** | §4.18 |
| **Tutorial hint ring** | Soft ring (2 dp, `surface_hi` @ 0.8) expanding 36 dp over 1.2 s every 3 s (k 200, the GDD §3.4 period): around the tutorial seed from 6.5 s, and around a ready bud after 3 s (`motion_tokens.json ui.tutorial_hint_ring`) |

### 9.5 Wireframes (1080×1920; x and y in px)

**Main view.**
```
x  0 24 48                            540                       1032 1056 1080
y 0 +---------------------------------------------------------------------+  Z0 status bar (sky bleeds under)
144 |  +-----------------------+               +--------+  +--------+      |  dew chip 48..48+w (passive)
    |  | [dew]  12,345         |               | [sun]  |  | [eye]  |      |  time chip 768..888 (passive, label peeks left)
264 |  +-----------------------+               +--------+  +--------+      |  eye 912..1032, hit 864..1080 x 144..360
336 |. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . |  Z2 look: sky, sun/moon, hills, optional taps
    | [willow canopy y 321-831]        sun day (780,380)       [L5 bough]  |
645 |    [chime branch]                                                    |  wind_chime anchors 280..368 x 645..657
758 | [mailbox]       far hills 610-790 / tree line 560-800                |
    |  (willow_root)(toadstool ring)   (hill_crest)  (moon_rock)  [stump]  |  crest 742..805
845 |===================== Z3 tend =========================================|
922 |                              [basket]                                |
989 |      (bed_4)                                         (bed_5)         |  beds hit 270x189
1085|  (fern)   (moss_cushion)   [SUN STONE] spot   (clover_bank)          |  FOCAL band 1056..1267
1267|    (bed_2)                   (bed_1 @1325)               (bed_3)     |
1344|  lanterns along the far bank   o    o    o    o    o    o    o    o   |  firefly_lantern anchors
1425|~~~~~~~~~~~~~~~~~~ brook (tap band from spots.json) ~~~~~~~~~~~~~~~~~~~|  stream_stones 540..929
1507|. . . . . . . . . . . near bank (lit meadow) . . . . . . . . . . . . . |
1541| +-------------------------------------------------------------------+ |  dock pill 24..1056 x 1541..1781, r 120
    | |  (Set)        ( GARDEN )          ( BASKET 3 )         (Album)    | |  plates: d168 @135, d216 @405, d216 @675, d168 @945
    | | Settings        Garden              Basket              Album     | |  hit rects 228x228 @ y 1547..1775
1781| +-------------------------------------------------------------------+ |
1793|. . . . . . . . . . . . . . Z5 gesture . . . . . . . . . . . . . . . . |
1920+---------------------------------------------------------------------+
```

**Garden sheet** (above the dock; scrim 0.24 over the world).
```
442 +---------------------------------------------------------------------+  sheet 24..1056 x 442..1517, live glass, r 96
    |                               ======                                |  grabber 120x12 @ y 464
490 |  Garden                                                ( x )        |  Title 84 @ x 72; close d108 @ 900..1008 x 526..634
670 |                                                                     |
718 |  +--------------------------------+--------------------------------+ |  segmented 72..1008 x 718..838 (hit 694..862)
    |  |            Flowers             |             Decor              | |  Decor tab ends with the Leaf boat row
838 |  +--------------------------------+--------------------------------+ |
886 |  +---------------------------------------------------------------+   |  item card 936x300 @ x 72..1008
    |  | +----------+  Sweet clover                3 of 10              |   |  well 252x252: live mini-render on leaf_tint
    |  | | (render) |  [d] 15     (drop)(drop)                          |   |  price chip + yield drops
    |  | |          |  Blooms in about 40 min                           |   |  Caption ink_2
    |  | +----------+  Loved by Puffmoss          [     Plant      ]    |   |  primary 300x132 bottom-right
1186|  +---------------------------------------------------------------+   |
1210|  +---------------------------------------------------------------+   |  next card (scrolls; 72 px fade mask)
1517+---------------------------------------------------------------------+  = dock top - 24
1541  (dock stays visible; Garden plate shows the active state)
```

**Album sheet.**
```
442 +---------------------------------------------------------------------+
490 |  Album   ( 7 / 12 )                                    ( x )        |  count chip: surface_hi pill 168x72, Label 42 ink
718 |  [   Friends   |    Photos    |   Postcards   ]                      |  segmented 3 x 312
886 |  +----------+   +----------+   +----------+                         |  friend cards 288x372 @ x 72 / 384 / 696
    |  | portrait |   | portrait |   | silhouet.|                         |  live fur shader, S 150, 30 fps
    |  | Puffmoss |   | Buttonbud|   | Not met  |                         |  name Label 42 @ y+252
    |  | vvv..    |   | v....    |   | hint...  |                         |  hearts 5x36 / hint Caption 36
1258|  +----------+   +----------+   +----------+                         |
1282|  row 2 ... (tap a card -> friend detail, `standard` push)           |  Photos: polaroids 288x336; Postcards: rows 936x168
1517+---------------------------------------------------------------------+
```

**Basket sheet.**
```
442 +---------------------------------------------------------------------+
490 |  Basket  ( 18 / 24 )                                   ( x )        |
694 |  (acorn cup 132)  Dew cup   [d] 23        The dew cup is brimming.  |  dew cup widget 694..856
880 |  [*][*][*][*][*][*][*][*]                                            |  8x3 tiles 108 px, gap 12, x 66..1014
    |  [*][*][*][*][*][*][*][*]                                            |  stamp 84 px; empty = ring + dot
1228|  [*][*][ ][ ][ ][ ][ ][ ]                                            |
1260|  +--------------------------------------------------------------+   |  primary "Collect all" 948x144 @ x 66..1014, y 1260..1404
    |  |                         Collect all                          |   |  items arc to the dew chip, stagger 30 ms
1404|  +--------------------------------------------------------------+   |
1517+---------------------------------------------------------------------+
```

**Settings sheet** (GDD §7.6 groups; scrolls; rows 156 px, separators `ink` @ 0.10).
```
490 |  Settings                                              ( x )        |
694 |  Comfort                                                            |  group caption 36 ink
742 |  Reduce motion                                          ( ==o )     |  toggle 156x90 @ x 852..1008; the whole row is the hit
898 |  Reduce transparency                                    ( o== )     |
1054|  Text size            ( A- )      130 %      ( A+ )                  |  stepper: 2 round buttons d132 (hit 180)
1210|  Hide buttons while I watch                             ( ==o )     |
1366|  Keep the screen on while I watch                       ( o== )     |
....|  Sound: Music [ On | Nature sounds only | Off ] (full-width row, 3 segments x 312)
....|        Music / Nature / Effects volume  [=======o-----]  80        |  slider track 624x12 @ x 300..924, thumb d72
....|        Mono audio ( o== ) ;  Sound captions ( o== )
....|  Touch: Haptics [ Off | Subtle | Full ] ;  Left-handed ( o== )
....|  Language [ Same as device | English | Tieng Viet ] ;  About >     |  About: privacy line, credits, licenses, version
```
- **Slider:** track 624×12 r-pill in `toggle_off_track` with a `primary` fill to the thumb; thumb Ø 72 `surface_hi` + e1; 11 detents (step 10) with a TICK per detent (Full). The row is the hit area; a drag starts after 24 px.
- **Long rows:** rows with long Vietnamese labels wrap to 2 lines and grow (minimum 156).
- **Segmented rows:** three-segment controls with long labels (Music, Language) take a full-width row under the label.

### 9.6 Layout behaviour
- **Left-handed:** mirrors the dock order and the HUD (eye and time chip on the left, dew chip on the right; the time label peeks to the right). The world is not mirrored.
- **Reduce Motion:** sheet rise → 150 ms crossfade; count rolls → a single fade.
- **Reduce Transparency:** all glass opaque.
- **Ambient watch** (eye button, or 60 s without input): HUD and dock fade out over 600 ms; the first tap only wakes them (`short` fade-in).
- **Idle:** after 8 s with no input the frame rate drops to 30 fps. There is no visual change.

---

## 10. Motion

### 10.1 Motion tokens (05 §0.2; ambient periods per synthesis C5)

| Token | Duration | Curve | Godot 4.7 | Use |
|---|---|---|---|---|
| `instant` | 0 ms | — | Set the property | Colour/state change on touch-down |
| `micro` | **100 ms** (80–120) | ease-out | `TRANS_QUAD`, `EASE_OUT` | Press to scale 0.95; toggle thumb |
| `release` | ≈ 330 ms settle | spring `pop` | Analytic spring, or `TRANS_BACK`+`EASE_OUT` | Button release, pickup |
| `short` | **200 ms** (150–240) | `cubic-bezier(0.2,0,0,1)` | Custom interpolator; fallback `TRANS_CUBIC`/`EASE_OUT` (err 0.13) | Fades, chips, icon swaps |
| `standard` | **320 ms** (280–360) | `(0.05,0.7,0.1,1)` | Custom; fallback `TRANS_EXPO`/`EASE_OUT` (err 0.155) | Elements entering or moving |
| `emphasized` | **500 ms** (450–600) | `(0.2,0,0,1)` or spring `move` | Custom or spring | New-friend card, reward reveal, postcard, décor settle |
| `exit` | 0.65 × enter | `(0.3,0,0.8,0.15)` | Fallback `TRANS_CUBIC`/`EASE_IN` (err 0.046) | Dismissals |
| `celebrate` | 900 ms (700–1200) | spring `pop` + sparkles | — | New species, unlocks; never blocks input > 1 s |
| `stagger` | 30 ms per item, cap 240 ms | — | `set_delay(i·0.03)` | Lists, reward items |
| `ambient` | 3–12.8 s loops | `(0.37,0,0.63,1)` | `TRANS_SINE`/`EASE_IN_OUT` (err 0.002) | Breathing, sway, glow. Periods 600/k: **3.00 / 4.84 / 7.89 / 12.77 s** (k 200/124/76/47) |
| `world` | 20–180 s | Linear or sine | — | Cloud drift, sun travel, weather crossfade (`world.json` 30 s) |
| `tod` | Device clock | OKLab | `Gradient.sample(g_day)` | Palette crossfade over 2400 s (`world.json`) |

Exact béziers go through `PropertyTweener.set_custom_interpolator()` with the tweener left at `TRANS_LINEAR` (05 §3.2 helper, verified on 4.7.2).

### 10.2 Spring tokens (mass 1; 05 §0.3, recomputed)

| Token | f (Hz) | ζ | k | c | Overshoot | Settle (2 %) | Use |
|---|---|---|---|---|---|---|---|
| `press` | 6.0 | 0.90 | 1421.2 | 67.86 | 0.15 % | 118 ms | Touch-down, finger tracking |
| `move` | 2.4 | 0.80 | 227.4 | 24.13 | 1.5 % | 332 ms | Panels, sheets, drag release |
| `pop` | 3.2 | 0.60 | 404.3 | 24.13 | 9.5 % | 332 ms | Rewards, release pop |
| `jelly` | 2.6 | 0.40 | 266.9 | 13.07 | 25.4 % | 612 ms | Creature body only, amplitude ≤ 12 % |
| `follow` | 1.6 | 0.35 | 101.1 | 7.04 | 30.9 % | 1137 ms | Ears, leaves, antennae, chimes, bells |

- **Integration:** analytic: each step applies the closed-form damped-oscillator solution over dt (`scripts/motion/spring.gd`), so it is exact at any frame rate, stable at 30 fps and through hitches, with no sub-steps; rest at |x| < 0.0005, |v| < 0.002 (`springs.integrator`).
- **Interruptibility:** every animation retargets from the current value *and velocity* (05 §3.1). `TRANS_SPRING` is never used for interactive motion.

### 10.3 Interaction → token map (GDD loops, `economy.json`, 06 SFX ids)

| Interaction | Visual | Audio / haptic |
|---|---|---|
| Touch-down (any) | `instant` tint +6 L* (lighter) + UI scale 0.96 in 80 ms (`micro` curve); world objects squash 0.94 | S01 / TICK (Full) |
| Release (tap) | `release` (`pop`) → 1.0; ring to 36 dp over 380 ms (α 0.35 → 0); sparkles 3–5 on rewarding taps only | — |
| Tap creature | Squash 0.94 → `jelly`; ears `follow`; look-at (`standard`); chirp bubble; name tag 2 s | S13 at `voice_step` / TICK (asleep: stirs, S14) |
| Long-press / stroke creature (pet) | Ring fill 150 → 450 ms; squash 0.88 on `jelly` + lean; release `jelly` (target 1.04) + 3 hearts; `celebrate` on a heart threshold | S03 loop / TICK every 120 ms (Full) |
| Tap bed / growing stem | Stems kicked 0.12 rad on `follow`; leaf rustle | S01 + S18 |
| Tap a ready bud | The bed's ready buds unfurl (`unfurl` 600 ms, 30 ms stagger, 3–5 sparkles; §6.2); auto after 20 s as a 2.4 s slow unfurl | S04; TICK at the end |
| Growth step in view | Stretch 1.08 (`move`); new parts `pop` + 300 ms fade | — |
| Buy flower (Plant) | Sheet `exit` (first copy: choose-a-bed mode, §9.4); seed arc 320 ms (`emphasized_decel`) to the stem; soil puff 120 ms (`pop`) | S05; TICK |
| Buy décor copy (Place) | Piece drops 40 px and settles over 500 ms (`emphasized`) with a 300 ms fade-in + 4-sparkle puff | S05; TICK |
| Collect all (basket) | Items arc to the dew chip, 500 ms each (`emphasized`), `stagger` 30 ms (cap 240); counter ticks 40 ms per step (max 600 ms) with `pop` 1.08; tiles fade (`short`) | S02 ascending ladder; DOUBLE |
| Dew counter change | Tick + `pop` 1.08 | — |
| Open sheet | Rise 96 px + fade, `standard` 320 ms; dock button → active state; scrim fade `short`; content `stagger` 30 ms | S07 |
| Close sheet / Back / same dock button | `exit` (≈ 210 ms); swipe-down tracks the finger (`press`); release decides by > 25 % of height or > 1000 px/s, then `move` | S08 |
| Swap sheet (other dock button) | 200 ms crossfade (`short`) | S07 |
| Switch tab (segmented) | Selection pill `move`; content crossfade `short` | S15 / TICK |
| Toggle | Thumb `micro`; track colour `short` | S15 / TICK |
| Select card | `micro` press; lift −6 px + e2 (`standard`); footer slides in (`standard`) | S01 |
| Postcard open / close (mailbox) | Flag pops; reader card `emphasized` (scale 0.92 → 1, rotate −2° → 0°, fade) / `exit` | S07 |
| Welcome back (recap) | Recap card `emphasized`; tap or 5 s → `exit` | S10; MEDIUM once |
| New friend (species debut) | World: spotlight halo + 5 sparkles (`celebrate` 900 ms). UI: new-friend card rises (`emphasized` 500 ms) and shrinks into the Album button on close; ≤ 1 s input block | S09; MEDIUM |
| Heart threshold / best friend | `celebrate` heart burst (5) | S09 |
| Creature arrives / leaves | 400 ms fade + hops (§5.7) | S12 |
| Creature naps | 1200 ms settle; z's every 4.84 s | S12 (low) |
| Stream tap | Ripple ring to 36 dp in 380 ms (eased out in-shader) + bubbles; nearby awake creatures glance | S06 |
| Leaf boat | Appears at the spring rock (`pop`), drifts 40 s; creatures gather to watch | S17 / TICK |
| Pinwheel tap | Spin burst, τ 1.2 s decay | S19 |
| Lantern tap | Brighten +60 % (200 ms in / 2 s hold / 1.2 s out, sine) + fireflies released | S20 |
| Chime tap | Per-tube impulse 8° on `follow`, staggered 40 ms | S21 (owned shells) |
| Mailbox (postcard waiting) | Flag raise `pop`; glow `ambient` k 76 | S16 on arrival; S07 on open |
| Weather change | `world` 30 s colour crossfade; particles via `ParticleBudget` (≥ 4 s fade); chip icon `short` + label peek 4 s | Bed crossfade (06) |
| Time-of-day change | `tod` 2400 s; chip icon `short` + label peek | Profile 90 s (06) |
| Ambient mode in / out | HUD fade 600 ms / `short` | — |
| Camera drift | `world` 45 s sine, ≤ 4 dp/s | — |
| Not affordable | Price chip pulse (`short`) + ±2 dp lateral nudge on `follow`; button reads "A little more dew"; never red | S11 (soft tok) |

### 10.4 Reduce Motion (`motion_tokens.reduce_motion`; X1)
- `g_motion` = 0.3 (scales all shader motion amplitudes).
- Spatial transitions → 150 ms crossfades.
- Springs critically damped (ζ 1.0, same f).
- Squash × 0.5; hops become glides.
- Parallax 0; no camera drift.
- Particles × 0.3.
- Ambient loops ≥ 4 s (breath k ≤ 150, grass k ≤ 150).
- Nothing flashes more than 3 times per second (always true).

---

## 11. Visual QA

### 11.1 Rubric (05 §5; score 1–10 each, 100 total)

| # | Criterion | 4 = prototype | 7 = solid | 10 = feature-worthy | Objective check |
|---|---|---|---|---|---|
| 1 | Value structure & focal hierarchy | Flat, competing focal points | Clear focal, some noise | Instant read at a squint | Blurred greyscale: focal = top local contrast; L* p5–p95 ≥ 55 (day) |
| 2 | Palette harmony | Ad-hoc colours | Token palette, a few clashes | Rich yet restrained; warm/cool split | k-means(8) colours within ΔE_OK ≤ 6 of a token; high-chroma area ≤ 10 % |
| 3 | Edge quality & AA | Jaggies, fringes, blurry text | Clean at 100 % | Crisp at 200 % zoom, with intentional soft/lost edges | No stair-steps or halos at 200 %; text is MSDF or rasterised at the right oversampling |
| 4 | Depth & atmosphere | 1–2 planes | 4 planes with haze | 6 planes, convincing air | Contrast to `sky_horizon` rises monotonically far → near |
| 5 | Lighting coherence | None, or contradictory | Consistent direction | Rims, tinted shadows, light pools that tell the time | Shadow offsets agree with `g_sun_dir`; no neutral-grey shadows |
| 6 | Motion quality | Linear, jerky, pops | Eased; ≥ 3 ambient layers | Springy, interruptible, alive yet calm | p95 frame time ≤ 16.7 ms; no linear spatial tweens; no onset without a fade; no *composite* scene repeat < 20 s |
| 7 | Touch feedback | Missing on some controls | Every control responds | Every touch delights (visual + haptic) | First visual change ≤ 100 ms (≤ 6 frames at 60 fps) on 100 % of taps |
| 8 | UI clarity & accessibility | Low contrast, cramped | WCAG AA | Effortless; glass legible over the worst background | Text ≥ 4.5:1, icons ≥ 3:1, targets ≥ 48 dp, idle HUD ≤ 20 % of area; Reduce Motion/Transparency work |
| 9 | Consistency | Mixed styles | One style, small drift | Every asset looks from one hand | Radii from tokens; one light direction; grain everywhere; same line rule |
| 10 | Polish & "Today tab" test | Placeholders | Complete | A random 1:1 crop works as key art | Blind A/B: rater picks it as a "store screenshot" against a 2026 store page from memory |

**Thresholds** (synthesis D13, V7):
- < 60 prototype; 70–79 soft-launch;
- **ship ≥ 80 with every criterion ≥ 7 and #1, #6, #8 ≥ 8**;
- feature-worthy ≥ 88 with every criterion ≥ 8.
- **R1 look-spike gate:** #3, #5, #6, #9 ≥ 7 before any content work.

### 11.2 Protocol (D13, C9, C10)
- **Capture set:**
  - 5 phases (`--tod` 0.2/0.4/0.6/0.8/1.0) × 2 screens (home; Garden sheet open);
  - + day rain + night with 5 lanterns;
  - + one 30 s idle video at 30 fps (`--write-movie`, `.movie` override 1080×2400);
  - all seeded and deterministic.
- **Render:** `xvfb-run … godot --rendering-driver opengl3_es --resolution 1080x2400` (stills via `capture.gd`). Raters score at **1080×2400, 1:1** (grain and dither vanish on downscaled PNGs, 05 §6).
- **Raters:** 3 independent raters, median score; a spread > 2 points triggers a review. Reports go to `qa/reports/`.
- **Automated pre-checks** (QA scripts; fail the build before human rating):
  - `art_data.py check` — 412 rules;
  - V2 (§11.3);
  - V4: Sobel edge map of a world-only frame (UI hidden), |∇L| > 0.04, box sizes 4–128 px, D ∈ [1.30, 1.50];
  - ladder: mean contrast to `sky_horizon` per layer mask;
  - squint: Gaussian σ = 2 % of width, greyscale, the focal box (sun stone ± 200 px) holds the max local-contrast tile;
  - k-means(8) ΔE_OK to tokens;
  - shadow-direction audit (shadow centroid offset sign vs `g_sun_dir` for every shadowed object);
  - device-only: p95 frame time and the ≤ 6-frame tap response (input injection).

### 11.3 V2 measurement (amendment A6 — needs Director ratification)
- **Dawn, day, golden:** synthesis V2 as written — ≥ 85 % of the area has HSV S ≤ 0.45 and V ≥ 0.45; accents ≤ 10 %. Mock results: 99.9 / 89.0 / 90.6 %.
- **Dusk, night:** the binding night palette has V < 0.45 by design (night sky V 0.22, ground 0.27), and HSV S overstates saturation of dark low-chroma colours (night sky S 0.70 at OKLCh C 0.061).
  - Measure ≥ 85 % of the area at **OKLCh C ≤ 0.10**, no pixel below L* 6, accents (C > 0.12) ≤ 10 %.
  - Mock of this layout: dusk 99.5 %, night 98.9 % (minimum L* 7.9).
- The low-arousal intent of 04 P6 (low saturation) holds at night. Brightness is low on purpose (05 §2.2, 02 §3 ambient mode).

### 11.4 Do / Don't

**Do:**
- Take every colour from `palettes.json`, through globals or instance uniforms.
- Ease every spatial move.
- Give every touch a visual answer on the next frame.
- Fade everything in over ≥ 300 ms.
- Keep one light direction per frame.
- Tint shadows (never grey or black).
- Dither every gradient, halo and glass surface.
- Anchor grain to objects.
- Keep the focal (sun stone) the highest local contrast.
- Leave 30–40 % of the frame calm.
- Vary repeats (scale ±8–15 %, rotation ±3–6°, hue ±4°, L* ±3).
- Place things by Poisson-disk in odd clusters.
- Put colour lines only on touchable things.
- Round every tip.
- Write `k/600` loops.
- Test at 200 % zoom and at 32 px thumbnails.
- Run `art_data.py check`.

**Don't:**
- Pure `#000` or `#FFF` in art (exceptions: the identity ambient and `surface_hi` text on primary/leaf).
- Black outlines, bevels, red badges or alarm red.
- Full-screen bloom, lens flare or chromatic aberration.
- Animated full-screen grain.
- Glass on glass.
- `ink_2` on glass.
- Linear spatial tweens.
- `TRANS_ELASTIC` or bounce on UI.
- Squash beyond 20 % (creatures ≤ 12 %).
- Screen shake or hit-stop.
- More than 3 flashes per second.
- Particle pop-in.
- Turbulence.
- More than 3 particle systems or 150 particles.
- `TIME` in shaders.
- `mediump` time or UV math.
- SubViewports for art.
- VRAM-compressed tone masks.
- SVG `<text>`.
- Filters other than `feGaussianBlur`.
- Sharp corners on friendly shapes.
- Lock icons or "neglect" visuals (wilted, dirty, sad).
- Colour as the only cue.
- Hard-coded positions that disagree with `spots.json`.

---

## 12. Implementation map and open issues

### 12.1 File map (by owner)

| Path | Contents |
|---|---|
| `shaders/inc/{noise,finish,world_light,lamps,sdf}.gdshaderinc` | §4.2 |
| `shaders/world/{sky,silhouette,meadow,grass,water,cloud,fg_frame}.gdshader` | §4.3–4.8, 4.16 |
| `shaders/props/prop_tone.gdshader` | §4.9 |
| `shaders/flora/flora_bed.gdshader` | §4.10 |
| `shaders/creature/mossling_fur.gdshader` | §4.11, §5 (start from `docs/art/reference/fur_spike.gdshader`) |
| `shaders/fx/{contact_shadow,halo_add,light_shaft,wander,particle_draw}.gdshader` | §4.12–4.15 |
| `shaders/ui/{glass_faux,glass_live,ring_fill}.gdshader` | §4.17–4.18 |
| `art/flora/flora_atlas.svg` (+ `.json` rects) | Flora stamps |
| `art/fx/fx_atlas.svg` | FX stamps |
| `art/props/*.svg` | Props and décor (tone masks) |
| `art/icons/*.svg` | Icons (DPITexture) |
| `scripts/world/{palette_driver,palette_math,weather_driver,celestial}.gd` (built; run by `scripts/autoload/time_of_day.gd`; the TimeDriver is `scripts/autoload/clock.gd`) + `{lamp_registry,shaft_controller,particle_budget}.gd` (to build) | Drivers and registries |
| `scripts/world/silhouette_builder.gd`, `scripts/flora/flora_builder.gd` | Geometry builders |
| `scripts/creature/{mossling,sdf_quad,rig_ids}.gd` | Creature node, quad, rig ids |
| `scripts/autoload/motion.gd` + `scripts/motion/{spring,spring_2d,cubic_bezier}.gd` (built) | Load `motion_tokens.json`; analytic springs; the 05 bézier helper |

### 12.2 Things other roles must know / unresolved

| # | Item | Owner |
|---|---|---|
| U1 | ~~Add the 26 globals (§4.1) to `project.godot [shader_globals]`~~ **Done** (37 globals in `project.godot`) | — |
| U2 | **Ratify V2 amendment A6** (dusk/night measured by OKLCh chroma) | Director |
| U3 | **F1 overdraw risk:** content ≈ 1.9–2.0× + blit ≈ 1.0 → ≈ 2.9–3.0 vs the 2.5 low-tier budget. Mitigation: opaque cores + governor tier 1 (§4.19). Measure on Mali-G52 / Adreno 610 before M1 | Tech Lead, QA |
| U4 | **Resolved:** `spots.json stream.water_width` (0.036) is a fraction of frame **height** (69 px), the same height as the tap band (`tap_band_y0..y1`, 0.748–0.784); GDD §10 now says so | — |
| U5 | The Z1 HUD band in `spots.json` ends at 336, but I2's 72 dp top hit needs 216 px → chip hits run to 360. Nothing else lives in 336–360 | GDD (note only) |
| U6 | **Resolved:** the `mailbox` hit (192 px) crossed the left edge (x −20, so only 57 dp was tappable). `mailbox` x 0.07 → 0.09 (97 px) and, to keep the 8 dp gap, `wind_chime_branch` and its 10 anchors x +0.02 (324 px). `validate_content.py` now fails any hit area that crosses a frame edge | — |
| U7 | Resolved by GDD §3.1: a stem becomes a glowing *ready bud* when its bloom time arrives on screen; tap unfurls (600 ms), otherwise it opens by itself after 20 s (2.4 s). Visuals in §6.2 | — |
| U12 | The GDD dock centres (x 135 / 945) put the outer 228 px hit rects at x 21–249 and 831–1059, inside the 48 px side margin. That is acceptable (bottom-edge targets, not side-edge drags), but QA should confirm no conflict with the Android back gesture | GDD, QA |
| U8 | Three species pairs differ by only one *part* (puffmoss/pebblepaw, puffmoss/moonpuff, honeyhum/dandelfluff). Pattern, size and eye type still separate them (Hamming ≥ 2 once pattern counts; checked by `art_data.py`). No change requested. If the 32 px album silhouette test fails for a pair, change one part of one species in `species.json`, then re-run `resolve` | GDD, QA |
| U9 | Wide-screen side extension (x −400..1480) must be honoured by the builders; `spots.json` positions stay in the 1080 column | Tech Lead |
| U10 | iOS GLES colour space and Android "vivid" modes (05 §6, R3, R15) are unverified; run the device colour check | QA |
| U11 | `opengl3_es` determinism for the fur spike frame was AE 0 over 2 runs (one data point toward R5); the full-scene double-render test is still needed | QA |
