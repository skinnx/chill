# Round 11 — Home & Memory

*Director plan · 2026-10-23 · owner request (paraphrased): speed up progress.*

**Baseline.** Round 10, 496/496 GUT tests, every local CI gate green on Godot 4.7.2-stable.
**Result.** 517 tests, all gates green (`lint data import strict test`).

---

## 1. What "faster" meant

Round 10 showed the pattern: the biggest depth in the game was already simulated, saved and tested — it just had no view. Three such views were left on the Retention v1 list (round 9 §6, round 10 §6): **nests**, the **away scenes**, and the **Memories / Keepsakes tabs**. Each is a reason to come back that the player could not see. This round builds all three, in the same shape as the signs: a view that reads the sim and holds no state of its own, one draw call, one tap, nothing to manage.

| | Added | New state | New verbs |
|---|---|---|---|
| Nests | a layer + a brain rule | none (view-side fade/pop) | none |
| Album | two tabs, four friend-card lines | none | none |
| Away scenes | a props layer + cast staging | none (view-side) | **one tap** (already in the sim) |

## 2. Nests — a home, and a friend asleep in it

`NestLayer` draws every nest in `Game.nests()`: four styles × three stages, 48 × 24 dp at `friendship.json nest.anchors`, procedural, one `draw_polygon`. A stage reached while watching pops by 12 % and settles; offline growth arrives with the recap line and simply shows grown. A nest is not a tap target — the mossling in it is — so the hit ladder is untouched.

The part that makes a nest *mean* something is in the brain: **the friend sleeps in it.** `CreatureBrain.nests` is a callable like `owned` and `bed_flowers`; with it, a nap bout takes the friend's own nest spot `nest:<species>` with p `nap_preference` = 0.7 before the normal spot rule, never twice in a row, capacity 1, nobody else's. The extra RNG draw happens **only for a friend with a nest**, so every other visit plans bout-for-bout as before and old saves replay unchanged (`test_a_friend_without_a_nest_plans_exactly_as_before`). `nap_during` wires the sim's nests too, so an absence's longest nap can be in one — and the recap's "{name} napped at the {spot}" then says *at the Moss bowl*.

Measured over six seeded 12 h night visits: nest naps are **40–75 %** of all naps — the common case, never every time.

## 3. Album — five tabs, as designed

GDD §13.5.1 asked for **Friends · Clues · Memories · Keepsakes · Postcards**. Photos moves into Memories as its second section, so the tab constants shift again (`TAB_MEMORIES` 2, `TAB_KEEPSAKES` 3, `TAB_POSTCARDS` 4) — and this time the round-10 clamp fix means nothing deep-links to the wrong tab.

- **Memories:** little moments newest first — the scene's title, the cast as live portrait wells (asleep for the nap scenes, beaming otherwise), the caption with their names, the day — then the photos.
- **Keepsakes:** ♥5 portraits, signature gifts (the gift itself from the décor atlas via `ItemPreview`, the Basket's own stamp cell), cousins met. Empty state `KEEPSAKES_EMPTY`.
- **Friend card:** the five unlock lines (`UNLOCK_HEART_1…5`; reached in ink, the rest *Comes with more hearts* — never a countdown, never points), `ALBUM_NEST` (style · stage), the `ALBUM_PAIR` tag once the pair is active, and the cousin row once met.

The two round-6 layout sweeps (every label inside its parent; nothing drawn outside the sheet clip) now walk **all five tabs** in both languages at 100 % and 150 % text.

**Not done:** tab-bar icons and the unread dots. A dot needs a per-tab "seen" marker in the save, which is a schema change this round does not make.

## 4. Away scenes — something happened while you were away

The sim has picked, cast, staged, lingered and archived scenes since P1. Now they are on stage:

- **The cast** (`CreatureLayer._stage_scene`): a friend already in the hollow walks to its slot (`SceneLayer.slot_px` = anchor + `slot_dp`) under `_override_until = INF`; a friend who is away is **summoned** as an extra, exactly like a greeter — no visit, no gift, no affection — fades in at the slot and walks off when the scene ends. The `pair_nap` anchor is the lead's nest (its favourite spot if it somehow has none).
- **The props** (`SceneLayer`): the pebble tower, the leaf fort, the flower crown and the boat line, procedural, one draw call, fading in with the scene and out when it is archived. The prop is a tap target at `PRIO_SCENE` (= `PRIO_SIGN`, below a friend); the participants are mosslings and tap as mosslings.
- **One tap** on a participant or a prop → `Game.tap_scene()` → the sim archives it, `scene_archived` fires, the HUD toasts `SCENE_SAVED` and refreshes the Album, the stage clears, the brain re-commands the visitors on the next frame, the summoned friends leave. The 600 s foreground linger was already in `Game._process`.
- `--qa-scene=<id>` works unchanged: the fixture stages the pending scene before `world_ready`, and the layer stages whatever is pending at `world_ready`.

**Poses.** The `scene_*` and `pair_nap_*` pose ids in `scenes.json` are rig work that does not exist yet. Rather than wait, `SceneLayer.scene_pose` maps them: the nap scenes **sleep**, the moon watchers **sit by the brook** (the anchor is `stream_bend`), and everyone else **stands at the slot, looks at the thing — the proud one at you — and beams**. `test_every_scene_pose_maps_to_something_a_mossling_can_do` pins that no pose id falls through. When the rig poses land, this one function is the seam.

## 5. One helper, three layers

`SignTris` (round 10) became `WorldTris`: blobs, rotated blobs, quads and strokes into one triangle array, one `draw_polygon`. Signs, nests and scene props all draw through it.

## 6. Still open

- Scene poses in the rig; S22–S38 voiced (S22 rustle, S25 scene).
- Album tab icons and unread dots (save-side seen markers).
- Pair play / pair sit-by-stream bouts (`friendship.json pair`) and the pair-nap nest fallback for ordinary naps.
- From earlier rounds: the F3 socket build inside the input callback, Reduce Motion's magnet teleport, `edit_hit_min_dp_after_clip`, the one-way play pair, the toast queue, sheet state across opens, Android Back popping the Album friend page.

---

## 7. Definition of done

1. Every local CI gate green (`lint data import strict test`): **517 tests, all passing**.
2. Every behaviour change carries a test.
3. `ARCHITECTURE.md` §3.3 / §3.5 / §5.4 and GDD §2.5 / §13.2.3 / §13.4 / §13.5.1 agree with the code.
