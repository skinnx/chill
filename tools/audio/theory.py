"""Harmony, tempo and pitch-set constants (single source of truth, exported to audio/manifest.json).

Binding inputs: 00-SYNTHESIS D10/C18 (F Lydian, 70 BPM, 8-bar pad clips = 1 209 600 samples) and
06 §0.3/§2.2 (chords Fmaj9, G/F, Dm9, Am7, Cmaj7; melody/SFX snap to the chord's pentatonic set).

Voicings are re-chosen from 06 §2.2 with a Sethares (1993) roughness score of the low-passed saw
partials (lower = smoother); see docs/AUDIO_BIBLE.md §4.2. The pitch-class sets are unchanged.
"""
from __future__ import annotations

from dsp import SR

BPM = 70
BAR_BEATS = 4
PAD_BARS = 8
SAMPLES_PER_BEAT = SR * 60 // BPM            # 37 800 (integer: C18)
PAD_SAMPLES = SAMPLES_PER_BEAT * BAR_BEATS * PAD_BARS   # 1 209 600 = 5376 * 225
PAD_SECONDS = PAD_SAMPLES / SR               # 27.428571 s
assert SR * 60 % BPM == 0 and PAD_SAMPLES % 225 == 0

SCALE_PCS = [5, 7, 9, 11, 0, 2, 4]           # F Lydian: F G A B C D E
PC_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

# name -> clip suffix, pentatonic set (06 §2.2), root pc, fifth pc, day / night pad voicings (MIDI)
CHORDS = [
	{"name": "Fmaj9", "clip": "Fmaj9", "pcs": [5, 7, 9, 0, 2], "root_pc": 5, "fifth_pc": 0,
		"day": [53, 60, 64, 67, 69], "night": [53, 60, 64, 67]},
	{"name": "G/F", "clip": "GoverF", "pcs": [7, 9, 11, 2, 4], "root_pc": 7, "fifth_pc": 2,
		"day": [53, 59, 62, 67, 69], "night": [53, 62, 67, 71]},
	{"name": "Dm9", "clip": "Dm9", "pcs": [2, 5, 7, 9, 0], "root_pc": 2, "fifth_pc": 9,
		"day": [50, 65, 69, 72, 76], "night": [50, 57, 65, 72]},
	{"name": "Am7", "clip": "Am7", "pcs": [9, 0, 2, 4, 7], "root_pc": 9, "fifth_pc": 4,
		"day": [57, 64, 67, 72, 74], "night": [57, 64, 67, 72]},
	{"name": "Cmaj7", "clip": "Cmaj7", "pcs": [0, 2, 4, 7, 9], "root_pc": 0, "fifth_pc": 7,
		"day": [55, 60, 64, 67, 71], "night": [55, 60, 64, 71]},
]
CHORD_BY_CLIP = {c["clip"]: c for c in CHORDS}

# Pitch classes present in every chord's set: a sound pitched on these is always "in key".
UNIVERSAL_PCS = sorted(set.intersection(*(set(c["pcs"]) for c in CHORDS)))  # [2, 7, 9] = D G A


def lydian_notes(lo: int, hi: int) -> list[int]:
	"""All F-Lydian MIDI notes in [lo, hi]."""
	return [m for m in range(lo, hi + 1) if m % 12 in SCALE_PCS]


def note_name(m: int) -> str:
	return f"{PC_NAMES[m % 12]}{m // 12 - 1}"


def snap(midi: int, pcs: list[int]) -> int:
	"""Nearest pitch in the set; ties prefer the lower neighbour (06 §2.4 order 0, +1, -1, ...)."""
	for d in (0, 1, -1, 2, -2, 3, -3):
		if (midi + d) % 12 in pcs:
			return midi + d
	return midi


def pent_step(midi: int, steps: int, pcs: list[int]) -> int:
	"""Move `steps` scale steps through the 5-note set, starting from snap(midi)."""
	m = snap(midi, pcs)
	d = 1 if steps > 0 else -1
	for _ in range(abs(steps)):
		m += d
		while m % 12 not in pcs:
			m += d
	return m


def wrap_into(midi: int, lo: int, hi: int) -> int:
	"""Octave-transpose into [lo, hi] (keeps pitch class)."""
	while midi < lo:
		midi += 12
	while midi > hi:
		midi -= 12
	return midi


# Note-bank ranges (06 §2.4 fact-check fix: ranges must cover what the conductor asks for).
# Every F-Lydian note in range is rendered, so pitch_scale is always exactly 1.0 -- required on
# Web, where AudioStreamPolyphonic sample playback ignores pitch_scale
# (scene/resources/audio_stream_polyphonic.cpp:241-262 never copies it to AudioSamplePlayback).
BANK_RANGES = {
	"ep": (53, 83),      # e-piano F3-B5: day base 72 +-3 plus steps, night base 60
	"mar": (53, 76),     # marimba F3-E5: base 65 +-3 plus S05 A3-D4
	"chime": (72, 95),   # chime C5-B6: base 79 +-3 with 3-note climbs
	"plip": (71, 84),    # S01 tap B4-C6 (snap of C5 can land on B4 under G/F)
	"dew": (71, 91),     # S02 collect ladder B4-G6 (+7 pentatonic steps cap from snap(C5))
	"purr": (53, 64),    # S03 purr root F3-E4
	"tok": (50, 64),     # S08/S11 wood tok D3-E4
	"coo": (62, 81),     # S13 mossling chirp D4-A5
}
SHELL_NOTES = [65, 67, 69, 72, 74, 77, 79, 81, 84, 86]  # GDD §4.3: F4 G4 A4 C5 D5 F5 G5 A5 C6 D6
