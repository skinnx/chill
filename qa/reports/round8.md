# Round 8 — Feel & Return: engine verification and regression notes

*2026-10-22 · engine `4.7.2.stable.official.ed1daf0bf` · plan: [`docs/plans/ROUND8_FEEL_AND_RETURN.md`](../../docs/plans/ROUND8_FEEL_AND_RETURN.md)*

This round changed how touches are measured, so the facts the changes rest on were read **out of the engine the project ships on**, not out of memory or a doc page for a different version. This file is that evidence, plus what each behaviour change is pinned by.

---

## 1. Input facts, read from this binary

Run against the project with `godot --headless --path . -s <probe>`:

```
--- Input ---
use_accumulated_input = true
--- ProjectSettings ---
input_devices/buffering/agile_event_flushing = false   default = false
input_devices/pointing/emulate_mouse_from_touch = true default = true
application/run/max_fps      = 60    default = 0
application/run/delta_smoothing = true  default = true
physics/common/physics_interpolation = false default = false
gui/common/drag_threshold    = 24    default = 10
gui/common/default_scroll_deadzone = 30  default = 0
--- ClassDB: InputEventScreenDrag ---
  index, tilt, pressure, pen_inverted, position,
  relative, screen_relative, velocity, screen_velocity
--- ClassDB: InputEventScreenTouch ---
  ... canceled (default false)
--- Input methods ---
  set_use_accumulated_input, is_using_accumulated_input, flush_buffered_events
--- Engine ---
  max_fps = 60   physics_ticks = 30   physics_jitter_fix = 0.5
```

What follows from each:

| Fact | Consequence for this round |
|---|---|
| **Accumulation is on by default.** The docs: "all input events generated during a frame will be merged and emitted when the frame is done rendering. Therefore, this limits the number of input method calls per second to the rendering FPS." | A handler sees **one** motion event per rendered frame. Anything measured *per event* is measured *per frame*, which is why the stir's 45°/event cap, the pan's start-of-drag overshoot, the décor carry's first velocity sample and the sheet's per-event velocity average were all frame-rate-scaled. Fixed in A1–A4 and A11. |
| The docs name **freehand drawing** as the case to turn accumulation off for. | Only a gesture whose meaning is the *path* gains anything. The pan, a carried piece, a slider and a petal under the thumb need only the latest position and are redrawn once per frame regardless. The tea stir is the one path-integrating gesture in the game, so it is the only holder of `InputPrecision`. |
| Merge semantics (`InputEventScreenDrag::accumulate`): `position`, `velocity` and `screen_velocity` are **overwritten** with the newest; `relative` and `screen_relative` are **summed**. | A merged event's `relative` is a sum over N raw samples and is legitimately large, so capping it is unsound — as is capping an absolute position delta at a low frame rate. Only a geometric or per-second rule is frame-rate independent. `WorldPan` already tracks absolute `position` and derives its own time-windowed velocity, so it was right. |
| `agile_event_flushing` is **false** by default and flushes before every idle *and physics* frame; implemented for Android only. | Left off deliberately. Physics runs at 30 Hz here, below the frame rate, so the extra flush points are unclear, and it is a latency lever that wants a device measurement rather than a guess. Recorded in the plan's §7. |
| `InputEventScreenTouch.canceled` exists. | It was never read anywhere in the game, so an OS gesture that takes the touch away (notification shade, back-swipe, a call) arrived as an ordinary release and fired a real world action on the way out. Fixed in A12. |
| 2D physics interpolation exists (`SceneTree.physics_interpolation`, `RenderingServer.canvas_item_set_interpolated`) but defaults off. | Irrelevant here: everything in this game animates in `_process`, not `_physics_process`. Recorded so it is not re-opened. |
| `Spring` is a closed-form analytic integrator; `PanBody._step_glide` is the exact exponential. | Two 1/60 steps equal one 1/30 step bit-for-bit. The motion layer was already frame-rate independent, which is exactly what made the per-event gesture rules stand out as the inconsistency. |

**Sources.** `Input.set_use_accumulated_input` / `ProjectSettings` class reference, and the engine's own `ClassDB` as dumped above.

---

## 2. What each change is pinned by

Every behaviour change carries a test. Two of them were checked the hard way — by reverting the fix and confirming the test fails:

| Change | Test | Reverted-fix result |
|---|---|---|
| Pan no longer lurches at the start of a drag | `test_world_pan.gd::test_the_pan_never_jumps_at_the_start_whatever_the_first_step` | — |
| Décor carry re-anchors at the handoff | `test_active_decor_view.gd::test_the_carry_starts_without_a_pop_or_a_lean_kick` | **fails**: foot pops `26.0 px` (the whole slop) against a 10.4 px bound, and the lean target reads `0.0908 rad` = 5.2° against a 6° cap |
| Stir ring geometry + chord guard | `test_active_tea_view.gd` × 6, incl. `test_tracing_the_drawn_progress_ring_credits_a_whole_turn` at the real 936 × 1092 panel | the ring-trace test asserts the premise first (`ry < stir_inner_px()`), so it cannot pass vacuously |
| Stir is frame-rate free | `test_the_same_stroke_counts_the_same_at_any_sampling_rate` (9 / 18 / 72 chords) | — |
| `InputPrecision` | `test_input_precision.gd` × 6, incl. `test_godot_accumulates_input_by_default` which re-checks the premise against the engine | — |
| Governor keeps 60 fps under a finger, defers tier pops | `test_frame_governor.gd` × 6 | — |
| Mossling one-slop | `test_creature_r4.gd::test_a_small_slide_still_taps_and_there_is_no_dead_band`, `..._a_fast_flick_across_a_friend_pets_it...` | — |
| Cancelled touch | `test_world_pan.gd::test_a_touch_the_os_cancels_fires_nothing` | — |
| Sheet dismiss velocity | `test_ui_sheets_r6.gd::test_swipe_velocity_is_windowed_and_goes_stale`, `..._the_same_flick_reads_the_same_at_30_and_60_fps` | — |
| Recap nap + waiting-wish lines | `test_core_helpers.gd` × 3, `test_creature_brain.gd` × 2 | — |
| ♥1 wave on open | `test_retention_wave.gd` × 4 | — |
| Held wish not granted unseen | `test_active_wishes.gd` × 2 (and the away case, which the first attempt broke — see §3) | — |

---

## 3. One thing the suite caught, worth writing down

The first version of the held-wish guard refused **every** non-open wish in `WishRules.on_decor_placed`. `test_active_decor.gd::test_decor_near_wish_is_granted_now_or_on_arrival` failed, and it was right to: `WISH_HELD` means two different things.

- A friend who **left** keeps its wish — that is the designed behaviour (ACTIVE_WISHES §5: "Works while the friend is away: it is then granted on its next arrival"), and a piece set near its spot must still be remembered for it.
- A friend who is **here** and held has no bubble, because its slot belongs to another friend.

Only the second is the bug. The guard now applies to present friends only, and both halves have a test.

---

## 4. Not verified here (needs a device or a rater)

- Every visual change in this round is motion the game already had (the `sway` motion for the ♥1 wave, the existing recap card rows). No new art was authored, so no new rubric pass is implied — but the wave and the two recap lines have never been seen by a human and should be in the next capture set.
- Frame pacing, haptics and the governor's tier behaviour still need the on-device checks of `docs/QA.md` §6.
- `tools/audio/synth.py --check` mis-gates `pad_night_cmaj7` in this container: in check mode `check_one` sets `pre.seam = post.seam`, i.e. it feeds the **decoded** Vorbis seam to the **pre-encode** seam threshold, which Vorbis ringing exceeds. The committed asset is fine; the tool's check path is not. Fix that before anyone uses `--only` to author the missing cues (`validate_content.py` now lists them every run).
