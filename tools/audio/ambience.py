"""Ambience beds (58.3 s = 68-beat seamless stereo loops) and bird one-shots (06 §4.4-§4.5).

Beds: meadow breeze (R-C1 wind + grass), stream trickle (R-C3 Minnaert bubbles), light rain
(R-C2 drops on a pond + leaf pats), night crickets (accent layer). All are exactly periodic:
FFT-shaped noise, integer-cycle LFOs, block-modulated filters over two periods, wrap-around
event scattering and circular-convolution reverb (dsp.py module notes). No thunder, ever (GDD §6.2).
"""
from __future__ import annotations

import numpy as np

from dsp import (MINNAERT, SR, bubble, fade_in, filt, hp, hp_loop, lfo, lp, lp_loop, mod_filter_loop,
	noise_band, noise_color, pan_mono, rbj, reverb_circular, reverb_oneshot, scatter, synth_ir, trim_tail, tt)

BED_BEATS = 68                        # 17 bars at 70 BPM = 58.29 s (06 asks ~60 s)
BED_SAMPLES = BED_BEATS * SR * 60 // 70   # 2 570 400 = 11 424 filter blocks
BED_SECONDS = BED_SAMPLES / SR
# Why 68 beats and not 60 s (= 70 beats): Godot loops a beat-tagged OGG at beat_count*60/bpm and
# needs >= 256 frames left in the current Vorbis packet there (fileio.ogg_loop_fade_room). With the
# 1024-frame long-block grid, 70 beats leaves 16 frames; 68 beats leaves 864.
assert BED_SAMPLES % 225 == 0 and BED_SAMPLES * 70 % (SR * 60) == 0


def _poisson_times(rng: np.random.Generator, rate_fn, rate_max: float, dur: float) -> np.ndarray:
	"""Inhomogeneous Poisson process by thinning; rate_fn(t) <= rate_max."""
	n = int(rate_max * dur * 1.3) + 16
	cand = np.cumsum(rng.exponential(1.0 / rate_max, n))
	cand = cand[cand < dur]
	keep = rng.random(cand.size) < rate_fn(cand) / rate_max
	return cand[keep]


def breeze(seed: int) -> np.ndarray:
	"""Soft wind through meadow grass: 1/f^1.5 noise band-passed at 240-780 Hz with slow gusts,
	plus a grass/leaf hush that swells only with the gusts (all LFOs well below 1 Hz)."""
	rng = np.random.default_rng(seed)
	n, dur = BED_SAMPLES, BED_SECONDS
	t = np.arange(n) / SR
	gust = 0.55 + 0.30 * lfo(t, 3, dur) + 0.15 * lfo(t, 8, dur, 1.3)
	chans = []
	for ch in (0, 1):
		src = noise_color(n, rng, 1.5)
		fc = 420.0 * 2.0 ** (0.9 * (0.6 * lfo(t, 5, dur, 2.1 + 0.5 * ch) + 0.4 * lfo(t, 11, dur, 0.4 + 0.3 * ch)))
		body = mod_filter_loop(src, "bp", fc, 1.3)
		body /= np.abs(body).max()
		grass = lp_loop(noise_band(n, rng, 700.0, 1800.0, 1.0), 2000.0, 0.6, 2)
		grass /= np.abs(grass).max()
		low = lp_loop(noise_color(n, rng, 2.0), 180.0, 0.6, 1)
		low /= np.abs(low).max()
		g = gust * (1.0 + 0.04 * lfo(t, 7, dur, 0.9 * ch))
		chans.append(body * g + 0.16 * grass * np.clip(g, 0, None) ** 2.2 + 0.10 * low * (0.7 + 0.3 * g))
	y = np.stack(chans)
	return hp_loop(y, 40.0, 0.7)


def stream(seed: int) -> np.ndarray:
	"""Quiet trickling stream: ~220 Minnaert bubbles/s (r 1.4-4.5 mm -> 0.73-2.35 kHz) over a
	soft band-limited flow bed; bubble density breathes on slow integer-cycle LFOs."""
	rng = np.random.default_rng(seed)
	n, dur = BED_SAMPLES, BED_SECONDS
	t = np.arange(n) / SR
	out = np.zeros((2, n))
	# flow bed
	for ch in (0, 1):
		bed = noise_band(n, rng, 280.0, 1500.0, 1.0)
		out[ch] += 0.30 * bed / np.abs(bed).max()
		low = lp_loop(noise_color(n, rng, 2.0), 260.0, 0.6, 1)
		out[ch] += 0.16 * low / np.abs(low).max()
	# riffles: a few fixed places in the stereo field, each with its own pitch centre
	riffles = [(0.22, 3.0e-3), (0.40, 2.3e-3), (0.58, 3.4e-3), (0.76, 2.6e-3), (0.52, 4.0e-3)]
	rate = lambda tt_: 220.0 * (1.0 + 0.22 * np.sin(2 * np.pi * 4 * tt_ / dur + 0.7) + 0.12 * np.sin(2 * np.pi * 9 * tt_ / dur))
	for t0 in _poisson_times(rng, rate, 220.0 * 1.34, dur):
		pan_c, r_c = riffles[rng.integers(len(riffles))]
		r = float(np.clip(r_c * np.exp(rng.normal(0.0, 0.28)), 1.4e-3, 4.5e-3))
		g = bubble(MINNAERT / r, rng.uniform(0.003, 0.009), 0.25)
		gain = 0.06 * min(rng.lognormal(0.0, 0.4), 2.0)
		scatter(out, g, int(t0 * SR), gain, float(np.clip(pan_c + rng.normal(0, 0.06), 0.05, 0.95)))
	out = lp_loop(out, 3800.0, 0.6, 2)
	out = reverb_circular(out, synth_ir(0.9, predelay_ms=8.0, seed=seed + 1, dark=0.4), 0.12)
	return hp_loop(out, 40.0, 0.7)


def rain(seed: int) -> np.ndarray:
	"""Light rain (never a storm): soft distant wash, ~26 drops/s on a pond (capped crest),
	~14 leaf pats/s and slow fat drips from the canopy."""
	rng = np.random.default_rng(seed)
	n, dur = BED_SAMPLES, BED_SECONDS
	out = np.zeros((2, n))
	for ch in (0, 1):
		wash = noise_band(n, rng, 300.0, 2600.0, 1.0)
		out[ch] += 0.20 * wash / np.abs(wash).max()
		low = lp_loop(noise_color(n, rng, 2.0), 300.0, 0.6, 1)
		out[ch] += 0.10 * low / np.abs(low).max()
	const = lambda rate: (lambda tt_: np.full_like(tt_, rate))
	for t0 in _poisson_times(rng, const(26.0), 26.0, dur):                 # drops on the pond
		r = rng.uniform(1.6e-3, 4.5e-3)
		g = bubble(MINNAERT / r, rng.uniform(0.005, 0.016), 0.1)
		scatter(out, g, int(t0 * SR), 0.20 * min(rng.lognormal(0.0, 0.5), 1.6), rng.uniform(0.1, 0.9))
	pat_len = int(0.02 * SR)
	for t0 in _poisson_times(rng, const(14.0), 14.0, dur):                 # pats on leaves
		z = rng.standard_normal(pat_len) * np.exp(-np.arange(pat_len) / (SR * rng.uniform(0.002, 0.004)))
		z = filt(z, rbj("lp", rng.uniform(1100.0, 2200.0), 0.7))
		scatter(out, z, int(t0 * SR), 0.05 * min(rng.lognormal(0.0, 0.4), 1.6), rng.uniform(0.05, 0.95))
	for t0 in _poisson_times(rng, const(1.2), 1.2, dur):                   # fat drips
		r = rng.uniform(4.0e-3, 6.0e-3)
		g = bubble(MINNAERT / r, rng.uniform(0.02, 0.035), 0.15)
		scatter(out, g, int(t0 * SR), 0.12 * min(rng.lognormal(0.0, 0.3), 1.4), rng.uniform(0.2, 0.8))
	out = lp_loop(out, 4200.0, 0.6, 2)
	out = reverb_circular(out, synth_ir(1.3, predelay_ms=10.0, seed=seed + 2, dark=0.4), 0.18)
	return hp_loop(out, 45.0, 0.7)


def crickets(seed: int) -> np.ndarray:
	"""Night crickets, distant and few (accent layer, mixed >= 15 dB under the bed).

	Tree-cricket-like carriers at 2.1-2.7 kHz (lower and softer than field crickets), pulse
	trains of 30-42 Hz grouped in chirps; each individual drifts in and out on 1-3 cycles/loop.
	"""
	rng = np.random.default_rng(seed)
	n, dur = BED_SAMPLES, BED_SECONDS
	out = np.zeros((2, n))
	t_all = np.arange(n) / SR
	for k in range(5):
		fc = rng.uniform(2100.0, 2700.0)
		pulse_hz = rng.uniform(30.0, 42.0)
		pulses = int(rng.integers(3, 6))
		period = rng.uniform(0.7, 1.25)
		pan = rng.uniform(0.1, 0.9)
		act_cycles, act_ph = int(rng.integers(1, 4)), rng.uniform(0, 2 * np.pi)
		gain = rng.uniform(0.5, 1.0)
		chirp_d = pulses / pulse_hz
		tc = tt(chirp_d)
		pulse_env = np.sin(np.pi * ((tc * pulse_hz) % 1.0)) ** 2 * np.sin(np.pi * tc / chirp_d) ** 0.5
		t0 = rng.uniform(0, period)
		while t0 < dur:
			act = 0.5 + 0.5 * np.sin(2 * np.pi * act_cycles * t0 / dur + act_ph)
			if act > 0.25:
				fdrift = fc * (1.0 + 0.002 * rng.normal())
				g = np.sin(2 * np.pi * fdrift * tc + rng.random() * 6.28) * pulse_env
				scatter(out, g, int(t0 * SR), gain * act, pan)
			t0 += period * rng.uniform(0.92, 1.08)
	out = lp_loop(out, 3600.0, 0.6, 2)
	out = hp_loop(out, 900.0, 0.7)
	out = reverb_circular(out, synth_ir(1.8, predelay_ms=25.0, seed=seed + 3, dark=0.35), 0.45)
	_ = t_all
	return out


# ----------------------------------------------------------------------------- birds (one-shots)
def _chirp(rng, f_hi: float, f_lo: float, dur: float, vib_hz: float = 30.0, vib: float = 60.0) -> np.ndarray:
	t = tt(dur)
	f = f_lo + (f_hi - f_lo) * np.exp(-t / (0.3 * dur)) + vib * np.sin(2 * np.pi * vib_hz * t)
	ph = 2 * np.pi * np.cumsum(f) / SR
	return np.sin(np.pi * t / dur) ** 2 * (np.sin(ph) + 0.10 * np.sin(2 * ph))


def _whistle(f0: float, f1: float, dur: float) -> np.ndarray:
	t = tt(dur)
	f = f0 + (f1 - f0) * t / dur
	return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / dur) ** 1.5


def bird(kind: str, seed: int) -> np.ndarray:
	"""Stereo bird phrase, distant and soft. kinds: warbler, feebee, trill, robin."""
	rng = np.random.default_rng(seed)
	parts: list[np.ndarray] = []
	gap = lambda a, b: np.zeros(int(SR * rng.uniform(a, b)))
	if kind == "warbler":       # 3-6 chirps, each ~3 % lower (06 R-D)
		base = rng.uniform(2100.0, 2800.0)
		for k in range(int(rng.integers(3, 7))):
			parts += [_chirp(rng, 1.4 * base * 0.97 ** k, base * 0.97 ** k, rng.uniform(0.05, 0.10)), gap(0.04, 0.11)]
	elif kind == "feebee":      # two clear whistles, the second a little lower
		f = rng.uniform(2700.0, 3200.0)
		parts += [_whistle(f, f * 0.98, rng.uniform(0.28, 0.36)), gap(0.08, 0.14),
			_whistle(f * 0.84, f * 0.82, rng.uniform(0.30, 0.40))]
	elif kind == "trill":       # short soft trill (tonal), 10-13 notes/s
		f = rng.uniform(2600.0, 3300.0)
		rate = rng.uniform(10.0, 13.0)
		for k in range(int(rng.integers(6, 10))):
			parts += [_chirp(rng, f * 1.15, f, 0.6 / rate, 0, 0), np.zeros(int(SR * 0.4 / rate))]
	elif kind == "robin":       # 3 syllables with up/down sweeps
		for k in range(3):
			a, b = rng.uniform(2000.0, 2600.0), rng.uniform(2700.0, 3400.0)
			up = rng.random() < 0.5
			parts += [_chirp(rng, b if up else a, a if up else b, rng.uniform(0.12, 0.2), 25.0, 40.0), gap(0.06, 0.15)]
	y = np.concatenate(parts + [np.zeros(int(0.05 * SR))])
	y = lp(hp(y, 1300.0, 0.7), 6000.0, 0.6, 2)
	y = fade_in(y, 3.0)
	st = pan_mono(y, rng.uniform(0.15, 0.85))
	st = reverb_oneshot(st, synth_ir(1.4, predelay_ms=18.0, seed=seed + 5, dark=0.35), 0.40)
	return trim_tail(st, -50.0, 80.0)
