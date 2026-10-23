#!/usr/bin/env python3
"""Validate Mossling Meadow content data and translations (docs/GDD.md section 10-11).

Checks:
  * every data/*.json file parses and carries "schema": 1
  * ids are unique snake_case; every cross-reference resolves (items, spots, entries, anchors, postcards)
  * economy rules from GDD 5: cost_growth in [1.10, 1.12], max_copies in [10, 12], all prices <= display_max,
    durations positive and increasing, positions inside the frame, anchors hold max_copies positions
  * layout: required/optional tap targets meet the hit-size floors and keep >= 8 dp gaps (I2)
  * i18n/strings.csv: header keys,en,vi; UTF-8 without BOM; NFC; every referenced key present with both
    languages; {placeholders} identical in en and vi; no banned urgency/guilt words (E8)
  * Retention v1 (GDD 13): friendship.json, mysteries.json, scenes.json and the species fields
    signature_gift / nest_style / best_friend / postcard_heart5: cross-references, symmetric best
    friends, unique 3-part postcard stories, timing windows, sign anchors (hit floors, 8 dp gaps, clear
    of beds/props/spots/nests), variant palettes (cr_* tokens that exist in palettes.json, fur within the
    V2 saturation band), scene conditions, casts and caption placeholders
  * Active Play v1 (GDD 14): wishes.json (target grammar, references, the "fulfillable now" requires,
    traits, coverage), tea.json (recipes unique and well-formed, fallbacks, preferences, petals, teaware,
    the tea nook as a static tap target), decor_placement.json (every set, rotation renders, the walkable
    rim, legacy anchors valid or nudgeable out of hard exclusions, derived spots, stream-stone reach for
    the F1 stones wish, hit floors) and sound-cue ids unique across the three features

Usage:
  python3 tools/sim/validate_content.py           # validate, exit 1 on any problem
  python3 tools/sim/validate_content.py --format  # also rewrite data/*.json in canonical layout
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import math
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA_FILES = ("species", "flora", "decor", "economy", "world", "spots", "friendship", "mysteries", "scenes",
	"wishes", "tea", "decor_placement")
SNAKE = re.compile(r"^[a-z][a-z0-9_]*$")
KEY = re.compile(r"^[A-Z][A-Z0-9_]*$")
PLACEHOLDER = re.compile(r"\{([a-z_]+)\}")
PX_PER_DP = 3.0
FRAME_W = 1080.0
FRAME_H = 1920.0
GAP_DP = 8.0
PLAY_HIT_MIN_DP = 60.0
LOOK_HIT_MIN_DP = 64.0

# E8 copy rules. Matched case-insensitively on word boundaries.
BANNED_EN = [
	r"hurry", r"rush", r"urgent", r"quick(ly)?!", r"last chance", r"limited", r"expire[sd]?", r"expiring",
	r"ending soon", r"don'?t miss", r"miss(ed|es)? (you|out)", r"streaks?", r"daily", r"every day",
	r"come back", r"lonely", r"sad", r"hungry", r"starving", r"thirsty", r"wilt(ed|ing|s)?", r"wither(ed|ing|s)?",
	r"dead", r"die[ds]?", r"dying", r"lost", r"lose", r"fail(ed|s|ure)?", r"error", r"wrong", r"penalty",
	r"punish\w*", r"waste[ds]?", r"only \d+ left", r"now or never", r"before it'?s gone", r"deadline",
	r"countdown", r"boost", r"premium", r"buy now", r"sale", r"deal", r"exclusive", r"neglect\w*",
	r"abandon\w*", r"forgot(ten)?", r"timer",
]
BANNED_VI = [
	r"nhanh lên", r"khẩn", r"gấp gáp", r"cơ hội cuối", r"sắp hết", r"hết hạn", r"giới hạn", r"có hạn",
	r"bỏ lỡ", r"chuỗi ngày", r"điểm danh", r"mỗi ngày", r"hằng ngày", r"hàng ngày", r"quay lại ngay",
	r"nhớ bạn", r"cô đơn", r"buồn(?! ngủ)", r"đói", r"khát", r"héo", r"chết", r"mất", r"thua", r"thất bại",
	r"lỗi", r"sai", r"phạt", r"lãng phí", r"bỏ rơi", r"khuyến mãi", r"giảm giá", r"độc quyền", r"đếm ngược",
]


class Report:
	def __init__(self) -> None:
		self.errors: list[str] = []

	def err(self, msg: str) -> None:
		self.errors.append(msg)


# ---------------------------------------------------------------- canonical JSON layout
def _dump(v, indent: int) -> str:
	pad = "\t" * indent
	compact = json.dumps(v, ensure_ascii=False, separators=(", ", ": "))
	if not isinstance(v, (dict, list)) or len(compact) + len(pad) <= 110:
		return compact
	if isinstance(v, list):
		inner = [pad + "\t" + _dump(x, indent + 1) for x in v]
		return "[\n" + ",\n".join(inner) + "\n" + pad + "]"
	inner = [pad + "\t" + json.dumps(k, ensure_ascii=False) + ": " + _dump(x, indent + 1) for k, x in v.items()]
	return "{\n" + ",\n".join(inner) + "\n" + pad + "}"


def format_file(path: Path) -> None:
	data = json.loads(path.read_text(encoding="utf-8"))
	path.write_text(_dump(data, 0) + "\n", encoding="utf-8")


# ---------------------------------------------------------------- data
def load(rep: Report) -> dict:
	out = {}
	for name in DATA_FILES:
		p = ROOT / "data" / f"{name}.json"
		try:
			out[name] = json.loads(p.read_text(encoding="utf-8"))
		except Exception as e:  # noqa: BLE001 - report every parse problem
			rep.err(f"{p}: {e}")
			continue
		if out[name].get("schema") != 1:
			rep.err(f"{name}.json: schema must be 1")
	return out


def price(base: float, growth: float, n: int) -> int:
	return int(base * growth ** n + 0.5)


def check_data(d: dict, rep: Report) -> set:
	keys: set[str] = set()
	eco = d["economy"]
	dmax = eco["display_max"]
	flowers = d["flora"]["flowers"]
	decor = d["decor"]["decor"]
	species = d["species"]["species"]
	spots = d["spots"]
	world = d["world"]
	ids: dict[str, str] = {}

	def reg(kind: str, i: str) -> None:
		if not SNAKE.match(i):
			rep.err(f"{kind} id '{i}' is not snake_case")
		if i in ids and kind in ("flower", "decor") and ids[i] in ("flower", "decor"):
			rep.err(f"duplicate item id '{i}'")
		ids.setdefault(i, kind)

	items = {}
	for f in flowers:
		reg("flower", f["id"])
		items[f["id"]] = f
		keys.update([f["name_key"], f["desc_key"]])
		if not (f["sprout_at_s"] > 0 and f["sprout_at_s"] < f["bud_at_s"] < f["bloom_at_s"]):
			rep.err(f"{f['id']}: stage times must increase")
	for x in decor:
		reg("decor", x["id"])
		items[x["id"]] = x
		keys.update([x["name_key"], x["desc_key"]])
	for it in items.values():
		if not (1.10 <= it["cost_growth"] <= 1.12):
			rep.err(f"{it['id']}: cost_growth {it['cost_growth']} outside [1.10, 1.12]")
		if not (10 <= it["max_copies"] <= 12):
			rep.err(f"{it['id']}: max_copies {it['max_copies']} outside [10, 12]")
		top = price(it["cost_base"], it["cost_growth"], it["max_copies"] - 1)
		if top > dmax:
			rep.err(f"{it['id']}: top price {top} > {dmax}")
	spot_ids = {s["id"] for s in spots["spots"]}
	entry_ids = {e["id"] for e in spots["entries"]}
	phase_ids = {p["id"] for p in world["phases"]}
	weather_ids = {w["id"] for w in world["weather"]}
	season_ids = {s["id"] for s in world["seasons"]}
	for s in species:
		reg("species", s["id"])
		for k in ("name_key", "default_name_key", "desc_key", "hint_key", "postcard_heart2", "postcard_heart4"):
			keys.add(s[k])
		if s["favourite_spot"] not in spot_ids:
			rep.err(f"{s['id']}: unknown favourite_spot {s['favourite_spot']}")
		if s["entry"] not in entry_ids:
			rep.err(f"{s['id']}: unknown entry {s['entry']}")
		for r in s["requires"] + s["likes_items"]:
			if r["item"] not in items:
				rep.err(f"{s['id']}: unknown item {r['item']}")
			elif r["min"] > items[r["item"]]["max_copies"]:
				rep.err(f"{s['id']}: needs {r['min']} {r['item']} but max is {items[r['item']]['max_copies']}")
		for p in s["phases"] + [l["phase"] for l in s["likes_phases"]]:
			if p not in phase_ids:
				rep.err(f"{s['id']}: unknown phase {p}")
		for l in s["likes_weather"]:
			if l["weather"] not in weather_ids:
				rep.err(f"{s['id']}: unknown weather {l['weather']}")
		if set(s["behaviours"]) != {"nap", "nibble", "play", "wander", "sit_by_stream"}:
			rep.err(f"{s['id']}: behaviours must list exactly the five behaviours")
		if abs(sum(s["behaviours"].values()) - 1.0) > 1e-6:
			rep.err(f"{s['id']}: behaviour weights must sum to 1")
		if "spring" not in s["seasons"]:
			rep.err(f"{s['id']}: MVP species must visit in spring")
		fav = next((x for x in spots["spots"] if x["id"] == s["favourite_spot"]), None)
		if fav and fav["requires_item"]:
			ok = any(r["item"] == fav["requires_item"] and r["min"] >= fav["requires_min"] for r in s["requires"])
			if not ok:
				rep.err(f"{s['id']}: favourite spot {fav['id']} may not exist when it visits")
		for k in ("fur", "fur_2", "belly", "accent"):
			if not s["rig"][k].startswith("cr_"):
				rep.err(f"{s['id']}: rig.{k} must be a cr_* creature token")
	for p in eco["event_postcards"]:
		keys.add(p["template"])
	gift_ids = set()
	for g in eco["gift_items"]:
		gift_ids.add(g["id"])
		keys.add(g["name_key"])
	for s in species:
		if s["gift_item"] not in gift_ids:
			rep.err(f"{s['id']}: unknown gift_item {s['gift_item']}")
	for k in ("first_visitor", "second_visitor", "third_visitor"):
		if eco["onboarding"][k] not in {s["id"] for s in species}:
			rep.err(f"onboarding.{k} unknown")
	if eco["onboarding"]["tutorial_flower"] not in items:
		rep.err("onboarding.tutorial_flower unknown")
	ob = eco["onboarding"]
	if not (ob["first_visitor_min_s"] <= ob["first_visitor_default_s"] <= ob["first_visitor_max_s"]):
		rep.err("onboarding: default first visitor time outside its window")
	for ph in world["phases"]:
		keys.add(ph["name_key"])
	for w in world["weather"]:
		keys.add(w["name_key"])
	for se in world["seasons"]:
		keys.add(se["name_key"])
	for sid in world["season_cycle"]:
		if sid not in season_ids:
			rep.err(f"season_cycle: unknown {sid}")
	# spots / layout
	for s in spots["spots"]:
		keys.add(s["name_key"])
		if s["requires_item"] and s["requires_item"] not in items:
			rep.err(f"spot {s['id']}: unknown requires_item")
	for b in spots["beds"]:
		keys.add(b["name_key"])
		if len(b["stems"]) != b["capacity"]:
			rep.err(f"{b['id']}: stems != capacity")
	total_stems = sum(b["capacity"] for b in spots["beds"])
	need = sum(f["max_copies"] for f in flowers)
	if total_stems < need:
		rep.err(f"beds hold {total_stems} stems but flowers allow {need}")
	anchors = {a["decor_id"]: a for a in spots["decor_anchors"]}
	for x in decor:
		a = anchors.get(x["anchor"])
		if a is None:
			rep.err(f"{x['id']}: missing anchor")
		elif len(a["positions"]) != x["max_copies"]:
			rep.err(f"{x['id']}: anchor has {len(a['positions'])} positions, max_copies {x['max_copies']}")
	check_layout(spots, rep, d.get("tea"))
	keys |= check_retention(d, rep)
	keys |= check_active(d, rep)
	return keys


# ---------------------------------------------------------------- Retention v1 (GDD 13)
def _hsv(hex_colour: str) -> tuple:
	h = hex_colour.lstrip("#")
	r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
	mx, mn = max(r, g, b), min(r, g, b)
	return (0.0 if mx == 0 else (mx - mn) / mx), mx


def _rect_gap_px(a: tuple, b: tuple) -> float:
	"""a, b = (x, y, w_dp, h_dp); returns the larger axis gap in px (negative = overlap)."""
	gx = abs(a[0] - b[0]) * FRAME_W - (a[2] + b[2]) * PX_PER_DP / 2.0
	gy = abs(a[1] - b[1]) * FRAME_H - (a[3] + b[3]) * PX_PER_DP / 2.0
	return max(gx, gy)


def _dist_dp(ax: float, ay: float, bx: float, by: float) -> float:
	return ((ax - bx) ** 2 * FRAME_W ** 2 + (ay - by) ** 2 * FRAME_H ** 2) ** 0.5 / PX_PER_DP


def check_retention(d: dict, rep: Report) -> set:
	keys: set[str] = set()
	eco, spots, world = d["economy"], d["spots"], d["world"]
	fr, my, sc = d["friendship"], d["mysteries"], d["scenes"]
	species = d["species"]["species"]
	sp_by = {s["id"]: s for s in species}
	items = {x["id"]: x for x in d["flora"]["flowers"] + d["decor"]["decor"]}
	phase_ids = {p["id"] for p in world["phases"]}
	weather_ids = {w["id"] for w in world["weather"]}
	spot_by = {s["id"]: s for s in spots["spots"]}
	zones = {z["id"]: z for z in spots["zones"]}
	dock_y0 = zones["dock"]["y0"]
	tend_y0 = zones["tend"]["y0"]
	gap_n = GAP_DP * PX_PER_DP / FRAME_H
	pal_path = ROOT / "data" / "palettes.json"
	tokens = json.loads(pal_path.read_text(encoding="utf-8"))["creatures"]["tokens"]
	motion = json.loads((ROOT / "data" / "motion_tokens.json").read_text(encoding="utf-8"))
	gifts = {g["id"]: g for g in eco["signature_gift_items"]}
	for g in gifts.values():
		keys.add(g["name_key"])
		if g["id"] in {x["id"] for x in eco["gift_items"]} or not SNAKE.match(g["id"]):
			rep.err(f"signature gift {g['id']}: id must be snake_case and distinct from gift_items")
	n_hearts = len(eco["heart_thresholds"])
	for name, doc in (("friendship", fr), ("mysteries", my), ("scenes", sc)):
		if not doc.get("doc"):
			rep.err(f"{name}.json: missing doc string")
	if "visit_affection_rest_s" not in eco or not (0 <= eco["visit_affection_rest_s"] <= 86400):
		rep.err("economy.visit_affection_rest_s missing or outside [0, 86400]")
	# ---- species fields
	style_ids = {x["id"] for x in fr["nest"]["styles"]}
	story_keys: dict[str, str] = {}
	sig_seen: dict[str, str] = {}
	for s in species:
		sid = s["id"]
		for f in ("signature_gift", "nest_style", "best_friend", "postcard_heart5"):
			if f not in s:
				rep.err(f"{sid}: missing {f}")
		g = gifts.get(s.get("signature_gift"))
		if g is None:
			rep.err(f"{sid}: signature_gift {s.get('signature_gift')} is not in economy.signature_gift_items")
		elif g.get("signature_of") != sid:
			rep.err(f"{sid}: gift {g['id']} must declare signature_of = {sid}")
		if s.get("signature_gift") in sig_seen:
			rep.err(f"{sid}: signature gift shared with {sig_seen[s['signature_gift']]}")
		sig_seen[s.get("signature_gift")] = sid
		if s.get("nest_style") not in style_ids:
			rep.err(f"{sid}: unknown nest_style {s.get('nest_style')}")
		bf = s.get("best_friend")
		if bf not in sp_by or bf == sid:
			rep.err(f"{sid}: best_friend {bf} must be another species")
		elif sp_by[bf].get("best_friend") != sid:
			rep.err(f"{sid}: best_friend {bf} is not symmetric")
		for f in ("postcard_heart2", "postcard_heart4", "postcard_heart5"):
			k = s.get(f, "")
			keys.add(k)
			if k in story_keys:
				rep.err(f"{sid}: {f} {k} is already used by {story_keys[k]} (each friend has its own story)")
			story_keys[k] = sid
	for g in gifts.values():
		if "signature_of" in g and g["signature_of"] not in sp_by:
			rep.err(f"gift {g['id']}: unknown signature_of")
	# ---- friendship.json
	hs = [h["heart"] for h in fr["heart_unlocks"]]
	if hs != list(range(1, n_hearts + 1)):
		rep.err(f"friendship.heart_unlocks must list hearts 1..{n_hearts} in order")
	for h in fr["heart_unlocks"]:
		keys.update([h["toast_key"], h["album_key"]])
	keys.update(x["name_key"] for x in fr["nest"]["styles"])
	keys.update(x["name_key"] for x in fr["nest"]["stages"])
	keys.update([fr["signature_gift"]["note_key"], fr["pair"]["album_key"], fr["keepsake"]["album_key"],
		fr["celebration"]["offline_recap_key"], fr["celebration"]["toast_title_key"]])
	at = [x["at_s"] for x in fr["nest"]["stages"]]
	if not at or at[0] != 0 or any(b <= a for a, b in zip(at, at[1:])):
		rep.err("friendship.nest.stages: at_s must start at 0 and increase")
	for f in ("min_hearts",):
		for block in ("nest", "keepsake"):
			if not (1 <= fr[block][f] <= n_hearts):
				rep.err(f"friendship.{block}.{f} outside 1..{n_hearts}")
	if not (1 <= fr["pair"]["min_hearts_either"] <= n_hearts):
		rep.err("friendship.pair.min_hearts_either out of range")
	if abs(sum(fr["pair"]["weights"].values()) - 1.0) > 1e-6:
		rep.err("friendship.pair.weights must sum to 1")
	if set(fr["pair"]["pose_ids"]) != set(fr["pair"]["weights"]):
		rep.err("friendship.pair.pose_ids must name a pose for every pair behaviour")
	for sp_id in fr["pair"]["nap_spots"]:
		if sp_id not in spot_by or spot_by[sp_id]["capacity"] < 2:
			rep.err(f"friendship.pair.nap_spots: {sp_id} must be a spot with capacity >= 2")
	cel = fr["celebration"]
	if cel["motion_token"] not in motion["tokens"]:
		rep.err(f"friendship.celebration.motion_token {cel['motion_token']} not in motion_tokens.tokens")
	if cel["max_duration_ms"] > 1000 or cel["input_block_ms"] != 0:
		rep.err("friendship.celebration: <= 1000 ms and no input block (plan P2 Creatures)")
	wv = fr["wave_on_open"]
	if not (0 < wv["delay_min_s"] <= wv["delay_max_s"]):
		rep.err("friendship.wave_on_open: delays must be positive and ordered")
	nest_hw = fr["nest"]["visual_w_dp"] * PX_PER_DP / FRAME_W / 2.0
	nest_hh = fr["nest"]["visual_h_dp"] * PX_PER_DP / FRAME_H / 2.0
	nests = {}
	for a in fr["nest"]["anchors"]:
		if a["species"] not in sp_by or a["species"] in nests:
			rep.err(f"nest anchor: unknown or duplicate species {a['species']}")
		nests[a["species"]] = (a["x"], a["y"])
		if a["x"] - nest_hw < 0 or a["x"] + nest_hw > 1 or a["y"] + nest_hh > dock_y0 - gap_n:
			rep.err(f"nest {a['species']}: outside the frame or reaching the dock")
		for p in spots["props"]:
			if p["hit_dp"] > 0 and _rect_gap_px((a["x"], a["y"], fr["nest"]["visual_w_dp"], fr["nest"]["visual_h_dp"]),
					(p["x"], p["y"], p["hit_dp"], p["hit_dp"])) < GAP_DP * PX_PER_DP:
				rep.err(f"nest {a['species']}: closer than {GAP_DP} dp to the {p['id']} tap target")
		fav = spot_by.get(sp_by.get(a["species"], {}).get("favourite_spot"))
		if fav and _dist_dp(a["x"], a["y"], fav["x"], fav["y"]) > 60:
			rep.err(f"nest {a['species']}: more than 60 dp from its favourite spot")
	if set(nests) != set(sp_by):
		rep.err("friendship.nest.anchors must place one nest per species")
	nl = list(nests.items())
	for i in range(len(nl)):
		for j in range(i + 1, len(nl)):
			if _dist_dp(*nl[i][1], *nl[j][1]) < 30:
				rep.err(f"nests {nl[i][0]} and {nl[j][0]} closer than 30 dp")
	# ---- mysteries.json
	types = {t["id"]: t for t in my["sign_types"]}
	for t in types.values():
		keys.update([t["name_key"], t["a11y_key"]])
	anchors = my["anchors"]
	ids = [a["id"] for a in anchors]
	if len(set(ids)) != len(ids):
		rep.err("mysteries.anchors: duplicate ids")
	beds = spots["beds"]
	for a in anchors:
		in_look = a["y"] < tend_y0
		floor = LOOK_HIT_MIN_DP if in_look else PLAY_HIT_MIN_DP
		if a["hit_dp"] < floor:
			rep.err(f"sign anchor {a['id']}: hit {a['hit_dp']} dp below {floor} dp")
		hw = a["hit_dp"] * PX_PER_DP / FRAME_W / 2.0
		hh = a["hit_dp"] * PX_PER_DP / FRAME_H / 2.0
		if a["x"] - hw < 0 or a["x"] + hw > 1:
			rep.err(f"sign anchor {a['id']}: hit area crosses a side edge")
		if a["y"] + hh > dock_y0 - gap_n or a["y"] - hh < zones["look"]["y0"]:
			rep.err(f"sign anchor {a['id']}: hit area outside the look/tend zones")
		for t in a["types"]:
			if t not in types:
				rep.err(f"sign anchor {a['id']}: unknown sign type {t}")
		for b in beds:  # a sign may sit over a bed's edge (sign wins the tap) but never on its centre area
			if abs(a["x"] - b["x"]) * FRAME_W < b["hit_w_dp"] * PX_PER_DP / 2 and abs(a["y"] - b["y"]) * FRAME_H < b["hit_h_dp"] * PX_PER_DP / 2:
				rep.err(f"sign anchor {a['id']}: centre inside {b['id']}")
		for p in spots["props"]:
			if p["hit_dp"] > 0 and _rect_gap_px((a["x"], a["y"], a["hit_dp"], a["hit_dp"]), (p["x"], p["y"], p["hit_dp"], p["hit_dp"])) < GAP_DP * PX_PER_DP:
				rep.err(f"sign anchor {a['id']}: closer than {GAP_DP} dp to the {p['id']} tap target")
		for s2 in spots["spots"]:
			if _dist_dp(a["x"], a["y"], s2["x"], s2["y"]) < 30:
				rep.err(f"sign anchor {a['id']}: within 30 dp of spot {s2['id']} (a resting mossling would cover it)")
		for sp_id, (nx, ny) in nests.items():
			if _dist_dp(a["x"], a["y"], nx, ny) < 30:
				rep.err(f"sign anchor {a['id']}: within 30 dp of the {sp_id} nest")
	for i in range(len(anchors)):
		for j in range(i + 1, len(anchors)):
			a, b = anchors[i], anchors[j]
			if _rect_gap_px((a["x"], a["y"], a["hit_dp"], a["hit_dp"]), (b["x"], b["y"], b["hit_dp"], b["hit_dp"])) < GAP_DP * PX_PER_DP:
				rep.err(f"sign anchors {a['id']} and {b['id']} closer than {GAP_DP} dp")
	for t in types:
		n = sum(1 for a in anchors if t in a["types"])
		if n < my["max_visible"]:
			rep.err(f"sign type {t}: only {n} anchors for max_visible {my['max_visible']}")
	def check_windows(name: str, table: dict) -> None:
		for n, ws in table.items():
			if len(ws) != int(n):
				rep.err(f"mysteries.{name}[{n}]: needs {n} windows")
			prev = 0
			for lo, hi in ws:
				if not (0 < lo < hi) or lo < prev:
					rep.err(f"mysteries.{name}[{n}]: windows must be positive, ordered and non-empty")
				prev = lo
	check_windows("sign_windows_s", my["sign_windows_s"])
	check_windows("variant_sign_windows_s", my["variant_sign_windows_s"])
	ob = eco["onboarding"]
	onboard = {ob["first_visitor"], ob["second_visitor"], ob["third_visitor"]}
	seen_sp = set()
	for r in my["species"]:
		sid = r["species"]
		seen_sp.add(sid)
		keys.add(r["riddle_key"])
		if sid not in sp_by:
			rep.err(f"mysteries.species: unknown {sid}")
			continue
		if r["onboarding"] != (sid in onboard):
			rep.err(f"mysteries.species {sid}: onboarding flag must match economy.onboarding")
		if r["tint"] not in tokens:
			rep.err(f"mysteries.species {sid}: tint {r['tint']} is not a palettes.json creature token")
		if not r["onboarding"]:
			if not sp_by[sid]["requires"]:
				rep.err(f"mysteries.species {sid}: a mystery needs a requires list to open")
			if not r["signs"] or r["signs"][-1] != "note" or str(len(r["signs"])) not in my["sign_windows_s"]:
				rep.err(f"mysteries.species {sid}: 1-3 signs ending with the riddle note")
		elif r["signs"]:
			rep.err(f"mysteries.species {sid}: onboarding friends arrive without signs")
		for t in r["signs"]:
			if t not in types:
				rep.err(f"mysteries.species {sid}: unknown sign type {t}")
	if seen_sp != set(sp_by):
		rep.err("mysteries.species must list every species once")
	var_sp = []
	for v in my["variants"]:
		vid = v["id"]
		if not SNAKE.match(vid):
			rep.err(f"variant id {vid} is not snake_case")
		keys.update([v["name_key"], v["desc_key"], v["riddle_key"]])
		base = sp_by.get(v["species"])
		var_sp.append(v["species"])
		if base is None:
			rep.err(f"variant {vid}: unknown species")
			continue
		if set(v["rig"]) != {"fur", "fur_2", "belly", "accent"}:
			rep.err(f"variant {vid}: rig must override exactly fur, fur_2, belly, accent")
		for slot, tok in v["rig"].items():
			if not tok.startswith("cr_") or tok not in tokens:
				rep.err(f"variant {vid}: rig.{slot} {tok} is not a palettes.json creature token")
		diff = sum(1 for k2 in ("fur", "fur_2", "belly", "accent") if v["rig"].get(k2) != base["rig"][k2])
		if v["rig"].get("fur") == base["rig"]["fur"] or diff < 2:
			rep.err(f"variant {vid}: must change the fur and at least 2 slots")
		if v["rig"].get("fur") in tokens:
			sat, val = _hsv(tokens[v["rig"]["fur"]])
			if sat > 0.45 or val < 0.45:
				rep.err(f"variant {vid}: fur outside the V2 band (S {sat:.2f}, V {val:.2f})")
		for t in v["signs"]:
			if t not in types:
				rep.err(f"variant {vid}: unknown sign type {t}")
		if str(len(v["signs"])) not in my["variant_sign_windows_s"]:
			rep.err(f"variant {vid}: no variant_sign_windows_s for {len(v['signs'])} signs")
		c = v["condition"]
		for r in c["items"]:
			if r["item"] not in items or r["min"] > items[r["item"]]["max_copies"]:
				rep.err(f"variant {vid}: impossible item condition {r}")
		for p in c["arrival_phases"]:
			if p not in phase_ids:
				rep.err(f"variant {vid}: unknown phase {p}")
		if base["phases"] and c["arrival_phases"] and not set(base["phases"]) & set(c["arrival_phases"]):
			rep.err(f"variant {vid}: arrival phases never overlap the base species' phases")
		for w in c["arrival_weather"]:
			if w not in weather_ids:
				rep.err(f"variant {vid}: unknown weather {w}")
	if sorted(var_sp) != sorted(sp_by):
		rep.err("mysteries.variants: exactly one variant per species")
	if not (1 <= my["variant_hearts_required"] <= n_hearts) or my["cousin_every_n_visits"] < 1:
		rep.err("mysteries: variant_hearts_required / cousin_every_n_visits out of range")
	# ---- scenes.json
	if sc["min_absence_s"] < 7200 or sc["max_per_return"] != 1 or not (0 < sc["scene_chance"] <= 1):
		rep.err("scenes: min_absence_s >= 7200, max_per_return = 1, 0 < scene_chance <= 1")
	known_cond = {"met_min", "items", "boats_min", "bloomed_stems_min", "bloomed_types_min", "pair_hearts_min", "away"}
	sids = [x["id"] for x in sc["scenes"]]
	if len(set(sids)) != len(sids):
		rep.err("scenes: duplicate ids")
	for x in sc["scenes"]:
		xid = x["id"]
		keys.update([x["title_key"], x["caption_key"], x["teaser_key"]])
		an = x["anchor"]
		if "spot" in an:
			if an["spot"] not in spot_by:
				rep.err(f"scene {xid}: unknown anchor spot")
			elif spot_by[an["spot"]]["requires_item"]:
				rep.err(f"scene {xid}: anchor spot may not exist")
			ax, ay = (spot_by[an["spot"]]["x"], spot_by[an["spot"]]["y"]) if an["spot"] in spot_by else (0.5, 0.5)
		elif "nest_of" in an:
			if an["nest_of"] != "pair_lead" or not x["pair"]:
				rep.err(f"scene {xid}: nest_of anchors need a pair scene")
			ax, ay = 0.5, 0.6
		else:
			ax, ay = an["x"], an["y"]
		for r in x["roles"]:
			px = ax + r["slot_dp"][0] * PX_PER_DP / FRAME_W
			py = ay + r["slot_dp"][1] * PX_PER_DP / FRAME_H
			if not (0.03 <= px <= 0.97) or not (zones["look"]["y0"] <= py <= dock_y0 - gap_n):
				rep.err(f"scene {xid}: role {r['role']} sits outside the play area")
			for p in r.get("prefer", []):
				if p not in sp_by:
					rep.err(f"scene {xid}: unknown preferred species {p}")
		if x["pair"] and len(x["roles"]) != 2:
			rep.err(f"scene {xid}: pair scenes cast exactly 2")
		c = x["conditions"]
		for k2 in c:
			if k2 not in known_cond:
				rep.err(f"scene {xid}: unknown condition {k2}")
		if c.get("met_min", 0) < len(x["roles"]):
			rep.err(f"scene {xid}: met_min must cover every role")
		for r in c.get("items", []):
			if r["item"] not in items or r["min"] > items[r["item"]]["max_copies"]:
				rep.err(f"scene {xid}: impossible item condition {r}")
		for a in c.get("away", []):
			for p in a["phases"]:
				if p not in phase_ids:
					rep.err(f"scene {xid}: unknown phase {p}")
			for w in a["weather"]:
				if w not in weather_ids:
					rep.err(f"scene {xid}: unknown weather {w}")
			if a["min_s"] <= 0 or a["min_s"] > sc["min_absence_s"]:
				rep.err(f"scene {xid}: away.min_s must fit inside the minimum absence")
		if c.get("pair_hearts_min", 0) > n_hearts:
			rep.err(f"scene {xid}: pair_hearts_min above {n_hearts}")
	return keys


def check_retention_strings(d: dict, rows: dict, rep: Report) -> None:
	"""Placeholder contracts that need both the data and the CSV."""
	sc = d["scenes"]
	for x in sc["scenes"]:
		en = rows.get(x["caption_key"], ("", ""))[0]
		ph = set(PLACEHOLDER.findall(en))
		if not ph <= {"name", "friend"} or "name" not in ph:
			rep.err(f"{x['caption_key']}: captions take {{name}} (and {{friend}} for a second role)")
		if "friend" in ph and len(x["roles"]) < 2:
			rep.err(f"{x['caption_key']}: {{friend}} needs a second role")
		if PLACEHOLDER.findall(rows.get(x["teaser_key"], ("", ""))[0]):
			rep.err(f"{x['teaser_key']}: recap teasers name nobody (the scene is the surprise)")
	for s in d["species"]["species"]:
		for f in ("postcard_heart2", "postcard_heart4", "postcard_heart5"):
			en = rows.get(s[f], ("", ""))[0]
			allowed = {"friend"} if f == "postcard_heart4" else set()
			if not set(PLACEHOLDER.findall(en)) <= allowed:
				rep.err(f"{s[f]}: unexpected placeholders (only {sorted(allowed)} allowed)")
	for v in d["mysteries"]["variants"]:
		if set(PLACEHOLDER.findall(rows.get(v["desc_key"], ("", ""))[0])) != {"name"}:
			rep.err(f"{v['desc_key']}: a cousin description names its base friend with {{name}}")


def check_layout(spots: dict, rep: Report, tea: dict | None = None) -> None:
	zones = {z["id"]: z for z in spots["zones"]}
	tend, dock = zones["tend"], zones["dock"]
	targets = []
	for b in spots["beds"]:
		targets.append((b["id"], b["x"], b["y"], b["hit_w_dp"], b["hit_h_dp"], True))
	for p in spots["props"]:
		if p["hit_dp"] > 0:
			targets.append((p["id"], p["x"], p["y"], p["hit_dp"], p["hit_dp"], False))
	if tea:  # Active F2: the tea nook is a static prop target on the stump (optional, look zone)
		n = tea["nook"]
		targets.append((n["prop_id"], n["x"], n["y"], n["hit_dp"], n["hit_dp"], False))
	st = spots["stream"]
	if st["tap_band_y1"] > dock["y0"] - GAP_DP * PX_PER_DP / FRAME_H:
		rep.err("stream tap band reaches the dock")
	for name, x, y, w, h, required in targets:
		in_look = y < tend["y0"]
		floor = LOOK_HIT_MIN_DP if in_look else PLAY_HIT_MIN_DP
		if min(w, h) < floor:
			rep.err(f"target {name}: hit {w}x{h} dp below {floor} dp")
		bottom = y + h * PX_PER_DP / FRAME_H / 2.0
		if bottom > dock["y0"] - GAP_DP * PX_PER_DP / FRAME_H:
			rep.err(f"target {name}: hit area reaches the dock")
		# The frame is always fully visible (stretch aspect "expand"), so a hit area that crosses a
		# side edge is clipped below its floor on every phone.
		half_w = w * PX_PER_DP / FRAME_W / 2.0
		if x - half_w < 0.0 or x + half_w > 1.0:
			rep.err(f"target {name}: hit area crosses a side edge of the frame")
		if required and in_look:
			rep.err(f"target {name}: required target in the look zone")
	for i in range(len(targets)):
		for j in range(i + 1, len(targets)):
			a, b = targets[i], targets[j]
			gx = abs(a[1] - b[1]) * FRAME_W - (a[3] + b[3]) * PX_PER_DP / 2.0
			gy = abs(a[2] - b[2]) * FRAME_H - (a[4] + b[4]) * PX_PER_DP / 2.0
			if max(gx, gy) < GAP_DP * PX_PER_DP:
				rep.err(f"targets {a[0]} and {b[0]} closer than {GAP_DP} dp")


# ---------------------------------------------------------------- Active Play v1 (GDD 14)
WISH_KINDS = {"pet": None, "play_taps": "int", "chime_tap": None, "bed_invite": "flower", "decor_near": "decor",
	"decor_tap": "decor", "boat": None, "stream_tap": None, "tea": "recipe", "tea_kind": "kind", "tea_petal": "flower",
	"tea_loved": None}
TEA_KINDS = {"tea", "tea_kind", "tea_petal", "tea_loved"}


def _seg_dist_dp(px: float, py: float, poly: list) -> float:
	"""Distance in dp from a frame-normalized point to a frame-normalized polyline."""
	best = INF_DP
	sx, sy = FRAME_W / PX_PER_DP, FRAME_H / PX_PER_DP
	for (ax, ay), (bx, by) in zip(poly, poly[1:]):
		ax, ay, bx, by, qx, qy = ax * sx, ay * sy, bx * sx, by * sy, px * sx, py * sy
		dx, dy = bx - ax, by - ay
		t = 0.0 if dx == dy == 0 else max(0.0, min(1.0, ((qx - ax) * dx + (qy - ay) * dy) / (dx * dx + dy * dy)))
		best = min(best, ((qx - ax - t * dx) ** 2 + (qy - ay - t * dy) ** 2) ** 0.5)
	return best


INF_DP = float("inf")


def check_active(d: dict, rep: Report) -> set:
	keys: set[str] = set()
	wi, te, dp = d["wishes"], d["tea"], d["decor_placement"]
	eco, spots, world = d["economy"], d["spots"], d["world"]
	species = d["species"]["species"]
	sp_by = {s["id"]: s for s in species}
	flowers = {f["id"]: f for f in d["flora"]["flowers"]}
	decor = {x["id"]: x for x in d["decor"]["decor"]}
	phase_ids = {p["id"] for p in world["phases"]}
	weather_ids = {w["id"] for w in world["weather"]}
	spot_by = {s["id"]: s for s in spots["spots"]}
	for name, doc in (("wishes", wi), ("tea", te), ("decor_placement", dp)):
		if not doc.get("doc"):
			rep.err(f"{name}.json: missing doc string")
	# ---- tea.json
	recipes = {r["id"]: r for r in te["recipes"]}
	if len(recipes) != len(te["recipes"]):
		rep.err("tea.recipes: duplicate ids")
	seen_mix: dict = {}
	fallbacks: dict = {}
	for r in te["recipes"]:
		rid = r["id"]
		if not SNAKE.match(rid):
			rep.err(f"recipe {rid}: id is not snake_case")
		keys.update([r["name_key"], r["desc_key"], r["hint_key"]])
		if r.get("match") == "fallback":
			for dr in r["drops_any"]:
				if dr in fallbacks:
					rep.err(f"tea: two fallbacks for {dr} drops ({fallbacks[dr]}, {rid})")
				fallbacks[dr] = rid
				if (r["kind"] == "treat") != (dr == te["pot"]["treat_at_drops"]):
					rep.err(f"recipe {rid}: kind must be treat exactly when drops == treat_at_drops")
			continue
		n = sum(r["petals"].values())
		if not (te["pot"]["min_petals"] <= n <= te["pot"]["max_petals"]) or not (0 <= r["drops"] <= te["pot"]["max_drops"]):
			rep.err(f"recipe {rid}: {n} petals / {r['drops']} drops outside the pot limits")
		if (r["kind"] == "treat") != (r["drops"] == te["pot"]["treat_at_drops"]):
			rep.err(f"recipe {rid}: kind must be treat exactly when drops == treat_at_drops")
		for f in r["petals"]:
			if f not in flowers:
				rep.err(f"recipe {rid}: unknown flower {f}")
		mix = (tuple(sorted(r["petals"].items())), r["drops"])
		if mix in seen_mix:
			rep.err(f"recipes {seen_mix[mix]} and {rid} share the same mix")
		seen_mix[mix] = rid
	if set(fallbacks) != set(range(te["pot"]["max_drops"] + 1)):
		rep.err("tea: exactly one fallback recipe for every drop count")
	orders = [r["book_order"] for r in te["recipes"]]
	if sorted(orders) != list(range(1, len(orders) + 1)):
		rep.err("tea.recipes: book_order must be 1..n without gaps")
	loved_or_liked: set = set()
	if set(te["species_prefs"]) != set(sp_by):
		rep.err("tea.species_prefs must list every species once")
	for sid, pr in te["species_prefs"].items():
		for rid in pr["loves"] + pr["likes"]:
			if rid not in recipes or recipes[rid].get("match") == "fallback":
				rep.err(f"tea.species_prefs.{sid}: {rid} is not a named recipe")
		if set(pr["loves"]) & set(pr["likes"]) or len(pr["loves"]) != 2 or len(pr["likes"]) != 3:
			rep.err(f"tea.species_prefs.{sid}: 2 loves and 3 likes, no overlap")
		if pr["gift_petal"] not in flowers:
			rep.err(f"tea.species_prefs.{sid}: unknown gift_petal")
		loved_or_liked |= set(pr["loves"]) | set(pr["likes"])
	for rid, r in recipes.items():
		if r.get("match") != "fallback" and rid not in loved_or_liked:
			rep.err(f"recipe {rid}: loved or liked by nobody")
	pet_rows = {p["flower"]: p for p in te["petals"]}
	if set(pet_rows) != set(flowers):
		rep.err("tea.petals must have one row per flower")
	for f, p in pet_rows.items():
		if p["petal_regrow_s"] <= 0 or p["pantry_cap"] < te["harvest"]["petal_hold_per_stem"] or p["pantry_cap"] > 99:
			rep.err(f"tea.petals.{f}: regrow > 0 and hold <= pantry_cap <= 99 (E6)")
	h = te["harvest"]
	if h["harms_flower"] or h["affects_dew_or_attraction"]:
		rep.err("tea.harvest: harvesting never harms a flower or changes dew/attraction (ACTIVE_TEA T1)")
	of = te["offering"]
	if min(of["affection_content"], of["affection_liked"]) < 1 or of["affection_loved"] < of["affection_liked"]:
		rep.err("tea.offering: every reaction gives >= 1 affection (no dislikes) and loved >= liked")
	if of["greeter_affection"] != 0:
		rep.err("tea.offering.greeter_affection must be 0 (GDD 5.6: the greeter gives nothing)")
	if not (0 <= of["affection_rest_s"] <= 86400):
		rep.err("tea.offering.affection_rest_s outside [0, 86400]")
	keys.add(te["dew_drop"]["name_key"])
	if not (1 <= te["dew_drop"]["cost_dew"] <= 99):
		rep.err("tea.dew_drop.cost_dew outside 1..99")
	slots: dict = {}
	tw_ids = set()
	for x in te["teaware"]:
		keys.add(x["name_key"])
		if x["id"] in tw_ids or not SNAKE.match(x["id"]):
			rep.err(f"teaware {x['id']}: duplicate or not snake_case")
		tw_ids.add(x["id"])
		if x.get("default"):
			if x["cost"] != 0 or x["slot"] in slots:
				rep.err(f"teaware {x['id']}: one free default per slot")
			slots[x["slot"]] = x["id"]
		elif not (0 < x["cost"] <= eco["display_max"]):
			rep.err(f"teaware {x['id']}: cost outside 1..{eco['display_max']}")
	if set(slots) != {x["slot"] for x in te["teaware"]}:
		rep.err("teaware: every slot needs a free default")
	if te["teaware_snug"] != 0:
		rep.err("teaware_snug must be 0 (visitor maths untouched)")
	for p in te["event_postcards"]:
		keys.add(p["template"])
		if p["id"] in {x["id"] for x in eco["event_postcards"]}:
			rep.err(f"tea event postcard {p['id']} clashes with economy.event_postcards")
	nook = te["nook"]
	if nook["on_prop"] not in {p["id"] for p in spots["props"]}:
		rep.err("tea.nook.on_prop is not a spots.json prop")
	keys.update(["TEA_NOOK_NAME", "TEA_NOOK_A11Y"])
	hooks = set(te["wish_hooks"]["types"])
	if {t.split(":")[0] for t in hooks} != TEA_KINDS:
		rep.err("tea.wish_hooks.types must be exactly the F1 tea target kinds")
	# ---- wishes.json
	tu, rw = wi["tuning"], wi["reward"]
	if not (1 <= tu["max_visible"] <= tu["max_pending"]) or tu["max_per_friend"] != 1:
		rep.err("wishes.tuning: 1 <= max_visible <= max_pending, max_per_friend 1")
	if not (0 < tu["spawn_chance"] <= 1) or min(tu["spawn_check_s"], tu["global_gap_s"], tu["friend_gap_s"]) <= 0:
		rep.err("wishes.tuning: spawn timings must be positive and 0 < spawn_chance <= 1")
	if tu["near_dp"] != dp["attraction"]["near_dp_for_wishes"]:
		rep.err("wishes.tuning.near_dp must equal decor_placement.attraction.near_dp_for_wishes")
	if rw["affection_per_wish"] < 1 or not (0 <= rw["wish_affection_rest_s"] <= 3 * 86400):
		rep.err("wishes.reward: affection_per_wish >= 1, rest within 0..3 days")
	if set(wi["traits"]) != set(sp_by):
		rep.err("wishes.traits must list every species once")
	ids = [w["id"] for w in wi["wishes"]]
	if len(set(ids)) != len(ids):
		rep.err("wishes: duplicate ids (and the list is append-only: wish_stamps are a bitmask over its order)")
	if len(ids) > 62:
		rep.err("wishes: at most 62 wishes fit the wish_stamps int64 bitmask")
	prefer_n = {s: 0 for s in sp_by}
	match_n = {s: 0 for s in sp_by}
	if wi["tuning"]["first_wish"]["wish"] not in ids:
		rep.err("wishes.tuning.first_wish: unknown wish")
	water = spots["stream"]["polyline"]
	for w in wi["wishes"]:
		wid = w["id"]
		if not SNAKE.match(wid):
			rep.err(f"wish {wid}: id is not snake_case")
		keys.update([w["title_key"], w["hint_key"]])
		kind, _, arg = w["target"].partition(":")
		if kind not in WISH_KINDS:
			rep.err(f"wish {wid}: unknown target kind {kind}")
			continue
		want = WISH_KINDS[kind]
		req = w["requires"]
		for k2 in req:
			if k2 not in {"bloomed", "owned", "feature", "buddy_present", "not_already_near"}:
				rep.err(f"wish {wid}: unknown requires key {k2}")
		if want == "flower" and arg not in flowers:
			rep.err(f"wish {wid}: unknown flower {arg}")
		elif want == "decor" and arg not in decor:
			rep.err(f"wish {wid}: unknown decor {arg}")
		elif want == "recipe" and arg not in recipes:
			rep.err(f"wish {wid}: unknown recipe {arg}")
		elif want == "kind" and arg not in {"tea", "treat"}:
			rep.err(f"wish {wid}: tea_kind must be tea or treat")
		elif want == "int" and not arg.isdigit():
			rep.err(f"wish {wid}: {kind} needs a count")
		elif want is None and arg:
			rep.err(f"wish {wid}: {kind} takes no argument")
		for f, n in req.get("bloomed", {}).items():
			if f not in flowers or not (1 <= n <= flowers[f]["max_copies"]):
				rep.err(f"wish {wid}: impossible bloomed requirement {f}:{n}")
		for x, n in req.get("owned", {}).items():
			if x not in decor or not (1 <= n <= decor[x]["max_copies"]):
				rep.err(f"wish {wid}: impossible owned requirement {x}:{n}")
		# the "fulfillable now" rule (ACTIVE_WISHES 4.3): the means to grant must be required to appear
		if kind in ("bed_invite", "tea_petal") and req.get("bloomed", {}).get(arg, 0) < 1:
			rep.err(f"wish {wid}: needs bloomed {{{arg}: 1}} to be fulfillable when it appears")
		if kind in ("decor_near", "decor_tap") and req.get("owned", {}).get(arg, 0) < 1:
			rep.err(f"wish {wid}: needs owned {{{arg}: 1}}")
		if kind == "chime_tap" and req.get("owned", {}).get("wind_chime", 0) < 1:
			rep.err(f"wish {wid}: needs owned {{wind_chime: 1}}")
		if kind == "tea" and arg in recipes:
			for f in recipes[arg].get("petals", {}):
				if req.get("bloomed", {}).get(f, 0) < 1:
					rep.err(f"wish {wid}: tea:{arg} needs bloomed {{{f}: 1}} (tea.wish_hooks.feasible_only)")
		if kind in TEA_KINDS and req.get("feature") != "tea":
			rep.err(f"wish {wid}: tea targets need feature tea")
		if kind == "decor_near" and (req.get("feature") != dp["feature_flag"] or not req.get("not_already_near")):
			rep.err(f"wish {wid}: decor_near needs feature {dp['feature_flag']} and not_already_near")
		if req.get("feature") not in (None, "tea", dp["feature_flag"]):
			rep.err(f"wish {wid}: unknown feature {req.get('feature')}")
		if kind in TEA_KINDS and w["target"].split(":")[0] + (":<" + ("recipe_id" if kind == "tea" else "flower_id") + ">" if kind in ("tea", "tea_petal") else (":" + arg if arg else "")) not in hooks:
			rep.err(f"wish {wid}: target {w['target']} is not in tea.wish_hooks.types")
		for p in w["spawn_when"].get("phases", []) + list(w["boost"].get("phases", {})):
			if p not in phase_ids:
				rep.err(f"wish {wid}: unknown phase {p}")
		for x in w["spawn_when"].get("weather", []) + list(w["boost"].get("weather", {})):
			if x not in weather_ids:
				rep.err(f"wish {wid}: unknown weather {x}")
		for sid in w["prefer"] + w["species_only"]:
			if sid not in sp_by:
				rep.err(f"wish {wid}: unknown species {sid}")
			elif sid in w["prefer"]:
				prefer_n[sid] += 1
		for sid in sp_by:
			if set(w["tags"]) & set(wi["traits"].get(sid, [])):
				match_n[sid] += 1
		if not w["icon"] or not w["granted_pose"] or w["weight"] <= 0:
			rep.err(f"wish {wid}: icon, granted_pose and a positive weight are required")
		if kind == "decor_near" and arg == "stream_stones":
			for sid in w["species_only"] or list(sp_by):
				fav = spot_by.get(sp_by.get(sid, {}).get("favourite_spot"))
				if fav and _seg_dist_dp(fav["x"], fav["y"], water) > tu["near_dp"]:
					rep.err(f"wish {wid}: {sid}'s favourite spot is more than {tu['near_dp']} dp from the water line")
	for sid in sp_by:
		if prefer_n[sid] < 2 or match_n[sid] < 6:
			rep.err(f"wishes: {sid} needs >= 2 preferred and >= 6 trait-matching wishes ({prefer_n[sid]} / {match_n[sid]})")
	# ---- decor_placement.json
	sets = dp["sets"]
	if set(sets) != set(decor):
		rep.err("decor_placement.sets must list every decor id once")
	for sid, st in sets.items():
		if st["movable"]:
			if len(st.get("rot_render", [])) != st["rot_steps"] or st["rot_steps"] < 1:
				rep.err(f"decor_placement.sets.{sid}: rot_render must hold rot_steps entries")
			if st["footprint_r_dp"] <= 0 or st["same_set_min_dp"] <= 0:
				rep.err(f"decor_placement.sets.{sid}: footprint and spacing must be positive")
	area = dp["area"]
	gt = area["ground_top"]
	if any(b[0] <= a[0] for a, b in zip(gt, gt[1:])) or gt[0][0] > area["x_min"] or gt[-1][0] < area["x_max"]:
		rep.err("decor_placement.area.ground_top must be x-sorted and span x_min..x_max")
	if not (area["x_min"] < 0 < 1 < area["x_max"]) or area["ground_bottom_y"] > {z["id"]: z for z in spots["zones"]}["tend"]["y1"]:
		rep.err("decor_placement.area: wings outside the frame, bottom at or above the tend zone's bottom")
	hit = dp["hit"]
	if min(hit["edit_piece_hit_dp"], hit["still_piece_hit_dp"]) < PLAY_HIT_MIN_DP or hit["edit_piece_hit_dp_look_zone"] < LOOK_HIT_MIN_DP:
		rep.err("decor_placement.hit: edit and still-piece hits below the I2 floors")
	if hit["edit_hit_min_dp_after_clip"] < 48 or dp["storage"]["tile_dp"] < 48 or dp["storage"]["tile_gap_dp"] < GAP_DP:
		rep.err("decor_placement: clipped hits and tray tiles >= 48 dp, gaps >= 8 dp")
	if hit["prio_edit_piece"] <= 8 or hit["prio_still_piece_play"] != 1:
		rep.err("decor_placement.hit: edit pieces outrank every play target, still pieces sit at the stream's priority")
	if dp["attraction"]["count"] != "owned":
		rep.err("decor_placement.attraction.count must stay 'owned' (economy_sim parity, GDD 14)")
	keys.add(dp["auto_place"]["first_tip"])
	for spot_id, ds in dp["derived_spots"].items():
		if spot_id == "rule" or not isinstance(ds, dict):
			continue
		sp = spot_by.get(spot_id)
		if sp is None or sp["requires_item"] != ds["set"] or sp["requires_min"] < ds["min"]:
			rep.err(f"decor_placement.derived_spots.{spot_id}: must match a gated spots.json spot of {ds['set']}")
	# legacy anchors: hard exclusions (hard props, the tea nook) must leave valid ground within the nudge radius
	cl = dp["clearances"]
	hard = [(p["x"], p["y"] + p["cy_dp"] * PX_PER_DP / FRAME_H, p["rx_dp"], p["ry_dp"], p.get("gap_dp", cl["gap_dp"]))
		for p in cl["props"] if p["hard"]]
	hard.append((nook["x"], nook["y"], nook["f3_exclusion_radius_dp"], nook["f3_exclusion_radius_dp"], 0.0))

	def blocked(x: float, y: float, r: float) -> bool:
		for cx, cy, rx, ry, gap in hard:
			dx = (x - cx) * FRAME_W / PX_PER_DP
			dy = (y - cy) * FRAME_H / PX_PER_DP
			if (dx / (rx + r + gap)) ** 2 + (dy / (ry + r + gap)) ** 2 < 1.0:
				return True
		return False
	nud = dp["snap"]["invalid_drop"]
	for a in spots["decor_anchors"]:
		st = sets.get(a["decor_id"], {})
		if not st.get("movable"):
			continue
		for i, (x, y) in enumerate(a["positions"]):
			if not blocked(x, y, st["footprint_r_dp"]):
				continue
			ok = False
			rad = nud["nudge_step_dp"]
			while rad <= nud["nudge_search_dp"] and not ok:
				for j in range(32):
					ang = 2 * math.pi * j / 32
					nx = x + rad * PX_PER_DP / FRAME_W * math.cos(ang)
					ny = y + rad * PX_PER_DP / FRAME_H * math.sin(ang)
					if not blocked(nx, ny, st["footprint_r_dp"]) and ny <= area["ground_bottom_y"]:
						ok = True
						break
				rad += nud["nudge_step_dp"]
			if not ok:
				rep.err(f"{a['decor_id']} anchors[{i}]: inside a hard exclusion and not nudgeable within {nud['nudge_search_dp']} dp")
	# ---- sound-cue ids: one meaning per id across the three features (GDD 14.8)
	cues: dict = {}
	pres = wi["presentation"]
	for cid, what in ((pres["cue_appear"], "wish_appear"), (pres["cue_granted"], "wish_granted")):
		cues.setdefault(cid, set()).add(what)
	for cid, what in te["audio_cues"].items():
		if re.match(r"^S\d+$", cid):
			cues.setdefault(cid, set()).add(what)
	for what, cid in dp["audio"].items():
		if what != "note" and re.match(r"^S\d+$", str(cid)) and int(cid[1:]) >= 26:
			cues.setdefault(cid, set()).add("decor_" + ("lift" if what == "take_out" else what))
	for cid, whats in cues.items():
		if len(whats) > 1:
			rep.err(f"sound cue {cid} claimed for {sorted(whats)}")
	return keys


def check_active_strings(d: dict, rows: dict, rep: Report) -> None:
	"""Placeholder contracts of the Active Play strings."""
	allowed = {"name", "spot", "friend"}
	for w in d["wishes"]["wishes"]:
		for k in (w["title_key"], w["hint_key"]):
			ph = set(PLACEHOLDER.findall(rows.get(k, ("", ""))[0]))
			if not ph <= allowed:
				rep.err(f"{k}: wish copy may use only {sorted(allowed)}")
			if "friend" in ph and not w["requires"].get("buddy_present"):
				rep.err(f"{k}: {{friend}} needs requires.buddy_present")
		if w["target"].startswith("decor_near") and "{spot}" not in rows.get(w["hint_key"], ("", ""))[0]:
			rep.err(f"{w['hint_key']}: a decor_near hint names the friend's {{spot}}")


# ---------------------------------------------------------------- strings
# ---------------------------------------------------------------- audio cue coverage
# Every cue id a data file names has to exist in audio/manifest.json, or the feature that fires it
# is simply silent and nothing says so. Retention v1 (GDD S13.7) and Active Play v1 (S14.8) were
# designed with S22-S38 and shipped without them: the sim, the save, the strings and the tests all
# landed, the sounds never did, and no gate noticed for two rounds.
#
# UNVOICED is that debt, written down. Anything NOT on this list that goes missing fails the
# build, so the hole cannot grow; the Sound Designer deletes ids from here as the cues land, and
# an id that is both authored and still listed fails too, so the list cannot go stale.
UNVOICED = {
	# Retention v1 (GDD S13.7)
	"S22": "rustle sign shakes", "S23": "sign tapped (clue found)", "S24": "heart-up",
	"S25": "scene fades in / teaser",
	# Active Play S26-S38 were synthesised in e5462e7 (tools/audio/active_sfx.py) and left the list.
}
CUE_ID = re.compile(r"^S\d{2}$")


def _cue_ids(node, out: set) -> None:
	"""Every "S07"-shaped string anywhere in a data document."""
	if isinstance(node, dict):
		for k, v in node.items():
			if isinstance(k, str) and CUE_ID.match(k):   # tea.json lists its cues as keys
				out.add(k)
			_cue_ids(v, out)
	elif isinstance(node, list):
		for v in node:
			_cue_ids(v, out)
	elif isinstance(node, str) and CUE_ID.match(node):
		out.add(node)


def check_audio_cues(d: dict, rep: Report) -> None:
	manifest = json.loads((ROOT / "audio" / "manifest.json").read_text(encoding="utf-8"))
	have = set(manifest.get("cues", {}))
	want: set = set()
	for name, doc in d.items():
		ids: set = set()
		_cue_ids(doc, ids)
		for cue in ids:
			want.add(cue)
			if cue not in have and cue not in UNVOICED:
				rep.err(f"{name}.json references audio cue {cue}, which audio/manifest.json does not define")
	for cue, what in sorted(UNVOICED.items()):
		if cue in have:
			rep.err(f"audio cue {cue} ({what}) is authored now: drop it from UNVOICED in validate_content.py")
	missing = sorted(c for c in UNVOICED if c in want)
	if missing:
		print(f"  audio: {len(missing)} cue(s) still unvoiced (GDD S13.7, S14.8): {', '.join(missing)}")


def check_strings(needed: set, rep: Report) -> dict:
	p = ROOT / "i18n" / "strings.csv"
	raw = p.read_bytes()
	if raw.startswith(b"\xef\xbb\xbf"):
		rep.err("strings.csv must not start with a BOM")
	text = raw.decode("utf-8")
	rows = list(csv.reader(io.StringIO(text)))
	if rows[0] != ["keys", "en", "vi"]:
		rep.err(f"strings.csv header must be keys,en,vi (got {rows[0]})")
	seen: dict[str, tuple] = {}
	ban_en = [re.compile(r"\b" + b + r"\b", re.IGNORECASE) for b in BANNED_EN]
	ban_vi = [re.compile(r"(?<![\w])" + b + r"(?![\w])", re.IGNORECASE) for b in BANNED_VI]
	for n, row in enumerate(rows[1:], start=2):
		if len(row) != 3:
			rep.err(f"strings.csv line {n}: expected 3 columns")
			continue
		k, en, vi = row
		if not KEY.match(k):
			rep.err(f"strings.csv line {n}: bad key {k!r}")
		if k in seen:
			rep.err(f"strings.csv: duplicate key {k}")
		seen[k] = (en, vi)
		if not en.strip() or not vi.strip():
			rep.err(f"{k}: empty translation")
		if unicodedata.normalize("NFC", vi) != vi or unicodedata.normalize("NFC", en) != en:
			rep.err(f"{k}: not NFC")
		if sorted(PLACEHOLDER.findall(en)) != sorted(PLACEHOLDER.findall(vi)):
			rep.err(f"{k}: placeholders differ between en and vi")
		for rx in ban_en:
			if rx.search(en):
				rep.err(f"{k}: banned word '{rx.pattern}' in en: {en}")
		for rx in ban_vi:
			if rx.search(vi):
				rep.err(f"{k}: banned word '{rx.pattern}' in vi: {vi}")
	for k in sorted(needed):
		if k not in seen:
			rep.err(f"strings.csv: missing key {k}")
	return seen


def main() -> int:
	ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("--format", action="store_true", help="rewrite data/*.json in canonical layout first")
	args = ap.parse_args()
	if args.format:
		for name in DATA_FILES:
			format_file(ROOT / "data" / f"{name}.json")
	rep = Report()
	d = load(rep)
	if rep.errors:
		print("\n".join(rep.errors))
		return 1
	needed = check_data(d, rep)
	rows = check_strings(needed, rep)
	check_retention_strings(d, rows, rep)
	check_active_strings(d, rows, rep)
	check_audio_cues(d, rep)
	if rep.errors:
		print(f"{len(rep.errors)} problem(s):")
		print("\n".join("  " + e for e in rep.errors))
		return 1
	print(f"content OK: {len(d['species']['species'])} species, {len(d['flora']['flowers'])} flowers, "
		f"{len(d['decor']['decor'])} decor, {len(d['spots']['spots'])} spots, {len(d['spots']['beds'])} beds; "
		f"retention: {len(d['mysteries']['variants'])} cousins, {len(d['mysteries']['anchors'])} sign anchors, "
		f"{len(d['scenes']['scenes'])} scenes; active: {len(d['wishes']['wishes'])} wishes, "
		f"{len(d['tea']['recipes'])} recipes, {len(d['tea']['teaware'])} teaware, {len(d['decor_placement']['sets'])} decor sets; "
		f"{len(needed)} referenced string keys present")
	return 0


if __name__ == "__main__":
	sys.exit(main())
