# Active play F2: Tea & Treats

*Game Designer (F2) · 2026-10-22 · status: **accepted with lead changes** (GDD §14, 2026-10-22) · numbers in `data/tea.json` (it wins if the two disagree) · strings merged into `i18n/strings.csv` (156 keys, en + vi, NFC, E8-linted).*

> **Lead integration (GDD §14) supersedes this document where they differ:** sound ids renumbered to S28–S34 (teaware placing reuses S05); the offering credit is **once per friend per 20 h** (`offering.affection_rest_s` 72,000, clock `tea_aff_t`) instead of once per visit, so `present[].tea_credit` is dropped; teaware prices raised to 150–4,500 (14,850 dew in total) as the main post-catalogue dew sink; pinwheel anchors are named 0-based (`anchors[4]`, `anchors[8]`) and are nudged by the Active F3 migration; the greeter may bring its held Active F1 wish and can be offered tea (0 affection); a cup that grants a wish stacks with the wish point (§14.6).

Sibling features: **Active F1 Wishes** and **Active F3 Free décor placement**. They are named "Active F1/F3" here so they are not confused with Retention v1 F1–F3 (GDD §13).

## 0. One paragraph

Bloomed flowers grow **spare petals** that you gather with a tap on the bed. The flower is never harmed. Petals go into a **petal pantry**. At the **tea nook** (a small teapot on the stump) you drag petals into the pot, add a dew drop or two if you like, **stir** in a slow circle and **tilt to pour**. Each mix makes a tea or a treat. 22 named recipes and 2 "any mix" recipes are written into a **recipe book** as you find them. You can **offer** a cup to a visiting mossling, and it reacts: it sips happily, likes the cup or loves it. Every offering gives affection toward the existing hearts. Loved cups give more, and the friend tucks a few petals back into your pantry. Cups also fulfil **tea wishes** (Active F1). Nothing in tea can fail, cool down, spoil, time out or run away.

Pillars served: every step is optional and gives a soft response within 100 ms (I1), it is relatedness through care (E7), and it is abundant (E5). Tea is fully deterministic: there is no randomness anywhere in it.

## 1. Cozy guarantees (binding)

| # | Guarantee | How it holds |
|---|---|---|
| T1 | Harvesting never harms a flower | A stem stays bloomed. Its `dew_per_hour`, snug and attraction counts are unchanged (`harvest.harms_flower: false`, `affects_dew_or_attraction: false`). The only visual change is that the loose petals resting on the leaves lift off |
| T2 | Nothing decays | Petals, cups and treats never cool, wilt or spoil. A cup on the tray stays warm forever (`tray.cups_never_cool`) |
| T3 | Nothing is discarded | When a jar is full, gathering simply stops for that flower and the petals wait on the flowers. Petals taken back out of the pot return to the pantry. Dew drops taken out are refunded. Pot contents and stir progress survive closing the sheet and the app |
| T4 | No fail and no timing | Any mix makes something (fallbacks). No step times out (`no_step_ever_times_out`). The stir counts any speed and either direction. A pour released early springs back |
| T5 | No guilt | No friend ever dislikes a cup. The lowest reaction is "sips happily", which still gives +1 affection |
| T6 | Every gesture has a tap alternative | Tap a jar to add a petal, the Stir button (+180° per tap), the Pour button, or **Simple brewing** (one tap). Simple brewing is on by default under Reduce Motion |

## 2. Harvesting petals

### 2.1 Rules ⟲ `tea.json: harvest, petals`

- **Which stems:** only stems at the **bloom** stage. A stem holds at most `petal_hold_per_stem` = **2** spare petals.
- **Regrow:** a stem grows one petal every `petal_regrow_s` of world time (it keeps running offline):

| Flower | Regrow (s) | ≈ | Jar cap |
|---|---|---|---|
| sweet_clover | 1800 | 30 min | 24 |
| button_daisy | 2400 | 40 min | 24 |
| buttercup | 2700 | 45 min | 24 |
| forget_me_not | 3600 | 1 h | 24 |
| bluebell | 3600 | 1 h | 24 |
| primrose | 4500 | 1.25 h | 24 |
| dandelion | 4500 | 1.25 h | 24 |
| moonbloom | 7200 | 2 h | 24 |

- **Pure formula** (no per-step work, offline-exact). Each stem has a petal anchor `pa` (save field `petal_from_t`, default = the stem's bloom time):
  `ready(t) = min(hold, floor((t − pa) / regrow))`.
- **On harvest** of k ≤ ready petals:
  - if ready < hold, then `pa += k · regrow` (the partial progress is kept);
  - if ready == hold (the stem was full and its clock had paused), then `pa = t − (ready − k) · regrow`.
  - A full stem pauses like the brimming dew cup does. Nothing is lost, it just stops adding.
- **Tap a bed = gather all ready petals in that bed,** taken in stem order and limited by each jar's free room. Petals that do not fit stay on their stems (T3).
- Moonbloom petals can be gathered at any time of day: they rest on the leaves even while the flower is closed. There is no time-of-day gate.
- **Tutorial clover:** it uses its own bloom time (90 s) as `pa`.

### 2.2 World presentation and input

- **Petal glints:** a bed with ready petals shows 1 glint per 2 ready petals, at most 3 per bed (`glints_max_per_bed`). A glint is a loose pastel petal resting on a leaf, in the flower's `fl_*` token, with a slow 4 s shimmer (V5). Glints dim to 50 % when that flower's jar is full.
  - Draw calls: glints are drawn by the bed shader (an instance parameter for the count) or by one MultiMesh for all beds. Budget **+1 draw**. Garden/Env team.
- **Tap:** the bed's tap action (release-to-fire, ARCHITECTURE §3.5) is resolved inside the one bed target, in this order:
  1. a ready bud unfurls (existing);
  2. else gather petals;
  3. else the stems sway (S18).
- **Hit priority:** a bed with ready petals uses priority **5**, the same as a ready bud (`bed_hit_prio_with_petals`). This change goes to ARCHITECTURE §3.5 and GDD §2.5. Long-press still opens the bed card. A pan that starts on a bed still pans.
- **Feedback:** on touch-down (same frame) the bed squashes to 0.94 (existing) and S01 plays. On release the petals lift and arc to the tea nook (`gather_fly_ms` 600, 40 ms stagger, `move` spring, no linear tween), S28 plays, haptic — / TICK. The nook's pantry jar on the stump bobs once. The a11y announcement is `TEA_HARVEST_A11Y`.
- **Bed card** (long-press or the info chip) adds the lines `TEA_BED_PETALS` ("Spare petals: 4"), `TEA_BED_NEXT` ("Another petal in about 20 min", good news only, E2) and, when the jars are full, `TEA_BED_RESTING`. The first card ever shown adds `TEA_GENTLE_NOTE`.
- **Mosslings nibbling** at a bed (§4.1.3) are unaffected. Nibbling never touches petals.

### 2.3 Unlock and first time

- **The tea nook appears** when onboarding is done (after the welcome postcard, about 240 s) **and** at least one stem is in bloom (`unlock`). It fades in over 400 ms on the stump with a small steam wisp and S34. The toast `TEA_NOOK_AWAKE` plays once, and the nook twinkles with the standard "something new" sparkle (never a dot) until first opened.
- **First open:** the sheet shows `TEA_FIRST_HINT` above an empty pantry. A ghost-thumb hint loops over the nearest bed with glints in the world after the sheet closes. It stops after the first gather or after 3 loops, and never blocks input.
- **Inside the pot**, each step label (`TEA_STEP_ADD`, `TEA_STEP_STIR`, `TEA_STEP_POUR`) shows a faint ghost gesture the first 3 times only.

## 3. Pantry, pot and tray

- **Pantry** ⟲ `petals[].pantry_cap`: 8 jars, one per flower, at most 24 petals each. Jars for flowers you have never gathered show as empty glass with a soft outline (never greyed or locked). A full jar shows `TEA_JAR_FULL` when tapped from the world and bobs gently in the sheet.
- **Dew drop** ⟲ `dew_drop`: costs **3 dew** from the wallet, charged when the drop goes into the pot and refunded when it is taken out. If the wallet holds less than 3 dew, the drop jar gives the existing "not affordable" response (S11 soft tok, ±2 dp wiggle, `GARDEN_MORE_DEW`).
- **Pot** ⟲ `pot`: 1–3 petals and 0–2 dew drops. Two drops always make a **treat** (`treat_at_drops`), and 0–1 drops make a **tea**. This one rule is easy to learn, and the recipe hints teach it.
- **Tray** ⟲ `tray.slots`: 6 cups or treats. When the tray is full, Pour or Brew says `TEA_TRAY_FULL` (S11 tok, no buzz). The pot keeps its contents.

## 4. Brewing, step by step ⟲ `tea.json: brewing`

The **Brew** tab is a fixed layout with no scrolling. It opens at the sheet's large detent (≤ 80 %), because the pot and two jar rows need about 470 dp. On this tab the sheet's swipe-to-dismiss is taken only from the grabber and header, because the pot area consumes its own drags. Layout at 360 dp wide:

```
┌ header: Tea nook                         [×] ┐
│ [Brew] [Recipes] [Teaware]                   │
│        ╭──────╮            ┌──┬──┐           │
│  spoon │ POT  │  ~150 dp   │c1│c2│  tray      │
│        ╰──────╯            │c3│c4│  2×3 cups  │
│   step label · [Stir] [Pour]│c5│c6│  48 dp     │
│ (C)(D)(B)(F)(L)    pantry row 1, jars 56 dp   │
│ (P)(N)(M)(drop)    pantry row 2, gap 10 dp    │
└──────────────────────────────────────────────┘
```

**Step 1: add (drag petals in).**
- Drag from a jar: past 24 px (`petal_drag_threshold_px`) a petal lifts and follows the thumb. Release anywhere over the pot's drop zone (1.4× the pot, `drop_zone_scale`) and it falls in: S29 plip, pitched up per petal, and a TICK. Release elsewhere and it floats back to its jar (320 ms). That is not a miss, just a float.
- **Tap a jar** to add one petal (it arcs 320 ms). This is the tap alternative.
- **Tap a petal in the pot** to take it out (`TEA_TAKE_OUT_A11Y`). It returns to its jar. Drops work the same way, with the refund.
- A 4th petal or a 3rd drop: the jar bobs, and `TEA_POT_ROOM` shows once as a caption. Nothing is charged.

**Step 2: stir.** The spoon appears once there is at least 1 petal.
- The stir is a circular drag around the pot's centre. Progress is the accumulated |Δθ| up to `stir_target_deg` = **540°** (1.5 turns).
- **Tolerance:**
  - Only motion between 28 and 150 dp from the centre counts (`stir_ring_inner_dp`, `stir_ring_outer_dp`). That ring is far wider than the pot.
  - **Round 8 — the dead middle is the same flat ellipse as the ring.** `stir_ring_inner_dp` is measured in *ring space* (the y axis stretched by the progress ring's aspect, `RING_R` 176 × 64), so the ellipse the player is invited to trace is live all the way round. Measured as a circle, as it was, the ring's own top and bottom — and the whole liquid surface with the spoon standing in it — fell inside the dead radius, so about a quarter of the stroke counted for nothing, and the shorter the phone the flatter the pot and the worse it got. `stir_ring_outer_dp` stays a plain circle: its only job is to ignore motion elsewhere in the panel, and a player who stirs a wide round circle instead of following the ring must keep every degree.
  - **Nothing about the stir depends on the frame rate.** Both ends of a sample must be in the ring, and the straight line between them must miss the dead middle — that is what makes "a scribble through the centre adds nothing strange" exactly true, and it also refuses the cheat the old rule allowed (press on the tea, flick straight out, repeat). What is left is clamped to `stir_max_deg_per_sample` = **170°**, which sits under the ±180° shortest-arc wrap so a thumb that jumps half the pot can never read as a turn the other way. This replaces a flat **45° per motion event**: Godot merges input once per rendered frame by default, so a per-event ceiling was really a frame-rate cap — 2,700 °/s at 60 fps but only 1,350 °/s at 30 fps — and the same brisk stir counted for half as much on a slower phone.
  - The stir is the one gesture in the game whose meaning is the *path* of the thumb rather than its latest position, so while a stir drag runs it holds `InputPrecision` (ARCHITECTURE §3.5): the circle is sampled at the pointer's own rate rather than the frame rate, which keeps the chords short, the swirl smooth and the credited angle equal to the angle actually travelled.
  - Either direction counts, and so do changes of direction. Speed does not matter.
  - Lifting the thumb keeps the progress. The stir drag never pans, scrolls or closes the sheet.
- **Feedback:**
  - The liquid swirls with the thumb and its colour blends from the petals' `fl_*` tokens in three steps (at 180°, 360° and 540°).
  - S30 is a soft loop whose gain follows the stir speed, and a chord-snapped bell sounds every 180°.
  - Haptic — / TICK every 180°. A thin progress ring around the pot fills (`ring_fill` shader).
- **Tap alternative:** the Stir button adds 180° per tap, animated over 600 ms (`stir_tap_alt_deg_per_tap`, `stir_tap_anim_ms`). Three taps finish the stir.

**Step 3: pour.** It is ready when the stir reaches 540°. The pot's handle glows softly.
- Drag the handle down and toward the tray. The pot tilts with the thumb (0–55°).
- Past 30° (`pour_start_tilt_deg`, reached after about 40 dp of travel) the pour plays to its end by itself: `pour_ms` 1200, a stream arcs into the next free cup (or the **leaf mould** for a treat, label `TEA_STEP_POUR_TREAT`), with S31 and a TICK at the end.
- Released before 30°, the pot springs back (`move` spring). Nothing spills.
- **Tap alternative:** the Pour button.

**Reveal.** The result card rises (`emphasized` 500 ms) with the recipe name, the cup or plate in the liquid colour, and the kind chip (Tea or Treat).
- **First time:** a "A new recipe!" stamp (`TEA_NEW_RECIPE`, 900 ms) plays with S33 and MEDIUM / MEDIUM haptics. The card then slides into the Recipes tab icon.
- The cup settles on the tray. In the world, up to 3 cups appear on the nook's cloth (`cups_drawn_max`).
- Input is never blocked: tapping dismisses the card early.

**Simple brewing** (Settings toggle `TEA_SETTING_SIMPLE` / `TEA_SETTING_SIMPLE_DESC`, default = the Reduce Motion value): Step 1 is unchanged (tap jars). Then one **Brew** button replaces stir and pour. The petals dissolve into the cup in a 900 ms cross-fade (`simple_brew_ms`) with S31. Under Reduce Motion the liquid swirl becomes a colour cross-fade and the reveal is a 150 ms fade.

## 5. Recipes ⟲ `tea.json: recipes`

**Match rule.** A recipe matches the exact multiset of petals and the exact drop count. Order never matters. Anything else becomes the fallback for its drop count: *A cup of meadow tea* (0–1 drops) or *Petal sweet* (2 drops). The fallbacks are recipes too, so the first brew always finds something. The book has 24 entries (22 named + 2 fallbacks), and 164 × 3 = 492 pot states are possible.

Petal letters used in the table: C clover, D daisy, B buttercup, F forget-me-not, L bluebell, P primrose, N dandelion, M moonbloom, ● dew drop.

| # | id | en / vi | Mix | Kind |
|---|---|---|---|---|
| 1 | `clover_tea` | Clover tea / Trà cỏ ba lá | C C | tea |
| 2 | `daisy_tea` | Daisy tea / Trà cúc dại | D D | tea |
| 3 | `buttercup_tea` | Sunshine tea / Trà nắng mao lương | B B | tea |
| 4 | `blue_sky_tea` | Blue-sky tea / Trà trời xanh | F F | tea |
| 5 | `bluebell_tea` | Bluebell hum tea / Trà chuông xanh ngân nga | L L | tea |
| 6 | `primrose_tea` | Primrose blush tea / Trà anh thảo má hồng | P P | tea |
| 7 | `breezy_tea` | Breezy tea / Trà gió nhẹ | N N | tea |
| 8 | `moonlight_tea` | Moonlight tea / Trà ánh trăng | M M ● | tea |
| 9 | `meadow_blend` | Meadow blend / Trà đồng cỏ | C D B | tea |
| 10 | `dewy_clover_tea` | Dewy clover tea / Trà cỏ ba lá đẫm sương | C C ● | tea |
| 11 | `twilight_tea` | Twilight tea / Trà chạng vạng | F L M | tea |
| 12 | `sleepy_tea` | Sleepy-time tea / Trà giấc êm | P M ● | tea |
| 13 | `starlight_tea` | Starlight tea / Trà ánh sao | N M ● | tea |
| 14 | `clover_puff_cake` | Clover puff cake / Bánh bông cỏ ba lá | C C C ●● | treat |
| 15 | `daisy_biscuit` | Daisy button biscuit / Bánh quy cúc áo | D D ●● | treat |
| 16 | `buttercup_jelly` | Buttercup jelly / Thạch mao lương | B B ●● | treat |
| 17 | `sky_sugar_drops` | Sky sugar drops / Kẹo trời xanh | F F ●● | treat |
| 18 | `bluebell_candy` | Bluebell candy bells / Kẹo chuông xanh | L L ●● | treat |
| 19 | `primrose_tart` | Primrose tart / Bánh nướng anh thảo | P P ●● | treat |
| 20 | `fluff_cake` | Fluff cake / Bánh bông gió | N N N ●● | treat |
| 21 | `little_moon_cake` | Little moon cake / Bánh trăng nhỏ | M M ●● | treat |
| 22 | `rainbow_jelly` | Rainbow jelly / Thạch cầu vồng | B F P ●● | treat |
| 23 | `meadow_tea` | A cup of meadow tea / Một tách trà đồng nội | any other, 0–1 ● | tea |
| 24 | `petal_sweet` | Petal sweet / Kẹo cánh hoa | any other, ●● | treat |

**Progression falls out of the flower ladder.** Clover tea is possible within about an hour of the nook waking. Moonbloom recipes (5) arrive with the last flower. Moonlight tea, Little moon cake and the moon recipes carry a Trung thu (mid-autumn) warmth in Vietnamese, but they are not seasonal and never leave.

**Discovery.** You discover recipes by experimenting. The book shows every hint from the start (`TEA_R_*_HINT`, for example "Two petals that hold the sun.", "Sky, bell and moon, one of each."), so experimenting is guided. Nothing is hidden behind a gate. `TEA_BOOK_TIP` explains the any-mix rule.

## 6. Species preferences ⟲ `tea.json: species_prefs`

Each friend has 2 **loves** and 3 **likes**. Everything else is "content", never a dislike (T5). Every named recipe is loved or liked by at least one friend. The choices follow each species' personality and flower.

| Species | Loves | Likes | Petals it gives back |
|---|---|---|---|
| puffmoss (sunbather) | sleepy_tea, clover_tea | buttercup_tea, clover_puff_cake, meadow_blend | clover |
| buttonbud (curious, petals) | daisy_biscuit, daisy_tea | meadow_blend, rainbow_jelly, clover_tea | daisy |
| pebblepaw (calm, stream) | blue_sky_tea, twilight_tea | dewy_clover_tea, daisy_tea, sky_sugar_drops | forget-me-not |
| honeyhum (dew sipper) | buttercup_tea, buttercup_jelly | daisy_tea, meadow_blend, clover_puff_cake | buttercup |
| fernwhisk (shy, soft) | sky_sugar_drops, dewy_clover_tea | blue_sky_tea, sleepy_tea, twilight_tea | forget-me-not |
| dandelfluff (dreamy, breeze) | fluff_cake, breezy_tea | starlight_tea, meadow_blend, rainbow_jelly | dandelion |
| bellkin (musical) | bluebell_tea, bluebell_candy | twilight_tea, breezy_tea, blue_sky_tea | bluebell |
| primpip (tidy, polite) | primrose_tea, primrose_tart | rainbow_jelly, daisy_biscuit, sleepy_tea | primrose |
| capling (bouncy) | clover_puff_cake, rainbow_jelly | clover_tea, buttercup_jelly, fluff_cake | clover |
| puddlewump (rain, splashes) | dewy_clover_tea, bluebell_candy | blue_sky_tea, buttercup_jelly, primrose_tea | bluebell |
| glowmote (evening glow) | starlight_tea, moonlight_tea | twilight_tea, little_moon_cake, sky_sugar_drops | moonbloom |
| moonpuff (moon, sleepy) | little_moon_cake, sleepy_tea | moonlight_tea, starlight_tea, clover_tea | moonbloom |

**Revealing loves.** A love or like becomes known when you see the reaction, or automatically at ♥3 (the existing "likes revealed" unlock, `likes_revealed_at_heart`). Album › friend detail gains a "Tea" line, and the book card shows `TEA_BOOK_LOVED_BY` / `TEA_BOOK_LIKED_BY` listing only met friends whose preference is revealed.

## 7. Offering ⟲ `tea.json: offering`

**Flow.**
1. Tap a cup on the tray. The pantry rows swap to the **Offer to a friend** row (`TEA_OFFER_TITLE`): 64 dp portrait chips of the present friends, 8 dp apart. Friends with an open tea wish come first and wear their wish bubble, then friends by hearts (desc). Nobody present: `TEA_OFFER_NOBODY`.
2. Tap a chip. The sheet closes (`exit`), the cup arcs from the nook to the friend (320 ms), the friend sits and sips (pose `sip_tea`, 2.4 s, S32 clink), then reacts.
3. Back or × returns to the pantry rows.

**Reactions** (deterministic):

| Reaction | When | Affection (once per friend per 20 h) | Extra | Copy |
|---|---|---|---|---|
| content | anything else | +1 | a soft purr | `TEA_REACT_CONTENT` |
| liked | in `likes` | +1 | a happy hop, 1 petal of its gift flower into the pantry | `TEA_REACT_LIKED` (+ `TEA_REACT_PETALS`) |
| loved | in `loves` | +2 | `celebrate` delight (≤ 900 ms, hearts, S24-light), 2 petals back | `TEA_REACT_LOVED` (+ `TEA_REACT_PETALS`) |

- **Credit rules:**
  - The affection credit is at most once per friend per 20 h of world time (`offering.affection_rest_s`, clock `tea_aff_t`), like the visit rest (GDD §13.2.1). The rest is never shown.
  - Later cups are still sipped happily (`TEA_REACT_AGAIN`) and still show their reaction, but give no affection.
  - Returned petals respect jar caps. The petal line shows only if at least one petal fit.
- **Greeter:** the greeter sips and reacts, with 0 affection (`greeter_affection`), matching §5.6/§13.2.1 ("the greeter gives nothing").
- **Sleeping friend:** the cup is set down beside it (`TEA_OFFER_ASLEEP`). The credit is immediate, and the sip plays when it wakes (presentation only; the sim needs no change).
- **Heart-ups** from tea use the existing §13.2.2 celebrate, toast and S24 flow.
- **The gift** for a loved cup is the returned petals (an ingredient loop, no dew faucet) and the reaction itself. A tea photo pose is proposed in Q4.

## 8. Links to the other Active features

**Active F1 Wishes**, the types F2 can satisfy (`tea.json: wish_hooks`):
- `tea:<recipe_id>`, for example "craving clover tea" = `tea:clover_tea`
- `tea_kind:tea` / `tea_kind:treat`
- `tea_petal:<flower_id>`, any cup containing that petal
- `tea_loved`, any of the friend's loves

F2 emits `tea_offered(species: String, recipe_id: String, reaction: StringName, petals: Dictionary)` after the sip, and offers the pure check `TeaRules.satisfies(wish: String, species: String, recipe_id: String, petals: Dictionary) -> bool`.

Requests to F1:
- Pick a tea wish only when every petal it needs comes from a flower with at least one bloomed stem (`feasible_only`).
- Prefer the friend's loves, which ties wishes to personality.
- A tea wish may name an undiscovered recipe. Its book card then shows the friend's wish bubble beside the hint, which is a strong discovery hook.
- **Affection:** the wish bonus is F1's and stacks with the tea credit. F1 owns that number, and the sim should count both (Q2).

**Active F3 Free décor:**
- The tea nook is a fixed **prop**, not décor. It is not draggable in v1. F3's valid-placement map must treat a `f3_exclusion_radius_dp` = 40 dp disc around the nook as invalid (a soft hint, as for any blocked spot).
- The candidate nook position (0.900, 0.400, 64 dp hit) overlaps **leaf_pinwheel `anchors[4]` (0.800, 0.405) and `anchors[8]` (0.830, 0.378)** (0-based). Resolved: the Active F3 migration nudges those two pieces out of the exclusion, and `validate_content.py` checks every legacy anchor is valid or nudgeable. Bed_5 is 10 dp below the hit (OK).
- A long-press on the nook does nothing special, so it cannot collide with F3's long-press-to-edit.
- Teaware lives on the nook and is never placed in the garden.

## 9. Economy ⟲ `dew_drop`, `teaware`

- **Faucets:** none. Tea never creates dew. Returned petals are ingredients only.
- **Sinks:**
  1. **Dew drops** cost 3 dew each. With a model of 0–2 brews per session and 0.8 drops per brew, that is about 10–15 dew/day. It is small by design, so it never slows the early flower ladder.
  2. **Teaware**, 15 cosmetic pieces in three slots (teapot, cups, cloth), shown on the nook and in the sheet. 3 are free defaults and 12 are for sale, **14,850 dew** in total, from 150 to 4,500 (lead balance pass, GDD §14.7). Snug 0 (`teaware_snug`), so visitor maths are untouched. The Teaware tab opens after the first brew. Cards reuse the Garden item card: price chip, "Place", then "Use" / "In use", and unaffordable = `GARDEN_MORE_DEW`.
- **Effect on the pile-up** (GDD §9.3: median wallet 32 k on day 30): teaware absorbs about 18 % of the day-30 wallet. That is a real but modest sink. A larger one still needs Seasons. A repeatable sink (such as "tea parties") is not proposed, because it would push grinding.
- **E5:** nothing in tea is required, and the leaf boat (1 dew) remains the floor.
- **E6:** pantry counts are ≤ 24 and no dew numbers are new.
- **Sim hooks** (`sim_model`, for the sim owner, who runs `economy_sim.py`):
  - brews per session 0–2, an offer on 50 % of the visits seen in session, 35 % of them loved;
  - teaware bought after the catalogue in garden order;
  - re-check `last_heart5_day_median` [45, 70] and `heart3_by_day`.
  - My estimate: tea adds about +0.4 affection per friend per day for the reference player, which may pull the median ♥5 below day 45. The knobs, in order, are `affection_loved` 2 → 1, then `affection_rest_s` 0 → 72000 (one tea credit per friend per 20 h).

## 10. UI summary

| Surface | Contents |
|---|---|
| World: tea nook (prop, prio 4, 64 dp hit, release-to-fire) | Teapot, pantry jar, up to 3 cups on the cloth, a steam wisp. Tap: open the Tea sheet. Night: the moon kettle and moon cups glow (`night_glow`) |
| World: beds | Petal glints; tap to gather (§2.2) |
| Tea sheet › **Brew** | Pot, spoon, Stir/Pour (or Brew), tray 2×3, pantry 5 + 4 jars incl. the dew drop; offer row |
| Tea sheet › **Recipes** | A 3-column grid of 96×128 dp cards in `book_order`, with the count `TEA_BOOK_COUNT` ("9 of 24 recipes"). Found: icon, name, kind, mix icons, loved/liked by, **Fill the pot** (fills from the pantry, charges drops refundably, switches to Brew) or `TEA_BOOK_FILL_MORE`. Unfound: a silhouette, `TEA_BOOK_SECRET` and the hint. A friend's wish bubble shows on wished recipes |
| Tea sheet › **Teaware** | 3 sections of item cards |
| Basket sheet | One extra row at the bottom, "Tea nook", which opens the Tea sheet (a findable path besides the world prop). The dock stays at three buttons |
| Settings | `TEA_SETTING_SIMPLE` toggle in the accessibility group |

All targets in the sheet are ≥ 48 dp (jars 56, cups 48, chips 64, buttons 48 tall) with gaps ≥ 8 dp, at 200 % text, in vi/en, with night chrome. **Draw budget:** world +2 (glints and nook), sheet open ≤ +8 (pot, liquid, petals MultiMesh, spoon, tray MultiMesh, jars MultiMesh, ring, card).

## 11. Audio and haptics (for the Sound Designer; chord-snapped, A1–A3 gates)

| Cue | When | Sound | Bus / level | Caption | Haptic |
|---|---|---|---|---|---|
| S28 | Petals gathered | Paper-soft petal flutter + one glass plink on arrival | SFX −25 | `CAPTION_PETALS` | — / TICK |
| S29 | Petal or drop into the pot | Tiny water plip, stepping up the pentatonic per item | SFX −26 | `CAPTION_PLIP` | — / TICK |
| S30 | Stirring | Ceramic spoon swish loop, gain follows speed; a felt bell every 180° | SFX −28 | `CAPTION_STIR` | — / TICK per 180° |
| S31 | Pour / simple brew | Warm liquid pour 1.2 s with a rising glass gliss | SFX −24 | `CAPTION_POUR` | — / TICK at end |
| S32 | Cup offered, sip | Two-cup clink + a soft sip | SFX −24 | `CAPTION_CLINK` | — |
| S33 | New recipe | Small sparkle triad (S09 family, shorter) | SFX −23 | `CAPTION_RECIPE` | MEDIUM / MEDIUM |
| S34 | Nook ambience | Very soft kettle steam, slow AM, no rhythm, only while the nook is on screen | Ambience −36 | `CAPTION_STEAM` | — |
| S05 | Teaware placed | Reuse S05 (piece settles), no new id | SFX | `CAPTION_PLANT` | — / TICK |

A loved reaction reuses S24 at −6 dB. Jar full and tray full reuse S11. There is no buzz anywhere.

## 12. Save fields (additive; one schema bump shared with Active F1/F3, Q1)

| Field | Type | Meaning |
|---|---|---|
| `tea_unlocked` | bool | The nook has appeared |
| `petal_from_t` | Dictionary[String "bed_id:slot" → float world t] | Petal anchor per stem; absent = bloom time |
| `pantry` | Dictionary[String flower → int] | 0–24 each |
| `pot` | {petals: Array[String], drops: int, stir_deg: float} | Survives closing the sheet and the app |
| `tray` | Array[{recipe: String, made_unix: float}] | ≤ 6 |
| `recipes_found` | Dictionary[String recipe → float unix] | Never shrinks |
| `tea_prefs_seen` | Dictionary[String species → Array[String] recipe] | Revealed reactions |
| `tea_aff_t` | Dictionary[String species → float] | Last affection-granting cup per friend (20 h rest) |
| `teaware_owned` | Array[String] | Defaults are implicit |
| `teaware_set` | {teapot, cup, cloth: String} | |
| `cups_offered` | int | Lifetime count (event postcard `first_tea`) |
| `tea_flags` | Dictionary[String → bool] | first_hint_done, nook_seen, ghost counts |

**Migration:**
- Add all fields empty.
- `tea_unlocked` = onboarding done and any bloom.
- Petal anchors are absent, which means bloom time, so a returning player finds full stems: a generous first harvest.
- Affection is untouched.
- Every rule is a pure function of the save, so live play and offline match exactly.

**Suggested code shape** (for the Gameplay Engineer):
- `scripts/sim/tea_rules.gd` (pure): `petals_ready`, `harvest_bed`, `match_recipe`, `reaction`, `satisfies`.
- Game API: `harvest_bed(bed_id)`, `pot_add_petal(flower)`, `pot_remove(index)`, `pot_add_drop()`, `pot_remove_drop()`, `pot_stir(deg)`, `pot_pour() -> recipe_id`, `offer_cup(tray_index, species)`, `buy_teaware(id)`, `use_teaware(id)`.
- Signals: `petals_harvested(bed_id, counts)`, `recipe_found(id)`, `tea_offered(...)`.

## 13. Validator additions (for `validate_content.py`)

- Every recipe has 1–3 petals and 0–2 drops, and kind is treat if and only if drops == 2.
- No two recipes share a (multiset, drops) key.
- Exactly one fallback for each drop count.
- Every `species_prefs` key is a species, every listed recipe exists, and every named recipe is loved or liked by at least one friend.
- Every flower has a `petals` row.
- All string keys exist.
- The nook prop passes the 8 dp gap and frame checks.
- The E8 lint covers `staging_tea.csv` until it is merged.

## 14. Event postcards

`first_tea` (first cup offered) and `tea_book` (all 22 named recipes found), with templates `POSTCARD_EVENT_FIRST_TEA` and `POSTCARD_EVENT_TEA_BOOK`. These go into `economy.json: event_postcards` at merge.

## 15. Open questions for the Director

1. **One schema bump** for all three Active features (recommended), rather than three.
2. **Affection stacking** of a tea cup that fulfils a wish: tea credit plus F1's wish bonus? I recommend yes, with the sim re-run (§9).
3. **Nook position and the two pinwheel anchors** (§8): approve moving them.
4. **Tea photo pose** `tea_time` as a 6th photo slot per friend (60 → 72 photos)? It is a nice collectible, but it changes Album counts and Retention numbers.
5. **Greeter** gets 0 affection from tea (consistent). Is that acceptable, or should it be +1?
6. A later **away scene `tea_party`** (Retention F3) when ≥ 3 cups were offered while you were away? Out of scope here.
