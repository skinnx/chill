"""Conductor and mix tables: the single source the AudioDirector reads (via audio/manifest.json)
and the offline mix simulator (mixsim.py) executes. Change numbers here, re-run synth.py.

Binding: 06 §0.2 bus graph (C15), §0.3 music system, §0.4 time-of-day profiles with the GDD §6.1
phase boundaries (world.json supersedes 06's 05/09/17/21 table), §0.5 SFX list, §0.6 + D11 haptics.
"""
from __future__ import annotations

# ----------------------------------------------------------------------------- buses (06 §0.2)
BUSES = [
	{"name": "Master", "volume_db": 0.0, "send": "", "effects": [
		{"class": "AudioEffectStereoEnhance", "enabled": False, "props": {"pan_pullout": 0.0},
			"role": "mono_toggle"},
		{"class": "AudioEffectHardLimiter", "enabled": True, "props": {"ceiling_db": -1.5},
			"role": "safety_limiter"},
	]},
	{"name": "Music", "volume_db": -3.0, "send": "Master", "effects": [
		{"class": "AudioEffectLowPassFilter", "enabled": True,
			"props": {"cutoff_hz": 20000.0, "resonance": 0.5}, "role": "tone_duck"},
	]},
	{"name": "Ambience", "volume_db": -6.0, "send": "Master", "effects": []},
	{"name": "SFX", "volume_db": 0.0, "send": "Master", "effects": [
		{"class": "AudioEffectReverb", "enabled": True, "role": "room",
			"props": {"room_size": 0.5, "damping": 0.25, "spread": 0.8, "hipass": 0.15,
				"predelay_msec": 20.0, "predelay_feedback": 0.0, "dry": 1.0, "wet": 0.15}},
	]},
	{"name": "UI", "volume_db": -3.0, "send": "Master", "effects": []},
]
BUS_GAIN = {b["name"]: b["volume_db"] for b in BUSES}

# ----------------------------------------------------------------------------- music flow (06 §0.3)
MUSIC_FLOW = {
	"chord_hold_bars": [6, 10],          # 8 +- 2 bars, uniform integer, no immediate repeat
	"crossfade_beats": 6.0,              # AudioStreamInteractive FADE_CROSS (linear), NEXT_BAR -> START
	"min_onset_gap_s": 4.0,              # between motif onsets across all voices
	"motif_ioi_s": [0.4286, 0.6429, 0.8571],   # eighth, dotted eighth, quarter at 70 BPM
	"motif_ioi_weights": [0.4, 0.4, 0.2],
	"motif_steps": [1, 1, 2, -1, -2],    # pentatonic steps between motif notes (uniform pick)
	"onset_jitter_s": 0.02,              # +- humanised timing
	"velocity_db": [-3.0, 0.0],          # uniform per note
	"base_spread": 3,                    # motif start = snap(base + randi(-3, 3))
	"rest_every_s": [240.0, 420.0],      # every 4-7 min ...
	"rest_len_s": [45.0, 90.0],          # ... a 45-90 s rest with ambience only
	"rest_fade_s": 8.0,
	"fatigue_after_s": 2700.0,           # 45 min of foreground play ...
	"fatigue_rest_s": 600.0,             # ... then 10 min of ambience only
	"boot_bed_fade_in_s": 4.0,           # GDD §3.4: bed fades in over 4 s
	"boot_pad_delay_s": 6.0,             # pad joins at 6 s
	"boot_pad_fade_in_s": 6.0,
	"profile_crossfade_s": 90.0,         # world.json audio_profile_crossfade_s
	"weather_crossfade_s": 30.0,         # world.json weather_crossfade_s
	"swell_db": 2.0, "swell_up_s": 2.0, "swell_down_s": 4.0,   # S09 pad swell
	"voice_hush_s": 4.0,                 # no motif onsets this long after S09/S10
}

# Eno voices (06 §0.3): incommensurate periods 23.5 / 25.875 / 29.9375 s
VOICES = {
	"ep": {"bank": "ep", "period_s": 23.5, "notes": 2},
	"mar": {"bank": "mar", "period_s": 25.875, "notes": 1},
	"chime": {"bank": "chime", "period_s": 29.9375, "notes": 3},
}

# ----------------------------------------------------------------------------- profiles (06 §0.4 + GDD §6)
# Bed / voice levels are AudioStreamPlayer volume_db (before the bus gain). `None` = silent.
PROFILES = {
	"dawn": {
		"beds": {"amb_breeze": -1.0, "amb_stream": 0.0, "amb_rain": None, "amb_crickets": None},
		"birds": {"interval_s": [6.0, 15.0], "volume_db": -1.0},
		"pad_set": "day", "pad_db": 1.5,
		"voices": {"chime": {"base": 79, "db": 1.5}, "ep": {"base": 72, "db": 3.0}},
		"density": 0.50, "music_lpf_hz": 20000.0,
	},
	"day": {
		"beds": {"amb_breeze": -1.0, "amb_stream": 1.0, "amb_rain": None, "amb_crickets": None},
		"birds": {"interval_s": [15.0, 40.0], "volume_db": -1.0},
		"pad_set": "day", "pad_db": 1.0,
		"voices": {"mar": {"base": 65, "db": 2.5}, "ep": {"base": 72, "db": 3.0}},
		"density": 0.55, "music_lpf_hz": 20000.0,
	},
	"dusk": {
		"beds": {"amb_breeze": 0.0, "amb_stream": -0.5, "amb_rain": None, "amb_crickets": None},
		"birds": {"interval_s": [25.0, 60.0], "volume_db": -2.0},
		"pad_set": "day", "pad_db": 1.5,
		"voices": {"ep": {"base": 72, "db": 3.0}},
		"density": 0.40, "music_lpf_hz": 12000.0,
	},
	"night": {
		"beds": {"amb_breeze": -3.0, "amb_stream": -0.5, "amb_rain": None, "amb_crickets": -15.0},
		"birds": None,
		"pad_set": "night", "pad_db": 1.5,
		"voices": {"ep": {"base": 60, "db": 2.0}},
		"density": 0.25, "music_lpf_hz": 3500.0,
	},
}

WEATHER = {
	"clear": {"bed_add_db": {}, "replace": {}, "density_add": 0.0, "music_lpf_add_hz": 0.0, "music_add_db": 0.0,
		"birds_rate_mult": 1.0, "birds_add_db": 0.0, "crickets": True, "chime_gust_s": [30.0, 60.0]},
	"breeze": {"bed_add_db": {"amb_breeze": 4.0, "amb_stream": -1.5}, "replace": {}, "density_add": 0.0,
		"music_lpf_add_hz": 0.0, "music_add_db": 0.0, "birds_rate_mult": 0.8, "birds_add_db": 0.0, "crickets": True,
		"chime_gust_s": [8.0, 20.0]},
	"rain": {"bed_add_db": {"amb_breeze": -4.0}, "replace": {"amb_stream": "amb_rain"}, "density_add": -0.10,
		"music_lpf_add_hz": -2000.0, "music_add_db": 1.0, "birds_rate_mult": 0.3, "birds_add_db": -1.5,
		"crickets": False, "chime_gust_s": [30.0, 60.0]},
}
MUSIC_LPF_MIN_HZ = 1200.0

# Diegetic critter life while idle (L3): awake visitors coo now and then, sleepers snore softly.
CRITTERS = {
	"coo_interval_s": [40.0, 90.0], "coo_db": -6.0,
	"snore_interval_s": [60.0, 120.0], "snore_db": -3.0,
}

# ----------------------------------------------------------------------------- ducking & settings
DUCK = {
	"sheet_open_lpf_hz": 1200.0, "focus_out_lpf_hz": 1200.0, "lpf_tween_s": 0.4,
	"web_sheet_duck_db": -6.0, "web_night_music_db": -3.0,   # Web: no bus effects (R14)
}
SETTINGS = {
	"volume_default": 80, "volume_step": 10,
	"volume_curve": "offset_db = 30 * log10(slider / 80); slider 0 -> bus muted",
	"music_modes": ["on", "ambience", "off"],
	"mode_fade_s": 3.0,
}

# ----------------------------------------------------------------------------- haptics (D11, 06 §0.6)
HAPTICS = {
	"modes": ["off", "subtle", "full"], "default": "subtle", "min_gap_ms": 60,
	"subtle_amplitude_mult": 0.7,
	"kinds": {
		"TICK": {"android": ["CLOCK_TICK"], "android_gap_ms": 0, "ios": [[12, 0.30]]},
		"DOUBLE": {"android": ["CLOCK_TICK", "CLOCK_TICK"], "android_gap_ms": 70, "ios": [[12, 0.42], [12, 0.294]]},
		"MEDIUM": {"android": ["CONFIRM"], "android_fallback_below_api30": "CLOCK_TICK", "ios": [[24, 0.60]]},
	},
	"web": "none",
}
