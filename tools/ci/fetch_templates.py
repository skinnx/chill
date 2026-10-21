#!/usr/bin/env python3
"""Fetch only the Godot export templates we need, verified (synthesis D14; 03 §7, Appendix A).

The official templates archive (Godot_v4.7.2-stable_export_templates.tpz) is 1.28 GB; we need
~150 MB of it. GitHub's release CDN serves explicit byte ranges (HTTP 206; suffix ranges are
refused with 501), so this script reads the zip's central directory with two small range
requests and then downloads just the members below.

Every member is verified twice: the zip CRC32 and size from the official archive, and a SHA-256
pinned in this file. The pins were computed from members whose CRC32 and size matched the
official 4.7.2-stable archive (whose SHA-512, also pinned below and in SHA512-SUMS.txt, was
checked by the full-download path). A ranged download therefore cannot hand us a different
file than the full, SHA-512-verified archive would have.

Usage:
    tools/ci/fetch_templates.py [--dest DIR]           # ranged fetch of the pinned members
    tools/ci/fetch_templates.py --full [--dest DIR]    # whole .tpz, SHA-512 checked, then extract
    tools/ci/fetch_templates.py --verify [--dest DIR]  # check an existing install, no network
Default DIR: ~/.local/share/godot/export_templates/4.7.2.stable (where the editor looks).
Standard library only; honours HTTPS_PROXY and SSL_CERT_FILE.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import struct
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile
import zlib
from pathlib import Path

VERSION = "4.7.2"
BASE = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable"
TPZ = f"Godot_v{VERSION}-stable_export_templates.tpz"
TPZ_SHA512 = (
    "ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5"
    "f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079"
)
DEFAULT_DEST = Path.home() / ".local/share/godot/export_templates" / f"{VERSION}.stable"

# Member -> pinned SHA-256 of its uncompressed bytes (see the module docstring).
MEMBERS = {
    "templates/version.txt": "38885c88f75abbc797a1db7559719800279a00cfb9fa8b2e2868a7f6f84bad2e",
    "templates/android_debug.apk": "59e0073f0fa59f552684a861d8f4266b0b34b488a140d6657eac7dd70d1a0a0d",
    "templates/web_nothreads_debug.zip": "08962aefef811b603541d7951ac67ef00413aad2d978855183c28adee98f626a",
    "templates/web_nothreads_release.zip": "d3ee2f08cef0cf3cf6678a6355a92a8db48ccdd35cbd2e8bfd5f0e8a0b4032a0",
}

TAIL_BYTES = 65536
EOCD_SIG = b"PK\x05\x06"
CHUNK = 1 << 20
RETRIES = 4


def _open(req: urllib.request.Request):
    for attempt in range(RETRIES):
        try:
            return urllib.request.urlopen(req, timeout=120)
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            if attempt == RETRIES - 1:
                raise
            wait = 2 ** attempt
            print(f"fetch_templates: {e}; retrying in {wait} s", file=sys.stderr)
            time.sleep(wait)
    raise AssertionError("unreachable")


def _range(url: str, a: int, b: int) -> bytes:
    req = urllib.request.Request(url, headers={"Range": f"bytes={a}-{b}"})
    with _open(req) as f:
        if f.status != 206:
            raise RuntimeError(f"server ignored the range request (HTTP {f.status})")
        data = f.read()
    if len(data) != b - a + 1:
        raise RuntimeError(f"short range read {len(data)} != {b - a + 1}")
    return data


def _size(url: str) -> int:
    with _open(urllib.request.Request(url, method="HEAD")) as f:
        return int(f.headers["Content-Length"])


def central_directory(url: str) -> dict[str, tuple[int, int, int, int, int]]:
    """name -> (method, crc32, compressed size, uncompressed size, local header offset)."""
    size = _size(url)
    tail = _range(url, max(0, size - TAIL_BYTES), size - 1)
    eocd = tail.rfind(EOCD_SIG)
    if eocd < 0:
        raise RuntimeError("no end-of-central-directory record (zip64 archives are not supported)")
    _, _, _, _, n, cd_size, cd_off, _ = struct.unpack("<IHHHHIIH", tail[eocd:eocd + 22])
    cd = _range(url, cd_off, cd_off + cd_size - 1)
    entries: dict[str, tuple[int, int, int, int, int]] = {}
    p = 0
    for _ in range(n):
        (sig, _, _, _, method, _, _, crc, csize, usize, nlen, xlen, clen, _, _, _, lho) = struct.unpack(
            "<IHHHHHHIIIHHHHHII", cd[p:p + 46])
        if sig != 0x02014B50:
            raise RuntimeError("corrupt central directory")
        entries[cd[p + 46:p + 46 + nlen].decode()] = (method, crc, csize, usize, lho)
        p += 46 + nlen + xlen + clen
    return entries


def _check(name: str, data: bytes, crc: int | None, usize: int | None) -> None:
    if usize is not None and len(data) != usize:
        raise RuntimeError(f"{name}: size {len(data)} != {usize}")
    if crc is not None and zlib.crc32(data) != crc:
        raise RuntimeError(f"{name}: CRC32 mismatch")
    want = MEMBERS[name]
    got = hashlib.sha256(data).hexdigest()
    if got != want:
        raise RuntimeError(f"{name}: SHA-256 {got} != pinned {want}")


def fetch_ranged(dest: Path) -> None:
    url = f"{BASE}/{TPZ}"
    entries = central_directory(url)
    dest.mkdir(parents=True, exist_ok=True)
    for name in MEMBERS:
        method, crc, csize, usize, lho = entries[name]
        nlen, xlen = struct.unpack("<HH", _range(url, lho, lho + 29)[26:30])
        start = lho + 30 + nlen + xlen
        raw = _range(url, start, start + csize - 1) if csize else b""
        if method == zipfile.ZIP_DEFLATED:
            data = zlib.decompress(raw, -15)
        elif method == zipfile.ZIP_STORED:
            data = raw
        else:
            raise RuntimeError(f"{name}: unsupported compression method {method}")
        _check(name, data, crc, usize)
        (dest / Path(name).name).write_bytes(data)
        print(f"fetch_templates: {name} {usize} B ok")


def fetch_full(dest: Path) -> None:
    url = f"{BASE}/{TPZ}"
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / TPZ
        h = hashlib.sha512()
        with _open(urllib.request.Request(url)) as f, open(path, "wb") as out:
            while chunk := f.read(CHUNK):
                h.update(chunk)
                out.write(chunk)
        if h.hexdigest() != TPZ_SHA512:
            raise RuntimeError(f"{TPZ}: SHA-512 mismatch")
        print(f"fetch_templates: {TPZ} SHA-512 ok")
        dest.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(path) as z:
            for name in MEMBERS:
                info = z.getinfo(name)
                data = z.read(name)
                _check(name, data, info.CRC, info.file_size)
                (dest / Path(name).name).write_bytes(data)
                print(f"fetch_templates: {name} {info.file_size} B ok")


def verify(dest: Path, quiet: bool = False) -> bool:
    ok = True
    for name, want in MEMBERS.items():
        p = dest / Path(name).name
        if not p.is_file():
            if not quiet:
                print(f"fetch_templates: missing {p}", file=sys.stderr)
            ok = False
            continue
        got = hashlib.sha256(p.read_bytes()).hexdigest()
        if got != want:
            if not quiet:
                print(f"fetch_templates: {p} SHA-256 {got} != pinned {want}", file=sys.stderr)
            ok = False
    return ok


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Fetch the pinned Godot export templates.")
    ap.add_argument("--dest", type=Path, default=DEFAULT_DEST)
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--full", action="store_true", help="download the whole .tpz and check its SHA-512")
    mode.add_argument("--verify", action="store_true", help="only verify an existing install")
    args = ap.parse_args(argv)
    dest = args.dest.expanduser()
    if args.verify:
        ok = verify(dest)
        print("fetch_templates: verify", "ok" if ok else "FAILED")
        return 0 if ok else 1
    if verify(dest, quiet=True):
        print(f"fetch_templates: {dest} already holds the pinned templates")
        return 0
    try:
        fetch_full(dest) if args.full else fetch_ranged(dest)
    except (RuntimeError, urllib.error.URLError, OSError) as e:
        print(f"fetch_templates: FAILED: {e}", file=sys.stderr)
        return 1
    return 0 if verify(dest) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
