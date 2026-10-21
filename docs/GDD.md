# Mossling Meadow — Game Design Document (MVP slice)

*Game Designer + Systems/Economy Designer · 2026-10-20 · Godot 4.7.2-stable · binding inputs: `docs/research/00-SYNTHESIS.md` (§4 principles, §5.2 concept), `docs/research/04-cozy-idle-design-science.md`; supporting: 02 (UX), 05 (visual/motion), 06 (audio/haptics).*

**How to read this.** Numbers live in `data/*.json` and `i18n/strings.csv`; those files are the single source of truth. Tables marked ⟲ were generated from them when this document was written — if a table and a data file disagree, the data file wins and the table is stale. Principle tags (E1…X2) refer to 00-SYNTHESIS §4. "dp" = design dp = 3 px on the 1080×1920 base (C2).

**Validation status.** `python3 tools/sim/economy_sim.py` → **ALL CHECKS PASS** on 10,000 random play schedules + 2,000 reference players over 30 days (§9). `python3 tools/sim/validate_content.py` → content OK (§10). Godot 4.7.2 imports `i18n/strings.csv` and resolves both locales (checked headless, §11).

---

## 0. One-page summary

A sun-dappled hollow under an open sky. Round, felted **mosslings** wander in, nap on warm stones, sip dew from your flowers and leave little gifts. You plant, place a few cozy things, pet whoever is visiting, and read the postcards they send. Nothing can go wrong: nothing wilts, nobody leaves forever, nothing expires, and every return finds the hollow at least as lovely as you left it.

| | MVP slice |
|---|---|
| Place | 1 hollow, portrait, one screen, no camera travel |
| Content | 12 mossling species (one named individual each), 8 flowers, 6 décor sets, 1 repeatable leaf boat, 20 postcard templates, 60 photo poses |
| Time | Device clock: 5 palettes (dawn, day, golden hour, dusk, night) · weather: clear / breeze / soft rain · Spring only (season structure in place) |
| Currency | **Dew** (one spendable currency) + **affection** per mossling (never decays, never spent) |
| Sessions | 30 s glance · 1–5 min check-in · ambient watch mode |
| Pacing (reference player, 2 × 5 min/day) | first visitor at 20–40 s · 3 friends in the first 5 min · 4 by 24 h · all 12 by day 8 (median; p90 day 11) · whole catalogue ≈ day 24 |
| Economy | 140 purchasable copies, prices 15–527 dew, r = 1.10 (flowers) / 1.12 (décor), next purchase ≈ 79 min of passive income mid-game (median), basket full after ≈ 10–17 h, offline clamp 7 days |
| Ethics | No fail states, decay, timers that end in loss, streaks, FOMO, gacha, ads, IAP, notifications, accounts or network (E1–E9) |

---

## 1. Vision

### 1.1 Fantasy and logline
> *"Grow a little garden in a mossy hollow, and the fuzzy ones will come."*

The player is the quiet keeper of a hollow: a shallow, mossy bowl ringed by a willow, an old stump and a gentle hill, with a trickling stream along its foot and the whole sky above. **Refuge with prospect** (04 §3.2): enclosed and safe below, open and luminous above. Mosslings are not pets to maintain; they are guests who choose to visit because the place is lovely. The player's verbs are *plant, place, pet, watch, name, read*.

### 1.2 Pillars (every feature must serve at least one and break none)

| # | Pillar | Means | Never |
|---|---|---|---|
| P-A | **Safe and soft** | No loss, no hurry, no wrong answers. Every input makes something nicer (Townscaper principle). | Fail states, decay, red alerts, error buzzes, countdowns |
| P-B | **Small tender relationships** | Twelve named individuals who remember their favourite spot, grow fonder of you, and write to you. | Leaderboards, guilt NPCs, "X misses you" |
| P-C | **A garden that is always lovelier** | Growth is visible within minutes, absence is rewarded, the hollow only ever gains. | Weeds, mess, empty "come back" screens |
| P-D | **Calm to watch** | Ambient life (wind, light, water, breathing creatures) is a first-class mode, not a screensaver. | Busy UI, flashing, looping animations under 20 s composite |

### 1.3 Emotional targets
- **Affect quadrant:** positive valence, low arousal (Russell circumplex; 04 §3.3). Internal panel target after 5 min of watching: valence ≥ +2 and arousal ≤ −1 on a ±4 affect grid (04 §7).
- **Primary feeling: tenderness** (baby-schema care response, 04 §3.2): round silhouettes, low-set eyes, slow breathing, squash on touch.
- **Secondary:** soft fascination (ART), quiet competence ("I figured out what Bellkins like"), gentle anticipation ("the bluebells open this afternoon") that is *never* framed as pressure.
- **Recovery experience** (Sonnentag & Fritz): detachment (no news, no real-world stakes), relaxation (low-arousal AV), optional mastery (combo discovery), full control (player decides everything).
- **Anti-targets:** flow/challenge, urgency, completionist anxiety, spreadsheet thinking (numbers stay small, §5).

### 1.4 Target player
- Adults 18–45 who use phones to decompress (commute, bed, breaks); fans of Neko Atsume, Usagi Shima, Cats & Soup, Alba, Unpacking; many play with sound off (A4 covers that).
- One-handed, portrait, often half-attentive. Bilingual launch: **Vietnamese and English** at equal quality.
- Accessibility first-class: motion- and transparency-sensitive players, low vision (text to 200 %), left-handed, mono listeners (X1).

### 1.5 Session shapes

| Shape | Typical flow (taps) | Design guarantees |
|---|---|---|
| **30 s glance** | Open → (recap card 3–5 s, tap to skip) → see who is visiting → tap **Basket** → **Collect all** → close. 2–3 taps. | Something new every time (§5.6). Collecting is one tap. Leaving costs nothing; leaving mid-anything is safe (autosave). E4: even a 30 s session plants the tutorial seed or collects a gift, which is visible next launch. |
| **1–5 min check-in** | Glance + plant 1–2 flowers or place 1 décor piece (Garden sheet) + pet a visitor + read a postcard / rename a new friend / float a leaf boat. | ≥ 1 affordable purchase at every session start (E5, proven in §5.11 and §9). Next catalogue item ≈ 30–90 min of passive income mid-game. |
| **Ambient watch** | Put the phone down. After 60 s without input (or tap the eye in the HUD) the HUD and dock fade out (600 ms), frame rate drops to 30 fps (C21), the world keeps living by the device clock. First tap only wakes the UI. | No required input ever. Screen stays on only if the player enabled it (default off, 02 R12). |

### 1.6 Principle traceability

| Principle | Where it is satisfied |
|---|---|
| E1 no fail/decay | §5.8 world step only adds; sim check E1 (§9); no decay code path exists to write |
| E2 timers only good news | Only timers: growth ("Blooms in about 40 min"), dew cup ("brimming"), visits. None ends in loss (§3.3, §8.6) |
| E3 return without guilt | §5.6 greeter + recap, basket → photos when full, nothing ever degrades; 30-day absence test (§9) |
| E4 player-paced | §3.4: seed waits until tapped; scripted visitors happen in world time even if the app closed |
| E5 abundance | §5.11 proof + sim: 0 of 2,985,975 sessions without an affordable purchase or something new |
| E6 small numbers | Max price 527, max displayed ≈ 52 k (a saver's wallet after 30 d), hard cap 99,999 (§5.7) |
| E7 relatedness | Named individuals, favourite spots, hearts, postcards (§4.1, §7) |
| E8 no streaks/FOMO | No day counters; banned-word lint (§8.6); seasons recur (§6.4) |
| E9 ethical v1 | No IAP/ads/notifications/accounts/network anywhere in this design |
| I1–I3 input | §8.2–8.4 (feedback map, hit sizes, gestures) |
| V1–V6 | §2 composition, §6 palettes/weather, motion tokens referenced from 05 |
| A1–A4 | §8.3 feedback map (every meaningful sound has a visual twin; captions in X1) |
| X1–X2 | §7.6 settings; copy rules §8.6 |

---

## 2. The world: one hollow

### 2.1 Frame and zones
- The world is authored in a **1080 × 1920 play frame anchored to the bottom of the viewport**. Positions in `data/spots.json` are normalized: x ∈ [0, 1] left→right, y ∈ [0, 1] top→bottom of the frame. On taller phones (20:9 = 1080 × 2400) the extra height is **sky above y = 0** (02 §1.2, Z2 is elastic). The play area never moves.
- Zones (frame-normalized y; ⟲ `spots.json:zones`): **HUD** 0.075–0.175 (overlaps the frame only on 16:9 phones) · **look** 0.175–0.44 (sky, tree line, the hollow's rim; optional "delight" targets ≥ 64 dp) · **tend** 0.44–0.785 (garden floor; core targets ≥ 60 dp) · **dock** 0.797–0.934 (UI; the world renders under it, no world targets) · **gesture** 0.934–1.0 (nothing interactive).
- No drag may *start* outside x ∈ [0.067, 0.933] (24 dp edge rule, I2).

### 2.2 Layout in words (the Art Bible owns the look)
Reading the screen top to bottom:
1. **Sky** (L0/L1): the full upper half; sun or moon arcs across with the clock; clouds drift on L2. This is the rest area (30–40 % low detail, 05 §4).
2. **Far hills and tree line** (L2/L3): a soft fractal ridge at y ≈ 0.30 descending to the hollow's rim at y ≈ 0.42.
3. **The rim** (look zone, y 0.33–0.44), left to right: a **willow** whose canopy fills the top-left corner with one low branch where the **shell wind chime** hangs (0.28, 0.336); the **mailbox** on a mossy post (0.07, 0.395); the **toadstool ring** on the left slope (centre 0.32, 0.43); the grassy **hill crest** (0.56, 0.405) where **leaf pinwheels** catch the wind; a pale mossy **moon rock** (0.74, 0.385); the **old stump** with a hollow (0.90, 0.445) on the right.
4. **The garden floor** (tend zone, y 0.44–0.75): the woven **gift basket** sits at the top centre (0.50, 0.48) just above the flat, warm **sun stone** (0.50, 0.585), the composition's focal point (05 §4: lower-third band). Five **flower beds** surround it like petals: two upper beds (willow side and stump side) and three lower beds. A loose path runs left–right through the middle (y ≈ 0.59) with the **moss cushion**, **clover bank** and **fern shade** spots along it.
5. **The stream** (y 0.74–0.80): a quiet trickle that rises from a **spring rock** at the right edge (0.95, 0.735) and runs right→left along the foot of the garden, half under the frosted dock glass. Its upper bank carries the **firefly lantern** posts, the water holds the **stream stones**, and the **pebble cairn** grows on the far-left bank. Leaf boats drift along it from right to left.

⟲ Preview of the authored layout (spot circles ≈ a 50 dp creature, boxes = hit areas):

![Hollow layout schematic](gdd/hollow_layout.png)

### 2.3 Mossling spots ("favourite spots")
Named rest positions. A spot holds `capacity` mosslings and allows the listed behaviours. Four spots only exist once enough of their décor is placed. ⟲ `spots.json:spots`

| id | Name (en / vi) | x | y | Cap. | Behaviours | Shelter | Appears when |
|---|---|---|---|---|---|---|---|
| `sun_stone` | Sun Stone / Phiến đá nắng | 0.500 | 0.565 | 2 | nap, play | no | always |
| `moss_cushion` | Moss Cushion / Nệm rêu | 0.350 | 0.595 | 1 | nap, play | no | always |
| `clover_bank` | Clover Bank / Gò cỏ ba lá | 0.650 | 0.595 | 1 | nibble, nap | no | always |
| `fern_shade` | Fern Shade / Bóng dương xỉ | 0.080 | 0.585 | 1 | nap, wander | yes | always |
| `stream_bend` | Stream Bend / Khúc suối cong | 0.330 | 0.752 | 1 | sit_by_stream | no | always |
| `willow_root` | Willow Root / Gốc liễu | 0.130 | 0.430 | 1 | nap, wander | yes | always |
| `hill_crest` | Hill Crest / Đỉnh đồi | 0.560 | 0.405 | 1 | wander, play | no | always |
| `stump_hollow` | Stump Hollow / Hốc gốc cây | 0.900 | 0.437 | 1 | nap | yes | always |
| `moon_rock` | Moon Rock / Tảng đá trăng | 0.740 | 0.385 | 1 | nap, wander | no | always |
| `toadstool_ring` | Toadstool Ring / Vòng nấm | 0.320 | 0.430 | 2 | play, nap | yes | 3 × Toadstool Seat |
| `stream_stones` | Stepping Stones / Đá giữa suối | 0.660 | 0.770 | 1 | sit_by_stream, play | no | 3 × Stream Stones |
| `lantern_nook` | Lantern Nook / Góc đèn | 0.905 | 0.738 | 1 | nap, sit_by_stream | no | 3 × Firefly Lantern |
| `cairn_side` | Cairn Corner / Góc tháp sỏi | 0.150 | 0.742 | 1 | sit_by_stream, nap | no | 3 × Pebble Cairn |

**Entries** (off-screen walk-in points, ⟲): 

- `entry_fern_gap` (-0.08, 0.585)
- `entry_stump` (1.08, 0.455)
- `entry_hill` (0.56, 0.355)
- `entry_streamside` (-0.08, 0.745)

### 2.4 Flower beds
Five beds × 16 stem positions = 80 = the total of all flower copies (8 × 10), so planting can never dead-end. Each bed's stems are a seeded Poisson-disk cluster (min 31 px apart) stored centre-out as offsets in `beds[].stems`; `nibble_points` are where a nibbling mossling sits at the bed's edge. Hit area 90 × 63 dp per bed. ⟲

| id | Name (en / vi) | x | y | Hit (dp) | Stems | Fill order |
|---|---|---|---|---|---|---|
| `bed_1` | Brookside bed / Luống bên suối | 0.500 | 0.690 | 90 × 63 | 16 | 1 |
| `bed_2` | Fern bed / Luống dương xỉ | 0.200 | 0.660 | 90 × 63 | 16 | 2 |
| `bed_3` | Sunny bed / Luống nắng | 0.800 | 0.660 | 90 × 63 | 16 | 3 |
| `bed_4` | Willow bed / Luống gốc liễu | 0.220 | 0.515 | 90 × 63 | 16 | 4 |
| `bed_5` | Stump bed / Luống gốc cây | 0.780 | 0.515 | 90 × 63 | 16 | 5 |

Placement rules (implementable as written):
1. The **first** copy of a flower type asks the player to choose a bed: beds with free stem slots glow; tap one. (Tapping outside picks the bed with the lowest `fill_order` that has room.)
2. Later copies of that type go to the bed that already holds most stems of that type if it has room, else to the bed with room nearest to it.
3. Inside a bed, the stem takes the free slot nearest to the centroid of same-type stems already in the bed (types cluster, Townscaper-style); the first stem of a type takes the free slot with the lowest index.
4. Mixed beds are allowed and look lovely; nothing can be uprooted or moved in the MVP (no destructive actions).

### 2.5 Décor anchors and props
Décor sets **grow at fixed, pre-authored positions**: each copy adds the next position of its anchor (auto-beautified, no placement UI, 05 §4 odd-cluster rule handled by authoring order). ⟲ `spots.json:decor_anchors`

- `firefly_lantern` (path): (0.930, 0.716), (0.820, 0.726), (0.710, 0.735), (0.600, 0.740), (0.490, 0.738), (0.380, 0.743), (0.270, 0.749), (0.160, 0.754), (0.060, 0.757), (0.985, 0.700)
- `stream_stones` (path): (0.660, 0.768), (0.700, 0.773), (0.620, 0.770), (0.740, 0.771), (0.580, 0.769), (0.780, 0.768), (0.540, 0.769), (0.820, 0.764), (0.500, 0.768), (0.860, 0.760)
- `leaf_pinwheel` (scatter): (0.500, 0.418), (0.620, 0.392), (0.680, 0.428), (0.460, 0.392), (0.800, 0.405), (0.585, 0.437), (0.700, 0.372), (0.420, 0.430), (0.830, 0.378), (0.520, 0.372)
- `toadstool_seat` (ring): (0.320, 0.408), (0.320, 0.452), (0.401, 0.423), (0.239, 0.437), (0.370, 0.448), (0.270, 0.412), (0.370, 0.412), (0.270, 0.448), (0.401, 0.437), (0.239, 0.423)
- `pebble_cairn` (stack): (0.045, 0.728), (0.045, 0.720), (0.045, 0.711), (0.045, 0.703), (0.045, 0.694), (0.045, 0.685), (0.045, 0.677), (0.045, 0.668), (0.045, 0.660), (0.045, 0.651)
- `wind_chime` (string): (0.239, 0.336), (0.248, 0.342), (0.258, 0.336), (0.267, 0.342), (0.276, 0.336), (0.284, 0.342), (0.293, 0.336), (0.302, 0.342), (0.311, 0.336), (0.321, 0.342)

Props (⟲ `spots.json:props`):

| id | x | y | Size (dp) | Tap | Hit (dp) |
|---|---|---|---|---|---|
| `sun_stone_rock` | 0.500 | 0.585 | 87 × 40 | — | — |
| `basket` | 0.500 | 0.480 | 44 × 36 | open_basket | 64 |
| `mailbox` | 0.070 | 0.395 | 30 × 48 | open_postcards | 64 |
| `wind_chime_branch` | 0.280 | 0.336 | 40 × 60 | ring_chime | 64 |
| `stump` | 0.900 | 0.445 | 70 × 60 | — | — |
| `spring_rock` | 0.950 | 0.735 | 60 × 40 | — | — |
| `willow` | 0.120 | 0.300 | 140 × 170 | — | — |

**Hit priority** when targets overlap (world): mossling > bed with a ready bud > prop (basket, mailbox, chime) > bed > stream > background. The validator checks every static target for size floors and 8 dp gaps (§10).

---

## 3. Core loops, timings and onboarding

### 3.1 Seconds loop (touch → delight, always < 100 ms to first response, I1)
| Action | Result | Timing |
|---|---|---|
| Tap a **ready bud** (a stem whose bloom time arrived while you were watching) | the bed's ready buds unfurl, 30 ms stagger, 3–5 sparkles, S04 | 600 ms unfurl; un-tapped ready buds open by themselves after 20 s (2.4 s slow unfurl) |
| **Long-press** a mossling | pet: radial fill from 150 ms, at 450 ms squash to 0.88 (`jelly` spring), purr chime S03 loops while held, hearts on release | +1 affection, first pet per visit only (never stated in UI) |
| **Stroke** (drag ≥ 24 px starting on a mossling) | same as pet | — |
| Tap a mossling | it turns to you, chirps (S12 at its `voice_step`), name tag fades in for 2 s; a second tap within 2 s opens its card | — |
| Tap the **stream** | ripple ring to 36 dp in 380 ms, bubbles S06; nearby awake mosslings glance | — |
| Tap the **wind chime** (once placed) | rings the owned shells, falling arpeggio | — |
| Tap a bed (no ready buds) | stems sway, soft rustle; long-press = bed card ("Blooms in about 40 min") | — |

### 3.2 Minutes loop (1–5 min)
1. **Collect** — Basket (dock or in-world basket) → **Collect all**: gifts fly to the dew counter, counter rolls up (600 ms), S02 ladder. One tap.
2. **Grow** — Garden → Flowers → **Plant** (first copy: choose a bed). Or Décor → **Place**. 2–3 taps each. Typical: plant 1–2 flowers or place 1 décor piece per check-in.
3. **Befriend** — pet whoever is visiting; read a postcard (mailbox flag); name a new friend.
4. **Ritual** — float a **leaf boat** (1 dew): it drifts the length of the stream in 40 s and visiting mosslings gather to watch (+1 affection each, once per visit).

### 3.3 Hours and days loop
| Clock | What happens | Source |
|---|---|---|
| 2 min – 6.3 h | Flower stages: sprout → bud → bloom (per flower, §4.2). Bloomed stems add dew to the cup and count for attraction | `flora.json` |
| ~25–40 min | Average gap between visits: λ = 1.4–2.4 visits/h, rising with snugness | `economy.json` |
| 40–80 min × stay | A visit (the mossling stays, cycles 2–6 min behaviour bouts, leaves a gift on departure) | §5.6 |
| 10–17 h | Gift basket fills (24 slots); after that, visitors leave **photos** instead | §5.7 |
| 12 h | Dew cup stops filling until the next collect ("brimming") | §5.3 |
| ~1 day early / ~2 days later | A new species debuts after its flower/décor combination blooms or is placed | §5.5, §9 |
| Days–weeks | Hearts grow; postcards at ♥2 and ♥4; best friends at ♥5 | §7.4 |
| 14 days | A season length. MVP is Spring only; the cycle structure exists (`world.json`) | §6.4 |

### 3.4 The first five minutes (scripted; numbers in `economy.json:onboarding`)
Rule zero: **no text walls**. The only words on screen in the first five minutes are mossling names on the new-friend card and labels inside sheets the player chooses to open. Every hint is diegetic (light, motion, sound).

| Time | What the player sees and hears | Diegetic hint (only if the player is idle) |
|---|---|---|
| 0.0 s | Splash `#F0EEE9` fades into the hollow at the device's time of day while shaders warm up behind it (C8). Ambience bed fades in over 4 s, pad joins at 6 s. The camera settles from 103 % to 100 % over 2.5 s (`emphasized`; cross-fade under Reduce Motion). The dock is present but Garden, Album and Basket are "asleep" (50 % opacity, still tappable); Settings is awake. | — |
| 2.5 s | A single **glowing seed** rests on the Brookside bed (`bed_1`, nearest the thumb), pulsing on the 4.84 s ambient period. | From 6.5 s: a soft tap ring expands from the seed every 3 s |
| tap (3–25 s typical) | Tap the seed: it sinks into the soil (S05, soil puff). Tutorial stages: sprout +10 s, bud +40 s, bloom-ready +90 s. | — |
| 20–40 s | **First visitor Pip** (Puffmoss) at clamp(tap + 15 s, 20 s, 40 s); if the seed is not tapped by 25 s Pip comes at 30 s anyway. Fades in at the fern gap (400 ms), hops to sniff the sprout, then curls up on the sun stone (S12). When Pip settles, the **new-friend card** rises (S09, MEDIUM haptic): portrait, "A new friend!", "This is Pip", pencil to rename. Tap anywhere: the card shrinks into the Album button, which wakes. | 6 s after the card closes, if Pip has not been touched: a dotted ring fills around Pip in 450 ms (demonstrating "hold"), every 5 s, at most 3 times |
| tap + 90 s | The bud glows: ready. Tap → unfurls in 600 ms (S04). Auto-opens after 20 s. | Tap ring on the bud after 3 s |
| Pip + 80 s | Pip wakes, stretches, waves and leaves an **acorn cup of dew (18)** in the in-world basket; the Basket button wakes with a glint and a soft bounce. | Basket button glints every 6 s |
| on collect | **Collect all**: "+18" flies to the HUD where the dew counter appears for the first time. Clover #2 costs 17, so the Garden button wakes with a small "new" dot. | — |
| bloom + 15 s (≤ 150 s) | **Second visitor Dot** (Buttonbud), drawn by the new bloom, bounces over the hill crest straight to the clover (nibble). New-friend card. Stays 100 s, leaves a petal bundle (12 dew). | — |
| 210 s | **Third visitor Cobble** (Pebblepaw) wanders up the stream bank to the stream bend. New-friend card. While Cobble sits there, a leaf drifts down the stream once and a ripple ghost appears on the water (invites the stream tap). Cobble is the first normal visit (40–80 min stay, normal gift). | — |
| 240 s | The **mailbox flag** pops up with a paper rustle (S07): the welcome postcard. Opening it is optional. | Flag wiggles every 8 s |
| 300 s | Scripted part ends; Poisson visits begin (§5.4). | — |

Outcome (sim-verified): 3 species met, 1 flower bloomed, 1–2 purchases possible, 0 words of instruction. Players who leave early lose nothing: scripted visits run in world time, so their gifts and new-friend cards are waiting (in the recap) next time; the seed keeps sparkling until tapped.

---

## 4. Content (MVP)

### 4.1 Mosslings (12 species, one named individual each)

#### 4.1.1 Roster ⟲ `species.json`
| # | id | Species (en / vi) | Default name (en / vi) | Rarity | Gift | Favourite spot | Entry | Personality |
|---|---|---|---|---|---|---|---|---|
| 1 | `puffmoss` | Puffmoss / Rêu Bông | Pip / Bơ | common | 12 dew (acorn cup) | Sun Stone | `entry_fern_gap` | A round little sunbather. Puffmosses can nap anywhere warm, and usually do. |
| 2 | `buttonbud` | Buttonbud / Nụ Cúc | Dot / Chấm | common | 12 dew (petal bundle) | Clover Bank | `entry_hill` | Curious about everything, especially petals. Follows your taps with great interest. |
| 3 | `pebblepaw` | Pebblepaw / Sỏi Tròn | Cobble / Cuội | common | 12 dew (shiny pebble) | Stream Bend | `entry_streamside` | Patient and calm. Can watch the stream for an entire afternoon. |
| 4 | `honeyhum` | Honeyhum / Mật Ngọt | Bumble / Vo Ve | uncommon | 15 dew (petal bundle) | Moss Cushion | `entry_hill` | Hums while working, and is always working. Sips dew from flower to flower. |
| 5 | `fernwhisk` | Fernwhisk / Lá Xoăn | Wisp / Xíu | uncommon | 15 dew (seed pouch) | Fern Shade | `entry_fern_gap` | Shy, gentle and very soft. Peeks out from the ferns before saying hello. |
| 6 | `dandelfluff` | Dandelfluff / Bông Gió | Drift / Mây | uncommon | 15 dew (seed pouch) | Hill Crest | `entry_hill` | Light as a seed and twice as dreamy. Drifts wherever the breeze goes. |
| 7 | `bellkin` | Bellkin / Chuông Nhỏ | Lilt / Leng Keng | uncommon | 15 dew (acorn cup) | Willow Root | `entry_fern_gap` | Musical down to the ears. Sways to any sound and hums along to wind chimes. |
| 8 | `primpip` | Primpip / Má Hồng | Tansy / Mận | uncommon | 15 dew (petal bundle) | Stump Hollow | `entry_stump` | Tidy and polite. Blushes when petted and lines up pebbles in neat little rows. |
| 9 | `capling` | Capling / Nấm Lùn | Nib / Tí | rare | 20 dew (seed pouch) | Toadstool Ring | `entry_fern_gap` | Bouncy, bubbly and fond of puddles. Hops from toadstool to toadstool. |
| 10 | `puddlewump` | Puddlewump / Bì Bõm | Puddle / Bọt | rare | 20 dew (shiny pebble) | Stepping Stones | `entry_streamside` | Happiest when it rains. Splashes in the shallows and sits on stream stones. |
| 11 | `glowmote` | Glowmote / Đốm Sáng | Lumen / Đóm | rare | 20 dew (moon drop) | Lantern Nook | `entry_hill` | Quiet and thoughtful. Its antenna glows softly as the evening settles in. |
| 12 | `moonpuff` | Moonpuff / Bông Trăng | Luna / Hằng | very rare | 28 dew (moon drop) | Moon Rock | `entry_stump` | Arrives with the moon and naps on the moon rock until dawn. Very hard to wake, very easy to love. |

Album hints (shown on a silhouette before you meet them) are in `strings.csv` as `SPECIES_*_HINT`; the album also shows the required items as icons with dots (● bloomed/placed, ◐ growing, ○ missing).

#### 4.1.2 Parametric rig and palette contract
All mosslings are one SDF creature material with `instance uniform`s (D7, C11): a single rounded body blob (head = body, baby schema: eyes in the lower half, eye width ≥ 18 % of body width, 05 §0.1) on tiny nub feet, plus swappable parts. Parameters ⟲:

| id | body w/h | size | ear | tail | antenna | pattern | eye | fuzz dp | fur | fur_2 | belly | accent | voice step |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `puffmoss` | 1.15 | 1.00 | round | puff | none | belly | sleepy | 1.0 | `cr_moss` | `cr_fern` | `cr_cream` | `cr_rose` | +0 |
| `buttonbud` | 1.00 | 0.85 | tuft | none | sprout | freckles | round | 0.8 | `cr_cream` | `cr_oat` | `cr_snow` | `cr_sun` | +2 |
| `pebblepaw` | 1.25 | 1.05 | round | curl | none | socks | round | 0.7 | `cr_mist` | `cr_slate` | `cr_snow` | `cr_sky` | -2 |
| `honeyhum` | 1.05 | 0.95 | none | puff | double_bobble | back_stripes | round | 1.1 | `cr_honey` | `cr_cocoa` | `cr_cream` | `cr_sun` | +3 |
| `fernwhisk` | 0.85 | 1.00 | pointed_soft | brush | fern_curl | cap | round | 1.2 | `cr_sage` | `cr_fern` | `cr_cream` | `cr_leaf` | +1 |
| `dandelfluff` | 1.00 | 0.90 | none | puff | dandelion_puff | none | round | 1.2 | `cr_snow` | `cr_cream` | `cr_snow` | `cr_sky` | +4 |
| `bellkin` | 1.00 | 0.95 | bell | none | none | belly | round | 0.9 | `cr_mist` | `cr_lilac` | `cr_snow` | `cr_berry` | +5 |
| `primpip` | 1.10 | 0.90 | leaf | leaf | none | cheeks | round | 0.9 | `cr_peach` | `cr_blush` | `cr_cream` | `cr_rose` | +2 |
| `capling` | 1.10 | 0.85 | none | sprout | none | cap_spots | round | 0.8 | `cr_oat` | `cr_rose` | `cr_cream` | `cr_snow` | +3 |
| `puddlewump` | 1.30 | 1.05 | nub | none | none | spots | round | 0.6 | `cr_mist` | `cr_sage` | `cr_snow` | `cr_sky` | -1 |
| `glowmote` | 0.95 | 0.85 | pointed_soft | curl | glow_bobble | none | round | 1.0 | `cr_dusk` | `cr_slate` | `cr_lilac` | `cr_glow` | +1 |
| `moonpuff` | 1.20 | 1.15 | tuft | puff | none | cap | sleepy | 1.2 | `cr_lilac` | `cr_snow` | `cr_snow` | `cr_glow` | -3 |

- `body_w_h`: width/height of the body ellipse-squircle at rest (0.85 tall … 1.30 wide). `size`: scale relative to 1.0 = 50 dp tall (150 px).
- `ear` ∈ {none, round, tuft, pointed_soft, bell, leaf, nub} · `tail` ∈ {none, puff, curl, brush, leaf, sprout} · `antenna` ∈ {none, sprout, double_bobble, fern_curl, dandelion_puff, glow_bobble} · `pattern` ∈ {none, belly, freckles, socks, back_stripes, cap, cap_spots, cheeks, spots} · `eye` ∈ {round, sleepy}.
- `fuzz_dp`: amplitude of the noise-displaced fur rim (05 §2.3 item 7: 0.6–1.2 dp). Golden hour adds the backlit peach-fuzz rim in the palette's `key` colour.
- Palette slots: `fur` (body), `fur_2` (pattern/secondary), `belly`, `accent` (ear insides, antenna tips, blush). All four reference **creature tokens `cr_*`**; flowers reference **`fl_*`** petal tokens. **Contract:** the token *names* below are binding for data; **final hex values live in `data/palettes.json` (`creatures.tokens`, `flora.flowers`, owned by the Art Bible)** — all 20 `cr_*` and 8 `fl_*` tokens referenced here are present there (checked 2026-10-20). The hex column below is only the initial design proposal (fur at HSV S ≤ 0.45 for V2; `cr_sun`, `fl_buttercup`, `fl_dandelion` as small-area accents); where it differs, `palettes.json` wins. Each palette is re-lit per time of day by the shared ambient/key globals, never hand-tinted.

| Token | Initial proposal (superseded by `palettes.json`) | HSV S | HSV V | Used by |
|---|---|---|---|---|
| `cr_moss` | `#A3C68C` | 0.29 | 0.78 | puffmoss |
| `cr_fern` | `#7FA37A` | 0.25 | 0.64 | fernwhisk, puffmoss |
| `cr_sage` | `#B7CBA8` | 0.17 | 0.80 | fernwhisk, puddlewump |
| `cr_cream` | `#F3E8D2` | 0.14 | 0.95 | buttonbud, capling, dandelfluff, fernwhisk, honeyhum, primpip, puffmoss |
| `cr_oat` | `#E2D0AE` | 0.23 | 0.89 | buttonbud, capling |
| `cr_snow` | `#F7F4EE` | 0.04 | 0.97 | bellkin, buttonbud, capling, dandelfluff, moonpuff, pebblepaw, puddlewump |
| `cr_peach` | `#F5C9AE` | 0.29 | 0.96 | primpip |
| `cr_blush` | `#EDB9BE` | 0.22 | 0.93 | primpip |
| `cr_rose` | `#E39AA6` | 0.32 | 0.89 | capling, primpip, puffmoss |
| `cr_honey` | `#EBC889` | 0.42 | 0.92 | honeyhum |
| `cr_cocoa` | `#A98C7B` | 0.27 | 0.66 | honeyhum |
| `cr_mist` | `#B9CDE0` | 0.17 | 0.88 | bellkin, pebblepaw, puddlewump |
| `cr_slate` | `#8C9BB3` | 0.22 | 0.70 | glowmote, pebblepaw |
| `cr_sky` | `#9CC3E6` | 0.32 | 0.90 | dandelfluff, pebblepaw, puddlewump |
| `cr_lilac` | `#CBBCE0` | 0.16 | 0.88 | bellkin, glowmote, moonpuff |
| `cr_dusk` | `#8F8BB8` | 0.24 | 0.72 | glowmote |
| `cr_berry` | `#B98AB0` | 0.25 | 0.73 | bellkin |
| `cr_sun` | `#F4CF6E` | 0.55 | 0.96 | buttonbud, honeyhum |
| `cr_leaf` | `#74A86F` | 0.34 | 0.66 | fernwhisk |
| `cr_glow` | `#FFE6A6` | 0.35 | 1.00 | glowmote, moonpuff |
| `fl_clover` | `#EBB3C8` | 0.24 | 0.92 | sweet_clover |
| `fl_daisy` | `#FBF7EE` | 0.05 | 0.98 | button_daisy |
| `fl_buttercup` | `#F2D16B` | 0.56 | 0.95 | buttercup |
| `fl_forget_me_not` | `#9EC4EC` | 0.33 | 0.93 | forget_me_not |
| `fl_bluebell` | `#9AA6E0` | 0.31 | 0.88 | bluebell |
| `fl_primrose` | `#F3E39E` | 0.35 | 0.95 | primrose |
| `fl_dandelion` | `#F4CF62` | 0.60 | 0.96 | dandelion |
| `fl_moonbloom` | `#EDEAF7` | 0.05 | 0.97 | moonbloom |

- `voice_step`: offset in pentatonic steps for the species' chirp (S12) and purr root (S03), so friends are distinguishable by ear (06 §0.5).

#### 4.1.3 Behaviours (state machine shared by all species)
States: **ENTER** → (**BOUT** ⇄ **MOVE**)* → **LEAVE**.
- **ENTER**: fade in over 400 ms at the species' `entry`, walk to the first bout's spot (20–30 dp/s, hop gait with 8 % squash for bouncy species: Buttonbud, Capling, Puddlewump).
- **BOUT**: one of five behaviours, duration uniform **120–360 s**, chosen by the species' `behaviours` weights, adjusted: **night ×3 nap**; in **rain**, species without a rain like (`likes_weather` rain) pick shelter spots (`shelter: true`) or hold a big leaf over their head (fallback, any spot); rain-likers ×1.5 play. **A new bout never repeats the previous (behaviour, spot) pair**, and bouts never exceed 6 min — so after any absence of ≥ 10 min, every mossling still visiting is visibly doing something different (used by E5, §5.11).
  - `nap`: curl up, eyes closed, breathing 5–6 s (V5), tiny "z" puffs (no text).
  - `nibble`: sit at a bed's `nibble_point` (prefer a bed holding a flower the species requires or likes) or the Clover Bank and sip dew from the petals — **flowers never lose anything**.
  - `play`: hop, roll, chase pollen; with another mossling present they play together (photo pose stays `play`).
  - `wander`: stroll a Catmull-Rom path through 2–3 random points of the tend zone, sniff flowers, look at the camera.
  - `sit_by_stream`: sit at a stream spot or anywhere on the upper bank, paw the water (ripples), watch boats.
- **Spot choice**: the first bout and every nap go to the **favourite spot** if it is free and allows the behaviour (60 %); otherwise a random free spot allowing it. Spot capacity is respected; `nibble` uses beds, `wander` uses paths.
- **Awake breathing** 3.5–4.5 s, asleep 5–6 s, ±10 % per individual (05 §3.4). Blinks every 2.5–7 s.
- **LEAVE**: at departure time: stretch, wave toward the camera, drop the gift into the basket (gift flies 600 ms to the in-world basket), walk to the entry, fade out over 400 ms.
- **Boat**: when a leaf boat launches, awake mosslings turn to watch; those within 300 px of the stream walk to the bank and `sit_by_stream` until it passes.
- **Max 5 mosslings in the hollow**; a 6th arrival "peeks" (waves from the rim for 4 s, leaves its gift, no stay).

#### 4.1.4 Attraction rules (Neko Atsume-style, never gacha)
Weights are deterministic functions of what is in the garden, the weather and the time of day; randomness only decides *which eligible friend* comes next. Nothing is bought for a chance. ⟲

| id | Base weight | Requires (all) | Phases | Likes (multipliers) | Stay × | Behaviours nap / nibble / play / wander / stream |
|---|---|---|---|---|---|---|
| `puffmoss` | 10 | — | any | 3 × Sweet Clover ×1.5; clear ×1.2; golden ×1.3 | 1.0 | 0.45 / 0.20 / 0.05 / 0.15 / 0.15 |
| `buttonbud` | 10 | — | any | 3 × Button Daisy ×2.0; 3 × Sweet Clover ×1.3; day ×1.2 | 0.9 | 0.10 / 0.30 / 0.25 / 0.30 / 0.05 |
| `pebblepaw` | 10 | — | any | 2 × Pebble Cairn ×2.0; 2 × Stream Stones ×1.5 | 1.1 | 0.20 / 0.10 / 0.05 / 0.15 / 0.50 |
| `honeyhum` | 6 | 2 × Buttercup | any | 3 × Button Daisy ×1.5; clear ×1.2; dawn ×1.4; day ×1.4 | 0.9 | 0.10 / 0.50 / 0.10 / 0.25 / 0.05 |
| `fernwhisk` | 6 | 3 × Forget-me-not | any | rain ×1.3; golden ×1.5; dusk ×1.5 | 1.0 | 0.35 / 0.15 / 0.05 / 0.30 / 0.15 |
| `dandelfluff` | 6 | 2 × Dandelion | any | 3 × Leaf Pinwheel ×1.5; breeze ×2.5 | 0.8 | 0.15 / 0.10 / 0.30 / 0.40 / 0.05 |
| `bellkin` | 6 | 3 × Bluebell | any | 1 × Shell Wind Chime ×2.5; breeze ×1.3 | 1.0 | 0.25 / 0.15 / 0.20 / 0.25 / 0.15 |
| `primpip` | 6 | 3 × Primrose | any | 3 × Pebble Cairn ×2.0; dawn ×1.5 | 1.0 | 0.30 / 0.25 / 0.10 / 0.25 / 0.10 |
| `capling` | 4 | 5 × Toadstool Seat | any | 5 × Sweet Clover ×1.3; rain ×1.8 | 1.0 | 0.15 / 0.10 / 0.50 / 0.20 / 0.05 |
| `puddlewump` | 4 | 5 × Stream Stones | any | 2 × Pebble Cairn ×1.3; rain ×4.0 | 1.0 | 0.10 / 0.05 / 0.35 / 0.10 / 0.40 |
| `glowmote` | 4 | 5 × Firefly Lantern | dusk, night | 2 × Moonbloom ×2.0; clear ×1.3 | 1.2 | 0.30 / 0.10 / 0.10 / 0.30 / 0.20 |
| `moonpuff` | 3 | 5 × Moonbloom, 5 × Shell Wind Chime | night | 6 × Firefly Lantern ×1.5; clear ×1.5 | 1.5 | 0.60 / 0.05 / 0.05 / 0.15 / 0.15 |

Item counts mean **bloomed stems** for flowers and **copies** for décor. A species with unmet `requires`, or outside its `phases`, has weight 0. Its favourite spot always exists when it can visit (validator check).

### 4.2 Flowers (8) ⟲ `flora.json`
Times are cumulative from planting. Price of copy n (n = copies already owned, 0-based) = ⌊cost_base · r^n + 0.5⌋.

| # | id | Name (en / vi) | Sprout | Bud | Bloom | Dew/h per bloom | Snug | Opens | Price copy 1 → 10 | All 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `sweet_clover` | Sweet Clover / Cỏ ba lá | 2 min | 12 min | 42 min | 0.5 | 1 | any | 15 → 35 (r = 1.10) | 239 |
| 2 | `button_daisy` | Button Daisy / Cúc dại | 5 min | 25 min | 1.1 h | 0.5 | 1 | any | 24 → 57 (r = 1.10) | 383 |
| 3 | `buttercup` | Buttercup / Mao lương vàng | 5 min | 35 min | 1.6 h | 0.6 | 1 | any | 34 → 80 (r = 1.10) | 541 |
| 4 | `forget_me_not` | Forget-me-not / Lưu ly | 10 min | 40 min | 2.2 h | 0.7 | 1 | any | 46 → 108 (r = 1.10) | 733 |
| 5 | `bluebell` | Bluebell / Chuông xanh | 10 min | 1.2 h | 3.2 h | 0.8 | 1 | any | 60 → 141 (r = 1.10) | 957 |
| 6 | `primrose` | Primrose / Anh thảo | 10 min | 1.2 h | 4.2 h | 0.9 | 1 | any | 72 → 170 (r = 1.10) | 1,147 |
| 7 | `dandelion` | Dandelion / Bồ công anh | 10 min | 1.2 h | 5.2 h | 1.0 | 1 | any | 88 → 207 (r = 1.10) | 1,402 |
| 8 | `moonbloom` | Moonbloom / Hoa quỳnh | 20 min | 2.3 h | 6.3 h | 1.5 | 2 | dusk/night | 150 → 354 (r = 1.10) | 2,393 |

Who each flower attracts ⟲: 

- Sweet Clover: Puffmoss ×1.5 at 3+; Buttonbud ×1.3 at 3+; Capling ×1.3 at 5+
- Button Daisy: Buttonbud ×2.0 at 3+; Honeyhum ×1.5 at 3+
- Buttercup: Honeyhum needs 2 in bloom
- Forget-me-not: Fernwhisk needs 3 in bloom
- Bluebell: Bellkin needs 3 in bloom
- Primrose: Primpip needs 3 in bloom
- Dandelion: Dandelfluff needs 2 in bloom
- Moonbloom: Glowmote ×2.0 at 2+; Moonpuff needs 5 in bloom

Notes:
- Forms (`form`) feed the procedural L-system presets: globe, daisy, cup, cluster, bell, primrose, puff, lily. Moonbloom petals close by day (still counts as bloomed) and open with a faint glow from dusk.
- The tutorial clover is a free copy (copy #1 of 10) with stages 10 s / 40 s / 90 s.
- Growth visuals: sprout = two leaves; bud = closed head that sways; bloom = open, with dew beads catching light. Growth steps use the `move` spring stretch (05 §3.3).

### 4.3 Décor (6 sets) ⟲ `decor.json`
| # | id | Name (en / vi) | Snug / copy | Price copy 1 → 10 | All 10 | Attracts | Look & feel |
|---|---|---|---|---|---|---|---|
| 9 | `leaf_pinwheel` | Leaf Pinwheel / Chong chóng lá | 2 | 70 → 194 (r = 1.12) | 1,227 | Dandelfluff ×1.5 at 3+ | spin_with_wind |
| 10 | `pebble_cairn` | Pebble Cairn / Tháp sỏi | 2 | 75 → 208 (r = 1.12) | 1,316 | Pebblepaw ×2.0 at 2+; Primpip ×2.0 at 3+; Puddlewump ×1.3 at 2+ | stack_grows |
| 11 | `toadstool_seat` | Toadstool Seat / Ghế nấm | 3 | 85 → 236 (r = 1.12) | 1,492 | Capling needs 5 | ring_forms, rain_shelter |
| 12 | `stream_stones` | Stream Stones / Đá suối | 3 | 95 → 263 (r = 1.12) | 1,665 | Pebblepaw ×1.5 at 2+; Puddlewump needs 5 | water_riffle |
| 13 | `firefly_lantern` | Firefly Lantern / Đèn đom đóm | 4 | 150 → 416 (r = 1.12) | 2,632 | Glowmote needs 5; Moonpuff ×1.5 at 6+ | glow_golden_dusk_night, fireflies_gather |
| 14 | `wind_chime` | Shell Wind Chime / Chuông gió vỏ ốc | 4 | 190 → 527 (r = 1.12) | 3,334 | Bellkin ×2.5 at 1+; Moonpuff needs 5 | adds_chime_note, rings_with_wind |

Each copy adds the next piece at its anchor (§2.5). Effects beyond attraction (`fx`): pinwheels spin with `g_wind`; the cairn grows one pebble taller per copy; ten toadstools close a fairy ring (shelter in rain); stream stones add riffles to the water sound; lanterns glow from golden hour to morning and draw fireflies (particle budget shared, D9); **each wind-chime shell adds one note** of F-Lydian pentatonic over two octaves (F4 G4 A4 C5 D5 F5 G5 A5 C6 D6), and the chime rings on breeze gusts (every 8–20 s in breeze, 30–60 s otherwise) using only owned shells.

### 4.4 Leaf boat (the always-affordable ritual)
- Cost `leaf_boat_cost` = **1 dew**, unlimited, found as the last row of the Garden → Décor tab.
- A boat appears at the spring rock and drifts the stream polyline right→left in `leaf_boat_drift_s` = 40 s (a candle on it from golden hour to dawn). Up to 3 on the water; extra taps queue 4 s apart.
- Every mossling present that has not yet watched a boat this visit gains +1 affection. The 10th boat ever sends a postcard. Pure delight, no economic return.

### 4.5 Gift items
Visual types for basket gifts (⟲ `economy.json:gift_items`, assigned per species `gift_item`): acorn cup of dew, petal bundle, shiny pebble, seed-pod pouch, moonlit dewdrop. The dew value is the species' `gift_dew` (onboarding overrides: 18 and 12).

---

## 5. Economy and visitor model

### 5.1 Currencies
- **Dew** — the only spendable currency. Shown as a drop icon and an integer (Baloo 2, MSDF). Never negative, never decays, never displayed above 99,999.
- **Affection** — per individual, integer points, **never decays and is never spent**. Shown only as hearts (0–5). See §7.4.

### 5.2 Prices
- `price(item, n) = floor(cost_base · cost_growth^n + 0.5)`, n = copies owned (the free tutorial clover counts as owned).
- `cost_growth` r = **1.10 for flowers, 1.12 for décor**; `max_copies` = **10** everywhere (04 §4.2: last copy = r⁹ = 2.36× / 2.77× the first).
- Catalogue: 140 copies, total **19,461 dew** (flowers 7,795; décor 11,666). ⟲ Full price ladders:

| id | #1 | #2 | #3 | #4 | #5 | #6 | #7 | #8 | #9 | #10 |
|---|---|---|---|---|---|---|---|---|---|---|
| `sweet_clover` | 15 | 17 | 18 | 20 | 22 | 24 | 27 | 29 | 32 | 35 |
| `button_daisy` | 24 | 26 | 29 | 32 | 35 | 39 | 43 | 47 | 51 | 57 |
| `buttercup` | 34 | 37 | 41 | 45 | 50 | 55 | 60 | 66 | 73 | 80 |
| `forget_me_not` | 46 | 51 | 56 | 61 | 67 | 74 | 81 | 90 | 99 | 108 |
| `bluebell` | 60 | 66 | 73 | 80 | 88 | 97 | 106 | 117 | 129 | 141 |
| `primrose` | 72 | 79 | 87 | 96 | 105 | 116 | 128 | 140 | 154 | 170 |
| `dandelion` | 88 | 97 | 106 | 117 | 129 | 142 | 156 | 171 | 189 | 207 |
| `moonbloom` | 150 | 165 | 182 | 200 | 220 | 242 | 266 | 292 | 322 | 354 |
| `leaf_pinwheel` | 70 | 78 | 88 | 98 | 110 | 123 | 138 | 155 | 173 | 194 |
| `pebble_cairn` | 75 | 84 | 94 | 105 | 118 | 132 | 148 | 166 | 186 | 208 |
| `toadstool_seat` | 85 | 95 | 107 | 119 | 134 | 150 | 168 | 188 | 210 | 236 |
| `stream_stones` | 95 | 106 | 119 | 133 | 149 | 167 | 188 | 210 | 235 | 263 |
| `firefly_lantern` | 150 | 168 | 188 | 211 | 236 | 264 | 296 | 332 | 371 | 416 |
| `wind_chime` | 190 | 213 | 238 | 267 | 299 | 335 | 375 | 420 | 470 | 527 |

### 5.3 Income
Two sources, both passive, both saturating so that absence is rewarded but bounded:
1. **Visitor gifts** — each visit leaves one gift on departure (`gift_dew` 12 / 15 / 20 / 28 by rarity) into the **24-slot basket**.
2. **Dew cup** — the moss and the bloomed flowers condense dew continuously:
   `cup_rate (dew/h) = dew_cup_base_per_h (6) + Σ_bloomed_stems dew_per_hour(flower)` (max 6 + 65 = 71/h with every stem in bloom).
   The cup accrues only while `t < last_collect + dew_cup_saturation_s` (12 h), then shows "brimming". Collecting takes `floor(cup)`; the fractional remainder stays (nothing lost).

Passive income right now (used by the pacing metric): `income/min = (cup_rate + λ(S) · mean_gift_eligible) / 60`, where mean_gift_eligible is the weight-averaged `gift_dew` of currently eligible species.

### 5.4 Visitors: Poisson arrivals modulated by snugness
- **Snugness** S = Σ_bloomed stems `snug` (1; Moonbloom 2) + Σ_décor copies `snug` (2–4). Range 0–270. Not shown as a number; the hollow simply looks cozier.
- **Arrival rate** λ(S) = λ_min + (λ_max − λ_min) · S / (S + S_half), with λ_min = 1.4/h, λ_max = 2.6/h, S_half = 45 → ⟲:

| Snugness | lambda (visits/h) | Basket full after (h) |
|---|---|---|
| 0 | 1.40 | 17.1 |
| 30 | 1.88 | 12.8 |
| 60 | 2.09 | 11.5 |
| 120 | 2.27 | 10.6 |
| 240 | 2.41 | 10.0 |

- Implementation: a homogeneous candidate process at λ_max (next candidate = now + Exp(λ_max)), each candidate accepted with probability λ(S)/λ_max (thinning — exact for a piecewise-constant λ). The first candidate is drawn at `poisson_start_s` (300 s).
- **Stay** = U(40, 80 min) × `stay_mult`. Mean presence ≈ λ × 1 h ≈ 2.1–2.4 mosslings.

### 5.5 Who comes (species choice and debuts)
At an accepted arrival time t:
1. `eligible` = species not currently present, with every `requires` met and (if `phases` non-empty) the current phase listed.
2. `w(k) = base_weight · Π(mult of satisfied likes_items, likes_weather, likes_phases) · (1.25 if ♥5)`.
3. **Debut rule**: if any eligible species has never been met, with probability `debut_chance` = 0.6 the pick is made among those only (weighted by w). This makes discovery feel responsive ("I planted bluebells and a Bellkin came") without guaranteeing it on a clock.
4. Otherwise pick among all eligible by w. If none is eligible, the candidate is skipped.

### 5.6 Presence, gifts and the greeter
- A visit: +1 affection on arrival; gift on departure (§5.7). More than `max_present` (5) → peek visit (§4.1.3).
- **Greeter rule** (E3/E5): when the app is opened (or resumed) and **either nothing happened since the last close or nobody is in the hollow**, an already-met mossling that is not present strolls in from its entry `greeter_delay` 4–10 s after the world is visible (after the recap). It is a hello, not a visit: **no gift and no visit affection**, so opening the app often is never an advantage. It stays until the app is backgrounded or 5 min pass, then leaves like a visitor. Petting it counts only if that individual has not been petted in the last 60 min. If a real arrival picks the greeter's species, the greeter simply becomes that visit.

### 5.7 Basket, photos and brimming
- On departure: if the basket has a free slot → the gift goes in (and 15 % of the time the friend also leaves a **photo**); if the basket is full (24) → the friend leaves a **photo** instead. First time the basket fills → postcard "brimming". Photos never stop, so a long absence always brings something to see.
- **Collect all** moves every gift and `floor(cup)` into the wallet in one tap. **Wallet cap** 99,999: if a gift would exceed it, that gift waits in the basket and the sheet says the dew jar is brimming (still good news; E6 holds by construction).
- Display bounds: max gift 28, basket ≤ 672, cup ≤ 852, wallet ≤ 99,999, prices ≤ 527.

### 5.8 World step and offline progress (one algorithm for live and offline)
- All world timestamps are in **world seconds** (a monotonic world clock saved in the save file), not wall time.
- `advance(to)` processes, in time order, every event in (now, to]: next arrival candidate, earliest departure, next growth stage, next scripted onboarding event. Ties: scripted → growth → departure → candidate. Before any change of the cup rate (a bloom) the cup is settled. Nothing in `advance` ever removes or decreases anything (E1). `tools/sim/economy_sim.py: Player.advance` is the reference implementation.
- **Live play** calls `advance(world_now)` every frame (cheap: usually no event). Phase and weather are read from the device's local wall clock.
- **On resume/launch**: `delta = clamp(now_unix − saved_at_unix, 0, offline_clamp_s = 7 d)`; `advance(world + delta)`; during catch-up the wall time of an event is `now_unix − (world_end − t_event)`, used for phase/weather lookups. Any time beyond 7 days is skipped ("the hollow rested"): timers are in world seconds, so nothing jumps or is lost.
- **Clock rolled back** (delta < 0): delta = 0, re-anchor `saved_at` to now, nothing changes (sim-tested).
- Saves: JSON per D12 (tmp → rename, `.bak`, on FOCUS_OUT, PAUSED and every 30 s). Persist at least: schema, install_seed, rng state, world clock, saved_at_unix, dew, basket entries {species, gift_item, dew}, cup value + last_collect, stems {flower, bed, slot, planted_world_t}, décor counts, present visitors {species, arrive_t, depart_t, gift, boat_credit, pet_credit, scripted}, next_candidate_t, met {species: first_met_unix}, custom names, affection, photos, postcards {id, species, received_unix, read}, boats, onboarding step and flags (tutorial seed planted, basket_full_seen, postcards sent).

### 5.9 Seasons (structure only in the MVP)
`season_index = floor(world_days / length_days) mod len(season_cycle)`; MVP cycle = [spring]. Content carries `seasons` tags; a species out of season has weight 0, a flower out of season stays planted and keeps counting (nothing is removed, seasons recur — E8).

### 5.10 Affection and hearts
+1 per visit (arrival), +1 per pet (once per visit), +1 per leaf boat watched (once per visit). Hearts at **3 / 8 / 15 / 25 / 40** points (`heart_thresholds`). Unlocks in §7.4.

### 5.11 Why E5 holds by construction (and the sim confirms it)
- **Affordable**: the minimum gap between sessions is 10 min; the cup gains at least 6 dew/h × 1/6 h = 1 dew in any gap of 10 min–12 h (and ≥ 72 dew beyond), the fractional remainder is kept, and the leaf boat costs 1. At install, the free tutorial seed is the action. At the wallet cap, dew ≥ 1. So **every session can buy something meaningful** whatever the player spent before — even the sim's "drain" players who float boats with every last drop.
- **Something new**: either something happened while away (90 % of sessions organically), or a visiting mossling is visibly doing something new (bouts ≤ 6 min < 10 min, never repeated), or the greeter walks in, or the palette/weather changed.
- Catalogue health is tracked separately: a new flower/décor copy is affordable at **99.5 % of sessions after ≥ 3 h away** (§9).

---

## 6. Weather and time of day (device clock)

### 6.1 Phases and palettes ⟲ `world.json`
| Phase | Starts (local) | `g_day` | Audio profile | Cross-fade |
|---|---|---|---|---|
| Dawn | 05:00 | 0.2 | dawn | palette lerps from the previous key over 40 min starting at the phase start (`phase_crossfade_s` 2400); audio profile switches over 90 s at the start |
| Day | 08:00 | 0.4 | day | " |
| Golden hour | 16:30 | 0.6 | day | " |
| Dusk (blue hour) | 18:30 | 0.8 | dusk | " |
| Night | 20:30 | 1.0 (= 0.0) | night | " ; `g_day` wraps 1.0 → 0.0 at midnight, seamless because the gradient has night at both ends |

The five palettes are 05 §0.4 (OKLab `Gradient` sampled by `g_day`, D8). Gameplay uses the phase id for `phases`/`likes_phases`. **Audio note:** these boundaries supersede 06 §0.4's 05/09/17/21 table so picture and sound turn together.

Per phase: dawn — birds every 6–15 s, low mist, long cool shadows; day — dust motes in sun shafts, butterflies; golden — peach-fuzz rim light on mosslings, lanterns begin to glow, pollen drifts; dusk — fireflies (8–20) wake, moonbloom opens, lanterns full; night — moon, stars twinkle 0.2–0.5 Hz, most mosslings nap (×3), crickets low in the mix.

### 6.2 Weather
Three states. A **day plan** per local calendar day is drawn deterministically from (install seed, day index): rain episode count ∈ {0, 1, 2} with p = 0.30 / 0.45 / 0.25, breeze episode count ∈ {0, 1, 2, 3} with p = 0.10 / 0.25 / 0.40 / 0.25; each episode starts uniformly in the day and lasts 1–3 h; episodes may cross midnight; **rain wins over breeze, otherwise clear**. Measured over 300 installs × 30 days: soft rain 7.9 % of the time, breeze 13.1 %, clear 79.1 %. Transitions cross-fade over **30 s** (particles fade in over ≥ 300 ms, `g_wind` tweens, audio beds cross-fade).

| | Clear | Breeze | Soft rain |
|---|---|---|---|
| `g_wind` | 0.35 | 0.85 (sway ×1.6, gusts every 6–10 s) | 0.55 |
| Sky | light shafts, dust motes | clouds drift ×2, pollen and dandelion seeds | cloud cover 0.85, sun halo ×0.4, `ambient` multiply 0.92 |
| Particles | motes 15–40 | seeds/pollen 5–12 | rain streaks ≈ 120 (≤ 150 cap) + 4–8 ground ripples/s; no fireflies |
| Sound (06) | stream + wind | wind layer +4 dB, chime rings more | rain bed replaces stream, music density −0.1; **no thunder, ever** |
| Mosslings | normal | Dandelfluff ×2.5, Bellkin ×1.3; pinwheels spin | shelter or leaf umbrellas; Puddlewump ×4, Capling ×1.8, Fernwhisk ×1.3 |

Rain is "threat as contrast" only in the coziest sense: it is gentle, everyone is sheltered, and it brings rain-loving friends.

### 6.3 What the clock never does
It never closes anything, never makes anyone sad, never penalizes the player for playing at night or never at night: night visitors arrive while you sleep and are waiting in the recap and the album.

### 6.4 Seasons
See §5.9. Each future season adds flowers, species and a palette shift, and recurs every cycle; nothing is exclusive.

---

## 7. Album, postcards, photos, naming, petting, settings

### 7.1 Album (collection)
Three tabs: **Friends**, **Photos**, **Postcards**.
- **Friends**: 12 cards in `album_order`. Unmet: soft silhouette, "Not met yet", the hint line, and requirement icons with dots (● ◐ ○), plus a moon icon for night-only friends. Met: live portrait (the rig, idle-breathing, at the current palette), name (tap the pencil to rename), hearts, "Favourite spot" (shows "Still a little secret" until ♥1), "First met on {date}", photo strip (5 poses), "Likes" (revealed at ♥3). If the friend is currently in the hollow: a **Pet** button (accessible alternative to long-press).
- **Photos**: per friend, 5 pose slots (nap, sipping dew, playing, wandering, by the stream) = 60 total. A photo is *metadata* (species, pose, phase, weather, world time) rendered live by the rig, so no screenshots are stored. Re-taking a pose refreshes its time-of-day variant.
- **Postcards**: newest first; unread marked with a small dot (not a number).
- The counter "{met} of {total} friends met" is the only collection number. No percentages.

### 7.2 Postcards (20 templates ⟲ `strings.csv: POSTCARD_*`)
- **Friendship**: each species has two templates (`postcard_heart2`, `postcard_heart4`) from 12 friend templates, signed "— {name}" with the player's chosen name. 24 deliveries in total.
- **Events** (`economy.json:event_postcards`, signed "— the hollow"): welcome (240 s), first bloom of a bought flower, first décor, first rainy visit, first night visitor, basket brimming, 10th leaf boat, all friends of spring met. 8 deliveries.
- Delivery: the mailbox flag pops up (S07, paper rustle); tap the mailbox or open Album → Postcards. Reading is optional and nothing waits on it.

### 7.3 Naming
- Every friend has a default name per language (`SPECIES_*_DEFAULT_NAME`). Renaming: tap the name on the new-friend card or in the album → `LineEdit` with the platform keyboard, max **12 characters**, trimmed; empty → default. A custom name is shown in every language.
- **Allowed characters = the subset font's coverage** (Latin + Vietnamese + digits + space + `- ' .`), because fonts have no system fallback (D6); other characters are silently filtered while typing (no error). Input is NFC-normalized before saving.

### 7.4 Petting and hearts
- Long-press 450 ms or stroke (§3.1). Purr S03 loops while held; haptic: Subtle = none during the purr, Full = TICK every 120 ms (≥ 60 ms apart). On release 3–5 hearts float up (fade in ≥ 300 ms).
- Unlocks: ♥1 favourite spot revealed · ♥2 first postcard · ♥3 "Likes" list revealed + greets you with a wave on arrival · ♥4 second postcard · ♥5 **best friend**: golden frame in the album, visit weight ×1.25.
- Reference player: 11 best friends by day 30 (median).

### 7.5 Welcome-back recap
Shown on resume when the gap ≥ `welcome_back_min_gap_s` (20 min) and at least one event happened. A frosted card over the living world, up to 3 lines chosen in priority order: new friend → postcard → "{name} napped at the {spot}" (the longest nap of the absence) → gifts waiting → new flowers opened → photos → it rained. Sound S10, MEDIUM haptic once. Auto-continues after 5 s; tap anywhere skips. Never lists what *didn't* happen.

### 7.6 Settings (X1) — one sheet, grouped
| Group | Setting | Values (default **bold**) | Effect |
|---|---|---|---|
| Comfort | Reduce motion | on / **off** (default follows the OS where readable: Android `ValueAnimator.areAnimatorsEnabled()`, Web `prefers-reduced-motion`) | `g_motion` 0.3, cross-fades ≤ 150 ms replace moves, parallax and camera drift off, particles ×0.3, ambient loops ≥ 4 s |
| Comfort | Reduce transparency | on / **off** | glass → 100 % surface fill |
| Comfort | Text size | **100** / 115 / 130 / 150 / 200 % (default nearest Android `font_scale`) | rebuild theme font sizes; hit areas unchanged |
| Comfort | Hide buttons while I watch | **on** / off | ambient mode after 60 s idle |
| Comfort | Keep the screen on while I watch | on / **off** | `screen_set_keep_on` only in ambient mode |
| Sound | Music | **On** / Nature sounds only / Off | 06 §0.3 fatigue guard still applies |
| Sound | Music / Nature / Effects volume | 0–100, step 10, **80** | bus gains |
| Sound | Mono audio | on / **off** | Master `AudioEffectStereoEnhance pan_pullout = 0` |
| Sound | Sound captions | on / **off** | caption bubbles for meaningful sounds (`CAPTION_*`) |
| Touch | Haptics | Off / **Subtle** / Full | D11 |
| Touch | Left-handed | on / **off** | mirrors the dock and HUD |
| — | Language | **Same as device** / English / Tiếng Việt | device locale `vi*` → vi, else en |
| About | Privacy line, Credits, Licenses, Version | — | Godot MIT notice, OFL fonts |

There is deliberately **no "reset game"** in the MVP (no destructive action reachable by a stray tap).

---

## 8. UI flow, input and copy

### 8.1 Screens and sheets
```
Boot (splash + warm-up) ──▶ Main = World + HUD + Dock
                              │  ├─ Recap card (if eligible) ─ tap/5 s ─▶ Main
                              │  ├─ New-friend card ─ tap ─▶ Main (shrinks into Album)
                              │  └─ Postcard reader (from mailbox) ─ tap/Back ─▶ Main
Dock:  [Settings] [Garden] [Basket] [Album]      (left-handed: [Album] [Basket] [Garden] [Settings])
  Garden sheet  ─ tabs Flowers | Décor (+ Leaf boat row) ─ item card ─ Plant/Place ─(first copy: choose bed)─▶ Main
  Basket sheet  ─ 24-slot grid + dew cup + [Collect all]
  Album sheet   ─ tabs Friends | Photos | Postcards ─ friend detail (rename, Pet, photos)
  Settings sheet─ groups §7.6
Back (Android) closes the top-most card/sheet; at Main it opens "Leave the hollow for now?" [Stay a while] [Leave for now]
```
- **Dock**: 4 buttons, centres at x = 135 / 405 / 675 / 945 px, hit 76 dp (228 px) each, gaps ≥ 42 px. The frequent pair (Garden, Basket) sits in the centre with 72 dp visuals; Settings and Album 56 dp visuals. Faux glass (no screen read, C7). The Basket shows a small gift-count badge (≤ 24) and a brim sparkle when full.
- **HUD (Z1, passive)**: dew chip (top-left, appears after the first collect), time/weather chip and the "just watch" eye (top-right, 72 dp hit). Mirrored when left-handed.
- **Sheets**: bottom sheets rising from the dock, ≤ 60 % of the height, `standard` 320 ms in / `exit` ≈ 220 ms out; exactly one at a time; the open sheet is the one live-glass surface (C7). Close by tapping the scrim, swiping down (> 25 % of height or > 1000 px/s), Back, or tapping the same dock button. Tapping another dock button swaps sheets (200 ms cross-fade).
- **Garden item card**: icon (live mini-render), name, price chip with drop icon, "{owned} of {max}", dew-yield drops (flowers), bloom time ("Blooms in about 40 min"), "Loved by {names}" for met friends or "A friend you haven't met yet loves these", primary button **Plant / Place** at the card's bottom. Unaffordable: button reads "A little more dew", price chip in `ink_2`; pressing it gives the soft S11 tok and a ±2 dp wiggle — never red, never a buzz.

### 8.2 Gestures (I3)
- **Tap**: pressed state on touch-down in the same frame; action on touch-up inside the target; sliding off cancels.
- **Long-press**: 450 ms, radial fill from 150 ms, cancelled by > 24 px movement. Every long-press action has a tap alternative (Pet button, bed card via tap on the bed's info chip).
- **Drag**: starts after 24 px (`gui/common/drag_threshold = 24`); used only for stroking mosslings, scrolling sheets and swipe-to-dismiss. No drag starts within 24 dp of a side edge.
- No double-tap, no multi-touch, no timed or rapid input. Pinch is not used.

### 8.3 Feedback map (I1, A3, A4)
| Event | Visual (≤ 100 ms to first change) | Sound (06 §0.5) | Haptic (Subtle / Full) |
|---|---|---|---|
| Any touch-down | tint +6 L*, UI scale 0.96 in 80 ms / world squash 0.94 | S01 | — / TICK |
| Tap mossling | look-at, chirp bubble, name tag 2 s | S12 at `voice_step` | — / TICK |
| Pet | radial fill, squash 0.88, hearts on release | S03 loop | — / TICK every 120 ms |
| Ready bud | unfurl 600 ms, sparkles | S04 | — / TICK at end |
| Plant / place | seed arc 320 ms, soil puff / piece settles 500 ms | S05 | — / TICK |
| Collect | gifts fly to HUD, counter rolls 600 ms | S02 ladder | DOUBLE / DOUBLE |
| New friend | card rises (`emphasized` 500 ms) | S09 | MEDIUM / MEDIUM |
| Welcome back | recap card | S10 | MEDIUM once |
| Sheet open / close | rise / exit | S07 / S08 | — |
| Not affordable | price chip pulse, ±2 dp wiggle | S11 (soft tok, no buzz) | — |
| Stream tap | ripple ring 380 ms | S06 | — |
| Leaf boat | boat launches at the spring | S06 + paper | — / TICK |
| Postcard | mailbox flag pops | S07 | — |
| Arrival / falls asleep | fade-in 400 ms / curls up | S12 | — |
Captions (setting) show `CAPTION_*` bubbles next to the source.

### 8.4 Targets (I2)
Play zone ≥ 60 dp, look zone ≥ 64 dp, HUD ≥ 72 dp, dock ≥ 76 dp; gaps ≥ 8 dp; world hit areas extend 4 dp downward (02 §1.1). Mossling hit circle ≥ 60 dp whatever its visual size. No required target in Z0, Z1 or Z5. The validator enforces static targets (§10); dynamic mosslings use hit priority (§2.5).

### 8.5 Text rendering
Nunito 500/700/800, Baloo 2 700 (D6); type scale Caption 36 / Label 42 / Body 48 / HUD numerals 66 / Title 84 px; Vietnamese lines +12 % line spacing; dark text on pastels, never white on pastel (X2). HUD strings have a 2-line or ellipsis fallback at 200 % text.

### 8.6 Copy tone guide and banned words (E8)
**Voice:** warm, small and concrete. Present tense. Nature nouns. Short sentences. Mosslings speak in first person ("I", *mình*) and call the player "you" (*bạn*). Good news only; describe what *is*, never what is missing. At most one exclamation mark per string, only for joy. Numbers only where needed (prices, dew, "3 of 12").

| Do | Don't |
|---|---|
| "Blooms in about 40 min" | "Only 40 min left!" |
| "A little more dew" | "Not enough dew" / "Insufficient funds" |
| "Pip dropped by" | "Pip missed you" |
| "The basket is brimming" | "Basket full — collect now or lose gifts" |
| "Leave for now" / "Stay a while" | "Are you sure you want to quit?" |

**Vietnamese:** natural northern-standard Vietnamese, not literal. Mosslings use *mình – bạn*; UI uses soft imperatives sparingly softened with *nhé*. Prefer native words over Sino-Vietnamese where both exist (*ghé chơi*, not *viếng thăm*). Diacritics NFC. Species and spot names are proper names (*Rêu Bông*, *Phiến đá nắng*); flower names are common nouns in sentence case (*Cỏ ba lá*, *Lưu ly*).

**Banned (lint in `validate_content.py`, word-boundary, case-insensitive):**
- en: hurry, rush, urgent, "quick!", last chance, limited, expire(s/d), expiring, ending soon, don't miss, miss you / miss out, streak, daily, every day, come back, lonely, sad, hungry, starving, thirsty, wilt*, wither*, dead, die(s/d), dying, lost, lose, fail*, error, wrong, penalty, punish*, waste*, "only N left", now or never, before it's gone, deadline, countdown, boost, premium, buy now, sale, deal, exclusive, neglect*, abandon*, forgot(ten), timer.
- vi: nhanh lên, khẩn, gấp gáp, cơ hội cuối, sắp hết, hết hạn, giới hạn, có hạn, bỏ lỡ, chuỗi ngày, điểm danh, mỗi ngày, hằng ngày, hàng ngày, quay lại ngay, nhớ bạn, cô đơn, buồn (except *buồn ngủ*), đói, khát, héo, chết, mất, thua, thất bại, lỗi, sai, phạt, lãng phí, bỏ rơi, khuyến mãi, giảm giá, độc quyền, đếm ngược.

### 8.7 String keys
All 271 player-facing strings, en + vi, are in Appendix A (copied from `i18n/strings.csv`, which wins). Placeholders use `{name}` style for `String.format()`: `{count} {name} {spot} {flower} {names} {time} {hours} {minutes} {owned} {max} {met} {total} {hearts} {date} {bed} {behaviour} {percent} {version}`. No plural forms are needed: every string is phrased to avoid them (no `?plural` column).

---

## 9. Validation (economy simulation)

### 9.1 Method
`tools/sim/economy_sim.py` (numpy, seed 20261020, 4 worker processes) loads `data/*.json` and contains **no game constants**; only player behaviour lives in the script:
- **10,000 random players**, each with its own mix of 30 s / 3 min / 10 min sessions (Dirichlet) and its own typical gap (log-uniform median 20 min–1 day, lognormal σ = 1, clipped to 10 min–3 days), install at a random local hour 07–23, 10 % never tap the tutorial seed in the first session.
- **Spending policies** (share): *gentle* 35 % (≤ 1/2/3/4 purchases per 30 s/3 min/5 min/10 min session, sometimes skips, sometimes saves), *keen* 40 % (≤ 2/5/6/10), *greedy* 15 % (buys everything affordable), *drain* 10 % (greedy, then floats leaf boats with every remaining drop — the E5 stress case). Players follow album hints toward the next friend 0–70 % of the time.
- **2,000 reference players**: install 20:00, then 2 × 5 min per day (08:00 and 20:00 ± 30 min), half gentle and half keen — the GDD pacing yardstick.
- Plus a **30-day absence** test (clamped to 7 days), a clock-rollback test and a deterministic trace of the first 300 s.
- Iteration log: first pass failed E5 at install sessions and on early "everyone is already here" sessions, and pacing was too slow (median all-12 at day 16) → added the free-seed/greeter/bout rules (§5.11), bigger visitor gifts with a smaller moss drip, hint-directed players, λ_min 1.0 → 1.4/h; then discovery was too fast (day 7) → raised rare requirements to 5 copies; then next-purchase minutes were too high (98) → raised flower dew yields; finally breeze was rarer than intended (10 % of the time) → more breeze episodes. Final numbers below.

### 9.2 Results (final run)
Simulated 10,000 random-schedule players + 2,000 reference players (2 x 5 min/day), 30 days, 2,985,975 sessions, seed 20261020, 197 s.

| Check | Result | Target | Verdict |
|---|---|---|---|
| E1 no decrease (all sessions + 30-day absence) | 0 violations | 0 | PASS |
| E1 clock rollback | unchanged | unchanged | PASS |
| E5 sessions with nothing affordable | 0 of 2,985,975 | 0 | PASS |
| E5 sessions with nothing new to see | 0 of 2,985,975 | 0 | PASS |
| E6 max displayed value | 51,734 | <= 99,999 | PASS |
| E6 max price | 527 | <= 99,999 | PASS |
| First visitor (s) | 20-40 | 20-40 | PASS |
| Species met in the 5-min first session | 3-3 | 3 | PASS |
| Reference: species by 24 h (median) | 4 | 4-6 | PASS |
| Reference: species by day 7 (median) | 11 | >= 9 | PASS |
| Reference: all 12 met, day (p10 / median / p90) | 6.0 / 8.0 / 11.0 | median 7-14 | PASS |
| Reference: players who never meet all 12 in 30 d | 0 of 2000 | 0 | PASS |
| Next purchase, minutes of passive income (days 2-10; p25 / median / p75) | 56 / 79 / 101 | median 30-90 | PASS |
| Basket saturation at mid-game snugness (h) | 11.5 | 10-14 | PASS |

| Informational metric | Value |
|---|---|
| Sessions where a new flower/decor copy is affordable (all gaps) | 59.6 % |
| ... after a gap of 3 h or more | 99.5 % |
| Sessions with organic news (without the greeter rule) | 89.9 % |
| Reference: whole catalogue bought, day (median) | 24.0 |
| Random: whole catalogue bought within 30 d | 81.4 % |
| Random 'gentle' (3493): species by day 7 / day 30 (median) | 11 / 12 |
| Random 'keen' (3994): species by day 7 / day 30 (median) | 11 / 12 |
| Random 'greedy' (1525): species by day 7 / day 30 (median) | 10 / 12 |
| Random 'drain' (988): species by day 7 / day 30 (median) | 9 / 12 |
| Final wallet after 30 d (median / max) | 32,139 / 51,734 |
| Postcards by day 30, reference (median of 32) | 31 |
| Photo poses by day 30, reference (median of 60) | 54 |
| Best friends (5 hearts) by day 30, reference (median) | 11 |
| 30-day absence: basket after return | 24 / 24 slots, cup 271 dew, photos 11 -> 44 |

| Species (reference player) | Met by day (median) | p90 |
|---|---|---|
| puffmoss | 0.00 | 0.00 |
| buttonbud | 0.00 | 0.00 |
| pebblepaw | 0.00 | 0.00 |
| honeyhum | 0.62 | 1.16 |
| fernwhisk | 1.59 | 2.63 |
| dandelfluff | 1.79 | 3.36 |
| bellkin | 2.16 | 3.70 |
| primpip | 2.68 | 4.30 |
| capling | 4.02 | 6.52 |
| puddlewump | 4.06 | 7.03 |
| glowmote | 5.97 | 8.95 |
| moonpuff | 8.04 | 11.04 |

| Snugness | lambda (visits/h) | Basket full after (h) |
|---|---|---|
| 0 | 1.40 | 17.1 |
| 30 | 1.88 | 12.8 |
| 60 | 2.09 | 11.5 |
| 120 | 2.27 | 10.6 |
| 240 | 2.41 | 10.0 |

Onboarding trace (first 300 s): 25 s meets puffmoss; 106 s basket holds 18 dew; 115 s meets buttonbud; 210 s meets pebblepaw; 226 s basket holds 30 dew

### 9.3 Reading the results
- **E1/E3**: no value ever decreased across ≈ 3 M sessions; after a 30-day absence the basket is full, the cup brimming and the photo album grew.
- **E5**: 0 sessions without an affordable purchase or something new, including the drain players.
- **E6**: the largest number ever displayed is the wallet of a gentle saver on day 30 (≈ 52 k); every price is ≤ 527.
- **Pacing**: first visitor 20–40 s; 3 friends in the first 5-min session; 4 by 24 h; all 12 by day 8 (p10 6, p90 11) for the reference player, so the "~1–2 weeks" target holds; the catalogue lasts ≈ 3.5 weeks; mid-game the next purchase costs a median of 79 minutes of passive income.
- **Known MVP characteristic** (not a failure): after the catalogue is complete (≈ day 24 for the reference player) dew keeps accumulating (median wallet 32 k on day 30). Seasons (post-MVP) are the intended sink; the 99,999 hard cap and "brimming" copy keep E6 safe meanwhile.

How to re-run: `python3 tools/sim/economy_sim.py` (≈ 4 min on 4 CPUs; `--players 500 --reference 200` for a 15 s smoke run; `--markdown FILE` writes the tables). Exit code 1 on any failed check, so it can gate CI.

---

## 10. Data files (single source of truth)

All files: UTF-8 JSON, `"schema": 1`, a `"doc"` string, snake_case ids, seconds for durations, rates per hour only where the key says `_per_h`, positions normalized to the 1080 × 1920 bottom-anchored frame. Text is never stored in data — only string keys. Validate with `python3 tools/sim/validate_content.py` (add `--format` to rewrite the canonical layout).

| File | Top-level | Record fields |
|---|---|---|
| `data/species.json` | `species[]` | `id, name_key, default_name_key, desc_key, hint_key, album_order, rarity, base_weight, gift_dew, gift_item, stay_mult, entry, favourite_spot, requires[{item,min}], phases[], likes_items[{item,min,mult}], likes_weather[{weather,mult}], likes_phases[{phase,mult}], behaviours{nap,nibble,play,wander,sit_by_stream} (sum 1), rig{body_w_h,size,ear,tail,antenna,pattern,eye,fuzz_dp,fur,fur_2,belly,accent}, voice_step, postcard_heart2, postcard_heart4, seasons[]` |
| `data/flora.json` | `flowers[]` | `id, name_key, desc_key, garden_order, form, petal_token, cost_base, cost_growth, max_copies, sprout_at_s, bud_at_s, bloom_at_s, dew_per_hour, snug, opens_at (any / dusk_night), seasons[]` |
| `data/decor.json` | `decor[]` | `id, name_key, desc_key, garden_order, anchor, cost_base, cost_growth, max_copies, snug, fx[], tap_fx, seasons[]` |
| `data/economy.json` | flat constants | `display_max, wallet_cap, offline_clamp_s, welcome_back_min_gap_s, basket_slots, dew_cup_saturation_s, dew_cup_base_per_h, lambda_min_per_h, lambda_max_per_h, snug_half, stay_min_s, stay_max_s, max_present, photo_chance_with_gift, debut_chance, affection_per_visit/pet/boat, heart_thresholds[5], best_friend_heart, best_friend_weight_mult, leaf_boat_cost, leaf_boat_drift_s, greeter_delay_min_s/max_s, rarity_order[], onboarding{…}, event_postcards[{id,template,trigger}], gift_items[{id,name_key}], validation_targets{…}` |
| `data/world.json` | clock & weather | `phases[{id,start_s,g_day,audio_profile,name_key}], phase_crossfade_s, audio_profile_crossfade_s, weather[{id,name_key,g_wind,rain_particles,cloud_cover,ambient_mult}], weather_crossfade_s, weather_plan{rain_count_probs, rain_min_s, rain_max_s, breeze_count_probs, breeze_min_s, breeze_max_s}, seasons[{id,name_key,length_days}], season_cycle[]` |
| `data/spots.json` | layout | `frame{width_px,height_px,anchor,px_per_dp}, zones[{id,y0,y1}], safe_x{x0,x1}, stream{polyline[[x,y]],water_width,tap_band_y0,tap_band_y1}, entries[{id,x,y}], spots[{id,name_key,x,y,capacity,behaviours[],shelter,requires_item,requires_min}], beds[{id,name_key,x,y,fill_order,hit_w_dp,hit_h_dp,capacity,stems[[dx,dy]],nibble_points[[x,y]]}], decor_anchors[{decor_id,layout,positions[[x,y]]}], props[{id,x,y,w_dp,h_dp,tap_action,hit_dp}]` |

`world.json` is a sixth file beyond the five requested: clock and weather numbers are needed by both the sim and the game, and do not belong in the economy file.

Validator rules (exit 1 on failure): ids unique snake_case; every reference resolves (items, spots, entries, anchors, phases, weather, seasons, gift items, string keys); r ∈ [1.10, 1.12]; copies ∈ [10, 12]; top price ≤ 99,999; stage times increase; behaviour weights sum to 1; every MVP species visits in spring; favourite spots exist whenever the species can visit; rig palette slots are `cr_*`; beds hold all flower copies; anchors hold exactly `max_copies` positions; static targets meet size floors, keep 8 dp gaps and stay clear of the dock; required targets are not in the look zone.

---

## 11. Translations
- `i18n/strings.csv` — Godot CSV translation format, header `keys,en,vi`, UTF-8 **without BOM**, Vietnamese **NFC**, comma-delimited, RFC-4180 quoting. 271 keys: UI, dock, sheets, settings, accessibility labels, captions, species (name, default name, description, hint), flowers, décor, spots, beds, behaviours, time/weather/season names, recap lines, 20 postcard templates.
- Import: Godot generates `strings.en.translation` and `strings.vi.translation` next to the CSV (verified on 4.7.2 headless; `unescape_translations` default true). Register both in `project.godot` → `internationalization/locale/translations`. Use `tr("KEY").format({...})`.
- Lint: `validate_content.py` checks header, BOM, NFC, empty cells, duplicate keys, placeholder parity between en and vi, banned words, and that every key referenced from data exists.

---

## 12. Hand-offs and open items
**Art Director / Technical Artist:** creature token names `cr_*` (20) and petal tokens `fl_*` (8) are binding names and already resolve in `data/palettes.json`; keep them in sync if tokens are renamed. Layout positions (§2) are a gameplay contract; nudges ≤ 0.02 are fine if `validate_content.py` still passes. Gift item art (5), photo poses (5) and the leaf boat are needed.
**Sound Designer:** phase boundaries in `world.json` supersede 06 §0.4 (05:00 / 08:00 / 18:30 / 20:30 for dawn / day / dusk / night profiles). Each species has a `voice_step`; wind-chime notes per §4.3; no thunder.
**Gameplay Engineer / Tech Lead:** port `Player.advance` from the sim (§5.8) as the one world step for live and offline; world seconds in the save; RNG state persisted; data loaded from JSON only. Greeter, debut, bout and wallet-cap rules are part of the contract (§5.5–5.7, §4.1.3).
**UI Engineer:** dock order and mirroring (§8.1), sheet behaviour, unaffordable state (§8.1), name input filtering (§7.3), recap (§7.5), all strings via `tr()`.
**QA:** `economy_sim.py` and `validate_content.py` are CI-ready gates (exit codes). The E1/E3 30-day screenshot diff (00 §4) still needs a render-based test.
**Open:** (1) post-catalogue dew accumulation is accepted for the MVP; revisit when Seasons land. (2) The first-visit card for night species discovered offline appears in the morning recap — playtest whether players want a "who came last night" moment in the album. (3) A one-time unlock (04 §5) is out of scope (R11).

---

## Appendix A — String keys (en + vi) ⟲ `i18n/strings.csv`
| Key | en | vi |
|---|---|---|
| `APP_TITLE` | Mossling Meadow | Mossling Meadow |
| `APP_TAGLINE` | A tiny hollow of fuzzy friends | Thung lũng nhỏ của những người bạn lông xù |
| `DOCK_GARDEN` | Garden | Khu vườn |
| `DOCK_ALBUM` | Album | Album |
| `DOCK_BASKET` | Basket | Giỏ quà |
| `DOCK_SETTINGS` | Settings | Cài đặt |
| `HUD_DEW_A11Y` | {count} dew | {count} giọt sương |
| `HUD_WATCH_A11Y` | Just watch the meadow | Chỉ ngắm đồng cỏ thôi |
| `UNIT_DEW` | dew | sương |
| `COMMON_CLOSE` | Close | Đóng |
| `COMMON_BACK` | Back | Quay lại |
| `COMMON_DONE` | Done | Xong |
| `COMMON_NOT_NOW` | Not now | Để sau |
| `TIME_MINUTES` | {minutes} min | {minutes} phút |
| `TIME_HOURS` | {hours} h | {hours} giờ |
| `TIME_HOURS_MINUTES` | {hours} h {minutes} min | {hours} giờ {minutes} phút |
| `BASKET_TITLE` | Gift basket | Giỏ quà |
| `BASKET_COLLECT_ALL` | Collect all | Nhận hết |
| `BASKET_EMPTY` | The basket is ready for gifts. | Giỏ đã sẵn sàng đón quà. |
| `BASKET_FROM` | From {name} | Từ {name} |
| `BASKET_CUP` | Dew cup | Chén sương |
| `BASKET_CUP_DESC` | Moss and flowers fill it, drop by drop. | Rêu và hoa rót đầy chén, từng giọt một. |
| `BASKET_CUP_BRIMMING` | The dew cup is brimming. | Chén sương đã đầy tràn. |
| `BASKET_FULL_NOTE` | When the basket is full, friends leave photos for you. | Khi giỏ đầy, các bạn sẽ để lại ảnh tặng bạn. |
| `BASKET_NEW_PHOTOS` | New photos in your album | Có ảnh mới trong album |
| `WALLET_BRIMMING` | Your dew jar is brimming. Gifts will wait here for you. | Hũ sương của bạn đã đầy tràn. Quà sẽ nằm đây chờ bạn. |
| `GIFT_ACORN_CUP` | Acorn cup of dew | Chén hạt dẻ đựng sương |
| `GIFT_PETAL_BUNDLE` | Petal bundle | Bó cánh hoa |
| `GIFT_SHINY_PEBBLE` | Shiny pebble | Viên sỏi lấp lánh |
| `GIFT_SEED_POUCH` | Seed-pod pouch | Túi vỏ hạt |
| `GIFT_MOON_DROP` | Moonlit dewdrop | Giọt sương ánh trăng |
| `GARDEN_TITLE` | Garden | Khu vườn |
| `GARDEN_TAB_FLOWERS` | Flowers | Hoa |
| `GARDEN_TAB_DECOR` | Décor | Trang trí |
| `GARDEN_PLANT` | Plant | Trồng |
| `GARDEN_PLACE` | Place | Đặt |
| `GARDEN_OWNED` | {owned} of {max} | {owned}/{max} |
| `GARDEN_ALL_PLANTED` | All planted | Đã trồng đủ |
| `GARDEN_ALL_PLACED` | All placed | Đã đặt đủ |
| `GARDEN_MORE_DEW` | A little more dew | Cần thêm chút sương |
| `GARDEN_BLOOMS_IN` | Blooms in about {time} | Nở sau khoảng {time} |
| `GARDEN_DEW_YIELD` | Beads dew | Đọng sương |
| `GARDEN_LOVED_BY` | Loved by {names} | {names} rất thích |
| `GARDEN_LOVED_BY_SOMEONE` | A friend you haven't met yet loves these | Có một bạn chưa quen rất thích món này |
| `GARDEN_CHOOSE_BED` | Choose a bed for your {flower} | Chọn luống cho {flower} nhé |
| `GARDEN_LEAF_BOAT` | Leaf boat | Thuyền lá |
| `GARDEN_LEAF_BOAT_DESC` | A tiny boat drifts down the stream. Friends nearby love to watch it go by. | Một chiếc thuyền nhỏ trôi theo dòng suối. Các bạn ở gần đều thích ngồi ngắm thuyền trôi. |
| `GARDEN_FLOAT` | Float | Thả |
| `GARDEN_NEW` | New | Mới |
| `BED_1_NAME` | Brookside bed | Luống bên suối |
| `BED_2_NAME` | Fern bed | Luống dương xỉ |
| `BED_3_NAME` | Sunny bed | Luống nắng |
| `BED_4_NAME` | Willow bed | Luống gốc liễu |
| `BED_5_NAME` | Stump bed | Luống gốc cây |
| `SPOT_SUN_STONE` | Sun Stone | Phiến đá nắng |
| `SPOT_MOSS_CUSHION` | Moss Cushion | Nệm rêu |
| `SPOT_CLOVER_BANK` | Clover Bank | Gò cỏ ba lá |
| `SPOT_FERN_SHADE` | Fern Shade | Bóng dương xỉ |
| `SPOT_STREAM_BEND` | Stream Bend | Khúc suối cong |
| `SPOT_WILLOW_ROOT` | Willow Root | Gốc liễu |
| `SPOT_HILL_CREST` | Hill Crest | Đỉnh đồi |
| `SPOT_STUMP_HOLLOW` | Stump Hollow | Hốc gốc cây |
| `SPOT_MOON_ROCK` | Moon Rock | Tảng đá trăng |
| `SPOT_TOADSTOOL_RING` | Toadstool Ring | Vòng nấm |
| `SPOT_STREAM_STONES` | Stepping Stones | Đá giữa suối |
| `SPOT_LANTERN_NOOK` | Lantern Nook | Góc đèn |
| `SPOT_CAIRN_SIDE` | Cairn Corner | Góc tháp sỏi |
| `BEHAVIOUR_NAP` | Snoozing | Ngủ khì |
| `BEHAVIOUR_NIBBLE` | Sipping dew | Nhấm nháp sương |
| `BEHAVIOUR_PLAY` | Playing | Nô đùa |
| `BEHAVIOUR_WANDER` | Wandering | Dạo chơi |
| `BEHAVIOUR_SIT_BY_STREAM` | By the stream | Ngắm suối |
| `TIME_DAWN` | Dawn | Bình minh |
| `TIME_DAY` | Daytime | Ban ngày |
| `TIME_GOLDEN` | Golden hour | Nắng chiều |
| `TIME_DUSK` | Dusk | Chạng vạng |
| `TIME_NIGHT` | Night | Đêm |
| `WEATHER_CLEAR` | Clear skies | Trời trong |
| `WEATHER_BREEZE` | Gentle breeze | Gió nhẹ |
| `WEATHER_RAIN` | Soft rain | Mưa phùn |
| `SEASON_SPRING` | Spring | Mùa xuân |
| `ALBUM_TITLE` | Album | Album |
| `ALBUM_TAB_FRIENDS` | Friends | Bạn bè |
| `ALBUM_TAB_PHOTOS` | Photos | Ảnh |
| `ALBUM_TAB_POSTCARDS` | Postcards | Bưu thiếp |
| `ALBUM_MET_COUNT` | {met} of {total} friends met | Đã gặp {met}/{total} bạn |
| `ALBUM_NOT_MET` | Not met yet | Chưa gặp |
| `ALBUM_FAVOURITE_SPOT` | Favourite spot | Chỗ yêu thích |
| `ALBUM_SPOT_SECRET` | Still a little secret | Vẫn còn là bí mật nhỏ |
| `ALBUM_HEARTS_A11Y` | {hearts} of 5 hearts | {hearts}/5 trái tim |
| `ALBUM_BEST_FRIEND` | Best friend | Bạn thân |
| `ALBUM_RENAME` | Rename | Đổi tên |
| `ALBUM_NAME_HINT` | A name for your friend | Đặt tên cho bạn nhỏ |
| `ALBUM_PET` | Pet | Vuốt ve |
| `ALBUM_PHOTOS_COUNT` | {count} of 5 photos | {count}/5 ảnh |
| `ALBUM_PHOTO_EMPTY` | Not taken yet | Chưa có ảnh |
| `ALBUM_FIRST_MET` | First met on {date} | Gặp lần đầu ngày {date} |
| `ALBUM_LIKES` | Likes | Thích |
| `POSTCARD_NEW_A11Y` | New postcard | Bưu thiếp mới |
| `POSTCARD_SIGNATURE` | — {name} | — {name} |
| `POSTCARD_SIGNATURE_HOLLOW` | — the hollow | — Thung lũng nhỏ |
| `NEWFRIEND_TITLE` | A new friend! | Bạn mới nè! |
| `NEWFRIEND_THIS_IS` | This is {name} | Đây là {name} |
| `NEWFRIEND_SAY_HI` | Say hello | Chào bạn ấy |
| `RECAP_TITLE` | While you were away | Trong lúc bạn đi vắng |
| `RECAP_NEW_FRIEND` | {name} visited for the first time | {name} ghé thăm lần đầu |
| `RECAP_ONE_VISITED` | {name} dropped by | {name} đã ghé chơi |
| `RECAP_FRIENDS_VISITED` | {name} and friends dropped by | {name} và các bạn đã ghé chơi |
| `RECAP_NAPPED` | {name} napped at the {spot} | {name} đã ngủ một giấc ở {spot} |
| `RECAP_BLOOMED` | New flowers opened | Hoa mới đã nở |
| `RECAP_GIFTS` | Gifts are waiting in the basket | Quà đang chờ trong giỏ |
| `RECAP_PHOTOS` | Friends left photos for you | Các bạn để lại ảnh tặng bạn |
| `RECAP_POSTCARD` | A postcard arrived | Có bưu thiếp mới |
| `RECAP_RAINED` | It rained softly | Trời đã mưa phùn nhè nhẹ |
| `RECAP_CONTINUE_A11Y` | Continue | Tiếp tục |
| `SETTINGS_TITLE` | Settings | Cài đặt |
| `SET_GROUP_COMFORT` | Comfort | Dễ chịu |
| `SET_GROUP_SOUND` | Sound | Âm thanh |
| `SET_GROUP_TOUCH` | Touch | Cảm ứng |
| `SET_GROUP_ABOUT` | About | Thông tin |
| `SET_REDUCE_MOTION` | Reduce motion | Giảm chuyển động |
| `SET_REDUCE_MOTION_DESC` | Gentler, slower movement and a still camera. | Chuyển động nhẹ và chậm hơn, khung hình đứng yên. |
| `SET_REDUCE_TRANSPARENCY` | Reduce transparency | Giảm độ trong suốt |
| `SET_REDUCE_TRANSPARENCY_DESC` | Solid panels instead of frosted glass. | Dùng bảng nền đặc thay cho kính mờ. |
| `SET_TEXT_SIZE` | Text size | Cỡ chữ |
| `SET_TEXT_SIZE_VALUE` | {percent}% | {percent}% |
| `SET_HAPTICS` | Haptics | Rung phản hồi |
| `SET_HAPTICS_OFF` | Off | Tắt |
| `SET_HAPTICS_SUBTLE` | Subtle | Nhẹ |
| `SET_HAPTICS_FULL` | Full | Đầy đủ |
| `SET_MUSIC` | Music | Nhạc |
| `SET_MUSIC_ON` | On | Bật |
| `SET_MUSIC_AMBIENCE` | Nature sounds only | Chỉ tiếng thiên nhiên |
| `SET_MUSIC_OFF` | Off | Tắt |
| `SET_VOLUME_MUSIC` | Music volume | Âm lượng nhạc |
| `SET_VOLUME_AMBIENCE` | Nature volume | Âm lượng thiên nhiên |
| `SET_VOLUME_EFFECTS` | Effects volume | Âm lượng hiệu ứng |
| `SET_MONO` | Mono audio | Âm thanh đơn kênh |
| `SET_CAPTIONS` | Sound captions | Phụ đề âm thanh |
| `SET_LEFT_HANDED` | Left-handed | Thuận tay trái |
| `SET_LEFT_HANDED_DESC` | Mirrors the buttons for your left thumb. | Đảo vị trí các nút cho ngón cái tay trái. |
| `SET_AUTO_HIDE` | Hide buttons while I watch | Ẩn nút khi mình ngắm cảnh |
| `SET_KEEP_AWAKE` | Keep the screen on while I watch | Giữ màn hình sáng khi mình ngắm cảnh |
| `SET_LANGUAGE` | Language | Ngôn ngữ |
| `SET_LANGUAGE_DEVICE` | Same as device | Theo thiết bị |
| `LANG_EN` | English | English |
| `LANG_VI` | Tiếng Việt | Tiếng Việt |
| `SET_PRIVACY` | Mossling Meadow plays offline and collects no data. | Mossling Meadow chơi ngoại tuyến và không thu thập bất kỳ dữ liệu nào. |
| `SET_CREDITS` | Credits | Ghi công |
| `SET_CREDITS_BODY` | Made with care using Godot Engine (MIT License). Fonts: Nunito and Baloo 2 (SIL Open Font License). | Được làm bằng cả tấm lòng với Godot Engine (Giấy phép MIT). Phông chữ: Nunito và Baloo 2 (Giấy phép SIL Open Font). |
| `SET_LICENSES` | Licenses | Giấy phép |
| `SET_VERSION` | Version {version} | Phiên bản {version} |
| `LEAVE_TITLE` | Leave the hollow for now? | Tạm rời thung lũng nhé? |
| `LEAVE_DESC` | Everything keeps growing while you're away. | Mọi thứ vẫn tiếp tục lớn lên khi bạn đi vắng. |
| `LEAVE_YES` | Leave for now | Tạm rời |
| `LEAVE_NO` | Stay a while | Ở lại chút nữa |
| `A11Y_SEED` | A seed, ready to plant | Một hạt giống, sẵn sàng để trồng |
| `A11Y_BUD` | A bud, ready to open | Một nụ hoa, sắp nở |
| `A11Y_MOSSLING` | {name}, {behaviour} | {name}, {behaviour} |
| `A11Y_MAILBOX` | Mailbox | Hộp thư |
| `A11Y_STREAM` | Stream | Dòng suối |
| `A11Y_BED` | {bed} | {bed} |
| `A11Y_HOLD_TO_PET` | Touch and hold to pet | Chạm và giữ để vuốt ve |
| `CAPTION_PURR` | soft purr | tiếng gừ gừ |
| `CAPTION_CHIRP` | happy chirp | tiếng ríu rít |
| `CAPTION_SNORE` | tiny snore | tiếng ngáy khe khẽ |
| `CAPTION_CHIME` | wind chime | chuông gió leng keng |
| `CAPTION_SPLASH` | little splash | tiếng nước tõm |
| `CAPTION_BLOOM` | petals unfold | cánh hoa xòe nở |
| `CAPTION_COLLECT` | dew tinkles | sương kêu lanh canh |
| `CAPTION_PLANT` | soil pat | tiếng vỗ đất |
| `CAPTION_RAIN` | soft rain | mưa rơi tí tách |
| `CAPTION_BIRDS` | birdsong | chim hót |
| `CAPTION_BOAT` | leaf boat drifting | thuyền lá trôi |
| `CAPTION_POSTCARD` | paper rustle | giấy sột soạt |
| `SPECIES_PUFFMOSS_NAME` | Puffmoss | Rêu Bông |
| `SPECIES_PUFFMOSS_DEFAULT_NAME` | Pip | Bơ |
| `SPECIES_PUFFMOSS_DESC` | A round little sunbather. Puffmosses can nap anywhere warm, and usually do. | Một cục bông tròn mê tắm nắng. Rêu Bông ngủ được ở bất cứ chỗ nào ấm áp, và thường là ngủ thật. |
| `SPECIES_PUFFMOSS_HINT` | Loves a warm stone in the sun. | Mê những phiến đá ấm nắng. |
| `SPECIES_BUTTONBUD_NAME` | Buttonbud | Nụ Cúc |
| `SPECIES_BUTTONBUD_DEFAULT_NAME` | Dot | Chấm |
| `SPECIES_BUTTONBUD_DESC` | Curious about everything, especially petals. Follows your taps with great interest. | Tò mò với mọi thứ, nhất là những cánh hoa. Thích dõi theo từng cú chạm của bạn. |
| `SPECIES_BUTTONBUD_HINT` | Drawn to daisies and clover. | Hay ghé chỗ có cúc dại và cỏ ba lá. |
| `SPECIES_PEBBLEPAW_NAME` | Pebblepaw | Sỏi Tròn |
| `SPECIES_PEBBLEPAW_DEFAULT_NAME` | Cobble | Cuội |
| `SPECIES_PEBBLEPAW_DESC` | Patient and calm. Can watch the stream for an entire afternoon. | Kiên nhẫn và điềm tĩnh. Có thể ngắm suối suốt cả buổi chiều. |
| `SPECIES_PEBBLEPAW_HINT` | Fond of smooth stones and running water. | Thích sỏi nhẵn và nước chảy. |
| `SPECIES_HONEYHUM_NAME` | Honeyhum | Mật Ngọt |
| `SPECIES_HONEYHUM_DEFAULT_NAME` | Bumble | Vo Ve |
| `SPECIES_HONEYHUM_DESC` | Hums while working, and is always working. Sips dew from flower to flower. | Vừa làm vừa ngân nga, mà lúc nào cũng đang làm. Nhấm nháp sương từ hoa này sang hoa khác. |
| `SPECIES_HONEYHUM_HINT` | Comes when a few buttercups bloom. | Sẽ ghé khi vài bông mao lương vàng nở. |
| `SPECIES_FERNWHISK_NAME` | Fernwhisk | Lá Xoăn |
| `SPECIES_FERNWHISK_DEFAULT_NAME` | Wisp | Xíu |
| `SPECIES_FERNWHISK_DESC` | Shy, gentle and very soft. Peeks out from the ferns before saying hello. | Nhút nhát, hiền lành và mềm mại. Hay nấp sau đám dương xỉ rồi mới ló ra chào. |
| `SPECIES_FERNWHISK_HINT` | Comes when forget-me-nots bloom. Likes shady afternoons. | Sẽ ghé khi hoa lưu ly nở. Thích những buổi chiều râm mát. |
| `SPECIES_DANDELFLUFF_NAME` | Dandelfluff | Bông Gió |
| `SPECIES_DANDELFLUFF_DEFAULT_NAME` | Drift | Mây |
| `SPECIES_DANDELFLUFF_DESC` | Light as a seed and twice as dreamy. Drifts wherever the breeze goes. | Nhẹ như hạt bồ công anh, lại mơ màng gấp đôi. Gió thổi đến đâu là bay theo đến đó. |
| `SPECIES_DANDELFLUFF_HINT` | Comes when dandelions bloom. Loves a breezy day. | Sẽ ghé khi bồ công anh nở. Rất thích những ngày có gió. |
| `SPECIES_BELLKIN_NAME` | Bellkin | Chuông Nhỏ |
| `SPECIES_BELLKIN_DEFAULT_NAME` | Lilt | Leng Keng |
| `SPECIES_BELLKIN_DESC` | Musical down to the ears. Sways to any sound and hums along to wind chimes. | Yêu âm nhạc đến từng chiếc tai. Nghe tiếng gì cũng đung đưa, nghe chuông gió là ngân nga theo. |
| `SPECIES_BELLKIN_HINT` | Comes when bluebells bloom. Adores wind chimes. | Sẽ ghé khi hoa chuông xanh nở. Mê tiếng chuông gió. |
| `SPECIES_PRIMPIP_NAME` | Primpip | Má Hồng |
| `SPECIES_PRIMPIP_DEFAULT_NAME` | Tansy | Mận |
| `SPECIES_PRIMPIP_DESC` | Tidy and polite. Blushes when petted and lines up pebbles in neat little rows. | Gọn gàng và lễ phép. Được vuốt ve là đỏ mặt, hay xếp sỏi thành từng hàng ngay ngắn. |
| `SPECIES_PRIMPIP_HINT` | Comes when primroses bloom. Likes a neat pebble cairn. | Sẽ ghé khi hoa anh thảo nở. Thích tháp sỏi gọn gàng. |
| `SPECIES_CAPLING_NAME` | Capling | Nấm Lùn |
| `SPECIES_CAPLING_DEFAULT_NAME` | Nib | Tí |
| `SPECIES_CAPLING_DESC` | Bouncy, bubbly and fond of puddles. Hops from toadstool to toadstool. | Nhún nhảy, hớn hở và mê vũng nước. Nhảy từ chiếc nấm này sang chiếc nấm khác. |
| `SPECIES_CAPLING_HINT` | Visits a ring of toadstool seats. Rainy days are even better. | Ghé chơi khi có cả vòng ghế nấm. Ngày mưa lại càng thích. |
| `SPECIES_PUDDLEWUMP_NAME` | Puddlewump | Bì Bõm |
| `SPECIES_PUDDLEWUMP_DEFAULT_NAME` | Puddle | Bọt |
| `SPECIES_PUDDLEWUMP_DESC` | Happiest when it rains. Splashes in the shallows and sits on stream stones. | Vui nhất là khi trời mưa. Lội bì bõm chỗ nước nông và ngồi trên đá suối. |
| `SPECIES_PUDDLEWUMP_HINT` | Visits when the stream has plenty of stones. Loves the rain. | Ghé chơi khi suối có nhiều đá. Rất mê mưa. |
| `SPECIES_GLOWMOTE_NAME` | Glowmote | Đốm Sáng |
| `SPECIES_GLOWMOTE_DEFAULT_NAME` | Lumen | Đóm |
| `SPECIES_GLOWMOTE_DESC` | Quiet and thoughtful. Its antenna glows softly as the evening settles in. | Lặng lẽ và hay suy tư. Chiếc râu nhỏ phát sáng dịu dàng khi chiều buông. |
| `SPECIES_GLOWMOTE_HINT` | Appears at dusk and at night, near firefly lanterns. | Xuất hiện lúc chạng vạng và về đêm, gần những chiếc đèn đom đóm. |
| `SPECIES_MOONPUFF_NAME` | Moonpuff | Bông Trăng |
| `SPECIES_MOONPUFF_DEFAULT_NAME` | Luna | Hằng |
| `SPECIES_MOONPUFF_DESC` | Arrives with the moon and naps on the moon rock until dawn. Very hard to wake, very easy to love. | Đến cùng ánh trăng và ngủ trên tảng đá trăng cho tới sáng. Rất khó đánh thức, nhưng rất dễ thương. |
| `SPECIES_MOONPUFF_HINT` | Visits on quiet nights when moonblooms open and wind chimes ring. | Ghé vào những đêm yên tĩnh, khi hoa quỳnh nở và chuông gió ngân vang. |
| `FLOWER_SWEET_CLOVER_NAME` | Sweet Clover | Cỏ ba lá |
| `FLOWER_SWEET_CLOVER_DESC` | Soft pink puffs that grow quickly. Sleepy mosslings adore them. | Những bông tròn hồng mềm, lớn rất nhanh. Các bé rêu buồn ngủ mê lắm. |
| `FLOWER_BUTTON_DAISY_NAME` | Button Daisy | Cúc dại |
| `FLOWER_BUTTON_DAISY_DESC` | Cheerful white petals around a sunny middle. | Cánh trắng tươi tắn quanh nhụy vàng như nắng. |
| `FLOWER_BUTTERCUP_NAME` | Buttercup | Mao lương vàng |
| `FLOWER_BUTTERCUP_DESC` | Little golden cups that catch the morning dew. | Những chiếc chén vàng nhỏ xíu hứng sương sớm. |
| `FLOWER_FORGET_ME_NOT_NAME` | Forget-me-not | Lưu ly |
| `FLOWER_FORGET_ME_NOT_DESC` | Tiny sky-blue flowers that grow in friendly clusters. | Những bông hoa xanh màu trời bé xíu, mọc thành từng chùm thân thiện. |
| `FLOWER_BLUEBELL_NAME` | Bluebell | Chuông xanh |
| `FLOWER_BLUEBELL_DESC` | Nodding bells that seem to ring when nobody is listening. | Những chiếc chuông khẽ gật gù, như đang ngân lên khi chẳng ai để ý. |
| `FLOWER_PRIMROSE_NAME` | Primrose | Anh thảo |
| `FLOWER_PRIMROSE_DESC` | Pale yellow and gentle. The first to wake up in spring. | Vàng nhạt và dịu dàng. Loài hoa thức dậy đầu tiên của mùa xuân. |
| `FLOWER_DANDELION_NAME` | Dandelion | Bồ công anh |
| `FLOWER_DANDELION_DESC` | Sunny flowers that turn into wishes. The breeze carries the seeds around the hollow. | Hoa vàng như nắng rồi hóa thành những điều ước. Gió mang hạt bay khắp thung lũng. |
| `FLOWER_MOONBLOOM_NAME` | Moonbloom | Hoa quỳnh |
| `FLOWER_MOONBLOOM_DESC` | Sleeps all day and opens at dusk, glowing faintly under the stars. | Ngủ suốt ngày, đến chạng vạng mới nở, tỏa sáng mờ mờ dưới ánh sao. |
| `DECOR_LEAF_PINWHEEL_NAME` | Leaf Pinwheel | Chong chóng lá |
| `DECOR_LEAF_PINWHEEL_DESC` | Spins happily whenever the wind passes by. | Quay tít mỗi khi có gió ghé qua. |
| `DECOR_PEBBLE_CAIRN_NAME` | Pebble Cairn | Tháp sỏi |
| `DECOR_PEBBLE_CAIRN_DESC` | A balanced stack of smooth pebbles. Each one makes it a little taller. | Một chồng sỏi tròn xếp cân bằng. Thêm viên nào là cao thêm một chút. |
| `DECOR_TOADSTOOL_SEAT_NAME` | Toadstool Seat | Ghế nấm |
| `DECOR_TOADSTOOL_SEAT_DESC` | A perfect place to sit, hop, or shelter from the rain. Ten make a fairy ring. | Chỗ tuyệt vời để ngồi, để nhảy, hay để trú mưa. Đủ mười chiếc là thành một vòng nấm thần tiên. |
| `DECOR_STREAM_STONES_NAME` | Stream Stones | Đá suối |
| `DECOR_STREAM_STONES_DESC` | Smooth stones that make the water sing a little louder. | Những viên đá nhẵn khiến dòng nước hát to hơn một chút. |
| `DECOR_FIREFLY_LANTERN_NAME` | Firefly Lantern | Đèn đom đóm |
| `DECOR_FIREFLY_LANTERN_DESC` | Glows warmly from golden hour until morning. Fireflies love to visit. | Tỏa ánh sáng ấm từ lúc nắng chiều cho tới sáng. Đom đóm rất thích ghé chơi. |
| `DECOR_WIND_CHIME_NAME` | Shell Wind Chime | Chuông gió vỏ ốc |
| `DECOR_WIND_CHIME_DESC` | Every shell adds a new note to the breeze. | Mỗi vỏ ốc lại thêm một nốt nhạc mới vào làn gió. |
| `POSTCARD_FRIEND_01` | I found the warmest spot in the whole hollow, and it's right next to you. Thank you for the sunshine. | Mình tìm được chỗ ấm nhất cả thung lũng rồi, ngay cạnh bạn đó. Cảm ơn bạn vì những tia nắng nhé. |
| `POSTCARD_FRIEND_02` | Did you see the petals open this morning? I counted every one. Twice! I think the garden likes you. | Sáng nay bạn có thấy cánh hoa nở không? Mình đếm từng cánh luôn. Đếm hai lần! Chắc khu vườn quý bạn lắm. |
| `POSTCARD_FRIEND_03` | The stream told me a story today. It was mostly about pebbles. I listened all afternoon and thought of you. | Hôm nay con suối kể mình nghe một câu chuyện. Chủ yếu là về mấy viên sỏi thôi. Mình nghe suốt buổi chiều và nghĩ đến bạn. |
| `POSTCARD_FRIEND_04` | Busy, busy, happy! Every flower here tastes like a sunny morning. I saved you the sweetest drop. | Bận ơi là bận, mà vui ơi là vui! Bông hoa nào ở đây cũng ngọt như buổi sáng đầy nắng. Mình để dành cho bạn giọt sương ngọt nhất. |
| `POSTCARD_FRIEND_05` | I'm not very good at saying hello. But I like it here. I like it a lot. | Mình không giỏi chào hỏi lắm. Nhưng mình thích ở đây. Thích nhiều lắm. |
| `POSTCARD_FRIEND_06` | The wind and I went all the way up the hill and back. From up there, your garden looks like a patchwork quilt. | Mình với cơn gió đã lên tận đỉnh đồi rồi quay về. Từ trên đó nhìn xuống, khu vườn của bạn trông như một tấm chăn chắp vá. |
| `POSTCARD_FRIEND_07` | I dreamed the whole hollow was a soft, round pillow. Then I woke up, and it was true. | Mình mơ thấy cả thung lũng là một chiếc gối tròn êm ái. Tỉnh dậy thì thấy đúng là vậy thật. |
| `POSTCARD_FRIEND_08` | I hopped three times around the garden today. That's how happy I am. You can hop too, if you like. | Hôm nay mình nhảy ba vòng quanh vườn. Mình vui đến thế đó. Bạn cũng nhảy thử nhé, nếu thích. |
| `POSTCARD_FRIEND_09` | Whenever you'd like a quiet place, the stream and I will keep a spot for you. | Bất cứ khi nào bạn muốn tìm một chỗ yên tĩnh, mình và con suối sẽ giữ cho bạn một chỗ ngồi. |
| `POSTCARD_FRIEND_10` | I made up a little song about your garden. It goes hmm, hmm-hmm, hmmm. It sounds even better with chimes. | Mình nghĩ ra một bài hát nho nhỏ về khu vườn của bạn. Nó như thế này: ư ư, ư-ư, ưưư. Có tiếng chuông gió thì còn hay hơn nữa. |
| `POSTCARD_FRIEND_11` | I tidied the moss by the old stump and left a pebble there for you. It's the roundest one I could find. | Mình đã chải lại lớp rêu cạnh gốc cây cũ và để ở đó một viên sỏi cho bạn. Viên tròn nhất mà mình tìm được đấy. |
| `POSTCARD_FRIEND_12` | When the lanterns glow, I like to sit very still and watch the sky. Thank you for the warm little lights. | Khi những chiếc đèn sáng lên, mình thích ngồi thật yên và ngắm bầu trời. Cảm ơn bạn vì những ánh đèn nhỏ ấm áp. |
| `POSTCARD_EVENT_WELCOME` | Welcome to the hollow. Stay as long as you like. Everything here grows at its own pace, and so can you. | Chào mừng bạn đến thung lũng nhỏ. Cứ ở lại bao lâu tùy thích nhé. Mọi thứ ở đây đều lớn lên theo nhịp riêng của mình, và bạn cũng vậy. |
| `POSTCARD_EVENT_FIRST_BLOOM` | A flower you planted opened today. Somebody small noticed, and did a happy wiggle. | Hôm nay bông hoa bạn trồng đã nở. Có một bạn nhỏ trông thấy và lắc lư vui sướng. |
| `POSTCARD_EVENT_FIRST_DECOR` | The hollow feels a little more like home now. The mosslings keep stopping to admire it. | Thung lũng giờ thấy giống nhà hơn một chút rồi. Các bé rêu cứ dừng lại ngắm mãi. |
| `POSTCARD_EVENT_FIRST_RAIN` | It rained softly today. Everyone shared the big leaves, and nobody minded getting a little damp. | Hôm nay trời mưa phùn nhè nhẹ. Mọi người cùng trú dưới những chiếc lá to, chẳng ai ngại bị ướt một chút. |
| `POSTCARD_EVENT_FIRST_NIGHT` | Someone visited while the stars were out. They left a tiny footprint in the moss, curved like a crescent moon. | Có ai đó ghé chơi lúc trời đầy sao. Bạn ấy để lại một dấu chân bé xíu trên lớp rêu, cong cong như vầng trăng khuyết. |
| `POSTCARD_EVENT_BRIMMING` | The basket is brimming with gifts! From now on, when it is full, friends will leave photos for you. | Giỏ đã đầy ắp quà rồi! Từ giờ, mỗi khi giỏ đầy, các bạn sẽ để lại ảnh tặng bạn. |
| `POSTCARD_EVENT_TEN_BOATS` | Ten little leaf boats have sailed down the stream. Somewhere far away, a duck is very puzzled and very pleased. | Đã có mười chiếc thuyền lá xuôi dòng suối. Ở đâu đó thật xa, có một chú vịt vừa ngơ ngác vừa thích thú lắm. |
| `POSTCARD_EVENT_ALBUM_COMPLETE` | Every mossling of spring has visited your hollow. They all agree: it's the coziest place they know. | Tất cả các bé rêu mùa xuân đều đã ghé thăm thung lũng của bạn. Bạn nào cũng đồng ý: đây là nơi ấm cúng nhất mà các bạn từng biết. |
