# 06 — Relaxing Audio, Generative Music & Haptics

**Role:** Audio & Haptics Researcher · **Date:** 2026-10-20 · **Engine:** Godot 4.7.2-stable · **Status:** v1.1, adversarially fact-checked 2026-10-20 (see "Verification log" at the end)
**Concept fit:** "Mossling Meadow" (report 04): stream, rain weather, petting, unfurling buds, day–night on the device clock.
**Tags:** **[V]** verified against engine source (path:line), an official doc, or measured in this container · **[W]** peer-reviewed abstract or textbook result · **[J]** our judgement; tune it on a device.
**Method:**
- Journal hosts were unreachable, so papers were read through abstracts and records found by search.
- Every DSP recipe was **run** (numpy 2.5.3, scipy 1.18.1). Loudness was cross-checked three ways: my BS.1770 code, pyloudnorm 0.2.0 and `ffmpeg ebur128`.
- Godot behaviour was checked headless with the 4.7.2 editor binary.
- Prototypes: `/tmp/claude-research/audio/synth.py` and `/tmp/claude-research/gdtest/`.

---

## 0. Audio Bible (decision summary)

### 0.1 Loudness & format contract

| Item | Decision | Basis |
|---|---|---|
| Whole-game mix | **−18 LUFS-I ±1 LU** over ≥10 min of idle play (MovieWriter capture). **TP ≤ −1 dBTP**. LRA ≤ 8 LU. Max short-term ≤ −14 LUFS-S, so nothing startles | Sony ASWG portable −18 ±2 LU [W]; EBU R128 TP [V]; −14 S [J] |
| Long files (beds, pads) | Each mastered to **−18 LUFS-I**. Mono measured as **dual-mono**. **≤ −1.5 dBTP before encoding** | Godot copies mono to L and R (`scene/resources/audio_stream_wav.cpp:206-211`) [V]. Vorbis q4 adds up to +0.2 dB TP (measured) [V] |
| Short SFX | **Momentary max (400 ms, dual-mono):** tap −24, collect −21, milestone −18 LUFS-M. Sample peak ≤ −6 dBFS | Frequent sounds sit inside the mix; rare rewards poke out 0–3 LU [J] |
| Codecs | Beds/pads: **OGG Vorbis q4 stereo**. Measured: noise beds 108–118 kb/s ≈ 0.85 MB/min; pads ≈ 80 kb/s. Notes/SFX: **16-bit mono WAV → QOA import** (default `compress/mode=2`) | ffmpeg `libvorbis` present [V]. `editor/import/resource_importer_wav.cpp:89` [V]. Report 03 §5 |
| Sample rate | **44.1 kHz**, equal to the `audio/driver/mix_rate` default. The Android OpenSL driver is hard-coded to 44.1 kHz | `servers/audio/audio_server.cpp:229`, `audio_server.h:170`; `platform/android/audio_driver_opensl.cpp:303` [V] |
| iOS session | Keep `audio/general/ios/session_category=0` (Ambient). It honours the silent switch and mixes with the player's podcasts | `core/config/project_settings.cpp:1760`; `ProjectSettings.xml:491` ("Ambient always has [mixWithOthers] set"); `drivers/apple_embedded/app_delegate_service.mm:100-125` [V] |
| Budget | ≈8 MB total: 4 beds × 60 s, 5 pads × 8 bars (29.1 s at 66 BPM, §4.3), 3 instruments × 14–18 notes (§2.4), ≈40 SFX | [J] |

### 0.2 Bus graph (built at boot, §2.5)

| Bus | Gain | Effects (in order) |
|---|---|---|
| Master | 0 dB | `AudioEffectStereoEnhance` `pan_pullout=0` (the **Mono** toggle, off by default) → `AudioEffectHardLimiter` `ceiling_db=-1.5` (sample-peak limiter, so 0.5 dB margin for the −1 dBTP goal) |
| Music | −3 dB | `AudioEffectLowPassFilter` at 20 kHz, **`resonance=0.5`** (the default; **never 0**, see §2.5 gotcha 4). Tween to 3.5 kHz at night, and to 1.2 kHz on menus or focus-out |
| Ambience | −6 dB | none (reverb baked into the files) |
| SFX | 0 dB | `AudioEffectReverb` `room_size=0.5`, **`damping=0.25`**, `spread=0.8`, `hipass=0.15`, `predelay_msec=20`, **`predelay_feedback=0`**, `dry=1`, `wet=0.15` |
| UI | −3 dB | none (dry, immediate) |

### 0.3 Music system

| Parameter | Decision |
|---|---|
| Harmony | **F Lydian**. Chords **Fmaj9, G/F, Dm9, Am7, Cmaj7**, random with no immediate repeat |
| Melody/SFX pitch | Snap to the **current chord's pentatonic set** (§2.2). No semitones or tritones *within a set*, so any melodic order is consonant. Against the pad, maj7/9 colour remains (e.g. E over F), which is intended [J] |
| Tempo | **66 BPM** (0.909 s beat, 3.64 s bar). It only quantizes chord changes (`TRANSITION_FROM_TIME_NEXT_BAR`). Voices are unmetered |
| Chord rhythm | Every **8 ±2 bars (≈29 s)**, crossfade over 6 beats (5.5 s) |
| Layers | **L0** ambience bed · **L1** pad (`AudioStreamInteractive`, one clip per chord) · **L2** 3 Eno voices (e-piano, marimba, chime) via `AudioStreamPolyphonic` · **L3** critter one-shots · **L4** SFX |
| Voice periods | **23.5 / 25.875 / 29.9375 s**, Eno's *Music for Airports* loop lengths [W]. Onsets never re-align |
| Space | Density p = 0.55 by day and 0.25 at night. ≥ 4 s between motif onsets. Every 4–7 min, a **45–90 s rest** with ambience only |
| Fatigue guard | Setting **Music: On / Ambience only / Off**. After 45 min of foreground play, music fades to ambience for 10 min [J] |

### 0.4 Time-of-day profiles (device clock, 90 s transitions)

| Phase | Bed (L0) | Pad LPF | Voices | Density | Music-bus LPF |
|---|---|---|---|---|---|
| Dawn 05–09 | birds (a phrase every 6–15 s) + light wind | 1.0 kHz | chime, e-piano | 0.5 | 20 kHz |
| Day 09–17 | stream + wind | 1.2 kHz | marimba, e-piano | 0.55 | 20 kHz |
| Dusk 17–21 | wind, few birds | 0.8 kHz | e-piano | 0.4 | 12 kHz |
| Night 21–05 | rain or soft wind + low crickets | 0.6 kHz | e-piano, −12 st | 0.25 | 3.5 kHz |
| Rain weather | rain replaces stream | — | — | −0.1 | −2 kHz |

### 0.5 SFX list (recipe IDs → §4)

| ID | Event | Recipe | Pitch rule | LUFS-M | Haptic |
|---|---|---|---|---|---|
| S01 | Tap/select | **R-E** plip, τ 50 ms, rise 0.3 | random walk ±1 pentatonic step, C5–C6 | −24 | Full: TICK |
| S02 | Collect dew/gift | R-E + R-F grace note at +40 ms | **ascending ladder** per combo; reset after 1.5 s; cap +7 steps | −21 | DOUBLE |
| S03 | Pet (hold) | "purr chime": R-A1 root 220–330 Hz, 22 Hz AM at 25 % depth, loops while held, 150 ms release | chord root | −23 | Full: 3 TICKs, 120 ms apart |
| S04 | Bud unfurls (600 ms) | R-F arpeggio, 3 tones 90 ms apart + rustle grains | chord tones, rising | −21 | TICK at end |
| S05 | Plant/place décor | R-A2 low marimba (A3–D4) + soil "pat" (LP noise, 120 ms) | root or 5th | −22 | TICK |
| S06 | Water/pour | R-C4 cluster: 6–10 bubbles in 300 ms, f0 1–2.5 kHz | — | −24 | — |
| S07 | Panel/postcard | paper rustle: 20–40 noise grains of 3–8 ms, BP 1.2–3 kHz, LP 5 kHz | — | −28 | — |
| S08 | Close/back | wood "tok": R-A2 partial 1, τ 60 ms | 5th, one octave down | −26 | — |
| S09 | Milestone/species | R-F 4-tone arpeggio + pad swell (+2 dB over 2 s) | chord tones, rising | −18 | MEDIUM |
| S10 | Welcome back | S09 + R-D bird phrase | — | −19 | MEDIUM once |
| S11 | "Not possible" | S08 lowered 5 st. **No buzz** | — | −28 | — |
| S12 | Creature arrives/naps | 2-note R-A1, up/down a 5th | chord tones | −25/−27 | — |

### 0.6 Haptics

- **Modes:** Off / **Subtle (default; no TICK)** / Full. Leave ≥ 60 ms between events.
- **Android:** `View.performHapticFeedback`, no VIBRATE permission (report 02 §2.3). TICK → `CLOCK_TICK`; DOUBLE → 2 × `CLOCK_TICK`, 70 ms apart; MEDIUM → `CONFIRM`.
- **iOS:** `Input.vibrate_handheld(12, 0.30)` / `(12, 0.42)` ×2 / `(24, 0.60)`.
- **Web:** none.

---

## 1. Science: what is supported and what is not

### 1.1 Nature sounds

- **Alvarsson, Wiens & Nilsson 2010** (*IJERPH* 7:1036, doi:10.3390/ijerph7031036) [W].
  - Design: n = 40 after a stressor. Fountain/bird sounds at 50 dBA versus traffic at 50 or 80 dBA, or ambient at 40 dBA.
  - Skin-conductance recovery *tended* to be faster with nature sound.
  - **HF-HRV did not differ.**
- **Gould van Praag et al. 2017** (*Sci Rep* 7:45273, doi:10.1038/srep45273) [W]: natural sounds produced outward-directed attention and higher peak HF-HRV than artificial sounds. Responses depended on baseline.
- **Buxton et al. 2021** (*PNAS* 118:e2013097118, doi:10.1073/pnas.2013097118) [W].
  - 36 publications, 18 meta-analysed.
  - Stress/annoyance **g = −0.60 [−0.97, −0.23]**. Health/positive affect **g = 1.63 [0.09, 3.16]**, a very wide interval. **[FLAGGED: effect sizes and CIs not re-verified by the fact-checker; PNAS/PubMed unreachable. Cite only the qualitative result until checked.]**
  - Reported: **water** best for health and affect, **birdsong** best for stress and annoyance.
- **Fan & Baharum 2024** (*Stress*, doi:10.1080/10253890.2024.2402519) [W]: versus quiet, HR (p = .006), BP (p = .001) and respiration (p = .032) improved. Perceived stress did not differ. **[FLAGGED: not re-verified (DOI/PubMed unreachable); treat the p-values as unconfirmed.]**

**Consequences [J]:**
- Water is the default bed; birds are sparse accents.
- Effects are moderate and were measured on *recordings*, so our synthesis must be believable. That is why we use physical models (Minnaert bubbles, modal bars).
- Make **no health claims** in marketing.

### 1.2 Tempo, mode, arousal — the "60–80 BPM heart-rate" myth

- **Bernardi, Porta & Sleight 2006** (*Heart* 92:445, doi:10.1136/hrt.2005.064600) [W]: n = 24. Fast tempo raised breathing, BP and HR. **A 2-min pause dropped them below baseline.**
- **Koelsch & Jäncke 2015** (*Eur Heart J* 36:3043, doi:10.1093/eurheartj/ehv430) [W]: **no studies show HR entraining to the beat**. Effects are small and inconsistent.
- **Husain et al. 2002** (*Music Percept* 20:151, doi:10.1525/mp.2002.20.2.151) [W]: **tempo drives arousal; mode drives mood.**
- **Gagnon & Peretz 2003** (*Cogn Emot* 17:25) [W]: tempo is the stronger happy/sad cue.
- **de Witte et al. 2020** (*Health Psychol Rev* 14:294, doi:10.1080/17437199.2019.1627897) [W]: 104 RCTs. Music reduces stress (physiological d = .38, psychological d = .55).

**Verdict:**
- "60–80 BPM makes your heart match" is **unsupported**. Don't repeat it.
- What is supported: slow tempo lowers arousal, major-family modes lift valence, and pauses relax.
- Hence **66 BPM**, **Lydian** and built-in rests.

### 1.3 Lo-fi, and binaural beats (excluded)

- **Lo-fi:** evidence is a 2024 pilot (Dsouza et al., *Int J Adolesc Youth*, doi:10.1080/02673843.2024.2388787) reporting lower state anxiety [W, small n]. **[FLAGGED: the fact-checker could not confirm this record (DOI resolver unreachable). Nothing in our design depends on it.]**
  - Borrow lo-fi's *sonic* traits: rolled-off highs, soft transients, maj7/9 chords, noise beds.
  - Do not borrow 70–90 BPM drum loops, which raise arousal and repeat [J].
- **Binaural beats:**
  - Garcia-Argibay et al. 2019 (*Psychol Res* 83:357): 22 studies, g = 0.45, heterogeneous.
  - Ingendoh et al. 2023 (*PLOS ONE*, doi:10.1371/journal.pone.0286023): 5 of 14 EEG studies support entrainment, **8 contradict** [W].
  - They need different tones in each ear (headphones). On a phone speaker they become ordinary beating [W].
  - **Excluded**, along with any "brainwave" claims.

### 1.4 Loudness, spectrum, fatigue

- **Loudness:**
  - −18 LUFS is the portable target: Sony ASWG used −23 for PS3 and −18 ±2 for PS Vita, per the Garry Taylor interview [W].
  - EBU R128 sets TP ≤ −1 dBTP [V].
  - BS.1770 gating (400 ms blocks, −70 LUFS absolute, −10 LU relative) is implemented in §4.8.
- **Harsh band:**
  - Peak ear sensitivity is ≈ 2–5 kHz (ISO 226; ear-canal resonance) [W]. BS.1770's K-weighting adds +4 dB above ~1.5 kHz [V].
  - **Kumar et al. 2008** (*JASA* 124:3810, doi:10.1121/1.3006380) [W]: unpleasantness tracks energy at **2.5–5.5 kHz** with **1–16 Hz modulation**.
- **Pleasantness:**
  - Sensory pleasantness falls with sharpness and roughness (Fastl & Zwicker, *Psychoacoustics: Facts and Models*, 3rd ed. 2007, ch. 9 "Sharpness and Sensory Pleasantness"; roughness is ch. 11) [W].
  - Sensory dissonance of two pure tones peaks at a separation of **≈ ¼ critical bandwidth** and is near zero beyond about one critical bandwidth (**Plomp & Levelt 1965**, *JASA* 38:548) [W]. Hence pentatonic sets (no semitone pairs). Chime pairs detuned by 0.4–1.4 Hz beat slowly, far below the roughness range (≈ 15–300 Hz modulation, Fastl & Zwicker ch. 11), so they shimmer instead of sounding rough.
- **Phone speakers:**
  - Small radiators emit little bass [W]. Put warmth in **200–600 Hz** harmonics.
  - Keep melodic fundamentals ≥ **F3 (175 Hz)**; the missing fundamental carries bass pitch.
- **Spectral QA gate [J]** (measured in §4.9):
  - Energy above 10 kHz ≤ 0.5 %.
  - Energy at 2–5 kHz ≤ 5 % for instruments, pads and UI, and ≤ 20 % for water beds.
  - Birds ≥ 15 dB under the bed.
  - No 1–16 Hz AM on bright noise.
- **Sound-off play is common:**
  - Appington 2013 (via TouchArcade): 73 % play with sound on. Tap Research, undated: 8 % play with sound on. The two figures contradict each other, and both are vendor blog posts, not peer-reviewed. **[FLAGGED: neither page could be re-fetched; the "volume ≥ 10 %" threshold and the 8 % figure are unconfirmed.]** The design rule below holds either way.
  - **Every cue needs a visual twin** (report 02) and the game must be complete when muted.

---

## 2. Generative music for hours without fatigue

### 2.1 Principles

1. **Incommensurate loops.** Eno's tape loops (23½, 25⅞, 29 15/16 s) "are not likely to come back into sync" (Eno, "Generative Music", 1996) [W]. Beds are 60 s loops with 3–11 LFO cycles per loop, so beds drift against the voices.
2. **Low-tension modal harmony.** Lydian maj7/9 chords, no dominant-7 resolutions, and about 29 s of harmonic rhythm [J].
3. **Silence budget.** Low onset probability, a minimum gap and periodic rests (Bernardi).
4. **Seeded randomness** (`RandomNumberGenerator.seed`) with no immediate repeats. QA captures stay reproducible.
5. **Adapt by time of day, not intensity.** No stingers; changes take 90 s.

### 2.2 Pitch sets (pitch class 0 = C)

| Chord clip | Pad voicing (MIDI) | Allowed melody/SFX pcs |
|---|---|---|
| `Fmaj9` | 53 57 60 64 67 | F G A C D `[5,7,9,0,2]` |
| `G/F` | 53 59 62 67 69 | G A B D E `[7,9,11,2,4]` |
| `Dm9` | 50 57 60 64 65 | D F G A C `[2,5,7,9,0]` |
| `Am7` | 57 60 64 67 | A C D E G `[9,0,2,4,7]` |
| `Cmaj7` | 55 60 64 67 71 | C D E G A `[0,2,4,7,9]` |

### 2.3 Godot 4.7.2 building blocks (verified)

| Class | Our use | Verified facts / gotchas |
|---|---|---|
| `AudioStreamInteractive` | **L1 pads**, one clip per chord | Transition `CLIP_ANY→CLIP_ANY`, `TRANSITION_FROM_TIME_NEXT_BAR`, `TO_TIME_START`, `FADE_CROSS`, `fade_beats=6`. Needs `bpm`/`bar_beats` on the OGG. **With `bpm=0`, `fade_beats` means seconds** (`modules/interactive_music/audio_stream_interactive.cpp:723,735`). **Run:** a switch requested at 0.5 s landed on the next bar (≈3.6 s at 66 BPM), and `get_current_clip_index()` went 0→1 [V] |
| `AudioStreamSynchronized` | Phase-locked stem variants, ≤ 32 | Each sub-stream loops by its own length. `set_sync_stream_volume` is stored **on the resource** (shared by all players) and applied per **128-frame** block with no ramp, so tween it. **Muted sub-streams are still decoded** (`audio_stream_synchronized.cpp:231-245`) [V] |
| `AudioStreamPlaylist` | optional bed variants | Defaults `fade_time=0.3`, `loop=true`, `shuffle=false`. **No current-index API**, so it can't drive chord logic [V] |
| `AudioStreamRandomizer` | SFX timbre variants (3–4), `random_volume_offset_db=1.5` | Pitch is **log-uniform in [1/r, r]** (`servers/audio/audio_stream.cpp:798-801`) and not scale-aware, so keep `random_pitch_semitones ≤ 0.1` [V] |
| `AudioStreamPolyphonic` | **L2 voices + SFX** from one player | `play_stream(stream, from_offset, volume_db, pitch_scale, playback_type, bus)` takes a per-voice bus. `polyphony=32` [V] |
| `AudioStreamGenerator` | **not used** | One GDScript 2-op FM voice = **7.4 ms CPU per 1 s of audio** (x86 here) [V, run]. A phone is probably 2–4× slower [J], so a 10-voice synth costs 20–40 % of the main thread and risks underruns |
| Bus sleep | free when idle | `audio/buses/channel_disable_threshold_db=-60`, `channel_disable_time=2.0` (`audio_server.cpp:1527`) [V] |

### 2.4 Conductor sketch (ran headless on 4.7.2)

```gdscript
extends Node  # autoload "AudioDirector"
const CHORDS := { &"Fmaj9": [5,7,9,0,2], &"G/F": [7,9,11,2,4], &"Dm9": [2,5,7,9,0],
	&"Am7": [9,0,2,4,7], &"Cmaj7": [0,2,4,7,9] }
const VOICES := [ {"period": 23.5, "base": 72, "notes": 2, "inst": &"ep"},
	{"period": 25.875, "base": 65, "notes": 1, "inst": &"mar"},
	{"period": 29.9375, "base": 79, "notes": 3, "inst": &"chime"} ]
@export var density := 0.55
var chord: StringName = &"Fmaj9"
var samples := {}            # {inst: {midi: AudioStreamWAV}}: 14 F-Lydian notes per instrument, preloaded
var _poly: AudioStreamPlaybackPolyphonic
var _pad: AudioStreamPlaybackInteractive   # from the AudioStreamPlayer that plays the pad AudioStreamInteractive
var _rng := RandomNumberGenerator.new()
var _last_onset := -100.0

func _ready() -> void:
	_rng.seed = 20261020
	var p := AudioStreamPlayer.new(); p.stream = AudioStreamPolyphonic.new(); p.bus = &"Music"
	add_child(p); p.play(); _poly = p.get_stream_playback()
	for v in VOICES:
		var t := Timer.new(); t.wait_time = v.period; t.autostart = true
		t.timeout.connect(_on_voice.bind(v)); add_child(t)

func next_chord() -> void:   # called every 8±2 bars
	chord = CHORDS.keys().filter(func(k): return k != chord).pick_random()
	if _pad: _pad.switch_to_clip_by_name(chord)   # bar-quantized 6-beat crossfade

func snap(midi: int) -> int:  # nearest pitch in the current chord's pentatonic set
	for d in [0, 1, -1, 2, -2, 3, -3]:
		if posmod(midi + d, 12) in CHORDS[chord]: return midi + d
	return midi

func _on_voice(v: Dictionary) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _rng.randf() > density or now - _last_onset < 4.0: return   # leave space
	_last_onset = now
	var m := snap(v.base + _rng.randi_range(-3, 3))
	for i in v.notes:
		get_tree().create_timer(i * 0.6).timeout.connect(play_note.bind(v.inst, m, &"Music"))
		m = snap(m + [2, 3, -2].pick_random())

func play_note(inst: StringName, m: int, bus: StringName, vol_db := 0.0) -> void:
	var lib: Dictionary = samples[inst]
	var key := m
	while not lib.has(key) and key > m - 12: key -= 1   # nearest rendered note at or below
	if not lib.has(key): return
	_poly.play_stream(lib[key], 0.0, vol_db + _rng.randf_range(-3.0, 0.0),
		pow(2.0, (m - key) / 12.0), AudioServer.PLAYBACK_TYPE_DEFAULT, bus)
```

- SFX use `play_note(&"plip", snap(base + step), &"SFX", -2)`; the collect ladder raises `step`.
- Render the 7 F-Lydian pitch classes over each instrument's **playable range**. `play_note` only repitches *upward* from the nearest rendered note below, and silently skips notes with nothing rendered within 12 st below them. The ranges must therefore cover what the conductor asks for (fact-check fix; the prototype's `ep_60…ep_83` set, C4–B5, would drop the night e-piano's A3–B3 and S05's low marimba):
  - e-piano: day base 72 ± 3 plus steps, night base 60 ± 3, so **F3–B5 (18 notes)**.
  - marimba: base 65 ± 3 plus S05 A3–D4, so **F3–E5 (14 notes)**.
  - chime: base 79 ± 3 with 3-note climbs, so **C5–B6 (14 notes)**.
  - Repitch then stays ≤ +2 st.

### 2.5 Bus builder (ran headless)

```gdscript
static func build() -> void:
	var add := func(n: StringName, db: float, fx: Array) -> void:
		var i := AudioServer.bus_count
		AudioServer.add_bus(i); AudioServer.set_bus_name(i, n)
		AudioServer.set_bus_volume_db(i, db); AudioServer.set_bus_send(i, &"Master")
		for e in fx: AudioServer.add_bus_effect(i, e)
	var mono := AudioEffectStereoEnhance.new(); mono.pan_pullout = 0.0   # 0 = mono downmix
	AudioServer.add_bus_effect(0, mono); AudioServer.set_bus_effect_enabled(0, 0, false)
	var lim := AudioEffectHardLimiter.new(); lim.ceiling_db = -1.5; AudioServer.add_bus_effect(0, lim)
	var duck := AudioEffectLowPassFilter.new(); duck.cutoff_hz = 20000.0; duck.resonance = 0.5   # NOT 0: 0 -> Q 0.0001 -> ~-40 dB
	add.call(&"Music", -3.0, [duck]); add.call(&"Ambience", -6.0, [])
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.5; rev.damping = 0.25; rev.spread = 0.8; rev.hipass = 0.15
	rev.predelay_msec = 20.0; rev.predelay_feedback = 0.0; rev.dry = 1.0; rev.wet = 0.15
	add.call(&"SFX", 0.0, [rev]); add.call(&"UI", -3.0, [])
```

**Engine gotchas [V: source + measurement]:**
1. **`AudioEffectReverb.damping` is reflectivity: higher means brighter.**
   - The in-loop LP cutoff is `((damping/2+0.5)^2)·10 kHz`: 2.5 kHz at 0, 10 kHz at 1 (`servers/audio/effects/reverb_filter.cpp:290-293`).
   - Captured tails had a centroid of **504 Hz** at damping 0 and **2418 Hz** at damping 1.
   - Use 0.2–0.3 for a warm room.
2. **"Predelay" is a feedback echo into the reverb, not a pure delay** (`reverb_filter.cpp:61-85`, the feedback at :79).
   - The defaults (150 ms, feedback 0.4) cause repeats. Set feedback to 0.
   - The core is Freeverb-derived: 8 combs (feedback 0.7 + 0.28·`room_size`, :278-289) and 4 all-passes. Godot's all-pass gain is **0.7** (:122), not Freeverb's 0.5.
   - `hipass` is a one-pole high-pass on the reverb input at ≈ `hipass` × 6 kHz (:91). Our 0.15 is ≈ 900 Hz, so the room never muddies the lows.
3. **`AudioEffectLimiter` is deprecated** (`doc/classes/AudioEffectLimiter.xml:2`). Use `AudioEffectHardLimiter` (default −0.3 dB). It is a look-ahead *sample-peak* limiter, so set **−1.5 dB**. That leaves margin for inter-sample peaks under the −1 dBTP target.
4. **Never set a filter's `resonance` to 0.** `AudioFilterSW` maps `resonance` straight to biquad Q and clamps Q ≤ 0 to **0.0001** (`servers/audio/audio_filter_sw.cpp:68-71`). An RBJ low-pass with Q → 0 degenerates into a ~first-order low-pass with its corner at a few Hz. Computed response at 20 kHz cutoff: −20 dB at 100 Hz, −40 dB at 1 kHz, −60 dB at 8 kHz (`/tmp/claude-verify-audio/lpf.py`).
   - At `cutoff_hz=20000`, `resonance=0` a 1 kHz sine came out **−40.4 dB** (headless 4.7.2 capture: −49.45 vs −9.03 dB RMS). The Music bus would be almost silent.
   - Use the default 0.5 (Q 0.5, no peak; −0.0 dB at 1 kHz) or 0.707 (Butterworth).

**Other notes:**
- **Ducking:** tweening the Music LPF (20 k → 1.2 kHz over 400 ms) on menus or `NOTIFICATION_APPLICATION_FOCUS_OUT` feels softer than a volume dip [J].
- **CPU:** a live SFX reverb is fine. It costs ≈ 30 MAC per sample per channel, and the bus sleeps when silent. Beds stay baked. This revises report 02 for the SFX bus only [J].
- **Web:** `audio/general/default_playback_type.web=1` (Sample). Bus **effects are not applied**, and only WAV/OGG/MP3 can be sampled (`project_settings.cpp:1755`, `audio_stream_player_internal.cpp:158-171`) [V]. The web demo uses baked-wet SFX.
- **Android latency:**
  - The OpenSL driver queues **2 × 1024 frames ≈ 46 ms** before device latency, and `output_latency` is ignored on Android (`platform/android/audio_driver_opensl.cpp:102`, `.h:44`) [V].
  - Trigger SFX on **touch-down** and keep attacks soft.
  - Measure against report 04's P12 rule (≤ 100 ms).

---

## 3. SFX rules

- **Envelopes:**
  - Raised-cosine attack of **2–10 ms**: 2 ms for plips, 5–10 ms for purrs. Below 1 ms it clicks.
  - Decay τ: **40–80 ms** for taps, 150–400 ms for collects, T60 1–3 s for milestone chimes.
- **Pitch:** quantize to the chord pentatonic. Repeats move **±1–3 semitones but stay in the scale**, so rapid taps make a melody, not a machine-gun. Combos ascend. The Randomizer only varies timbre and level (±1.5 dB).
- **Layers (≤ 3):**
  - Body: sine/FM at 200 Hz–1.5 kHz.
  - Air: noise ≤ 6 kHz, −12 dB, < 20 ms.
  - Room: SFX reverb at 15 % wet.
  - Low-pass everything at ≤ 9 kHz.
- **Polyphony:** at most 4 SFX at once; merge bursts into the S02 ladder [J].
- **No negative sounds and no error buzz** (report 04 P12).

---

## 4. Synthesis recipes (numpy + scipy, deterministic seeds)

- **Install:** `pip install scipy pyloudnorm`. pyloudnorm 0.2.0 is pure Python, MIT, and depends on scipy and numpy [V].
- **Encode:** `ffmpeg -i x.wav -c:a libvorbis -q:a 4 x.ogg` [V]. ffmpeg's native `vorbis` encoder is experimental, so use `libvorbis`.
- The excerpts below come from the tested `synth.py`. Copy it to `tools/audio/`.

### 4.1 Helpers

```python
import numpy as np
from scipy.signal import lfilter, resample_poly, fftconvolve
SR = 44100
tt = lambda d: np.arange(int(round(d*SR)))/SR
def env_ad(n, attack_ms=5., tau=.3):          # raised-cosine attack + exp decay
    t = np.arange(n)/SR; a = attack_ms/1000
    return np.where(t < a, np.sin(.5*np.pi*t/a)**2, np.exp(-(t-a)/tau))
def rbj(kind, f0, q=.7071, gain_db=0.):       # RBJ Audio-EQ-Cookbook biquads
    w = 2*np.pi*f0/SR; c, s = np.cos(w), np.sin(w); al = s/(2*q); A = 10**(gain_db/40)
    if kind == 'lp':   b, a = [(1-c)/2, 1-c, (1-c)/2], [1+al, -2*c, 1-al]
    elif kind == 'hp': b, a = [(1+c)/2, -(1+c), (1+c)/2], [1+al, -2*c, 1-al]
    elif kind == 'bp': b, a = [al, 0., -al], [1+al, -2*c, 1-al]
    elif kind == 'hshelf':
        sq = 2*np.sqrt(A)*al
        b = [A*((A+1)+(A-1)*c+sq), -2*A*((A-1)+(A+1)*c), A*((A+1)+(A-1)*c-sq)]
        a = [(A+1)-(A-1)*c+sq, 2*((A-1)-(A+1)*c), (A+1)-(A-1)*c-sq]
    b, a = np.asarray(b), np.asarray(a); return b/a[0], a/a[0]
filt = lambda x, ba: lfilter(ba[0], ba[1], x, axis=-1)
def filt_loop(x, ba):                         # seamless: run 2 periods, keep the 2nd
    n = x.shape[-1]; return filt(np.concatenate([x, x], -1), ba)[..., n:]
def noise_color(n, rng, alpha=1.):            # 1/f^alpha by FFT shaping -> periodic, loops seamlessly
    X = np.fft.rfft(rng.standard_normal(n)); f = np.fft.rfftfreq(n, 1/SR); f[0] = f[1]
    x = np.fft.irfft(X/f**(alpha/2), n); return x/np.abs(x).max()
def mod_filter(x, kind, fc, q=.7071, block=225):   # 44100 = 225*196 -> whole-second loops stay periodic
    out, zi = np.empty_like(x), np.zeros(x.shape[:-1]+(2,))
    for i in range(0, x.shape[-1], block):
        b, a = rbj(kind, float(fc[i]), q)
        out[..., i:i+block], zi = lfilter(b, a, x[..., i:i+block], axis=-1, zi=zi)
    return out
```

**Seamless loops:**
- Use FFT-shaped (periodic) noise.
- Give each LFO an integer number of cycles per loop.
- Run LTI filters over 2 periods.
- Add events with wrap-around (`scatter`).

A 3-period render gave **max |P3 − P2| = 0.0** with block 225. Block 256 left 0.0027, about 17 % of RMS [V, run].

### 4.2 (a) R-A1 e-piano (2-op FM) · R-A2 marimba (modal)

```python
def epiano(f, dur=3.):                         # Chowning FM, C:M = 1:1 -> harmonic; index decays
    t = tt(dur); I = 2.0*np.exp(-t/.25) + .3
    y = np.sin(2*np.pi*f*t + I*np.sin(2*np.pi*f*t)) + .08*np.exp(-t/.03)*np.sin(2*np.pi*7*f*t)
    return y*env_ad(len(t), 3, 1.1*(220/f)**.6)            # higher notes decay faster
def marimba(f, dur=1.6, seed=0):                          # bar tuned ~1:4:10 (Rossing)
    rng = np.random.default_rng(seed)
    t = tt(dur); y = sum(a*np.sin(2*np.pi*r*f*t)*np.exp(-t/(tau*(330/f)**.5))
                         for r, a, tau in [(1,1,.5), (4,.25,.1), (10,.06,.03)] if r*f < 9000)
    click = filt(rng.standard_normal(len(t))*np.exp(-t/.002), rbj('lp', 2500))
    return (y + .05*click)*env_ad(len(t), 1.5, 1e9)
```

### 4.3 (b) R-B pad: detuned PolyBLEP saws → 24 dB/oct LP, 0.07 Hz LFO

```python
def saw_blep(f, t, ph0=0.):
    dt = f/SR; p = (ph0 + f*t) % 1.; y = 2*p - 1
    m = p < dt; x = p[m]/dt; y[m] -= x+x-x*x-1
    m = p > 1-dt; x = (p[m]-1)/dt; y[m] -= x*x+x+x+1
    return y
def pad(freqs, dur=24., seed=1, fc=800., attack=4., release=6.):
    rng = np.random.default_rng(seed); t = tt(dur); y = np.zeros((2, len(t)))
    for f in freqs:
        for ch in (0, 1):
            for cents in (-10, -4, 3, 9):
                y[ch] += saw_blep(f*2**((cents + rng.uniform(-1, 1))/1200), t, rng.random())
    cut = fc*2**(.5*np.sin(2*np.pi*.07*t))
    y = mod_filter(mod_filter(y, 'lp', cut, .6), 'lp', 1.5*cut, .6)
    e = np.minimum(1, t/attack)**2*np.clip((dur - t)/release, 0, 1)**2
    return y*e/np.abs(y).max()
```

For `AudioStreamInteractive` clips, render **exactly periodic** loops of a **whole number of bars**: 8 bars at 66 BPM = 29.09 s.
- Why whole bars: `TRANSITION_FROM_TIME_NEXT_BAR` computes `fmod(clip_position, bar_sec)` (`audio_stream_interactive.cpp:695-699`). A 32 s clip (8.8 bars) would shift the bar grid by 2.9 s at every loop point.
- Round the sample count to whole 225-sample `mod_filter` blocks, then set `dur = n/SR`.
- Round oscillator frequencies to multiples of `1/dur` (error ≤ 0.017 Hz).
- Use an integer number of LFO cycles.
- Render 2 periods and keep the second.
- Import with `bpm=66`, `bar_beats=4`, `loop=true`.

A 3-period check gave max |P3 − P2| = 4.6e-11 at 32 s. The fact-checker re-ran the 8-bar version and got 2.0e-10 [V, run]. Without block alignment the error was 8e-4 of peak.

```python
def pad_loop(freqs, dur=8*4*60/66, seed=1, fc=800., lfo_cycles=2):   # 8 bars @ 66 BPM
    rng = np.random.default_rng(seed); n = int(round(dur*SR/225))*225; dur = n/SR   # whole filter blocks
    t = np.arange(2*n)/SR; y = np.zeros((2, 2*n))
    for f in freqs:
        for ch in (0, 1):
            for cents in (-10, -4, 3, 9):
                fq = round(f*2**((cents + rng.uniform(-1, 1))/1200)*dur)/dur   # k/dur Hz
                y[ch] += saw_blep(fq, t, rng.random())
    cut = fc*2**(.5*np.sin(2*np.pi*lfo_cycles*t/dur))
    y = mod_filter(mod_filter(y, 'lp', cut, .6), 'lp', 1.5*cut, .6)[:, n:]
    return y/np.abs(y).max()
```

### 4.4 (c) R-C1 wind · R-C2 rain · R-C3 stream · R-C4 bubbles

```python
MINNAERT = np.sqrt(3*1.4*101325/998.)/(2*np.pi)    # f*R = 3.29 m/s -> R = 1 mm rings at 3.29 kHz
def bubble(f0, tau, sigma=.1):                     # damped sine, pitch rising while it rings
    t = np.arange(int(SR*6*tau))/SR; f = f0*(1 + sigma*t/tau)   # (van den Doel 2005 model shape)
    return np.sin(2*np.pi*np.cumsum(f)/SR)*np.exp(-t/tau)*(1 - np.exp(-t/.0004))
def scatter(out, g, pos, gain, pan):               # wrap-around add keeps the loop seamless
    idx = (pos + np.arange(len(g))) % out.shape[1]
    out[0, idx] += g*gain*np.cos(pan*np.pi/2); out[1, idx] += g*gain*np.sin(pan*np.pi/2)
def wind(dur=60., seed=2):
    rng = np.random.default_rng(seed); n = int(dur*SR); t = np.arange(n)/SR
    lfo = lambda k, ph: np.sin(2*np.pi*k*t/dur + ph)               # integer cycles per loop
    y = np.stack([noise_color(n, rng, 1.5) for _ in (0, 1)])
    fc = 420*2**(.9*(.6*lfo(5, 2.1) + .4*lfo(11, .4)))             # 240-780 Hz
    y = mod_filter(np.concatenate([y, y], -1), 'bp', np.concatenate([fc, fc]), 1.4)[:, n:]
    g = .55 + .30*lfo(3, 0) + .15*lfo(8, 1.3)                      # gusts
    return y*g/np.abs(y*g).max()
def rain(dur=60., rate=30., seed=3):
    rng = np.random.default_rng(seed); n = int(dur*SR)
    bed = np.stack([noise_color(n, rng, 1.) for _ in (0, 1)])
    out = .35*filt_loop(filt_loop(bed, rbj('hp', 250)), rbj('lp', 4500))/np.abs(bed).max()
    for t0 in np.cumsum(rng.exponential(1/rate, int(rate*dur*1.2))):   # Poisson drops
        if t0 >= dur: break
        r = rng.uniform(1.4e-3, 4e-3)                                  # radius -> 0.8-2.3 kHz
        scatter(out, bubble(MINNAERT/r, rng.uniform(.005, .018)), int(t0*SR),
                .25*min(rng.lognormal(0, .5), 1.6), rng.uniform(.15, .85))   # cap crest
    out = filt_loop(out, rbj('lp', 5000)); return out/np.abs(out).max()
# stream(): same, rate 220/s, r 1.2-4 mm, tau 3-9 ms, sigma .25, gain .06, BP-900 Hz noise bed, LP 4 kHz
```

- Minnaert: f·R = 3.29 m/s, computed from γ = 1.4, P₀ = 101.3 kPa, ρ = 998 kg/m³ [V].
- Real rain's tiny entrained bubbles give underwater rain noise a peak near 13–25 kHz (Medwin et al. 1992, "The anatomy of underwater rain noise", *JASA* 92(3):1613 [W; citation added by the fact-checker from memory, not re-fetched]). That is too sharp for us, so we use "drops on a pond" radii of 1.4–4 mm [J].
- **Cap the drop gains.** Without the cap, rare loud drops hit the −1.5 dBTP ceiling and leave the bed 2–4.6 LU short of −18. With the 1.6 cap, 5 of 6 seed/length cases reached −18.0 exactly [V, run].

### 4.5 (d) R-D birdsong · (e) R-E plip

```python
def chirp(f_hi=3400., f_lo=2300., dur=.08, vib_hz=30., vib=80.):    # FM sweep + vibrato
    t = tt(dur); f = f_lo + (f_hi-f_lo)*np.exp(-t/(.3*dur)) + vib*np.sin(2*np.pi*vib_hz*t)
    ph = 2*np.pi*np.cumsum(f)/SR
    return np.sin(np.pi*t/dur)**2*(np.sin(ph) + .12*np.sin(2*ph))
def bird_phrase(rng):                     # 3-6 chirps, each ~3 % lower, gaps 40-120 ms
    base, parts = rng.uniform(2000, 3000), []
    for k in range(rng.integers(3, 7)):
        parts += [chirp(1.45*base*.97**k, base*.97**k, rng.uniform(.05, .11)),
                  np.zeros(int(SR*rng.uniform(.04, .12)))]
    return filt(np.concatenate(parts), rbj('lp', 7000))
def plip(f=880., tau=.05, rise=.3):       # "bloop" = bubble with strong upward glide + sub-octave body
    b = bubble(f, tau, rise); t = np.arange(len(b))/SR
    return (b + .35*np.sin(np.pi*f*t)*np.exp(-t/(.6*tau)))*env_ad(len(b), 2, 1e9)
```

### 4.6 (f) R-F chime: free–free bar modes with slow beating

```python
FREE_BAR = [1., 2.7565, 5.4039, 8.9330]   # (x_k/x_1)^2, roots of cos x cosh x = 1 (computed)
def chime(f, dur=4., seed=0, t60=3.):
    rng = np.random.default_rng(seed); t = tt(dur); y = np.zeros_like(t)
    for k, r in enumerate(FREE_BAR):
        if r*f > 10000: break
        for d in (-.5, .5):                                       # detuned pair: 0.4-1.4 Hz beats
            y += .55**k*np.sin(2*np.pi*(r*f + d*rng.uniform(.4, 1.4))*t + 6.283*rng.random()) \
                 * np.exp(-6.91*t/(t60/(1 + 1.2*k)))              # higher modes die sooner
    return y*env_ad(len(t), 1., 1e9)
```

- The mode ratios are 1, 2.7565, 5.4039 and 8.9330, re-derived numerically [V]. They are the modes of a free–free Euler–Bernoulli beam: chime tubes, glockenspiel bars (Rossing) [W].
- Glass variant: t60 = 1.2, drop k = 0.

### 4.7 (g) Reverb: exact Freeverb (block-vectorised) or synthetic IR

```python
COMBS, APS = [1116,1188,1277,1356,1422,1491,1557,1617], [556,441,341,225]  # Jezar Freeverb @44.1k
def _comb(x, N, fb, d):                   # LBCF; feedback delay N >= block, so blocks are independent
    v, y, zi = np.zeros(len(x)), np.zeros(len(x)), np.zeros(1)
    for i in range(0, len(x), N):
        j = min(i+N, len(x)); y[i:j] = v[i-N:j-N] if i >= N else 0.
        lp, zi = lfilter([1-d], [1, -d], y[i:j], zi=zi); v[i:j] = x[i:j] + fb*lp
    return y
def _allpass(x, N, g=.5):
    w, out = np.zeros(len(x)), np.zeros(len(x))
    for i in range(0, len(x), N):
        j = min(i+N, len(x)); wp = w[i-N:j-N] if i >= N else np.zeros(j-i)
        w[i:j] = x[i:j] + g*wp; out[i:j] = wp - x[i:j]
    return out
def freeverb(x, room=.8, damp=.5, spread=23):     # returns wet stereo
    m = np.atleast_2d(x).mean(0)*.015; fb, d = .7 + .28*room, .4*damp; out = []
    for s in (0, spread):
        y = sum(_comb(m, N+s, fb, d) for N in COMBS)
        for N in APS: y = _allpass(y, N+s)
        out.append(y)
    return np.stack(out)
def synth_ir(rt60=2., dur=2.5, predelay_ms=12, seed=7, dark=.45):   # highs decay 1/dark x faster
    rng = np.random.default_rng(seed); t = tt(dur); e = lambda T: np.exp(-6.91*t/T); ir = []
    for _ in (0, 1):
        z = rng.standard_normal(len(t))
        ir.append(filt(z, rbj('lp', 3000))*e(rt60) + filt(z, rbj('hp', 3000))*e(rt60*dark))
    ir = np.stack(ir)*(1 - np.exp(-t/.004)); ir /= np.sqrt((ir**2).sum()/2)
    return np.concatenate([np.zeros((2, int(SR*predelay_ms/1000))), ir], 1)
# wet = np.stack([fftconvolve(x, ir[c]) for c in (0, 1)])
```

- Cost: Freeverb took 0.05 s per 3.3 s of audio; convolution took 0.026 s [V, run]. Schroeder 1962 / Jezar, per J.O. Smith (PASP).
- Bake beds and pads with `synth_ir(rt60=2–2.5, dark=0.45)` at 20–30 % wet.

### 4.8 (h) Loudness without pyloudnorm (BS.1770 / R128)

```python
def k_weight(x):  # +4 dB shelf @1.5 kHz, Q .7071 + 2nd-order HP @38 Hz, Q .5 (pyloudnorm's parameters)
    return filt(filt(x, rbj('hshelf', 1500., .7071, 4.)), rbj('hp', 38., .5))
def lufs_integrated(x):                  # mono is measured as dual-mono (Godot copies mono to L+R)
    x = np.atleast_2d(x); x = np.vstack([x, x]) if x.shape[0] == 1 else x
    y = k_weight(x); blk, hop = int(.4*SR), int(.1*SR)
    if y.shape[1] < blk: y = np.pad(y, ((0, 0), (0, blk - y.shape[1])))   # SFX -> 400 ms momentary
    z = np.array([np.mean(y[:, i:i+blk]**2, 1).sum() for i in range(0, y.shape[1]-blk+1, hop)])
    L = lambda p: -.691 + 10*np.log10(p + 1e-30)
    z = z[L(z) > -70.]; z = z[L(z) > L(z.mean()) - 10.]      # absolute, then relative gate
    return L(z.mean())
def lufs_momentary_max(x):              # SFX metric (§0.5 "LUFS-M"): loudest 400 ms window, 10 ms hop
    x = np.atleast_2d(x); x = np.vstack([x, x]) if x.shape[0] == 1 else x
    y = k_weight(x); blk, hop = int(.4*SR), int(.01*SR)
    if y.shape[1] < blk: y = np.pad(y, ((0, 0), (0, blk - y.shape[1])))
    z = np.array([np.mean(y[:, i:i+blk]**2, 1).sum() for i in range(0, y.shape[1]-blk+1, hop)])
    return -.691 + 10*np.log10(z.max() + 1e-30)
true_peak = lambda x: 20*np.log10(np.abs(resample_poly(np.atleast_2d(x), 4, 1, axis=-1)).max())
def normalize(x, target=-18., ceiling=-1.5):
    y = x
    for _ in range(2):                   # 2 passes: gain moves decaying tails across the -70 gate
        y = y*10**((target - lufs_integrated(y))/20)
    tp = true_peak(y)
    return y*10**((ceiling - tp)/20) if tp > ceiling else y
```

**SFX use the momentary metric, not `lufs_integrated` (fact-check fix).** For SFX longer than 400 ms the two differ a lot (fact-checker run):

| SFX | Integrated | Momentary max |
|---|---|---|
| marimba, 1.6 s | −9.4 | −4.0 |
| e-piano, 3 s | −9.6 | −4.5 |
| chime, 4 s | −2.2 | +3.1 |

Normalizing SFX with `normalize()` would leave them about 5 LU louder than the §0.5 targets. Scale SFX by `target_M − lufs_momentary_max(x)`, then apply the −6 dBFS sample-peak cap. Below 400 ms the two metrics are identical (plip: −12.64 both).

**Validation [V, run]:**
- On files ≥ 1.6 s, this matches **pyloudnorm within ±0.01 LU** and ffmpeg within ±0.1 LU. The fact-checker re-ran this against pyloudnorm 0.2.0: 10 s stereo noise and 3 s dual-mono e-piano both agreed within 1e-5 LU.
- ffmpeg reads mono **3.0 LU low** unless `-af ebur128=dualmono=true` is set.
- A pad and a rain bed, each at −18 and mixed at −3 dB and −6 dB, measured **−19.9 LUFS-I with LRA 4.0**. Power summation predicts −19.3. **Always measure the real MovieWriter capture.**

### 4.9 Measured properties (normalized renders)

Centroid is magnitude-weighted (Σ|X|f / Σ|X|); band columns are energy fractions. The fact-checker re-ran the instrument rows: e-piano 839 Hz, marimba 808, plip 612, chime 2926. Those are within 5 % of the table, and the band fractions match.

| Recipe | Render | Centroid | 2–5 kHz | >10 kHz | 200–500 Hz |
|---|---|---|---|---|---|
| R-A1 e-piano F4 | 15 ms | 804 Hz | 0 % | 0 | 64 % |
| R-A2 marimba A4 | — | 805 Hz | 0 % | 0 | 99 % |
| R-B pad, 24 s | 1.7 s | 567 Hz | 0 % | 0 | 73 % |
| R-C1 wind, 60 s | 2.4 s | 1188 Hz | 0.5 % | 0 | 55 % |
| R-C2 rain, 60 s | 1.9 s | 1995 Hz | 15.3 % | 0.02 % | 8 % |
| R-C3 stream, 60 s | 2.6 s | 1827 Hz | 17.9 % | 0 | 8 % |
| R-D bird phrase | — | 3278 Hz | 99 % → **≥ 15 dB under bed** | 0 | 0 |
| R-E plip C5 | — | 607 Hz | 0 % | 0 | 9 % |
| R-F chime C6 | — | 2926 Hz | 13 % | 0 | 0 |

Godot 4.7.2 loaded the 60 s OGG at runtime with `get_length()` = 60.0. Set `loop=true` in `.import` [V].

---

## 5. Haptics

### 5.1 Guidance [V]

- **Apple HIG, "Playing haptics"** (re-fetched by the fact-checker):
  - Be consistent, with a clear cause and effect.
  - **Complement** other feedback. Match a haptic's intensity and sharpness to the animation it accompanies, and sync it with sound.
  - **Avoid overuse.** Prefer short haptics for discrete events.
  - **Make haptics optional.**
  - Transient = tap; continuous = sustained. Sharpness runs from "soft, rounded, organic" to "crisp, mechanical".
- **Android principles:**
  - Prefer **clear** over **buzzy**: "Given the choice of buzzy haptics or no haptics for touch feedback, choose no haptics."
  - A keyclick lasts **10–20 ms**, and the actuator rings for another 20–50 ms.
  - Avoid `createOneShot`.
  - Co-design haptics with audio and visuals.
- **Android custom effects:**
  - Without amplitude control, non-zero amplitudes round up to 100 %.
  - Steps should differ by **≥ 1.4×** (0.5 / 0.7 / 1.0), with **≤ 3 levels**.
  - Gaps of 5–10 ms are imperceptible; use ≥ 50 ms.
  - These two rules are stated for *composition primitives*. Applying them to iOS amplitudes and to `CLOCK_TICK` pairs is our extrapolation [J].
- **Android `performHapticFeedback`:** needs no VIBRATE permission and honours the system touch-feedback setting.

### 5.2 What Godot 4.7.2 does

- **Signature:** `Input.vibrate_handheld(duration_ms: int = 500, amplitude: float = -1.0)` (`core/input/input.cpp:161`), on Android, iOS and Web [V].
- **Android** (`platform/android/java_godot_wrapper.cpp:469-481`, `GodotNativeBridge.kt:179-200`) [V]:
  - `CLAMP(int(amp*255), 1, 255)` feeds `VibrationEffect.createOneShot`, and VIBRATE permission is required.
  - **`amplitude=0.0` still vibrates.**
  - This is the discouraged API, so use `performHapticFeedback` instead (report 02 §2.3).
- **iOS** (`drivers/apple_embedded/os_apple_embedded.mm:741-751`, `apple_embedded.mm:73-117`) [V]:
  - Each call builds a Core Haptics **continuous** event with only `HapticIntensity`: no transient, no sharpness.
  - When Core Haptics is unsupported, it falls back to `kSystemSoundID_Vibrate`, which takes no duration or amplitude. That happens below iOS 13, and on hardware where `capabilitiesForHardware.supportsHaptics` is false, e.g. iPads. Expect no feedback there.
  - The engine is created with auto-shutdown (`apple_embedded.mm:63`), and the engine code never starts it.
  - Scripts *can* pre-warm it on resume, to cut first-tap latency: `Engine.get_singleton("AppleEmbedded").start_haptic_engine()`. The singleton is registered at `os_apple_embedded.mm:189` and the method is bound at `apple_embedded.mm:44`. It is undocumented and untested on a device [V source / J].
  - `NSLog("Could not vibrate…")` runs on **every call** (log spam), so rate-limit.
  - 10–25 ms events approximate transients [J].
  - Whether the "System Haptics" setting mutes it is **unverified**, which makes our toggle mandatory.
- **Web:** `navigator.vibrate(ms)` ignores amplitude and is often unsupported [V]. Ship none.

### 5.3 Mapping & wrapper (ran headless)

| Kind | Used by | Android | iOS (ms, amp); Subtle ×0.7 |
|---|---|---|---|
| TICK | tap (Full only), place, bud | `CLOCK_TICK` | 12, 0.30 |
| DOUBLE | collect | `CLOCK_TICK` ×2, 70 ms apart | 12, 0.42 then ×0.7 |
| MEDIUM | milestone, welcome back | `CONFIRM` (API 30+, else `CLOCK_TICK`) | 24, 0.60 |

iOS amplitude steps are ≈ 1.4× apart (Android's perceptibility rule).

```gdscript
extends Node  # autoload "Haptics"
enum Kind { TICK, DOUBLE, MEDIUM }
enum Mode { OFF, SUBTLE, FULL }
var mode := Mode.SUBTLE
const IOS := { Kind.TICK: [12, 0.30], Kind.DOUBLE: [12, 0.42], Kind.MEDIUM: [24, 0.60] }
var _last := -1000
func play(kind: Kind) -> void:
	if mode == Mode.OFF or (mode == Mode.SUBTLE and kind == Kind.TICK): return
	var now := Time.get_ticks_msec()
	if now - _last < 60: return
	_last = now
	match OS.get_name():
		"Android": _android(kind)          # performHapticFeedback via JavaClassWrapper (report 02 §2.3)
		"iOS":
			var amp: float = IOS[kind][1] * (0.7 if mode == Mode.SUBTLE else 1.0)
			Input.vibrate_handheld(IOS[kind][0], amp)
			if kind == Kind.DOUBLE:
				get_tree().create_timer(0.07).timeout.connect(Input.vibrate_handheld.bind(IOS[kind][0], amp * 0.7))
func _android(_kind: Kind) -> void: pass
```

Fire the haptic in the same frame as the visual squash. Audio can lag ≈ 50 ms on Android (§2.5); verify the feel on a device.

---

## 6. Open device tests

1. Tap-to-sound latency on a low-end Android device, against P12 ≤ 100 ms.
2. Core Haptics with "System Haptics" off. Feel of 12 ms events on iPhone SE versus Pro.
3. Vorbis decode CPU per stream on ARMv8. This decides between A/B players and `AudioStreamSynchronized` for L0.
4. Listening panel (n ≥ 5): "calm / annoying after 30 min" for rain and stream. Tune the 2–5 kHz gate.

## 7. Self-verification log

- **Engine source:** every §2.3, §2.5 and §5.2 claim at its path:line in the 4.7.2 tree.
- **Headless 4.7.2 runs:**
  - OGG and WAV runtime load.
  - Randomizer: 1 st → `random_pitch` 1.0595.
  - Synchronized volume.
  - Interactive bar-quantized switch.
  - Polyphonic `play_stream` with a bus.
  - Effect defaults.
  - This report's bus builder, conductor and haptics code, run verbatim.
  - Reverb damping capture with `AudioEffectCapture`.
  - GDScript FM CPU benchmark.
- **DSP:** all §4 code was extracted from this file and executed. Loudness was triple-checked. Loop periodicity, Minnaert and free-bar constants were computed. Vorbis TP overshoot was measured.

## Sources

- **Nature sounds:**
  - Alvarsson 2010 [PMC2872309](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC2872309/)
  - Gould van Praag 2017 [PMC5366899](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5366899/)
  - Buxton 2021 [ScienceOpen](https://www.scienceopen.com/document?vid=05cc3c16-2aef-46e2-99ce-4b014fa8cf9c), [EurekAlert](https://www.eurekalert.org/news-releases/593536)
  - Fan & Baharum 2024 [PubMed](https://pubmed.ncbi.nlm.nih.gov/39285764/)
- **Music and the body:**
  - Bernardi 2006 [Heart 92(4):445–452](https://heart.bmj.com/content/92/4/445), [doi](https://doi.org/10.1136/hrt.2005.064600)
  - Koelsch & Jäncke 2015 [PDF](https://doc.rero.ch/record/298843/files/ehv430.pdf)
  - Husain 2002 [PDF](https://sites.utm.utoronto.ca/sites/sites.utm.utoronto.ca.glenn_website/files/download/Husain.pdf)
  - Gagnon & Peretz 2003 [doi](https://doi.org/10.1080/02699930302279)
  - de Witte 2020 [PubMed](https://pubmed.ncbi.nlm.nih.gov/31167611/)
- **Lo-fi and binaural beats:**
  - Dsouza 2024 [doi](https://doi.org/10.1080/02673843.2024.2388787)
  - Garcia-Argibay 2019 [PubMed](https://pubmed.ncbi.nlm.nih.gov/30073406/)
  - Ingendoh 2023 [PMC10198548](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10198548/)
- **Psychoacoustics:**
  - Kumar 2008 [record](https://iro.uiowa.edu/esploro/outputs/journalArticle/Mapping-unpleasantness-of-sounds-to-their/9984304036602771)
  - Plomp & Levelt 1965 [PDF](https://www.math.miami.edu/~armstrong/592sp15/Plomp_Levelt_1965.pdf)
- **Generative music:** Eno 1996 [In Motion](https://inmotionmagazine.com/eno1.html)
- **Loudness:**
  - [EBU R128](https://tech.ebu.ch/docs/r/r128s1.pdf)
  - [Sony ASWG interview](https://designingsound.org/2012/07/30/video-games-and-loudness-standards-interview-with-sonys-garry-taylor/)
  - [Mobile loudness](https://audiomediainternational.com/mobile-loudness-an-adaptive-approach/)
- **Sound-on rates:** [Appington](https://toucharcade.com/2013/11/05/73-of-mobile-gamers-play-with-the-sound-on/), [Tap Research](https://blog.tapresearch.com/how-sound-preferences-impact-player-engagement)
- **Speakers:** [IOA small-radiator paper](https://www.ioa.org.uk/system/files/proceedings/k_holland_p_newell_p_mapp_steady_state_and_transient_loudspeaker_frequency_responses.pdf)
- **Haptics:**
  - [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
  - [Android principles](https://developer.android.com/develop/ui/views/haptics/haptics-principles)
  - [custom effects](https://developer.android.com/develop/ui/views/haptics/custom-haptic-effects)
  - [haptic feedback](https://developer.android.com/develop/ui/views/haptics/haptic-feedback)
- **DSP:**
  - Chowning 1973 *JAES* 21(7)
  - van den Doel 2005, "Physically based models for liquid sounds", *ACM TAP* 2(4):534–546 (look it up in the ACM Digital Library; the earlier persianney.com PDF mirror could not be verified and was dropped)
  - [Freeverb (J.O. Smith)](https://ccrma.stanford.edu/~jos/pasp/Freeverb.html)
  - [RBJ cookbook](https://www.w3.org/TR/audio-eq-cookbook/)
  - ITU-R BS.1770
  - [pyloudnorm](https://pypi.org/project/pyloudnorm/)
  - AudioStreamGeneratorPlayback: `doc/classes/AudioStreamGeneratorPlayback.xml` in the 4.7.2 tree ([stable docs](https://docs.godotengine.org/en/stable/classes/class_audiostreamgeneratorplayback.html); the old link pointed at 4.2)
- **Physical acoustics:** Medwin et al. 1992, *JASA* 92(3):1613 (rain noise); Fastl & Zwicker 2007, *Psychoacoustics: Facts and Models*, 3rd ed., Springer

## Verification log

**Fact-check, 2026-10-20.** 81 claims checked: **60 OK · 16 FIXED · 5 FLAGGED**. A row that is OK on substance but had its link fixed (#59, #62) counts as FIXED.

**Method:**
- Engine claims were grepped in the 4.7.2-stable tree at `/home/user/godotengine/godot`. Paths below are relative to it.
- Behaviour was re-run headless on `bin/godot.linuxbsd.editor.x86_64`, using the scripts in `/tmp/claude-verify-audio/proj/`. DSP was re-run in `/tmp/claude-verify-audio/dsp/`. Both ran the code blocks *as edited here*.
- Android and Apple haptics pages were re-fetched.

**Limitation:** the WebSearch budget was exhausted, and NCBI, DOI resolvers, publisher sites, w3.org and ccrma were unreachable from the container. Paper rows marked "knowledge" are therefore checked against the reviewer's own knowledge, not re-fetched. Anything the reviewer could not vouch for is FLAGGED.

### Engine / API (4.7.2 source and headless runs)

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | Mono WAV is copied to L and R | OK | `scene/resources/audio_stream_wav.cpp:206-208` |
| 2 | `audio/driver/mix_rate` defaults to 44100 | OK | `servers/audio/audio_server.cpp:229`, `audio_server.h:170` |
| 3 | Android mixes at 44.1 kHz | OK (added) | `platform/android/audio_driver_opensl.cpp:303` |
| 4 | `ios/session_category` defaults to 0 (Ambient), which mixes with other audio | OK | `core/config/project_settings.cpp:1760-1761`; `doc/classes/ProjectSettings.xml:489-495`; `drivers/apple_embedded/app_delegate_service.mm:100-125` |
| 5 | WAV import defaults to `compress/mode=2` (QOA) | OK | `editor/import/resource_importer_wav.cpp:89` |
| 6 | OGG import has `loop`/`bpm`/`beat_count`/`bar_beats` | OK | `modules/vorbis/resource_importer_ogg_vorbis.cpp:75-81` |
| 7 | StereoEnhance `pan_pullout=0` gives mono | OK | `servers/audio/effects/audio_effect_stereo_enhance.cpp:37-49` |
| 8 | HardLimiter defaults to −0.3 dB | OK | `doc/classes/AudioEffectHardLimiter.xml:16` |
| 8a | Ceiling −1.0 dB is enough for −1 dBTP with a sample-peak limiter | **FIXED** → −1.5 dB [J] | Same file: the doc says −0.3 exists *for* inter-sample peaks |
| 9 | `AudioEffectLimiter` is deprecated | OK | `doc/classes/AudioEffectLimiter.xml:2` |
| 10 | Music LPF `resonance = 0.0` is harmless | **FIXED**: it attenuates ≈ −40 dB | `servers/audio/audio_filter_sw.cpp:68-71` (Q ≤ 0 → 0.0001); headless capture of a 1 kHz sine read −49.45 dB at resonance 0 and −9.03 dB at 0.5; the edited bus builder passes −9.03 dB |
| 11 | Reverb member names and defaults (150 ms, 0.4, damping 0.5, room 0.8) | OK | `doc/classes/AudioEffectReverb.xml:17-38`; headless print |
| 12 | Damping maps to an in-loop LP at 2.5–10 kHz; higher is brighter | OK | `servers/audio/effects/reverb_filter.cpp:290-293`, `:114` |
| 13 | Predelay is a feedback echo | OK (line range corrected) | `reverb_filter.cpp:61-85` |
| 14 | 8 combs with feedback 0.7 + 0.28·room; 4 all-passes | OK; all-pass g = 0.7 added | `reverb_filter.cpp:122`, `:278-289`, `reverb_filter.h:42-43` |
| 15 | `hipass` ≈ hipass × 6 kHz one-pole HP | OK (added) | `reverb_filter.cpp:91` |
| 16 | Interactive enums and methods (`CLIP_ANY`, `NEXT_BAR`, `TO_TIME_START`, `FADE_CROSS`, `switch_to_clip_by_name`, `get_current_clip_index`) | OK | `modules/interactive_music/doc_classes/AudioStreamInteractive.xml:184-229`, `AudioStreamPlaybackInteractive.xml:12-31` |
| 17 | With `bpm=0`, `fade_beats` means seconds | OK | `audio_stream_interactive.cpp:723,735` |
| 18 | Bar quantization uses the source clip's bpm/bar_beats and its loop position | OK, which exposed #43 | `audio_stream_interactive.cpp:684-699` |
| 19 | Synchronized: ≤ 32 streams, 128-frame blocks, volume stored on the resource, muted streams still mixed | OK | `audio_stream_synchronized.h:45,85`; `.cpp:226-245` |
| 20 | Playlist defaults 0.3/true/false; no index API | OK | `AudioStreamPlaylist.xml:36-45`; `AudioStreamPlaybackPlaylist.xml` (no methods) |
| 21 | Randomizer pitch is log-uniform; `random_pitch_semitones` exists; 1 st → 1.0595 | OK | `servers/audio/audio_stream.cpp:798-801`; `AudioStreamRandomizer.xml:72-80`; headless run |
| 22 | `play_stream(stream, from_offset, volume_db, pitch_scale, playback_type, bus)`; polyphony 32 | OK | `AudioStreamPlaybackPolyphonic.xml:19-25`; `AudioStreamPolyphonic.xml:14` |
| 23 | Bus sleep: −60 dB / 2.0 s | OK | `audio_server.cpp:1527-1528` |
| 24 | Web defaults to Sample playback; no effects; only WAV/OGG/MP3 can be samples | OK | `project_settings.cpp:1755`; `AudioServer.xml:427-431`; `scene/audio/audio_stream_player_internal.cpp:157-173`; `can_be_sampled` in `audio_stream_wav.h:169`, `audio_stream_ogg_vorbis.h:175`, `audio_stream_mp3.h:143` |
| 25 | OpenSL uses 2 × 1024 frames; `output_latency` ignored on Android | OK | `audio_driver_opensl.cpp:102`, `.h:44`; `ProjectSettings.xml:467` |
| 26 | `vibrate_handheld(duration_ms=500, amplitude=-1.0)` | OK | `core/input/input.cpp:161`; `doc/classes/Input.xml:807-820` |
| 27 | Android: CLAMP(amp·255, 1, 255), `createOneShot`, VIBRATE permission; amp 0 still vibrates | OK | `platform/android/java_godot_wrapper.cpp:469-481`; `GodotNativeBridge.kt:179-200` |
| 28 | iOS: continuous event with intensity only; NSLog on every call; auto-shutdown | OK | `drivers/apple_embedded/apple_embedded.mm:63,73-121`; `os_apple_embedded.mm:741-751` |
| 29 | iOS fallback happens only "below iOS 13" | **FIXED**: also on hardware without haptics | `os_apple_embedded.mm:742-750`; `apple_embedded.mm:48-51` |
| 30 | Haptic engine is "never started explicitly" | **FIXED**: scripts can call `start_haptic_engine()` | `apple_embedded.mm:44,124`; `os_apple_embedded.mm:189` |
| 31 | Web vibrate ignores amplitude | OK | `platform/web/os_web.cpp:206-207`; `Input.xml:817-818` |
| 32 | The three GDScript blocks run on 4.7.2; `Input.vibrate_handheld.bind()` is a valid Callable | OK | Headless run of the edited blocks (`run_all.gd`, `bus_measure.gd`, `cb_test.gd`) |
| 33 | 14 notes over 2 octaves cover the conductor | **FIXED**: per-instrument ranges added | `play_note` only repitches upward; prototype set `gdtest/notes/ep_60…ep_83` misses the night e-piano and S05 |
| 80 | "No semitones or tritones, so any order is consonant" | **FIXED** (scope: within a set) | The G/F pad itself contains F–B |

### Tools and DSP (re-run)

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 34 | pyloudnorm 0.2.0: MIT, pure Python, depends on scipy and numpy | OK | `pypi.org/pypi/pyloudnorm/json`: py3-none-any wheel, uploaded 2026-01-04 |
| 35 | numpy 2.5.3, scipy 1.18.1 | OK | `/tmp/claude-research/venv` |
| 36 | Native `vorbis` encoder is experimental; `ebur128` has `dualmono` | OK | `ffmpeg -encoders` (`A..X.D vorbis`); `ffmpeg -h filter=ebur128` |
| 37 | Vorbis q4 runs 112–118 kb/s | **FIXED**: beds 108–118, pads ≈ 80 kb/s | ffprobe on `/tmp/claude-research/audio/out/*.ogg` |
| 38 | Vorbis true-peak overshoot ≤ +0.2 dB | OK | Re-measured −0.3…+0.1 dB on 4 files (`ebur128=peak=true`, 0.1 dB resolution) |
| 39 | BS.1770 code matches pyloudnorm | OK | Δ < 1e-5 LU on 10 s stereo noise and 3 s dual-mono e-piano |
| 40 | SFX "LUFS-M" targets met by `lufs_integrated`/`normalize` | **FIXED**: added `lufs_momentary_max`; off by ≈ 5 LU for > 0.4 s SFX | §4.8 table, re-run |
| 41 | Free–free bar ratios 1 / 2.7565 / 5.4039 / 8.9330 | OK | brentq roots of cos x·cosh x = 1 |
| 42 | Minnaert f·R = 3.29 m/s | OK | Recomputed 3.2865 |
| 43 | 32 s pad loops fit the 66 BPM bar quantization | **FIXED**: 8 bars = 29.09 s, block-aligned | Re-run: P3 − P2 = 2.0e-10; 8e-4 without block alignment |
| 44 | Centroid table | OK (definition stated) | Magnitude-weighted re-run within 5 % |
| 45 | RBJ LP/HP/BP/high-shelf coefficients | OK (knowledge) | W3C Audio EQ Cookbook formulas; LP coefficients re-derived in `/tmp/claude-verify-audio/lpf.py` |
| 46 | Freeverb constants (comb/all-pass lengths, 0.28/0.7, 0.4, 0.015, spread 23) | OK (knowledge) | Jezar's Freeverb source as described in J.O. Smith's PASP |
| 47 | PolyBLEP residual | OK | Standard 2-point polyBLEP |
| 48 | Power sum predicts −19.3 LUFS | OK | 10·log10(10^−2.1 + 10^−2.4) = −19.24 |

### Haptics guidance (re-fetched pages)

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 49 | Apple HIG principles; "soft, rounded, or organic … crisp, precise, or mechanical" | OK (wording tightened) | `developer.apple.com/tutorials/data/design/human-interface-guidelines/playing-haptics.json` |
| 50 | "Given the choice of buzzy haptics or no haptics…, choose no haptics" | OK | developer.android.com …/haptics-principles |
| 51 | Keyclick 10–20 ms, then 20–50 ms of ring; avoid `createOneShot` | OK | Same page |
| 52 | Amplitude rounds to 100 % without control; ≥ 1.4× steps, ≤ 3 levels; 5–10 ms gaps undetectable, ≥ 50 ms detectable | OK (scope note added: composition primitives) | …/custom-haptic-effects |
| 53 | `performHapticFeedback` needs no VIBRATE permission and honours `HAPTIC_FEEDBACK_ENABLED` | OK | …/haptic-feedback |
| 54 | `CONFIRM` requires API 30 | OK (knowledge) | Android API reference, HapticFeedbackConstants |

### Literature and URLs (not re-fetched; see Limitation)

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 55 | Alvarsson 2010, IJERPH 7:1036 (n = 40; SCL; HF-HRV null) | OK (knowledge) | — |
| 56 | Gould van Praag 2017, Sci Rep 7:45273 (outward attention; baseline-dependent autonomic effects) | OK (knowledge; the exact HF-HRV metric is unconfirmed) | — |
| 57 | Buxton 2021, PNAS: bibliographic data and qualitative water/birdsong result | OK; **g values and CIs FLAGGED** | — |
| 58 | Fan & Baharum 2024, Stress: p-values | **FLAGGED** | — |
| 59 | Bernardi 2006, Heart 92:445 (n = 24, pause below baseline) | OK; **URL FIXED** (/433 → /445) | — |
| 60 | Koelsch & Jäncke 2015, EHJ 36:3043 (no evidence for HR–beat entrainment) | OK (knowledge) | — |
| 61 | Husain 2002, Music Percept 20:151 | OK | — |
| 62 | Gagnon & Peretz 2003, Cogn Emot 17:25 | OK; **link FIXED** (dead informahealthcare host → doi.org) | — |
| 63 | de Witte 2020, HPR 14:294 (104 RCTs; d = .380 / .545) | OK (knowledge) | — |
| 64 | Dsouza 2024 lo-fi pilot | **FLAGGED** (unconfirmed) | — |
| 65 | Garcia-Argibay 2019, Psychol Res 83:357 (22 studies, g = 0.45) | OK (knowledge) | — |
| 66 | Ingendoh 2023, PLOS ONE (5 support / 8 contradict / 1 mixed of 14) | OK (knowledge) | — |
| 67 | Kumar 2008, JASA 124:3810 (2.5–5.5 kHz, 1–16 Hz) | OK (knowledge) | — |
| 68 | Plomp & Levelt: "roughness peaks within one critical band" | **FIXED**: peak at ≈ ¼ CB, gone beyond ≈ 1 CB | — |
| 69 | Fastl & Zwicker "ch. 16" | **FIXED** → ch. 9 (sensory pleasantness) and ch. 11 (roughness), 3rd ed. | Reviewer's recollection of the TOC |
| 70 | Sony ASWG: −23 home, −18 ± 2 portable | OK (knowledge) | — |
| 71 | EBU R128 −1 dBTP; BS.1770 gating at 400 ms / −70 / −10 | OK | Code re-run matches pyloudnorm |
| 72 | Eno loops 23½ / 25⅞ / 29 15⁄16 s and the quote | OK (knowledge) | — |
| 73 | Appington 73 % "≥ 10 % volume"; Tap Research 8 % | **FLAGGED** (contradictory vendor stats) | — |
| 74 | Rain "≈ 14 kHz" had no source | **FIXED**: Medwin et al. 1992 added, marked not re-fetched | — |
| 75 | van den Doel PDF mirror on persianney.com | **FIXED** (unverifiable mirror dropped) | — |
| 76 | Godot docs link pointed at 4.2 | **FIXED** (engine XML path + stable link) | — |
| 77 | Marimba tuned ≈ 1:4:10 (Rossing) | OK (knowledge) | — |
| 78 | Chowning 1973, JAES 21(7) | OK | — |
| 79 | IOA "small-radiator" paper supports the phone-bass claim | **FLAGGED** (its title is about steady-state vs transient loudspeaker response; relevance unconfirmed) | — |
