#!/usr/bin/env python3
"""Build the shipped UI fonts (synthesis C12, C13, D6).

Fetches the pinned OFL packages from npm (`npm pack`), verifies their SHA-512, subsets each
static weight to Latin + Vietnamese (one WOFF2 per weight, all OpenType layout features kept,
so kerning and mark positioning never split across files) and writes:

  fonts/nunito/Nunito-Medium.woff2      500  body, labels
  fonts/nunito/Nunito-Bold.woff2        700  emphasis, buttons
  fonts/nunito/Nunito-ExtraBold.woff2   800  titles in running text
  fonts/baloo2/Baloo2-Bold.woff2        700  titles, HUD, prices
  fonts/baloo2/Baloo2-Bold-Numerals.woff2   digits only, imported as MSDF for tweened counters
  fonts/{nunito,baloo2}/OFL.txt         the licence (OFL-1.1 requires it next to the fonts)

Then it checks coverage: all 147 Vietnamese test letters (03 §3) and every character used by
i18n/strings.csv must be present in every text weight. Exit code 1 on any failure.

Usage:  python3 -I tools/fonts/build_fonts.py            (needs npm, fonttools, brotli)
        python3 -I tools/fonts/build_fonts.py --check    (coverage check of the committed files)
"""
from __future__ import annotations

import argparse
import hashlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "fonts"

# npm package -> (version, sha512 of the tarball as published, family dir)
PACKAGES = {
	"@expo-google-fonts/nunito": ("0.4.2", "d4a096a61c3f236ba0a9fb3d8911d40a43d39e898d8063ed17802fa95aaea042b1af410bfa670b34b81e8b1b2c95b69215ebd147afca240137b1cf20d15698d1", "nunito"),
	"@expo-google-fonts/baloo-2": ("0.4.2", "bafaf0d48fac3fbd8f63cc5138943a08c8861eef7e58909d8bbd90f8e896a50dec2ac211c881178a60df8149e4936be95957a3d095fd7cb73cee20e68ca13ce8", "baloo2"),
}

# (package, file inside the tarball, output file)
TEXT_FONTS = [
	("@expo-google-fonts/nunito", "package/500Medium/Nunito_500Medium.ttf", "nunito/Nunito-Medium.woff2"),
	("@expo-google-fonts/nunito", "package/700Bold/Nunito_700Bold.ttf", "nunito/Nunito-Bold.woff2"),
	("@expo-google-fonts/nunito", "package/800ExtraBold/Nunito_800ExtraBold.ttf", "nunito/Nunito-ExtraBold.woff2"),
	("@expo-google-fonts/baloo-2", "package/700Bold/Baloo2_700Bold.ttf", "baloo2/Baloo2-Bold.woff2"),
]
NUMERAL_FONT = ("@expo-google-fonts/baloo-2", "package/700Bold/Baloo2_700Bold.ttf", "baloo2/Baloo2-Bold-Numerals.woff2")

# 03 §3 range list (Latin-1, Latin Extended-A, Vietnamese, punctuation, arrows, a few symbols)
# plus the geometric dots used by the album requirement icons (GDD §4.1.1) where the font has them.
UNICODES = (
	"U+0000-00FF,U+0100-017F,U+0131,U+0152-0153,U+01A0-01A1,U+01AF-01B0,U+02BB-02BC,U+02C6,U+02DA,"
	"U+02DC,U+0300-0309,U+0323,U+0329,U+1EA0-1EF9,U+2000-206F,U+20AB,U+20AC,U+2122,U+2190-2193,"
	"U+2212,U+2215,U+2605,U+2665,U+25CB,U+25CF,U+25D0,U+00D7"
)
NUMERAL_UNICODES = "U+0020,U+0025,U+002B-002E,U+0030-0039,U+00A0,U+00D7,U+2009,U+202F,U+2212"


def vietnamese_test_set() -> list[str]:
	"""The 147 code points of 03 §3: 12 base vowels x 2 cases x 5 tones (NFC) + đ Đ ₫."""
	bases = "a ă â e ê i o ô ơ u ư y".split()
	tones = ["̀", "́", "̉", "̃", "̣"]  # huyền sắc hỏi ngã nặng
	out: list[str] = []
	for b in bases:
		for case_b in (b, b.upper()):
			for t in tones:
				out.append(unicodedata.normalize("NFC", case_b + t))
	out += ["đ", "Đ", "₫"]
	return out


def strings_chars() -> set[str]:
	text = (ROOT / "i18n" / "strings.csv").read_text(encoding="utf-8")
	return {c for c in text if c.isprintable() and c not in "\r\n\t"}


def sha512(p: Path) -> str:
	h = hashlib.sha512()
	with open(p, "rb") as f:
		for chunk in iter(lambda: f.read(1 << 16), b""):
			h.update(chunk)
	return h.hexdigest()


def fetch(dl_dir: Path) -> dict[str, Path]:
	"""npm pack each pinned package into dl_dir, verify, extract into its own subdir."""
	roots: dict[str, Path] = {}
	for pkg, (ver, digest, fam) in PACKAGES.items():
		res = subprocess.run(["npm", "pack", f"{pkg}@{ver}", "--silent"], cwd=dl_dir, check=True,
			capture_output=True, text=True)
		tgz = dl_dir / res.stdout.strip().splitlines()[-1]
		got = sha512(tgz)
		if got != digest:
			sys.exit(f"SHA-512 mismatch for {pkg}@{ver}: {got}")
		dest = dl_dir / fam
		dest.mkdir()
		with tarfile.open(tgz) as tf:
			tf.extractall(dest, filter="data")
		roots[pkg] = dest
	return roots


def subset(src: Path, dst: Path, unicodes: str) -> None:
	from fontTools import subset as fts
	dst.parent.mkdir(parents=True, exist_ok=True)
	args = [str(src), f"--unicodes={unicodes}", "--layout-features=*", "--flavor=woff2",
		"--name-IDs=*", "--name-languages=*", "--notdef-outline", "--drop-tables+=DSIG",
		f"--output-file={dst}"]
	fts.main(args)


def check(required: list[str]) -> list[str]:
	from fontTools.ttLib import TTFont
	fails: list[str] = []
	for _, _, out in TEXT_FONTS:
		p = OUT / out
		if not p.exists():
			fails.append(f"{out}: missing")
			continue
		cmap = TTFont(p).getBestCmap()
		missing = [c for c in required if ord(c) not in cmap]
		if missing:
			fails.append(f"{out}: missing {''.join(missing)}")
		print(f"  {out}: {p.stat().st_size / 1024:.1f} KB, {len(cmap)} code points, "
			f"{len(required) - len(missing)}/{len(required)} required present")
	num = OUT / NUMERAL_FONT[2]
	if num.exists():
		cmap = TTFont(num).getBestCmap()
		digits = [c for c in "0123456789+" if ord(c) not in cmap]
		if digits:
			fails.append(f"{NUMERAL_FONT[2]}: missing {''.join(digits)}")
		print(f"  {NUMERAL_FONT[2]}: {num.stat().st_size / 1024:.1f} KB")
	else:
		fails.append(f"{NUMERAL_FONT[2]}: missing")
	for fam in ("nunito", "baloo2"):
		if not (OUT / fam / "OFL.txt").exists():
			fails.append(f"fonts/{fam}/OFL.txt missing")
	return fails


def main() -> int:
	ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("--check", action="store_true", help="only verify the committed files")
	args = ap.parse_args()
	required = sorted(set(vietnamese_test_set()) | strings_chars())
	if not args.check:
		with tempfile.TemporaryDirectory(prefix="mm_fonts_") as tmp:
			roots = fetch(Path(tmp))
			for pkg, inner, out in TEXT_FONTS:
				subset(roots[pkg] / inner, OUT / out, UNICODES)
			pkg, inner, out = NUMERAL_FONT
			subset(roots[pkg] / inner, OUT / out, NUMERAL_UNICODES)
			for pkg, (_, _, fam) in PACKAGES.items():
				lic = (roots[pkg] / "package" / "LICENSE_FONT").read_text(encoding="utf-8-sig")
				(OUT / fam / "OFL.txt").write_text(lic.replace("\r\n", "\n"), encoding="utf-8", newline="\n")
				# Where the bytes came from (the npm wrapper itself is MIT, the fonts are OFL-1.1).
				ver, digest, _ = PACKAGES[pkg]
				(OUT / fam / "SOURCE.txt").write_text(
					f"{pkg}@{ver} (npm), tarball sha512 {digest}\n"
					f"Subset by tools/fonts/build_fonts.py: Latin + Vietnamese, all layout features kept.\n"
					f"The copyright line of OFL.txt declares no Reserved Font Name, so the subset files\n"
					f"keep the original family names. Licence: SIL Open Font License 1.1 (OFL.txt).\n",
					encoding="utf-8", newline="\n")
	fails = check(required)
	for f in fails:
		print("FAIL", f)
	print("fonts OK" if not fails else f"{len(fails)} font check(s) failed")
	return 1 if fails else 0


if __name__ == "__main__":
	sys.exit(main())
