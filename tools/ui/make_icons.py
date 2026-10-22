#!/usr/bin/env python3
"""Duotone UI icon set (Art Bible §9.3) -> art/icons/<name>.svg + matching .import stubs.

Grid: 24 dp = 72 px canvas, 2 dp padding (60 px live area), rounded terminals and joins, no
interior angle below 60 degrees. Duotone: the primary shape is `ink` (strokes 6 px = 2 dp, round
caps), the secondary shape is the icon's accent (palettes.json `icon_accent`) at
`ui_alpha.icon_duotone_secondary` (0.40). Colours are read from data/palettes.json, never typed.

The accent layer is written with fill-opacity="0.4" (exactly that literal) so the runtime can
switch an icon to its active state (accent at 100 %, Art Bible §9.4 dock "Active") by replacing
that one attribute (scripts/ui/icons.gd). No <text>, no filters (Art Bible §11.4).

Usage: python3 -I tools/ui/make_icons.py   (re-run after changing palettes.json ui tokens)
"""
from __future__ import annotations

import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "art" / "icons"
CANVAS = 72
STROKE = 6
THIN = 4.5

IMPORT_STUB = """[remap]

importer="svg"
type="DPITexture"

[params]

base_scale=1.0
saturation=1.0
color_map={{}}
fix_alpha_border=true
premult_alpha=false
compress=true
"""


def load_tokens() -> tuple[dict, dict, float]:
    pal = json.loads((ROOT / "data" / "palettes.json").read_text(encoding="utf-8"))
    ui = dict(pal["ui"])
    ui.update(pal["ui_derived"])
    return ui, pal["icon_accent"], float(pal["ui_alpha"]["icon_duotone_secondary"])


def svg(body: str) -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" '
            f'viewBox="0 0 {CANVAS} {CANVAS}">{body}</svg>\n')


class Pen:
    """Helpers that emit the two layers with the right colours."""

    def __init__(self, ink: str, accent: str, alpha: float) -> None:
        self.ink = ink
        self.accent = accent
        self.alpha = alpha

    def acc(self, d: str) -> str:  # secondary (accent) filled shape
        return f'<path d="{d}" fill="{self.accent}" fill-opacity="{self.alpha:g}"/>'

    def acc_full(self, d: str) -> str:  # accent at 100 % (hearts, filled states)
        return f'<path d="{d}" fill="{self.accent}"/>'

    def fill(self, d: str) -> str:  # primary filled shape
        return f'<path d="{d}" fill="{self.ink}"/>'

    def line(self, d: str, w: float = STROKE) -> str:  # primary stroke
        return (f'<path d="{d}" fill="none" stroke="{self.ink}" stroke-width="{w:g}" '
                f'stroke-linecap="round" stroke-linejoin="round"/>')

    def circle_acc(self, cx: float, cy: float, r: float) -> str:
        return f'<circle cx="{cx:g}" cy="{cy:g}" r="{r:g}" fill="{self.accent}" fill-opacity="{self.alpha:g}"/>'

    def circle_fill(self, cx: float, cy: float, r: float) -> str:
        return f'<circle cx="{cx:g}" cy="{cy:g}" r="{r:g}" fill="{self.ink}"/>'

    def circle_line(self, cx: float, cy: float, r: float, w: float = STROKE) -> str:
        return (f'<circle cx="{cx:g}" cy="{cy:g}" r="{r:g}" fill="none" stroke="{self.ink}" '
                f'stroke-width="{w:g}"/>')


DROP = "M36 9 C36 9 17 30 17 44 A19 19 0 0 0 55 44 C55 30 36 9 36 9 Z"
CLOUD = "M23 52 H50 A12 12 0 0 0 51 28 A16 16 0 0 0 21 31 A10.5 10.5 0 0 0 23 52 Z"
HEART = ("M36 58 C21 49 10 39 10 27.5 C10 19 16.5 13 24.5 13 C29.5 13 33.5 16 36 20 "
         "C38.5 16 42.5 13 47.5 13 C55.5 13 62 19 62 27.5 C62 39 51 49 36 58 Z")


def rays(cx: float, cy: float, r0: float, r1: float, angles: list[float]) -> str:
    import math
    parts = []
    for a in angles:
        t = math.radians(a)
        parts.append(f"M{cx + r0 * math.cos(t):.2f} {cy + r0 * math.sin(t):.2f} "
                     f"L{cx + r1 * math.cos(t):.2f} {cy + r1 * math.sin(t):.2f}")
    return " ".join(parts)


def icons(p: Pen, accent_of) -> dict[str, str]:
    """name -> svg body. accent_of(name) returns a Pen for another accent."""
    out: dict[str, str] = {}
    g = accent_of("dew")
    out["dew"] = g.acc(DROP) + g.line(DROP) + g.line("M27 44 A9 9 0 0 0 36 53", THIN)
    w = accent_of("watch")
    eye = "M8 36 C17 20 55 20 64 36 C55 52 17 52 8 36 Z"
    out["watch"] = w.acc(eye) + w.line(eye) + w.circle_fill(36, 36, 9) + \
        f'<circle cx="39.5" cy="32.5" r="2.8" fill="{w.accent}"/>'
    out["watch_closed"] = (w.acc("M9 33 C20 47 52 47 63 33 C52 41 20 41 9 33 Z")
                           + w.line("M9 33 C20 47 52 47 63 33")
                           + w.line("M20 44 L16 51 M36 47 V55 M52 44 L56 51", THIN))
    gd = accent_of("garden")
    pot = "M17 41 H55 L50.5 60 Q49.5 63 46.5 63 H25.5 Q22.5 63 21.5 60 Z"
    leaf_l = "M35 33 C26 33 18 27 17 16 C27 15 35 21 35 33 Z"
    leaf_r = "M37 29 C39 20 46 14 56 14 C56 24 48 30 37 29 Z"
    out["garden"] = (gd.acc(pot) + gd.acc(leaf_l) + gd.acc(leaf_r) + gd.line("M36 41 V27")
                     + gd.line(pot) + gd.line(leaf_l) + gd.line(leaf_r))
    al = accent_of("album")
    book = "M20 10 H52 Q58 10 58 16 V56 Q58 62 52 62 H20 Q14 62 14 56 V16 Q14 10 20 10 Z"
    out["album"] = (al.acc(book) + al.line(book) + al.line("M24 11 V61", THIN)
                    + '<ellipse cx="41" cy="43" rx="7.5" ry="6.5" fill="%s"/>' % al.ink
                    + al.circle_fill(32, 32.5, 3.6) + al.circle_fill(41, 28, 3.6) + al.circle_fill(50, 32.5, 3.6))
    bk = accent_of("basket")
    body = "M11 33 H61 L56.5 56 Q55 62 49 62 H23 Q17 62 15.5 56 Z"
    out["basket"] = (bk.acc(body) + bk.line("M20 33 C20 12 52 12 52 33") + bk.line(body)
                     + bk.line("M16.5 46 H55.5", THIN) + bk.line("M30 34 V61 M42 34 V61", THIN))
    st = accent_of("settings")
    out["settings"] = (st.line("M12 25 H18 M36 25 H60") + st.line("M12 47 H36 M54 47 H60")
                       + st.circle_acc(27, 25, 9) + st.circle_line(27, 25, 9)
                       + st.circle_acc(45, 47, 9) + st.circle_line(45, 47, 9))
    out["close"] = p.line("M25 25 L47 47 M47 25 L25 47", 7)
    out["back"] = p.line("M43 17 L25 36 L43 55", 7)
    out["chevron"] = p.line("M29 17 L47 36 L29 55", 7)
    h = accent_of("heart")
    out["heart"] = h.acc_full(HEART)
    out["heart_empty"] = p.line(HEART, THIN)
    t = accent_of("time")
    out["sun"] = (t.circle_acc(36, 36, 13) + t.circle_line(36, 36, 13)
                  + t.line(rays(36, 36, 21, 27, [0, 45, 90, 135, 180, 225, 270, 315])))
    moon = "M42 11 A26 26 0 1 0 61 45 A19 19 0 0 1 42 11 Z"
    out["moon"] = t.acc(moon) + t.line(moon) + t.line("M54 15 V23 M50 19 H58", THIN)
    out["dawn"] = (t.acc("M19 50 A17 17 0 0 1 53 50 Z") + t.line("M19 50 A17 17 0 0 1 53 50")
                   + t.line("M8 50 H64") + t.line(rays(36, 50, 24, 30, [-90, -135, -45]))
                   + t.line("M26 60 H46", THIN))
    out["golden"] = (t.acc("M22 46 A14 14 0 0 1 50 46 Z") + t.line("M22 46 A14 14 0 0 1 50 46")
                     + t.line("M8 46 H64") + t.line("M16 56 H56", THIN) + t.line("M27 64 H45", THIN)
                     + t.line(rays(36, 46, 21, 27, [-90, -140, -40]), THIN))
    out["dusk"] = (t.acc("M26 50 A10 10 0 0 1 46 50 Z") + t.line("M26 50 A10 10 0 0 1 46 50")
                   + t.line("M8 50 H64") + t.line("M18 60 H54", THIN)
                   + t.line("M50 16 V26 M45 21 H55", THIN) + t.circle_fill(24, 24, 3))
    wx = accent_of("weather")
    out["cloud"] = wx.acc(CLOUD) + wx.line(CLOUD)
    out["breeze"] = (wx.line("M10 26 H44 A8 8 0 1 0 36 18")
                     + wx.line("M10 38 H56 A8 8 0 1 1 48 46")
                     + wx.line("M10 50 H30", THIN))
    rain_cloud = "M23 42 H50 A11 11 0 0 0 51 20 A15 15 0 0 0 22 23 A10 10 0 0 0 23 42 Z"
    out["rain"] = (wx.acc(rain_cloud) + wx.line(rain_cloud)
                   + wx.line("M26 50 L23 58 M37 50 L34 58 M48 50 L45 58", THIN))
    pc = accent_of("postcard")
    env = "M16 16 H56 Q62 16 62 22 V50 Q62 56 56 56 H16 Q10 56 10 50 V22 Q10 16 16 16 Z"
    seal = ("M36 47 C30 43.5 26 40 26 35.5 C26 32.5 28.5 30.5 31 30.5 C33 30.5 35 31.7 36 33.5 "
            "C37 31.7 39 30.5 41 30.5 C43.5 30.5 46 32.5 46 35.5 C46 40 42 43.5 36 47 Z")
    out["postcard"] = (pc.acc(env) + pc.line(env) + pc.line("M12 20 L30 34 M60 20 L42 34", THIN)
                       + pc.acc_full(seal))
    ck = accent_of("check")
    out["check"] = ck.line("M19 37 L31 49 L53 24", 7)
    out["plus"] = p.line("M36 18 V54 M18 36 H54", 7)
    out["minus"] = p.line("M18 36 H54", 7)
    s = accent_of("settings")
    out["music"] = (s.circle_acc(25.5, 51.5, 7.5) + s.circle_acc(51.5, 45.5, 7.5)
                    + s.line("M33 51 V16 L59 11 V45") + s.line("M33 27 L59 22", THIN)
                    + s.circle_line(25.5, 51.5, 7.5, THIN) + s.circle_line(51.5, 45.5, 7.5, THIN))
    phone = "M27 12 H45 Q51 12 51 18 V54 Q51 60 45 60 H27 Q21 60 21 54 V18 Q21 12 27 12 Z"
    out["haptics"] = (s.acc(phone) + s.line(phone) + s.line("M32 52 H40", THIN)
                      + s.line("M12 26 Q8 36 12 46 M60 26 Q64 36 60 46", THIN))
    out["motion"] = (s.circle_acc(44, 36, 14) + s.circle_line(44, 36, 14)
                     + s.line("M10 28 H22 M8 38 H20 M12 48 H24", THIN))
    sq1 = "M16 12 H40 Q46 12 46 18 V40 Q46 46 40 46 H18 Q12 46 12 40 V18 Q12 12 16 12 Z"
    sq2 = "M32 26 H54 Q60 26 60 32 V54 Q60 60 54 60 H32 Q26 60 26 54 V32 Q26 26 32 26 Z"
    out["transparency"] = s.acc(sq2) + s.line(sq1) + s.line(sq2)
    out["text_size"] = (s.line("M10 58 L24 16 L38 58 M15 44 H33")
                        + s.circle_acc(51, 47, 9) + s.circle_line(51, 47, 9, THIN) + s.line("M60 37 V57", THIN))
    spk = "M10 29 H20 L33 18 V54 L20 43 H10 Z"
    out["mono"] = s.acc(spk) + s.line(spk) + s.line("M44 26 Q50 36 44 46")
    palm = "M22 40 V22 Q22 18 26 18 Q30 18 30 22 V34 M30 34 V14 Q30 10 34 10 Q38 10 38 14 V34 " \
           "M38 34 V17 Q38 13 42 13 Q46 13 46 17 V36 M46 36 V26 Q46 22 50 22 Q54 22 54 26 V44 " \
           "Q54 62 36 62 Q26 62 20 54 L12 42 Q10 38 13 36 Q16 34 19 37 L22 40"
    out["hand"] = s.acc("M22 40 V22 H54 V44 Q54 62 36 62 Q26 62 20 54 L12 42 Q14 34 22 40 Z") + s.line(palm, THIN + 0.5)
    bubble = "M18 12 H54 Q62 12 62 20 V42 Q62 50 54 50 H34 L22 60 V50 H18 Q10 50 10 42 V20 Q10 12 18 12 Z"
    out["language"] = (s.acc(bubble) + s.line(bubble)
                       + s.circle_line(36, 34, 7, THIN) + s.line("M43 27 V41", THIN)
                       + s.line("M30 22 L36 17 L42 22", THIN))
    frame = "M16 10 H56 Q62 10 62 16 V56 Q62 62 56 62 H16 Q10 62 10 56 V16 Q10 10 16 10 Z"
    out["photo"] = (s.acc("M16 46 L28 32 L38 42 L44 36 L56 46 V48 H16 Z") + s.line(frame)
                    + s.line("M16 46 L28 32 L38 42 L44 36 L56 46", THIN) + s.circle_fill(45, 22, 4.5))
    out["pencil"] = (s.acc("M46 13 L59 26 L27 58 L13 59 L14 45 Z")
                     + s.line("M46 13 L59 26 L27 58 L13 59 L14 45 Z") + s.line("M39 20 L52 33", THIN))
    lb = accent_of("garden")
    hull = "M8 40 Q36 34 64 40 Q60 56 36 56 Q12 56 8 40 Z"
    out["leaf_boat"] = (lb.acc(hull) + lb.line(hull) + lb.line("M36 38 V12") + lb.acc("M38 14 Q54 22 38 32 Z")
                        + lb.line("M38 14 Q54 22 38 32", THIN))
    # paw (a friend dropped by; recap "visited" rows): a soft pad under four toes, accent pad
    pw = accent_of("album")
    pad = "M36 64 C26 64 18 59 18 51 C18 42 27 36 36 36 C45 36 54 42 54 51 C54 59 46 64 36 64 Z"
    out["paw"] = (pw.acc(pad) + pw.line(pad, THIN)
                  + pw.circle_fill(14.5, 33, 5.6) + pw.circle_fill(26, 18.5, 6.2)
                  + pw.circle_fill(46, 18.5, 6.2) + pw.circle_fill(57.5, 33, 5.6))
    out["sparkle"] = g.acc_full("M36 8 Q39 33 64 36 Q39 39 36 64 Q33 39 8 36 Q33 33 36 8 Z")
    return out


def main() -> None:
    ui, accents, alpha = load_tokens()
    ink = ui["ink"]

    def pen_for(name: str) -> Pen:
        token = accents.get(name, "primary")
        return Pen(ink, ui[token], alpha)

    base = Pen(ink, ui["primary"], alpha)
    OUT.mkdir(parents=True, exist_ok=True)
    made = icons(base, pen_for)
    for name, body in sorted(made.items()):
        (OUT / f"{name}.svg").write_text(svg(body), encoding="utf-8")
        imp = OUT / f"{name}.svg.import"
        if not imp.exists():
            imp.write_text(IMPORT_STUB.format(), encoding="utf-8")
    print(f"make_icons: wrote {len(made)} icons to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
