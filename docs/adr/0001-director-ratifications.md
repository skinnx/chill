# ADR 0001 — Director ratifications after the design phase

*Status: accepted · 2026-10-21 · Director*

| # | Proposal | Raised by | Ruling | Rationale |
|---|---|---|---|---|
| 1 | **V2 at dusk/night** is measured as ≥ 85 % of area at OKLCh C ≤ 0.10, no pixel below L* 6, accents (C > 0.12) ≤ 10 % (Art Bible §11.3, A6). Dawn/day/golden keep the HSV rule. | Art Director | **Accepted** | The binding night palette is dark by design; the low-arousal intent of 04 P6 is about saturation, which the chroma test measures correctly in the dark. |
| 2 | **Save format** uses typed `to_dict`/`from_dict` + checksum over the read-back JSON instead of `JSON.from_native`. | Tech Lead | **Accepted** | Explicit schema is safer against `user://` tampering and float round-trip drift; D12's intent (versioned JSON, atomic write, `.bak`) is unchanged. |
| 3 | `greeter_stay_s` and `greeter_pet_cooldown_s` added to `data/economy.json`. | Tech Lead | **Accepted** | Data stays the single source of truth; the greeter gives no reward (E8-safe). |
| 4 | **Golden images** are blessed only after the R1 look-spike gate passes. | QA | **Accepted** | Placeholder goldens would be replaced wholesale. |
| 5 | Rubric verdict = the lower of the median-based and mean-based levels. | QA | **Accepted** | Satisfies both the Art Bible (median) and TEAM.md (average); conservative. |
| 6 | `gdformat` advisory, `gdlint` gating. | QA | **Accepted** until feature work settles; revisit before 1.0. |
| 7 | Pads use A/B players instead of `AudioStreamInteractive` (D10). | Sound Designer | **Accepted**, conditional on equal-power linear-gain crossfades. | Same musical result, simpler Web fallback. |
| 8 | Audio sources (~31 MB WAV/OGG) stay in git without LFS. | Sound Designer | **Accepted** for now (shipped size 9.67 MB after import). Revisit if the repo exceeds 150 MB. |
