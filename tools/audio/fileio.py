"""File output: 16-bit WAV (TPDF dither, optional `smpl` loop), OGG Vorbis via ffmpeg/libvorbis,
decoding for post-encode verification, and Godot `.import` parameter files.

Godot facts this relies on (verified in the 4.7.2 tree):
- WAV `smpl` loops: Godot skips 10 dwords then reads type/start/end
  (scene/resources/audio_stream_wav.cpp:840-870). The forward-loop period is loop_end - loop_begin
  and the mixer reads frame `loop_end` before wrapping, so we write a guard frame there that
  equals frame `loop_begin` (report 03 §5 seamless recipe).
- WAV import default compress/mode=2 (QOA) (editor/import/resource_importer_wav.cpp:89);
  edit/loop_mode=0 means "Detect From WAV" (reads our smpl chunk).
- OGG import options loop / loop_offset / bpm / beat_count / bar_beats
  (modules/vorbis/doc_classes/ResourceImporterOggVorbis.xml). Ogg tags are not read for looping,
  so `loop=true` must be in the .import file.
"""
from __future__ import annotations

import os
import struct
import subprocess
import tempfile

import numpy as np

from dsp import SR

FFMPEG = os.environ.get("FFMPEG", "ffmpeg")
OGG_QUALITY = 4  # D10: OGG Vorbis q4

# Seamless Vorbis loops in Godot 4.7.2 ("beat-loop crossfade").
# With loop=true, bpm>0 and beat_count>0, AudioStreamPlaybackOggVorbis loops after exactly
# beat_count*60/bpm seconds instead of at end-of-file; at that point it decodes the next FADE_SIZE
# (256) frames that follow in the file, seeks to loop_offset, and adds those frames on top of the
# restarted stream with a linear fade-out (modules/vorbis/audio_stream_ogg_vorbis.cpp:51-123,
# FADE_SIZE in audio_stream_ogg_vorbis.h:52). We therefore write
#     file = [x[0:256] * i/256,  x[256:L],  x[0:256]]          (L + 256 frames)
# so the restarted, faded-in head plus Godot's faded-out tail sum to exactly x: the codec error
# crossfades over 5.8 ms instead of stepping at the seam. If FADE_SIZE ever changes, change this.
GODOT_OGG_LOOP_FADE = 256


def ogg_loop_layout(x: np.ndarray) -> np.ndarray:
	F = GODOT_OGG_LOOP_FADE
	x = np.atleast_2d(x)
	ramp = np.arange(F) / F
	return np.concatenate([x[:, :F] * ramp, x[:, F:], x[:, :F]], axis=1)


def ogg_loop_fade_room(path: str, period: int) -> int:
	"""Frames Godot can actually read for the loop fade at `period` (must be >= 256).

	AudioStreamPlaybackOggVorbis::_mix_frames_vorbis returns at most the frames left in the current
	decoded Vorbis packet (audio_stream_ogg_vorbis.cpp:147-191), so the 256-frame loop-fade read is
	truncated if a packet boundary falls less than 256 frames after the loop point. ffprobe's packet
	table gives the boundaries (verified against a MovieWriter capture of Godot 4.7.2).
	"""
	cmd = [os.environ.get("FFPROBE", "ffprobe"), "-v", "error", "-select_streams", "a", "-show_entries",
		"packet=pts,duration", "-of", "csv=p=0", path]
	rows = [ln.split(",") for ln in subprocess.run(cmd, check=True, capture_output=True, text=True).stdout.split()]
	pts = np.array([int(r[0]) for r in rows if len(r) >= 2])
	dur = np.array([int(r[1]) for r in rows if len(r) >= 2])
	ends = pts + dur
	hit = np.nonzero(ends == period)[0]
	if hit.size:   # loop point on a boundary: the fade read decodes the next packet
		return int(dur[hit[0] + 1]) if hit[0] + 1 < len(dur) else 0
	i = int(np.searchsorted(ends, period, side="right"))
	return int(ends[i] - period) if i < len(ends) else 0


def ogg_as_played(dec: np.ndarray, period: int) -> np.ndarray:
	"""Steady-state loop period exactly as Godot plays it (2nd and later passes)."""
	F = GODOT_OGG_LOOP_FADE
	out = np.array(dec[:, :period], copy=True)
	out[:, :F] += dec[:, period:period + F] * ((F - np.arange(F)) / F)
	return out


def _to_int16(x: np.ndarray, rng: np.random.Generator) -> np.ndarray:
	"""TPDF dither of +-1 LSB, then round and clip (report 03 §5)."""
	x = np.atleast_2d(np.asarray(x, dtype=float))
	tpdf = rng.random(x.shape) - rng.random(x.shape)
	y = np.round(x * 32767.0 + tpdf)
	return np.clip(y, -32768, 32767).astype("<i2")


def write_wav16(path: str, x: np.ndarray, seed: int, loop: tuple[int, int] | None = None) -> int:
	"""Write 16-bit PCM WAV. `loop` = (begin, end) frames; a guard frame is appended at `end`.

	Returns the number of frames written.
	"""
	rng = np.random.default_rng(seed ^ 0x5EED)
	pcm = _to_int16(x, rng)  # (ch, n)
	if loop is not None:
		begin, end = loop
		assert pcm.shape[1] == end, "loop body must end at the last frame before the guard"
		pcm = np.concatenate([pcm, pcm[:, begin:begin + 1]], axis=1)
	ch, n = pcm.shape
	data = pcm.T.reshape(-1).tobytes()
	chunks = [b"fmt " + struct.pack("<IHHIIHH", 16, 1, ch, SR, SR * ch * 2, ch * 2, 16)]
	chunks.append(b"data" + struct.pack("<I", len(data)) + data)
	if loop is not None:
		begin, end = loop
		smpl = struct.pack("<9I", 0, 0, int(round(1e9 / SR)), 60, 0, 0, 0, 1, 0)
		smpl += struct.pack("<6I", 0, 0, begin, end, 0, 0)  # cue id, type 0 = forward, start, end, fraction, play count
		chunks.append(b"smpl" + struct.pack("<I", len(smpl)) + smpl)
	body = b"WAVE" + b"".join(chunks)
	os.makedirs(os.path.dirname(path), exist_ok=True)
	with open(path, "wb") as fh:
		fh.write(b"RIFF" + struct.pack("<I", len(body)) + body)
	return n


def read_wav16(path: str) -> np.ndarray:
	"""Minimal reader for our own files: returns float (ch, n) without the smpl info."""
	with open(path, "rb") as fh:
		raw = fh.read()
	pos, ch, data = 12, 1, b""
	while pos < len(raw):
		cid, size = raw[pos:pos + 4], struct.unpack("<I", raw[pos + 4:pos + 8])[0]
		if cid == b"fmt ":
			ch = struct.unpack("<H", raw[pos + 10:pos + 12])[0]
		elif cid == b"data":
			data = raw[pos + 8:pos + 8 + size]
		pos += 8 + size + (size & 1)
	a = np.frombuffer(data, dtype="<i2").astype(float) / 32768.0
	return a.reshape(-1, ch).T


def encode_ogg(path: str, x: np.ndarray, quality: int = OGG_QUALITY) -> None:
	"""Encode float audio to OGG Vorbis with libvorbis (bitexact: no version strings)."""
	x = np.atleast_2d(np.asarray(x, dtype="<f4"))
	os.makedirs(os.path.dirname(path), exist_ok=True)
	with tempfile.NamedTemporaryFile(suffix=".f32", delete=False) as tmp:
		tmp.write(np.ascontiguousarray(x.T).tobytes())
		raw = tmp.name
	try:
		cmd = [FFMPEG, "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
			"-f", "f32le", "-ar", str(SR), "-ac", str(x.shape[0]), "-i", raw,
			"-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
			"-c:a", "libvorbis", "-q:a", str(quality), path]
		subprocess.run(cmd, check=True)
	finally:
		os.unlink(raw)


def decode_audio(path: str, channels: int) -> np.ndarray:
	"""Decode any ffmpeg-readable file to float (ch, n) at SR."""
	cmd = [FFMPEG, "-nostdin", "-hide_banner", "-loglevel", "error", "-i", path,
		"-f", "f32le", "-ac", str(channels), "-ar", str(SR), "-"]
	out = subprocess.run(cmd, check=True, capture_output=True).stdout
	a = np.frombuffer(out, dtype="<f4").astype(float)
	return a.reshape(-1, channels).T


# ----------------------------------------------------------------------------- Godot .import
OGG_IMPORTER = ("oggvorbisstr", "AudioStreamOggVorbis")
WAV_IMPORTER = ("wav", "AudioStreamWAV")

WAV_DEFAULT_PARAMS = {
	"force/8_bit": "false",
	"force/mono": "false",
	"force/max_rate": "false",
	"force/max_rate_hz": "44100",
	"edit/trim": "false",       # our files are already trimmed; keep sample-exact onsets
	"edit/normalize": "false",  # loudness is mastered here, never in the importer
	"edit/loop_mode": "0",      # Detect From WAV (reads our smpl chunk)
	"edit/loop_begin": "0",
	"edit/loop_end": "-1",
	"compress/mode": "2",       # Quite OK Audio (D10: QOA SFX)
}


def write_import(asset_path: str, importer: tuple[str, str], params: dict[str, str]) -> None:
	"""Create or update `<asset>.import`, replacing only the [params] section.

	An existing file keeps its uid/remap/deps (written by the editor on first import), so
	re-running the toolchain never churns resource UIDs.
	"""
	imp = asset_path + ".import"
	params_txt = "[params]\n\n" + "".join(f"{k}={v}\n" for k, v in params.items())
	if os.path.exists(imp):
		with open(imp, encoding="utf-8") as fh:
			txt = fh.read()
		head = txt.split("[params]")[0].rstrip("\n") + "\n\n"
		new = head + params_txt
	else:
		new = (f"[remap]\n\nimporter=\"{importer[0]}\"\ntype=\"{importer[1]}\"\n\n" + params_txt)
	if not os.path.exists(imp) or open(imp, encoding="utf-8").read() != new:
		with open(imp, "w", encoding="utf-8", newline="\n") as fh:
			fh.write(new)
