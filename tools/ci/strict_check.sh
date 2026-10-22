#!/usr/bin/env bash
# Compile every GDScript with the four synthesis warnings (§3: untyped_declaration,
# unsafe_call_argument, unsafe_method_access, unsafe_property_access) promoted from 1 (warn) to
# 2 (error), so CI fails on any new warning.
#
# The check runs on a throw-away copy of the project (with its .godot import cache), so the
# promotion never touches the real project.godot and never leaks into a Godot process a teammate
# starts in the same checkout meanwhile. An interrupted run leaves nothing behind in the repo.
# Usage: tools/ci/strict_check.sh   (repo root; needs `godot` 4.7.2 on PATH or $GODOT, run --import first)
set -euo pipefail
cd "$(dirname "$0")/../.."
[ -d .godot ] || { echo "strict_check: no .godot import cache; run godot --headless --path . --import first" >&2; exit 2; }
work=$(mktemp -d)
log=$(mktemp)
trap 'rm -rf "$work" "$log"' EXIT
tar -cf - --exclude=./.git --exclude=./build --exclude=./qa --exclude=./reports \
	--exclude=./tools/qa/web/node_modules --exclude='__pycache__' . | tar -xf - -C "$work"
sed -i -E 's#^(gdscript/warnings/(untyped_declaration|unsafe_call_argument|unsafe_method_access|unsafe_property_access))=1#\1=2#' \
	"$work/project.godot"
promoted=$(grep -cE '^gdscript/warnings/(untyped_declaration|unsafe_call_argument|unsafe_method_access|unsafe_property_access)=2' \
	"$work/project.godot" || true)
[ "$promoted" -eq 4 ] || { echo "strict_check: expected 4 warning settings at 1 in project.godot, promoted $promoted" >&2; exit 2; }
"${GODOT:-godot}" --headless --path "$work" -s res://tools/ci/check_scripts.gd > "$log" 2>&1 || true
# Vendored addons are excluded by directory_rules; tools/audio is owned by the audio pipeline.
errors=$(grep -A1 -E "Parse Error|Compile Error" "$log" | grep -E "at: .*res://(scripts|tests|tools/ci|tools/qa|tools/ui)/" || true)
summary=$(grep -E "^check_scripts: " "$log" || true)
[ -n "$summary" ] || { cat "$log"; echo "strict_check: check_scripts.gd did not run" >&2; exit 1; }
echo "$summary"
if [ -n "$errors" ]; then
	grep -E "Parse Error|Compile Error" "$log" | sort | uniq -c
	echo "$errors"
	exit 1
fi
echo "strict_check: no warnings or errors"
