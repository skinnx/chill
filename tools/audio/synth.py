#!/usr/bin/env python3
"""Mossling Meadow -- deterministic procedural audio build (numpy + scipy only).

Renders every audio asset into audio/{music,ambience,sfx,sfx_web}/, masters it to the loudness
contract, encodes (OGG Vorbis q4 for beds/pads/Web twins, 16-bit WAV for notes/SFX -> QOA import),
writes Godot .import parameters, runs the A1/A2 gates plus an offline mix simulation of the
AudioDirector, and writes audio/manifest.json and the stats appendix of docs/AUDIO_BIBLE.md.

Exit status is non-zero, with a FAIL table, if any gate fails; the manifest and the appendix are
then NOT updated (pass --force-write to inspect a failing build).

Usage (from the repo root):
	pip install -r tools/audio/requirements.txt
	python3 tools/audio/synth.py                 # full build, 4 workers
	python3 tools/audio/synth.py --only 'pad_*'  # re-render a subset (gates still run on all files)
	python3 tools/audio/synth.py --check         # no rendering: re-analyse files on disk + gates
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import multiprocessing as mp
import os
import sys
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

import numpy as np  # noqa: E402

import ambience  # noqa: E402
import cues as cue_table  # noqa: E402
import instruments  # noqa: E402
import music  # noqa: E402
import score  # noqa: E402
import sfx  # noqa: E402
import theory  # noqa: E402
from analysis import bright_am_index, loop_seam, spectral_stats  # noqa: E402
from dsp import SR, godot_reverb, undb  # noqa: E402
from fileio import (GODOT_OGG_LOOP_FADE, OGG_IMPORTER, WAV_DEFAULT_PARAMS, WAV_IMPORTER, decode_audio,  # noqa: E402
	encode_ogg, ogg_as_played, ogg_loop_fade_room, ogg_loop_layout, read_wav16, write_import, write_wav16)
from loudness import (gain_to_integrated, gain_to_momentary, loudness_range, lufs_integrated,  # noqa: E402
	lufs_momentary_max, pyloudnorm_integrated, sample_peak_db, true_peak_db)

BASE_SEED = 20261020
LONG_TARGET_LUFS = -18.0          # A1 / D10: every bed and pad file
LONG_TP_PRE_ENCODE = -1.5         # 06 §0.1: <= -1.5 dBTP before encoding
QOA_BYTES_PER_SAMPLE = 0.4        # QOA: 64-bit slice per 20 samples (+ small frame headers)
LOOP_ROTATION_TRIES = 12          # phases tried per loop to satisfy the Vorbis loop-fade gate

GATES = {
	"lufs_tol_lu": 1.0,             # C19: target +-1 LU (CI hard limit is +-2 LU; we gate at the target)
	"long_tp_max_dbtp": -1.0,       # A1, measured after Vorbis encoding
	"short_peak_max_dbfs": -6.0,    # 06 §0.5: SFX sample peak
	"short_tp_max_dbtp": -5.0,
	"above_10k_max": 0.005,         # A2
	"band_2_5k_max": {"tonal": 0.05, "foley": 0.05, "air": 0.05, "water": 0.20, "accent": 1.0},
	"am_index_max": 0.20,           # A2 "no 1-16 Hz AM on bright noise" (air/water beds)
	"am_band_min_frac": 0.01,       # ...applied when >= 1 % of energy is in 2.5-5.5 kHz
	"seam_max_float": 1.0,          # loop wrap step <= the 99.9th percentile step
	"seam_max_encoded": 2.0,        # after Vorbis/16-bit quantisation
	"meter_agreement_lu": 0.05,     # own BS.1770 vs pyloudnorm 0.2.0
	"cue_tol_lu": 1.5,              # cue heard loudness over every reachable note
	"mix_lufs_range": [-19.0, -17.0],   # A1: -18 +-1 LUFS-I, 10 min idle capture
	"mix_tp_max": -1.0,
	"mix_st_max": -14.0,            # A1 short-term ceiling
	"mix_lra_max": 8.0,             # 06 §0.1
	"accent_under_bed_db": 15.0,    # A2 birds (and crickets) >= 15 dB under the bed
	"shipped_mb_max": 12.0,
}


def seed_for(asset_id: str) -> int:
	return (zlib.crc32(asset_id.encode()) ^ BASE_SEED) & 0x7FFFFFFF


def slug(s: str) -> str:
	return "".join(ch.lower() if ch.isalnum() else "_" for ch in s).strip("_")


def res(path: str) -> str:
	return "res://" + path.replace(os.sep, "/")


# ============================================================================= registry
# bank -> (renderer, file-level LUFS-M target, default bus, spectral class, web twin?)
NOTE_BANKS = {
	"ep": (instruments.epiano, -20.0, "Music", "tonal"),
	"mar": (instruments.marimba, -21.0, "Music", "tonal"),
	"chime": (instruments.chime, -22.0, "Music", "tonal"),
	"shell": (instruments.shell, -23.0, "SFX", "tonal"),
}
NOTE_TILT_DB_PER_OCT = -1.5        # notes above C5 a little softer: gentle top end
PITCHED_SFX = {   # bank -> (renderer, file target, bus, class, web twin, cue)
	"plip": (instruments.plip, -21.0, "UI", "tonal", True, "S01"),
	"dew": (instruments.dew, -21.0, "SFX", "tonal", True, "S02"),
	"tok": (instruments.tok, -23.0, "UI", "tonal", False, "S08"),
	"coo": (instruments.coo, -25.0, "SFX", "tonal", True, "S13"),
}
VARIANT_SFX = {   # bank -> (renderer, count, file target, bus, class, web twin, cue)
	"bubbles": (sfx.bubbles, 4, -24.0, "SFX", "water", True, "S06"),
	"paper": (sfx.paper, 3, -25.0, "UI", "foley", False, "S07"),
	"soil": (sfx.soil, 3, -25.5, "SFX", "foley", True, "S05"),
	"rustle": (sfx.rustle, 3, -27.0, "SFX", "foley", True, "S18"),
	"swish": (sfx.swish, 2, -27.0, "SFX", "foley", True, "S19"),
	"boat": (sfx.boat, 2, -24.0, "SFX", "water", True, "S17"),
	"snore": (instruments.snore, 2, -30.0, "SFX", "foley", True, "S14"),
}
CHORD_SFX = {     # bank -> (renderer, file target, cue)
	"unfurl": (sfx.unfurl, -21.0, "S04"),
	"friend": (sfx.fanfare, -18.0, "S09"),
	"welcome": (sfx.welcome, -19.0, "S10"),
	"postcard": (sfx.postcard, -24.0, "S16"),
}
BIRDS = [("warbler", 1), ("warbler", 2), ("feebee", 1), ("feebee", 2), ("trill", 1), ("trill", 2),
	("robin", 1), ("robin", 2)]
BIRD_FILE_LUFS_M = -30.0
BEDS = [  # id, recipe, class, tags
	("amb_breeze", ambience.breeze, "air", {"layer": "wind", "weather": ["clear", "breeze", "rain"],
		"time_of_day": ["dawn", "day", "dusk", "night"]}),
	("amb_stream", ambience.stream, "water", {"layer": "water", "weather": ["clear", "breeze"],
		"time_of_day": ["dawn", "day", "dusk", "night"]}),
	("amb_rain", ambience.rain, "water", {"layer": "water", "weather": ["rain"],
		"time_of_day": ["dawn", "day", "dusk", "night"]}),
	("amb_crickets", ambience.crickets, "accent", {"layer": "critters", "weather": ["clear", "breeze"],
		"time_of_day": ["night"]}),
]


def registry() -> list[dict]:
	A: list[dict] = []
	tod_for_set = {"day": ["dawn", "day", "dusk"], "night": ["night"]}
	for c in theory.CHORDS:
		for style in ("day", "night"):
			aid = f"pad_{style}_{slug(c['clip'])}"
			A.append({"id": aid, "kind": "pad", "path": f"audio/music/pads/{aid}.ogg", "fmt": "ogg", "ch": 2,
				"bus": "Music", "loop": True, "recipe": ("pad", c["clip"], style), "target": ("I", LONG_TARGET_LUFS),
				"cls": "tonal", "tags": {"chord": c["name"], "clip": c["clip"], "pad_set": style,
					"time_of_day": tod_for_set[style], "voicing": c[style]}})
	for aid, _fn, cls, tags in BEDS:
		A.append({"id": aid, "kind": "bed", "path": f"audio/ambience/{aid}.ogg", "fmt": "ogg", "ch": 2,
			"bus": "Ambience", "loop": True, "recipe": ("bed", aid), "target": ("I", LONG_TARGET_LUFS),
			"cls": cls, "tags": tags})
	for i, (kind, var) in enumerate(BIRDS, 1):
		aid = f"amb_bird_{i:02d}_{kind}"
		A.append({"id": aid, "kind": "bird", "path": f"audio/ambience/birds/{aid}.wav", "fmt": "wav", "ch": 2,
			"bus": "Ambience", "loop": False, "recipe": ("bird", kind, var), "target": ("M", BIRD_FILE_LUFS_M),
			"cls": "accent", "bank": "bird", "variant": i,
			"tags": {"bird": kind, "time_of_day": ["dawn", "day", "dusk"], "weather": ["clear", "breeze", "rain"]}})
	for bank, (_fn, tgt, bus, cls) in NOTE_BANKS.items():
		notes = theory.SHELL_NOTES if bank == "shell" else theory.lydian_notes(*theory.BANK_RANGES[bank])
		for m in notes:
			aid = f"{bank}_{m:03d}"
			tilt = NOTE_TILT_DB_PER_OCT * max(0.0, (m - 72) / 12.0)
			A.append({"id": aid, "kind": "note", "path": f"audio/music/notes/{aid}.wav", "fmt": "wav", "ch": 1,
				"bus": bus, "loop": False, "recipe": ("note", bank, m), "target": ("M", tgt + tilt), "cls": cls,
				"bank": bank, "midi": m, "tags": {"note": theory.note_name(m)}})
	for bank, (_fn, tgt, bus, cls, web, cue) in PITCHED_SFX.items():
		for m in theory.lydian_notes(*theory.BANK_RANGES[bank]):
			aid = f"{cue.lower()}_{bank}_{m:03d}"
			A.append({"id": aid, "kind": "sfx", "path": f"audio/sfx/{aid}.wav", "fmt": "wav", "ch": 1, "bus": bus,
				"loop": False, "recipe": ("pitched", bank, m), "target": ("M", tgt), "cls": cls, "bank": bank,
				"midi": m, "web_twin": web, "cue": cue, "tags": {"note": theory.note_name(m)}})
	for m in theory.lydian_notes(*theory.BANK_RANGES["purr"]):
		aid = f"s03_purr_{m:03d}"
		A.append({"id": aid, "kind": "sfx", "path": f"audio/sfx/{aid}.wav", "fmt": "wav", "ch": 1, "bus": "SFX",
			"loop": True, "recipe": ("purr", m), "target": ("M", -23.0), "cls": "tonal", "bank": "purr", "midi": m,
			"web_twin": True, "cue": "S03", "tags": {"note": theory.note_name(m)}})
	for name, m in (("on", 81), ("off", 74)):
		aid = f"s15_click_{name}"
		A.append({"id": aid, "kind": "sfx", "path": f"audio/sfx/{aid}.wav", "fmt": "wav", "ch": 1, "bus": "UI",
			"loop": False, "recipe": ("click", m), "target": ("M", -25.0), "cls": "tonal", "bank": "click",
			"midi": m, "variant": name, "web_twin": False, "cue": "S15", "tags": {"note": theory.note_name(m)}})
	for bank, (_fn, count, tgt, bus, cls, web, cue) in VARIANT_SFX.items():
		for v in range(1, count + 1):
			aid = f"{cue.lower()}_{bank}_{v}"
			A.append({"id": aid, "kind": "sfx", "path": f"audio/sfx/{aid}.wav", "fmt": "wav", "ch": 1, "bus": bus,
				"loop": False, "recipe": ("variant", bank, v), "target": ("M", tgt), "cls": cls, "bank": bank,
				"variant": v, "web_twin": web, "cue": cue, "tags": {}})
	for bank, (_fn, tgt, cue) in CHORD_SFX.items():
		for c in theory.CHORDS:
			aid = f"{cue.lower()}_{bank}_{slug(c['clip'])}"
			A.append({"id": aid, "kind": "sfx", "path": f"audio/sfx/{aid}.wav", "fmt": "wav", "ch": 1, "bus": "SFX",
				"loop": False, "recipe": ("chord", bank, c["clip"]), "target": ("M", tgt), "cls": "tonal",
				"bank": bank, "clip": c["clip"], "web_twin": True, "cue": cue, "tags": {"chord": c["name"]}})
	for a in A:
		a.setdefault("base_volume_db", 0.0)
		a.setdefault("web_twin", False)
		if a.get("web_twin"):
			a["web_path"] = "audio/sfx_web/" + os.path.splitext(os.path.basename(a["path"]))[0] + ".ogg"
	ids = [a["id"] for a in A]
	assert len(ids) == len(set(ids)), "duplicate asset ids"
	return A


# ============================================================================= rendering (worker)
BED_FN = {aid: fn for aid, fn, _c, _t in BEDS}


def render(a: dict, seed: int):
	r = a["recipe"]
	if r[0] == "pad":
		c = theory.CHORD_BY_CLIP[r[1]]
		return music.pad(c[r[2]], r[2], seed), None
	if r[0] == "bed":
		return BED_FN[r[1]](seed), None
	if r[0] == "bird":
		return ambience.bird(r[1], seed), None
	if r[0] == "note":
		return NOTE_BANKS[r[1]][0](r[2], seed), None
	if r[0] == "pitched":
		return PITCHED_SFX[r[1]][0](r[2], seed), None
	if r[0] == "purr":
		return instruments.purr(r[1], seed)
	if r[0] == "click":
		return instruments.click(r[1], seed), None
	if r[0] == "variant":
		return VARIANT_SFX[r[1]][0](seed), None
	if r[0] == "chord":
		return CHORD_SFX[r[1]][0](r[2], seed), None
	raise ValueError(r)


def _abs(p: str) -> str:
	return os.path.join(REPO, p)


def _file_md5(p: str) -> str:
	with open(p, "rb") as fh:
		return hashlib.md5(fh.read()).hexdigest()


def _web_twin(x: np.ndarray, loop) -> np.ndarray:
	"""Bake the SFX-bus reverb (exact port) for the Web build, where bus effects are not applied.

	Loops (purr) are tiled to 4 periods so the Web restart-on-`ended` gap (see AUDIO_BIBLE §9)
	happens at most every ~8 s of continuous petting.
	"""
	p = score.BUSES[3]["effects"][0]["props"]
	if loop is not None:
		begin, end = loop
		body = x[begin:end]
		x = np.concatenate([x[:begin]] + [body] * 4)
		return godot_reverb(x, p["room_size"], p["damping"], p["spread"], p["hipass"], p["wet"], p["dry"], 0.0)
	y = godot_reverb(x, p["room_size"], p["damping"], p["spread"], p["hipass"], p["wet"], p["dry"], 1.6)
	from dsp import trim_tail
	return trim_tail(y, -62.0, 40.0)


def analyse(x: np.ndarray, a: dict) -> dict:
	s = spectral_stats(x)
	st = {"length_samples": int(x.shape[-1]), "seconds": round(x.shape[-1] / SR, 4),
		"centroid_hz": round(s["centroid_hz"], 1), "frac_above_10k": s["frac_above_10k"],
		"frac_2k_5k": s["frac_2k_5k"], "frac_200_500": s["frac_200_500"],
		"true_peak_dbtp": round(true_peak_db(x), 2), "sample_peak_dbfs": round(sample_peak_db(x), 2)}
	if a["kind"] in ("pad", "bed"):
		st["lufs_i"] = round(lufs_integrated(x), 2)
		st["lra"] = round(loudness_range(np.concatenate([x, x], -1)), 2)
		st["lufs_m_max"] = round(lufs_momentary_max(x), 2)
	else:
		st["lufs_m_max"] = round(lufs_momentary_max(x), 2)
	if a["cls"] in ("air", "water") and a["kind"] == "bed":
		frac, am = bright_am_index(x)
		st["bright_frac"] = frac
		st["am_index"] = round(am, 4)
	return st


def ogg_import_params(a: dict, period: int) -> dict:
	"""Beat-based looping (see fileio.GODOT_OGG_LOOP_FADE): beat_count * 60 / bpm == period."""
	beats = period * theory.BPM // (SR * 60)
	assert beats * SR * 60 == period * theory.BPM, "loop must be a whole number of 70 BPM beats"
	return {"loop": "true", "loop_offset": "0", "bpm": str(theory.BPM), "beat_count": str(beats),
		"bar_beats": str(theory.BAR_BEATS)}


def _analyse_ogg_loop(dec: np.ndarray, period: int, a: dict) -> dict:
	played = ogg_as_played(dec, period)
	st = analyse(played, a)
	st["seam"] = round(loop_seam(played), 3)
	st["file_samples"] = int(dec.shape[-1])
	st["expected_samples"] = period + GODOT_OGG_LOOP_FADE
	st["length_samples"] = period
	st["beat_count"] = period * theory.BPM // (SR * 60)
	return st


def build_one(a: dict) -> dict:
	t0 = time.time()
	seed = seed_for(a["id"])
	x, loop = render(a, seed)
	x = np.asarray(x, dtype=float)
	mode, target = a["target"]
	body = x[..., loop[0]:loop[1]] if loop else x
	g = gain_to_integrated(body, target) if mode == "I" else gain_to_momentary(body, target)
	x = x * g
	ceiling_note = ""
	if a["kind"] in ("pad", "bed"):
		tp = true_peak_db(x)
		if tp > LONG_TP_PRE_ENCODE:
			x *= undb(LONG_TP_PRE_ENCODE - tp)
			ceiling_note = f"TP-limited by {tp - LONG_TP_PRE_ENCODE:.2f} dB"
	else:
		sp = sample_peak_db(x)
		if sp > GATES["short_peak_max_dbfs"]:
			x *= undb(GATES["short_peak_max_dbfs"] - 0.05 - sp)
			ceiling_note = f"peak-limited by {sp - GATES['short_peak_max_dbfs']:.2f} dB"
	out = {"id": a["id"], "pre": {}, "post": {}, "note": ceiling_note}
	if a["kind"] in ("pad", "bed"):
		out["pre"]["seam"] = round(loop_seam(x), 3)
		out["pre"]["true_peak_dbtp"] = round(true_peak_db(x), 2)
		out["pre"]["lufs_i"] = round(lufs_integrated(x), 3)
		out["pre"]["lufs_i_pyloudnorm"] = round(pyloudnorm_integrated(x), 3)
	path = _abs(a["path"])
	if a["fmt"] == "ogg":
		period = int(x.shape[-1])
		room, rot = 0, 0
		for k in range(LOOP_ROTATION_TRIES):
			# A periodic loop may start at any phase; rotate until Godot gets its full 256-frame fade.
			rot = (k * period) // LOOP_ROTATION_TRIES
			encode_ogg(path, ogg_loop_layout(np.roll(x, -rot, axis=-1)))
			room = ogg_loop_fade_room(path, period)
			if room >= GODOT_OGG_LOOP_FADE:
				break
		dec = decode_audio(path, a["ch"])
		out["post"] = _analyse_ogg_loop(dec, period, a)
		out["post"]["loop_fade_room"] = room
		out["post"]["loop_rotation"] = rot
		write_import(path, OGG_IMPORTER, ogg_import_params(a, period))
	else:
		write_wav16(path, x, seed, loop)
		dec = read_wav16(path)
		if loop:
			body_dec = dec[:, loop[0]:loop[1]]
			st = analyse(body_dec, a)
			st["loop_begin"], st["loop_end"] = int(loop[0]), int(loop[1])
			st["seam"] = round(loop_seam(body_dec), 3)
			st["guard_ok"] = bool(np.array_equal(dec[:, loop[1]], dec[:, loop[0]]))
			st["length_samples"] = int(dec.shape[-1])
			out["post"] = st
		else:
			out["post"] = analyse(dec, a)
		write_import(path, WAV_IMPORTER, dict(WAV_DEFAULT_PARAMS))
	out["post"]["bytes"] = os.path.getsize(path)
	out["post"]["md5"] = _file_md5(path)
	if a.get("web_twin"):
		w = _web_twin(x if x.ndim == 1 else x.mean(0), loop)
		sp = sample_peak_db(w)
		if sp > GATES["short_peak_max_dbfs"]:
			w *= undb(GATES["short_peak_max_dbfs"] - 0.05 - sp)
		wp = _abs(a["web_path"])
		encode_ogg(wp, w)
		wd = decode_audio(wp, 2)
		out["web"] = {"lufs_m_max": round(lufs_momentary_max(wd), 2), "true_peak_dbtp": round(true_peak_db(wd), 2),
			"bytes": os.path.getsize(wp), "seconds": round(wd.shape[-1] / SR, 3)}
		write_import(wp, OGG_IMPORTER, {"loop": "true" if loop else "false", "loop_offset": "0", "bpm": "0",
			"beat_count": "0", "bar_beats": "4"})
	out["render_s"] = round(time.time() - t0, 2)
	return out


def check_one(a: dict) -> dict:
	"""--check: re-analyse a file already on disk (no rendering)."""
	path = _abs(a["path"])
	out = {"id": a["id"], "pre": {}, "post": {}, "note": "checked from disk"}
	if a["fmt"] == "ogg":
		dec = decode_audio(path, a["ch"])
		period = theory.PAD_SAMPLES if a["kind"] == "pad" else ambience.BED_SAMPLES
		out["post"] = _analyse_ogg_loop(dec, period, a)
		out["post"]["loop_fade_room"] = ogg_loop_fade_room(path, period)
		played = ogg_as_played(dec, period)
		out["pre"] = {"lufs_i": out["post"]["lufs_i"], "lufs_i_pyloudnorm": round(pyloudnorm_integrated(played), 3),
			"seam": out["post"]["seam"], "true_peak_dbtp": out["post"]["true_peak_dbtp"]}
	else:
		dec = read_wav16(path)
		if a.get("loop"):
			import struct
			raw = open(path, "rb").read()
			i = raw.find(b"smpl")
			b, e = struct.unpack("<II", raw[i + 52:i + 60])   # 'smpl', size, 9 header dwords, cue id, type
			body = dec[:, b:e]
			out["post"] = analyse(body, a)
			out["post"].update({"loop_begin": b, "loop_end": e, "guard_ok": bool(np.array_equal(dec[:, e], dec[:, b])),
				"seam": 0.0, "length_samples": int(dec.shape[-1])})
		else:
			out["post"] = analyse(dec, a)
	out["post"]["bytes"] = os.path.getsize(path)
	out["post"]["md5"] = _file_md5(path)
	if a.get("web_twin"):
		wp = _abs(a["web_path"])
		wd = decode_audio(wp, 2)
		out["web"] = {"lufs_m_max": round(lufs_momentary_max(wd), 2), "true_peak_dbtp": round(true_peak_db(wd), 2),
			"bytes": os.path.getsize(wp), "seconds": round(wd.shape[-1] / SR, 3)}
	return out


# ============================================================================= gates
def gate_assets(assets: list[dict], stats: dict[str, dict]) -> list[tuple[str, str, str]]:
	fails: list[tuple[str, str, str]] = []
	G = GATES
	for a in assets:
		s = stats[a["id"]]
		p = s["post"]
		fail = lambda gate, msg: fails.append((a["id"], gate, msg))
		mode, target = a["target"]
		if mode == "I":
			if abs(p["lufs_i"] - target) > G["lufs_tol_lu"]:
				fail("A1 loudness", f"LUFS-I {p['lufs_i']} vs {target} +-{G['lufs_tol_lu']}")
			if p["true_peak_dbtp"] > G["long_tp_max_dbtp"]:
				fail("A1 true peak", f"{p['true_peak_dbtp']} dBTP > {G['long_tp_max_dbtp']}")
			if p.get("loop_fade_room", 0) < GODOT_OGG_LOOP_FADE:
				fail("loop fade", f"Godot can read only {p.get('loop_fade_room')} of 256 loop-fade frames (packet boundary)")
			if p["file_samples"] != p["expected_samples"]:
				fail("loop length", f"file {p['file_samples']} != {p['expected_samples']} samples (period + 256)")
			if s["pre"] and s["pre"]["seam"] > G["seam_max_float"]:
				fail("loop seam", f"pre-encode seam {s['pre']['seam']}")
			if p["seam"] > G["seam_max_encoded"]:
				fail("loop seam", f"encoded seam {p['seam']}")
			if s["pre"] and abs(s["pre"]["lufs_i"] - s["pre"]["lufs_i_pyloudnorm"]) > G["meter_agreement_lu"]:
				fail("meter", f"own {s['pre']['lufs_i']} vs pyloudnorm {s['pre']['lufs_i_pyloudnorm']}")
			if a["kind"] == "pad" and p["length_samples"] != theory.PAD_SAMPLES:
				fail("C18 bars", "pad is not exactly 8 bars at 70 BPM")
		else:
			if abs(p["lufs_m_max"] - target) > G["lufs_tol_lu"]:
				fail("loudness", f"LUFS-M {p['lufs_m_max']} vs {target:.1f} +-{G['lufs_tol_lu']}")
			if p["sample_peak_dbfs"] > G["short_peak_max_dbfs"] + 0.01:
				fail("peak", f"{p['sample_peak_dbfs']} dBFS > {G['short_peak_max_dbfs']}")
			if p["true_peak_dbtp"] > G["short_tp_max_dbtp"]:
				fail("true peak", f"{p['true_peak_dbtp']} dBTP > {G['short_tp_max_dbtp']}")
			if a.get("loop"):
				if not p.get("guard_ok"):
					fail("loop guard", "guard frame != loop_begin frame")
				if p["seam"] > G["seam_max_encoded"]:
					fail("loop seam", f"{p['seam']}")
			if a.get("web_twin") and s.get("web", {}).get("true_peak_dbtp", -99) > G["long_tp_max_dbtp"]:
				fail("web twin TP", f"{s['web']['true_peak_dbtp']} dBTP")
		if p["frac_above_10k"] > G["above_10k_max"]:
			fail("A2 >10 kHz", f"{100 * p['frac_above_10k']:.3f} % > {100 * G['above_10k_max']} %")
		lim = G["band_2_5k_max"][a["cls"]]
		if p["frac_2k_5k"] > lim:
			fail("A2 2-5 kHz", f"{100 * p['frac_2k_5k']:.2f} % > {100 * lim:.0f} % ({a['cls']})")
		if "am_index" in p and p["bright_frac"] >= G["am_band_min_frac"] and p["am_index"] > G["am_index_max"]:
			fail("A2 AM 1-16 Hz", f"index {p['am_index']} > {G['am_index_max']}")
	return fails


# ============================================================================= cues
def build_cues(assets: list[dict], stats: dict[str, dict]) -> tuple[dict, list[tuple[str, str, str]], dict]:
	"""Resolve each cue layer to a bank and a gain; check heard loudness over every reachable file."""
	by_bank: dict[str, list[dict]] = {}
	for a in assets:
		if a.get("bank"):
			by_bank.setdefault(a["bank"], []).append(a)
	fails: list[tuple[str, str, str]] = []
	report: dict[str, dict] = {}
	out: dict[str, dict] = {}
	for cid, c in cue_table.CUES.items():
		cc = json.loads(json.dumps(c))
		for li, layer in enumerate(cc["layers"]):
			bank = layer["bank"]
			files = by_bank[bank]
			heard = layer.get("heard_lufs_m", c["heard_lufs_m"])
			bus = c["bus"]
			rule = layer["pitch"]
			cand = files
			lo_hi = rule.get("range")
			if rule["rule"] == "fixed" and "midi" in rule:
				cand = [f for f in files if f.get("midi") == rule["midi"]]
			elif lo_hi:
				cand = [f for f in files if lo_hi[0] <= f.get("midi", -1) <= lo_hi[1]]
			levels = np.array([stats[f["id"]]["post"]["lufs_m_max"] for f in cand])
			ref = float(np.median(levels))
			gain = round(heard - ref - score.BUS_GAIN[bus], 2)
			layer["gain_db"] = gain
			heard_all = levels + gain + score.BUS_GAIN[bus]
			spread = (float(heard_all.min()), float(heard_all.max()))
			report[f"{cid}.{li}"] = {"bank": bank, "files": len(cand), "gain_db": gain, "heard_target": heard,
				"heard_min": round(spread[0], 2), "heard_max": round(spread[1], 2)}
			if max(abs(spread[0] - heard), abs(spread[1] - heard)) > GATES["cue_tol_lu"]:
				fails.append((cid, "cue loudness", f"layer {bank}: heard {spread[0]:.1f}..{spread[1]:.1f} vs {heard}"))
			if "gust_heard_lufs_m" in c:
				layer["gust_gain_db"] = round(c["gust_heard_lufs_m"] - ref - score.BUS_GAIN[c["gust_bus"]], 2)
			if "nap_offset_db" in c:
				layer["nap_gain_db"] = round(gain + c["nap_offset_db"], 2)
		out[cid] = cc
	return out, fails, report


def composite_cue_checks(cues: dict, stats: dict) -> tuple[list, dict]:
	"""Render multi-note / multi-layer cues offline at representative pitches and measure them."""
	import mixsim
	from mixsim import load_asset_audio
	mixsim.PATHS.update({a["id"]: res(a["path"]) for a in registry()})
	fails, rep = [], {}
	_ = stats

	def heard_of(parts: list[tuple[str, float, float]], bus: str) -> float:
		n = int(SR * 2.5)
		y = np.zeros(n)
		for aid, t0, gdb in parts:
			x = load_asset_audio(aid)
			x = x.mean(0) if x.ndim == 2 else x
			i = int(t0 * SR)
			k = min(len(x), n - i)
			y[i:i + k] += x[:k] * undb(gdb)
		return lufs_momentary_max(y) + score.BUS_GAIN[bus]

	s05 = cues["S05"]["layers"]
	v = heard_of([("s05_soil_1", 0.0, s05[0]["gain_db"]), ("mar_060", 0.0, s05[1]["gain_db"])], "SFX")
	rep["S05 soil+mar C4"] = round(v, 2)
	if abs(v - cues["S05"]["heard_lufs_m"]) > GATES["cue_tol_lu"]:
		fails.append(("S05", "cue loudness", f"composite {v:.1f} vs {cues['S05']['heard_lufs_m']}"))
	g12 = cues["S12"]["layers"][0]["gain_db"]
	v = heard_of([("ep_067", 0.0, g12), ("ep_074", 0.14, g12)], "SFX")
	rep["S12 arrive G4->D5"] = round(v, 2)
	if abs(v - cues["S12"]["heard_lufs_m"]) > GATES["cue_tol_lu"]:
		fails.append(("S12", "cue loudness", f"composite {v:.1f} vs {cues['S12']['heard_lufs_m']}"))
	g21 = cues["S21"]["layers"][0]["gain_db"]
	run = [("shell_086", 0.0, g21), ("shell_081", 0.11, g21 - 1.5), ("shell_077", 0.22, g21 - 3.0),
		("shell_074", 0.33, g21 - 4.5), ("shell_069", 0.44, g21 - 6.0)]
	v = heard_of(run, "SFX")
	rep["S21 tap run (5 shells)"] = round(v, 2)
	if abs(v - cues["S21"]["heard_lufs_m"]) > GATES["cue_tol_lu"] + 1.0:
		fails.append(("S21", "cue loudness", f"tap run {v:.1f} vs {cues['S21']['heard_lufs_m']}"))
	return fails, rep


# ============================================================================= manifest
def phase_profiles() -> dict:
	with open(os.path.join(REPO, "data", "world.json"), encoding="utf-8") as fh:
		w = json.load(fh)
	return {p["id"]: {"audio_profile": p["audio_profile"], "start_s": p["start_s"]} for p in w["phases"]}


def build_manifest(assets: list[dict], stats: dict, cues: dict) -> dict:
	banks: dict[str, dict] = {}
	for a in assets:
		b = a.get("bank")
		if a["kind"] == "pad":
			continue
		if not b:
			continue
		e = banks.setdefault(b, {"bus": a["bus"], "kind": a["kind"]})
		if "midi" in a and b != "click":
			e.setdefault("notes", {})[str(a["midi"])] = res(a["path"])
			if a.get("web_path"):
				e.setdefault("web_notes", {})[str(a["midi"])] = res(a["web_path"])
			e["range"] = [min(int(k) for k in e["notes"]), max(int(k) for k in e["notes"])]
		elif "clip" in a:
			e.setdefault("clips", {})[a["clip"]] = res(a["path"])
			if a.get("web_path"):
				e.setdefault("web_clips", {})[a["clip"]] = res(a["web_path"])
		else:
			key = str(a.get("variant"))
			e.setdefault("variants", {})[key] = res(a["path"])
			if a.get("web_path"):
				e.setdefault("web_variants", {})[key] = res(a["web_path"])
		if a.get("loop"):
			e["loop"] = True
	chords = []
	for c in theory.CHORDS:
		chords.append({"name": c["name"], "clip": c["clip"], "pcs": c["pcs"], "root_pc": c["root_pc"],
			"fifth_pc": c["fifth_pc"], "voicing_day": c["day"], "voicing_night": c["night"],
			"pad_clips": {s: f"pad_{s}_{slug(c['clip'])}" for s in ("day", "night")}})
	alist = []
	for a in assets:
		p = stats[a["id"]]["post"]
		e = {"id": a["id"], "path": res(a["path"]), "kind": a["kind"], "bus": a["bus"], "loop": bool(a["loop"]),
			"channels": a["ch"], "base_volume_db": a["base_volume_db"], "length_samples": p["length_samples"],
			"tags": a["tags"]}
		for k in ("bank", "midi", "clip", "variant", "cue"):
			if k in a:
				e[k] = a[k]
		if a.get("web_path"):
			e["web_path"] = res(a["web_path"])
		if a["kind"] in ("pad", "bed"):
			e["lufs_i"] = p["lufs_i"]
		else:
			e["lufs_m_max"] = p["lufs_m_max"]
		e["true_peak_dbtp"] = p["true_peak_dbtp"]
		if a.get("loop") and a["fmt"] == "wav":
			e["loop_begin"], e["loop_end"] = p["loop_begin"], p["loop_end"]
		alist.append(e)
	return {
		"schema": 1,
		"generator": "tools/audio/synth.py",
		"doc": "Audio contract for the AudioDirector autoload. See docs/AUDIO_BIBLE.md. Generated: do not edit; change tools/audio/*.py and re-run.",
		"sample_rate": SR, "seed": BASE_SEED,
		"loudness": {"mix_lufs_i": -18.0, "tolerance_lu": 1.0, "ci_fail_lu": 2.0, "true_peak_dbtp": -1.0,
			"short_term_max": -14.0, "long_file_lufs_i": LONG_TARGET_LUFS, "sfx_peak_dbfs": -6.0,
			"metering": "BS.1770-4, mono measured dual-mono"},
		"tempo": {"bpm": theory.BPM, "bar_beats": theory.BAR_BEATS, "pad_bars": theory.PAD_BARS,
			"samples_per_beat": theory.SAMPLES_PER_BEAT, "pad_samples": theory.PAD_SAMPLES,
			"pad_seconds": round(theory.PAD_SECONDS, 6)},
		"harmony": {"key": "F Lydian", "scale_pcs": theory.SCALE_PCS, "universal_pcs": theory.UNIVERSAL_PCS,
			"chords": chords, "shell_notes": theory.SHELL_NOTES,
			"pad_clip_order": [c["pad_clips"][s] for s in ("day", "night") for c in chords]},
		"buses": score.BUSES,
		"phases": phase_profiles(),
		"music_flow": score.MUSIC_FLOW, "voices": score.VOICES, "profiles": score.PROFILES,
		"weather": score.WEATHER, "music_lpf_min_hz": score.MUSIC_LPF_MIN_HZ, "critters": score.CRITTERS,
		"duck": score.DUCK, "settings": score.SETTINGS, "haptics": score.HAPTICS,
		"banks": banks, "cues": cues, "reward_cues": cue_table.REWARD_CUES, "assets": alist,
	}


# ============================================================================= report
def sizes(assets: list[dict], stats: dict) -> dict:
	repo = {"ogg": 0, "wav": 0, "web": 0}
	shipped = 0.0
	for a in assets:
		p = stats[a["id"]]["post"]
		if a["fmt"] == "ogg":
			repo["ogg"] += p["bytes"]
			shipped += p["bytes"]
		else:
			repo["wav"] += p["bytes"]
			shipped += p["length_samples"] * a["ch"] * QOA_BYTES_PER_SAMPLE + 64
		if a.get("web_twin"):
			repo["web"] += stats[a["id"]]["web"]["bytes"]
	return {"repo_mb": round(sum(repo.values()) / 1e6, 2), "repo_ogg_mb": round(repo["ogg"] / 1e6, 2),
		"repo_wav_mb": round(repo["wav"] / 1e6, 2), "repo_web_mb": round(repo["web"] / 1e6, 2),
		"shipped_android_est_mb": round(shipped / 1e6, 2),
		"shipped_web_est_mb": round((shipped - 0 + repo["web"]) / 1e6, 2)}


def fmt_pct(x: float) -> str:
	return f"{100 * x:.2f}"


def report_md(assets, stats, cue_rep, comp_rep, mix, sz, fails) -> str:
	L = []
	L.append(f"Generated by `tools/audio/synth.py` (seed {BASE_SEED}). {len(assets)} assets"
		f" + {sum(1 for a in assets if a.get('web_twin'))} Web twins. Gates: "
		+ ("**all passed**." if not fails else f"**{len(fails)} FAILED**."))
	L.append("")
	L.append(f"**Size.** Repo {sz['repo_mb']} MB (OGG {sz['repo_ogg_mb']}, WAV {sz['repo_wav_mb']}, Web twins "
		f"{sz['repo_web_mb']}). Shipped Android estimate **{sz['shipped_android_est_mb']} MB** (OGG as-is + WAV "
		f"at QOA 3.2 bit/sample); Web adds the twins. Gate: <= {GATES['shipped_mb_max']} MB.")
	L.append("")
	L.append("### A. Long files (post-encode, decoded OGG)")
	L.append("")
	L.append("| id | LUFS-I | pyloudnorm (pre) | dBTP | LRA | seam pre/post | centroid Hz | 2-5 kHz % | >10 kHz % | AM idx | KB |")
	L.append("|---|---|---|---|---|---|---|---|---|---|---|")
	for a in assets:
		if a["kind"] not in ("pad", "bed"):
			continue
		s, p = stats[a["id"]], stats[a["id"]]["post"]
		am = f"{p['am_index']:.3f}" if "am_index" in p else "-"
		L.append(f"| {a['id']} | {p['lufs_i']} | {s['pre'].get('lufs_i_pyloudnorm', '-')} | {p['true_peak_dbtp']} | {p['lra']} | "
			f"{s['pre'].get('seam', '-')}/{p['seam']} | {p['centroid_hz']:.0f} | {fmt_pct(p['frac_2k_5k'])} | "
			f"{100 * p['frac_above_10k']:.3f} | {am} | {p['bytes'] // 1024} |")
	L.append("")
	L.append("### B. Short files (16-bit WAV as written) -- per bank: min / max over the bank")
	L.append("")
	L.append("| bank | files | bus | LUFS-M min..max | peak dBFS max | centroid Hz min..max | 2-5 kHz % max | >10 kHz % max | s total | Web twin LUFS-M |")
	L.append("|---|---|---|---|---|---|---|---|---|---|")
	groups: dict[str, list[dict]] = {}
	for a in assets:
		if a["kind"] in ("pad", "bed"):
			continue
		groups.setdefault(a.get("bank", a["id"]), []).append(a)
	for b, lst in groups.items():
		P = [stats[a["id"]]["post"] for a in lst]
		W = [stats[a["id"]].get("web") for a in lst if stats[a["id"]].get("web")]
		web = f"{min(w['lufs_m_max'] for w in W):.1f}..{max(w['lufs_m_max'] for w in W):.1f}" if W else "-"
		L.append(f"| {b} | {len(lst)} | {lst[0]['bus']} | {min(p['lufs_m_max'] for p in P):.1f}..{max(p['lufs_m_max'] for p in P):.1f} | "
			f"{max(p['sample_peak_dbfs'] for p in P):.1f} | {min(p['centroid_hz'] for p in P):.0f}..{max(p['centroid_hz'] for p in P):.0f} | "
			f"{max(100 * p['frac_2k_5k'] for p in P):.2f} | {max(100 * p['frac_above_10k'] for p in P):.3f} | "
			f"{sum(p['length_samples'] for p in P) / SR:.1f} | {web} |")
	L.append("")
	L.append("### C. Cue levels (heard at Master = file + gain + bus)")
	L.append("")
	L.append("| cue.layer | bank | files | gain dB | target | heard min..max |")
	L.append("|---|---|---|---|---|---|")
	for k, r in cue_rep.items():
		L.append(f"| {k} | {r['bank']} | {r['files']} | {r['gain_db']:+.2f} | {r['heard_target']} | {r['heard_min']}..{r['heard_max']} |")
	for k, v in comp_rep.items():
		L.append(f"| {k} (composite) | - | - | - | - | {v} |")
	L.append("")
	if mix:
		L.append("### D. Offline mix simulation (AudioDirector rules, 10 min idle per row)")
		L.append("")
		L.append("| profile / weather | LUFS-I | TP dBTP | LUFS-S max | LRA | beds LUFS-I | accent max (heard) | accent margin dB | notes played | rests |")
		L.append("|---|---|---|---|---|---|---|---|---|---|")
		for k, m in mix.items():
			L.append(f"| {k} | {m['lufs_i']} | {m['tp']} | {m['st_max']} | {m['lra']} | {m['beds_lufs_i']} | "
				f"{m['accent_max']} | {m['accent_margin']} | {m['notes']} | {m['rests']} |")
		L.append("")
	if fails:
		L.append("### FAILURES")
		L.append("")
		for f in fails:
			L.append(f"- `{f[0]}` -- {f[1]}: {f[2]}")
	return "\n".join(L) + "\n"


APPENDIX_BEGIN = "<!-- BEGIN GENERATED: tools/audio/synth.py -->"
APPENDIX_END = "<!-- END GENERATED -->"


def update_bible(md: str) -> None:
	p = os.path.join(REPO, "docs", "AUDIO_BIBLE.md")
	if not os.path.exists(p):
		return
	with open(p, encoding="utf-8") as fh:
		txt = fh.read()
	if APPENDIX_BEGIN not in txt:
		return
	head, rest = txt.split(APPENDIX_BEGIN, 1)
	tail = rest.split(APPENDIX_END, 1)[1] if APPENDIX_END in rest else ""
	with open(p, "w", encoding="utf-8", newline="\n") as fh:
		fh.write(head + APPENDIX_BEGIN + "\n\n" + md + "\n" + APPENDIX_END + tail)


# ============================================================================= main
def main() -> int:
	ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("--jobs", type=int, default=min(4, os.cpu_count() or 1))
	ap.add_argument("--only", default=None, help="glob of asset ids to re-render (others are re-checked from disk)")
	ap.add_argument("--check", action="store_true", help="no rendering; analyse files on disk and run all gates")
	ap.add_argument("--skip-mixsim", action="store_true")
	ap.add_argument("--force-write", action="store_true", help="write manifest/appendix even if gates fail")
	args = ap.parse_args()

	t0 = time.time()
	assets = registry()
	todo = [] if args.check else [a for a in assets if not args.only or fnmatch.fnmatch(a["id"], args.only)]
	rest = [a for a in assets if a not in todo]
	print(f"[synth] {len(assets)} assets: rendering {len(todo)}, checking {len(rest)} from disk, {args.jobs} jobs")
	stats: dict[str, dict] = {}
	todo.sort(key=lambda a: {"pad": 0, "bed": 1}.get(a["kind"], 2))   # long jobs first
	with mp.get_context("fork").Pool(args.jobs) as pool:
		for r in pool.imap_unordered(build_one, todo, chunksize=1):
			stats[r["id"]] = r
		for r in pool.imap_unordered(check_one, rest, chunksize=4):
			stats[r["id"]] = r
	print(f"[synth] rendered/analysed in {time.time() - t0:.1f} s")

	fails = gate_assets(assets, stats)
	cues, cue_fails, cue_rep = build_cues(assets, stats)
	fails += cue_fails
	comp_fails, comp_rep = composite_cue_checks(cues, stats)
	fails += comp_fails
	manifest = build_manifest(assets, stats, cues)
	mix = {}
	if not args.skip_mixsim:
		import mixsim
		mix, mix_fails = mixsim.run_all(manifest, GATES, jobs=args.jobs)
		fails += mix_fails
	sz = sizes(assets, stats)
	if sz["shipped_android_est_mb"] > GATES["shipped_mb_max"]:
		fails.append(("(all)", "size", f"shipped {sz['shipped_android_est_mb']} MB > {GATES['shipped_mb_max']}"))
	md = report_md(assets, stats, cue_rep, comp_rep, mix, sz, fails)
	os.makedirs(os.path.join(REPO, "qa", "out", "audio"), exist_ok=True)
	with open(os.path.join(REPO, "qa", "out", "audio", "report.md"), "w", encoding="utf-8") as fh:
		fh.write(md)
	with open(os.path.join(REPO, "qa", "out", "audio", "stats.json"), "w", encoding="utf-8") as fh:
		json.dump(stats, fh, indent=1, sort_keys=True)
	print(md)
	if fails and not args.force_write:
		print(f"[synth] FAIL: {len(fails)} gate(s) failed -- manifest and AUDIO_BIBLE appendix NOT updated", file=sys.stderr)
		for f in fails:
			print(f"  FAIL {f[0]:28s} {f[1]:16s} {f[2]}", file=sys.stderr)
		return 1
	with open(os.path.join(REPO, "audio", "manifest.json"), "w", encoding="utf-8", newline="\n") as fh:
		json.dump(manifest, fh, indent="\t", ensure_ascii=False)
		fh.write("\n")
	update_bible(md)
	print(f"[synth] OK in {time.time() - t0:.1f} s: audio/manifest.json written ({len(assets)} assets)")
	return 1 if fails else 0


if __name__ == "__main__":
	sys.exit(main())
