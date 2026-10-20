# 04 — The Science & Craft of Cozy, Idle, Relaxing Games

**Role:** Game Design & Player Psychology Researcher · **Date:** 2026-10-20 · **Status:** v1.1, adversarially fact-checked 2026-10-20 (see "Verification log")
**Evidence tags:** **[F]** fact checked against a cited source · **[H]** well-supported heuristic · **[J]** our judgement · **†** store/press figure not re-verified by the fact-checker.
**Method note:** WebFetch could not reach any host from this container (DNS failure, re-confirmed during fact-check), so sources were checked through search-indexed abstracts, publisher records and repository pages. We did not read full texts. Figures that come from press coverage and not the paper are labeled. The fact-check's shared web-search budget ran out part-way, so some items are marked "not re-verified" in the log. Items still unconfirmed are listed in §8.

---

## 0. Decision summary

- **Recommended concept: B — "Mossling Meadow".** It is a fuzzy-creature garden in a sunlit hollow. Round, furry critters visit, nap and leave gifts while you are away. It scored **92/100** against A (pond) 83 and C (rainy terrarium) 86, and it stays first when the art-feasibility weight is doubled (§6.4).
- **Borrow from the runners-up:** A's rippling stream and C's L-system flora and rain weather become B's ambient layers.
- **Economy:** "breadth, not height". Numbers stay bounded (nothing displayed above 99,999) and there is one spendable currency. Progress comes from new *content* (species, flora, seasons). Prestige becomes **Seasons**, a soft renewal that never takes anything away.
- **Ethics:** no fail states, decay, streaks, FOMO, loot boxes, pay-to-skip or interstitial ads. Notifications are opt-in only (and need a native plugin, so v1 ships without them, see P15). Monetization: **a free trial plus one one-time unlock**, the model *A Little to the Left* is reported to use on mobile†.

---

## 1. Design Principles checklist (all must pass the TEAM.md "Emotion" gate)

| # | Rule | Pass/fail test | Basis |
|---|---|---|---|
| P1 | **No fail state.** Nothing dies, withers, leaves forever or goes negative. | Headless test: 30 simulated days away → every entity and currency is ≥ its value at save. No decay branch in the sim code. | [1]; Viridi (§4.5) |
| P2 | **No punitive timers.** No countdown ends in a loss. A timer may only mean "something nice is ready". | UI audit of every timer label. | PH17 "safety" [1]. [12] is consistent with this but did **not** test timed vs untimed play (§2.4) |
| P3 | **Return without guilt.** After any absence the world looks as good or better: no weeds, mess or sad NPCs. | No "neglect" assets exist. Screenshot diff after a 30-day sim. | [1][45] |
| P4 | **Player-paced.** Ignoring any prompt costs nothing. A 30 s session still makes visible progress. | Scripted 30 s session → progress visible on next launch. | [35][37] |
| P5 | **Soft fascination always on.** The idle screen has ≥3 independent ambient motion layers (wind, light or water, creatures), none on a loop shorter than 20 s that a viewer could notice. | 60 s capture: count moving layers; frame-diff autocorrelation shows no period < 20 s. | [16][17][20][22] |
| P6 | **Low-arousal colour.** ≥85% of screen area has HSV S ≤ 0.45 and V ≥ 0.45. Saturated accents cover ≤10%. No alarm-red UI. | numpy/ImageMagick histogram on 1080×2400 screenshots. | Arousal = −.31·B + .60·S [30] |
| P7 | **Curves over corners.** UI corner radius ≥ 8 dp. No spikes on friendly entities. | SVG lint: no interior angle < 60° on UI or creature layers. | [29] |
| P8 | **Mid-range fractal scenery.** Treeline, grass and cloud silhouettes measure box-counting D ≈ 1.3–1.5. | Box-counting script on edge-detected screenshots. | [24][25][27] |
| P9 | **Calm motion.** No screen shake. ≤3 flashes in any 1 s. Ambient periods 3–8 s, mixed by irrational (golden-ratio) ratios so they never re-sync. Sleeping-creature "breath" period 4–6 s. | Motion-token review and capture analysis. | [46]. [J] 4–6 s = 10–15 breaths/min (0.17–0.25 Hz), the slow end of normal adult resting rate (~12–20/min) [H]. That is still faster than the ~0.1 Hz (≈10 s, 6/min) HRV-resonance breathing in [36], so we claim no entrainment effect. |
| P10 | **Abundance.** Every session starts with ≥1 affordable, meaningful action. | Economy sim over 10k random session schedules → 0 sessions with nothing affordable. | [1] |
| P11 | **Small numbers.** Displayed values ≤ 99,999. No scientific notation. One spendable currency plus one non-spendable affection meter. | Economy-sim maximum; UI string audit. | [J]; score-pull in Dorfromantik (§4.5) |
| P12 | **Immediate, soft feedback.** Every tap answers within ≤100 ms with matched visual, audio and haptic feedback. No negative-feedback sounds. | On-device latency test; SFX audit. | Competence [37]; 0.1 s "feels instantaneous" limit [49] [H] |
| P13 | **Relatedness without competition.** Creatures are named and remember the player. Affection never decays. No leaderboards. | Feature audit. | [9][37] |
| P14 | **No streaks or FOMO.** No consecutive-day counters. No limited-time exclusives: seasonal content recurs every cycle. The return gift grows with absence, up to a bound. | Feature and copy audit. | [42][45] |
| P15 | **Ethical monetization and notifications.** No loot boxes, consumable premium currency, pay-to-skip, or forced/interstitial ads. Notifications are opt-in, ≤1/day, never loss-framed, silent 21:00–09:00. Godot 4.7.2 has no API for scheduling local notifications. It only offers `OS.request_permission("android.permission.POST_NOTIFICATIONS")` and the Android export option `permissions/post_notifications`. Notifications would therefore need a native Android/iOS plugin, which the TEAM.md pure-GDScript rule excludes [F, 47]. So **v1 ships with none** [J]. | Store-build audit and notification copy review. | [1][5][43][44] |

---

## 2. Defining coziness

### 2.1 Project Horseshoe 2017 [1]
"Coziness in Games: An Exploration of Safety, Softness and Satisfied Needs". The participants were Jake Forbes, Daniel Cook, Chelsea Howe, Squirrel Eiserloh, Dan Hurd, Anthony Ordon, Joshua Diaz and Tanya X. Short (editor), with Ron Meiners moderating [F, via secondary reproductions on Lost Garden and Game Developer].
- Coziness is **an aesthetic goal, not a genre**: "a flavor that can be applied to any underlying type of game".
- **Safety:** there is no impending loss or threat. Activities are voluntary and opt-in, so the player never feels coerced.
- **Abundance:** lower Maslow needs are met. "Nothing is lacking, pressing or imminent."
- **Softness:** gentle stimuli. The levers are warm, gentle palettes, low ambient light, natural materials (wood, stone, water), enclosed spaces and hand-crafted objects.
- The pillars reinforce each other and bring **intimacy, slow pace and sincerity** with them.
- **Threat as contrast** works only *outside* the cozy space (rain beyond the window).
- **Notifications:** the report criticises reward promises, lost-opportunity threats and marketing spin. It argues "consensual notifications" are possible.

### 2.2 Waszkiewicz & Bakun 2020 [2]
The paper exists (*J. Gaming & Virtual Worlds* 12(3), an issue that actually came out in Feb 2021) and is widely cited for adapting "cozy" from industry usage to an aesthetic category [F]. **FLAGGED:** the fact-check found no source that confirms the specific three-mode typology below or the "tending, befriending, storytelling" practices. Treat both as an unverified paraphrase and do not cite them externally.
- **coherent**: the whole game is cozy;
- **dissonant**: cozy form around uncomfortable themes;
- **situational**: cozy pockets inside stressful games.

→ Whatever the source says, our own design choice stands: *coherent* coziness, with tending and befriending as core verbs [J].

### 2.3 Academic work 2021–2026
- **Krzywinska et al. 2025** [3]: coziness ("second homes") has formal and engagement functions across many genres [F].
- **Daneels & Maes 2025** [4]: survey of N = 277 cozy players. Five motives: moral self-reflection, **agency**, **escapism**, **eudaimonic emotions** (being moved or warmed), and interest in the narrative. Players also scored higher on "Light Triad" traits [F].
- **Critiques to design against:**
  - Buergi 2024 [5]: idle games can be cozy, but **selling ways around waiting** exploits impatience [F].
  - Andiloro [6]: cozy games often re-stage productivity and accumulation [F].
  - *Wanderstop* (2025) dramatises burnout.

  → Relaxation must not become a chore list (P4, P11).

### 2.4 Wellbeing evidence
| Study | Finding | Implication |
|---|---|---|
| Johannes, Vuorre & Przybylski 2021 [7] | Telemetry from Nintendo and EA (~2,756 ACNH players plus a smaller PvZ sample): play time had a **small positive** correlation with affective wellbeing. Need satisfaction related to wellbeing **independently** of time [F]. | Design for need satisfaction, not time-on-app. |
| Vuorre et al. 2022 [8] | 38,935 players of 7 games from 7 publishers, 6 weeks of telemetry and 3 survey waves: little to no evidence of a causal effect of play time. Intrinsic motivation tracked wellbeing positively, extrinsic negatively [F, abstract]. | Extrinsic hooks (streaks, FOMO) are not neutral. |
| Yee & Sng 2022 [9] | Interviews: ACNH met autonomy, competence and relatedness in lockdown. Players **quit when needs were thwarted** [F]. | Use SDT. Treat lapse and return as normal. |
| Zhu 2021 [10] | ACNH as escape and as virtual social contact [F, abstract]. | Safety and escapism are valid goals. |
| Barr & Copeland-Stewart 2022 [11] | N = 781 survey: 71% played more. 58% reported a wellbeing impact, mostly positive (less stress and anxiety). Self-report [F]. | Weak causal support. |
| Russoniello et al. 2009 [12] | Three PopCap games (Bejeweled 2, Peggle, Bookworm Adventures) vs a web-browsing control. Only Bejeweled 2 lowered HRV-indexed physiological stress; press coverage says it was played in an *untimed* mode. All three games improved mood. **Timed vs untimed was never compared.** PopCap-funded [F, press/abstract]. | Consistent with avoiding timers (P2), but **not evidence that timers cause stress**. P2 rests on PH17 [1] plus [J]. |
| Desai et al. 2021 [13] | 20 min of *Flower* (a wind/nature game) vs a 20 min mindfulness body scan, N = 80 undergraduates. Both reduced stress, with similar physiological reductions. Mindfulness did slightly better on self-report [F, abstract]. | Nature-themed, low-demand play restores. |
| Reinecke 2009 [14] | Games are used systematically for recovery after strain [F]. | Position the game as recovery. |
| Heinze, Mandryk & Klarkowski 2024 [15] | N = 60, stress induction, then a roguelike with combat required, optional or absent. All variants supported detachment and control. Action mechanics helped restore **mastery** but **undermined relaxation**: arousal and subjective stress were higher [F, abstract]. | Keep **optional, failure-free mastery** (combo discovery). Add no action or combat verbs. |

---

## 3. Relaxation & restoration science → design rules

### 3.1 Attention Restoration Theory and Stress Reduction Theory
- **Kaplan 1995** [16]: directed attention fatigues. Restorative settings offer **being away, extent, soft fascination and compatibility** [F].
- **Berman et al. 2008** [17]: even *pictures* of nature improved directed attention [F].
- **Effect size:** Stevenson et al. 2018 [18] meta-analysed 42 studies. Working memory, cognitive flexibility and (less reliably) attentional control improve with **low–moderate effects**. Real exposure beats virtual, possibly because real exposures last longer [F]. Ohly et al. 2016 [19] note that "soft fascination" is under-operationalised [F].
  - → Use nature content, but make **no therapeutic claims** in marketing [J].
- **Ulrich et al. 1991** [20]: N = 120 stressed participants recovered faster and more fully, physiologically and in self-report, watching nature video than urban video [F].
- **2026 multisite replication** [21]: N = 959 across 10 labs. Psychological recovery was greater after nature videos, which only *partly* confirms the original. Physiologically, only the parasympathetic effects replicated [F, abstract]. The two nature videos also differed from each other, which the authors tentatively attribute to the **loud noise of fast-streaming water** in one of them.
  - → Our stream audio must be a gentle trickle, quiet in the mix, never a rushing torrent [J].
- **Virtual nature:**
  - Spano et al. 2023 [22] (59 studies): a generally positive effect on mood, stress and restoration [F].
  - Li et al. 2023 [23] (meta-analysis): **medium immersion** gave the largest positive affect. Risk of bias was moderate to high [F].
  - → A phone screen with matched audio is enough. Do not chase VR-level immersion [H].

### 3.2 Fractals, biophilia, shape, colour, cuteness
- **Fractals:**
  - Spehar et al. 2003 [24]: preference peaks at **D = 1.3–1.5** across natural, mathematical and Pollock images [F].
  - Hägerhäll et al. 2004 [25]: the D of a landscape silhouette predicts preference [F].
  - Taylor 2006/2021 [26][27]: "fractal fluency" and preliminary stress data. The "60% better recovery" figure is press-only [H].
  - → **P8.**
- **Biophilic patterns** [28]: non-rhythmic sensory stimuli, dynamic and diffuse light, presence of water, complexity and order, prospect, refuge [F]. → The scene contains water, moving light, non-rhythmic motion, and **refuge with prospect**: an enclosed hollow under an open sky, matching PH17's "enclosed spaces" [H].
- **Curvature:** Bar & Neta 2006 [29]. Curved objects are preferred at 84 ms exposure. Sharp contours may signal threat [F]. → **P7.**
- **Colour:** Valdez & Mehrabian 1994 [30]:
  - Pleasure = .69·B + .22·S
  - Arousal = −.31·B + .60·S

  These are regressions on *standardized* Munsell brightness and saturation (chroma), so HSV S and V are only a proxy and P6's thresholds are [J] [F for the equations]. Blue, blue-green and green rank among the most pleasant hues [F]. Our recollection of the abstract, not re-fetched: yellow and green-yellow were least pleasant, and green-yellow among the most arousing. → **High value, low-to-moderate saturation (P6).** Keep meadow greens away from saturated chartreuse [J].
- **Cuteness:** Glocker et al. 2009 [31]. N = 122 adults rated photos of infants edited for more or less baby schema: rounder face, higher forehead, larger eyes, smaller nose and mouth. High-schema faces raised cuteness and **caretaking motivation** [F]. Nittono et al. 2012 [32]: cute images led to more careful behaviour and narrower focus [F].
  - → Creature rig: head-to-body ratio ≥ 1:1.5, eyes on the lower half of the face, round silhouette [J].

### 3.3 Flow vs relaxation
- Csikszentmihalyi's flow is a high challenge–skill balance. In the 8-channel model [33] the channels are **arousal, flow, control, relaxation, boredom, apathy, worry, anxiety** [F].
  - Our targets are **relaxation** (high skill, low challenge) and **control**, not flow.
  - "Low-arousal flow" is **not an established construct** [J]. The operational target is *absorption without challenge*, which is close to soft fascination.
- **Affect target:** the positive-valence, low-arousal quadrant of Russell's circumplex [34]: calm, content, serene.
- **Recovery experience** (Sonnentag & Fritz 2007 [35]):
  - **detachment**: a fantasy world with no news or real-world stress;
  - **relaxation**: low-arousal audio-visuals;
  - **mastery**: optional discovery;
  - **control**: the player decides everything.

### 3.4 Self-Determination Theory
Ryan, Rigby & Przybylski 2006 [37]: autonomy and competence predicted enjoyment across four studies. In the MMO sample, autonomy, competence and relatedness **independently predicted enjoyment and future play** [F]. Tyack & Mekler 2020 [38] warn against applying SDT shallowly [F]. So each need maps to a concrete mechanic:

| Need | Mechanic (Concept B) | Banned anti-pattern |
|---|---|---|
| Autonomy | Free placement; no mandatory quests; several valid goals (album, décor, friendship). | Forced tutorial > 60 s; blocking quest chains. |
| Competence | Instant juicy feedback; visible growth; combo discovery with no way to fail. | Fail screens; star ratings; hidden "optimal" solutions. |
| Relatedness | Named creatures that greet you and remember favourite spots; postcards. | Leaderboards; guilt NPCs ("we missed you…"). |

---

## 4. Idle / incremental design

### 4.1 Sources
- **Alharthi et al. 2018** [39]: taxonomy of 66 idle games. It covers interactivity, progress rate and rewards [F].
- **Pecorella (Kongregate)** [40]:
  - GDC **2015** "Idle Games: The Mechanics and Monetization of Self-Playing Games" (not 2016).
  - GDC Europe 2016 "Quest for Progress".
  - "The Math of Idle Games" I–III on the Kongregate blog [F, from memory; GDC Vault IDs not re-verified].

### 4.2 The math
- **Pecorella's core model [F]:** `cost_next = cost_base · r^owned` and `production = production_base · owned · multipliers`. Costs are exponential; production is linear or polynomial.
  - AdVenture Capitalist Lemonade Stand: r = **1.07**, base cost 4, 1.67/s, so the 11th costs 4·1.07¹⁰ = 7.87.
  - Cookie Clicker: r = **1.15**, which doubles the price about every 5 buys [41].
- Price doubles every ln 2 / ln r buys:

| r | doubles every | r¹⁰ | r¹² |
|---|---|---|---|
| 1.07 | 10.2 buys | 1.97× | 2.25× |
| 1.10 | 7.3 | 2.59× | 3.14× |
| 1.12 | 6.1 | 3.11× | 3.90× |
| 1.15 | 5.0 | 4.05× | 5.35× |

- **Why classic idle games explode:** time-to-next-buy ≈ rⁿ/n. Designers answer with multipliers and prestige, which leads to 10³⁰⁰-scale numbers and **spreadsheet anxiety** [H].
- **Our fix, "breadth, not height" [J]:**
  - cap each item type at **10–12 copies** with r = 1.10–1.12, so the last copy costs ≤ 3.5× the first (the 12th copy costs r¹¹ = 3.48× at r = 1.12; the table's r¹² column is one copy beyond the cap) (P11);
  - long-term progress is **new content**;
  - mid-game, the next item costs ≈ **30–90 min of passive income**, so every return can buy something;
  - pacing targets for B:
    - first visitor in 20–40 s (scripted);
    - first ≤5 min session meets 3 species;
    - day 1 → 8 species, week 1 → ~25, month 1 → ~45;
    - full album in ~8–12 weeks at 2 × 5 min/day.

### 4.3 Offline progress
- Industry practice is to simulate time away on return. Caps of 8, 12 or 24 h are common, sometimes at a reduced (~50%) rate [H].
- **Our policy [J]:**
  - simulate at **100% rate**; leaving is never penalised;
  - gifts fill a **24-slot basket** at λ ≈ 2 visitors/h, full in ~12 h;
  - once it is full, visitors leave *photos and memories*, so there is no waste and always something to see;
  - simulate up to 7 days.
- **Godot 4.7.2 [F, 47]:**
  - Save on `NOTIFICATION_APPLICATION_PAUSED`; iOS allows only ~5 s before killing the app.
  - Also save, debounced, on `NOTIFICATION_APPLICATION_FOCUS_OUT`, which arrives *before* PAUSED on both platforms:
    - Android: `onActivityPaused` calls `GodotLib.focusout()` and only then pauses the renderer, which sends PAUSED.
    - iOS: `applicationWillResignActive` / `sceneWillResignActive` fire before `on_enter_background`.
    - On iOS it also fires for transient interruptions (notification panel, app switcher, audio interruption).
  - Save on `NOTIFICATION_WM_CLOSE_REQUEST` for desktop builds only; Node.xml says it is "Implemented on desktop platforms".
  - Resume on `NOTIFICATION_APPLICATION_RESUMED` (Android/iOS). SceneTree propagates all of these to every node.
  - Compute the delta with `Time.get_unix_time_from_system()` (UTC). The docs warn that users can change the clock, so clamp the delta to [0, 7 d] and never punish a clock change. Use `Time.get_ticks_msec()` in-session (monotonic).
- **Welcome-back recap [J]:** a 3–5 s skippable diorama, for example "While you were away, Pip napped under the bluebells."

### 4.4 Prestige → Seasons
- Classic prestige wipes progress in exchange for a permanent multiplier. Prestige currency is often ∝ √(lifetime earnings) [H, fan-documented for AdCap].
- Wiping the player's *home* violates PH17 safety [J].
- **Seasons** instead:
  - every ~14 in-game days, or when the player chooses, the palette, flora and weather turn and seasonal species visit;
  - nothing is removed, and each season recurs every cycle (P14);
  - an optional "new plot" adds a garden and never replaces the old one.

### 4.5 Case studies [48]
| Game | Core verb · session | Why cozy | Monetization | Lesson |
|---|---|---|---|---|
| **Neko Atsume** (Hit-Point 2014; sequel 2024) | Place food and toys; cats arrive **while the app is closed**; 30 s–2 min checks. | Rewards leaving; no fail; dozens of cats, some rare and item-attracted (the count changed across updates, so the earlier "49 / 17" figure is not re-verified†). | F2P. Gold-fish IAP† (pack price and size not re-verified), not required to see every cat. | TAKE: combo-attraction collection. |
| **Usagi Shima** (Jess Yu 2023, **Godot**) | Decorate an island, collect bunnies. | No win or lose. | F2P + IAP. The developer calls AdMob, Billing, iCloud and Game Center integration the hardest part†. | A solo Godot developer can ship this genre; budget time for platform integration. |
| **Cats & Soup** (HIDEA 2021) | Upgrade cat cooking stations; idle tableau. | Cats, forest, no difficulty; ~4.9★ from ~336k iOS ratings (a volatile snapshot†). | IAP + optional rewarded ads (e.g. 2× speed). | TAKE: a watchable workshop. AVOID: selling relief from waiting [5]. |
| **Viridi** (Ice Water 2015) | Water succulents in real time. | Zen pot, circling snail. | Freemium; **paid seeds can wilt**†. | AVOID: death and losing money (P1). |
| **Townscaper** (Stålberg 2020; mobile $4.99) | Tap to place blocks. | No goals; a WFC solver makes **every input beautiful**. | Premium. | TAKE: procedural beautification. |
| **A Little to the Left** (Max Inferno; mobile 2024) | Tidy; 1–3 min puzzles plus a **Daily Tidy**. | Order, several valid solutions, no timer. | **Free trial (no ads) → one-time unlock**; reported prices of $9.99 and DLC $2.99/$4.99†. | TAKE: the ethical model; dailies without a streak penalty. |
| **Alba** (ustwo 2020) | Photograph wildlife; ~3–5 h. | Nature, community. | Premium / Apple Arcade; 1 tree per download, 1M trees by Dec 2021†. | TAKE: a wildlife journal; real-world good. |
| **Kind Words** (Popcannibal 2019) | Write kind anonymous letters. | **No counters or scoreboard**; stickers only. | Premium (~$5). | TAKE: no numbers. SKIP: needs a server and moderation. |
| **Dorfromantik** (Toukana 2022) | Place hex tiles; 20–60 min runs. | Gentle growth; creative mode has no score. | Premium. | A reviewer slid into **min-maxing for score**, so hide numbers. |
| **Cozy Grove** (Spry Fox 2021) | Real-day-synced quests. | 30–60 min of new content per day, then free play. | Premium. | Gate *content*, never *rewards*. |
| **Wanderstop** (Ivy Road 2025) | Tea garden; narrative. | About burnout. | Premium. | Rest must not become a to-do list. |
| *Cautionary:* **Fishing and Life** | Idle fishing. | Calm audio-visuals. | F2P with frequent forced ads, which players say **break the relaxation** (low-reliability aggregator). | No interstitials. |

---

## 5. Ethical design

- **Dark patterns** (Zagal, Björk & Lewis 2013 [42]): design choices that harm players without informed consent. The paper covers:
  - **temporal**: grinding, *playing by appointment*;
  - **monetary**: *pay to skip*, pre-delivered content, monetized rivalries;
  - **social-capital**: social pyramid schemes, impersonation.

  [F for grinding, appointment, pay-to-skip and pyramid; the others are from the paper and not re-checked.]
  - *Nuance [J]:* Neko Atsume-style check-ins are not appointment play, because missing one costs nothing. Appointment play turns dark when absence is **punished**.
- **Predatory monetisation** [43]: 1,104 players described 35 unfair, misleading or aggressive techniques across 8 domains. Several may conflict with UK consumer law [F].
- **Loot boxes** [44]: N = 7,422. Loot-box spend tracked problem-gambling severity at η² = 0.054, against 0.004 for other spending [F]. → No gacha of any kind, including free creature gacha [J].
- **Streaks** [45]: across 7 studies, a logged streak shown as intact raises repetition and one shown as **broken lowers it**, even when past behaviour is identical. The drop is stronger when users blame themselves for the break and weaker when the streak can be "repaired" [F, abstract]. A streak therefore guarantees a guilt moment for every lapsing player.
  - → Use a **visit diary** that celebrates days played and never shows gaps.
  - → Use **welcome-back gifts** that grow with time away, up to the basket's bound.
- **Never list:**
  - loot boxes or gacha;
  - consumable premium currency;
  - pay-to-skip or speed-up, through IAP or rewarded ads;
  - interstitial or forced ads;
  - streaks;
  - limited-time exclusives;
  - decay, withering or weeds;
  - leaderboards;
  - guilt-copy notifications ("X misses you");
  - accounts or online requirements.
- **Monetization recommendation [J; the Director decides]:**
  - free trial covering Spring plus ~15 species;
  - one non-consumable unlock (~$4.99–6.99) priced in local currency;
  - optional cosmetic supporter packs with no gameplay effect;
  - no ads.

---

## 6. Three candidate concepts

### 6.1 Concept A — "Lantern Pond"
| Field | Spec |
|---|---|
| Fantasy | Keeping a lily pond behind a forest-edge tea house, from dusk to dawn. |
| Core loop | **s:** tap the water → ripple, and koi drift over (2–4 s). **min:** a 2–4 min check-in to collect visitors' petals and place a stone, reed or lantern. **days:** pond composition attracts frogs, dragonflies, turtles and resting herons; lotus blooms on a 24 h cycle. |
| Idle mechanic | A habitat score sets Poisson visitor arrivals. Petals and sketches go into a capped basket. |
| Collection / meta | Journal of ~50 species. Noise-generated koi patterns make every fish unique and nameable. |
| Idle view | Koi boids, caustics, rain ripples, fireflies, lanterns, reflected sky gradient. |
| Emotion | Serenity, contemplation. |
| Art hook | 256² ripple heightfield in a SubViewport, normal-mapped water, SVG koi with procedural spine wiggle, GPUParticles2D fireflies. |
| Risks | Premium water on the Compatibility renderer is the hardest shader to get right. Fish are not "fuzzy". Koi apps are saturated. The scene can read as a screensaver. |

### 6.2 Concept B — "Mossling Meadow" (recommended)
| Field | Spec |
|---|---|
| Fantasy | A sun-dappled hollow where round, fuzzy *mosslings* nap, nibble and play in the garden you grow. |
| Core loop | **s:** tap-hold to pet (squash-stretch, purr chime, light haptic); tap a bud and it unfurls in ~600 ms. **min:** a 1–5 min check-in to empty the dew basket, plant 1–2 flowers or place a décor piece, and read a postcard. **days:** specific flower and décor combos attract new species (Neko Atsume logic); flowers grow in stages at 10 min, 1 h and 4 h; weather changes and Seasons turn. |
| Idle mechanic | A "snugness" score sets Poisson visits. Visitors nap and leave dew in a 24-slot basket, then photos once it is full. Growth is real-time and nothing decays. |
| Collection / meta | **Mossling Album**: ~48 species × procedural colour and pattern variants. Each individual has a name, a favourite spot, and affection hearts that never decay. Seasons (§4.4). |
| Idle view | Gusting wind-sway on grass and flowers, drifting pollen and dandelion seeds, crossing cloud shadows, light shafts, sleeping mosslings breathing (4–6 s), butterflies, a rippling stream (from A), day–night on the device clock. |
| Emotion | Tenderness and "warm fuzzies": positive valence, low arousal, a care response [31][32]. |
| Art hook | Literal fuzz: SVG shapes plus a canvas_item shader with a noise-displaced alpha rim, soft inner gradient, rim light and grain. One **parametric creature rig** (body ellipse plus swappable ears, antennae, tails and patterns) gives combinatorial variety. Spring squash-stretch. |
| Risks | A crowded niche (Neko Atsume, Usagi Shima, Cats & Soup). A cheap-looking fur shader would sink the game, so prototype it first and QA against the rubric. Content volume is handled by the parametric rig. |

### 6.3 Concept C — "Drizzle & Fern"
| Field | Spec |
|---|---|
| Fantasy | A rainy windowsill. You grow a glass terrarium of moss, ferns and mushrooms while a sleepy cat watches the rain. |
| Core loop | **s:** mist plants (droplets, leaves perk up). **min:** trim, re-pot and arrange 1–3 plants. **days:** plants grow by real-time L-system iterations; cross-pollinating produces new genomes. |
| Idle mechanic | Real-time growth. Plants never need water; misting only speeds growth and adds shine. Snails and ladybugs visit. A time-lapse replays on return. |
| Collection / meta | Herbarium of procedurally generated species (genome = L-system parameters plus palette); collectible jars. |
| Idle view | Rain-on-glass refraction, plants swaying and growing, condensation, bokeh city lights, the cat's breathing. |
| Emotion | Hygge, refuge with prospect, quiet nurturing. |
| Art hook | L-system and space-colonisation plants as Line2D/Polygon2D with SVG leaf stamps (very code-friendly), plus a rain-glass shader. |
| Risks | Subtle growth gives a weak return hook. Few characters to love. Comparison with Viridi. Static segments must be baked to textures. |

### 6.4 Scoring (1–5; weights sum to 100) [J]
| Criterion (weight) | A | B | C |
|---|---|---|---|
| (a) Zero stress / no fail (15) | 5 | 5 | 5 |
| (b) Idle progress, satisfying to watch (12) | 4 | 5 | 4 |
| (c) One-thumb portrait (8) | 5 | 5 | 5 |
| (d) Premium quality from code-only art (18) | 4 | 4 | 5 |
| (e) Soft-fascination ambience (12) | 5 | 4 (5 with stream) | 5 |
| (f) Warmth and relatedness, SDT (12) | 3 | 5 | 3 |
| (g) Legible, FOMO-free return hook (10) | 4 | 5 | 3 |
| (h) Content scalability (8) | 4 | 5 | 4 |
| (i) Differentiation (5) | 2 | 3 | 4 |
| **Weighted /100** | **82.6** | **92.0** | **86.2** |

Doubling the weight of (d) (total weight 118) still ranks B first: B 4.51, C 4.42, A 4.11 on the 5-point scale (re-computed in the fact-check). **Recommend B**, with A's stream and C's flora and rain as ambient layers.

---

## 7. Validation plan
1. **Automated:** P1, P3, P6, P8, P10 and P11 run as headless tests and screenshot scripts in `tests/` and `qa/`.
2. **Internal panel:** after 5 min of idle-watching, rate on an affect grid [34]. Target: valence ≥ +2 and arousal ≤ −1 on a ±4 scale [J].
3. **Copy audit:** check every string against P14 and P15. Ban urgency words such as "hurry", "last chance" and "expires".

## 8. Open items (updated after fact-check)
- [1]: verbatim quotes were seen only in search excerpts, and the fact-check found projecthorseshoe.com unreachable too (DNS). Participants are confirmed via secondary sources.
- [2]: the three-mode typology and the "tending/befriending/storytelling" practices are **unconfirmed** (§2.2).
- DOIs are still unverified for [2], [6] and [11]. The DOI for [4] was malformed and has been replaced by the article URL.
- The Terrapin "~20 s every 20 min" timing is unverified, so it is not used in the rules.
- [7]: the PvZ N differs between the preprint (471) and secondary reports. Not re-checked because the search budget ran out.
- [33]: the channel names match the standard Massimini & Carli 8-channel model. Checked from domain knowledge; the book was not re-read.
- Every † item in §4.5 (store prices, rating counts, cat counts, Viridi wilting, the Usagi Shima quote) needs a fresh store or press check before it is quoted outside the team.

---

## References
1. Short, T. X. (ed.), Forbes, J., Cook, D., Howe, C., Eiserloh, S., Hurd, D., Ordon, A., Diaz, J.; moderator Meiners, R. (2017). *Coziness in Games: An Exploration of Safety, Softness and Satisfied Needs.* Project Horseshoe. projecthorseshoe.com/reports/featured/ph17r3.htm
2. Waszkiewicz, A., & Bakun, M. (2020; issue 12.3 published Feb 2021). Towards the aesthetics of cozy video games. *J. Gaming & Virtual Worlds* 12(3), 225–240.
3. Krzywinska, T., Brown, D., Ma, M., Belinskiy, A., & Bhui, K. (online Jan 2025; print 2026). Coziness in Games: Second Homes, Audiences, and Esthetics. *Games and Culture* 21(5), 1170–1188. doi:10.1177/15554120241310920
4. Daneels, R., & Maes, K. (2025). Curled up with a good game. *Eludamos* 16(2), 185–215. eludamos.org/index.php/eludamos/article/view/7938. The DOI is unverified: the earlier "10.7557/ejcgc…" did not match the journal's 10.7557/23.xxxx pattern.
5. Buergi, J. (2024). Idle Games: A Cozy Genre Turned Exploitative. *Replay* 2(12), 73–86. doi:10.18778/2391-8551.12.02
6. Andiloro, A. (2024). Comfortably Numb: An Ideological Analysis of Coziness in Videogames. *Replay* 1(11), 79–92. czasopisma.uni.lodz.pl/Replay/article/view/23169 (DOI 10.18778/2391-8551.11.06 is unverified).
7. Johannes, N., Vuorre, M., & Przybylski, A. K. (2021). Video game play is positively correlated with well-being. *R. Soc. Open Sci.* 8:202049. doi:10.1098/rsos.202049
8. Vuorre, M., Johannes, N., Magnusson, K., & Przybylski, A. K. (2022). Time spent playing video games is unlikely to impact well-being. *R. Soc. Open Sci.* 9:220411. doi:10.1098/rsos.220411
9. Yee, A. Z. H., & Sng, J. R. H. (2022). Animal Crossing and COVID-19. *Front. Psychol.* 13:800683. doi:10.3389/fpsyg.2022.800683
10. Zhu, L. (2021; online 2020). The psychology behind video games during COVID-19: Animal Crossing: New Horizons. *Hum. Behav. Emerg. Technol.* 3(1). doi:10.1002/hbe2.221
11. Barr, M., & Copeland-Stewart, A. (2022; online 2021). Playing video games during the COVID-19 pandemic and effects on players' well-being. *Games and Culture* 17(1), 122–139.
12. Russoniello, C. V., O'Brien, K., & Parks, J. M. (2009). The effectiveness of casual video games in improving mood and decreasing stress. *J. CyberTher. Rehabil.* 2(1), 53–66.
13. Desai, V., Gupta, A., Andersen, L., Ronnestrand, B., & Wong, M. (2021). Stress-reducing effects of playing a casual video game among undergraduate students. *Trends in Psychology* 29(3), 563–579. doi:10.1007/s43076-021-00062-6
14. Reinecke, L. (2009). Games and Recovery. *J. Media Psychol.* 21(3), 126–142. doi:10.1027/1864-1105.21.3.126
15. Heinze, R. A., Mandryk, R. L., & Klarkowski, M. (2024). Exploring the Role of Action Mechanics in Game-Based Stress Recovery. CHI PLAY. doi:10.1145/3677070
16. Kaplan, S. (1995). The restorative benefits of nature. *J. Environ. Psychol.* 15, 169–182. doi:10.1016/0272-4944(95)90001-2
17. Berman, M. G., Jonides, J., & Kaplan, S. (2008). The cognitive benefits of interacting with nature. *Psychol. Sci.* 19(12), 1207–1212. doi:10.1111/j.1467-9280.2008.02225.x
18. Stevenson, M. P., Schilhab, T., & Bentsen, P. (2018). Attention Restoration Theory II. *J. Toxicol. Environ. Health B* 21(4). doi:10.1080/10937404.2018.1505571
19. Ohly, H., et al. (2016). Attention Restoration Theory: A systematic review. *J. Toxicol. Environ. Health B.* doi:10.1080/10937404.2016.1196155
20. Ulrich, R. S., Simons, R. F., Losito, B. D., Fiorito, E., Miles, M. A., & Zelson, M. (1991). *J. Environ. Psychol.* 11(3), 201–230. doi:10.1016/S0272-4944(05)80184-7
21. Van den Berg, A. E., et al. (2026). Psychophysiological recovery from viewing nature and urban settings: A multisite replication. *J. Environ. Psychol.* 111:102956. doi:10.1016/j.jenvp.2026.102956
22. Spano, G., Theodorou, A., et al. (2023). Virtual nature and psychological and psychophysiological outcomes. *J. Environ. Psychol.* 89:102044. doi:10.1016/j.jenvp.2023.102044
23. Li, H., Ding, Y., Zhao, B., Xu, Y., & Wei, W. (2023). Effects of immersion in a simulated natural environment on stress reduction and emotional arousal. *Front. Psychol.* doi:10.3389/fpsyg.2022.1058177
24. Spehar, B., Clifford, C. W. G., Newell, B. R., & Taylor, R. P. (2003). Universal aesthetic of fractals. *Computers & Graphics* 27(5), 813–820. doi:10.1016/S0097-8493(03)00154-7
25. Hägerhäll, C. M., Purcell, T., & Taylor, R. P. (2004). Fractal dimension of landscape silhouette outlines as a predictor of landscape preference. *J. Environ. Psychol.* 24, 247–255.
26. Taylor, R. P. (2006). Reduction of physiological stress using fractal art and architecture. *Leonardo* 39(3), 245–251. doi:10.1162/leon.2006.39.3.245
27. Taylor, R. P. (2021). The potential of biophilic fractal designs to promote health and performance. *Sustainability* 13:823. doi:10.3390/su13020823
28. Browning, W., Ryan, C., & Clancy, J. (2014; 10th-anniv. ed. 2024). *14 Patterns of Biophilic Design.* Terrapin Bright Green.
29. Bar, M., & Neta, M. (2006). Humans prefer curved visual objects. *Psychol. Sci.* 17(8), 645–648.
30. Valdez, P., & Mehrabian, A. (1994). Effects of color on emotions. *J. Exp. Psychol. Gen.* 123(4), 394–409. doi:10.1037/0096-3445.123.4.394
31. Glocker, M. L., Langleben, D. D., Ruparel, K., Loughead, J. W., Gur, R. C., & Sachser, N. (2009). Baby schema in infant faces induces cuteness perception and motivation for caretaking in adults. *Ethology* 115(3), 257–263. doi:10.1111/j.1439-0310.2008.01603.x
32. Nittono, H., Fukushima, M., Yano, A., & Moriya, H. (2012). The power of kawaii. *PLoS ONE* 7(9):e46362. doi:10.1371/journal.pone.0046362
33. Massimini, F., & Carli, M. (1988). The systematic assessment of flow in daily experience. In Csikszentmihalyi & Csikszentmihalyi (Eds.), *Optimal Experience.* Cambridge UP. See also Csikszentmihalyi, M. (1990). *Flow.*
34. Russell, J. A. (1980). A circumplex model of affect. *J. Pers. Soc. Psychol.* 39(6), 1161–1178. doi:10.1037/h0077714
35. Sonnentag, S., & Fritz, C. (2007). The Recovery Experience Questionnaire. *J. Occup. Health Psychol.* 12(3), 204–221. doi:10.1037/1076-8998.12.3.204
36. Lehrer, P. M., & Gevirtz, R. (2014). Heart rate variability biofeedback: how and why does it work? *Front. Psychol.* 5:756. doi:10.3389/fpsyg.2014.00756
37. Ryan, R. M., Rigby, C. S., & Przybylski, A. (2006). The motivational pull of video games. *Motiv. Emot.* 30(4), 347–363. doi:10.1007/s11031-006-9051-8
38. Tyack, A., & Mekler, E. D. (2020). Self-Determination Theory in HCI Games Research. CHI '20. doi:10.1145/3313831.3376723
39. Alharthi, S. A., Alsaedi, O., Toups, Z. O., Tanenbaum, T. J., & Hammer, J. (2018). Playing to Wait: A Taxonomy of Idle Games. CHI '18. doi:10.1145/3173574.3174195
40. Pecorella, A. GDC 2015 (GDC Vault 1022065/1022066); GDC Europe 2016 "Quest for Progress" (media.gdcvault.com slides); "The Math of Idle Games" Parts I–III (kongregate.com/en/pages/the-math-of-idle-games-part-i, -ii, -iii).
41. Cookie Clicker Wiki, "Building" (cookieclicker.wiki.gg): price = base·1.15^(owned−free).
42. Zagal, J. P., Björk, S., & Lewis, C. (2013). Dark Patterns in the Design of Games. *Foundations of Digital Games 2013.*
43. Petrovskaya, E., & Zendle, D. (2022). Predatory Monetisation? *J. Bus. Ethics* 181(4), 1065–1081. doi:10.1007/s10551-021-04970-6
44. Zendle, D., & Cairns, P. (2018). Video game loot boxes are linked to problem gambling. *PLoS ONE* 13(11):e0206767. doi:10.1371/journal.pone.0206767
45. Silverman, J., & Barasch, A. (2023). On or Off Track: How (Broken) Streaks Affect Consumer Decisions. *J. Consumer Res.* 49(6), 1095–1117.
46. W3C (2023). WCAG 2.2, Success Criterion 2.3.1 "Three Flashes or Below Threshold".
47. Godot 4.7.2-stable source (`/home/user/godotengine/godot`):
    - `doc/classes/Node.xml:1311-1327`: `NOTIFICATION_APPLICATION_RESUMED` = 2014, `NOTIFICATION_APPLICATION_PAUSED` = 2015 (iOS ~5 s note), `FOCUS_IN`/`FOCUS_OUT` = 2016/2017 "Implemented on desktop and mobile platforms"; `:1256-1258` `NOTIFICATION_WM_CLOSE_REQUEST` is desktop only.
    - `doc/classes/Time.xml:10-11` (UTC and clock-change warning), `:108-121` (`get_ticks_msec`/`get_ticks_usec`), `:180-186` (`get_unix_time_from_system` returns a float).
    - `scene/main/scene_tree.cpp:926-946`: pause, resume and focus in/out propagated to all nodes.
    - `platform/android/java/lib/src/main/java/org/godotengine/godot/GodotGLRenderView.java:105-110` and `platform/android/java_godot_lib_jni.cpp:680,695`: Android order.
    - `drivers/apple_embedded/app_delegate_service.mm:152-191` and `os_apple_embedded.mm:774-823`: iOS order.
    - Notifications: `doc/classes/OS.xml:807` (`request_permission("android.permission.POST_NOTIFICATIONS")`) and `platform/android/doc_classes/EditorExportPlatformAndroid.xml:394` (`permissions/post_notifications`); no scheduling API in core.
48. Game facts: App Store / Google Play listings (Cats & Soup id1581431235; A Little to the Left id1613352146; Usagi Shima id1632728038); godotengine.org/article/godot-showcase-usagi-shima; ustwogames.co.uk (Alba, 1M trees, 2021-12-02); wearesecretmode.com (ALTTL mobile); Pocket Gamer; Siliconera; Engadget 2020-03-28 (Kind Words); Nintendo eShop listing (Cozy Grove "30–60 minutes of new quest content each day"); Kill Screen / Wikipedia (Viridi); press release (Townscaper mobile $4.99); Nintendo Life and *A Most Agreeable Pastime* (Dorfromantik); Well Played, RPG Fan (Wanderstop); marlvel.ai aggregator (Fishing and Life, low reliability).
49. Nielsen, J. (1993). *Usability Engineering*, ch. 5 "Response times: the three important limits" (0.1 s / 1 s / 10 s; building on Miller 1968 and Card, Robertson & Mackinlay 1991).

---

## Verification log
Fact-check on 2026-10-20 against the Godot 4.7.2-stable tree (`git describe` → `4.7.2-stable`) and the web.

**How sources were checked:**
- WebFetch failed with DNS errors for every host tried: projecthorseshoe.com, royalsocietypublishing.org, pmc.ncbi.nlm.nih.gov.
- curl to api.crossref.org was refused by the proxy (403).
- Web evidence therefore comes from search-indexed abstracts and repository pages.
- The shared search budget ran out after about 30 queries. Rows marked "prior knowledge" were checked against the checker's domain knowledge only, not re-fetched.

**Verdicts:** OK = confirmed · FIXED = text corrected · FLAGGED = left in but marked unverified or unsupported.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | `NOTIFICATION_APPLICATION_PAUSED` = 2015, Android/iOS only, iOS ~5 s limit | OK | `doc/classes/Node.xml:1315-1319` |
| 2 | `NOTIFICATION_APPLICATION_RESUMED` = 2014, Android/iOS | OK | `Node.xml:1311-1314` |
| 3 | `Time.get_unix_time_from_system()` is UTC; docs warn the user can change the clock | OK | `doc/classes/Time.xml:10-11,180-186` (returns `float`) |
| 4 | `Time.get_ticks_msec()` is monotonic | OK | `Time.xml:11,108-114` |
| 5 | Save-on-exit path (added): FOCUS_OUT precedes PAUSED; WM_CLOSE_REQUEST is desktop only | FIXED (added) | `GodotGLRenderView.java:105-109`; `java_godot_lib_jni.cpp:680,695`; `app_delegate_service.mm:152-191`; `os_apple_embedded.mm:774-823`; `scene_tree.cpp:926-946`; `Node.xml:1256-1258,1320-1327` |
| 6 | Opt-in notifications are implementable | FIXED (caveat) | Core has no scheduling API, only the permission request: `OS.xml:807`, `EditorExportPlatformAndroid.xml:394`. A native plugin would be needed, which conflicts with TEAM.md |
| 7 | GPUParticles2D / SubViewport / Line2D / Polygon2D available under Compatibility | OK | `doc/classes/*.xml` exist; `drivers/gles3/storage/particles_storage.cpp`. Only `emit_particle` is unsupported in Compatibility (`GPUParticles2D.xml:41`) |
| 8 | Compatibility renderer premise | OK | Matches 01-godot-4.7-engine.md R1; `ProjectSettings.xml:3279-3291` |
| 9 | PH17 [1] participants | FIXED (full list) | lostgarden.com/2018/01/24/cozy-games; gamedeveloper.com/design/designing-for-coziness |
| 10 | PH17 verbatim quotes ("a flavor that…", "Nothing is lacking…", "consensual notifications") | FLAGGED | Source site unreachable (DNS); seen only in search excerpts |
| 11 | Waszkiewicz & Bakun [2], JGVW 12(3) 225–240 | OK (issue published Feb 2021) | intellectbooks.com, issue 12.3 announcement |
| 12 | [2] coherent/dissonant/situational typology; tending/befriending/storytelling | FLAGGED | No source found (search returned nothing) |
| 13 | Krzywinska et al. [3], authors, DOI, 21(5) 1170–1188 | OK | repository.falmouth.ac.uk/5082; ora.ox.ac.uk |
| 14 | Daneels & Maes [4]: N = 277, five motives | OK; DOI FIXED | eludamos.org/index.php/eludamos/article/view/7938. The DOI "10.7557/ejcgc…" did not fit the journal's 10.7557/23.x pattern (doaj/septentrio) |
| 15 | Buergi [5]: selling shortcuts exploits impatience; DOI | OK | czasopisma.uni.lodz.pl/Replay/article/view/23588 |
| 16 | Andiloro [6] | FIXED (2024, 1(11), pp. 79–92); DOI FLAGGED | czasopisma.uni.lodz.pl/Replay/article/view/23169 |
| 17 | Johannes et al. [7]: small positive correlation; needs independent of time | OK; PvZ N FLAGGED | Search abstract of PMC8074794 / doi:10.1098/rsos.202049 |
| 18 | Vuorre et al. [8]: 38,935 players, 7 publishers, 6 weeks; intrinsic +, extrinsic − | OK | oii.ox.ac.uk; psypost.org 2022-09; PMC9326284 |
| 19 | Yee & Sng [9]: players quit when needs were thwarted | OK | PMC9022176 abstract; sutd.edu.sg highlight |
| 20 | Barr & Copeland-Stewart [11]: N = 781, 71%, 58% | OK | eprints.gla.ac.uk/240064 |
| 21 | Russoniello et al. [12]: "only **untimed** play cut stress", hence "timers are the enemy" | **FIXED** | Timed vs untimed was never compared; "untimed" describes the Bejeweled 2 mode used (Daily Herald). ECU release 2008-04-28: Bejeweled −54% physiological stress vs control; Peggle and Bookworm not significant. Issue 2(1) added. P2's basis rewritten |
| 22 | "Wong et al. 2021" [13] | **FIXED** | First author is V. Desai (Wong is last author); *Trends Psychol.* 29(3) 563–579; experts.mcmaster.ca/scholarly-works/1963907 |
| 23 | Heinze et al. [15]: action mechanics restore mastery | FIXED (added N = 60 and "undermined relaxation") | api.crossref.org/works/10.1145/3677070 (abstract) |
| 24 | Stevenson et al. [18]: 42 studies; WM, flexibility, attentional control; low–moderate; real > virtual possibly due to duration | OK | research.regionh.dk record of doi:10.1080/10937404.2018.1505571 |
| 25 | 2026 Ulrich replication [21]: N = 959, 10 teams; psych yes, parasympathetic only | OK; FIXED (title, DOI, "partly", water-noise caveat) | research.vu.nl; openresearch.surrey.ac.uk (doi:10.1016/j.jenvp.2026.102956) |
| 26 | Spano et al. [22]: 59 studies | OK | art.torvergata.it publisher PDF record |
| 27 | Li et al. [23]: medium immersion largest effect on positive affect; RoB moderate–high; 26 publications | OK | PMC9869155 (search abstract) |
| 28 | Bar & Neta [29]: 84 ms exposure; sharp contours may signal threat | OK | nmr.mgh.harvard.edu/publications/journal_articles/743 |
| 29 | Spehar et al. [24]: preferred D ≈ 1.3–1.5 across natural, mathematical and Pollock images | OK (secondary) | Street et al. 2016, *Front. Hum. Neurosci.* doi:10.3389/fnhum.2016.00213 |
| 30 | Valdez & Mehrabian [30]: P = .69B + .22S, A = −.31B + .60S | OK; FIXED (standardized Munsell variables, so HSV is a proxy) | pubmed.ncbi.nlm.nih.gov/7996122 abstract. The yellow/green-yellow addition is prior knowledge, not re-fetched |
| 31 | Glocker et al. [31]: features "big head, large low-set eyes" | FIXED (manipulated features, N = 122, authors, DOI) | cceb.upenn.edu PDF; repository.upenn.edu/cog_neuro_pubs/11 |
| 32 | Silverman & Barasch [45]: 7 studies; self-blame moderates | OK; FIXED (added "repairable" moderator) | colorado.edu 2023-04-19 research note; udspace.udel.edu/handle/19716/34160 |
| 33 | Ryan, Rigby & Przybylski [37]: A, C, R "independently predict" | FIXED (scoped to the MMO study) | Prior knowledge of the abstract |
| 34 | P9: 4–6 s breath is "toward the ~0.1 Hz band" | FIXED | Arithmetic: 4–6 s = 0.17–0.25 Hz, while 0.1 Hz = 10 s [36]. Now framed as normal resting pace, with no entrainment claim |
| 35 | P12 ≤ 100 ms | OK; source added [49] | Nielsen 1993 (prior knowledge) |
| 36 | Pecorella GDC 2015 title; "the brief's 2016 is wrong; 2016 had Idle Chatter" | FIXED (removed internal-brief remark and the unverified "Idle Chatter"); Vault IDs FLAGGED | Prior knowledge; not re-searched |
| 37 | AdCap Lemonade Stand: base 4, r = 1.07, 1.67/s; 4·1.07¹⁰ = 7.87 | OK | Recomputed with python (7.869). Constants match "Math of Idle Games I" (prior knowledge) |
| 38 | r-table: doubling, r¹⁰, r¹² | OK | Recomputed with python: 10.24/7.27/6.12/4.96; 1.967/2.594/3.106/4.046; 2.252/3.138/3.896/5.350 |
| 39 | "last copy ≤ 3.9× the first" | FIXED | The 12th copy is r¹¹ = 3.48× at r = 1.12 |
| 40 | Concept scores 82.6 / 92.0 / 86.2; doubled-(d) 4.11 / 4.51 / 4.42 | OK; labels FIXED | Recomputed with python (B uses e = 4) |
| 41 | Zendle & Cairns [44]: N = 7,422; η² .054 vs .004 | OK (prior knowledge) | Not re-searched (budget) |
| 42 | Petrovskaya & Zendle [43]: 1,104 players, 35 techniques, 8 domains | FLAGGED (not re-verified) | Search budget exhausted. Plausible from prior knowledge |
| 43 | Alharthi et al. [39]: 66 idle games | OK (prior knowledge) | Not re-searched |
| 44 | Zagal et al. [42]: temporal, monetary and social-capital categories | OK (prior knowledge) | — |
| 45 | WCAG 2.2 SC 2.3.1: ≤ 3 flashes/s | OK (prior knowledge) | w3.org/TR/WCAG22 |
| 46 | Massimini & Carli 8-channel names [33] | OK (prior knowledge) | — |
| 47 | §4.5 store and press figures: Neko Atsume 49/17 cats and IAP, Cats & Soup rating, ALTTL prices, Alba 1M trees, Viridi wilting, Usagi Shima quote | FLAGGED (†) | Not re-verified. The Neko counts were softened because they changed across updates |
| 48 | Standard citations: Kaplan 1995, Berman 2008, Ulrich 1991 N = 120, Russell 1980, Sonnentag & Fritz 2007, Reinecke 2009, Hägerhäll 2004, Taylor 2006/2021, Nittono 2012, Tyack & Mekler 2020, Zhu 2021, Lehrer & Gevirtz 2014 | OK (prior knowledge) | Bibliographic data consistent with the checker's knowledge; not re-fetched |

**Summary:** 48 rows covering about 60 individual claims. 17 rows FIXED (two of them additions) and 7 FLAGGED; the rest OK.
