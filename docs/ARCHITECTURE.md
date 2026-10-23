# ARCHITECTURE — Mossling Meadow

*Tech Lead / Architect · 2026-10-20 · Godot 4.7.2-stable (ed1daf0), Compatibility renderer · status: **binding** for code structure, data flow, save format and engineering conventions. Inputs: `docs/research/00-SYNTHESIS.md` (binding), `docs/GDD.md`, `docs/ART_BIBLE.md`, `audio/manifest.json` (Sound Designer), research reports 01–06.*

**What exists today.** Everything in this document is implemented and verified headless on 4.7.2. The world step, save system, time-of-day driver, settings, haptics, audio director, motion helpers, frame governor, shader warm-up, boot flow and a placeholder main scene all run. The art layers, creatures and UI screens are deliberately **not** here; §12 lists every placeholder and who replaces it.

| Check (re-run with the commands in §13) | Result |
|---|---|
| GUT, 25 suites / 264 tests / 34,457 asserts (Retention v1: 3 suites, 29 tests) | **all pass**, 41 s headless (re-run 2026-10-21) |
| E5 / E6 in GDScript: 48 random + 12 reference players × 30 days, **15,908 sessions** | 0 sessions with nothing affordable, 0 with nothing new; max displayed 50,401, max price 527 (the Python sim: 51,734 / 527) |
| `godot --headless --path . --import` on a fresh clone | 0 errors, 0 warnings |
| Boot → main headless, `--quit-after 300` | 0 errors, 0 leaks |
| `tools/ci/strict_check.sh` (the four synthesis warnings promoted to errors) | 54 scripts, 0 warnings in our code |
| Xvfb audio smoke (`tools/qa/audio_smoke.gd`): every cue S01–S21 with each pitch-rule context, purr, rain, night, sheet duck, the three music modes, mono | 0 script errors, 0 leaks at exit |
| Movie Maker idle capture, 20 s (`--write-movie`), `tools/audio/measure.py --skip-s 8` | −19.5 LUFS-I while the pad is still fading in, −7.4 dBTP, 0.001 % above 10 kHz. The 10-min A1/A2 gate on real play (`tools/qa/capture.sh loudness`) reads −17.85 LUFS-I day/clear and −17.91 night/rain (docs/QA.md §3.4) |
| Xvfb `opengl3_es` stills at 540×960 and 540×1200 | palette, globals and layout overlay are correct |
| Exports | Web (nothreads) and Android debug APK (arm64, signed, no VIBRATE/INTERNET) both build; the pack contains `data/`, the translations, fonts and `audio/manifest.json`, and excludes GUT, tests and tools |

---

## 1. Principles

1. **One world step.** `WorldSim.advance()` is a GDScript port of `tools/sim/economy_sim.py: Player.advance`, the algorithm the economy was validated with. Live play and offline catch-up use it unchanged (GDD §5.8).
2. **The sim is pure.** No nodes, no autoloads, no wall clock. Time comes in as arguments, so a whole history replays from a save, and tests run in milliseconds.
3. **Data, not constants.** Every game number lives in `data/*.json`, every string in `i18n/strings.csv`, every colour in `data/palettes.json`, every duration and spring in `data/motion_tokens.json`, every audio rule in `audio/manifest.json`. Code holds formulas and named structural constants that cite their source.
4. **Views never mutate state.** They read `Game.sim` and listen to signals. Player intents go through `Game` methods, which advance to "now", act, dispatch events and request a save.
5. **Nothing can be lost.** No decay branch exists (E1). Saves are atomic with a backup. An unreadable save is moved aside and never deleted. Errors degrade silently into "nothing happens", never into an error screen (E2, A3).
6. **Headless first.** Every system works under `--headless` (Dummy renderer and audio) so CI can test it. Rendering-only work (shader warm-up, ambient audio layers) skips itself there.

---

## 2. Folder layout

```
project.godot            synthesis §3 + additions below            export_presets.cfg  Android (arm64 APK) + Web
icon.svg                 hand-written app icon                     default_bus_layout.tres  (audio pipeline, generated)
.gutconfig.json          GUT defaults (tests/, include subdirs)    .gitignore / .gitattributes
addons/gut/              GUT v9.7.1 @ aeb5d4f… (tools/vendor_addons.sh; dev-only, excluded from exports)
data/                    GDD + Art data (single sources of truth; JSON, schema 1)
i18n/strings.csv         en + vi (CSV import → strings.{en,vi}.translation, git-ignored build products)
fonts/nunito|baloo2/     subset WOFF2 + OFL.txt + SOURCE.txt (tools/fonts/build_fonts.py)
audio/                   rendered assets + manifest.json (tools/audio/synth.py, Sound Designer)
ui/theme/base_theme.tres editor-preview build of the UI theme (tools/ui/build_theme.gd)
scenes/boot.tscn         splash + warm-up + Game.boot() → main
scenes/main.tscn         the hollow: named composition layers + HUD placeholders
shaders/                 Art Bible §12.1 shaders (Technical Artist); shaders/dev/ = skeleton placeholders
scripts/
  autoload/              the 11 autoloads (§3.1)
  sim/                   PURE world model: world_state, world_sim, retention_rules, retention_hash, tod_math,
                         weather_plan, garden_rules, recap; Active Play v1 (§5.2b): active_rules, wish_rules,
                         tea_rules, decor_placement_rules
  qa/                    QA fixtures that touch Game (retention_fixture: --fixture=retention_mid, --qa-scene;
                         active_fixture: --fixture=active_mid)
  core/                  PURE infrastructure: game_content, save_store, atomic_file, i18n, name_rules, nfc_table, platform
  world/                 PURE look math: palette_math (OKLab), palette_driver, weather_driver, celestial
  motion/                spring, spring_2d (analytic), cubic_bezier
  audio/                 harmony (pitch-set helpers mirroring tools/audio/theory.py)
  ui/                    theme_builder, safe_area_container
  boot/  main/           scene scripts (boot, shader_warmup / main, placeholder_band, layout_debug)
tests/                   GUT suites (test_*.gd) + helpers/ (sim_player, compare_util, retention_util, active_util)
tools/  (.gdignore)      vendor_addons.sh · fonts/ · i18n/ · ui/ · ci/ · qa/ · sim/ (GDD) · art/ (Art) · audio/ (Sound)
docs/ qa/ build/         each has an empty .gdignore so the editor never imports them
```

Ownership follows `docs/TEAM.md`: `scripts/sim`, `scripts/core`, `scripts/autoload` belong to the Tech Lead and Gameplay Engineer. `shaders/` and `scripts/world` drawing belong to the Technical Artist. `ui/` and `scripts/ui` belong to the UI Engineer. `scripts/motion` belongs to Motion. `tests/`, `qa/` and `tools/ci|qa` belong to QA.

**`project.godot` versus synthesis §3.** The §3 block is reproduced verbatim. The additions are:

| Addition | Why |
|---|---|
| `[shader_globals]` +26 | Art Bible §4.1 (A5). There are now 37 globals in total, and each has exactly one writer (§7) |
| `[autoload]` ×11 | §3.1 |
| `application/config/version="0.1.0"` | Written into every save |
| `application/boot_splash/show_image=false` | A plain `#F0EEE9` splash: no engine logo, and a seamless hand-off to `boot.tscn` |
| `internationalization/locale/fallback="en"` | GDD §7.6 |

Two settings are **deliberately not** in `project.godot`:
- **Translations** (`I18n.ensure_translations()`).
- **The project theme** (`UiTheme`).

On a fresh clone the editor loads both before the first import has produced the `.translation` and font files, and logs load errors. Registering them from code keeps the very first `--import` clean (verified).

---

## 3. Runtime structure

### 3.1 Autoloads (in load order; each may use only those above it)

| # | Name | File | Responsibility | Public API (main) | Signals |
|---|---|---|---|---|---|
| 1 | **ContentRegistry** | `autoload/content_registry.gd` | Loads every `data/*.json` and `audio/manifest.json` once into a read-only `GameContent` | `content`, `is_valid()`, `reload()`, `economy()`, `palettes()`, `motion_tokens()`, `audio_manifest()` | `content_loaded(content)` |
| 2 | **Settings** | `autoload/settings.gd` | X1 settings store: validation, OS-derived defaults, atomic `user://settings.cfg` | `get_value/get_bool/get_int/get_string(key)`, `set_value(key, v)`, `validate(key, v)`, `is_explicit(key)`, key constants (`Settings.TEXT_SCALE` …) | `changed(key, value)` |
| 3 | **Clock** | `autoload/clock.gd` | The only reader of wall time. Monotonic ticks. Writes `g_time` (wrapped at 600 s) and `g_motion` | `now_unix()`, `tz_offset_s()`, `now_local()`, `ticks_s()`, `override_now(unix)`, `override_timezone(s)`, `clear_overrides()`, `g_time`, `time_scale`, `frame_clock` (QA: time follows frame deltas) | `time_overridden` |
| 4 | **SaveService** | `autoload/save_service.gd` | Where and how the world is saved: a `SaveStore` at `user://save.json`, 30 s autosave, debounced action saves, quarantine | `register_provider(callable)`, `load_world()`, `save_now(reason)`, `request_save()`, `has_save()`, `quarantine()` | `saved(ok, reason)`, `loaded(source)` |
| 5 | **FrameGovernor** | `autoload/frame_governor.gd` | C21 frame rate (60 → 30 when idle or ambient, as refresh divisors), quality tier, hitch counter, keep-screen-on in ambient mode | `ambient_mode`, `poke()`, `hold_for(s)`, `tier`, `idle`, `target_fps()`, `hitch_count` | `tier_changed(tier)`, `idle_changed(idle)` |
| 6 | **Motion** | `autoload/motion.gd` | Motion tokens → tweens and springs, with Reduce Motion applied in one place | `duration(token)`, `tween(node, prop, to, token)`, `exit(…)`, `fade_in/fade_out(item)`, `apply_curve(tweener, curve)`, `spring(token, v)`, `spring_2d(…)`, `spring_to(obj, prop, to, token)`, `stagger_delay(i)`, `reduce_motion` | `reduce_motion_changed(on)` |
| 7 | **Haptics** | `autoload/haptics.gd` | D11 / AUDIO_BIBLE §7: off / subtle / full, 60 ms minimum gap. Android `performHapticFeedback` with constants read through `JavaClassWrapper`; iOS `vibrate_handheld`; never a buzz | `play(kind: StringName)`, `start_repeat(kind, interval_ms)`, `stop_repeat()`, `play_for_cue(map, cue_id)`, `mode` (persisted), `TICK`/`DOUBLE`/`MEDIUM` | — |
| 8 | **UiTheme** | `autoload/ui_theme.gd` | Builds the Theme from tokens, sets it on the root window, rebuilds on text size, language or transparency changes | `theme`, `rebuild()`, `attach(control)` | `theme_rebuilt(theme)` |
| 9 | **TimeOfDay** | `autoload/time_of_day.gd` | Art Bible PaletteDriver + WeatherDriver + celestial: clock → `g_day` → OKLab palettes → rain transform → shader globals | `phase`, `weather`, `g_day`, `colors`, `scalars`, `evaluate(local_s)`, `set_install_seed(seed)`, `set_world_offset(v)`, `set_overrides(g_day, weather)` | `phase_changed(phase)`, `weather_changed(w)`, `globals_updated(values)` |
| 10 | **AudioDirector** | `autoload/audio_director.gd` | Executes `audio/manifest.json` (AUDIO_BIBLE §8): bus graph, beds, pads, Eno voices, birds, critters, gusts, cues with pitch rules, haptics, ducking, music modes, volumes | `request_preload()`, `start_world_audio()`, `play_cue(id, ctx)`, `start_purr(voice_step)`, `stop_purr()`, `set_phase(p)`, `set_weather(w)`, `set_sheet_open(open)`, `set_music_mode(m)`, `set_volume(group, v)`, `set_mono(on)`, `set_world_state(shells, awake, sleeping)`, `set_install_seed(s)`, `current_chord()`, `current_pcs()`, `debug_set_clock(p, w)`, `stop_all()`, `slider_to_db(v)` | `cue_played(id, caption_key, world_position)`, `chord_changed(chord_name)` |
| 11 | **Game** | `autoload/game.gd` | Glue: owns `sim: WorldSim`; boot/load/catch-up; away-scene check on every return; per-frame advance (+ pending-scene foreground time); player-action API; lifecycle; Back button; greeter scheduling | `boot()`, `world_now()`, `tap_seed()`, `plant(flower, bed)`, `place(decor)`, `collect_all()`, `float_boat()`, `pet(species)`, `rename(species, name)`, `read_postcard(id)`, `display_name(species)`, `notify_world_visible()`, `push_back_handler(c)`, `remove_back_handler(c)`, `handle_back()`, `leave_now()`, `quit_cleanly(code)`; **Retention v1 (§5.2a):** `tap_sign(sign_key)`, `tap_scene()`, `scene_foreground_tick(dt)`, `on_background(world_t)`, `pending_scene()`, `visible_signs()`, `clue_cards()`, `clues_for(mystery)`, `heart_level(species)`, `unlocks(species)`, `unseen_hearts()`, `mark_hearts_seen(species)`, `nest_state(species)`, `nests()`, `memories()`, `keepsakes()`, `cousin_of(species)`, `variants_met()`, `best_buddy(species)`, `wave_plan()`, `can_rename(species)`; **Active Play v1 (§5.2b):** `feature_on(flag)`, `world_action(kind, args)`, `wish_foreground_tick(dt)`, `pause_wishes(reason, on)`, `report_wish_busy(species)`, `wishes()`, `wish_of(species)`, `wish_stamps(species)`, `wish_list_unread()`, `mark_wish_list_seen()`, `tea_unlocked()`, `harvest_bed(bed)`, `petals_ready(bed)`, `next_petal_in_s(bed)`, `pantry()`, `pot()`, `pot_add_petal(flower)`, `pot_remove(i)`, `pot_add_drop()`, `pot_remove_drop()`, `pot_stir(deg)`, `pot_pour()`, `simple_brew()`, `tray()`, `offer_cup(i, species)`, `recipes_found()`, `tea_prefs_seen(species)`, `buy_teaware(id)`, `use_teaware(id)`, `teaware()`, `decor_layout()`, `decor_placed_count(set)`, `decor_rules()`, `decor_context()`, `move_decor(piece, pos_norm, rot)`, `turn_decor(piece)`, `store_decor(piece)`, `take_out_decor(set, pos_norm)`, `lift_pebble(stack)`, `undo_decor()`, `can_undo_decor()`, `set_edit_mode(on)`, `edit_mode()`, `spot_position(spot)` | `world_ready(recap)`, `sim_event(ev)`, `wallet_changed(dew)`, `basket_changed(n, dew)`, `leave_requested`, `suspended`, `resumed`; **Retention v1:** `heart_up(species, hearts, offline)`, `mystery_opened(mystery, kind, target)`, `sign_appeared(sign)`, `clue_found(clue)`, `nest_grew(species, stage, offline)`, `scene_ready(scene)`, `scene_archived(memory)`, `cousin_met(variant, species)`, `cousin_arrived(variant, species, first)`, `keepsake_added(species)`; **Active Play v1:** `wish_opened(species, wish, visible)`, `wish_shown(species, wish)`, `wish_held(species, wish)`, `wish_granted(species, wish, affection, gift_flower, first_stamp, on_arrival)`, `tea_nook_awake`, `petals_harvested(bed, counts)`, `recipe_found(recipe)`, `tea_offered(species, recipe, reaction, petals)`, `teaware_changed(slot, id)`, `decor_placed(set, piece, pos_norm, rot_deg)`, `decor_stored(set, piece)`, `decor_edit_entered`, `decor_edit_exited` |

Rules:
- Autoloads talk *down* the list by direct calls and *up* by signals.
- No autoload holds a node from a scene.
- Scene scripts never instantiate pure classes that already have a shared instance; they use `ContentRegistry.content` and `Game.sim`.

### 3.2 Boot flow (`scenes/boot.tscn`, `scripts/boot/boot.gd`)

```
OS splash (#F0EEE9, Android export option) → engine boot splash (#F0EEE9, show_image=false)
→ Boot (Control)
     ├─ WarmupStage (ShaderWarmup, Node2D)   drawn first: every shader/material/font once, alpha 0.02 (C8)
     └─ Splash (ColorRect, ui.surface)       opaque, on top: the warm-up is invisible
  _ready: load_threaded_request(main.tscn); AudioDirector.request_preload()
  frame 1: splash visible → WarmupStage.run(2 frames) → Game.boot() → change_scene_to_packed(main)
→ Main: BootCover (same colour) fades out over `emphasized`; the camera settles from 1.03 to 1.00 over 2.5 s
  (GDD §3.4; a cross-fade only under Reduce Motion) → AudioDirector.start_world_audio()
  → Game.notify_world_visible() (greeter timer)
```

**Warm-up** (`ShaderWarmup`):
- Scans `res://shaders/**.gdshader` with `ResourceLoader.list_directory`, which works inside exported packs.
- Draws each `canvas_item` shader on an 8 px `ColorRect`. Each `particles` shader, and every `ParticleProcessMaterial` passed to `ShaderWarmup.register()`, gets a 1-particle `GPUParticles2D`.
- Draws every font in `res://fonts` at the five type sizes, using a Vietnamese sample string.
- **New shaders need no code change.** Code-made materials must call `ShaderWarmup.register(mat)` before boot runs (for example from an autoload's `_ready` or a static initialiser).
- Headless runs wait `process_frame`, because the dummy renderer never emits `frame_post_draw`.

### 3.3 Main scene tree (`scenes/main.tscn`; layer names per Art Bible §2.3)

```
Main (Node2D, main.gd)                    layout, camera = home + map pan + drift (≤ 4 dp/s, off under Reduce Motion), intro
├─ Camera2D                                home = centre of the visible rect; zoom 1.03 → 1.0 intro
├─ World (Node2D)                          position = g_world_offset = ((W−1080)/2, H−1920) — bottom-anchored (A1)
│  ├─ Sky        Parallax2D 0              L0  └─ Placeholder (PlaceholderBand SKY)
│  ├─ Celestial  Parallax2D 0.02           L1  (empty marker; the sky shader draws sun/moon/stars)
│  ├─ FarHills   Parallax2D 0.10           L2  └─ Placeholder (FAR)
│  ├─ MidHills   Parallax2D 0.30           L3  └─ Placeholder (MID)
│  ├─ Ground     Parallax2D 1.0            L4  play layer
│  │  ├─ Meadow                                └─ Placeholder (GROUND gradient)
│  │  ├─ Stream                                └─ Placeholder (stream polyline from spots.json)
│  │  ├─ Play (y_sort)                         ├─ Props · Plots (beds) · Nests · Signs · Decor · SceneProps · Creatures (each y_sort)
│  │  ├─ Particles                             Air: light shafts + ≤ 3 GPUParticles2D (D9)
│  │  └─ LayoutDebug                           --debug-layout overlay of the spots.json contract
│  └─ Foreground Parallax2D 1.3            L5  (empty)
└─ HUD (CanvasLayer 10)
   └─ HudRoot (Control, UiTheme.attach)
      ├─ SafeArea (SafeAreaContainer: max(OS safe area, 72 / 127 / 48 px floors))
      │  └─ Layout (VBox) ─ TopBar (216 px, Settings gear · dew · time · eye) · Spacer · Dock (pebble 204 px: Album · Garden · Basket)
      ├─ Sheets · Overlays (full-rect, mouse-transparent hosts)
      ├─ DebugReadout (--debug-hud)
      └─ BootCover (ColorRect #F0EEE9, fades out once)
└─ WorldPan (Node, world_pan.gd)           the one world input arbiter: target + map drag (§3.4-3.5); LAST child
```

Coordinates are design px in the 1080×1920 frame: `px = (x·1080, y·1920)` from `spots.json` (`GardenRules.frame_to_px`).
- On taller phones the extra height is sky above y = 0.
- On wider screens the 1080 column is centred.
- Layer geometry should extend to x ∈ [−400, 1480] (Art Bible §2.1).

### 3.4 Input: world taps and the map pan

World input is a chain, in Godot's order (the full contract is §3.5):
1. **GUI** (HUD, sheets, scrims, cards, toast, the top bar's band and the dock's gesture guard: `CanvasLayer` 10) consumes its own presses, so nothing below sees a touch on the HUD. `HudController._input` swallows the whole first gesture in ambient watch mode (`PointerGate`).
2. **`WorldPan._unhandled_input`** (`scripts/main/world_pan.gd`): the last child of Main, so it is called *first* among the unhandled handlers, and it is the **only** world input handler. It asks every node in group `WorldPan.GROUP_HIT` (creatures, plots, décor, props, brook) for its best candidate, picks **one** target, calls its `world_press` (touch-down feedback in the same frame, I1) and arms a pan. Nothing happens while a sheet or modal card is open (`blocked`); no pan starts within 24 dp of a side edge (`spots.json safe_x`, I2), though taps there work; a mossling claims the drag (a stroke pets it and never pans), and a pressed décor piece may claim it mid-press (`claim_drag()`, the Active F3 long-press). In Active F3 edit mode only group `GROUP_HIT_EDIT` is asked (§3.5).
3. On **release** within the slop the target's `world_release(act = true)` fires its action; a move past the slop cancels it (`act = false`) and starts the pan. A press that found no target is an empty press: two within `double_tap_ms` glide home (optional, never required, GDD §8.2).

Drag arbitration: motion and release are read in `WorldPan._input` (a drag across the dock keeps panning). Past `gui/common/drag_threshold` (24 px) the pending tap is cancelled and the pan starts from the slop edge (no jump); `drag_started` fires and the drag's motion and release events are consumed. One input path: touch index 0 on devices, the real mouse on desktop and web; emulated mouse events are ignored.

Motion (`PanBody`, pure; maths in `PanMath`; tokens `motion_tokens.world.pan`):
- **Bounds** per viewport: for each full-width layer with scroll s ≤ 1, the visible rect stays inside the authored x range (`TerrainMath.X_MIN/X_MAX`), so d ∈ [(x_min + ox)/s, (x_max + ox − W)/s] (±400 px on phones, ±220 at 1440 px wide, none past 1880). Vertically from `sky_up_px` (600) into the sky down to the home view (the frame bottom = the ground's bottom). The rest bounds sit `rubber_room_dp` (16 dp) inside, so the rubber band never shows past the geometry; no rubber band below the ground.
- **Feel:** 1:1 while dragging; on release an exact exponential glide (`glide_friction_per_s`); past an edge the rubber band (`rubber_k`) and the `move` spring back. Reduce Motion: no inertia, no rubber band (clamped), home is a cut.
- **Idle drift** pauses while the map is dragged or gliding (the current drift is folded into the pan, no jump) and resumes from zero over `drift_resume_s`, its amplitude capped by the distance to the rest bounds.
- **Followers:** `TimeOfDay.set_camera_pan` → `g_cam_pan`. The sun and moon *positions* stay pinned to the world (lighting, shadows and lamp pools are camera-invariant: everything world-space works in design px); the sky draws the discs and stars on L1 (0.02 × pan), and the sun veil and light shafts add `celestial_shift()` to follow the disc. Nodes in group `world_pan_view` get `on_world_pan(pan, cam, reveal_px)`: `SkyQuad` and `SilhouetteLayer` extend their bottoms (a skirt in the body-bottom colour, hidden at rest) by the gap the faster layer in front opens; `ForegroundFrame` keeps the 1.3× pieces from sliding far enough to show their cut edges (exact up to `fg_knee` × room, which covers the drift). The value frame and the brook (mesh only) run to x_max. Glass sheets read the screen texture and need nothing. Caption anchors are canvas px; the overlay applies the camera.
- **QA:** captures start centred (the pan is 0, so frames are unchanged); `--qa-pan=x,y` starts panned, clamped to the rest bounds (`--qa-pan=-9999,-9999` = left-top corner).

### 3.5 Input & hit-testing contract (round 7: "I often mis-tap" on a 720×1600 phone)

**One path per layer of the UI.** `input_devices/pointing/emulate_mouse_from_touch` stays on (GUI needs it). Input dispatches a touch's emulated mouse twin (device −1) *before* the `InputEventScreenTouch` itself.
- **World:** only `WorldPan` reads input, on the touch path (index 0) or the real mouse; emulated events are ignored. No world layer has an `_unhandled_input` any more, so nothing in the world can act twice or on both paths.
- **GUI:** `BaseButton` sees both twins and fires once (on the first release; the second finds no press attempt). Custom controls (`UiSlider`, the sheet swipe zone, the scrims, cards) read the mouse path only. `HudController._input` and `PointerGate` read both, and swallow both.

**Sampling rate (round 8).** Godot accumulates input by default: every event generated during a frame is merged and emitted once the frame is rendered, so a handler sees at most **one motion event per rendered frame** (checked on 4.7.2: `Input.is_using_accumulated_input()` is `true` at boot, and `input_devices/buffering/agile_event_flushing` is `false` — it only adds a flush before each *physics* step, which runs at 30 Hz here, and it is implemented for Android only, so it is left off deliberately). Two rules follow:
- **No gesture may be measured per event.** A per-event ceiling or step is really a frame-rate cap, so it makes the same hand movement count for less on a slower phone. Where a gesture accumulates something, its rules are geometric rather than per-sample: the tea stir takes any chord whose two ends are both in the ring and whose line misses the dead middle, so a coarse 30 fps stroke and a raw 240 Hz one credit the same total (`TeaPot.stir_delta`; `stir_max_deg_per_sample` 170° is only a guard under the ±180° shortest-arc wrap). Springs are already frame-rate independent by construction (`Spring` is analytic, Art Bible §10.2).
- **Hit shapes follow drawn shapes.** A tolerance measured as a circle around art drawn as an ellipse is dead where the art is flattest. The stir's dead middle is measured in *ring space* (the y axis stretched by the drawn progress ring's aspect) so the ellipse the player traces is live all the way round, while its outer bound stays a circle because that one only has to ignore the rest of the panel.
- **Only a path-integrating gesture turns accumulation off.** `InputPrecision` (`scripts/core/input_precision.gd`) is a counted hold on raw-pointer mode: `acquire(name)` / `release(name)` / `release_all()`. A gesture that only needs the *latest* position — the map pan, a carried décor piece, a slider, a petal under the thumb — gains nothing from it, because those are redrawn once per frame anyway; a gesture whose meaning is the path itself does. The tea stir is the only such gesture in the game and so the only holder; it releases on release, on a press that arrives without one, and in `_exit_tree` (a sheet that closes with a thumb down).

**World targets** (`world_hit(canvas_pos, slop) -> {prio, inside, core?, d, key, drag?}`, `world_press`, `world_release(key, pos, act)`, `world_drag`; debug shapes via `world_hit_shapes()`):
- **One target per press.** Candidates compare by tier, then priority, then distance. Tiers: core hit, then the rest of the hit area, then reachable only through the fat-finger slop (`SLOP_DP` 9 dp). Priority follows GDD §2.5 (as amended by §13.3.2 and §14.4 D5): choose-a-bed bed with room 8, mossling 7, mystery sign and away-scene prop 6 (`PRIO_SIGN`, `PRIO_SCENE`; round 10/11: a clue is there to be found and a scene to be looked at, so both outrank whatever a tap would do to the ground under them; a scene's participants are mosslings and rank as such), bed with a ready bud, the seed or ready petals 5 (`PRIO_PETAL_BED`), prop and the tea nook 4 (`PRIO_TEA_NOOK`), pinwheel and lantern 3, bed 2, stream and the still décor pieces (cairn stack, toadstool, stone: `PRIO_STILL`) 1; in edit mode pieces 9, the selected one 10 (`PRIO_EDIT`, `PRIO_EDIT_SELECTED`, pinned by `decor_placement.json hit`). Distance is to the target's centre. Only the winner gets the press.
- **Aim and slop.** A touch aims `AIM_UP_DP` (3 dp) above the contact (contacts land low, 02 §1.1). Décor keeps its 64 dp hit for empty ground, but only its 20 dp-radius core outranks a bed it overlaps.
- **Release-to-fire.** Feedback comes on touch-down; the action comes on release within the 24 px drag threshold. Moving further cancels it and pans: the tap slop and the pan threshold are one number, so there is no gap where neither or both happen. This covers props (basket, mailbox, chime), the brook, beds, décor and mossling taps.
- **One slop, on every target, including the mosslings (round 8).** A mossling claims the drag (a stroke pets it), so it runs its own tap-versus-stroke split — and that split used to use its own numbers: an 18 dp tap, a separate 24 px stroke gate, and a 60 ms minimum hold before a pet could begin. Two gestures therefore did nothing at all on the single most-tapped thing in the game: a thumb that slid 19–24 px (neither a tap nor a pet), and a quick flick across a friend that crossed 24 px inside the first frame (past the tap slop, but under the hold). Both now resolve: travel up to `creature_rig.json pet.stroke_drag_px` (24 px, the same number as `threshold_px`) is a tap, past it is a pet, and the hold is gone — the distance alone already rejects touch-down jitter.
- **A cancelled touch is not a release (round 8).** Android delivers a touch the OS takes away — the notification shade, the back-swipe, an incoming call — as an ordinary release with `InputEventScreenTouch.canceled` set. `WorldPan` reads that flag and treats it as a cancel: the pending tap is dropped and any drag ends without inertia, so a finger dragged off the screen by the system never fires a world action on the way out.
- **A claimed drag is interaction.** The `world_drag` branch pokes the `FrameGovernor` like every other branch, so a long stroke — petting a mossling — cannot be mistaken for idleness and halve the frame rate under the thumb.
- **No action after a drag, a fling or a cancel.** A press on a gliding map only stops it. A sheet or card that opens mid-press takes the tap. A long-press that fired the bed card never also taps.

**Active Play v1 additions (GDD §14.11 a6; `tests/test_active_input.gd`).**
- **`claim_drag()`.** The pressed target may take the drag while the finger is still within the slop and no pan has started (DecorLayer calls it when its 450 ms long-press fires, so one gesture enters edit mode and carries the piece). The pan is disarmed; later motion arrives as `world_drag(key, pos)` and the release as `world_release(key, pos, true)`. A drag past the slop *before* the long-press still pans, exactly as on a bed.
- **`empty_tapped(canvas_pos)`.** Every empty tap within the slop emits it (the double-tap glide is unchanged). DecorEdit uses it as "tap a destination".
- **Edit filter.** `WorldPan.edit_mode` follows `Game.decor_edit_entered / decor_edit_exited`. While on, `resolve()` asks only `GROUP_HIT_EDIT` (the DecorEdit controller: pieces at prio 9, +1 selected, 60 dp hit or 64 dp in the look zone around the visual centre, clipped above the dock); mosslings, beds, props and the brook are ground. `--debug-hits` draws that group in edit mode.
- **`nudge(delta_px)`** pans inside the rest bounds (no rubber band, no glide) for the edge pan while a piece is carried, and pokes the FrameGovernor.
- **`is_blocked()`** is public: Game pauses the wish clock while a sheet or card is open.
- **Wish fulfilment rides on release-to-fire.** Views report the actions the player already has through `Game.world_action(kind, args)` from `world_release(act = true)` only (`tap_creature`, `ring_chime`, `bed_tap` on every bed release whichever branch ran, `decor_tap`, `stream_tap`; pets and boats report themselves), so a pan or a cancelled press never grants a wish. The wish bubble is not a hit target.

**Sheets follow the finger everywhere (round 9).** The header swipe zone is only `HEADER_TOP + HEADER_H` = 228 px (76 dp) tall, which at the medium detent on a 1080×2400 phone puts every way to resize or dismiss a sheet in the top quarter of the screen — while the ~77 % of the sheet actually under the thumb did nothing at all. `UiSheet` now bridges the list to the sheet the way a nested scroll does: while the list is at `scroll_vertical == 0` and the finger pulls **down** past `LIST_HANDOFF_PX` (24 px, `gui/common/drag_threshold` — under both the 10 dp button slop and the list's 10 dp scroll deadzone, so the sheet claims first), the gesture becomes the sheet's and the list does not scroll. Any other direction, and any list with content above the window, scrolls as before; pulling *up* to expand from the medium detent is deliberately not taken, so a long list still scrolls without first growing the sheet. The handoff re-anchors (`drag_begin` at the live finger), so it costs no jump, and `TapGuard.cancel_in` drops the row press underneath it. A sheet grabbed mid-animation carries its live `rise` into the drag (`_drag_rise0`) instead of snapping up by what was left of the open.

**A rebuild never lands under a thumb (round 9).** A gift arriving, a bloom, a heart or a postcard fires a sim event, and the open sheet's `refresh()` rebuilds its rows — freeing the control a press belongs to, so the tap simply never happens. `SheetHost.refresh` holds the rebuild while `UiSheet.is_touched()` (a header or list drag, or a list still gliding) and applies it on the first frame after the finger leaves.

**GUI consumption (no through-taps).** Every surface that looks like UI stops presses (`MOUSE_FILTER_STOP`):
- **The sheet and its scrim.** The sheet's whole rect (padding, grabber, header) stops presses, and so does the full-screen scrim. While a sheet *closes*, it is input-dead (`mouse_behavior_recursive = DISABLED`, so a fast second tap on Plant or Collect never acts). Its rect and the scrim keep consuming until the sheet is freed. A scrim tap (press and release within 10 dp) closes the sheet and never reaches the world; a drag over it does nothing.
- **Modal cards and their scrim.** They behave the same way, and dismissing one needs a tap, not a drag.
- **The toast**, while shown and while it fades.
- **The top bar's band.** It runs from the top of the screen to the bottom of the gear and eye hits, over the chips and the gaps between them. Under an open sheet it yields to the scrim, so a tap there still closes the sheet.
- **The dock.** The pebble stops presses, the tabs tile it edge to edge, and the tabs reach down to the gesture guard. The guard is a full-width strip over the bottom inset (max(safe bottom, 127 px)); presses that start in the gesture-bar zone do nothing.

**Buttons** (`TapGuard`, wired by `PressFeedback.attach`):
- **Press slop.** A press that travels more than 10 dp (30 px) is cancelled (no action, the visual springs back). Sliding off cancels too.
- **Scroll-through.** Buttons inside a `ScrollContainer` pass their presses on (`MOUSE_FILTER_PASS`), so a drag that starts on a button scrolls. The list's `scroll_deadzone` is 30 px (`gui/common/default_scroll_deadzone`), and its `NOTIFICATION_SCROLL_BEGIN` cancels the press.
- **Fling catch.** A press while the list is still moving only stops it.
- **Debounce.** A second press within 350 ms of an action on the same button is swallowed: one purchase, plant or collect per press, and no double-open of a dock tab.
- **Selection on release.** Dock tabs and buttons fire on release. Tapping the active dock tab closes its sheet (GDD §8.1, kept).

**Sliders.** `UiSlider` is `PASS`. A press stays pending until it moves. Horizontally past 24 px it becomes a slider drag, the only case that consumes the motion. Vertically past 10 dp it is the list's scroll and the value never changes. A tap jumps to the nearest detent.

**Ambient watch.** The first gesture only wakes the HUD. `PointerGate` swallows the touch, its twin, their moves and both releases.

**Sizes and gaps** (GDD §8.4):
- Dock tabs ≥ 76 dp (88 × 88, the hero 96 × 93).
- The gear and the eye 72 dp.
- In-sheet buttons, sliders, segments and rows ≥ 48 dp; the sheet × is 60 dp and nothing sits next to it.
- At least 8 dp between discrete targets: the tabs-to-list gap (`UiSheet.TABS_GAP`) and the padding of rows that hold their own steppers or sliders keep it. Full-width Settings list rows stack under a hairline (the Material list pattern), and contiguous dock tabs share edges by design.
- Nothing in the app is irreversible ("Leave for now" saves first), so no primary action sits next to a destructive one.

**QA.** `--debug-hits` (`HitDebug`, CanvasLayer 100) draws every live world hit area with its slop ring and core, and every UI target and consumer with its size in dp. It flags targets under 48 dp (red), overlaps (magenta) and gaps under 8 dp (orange), and prints a `debug-hits:` summary. World areas are hidden while the world is blocked. Renders: `qa/out/hits/`.

---

## 4. Data flow

```
data/*.json ─┐                                     ┌─> Game.sim_event ─> views (creatures, beds, HUD, recap, audio cues)
audio/manifest.json ─> GameContent (ContentRegistry) ─> WorldSim (Game) ─┤
i18n/strings.csv ─> .translation ─> TranslationServer        │          └─> SaveService (provider) ─> user://save.json
                                                             │
Clock (wall + ticks) ─> Game.world_now() ─> sim.advance()    │
Clock.now_local() ─> TodMath.g_day_at ─> PaletteDriver (OKLab) + WeatherPlan/WeatherDriver + Celestial
                 ─> TimeOfDay ─> RenderingServer.global_shader_parameter_set(g_*) ─> every shader
Settings.changed ─> Clock (g_motion), Motion, Haptics, AudioDirector, UiTheme, FrameGovernor, I18n
```

- **`GameContent`** (`scripts/core/game_content.gd`) indexes the raw documents: species by album order, flowers and décor by garden order, phases by start, beds by fill order, and lookups by id. It implements the formulas `price(item, n)`, `hearts_for(affection)`, `catalogue_size()` and `season_for_world_day(d)`.
  - It checks schema versions, required top-level keys and cross-references, and reports problems in `errors`; it never crashes.
  - The full content lint stays in `tools/sim/validate_content.py` (GDD §10).
  - Tests build their own instance with `GameContent.load_from_dir()`, or inject edited documents with `GameContent.from_documents()`.
- **Weather and phase agree** between gameplay and picture because the sim and TimeOfDay call the same pure `TodMath` and `WeatherPlan` with the same install seed. Game calls `TimeOfDay.set_install_seed()` after loading.

---

## 5. The deterministic sim (`scripts/sim/`)

### 5.1 `WorldState` — everything the world remembers
Plain typed fields (GDD §5.8 persistence list), serialised by `to_dict()` and restored by `from_dict()`. `from_dict()` coerces every value to its declared type and clamps counts and clocks at 0, so a damaged or hand-edited file can never inject a wrong type or a negative value.

| Group | Fields |
|---|---|
| Identity / RNG | `install_seed` (int64, saved as a decimal string), `installed_unix`, `rng_state` (RandomNumberGenerator.state, saved as a string) |
| Clocks | `t` (world seconds, monotonic) · wall anchor `anchor_world_t`, `anchor_unix`, `tz_offset_s` |
| Wallet / basket / cup | `dew`, `basket[{species, gift_item, dew}]`, `cup`, `cup_last_t`, `last_collect_t` |
| Garden | `owned{item: copies}`, `stems[{flower, bed, slot, planted_t, tutorial, stage}]`, `items_bought` |
| Visitors | `present[{species, arrive_t, depart_t, gift_dew, gift_item, boat_credit, pet_credit, scripted, greeter}]`, `next_candidate_t`, `scripted[{t, kind, species, stay_s, gift_dew, id, role}]` |
| Relationships | `met{species: first_met_unix}`, `names`, `affection`, `photos{species: 5-bit mask}`, `photo_meta{"species/pose": {phase, weather, world_t}}`, `postcards[{id, template, species, received_unix, read}]`, `boats`, `last_pet_unix` |
| Flags | `seed_planted`, `seed_tap_t`, `basket_full_seen`, `first_bloom_postcard_sent` |
| Retention v1 (schema 2, GDD §13.6) | `retention_v` (content-aware migration done), `visit_aff_t`, `hearts_seen`, `nests{style, built_t, stage}`, `postcards_waiting`, `mysteries{kind, target, open_t, ok_t, solved_unix}`, `signs[{mystery, index, type, appear_t, anchor}]`, `clues{mystery: bitmask}`, `variants_met`, `cousin_visits`, `scene_returns`, `scenes_seen`, `scene_cast`, `pending_scene{scene, cast, phase, weather, world_t, shown_s}`, `memories[{scene, cast, phase, weather, world_t, unix}]`, `keepsakes`, `signature_gifts`, `last_bg_t`, `open_count`; `basket[].signature`, `present[].cousin` |
| Active Play v1 (schema 3, GDD §14.9) | `active_v` (content-aware migration done); **F1** `wishes[{species, wish, opened_t, state open/held, taps, placed}]`, `wish_checks` (hash index), `wish_fg_s`, `wish_last_t`, `wish_friend_t`, `wish_visit_count{species: {arrive_t, n}}`, `wish_last_id`, `wish_aff_t`, `wish_stamps{species: bitmask over wishes.json order}`, `wishes_granted`, `wish_tutorial_done`, `wish_list_seen_t`; **F2** `tea_unlocked`, `petal_from_t{"bed:slot": t}`, `pantry`, `pot{petals, drops, stir_deg}`, `tray[{recipe, made_unix, drops, petals}]`, `recipes_found`, `tea_prefs_seen`, `tea_aff_t`, `teaware_owned`, `teaware_set`, `cups_offered`, `tea_flags`; **F3** `decor_layout[{id "set#n", set, x, y, rot, stored, stack, level}]` |
| Active Play polish (schema 4) | `tips_seen{tip id: true}`: one-time tips already shown (`Game.TIP_DECOR_LONG_PRESS` after the first movable décor purchase, `Game.TIP_WISH_KEPT` the Album's held-wish note); `Game.tip_seen` / `Game.mark_tip_seen` |

### 5.2 `WorldSim` — the world step

**Time mapping.**
- `unix_at(t) = anchor_unix + (t − anchor_world_t)` and `local_at(t) = unix_at(t) + tz_offset_s`.
- Phase and weather are looked up at `local_at(t)`.
- The anchor is reset on launch, on resume and on every save.

**`advance(to_t)`** processes every event in (t, to_t] in time order. On ties the order is **scripted → growth → departure → candidate**, as in the reference. The events are:
- **Scripted:** onboarding arrivals and the welcome postcard.
- **Growth:** each stem moves seed → sprout → bud → bloom at `planted_t + stage time`. The tutorial seed uses `onboarding.tutorial_*_at_s`. The cup is settled before a bloom changes the cup rate.
- **Departure:** the visitor leaves its gift in the basket, or a photo when the basket holds `basket_slots` gifts. The greeter leaves nothing.
- **Arrival candidate:** a homogeneous process at λ_max, thinned to λ(S) = λ_min + (λ_max − λ_min)·S/(S + S_half).
  - **Eligible species:** not present, every `requires` met (bloomed stems or décor copies), in an allowed `phases`, and in season.
  - **Debut rule:** with probability `debut_chance` the pick is made among never-met species only. The pick is weighted by base × likes × best-friend multiplier.
  - When more than `max_present` real visitors would be present, the arrival becomes a peek visit.

Between events, `advance` is O(1): it caches the next event time and only settles the cup, so calling it every frame is free. **E1 holds by construction:** nothing in `advance` removes or decreases anything the player owns.

**Offline catch-up** is `catch_up(now_unix, tz, saved_at_unix)`:
- `delta = clamp(now − saved_at, 0, offline_clamp_s = 7 d)` (C14). The world advances by `delta`; anything beyond that is skipped ("the hollow rested").
- The anchor is set *before* advancing, so wall(t_event) = now − (world_end − t_event).
- A rolled-back clock gives delta = 0 and only re-anchors.
- It returns `{raw_s, delta_s, skipped_s, rolled_back, events}`.

**Player actions.** None of them can fail into a loss; on failure they return false or −1 and change nothing.
- `tap_tutorial_seed()` plants the free clover, and within the tap window pulls Pip and Dot forward.
- `buy_flower(id, bed)` follows the GDD §2.4 rules in `GardenRules`: the first copy goes to the chosen bed, or the lowest fill order. Later copies go to the bed holding most of that type, else the nearest bed with room. Inside a bed, a stem takes the free slot nearest the centroid of its type.
- `buy_decor(id)`.
- `collect()`: the wallet cap holds gifts back in the basket, and the cup's fractional remainder stays.
- `float_boat()`.
- `pet(species, now_unix)`: once per visit; for the greeter, only after `greeter_pet_cooldown_s`.
- `add_greeter(t)` / `dismiss_greeter()`.
- `set_custom_name()`, via `NameRules`: filtered to the font coverage, NFC-normalised, at most 12 characters.
- `mark_postcard_read()`.

**Queries.** `price_of`, `can_buy`, `needs_bed_choice`, `catalogue_options`, `snugness`, `lambda_per_h`, `cup_rate_per_h`, `cup_brimming`, `basket_full`, `hearts_of`, `is_met`, `income_per_min`, `displayed_values` (E6 audit), `monotone_snapshot` (E1 audit).

**Events (outbox).** Every change appends `{type, t, …}`, which Game drains each frame and re-emits as `Game.sim_event`. Catch-up events carry `catch_up: true`.

| type | fields | typical view reaction |
|---|---|---|
| `arrived` | species, debut, peek, scripted, from_greeter, depart_t | creature fades in at its `entry` (400 ms), S12; a debut opens the new-friend card (S09) |
| `departed` | species, gift_dew | stretch, wave, gift flies 600 ms to the basket |
| `greeter_arrived` / `greeter_left` | species | stroll in / out, no gift |
| `met` | species | album entry, new-friend card |
| `gift` | species, gift_item, dew, slot | basket badge, basket tile |
| `photo` | species, pose, new | album photo strip |
| `basket_full` | — | brim sparkle on the dock button (the dock shows the basket's fill by what peeks out, never a count) |
| `stage` | stem, flower, stage (3 = bloom) | grow step / ready bud glow (GDD §3.1) |
| `hearts` | species, hearts | `celebrate` heart burst |
| `postcard` | id, template, species | mailbox flag, S16 |
| `collected` | dew, gifts, cup, kept | gifts fly to the HUD, counter roll; `kept > 0` → "dew jar is brimming" |
| `planted` / `placed` | stem/decor, bed, slot, index, cost, tutorial | seed arc / piece settles, S05 |
| `boat` | count, watchers | boat at the spring rock, watchers gather |
| `petted` | species, credited | hearts on release (the credit is never shown) |
| `mystery_opened` | mystery, kind (species/variant), target, signs | Album › Clues card |
| `sign_appeared` / `clue_found` | the sign record / the clue taken | `SignLayer` draws it in the hollow (round 10); tapping it toasts `CLUE_FOUND_*`, or opens the riddle card for the note |
| `nest_grew` | species, stage, offline | `NestLayer` draws every nest (round 11); a stage reached while watching pops; the brain naps the friend in it (`CreatureBrain.nests`) and the recap's nap line names the nest |
| `scene_ready` / `scene_archived` | the pending scene / the memory | `CreatureLayer._stage_scene` walks present cast to their slots and summons absent cast as extras; `SceneLayer` draws the props and is their tap target; a tap on either calls `Game.tap_scene`; archived → `SCENE_SAVED` toast, the Album refreshes, everyone resumes (round 11) |
| `keepsake_added` | species | Album › Keepsakes (round 11) |
| `sign_due` / `sign_visible` | key, mystery, index, sign (type), species, variant, anchor, appear_t, footprint, dropped, tint | a visible sign fades in at its anchor (600 ms); `due` alone = queued (≤ 3 visible) |
| `clue` | sign fields + riddle_key, found, total, solved | `clue_lift` + S23, toast; a note opens the riddle |
| `nest_stage` | species, style, stage, stage_id, built | nest built (stage 0) / grew |
| `scene_staged` | scene, cast, phase, weather, world_t, shown_s, resumed, new_memory, first_time | stage the away scene, recap teaser, S25 |
| `scene_archived` | scene, cast, phase, weather, world_t, unix, index | Memories; `SCENE_SAVED` toast |
| `cousin_met` / `cousin_arrived` | variant, species (, first) | new-friend card with `NEWFRIEND_COUSIN_TITLE` / the cousin walks in with its base |
| `keepsake` | species | Keepsakes dot |
| `hearts` (extended) | species, hearts, from | heart-up celebrate + toast (`unseen_hearts()` for offline ones) |
| `gift` (extended) | + signature, first_signature | `BASKET_SIGNATURE_NOTE` under the first signature gift |

**Onboarding (GDD §3.4)** is scheduled at install with provisional times: Pip at 30 s, Dot at 150 s, Cobble at 210 s, the welcome postcard at 240 s, and Poisson visits from 300 s. A seed tapped at t ≤ 25 s reschedules Pip to clamp(t + 15, 20, 40) and Dot to min(t + 90 + 15, 150). The tutorial hints are view-side.

**Recap (`Recap.build`)** produces up to 3 lines in GDD §13.5.3 priority order: new friend → away-scene teaser → cousin → postcard → hearts → a wish granted on arrival (`RECAP_WISH`, Active F1) → clue → visitors → nest → gifts waiting → blooms → photos → rain; a staged scene's teaser always gets a line. It appears only when the gap is at least `welcome_back_min_gap_s` and something happened. Lines are `{key, species}`, so the UI formats names and language at display time.

**Greeter (GDD §5.6).**
- On launch or resume, if nothing happened or nobody is present, Game marks the greeter as wanted.
- Once the UI calls `Game.notify_world_visible()`, it waits `greeter_delay_min..max_s`, then `sim.add_greeter()`.
- The greeter leaves when the app is backgrounded. A real arrival of the same species converts the greeter into the visit.
- **Active Play (GDD §14.2.3).** The greeter is preferably a met, absent friend holding a wish (oldest first, `WishRules.greeter_pick`); the pool draw still runs first, so the world RNG stream is identical with or without a wish. It brings that wish back for its stay and never spawns one; a cup gives it 0 affection and no petals back.

### 5.2a Retention v1 (`RetentionRules`, `RetentionHash`; GDD §13)

`WorldSim.retention` is a `RetentionRules` holding the content-derived constants and **no reference back** to the sim (no RefCounted cycle): every hook takes the sim as its first argument. It ports the retention half of the reference `Player` and is called from the one world step, so live play and offline catch-up share it.
- **Hash.** `RetentionHash.u(seed, parts)` is §13.1 (FNV-1a 64 + splitmix64, logical shifts masked). Sign times, scene roll and pick, and wave delays use it; the world RNG stream is never touched (tested: `rng_state` is unchanged by every retention call).
- **Hooks in the world step.** `_arrive`: `on_debut` (mystery solved, waiting ♥4 postcards sent, all met → cousin mysteries), the 20 h `visit_affection_due` rest, `gift_item_for` (signature gift from ♥2), `on_base_arrival` (cousin debut / every 3rd visit, stored as `present[].cousin`; like the reference it takes no economy place). `_add_affection`: `on_heart_level` per level (♥2/♥4/♥5 stories, ♥4 waits for an unmet buddy, ♥3 nest, ♥5 keepsake), then `after_hearts` (♥5 → cousin mystery). `_eligible`: `debut_ok_t` (onboarding −∞, not opened +∞, else last sign + 1,800 s). `check_mysteries` after every bloom, décor purchase, the last friend met, a ♥5 heart-up and the migration.
- **Timed retention events** join `advance()` as a fifth source (`next_event_t`): a sign coming due (`sign_due`; `fill_visible` then gives it one of ≤ 3 slots at the nearest free anchor of its type, ties by anchor order) and nest stages (`nest_stage`, derived from `built_t`, never lower than stored). Tie order: scripted → growth → retention → departure → candidate.
- **Away scenes** are not in `advance()`: Game calls `retention.on_return(sim, t_bg, t_now)` after each catch-up (boot from a save: t_bg = the saved world t; resume: `last_bg_t`, set on suspend). It needs ≥ 2 h; a pending scene is re-shown instead of a new pick; `scene_returns` = r; roll and pick by hash; absence profile sampled every 600 s; unseen-first pool; casting = prefer lists, then new faces, present first, hearts, album order; pair scenes take the best-ranked best-buddy pair meeting `pair_hearts_min`, higher hearts first. `stage_scene` never replaces a pending scene unseen. `tap_scene()` or 600 s of `foreground_tick` archives it to `memories`.
- **Read models** for P2 (`unlock_list`, `unseen_hearts`, `nest_view`, `clue_cards`/`clue_card`, `cousin_view`, `keepsake_view`, `buddy_view`, `visible_signs`, `wave_plan`) are pure and wrapped by `Game` (§3.1).
- **E1/G1.** `monotone_snapshot()` also covers hearts, nest stages, clues + waiting signs, mysteries, cousins, memories + pending, scenes seen, keepsakes, signature gifts and postcards + waiting.
- **Not in the sim (creature brain, P2):** nest nap preference 0.7, pair bouts, wave-on-open poses, cousin bouts, staged-scene slots and staged friends as greeters (GDD §13.9).

### 5.2b Active Play v1 (`ActiveRules`, `WishRules`, `TeaRules`, `DecorPlacementRules`; GDD §14)

`WorldSim.active` is an `ActiveRules` that holds the three pure rule objects and the feature flags (`FEATURES_V1`: `wishes`, `tea`, `free_decor`, all on; `Game.feature_on`) and, like `RetentionRules`, **no reference back**: every call takes the sim. Content comes from `GameContent` (`wishes.json`, `tea.json`, `decor_placement.json`: required keys and cross-references checked at load, the full lint in `validate_content.py`; tea's event postcards are merged into `event_postcards_by_trigger`).
- **Active F1 `WishRules`** (port of the reference `wish_*`). `foreground_tick(sim, dt, blocked)` accumulates `wish_fg_s` and runs one `check(sim, t)` per `spawn_check_s`; Game calls it from `_process` and passes `blocked` while a sheet, card, edit mode or `pause_wishes` is on. **It never runs inside `advance()` or catch-up**, so offline time spawns nothing (AP6). `check`: the scripted teaching `cuddle` (first present onboarding friend, `poisson_start_s + after_onboarding_s`), caps (2 visible, 4 pending, 1 per friend, 2 per visit), gaps (90 s global, 600 s per friend), then hash draws `["wish_roll", n]`, `["wish_friend", n]` (candidates in album order: real visitors present ≥ 45 s, not reported busy), `["wish_pick", n]` over the weights `weight × (1 + trait_bonus × matches) × prefer × boost(phase × weather) × unseen × repeat` of the eligible wishes (requires hold now: blooms, **placed** pieces, feature and tea unlock, best buddy present, `not_already_near` = no placed piece of the set within `near_dp` of the friend's favourite spot; `spawn_when` gates appearance only). Fulfilment: `on_action` (pet, play_taps, chime, bed with that flower blooming, décor tap, stream, boat: every open wish of a present friend that the action matches, collected first, then granted), `on_offer` (tea targets via `TeaRules.satisfies`), `on_decor_placed` (`decor_near`: granted now if the friend is here, else `placed` and granted on its next arrival). `grant` is atomic: removed, stamp bit, +1 affection on its own 20 h `wish_aff_t` rest, one gift petal by the shared rule (tea unlocked, jar cap), slot refilled. `on_arrive` / `on_depart` move wishes between open and held (never removed); `greeter_pick` (§5.2).
- **Active F2 `TeaRules`** (port of `petals_ready`, `harvest`, `offer`, `tea_satisfies`; no randomness). Petal anchor per stem `petal_from_t["bed:slot"]` (absent = bloom time, `WorldSim.stem_bloom_t`), `ready = min(hold, ⌊(t − pa)/regrow⌋)`; `harvest_bed` takes petals in stem order within each jar's room and moves the anchor (`pa += k·regrow`, or `t − (ready − k)·regrow` on a full stem); the flower's stage, dew and attraction never change. Pot ops (`pot_add_petal/remove`, `pot_add_drop/remove_drop`: 3 dew charged in, refunded out; `pot_stir`; `pour(simple)`), `GameContent.match_recipe` (exact multiset + drops, else the fallback per drop count: every pot makes something), the tray (≤ 6, cups keep their petals for `tea_petal` wishes), `offer` (reaction loved/liked/content, never a dislike; affection once per friend per 20 h on `tea_aff_t`, the greeter 0; petals back by the gift rule; then `WishRules.on_offer`), known preferences (seen or ♥3), teaware (a pure sink, snug 0), the nook unlock (after the welcome postcard time and a bloom; checked at the end of `advance`), postcards `first_tea` / `tea_book`.
- **Active F3 `DecorPlacementRules`** (pure; the front-end calls it through `Game.decor_rules()` with `Game.decor_layout()` and `Game.decor_context()` for the live drag): `validate` → one soft reason (`sky`, `low`, `edge`, `water`, `dry`, `flowers`, `spot`, `nest`, `prop`, `crowded`, `stack`; `hint_key` → `DECOR_HINT_*`), `validate_hard`, `sockets` (same-set rings, the fairy ring around a cluster ≥ 3, water and bank lines, legacy anchors, spot sides; valid ones only), `snap` (14 dp magnet, family priority then nearest), `magnet` (the ≤ 70 % visual pull), `nudge` (48 dp ring search, 4 dp rings), `jitter` (±1.5 dp hash of piece and position), `resolve_drop`, `merge_target` (cairn ≤ 14 dp, ≤ 10 high), `clusters`, `derived_spots`, `auto_place` (anchor n if valid → best socket by the largest cluster → spiral from anchor 0 → tray), `nearest_piece_dp`, `is_clear`, `migrate_v1`, `sync_owned`. `ActiveRules` owns the layout operations (`move`, `turn`, `store`, `take_out`, `lift_pebble`, one-step `undo` per edit session) and emits `decor_placed` **only after a settle** (a failed move changes and emits nothing), `refresh_spots` on load and edit-mode exit, `on_decor_bought` (a purchase is auto placed; a new pebble joins the tallest stack with room). **Attraction, snug and spot gating keep counting owned copies** (placed or tucked away); only wish gates and fx read placed pieces (`decor_placed_count`).
- **E1/AP2.** `monotone_snapshot()["active"]`: pending + granted wishes, stamps, grants, petals ready + in jars + in the pot, recipes, teaware, cups offered, tray + offered, layout records. `displayed_values()` adds teaware prices, jar counts and the drop price (E6).

### 5.3 Parity with `tools/sim/economy_sim.py`
Rules, data and the order of operations are ported 1:1. The known differences are listed below; none of them changes any GDD rule:
- **RNG engine.** Godot's PCG32 (`RandomNumberGenerator`, whose state is persisted) replaces numpy's PCG64. The results are statistically equivalent but not bit-identical, which is why the GDScript E5/E6 test re-checks the invariants instead of comparing numbers.
- **Growth tie order.** It is (time, stage, stem index) instead of the heap's (time, stage, flower index).
- **`first_bloom` postcard.** It is sent for the first bloom of a *bought* stem, which is the GDD intent; the reference used "any bloom after the first purchase".
- **Greeter and live tap times.** The greeter and the live seed-tap rescheduling exist only in the game; the reference knows the tap time up front.
- **Retention (bit-exact).** All retention randomness is the stateless hash, so `tests/test_retention_parity.gd` replays the reference's scripted schedule (`python3 tools/sim/economy_sim.py --parity-export tests/fixtures/retention_parity.json`: visits, pets, garden counts, sign taps, 21 returns with fixed absence profiles, two cousin debuts) and matches affection, the rest, hearts, story postcards and waits, nests, every mystery `open_t`/`ok_t`, every sign `appear_t`, clues, cousins and every scene roll, pick and cast. Regenerate the fixture after any rule or data change. Game-only bookkeeping the reference does not model: sign anchors and visibility, nest stage events, pending scenes and linger, cousin repeat visits, signature gifts, keepsakes, `hearts_seen`, the migration.
- **Active Play (bit-exact).** `tests/test_active_parity.gd` replays `python3 tools/sim/economy_sim.py --active-parity-export tests/fixtures/active_parity.json` (467 ops generated online from the reference model: 260 foreground checks with the sky pinned, visits and departures, help through each wish's own action, gathering, brewing, offering, two gaps past the 20 h rests; no world-RNG draws) and matches after every op the wish list (species, wish, open/held, `opened_t`), `wish_checks`, both gaps, both rests, stamps, grants, the teaching wish, affection, the nook, every petal anchor and jar, the book, the tray, cups offered and the wallet. Friends with an always-on favourite spot only, so `not_already_near` agrees (the reference stands copy n at its legacy anchor). `retention_parity.json` is unchanged. Game-only: the pot steps, teaware, the layout operations and validity, derived spots, the migration, events.

Two greeter numbers stated only in GDD prose were added to `data/economy.json` as `greeter_stay_s: 300` and `greeter_pet_cooldown_s: 3600`. `validate_content.py` still passes.

### 5.4 Not in the sim (contract for the creature brain)
Behaviour bouts, spots, walking paths, hops, look-at and every other position are **view-side**, owned by the Gameplay Engineer's creature brain under `Main/World/Ground/Play/Creatures`. The rules are:
- The brain reads `sim.state.present` and `arrived/departed/greeter_*` events.
- It plans bouts by the GDD §4.1.3 rules: 120–360 s, never repeating the previous (behaviour, spot) pair, ×3 nap at night, shelter in rain, favourite spot 60 %, spot capacity.
- It must be seeded per visit, as `hash([install_seed, species, arrive_t])`, so the same visit always looks the same after a reload.
- **Nests (round 11, GDD §13.2.3).** With `brain.nests` set (a `Callable(species) -> nest view`), a nap draws the friend's own nest spot `nest:<species>` with p `nap_preference` (0.7) before the normal spot rule, never twice in a row; capacity 1, nobody else's. The draw happens only for a friend WITH a nest, so every other visit plans exactly as before. `nap_during` wires the sim's nests, so an absence's longest nap can be in one and the recap says so.
- **Away scenes (round 11, GDD §13.4).** A staged scene is not a bout: present cast members are held under `_override_until = INF` and walk to `SceneLayer.slot_px`; absent ones are summoned as extras (no visit, no gift, no affection) and leave on archive. The scene poses (`scene_*`, `pair_nap_*`) are rig work still to come; `SceneLayer.scene_pose` maps them to nap / sit-by-stream / stand-look-and-beam.
- **Nothing in a bout can change state.** Pet, boat and tap all go through `Game`.
- The recap's "{name} napped at the {spot}" line needs the brain to report the longest nap per absence. Until then the recap uses the "dropped by" lines.

---

## 6. Save system (`SaveStore`, `AtomicFile`, `SaveService`)

**File** `user://save.json`. It is one JSON object, written by `JSON.stringify(doc, "\t", sort_keys, full_precision)`:
```json
{ "format": "mossling-meadow-save", "schema": 4, "app_version": "0.1.0",
  "saved_at_unix": 1792700000.25, "sha256": "<hex>", "world": { …WorldState.to_dict()… } }
```

**Write** (`AtomicFile.write_text`):
1. Write `save.json.tmp`, then flush and close.
2. Re-read the temp file and `decode()` it; on failure, abort and keep the old files.
3. Move `save.json` to `save.json.bak`.
4. Rename `save.json.tmp` to `save.json`.

A crash at any step leaves at least one complete file. Saving is synchronous and small (22 KB and 7 ms measured for a mid-game save), well inside iOS's ≈ 5 s pause budget.

**Read** tries `save.json`, then `.tmp` (an orphan of a crash between steps 3 and 4), then `.bak`. It takes the first file that parses, has a supported schema and a matching checksum. Every skipped file is reported with a warning. If none is readable, Game **quarantines** the files (`*.broken-<unix>`, never deleted) and starts a new install.

**Checksum.** Measured on 4.7.2: Godot's number parser is not correctly rounded, and about 12 % of 17-digit doubles come back 1 ulp off.
- The checksum is therefore computed over the *parsed-back* encoding at save time: `sha256(stringify(normalize(parse(stringify(world)))))`. The same text always parses to the same doubles, so verification at load is exact. `normalize` is `WorldState.from_dict(...).to_dict()`.
- A reload can differ from the in-memory state by ≤ 1 ulp per float, which no game rule can observe. Tests compare floats to 10 significant digits (`TestUtil.canonical`).
- **Deviation from D12's "`from_native`", for the record:** 4.7.2's `JSON.from_native` stores floats as `"f:<15 digits>"` strings. That is a much larger loss and an unreadable file, so typed `to_dict`/`from_dict` with explicit coercion is used instead. It is equally safe, because objects are never deserialised.

**Schema evolution.**
- Bump `SaveStore.SCHEMA` when `to_dict()` changes shape, add the old schema to `MIGRATABLE` and a `match` arm to `SaveStore.migrate(from_schema, world)` (pure and additive: it never overwrites or removes a key).
- Older files are migrated forward, without checksum, before normalisation; the next save writes the current schema with its checksum. The main → `.tmp` → `.bak` order is unchanged, so an old `.bak` behind a corrupt main file is migrated too.
- Newer files are refused (`unsupported schema`) and never misread.
- **Schema 1 → 2 (Retention v1, GDD §13.6).** `SaveStore.migrate(1, w)` adds every new field empty (`RETENTION_V1_DEFAULTS`, with `retention_v = 0`); `WorldState.from_dict` adds `basket[].signature = false` and `present[].cousin = ""`. The content-aware steps need the data, so `WorldSim._init` runs `RetentionRules.migrate_v1` once when `retention_v < RETENTION_VERSION`, at the saved world time: `hearts_seen` = hearts; nests (twigs) for ♥3+; ♥4/♥5 stories not yet delivered by template (♥4 waits for an unmet buddy; if an MVP `<species>_h4` card with the old shared template holds the id, the new story gets `<species>_h4_story`); keepsakes for ♥5; then `check_mysteries`. Affection is untouched and the 20 h rest starts empty. Tested from a real schema-1 save written by the MVP code (`tests/fixtures/save_schema1.json`).
- **Schema 2 → 3 (Active Play v1, GDD §14.9).** `SaveStore.migrate(2, w)` adds every new field with its default (`ACTIVE_V1_DEFAULTS`, `active_v = 0`; literal, so the step keeps meaning "2 → 3") and never overwrites a key; a schema-1 file runs 1 → 2 → 3. `WorldSim._init` then runs `ActiveRules.migrate_v1` once when `active_v < ACTIVE_VERSION`, after the retention step, at the saved world time: copy n of each movable set takes `spots.json decor_anchors[set].positions[n]` verbatim (rot 0, placed), the lantern jitter (`DecorPlacementRules.legacy_lantern_jitter_px`, the old `DecorLayer` hash-seeded RNG) baked into x, every cairn pebble one stack at `anchors[0]` in copy order, the chime not in the layout; only the hard exclusions (hard props, the tea nook) nudge a piece by the ring search (on today's data pinwheels `anchors[4]` by 8 dp and `anchors[8]` by 16 dp; nothing else moves, ≤ 0.5 px); `tea_unlocked` if onboarding is done and a stem blooms; no wish open, the teaching wish still to come; petal anchors absent (full stems). Affection, hearts, `owned`, `rng_state` and every Retention field are untouched. Every load also runs `ActiveRules.on_load`: owned movable copies missing from the layout are auto placed (a fixture or a later purchase) and the derived spots are computed. Tested from a real schema-2 save written by the pre-Active code (`tests/fixtures/save_schema2.json`), through boot as well.
- **Schema 3 → 4 (Active Play polish).** `SaveStore.migrate(3, w)` adds `tips_seen = {}` (`TIPS_DEFAULTS`, literal); nothing else changes, so a returning player sees each one-time tip once. Needed because the checksum of a current-schema file is over the normalised `to_dict()`, which now has the field. Tested in `test_active_save.gd` with a schema-3 file built exactly as the Active Play v1 code wrote it.

**Policy (who saves when).**

| Trigger | Where | Notes |
|---|---|---|
| `NOTIFICATION_APPLICATION_PAUSED` | `Game._suspend()` | Settle to now, dismiss the greeter, re-anchor, then `save_now(&"paused")` |
| `FOCUS_OUT` (desktop/web) | Game | Save only; the world keeps running |
| Window close / "Leave for now" | Game | `_suspend()`, then `quit_cleanly()` (audio stopped; ≥ 2 frames **and** ≥ 150 ms wall time so the mixer frees its playbacks; quit) |
| Every 30 s | SaveService `_process` | `AUTOSAVE_INTERVAL_S` |
| Player actions | `SaveService.request_save()` | Debounced 2 s |
| After boot | Game | One save, so the install exists on disk at once |

**Settings** use a separate `user://settings.cfg` (ConfigFile text, written atomically). Only keys the player changed are stored. Defaults, and the OS-derived defaults for Reduce Motion and text size, apply to the rest and are re-read on resume. QA user args: `--no-save` (never writes) and `--fresh` (removes the save files at start).

---

## 7. Time of day and weather → shader globals

| Global(s) | Writer | Rate |
|---|---|---|
| `g_time` (wrapped at `motion_tokens.time.g_time_wrap_s` = 600 s, C4), `g_motion` (1.0 or `reduce_motion.g_motion` 0.3) | Clock | every frame / on change |
| the 16 palette colours (`g_sky_*`, `g_glow`, `g_far`, `g_mid`, `g_near`, `g_fg`, `g_ambient`, `g_key`, `g_shadow`, `g_accent`, `g_ground_back/front`, `g_water_deep/shallow`), 9 scalars (`g_rim`, `g_backlight`, `g_ground_light`, `g_shadow_alpha`, `g_stars`, `g_lights`, `g_shafts`, `g_cloud_shadow`, `g_mist`), `g_halo`, `g_day` | TimeOfDay (palette) | 2 Hz; every frame during a weather crossfade or override |
| `g_wind`, `g_cloud`, `g_rain` | TimeOfDay (weather) | same |
| `g_sun_pos`, `g_moon_pos`, `g_celestial`, `g_sun_dir` | TimeOfDay (celestial) | same |
| `g_world_offset` | TimeOfDay, set by Main on resize | on change |
| `g_cam_pan` (map pan, canvas px, idle drift excluded; §3.4) | TimeOfDay, set by Main | on change (every frame while panning) |

The pipeline:
1. **`TodMath.g_day_at(local_s)`** maps the clock to `g_day` per `world.json`: dawn 05:00 → 0.2, day 08:00 → 0.4, golden 16:30 → 0.6, dusk 18:30 → 0.8, night 20:30 → 1.0. Each phase crossfades over `phase_crossfade_s` (2400 s). Night reads 0.0 after midnight, and the jump is invisible because the gradient has night at both ends (tested at every minute of the day).
2. **`PaletteDriver`** precomputes OKLab for every slot and key from `palettes.json tod`, and samples by linear OKLab interpolation. It matches Godot's `Gradient` in `GRADIENT_COLOR_SPACE_OKLAB` within 1.5/255 (tested). Scalars lerp on the same keys. `make_gradient(slot)` builds an engine `Gradient` for shader textures (the sky's `GradientTexture1D`).
3. **The rain transform** (`palettes.json weather.rain_transform`) is scaled by `g_rain`: OKLCh chroma and lightness on the listed slots, key chroma and lightness, and the scalar multipliers and mist add. Then `g_ambient *= blend(ambient_mult)`.
4. **`WeatherPlan(install_seed)`** draws the deterministic per-day episode plan (GDD §6.2), seeded by `String.hash()` of (salt, seed, day). **`WeatherDriver`** crossfades over `weather_crossfade_s` (30 s, smoothstep) and blends `g_wind`, `cloud_cover`, `ambient_mult` and `rain_particles`.
5. **`Celestial`** uses hour-keyed time-aware Catmull-Rom paths, fades over `fade_minutes` at the path ends, dims sun visibility by (1 − 0.85·g_cloud), and takes `g_sun_dir` from the brighter body.
6. **Push.** Only changed values are sent, against a CPU mirror; `global_shader_parameter_get()` is never called during play.

QA args:
- `--tod=<0..1>` pins `g_day`; the sun and moon move to a matching hour.
- `--weather=clear|breeze|rain` pins the weather.
- `--clock=HH:MM`, `--now=<unix>` and `--tz=<min>` shift the wall clock.
- `--freeze-time` stops `g_time`; `--g-time=<s>` sets its start value.

---

## 8. Platform services

### 8.1 Settings (X1, GDD §7.6)

| Key | Values (default) | Applied by |
|---|---|---|
| `reduce_motion` | bool (OS: Android `ValueAnimator.areAnimatorsEnabled`, Web `prefers-reduced-motion`, desktop AccessKit) | Clock (`g_motion`), Motion (springs ζ ≥ 1, 150 ms cross-fades), Main (no camera drift or zoom) |
| `reduce_transparency` | false | UiTheme (glass fill 1.0) |
| `text_scale` | 100 / 115 / 130 / 150 / 200 (OS: Android `font_scale`) | UiTheme |
| `auto_hide_ui`, `keep_awake` | true, false | UI ambient mode; FrameGovernor (`screen_set_keep_on` only while ambient) |
| `music` | on / ambience / off | AudioDirector (3 s mode fades) |
| `volume_music`, `volume_ambience`, `volume_effects` | 0–100 step 10 (80) | AudioDirector: offset dB = 30·log10(v/80), 0 = bus muted |
| `mono`, `captions` | false | AudioDirector (Master stereo-enhance pan_pullout 0); captions UI listens to `cue_played` |
| `haptics` | off / **subtle** / full | Haptics |
| `left_handed` | false | UI (dock/HUD mirroring) |
| `language` | auto / en / vi | I18n (`vi*` → vi, else en) |

### 8.2 Haptics (D11, 06 §5, AUDIO_BIBLE §7)
- **Kinds** are `Haptics.TICK`, `DOUBLE` and `MEDIUM` (StringNames, the manifest's names). **Modes** `off` / **`subtle`** / `full`; assigning `Haptics.mode` validates and persists through Settings. Subtle never plays TICK. Events are at least 60 ms apart (wall clock). Timings and iOS pulses come from `manifest.haptics`, with a built-in copy of 06 §5.3 as fallback.
- **Cue extras** (`play_for_cue(cue.haptic, cue_id)`): `<mode>_delay_ms` (S04: TICK 600 ms after touch-down), `once` (S10: once per foreground session, reset on resume). The AudioDirector applies `haptic_once_per_burst` (S02: one DOUBLE per Collect-all burst) and drives `start_repeat(kind, full_repeat_ms)` / `stop_repeat()` from `start_purr` / `stop_purr` (S03: TICK every 120 ms while held, Full only). Repeats stop on pause and focus-out.
- **Android:** `AndroidRuntime.getActivity().runOnUiThread(createRunnableFromGodotCallable(…getWindow().getDecorView().performHapticFeedback(c)))`.
  - The constants are read once from `JavaClassWrapper.wrap("android.view.HapticFeedbackConstants")` by the names in `manifest.haptics.kinds[k].android` (never hard-coded). Below API 30 (`Build$VERSION.SDK_INT`) or when a field is missing, MEDIUM uses `android_fallback_below_api30` (CLOCK_TICK). DOUBLE is two ticks `android_gap_ms` (70) apart.
  - `permissions/vibrate=false`.
  - **`Input.vibrate_handheld` is never called on Android**: with no bridge or no constant there is no haptic.
- **iOS:** `vibrate_handheld(ms, amplitude × 0.7 in Subtle)` per manifest pulse.
- **Web / desktop:** none, but `played_count` and `last_kind` are still updated for tests.
- `AudioDirector.play_cue()` fires the cue's haptic in the same frame (I1).

### 8.3 AudioDirector (executes `audio/manifest.json`; the Sound Designer owns every number)
The contract is AUDIO_BIBLE §8; `tools/audio/mixsim.py` is its executable reference. Nothing below is a number of ours.
- **Bus graph.** Built from `manifest.buses`, falling back to the identical 06 §0.2 table. The build is idempotent, so it agrees with the audio pipeline's `default_bus_layout.tres`: Master (mono toggle off, HardLimiter −1.5 dB) ← Music (LPF, resonance 0.5), Ambience, SFX (room reverb), UI.
- **Gains.** Every fade is an equal-power `Fader` in linear amplitude (in = sin(u·π/2), out = cos(u·π/2)) written as `linear_to_db` (§8.3 of the bible; never a dB-linear tween).
- **Layers.**
  - Four beds per profile and weather, with `replace` (rain takes the stream's level) and `bed_add_db`, crickets only when the weather allows; 90 s phase / 30 s weather crossfades; 4 s fade-in at boot. A bed silent for 2 s is stopped and restarts at a seeded position.
  - Pads natively: one `AudioStreamInteractive` built from `harmony.pad_clip_order`, bar-quantised 6-beat crossfades; the sounding chord is polled with `get_current_clip_index()` and drives every pitch rule. Web: two players crossfaded equal-power, chords held short enough that no clip loops (§9).
  - Eno voices (period, density, minimum onset gap) through a time-ordered note queue serviced in `_process`; every motif note is wrapped into its bank range, so `pitch_scale` stays 1.0 (required on Web).
  - Rests, the 45-min fatigue guard, and the swell + hush after S09/S10; birds (from the asset list), critter coos and night snores (from `set_world_state`), wind-chime gusts (`chime_gust_s`, only with shells owned).
- **Cues.** `play_cue(&"S04", ctx)` with ctx `world` (S01 bus), `position` (caption anchor), `voice_step` (S03/S12/S13), `nap` (S12), `on` (S15), `shells`, `gust` (S21), `haptic` (default true). It implements walk, ladder, chord_root, species (+ second note), chord_fifth, below_last, fixed, chord_clip, variant (never the previous one, −1.5…0 dB level) and shell_run; honours `max_voices` per cue and at most 4 SFX-bus voices; uses Web twins on Web; fires the haptic; emits `cue_played(id, caption_key, world_position)` (the captions UI shows it when Captions is on). The purr (S03) has its own player: `start_purr(voice_step)` / `stop_purr()` with the manifest attack and release.
- **Ducking.** `set_sheet_open(true)` tweens the Music LPF to `min(profile cutoff, 1.2 kHz)` over 0.4 s; focus-out does the same automatically; profile and weather retarget it over 90 s / 30 s.
- **Settings.** Music on / nature only / off fade over 3 s, then mute and stop the silenced players; turning back on restarts with the boot fades and a fresh chord. Volumes: manifest bus level + 30·log10(v/80). Mono hidden on Web.
- **World input.** Phase and weather arrive from TimeOfDay's signals; `Game` calls `set_install_seed` at boot and `set_world_state(owned chime shells, voice_step of every mossling present, sleepers = 0 until the creature brain exists)` after every sim event batch.
- **QA.** `--audio-seed=N`, `debug_set_clock(phase, weather)`, `tools/qa/audio_smoke.gd`; Movie Maker settings `editor/movie_writer/mix_rate=44100` and `fps=30` are in `project.godot` (from the command line also pass `--fixed-fps 30`, otherwise `--write-movie` records at 60).
- **Loading.** `request_preload()` at boot starts threaded loads and collects them 16 per frame.
- **Headless** runs skip the endless layers, so nothing stays registered with the AudioServer at exit; captures under Xvfb play everything. `stop_all()` precedes every quit.
- **Data boundary.** JSON numbers are floats and `Array.has()` is type-strict, so chord pitch-class sets are converted to ints at load (`Harmony.pc_list`) and `Harmony` looks pitch classes up through `PackedInt32Array`. Before this fix `pent_step` looped forever on a JSON set.

### 8.4 Motion (`data/motion_tokens.json`, Art Bible §10)
- **Durations and curves.** `Motion.duration(&"standard")` is 0.32 s, and `&"exit"` is 0.65 × standard.
- **Béziers.** Exact béziers use `PropertyTweener.set_custom_interpolator(CubicBezier.progress)` on TRANS_LINEAR. Fallback trans/ease come from the token table.
- **UI tweens** call `FrameGovernor.hold_for(duration)`.
- **Springs.** `Spring` / `Spring2D` are analytic: they apply the closed-form solution of the damped oscillator over each dt (under-, critically and over-damped).
  - Exact at any frame rate, stable through 250 ms hitches, and retargetable with value and velocity kept.
  - `Motion.spring(&"jelly")` builds one from the token's f and ζ and the `springs.integrator.rest_epsilon` settle thresholds. Under Reduce Motion ζ = max(ζ, 1), so it never overshoots.
  - `Motion.spring_to(obj, "scale", Vector2.ONE, &"pop")` drives a property until it is at rest.
- **Reduce Motion:**
  - spatial tweens become a 150 ms fade, set, fade;
  - camera drift and zoom are off;
  - `g_motion` is 0.3.

### 8.5 i18n
- **Strings.** `i18n/strings.csv` (en, vi; NFC; no BOM) is imported by Godot's CSV importer into `strings.{en,vi}.translation`. Those files are git-ignored build products, registered at startup by `I18n.ensure_translations()`.
- **Locale.** `I18n.resolve(pref, OS.get_locale())`: "auto" with `vi*` → vi, else en.
- **Formatting.** Always `tr(KEY)` plus `String.format({name})`. `I18n.fmt()` and `I18n.duration_text()` ("about 40 min") are provided.
- **Line spacing.** Vietnamese gets +12 % (`VI_LINE_SPACING_MUL`; UiTheme rebuilds on a language change).
- **Names.** Fonts have no system fallback, so `NameRules` filters input to their coverage. `NfcTable` (generated by `tools/i18n/gen_nfc_table.py`) provides NFC, because GDScript has no Unicode normalisation.

### 8.6 Frame-rate governor (C21, 02 §4.4)
- **Frame rate.** 60 fps while there is input or a UI motion hold. 30 fps after `world.idle_fps_after_s` (8 s), and always in ambient mode. Rates are the nearest refresh divisor (active/idle: 60 Hz → 60/30, 90 Hz → 45/30, 120 Hz → 60/30).
- **Unstable idle rate.** If the idle 30 fps p95 delta exceeds 40 ms, idle-30 is switched off for the session and the tier drops instead (R2).
- **Quality tier** (0–2). It steps down when more than 5 % of frames in a 3 s window exceed 1.5× the target interval, and back up after 30 s clean. Views read `tier`. Art Bible §4.19 tier 1 means no shafts or L5, 1 cloud, and grass ×0.6.
- **Hitches.** `hitch_count` counts frames longer than 2× the target interval, for QA (no frame may exceed that after warm-up).
- **When it is off:** in headless runs, Movie Maker and with `--no-governor`.

### 8.7 Back button, safe area, theme
- **Back button.** `quit_on_go_back=false`, and `NOTIFICATION_WM_GO_BACK_REQUEST` goes to `Game.handle_back()`.
  - The top-most card or sheet registers a closer with `Game.push_back_handler(callable)` and removes it with `remove_back_handler`.
  - With nothing open, Back emits `leave_requested` and the UI shows "Leave the hollow for now?".
  - "Leave for now" calls `Game.leave_now()`: it saves, then `Activity.moveTaskToBack(true)` on Android, else quits cleanly.
- **`SafeAreaContainer`.** Margins are max(OS safe area in canvas units, floors): top 72 px, bottom 127 px, sides 48 px (Art Bible §2.2). They are re-applied on resize and resume.
- **`UiTheme` / `ThemeBuilder`.**
  - **Type scale:** Caption 36 / Label 42 / Body 48 / HUD 66 (MSDF numerals) / Title 84 px.
  - **Shape and elevation:** radii 24–96, elevation e1–e3 in ink.
  - **Variations:** TitleLabel, BodyLabel, StrongLabel, CaptionLabel, SecondaryLabel, HudNumeral, PriceLabel; the primary Button pill and SecondaryButton; panels Card, Sheet, Chip and ModalCard; LineEdit; thin scrollbars.
  - **CanvasLayer root Controls must call `UiTheme.attach(control)`**, because theme propagation stops at a CanvasLayer.
  - **Fonts** (`fonts/`) are subset WOFF2 files. They are imported with hinting None and no system fallback; `Baloo2-Bold-Numerals` is imported as MSDF.

---

### 8.4a Motion: when a spring stops (round 9)

`Spring` is analytic, so its cost is one step per frame; what was expensive was how *long* it ran.
The `rest_epsilon` in `motion_tokens.json` is absolute (0.0005), but half of these springs drive
properties measured in **pixels**: settling a 300 px panel to within 1/2000 of a pixel takes the
`move` spring 1.10 s, against 0.63 s to reach 0.15 px. That half-second is invisible and not free —
`Motion._process` calls `FrameGovernor.hold_for` for as long as any drive is alive, so every sheet
open, dock move, tray slide and drag release pinned the whole app at 60 fps for an extra half
second before the idle timer could even start.

A **driven** spring (`Motion.spring_to`) therefore rests within `REST_REL` (0.05 %) of the distance
it set out to travel, never tighter than the token floor, and a drive that finishes writes the
**exact** target so stopping early leaves no residue (a `rise` left 0.3 px short is invisible, but
`rise > 0.0` is not). The relative form is right for a pixel property and an alpha alike without
Motion knowing units, and 0.05 % keeps the final snap under a pixel even for the longest travel in
the game (a full-height sheet, 1,709 px → 0.85 px). `Spring`'s own default is unchanged for the
many places that step a spring themselves.

---

## 9. Budgets the skeleton respects (synthesis §3)
- **Draw calls and fill.**
  - Placeholders cost 5 draw calls: one material per band and an opaque fill.
  - The warm-up stage exists only behind the splash.
  - The HUD is empty, and there are no screen reads.
- **No per-frame allocations in steady state.**
  - `WorldSim.advance()` is O(1) between events.
  - TimeOfDay evaluates at 2 Hz and sends only changed globals.
  - The Motion and FrameGovernor `_process` are early-out.
- **Particles and lights.** No `Light2D`, SubViewport or 3D; particles are reserved for the Technical Artist (≤ 3 systems / 150 particles, D9).
- **Cold start.** Boot loads the main scene and audio threaded while warm-up draws. Measured on the x86 CI container: `Game.boot()` with a full 7-day catch-up processes 1,208 events with 49 stems in **65 ms**, the recap takes 1.3 ms, and a save (write + verify) takes **7 ms** for 22 KB. Expect 3–5× on the low tier; measure on device (R4).

---

## 10. Coding conventions
- **GDScript 2.0, statically typed everywhere.**
  - `var x: T` or `:=`, typed parameters and returns, `Array[T]` and typed loop variables.
  - Tabs for indentation; files in snake_case; `class_name` only for reusable types (every `scripts/sim|core|world|motion|audio|ui` class); autoload scripts have no `class_name`.
- **Naming.**
  - Signals are past tense or state nouns (`world_ready`, `tier_changed`).
  - Constants are UPPER_SNAKE.
  - Private members start with `_`.
  - Identifiers and comments are in English.
- **No magic numbers.** Game values come from `data/` and the manifest. A structural constant in code is a named `const` with its source cited (for example `## GDD §3.4: "103 % → 100 % over 2.5 s"`).
- **Player-facing text** always goes through `tr()` with keys in `strings.csv`. Never concatenate translated fragments; use `{placeholders}`.
- **Errors.**
  - Data and programming errors use `push_error` (tests fail on them).
  - Recoverable runtime conditions use `push_warning`.
  - The player never sees an error state (E2, A3).
- **Warnings.** The four synthesis warnings are on at level 1. `tools/ci/strict_check.sh` promotes them to errors and must report 0. Data-boundary files (JSON/Dictionary heavy) and tests carry a commented `@warning_ignore_start("unsafe_call_argument")`, because each conversion is explicit at the read site.
  - `untyped_declaration`, `unsafe_method_access` and `unsafe_property_access` are never silenced.
  - Prefer a typed local (`var x: float = d["k"]`) or a typed accessor over a new suppression.
- **Pure versus node code.**
  - Logic that can be pure goes in a `RefCounted` with static or instance methods and is tested directly.
  - Nodes adapt it to the engine.
  - Pure classes never call autoloads.
- **Adding a data field.**
  1. Add it to the JSON.
  2. Read it at one place in code.
  3. Add a check in `validate_content.py` (GDD) or `GameContent._check_references`.
  4. Add a test.
- **Adding persisted state.**
  1. Add the field to `WorldState` and to both `to_dict` and `from_dict`, with a typed default.
  2. If the shape of existing data changes, bump `SaveStore.SCHEMA` and add a migration.
  3. Extend `test_save_service`.
- **Adding an autoload.**
  1. Append it in `project.godot` under its dependencies.
  2. Document it in §3.1.
  3. Make it headless-safe.

---

## 11. Testing

| Suite (`tests/`) | Verifies |
|---|---|
| `test_content_registry.gd` | All 9 data files load and validate; MVP counts; GDD §5.2 price ladders and the catalogue total of 19,461; references resolve; 80 bed slots for 80 flower copies; hearts; broken documents are reported, not crashed |
| `test_sim_invariants.gd` | **E1** 30 days away → nothing decreases; **E1** clock rollback changes nothing; E1 across random sessions; **offline clamp** 7 d (and short gaps unclamped); **basket saturation** → photos and the brimming postcard, never more than 24, analytic 10–14 h target; cup brimming keeps the remainder; **E5/E6** over ~16 k sessions; wallet cap; onboarding (3 friends in 5 min, first at 20–40 s, clover #2 = 17); untapped seed; save/load mid-game does not change the future; greeter gives nothing; bed rules |
| `test_save_service.gd` | Lossless round trip, including the 64-bit RNG state and Vietnamese names; .bak rotation; **corrupt main → .bak**; checksum mismatch → .bak; orphaned .tmp; garbage and missing files; future schema refused; type coercion; disabled service |
| `test_retention_core.gd` | GDD §13: the §13.1 golden hash vectors; retention never draws from the world RNG; the 20 h visit rest; heart unlock order (♥2 story + signature gift, ♥3 nest, ♥4 waits for the buddy, ♥5 story + keepsake, multi-level jumps); nests grow offline and never wilt; signs precede the debut, never expire and are still collectable after 30 days; ≤ 3 visible at distinct, type-valid anchors; cousin conditions and every-3rd visit; scenes: ≥ 2 h, one per return, pending re-shown, deterministic per seed, unseen first, profile conditions, cast rules, pending across close + 600 s linger; 30 days away nothing decreases; live = one catch-up; recap teaser; view models; `retention_mid` and every `--qa-scene` |
| `test_retention_save.gd` | Schema 1 → 2 from a real MVP save: every v1 value kept, new fields added, content-aware steps (hearts_seen, nests, keepsakes, stories, mysteries), runs once, plays on and round-trips; old `.bak` migrated behind a corrupt main; `migrate` only adds; coercion of the new fields |
| `test_retention_parity.gd` | Bit-level parity with `economy_sim.py` on the exported scripted schedule (§5.3) |
| `test_active_wishes.gd` | Active F1: spawns deterministic per seed and never touching the world RNG; nothing spawns in `advance` or catch-up; the 60 s cadence survives a reload and stops when blocked or flagged off; caps and the teaching wish; held wishes kept across visits and 30 days; every world target grants (pet, chime, bed, décor tap, stream, boat, play_taps ×3); a mismatched action is no mistake; one action grants every matching wish; rewards with the 20 h rest, one stamp, the gift petal and its jar cap; "fulfillable now" eligibility (nook, blooms, phase, weather, species_only, buddy, placed pieces, not_already_near); the greeter brings a held wish and never spawns one; a wish leaves only by a grant |
| `test_active_tea.gd` | Active F2: the nook unlock; harvest never harms a flower; offline-exact regrow, partial progress kept, full stems pause, live = one jump; jar caps (the rest waits); every pot of 1–3 petals × 0–2 drops makes something, two drops a treat; the pot returns petals and refunds drops, never creates dew; stir both ways to the target, simple brewing, a full tray keeps the pot; reactions (never a dislike), the 20 h tea rest, petals back, the greeter's 0, `first_tea`; known preferences; a cup grants a tea wish and stacks; teaware is a sink with snug 0; `tea_book` |
| `test_active_decor.gd` | Active F3: the validity table (one soft reason each, hint keys in strings.csv), spacing and the cairn merge / full stack, snapping (in reach vs free), valid family-ordered sockets incl. the fairy ring and the water line, the 48 dp nudge and the float home, repeatable jitter, a move that settles commits and emits one `decor_placed` and a float home changes and emits nothing, turn / put away / take out / undo (one step, cleared on exit), tidying keeps owned counts and λ, cairn lift and merge, purchases auto placed on valid ground, derived spots follow the pieces and fall back to the authored spot, `decor_near` granted now and on arrival |
| `test_active_save.gd` | Schema 2 → 3 from a real pre-Active save: every v2 value kept, defaults added; every piece where it stood (≤ 0.5 px) but the two nudged pinwheels (≤ 48 dp, now clear), one cairn stack, owned / affection / RNG / retention untouched, the nook awake, full stems; idempotent and round-trips; schema 1 → 3; `.bak` behind a corrupt main; `migrate` only adds; every active field round-trips; coercion of hand-edited fields |
| `test_active_invariants.gd` | E1 / E5 / E6 with the whole active layer in play (`SimPlayer.active_play`: wish clock, help, gather, brew, offer, teaware); jars within caps; tea and wishes create no dew; 30 days away keeps every wish and petal; the `active_mid` fixture |
| `test_active_input.gd` | §3.5 additions through real dispatch: `claim_drag` carries the piece and never pans, a drag before it still pans and cancels the tap, `empty_tapped`, the edit-group filter driven by Game's edit signals, `nudge` inside the rest bounds, the Active priorities match the data |
| `test_active_parity.gd` | Bit-level parity with `economy_sim.py` on the exported Active Play schedule (§5.3) |
| `test_palette.gd` | **Palette interpolation:** keys exact, midpoints equal to the engine's OKLab Gradient; OKLab round trip; scalars; clock → `g_day` (crossfades, midnight, continuity over 24 h); rain transform; 30 s weather crossfade; celestial; every declared global has a writer |
| `test_clock.gd` | **Frame clock** (QA captures): replays identically, ignores real time, `--now`/override mid-run and clear; the system-clock mode is unchanged |
| `test_world_pan.gd` | Map pan (§3.4): bounds per aspect keep every layer inside its geometry (phones, tablets, wider than the geometry); rubber band is 1:1 inside and never passes the hard bounds; release past the bounds springs back inside; fling glides with friction, overshoots an edge and settles on it; home glide; Reduce Motion (no inertia, clamp, cut); soft limit and reveal; foreground room. Arbiter (§3.5): threshold and slop from the settings; release-to-fire; a drag cancels the tap and tracks 1:1 from the slop edge; a drag-claiming target never pans; one target per press by priority then nearest; direct hit beats slop, slop catches near misses; touch aim offset; the emulated twin is ignored; second finger; edge band (taps still work); nothing through a sheet or a card that rose mid-press; a press on a gliding map only catches it; cancel; double tap on empty ground only |
| `test_input_contract.gd` | §3.5 through real GUI dispatch (a SubViewport fed the phone's emulated-mouse + touch pairs): one world press per touch; release-to-fire with slop; props act on release; bed priority and choose mode; candidate order (tier, priority, distance); HUD band, chips, dock seams, pebble ends, under the pebble and the gesture inset consume; toast (shown and fading); sheet rect, grabber and padding consume, scrim drag vs tap, no world tap through the scrim; a closing sheet consumes and never acts; modal scrim; the ambient wake gesture swallowed whole; one fire per touch on a button; press slop; scroll-through and deadzone; fling catch; debounce; dock select on release, slide-off cancel, active tab closes; slider moves only on a horizontal drag; size floors |
| `test_spring.gd` | **Spring helper converges** for all 5 tokens, with analytic overshoot and envelope settle times; frame-rate independence (30 vs 120 fps); stability through hitches; retarget keeps velocity; critically and over-damped never overshoot; Reduce Motion ζ ≥ 1; Spring2D; bézier tokens; duration tokens; the loop table meets V5 (integer k, breathing 3.5–4.5 / 5–6 s, ≤ 3 firefly glows/s); `Motion` springs take the token rest epsilon |
| `test_core_helpers.gd` | NFC and name filtering; weather plan determinism and share; locale policy and loaded translations; settings validation; recap priority; harmony helpers versus theory.py (including JSON float sets); bus graph (limiter −1.5 dB, LPF resonance 0.5); frame-rate divisors; haptics modes, persistence and repeat |
| `test_audio_director.gd` | AUDIO_BIBLE §8.10 without a device: manifest loaded; ladder climbs, caps at 7 and resets after 1.5 s; walk stays in range and set and always moves; variants never repeat and all are used; chord hold 6–10 bars; bed targets (rain replaces the stream, crickets only at night and never in rain); slider curve; `cue_played` captions; one DOUBLE per Collect burst; S10 MEDIUM once |

`tests/helpers/sim_player.gd` ports the Python sim's *player* model (schedules, spending policies, E5 "new/affordable" audit; `active_play` adds the wish clock, help, gathering, brewing, offering and teaware). All game rules are the real `WorldSim`. `tests/helpers/active_util.gd` builds quiet Active Play worlds (a bloomed bed, décor at the legacy anchors, long visits, world actions, simple brewing).

**Pipeline** (CI order; extends synthesis D14). Every gate is a stage of `tools/ci/run_ci.sh`, which `.github/workflows/ci.yml` calls, so a local run reproduces CI; commands, thresholds and the visual QA protocol are in `docs/QA.md`:
```
tools/ci/run_ci.sh lint data      # gdlint (.gdlintrc); content lint, 412 colour rules, font coverage, fast economy gate, metrics self-test
tools/ci/run_ci.sh import strict  # headless import must print no ERROR/WARNING; every script compiles with 0 warnings
tools/ci/run_ci.sh test smoke     # GUT (JUnit in reports/); boot -> main 300 frames, 0 errors/leaks
tools/ci/run_ci.sh audio visual   # Xvfb audio smoke; opengl3_es determinism, golden-size stills, V2/banding/contrast metrics
tools/ci/run_ci.sh import export  # Web (nothreads, release) + "Android Debug" APK (arm64) into build/
```

**Capture** (`tools/qa/capture.sh` wraps `tools/qa/capture.gd`; docs/QA.md §3):
```
tools/qa/capture.sh still --size=1080x1920 --tod=0.62 --weather=clear --seed=7 --out=qa/out/golden.png
tools/qa/capture.sh video --seconds=30 --tod=0.6        # Movie Maker 1080x2400 @ 30 fps -> qa/out/clip/clip.{avi,mp4,gif}
tools/qa/capture.sh determinism                         # R5 double render
```
It runs the real boot → main hand-off with a throw-away user://, the frame clock (`Clock.frame_clock`: wall time and ticks follow the fixed frame delta), a frozen `g_time` unless `--animate`, and fixed defaults for every time and weather input, and quits cleanly with no leaks. R5 is closed: `opengl3_es` renders are byte-identical run to run (docs/QA.md §3.2).

---

## 12. Placeholders register and hand-offs

| Placeholder | Replaced by | Notes |
|---|---|---|
| `shaders/dev/placeholder_band.gdshader`, `PlaceholderBand` nodes under Sky / FarHills / MidHills / Meadow / Stream | Technical Artist: Art Bible §4.3–4.8 shaders and builders | Delete the dev shader with the last band. Warm-up picks up new shaders automatically |
| Empty `Celestial`, `Foreground`, `Play/*`, `Particles` | Technical Artist (layers, particles), Gameplay Engineer (beds, décor, creatures) | `Plots` children = beds from `spots.json` + `sim.state.stems`; `Decor` from `owned` × anchors; `Creatures` from `present` |
| `HUD/…/TopBar`, `Dock`, `Sheets`, `Overlays` | UI Engineer | Back handlers, the leave dialog on `leave_requested`, the recap on `world_ready(recap)`, choose-a-bed mode (`sim.needs_bed_choice`, `GardenRules.beds_with_room`), `UiTheme.attach` on new CanvasLayers |
| `LayoutDebug`, `HitDebug`, `DebugReadout` | stay (debug-only flags) | `--debug-layout`, `--debug-hits`, `--debug-hud`, `--log-events` |

**For other roles.**
- **Gameplay:**
  - Build the creature brain (§5.4) and the tutorial hints.
  - Call `AudioDirector.play_cue()` on touch-down (R8). Pass `voice_step` for species cues; S12 on arrival/nap, S13 on mossling tap, S02 per collected item (90 ms apart).
  - Report sleepers through `Game._push_audio_state()` once the brain knows who naps (it passes 0 today).
  - Use `Game.*` for every intent.
- **UI:**
  - `ThemeBuilder` tables are the place to restyle; regenerate `base_theme.tres` with `tools/ui/build_theme.gd`.
  - Text size rebuilds the theme.
  - Dock labels take the full text size; the pebble widens and grows (Art Bible §9.4). Settings is the top bar's gear (`TopBarView.gear`, `settings_pressed`), not a dock tab.
  - Call `FrameGovernor.ambient_mode = true` in watch mode.
  - Audio hooks: `set_sheet_open()` on sheet rise/exit; `start_purr()` / `stop_purr()` on the long-press; captions from `cue_played`; the four sound settings and `Haptics.mode` through Settings.
- **Technical Artist:**
  - Read globals only; never write them (TimeOfDay owns them).
  - Register code-made particle materials with `ShaderWarmup.register()`.
  - Honour `FrameGovernor.tier`.
- **Audio:**
  - The manifest is consumed as generated.
  - `tools/audio/make_bus_layout.gd` has 2 unsafe-argument warnings (outside `strict_check`'s scope).
  - Rule details in the AUDIO_BIBLE override §8.3 if they differ; tell the Tech Lead so the director follows.
  - AUDIO_BIBLE §8.1 now lists the implemented API (updated 2026-10-21; the first draft's `caption_requested`, `start_loop`/`stop_loop` and `set_ducked` are gone), and its §8.11 review items are marked done.
  - `banks.bird.variants` keys collide (all "None"), so birds are taken from the asset list, as mixsim.py does.
- **QA:** capture tool, determinism test, and on-device checks (frame pacing, haptics feel, 7-day catch-up time).

**Decisions for the Director to ratify.**
1. Typed `to_dict`/`from_dict` instead of `JSON.from_native` (§6).
2. Translations and the project theme registered at runtime instead of in `project.godot` (§2).
3. The two greeter keys added to `economy.json` (§5.3).
4. `.gitignore`: `/build/*` plus `!/build/.gdignore`, so the empty `build/.gdignore` can be committed as synthesis §3 asks; `/reports/` is ignored.

**Open issues.**
- **(a)** The recap's "napped at" line needs the creature brain.
- **(b)** Cold-start and catch-up cost must be measured on the low-tier device.
- **(c)** The Android haptics bridge, `ValueAnimator` and `font_scale` reads are untested on hardware (R7).
- **(d)** iOS has no OS Reduce Motion or font-scale read in 4.7.2 without a plugin; the in-game toggles cover it.

---

## 13. Command cheat sheet
```
tools/vendor_addons.sh                                     # GUT v9.7.1, SHA-verified
python3 -I tools/fonts/build_fonts.py                      # re-fetch + subset fonts (npm, fonttools, brotli)
python3 -I tools/i18n/gen_nfc_table.py                     # regenerate scripts/core/nfc_table.gd
python3 tools/sim/economy_sim.py --parity-export tests/fixtures/retention_parity.json        # retention parity
python3 tools/sim/economy_sim.py --active-parity-export tests/fixtures/active_parity.json    # Active Play parity
godot --headless --path . -s res://tools/ui/build_theme.gd # regenerate ui/theme/base_theme.tres
godot --headless --path . -s res://tools/ci/check_scripts.gd   # compile every script with autoloads live
godot --path . -- --clock=19:00 --weather=breeze --world-speed=60 --debug-hud --log-events   # look around
```
User args (after `--`):
- `--seed=N` (new install seed)
- `--world-speed=X`
- `--no-save`, `--fresh`
- `--clock=HH:MM`, `--now=<unix>`, `--tz=<min>`
- `--tod=<0..1>`, `--weather=<id>`
- `--freeze-time`, `--g-time=<s>`
- `--frame-clock` (wall time and ticks follow the frame delta; implied in Movie Maker mode)
- `--no-governor`
- `--debug-layout`, `--debug-hits` (every world and UI hit area, §3.5), `--debug-hud`, `--log-events`
- `--audio-seed=N`
- `--fixture=active_mid` (garden_mid + five friends met, three visiting; two open wishes and one held; the tea nook with five jars, full glints on bed_1, a half-stirred pot, two cups, six recipes, a teaware cup; free-placed décor: pinwheels on the hill crest, a toadstool ring by the moss cushion, a turned lantern, a second cairn stack, a stone tucked away): `ActiveFixture`, called from `GardenFixture.apply_from_args`. Every `GardenFixture` world now lays its décor out through the §6 migration (anchors verbatim, the lantern jitter baked in), so existing captures are unchanged
- `--fixture=retention_mid` (garden_mid + hearts 1–5, nests at all 3 stages, 2 open mysteries with 1 visible sign each, a cousin met, memories, a pending `pair_nap`) and `--qa-scene=<scene id>` (that scene pending; implies the retention_mid world): `RetentionFixture`, called from `GardenFixture.apply_from_args`
