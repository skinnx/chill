"""Tuned instruments and pitched SFX banks (one mono note per call, un-normalised).

Recipes extend 06 §4.2-§4.6 (R-A1 e-piano, R-A2 marimba, R-F chime, R-E plip) with the
sound-design rules of 06 §3: raised-cosine attacks of 2-10 ms, decays matched to the gesture,
everything low-passed <= 6 kHz, warmth carried by 200-600 Hz partials (phone speakers), and
no partial placed where it would push the 2-5 kHz band past the A2 gate.
"""
from __future__ import annotations

from functools import lru_cache

import numpy as np

from dsp import (SR, bubble, env_ad, fade_in, fade_out, hp, loop_freq, lp, lp_loop, hp_loop, midi_hz,
	noise_band, raised_cos_in, reverb_oneshot, synth_ir, trim_tail, tt)


@lru_cache(maxsize=None)
def room_ir(rt60: float, dark: float, seed: int, stereo: bool = False) -> np.ndarray:
	return synth_ir(rt60=rt60, predelay_ms=14.0, seed=seed, dark=dark, xover_hz=2200.0, stereo=stereo)


def _finish(y: np.ndarray, lp_hz: float, rt60: float, wet: float, seed: int, floor_db: float = -50.0) -> np.ndarray:
	"""Common note post-chain: gentle LP, baked small room, tail trim."""
	y = lp(y, lp_hz, 0.6, 2)
	y = hp(y, 45.0, 0.7)
	y = reverb_oneshot(y, room_ir(rt60, 0.5, 11 + seed % 7), wet)
	return trim_tail(y, floor_db, 40.0)


# ----------------------------------------------------------------------------- R-A1 e-piano
def epiano(m: int, seed: int) -> np.ndarray:
	"""2-op FM (Chowning, C:M 1:1) with a decaying index, a warm sine body and a soft tine."""
	rng = np.random.default_rng(seed)
	f = midi_hz(m)
	tau = 1.15 * (220.0 / f) ** 0.6           # F3 1.32 s ... B5 0.47 s: higher notes decay faster
	dur = min(2.5, 0.3 + 3.6 * tau)
	t = tt(dur)
	ph = 2 * np.pi * rng.random()
	index = 1.15 * np.exp(-t / 0.22) + 0.2      # bright "bark" that mellows within ~0.3 s
	car = np.sin(2 * np.pi * f * t + index * np.sin(2 * np.pi * f * t + ph))
	body = 0.5 * np.sin(2 * np.pi * f * t) * np.exp(-t / (1.6 * tau))
	ratio = next(r for r in (7.0, 5.0, 3.0, 2.0) if r * f < 3200.0)  # tine stays below the harsh band
	tine = 0.045 * np.exp(-t / 0.02) * np.sin(2 * np.pi * ratio * f * t)
	y = car * np.exp(-t / tau) + body + tine
	y *= env_ad(len(t), 4.0, 1e9)
	y = fade_out(y, 0.35 * dur * 1000.0)
	return _finish(y, 4200.0, 1.5, 0.20, seed)


# ----------------------------------------------------------------------------- R-A2 marimba
def marimba(m: int, seed: int) -> np.ndarray:
	"""Modal bar tuned ~1:4:10 (Rossing) with a felt mallet; the fundamental rings longest."""
	rng = np.random.default_rng(seed)
	f = midi_hz(m)
	dur = min(1.5, 0.4 + 2.0 * (330.0 / f) ** 0.5)
	t = tt(dur)
	k = (330.0 / f) ** 0.5
	y = np.zeros_like(t)
	for r, a, tau in ((1.0, 1.0, 0.55), (3.93, 0.16, 0.09), (9.2, 0.035, 0.025)):
		if r * f < 4500.0:
			y += a * np.sin(2 * np.pi * r * f * t + 2 * np.pi * rng.random()) * np.exp(-t / (tau * k))
	mallet = lp(rng.standard_normal(len(t)) * np.exp(-t / 0.0018), 1400.0, 0.7, 2)
	y = (y + 0.05 * mallet / (np.abs(mallet).max() + 1e-12)) * env_ad(len(t), 2.5, 1e9)
	y = fade_out(y, 0.4 * dur * 1000.0)
	return _finish(y, 4500.0, 1.3, 0.16, seed)


# ----------------------------------------------------------------------------- R-F chime
FREE_BAR = [1.0, 2.7565, 5.4039, 8.9330]   # free-free beam modes (06 §4.6)


def chime(m: int, seed: int, t60: float | None = None, amps=(1.0, 0.24, 0.07, 0.02), lp_hz: float = 5200.0) -> np.ndarray:
	"""Free-free bar modes with detuned pairs beating at 0.4-1.4 Hz (shimmer, not roughness)."""
	rng = np.random.default_rng(seed)
	f = midi_hz(m)
	t60 = t60 if t60 is not None else 3.3 * (784.0 / f) ** 0.35
	dur = min(2.4, 0.8 * t60)
	t = tt(dur)
	y = np.zeros_like(t)
	for k, (r, a) in enumerate(zip(FREE_BAR, amps)):
		if r * f > 7000.0:
			break
		for d in (-0.5, 0.5):
			y += a * np.sin(2 * np.pi * (r * f + d * rng.uniform(0.4, 1.4)) * t + 2 * np.pi * rng.random()) \
				* np.exp(-6.91 * t / (t60 / (1.0 + 1.6 * k)))
	y *= env_ad(len(t), 1.5, 1e9)
	y = fade_out(y, 0.3 * dur * 1000.0)
	return _finish(y, lp_hz, 1.8, 0.22, seed)


def shell(m: int, seed: int) -> np.ndarray:
	"""Shell wind-chime note (decor, GDD §4.3): glassy, shorter, with a tiny soft 'clack'."""
	rng = np.random.default_rng(seed)
	f = midi_hz(m)
	t60 = 1.9 * (523.0 / f) ** 0.3
	dur = min(2.2, 0.95 * t60)
	t = tt(dur)
	y = np.zeros_like(t)
	for k, (r, a) in enumerate(((1.0, 1.0), (2.76, 0.17), (5.40, 0.04))):
		if r * f > 6500.0:
			break
		for d in (-0.5, 0.5):
			y += a * np.sin(2 * np.pi * (r * f + d * rng.uniform(0.6, 1.6)) * t + 2 * np.pi * rng.random()) \
				* np.exp(-6.91 * t / (t60 / (1.0 + 2.0 * k)))
	clack = lp(rng.standard_normal(len(t)) * np.exp(-t / 0.0012), 1600.0, 0.8, 2)
	y = y + 0.06 * clack / (np.abs(clack).max() + 1e-12)
	y *= env_ad(len(t), 1.2, 1e9)
	y = fade_out(y, 0.3 * dur * 1000.0)
	return _finish(y, 5000.0, 1.6, 0.25, seed)


# ----------------------------------------------------------------------------- R-E plip family
def _plip_core(f: float, tau: float, rise: float) -> np.ndarray:
	b = bubble(f, tau, rise)
	t = np.arange(len(b)) / SR
	return (b + 0.35 * np.sin(np.pi * f * t) * np.exp(-t / (0.6 * tau))) * env_ad(len(b), 2.0, 1e9)


def plip(m: int, seed: int) -> np.ndarray:
	"""S01 tap: a round water 'plip' (bubble with a gentle upward glide plus a sub-octave body)."""
	y = _plip_core(midi_hz(m), 0.05, 0.18)
	y = np.concatenate([y, np.zeros(int(0.05 * SR))])
	return _finish(y, 4000.0, 0.9, 0.12, seed, -60.0)


def dew(m: int, seed: int) -> np.ndarray:
	"""S02 collect: plip plus a glass grace note 40 ms later (octave above while it stays < 1.9 kHz).

	Above ~1 kHz the bubble glide is reduced so the top of the ladder stays out of 2-5 kHz (A2).
	"""
	rng = np.random.default_rng(seed)
	f = midi_hz(m)
	body = _plip_core(f, 0.07, 0.12 if f < 1000.0 else 0.04)
	gf = 2.0 * f if 2.0 * f < 1900.0 else f
	t = tt(0.75)
	ting = np.zeros_like(t)
	for d in (-0.5, 0.5):
		ting += np.sin(2 * np.pi * (gf + d * rng.uniform(0.5, 1.2)) * t + 2 * np.pi * rng.random())
	ting *= 0.5 * np.exp(-6.91 * t / 0.65) * env_ad(len(t), 1.5, 1e9)
	y = np.zeros(int(0.9 * SR))
	y[:len(body)] += body
	off = int(0.04 * SR)
	y[off:off + len(ting)] += 0.32 * ting[:len(y) - off]
	return _finish(y, 4200.0, 1.1, 0.16, seed, -60.0)


# ----------------------------------------------------------------------------- S03 purr (loop)
PURR_LOOP_S = 2.0       # 88 200 samples = 392 filter blocks; 22 Hz AM -> 44 whole cycles
PURR_PREROLL_S = 0.08   # attack segment before loop_begin


def purr(m: int, seed: int) -> tuple[np.ndarray, tuple[int, int]]:
	"""S03 'purr chime': warm FM tone, 22 Hz AM at 25 % depth (06 §0.5), one slow breath per loop.

	Returns (signal, (loop_begin, loop_end)). Frames before loop_begin are a raised-cosine fade-in
	of the loop's own last 80 ms, so playback enters the loop with no discontinuity.
	"""
	rng = np.random.default_rng(seed)
	L = int(PURR_LOOP_S * SR)
	t = np.arange(L) / SR
	f = loop_freq(midi_hz(m), PURR_LOOP_S)
	am = 1.0 - 0.25 * (0.5 - 0.5 * np.cos(2 * np.pi * 22.0 * t))
	breath = 0.86 + 0.14 * np.sin(2 * np.pi * t / PURR_LOOP_S - 0.5 * np.pi)
	tone = np.sin(2 * np.pi * f * t + 0.45 * np.sin(2 * np.pi * f * t)) \
		+ 0.22 * np.sin(2 * np.pi * 2 * f * t + 1.1) + 0.08 * np.sin(2 * np.pi * 3 * f * t + 2.3)
	fur = noise_band(L, rng, 110.0, 420.0, alpha=1.0)
	fur_am = 1.0 - 0.6 * (0.5 - 0.5 * np.cos(2 * np.pi * 22.0 * t + 0.4))
	y = (tone * am + 0.22 * fur * fur_am) * breath
	y = hp_loop(lp_loop(y, 2400.0, 0.6, 2), 60.0, 0.7)  # periodic filtering keeps the loop exact
	A = int(PURR_PREROLL_S * SR)
	pre = y[-A:] * raised_cos_in(A)
	return np.concatenate([pre, y]), (A, A + L)


# ----------------------------------------------------------------------------- S08/S11 wood tok
def tok(m: int, seed: int) -> np.ndarray:
	"""Soft wooden 'tok' (R-A2 partial 1 with tau 60 ms, a faint 2.6x mode and a felt click)."""
	rng = np.random.default_rng(seed)
	f = midi_hz(m)
	t = tt(0.35)
	y = np.sin(2 * np.pi * f * t) * np.exp(-t / 0.06) + 0.18 * np.sin(2 * np.pi * 2.57 * f * t) * np.exp(-t / 0.022)
	click = lp(rng.standard_normal(len(t)) * np.exp(-t / 0.001), 1800.0, 0.7, 2)
	y = (y + 0.08 * click / (np.abs(click).max() + 1e-12)) * env_ad(len(t), 1.2, 1e9)
	return _finish(y, 3500.0, 0.8, 0.10, seed, -58.0)


# ----------------------------------------------------------------------------- S13 mossling chirp
def coo(m: int, seed: int) -> np.ndarray:
	"""A small round 'mrrp?' -- pitch glides up 2.5 st into the note, soft vibrato, breathy edge."""
	rng = np.random.default_rng(seed)
	f = midi_hz(m)
	dur = 0.30
	t = tt(dur)
	glide = -2.5 * np.exp(-t / 0.035) + 0.5 * np.exp(-((t - 0.09) / 0.04) ** 2)
	vib = 0.18 * np.sin(2 * np.pi * 5.5 * t + rng.random()) * np.clip((t - 0.08) / 0.08, 0, 1)
	inst = f * 2.0 ** ((glide + vib) / 12.0)
	ph = 2 * np.pi * np.cumsum(inst) / SR
	y = np.sin(ph) + 0.30 * np.sin(2 * ph + 0.7) + 0.09 * np.sin(3 * ph + 1.9) + 0.03 * np.sin(4 * ph)
	amp = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.6 * np.minimum(1.0, t / 0.010)
	breath = lp(rng.standard_normal(len(t)), 900.0, 0.7, 2)
	y = y * amp + 0.025 * breath / (np.abs(breath).max() + 1e-12) * amp
	y = np.concatenate([y, np.zeros(int(0.08 * SR))])
	return _finish(y, 3600.0, 0.9, 0.14, seed, -58.0)


# ----------------------------------------------------------------------------- S14 tiny snore
def snore(seed: int) -> np.ndarray:
	"""Inhale (soft low noise swell) then exhale with a tiny whistle gliding A5 -> F5."""
	rng = np.random.default_rng(seed)
	inh_d, gap, exh_d = 0.55 + 0.1 * rng.random(), 0.12, 0.7
	t1 = tt(inh_d)
	inh = noise_band(len(t1), rng, 180.0, 650.0, 1.0) * np.sin(np.pi * t1 / inh_d) ** 2
	t2 = tt(exh_d)
	exh = 0.6 * noise_band(len(t2), rng, 250.0, 900.0, 1.0) * np.sin(np.pi * t2 / exh_d) ** 1.5
	fw = midi_hz(81) * 2.0 ** (-4.0 * (t2 / exh_d) / 12.0)
	whistle = 0.10 * np.sin(2 * np.pi * np.cumsum(fw) / SR) * np.sin(np.pi * t2 / exh_d) ** 3
	y = np.concatenate([inh, np.zeros(int(gap * SR)), exh + whistle, np.zeros(int(0.1 * SR))])
	return _finish(y, 2500.0, 0.8, 0.10, seed, -56.0)


# ----------------------------------------------------------------------------- S15 toggle click
def click(m: int, seed: int) -> np.ndarray:
	"""Felt switch: a 4 ms soft click plus a very short tuned body (pitch on a universal pc)."""
	rng = np.random.default_rng(seed)
	f = midi_hz(m)
	t = tt(0.22)
	body = np.sin(2 * np.pi * f * t) * np.exp(-t / 0.028) + 0.2 * np.sin(np.pi * f * t) * np.exp(-t / 0.02)
	nz = lp(rng.standard_normal(len(t)) * np.exp(-t / 0.0015), 1500.0, 0.7, 2)
	y = (0.8 * body + 0.25 * nz / (np.abs(nz).max() + 1e-12)) * env_ad(len(t), 1.0, 1e9)
	return _finish(y, 3500.0, 0.7, 0.08, seed, -58.0)


def glass_note(f: float, t60: float, seed: int, n_s: float | None = None) -> np.ndarray:
	"""Small glass/chime tone used inside composite SFX (no room; caller adds space)."""
	rng = np.random.default_rng(seed)
	dur = n_s if n_s is not None else min(2.5, 0.9 * t60)
	t = tt(dur)
	y = np.zeros_like(t)
	for k, (r, a) in enumerate(((1.0, 1.0), (2.7565, 0.2), (5.4039, 0.05))):
		if r * f > 6000.0:
			break
		for d in (-0.5, 0.5):
			y += a * np.sin(2 * np.pi * (r * f + d * rng.uniform(0.4, 1.2)) * t + 2 * np.pi * rng.random()) \
				* np.exp(-6.91 * t / (t60 / (1.0 + 1.6 * k)))
	return fade_in(y * env_ad(len(t), 1.2, 1e9), 1.0)
