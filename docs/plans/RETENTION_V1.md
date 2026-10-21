# Retention v1: "a reason to come back tomorrow"

*Director · 2026-10-21 · status: **proposed**, awaiting owner approval · scope: features 1–3 from the review discussion*

## 0. Problem and goal

At the current pace a reference player (2 × 5 min/day) meets all 12 species by about **day 8**. After that the only pulls are the basket and the recap, and there is nothing left to wonder about.

**Goal.** Keep the reference player curious and attached **through day 30 and beyond**, without breaking any design principle (E1–E9 in `docs/research/00-SYNTHESIS.md` §4: no streaks, no FOMO, no decay, no punishment for being away).

The three mechanisms are:

| # | Feature | Psychological lever | Builds on what exists |
|---|---|---|---|
| F1 | **Friendship depth**: 5 heart levels per mossling, each unlocking something specific | Relatedness (SDT), the endowment effect | `affection`, `heart_thresholds [3,8,15,25,40]`, `postcard_heart2/4` |
| F2 | **Mystery signs**: clues that an unmet species is coming | Curiosity / information gap (Loewenstein 1994) | the species `hint_key`, `debut_chance`, attraction rules |
| F3 | **Away scenes**: small staged moments that happen only while you're gone | Variable, *positive* reward for absence | `recap.gd`, `photo_meta`, the creature brain |

### Success metrics

Measured by extending `tools/sim/economy_sim.py` with a "content-left" model.

| Metric | Now | Target |
|---|---|---|
| Days on which the reference player has ≥ 1 *new* thing to discover (species, heart unlock, clue, scene, postcard) | ~8 | **≥ 30 of the first 30** |
| Median day the last heart-5 is reached across 12 species | n/a | **45–70** (a long tail by design) |
| Sessions with nothing new *and* nothing affordable | 0 | 0 (E5 stays) |
| Anything that decreases, expires or is missable | 0 | 0 (E1/E8 stay) |

## 1. Feature specs

### F1. Friendship depth (hearts 1–5)

Affection already accrues (+1 per visit, pet or boat) and never decays. Each level gets a concrete, visible unlock:

| Heart | Threshold (existing) | Unlock | Visible where |
|---|---|---|---|
| 1 | 3 | Its **name** can be changed, and it **waves** when you open the app | Album, world |
| 2 | 8 | **Story postcard I** (existing `postcard_heart2`) plus its **signature gift** (unique item per species, new `signature_gift`) | Basket, postcards |
| 3 | 15 | **Nest**: a personal sleeping spot near its favourite spot that grows over 3 days (twigs → moss bed → flower canopy) | World |
| 4 | 25 | **Story postcard II** (existing `postcard_heart4`) plus a **friend pair**: it now seeks out its best friend species and they nap/play together (a pair animation) | World, Album |
| 5 | 40 | **Keepsake**: a framed plush-portrait photo in the Album, and it can bring **one rare variant cousin** (see F2) | Album |

Notes:
- **Pacing:** heart-5 needs about 40 interactions. With visits at about 2/h shared across species, plus pets, that is weeks for most species. It is intentionally slower for rare ones.
- **Nest growth** uses real time, and nests never wilt (E1).

**Data** (`data/species.json`, per species):
- `signature_gift`
- `nest_style`
- `best_friend`
- `postcard_heart2`, `postcard_heart4` (the existing keys)
- new `postcard_heart5`

**Data** (new `data/friendship.json`): unlock table, nest growth stages and their seconds, pair-behaviour weights.

### F2. Mystery signs

When an unmet species becomes eligible (its attraction rule is satisfied, a check `WorldSim` already runs for `debut_chance`), the sim schedules **1–3 signs** over the next real hours *before* its debut. Each sign appears at a world anchor and is tappable:

- **footprints** in the moss (species-shaped paw/blob stamp);
- **a dropped thing**: a leaf, feather, petal or acorn in its colours;
- **a rustle**: a bush shakes, with a soft species-voiced chirp (AudioDirector cue);
- **a note**: a tiny postcard with a poetic riddle built from its existing `hint_key` ("Someone who loves the smell of sweet clover after rain…").

Tapping a sign adds it to a new **"Clues"** row in the Album: a silhouette card with the clues collected so far. Signs are **never missable**. They wait until seen, and the debut can happen regardless.

- **Post-album long tail:** after all 12 are met, heart-5 friends can bring **variant cousins** (colour/pattern variants, e.g. "Twilight Puffmoss"). Each variant is announced by signs and has an explicit, deterministic condition, never a random draw. MVP: **1 variant per species = 12 more discoveries.**
- **Data** (new `data/mysteries.json`): sign types, anchors, timing windows, riddle string keys; plus `variants` per species (rig colour overrides + condition).

### F3. Away scenes

When the player returns after **≥ 2 h**, the recap can show one **staged scene** chosen deterministically (seeded) from those whose conditions hold:

| Scene | Condition | What you see |
|---|---|---|
| Nap pile | ≥ 3 sleepers, night or rain | Mosslings stacked in a cuddle heap at the sun stone |
| Pebble tower | Cairn décor ≥ 1, ≥ 2 visitors | A wobbly stone tower beside a proud builder |
| Leaf fort | Rain fell while away | A leaf-umbrella fort with eyes peeking out |
| Moon watchers | Night passed, clear | Two friends sitting by the brook facing the moon |
| Flower crowns | ≥ 3 beds in bloom | A friend wearing a flower crown |
| Boat regatta | ≥ 5 boats sent lifetime | Three leaf boats lined up on the bank |
| Lantern party | ≥ 3 lanterns, dusk/night | Mosslings circling a lantern |
| Pair nap | A heart-4 pair exists | The best friends asleep back to back |

How scenes behave:
- The scene stays **in the world** until the player taps it or 10 min pass. It is then photographed into the Album **"Memories"** tab (metadata only, rendered live like the existing photos) and the world returns to normal.
- **Never missable:** if you never return to see it, nothing is lost, and the next return picks again.
- At most **1 scene per return**, so it stays special. Repeats are allowed only after all applicable scenes have been seen once.

**Data** (new `data/scenes.json`): conditions, participants (count, roles), pose ids, anchor, string keys.

## 2. Work breakdown (teams and file ownership as in the production rounds)

| Phase | Team | Deliverables | Est. |
|---|---|---|---|
| **P0 Design** | Game Designer | GDD §13 "Retention v1". Fill `friendship.json`, `mysteries.json`, `scenes.json` and the species fields. Write 12 × 3 story postcards (heart 2/4/5) + 12 riddles + 8 scene captions + 12 variant names in **en + natural vi** (`i18n/strings.csv`). Extend `economy_sim.py` with the content-left metric and iterate until §0 targets pass | 1 round |
| **P1 Systems** | Gameplay Engineer | `WorldState` fields (`nests`, `signs`, `clues`, `variants_met`, `scenes_seen`, `memories`), **save schema +1 with a migration** in `SaveStore`. `WorldSim` steps for sign scheduling, nest growth, scene selection on return, variant debuts. `Game` API (`tap_sign`, `tap_scene`). GUT tests for determinism, the never-decreasing rule, offline parity with the Python sim, and migration from the current schema | 1 round |
| **P2 Creatures** | Creature team | Wave (heart 1), pair nap/play poses, nap-pile / leaf-fort / moon-watch / crown / lantern-circle staging poses, variant colourways via `creature_rig.json`, heart-up celebration (`celebrate` token, ≤ 1 s, no input block) | 1 round |
| **P2 World** | Env + Garden | Footprint, dropped-item and rustling-bush stamps (SVG tone masks, plush/felt look). Nests ×3 stages × 4 styles. Pebble tower, leaf fort, flower crown, boat line-up props. All within ≤ 100 draw calls | 1 round, parallel |
| **P2 UI** | UI team | Album tabs: Friends (heart bar + unlock list), **Clues** (silhouette cards), **Memories** (scene photos), Keepsakes. Heart-up toast. Recap card shows the scene teaser ("Something happened by the sun stone…"). vi/en, text 200 %, night chrome | 1 round, parallel |
| **P2 Audio** | Sound Designer | Cues: sign rustle (per-species voice step), clue found, heart-up chime, scene reveal. Synthesized in `tools/audio/`, pass the loudness/spectral gates | parallel |
| **P3 QA** | QA + 3 raters | Fixtures `--fixture=retention_mid` (hearts spread 1–5, 2 nests, 2 open clues, a pending scene) and `--qa-scene=<id>`. Rubric pass on the new views. Copy audit for E8 banned words. 30-day sim report | 1 round |

**Order:** P0 → P1 → P2 (four teams in parallel) → P3. That is about 4 workflow rounds, similar in size to the production rounds.

## 3. Risks and guards

| Risk | Guard |
|---|---|
| Hearts feel like a grind | Every visit already counts. No heart requires active play beyond petting. The sim checks that the median player reaches heart-3 on ≥ 6 species by day 14 |
| Signs read as FOMO ("hurry!") | Signs never expire. Copy is wonder-framed, never urgent. The E8 banned-word audit runs on all new strings |
| Scenes feel random or punishing | Deterministic seed, never missable, at most 1 per return, only positive staging |
| Save migration bug loses progress | Migration test from a real current-schema save fixture. Existing `.bak` fallback. Additive fields only |
| Content cost (36 postcards, 12 riddles, 12 variants) | Template-driven writing by the GDD role. Variants are rig colour overrides only, no new shapes |
| Visual clutter | ≤ 1 scene and ≤ 3 signs on screen. Every new prop obeys the 30–40 % calm-area rule (V-principles) |

## 4. Out of scope for v1

- Seasons and real-calendar festivals (Tết, Trung thu), planned for v2.
- New areas (pond, mushroom grove).
- Accessories.
- Notifications and widgets, which need native plugins and a new ADR.
