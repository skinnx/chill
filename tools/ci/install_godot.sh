#!/usr/bin/env bash
# Installs the official Godot 4.7.2-stable Linux editor, SHA-512 verified (synthesis D14, 03 §7).
#
#   tools/ci/install_godot.sh [DIR]     default DIR: ~/godot  ->  DIR/godot (on PATH via GITHUB_PATH)
#
# The archive must match BOTH the SHA-512 pinned below and the line in the release's
# SHA512-SUMS.txt; a mismatch with either aborts before anything is unpacked. Re-running with a
# valid install in DIR is a no-op (CI caches DIR). Export templates: tools/ci/fetch_templates.py.
set -euo pipefail

VERSION=4.7.2
BASE="https://github.com/godotengine/godot-builds/releases/download/${VERSION}-stable"
ZIP="Godot_v${VERSION}-stable_linux.x86_64.zip"
BIN="Godot_v${VERSION}-stable_linux.x86_64"
# From SHA512-SUMS.txt of the 4.7.2-stable release (03 §7, re-checked 2026-10-21).
ZIP_SHA512=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65
EXPECTED_VERSION="${VERSION}.stable.official"

dir=${1:-$HOME/godot}
mkdir -p "$dir"
if [ -x "$dir/godot" ] && "$dir/godot" --headless --version 2>/dev/null | grep -q "^${EXPECTED_VERSION}"; then
	echo "install_godot: $("$dir/godot" --headless --version) already in $dir"
else
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	curl -fsSL --retry 4 --retry-delay 2 -o "$tmp/$ZIP" "$BASE/$ZIP"
	curl -fsSL --retry 4 --retry-delay 2 -o "$tmp/SHA512-SUMS.txt" "$BASE/SHA512-SUMS.txt"
	echo "$ZIP_SHA512  $tmp/$ZIP" | sha512sum -c --quiet -
	listed=$(awk -v f="$ZIP" '$2 == f { print $1 }' "$tmp/SHA512-SUMS.txt")
	[ "$listed" = "$ZIP_SHA512" ] || { echo "install_godot: SHA512-SUMS.txt lists '$listed' for $ZIP" >&2; exit 1; }
	unzip -q -o "$tmp/$ZIP" -d "$tmp"
	mv -f "$tmp/$BIN" "$dir/godot"
	chmod +x "$dir/godot"
	echo "install_godot: installed $("$dir/godot" --headless --version) to $dir (SHA-512 ok)"
fi
if [ -n "${GITHUB_PATH:-}" ]; then
	echo "$dir" >> "$GITHUB_PATH"
fi
