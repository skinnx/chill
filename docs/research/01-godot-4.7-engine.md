# 01 — Godot 4.7.2 engine capabilities for a premium 2D cozy mobile game

*Engine researcher report · 2026-10-20 · engine: `4.7.2-stable` (`/home/user/godotengine/godot`, commit `ed1daf0`)*

**Evidence tags.** **[V]** verified in the 4.7.2 source tree or its doc XML (path:line or symbol given) · **[D]** official Godot docs/release notes (godot-docs `4.7` branch @`9adca4c`, godot-website repo; both cloned via git because godotengine.org is blocked) · **[W]** other web source · **[H]** well-supported heuristic (cited) · **[J]** our judgement. **[E]** = checked empirically by running the 4.7.2 editor binary under Xvfb/llvmpipe (fact-check pass, 2026-10-20; see *Verification log*).

---

## 0. Recommendations (decision table)

| # | Topic | Decision | Conf. | Key evidence |
|---|---|---|---|---|
| R1 | Renderer | **Compatibility (`gl_compatibility`) on Android, iOS and Web.** The project stays Mobile-ready: switching later is a one-line change (§1.4). | High | [D] renderers.rst says Compatibility is "usually good enough for 2D". [V] project_dialog.cpp:522 describes it as "Fastest rendering of simple scenes". |
| R2 | 2D vs 3D | **Layered 2D diorama**: SVG art, `canvas_item` shaders, Polygon2D/`draw_*` geometry, GPUParticles2D, Parallax2D depth. **No 3D.** | High | §2 |
| R3 | Resolution | Base **720×1280**, `canvas_items` + `expand`, portrait (`orientation=1`). | High | [D] multiple_resolutions.rst, "Mobile game in portrait mode" |
| R4 | Art import | World art: SVG imported as Texture2D with `svg/scale=2.0`, `mipmaps/generate=true`, global filter **Linear Mipmap**. `svg/scale` changes the texture's pixel size, so a 2.0 import draws 2× larger: author SVGs at half size or set node `scale = 0.5`. UI icons: **DPITexture** (re-rasterized per scale; the class is marked **experimental**). Never VRAM-compress 2D. | High | [V] ResourceImporterTexture.xml:37 (`compress/mode`: "Only use for textures in 3D scenes, not for 2D elements"), :169-171 (`svg/scale`); DPITexture.xml:2 `experimental=""` |
| R5 | Bloom | No `Environment` glow in v1. Use **additive halo sprites/shaders** for selective glow. Use WorldEnvironment `BG_CANVAS` only for grading. Adjustments and the LUT were already applied in post in Compatibility before 4.7. What 4.7 adds is tonemapping in post for canvas BG, so keep `tonemap_mode = TONE_MAPPER_LINEAR` (default) or the art's colors shift. Grading costs one extra full-screen pass, so measure it. | Med-High | [V] Environment.xml:131-201; CHANGELOG 4.7 GH-113861; 4.6-stable `rasterizer_scene_gles3.cpp:2383-2385` (`apply_color_adjustments_in_post`) vs 4.7.2 :2419 (`canvas_tonemapping`) |
| R6 | Banding | Every gradient shader adds ±0.5 LSB interleaved-gradient-noise dither (uniform). Optional upgrade: triangular-PDF noise (the sum of two uniform samples, ±1 LSB), which keeps noise power uniform. | High | [H] Jimenez 2014 (IGN); Gjøl, "Banding in Games: A Noisy Rant" (Playdead 2014, via secondary sources); Gjøl & Svendsen, GDC Europe 2016 |
| R7 | Motion | Tween first: `TRANS_SPRING`/`TRANS_BACK` + `EASE_OUT`, `set_parallel`, `tween_await` (4.7). Analytic damped springs in `_process` for interactive wobble. Control `offset_transform_*` (4.7) for UI pops. | High | §4 |
| R8 | Shader time | Use a **`global uniform float g_time`** that we wrap at 600 s, with every loop frequency a multiple of 1/600 Hz. This avoids the hourly `TIME` jump. | Med | [V] `rendering/limits/time/time_rollover_secs`=3600 |
| R9 | Frame/power | `max_fps=60`. Drop to 30 after 8 s with no input and when nothing is tweening. `physics_ticks_per_second=30`. `low_processor_mode=false`. `keep_screen_on=false`. | Med | §6 |
| R10 | Save | JSON via `JSON.from_native`. Atomic write: temp file, rename, keep a `.bak`. Save on `NOTIFICATION_APPLICATION_PAUSED`/`FOCUS_OUT`. Offline progress from `Time.get_unix_time_from_system()`, clamped to [0, 12 h]. | High | §7 |
| R11 | Android | `import_etc2_astc=true` (export is **blocked** without it). `quit_on_go_back=false`. Handle `NOTIFICATION_WM_GO_BACK_REQUEST`. Immersive mode plus safe-area layout. `permissions/vibrate=true`. | High | [V] export_plugin.cpp:3148 |
| R12 | Accessibility | The 4.7.2 screen reader (AccessKit) is **desktop-only**, so accessibility on mobile is our job: text scale, reduced motion, contrast, ≥48 dp targets. | High | [V] accesskit only in linuxbsd/macos/windows `detect.py` |
| R13 | Shader warm-up | On the splash screen, draw every material/particle once for ≥1 frame. It must be **inside the viewport rect** (for example behind the opaque splash), with combined `modulate.a ≥ 0.01`. Off-screen items and items with alpha < 0.007 are culled, so they never compile. | High | [D] pipeline_compilations.rst:15-17, :113-115; [V] renderer_canvas_cull.cpp:329 (`modulate.a < 0.007` → return) |
| R14 | QA/CLI | `xvfb-run … --rendering-driver opengl3_es --write-movie /abs/dir/f.png --fixed-fps 30 --quit-after N`. This uses the same rendering method as the shipped game (Compatibility), but on Mesa llvmpipe instead of a phone GPU. `opengl3_es` uses the GLES code path that phones use. The movie size comes from the project settings, not from `--resolution` (§8). | High | §8; [E] |

---

## 1. Renderer choice

### 1.1 What each renderer supports for 2D (Forward+ is excluded)
Forward+ on mobile is "Supported, but poorly optimized. Use Mobile or Compatibility instead" ([D] renderers.rst).

| 2D feature | Compatibility (GLES3/WebGL2) | Mobile (Vulkan/Metal) | Evidence |
|---|---|---|---|
| `canvas_item` vertex/fragment/light shaders, SDF funcs, `instance uniform`, `global uniform` | ✔ | ✔ | [V] servers/rendering/shader_types.cpp:269-363 (shared); shader_language.cpp:9566 |
| Light2D + normal/specular (CanvasTexture), LightOccluder2D shadows | ✔ `max_lights_per_item=16`, but the loop stops at 15, so **15 lights/item** in practice; 64 or 256 lights/render (by UBO size) | ✔ 15/item (same loop), 256/render | [V] rasterizer_canvas_gles3.h:246, rasterizer_canvas_gles3.cpp:860 (`== max_lights_per_item - 1` → break), :2777-2781; renderer_canvas_render_rd.h:108-109, .cpp:2382 |
| `hint_screen_texture` (+mipmap blur), BackBufferCopy, CanvasGroup | ✔ (Gaussian mip chain) | ✔ | [V] rasterizer_canvas_gles3.cpp:414-506; gles3 texture_storage.cpp:3657-3737 |
| 2D glow via WorldEnvironment `BG_CANVAS` | ⚠ simplified: Screen blend only; `glow_levels/*`, `glow_mix`, `glow_map`, `glow_strength`, `glow_normalized` ignored; 2D source clamped to ≤1.0 | ✔ full (Mobile glow rewritten in 4.6) | [V] Environment.xml:131-201; renderer_viewport.cpp:365-371; rasterizer_scene_gles3.cpp:2419,2465 |
| Tonemap/adjustments/color-correction LUT on canvas BG | ✔ Adjustments/LUT in post already in 4.6; **tonemapping** of canvas BG in post is new in 4.7 (GH-113861) | ✔ | [V] CHANGELOG.md:1792; 4.7.2 rasterizer_scene_gles3.cpp:2419-2421; 4.6-stable same file :2383-2385 |
| HDR 2D (`rendering/viewport/hdr_2d`) | ✖ per docs. Source: GLES3 does allocate RGBA16F (texture_storage.cpp:2554) but the GLES3 canvas renderer never reads `render_target_is_using_hdr`, so there is no linear-space 2D | ✔ RGBA16F, linear | [D] renderers.rst; [V] renderer_canvas_render_rd.cpp:672 vs grep of rasterizer_canvas_gles3.cpp |
| MSAA 2D | ✖ | ✔ | [V] ProjectSettings.xml `msaa_2d` note |
| Debanding | ✖ | ✔ | [V] Viewport.xml `use_debanding` |
| GPUParticles2D | ✔. No trails, no SDF collision, no `emit_particle()`, **no sub-emitters**. GPUParticles are **disabled on Adreno 3xx** (driver workaround), so CPUParticles2D is the fallback there | ✔ all | [D] renderers.rst:368-370; [V] GPUParticles2D.xml:41; gles3 particles_storage.cpp:385-393 ("does not support particle sub-emitters"), :124; gles3 config.cpp:223-226 |
| Ubershaders / pipeline precompile / shader baker | ✖. Warm up by drawing once | ✔. But canvas pipelines are **not** precompiled in any renderer | [D] pipeline_compilations.rst; [V] EditorExportPlatformAndroid.xml `shader_baker/enabled` |
| Android frame pacing (Swappy) | ✖ (Swappy lives in drivers/vulkan only) | ✔ `display/window/frame_pacing/android/enable_frame_pacing=true` | [V] grep "swappy": drivers/vulkan/rendering_device_driver_vulkan.cpp |
| 2D render-target precision | RGB10A2 (opaque) / RGBA8 (transparent) per source. The docs table says "RGBA8", and the EGL window surface it is blitted to is normally 8-bit | **RGBA8** (UNORM/sRGB) for 2D unless HDR 2D, then RGBA16F. Docs' "RGB10A2" refers to Mobile's 3D buffers | [V] gles3 texture_storage.cpp:2554-2570; renderer_rd texture_storage.cpp:5285-5290; [D] renderers.rst:352-354 |
| Web export | ✔ (only option) | ✖ | [V] main.cpp:2649 `rendering_method.web` hint = gl_compatibility |

### 1.2 Device reach in 2026
- **Android, Compatibility**: OpenGL ES 3.0. Default `minSdk` is 24 [V] export_plugin.cpp:303, and 4.7 GH-118942 set the Compatibility minSdk to 24. Practically every Play device qualifies.
- **Android, Mobile**: Godot **requires** Vulkan 1.1 (`FEATURE_VULKAN_HARDWARE_VERSION 0x401000`). `FEATURE_VULKAN_HARDWARE_LEVEL ≥1` is only checked for a log warning, not required [V] platform/android/java/lib/src/main/java/org/godotengine/godot/Godot.kt:939-949. Recommended minSdk is 29 [V] export_plugin.cpp:304. The Android dashboard (28 days ending 2025-11-24, fetched directly) reports Vulkan ≥1.1 on **88.8 % of handheld / 87.3 % of all devices**, with 3.9 % on Vulkan 1.0.3 only and 7.4 % handheld / 8.9 % all with no Vulkan. GLES 3.0+ is on ≥99.5 % of handhelds [W]. Devices that fail fall back to Compatibility when `rendering/rendering_device/fallback_to_opengl3=true` [V] display_server_android.cpp:695-712. So a Mobile-renderer build **still has to look right in Compatibility.**
- **iOS**: Mobile renderer uses Metal (`rendering_device/driver.ios="metal"`), needs iOS ≥14 [V] ios/export/export_plugin.cpp:75-79, and the default minimum is iOS 15.0 [V] export_plugin.h:44. Compatibility on iOS is native OpenGL ES 3.0, the only option [V] ProjectSettings `gl_compatibility/driver.ios`. Apple has deprecated OpenGL ES since iOS 12, but it still ships. **Risk, unverified for future iOS releases.**
- Metal shaders **cannot be baked from our Linux editor**: `shader_baker_export_plugin_platform_metal.cpp` is compiled only when `env["metal"]` is set [V] editor/shader/shader_baker/SCsub:12.

### 1.3 Firm recommendation — Compatibility everywhere
1. Godot's own guidance favors it for 2D: "Compatibility is usually good enough for 2D" [D]; "Fastest rendering of simple scenes" [V]; "design for the lowest common denominator… use the Compatibility rendering method for both desktop and mobile" [D] gpu_optimization.rst. A cozy 2D scene is a simple scene.
2. Mobile's 2D extras can be replaced cheaply. HDR glow becomes additive halos (no full-screen glow passes). Debanding becomes dither in our shaders. MSAA 2D becomes analytic AA (`fwidth`/`smoothstep`) plus pre-antialiased SVG rasters and `Polygon2D.antialiased`. Trails become Line2D ribbons.
3. **One visual target** covers Android, iOS, Web and the ~11 % of Android devices that would fall back anyway. Our container renders the same rendering method (Mesa llvmpipe). With `--rendering-driver opengl3_es` it also uses the GLES 3.2 code path that phones use [E], so QA frames closely match what ships. llvmpipe will not reproduce mobile GPU precision or performance [J].
4. Compatibility has the lowest base cost [D] renderers.rst ("Low base cost, but high scaling cost"). We expect that to mean less heat and battery drain in long idle sessions [J, not measured].

**Risks we accept, with mitigations:**
- No Swappy. Device-test frame pacing at 60 fps on 90/120 Hz phones.
- Deprecated GLES on iOS.
- First-draw shader hitches. Mitigated by R13.
- No HDR output (4.7's HDR output is Mobile/Forward+ only [D]).

**Revisit triggers [J]:** p95 frame-time jitter >2 ms on a 120 Hz Android device; App Store/TestFlight problems with GLES; art direction that truly needs HDR bloom.

### 1.4 How to switch later (zero code if we follow §5 rules)
Set `rendering/renderer/rendering_method.mobile="mobile"`, keep `rendering/rendering_device/fallback_to_opengl3=true`, and set export `shader_baker/enabled=true` (Android/Vulkan only from Linux). Per-platform overrides such as `rendering_method.ios` also work: feature-tag overrides are generic [V] core/config/project_settings.cpp:324-338 and 418-433. They are **order-sensitive** (the first matching override in insertion order wins), so verify the result with `RenderingServer.get_current_rendering_method()`.

---

## 2. 2D vs 3D vs hybrid

| Criterion (weight) | Layered 2D (SVG + shaders) | Procedural 3D diorama (CSG/primitives + toon) |
|---|---|---|
| Authorable with no artists (×3) | SVG is text we can write, diff and iterate on. ThorVG 1.0.3 parses gradients, masks, clipPath and `feGaussianBlur` [V] thirdparty/README.md:1086-1089, tvgSvgLoader.cpp:2151,2781 | Primitive/CSG shapes read as "generic low-poly". Good results need sculpted meshes, which we cannot make [J] |
| Look ceiling for cozy (×3) | Soft gradients, painterly shapes, parallax depth, particles. This is the dominant style of the cozy-mobile genre [J] | High only with real modeling, lighting and AA |
| Mobile cost (×2) | Fill-rate bound but predictable | Depth, shadows, MSAA 3D; Compatibility 3D lighting is computed in sRGB space and is "inaccurate" [V] ProjectSettings `rendering_method` |
| Compatibility renderer (×2) | Full 2D feature set | Core 3D only |

**Decision [J]: layered 2D.** Build the 2.5D feel with:
- 6–8 `Parallax2D` layers (`scroll_scale`, `autoscroll` for drifting clouds, `repeat_size`) [V] Parallax2D.xml.
- Atmospheric perspective per layer: tint toward the sky color and lower contrast via a global uniform.
- Y-sorted props.
- Subtle vertex sway.
- Depth-of-field-like softness: sample a lower mip level on far layers, e.g. `textureLod(TEXTURE, UV, 1.5)` (needs mipmaps).

No SubViewport-3D hybrid. Each extra viewport is an extra render target, and tiled GPUs pay for every resolve [D] gpu_optimization.rst "Mobile/tiled renderers".

---

## 3. 4.4 → 4.7 changes that matter (APIs verified in `doc/classes/*.xml`)

| Ver | Feature | Exact API | Our use |
|---|---|---|---|
| 4.4 | Nested tweens | `Tween.tween_subtween(Tween)` (GH-98660) | Reusable "pop" sub-animations |
| 4.4 | Tween ignores `Engine.time_scale` | `Tween.set_ignore_time_scale(bool)` (GH-100735) | UI keeps animating while the world is paused or slowed |
| 4.4 | RD 2D batching; ubershaders | GH-92797, GH-90400 | Matters only if we switch to Mobile |
| 4.5 | FoldableContainer | `FoldableContainer.title` (GH-102346) | Settings/collection panels |
| 4.5 | Stacked label effects | `LabelSettings.add_stacked_outline(index=-1)`, `add_stacked_shadow(index=-1)` (GH-104731) | Soft multi-layer title text |
| 4.5 | Auto-scalable SVG (experimental) | `DPITexture` (`base_scale`, `saturation`, `color_map`, `create_from_string()`), importer `svg` → "DPITexture" (GH-105375, renamed GH-109811) | UI icons, palette swaps via `color_map` |
| 4.5 | Android edge-to-edge | export `screen/edge_to_edge` (GH-107742); `DisplayServer.get_display_safe_area() -> Rect2i`, `get_display_cutouts() -> Rect2[]` | Notch/gesture-bar safe layout |
| 4.5 | Screen reader (AccessKit) | `Control.accessibility_name/description/live` | Desktop only (Windows/macOS/Linux). **Not Web, Android or iOS** in 4.7.2 (R12): AccessKit appears only in those three `detect.py` files, and no Web/Android/iOS accessibility backend exists |
| 4.5 | Shader baker | export `shader_baker/enabled` (Forward+/Mobile only) | n/a under R1 |
| 4.5 | Stencil buffer | `stencil_mode` in **spatial** shaders only [V] shader_types.cpp:261-263 | n/a for 2D |
| 4.5 | 16 KB page Android devices | GH-106358 | Play Store requirement covered |
| 4.6 | Ratio pivot | `Control.pivot_offset_ratio = Vector2(0.5,0.5)` (GH-70646) | Centered scale pops on resizable Controls |
| 4.6 | Glow blended before tonemap, Screen default; Mobile glow rewrite | GH-110671, GH-110077 | Mobile and Compatibility glow differ, another reason to avoid Environment glow |
| 4.6 | Mouse vs keyboard focus separated | GH-110250 | No focus ring after taps |
| 4.7 | **Tweens await signals** | `Tween.tween_await(signal: Signal) -> AwaitTweener`; `AwaitTweener.set_timeout(float)` (GH-79712) | Sequences: "walk to → wait for `arrived` → emote" |
| 4.7 | `Tween.has_tweeners()` | GH-92429 | Avoid empty-tween errors |
| 4.7 | **Control offset transform** | `offset_transform_enabled`, `_position`, `_position_ratio`, `_rotation`, `_scale`, `_pivot`, `_pivot_ratio` (default `Vector2(0.5,0.5)`), `offset_transform_visual_only` (default `true`) (GH-87081) | Animate buttons inside Containers without fighting layout |
| 4.7 | Oversampling follows scale | `CanvasItem.oversampling_with_scale` = `OVERSAMPLING_WITH_SCALE_ENABLED` (GH-119692) | Crisp text/DPITexture on statically scaled items. **Do not** enable on items with tweened scale, since it re-rasterizes every frame [J] |
| 4.7 | Conic gradients | `GradientTexture2D.FILL_CONIC` (=3) (GH-115394) | Sun rays, dial UIs, fake shading |
| 4.7 | DrawableTexture2D (methods experimental) | `setup()`, `blit_rect(rect, source, modulate, mipmap, material)` (GH-105701) | Optional footprint/paint layers |
| 4.7 | TextureRect + AtlasTexture tiling; RichTextLabel `[img height=1em]` | GH-113808, GH-112617 | Atlas-friendly UI; inline icons scale with text |
| 4.7 | Android splash options | export `splash_screen/background_color`, `splash_screen/icon`, `splash_screen/branding_image`, `splash_screen/disable_godot_boot_splash` (GH-114671) | Seamless brand-colored launch |
| 4.7 | Behavior: lines no longer get AA feather | GH-105122 | Draw lines ~1 px thicker than before |
| 4.7 | Accessibility API moved | `AccessibilityServer` singleton (GH-116839) | Use the new names |
| — | Haptics | `Input.vibrate_handheld(duration_ms: int = 500, amplitude: float = -1.0)`. Android needs export `permissions/vibrate`; iOS uses Core Haptics when available [V] drivers/apple_embedded/os_apple_embedded.mm:741-750 | 10–20 ms, amplitude 0.2–0.4 "ticks" [J]; user toggle |
| — | GPUParticles2D | `ParticleProcessMaterial` shapes `EMISSION_SHAPE_POINT/SPHERE/SPHERE_SURFACE/BOX/POINTS/DIRECTED_POINTS/RING`; `turbulence_enabled`, `turbulence_noise_strength/scale/speed`; `GPUParticles2D.amount_ratio`, `sub_emitter`, `preprocess`, `fixed_fps` (default 30), `interpolate` | Fireflies, petals, dust motes. Fade density with `amount_ratio` instead of changing `amount` (which restarts the system). `amount_ratio` does not save GPU cost, since all `amount` particles are still processed. **`sub_emitter` does nothing in Compatibility** (warning only). The docs say turbulence "has a high performance cost on the GPU… consider disabling it when targeting mobile/web", so use at most 1 turbulent system [V] GPUParticles2D.xml:64-71; ParticleProcessMaterial.xml:401 |

---

## 4. Animation toolset

### 4.1 Tween patterns (all [V] Tween.xml / PropertyTweener.xml)
```gdscript
func pop(node: CanvasItem) -> void:
    var t := node.create_tween().set_parallel(true)          # bound to node; auto-killed with it
    t.tween_property(node, "scale", Vector2.ONE, 0.45).from(Vector2(1.18, 0.86)) \
        .set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
    t.tween_property(node, "modulate:a", 1.0, 0.25).from(0.0)
    t.chain().tween_callback(func(): node.emit_signal("popped"))

# Control inside a Container (4.7): animate the visual-only offset, not position
btn.offset_transform_enabled = true
create_tween().tween_property(btn, "offset_transform_scale", Vector2.ONE, 0.3) \
    .from(Vector2(0.92, 0.92)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
```
Also useful:
- `tween_method(callable, from, to, dur)` for shader params, e.g. `func(v): mat.set_shader_parameter("reveal", v)`.
- `set_loops()` for ambient loops.
- `PropertyTweener.set_custom_interpolator(Callable)` for exact cubic-béziers.

**Overshoot of built-in curves** [V] computed from `scene/animation/easing_equations.h`. Godot's Elastic uses a period of `0.3·d`, so these numbers do not depend on duration.

| Trans + `EASE_OUT` | Peak overshoot | at % of duration | Use |
|---|---|---|---|
| `TRANS_BACK` (s = 1.70158) | 10.0 % | 58 % | UI pops, panel arrivals |
| `TRANS_SPRING` | 8.4 % | 58 % | Organic settle (default for "cozy") |
| `TRANS_ELASTIC` | 37.3 % | 13.5 % | Too bouncy. Only for jelly/comic hits |
| `TRANS_SINE/QUAD/CUBIC` | 0 | — | Ambient drifts, fades |

**Durations** [H] Material 3 tokens, verified in Flutter `packages/flutter/lib/src/material/motion.dart`:
- short1–4 = 50/100/150/200 ms
- medium1–4 = 250–400 ms
- long1–4 = 450–600 ms
- extralong1–4 = 700–1000 ms
- easing: `standard = cubic(0.2,0,0,1)`, `emphasizedDecelerate = cubic(0.05,0.7,0.1,1)`

Cozy mapping [J]:
- Press feedback: 100 ms.
- Release pop: 300–450 ms.
- Panel slide: 450–600 ms.
- Ambient loops: 3–12 s periods.
- Nothing that blocks input runs longer than 1 s.

### 4.2 Procedural springs (interactive wobble, drag, squash)
A second-order underdamped system overshoots by `OS = exp(−ζπ/√(1−ζ²))` [H] (Ogata, *Modern Control Engineering*): ζ 0.5 → 16.3 %, 0.6 → 9.5 %, 0.7 → 4.6 %. Recommended: f = 2–4 Hz, ζ = 0.55–0.7.
```gdscript
var x := 1.0; var v := 0.0            # current value / velocity
func spring_step(target: float, dt: float, f := 3.0, zeta := 0.6) -> void:
    var w := TAU * f
    var steps := maxi(1, ceili(dt / 0.008))  # sub-step: stays stable at 30 fps
    var h := dt / steps
    for i in steps:
        v += (-2.0 * zeta * w * v - w * w * (x - target)) * h   # semi-implicit Euler
        x += v * h
```
- **Squash & stretch:** area-preserving 2D scale `Vector2(1.0 / s, s)`, from the constant-volume principle [H] (Thomas & Johnston, *The Illusion of Life*, 1981). Drive `s` from the spring. Stretch along velocity: rotate a parent pivot to `v.angle()` and clamp `s` to 0.85–1.2 [J].
- **Frame-rate-independent smoothing:** `pos = pos.lerp(target, 1.0 - exp(-k * delta))` with k ≈ 8–12 s⁻¹. This is the exact per-step solution of dx/dt = k·(target − x) for a constant target, so the result does not depend on the frame rate (math). The k range is [J].
- Run springs in `_process` (render rate). Leave `physics_interpolation` off (R9) so `_process`-driven transforms are not interpolated against physics ticks.

### 4.3 Other tools
- **AnimationPlayer** (inherits `AnimationMixer`: `callback_mode_process` default Idle; `play_section*()` for looping sub-ranges) [V]. Use it for authored, multi-property loops such as breathing creatures and blinking lanterns.
- **AnimationTree**: only for character state machines. 4.7 replaced BlendSpace `sync` with `sync_mode` [D] upgrading_to_godot_4.7.rst.
- **Skeleton2D/Bone2D + Polygon2D** (with `internal_vertex_count`) for soft creature deformation. `SkeletonModification2D*` is **experimental** [V] (`experimental=""`), so avoid it. The 4.6 IK framework is 3D-only [D].
- **Path2D/PathFollow2D**: tween `progress_ratio` with `loop=true`, `cubic_interp=true` for drifting koi, birds and leaves [V].

---

## 5. Shaders for cozy visuals

**Capabilities [V]**
- `canvas_item` built-ins: `VERTEX`, `UV`, `COLOR`, `TIME`, `MODEL_MATRIX`, `CANVAS_MATRIX`, `SCREEN_UV`, `FRAGCOORD`, `TEXTURE_PIXEL_SIZE`, `INSTANCE_CUSTOM`, `NORMAL_MAP`, `light()` with `LIGHT_COLOR/ENERGY/DIRECTION`, plus `texture_sdf()`/`screen_uv_to_sdf()`.
- Render modes: `blend_mix|add|sub|mul|premul_alpha|disabled`, `unshaded`, `light_only`, `skip_vertex_transform`, `world_vertex_coords` (shader_types.cpp:359-363).
- **`instance uniform` works in canvas_item** (shader_language.cpp:9566). One material can serve many sprites through `CanvasItem.set_instance_shader_parameter()`, which preserves batching.
- **Global uniforms** go in project.godot under `[shader_globals]` as `name={"type":"float","value":0.0}`. Godot parses keys `type`/`value` (renderer_rd material_storage.cpp:1948-1951; gles3 material_storage.cpp:2014). Set them at runtime with `RenderingServer.global_shader_parameter_set()`. A `"color"` global is declared in the shader as `global uniform vec4` (rendering_server.cpp:1855-1856). With Compatibility, most mobile devices and all Web exports are capped at **1024** slots [V] ProjectSettings.xml:3203.

**Precision [V]:** GLES3 prepends `precision highp float; precision highp int;` (drivers/gles3/shader_gles3.cpp:219-220), so `mediump` must be written explicitly. Use it only for colors. **Never** use it for `TIME` or UV math: fp16 has ~2-unit steps near 3000, so time-based animation collapses.

**Recipes** (each is a few ALU ops plus 1–2 texture reads):
```glsl
shader_type canvas_item;              // wind sway (needs vertices: Polygon2D with internal verts, or
global uniform float g_time;          // MeshInstance2D+QuadMesh subdivide_depth=8; a Sprite2D quad has only 4 verts → shear only)
global uniform float g_wind;          // 0..1
uniform float amp_px = 6.0; uniform float freq_hz = 0.35;   // 0.35 = 210/600 → loops cleanly at 600 s
void vertex() {
    float h = 1.0 - UV.y;   // 0 at root, 1 at tip for Sprite2D/Polygon2D (UV.y=0 at top).
                            // QuadMesh in MeshInstance2D is V-FLIPPED (UV.y=1 at screen top, texture upside down):
                            // there use h = UV.y, or set the node's scale.y = -1 [E][V] primitive_meshes.cpp:1466-1477
    float ph = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).x * 0.004;  // world-x phase offset
    float t = g_time * TAU * freq_hz + ph;
    VERTEX.x += (sin(t) + 0.35 * sin(2.13 * t + 1.7)) * amp_px * g_wind * h * h;
}
```
```glsl
// gradient sky + debanding dither (IGN, Jimenez 2014)
global uniform vec4 g_sky_top; global uniform vec4 g_sky_bottom;
float ign(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }
void fragment() {
    vec3 c = mix(g_sky_bottom.rgb, g_sky_top.rgb, smoothstep(0.0, 1.0, 1.0 - UV.y));
    COLOR = vec4(c + (ign(FRAGCOORD.xy) - 0.5) / 255.0, 1.0);
}
```
More recipes:
- **Soft drop shadow:** sample `textureLod(TEXTURE, UV - off, 2.5).a` (requires mipmaps). Composite under the sprite, or use a separate blurred, darkened copy node.
- **Outline:** take the max of 8 alpha taps at `TEXTURE_PIXEL_SIZE * w`. Use it only on hero objects.
- **Dissolve/reveal:** `step(noise, u_reveal)` with a `smoothstep` edge band × an HDR-looking warm tint. Drive `u_reveal` with `tween_method`.
- **Water:** scroll two normal-ish noise samples for UV offset, plus a fresnel-like vertical gradient. Use `hint_screen_texture` refraction only on one bounded water rect with `filter_linear_mipmap`.
- **Grain/"fuzzy" film:** IGN or hash noise at amplitude 0.01–0.02, animated by `floor(g_time*12.0)`.
- **Time of day:** one `g_day` (0..1) global drives sky colors, layer tints and `CanvasModulate` (or a WorldEnvironment `adjustment_color_correction` LUT, see R5 for its cost).
- The sky and wind recipes above compile and run in 4.7.2 Compatibility on both `opengl3` and `opengl3_es` [E].

**Mobile performance rules**
- **[D]** Fill rate and overdraw dominate on tiled GPUs. Transparent overlaps are "particularly bad"; keep transparent areas small (gpu_optimization.rst).
- **[J]** Budget: ≤3 full-screen alpha layers; opaque sky bottom layer with `blend_disabled` if it is fully opaque.
- **[D]** Each `hint_screen_texture`/BackBufferCopy forces a copy, and results that depend on earlier operations are slow on tilers. Limit to ≤1 per frame, bounded with a `BackBufferCopy.rect`.
- **[J]** Shadowed Light2Ds: ≤1–2. Prefer baked gradients plus additive "light cookie" sprites. The shadow atlas defaults to 2048 (`rendering/2d/shadow_atlas/size`).
- **[D]** Texture reads are the main fragment cost. Move per-object work to `vertex()`; prefer math noise over noise textures for small effects.

---

## 6. Project settings (keys verified in 4.7.2 source)

```ini
config_version=5

[application]
config/name="Chill"
config/features=PackedStringArray("4.7", "GL Compatibility")
run/main_scene="res://scenes/main.tscn"
config/quit_on_go_back=false              ; handle NOTIFICATION_WM_GO_BACK_REQUEST ourselves
run/max_fps=60                            ; drop to 30 at runtime via Engine.max_fps when idle
boot_splash/bg_color=Color(0.96, 0.92, 0.86, 1)

[display]
window/size/viewport_width=720
window/size/viewport_height=1280
window/size/window_width_override=405     ; desktop preview only (ignored on mobile/web)
window/size/window_height_override=720
window/size/window_width_override.movie=720    ; Movie Maker records at the override size (main.cpp:4841-4853);
window/size/window_height_override.movie=1280  ; "movie" feature tag is active while writing (os.cpp:477) [E]
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/handheld/orientation=1             ; SCREEN_PORTRAIT (5 = SENSOR_PORTRAIT)
window/energy_saving/keep_screen_on=false

[physics]
common/physics_ticks_per_second=30        ; no physics gameplay; halves tick CPU

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/canvas_textures/default_texture_filter=2    ; Linear Mipmap (0 Nearest,1 Linear,2 Linear Mipmap,3 Nearest Mipmap)
textures/vram_compression/import_etc2_astc=true      ; Android/iOS export is refused without it
environment/defaults/default_clear_color=Color(0.96, 0.92, 0.86, 1)

[shader_globals]
g_time={"type":"float","value":0.0}
g_day={"type":"float","value":0.35}
g_wind={"type":"float","value":0.5}
g_sky_top={"type":"color","value":Color(0.55, 0.72, 0.93, 1)}
g_sky_bottom={"type":"color","value":Color(0.99, 0.86, 0.78, 1)}
```
(`color` is one of the global types listed in gles3 material_storage.cpp:2023-2058.)

| Key (default) | Value | Source of truth |
|---|---|---|
| `display/window/handheld/orientation` (0 landscape) | 1 | main.cpp:2836; enum servers/display/display_server_enums.h:165 |
| `display/window/stretch/mode`/`aspect` ("disabled"/"keep") | canvas_items/expand | core/config/project_settings.cpp:1787-1788 |
| `display/window/size/viewport_width/height` (1152×648) | 720×1280 | project_settings.cpp:1719 |
| `rendering/renderer/rendering_method.mobile` ("mobile") | gl_compatibility | main.cpp:2648; project_dialog.cpp:587-589 does the same for Compatibility projects |
| `rendering/textures/vram_compression/import_etc2_astc` (false) | true | rendering_server.cpp:3660; android export_plugin.cpp:3148; editor_export_platform_apple_embedded.cpp:2293 |
| `rendering/textures/canvas_textures/default_texture_filter` (1) | 2 | project_settings.cpp:1844 |
| `application/run/max_fps` (0) | 60 | main.cpp:2255 |
| `application/run/low_processor_mode` (false) | keep false. It only skips redraws when nothing changed, and any visible canvas shader that reads built-in `TIME` requests a redraw every frame. Our always-animated scene would gain nothing, apart from the sleep (`low_processor_mode_sleep_usec`=6900) adding jitter. (`TIME` shaders do **not** freeze.) | main.cpp:2263; rasterizer_canvas_gles3.cpp:442-443, 563-565 (`redraw_request()`); ProjectSettings.xml:411-415 |
| `physics/common/physics_ticks_per_second` (60) | 30 | main.cpp:2252 |
| `physics/common/physics_interpolation` (false) | keep false | scene_tree.cpp:2090 |
| `rendering/2d/snap/snap_2d_transforms_to_pixel` (false) | keep false (smooth sub-pixel drift) | scene_tree.cpp:2140 |
| `gui/common/snap_controls_to_pixels` (true) | keep true (crisp text) | project_settings.cpp:1819 |
| `rendering/anti_aliasing/quality/msaa_2d` (0) | 0. No effect in Compatibility | rendering_server.cpp:3742 |
| `rendering/viewport/hdr_2d` (false) | false. Not supported in Compatibility | rendering_server.cpp:3740 |
| `rendering/limits/time/time_rollover_secs` (3600) | keep. We use `g_time` instead | rendering_server.cpp:3669 |
| `display/window/energy_saving/keep_screen_on` (true) | false | project_settings.cpp:1745 |
| `display/window/vsync/vsync_mode` (1 Enabled) | keep. Adaptive/Mailbox behave like Enabled in Compatibility | main.cpp:2839; DisplayServer.xml:3433,3437 |

**Anisotropic filtering** (`rendering/textures/default_filters/anisotropic_filtering_level`, default 2) applies only to the `*_ANISOTROPIC` filter modes. CanvasItem has such modes (values 5 and 6), but its docs call them "rarely useful in 2D", and our default filter (2 = Linear Mipmap) does not use it, so it does not matter here [V] CanvasItem.xml:783-789.

**Export presets** [V] EditorExportPlatformAndroid.xml:
- Android: `screen/immersive_mode=true` (default), `screen/edge_to_edge=false` (immersive already covers the whole screen; still lay out inside `get_display_safe_area()`), `permissions/vibrate=true`, `architectures/arm64-v8a=true`, `splash_screen/*`.
- Android 15 makes apps targeting SDK 35 edge-to-edge by default. For targetSdk 36 on Android 16, the `windowOptOutEdgeToEdgeEnforcement` opt-out is "deprecated and disabled" [W] developer.android.com/about/versions/15/behavior-changes-15, /16/behavior-changes-16. Godot's default targetSdk is 36 [V] export_plugin.cpp:305. Since 4.5, immersive mode no longer excludes the display cutout (GH-108205). So safe-area handling is mandatory.
- **Safe area to canvas units:** `var k := get_viewport().get_visible_rect().size / Vector2(get_window().size)`, then multiply the safe-area rect by `k` [J].

---

## 7. Data, save and app lifecycle

- **`user://`** maps to a sandboxed app directory on Android/iOS [V] OS.xml `get_user_data_dir`. On Android it resolves through `GodotIO.get_user_data_dir` [V] os_android.cpp:741-751.
- **Format:**
  - `JSON.stringify(JSON.from_native(data))` / `JSON.to_native(JSON.parse_string(s))`. Objects are off by default (`from_native(variant, full_objects=false)`, `to_native(json, allow_objects=false)`), so the format is type-preserving for Vector2/Color and safe [V] JSON.xml:40-46, 141-151. Round-trip of a Vector2 and a Color tested [E].
  - `ConfigFile` for settings.
  - **Avoid** `get_var(true)` / `bytes_to_var_with_objects`. The docs warn that deserialized objects "can contain code which gets executed" [V] FileAccess.xml:346, @GlobalScope.xml:192.
  - Avoid loading `.tres` from `user://` for the same reason [J].
- **Atomic write:** `FileAccess.open("user://save.tmp", WRITE)` → `store_string()` (returns `bool` [V]) → `close()` → `DirAccess.rename_absolute(tmp, "user://save.json")`, after copying the previous file to `save.bak` [J].
- **Lifecycle** [V] Node.xml constants:
  - `NOTIFICATION_APPLICATION_PAUSED` (2015): Android/iOS. **iOS allows ~5 s** before it kills the app, so save synchronously and keep the save small.
  - `NOTIFICATION_APPLICATION_RESUMED` (2014): recompute offline progress.
  - `NOTIFICATION_APPLICATION_FOCUS_OUT/IN` (2017/2016): desktop+mobile. Pause audio and drop to 10–30 fps.
  - `NOTIFICATION_WM_GO_BACK_REQUEST` (1007): Android only. Close the top panel, or show "exit?" at root.
  - `NOTIFICATION_OS_MEMORY_WARNING` (2009): iOS. Free caches.
- **Offline progress:** `Time.get_unix_time_from_system() -> float` returns UTC seconds from the system clock, which the user can change [V] Time.xml. Use `delta = clamp(now - saved_at, 0.0, 12.0 * 3600.0)`. Treat negative delta (clock rollback) as 0. Use `Time.get_ticks_msec()` (monotonic) for in-session timing [V]. Generous caps fit a "chill" contract: no punishment for being away [J].

---

## 8. Headless / CLI (verified in `main/main.cpp` help, lines 554-733)

| Task | Command |
|---|---|
| Import assets (CI, first run) | `godot --headless --path /home/user/chill --import` (sets editor mode, waits for import, quits; main.cpp:1683-1687) |
| Parse-check a script | `godot --headless --path . --check-only --script res://tools/x.gd` |
| Run a scene | `godot --path . --scene res://scenes/main.tscn` (path or UID) |
| Force renderer | `--rendering-method gl_compatibility --rendering-driver opengl3` (desktop GL 4.5 core on llvmpipe) or `--rendering-driver opengl3_es` (GLES 3.2 on llvmpipe, the closest to phones; display_server_x11.cpp:6327) [E]. Use `mobile` + `vulkan` to test lavapipe |
| Display/audio | `--display-driver x11` (or `headless`, which implies the Dummy renderer with **no pixels**); `--audio-driver Dummy` |
| Window | `--resolution 720x1280`, `--windowed`, `--position 0,0` |
| Video/screenshots | `mkdir -p /tmp/claude-research/qa && xvfb-run -a -s "-screen 0 1440x2560x24" godot --path . --rendering-driver opengl3_es --fixed-fps 30 --write-movie /tmp/claude-research/qa/f.png --quit-after 300 --scene res://scenes/main.tscn` (tested [E]: 720×1280 frames with the `.movie` overrides of §6) |
| Export | `--export-release "<preset>" build/game.apk`, `--export-debug`, `--export-pack <preset> x.pck/.zip`, `--export-patch`, `--patches a,b`, `--install-android-build-template` |
| Misc | `--max-fps`, `--time-scale`, `--disable-vsync`, `--print-fps`, `--debug-canvas-item-redraw`, `--quit-after N`, `--log-file`, `-- <user args>` (read with `OS.get_cmdline_user_args()`) |

Notes on `--write-movie` [V]:
- **The frame size ignores `--resolution`.** It is `viewport_width/height`, replaced by `window_width/height_override` when the stretch mode is not `viewport` (main.cpp:4841-4853). With our 405×720 preview override, plain captures come out **405×720** [E]. Fix: the `.movie` overrides in §6.
- The output directory must already exist (the writer does not create it). A relative path is resolved against the project directory, not the shell's working directory [E]. Use absolute paths.
- It defaults to 60 fps unless `--fixed-fps` is given (main.cpp:1961-1966).
- It **always forces the Dummy audio driver** and records the mix to WAV (main.cpp:2829-2832).
- `.png` output is written as `f00000000.png…` (8-digit index) plus `f.wav` (movie_writer_pngwav.h:39). `.avi` (MJPEG) and `.ogv` (Theora, editor builds) also work.
- `--headless` cannot capture frames, so use Xvfb.

**Export templates** live in `$XDG_DATA_HOME/godot/export_templates/4.7.2.stable/` (default `~/.local/share/…`) [V] export_template_manager.cpp:1401. GitHub release assets **are** reachable from this container, contrary to the original brief. `https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/SHA512-SUMS.txt` returns 302 to `release-assets.githubusercontent.com` [E]. `android_debug.apk`, `web_nothreads_{debug,release}.zip` and `version.txt` (`4.7.2.stable`) are already in `/tmp/claude-research/xdg/data/godot/export_templates/4.7.2.stable/` [E]. The ranged fetch method and checksums are in 03-tooling-plugins-pipeline.md. Compiling templates from source is **not** required.

---

## Sources
- Engine source `4.7.2-stable`: files cited inline; `CHANGELOG.md` (4.7.x); 4.4/4.5/4.6 `CHANGELOG.md` via sparse `git clone --branch 4.x-stable`.
- Release notes (godotengine/godot-website repo): `_data/release_4_7/features.yml`, `_data/release_4_6/features.yml`, `collections/_release_4_5/*.md`. These mirror https://godotengine.org/releases/4.7/, /4.6/ and /4.5/.
- godot-docs `4.7` branch: `tutorials/rendering/renderers.rst`, `multiple_resolutions.rst`, `tutorials/performance/gpu_optimization.rst`, `pipeline_compilations.rst`, `tutorials/migrating/upgrading_to_godot_4.6.rst` / `4.7.rst`, `tutorials/io/saving_games.rst`. Online at https://docs.godotengine.org/en/4.7/.
- Android distribution dashboard (Vulkan/GLES versions, 28 days ending 2025-11-24; fetched directly 2026-10-20): https://developer.android.com/about/dashboards. Android 10+ ≈90.8 % (data of 2025-12-01; the site is unreachable from here, so this is the sum of 83.0 % for Android 11+ and 7.8 % for Android 10, as quoted by search results): https://heise.de/-11162154.
- Android 15/16 edge-to-edge: https://developer.android.com/about/versions/15/behavior-changes-15 · https://developer.android.com/about/versions/16/behavior-changes-16
- Material 3 motion tokens: Flutter `packages/flutter/lib/src/material/motion.dart`; spec https://m3.material.io/styles/motion/easing-and-duration
- J. Jimenez, "Next Generation Post Processing in Call of Duty: Advanced Warfare", SIGGRAPH 2014 (interleaved gradient noise).
- M. Gjøl & M. Svendsen, "Low Complexity, High Fidelity: INSIDE Rendering", GDC **Europe** 2016, Cologne (dithering against banding; GDC Vault 1023002, slides behind a login).
- M. Gjøl, "Banding in Games: A Noisy Rant", Playdead, 2014 (triangular-PDF dither). Known via B. Wronski, "Dithering part three", 2016 (https://bartwronski.com/2016/10/30/dithering-part-three-real-world-2d-quantization-dithering/) and Blender commit 852cdd476b5, 2020. Original slides not fetched.
- K. Ogata, *Modern Control Engineering*, 5th ed., §5 (second-order overshoot).
- F. Thomas & O. Johnston, *The Illusion of Life: Disney Animation*, 1981 (squash & stretch).

---

## Verification log

*Adversarial fact-check, 2026-10-20.* Sources used: the engine tree `4.7.2-stable` @`ed1daf0`; godot-docs branch `4.7` @`9adca4c` (the original author had cloned `master`; quotes re-checked on `4.7`); a sparse 4.6-stable clone and the 4.4/4.5/4.6 CHANGELOGs for "since" claims; web fetches. **[E]** runs used `bin/godot.linuxbsd.editor.x86_64` (4.7.2.stable.custom_build.ed1daf0bf) with a test project at `/tmp/claude-verify-engine/proj*`. That project used the §6 settings plus the §4.1, §4.2 and §5 code verbatim. Both `opengl3` (GL 4.5 core) and `opengl3_es` (GLES 3.2) ran on llvmpipe. Paths in this table are relative to the engine root unless noted.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | "Fastest rendering of simple scenes" (Compatibility) | OK | editor/project_manager/project_dialog.cpp:522 |
| 2 | renderers.rst: Compat "usually good enough for 2D"; Forward+ on mobile "poorly optimized" | OK | docs47 tutorials/rendering/renderers.rst:151-163 |
| 3 | gpu_optimization.rst "lowest common denominator… Compatibility for both" | OK | docs47 gpu_optimization.rst:272-275 |
| 4 | Portrait 720×1280 + canvas_items + expand | OK | docs47 multiple_resolutions.rst:465-484 |
| 5 | canvas_item built-ins / render modes / SDF funcs | OK | servers/rendering/shader_types.cpp:269-363 |
| 6 | `instance uniform` allowed in canvas_item; keeps batching | OK | shader_language.cpp:9566; batches split only on material change, instance offset per instance: renderer_canvas_render_rd.cpp:2223, 2358 |
| 7 | 16 lights per item | **FIXED** → 15 in practice | rasterizer_canvas_gles3.cpp:860; renderer_canvas_render_rd.cpp:2382 |
| 8 | Screen-texture Gaussian mip chain (GLES3) | OK | gles3 texture_storage.cpp:3687, 3737 |
| 9 | Compatibility glow limits (Screen blend only, levels/mix/map/strength/normalized ignored) | OK | doc/classes/Environment.xml:131-201 |
| 10 | Canvas-BG tonemap/adjustments/LUT "new in 4.7" | **FIXED** → only tonemap-in-post is new | 4.6-stable rasterizer_scene_gles3.cpp:2383-2385 vs 4.7.2 :2419-2421; CHANGELOG.md:1792 |
| 11 | No HDR 2D in Compatibility; RD canvas reads `render_target_is_using_hdr` | OK | renderer_canvas_render_rd.cpp:672; no `using_hdr` in rasterizer_canvas_gles3.cpp |
| 12 | MSAA 2D / debanding Mobile+Forward+ only | OK | ProjectSettings.xml:2861; Viewport.xml:466-467 |
| 13 | GPUParticles2D Compat limits | **FIXED**: added no sub-emitters and Adreno 3xx disable | gles3 particles_storage.cpp:124, 385-393; gles3 config.cpp:223-226 |
| 14 | Turbulence suggested for fireflies | **FIXED**: added the docs' mobile cost warning | ParticleProcessMaterial.xml:401 |
| 15 | Canvas pipelines never precompiled; Compat warm-up = draw once | OK | docs47 pipeline_compilations.rst:8-17, 113-115 |
| 16 | Warm-up "off-screen or at alpha 0.01" | **FIXED**: off-screen items are culled, alpha threshold 0.007 | servers/rendering/renderer_canvas_cull.cpp:329 |
| 17 | Swappy only in Vulkan driver; `enable_frame_pacing` default true | OK | drivers/vulkan/rendering_device_driver_vulkan.cpp:1874; core/config/project_settings.cpp:1771 |
| 18 | Mobile 2D framebuffer "RGB10A2" | **FIXED** → RGBA8 unless HDR 2D | renderer_rd/storage_rd/texture_storage.cpp:5285-5290 |
| 19 | Compat 2D RT RGB10A2 opaque / RGBA8 transparent | OK (docs table says RGBA8; noted) | gles3 texture_storage.cpp:2554-2570 |
| 20 | Web: `rendering_method.web` = gl_compatibility only | OK | main/main.cpp:2649 |
| 21 | Android minSdk 24 / Vulkan 29 / targetSdk 36; GH-118942 | OK | platform/android/export/export_plugin.cpp:303-305; CHANGELOG.md:937 |
| 22 | Vulkan "requires HARDWARE_LEVEL ≥1 and 1.1" | **FIXED** → only 1.1 required; level is a warning | platform/android/java/lib/src/main/java/org/godotengine/godot/Godot.kt:939-949 |
| 23 | Vulkan share ≈87 % / 89 %, no-Vulkan 8.9 % | OK (now fetched directly, exact numbers added) | https://developer.android.com/about/dashboards (28 d ending 2025-11-24) |
| 24 | Android 10+ ≈90.8 % | **FLAGGED** (heise unreachable; number reconstructed from search snippets) | https://heise.de/-11162154 |
| 25 | Fallback to GLES3 when Vulkan init fails; default true | OK | platform/android/display_server_android.cpp:695-712; main.cpp:2398 |
| 26 | iOS Metal needs ≥14, default min 15.0, GL on iOS = native EAGL GLES3 | OK | platform/ios/export/export_plugin.cpp:73-79; export_plugin.h:44; platform/ios/display_layer_ios.mm:97 |
| 27 | Metal shader baker not buildable on Linux | OK | editor/shader/shader_baker/SCsub:12; SConstruct:200 ("Apple arm64 only") |
| 28 | Feature-tag overrides generic, first match wins | OK | core/config/project_settings.cpp:323-338, 418-433 |
| 29 | ThorVG 1.0.3; gradients/mask/clipPath/feGaussianBlur | OK | thirdparty/README.md:1086-1089; tvgSvgLoader.cpp:1164-1165, 2151; sw_engine/tvgSwPostEffect.cpp present |
| 30 | 4.4–4.6 PR numbers (98660, 100735, 92797, 90400, 102346, 104731, 105375, 109811, 107742, 106358, 70646, 110671, 110077, 110250) | OK | g4.4/g4.5/g4.6 CHANGELOG.md (e.g. 4.4:265, 4.5:1575, 4.6:1804) |
| 31 | 4.7 PR numbers (113861, 118942, 92429, 87081, 119692, 115394, 105701, 113808, 112617, 114671, 105122, 116839) | OK | CHANGELOG.md:415-1867 |
| 32 | `tween_await` GH-79712 is new in 4.7 | OK (not in CHANGELOG; in release data; class absent in 4.6) | godot-website `_data/release_4_7/features.yml:151-156`; 4.6-stable has no AwaitTweener.xml |
| 33 | API names/signatures/defaults in §3 (AwaitTweener.set_timeout, tween_subtween, set_ignore_time_scale, has_tweeners, offset_transform_* defaults, pivot_offset_ratio, oversampling_with_scale enum, FILL_CONIC=3, DrawableTexture2D.setup/blit_rect, add_stacked_*, FoldableContainer.title, DPITexture members, safe-area return types, AccessibilityServer, RTL `[img height=…em]`) | OK | doc/classes/*.xml (e.g. Control.xml:1161-1201, CanvasItem.xml:671, 821-829, DrawableTexture2D.xml:12-67); rich_text_label.cpp:6334-6347 |
| 34 | AccessKit "Desktop/Web" | **FIXED** → desktop only | platform/{linuxbsd,macos,windows}/detect.py only; nothing in platform/web |
| 35 | Line AA feather removal (GH-105122) | OK | docs47 upgrading_to_godot_4.7.rst:206-208 |
| 36 | BlendSpace `sync` → `sync_mode` | OK | AnimationNodeBlendSpace1D.xml:116-119 |
| 37 | `vibrate_handheld(500, -1.0)`; iOS Core Haptics; Android VIBRATE permission | OK | Input.xml:807-815; drivers/apple_embedded/os_apple_embedded.mm:741-750 |
| 38 | GPUParticles2D defaults (fixed_fps 30, interpolate true, amount restart, amount_ratio) | OK | GPUParticles2D.xml:64-71, 87, 97 |
| 39 | §4.1/§4.2 GDScript (pop, offset tween, spring) and tween_await | OK [E] | test run printed POPPED, AWAITED; spring converged (x≈-3e-6 after 30 frames) |
| 40 | Overshoot Back 10.0 % @58 %, Spring 8.4 % @58 %, Elastic 37.3 % @13.5 % | OK (recomputed numerically) | scene/animation/easing_equations.h:229-243, 389-394, 418-423 |
| 41 | Material 3 duration/easing tokens | OK | flutter packages/flutter/lib/src/material/motion.dart:28-208 |
| 42 | Ogata OS formula; ζ 0.5/0.6/0.7 → 16.3/9.5/4.6 % | OK (recomputed) | Ogata, *Modern Control Engineering* 5th ed., ch. 5 |
| 43 | AnimationMixer `callback_mode_process` default Idle; `play_section*` | OK | AnimationMixer.xml:305, 376; AnimationPlayer.xml:142-179 |
| 44 | SkeletonModification2D experimental; 4.6 IK is 3D-only | OK | SkeletonModification2D.xml:2; release_4_6 "IKModifier3D" family |
| 45 | Wind shader `h = 1 - UV.y` on QuadMesh | **FIXED**: QuadMesh in MeshInstance2D is V-flipped | [E] UV.y=0.95 at top, 0.04 at bottom; scene/resources/3d/primitive_meshes.cpp:1466-1477 |
| 46 | GLES3 prepends `precision highp`; fp16 step 2 near 3000 | OK | drivers/gles3/shader_gles3.cpp:219-220; IEEE half: 10-bit mantissa, 2048-4096 step 2 |
| 47 | IGN constants (Jimenez 2014) | OK (several secondary reproductions; slides not fetched) | demofox 2022 IGN post; frost.kiwi |
| 48 | Gjøl & Svendsen "GDC 2016"; ±0.5 LSB attributed to them | **FIXED** venue (GDC Europe 2016); TPDF note added | gdcvault.com/play/1023002 |
| 49 | Gjøl 2014 TPDF recommendation | **FLAGGED** (secondary only) | Wronski 2016; Blender commit 852cdd476b5 |
| 50 | Global uniforms `[shader_globals]` format; color → vec4; 1024 Compat cap | OK [E] (shaders compiled) | gles3 material_storage.cpp:2014-2058; rendering_server.cpp:1855; ProjectSettings.xml:3203 |
| 51 | Shadow atlas 2048 default | OK | servers/rendering/rendering_server.cpp:3683 |
| 52 | Settings defaults table (orientation 0, stretch disabled/keep, 1152×648, etc2_astc false, texture filter enum 2 = Linear Mipmap, max_fps 0, ticks 60, interpolation false, snap flags, msaa_2d 0, hdr_2d false, rollover 3600, keep_screen_on true) | OK | main.cpp:2252-2263, 2836; project_settings.cpp:1719-1844; rendering_server.cpp:3660-3742; scene_tree.cpp:2090, 2140 |
| 53 | low_processor_mode makes "TIME shaders freeze" | **FIXED**: TIME shaders force redraws | rasterizer_canvas_gles3.cpp:442-443, 563-565 |
| 54 | Anisotropic "applies only to 3D" | **FIXED** (CanvasItem has `*_ANISOTROPIC` modes) | CanvasItem.xml:783-789 |
| 55 | Vsync evidence "ProjectSettings.xml" | **FIXED** source | DisplayServer.xml:3433, 3437 |
| 56 | Window override ignored on mobile/Web | OK | ProjectSettings.xml:1077 |
| 57 | QA `--resolution 720x1280` sets capture size | **FIXED**: the movie uses the override size; `.movie` tag fix tested | main.cpp:4841-4853; core/os/os.cpp:477; [E] 405×720 without, 720×1280 with the fix |
| 58 | `--write-movie` details (60 fps default, Dummy audio, 8-digit PNG + WAV, .ogv editor-only, .avi via modules/jpg) | OK [E]; added: output dir must exist, relative path resolves against the project | main.cpp:1961-1966, 2829-2832; movie_writer_pngwav.h:39; modules/theora/register_types.cpp:43-55 |
| 59 | QA renderer "same as ships" | **FIXED**: recommend `opengl3_es` | display_server_x11.cpp:6327; [E] "OpenGL ES 3.2 Mesa 25.2.8 - Compatibility" |
| 60 | ETC2/ASTC required for Android/iOS export | OK | export_plugin.cpp:3148; editor_export_platform_apple_embedded.cpp:2293; resource_importer_texture_settings.cpp:47-53 |
| 61 | Android export defaults (immersive true, edge_to_edge false, splash_screen/*) | OK | export_plugin.cpp:2262-2263; EditorExportPlatformAndroid.xml:602-637 |
| 62 | Android 15 edge-to-edge for target 35 | OK; Android 16 no-opt-out added | developer.android.com …/15/behavior-changes-15, …/16/behavior-changes-16 |
| 63 | 16 KB page support covers the Play requirement | OK | CHANGELOG 4.5 GH-106358 (NDK r28b); Play rule from 2025-11-01 per heise -10378155 / 9to5google |
| 64 | `user://` sandboxed on Android/iOS | OK | OS.xml:587; platform/android/os_android.cpp:741-751 |
| 65 | `JSON.from_native(…, allow_objects)` | **FIXED** → param is `full_objects` | JSON.xml:40-46 |
| 66 | get_var / bytes_to_var_with_objects warnings; store_string → bool; rename_absolute | OK | FileAccess.xml:346, 622-623; @GlobalScope.xml:192; DirAccess.xml:368 |
| 67 | Notification values; iOS ~5 s on PAUSED | OK | Node.xml:1260-1326 |
| 68 | Time APIs | OK | Time.xml:108-113, 180-185 |
| 69 | CLI flags list; `--import` behavior; `--headless` | OK [E] | main.cpp:573-708, 1505-1508, 1683-1687 |
| 70 | Templates "cannot download; must compile" | **FIXED**: downloadable and already fetched | [E] HTTP 302 to release-assets; `/tmp/claude-research/xdg/data/godot/export_templates/4.7.2.stable/` |
| 71 | `svg/scale` / DPITexture | **FIXED** (clarified 2× draw size; DPITexture experimental) | ResourceImporterTexture.xml:169-171; DPITexture.xml:2 |
| 72 | Oversampling re-rasterizes every frame under tweened scale | **FLAGGED** ([J], not measured) | — |

**Totals:** 72 rows covering ≈130 individual facts. **OK 51 · FIXED 18 · FLAGGED 3.** No addon claims were in scope; the report recommends no plugins.
