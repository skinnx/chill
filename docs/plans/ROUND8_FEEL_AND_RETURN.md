# Round 8 — Feel & Return

*Director plan · 2026-10-22 · owner request (paraphrased): keep the chill character, give players a reason to come back, **polish the complex features**, and read the Godot docs carefully so the touch interaction is as smooth and as well suited to a thumb as it can be.*

**Baseline.** Round 7 + Active Play v1, 438/438 GUT tests, every CI gate green (lint, data, import, strict, test) on Godot 4.7.2-stable.

**How this round was scoped.** Eight parallel read-only audits over the input arbiter, the three Active Play features, the creature brain, performance, the retention surfaces and the Godot 4.7 input documentation, each asked for file:line evidence and a fix that breaks no pillar. Everything below is something an audit found and this plan then re-verified in the code. Nothing here is speculative polish.

---

## 0. The one-line summary

Round 8 does not add a feature. It makes the features that exist **land where they look like they land**, **answer the same way on a slow phone as on a fast one**, and **say something warm at the moment the player comes back**.

---

## 1. Binding constraints (unchanged)

Every pillar in GDD §1.2 and every guarantee in §13.0 / §14.0 holds. In particular, nothing in this round may introduce a fail state, a decay, a countdown, a streak, a badge number, a notification or any copy that implies the player is behind. Where this round adds a line of text, it is present-tense, names no number and asks for nothing.

---

## 2. Strand A — touch feel

The Godot research for this round (§6) produced one governing fact: **Godot merges input events once per rendered frame by default**, so anything measured *per event* is really measured *per frame*. That single fact explains four of the defects below, on four different surfaces, none of which were visible at 60 fps.

| # | Defect (verified) | Change |
|---|---|---|
| A1 | The tea stir's dead zone was a **circle** while the progress ring the player is invited to trace is a flat **ellipse** (`RING_R` 176 × 64), so the ring's own top and bottom — and the whole liquid surface with the spoon standing in it — registered nothing. | The dead middle is measured in **ring space**, so the drawn ring is live all the way round. The outer bound stays a circle: a wide round stir must keep every degree. |
| A2 | The stir's `45° per motion event` ceiling was a frame-rate cap: 2,700 °/s at 60 fps, 1,350 °/s at 30 fps. A straight pull out of the middle of the pot was also credited, because only the *new* end of a sample was range-checked. | The rule is now geometric and frame-rate free: both ends of a sample must be in the ring **and** the line between them must miss the dead middle (which is what makes "a scribble through the centre adds nothing strange" exactly true). What is left is clamped to `stir_max_deg_per_sample` 170°, a guard under the ±180° wrap. |
| A3 | The map **lurched** at the start of a fast drag by `v · dt`: ~2 dp at 60 fps, ~12 dp at 30 fps, ~25 dp for a hard flick on a tier-dropped device. | The pan begins where the finger *is* on the crossing frame. Zero jump at any frame rate; the slop is swallowed. |
| A4 | A carried décor piece **popped the full 24 px slop** the instant it started following, and the first velocity sample divided that slop by one frame delta (≈480 dp/s), slamming the lean spring to its 6° cap. Every pick-up — the core verb of F3 — began with a lurch and a flinch. | The carry re-anchors on the frame it starts, exactly as the pan does. Measured: 26 px → under 7 px, lean 5.2° → under 1.7°. |
| A5 | The quality-tier step took the foreground frame, the vignette, the light shafts, a cloud and 40 % of the grass off the screen **in one frame**, and was structurally biased to fire mid-pan (panning is the heaviest render path, so it is the most likely thing to trip the slow-frame test). | The step is held until no finger is down and the map has stopped, then applied. The frames are already slow; a few hundred ms of delay costs nothing, and the startle is what breaks the calm. |
| A6 | The governor dropped to 30 fps **with a finger still on the glass** — a resting thumb generates no events, so 8 s of stillness took the session idle mid-gesture and the next drag frame applied two frames of travel at once. | A pointer on the glass counts as activity, with a 16 s staleness guard so a lost release can never pin the session at 60 fps. |
| A7 | The mossling — the most-tapped thing in the game — had the **strictest slop in the app** and a dead band: 18 px tap, 24 px stroke, plus a 60 ms minimum hold. A thumb that slid 19–24 px did nothing at all, and neither did a quick flick across a friend. This is the round-7 "I often mis-tap" complaint, still live where it hurts most. | One number, `stroke_drag_px` 24 px, the same as every other target: up to it is a tap, past it is a pet, no band in between and no hold. |
| A8 | `WorldPan.nudge` (the edit-mode edge pan) never emitted `motion_started`, so the camera's idle drift kept running and was never folded — the ground slid under a piece the player was still aiming. | `nudge` emits it, like a drag and a home glide. |
| A9 | The décor drop used the **previous frame's** position, so a flick-release committed up to a frame short of where the player let go, and a drop just inside the tray could read as a world drop. | Both the world path and the tray path settle from the release position. |
| A10 | `InputPrecision` is new in this round (see §6); a claim could outlive the gesture if the app went away under a finger. | `release_all()` on `APPLICATION_PAUSED` / `FOCUS_OUT`. |
| A11 | Swipe-to-dismiss measured its velocity with a **per-event** exponential average (alpha 0.5), so its time constant was the frame interval: the same flick read ~1,135 px/s at 60 fps and ~920 px/s at 30, and one phone closed the sheet where another bounced it back. It also never decayed — pull a sheet down a little, hold it to look at the world behind it, lift, and it closed on the speed of a pull that had finished a second ago. | The same time-windowed estimate `WorldPan` already uses, with the same staleness guard. |
| A12 | `InputEventScreenTouch.canceled` was **never read anywhere in the game**. Android delivers a touch the OS takes away — the notification shade, the back-swipe, an incoming call — as an ordinary release with that flag set, so a finger dragged off the screen by the system fired a real world action on its way out. | A cancelled touch drops the pending tap and ends the drag without inertia. |
| A13 | The `world_drag` branch of the arbiter was the only one that did not poke the `FrameGovernor`. A mossling claims the drag, so **petting** generated no activity: a long stroke halved the frame rate under the thumb. | It pokes like every other branch. (A6's pointer-down rule already bounded this; the poke fixes it at the source.) |

## 3. Strand B — Active Play correctness

| # | Defect (verified) | Change |
|---|---|---|
| B1 | A wish granted **during offline catch-up** replays on resume as a full live celebration — petal pop, the friend walking over, S27, a toast — *on top of* the `RECAP_WISH` line the recap already produced. ACTIVE_WISHES §7.5 says the toast **or** the line, never both. | `wish_granted` carries an `offline` flag, as `heart_up` already does; the view stays quiet and lets the recap tell it. |
| B2 | `on_decor_placed` grants a wish in **any** state, where `on_action` requires `WISH_OPEN`. A *held* wish has no bubble — its slot belongs to another friend — so the pose, the stamp, the gift petal and the once-per-20 h affection were handed out for a goal the player was never shown. | It gains the same open-state guard. A wish never expires, so waiting for its bubble costs nothing. *(The audit also wanted the purchase path to stop granting at all. Left alone deliberately: the eligibility filter only spawns a `decor_near` wish when nothing of that set is near the friend yet, so a purchase that lands one there is a fair fulfilment. Recorded in §7 for the Director.)* |
| B3 | A petal or dew drop released over a **full** pot simply vanishes — no flight, no float home — breaking ACTIVE_TEA T3 "nothing is discarded" at the exact moment the player is most likely confused. A drag out of an **empty** jar ends in silence. | Both float home, and the empty jar says what the tap already says. |

## 4. Strand C — the features are silent, and nothing said so

`audio/manifest.json` carries **S01–S21**. The data files reference **S22–S38**. Every cue of Retention v1 and of all three Active Play features is missing, so the most gesture-heavy feature in the game is mute: no plip as a petal falls in, no stir swish, no pour, no clink, no "new recipe", no décor lift, snap, turn or tuck. It compounds A1 — between the 180° bells, the only confirmation that a stir was registering at all was the ring slowly filling.

This is the Sound Designer hand-off of GDD §13.7 and §14.8, never executed through two rounds while the sim, the save, the strings and the tests for those features all landed.

**What this round does about it.** Not the synthesis: `tools/audio/synth.py` is a deterministic build with hard loudness and seam gates, and rebuilding every asset from a container where the result cannot be listened to is not something to do blind. (Note for whoever does: `--check` currently mis-gates `pad_night_cmaj7`, because in check mode it feeds the *decoded* Vorbis seam to the *pre-encode* seam threshold — `check_one` sets `pre.seam = post.seam`. Fix that before using `--only`.)

What it does instead is make the gap permanent and loud: **`validate_content.py` now fails the build when any data file names a cue the manifest does not define.** The 17 known-missing ids are written down in one `UNVOICED` table with what each is for, so the hole cannot grow, and an id that is authored while still listed also fails, so the list cannot go stale. `tools/ci/run_ci.sh data` prints the outstanding count every run.

*Corrected from the audit:* `TeaArt.cue`'s `elif` is **not** a bug. `AudioDirector.play_cue` plays the manifest cue's own haptic, so the fallback branch exists exactly so the touch is never silent and never double-buzzes once the cue lands. The docstring says so; it was checked and left alone.

## 5. Strand D — a reason to come back, with no pressure

Two lines on the welcome-back card. Both are lowest-priority candidates, so they only ever appear when there is room; both are present-tense, name no number and ask for nothing.

| # | Line | Why it is the right answer |
|---|---|---|
| D1 | **"{name} napped at the {spot}."** `RECAP_NAPPED` has existed in `strings.csv` since the MVP, `OverlayHost` already maps it to the moon icon, and `CreatureBrain.longest_nap(t0, t1)` already exists and is tested. The line was blocked on the brain, which now exists (ARCHITECTURE §12 open issue (a); `Recap`'s own header says it "replaces this slot once that exists"). | It is the purest form of what this game promises: the hollow lived while you were away, and here is a small true story about it. It rewards absence (G4), it names nobody as waiting, and it costs no save schema — the brain is deterministic, so the bouts of a past visit can be *reconstructed* rather than stored. |
| D2 | **"{name} is still hoping for {wish}."** Built from `state.wishes`, not from events: the oldest pending wish, a present friend preferred. Never shown together with `RECAP_WISH`, which is the same thought already answered. | The system already holds the best possible no-FOMO hook — a friend is waiting for something small you can do in ten seconds — and today it says so nowhere at the moment the player is most receptive. A returning player sees at most two bubbles in the hollow and otherwise has to notice a small cloud over the right friend. A wish never expires, so the line can never become a deadline. |

## 6. The Godot research behind strand A

Checked against the engine the project ships on (`4.7.2.stable.official.ed1daf0bf`), not from memory. The probe output is in the round-8 QA notes.

| Fact | Verified how | What follows |
|---|---|---|
| `Input.is_using_accumulated_input()` is **true** at boot. The docs: "all input events generated during a frame will be merged and emitted when the frame is done rendering. Therefore, this limits the number of input method calls per second to the rendering FPS." | Ran a script against 4.7.2 and read the property. | A handler sees **one** motion event per rendered frame. Anything per-event is per-frame. → A2, A3, A4. |
| The docs name **freehand drawing** as the case to turn accumulation off for. | Godot `Input.set_use_accumulated_input` reference. | Only a gesture whose meaning is the *path* benefits. The map pan, a carried piece, a slider and a petal under the thumb all only need the latest position and are redrawn once per frame anyway. The tea stir is the one path-integrating gesture in the game, so it is the only holder of `InputPrecision`. |
| `input_devices/buffering/agile_event_flushing` is **false** by default. | Same probe. | Deliberately left off: it adds a flush before each *physics* step, which runs at 30 Hz here (slower than the frame rate, so it adds nothing), and only Android implements it. |
| `InputEventScreenDrag` exposes `relative`/`screen_relative` and `velocity`/`screen_velocity`; the plain ones are scaled by the content-scale factor. | `ClassDB` dump + the class reference. | The project tracks absolute `position` and derives its own time-windowed velocity, which is stretch-correct by construction. No change needed. |
| `Spring` is an analytic closed form; `PanBody._step_glide` uses the exact exponential. | Read. | Two 1/60 steps equal one 1/30 step bit-for-bit. The motion layer was already frame-rate independent — which is exactly why the per-event gesture rules stood out as the inconsistency. |

## 6b. The headline for round 9: Retention v1 has no front end

The retention audit found, and this was then verified directly, that **Retention v1's P2 view layer (GDD §13.9) was never built**. Seven of its eight typed `Game` signals have **zero** listeners anywhere outside `game.gd` and the sim:

| Signal | Listeners outside `game.gd` / `scripts/sim` |
|---|---|
| `sign_visible`, `scene_staged`, `nest_grew`, `clue_found`, `cousin_arrived`, `keepsake_added`, `mystery_opened` | **0** |
| `heart_up` | 2 |

So: mystery signs are never drawn and cannot be tapped; away scenes exist only as save data and are never staged, although the recap happily promises one; nests never appear; and the Album still has its three MVP tabs, so Clues, Memories and Keepsakes — content, strings, sim, save and tests all shipped — have no UI at all.

This is the real answer to "give players a reason to come back": **it already exists, fully simulated and saved, and the player cannot see any of it.** It is a whole round of work (world art, an Album rebuild, the input arbiter's sign priority, the scene staging view), which is why this round did not start it — but it is the first thing round 9 should do, and it dwarfs everything in §7.

One piece of it was small enough to finish here: **the ♥1 "waves hello on open"**. `RetentionRules.wave_plan` has existed and been tested since P1 and nothing ever called it. It now runs from `CreatureLayer` once the welcome-back card is out of the way, each friend after its own deterministic delay, skipping anyone who has since left or fallen asleep. It is the one beat in the design whose whole purpose is to make a *return* feel personal.

## 7. Out of scope for this round (recorded, not forgotten)

Found and verified by the audits, deliberately deferred:

- **F3 edit-mode cost.** `_to_held()` builds ~110 sockets (each through a full `validate`) inside the input callback on the first motion frame; `resolve_drop` rebuilds the same list on release; the ground overlay re-tessellates every movable piece as a 40-segment ellipse every frame (~7.2k vertex appends at endgame) to animate one colour. All three are real and worth a dedicated performance round with a device profile behind it.
- **Reduce Motion in edit mode** teleports a held piece up to 14 dp into and out of every socket, where ACTIVE_DECOR §10 specifies a 300 ms crossfade — an inversion of the setting's purpose, for the players most sensitive to it.
- **`edit_hit_min_dp_after_clip`** is CI-validated but never read, so a piece placed at the bottom of the hollow loses about a third of its edit target.
- **The play pair** is the only inter-creature behaviour, and it is one-way, never cleared, and does not check that the partner is awake — so the common case is a friend "playing with" a sleeping one.
- **`OverlayHost.show_toast` has no queue**, so one action that delights two friends names only the second.
- **Buying décor grants `decor_near` wishes from behind the shop sheet** (the world is covered, and the friend walks to the piece unseen). Defensible — the player did buy the thing — but a Director call.
- **An offline wish grant on a *sleeping* friend** still toasts with no visible reaction, and `stream_near_dp` is in the data but never read, so a stream tap grants a wish to a friend on the far bank.
- **`input_devices/buffering/agile_event_flushing`** is off and untested. It flushes key/touch events before every idle *and physics* frame and is implemented for Android only; physics runs at 30 Hz here, below the frame rate, so the gain is unclear. It is a latency lever that wants a device measurement, not a guess.
- **The display refresh rate is read once at boot**, so a session that starts on one rate and continues on another keeps the wrong frame-rate divisor.
- **Waking from idle keeps the 30 fps deltas in the window**, so the first touch after a pause can trip a tier step-down; and the ambient wake gate consumes its gesture before the governor sees it, so the new pointer-down rule is blind on that one path.
- **`decor_placed` fires at commit**, ~332 ms before the piece settles, where ACTIVE_DECOR §15 contracts "after the settle". Doc and code must be made to agree either way.

---

## 8. Definition of done

1. Every CI gate green, locally and in CI (`lint data import strict test`), with the new regression tests passing.
2. Every behaviour change above carries a test that **fails without the change** (checked by reverting, for the two carry/pan anchoring fixes).
3. `ARCHITECTURE.md` §3.5, `GDD.md` §14, `ACTIVE_TEA.md` §4 and `ACTIVE_DECOR.md` agree with the code.
4. No new string breaks the E8 banned-word lint; both locales stay at parity.
