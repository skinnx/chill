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

Usage:
  python3 tools/sim/validate_content.py           # validate, exit 1 on any problem
  python3 tools/sim/validate_content.py --format  # also rewrite data/*.json in canonical layout
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA_FILES = ("species", "flora", "decor", "economy", "world", "spots", "friendship", "mysteries", "scenes")
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
	check_layout(spots, rep)
	keys |= check_retention(d, rep)
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


def check_layout(spots: dict, rep: Report) -> None:
	zones = {z["id"]: z for z in spots["zones"]}
	tend, dock = zones["tend"], zones["dock"]
	targets = []
	for b in spots["beds"]:
		targets.append((b["id"], b["x"], b["y"], b["hit_w_dp"], b["hit_h_dp"], True))
	for p in spots["props"]:
		if p["hit_dp"] > 0:
			targets.append((p["id"], p["x"], p["y"], p["hit_dp"], p["hit_dp"], False))
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


# ---------------------------------------------------------------- strings
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
	if rep.errors:
		print(f"{len(rep.errors)} problem(s):")
		print("\n".join("  " + e for e in rep.errors))
		return 1
	print(f"content OK: {len(d['species']['species'])} species, {len(d['flora']['flowers'])} flowers, "
		f"{len(d['decor']['decor'])} decor, {len(d['spots']['spots'])} spots, {len(d['spots']['beds'])} beds; "
		f"retention: {len(d['mysteries']['variants'])} cousins, {len(d['mysteries']['anchors'])} sign anchors, "
		f"{len(d['scenes']['scenes'])} scenes; "
		f"{len(needed)} referenced string keys present")
	return 0


if __name__ == "__main__":
	sys.exit(main())
