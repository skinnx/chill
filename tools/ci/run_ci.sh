#!/usr/bin/env bash
# The CI gates as one script, shared by .github/workflows/ci.yml and local runs, so a green local
# run means a green CI run (synthesis D14; docs/QA.md §1). Stages run in the order given.
#
#   tools/ci/run_ci.sh <stage>...      e.g. tools/ci/run_ci.sh lint data import strict test
#   tools/ci/run_ci.sh all             every stage except export
#
# Stages
#   lint       gdlint (gdtoolkit 4.5.0, .gdlintrc) over every project script; addons excluded
#   data       content lint, Art Bible colour rules, font coverage, fast economy gate (E5/E6)
#   import     headless import on this checkout; any ERROR/WARNING line fails
#   strict     every script compiles with the four synthesis warnings promoted to errors
#   test       GUT, JUnit XML in reports/junit.xml
#   smoke      boot -> main, 300 frames headless; any error or leak fails
#   audio      Xvfb audio smoke: every cue and audio state (tools/qa/audio_smoke.gd)
#   visual     opengl3_es determinism double render, D13 golden-size stills, V2/banding/contrast
#              metrics, golden comparison when goldens exist (qa/goldens/<driver>-mesa<ver>)
#   export     Web (nothreads, release) + Android debug APK (arm64) into build/, verified
#
# Environment: GODOT (default godot), PYTHON (default python3), REPORTS (default reports).
# Needs: Godot 4.7.2 on PATH (tools/ci/install_godot.sh), pip install -r tools/ci/requirements.txt,
# xvfb-run + ImageMagick (audio, visual), export templates (tools/ci/fetch_templates.py), JDK 17+
# and an Android SDK with build-tools (export; keystore via GODOT_ANDROID_KEYSTORE_DEBUG_*).
set -euo pipefail
cd "$(dirname "$0")/../.."

GODOT=${GODOT:-godot}
PYTHON=${PYTHON:-python3}
REPORTS=${REPORTS:-reports}
export GODOT PYTHON
VISUAL_OUT=qa/out/ci
# D13 golden sizes (16:9, 20:9, 4:3 tablet) + the 1080x2400 rater size.
GOLDEN_SIZES=(540x960 540x1200 720x960)
# Gate on these metrics now; V2 reports only until the look spike lands real art (docs/QA.md §4).
METRICS_GATE=banding,contrast
# Web exports must stay small enough for a phone browser demo (synthesis R12); generous ceiling.
WEB_MAX_BYTES=$((80 * 1024 * 1024))
APK_MAX_BYTES=$((80 * 1024 * 1024))

log() { printf '\n== %s\n' "$*"; }

# Fails if a Godot log has engine/script errors or leak reports. <log file>
check_log() {
	if grep -nE "SCRIPT ERROR|^ERROR:|^WARNING:|leaked at exit|still in use at exit" "$1"; then
		echo "run_ci: problems in $1" >&2
		return 1
	fi
}

# A throw-away user:// so no save or settings from a previous step leak into the next one.
with_profile() {
	local profile status=0
	profile=$(mktemp -d)
	XDG_DATA_HOME="$profile/data" XDG_CACHE_HOME="$profile/cache" "$@" || status=$?
	rm -rf "$profile"
	return "$status"
}

stage_lint() {
	log "lint: gdlint $(gdlint --version 2>/dev/null || echo '(missing)')"
	gdlint .
}

stage_data() {
	log "data: content, colour rules, fonts, economy"
	"$PYTHON" -I tools/sim/validate_content.py
	"$PYTHON" -I tools/art/art_data.py check
	"$PYTHON" -I tools/fonts/build_fonts.py --check
	"$PYTHON" -I tools/sim/economy_sim.py --players 500 --reference 200 | tail -3
	"$PYTHON" -I tools/qa/metrics.py --selftest | tail -1
}

stage_import() {
	log "import: $("$GODOT" --headless --version)"
	mkdir -p "$REPORTS"
	"$GODOT" --headless --path . --import > "$REPORTS/import.log" 2>&1
	check_log "$REPORTS/import.log"
	echo "import: clean"
}

stage_strict() {
	log "strict: compile every script, warnings as errors"
	tools/ci/strict_check.sh
}

stage_test() {
	log "test: GUT"
	mkdir -p "$REPORTS"
	with_profile "$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs \
		-gexit -gjunit_xml_file="res://$REPORTS/junit.xml" | tee "$REPORTS/gut.log" | tail -12
	# GUT's exit code is lost in the pipe: re-check its summary.
	grep -q "All tests passed" "$REPORTS/gut.log"
}

stage_smoke() {
	log "smoke: boot -> main, 300 frames headless"
	mkdir -p "$REPORTS"
	with_profile "$GODOT" --headless --path . --quit-after 300 -- --no-save > "$REPORTS/smoke.log" 2>&1
	check_log "$REPORTS/smoke.log"
	echo "smoke: clean"
}

stage_audio() {
	log "audio: Xvfb audio smoke"
	mkdir -p "$REPORTS"
	with_profile timeout 900 xvfb-run -a "$GODOT" --path . --rendering-driver opengl3_es --audio-driver Dummy \
		--resolution 270x480 --fixed-fps 30 -s res://tools/qa/audio_smoke.gd -- --no-save > "$REPORTS/audio_smoke.log" 2>&1
	check_log "$REPORTS/audio_smoke.log"
	grep "^audio_smoke:" "$REPORTS/audio_smoke.log"
}

stage_visual() {
	log "visual: determinism, stills, metrics, goldens"
	rm -rf "$VISUAL_OUT"
	mkdir -p "$VISUAL_OUT"
	tools/qa/capture.sh determinism --animate --frames=120 --tod=0.62 --weather=breeze
	cp qa/out/determinism/result.json "$VISUAL_OUT/determinism.json"
	local shots=()
	local s
	for s in "${GOLDEN_SIZES[@]}"; do
		tools/qa/capture.sh still --size="$s" --seed=7 --tod=0.4 --weather=clear --out="$VISUAL_OUT/day_$s.png"
		shots+=("$VISUAL_OUT/day_$s.png")
	done
	tools/qa/capture.sh still --size=1080x2400 --seed=7 --tod=0.6 --weather=clear --out="$VISUAL_OUT/golden_1080x2400.png"
	tools/qa/capture.sh still --size=1080x2400 --seed=7 --tod=1.0 --weather=clear --out="$VISUAL_OUT/night_1080x2400.png"
	shots+=("$VISUAL_OUT/golden_1080x2400.png" "$VISUAL_OUT/night_1080x2400.png")
	"$PYTHON" -I tools/qa/metrics.py --gate "$METRICS_GATE" --json "$VISUAL_OUT/metrics.json" "${shots[@]}" > /dev/null
	tools/qa/contact_sheet.sh -o "$VISUAL_OUT/contact_sheet.png" -c 5 -t "CI snapshots" "${shots[@]}"
	local mesa
	mesa=$("$PYTHON" -c 'import json,re,sys; v=json.load(open(sys.argv[1]))["adapter_version"]; m=re.search(r"Mesa (\d+\.\d+)", v); print(m.group(1) if m else "unknown")' \
		"$VISUAL_OUT/day_540x960.png.json")
	tools/qa/compare_goldens.sh "$VISUAL_OUT" "qa/goldens/opengl3_es-mesa$mesa"
}

stage_export() {
	log "export: Web + Android debug"
	mkdir -p "$REPORTS"
	"$PYTHON" -I tools/ci/fetch_templates.py --verify
	rm -rf build/web build/android
	mkdir -p build/web build/android
	"$GODOT" --headless --path . --export-release "Web" build/web/index.html > "$REPORTS/export_web.log" 2>&1
	check_log "$REPORTS/export_web.log"
	"$GODOT" --headless --path . --export-debug "Android Debug" build/android/mossling-meadow-debug.apk \
		> "$REPORTS/export_android.log" 2>&1
	check_log "$REPORTS/export_android.log"
	test -s build/web/index.wasm && test -s build/web/index.pck && test -s build/android/mossling-meadow-debug.apk
	local web apk
	web=$(du -sb build/web | cut -f1)
	apk=$(stat -c %s build/android/mossling-meadow-debug.apk)
	[ "$web" -le "$WEB_MAX_BYTES" ] || { echo "run_ci: Web build $web B > $WEB_MAX_BYTES B" >&2; return 1; }
	[ "$apk" -le "$APK_MAX_BYTES" ] || { echo "run_ci: APK $apk B > $APK_MAX_BYTES B" >&2; return 1; }
	# Dev-only content must not ship (synthesis D5, export_presets.cfg exclude_filter).
	if unzip -l build/android/mossling-meadow-debug.apk | grep -qE "assets/(addons|tests|tools|docs|qa)/"; then
		echo "run_ci: dev-only files in the APK" >&2
		return 1
	fi
	if grep -aqE "res://(addons/gut|tests|tools)/" build/web/index.pck; then
		echo "run_ci: dev-only files in the Web pack" >&2
		return 1
	fi
	if command -v apksigner > /dev/null; then
		apksigner verify build/android/mossling-meadow-debug.apk
	fi
	unzip -l build/android/mossling-meadow-debug.apk | grep -E " lib/" | awk '{print $4}'
	echo "export: web $web B, apk $apk B"
}

[ "$#" -gt 0 ] || { sed -n '2,24p' "$0"; exit 2; }
mkdir -p "$REPORTS"
touch "$REPORTS/.gdignore"  # logs and JUnit XML are never imported as project files
stages=()
for st in "$@"; do
	if [ "$st" = all ]; then stages+=(lint data import strict test smoke audio visual); else stages+=("$st"); fi
done
for st in "${stages[@]}"; do
	case $st in
		lint | data | import | strict | test | smoke | audio | visual | export) "stage_$st" ;;
		*) echo "run_ci: unknown stage '$st'" >&2; exit 2 ;;
	esac
done
log "run_ci: ${stages[*]}: all passed"
