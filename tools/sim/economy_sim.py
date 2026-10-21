#!/usr/bin/env python3
"""Mossling Meadow - economy and pacing simulation (docs/GDD.md section 9).

Reads every game number from data/*.json (species, flora, decor, economy, world,
spots); only player-behaviour assumptions (schedules and spending policies) live
here. The world step is the same event-driven algorithm the game uses for both
live play and offline catch-up (GDD section 5.8), so this file doubles as the
reference implementation for scripts/sim.

Checks (exit code 1 on any failure):
  E1  nothing the player owns ever decreases without a player action
  E5  every session has >= 1 affordable meaningful purchase and >= 1 new thing to see
  E6  no displayed value above display_max (99,999)
  P*  pacing targets from economy.json "validation_targets"
  R*  Retention v1 (GDD section 13): friendship depth (friendship.json), mystery signs, clues and
      variant cousins (mysteries.json), away scenes (scenes.json) and the "content-left" metric:
      on how many of the first 30 local days did the player see >= 1 new discovery (species,
      heart, postcard, clue, scene, variant). Nothing may be missable or decrease.

Usage:
  python3 tools/sim/economy_sim.py                # 10,000 random (30 d) + 2,000 reference players (80 d)
  python3 tools/sim/economy_sim.py --quick        # 500 random + 200 reference, about 20 s
  python3 tools/sim/economy_sim.py --players 500  # custom size
  python3 tools/sim/economy_sim.py --markdown out.md
"""
from __future__ import annotations

import argparse
import heapq
import json
import math
import os
import sys
import time
from multiprocessing import Pool
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
DAY = 86400.0
HOUR = 3600.0
INF = float("inf")
BASE_SEED = 20261020

# ---------------------------------------------------------------- player model
# These are assumptions about PLAYERS, not game data, so they live here.
SESSION_LENGTHS_S = (30.0, 180.0, 600.0)
GAP_MIN_S = 600.0
GAP_MAX_S = 3.0 * DAY
SIM_DAYS = 30
REF_DAYS = 80  # reference players run longer: the heart-5 tail is a 45-70 day target
# name, share, purchases per session by length (30 s, 3 min, 5 min, 10 min), buy probability,
# boat probability, focus probability (follow the album hint of the next friend), save probability
# (when the hinted item is not affordable yet, keep the dew instead of buying something else)
POLICIES = (
	("gentle", 0.35, {30: 1, 180: 2, 300: 3, 600: 4}, 0.8, 0.3, 0.5, 0.3),
	("keen", 0.40, {30: 2, 180: 5, 300: 6, 600: 10}, 1.0, 0.5, 0.7, 0.3),
	("greedy", 0.15, {30: 99, 180: 99, 300: 99, 600: 99}, 1.0, 0.0, 0.3, 0.0),
	("drain", 0.10, {30: 99, 180: 99, 300: 99, 600: 99}, 1.0, 1.0, 0.0, 0.0),  # also floats boats until broke
)
POLICY_NAMES = tuple(p[0] for p in POLICIES)
POSES = ("nap", "nibble", "play", "wander", "sit_by_stream")


# ---------------------------------------------------------------- content
def load_content(root: Path) -> dict:
	data = {}
	for name in ("species", "flora", "decor", "economy", "world", "spots", "friendship", "mysteries", "scenes"):
		with open(root / "data" / f"{name}.json", encoding="utf-8") as f:
			data[name] = json.load(f)
	return data


class Content:
	"""Pre-indexed view of the JSON data (no constants of its own)."""

	def __init__(self, raw: dict) -> None:
		self.raw = raw
		eco = raw["economy"]
		self.eco = eco
		self.world = raw["world"]
		self.flowers = raw["flora"]["flowers"]
		self.decor = raw["decor"]["decor"]
		self.species = sorted(raw["species"]["species"], key=lambda s: s["album_order"])
		self.nf = len(self.flowers)
		self.nd = len(self.decor)
		self.ns = len(self.species)
		self.item_index: dict[str, tuple[int, int]] = {}
		for i, fl in enumerate(self.flowers):
			self.item_index[fl["id"]] = (0, i)
		for j, de in enumerate(self.decor):
			self.item_index[de["id"]] = (1, j)
		self.species_index = {s["id"]: k for k, s in enumerate(self.species)}
		self.phases = sorted(self.world["phases"], key=lambda p: p["start_s"])
		self.phase_ids = [p["id"] for p in self.phases]
		self.phase_index = {p: i for i, p in enumerate(self.phase_ids)}
		self.weather_ids = [w["id"] for w in self.world["weather"]]
		self.weather_index = {w: i for i, w in enumerate(self.weather_ids)}
		# compiled species rules
		self.sp_req = []      # list of [(kind, idx, min)]
		self.sp_phase_ok = []  # set of phase idx or None
		self.sp_like_items = []
		self.sp_like_weather = []
		self.sp_like_phase = []
		self.sp_pose_cum = []
		for s in self.species:
			self.sp_req.append([(*self.item_index[r["item"]], int(r["min"])) for r in s["requires"]])
			self.sp_phase_ok.append({self.phase_index[p] for p in s["phases"]} if s["phases"] else None)
			self.sp_like_items.append([(*self.item_index[l["item"]], int(l["min"]), float(l["mult"])) for l in s["likes_items"]])
			self.sp_like_weather.append({self.weather_index[l["weather"]]: float(l["mult"]) for l in s["likes_weather"]})
			self.sp_like_phase.append({self.phase_index[l["phase"]]: float(l["mult"]) for l in s["likes_phases"]})
			w = [float(s["behaviours"][p]) for p in POSES]
			tot = sum(w)
			acc = 0.0
			cum = []
			for x in w:
				acc += x / tot
				cum.append(acc)
			self.sp_pose_cum.append(cum)
		self.sp_base = [float(s["base_weight"]) for s in self.species]
		self.sp_gift = [int(s["gift_dew"]) for s in self.species]
		self.sp_stay = [float(s["stay_mult"]) for s in self.species]
		self.night_idx = self.phase_index["night"]
		self.rain_idx = self.weather_index["rain"]
		self.fl_cost = [(float(f["cost_base"]), float(f["cost_growth"]), int(f["max_copies"])) for f in self.flowers]
		self.de_cost = [(float(d["cost_base"]), float(d["cost_growth"]), int(d["max_copies"])) for d in self.decor]
		self.fl_times = [(float(f["sprout_at_s"]), float(f["bud_at_s"]), float(f["bloom_at_s"])) for f in self.flowers]
		self.fl_dew_h = [float(f["dew_per_hour"]) for f in self.flowers]
		self.fl_snug = [float(f["snug"]) for f in self.flowers]
		self.de_snug = [float(d["snug"]) for d in self.decor]
		self.total_items = sum(c[2] for c in self.fl_cost) + sum(c[2] for c in self.de_cost)
		self.heart_thr = list(eco["heart_thresholds"])
		self.event_postcards = {p["trigger"]: p["id"] for p in eco["event_postcards"]}
		wp = self.world["weather_plan"]
		self.rain_cum = np.cumsum(wp["rain_count_probs"]).tolist()
		self.breeze_cum = np.cumsum(wp["breeze_count_probs"]).tolist()
		self.wp = wp
		# ---- Retention v1 (GDD 13) -------------------------------------------------------
		self.aff_rest_s = float(eco.get("visit_affection_rest_s", 0.0))
		self.sp_best = [self.species_index[s["best_friend"]] for s in self.species]
		self.sp_order = [int(s["album_order"]) for s in self.species]
		fr = raw["friendship"]
		self.fr = fr
		self.nest_min_hearts = int(fr["nest"]["min_hearts"])
		self.nest_stage_at = [float(st["at_s"]) for st in fr["nest"]["stages"]]
		self.pair_min_hearts = int(fr["pair"]["min_hearts_either"])
		my = raw["mysteries"]
		self.my = my
		self.sign_windows = {int(k): [tuple(w) for w in v] for k, v in my["sign_windows_s"].items()}
		self.var_sign_windows = {int(k): [tuple(w) for w in v] for k, v in my["variant_sign_windows_s"].items()}
		self.debut_after_last = float(my["debut_after_last_sign_s"])
		self.max_visible_signs = int(my["max_visible"])
		self.sp_signs = [[] for _ in self.species]
		self.sp_onboarding = [True] * self.ns
		for rec in my["species"]:
			k = self.species_index[rec["species"]]
			self.sp_signs[k] = list(rec["signs"])
			self.sp_onboarding[k] = bool(rec["onboarding"])
		self.var_hearts = int(my["variant_hearts_required"])
		self.var_all_met = bool(my["variant_requires_all_met"])
		self.variants = []  # (id, base k, [(kind, idx, min)], phase set|None, weather set|None, n signs)
		for v in my["variants"]:
			c = v["condition"]
			self.variants.append((
				v["id"], self.species_index[v["species"]],
				[(*self.item_index[r["item"]], int(r["min"])) for r in c["items"]],
				{self.phase_index[x] for x in c["arrival_phases"]} or None,
				{self.weather_index[x] for x in c["arrival_weather"]} or None,
				len(v["signs"]),
			))
		self.nv = len(self.variants)
		sc = raw["scenes"]
		self.sc = sc
		self.scene_min_abs = float(sc["min_absence_s"])
		self.scene_chance = float(sc["scene_chance"])
		self.away_sample_s = float(sc["away_sample_s"])
		self.scenes = []
		for x in sc["scenes"]:
			c = x["conditions"]
			self.scenes.append({
				"id": x["id"], "weight": float(x["weight"]), "pair": bool(x["pair"]), "roles": len(x["roles"]),
				"met_min": int(c.get("met_min", 0)),
				"items": [(*self.item_index[r["item"]], int(r["min"])) for r in c.get("items", [])],
				"boats_min": int(c.get("boats_min", 0)),
				"stems_min": int(c.get("bloomed_stems_min", 0)),
				"types_min": int(c.get("bloomed_types_min", 0)),
				"pair_hearts_min": int(c.get("pair_hearts_min", 0)),
				"away": [({self.phase_index[p] for p in a["phases"]} or None,
					{self.weather_index[w] for w in a["weather"]} or None, float(a["min_s"])) for a in c.get("away", [])],
			})
		self.ns_scenes = len(self.scenes)

	@staticmethod
	def price(base: float, growth: float, n: int) -> int:
		return int(math.floor(base * growth ** n + 0.5))

	def phase_at(self, local_s: float) -> int:
		sod = local_s % DAY
		idx = len(self.phases) - 1  # before the first start it is still night
		for i, p in enumerate(self.phases):
			if sod >= p["start_s"]:
				idx = i
		return idx


# ---------------------------------------------------------------- rng
class Rng:
	"""Buffered numpy PCG64 stream: deterministic and fast for scalar draws."""

	__slots__ = ("g", "buf", "i")

	def __init__(self, seed: int | list) -> None:
		self.g = np.random.default_rng(seed)
		self.buf = self.g.random(4096).tolist()
		self.i = 0

	def u(self) -> float:
		if self.i >= 4096:
			self.buf = self.g.random(4096).tolist()
			self.i = 0
		v = self.buf[self.i]
		self.i += 1
		return v

	def uniform(self, a: float, b: float) -> float:
		return a + (b - a) * self.u()

	def expo(self, rate: float) -> float:
		return -math.log(1.0 - self.u()) / rate

	def pick(self, weights: list) -> int:
		tot = 0.0
		for w in weights:
			tot += w
		x = self.u() * tot
		acc = 0.0
		for i, w in enumerate(weights):
			acc += w
			if x < acc:
				return i
		return len(weights) - 1


# ---------------------------------------------------------------- retention hash (GDD 13.1)
MASK64 = (1 << 64) - 1


def fnv1a64(text: str) -> int:
	h = 0xCBF29CE484222325
	for b in text.encode("utf-8"):
		h ^= b
		h = (h * 0x100000001B3) & MASK64
	return h


def splitmix64(x: int) -> int:
	x = (x + 0x9E3779B97F4A7C15) & MASK64
	z = x
	z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
	z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK64
	return z ^ (z >> 31)


def hash_u(seed: int, *parts) -> float:
	"""Stateless retention draw in [0, 1): splitmix64(install_seed XOR fnv1a64("a|b|c")) >> 11 / 2^53.
	Retention systems never draw from the world RNG stream, so adding them cannot change the
	visitor/economy history of an existing save (GDD 13.1)."""
	key = "|".join(str(p) for p in parts)
	return (splitmix64((seed & MASK64) ^ fnv1a64(key)) >> 11) / float(1 << 53)


# ---------------------------------------------------------------- world
class Player:
	"""One save file + its world. Event-driven; advance(t) is the GDD 5.8 world step."""

	def __init__(self, C: Content, seed: int, install_local_s: float, policy: tuple) -> None:
		self.C = C
		eco = C.eco
		self.eco = eco
		self.seed = seed
		self.rng = Rng([BASE_SEED, seed, 1])
		self.install_local_s = install_local_s
		self.policy = policy
		self.t = 0.0
		# wallet / basket / cup
		self.dew = 0
		self.basket: list[int] = []
		self.cup = 0.0
		self.cup_last_t = 0.0
		self.last_collect_t = 0.0
		self.sat = float(eco["dew_cup_saturation_s"])
		self.slots = int(eco["basket_slots"])
		self.cap = int(eco["wallet_cap"])
		# garden
		self.owned_f = [0] * C.nf
		self.bloomed = [0] * C.nf
		self.owned_d = [0] * C.nd
		self.growth: list = []  # heap of (time, stage, flower)
		self.snug = 0.0
		self.cup_rate_h = float(eco["dew_cup_base_per_h"])
		# visitors
		self.present: list[list] = []  # [species, depart_t, boat_credit, pet_credit, scripted_gift]
		self.lmin = float(eco["lambda_min_per_h"]) / HOUR
		self.lmax = float(eco["lambda_max_per_h"]) / HOUR
		self.lhalf = float(eco["snug_half"])
		ob = eco["onboarding"]
		self.next_cand = float(ob["poisson_start_s"]) + self.rng.expo(self.lmax)
		self.scripted: list = []  # heap of (time, kind, payload)
		# collection
		self.discovered = [False] * C.ns
		self.discover_t = [INF] * C.ns
		self.affection = [0] * C.ns
		self.hearts = [0] * C.ns
		self.photos = [0] * C.ns
		self.postcards: set[str] = set()
		self.boats = 0
		self.novelty = 0
		self.first_visit_t = INF
		self.content_done_t = INF
		self.items_bought = 0
		self.weather_cache: dict[int, tuple] = {}
		self.basket_full_seen = False
		self.max_display = 0
		self.max_price_seen = 0
		self.e1_violations = 0
		self.purchase_log_first_bloom = False
		# ---- Retention v1 (GDD 13)
		ns = C.ns
		self.last_aff_visit_t = [-INF] * ns
		self.heart_t = [[INF] * 6 for _ in range(ns)]  # heart_t[k][h] = world t heart h was reached
		self.nest_t = [INF] * ns
		# mysteries: species debuts are held until their signs are out (never until tapped)
		self.myst_open_t = [INF] * ns
		self.debut_ok_t = [0.0 if C.sp_onboarding[k] else INF for k in range(ns)]
		self.signs: list = []  # pending signs, sorted: [appear_t, key, index]
		self.signs_scheduled = 0
		self.clues = 0
		self.var_open_t = [INF] * C.nv
		self.var_ok_t = [INF] * C.nv
		self.var_met_t = [INF] * C.nv
		self.scene_seen = [0] * C.ns_scenes
		self.scene_cast = [set() for _ in range(C.ns_scenes)]  # friends already photographed in each scene
		self.new_memories = 0
		self.h4_waiting: set = set()
		self.scene_returns = 0
		self.memories = 0
		self.missable = 0  # invariant counter: anything removed without the player seeing it

	# ------------------------------------------------------------ retention (GDD 13)
	def reqs_hold(self, reqs: list) -> bool:
		for kind, idx, mn in reqs:
			if self.count(kind, idx) < mn:
				return False
		return True

	def schedule_signs(self, t0: float, key: str, n: int, variant: bool = False) -> float:
		"""Signs of one mystery; returns the time the last one appears."""
		last = t0
		windows = (self.C.var_sign_windows if variant else self.C.sign_windows).get(n, [])
		for i, (lo, hi) in enumerate(windows):
			at = t0 + lo + (hi - lo) * hash_u(self.seed, "sign", key, i)
			self.signs.append([at, key, i])
			self.signs_scheduled += 1
			last = max(last, at)
		self.signs.sort()
		return last

	def check_mysteries(self, t: float) -> None:
		C = self.C
		for k in range(C.ns):
			if self.discovered[k] or self.myst_open_t[k] != INF or C.sp_onboarding[k]:
				continue
			if self.reqs_hold(C.sp_req[k]):
				self.myst_open_t[k] = t
				last = self.schedule_signs(t, C.species[k]["id"], len(C.sp_signs[k]))
				self.debut_ok_t[k] = last + C.debut_after_last
		if C.var_all_met and not all(self.discovered):
			return
		for v, (vid, base, reqs, _ph, _wx, n) in enumerate(C.variants):
			if self.var_open_t[v] != INF or self.hearts[base] < C.var_hearts:
				continue
			if self.reqs_hold(reqs):
				self.var_open_t[v] = t
				self.var_ok_t[v] = self.schedule_signs(t, vid, n, True)

	def tap_signs(self, now: float) -> None:
		"""The player taps every visible sign (<= max_visible at a time; the next ones fade in)."""
		while True:
			vis = [s for s in self.signs[: self.C.max_visible_signs] if s[0] <= now]
			if not vis:
				return
			for s in vis:
				self.signs.remove(s)
				self.clues += 1

	def maybe_cousin(self, t: float, k: int) -> None:
		C = self.C
		for v, (vid, base, _reqs, ph_ok, wx_ok, _n) in enumerate(C.variants):
			if base != k or self.var_met_t[v] != INF or t < self.var_ok_t[v]:
				continue
			if ph_ok is not None and self.phase(t) not in ph_ok:
				continue
			if wx_ok is not None and self.weather(t) not in wx_ok:
				continue
			if len(self.present) >= self.eco["max_present"]:
				continue  # the cousin needs a free place; it simply comes along another time
			self.var_met_t[v] = t
			self.novelty += 1

	def away_profile(self, t0: float, t1: float) -> dict:
		"""Seconds of (phase, weather) during an absence, sampled every away_sample_s."""
		step = self.C.away_sample_s
		prof: dict = {}
		t = t0
		while t < t1:
			key = (self.phase(t), self.weather(t))
			prof[key] = prof.get(key, 0.0) + min(step, t1 - t)
			t += step
		return prof

	def scene_ok(self, sc: dict, prof: dict) -> bool:
		C = self.C
		if sum(self.discovered) < sc["met_min"]:
			return False
		if not self.reqs_hold(sc["items"]):
			return False
		if self.boats < sc["boats_min"]:
			return False
		if sum(self.bloomed) < sc["stems_min"] or sum(1 for b in self.bloomed if b > 0) < sc["types_min"]:
			return False
		if sc["pair"] or sc["pair_hearts_min"]:
			best = -1
			for a in range(C.ns):
				b = C.sp_best[a]
				if self.discovered[a] and self.discovered[b]:
					best = max(best, self.hearts[a], self.hearts[b])
			if best < 0 or best < sc["pair_hearts_min"]:
				return False
		if sc["away"]:
			ok = False
			for ph_ok, wx_ok, min_s in sc["away"]:
				tot = sum(v for (ph, wx), v in prof.items()
					if (ph_ok is None or ph in ph_ok) and (wx_ok is None or wx in wx_ok))
				if tot >= min_s:
					ok = True
					break
			if not ok:
				return False
		return True

	def on_return(self, prev_end: float, now: float) -> None:
		"""GDD 13.4: at most one staged scene per return after >= min_absence_s; unseen first."""
		C = self.C
		if now - prev_end < C.scene_min_abs:
			return
		self.scene_returns += 1
		r = self.scene_returns
		if hash_u(self.seed, "scene_roll", r) >= C.scene_chance:
			return
		prof = self.away_profile(prev_end, now)
		elig = [i for i, sc in enumerate(C.scenes) if self.scene_ok(sc, prof)]
		if not elig:
			return
		unseen = [i for i in elig if self.scene_seen[i] == 0]
		pool = unseen if unseen else elig
		ws = [C.scenes[i]["weight"] for i in pool]
		x = hash_u(self.seed, "scene_pick", r) * sum(ws)
		acc = 0.0
		pick = pool[-1]
		for i, w in zip(pool, ws):
			acc += w
			if x < acc:
				pick = i
				break
		cast = self.cast(pick)
		if any(k not in self.scene_cast[pick] for k in cast):
			self.new_memories += 1  # a first-time scene, or a friend's first time in it
		self.scene_cast[pick].update(cast)
		self.scene_seen[pick] += 1
		self.memories += 1  # archived on tap or after linger_s: never lost

	def cast(self, i: int) -> list:
		"""GDD 13.4 casting: role prefer lists, then friends new to this scene (present first),
		then the rest; ties by hearts (desc) then album order. Pair scenes take a best-friend pair."""
		C = self.C
		sc = C.scenes[i]
		present = {p[0] for p in self.present}
		seen = self.scene_cast[i]
		met = [k for k in range(C.ns) if self.discovered[k]]
		def rank(k: int) -> tuple:
			return (k in seen, k not in present, -self.hearts[k], C.sp_order[k])
		if sc["pair"]:
			pairs = []
			for a in met:
				b = C.sp_best[a]
				if a < b and self.discovered[b]:
					pairs.append((min(rank(a), rank(b)), a, b))
			if not pairs:
				return []
			pairs.sort()
			return [pairs[0][1], pairs[0][2]]
		out = []
		for k in sorted(met, key=rank):
			if len(out) >= sc["roles"]:
				break
			out.append(k)
		return out

	def disc_snapshot(self) -> tuple:
		"""Player-visible discoveries for the content-left metric."""
		nests = 0
		for t0 in self.nest_t:
			if t0 != INF:
				nests += sum(1 for at in self.C.nest_stage_at[1:] if t0 + at <= self.t)
		return (sum(self.discovered), sum(self.hearts), len(self.postcards), self.clues,
			sum(1 for x in self.scene_seen if x), sum(1 for x in self.var_met_t if x != INF),
			self.new_memories, nests)

	# ------------------------------------------------------------ clock
	def local(self, t: float) -> float:
		return self.install_local_s + t

	def phase(self, t: float) -> int:
		return self.C.phase_at(self.local(t))

	def _day_plan(self, d: int) -> tuple:
		plan = self.weather_cache.get(d)
		if plan is None:
			g = Rng([BASE_SEED, self.seed, 2, d + 10000])  # d may be -1
			wp = self.C.wp
			def episodes(cum: list, lo: float, hi: float) -> list:
				x = g.u()
				n = 0
				while n < len(cum) and x >= cum[n]:
					n += 1
				out = []
				for _ in range(n):
					st = d * DAY + g.u() * DAY
					out.append((st, st + g.uniform(lo, hi)))
				return out
			rain = episodes(self.C.rain_cum, wp["rain_min_s"], wp["rain_max_s"])
			breeze = episodes(self.C.breeze_cum, wp["breeze_min_s"], wp["breeze_max_s"])
			plan = (rain, breeze)
			self.weather_cache[d] = plan
		return plan

	def weather(self, t: float) -> int:
		la = self.local(t)
		d = int(la // DAY)
		rain_hit = False
		breeze_hit = False
		for dd in (d, d - 1):
			rain, breeze = self._day_plan(dd)
			for a, b in rain:
				if a <= la < b:
					rain_hit = True
			for a, b in breeze:
				if a <= la < b:
					breeze_hit = True
		if rain_hit:
			return self.C.weather_index["rain"]
		if breeze_hit:
			return self.C.weather_index["breeze"]
		return self.C.weather_index["clear"]

	# ------------------------------------------------------------ rates
	def lam(self) -> float:
		s = self.snug
		return self.lmin + (self.lmax - self.lmin) * s / (s + self.lhalf)

	def settle_cup(self, t: float) -> None:
		end = min(t, self.last_collect_t + self.sat)
		if end > self.cup_last_t:
			self.cup += self.cup_rate_h / HOUR * (end - self.cup_last_t)
		self.cup_last_t = max(self.cup_last_t, t)

	def count(self, kind: int, idx: int) -> int:
		return self.bloomed[idx] if kind == 0 else self.owned_d[idx]

	def eligible(self, k: int, ph: int, present_ids: set, t: float) -> bool:
		if k in present_ids:
			return False
		if not self.discovered[k] and t < self.debut_ok_t[k]:
			return False  # GDD 13.3: an unmet friend debuts only after its signs are out
		ok = self.C.sp_phase_ok[k]
		if ok is not None and ph not in ok:
			return False
		for kind, idx, mn in self.C.sp_req[k]:
			if self.count(kind, idx) < mn:
				return False
		return True

	def weight(self, k: int, ph: int, wx: int) -> float:
		C = self.C
		w = C.sp_base[k]
		for kind, idx, mn, mult in C.sp_like_items[k]:
			if self.count(kind, idx) >= mn:
				w *= mult
		w *= C.sp_like_weather[k].get(wx, 1.0)
		w *= C.sp_like_phase[k].get(ph, 1.0)
		if self.hearts[k] >= self.eco["best_friend_heart"]:
			w *= self.eco["best_friend_weight_mult"]
		return w

	# ------------------------------------------------------------ events
	def add_affection(self, k: int, n: int, t: float) -> None:
		self.affection[k] += n
		h = 0
		for thr in self.C.heart_thr:
			if self.affection[k] >= thr:
				h += 1
		if h > self.hearts[k]:
			for lvl in range(self.hearts[k] + 1, h + 1):
				self.novelty += 1
				self.heart_t[k][lvl] = t
				if lvl == 4 and not self.discovered[self.C.sp_best[k]]:
					self.h4_waiting.add(k)  # chapter II introduces the best buddy: it waits for their first visit
				elif lvl in (2, 4, 5):
					self.postcards.add(f"{self.C.species[k]['id']}_h{lvl}")
				if lvl == self.C.nest_min_hearts:
					self.nest_t[k] = t
			self.hearts[k] = h
			if h >= self.C.var_hearts:
				self.check_mysteries(t)

	def take_photo(self, k: int) -> None:
		cum = self.C.sp_pose_cum[k]
		x = self.rng.u()
		p = 0
		while p < len(cum) - 1 and x >= cum[p]:
			p += 1
		bit = 1 << p
		if not self.photos[k] & bit:
			self.photos[k] |= bit
			self.novelty += 1

	def leave_gift(self, k: int, gift: int) -> None:
		if len(self.basket) < self.slots:
			self.basket.append(gift)
			self.novelty += 1
			if self.rng.u() < self.eco["photo_chance_with_gift"]:
				self.take_photo(k)
			if len(self.basket) == self.slots and not self.basket_full_seen:
				self.basket_full_seen = True
				self.postcards.add("brimming")
		else:
			self.novelty += 1
			self.take_photo(k)

	def arrive(self, t: float, k: int, stay: float, scripted_gift: int) -> None:
		C = self.C
		if not self.discovered[k]:
			self.discovered[k] = True
			self.discover_t[k] = t
			self.novelty += 1
			for j in [j for j in self.h4_waiting if C.sp_best[j] == k]:
				self.h4_waiting.discard(j)
				self.postcards.add(f"{C.species[j]['id']}_h4")
			if all(self.discovered):
				self.postcards.add("album_complete")
				self.check_mysteries(t)
		if self.first_visit_t == INF:
			self.first_visit_t = t
		ph = self.phase(t)
		if ph == C.night_idx:
			self.postcards.add("first_night")
		if self.weather(t) == C.rain_idx:
			self.postcards.add("first_rain")
		if t - self.last_aff_visit_t[k] >= C.aff_rest_s:
			# GDD 5.10 / 13.2: a visit warms a friendship at most once per visit_affection_rest_s
			self.last_aff_visit_t[k] = t
			self.add_affection(k, self.eco["affection_per_visit"], t)
		self.novelty += 1
		gift = scripted_gift if scripted_gift > 0 else C.sp_gift[k]
		if len(self.present) >= self.eco["max_present"]:
			self.leave_gift(k, gift)  # a peek visit: waves from the rim, gift goes straight to the basket
			return
		self.present.append([k, t + stay, False, False, gift])
		self.maybe_cousin(t, k)

	def candidate(self, t: float) -> None:
		if self.rng.u() * self.lmax >= self.lam():
			return
		ph = self.phase(t)
		wx = self.weather(t)
		present_ids = {p[0] for p in self.present}
		elig = [k for k in range(self.C.ns) if self.eligible(k, ph, present_ids, t)]
		if not elig:
			return
		debut = [k for k in elig if not self.discovered[k]]
		if debut and self.rng.u() < self.eco["debut_chance"]:
			pool = debut
		else:
			pool = elig
		k = pool[self.rng.pick([self.weight(j, ph, wx) for j in pool])]
		stay = self.rng.uniform(self.eco["stay_min_s"], self.eco["stay_max_s"]) * self.C.sp_stay[k]
		self.arrive(t, k, stay, 0)

	def bloom(self, t: float, f: int) -> None:
		self.settle_cup(t)
		self.bloomed[f] += 1
		self.snug += self.C.fl_snug[f]
		self.cup_rate_h += self.C.fl_dew_h[f]
		self.novelty += 1
		self.check_mysteries(t)

	def advance(self, to_t: float) -> None:
		"""Process every world event in (self.t, to_t] in time order. Never removes anything."""
		while True:
			t_dep = min((p[1] for p in self.present), default=INF)
			t_gro = self.growth[0][0] if self.growth else INF
			t_scr = self.scripted[0][0] if self.scripted else INF
			t_next = min(self.next_cand, t_dep, t_gro, t_scr)
			if t_next > to_t:
				break
			if t_next == t_scr:
				_, kind, payload = heapq.heappop(self.scripted)
				if kind == "arrive":
					k, stay, gift = payload
					self.arrive(t_scr, k, stay, gift)
				elif kind == "postcard":
					self.postcards.add(payload)
					self.novelty += 1
			elif t_next == t_gro:
				_, stage, f = heapq.heappop(self.growth)
				if stage == 2:
					self.bloom(t_gro, f)
					if f >= 0 and not self.purchase_log_first_bloom and self.items_bought > 0:
						self.purchase_log_first_bloom = True
						self.postcards.add("first_bloom")
				else:
					self.novelty += 1
			elif t_next == t_dep:
				i = min(range(len(self.present)), key=lambda j: self.present[j][1])
				k, _, _, _, gift = self.present.pop(i)
				self.leave_gift(k, gift)
			else:
				self.candidate(self.next_cand)
				self.next_cand += self.rng.expo(self.lmax)
		self.settle_cup(to_t)
		self.t = to_t

	# ------------------------------------------------------------ player actions
	def collect(self) -> int:
		self.settle_cup(self.t)
		got = 0
		keep: list[int] = []
		for g in self.basket:
			if self.dew + got + g <= self.cap:
				got += g
			else:
				keep.append(g)  # brimming wallet: the gift simply waits in the basket
		cup_whole = int(math.floor(self.cup))
		cup_take = min(cup_whole, self.cap - self.dew - got)
		self.cup -= cup_take
		got += cup_take
		self.basket = keep
		self.dew += got
		self.last_collect_t = self.t
		self.cup_last_t = self.t
		return got

	def options(self) -> list:
		C = self.C
		out = []
		for i, (b, r, mx) in enumerate(C.fl_cost):
			n = self.owned_f[i]
			if n < mx:
				out.append((0, i, C.price(b, r, n)))
		for j, (b, r, mx) in enumerate(C.de_cost):
			n = self.owned_d[j]
			if n < mx:
				out.append((1, j, C.price(b, r, n)))
		return out

	def wanted_items(self) -> set:
		"""Items named by album hints of species not yet met (players read hints)."""
		want = set()
		for k in range(self.C.ns):
			if self.discovered[k]:
				continue
			for kind, idx, mn in self.C.sp_req[k]:
				have = self.owned_f[idx] if kind == 0 else self.owned_d[idx]
				if have < mn:
					want.add((kind, idx))
		return want

	def buy(self, kind: int, idx: int, cost: int) -> None:
		C = self.C
		assert cost <= self.dew
		self.dew -= cost
		self.items_bought += 1
		if kind == 0:
			self.owned_f[idx] += 1
			s, b, bl = C.fl_times[idx]
			heapq.heappush(self.growth, (self.t + s, 0, idx))
			heapq.heappush(self.growth, (self.t + b, 1, idx))
			heapq.heappush(self.growth, (self.t + bl, 2, idx))
		else:
			if sum(self.owned_d) == 0:
				self.postcards.add("first_decor")
			self.owned_d[idx] += 1
			self.snug += C.de_snug[idx]
			self.check_mysteries(self.t)
		if self.items_bought >= C.total_items - 1 and self.content_done_t == INF:
			# total_items includes the free tutorial clover
			if not self.options():
				self.content_done_t = self.t

	def next_goal(self) -> tuple | None:
		"""The hinted item of the not-yet-met friend whose missing items are cheapest in total."""
		C = self.C
		best = None
		for k in range(C.ns):
			if self.discovered[k]:
				continue
			total = 0
			first = None
			for kind, idx, mn in C.sp_req[k]:
				have = self.owned_f[idx] if kind == 0 else self.owned_d[idx]
				b, r, _ = C.fl_cost[idx] if kind == 0 else C.de_cost[idx]
				for n in range(have, mn):
					c = C.price(b, r, n)
					total += c
					if first is None:
						first = (kind, idx, c)
			if first is not None and (best is None or total < best[0]):
				best = (total, first)
		return best[1] if best else None

	def shop(self, budget: int) -> int:
		_, _, _, buy_p, _, focus_p, save_p = self.policy
		bought = 0
		while bought < budget:
			opts = [o for o in self.options() if o[2] <= self.dew]
			if not opts:
				break
			if self.rng.u() > buy_p:
				break
			goal = self.next_goal()
			if goal is not None and self.rng.u() < focus_p:
				if goal[2] <= self.dew:
					self.buy(*goal)
					bought += 1
					continue
				if self.rng.u() < save_p:
					break
			want = self.wanted_items()
			ws = []
			for kind, idx, cost in opts:
				w = 1.0 / math.sqrt(cost)
				if (kind, idx) in want:
					w *= 3.0
				if (self.owned_f[idx] if kind == 0 else self.owned_d[idx]) == 0:
					w *= 2.0
				ws.append(w)
			kind, idx, cost = opts[self.rng.pick(ws)]
			self.buy(kind, idx, cost)
			bought += 1
		return bought

	def float_boat(self, n: int = 1) -> None:
		cost = int(self.eco["leaf_boat_cost"])
		assert n >= 1 and cost * n <= self.dew
		self.dew -= cost * n
		before = self.boats
		self.boats += n
		if before < 10 <= self.boats:
			self.postcards.add("ten_boats")
		for p in self.present:
			if not p[2]:
				p[2] = True
				self.add_affection(p[0], self.eco["affection_per_boat"], self.t)

	def pet_all(self, limit: int) -> None:
		n = 0
		for p in self.present:
			if n >= limit:
				break
			if not p[3]:
				p[3] = True
				self.add_affection(p[0], self.eco["affection_per_pet"], self.t)
				n += 1

	def snapshot(self) -> tuple:
		return (self.dew, sum(self.basket), len(self.basket), self.cup, tuple(self.affection),
			tuple(self.owned_f), tuple(self.bloomed), tuple(self.owned_d), sum(self.discovered),
			sum(bin(x).count("1") for x in self.photos), len(self.postcards),
			# retention (GDD 13.6): hearts, nests, clues + waiting signs, cousins, memories never decrease
			tuple(self.hearts), sum(1 for x in self.nest_t if x != INF), self.clues + len(self.signs),
			sum(1 for x in self.var_met_t if x != INF), self.memories, tuple(self.scene_seen))

	def check_monotone(self, before: tuple, after: tuple) -> None:
		for a, b in zip(before, after):
			if isinstance(a, tuple):
				if any(y < x for x, y in zip(a, b)):
					self.e1_violations += 1
			elif b < a - 1e-9:
				self.e1_violations += 1

	def track_display(self) -> None:
		shown = max(self.dew, sum(self.basket) + int(math.floor(self.cup)))
		for _, _, c in self.options():
			shown = max(shown, c)
			self.max_price_seen = max(self.max_price_seen, c)
		self.max_display = max(self.max_display, shown)

	def income_per_min(self) -> float:
		"""Passive income right now: dew cup rate + expected visitor gifts."""
		ph = self.phase(self.t)
		wx = self.weather(self.t)
		elig = [k for k in range(self.C.ns) if self.eligible(k, ph, set(), self.t)]
		if elig:
			ws = [self.weight(k, ph, wx) for k in elig]
			g = sum(w * self.C.sp_gift[k] for w, k in zip(ws, elig)) / sum(ws)
		else:
			g = 0.0
		return (self.cup_rate_h + self.lam() * HOUR * g) / 60.0


# ---------------------------------------------------------------- onboarding
def plant_tutorial_seed(pl: Player, plant_at_s: float) -> float:
	"""The tutorial seed is a free copy of the tutorial flower with accelerated stages."""
	ob = pl.eco["onboarding"]
	fi = pl.C.item_index[ob["tutorial_flower"]][1]
	pl.owned_f[fi] += 1
	heapq.heappush(pl.growth, (plant_at_s + ob["tutorial_sprout_at_s"], 0, fi))
	heapq.heappush(pl.growth, (plant_at_s + ob["tutorial_bud_at_s"], 1, fi))
	bloom_t = plant_at_s + ob["tutorial_bloom_at_s"]
	heapq.heappush(pl.growth, (bloom_t, 2, fi))
	return bloom_t


def start_onboarding(pl: Player, plant_at_s: float | None) -> None:
	"""GDD 3.4 script. plant_at_s None = the player did not tap the seed in the first session."""
	C = pl.C
	ob = pl.eco["onboarding"]
	if plant_at_s is not None and plant_at_s <= ob["tutorial_tap_window_s"]:
		bloom_t = plant_tutorial_seed(pl, plant_at_s)
		t1 = min(max(plant_at_s + ob["first_visitor_after_plant_s"], ob["first_visitor_min_s"]), ob["first_visitor_max_s"])
	else:
		bloom_t = INF
		t1 = float(ob["first_visitor_default_s"])
	heapq.heappush(pl.scripted, (t1, "arrive", (C.species_index[ob["first_visitor"]], float(ob["first_visitor_stay_s"]), int(ob["first_visitor_gift_dew"]))))
	t2 = min(bloom_t + ob["second_visitor_after_bloom_s"], ob["second_visitor_latest_s"])
	heapq.heappush(pl.scripted, (t2, "arrive", (C.species_index[ob["second_visitor"]], float(ob["second_visitor_stay_s"]), int(ob["second_visitor_gift_dew"]))))
	k3 = C.species_index[ob["third_visitor"]]
	stay3 = pl.rng.uniform(pl.eco["stay_min_s"], pl.eco["stay_max_s"]) * C.sp_stay[k3]
	heapq.heappush(pl.scripted, (float(ob["third_visitor_at_s"]), "arrive", (k3, stay3, 0)))
	heapq.heappush(pl.scripted, (float(ob["welcome_postcard_at_s"]), "postcard", "welcome"))


# ---------------------------------------------------------------- schedules
def random_schedule(rng: Rng, days: int = SIM_DAYS) -> tuple:
	"""Heterogeneous player: own session-length mix and own typical gap (10 min - 3 days)."""
	g = rng.g
	mix = g.dirichlet([1.0, 1.0, 1.0])
	log_med = math.log(1200.0) + rng.u() * (math.log(DAY) - math.log(1200.0))
	first = (30.0, 180.0, 300.0)[rng.pick([0.10, 0.30, 0.60])]
	sessions = [(0.0, first)]
	t = first
	end = days * DAY
	while True:
		gap = math.exp(g.normal(log_med, 1.0))
		gap = min(max(gap, GAP_MIN_S), GAP_MAX_S)
		t += gap
		if t >= end:
			break
		length = SESSION_LENGTHS_S[rng.pick(mix.tolist())]
		sessions.append((t, length))
		t += length
	install_local = 7 * HOUR + rng.u() * 16 * HOUR
	return sessions, install_local


def reference_schedule(rng: Rng, days: int = SIM_DAYS) -> tuple:
	"""GDD reference player: installs at 20:00, then 2 x 5 min per day (08:00 and 20:00 +/- 30 min)."""
	install_local = 20 * HOUR
	sessions = [(0.0, 300.0)]
	for d in range(days + 1):
		for hh in (8.0, 20.0):
			t = d * DAY + hh * HOUR + (rng.u() - 0.5) * HOUR - install_local
			if t <= 2.0 * HOUR or t >= days * DAY:
				continue  # the install session covers day 0 evening
			sessions.append((t, 300.0))
	sessions.sort()
	return sessions, install_local


def pick_policy(rng: Rng) -> tuple:
	return POLICIES[rng.pick([p[1] for p in POLICIES])]


# ---------------------------------------------------------------- one player
def run_player(args: tuple) -> dict:
	idx, kind = args
	C = CONTENT
	days = SIM_DAYS if kind == "random" else REF_DAYS
	srng = Rng([BASE_SEED, idx, 0, 0 if kind == "random" else 1])
	if kind == "random":
		sessions, install_local = random_schedule(srng, days)
	else:
		sessions, install_local = reference_schedule(srng, days)
	# reference player: half "gentle", half "keen" (GDD 9.1)
	policy = pick_policy(srng) if kind == "random" else POLICIES[0 if srng.u() < 0.5 else 1]
	pl = Player(C, idx * 2 + (0 if kind == "random" else 1), install_local, policy)
	# most players tap the sparkling seed within 3-25 s; 10 % do not tap it in the first session
	plant_at = None if srng.u() < 0.10 else srng.uniform(3.0, 25.0)
	start_onboarding(pl, plant_at)
	seed_pending = plant_at is None
	res = {
		"kind": kind, "policy": policy[0], "sessions": 0, "e5_no_afford": 0, "e5_no_new": 0,
		"organic_new": 0, "content_afford": 0, "content_afford_n": 0,
		"content_afford_ret": 0, "content_afford_ret_n": 0,
		"mid_minutes": [], "e1": 0, "max_display": 0, "max_price": 0,
	}
	last_snap = pl.snapshot()
	last_novelty = pl.novelty
	last_disc = pl.disc_snapshot()
	last_amb = None
	day_marks = (1, 3, 7, 14, 21, 30)
	species_at_day = {d: 0 for d in day_marks}
	first_session_species = None
	prev_end = 0.0
	day0 = int(install_local // DAY)
	played_days: set = set()
	new_days: set = set()
	new_by_kind = [0] * 8  # species, hearts, postcards, clues, scenes, cousins, new memories, nest stages
	strict_days: set = set()  # the plan's narrower list: species, hearts, postcards, clues, scenes, cousins
	day30 = None
	for si, (start, length) in enumerate(sessions):
		if day30 is None and start >= SIM_DAYS * DAY:
			pl.advance(SIM_DAYS * DAY)
			day30 = (pl.dew, len(pl.postcards), sum(bin(x).count("1") for x in pl.photos),
				sum(1 for h in pl.hearts if h >= 5), pl.disc_snapshot())
		pl.advance(start)
		if seed_pending and si > 0:
			plant_tutorial_seed(pl, start + 5.0)  # tapped early in the next session
			seed_pending = False
		if si > 0:
			pl.on_return(prev_end, start)  # GDD 13.4: a staged scene may be waiting
		pl.tap_signs(start)
		snap = pl.snapshot()
		pl.check_monotone(last_snap, snap)
		res["sessions"] += 1
		new = pl.novelty > last_novelty
		amb = (pl.phase(start), pl.weather(start))
		ambient_new = last_amb is not None and amb != last_amb
		# greeter rule (GDD 5.6): if nothing happened since the last close, or the hollow is empty,
		# an already-met mossling that is not here strolls in within 4-10 s (no gift, no affection)
		present_ids = {p[0] for p in pl.present}
		greeter_possible = len(pl.present) < pl.eco["max_present"] and any(
			pl.discovered[k] and k not in present_ids for k in range(C.ns))
		greeter = greeter_possible and (not new or not pl.present)
		# a mossling that stayed is visibly doing something else: behaviour bouts last at most
		# bout_max_s (< the 10 min minimum gap) and never repeat back-to-back (GDD 4.1.3)
		stayed = len(pl.present) > 0
		first = si == 0  # install session: the whole hollow plus the scripted welcome is new
		if new:
			res["organic_new"] += 1
		if not (first or new or stayed or greeter or ambient_new):
			res["e5_no_new"] += 1
		pl.collect()
		pl.track_display()
		opts = pl.options()
		cheapest_content = min((o[2] for o in opts), default=INF)
		# install session: the free tutorial seed is the affordable action
		affordable = first or pl.dew >= pl.eco["leaf_boat_cost"] or cheapest_content <= pl.dew
		if not affordable:
			res["e5_no_afford"] += 1
		if opts:
			res["content_afford_n"] += 1
			if cheapest_content <= pl.dew:
				res["content_afford"] += 1
			if start - prev_end >= 3 * HOUR:
				res["content_afford_ret_n"] += 1
				if cheapest_content <= pl.dew:
					res["content_afford_ret"] += 1
		dday = start / DAY
		mg0, mg1 = pl.eco["validation_targets"]["mid_game_days"]
		if opts and mg0 <= dday < mg1:
			ipm = pl.income_per_min()
			if ipm > 0:
				res["mid_minutes"].append(cheapest_content / ipm)
		L = int(length) if int(length) in (30, 180, 300, 600) else 300
		budget = pl.policy[2][L]
		boat_cost = int(pl.eco["leaf_boat_cost"])
		pl.pet_all(1 if L == 30 else 99)
		budget -= pl.shop(budget)
		boat_p = pl.policy[4]
		if pl.policy[0] == "drain":
			if pl.dew >= boat_cost:
				pl.float_boat(pl.dew // boat_cost)
		elif pl.dew >= boat_cost and pl.rng.u() < boat_p:
			pl.float_boat()
		pl.advance(start + length)
		pl.tap_signs(start + length)
		if L >= 180:
			# players collect and shop again when gifts arrive during a longer session
			pl.collect()
			pl.pet_all(99)
			pl.track_display()
			pl.shop(budget)
			if pl.policy[0] == "drain" and pl.dew >= boat_cost:
				pl.float_boat(pl.dew // boat_cost)
		if si == 0:
			first_session_species = sum(pl.discovered)
		# content-left (GDD 13.7): did this session show the player >= 1 new discovery?
		ld = int((install_local + start) // DAY) - day0  # local calendar day, install day = 0
		disc = pl.disc_snapshot()
		played_days.add(ld)
		if any(b > a for a, b in zip(last_disc[:6], disc[:6])):
			strict_days.add(ld)
		if any(b > a for a, b in zip(last_disc, disc)):
			new_days.add(ld)
			if ld < SIM_DAYS:
				for i, (a, b) in enumerate(zip(last_disc, disc)):
					new_by_kind[i] += b - a
		last_disc = disc
		last_snap = pl.snapshot()
		last_novelty = pl.novelty
		last_amb = (pl.phase(pl.t), pl.weather(pl.t))
		prev_end = start + length
	if day30 is None:
		pl.advance(SIM_DAYS * DAY)
		day30 = (pl.dew, len(pl.postcards), sum(bin(x).count("1") for x in pl.photos),
			sum(1 for h in pl.hearts if h >= 5), pl.disc_snapshot())
	pl.advance(days * DAY)
	for d in day_marks:
		species_at_day[d] = sum(1 for t in pl.discover_t if t <= d * DAY)
	h5 = [pl.heart_t[k][5] for k in range(C.ns)]
	# invariant: every sign ever scheduled is either collected or still waiting (never removed)
	if pl.clues + len(pl.signs) != pl.signs_scheduled:
		pl.missable += 1
	res.update({
		"e1": pl.e1_violations,
		"missable": pl.missable,
		"max_display": pl.max_display,
		"max_price": pl.max_price_seen,
		"first_visit_t": pl.first_visit_t,
		"first_session_species": first_session_species,
		"species_at_day": species_at_day,
		"all_species_day": (max(pl.discover_t) / DAY) if all(pl.discovered) else INF,
		"content_done_day": pl.content_done_t / DAY,
		"final_dew": day30[0],
		"items": pl.items_bought,
		"postcards": day30[1],
		"photos": day30[2],
		"boats": pl.boats,
		"hearts5": day30[3],
		"disc30": day30[4],
		"discover_day": [t / DAY for t in pl.discover_t],
		"new_days_30": sum(1 for d in new_days if d < SIM_DAYS),
		"strict_days_30": sum(1 for d in strict_days if d < SIM_DAYS),
		"empty_days": sorted(d for d in played_days if d not in new_days and d < 2 * SIM_DAYS),
		"played_days_30": sum(1 for d in played_days if d < SIM_DAYS),
		"new_days_30_60": sum(1 for d in new_days if SIM_DAYS <= d < 2 * SIM_DAYS),
		"played_days_30_60": sum(1 for d in played_days if SIM_DAYS <= d < 2 * SIM_DAYS),
		"new_by_kind": new_by_kind,
		"heart3_day14": sum(1 for k in range(C.ns) if pl.heart_t[k][3] <= 14 * DAY),
		"last_heart5_day": (max(h5) / DAY) if all(x != INF for x in h5) else INF,
		"heart5_day": [x / DAY for x in h5],
		"heart_day": [[pl.heart_t[k][h] / DAY for h in range(1, 6)] for k in range(C.ns)],
		"variant_day": [x / DAY for x in pl.var_met_t],
		"scenes_seen": [1 if x else 0 for x in pl.scene_seen],
		"clues": pl.clues,
		"signs_scheduled": pl.signs_scheduled,
	})
	return res


# ---------------------------------------------------------------- offline / absence tests
def absence_test() -> dict:
	"""E1/E3: play 3 reference days, then leave for 30 days (clamped to 7 d), then return."""
	C = CONTENT
	srng = Rng([BASE_SEED, 999, 0, 2])
	sessions, install_local = reference_schedule(srng)
	pl = Player(C, 99991, install_local, POLICIES[1])
	start_onboarding(pl, 10.0)
	for start, length in sessions:
		if start > 3 * DAY:
			break
		pl.advance(start)
		pl.collect()
		pl.pet_all(99)
		pl.shop(POLICIES[1][2][300])
		pl.advance(start + length)
	saved = pl.snapshot()
	saved_at = pl.t
	away = 30 * DAY
	clamp = float(C.eco["offline_clamp_s"])
	delta = min(max(away, 0.0), clamp)
	pl.advance(saved_at + delta)
	pl.on_return(saved_at, pl.t)
	after = pl.snapshot()
	viol = 0
	for a, b in zip(saved, after):
		if isinstance(a, tuple):
			viol += sum(1 for x, y in zip(a, b) if y < x)
		elif b < a:
			viol += 1
	# clock rolled back by a day: delta clamps to 0, nothing happens, nothing is lost
	before_rb = pl.snapshot()
	delta_rb = min(max(-DAY, 0.0), clamp)
	pl.advance(pl.t + delta_rb)
	rb_ok = pl.snapshot() == before_rb
	return {
		"violations": viol,
		"basket_after": len(pl.basket),
		"basket_slots": pl.slots,
		"cup_after": int(pl.cup),
		"photos_after": sum(bin(x).count("1") for x in pl.photos),
		"photos_saved": saved[9],
		"rollback_ok": rb_ok,
		"signs_waiting": len(pl.signs),
		"memories": pl.memories,
	}


def saturation_hours() -> list:
	C = CONTENT
	out = []
	eco = C.eco
	for snug in (0.0, 30.0, 60.0, 120.0, 240.0):
		lam = eco["lambda_min_per_h"] + (eco["lambda_max_per_h"] - eco["lambda_min_per_h"]) * snug / (snug + eco["snug_half"])
		out.append((snug, lam, eco["basket_slots"] / lam))
	return out


def onboarding_trace() -> list:
	"""Deterministic first five minutes (the scripted part does not depend on the RNG)."""
	C = CONTENT
	pl = Player(C, 7, 20 * HOUR, POLICIES[1])
	start_onboarding(pl, 10.0)
	events = []
	seen = set()
	for t in range(0, 301, 1):
		pl.advance(float(t))
		for k in range(C.ns):
			if pl.discovered[k] and k not in seen:
				seen.add(k)
				events.append((t, "meets " + C.species[k]["id"]))
		if pl.basket and t in (106, 226):
			events.append((t, f"basket holds {sum(pl.basket)} dew"))
	return events


# ---------------------------------------------------------------- driver
CONTENT: Content | None = None


def _init(root: str, ref_days: int = REF_DAYS) -> None:
	global CONTENT, REF_DAYS
	CONTENT = Content(load_content(Path(root)))
	REF_DAYS = ref_days


def pct(xs: list, q: float) -> float:
	xs = [x for x in xs if x != INF]
	if not xs:
		return INF
	return float(np.percentile(xs, q))


def pct_all(xs: list, q: float) -> float:
	"""Nearest-rank percentile that keeps 'never' (INF) values, so a tail cannot hide."""
	ys = sorted(xs)
	if not ys:
		return INF
	i = min(len(ys) - 1, max(0, int(math.ceil(q / 100.0 * len(ys))) - 1))
	return ys[i]


def fmt(x: float, nd: int = 1) -> str:
	if x == INF:
		return "never"
	return f"{x:,.{nd}f}"


def main() -> int:
	ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("--players", type=int, default=10000, help="random-schedule players")
	ap.add_argument("--reference", type=int, default=2000, help="2 x 5 min/day reference players")
	ap.add_argument("--workers", type=int, default=os.cpu_count() or 1)
	ap.add_argument("--root", default=str(ROOT))
	ap.add_argument("--markdown", default="", help="also write the results table to this file")
	ap.add_argument("--ref-days", type=int, default=REF_DAYS, help="days simulated for reference players")
	ap.add_argument("--quick", action="store_true", help="500 random + 200 reference players (smoke run)")
	args = ap.parse_args()
	if args.quick:
		args.players, args.reference = 500, 200

	t0 = time.time()
	_init(args.root, args.ref_days)
	C = CONTENT
	jobs = [(i, "random") for i in range(args.players)] + [(i, "reference") for i in range(args.reference)]
	with Pool(args.workers, initializer=_init, initargs=(args.root, args.ref_days)) as pool:
		results = pool.map(run_player, jobs, chunksize=64)
	rnd = [r for r in results if r["kind"] == "random"]
	ref = [r for r in results if r["kind"] == "reference"]
	absn = absence_test()
	sat = saturation_hours()
	trace = onboarding_trace()
	tg = C.eco["validation_targets"]
	dmax = C.eco["display_max"]

	rows = []
	fails = []

	def check(name: str, value: str, target: str, ok: bool) -> None:
		rows.append((name, value, target, "PASS" if ok else "FAIL"))
		if not ok:
			fails.append(name)

	n_sess = sum(r["sessions"] for r in rnd) + sum(r["sessions"] for r in ref)
	e1 = sum(r["e1"] for r in results) + absn["violations"]
	check("E1 no decrease (all sessions + 30-day absence)", f"{e1} violations", "0", e1 == 0)
	check("E1 clock rollback", "unchanged" if absn["rollback_ok"] else "changed", "unchanged", absn["rollback_ok"])
	e5a = sum(r["e5_no_afford"] for r in results)
	e5b = sum(r["e5_no_new"] for r in results)
	check("E5 sessions with nothing affordable", f"{e5a} of {n_sess:,}", "0", e5a == 0)
	check("E5 sessions with nothing new to see", f"{e5b} of {n_sess:,}", "0", e5b == 0)
	mx = max(r["max_display"] for r in results)
	check("E6 max displayed value", f"{mx:,}", f"<= {dmax:,}", mx <= dmax)
	mp = max(r["max_price"] for r in results)
	check("E6 max price", f"{mp:,}", f"<= {dmax:,}", mp <= dmax)
	fv = [r["first_visit_t"] for r in results]
	lo, hi = tg["first_visitor_s"]
	check("First visitor (s)", f"{min(fv):.0f}-{max(fv):.0f}", f"{lo}-{hi}", lo <= min(fv) and max(fv) <= hi)
	fs = [r["first_session_species"] for r in ref]
	check("Species met in the 5-min first session", f"{min(fs)}-{max(fs)}", f"{tg['species_after_first_session']}", min(fs) >= tg["species_after_first_session"])
	d1 = [r["species_at_day"][1] for r in ref]
	lo, hi = tg["reference_species_day1"]
	check("Reference: species by 24 h (median)", fmt(pct(d1, 50), 0), f"{lo}-{hi}", lo <= pct(d1, 50) <= hi)
	d7 = [r["species_at_day"][7] for r in ref]
	check("Reference: species by day 7 (median)", fmt(pct(d7, 50), 0), f">= {tg['reference_species_day7_median_min']}", pct(d7, 50) >= tg["reference_species_day7_median_min"])
	alld = [r["all_species_day"] for r in ref]
	lo, hi = tg["reference_all_species_day_median"]
	med_all = pct(alld, 50)
	check("Reference: all 12 met, day (p10 / median / p90)", f"{fmt(pct(alld, 10))} / {fmt(med_all)} / {fmt(pct(alld, 90))}", f"median {lo}-{hi}", lo <= med_all <= hi)
	never = sum(1 for x in alld if x == INF)
	check("Reference: players who never meet all 12 in 30 d", f"{never} of {len(ref)}", "0", never == 0)
	mm = [m for r in results for m in r["mid_minutes"]]
	lo, hi = tg["mid_game_next_purchase_minutes_median"]
	check(f"Next purchase, minutes of passive income (days {tg['mid_game_days'][0]}-{tg['mid_game_days'][1]}; p25 / median / p75)", f"{fmt(pct(mm, 25), 0)} / {fmt(pct(mm, 50), 0)} / {fmt(pct(mm, 75), 0)}", f"median {lo}-{hi}", lo <= pct(mm, 50) <= hi)
	lo, hi = tg["basket_saturation_hours"]
	sat_mid = sat[2][2]
	check("Basket saturation at mid-game snugness (h)", f"{sat_mid:.1f}", f"{lo}-{hi}", lo <= sat_mid <= hi)

	# ---- Retention v1 (GDD 13.7)
	nd = [r["new_days_30"] for r in ref]
	check(f"R1 Reference: days with something new, first {SIM_DAYS} (min / p10 / median)",
		f"{min(nd)} / {fmt(pct_all(nd, 10), 0)} / {fmt(pct_all(nd, 50), 0)}",
		f"median >= {tg['retention_new_days_min']}", pct_all(nd, 50) >= tg["retention_new_days_min"])
	lh = [r["last_heart5_day"] for r in ref]
	lo, hi = tg["last_heart5_day_median"]
	check("R2 Reference: day the last of 12 friends reaches 5 hearts (p10 / median / p90)",
		f"{fmt(pct_all(lh, 10))} / {fmt(pct_all(lh, 50))} / {fmt(pct_all(lh, 90))}", f"median {lo}-{hi}",
		lo <= pct_all(lh, 50) <= hi)
	h3 = [r["heart3_day14"] for r in ref]
	h3r = [r["heart3_day14"] for r in rnd]
	check(f"R3 Species at >= 3 hearts by day {tg['heart3_by_day']} (reference median / random median)",
		f"{fmt(pct_all(h3, 50), 0)} / {fmt(pct_all(h3r, 50), 0)}", f">= {tg['heart3_species_median_min']}",
		pct_all(h3, 50) >= tg["heart3_species_median_min"] and pct_all(h3r, 50) >= tg["heart3_species_median_min"])
	miss = sum(r["missable"] for r in results)
	check("R4 Missable content (signs or scenes removed unseen)", f"{miss}", "0", miss == 0)
	check("R4 30-day absence keeps waiting signs and scenes", f"{absn['signs_waiting']} signs waiting, {absn['memories']} memories",
		"nothing removed", absn["violations"] == 0)

	info = []
	frac = [r["new_days_30"] / max(r["played_days_30"], 1) for r in rnd]
	info.append((f"Random: share of played days (first {SIM_DAYS}) with something new (p10 / median)",
		f"{100 * pct_all(frac, 10):.0f} % / {100 * pct_all(frac, 50):.0f} %"))
	ndr = [r["new_days_30"] for r in rnd]
	info.append((f"Random: days with something new, first {SIM_DAYS} (p10 / median)", f"{fmt(pct_all(ndr, 10), 0)} / {fmt(pct_all(ndr, 50), 0)}"))
	if REF_DAYS >= 2 * SIM_DAYS:
		nd2 = [r["new_days_30_60"] for r in ref]
		info.append(("Reference: days 30-59 with something new (p10 / median)", f"{fmt(pct_all(nd2, 10), 0)} / {fmt(pct_all(nd2, 50), 0)}"))
	sd = [r["strict_days_30"] for r in ref]
	info.append((f"Reference: days with something new counting only friends, hearts, postcards, clues, first-time scenes and cousins (p10 / median)",
		f"{fmt(pct_all(sd, 10), 0)} / {fmt(pct_all(sd, 50), 0)}"))
	kinds = ("new friends", "heart levels", "postcards", "clues", "first-time scenes", "cousins", "new memories", "nest growth stages")
	for i, kname in enumerate(kinds):
		info.append((f"Reference: {kname} seen in the first {SIM_DAYS} days (median)", fmt(pct_all([r["new_by_kind"][i] for r in ref], 50), 0)))
	info.append((f"Reference: cousins met by day {SIM_DAYS} / by day {REF_DAYS} (median of {C.nv})",
		f"{fmt(pct_all([sum(1 for d in r['variant_day'] if d <= SIM_DAYS) for r in ref], 50), 0)} / "
		f"{fmt(pct_all([sum(1 for d in r['variant_day'] if d != INF) for r in ref], 50), 0)}"))
	info.append((f"Reference: last cousin met, day (median)", fmt(pct_all([max(r["variant_day"]) for r in ref], 50))))
	info.append((f"Reference: clues collected by day {REF_DAYS} (median of {sum(len(x) for x in C.sp_signs) + sum(v[5] for v in C.variants)})",
		fmt(pct_all([r["clues"] for r in ref], 50), 0)))
	info.append((f"Random: heart-5 friends by day {SIM_DAYS} (median)", fmt(pct_all([r["hearts5"] for r in rnd], 50), 0)))
	ca = sum(r["content_afford"] for r in results)
	can = sum(r["content_afford_n"] for r in results)
	car = sum(r["content_afford_ret"] for r in results)
	carn = sum(r["content_afford_ret_n"] for r in results)
	info.append(("Sessions where a new flower/decor copy is affordable (all gaps)", f"{100.0 * ca / max(can, 1):.1f} %"))
	info.append(("... after a gap of 3 h or more", f"{100.0 * car / max(carn, 1):.1f} %"))
	on = sum(r["organic_new"] for r in results)
	info.append(("Sessions with organic news (without the greeter rule)", f"{100.0 * on / n_sess:.1f} %"))
	cd = [r["content_done_day"] for r in ref]
	info.append(("Reference: whole catalogue bought, day (median)", fmt(pct(cd, 50))))
	cdr = [r["content_done_day"] for r in rnd]
	info.append(("Random: whole catalogue bought within 30 d", f"{100.0 * sum(1 for x in cdr if x != INF) / len(cdr):.1f} %"))
	for pol in POLICY_NAMES:
		rr = [r for r in rnd if r["policy"] == pol]
		if rr:
			info.append((f"Random '{pol}' ({len(rr)}): species by day 7 / day 30 (median)", f"{fmt(pct([r['species_at_day'][7] for r in rr], 50), 0)} / {fmt(pct([r['species_at_day'][30] for r in rr], 50), 0)}"))
	info.append(("Final wallet after 30 d (median / max)", f"{fmt(pct([r['final_dew'] for r in results], 50), 0)} / {max(r['final_dew'] for r in results):,}"))
	info.append((f"Postcards by day 30, reference (median of {3 * C.ns + len(C.eco['event_postcards'])})", fmt(pct([r["postcards"] for r in ref], 50), 0)))
	info.append(("Photo poses by day 30, reference (median of 60)", fmt(pct([r["photos"] for r in ref], 50), 0)))
	info.append(("Best friends (5 hearts) by day 30, reference (median)", fmt(pct([r["hearts5"] for r in ref], 50), 0)))
	info.append(("30-day absence: basket after return", f"{absn['basket_after']} / {absn['basket_slots']} slots, cup {absn['cup_after']} dew, photos {absn['photos_saved']} -> {absn['photos_after']}"))
	per_species = []
	for k, s in enumerate(C.species):
		ds = [r["discover_day"][k] for r in ref]
		hd = [[r["heart_day"][k][h] for r in ref] for h in range(5)]
		vd = [r["variant_day"][k] for r in ref]
		per_species.append((s["id"], fmt(pct(ds, 50), 2), fmt(pct(ds, 90), 2),
			" / ".join(fmt(pct_all(x, 50), 0) for x in hd), fmt(pct_all(hd[4], 90), 0), fmt(pct_all(vd, 50), 0)))
	scene_rows = []
	for i, sc in enumerate(C.scenes):
		seen = [r["scenes_seen"][i] for r in ref]
		scene_rows.append((sc["id"], f"{100.0 * sum(seen) / len(seen):.0f} %"))

	lines = []
	lines.append(f"Simulated {len(rnd):,} random-schedule players + {len(ref):,} reference players (2 x 5 min/day), {SIM_DAYS} days (reference {REF_DAYS} days), {n_sess:,} sessions, seed {BASE_SEED}, {time.time() - t0:.0f} s.")
	lines.append("")
	lines.append("| Check | Result | Target | Verdict |")
	lines.append("|---|---|---|---|")
	for r in rows:
		lines.append(f"| {r[0]} | {r[1]} | {r[2]} | {r[3]} |")
	lines.append("")
	lines.append("| Informational metric | Value |")
	lines.append("|---|---|")
	for a, b in info:
		lines.append(f"| {a} | {b} |")
	lines.append("")
	lines.append("| Species (reference player) | Met by day (median) | p90 | Hearts 1/2/3/4/5 by day (median) | Heart 5 p90 | Cousin met, day (median) |")
	lines.append("|---|---|---|---|---|---|")
	for row in per_species:
		lines.append("| " + " | ".join(row) + " |")
	lines.append("")
	lines.append(f"| Scene (reference player) | Seen within {REF_DAYS} days |")
	lines.append("|---|---|")
	for a, b in scene_rows:
		lines.append(f"| {a} | {b} |")
	lines.append("")
	lines.append("| Snugness | lambda (visits/h) | Basket full after (h) |")
	lines.append("|---|---|---|")
	for s, lam, h in sat:
		lines.append(f"| {s:.0f} | {lam:.2f} | {h:.1f} |")
	lines.append("")
	lines.append("Onboarding trace (first 300 s): " + "; ".join(f"{t} s {e}" for t, e in trace))
	text = "\n".join(lines)
	print(text)
	if args.markdown:
		Path(args.markdown).write_text(text + "\n", encoding="utf-8")
	if fails:
		print("\nFAILED: " + ", ".join(fails), file=sys.stderr)
		return 1
	print("\nALL CHECKS PASS")
	return 0


if __name__ == "__main__":
	sys.exit(main())
