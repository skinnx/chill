class_name Harmony
extends RefCounted
## Pitch helpers mirroring tools/audio/theory.py (the audio pipeline's single source): snap to a
## chord's pentatonic set, step through the set, octave-wrap into a range. Pure static functions.
##
## A pitch-class set may come straight from JSON (floats): every lookup goes through
## PackedInt32Array, because Array.has() is type-strict ([5.0].has(5) is false).

const OCTAVE := 12
const SNAP_OFFSETS: Array[int] = [0, 1, -1, 2, -2, 3, -3]


## [param values] (ints or JSON floats) as an Array of int pitch classes 0..11.
static func pc_list(values: Array) -> Array:
	var out: Array = []
	for pc: int in PackedInt32Array(values):
		out.append(posmod(pc, OCTAVE))
	return out


## Nearest pitch in [param pcs]; ties prefer the upper neighbour (order 0, +1, -1, +2, -2 ...).
static func snap(midi: int, pcs: Array) -> int:
	var pc_set := PackedInt32Array(pcs)
	for d: int in SNAP_OFFSETS:
		if pc_set.has(posmod(midi + d, OCTAVE)):
			return midi + d
	return midi


## Moves [param steps] scale steps through the set, starting from snap(midi).
static func pent_step(midi: int, steps: int, pcs: Array) -> int:
	var m := snap(midi, pcs)
	var pc_set := PackedInt32Array(pcs)
	if steps == 0 or not _has_any_pc(pc_set):
		return m
	var d := 1 if steps > 0 else -1
	for _i in absi(steps):
		m += d
		while not pc_set.has(posmod(m, OCTAVE)):
			m += d
	return m


static func _has_any_pc(pc_set: PackedInt32Array) -> bool:
	for pc in pc_set:
		if pc >= 0 and pc < OCTAVE:
			return true
	return false


## Octave-transposes into [lo, hi] (keeps the pitch class).
static func wrap_into(midi: int, lo: int, hi: int) -> int:
	var m := midi
	while m < lo:
		m += OCTAVE
	while m > hi:
		m -= OCTAVE
	return m


## The pitch class [param pc] placed in [lo, hi] (lowest occurrence).
static func place_pc(pc: int, lo: int, hi: int) -> int:
	var m := lo + posmod(pc - lo, OCTAVE)
	return m if m <= hi else m - OCTAVE


## Pitch-scale factor to play [param midi] from a sample rendered at [param sample_midi].
static func pitch_scale(midi: int, sample_midi: int) -> float:
	return pow(2.0, float(midi - sample_midi) / float(OCTAVE))


## The rendered note at or below [param midi] within an octave (06 §2.4: repitch upward only).
static func nearest_rendered(notes: Dictionary, midi: int) -> int:
	var key := midi
	while key > midi - OCTAVE:
		if notes.has(key):
			return key
		key -= 1
	return -1
