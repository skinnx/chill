# Active play F1 — Wishes

*Game Designer (F1) · 2026-10-22 · status: **accepted with lead changes** (GDD §14, 2026-10-22) · data ⟲ `data/wishes.json` · strings ⟲ `i18n/strings.csv` (merged). Where this document and the data disagree, the data wins.*

Sibling features: **F2 Tea & Treats** (petals, teapot, recipe book, offering a cup) and **F3 Free décor placement** (drag, rotate, soft snap, edit mode). Every link to them is named here as a *contract* (§5, §11) so the three designs can be built in parallel.

---

## 1. Fantasy and pillars

A mossling sometimes floats a small thought bubble: a daisy, a teacup, a pinwheel, a leaf boat. You can help it, or not. Helping takes a few seconds, uses only what you already have, and makes the friend visibly delighted. This answers "there is not much to do" with **small, optional, legible goals** that point at the other systems (flowers, décor, the boat, the stream, tea).

| Principle | How wishes keep it |
|---|---|
| E1 nothing decays | A wish never expires, never fades, never gets "sadder". Affection from wishes only adds |
| E3 no guilt when away | A friend who leaves with an open wish keeps it (*held*) and brings it on a later visit. Copy is positive: "keeps the wish for another visit" |
| E5 always something to do | Every wish is fulfillable **right now with what the player already owns** (§4.3). None needs a purchase |
| E8 no urgency | No countdown, no badge numbers, no push notification, no "last chance". Banned-word lint passes on every string |
| G5 opening often is no advantage | Wishes spawn only in the foreground, at a calm rate, and their affection has its own 20 h rest (§6.1) |
| G6 deterministic | Every roll uses the retention hash (GDD §13.1) with wish keys; the world RNG is never touched |
| I1 soft immediate feedback | Every fulfilling action already has its own ≤ 100 ms feedback (pet, bed tap, stream tap…); the grant adds the delight on top |

## 2. Rules in one screen

1. A **wish** is (`species`, `wish id`). Each friend holds **at most 1** wish at a time (`max_per_friend`).
2. At most **2 wish bubbles are visible** in the hollow (`max_visible`) and at most **4 wishes pending** in total, visible plus held (`max_pending`).
3. Wishes **spawn only while the app is in the foreground** and the world is not blocked by a sheet or card (§4). Offline catch-up never creates a wish, so the offline sim is untouched.
4. A wish is fulfilled by a normal action the player already knows (pet, tap a bed, tap the stream, float a boat, tap a lantern, move décor with F3, offer a cup with F2). There is no new input to learn and **no new world hit target** (§8.1).
5. Fulfilling one gives: the delight animation, a small gift, a stamp the first time, and affection subject to its rest (§6).
6. Ignoring one costs nothing. A held wish is never removed; it simply waits.

## 3. States

```
          spawn (foreground)            action matches target
 (none) ──────────────────▶ OPEN ─────────────────────────────▶ GRANTED (archived as a stamp)
                             │  ▲
          friend departs     │  │ friend arrives again, a visible slot is free
                             ▼  │
                            HELD ──── condition already true on arrival (decor_near) ──▶ GRANTED on arrival
```

- **OPEN**: the friend is present and its bubble is visible.
- **HELD**: the friend is away, or present but both visible slots are taken. Held wishes show in the Album and the wish list only.
- On arrival a held wish takes a visible slot if one is free (ties: older `opened_t` first). A held wish never blocks other friends from wishing beyond `max_pending`.
- **Cousins** (§13.3.5) and **greeters** never *spawn* a wish. Lead change (GDD §14.2): the greeter is preferably a met friend holding a wish (oldest first) and it brings that held wish back for its stay, so an empty hollow still has a small goal. A **staged scene** participant does not spawn a wish while the scene is up; an existing bubble hides during the scene and comes back after it.

## 4. Spawn rules ⟲ `wishes.json: tuning`

### 4.1 The check
Every `spawn_check_s` = **60 s of foreground time** (world unblocked), the wish clock runs one check. `wish_checks += 1` (= n, the hash index; saved).

A check spawns nothing unless **all** hold:
- visible wishes < `max_visible` (2) and pending < `max_pending` (4);
- ≥ `global_gap_s` = **90 s** since the last wish spawned or was granted (`wish_last_t`);
- `u("wish_roll", n) < spawn_chance` = **0.4**;
- there is at least one **candidate friend**: present (not a greeter or cousin), present for ≥ `min_present_s` = 45 s, no wish held, ≥ `friend_gap_s` = **600 s** since its own last wish spawned or was granted, fewer than `max_spawned_per_visit` = 2 wishes this visit, and not napping, being petted, entering, leaving or cast in a scene.

Expected rhythm at steady play: about one new wish every 2–4 minutes with 2–3 friends present; with 2 already open, none. A reference player (2 × 5 min a day) sees roughly 2–4 wishes per session.

### 4.2 Picking the friend and the wish
- **Friend:** candidates sorted by album order; pick index ⌊`u("wish_friend", n)` × count⌋.
- **Wish:** among wishes eligible for that friend (§4.3), weighted:
  `w = weight × (1 + trait_bonus × matches(tags, traits[species])) × (prefer_mult if species ∈ prefer) × boost(phase, weather) × (unseen_mult if this friend never had this wish granted) × (repeat_mult if it was this friend's previous wish)`
  with `trait_bonus` 1.5, `prefer_mult` 3, `unseen_mult` 2, `repeat_mult` 0.25. Pick by cumulative weight with `u("wish_pick", n)`.
- If no wish is eligible, the check spawns nothing (not counted as a failure, nothing shown).

### 4.3 Eligibility (the "fulfillable now" rule)
A wish is eligible only if its `requires` hold now:
- `bloomed: {flower: k}`: ≥ k stems of that flower are bloomed (petals harvestable for F2, bed tappable for `bed_invite`).
- `owned: {decor: k}`: ≥ k copies of the set are placed.
- `feature: "tea"` (F2 shipped and the teapot unlocked) or `"free_decor"` (F3 shipped). If the feature is not in the build, those wishes are simply never eligible.
- `buddy_present`: the friend's best buddy is present too.
- `not_already_near` (décor wishes): no piece of that set is already within `near_dp` of the friend's favourite spot. Otherwise there is nothing to do.
- `spawn_when` (`phases`, `weather`): only gates **appearance**. Fulfilment never re-checks time or weather, so a firefly wish opened at dusk is still fulfillable at noon (a lantern tap releases fireflies at any hour). Nothing can become impossible.
- `species_only`: Stream Stones can only sit in the stream, so `stones_nearby` is limited to friends whose favourite spot is within reach of the water (pebblepaw at the Stream Bend, puddlewump at the Stepping Stones, glowmote at the Lantern Nook — the validator should check each favourite spot is ≤ `near_dp` from an F3 stream-stone snap point).

### 4.4 First wish (teaching)
After onboarding completes (`economy.json:onboarding` last step) plus `after_onboarding_s` = 60 s, the first onboarding friend present gets the scripted wish **`cuddle`** (fulfilled by petting, which the player has just learned). `WISH_TIP_FIRST` shows once as a toast when it appears. It does not use a hash draw.

### 4.5 Determinism

| Draw | Key parts |
|---|---|
| Spawn roll | `"wish_roll", <wish_checks>` |
| Friend pick | `"wish_friend", <wish_checks>` |
| Wish pick | `"wish_pick", <wish_checks>` |

Everything else (held slot order, eligibility, fulfilment) is a pure function of the save. `wish_checks` advances only in the foreground, so the same save plus the same play gives the same wishes. Golden vectors for P1 parity: to be generated with `economy_sim.py: hash_u` once the Director accepts the keys.

## 5. Targets and fulfilment detection

A wish's `target` is a small grammar. Detection runs in `WishRules` (pure, sim-side, like `RetentionRules`) from events that `Game` already emits or that F2/F3 add. The friend must be **present** unless noted.

| Target | Fulfilled when | Event (owner) | Friend's reaction |
|---|---|---|---|
| `pet` | the friend is petted (any length that grants the pet hearts) | `pet(species)` (exists) | `delight_snuggle` |
| `play_taps:N` | the friend is tapped N times during the wish (taps any time, no window). After each tap it hops ~40 dp to a free point in the tend zone and looks back | `tap_creature(species)` (exists) | `delight_hop` |
| `chime_tap` | the wind chime prop is tapped (or a breeze gust rings it while the friend is within `near_dp`) | `ring_chime` (exists) | `delight_sway` |
| `bed_invite:<flower>` | the player taps a bed holding ≥ 1 bloomed `<flower>` while this wish is open. The bed tap keeps its own sway and S18. The friend walks to that bed's `nibble_point` and plays the pose; `WISH_INVITE` captions it | `bed_tap(bed)` (exists) | `delight_nap` / `delight_nibble` |
| `decor_near:<set>` | a piece of `<set>` ends an F3 placement within `near_dp` = 120 dp of the friend's **favourite spot**. Works while the friend is **away**: it is then granted on its next arrival (`WISH_GRANTED_ARRIVAL`, `RECAP_WISH` if offline) | **F3** `decor_placed(set, piece_id, pos, rot)` | walks to the piece, `delight_sit_by` |
| `decor_tap:<set>` | any piece of `<set>` is tapped (its `tap_fx` plays as today) | `decor_tap(set, piece)` (exists) | `delight_gaze` / `delight_spin` |
| `boat` | a leaf boat launches while the friend is present | `boat_launched` (exists) | `boat_ride`: rides the boat (§10 Q3); `candle_boat`: walks to the bank and gazes |
| `stream_tap` | the stream is tapped within `stream_near_dp` = 240 dp of the friend (else the friend walks over on the next tap anyway, so any stream tap counts) | `stream_tap(pos)` (exists) | `delight_splash` / `delight_paw_water` |
| `tea:<recipe_id>` | a cup of that recipe is offered to this friend | **F2** `TeaRules.offer()` | `delight_sip` |
| `tea_petal:<flower>` | a cup whose petals include `<flower>` is offered | **F2** `TeaRules.offer()` (`tea.json: wish_hooks`) | `delight_sip` |
| `tea_loved` | a cup this friend *loves* by F2's `species_prefs` is offered | **F2** `TeaRules.offer()` | `delight_sip` |
| `tea_kind:tea` + `buddy_present` | any tea is offered while the best buddy is present; the buddy also gets a sip pose (no extra reward) | **F2** `TeaRules.offer()` | `delight_sip`, buddy leans in |
| `tea_kind:treat` | any F2 treat is offered | **F2** `TeaRules.offer()` | `delight_sip` |

Rules:
- **One action, one wish.** If one action matches two open wishes (two friends both wanting a stream tap), both are granted; if an F2 cup is offered to one friend, only that friend's wish counts.
- **Offering a cup that does not match** a wish is never a mistake: F2's normal reaction plays and the wish stays open. No S11, no "wrong".
- **Granted only once.** The grant is atomic in `WishRules.grant()`, which removes the wish from `wishes` and appends the stamp.

## 6. Rewards ⟲ `wishes.json: reward`

### 6.1 Affection and the 20 h rest (decision)
- A granted wish gives **+1 affection** (`affection_per_wish`) **if at least `wish_affection_rest_s` = 72,000 s (20 h) of world time passed since this friend's last affection-granting wish** (`wish_aff_t[species]`).
- This is its **own clock**, separate from `visit_aff_t`. A wish does not reset or use the visit rest, and a visit does not use the wish rest. So per friend and per 20 h, wishes add at most one point, the same size as the visit point.
- Why: an uncapped +1 per wish would let frequent players race hearts (breaking G5 and the 45–70-day ♥5 tail). One point per 20 h is felt (a heart fill on the friend's bar) yet bounded: at most +1/day per friend, roughly +30 to +60 % on heart pace for players who help every day, nothing for those who do not (no disadvantage).
- During the rest a granted wish still gives the full delight, the gift and the stamp. The rest is never shown (like §13.2.1).
- Heart-ups caused by a wish use the existing heart-up flow (`celebrate`, S24, toast); the wish's own toast is skipped then so only one toast shows.
- **Sim ask:** the Director should add a wish model to `tools/sim/economy_sim.py` (reference player grants ~1 wish per friend-day present, fulfil rate 0.6) and re-check §13.8's median ♥5 day. Tuning knob if it lands early: raise `wish_affection_rest_s` to 129,600 (36 h).

### 6.2 Gift
- **1 petal** (`gift: {kind: petal}`) of the friend's own flower: `tea.json species_prefs[species].gift_petal` if it has a bloomed stem, else the flower with the most bloomed stems (lead change, GDD §14.2: one rule shared with F2's returned petals). It flies from the friend to F2's petal pantry over 600 ms (`WISH_GIFT_PETAL`) and respects F2's petal cap (at the cap the petal simply stays on the flower). This closes the loop wishes → petals → teas → tea wishes.
- **No dew currency and no free dew drop** (F2 sells the drop for 3 dew, `tea.json: dew_drop`), so the economy sim (E5/E6) and income are unchanged. Without F2 the gift is omitted (`fallback_if_no_f2: none`), never converted to dew.
- Toast: `WISH_GIFT_PETAL` merged into the granted toast body line.

### 6.3 Stamps (collection)
- The first time a friend has a given wish granted, a **stamp** (the wish icon in a felt circle) is added to that friend's Album page (`wish_stamps[species]` bitmask over the wish list order). 12 friends × their eligible wishes. Never decreases. No percentages or totals are shown.

## 7. Presentation

### 7.1 Thought bubble (world)
- A felt-look cloud **44 dp** with two trailing dots, at `bubble_offset_dp` (18, −56) from the creature's head anchor, holding a 28 dp icon (`icon`: a flower icon from the flora atlas, a décor icon from the décor atlas, or one of the `wish_*` icons: heart, paw, note, firefly, pinwheel, boat, candle, droplet, ripple, teacup, treat). One atlas region per bubble: **1 draw call each, ≤ 2 on screen**.
- **In:** fade + rise 600 ms (`bubble_in_ms`, fade ≥ 300 ms), S26. **Idle:** bob 3 dp on a 600/k loop (k from `motion_tokens` like breathing). **Napping:** bubble at 45 % alpha with a tiny "z" (the wish waits). **Out on grant:** the bubble pops into 5 petals (400 ms) and the friend plays `granted_pose` (900 ms).
- **Reduce Motion:** cross-fades only (≤ 150 ms), no bob, petals ×0.3. **Night chrome:** bubble uses the night card tint.
- Follows the creature and the map pan like the name tag (no separate layer).

### 7.2 Reading a wish
- **Tap the friend** (existing tap: chirp, look-at, name tag): while it holds a wish the name tag becomes **"{name} · {wish title}"** for `caption_chip_s` 2.5 s, plus the hint line in `ink_2` under it. Nothing else changes about the tap (it still counts for `play_taps`).
- A11y: the mossling's label gains `A11Y_WISH_BUBBLE`.

### 7.3 Album friend page
- Row **`ALBUM_WISHING`** under the hearts when the friend holds a wish: icon + title + hint. If the friend is present, a 48 dp **`WISH_LIST_VISIT`** button closes the Album and glides the camera to it (map pan `glide_to`, ARCHITECTURE §3.4).
- Section **`ALBUM_WISH_STAMPS`**: a row of stamps granted with this friend (48 dp, tap shows the title). Empty: `ALBUM_WISH_STAMPS_EMPTY`.

### 7.4 Wish list card (optional)
- Opened from a **`WISH_LIST_BUTTON`** chip at the top of Album → Friends (48 dp, an unread dot when a new wish appeared since the card was last opened; never a number).
- Card `WISH_LIST_TITLE`: up to 4 rows (portrait, title, hint, `WISH_LIST_HERE` / `WISH_LIST_AWAY`, Visit button when here). Empty: `WISH_LIST_EMPTY`. Row a11y: `A11Y_WISH_LIST_ROW`.
- No HUD badge, no toast for new wishes beyond the first-ever tip, no notification. Wishes are found by looking at the hollow.

### 7.5 Toasts and recap
- Granted: `WISH_GRANTED_TITLE` + `WISH_GRANTED_BODY` (+ gift line), frosted toast 3.0 s, queued with the §13.2.2 rules. Suppressed if a heart-up toast fires for the same grant.
- Granted on arrival (`decor_near` while away): `WISH_GRANTED_ARRIVAL` live, or recap line `RECAP_WISH` (priority just after "hearts" in §13.5.3).
- Held on departure: no toast. The Album row shows `WISH_TIP_HELD` the first time only.

## 8. Input, hit-testing and performance

### 8.1 No new hit target
The bubble is **not** a world target; it is part of the mossling's existing visual. The arbiter (ARCHITECTURE §3.5) and GDD §2.5 priorities are unchanged. All fulfilments ride on existing targets' `world_release(act = true)` or on F2/F3 events, so a pan or a cancelled press never fulfils anything (the contract's "no action after a drag" holds for free).

### 8.2 Budgets
≤ 2 bubbles (2 draw calls), ≤ 1 grant burst at a time (petals share the celebrate particle budget). The spawn check is O(present × wishes) once a minute.

## 9. Audio and haptics (proposed cue ids; the Sound Designer owns the sound)

| Cue | When | Sound brief | Haptic Subtle / Full | Caption |
|---|---|---|---|---|
| **S26** wish appears | bubble fades in | a soft, airy bubble "blup" rising a third at the species' `voice_step`, −30 dB, SFX; never louder than S12 | — / — (a wish never buzzes the hand) | `CAPTION_WISH` |
| **S27** wish granted | grant | the species' chirp (S13 voice) followed by a 3-note glass sparkle on the current chord, −22 dB | — / DOUBLE | `CAPTION_WISH_GRANTED` |

Existing cues still play for the fulfilling action (S03 pet, S18 bed, S06 stream, S17 boat, S20 lantern, S21 chime, F2's pour). S27 starts 120 ms after the action's cue so they do not mask each other. Ids confirmed centrally (GDD §14.8): S26–S27 Active F1, S28–S34 Active F2, S35–S38 Active F3.

## 10. Wish catalogue (31) ⟲ `wishes.json: wishes`

Traits (personality tags, `wishes.json: traits`): puffmoss sleepy/sunny/sweet · buttonbud curious/petals/bouncy · pebblepaw calm/water/pebbles · honeyhum sweet/music/sunny · fernwhisk shy/calm/rain · dandelfluff dreamy/breeze/curious · bellkin music/dreamy/shy · primpip tidy/pebbles/petals · capling bouncy/rain/curious · puddlewump water/rain/bouncy · glowmote glow/night/calm · moonpuff night/sleepy/glow.

| # | id | Category | Target | Requires | Appears when | Prefers |
|---|---|---|---|---|---|---|
| 1 | `cuddle` | cuddle | `pet` | — | any (also the tutorial wish) | — |
| 2 | `tag_game` | cuddle | `play_taps:3` | — | any | capling, buttonbud |
| 3 | `sing_along` | cuddle | `chime_tap` | 1 Shell Wind Chime | any | bellkin, honeyhum |
| 4 | `nap_daisies` | garden | `bed_invite:button_daisy` | 1 Button Daisy bloomed | any | puffmoss, buttonbud |
| 5 | `clover_nibble` | garden | `bed_invite:sweet_clover` | 1 Sweet Clover bloomed | any | puffmoss, capling |
| 6 | `listen_bluebells` | garden | `bed_invite:bluebell` | 1 Bluebell bloomed | any | bellkin |
| 7 | `forget_me_not_nook` | garden | `bed_invite:forget_me_not` | 1 Forget-me-not bloomed | any | fernwhisk |
| 8 | `tidy_primroses` | garden | `bed_invite:primrose` | 1 Primrose bloomed | any | primpip |
| 9 | `blow_dandelions` | garden | `bed_invite:dandelion` | 1 Dandelion bloomed | any | dandelfluff |
| 10 | `moonbloom_glow` | garden | `bed_invite:moonbloom` | 1 Moonbloom bloomed | dusk, night | glowmote, moonpuff |
| 11 | `buttercup_sip` | garden | `bed_invite:buttercup` | 1 Buttercup bloomed | any | honeyhum |
| 12 | `pinwheel_nearby` | décor (F3) | `decor_near:leaf_pinwheel` | 1 owned, F3, none near yet | any | dandelfluff |
| 13 | `cairn_nearby` | décor (F3) | `decor_near:pebble_cairn` | " | any | primpip, pebblepaw |
| 14 | `toadstool_nearby` | décor (F3) | `decor_near:toadstool_seat` | " | any | capling |
| 15 | `lantern_nearby` | décor (F3) | `decor_near:firefly_lantern` | " | any | glowmote |
| 16 | `stones_nearby` | décor (F3) | `decor_near:stream_stones` | " ; stream-side friends only | any | pebblepaw, puddlewump |
| 17 | `watch_fireflies` | sky | `decor_tap:firefly_lantern` | 1 Firefly Lantern | golden, dusk, night | glowmote, moonpuff |
| 18 | `pinwheel_spin` | sky | `decor_tap:leaf_pinwheel` | 1 Leaf Pinwheel | any, ×3 in breeze | dandelfluff |
| 19 | `boat_ride` | stream | `boat` | — (1 dew, always affordable by E5) | any | pebblepaw, puddlewump |
| 20 | `candle_boat` | stream | `boat` | — | golden, dusk, night, dawn | moonpuff, fernwhisk |
| 21 | `rain_splash` | stream | `stream_tap` | — | soft rain | puddlewump, capling |
| 22 | `brook_song` | stream | `stream_tap` | — | any | pebblepaw |
| 23 | `clover_tea` | tea (F2) | `tea_petal:sweet_clover` | F2, 1 Sweet Clover bloomed | any | puffmoss |
| 24 | `daisy_tea` | tea (F2) | `tea_petal:button_daisy` | F2, 1 Button Daisy bloomed | any | buttonbud |
| 25 | `buttercup_tea` | tea (F2) | `tea_petal:buttercup` | F2, 1 Buttercup bloomed | any | honeyhum |
| 26 | `bluebell_tea` | tea (F2) | `tea_petal:bluebell` | F2, 1 Bluebell bloomed | any | bellkin |
| 27 | `forget_me_not_tea` | tea (F2) | `tea_petal:forget_me_not` | F2, 1 Forget-me-not bloomed | any | fernwhisk |
| 28 | `moonlight_tea` | tea (F2) | `tea:moonlight_tea` | F2, 1 Moonbloom bloomed | dusk, night | moonpuff, glowmote |
| 29 | `favourite_cup` | tea (F2) | `tea_loved` | F2 | any | — (tags: sweet, tidy, calm, curious) |
| 30 | `share_tea` | tea (F2) | `tea_kind:tea` | F2, best buddy present | any | — |
| 31 | `sweet_treat` | treat (F2) | `tea_kind:treat` | F2 | any | honeyhum, capling |

Coverage: flowers 8/8, décor sets 6/6 (chime via the prop), weather (rain, breeze), all five phases, the leaf boat, petting, tapping, the stream, best buddies, F2 (9) and F3 (5). Every species has ≥ 2 preferred wishes and ≥ 6 trait-matching wishes. Without F2 and F3 in the build, 17 wishes remain, so F1 can ship first.

## 11. Contracts with F2 and F3 (please confirm)

| Need | From | Proposed shape |
|---|---|---|
| Cup offered to a mossling | F2 | `TeaRules.offer(species, cup)` result `{recipe, kind: tea/treat, petals, pref: content/liked/loved}` passed to `WishRules.on_offer` |
| Wish hook types | F2 | F1 uses exactly `tea.json: wish_hooks.types`: `tea:<recipe_id>`, `tea_kind:tea`, `tea_kind:treat`, `tea_petal:<flower_id>`, `tea_loved`, evaluated in `TeaRules.offer()`, which then calls `WishRules.on_offer(species, result)` |
| Recipe id | F2 | `moonlight_tea` (a moonbloom-petal recipe). If F2 names it differently, only `wishes.json` changes |
| Petal gift | F2 | `Game.add_petals(flower, 1)` honouring F2's cap |
| Offering affection | F2 | Resolved (GDD §14.6): F2's offering gives +1/+2 at most once per friend per 20 h (`tea_aff_t`); a tea wish's +1 stacks on its own 20 h rest, so one cup gives at most +3 per friend per 20 h |
| Feature flags | F2 / F3 | `Game.feature_on(&"tea")`, `Game.feature_on(&"free_decor")` |
| Décor placed | F3 | signal `decor_placed(set, piece_id, pos_norm, rot)` after the soft snap settles (not during the drag) |
| Snap points by the stream | F3 | the stream-stone valid area, so the validator can check `stones_nearby` |
| Edit mode vs. wish taps | F3 | while F3 edit mode is on, wish spawn checks pause (world is "blocked" for wishes) and bubbles dim to 45 %; long-press on décor is F3's, on a mossling it stays petting |

## 12. Save fields (schema +1, additive; migration adds them empty)

| Field | Type | Meaning |
|---|---|---|
| `wishes` | Array[{species: String, wish: String, opened_t: float, state: "open"/"held", taps: int}] | Pending wishes (≤ 4). `taps` counts `play_taps` progress (never reset) |
| `wish_checks` | int | Foreground checks so far (hash index n) |
| `wish_last_t` | float | World t of the last spawn or grant (global gap) |
| `wish_friend_t` | Dictionary[String species → float] | Last spawn or grant per friend (friend gap) |
| `wish_visit_count` | Dictionary[String species → {arrive_t: float, n: int}] | Wishes spawned this visit (cap 2) |
| `wish_last_id` | Dictionary[String species → String] | Previous wish per friend (`repeat_mult`) |
| `wish_aff_t` | Dictionary[String species → float] | Last affection-granting wish (20 h rest, separate from `visit_aff_t`) |
| `wish_stamps` | Dictionary[String species → int bitmask over `wishes` order] | Stamps (never decreases; append-only wish list order, never reorder the JSON) |
| `wishes_granted` | int | Total grants (stats, Album copy if ever needed) |
| `wish_tutorial_done` | bool | The scripted first wish has spawned |
| `wish_list_seen_t` | float | For the wish-list chip's unread dot |

`monotone_snapshot()` should add `wish_stamps`, `wishes_granted` and affection (already covered).

## 13. Strings ⟲ `i18n/staging_wishes.csv`

83 keys: `WISH_<ID>_TITLE` and `WISH_<ID>_HINT` for all 31 wishes, plus UI keys (`WISH_LIST_*`, `ALBUM_WISHING`, `ALBUM_WISH_STAMPS*`, `WISH_GRANTED_*`, `WISH_GIFT_PETAL`, `WISH_TIP_*`, `WISH_INVITE`, `RECAP_WISH`, `CAPTION_WISH*`, `A11Y_WISH_*`). Checked against the E8 banned lists, NFC, placeholder parity and no clash with `strings.csv`. **New placeholders:** `{wish}` and `{hint}` (A11Y only); add them to GDD §8.7. `{spot}` in décor hints is the friend's favourite spot name (`SPOT_*`).

## 14. Open questions for the Director

- **Q1 affection pacing:** accept +1 per friend per 20 h on a separate clock (§6.1), pending a sim run? Alternative: share `visit_aff_t` (simpler, but then a wish would "use up" the visit point, which feels like nothing).
- **Q2 gift:** one loved-flower petal (no dew, no free dew drop, since F2 prices the drop). Also decide whether a tea wish + F2 offering stacking (up to +3 from one cup, once per 20 h) is acceptable or whether F2's offering credit should be skipped when a wish is granted.
- **Q3 boat ride:** `boat_ride` has the friend sit on the leaf (one new pose `ride_boat`, the boat sprite carries the creature for the 40 s drift, then it hops off at the far bank and walks back). Art and gameplay cost; fallback is "watches from the bank" like `candle_boat`.
- **Q4 new poses:** `delight_snuggle/hop/sway/nap/nibble/sit_by/gaze/spin/splash/paw_water/sip` — the Art Director may map several onto existing `celebrate` + behaviour poses.
- **Q5 validator:** extend `validate_content.py` for `wishes.json` (target grammar, ids exist in flora/décor/species, traits for all 12 species, key presence, append-only order).
