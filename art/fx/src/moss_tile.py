#!/usr/bin/env python3
"""Generates art/fx/moss_tile.png: a tileable felted-moss surface (Art Bible §1.1 "needle-felted
diorama", round-2 directive: the meadow reads as a soft felted MOSS meadow).

Channels (linear data, sampled without source_color, mipmapped, repeat):
  R  cushion height 0..1 (two scales of rounded Worley domes: big cushions + small lumps)
  G  screen-space normal x * 0.5 + 0.5 (from the height gradient)
  B  screen-space normal y * 0.5 + 0.5 (y down, like the canvas)
  A  felt fibre noise 0..1 (fine, slightly streaky; the felt grain)

Deterministic (seeded). Run from the repo root:  python3 -I art/fx/src/moss_tile.py
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "art/fx/moss_tile.png"
N = 256
SEED = 20261021


def worley(n: int, count: int, rng: np.random.Generator) -> tuple[np.ndarray, np.ndarray]:
    """Periodic F1, F2 distances (texels) for `count` jittered points on an n x n torus."""
    pts = rng.random((count, 2)) * n
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
    f1 = np.full((n, n), 1e9)
    f2 = np.full((n, n), 1e9)
    for px, py in pts:
        dx = np.abs(xx - px)
        dy = np.abs(yy - py)
        dx = np.minimum(dx, n - dx)
        dy = np.minimum(dy, n - dy)
        d = np.sqrt(dx * dx + dy * dy)
        f2 = np.where(d < f1, f1, np.minimum(f2, d))
        f1 = np.minimum(f1, d)
    return f1, f2


def cushions(n: int, count: int, rng: np.random.Generator, r_range: tuple[float, float]) -> np.ndarray:
    """Union of spherical caps (packed cushions): rounded tops, soft crevices where they meet."""
    pts = rng.random((count, 2)) * n
    spacing = n / np.sqrt(count)
    radii = rng.uniform(r_range[0], r_range[1], count) * spacing
    lift = rng.uniform(0.8, 1.0, count)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
    h = np.zeros((n, n))
    for (px, py), r, s in zip(pts, radii, lift):
        dx = np.abs(xx - px)
        dy = np.abs(yy - py)
        dx = np.minimum(dx, n - dx)
        dy = np.minimum(dy, n - dy)
        q = 1.0 - (dx * dx + dy * dy) / (r * r)
        cap = np.sqrt(np.clip(q, 0.0, 1.0)) * s
        h = np.maximum(h, cap)
    return h


def blur(a: np.ndarray, r: int) -> np.ndarray:
    """Periodic box blur (applied twice ~ gaussian)."""
    out = a
    for _ in range(2):
        acc = np.zeros_like(out)
        for k in range(-r, r + 1):
            acc += np.roll(out, k, axis=1)
        out = acc / (2 * r + 1)
        acc = np.zeros_like(out)
        for k in range(-r, r + 1):
            acc += np.roll(out, k, axis=0)
        out = acc / (2 * r + 1)
    return out


def value_noise(n: int, cells: int, rng: np.random.Generator) -> np.ndarray:
    g = rng.random((cells, cells))
    t = np.arange(n) / n * cells
    i0 = np.floor(t).astype(int)
    f = t - i0
    f = f * f * (3 - 2 * f)
    i1 = (i0 + 1) % cells
    a = g[np.ix_(i0, i0)]
    b = g[np.ix_(i0, i1)]
    c = g[np.ix_(i1, i0)]
    d = g[np.ix_(i1, i1)]
    fx = f[None, :]
    fy = f[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def main() -> int:
    rng = np.random.default_rng(SEED)
    big = cushions(N, 38, rng, (0.68, 0.92))
    small = cushions(N, 140, rng, (0.55, 0.8))
    h = 0.78 * big + 0.22 * small
    h = blur(h, 2)
    h = (h - h.min()) / (h.max() - h.min())
    # Normals from the periodic gradient of a slightly smoothed height (screen space, y down).
    hs = blur(h, 1)
    k = 3.2
    gx = (np.roll(hs, -1, axis=1) - np.roll(hs, 1, axis=1)) * 0.5 * k
    gy = (np.roll(hs, -1, axis=0) - np.roll(hs, 1, axis=0)) * 0.5 * k
    # The normal points down the slope (away from the cushion top): lit where it faces the light.
    nz = 1.0
    ln = np.sqrt(gx * gx + gy * gy + nz * nz)
    nx = -gx / ln
    ny = -gy / ln
    # Felt fibres: fine value noise, stretched a little along x (felt is matted, not isotropic).
    fib = 0.55 * value_noise(N, 64, rng) + 0.3 * value_noise(N, 128, rng) + 0.15 * value_noise(N, 32, rng)
    fib = np.roll(fib, 0, axis=0)
    fib = (fib - fib.min()) / (fib.max() - fib.min())
    img = np.stack([h, nx * 0.5 + 0.5, ny * 0.5 + 0.5, fib], axis=-1)
    img8 = np.clip(np.round(img * 255.0), 0, 255).astype(np.uint8)
    Image.fromarray(img8, "RGBA").save(OUT, optimize=True)
    print(f"wrote {OUT.relative_to(ROOT)} ({N}x{N})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
