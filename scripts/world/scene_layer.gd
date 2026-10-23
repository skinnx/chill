class_name SceneLayer
extends Node2D
## Away scenes in the hollow (Retention v1 F3, GDD §13.4, `scenes.json`): the props half.
##
## Come back after two hours and something may have happened while you were away: a nap pile on
## the sun stone, a wobbly pebble tower, a leaf fort, two friends watching the moon. The sim
## picks the scene, casts it and keeps it pending until the player taps it or 600 s of foreground
## time pass; then it is archived to Album › Memories. The creatures themselves are staged by the
## CreatureLayer (the cast walks or fades to its slots and holds the scene's pose). This layer
## draws the scene's PROPS (`scene_pebble_tower`, `scene_leaf_fort`, `scene_flower_crown`,
## `scene_boat_line`), fades them in with the scene and out when it is archived, and is the prop's
## tap target: tapping a prop archives the scene exactly as tapping a participant does.
##
## It owns no state the sim does not: it reads [method Game.pending_scene] and calls
## [method Game.tap_scene]. Drawing is one draw_polygon (WorldTris), procedural, no textures.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const CUE_TOUCH := &"S01"
## scenes.json audio_cue: plays as the scene fades in (S25; unvoiced until the audio build lands).
const CUE_STAGED := &"S25"
const FADE_S := 0.6
const FADE_OUT_S := 0.4
## A prop's hit radius (dp): a generous, forgiving target - a scene is there to be looked at.
const HIT_DP := 44.0
const PRESS_SQUASH := 0.94
const PRESS_S := 0.12
## The nap-ish scene poses: the cast sleeps; everyone else stands, looks and beams.
const NAP_POSES: Array[StringName] = [&"scene_pile_bottom", &"scene_pile_middle", &"scene_pile_top",
	&"pair_nap_back_to_back"]
const SIT_POSES: Array[StringName] = [&"scene_moon_sit", &"scene_moon_sit_lean"]
## Poses that face the player rather than the scene's centre.
const PROUD_POSES: Array[StringName] = [&"scene_tower_proud", &"scene_crown_wear", &"scene_regatta_wave"]
## The spot id a staged mossling performs at (no real spot: nothing in the rig is keyed on it).
const SCENE_SPOT := &"scene"
const IDLE := &"idle"
const HAPPY_S := 3.0

static var current: SceneLayer = null

var _content: GameContent
var _dp: float = 3.0
## The staged scene (Game.pending_scene view) or {}.
var _scene: Dictionary = {}
var _t: float = 0.0
## Fade-out progress once archived (-1 = not leaving).
var _out: float = -1.0
var _press: float = -1.0
## Prop records of the staged scene: {id, pos (design px)}.
var _props: Array[Dictionary] = []
var _materials: Dictionary = {}


func _ready() -> void:
	current = self
	add_to_group(WorldPan.GROUP_HIT)
	_content = ContentRegistry.content
	if _content != null:
		_dp = float((_content.spots_doc["frame"] as Dictionary)["px_per_dp"])
		_materials = _content.palettes.get("materials", {})
	if Game.world_ready.is_connected(_on_world_ready):
		return
	Game.world_ready.connect(_on_world_ready)
	Game.scene_ready.connect(func(_sc: Dictionary) -> void: sync())
	Game.scene_archived.connect(func(_m: Dictionary) -> void: sync())


func _exit_tree() -> void:
	if current == self:
		current = null


func _on_world_ready(_recap: Array) -> void:
	sync()


## Takes the sim's pending scene as the truth: a new one fades in (with S25), a gone one fades out.
func sync() -> void:
	if not Game.is_ready or Game.sim == null:
		return
	var sc := Game.pending_scene()
	if sc.is_empty():
		if not _scene.is_empty() and _out < 0.0:
			_out = 0.0
			set_process(true)
		return
	if String(sc.get("scene", "")) == String(_scene.get("scene", "")) and _out < 0.0:
		return
	_scene = sc
	_t = 0.0
	_out = -1.0
	_press = -1.0
	_props.clear()
	var id := StringName(String(sc["scene"]))
	var def: Dictionary = _content.scenes_by_id.get(id, {})
	var props: Array = def.get("props", [])
	for i in props.size():
		_props.append({"id": StringName(String((props[i] as Dictionary)["id"])), "pos": prop_px(_content, id, i, sc["cast"])})
	AudioDirector.play_cue(CUE_STAGED, {"haptic": false})
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	var busy := _t < FADE_S
	if _press >= 0.0:
		_press += delta
		busy = busy or _press < PRESS_S
	if _out >= 0.0:
		_out += delta
		if _out >= FADE_OUT_S:
			_scene = {}
			_props.clear()
			_out = -1.0
		else:
			busy = true
	set_process(busy)
	queue_redraw()


## The staged scene's id, or &"" (tests, the debug overlay).
func scene_id() -> StringName:
	return StringName(String(_scene.get("scene", "")))


func is_leaving() -> bool:
	return _out >= 0.0


# ------------------------------------------------------------------ geometry (shared with the creature layer)

## Where a scene is anchored (design px): a spot, a frame point, or the pair lead's nest.
static func anchor_px(content: GameContent, scene: StringName, cast: Array) -> Vector2:
	var def: Dictionary = content.scenes_by_id.get(scene, {})
	var a: Dictionary = def.get("anchor", {})
	if a.has("spot"):
		var sp: Dictionary = content.spots_by_id.get(StringName(String(a["spot"])), {})
		return GardenRules.frame_to_px(content, Vector2(float(sp.get("x", 0.5)), float(sp.get("y", 0.6))))
	if a.has("nest_of"):
		var lead := StringName(String(cast[0])) if not cast.is_empty() else &""
		var nest := Game.nest_state(lead) if Game.is_ready and lead != &"" else {}
		if not nest.is_empty():
			return GardenRules.frame_to_px(content, Vector2(float(nest["x"]), float(nest["y"])))
		# no nest yet (a fixture, or ♥4 reached before ♥3 on an old save): the lead's favourite spot
		var fav: Dictionary = content.spots_by_id.get(
				StringName(String((content.species_by_id.get(lead, {}) as Dictionary).get("favourite_spot", ""))), {})
		return GardenRules.frame_to_px(content, Vector2(float(fav.get("x", 0.5)), float(fav.get("y", 0.6))))
	return GardenRules.frame_to_px(content, Vector2(float(a.get("x", 0.5)), float(a.get("y", 0.6))))


## Role [param i]'s feet (design px): the anchor plus the role's slot_dp.
static func slot_px(content: GameContent, scene: StringName, i: int, cast: Array) -> Vector2:
	var def: Dictionary = content.scenes_by_id.get(scene, {})
	var roles: Array = def.get("roles", [])
	var off: Array = (roles[i] as Dictionary).get("slot_dp", [0, 0]) if i < roles.size() else [0, 0]
	return anchor_px(content, scene, cast) + Vector2(float(off[0]), float(off[1])) * _dp_of(content)


## Prop [param i]'s foot (design px).
static func prop_px(content: GameContent, scene: StringName, i: int, cast: Array) -> Vector2:
	var def: Dictionary = content.scenes_by_id.get(scene, {})
	var props: Array = def.get("props", [])
	var off: Array = (props[i] as Dictionary).get("slot_dp", [0, 0]) if i < props.size() else [0, 0]
	return anchor_px(content, scene, cast) + Vector2(float(off[0]), float(off[1])) * _dp_of(content)


static func _dp_of(content: GameContent) -> float:
	return float((content.spots_doc.get("frame", {}) as Dictionary).get("px_per_dp", 3.0))


## What a staged mossling does for a scene pose: {behaviour, params} for Mossling.perform. The
## scene poses are rig work still to come (GDD §13.4 pose ids); until then the nap scenes sleep,
## the moon watchers sit by the brook, and everyone else stands at their slot, looks at the thing
## (or at you, if they are the proud one) and beams.
static func scene_pose(pose: StringName, slot: Vector2, anchor: Vector2) -> Dictionary:
	if NAP_POSES.has(pose):
		return {"behaviour": Mossling.B_NAP, "params": {}}
	if SIT_POSES.has(pose):
		return {"behaviour": Mossling.B_STREAM, "params": {"look": -0.6 if slot.x <= anchor.x else 0.6}}
	var look := 0.0
	if not PROUD_POSES.has(pose) and absf(anchor.x - slot.x) > 1.0:
		look = 0.6 * signf(anchor.x - slot.x)
	return {"behaviour": IDLE, "params": {"look": look, "look_hold_s": 600.0, "happy_s": HAPPY_S}}


# ------------------------------------------------------------------ world target (the props)

func world_hit(canvas_pos: Vector2, slop: float) -> Dictionary:
	if _props.is_empty() or _out >= 0.0:
		return {}
	var pos := get_global_transform_with_canvas().affine_inverse() * canvas_pos
	var best := {}
	for i in _props.size():
		var c: Vector2 = _props[i]["pos"] + Vector2(0.0, -HIT_DP * _dp * 0.5)
		var cand := WorldPan.circle_hit(pos, c, HIT_DP * _dp * 0.5, slop, WorldPan.PRIO_SCENE, i)
		if not cand.is_empty() and (best.is_empty() or WorldPan.better(cand, best)):
			best = cand
	return best


func world_press(_key: Variant, _canvas_pos: Vector2) -> void:
	if _props.is_empty():
		return
	_press = 0.0
	AudioDirector.play_cue(CUE_TOUCH, {"world": true, "position": get_global_transform() * _props[0]["pos"]})
	set_process(true)
	queue_redraw()


func world_release(_key: Variant, _canvas_pos: Vector2, act: bool) -> void:
	_press = -1.0
	if act and not _scene.is_empty() and _out < 0.0:
		Game.tap_scene()  # the sim archives it and emits scene_archived; sync() then fades us out
	queue_redraw()


func world_hit_shapes() -> Array:
	var out: Array = []
	if _out >= 0.0:
		return out
	var xf := get_global_transform_with_canvas()
	for i in _props.size():
		var c: Vector2 = _props[i]["pos"] + Vector2(0.0, -HIT_DP * _dp * 0.5)
		out.append({"kind": "circle", "c": xf * c, "r": HIT_DP * _dp * 0.5 * xf.get_scale().x,
			"prio": WorldPan.PRIO_SCENE, "name": String(_props[i]["id"])})
	return out


func a11y_label() -> String:
	return tr("A11Y_SCENE") if not _scene.is_empty() else ""


# ------------------------------------------------------------------ drawing

func _mat(id: String, part: String, alpha: float = 1.0) -> Color:
	var m: Dictionary = _materials.get(id, {})
	var c := Color.html(String(m.get(part, "#C9BFA8")))
	c.a = alpha
	return c


func _draw() -> void:
	if _props.is_empty():
		return
	var a := clampf(_t / FADE_S, 0.0, 1.0)
	if _out >= 0.0:
		a *= 1.0 - clampf(_out / FADE_OUT_S, 0.0, 1.0)
	if a <= 0.004:
		return
	var k := 1.0
	if _press >= 0.0:
		k = lerpf(PRESS_SQUASH, 1.0, clampf(_press / PRESS_S, 0.0, 1.0))
	var tris := WorldTris.new()
	for p: Dictionary in _props:
		var foot: Vector2 = p["pos"]
		match StringName(p["id"]):
			&"scene_pebble_tower":
				_pebble_tower(tris, foot, k, a)
			&"scene_leaf_fort":
				_leaf_fort(tris, foot, k, a)
			&"scene_flower_crown":
				_flower_crown(tris, foot, k, a)
			&"scene_boat_line":
				_boat_line(tris, foot, k, a)
	tris.flush(self)


## Five pebbles, each a little smaller and a little off-centre: wobbly, and very proud.
func _pebble_tower(tris: WorldTris, foot: Vector2, k: float, a: float) -> void:
	var y := foot.y
	var w := 16.0 * _dp
	var wobble := [0.0, 2.0, -3.0, 1.5, -1.0]
	for i in 5:
		var half := Vector2(w * (1.0 - 0.14 * float(i)) * 0.5, w * 0.34 * (1.0 - 0.1 * float(i))) * k
		var c := Vector2(foot.x + float(wobble[i]) * _dp * 0.5, y - half.y)
		var mat := "stone_cool" if i % 2 == 0 else "pebble_alt"
		tris.blob(c + Vector2(0.0, 3.0), half, _mat(mat, "shade", a))
		tris.blob(c, half, _mat(mat, "lit", a))
		tris.blob(c + Vector2(-half.x * 0.3, -half.y * 0.3), half * 0.35, _mat(mat, "detail", a * 0.6), 8)
		y -= half.y * 1.6


## Three big leaves leaning into a little tent, two peekers in the gap.
func _leaf_fort(tris: WorldTris, foot: Vector2, k: float, a: float) -> void:
	var h := 40.0 * _dp * k
	var w := 26.0 * _dp * k
	var lit := _mat("willow_leaf", "lit", a)
	var shade := _mat("willow_leaf", "shade", a)
	tris.blob_rot(foot + Vector2(-w * 0.55, -h * 0.45), Vector2(h * 0.55, w * 0.38), -1.15, shade)
	tris.blob_rot(foot + Vector2(w * 0.55, -h * 0.45), Vector2(h * 0.55, w * 0.38), 1.15, lit)
	tris.blob_rot(foot + Vector2(0.0, -h * 0.72), Vector2(h * 0.4, w * 0.3), 0.0, _mat("willow_leaf", "detail", a))
	tris.stroke(foot + Vector2(-w * 0.9, 0.0), foot + Vector2(-w * 0.2, -h * 0.85), 2.5, _mat("wood_bark", "shade", a))
	tris.stroke(foot + Vector2(w * 0.9, 0.0), foot + Vector2(w * 0.2, -h * 0.85), 2.5, _mat("wood_bark", "shade", a))


## A ring of petals sitting where the wearer's head is.
func _flower_crown(tris: WorldTris, foot: Vector2, k: float, a: float) -> void:
	var r := 11.0 * _dp * k
	var petal := _mat("toadstool_cap", "lit", a)
	var petal2 := _mat("pinwheel_b", "lit", a)
	var heart := _mat("pinwheel_b", "detail", a)
	for i in 7:
		var ang := TAU * float(i) / 7.0
		var c := foot + Vector2(cos(ang) * r, sin(ang) * r * 0.45)
		tris.blob(c, Vector2(r * 0.42, r * 0.36), petal if i % 2 == 0 else petal2, 8)
		tris.blob(c, Vector2(r * 0.16, r * 0.14), heart, 6)
	tris.stroke(foot + Vector2(-r, 0.0), foot + Vector2(r, 0.0), 2.0, _mat("willow_leaf", "shade", a * 0.7))


## Three leaf boats lined up on the bank, sails up, ready for the parade.
func _boat_line(tris: WorldTris, foot: Vector2, k: float, a: float) -> void:
	var w := 14.0 * _dp * k
	var hull := _mat("leaf_boat", "lit", a)
	var hull2 := _mat("leaf_boat", "shade", a)
	var sail := _mat("leaf_boat", "detail", a)
	for i in 3:
		var c := foot + Vector2((float(i) - 1.0) * w * 1.5, 0.0)
		tris.blob(c + Vector2(0.0, 2.0), Vector2(w * 0.5, w * 0.2), hull2)
		tris.blob(c, Vector2(w * 0.5, w * 0.18), hull)
		tris.tri(c + Vector2(0.0, -w * 0.05), c + Vector2(0.0, -w * 0.75), c + Vector2(w * 0.32, -w * 0.25), sail)
		tris.stroke(c, c + Vector2(0.0, -w * 0.78), 1.5, _mat("wood_bark", "lit", a))
