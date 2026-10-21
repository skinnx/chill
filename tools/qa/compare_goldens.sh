#!/usr/bin/env bash
# Golden-image regression check (synthesis D13: ImageMagick AE at fuzz 2 %, fail when more than
# 0.1 % of the pixels differ; 03 §6.2). docs/QA.md §3.4.
#
#   tools/qa/compare_goldens.sh <new_dir> <golden_dir> [--update]
#
# Every <golden_dir>/*.png must have a same-named, same-sized image in <new_dir>. Goldens are
# pinned per renderer AND per Mesa build (llvmpipe output can change between Mesa releases), so
# <golden_dir> is e.g. qa/goldens/opengl3_es-mesa25.2 and is blessed from the CI artifact of the
# runner that compares against it. No golden directory or no goldens yet = skipped, exit 0.
# --update copies the new images over the goldens (QA lead only, after review; record why in the PR).
# Writes <new_dir>/golden_diff/<name>.png highlight images and <new_dir>/golden_report.json.
set -euo pipefail

new=${1:?usage: compare_goldens.sh <new_dir> <golden_dir> [--update]}
gold=${2:?usage: compare_goldens.sh <new_dir> <golden_dir> [--update]}
update=${3:-}
FUZZ=2%
MAX_SHARE=0.001

if [ "$update" = "--update" ]; then
	mkdir -p "$gold"
	n=0
	for f in "$new"/*.png; do
		[ -e "$f" ] || continue
		cp "$f" "$gold/"
		[ -f "$f.json" ] && cp "$f.json" "$gold/"
		n=$((n + 1))
	done
	echo "compare_goldens: blessed $n images into $gold"
	exit 0
fi

shopt -s nullglob
goldens=("$gold"/*.png)
if [ ! -d "$gold" ] || [ ${#goldens[@]} -eq 0 ]; then
	echo "compare_goldens: no goldens in $gold yet - skipped"
	exit 0
fi

mkdir -p "$new/golden_diff"
fail=0
rows=()
for g in "${goldens[@]}"; do
	name=$(basename "$g")
	n="$new/$name"
	if [ ! -f "$n" ]; then
		echo "compare_goldens: MISSING $name (no new capture)" >&2
		rows+=("{\"image\": \"$name\", \"status\": \"missing\"}")
		fail=1
		continue
	fi
	gs=$(identify -format '%wx%h' "$g")
	ns=$(identify -format '%wx%h' "$n")
	if [ "$gs" != "$ns" ]; then
		echo "compare_goldens: SIZE $name golden $gs, new $ns" >&2
		rows+=("{\"image\": \"$name\", \"status\": \"size\", \"golden\": \"$gs\", \"new\": \"$ns\"}")
		fail=1
		continue
	fi
	out=$(compare -metric AE -fuzz "$FUZZ" "$g" "$n" "$new/golden_diff/$name" 2>&1 >/dev/null || true)
	out=${out%% *}
	if ! [[ $out =~ ^[0-9.e+]+$ ]]; then
		echo "compare_goldens: compare failed for $name: $out" >&2
		fail=1
		continue
	fi
	px=$(( ${gs%x*} * ${gs#*x} ))
	ae=$(awk -v v="$out" 'BEGIN { printf "%d", v }')
	limit=$(awk -v p="$px" -v m="$MAX_SHARE" 'BEGIN { printf "%d", p * m }')
	status=pass
	if [ "$ae" -gt "$limit" ]; then
		status=fail
		fail=1
	fi
	printf 'compare_goldens: %-4s %s  %d px differ (limit %d)\n' "$status" "$name" "$ae" "$limit"
	rows+=("{\"image\": \"$name\", \"status\": \"$status\", \"ae_fuzz_2pct\": $ae, \"limit\": $limit}")
done
{
	echo "{\"golden_dir\": \"$gold\", \"fuzz\": \"$FUZZ\", \"max_share\": $MAX_SHARE, \"pass\": $([ $fail -eq 0 ] && echo true || echo false), \"images\": ["
	(IFS=,; echo "${rows[*]}")
	echo "]}"
} > "$new/golden_report.json"
exit $fail
