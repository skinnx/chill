#!/usr/bin/env python3
"""Measure a capture (WAV/OGG/AVI from Godot MovieWriter, or any ffmpeg-readable file) against the
A1/A2 audio contract (00-SYNTHESIS §4; docs/AUDIO_BIBLE.md §3).

	python3 tools/audio/measure.py capture.avi            # print stats
	python3 tools/audio/measure.py capture.avi --gate     # exit 1 if A1/A2 fail (needs >= 10 min)

A1: -18 +-1 LUFS-I (CI hard fail beyond +-2), TP <= -1 dBTP, short-term <= -14 LUFS-S, LRA <= 8.
A2: > 10 kHz <= 0.5 % of energy (the 2-5 kHz limits apply per asset class, not to the mix).
"""
from __future__ import annotations

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from analysis import spectral_stats  # noqa: E402
from dsp import SR  # noqa: E402
from fileio import decode_audio  # noqa: E402
from loudness import loudness_range, lufs_integrated, lufs_momentary_max, lufs_shortterm_max, true_peak_db  # noqa: E402


def main() -> int:
	ap = argparse.ArgumentParser()
	ap.add_argument("file")
	ap.add_argument("--gate", action="store_true")
	ap.add_argument("--skip-s", type=float, default=0.0, help="ignore the first N seconds (boot fade-in)")
	a = ap.parse_args()
	x = decode_audio(a.file, 2)[:, int(a.skip_s * SR):]
	dur = x.shape[1] / SR
	st = {"seconds": round(dur, 1), "lufs_i": round(lufs_integrated(x), 2), "true_peak_dbtp": round(true_peak_db(x), 2),
		"lufs_s_max": round(lufs_shortterm_max(x), 2), "lufs_m_max": round(lufs_momentary_max(x), 2),
		"lra": round(loudness_range(x), 2)}
	sp = spectral_stats(x)
	st.update({"centroid_hz": round(sp["centroid_hz"]), "pct_above_10k": round(100 * sp["frac_above_10k"], 3),
		"pct_2k_5k": round(100 * sp["frac_2k_5k"], 2)})
	for k, v in st.items():
		print(f"{k:16s} {v}")
	if not a.gate:
		return 0
	fails = []
	if dur < 600.0:
		fails.append(f"capture is {dur:.0f} s; A1 needs >= 600 s of idle play")
	if abs(st["lufs_i"] + 18.0) > 2.0:
		fails.append(f"LUFS-I {st['lufs_i']} outside -18 +-2 (CI limit)")
	elif abs(st["lufs_i"] + 18.0) > 1.0:
		print("WARN  LUFS-I outside the +-1 LU target (inside the +-2 CI limit)")
	if st["true_peak_dbtp"] > -1.0:
		fails.append(f"true peak {st['true_peak_dbtp']} > -1 dBTP")
	if st["lufs_s_max"] > -14.0:
		fails.append(f"short-term max {st['lufs_s_max']} > -14")
	if st["lra"] > 8.0:
		fails.append(f"LRA {st['lra']} > 8")
	if st["pct_above_10k"] > 0.5:
		fails.append(f"{st['pct_above_10k']} % energy above 10 kHz > 0.5 %")
	for f in fails:
		print("FAIL ", f)
	return 1 if fails else 0


if __name__ == "__main__":
	sys.exit(main())
