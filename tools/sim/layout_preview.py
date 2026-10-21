#!/usr/bin/env python3
"""Render the GDD hollow layout schematic (docs/gdd/hollow_layout.png) from data/spots.json.

The picture is a gameplay-contract preview, not art: zones, the drag-start band, beds with their
16 stem slots, spot circles (a 50 dp creature), prop hit boxes, decor anchors, the stream and the
entries, at half scale (540x960 for the 1080x1920 frame) plus a legend. Re-run it whenever
spots.json changes so the GDD's generated figure never drifts from the data (docs/GDD.md §2.2).

Usage:
  python3 -I tools/sim/layout_preview.py                 # writes docs/gdd/hollow_layout.png
  python3 -I tools/sim/layout_preview.py --out FILE.png
Needs Pillow (tools/ci/requirements.txt).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SCALE = 0.5  # preview px per design px
LEGEND_H = 80
SPOT_DIAMETER_DP = 50.0
FONT_CANDIDATES = ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "DejaVuSans.ttf")
FONT_PX = 11

ZONE_FILL = {
	"hud": (226, 227, 244), "look": (214, 235, 222), "tend": (190, 222, 196),
	"dock": (236, 235, 232), "gesture": (216, 216, 216),
}
SKY = (212, 238, 246)
INK = (42, 40, 56)
EDGE = (232, 120, 110)
BED = (126, 84, 50)
STEM = (238, 150, 190)
SPOT = (52, 62, 170)
SPOT_GATED = (150, 60, 160)
PROP = (200, 30, 40)
ENTRY = (30, 130, 30)
WATER = (122, 170, 226)
DECOR = {
	"firefly_lantern": (240, 180, 30), "stream_stones": (110, 110, 120), "leaf_pinwheel": (80, 150, 90),
	"toadstool_seat": (226, 104, 110), "pebble_cairn": (150, 140, 120), "wind_chime": (140, 120, 210),
}


def _font() -> ImageFont.ImageFont:
	for path in FONT_CANDIDATES:
		try:
			return ImageFont.truetype(path, FONT_PX)
		except OSError:
			continue
	return ImageFont.load_default()


def render(spots: dict, out: Path) -> None:
	frame = spots["frame"]
	w_px, h_px, dp = float(frame["width_px"]), float(frame["height_px"]), float(frame["px_per_dp"])
	W, H = round(w_px * SCALE), round(h_px * SCALE)
	img = Image.new("RGB", (W, H + LEGEND_H), (250, 249, 246))
	d = ImageDraw.Draw(img)
	font = _font()

	def pt(x: float, y: float) -> tuple[float, float]:
		return x * W, y * H

	def box(cx: float, cy: float, w_dp: float, h_dp: float) -> list[float]:
		x, y = pt(cx, cy)
		hw, hh = w_dp * dp * SCALE / 2, h_dp * dp * SCALE / 2
		return [x - hw, y - hh, x + hw, y + hh]

	d.rectangle([0, 0, W, H], fill=SKY)
	for z in spots["zones"]:
		d.rectangle([0, z["y0"] * H, W, z["y1"] * H], fill=ZONE_FILL.get(z["id"], (230, 230, 230)))
		d.text((4, z["y0"] * H + 4), z["id"], fill=(90, 90, 100), font=font)
	for x in (spots["safe_x"]["x0"], spots["safe_x"]["x1"]):
		d.line([x * W, 0, x * W, H], fill=EDGE, width=1)
	st = spots["stream"]
	d.line([pt(x, y) for x, y in st["polyline"]], fill=WATER, width=max(1, round(st["water_width"] * H)))
	for a in spots["decor_anchors"]:
		col = DECOR.get(a["decor_id"], INK)
		for x, y in a["positions"]:
			px, py = pt(x, y)
			d.rectangle([px - 3, py - 3, px + 3, py + 3], fill=col)
	for b in spots["beds"]:
		r = box(b["x"], b["y"], b["hit_w_dp"], b["hit_h_dp"])
		d.rectangle(r, outline=BED, width=2)
		for dx, dy in b["stems"]:
			px, py = pt(b["x"] + dx, b["y"] + dy)
			d.ellipse([px - 3.5, py - 3.5, px + 3.5, py + 3.5], fill=STEM)
		d.text(((r[0] + r[2]) / 2, r[1] + 2), b["id"], fill=INK, font=font, anchor="ma")
	rad = SPOT_DIAMETER_DP * dp * SCALE / 2
	for s in spots["spots"]:
		px, py = pt(s["x"], s["y"])
		col = SPOT_GATED if s["requires_item"] else SPOT
		d.ellipse([px - rad, py - rad, px + rad, py + rad], outline=col, width=1)
		d.text((px, py + rad + 2), s["id"], fill=INK, font=font, anchor="ma")
	for p in spots["props"]:
		px, py = pt(p["x"], p["y"])
		if p["hit_dp"] > 0:
			d.rectangle(box(p["x"], p["y"], p["hit_dp"], p["hit_dp"]), outline=PROP, width=2)
		d.text((px, py), p["id"], fill=PROP, font=font, anchor="mm")
	for e in spots["entries"]:
		name = e["id"].removeprefix("entry_")
		if e["x"] > 1.0:  # off the right edge: label it at the edge, pointing in
			d.text((W - 2, e["y"] * H), name + " <", fill=ENTRY, font=font, anchor="rm")
		else:
			px, py = pt(max(e["x"], 0.0), e["y"])
			d.text((px + 2, py), "> " + name, fill=ENTRY, font=font, anchor="lm")

	# legend
	y0 = H + 8
	items = [("rect", BED, "bed hit box + 16 stem slots"), ("rect", SPOT, "spot (50 dp creature)"),
		("rect", SPOT_GATED, "decor-gated spot"), ("rect", PROP, "prop hit box")]
	for i, (_, col, label) in enumerate(items):
		x = 6 + (i % 2) * 270
		y = y0 + (i // 2) * 18
		d.rectangle([x, y, x + 10, y + 10], outline=col, width=2)
		d.text((x + 16, y - 1), label, fill=INK, font=font)
	x, y = 6, y0 + 36
	for decor_id, col in DECOR.items():
		step = 14 + d.textlength(decor_id, font=font) + 10
		if x + step > W:
			x, y = 6, y + 14
		d.rectangle([x, y + 2, x + 8, y + 10], fill=col)
		d.text((x + 12, y), decor_id, fill=INK, font=font)
		x += step
	out.parent.mkdir(parents=True, exist_ok=True)
	img.save(out, optimize=True)


def main() -> int:
	ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
	ap.add_argument("--out", type=Path, default=ROOT / "docs" / "gdd" / "hollow_layout.png")
	args = ap.parse_args()
	spots = json.loads((ROOT / "data" / "spots.json").read_text(encoding="utf-8"))
	render(spots, args.out)
	print(f"layout_preview: wrote {args.out}")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
