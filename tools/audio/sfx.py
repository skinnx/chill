"""Composite and unpitched SFX (mono, un-normalised). IDs refer to docs/AUDIO_BIBLE.md §6.

Chord-dependent gestures (S04 unfurl, S09 new friend, S10 welcome back, S16 postcard) are
pre-rendered once per chord so their internal rhythm is sample-tight; the AudioDirector picks
the file for the chord that is sounding. Their pitches are chord tones inside that chord's
pentatonic set (A3).
"""
from __future__ import annotations

import numpy as np

from ambience import bird
from dsp import SR, bubble, env_ad, filt, hp, lp, midi_hz, noise_band, rbj, reverb_oneshot, trim_tail, tt
from instruments import epiano, glass_note, room_ir, shell
from theory import pent_step

# chord -> (triad pcs from the root, colour tone in the chord's own set)
CHORD_TONES = {
	"Fmaj9": ([5, 9, 0], 7),
	"GoverF": ([7, 11, 2], 9),
	"Dm9": ([2, 5, 9], 0),
	"Am7": ([9, 0, 4], 7),
	"Cmaj7": ([0, 4, 7], 2),
}


def _rising(pcs: list[int], start: int) -> list[int]:
	"""Stack pitch classes upward from the first one at/above `start`."""
	out, m = [], start
	for pc in pcs:
		while m % 12 != pc:
			m += 1
		out.append(m)
		m += 1
	return out


def _grains(rng, dur: float, rate: float, f_lo: float, f_hi: float, g_ms=(2.0, 6.0), q: float = 1.2,
		shape=None) -> np.ndarray:
	"""Soft noise-grain texture (paper, leaves): Poisson grains through random band-passes."""
	n = int(dur * SR)
	y = np.zeros(n + int(0.05 * SR))
	t = 0.0
	while True:
		t += rng.exponential(1.0 / rate)
		if t >= dur:
			break
		ln = int(SR * rng.uniform(*g_ms) / 1000.0)
		z = rng.standard_normal(ln) * np.hanning(ln)
		z = filt(z, rbj("bp", rng.uniform(f_lo, f_hi), q))
		a = shape(t / dur) if shape else 1.0
		i = int(t * SR)
		y[i:i + ln] += a * z * min(rng.lognormal(0.0, 0.35), 1.8)
	return y


def _room(y: np.ndarray, seed: int, rt60: float = 1.0, wet: float = 0.12) -> np.ndarray:
	return reverb_oneshot(y, room_ir(rt60, 0.5, 30 + seed % 5), wet)


# ----------------------------------------------------------------------------- unpitched
def bubbles(seed: int) -> np.ndarray:
	"""S06 stream tap / water: 6-10 Minnaert bubbles within 300 ms, f0 0.8-1.7 kHz (A2 water band)."""
	rng = np.random.default_rng(seed)
	y = np.zeros(int(0.6 * SR))
	for k in range(int(rng.integers(6, 11))):
		t0 = rng.uniform(0.0, 0.30) * (0.4 + 0.6 * k / 10.0)
		b = bubble(rng.uniform(800.0, 1700.0), rng.uniform(0.006, 0.016), rng.uniform(0.08, 0.2))
		i = int(t0 * SR)
		y[i:i + len(b)] += b[:len(y) - i] * rng.uniform(0.4, 1.0)
	y = lp(y, 3800.0, 0.6, 2)
	return trim_tail(_room(y, seed, 1.0, 0.14), -60.0, 30.0)


def paper(seed: int) -> np.ndarray:
	"""S07 sheet open: soft felted-paper rustle, 20-40 grains, kept below 2 kHz (A2 UI band)."""
	rng = np.random.default_rng(seed)
	dur = rng.uniform(0.28, 0.38)
	shape = lambda u: np.sin(np.pi * min(u, 1.0)) ** 0.7
	y = _grains(rng, dur, rng.uniform(70.0, 110.0), 500.0, 1500.0, (3.0, 8.0), 1.1, shape)
	y += 0.25 * lp(_grains(rng, dur, 40.0, 250.0, 600.0, (6.0, 14.0), 0.9, shape), 900.0)
	y = lp(y, 1800.0, 0.6, 2)
	return trim_tail(_room(y, seed, 0.7, 0.08), -58.0, 25.0)


def rustle(seed: int) -> np.ndarray:
	"""S18 tap a bed: leaves and stems sway -- soft, low grains over ~400 ms."""
	rng = np.random.default_rng(seed)
	dur = rng.uniform(0.35, 0.48)
	shape = lambda u: (u / 0.25) if u < 0.25 else np.exp(-(u - 0.25) * 3.0)
	y = _grains(rng, dur, rng.uniform(90.0, 140.0), 450.0, 1400.0, (2.0, 6.0), 1.3, shape)
	y = lp(y, 1900.0, 0.6, 2)
	return trim_tail(_room(y, seed, 0.8, 0.10), -58.0, 25.0)


def soil(seed: int) -> np.ndarray:
	"""S05 layer: soft soil 'pat' (low-passed noise, 120 ms) with a small thump."""
	rng = np.random.default_rng(seed)
	t = tt(0.25)
	nz = lp(rng.standard_normal(len(t)) * np.exp(-t / 0.035), 420.0, 0.7, 2)
	f = 95.0 * np.exp(-t / 0.05) + 70.0
	thump = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.045)
	y = (nz / np.abs(nz).max() + 0.5 * thump) * env_ad(len(t), 2.0, 1e9)
	return trim_tail(hp(_room(y, seed, 0.6, 0.06), 50.0), -56.0, 25.0)


def swish(seed: int) -> np.ndarray:
	"""S19 pinwheel spin: one airy swell, band sweeping 350 -> 900 -> 450 Hz (no flutter: A2)."""
	rng = np.random.default_rng(seed)
	dur = rng.uniform(0.45, 0.6)
	n = int(dur * SR)
	src = noise_band(n, rng, 200.0, 1800.0, 1.0)
	u = np.arange(n) / n
	fc = 350.0 + 550.0 * np.sin(np.pi * u ** 0.7)
	y = np.zeros(n)
	zi = np.zeros(2)
	from scipy.signal import lfilter
	for i in range(0, n, 225):
		b, a = rbj("bp", float(fc[i]), 1.1)
		y[i:i + 225], zi = lfilter(b, a, src[i:i + 225], zi=zi)
	y *= np.sin(np.pi * u) ** 1.6
	y = lp(y, 1800.0, 0.6, 2)
	return trim_tail(_room(y, seed, 0.8, 0.08), -58.0, 30.0)


def boat(seed: int) -> np.ndarray:
	"""S17 leaf boat launch: a low water plop, two small bubbles, a hint of paper."""
	rng = np.random.default_rng(seed)
	y = np.zeros(int(1.0 * SR))
	plop = bubble(rng.uniform(420.0, 560.0), 0.028, 0.35)
	y[:len(plop)] += plop
	for k in range(2):
		b = bubble(rng.uniform(1000.0, 1600.0), rng.uniform(0.008, 0.012), 0.2)
		i = int(rng.uniform(0.08, 0.22) * SR)
		y[i:i + len(b)] += 0.35 * b
	pp = paper(seed + 9)
	i = int(0.03 * SR)
	y[i:i + len(pp)] += 0.25 * pp[:len(y) - i] / (np.abs(pp).max() + 1e-12)
	y = lp(y, 3500.0, 0.6, 2)
	return trim_tail(_room(y, seed, 1.1, 0.14), -60.0, 30.0)


# ----------------------------------------------------------------------------- chord gestures
def unfurl(clip: str, seed: int) -> np.ndarray:
	"""S04 bud unfurls (600 ms): leaf rustle swelling from touch-down, then a rising 3-note
	glass arpeggio (chord triad) that lands as the petals open, plus one faint sparkle."""
	rng = np.random.default_rng(seed)
	triad, colour = CHORD_TONES[clip]
	notes = _rising(triad, 74)
	y = np.zeros(int(2.4 * SR))
	shape = lambda u: (u / 0.8) ** 1.5 if u < 0.8 else max(0.0, 1.0 - (u - 0.8) * 5.0)
	r = lp(_grains(rng, 0.55, 120.0, 500.0, 1500.0, (2.0, 5.0), 1.3, shape), 1900.0, 0.6, 2)
	y[:len(r)] += 0.55 * r / (np.abs(r).max() + 1e-12)
	for k, (m, t0) in enumerate(zip(notes, (0.33, 0.42, 0.51))):
		g = glass_note(midi_hz(m), 1.2, seed + k, 1.6)
		i = int(t0 * SR)
		y[i:i + len(g)] += (0.55 + 0.15 * k) * g[:len(y) - i]
	sp = glass_note(midi_hz(_rising([colour], notes[-1] + 1)[0]), 0.9, seed + 7, 1.2)
	i = int(0.60 * SR)
	y[i:i + len(sp)] += 0.18 * sp[:len(y) - i]
	y = lp(y, 5000.0, 0.6, 2)
	return trim_tail(_room(y, seed, 1.6, 0.2), -60.0, 40.0)


def fanfare(clip: str, seed: int) -> np.ndarray:
	"""S09 new friend / milestone: warm e-piano root, then a 4-tone rising arpeggio (triad +
	colour tone) doubled by glass, then a soft two-note sparkle. Gentle, never a stinger."""
	triad, colour = CHORD_TONES[clip]
	start = 65 if triad[0] in (5, 7) else 62   # keep the arpeggio inside F4-A6
	notes = _rising(triad + [colour], start)
	y = np.zeros(int(3.4 * SR))
	root = epiano(notes[0] - 12, seed)
	y[:len(root)] += 0.45 * root[:len(y)] / (np.abs(root).max() + 1e-12)
	for k, m in enumerate(notes):
		t0 = 0.05 + 0.13 * k
		i = int(t0 * SR)
		ep = epiano(m, seed + 10 + k)
		y[i:i + len(ep)] += 0.55 * ep[:len(y) - i] / (np.abs(ep).max() + 1e-12)
		g = glass_note(midi_hz(m + 12) if m + 12 <= 93 else midi_hz(m), 2.2, seed + 20 + k)
		y[i:i + len(g)] += 0.22 * g[:len(y) - i]
	for k, m in enumerate((notes[-1] + 12, notes[-2] + 12)):
		g = glass_note(midi_hz(min(m, 93)), 1.6, seed + 40 + k)
		i = int((0.70 + 0.11 * k) * SR)
		y[i:i + len(g)] += 0.12 * g[:len(y) - i]
	y = lp(y, 5000.0, 0.6, 2)
	return trim_tail(_room(y, seed, 2.0, 0.22), -52.0, 120.0)


def welcome(clip: str, seed: int) -> np.ndarray:
	"""S10 welcome back: an unhurried rising triad on e-piano + glass, and a far bird answering."""
	triad, _colour = CHORD_TONES[clip]
	notes = _rising(triad, 62)
	y = np.zeros(int(3.6 * SR))
	for k, m in enumerate(notes):
		i = int((0.04 + 0.19 * k) * SR)
		ep = epiano(m, seed + k)
		y[i:i + len(ep)] += 0.5 * ep[:len(y) - i] / (np.abs(ep).max() + 1e-12)
		g = glass_note(midi_hz(m + 12), 2.4, seed + 10 + k)
		y[i:i + len(g)] += 0.16 * g[:len(y) - i]
	b = bird("feebee", seed + 77).mean(axis=0)
	i = int(0.95 * SR)
	y[i:i + len(b)] += 0.10 * b[:len(y) - i] / (np.abs(b).max() + 1e-12)
	y = lp(y, 5000.0, 0.6, 2)
	return trim_tail(_room(y, seed, 2.0, 0.2), -52.0, 120.0)


def postcard(clip: str, seed: int) -> np.ndarray:
	"""S16 postcard arrives: paper slide, the mailbox flag's wooden tick, then a two-note shell
	'ding-ding' rising a fifth from the chord root."""
	rng = np.random.default_rng(seed)
	triad, _ = CHORD_TONES[clip]
	root = _rising([triad[0]], 72)[0]
	fifth = _rising([triad[2]], root + 1)[0]
	y = np.zeros(int(2.4 * SR))
	pp = paper(seed + 3)
	y[:len(pp)] += 0.6 * pp / (np.abs(pp).max() + 1e-12)
	t = tt(0.12)
	tick = np.sin(2 * np.pi * midi_hz(62) * t) * np.exp(-t / 0.03) * env_ad(len(t), 1.0, 1e9)
	i = int(0.06 * SR)
	y[i:i + len(tick)] += 0.35 * tick
	for k, (m, t0) in enumerate(((root, 0.20), (fifth, 0.36))):
		s = shell(m, seed + 5 + k)
		i = int(t0 * SR)
		y[i:i + len(s)] += 0.5 * s[:len(y) - i] / (np.abs(s).max() + 1e-12)
	_ = rng
	y = lp(y, 5000.0, 0.6, 2)
	return trim_tail(_room(y, seed, 1.4, 0.14), -60.0, 40.0)


_ = pent_step  # re-exported for callers composing ladders
