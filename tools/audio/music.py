"""L1 pads: one exactly periodic 8-bar clip per chord and per palette (day / night).

R-B recipe (06 §4.3) extended: per note, 4 detuned PolyBLEP saws per channel plus a sine body,
a slow per-voice swell (integer cycles per loop), a 24 dB/oct low-pass with a slow cutoff LFO
(different phase per channel), a soft sub an octave under the bass, then a long dark baked
reverb applied by circular convolution so the clip loops sample-exactly.

Loop contract (synthesis C18): 1 209 600 samples = 8 bars at 70 BPM = 5376 filter blocks.
All oscillator frequencies are rounded to k / 27.428571 Hz (error <= 0.018 Hz).
"""
from __future__ import annotations

import numpy as np

from dsp import (SR, filt_loop, hp_loop, loop_freq, midi_hz, mod_filter, rbj, reverb_circular, saw_blep,
	synth_ir)
from theory import PAD_SAMPLES

PAD_STYLE = {
	# fc: cutoff centre (Hz); lfo: cutoff LFO cycles per clip; depth: +-octaves; wet: reverb send
	"day": {"fc": 1300.0, "lfo": 2, "depth": 0.40, "wet": 0.30, "sub": 0.12, "air": 0.018, "rt60": 3.2, "shelf_db": -4.5},
	"night": {"fc": 620.0, "lfo": 1, "depth": 0.32, "wet": 0.36, "sub": 0.16, "air": 0.0, "rt60": 3.6, "shelf_db": -6.0},
}


def pad(voicing: list[int], style: str, seed: int) -> np.ndarray:
	cfg = PAD_STYLE[style]
	rng = np.random.default_rng(seed)
	n = PAD_SAMPLES
	dur = n / SR
	t2 = np.arange(2 * n) / SR          # two periods; the filters' second period is kept
	y = np.zeros((2, 2 * n))
	nv = len(voicing)
	for vi, m in enumerate(voicing):
		f = midi_hz(m)
		g = 1.0 if 0 < vi < nv - 1 else (1.12 if vi == 0 else 0.86)   # bass a touch fuller, top softer
		swell_cycles = 1 + (vi % 3)
		swell_ph = rng.uniform(0, 2 * np.pi)
		for ch in (0, 1):
			sw = 1.0 + 0.16 * np.sin(2 * np.pi * swell_cycles * t2 / dur + swell_ph + 0.6 * ch)
			for cents in (-9.0, -3.0, 4.0, 10.0):
				fq = loop_freq(f * 2.0 ** ((cents + rng.uniform(-1.0, 1.0)) / 1200.0), dur)
				y[ch] += g * sw * saw_blep(fq, t2, rng.random())
			y[ch] += 0.9 * g * sw * np.sin(2 * np.pi * loop_freq(f, dur) * t2 + rng.uniform(0, 2 * np.pi))
	out = np.empty((2, n))
	for ch in (0, 1):
		cut = cfg["fc"] * 2.0 ** (cfg["depth"] * np.sin(2 * np.pi * cfg["lfo"] * t2 / dur + 1.3 * ch))
		z = mod_filter(mod_filter(y[ch:ch + 1], "lp", cut, 0.6), "lp", 1.5 * cut, 0.6)
		out[ch] = z[0, n:]
	out /= np.abs(out).max()
	t = t2[:n]
	bass = voicing[0] - 12
	if bass >= 36:   # sub sine for headphones; phone speakers rely on the missing fundamental
		fs = loop_freq(midi_hz(bass), dur)
		out += cfg["sub"] * np.sin(2 * np.pi * fs * t)[None, :] * (1.0 + 0.1 * np.sin(2 * np.pi * t / dur))
	if cfg["air"] > 0:  # faint octave shimmer on the top note, breathing once per clip
		fa = loop_freq(midi_hz(voicing[-1] + 12), dur)
		for ch in (0, 1):
			out[ch] += cfg["air"] * np.sin(2 * np.pi * fa * t + ch) * (0.5 + 0.5 * np.sin(2 * np.pi * t / dur + ch))
	out = filt_loop(out, rbj("hshelf", 2500.0, 0.7071, cfg["shelf_db"]))
	out = hp_loop(out, 38.0, 0.7)
	ir = synth_ir(cfg["rt60"], predelay_ms=24.0, seed=seed + 101, dark=0.45, xover_hz=1800.0)
	return reverb_circular(out, ir, cfg["wet"], dry=1.0 - 0.5 * cfg["wet"])
