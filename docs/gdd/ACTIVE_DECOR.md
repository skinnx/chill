# ACTIVE PLAY F3: Free décor placement

Status: design v1, **accepted with lead changes** (GDD §14, 2026-10-22) (Game + UX Designer, F3). Lead decisions: attraction counts owned copies (Q1 yes); the chime stays on its branch in v1 (Q2, revisit with Seasons); NestRules may shift a not-yet-built nest up to 24 dp (Q3 yes); still pieces become prio-1 targets (Q4 yes); the Env Artist still confirms `ground_top` and the wings (Q5 open); one schema 3 bump (Q6 yes); cue ids S35–S38 (Q7). Anchor indices are 0-based everywhere. Data: `data/decor_placement.json` (rules and tuning, the single source of truth for every number below). Strings: `i18n/staging_decor.csv` (45 keys, en + vi, NFC, E8-linted, no key clashes with `strings.csv` or the F1/F2 staging files).

Sibling features: **F1 Wishes** (`docs/gdd/ACTIVE_WISHES.md`) and **F2 Tea & Treats** (`docs/gdd/ACTIVE_TEA.md`, `data/tea.json`). The links between them are written as contracts in §15.

---

## 0. One paragraph

Today every décor copy pops in at the next pre-authored anchor (GDD §2.5). F3 lets the player **pick up any piece and set it down somewhere else in the hollow**, turn it, or tuck it away in a storage tray. Pieces lean gently toward pleasant spots (beside their own kind, along the bank, around a toadstool ring, on the stepping-stone line), so a careless drop still looks composed (Townscaper-style). Nothing can go wrong. A spot that does not work makes the piece look a little hesitant and shows a soft hint, and the piece either finds a good place nearby or floats back to where it came from. Edit mode is optional, so the fixed-anchor behaviour stays the default: a new purchase still places itself.

**Pillars served:** player-paced expression (E4), soft and immediate feedback (I1), simple gestures with a no-drag path (I3), calm motion (V5). **Nothing broken:** no fail state (E1), nothing is lost (a tucked-away piece still counts for friends, §7), no timers (E2/E8), one currency and no new numbers beyond "×3" in the tray (E6).

## 1. Scope

| Set | Movable | Unit | Where it may stand | Turn steps |
|---|---|---|---|---|
| `leaf_pinwheel` | yes | piece | ground (look + tend) | 4 (front, ¾ right, back, ¾ left) |
| `pebble_cairn` | yes | **stack** of 1–10 pebbles | ground | 4 (re-seeded pebble jitter + flip) |
| `toadstool_seat` | yes | piece | ground | 4 (flip × two cap-spot patterns) |
| `stream_stones` | yes | piece | **water only** | 2 (flip) |
| `firefly_lantern` | yes | piece | ground (prefers the far bank) | 2 (crook faces left or right) |
| `wind_chime` | **no** (v1) | rail on the willow branch | its branch anchors | — |

The wind chime is a hanging set and the willow branch is the only hanger, so v1 leaves it on its branch (Q2 proposes more hang points). Flowers and beds are out of scope: GDD §2.4 rule 4 still holds.

---

## 2. Edit-mode flow

```
           PLAY ──long-press 450 ms on a movable piece──▶ EDIT, that piece HELD under the finger
             │                                             (keep holding and drag: one gesture)
             └──Garden sheet › Décor › "Arrange"──────────▶ EDIT, nothing selected (sheet exits)

EDIT ─┬─ press a piece ──▶ PRESSED (lifts in the same frame; the drag is claimed, no pan)
      │        ├─ release within 24 px ──▶ SELECTED (selection chip: Turn · Put away [· Lift a pebble])
      │        └─ move past 24 px ───────▶ HELD (follows the finger; magnet; valid/hint ring)
      │                    └─ release ──▶ SETTLE (snap, nudge, or float home) ──▶ commit + autosave
      ├─ SELECTED + tap ground ──▶ GLIDE to that spot ──▶ SETTLE ──▶ commit
      ├─ SELECTED + tap the same piece ──▶ deselect
      ├─ drag ground ──▶ map pan (as in play)
      ├─ drag a piece onto the tray ──▶ PUT AWAY ──▶ commit
      ├─ tray tile: tap ──▶ IN HAND (tile raised; tap ground to set it, or "Find a spot")
      │             drag out of the tray ──▶ HELD (a new piece from storage)
      ├─ Undo ──▶ reverts the last commit (one step)
      └─ Done / Back / app paused ──▶ PLAY (everything is already saved)
```

**Enter.**
- **Long-press** a movable piece in play (450 ms, the radial ring fill from 150 ms, Art Bible §4.18). Moving more than 24 px before 450 ms cancels the long-press and pans, exactly as on a bed. When it fires, the HUD and dock fade out (`short`), the edit chrome rises (`standard`), and the piece is already held, so the same finger can carry it away without lifting. Releasing without moving leaves it selected.
- **Garden sheet › Décor tab › "Arrange your décor"** row (`GARDEN_ARRANGE_ROW`, button `GARDEN_ARRANGE`). It shows once at least one movable piece is owned. The sheet exits (`exit`), and edit mode opens with nothing selected and the hint `DECOR_EDIT_HINT` for 4 s. This is the discoverable, no-long-press path.
- **First-time tip.** After the first décor purchase in a build with F3, the toast `DECOR_TIP_LONG_PRESS` shows once (Settings › "Show tips again" resets it like every tip).

**Move.** Drag (§3), or tap the piece then tap a spot (§10).

**Rotate.** "Turn" in the selection chip advances one step (`rot_steps` per set). The piece turns on a `pop` spring with a small hop (2 dp) and plays S37. There is no rotation gesture: it would need two fingers or a timed twist (I3).

**Put back into storage.** "Put away" in the chip, or drag the piece onto the tray. The piece shrinks into its tray tile on the `move` spring (332 ms), the tile pops, and S38 plays. The tray is never full.

**Exit.** "Done" (top-right), Android Back, or the app pausing. Every change is committed when it settles, so leaving never asks anything and never discards anything. Exiting shows the toast `DECOR_EDIT_DONE_TOAST` ("The garden looks lovely") only if something changed. The app always resumes in play mode.

**While in edit mode:**
- Mosslings keep living their lives but are not world targets. They glance at a held piece (look-at, as on a tap) and a friend at a spot that a piece is carried past may give a small chirp (`voice_step`, no affection).
- Beds, props and the brook are not targets. A press on them counts as ground: a tap there is a destination, a drag there pans.
- F1 wish spawn checks pause and wish bubbles dim to 45 %.
- Ambient watch and its auto-hide timer are off.
- The sim keeps running: gifts arrive, flowers open, and the toasts queue until exit.

---

## 3. Gestures and input arbitration (ARCHITECTURE §3.4–3.5, `scripts/main/world_pan.gd`)

### 3.1 Gesture table

| Where | Gesture | Play mode | Edit mode |
|---|---|---|---|
| Pinwheel / lantern | tap | `tap_fx` (spin burst / brighten), unchanged | select / deselect |
| Cairn, toadstool, stone | tap | **new:** a small wobble (squash 0.94 on `press`, S01, TICK). A tiny delight, prio 1 | select / deselect |
| Any movable piece | long-press 450 ms | **enter edit, piece held** (the tap never also fires) | same as a press (nothing extra) |
| Any movable piece | drag > 24 px | pans the map (cancels the long-press) | **moves the piece** (drag claimed at press) |
| Mossling | tap / long-press / stroke | unchanged (chirp / pet / pet) | ground |
| Bed | tap / long-press | unchanged (sway / bed card) | ground (a destination tap gives the flowers hint) |
| Prop, brook | tap | unchanged | ground |
| Empty ground | tap | nothing (double tap = glide home) | with a selection: **move it here**. Without one: a soft touch ring and the hint again. A double tap glides home only when nothing is selected |
| Empty ground | drag | pan | pan |
| Near a side edge (< 24 dp) | press on a piece | taps work, no pan starts | select only, no drag (I2 edge rule). Tap-then-tap or pan first |
| Held piece | carried within 40 dp of a side edge | — | the map edge-pans gently (§3.3) |
| Tray tile | tap / drag out | — | in hand / held |
| Top bar | tap | gear, eye | Undo, Done |

### 3.2 Arbiter changes (Engine Programmer)

1. **Play mode.** `DecorLayer.world_hit` keeps pinwheels and lanterns at `PRIO_DECOR` 3 (64 dp hit, 20 dp core). It adds cairn stacks, toadstools and stones as **still pieces** at a new `PRIO_STILL = 1` (60 dp hit, 20 dp core; `hit.prio_still_piece_play`). A still piece never outranks a mossling, a prop, a ready bed or a bed. A stone beats the brook only through its core (tier 2 against the brook's tier 2, then the nearer centre). This change makes every movable piece long-pressable without stealing presses.
2. **Mid-press drag claim.** New `WorldPan.claim_drag()`, callable by the pressed target while the finger is down and still within the slop: it sets `_target_drag = true` and disarms the pan. DecorLayer calls it when its long-press timer fires (the same 450 ms timer pattern as `PlotsLayer`). Later motion arrives as `world_drag(key, pos)` and the release as `world_release(key, pos, true)`.
3. **Edit filter.** While `DecorEdit.active`, `WorldPan.resolve` asks only nodes in a new group `world_hit_edit` (the DecorEdit controller). Its candidates have `prio 8` (+1 for the selected piece), a 60 dp hit circle (64 dp in the look zone) around the piece's **visual centre** (`visual_centre_dy_dp`), clipped above the dock, and `drag: true`, except for presses that start within 24 dp of a side edge.
4. **Ground taps.** New signal `WorldPan.empty_tapped(canvas_pos)`, emitted on every empty tap within the slop (the double-tap logic is unchanged). DecorEdit uses it as "tap a destination".
5. **Edge pan.** New `WorldPan.nudge(delta_px)`, which moves the pan inside the rest bounds (no rubber band, no glide) and pokes the FrameGovernor.
6. **One target per press and release-to-fire** hold as before. A sheet cannot open in edit mode (the dock is hidden), and `blocked` still guards cards (a new-friend card that rises mid-drag takes the touch: the held piece settles where it is, or floats home if that spot is invalid).

### 3.3 Feel of a drag

- **Press (same frame, I1).** The piece lifts: scale 1.08 and rise 6 dp on `press`, its contact shadow grows ×1.25 and softens. S35 plays with a TICK.
- **Carry offset.** Over the first 120 ms of the drag, the piece's foot eases to **24 dp above the contact point**, so the thumb never hides the foot ring or the snap marker.
- **Lean.** The piece leans up to 6° into its motion on `follow` (secondary motion, V5: no shake).
- **Magnet.** Within 14 dp of a snap socket, the piece is pulled toward it (smoothstep, at most 70 % of the way, so the finger always stays in charge). The socket shows a sparkle dot, and entering a socket gives S36 with a TICK, at most once per 150 ms.
- **Validity, live.** The foot ring is `leaf` at 3 dp when the spot is valid. When it is not, the ring becomes a dashed `ink_2` ring and the piece fades to α 0.7 with a slight lean back. After 150 ms of being invalid (no flicker), one hint bubble names the reason (§4.3). Never red, never a buzz, never a screen shake.
- **Keep-clear halos.** Only while a piece is held, the beds' soil ellipses, the always-on spots and the built nests show soft `ink` @ 0.10 halos, and when a stone is held the water line glows faintly.
- **Edge pan.** After 250 ms within 40 dp of a side edge, the map pans toward that side, up to 220 dp/s and easing in with depth (half that under Reduce Motion), and stops at the rest bounds. The pan wings (x −0.30 … 1.30) are placeable, so a garden can spread beyond the home view.

---

## 4. Validity rules (`decor_placement.json: area, water, clearances, sets`)

Every rule uses the piece's **foot** (its ground contact) and its `footprint_r_dp`. Distances are in dp (1.0 frame x = 360 dp, 1.0 y = 640 dp).

### 4.1 Rules for a new drop

1. **Ground.** `x_min ≤ x ≤ x_max` (−0.30 … 1.30, inside TerrainMath's −400 … 1480 px with a 25 dp margin). The foot lies below the `ground_top` polyline (the hollow's walkable rim: about 0.355 on the hill crest and 0.40 at the edges; the Env Artist confirms it against the meadow mask, Q5). The foot lies above `ground_bottom_y` 0.785, the tend zone's bottom, so nothing is placed under the dock.
2. **Water.** Stream stones: the foot lies within the water band (distance to `spots.json stream.polyline` ≤ half the water width, 11.5 dp), so stones run x ≈ 0.24 … 1.30, wherever the water sits above 0.785. Every other set keeps its footprint out of the water plus 2 dp of bank.
3. **Beds.** The footprint stays out of each bed's **soil ellipse** (42 × 22 dp radii) plus 4 dp, and 8 dp from each `nibble_point`. This is the soil, not the 90 × 63 dp hit rect: lanterns may stand at a bed's lower rim as they do today, because the bed's core still wins its taps (GDD §2.5).
4. **Spots.** The footprint stays 10 dp from the centre of every **always-on** spot. Gated spots (`requires_item`) are derived from décor clusters (§7) and are not exclusions.
5. **Nests.** The foot stays 12 dp from the centre of a **built** nest, so the nest stays visible and tappable. Nests are friends' homes and look lovely among décor (the Puddlewump nest sits on the stepping stones), so they are not area exclusions.
6. **Props.** The footprint stays out of each prop's ground ellipse plus 4 dp (`clearances.props`: the ellipse sits `cy_dp` below the prop's visual centre). The basket and the mailbox use their 64 dp tap circle with gap 0: a piece may touch the ring, but its tap core never enters it.
7. **Tea nook (F2).** A circle of `tea.json nook.f3_exclusion_radius_dp` (40 dp), when F2 is on. Hard.
8. **Other pieces.** Same set: centres at least `same_set_min_dp` apart (pinwheel 12, toadstool 8, stone 12, lantern 16, cairn stacks 20; a cairn drop within 14 dp of a stack **merges** onto it, §8.2). Different sets: footprints at least 4 dp apart.
9. **Hit targets** (I2, §8.4 GDD). These follow from the rules above: edit targets are 60 / 64 dp circles. In play, pinwheel and lantern cores keep their 20 dp, and still pieces are prio-1 targets that never block anything above them. Décor-to-décor overlaps are resolved by the nearest centre, as today.
10. **Sign anchors** (Retention v1) never block décor. A sign whose anchor is covered picks its next free anchor of the same type (contract, §15).

### 4.2 Hard rules and grandfathering

`hard: true` props (sun stone rock, basket, mailbox, stump) and the tea nook also apply to **migrated** pieces (§13). Every other rule applies to new drops only. A legacy piece keeps its position even where it sits closer than these numbers (e.g. stone #9 against the spring rock, pinwheel #7 beside the toadstool ring), and it is checked again only if it is moved. Checked against `spots.json` today (scratch check of all 60 anchors): only pinwheels `anchors[4]` (0.800, 0.405) and `anchors[8]` (0.830, 0.378) (0-based) break a hard rule (the F2 tea nook), and the migration nudge finds valid ground 8 dp and 32 dp away. This resolves the overlap that F2 flagged in `tea.json nook.note`.

### 4.3 Soft hints (one at a time, in priority order)

| Reason | Key | en |
|---|---|---|
| over the sky / beyond the rim | `DECOR_HINT_SKY` | Pieces like to sit on the ground |
| under the tend zone | `DECOR_HINT_LOW` | A little higher up |
| beyond x_min / x_max | `DECOR_HINT_EDGE` | A little further in |
| non-stone in water | `DECOR_HINT_WATER` | Only stream stones like the water |
| stone on dry ground | `DECOR_HINT_DRY` | Stream stones like to sit in the water |
| bed or nibble point | `DECOR_HINT_FLOWERS` | Let's leave the flowers a little room |
| always-on spot | `DECOR_HINT_SPOT` | A friend likes to rest here |
| built nest | `DECOR_HINT_NEST` | This is {name}'s nest |
| prop / tea nook | `DECOR_HINT_PROP` | Something already sits here |
| other pieces | `DECOR_HINT_CROWDED` | A touch more room between pieces |
| a stack at 10 | `DECOR_HINT_STACK` | The cairn is as tall as it gets |
| floated home | `DECOR_HINT_RETURNED` | It went back to where it was |

### 4.4 Releasing on an invalid spot

1. Search for valid ground within 48 dp, in rings 4 dp apart, starting nearest the drop. The nearest valid point wins, and among equals the snap socket wins.
2. If found, the piece glides there on `move` and settles (a valid commit).
3. If not, the piece floats back to its origin on `move` (S35 reversed, no S11), shows `DECOR_HINT_RETURNED`, and commits nothing. A piece taken from the tray floats back into the tray.

---

## 5. Soft snapping and beautify (`snap`, `beautify`)

### 5.1 Snap sockets

Sockets are computed once when a hold starts (≤ 300 points, so nearest-socket lookup each frame is trivial). The **magnet radius is 14 dp**. Without a socket in reach the piece stands exactly where it is dropped: free placement is real, and sockets only help.

| Socket family | Sets | Where |
|---|---|---|
| `same_set_ring` | all | 8 directions around each placed piece of the same set at `preferred_spacing_dp` (pinwheel 22, cairn 26, toadstool 16, stone 14, lantern 36) |
| `ring_around_cluster` | toadstool | a cluster of ≥ 3 toadstools (link 30 dp) offers 10 sockets on a 16 dp-radius ring around its centroid (the fairy ring forms anywhere) |
| `water_line` | stones | the brook polyline sampled every 14 dp |
| `bank_line` | lantern, cairn | the polyline shifted 22 dp up (the far bank where the lanterns stand today), sampled every `preferred_spacing_dp` |
| `legacy_anchor` | all | the authored `spots.json decor_anchors` positions: the hollow's original "good spots" keep acting as gentle memories |
| `spot_side` | pinwheel, lantern, cairn | 26 dp left, right and diagonally below each always-on spot, the "cosy corners" (useful for F1 `decor_near` wishes) |

A socket is only offered if it is valid for the held piece. Ties go to the family order in `snap.priority`, then to the one nearest the finger.

### 5.2 Beautify on settle (silent, never a message)

- **Jitter.** ±1.5 dp, seeded by `hash(piece_id, x_dp, y_dp)`, so lines never look ruled and a re-drop on the same spot looks the same.
- **Depth.** `DecorLayer.depth_scale(foot.y)` re-applies, so a piece carried up the slope shrinks smoothly while held. Y-sort follows.
- **Face the cluster.** A dropped pinwheel or lantern takes the rotation step most common in its cluster, unless the player turned it during this session.
- **Clusters come alive.** `ring_forms` (≥ 3 toadstools within link distance: 6 glow motes at dusk and night around the cluster centroid), lantern pools (≤ 8, `LampRegistry`), the brook reflection (only within 40 dp of the water), stone riffles (`BrookLayer.set_stone` at the new foot), and pinwheel spin, which already varies with position (`gust_at_pos`).
- **Odd-cluster aesthetic** (05 §4). It is expressed only through the sockets (rings of 8 and line spacing), never as advice.

## 6. Rotation

`rot` is a step `0 … rot_steps − 1`, stored per piece. Rendering is by stamp flip, x-squash or variant (`sets.*.rot_render`), because the art is 2D tone-mask stamps (Art Bible §6.6):
- **pinwheel:** front, ¾ right (squash 0.72), back (blade colours swapped), ¾ left.
- **lantern:** crook left or right.
- **stone:** flip.
- **toadstool:** flip × two cap-spot patterns (Art: one extra region).
- **cairn:** each turn re-seeds the pebble offsets and tilts (±4 px, ±5°), so the stack is "rebalanced".

Signals carry `rot_deg = step × 360 / rot_steps` (for F1).

---

## 7. Attraction, snug and derived spots

- **Counting is unchanged:** `requires`, `likes_items`, snug and spot gating all count **owned copies, placed or tucked away**. Putting a piece away is tidying, not giving something up (E1). Friends never react badly, and `tools/sim/economy_sim.py` stays byte-identical (parity holds by construction). The Garden card copy says so: `GARDEN_ARRANGE_DESC` "Friends still love everything you own."
- **What uses placed pieces:** the visual fx (§5.2), F1's `decor_near` and `owned:{decor}` wish gates (`Game.decor_placed_count(set)`), and the creature brain flavour. A friend that likes a set picks wander and rest targets within 60 dp of its pieces ×1.5 more often. This lives in the brain, not the sim, so it adds nothing to the economy.
- **Derived spots** (`derived_spots`). The four gated spots still exist while owned ≥ `requires_min` (so the validator's "a species' favourite spot exists whenever it can visit" still holds). Their **position** comes from the placed pieces:
  - `toadstool_ring`: the centroid of the largest cluster of ≥ 3 toadstools (30 dp link).
  - `stream_stones`: the middle stone of the largest cluster of ≥ 3 stones (24 dp link).
  - `lantern_nook`: beside the largest cluster of ≥ 3 lanterns (60 dp link), offset (−14, +8) dp.
  - `cairn_side`: 24 dp right of the tallest stack of ≥ 3 pebbles.

  Fallbacks, in order: the centroid of all placed pieces of the set, then the authored `spots.json` position (for example, when everything is tucked away). A derived position that breaks a hard rule or sits within 20 dp of another spot steps along its offset (4 dp steps, at most 24 dp), else it uses the authored position. Spots are recomputed on edit-mode exit and on load, never mid-drag. A friend resting on a spot that moved stands up and walks to the new place (brain `walk_to`, no affection change).

---

## 8. Storage tray

### 8.1 Layout (px at H = 1920)
- The tray replaces the dock while editing: the dock exits, and the tray rises 48 px on `standard`.
- **Glass:** HUD faux glass (`hud_glass` 0.90, e2), r-xl 96, at x 72–1008 × y 1505–1757 (936 × 252). The bottom stays 36 px above max(safe bottom, 127), like the dock. The caption `DECOR_TRAY_TITLE` ("Tucked away", Caption 36, ink) sits above its left shoulder.
- **Tiles:** one per set with pieces stored. Each is 216 × 216 (72 dp), `surface_hi` (no glass on glass), r-m 48, with 24 px (8 dp) gaps from x 90. The tray scrolls horizontally, a partly visible fourth tile shows there is more, and a 48 px edge fade marks the scroll. Each tile holds a live mini-render stamp (144 px) and a count pill `DECOR_TRAY_COUNT` "×3" (Caption 36, ink on `leaf_tint`; no badge, never red).
- **Empty tray:** one wide dashed well (2 dp `ink` @ 0.10) with `DECOR_TRAY_EMPTY` ("Pieces you put away rest here.").
- **Drop target:** the whole tray rect, grown 12 dp. While a held piece hovers over it, a `basket_glow` halo shows, the tray lifts 6 px on `pop`, and the hint reads `DECOR_TRAY_DROP` ("Put it away here").

### 8.2 Behaviour
- **Put away:** one piece goes into its set's tile. A cairn stack puts away all its pebbles (one Undo restores the whole stack).
- **Take out:** drag a tile more than 10 dp in any direction and one piece pops out under the finger as a HELD piece. The tray's scroll uses its 30 px deadzone, and a mostly horizontal drag scrolls the tray until the finger leaves the tray rect, which hands the drag to the piece. Or tap a tile: it rises 12 px with a 3 dp `primary` ring (**in hand**), the hint becomes `DECOR_EDIT_TRAY_HINT`, and a chip offers **Find a spot** (auto-place, §12). The next ground tap sets it down.
- **Cairn:** a taken-out pebble is a new stack of 1 and merges if dropped within 14 dp of a stack. The selection chip on a stack adds **Lift a pebble**, which takes the top pebble into the hand.
- The tray holds any number of pieces. A tucked-away piece keeps its id, so a later Undo or take-out restores the same piece.

## 9. Undo and auto-save

- **Undo, one step** (`undo`). The round Undo button in the top bar reverts the last commit within this edit session: a move or glide, a turn, a put-away, a take-out, a lifted pebble or a stack merge. The piece glides back on `move`, the a11y label reads `A11Y_DECOR_UNDONE`, and the button greys out (icon ink @ 0.35; pressing it then gives the soft S11 tok and does nothing). There is no redo. Exiting clears the step. Nothing in edit mode is destructive, so Undo is a convenience, not a safety net.
- **Auto-save.** Every commit (a settled drop, a turn, a put-away, a take-out, an undo) writes `WorldState.decor_layout` and calls `SaveService.request_save()` (debounced 2 s, ARCHITECTURE §6). A pause saves through `Game._suspend()` as always. No "Save" button and no unsaved state exist. A piece mid-drag when the app pauses settles first (or floats home if invalid), then the save runs.

## 10. Accessibility

- **No-drag path (I3, WCAG 2.5.7):** tap a piece (select) → tap a spot on the ground (it glides there in 332 ms, snaps, or uses the §4.4 nudge) → Turn / Put away from the chip. For the tray: tap a tile → tap the ground, or "Find a spot". Entering edit mode needs no long-press (the Garden sheet "Arrange" row).
- **Targets:** edit pieces 60 dp (64 dp in the look zone), chip buttons 60 dp with 8 dp gaps, tray tiles 72 dp, Undo and Done 72 dp. An edit hit that the dock clip shrinks below 48 dp is offered from its visual centre instead.
- **Left-handed:** Undo and Done swap sides, and the chip button order mirrors.
- **Reduce Motion:** no lean, no magnet easing (the piece jumps to the socket with a 300 ms crossfade, V5: no pop-in), glides become 300 ms crossfades, and edge-pan runs at half speed.
- **Text size:** chip and tray labels scale. From 150 % the chip stacks its buttons vertically and the tray tiles grow to 84 dp.
- **Captions:** `CAPTION_DECOR_LIFT / SNAP / SETTLE / TURN / TUCK`.
- **Screen-reader labels (A11Y):** `A11Y_DECOR_PIECE` (play: "{decor}. Touch and hold to move"), `A11Y_DECOR_PIECE_EDIT`, `A11Y_TRAY_TILE`, `A11Y_DECOR_UNDO`. Spoken results: `A11Y_DECOR_MOVED` ("{decor} now sits near the {spot}", using the nearest spot's name), `A11Y_DECOR_STORED`, `A11Y_DECOR_TURNED`.
- **Desktop and web:** the mouse behaves like touch. Optional keys in edit mode: arrow keys move the selection 8 dp, R turns, Backspace puts away, Ctrl/Cmd+Z undoes, Esc means Done.

---

## 11. Edit-mode chrome (px at H = 1920, T = 120; Art Bible §9)

| Element | Spec |
|---|---|
| **Undo** | Faux glass circle Ø 120 at x 48–168, y 144 (the gear's slot), with a curved-arrow icon 72. Hit 216 × 216 (x 0–216, y 144–360). Disabled: icon @ 0.35 |
| **Banner** | Faux glass pill h 96 at x 240–744, y 156–252, `DECOR_EDIT_TITLE` ("Arranging the garden", Label 42, ink). Passive, but the top-bar band consumes presses as today |
| **Done** | Primary pill 264 × 120 at x 768–1032, y 144–264, `DECOR_EDIT_DONE` (Label 42, Nunito 800, `surface_hi`). Hit x 744–1080 × y 144–360 |
| **Context hint** | Toast-style faux glass pill h 96, Label 42, centred at y 400. Shows `DECOR_EDIT_HINT` on entry (4 s), `DECOR_EDIT_SELECTED_HINT` on selection, `DECOR_EDIT_TRAY_HINT` with a tray piece in hand. Never stacks with an invalid hint (that one wins) |
| **Selection chip** | `surface_hi` pill, e1. Round buttons Ø 156 (hit 180 = 60 dp, 24 px apart) with Caption labels under them: **Turn**, **Put away**, plus **Lift a pebble** (stack) or **Find a spot** (tray piece). It sits 36 px above the piece's top, or below its foot if that would cross y 400. It is clamped to x 24–1056, never covers the tray, follows the piece on `move`, hides while the piece is held, and returns on settle |
| **Piece states** | Idle: a 2 dp colour line at the foot ellipse @ 0.5, breathing at k 200 (the "I can be moved" affordance, Art Bible §9.2 colour line rule). Selected: 3 dp `primary` @ 0.7 ring, raised 3 dp. Held: §3.3 |
| **Origin ghost** | While held, the piece's stamp at α 0.22 at its origin (where Undo and "float home" go) |
| **Snap marker** | Sparkle dot 12 px (`surface_hi`, `halo_add`), at most 8 nearest sockets shown at α 0.35, the active one at 1.0 |
| **Tray** | §8.1 |
| **Night chrome** | As the dock: dim glass, `night_ink` labels, `night_capsule` tiles |

**Draw calls:** the edit chrome uses ≤ 6 (tray glass 1, tiles batched via `UiBatch` 1, chip 1, banner and Done/Undo 2, markers and halos 1). Décor itself stays ≤ 20 (§14).

## 12. Placement when buying, and "Find a spot" (`auto_place`)

When a copy is bought, nothing new is asked: the piece pops in as today (fade 300 ms + `pop` 0.6 → 1 + dust puff + S05). Its position comes from this order:
1. Its legacy anchor `anchors[n]`, if valid and free.
2. The best socket near the set's largest cluster.
3. A spiral search from `anchors[0]` (8 dp steps, up to 200 dp).
4. The tray, only if no valid ground exists (practically never). The Garden card then shows `GARDEN_TUCKED_AWAY`.

"Find a spot" in the chip uses steps 1–3 for a tray piece. The Garden item card gains a caption `GARDEN_TUCKED_AWAY` ("{count} tucked away") when some copies are stored. "{owned} of {max}" and "All placed" keep meaning owned.

## 13. Save schema and migration (`migration`)

New `WorldState` fields (additive; the Director merges the F1/F2/F3 bumps into one schema 3):

| Field | Type | Meaning |
|---|---|---|
| `decor_layout` | Array[{id: String "set#n", set: String, x: float, y: float, rot: int, stored: bool, stack: String ("" or the base piece id, cairn only), level: int (cairn only)}] | One entry per owned movable copy. x and y are frame-normalized foot positions (x may be < 0 or > 1) |
| `active_v` | int | Shared Active Play migration version (GDD §14.9; replaces the proposed `decor_layout_v`): 0 = not migrated, 1 = v1 |

**Migration** (`DecorPlacementRules.migrate_v1`, run once from `WorldSim._init` when `active_v < 1` as part of `ActiveRules.migrate_v1`, content-aware like `RetentionRules.migrate_v1`):
1. Copy *n* of each set takes `anchors[n]` verbatim, with rot 0 and placed.
2. The lantern jitter (`LANTERN_JITTER_PX`, seeded by `hash(["firefly_lantern", n])`) is baked into x. **Nothing moves on screen** (test: ≤ 0.5 px).
3. Cairn: all copies form one stack at `anchors[0]`, in copy order. Chime: not in the layout (not movable).
4. The hard rules nudge a piece (today pinwheels #4 and #8, out of the F2 tea nook by 8 and 32 dp). Everything else is grandfathered.
5. Owned copies missing from the layout (e.g. bought on an older build after migration) are auto-placed on load.

Migration never removes or overwrites keys and never changes `owned`. An old `.bak` migrates the same way.

## 14. Budgets and performance

- **Décor draw calls ≤ 20** (Art Bible §4.19 "props + décor ≈ 20", global ≤ 100). Pinwheels keep one node each (they spin). Static pieces (stacks, toadstools, stones, lanterns) merge into one stamp per (set, 16 dp y band) so y-sort with creatures stays right. If the total would pass 20, the nearest bands of a set merge (a few dp of y-sort imprecision against a passing mossling is acceptable). The held piece has its own stamp (+1) until it settles.
- **Particles:** unchanged (fireflies bias to lantern positions, D9 ≤ 3 systems).
- **CPU:** validity is O(5 beds + 13 spots + 12 nests + 6 props + 60 pieces) per frame while held. Sockets are built once per hold (≤ 300). FrameGovernor is poked while dragging and held for the settle (`move` 332 ms).

## 15. Contracts

### With F1 Wishes (`ACTIVE_WISHES.md` §11): confirmed
| Need | F3 provides |
|---|---|
| Feature flag | `Game.feature_on(&"free_decor")` |
| Décor placed | signal `Game.decor_placed(set: StringName, piece_id: String, pos_norm: Vector2, rot_deg: int)` after the settle (move, glide, take-out, undo, and turn); never during a drag |
| `decor_near:<set>` | `DecorPlacementRules.nearest_piece_dp(set, pos_norm) -> float` (placed pieces only); `near_dp` 120 is F1's number (mirrored in `attraction.near_dp_for_wishes`) |
| `owned: {decor: k}` gate (placed) | `Game.decor_placed_count(set)`; attraction itself keeps owned counts (§7) |
| Stream-stone area | `water_line` sockets (polyline sampled every 14 dp, x ≈ 0.24–1.30). Every stream-side favourite spot (stream_bend at 18 dp from the water; derived stream_stones and lantern_nook) is ≤ 120 dp from one, so the validator check for `stones_nearby` holds |
| Edit mode vs wishes | `DecorEdit.active` + signals `decor_edit_entered` / `decor_edit_exited`: F1 pauses spawn checks and dims bubbles to 45 %. Long-press on décor is F3's; on a mossling it stays petting |

### With F2 Tea & Treats
| Need | F3 provides |
|---|---|
| Tea nook on the stump | a hard exclusion circle from `tea.json nook.f3_exclusion_radius_dp` (40 dp) when F2 is on. Legacy pinwheels #4 and #8 are nudged on migration (§13), which resolves `tea.json nook.note` |
| Teapot / teaware | not décor; not movable in F3 v1 |

### With Retention v1 (Director: RetentionRules owner)
- **Sign anchors yield:** a sign whose anchor lies under a footprint + 4 dp takes the next free anchor of its type. F3 offers `DecorPlacementRules.is_clear(pos_norm, radius_dp)`.
- **A nest built later never moves a piece.** If a footprint covers the nest centre, NestRules shifts the nest by up to 24 dp to clear ground (Q3).

## 16. Implementation map (for the engineers; not built here)

| Piece | File (proposed) |
|---|---|
| Pure rules: validate, sockets, snap, nudge, auto-place, derived spots, migrate, undo op | `scripts/sim/decor_placement_rules.gd` (static, no nodes, unit-tested) |
| Edit controller: state machine, edit hit group, chip, hints, tray hand-off | `scripts/garden/decor_edit.gd` + `scenes/garden/decor_edit.tscn` |
| Layer changes: positions from `decor_layout`, still-piece hits, long-press, banded merge, rot render | `scripts/garden/decor_layer.gd`, `decor_kit.gd` |
| Arbiter: `claim_drag`, `empty_tapped`, `nudge`, edit filter | `scripts/main/world_pan.gd` |
| Tray and top-bar chrome | `scripts/ui/decor_tray.gd`, HUD controller |
| Garden sheet row and caption | `scripts/ui/garden_sheet.gd` |
| Content load | `GameContent` reads `decor_placement.json` |
| Validator | `tools/sim/validate_content.py`: schema; every décor id has a `sets` entry; `rot_render` length = `rot_steps`; `ground_top` x-sorted; hint keys exist; each legacy anchor is hard-valid or nudgeable ≤ 48 dp; derived spots resolvable at their authored fallback; the F1 stones check |
| Tests | rules unit tests (validity table, magnet, nudge, merge, undo); migration fixture from a schema-2 save (positions within 0.5 px); `--qa-decor-edit=<enter / hold_valid / hold_invalid / tray / chip>` render captures; `--debug-hits` shows edit targets (≥ 48 dp floors, 8 dp gaps) |
| Docs to amend on ship | GDD §2.5 ("grow at fixed anchors" → "start at the anchors, movable"), §8.1 (Arrange row), §8.2 (long-press list), §8.3 (feedback rows below), §8.7 (`{decor}` placeholder); ARCHITECTURE §3.5 (prio 8 / prio 1, `claim_drag`); `decor.json` doc string |

**Feedback map additions** (GDD §8.3):

| Event | Visual (≤ 100 ms) | Sound | Haptic (Subtle / Full) |
|---|---|---|---|
| Tap a still piece | wobble, squash 0.94 | S01 | — / TICK |
| Long-press → edit | ring fill, then chrome rises and the piece lifts | S35, S07 | — / TICK |
| Lift in edit | scale 1.08, rise 6 dp, shadow grows | S35 | — / TICK |
| Enter a socket | sparkle dot brightens, magnet pull | S36 | — / TICK |
| Invalid spot | dashed `ink_2` ring, α 0.7, hint after 150 ms | none (S11 only on a disabled button) | — |
| Settle | `move` settle + 4-mote dust puff | S05 | TICK / TICK |
| Turn | `pop` turn + 2 dp hop | S37 | — / TICK |
| Put away / take out | shrink into the tile / pop out | S38 / S35 | — / TICK |
| Done | chrome exits, HUD and dock return | S08 | — |

Cue ids assigned centrally (GDD §14.8): S35 lift, S36 snap, S37 turn, S38 tuck (S26–S27 are Active F1, S28–S34 Active F2).

## 17. Strings (`i18n/staging_decor.csv`, 45 keys)

- **Edit chrome:** `DECOR_EDIT_*` (title, three hints, Done, Undo, Turn, Put away, Lift a pebble, Find a spot, the done toast).
- **Tray:** `DECOR_TRAY_*`.
- **Hints:** twelve `DECOR_HINT_*`.
- **Tip:** `DECOR_TIP_LONG_PRESS`.
- **Garden sheet:** `GARDEN_ARRANGE`, `GARDEN_ARRANGE_ROW`, `GARDEN_ARRANGE_DESC`, `GARDEN_TUCKED_AWAY`.
- **A11Y:** eight `A11Y_DECOR_*` / `A11Y_TRAY_TILE`.
- **Captions:** five `CAPTION_DECOR_*`.

**New placeholder: `{decor}`** (a décor set's name, `DECOR_*_NAME`); add it to GDD §8.7. `{name}` in `DECOR_HINT_NEST` is the friend's name, and `{spot}` is a `SPOT_*` name. The vi strings use the UI's soft imperatives with *nhé*. They avoid *mất*, *sai* and *lỗi*. Stored pieces are *cất* ("tucked away"), never "removed".

## 18. Open questions for the Director

1. **Attraction counts owned, not placed (§7).** Recommended (E1, sim parity, and tidying never costs a friend). The alternative (placed only) would need an economy_sim change and could make a friend stop visiting after a tidy-up.
2. **Wind chime hang points.** Keep it on the willow branch in v1, or add rails (the stump's side branch, a lantern crook) in v2? It needs Env art and Sound (notes stay owned-based either way).
3. **Nests vs décor.** Is NestRules allowed to shift a not-yet-built nest by up to 24 dp when a piece covers its anchor (§15)? The alternative is reserving nest anchors, which reveals future nests and blocks space the player cannot see a reason for.
4. **Still-piece taps (prio 1).** Making cairns, toadstools and stones tappable (a wobble) is needed for long-press entry. It slightly reduces empty ground for the double-tap home within 30 dp of them. OK?
5. **`ground_top` and the wings.** The Env Artist should confirm the walkable rim polyline and that the meadow reads well with décor at x < 0 and x > 1 (seen only when panned on phones, always on wide screens).
6. **Schema.** One combined bump for F1 + F2 + F3 (schema 3), with each feature's own content-aware `migrate_v1` step?
7. ~~Sound ids~~ resolved: S35–S38.
