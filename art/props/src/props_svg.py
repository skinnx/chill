#!/usr/bin/env python3
"""Generates art/props/props_atlas.svg (tone masks) + art/props/props_atlas.json (regions, layout).

Art Bible §2.4 (positions), §3.8 (materials), §4.9 (prop_tone contract), §6.4-6.5 (designs).
Run from the repo root:  python3 -I art/props/src/props_svg.py
Every part is authored in its own local frame (0..w, 0..h) at design px (svg/scale = 1.0) and packed
into one atlas so all props share one texture + one material (batching, §4.9). Parts are padded
by PAD px so mip levels up to ~3 never bleed between cells.

Layout fields per part (read by scripts/world/props_layer.gd):
  prop      spots.json prop id the part belongs to ("" = art dressing at an absolute position)
  centre    part centre: relative to the prop centre (prop parts) or absolute design px (dressing)
  sort_y    y-sort origin, same frame as centre: where the part sorts against creatures and beds
  material  palettes.json materials id (lit / shade / detail)
  shadow    optional contact shadow [half_w, half_h, alpha_mul, foot_y] (foot_y in the centre's frame)
  sway      optional [amp_px, k, pivot_uv_y]: shear sway above the pivot (k/600 Hz)
  emission  optional detail emission x g_lights (glow mushrooms 0.55)
  rim       0 to skip the rim read for small pieces (< 40 px, §4.9 step 3)
  ground    0..1 ground-cover shade (moss, clover, ferns take the meadow's shade, never stickers)
"""
from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from svgkit import DETAIL, LINE, LIT, SHADE, Part, Svg, blob, blob_pts, f, smooth_path  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
OUT_SVG = ROOT / "art/props/props_atlas.svg"
OUT_JSON = ROOT / "art/props/props_atlas.json"
OUT_FG_SVG = ROOT / "art/props/fg_atlas.svg"
OUT_FG_JSON = ROOT / "art/props/fg_atlas.json"
FG_PAD = 24  # mip LOD 2 blur (Art Bible §4.16) reads ~16 px around each texel
ATLAS_W = 1024
PAD = 10
LINE_W = 6.0  # 2 dp colour line on touchable props (§4.9 outline policy)


# --------------------------------------------------------------------------------------------- #
# Parts
# --------------------------------------------------------------------------------------------- #

def sun_stone(svg: Svg) -> Part:
    """FOCAL: broad, smooth, slightly tilted flat stone (stone_warm), lichen toward the back.

    Reads as a convex slab: a big lit top plane with a light rounded front edge, a mid-tone front
    face darkening to the ground, soft strata, lichen rosettes on the back half.
    """
    p = Part(svg, 264, 124)
    rng = random.Random(11)
    body = smooth_path([(10, 44), (9, 66), (18, 90), (42, 108), (92, 118), (150, 120), (206, 113), (240, 99),
                        (255, 76), (258, 50), (247, 28), (212, 13), (150, 6), (90, 7), (44, 14), (19, 27)])
    top = smooth_path([(13, 42), (34, 22), (86, 10), (150, 8), (210, 15), (244, 31), (251, 47), (232, 60),
                       (176, 67), (118, 68), (62, 64), (26, 54)])
    clip_body = svg.clip(body)
    clip_top = svg.clip(top)
    # Front face: mid tone under the edge, shade at the ground.
    p.path(body, svg.lin(0, 56, 0, 120, [(0, LIT), (0.12, LIT), (0.55, SHADE, 0.55), (1, SHADE)]))
    p.path(body, svg.lin(0, 56, 0, 120, [(0, SHADE, 0.0), (0.35, SHADE, 0.45), (1, SHADE, 0.2)]))
    for y, a in ((86, 0.22), (102, 0.2)):
        p.path(smooth_path([(14, y + 2), (80, y + 7), (150, y + 6), (226, y - 2), (258, y - 8)], closed=False),
               "none", a, svg.blur(2.6), SHADE, 6, clip_body)
    p.path(smooth_path([(20, 112), (90, 124), (180, 124), (240, 106)], closed=False), "none", 0.5,
           svg.blur(4), LINE, 10, clip_body)
    # Top plane: fully lit; a faint shallow dip in the middle keeps it from reading as a disc.
    p.path(top, LIT)
    p.ellipse(132, 40, 70, 13, SHADE, 0.12, svg.blur(8), clip_top)
    # Rounded front edge: a soft light bevel along the lip (convex edges catch the light).
    p.path(smooth_path([(18, 50), (60, 63), (118, 67), (176, 66), (230, 58), (250, 46)], closed=False),
           "none", 0.55, svg.blur(3.0), DETAIL, 7, clip_body)
    # Lichen rosettes and speckles toward the back of the top plane.
    for _ in range(9):
        cx, cy = rng.uniform(40, 225), rng.uniform(16, 36)
        r = rng.uniform(3.5, 7.5)
        p.path(blob(cx, cy, r, r * 0.6, 9, 0.18, rng), DETAIL, rng.uniform(0.55, 0.85), clip=clip_top)
        p.ellipse(cx, cy, r * 0.4, r * 0.25, SHADE, 0.25, clip=clip_top)
    p.speckles(rng, (24, 12, 240, 40), 70, (0.8, 2.0), DETAIL, (0.4, 0.9), clip_top)
    p.speckles(rng, (20, 72, 248, 112), 46, (0.7, 1.6), SHADE, (0.25, 0.55), clip_body)
    p.speckles(rng, (30, 70, 240, 100), 20, (0.8, 1.8), DETAIL, (0.25, 0.5), clip_body)
    return p


def stone_moss(svg: Svg) -> Part:
    """Soft moss tucked at the sun stone's base (moss)."""
    p = Part(svg, 284, 46)
    rng = random.Random(12)
    clumps = [(26, 30, 30, 15), (58, 34, 22, 11), (226, 33, 26, 12), (258, 29, 24, 14), (140, 38, 18, 7)]
    for cx, cy, rx, ry in clumps:
        d = blob(cx, cy, rx, ry, 14, 0.12, rng, squash_bottom=0.35)
        p.path(d, svg.lin(0, cy - ry, 0, cy + ry * 0.7, [(0, LIT), (1, SHADE)]))
        clip = svg.clip(d)
        p.speckles(rng, (cx - rx, cy - ry, cx + rx, cy), int(rx * 0.9), (0.8, 1.8), DETAIL, (0.4, 0.9), clip)
        p.speckles(rng, (cx - rx, cy - 2, cx + rx, cy + ry), int(rx * 0.5), (0.8, 1.6), SHADE, (0.3, 0.6), clip)
    return p


def glow_mushrooms(svg: Svg) -> Part:
    """Three glow mushrooms at the sun stone's left foot (glow_mushroom, night emission 0.55)."""
    p = Part(svg, 72, 50)
    rng = random.Random(13)
    for cx, base, h, rx in ((16, 46, 22, 10), (37, 47, 32, 14), (57, 46, 17, 8)):
        cap_y = base - h
        p.path(smooth_path([(cx - rx * 0.28, base), (cx - rx * 0.22, cap_y + 4), (cx + rx * 0.2, cap_y + 4),
                            (cx + rx * 0.3, base)]), svg.lin(cx - 4, 0, cx + 4, 0, [(0, LIT), (1, SHADE)]))
        cap = smooth_path([(cx - rx, cap_y + 4), (cx - rx * 0.8, cap_y - rx * 0.45), (cx, cap_y - rx * 0.72),
                           (cx + rx * 0.8, cap_y - rx * 0.45), (cx + rx, cap_y + 4), (cx, cap_y + 6)])
        p.path(cap, svg.lin(0, cap_y - rx * 0.7, 0, cap_y + 6, [(0, LIT), (0.7, LIT), (1, SHADE)]))
        clip = svg.clip(cap)
        p.speckles(rng, (cx - rx * 0.8, cap_y - rx * 0.6, cx + rx * 0.8, cap_y + 2), 6, (1.0, 2.2), DETAIL,
                   (0.7, 1.0), clip)
    return p


def basket(svg: Svg) -> Part:
    """Woven wicker basket with a cloth liner (wicker; detail = pale weave highlight)."""
    p = Part(svg, 140, 116)
    rng = random.Random(14)
    body = smooth_path([(12, 44), (16, 74), (28, 100), (52, 112), (88, 112), (112, 100), (124, 74), (128, 44),
                        (70, 56)])
    handle = smooth_path([(20, 46), (28, 16), (70, 5), (112, 16), (120, 46)], closed=False)
    clip_body = svg.clip(body)
    # Handle behind the rim: braided band.
    p.path(handle, "none", 1.0, stroke=LINE, sw=10 + LINE_W)
    p.path(handle, "none", 1.0, stroke=LIT, sw=10)
    p.path(handle, "none", 0.6, stroke=DETAIL, sw=3, extra=' stroke-dasharray="4 6"')
    # Dark interior opening + the cloth liner peeking over the back rim.
    p.ellipse(70, 44, 56, 14, LINE)
    p.path(smooth_path([(22, 42), (40, 33), (70, 30), (102, 33), (118, 42), (90, 40), (70, 41), (48, 40)]),
           DETAIL, 0.9)
    # Body with weave.
    p.path(body, svg.lin(0, 44, 0, 112, [(0, LIT), (0.5, LIT), (1, SHADE)]), stroke=LINE, sw=LINE_W)
    p.path(body, svg.lin(0, 44, 0, 112, [(0, LIT), (0.5, LIT), (1, SHADE)]))
    inner = []
    for row, y in enumerate(range(56, 112, 11)):
        off = 0 if row % 2 == 0 else 7
        for x in range(4 + off, 138, 14):
            inner.append(f'<ellipse cx="{x}" cy="{y}" rx="6.2" ry="4.2" fill="{DETAIL}" opacity="0.55"/>')
            inner.append(f'<ellipse cx="{x}" cy="{y + 2.6}" rx="5.8" ry="2.2" fill="{SHADE}" opacity="0.45"/>')
    p.group(inner, clip=clip_body)
    p.path(smooth_path([(16, 60), (70, 70), (124, 60)], closed=False), "none", 0.35, svg.blur(3), SHADE, 8,
           clip_body)
    # Front rim: braided torus band.
    rim = smooth_path([(10, 44), (30, 54), (70, 60), (110, 54), (130, 44), (110, 50), (70, 54), (30, 50)])
    p.path(rim, LIT, stroke=LINE, sw=LINE_W)
    p.path(rim, LIT)
    p.path(smooth_path([(14, 46), (40, 54), (70, 57), (100, 54), (126, 46)], closed=False), "none", 0.7,
           stroke=DETAIL, sw=2.4, extra=' stroke-dasharray="3 5"')
    p.speckles(rng, (20, 64, 120, 106), 30, (0.6, 1.3), SHADE, (0.3, 0.5), clip_body)
    return p


def mailbox_post(svg: Svg) -> Part:
    p = Part(svg, 26, 84)
    rng = random.Random(15)
    d = smooth_path([(6, 2), (20, 2), (21, 70), (25, 82), (13, 84), (1, 82), (5, 70)])
    p.path(d, svg.lin(4, 0, 22, 0, [(0, LIT), (0.55, LIT), (1, SHADE)]))
    clip = svg.clip(d)
    for x in (9, 15):
        p.path(smooth_path([(x, 4), (x + rng.uniform(-1, 1), 40), (x + rng.uniform(-1, 1), 80)], closed=False),
               "none", 0.5, stroke=DETAIL, sw=1.4, clip=clip)
    p.path(smooth_path([(3, 78), (13, 84), (23, 78)], closed=False), "none", 0.45, svg.blur(2), LINE, 6, clip)
    return p


def mailbox_body(svg: Svg) -> Part:
    """Little rounded mailbox (wood_painted) with a slot and a leaf emblem (detail)."""
    p = Part(svg, 76, 54)
    d = smooth_path([(6, 8), (38, 4), (70, 8), (72, 30), (70, 48), (38, 51), (6, 48), (4, 30)])
    p.path(d, svg.lin(0, 4, 0, 51, [(0, LIT), (0.55, LIT), (1, SHADE)]), stroke=LINE, sw=LINE_W)
    p.path(d, svg.lin(0, 4, 0, 51, [(0, LIT), (0.55, LIT), (1, SHADE)]))
    clip = svg.clip(d)
    p.path(smooth_path([(4, 12), (4, 46), (12, 50)], closed=False), "none", 0.35, svg.blur(2.5), SHADE, 8, clip)
    p.path(smooth_path([(72, 12), (72, 46), (64, 50)], closed=False), "none", 0.45, svg.blur(2.5), SHADE, 8, clip)
    # Slot.
    p.path(smooth_path([(24, 17), (52, 17)], closed=False), "none", 1.0, stroke=LINE, sw=4)
    # Leaf emblem.
    leaf = smooth_path([(28, 38), (34, 28), (44, 25), (48, 31), (42, 40), (31, 41)])
    p.path(leaf, DETAIL)
    p.path(smooth_path([(30, 40), (38, 33), (45, 28)], closed=False), "none", 0.6, stroke=SHADE, sw=1.6)
    return p


def mailbox_roof(svg: Svg) -> Part:
    """Arched slate roof cap with scalloped shingles (roof_slate)."""
    p = Part(svg, 86, 30)
    d = smooth_path([(4, 26), (10, 10), (43, 3), (76, 10), (82, 26), (43, 22)])
    p.path(d, svg.lin(0, 3, 0, 26, [(0, LIT), (0.6, LIT), (1, SHADE)]), stroke=LINE, sw=LINE_W)
    p.path(d, svg.lin(0, 3, 0, 26, [(0, LIT), (0.6, LIT), (1, SHADE)]))
    clip = svg.clip(d)
    inner = []
    for row, y in enumerate((12, 19)):
        off = 0 if row == 0 else 6
        for x in range(4 + off, 86, 12):
            inner.append(f'<path d="M{x - 6},{y} Q{x},{y + 7} {x + 6},{y}" fill="none" stroke="{DETAIL}" '
                         f'stroke-width="1.8" opacity="0.7" stroke-linecap="round"/>')
    p.group(inner, clip=clip)
    return p


def mailbox_flag(svg: Svg) -> Part:
    """Flag on a stick (toadstool_cap); pivot at the stick's foot (UV 0.5, 0.95)."""
    p = Part(svg, 24, 34)
    p.path(smooth_path([(10, 32), (11, 6), (13, 6), (14, 32)]), SHADE, stroke=LINE, sw=3)
    flag = smooth_path([(12, 4), (22, 5), (22, 15), (12, 15)])
    p.path(flag, svg.lin(0, 4, 0, 15, [(0, LIT), (1, SHADE)]), stroke=LINE, sw=4)
    p.path(flag, svg.lin(0, 4, 0, 15, [(0, LIT), (1, SHADE)]))
    p.ellipse(17, 9, 2.2, 2, DETAIL, 0.9)
    return p


# Stump geometry shared by its parts (local 210x180; prop centre = (105, 90)).
STUMP_SIL = [(40, 30), (36, 70), (33, 120), (30, 150), (14, 166), (6, 174), (28, 178), (52, 170), (80, 179),
             (130, 179), (158, 170), (184, 177), (204, 171), (188, 160), (178, 146), (176, 110), (174, 66),
             (172, 34), (160, 18), (130, 9), (100, 7), (66, 11), (48, 20)]
STUMP_NOOK = [(64, 44), (70, 62), (82, 78), (106, 84), (130, 78), (142, 60), (148, 42), (128, 50), (104, 52),
              (82, 50)]


def stump_back(svg: Svg) -> Part:
    p = Part(svg, 210, 180)
    rng = random.Random(16)
    sil = smooth_path(STUMP_SIL)
    clip = svg.clip(sil)
    p.path(sil, svg.lin(30, 0, 184, 0, [(0, SHADE), (0.18, LIT), (0.5, LIT), (1, SHADE)]))
    p.path(sil, svg.lin(0, 100, 0, 180, [(0, LIT, 0.0), (1, SHADE, 0.6)]))
    # Bark grooves with lit ridges.
    for i in range(9):
        x = 46 + i * 15 + rng.uniform(-3, 3)
        pts = [(x + rng.uniform(-2, 2), 30 + rng.uniform(0, 12))]
        for y in range(60, 181, 30):
            pts.append((x + (x - 105) * 0.08 * (y / 180) + rng.uniform(-3, 3), y))
        p.path(smooth_path(pts, closed=False), "none", 0.55, svg.blur(0.8), SHADE, 3.2, clip)
        p.path(smooth_path([(a + 3, b) for a, b in pts], closed=False), "none", 0.45, svg.blur(0.6), DETAIL, 1.6,
               clip)
    # The nook: dark mouth with a dim inner wall.
    nook = smooth_path(STUMP_NOOK)
    p.path(nook, LINE)
    p.path(smooth_path([(76, 54), (104, 58), (134, 54), (126, 70), (104, 74), (84, 70)]), SHADE, 0.35,
           svg.blur(4), clip=svg.clip(nook))
    # Root shadows.
    p.path(smooth_path([(20, 172), (60, 178), (104, 180), (150, 178), (196, 172)], closed=False), "none", 0.5,
           svg.blur(3), LINE, 7, clip)
    return p


def stump_top(svg: Svg) -> Part:
    """Cut top with growth rings, broken at the front where the nook dips (wood_cut)."""
    p = Part(svg, 150, 52)
    rng = random.Random(17)
    # Local frame: the stump top spans stump x 34..184, y 4..56 -> part x = stump x - 34, y = stump y - 4.
    rim = [(6, 26), (14, 14), (32, 6), (66, 3), (96, 5), (126, 14), (138, 28), (114, 38), (96, 46), (70, 48),
           (48, 46), (30, 40)]
    d = smooth_path(rim)
    p.path(d, svg.rad(72, 22, 80, [(0, LIT), (0.7, LIT), (1, SHADE)]))
    clip = svg.clip(d)
    for r in (12, 22, 32, 42, 52):
        p.ellipse(72, 26, r * 1.25, r * 0.42, "none", 1.0, clip=clip)
        p.items[-1] = p.items[-1].replace('fill="none"', f'fill="none" stroke="{DETAIL}" stroke-width="1.8" '
                                          f'opacity="{f(rng.uniform(0.5, 0.8))}"')
    # Shade where the top breaks into the nook.
    p.path(smooth_path([(30, 40), (70, 50), (114, 38)], closed=False), "none", 0.6, svg.blur(3), SHADE, 8, clip)
    return p


def stump_front(svg: Svg) -> Part:
    """Front of the trunk below the nook lip: drawn IN FRONT of a mossling napping in the nook."""
    p = Part(svg, 210, 180)
    rng = random.Random(16)
    sil = smooth_path(STUMP_SIL)
    # Everything below the nook lip, as an overlay identical to stump_back (seamless).
    lip = smooth_path([(0, 180), (0, 84), (40, 84), (62, 72), (82, 82), (106, 88), (130, 82), (146, 66),
                       (174, 80), (210, 84), (210, 180)])
    clip = svg.clip(lip)
    inner_clip = svg.clip(sil)
    g = [f'<path d="{sil}" fill="{svg.lin(30, 0, 184, 0, [(0, SHADE), (0.18, LIT), (0.5, LIT), (1, SHADE)])}"/>',
         f'<path d="{sil}" fill="{svg.lin(0, 100, 0, 180, [(0, LIT, 0.0), (1, SHADE, 0.6)])}"/>']
    p.group(g, clip=clip)
    for i in range(9):
        x = 46 + i * 15 + rng.uniform(-3, 3)
        pts = [(x + rng.uniform(-2, 2), 30 + rng.uniform(0, 12))]
        for y in range(60, 181, 30):
            pts.append((x + (x - 105) * 0.08 * (y / 180) + rng.uniform(-3, 3), y))
        groove = smooth_path(pts, closed=False)
        ridge = smooth_path([(a + 3, b) for a, b in pts], closed=False)
        p.group([f'<path d="{groove}" fill="none" stroke="{SHADE}" stroke-width="3.2" opacity="0.55" '
                 f'filter="{svg.blur(0.8)}"/>',
                 f'<path d="{ridge}" fill="none" stroke="{DETAIL}" stroke-width="1.6" opacity="0.45" '
                 f'filter="{svg.blur(0.6)}"/>'], clip=clip)
    # The lip itself catches light; a soft shadow under it.
    p.path(smooth_path([(64, 74), (82, 82), (106, 87), (130, 81), (144, 66)], closed=False), "none", 0.6,
           svg.blur(1.2), DETAIL, 3, inner_clip)
    p.path(smooth_path([(66, 84), (106, 96), (142, 80)], closed=False), "none", 0.4, svg.blur(3), SHADE, 8,
           inner_clip)
    p.group([f'<path d="{smooth_path([(20, 172), (60, 178), (104, 180), (150, 178), (196, 172)], closed=False)}" '
             f'fill="none" stroke="{LINE}" stroke-width="7" opacity="0.5" filter="{svg.blur(3)}"/>'], clip=clip)
    return p


def stump_moss(svg: Svg) -> Part:
    """Moss on the stump's rim and roots plus one fern on its right (moss)."""
    p = Part(svg, 270, 190)
    rng = random.Random(18)
    # Part frame = stump frame + (4, 6): part centre (135, 95) = stump centre (105, 90) + (26, -1).
    ox, oy = 4, 6
    for cx, cy, rx, ry in ((54, 20, 20, 9), (40, 34, 10, 9), (164, 24, 14, 7), (16, 168, 16, 8), (58, 172, 14, 6),
                           (186, 168, 18, 8)):
        d = blob(cx + ox, cy + oy, rx, ry, 12, 0.14, rng, squash_bottom=0.3)
        p.path(d, svg.lin(0, cy + oy - ry, 0, cy + oy + ry, [(0, LIT), (1, SHADE)]))
        p.speckles(rng, (cx + ox - rx, cy + oy - ry, cx + ox + rx, cy + oy), int(rx * 0.8), (0.7, 1.5), DETAIL,
                   (0.4, 0.9), svg.clip(d))
    # Fern on the right side: three arching fronds with rounded pinnae.
    for k, (ang, length) in enumerate(((-1.25, 70), (-0.85, 82), (-0.45, 60))):
        bx, by = 178 + ox, 150 + oy
        pts = []
        for i in range(9):
            t = i / 8
            a = ang + t * 0.9
            pts.append((bx + math.cos(a) * length * t * 0.95 + t * t * 10, by + math.sin(a) * length * t + t * t * 30))
        p.path(smooth_path(pts, closed=False), "none", 1.0, stroke=SHADE, sw=2.2)
        for i in range(1, 9):
            x, y = pts[i]
            s = 6.5 * (1.0 - i / 10)
            for side in (-1, 1):
                p.ellipse(x + side * s * 0.7, y - s * 0.5, s, s * 0.45, LIT if side < 0 else SHADE, 1.0,
                          rot=side * 35 + k * 8)
            p.ellipse(x, y - s * 0.6, s * 0.4, s * 0.2, DETAIL, 0.6)
    return p


def spring_rock(svg: Svg) -> Part:
    """Mossy cool boulder; the brook springs from a shadowed cleft at its lower left (stone_cool,
    detail = moss). Lit from above-left, a soft core shadow on the right, wet darker base."""
    p = Part(svg, 180, 120)
    rng = random.Random(19)
    d = smooth_path([(10, 84), (12, 58), (28, 30), (60, 12), (104, 8), (142, 18), (166, 42), (174, 72),
                     (168, 100), (140, 114), (90, 118), (40, 114), (16, 104)])
    clip = svg.clip(d)
    p.path(d, svg.rad(78, 36, 130, [(0, LIT), (0.5, LIT), (1, SHADE)], fx=64, fy=26))
    # Core shadow down the right flank, reflected light at the very edge.
    p.path(smooth_path([(150, 30), (160, 62), (152, 96), (130, 112)], closed=False), "none", 0.45, svg.blur(6),
           SHADE, 22, clip)
    # Wet base where the water meets the stone.
    p.path(smooth_path([(14, 100), (60, 114), (120, 116), (168, 100)], closed=False), "none", 0.55,
           svg.blur(4), LINE, 12, clip)
    # The cleft: a soft dark recess low on the left, with two wet glints at its lip.
    p.path(blob(30, 88, 16, 12, 10, 0.12, rng), LINE, 0.75, svg.blur(3), clip=clip)
    p.path(smooth_path([(20, 78), (30, 74), (42, 80)], closed=False), "none", 0.85, stroke=LIT, sw=2.2, clip=clip)
    p.path(smooth_path([(18, 96), (28, 101)], closed=False), "none", 0.7, stroke=LIT, sw=1.6, clip=clip)
    # Moss cap.
    cap = smooth_path([(30, 34), (60, 14), (104, 10), (142, 20), (160, 38), (130, 34), (110, 42), (84, 36),
                       (56, 44), (40, 42)])
    p.path(cap, svg.lin(0, 10, 0, 44, [(0, DETAIL), (1, DETAIL, 0.75)]))
    p.speckles(rng, (36, 14, 156, 40), 40, (0.8, 2.0), LIT, (0.25, 0.55), svg.clip(cap))
    p.speckles(rng, (40, 50, 170, 110), 50, (0.7, 1.7), SHADE, (0.25, 0.5), clip)
    p.speckles(rng, (30, 46, 120, 90), 16, (1.0, 2.2), LIT, (0.3, 0.6), clip)
    return p


def reeds(svg: Svg) -> Part:
    """Reeds at the spring rock: tapering curved blades (willow_leaf), sway above the root."""
    p = Part(svg, 120, 110)
    rng = random.Random(20)
    for i in range(11):
        bx = 10 + i * 9.5 + rng.uniform(-3, 3)
        h = rng.uniform(55, 100)
        lean = rng.uniform(-16, 20)
        tip = (bx + lean, 106 - h)
        mid = (bx + lean * 0.35, 106 - h * 0.55)
        w = rng.uniform(3.2, 4.6)
        left = smooth_path([(bx - w, 106), (mid[0] - w * 0.6, mid[1]), tip, (mid[0] + w * 0.6, mid[1]),
                            (bx + w, 106)])
        p.path(left, svg.lin(bx - w, 0, bx + w, 0, [(0, LIT), (1, SHADE)]))
        p.path(smooth_path([(bx - w * 0.3, 104), (mid[0] - w * 0.2, mid[1]), tip], closed=False), "none", 0.5,
               stroke=DETAIL, sw=1.0)
    return p


def fern_clump(svg: Svg) -> Part:
    """Fern clump framing the fern gap at the left edge (moss), five arching fronds."""
    p = Part(svg, 150, 132)
    rng = random.Random(21)
    for k, (ang, length, bend) in enumerate(((-2.0, 70, -0.5), (-1.55, 96, 0.3), (-1.05, 112, 0.75),
                                              (-0.6, 98, 0.9), (-0.25, 72, 0.8))):
        bx, by = 34 + k * 6, 128
        pts = []
        for i in range(11):
            t = i / 10
            a = ang + t * bend
            pts.append((bx + math.cos(a) * length * t, by + math.sin(a) * length * t + t * t * 26))
        p.path(smooth_path(pts, closed=False), "none", 1.0, stroke=SHADE, sw=2.6)
        for i in range(1, 11):
            x, y = pts[i]
            nx, ny = pts[min(i + 1, 10)]
            ang_d = math.degrees(math.atan2(ny - y, nx - x))
            s = 9.5 * (1.0 - i / 12) + 1.5
            for side in (-1, 1):
                p.ellipse(x, y, s, s * 0.42, LIT if side < 0 else SHADE, 1.0, rot=ang_d + side * 62)
            if i % 2 == 0:
                p.ellipse(x, y, s * 0.45, s * 0.2, DETAIL, 0.7, rot=ang_d - 60)
    _ = rng
    return p


def clover_patch(svg: Svg, seed: int, n: int) -> Part:
    """A patch of trifoliate clover leaves with pale chevrons (moss)."""
    p = Part(svg, 70, 38)
    rng = random.Random(seed)
    for _ in range(n):
        cx, cy = rng.uniform(14, 56), rng.uniform(14, 28)
        s = rng.uniform(5.0, 7.0)
        rot = rng.uniform(0, math.tau)
        for j in range(3):
            a = rot + j * math.tau / 3
            lx, ly = cx + math.cos(a) * s * 0.9, cy + math.sin(a) * s * 0.55
            p.ellipse(lx, ly, s, s * 0.78, svg.lin(lx, ly - s, lx, ly + s, [(0, LIT), (1, SHADE)]), 1.0,
                      rot=math.degrees(a))
            p.ellipse(lx, ly, s * 0.45, s * 0.18, DETAIL, 0.75, rot=math.degrees(a))
    return p


def moss_mound(svg: Svg) -> Part:
    """The moss cushion at moss_cushion (moss): a soft rounded mound."""
    p = Part(svg, 100, 46)
    rng = random.Random(22)
    d = smooth_path([(4, 40), (12, 24), (30, 12), (52, 8), (74, 12), (90, 24), (96, 40), (50, 44)])
    p.path(d, svg.rad(48, 16, 56, [(0, LIT), (0.6, LIT), (1, SHADE)], fx=44, fy=12))
    clip = svg.clip(d)
    p.speckles(rng, (8, 8, 92, 30), 60, (0.8, 1.8), DETAIL, (0.4, 0.9), clip)
    p.speckles(rng, (8, 20, 92, 44), 40, (0.8, 1.6), SHADE, (0.3, 0.6), clip)
    return p


def pebble(svg: Svg, seed: int, w: int, h: int) -> Part:
    p = Part(svg, w, h)
    rng = random.Random(seed)
    d = blob(w / 2, h / 2 + 1, w / 2 - 2, h / 2 - 2, 10, 0.08, rng, squash_bottom=0.15)
    p.path(d, svg.rad(w * 0.42, h * 0.3, w * 0.7, [(0, LIT), (0.55, LIT), (1, SHADE)]))
    p.speckles(rng, (3, 2, w - 3, h * 0.6), 4, (0.7, 1.4), DETAIL, (0.5, 0.9), svg.clip(d))
    return p


def moon_rock(svg: Svg) -> Part:
    """Pale mossy moon rock on the crest (stone_cool, detail = moss)."""
    p = Part(svg, 132, 66)
    rng = random.Random(23)
    d = smooth_path([(6, 56), (10, 36), (30, 16), (64, 8), (100, 12), (122, 28), (128, 50), (112, 62), (64, 64),
                     (24, 63)])
    clip = svg.clip(d)
    p.path(d, svg.rad(58, 22, 90, [(0, LIT), (0.6, LIT), (1, SHADE)], fx=52, fy=16))
    p.path(smooth_path([(10, 58), (64, 66), (120, 56)], closed=False), "none", 0.5, svg.blur(3), LINE, 8, clip)
    cap = smooth_path([(34, 20), (64, 10), (98, 14), (114, 26), (90, 24), (70, 30), (48, 28)])
    p.path(cap, DETAIL, 0.85)
    p.speckles(rng, (14, 24, 124, 58), 30, (0.6, 1.4), SHADE, (0.25, 0.5), clip)
    return p


# Willow (design frame: willow centre (130, 576), 420x510 -> x -80..340, y 321..831).
def _leaf_mass(p: Part, svg: Svg, rng: random.Random, pts: list, cx: float, cy: float, r: float) -> None:
    """One soft leaf mass: lit from the top-left, speckled leaves on the lit half, shade below."""
    d = smooth_path(pts)
    p.path(d, svg.rad(cx - r * 0.3, cy - r * 0.45, r * 1.5, [(0, LIT), (0.5, LIT), (1, SHADE)],
                      fx=cx - r * 0.35, fy=cy - r * 0.5))
    clip = svg.clip(d)
    inner = []
    for _ in range(int(r * 0.9)):
        a = rng.uniform(math.pi * 1.05, math.pi * 1.95)
        rr = r * math.sqrt(rng.random()) * 0.95
        x, y = cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.86
        inner.append(f'<ellipse cx="{f(x)}" cy="{f(y)}" rx="{f(rng.uniform(2.2, 4.2))}" ry="{f(rng.uniform(0.9, 1.6))}" '
                     f'transform="rotate({f(rng.uniform(55, 95))} {f(x)} {f(y)})" fill="{DETAIL}" '
                     f'opacity="{f(rng.uniform(0.45, 0.9))}"/>')
    for _ in range(int(r * 0.5)):
        a = rng.uniform(0, math.pi)
        rr = r * math.sqrt(rng.random()) * 0.95
        x, y = cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.86
        inner.append(f'<ellipse cx="{f(x)}" cy="{f(y)}" rx="{f(rng.uniform(2.0, 3.6))}" ry="{f(rng.uniform(0.8, 1.4))}" '
                     f'transform="rotate({f(rng.uniform(60, 100))} {f(x)} {f(y)})" fill="{SHADE}" '
                     f'opacity="{f(rng.uniform(0.3, 0.6))}"/>')
    p.group(inner, clip=clip)


def willow_crown(svg: Svg) -> Part:
    """Weeping willow crown: a soft dome of leaf masses (willow_leaf) the curtains hang from."""
    p = Part(svg, 480, 270)
    rng = random.Random(24)
    # Part frame: design x = local x - 110, design y = local y + 300.
    masses = [(70, 175, 88), (400, 160, 72), (300, 105, 112), (170, 120, 108), (230, 80, 84), (20, 220, 58),
              (340, 208, 66), (210, 175, 96), (118, 200, 70), (275, 210, 60)]
    for i, (cx, cy, r) in enumerate(masses):
        pts = blob_pts(cx, cy, r, r * 0.84, 16, 0.07, rng)
        _leaf_mass(p, svg, rng, pts, cx, cy, r)
        if i + 1 < len(masses):
            nx, ny, nr = masses[i + 1]
            p.ellipse(nx, ny + nr * 0.25, nr * 1.02, nr * 0.9, SHADE, 0.3, svg.blur(9), svg.clip(smooth_path(pts)))
    return p


# Curtains in design px: (centre x, top y, bottom y, width).
CURTAINS = [(-70, 500, 772, 66), (-16, 488, 738, 60), (36, 505, 700, 50), (184, 494, 702, 54),
            (238, 484, 718, 62), (292, 490, 692, 54), (336, 505, 660, 42)]


def willow_curtains(svg: Svg) -> Part:
    """The willow's hanging leaf curtains (willow_leaf): each curtain is 3 overlapping drooping
    strands of different lengths that taper to rounded tips, textured with short hanging leaves;
    gaps between curtains show the trunk."""
    p = Part(svg, 480, 360)
    rng = random.Random(26)
    # Part frame: design x = local x - 120, design y = local y - 440.
    # The shadowed inside of the crown: the trunk's limbs vanish into dim foliage instead of sky.
    inner = smooth_path([(20, 40), (120, 18), (240, 14), (380, 22), (470, 50), (440, 120), (330, 170),
                         (240, 200), (150, 190), (60, 150), (14, 100)])
    p.path(inner, SHADE, 0.92, svg.blur(10))
    p.path(inner, svg.lin(0, 20, 0, 200, [(0, LINE, 0.35), (1, LINE, 0.0)]), 0.8, svg.blur(12))
    for dcx, dtop, dbot, w in CURTAINS:
        cx, top, bot = dcx + 120, dtop - 440, dbot - 440
        for j, (off, wk, lk) in enumerate(((-0.28, 0.55, rng.uniform(0.78, 0.9)), (0.3, 0.5, rng.uniform(0.84, 0.95)),
                                           (0.0, 0.62, 1.0))):
            sx = cx + off * w
            sw = w * wk
            sb = top + (bot - top) * lk
            h = sb - top
            lean = rng.uniform(-6, 6)
            pts = [(sx - sw * 0.42, top), (sx - sw * 0.5, top + h * 0.3), (sx - sw * 0.4 + lean * 0.5, top + h * 0.7),
                   (sx - sw * 0.2 + lean, sb - 10), (sx + lean, sb + 2), (sx + sw * 0.2 + lean, sb - 10),
                   (sx + sw * 0.4 + lean * 0.5, top + h * 0.7), (sx + sw * 0.5, top + h * 0.3), (sx + sw * 0.42, top)]
            d = smooth_path(pts)
            p.path(d, svg.lin(sx - sw * 0.5, 0, sx + sw * 0.5, 0, [(0, SHADE), (0.35, LIT), (0.65, LIT), (1, SHADE)]))
            clip = svg.clip(d)
            p.path(d, svg.lin(0, top, 0, sb, [(0, SHADE, 0.45), (0.3, LIT, 0.0), (0.8, SHADE, 0.0), (1, SHADE, 0.35)]),
                   clip=clip)
            inner = []
            for _ in range(int(sw * h / 70)):
                x = rng.uniform(sx - sw * 0.5, sx + sw * 0.5)
                y = rng.uniform(top + 6, sb)
                col = DETAIL if rng.random() < 0.4 else SHADE
                inner.append(f'<ellipse cx="{f(x)}" cy="{f(y)}" rx="{f(rng.uniform(1.1, 1.8))}" ry="{f(rng.uniform(3.5, 6.0))}" '
                             f'transform="rotate({f(rng.uniform(-14, 14))} {f(x)} {f(y)})" fill="{col}" '
                             f'opacity="{f(rng.uniform(0.35, 0.75) if col == DETAIL else rng.uniform(0.2, 0.45))}"/>')
            p.group(inner, clip=clip)
            if j == 2:
                p.ellipse(sx + lean, sb - 4, 2.8, 7.0, LIT, 0.9)
    return p


def willow_trunk(svg: Svg) -> Part:
    """Willow trunk with root flare and two limbs into the canopy (wood_bark, grooves in detail)."""
    p = Part(svg, 210, 330)
    rng = random.Random(25)
    # Part frame: design x = local x + 15, design y = local y + 505 (base at local 326 = design 831).
    d = smooth_path([(56, 326), (70, 300), (84, 250), (86, 190), (80, 140), (52, 96), (22, 40), (14, 6), (34, 4),
                     (54, 44), (90, 100), (108, 120), (130, 86), (158, 40), (176, 18), (190, 26), (168, 70),
                     (138, 140), (130, 200), (132, 260), (144, 304), (168, 326), (112, 330)])
    clip = svg.clip(d)
    p.path(d, svg.lin(70, 0, 144, 0, [(0, LIT), (0.45, LIT), (1, SHADE)]))
    for i in range(6):
        x = 88 + i * 8 + rng.uniform(-2, 2)
        pts = [(x + rng.uniform(-3, 3), y) for y in range(110, 331, 44)]
        p.path(smooth_path(pts, closed=False), "none", 0.55, svg.blur(0.8), SHADE, 3, clip)
        p.path(smooth_path([(a + 2.5, b) for a, b in pts], closed=False), "none", 0.4, svg.blur(0.6), DETAIL, 1.4,
               clip)
    p.path(smooth_path([(48, 322), (108, 334), (172, 322)], closed=False), "none", 0.55, svg.blur(3), LINE, 8, clip)
    return p


def chime_branch(svg: Svg) -> Part:
    """The low willow limb the wind chime hangs from (wood_bark, colour line: it is touchable)."""
    p = Part(svg, 286, 64)
    # Part frame: design x = local x + 112, design y = local y + 610.
    limb = [(4, 52), (60, 38), (120, 32), (180, 30), (230, 34), (270, 42), (282, 50)]
    p.path(smooth_path(limb, closed=False), "none", 1.0, stroke=LINE, sw=16 + LINE_W)
    p.path(smooth_path(limb, closed=False), "none", 1.0, stroke=LIT, sw=16)
    twig = [(200, 30), (214, 14), (230, 6)]
    p.path(smooth_path(twig, closed=False), "none", 1.0, stroke=LINE, sw=6 + LINE_W)
    p.path(smooth_path(twig, closed=False), "none", 1.0, stroke=LIT, sw=6)
    p.path(smooth_path([(8, 56), (60, 44), (120, 38), (180, 37), (230, 40), (276, 50)], closed=False), "none", 0.7,
           stroke=SHADE, sw=5)
    p.path(smooth_path([(10, 48), (60, 34), (120, 28), (180, 26), (230, 30)], closed=False), "none", 0.6,
           stroke=DETAIL, sw=2)
    return p


# Foreground frame (L5, Art Bible §2.3, §4.16): dark, blurred (mip LOD 2) corner pieces.
def fg_reeds(svg: Svg) -> Part:
    """Bottom-left reeds and grass leaning in from the frame edge (willow_leaf)."""
    p = Part(svg, 300, 240)
    rng = random.Random(51)
    for i in range(16):
        bx = rng.uniform(-10, 170)
        h = rng.uniform(110, 230) * (1.0 - bx / 400)
        lean = rng.uniform(10, 70)
        w = rng.uniform(7, 12)
        tip = (bx + lean, 240 - h)
        mid = (bx + lean * 0.35, 240 - h * 0.55)
        d = smooth_path([(bx - w, 242), (mid[0] - w * 0.55, mid[1]), tip, (mid[0] + w * 0.55, mid[1]), (bx + w, 242)])
        p.path(d, svg.lin(bx - w, 0, bx + w, 0, [(0, LIT), (1, SHADE)]))
    for _ in range(5):
        cx, cy = rng.uniform(150, 290), rng.uniform(205, 235)
        for k in range(5):
            a = -math.pi / 2 + (k - 2) * 0.38
            ln = rng.uniform(30, 55)
            tip = (cx + math.cos(a) * ln, cy + math.sin(a) * ln)
            p.path(smooth_path([(cx - 4, 242), (tip[0] - 2, tip[1] + 6), tip, (tip[0] + 2, tip[1] + 6), (cx + 4, 242)]),
                   svg.lin(cx - 6, 0, cx + 6, 0, [(0, LIT), (1, SHADE)]))
    return p


def fg_clover(svg: Svg) -> Part:
    """Bottom-right clover cushion: big soft trifoliate leaves (moss)."""
    p = Part(svg, 250, 210)
    rng = random.Random(52)
    for i in range(14):
        cx = rng.uniform(40, 245)
        cy = rng.uniform(70, 200) + (245 - cx) * 0.1
        s_ = rng.uniform(16, 26) * (0.7 + cy / 400)
        p.path(smooth_path([(cx - 2, 214), (cx + rng.uniform(-8, 8), cy + s_ * 0.6), (cx + 2, 214)], closed=False),
               "none", 1.0, stroke=SHADE, sw=4)
        rot = rng.uniform(0, math.tau)
        for j in range(3):
            a = rot + j * math.tau / 3
            lx, ly = cx + math.cos(a) * s_ * 0.85, cy + math.sin(a) * s_ * 0.6
            p.ellipse(lx, ly, s_, s_ * 0.8, svg.lin(lx, ly - s_, lx, ly + s_, [(0, LIT), (1, SHADE)]), 1.0,
                      rot=math.degrees(a))
            p.ellipse(lx, ly, s_ * 0.45, s_ * 0.16, DETAIL, 0.6, rot=math.degrees(a))
    return p


def fg_bough(svg: Svg) -> Part:
    """Top-right leafy bough hanging into the frame from the right edge (willow_leaf)."""
    p = Part(svg, 280, 320)
    rng = random.Random(53)
    twig = [(290, 30), (230, 52), (170, 70), (120, 96), (84, 130)]
    p.path(smooth_path(twig, closed=False), "none", 1.0, stroke=SHADE, sw=9)
    for _ in range(34):
        t = rng.random()
        i = min(int(t * (len(twig) - 1)), len(twig) - 2)
        u = t * (len(twig) - 1) - i
        x = twig[i][0] + (twig[i + 1][0] - twig[i][0]) * u
        y = twig[i][1] + (twig[i + 1][1] - twig[i][1]) * u
        ln = rng.uniform(40, 120)
        ang = math.radians(rng.uniform(70, 125))
        tip = (x + math.cos(ang) * ln, y + math.sin(ang) * ln)
        w = rng.uniform(7, 12)
        nx, ny = -math.sin(ang) * w, math.cos(ang) * w
        mid = ((x + tip[0]) / 2, (y + tip[1]) / 2)
        d = smooth_path([(x, y), (mid[0] + nx, mid[1] + ny), tip, (mid[0] - nx, mid[1] - ny)])
        p.path(d, svg.lin(x + nx, y + ny, x - nx, y - ny, [(0, LIT), (1, SHADE)]))
        p.path(smooth_path([(x, y), mid, tip], closed=False), "none", 0.5, stroke=DETAIL, sw=1.5)
    return p


# --------------------------------------------------------------------------------------------- #
# Layout (Art Bible §2.4; prop centres come from spots.json at runtime)
# --------------------------------------------------------------------------------------------- #

PARTS = [
    # id, builder, prop, centre, sort_y, material, extras
    ("willow_trunk", willow_trunk, "willow", (-10, 94), 222, "wood_bark", {"shadow": [64, 14, 1.0, 255]}),
    ("willow_curtains", willow_curtains, "willow", (-10, 44), 223, "willow_leaf", {"sway": [4.0, 76, 1.0]}),
    ("willow_crown", willow_crown, "willow", (0, -141), 225, "willow_leaf", {"sway": [1.5, 47, 1.0]}),
    ("chime_branch", chime_branch, "willow", (125, 66), 226, "wood_bark", {}),
    ("mailbox_post", mailbox_post, "mailbox", (-2, 30), 62, "wood_bark", {"shadow": [24, 7, 1.0, 72], "rim": 0}),
    ("mailbox_body", mailbox_body, "mailbox", (-3, -17), 63, "wood_painted", {}),
    ("mailbox_roof", mailbox_roof, "mailbox", (-3, -45), 64, "roof_slate", {}),
    ("mailbox_flag", mailbox_flag, "mailbox", (36, -24), 65, "toadstool_cap", {"rim": 0}),
    ("stump_back", stump_back, "stump", (0, 0), -26, "wood_bark", {"shadow": [100, 16, 1.0, 88]}),
    ("stump_top", stump_top, "stump", (4, -60), -25, "wood_cut", {}),
    ("stump_front", stump_front, "stump", (0, 0), 86, "wood_bark", {}),
    ("stump_moss", stump_moss, "stump", (26, -1), 87, "moss", {"ground": 0.5}),
    ("basket", basket, "basket", (0, -4), 48, "wicker", {"shadow": [58, 10, 1.0, 52]}),
    ("sun_stone", sun_stone, "sun_stone_rock", (0, 0), -52, "stone_warm", {"shadow": [126, 16, 1.2, 56]}),
    ("stone_moss", stone_moss, "sun_stone_rock", (0, 50), 58, "moss", {"rim": 0, "ground": 1.0}),
    ("spring_rock", spring_rock, "spring_rock", (0, 0), -10, "stone_cool", {"shadow": [84, 12, 1.0, 56]}),
    # Art dressing (absolute design px).
    ("glow_mushrooms", glow_mushrooms, "", (488, 1158), 1182, "glow_mushroom", {"emission": 0.55, "rim": 0}),
    ("reeds", reeds, "", (1030, 1352), 1396, "willow_leaf", {"sway": [5.0, 141, 0.95], "rim": 0, "ground": 0.5}),
    ("fern_clump", fern_clump, "", (66, 1108), 1104, "moss", {"sway": [4.0, 133, 0.97], "ground": 0.8}),
    ("clover_a", lambda s: clover_patch(s, 31, 8), "", (430, 1290), 1300, "willow_leaf", {"rim": 0, "ground": 1.0}),
    ("clover_b", lambda s: clover_patch(s, 32, 7), "", (700, 1225), 1236, "willow_leaf", {"rim": 0, "ground": 1.0}),
    ("clover_c", lambda s: clover_patch(s, 33, 9), "", (905, 1385), 1396, "willow_leaf", {"rim": 0, "ground": 1.0}),
    ("clover_bank", lambda s: clover_patch(s, 34, 9), "", (702, 1152), 1135, "willow_leaf", {"rim": 0, "ground": 1.0}),
    ("moss_mound", moss_mound, "", (378, 1150), 1134, "moss", {"ground": 0.7}),
    ("moon_rock", moon_rock, "", (800, 764), 730, "stone_cool", {"shadow": [60, 9, 1.0, 795]}),
    ("pebble_a", lambda s: pebble(s, 41, 30, 18), "", (176, 1470), 1470, "pebble_alt", {"rim": 0}),
    ("pebble_b", lambda s: pebble(s, 42, 22, 14), "", (318, 1459), 1459, "pebble_alt", {"rim": 0}),
    ("pebble_c", lambda s: pebble(s, 43, 34, 20), "", (468, 1451), 1451, "pebble_alt", {"rim": 0}),
    ("pebble_d", lambda s: pebble(s, 44, 24, 15), "", (790, 1436), 1436, "pebble_alt", {"rim": 0}),
    ("pebble_e", lambda s: pebble(s, 45, 28, 17), "", (640, 1546), 1546, "pebble_alt", {"rim": 0}),
]


def pack(sizes: list[tuple[int, int]]) -> tuple[list[tuple[int, int]], int]:
    """Shelf packing, tallest first; returns positions and the atlas height."""
    order = sorted(range(len(sizes)), key=lambda i: -sizes[i][1])
    pos = [(0, 0)] * len(sizes)
    x = y = shelf = 0
    for i in order:
        w, h = sizes[i]
        if x + w + PAD * 2 > ATLAS_W:
            x = 0
            y += shelf
            shelf = 0
        pos[i] = (x + PAD, y + PAD)
        x += w + PAD * 2
        shelf = max(shelf, h + PAD * 2)
    return pos, y + shelf


def main() -> int:
    svg = Svg(ATLAS_W, 16)
    parts = [(pid, b(svg), prop, c, sy, mat, ex) for pid, b, prop, c, sy, mat, ex in PARTS]
    pos, height = pack([(pt.w, pt.h) for _, pt, *_ in parts])
    height = (height + 63) // 64 * 64
    svg.h = height
    layout = []
    for (pid, pt, prop, c, sy, mat, ex), (x, y) in zip(parts, pos):
        cell = svg.clip(f"M{x - 2},{y - 2}h{pt.w + 4}v{pt.h + 4}h{-(pt.w + 4)}Z")
        svg.body.append(f'<g clip-path="{cell}"><g transform="translate({x},{y})">' + "".join(pt.items) + "</g></g>")
        entry = {"id": pid, "prop": prop, "region": [x, y, pt.w, pt.h], "centre": list(c), "sort_y": sy,
                 "material": mat}
        entry.update(ex)
        layout.append(entry)
    OUT_SVG.write_text(svg.to_string())
    OUT_JSON.write_text(json.dumps({"schema": 1, "doc": __doc__.strip().splitlines()[0],
                                    "atlas": "res://art/props/props_atlas.svg", "size": [ATLAS_W, height],
                                    "pad": PAD, "parts": layout}, indent="\t") + "\n")
    print(f"wrote {OUT_SVG.relative_to(ROOT)} ({ATLAS_W}x{height}, {len(layout)} parts)")
    write_fg()
    return 0


# (id, builder, anchor, design rect origin (x, y) of the part's top-left, material). anchor "top" =
# the y is measured from the VISIBLE top of the viewport (tall phones), "bottom" = design frame.
FG_PARTS = [
    ("fg_reeds", fg_reeds, "bottom", (-20, 1684), "willow_leaf", [6.0, 133, 0.95]),
    ("fg_clover", fg_clover, "bottom", (846, 1716), "moss", [3.0, 120, 0.9]),
    ("fg_bough", fg_bough, "top", (812, -16), "willow_leaf", [5.0, 76, 0.0]),
]


def write_fg() -> None:
    svg = Svg(1024, 16)
    x = FG_PAD
    layout = []
    hmax = 0
    for pid, builder, anchor, origin, mat, sway in FG_PARTS:
        pt = builder(svg)
        cell = svg.clip(f"M{x - 2},{FG_PAD - 2}h{pt.w + 4}v{pt.h + 4}h{-(pt.w + 4)}Z")
        svg.body.append(f'<g clip-path="{cell}"><g transform="translate({x},{FG_PAD})">' + "".join(pt.items) + "</g></g>")
        layout.append({"id": pid, "region": [x, FG_PAD, pt.w, pt.h], "anchor": anchor, "origin": list(origin),
                       "material": mat, "sway": sway})
        x += pt.w + FG_PAD * 2
        hmax = max(hmax, pt.h)
    svg.w = 1024
    svg.h = (hmax + FG_PAD * 2 + 63) // 64 * 64
    OUT_FG_SVG.write_text(svg.to_string())
    OUT_FG_JSON.write_text(json.dumps({"schema": 1, "doc": "L5 foreground frame atlas (props_svg.py)",
                                       "atlas": "res://art/props/fg_atlas.svg", "size": [svg.w, svg.h],
                                       "parts": layout}, indent="\t") + "\n")
    print(f"wrote {OUT_FG_SVG.relative_to(ROOT)} ({svg.w}x{svg.h})")


if __name__ == "__main__":
    raise SystemExit(main())
