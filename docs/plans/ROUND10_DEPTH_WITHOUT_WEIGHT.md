# Round 10 — Depth Without Weight

*Director plan · 2026-10-23 · owner request (paraphrased): develop it with depth, but keep it easy to play.*

**Baseline.** Round 9, 481/481 GUT tests, every local CI gate green on Godot 4.7.2-stable.
**Result.** 496 tests, all gates green (`lint data import strict test`).

---

## 1. The reading of "depth but easy"

Depth and ease pull apart only when depth is bought with **management**: more taps, more screens, more to keep track of. The cheapest depth is the kind the player already owns and cannot see.

Retention v1's mystery layer is exactly that. Since P1 the sim has been opening mysteries, laying signs at valid anchors, awarding clues, holding riddles and solving them — **saved, replayed, parity-tested, and completely invisible.** Seven of its eight signals had zero listeners (round 8 §7, round 9 §6). The player's world already had a story in it and the screen never said so.

So round 10 adds **no new systems and no new verbs**. It renders the depth that is already there and gives it the simplest possible verb: **one tap, no decision, nothing to miss.**

| | |
|---|---|
| New things to manage | 0 |
| New gestures | 0 (a tap, on the ladder the arbiter already runs) |
| New screens | 0 (a tab in a sheet that exists) |
| Things that can expire | 0 |
| Things that can be done wrong | 0 |

## 2. Signs in the hollow

`SignLayer` (`scripts/world/sign_layer.gd`, mounted under `World/Ground/Play` so it y-sorts with everything else) takes `Game.visible_signs()` as truth and draws the ≤ 3 signs the sim says are out: footprints in the species' own style, a dropped thing in its tint, a rustling bush, or a folded note.

- **It owns no state the sim does not.** `sync()` adds what is new, keeps what is still listed, and lifts out what has gone — including a mystery solved while the app was closed, which leaves quietly rather than vanishing between frames.
- **It never asks for anything.** A sign has no timer and no badge. `test_a_sign_left_alone_stays` holds it to that for 200 simulated seconds; the sim has held it to 30 days since P1.
- **One draw call.** Every sign accumulates into a shared triangle buffer (`SignTris`) and the whole layer flushes as a single `draw_polygon`, the same approach the décor overlay uses. Three signs, four shapes, one call.
- **It idles for free.** `set_process` is left on only while something is fading, pressed or lifting; a settled sign costs a `_draw` the governor is already not asking for.
- **Three bushes never shake in step.** The rustle phase is `hash(key)`-derived, so it is stable across frames and saves, and decorrelated between signs.

## 3. Where a clue sits on the hit ladder

GDD §13.3.2 puts a sign between the mossling and the ready bud, which the ladder had no room for: the numbers ran contiguously from stream 1 to choose-a-bed 7.

The ladder was renumbered to open slot 6, and the two edit priorities moved with it (8/9 → 9/10). That number is **pinned in data**, so the renumber is three files or none:

| | |
|---|---|
| `scripts/main/world_pan.gd` | `PRIO_SIGN := 6`, `PRIO_EDIT := 9`, `PRIO_EDIT_SELECTED := 10` |
| `data/decor_placement.json` | `hit.prio_edit_piece: 9` |
| `tools/sim/validate_content.py` | the gate that asserts they agree |

`test_the_edit_priorities_still_match_their_data` asserts code against data so a future edit to either one fails loudly rather than silently mis-ordering presses.

The reasoning for slot 6: a clue is there **to be found**, and it goes away once it is. Anything a tap would otherwise do to the ground under it — plant, place, wobble, pan — will still be there a second later. A friend still outranks it, because a friend is never a means to something else.

## 4. One tap, and where it goes

Release-to-fire through the existing arbiter, so a sign behaves exactly like every other world target: touch-down squashes it 8 %, a drag past the slop pans the map instead and takes nothing, and the OS cancelling the touch takes nothing.

On release the sim awards the clue and the sign eases up and out over 600 ms. Then one of two things, and never both:

- **A note** opens the riddle card. It is the one clue worth stopping for, and it is the only one that was ever going to be read.
- **Anything else** toasts what was found — and, **on the first clue of the install only**, one extra line saying where it went. After that the player knows, and is never told again.

That rule is now a pure function (`HudController.clue_line`), which is both how it gets tested without standing up the whole HUD and the clearer place for it to live.

## 5. Album › Clues

A fourth tab, between Friends and Photos. Each open mystery is a card: the silhouette of whoever is coming, a title that changes as you learn more (*Someone is on the way* → *A cousin of Pip* → *So it was Pip!*), and the clues as **dots, never a number** — ● found, ○ still out there. The count exists only as the tooltip a screen reader reads.

The riddle appears on the card once the note is in, because the note is what earns it.

**A bug this surfaced:** `select_tab` still clamped to `0..2` from when there were three tabs, so adding Clues silently redirected every deep link to Postcards into Photos — including the one the mailbox uses. Fixed to clamp against the tab constants, and `test_the_clues_tab_is_reachable_and_reads_empty_before_anyone_is_on_the_way` walks all four.

The two round-6 layout sweeps in `test_ui_sheets_r6.gd` (every label inside its parent; nothing drawn outside the sheet clip) only ever saw the album's **Friends** tab. They now walk all four, in both languages at 100 % and 150 % text — so the new tab is held to the contract the file exists for, and so are Photos and Postcards, which were never checked either.

## 6. Still open

Unchanged from round 9 §6, less the sign layer and the Clues tab: the rest of the Retention v1 front end is **away-scene staging, nests, and the Memories and Keepsakes tabs** — which is also why Photos still has a tab of its own (GDD §13.5.1 merges it into Memories when Memories exists). Also still open: the 17 unvoiced audio cues S22–S38 (S22 is the rustle's own voice, so the bushes shake silently for now), the F3 socket build inside the input callback, Reduce Motion's magnet teleport, `edit_hit_min_dp_after_clip`, the one-way play pair, the toast queue, sheet state across opens, and Android Back popping the Album friend page.

---

## 7. Definition of done

1. Every local CI gate green (`lint data import strict test`): **496 tests, all passing**.
2. Every behaviour change carries a test.
3. `ARCHITECTURE.md` §3.3/§3.5 and GDD §2.5/§13.5.1 agree with the code.
