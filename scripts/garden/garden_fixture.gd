class_name GardenFixture
extends RefCounted
## QA save fixtures for the garden (docs/QA.md §5.1 "mid-game garden", "night with 5 lanterns";
## requested from Gameplay in docs/QA.md §7): a deterministic garden written into the world state
## so captures show beds at mixed stages, every décor set and a basket with gifts.
##
##   tools/qa/capture.sh still --tod=0.6 --fixture=garden_mid --out=...
##   tools/qa/capture.sh still --tod=1.0 --fixture=night_lanterns --out=...   (5 lanterns lit)
##   --fixture=garden_full  every stem and every décor copy (draw-call / fill stress)
##
## Pure: [method apply] edits a WorldState through the same placement rules play uses
## (GardenRules.auto_bed / choose_slot), with planted_t set so each stem is at the listed stage
## right now (no events fire). [method apply_from_args] is the QA hook: PlotsLayer calls it in
## _ready (before the creature layer and the HUD bind), and it swaps Game.sim for a sim built on
## the edited state so every derived cache (bloomed counts, snugness, cup rate) is right.
## Captures run with --no-save, so a fixture never reaches a real save.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const ARG := "--fixture="
const MID := "garden_mid"
const NIGHT_LANTERNS := "night_lanterns"
const FULL := "garden_full"
## Growth progress inside the stage for SPROUT / BUD rows, and how long ago blooms opened.
const IN_STAGE := 0.6
const BLOOMED_AGO_S := 900.0
const SEED_AGO_S := 30.0
const FIXTURE_DEW := 340

## [flower, bed, count, stage]: the mid-game garden (38 stems, every flower, all five beds).
const MID_STEMS: Array[Array] = [
	[&"sweet_clover", &"bed_1", 4, WorldSim.STAGE_BLOOM],
	[&"button_daisy", &"bed_1", 3, WorldSim.STAGE_BLOOM],
	[&"button_daisy", &"bed_1", 1, WorldSim.STAGE_BUD],
	[&"forget_me_not", &"bed_1", 3, WorldSim.STAGE_BLOOM],
	[&"bluebell", &"bed_2", 3, WorldSim.STAGE_BLOOM],
	[&"primrose", &"bed_2", 2, WorldSim.STAGE_BLOOM],
	[&"primrose", &"bed_2", 1, WorldSim.STAGE_BUD],
	[&"button_daisy", &"bed_2", 2, WorldSim.STAGE_BLOOM],
	[&"buttercup", &"bed_3", 3, WorldSim.STAGE_BLOOM],
	[&"buttercup", &"bed_3", 1, WorldSim.STAGE_BUD],
	[&"dandelion", &"bed_3", 2, WorldSim.STAGE_BLOOM],
	[&"sweet_clover", &"bed_3", 2, WorldSim.STAGE_SPROUT],
	[&"moonbloom", &"bed_4", 2, WorldSim.STAGE_BLOOM],
	[&"forget_me_not", &"bed_4", 3, WorldSim.STAGE_BUD],
	[&"button_daisy", &"bed_4", 1, WorldSim.STAGE_SEED],
	[&"primrose", &"bed_5", 2, WorldSim.STAGE_SPROUT],
	[&"bluebell", &"bed_5", 2, WorldSim.STAGE_BUD],
	[&"button_daisy", &"bed_5", 1, WorldSim.STAGE_SEED],
	[&"sweet_clover", &"bed_5", 2, WorldSim.STAGE_BLOOM],
]
## Décor copies per set (garden_mid; night_lanterns raises the lanterns to 5).
const MID_DECOR := {
	&"leaf_pinwheel": 3, &"pebble_cairn": 5, &"toadstool_seat": 4, &"stream_stones": 4,
	&"firefly_lantern": 3, &"wind_chime": 4,
}
const NIGHT_LANTERN_COUNT := 5
## Gifts waiting in the basket (species whose gift item they are).
const MID_GIFTS: Array[StringName] = [
	&"puffmoss", &"buttonbud", &"pebblepaw", &"fernwhisk", &"glowmote", &"bellkin", &"honeyhum",
]

static var applied: String = ""


static func names() -> PackedStringArray:
	return PackedStringArray([MID, NIGHT_LANTERNS, FULL])


## The fixture named on the command line ("" if none).
static func requested() -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(ARG):
			return a.trim_prefix(ARG)
	return ""


## QA hook (idempotent): applies --fixture=<name> to Game.sim once per run.
static func apply_from_args(content: GameContent) -> void:
	var name := requested()
	if name == "" or applied == name or Game.sim == null:
		return
	if not names().has(name):
		push_warning("GardenFixture: unknown fixture '%s' (known: %s)" % [name, ", ".join(names())])
		return
	var state := Game.sim.state
	apply(content, state, name)
	Game.sim = WorldSim.new(content, state)
	applied = name


## Writes fixture [param name] into [param state] at world time state.t. Returns false if unknown.
static func apply(content: GameContent, state: WorldState, name: String) -> bool:
	if not names().has(name):
		return false
	state.seed_planted = true
	state.stems.clear()
	state.owned.clear()
	if name == FULL:
		_plant_full(content, state)
	else:
		for row: Array in MID_STEMS:
			_plant(content, state, StringName(row[0]), StringName(row[1]), int(row[2]), int(row[3]))
	for d: Dictionary in content.decor:
		var id := StringName(d["id"])
		var n := int(MID_DECOR.get(id, 0))
		if name == NIGHT_LANTERNS and id == &"firefly_lantern":
			n = NIGHT_LANTERN_COUNT
		if name == FULL:
			n = content.max_copies(id)
		if n > 0:
			state.owned[String(id)] = n
	state.basket.clear()
	for sp: StringName in MID_GIFTS:
		var s: Dictionary = content.species_by_id.get(sp, {})
		if s.is_empty():
			continue
		state.basket.append({"species": String(sp), "gift_item": String(s["gift_item"]), "dew": int(s["gift_dew"])})
	state.dew = maxi(state.dew, FIXTURE_DEW)
	return true


static func _plant_full(content: GameContent, state: WorldState) -> void:
	var stages := [WorldSim.STAGE_BLOOM, WorldSim.STAGE_BLOOM, WorldSim.STAGE_BUD, WorldSim.STAGE_BLOOM,
		WorldSim.STAGE_SPROUT]
	var k := 0
	for f: Dictionary in content.flowers:
		var id := StringName(f["id"])
		for i in content.max_copies(id):
			_plant(content, state, id, &"", 1, int(stages[k % stages.size()]))
			k += 1


## Plants [param count] stems of [param flower] in [param bed] (rules 2-3 pick the slot) at [param stage].
static func _plant(content: GameContent, state: WorldState, flower: StringName, bed: StringName, count: int,
		stage: int) -> void:
	var f: Dictionary = content.flowers_by_id.get(flower, {})
	if f.is_empty():
		return
	var times := PackedFloat64Array([float(f["sprout_at_s"]), float(f["bud_at_s"]), float(f["bloom_at_s"])])
	for _i in count:
		var b := bed
		if b == &"" or not GardenRules.has_room(content, state.stems, b):
			b = GardenRules.auto_bed(content, state.stems, flower)
		if b == &"":
			return
		var slot := GardenRules.choose_slot(content, state.stems, b, flower)
		state.stems.append({"flower": String(flower), "bed": String(b), "slot": slot,
			"planted_t": state.t - age_for(times, stage), "tutorial": false, "stage": stage})
		state.owned[String(flower)] = int(state.owned.get(String(flower), 0)) + 1


## Seconds since planting that put a stem [param stage] (IN_STAGE through its sprout/bud stage).
static func age_for(times: PackedFloat64Array, stage: int) -> float:
	match stage:
		WorldSim.STAGE_SEED:
			return minf(SEED_AGO_S, times[0] * 0.5)
		WorldSim.STAGE_SPROUT:
			return lerpf(times[0], times[1], IN_STAGE)
		WorldSim.STAGE_BUD:
			return lerpf(times[1], times[2], IN_STAGE)
	return times[2] + BLOOMED_AGO_S
