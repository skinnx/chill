class_name PanMath
extends RefCounted
## Pure maths of the one-finger map drag (docs/ARCHITECTURE.md §3.4). Pans are camera offsets from
## the home view in canvas px (+x shows more of the right, -y rises into the sky).
##
## Horizontal: a Parallax2D layer with scroll factor s shows local x in [s·d − ox, s·d − ox + W] at
## pan d (ox = the centring offset of the 1080 column), so its authored span [x_min, x_max] limits
## d to [(x_min + ox) / s, (x_max + ox − W) / s]; the strictest layer wins (the ground, s = 1).
## Vertical: up to sky_up_px into the sky, never below the home view (the frame bottom is the ground's
## bottom). The rest bounds sit rubber_room px inside these hard bounds on every side that may
## rubber-band, so even the overshoot never shows past the authored geometry.


## Hard pan bounds (the visible rect never leaves the authored geometry). [param scales] are the
## scroll factors of the full-width layers (0 < s <= 1; others are skipped).
static func hard_bounds(vis: Vector2, frame: Vector2, x_range: Vector2, scales: PackedFloat64Array,
		up_px: float, room_px: float) -> Rect2:
	var ox := roundf((vis.x - frame.x) * 0.5)
	var lo := -INF
	var hi := INF
	for s: float in scales:
		if s <= 0.0 or s > 1.0:
			continue
		lo = maxf(lo, (x_range.x + ox) / s)
		hi = minf(hi, (x_range.y + ox - vis.x) / s)
	if lo > hi or is_inf(lo) or is_inf(hi):
		# screen wider than the geometry (or no layer): no horizontal pan, stay centred
		lo = 0.0
		hi = 0.0
	var top := -(maxf(up_px, 0.0) + maxf(room_px, 0.0))
	return Rect2(lo, top, hi - lo, -top)


## Rest bounds: the hard bounds shrunk by the rubber room on the left, right and top (never more
## than half the span); the bottom is hard (no rubber band below the ground).
static func rest_bounds(hard: Rect2, room_px: float) -> Rect2:
	var rx := minf(maxf(room_px, 0.0), hard.size.x * 0.5)
	var ry := minf(maxf(room_px, 0.0), hard.size.y)
	return Rect2(hard.position.x + rx, hard.position.y + ry, hard.size.x - 2.0 * rx, hard.size.y - ry)


## Rubber band on one axis: identity inside [lo, hi]; past an edge the overshoot o is shown as
## room·(1 − 1/(1 + k·o/room)) (UIScrollView-like), which never exceeds room. room 0 = hard clamp.
static func rubber(raw: float, lo: float, hi: float, room_lo: float, room_hi: float, k: float) -> float:
	if raw < lo:
		return lo - _band(lo - raw, room_lo, k)
	if raw > hi:
		return hi + _band(raw - hi, room_hi, k)
	return raw


## [method rubber] on both axes of a rest rect inside a hard rect.
static func rubber_2d(raw: Vector2, rest: Rect2, hard: Rect2, k: float) -> Vector2:
	return Vector2(
		rubber(raw.x, rest.position.x, rest.end.x, rest.position.x - hard.position.x, hard.end.x - rest.end.x, k),
		rubber(raw.y, rest.position.y, rest.end.y, rest.position.y - hard.position.y, hard.end.y - rest.end.y, k))


static func clamp_2d(p: Vector2, r: Rect2) -> Vector2:
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))


static func _band(over: float, room: float, k: float) -> float:
	if room <= 0.0:
		return 0.0
	return room * (1.0 - 1.0 / (1.0 + k * over / room))


## Soft saturation for the 1.3x foreground frame: identity up to knee·room, then an exponential
## approach to room (C1-continuous). [param room_neg] / [param room_pos] are how far x may go below
## / above 0 (>= 0).
static func soft_limit(x: float, room_neg: float, room_pos: float, knee: float) -> float:
	var room := room_pos if x >= 0.0 else room_neg
	room = maxf(room, 0.0)
	var ax := absf(x)
	var k := room * clampf(knee, 0.0, 1.0)
	if ax <= k:
		return x
	var tail := room - k
	var y := k if tail <= 0.0 else k + tail * (1.0 - exp(-(ax - k) / tail))
	return y if x >= 0.0 else -y


## How far a layer's lower edge is revealed when the camera rises: the layer at scroll factor
## [param s] and the next opaque layer in front at [param s_front] part by rise·(s_front − s).
static func reveal(pan_y: float, s: float, s_front: float) -> float:
	return maxf(-pan_y, 0.0) * maxf(s_front - s, 0.0)
