"""Tiny SVG authoring kit for tone-mask art (Art Bible §4.9, §6.1).

Tone masks paint pure channels: R = lit, G = shade, B = detail, black = colour-line tone; gradients
only run between pure channels so R + G + B = 1 inside, alpha = coverage. Shapes are smooth
Catmull-Rom blobs (every tip rounded), filters are feGaussianBlur only, no <text>.
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
             rng: random.Random | None = None, rot: float = 0.0, squash_bottom: float = 0.0) -> list:
    rng = rng or random.Random(0)
    pts = []
    phase = rng.random() * math.tau
    for i in range(n):
        a = math.tau * i / n + phase * 0.0
        k = 1.0 + (rng.random() - 0.5) * 2.0 * wob
        x = math.cos(a) * rx * k
        y = math.sin(a) * ry * k
        if squash_bottom and y > 0:
            y *= 1.0 - squash_bottom
        xr = x * math.cos(rot) - y * math.sin(rot)
        yr = x * math.sin(rot) + y * math.cos(rot)
        pts.append((cx + xr, cy + yr))
    return pts


def blob(cx, cy, rx, ry, n=12, wob=0.06, rng=None, rot=0.0, squash_bottom=0.0) -> str:
    return smooth_path(blob_pts(cx, cy, rx, ry, n, wob, rng, rot, squash_bottom))


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

    def lin(self, x1, y1, x2, y2, stops, units="userSpaceOnUse") -> str:
        gid = self.uid("lg")
        st = "".join(f'<stop offset="{f(o)}" stop-color="{c}"' + (f' stop-opacity="{f(a)}"' if a < 1 else "") + "/>"
                     for o, c, a in [(s + (1.0,))[:3] if len(s) == 2 else s for s in stops])
        self.defs.append(f'<linearGradient id="{gid}" gradientUnits="{units}" x1="{f(x1)}" y1="{f(y1)}" '
                         f'x2="{f(x2)}" y2="{f(y2)}">{st}</linearGradient>')
        return f"url(#{gid})"

    def rad(self, cx, cy, r, stops, fx=None, fy=None) -> str:
        gid = self.uid("rg")
        st = "".join(f'<stop offset="{f(o)}" stop-color="{c}"' + (f' stop-opacity="{f(a)}"' if a < 1 else "") + "/>"
                     for o, c, a in [(s + (1.0,))[:3] if len(s) == 2 else s for s in stops])
        fxy = f' fx="{f(fx)}" fy="{f(fy)}"' if fx is not None else ""
        self.defs.append(f'<radialGradient id="{gid}" gradientUnits="userSpaceOnUse" cx="{f(cx)}" cy="{f(cy)}" '
                         f'r="{f(r)}"{fxy}>{st}</radialGradient>')
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
    """One atlas cell: drawing commands in local coordinates (0..w, 0..h)."""

    def __init__(self, svg: Svg, w: int, h: int):
        self.svg = svg
        self.w = w
        self.h = h
        self.items: list[str] = []

    # Every call returns self so drawing reads top-down.
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

    def group(self, inner: list[str], clip: str | None = None, opacity: float = 1.0, filt: str | None = None) -> "Part":
        attrs = ""
        if clip:
            attrs += f' clip-path="{clip}"'
        if opacity < 1:
            attrs += f' opacity="{f(opacity)}"'
        if filt:
            attrs += f' filter="{filt}"'
        self.items.append(f"<g{attrs}>" + "".join(inner) + "</g>")
        return self

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
