class_name DecorPlacementRules
extends RefCounted
## Active F3 free décor placement rules (GDD §14, docs/gdd/ACTIVE_DECOR.md §4-§7, §12-§13;
## data/decor_placement.json).
##
## Pure and deterministic: no nodes, no autoloads, no randomness except the stateless settle
## jitter hash. Every function takes the layout it works on (WorldState.decor_layout records) and a
## small world context ({"nests": Array[Vector2] built nest centres, "tea": bool tea nook on}), so
## the front-end can call the same validate / snap / nudge it shows while a piece is held, and the
## sim and tests get the same answers. Positions are frame-normalised foot positions (x right,
## y down; 1.0 x = 360 dp, 1.0 y = 640 dp; x may leave [0, 1] into the pan wings).
##
## Attraction never reads this: requires / likes / snug / spot gating keep counting owned copies,
## placed or tucked away (decor_placement.json attraction.count, GDD §14.4 D7).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## Validity reasons (ACTIVE_DECOR §4.3) in hint priority order; "" = valid. Each maps to a
## DECOR_HINT_* string key ([method hint_key]).
const VALID := &""
const R_SKY := &"sky"
const R_LOW := &"low"
const R_EDGE := &"edge"
const R_WATER := &"water"
const R_DRY := &"dry"
const R_FLOWERS := &"flowers"
const R_SPOT := &"spot"
const R_NEST := &"nest"
const R_PROP := &"prop"
const R_CROWDED := &"crowded"
const R_STACK := &"stack"
const R_RETURNED := &"returned"
const R_NOT_MOVABLE := &"not_movable"
const CAIRN := &"pebble_cairn"
const LANTERN := &"firefly_lantern"
const ID_SEP := "#"
## DecorLayer.LANTERN_JITTER_PX (design px): the MVP lantern x jitter, baked in by the migration.
const LANTERN_JITTER_PX := 10.0
## Angular samples of the smallest search ring; larger rings keep about this arc spacing.
const RING_MIN_SAMPLES := 8
const RING_ARC_DP := 4.0
const SPOT_MIN_GAP_DP := 20.0
const SPOT_STEP_DP := 4.0
const SPOT_STEP_MAX_DP := 24.0

var content: GameContent
var dp: Dictionary
## dp per normalised unit (360 x 640 on the 1080 x 1920 frame at 3 px/dp).
var w_dp: float = 360.0
var h_dp: float = 640.0
var _water: PackedVector2Array = PackedVector2Array()
var _water_half_dp: float = 11.5
var _ground_top: PackedVector2Array = PackedVector2Array()


func _init(p_content: GameContent) -> void:
	content = p_content
	dp = content.decor_placement
	var frame: Dictionary = content.spots_doc.get("frame", {})
	var px_per_dp := float(frame.get("px_per_dp", 3.0))
	w_dp = float(frame.get("width_px", 1080.0)) / px_per_dp
	h_dp = float(frame.get("height_px", 1920.0)) / px_per_dp
	var stream: Dictionary = content.spots_doc.get("stream", {})
	for q: Variant in stream.get("polyline", []):
		_water.append(Vector2(float(q[0]), float(q[1])))
	_water_half_dp = float(stream.get("water_width", 0.036)) * h_dp * 0.5
	for q: Variant in (dp.get("area", {}) as Dictionary).get("ground_top", []):
		_ground_top.append(Vector2(float(q[0]), float(q[1])))


# ================================================================= ids and records

static func piece_id(set_id: StringName, n: int) -> String:
	return "%s%s%d" % [set_id, ID_SEP, n]


static func is_placed(piece: Dictionary) -> bool:
	return not bool(piece["stored"])


## The cairn stack a pebble belongs to (its base piece id; a base is its own stack).
static func stack_of(piece: Dictionary) -> String:
	var s := String(piece["stack"])
	return s if s != "" else String(piece["id"])


static func find(layout: Array[Dictionary], id: String) -> int:
	for i in layout.size():
		if String(layout[i]["id"]) == id:
			return i
	return -1


func set_def(set_id: StringName) -> Dictionary:
	return content.placement_set(set_id)


func footprint_dp(set_id: StringName) -> float:
	return float(set_def(set_id).get("footprint_r_dp", 0.0))


func rot_steps(set_id: StringName) -> int:
	return maxi(1, int(set_def(set_id).get("rot_steps", 1)))


func hint_key(reason: StringName) -> String:
	return "" if reason == VALID else "DECOR_HINT_%s" % String(reason).to_upper()


## Placed pieces of [param set_id] (cairn: one entry per stack, the base).
func placed_units(layout: Array[Dictionary], set_id: StringName, ignore: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in layout:
		if StringName(p["set"]) != set_id or not is_placed(p) or _ignored(p, ignore):
			continue
		if set_id == CAIRN and String(p["stack"]) != "":
			continue
		out.append(p)
	return out


func placed_count(layout: Array[Dictionary], set_id: StringName) -> int:
	var n := 0
	for p: Dictionary in layout:
		if StringName(p["set"]) == set_id and is_placed(p):
			n += 1
	return n


func stack_size(layout: Array[Dictionary], stack_id: String) -> int:
	var n := 0
	for p: Dictionary in layout:
		if StringName(p["set"]) == CAIRN and is_placed(p) and stack_of(p) == stack_id:
			n += 1
	return n


# ================================================================= geometry

func dist_dp(a: Vector2, b: Vector2) -> float:
	return Vector2((a.x - b.x) * w_dp, (a.y - b.y) * h_dp).length()


func offset_norm(p: Vector2, d_dp: Vector2) -> Vector2:
	return Vector2(p.x + d_dp.x / w_dp, p.y + d_dp.y / h_dp)


## Distance in dp from [param p] to the brook polyline (shifted [param dy_dp] down).
func water_dist_dp(p: Vector2, dy_dp: float = 0.0) -> float:
	var best := INF
	var q := Vector2(p.x * w_dp, p.y * h_dp)
	for i in _water.size() - 1:
		var a := Vector2(_water[i].x * w_dp, _water[i].y * h_dp + dy_dp)
		var b := Vector2(_water[i + 1].x * w_dp, _water[i + 1].y * h_dp + dy_dp)
		best = minf(best, q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)))
	return best


## The walkable rim at [param x] (piecewise-linear ground_top; the foot must lie below it).
func ground_top_at(x: float) -> float:
	if _ground_top.is_empty():
		return 0.0
	if x <= _ground_top[0].x:
		return _ground_top[0].y
	for i in _ground_top.size() - 1:
		var a := _ground_top[i]
		var b := _ground_top[i + 1]
		if x <= b.x:
			return lerpf(a.y, b.y, (x - a.x) / maxf(1e-9, b.x - a.x))
	return _ground_top[_ground_top.size() - 1].y


func _in_ellipse(p: Vector2, c: Vector2, rx_dp: float, ry_dp: float) -> bool:
	var dx := (p.x - c.x) * w_dp / maxf(rx_dp, 1e-6)
	var dy := (p.y - c.y) * h_dp / maxf(ry_dp, 1e-6)
	return dx * dx + dy * dy < 1.0


# ================================================================= validity (ACTIVE_DECOR §4)

## Why [param set_id] may not stand with its foot at [param pos] (VALID = it may). [param ignore] is
## the piece being moved (a cairn base id ignores its whole stack). [param ctx]: {"nests":
## Array of Vector2 built nest centres, "tea": bool}. Every rule of §4.1 (new drops).
func validate(set_id: StringName, pos: Vector2, layout: Array[Dictionary], ctx: Dictionary,
		ignore: String = "") -> StringName:
	var st := set_def(set_id)
	if not bool(st.get("movable", false)):
		return R_NOT_MOVABLE
	var r := footprint_dp(set_id)
	var area := _area_reason(set_id, pos)
	if area != VALID:
		return area
	var cl: Dictionary = dp["clearances"]
	var gap := float(cl["gap_dp"])
	for b: Dictionary in content.beds:
		var soil: Dictionary = cl["bed_soil"]
		if _in_ellipse(pos, Vector2(float(b["x"]), float(b["y"])), float(soil["rx_dp"]) + r + gap,
				float(soil["ry_dp"]) + r + gap):
			return R_FLOWERS
		for q: Variant in b.get("nibble_points", []):
			if dist_dp(pos, Vector2(float(q[0]), float(q[1]))) < float(cl["nibble_clear_dp"]) + r:
				return R_FLOWERS
	for s: Dictionary in content.spots:
		if String(s.get("requires_item", "")) == "" \
				and dist_dp(pos, Vector2(float(s["x"]), float(s["y"]))) < float(cl["spot_clear_dp"]) + r:
			return R_SPOT
	var nest_clear := float((cl["nest"] as Dictionary)["centre_clear_dp"])
	for n: Variant in ctx.get("nests", []):
		if dist_dp(pos, n as Vector2) < nest_clear:
			return R_NEST
	if _prop_blocked(pos, r, ctx, false):
		return R_PROP
	return _pieces_reason(set_id, pos, layout, ignore)


## Only the hard exclusions (hard props, the tea nook) and the area: what migrated pieces obey.
func validate_hard(set_id: StringName, pos: Vector2, ctx: Dictionary) -> StringName:
	var area := _area_reason(set_id, pos)
	if area != VALID:
		return area
	return R_PROP if _prop_blocked(pos, footprint_dp(set_id), ctx, true) else VALID


func _area_reason(set_id: StringName, pos: Vector2) -> StringName:
	var area: Dictionary = dp["area"]
	if pos.x < float(area["x_min"]) or pos.x > float(area["x_max"]):
		return R_EDGE
	var stone := String(set_def(set_id).get("water", "")) == "only"
	var wd := water_dist_dp(pos)
	if stone:
		return VALID if wd <= _water_half_dp else R_DRY
	if pos.y <= ground_top_at(pos.x):
		return R_SKY
	if pos.y > float(area["ground_bottom_y"]):
		return R_LOW
	var cl: Dictionary = dp["clearances"]
	if wd < _water_half_dp + footprint_dp(set_id) + float(cl["bank_gap_dp"]):
		return R_WATER
	return VALID


func _prop_blocked(pos: Vector2, r: float, ctx: Dictionary, hard_only: bool) -> bool:
	var cl: Dictionary = dp["clearances"]
	for p: Dictionary in GameContent._records(cl["props"]):
		if hard_only and not bool(p.get("hard", false)):
			continue
		var gap := float(p.get("gap_dp", cl["gap_dp"]))
		var c := Vector2(float(p["x"]), float(p["y"]) + float(p["cy_dp"]) / h_dp)
		if _in_ellipse(pos, c, float(p["rx_dp"]) + r + gap, float(p["ry_dp"]) + r + gap):
			return true
	if bool(ctx.get("tea", false)):
		var nook: Dictionary = content.tea["nook"]
		if dist_dp(pos, Vector2(float(nook["x"]), float(nook["y"]))) < float(nook["f3_exclusion_radius_dp"]) + r:
			return true
	return false


func _pieces_reason(set_id: StringName, pos: Vector2, layout: Array[Dictionary], ignore: String) -> StringName:
	var st := set_def(set_id)
	var r := float(st["footprint_r_dp"])
	var gap := float((dp["clearances"] as Dictionary)["gap_dp"])
	for p: Dictionary in layout:
		if not is_placed(p) or _ignored(p, ignore):
			continue
		var other := StringName(p["set"])
		if other == CAIRN and String(p["stack"]) != "":
			continue  # a stack is checked once, through its base
		var d := dist_dp(pos, Vector2(float(p["x"]), float(p["y"])))
		if other == set_id:
			if set_id == CAIRN and d <= float(st["stack_merge_dp"]):
				if stack_size(layout, String(p["id"])) + _moving_size(layout, ignore) > int(st["stack_max"]):
					return R_STACK
				continue  # it merges onto this stack (ACTIVE_DECOR §8.2)
			if d < float(st["same_set_min_dp"]):
				return R_CROWDED
		elif d < r + footprint_dp(other) + gap:
			return R_CROWDED
	return VALID


## Pebbles carried by a move of [param ignore] (a whole stack, or one loose piece).
func _moving_size(layout: Array[Dictionary], ignore: String) -> int:
	if ignore == "":
		return 1
	var i := find(layout, ignore)
	if i < 0 or not is_placed(layout[i]):
		return 1
	return maxi(1, stack_size(layout, ignore)) if String(layout[i]["stack"]) == "" else 1


func _ignored(p: Dictionary, ignore: String) -> bool:
	if ignore == "":
		return false
	return String(p["id"]) == ignore or String(p["stack"]) == ignore


## The cairn stack a drop at [param pos] merges onto ("" = none).
func merge_target(pos: Vector2, layout: Array[Dictionary], ignore: String = "") -> String:
	var st := set_def(CAIRN)
	var best := ""
	var best_d := INF
	for p: Dictionary in placed_units(layout, CAIRN, ignore):
		var d := dist_dp(pos, Vector2(float(p["x"]), float(p["y"])))
		if d <= float(st["stack_merge_dp"]) and d < best_d:
			best_d = d
			best = String(p["id"])
	return best


## True when no placed footprint (plus the gap) lies within [param radius_dp] of [param pos]
## (sign anchors yield to décor, ACTIVE_DECOR §15).
func is_clear(pos: Vector2, radius_dp: float, layout: Array[Dictionary]) -> bool:
	var gap := float((dp["clearances"] as Dictionary)["gap_dp"])
	for p: Dictionary in layout:
		if is_placed(p) and dist_dp(pos, Vector2(float(p["x"]), float(p["y"]))) \
				< radius_dp + footprint_dp(StringName(p["set"])) + gap:
			return false
	return true


## Distance in dp from [param pos] to the nearest placed piece of [param set_id] (INF if none).
func nearest_piece_dp(set_id: StringName, pos: Vector2, layout: Array[Dictionary]) -> float:
	var best := INF
	for p: Dictionary in layout:
		if StringName(p["set"]) == set_id and is_placed(p):
			best = minf(best, dist_dp(pos, Vector2(float(p["x"]), float(p["y"]))))
	return best


# ================================================================= sockets and snapping (§5)

## Snap sockets for [param set_id]: [{pos: Vector2, family: StringName}] in snap.priority family
## order, only those valid for the held piece.
func sockets(set_id: StringName, layout: Array[Dictionary], ctx: Dictionary, ignore: String = "") -> Array[Dictionary]:
	var st := set_def(set_id)
	var aff: Array = st.get("affinity", [])
	var sn: Dictionary = dp["snap"]
	var raw: Array[Dictionary] = []
	for fam_v: Variant in sn["priority"]:
		var fam := StringName(fam_v)
		if not aff.has(String(fam)):
			continue
		match fam:
			&"same_set_ring":
				var n := int(sn["same_set_ring_dirs"])
				for p: Dictionary in placed_units(layout, set_id, ignore):
					var c := Vector2(float(p["x"]), float(p["y"]))
					for k in n:
						var a := TAU * float(k) / float(n)
						raw.append({"pos": offset_norm(c, Vector2(cos(a), sin(a)) * float(st["preferred_spacing_dp"])),
							"family": fam})
			&"ring_around_cluster":
				var ring: Dictionary = st.get("ring", {})
				for cl: Array in clusters(layout, set_id, ignore):
					if cl.size() < int(ring.get("forms_at", 3)):
						continue
					var c := _centroid(cl)
					var m := int(ring.get("socket_count", 10))
					for k in m:
						var a := TAU * float(k) / float(m)
						raw.append({"pos": offset_norm(c, Vector2(cos(a), sin(a)) * float(ring["socket_radius_dp"])),
							"family": fam})
			&"water_line":
				for q: Vector2 in _line_samples(float(sn["water_line_offset_dp"]), float(st["preferred_spacing_dp"])):
					raw.append({"pos": q, "family": fam})
			&"bank_line":
				for q: Vector2 in _line_samples(float(sn["bank_line_offset_dp"]), float(st["preferred_spacing_dp"])):
					raw.append({"pos": q, "family": fam})
			&"legacy_anchor":
				var a: Dictionary = content.anchors_by_decor.get(set_id, {})
				for q: Variant in a.get("positions", []):
					raw.append({"pos": Vector2(float(q[0]), float(q[1])), "family": fam})
			&"spot_side":
				for s: Dictionary in content.spots:
					if String(s.get("requires_item", "")) != "":
						continue
					var c := Vector2(float(s["x"]), float(s["y"]))
					for dv: Variant in sn["spot_side_dirs"]:
						var dir := Vector2(float(dv[0]), float(dv[1]))
						raw.append({"pos": offset_norm(c, dir * float(sn["spot_side_offset_dp"])), "family": fam})
	var out: Array[Dictionary] = []
	for s: Dictionary in raw:
		if validate(set_id, s["pos"], layout, ctx, ignore) == VALID:
			out.append(s)
	return out


## The settle point for a drop at [param pos]: the best socket within the magnet radius (family
## priority, then nearest to the finger), else [param pos] itself. Returns {pos, socket: bool,
## family}. [param socket_list] may pass sockets built once per hold (§5.1).
func snap(set_id: StringName, pos: Vector2, layout: Array[Dictionary], ctx: Dictionary, ignore: String = "",
		socket_list: Array[Dictionary] = []) -> Dictionary:
	var list := socket_list if not socket_list.is_empty() else sockets(set_id, layout, ctx, ignore)
	var radius := float((dp["snap"] as Dictionary)["magnet_radius_dp"])
	var best := {}
	var best_rank := 1 << 30
	var best_d := INF
	var prio: Array = (dp["snap"] as Dictionary)["priority"]
	for s: Dictionary in list:
		var d := dist_dp(pos, s["pos"])
		if d > radius:
			continue
		var rank := prio.find(String(s["family"]))
		if rank < best_rank or (rank == best_rank and d < best_d):
			best = s
			best_rank = rank
			best_d = d
	if best.is_empty():
		return {"pos": pos, "socket": false, "family": &"free"}
	return {"pos": best["pos"], "socket": true, "family": best["family"]}


## The magnet's visual pull while held: [param pos] moved toward a socket in reach by at most
## magnet_pull_max of the way (smoothstep on the distance). The finger always stays in charge.
func magnet(set_id: StringName, pos: Vector2, layout: Array[Dictionary], ctx: Dictionary, ignore: String = "",
		socket_list: Array[Dictionary] = []) -> Vector2:
	var s := snap(set_id, pos, layout, ctx, ignore, socket_list)
	if not bool(s["socket"]):
		return pos
	var sn: Dictionary = dp["snap"]
	var radius := float(sn["magnet_radius_dp"])
	var target: Vector2 = s["pos"]
	var k := float(sn["magnet_pull_max"]) * (1.0 - smoothstep(0.0, radius, dist_dp(pos, target)))
	return pos.lerp(target, k)


## The §4.4 ring search: the nearest valid point within nudge_search_dp (rings nudge_step_dp
## apart; a socket wins a tie), or [param pos] when it is already valid. Returns {ok, pos}.
func nudge(set_id: StringName, pos: Vector2, layout: Array[Dictionary], ctx: Dictionary,
		ignore: String = "") -> Dictionary:
	if validate(set_id, pos, layout, ctx, ignore) == VALID:
		return {"ok": true, "pos": pos}
	return _ring_search(set_id, pos, func(q: Vector2) -> bool: return validate(set_id, q, layout, ctx, ignore) == VALID,
		sockets(set_id, layout, ctx, ignore))


func _ring_search(set_id: StringName, pos: Vector2, valid: Callable, socket_list: Array[Dictionary]) -> Dictionary:
	var nd: Dictionary = (dp["snap"] as Dictionary)["invalid_drop"]
	var step := float(nd["nudge_step_dp"])
	var max_r := float(nd["nudge_search_dp"])
	var best_sock := {}
	var best_sock_d := INF
	for s: Dictionary in socket_list:
		var d := dist_dp(pos, s["pos"])
		if d <= max_r and d < best_sock_d:
			best_sock_d = d
			best_sock = s
	var r := step
	while r <= max_r + 1e-6:
		if not best_sock.is_empty() and best_sock_d <= r:
			return {"ok": true, "pos": best_sock["pos"]}
		var n := maxi(RING_MIN_SAMPLES, ceili(TAU * r / RING_ARC_DP))
		for k in n:
			var a := TAU * float(k) / float(n)
			var q := offset_norm(pos, Vector2(cos(a), sin(a)) * r)
			if valid.call(q):
				return {"ok": true, "pos": q}
		r += step
	if not best_sock.is_empty():
		return {"ok": true, "pos": best_sock["pos"]}
	return {"ok": false, "pos": pos, "set": set_id}


## The silent settle jitter (beautify): +-settle_jitter_dp seeded by the piece id and its dp
## position, so a re-drop on the same spot looks the same. Kept only if the result stays valid.
func jitter(piece: String, pos: Vector2) -> Vector2:
	var b: Dictionary = dp["beautify"]
	if not bool(b.get("enabled", true)):
		return pos
	var amp := float(b["settle_jitter_dp"])
	var xi := floori(pos.x * w_dp)
	var yi := floori(pos.y * h_dp)
	var jx := (RetentionHash.u(0, [piece, xi, yi, "x"]) * 2.0 - 1.0) * amp
	var jy := (RetentionHash.u(0, [piece, xi, yi, "y"]) * 2.0 - 1.0) * amp
	return offset_norm(pos, Vector2(jx, jy))


## Full drop resolution (release of a held piece or a tap-then-tap glide): snap, else nudge,
## then the jitter. Returns {ok, pos, nudged, socket, family, reason, merge}; ok false = float home.
func resolve_drop(set_id: StringName, pos: Vector2, layout: Array[Dictionary], ctx: Dictionary,
		piece: String = "") -> Dictionary:
	var socket_list := sockets(set_id, layout, ctx, piece)
	var reason := validate(set_id, pos, layout, ctx, piece)
	var at := pos
	var nudged := false
	var s := snap(set_id, pos, layout, ctx, piece, socket_list)
	if bool(s["socket"]):
		at = s["pos"]
	elif reason != VALID:
		var n := _ring_search(set_id, pos,
			func(q: Vector2) -> bool: return validate(set_id, q, layout, ctx, piece) == VALID, socket_list)
		if not bool(n["ok"]):
			return {"ok": false, "pos": pos, "nudged": false, "socket": false, "family": &"free",
				"reason": reason if reason != VALID else R_RETURNED, "merge": ""}
		at = n["pos"]
		nudged = true
	var merge := merge_target(at, layout, piece) if set_id == CAIRN else ""
	if merge == "":
		var j := jitter(piece, at)
		if validate(set_id, j, layout, ctx, piece) == VALID:
			at = j
	else:
		var mi := find(layout, merge)
		at = Vector2(float(layout[mi]["x"]), float(layout[mi]["y"]))
	return {"ok": true, "pos": at, "nudged": nudged, "socket": bool(s["socket"]), "family": s["family"],
		"reason": reason, "merge": merge}


func _line_samples(dy_dp: float, step_dp: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var step := maxf(1.0, step_dp)
	for i in _water.size() - 1:
		var a := Vector2(_water[i].x * w_dp, _water[i].y * h_dp + dy_dp)
		var b := Vector2(_water[i + 1].x * w_dp, _water[i + 1].y * h_dp + dy_dp)
		var length := a.distance_to(b)
		var n := maxi(1, floori(length / step))
		for k in n:
			var q := a.lerp(b, float(k) / float(n))
			out.append(Vector2(q.x / w_dp, q.y / h_dp))
	return out


# ================================================================= clusters and derived spots (§7)

## Placed units of [param set_id] grouped by cluster_link_dp linkage, in layout order.
func clusters(layout: Array[Dictionary], set_id: StringName, ignore: String = "") -> Array[Array]:
	var units := placed_units(layout, set_id, ignore)
	var link := float(set_def(set_id).get("cluster_link_dp", 0.0))
	var seen := {}
	var out: Array[Array] = []
	for i in units.size():
		if seen.has(i):
			continue
		var group: Array = []
		var queue: Array[int] = [i]
		seen[i] = true
		while not queue.is_empty():
			var j: int = queue.pop_front()
			group.append(units[j])
			for k in units.size():
				if seen.has(k):
					continue
				if dist_dp(_pos(units[j]), _pos(units[k])) <= link:
					seen[k] = true
					queue.append(k)
		out.append(group)
	return out


## Pebbles (cairn) or pieces in a cluster.
func _cluster_weight(layout: Array[Dictionary], set_id: StringName, cl: Array) -> int:
	if set_id != CAIRN:
		return cl.size()
	var n := 0
	for p: Variant in cl:
		n += stack_size(layout, String((p as Dictionary)["id"]))
	return n


static func _pos(p: Dictionary) -> Vector2:
	return Vector2(float(p["x"]), float(p["y"]))


static func _centroid(list: Array) -> Vector2:
	var c := Vector2.ZERO
	for p: Variant in list:
		c += _pos(p as Dictionary)
	return c / maxf(1.0, float(list.size()))


## Positions of the décor-gated spots from the placed pieces (decor_placement.json derived_spots):
## spot id -> Vector2. Always-on spots keep their authored position (not listed).
func derived_spots(layout: Array[Dictionary], ctx: Dictionary) -> Dictionary:
	var out := {}
	var defs: Dictionary = dp["derived_spots"]
	for sid_v: Variant in defs:
		var d: Variant = defs[sid_v]
		if not d is Dictionary:
			continue
		var sid := StringName(sid_v)
		out[sid] = _derived_spot(sid, d, layout, ctx, out)
	return out


func _derived_spot(sid: StringName, d: Dictionary, layout: Array[Dictionary], ctx: Dictionary,
		done: Dictionary) -> Vector2:
	var spot: Dictionary = content.spots_by_id.get(sid, {})
	var authored := Vector2(float(spot.get("x", 0.5)), float(spot.get("y", 0.5)))
	var set_id := StringName(d["set"])
	var off_v: Array = d.get("offset_dp", [0.0, 0.0])
	var off := Vector2(float(off_v[0]), float(off_v[1]))
	var best: Array = []
	var best_w := 0
	for cl: Array in clusters(layout, set_id):
		var w := _cluster_weight(layout, set_id, cl)
		if w >= int(d["min"]) and w > best_w:
			best = cl
			best_w = w
	var p := Vector2.INF
	if not best.is_empty():
		match String(d["place"]):
			"middle_piece":
				var xs := best.duplicate()
				xs.sort_custom(func(a: Variant, b: Variant) -> bool:
					return float((a as Dictionary)["x"]) < float((b as Dictionary)["x"]))
				p = _pos(xs[floori(xs.size() * 0.5)] as Dictionary)
			"beside_tallest_stack":
				var tall: Dictionary = best[0]
				for s: Variant in best:
					if stack_size(layout, String((s as Dictionary)["id"])) > stack_size(layout, String(tall["id"])):
						tall = s
				p = offset_norm(_pos(tall), off)
			"beside_cluster":
				p = offset_norm(_centroid(best), off)
			_:
				p = _centroid(best)
	else:
		var all := placed_units(layout, set_id)
		if not all.is_empty():
			p = offset_norm(_centroid(all), off)
	if p == Vector2.INF:
		return authored
	var dir := off.normalized() if off.length() > 0.0 else Vector2(0.0, 1.0)
	var moved := 0.0
	while moved <= SPOT_STEP_MAX_DP:
		var q := offset_norm(p, dir * moved)
		if _spot_ok(sid, q, ctx, done):
			return q
		moved += SPOT_STEP_DP
	return authored


func _spot_ok(sid: StringName, q: Vector2, ctx: Dictionary, done: Dictionary) -> bool:
	if _prop_blocked(q, 0.0, ctx, true):
		return false
	for s: Dictionary in content.spots:
		var other := StringName(s["id"])
		if other == sid:
			continue
		var at: Vector2 = done.get(other, Vector2(float(s["x"]), float(s["y"])))
		if dist_dp(q, at) < SPOT_MIN_GAP_DP:
			return false
	return true


# ================================================================= auto place and migration

## Where a new copy of [param set_id] (copy index [param n]) goes (ACTIVE_DECOR §12): its legacy
## anchor if valid and free, else the best socket near the set's largest cluster, else a spiral
## from anchors[0]. {ok: false} = the tray (practically never).
func auto_place(set_id: StringName, n: int, layout: Array[Dictionary], ctx: Dictionary,
		piece: String = "") -> Dictionary:
	var anchors: Array = (content.anchors_by_decor.get(set_id, {}) as Dictionary).get("positions", [])
	if n < anchors.size():
		var a := Vector2(float(anchors[n][0]), float(anchors[n][1]))
		if validate(set_id, a, layout, ctx, piece) == VALID and (set_id != CAIRN or merge_target(a, layout, piece) == ""):
			return {"ok": true, "pos": a}
	var cls := clusters(layout, set_id, piece)
	if not cls.is_empty():
		var big: Array = cls[0]
		for cl: Array in cls:
			if cl.size() > big.size():
				big = cl
		var c := _centroid(big)
		var best := {}
		var best_d := INF
		for s: Dictionary in sockets(set_id, layout, ctx, piece):
			if StringName(s["family"]) != &"same_set_ring" and StringName(s["family"]) != &"ring_around_cluster":
				continue
			var d := dist_dp(c, s["pos"])
			if d < best_d:
				best_d = d
				best = s
		if not best.is_empty():
			return {"ok": true, "pos": best["pos"]}
	if anchors.is_empty():
		return {"ok": false, "pos": Vector2.ZERO}
	var a0 := Vector2(float(anchors[0][0]), float(anchors[0][1]))
	var ap: Dictionary = dp["auto_place"]
	var step := float(ap["spiral_step_dp"])
	var r := 0.0
	while r <= float(ap["spiral_max_dp"]) + 1e-6:
		var m := 1 if r == 0.0 else maxi(RING_MIN_SAMPLES, ceili(TAU * r / step))
		for k in m:
			var ang := TAU * float(k) / float(m)
			var q := offset_norm(a0, Vector2(cos(ang), sin(ang)) * r)
			if validate(set_id, q, layout, ctx, piece) == VALID and (set_id != CAIRN or merge_target(q, layout, piece) == ""):
				return {"ok": true, "pos": q}
		r += step
	return {"ok": false, "pos": a0}


## A new layout record (placed unless [param pos_ok] is false: then it waits in the tray).
static func make_piece(set_id: StringName, n: int, pos: Vector2, pos_ok: bool) -> Dictionary:
	return {"id": piece_id(set_id, n), "set": String(set_id), "x": pos.x, "y": pos.y, "rot": 0,
		"stored": not pos_ok, "stack": "", "level": 0}


## Fixed anchors -> free positions (GDD §14.9 step 1): copy n of each movable set takes
## anchors[n] verbatim (rot 0, placed), the lantern jitter baked into x, every cairn copy one stack
## at anchors[0]; only the hard exclusions nudge a piece (today pinwheels 4 and 8 under the tea
## nook). [param owned] is WorldState.owned. Returns the new layout; nothing is ever dropped.
func migrate_v1(owned: Dictionary, ctx: Dictionary) -> Array[Dictionary]:
	var layout: Array[Dictionary] = []
	for d: Dictionary in content.decor:
		var set_id := StringName(d["id"])
		if not content.is_movable_decor(set_id):
			continue
		var n := int(owned.get(String(set_id), 0))
		var anchors: Array = (content.anchors_by_decor.get(set_id, {}) as Dictionary).get("positions", [])
		for i in n:
			var src: Variant = anchors[0 if set_id == CAIRN else mini(i, anchors.size() - 1)]
			var p := Vector2(float(src[0]), float(src[1]))
			if set_id == LANTERN:
				p.x += legacy_lantern_jitter_px(i) / (w_dp * _px_per_dp())
			var rec := make_piece(set_id, i, p, true)
			if set_id == CAIRN and i > 0:
				rec["stack"] = piece_id(set_id, 0)
				rec["level"] = i
			layout.append(rec)
	for rec: Dictionary in layout:
		var set_id := StringName(rec["set"])
		if set_id == CAIRN and String(rec["stack"]) != "":
			continue
		var p := _pos(rec)
		if validate_hard(set_id, p, ctx) != R_PROP:
			continue
		var none: Array[Dictionary] = []
		var n := _ring_search(set_id, p, func(q: Vector2) -> bool: return validate_hard(set_id, q, ctx) == VALID, none)
		if bool(n["ok"]):
			_move_unit(layout, rec, n["pos"])
	return layout


## The MVP DecorLayer lantern jitter of copy [param i] in design px (hash([id, i]) seeded RNG).
static func legacy_lantern_jitter_px(i: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(LANTERN), i])
	return rng.randf_range(-1.0, 1.0) * LANTERN_JITTER_PX


func _px_per_dp() -> float:
	return float((content.spots_doc.get("frame", {}) as Dictionary).get("px_per_dp", 3.0))


## Moves a piece (a cairn base carries its whole stack).
static func _move_unit(layout: Array[Dictionary], rec: Dictionary, p: Vector2) -> void:
	var id := String(rec["id"])
	for q: Dictionary in layout:
		if String(q["id"]) == id or String(q["stack"]) == id:
			q["x"] = p.x
			q["y"] = p.y


## Owned movable copies missing from [param layout] get records (auto placed, else stored):
## a purchase on an older build, or a fixture. Returns the ids added.
func sync_owned(layout: Array[Dictionary], owned: Dictionary, ctx: Dictionary) -> PackedStringArray:
	var added := PackedStringArray()
	for d: Dictionary in content.decor:
		var set_id := StringName(d["id"])
		if not content.is_movable_decor(set_id):
			continue
		var n := int(owned.get(String(set_id), 0))
		for i in n:
			var id := piece_id(set_id, i)
			if find(layout, id) >= 0:
				continue
			var spot := auto_place(set_id, i, layout, ctx, id)
			layout.append(make_piece(set_id, i, spot["pos"], bool(spot["ok"])))
			added.append(id)
	return added
