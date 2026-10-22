class_name ActiveRules
extends RefCounted
## Active Play v1 (GDD §14): the three linked features and their glue. [WorldSim] owns one
## instance ([member WorldSim.active]); it holds the pure rule objects and the feature flags, runs
## the one content-aware migration (GDD §14.9) and owns the Active F3 layout operations (move,
## turn, put away, take out, lift a pebble, one-step undo) on top of [DecorPlacementRules].
##
##  * [member wishes] Active F1 [WishRules]   * [member tea] Active F2 [TeaRules]
##  * [member decor] Active F3 [DecorPlacementRules] (pure; the front-end calls it too)
##
## Like [RetentionRules] the world is passed in as [param sim] on every call (no RefCounted cycle).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const FEATURE_WISHES := &"wishes"
const FEATURE_TEA := &"tea"
const FEATURE_FREE_DECOR := &"free_decor"
## Build constant (GDD §14.11 a1): every Active Play feature is on in v1.
const FEATURES_V1 := {&"wishes": true, &"tea": true, &"free_decor": true}
const OP_MOVE := &"move"
const OP_TURN := &"turn"
const OP_PUT_AWAY := &"put_away"
const OP_TAKE_OUT := &"take_out"
const OP_LIFT_PEBBLE := &"lift_pebble"
const OP_MERGE := &"merge_stack"

var content: GameContent
var wishes: WishRules
var tea: TeaRules
var decor: DecorPlacementRules
## Feature flags (Game.feature_on); tests may switch one off.
var features: Dictionary = FEATURES_V1.duplicate()
## Edit mode is on (Active F3): wish checks pause, still pieces become edit targets.
var edit_mode: bool = false
## The one-step undo of this edit session: the layout before the last commit ([] = nothing).
var _undo: Array[Dictionary] = []
var _undo_op: StringName = &""
## Derived spot positions, recomputed on edit-mode exit and on load (never mid-drag).
var _spots: Dictionary = {}


func _init(p_content: GameContent) -> void:
	content = p_content
	wishes = WishRules.new(content)
	tea = TeaRules.new(content)
	decor = DecorPlacementRules.new(content)


func feature_on(flag: StringName) -> bool:
	return bool(features.get(flag, false))


# ================================================================= migration (GDD §14.9)

## The content-aware Active Play step, run once from WorldSim._init when active_v < 1 (after the
## retention migration): fixed décor anchors -> free positions (nothing visible moves except the
## two pinwheels under the tea nook), tea unlocked if onboarding is done and a stem blooms, no
## wish open. Affection, hearts, owned and every Retention field are untouched.
func migrate_v1(sim: WorldSim) -> void:
	var st := sim.state
	if st.decor_layout.is_empty():
		st.decor_layout = decor.migrate_v1(st.owned, context(sim))
	if feature_on(FEATURE_TEA):
		tea.check_unlock(sim, st.t)
	st.active_v = WorldState.ACTIVE_VERSION


## Load-time bookkeeping (every load, after the migration): owned copies missing from the layout
## get a place, and the derived spots are computed.
func on_load(sim: WorldSim) -> void:
	decor.sync_owned(sim.state.decor_layout, sim.state.owned, context(sim))
	refresh_spots(sim)


## {"nests": built nest centres, "tea": the tea nook stands} for [DecorPlacementRules].
func context(sim: WorldSim) -> Dictionary:
	var nests: Array[Vector2] = []
	for sp: String in sim.state.nests:
		var a: Dictionary = content.nest_anchor_by_species.get(StringName(sp), {})
		if not a.is_empty():
			nests.append(Vector2(float(a["x"]), float(a["y"])))
	return {"nests": nests, "tea": feature_on(FEATURE_TEA)}


# ================================================================= spots and counts

func refresh_spots(sim: WorldSim) -> void:
	_spots = decor.derived_spots(sim.state.decor_layout, context(sim))


## A spot's position now (derived spots follow the placed pieces; GDD §14.11 Game.spot_position).
func spot_pos(spot_id: StringName) -> Vector2:
	if _spots.has(spot_id):
		return _spots[spot_id]
	var s: Dictionary = content.spots_by_id.get(spot_id, {})
	return Vector2(float(s.get("x", 0.5)), float(s.get("y", 0.5)))


func favourite_spot_pos(_sim: WorldSim, species: StringName) -> Vector2:
	var sdef: Dictionary = content.species_by_id.get(species, {})
	return spot_pos(StringName(sdef.get("favourite_spot", "")))


## Placed copies of a set (wish gates); a set that is not movable (the chime) counts owned.
func decor_placed_count(sim: WorldSim, set_id: StringName) -> int:
	if not content.is_movable_decor(set_id) or not feature_on(FEATURE_FREE_DECOR):
		return sim.owned_count(set_id)
	return decor.placed_count(sim.state.decor_layout, set_id)


# ================================================================= Active F3 layout operations

## A purchase: the new copy gets its place (cairn: onto the tallest stack with room, else a new
## stack) and decor_placed fires. Called by WorldSim.buy_decor after the copy is owned.
func on_decor_bought(sim: WorldSim, set_id: StringName, n: int) -> void:
	if not content.is_movable_decor(set_id):
		return
	var st := sim.state
	var id := DecorPlacementRules.piece_id(set_id, n)
	if DecorPlacementRules.find(st.decor_layout, id) >= 0:
		return
	var ctx := context(sim)
	if set_id == DecorPlacementRules.CAIRN:
		var base := _stack_with_room(sim)
		if base != "":
			var bi := DecorPlacementRules.find(st.decor_layout, base)
			var b: Dictionary = st.decor_layout[bi]
			var rec := DecorPlacementRules.make_piece(set_id, n, Vector2(float(b["x"]), float(b["y"])), true)
			rec["stack"] = base
			rec["level"] = decor.stack_size(st.decor_layout, base)
			st.decor_layout.append(rec)
			_placed(sim, rec)
			return
	var spot := decor.auto_place(set_id, n, st.decor_layout, ctx, id)
	var piece := DecorPlacementRules.make_piece(set_id, n, spot["pos"], bool(spot["ok"]))
	st.decor_layout.append(piece)
	if bool(spot["ok"]):
		_placed(sim, piece)
	else:
		sim.emit_event(WorldSim.EV_DECOR_STORED, {"set": set_id, "piece": id})
	refresh_spots(sim)


func _stack_with_room(sim: WorldSim) -> String:
	var best := ""
	var best_n := 0
	var cap := int(content.placement_set(DecorPlacementRules.CAIRN).get("stack_max", 10))
	for p: Dictionary in decor.placed_units(sim.state.decor_layout, DecorPlacementRules.CAIRN):
		var n := decor.stack_size(sim.state.decor_layout, String(p["id"]))
		if n < cap and n > best_n:
			best_n = n
			best = String(p["id"])
	return best


func _placed(sim: WorldSim, rec: Dictionary) -> void:
	var pos := Vector2(float(rec["x"]), float(rec["y"]))
	var set_id := StringName(rec["set"])
	sim.emit_event(WorldSim.EV_DECOR_PLACED, {"set": set_id, "piece": String(rec["id"]), "pos": pos,
		"rot_deg": int(rec["rot"]) * 360 / decor.rot_steps(set_id)})
	wishes.on_decor_placed(sim, set_id, pos, sim.state.t)


func set_edit_mode(sim: WorldSim, on: bool) -> bool:
	if on == edit_mode or not feature_on(FEATURE_FREE_DECOR):
		return false
	edit_mode = on
	_undo = []
	_undo_op = &""
	if not on:
		refresh_spots(sim)
	sim.emit_event(WorldSim.EV_DECOR_EDIT, {"on": on})
	return true


## Moves (drop or tap-then-tap glide) piece [param id] to [param pos]: snap, nudge or float home
## (ACTIVE_DECOR §4.4, §5). A stored piece is taken out. A cairn base carries its stack; a drop on a
## stack merges. Returns {ok, pos, nudged, socket, reason, merge}; ok false changes nothing.
func move(sim: WorldSim, id: String, pos: Vector2, rot: int = -1) -> Dictionary:
	var st := sim.state
	var i := DecorPlacementRules.find(st.decor_layout, id)
	if i < 0 or not feature_on(FEATURE_FREE_DECOR):
		return {"ok": false, "pos": pos, "nudged": false, "socket": false, "reason": DecorPlacementRules.R_NOT_MOVABLE,
			"merge": ""}
	var rec: Dictionary = st.decor_layout[i]
	var set_id := StringName(rec["set"])
	var res := decor.resolve_drop(set_id, pos, st.decor_layout, context(sim), id)
	if not bool(res["ok"]):
		return res
	var was_stored := bool(rec["stored"])
	_snapshot(OP_TAKE_OUT if was_stored else (OP_MERGE if String(res["merge"]) != "" else OP_MOVE), st)
	var at: Vector2 = res["pos"]
	var merge := String(res["merge"])
	if merge != "":
		# every pebble carried (a base takes its stack) joins the target stack on top
		var level := decor.stack_size(st.decor_layout, merge)
		for q: Dictionary in st.decor_layout:
			if String(q["id"]) == id or String(q["stack"]) == id:
				q["stack"] = merge
				q["level"] = level
				q["x"] = at.x
				q["y"] = at.y
				q["stored"] = false
				level += 1
	else:
		if set_id == DecorPlacementRules.CAIRN and String(rec["stack"]) != "":
			_detach_pebble(st, rec)
		for q: Dictionary in st.decor_layout:
			if String(q["id"]) == id or String(q["stack"]) == id:
				q["x"] = at.x
				q["y"] = at.y
				q["stored"] = false
	if rot >= 0:
		rec["rot"] = posmod(rot, decor.rot_steps(set_id))
	_placed(sim, rec)
	res["pos"] = at
	return res


## A loose pebble leaves its stack: the stack above it closes the gap.
func _detach_pebble(st: WorldState, rec: Dictionary) -> void:
	var base := String(rec["stack"])
	var lvl := int(rec["level"])
	for q: Dictionary in st.decor_layout:
		if String(q["stack"]) == base and int(q["level"]) > lvl:
			q["level"] = int(q["level"]) - 1
	rec["stack"] = ""
	rec["level"] = 0


## Turn one step (rot_steps per set). Returns the new step or -1.
func turn(sim: WorldSim, id: String) -> int:
	var st := sim.state
	var i := DecorPlacementRules.find(st.decor_layout, id)
	if i < 0 or not feature_on(FEATURE_FREE_DECOR):
		return -1
	var rec: Dictionary = st.decor_layout[i]
	var steps := decor.rot_steps(StringName(rec["set"]))
	if steps <= 1:
		return -1
	_snapshot(OP_TURN, st)
	rec["rot"] = posmod(int(rec["rot"]) + 1, steps)
	if not bool(rec["stored"]):
		_placed(sim, rec)
	return int(rec["rot"])


## Tuck a piece into the tray (a cairn base takes its whole stack). It keeps counting for friends.
func store(sim: WorldSim, id: String) -> bool:
	var st := sim.state
	var i := DecorPlacementRules.find(st.decor_layout, id)
	if i < 0 or bool(st.decor_layout[i]["stored"]) or not feature_on(FEATURE_FREE_DECOR):
		return false
	_snapshot(OP_PUT_AWAY, st)
	var rec: Dictionary = st.decor_layout[i]
	if String(rec["stack"]) != "":
		_detach_pebble(st, rec)
		rec["stored"] = true
	else:
		for q: Dictionary in st.decor_layout:
			if String(q["id"]) == id or String(q["stack"]) == id:
				q["stored"] = true
	sim.emit_event(WorldSim.EV_DECOR_STORED, {"set": StringName(rec["set"]), "piece": id})
	return true


## Takes one stored piece of [param set_id] out to [param pos] (or, with pos = Vector2.INF,
## "Find a spot": auto place). Returns the move result plus "piece".
func take_out(sim: WorldSim, set_id: StringName, pos: Vector2) -> Dictionary:
	var st := sim.state
	var id := ""
	for q: Dictionary in st.decor_layout:
		if StringName(q["set"]) == set_id and bool(q["stored"]):
			id = String(q["id"])
			break
	if id == "":
		return {"ok": false, "reason": DecorPlacementRules.R_NOT_MOVABLE, "piece": ""}
	# a stored cairn pebble comes out alone (a new stack of 1)
	for q: Dictionary in st.decor_layout:
		if String(q["stack"]) == id:
			q["stack"] = ""
			q["level"] = 0
	var at := pos
	if pos == Vector2.INF:
		var n := int(id.get_slice(DecorPlacementRules.ID_SEP, 1))
		var spot := decor.auto_place(set_id, n, st.decor_layout, context(sim), id)
		if not bool(spot["ok"]):
			return {"ok": false, "reason": DecorPlacementRules.R_RETURNED, "piece": id}
		at = spot["pos"]
	var res := move(sim, id, at)
	res["piece"] = id
	return res


## "Lift a pebble": the top pebble of a stack becomes a loose piece in the hand (still placed at
## the stack until it is set down). Returns its id or "".
func lift_pebble(sim: WorldSim, stack_id: String) -> String:
	var st := sim.state
	var top := ""
	var top_lvl := 0
	for q: Dictionary in st.decor_layout:
		if String(q["stack"]) == stack_id and int(q["level"]) >= top_lvl:
			top_lvl = int(q["level"])
			top = String(q["id"])
	if top == "":
		return ""
	_snapshot(OP_LIFT_PEBBLE, st)
	var rec: Dictionary = st.decor_layout[DecorPlacementRules.find(st.decor_layout, top)]
	_detach_pebble(st, rec)
	return top


## Reverts the last commit of this edit session (one step). False if there is nothing to undo.
func undo(sim: WorldSim) -> bool:
	if _undo.is_empty() and _undo_op == &"":
		return false
	var st := sim.state
	st.decor_layout = _undo
	_undo = []
	var op := _undo_op
	_undo_op = &""
	sim.emit_event(WorldSim.EV_DECOR_UNDONE, {"op": op})
	return true


func can_undo() -> bool:
	return _undo_op != &""


func _snapshot(op: StringName, st: WorldState) -> void:
	_undo = []
	for q: Dictionary in st.decor_layout:
		_undo.append(q.duplicate())
	_undo_op = op


# ================================================================= E1 and E6

## GDD §14.9: pending + granted wishes, stamps, petals in jars and ready on stems, recipes,
## teaware, cups offered, owned movable copies in the layout. None may ever decrease.
func monotone_items(sim: WorldSim) -> Dictionary:
	var st := sim.state
	var jars := 0
	for f: String in st.pantry:
		jars += int(st.pantry[f])
	var pot_petals := (st.pot["petals"] as Array).size()
	return {"wishes_pending_and_granted": st.wishes.size() + st.wishes_granted, "wish_stamps": wishes.stamp_count(sim),
		"wishes_granted": st.wishes_granted, "petals_ready_and_held": tea.petals_ready(sim, &"", st.t) + jars + pot_petals,
		"recipes_found": st.recipes_found.size(), "teaware_owned": st.teaware_owned.size(), "cups_offered": st.cups_offered,
		"cups_and_offered": st.tray.size() + st.cups_offered,
		"decor_layout": st.decor_layout.size()}
