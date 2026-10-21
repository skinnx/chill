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
DATA_FILES = ("species", "flora", "decor", "economy", "world", "spots")
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
	return keys


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
def check_strings(needed: set, rep: Report) -> None:
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
	check_strings(needed, rep)
	if rep.errors:
		print(f"{len(rep.errors)} problem(s):")
		print("\n".join("  " + e for e in rep.errors))
		return 1
	print(f"content OK: {len(d['species']['species'])} species, {len(d['flora']['flowers'])} flowers, "
		f"{len(d['decor']['decor'])} decor, {len(d['spots']['spots'])} spots, {len(d['spots']['beds'])} beds; "
		f"{len(needed)} referenced string keys present")
	return 0


if __name__ == "__main__":
	sys.exit(main())
