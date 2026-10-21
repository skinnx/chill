#!/usr/bin/env python3
"""Generates art/fx/meadow_relief.png: the hollow's gentle ground relief (round-2 directive 3:
"gentle mounds so the ground has relief and the eye is led to the sun-stone focal").

The meadow is a soft bowl: its sides rise toward the left/right frame edges, a few broad moss
mounds sit around the beds and along the near bank, the banks slope into the brook and the floor
around the sun stone (the focal) stays flat and open. Sampled once per meadow fragment
(meadow.gdshaderinc) at 1/8 resolution with linear filtering.

Texel (i, j) covers design px x = X0 + (i + 0.5) * CELL, y = Y0 + (j + 0.5) * CELL.
Channels (linear data):
  R  height 0..1
  G  slope x * 0.5 + 0.5   (screen-space normal = -grad(height) * NORMAL_K, clamped to +-1)
  B  slope y * 0.5 + 0.5
  A  bowl occlusion 0..1 (1 = open floor, lower toward the hollow's walls and the bank crease)

Run from the repo root:  python3 -I art/fx/src/meadow_relief.py
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "art/fx/meadow_relief.png"
SPOTS = ROOT / "data/spots.json"
# Must match shaders/world/meadow.gdshaderinc RELIEF_* constants.
X0, Y0, CELL = -400.0, 700.0, 8.0
W, H = 236, 160  # 1888 x 1280 design px: x -400..1488, y 700..1980
NORMAL_K = 260.0
SEED = 7331

# Broad moss mounds (design px): centre x, y, sigma x, sigma y, amplitude.
MOUNDS = [
    (190, 965, 150, 62, 0.42), (900, 1010, 170, 70, 0.40), (95, 1235, 165, 80, 0.55),
    (1000, 1225, 150, 78, 0.50), (300, 1690, 230, 86, 0.48), (830, 1745, 250, 96, 0.52),
    (560, 1915, 280, 90, 0.30), (705, 875, 110, 42, 0.20), (385, 868, 105, 40, 0.20),
    (1180, 1500, 160, 140, 0.55), (-110, 1520, 170, 150, 0.6), (-60, 900, 170, 120, 0.45),
    (1140, 905, 160, 110, 0.4),
]
FOCAL = (540.0, 1123.0)
BOWL_EDGE = (250.0, 640.0)
BOWL_AMP = 0.38
FOCAL_FLAT = (330.0, 170.0)
BROOK_DIP = 0.30
BROOK_SIGMA = 46.0
NOISE_AMP = 0.10
NOISE_CELL = 110.0


def brook_y(xs: np.ndarray) -> np.ndarray:
    d = json.loads(SPOTS.read_text())
    fw, fh = float(d["frame"]["width_px"]), float(d["frame"]["height_px"])
    pts = sorted(((p[0] * fw, p[1] * fh) for p in d["stream"]["polyline"]), key=lambda q: q[0])
    px = np.array([p[0] for p in pts])
    py = np.array([p[1] for p in pts])
    return np.interp(xs, px, py)


def value_noise(xs: np.ndarray, ys: np.ndarray, cell: float, rng: np.random.Generator) -> np.ndarray:
    g = rng.random((64, 64))
    fx, fy = xs / cell, ys / cell
    ix, iy = np.floor(fx).astype(int), np.floor(fy).astype(int)
    tx, ty = fx - ix, fy - iy
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    def at(i, j):
        return g[j % 64, i % 64]
    a, b, c, d = at(ix, iy), at(ix + 1, iy), at(ix, iy + 1), at(ix + 1, iy + 1)
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


def smoothstep(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def main() -> int:
    rng = np.random.default_rng(SEED)
    xs = X0 + (np.arange(W) + 0.5) * CELL
    ys = Y0 + (np.arange(H) + 0.5) * CELL
    X, Y = np.meshgrid(xs, ys)
    h = np.zeros_like(X)
    # The bowl: the hollow's walls rise toward both frame edges (more toward the bottom corners).
    side = smoothstep(BOWL_EDGE[0], BOWL_EDGE[1], np.abs(X - FOCAL[0]))
    h += BOWL_AMP * side * (0.55 + 0.45 * smoothstep(800.0, 1700.0, Y))
    for cx, cy, sx, sy, a in MOUNDS:
        h += a * np.exp(-0.5 * (((X - cx) / sx) ** 2 + ((Y - cy) / sy) ** 2))
    h += NOISE_AMP * (value_noise(X, Y, NOISE_CELL, rng) - 0.5) * 2.0
    # The focal floor stays open and flat (the eye rests on the sun stone).
    flat = np.exp(-0.5 * (((X - FOCAL[0]) / FOCAL_FLAT[0]) ** 2 + ((Y - FOCAL[1]) / FOCAL_FLAT[1]) ** 2))
    h *= 1.0 - 0.75 * flat
    # The banks slope gently into the brook.
    dy = Y - brook_y(X)
    dip = np.exp(-0.5 * (dy / BROOK_SIGMA) ** 2)
    h -= BROOK_DIP * dip
    lo, hi = h.min(), h.max()
    hn = (h - lo) / (hi - lo)
    gy, gx = np.gradient(h, CELL)
    nx = np.clip(-gx * NORMAL_K, -1.0, 1.0)
    ny = np.clip(-gy * NORMAL_K, -1.0, 1.0)
    # Occlusion: the walls of the bowl and the bank crease sit in a little more shade.
    occ = 1.0 - 0.55 * side * smoothstep(900.0, 1900.0, Y) - 0.35 * dip
    occ = np.clip(occ, 0.0, 1.0)
    img = np.stack([hn, nx * 0.5 + 0.5, ny * 0.5 + 0.5, occ], axis=-1)
    img8 = np.clip(np.round(img * 255.0), 0, 255).astype(np.uint8)
    Image.fromarray(img8, "RGBA").save(OUT, optimize=True)
    print(f"wrote {OUT.relative_to(ROOT)} ({W}x{H}), slope range x {nx.min():.2f}..{nx.max():.2f} "
          f"y {ny.min():.2f}..{ny.max():.2f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
