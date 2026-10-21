#!/usr/bin/env python3
"""Ground-truth loop check: play every looping asset in Godot 4.7.2 and diff the capture.

For each pad, bed and purr loop in audio/manifest.json this script builds a throw-away Godot
project (in a temp dir), imports the audio, records the stream on Master with MovieWriter
(--write-movie, fixed 30 fps, 44.1 kHz, non-real-time), and compares the captured PCM with the
signal the toolchain predicts (fileio.ogg_as_played for OGG beat loops, the smpl body for WAV).
It fails if the residual near any loop point is larger than the residual elsewhere, i.e. if
Godot loops at a different point, truncates the loop fade, or clicks.

Usage (repo root; needs godot on PATH, xvfb-run, ffmpeg):
	python3 tools/audio/verify_loops_in_godot.py [--only GLOB]
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

import numpy as np  # noqa: E402

from dsp import SR  # noqa: E402
from fileio import decode_audio, ogg_as_played, read_wav16  # noqa: E402

PROJECT = """config_version=5

[application]
config/name="AudioLoopVerify"
config/features=PackedStringArray("4.7", "GL Compatibility")

[display]
window/size/viewport_width=64
window/size/viewport_height=64

[editor]
movie_writer/mix_rate=44100
movie_writer/fps=30

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
"""
PLAYER = """extends SceneTree

func _init() -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load(OS.get_cmdline_user_args()[0])
	root.add_child.call_deferred(p)
	p.ready.connect(p.play)
"""
FPS = 30


def capture(proj: str, res_path: str, seconds: float, out: str) -> np.ndarray:
	frames = int(seconds * FPS) + 3
	cmd = ["xvfb-run", "-a", "-s", "-screen 0 320x320x24", "godot", "--path", proj, "--rendering-driver", "opengl3_es",
		"--write-movie", out, "--fixed-fps", str(FPS), "--quit-after", str(frames), "-s", "res://player.gd", "--", res_path]
	subprocess.run(cmd, check=True, capture_output=True, timeout=900)
	raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", out, "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"],
		check=True, capture_output=True).stdout
	return np.frombuffer(raw, "<f4").astype(float).reshape(-1, 2).T


def compare(cap: np.ndarray, expected: np.ndarray, loop_points: list[int]) -> dict:
	seg = expected[0, :20000]
	errs = [np.abs(cap[0, o:o + 20000] - seg).max() for o in range(0, 6000)]
	off = int(np.argmin(errs))
	n = min(cap.shape[1] - off, expected.shape[1])
	r = np.abs(cap[:, off:off + n] - expected[:, :n]).max(axis=0)
	base = float(np.percentile(r, 99.99))
	near = [float(r[max(0, lp - 600):lp + 600].max()) for lp in loop_points if lp + 600 < n]
	return {"offset": off, "resid_p9999": base, "resid_max": float(r.max()), "near_loop": near, "loops_seen": len(near)}


def main() -> int:
	ap = argparse.ArgumentParser()
	ap.add_argument("--only", default=None)
	ap.add_argument("--keep", action="store_true", help="keep the temp project")
	args = ap.parse_args()
	with open(os.path.join(REPO, "audio", "manifest.json"), encoding="utf-8") as fh:
		man = json.load(fh)
	loops = [a for a in man["assets"] if a["loop"] and (not args.only or fnmatch.fnmatch(a["id"], args.only))]
	tmp = tempfile.mkdtemp(prefix="audio_loop_verify_")
	try:
		shutil.copytree(os.path.join(REPO, "audio"), os.path.join(tmp, "audio"),
			ignore=shutil.ignore_patterns("sfx_web"))
		with open(os.path.join(tmp, "project.godot"), "w") as fh:
			fh.write(PROJECT)
		with open(os.path.join(tmp, "player.gd"), "w") as fh:
			fh.write(PLAYER)
		subprocess.run(["godot", "--headless", "--path", tmp, "--import"], check=True, capture_output=True, timeout=900)
		fails = 0
		for a in loops:
			src = os.path.join(REPO, a["path"].replace("res://", ""))
			period = a["length_samples"]
			if src.endswith(".ogg"):
				d = decode_audio(src, 2)
				played = ogg_as_played(d, period)
				reps = 2 if a["kind"] == "pad" else 1
				expected = np.concatenate([d[:, :period]] + [played] * reps, axis=1)
				points = [period * (k + 1) for k in range(reps)]
				secs = (period * (reps + 0.1)) / SR
			else:
				w = read_wav16(src)
				b, e = a["loop_begin"], a["loop_end"]
				mono = np.concatenate([w[0, :e]] + [w[0, b:e]] * 3)
				expected = np.vstack([mono, mono])
				points = [e + k * (e - b) for k in range(3)]
				secs = expected.shape[1] / SR - 0.2
			cap = capture(tmp, a["path"], secs, os.path.join(tmp, a["id"] + ".avi"))
			c = compare(cap, expected, points)
			# Pass: Godot output equals the prediction everywhere (AVI is 16-bit: ~3e-5), and
			# the loop points are no worse than the rest of the file.
			ok = c["loops_seen"] == len(points) and c["resid_max"] < 1e-3 \
				and max(c["near_loop"], default=1.0) <= max(2.0 * c["resid_p9999"], 1e-4)
			fails += 0 if ok else 1
			print(f"{'PASS' if ok else 'FAIL'} {a['id']:22s} loops={c['loops_seen']} resid max {c['resid_max']:.1e} "
				f"p99.99 {c['resid_p9999']:.1e} near-loop {', '.join(f'{v:.1e}' for v in c['near_loop'])}")
		print(f"[verify] {len(loops) - fails}/{len(loops)} loops match Godot playback")
		return 1 if fails else 0
	finally:
		if not args.keep:
			shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
	sys.exit(main())
