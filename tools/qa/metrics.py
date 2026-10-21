#!/usr/bin/env python3
"""Automated visual checks on screenshots (synthesis §4 V2, V6, X2; docs/QA.md §4).

Usage:
    python3 -I tools/qa/metrics.py [options] shot.png [more.png ...]
    python3 -I tools/qa/metrics.py --selftest

Each image may have a sidecar ``<image>.json`` written by tools/qa/capture.gd. It gives the
phase (which V2 rule applies) and the screen rects and font colours of every visible text
control (the contrast check). Without a sidecar the HSV rule is used and only the regions
passed with --text-region are checked.

Checks:
  v2        Low-arousal colour (synthesis V2, 04 P6).
            hsv:   >= 85 % of the area has HSV S <= 0.45 and V >= 0.45; saturated accents
                   (S > 0.45, V >= 0.45) <= 10 %. Applies to dawn, day and golden.
            oklch: Art Bible §11.3 amendment A6, PROVISIONAL until the Director ratifies it.
                   >= 85 % of the area at OKLCh C <= 0.10, accents (C > 0.12) <= 10 %,
                   no pixel below CIE L* 6. Applies to dusk and night.
            Always: the 99.9th-percentile OKLab chroma is <= 0.2 (token colours only).
            Both rules are always reported; --v2-mode picks the gating one (auto = by phase).
  banding   Quantisation staircases in gradients (synthesis V6, C6; 05 §2.4). Per channel,
            along rows and columns, a staircase is >= 3 consecutive flat runs, each >= --band-run
            px long, separated by steps of 1..2 code values in the same direction: the exact
            signature of an undithered 8-bit gradient. TPDF dither (+-1 LSB) breaks every run,
            so a correctly dithered frame scores ~0. Fails above --band-max (fraction of area).
  contrast  Text contrast (synthesis X2, WCAG 2.2 1.4.3). For each text rect, the declared
            font colour (sidecar) or, failing that, the extreme 2 % of the rect, against the
            background pixels in the rect. Gates on the 5th-percentile ratio (the worst part of
            the backdrop, e.g. glass over the sky) >= 4.5.

Output: a JSON report on stdout (and --json PATH). Exit 1 if a gating check fails (--gate, default
every check that ran; --no-fail reports only), 2 on usage errors. Needs numpy and Pillow only.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# --- V2 thresholds (synthesis V2 / 04 P6; Art Bible §11.3 A6) ------------------------------
HSV_S_MAX = 0.45
HSV_V_MIN = 0.45
CALM_MIN_SHARE = 0.85
ACCENT_MAX_SHARE = 0.10
OKLCH_CALM_C_MAX = 0.10
OKLCH_ACCENT_C_MIN = 0.12
OKLCH_L_STAR_MIN = 6.0
TOKEN_CHROMA_MAX = 0.20
TOKEN_CHROMA_PERCENTILE = 99.9
HSV_PHASES = {"dawn", "day", "golden"}
OKLCH_PHASES = {"dusk", "night"}

# --- Banding (V6) ----------------------------------------------------------------------------
BAND_MIN_RUN_PX = 16  # 05 §2.4: the day sky's blue steps every 110 px (290 px on tall screens) and
# is visible; red/green step every 11-20 px and is not. TPDF runs of 16+ equal values are ~1 %.
BAND_MAX_STEP = 2  # code values; larger steps are real edges, not quantisation
BAND_MIN_PLATEAUS = 3
BAND_MAX_SHARE = 0.005

# --- Contrast (X2) ---------------------------------------------------------------------------
CONTRAST_MIN = 4.5
CONTRAST_PERCENTILE = 5.0
TEXT_EXTREME_SHARE = 0.02
## A pixel is a glyph (or anti-aliasing) pixel when it is closer to the declared font colour than
## this share of the rect-median-to-font distance (OKLab); everything else is backdrop.
GLYPH_DISTANCE_SHARE = 0.5
MIN_BG_PIXELS = 16


# ============================================================================== colour maths

def srgb_to_linear(c: np.ndarray) -> np.ndarray:
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def relative_luminance(rgb01: np.ndarray) -> np.ndarray:
    lin = srgb_to_linear(rgb01)
    return lin[..., 0] * 0.2126 + lin[..., 1] * 0.7152 + lin[..., 2] * 0.0722


def linear_to_oklab(lin: np.ndarray) -> np.ndarray:
    """Björn Ottosson's OKLab (2020), the same matrices as scripts/world/palette_math.gd."""
    r, g, b = lin[..., 0], lin[..., 1], lin[..., 2]
    l_ = np.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    m_ = np.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    s_ = np.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return np.stack([
        0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    ], axis=-1)


def cie_l_star(y: np.ndarray) -> np.ndarray:
    eps = 216.0 / 24389.0
    kappa = 24389.0 / 27.0
    return np.where(y > eps, 116.0 * np.cbrt(y) - 16.0, kappa * y)


def contrast_ratio(y1: np.ndarray | float, y2: np.ndarray | float) -> np.ndarray:
    hi = np.maximum(y1, y2)
    lo = np.minimum(y1, y2)
    return (hi + 0.05) / (lo + 0.05)


# ============================================================================== checks

def check_v2(rgb: np.ndarray, phase: str | None, mode: str) -> dict:
    x = rgb.astype(np.float64) / 255.0
    mx = x.max(axis=-1)
    mn = x.min(axis=-1)
    sat = np.where(mx > 0.0, (mx - mn) / np.maximum(mx, 1e-12), 0.0)
    val = mx
    bright = val >= HSV_V_MIN
    hsv_calm = float(np.mean((sat <= HSV_S_MAX) & bright))
    hsv_accent = float(np.mean((sat > HSV_S_MAX) & bright))
    lab = linear_to_oklab(srgb_to_linear(x))
    chroma = np.hypot(lab[..., 1], lab[..., 2])
    l_star = cie_l_star(relative_luminance(x))
    ok_calm = float(np.mean(chroma <= OKLCH_CALM_C_MAX))
    ok_accent = float(np.mean(chroma > OKLCH_ACCENT_C_MIN))
    l_min = float(l_star.min())
    chroma_hi = float(np.percentile(chroma, TOKEN_CHROMA_PERCENTILE))
    hsv_pass = hsv_calm >= CALM_MIN_SHARE and hsv_accent <= ACCENT_MAX_SHARE
    ok_pass = ok_calm >= CALM_MIN_SHARE and ok_accent <= ACCENT_MAX_SHARE and l_min >= OKLCH_L_STAR_MIN
    if mode == "auto":
        mode = "oklch" if phase in OKLCH_PHASES else "hsv"
    gate = hsv_pass if mode == "hsv" else ok_pass
    token_pass = chroma_hi <= TOKEN_CHROMA_MAX
    return {
        "mode": mode,
        "provisional": mode == "oklch",
        "hsv": {"calm_share": round(hsv_calm, 4), "accent_share": round(hsv_accent, 4), "pass": hsv_pass},
        "oklch": {"calm_share": round(ok_calm, 4), "accent_share": round(ok_accent, 4),
                  "l_star_min": round(l_min, 2), "pass": ok_pass},
        "chroma_p999": round(chroma_hi, 4),
        "token_chroma_pass": token_pass,
        "pass": bool(gate and token_pass),
    }


def _row_staircases(row: np.ndarray, min_run: int, max_step: int, min_plateaus: int) -> tuple[int, int]:
    """(pixels covered by staircases, number of staircases) in one 1-D int array."""
    edges = np.flatnonzero(np.diff(row))
    if edges.size < min_plateaus - 1:
        return 0, 0
    starts = np.concatenate(([0], edges + 1))
    lengths = np.diff(np.concatenate((starts, [row.size])))
    steps = row[edges + 1] - row[edges]
    long_run = lengths >= min_run
    link = long_run[:-1] & long_run[1:] & (np.abs(steps) <= max_step)
    signed = np.where(link, np.sign(steps), 0)
    if not signed.any():
        return 0, 0
    # Maximal segments of equal non-zero sign: each segment of n links spans n + 1 plateaus.
    padded = np.concatenate(([0], signed, [0]))
    change = np.flatnonzero(np.diff(padded))
    covered = 0
    count = 0
    for a, b in zip(change[:-1], change[1:]):
        if signed[a] == 0:
            continue
        if b - a + 1 >= min_plateaus:
            covered += int(lengths[a:b + 1].sum())
            count += 1
    return covered, count


def check_banding(rgb: np.ndarray, min_run: int, max_share: float) -> dict:
    h, w, _ = rgb.shape
    data = rgb.astype(np.int16)
    mask = np.zeros((h, w), dtype=bool)
    staircases = 0
    for ch in range(3):
        plane = data[..., ch]
        for axis in (0, 1):
            lines = plane if axis == 1 else plane.T
            for i, line in enumerate(lines):
                covered, n = _row_staircases(line, min_run, BAND_MAX_STEP, BAND_MIN_PLATEAUS)
                if n:
                    staircases += n
                    _mark_staircases(line, i, axis, min_run, mask)
    share = float(mask.mean())
    bbox = None
    if mask.any():
        ys, xs = np.nonzero(mask)
        bbox = [int(xs.min()), int(ys.min()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)]
    return {
        "share": round(share, 5),
        "staircases": staircases,
        "bbox": bbox,
        "min_run_px": min_run,
        "max_share": max_share,
        "pass": share <= max_share,
    }


def _mark_staircases(line: np.ndarray, index: int, axis: int, min_run: int, mask: np.ndarray) -> None:
    edges = np.flatnonzero(np.diff(line))
    starts = np.concatenate(([0], edges + 1))
    lengths = np.diff(np.concatenate((starts, [line.size])))
    steps = line[edges + 1] - line[edges]
    long_run = lengths >= min_run
    link = long_run[:-1] & long_run[1:] & (np.abs(steps) <= BAND_MAX_STEP)
    signed = np.where(link, np.sign(steps), 0)
    padded = np.concatenate(([0], signed, [0]))
    change = np.flatnonzero(np.diff(padded))
    for a, b in zip(change[:-1], change[1:]):
        if signed[a] == 0 or b - a + 1 < BAND_MIN_PLATEAUS:
            continue
        lo = int(starts[a])
        hi = int(starts[b] + lengths[b])
        if axis == 1:
            mask[index, lo:hi] = True
        else:
            mask[lo:hi, index] = True


def check_contrast(rgb: np.ndarray, regions: list[dict], min_ratio: float) -> dict:
    h, w, _ = rgb.shape
    results = []
    for reg in regions:
        x, y, rw, rh = (int(round(v)) for v in reg["rect"])
        x0, y0 = max(0, x), max(0, y)
        x1, y1 = min(w, x + rw), min(h, y + rh)
        entry = {"name": reg.get("path", reg.get("name", "region")), "rect": [x0, y0, x1 - x0, y1 - y0]}
        if x1 - x0 < 2 or y1 - y0 < 2:
            entry.update({"skipped": "off-screen or empty", "pass": True})
            results.append(entry)
            continue
        px = rgb[y0:y1, x0:x1].reshape(-1, 3).astype(np.float64) / 255.0
        lum = relative_luminance(px)
        font = reg.get("font_color")
        if font is not None and len(font) >= 3 and (len(font) < 4 or font[3] > 0.0):
            text_rgb = np.clip(np.array(font[:3], dtype=np.float64), 0.0, 1.0)
            lab = linear_to_oklab(srgb_to_linear(px))
            text_lab = linear_to_oklab(srgb_to_linear(text_rgb[None, :]))[0]
            d_text = np.linalg.norm(lab - text_lab, axis=-1)
            bg = d_text > GLYPH_DISTANCE_SHARE * float(np.median(d_text))
            text_y = float(relative_luminance(text_rgb[None, :])[0])
            source = "declared"
        else:
            med = float(np.median(lum))
            lo_q, hi_q = np.quantile(lum, [TEXT_EXTREME_SHARE, 1.0 - TEXT_EXTREME_SHARE])
            dark_text = abs(med - lo_q) > abs(hi_q - med)
            text_y = float(lo_q if dark_text else hi_q)
            bg = lum > (med + lo_q) / 2.0 if dark_text else lum < (med + hi_q) / 2.0
            source = "measured"
        if int(bg.sum()) < MIN_BG_PIXELS:
            entry.update({"skipped": "no background pixels", "pass": True})
            results.append(entry)
            continue
        ratios = contrast_ratio(lum[bg], text_y)
        worst = float(np.percentile(ratios, CONTRAST_PERCENTILE))
        entry.update({
            "text_color": source,
            "ratio_median": round(float(np.median(ratios)), 2),
            "ratio_p5": round(worst, 2),
            "pass": worst >= min_ratio,
        })
        results.append(entry)
    return {"min_ratio": min_ratio, "regions": results, "pass": all(r["pass"] for r in results)}


# ============================================================================== driver

def load_sidecar(path: Path) -> dict:
    side = Path(str(path) + ".json")
    if side.is_file():
        try:
            return json.loads(side.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}
    return {}


def parse_region(spec: str) -> dict:
    parts = spec.split(",")
    if len(parts) not in (4, 5):
        raise argparse.ArgumentTypeError("expected x,y,w,h[,#rrggbb]")
    reg: dict = {"name": "cli:" + spec, "rect": [float(p) for p in parts[:4]]}
    if len(parts) == 5:
        hexs = parts[4].lstrip("#")
        reg["font_color"] = [int(hexs[i:i + 2], 16) / 255.0 for i in (0, 2, 4)] + [1.0]
    return reg


def analyse(path: Path, args: argparse.Namespace) -> dict:
    rgb = np.asarray(Image.open(path).convert("RGB"))
    meta = load_sidecar(path)
    phase = meta.get("phase") or args.phase
    out = {"image": str(path), "size": [int(rgb.shape[1]), int(rgb.shape[0])], "phase": phase or None}
    checks = set(args.checks.split(","))
    if "v2" in checks:
        out["v2"] = check_v2(rgb, phase, args.v2_mode)
    if "banding" in checks:
        out["banding"] = check_banding(rgb, args.band_run, args.band_max)
    if "contrast" in checks:
        regions = list(meta.get("text_regions", [])) + list(args.text_region or [])
        out["contrast"] = check_contrast(rgb, regions, args.contrast_min)
    out["pass"] = all(out[k]["pass"] for k in ("v2", "banding", "contrast") if k in out)
    return out


# ============================================================================== self-test

def _tpdf(shape: tuple, rng: np.random.Generator) -> np.ndarray:
    return rng.random(shape) + rng.random(shape) - 1.0


def _sky(h: int, w: int, top: tuple, bottom: tuple, dither: bool, rng: np.random.Generator) -> np.ndarray:
    t = np.linspace(0.0, 1.0, h)[:, None, None]
    c = (np.array(top, dtype=np.float64) * (1 - t) + np.array(bottom, dtype=np.float64) * t)
    c = np.broadcast_to(c, (h, w, 3)).copy()
    if dither:
        c += _tpdf(c.shape, rng)
    return np.clip(np.rint(c), 0, 255).astype(np.uint8)


def selftest() -> int:
    rng = np.random.default_rng(7)
    ok = True

    def expect(name: str, cond: bool, detail: object) -> None:
        nonlocal ok
        ok = ok and cond
        print(("PASS " if cond else "FAIL ") + name + "  " + json.dumps(detail))

    day_top, day_bottom = (0x6F, 0xB6, 0xEC), (0xD6, 0xEE, 0xF6)  # 05 §2.4 day sky
    night_top, night_bottom = (0x11, 0x19, 0x38), (0x3D, 0x4F, 0x8C)
    plain = _sky(1100, 540, day_top, day_bottom, False, rng)
    dith = _sky(1100, 540, day_top, day_bottom, True, rng)
    b_plain = check_banding(plain, BAND_MIN_RUN_PX, BAND_MAX_SHARE)
    b_dith = check_banding(dith, BAND_MIN_RUN_PX, BAND_MAX_SHARE)
    expect("undithered day sky bands", not b_plain["pass"] and b_plain["share"] > 0.3, b_plain)
    expect("TPDF-dithered day sky is clean", b_dith["pass"] and b_dith["share"] < 0.001, b_dith)
    n_plain = check_banding(_sky(1100, 540, night_top, night_bottom, False, rng), BAND_MIN_RUN_PX, BAND_MAX_SHARE)
    n_dith = check_banding(_sky(1100, 540, night_top, night_bottom, True, rng), BAND_MIN_RUN_PX, BAND_MAX_SHARE)
    expect("undithered night sky bands", not n_plain["pass"], n_plain)
    expect("dithered night sky is clean", n_dith["pass"], n_dith)
    flat = np.zeros((400, 400, 3), dtype=np.uint8)
    flat[:] = (0xF0, 0xEE, 0xE9)
    flat[100:300, 100:300] = (0x2A, 0x28, 0x38)  # hard-edged panel: real edges, not banding
    expect("flat fills and hard edges are not banding", check_banding(flat, BAND_MIN_RUN_PX, BAND_MAX_SHARE)["pass"],
           check_banding(flat, BAND_MIN_RUN_PX, BAND_MAX_SHARE)["share"])

    calm = np.zeros((200, 200, 3), dtype=np.uint8)
    calm[:] = (0x9E, 0xD2, 0xF2)  # sky_mid, S 0.35 V 0.95
    calm[:, :16] = (0xFF, 0xC5, 0x6E)  # 8 % marigold accent (S 0.57)
    v = check_v2(calm, "day", "auto")
    expect("day palette with an 8 % accent passes V2 (hsv)", v["pass"] and v["mode"] == "hsv", v)
    loud = calm.copy()
    loud[:, :60] = (0xFF, 0x30, 0x30)  # 30 % alarm red
    v = check_v2(loud, "day", "auto")
    expect("30 % saturated red fails V2", not v["pass"], v)
    night = np.zeros((200, 200, 3), dtype=np.uint8)
    night[:] = (0x26, 0x33, 0x5E)  # dark low-chroma night sky: fails HSV by design (A6)
    v = check_v2(night, "night", "auto")
    expect("night sky fails HSV but passes the A6 OKLCh rule", (not v["hsv"]["pass"]) and v["oklch"]["pass"] and v["pass"], v)

    panel = np.zeros((120, 400, 3), dtype=np.uint8)
    panel[:] = (0xF0, 0xEE, 0xE9)
    panel[40:80, 20:380:6] = (0x2A, 0x28, 0x38)  # ink "glyph" strokes on the surface colour
    ink = [0x2A / 255, 0x28 / 255, 0x38 / 255, 1.0]
    c = check_contrast(panel, [{"name": "ink", "rect": [0, 0, 400, 120], "font_color": ink}], CONTRAST_MIN)
    expect("ink on surface >= 4.5:1 (declared colour)", c["pass"] and c["regions"][0]["ratio_p5"] > 10, c)
    c = check_contrast(panel, [{"name": "ink", "rect": [0, 0, 400, 120]}], CONTRAST_MIN)
    expect("ink on surface >= 4.5:1 (measured colour)", c["pass"], c)
    pale = panel.copy()
    pale[40:80, 20:380:6] = (0xC8, 0xC4, 0xBC)
    c = check_contrast(pale, [{"name": "pale", "rect": [0, 0, 400, 120], "font_color": [0xC8 / 255, 0xC4 / 255, 0xBC / 255, 1]}], CONTRAST_MIN)
    expect("pale text on surface fails", not c["pass"], c)
    print("selftest:", "ok" if ok else "FAILED")
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("images", nargs="*", type=Path)
    ap.add_argument("--selftest", action="store_true", help="run the detector calibration self-test")
    ap.add_argument("--json", type=Path, help="also write the report here")
    ap.add_argument("--checks", default="v2,banding,contrast", help="comma list of v2,banding,contrast")
    ap.add_argument("--v2-mode", choices=("auto", "hsv", "oklch"), default="auto")
    ap.add_argument("--phase", help="phase when there is no sidecar (dawn/day/golden/dusk/night)")
    ap.add_argument("--band-run", type=int, default=BAND_MIN_RUN_PX, help="min plateau length in px")
    ap.add_argument("--band-max", type=float, default=BAND_MAX_SHARE, help="max banded share of the area")
    ap.add_argument("--contrast-min", type=float, default=CONTRAST_MIN)
    ap.add_argument("--text-region", action="append", type=parse_region, metavar="x,y,w,h[,#rrggbb]",
                    help="extra text rect in image px (repeatable)")
    ap.add_argument("--gate", help="comma list of the checks that set the exit code (default: all run)")
    ap.add_argument("--no-fail", action="store_true", help="always exit 0 (report only)")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()
    if not args.images:
        ap.print_usage(sys.stderr)
        return 2
    reports = []
    for p in args.images:
        if not p.is_file():
            print(f"metrics: no such image: {p}", file=sys.stderr)
            return 2
        reports.append(analyse(p, args))
    gate = set((args.gate or args.checks).split(","))
    gated = all(r[k]["pass"] for r in reports for k in gate if k in r)
    doc = {"tool": "tools/qa/metrics.py", "version": 1, "gate": sorted(gate), "images": reports,
           "pass": all(r["pass"] for r in reports), "gated_pass": gated}
    text = json.dumps(doc, indent=2)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(text + "\n", encoding="utf-8")
    print(text)
    for r in reports:
        status = "PASS" if r["pass"] else "FAIL"
        parts = [f"{k}={'ok' if r[k]['pass'] else 'FAIL'}" for k in ("v2", "banding", "contrast") if k in r]
        print(f"metrics: {status} {r['image']} " + " ".join(parts), file=sys.stderr)
    return 0 if gated or args.no_fail else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
