# QA & Tools — Mossling Meadow

*Tools & QA Engineer · 2026-10-21 · Godot `4.7.2-stable` (ed1daf0) · binding inputs: `docs/research/00-SYNTHESIS.md` (C9, C10, D13, D14, §4), report 03 §5–§7 and Appendices A/B, Art Bible §11.*

This page explains how to run every automated gate, capture, metric and export on a workstation or in CI, and the human visual-QA protocol. CI runs the same commands as a local run, `tools/ci/run_ci.sh <stage>…`. A green local run therefore means a green CI run, apart from the runner-specific notes in §1.4.

| Need | Command (repo root) |
|---|---|
| Everything except exports | `tools/ci/run_ci.sh all` (≈ 2 min here) |
| Unit tests only | `tools/ci/run_ci.sh test` |
| One still | `tools/qa/capture.sh still --tod=0.62 --weather=clear --seed=7 --out=qa/out/golden.png` |
| A clip (mp4 + gif) | `tools/qa/capture.sh video --seconds=30 --tod=0.6` |
| 10-min loudness (A1/A2) | `tools/qa/capture.sh loudness --tod=0.4 --weather=clear --seed=7` |
| Rater set + metrics + sheet | `tools/qa/capture.sh set` |
| Exports + browser boot | `tools/ci/run_ci.sh import export web` |

---

## 1. Gates (CI = local)

### 1.1 One-time setup

| What | How | Needed by |
|---|---|---|
| Godot 4.7.2 on `PATH` (or `GODOT=/path`) | This container: `/usr/local/bin/godot` (source build of ed1daf0). Elsewhere: `tools/ci/install_godot.sh ~/godot` (official zip, SHA-512 pinned and cross-checked against `SHA512-SUMS.txt`) | all Godot stages |
| Python tools | `pip install -r tools/ci/requirements.txt` (gdtoolkit 4.5.0, numpy, Pillow, fontTools, brotli; pinned) | lint, data, visual |
| Xvfb + Mesa + ImageMagick + ffmpeg | `apt install xvfb xauth libgl1-mesa-dri libegl1 libgles2 imagemagick ffmpeg` | audio, visual, video |
| Export templates | `python3 -I tools/ci/fetch_templates.py`: ranged fetch of the 4 members we use (~148 MB of the 1.28 GB `.tpz`), each checked by zip CRC32 and a pinned SHA-256. `--full` downloads the whole `.tpz` and checks its SHA-512. `--verify` only checks what is already installed | export |
| Android signing | JDK 17+, `apksigner` (build-tools), and a debug keystore, given either in editor settings (this container: `/opt/godot-tools/debug.keystore`) or through `GODOT_ANDROID_KEYSTORE_DEBUG_{PATH,USER,PASSWORD}` | export |
| Node 20+ | `tools/qa/web/`: `npm ci` installs the pinned `puppeteer-core` and the npm-packaged Chromium (no browser-download host needed) | web |

The pins were re-verified on 2026-10-21:
- The editor zip and `.tpz` SHA-512 values match the release's `SHA512-SUMS.txt`.
- Every template member's size and CRC32 match the official archive's central directory.
- The action SHAs match `git ls-remote` for their tags.

### 1.2 Stages

`tools/ci/run_ci.sh <stage>…` runs the stages in the order given and stops at the first failure. `all` runs every stage up to and including `visual`. Times are measured in this container (4 CPUs, llvmpipe).

| Stage | Gate | Fails on | Time |
|---|---|---|---|
| `lint` | `gdlint .` (gdtoolkit 4.5.0, `.gdlintrc`, addons excluded) | any lint problem | 3 s |
| `data` | content lint, 412 Art Bible colour rules, font coverage (209/209 code points), fast economy gate (E5/E6), self-tests for `metrics.py` and `rubric.py` | any rule | 13 s |
| `import` | `godot --headless --import` | any `ERROR:`/`WARNING:`/`SCRIPT ERROR` line, except the engine race in §1.3 | 9 s |
| `strict` | `tools/ci/strict_check.sh`: every script under `scripts/ tests/ tools/{ci,qa,ui}` compiles with the four synthesis §3 warnings promoted to errors. The promotion is applied to a throw-away copy of the project, so `project.godot` is never edited and a teammate's concurrent Godot run is never affected | any warning | 2 s |
| `test` | GUT 9.7.1, `-gdir=res://tests`, JUnit in `reports/junit.xml` | a failing test or engine error (8 scripts, 78 tests, 5,836 asserts on 2026-10-21) | 25 s |
| `smoke` | boot → main, 300 frames headless, `--no-save` | any error or leak at exit | 4 s |
| `audio` | Xvfb `tools/qa/audio_smoke.gd`: every cue and audio state | any error or leak | 6 s |
| `visual` | §3.2 determinism, 3 D13 golden-size stills plus 2 rater-size stills, §4 metrics (gating banding and contrast), §3.5 golden comparison | non-determinism, script errors in a capture, banding or contrast failure, golden diff > 0.1 % | 43 s |
| `export` | Web (nothreads, release) and "Android Debug" APK into `build/` (§2) | export errors, missing outputs, size ceiling (80 MiB each), dev-only files in either package, `apksigner verify` failure | 22 s |
| `web` | `tools/qa/web/web_smoke.mjs`: boots `build/web` in headless Chromium (§2.3) | any console error, a failed request, or a blank canvas | 25 s |

Every Godot run gets a throw-away `user://` (temporary `XDG_DATA_HOME`). Saves and settings never leak between stages or from a developer's profile.

**Running one thing.**
- One GUT suite: `godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gselect=test_clock -gexit`. Add `-gunit_test_name=<substring>` for a single test.
  - `.gutconfig.json` already lists `res://tests/`, so `-gtest=` *adds* a file to the full run instead of selecting it.
- One script's analyzer: `godot --headless --path . --check-only -s res://path.gd`. This exits 1 for any script that uses an autoload (03 §6.3). Use `strict` for the real gate.

### 1.3 Known engine noise

`import` and `export` run the editor. About one incremental import in five (and none of the fresh-clone imports tried) ends with:

```
ERROR: Parameter "singleton" is null.
   at: is_cmdline_mode (editor/editor_node.cpp:6618)
WARNING: A Thread object is being destroyed without its completion having been realized.
```

This is an engine shutdown race, not a project problem. The editor quits while an `EditorFileSystem` update is still pending. That update calls `EditorNode::is_cmdline_mode()` (`editor/file_system/editor_file_system.cpp:2315`) after `EditorNode` is gone, and the scan thread is destroyed unjoined. `run_ci.sh check_editor_log` drops exactly these two messages. Any other `ERROR`/`WARNING` still fails, and runs that are not editor runs are not filtered at all.

The same race can also abort the editor (SIGABRT, exit 134) right after the `ERROR` line, with no `WARNING` (seen 1 in 4 incremental imports during the 2026-10-21 integration review). The import or export has finished by then, but the non-zero exit would stop `set -e`. `run_ci.sh run_editor` therefore retries an import/export run once when it exits non-zero *and* its log shows the `is_cmdline_mode` signature; the retry must pass on its own (the aborted log is kept as `<log>.race`). Any other non-zero exit fails as before.

### 1.4 GitHub Actions (`.github/workflows/ci.yml`)

The workflow only provisions machines. Every gate is a `run_ci.sh` stage.

| Job | Runner | Steps |
|---|---|---|
| `lint` | ubuntu-24.04 | Python 3.13 and pinned requirements, then `run_ci.sh lint data` |
| `test` | ubuntu-24.04 | Mesa/Xvfb/ImageMagick from apt, cached official Godot (`install_godot.sh`), then `run_ci.sh import strict test smoke audio visual`. Uploads `reports/` and `qa/out/` |
| `export` (needs both) | ubuntu-24.04 | Temurin 17 and Node 22. Cached Godot and templates (`fetch_templates.py`). A throw-away debug keystore (`keytool`, passed through the `GODOT_ANDROID_KEYSTORE_DEBUG_*` env vars). The runner's `ANDROID_HOME` build-tools 36.1.0 provides `apksigner`. Then `run_ci.sh import export web`. Uploads `web-nothreads`, `android-debug-apk` and `export-logs` (with the web-smoke screenshot and JSON) |

**Pins.**
- Release assets come from `github.com/godotengine/godot-builds/releases/download/4.7.2-stable/`: `Godot_v4.7.2-stable_linux.x86_64.zip`, `Godot_v4.7.2-stable_export_templates.tpz` and `SHA512-SUMS.txt`.
- Actions are pinned to commit SHAs, each with its tag in a comment: checkout v7, setup-python v7, setup-java v6, setup-node v6, cache v6, upload-artifact v7.
- `actionlint` 1.7.7 with shellcheck 0.11 reports 0 issues on the workflow, and shellcheck reports 0 on every `tools/**/*.sh`.

**Checked against the official binary.**
- `install_godot.sh` was run here. It installed `4.7.2.stable.official.ed1daf0bf`.
- A still captured with that binary is byte-identical to one from the local source build.

AAB release, Play signing and iOS stay deferred (D14, R12).

### 1.5 Lint and style

- **`.gdlintrc`** follows `docs/ARCHITECTURE.md` §10 and the GDScript style guide. Its deviations from the gdtoolkit defaults are explained in its header:
  - line length 120;
  - file length 1,500 lines;
  - 50 public methods;
  - 10 returns;
  - a trailing `_` allowed in local names (OKLab code).
- **Excluded:** `addons/`, `.godot/` and `build/`.
- **Current result:** our 54 scripts pass with 0 problems.
- **`gdformat --check` is advisory, not gated.** It would rewrite 31 of the 54 scripts today, mostly by re-wrapping long lines. A mass reformat while five roles are editing in parallel would cause merge churn for no behavioural gain. If the Director wants it gated, run `gdformat --line-length 120` once at a quiet checkpoint, then add it to `stage_lint`.
- **Python tools:** `flake8 --max-line-length 125` reports 0 issues on `tools/qa` and `tools/ci`.

---

## 2. Exports

### 2.1 Presets (`export_presets.cfg`)

| Preset | Keys (synthesis §3) |
|---|---|
| **Android Debug** | `gradle_build/use_gradle_build=false`; `architectures/arm64-v8a=true` only (C22); `screen/immersive_mode=true`; `screen/edge_to_edge=false`; `permissions/vibrate=false` (C3: haptics go through `performHapticFeedback`); `package/app_category=2` (Game); splash `#F0EEE9`, Godot boot splash disabled; `package/unique_name="studio.chill.mosslingmeadow"`; version 0.1.0 (code 1). Also excludes `audio/sfx_web/*`, the Web-only baked-wet SFX (R14) |
| **Web** | `variant/thread_support=false` (no COOP/COEP headers needed); `variant/extensions_support=false`; `vram_texture_compression/for_mobile=true`; `html/canvas_resize_policy=2`; PWA off |
| Both | `include_filter=""`. `exclude_filter` covers `addons/gut/*, tests/*, tools/*, docs/*, qa/*, build/*` (D5). `script_export_mode=2` (binary tokens, compressed) |

`project.godot` already has what exports require: `config/icon`, and `import_etc2_astc=true`, without which Android and Web refuse to export (03 §1.3). `build/.gdignore` and `qa/.gdignore` are committed. `/build/*` and `/qa/out/` are git-ignored.

### 2.2 Exporting locally

```bash
tools/ci/run_ci.sh import export          # both presets, verified as in CI
# or by hand:
godot --headless --path . --export-release "Web" build/web/index.html
godot --headless --path . --export-debug "Android Debug" build/android/mossling-meadow-debug.apk
```

Measured on 2026-10-21, skeleton build `befe0ea` + working tree:

| Artefact | Size | Notes |
|---|---|---|
| `build/web/` total | **51.5 MB** (51,530,767 B) | `index.wasm` 39.5 MB (**10.1 MB gzip -9**), `index.pck` 11.7 MB (9.7 MB gzip, mostly OGG/QOA audio), `index.js` 280 KB (68 KB gzip). Exported in ~6 s |
| `build/android/mossling-meadow-debug.apk` | **37.3 MB** (37,348,289 B) | Only `lib/arm64-v8a/` (`libgodot_android.so` 76 MB uncompressed); assets 9.8 MB. Signed with APK Signature Scheme v2 and v3 (`apksigner verify -v`; min SDK 24 needs no v1). Exported in ~12 s |

A web host should serve `.wasm` and `.pck` pre-compressed (gzip or brotli). The first visit then transfers about 20 MB.

### 2.3 Web boot smoke (`tools/qa/web/web_smoke.mjs`)

`run_ci.sh web` (or `cd tools/qa/web && npm ci && node web_smoke.mjs`) does the following:
1. Serves `build/web` on localhost.
2. Opens it in headless Chromium with WebGL2 on SwiftShader, at a 360×640 phone viewport with touch.
3. Waits 20 s, then taps the meadow once to exercise the touch-down cue and Web audio.
4. Writes `qa/out/web/web_smoke.{png,json}`.

It fails on any console error, failed request or `SCRIPT ERROR`, a missing Godot banner, or a canvas with fewer than 8 colours.
- **Browser:** `$CHROME` if set; otherwise the pinned `@sparticuz/chromium` from npm.
- **Result on 2026-10-21:** PASS. WebGL 2.0 via SwiftShader; the Godot 4.7.2 banner appears, with 0 errors and 0 warnings; the frame showed the main scene (136 colours). Boot to main took about 24 s.
- **Negative check:** a build with `index.pck` removed fails with 9 errors.

### 2.4 On a device

- **Android:** `adb install -r build/android/mossling-meadow-debug.apk`. The Android preset is `runnable`, so the editor's one-click deploy works when a phone is attached.
- **Web:** `python3 -m http.server -d build/web 8000`, then open the page on the phone. A nothreads build needs no special headers.
  - **Use a secure context.** Plain `http://<lan-ip>` is not one, so `AudioWorklet` is unavailable and Godot falls back to the deprecated ScriptProcessor path (`platform/web/js/libs/library_godot_audio.js:2183`).
  - **To test the real audio path,** either serve over HTTPS, or run `adb reverse tcp:8000 tcp:8000` and open `http://localhost:8000/`.

---

## 3. Captures

### 3.1 Stills: `tools/qa/capture.sh still` → `tools/qa/capture.gd`

```bash
tools/qa/capture.sh still --tod=0.62 --weather=clear --seed=7 --frames=90 --out=qa/out/golden.png --size=1080x1920
```

**What the wrapper does.**
- Starts a private Xvfb screen big enough for the size.
- Passes `--rendering-driver opengl3_es --audio-driver Dummy --resolution <size> --fixed-fps 30`.
- Isolates `user://` and passes `--no-save`.
- Fails the run on any `SCRIPT ERROR`/`ERROR:` in its log (`<out>.log`).

`capture.gd` writes `<out>.png` (RGB8) and a `<out>.png.json` sidecar. The sidecar records the engine, driver, adapter, Mesa version, every input, the resulting `g_day`/phase/weather/`g_time`, the install seed, warnings, `deterministic: true|false`, and the screen rects and font colours of every visible text control (used by §4 contrast).

| Arg (after `--`) | Default | Effect |
|---|---|---|
| `--out=<png>` | `qa/out/capture.png` | Relative paths resolve against the repo. `none` = no still (video runs) |
| `--size=WxH` | 1080x1920 | Window size. The run fails if the window differs |
| `--frames=N` | 90 (3 s at 30 fps) | Frames after the boot scene is entered (the real boot → main hand-off runs) |
| `--tod=0..1` | 0.4 (day) | Pins `g_day`. Keys: 0.2 dawn, 0.4 day, 0.6 golden, 0.8 dusk, 1.0 night |
| `--weather=clear\|breeze\|rain\|plan` | clear | Pins the weather. `plan` keeps the seeded day plan |
| `--seed=N` | 1 (wrapper) | Install seed. Global RNG is also seeded (12345) |
| `--date= --clock= --tz=` / `--now=<unix>` | 2026-04-18 10:00 UTC | Fixed wall clock. `--clock`/`--now` drive the palette unless `--tod` is also given |
| `--g-time=S`, `--animate` | 0, frozen | Shader clock start. `--animate` lets it run (frame clock, so still deterministic) |
| `--hide-ui` | off | Hides every CanvasLayer: a world-only frame (V2, V4) |
| `--set=key:value` | none | Applies a Settings key for this run, e.g. `language:vi`, `text_scale:200`, `reduce_motion:true`; repeatable |
| `--debug-layout`, `--debug-hud` | off | Game debug overlays |
| `--driver=` (wrapper) | opengl3_es | e.g. `opengl3` for the C9 fallback |

**Why it is reproducible.**
- `Clock.frame_clock`: wall time and ticks advance by the fixed frame delta, never by the system clock.
- `g_time` is forced, and the time zone and date are fixed.
- The weather and the time of day are pinned.
- The RNG is seeded.
- `FrameGovernor` is disabled.
- `Settings` are not persisted.
- `user://` is empty.

The sidecar flips `deterministic` to false, with a reason, when any of these was left to the system. Typical cost: 3 s for 540×960, 5–6 s for 1080×1920 or 1080×2400.

### 3.2 Determinism (R5): closed, `opengl3_es` is byte-stable

`tools/qa/capture.sh determinism [still args]` renders the same still in two fresh processes. It then compares them (ImageMagick AE, exact and at fuzz 2 %) and writes `qa/out/determinism/result.json`. It fails above 0.1 % of pixels. The CI `visual` stage runs it on the hardest case available: `--animate --frames=120 --tod=0.62 --weather=breeze` at 1080×1920, seed 7, with moving shaders and wind.

| Check (2026-10-21, Mesa 25.2.8 llvmpipe, GLES 3.2) | Result |
|---|---|
| Run A vs run B, `opengl3_es`, animated 120 frames, 1080×1920 | **byte-identical PNGs**, AE 0 exact / 0 at fuzz 2 % (limit 2,073 px). 12 s for both runs |
| Official 4.7.2 binary vs local source build, same still (540×960) | byte-identical |
| `opengl3_es` vs `opengl3` (C9 fallback), same still | AE 0, RMSE 0 on the current scene |

C9 stands: goldens use `opengl3_es`. The `opengl3` fallback is not needed. Re-run `determinism` whenever a shader adds noise, particles or time-dependent code. Particles must use `use_fixed_seed` with a fixed `seed`. Shaders must read `g_time`, never `TIME` (C4).

### 3.3 Video: `tools/qa/capture.sh video`

```bash
tools/qa/capture.sh video --seconds=30 --tod=0.6 --weather=breeze --seed=7     # -> qa/out/clip/clip.{avi,mp4,gif}
tools/qa/capture.sh video --seconds=5 --png --out=qa/out/clip_png              # lossless PNG frames + WAV
tools/qa/capture.sh encode qa/out/clip_png                                     # (re-)encode any AVI or PNG-frame dir
```

**What `video` runs.** Movie Maker is driven by `capture.gd` (`--write-movie <abs path> --fixed-fps 30 -- --out=none --animate --frames=N`). The size comes from the `.movie` overrides in `project.godot` (1080×2400, C10).

**Output formats.**
- **Default: MJPEG AVI.** About 38 ms per frame to encode (2 s of video takes 6 s), with audio.
- **`--png`:** about 0.94 s per frame. Use it for short lossless clips only.

**`encode`.** It makes:
- an H.264 `clip.mp4` (CRF 18, yuv420p, AAC 160k, faststart);
- a `clip.gif` preview (360 px wide, 15 fps, 2-pass palette, ordered dither).

**Recipe notes (verified 2026-10-21).**
- **Frame rate.** Command-line `--write-movie` forces 60 fps unless `--fixed-fps` is also given, in either order (`main/main.cpp:1965`). `editor/movie_writer/fps=30` only affects the editor's Movie Maker button. `mix_rate=44100` divides evenly by 30 fps.
- **The raw recipe works but leaks.** `godot --path . --rendering-driver opengl3_es --write-movie $PWD/qa/out/clip/frame.png --fixed-fps 30 --quit-after N -- --no-save --seed=7` produces frames `frame00000000.png…` and `frame.wav`. But it exits with audio still playing, which logs "10 ObjectDB instances leaked" and "4 resources still in use". The wrapper ends the run through `Game.quit_cleanly` instead. That adds about 4 frames past N.
- **Paths.** The output directory must exist, and a relative `--write-movie` path resolves to `res://`. The wrapper handles both.
- **Movie Maker clock.** It always uses the frame clock (`Clock`), so the world and the music follow the frames.

### 3.4 Loudness on real play (A1/A2): `tools/qa/capture.sh loudness`

```bash
tools/qa/capture.sh loudness --tod=0.4 --weather=clear --seed=7                       # 10 min after a 30 s pre-roll
tools/qa/capture.sh loudness --tod=0.9 --weather=rain --seed=7 --out-dir=qa/out/loudness_night_rain
```

**How it runs.**
- Movie Maker records the game's own mix (`--frame-clock`, idle and untouched).
- It records on a throw-away copy of the project whose `.movie` size is 270×600. Only the audio is measured, and full-size MJPEG would take about 30 min. The real `project.godot` is never edited.
- It then runs `tools/audio/measure.py --gate --skip-s 30` (needs the `tools/audio/requirements.txt` packages).

**Gate (A1/A2):**
- −18 ± 2 LUFS-I (warns outside ± 1);
- TP ≤ −1 dBTP;
- S ≤ −14 LUFS;
- LRA ≤ 8;
- ≤ 0.5 % of energy above 10 kHz;
- at least 600 s of capture.

**Cost:** about 3.3 min wall-clock, at roughly 440 % of real time.

| 2026-10-21, 600 s each | LUFS-I | TP dBTP | max S / M | LRA | > 10 kHz | 2–5 kHz | Verdict |
|---|---|---|---|---|---|---|---|
| day, clear (`--tod=0.4`) | **−17.85** | −4.27 | −15.69 / −14.05 | 3.1 | 0.001 % | 0.35 % | ✅ A1 + A2 |
| night, rain (`--tod=0.9 --weather=rain`) | **−17.91** | −3.71 | −15.53 / −12.84 | 5.9 | 0.000 % | 0.96 % | ✅ A1 + A2 |

The Tech Lead's 20 s reading of −19.5 LUFS was the pad fade-in. Over 10 minutes the mix sits 0.1–0.2 LU above the −18 target. Re-run this after any change to the mix, the beds or the bus layout, and attach `loudness.txt` to the PR.

### 3.5 Goldens: `tools/qa/compare_goldens.sh <new_dir> <golden_dir> [--update]`

- **Metric:** AE at fuzz 2 %. A golden fails when more than 0.1 % of its pixels differ (D13). Each run writes `golden_diff/<name>.png` and `golden_report.json`.
- **Sizes (D13):** 540×960, 540×1200 and 720×960, plus 1080×2400 for raters.
- **Pinning:** goldens are pinned per renderer and per Mesa minor version, in `qa/goldens/opengl3_es-mesa<maj.min>/`. CI derives the directory from the capture sidecar, so a runner Mesa upgrade shows up as "no goldens yet" instead of as false failures. The runner's ubuntu-24.04 Mesa should match, since both come from noble-updates (this container has 25.2.8). Confirm from the first CI artifact's sidecar `adapter_version` before blessing.
- **Policy:** no goldens are committed yet, so the comparison is skipped. The scene is a skeleton (`PlaceholderBand` nodes) that the look spike will replace wholesale. Blessing now would only produce churn. **Bless after the R1 look-spike gate passes** (§5): `tools/qa/compare_goldens.sh qa/out/ci qa/goldens/opengl3_es-mesa25.2 --update`. The QA lead does this from a CI artifact, giving the reason in the PR. Until then, `visual` gates determinism, script errors, banding and contrast.

---

## 4. Automated visual metrics (`tools/qa/metrics.py`)

```bash
python3 -I tools/qa/metrics.py [--gate banding,contrast] [--json out.json] [--no-fail] shot.png …
python3 -I tools/qa/metrics.py --selftest        # detector calibration (runs in the data stage)
```

It reads each PNG and its capture sidecar, and needs only numpy and Pillow. It writes a JSON report and prints one PASS/FAIL line per image. The exit code is 1 if a gated check fails.

| Check | Rule | Source |
|---|---|---|
| **V2 low-arousal colour, `hsv`** (dawn, day, golden) | ≥ 85 % of the area with HSV S ≤ 0.45 and V ≥ 0.45; saturated accents (S > 0.45, V ≥ 0.45) ≤ 10 % | synthesis V2, 04 P6 |
| **V2, `oklch`** (dusk, night; **provisional**) | ≥ 85 % at OKLCh C ≤ 0.10, accents (C > 0.12) ≤ 10 %, no pixel below L* 6 | Art Bible §11.3 amendment A6, awaiting Director ratification (U2) |
| **Token chroma** (always) | 99.9th-percentile OKLab chroma ≤ 0.20 | V2 "C_OK ≤ 0.2" |
| **Banding** | Per channel, along rows and columns, finds staircases: ≥ 3 consecutive flat runs ≥ 16 px separated by same-direction 1–2-code steps, which is the signature of an undithered 8-bit gradient. Fails above 0.5 % of the area. TPDF dither (C6) breaks every run | V6, 05 §2.4 |
| **Contrast** | Uses each text rect from the sidecar (or `--text-region x,y,w,h[,#rgb]`). Separates glyph pixels from backdrop by OKLab distance to the declared font colour, then takes the 5th-percentile WCAG ratio of text against backdrop. Requires ≥ 4.5 | X2, WCAG 2.2 1.4.3 |

**Phase.** The sidecar's phase picks the V2 rule (`--v2-mode` overrides it). Both rules are always reported.

**Self-test:**
- undithered day and night skies band (> 30 % of the area), and TPDF-dithered ones score < 0.1 %;
- hard-edged panels score 0;
- an 8 % accent passes and 30 % alarm red fails;
- the night sky fails HSV but passes A6;
- ink on the surface colour scores > 10:1, and pale text fails.

**Results on the skeleton** (2026-10-21; `qa/out/set`, `qa/out/ci`):

| Frame | V2 rule | Calm / accent | Banding | Contrast |
|---|---|---|---|---|
| dawn 0.2 | hsv | 100 % / 0 % ✅ | 0 | — |
| **day 0.4** (all 4 sizes) | hsv | **63–67 % / 33–37 % ❌** | 0 | — |
| golden 0.6 | hsv | 94 % / 6 % ✅ | 0 | — |
| dusk 0.8 | oklch | 95 % ✅ (HSV 46 %) | 0 | — |
| night 1.0 | oklch | 99.4 %, L* min 9.3 ✅ (HSV 0 %) | 0 | — |
| day rain | hsv | 100 % ✅ | 0 | — |
| day + `--debug-hud` | — | — | — | DebugReadout ink on sky 9.5:1 (p5) ✅ |

**Gating today:** `banding,contrast`. **V2 is reported but does not gate yet** (`METRICS_GATE` in `run_ci.sh`). The day failure is real and belongs to the Art Director and Technical Artist:
- The day tokens are above S 0.45 in HSV: `sky_top` #6FB6EC has S 0.53, and `near`/`ground_front` #4FA06F has S 0.51.
- The placeholder bands paint them flat, over the whole sky top and the near bank.
- The Art Bible budget (day 89 %) assumes the near bank is lit meadow mixed toward `ground_front_lit`, that `sky_mid` sits at 42 % of the sky gradient, and that L5 stays ≤ 8 %.

Switch V2 to gating (`METRICS_GATE=v2,banding,contrast`) when the look spike lands the real sky and meadow shaders. Once A6 is ratified, drop "provisional".

**Not computed from screenshots (yet).** Each of these checks is mapped to its owner and the place it lives:
- **V4 fractal D:** Art Bible §11.2 recipe (Sobel, box counting on `--hide-ui` frames). Add it to `metrics.py` when silhouettes exist.
- **V5 motion:** needs a clip with frame differencing. Planned on the `video` output.
- **I1 latency and frame pacing:** device only (§6).
- **V3 radii:** audit by `art_data.py`.

---

## 5. Visual QA protocol (human raters)

### 5.1 Capture set (Art Bible §11.2)

`tools/qa/capture.sh set [--out-dir=qa/out/set] [--size=1080x2400]` renders the deterministic rater set (seed 7, 120 frames, opengl3_es). It runs `metrics.py` on the set and builds a labelled contact sheet.

| Frame | Args | Status |
|---|---|---|
| 5 phases, home screen | `--tod=0.2/0.4/0.6/0.8/1.0 --weather=clear` | in the set |
| day rain | `--tod=0.4 --weather=rain` | in the set |
| 5 phases, Garden sheet open | needs a UI arg to open the sheet | added when the UI Engineer ships the sheet (a `--open=garden` debug arg is requested) |
| night with 5 lanterns | needs décor and a save fixture | added with the décor system (a save-fixture arg is requested from Gameplay) |
| 30 s idle video, 1080×2400 at 30 fps | `tools/qa/capture.sh video --seconds=30 --tod=0.6 --weather=breeze --seed=7` | ready |

### 5.2 Raters and independence

- **Three independent raters** (TEAM.md: the Visual QA Panel). Each scores alone, before seeing anyone else's scores or the metrics verdict, and is told only the build label. Raters can be humans or isolated agent sessions that share no context with the authors of the art.
- **Raters score full-size stills at 1:1** (1080×2400 on a screen at 100 %, or zoomed to 200 % for #3) and watch the 30 s clip at native size. Grain and dither vanish on downscaled images (05 §6). The contact sheet is for orientation only.
- Each rater fills in one file:
  - `python3 -I tools/qa/rubric.py template --rater <name> --build <git sha> > qa/reports/<sha>/rater_<name>.json`
  - one integer from 1 to 10 per criterion, plus a short note per criterion naming the frame and the problem.
- Anyone can then aggregate. `qa/reports/` is committed; `qa/.gdignore` keeps it out of the game:
  - `python3 -I tools/qa/rubric.py score qa/reports/<sha>/rater_*.json --json qa/reports/<sha>/verdict.json [--require ship]`

### 5.3 Rubric and thresholds (Art Bible §11.1; synthesis D13, V7)

| # | Criterion | 7 = solid | Objective aid |
|---|---|---|---|
| 1 | Value structure & focal hierarchy | Clear focal, some noise | Squint test: the focal (sun stone) is the top local contrast; L* p5–p95 ≥ 55 (day) |
| 2 | Palette harmony | Token palette, a few clashes | §4 V2 and token chroma; k-means(8) within ΔE_OK 6 of a token |
| 3 | Edge quality & AA | Clean at 100 % | No stair-steps or halos at 200 %; text is MSDF or rasterised at the right size |
| 4 | Depth & atmosphere | 4 planes with haze | Contrast to `sky_horizon` rises far → near |
| 5 | Lighting coherence | Consistent direction | Shadows agree with `g_sun_dir`; no neutral-grey shadows |
| 6 | Motion quality | Eased; ≥ 3 ambient layers | Clip: no linear spatial tweens, no pop-in, no composite repeat < 20 s |
| 7 | Touch feedback | Every control responds | First visual change ≤ 6 frames (device, §6) |
| 8 | UI clarity & accessibility | WCAG AA | §4 contrast; targets ≥ 48 dp; idle HUD ≤ 20 % of the area |
| 9 | Consistency | One style, small drift | One light direction, grain everywhere, token radii |
| 10 | Polish & "Today tab" | Complete | A random 1:1 crop works as key art |

`rubric.py` takes the per-criterion **median** (Art Bible §11.2) and the **mean** (TEAM.md gate 3 says "average"). It applies the thresholds below to both and reports the **lower** level:

| Level | Rule |
|---|---|
| prototype | total < 60 |
| alpha | 60–69 |
| soft-launch | 70–79, or ≥ 80 without the floors below |
| **ship** | **total ≥ 80, every criterion ≥ 7, and #1, #6, #8 ≥ 8** |
| feature-worthy | total ≥ 88 and every criterion ≥ 8 |
| **R1 look-spike gate** | #3, #5, #6, #9 ≥ 7 (reported separately; must pass before any content work) |

**Process rules.**
- **Disagreement:** any criterion whose spread across raters exceeds 2 points is flagged for a review discussion. Raters may then re-score that criterion only, with a note saying why.
- **Fewer than 3 raters:** no verdict, and `--require` fails.
- **Before human rating:** a build goes to raters only after the automated pre-checks pass (`run_ci.sh all`; V2 too once it gates). There is no point rating a frame that fails a measurable rule.

### 5.4 Contact sheets: `tools/qa/contact_sheet.sh`

```bash
tools/qa/contact_sheet.sh -o qa/out/sheet.png -c 3 -w 360 -t "Build befe0ea" qa/out/set/*.png
```

- Tiles keep their aspect ratio.
- Each tile is labelled from its sidecar with its phase, weather, `g_day`, size and driver.
- The background and ink use the UI `surface`/`ink` tokens.
- The montage is built at 16 bits and re-quantised with an ordered dither, so the sheet does not create bands that the stills do not have.
- Use it for PR descriptions and reviewer overviews. Never score from it.

---

## 6. Device checklist (cannot be tested in this container)

Run before every milestone (synthesis R4; 02 §7). Record the results in `qa/reports/<sha>/device.md`.

1. **Frame pacing:**
   - p95 frame delta at 30 fps idle (≤ 40 ms, else follow R2);
   - after warm-up, no frame over 2× the interval;
   - cold start ≤ 3 s on a low-tier phone (Mali-G52 / Adreno 610);
   - catch-up time after 7 days away.
2. **Budgets** (§3): ≤ 100 draw calls, ≤ 96 MB texture memory, ≤ 300 MB PSS.
3. **Input:**
   - I1: first visual change ≤ 6 frames, with sound and haptic in the same frame, using input injection or a 240 fps camera;
   - Android `performHapticFeedback` feel for Off/Subtle/Full;
   - no buzz fallback.
4. **Accessibility:**
   - the OS reduce-motion and font-scale reads (Android);
   - the in-game toggles (iOS, which has no OS read without a plugin);
   - back gesture closes the top sheet.
5. **Web:**
   - the audio-unlock path on iOS Safari and Android Chrome;
   - the baked-wet SFX fallback (R14);
   - load time on 4G.
6. **Colour:**
   - Samsung "Vivid" mode (R15);
   - a gamma check on iOS GLES (R3).
7. **Battery:** a 30 min ambient soak at 50 % brightness, target ≤ 8 %/h.

---

## 7. Open items for other roles

- **Art Director / Technical Artist:**
  - Day V2 fails on the skeleton (§4). The real sky and meadow must meet the 85 % budget before V2 can gate.
  - Ratify or reject A6 (U2) with the Director.
- **UI Engineer:** add a debug arg that opens a sheet (`--open=garden`) so the rater set can include the Garden-sheet frames. Keep the text controls as `Label`/`Button`/`RichTextLabel` so §4 contrast finds them.
- **Gameplay Engineer:** add a save-fixture arg (e.g. `--fixture=night_lanterns`) so the capture set can show placed décor deterministically.
- **Sound Designer:** the 10-minute A1/A2 check now passes on real play (§3.4: −17.85 LUFS-I for day/clear, −17.91 for night/rain). Run `tools/qa/capture.sh loudness` after any mix change. It is not a CI stage, because it takes about 3.3 min and needs scipy and pyloudnorm.
- **Director:**
  - Ratify the policies of blessing goldens after R1 (§3.5) and keeping `gdformat` advisory (§1.5).
  - Decide whether the median+mean "lower level" rule (§5.3) is acceptable.

---

## 8. Garden QA flags (fixtures and touch strip; owner: Flora & Décor)

Fixtures (`scripts/garden/garden_fixture.gd`, applied before the world layers bind; use ONE `--fixture`):
`--fixture=garden_mid` (46 stems at mixed stages in all five beds, bed_2 as two masses with a rest gap, every décor set, 7 gifts in the basket),
`--fixture=night_lanterns` (the same garden with 5 lanterns; pair with `--tod=1.0`),
`--fixture=garden_full` (every stem and all 10 copies of every décor set: the draw-call / uniform-buffer stress case).

Touch strip (`--qa-garden=<kind>:<ms>`): the touch happens 1.2 s after the world is ready and the garden FREEZES `<ms>` later,
so keep the default `--frames=90` and `<ms>` ≤ 1500. Every touch-down shows the world TouchRing, a 0.94 squash and a tint in the
same frame, and plays S01 (+ its haptic).

| Frame | Command (add `--size=1080x2400 --seed=7 --qa-creatures=6 --out=...`) | Shows |
|---|---|---|
| bed press | `--tod=0.4 --fixture=garden_mid --qa-garden=bed:90` | bed_2 at peak squash + tint, ground ring |
| ready buds | `--tod=0.4 --fixture=garden_mid --qa-garden=ready` | the 3 front-most blooms of bed_2 as ready buds (1.6× halo, α 0.4) |
| bud unfurl | `--tod=0.4 --fixture=garden_mid --qa-garden=unfurl:220` | 220 ms into the 600 ms unfurl after a tap: petals opening, the ready glow flaring (×1.7 α, 1.45× size), 3-5 sparkles (30 px), ring α 0.6 |
| lantern tap | `--tod=1.0 --fixture=night_lanterns --qa-garden=lantern:200` | the first (right-most) lantern at the top of its +60 % brighten: halo blooms 1.5×, pool 150 → 190 px, warm ring α 0.6 |
| pinwheel tap | `--tod=0.4 --fixture=garden_mid --qa-garden=pinwheel:200` | spin burst + dust puff, ring |
| chime swing | `--tod=0.6 --fixture=garden_mid --qa-garden=chime:300` | the tubes mid-swing after the willow-branch tap |
| décor placed | `--tod=0.4 --fixture=garden_mid --qa-garden=place:150` | a new pinwheel popping in (fade + pop 0.6 → 1) with its dust puff |

`--qa-ready=<bed_id>` picks the bed for bed / ready / unfurl (default `bed_2`). Draw calls: add `--qa-drawcalls`
(round 3: `garden_full` + HUD + 8 mosslings = 91-92 at golden; round 4: `garden_full` + HUD + 6 mosslings = 89-90).

Round 4 notes: beds and décor outside the focal ellipse (centre 540,1100, radii 260×180 design px) sit back
(−10 % value, −14 % chroma, petal value contrast −28 % at full calm), so the sun stone wins the squint; flower sway is
25 % lower and the gust front is the env's diagonal `gust_at` (beds, pinwheels, chimes and lanterns lag with depth).
Best motion strip for the garden: `video --seconds=8 --tod=0.4 --fixture=garden_mid --qa-creatures=6` (a gust crosses
the beds left to right every ~9.7 s; pinwheels spin up with it, chime tubes swing on their own pendulums).

---

## 9. Creature QA flags (fixtures, touch strip, lineup; owner: Creature team)

Fixture: `--qa-creatures=<n>` (1-9) places n mosslings in varied behaviours at their favourite spots
(`scripts/creature/creature_layer.gd` QA_FIXTURE): Puffmoss naps on the sun stone (focal, z's),
Buttonbud nibbles a clover, Pebblepaw sits by the brook looking at the water, Honeyhum plays beside the
stone with a held "^ ^" face, Dandelfluff plays on the hill crest, Primpip naps in the stump. Use 6 for
the rater set. `--qa-walk` makes them walk in from their entries instead (arrive fade >= 300 ms).

Touch strip (`--qa-touch=<species>:<tap|hold|release>:<ms>`): the touch happens 1.0 s after the fixture
spawns and that mossling (and its stamps) FREEZES `<ms>` later. Keep `--frames=120`.

| Frame | Command (add `--size=1080x2400 --seed=7 --fixture=garden_mid --qa-creatures=6 --qa-met=7 --frames=120 --out=...`) | Shows at peak |
|---|---|---|
| tap | `--tod=0.4 --qa-touch=buttonbud:tap:300` | ripple ring, press squash -> 1.08 stretch beat, "^ ^" eyes, 6 gold sparkles bursting from the silhouette, name tag rising |
| hold / pet | `--tod=0.4 --qa-touch=pebblepaw:hold:1100` | pet squash 0.88, happy eyes + blush, 3-4 outlined hearts (~27 dp) streaming from the head (1 per 220 ms) |
| release | `--tod=0.4 --qa-touch=pebblepaw:release:250` | the 5-heart bouquet (~31 dp) and the 1.04 overshoot |
| napper stir | `--tod=0.4 --qa-touch=puffmoss:tap:200` | a gentle ripple, ear twitch, one sparkle; the z's pause (never wakes) |
| Album at night | `--tod=0.95 --fixture=night_lanterns --qa-friend=puffmoss` | the portrait in the fixed studio light (day palette), never a night blob |

Lineup (`scenes/creatures/lineup.tscn`, all 12 species awake and asleep on the live meadow colours):
`tools/qa/capture.sh still --scene=res://scenes/creatures/lineup.tscn --size=1080x2400 --seed=7 --frames=20 --tod=0.4 --lineup-pose=both --out=...`
(`--tod=0.6` golden rim, `--tod=1.0` moon rim). Close-ups: `--lineup-only=pebblepaw,honeyhum --lineup-scale=2.2 --lineup-pose=awake`
(1:1 / 200 % fibre check); `--lineup-pose=happy`, `--lineup-live` (blinks / fidgets on), `--lineup-labels=0`.

Draw calls (round 4): `garden_full` + HUD + 6 mosslings = 90 at golden (`--qa-draw-audit`: Creatures 11).

### Environment touch + value flags (round 4, env)

| Frame | Command (add `--size=1080x2400 --seed=7 --qa-creatures=6 --fixture=garden_mid --out=...`) | Shows |
|---|---|---|
| brook tap | `--tod=0.4 --qa-brook-tap=640@150` | ripple rings (3, flattened) + TouchRing bloom/sparkles on the water, 150 ms into the 380 ms ripple; `@<ms>` picks the moment (peak ≈ 120–180 ms) |
| prop tap | `--tod=0.4 --qa-prop-tap=mailbox@120` (or `basket`, `wind_chime_branch`) | peak squash + tint + ground ring |
| both in one still | `--tod=0.4 --qa-brook-tap=640@150 --qa-prop-tap=basket@90` | the two env touch beats side by side |
| draw calls | `--tod=0.6 --fixture=garden_full --qa-draw-audit --frames=200` | per-layer draw calls in the log (`qa-draw-audit:` lines; round 4: 90 total) |

`--debug-ripple=<x>` is the older ripple-only alias. Real brook taps now also spawn the flattened TouchRing (S01 + S06 cues unchanged).

## 10. UI QA flags (HUD, dock, sheets, overlays; owner: UI)

All flags are user args after `--` (capture.sh passes them through); parsed in `scripts/ui/hud_controller.gd`.
Base: `tools/qa/capture.sh still --size=1080x2400 --seed=7 --frames=120 --no-save --fixture=garden_mid --qa-creatures=6 --qa-met=7 --out=...`

| Still | Add | Shows |
|---|---|---|
| Garden sheet | `--tod=0.4 --qa-sheet=garden` (`--qa-tab=1` Décor) | live glass sheet, raised segmented thumb, hugging Plant / Place pills, price chips |
| Album grid | `--tod=0.4 --qa-sheet=album` (`--qa-tab=1` Photos, `2` Postcards) | 12 portrait wells (studio light, studio diorama) |
| Album friend at night | `--fixture=night_lanterns --tod=0.95 --qa-friend=puffmoss` | night chrome dock/chips, neutral sheet, crisp studio-lit portrait |
| Basket / Settings | `--qa-sheet=basket` / `--qa-sheet=settings` | — |
| Recap / new friend / leave / toast / captions | `--qa-recap`, `--qa-newfriend=honeyhum`, `--qa-leave`, `--qa-toast`, `--qa-captions` | overlays (no auto-dismiss) |
| Ambient watch | `--qa-ambient` | HUD hidden |
| Night chrome | `--fixture=night_lanterns --tod=1.0` (also dusk `--tod=0.82`) | dim warm-navy glass, night_ink labels/icons (switch at g_lights >= 0.6, back <= 0.4) |
| vi + large text | `--set=language:vi --set=text_scale:200` | reflow, +12 % vi line height |

Touch strip (UI): `--qa-press=<target> --qa-press-t=<ms>` freezes a touch-down `<ms>` after it happened (press dip
peaks at 80 ms, ripple runs 380 ms; best stills 60-120 ms).

| Frame | Add | Shows at peak |
|---|---|---|
| dock tab | `--tod=0.4 --qa-press=garden --qa-press-t=60` | squash on the baseline, press capsule, ripple under icon + label |
| dock tab at night | `--fixture=night_lanterns --tod=1.0 --qa-press=garden --qa-press-t=60` | light capped ripple (0.12) on the night capsule |
| primary pill | `--tod=0.4 --qa-sheet=garden --qa-press=primary --qa-press-t=90` | pressed primary_deep fill, lighter-primary splash UNDER the white label (>= 5.2:1 at the crest) |
| segmented tab | `--tod=0.4 --qa-sheet=album --qa-press=tab --qa-press-t=90` | ripple inside the track segment |
| friend card | `--tod=0.4 --qa-sheet=album --qa-press=card --qa-press-t=90` | card dip + ripple |
| toggle | `--tod=0.4 --qa-sheet=settings --qa-press=toggle --qa-press-t=90` | row press + thumb |
| eye / close | `--qa-press=eye` / `--qa-sheet=garden --qa-press=close` | plate press |

Draw calls: `--qa-drawcalls --frames=200` prints `qa-drawcalls: <n>`. Round 4: HUD-only golden `garden_full` 86-87;
with a sheet open the sheet adds ~30 (Garden) to ~57 (Album grid; rows scrolled out of the window are culled).
