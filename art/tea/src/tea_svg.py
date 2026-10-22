#!/usr/bin/env python3
"""Generates art/tea/tea_atlas.svg + art/tea/tea_atlas.json (Active F2 Tea & Treats, GDD §14).

Run from the repo root:  python3 -I art/tea/src/tea_svg.py

Plush / felt sticker style shared with the dock icons (tools/ui/make_icons.py dock_*): soft round
shapes, a warm cocoa outline (dock_icon.outline #4B3A33), a stitched seam just inside the edge, a
cream highlight and blush cheeks on the pieces with a face. ONE atlas, so the tea nook in the world
and the whole teapot panel in the sheet draw from one texture (one batch each).

Tintable pieces are authored in a neutral light grey (felt shading from #FBFBFB to #DADADA) with
the cocoa outline: the view multiplies them by a teaware or flower colour (outline * colour stays a
dark warm line). Pieces marked "tint": false are full colour.

JSON per piece: region [x, y, w, h] in atlas px, pivot [x, y] in piece px (where the piece stands
or turns), tint (bool). Art Director placeholder set for the 15 teaware pieces: each teaware id is
a colour pair over these shapes (art/tea/README.md).
"""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT_SVG = ROOT / "art/tea/tea_atlas.svg"
OUT_JSON = ROOT / "art/tea/tea_atlas.json"
ATLAS_W = 1024
PAD = 12
LINE = "#4B3A33"
CREAM = "#FFF4E8"
BLUSH = "#FF8F86"
LW = 9.0  # outline at ~3 px per dp for a 150 dp teapot (dock icons: 4.5 at 72 px)


def f(v: float) -> str:
    s = f"{v:.1f}"
    return s[:-2] if s.endswith(".0") else s


class Piece:
    def __init__(self, name: str, w: int, h: int, pivot: tuple[float, float], tint: bool) -> None:
        self.name, self.w, self.h, self.pivot, self.tint = name, w, h, pivot, tint
        self.body: list[str] = []
        self.x = 0
        self.y = 0

    def add(self, s: str) -> None:
        self.body.append(s)


def felt_grad(gid: str, top: str = "#FBFBFB", bottom: str = "#D6D6D6") -> str:
    return (f'<linearGradient id="{gid}" x1="0" y1="0" x2="0.25" y2="1">'
            f'<stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>')


def ellipse_path(cx: float, cy: float, rx: float, ry: float) -> str:
    return (f"M{f(cx - rx)} {f(cy)} A{f(rx)} {f(ry)} 0 1 0 {f(cx + rx)} {f(cy)} "
            f"A{f(rx)} {f(ry)} 0 1 0 {f(cx - rx)} {f(cy)} Z")


def face(p: Piece, cx: float, cy: float, s: float) -> None:
    """Two bead eyes, a tiny smile and blush (the dock icons' plush face)."""
    p.add(f'<ellipse cx="{f(cx - 34 * s)}" cy="{f(cy + 16 * s)}" rx="{f(13 * s)}" ry="{f(8 * s)}" '
          f'fill="{BLUSH}" fill-opacity="0.5"/>')
    p.add(f'<ellipse cx="{f(cx + 34 * s)}" cy="{f(cy + 16 * s)}" rx="{f(13 * s)}" ry="{f(8 * s)}" '
          f'fill="{BLUSH}" fill-opacity="0.5"/>')
    p.add(f'<circle cx="{f(cx - 20 * s)}" cy="{f(cy)}" r="{f(7.5 * s)}" fill="{LINE}"/>')
    p.add(f'<circle cx="{f(cx + 20 * s)}" cy="{f(cy)}" r="{f(7.5 * s)}" fill="{LINE}"/>')
    p.add(f'<circle cx="{f(cx - 22 * s)}" cy="{f(cy - 2.5 * s)}" r="{f(2.4 * s)}" fill="#FFFFFF"/>')
    p.add(f'<circle cx="{f(cx + 18 * s)}" cy="{f(cy - 2.5 * s)}" r="{f(2.4 * s)}" fill="#FFFFFF"/>')
    p.add(f'<path d="M{f(cx - 9 * s)} {f(cy + 12 * s)} Q{f(cx)} {f(cy + 20 * s)} {f(cx + 9 * s)} {f(cy + 12 * s)}" '
          f'fill="none" stroke="{LINE}" stroke-width="{f(4 * s)}" stroke-linecap="round"/>')


def stitch(d: str, w: float = 3.5, dash: str = "11 9", color: str = "#B4B4B4", op: float = 0.9) -> str:
    return (f'<path d="{d}" fill="none" stroke="{color}" stroke-opacity="{op}" stroke-width="{f(w)}" '
            f'stroke-dasharray="{dash}" stroke-linecap="round"/>')


# --------------------------------------------------------------------------------------------- #

def pot_body() -> Piece:
    """The open teapot seen a little from above: a squat felt body, spout left, loop handle right,
    an open mouth (the liquid is drawn into it), a sleepy-happy face. Pivot = the foot centre."""
    p = Piece("pot_body", 460, 340, (220, 326), True)
    p.add(felt_grad("gpot"))
    cx, cy = 240.0, 196.0
    # authored spout-left, mirrored so the spout faces the tray (right) and the handle the thumb
    p.add('<g transform="translate(460 0) scale(-1 1)">')
    # handle (behind the body)
    p.add(f'<path d="M352 132 C452 112 470 262 352 270" fill="none" stroke="{LINE}" stroke-width="44" '
          f'stroke-linecap="round"/>')
    p.add(f'<path d="M352 132 C452 112 470 262 352 270" fill="none" stroke="url(#gpot)" stroke-width="26" '
          f'stroke-linecap="round"/>')
    p.add(stitch("M362 140 C440 128 452 252 362 260", 3, "9 8"))
    # spout
    spout = "M118 200 C78 196 54 160 28 104 C22 92 34 84 44 92 C70 120 96 150 138 160 Z"
    p.add(f'<path d="{spout}" fill="url(#gpot)" stroke="{LINE}" stroke-width="{LW}" stroke-linejoin="round"/>')
    p.add(f'<ellipse cx="36" cy="97" rx="13" ry="8" transform="rotate(-38 36 97)" fill="#7E6A60"/>')
    # body
    body = (f"M{cx - 150} {cy - 40} C{cx - 160} {cy + 40} {cx - 120} {cy + 128} {cx} {cy + 128} "
            f"C{cx + 120} {cy + 128} {cx + 160} {cy + 40} {cx + 150} {cy - 40} "
            f"C{cx + 120} {cy - 92} {cx - 120} {cy - 92} {cx - 150} {cy - 40} Z")
    p.add(f'<path d="{body}" fill="url(#gpot)" stroke="{LINE}" stroke-width="{LW}" stroke-linejoin="round"/>')
    p.add(stitch(f"M{cx - 128} {cy + 2} C{cx - 120} {cy + 84} {cx - 70} {cy + 110} {cx} {cy + 112} "
                 f"C{cx + 70} {cy + 110} {cx + 120} {cy + 84} {cx + 128} {cy + 2}"))
    # felt band below the rim
    p.add(f'<path d="M{cx - 146} {cy - 30} C{cx - 90} {cy + 6} {cx + 90} {cy + 6} {cx + 146} {cy - 30}" '
          f'fill="none" stroke="#C9C9C9" stroke-width="12" stroke-linecap="round"/>')
    # the open mouth (rim + dark inside)
    p.add(f'<path d="{ellipse_path(cx, cy - 52, 122, 34)}" fill="#5E4A42" stroke="{LINE}" stroke-width="{LW}"/>')
    p.add(f'<path d="M{cx - 118} {cy - 46} C{cx - 80} {cy - 22} {cx + 80} {cy - 22} {cx + 118} {cy - 46}" '
          f'fill="none" stroke="#F2F2F2" stroke-width="7" stroke-linecap="round"/>')
    p.add('</g>')
    # highlight (light from the top left) and face, unmirrored
    mx = 460.0 - cx
    p.add(f'<ellipse cx="{mx - 92}" cy="{cy + 20}" rx="20" ry="34" transform="rotate(18 {mx - 92} {cy + 20})" '
          f'fill="#FFFFFF" fill-opacity="0.75"/>')
    face(p, mx - 6, cy + 54, 1.15)
    return p


def pot_cap() -> Piece:
    """The acorn cap lid with its stem nub and a felt cross-hatch. Pivot = the rim centre."""
    p = Piece("pot_cap", 280, 140, (140, 118), True)
    p.add(felt_grad("gcap", "#F4F4F4", "#C8C8C8"))
    d = "M16 112 C10 52 70 22 140 22 C210 22 270 52 264 112 C210 128 70 128 16 112 Z"
    p.add(f'<path d="M126 26 C122 8 134 0 146 6" fill="none" stroke="{LINE}" stroke-width="16" stroke-linecap="round"/>')
    p.add(f'<path d="M126 26 C122 8 134 0 146 6" fill="none" stroke="#DADADA" stroke-width="7" stroke-linecap="round"/>')
    p.add(f'<clipPath id="ccap"><path d="{d}"/></clipPath>')
    p.add(f'<path d="{d}" fill="url(#gcap)"/>')
    p.add('<g clip-path="url(#ccap)">')
    for i in range(8):
        x = 14 + i * 34
        p.add(f'<path d="M{x} 110 Q{x + 10} 70 {x + 30} 38" fill="none" stroke="#A9A9A9" stroke-width="3.5" '
              f'stroke-linecap="round" stroke-opacity="0.8"/>')
        p.add(f'<path d="M{x + 30} 112 Q{x + 18} 72 {x - 2} 42" fill="none" stroke="#A9A9A9" stroke-width="3.5" '
              f'stroke-linecap="round" stroke-opacity="0.55"/>')
    p.add('</g>')
    p.add(f'<path d="{d}" fill="none" stroke="{LINE}" stroke-width="{LW}" stroke-linejoin="round"/>')
    p.add('<ellipse cx="86" cy="50" rx="30" ry="10" transform="rotate(-14 86 50)" fill="#FFFFFF" fill-opacity="0.6"/>')
    return p


def liquid() -> Piece:
    """The tea surface inside the pot's mouth (tinted by the blended petal colours)."""
    p = Piece("liquid", 240, 64, (120, 32), True)
    p.add(f'<path d="{ellipse_path(120, 32, 112, 26)}" fill="#EDEDED"/>')
    p.add(f'<path d="{ellipse_path(120, 36, 88, 16)}" fill="#FFFFFF" fill-opacity="0.35"/>')
    p.add('<ellipse cx="78" cy="24" rx="26" ry="6" fill="#FFFFFF" fill-opacity="0.7"/>')
    return p


def jar_back() -> Piece:
    """Glass behind the jar's petals."""
    p = Piece("jar_back", 168, 200, (84, 196), False)
    p.add('<path d="M30 58 C18 70 16 96 16 130 C16 170 34 190 84 190 C134 190 152 170 152 130 '
          'C152 96 150 70 138 58 Z" fill="#DDEFF2" fill-opacity="0.55"/>')
    return p


def jar_front() -> Piece:
    """The jar's outline, glass shine and cork (drawn over the petals)."""
    p = Piece("jar_front", 168, 200, (84, 196), False)
    p.add('<path d="M30 58 C18 70 16 96 16 130 C16 170 34 190 84 190 C134 190 152 170 152 130 '
          f'C152 96 150 70 138 58" fill="none" stroke="{LINE}" stroke-width="7" stroke-linejoin="round" '
          'stroke-linecap="round"/>')
    p.add('<path d="M34 92 C28 112 28 142 36 164" fill="none" stroke="#FFFFFF" stroke-width="9" '
          'stroke-linecap="round" stroke-opacity="0.85"/>')
    p.add('<path d="M122 160 C130 150 134 136 134 122" fill="none" stroke="#FFFFFF" stroke-width="5" '
          'stroke-linecap="round" stroke-opacity="0.55"/>')
    # neck + cork
    p.add(f'<rect x="34" y="46" width="100" height="18" rx="9" fill="#E9F3F5" stroke="{LINE}" stroke-width="6"/>')
    p.add(f'<path d="M44 46 L46 14 C46 8 52 6 84 6 C116 6 122 8 122 14 L124 46 Z" fill="#E2A76E" '
          f'stroke="{LINE}" stroke-width="6" stroke-linejoin="round"/>')
    p.add(stitch("M54 20 H114", 3, "6 6", "#B97C47", 1.0))
    p.add('<circle cx="66" cy="32" r="3.5" fill="#B97C47"/><circle cx="98" cy="28" r="3" fill="#B97C47"/>')
    return p


def petal() -> Piece:
    """One felt petal (tinted by the flower's petal colour)."""
    p = Piece("petal", 64, 64, (32, 32), True)
    p.add(felt_grad("gpet", "#FFFFFF", "#DCDCDC"))
    d = "M32 6 C48 14 56 30 50 46 C46 56 38 60 32 60 C26 60 18 56 14 46 C8 30 16 14 32 6 Z"
    p.add(f'<path d="{d}" fill="url(#gpet)" stroke="{LINE}" stroke-width="4" stroke-linejoin="round"/>')
    p.add('<path d="M32 18 C30 30 31 42 32 52" fill="none" stroke="#BDBDBD" stroke-width="3" stroke-linecap="round"/>')
    p.add('<ellipse cx="24" cy="26" rx="4" ry="8" transform="rotate(20 24 26)" fill="#FFFFFF" fill-opacity="0.8"/>')
    return p


def cup() -> Piece:
    """A walnut-shell cup on the tray (tinted by the cup teaware); pivot = its foot."""
    p = Piece("cup", 160, 120, (78, 114), True)
    p.add(felt_grad("gcup", "#F7F7F7", "#CFCFCF"))
    p.add(f'<path d="M132 44 C162 40 164 86 128 84" fill="none" stroke="{LINE}" stroke-width="20" stroke-linecap="round"/>')
    p.add('<path d="M132 44 C162 40 164 86 128 84" fill="none" stroke="#E4E4E4" stroke-width="8" stroke-linecap="round"/>')
    d = "M12 38 C12 84 38 110 78 110 C118 110 144 84 144 38 Z"
    p.add(f'<path d="{d}" fill="url(#gcup)" stroke="{LINE}" stroke-width="7" stroke-linejoin="round"/>')
    p.add(stitch("M26 52 C30 84 50 98 78 98 C106 98 126 84 130 52", 3, "8 7"))
    p.add(f'<path d="{ellipse_path(78, 38, 66, 16)}" fill="#6A564D" stroke="{LINE}" stroke-width="7"/>')
    p.add('<ellipse cx="38" cy="68" rx="7" ry="14" transform="rotate(16 38 68)" fill="#FFFFFF" fill-opacity="0.7"/>')
    return p


def cup_tea() -> Piece:
    """The tea inside a cup's rim (tinted by the recipe's liquid token)."""
    p = Piece("cup_tea", 128, 32, (64, 16), True)
    p.add(f'<path d="{ellipse_path(64, 17, 58, 12)}" fill="#EFEFEF"/>')
    p.add('<ellipse cx="44" cy="13" rx="16" ry="4" fill="#FFFFFF" fill-opacity="0.75"/>')
    return p


def mould() -> Piece:
    """The leaf mould treats are poured into (full colour)."""
    p = Piece("mould", 180, 96, (90, 84), False)
    d = "M10 54 C30 18 140 10 172 44 C150 82 40 92 10 54 Z"
    p.add(f'<path d="{d}" fill="#9FD08E" stroke="{LINE}" stroke-width="6" stroke-linejoin="round"/>')
    p.add('<path d="M22 54 C70 46 120 42 160 44" fill="none" stroke="#6FAE74" stroke-width="4" stroke-linecap="round"/>')
    for x, y in ((60, 50), (96, 46), (130, 45)):
        p.add(f'<path d="M{x} {y} L{x + 14} {y - 16}" stroke="#6FAE74" stroke-width="3" stroke-linecap="round"/>')
        p.add(f'<path d="M{x} {y} L{x + 12} {y + 14}" stroke="#6FAE74" stroke-width="3" stroke-linecap="round"/>')
    return p


def treat() -> Piece:
    """A little felt cake / sweet on the leaf (tinted by the recipe's liquid token)."""
    p = Piece("treat", 120, 96, (60, 90), True)
    p.add(felt_grad("gtr", "#FFFFFF", "#D2D2D2"))
    d = "M12 74 C10 30 34 12 60 12 C86 12 110 30 108 74 C90 88 30 88 12 74 Z"
    p.add(f'<path d="{d}" fill="url(#gtr)" stroke="{LINE}" stroke-width="6" stroke-linejoin="round"/>')
    p.add('<path d="M18 46 C30 56 36 40 46 52 C56 62 64 44 74 54 C84 62 92 44 102 48" fill="none" '
          'stroke="#FFFFFF" stroke-width="9" stroke-linecap="round" stroke-opacity="0.95"/>')
    p.add(f'<circle cx="60" cy="12" r="9" fill="#FF9DB6" stroke="{LINE}" stroke-width="4"/>')
    p.add('<circle cx="40" cy="68" r="3" fill="#BDBDBD"/><circle cx="78" cy="70" r="3" fill="#BDBDBD"/>')
    return p


def drop() -> Piece:
    """A dew drop (full colour, the HUD dew: dock_icon.dew / dew_hi)."""
    p = Piece("drop", 72, 88, (36, 84), False)
    d = "M36 6 C50 28 64 44 64 58 C64 74 52 84 36 84 C20 84 8 74 8 58 C8 44 22 28 36 6 Z"
    p.add(f'<path d="{d}" fill="#8CCFEF" stroke="{LINE}" stroke-width="5" stroke-linejoin="round"/>')
    p.add('<path d="M24 52 C22 62 26 70 32 74" fill="none" stroke="#E2F5FD" stroke-width="6" stroke-linecap="round"/>')
    p.add('<circle cx="46" cy="46" r="4" fill="#E2F5FD"/>')
    return p


def spoon() -> Piece:
    """The little wooden stirring spoon (full colour); pivot = the bowl's centre."""
    p = Piece("spoon", 64, 236, (32, 206), False)
    p.add(f'<path d="M28 12 C28 6 36 6 36 12 L38 170 L26 170 Z" fill="#E7B47E" stroke="{LINE}" stroke-width="5" '
          'stroke-linejoin="round"/>')
    p.add(f'<ellipse cx="32" cy="200" rx="22" ry="30" fill="#E7B47E" stroke="{LINE}" stroke-width="5"/>')
    p.add('<ellipse cx="32" cy="204" rx="12" ry="18" fill="#C98E58"/>')
    p.add('<path d="M31 24 L32 160" stroke="#F6D2A8" stroke-width="3" stroke-linecap="round"/>')
    return p


def steam() -> Piece:
    """A soft steam wisp (white; the view fades and sways it)."""
    p = Piece("steam", 72, 160, (36, 156), True)
    p.add('<path d="M36 152 C14 128 56 108 36 82 C18 58 54 40 38 10" fill="none" stroke="#FFFFFF" '
          'stroke-width="16" stroke-linecap="round" stroke-opacity="0.7"/>')
    p.add('<path d="M36 152 C14 128 56 108 36 82 C18 58 54 40 38 10" fill="none" stroke="#FFFFFF" '
          'stroke-width="6" stroke-linecap="round"/>')
    return p


def cloth() -> Piece:
    """The nook's mat with a scalloped edge (tinted by the cloth teaware)."""
    p = Piece("cloth", 300, 84, (150, 50), True)
    p.add(felt_grad("gcl", "#F6F6F6", "#D2D2D2"))
    d = "M14 66 C6 40 40 18 150 18 C260 18 294 40 286 66"
    for i in range(12, 0, -1):
        x0 = 14 + i * 22.6
        x1 = x0 - 22.6
        d += f" Q{f((x0 + x1) / 2)} 80 {f(x1)} 66"
    d += " Z"
    p.add(f'<path d="{d}" fill="url(#gcl)" stroke="{LINE}" stroke-width="6" stroke-linejoin="round"/>')
    p.add(stitch("M30 58 C30 40 60 30 150 30 C240 30 270 40 270 58", 3, "8 7"))
    return p


def sparkle() -> Piece:
    """A four-point sparkle (the "new recipe" stamp, the nook's something-new twinkle)."""
    p = Piece("sparkle", 64, 64, (32, 32), False)
    p.add(f'<path d="M32 4 C35 24 40 29 60 32 C40 35 35 40 32 60 C29 40 24 35 4 32 C24 29 29 24 32 4 Z" '
          f'fill="#FFD66B" stroke="{LINE}" stroke-width="3.5" stroke-linejoin="round"/>')
    p.add('<circle cx="28" cy="27" r="3" fill="#FFF4E8"/>')
    return p


def stamp() -> Piece:
    """A round felt rosette behind "A new recipe!" (full colour, coral)."""
    p = Piece("stamp", 132, 132, (66, 66), False)
    pts = []
    for i in range(24):
        a = i / 24 * math.tau
        r = 62 if i % 2 == 0 else 54
        pts.append(f"{f(66 + r * math.cos(a))} {f(66 + r * math.sin(a))}")
    p.add(f'<path d="M{" L".join(pts)} Z" fill="#FF9F86" stroke="{LINE}" stroke-width="4" stroke-linejoin="round"/>')
    p.add(f'<circle cx="66" cy="66" r="40" fill="#FFF4E8" stroke="#EE8068" stroke-width="4" stroke-dasharray="7 6"/>')
    return p


# Placeholder colour pairs per teaware id (tea.json teaware) over the shared felt shapes, until the
# Art Director's set (GDD §14.11): body / cap tints, glow = the night pieces (moon kettle, moon cups).
TEAWARE = {
    "acorn_teapot": {"body": "#F0C995", "cap": "#B98458"},
    "toadstool_teapot": {"body": "#FFF1DE", "cap": "#F08A72"},
    "shell_teapot": {"body": "#F7DCC8", "cap": "#E7A68C"},
    "willow_teapot": {"body": "#D5E7B8", "cap": "#97C18A"},
    "moon_kettle": {"body": "#DCE4F8", "cap": "#B4C0EA", "glow": True},
    "walnut_cup": {"body": "#DDAE7C"},
    "daisy_cup": {"body": "#FFF7E8"},
    "bluebell_cup": {"body": "#CFCBF4"},
    "leaf_cup": {"body": "#BDDDA6"},
    "pebble_cup": {"body": "#D9D5CF"},
    "moon_cup": {"body": "#DFE8F9", "glow": True},
    "moss_mat": {"body": "#AFD39A"},
    "gingham_cloth": {"body": "#F8CBC4"},
    "fern_lace_cloth": {"body": "#E6F1D8"},
    "star_quilt": {"body": "#C3CCEF"},
}

def white() -> Piece:
    """A solid white texel block: rings, swirls and the pour stream are drawn as polygons UV-mapped
    onto it, so they batch with the pieces (one texture)."""
    p = Piece("white", 16, 16, (8, 8), True)
    p.add('<rect x="0" y="0" width="16" height="16" fill="#FFFFFF"/>')
    return p


def dot() -> Piece:
    """A soft round white dot: stitched rings, the swirl and the pour stream are chains of these."""
    p = Piece("dot", 32, 32, (16, 16), True)
    p.add('<circle cx="16" cy="16" r="14" fill="#FFFFFF"/>')
    return p


PIECES = [white, dot, pot_body, pot_cap, liquid, jar_back, jar_front, petal, cup, cup_tea, mould, treat, drop, spoon, steam,
          cloth, sparkle, stamp]


def pack(pieces: list[Piece]) -> int:
    x, y, row_h = PAD, PAD, 0
    for p in sorted(pieces, key=lambda q: -q.h):
        if x + p.w + PAD > ATLAS_W:
            x, y, row_h = PAD, y + row_h + PAD * 2, 0
        p.x, p.y = x, y
        x += p.w + PAD * 2
        row_h = max(row_h, p.h)
    return y + row_h + PAD


def main() -> None:
    pieces = [fn() for fn in PIECES]
    h = pack(pieces)
    h = int(math.ceil(h / 4.0) * 4)
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{ATLAS_W}" height="{h}" viewBox="0 0 {ATLAS_W} {h}">']
    defs = []
    for p in pieces:
        body = []
        for s in p.body:
            (defs if s.startswith(("<linearGradient", "<clipPath")) else body).append(s)
        out.append(f'<g transform="translate({p.x} {p.y})">' + "".join(body) + "</g>")
    out.insert(1, "<defs>" + "".join(defs) + "</defs>")
    out.append("</svg>")
    OUT_SVG.parent.mkdir(parents=True, exist_ok=True)
    OUT_SVG.write_text("".join(out) + "\n", encoding="utf-8")
    doc = {
        "schema": 1,
        "doc": "Generated by art/tea/src/tea_svg.py (do not edit). Regions in atlas px; pivot in piece px.",
        "atlas": "res://art/tea/tea_atlas.svg",
        "size": [ATLAS_W, h],
        "pieces": {p.name: {"region": [p.x, p.y, p.w, p.h], "pivot": list(p.pivot), "tint": p.tint}
                   for p in pieces},
        "teaware": TEAWARE,
    }
    OUT_JSON.write_text(json.dumps(doc, indent="\t") + "\n", encoding="utf-8")
    print(f"tea atlas: {len(pieces)} pieces, {ATLAS_W}x{h}")


if __name__ == "__main__":
    main()
