"""Active Play v1 SFX (GDD §14.8: S26-S38; mono, un-normalised).

Same rules as sfx.py / instruments.py (AUDIO_BIBLE §3): raised-cosine attacks, everything
low-passed <= 5 kHz, warmth carried by 200-600 Hz, tonal parts on F-Lydian notes (pitched banks:
one file per note, the AudioDirector snaps to the chord's pentatonic set) or on the chord's own
tones (chord-clip banks), unpitched parts as soft noise grains. Nothing buzzes, nothing is sharp.
"""
from __future__ import annotations

import numpy as np

from dsp import SR, bubble, env_ad, fade_in, fade_out, hp, lp, midi_hz, noise_band, trim_tail, tt
from instruments import _finish, glass_note
from sfx import CHORD_TONES, _grains, _rising, _room


def _norm(x: np.ndarray) -> np.ndarray:
	return x / (np.abs(x).max() + 1e-12)


def _add(y: np.ndarray, x: np.ndarray, t0: float, gain: float = 1.0) -> None:
	i = int(t0 * SR)
	if i >= len(y):
		return
	k = min(len(x), len(y) - i)
	y[i:i + k] += gain * x[:k]


def _soft_tone(f: float, dur: float, tau: float, seed: int, partials=((1.0, 1.0), (2.0, 0.12))) -> np.ndarray:
	"""Sine body with a few gentle partials kept below 2 kHz (A2), slow beating for warmth."""
	rng = np.random.default_rng(seed)
	t = tt(dur)
	y = np.zeros_like(t)
	for k, (r, a) in enumerate(partials):
		if r * f > 2000.0 and k > 0:
			continue
		for d in (-0.4, 0.4):
			y += a * np.sin(2 * np.pi * (r * f + d * rng.uniform(0.3, 0.9)) * t + 2 * np.pi * rng.random()) \
				* np.exp(-t / (tau / (1.0 + 1.5 * k)))
	return y * env_ad(len(t), 2.0, 1e9)


# ============================================================================= pitched banks
def blup(m: int, seed: int) -> np.ndarray:
	"""S26 wish appears: a soft, airy bubble 'blup' (a round bubble gliding up into the note)."""
	f = midi_hz(m)
	t = tt(0.42)
	glide = f * 2.0 ** ((-3.0 * np.exp(-t / 0.03)) / 12.0)
	body = np.sin(2 * np.pi * np.cumsum(glide) / SR) * np.exp(-t / 0.11)
	body += 0.25 * np.sin(np.pi * np.cumsum(glide) / SR) * np.exp(-t / 0.07)
	air = lp(np.random.default_rng(seed).standard_normal(len(t)), 900.0, 0.7, 2)
	y = (body + 0.03 * _norm(air) * np.exp(-t / 0.04)) * env_ad(len(t), 6.0, 1e9)
	return _finish(fade_out(y, 120.0), 2600.0, 0.7, 0.12, seed, -52.0)


def drip(m: int, seed: int) -> np.ndarray:
	"""S29 petal or drop into the pot: a tiny round plip into warm tea (darker than S01)."""
	f = midi_hz(m)
	b = bubble(f, 0.045, 0.10)
	tb = np.arange(len(b)) / SR
	y = b + 0.4 * np.sin(np.pi * f * tb) * np.exp(-tb / 0.03)
	y = np.concatenate([y * env_ad(len(y), 2.5, 1e9), np.zeros(int(0.06 * SR))])
	return _finish(y, 2800.0, 0.9, 0.12, seed, -60.0)


def bell(m: int, seed: int) -> np.ndarray:
	"""S30 stir bell (every 180 degrees): a small felt-struck bell, round and short."""
	f = midi_hz(m)
	y = _soft_tone(f, 0.9, 0.3, seed, ((1.0, 1.0), (2.0, 0.10), (3.0, 0.03)))
	felt = lp(np.random.default_rng(seed).standard_normal(len(y)) * np.exp(-tt(0.9) / 0.002), 1200.0, 0.7, 2)
	y = y + 0.04 * _norm(felt)
	return _finish(fade_out(y, 300.0), 3200.0, 1.0, 0.16, seed, -52.0)


def tink(m: int, seed: int) -> np.ndarray:
	"""S36 snap into a socket: a tiny glassy 'tink' (sine + soft octave, 350 ms)."""
	f = midi_hz(m)
	y = _soft_tone(f, 0.45, 0.10, seed, ((1.0, 1.0), (2.0, 0.06)))
	return _finish(fade_out(y, 150.0), 2800.0, 0.7, 0.10, seed, -54.0)


# ============================================================================= variants
def petals(seed: int) -> np.ndarray:
	"""S28 petals gathered: paper-soft petal flutter, then one glass plink (A5 or D6) on arrival."""
	rng = np.random.default_rng(seed)
	dur = rng.uniform(0.45, 0.55)
	shape = lambda u: np.sin(np.pi * min(u, 1.0)) ** 1.2
	fl = lp(_grains(rng, dur, rng.uniform(55.0, 80.0), 400.0, 1200.0, (3.0, 9.0), 1.0, shape), 1500.0, 0.6, 2)
	y = np.zeros(int(1.5 * SR))
	_add(y, _norm(fl), 0.0, 0.55)
	note = (81, 86)[int(rng.integers(0, 2))]
	_add(y, _soft_tone(midi_hz(note), 0.9, 0.3, seed + 3, ((1.0, 1.0),)), dur + 0.04, 0.5)
	return trim_tail(_room(lp(y, 3000.0, 0.6, 2), seed, 1.0, 0.14), -60.0, 30.0)


def spoon(seed: int) -> np.ndarray:
	"""S30 layer: a ceramic spoon swish, one airy swirl (no flutter, A2)."""
	rng = np.random.default_rng(seed)
	dur = rng.uniform(0.32, 0.42)
	n = int(dur * SR)
	u = np.arange(n) / n
	y = noise_band(n, rng, 300.0, 1100.0, 1.0) * np.sin(np.pi * u) ** 1.8
	y = lp(y, 1400.0, 0.6, 2)
	return trim_tail(_room(y, seed, 0.7, 0.08), -58.0, 25.0)


def clink(seed: int) -> np.ndarray:
	"""S32 two cups clink, then a soft sip. The clink rings on universal pitch classes."""
	rng = np.random.default_rng(seed)
	y = np.zeros(int(1.4 * SR))
	a, b = ((81, 86), (79, 86), (81, 91))[int(rng.integers(0, 3))]
	for k, (m, t0) in enumerate(((a, 0.0), (b, 0.012))):
		_add(y, _soft_tone(midi_hz(m), 0.6, 0.16, seed + k, ((1.0, 1.0), (2.0, 0.05))), t0, 0.5)
	tick = lp(rng.standard_normal(int(0.01 * SR)) * np.exp(-tt(0.01) / 0.0015), 1600.0, 0.7, 2)
	_add(y, _norm(tick), 0.0, 0.12)
	sd = rng.uniform(0.28, 0.36)
	ns = int(sd * SR)
	u = np.arange(ns) / ns
	sip = noise_band(ns, rng, 250.0, 900.0, 1.2) * (np.sin(np.pi * u) ** 2) * (0.6 + 0.4 * u)
	_add(y, lp(sip, 1100.0, 0.7, 2), 0.42, 0.22)
	return trim_tail(_room(lp(y, 3000.0, 0.6, 2), seed, 0.9, 0.12), -60.0, 30.0)


def steam(seed: int) -> np.ndarray:
	"""S34 nook ambience: very soft kettle steam, one slow breath (0.4 Hz), no rhythm."""
	rng = np.random.default_rng(seed)
	dur = rng.uniform(2.4, 2.9)
	n = int(dur * SR)
	u = np.arange(n) / n
	y = noise_band(n, rng, 250.0, 1200.0, 1.4) * np.sin(np.pi * u) ** 1.5
	y = lp(y, 1300.0, 0.6, 2)
	return trim_tail(fade_in(fade_out(y, 600.0), 300.0), -60.0, 40.0)


def lift(seed: int) -> np.ndarray:
	"""S35 decor lift: a soft upward felt 'fwump' (band rising 300 -> 650 Hz) and a tiny wood tick."""
	rng = np.random.default_rng(seed)
	dur = rng.uniform(0.22, 0.28)
	n = int(dur * SR)
	u = np.arange(n) / n
	src = noise_band(n, rng, 200.0, 1100.0, 1.0)
	lo = lp(src, 300.0 + 350.0 * float(u[-1]), 0.8, 2)
	y = (0.6 * lo + 0.4 * lp(src, 650.0, 0.8, 2) * u) * np.sin(np.pi * u) ** 1.3
	t = tt(0.12)
	tok = np.sin(2 * np.pi * midi_hz(67) * t) * np.exp(-t / 0.03) * env_ad(len(t), 1.0, 1e9)
	out = np.zeros(int(0.7 * SR))
	_add(out, _norm(y), 0.0, 0.8)
	_add(out, tok, dur * 0.8, 0.22)
	return trim_tail(_room(lp(out, 1800.0, 0.6, 2), seed, 0.7, 0.08), -58.0, 25.0)


def turn(seed: int) -> np.ndarray:
	"""S37 turn: a round 'pop' and a few soft wood grains (a tiny creak, never squeaky)."""
	rng = np.random.default_rng(seed)
	y = np.zeros(int(0.7 * SR))
	pop = bubble(rng.uniform(300.0, 380.0), 0.025, 0.35)
	_add(y, pop, 0.0, 0.7)
	shape = lambda u: np.sin(np.pi * min(u, 1.0))
	cr = _grains(rng, 0.16, rng.uniform(55.0, 75.0), 500.0, 950.0, (3.0, 6.0), 2.5, shape)
	_add(y, lp(_norm(cr), 1300.0, 0.7, 2), 0.05, 0.35)
	return trim_tail(_room(lp(y, 2000.0, 0.6, 2), seed, 0.7, 0.08), -58.0, 25.0)


def tuck(seed: int) -> np.ndarray:
	"""S38 tuck into the tray: a leafy rustle falling away and a soft cushioned thump."""
	rng = np.random.default_rng(seed)
	dur = rng.uniform(0.28, 0.34)
	shape = lambda u: np.exp(-u * 2.5) * min(1.0, u / 0.12)
	r = lp(_grains(rng, dur, rng.uniform(80.0, 110.0), 400.0, 1100.0, (2.0, 6.0), 1.2, shape), 1500.0, 0.6, 2)
	t = tt(0.22)
	f = 120.0 * np.exp(-t / 0.05) + 80.0
	thump = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.05) * env_ad(len(t), 3.0, 1e9)
	y = np.zeros(int(0.7 * SR))
	_add(y, _norm(r), 0.0, 0.6)
	_add(y, thump, dur * 0.75, 0.55)
	return trim_tail(hp(_room(lp(y, 1800.0, 0.6, 2), seed, 0.6, 0.07), 50.0), -58.0, 25.0)


# ============================================================================= chord gestures
def sparkle(clip: str, seed: int) -> np.ndarray:
	"""S27 wish granted (layer 2): a 3-note glass sparkle up the chord triad. It starts 150 ms
	into the file so the species chirp (layer 1) speaks first."""
	triad, _colour = CHORD_TONES[clip]
	notes = _rising(triad, 76)
	y = np.zeros(int(1.9 * SR))
	for k, m in enumerate(notes):
		g = _soft_tone(midi_hz(m), 1.1, 0.34, seed + k, ((1.0, 1.0), (2.0, 0.08)))
		_add(y, g, 0.15 + 0.085 * k, 0.5 + 0.12 * k)
	return trim_tail(_room(lp(y, 3200.0, 0.6, 2), seed, 1.2, 0.16), -54.0, 40.0)


def pour(clip: str, seed: int) -> np.ndarray:
	"""S31 pour / simple brew (1.2 s): a warm liquid trickle with small bubbles, and a rising run
	of soft glass notes on the chord (the 'gliss', kept on chord tones)."""
	rng = np.random.default_rng(seed)
	triad, colour = CHORD_TONES[clip]
	y = np.zeros(int(2.4 * SR))
	n = int(1.2 * SR)
	u = np.arange(n) / n
	trickle = noise_band(n, rng, 300.0, 1400.0, 1.2) * np.minimum(1.0, u / 0.08) * np.minimum(1.0, (1.0 - u) / 0.25)
	_add(y, lp(trickle, 1500.0, 0.7, 2), 0.0, 0.30)
	for _k in range(9):
		b = bubble(rng.uniform(600.0, 1300.0), rng.uniform(0.006, 0.012), 0.15)
		_add(y, b, rng.uniform(0.05, 1.1), rng.uniform(0.10, 0.22))
	notes = _rising(triad + [colour], 72)
	for k, m in enumerate(notes):
		_add(y, _soft_tone(midi_hz(m), 1.0, 0.3, seed + 10 + k, ((1.0, 1.0),)), 0.25 + 0.22 * k, 0.22 + 0.04 * k)
	return trim_tail(_room(lp(y, 3000.0, 0.6, 2), seed, 1.0, 0.14), -54.0, 40.0)


def recipe(clip: str, seed: int) -> np.ndarray:
	"""S33 new recipe: a small sparkle triad (S09 family, shorter) over a warm low root."""
	triad, colour = CHORD_TONES[clip]
	notes = _rising(triad, 72)
	y = np.zeros(int(2.2 * SR))
	root = _soft_tone(midi_hz(notes[0] - 12), 1.6, 0.6, seed, ((1.0, 1.0), (2.0, 0.2), (3.0, 0.05)))
	_add(y, root, 0.0, 0.35)
	for k, m in enumerate(notes):
		_add(y, _soft_tone(midi_hz(m), 1.2, 0.4, seed + 5 + k, ((1.0, 1.0), (2.0, 0.1))), 0.03 + 0.1 * k, 0.45)
	top = _rising([colour], notes[-1] + 1)[0]
	_add(y, glass_note(midi_hz(top), 0.9, seed + 9, 0.9), 0.36, 0.12)
	return trim_tail(_room(lp(y, 3400.0, 0.6, 2), seed, 1.3, 0.18), -54.0, 40.0)
