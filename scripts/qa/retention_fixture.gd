class_name RetentionFixture
extends RefCounted
## QA save fixtures for Retention v1 (GDD §13.9 P3, docs/plans/RETENTION_V1.md):
##
##   tools/qa/capture.sh still --tod=0.6 --fixture=retention_mid --out=qa/out/retention_mid.png
##   tools/qa/capture.sh still --tod=0.6 --fixture=retention_mid --qa-scene=leaf_fort --out=...
##   tools/qa/capture.sh still --qa-scene=nap_pile --out=...    (implies the retention_mid world)
##
## retention_mid = the garden_mid garden (GardenFixture) plus: hearts spread 1-5 over ten met
## friends; nests at all three stages (twigs, moss bed, flower canopy: every friend at >= ♥3 has
## one, so a 1-5 spread means three nests); two open mysteries (capling, puddlewump: still unmet,
## their requires raised to hold) with one visible sign each and one more waiting; one cousin met
## (twilight_puffmoss; a QA shortcut, in play a cousin needs all 12 met); a few clues, memories,
## a keepsake and signature gifts; and a pending away scene (pair_nap, or --qa-scene=<id>, cast by
## the real casting rule). Written straight into the state at its world time; no events fire.
## Captures run with --no-save, so a fixture never reaches a real save.
##
## Wiring: GardenFixture.apply_from_args (PlotsLayer._ready, before the creature layer and HUD
## bind) hands over to [method apply_from_args] when [method wanted] is true.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const NAME := "retention_mid"
const ARG_FIXTURE := "--fixture="
const ARG_SCENE := "--qa-scene="
const DEFAULT_SCENE := &"pair_nap"
const HOUR := 3600.0
const DAY := 86400.0
## species -> affection (hearts 5/4/3/2/1 at the 3/8/15/25/40 thresholds; economy.json).
const AFFECTION := {
	&"puffmoss": 44, &"buttonbud": 30, &"pebblepaw": 17, &"honeyhum": 10, &"fernwhisk": 4,
	&"dandelfluff": 9, &"bellkin": 3, &"primpip": 5, &"glowmote": 3, &"moonpuff": 4,
}
## Nest ages: canopy (>= 3 days), moss bed (1-3 days), twigs (fresh).
const NEST_AGE_S := {&"puffmoss": 3.5 * DAY, &"buttonbud": 1.5 * DAY, &"pebblepaw": 2.0 * HOUR}
const OPEN_MYSTERIES: Array[StringName] = [&"capling", &"puddlewump"]
## Items raised so the two open mysteries' requires hold (species.json requires).
const ITEMS := {&"toadstool_seat": 5, &"stream_stones": 5}
## The first sign of each open mystery appeared this long ago (visible); later ones still wait.
const SIGN_AGO_S := 1800.0
const COUSIN := &"twilight_puffmoss"
const FOUND_CLUES := {&"honeyhum": 3, &"fernwhisk": 3}
const MEMORY_SCENES: Array[StringName] = [&"nap_pile", &"boat_regatta"]

static var applied: bool = false


## True when --fixture=retention_mid or --qa-scene=<id> is on the command line.
static func wanted() -> bool:
	return requested_fixture() == NAME or requested_scene() != &""


static func requested_fixture() -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(ARG_FIXTURE):
			return a.trim_prefix(ARG_FIXTURE)
	return ""


static func requested_scene() -> StringName:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(ARG_SCENE):
			return StringName(a.trim_prefix(ARG_SCENE))
	return &""


## QA hook (idempotent): applies the fixture to Game.sim and rebuilds it on the edited state.
static func apply_from_args(content: GameContent) -> void:
	if applied or Game.sim == null:
		return
	var scene := requested_scene()
	if scene == &"":
		scene = DEFAULT_SCENE
	if not content.scenes_by_id.has(scene):
		push_warning("RetentionFixture: unknown scene '%s' (known: %s)" % [scene, ", ".join(content.scenes_by_id.keys())])
		scene = DEFAULT_SCENE
	var state := Game.sim.state
	GardenFixture.apply(content, state, GardenFixture.MID)
	GardenFixture.applied = GardenFixture.MID
	Game.sim = WorldSim.new(content, state)
	apply(Game.sim, scene)
	Game.sim = WorldSim.new(content, state)  # derived caches (bloomed counts) from the final state
	Game.sim.drain_events()
	applied = true


## Writes the retention_mid friendships, nests, mysteries, signs, cousin, memories and a pending
## [param scene] into [param sim]'s state at its current world time.
static func apply(sim: WorldSim, scene: StringName) -> void:
	var content := sim.content
	var st := sim.state
	var t := st.t
	for item: StringName in ITEMS:
		st.owned[String(item)] = maxi(int(st.owned.get(String(item), 0)), int(ITEMS[item]))
	for s: Dictionary in content.species:
		var sp := StringName(s["id"])
		if OPEN_MYSTERIES.has(sp):
			st.met.erase(String(sp))
			continue
		st.met[String(sp)] = sim.unix_at(t - 4.0 * DAY)
		st.affection[String(sp)] = int(AFFECTION.get(sp, 3))
		st.hearts_seen[String(sp)] = sim.hearts_of(sp)
		st.visit_aff_t[String(sp)] = t - HOUR
		var h := sim.hearts_of(sp)
		if h >= 2:
			_postcard(sim, sp, 2, String(s["postcard_heart2"]))
			st.signature_gifts[String(sp)] = sim.unix_at(t - DAY)
		if h >= 4:
			_postcard(sim, sp, 4, String(s["postcard_heart4"]))
		if h >= 5:
			_postcard(sim, sp, 5, String(s["postcard_heart5"]))
			st.keepsakes[String(sp)] = sim.unix_at(t - DAY)
	for sp: StringName in NEST_AGE_S:
		var built := t - float(NEST_AGE_S[sp])
		var nest := {"style": String(content.species_by_id[sp]["nest_style"]), "built_t": built, "stage": 0}
		nest["stage"] = sim.retention.nest_stage_at(nest, t)
		st.nests[String(sp)] = nest
	# Two open mysteries (opened ~2.5 h ago): the first sign is visible, the rest wait.
	st.signs.clear()
	for sp: StringName in OPEN_MYSTERIES:
		var rec: Dictionary = content.mystery_species_by_id[sp]
		var types: Array = rec["signs"]
		st.mysteries[String(sp)] = {"kind": RetentionRules.KIND_SPECIES, "target": String(sp), "open_t": t - 2.5 * HOUR,
			"ok_t": t + 6.0 * HOUR, "solved_unix": -1.0}
		for i in types.size():
			var at := t - SIGN_AGO_S if i == 0 else t + (i + 1) * HOUR
			st.signs.append({"mystery": String(sp), "index": i, "type": String(types[i]), "appear_t": at, "anchor": ""})
	# Solved mysteries with all clues found (Album › Clues "So it was {name}!").
	for sp: StringName in FOUND_CLUES:
		st.mysteries[String(sp)] = {"kind": RetentionRules.KIND_SPECIES, "target": String(sp), "open_t": t - 3.8 * DAY,
			"ok_t": t - 3.6 * DAY, "solved_unix": sim.unix_at(t - 3.5 * DAY)}
		st.clues[String(sp)] = int(FOUND_CLUES[sp])
	var base := StringName(content.variants_by_id[COUSIN]["species"])
	st.mysteries[String(COUSIN)] = {"kind": RetentionRules.KIND_VARIANT, "target": String(base), "open_t": t - 2.0 * DAY,
		"ok_t": t - 1.0 * DAY, "solved_unix": sim.unix_at(t - 0.5 * DAY)}
	st.clues[String(COUSIN)] = 3
	st.variants_met[String(COUSIN)] = sim.unix_at(t - 0.5 * DAY)
	st.cousin_visits[String(base)] = 0
	sim.retention.fill_visible(sim, t)
	# Earlier memories, then the pending scene staged by the real selection rules' cast.
	for id: StringName in MEMORY_SCENES:
		var cast := sim.retention.cast_for(sim, content.scenes_by_id[id])
		sim.retention.stage_scene(sim, id, cast, t - DAY)
		sim.retention.tap_scene(sim)
	st.scene_returns = MEMORY_SCENES.size()
	sim.retention.stage_scene(sim, scene, sim.retention.cast_for(sim, content.scenes_by_id[scene]), t)
	st.retention_v = WorldState.RETENTION_VERSION


static func _postcard(sim: WorldSim, species: StringName, level: int, template: String) -> void:
	sim.send_postcard("%s_h%d" % [species, level], template, species, sim.state.t)
