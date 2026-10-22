"""DSP primitives for the Mossling Meadow offline synthesis toolchain.

Everything here is deterministic: callers pass a numpy Generator seeded from the
asset id (see synth.seed_for). Recipes follow docs/research/06-audio-haptics.md §4.

Conventions
- Sample rate SR = 44100 (06 §0.1, D10). Signals are float64 numpy arrays,
  mono shape (n,) or stereo shape (2, n).
- "Loop-safe" helpers keep a signal exactly periodic so the file loops with no seam:
  periodic (FFT-shaped) noise, integer LFO cycles per loop, filters run over two
  periods (keep the second), block-modulated filters on 225-sample blocks
  (44100 = 225 * 196 and 70 BPM bars are 168 * 225 * 4 samples; synthesis C18),
  wrap-around event scattering, circular convolution reverbs.
"""
from __future__ import annotations

import numpy as np
from scipy.signal import lfilter, fftconvolve, resample_poly  # noqa: F401  (resample_poly re-exported)

SR = 44100
FILTER_BLOCK = 225  # samples; 44100 = 225 * 196, one 70 BPM beat = 37800 = 168 * 225


# ----------------------------------------------------------------------------- basics
def tt(dur_s: float) -> np.ndarray:
	"""Time axis in seconds for a duration (rounded to whole samples)."""
	return np.arange(int(round(dur_s * SR))) / SR


def midi_hz(m: float) -> float:
	return 440.0 * 2.0 ** ((m - 69.0) / 12.0)


def db(x: float) -> float:
	return 20.0 * np.log10(max(float(x), 1e-12))


def undb(d: float) -> float:
	return 10.0 ** (d / 20.0)


def raised_cos_in(n: int) -> np.ndarray:
	"""0 -> 1 raised-cosine ramp of n samples (sin^2)."""
	if n <= 0:
		return np.ones(0)
	return np.sin(0.5 * np.pi * (np.arange(n) + 0.5) / n) ** 2


def env_ad(n: int, attack_ms: float = 5.0, tau: float = 0.3) -> np.ndarray:
	"""Raised-cosine attack, then exponential decay with time constant tau (s)."""
	t = np.arange(n) / SR
	a = max(attack_ms, 1e-3) / 1000.0
	return np.where(t < a, np.sin(0.5 * np.pi * t / a) ** 2, np.exp(-(t - a) / tau))


def fade_out(x: np.ndarray, ms: float) -> np.ndarray:
	"""Cosine fade over the last `ms` milliseconds (in place on a copy)."""
	y = np.array(x, dtype=float, copy=True)
	n = min(int(ms * SR / 1000.0), y.shape[-1])
	if n > 0:
		y[..., -n:] *= np.cos(0.5 * np.pi * (np.arange(n) + 0.5) / n) ** 2
	return y


def fade_in(x: np.ndarray, ms: float) -> np.ndarray:
	y = np.array(x, dtype=float, copy=True)
	n = min(int(ms * SR / 1000.0), y.shape[-1])
	if n > 0:
		y[..., :n] *= raised_cos_in(n)
	return y


def pad_to(x: np.ndarray, n: int) -> np.ndarray:
	if x.shape[-1] >= n:
		return x[..., :n]
	pad = [(0, 0)] * (x.ndim - 1) + [(0, n - x.shape[-1])]
	return np.pad(x, pad)


def mix_at(out: np.ndarray, x: np.ndarray, start: int, gain: float = 1.0) -> None:
	"""Add x into out at sample offset `start` (truncating at the end). Mono or stereo."""
	if start >= out.shape[-1]:
		return
	n = min(x.shape[-1], out.shape[-1] - start)
	if out.ndim == 2 and x.ndim == 1:
		out[:, start:start + n] += gain * x[:n]
	else:
		out[..., start:start + n] += gain * x[..., :n]


def pan_mono(x: np.ndarray, pan: float) -> np.ndarray:
	"""Equal-power pan; pan in [0, 1], 0.5 = centre."""
	return np.stack([x * np.cos(pan * np.pi / 2.0), x * np.sin(pan * np.pi / 2.0)]) * np.sqrt(2.0)


def trim_tail(x: np.ndarray, floor_db: float = -66.0, fade_ms: float = 30.0, min_len_s: float = 0.05) -> np.ndarray:
	"""Cut the decayed tail below floor_db re peak, with a short cosine fade (one-shots only)."""
	mono = np.abs(x) if x.ndim == 1 else np.abs(x).max(axis=0)
	peak = mono.max()
	if peak <= 0:
		return x
	thr = peak * undb(floor_db)
	above = np.nonzero(mono > thr)[0]
	end = int(above[-1]) + 1 if above.size else x.shape[-1]
	end = max(end + int(fade_ms * SR / 1000.0), int(min_len_s * SR))
	end = min(end, x.shape[-1])
	return fade_out(x[..., :end], fade_ms)


# ----------------------------------------------------------------------------- filters
def rbj(kind: str, f0: float, q: float = 0.7071, gain_db: float = 0.0):
	"""RBJ Audio-EQ-Cookbook biquad coefficients (b, a), normalised by a0."""
	f0 = min(max(f0, 1.0), 0.49 * SR)
	w = 2.0 * np.pi * f0 / SR
	c, s = np.cos(w), np.sin(w)
	al = s / (2.0 * q)
	A = 10.0 ** (gain_db / 40.0)
	if kind == "lp":
		b, a = [(1 - c) / 2, 1 - c, (1 - c) / 2], [1 + al, -2 * c, 1 - al]
	elif kind == "hp":
		b, a = [(1 + c) / 2, -(1 + c), (1 + c) / 2], [1 + al, -2 * c, 1 - al]
	elif kind == "bp":
		b, a = [al, 0.0, -al], [1 + al, -2 * c, 1 - al]
	elif kind == "hshelf":
		sq = 2 * np.sqrt(A) * al
		b = [A * ((A + 1) + (A - 1) * c + sq), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - sq)]
		a = [(A + 1) - (A - 1) * c + sq, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - sq]
	elif kind == "lshelf":
		sq = 2 * np.sqrt(A) * al
		b = [A * ((A + 1) - (A - 1) * c + sq), 2 * A * ((A - 1) - (A + 1) * c), A * ((A + 1) - (A - 1) * c - sq)]
		a = [(A + 1) + (A - 1) * c + sq, -2 * ((A - 1) + (A + 1) * c), (A + 1) + (A - 1) * c - sq]
	elif kind == "peak":
		b = [1 + al * A, -2 * c, 1 - al * A]
		a = [1 + al / A, -2 * c, 1 - al / A]
	else:
		raise ValueError(kind)
	b, a = np.asarray(b, float), np.asarray(a, float)
	return b / a[0], a / a[0]


def filt(x: np.ndarray, ba) -> np.ndarray:
	return lfilter(ba[0], ba[1], x, axis=-1)


def filt_loop(x: np.ndarray, ba) -> np.ndarray:
	"""Seamless LTI filtering of a periodic signal: run 2 periods, keep the 2nd."""
	n = x.shape[-1]
	return filt(np.concatenate([x, x], -1), ba)[..., n:]


def lp(x: np.ndarray, fc: float, q: float = 0.7071, order2: int = 1) -> np.ndarray:
	"""Cascade of `order2` RBJ low-pass biquads (12 dB/oct each). One-shots only."""
	for _ in range(order2):
		x = filt(x, rbj("lp", fc, q))
	return x


def hp(x: np.ndarray, fc: float, q: float = 0.7071, order2: int = 1) -> np.ndarray:
	for _ in range(order2):
		x = filt(x, rbj("hp", fc, q))
	return x


def bp(x: np.ndarray, fc: float, q: float = 1.0) -> np.ndarray:
	return filt(x, rbj("bp", fc, q))


def lp_loop(x: np.ndarray, fc: float, q: float = 0.7071, order2: int = 1) -> np.ndarray:
	for _ in range(order2):
		x = filt_loop(x, rbj("lp", fc, q))
	return x


def hp_loop(x: np.ndarray, fc: float, q: float = 0.7071, order2: int = 1) -> np.ndarray:
	for _ in range(order2):
		x = filt_loop(x, rbj("hp", fc, q))
	return x


def mod_filter(x: np.ndarray, kind: str, fc: np.ndarray, q: float = 0.7071, block: int = FILTER_BLOCK) -> np.ndarray:
	"""Time-varying biquad, coefficients updated every `block` samples (state carried)."""
	out = np.empty_like(x)
	zi = np.zeros(x.shape[:-1] + (2,))
	for i in range(0, x.shape[-1], block):
		b, a = rbj(kind, float(fc[i]), q)
		out[..., i:i + block], zi = lfilter(b, a, x[..., i:i + block], axis=-1, zi=zi)
	return out


def mod_filter_loop(x: np.ndarray, kind: str, fc: np.ndarray, q: float = 0.7071) -> np.ndarray:
	"""Seamless time-varying filter on a periodic signal whose length is a multiple of FILTER_BLOCK."""
	n = x.shape[-1]
	assert n % FILTER_BLOCK == 0, "loop length must be a whole number of filter blocks"
	return mod_filter(np.concatenate([x, x], -1), kind, np.concatenate([fc, fc]), q)[..., n:]


# ----------------------------------------------------------------------------- sources
def noise_color(n: int, rng: np.random.Generator, alpha: float = 1.0) -> np.ndarray:
	"""1/f^alpha noise by FFT shaping. Periodic with period n, so it loops seamlessly."""
	X = np.fft.rfft(rng.standard_normal(n))
	f = np.fft.rfftfreq(n, 1.0 / SR)
	f[0] = f[1]
	x = np.fft.irfft(X / f ** (alpha / 2.0), n)
	return x / np.abs(x).max()


def noise_band(n: int, rng: np.random.Generator, f_lo: float, f_hi: float, alpha: float = 0.0,
		edge_oct: float = 0.5) -> np.ndarray:
	"""Periodic band-limited noise with smooth (raised-cosine, `edge_oct` octaves) band edges."""
	X = np.fft.rfft(rng.standard_normal(n))
	f = np.fft.rfftfreq(n, 1.0 / SR)
	f[0] = 1e-3
	lf = np.log2(f)
	lo, hi = np.log2(f_lo), np.log2(f_hi)
	w = np.ones_like(f)
	w = np.where(lf < lo, np.cos(0.5 * np.pi * np.clip((lo - lf) / edge_oct, 0, 1)) ** 2, w)
	w = np.where(lf > hi, np.cos(0.5 * np.pi * np.clip((lf - hi) / edge_oct, 0, 1)) ** 2, w)
	x = np.fft.irfft(X * w / f ** (alpha / 2.0), n)
	return x / (np.abs(x).max() + 1e-12)


def saw_blep(f: float, t: np.ndarray, ph0: float = 0.0) -> np.ndarray:
	"""PolyBLEP band-limited sawtooth."""
	dt = f / SR
	p = (ph0 + f * t) % 1.0
	y = 2.0 * p - 1.0
	m = p < dt
	x = p[m] / dt
	y[m] -= x + x - x * x - 1.0
	m = p > 1.0 - dt
	x = (p[m] - 1.0) / dt
	y[m] -= x * x + x + x + 1.0
	return y


def scatter(out: np.ndarray, g: np.ndarray, pos: int, gain: float, pan: float) -> None:
	"""Wrap-around add of a mono grain into a stereo loop buffer (keeps the loop seamless)."""
	idx = (pos + np.arange(len(g))) % out.shape[1]
	out[0, idx] += g * gain * np.cos(pan * np.pi / 2.0)
	out[1, idx] += g * gain * np.sin(pan * np.pi / 2.0)


# Minnaert resonance: f * R = sqrt(3 gamma P0 / rho) / (2 pi) = 3.29 m/s (06 §4.4)
MINNAERT = np.sqrt(3.0 * 1.4 * 101325.0 / 998.0) / (2.0 * np.pi)


def bubble(f0: float, tau: float, sigma: float = 0.1) -> np.ndarray:
	"""Damped sine whose pitch rises while it rings (van den Doel 2005 model shape)."""
	t = np.arange(int(SR * 6 * tau)) / SR
	f = f0 * (1.0 + sigma * t / tau)
	return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / tau) * (1.0 - np.exp(-t / 0.0004))


# ----------------------------------------------------------------------------- reverb
def synth_ir(rt60: float = 2.0, dur: float | None = None, predelay_ms: float = 12.0, seed: int = 7,
		dark: float = 0.45, xover_hz: float = 2500.0, stereo: bool = True) -> np.ndarray:
	"""Synthetic room IR: exponentially decaying noise, highs decay 1/dark times faster.

	Returns shape (2, n) if stereo else (n,). Energy-normalised (unit power sum per channel).
	"""
	rng = np.random.default_rng(seed)
	dur = dur if dur is not None else rt60 * 1.15
	t = tt(dur)
	e = lambda T: np.exp(-6.91 * t / T)
	chans = []
	for _ in range(2 if stereo else 1):
		z = rng.standard_normal(len(t))
		lo = filt(z, rbj("lp", xover_hz)) * e(rt60)
		hi = filt(z, rbj("hp", xover_hz)) * e(rt60 * dark)
		ir = (lo + hi) * (1.0 - np.exp(-t / 0.004))
		ir = filt(ir, rbj("lp", 6000.0))  # keep the room soft (A2 > 10 kHz gate)
		ir /= np.sqrt((ir ** 2).sum())
		chans.append(np.concatenate([np.zeros(int(SR * predelay_ms / 1000.0)), ir]))
	return np.stack(chans) if stereo else chans[0]


def reverb_oneshot(x: np.ndarray, ir: np.ndarray, wet: float, dry: float = 1.0) -> np.ndarray:
	"""Linear convolution reverb for one-shots. Output grows by the IR tail.

	mono x + mono ir -> mono; mono x + stereo ir -> stereo; stereo x + stereo ir -> stereo.
	"""
	if x.ndim == 1 and ir.ndim == 1:
		w = fftconvolve(x, ir)
		return dry * pad_to(x, len(w)) + wet * w
	xs = np.stack([x, x]) if x.ndim == 1 else x
	irs = np.stack([ir, ir]) if ir.ndim == 1 else ir
	w = np.stack([fftconvolve(xs[c], irs[c]) for c in (0, 1)])
	return dry * pad_to(xs, w.shape[-1]) + wet * w


def reverb_circular(x: np.ndarray, ir: np.ndarray, wet: float, dry: float = 1.0) -> np.ndarray:
	"""Circular convolution: the tail wraps into the loop start, so loops stay exactly periodic."""
	n = x.shape[-1]
	assert ir.shape[-1] <= n, "IR longer than loop"
	xs = np.stack([x, x]) if x.ndim == 1 else x
	irs = np.stack([ir, ir]) if ir.ndim == 1 else ir
	X = np.fft.rfft(xs, n, axis=-1)
	H = np.fft.rfft(irs, n, axis=-1)
	w = np.fft.irfft(X * H, n, axis=-1)
	return dry * xs + wet * w


# ----------------------------------------------------------------------------- misc
def lfo(t: np.ndarray, cycles: float, dur: float, phase: float = 0.0) -> np.ndarray:
	"""Sine LFO with an integer number of cycles per loop of length dur (seamless)."""
	return np.sin(2.0 * np.pi * cycles * t / dur + phase)


def loop_freq(f: float, dur: float) -> float:
	"""Round a frequency to the nearest k/dur Hz so a whole number of cycles fits the loop."""
	return max(1.0, round(f * dur)) / dur


def peak_normalise(x: np.ndarray, peak: float = 0.9) -> np.ndarray:
	m = np.abs(x).max()
	return x * (peak / m) if m > 0 else x


# ----------------------------------------------------------------------------- Godot reverb port
# Exact numpy port of servers/audio/effects/reverb_filter.cpp (Godot 4.7.2) as driven by
# AudioEffectReverb (audio_effect_reverb.cpp: left extra_spread_base 0, right 0.000521 s).
# Used to bake the Web twins of SFX (R14: the Web build applies no bus effects).
_GD_COMB = [0.025306122448979593, 0.026938775510204082, 0.028956916099773241, 0.03074829931972789,
	0.032244897959183672, 0.03380952380952381, 0.035306122448979592, 0.036666666666666667]
_GD_ALLPASS = [0.0051020408163265302, 0.007732426303854875, 0.01, 0.012607709750566893]


def _gd_comb(x: np.ndarray, size: int, fb: float, damp: float) -> np.ndarray:
	# out[n] = LP(fb * v[n-size]); v[n] = x[n] + out[n]; LP: o = o*(1-damp) + o_prev*damp
	v = np.zeros(len(x))
	o = np.zeros(len(x))
	zi = np.zeros(1)
	for i in range(0, len(x), size):
		j = min(i + size, len(x))
		delayed = v[i - size:j - size] if i >= size else np.zeros(j - i)
		blk, zi = lfilter([1.0 - damp], [1.0, -damp], fb * delayed, zi=zi)
		o[i:j] = blk
		v[i:j] = x[i:j] + blk
	return o


def _gd_allpass(x: np.ndarray, size: int, g: float = 0.7) -> np.ndarray:
	# aux = w[n-size]; w[n] = g*aux + x[n]; y[n] = aux - g*w[n]
	w = np.zeros(len(x))
	y = np.zeros(len(x))
	for i in range(0, len(x), size):
		j = min(i + size, len(x))
		aux = w[i - size:j - size] if i >= size else np.zeros(j - i)
		w[i:j] = g * aux + x[i:j]
		y[i:j] = aux - g * w[i:j]
	return y


def godot_reverb(x: np.ndarray, room_size: float = 0.5, damping: float = 0.25, spread: float = 0.8,
		hipass: float = 0.15, wet: float = 0.15, dry: float = 1.0, tail_s: float = 2.5) -> np.ndarray:
	"""AudioEffectReverb as configured on the SFX bus (06 §0.2), predelay_feedback = 0.

	With predelay_feedback = 0 the 'predelay' stage passes the input through unchanged
	(reverb_filter.cpp:76-85), so it is omitted. Input mono or stereo; output stereo with tail.
	"""
	xs = np.stack([x, x]) if x.ndim == 1 else x
	xs = np.concatenate([xs, np.zeros((2, int(tail_s * SR)))], axis=1)
	fb = min(max(0.7 + 0.28 * room_size, 0.7), 0.98)
	aux = (damping / 2.0 + 0.5) ** 2
	damp = float(np.exp(-2.0 * np.pi * aux * 10000.0 / SR))
	out = np.zeros_like(xs)
	for ch, spread_base in ((0, 0.0), (1, 0.000521)):
		extra = int(np.rint(spread_base * SR))
		inp = xs[ch]
		if hipass > 0:
			h = float(np.exp(-2.0 * np.pi * hipass * 6000.0 / SR))
			inp = lfilter([(1 + h) / 2, -(1 + h) / 2], [1.0, -h], inp)
		acc = np.zeros(xs.shape[1])
		for tun in _GD_COMB:
			size = int(np.rint(tun * SR)) + extra
			size -= int(np.rint(extra * (1.0 - spread)))
			acc += _gd_comb(inp, size, fb, damp)
		for tun in _GD_ALLPASS:
			size = int(np.rint(tun * SR)) + extra
			size -= int(np.rint(extra * (1.0 - spread)))
			acc = _gd_allpass(acc, size)
		out[ch] = acc * wet * 0.6 + xs[ch] * dry
	return out
