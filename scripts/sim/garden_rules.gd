class_name GardenRules
extends RefCounted
## Flower-bed placement rules, implementable as written in GDD §2.4. Pure static functions over
## the content layout and the current stems; nothing is ever uprooted or moved.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## Free stem slots of [param bed_id] given the current stems.
static func free_slots(content: GameContent, stems: Array[Dictionary], bed_id: StringName) -> PackedInt32Array:
	var bed: Dictionary = content.beds_by_id.get(bed_id, {})
	var out := PackedInt32Array()
	if bed.is_empty():
		return out
	var taken := {}
	for s: Dictionary in stems:
		if StringName(s["bed"]) == bed_id:
			taken[int(s["slot"])] = true
	var n := mini(int(bed["capacity"]), (bed["stems"] as Array).size())
	for i in n:
		if not taken.has(i):
			out.append(i)
	return out


static func has_room(content: GameContent, stems: Array[Dictionary], bed_id: StringName) -> bool:
	return not free_slots(content, stems, bed_id).is_empty()


## Beds that can take another stem (they glow in choose-a-bed mode), in fill order.
static func beds_with_room(content: GameContent, stems: Array[Dictionary]) -> Array[StringName]:
	var out: Array[StringName] = []
	for b: Dictionary in content.beds:
		var id := StringName(b["id"])
		if has_room(content, stems, id):
			out.append(id)
	return out


## The bed a copy of [param flower_id] goes to when the player does not choose (rules 1-2):
## a first copy takes the lowest fill_order bed with room; later copies go to the bed holding the
## most stems of that type if it has room, else to the bed with room nearest to it.
static func auto_bed(content: GameContent, stems: Array[Dictionary], flower_id: StringName) -> StringName:
	var counts := {}
	for s: Dictionary in stems:
		if StringName(s["flower"]) == flower_id:
			var b := StringName(s["bed"])
			counts[b] = int(counts.get(b, 0)) + 1
	var rooms := beds_with_room(content, stems)
	if rooms.is_empty():
		return &""
	if counts.is_empty():
		return rooms[0]
	var home: StringName = &""
	var best := -1
	for b: Dictionary in content.beds:  # fill order breaks ties
		var id := StringName(b["id"])
		var c := int(counts.get(id, 0))
		if c > best:
			best = c
			home = id
	if rooms.has(home):
		return home
	var home_pos := bed_position_px(content, home)
	var nearest: StringName = rooms[0]
	var nearest_d := INF
	for id: StringName in rooms:
		var d := bed_position_px(content, id).distance_to(home_pos)
		if d < nearest_d:
			nearest_d = d
			nearest = id
	return nearest


## Rule 3: the free slot nearest to the centroid of same-type stems in the bed (types cluster);
## the first stem of a type takes the free slot with the lowest index. -1 when the bed is full.
static func choose_slot(content: GameContent, stems: Array[Dictionary], bed_id: StringName,
		flower_id: StringName) -> int:
	var free := free_slots(content, stems, bed_id)
	if free.is_empty():
		return -1
	var bed: Dictionary = content.beds_by_id[bed_id]
	var offsets: Array = bed["stems"]
	var sum := Vector2.ZERO
	var n := 0
	for s: Dictionary in stems:
		if StringName(s["bed"]) == bed_id and StringName(s["flower"]) == flower_id:
			sum += _offset_px(content, offsets[int(s["slot"])])
			n += 1
	if n == 0:
		return free[0]
	var centroid := sum / float(n)
	var best := free[0]
	var best_d := INF
	for slot: int in free:
		var d := _offset_px(content, offsets[slot]).distance_squared_to(centroid)
		if d < best_d:
			best_d = d
			best = slot
	return best


static func bed_position_px(content: GameContent, bed_id: StringName) -> Vector2:
	var bed: Dictionary = content.beds_by_id.get(bed_id, {})
	if bed.is_empty():
		return Vector2.ZERO
	return frame_to_px(content, Vector2(float(bed["x"]), float(bed["y"])))


## Normalised frame coordinates (GDD §2.1) -> design px in the bottom-anchored frame.
static func frame_to_px(content: GameContent, p: Vector2) -> Vector2:
	var frame: Dictionary = content.spots_doc["frame"]
	return Vector2(p.x * float(frame["width_px"]), p.y * float(frame["height_px"]))


static func _offset_px(content: GameContent, off: Variant) -> Vector2:
	var a: Array = off
	return frame_to_px(content, Vector2(float(a[0]), float(a[1])))
