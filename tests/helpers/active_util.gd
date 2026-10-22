class_name ActiveTestUtil
extends RefCounted
## Shared drivers for the Active Play v1 suites (GDD §14): a quiet world (no scripted onboarding,
## no Poisson visitors), a garden of bloomed stems in one bed, décor laid out at the legacy anchors,
## long visits, and the world actions the reference parity schedule uses.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const HOUR := 3600.0
const DAY := 86400.0
const STEM_BED := "bed_1"
const LONG_STAY_S := 1.0e9


static func quiet_sim(content: GameContent, seed: int = 24680, install_local_s: float = 20.0 * HOUR) -> WorldSim:
	return RetentionTestUtil.quiet_sim(content, seed, install_local_s)


## Bloomed stems in bed_1 (in garden order, slots 0..), each blooming at [param bloom_t]; décor
## copies at their legacy anchors (verbatim, every cairn pebble in one stack at anchors[0]).
static func set_garden(sim: WorldSim, content: GameContent, bloomed: Dictionary, owned: Dictionary,
		bloom_t: float = 0.0) -> void:
	var st := sim.state
	st.stems.clear()
	st.owned.clear()
	st.petal_from_t.clear()
	var slot := 0
	for f: Dictionary in content.flowers:
		var n := int(bloomed.get(String(f["id"]), bloomed.get(StringName(f["id"]), 0)))
		for i in n:
			st.stems.append({"flower": String(f["id"]), "bed": STEM_BED, "slot": slot,
				"planted_t": bloom_t - float(f["bloom_at_s"]), "tutorial": false, "stage": WorldSim.STAGE_BLOOM})
			slot += 1
		if n > 0:
			st.owned[String(f["id"])] = n
	for id: Variant in owned:
		st.owned[String(id)] = int(owned[id])
	st.decor_layout = anchor_layout(content, st.owned)
	sim._rebuild_caches()
	sim.active.refresh_spots(sim)
	sim.mark_dirty()


## Every owned movable copy at anchors[n] verbatim (no lantern jitter, no nudge).
static func anchor_layout(content: GameContent, owned: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Dictionary in content.decor:
		var id := StringName(d["id"])
		if not content.is_movable_decor(id):
			continue
		var pos: Array = (content.anchors_by_decor[id] as Dictionary)["positions"]
		for i in int(owned.get(String(id), 0)):
			var q: Array = pos[0 if id == DecorPlacementRules.CAIRN else i]
			var rec := DecorPlacementRules.make_piece(id, i, Vector2(float(q[0]), float(q[1])), true)
			if id == DecorPlacementRules.CAIRN and i > 0:
				rec["stack"] = DecorPlacementRules.piece_id(id, 0)
				rec["level"] = i
			out.append(rec)
	return out


## A long real visit at [param t].
static func arrive(sim: WorldSim, species: StringName, t: float) -> void:
	sim.advance(maxf(t, sim.state.t))
	sim._arrive(t, species, LONG_STAY_S, 0, false)


static func depart(sim: WorldSim, species: StringName, t: float) -> void:
	sim.advance(maxf(t, sim.state.t))
	var i := sim.present_index(species)
	if i >= 0:
		sim._depart(i, t)


## One spawn check at [param t] with the sky pinned.
static func check(sim: WorldSim, t: float, ph: StringName = &"day", wx: StringName = &"clear") -> void:
	sim.advance(maxf(t, sim.state.t))
	sim.active.wishes.check(sim, t, ph, wx)


## Opens [param wish] for a present friend directly (bypasses the draw).
static func give_wish(sim: WorldSim, species: StringName, wish: StringName) -> void:
	sim.active.wishes._open(sim, species, wish, sim.state.t)


## A world action as the views report it (tests and the parity driver).
static func act(sim: WorldSim, kind: StringName, args: Dictionary, t: float) -> void:
	sim.advance(maxf(t, sim.state.t))
	match kind:
		WishRules.ACT_PET:
			sim.pet(StringName(args["species"]), sim.unix_at(t))
		WishRules.ACT_BOAT:
			sim.float_boat()
		WishRules.ACT_BED_TAP:
			sim.active.wishes.on_action(sim, kind, {"bed": StringName(args.get("bed", STEM_BED))}, t)
		_:
			var a := {}
			for k: Variant in args:
				a[String(k)] = StringName(args[k])
			sim.active.wishes.on_action(sim, kind, a, t)


## Brews [param petals] + [param drops] (simple brewing). Returns the recipe or &"".
static func brew(sim: WorldSim, petals: Array, drops: int, t: float) -> StringName:
	sim.advance(maxf(t, sim.state.t))
	for f: Variant in petals:
		if not sim.active.tea.pot_add_petal(sim, StringName(f)):
			return &""
	for i in drops:
		if not sim.active.tea.pot_add_drop(sim):
			return &""
	return sim.active.tea.pour(sim, true, t)
