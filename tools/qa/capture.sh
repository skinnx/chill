#!/usr/bin/env bash
# Visual QA captures under Xvfb on the phone GL path (synthesis C9 opengl3_es, C10, D13).
# Every run gets a throw-away user:// (XDG_DATA_HOME/XDG_CACHE_HOME), so no developer save or
# settings leak into a frame and nothing is written to the real profile. docs/QA.md §3.
#
#   tools/qa/capture.sh still [--size=WxH] [--driver=D] [capture.gd / game args ...]
#       One deterministic still (default 1080x1920, --seed=1). Examples:
#         tools/qa/capture.sh still --tod=0.62 --weather=clear --seed=7 --out=qa/out/golden.png
#         tools/qa/capture.sh still --size=1080x2400 --tod=1.0 --set=language:vi --out=qa/out/night_vi.png
#   tools/qa/capture.sh video [--seconds=S] [--out=DIR] [--png] [game args ...]
#       Movie Maker clip at 30 fps (size from the .movie override in project.godot, 1080x2400),
#       then DIR/clip.mp4 (H.264 + AAC) and DIR/clip.gif. MJPEG AVI by default (~40 ms/frame); --png
#       writes lossless PNG frames + WAV instead (~1.4 s/frame at 1080x2400: short clips only).
#   tools/qa/capture.sh encode <clip.avi | png-frames-dir> [--gif-width=W] [--gif-fps=F]
#       ffmpeg helper: clip.mp4 and clip.gif next to the AVI, or inside the PNG frames directory.
#   tools/qa/capture.sh determinism [--size=WxH] [still args ...]
#       Renders the same still twice in fresh processes and compares them (R5). Writes
#       qa/out/determinism/result.json; exit 1 if more than 0.1 % of pixels differ at fuzz 2 %.
#   tools/qa/capture.sh set [--out-dir=DIR] [--size=WxH]
#       The Art Bible §11.2 rater set that the current build can show (5 phases + day rain), the
#       metrics report and a contact sheet. Default qa/out/set at 1080x2400.
#
# Environment: GODOT (default godot), CAPTURE_TIMEOUT seconds per Godot run (default 900),
# PYTHON (default python3).
set -euo pipefail
cd "$(dirname "$0")/../.."

GODOT=${GODOT:-godot}
PYTHON=${PYTHON:-python3}
CAPTURE_TIMEOUT=${CAPTURE_TIMEOUT:-900}
DEFAULT_SIZE=1080x1920
SET_SIZE=1080x2400
MOVIE_FPS=30
# Movie Maker size is the .movie window override (project.godot, synthesis C10).
MOVIE_SCREEN=1280x2560
FUZZ=2%
MAX_DIFF_SHARE=0.001
DRIVER=opengl3_es

die() { echo "capture.sh: $*" >&2; exit 2; }

has_arg() {  # <prefix> <args...>: true if any arg starts with prefix
	local p=$1; shift
	local a
	for a in "$@"; do [[ $a == "$p"* ]] && return 0; done
	return 1
}

# Runs Godot under a private Xvfb screen with a throw-away profile. <screen WxH> <log> <godot args...>
run_godot() {
	local screen=$1 log=$2; shift 2
	local profile
	profile=$(mktemp -d)
	local status=0
	mkdir -p "$(dirname "$log")"
	XDG_DATA_HOME="$profile/data" XDG_CACHE_HOME="$profile/cache" \
		timeout "$CAPTURE_TIMEOUT" xvfb-run -a -s "-screen 0 ${screen}x24" \
		"$GODOT" --path . --rendering-driver "$DRIVER" "$@" > "$log" 2>&1 || status=$?
	rm -rf "$profile"
	if grep -qE "SCRIPT ERROR|^ERROR:" "$log"; then
		grep -E -A1 "SCRIPT ERROR|^ERROR:" "$log" >&2
		[ "$status" -eq 0 ] && status=1
	fi
	return "$status"
}

screen_for() {  # <WxH> -> an Xvfb screen at least that large
	local w=${1%x*} h=${1#*x}
	echo "$(( w > 1216 ? w + 64 : 1280 ))x$(( h > 2496 ? h + 64 : 2560 ))"
}

cmd_still() {
	local size=$DEFAULT_SIZE pass=()
	local a
	for a in "$@"; do
		case $a in
			--size=*) size=${a#--size=}; pass+=("$a") ;;
			--driver=*) DRIVER=${a#--driver=} ;;
			*) pass+=("$a") ;;
		esac
	done
	[[ $size =~ ^[0-9]+x[0-9]+$ ]] || die "bad --size=$size"
	has_arg --size= "${pass[@]}" || pass+=("--size=$size")
	has_arg --seed= "${pass[@]}" || pass+=("--seed=1")
	has_arg --out= "${pass[@]}" || pass+=("--out=qa/out/capture.png")
	local out
	for a in "${pass[@]}"; do [[ $a == --out=* ]] && out=${a#--out=}; done
	run_godot "$(screen_for "$size")" "${out%.png}.log" --audio-driver Dummy --resolution "$size" \
		--fixed-fps "$MOVIE_FPS" -s res://tools/qa/capture.gd -- --no-save "${pass[@]}"
	grep -E "^capture: " "${out%.png}.log" || true
}

cmd_video() {
	local seconds=10 out=qa/out/clip png=0 pass=()
	local a
	for a in "$@"; do
		case $a in
			--seconds=*) seconds=${a#--seconds=} ;;
			--out=*) out=${a#--out=} ;;
			--png) png=1 ;;
			--driver=*) DRIVER=${a#--driver=} ;;
			*) pass+=("$a") ;;
		esac
	done
	has_arg --seed= "${pass[@]}" || pass+=("--seed=1")
	local frames=$(( seconds * MOVIE_FPS ))
	rm -rf "$out"
	mkdir -p "$out"  # Movie Maker needs the directory to exist (03 §6.1)
	local target="$out/clip.avi"
	[ "$png" -eq 1 ] && target="$out/frame.png"
	# capture.gd drives the run (frame clock, seeded, fixed defaults) and ends it through
	# Game.quit_cleanly; a bare --quit-after N also works but exits with audio still playing and
	# logs leaked-instance warnings.
	run_godot "$MOVIE_SCREEN" "$out/movie.log" --write-movie "$(realpath "$target")" --fixed-fps "$MOVIE_FPS" \
		-s res://tools/qa/capture.gd -- --no-save --out=none --animate --frames="$frames" "${pass[@]}"
	grep -E "^capture: |recorded in|Encoding time" "$out/movie.log" || true
	if [ "$png" -eq 1 ]; then cmd_encode "$out"; else cmd_encode "$target"; fi
}

cmd_encode() {
	local input=${1:?usage: capture.sh encode <clip.avi|frames-dir>}; shift
	local gif_w=360 gif_fps=15
	local a
	for a in "$@"; do
		case $a in
			--gif-width=*) gif_w=${a#--gif-width=} ;;
			--gif-fps=*) gif_fps=${a#--gif-fps=} ;;
			*) die "unknown encode option $a" ;;
		esac
	done
	local base video=() audio=()
	if [ -d "$input" ]; then
		base=${input%/}/clip
		video=(-framerate "$MOVIE_FPS" -i "${input%/}/frame%08d.png")
		[ -f "${input%/}/frame.wav" ] && audio=(-i "${input%/}/frame.wav")
	else
		[ -f "$input" ] || die "no such clip: $input"
		base=${input%.*}
		video=(-i "$input")
	fi
	# H.264 yuv420p for any player; CRF 18 is visually lossless for review (grain survives).
	ffmpeg -hide_banner -loglevel error -y "${video[@]}" "${audio[@]}" -c:v libx264 -preset slow -crf 18 \
		-pix_fmt yuv420p -c:a aac -b:a 160k -shortest -movflags +faststart "$base.mp4"
	# GIF for chat/PR previews: 2-pass palette, ordered dither (stable between frames).
	ffmpeg -hide_banner -loglevel error -y "${video[@]}" -an -vf \
		"fps=$gif_fps,scale=$gif_w:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
		"$base.gif"
	echo "encode: $base.mp4 ($(du -h "$base.mp4" | cut -f1)), $base.gif ($(du -h "$base.gif" | cut -f1))"
}

# AE pixel count between two PNGs at a fuzz (ImageMagick prints it on stderr; IM6 and IM7 exit 1
# when the images differ). Dies on anything that is not a number (e.g. a size mismatch).
ae() {
	local fuzz=$1 a=$2 b=$3 diff=${4:-null:} out
	out=$(compare -metric AE -fuzz "$fuzz" "$a" "$b" "$diff" 2>&1 >/dev/null || true)
	out=${out%% *}
	[[ $out =~ ^[0-9.e+]+$ ]] || die "compare failed for $a vs $b: $out"
	awk -v v="$out" 'BEGIN { printf "%d", v }'
}

cmd_determinism() {
	local dir=qa/out/determinism pass=()
	local a
	for a in "$@"; do
		case $a in
			--out=*) die "determinism writes to $dir; do not pass --out" ;;
			*) pass+=("$a") ;;
		esac
	done
	has_arg --size= "${pass[@]}" || pass+=("--size=$DEFAULT_SIZE")
	has_arg --seed= "${pass[@]}" || pass+=("--seed=7")
	has_arg --tod= "${pass[@]}" || pass+=("--tod=0.62")
	rm -rf "$dir"
	mkdir -p "$dir"
	local t0 t1
	t0=$(date +%s)
	cmd_still "${pass[@]}" --out="$dir/a.png"
	cmd_still "${pass[@]}" --out="$dir/b.png"
	t1=$(date +%s)
	local w h exact fuzzed identical=false
	read -r w h < <(identify -format '%w %h\n' "$dir/a.png")
	cmp -s "$dir/a.png" "$dir/b.png" && identical=true
	exact=$(ae 0 "$dir/a.png" "$dir/b.png")
	fuzzed=$(ae "$FUZZ" "$dir/a.png" "$dir/b.png" "$dir/diff.png")
	"$PYTHON" -I - "$dir" "$w" "$h" "$identical" "$exact" "$fuzzed" "$MAX_DIFF_SHARE" "$(( t1 - t0 ))" \
		"${pass[@]}" <<-'PY'
	import json, sys
	d, w, h, ident, exact, fuzzed, share, secs = sys.argv[1:9]
	meta = json.load(open(f"{d}/a.png.json", encoding="utf-8"))
	px = int(w) * int(h)
	res = {
	    "tool": "tools/qa/capture.sh determinism",
	    "driver": meta["driver"], "adapter_version": meta["adapter_version"], "engine": meta["engine"],
	    "args": sys.argv[9:], "size": [int(w), int(h)], "pixels": px,
	    "byte_identical": ident == "true", "ae_exact": int(exact), "ae_fuzz_2pct": int(fuzzed),
	    "max_allowed": int(px * float(share)), "seconds_for_two_runs": int(secs),
	}
	res["pass"] = res["ae_fuzz_2pct"] <= res["max_allowed"]
	open(f"{d}/result.json", "w", encoding="utf-8").write(json.dumps(res, indent=2) + "\n")
	print(json.dumps(res, indent=2))
	sys.exit(0 if res["pass"] else 1)
	PY
}

cmd_set() {
	local dir=qa/out/set size=$SET_SIZE
	local a
	for a in "$@"; do
		case $a in
			--out-dir=*) dir=${a#--out-dir=} ;;
			--size=*) size=${a#--size=} ;;
			*) die "unknown set option $a" ;;
		esac
	done
	rm -rf "$dir"
	mkdir -p "$dir"
	# Art Bible §11.2: 5 phases (g_day keys) + day rain. The Garden-sheet and 5-lantern frames
	# join this list when the UI and décor land (docs/QA.md §5.1).
	local shots=(
		"dawn_clear --tod=0.2 --weather=clear"
		"day_clear --tod=0.4 --weather=clear"
		"golden_clear --tod=0.6 --weather=clear"
		"dusk_clear --tod=0.8 --weather=clear"
		"night_clear --tod=1.0 --weather=clear"
		"day_rain --tod=0.4 --weather=rain"
	)
	local s name rest imgs=()
	for s in "${shots[@]}"; do
		name=${s%% *}
		rest=${s#* }
		# shellcheck disable=SC2086  # $rest is a list of flags
		cmd_still --size="$size" --seed=7 --frames=120 $rest --out="$dir/$name.png"
		imgs+=("$dir/$name.png")
	done
	"$PYTHON" -I tools/qa/metrics.py --json "$dir/metrics.json" --no-fail "${imgs[@]}" > /dev/null
	tools/qa/contact_sheet.sh -o "$dir/contact_sheet.png" -t "Mossling Meadow — rater set $size" "${imgs[@]}"
	echo "set: ${#imgs[@]} stills, $dir/metrics.json, $dir/contact_sheet.png"
}

sub=${1:-}
[ -n "$sub" ] || { sed -n '2,24p' "$0"; exit 2; }
shift
case $sub in
	still) cmd_still "$@" ;;
	video) cmd_video "$@" ;;
	encode) cmd_encode "$@" ;;
	determinism) cmd_determinism "$@" ;;
	set) cmd_set "$@" ;;
	*) die "unknown command '$sub' (still | video | encode | determinism | set)" ;;
esac
