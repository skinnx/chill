# 03: Tooling, Plugins, Asset Pipeline, QA and CI (Godot 4.7.2)

*Researcher: Tooling & Pipeline. Date: 2026-10-20. Engine reference: `/home/user/godotengine/godot` @ `4.7.2-stable` (ed1daf0, ThorVG 1.0.3).*

**Evidence tags.** **[V]** = verified in this container or in engine source (path given). **[S]** = external source (URL). **[J]** = my judgement. Probes used the locally built editor `bin/godot.linuxbsd.editor.x86_64` (`4.7.2.stable.custom_build.ed1daf0bf`); artefacts are listed in Appendix C.

---

## 0. Adopt list

| # | What | Kind | Verdict | Pin / version | Why it earns its place |
|---|---|---|---|---|---|
| 1 | **GUT** (bitwes/Gut) | GDScript addon, dev-only | **ADOPT** | tag `v9.7.1` = commit `aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605` (2026-07-09), branch `godot_4_7` | Its README names this release for "4.7.x". Runs headless with no flags, exits 1 on failure and writes JUnit [V] |
| 2 | **gdtoolkit** (`gdlint`, `gdformat`) | PyPI | **ADOPT** | `gdtoolkit==4.5.0` (latest on PyPI) | Parses 4.5–4.7 syntax: `@abstract`, `...rest`, typed `Dictionary[K,V]`, `@export_tool_button`, `@warning_ignore_start` [V] |
| 3 | **Nunito** (variable, `wght` 200–1000) | OFL font | **ADOPT** (UI/body) | `google/fonts` `ofl/nunito/Nunito[wght].ttf` @ `47d54ca` (2026-10-16). npm fallback `@fontsource-variable/nunito@5.3.0` | Covers all 147 Vietnamese letters [V]. Rounded terminals |
| 4 | **Baloo 2** (variable, `wght` 400–800) | OFL font | **ADOPT** (titles, numbers, buttons) | `ofl/baloo2/Baloo2[wght].ttf`, npm `@fontsource-variable/baloo-2@5.3.0` | Chunky and friendly. Covers Vietnamese [V] |
| 5 | Engine built-ins: `Tween`, `Input.vibrate_handheld(ms, amp)`, `DPITexture` SVG importer, `AudioStreamSynchronized`/`Playlist`/`Interactive`/`Randomizer`, MovieWriter, `--check-only` | engine | **ADOPT** | 4.7.2 | These replace juice, haptics, sound-manager and save plugins at no extra risk |
| 6 | Offline pipeline: Python 3.13 + numpy 2.5.3 (+ scipy 1.18.1 wheel), ffmpeg `libvorbis`, ImageMagick, fontTools 4.67 (`pyftsubset`) | tooling | **ADOPT** | as listed | Every tool is available here [V] |
| 7 | CI: official binaries from `godotengine/godot-builds` with SHA512 check. GitHub-hosted `ubuntu-24.04` already has JDK 17 and build-tools 36.1.0 | CI | **ADOPT** | Godot 4.7.2 | No third-party image needed (§7) |
| 8 | Godot State Charts (derkork) | addon | OPTIONAL (defer) | `v0.22.5` `76d226a` (2026-06-26) | Adopt only if creature/NPC logic needs more than about 5 states or parallel regions |
| 9 | Scalable Vector Shapes 2D | addon | OPTIONAL (one-day spike) | `3.1.0` `ee65712` (2026-10-17), declares "4.7" | Editable and animatable vector curves in-engine. Young project, 44 MB repo |
| 10 | Panku Console | addon, dev-only | OPTIONAL | HEAD `863324d` (2025-01-25) | On-device debug console. Must be excluded from release |
| — | gdUnit4, Phantom Camera, Dialogue Manager*, Beehave, SmartShape2D, Sound Manager, Input Helper, Dialogic, LimboAI, haptics/juice/save plugins | — | **REJECT** | — | Each is redundant, needs a native binary, or brings little value for a portrait idle game (§2) |

\*Dialogue Manager becomes OPTIONAL if the design adds written NPC dialogue.

---

## 1. Findings that change the plan

1. **GitHub release-asset downloads work here, contrary to the brief** [V]. `curl -L https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/SHA512-SUMS.txt` returns 302, then 200 from `release-assets.githubusercontent.com`. The templates `.tpz` is **1,281,349,702 B**. The CDN rejects suffix ranges (`bytes=-N`, HTTP 501; this breaks `remotezip` in its default mode, which can be avoided with `--disable-suffix-range-support` / `support_suffix_range=False`) but accepts explicit ranges (HTTP 206). So a ~20-line stdlib fetcher with CRC32 checks (Appendix A) pulls only the ~150 MB we need.
2. **Local exports already work in this container** [V], using templates in `/tmp/claude-research/xdg/data/godot/export_templates/4.7.2.stable/` (set `XDG_DATA_HOME=/tmp/claude-research/xdg/data`):
   - **Web** (`variant/thread_support=false`): 6 s, `index.wasm` 39.5 MB, `index.pck` 347 KB.
   - **Android debug APK** (arm64-v8a only): 12 s, 28.5 MB, signed with APK Signature Scheme v2 and v3. This works **without Google's SDK** (`dl.google.com` is unreachable): `apt install apksigner adb` (Ubuntu noble `apksigner 31.0.2-1ubuntu1`, `adb 1:34.0.4`), JDK 21, and a fake SDK dir where `$SDK/platform-tools/adb` and `$SDK/build-tools/36.1.0/apksigner` symlink to `/usr/bin` (lookup: `export_plugin.cpp::get_apksigner_path`).
3. **Android, iOS and Web (with "for mobile" VRAM compression) refuse to export unless `rendering/textures/vram_compression/import_etc2_astc=true`** (default `false`, `servers/rendering/rendering_server.cpp:3660`). On the CLI, Android prints an explicit "ETC2/ASTC texture compression is required for Android export…" line, but **the Web error is blank** ("due to configuration errors:" followed by nothing); both exit 1 [V: re-run in `/tmp/claude-verify-tooling/etc2test`]. Source: `platform/android/export/export_plugin.cpp:3148`, `platform/web/export/export_plugin.cpp:472`, `editor/export/editor_export_platform_apple_embedded.cpp:2293`. Put this in `project.godot` on day 1: the setting does not re-import textures that were already imported (`doc/classes/ProjectSettings.xml:3498`).
4. **SVG imports as a fixed raster by default.** The `texture` importer is registered first and wins the priority tie (`editor/editor_node.cpp:8511` vs `:8537`, `core/io/resource_importer.cpp` uses a strict `>` comparison). For crisp art on 2–3× screens, switch art SVGs to the **`svg` importer, which produces a `DPITexture`** (§4).
5. **Fredoka and Outfit lack Vietnamese** (103 and 97 of 147 letters missing) [V].

---

## 2. Addons: evaluation

Method: `ls-remote --tags`, shallow clone at the latest tag, read `plugin.cfg`/README/LICENSE, then a compile check (`--import` in a clean 4.7.2 project, then `ResourceLoader.load()` on every `.gd`). Result: **0 failures and 0 `Parse Error`** for State Charts, SVS2D, Dialogue Manager, Phantom Camera, Panku and Sound Manager [V]. Optional C# wrappers are ignored by the non-.NET editor; the recipe deletes them.

| Addon (repo) | Latest tag → commit (date) | Godot support (stated) | License | Pure GDScript | Addon size | Verdict and reason |
|---|---|---|---|---|---|---|
| **GUT** `bitwes/Gut` | v9.7.1 → aeb5d4f (2026-07-09) | README: 9.7.1 "(godot_4_7 branch) 4.7.x". `main` targets 4.6.x | MIT | yes (86 .gd) | 3.2 MB | **ADOPT**. Ran 3 tests in 0.42 s (1.6 s wall). A failing test gives exit 1. JUnit via `-gjunit_xml_file` (the directory must already exist, otherwise "Error 7") [V] |
| gdUnit4 `MikeSchulze/gdUnit4` | v6.2.2 → 0127a55 (2026-10-07) | README: v6.2.x for 4.5–4.7.1 | MIT | GDScript plus optional C# API | 4.4 MB (2.0 MB without `test/`) | **REJECT** (redundant with GUT). Works, but exits **103** in headless mode unless given `--ignoreHeadlessMode`. Has 480 scripts. Better scene-runner and input simulation, but we need only one framework [V] |
| Phantom Camera `ramokz/phantom-camera` | v0.11.0.3 → cb6e096 (2026-07-19) | "Godot 4 plugin" | MIT | yes plus C# | 2.2 MB | **REJECT**. Near-static portrait camera; `Camera2D` plus `Tween` is enough [J] |
| Dialogue Manager `nathanhoad/godot_dialogue_manager` | v4.1.0 → a719088 (2026-09-04) | "for Godot 4.6+" | MIT | yes plus C# | 1.3 MB | **REJECT for MVP**, OPTIONAL later if NPC chatter is designed. Compiles on 4.7.2 [V] |
| Godot State Charts `derkork/godot-statecharts` | v0.22.5 → 76d226a (2026-06-26) | 4.x | MIT | yes plus C# | 624 KB | **OPTIONAL (defer)**. Good debugger. An enum FSM is enough for an idle loop [J] |
| Beehave `bitbrain/beehave` | v2.9.3 → 773a5f6 (2026-08-18) | project file says 4.7 | MIT | yes | 676 KB | **REJECT**. Behaviour trees are overkill for ambient critters [J] |
| SmartShape2D `SirRamEsq/SmartShape2D` | v3.3.1 → a9cb0ac (2025-12-20) | badge 4.3, project 4.5 | MIT | yes | **14 MB** | **REJECT**. Built for textured terrain. We draw with SVG and shaders |
| Sound Manager `nathanhoad/godot_sound_manager` | v2.6.2 (annotated) → fd96cad (2024-04-18). HEAD 1c04158 (2026-03-29) | project 4.6 at HEAD (4.2 at tag v2.6.2) | MIT | yes plus C# | 48 KB | **REJECT**. An 80-line `Audio` autoload plus `AudioStreamPlaylist`/`Synchronized` covers it [J] |
| Input Helper `nathanhoad/godot_input_helper` | v4.7.0 (annotated tag object fb0aafe) → commit ccfad58 = HEAD (2025-06-08) | 4.4 | MIT | yes | — | **REJECT**. The game is touch-only, so there is no device or glyph switching to manage |
| Scalable Vector Shapes 2D `Teaching-myself-Godot/ez-curved-lines-2d` | 3.1.0 → ee65712 (2026-10-17) | project 4.7 | MIT | yes (57 .gd) | 44 MB (41 MB is `screenshots/`) | **OPTIONAL spike**. SVG → editable, keyframeable `Polygon2D`/`Line2D` curves. It is a runtime dependency, so adopt only if it beats hand SVG plus shaders |
| Panku Console `Ark2000/PankuConsole` | v1.7.9 → be716a5. HEAD 863324d (2025-01-25) | 4.3 | MIT | yes (98 .gd) | 1.1 MB | **OPTIONAL dev-only**. Compiles on 4.7.2 [V]. Exclude it from export presets |
| Dialogic `dialogic-godot/dialogic` | 2.x pre-release tags | 4.x | MIT | yes | large | **REJECT**. Heavy, and its v1 tags are for Godot 3 |
| LimboAI, godot-git-plugin | v1.8.1 / v3.3.0 | — | MIT | **no** (GDExtension or module binaries) | — | **REJECT** (not viable without binaries) |
| Haptics plugins | none found as pure GDScript | — | — | iOS/Android native only | — | **REJECT**. Built-in `Input.vibrate_handheld(duration_ms=500, amplitude=-1.0)` covers Android, iOS (CoreHaptics, `drivers/apple_embedded/apple_embedded.mm`) and Web; Android needs `permissions/vibrate=true` [V: `doc/classes/Input.xml`] |
| Juice/tween plugins (e.g. Anima `ceceppa/anima` 0.3.1). GTweens lives at `Guillemsc/GTweensGodot` (v6.0.0) but is **C#-only** (56 `.cs`, 0 `.gd`), so it cannot run in a non-.NET build | — | — | — | — | — | **REJECT**. Built-in `Tween` already has `TRANS_SPRING/BACK/ELASTIC`, `parallel()`, `set_loops()` and `tween_method()`. Write a ~100-line `Juice.gd` (pop, squash, float) [J] |
| Save helpers (e.g. AdamKormos/SaveMadeEasy, no tags) | — | — | — | — | — | **REJECT**. JSON via `FileAccess`: write `user://save.tmp`, `flush()`, `close()`, then `DirAccess.rename_absolute()` onto `user://save.json`, with a `"schema": N` field. Never call `get_var(true)` on `user://` data: the `FileAccess.get_var` docs warn of "remote code execution" [V: `doc/classes/FileAccess.xml:346`]. Do not load `.tres` from `user://` either, because resources can embed scripts [J; not stated in the class docs] |

### Install recipe (vendored, pinned, reproducible)

Commit addons into the repo; never fetch them at build time. Recommended `tools/vendor_addons.sh`:

```bash
#!/usr/bin/env bash
# Usage: tools/vendor_addons.sh   (run from repo root; re-run to update after bumping a pin)
set -euo pipefail
vendor() {  # <owner/repo> <tag> <expected commit sha> <subdir in repo>
  local tmp; tmp=$(mktemp -d)
  git clone -q --depth 1 --branch "$2" "https://github.com/$1.git" "$tmp"
  [ "$(git -C "$tmp" rev-parse HEAD)" = "$3" ] || { echo "SHA mismatch for $1@$2"; exit 1; }
  local name; name=$(basename "$4"); rm -rf "addons/$name"; mkdir -p addons
  cp -r "$tmp/$4" "addons/$name"
  find "addons/$name" \( -name '*.cs' -o -name '*.csproj' -o -name '*.sln' \) -delete
  rm -rf "addons/$name/test" "addons/$name/tests" "addons/$name/examples" "addons/$name/screenshots" "addons/$name/video_thumbnails"
  echo "$1 $2 $3" >> addons/VENDORED.txt; rm -rf "$tmp"
}
mkdir -p addons; : > addons/VENDORED.txt   # mkdir first: with set -e, ':>' fails on a fresh repo without addons/
vendor bitwes/Gut v9.7.1 aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605 addons/gut
# optional, only if adopted later:
# vendor derkork/godot-statecharts v0.22.5 76d226a3efac66a72aea825382b320c94808f409 addons/godot_state_charts
# vendor Teaching-myself-Godot/ez-curved-lines-2d 3.1.0 ee65712108b5aabbe7dfc2b5767991b9218543c5 addons/curved_lines_2d
```

- GUT runs from the CLI without being enabled as an editor plugin. Every export preset needs `exclude_filter="addons/gut/*, test/*, tools/*"` (verified in the Web/APK probe).
- Let the engine warn on our code only. **4.6** (not 4.7) replaced `exclude_addons` with `debug/gdscript/warnings/directory_rules`, whose default is `{"res://addons": 0}` = Exclude [V: `doc/classes/ProjectSettings.xml:566`, enum `Exclude,Include` in `modules/gdscript/gdscript.cpp:2880-2884`; absent in 4.5-stable docs, present in 4.6-stable]. An old `exclude_addons` key is migrated automatically (`gdscript_parser.cpp:106-112`). Recommended project settings (all default 0 = ignore): `debug/gdscript/warnings/untyped_declaration=1`, `…/unsafe_call_argument=1`, `…/unsafe_method_access=1`, `…/unsafe_property_access=1` (0 ignore, 1 warn, 2 error).

---

## 3. Fonts (rounded, cozy, Vietnamese and English)

Coverage was measured with fontTools on each full TTF. The test set is 147 code points: `a ă â e ê i o ô ơ u ư y` in both cases × 5 tones (NFC), plus `đ Đ ₫` [V].

| Font | Axes | Vietnamese missing | Full TTF size | Subset (Latin + Viet) TTF / WOFF2 | Role |
|---|---|---|---|---|---|
| **Nunito** | wght 200–1000 | **0** | 277 KB | 133 KB / **52 KB** | **UI/body** (use 400/600/800) |
| **Baloo 2** | wght 400–800 | **0** | 683 KB (includes Devanagari) | 128 KB / **46 KB** | **Titles, currency, buttons** |
| Quicksand | wght 300–700 | 0 | 125 KB | 87 KB / 39 KB | Alternative. Thin strokes, so stay ≥ 500 weight below 16 dp [J] |
| Lexend | wght 100–900 | 0 | 176 KB | 126 KB / 54 KB | Readability-tuned. Not very "rounded" |
| M PLUS Rounded 1c | static, 7 files | 0 | **3.4 MB per weight** | — | Reject (size) |
| Fredoka | wght, wdth | **103** | 159 KB | — | **Reject** |
| Outfit | wght | **97** | 111 KB | — | **Reject** |

**Godot 4.7 imports WOFF2** [V]:
- `ResourceImporterDynamicFont` recognises `ttf ttc otf otc woff woff2 pfb pfm` (`editor/import/resource_importer_dynamic_font.cpp:50-57`).
- WOFF2 needs Brotli: SConstruct has `brotli` default `True` (`SConstruct:195`) and `modules/text_server_adv/SCsub:538` defines `FT_CONFIG_OPTION_USE_BROTLI`.
- Render test: subset variable WOFF2 files with `FontVariation.variation_opentype = {wght: 800}` render Vietnamese correctly in Godot (stacked marks in "Ẫ Ỗ Ữ Ặ" are positioned correctly). Image: `/tmp/claude-research/tooling/out/fonts.png`.

**npm caveat** [V]. `@fontsource-variable/*@5.3.0` ships **only per-subset WOFF2** files (the static `@fontsource/*` packages add WOFF), **never TTF**. Vietnamese needs two of them: `nunito-latin-…` (230 code points, ASCII + Latin-1) and `nunito-vietnamese-…` (116 code points, no ASCII, but it already contains `ă đ ơ ư` and U+1EA0–1EF9). Together they cover all 147 test letters; `latin-ext` is not needed [V: fontTools cmap check]. Chaining via `Font.fallbacks` works, but kerning and shaping stop at file boundaries. **Prefer the full font from `google/fonts` via sparse clone** (works anonymously [V]):

```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/google/fonts.git /tmp/claude-research/gfonts
git -C /tmp/claude-research/gfonts sparse-checkout set --no-cone 'ofl/nunito/*' 'ofl/baloo2/*'
U="U+0000-00FF,U+0100-017F,U+0131,U+0152-0153,U+01A0-01A1,U+01AF-01B0,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0300-0309,U+0323,U+0329,U+1EA0-1EF9,U+2000-206F,U+20AB,U+20AC,U+2122,U+2190-2193,U+2212,U+2215,U+2605,U+2665"
pyftsubset "ofl/nunito/Nunito[wght].ttf" --unicodes="$U" --layout-features='*' --flavor=woff2 --output-file=assets/fonts/Nunito-vi.woff2
# ship OFL.txt next to each font (OFL-1.1 requirement)
```

npm fallback: `npm pack @fontsource-variable/nunito@5.3.0`, then use `package/files/nunito-{latin,vietnamese}-wght-normal.woff2` (Latin primary, Vietnamese as its `fallbacks` entry).

**Import settings** (`.woff2.import`; defaults verified at `resource_importer_dynamic_font.cpp:118-134`):
- `antialiasing=1` (Grayscale, the default). Never use LCD on rotating mobile screens [J].
- `hinting=0` (None) for rounded display faces on ≥ 2× screens [J].
- Keep `subpixel_positioning=4` (default) and `gui/fonts/dynamic_fonts/use_oversampling=true` (default). Oversampling only works with `display/window/stretch/mode="canvas_items"` (`ProjectSettings.xml:1260`). The setting's built-in default is `"disabled"`, but projects created by the 4.7 editor (project manager, or an empty `project.godot`) get `canvas_items` + `stretch/aspect="expand"` (`EditorNode::get_initial_settings`, `editor/editor_node.cpp:8345-8350`). Set both explicitly anyway [V].
- For text animated by scale tweens ("+12 ☘" pops), make a **separate MSDF import**: `multichannel_signed_distance_field=true`, `msdf_pixel_range=8`, `msdf_size=48` (defaults). Scaling then stays sharp without re-rasterization [V options; J use].
- Turn off `allow_system_fallback` so device fonts never leak in [J].
- QA string: `"Vườn Mây Nhỏ — Ẫ Ỗ Ữ Ặ Ỵ đ ₫ 1.250"`. Give Vietnamese lines about +10–15 % line spacing to fit stacked marks [J].

---

## 4. SVG via ThorVG in 4.7.2

**Build facts** [V]:
- ThorVG **1.0.3** (`thirdparty/README.md`).
- Godot vendors only these loaders: `svg`, `raw`, `external_png`, `external_webp`, `external_jpg` (`thirdparty/thorvg/update-thorvg.sh:69-74`). There is **no TTF loader**, so SVG `<text>` cannot render.
- Maximum raster size is 16384 px per side (`modules/svg/image_loader_svg.cpp:95`).

**Feature probe.** Four SVGs were rasterized at 1× and 3× through `Image.load_svg_from_string()`, which is the same path the importer uses. Montage: `/tmp/claude-research/tooling/out/montage.png`.

| Feature | Result |
|---|---|
| `linearGradient`, `radialGradient`, `stop-opacity` | ✅ correct |
| `opacity`, `fill-opacity`, `transform` (translate, rotate), nested `<g>` | ✅ |
| `stroke-linecap/linejoin=round`, `stroke-dasharray` | ✅ |
| `<style>` with class selectors (`.leaf{…}`) | ✅ |
| `clipPath` | ✅ |
| `mask` (luminance) | ✅ (cut exactly at the mask edge) |
| `filter` + `feGaussianBlur` | ✅ soft shadow rendered. Baked at import time; the blur scales with import scale |
| `<text>` | ❌ **renders nothing**. It is parsed (`_createTextNode`), but no font loader is vendored. Convert text to paths, or use Godot `Label` |
| Other filters (`feDropShadow`, `feOffset`, `feColorMatrix`) | ❌ not in the parser tag table. In `tvgSvgLoader.cpp:2140-2152`, `graphicsTags[]` lists shapes, `use`, `image` and `text`; its **only filter primitive is `feGaussianBlur`**. Avoid the others |

**Two importers** [V]:
- `texture` importer (the default, produces `CompressedTexture2D`). Options include `svg/scale` (0.001–100, default 1.0) and `editor/scale_with_editor_scale`, plus the usual `compress/mode`, `mipmaps/generate` and `process/fix_alpha_border` (default **true** for 2D). It rasterizes once at `round(w·scale)`.
- `svg` importer (produces **`DPITexture`**, `.dpitex`). Options: `base_scale=1.0`, `saturation=1.0`, `color_map={}`, `fix_alpha_border=false`, `premult_alpha=false`, `compress=true`. It **re-rasterizes to match viewport oversampling** in `canvas_items` stretch mode. The class is marked `experimental` in `doc/classes/DPITexture.xml`.
- **Measured:** with a 540×960 viewport shown in a 1080×1920 window (2×), the 99th-percentile edge gradient was 24 for `texture`@1× and **38 for `DPITexture`**. The DPITexture render is visibly crisp (`/tmp/claude-research/tooling/out/dpi_crop.png`).
- To select the importer, commit a minimal `.import` file. On first import the editor fills in the rest:
  ```ini
  [remap]
  importer="svg"
  [params]
  base_scale=1.0
  fix_alpha_border=true
  ```
- Runtime generation works: `DPITexture.create_from_string(svg, scale, saturation, color_map)` and `Image.load_svg_from_string(svg, scale)`. Generate procedural plants as SVG strings at load time, never per frame [J].

**Authoring rules for hand-written game art** [J unless noted]:
1. **Units.** Use `viewBox` units equal to design-viewport pixels at the reference resolution, e.g. 1080-wide portrait = 3 px per dp on a 360 dp phone. Keep node `scale` ≈ 1.0. DPITexture follows viewport oversampling, not per-node scale, so for a bigger sprite raise `base_scale` instead of scaling the node.
2. **Static vs scalable.** Art that never resizes (backgrounds, big props) is cheaper via the `texture` importer with `svg/scale` = largest expected screen scale (e.g. 1.5) and `mipmaps/generate=true`. `svg/scale` also enlarges the texture's size in 2D (`ResourceImporterTexture.xml:170`), so set the node `scale` to `1/svg_scale`. Mipmaps are only sampled with `texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS` [V doc]. Use DPITexture for UI and icons.
3. **Line weight.** Minimum stroke 3 design px (1 dp). Snap horizontal and vertical edges to whole pixels. Use `stroke-linejoin="round"` and `stroke-linecap="round"` everywhere; that reads as cozy.
4. **Gradients.** Large-area gradients band at 8 bit; the banding is visible in `/tmp/claude-research/tooling/out/caps.png`. Do sky and backdrop gradients in a `canvas_item` shader with ±0.5/255 dither noise. Keep SVG gradients for small props.
5. **Self-contained files.** No external `href` images, no CSS beyond class selectors, no `<text>`, no filters except `feGaussianBlur`. Split hinge parts (leaf, stem, pot) into separate SVGs and animate them in `AnimationPlayer`.
6. **Palette swaps.** Use DPITexture `color_map` (Color→Color) for seasons and day/night recolours instead of duplicating files [V option].
7. **Alpha edges.** DPITexture defaults to `fix_alpha_border=false`. Set it to true, or use `premult_alpha=true` with `CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA`, to avoid dark fringes [V doc].

---

## 5. Procedural audio pipeline (numpy → WAV/OGG → Godot)

**Verified toolchain:**
- ffmpeg has `libvorbis`, `libopus`, `ebur128` and `loudnorm`. numpy is 2.5.3. scipy installs from PyPI (`scipy-1.18.1-cp313…manylinux` wheel downloaded) [V].
- End-to-end probe `/tmp/claude-research/scripts/synth_probe.py`: a 72 BPM × 8-beat loop of exactly 294,000 samples at 44.1 kHz, written as WAV with a `smpl` loop chunk and encoded with `-q:a 4`.
  - The probe wrote `dwEnd = N−1` (RIFF convention: last sample played). Godot reports `loop_mode=1` (Forward) and `loop_end=293999`, both at runtime (`AudioStreamWAV.load_from_file`) and when imported. Because of Godot's loop semantics (see the table below), this loop is **one frame short**.
  - The OGG length is 6.6666665 s, exact to the sample [V].

**Engine facts** [V, `doc/classes/*.xml` and source]:

| Item | Value |
|---|---|
| Mix rate | `audio/driver/mix_rate` default **44100** (`servers/audio/audio_server.h:170`) |
| WAV import | `compress/mode` default **2 = Quite OK Audio (QOA)**. Modes are PCM, IMA-ADPCM (forward loop only, no seek) and QOA. Also `edit/loop_mode` (0 = Detect From WAV, 1 Disabled, 2 Forward, 3 Ping-Pong, 4 Backward), `edit/loop_begin=0`, `edit/loop_end=-1`, `edit/trim=false`, `edit/normalize=false`, `force/mono=false`, `force/max_rate=false` (so `force/max_rate_hz=44100` has no effect unless enabled) |
| WAV `smpl` chunk | read by `scene/resources/audio_stream_wav.cpp:~858`. Loop types 0/1/2 map to forward, ping-pong and backward. The forward-loop period is **`loop_end − loop_begin` frames** (`offset >= loop_end` → wrap, `:307-326`), and the mixer **reads frame index `loop_end`** before it wraps (no data padding). Measured with a 1000-frame 16-bit PCM ramp (MovieWriter capture, `/tmp/claude-verify-tooling/wavloop`): **`loop_end=999`** → period 999 (frame 0 is skipped after the first pass); **`loop_end=1000` with 1000 frames** → period 1000, but it plays **one garbage out-of-bounds frame** (−29506 here, a full-scale click) every loop. **Seamless recipe:** write N+1 frames, with frame N a copy of frame 0, and set `dwEnd = N` (`loop_end = N`). The period is then exactly N, with no out-of-bounds read [V]. Re-check with QOA (the import default); only PCM was tested |
| OGG import | `loop=false` (set it **true** in `.import`; Ogg tags are not read for looping), `loop_offset` in seconds, and `bpm`, `beat_count`, `bar_beats=4` for interactive sync |
| Adaptive music | `AudioStreamSynchronized` (layered stems, `set_sync_stream_volume`), `AudioStreamPlaylist` (`fade_time=0.3`, `shuffle`, `loop=true`), `AudioStreamInteractive` (clip transitions) live in `modules/interactive_music/`. `AudioStreamRandomizer` offers `random_pitch`, `random_pitch_semitones` and `random_volume_offset_db` |

**Recipe** [S/J as marked]:

| Asset class | Format | Settings |
|---|---|---|
| Music stems (60–80 BPM, layered) | OGG Vorbis stereo 44.1 kHz | `-c:a libvorbis -q:a 4`. These are **nominal header bitrates** (`ffprobe` `stream=bit_rate`, not measured): q2 = 96k, q3 = 112k, q4 ≈ 128k, q5 = 160k, q6 = 192k stereo, q3 mono = 80k. Vorbis is VBR: on the sparse 6.67 s probe loop the actual rate was only **33–39 kbps** (q2–q6 file sizes 27.6–32.8 KB) [V] |
| Ambience beds (rain, wind, birds) | OGG q3 stereo, ≥ 30 s loops | Crossfade the seam (see below). Mono q3 (80 kbps) when width is not needed |
| SFX (taps, coins, pops) | 16-bit mono WAV 44.1 kHz | Import with QOA (default) and `edit/trim=true`. Build 3–5 variants and feed them to `AudioStreamRandomizer` (`random_pitch_semitones=1.0`, which is equivalent to `random_pitch` ≈ 1.0595 = 2^(1/12) because the two setters are coupled; `random_volume_offset_db=1.5`) [V API; J values] |
| Short sample loops | WAV with `smpl` chunk | Detected automatically. Use the guard-frame recipe above [V] |

- **Exact-length tempo loops.** Choose BPM values where `44100·60/BPM` is an integer: 60 → 44100, 70 → 37800, **72 → 36750**, 75 → 35280, 84 → 31500 samples per beat. Make every LFO period divide the loop length.
- **Seamless seam.** Render N + T samples, mix the last T into the first T with an equal-power fade (T ≈ 50–200 ms for ambience), and keep N. For WAV loops, append a copy of frame 0 as frame N (guard frame, see the table above).
- **16-bit conversion.** Apply TPDF dither of ±1 LSB [J].
- **Loudness.** Master each music or ambience file to **−18 LUFS integrated ±2 LU, true peak ≤ −1 dBTP**, the portable/handheld target attributed to Sony ASWG (PS Vita) and the IESD. **[FLAGGED]** None of the three source URLs could be fetched from this container (DNS failure), so these values are not re-verified here; they match report 06's reading of the Garry Taylor interview. The Audiokinetic URL path is unconfirmed. Sources: [IESD Mix Ref Levels](https://www.audiogang.org/wp-content/uploads/2015/04/IESD-Mix-Ref-Levels-v03.02.pdf), [Audiokinetic: Mastering a game with Wwise](https://audiokinetic.com/en/mastering-a-game-with-wwise-part1), [Designing Sound interview with Garry Taylor](https://designingsound.org/2012/07/30/video-games-and-loudness-standards-interview-with-sonys-garry-taylor/).
  - Measure: `ffmpeg -nostats -i x.wav -af ebur128=peak=true -f null -`.
  - Normalise with **two passes**. Pass 1: `-af loudnorm=I=-18:TP=-1.5:LRA=11:print_format=json -f null -`. Pass 2: the same filter plus `measured_I/measured_TP/measured_LRA/measured_thresh/offset` and `linear=true`. Single-pass `loudnorm` runs in dynamic mode, because linear mode needs the measured values. **`loudnorm` outputs 192 kHz**, so always add `-ar 44100` [V: probe output was 192000 Hz].
  - The probe loop measured −11.5 LUFS (too hot), so normalising is required. Starting bus levels: Music −6 dB, Ambience −9 dB, SFX 0 dB, UI −3 dB [J], with `AudioEffectHardLimiter` on Master.
- **Synthesis methods** (all fine in numpy, plus scipy.signal filters):
  - FM bells and pads: Chowning 1973, *JAES* 21(7):526–534, "The Synthesis of Complex Audio Spectra by Means of Frequency Modulation".
  - Karplus–Strong plucks for kalimba and guitar: Karplus & Strong 1983, "Digital Synthesis of Plucked-String and Drum Timbres", *Computer Music Journal* 7(2):43–55, DOI 10.2307/3680062.
  - Filtered noise for rain and wind (`scipy.signal.butter` + `sosfilt`).
  - Schroeder comb/all-pass reverb: Schroeder 1962, "Natural Sounding Artificial Reverberation", *JAES* 10(3):219–223. Alternatively, convolution with an exponentially decaying noise impulse response (`scipy.signal.fftconvolve`).
- `AudioStreamGenerator` exists for real-time synthesis, but per-sample GDScript is CPU-heavy on phones. Synthesize **offline** [J].

---

## 6. Automated QA

### 6.1 CLI facts (`main/main.cpp` help table, lines ~560–730) [V]

- `--headless` equals `--display-driver headless --audio-driver Dummy`. The renderer becomes dummy, so **headless runs cannot take screenshots**.
- `--write-movie <file>` turns on `--fixed-fps 60` unless you pass one (`main.cpp:1961-1969`; a later `--fixed-fps` overrides it) and forces the Dummy audio driver, non-threaded (`main.cpp:2829-2833`). A relative path resolves to `res://…`, and the target directory must already exist (`movie_writer_pngwav.cpp` `write_begin`). `editor/movie_writer/mix_rate` must be divisible by the FPS (48000/30 = 1600) [V doc]. Writers available: `.png` (PNG frames plus WAV, `servers/movie_writer/movie_writer_pngwav.cpp`, 8-digit frame suffix), `.avi` (MJPEG, `modules/jpg`) and `.ogv` (Theora, `modules/theora/editor/`, editor builds only). Project settings: `editor/movie_writer/mix_rate=48000`, `…/fps=60`, `…/video_quality=0.75`.
- User arguments go after `--` (read with `OS.get_cmdline_user_args()`).

### 6.2 Rendering under Xvfb (`Xvfb :99 -screen 0 1440x2560x24`) [V]

| `--rendering-driver` / `--rendering-method` | Device reported | 30-frame capture, 540×960 |
|---|---|---|
| `opengl3` / `gl_compatibility` | OpenGL 4.5 Core, Mesa 25.2.8 **llvmpipe** | ✅ ~2 s |
| `vulkan` / `mobile` | Vulkan 1.4.318, "llvmpipe" (lavapipe) | ✅ 2.4 s |
| `vulkan` / `forward_plus` | same | ✅ 2.1 s |

- **Determinism.** Two OpenGL runs gave **0 differing pixels**. GL vs Vulkan RMSE was **0.116 %**; mobile vs forward_plus was identical. To get this: `--fixed-fps 30`, `seed(12345)`, `GPUParticles2D.use_fixed_seed=true` with a fixed `seed`, fixed `--resolution`, and no wall-clock time in game logic.
- **Golden images must be pinned per renderer.** Use `opengl3` (Compatibility), which also covers the Web build [J].

**Screenshot recipe.** Wait N `process_frame`s, `await RenderingServer.frame_post_draw`, then `root.get_texture().get_image().save_png(path)` (Appendix B).
- **Movie recipe** (verified 90 frames in 3.7 s; GPU 3.07 ms/frame, PNG encode 24.7 ms/frame):
  ```bash
  mkdir -p qa/out/movie && touch qa/.gdignore   # .gdignore stops the editor importing frames and goldens
  DISPLAY=:99 godot --path . --rendering-driver opengl3 --resolution 540x960 \
    --write-movie qa/out/movie/f.png --fixed-fps 30 --quit-after 90 --scene res://main.tscn
  ffmpeg -framerate 30 -i qa/out/movie/f%08d.png -i qa/out/movie/f.wav -c:v libx264 -pix_fmt yuv420p -crf 18 -shortest qa/out/preview.mp4
  ```
- **Diff:** `compare -metric AE -fuzz 2% golden.png new.png diff.png`. Fail if more than 0.1 % of pixels differ [J]. Capture at 540×960 (16:9), 540×1170 (19.5:9) and 1080×2340 (3× physical) to check the safe area and expand-aspect layout.

### 6.3 Tests and static checks [V]

- **GUT:**
  ```bash
  godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit -gjunit_xml_file=res://reports/junit.xml
  ```
  Exit 0 on pass and 1 on fail. Defaults can live in `res://.gutconfig.json`; generate one with `-gprint_gutconfig_sample`. By default, engine errors, GUT errors and `push_error` fail tests (`failure_error_types=["engine","gut","push_error"]`, `addons/gut/gut_config.gd:57`). Narrow this with `-gfailure_error_types` or turn it off with `-gno_error_tracking`. `-gerrors_do_not_cause_failure` is deprecated ("Use failure_error_types instead.", `gut_config.gd:15`).
- **Import is not a parse gate.** `godot --headless --path . --import` exits 0, and it printed **no** `SCRIPT ERROR`/`Parse Error` for a script with a syntax error, whether or not the script had a `class_name` or was used by a scene [V: `/tmp/claude-verify-tooling/clitest`]. Grepping the import log therefore catches nothing. Run `--import` only to build the class cache, then type-check each file.
- **Per-file type check.** `godot --headless --path . --check-only -s res://x.gd` runs the analyzer. It exits 1 on a type error (`Cannot assign a value of type "String" as "int"`) or a syntax error, and 0 when clean (~0.2 s per file) [V]. **Caveat:** a script that uses an autoload also exits 1, with `Compile Error: Identifier not found: <Autoload>`, because autoloads are not instantiated under `-s`. **Fail CI on `Parse Error` lines only**, not on the exit code (see the YAML in §7).
- **gdtoolkit 4.5.0.**
  - `gdlint` passes a 4.5+ syntax sample: `@abstract class_name`, `@abstract func`, `func f(a, ...rest: Array)`, `Dictionary[StringName, int]`, `@export_tool_button`, `@warning_ignore_start/restore`, `match … when` guards, typed `for v: int in`. It passes engine tests `vararg_call.gd` and `typed_dictionaries.gd`.
  - The **only parse failure** found was a `;` after an `@abstract func` declaration (`modules/gdscript/tests/scripts/runtime/features/abstract_methods.gd`, lines 8 and 9). Do not use `;`.
  - On `vararg_call.gd`/`typed_dictionaries.gd`, `gdformat --check` exits 1 only because it "would reformat"; they still parse.
  - `gdformat` rewrites `@abstract\nclass_name X` to one line, which is valid.
  - Use `gdformat --check` in CI. `trait` is reserved but unimplemented in 4.7 (`gdscript_tokenizer.cpp:530`); re-check gdtoolkit when traits land.

---

## 7. CI/CD (GitHub Actions)

**Verified inputs:**
- Asset names on `godotengine/godot-builds` and `godotengine/godot` releases (WebFetch of `releases/expanded_assets/4.7.2-stable`): `Godot_v4.7.2-stable_linux.x86_64.zip` (77.9 MB), `Godot_v4.7.2-stable_export_templates.tpz` (1.28 GB), `SHA512-SUMS.txt`.
  - SHA512 of the editor zip: `9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65`.
  - SHA512 of the templates: `ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079`.
  - The templates install to `~/.local/share/godot/export_templates/4.7.2.stable/`; `templates/version.txt` contains `4.7.2.stable`.
  - Template members include `android_debug.apk` (127 MB), `android_release.apk` (105 MB), `android_source.zip`, `web_nothreads_{debug,release}.zip` (10.2 MB each), `web_{debug,release}.zip` and `web_dlink_*`.
- **Runner** (`ubuntu-24.04` image 20261012.334.1): JDK 17.0.20 is the default (`JAVA_HOME_17_X64`). `ANDROID_HOME=/usr/local/lib/android/sdk` has build-tools 34.0.0–**36.1.0** and 37.0.0, and platforms android-34 to 37.x, including android-36. Source: [runner-images Ubuntu2404 README](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md). Godot 4.7 itself wants target SDK **36**, build-tools `36.1.0`, Java 17 and min SDK 24 (`platform/android/java/app/config.gradle`, `export_plugin.cpp:303-305`). Editor settings `export/android/java_sdk_path` and `android_sdk_path` default to `$JAVA_HOME` and `$ANDROID_HOME` (`platform/android/export/export.cpp:58,61`). Keystore environment variables: `GODOT_ANDROID_KEYSTORE_{DEBUG,RELEASE}_{PATH,USER,PASSWORD}` (`export_plugin.h:47-52`).
- **Action tags verified by `git ls-remote`:** `actions/checkout@v7`, `actions/setup-python@v7`, `actions/setup-java@v6`, `actions/cache@v6`, `actions/upload-artifact@v7`, `actions/upload-pages-artifact@v5`, `actions/deploy-pages@v5`, `android-actions/setup-android@v4` (v4.0.4; default `cmdline-tools-version 15859902`).

**Alternatives considered:**
- `barichello/godot-ci:4.7.2` (Docker Hub, 2026-08-18, **2.58 GB** compressed): JDK 17, build-tools 33.0.2, NDK 25 (Dockerfile at git tag `4.7.2-stable`, the same commit as `4.7.1-stable`). Works, because `get_apksigner_path` prefers build-tools matching the target SDK, then 28 to target, then any version (`export_plugin.cpp:2713`), but it is slow to pull and adds a third-party trust root.
- `chickensoft-games/setup-godot@v2` (v2.4.3, 2026-10-01; `use-dotnet: false`, `include-templates: true`): its `src/` has **no checksum verification**.
- **Pick:** direct downloads, SHA512-verified and cached.

```yaml
# .github/workflows/ci.yml
name: ci
on: { push: { branches: [main] }, pull_request: {}, workflow_dispatch: {} }
env:
  GODOT_VERSION: "4.7.2"
  GODOT_BASE: https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable
  TPL_DIR: /home/runner/.local/share/godot/export_templates/4.7.2.stable
jobs:
  lint:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-python@v7
        with: { python-version: "3.13" }
      - run: pip install gdtoolkit==4.5.0
      - run: |
          files=$(git ls-files '*.gd' ':!:addons/**')
          gdlint $files && gdformat --check $files

  test:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - uses: actions/cache@v6
        with: { path: ~/godot, key: godot-editor-4.7.2 }
      - name: Install Godot (SHA512-verified)
        run: |
          if [ ! -x ~/godot/godot ]; then
            mkdir -p ~/godot && cd ~/godot
            curl -fsSLO "$GODOT_BASE/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
            curl -fsSLO "$GODOT_BASE/SHA512-SUMS.txt"
            grep " Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip$" SHA512-SUMS.txt | sha512sum -c -
            unzip -q Godot_v*_linux.x86_64.zip && mv "Godot_v${GODOT_VERSION}-stable_linux.x86_64" godot && rm -f ./*.zip
          fi
          echo "$HOME/godot" >> "$GITHUB_PATH"
      - name: Import + parse gate
        run: |
          godot --headless --path . --import   # builds .godot/ class cache; does NOT report parse errors
          fail=0
          for f in $(git ls-files '*.gd' ':!:addons/**'); do
            out=$(godot --headless --path . --check-only -s "res://$f" 2>&1 || true)
            if grep -q "Parse Error" <<<"$out"; then grep "Parse Error" <<<"$out"; echo "::error file=$f::GDScript parse error"; fail=1; fi
          done
          exit $fail
      - name: GUT
        run: |
          mkdir -p reports
          godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit -gjunit_xml_file=res://reports/junit.xml
      - name: Visual snapshots (Mesa llvmpipe)
        run: |
          sudo apt-get update -q && sudo apt-get install -y -q xvfb libgl1-mesa-dri mesa-vulkan-drivers imagemagick
          mkdir -p qa/out
          for r in 540x960 540x1170 1080x2340; do
            xvfb-run -a -s "-screen 0 1440x2560x24" godot --path . --rendering-driver opengl3 --audio-driver Dummy \
              --resolution $r --fixed-fps 30 -s res://tools/qa/capture.gd -- out=$PWD/qa/out/main_$r.png frames=90
          done
          bash tools/qa/compare_goldens.sh qa/out qa/goldens   # AE/fuzz 2%, fail >0.1% px; skip if no golden yet
      - uses: actions/upload-artifact@v7
        if: always()
        with: { name: qa-and-junit, path: "reports/\nqa/out/" }

  export:
    needs: [lint, test]
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-java@v6
        with: { distribution: temurin, java-version: "17" }
      - uses: actions/cache@v6
        with: { path: ~/godot, key: godot-editor-4.7.2 }
      - uses: actions/cache@v6
        id: tpl
        with: { path: /home/runner/.local/share/godot/export_templates/4.7.2.stable, key: godot-tpl-4.7.2-android-web }
      - name: Install Godot + templates (SHA512-verified)
        run: |
          [ -x ~/godot/godot ] || { echo "editor cache miss: run 'test' job first"; exit 1; }   # same cache key as test job
          echo "$HOME/godot" >> "$GITHUB_PATH"
          if [ "${{ steps.tpl.outputs.cache-hit }}" != "true" ]; then
            curl -fsSLO "$GODOT_BASE/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
            curl -fsSLO "$GODOT_BASE/SHA512-SUMS.txt"
            grep " Godot_v${GODOT_VERSION}-stable_export_templates.tpz$" SHA512-SUMS.txt | sha512sum -c -
            mkdir -p "$TPL_DIR"
            unzip -j -o ./*.tpz 'templates/version.txt' 'templates/android_*.apk' 'templates/web_nothreads_*.zip' -d "$TPL_DIR"
            rm -f ./*.tpz
          fi
      - name: Debug keystore
        run: keytool -genkeypair -keyalg RSA -keysize 2048 -validity 10000 -alias androiddebugkey -keypass android -storepass android -keystore "$RUNNER_TEMP/debug.keystore" -dname "CN=Android Debug,O=Android,C=US"
      - name: Export Android (debug APK) + Web
        env:
          GODOT_ANDROID_KEYSTORE_DEBUG_PATH: ${{ runner.temp }}/debug.keystore
          GODOT_ANDROID_KEYSTORE_DEBUG_USER: androiddebugkey
          GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD: android
        run: |
          godot --headless --path . --import
          mkdir -p build/android build/web
          godot --headless --path . --export-debug "Android" build/android/chill-debug.apk
          godot --headless --path . --export-release "Web" build/web/index.html
          test -s build/android/chill-debug.apk && test -s build/web/index.wasm
      - uses: actions/upload-artifact@v7
        with: { name: builds, path: build/ }
```

**Notes:**
- If a future runner image drops build-tools 36.1.0, add `android-actions/setup-android@v4` with `packages: "platform-tools build-tools;36.1.0"`.
- Release AAB for Play needs `gradle_build/use_gradle_build=true`, `--install-android-build-template` (installs `android_source.zip`), and keystore secrets in `GODOT_ANDROID_KEYSTORE_RELEASE_*`. Defer this past the MVP.
- iOS needs a macOS runner with Xcode (out of scope here) [J]. Web on GitHub Pages: `web_nothreads` needs no COOP/COEP headers; deploy with `upload-pages-artifact@v5` + `deploy-pages@v5`.

**Minimal `export_presets.cfg` keys proven locally** [V]:
- Web: `variant/thread_support=false`, `vram_texture_compression/for_mobile=true`, `html/canvas_resize_policy=2`.
- Android: `gradle_build/use_gradle_build=false`, `architectures/arm64-v8a=true` (add `armeabi-v7a=true` for older phones), `package/unique_name="com.<studio>.<game>"`, `screen/immersive_mode=true`, `permissions/vibrate=true`.
- Both: `include_filter=""` (the CLI errors if this key is missing), `exclude_filter="addons/gut/*, test/*, tools/*"`.
- Set `application/config/icon`; otherwise the APK export logs a non-fatal "No project icon specified" error.
- Commit an empty `build/.gdignore`. Without it, the editor imports the exported Web icons on the next scan: the probe's `build/web/` gained `index.icon.png.import` and similar files [V: `/tmp/claude-research/tooling/proj/build/web/`].

---

## Appendix A: `tools/ci/fetch_templates.py` (stdlib, ranged, CRC-checked) [V]

Use it locally to fetch the about 150 MB we need instead of 1.28 GB. Tested on `version.txt`, `web_nothreads_{debug,release}.zip` and `android_debug.apk`.

```python
#!/usr/bin/env python3
"""fetch_templates.py <ver> <dest_dir> <member>...  e.g. 4.7.2 ~/.local/share/godot/export_templates/4.7.2.stable templates/android_debug.apk"""
import sys, os, struct, zlib, urllib.request
ver, dest, members = sys.argv[1], sys.argv[2], sys.argv[3:]
url = f"https://github.com/godotengine/godot-builds/releases/download/{ver}-stable/Godot_v{ver}-stable_export_templates.tpz"
def rng(a, b):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"Range": f"bytes={a}-{b}"})) as f: return f.read()
with urllib.request.urlopen(urllib.request.Request(url, method="HEAD")) as f: size = int(f.headers["Content-Length"])
tail = rng(max(0, size - 65536), size - 1)              # suffix ranges -> HTTP 501 on GitHub's CDN
eocd = tail.rfind(b"PK\x05\x06")
_, _, _, _, n, cd_size, cd_off, _ = struct.unpack("<IHHHHIIH", tail[eocd:eocd + 22])
cd, entries, p = rng(cd_off, cd_off + cd_size - 1), {}, 0
for _ in range(n):
    (_, _, _, _, method, _, _, crc, csize, usize, nlen, xlen, clen, _, _, _, lho) = struct.unpack("<IHHHHHHIIIHHHHHII", cd[p:p + 46])
    entries[cd[p + 46:p + 46 + nlen].decode()] = (method, crc, csize, usize, lho); p += 46 + nlen + xlen + clen
for m in members:
    method, crc, csize, usize, lho = entries[m]
    nlen, xlen = struct.unpack("<HH", rng(lho, lho + 29)[26:30]); start = lho + 30 + nlen + xlen
    data = rng(start, start + csize - 1); data = zlib.decompress(data, -15) if method == 8 else data
    assert len(data) == usize and zlib.crc32(data) == crc, f"size/CRC mismatch: {m}"
    os.makedirs(dest, exist_ok=True); open(os.path.join(dest, os.path.basename(m)), "wb").write(data); print(m, usize)
```

## Appendix B: `tools/qa/capture.gd` pattern (verified on all three drivers)

```gdscript
extends SceneTree
# godot --path . --rendering-driver opengl3 --resolution 540x960 --fixed-fps 30 -s res://tools/qa/capture.gd -- scene=res://main.tscn out=/abs/shot.png frames=90
func _initialize() -> void:
	var args := {"scene": "res://main.tscn", "out": "user://shot.png", "frames": "60"}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2: args[kv[0]] = kv[1]
	seed(12345)
	root.add_child((load(args.scene) as PackedScene).instantiate())
	for i in int(args.frames):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args.out)
	print("saved ", args.out, " ", RenderingServer.get_current_rendering_driver_name())
	quit()
```

## Appendix C: probe artefacts

Probes: `/tmp/claude-research/tooling/{proj,proj2,proj3,out}` (tests/SVG/fonts/audio/export presets, addon compile check, DPITexture, images). Fetched templates, keystore and editor settings are in `/tmp/claude-research/xdg/`; reuse them with `XDG_DATA_HOME=/tmp/claude-research/xdg/data XDG_CONFIG_HOME=/tmp/claude-research/xdg/config`. The fake Android SDK is `/tmp/claude-research/android-sdk`.

---

## Verification log

*Adversarial fact-check, 2026-10-20. Engine claims were checked against `/home/user/godotengine/godot` @ `4.7.2-stable` (ed1daf0). Runtime claims were re-run with `bin/godot.linuxbsd.editor.x86_64` in `/tmp/claude-verify-tooling/` (projects `etc2test`, `clitest`, `svgimp`, `wavloop`). Repo facts were checked with `git ls-remote` or shallow clones. Web citations used WebFetch: the runner-images README worked, but the audio-loudness sites and Crossref were unreachable. 104 claims were checked: 75 OK, 26 FIXED, 3 FLAGGED.*

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | GitHub release assets download anonymously (302 → 200) | OK | `curl -L …/4.7.2-stable/SHA512-SUMS.txt` → 200 from `release-assets.githubusercontent.com` |
| 2 | `.tpz` = 1,281,349,702 B; editor zip 77.9 MB | OK | HEAD `Content-Length` 1281349702 / 77860424 |
| 3 | Suffix ranges → 501, explicit ranges work | OK | `Range: bytes=-100` → 501; `bytes=0-99` → 206 |
| 4 | "breaks remotezip" | FIXED | Only in the default mode; `remotezip.py:201,254`, CLI `--disable-suffix-range-support` |
| 5 | "33-line" fetcher works | FIXED / OK | Script is 21 lines; it fetched `templates/version.txt` = `4.7.2.stable` |
| 6 | SHA512 of editor zip and templates | OK | Matches `SHA512-SUMS.txt` lines exactly |
| 7 | Template member sizes (android_debug 127 MB, release 105 MB, web_nothreads 10.2 MB) | OK | Central-directory listing via ranged reads |
| 8 | ETC2/ASTC needed for Android/Web export | OK | `platform/android/export/export_plugin.cpp:3148`, `platform/web/export/export_plugin.cpp:472` |
| 9 | "CLI error is blank" | FIXED | Android prints an explicit ETC2/ASTC message (cmdline-mode branch, `:3150-3152`); only Web is blank. Re-run: both exit 1 |
| 10 | iOS also requires ETC2/ASTC | FIXED (added) | `editor/export/editor_export_platform_apple_embedded.cpp:2293` |
| 11 | `import_etc2_astc` default false | OK | `servers/rendering/rendering_server.cpp:3660` |
| 12 | Texture importer wins SVG by registration order and strict `>` | OK | `editor/editor_node.cpp:8511/8537`, `core/io/resource_importer.cpp:530`, default priority 1.0 (`resource_importer.h:126`) |
| 13 | Minimal `.import` (`importer="svg"`) yields DPITexture | OK | Re-run: `load()` → `DPITexture (64,64) fix_alpha_border=true` |
| 14 | SVG importer options and defaults | OK | `editor/import/resource_importer_svg.cpp` `get_import_options` |
| 15 | `svg/scale` 0.001–100 default 1; `fix_alpha_border` default true for 2D | OK | `resource_importer_texture.cpp:251,264` |
| 16 | DPITexture `experimental`; `create_from_string(source, scale, saturation, color_map)` | OK | `doc/classes/DPITexture.xml:2,12-20` |
| 17 | `Image.load_svg_from_string(svg_str, scale=1.0)` | OK | `doc/classes/Image.xml:406` |
| 18 | `svg/scale` art can stay at node scale 1 | FIXED | `svg/scale` changes the 2D size (`ResourceImporterTexture.xml:170`); compensation and mipmap filter added |
| 19 | ThorVG 1.0.3; loaders svg/raw/png/webp/jpg | OK | `thirdparty/README.md:1089`, `thirdparty/thorvg/update-thorvg.sh:69-74` |
| 20 | Max raster 16384 px | OK | `modules/svg/image_loader_svg.cpp:95` (scales down with a warning) |
| 21 | "`graphicsTags[]` lists only feGaussianBlur" | FIXED | The table also lists shapes, `use`, `image` and `text`; `feGaussianBlur` is its only filter primitive (`tvgSvgLoader.cpp:2140-2152`) |
| 22 | `<text>` renders nothing | OK | Parsed (`_createTextNode`), but no font loader is vendored; probe `probe_text@*.png` is blank |
| 23 | DPITexture `color_map`, `premult_alpha` + `BLEND_MODE_PREMULT_ALPHA` | OK | `DPITexture.xml:53-62`, `CanvasItemMaterial.xml:48` |
| 24 | Font importer extensions | OK | `editor/import/resource_importer_dynamic_font.cpp:50-57` |
| 25 | WOFF2 via Brotli | OK | `SConstruct:195`, `modules/text_server_adv/SCsub:538` |
| 26 | Font import defaults (AA 1, hinting 3, subpixel 4, MSDF 8/48, system fallback on) | OK | `resource_importer_dynamic_font.cpp:117-131` |
| 27 | Oversampling needs `canvas_items`; default `disabled` | FIXED | Built-in default is `disabled`, but new 4.7 projects get `canvas_items` (`editor_node.cpp:8345-8350`) |
| 28 | `FontVariation.variation_opentype` with name keys | OK | `doc/classes/FontVariation.xml:82` |
| 29 | Vietnamese coverage: Nunito/Baloo 2/Quicksand/Lexend 0 missing; Fredoka 103; Outfit 97 | OK | Re-measured with fontTools on `google/fonts@47d54ca` (147-letter set) |
| 30 | Font axes and file sizes; M PLUS Rounded 1c 7 × ~3.5 MB | OK | fontTools `fvar`; `stat` |
| 31 | Subsets: Nunito 133 KB / 52 KB, Baloo 2 128 KB / 46 KB | OK | Re-run `pyftsubset`: 132,836 / 52,472 and 127,816 / 45,820 B |
| 32 | `@fontsource*` ship WOFF2/WOFF | FIXED | `@fontsource-variable/nunito@5.3.0` has 10 files, all `.woff2` |
| 33 | Vietnamese needs 3 fontsource subsets | FIXED | `latin` + `vietnamese` cover all 147 (fontTools cmap union) |
| 34 | fontsource 5.3.0 is the latest | OK | `npm view` |
| 35 | GUT v9.7.1 = `aeb5d4f…`, branch `godot_4_7`, README "4.7.x", MIT | OK | `git ls-remote` (lightweight tag = `refs/heads/godot_4_7`); README line 27; `addons/gut/LICENSE.md` |
| 36 | GUT JUnit dir must exist ("Error 7") | OK | `/tmp/claude-research/tooling/gut2.log` |
| 37 | GUT opt-out `-gerrors_do_not_cause_failure` | FIXED | Deprecated (`gut_config.gd:15`); defaults `failure_error_types` (`:57`), `-gno_error_tracking` |
| 38 | gdUnit4 v6.2.2 `0127a55`, exit 103 headless, 480 scripts, 4.4 MB / 2.0 MB, README 4.5–4.7.1 | OK | ls-remote; `GdUnitTestSessionRunner.gd:21`; `find`/`du`; README:40 |
| 39 | Phantom Camera, Dialogue Manager, State Charts, Beehave, SmartShape2D tags/commits/dates/licences | OK | ls-remote + `git log -1` in clones; `project.godot` features |
| 40 | Sound Manager "project 4.6" | FIXED | 4.6 at HEAD `1c04158`; 4.2 at tag v2.6.2 |
| 41 | Input Helper v4.7.0 → `fb0aafe` | FIXED | `fb0aafe` is the annotated tag object; the commit is `ccfad58` (= HEAD) |
| 42 | SVS2D 3.1.0 = `ee65712…` (2026-10-17), 4.7, 57 .gd, 44 MB (41 MB screenshots) | OK | Shallow clone at tag; `du` |
| 43 | Panku v1.7.9 `be716a5`, HEAD `863324d` (2025-01-25), 4.3, 98 .gd | OK | ls-remote; clone |
| 44 | Dialogic 2.x pre-release tags | OK | Tags `2.0-alpha-1` to `-20`; v1.x tags for Godot 3 |
| 45 | LimboAI v1.8.1 | OK | ls-remote |
| 46 | godot-git-plugin v3.2.1 | FIXED | Latest tag is v3.3.0 |
| 47 | GTweens "unreachable" | FIXED | `Guillemsc/GTweensGodot` clones fine (v6.0.0) but is C#-only |
| 48 | SaveMadeEasy has no tags; Anima 0.3.1 | OK | ls-remote |
| 49 | `vibrate_handheld(duration_ms=500, amplitude=-1.0)`, Android/iOS/Web, VIBRATE permission, CoreHaptics | OK | `doc/classes/Input.xml:807-819`; `CHHapticEngine` in `drivers/apple_embedded/apple_embedded.mm` |
| 50 | FileAccess docs warn about `.tres` | FIXED | The warning is on `FileAccess.get_var(allow_objects)` (`FileAccess.xml:346`); the `.tres` rule is now [J] |
| 51 | `DirAccess.rename_absolute`, `FileAccess.flush` exist | OK | `DirAccess.xml:368`, `FileAccess.xml:96` |
| 52 | Vendor script runs on a fresh repo | FIXED | `: > addons/VENDORED.txt` ran before `mkdir`, so `set -e` aborted; SVS2D folders `tests`/`examples` were not stripped |
| 53 | `directory_rules` introduced in 4.7 | FIXED | Absent in `4.5-stable` docs, present in `4.6-stable` (sparse clones) |
| 54 | `directory_rules` default `{"res://addons": 0}` = Exclude; the four warnings default 0 | OK | `modules/gdscript/gdscript.cpp:2880-2884`; `ProjectSettings.xml:660-675` |
| 55 | gdtoolkit 4.5.0 is latest and lints the 4.5+ syntax sample | OK | `pip index`; `gdlint` "Success" on a sample with `@abstract`, varargs, typed dict, tool button, `@warning_ignore_start`, `match…when` |
| 56 | Only failure: `;` after `@abstract func` (line 8) | OK (refined) | Lines 8 and 9 of `runtime/features/abstract_methods.gd` both fail |
| 57 | `gdformat` joins `@abstract` and `class_name` | OK | Diff shows `@abstract class_name Base` |
| 58 | `trait` reserved | OK | `modules/gdscript/gdscript_tokenizer.cpp:122,530` |
| 59 | Python 3.13 / numpy 2.5.3 / scipy 1.18.1 / fontTools 4.67 | OK | `python3 --version` 3.13.16; installed numpy 2.5.3 (PyPI latest is 2.5.4); `pip index` |
| 60 | ffmpeg `libvorbis`, `libopus`, `ebur128`, `loudnorm` | OK | `ffmpeg -encoders/-filters` |
| 61 | Vorbis bitrates "measured" | FIXED | Nominal header values; actual 33–39 kbps on the probe (`ffprobe`, file sizes) |
| 62 | `audio/driver/mix_rate` default 44100 | OK | `servers/audio/audio_server.h:170`, `audio_server.cpp:229` |
| 63 | WAV import defaults, enums, IMA-ADPCM forward-only / no seek | OK | `resource_importer_wav.cpp:78-89`; `ResourceImporterWAV.xml:17`; `audio_stream_wav.cpp:79-81` |
| 64 | `force/max_rate_hz=44100` listed as an active default | FIXED | Only applies if `force/max_rate=true` (default false, `:80`) |
| 65 | `smpl` loop types 0/1/2 | OK | `audio_stream_wav.cpp:858-870` |
| 66 | "loop_end exclusive; write dwEnd = N" | FIXED | Measured: N frames + `loop_end=N` reads one out-of-bounds frame (full-scale click); `loop_end=N−1` is one frame short; guard frame + `loop_end=N` is exact (`/tmp/claude-verify-tooling/wavloop`) |
| 67 | OGG import options; Ogg tags not used for looping | OK | `modules/vorbis/resource_importer_ogg_vorbis.cpp:76-80`; tags parsed only into `tags` (`audio_stream_ogg_vorbis.cpp:462-481`) |
| 68 | interactive_music classes; Playlist `fade_time=0.3`, `loop=true`, `shuffle`; `set_sync_stream_volume` | OK | `modules/interactive_music/doc_classes/*.xml` |
| 69 | Randomizer members; `random_pitch=1.06` ≈ ±1 semitone | OK (refined) | `AudioStreamRandomizer.xml:72-81`; 2^(1/12) = 1.0595 |
| 70 | Integer samples-per-beat table; 72 BPM × 8 = 294,000 = 6.667 s; 1/44100 = 22.7 µs | OK | Arithmetic |
| 71 | −18 LUFS ±2 LU, TP ≤ −1 dBTP portable target (ASWG/IESD) and its 3 URLs | FLAGGED | audiogang.org, designingsound.org and audiokinetic.com unreachable (DNS); consistent with report 06 |
| 72 | Audiokinetic URL path `/en/mastering-a-game-with-wwise-part1` | FLAGGED | Not confirmable; it may be a non-canonical path |
| 73 | Single-pass `loudnorm=I=-18:TP=-1.5:LRA=11` | FIXED | Outputs 192000 Hz (re-run); linear mode needs measured values (`ffmpeg -h filter=loudnorm`) |
| 74 | Chowning 1973 JAES 21(7); Karplus & Strong 1983 CMJ 7(2) DOI 10.2307/3680062; Schroeder 1962 JAES 10(3) | FLAGGED | Crossref/JSTOR unreachable; details match the standard records known to the checker (titles and pages added from those records, not fetched) |
| 75 | `--headless` = headless display + Dummy audio | OK | `main/main.cpp:626,1505-1508` |
| 76 | `--write-movie` → fixed 60 fps unless set; Dummy non-threaded audio | OK | `main.cpp:1961-1969, 2829-2833` |
| 77 | Movie recipe runs as written | FIXED | Relative path → `res://`; the target dir must exist (`movie_writer_pngwav.cpp` `write_begin`); `mkdir` + `.gdignore` added |
| 78 | Writers png/avi/ogv (ogv editor-only); 8-digit frames; settings 48000 / 60 / 0.75 | OK | `movie_writer_pngwav.h:39`; `modules/theora/SCsub:109`; `servers/movie_writer/movie_writer.cpp:151-162` |
| 79 | `--import` exits 0; grep `SCRIPT ERROR\|Parse Error` gates parse errors | FIXED | Re-run: exit 0 **and no such lines** for a broken script (with or without `class_name`, used by a scene). Gate replaced |
| 80 | `--check-only -s` exits 1 on type error, 0 clean | OK | Re-run: bad 1, syntax 1, good 0 |
| 81 | `--check-only` usable as-is on all scripts | FIXED | Autoload users fail with `Compile Error: Identifier not found`; the gate now keys on `Parse Error` (re-tested) |
| 82 | Xvfb devices and timings | OK | `cap_gl.log`, `cap_vk_mobile.log`, `movie.log` |
| 83 | Determinism: GL runs 0 px diff; GL vs VK RMSE 0.116 %; mobile = forward_plus | OK | Recomputed with `compare`: 0 / 0.00116 / 0 |
| 84 | `GPUParticles2D.use_fixed_seed`/`seed`; Tween `TRANS_SPRING/BACK/ELASTIC`, `parallel`, `set_loops`, `tween_method`; `AudioEffectHardLimiter`; `OS.get_cmdline_user_args`; `RenderingServer.frame_post_draw` | OK | `doc/classes/*.xml` |
| 85 | Runner `ubuntu-24.04` 20261012: JDK 17 default, build-tools 36.1.0, android-36, ANDROID_HOME | OK | [Ubuntu2404-Readme.md](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md) (image 20261012.334.1) |
| 86 | Android target 36, build-tools 36.1.0, Java 17, minSdk 24 | OK | `platform/android/java/app/config.gradle:3-14`; `export_plugin.cpp:303-305` |
| 87 | SDK path editor-setting defaults; keystore env vars | OK | `platform/android/export/export.cpp:58,61`; `export_plugin.h:47-52` |
| 88 | Build-tools selection "28–36" | OK (refined) | `get_apksigner_path` order (`export_plugin.cpp:2713-2760`) |
| 89 | Action tags v7/v7/v6/v6/v7/v5/v5, setup-android v4.0.4, cmdline-tools 15859902 | OK | `git ls-remote --tags`; `setup-android/action.yml:9` |
| 90 | `barichello/godot-ci:4.7.2` date/size/toolchain | OK | Docker Hub API: 2026-08-18, 2,584,416,488 B; Dockerfile:15,63 |
| 91 | setup-godot v2.4.3 has no checksum verification | OK | No sha/hash/digest logic in `src/*.ts` |
| 92 | Export option keys (Web and Android) | OK | `platform/web/export/export_plugin.cpp:375-382`; `platform/android/export/export_plugin.cpp:2262` etc. |
| 93 | Missing `include_filter` errors | OK | `editor/export/editor_export.cpp:378` (`get_value` with no default) |
| 94 | APK 28.5 MB, arm64 only, v2+v3 signed; Web `index.wasm` 39.5 MB, `index.pck` 347 KB | OK | `apksigner verify -v`; `unzip -l`; `ls -l` |
| 95 | "No project icon specified" is non-fatal | OK | `apkexport.log:34`, export succeeded |
| 96 | Exporting into `build/` is side-effect-free | FIXED (added) | Probe `build/web/*.png.import` files; `build/.gdignore` added |
| 97 | `web_nothreads` needs no COOP/COEP | OK | `platform/web/export/export_plugin.cpp:375` comment |
| 98 | Ubuntu apksigner 31.0.2 / adb | FIXED (label) | `dpkg -l`: `31.0.2-1ubuntu1` (Ubuntu, not Debian) |
| 99 | Fake SDK symlinks work for APK signing | OK | `/tmp/claude-research/android-sdk/build-tools/36.1.0/apksigner` → `/usr/bin/apksigner`; `apkexport.log` "Signed" |
| 100 | GDScript CI lint pathspec `':!:addons/**'` | OK | Standard git exclude magic [J: not run in CI] |
| 101 | Template install dir and `version.txt` | OK | Fetched `version.txt` = `4.7.2.stable` |
| 102 | Addon compile check: 0 failures for 6 addons | OK | `/tmp/claude-research/tooling/proj2/compile.log` |
| 103 | `AudioStreamWAV.load_from_file`, `AudioStreamGenerator` exist | OK | `AudioStreamWAV.xml:24`; `AudioStreamGenerator.xml` |
| 104 | iOS needs a macOS runner | OK [J] | Judgement; not testable here |
