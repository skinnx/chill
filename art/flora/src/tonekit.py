"""Tone-mask SVG authoring kit shared by the flora and décor atlases (Art Bible §4.9, §6.1).

Tone masks paint pure channels: R = lit, G = shade, B = detail, black = colour-line tone; colour
gradients only run between pure channels (or a pure channel over itself with an opacity ramp), so
R + G + B = 1 wherever a part covers, and alpha = coverage. Every tip is rounded (Catmull-Rom blobs,
round joins), the only filter is feGaussianBlur, there is no <text>.

Parts are authored at design px (depth scale 1) and written at SCALE x into the atlas, so the
stamps stay crisp on 1440 px phones and in 200 % QA crops; mipmaps handle the minification.
Deterministic: every random draw comes from a seeded random.Random.
"""
from __future__ import annotations

import math
import random

LIT = "#FF0000"
SHADE = "#00FF00"
DETAIL = "#0000FF"
LINE = "#000000"


def f(v: float) -> str:
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def smooth_path(pts: list[tuple[float, float]], closed: bool = True, tension: float = 1.0) -> str:
    """Catmull-Rom through pts as cubic Beziers."""
    n = len(pts)
    if n < 2:
        return ""
    out = [f"M{f(pts[0][0])},{f(pts[0][1])}"]
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        p0 = pts[(i - 1) % n] if closed else pts[max(i - 1, 0)]
        p1 = pts[i]
        p2 = pts[(i + 1) % n] if closed else pts[min(i + 1, n - 1)]
        p3 = pts[(i + 2) % n] if closed else pts[min(i + 2, n - 1)]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6 * tension, p1[1] + (p2[1] - p0[1]) / 6 * tension)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6 * tension, p2[1] - (p3[1] - p1[1]) / 6 * tension)
        out.append(f"C{f(c1[0])},{f(c1[1])} {f(c2[0])},{f(c2[1])} {f(p2[0])},{f(p2[1])}")
    if closed:
        out.append("Z")
    return " ".join(out)


def blob_pts(cx: float, cy: float, rx: float, ry: float, n: int = 12, wob: float = 0.06,
             rng: random.Random | None = None, rot: float = 0.0) -> list[tuple[float, float]]:
    rng = rng or random.Random(0)
    pts = []
    for i in range(n):
        a = math.tau * i / n
        k = 1.0 + (rng.random() - 0.5) * 2.0 * wob
        x = math.cos(a) * rx * k
        y = math.sin(a) * ry * k
        pts.append((cx + x * math.cos(rot) - y * math.sin(rot), cy + x * math.sin(rot) + y * math.cos(rot)))
    return pts


def blob(cx: float, cy: float, rx: float, ry: float, n: int = 12, wob: float = 0.06,
         rng: random.Random | None = None, rot: float = 0.0) -> str:
    return smooth_path(blob_pts(cx, cy, rx, ry, n, wob, rng, rot))


def rot_pts(pts: list[tuple[float, float]], cx: float, cy: float, deg: float) -> list[tuple[float, float]]:
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in pts]


def _stops(stops) -> str:
    out = []
    for s in stops:
        o, c = s[0], s[1]
        a = s[2] if len(s) > 2 else 1.0
        out.append(f'<stop offset="{f(o)}" stop-color="{c}"' + (f' stop-opacity="{f(a)}"' if a < 1 else "") + "/>")
    return "".join(out)


class Svg:
    """Collects defs and body for one atlas."""

    def __init__(self, w: int, h: int):
        self.w = w
        self.h = h
        self.defs: list[str] = []
        self.body: list[str] = []
        self._id = 0

    def uid(self, prefix: str) -> str:
        self._id += 1
        return f"{prefix}{self._id}"

    def lin(self, x1, y1, x2, y2, stops) -> str:
        gid = self.uid("lg")
        self.defs.append(f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="{f(x1)}" y1="{f(y1)}" '
                         f'x2="{f(x2)}" y2="{f(y2)}">{_stops(stops)}</linearGradient>')
        return f"url(#{gid})"

    def rad(self, cx, cy, r, stops, fx=None, fy=None) -> str:
        gid = self.uid("rg")
        fxy = f' fx="{f(fx)}" fy="{f(fy)}"' if fx is not None else ""
        self.defs.append(f'<radialGradient id="{gid}" gradientUnits="userSpaceOnUse" cx="{f(cx)}" cy="{f(cy)}" '
                         f'r="{f(r)}"{fxy}>{_stops(stops)}</radialGradient>')
        return f"url(#{gid})"

    def blur(self, sd: float) -> str:
        fid = self.uid("bl")
        self.defs.append(f'<filter id="{fid}" x="-60%" y="-60%" width="220%" height="220%">'
                         f'<feGaussianBlur stdDeviation="{f(sd)}"/></filter>')
        return f"url(#{fid})"

    def clip(self, d: str) -> str:
        cid = self.uid("cp")
        self.defs.append(f'<clipPath id="{cid}"><path d="{d}"/></clipPath>')
        return f"url(#{cid})"

    def to_string(self) -> str:
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" '
                f'viewBox="0 0 {self.w} {self.h}">\n<defs>\n' + "\n".join(self.defs) + "\n</defs>\n"
                + "\n".join(self.body) + "\n</svg>\n")


class Part:
    """One atlas cell: drawing commands in local design px (0..w, 0..h)."""

    def __init__(self, svg: Svg, w: float, h: float, pivot: tuple[float, float] = (0.5, 0.5)):
        self.svg = svg
        self.w = w
        self.h = h
        self.pivot = pivot
        self.items: list[str] = []
        # Empty design px added around the part in the atlas (write_atlas grows the cell and remaps
        # size + pivot, so placement is unchanged): keeps tips and blurs from being cut by the cell.
        self.margin = 0.0

    def path(self, d: str, fill: str = LIT, opacity: float = 1.0, filt: str | None = None,
             stroke: str | None = None, sw: float = 0.0, clip: str | None = None, extra: str = "") -> "Part":
        a = f'<path d="{d}" fill="{fill}"'
        if opacity < 1:
            a += f' opacity="{f(opacity)}"'
        if stroke:
            a += f' stroke="{stroke}" stroke-width="{f(sw)}" stroke-linejoin="round" stroke-linecap="round"'
        if filt:
            a += f' filter="{filt}"'
        a += extra + "/>"
        if clip:
            a = f'<g clip-path="{clip}">{a}</g>'
        self.items.append(a)
        return self

    def ellipse(self, cx, cy, rx, ry, fill=LIT, opacity=1.0, filt=None, clip=None, rot=0.0) -> "Part":
        a = f'<ellipse cx="{f(cx)}" cy="{f(cy)}" rx="{f(rx)}" ry="{f(ry)}" fill="{fill}"'
        if rot:
            a += f' transform="rotate({f(rot)} {f(cx)} {f(cy)})"'
        if opacity < 1:
            a += f' opacity="{f(opacity)}"'
        if filt:
            a += f' filter="{filt}"'
        a += "/>"
        if clip:
            a = f'<g clip-path="{clip}">{a}</g>'
        self.items.append(a)
        return self

    def line(self, pts: list[tuple[float, float]], color: str, width: float, opacity: float = 1.0,
             filt: str | None = None, clip: str | None = None, dash: tuple[float, float] | None = None) -> "Part":
        """An open smooth stroke; `dash` = (stitch, gap) draws it as a running stitch (round caps)."""
        extra = f' stroke-dasharray="{f(dash[0])} {f(dash[1])}"' if dash else ""
        return self.path(smooth_path(pts, closed=False), "none", opacity, filt, color, width, clip, extra)

    def stitch(self, pts: list[tuple[float, float]], width: float, stitch: float, gap: float,
               clip: str | None = None, color: str = DETAIL, opacity: float = 0.9, groove: float = 0.4) -> "Part":
        """Plush seam (round 5): a soft pressed groove (shade, blurred) under a running stitch."""
        if groove > 0:
            self.line(pts, SHADE, width * 1.9, groove, self.svg.blur(width * 0.45), clip)
        return self.line(pts, color, width, opacity, None, clip, (stitch, gap))

    def group(self, inner: list[str], clip: str | None = None, opacity: float = 1.0, filt: str | None = None,
              transform: str = "") -> "Part":
        attrs = ""
        if clip:
            attrs += f' clip-path="{clip}"'
        if opacity < 1:
            attrs += f' opacity="{f(opacity)}"'
        if filt:
            attrs += f' filter="{filt}"'
        if transform:
            attrs += f' transform="{transform}"'
        self.items.append(f"<g{attrs}>" + "".join(inner) + "</g>")
        return self

    def mark(self) -> int:
        return len(self.items)

    def take(self, since: int) -> list[str]:
        """Removes and returns the items drawn since [mark] (to wrap them in a group)."""
        out = self.items[since:]
        del self.items[since:]
        return out

    def speckles(self, rng: random.Random, region, count: int, r: tuple[float, float], fill=DETAIL,
                 opacity: tuple[float, float] = (0.5, 1.0), clip: str | None = None) -> "Part":
        x0, y0, x1, y1 = region
        inner = []
        for _ in range(count):
            x = rng.uniform(x0, x1)
            y = rng.uniform(y0, y1)
            rr = rng.uniform(*r)
            inner.append(f'<ellipse cx="{f(x)}" cy="{f(y)}" rx="{f(rr * rng.uniform(0.8, 1.3))}" ry="{f(rr)}" '
                         f'fill="{fill}" opacity="{f(rng.uniform(*opacity))}"/>')
        self.group(inner, clip=clip)
        return self


def pack(sizes: list[tuple[int, int]], atlas_w: int, pad: int) -> tuple[list[tuple[int, int]], int]:
    """Shelf packing, tallest first; returns cell positions (inside the padding) and the height."""
    order = sorted(range(len(sizes)), key=lambda i: (-sizes[i][1], -sizes[i][0]))
    pos = [(0, 0)] * len(sizes)
    x = y = shelf = 0
    for i in order:
        w, h = sizes[i]
        if x + w + pad * 2 > atlas_w:
            x = 0
            y += shelf
            shelf = 0
        pos[i] = (x + pad, y + pad)
        x += w + pad * 2
        shelf = max(shelf, h + pad * 2)
    return pos, y + shelf


def write_atlas(svg: Svg, parts: list[tuple[str, Part]], scale: int, atlas_w: int, pad: int) -> dict:
    """Packs parts into svg (at scale x) and returns {id: {region, size, pivot}}."""
    sizes = [(math.ceil((p.w + 2 * p.margin) * scale), math.ceil((p.h + 2 * p.margin) * scale)) for _, p in parts]
    pos, height = pack(sizes, atlas_w, pad)
    svg.h = (height + 63) // 64 * 64
    out = {}
    for (pid, p), (x, y), (w, h) in zip(parts, pos, sizes):
        m = p.margin
        cell = svg.clip(f"M{x - 1},{y - 1}h{w + 2}v{h + 2}h{-(w + 2)}Z")
        inner = f" translate({f(m)},{f(m)})" if m else ""
        svg.body.append(f'<g clip-path="{cell}"><g transform="translate({x},{y}) scale({scale}){inner}">'
                        + "".join(p.items) + "</g></g>")
        mw, mh = p.w + 2 * m, p.h + 2 * m
        out[pid] = {"region": [x, y, w, h], "size": [round(mw, 2), round(mh, 2)],
                    "pivot": [round((p.pivot[0] * p.w + m) / mw, 4), round((p.pivot[1] * p.h + m) / mh, 4)]}
    return out
