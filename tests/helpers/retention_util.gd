class_name RetentionTestUtil
extends RefCounted
## Shared drivers for the Retention v1 suites: a "quiet" world without scripted onboarding or
## Poisson visitors (only what a test does happens), and direct visits, pets and garden counts.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const HOUR := 3600.0
const DAY := 86400.0
const VISIT_STAY_S := 3600.0
const STEM_BED := "bed_1"
## "No Poisson visitor" that still survives a JSON round trip (INF does not).
const NEVER_T := 1.0e15


## Local time = t + [param install_local_s] (unix 0 + tz), like the reference sim's clock.
static func quiet_sim(content: GameContent, seed: int = 12345, install_local_s: float = 20.0 * HOUR) -> WorldSim:
	var sim := WorldSim.new_game(content, seed, 0.0, install_local_s)
	sim.state.scripted.clear()
	sim.state.next_candidate_t = NEVER_T
	sim.mark_dirty()
	return sim


## A real (not peek) visit at [param t] that leaves at once (no gift is left).
static func visit(sim: WorldSim, species: StringName, t: float) -> void:
	sim.advance(maxf(t, sim.state.t))
	sim._arrive(t, species, VISIT_STAY_S, 0, false)
	sim.state.present.clear()
	sim.mark_dirty()


static func pet(sim: WorldSim, species: StringName, n: int, t: float) -> void:
	sim.advance(maxf(t, sim.state.t))
	for i in n:
		sim._add_affection(species, 1, t)


static func meet(sim: WorldSim, species: Array, t: float) -> void:
	for i in species.size():
		visit(sim, StringName(species[i]), t + i)


## Garden counts: [param bloomed] flower -> blooming stems, [param owned] décor -> copies.
static func set_items(sim: WorldSim, content: GameContent, bloomed: Dictionary, owned: Dictionary) -> void:
	var st := sim.state
	st.stems.clear()
	st.owned.clear()
	for f: Dictionary in content.flowers:
		var n := int(bloomed.get(StringName(f["id"]), 0))
		for i in n:
			st.stems.append({"flower": String(f["id"]), "bed": STEM_BED, "slot": i, "planted_t": -1.0e7,
				"tutorial": false, "stage": WorldSim.STAGE_BLOOM})
		if n > 0:
			st.owned[String(f["id"])] = n
	for id: Variant in owned:
		st.owned[String(id)] = int(owned[id])
	sim._rebuild_caches()
	sim.retention.check_mysteries(sim, st.t)


static func tap_all_signs(sim: WorldSim) -> int:
	var n := 0
	var vis := sim.retention.visible_signs(sim)
	while not vis.is_empty():
		for s: Dictionary in vis:
			if sim.retention.tap_sign(sim, String(s["key"])):
				n += 1
		vis = sim.retention.visible_signs(sim)
	return n


static func all_species(content: GameContent) -> Array[StringName]:
	var out: Array[StringName] = []
	for s: Dictionary in content.species:
		out.append(StringName(s["id"]))
	return out


static func count_events(events: Array[Dictionary], type: StringName) -> int:
	var n := 0
	for e: Dictionary in events:
		if StringName(e["type"]) == type:
			n += 1
	return n
