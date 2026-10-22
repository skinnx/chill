"""Spectral and modulation analysis for the A2 "gentle spectrum" gates (00-SYNTHESIS §4).

A2: energy > 10 kHz <= 0.5 %; 2-5 kHz <= 5 % (<= 20 % for water); birds >= 15 dB under the bed;
no 1-16 Hz AM on bright noise.

Definitions (stated here because the gates depend on them):
- Band energy fraction: sum of |X(f)|^2 inside the band over the total, from one rFFT of the
  channel-summed power spectrum (whole file).
- Centroid: magnitude-weighted mean frequency, sum |X| f / sum |X| (06 §4.9 definition).
- Bright-noise AM index: the 2.5-5.5 kHz band (Kumar et al. 2008) is isolated, its Hilbert
  envelope is low-passed and decimated to 200 Hz, and the RMS of the envelope's 1-16 Hz
  component is divided by the mean envelope. Steady Gaussian noise reads ~0.04; a 2 dB
  peak-to-peak tremolo reads ~0.08; a deep scrape-like flutter reads > 0.5.
"""
from __future__ import annotations

import numpy as np
from scipy.signal import butter, hilbert, resample_poly, sosfiltfilt

from dsp import SR


def _power_spectrum(x: np.ndarray):
	x = np.atleast_2d(x)
	X = np.fft.rfft(x, axis=-1)
	p = (np.abs(X) ** 2).sum(axis=0)
	mag = np.abs(X).sum(axis=0)
	f = np.fft.rfftfreq(x.shape[-1], 1.0 / SR)
	return f, p, mag


def spectral_stats(x: np.ndarray) -> dict:
	f, p, mag = _power_spectrum(x)
	tot = p.sum() + 1e-30
	band = lambda lo, hi: float(p[(f >= lo) & (f < hi)].sum() / tot)
	return {
		"centroid_hz": float((mag * f).sum() / (mag.sum() + 1e-30)),
		"frac_above_10k": band(10000.0, SR / 2 + 1),
		"frac_2k_5k": band(2000.0, 5000.0),
		"frac_200_500": band(200.0, 500.0),
		"frac_below_150": band(0.0, 150.0),
	}


def bright_am_index(x: np.ndarray) -> tuple[float, float]:
	"""Return (energy fraction in 2.5-5.5 kHz, 1-16 Hz AM index of that band's envelope)."""
	m = np.atleast_2d(x).mean(axis=0)
	f, p, _ = _power_spectrum(m)
	frac = float(p[(f >= 2500) & (f < 5500)].sum() / (p.sum() + 1e-30))
	sos = butter(4, [2500.0, 5500.0], btype="bandpass", fs=SR, output="sos")
	band = sosfiltfilt(sos, m)
	env = np.abs(hilbert(band))
	env = resample_poly(env, 2, 441)  # -> 200 Hz
	env = env[100:-100] if env.size > 400 else env  # drop filter edge effects
	mean = env.mean() + 1e-30
	sos_m = butter(2, [1.0, 16.0], btype="bandpass", fs=200.0, output="sos")
	mod = sosfiltfilt(sos_m, env - mean)
	return frac, float(np.sqrt(np.mean(mod ** 2)) / mean)


def loop_seam(x: np.ndarray) -> float:
	"""Discontinuity at the wrap point: the second differences that straddle the seam
	(x[-2], x[-1], x[0] and x[-1], x[0], x[1]) relative to the 99.9th percentile of |second
	difference| inside the file. A click or step at the seam spikes the second difference;
	<= 1.0 means the wrap is as smooth as an ordinary sample inside the loop.
	"""
	x = np.atleast_2d(x)
	d2 = np.abs(np.diff(x, 2, axis=-1))
	typ = float(np.percentile(d2, 99.9)) + 1e-12
	a = np.abs(x[:, 0] - 2 * x[:, -1] + x[:, -2])
	b = np.abs(x[:, 1] - 2 * x[:, 0] + x[:, -1])
	return float(max(a.max(), b.max()) / typ)
