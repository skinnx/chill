#!/usr/bin/env bash
# Vendor the pinned, pure-GDScript addons into addons/ (synthesis D5, report 03 §2).
# Usage: tools/vendor_addons.sh   (run from the repo root; re-run after bumping a pin)
#
# Each addon is cloned at an exact tag, the checked-out commit must equal the pinned SHA,
# C#/test/example payloads are dropped, and the pin is recorded in addons/VENDORED.txt.
# Addons are dev-only: every export preset excludes them (export_presets.cfg exclude_filter).
set -euo pipefail

cd "$(dirname "$0")/.."

vendor() {  # <owner/repo> <tag> <expected commit sha> <subdir in repo>
	local tmp
	tmp=$(mktemp -d)
	git -c advice.detachedHead=false clone -q --depth 1 --branch "$2" "https://github.com/$1.git" "$tmp"
	local got
	got=$(git -C "$tmp" rev-parse HEAD)
	if [ "$got" != "$3" ]; then
		echo "SHA mismatch for $1@$2: expected $3, got $got" >&2
		rm -rf "$tmp"
		exit 1
	fi
	local name
	name=$(basename "$4")
	rm -rf "addons/$name"
	mkdir -p addons
	cp -r "$tmp/$4" "addons/$name"
	find "addons/$name" \( -name '*.cs' -o -name '*.csproj' -o -name '*.sln' \) -delete
	rm -rf "addons/$name/test" "addons/$name/tests" "addons/$name/examples" \
		"addons/$name/screenshots" "addons/$name/video_thumbnails"
	if [ -f "$tmp/LICENSE.md" ]; then cp "$tmp/LICENSE.md" "addons/$name/LICENSE.md"; fi
	if [ -f "$tmp/LICENSE" ]; then cp "$tmp/LICENSE" "addons/$name/LICENSE"; fi
	echo "$1 $2 $3" >> addons/VENDORED.txt
	rm -rf "$tmp"
	echo "vendored $1 $2 ($3) -> addons/$name"
}

mkdir -p addons
: > addons/VENDORED.txt
vendor bitwes/Gut v9.7.1 aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605 addons/gut
# Optional, only if adopted later by ADR (03 §2):
# vendor derkork/godot-statecharts v0.22.5 76d226a3efac66a72aea825382b320c94808f409 addons/godot_state_charts
