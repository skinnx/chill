#!/usr/bin/env python3
"""Generates art/decor/decor_atlas.svg (tone masks) + art/decor/decor_atlas.json (regions, layout).

Art Bible §6.6 (the six décor sets), §6.7 (gifts and dew), §6.8 (leaf boat), §3.8 (materials),
§4.9 (prop_tone contract). Run from the repo root:

    python3 -I -B art/decor/src/decor_svg.py && godot --headless --path . --import

Every part is authored at design px (depth scale 1) and written at SCALE x. The JSON lists, per
part, its atlas region (px), size at depth 1 (design px), pivot (normalised: the ground contact or
hanging point the piece is placed by), palettes.json material, optional detail emission, and a
rim flag. scripts/garden/decor_layer.gd places the pieces at the spots.json décor anchors.

Line rule (QA round 1, one hand): no dark ink outlines; volume comes from the R -> G gradients
and soft occlusion, like the felted mosslings. Every tip is rounded, filters are blur only.
"""
from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "art/flora/src"))
from tonekit import DETAIL, LINE, LIT, SHADE, Part, Svg, blob, blob_pts, rot_pts, smooth_path, write_atlas  # noqa: E402

OUT_SVG = ROOT / "art/decor/decor_atlas.svg"
OUT_JSON = ROOT / "art/decor/decor_atlas.json"
SCALE = 2
ATLAS_W = 1024
PAD = 6


# --------------------------------------------------------------------------------------------- #
# Leaf pinwheel (pinwheel_a / pinwheel_b blades, wood_cut stick)
# --------------------------------------------------------------------------------------------- #

def _blade(p: Part, svg: Svg, cx: float, cy: float, deg: float, r: float) -> None:
    """One broad leaf blade from the hub outward along deg: a rounded leaf whose leading half is
    cupped toward the wind (shade) and whose tip curls back (lit), so the head reads as a
    pinwheel even when still."""
    w = r * 0.42
    pts = [(0, 1.0), (r * 0.18, w * 0.62), (r * 0.5, w * 1.0), (r * 0.82, w * 0.86), (r * 1.0, w * 0.3),
           (r * 0.96, -w * 0.18), (r * 0.72, -w * 0.42), (r * 0.42, -w * 0.4), (r * 0.16, -w * 0.22), (0, -1.0)]
    pts = rot_pts([(cx + x, cy + y) for x, y in pts], cx, cy, deg)
    d = smooth_path(pts)
    clip = svg.clip(d)
    a = math.radians(deg)
    ux, uy = math.cos(a), math.sin(a)
    nx, ny = -uy, ux
    ex, ey = cx + ux * r, cy + uy * r
    p.path(d, svg.lin(cx, cy, ex, ey, [(0, SHADE), (0.3, LIT), (1, LIT)]))
    # cupped leading half (toward +normal) in soft shade
    p.path(d, svg.lin(cx - nx * w * 0.2, cy - ny * w * 0.2, cx + nx * w, cy + ny * w,
                      [(0, SHADE, 0.0), (0.45, SHADE, 0.0), (1, SHADE, 0.55)]))
    # midrib and two side veins (detail)
    p.line([(cx + ux * 3, cy + uy * 3), (cx + ux * r * 0.55 + nx * w * 0.12, cy + uy * r * 0.55 + ny * w * 0.12),
            (ex - ux * 3, ey - uy * 3)], DETAIL, 1.2, 0.8, None, clip)
    for t in (0.42, 0.66):
        bx, by = cx + ux * r * t, cy + uy * r * t
        p.line([(bx, by), (bx + ux * r * 0.14 + nx * w * 0.55, by + uy * r * 0.14 + ny * w * 0.55)], DETAIL, 0.8,
               0.5, None, clip)
    # a lit sheen near the curled tip
    p.ellipse(cx + ux * r * 0.78 - nx * w * 0.1, cy + uy * r * 0.78 - ny * w * 0.1, r * 0.14, w * 0.18, LIT, 0.8,
              svg.blur(0.8), clip, deg)


def pinwheel_a(svg: Svg) -> Part:
    p = Part(svg, 64, 64, (0.5, 0.5))
    for deg in (-45, 135):
        _blade(p, svg, 32, 32, deg, 29)
    return p


def pinwheel_b(svg: Svg) -> Part:
    p = Part(svg, 64, 64, (0.5, 0.5))
    for deg in (45, 225):
        _blade(p, svg, 32, 32, deg, 29)
    # hub pin (detail cream) with a soft shade ring
    p.ellipse(32, 32, 5.2, 5.2, SHADE, 0.8)
    p.ellipse(32, 32, 4.0, 4.0, DETAIL)
    p.ellipse(31, 31, 1.5, 1.2, LIT, 0.7)
    return p


def pinwheel_stick(svg: Svg) -> Part:
    p = Part(svg, 12, 92, (0.5, 0.99))
    d = smooth_path([(4.4, 4), (6, 1.4), (7.6, 4), (7.4, 60), (7.9, 88), (6, 91.2), (4.1, 88), (4.6, 60)])
    p.path(d, svg.lin(4, 0, 8, 0, [(0, LIT), (0.45, LIT), (1, SHADE)]))
    p.line([(5.4, 8), (5.2, 50), (5.6, 86)], DETAIL, 0.9, 0.5)
    p.ellipse(6, 88, 4.4, 2.2, SHADE, 0.7, svg.blur(1.0))
    return p


# --------------------------------------------------------------------------------------------- #
# Pebble cairn, stream stones, gifts (stone materials)
# --------------------------------------------------------------------------------------------- #

def pebble_flat(svg: Svg, seed: int, w: float, h: float, moss: bool) -> Part:
    """A flat, rounded stacking pebble: lit top plane, shade belly, optional moss cap (detail)."""
    p = Part(svg, w, h, (0.5, 0.86))
    rng = random.Random(seed)
    pts = blob_pts(w / 2, h * 0.52, w * 0.47, h * 0.44, 14, 0.04, rng)
    d = smooth_path(pts)
    clip = svg.clip(d)
    p.path(d, svg.lin(0, 0, 0, h, [(0, LIT), (0.5, LIT), (1, SHADE)]))
    p.ellipse(w * 0.46, h * 0.34, w * 0.34, h * 0.16, LIT, 0.8, svg.blur(h * 0.08), clip)
    p.ellipse(w * 0.5, h * 0.92, w * 0.5, h * 0.2, SHADE, 0.7, svg.blur(h * 0.08), clip)
    p.speckles(rng, (w * 0.15, h * 0.2, w * 0.85, h * 0.8), int(w / 4), (0.3, 0.7), SHADE, (0.2, 0.45), clip)
    if moss:
        cap = smooth_path([(w * 0.18, h * 0.32), (w * 0.3, h * 0.12), (w * 0.52, h * 0.06), (w * 0.72, h * 0.14),
                           (w * 0.8, h * 0.3), (w * 0.62, h * 0.36), (w * 0.4, h * 0.38)])
        p.path(cap, DETAIL, 0.95, clip=clip)
        p.speckles(rng, (w * 0.25, h * 0.1, w * 0.75, h * 0.32), 6, (0.4, 0.8), LIT, (0.3, 0.5), clip)
    return p


def stream_stone(svg: Svg) -> Part:
    """Stepping stone sitting IN the brook (stone_cool): a rounded dome above the waterline with a
    moss cap (detail), a dark wet band at the waterline, the submerged foot fading into the water,
    and a pale riffle ring hugging it. Pivot at the waterline."""
    p = Part(svg, 60, 30, (0.5, 0.66))
    rng = random.Random(211)
    wl = 20.0
    dome = smooth_path([(4, wl), (6, 12.5), (14, 6.0), (26, 3.0), (38, 3.4), (49, 7.0), (55, 13.0), (56, wl),
                        (44, wl + 2.2), (30, wl + 2.6), (16, wl + 2.2)])
    clip = svg.clip(dome)
    # submerged foot: a darker blob below the waterline fading out
    p.path(smooth_path([(5, wl - 1), (30, wl - 2), (55, wl - 1), (50, wl + 7), (30, wl + 8.5), (10, wl + 7)]),
           svg.lin(0, wl - 2, 0, wl + 9, [(0, SHADE, 0.85), (1, SHADE, 0.0)]))
    p.path(dome, svg.lin(0, 3, 0, wl + 2, [(0, LIT), (0.5, LIT), (0.85, SHADE), (1, SHADE)]))
    p.path(smooth_path([(4, wl - 3.6), (18, wl - 1.4), (30, wl - 0.8), (42, wl - 1.4), (56, wl - 3.6), (56, wl + 3),
                        (4, wl + 3)]), LINE, 0.35, svg.blur(1.0), clip=clip)
    cap = smooth_path([(12, 9.0), (20, 4.8), (31, 3.6), (42, 5.8), (47, 9.6), (40, 11.8), (28, 12.6), (17, 12.0)])
    p.path(cap, DETAIL, 0.95, clip=clip)
    p.speckles(rng, (14, 5, 46, 11), 8, (0.4, 0.8), LIT, (0.25, 0.45), clip)
    p.speckles(rng, (8, 9, 52, 18), 12, (0.4, 0.8), SHADE, (0.2, 0.4), clip)
    p.ellipse(22, 6.4, 5, 1.4, LIT, 0.7, svg.blur(0.8), clip)
    # riffle ring at the waterline (pale water catching the light)
    p.path(smooth_path([(1, wl + 0.4), (14, wl + 3.6), (30, wl + 4.4), (46, wl + 3.6), (59, wl + 0.4)], closed=False),
           "none", 0.55, svg.blur(0.7), LIT, 1.8)
    return p


# --------------------------------------------------------------------------------------------- #
# Toadstool seat (toadstool_cap + toadstool_stem)
# --------------------------------------------------------------------------------------------- #

def toadstool_cap(svg: Svg) -> Part:
    """Domed cap 48 x 28: cream spots (detail), gills tucked under the rim (shade)."""
    p = Part(svg, 50, 30, (0.5, 0.9))
    rng = random.Random(221)
    dome = smooth_path([(2.4, 22), (4.4, 13), (12, 5), (25, 1.6), (38, 5), (45.6, 13), (47.6, 22), (40, 25.2),
                        (25, 26.4), (10, 25.2)])
    clip = svg.clip(dome)
    p.path(dome, svg.rad(20, 6, 30, [(0, LIT), (0.6, LIT), (1, SHADE)]))
    p.path(smooth_path([(2.4, 21), (12, 24.4), (25, 25.6), (38, 24.4), (47.6, 21), (40, 28), (10, 28)]), SHADE, 0.9,
           svg.blur(0.9), clip=clip)
    for cx, cy, r in ((15, 10, 3.6), (27, 6.4, 3.0), (36, 12, 3.4), (22, 15.6, 2.4), (9, 17, 2.0), (41, 18, 1.8),
                      (31, 18.4, 2.0)):
        p.path(blob(cx, cy, r, r * 0.8, 9, 0.12, rng), DETAIL, 0.95, clip=clip)
    p.ellipse(18, 7, 8, 2.6, LIT, 0.55, svg.blur(1.2), clip)
    return p


def toadstool_stem(svg: Svg) -> Part:
    """Stout stem 20 x 24 with its gill ring at the top (detail)."""
    p = Part(svg, 22, 27, (0.5, 0.95))
    d = smooth_path([(5, 4), (11, 2.4), (17, 4), (17.4, 15), (19.4, 23.4), (11, 26), (2.6, 23.4), (4.6, 15)])
    clip = svg.clip(d)
    p.path(d, svg.lin(2, 0, 20, 0, [(0, LIT), (0.5, LIT), (1, SHADE)]))
    p.path(smooth_path([(3, 2), (11, 0.4), (19, 2), (17, 7.4), (11, 8.4), (5, 7.4)]), DETAIL, 0.9, clip=clip)
    p.ellipse(11, 25, 9, 3.2, SHADE, 0.7, svg.blur(1.2), clip)
    return p


# --------------------------------------------------------------------------------------------- #
# Firefly lantern (wood_bark crook + lid, lantern_light core, lantern_jar glass)
# --------------------------------------------------------------------------------------------- #

LANTERN_HOOK = (30.0, 28.0)   # where the jar's wire hangs (design px in the crook part)


def lantern_crook(svg: Svg) -> Part:
    """Shepherd's-crook stick, 150 px, its hook holding the jar's wire; a little leaf lid."""
    p = Part(svg, 40, 154, (0.3, 0.985))
    stick = [(12, 152), (12.6, 110), (11.4, 60), (12, 24), (16, 10), (25, 6), (32, 10), (33, 18)]
    p.line(stick, SHADE, 6.0)
    p.line([(x - 0.9, y) for x, y in stick[:4]] + stick[4:], LIT, 2.6, 0.9)
    p.line([(10.8, 140), (10.6, 90), (10.2, 40), (12.6, 18)], DETAIL, 0.9, 0.35)
    # a few felted bark knots and fibre flecks along the stick
    for y in (46, 92, 128):
        p.ellipse(12.4, y, 2.6, 1.4, SHADE, 0.8)
    rng = random.Random(251)
    for _ in range(18):
        y = rng.uniform(26, 146)
        p.ellipse(11.4 + rng.uniform(-0.8, 0.8), y, 0.7, 1.4, DETAIL, rng.uniform(0.35, 0.6))
    p.ellipse(12, 151, 7, 2.6, SHADE, 0.7, svg.blur(1.2))
    # wire from the hook to the jar's lid
    p.line([(33, 18), (31.2, 24), (30, 28)], LINE, 1.2, 0.8)
    return p


def lantern_jar(svg: Svg) -> Part:
    """Glass jar 36 x 44 (lantern_jar): translucent body, bright rims, a vertical gloss (detail),
    a wooden lid and a wire bail; pivot at the bail (hangs from the crook)."""
    p = Part(svg, 38, 52, (0.5, 0.04))
    body = smooth_path([(8, 12), (30, 12), (33, 18), (34, 36), (31, 47), (19, 50), (7, 47), (4, 36), (5, 18)])
    clip = svg.clip(body)
    p.path(body, LIT, 0.42)
    p.path(body, svg.lin(4, 0, 34, 0, [(0, SHADE, 0.5), (0.25, SHADE, 0.0), (0.75, SHADE, 0.0), (1, SHADE, 0.55)]))
    p.path(smooth_path([(5, 40), (19, 46), (33, 40), (31, 48), (19, 51), (7, 48)]), SHADE, 0.55, svg.blur(1.0),
           clip=clip)
    p.line([(10, 18), (9.4, 30), (10.4, 42)], DETAIL, 2.6, 0.9, svg.blur(0.5), clip)
    p.line([(27.5, 20), (28.6, 30)], DETAIL, 1.2, 0.6, svg.blur(0.4), clip)
    # rim + lid (lid painted as shade/line: a soft dark cap)
    p.path(smooth_path([(6, 13), (19, 10.6), (32, 13), (32, 16), (19, 17.4), (6, 16)]), LIT, 0.95)
    p.path(smooth_path([(9, 8), (19, 5.2), (29, 8), (30, 12), (19, 13.4), (8, 12)]), LINE, 0.85)
    p.ellipse(19, 7.6, 7, 1.6, SHADE, 0.6, svg.blur(0.5))
    # bail
    p.line([(9, 9), (12, 3), (19, 1.4), (26, 3), (29, 9)], LINE, 1.1, 0.75)
    return p


def lantern_core(svg: Svg) -> Part:
    """Glow inside the jar (lantern_light; detail = the hot amber centre, emissive at night)."""
    p = Part(svg, 30, 34, (0.5, 0.0))
    p.ellipse(15, 22, 12, 12, svg.rad(15, 22, 12.5, [(0, DETAIL), (0.45, LIT), (1, LIT, 0.0)]))
    for x, y in ((10, 18), (20, 25), (14, 28)):
        p.ellipse(x, y, 1.6, 1.6, DETAIL, 0.95)
    return p


# --------------------------------------------------------------------------------------------- #
# Wind chime (chime_ceramic tube on a string; copy 1 carries a paper strip in detail pink)
# --------------------------------------------------------------------------------------------- #

def chime_tube(svg: Svg, tube_len: float, string_len: float, paper: bool) -> Part:
    w = 14.0
    h = string_len + tube_len + (22 if paper else 4)
    p = Part(svg, w, h, (0.5, 0.0))
    cx = w / 2
    p.line([(cx, 0.6), (cx, string_len + 1)], LINE, 1.8, 0.95)
    y0 = string_len
    tube = smooth_path([(cx - 4.0, y0 + 1.4), (cx, y0), (cx + 4.0, y0 + 1.4), (cx + 4.4, y0 + tube_len * 0.5),
                        (cx + 4.4, y0 + tube_len - 2.4), (cx + 2.6, y0 + tube_len - 0.4), (cx, y0 + tube_len),
                        (cx - 2.6, y0 + tube_len - 0.4), (cx - 4.4, y0 + tube_len - 2.4), (cx - 4.4, y0 + tube_len * 0.5)])
    clip = svg.clip(tube)
    p.path(tube, svg.lin(cx - 5, 0, cx + 5, 0, [(0, SHADE), (0.3, LIT), (0.55, LIT), (1, SHADE)]))
    # glaze: lighter toward the top, a soft drip line, two pressed rings
    p.path(tube, svg.lin(0, y0, 0, y0 + tube_len, [(0, DETAIL, 0.0), (1, SHADE, 0.25)]))
    p.line([(cx - 1.6, y0 + 4), (cx - 1.8, y0 + tube_len - 5)], LIT, 1.4, 0.8, svg.blur(0.4), clip)
    for t in (0.14, 0.86):
        yy = y0 + tube_len * t
        p.path(smooth_path([(cx - 5, yy - 0.6), (cx, yy + 0.4), (cx + 5, yy - 0.6)], closed=False), "none", 0.55,
               None, SHADE, 1.1, clip)
    p.ellipse(cx, y0 + 1.4, 2.6, 0.9, LINE, 0.55, clip=clip)
    p.ellipse(cx, y0 + 1.6, 4.0, 1.2, SHADE, 0.45, clip=clip)
    if paper:
        yp = y0 + tube_len
        p.line([(cx, yp), (cx, yp + 4)], LINE, 0.8, 0.7)
        strip = smooth_path([(cx - 3.2, yp + 4), (cx + 3.2, yp + 4), (cx + 3.6, yp + 19), (cx, yp + 21),
                             (cx - 3.6, yp + 19)])
        p.path(strip, DETAIL)
        p.path(strip, svg.lin(0, yp + 4, 0, yp + 21, [(0, SHADE, 0.0), (1, SHADE, 0.3)]))
    return p


# --------------------------------------------------------------------------------------------- #
# Gifts and dew (Art Bible §6.7), basket front rim, leaf boat + candle (§6.8)
# --------------------------------------------------------------------------------------------- #

def acorn_cup(svg: Svg) -> Part:
    """Acorn cap (wood_bark, scaled lit/shade) holding a dew bead (detail)."""
    p = Part(svg, 22, 18, (0.5, 0.9))
    cap = smooth_path([(2, 8), (11, 6.4), (20, 8), (18.6, 13), (11, 16.6), (3.4, 13)])
    clip = svg.clip(cap)
    p.path(cap, svg.lin(0, 6, 0, 17, [(0, LIT), (0.5, LIT), (1, SHADE)]))
    for i in range(6):
        p.line([(3 + i * 3.2, 9.4), (4.6 + i * 3.0, 14.6)], SHADE, 0.9, 0.45, None, clip)
    p.ellipse(11, 7.4, 5.6, 4.4, DETAIL, 0.95)
    p.ellipse(9.6, 6.0, 1.8, 1.2, LIT, 0.8)
    p.line([(11, 6.2), (12.4, 2.2)], SHADE, 1.6)
    return p


def petal_bundle(svg: Svg) -> Part:
    """Three petals tied with a string (toadstool_cap tones; the tie in detail)."""
    p = Part(svg, 22, 22, (0.5, 0.92))
    for deg, ln in ((-120, 15), (-90, 17), (-60, 15)):
        a = math.radians(deg)
        pts = [(11, 19), (11 + math.cos(a - 0.35) * ln * 0.6, 19 + math.sin(a - 0.35) * ln * 0.6),
               (11 + math.cos(a) * ln, 19 + math.sin(a) * ln),
               (11 + math.cos(a + 0.35) * ln * 0.6, 19 + math.sin(a + 0.35) * ln * 0.6)]
        d = smooth_path(pts)
        p.path(d, svg.lin(11, 19, 11 + math.cos(a) * ln, 19 + math.sin(a) * ln, [(0, SHADE), (0.4, LIT), (1, LIT)]))
    p.ellipse(11, 16.4, 3.6, 1.8, DETAIL)
    p.line([(11, 16.4), (8.6, 20.6)], DETAIL, 1.0)
    p.line([(11, 16.4), (13.6, 20.8)], DETAIL, 1.0)
    return p


def shiny_pebble(svg: Svg) -> Part:
    """A polished pebble with a strong highlight (pebble_alt; detail = the shine)."""
    p = Part(svg, 18, 13, (0.5, 0.88))
    d = blob(9, 7, 8, 5.4, 12, 0.03, random.Random(231), math.radians(-8))
    clip = svg.clip(d)
    p.path(d, svg.lin(0, 1, 0, 13, [(0, LIT), (0.5, LIT), (1, SHADE)]))
    p.ellipse(6.6, 4.6, 3.4, 1.6, DETAIL, 1.0, svg.blur(0.4), clip, -12)
    p.ellipse(12.6, 8.4, 1.0, 0.7, DETAIL, 0.8, clip=clip)
    return p


def seed_pouch(svg: Svg) -> Part:
    """A tiny cloth pouch (wood_painted tones) tied at the neck, a leaf tag (detail)."""
    p = Part(svg, 18, 22, (0.5, 0.94))
    body = smooth_path([(6.4, 8), (11.6, 8), (15.6, 13), (16, 18.6), (9, 21.4), (2, 18.6), (2.4, 13)])
    p.path(body, svg.lin(2, 0, 16, 0, [(0, LIT), (0.55, LIT), (1, SHADE)]))
    p.path(smooth_path([(5.6, 8.6), (9, 2.6), (12.4, 8.6), (9, 9.6)]), LIT)
    p.path(smooth_path([(4.6, 9.4), (9, 8.2), (13.4, 9.4), (9, 10.6)]), SHADE, 0.9)
    p.path(blob(13.6, 5.6, 3.4, 1.8, 8, 0.05, random.Random(232), math.radians(-30)), DETAIL)
    return p


def moon_drop(svg: Svg) -> Part:
    """A pale blue glass bead that faintly glows at night (lantern_jar tones, emission 0.3)."""
    p = Part(svg, 14, 14, (0.5, 0.88))
    p.ellipse(7, 7.4, 6.2, 6.0, svg.rad(6, 6, 7, [(0, DETAIL), (0.35, LIT), (1, SHADE)]))
    p.ellipse(5, 5, 1.8, 1.2, DETAIL)
    return p


def dew_drop(svg: Svg) -> Part:
    """Gold-tinted glass dew drop (pinwheel_b tones: honey lit, amber shade, cream highlight)."""
    p = Part(svg, 12, 15, (0.5, 0.92))
    d = smooth_path([(6, 0.8), (8.6, 5.4), (10.6, 9.4), (9.8, 12.8), (6, 14.4), (2.2, 12.8), (1.4, 9.4), (3.4, 5.4)])
    clip = svg.clip(d)
    p.path(d, svg.lin(0, 0, 12, 14, [(0, LIT), (0.55, LIT), (1, SHADE)]))
    p.ellipse(4.4, 8.6, 1.4, 2.6, DETAIL, 0.95, svg.blur(0.3), clip, 15)
    p.ellipse(8, 12, 1.6, 0.8, DETAIL, 0.6, clip=clip)
    return p


# The env basket (art/props/src/props_svg.py basket(), 140 x 116 frame): its front rim band,
# replicated so gifts drawn between the basket and this overlay sit INSIDE the basket.
BASKET_RIM = [(10, 44), (30, 54), (70, 60), (110, 54), (130, 44), (110, 50), (70, 54), (30, 50)]


def basket_rim(svg: Svg) -> Part:
    p = Part(svg, 140, 64, (0.5, 0.0))
    # Front wall just under the rim, so gift bottoms vanish into the basket.
    wall = smooth_path([(12, 46), (30, 55), (70, 60), (110, 55), (128, 46), (126, 60), (110, 63), (70, 64), (30, 63),
                        (14, 60)])
    p.path(wall, svg.lin(0, 44, 0, 64, [(0, LIT), (1, LIT)]))
    p.path(smooth_path(BASKET_RIM), LIT)
    p.path(smooth_path([(14, 46), (40, 54), (70, 57), (100, 54), (126, 46)], closed=False), "none", 0.7,
           stroke=DETAIL, sw=2.4, extra=' stroke-dasharray="3 5"')
    p.path(smooth_path([(16, 58), (70, 64), (124, 58)], closed=False), "none", 0.35, svg.blur(2.0), SHADE, 5)
    return p


def leaf_boat(svg: Svg) -> Part:
    """A leaf folded into a little boat (leaf_boat): curled bow and stern, midrib (detail)."""
    p = Part(svg, 50, 22, (0.5, 0.8))
    hull = smooth_path([(1.6, 6), (8, 11), (18, 14.6), (32, 14.6), (42, 11), (48.4, 4.4), (46, 12), (38, 18.6),
                        (25, 20.6), (12, 18.6), (4, 12.4)])
    clip = svg.clip(hull)
    p.path(hull, svg.lin(0, 4, 0, 21, [(0, LIT), (0.55, LIT), (1, SHADE)]))
    p.path(smooth_path([(4, 7.4), (14, 11.4), (25, 12.6), (36, 11.4), (46, 6.4), (36, 14.4), (25, 15.6), (14, 14.4)]),
           SHADE, 0.75, clip=clip)
    p.line([(6, 12), (25, 17.2), (44, 11.4)], DETAIL, 1.2, 0.8, None, clip)
    for x in (14, 22, 30, 37):
        p.line([(x, 16.4), (x + 3, 13)], DETAIL, 0.7, 0.5, None, clip)
    return p


def candle(svg: Svg) -> Part:
    """A tiny candle on the boat (lantern_light; detail = the flame, emissive)."""
    p = Part(svg, 8, 16, (0.5, 0.97))
    p.path(smooth_path([(2.2, 8), (5.8, 8), (5.9, 15.4), (4, 15.8), (2.1, 15.4)]),
           svg.lin(2, 0, 6, 0, [(0, LIT), (0.6, LIT), (1, SHADE)]))
    p.path(smooth_path([(4, 1.0), (5.6, 4.0), (5.2, 6.4), (4, 7.2), (2.8, 6.4), (2.4, 4.0)]), DETAIL)
    return p


def dust_dot(svg: Svg) -> Part:
    """Soft round dust mote for the placement puff (string tones)."""
    p = Part(svg, 8, 8, (0.5, 0.5))
    p.ellipse(4, 4, 3.4, 3.4, svg.rad(4, 4, 3.8, [(0, DETAIL), (0.5, LIT), (1, LIT, 0.0)]))
    return p


PARTS = [
    # id, builder, material, emission, rim
    ("pinwheel_a", pinwheel_a, "pinwheel_a", 0.0, 1),
    ("pinwheel_b", pinwheel_b, "pinwheel_b", 0.0, 1),
    ("pinwheel_stick", pinwheel_stick, "wood_cut", 0.0, 0),
    ("pebble_0", lambda s: pebble_flat(s, 241, 58, 23, False), "stone_cool", 0.0, 1),
    ("pebble_1", lambda s: pebble_flat(s, 242, 50, 21, True), "stone_cool", 0.0, 1),
    # (moss caps need stone_cool: its detail tone is the moss, Art Bible §3.8)
    ("pebble_2", lambda s: pebble_flat(s, 243, 46, 19, False), "pebble_alt", 0.0, 1),
    ("pebble_3", lambda s: pebble_flat(s, 244, 42, 18, False), "stone_warm", 0.0, 1),
    ("pebble_4", lambda s: pebble_flat(s, 245, 38, 16, True), "stone_cool", 0.0, 0),
    ("pebble_5", lambda s: pebble_flat(s, 246, 34, 15, False), "pebble_alt", 0.0, 0),
    ("stream_stone", stream_stone, "stone_cool", 0.0, 1),
    ("toadstool_cap", toadstool_cap, "toadstool_cap", 0.0, 1),
    ("toadstool_stem", toadstool_stem, "toadstool_stem", 0.0, 0),
    ("lantern_crook", lantern_crook, "wood_bark", 0.0, 0),
    ("lantern_core", lantern_core, "lantern_light", 0.85, 0),
    ("lantern_jar", lantern_jar, "lantern_jar", 0.0, 0),
    ("chime_short", lambda s: chime_tube(s, 46, 30, False), "chime_ceramic", 0.0, 0),
    ("chime_mid", lambda s: chime_tube(s, 58, 34, False), "chime_ceramic", 0.0, 0),
    ("chime_long", lambda s: chime_tube(s, 70, 38, False), "chime_ceramic", 0.0, 0),
    ("chime_paper", lambda s: chime_tube(s, 52, 32, True), "chime_ceramic", 0.0, 0),
    ("gift_acorn_cup", acorn_cup, "wood_bark", 0.0, 0),
    ("gift_petal_bundle", petal_bundle, "toadstool_cap", 0.0, 0),
    ("gift_shiny_pebble", shiny_pebble, "pebble_alt", 0.0, 0),
    ("gift_seed_pouch", seed_pouch, "wood_painted", 0.0, 0),
    ("gift_moon_drop", moon_drop, "lantern_jar", 0.3, 0),
    ("dew_drop", dew_drop, "pinwheel_b", 0.0, 0),
    ("basket_rim", basket_rim, "wicker", 0.0, 0),
    ("leaf_boat", leaf_boat, "leaf_boat", 0.0, 1),
    ("candle", candle, "lantern_light", 0.85, 0),
    ("dust_dot", dust_dot, "string", 0.0, 0),
]

LAYOUT = {
    "doc": "Placement data for scripts/garden/decor_layer.gd (design px at depth 1). Art Bible §6.6-6.8.",
    "lantern_hook": list(LANTERN_HOOK),
    "lantern_core_dy": 14.0,
    "pinwheel_head_dy": -86.0,
    "chime_parts": ["chime_paper", "chime_mid", "chime_long", "chime_short"],
    "cairn_parts": ["pebble_0", "pebble_1", "pebble_2", "pebble_3", "pebble_4", "pebble_5"],
    "basket_frame": [140, 116],
    "set_scale": {"leaf_pinwheel": 1.3, "pebble_cairn": 1.0, "toadstool_seat": 1.25, "stream_stones": 0.82,
                  "firefly_lantern": 1.0, "wind_chime": 1.35},
    "toadstool_cap_dy": -20.0,
    "jar_centre_dy": 28.0,
    "toadstool_ring": {"centre": [345.6, 825.6], "radii": [72.0, 34.0], "motes": 6},
    "chime_sort_y": 806.0,
    "basket_rim_y": 0.0,
    "gift_parts": {"acorn_cup": "gift_acorn_cup", "petal_bundle": "gift_petal_bundle",
                   "shiny_pebble": "gift_shiny_pebble", "seed_pouch": "gift_seed_pouch",
                   "moon_drop": "gift_moon_drop"},
    # Gift slots peeking over the rim and dew-drop slots in the opening (basket frame px).
    "gift_slots": [[48, 44], [92, 43], [70, 41]],
    "dew_slots": [[34, 46], [106, 46], [58, 48], [82, 48], [44, 43], [96, 43], [70, 49], [26, 47],
                  [114, 47], [56, 41], [84, 41], [70, 44]],
}


def main() -> int:
    svg = Svg(ATLAS_W, 16)
    built = [(pid, b(svg)) for pid, b, *_ in PARTS]
    regions = write_atlas(svg, built, SCALE, ATLAS_W, PAD)
    OUT_SVG.write_text(svg.to_string())
    parts = {}
    for pid, _b, mat, em, rim in PARTS:
        entry = dict(regions[pid])
        entry.update({"material": mat, "emission": em, "rim": rim})
        parts[pid] = entry
    doc = {"schema": 1, "doc": __doc__.strip().splitlines()[0], "atlas": "res://art/decor/decor_atlas.svg",
           "size": [ATLAS_W, svg.h], "scale": SCALE, "parts": parts, "layout": LAYOUT}
    OUT_JSON.write_text(json.dumps(doc, indent="\t") + "\n")
    print(f"wrote {OUT_SVG.relative_to(ROOT)} ({ATLAS_W}x{svg.h}, {len(parts)} parts)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
