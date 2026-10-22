"""ITU-R BS.1770-4 / EBU R128 loudness metering (own implementation, cross-checked with pyloudnorm).

- K-weighting: +4 dB high shelf at 1.5 kHz (Q 0.7071) then 2nd-order high-pass at 38 Hz (Q 0.5),
  the same parameters pyloudnorm uses (06 §4.8); agreement is asserted by synth.py on long files.
- Mono is measured as dual-mono: Godot copies mono WAV to L and R
  (scene/resources/audio_stream_wav.cpp:206-211), so a mono file plays 3 dB louder than a
  single-channel BS.1770 reading would say.
- Integrated: 400 ms blocks, 75 % overlap, absolute gate -70 LUFS, relative gate -10 LU.
- Momentary max: loudest 400 ms window (10 ms hop) -- the SFX metric (06 §0.5 "LUFS-M").
- Short-term: 3 s windows, 100 ms hop (EBU Tech 3341). LRA per EBU Tech 3342.
- True peak: 4x oversampling (BS.1770-4 Annex 2), processed in chunks.
"""
from __future__ import annotations

import numpy as np
from scipy.signal import lfilter, resample_poly

from dsp import SR, rbj

_ABS_GATE = -70.0


def _as_stereo(x: np.ndarray) -> np.ndarray:
	x = np.atleast_2d(np.asarray(x, dtype=float))
	return np.vstack([x, x]) if x.shape[0] == 1 else x


def k_weight(x: np.ndarray) -> np.ndarray:
	b1, a1 = rbj("hshelf", 1500.0, 0.7071, 4.0)
	b2, a2 = rbj("hp", 38.0, 0.5)
	return lfilter(b2, a2, lfilter(b1, a1, x, axis=-1), axis=-1)


def _block_powers(x: np.ndarray, win_s: float, hop_s: float) -> np.ndarray:
	"""Mean-square per window, summed over channels (channel weights 1.0 for L/R)."""
	y = k_weight(_as_stereo(x))
	blk, hop = int(round(win_s * SR)), int(round(hop_s * SR))
	if y.shape[1] < blk:
		y = np.pad(y, ((0, 0), (0, blk - y.shape[1])))
	c = np.concatenate([np.zeros((y.shape[0], 1)), np.cumsum(y * y, axis=1)], axis=1)
	starts = np.arange(0, y.shape[1] - blk + 1, hop)
	return ((c[:, starts + blk] - c[:, starts]) / blk).sum(axis=0)


def _lufs(p) -> np.ndarray:
	return -0.691 + 10.0 * np.log10(np.asarray(p) + 1e-30)


def lufs_integrated(x: np.ndarray) -> float:
	z = _block_powers(x, 0.4, 0.1)
	z = z[_lufs(z) > _ABS_GATE]
	if z.size == 0:
		return -np.inf
	z = z[_lufs(z) > _lufs(z.mean()) - 10.0]
	return float(_lufs(z.mean()))


def lufs_momentary_max(x: np.ndarray) -> float:
	return float(_lufs(_block_powers(x, 0.4, 0.01).max()))


def lufs_shortterm_series(x: np.ndarray) -> np.ndarray:
	return _lufs(_block_powers(x, 3.0, 0.1))


def lufs_shortterm_max(x: np.ndarray) -> float:
	return float(lufs_shortterm_series(x).max())


def loudness_range(x: np.ndarray) -> float:
	s = lufs_shortterm_series(x)
	s = s[s > _ABS_GATE]
	if s.size == 0:
		return 0.0
	p = 10.0 ** ((s + 0.691) / 10.0)
	s = s[s > _lufs(p.mean()) - 20.0]
	return float(np.percentile(s, 95) - np.percentile(s, 10))


def true_peak_db(x: np.ndarray, chunk: int = 1 << 20) -> float:
	x = np.atleast_2d(np.asarray(x, dtype=float))
	pad = 64
	m = 0.0
	for i in range(0, x.shape[1], chunk):
		lo, hi = max(0, i - pad), min(x.shape[1], i + chunk + pad)
		y = resample_poly(x[:, lo:hi], 4, 1, axis=-1)
		m = max(m, float(np.abs(y).max()))
	return 20.0 * np.log10(max(m, 1e-12))


def sample_peak_db(x: np.ndarray) -> float:
	return 20.0 * np.log10(max(float(np.abs(x).max()), 1e-12))


def gain_to_integrated(x: np.ndarray, target: float) -> float:
	"""Linear gain that puts x at `target` LUFS-I (2 passes: gain shifts tails across the gate)."""
	g = 1.0
	for _ in range(2):
		g *= 10.0 ** ((target - lufs_integrated(x * g)) / 20.0)
	return g


def gain_to_momentary(x: np.ndarray, target: float) -> float:
	return 10.0 ** ((target - lufs_momentary_max(x)) / 20.0)


def pyloudnorm_integrated(x: np.ndarray) -> float:
	"""Reference reading with pyloudnorm 0.2.0 (dual-mono for mono input)."""
	import pyloudnorm  # imported lazily so the rest of the toolchain works without it
	meter = pyloudnorm.Meter(SR)
	return float(meter.integrated_loudness(_as_stereo(x).T))
