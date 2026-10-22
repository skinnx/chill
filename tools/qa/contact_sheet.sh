#!/usr/bin/env bash
# Tiles screenshots into one reviewer sheet (ImageMagick montage). docs/QA.md §5.
#
#   tools/qa/contact_sheet.sh [-o out.png] [-c columns] [-w tile_width] [-t title] img.png ...
#
# Each tile is labelled with the file name and, when tools/qa/capture.gd wrote a sidecar
# (<img>.json), the phase, weather, g_day, size and driver, so a reviewer always knows what a
# frame shows. Tiles keep their aspect ratio. The sheet is for overview only: raters score the
# full-size stills at 1:1 (grain and dither vanish when scaled down, 05 §6). A gradient that bands
# on the sheet but not in the still is a scaling artefact; metrics.py checks the stills.
set -euo pipefail

out=qa/out/contact_sheet.png
cols=3
tile_w=360
title=""
while getopts "o:c:w:t:h" opt; do
	case $opt in
		o) out=$OPTARG ;;
		c) cols=$OPTARG ;;
		w) tile_w=$OPTARG ;;
		t) title=$OPTARG ;;
		*) sed -n '2,9p' "$0"; exit 2 ;;
	esac
done
shift $((OPTIND - 1))
[ "$#" -gt 0 ] || { echo "contact_sheet.sh: no images" >&2; exit 2; }

# UI surface and ink tokens (data/palettes.json ui.surface / ui.ink).
bg='#F0EEE9'
ink='#2A2838'
font=DejaVu-Sans
convert -list font 2>/dev/null | grep -q "Font: $font$" || font=""

label_for() {
	local img=$1 side="$1.json"
	local name
	name=$(basename "$img" .png)
	if [ -f "$side" ]; then
		python3 -I - "$side" "$name" <<-'PY'
		import json, sys
		m = json.load(open(sys.argv[1], encoding="utf-8"))
		w, h = m.get("image_size", [0, 0])
		print(f"{sys.argv[2]}\n{m.get('phase', '?')} · {m.get('weather', '?')} · g_day {m.get('g_day', 0):.2f}"
		      f"\n{w}x{h} · {m.get('driver', '?')}")
		PY
	else
		echo "$name"
	fi
}

args=()
for img in "$@"; do
	[ -f "$img" ] || { echo "contact_sheet.sh: no such image $img" >&2; exit 2; }
	args+=(-label "$(label_for "$img")" "$img")
done
mkdir -p "$(dirname "$out")"
font_args=()
[ -n "$font" ] && font_args=(-font "$font")
title_args=()
[ -n "$title" ] && title_args=(-title "$title")
# Downscaling averages the shaders' +-1 LSB dither away, and writing the 16-bit result straight to
# 8 bits would then *create* bands that are not in the frames. Montage at 16 bits, then requantise
# to 8 bits through an ordered dither, so the sheet shows what the full-size stills show.
tmp=$(mktemp --suffix=.png)
trap 'rm -f "$tmp"' EXIT
montage -background "$bg" -fill "$ink" "${font_args[@]}" -pointsize 16 "${title_args[@]}" \
	"${args[@]}" -tile "${cols}x" -geometry "${tile_w}x+16+16" -depth 16 "PNG48:$tmp"
convert "$tmp" -ordered-dither o8x8,256 -depth 8 "$out"
echo "contact_sheet: $out ($# images, $(identify -format '%wx%h' "$out"))"
