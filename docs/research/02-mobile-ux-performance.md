# 02 — Mobile UX, Ergonomics, Performance, Battery & Accessibility

Scope: a 100% chill/idle/cozy portrait one-hand game, Godot **4.7.2-stable**. Engine claims were checked against the source in `/home/user/godotengine/godot` (paths cited). Date: 2026-10-20.

Evidence tags: **[V]** verified fact (doc, paper, or engine source path) · **[H]** well-supported heuristic · **[J]** our judgement, to confirm on a device.

---

## 0. Recommendations (decision table)

| # | Area | Decision | Concrete value | Tag |
|---|---|---|---|---|
| R1 | Base resolution | Portrait base 1080×1920, `canvas_items` + `expand` | `display/window/size/viewport_width=1080`, `display/window/size/viewport_height=1920`, `display/window/stretch/mode="canvas_items"`, `display/window/stretch/aspect="expand"`, `display/window/handheld/orientation=1` (Portrait) | V (docs `multiple_resolutions.rst` "Mobile game in portrait mode"; the project manager writes canvas_items+expand into *new* projects, `editor/editor_node.cpp:8348-8349`, but the engine defaults are still `"disabled"`/`"keep"`, `core/config/project_settings.cpp:1787-1788`, so a hand-written `project.godot` must set them explicitly) |
| R2 | Reference layout | 1080×2400 viewport = 412×914 dp at 2.625 px/dp | Zone spec in §1.2 | J built on H |
| R3 | Touch targets | Hit area ≥ 60 dp in play zones, ≥ 72 dp top row, ≥ 76 dp bottom dock. Visual size can be smaller. Gaps ≥ 8 dp | 158 / 189 / 200 px at the reference | H (Parhi 2006; Hoober; Google 48 dp min) |
| R4 | Primary action | One centred primary button in the bottom dock, handedness-neutral. Asymmetric UI mirrors when "left-handed" is on | x=540 px, y≈2142 px, Ø 88 dp visual / 96 dp hit | H/J |
| R5 | Safe area | Margins come from `DisplayServer.get_display_safe_area()`, with a floor of 24 dp top and 24 dp bottom. On Android immersive the API reports only the cutout, so the floor matters | snippet §1.4 | V (`GodotIO.java:getDisplaySafeArea`) |
| R6 | Gestures | Tap, long-press (450 ms), and drag. Swipe only for sheet dismiss. Pinch is optional and always has a single-pointer alternative | `gui/common/drag_threshold=24` | V (WCAG 2.5.1) / J |
| R7 | Haptics, Android | Use `View.performHapticFeedback(HapticFeedbackConstants.*)` through `JavaClassWrapper`, not `Input.vibrate_handheld`. This needs no VIBRATE permission and follows the user's settings | §2.3 | V (Godot uses `createOneShot`; Android says to avoid it for touch feedback) |
| R8 | Haptics, iOS | `Input.vibrate_handheld(ms, amp)` drives a Core Haptics continuous event. Use 10–30 ms at 0.25–0.6. No manual engine start is needed: Godot creates the `CHHapticEngine` with `autoShutdownEnabled=true`, so it starts on the first play and stops after about 2 min idle. `start_haptic_engine()` is only an optional pre-warm to cut first-tap latency | table §2.3 | V (`drivers/apple_embedded/apple_embedded.mm:63`; Apple `CHHapticEngine.isAutoShutdownEnabled` docs) / J |
| R9 | Renderer | **Compatibility** on all platforms (Android, iOS, Web): one look, lowest overhead, Web parity. Do not rely on HDR-2D, MSAA-2D, particle trails, sub-emitters or `emit_particle()` | `rendering/renderer/rendering_method="gl_compatibility"`, `rendering/renderer/rendering_method.mobile="gl_compatibility"` (Web is forced to `gl_compatibility`, `main/main.cpp:2649`) | V (docs `renderers.rst`: "2D game → Compatibility"; trails/sub-emitters/emit warn as unsupported in `drivers/gles3/storage/particles_storage.cpp:303,387,392`) / J |
| R10 | Frame rate | 60 fps interactive, 30 fps ambient. Choose integer divisors of the refresh rate at runtime. 120 Hz is an opt-in setting | `application/run/max_fps=60`, then `Engine.max_fps` at runtime | H/J |
| R11 | Low-processor mode | **Off.** It saves nothing while any TIME shader or particles are visible | `application/run/low_processor_mode=false` | V (`renderer_canvas_render_rd.cpp:914`, `rasterizer_canvas_gles3.cpp:564`: `if (time_used) redraw_request()`) |
| R12 | Screen-on | Our default is off. On only in user-entered Ambient mode. **The engine default is `true`**, so we must override it | `display/window/energy_saving/keep_screen_on=false` (engine default `true`, `project_settings.cpp:1745`); `DisplayServer.screen_set_keep_on(true)` in ambient | V/J |
| R13 | Budgets | Low tier: ≤ 100 draw calls, overdraw ≤ 2.5×, ≤ 150 particles, ≤ 96 MB textures. iPhone 12: ≤ 250, ≤ 4×, ≤ 600, ≤ 192 MB | §4.3 | J (built on H) |
| R14 | Sessions | Three loops: a 30 s glance, a 3–8 min tend, and an optional ambient mode. Offline progress capped at 12 h. No energy, no streak penalties, no FOMO timers | §3 | V (GameAnalytics; Zagal 2013) / J |
| R15 | Notifications | **None in v1.** Godot has no local-notification API, so it would need a native plugin. If added later: opt-in, at most one per day, no loss framing | — | V (no API in source) / J |
| R16 | Accessibility | In-game toggles for Calm motion, Text size 100–200%, Haptics, Mono audio, Left-handed, and captions for meaningful sounds. Text contrast ≥ 4.5:1 | §5 | V (WCAG 2.2) |
| R17 | Screen readers | **Not available on mobile in 4.7.2.** AccessKit is compiled only for macOS, Windows and Linux. Optional "read aloud" can use `DisplayServer.tts_speak` (works on Android and iOS) | — | V (`drivers/SCsub:36`) |
| R18 | Android store | targetSdk 36 (default) and 16 KB alignment are compliant out of the box. Ship an AAB through a Gradle build. `package/app_category=Game` keeps the portrait lock on large screens | §6 | V |
| R19 | iOS store | Build with Xcode 26 / iOS 26 SDK (needs a Mac). Set the privacy-manifest reasons to C617.1, 35F9.1 and E174.1. Handle resizable iPad windows | §6 | V (requirements, codes) / J (choice of reasons) |

---

## 1. Portrait one-handed layout

### 1.1 Evidence

- **Grip [V, via secondary sources]:** Hoober (2013) made 1,333 field observations, 780 of them touching the screen. 49% used one hand, 36% cradled the phone, 15% used two hands. In one-handed use the right thumb was on screen in 67% of cases and the left in 33%. ([UXmatters 2013](https://www.uxmatters.com/mt/archives/2013/02/how-do-users-really-hold-mobile-devices.php); the original is unreachable from our proxy, but the figures match several summaries.) Hoober himself said he was unsure what to make of the left/right split. In 2017 he revised his findings and warned against reading "thumb zone" diagrams as hard constraints.
- **Reach [V]:** the thumb's functional area depends on hand, grip and device size; on large phones the far top corner and the area under the thumb base are hardest (Bergstrom-Lehtovirta & Oulasvirta, CHI 2014, doi:10.1145/2556288.2557354).
- **Accuracy by position [H]:** Hoober's *Touch Design for Mobile Interfaces*, as summarised by Smashing (2023), recommends about 7 mm targets at the centre, 11 mm at the top and 12 mm at the bottom. ([Smashing cheatsheet](https://www.smashingmagazine.com/2023/04/accessible-tap-target-sizes-rage-taps-clicks/)) IxDF reports slightly different edge values, hence [H]. People prefer tapping near the centre and re-grip to reach edges.
- **Target size [V]:** Parhi, Karlson & Bederson (MobileHCI 2006, doi:10.1145/1152215.1152260) found one-handed thumb targets of 9.2 mm (discrete tasks) and 9.6 mm (serial tasks) were large enough without hurting speed or preference.
- **Platform minimums [V]:** Apple HIG (Accessibility) lists a **default** control size of 44×44 pt and a **minimum** of 28×28 pt on iOS/iPadOS, with about 12 pt of padding around bezelled elements and about 24 pt around borderless ones. Android/Material requires at least 48×48 dp with at least 8 dp between targets, which Google says is about 9 mm ([Google](https://support.google.com/accessibility/android/answer/7101858); [web.dev](https://web.dev/articles/accessible-tap-targets)). WCAG 2.2 SC 2.5.8 (AA) sets 24×24 CSS px as the floor, and SC 2.5.5 (AAA) sets 44×44.
- **Fitts' law [V]:** MT = a + b·log₂(D/W + 1) (Fitts 1954, doi:10.1037/h0055392; MacKenzie 1992, doi:10.1207/s15327051hci0701_3). So repeated actions should be **large and stationary** (D ≈ 0): one big "tend" target, not many small pickups.
- **Touch offset [H]:** Touch error is dominated by systematic offsets that depend on the user and the finger posture, not just by the "fat finger" (Holz & Baudisch CHI 2010, doi:10.1145/1753326.1753413). The common observation that contacts land slightly below the aim point is a heuristic; the paper models per-user and per-posture offsets rather than one fixed direction. [J] Extend hit areas about 4 dp further downward than the visual.

### 1.2 Layout spec: 1080×2400 reference (Pixel 7a class, 420 dpi, 2.625 px/dp, ≈16.5 px/mm)

With base 1080×1920 and `expand`, every phone of 16:9 or taller is **width-limited**. The viewport is always 1080 px wide and 1920–2600 px tall. On the reference device, viewport px equal physical px.

| Zone | y (px) | y (dp) | Content | Interaction rules |
|---|---|---|---|---|
| Z0 System top | 0–144 | 0–55 | Cutout, status bar, Dynamic Island equivalent | **Nothing interactive.** Sky art bleeds under it |
| Z1 Glance HUD | 144–336 | 55–128 | Passive state: time of day, 2–3 counters, "what's new" chips | **No required targets.** Optional tap opens a detail sheet (hit ≥ 72 dp = 189 px) |
| Z2 World, upper ("look") | 336–1260 | 128–480 | Sky, ambient life, weather. **Elastic:** absorbs aspect-ratio slack | Optional "delight" taps only, hit ≥ 64 dp = 168 px. Never required, never time-critical |
| Z3 World, lower ("tend") | 1260–2010 | 480–766 | Garden/room objects players touch, drag, arrange | All core gestures. Hit ≥ 60 dp = 158 px (Parhi 9.6 mm). Fixed height ≥ 640 px |
| Z4 Dock | 2010–2274 | 766–866 | `[Secondary] [PRIMARY] [Secondary]` at x = 210 / 540 / 870 | Primary Ø 88 dp (231 px) visual / 96 dp (252 px) hit. Secondary 56 dp (147 px) visual / 76 dp (200 px) hit (Hoober bottom 12 mm) |
| Z5 Gesture margin | 2274–2400 | 866–914 | Home indicator / gesture bar | **Nothing interactive.** Background and dock shadow only |

Horizontal rules:
- Side margin ≥ 16 dp (42 px).
- No drag *start* zone within 24 dp (63 px) of the left or right edge, which is the Android back-gesture and iOS edge-swipe area.
- Readable text column ≤ 1080 px, centred on wider viewports.

Bottom sheets (journal, decor, settings):
- Rise from the dock, maximum 60% of height.
- The sheet's primary button sits at the bottom of the sheet.
- Close by tapping the scrim, swiping down, or Back.

Settings lives inside a sheet, not in a top corner, so Z1 has no required targets.

Type scale at 1× (font sizes in viewport px):

| Use | sp | px |
|---|---|---|
| Caption (minimum) | 12 | 32 |
| Label | 14 | 37 |
| Body | 16 | 42 |
| HUD numerals | 22 | 58 |
| Title | 28 | 74 |

### 1.3 Other aspect ratios, foldables and tablets

| Device class | Viewport (base 1080×1920 + expand) | Rule |
|---|---|---|
| 16:9 phone (1080×1920) | 1080×1920 | Z2 shrinks to ≈444 px (≈554 px if Z3 compresses to its 640 px floor). Z4 stays fixed |
| 20:9 (reference) | 1080×2400 | As specified above |
| 21:9 to ~23:9 (Xperia, Fold cover screen) | 1080×2520 to 2770 | Z2 grows. Z1, Z3 and Z4 stay fixed |
| 4:3 tablet / iPad (portrait) | ≈1440×1920 (height-limited) | Playfield column stays 1080 wide and centred. Side "diorama" art fills the rest (no black bars). HUD anchors to the corners |
| Foldable inner screen (~5:6 held portrait, e.g. 1812×2176) | ≈1600×1920 (≈2300×1920 if the window is 6:5 landscape) | Same as tablet |

- **Android 16 [V]:** For apps targeting API 36, orientation and aspect-ratio restrictions are ignored on screens with smallest width ≥ 600 dp, **except for games** identified by `android:appCategory` ([behavior-changes-16](https://developer.android.com/about/versions/16/behavior-changes-16)). Godot writes `appCategory`/`isGame` from `package/app_category`, which defaults to Game (`platform/android/export/gradle_export_util.cpp:372-388`). Keep that default.
- **iPadOS 26 [V]:** `UIRequiresFullScreen` is deprecated and will be ignored in a future release (Apple TN3192). Godot still writes it (`misc/dist/apple_embedded_xcode/.../Info.plist:47`). The layout must survive arbitrary window sizes, so react to `get_tree().root.size_changed`.

### 1.4 Godot implementation (verified APIs)

- **Safe area on Android:** `DisplayServer.get_display_safe_area()` is implemented on Android and iOS (`doc/classes/DisplayServer.xml:865`). On Android, in immersive mode, only `WindowInsetsCompat.Type.displayCutout()` is subtracted (`GodotIO.java:228-233`). Immersive is the default (`screen/immersive_mode=true`, `export_plugin.cpp:2262`), so **the gesture bar is not reported**, hence the 24 dp floor.
- **Safe area on iOS:** the result is `safeAreaInsets × screen_get_scale()` in physical px (`display_server_apple_embedded.mm:482`).
- **`get_display_cutouts()`** is Android-only.
- **dp conversion:**
  - Android: `screen_get_dpi()/160` gives the true `densityDpi` (`GodotIO.java:174`). `screen_get_scale()` is bucketed (2.0 for 420 dpi, `GodotIO.java:181`), so do not use it for dp.
  - iOS: `screen_get_scale()` = points-to-pixels.

```gdscript
# safe_area_margin.gd — on a full-rect MarginContainer that wraps the HUD layer.
extends MarginContainer
const FLOOR_DP := 24.0
func _ready() -> void:
	get_tree().root.size_changed.connect(_apply)
	_apply()
func _apply() -> void:
	var win := Vector2(DisplayServer.window_get_size())          # physical px
	var vp := get_viewport().get_visible_rect().size             # viewport px (e.g. 1080x2400)
	var k := vp.x / win.x                                        # phys -> viewport
	var s := Rect2(DisplayServer.get_display_safe_area())
	var ppd := (DisplayServer.screen_get_dpi() / 160.0) if OS.get_name() == "Android" else DisplayServer.screen_get_scale()
	var floor_px := FLOOR_DP * ppd * k
	add_theme_constant_override("margin_left",   int(s.position.x * k))
	add_theme_constant_override("margin_top",    int(max(s.position.y * k, floor_px)))
	add_theme_constant_override("margin_right",  int((win.x - s.end.x) * k))
	add_theme_constant_override("margin_bottom", int(max((win.y - s.end.y) * k, floor_px)))
```

The world layer sits outside this container and renders full-bleed under cutouts. iOS: `display/window/ios/hide_home_indicator=true` (already the default), `display/window/ios/suppress_ui_gesture=false` (engine default is `true`, which needs two swipes; we use no edge gestures, so leaving should take one swipe; keys in `doc/classes/ProjectSettings.xml:994-1001`). The docs note that `suppress_ui_gesture` has no effect on the home indicator while `hide_home_indicator=true`.

---

## 2. Gestures, tactile feedback & haptics

### 2.1 Gesture vocabulary

| Gesture | Use | Parameters | Tag |
|---|---|---|---|
| Tap | Everything essential | Press state on touch-**down** in the same frame. Action on touch-up. Sliding off cancels | H (platform convention) |
| Long-press | Inspect / pick up | 450 ms (Android default 400 ms, iOS `UILongPressGestureRecognizer.minimumPressDuration` 0.5 s). A radial fill starts at 150 ms | V (AOSP commit [ab9efea](https://android.googlesource.com/platform/frameworks/base/+/ab9efea%5E%21/) sets `DEFAULT_LONG_PRESS_TIMEOUT` 500→400; the release that first shipped it was not confirmed) / J |
| Drag | Arrange, brush, pet | Start after 24 viewport px (≈ 9 dp; Android touch slop 8 dp). Object follows the finger with **no positional smoothing**; softness comes from secondary motion (tilt, squash) | J |
| Swipe down | Dismiss sheet | Distance > 25% of sheet height or velocity > 1000 px/s | J |
| Pinch / 2-finger | Optional zoom only | Always mirrored by a double-tap or button (WCAG 2.5.1 Pointer Gestures, Level A) | V |

- **Engine settings [V]:** keep `input_devices/pointing/emulate_mouse_from_touch=true` (default; GUI relies on it); use `InputEventScreenTouch`/`ScreenDrag` for world input; leave the Android long-press-as-right-click and pan/scale gesture options at their `false` defaults.
- **Godot default too small [V]:** the default `gui/common/drag_threshold` is 10 px, about 4 dp at our scale. Set it to 24.
- **Latency [H]:** users notice touch latency in the single-digit to tens of milliseconds (Ng et al., UIST 2012, doi:10.1145/2380116.2380174; Jota et al., CHI 2013, doi:10.1145/2470654.2481317). The exact thresholds were not re-read from the full texts. Give visual feedback on the very next frame. Do not run a 100 ms tween before showing the pressed state.

### 2.2 "Tactile" feedback rules [H/J]

1. Every touch gets synchronised three-channel feedback: visual (scale 0.96 in 80 ms, spring back), audio (soft click ≤ −18 dBFS), optional haptic. Out-of-sync haptics feel broken ([Android haptics principles](https://developer.android.com/develop/ui/views/haptics/haptics-principles)).
2. Strength scales with rarity. Frequent events (collecting, scrolling) get the faintest tick. Rare milestones get the strongest.
3. No haptic or "error buzz" for "not allowed". Cozy design does not punish.
4. Rate limit: at most one haptic per 60 ms. Bursts (collect-all) become a single "ripple" of at most 3 ticks.

### 2.3 Haptics in Godot 4.7.2 (verified in source)

- **API [V]:** `Input.vibrate_handheld(duration_ms: int = 500, amplitude: float = -1.0)` (`core/input/input.cpp:161`). Implemented on Android, iOS and Web.
- **Android path [V]:** it calls `VibrationEffect.createOneShot(ms, amp×255)` and **requires the VIBRATE permission** (`GodotNativeBridge.kt:179`, `java_godot_wrapper.cpp:469`). Android's guidance says to *avoid legacy one-shot vibrations for touch feedback*, because they feel "buzzy". A good keyclick is 10–20 ms, and the actuator keeps ringing 20–50 ms afterwards.
- **iOS path [V]:** it creates a `CHHapticEventTypeHapticContinuous` event with `HapticIntensity = amplitude` (`apple_embedded.mm:73-117`), so there is no transient or sharpness control. Each call builds a new `CHHapticPattern` and player, and calls `NSLog` unconditionally (`apple_embedded.mm:114`), which is one more reason for the 60 ms rate limit. `Engine.get_singleton("AppleEmbedded")` (registered in `os_apple_embedded.mm:189`; the class has no XML docs) exposes `supports_haptic_engine()`, `start_haptic_engine()` and `stop_haptic_engine()` (`apple_embedded.mm:43-45`). The engine is created with `setAutoShutdownEnabled:true` (`apple_embedded.mm:63`), so starting it by hand is optional.
- **Web [V]:** amplitude is ignored, and Safari and Firefox for Android do not support it.

Android recommended path [V]: `performHapticFeedback` needs no VIBRATE permission and honours the system touch-feedback setting ([haptic-feedback](https://developer.android.com/develop/ui/views/haptics/haptic-feedback)). The pattern below follows the official example in `godot-docs/tutorials/platform/android/javaclasswrapper_and_androidruntimeplugin.rst`.

```gdscript
var _rt := Engine.get_singleton("AndroidRuntime")
var _act = _rt.getActivity() if _rt else null
var HFC = JavaClassWrapper.wrap("android.view.HapticFeedbackConstants")
func haptic_android(kind: int) -> void:
	var cb := func(): _act.getWindow().getDecorView().performHapticFeedback(kind)
	_act.runOnUiThread(_rt.createRunnableFromGodotCallable(cb))
# Usage: haptic_android(HFC.CLOCK_TICK). Gate API-34 constants on
# JavaClassWrapper.wrap("android.os.Build$VERSION").SDK_INT.
```

| Event (frequency) | Android constant (API) | iOS `vibrate_handheld(ms, amp)` [J, tune on device] | Apple equivalent intent |
|---|---|---|---|
| Button press | `VIRTUAL_KEY` (5) | 12, 0.35 | `UIImpactFeedbackGenerator(.light)` |
| Collect / frequent tick | `CLOCK_TICK` (21), or `SEGMENT_FREQUENT_TICK` (34) | 10, 0.25 | `UISelectionFeedbackGenerator` |
| Long-press threshold / pick up | `LONG_PRESS` (3), or `DRAG_START` (34) | 20, 0.5 | `.soft` |
| Drop / snap into place | `GESTURE_END` (30), or `SEGMENT_TICK` (34) | 14, 0.4 | `.rigid` (light) |
| Toggle | `TOGGLE_ON`/`TOGGLE_OFF` (34), else `CLOCK_TICK` | 12, 0.3 | selection |
| Rare milestone | `CONFIRM` (30) | 20 @0.5 → 90 ms gap → 30 @0.8 | `UINotificationFeedbackGenerator(.success)` |

Haptics setting: **Off / Subtle (default; ×0.7 amplitude, ticks off) / Full.** Apple HIG ("Playing haptics") asks for haptics that are optional, used consistently and paired with other feedback.

---

## 3. Session design & ethics

- **Data [V]:** GameAnalytics 2025 benchmarks (2024 data): median session 5–6 min (top 25%: 8–9 min), ~4 sessions/day, ~22 min/day ([report PDF mirror](https://investgame.net/wp-content/uploads/2025/02/2025-GameAnalytics-Mobile-Gaming-Benchmarks.pdf); [GameDev Reports summary](https://gamedevreports.substack.com/p/gameanalytics-mobile-gaming-benchmarks)). A newer GameAnalytics 2026 edition (2025 data) exists and its headline numbers are not directly comparable, so re-read it before quoting medians. **[FLAGGED, unverified]** Idle genre top 25%: ~6 min, ~5 sessions/day (older genre data, secondary sources only; no primary page found).
- **Three nested loops [J]:**
  1. **Glance (≤ 30 s):** cold start to interactive in ≤ 3 s. Android vitals marks cold start ≥ 5 s as excessive (warm ≥ 2 s, hot ≥ 1.5 s) ([launch-time](https://developer.android.com/topic/performance/launch-time), which now redirects to `/topic/performance/issues/launch-time`; the thresholds come from the indexed page text, and the current page no longer states them inline). Then one "while you were away" card, dismissed by tapping anywhere, and 1–3 taps to collect or tend.
  2. **Tend (3–8 min):** arrange, decorate, small choices. Nothing expires.
  3. **Ambient (optional, 5–60 min):** entered by a dock button or opt-in after 60 s idle.
     - HUD fades out over 600 ms.
     - 30 fps (or refresh/2 or /3), particles ×0.5.
     - `screen_set_keep_on(true)` only if the player enabled it.
     - Darker "night" palette. On OLED phones, dark mode saved 3–9% of power on average at 30–50% brightness and 39–47% at 100% brightness (Dash & Hu, MobiSys 2021, doi:10.1145/3458864.3467682; [Purdue summary](https://engineering.purdue.edu/ECE/News/2021/dark-mode-may-not-save-your-phones-battery-life-as-much-as-you-think-but-there-are-a-few-silver-linings)).
     - The **first tap only wakes** the screen and never triggers an action.
- **Offline progress [J]:** `Time.get_unix_time_from_system()` delta, capped at 12 h; ignore negative/implausible deltas (clock guard). Never lost, only paused at the cap; framed as abundance ("the garden grew").
- **Persistence [V/J]:**
  - Save on `NOTIFICATION_APPLICATION_PAUSED`. On iOS there are only about 5 s (`doc/classes/Node.xml:1315-1318`).
  - Autosave every 30 s.
  - Write a temp file, then rename it (atomic save).
  - Android Back: handle `NOTIFICATION_WM_GO_BACK_REQUEST` to close the top sheet first. **Also set `application/config/quit_on_go_back=false`.** Its engine default is `true` (`core/config/project_settings.cpp:1709`; `scene/main/scene_tree.cpp:900`), which quits the app on the first Back. With it off, Back on the root screen must quit explicitly (`get_tree().quit()`) or show a calm "leave?" sheet. Godot already uses `OnBackPressedCallback` for API-36 predictive back (`GodotActivity.kt:143-144`).
- **No dark patterns [V]:** Zagal, Björk & Lewis (FDG 2013) list temporal dark patterns ("grinding", **"playing by appointment"**), monetary ones (pay-to-skip, pre-delivered content) and social ones. King et al. (2019, *Computers in Human Behavior* 101:131–143, doi:10.1016/j.chb.2019.07.017) show how monetisation patents exploit players. Our rules:
  - no energy or stamina
  - no streak loss
  - no expiring rewards or limited-time FOMO events
  - no loot boxes
  - no confirmshaming
  - no interstitials
  - closing the app is always one gesture
- **Notifications [V/J]:**
  - Godot 4.7.2 has no local-notification API, so it would need a native plugin. The only match in the source is the permission name in the Android exporter list (`platform/android/export/export_plugin.cpp:158`). Android 13+ requires the `POST_NOTIFICATIONS` runtime permission. App Store guideline 4.5.4 (about *push* notifications) says they must not be required for the app to work, and must not be used for promotions unless the user explicitly opts in through consent shown in the app, with a way to opt out.
  - v1 ships with **zero notifications**.
  - If added later: off by default; offered only after 3 or more sessions; at most one per day; neutral wording ("Your moonflowers opened 🌙").

---

## 4. Performance & battery

### 4.1 Hardware facts

- **TBDR [V]:** Mali, Adreno and Apple GPUs are tile-based; hidden-surface removal does **not** help blended 2D sprites, so every overlapping transparent layer is shaded again (Godot `gpu_optimization.rst`; Arm GPU Best Practices; Apple TBDR guide).
- **Fill cost is the 2D bottleneck [V]:** one full-screen layer at 1080×2400 is 2.59 Mpx, which is 155 Mpx/s at 60 fps. Reading the screen texture (`hint_screen_texture`, BackBufferCopy) forces a tile resolve and is expensive on TBDR.
- **Reference devices [V, spec sheets]:**
  - Low tier 2022: Galaxy A13 (Exynos 850, Mali-G52 MP1, 3–4 GB, 1080×2408, 60 Hz) or Redmi Note 11 (Snapdragon 680, Adreno 610, 4 GB, 1080×2400, 90 Hz).
  - iPhone 12: A14, 4-core GPU, 4 GB, 1170×2532 @3×, 60 Hz.

### 4.2 Engine findings (4.7.2 source)

| Finding | Evidence | Consequence |
|---|---|---|
| `low_processor_mode` only skips drawing when nothing changed. Any visible material using `TIME`, an active particle system or an animation slice calls `redraw_request()` every frame | `renderer_canvas_render_rd.cpp:914,2887,3174`; `rasterizer_canvas_gles3.cpp:564,1279,1436`; `main.cpp:5087` | It gives no benefit for an animated cozy scene. Its sleep (`low_processor_mode_sleep_usec=6900`) is a per-frame pacing target, roughly a 144 fps cap, not extra time added to each frame. A lower `max_fps` overrides it (`core/os/os.cpp:719-728`). **Keep off**; use `Engine.max_fps` |
| Compatibility renders the root viewport into an off-screen render target and then blits it to the window. That is one extra full-screen pass of bandwidth every frame. The opaque default target is `GL_RGB10_A2`; `RGBA16F` is used when HDR-2D is on | `servers/rendering/renderer_viewport.cpp:931-944`; `drivers/gles3/storage/texture_storage.cpp:2553-2569` | Count the blit as about one layer in the overdraw budget. `RenderingServer.viewport_set_render_direct_to_screen` would skip it, but it disables stretch modes and screen-texture reads, so it is **not usable** with `canvas_items` stretch |
| On Android, Swappy frame pacing exists **only in the Vulkan driver**. `Engine.max_fps` sets the swap interval to `max(refresh, 1/max_fps)` | `rendering_device_driver_vulkan.cpp:4150-4162`; no Swappy in `drivers/gles3` | With Compatibility on Android, `max_fps` is a CPU sleep, so 30 fps may jitter by ±1 vsync. **Measure on device** |
| The `swappy_mode` switch looks inverted against its docs (mode 0 sets `AutoSwapInterval(true)`, mode 2 sets `false`) | `rendering_device_driver_vulkan.cpp:3861-3875` vs `ProjectSettings.xml:976` | Only matters if we switch to the Mobile renderer. Verify empirically |
| iOS `preferredFrameRate` is 120 when `display/window/ios/allow_high_refresh_rate=true` (default). Godot sets `CADisableMinimumFrameDurationOnPhone` | `platform/ios/godot_view_ios.mm:89-93`; `Info.plist:61` | Cap with `Engine.max_fps`. 120 Hz stays opt-in |
| GPU timer queries are captured only for desktop GL, not GLES | `drivers/gles3/storage/utilities.cpp:329-336` | `viewport_get_measured_render_time_gpu` is unreliable on mobile Compatibility. Build the quality governor on **frame-delta statistics** |
| GLES3 shaders default to `highp` | `drivers/gles3/shader_gles3.cpp:219` | `TIME` precision is fine with the default `rendering/limits/time/time_rollover_secs=3600`. Choose loop periods that **divide 3600 s** (2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 24, 30, 60 …) so the rollover is seamless. Never do time math in `mediump` |
| Canvas `instance uniform` works in RD and GLES3 | `CanvasItem.xml:615`; `rasterizer_canvas_gles3.cpp:908` | Share **one** ShaderMaterial and vary per-item parameters, which preserves batching |
| No thermal API in Godot | grep "thermal": matches only in `modules/openxr/` | Android: `PowerManager.getThermalHeadroom(10)` (API 30) via `JavaClassWrapper`. Android docs say there is no benefit to calling it more than about once per second, and much faster calls may return NaN; we poll at ≤ 0.1 Hz [J]. iOS: rely on the frame-time governor |
| Particles (Compatibility): `emit_particle()`, trails and sub-emitters are **not supported** (engine prints a warning). Particle **SDF collision**: the docs table (`renderers.rst`) says unsupported, but the 4.7.2 GLES3 source implements it | `GPUParticles2D.xml:41`; `drivers/gles3/storage/particles_storage.cpp:303,387,392` (warnings); SDF path `rasterizer_canvas_gles3.cpp:1217-1227`, `particles_storage.cpp:585-626` | Use simple emitters. CPUParticles2D for counts under ~100 [H]. Treat SDF collision as "works in source, docs disagree": test it before use |
| `PIPELINE_COMPILATIONS_*` monitors are **hard-coded to 0** on Compatibility | `drivers/gles3/rasterizer_canvas_gles3.h:377`, `rasterizer_scene_gles3.h:878` (`return 0`) | An assert on them proves nothing on our renderer. Detect shader-compile hitches as first-use frame-time spikes. GLES3 caches program binaries in `user://` (`drivers/gles3/shader_gles3.cpp:557-671`, `rasterizer_gles3.cpp:339-345`), so expect stutter mainly on the first run after install or update |

### 4.3 Budgets per frame [J; derived from H above; verify on device]

| Metric | Low tier (Mali-G52/Adreno 610) | iPhone 12 |
|---|---|---|
| Interactive fps / ambient fps | 60 (45 on 90 Hz panels) / 30 | 60 / 30 |
| CPU frame (process + render submit) | ≤ 9 ms | ≤ 7 ms |
| GPU frame | ≤ 12 ms (≈ 70% of 16.7 ms, thermal headroom) | ≤ 10 ms |
| 2D draw calls after batching (`Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME`) | ≤ 100 | ≤ 250 |
| Visible CanvasItems | ≤ 600 | ≤ 1,500 |
| Mean overdraw (full-screen equivalents) | ≤ 2.5× | ≤ 4× |
| Per-frame full-screen post / screen-texture reads | 0 (static snapshots only) | ≤ 1 cheap pass |
| Live particles | ≤ 150 | ≤ 600 |
| GPU texture memory (`RENDER_TEXTURE_MEM_USED`) | ≤ 96 MB | ≤ 192 MB |
| Total RAM (PSS) | ≤ 300 MB | ≤ 450 MB |
| Shader-compile hitches during play (frames > 2× target on the first use of a material; `PIPELINE_COMPILATIONS_*` always reads 0 on Compatibility) | 0 after warm-up | 0 after warm-up |
| Cold start to interactive | ≤ 3 s | ≤ 2 s |

Memory arithmetic [V]:
- A 1080×2400 RGBA8 layer is 10.4 MB, or 13.8 MB with mipmaps.
- ASTC 4×4 or ETC2 at 8 bpp is 2.6 MB.
- Use VRAM compression (`rendering/textures/vram_compression/import_etc2_astc=true`; default `false`, but the Android and iOS exporters refuse to export without it: `platform/android/export/export_plugin.cpp:3148-3151`, `editor/export/editor_export_platform_apple_embedded.cpp:2293`) for large painted backgrounds. Keep SVG-rasterised UI lossless, packed in ≤ 2048² atlases. For SVG icons that must stay crisp at any scale, `DPITexture` (experimental in 4.7) re-rasterises when the stretch scale changes (`doc/classes/DPITexture.xml`; `multiple_resolutions.rst` "Reducing aliasing on downsampling").
- Low-tier 720×1600 screens downscale to 0.667×. Enable mipmaps plus `rendering/textures/canvas_textures/default_texture_filter=2` (Linear Mipmap) for world art (`multiple_resolutions.rst` "reducing aliasing on downsampling").

### 4.4 Techniques [H/J]

1. **Frame-rate policy:** `target = refresh / round(refresh / desired)`, using `DisplayServer.screen_get_refresh_rate()`, so the result divides the refresh rate exactly (90 Hz → 45 or 90; 120 → 60 or 30). Set `Engine.max_fps` on mode change. Android's frame-rate guidance says to render at the rate the content needs.
2. **Quality governor:**
   - Keep a 3 s rolling window of `delta`. If more than 5% of frames exceed 1.5× the target interval, step down one tier.
   - Step back up only after 30 s clean.
   - Tiers scale particle counts, parallax layer count, background SubViewport scale (1.0 → 0.75) and the update rate of static layers. For a static layer, set `SubViewport.render_target_update_mode = UPDATE_ONCE` when its content changes and leave it at `UPDATE_DISABLED` otherwise. `UPDATE_WHEN_VISIBLE` re-renders every frame while visible, so it saves nothing.
3. **Static layers:** pre-render sky gradients and distant hills to textures; animate via cheap UV/vertex shaders.
4. **"Glass"/frosted sheets** (a 2026 look): capture a 1/4-res snapshot **once** when a sheet opens, blur it in two passes at low res, then display it as a texture. Never sample the live screen texture every frame.
5. **Gradient banding without HDR-2D:** add ±0.5/255 blue-noise or interleaved-gradient dither in gradient shaders. The phone's 8-bit window framebuffer quantises the result anyway, so dither is needed even though Compatibility's opaque internal target is RGB10_A2. Dither is cheaper than HDR-2D's RGBA16F target. Note on HDR-2D: the docs table (`renderers.rst`, "2D HDR Viewport") says Compatibility does not support it, but the 4.7.2 GLES3 source allocates `GL_RGBA16F` when `use_hdr_2d` is on (`drivers/gles3/storage/texture_storage.cpp:2553-2558`, `:3226-3238`). It is untested on mobile GLES and needs float colour-buffer support, so **do not rely on it**.
6. **Warm-up:** at boot, behind the splash, draw each material and particle material once off-screen. Check in a perf test that no frame after warm-up exceeds 2× the target interval. Do not assert `PIPELINE_COMPILATIONS_*`, which is always 0 on GLES3. Shader Baker (`shader_baker/enabled`, an export option) applies only to Forward+/Mobile (`platform/android/doc_classes/EditorExportPlatformAndroid.xml:621-624`).
7. **Processing hygiene:**
   - `process_mode = Node.PROCESS_MODE_DISABLED` for off-screen systems; `VisibleOnScreenEnabler2D` for critters.
   - `physics/common/physics_ticks_per_second=30` if physics is only cosmetic.
   - No `_process` polling for UI; use signals.
8. **Audio:** keep `audio/general/ios/session_category=0` (Ambient: respects the silent switch, mixes with podcasts; `project_settings.cpp:1760`, applied in `drivers/apple_embedded/app_delegate_service.mm:100-122`). Bake reverb into assets; no live reverb buses.

---

## 5. Accessibility

- **Platform reality [V]:**
  - AccessKit is built only for `macos`, `windows` and `linuxbsd` (`drivers/SCsub:36`). It is the only `AccessibilityServer` backend in 4.7.2 (`drivers/accesskit/accessibility_server_accesskit.cpp:1790`); the per-element `DisplayServer.accessibility_*` update methods are deprecated in favour of `AccessibilityServer`.
  - `DisplayServer.accessibility_should_reduce_animation()` is implemented on macOS and Windows only; `accessibility_should_increase_contrast()` on Linux, macOS and Windows (`DisplayServer.xml:108-127`).
  - So **TalkBack/VoiceOver cannot read the game in 4.7.2**; OS motion/contrast preferences need other routes. Still set `accessibility_name` on Controls (cheap, future-proof).
- **Reading OS preferences:**
  - Android (via `JavaClassWrapper`): `ValueAnimator.areAnimatorsEnabled()` (API 26) returns false under "Remove animations". Font scale comes from `Settings$System.getFloat(activity.getContentResolver(), "font_scale", 1.0)`.
  - Web: `JavaScriptBridge.eval("matchMedia('(prefers-reduced-motion: reduce)').matches")`.
  - iOS: in-game toggle only, since a plugin would be required.
- **Calm motion (default follows the OS when readable):**
  - Replace translate and scale transitions with ≤ 150 ms crossfades.
  - Parallax 0, particles ×0.3, no camera drift.
  - Ambient loops slower than 4 s per cycle.
  - Nothing ever flashes more than 3 times per second (WCAG 2.3.1, A).
  - Auto-moving decorative content can be paused (2.2.2, A).
- **Contrast [V]:** WCAG 2.2 requires 4.5:1 for body text, 3:1 for text ≥ 24 px CSS / 18.66 px bold, and 3:1 for UI components and meaningful graphics (1.4.11). Measured with our script (`/tmp/claude-research/scripts/contrast.py`):
  - cocoa `#3B2A26` on cream `#FFF4E6` = **12.5:1** ✓
  - `#7A6A63` on cream = 4.75:1 ✓ (minimum grey for body text)
  - white on pastel pink `#F4A7B9` = **1.9:1** ✗
  - white on mint `#8FC9A9` = **1.9:1** ✗
  - cocoa on pink = 7.2:1 ✓
  - **Rule:** dark text on pastel fills, never white on pastel.
- **Colour-vision deficiency [V/J]:**
  - About 8% of men and 0.4% of women of European descent have red-green deficiency (Birch 2012, doi:10.1364/JOSAA.29.000313).
  - Never encode state by hue alone (WCAG 1.4.1, A). Add shape, icon or pattern.
  - CI check: simulate protan, deutan and tritan views with Machado et al. 2009 (doi:10.1109/TVCG.2009.113) matrices at severity 1.0, and require CIEDE2000 ΔE ≥ 10 between any two categorical palette colours in every simulation [J threshold].
- **Text scale:** in-game 100 / 115 / 130 / 150 / 200%, defaulting from the Android `font_scale` (WCAG 1.4.4 asks for 200%). Implement by rebuilding the Theme font sizes, not `content_scale_factor`, so hit areas keep their layout. HUD strings get a 2-line or ellipsis fallback.
- **Audio–visual pairing:** every meaningful sound gets a visual "sound bubble" caption; every visual reward gets a sound. Separate Music/Ambience/SFX sliders. Mono toggle: put an `AudioEffectStereoEnhance` with `pan_pullout=0.0` on the Master bus ("A value of 0 will downmix stereo to mono", `doc/classes/AudioEffectStereoEnhance.xml:15-16`).
- **Motor:** no timed inputs, no rapid tapping, no multi-touch requirement (WCAG 2.5.1). Long-press can be replaced by tap-to-select plus a button. Left-handed toggle mirrors any asymmetric elements.
- **Read aloud (optional):** `DisplayServer.tts_speak()` works on Android, iOS and Web (`DisplayServer.xml:2073-2091`). Keep `audio/general/text_to_speech=false` so TTS does not cost idle CPU.

---

## 6. App-store readiness (as of 2026-10-20)

| Requirement | Status / source | Godot 4.7.2 | Action |
|---|---|---|---|
| Play target API: new apps and updates must target **API 36** from 2026-08-31 (extension to 2026-11-01) | [target-sdk](https://developer.android.com/google/play/requirements/target-sdk) [V] | Default `targetSdk 36`, `compileSdk 36`, `minSdk 24` (`java/app/config.gradle:3-9`; `export_plugin.cpp:303-305`) | Keep the default |
| **16 KB pages**: required for API ≥ 35 apps on 64-bit devices. From 2027-02-01, non-compliant updates are blocked. Needs NDK r28+ and AGP ≥ 8.5.1 | [page-sizes](https://developer.android.com/guide/practices/page-sizes) [V] | NDK `29.0.14206865` (16 KB-aligned ELF by default), AGP 8.6.1. The non-Gradle exporter pads `.so` to 16 KB (`export_plugin.cpp:4378-4432`) | Verify with `zipalign -c -P 16 -v 4 app.apk` |
| Edge-to-edge enforced (API 35); opt-out disabled for API 36 on Android 16 | behavior-changes-16 [V] | Immersive by default. Non-immersive pads the decor view by insets (`Godot.kt:357-399`) | Keep `screen/immersive_mode=true`, `screen/edge_to_edge=false` |
| Predictive back (API 36) | behavior-changes-16 [V] | `OnBackPressedCallback` (`GodotActivity.kt:143`); changelog GH-117653 | Handle `NOTIFICATION_WM_GO_BACK_REQUEST` and set `application/config/quit_on_go_back=false` |
| AAB upload | Play policy [V] | Requires a Gradle build (Android SDK in CI) | Plan CI: export templates and SDK needed |
| Haptics permission | — | `VIBRATE` is needed only for `vibrate_handheld` | Not needed if R7 is followed |
| iOS: build with **Xcode 26 / iOS 26 SDK** since 2026-04-28 | [Apple upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) [V] | Godot exports an Xcode project (fix for Xcode 26 deploy in 4.7). Minimum iOS 15.0 (`platform/ios/export/export_plugin.h:44`) | Needs a macOS runner; out of scope in this container |
| iOS privacy manifest | Apple, required-reason APIs [V] | `PrivacyInfo.xcprivacy` is generated from `privacy/*` options. Engine defaults (flag values): file timestamp DDA9.1+C617.1 (3), boot time 35F9.1 (1), disk space E174.1+85F4.1 (3) (`editor_export_platform_apple_embedded.cpp:88-103`) | [J] Set `privacy/file_timestamp_access_reasons` to **C617.1** only (flag 2), `privacy/system_boot_time_access_reasons` to **35F9.1** (1), `privacy/disk_space_access_reasons` to **E174.1** (1), `privacy/tracking_enabled=false`, no collected data. Keeping DDA9.1/85F4.1 is harmless if review asks |
| UIScene lifecycle | Apple (post-iOS 26) [V] | `UIApplicationSceneManifest` present in Info.plist | None |
| iPad resizable windows (`UIRequiresFullScreen` deprecated) | Apple TN3192 [V] | Key still written | Responsive layout (§1.3) |
| Renderer note | — | Compatibility on iOS = OpenGL ES 3.0, deprecated by Apple since iOS 12 but still shipping [V/J] | Keep shaders portable so `rendering_method.mobile="mobile"` (Metal) is a one-line A/B |

---

## 7. Open risks & device checks

1. Compatibility renderer pacing at 30 fps on Android (no Swappy). Measure frame-delta jitter. If p95 > 40 ms, keep ambient at 60 with lighter content, or A/B the Mobile renderer.
2. iOS haptic latency and feel for short continuous events. Tune the table in §2.3.
3. Back-gesture behaviour in immersive mode at screen edges. Keep the 24 dp no-drag-start margin.
4. A battery soak: 30 min ambient at 50% brightness, measured with Perfetto/`batterystats` and the Xcode Energy gauge. [J] target: ≤ 8%/h on the iPhone 12 in ambient mode.
5. The docs and the source disagree on Compatibility features: HDR-2D and particle SDF collision are listed as unsupported in `renderers.rst` but are implemented in the 4.7.2 GLES3 source. Do not design around either until a device test (llvmpipe first, then a real Mali/Adreno phone) shows them working.

---

## References

Papers:
- Bergstrom-Lehtovirta, J., Oulasvirta, A. (2014). Modeling the functional area of the thumb on mobile touchscreen surfaces. CHI, 1991–2000. doi:10.1145/2556288.2557354
- Birch, J. (2012). Worldwide prevalence of red-green color deficiency. JOSA A 29(3). doi:10.1364/JOSAA.29.000313
- Dash, P., Hu, Y.C. (2021). How much battery does dark mode save? An accurate OLED display power profiler for modern smartphones. MobiSys. doi:10.1145/3458864.3467682
- Fitts, P.M. (1954). J. Exp. Psych. 47(6). doi:10.1037/h0055392
- Holz, C., Baudisch, P. (2010). The generalized perceived input point model and how to double touch accuracy by extracting fingerprints. CHI, 581–590. doi:10.1145/1753326.1753413
- Hoober, S. (2013). How do users really hold mobile devices? UXmatters. Also Hoober, *Touch Design for Mobile Interfaces* (Smashing, 2022), via the Smashing 2023 cheatsheet.
- Jota, R., Ng, A., Dietz, P., Wigdor, D. (2013). How fast is fast enough? A study of the effects of latency in direct-touch pointing tasks. CHI, 2291–2300. doi:10.1145/2470654.2481317
- King, D.L., Delfabbro, P.H., Gainsbury, S.M., Dreier, M., Greer, N., Billieux, J. (2019). Unfair play? Video games as exploitative monetized services. Computers in Human Behavior 101:131–143. doi:10.1016/j.chb.2019.07.017
- MacKenzie, I.S. (1992). Fitts' law as a research and design tool in HCI. HCI 7(1). doi:10.1207/s15327051hci0701_3
- Machado, G.M., Oliveira, M.M., Fernandes, L.A.F. (2009). IEEE TVCG 15(6). doi:10.1109/TVCG.2009.113
- Ng, A., Lepinski, J., Wigdor, D., Sanders, S., Dietz, P. (2012). Designing for low-latency direct-touch input. UIST, 453–464. doi:10.1145/2380116.2380174
- Parhi, P., Karlson, A., Bederson, B. (2006). MobileHCI. doi:10.1145/1152215.1152260
- Zagal, J.P., Björk, S., Lewis, C. (2013). Dark patterns in the design of games. FDG.

Platform guidance:
- Apple HIG: Accessibility, Layout, Playing haptics. Apple `CHHapticEngine.isAutoShutdownEnabled` reference.
- Apple TN3192.
- Apple Upcoming Requirements.
- App Review Guideline 4.5.4.
- Android: haptic-feedback, haptics-principles, `HapticFeedbackConstants` reference, `PowerManager.getThermalHeadroom` reference, behavior-changes-16, target-sdk, page-sizes, launch-time, notification-permission, ADPF thermal.
- Google Accessibility "Touch target size".
- W3C WCAG 2.2.
- GameAnalytics Mobile Gaming Benchmarks 2025.
- Godot docs (`godot-docs` master, 2026-10-19): `renderers.rst`, `multiple_resolutions.rst`, `gpu_optimization.rst`, `javaclasswrapper_and_androidruntimeplugin.rst`.

Engine source: all paths are relative to `/home/user/godotengine/godot` at tag `4.7.2-stable`.

---

## Verification log

Adversarial fact-check, 2026-10-20. Engine paths are relative to `/home/user/godotengine/godot` (tag `4.7.2-stable`, commit `ed1daf0`). Web pages were fetched with curl or WebFetch, or checked through WebSearch when a host was blocked (marked "secondary"). DOIs could not be resolved here because `doi.org` and `api.crossref.org` are blocked, so papers were checked by title, authors and venue.

**Engine: project settings, defaults and keys**

| Claim | Verdict | Evidence |
|---|---|---|
| Stretch, size and orientation keys (R1) | FIXED: the `display/` prefix was missing; the engine defaults are `disabled`/`keep` and only *new* projects get canvas_items+expand | `core/config/project_settings.cpp:1719-1720,1787-1788`; `editor/editor_node.cpp:8346-8352`; `main/main.cpp:2836` |
| `gui/common/drag_threshold` default 10 | OK | `project_settings.cpp:1818`; `ProjectSettings.xml:1236` |
| `keep_screen_on` "default off" (R12) | FIXED: the engine default is `true` | `project_settings.cpp:1745`; `ProjectSettings.xml:969` |
| `low_processor_mode` false, sleep 6900 µs | OK; the "adds 6.9 ms" wording was FIXED (it is a pacing target, and `max_fps` overrides it) | `main/main.cpp:2263-2265`; `core/os/os.cpp:708-740` |
| `max_fps` default 0; `physics_ticks_per_second` key | OK | `main/main.cpp:2252,2255` |
| iOS `hide_home_indicator`/`suppress_ui_gesture`/`allow_high_refresh_rate` (all default `true`) | OK (the default is now noted) | `main/main.cpp:2866-2869`; `ProjectSettings.xml:991-1003` |
| `session_category` 0 = Ambient; `text_to_speech` default false | OK | `project_settings.cpp:1756,1760`; `drivers/apple_embedded/app_delegate_service.mm:100-122` |
| `time_rollover_secs` 3600; `default_texture_filter` 2 = Linear Mipmap | OK | `ProjectSettings.xml:3222`; `project_settings.cpp:1844` |
| `import_etc2_astc` required for Android export | OK; iOS requires it too | `platform/android/export/export_plugin.cpp:3148-3151`; `editor/export/editor_export_platform_apple_embedded.cpp:2293` |
| `emulate_mouse_from_touch` true; Android long-press / pan-scale default false | OK | `ProjectSettings.xml:1689-1701` |
| Back handling | FIXED (omission): `application/config/quit_on_go_back` defaults to `true` | `project_settings.cpp:1709`; `scene/main/scene_tree.cpp:900` |

**Engine: display, safe area, haptics, accessibility**

| Claim | Verdict | Evidence |
|---|---|---|
| `get_display_safe_area` Android+iOS; `get_display_cutouts` Android-only | OK | `doc/classes/DisplayServer.xml:858-869` |
| Immersive mode subtracts only the cutout; immersive is on by default | OK | `GodotIO.java:216-250`; `export_plugin.cpp:2262-2263` |
| iOS safe area = `safeAreaInsets × UIScreen.scale` | OK | `display_server_apple_embedded.mm:482-489`; `platform/ios/display_server_ios.mm:116-122` |
| Android `screen_get_dpi` = densityDpi; `screen_get_scale` is bucketed (420 dpi → 2.0) | OK | `GodotIO.java:174-198`; `display_server_android.cpp:346-376` |
| `vibrate_handheld(500, -1.0)`; Android `createOneShot` and the VIBRATE permission; amplitude ×255 | OK | `core/input/input.cpp:161`; `GodotNativeBridge.kt:179-209`; `java_godot_wrapper.cpp:469-481`; `Input.xml:807-819` |
| iOS continuous event with intensity only | OK; the per-call `NSLog` was added | `drivers/apple_embedded/apple_embedded.mm:73-117` |
| `AppleEmbedded` singleton methods | OK (undocumented class) | `os_apple_embedded.mm:189`; `apple_embedded.mm:41-45` |
| "Call `start_haptic_engine()` at boot and on resume" (R8) | FIXED: not required; auto-shutdown is on | `apple_embedded.mm:63`; Apple `CHHapticEngine.isAutoShutdownEnabled` docs |
| `AndroidRuntime.getActivity/createRunnableFromGodotCallable`; JavaClass static fields readable | OK | `plugin/AndroidRuntimePlugin.kt:120-146`; `java_class_wrapper.cpp:722-724,1648-1660`; `godot-docs/.../javaclasswrapper_and_androidruntimeplugin.rst:90-99` |
| AccessKit desktop-only; reduce-animation only on macOS/Windows; increase-contrast on Linux/macOS/Windows | OK; the `AccessibilityServer` note was added | `drivers/SCsub:35-37`; `DisplayServer.xml:108-127`; `drivers/accesskit/accessibility_server_accesskit.cpp:1790` |
| `Control.accessibility_name`; `tts_speak` on Android/iOS/Web | OK | `Control.xml:1056`; `DisplayServer.xml:2073-2091` |
| `NOTIFICATION_APPLICATION_PAUSED` gives about 5 s on iOS; `WM_GO_BACK_REQUEST` is Android-only | OK | `Node.xml:1260-1263,1315-1319` |
| No local-notification API | OK | grep: only the permission string at `export_plugin.cpp:158` |
| Mono toggle implementation | ADDED | `AudioEffectStereoEnhance.xml:15-16` |

**Engine: rendering and performance**

| Claim | Verdict | Evidence |
|---|---|---|
| `TIME`/particles/animation call `redraw_request()` | OK; RD line FIXED (2973 is the debug-redraw path, TIME is at 914) | `renderer_canvas_render_rd.cpp:914,2887,3174`; `rasterizer_canvas_gles3.cpp:564,1279,1436`; `main.cpp:5087` |
| Swappy only in Vulkan; `max_fps` → `SwappyVk_setSwapIntervalNS(max(refresh, 1/max_fps))` | OK | `drivers/vulkan/rendering_device_driver_vulkan.cpp:1873-1875,4150-4162`; no Swappy in `drivers/gles3` |
| `swappy_mode` switch inverted against its docs | OK (confirmed) | `rendering_device_driver_vulkan.cpp:3855-3874` vs `ProjectSettings.xml:976-981` |
| On Compatibility, `max_fps` is a CPU sleep | OK | `core/os/os.cpp:708-740`, called from `main/main.cpp:5178` on every platform loop |
| iOS `preferredFrameRate` 120/60; `CADisableMinimumFrameDurationOnPhone` | OK | `platform/ios/godot_view_ios.mm:86-94`; `godot_apple_embedded-Info.plist:61` |
| GPU timestamps only when GLES runs over desktop GL | OK | `drivers/gles3/storage/utilities.cpp:329-336` |
| GLES3 `precision highp` default | OK | `drivers/gles3/shader_gles3.cpp:218-219` |
| Canvas `instance uniform` on GLES3 | OK | `CanvasItem.xml:615-621`; `rasterizer_canvas_gles3.cpp:908` |
| "Compatibility has no RGBA16F / HDR-2D" | FIXED: the docs say unsupported, but the source allocates RGBA16F; the opaque default is RGB10_A2 | `drivers/gles3/storage/texture_storage.cpp:2553-2569,3226-3238`; `godot-docs/tutorials/rendering/renderers.rst:351-382` |
| MSAA-2D unsupported on Compatibility | OK | `ProjectSettings.xml:2859-2861` |
| Trails, `emit_particle` unsupported | OK; sub-emitters ADDED | `particles_storage.cpp:303,387,392`; `GPUParticles2D.xml:41` |
| Particle SDF collision unsupported | FLAGGED: implemented in source, docs disagree | `rasterizer_canvas_gles3.cpp:1217-1227`; `particles_storage.cpp:585-626` |
| Assert `PIPELINE_COMPILATIONS_* == 0` | FIXED: always 0 on GLES3 | `rasterizer_canvas_gles3.h:377`; `rasterizer_scene_gles3.h:878` |
| Shader Baker applies only to RD renderers | OK | `EditorExportPlatformAndroid.xml:621-624` |
| Root viewport off-screen render + blit on Compatibility | ADDED | `renderer_viewport.cpp:931-944`; `RenderingServer.xml:4351-4356` |
| `UPDATE_WHEN_VISIBLE` for static layers | FIXED (it re-renders every frame) | `SubViewport.xml:53-65` |
| No thermal API | OK (matches only in OpenXR) | grep of `core servers scene platform drivers main modules` |
| iOS Compatibility = native EAGL GLES3 | OK | `platform/ios/display_layer_ios.mm:97`; `platform/ios/detect.py:178-183` |
| Arithmetic (dp↔px, zones, type scale, MB, Mpx/s, contrast) | OK, except the foldable row (FIXED: 5:6 portrait gives about 1600 px wide) | recomputed; contrast 12.51 / 4.75 / 1.90 / 1.89 / 7.17 |

**Store, platform and web sources**

| Claim | Verdict | Evidence |
|---|---|---|
| Play: target API 36 from 2026-08-31, extension to 2026-11-01 | OK | developer.android.com/google/play/requirements/target-sdk |
| 16 KB pages: API ≥ 35 on 64-bit; updates blocked from 2027-02-01; NDK r28+, AGP ≥ 8.5.1; `zipalign -c -P 16 -v 4` | OK | developer.android.com/guide/practices/page-sizes |
| Godot targetSdk/compileSdk 36, minSdk 24, AGP 8.6.1, NDK 29.0.14206865; 16 KB `.so` padding | OK | `platform/android/java/app/config.gradle:2-17`; `export_plugin.cpp:303-305,4378` |
| Android 16: sw ≥ 600 dp restrictions ignored except for games (`appCategory`); edge-to-edge opt-out removed; predictive back | OK | developer.android.com/about/versions/16/behavior-changes-16; `gradle_export_util.cpp:372-388`; `export_plugin.cpp:2240`; CHANGELOG GH-117653 |
| Haptics: no VIBRATE needed for `performHapticFeedback`, honours settings; avoid `createOneShot`; keyclick 10–20 ms, ringing 20–50 ms | OK | developer.android.com …/haptics/haptic-feedback, …/haptics-principles |
| `HapticFeedbackConstants` API levels (VIRTUAL_KEY 5, LONG_PRESS 3, CLOCK_TICK 21, GESTURE_END/CONFIRM 30, DRAG_START/SEGMENT_TICK/SEGMENT_FREQUENT_TICK/TOGGLE_* 34) | OK (all 9) | developer.android.com/reference/android/view/HapticFeedbackConstants |
| `getThermalHeadroom` API 30 | OK; polling note added | developer.android.com/reference/android/os/PowerManager |
| Long-press 400 ms (AOSP) | OK (release unconfirmed) | android.googlesource.com commit ab9efea |
| Cold start ≥ 5 s excessive | OK (secondary: the page moved and the threshold text was not re-read) | WebSearch index of developer.android.com/topic/performance/launch-time |
| Xcode 26 / iOS 26 SDK since 2026-04-28 | OK | developer.apple.com/news/upcoming-requirements |
| TN3192: `UIRequiresFullScreen` deprecated in iPadOS 26; Godot still writes it | OK | TN3192 JSON; `godot_apple_embedded-Info.plist:47` |
| App Review 4.5.4 "opt-in for anything promotional" | FIXED: applies to *push* notifications | developer.apple.com/app-store/review/guidelines |
| iOS minimum 15.0; privacy-reason codes and default flags; UIScene manifest/delegate | OK; tag on our reason choice changed to J | `platform/ios/export/export_plugin.h:44`; `editor_export_platform_apple_embedded.cpp:88-103,339-349`; `Info.plist:62`; `app_delegate_service.h:37` |
| Apple HIG "requires ≥ 44×44 pt" | FIXED: 44×44 is the default, 28×28 the minimum | developer.apple.com HIG Accessibility (JSON) |
| HIG Playing haptics (optional, consistent, complements other feedback) | OK | HIG Playing haptics (JSON) |
| Material 48 dp / 8 dp / ~9 mm; WCAG 2.2 SCs 2.5.8, 2.5.5, 2.5.1, 2.3.1, 2.2.2, 1.4.1, 1.4.3, 1.4.4, 1.4.11 | OK | web.dev accessible-tap-targets; W3C WCAG 2.2 (from knowledge; the Google support page is blocked) |
| GameAnalytics 2025 (5–6 / 8–9 min, ~4 sessions, ~22 min/day) | OK (secondary); a 2026 edition is noted | gamedevreports / investgame PDF mirror |
| Idle-genre session figures | FLAGGED: no primary source | — |
| Device spec sheets (A13, Redmi Note 11, iPhone 12, Pixel 7a 420 dpi) | OK from knowledge, not re-fetched | — |

**Papers**

| Citation | Verdict | Evidence |
|---|---|---|
| Hoober 2013 (1,333 / 780; 49/36/15 %; 67/33 %) | OK (secondary; the original host is blocked); the 2017 revision caveat was added | Smart Insights, Monterail and other summaries |
| Hoober via Smashing 2023 (7 / 11 / 12 mm) | OK | smashingmagazine.com/2023/04/accessible-tap-target-sizes-rage-taps-clicks |
| Bergstrom-Lehtovirta & Oulasvirta, CHI 2014 | OK (pp. 1991–2000) | KU research portal; bibsonomy |
| Parhi, Karlson & Bederson, MobileHCI 2006 (9.2 / 9.6 mm) | OK | MSR / UMD HCIL pages; dx.doi.org listing |
| Holz & Baudisch, CHI 2010 "tap below and to the side" | FIXED: the paper models per-user and per-posture offsets; tag V → H | christianholz.net project page; dblp |
| Ng et al., UIST 2012 | OK; DOI 10.1145/2380116.2380174 added; thresholds not re-read | dblp; IxDF |
| Jota et al., CHI 2013 | OK (pp. 2291–2300) | unpaywall listing; DGP Toronto |
| Dash & Hu, MobiSys 2021 (3–9 % at 30–50 %, 39–47 % at 100 %) | OK; DOI added | Purdue news release |
| Zagal, Björk & Lewis, FDG 2013 (grinding, playing by appointment, pay to skip, social pyramid) | OK | Chalmers research portal; DiGRA review |
| King et al., 2019, *CHB* 101:131–143 | OK | ORBilu / USyd repositories |
| Fitts 1954; MacKenzie 1992; Birch 2012; Machado et al. 2009 | OK (bibliographic details from knowledge; DOIs not resolvable here) | — |

**Totals:** 74 log rows covering about 110 individual claims, since several rows bundle claims (for example, 9 haptic constants and 9 WCAG criteria). 13 rows FIXED, 2 FLAGGED (particle SDF collision, where docs and source disagree; idle-genre session data), 3 ADDED, the rest OK. Smaller in-text fixes: the `Node.PROCESS_MODE_DISABLED` identifier, the `suppress_ui_gesture` default, the privacy-reason tag V→J, and the thermal-grep nuance. In-text additions: `DPITexture` for SVG UI, and the GLES3 binary shader cache. The body is above the 4,000-word target. Trimming is left to the synthesis step so that no verified content is lost.
