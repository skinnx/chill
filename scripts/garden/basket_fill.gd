class_name BasketFill
extends Node2D
## What is waiting in the in-world basket (Art Bible §6.5 basket fill states, §6.7; GDD §5.7):
## min(gifts, 12) gold-glass dew drops and up to 3 gift items (the newest) peeking over the rim,
## and a gentle gold glint (halo_add r0 10 px, breathing k 76) once anything is inside.
##
## The basket itself is a prop (art/props, PropsLayer). This node sorts right after it (its
## y-sort origin + a hair) and draws, in order: dew drops and gifts in the opening, then a copy of
## the basket's front rim (decor atlas basket_rim, same 140 x 116 frame as props_svg.py basket()),
## so the gifts sit INSIDE the basket instead of floating in front of it. A new gift pops in
## (spring pop); Collect empties it.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## Collect emptied the basket: canvas px of the basket opening and how many gifts left it (the UI
## can fly them from here to the dew counter, GDD §3.2).
signal emptied(canvas_pos: Vector2, gifts: int)

const PROPS_ATLAS := "res://art/props/props_atlas.json"
const BASKET_PROP := &"basket"
const BASKET_PART := "basket"
## Sort just after the basket sprite (same y-sort origin + a hair).
const SORT_AFTER := 0.5
const MAX_DEW := 12
const MAX_GIFTS := 3
const GIFT_SCALE := 1.45
const DEW_SCALE := 1.05
## Glint halo (Art Bible §6.5): r0 10 px, gold, alpha 0.3, breathing k 76.
const GLINT_R0 := 10.0
const GLINT_QUAD := 64.0
const GLINT_ALPHA := 0.3
const GLINT_MATERIAL := "pinwheel_b"

var _content: GameContent
var _kit: DecorKit
## Design px of the basket frame's top-left corner (props_svg.py basket(): 140 x 116).
var _origin := Vector2.ZERO
var _items: Node2D
var _glint: HaloSprite
var _shown_gifts: int = 0


func setup(content: GameContent, kit: DecorKit) -> void:
	_content = content
	_kit = kit
	y_sort_enabled = false
	var centre := GardenRules.frame_to_px(content, Vector2(0.5, 0.48))
	var prop: Dictionary = content.props_by_id.get(BASKET_PROP, {})
	if not prop.is_empty():
		centre = GardenRules.frame_to_px(content, Vector2(float(prop["x"]), float(prop["y"])))
	var frame: Array = kit.layout.get("basket_frame", [140, 116])
	var part_centre := Vector2(0.0, -4.0)
	var sort_y := 48.0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROPS_ATLAS))
	if parsed is Dictionary:
		for p: Dictionary in (parsed as Dictionary).get("parts", []):
			if String(p.get("id", "")) == BASKET_PART:
				var c: Array = p["centre"]
				part_centre = Vector2(float(c[0]), float(c[1]))
				sort_y = float(p["sort_y"])
				var r: Array = p["region"]
				frame = [float(r[2]), float(r[3])]
	var size := Vector2(float(frame[0]), float(frame[1]))
	_origin = centre + part_centre - size * 0.5
	position = Vector2(centre.x, centre.y + sort_y + SORT_AFTER)
	_items = Node2D.new()
	_items.name = "Items"
	add_child(_items)
	var mats: Dictionary = content.palettes["materials"]
	var gm: Dictionary = mats.get(GLINT_MATERIAL, {})
	var gc := Color.html(String(gm.get("lit", "#F6D58C")))
	gc.a = GLINT_ALPHA
	var k := float((content.motion["loops_k"]["glow_mushroom"] as Array)[0])
	_glint = HaloSprite.new().setup(GLINT_R0, GLINT_QUAD, gc, k, 0.0)
	_glint.position = _local(Vector2(size.x * 0.5, 40.0))
	_glint.visible = false
	add_child(_glint)
	Game.basket_changed.connect(func(_n: int, _dew: int) -> void: refresh())
	Game.sim_event.connect(_on_sim_event)


func _on_sim_event(ev: Dictionary) -> void:
	if StringName(ev["type"]) == WorldSim.EV_COLLECTED:
		var gifts := int(ev.get("gifts", 0))
		refresh()
		if gifts > 0 and not bool(ev.get("catch_up", false)):
			emptied.emit(get_global_transform_with_canvas() * _glint.position, gifts)


func _local(frame_px: Vector2) -> Vector2:
	return _origin + frame_px - position


## Rebuilds the fill from Game.sim.state.basket.
func refresh() -> void:
	if Game.sim == null or _items == null:
		return
	for c: Node in _items.get_children():
		c.queue_free()
	var basket := Game.sim.state.basket
	var n := basket.size()
	# All dew drops are one stamp (one draw, no per-drop uniform-buffer entry).
	var dew_slots: Array = _kit.layout.get("dew_slots", [])
	var quads := DecorKit.Quads.new()
	for i in mini(mini(n, MAX_DEW), dew_slots.size()):
		var q: Array = dew_slots[i]
		_kit.add_quad(quads, "dew_drop", _local(Vector2(float(q[0]), float(q[1]))), DEW_SCALE,
				deg_to_rad(float((i * 37) % 21 - 10)))
	if not quads.is_empty():
		_items.add_child(_kit.stamp(quads))
	var gift_slots: Array = _kit.layout.get("gift_slots", [])
	var gift_parts: Dictionary = _kit.layout.get("gift_parts", {})
	var shown := mini(mini(n, MAX_GIFTS), gift_slots.size())
	for j in shown:
		var entry: Dictionary = basket[n - shown + j]
		var part := String(gift_parts.get(String(entry.get("gift_item", "")), ""))
		if part == "":
			continue
		var q2: Array = gift_slots[j]
		var sp2 := _kit.sprite(part, GIFT_SCALE)
		sp2.position = _local(Vector2(float(q2[0]), float(q2[1])))
		sp2.rotation = deg_to_rad(float((j * 53) % 17 - 8))
		_items.add_child(sp2)
		if j == shown - 1 and n > _shown_gifts and _shown_gifts > 0:
			var target := sp2.scale
			sp2.scale = target * 0.6
			Motion.spring_to(sp2, "scale", target, &"pop")
	var rim := _kit.sprite("basket_rim", 1.0)
	rim.position = _local(Vector2(_kit.size_of("basket_rim").x * 0.5, 0.0))
	_items.add_child(rim)
	_glint.visible = n > 0
	_shown_gifts = n


## Number of dew drops and gifts on show (tests).
func shown_counts() -> Vector2i:
	if Game.sim == null:
		return Vector2i.ZERO
	var n := Game.sim.state.basket.size()
	return Vector2i(mini(n, MAX_DEW), mini(n, MAX_GIFTS))
