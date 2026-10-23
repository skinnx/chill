# Round 9 — Reach & Cost

*Director plan · 2026-10-23 · owner request (paraphrased): optimise the user experience and the graphics operations.*

**Baseline.** Round 8, 473/473 GUT tests, every local CI gate green on Godot 4.7.2-stable.
**Result.** 481 tests, all gates green, and the suite itself runs 32 % faster (118 s → 80 s) — a side effect of §2, which is the same half-second the player was paying for.

Scoped from the eight round-8 audits' deferred findings. Each was re-verified against the code before anything was changed, and **three were refuted and dropped** (§5). Nothing here is speculative.

---

## 1. Reach — the sheet gesture

**The defect.** `UiSheet`'s swipe zone is `HEADER_TOP + HEADER_H` = **228 px (76 dp)** tall and nothing else drags the sheet. At the medium detent on a 1080×2400 phone that puts the zone at roughly y 398–626: the top quarter of the screen. The close ✕ sits at (954, 536). The scrim's only thumb-reachable part is the 8 dp gap above the dock and two 8 dp side columns.

So every way to resize or dismiss a sheet lived outside the one-handed arc, while the **~77 % of the sheet that is under the thumb — the list — did nothing at all for the gesture.** This was the single biggest reachability gap in the app.

**The change.** The standard nested-scroll bridge. While the list is at `scroll_vertical == 0` and the finger pulls **down** past `LIST_HANDOFF_PX`, the gesture becomes the sheet's and the list does not scroll.

- **24 px** is `gui/common/drag_threshold`, the project's "this is a drag now" number. It sits under both the 10 dp button slop and the list's 10 dp scroll deadzone, so the sheet claims first and cleanly, and `TapGuard.cancel_in` explicitly drops the row press underneath — otherwise a pull-down that started on a row would also fire that row.
- The handoff **re-anchors** (`drag_begin` at the live finger), so it costs no jump. Same rule as the map pan in round 8.
- Any other direction, and any list with content above the window, scrolls exactly as before.
- Pulling **up** to expand from the medium detent is deliberately *not* taken. A long list must still scroll without first growing the sheet.

**Also fixed:** a sheet grabbed while it was still opening snapped up by whatever was left of the animation, because the first motion event recomputed `rise` from `dy` alone and discarded the live value. It now carries that rise into the drag (`_drag_rise0`).

## 2. Cost — the half-second nobody could see

`Spring` is analytic, so each step is cheap; what was expensive was how **long** it ran.

`motion_tokens.json`'s `rest_epsilon` is **absolute** (0.0005), but half of these springs drive properties measured in **pixels**. Measured for the `move` token (2.4 Hz, ζ 0.8):

| travel | to 0.0005 px | to 0.05 % of travel | wasted |
|---|---|---|---|
| 300 px (a panel) | 1.10 s | 0.63 s | **0.47 s** |
| 1,709 px (a full-height sheet) | 1.25 s | 0.63 s | **0.62 s** |

That tail is not free: `Motion._process` calls `FrameGovernor.hold_for` for as long as **any** drive is alive, so every sheet open, dock move, tray slide and drag release pinned the whole app at 60 fps for an extra half second — before the 8 s idle timer could even start.

A **driven** spring now rests within `REST_REL` = 0.05 % of the distance it set out to travel, never tighter than the token floor. Two details matter:

- The form is **relative**, so it is right for a pixel property and for an alpha alike without `Motion` having to know units. An alpha 0→1 keeps the absolute floor.
- A drive that finishes writes the **exact** target. Stopping early must leave no residue: a `rise` left 0.3 px short is invisible, but code asking `rise > 0.0` is not blind to it. (This bit immediately — a test began dismissing a sheet that should have settled.)
- 0.05 % rather than 0.1 % keeps the final snap under a pixel even for the longest travel in the game (1,709 px → 0.85 px), at a cost of only ~0.06 s of the saving.

`Spring`'s own default is untouched for the many places that step a spring themselves.

## 3. Cost — the décor overlay

While edit mode is open, the ground overlay rebuilds a ring for **every movable piece on every frame**, purely to animate one breathing colour. Two wastes, both removed:

- **Oversampling.** `_ellipse_points` used a flat **40 segments**. The foot rings run 30–71 px wide, so the chords sat **0.09–0.22 px** from the true curve inside a **6 px** stroke. Segments are now chosen from the ring's own size against a 0.75 px tolerance (a tenth of the stroke), which clamps to 12–24 and puts the common sets — pinwheels and lanterns, 10 copies each — at **14**. Each segment is a quad: 4 point, 4 colour and 6 index appends in GDScript, per piece, per frame.
- **`movable_pieces()`** built and lambda-sorted a fresh `Array` on every call, and `_draw` calls it every frame. It is now cached and invalidated only when a piece enters or leaves the index.

## 4. Reach — a rebuild never lands under a thumb

A gift arriving, a bloom, a heart or a postcard fires a sim event, and the open sheet's `refresh()` rebuilds its rows — **freeing the control the press belongs to**, so the tap the player was making simply never happens and the sheet appears to swallow it.

`SheetHost.refresh` now holds the rebuild while `UiSheet.is_touched()` (a header drag, a list drag, or a list still gliding) and applies it on the first frame after the finger leaves. The news is never urgent.

## 5. Checked and dropped

Three findings from the round-8 audits did not survive re-reading. Recorded so they are not re-opened:

| Claim | Why it was dropped |
|---|---|
| "Waking from idle keeps the 30 fps deltas in the window, so the first touch after a pause trips a tier step-down." | `FrameGovernor._process` already does `_deltas.clear()` and `_window_t = 0.0` on **every** idle transition, both directions. At most one 33 ms frame survives the switch, which is 0.55 % of a 3 s window against a 5 % threshold. |
| "The 30 s weather crossfade re-derives the whole OKLab palette every frame — ~50 pow() and ~35 RenderingServer writes for 1,800 frames." | The arithmetic is real but the cost is not: ~50 `pow()` is on the order of a microsecond against a 16 ms budget, the writes are already filtered to changed values, and weather episodes are ≥ 1 h apart, so this is ~0.8 % of wall time. Not worth the risk of touching the palette path. |
| "Un-gated `_process` loops in `dock_view` allocate Arrays every frame." | True (`buttons.values()`), but the dock has three buttons: a three-element array per frame is not where the frames go. |

## 6. Still open (unchanged from round 8 §7)

The headline remains **Retention v1 has no front end** — seven of its eight typed signals still have zero listeners, so signs, nests, away scenes and the Clues/Memories/Keepsakes tabs are simulated, saved and invisible. Also still open from the round-8 list: the F3 socket build inside the input callback, Reduce Motion's magnet teleport, `edit_hit_min_dp_after_clip`, the one-way play pair, the toast queue, and the 17 unvoiced audio cues (which `validate_content.py` now counts on every run).

Two more recorded here:

- **Sheets are rebuilt on every open**, so the tab, the scroll position and the Album page are forgotten; Décor is always three taps.
- **Android Back from an Album friend page closes the whole sheet** instead of popping back to the grid.

---

## 7. Definition of done

1. Every local CI gate green (`lint data import strict test`): **481 tests, all passing**.
2. Every behaviour change carries a test.
3. `ARCHITECTURE.md` §3.5 and the new §8.4a agree with the code.
