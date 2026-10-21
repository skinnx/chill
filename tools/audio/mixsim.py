"""Offline simulation of the AudioDirector (reference implementation of docs/AUDIO_BIBLE.md §8).

It reads only the manifest (the same data the game reads) plus the rendered files, mixes 10 minutes
of idle play per profile/weather at the real bus gains, and measures the A1/A2 mix contract:
LUFS-I -18 +-1, TP <= -1 dBTP (before the Master limiter), short-term <= -14, LRA <= 8, and
accents (birds, crickets) >= 15 dB under the beds. It also writes 2-minute listening previews to
qa/out/audio/ (git-ignored).

Emulated engine behaviour (Godot 4.7.2):
- AudioStreamInteractive NEXT_BAR / TO_TIME_START / FADE_CROSS: both clips ramp linearly over
  fade_beats starting at the bar line (modules/interactive_music/audio_stream_interactive.cpp:684-846).
- Music-bus AudioEffectLowPassFilter (db = 6 dB/oct preset = 1 stage): one RBJ low-pass biquad with
  Q = resonance (servers/audio/audio_filter_sw.cpp).
- Mono files are copied to both channels (audio_stream_wav.cpp:206-211).
"""
from __future__ import annotations

import json
import multiprocessing as mp
import os

import numpy as np
from scipy.signal import lfilter

from dsp import SR, rbj, undb
from fileio import GODOT_OGG_LOOP_FADE, decode_audio, encode_ogg, ogg_as_played, read_wav16
from loudness import loudness_range, lufs_integrated, lufs_momentary_max, lufs_shortterm_max, true_peak_db
from theory import pent_step, snap, wrap_into

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
PATHS: dict[str, str] = {}
_CACHE: dict[str, np.ndarray] = {}


def _res_to_abs(p: str) -> str:
	return os.path.join(REPO, p.replace("res://", ""))


def load_asset_audio(aid: str) -> np.ndarray:
	if aid not in _CACHE:
		if not PATHS:
			with open(os.path.join(REPO, "audio", "manifest.json"), encoding="utf-8") as fh:
				for a in json.load(fh)["assets"]:
					PATHS[a["id"]] = a["path"]
		p = _res_to_abs(PATHS[aid])
		if p.endswith(".ogg"):
			x = decode_audio(p, 2)
			period = x.shape[1] - GODOT_OGG_LOOP_FADE
			if period % (SR * 60 // 70) == 0:   # a beat-looped file: use the period as Godot plays it
				x = ogg_as_played(x, period)
		else:
			x = read_wav16(p)
		_CACHE[aid] = x[0] if x.shape[0] == 1 else x
	return _CACHE[aid]


def _add(buf: np.ndarray, x: np.ndarray, start: int, gain: float) -> None:
	if start >= buf.shape[1] or start < 0:
		return
	n = min(x.shape[-1], buf.shape[1] - start)
	if x.ndim == 1:
		buf[:, start:start + n] += gain * x[:n]
	else:
		buf[:, start:start + n] += gain * x[:, :n]


def _tile(x: np.ndarray, n: int, offset: int) -> np.ndarray:
	idx = (offset + np.arange(n)) % x.shape[1]
	return x[:, idx]


def simulate(man: dict, profile: str, weather: str, seconds: float = 600.0, seed: int = 1,
		events: list[tuple[float, str]] | None = None, shells_owned: int = 5,
		log: list | None = None) -> tuple[dict, np.ndarray]:
	"""Mix `seconds` of idle play. If `log` is a list, (time_s, kind, detail) tuples are appended."""
	rng = np.random.default_rng(seed)
	N = int(seconds * SR)
	P, W, F = man["profiles"][profile], man["weather"][weather], man["music_flow"]
	bus = {b["name"]: b["volume_db"] for b in man["buses"]}
	chords = man["harmony"]["chords"]
	banks = man["banks"]
	asset_by_id = {a["id"]: a for a in man["assets"]}
	for a in man["assets"]:
		PATHS.setdefault(a["id"], a["path"])
	f32 = np.float32
	beds = np.zeros((2, N), f32)
	accent = np.zeros((2, N), f32)
	music = np.zeros((2, N))
	fx = np.zeros((2, N), f32)
	ui = np.zeros((2, N), f32)
	cricket_only = np.zeros((2, N), f32)

	id_by_path = {a["path"]: a["id"] for a in man["assets"]}

	def bank_note(bank: str, m: int) -> str:
		return id_by_path[banks[bank]["notes"][str(m)]]

	# ---------------------------------------------------------------- L0 beds
	boot_fade = int(F["boot_bed_fade_in_s"] * SR)
	ramp = np.ones(N)
	ramp[:boot_fade] = np.linspace(0.0, 1.0, boot_fade)
	for bed_id, vol in P["beds"].items():
		if vol is None:
			continue
		bid = W["replace"].get(bed_id, bed_id)
		if bid == "amb_crickets" and not W["crickets"]:
			continue
		v = vol + W["bed_add_db"].get(bed_id, 0.0) + asset_by_id[bid]["base_volume_db"]
		x = load_asset_audio(bid)
		layer = _tile(x, N, int(rng.integers(0, x.shape[1]))) * undb(v) * ramp
		if bid == "amb_crickets":
			accent += layer
			cricket_only += layer
		else:
			beds += layer
	# birds
	bird_ids = sorted(a["id"] for a in man["assets"] if a.get("bank") == "bird")
	birds_only = np.zeros((2, N), f32)
	if P["birds"]:
		lo, hi = P["birds"]["interval_s"]
		t, last = rng.uniform(lo, hi) / W["birds_rate_mult"], None
		while t < seconds:
			choice = [b for b in bird_ids if b != last]
			last = choice[int(rng.integers(len(choice)))]
			_add(birds_only, load_asset_audio(last), int(t * SR), undb(P["birds"]["volume_db"] + W["birds_add_db"]))
			t += rng.uniform(lo, hi) / W["birds_rate_mult"]
		accent += birds_only

	# ---------------------------------------------------------------- L1 pads
	bar = man["tempo"]["samples_per_beat"] * man["tempo"]["bar_beats"]
	fade = int(F["crossfade_beats"] * man["tempo"]["samples_per_beat"])
	pad_start = int(F["boot_pad_delay_s"] * SR)
	clips: list[tuple[int, dict]] = []   # (start sample, chord)
	t = pad_start
	cur = chords[int(rng.integers(len(chords)))]
	while t < N:
		clips.append((t, cur))
		if log is not None:
			log.append((t / SR, "chord", cur["name"]))
		hold = int(rng.integers(F["chord_hold_bars"][0], F["chord_hold_bars"][1] + 1))
		t += hold * bar
		cur = [c for c in chords if c["name"] != cur["name"]][int(rng.integers(len(chords) - 1))]
	pad_segments = []
	for i, (st, c) in enumerate(clips):
		end = clips[i + 1][0] + fade if i + 1 < len(clips) else N
		end = min(end, N)
		x = load_asset_audio(c["pad_clips"][P["pad_set"]])
		seg = _tile(x, end - st, 0)
		env = np.ones(end - st)
		if i > 0:
			k = min(fade, end - st)
			env[:k] = np.linspace(0.0, 1.0, k)
		if i + 1 < len(clips):
			k = min(fade, end - st)
			env[-k:] *= np.linspace(1.0, 0.0, k)
		pad_segments.append((st, end, seg * env))
	music_env = np.zeros(N)
	pf = int(F["boot_pad_fade_in_s"] * SR)
	music_env[pad_start:] = 1.0
	music_env[pad_start:pad_start + pf] = np.linspace(0.0, 1.0, pf)
	# rests
	rests = []
	t = pad_start / SR + rng.uniform(*F["rest_every_s"])
	while t < seconds:
		ln = rng.uniform(*F["rest_len_s"])
		rests.append((t, t + ln))
		t += ln + rng.uniform(*F["rest_every_s"])
	rf = int(F["rest_fade_s"] * SR)
	for a, b in rests:
		if log is not None:
			log.append((a, "rest", f"{b - a:.0f} s"))
		ia, ib = int(a * SR), int(b * SR)
		seg = np.zeros(max(0, min(ib, N) - ia))
		music_env[ia:ia + len(seg)] = 0.0
		k = min(rf, N - ia)
		if k > 0:
			music_env[ia:ia + k] = np.linspace(1.0, 0.0, k)
		k2 = min(rf, N - ib) if ib < N else 0
		if k2 > 0:
			music_env[ib:ib + k2] = np.linspace(0.0, 1.0, k2)
	for st, end, seg in pad_segments:
		music[:, st:end] += seg * (music_env[st:end] * undb(P["pad_db"] + W["music_add_db"]))
	del pad_segments

	def chord_at(sample: int) -> dict:
		c = clips[0][1]
		for st, cc in clips:
			if st <= sample:
				c = cc
		return c

	def in_rest(ts: float) -> bool:
		return any(a - F["rest_fade_s"] <= ts <= b for a, b in rests) or ts * SR < pad_start

	# ---------------------------------------------------------------- L2 voices
	density = max(0.0, P["density"] + W["density_add"])
	last_onset = -100.0
	ticks = []
	for vname, vcfg in P["voices"].items():
		per = man["voices"][vname]["period_s"]
		k = 1
		while k * per < seconds:
			ticks.append((k * per, vname, vcfg))
			k += 1
	ticks.sort(key=lambda e: e[0])
	notes_played = 0
	for ts, vname, vcfg in ticks:
		if in_rest(ts) or rng.random() > density or ts - last_onset < F["min_onset_gap_s"]:
			continue
		last_onset = ts
		voice = man["voices"][vname]
		bank = voice["bank"]
		lo, hi = banks[bank]["range"]
		pcs = chord_at(int(ts * SR))["pcs"]
		m = wrap_into(snap(vcfg["base"] + int(rng.integers(-F["base_spread"], F["base_spread"] + 1)), pcs), lo, hi)
		tn = ts
		for i in range(voice["notes"]):
			jit = rng.uniform(-F["onset_jitter_s"], F["onset_jitter_s"])
			vel = rng.uniform(*F["velocity_db"])
			_add(music, load_asset_audio(bank_note(bank, m)), int((tn + jit) * SR), undb(vcfg["db"] + vel + W["music_add_db"]))
			if log is not None:
				log.append((tn + jit, "note", f"{vname}:{m}"))
			notes_played += 1
			tn += float(rng.choice(F["motif_ioi_s"], p=F["motif_ioi_weights"]))
			m = wrap_into(pent_step(m, int(rng.choice(F["motif_steps"])), pcs), lo, hi)

	# ---------------------------------------------------------------- L3 critters + chime gusts
	C = man["critters"]
	coo_bank = banks["coo"]
	t = rng.uniform(*C["coo_interval_s"])
	while t < seconds:
		pcs = chord_at(int(t * SR))["pcs"]
		m = wrap_into(pent_step(67, int(rng.integers(-3, 6)), pcs), *coo_bank["range"])
		g = man["cues"]["S13"]["layers"][0]["gain_db"] + C["coo_db"]
		_add(fx, load_asset_audio(bank_note("coo", m)), int(t * SR), undb(g))
		t += rng.uniform(*C["coo_interval_s"])
	if profile == "night":
		snores = sorted(banks["snore"]["variants"].values())
		t = rng.uniform(*C["snore_interval_s"])
		while t < seconds:
			aid = id_by_path[snores[int(rng.integers(len(snores)))]]
			_add(fx, load_asset_audio(aid), int(t * SR), undb(man["cues"]["S14"]["layers"][0]["gain_db"] + C["snore_db"]))
			t += rng.uniform(*C["snore_interval_s"])
	owned = man["harmony"]["shell_notes"][:shells_owned]
	gl = man["cues"]["S21"]["layers"][0]
	t = rng.uniform(*W["chime_gust_s"])
	while t < seconds:
		pcs = chord_at(int(t * SR))["pcs"]
		pool = [m for m in owned if m % 12 in pcs] or owned
		tn = t
		for _ in range(int(rng.integers(gl["pitch"]["gust_notes"][0], gl["pitch"]["gust_notes"][1] + 1))):
			m = pool[int(rng.integers(len(pool)))]
			_add(beds, load_asset_audio(bank_note("shell", m)), int(tn * SR), undb(gl["gust_gain_db"]))
			tn += rng.uniform(*gl["pitch"]["gust_gap_s"])
		t += rng.uniform(*W["chime_gust_s"])

	# ---------------------------------------------------------------- scripted events (interaction run)
	for te, cue in events or []:
		c = man["cues"][cue]
		layer = c["layers"][0]
		b = banks[layer["bank"]]
		if "clips" in b:
			aid = id_by_path[b["clips"][chord_at(int(te * SR))["clip"]]]
			_add(fx, load_asset_audio(aid), int(te * SR), undb(layer["gain_db"]))
		elif cue == "S02":
			pcs = chord_at(int(te * SR))["pcs"]
			for k in range(8):
				m = wrap_into(pent_step(72, min(k, 7), pcs), *b["range"])
				_add(fx, load_asset_audio(bank_note("dew", m)), int((te + 0.09 * k) * SR), undb(layer["gain_db"]))
		elif cue == "S01":
			pcs = chord_at(int(te * SR))["pcs"]
			m = wrap_into(snap(72, pcs), *b["range"])
			_add(ui, load_asset_audio(bank_note("plip", m)), int(te * SR), undb(layer["gain_db"]))

	# ---------------------------------------------------------------- buses -> master
	lpf = max(man["music_lpf_min_hz"], P["music_lpf_hz"] + W["music_lpf_add_hz"])
	mres = man["buses"][1]["effects"][0]["props"]["resonance"]
	if lpf < 20000.0:
		b_, a_ = rbj("lp", lpf, mres)
		music = lfilter(b_, a_, music, axis=-1)
	master = music * undb(bus["Music"]) + (beds + accent) * undb(bus["Ambience"]) + fx * undb(bus["SFX"]) \
		+ ui * undb(bus["UI"])
	beds_heard = beds * undb(bus["Ambience"])
	beds_i = lufs_integrated(beds_heard)
	acc = []
	if P["birds"]:
		acc.append(("birds_M", lufs_momentary_max(birds_only * undb(bus["Ambience"]))))
	if np.abs(cricket_only).max() > 0:
		acc.append(("crickets_I", lufs_integrated(cricket_only * undb(bus["Ambience"]))))
	acc_max = max((v for _, v in acc), default=-np.inf)
	stats = {
		"lufs_i": round(lufs_integrated(master), 2), "tp": round(float(true_peak_db(master)), 2),
		"st_max": round(lufs_shortterm_max(master), 2), "lra": round(loudness_range(master), 2),
		"beds_lufs_i": round(beds_i, 2), "accent_max": round(acc_max, 2) if acc else "-",
		"accent_margin": round(beds_i - acc_max, 2) if acc else "-", "accent_detail": {k: round(v, 2) for k, v in acc},
		"notes": notes_played, "rests": len(rests), "music_lpf_hz": lpf,
	}
	return stats, master


RUNS = [("dawn", "clear"), ("day", "clear"), ("day", "breeze"), ("dusk", "clear"), ("night", "clear"),
	("day", "rain"), ("night", "rain")]


def _run(args):
	man, profile, weather, seconds, seed, events, preview = args
	st, master = simulate(man, profile, weather, seconds, seed, events)
	if preview:
		out = os.path.join(REPO, "qa", "out", "audio", f"preview_{preview}.ogg")
		encode_ogg(out, master[:, :int(120 * SR)])
	return (preview or f"{profile}/{weather}", st)


def run_all(man: dict, gates: dict, jobs: int = 2) -> tuple[dict, list]:
	os.makedirs(os.path.join(REPO, "qa", "out", "audio"), exist_ok=True)
	work = [(man, p, w, 600.0, 7 + i, None, f"{p}_{w}") for i, (p, w) in enumerate(RUNS)]
	interaction = [(30.0, "S02"), (60.0, "S09"), (75.0, "S01"), (76.2, "S01"), (90.0, "S04"), (100.0, "S10"),
		(110.0, "S16")]
	work.append((man, "day", "clear", 150.0, 99, interaction, "interaction_day_clear"))
	with mp.get_context("fork").Pool(max(1, min(jobs, 2))) as pool:
		res = {}
		for name, st in pool.imap(_run, work):
			res[name] = st
	fails = []
	lo, hi = gates["mix_lufs_range"]
	for k, s in res.items():
		if k.startswith("interaction"):
			if s["st_max"] > gates["mix_st_max"]:
				fails.append((k, "A1 short-term", f"{s['st_max']} > {gates['mix_st_max']}"))
			if s["tp"] > gates["mix_tp_max"]:
				fails.append((k, "A1 true peak", f"{s['tp']} > {gates['mix_tp_max']}"))
			continue
		if not lo <= s["lufs_i"] <= hi:
			fails.append((k, "A1 mix LUFS-I", f"{s['lufs_i']} not in [{lo}, {hi}]"))
		if s["tp"] > gates["mix_tp_max"]:
			fails.append((k, "A1 true peak", f"{s['tp']} > {gates['mix_tp_max']}"))
		if s["st_max"] > gates["mix_st_max"]:
			fails.append((k, "A1 short-term", f"{s['st_max']} > {gates['mix_st_max']}"))
		if s["lra"] > gates["mix_lra_max"]:
			fails.append((k, "LRA", f"{s['lra']} > {gates['mix_lra_max']}"))
		if s["accent_margin"] != "-" and s["accent_margin"] < gates["accent_under_bed_db"]:
			fails.append((k, "A2 accents", f"{s['accent_detail']} only {s['accent_margin']} dB under beds {s['beds_lufs_i']}"))
	return res, fails
