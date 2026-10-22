#!/usr/bin/env python3
"""Generates art/flora/flora_atlas.svg (tone masks) + art/flora/flora_atlas.json (stamps, grammar).

Art Bible §6.1 (stamp list, authoring), §6.2 (stages), §6.3 (the eight MVP flowers), §3.7 (fl_*
colours, applied by the shader), §4.10 (flora_bed.gdshader). Run from the repo root:

    python3 -I -B art/flora/src/flora_svg.py && godot --headless --path . --import

Every stamp is authored at design px (depth scale 1) and written at SCALE x. The JSON lists, per
stamp, its atlas region (px), its size at depth 1 (design px) and its pivot (normalised: where it
attaches: a petal's base, a bell's hanger, a leaf's base, a head's centre). The "forms" block is
the per-flower grammar FloraBuilder (scripts/flora/flora_builder.gd) interprets: stem length and
width, lean, leaves (stamp, attach height, side, angle, scale), the head (kind, stamps, counts,
radii) and the bud, all in design px / degrees. Tone channels per part are mapped to colours by
the shader (part kinds in flora_builder.gd): petals/bells -> petal triple, leaves -> leaf triple,
centres -> petal detail as lit, buds -> bud with a petal-coloured tip (B), soil/moss -> row 8.
"""
from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from tonekit import DETAIL, LINE, LIT, SHADE, Part, Svg, blob, blob_pts, f, rot_pts, smooth_path, write_atlas  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
OUT_SVG = ROOT / "art/flora/flora_atlas.svg"
OUT_JSON = ROOT / "art/flora/flora_atlas.json"
SCALE = 2
ATLAS_W = 1024
PAD = 6


# --------------------------------------------------------------------------------------------- #
# Petals and heads
# --------------------------------------------------------------------------------------------- #

def petal_round(svg: Svg) -> Part:
    """Daisy ray: a soft spoon, base at the left (pivot), tip right; shade at the base and belly."""
    p = Part(svg, 24, 12, (0.02, 0.5))
    d = smooth_path([(0.8, 6), (4, 3.6), (11, 1.6), (19, 1.3), (23.2, 3.8), (23.4, 7.6), (19.5, 10.6),
                     (11, 10.5), (4, 8.6)])
    clip = svg.clip(d)
    p.path(d, svg.lin(0, 0, 24, 0, [(0, SHADE), (0.3, LIT), (1, LIT)]))
    p.path(d, svg.lin(0, 1, 0, 11, [(0, SHADE, 0.0), (0.55, SHADE, 0.0), (1, SHADE, 0.55)]))
    p.line([(4, 6.2), (12, 5.9), (19, 6.1)], SHADE, 1.0, 0.35, svg.blur(0.6), clip)
    p.ellipse(16, 4.2, 5, 1.6, LIT, 0.8, svg.blur(0.8), clip)
    return p


def daisy_center(svg: Svg) -> Part:
    """Domed golden boss (mapped to the petal detail colour), darker floret dots, a top highlight."""
    p = Part(svg, 16, 15, (0.5, 0.5))
    rng = random.Random(21)
    d = blob(8, 7.6, 7.2, 6.6, 14, 0.03, rng)
    clip = svg.clip(d)
    p.path(d, svg.rad(6.5, 5.5, 9.5, [(0, LIT), (0.55, LIT), (1, SHADE)]))
    for ring, (r, n) in enumerate(((2.2, 6), (4.4, 11), (6.0, 15))):
        for i in range(n):
            a = math.tau * (i + 0.5 * ring) / n
            p.ellipse(8 + math.cos(a) * r, 7.6 + math.sin(a) * r * 0.92, 0.75, 0.75, SHADE, 0.55, clip=clip)
    p.ellipse(6.2, 4.8, 2.8, 1.8, DETAIL, 0.7, svg.blur(0.9), clip)
    return p


def clover_head(svg: Svg) -> Part:
    """Sweet-clover globe: ~30 upright florets on a dome, pink-white tips (B), shade toward the base."""
    p = Part(svg, 32, 32, (0.5, 0.62))
    rng = random.Random(31)
    cx, cy = 16, 18
    p.path(blob(cx, cy + 1, 12.5, 11, 14, 0.05, rng), SHADE)
    florets = []
    for ring, (r, n, up) in enumerate(((11.5, 13, 0.0), (8, 10, 0.25), (4.2, 6, 0.55), (0.0, 1, 0.8))):
        for i in range(n):
            a = math.tau * (i + 0.37 * ring) / n + rng.uniform(-0.12, 0.12)
            x = cx + math.cos(a) * r
            y = cy + math.sin(a) * r * 0.82 - 6 * up
            florets.append((y, x, a, ring))
    florets.sort()
    for y, x, a, ring in florets:
        # Each floret: a rounded teardrop leaning outward from the dome centre, lighter at its tip.
        lean = math.degrees(math.atan2(x - cx, 11)) * 0.9
        pts = rot_pts([(x - 2.0, y + 2.6), (x - 2.2, y - 0.6), (x, y - 3.6), (x + 2.2, y - 0.6), (x + 2.0, y + 2.6)],
                      x, y, lean)
        d = smooth_path(pts)
        lower = y > cy + 2
        p.path(d, svg.lin(0, y + 3, 0, y - 4, [(0, SHADE), (0.45, LIT), (1, DETAIL)]) if not lower
               else svg.lin(0, y + 3, 0, y - 4, [(0, SHADE), (0.7, LIT), (1, LIT)]))
    p.path(blob(cx, cy + 6, 11, 5, 12, 0.05, rng), SHADE, 0.35, svg.blur(2.0))
    return p


def petal_cup(svg: Svg) -> Part:
    """Buttercup petal: broad rounded spoon, base at the bottom (pivot), a glossy streak (B)."""
    p = Part(svg, 18, 18, (0.5, 0.97))
    d = smooth_path([(9, 17.6), (5, 15), (1.6, 9.5), (2.4, 4), (6, 1.0), (9, 0.6), (12, 1.0), (15.6, 4), (16.4, 9.5),
                     (13, 15)])
    clip = svg.clip(d)
    p.path(d, svg.lin(0, 18, 0, 0, [(0, SHADE), (0.4, LIT), (1, LIT)]))
    p.path(d, svg.lin(0, 0, 18, 0, [(0, SHADE, 0.3), (0.3, SHADE, 0.0), (0.7, SHADE, 0.0), (1, SHADE, 0.35)]))
    p.path(smooth_path([(7.2, 4.0), (9, 2.6), (11.4, 4.2), (10.6, 8.8), (8, 9.4)]), DETAIL, 0.85, svg.blur(0.7), clip=clip)
    p.ellipse(9, 16, 4, 2.4, SHADE, 0.5, svg.blur(1.0), clip)
    return p


def forget_bloom(svg: Svg) -> Part:
    """Forget-me-not: five round lobes, a yellow eye (B) with a pale ring."""
    p = Part(svg, 14, 14, (0.5, 0.5))
    rng = random.Random(41)
    for i in range(5):
        a = math.tau * i / 5 - math.pi / 2
        x, y = 7 + math.cos(a) * 3.5, 7 + math.sin(a) * 3.5
        d = blob(x, y, 3.3, 3.1, 10, 0.05, rng, a)
        p.path(d, svg.rad(7, 7, 7, [(0, SHADE), (0.45, LIT), (1, LIT)]))
    p.path(blob(7, 7, 6.6, 6.6, 12, 0.02, rng), SHADE, 0.25, svg.blur(1.2))
    p.ellipse(7, 7, 2.2, 2.2, LIT, 0.9)
    p.ellipse(7, 7, 1.5, 1.5, DETAIL)
    return p


def bell(svg: Svg) -> Part:
    """Bluebell: a nodding bell hanging from its top (pivot), flared scalloped rim lighter (B)."""
    p = Part(svg, 16, 20, (0.5, 0.03))
    body = smooth_path([(8, 0.6), (11, 1.6), (12.4, 6), (13.4, 12), (15.4, 16.2), (14.6, 18.2), (12.6, 17.4),
                        (11, 19.2), (8, 18.0), (5, 19.2), (3.4, 17.4), (1.4, 18.2), (0.6, 16.2), (2.6, 12),
                        (3.6, 6), (5, 1.6)])
    clip = svg.clip(body)
    p.path(body, svg.lin(0, 0, 16, 0, [(0, SHADE), (0.35, LIT), (0.6, LIT), (1, SHADE)]))
    p.path(body, svg.lin(0, 0, 0, 20, [(0, SHADE, 0.45), (0.25, SHADE, 0.0), (1, SHADE, 0.0)]))
    p.path(smooth_path([(1.2, 16.6), (4, 15.4), (8, 15.0), (12, 15.4), (14.8, 16.6), (12.6, 18.6), (11, 19.6),
                        (8, 18.6), (5, 19.6), (3.4, 18.6)]), DETAIL, 0.9, clip=clip)
    p.ellipse(8, 17.4, 4.6, 1.4, SHADE, 0.55, svg.blur(0.6), clip)
    p.line([(6, 3), (5.4, 9), (5.0, 14)], LIT, 1.4, 0.6, svg.blur(0.5), clip)
    return p


def petal_heart(svg: Svg) -> Part:
    """Primrose petal: a broad notched heart, base at the bottom (pivot); the star (B) at the base."""
    p = Part(svg, 16, 15, (0.5, 0.98))
    d = smooth_path([(8, 14.8), (4, 12), (1.0, 7.6), (1.2, 3.2), (4, 0.9), (6.6, 1.2), (8, 3.0), (9.4, 1.2),
                     (12, 0.9), (14.8, 3.2), (15.0, 7.6), (12, 12)])
    clip = svg.clip(d)
    p.path(d, LIT)
    p.path(d, svg.lin(0, 0, 16, 0, [(0, SHADE, 0.35), (0.3, SHADE, 0.0), (0.7, SHADE, 0.0), (1, SHADE, 0.35)]))
    p.path(smooth_path([(8, 15.5), (5.6, 11.4), (8, 8.6), (10.4, 11.4)]), DETAIL, 0.95, svg.blur(0.7), clip=clip)
    p.line([(8, 13), (8, 5)], SHADE, 0.8, 0.25, svg.blur(0.4), clip)
    return p


def eye_center(svg: Svg) -> Part:
    """Small round eye (primrose / lily boss), mapped to the petal detail colour."""
    p = Part(svg, 6, 6, (0.5, 0.5))
    p.ellipse(3, 3, 2.7, 2.7, svg.rad(2.4, 2.2, 3.2, [(0, LIT), (0.6, LIT), (1, SHADE)]))
    return p


def petal_lily(svg: Svg) -> Part:
    """Moonbloom petal: long, softly pointed and recurved, base at the left (pivot), a central groove."""
    p = Part(svg, 30, 12, (0.02, 0.5))
    d = smooth_path([(0.6, 6), (5, 3.0), (13, 1.2), (22, 1.8), (28, 4.2), (29.6, 6.0), (28, 7.4), (22, 10.2),
                     (13, 10.8), (5, 9.0)])
    clip = svg.clip(d)
    p.path(d, svg.lin(0, 0, 30, 0, [(0, SHADE), (0.25, LIT), (1, LIT)]))
    p.path(d, svg.lin(0, 1, 0, 11, [(0, SHADE, 0.0), (0.5, SHADE, 0.0), (1, SHADE, 0.5)]))
    p.line([(3, 6), (14, 5.8), (26, 5.6)], SHADE, 0.9, 0.4, svg.blur(0.5), clip)
    p.ellipse(18, 3.6, 7, 1.4, LIT, 0.7, svg.blur(0.8), clip)
    return p


def stamens(svg: Svg) -> Part:
    """Moonbloom stamens: pale filaments (B = petal colour) fanning up to glowing anthers (R = detail)."""
    p = Part(svg, 16, 14, (0.5, 0.92))
    for i in range(6):
        a = math.radians(-90 + (i - 2.5) * 17)
        x, y = 8 + math.cos(a) * 11, 13 + math.sin(a) * 11
        p.line([(8, 13), ((8 + x) / 2 + (i - 2.5) * 0.2, (13 + y) / 2), (x, y)], DETAIL, 1.0)
        p.ellipse(x, y, 1.5, 1.1, LIT, 1.0, rot=math.degrees(a))
    return p


def seed_puff(svg: Svg) -> Part:
    """Dandelion clock: radiating pappus filaments with soft tufts, translucent; seed boss (B)."""
    p = Part(svg, 46, 46, (0.5, 0.5))
    rng = random.Random(71)
    cx = cy = 23
    p.ellipse(cx, cy, 19.5, 19.5, LIT, 0.22, svg.blur(2.0))
    p.ellipse(cx, cy + 4, 17, 12, SHADE, 0.12, svg.blur(3.0))
    n = 46
    tips = []
    for i in range(n):
        a = math.tau * i / n + rng.uniform(-0.05, 0.05)
        r = rng.uniform(17.5, 20.5)
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        tips.append((x, y, a))
        p.line([(cx + math.cos(a) * 2.5, cy + math.sin(a) * 2.5), (x, y)], LIT, 0.55, 0.55)
    for x, y, a in tips:
        lower = math.sin(a) > 0.35
        p.ellipse(x, y, 2.1, 2.1, SHADE if lower else LIT, 0.55 if lower else 0.75, svg.blur(0.45))
    # inner ring of tufts for body
    for i in range(22):
        a = math.tau * i / 22 + 0.1
        r = rng.uniform(9, 14)
        p.ellipse(cx + math.cos(a) * r, cy + math.sin(a) * r, 1.6, 1.6, LIT, 0.35, svg.blur(0.5))
    p.ellipse(cx, cy, 3.0, 3.0, DETAIL)
    p.ellipse(cx - 0.8, cy - 0.8, 1.2, 1.2, LIT, 0.6)
    return p


def bud_round(svg: Svg) -> Part:
    """Round bud: green sepals (shade) cupping a body in the bud colour, a petal-coloured tip (B)."""
    p = Part(svg, 10, 12, (0.5, 0.96))
    body = smooth_path([(5, 11.6), (2.0, 9.6), (0.8, 6.2), (2.2, 2.4), (5, 0.6), (7.8, 2.4), (9.2, 6.2), (8, 9.6)])
    clip = svg.clip(body)
    p.path(body, svg.lin(0, 0, 10, 0, [(0, LIT), (0.6, LIT), (1, SHADE)]))
    p.path(smooth_path([(1.6, 4.2), (5, 0.4), (8.4, 4.2), (6.6, 3.6), (5, 3.0), (3.4, 3.6)]), DETAIL, 0.95, svg.blur(0.5),
           clip=clip)
    for sx in (-1, 1):
        p.path(smooth_path([(5, 11.8), (5 + sx * 3.6, 9.4), (5 + sx * 4.2, 5.4), (5 + sx * 1.6, 8.4)]), SHADE, 0.9)
    p.path(smooth_path([(5, 11.8), (3.6, 8.8), (5, 5.6), (6.4, 8.8)]), SHADE, 0.8)
    return p


def bud_long(svg: Svg) -> Part:
    """Long closed bud (dandelion, moonbloom): sepals in shade, a petal-coloured tip (B)."""
    p = Part(svg, 9, 18, (0.5, 0.97))
    body = smooth_path([(4.5, 17.6), (1.4, 14), (0.8, 8), (2.4, 2.6), (4.5, 0.6), (6.6, 2.6), (8.2, 8), (7.6, 14)])
    clip = svg.clip(body)
    p.path(body, svg.lin(0, 0, 9, 0, [(0, LIT), (0.55, LIT), (1, SHADE)]))
    p.path(smooth_path([(1.4, 6), (4.5, 0.2), (7.6, 6), (4.5, 4.4)]), DETAIL, 0.95, svg.blur(0.5), clip=clip)
    for sx in (-1, 1):
        p.path(smooth_path([(4.5, 17.8), (4.5 + sx * 3.6, 13), (4.5 + sx * 2.6, 6.5), (4.5 + sx * 0.8, 12)]), SHADE, 0.85)
    return p


# --------------------------------------------------------------------------------------------- #
# Leaves (leaf triple: lit / shade / detail = pale midrib or chevron)
# --------------------------------------------------------------------------------------------- #

def _leaf(svg: Svg, w: float, h: float, outline: list, midrib: list, shade_below: float = 0.32,
          veins: int = 0) -> Part:
    p = Part(svg, w, h, (0.02, 0.5))
    d = smooth_path(outline)
    clip = svg.clip(d)
    p.path(d, svg.lin(0, 0, w, 0, [(0, SHADE), (0.12, LIT), (1, LIT)]))
    p.path(d, svg.lin(0, 0, 0, h, [(0, SHADE, 0.0), (0.6, SHADE, 0.0), (1, SHADE, shade_below)]))
    p.ellipse(w * 0.6, h * 0.3, w * 0.28, h * 0.12, DETAIL, 0.22, svg.blur(h * 0.08))
    # Plush felt leaf (round 5): the midrib is an embroidered running stitch in a pressed groove.
    sw = max(0.75, h * 0.065)
    p.stitch(midrib, sw, sw * 2.4, sw * 1.7, clip, opacity=0.8, groove=0.35)
    for i in range(veins):
        t = (i + 1) / (veins + 1)
        x = w * (0.12 + 0.75 * t)
        for sy in (-1, 1):
            p.line([(x, h / 2), (x + w * 0.1, h / 2 + sy * h * 0.32)], SHADE, max(0.7, h * 0.05), 0.45, None, clip)
    return p


def leaf_spoon(svg: Svg) -> Part:
    return _leaf(svg, 28, 12, [(0.5, 6), (6, 4.6), (14, 2.0), (22, 1.0), (27.2, 4.0), (27.4, 7.6), (22, 11),
                               (14, 10.2), (6, 7.6)], [(1, 6), (12, 6.2), (24, 5.8)])


def leaf_lance(svg: Svg) -> Part:
    return _leaf(svg, 26, 8, [(0.5, 4), (8, 1.6), (18, 0.9), (25.6, 3.4), (25.4, 4.8), (18, 7.2), (8, 6.6)],
                 [(1, 4), (13, 4.1), (23, 4.0)])


def leaf_strap(svg: Svg) -> Part:
    """Bluebell strap leaf, gently arched (the builder fans three from the base)."""
    out = [(0.5, 7.2), (12, 4.4), (28, 2.4), (44, 2.6), (56, 4.6), (59.4, 6.6), (57, 8.6), (44, 7.6), (28, 7.6),
           (12, 9.2)]
    return _leaf(svg, 60, 11, out, [(2, 7.2), (30, 5.2), (54, 6.4)], 0.4)


def leaf_trifoliate(svg: Svg) -> Part:
    """Clover leaf: three rounded heart leaflets around the petiole tip (pivot), pale chevrons (B)."""
    p = Part(svg, 28, 24, (0.5, 0.86))
    rng = random.Random(81)
    cx, cy = 14, 20.5
    for deg in (-150, -90, -30):
        a = math.radians(deg)
        x, y = cx + math.cos(a) * 7.4, cy + math.sin(a) * 7.4
        pts = blob_pts(x, y, 7.2, 6.0, 12, 0.03, rng, a)
        d = smooth_path(pts)
        clip = svg.clip(d)
        p.path(d, svg.lin(cx, cy, x + math.cos(a) * 7, y + math.sin(a) * 7, [(0, SHADE), (0.45, LIT), (1, LIT)]))
        # pale chevron
        ox, oy = math.cos(a), math.sin(a)
        nx, ny = -oy, ox
        mx, my = x + ox * 0.6, y + oy * 0.6
        p.line([(mx + nx * 3.4 - ox * 1.2, my + ny * 3.4 - oy * 1.2), (mx + ox * 1.4, my + oy * 1.4),
                (mx - nx * 3.4 - ox * 1.2, my - ny * 3.4 - oy * 1.2)], DETAIL, 1.5, 0.7, svg.blur(0.3), clip)
    p.ellipse(cx, cy, 2.0, 2.0, SHADE)
    return p


def leaf_lobed(svg: Svg) -> Part:
    """Buttercup leaf: a rounded three-lobed palm (no sharp teeth), base at the bottom (pivot)."""
    p = Part(svg, 30, 26, (0.5, 0.95))
    rng = random.Random(91)
    lobes = [(-58, 9.5, 7.4), (-90, 11.5, 8.2), (-122, 9.5, 7.4)]
    cx, cy = 15, 24
    for deg, r, s in lobes:
        a = math.radians(deg)
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        d = blob(x, y, s, s * 0.9, 12, 0.06, rng, a)
        p.path(d, svg.lin(cx, cy, x + math.cos(a) * s, y + math.sin(a) * s, [(0, SHADE), (0.4, LIT), (1, LIT)]))
    for deg, r, _s in lobes:
        a = math.radians(deg)
        p.line([(cx, cy - 1), (cx + math.cos(a) * r * 1.3, cy + math.sin(a) * r * 1.3)], DETAIL, 1.0, 0.6)
    p.ellipse(cx, cy - 2, 5, 3, SHADE, 0.5, svg.blur(1.0))
    return p


def leaf_rosette(svg: Svg) -> Part:
    """Primrose leaf: broad crinkled oval, veins pressed in (shade), base at the left (pivot)."""
    return _leaf(svg, 34, 15, [(0.5, 7.5), (6, 5.0), (14, 1.6), (24, 1.0), (32, 3.6), (33.6, 7.6), (31, 11.8),
                               (23, 14.2), (13, 13.6), (6, 10.2)], [(1, 7.6), (16, 7.4), (30, 7.2)], 0.35, 4)


def leaf_toothed(svg: Svg) -> Part:
    """Dandelion leaf: long with ROUNDED lobes (no spikes), base at the left (pivot)."""
    top = [(0.5, 6.5)]
    bot = []
    for i in range(5):
        x = 6 + i * 7.6
        top += [(x, 4.6 - 0.2 * i), (x + 3.4, 1.4 + 0.2 * i)]
        bot += [(x, 8.4 + 0.2 * i), (x + 3.4, 11.6 - 0.2 * i)]
    top += [(43.4, 5.6)]
    out = top + [(43.6, 7.2)] + list(reversed(bot))
    return _leaf(svg, 44, 13, out, [(1, 6.5), (22, 6.4), (40, 6.4)], 0.35)


def leaf_broad(svg: Svg) -> Part:
    return _leaf(svg, 46, 16, [(0.5, 8), (8, 4.4), (20, 1.4), (34, 1.4), (44, 5.6), (45.6, 8.2), (43, 10.6),
                               (32, 14.6), (18, 14.8), (8, 11.6)], [(1, 8), (22, 8.2), (42, 8.0)], 0.4)


def cotyledon(svg: Svg) -> Part:
    return _leaf(svg, 12, 8, [(0.4, 4), (3, 2.0), (7, 0.8), (11, 2.2), (11.6, 4.4), (9.6, 7.0), (5, 7.4),
                              (2, 5.8)], [(1, 4), (9, 4.2)], 0.3)


# --------------------------------------------------------------------------------------------- #
# Ground, stems and FX
# --------------------------------------------------------------------------------------------- #

def soil_mound(svg: Svg) -> Part:
    """A small tended soil mound (soil row): a soft rounded dome, lit crown, shade skirt, a few
    pale grains (B) and darker crumbs; low and round so it never reads as a dry dirt stamp."""
    p = Part(svg, 34, 13, (0.5, 0.88))
    rng = random.Random(101)
    d = smooth_path([(1.5, 11.6), (4, 7.4), (10, 4.0), (17, 3.0), (24, 4.0), (30, 7.4), (32.5, 11.6), (24, 12.8),
                     (17, 13.0), (10, 12.8)])
    clip = svg.clip(d)
    p.path(d, svg.lin(0, 2.5, 0, 13, [(0, LIT), (0.5, LIT), (1, SHADE)]))
    p.ellipse(15, 5.6, 7, 1.6, DETAIL, 0.45, svg.blur(0.8), clip)
    p.speckles(rng, (6, 5, 28, 11), 8, (0.45, 0.9), DETAIL, (0.5, 0.9), clip)
    p.speckles(rng, (6, 6, 28, 12), 10, (0.4, 0.8), SHADE, (0.3, 0.6), clip)
    return p


def foliage_tuft(svg: Svg) -> Part:
    """Leafy clump at a stem's foot (leaf triple): three rows of rounded leaves fanning from the
    base, back rows in shade, the front row lit with a soft sheen; neighbouring clumps overlap into
    one lush mound the flowers grow out of. Pivot at the bottom centre."""
    # 4 px of headroom below the foot so the tucked shade's blur is never cut by the atlas cell
    # (round 5: the clipped blur drew a hard horizontal bar under every clump).
    p = Part(svg, 48, 30, (0.5, 22.88 / 30))
    rng = random.Random(111)
    cx, base = 24, 23.5
    # Round 5 (plush play-set): fewer, chunkier felt leaves (the shader puffs each one up).
    rows = [(7, 9.0, 0.55, 0.62), (6, 9.8, 0.78, 0.82), (5, 10.6, 1.0, 1.0)]  # n, leaf len, reach, light
    for ri, (n, ln, reach, light) in enumerate(rows):
        for i in range(n):
            t = (i + 0.5) / n
            a = math.radians(-180 + 180 * t + rng.uniform(-7, 7))
            r = (13 + 7 * reach) * (0.92 + 0.16 * math.sin(math.pi * t))
            x = cx + math.cos(a) * r * 0.95
            y = base - 2 + math.sin(a) * r * (0.55 + 0.12 * ri) - ri * 0.6
            lx, ly = x, y
            rot = math.degrees(a)
            lw = ln * rng.uniform(0.9, 1.15)
            d = blob(lx, ly, lw * 0.62, lw * 0.4, 10, 0.06, rng, math.radians(rot))
            top = SHADE if light < 0.7 else LIT
            p.path(d, svg.lin(0, ly - lw * 0.5, 0, ly + lw * 0.5,
                               [(0, top), (0.55, LIT if light > 0.7 else SHADE), (1, SHADE)]))
            if light > 0.7:
                p.ellipse(lx - math.cos(a) * 1.2, ly - lw * 0.18, lw * 0.3, lw * 0.11, DETAIL, 0.4 * light,
                          svg.blur(0.5), rot=rot)
    # A soft tucked-under shade (no hard bar along the foot).
    p.ellipse(24, 23.2, 17, 2.4, SHADE, 0.45, svg.blur(1.8))
    return p


def bed_shadow(svg: Svg) -> Part:
    """Soft contact shade under a planted bed (moss row, shade tone): grounds the clumps."""
    # The cell holds the whole blur (round 5: a cut blur drew straight edges under the beds).
    p = Part(svg, 84, 38, (0.5, 21.6 / 38))
    p.ellipse(42, 20, 30, 8.5, SHADE, 0.75, svg.blur(4.5))
    return p


def moss_pad(svg: Svg) -> Part:
    """Moss cushion under a tended bed (moss row): a soft felted mound with fibre speckles."""
    p = Part(svg, 64, 24, (0.5, 0.88))
    rng = random.Random(121)
    d = smooth_path([(2, 19), (6, 12), (14, 7), (26, 4.2), (38, 4.0), (50, 6.4), (58, 11), (62, 18), (52, 21.6),
                     (32, 22.6), (12, 21.6)])
    clip = svg.clip(d)
    p.path(d, svg.lin(0, 3, 0, 23, [(0, LIT), (0.5, LIT), (1, SHADE)]))
    for _ in range(8):
        x, y = rng.uniform(10, 54), rng.uniform(7, 15)
        p.path(blob(x, y, rng.uniform(4, 7), rng.uniform(2.5, 4), 10, 0.1, rng), DETAIL, 0.35, svg.blur(1.0), clip=clip)
    p.speckles(rng, (6, 6, 58, 20), 40, (0.35, 0.7), SHADE, (0.3, 0.6), clip)
    p.speckles(rng, (6, 4, 58, 14), 26, (0.3, 0.6), DETAIL, (0.4, 0.8), clip)
    return p


def stem(svg: Svg) -> Part:
    """Stem strip texture: lit centre line, shade edges, soft alpha edges (u across, v along)."""
    p = Part(svg, 6, 16, (0.5, 1.0))
    p.path("M0.4,0 H5.6 V16 H0.4 Z", svg.lin(0, 0, 6, 0, [(0, SHADE), (0.3, LIT), (0.62, LIT), (1, SHADE)]))
    p.path("M2.2,0 H3.0 V16 H2.2 Z", DETAIL, 0.25, svg.blur(0.3))
    return p


def sparkle(svg: Svg) -> Part:
    """Rounded four-point sparkle (FX row: R core colour, B hot centre)."""
    p = Part(svg, 16, 16, (0.5, 0.5))
    pts = []
    for i in range(8):
        a = math.tau * i / 8 - math.pi / 2
        r = 7.6 if i % 2 == 0 else 2.0
        pts.append((8 + math.cos(a) * r, 8 + math.sin(a) * r))
    p.path(smooth_path(pts, tension=0.55), LIT)
    p.ellipse(8, 8, 2.4, 2.4, DETAIL, 1.0, svg.blur(0.6))
    return p


def glint(svg: Svg) -> Part:
    """Dew bead / seed glint: a soft round bead with a hot highlight (FX row)."""
    p = Part(svg, 8, 8, (0.5, 0.5))
    p.ellipse(4, 4, 3.4, 3.4, svg.rad(4, 4, 3.6, [(0, LIT), (0.7, LIT, 0.7), (1, LIT, 0.0)]))
    p.ellipse(3.0, 3.0, 1.2, 1.2, DETAIL)
    return p


def seed_glow(svg: Svg) -> Part:
    """The tutorial seed: a plump rounded seed (bud row tones), a warm highlight (B)."""
    p = Part(svg, 12, 9, (0.5, 0.85))
    d = blob(6, 4.6, 5.0, 3.6, 12, 0.04, random.Random(131), math.radians(-12))
    clip = svg.clip(d)
    p.path(d, svg.lin(0, 0, 0, 9, [(0, LIT), (0.55, LIT), (1, SHADE)]))
    p.ellipse(4.4, 3.0, 2.0, 1.0, DETAIL, 0.9, svg.blur(0.5), clip, -12)
    return p


def wing(svg: Svg) -> Part:
    """Butterfly wing pair (one side): a rounded forewing over a smaller hindwing, hinged at the
    body (pivot, left); petal tones (shade at the hinge), pale spots (B); the body edge is the
    colour-line tone."""
    p = Part(svg, 16, 16, (0.04, 0.5))
    rng = random.Random(141)
    fore = smooth_path([(0.6, 7.6), (3, 3.6), (8, 0.8), (13.4, 1.2), (15.4, 4.4), (13.6, 7.6), (7, 8.4)])
    hind = smooth_path([(0.6, 8.2), (5, 8.6), (10.4, 10.4), (11.4, 13.4), (8, 15.4), (3.6, 14.2), (1.2, 11)])
    for d in (hind, fore):
        clip = svg.clip(d)
        p.path(d, svg.lin(0, 0, 16, 0, [(0, SHADE), (0.45, LIT), (1, LIT)]))
        p.path(d, svg.lin(0, 0, 0, 16, [(0, SHADE, 0.0), (0.6, SHADE, 0.0), (1, SHADE, 0.35)]), clip=clip)
    p.ellipse(11.2, 3.6, 1.6, 1.2, DETAIL, 0.95)
    p.ellipse(7.6, 12.2, 1.2, 1.0, DETAIL, 0.9)
    p.ellipse(13.6, 2.6, 0.8, 0.7, DETAIL, 0.8)
    p.line([(0.4, 2.0), (0.6, 14.0)], LINE, 1.6)
    return p


# Round 5: every stamp but the tiling stem strip, the wing
# (hinged at its edge) and the FX gets STAMP_MARGIN design px of empty atlas around it, so no tip or
# blur is cut flat by its cell (the plush shading reads the blurred alpha right up to the edge).
STAMP_MARGIN = 1.5
UNPADDED = {"stem", "wing", "sparkle", "glint", "seed_glow"}
MARGIN_OVERRIDE = {"foliage_tuft": 4.5}

STAMPS = [
    ("petal_round", petal_round), ("daisy_center", daisy_center), ("clover_head", clover_head),
    ("petal_cup", petal_cup), ("forget_bloom", forget_bloom), ("bell", bell), ("petal_heart", petal_heart),
    ("eye_center", eye_center), ("petal_lily", petal_lily), ("stamens", stamens), ("seed_puff", seed_puff),
    ("bud_round", bud_round), ("bud_long", bud_long), ("leaf_spoon", leaf_spoon), ("leaf_lance", leaf_lance),
    ("leaf_strap", leaf_strap), ("leaf_trifoliate", leaf_trifoliate), ("leaf_lobed", leaf_lobed),
    ("leaf_rosette", leaf_rosette), ("leaf_toothed", leaf_toothed), ("leaf_broad", leaf_broad),
    ("cotyledon", cotyledon), ("soil_mound", soil_mound), ("foliage_tuft", foliage_tuft), ("moss_pad", moss_pad),
    ("bed_shadow", bed_shadow), ("wing", wing),
    ("stem", stem), ("sparkle", sparkle), ("glint", glint), ("seed_glow", seed_glow),
]


# --------------------------------------------------------------------------------------------- #
# Grammar (Art Bible §6.3). Angles in degrees, 0 = right, -90 = up (canvas y down). Leaf "at" is
# the attach height as a fraction of the stem (0 = root); side +1 right / -1 left; "angle" is the
# leaf's angle away from vertical-up toward its side; scale multiplies the stamp's depth-1 size.
# head.kind: globe | radial | cup | cluster | bells | primrose | puff | lily.
# --------------------------------------------------------------------------------------------- #

FORMS = {
    "globe": {
        "stem_len": 70, "stem_w": [3.6, 2.2], "lean_deg": 8, "s_curve": 0.12, "base": "foliage_tuft",
        "base_scale": 0.85,
        "leaves": [{"stamp": "leaf_trifoliate", "at": 0.34, "side": 1, "angle": 58, "scale": 0.95, "petiole": 12},
                   {"stamp": "leaf_trifoliate", "at": 0.14, "side": -1, "angle": 62, "scale": 0.85, "petiole": 10},
                   {"stamp": "leaf_trifoliate", "at": 0.05, "side": 1, "angle": 75, "scale": 0.8, "petiole": 8}],
        "head": {"kind": "globe", "stamp": "clover_head", "scale": 0.96},
        "bud": {"stamp": "bud_round", "scale": 1.45},
    },
    "daisy": {
        "stem_len": 90, "stem_w": [3.6, 2.2], "lean_deg": 8, "s_curve": 0.15, "base": "foliage_tuft",
        "base_scale": 0.9,
        "leaves": [{"stamp": "leaf_spoon", "at": 0.15, "side": -1, "angle": 62, "scale": 0.95},
                   {"stamp": "leaf_spoon", "at": 0.36, "side": 1, "angle": 55, "scale": 0.85},
                   {"stamp": "leaf_spoon", "at": 0.08, "side": 1, "angle": 72, "scale": 0.9}],
        "head": {"kind": "radial", "petal": "petal_round", "count": 13, "radius": 3.0, "petal_scale": 0.82,
                 "squash": 0.84, "centre": "daisy_center", "centre_scale": 0.92},
        "bud": {"stamp": "bud_round", "scale": 1.55},
    },
    "cup": {
        "stem_len": 95, "stem_w": [3.6, 2.2], "lean_deg": 9, "s_curve": 0.18, "base": "foliage_tuft",
        "base_scale": 0.95,
        "leaves": [{"stamp": "leaf_lobed", "at": 0.22, "side": -1, "angle": 52, "scale": 0.9, "petiole": 10},
                   {"stamp": "leaf_lobed", "at": 0.42, "side": 1, "angle": 48, "scale": 0.75, "petiole": 8},
                   {"stamp": "leaf_lobed", "at": 0.08, "side": 1, "angle": 70, "scale": 0.85, "petiole": 8}],
        "head": {"kind": "cup", "petal": "petal_cup", "petal_scale": 1.0,
                 "petals": [[-24, 0.92, 0], [24, 0.92, 0], [-46, 1.0, 1], [46, 1.0, 1], [0, 1.05, 1]]},
        "bud": {"stamp": "bud_round", "scale": 1.5},
    },
    "cluster": {
        "stem_len": 75, "stem_w": [3.2, 2.0], "lean_deg": 10, "s_curve": 0.2, "base": "foliage_tuft",
        "base_scale": 0.85,
        "leaves": [{"stamp": "leaf_lance", "at": 0.18, "side": 1, "angle": 55, "scale": 1.0},
                   {"stamp": "leaf_lance", "at": 0.4, "side": -1, "angle": 50, "scale": 0.9},
                   {"stamp": "leaf_lance", "at": 0.06, "side": -1, "angle": 70, "scale": 0.9}],
        "head": {"kind": "cluster", "stamp": "forget_bloom", "count": 8, "curl_r": 8.5, "bloom_scale": [0.66, 0.84],
                 "buds": 2, "bud_stamp": "bud_round", "bud_scale": 0.42},
        "bud": {"stamp": "bud_round", "scale": 1.25},
    },
    "bell": {
        "stem_len": 105, "stem_w": [3.4, 2.0], "lean_deg": 4, "s_curve": 0.0, "arch": 0.42, "base": "foliage_tuft",
        "base_scale": 0.8,
        "rosette": [{"stamp": "leaf_strap", "angle": -24, "scale": 0.9}, {"stamp": "leaf_strap", "angle": 22, "scale": 0.85},
                    {"stamp": "leaf_strap", "angle": -8, "scale": 0.7}],
        "head": {"kind": "bells", "stamp": "bell", "count": [4, 6], "from": 0.52, "bell_scale": [1.0, 1.2]},
        "bud": {"stamp": "bud_long", "scale": 1.25},
    },
    "primrose": {
        "stem_len": 45, "stem_w": [2.8, 2.0], "lean_deg": 14, "s_curve": 0.1, "base": "foliage_tuft",
        "base_scale": 0.75,
        "rosette": [{"stamp": "leaf_rosette", "angle": -62, "scale": 0.95}, {"stamp": "leaf_rosette", "angle": 64, "scale": 0.95},
                    {"stamp": "leaf_rosette", "angle": -28, "scale": 0.8}, {"stamp": "leaf_rosette", "angle": 30, "scale": 0.8},
                    {"stamp": "leaf_rosette", "angle": 2, "scale": 0.7}],
        "head": {"kind": "primrose", "petal": "petal_heart", "flowers": [3, 5], "petal_scale": 0.9, "spread_deg": 34,
                 "pedicel": [0.62, 1.0], "squash": 0.9, "centre": "eye_center", "centre_scale": 1.0},
        "bud": {"stamp": "bud_round", "scale": 1.35},
    },
    "puff": {
        "stem_len": 120, "stem_w": [3.0, 1.8], "lean_deg": 7, "s_curve": 0.16, "base": "foliage_tuft",
        "base_scale": 0.8,
        "rosette": [{"stamp": "leaf_toothed", "angle": -68, "scale": 0.9}, {"stamp": "leaf_toothed", "angle": 70, "scale": 0.85},
                    {"stamp": "leaf_toothed", "angle": -40, "scale": 0.7}, {"stamp": "leaf_toothed", "angle": 44, "scale": 0.72}],
        "head": {"kind": "puff", "stamp": "seed_puff", "scale": 0.96},
        "bud": {"stamp": "bud_long", "scale": 1.3},
    },
    "lily": {
        "stem_len": 110, "stem_w": [3.8, 2.4], "lean_deg": 6, "s_curve": 0.12, "base": "foliage_tuft",
        "base_scale": 0.95,
        "rosette": [{"stamp": "leaf_broad", "angle": -58, "scale": 0.95}, {"stamp": "leaf_broad", "angle": 60, "scale": 0.9},
                    {"stamp": "leaf_broad", "angle": -18, "scale": 0.8}],
        "head": {"kind": "lily", "petal": "petal_lily", "count": 6, "petal_scale": 0.95, "squash": 0.62, "tilt_deg": -8,
                 "centre": "stamens", "centre_scale": 1.0},
        "bud": {"stamp": "bud_long", "scale": 1.35},
    },
}

# Bed-wide size multipliers on top of the §6.3 sizes: at the beds' depth (0.74-0.91) the §6.3
# sizes read as sprinkles from arm's length; these keep the drawn proportions and give the beds
# the lush mass the Director asked for (R2 directive 6) [J].
BED_SCALE = {"stem": 1.25, "head": 1.34, "leaf": 1.35, "base": 1.7, "stem_w": 1.55}

GROWTH = {
    "doc": "Art Bible §6.2: sprout stem 30->60 % with 2 cotyledons; bud: all leaves, stem 85->100 %, bud 0.6->1.0.",
    "sprout_stem": [0.3, 0.6], "bud_stem": [0.85, 1.0], "bud_swell": [0.6, 1.0], "cotyledon_scale": 1.0,
    "seed_stamp": "soil_mound", "seed_scale": 0.8, "cotyledon": "cotyledon",
    "cushion": "bed_shadow", "cushion_scale": 0.9, "cushion_dy": 3.0,
    "jitter": {"scale": 0.1, "rot_deg": 5, "lightness": 1.0, "doc": "per stem ±10 % scale, ±5° rotation, L*/hue jitter"},
}


def main() -> int:
    svg = Svg(ATLAS_W, 16)
    parts = [(sid, b(svg)) for sid, b in STAMPS]
    for sid, part in parts:
        if sid not in UNPADDED:
            part.margin = MARGIN_OVERRIDE.get(sid, STAMP_MARGIN)
    stamps = write_atlas(svg, parts, SCALE, ATLAS_W, PAD)
    OUT_SVG.write_text(svg.to_string())
    doc = {"schema": 1, "doc": __doc__.strip().splitlines()[0], "atlas": "res://art/flora/flora_atlas.svg",
           "size": [ATLAS_W, svg.h], "scale": SCALE, "stamps": stamps, "forms": FORMS, "growth": GROWTH, "bed_scale": BED_SCALE}
    OUT_JSON.write_text(json.dumps(doc, indent="\t") + "\n")
    print(f"wrote {OUT_SVG.relative_to(ROOT)} ({ATLAS_W}x{svg.h}, {len(stamps)} stamps)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
