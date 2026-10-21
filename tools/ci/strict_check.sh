#!/usr/bin/env bash
# Compile every GDScript with the four synthesis warnings (§3: untyped_declaration,
# unsafe_call_argument, unsafe_method_access, unsafe_property_access) promoted from 1 (warn) to
# 2 (error), so CI fails on any new warning. project.godot is restored on exit, whatever happens.
# Usage: tools/ci/strict_check.sh   (repo root; needs `godot` 4.7.2 on PATH or $GODOT, run --import first)
set -euo pipefail
cd "$(dirname "$0")/../.."
backup=$(mktemp)
cp project.godot "$backup"
trap 'cp "$backup" project.godot; rm -f "$backup"' EXIT
sed -i -E 's#^(gdscript/warnings/(untyped_declaration|unsafe_call_argument|unsafe_method_access|unsafe_property_access))=1#\1=2#' project.godot
log=$(mktemp)
"${GODOT:-godot}" --headless --path . -s res://tools/ci/check_scripts.gd > "$log" 2>&1 || true
# Vendored addons are excluded by directory_rules; tools/audio is owned by the audio pipeline.
errors=$(grep -A1 -E "Parse Error|Compile Error" "$log" | grep -E "at: .*res://(scripts|tests|tools/ci|tools/qa|tools/ui)/" || true)
tail -1 "$log"
if [ -n "$errors" ]; then
	grep -E "Parse Error|Compile Error" "$log" | sort | uniq -c
	echo "$errors"
	exit 1
fi
echo "strict_check: no warnings or errors"
