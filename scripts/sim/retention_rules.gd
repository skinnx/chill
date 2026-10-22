class_name RetentionRules
extends RefCounted
## Retention v1 rules (GDD §13): friendship depth, mystery signs and clues, cousins, away scenes.
##
## A port of the retention half of tools/sim/economy_sim.py `Player` (check_mysteries,
## schedule_signs, tap_signs, maybe_cousin, away_profile, scene_ok, on_return, cast) plus the
## game-only bookkeeping the reference does not need (sign anchors and visibility, nest stage
## events, pending scenes, cousin repeat visits, signature gifts, keepsakes, the schema-1
## migration). [WorldSim] owns one instance and calls these hooks from the same world step for
## live play and offline catch-up; the world it acts on is passed in as [param sim] on every call,
## so this object holds no reference back to it (no RefCounted cycle).
##
## Pure and deterministic: every random choice is a [RetentionHash] draw keyed by the install
## seed (GDD §13.1, G6); the world RNG stream is never touched. Nothing here removes or lowers
## anything the player has (G1): signs move into clues when tapped, a pending scene moves into
## memories, a waiting postcard moves into postcards.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const KIND_SPECIES := "species"
const KIND_VARIANT := "variant"
## Sign key separator: "<mystery id>/<index>" (Game.tap_sign).
const KEY_SEP := "/"
const SIGN_NOTE := "note"
const REF_ENTRY := "entry"
const REF_FAVOURITE := "favourite_spot"
## Heart levels with a sim-side unlock (friendship.json heart_unlocks; the rest is view-side).
const HEART_STORY_I := 2
const HEART_STORY_II := 4
const HEART_STORY_III := 5
const PROFILE_SEP := "|"
const STORY_SUFFIX := "_story"

var content: GameContent
var _rest_s: float
var _max_visible: int
var _debut_after_s: float
var _var_hearts: int
var _var_all_met: bool
var _cousin_every: int
var _nest_min_hearts: int
var _keepsake_hearts: int
var _sig_from_heart: int
var _pair_min_hearts: int
var _min_absence_s: float
var _scene_chance: float
var _sample_s: float
var _linger_s: float


func _init(p_content: GameContent) -> void:
	content = p_content
	var eco := content.economy
	var my := content.mysteries
	var fr := content.friendship
	var sc := content.scenes_doc
	_rest_s = float(eco.get("visit_affection_rest_s", 0.0))
	_max_visible = int(my["max_visible"])
	_debut_after_s = float(my["debut_after_last_sign_s"])
	_var_hearts = int(my["variant_hearts_required"])
	_var_all_met = bool(my["variant_requires_all_met"])
	_cousin_every = maxi(1, int(my["cousin_every_n_visits"]))
	_nest_min_hearts = int(fr["nest"]["min_hearts"])
	_keepsake_hearts = int(fr["keepsake"]["min_hearts"])
	_sig_from_heart = int(fr["signature_gift"]["from_heart"])
	_pair_min_hearts = int(fr["pair"]["min_hearts_either"])
	_min_absence_s = float(sc["min_absence_s"])
	_scene_chance = float(sc["scene_chance"])
	_sample_s = maxf(1.0, float(sc["away_sample_s"]))
	_linger_s = float(sc["linger_s"])


# ================================================================= friendship (GDD §13.2)

## The 20 h visit rest (GDD §13.2.1): true (and the rest restarts) if this visit warms the
## friendship. The rest is never shown and nothing is lost.
func visit_affection_due(sim: WorldSim, species: StringName, t: float) -> bool:
	var last := float(sim.state.visit_aff_t.get(String(species), -INF))
	if t - last < _rest_s:
		return false
	sim.state.visit_aff_t[String(species)] = t
	return true


## One heart level reached (live or offline): story postcards, nest, keepsake (GDD §13.2.2).
func on_heart_level(sim: WorldSim, species: StringName, level: int, t: float) -> void:
	var sdef: Dictionary = content.species_by_id[species]
	if level == HEART_STORY_I:
		sim.send_postcard("%s_h2" % species, String(sdef["postcard_heart2"]), species, t)
	elif level == HEART_STORY_II:
		_story_postcard(sim, species, HEART_STORY_II, t)
	elif level == HEART_STORY_III:
		_story_postcard(sim, species, HEART_STORY_III, t)
	if level == _nest_min_hearts:
		_build_nest(sim, species, t)
	if level == _keepsake_hearts:
		_add_keepsake(sim, species, t)


## After a heart-up: a ♥5 friend may open its cousin's mystery (GDD §13.3.5).
func after_hearts(sim: WorldSim, hearts: int, t: float) -> void:
	if hearts >= _var_hearts:
		check_mysteries(sim, t)


## A first visit: the mystery is solved, waiting ♥4 postcards naming this buddy are sent, and
## once every friend is met the cousin mysteries may open.
func on_debut(sim: WorldSim, species: StringName, t: float) -> void:
	var m: Dictionary = sim.state.mysteries.get(String(species), {})
	if not m.is_empty() and float(m["solved_unix"]) < 0.0:
		m["solved_unix"] = sim.unix_at(t)
	for id: String in sim.state.postcards_waiting.duplicate():
		var owner := StringName(id.get_slice("_h", 0))
		if content.species_by_id.has(owner) and best_friend(owner) == species:
			sim.state.postcards_waiting.erase(id)
			_send_story(sim, owner, HEART_STORY_II, id, t)
	if sim.met_count() == content.species.size():
		check_mysteries(sim, t)


## The gift item this friend leaves now: its signature gift from ♥2 on (same dew, GDD §13.2.2).
func gift_item_for(sim: WorldSim, species: StringName) -> String:
	var sdef: Dictionary = content.species_by_id[species]
	if sim.hearts_of(species) >= _sig_from_heart:
		return String(sdef["signature_gift"])
	return String(sdef["gift_item"])


## Records a signature gift (Keepsakes lists it). Returns true for this friend's first one,
## which carries BASKET_SIGNATURE_NOTE.
func note_signature_gift(sim: WorldSim, species: StringName, t: float) -> bool:
	if sim.state.signature_gifts.has(String(species)):
		return false
	sim.state.signature_gifts[String(species)] = sim.unix_at(t)
	return true


func is_signature_item(species: StringName, item: String) -> bool:
	return String(content.species_by_id[species]["signature_gift"]) == item


func best_friend(species: StringName) -> StringName:
	var sdef: Dictionary = content.species_by_id.get(species, {})
	return StringName(sdef.get("best_friend", ""))


## Best buddies are a pair once both are met and either is at >= pair.min_hearts_either (GDD §13.2.4).
func pair_active(sim: WorldSim, species: StringName) -> bool:
	var b := best_friend(species)
	if not sim.is_met(species) or not sim.is_met(b):
		return false
	return maxi(sim.hearts_of(species), sim.hearts_of(b)) >= _pair_min_hearts


## Nest stage from built_t, never below the stored one (GDD §13.2.3).
func nest_stage_at(nest: Dictionary, t: float) -> int:
	var stage := 0
	for i in content.nest_stages.size():
		if float(nest["built_t"]) + float(content.nest_stages[i]["at_s"]) <= t:
			stage = i
	return maxi(stage, int(nest["stage"]))


## Up to max_wavers present friends at >= ♥1 wave on open (GDD §13.2.2): hearts desc, then album
## order, each with its delay u("wave", open_index, species) staggered stagger_s apart.
func wave_plan(sim: WorldSim, open_index: int) -> Array[Dictionary]:
	var w: Dictionary = content.friendship["wave_on_open"]
	var who: Array[StringName] = []
	for p: Dictionary in sim.state.present:
		var sp := StringName(p["species"])
		if sim.hearts_of(sp) >= int(w["min_hearts"]) and not who.has(sp):
			who.append(sp)
	who.sort_custom(func(a: StringName, b: StringName) -> bool:
		var ha := sim.hearts_of(a)
		var hb := sim.hearts_of(b)
		return ha > hb if ha != hb else content.album_index(a) < content.album_index(b))
	var out: Array[Dictionary] = []
	for i in mini(who.size(), int(w["max_wavers"])):
		var uu := RetentionHash.u(sim.state.install_seed, ["wave", open_index, String(who[i])])
		var delay := lerpf(float(w["delay_min_s"]), float(w["delay_max_s"]), uu) + i * float(w["stagger_s"])
		out.append({"species": who[i], "delay_s": delay, "pose": StringName(w["pose"])})
	return out


func _story_postcard(sim: WorldSim, species: StringName, level: int, t: float) -> void:
	var id := "%s_h%d" % [species, level]
	if level == HEART_STORY_II and not sim.is_met(best_friend(species)):
		# Chapter II introduces the best buddy: it waits for their first visit (G2).
		if not sim.state.postcards_waiting.has(id) and not sim.has_postcard(id):
			sim.state.postcards_waiting.append(id)
		return
	_send_story(sim, species, level, id, t)


func _send_story(sim: WorldSim, species: StringName, level: int, id: String, t: float) -> void:
	var template := String(content.species_by_id[species]["postcard_heart%d" % level])
	sim.send_postcard(id, template, species, t)


func _build_nest(sim: WorldSim, species: StringName, t: float) -> void:
	if sim.state.nests.has(String(species)):
		return
	var style := String(content.species_by_id[species]["nest_style"])
	sim.state.nests[String(species)] = {"style": style, "built_t": t, "stage": 0}
	sim.mark_dirty()  # a new timed event (its next stage)
	sim.emit_event(WorldSim.EV_NEST_STAGE, {"species": species, "style": StringName(style), "stage": 0,
		"stage_id": _stage_id(0), "built": true}, t)


func _add_keepsake(sim: WorldSim, species: StringName, t: float) -> void:
	if sim.state.keepsakes.has(String(species)):
		return
	sim.state.keepsakes[String(species)] = sim.unix_at(t)
	sim.emit_event(WorldSim.EV_KEEPSAKE, {"species": species}, t)


func _stage_id(stage: int) -> StringName:
	return StringName(content.nest_stages[stage]["id"]) if stage < content.nest_stages.size() else &""


# ================================================================= mysteries (GDD §13.3)

## Opens every mystery whose conditions hold now (after blooms, décor purchases, the last friend
## met, a ♥5 heart-up and the migration). An open mystery never closes.
func check_mysteries(sim: WorldSim, t: float) -> void:
	var st := sim.state
	for s: Dictionary in content.species:
		var id := StringName(s["id"])
		if sim.is_met(id) or st.mysteries.has(String(id)) or content.is_onboarding_species(id):
			continue
		if _items_hold(sim, s["requires"]):
			var rec: Dictionary = content.mystery_species_by_id[id]
			_open(sim, String(id), KIND_SPECIES, String(id), rec["signs"], t, false)
	if _var_all_met and sim.met_count() < content.species.size():
		return
	for v: Dictionary in content.variants:
		var vid := String(v["id"])
		var base := StringName(v["species"])
		if st.mysteries.has(vid) or sim.hearts_of(base) < _var_hearts:
			continue
		if _items_hold(sim, (v["condition"] as Dictionary)["items"]):
			_open(sim, vid, KIND_VARIANT, String(base), v["signs"], t, true)


## Earliest world time an unmet species may debut (GDD §13.3.1): onboarding friends at once,
## others once their mystery's last sign has appeared plus debut_after_last_sign_s.
func debut_ok_t(sim: WorldSim, species: StringName) -> float:
	if content.is_onboarding_species(species):
		return -INF
	var m: Dictionary = sim.state.mysteries.get(String(species), {})
	return float(m["ok_t"]) if not m.is_empty() else INF


func _open(sim: WorldSim, id: String, kind: String, target: String, types: Array, t: float, variant: bool) -> void:
	var windows := content.sign_windows(types.size(), variant)
	var last := t
	for i in windows.size():
		var win: Array = windows[i]
		var lo := float(win[0])
		var hi := float(win[1])
		var at := t + lo + (hi - lo) * RetentionHash.u(sim.state.install_seed, ["sign", id, i])
		sim.state.signs.append({"mystery": id, "index": i, "type": String(types[i]), "appear_t": at, "anchor": ""})
		last = maxf(last, at)
	var ok := last if variant else last + _debut_after_s
	sim.state.mysteries[id] = {"kind": kind, "target": target, "open_t": t, "ok_t": ok, "solved_unix": -1.0}
	sim.emit_event(WorldSim.EV_MYSTERY_OPENED, {"mystery": StringName(id), "kind": StringName(kind),
		"target": StringName(target), "signs": windows.size()}, t)
	sim.mark_dirty()


func _items_hold(sim: WorldSim, reqs: Variant) -> bool:
	if reqs is Array:
		for r: Variant in reqs:
			var rec: Dictionary = r
			if sim.item_count(StringName(rec["item"])) < int(rec["min"]):
				return false
	return true


# ================================================================= signs and clues

## Next retention event after [param after_t]: a sign coming due or a nest stage (INF if none).
func next_event_t(sim: WorldSim, after_t: float) -> float:
	var best := INF
	for s: Dictionary in sim.state.signs:
		var at := float(s["appear_t"])
		if at > after_t and at < best:
			best = at
	for sp: String in sim.state.nests:
		var n: Dictionary = sim.state.nests[sp]
		var nxt := int(n["stage"]) + 1
		if nxt < content.nest_stages.size():
			best = minf(best, maxf(float(n["built_t"]) + float(content.nest_stages[nxt]["at_s"]), after_t))
	return best


## Processes the retention events in (prev_t, t]: signs come due (and fill free visible slots),
## nests reach their next stages.
func process(sim: WorldSim, prev_t: float, t: float) -> void:
	for s: Dictionary in sim.state.signs:
		var at := float(s["appear_t"])
		if at > prev_t and at <= t:
			sim.emit_event(WorldSim.EV_SIGN_DUE, _sign_view(s), at)
	fill_visible(sim, t)
	for sp: String in sim.state.nests:
		var n: Dictionary = sim.state.nests[sp]
		var stage := nest_stage_at(n, t)
		while int(n["stage"]) < stage:
			n["stage"] = int(n["stage"]) + 1
			sim.emit_event(WorldSim.EV_NEST_STAGE, {"species": StringName(sp), "style": StringName(n["style"]),
				"stage": int(n["stage"]), "stage_id": _stage_id(int(n["stage"])), "built": false}, t)


## Gives due signs a visible slot while fewer than max_visible are shown (GDD §13.3.2): queue
## order appear_t, then album order; anchor = the free anchor of that type nearest the type's
## reference point, ties by anchor order.
func fill_visible(sim: WorldSim, t: float) -> void:
	while visible_signs(sim).size() < _max_visible:
		var best := -1
		for i in sim.state.signs.size():
			var s: Dictionary = sim.state.signs[i]
			if String(s["anchor"]) != "" or float(s["appear_t"]) > t:
				continue
			if best < 0 or _queue_before(s, sim.state.signs[best]):
				best = i
		if best < 0:
			return
		var sign: Dictionary = sim.state.signs[best]
		var anchor := _pick_anchor(sim, sign)
		if anchor == "":
			return  # no free anchor of this type: it waits (cannot happen with valid data)
		sign["anchor"] = anchor
		sim.emit_event(WorldSim.EV_SIGN_VISIBLE, _sign_view(sign), t)


func visible_signs(sim: WorldSim) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Dictionary in sim.state.signs:
		if String(s["anchor"]) != "":
			out.append(_sign_view(s))
	return out


## Tapping a visible sign adds its clue (GDD §13.3.2). Returns false for an unknown or not yet
## visible sign (nothing changes).
func tap_sign(sim: WorldSim, key: String) -> bool:
	for i in sim.state.signs.size():
		var s: Dictionary = sim.state.signs[i]
		if sign_key(s) != key or String(s["anchor"]) == "":
			continue
		var mid := String(s["mystery"])
		sim.state.clues[mid] = int(sim.state.clues.get(mid, 0)) | (1 << int(s["index"]))
		sim.state.signs.remove_at(i)
		var ev := _sign_view(s)
		var m: Dictionary = sim.state.mysteries.get(mid, {})
		ev["riddle_key"] = riddle_key(mid)
		ev["found"] = clue_count(sim, mid)
		ev["total"] = sign_total(mid)
		ev["solved"] = not m.is_empty() and float(m["solved_unix"]) >= 0.0
		sim.emit_event(WorldSim.EV_CLUE, ev)
		fill_visible(sim, sim.state.t)
		sim.mark_dirty()
		return true
	return false


static func sign_key(s: Dictionary) -> String:
	return "%s%s%d" % [s["mystery"], KEY_SEP, int(s["index"])]


func clue_count(sim: WorldSim, mystery: String) -> int:
	var bits := int(sim.state.clues.get(mystery, 0))
	var n := 0
	for i in sign_total(mystery):
		if bits & (1 << i):
			n += 1
	return n


func sign_total(mystery: String) -> int:
	var m := _mystery_def(mystery)
	return (m.get("signs", []) as Array).size()


func riddle_key(mystery: String) -> StringName:
	return StringName(_mystery_def(mystery).get("riddle_key", ""))


## Base species whose look and places a mystery's signs use.
func mystery_species(mystery: String) -> StringName:
	if content.variants_by_id.has(StringName(mystery)):
		return StringName(content.variants_by_id[StringName(mystery)]["species"])
	return StringName(mystery)


func _mystery_def(mystery: String) -> Dictionary:
	var id := StringName(mystery)
	if content.variants_by_id.has(id):
		return content.variants_by_id[id]
	return content.mystery_species_by_id.get(id, {})


func _sign_view(s: Dictionary) -> Dictionary:
	var mid := String(s["mystery"])
	var sp := mystery_species(mid)
	var rec: Dictionary = content.mystery_species_by_id.get(sp, {})
	var variant := content.variants_by_id.has(StringName(mid))
	return {"key": sign_key(s), "mystery": StringName(mid), "index": int(s["index"]), "sign": StringName(s["type"]),
		"species": sp, "variant": StringName(mid) if variant else &"", "anchor": StringName(s["anchor"]),
		"appear_t": float(s["appear_t"]), "footprint": StringName(rec.get("footprint", "")),
		"dropped": StringName(rec.get("dropped", "")), "tint": StringName(rec.get("tint", ""))}


func _queue_before(a: Dictionary, b: Dictionary) -> bool:
	var ta := float(a["appear_t"])
	var tb := float(b["appear_t"])
	if ta != tb:
		return ta < tb
	var oa := content.album_index(mystery_species(String(a["mystery"])))
	var ob := content.album_index(mystery_species(String(b["mystery"])))
	if oa != ob:
		return oa < ob
	if String(a["mystery"]) != String(b["mystery"]):
		return String(a["mystery"]) < String(b["mystery"])
	return int(a["index"]) < int(b["index"])


func _pick_anchor(sim: WorldSim, sign: Dictionary) -> String:
	var used := {}
	for s: Dictionary in sim.state.signs:
		if String(s["anchor"]) != "":
			used[String(s["anchor"])] = true
	var ref := _reference_point(String(sign["type"]), mystery_species(String(sign["mystery"])))
	var best := ""
	var best_d := INF
	for a: Dictionary in content.sign_anchors:
		var id := String(a["id"])
		if used.has(id) or not (a["types"] as Array).has(String(sign["type"])):
			continue
		var d := GardenRules.frame_to_px(content, Vector2(float(a["x"]), float(a["y"]))).distance_squared_to(ref)
		if d < best_d:
			best_d = d
			best = id
	return best


func _reference_point(type: String, species: StringName) -> Vector2:
	var sdef: Dictionary = content.species_by_id[species]
	var ref := String((content.sign_types_by_id.get(StringName(type), {}) as Dictionary).get("ref", ""))
	var rec: Dictionary = {}
	if ref == REF_ENTRY:
		rec = content.entries_by_id.get(StringName(sdef["entry"]), {})
	elif ref == REF_FAVOURITE:
		rec = content.spots_by_id.get(StringName(sdef["favourite_spot"]), {})
	else:
		rec = content.spots_by_id.get(StringName(ref), {})
	return GardenRules.frame_to_px(content, Vector2(float(rec.get("x", 0.5)), float(rec.get("y", 0.5))))


# ================================================================= cousins (GDD §13.3.5)

## The base friend arrived for a real (not peek) visit [param visit]: the cousin's debut, or its
## every-n-th repeat visit. The cousin is a guest of the base's visit record ("cousin" key).
func on_base_arrival(sim: WorldSim, species: StringName, visit: Dictionary, t: float) -> void:
	var v: Dictionary = content.variants_by_species.get(species, {})
	if v.is_empty():
		return
	var vid := String(v["id"])
	var st := sim.state
	if st.variants_met.has(vid):
		var n := int(st.cousin_visits.get(String(species), 0)) + 1
		st.cousin_visits[String(species)] = n
		if n % _cousin_every == 0:
			visit["cousin"] = vid
			sim.emit_event(WorldSim.EV_COUSIN_ARRIVED, {"variant": StringName(vid), "species": species, "first": false}, t)
		return
	var m: Dictionary = st.mysteries.get(vid, {})
	if m.is_empty() or t < float(m["ok_t"]):
		return
	var cond: Dictionary = v["condition"]
	var phases: Array = cond["arrival_phases"]
	if not phases.is_empty() and not phases.has(String(sim.phase_at(t))):
		return
	var wx: Array = cond["arrival_weather"]
	if not wx.is_empty() and not wx.has(String(sim.weather_at(t))):
		return
	if sim.real_visitor_count() >= int(content.economy["max_present"]):
		return  # the cousin needs a free place; it simply comes along another time
	var unix := sim.unix_at(t)
	st.variants_met[vid] = unix
	m["solved_unix"] = unix
	st.cousin_visits[String(species)] = 0
	visit["cousin"] = vid
	sim.emit_event(WorldSim.EV_COUSIN_MET, {"variant": StringName(vid), "species": species}, t)
	sim.emit_event(WorldSim.EV_COUSIN_ARRIVED, {"variant": StringName(vid), "species": species, "first": true}, t)


# ================================================================= away scenes (GDD §13.4)

## A foreground after a background (call after the offline catch-up). Returns true if a scene
## is pending now (a new one or the re-shown pending one). [param fixed_profile] (tests and the
## parity trace only) replaces the sampled absence profile ({"phase|weather": seconds}).
func on_return(sim: WorldSim, t_bg: float, t_now: float, fixed_profile: Variant = null) -> bool:
	if t_bg < 0.0 or t_now - t_bg < _min_absence_s:
		return false
	var st := sim.state
	if not st.pending_scene.is_empty():
		var ev := st.pending_scene.duplicate(true)
		ev["resumed"] = true
		sim.emit_event(WorldSim.EV_SCENE_STAGED, ev, t_now)
		return true
	st.scene_returns += 1
	var prof: Dictionary = fixed_profile if fixed_profile is Dictionary else away_profile(sim, t_bg, t_now)
	var pick := select_scene(sim, st.scene_returns, prof)
	if pick.is_empty():
		return false
	stage_scene(sim, StringName(pick["scene"]), pick["cast"], t_now)
	return true


## Steps 2-5 of GDD §13.4 for return index [param r] and an absence [param profile]:
## {scene, cast} or {} (no scene this return).
func select_scene(sim: WorldSim, r: int, profile: Dictionary) -> Dictionary:
	var seed := sim.state.install_seed
	if RetentionHash.u(seed, ["scene_roll", r]) >= _scene_chance:
		return {}
	var elig: Array[Dictionary] = []
	for sc: Dictionary in content.scenes:
		if scene_ok(sim, sc, profile):
			elig.append(sc)
	if elig.is_empty():
		return {}
	var pool: Array[Dictionary] = []
	for sc: Dictionary in elig:
		if int(sim.state.scenes_seen.get(String(sc["id"]), 0)) == 0:
			pool.append(sc)
	if pool.is_empty():
		pool = elig
	var tot := 0.0
	for sc: Dictionary in pool:
		tot += float(sc["weight"])
	var x := RetentionHash.u(seed, ["scene_pick", r]) * tot
	var acc := 0.0
	var pick: Dictionary = pool[pool.size() - 1]
	for sc: Dictionary in pool:
		acc += float(sc["weight"])
		if x < acc:
			pick = sc
			break
	return {"scene": StringName(pick["id"]), "cast": cast_for(sim, pick)}


## Seconds of the absence per "phase|weather", sampled every away_sample_s from [param t0]
## (the reference's away_profile).
func away_profile(sim: WorldSim, t0: float, t1: float) -> Dictionary:
	var prof := {}
	var t := t0
	while t < t1:
		var key := "%s%s%s" % [sim.phase_at(t), PROFILE_SEP, sim.weather_at(t)]
		prof[key] = float(prof.get(key, 0.0)) + minf(_sample_s, t1 - t)
		t += _sample_s
	return prof


func scene_ok(sim: WorldSim, sc: Dictionary, profile: Dictionary) -> bool:
	var c: Dictionary = sc["conditions"]
	if sim.met_count() < int(c.get("met_min", 0)):
		return false
	if not _items_hold(sim, c.get("items", [])):
		return false
	if sim.state.boats < int(c.get("boats_min", 0)):
		return false
	var stems := 0
	var kinds := 0
	for f: Dictionary in content.flowers:
		var n := sim.bloomed_count(StringName(f["id"]))
		stems += n
		kinds += 1 if n > 0 else 0
	if stems < int(c.get("bloomed_stems_min", 0)) or kinds < int(c.get("bloomed_types_min", 0)):
		return false
	var pair_min := int(c.get("pair_hearts_min", 0))
	if bool(sc.get("pair", false)) or pair_min > 0:
		if _best_pair_hearts(sim) < maxi(pair_min, 0):
			return false
	var away: Array = c.get("away", [])
	if away.is_empty():
		return true
	for a: Variant in away:
		var rule: Dictionary = a
		var phases: Array = rule["phases"]
		var wx: Array = rule["weather"]
		var tot := 0.0
		for key: String in profile:
			var ph := key.get_slice(PROFILE_SEP, 0)
			var w := key.get_slice(PROFILE_SEP, 1)
			if (phases.is_empty() or phases.has(ph)) and (wx.is_empty() or wx.has(w)):
				tot += float(profile[key])
		if tot >= float(rule["min_s"]):
			return true
	return false


## The deterministic cast (GDD §13.4 step 5): each role's prefer list wins if one of them is met;
## otherwise friends new to this scene first, present visitors before absent ones, hearts desc,
## album order. Pair scenes take the best-ranked best-buddy pair (both met, the pair's higher
## hearts >= pair_hearts_min), the higher-hearted buddy first.
func cast_for(sim: WorldSim, sc: Dictionary) -> Array[String]:
	var seen: Array = sim.state.scene_cast.get(String(sc["id"]), [])
	var met: Array[StringName] = []
	for s: Dictionary in content.species:
		if sim.is_met(StringName(s["id"])):
			met.append(StringName(s["id"]))
	var out: Array[String] = []
	if bool(sc.get("pair", false)):
		var pair_min := int((sc["conditions"] as Dictionary).get("pair_hearts_min", 0))
		var best_key: Array = []
		for a: StringName in met:
			var b := best_friend(a)
			if content.album_index(a) >= content.album_index(b) or not sim.is_met(b):
				continue
			if maxi(sim.hearts_of(a), sim.hearts_of(b)) < pair_min:
				continue
			var ra := _rank(sim, a, seen)
			var rb := _rank(sim, b, seen)
			var key := ra if _rank_less(ra, rb) or ra == rb else rb
			if best_key.is_empty() or _rank_less(key, best_key):
				best_key = key
				var lead := a if sim.hearts_of(a) >= sim.hearts_of(b) else b
				out = [String(lead), String(b if lead == a else a)]
		return out
	for role: Variant in sc["roles"]:
		var r: Dictionary = role
		var pick := &""
		for p: Variant in r.get("prefer", []):
			var sp := StringName(p)
			if sim.is_met(sp) and not out.has(String(sp)):
				pick = sp
				break
		if pick == &"":
			var best_r: Array = []
			for sp: StringName in met:
				if out.has(String(sp)):
					continue
				var rk := _rank(sim, sp, seen)
				if best_r.is_empty() or _rank_less(rk, best_r):
					best_r = rk
					pick = sp
		if pick == &"":
			break
		out.append(String(pick))
	return out


## Stages [param scene] with [param cast] at [param t] (pending until tapped or linger_s of
## foreground time; GDD §13.4 step 6).
func stage_scene(sim: WorldSim, scene: StringName, cast: Array, t: float) -> void:
	var st := sim.state
	if not st.pending_scene.is_empty():
		_archive(sim)  # never replace a staged scene unseen (G2); on_return re-shows it instead
	var id := String(scene)
	var cast_s: Array[String] = []
	for k: Variant in cast:
		cast_s.append(String(k))
	var seen: Array = st.scene_cast.get(id, [])
	var new_faces := false
	for k: String in cast_s:
		if not seen.has(k):
			seen.append(k)
			new_faces = true
	st.scene_cast[id] = seen
	st.scenes_seen[id] = int(st.scenes_seen.get(id, 0)) + 1
	st.pending_scene = {"scene": id, "cast": Array(cast_s), "phase": String(sim.phase_at(t)),
		"weather": String(sim.weather_at(t)), "world_t": t, "shown_s": 0.0}
	var ev := st.pending_scene.duplicate(true)
	ev["resumed"] = false
	ev["new_memory"] = new_faces
	ev["first_time"] = int(st.scenes_seen[id]) == 1
	sim.emit_event(WorldSim.EV_SCENE_STAGED, ev, t)


## The player tapped the scene: it is archived to Memories. False if none is pending.
func tap_scene(sim: WorldSim) -> bool:
	if sim.state.pending_scene.is_empty():
		return false
	_archive(sim)
	return true


## Foreground seconds while a scene is pending; archived after linger_s (GDD §13.4).
func foreground_tick(sim: WorldSim, dt: float) -> void:
	var p := sim.state.pending_scene
	if p.is_empty() or dt <= 0.0:
		return
	p["shown_s"] = float(p["shown_s"]) + dt
	if float(p["shown_s"]) >= _linger_s:
		_archive(sim)


func _archive(sim: WorldSim) -> void:
	var p := sim.state.pending_scene
	var mem := {"scene": String(p["scene"]), "cast": (p["cast"] as Array).duplicate(), "phase": String(p["phase"]),
		"weather": String(p["weather"]), "world_t": float(p["world_t"]), "unix": sim.unix_at(float(p["world_t"]))}
	sim.state.memories.append(mem)
	sim.state.pending_scene = {}
	var ev := mem.duplicate(true)
	ev["index"] = sim.state.memories.size() - 1
	sim.emit_event(WorldSim.EV_SCENE_ARCHIVED, ev)


func _best_pair_hearts(sim: WorldSim) -> int:
	var best := -1
	for s: Dictionary in content.species:
		var a := StringName(s["id"])
		var b := best_friend(a)
		if sim.is_met(a) and sim.is_met(b):
			best = maxi(best, maxi(sim.hearts_of(a), sim.hearts_of(b)))
	return best


func _rank(sim: WorldSim, sp: StringName, seen: Array) -> Array:
	return [1 if seen.has(String(sp)) else 0, 0 if sim.is_present(sp) else 1, -sim.hearts_of(sp),
		content.album_index(sp)]


static func _rank_less(a: Array, b: Array) -> bool:
	for i in a.size():
		if int(a[i]) != int(b[i]):
			return int(a[i]) < int(b[i])
	return false


# ================================================================= schema-1 migration (GDD §13.6)

## The content-aware half of the schema 1 -> 2 migration, run once at load ([SaveStore.migrate]
## added the empty fields): nobody re-toasts, ♥3+ friends build nests now, ♥4/♥5 stories already
## earned are sent (♥4 waits for an unmet buddy), ♥5 friends get keepsakes, and mysteries whose
## conditions hold open now. Affection is untouched; the 20 h rest starts empty.
func migrate_v1(sim: WorldSim) -> void:
	var st := sim.state
	var t := st.t
	for s: Dictionary in content.species:
		var sp := StringName(s["id"])
		var h := sim.hearts_of(sp)
		if h <= 0:
			continue
		st.hearts_seen[String(sp)] = maxi(h, int(st.hearts_seen.get(String(sp), 0)))
		if h >= _nest_min_hearts:
			_build_nest(sim, sp, t)
		for level: int in [HEART_STORY_II, HEART_STORY_III]:
			if h >= level and not _has_template(sim, String(s["postcard_heart%d" % level])):
				var id := "%s_h%d" % [sp, level]
				if sim.has_postcard(id):
					id += STORY_SUFFIX  # an MVP ♥4 card used this id with the old shared template
				if level == HEART_STORY_II and not sim.is_met(best_friend(sp)):
					if not st.postcards_waiting.has(id):
						st.postcards_waiting.append(id)
				else:
					_send_story(sim, sp, level, id, t)
		if h >= _keepsake_hearts:
			_add_keepsake(sim, sp, t)
	check_mysteries(sim, t)
	st.retention_v = WorldState.RETENTION_VERSION


func _has_template(sim: WorldSim, template: String) -> bool:
	for p: Dictionary in sim.state.postcards:
		if String(p["template"]) == template:
			return true
	return false


# ================================================================= read models for views (P2)

## Hearts not yet celebrated: [{species, hearts, seen}] in album order (offline toasts, §13.2.2).
func unseen_hearts(sim: WorldSim) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Dictionary in content.species:
		var sp := StringName(s["id"])
		var h := sim.hearts_of(sp)
		var seen := int(sim.state.hearts_seen.get(String(sp), 0))
		if h > seen:
			out.append({"species": sp, "hearts": h, "seen": seen})
	return out


## The 5-line unlock list of a friend card: [{heart, reached, album_key, toast_key, unlocks}].
func unlock_list(sim: WorldSim, species: StringName) -> Array[Dictionary]:
	var h := sim.hearts_of(species)
	var out: Array[Dictionary] = []
	for u: Variant in content.friendship["heart_unlocks"]:
		var rec: Dictionary = u
		out.append({"heart": int(rec["heart"]), "reached": h >= int(rec["heart"]),
			"album_key": StringName(rec["album_key"]), "toast_key": StringName(rec["toast_key"]),
			"unlocks": (rec["unlocks"] as Array).duplicate()})
	return out


## {species, style, stage, stage_id, built_t, style_key, stage_key, x, y} or {} (no nest yet).
func nest_view(sim: WorldSim, species: StringName) -> Dictionary:
	var n: Dictionary = sim.state.nests.get(String(species), {})
	if n.is_empty():
		return {}
	var stage := nest_stage_at(n, sim.state.t)
	var style: Dictionary = content.nest_styles_by_id.get(StringName(n["style"]), {})
	var anchor: Dictionary = content.nest_anchor_by_species.get(species, {})
	return {"species": species, "style": StringName(n["style"]), "stage": stage, "stage_id": _stage_id(stage),
		"built_t": float(n["built_t"]), "style_key": StringName(style.get("name_key", "")),
		"stage_key": StringName(content.nest_stages[stage].get("name_key", "")),
		"x": float(anchor.get("x", 0.0)), "y": float(anchor.get("y", 0.0))}


## Album › Clues: one card per opened mystery, species in album order then cousins in opening
## order (GDD §13.3.3): {mystery, kind, species, variant, found_mask, found, total, signs,
## riddle_key, riddle_found, solved, open_t}.
func clue_cards(sim: WorldSim) -> Array[Dictionary]:
	var species_cards: Array[Dictionary] = []
	var cousin_cards: Array[Dictionary] = []
	for s: Dictionary in content.species:
		if sim.state.mysteries.has(String(s["id"])):
			species_cards.append(clue_card(sim, String(s["id"])))
	for id: String in sim.state.mysteries:
		if String((sim.state.mysteries[id] as Dictionary)["kind"]) == KIND_VARIANT:
			cousin_cards.append(clue_card(sim, id))
	cousin_cards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["open_t"]) < float(b["open_t"]))
	species_cards.append_array(cousin_cards)
	return species_cards


func clue_card(sim: WorldSim, mystery: String) -> Dictionary:
	var m: Dictionary = sim.state.mysteries.get(mystery, {})
	var def := _mystery_def(mystery)
	var types: Array = def.get("signs", [])
	var mask := int(sim.state.clues.get(mystery, 0))
	var note_found := false
	for i in types.size():
		if String(types[i]) == SIGN_NOTE and mask & (1 << i):
			note_found = true
	var variant := content.variants_by_id.has(StringName(mystery))
	return {"mystery": StringName(mystery), "kind": StringName(m.get("kind", KIND_VARIANT if variant else KIND_SPECIES)),
		"species": mystery_species(mystery), "variant": StringName(mystery) if variant else &"",
		"found_mask": mask, "found": clue_count(sim, mystery), "total": types.size(), "signs": types.duplicate(),
		"riddle_key": riddle_key(mystery), "riddle_found": note_found,
		"solved": not m.is_empty() and float(m["solved_unix"]) >= 0.0, "open": not m.is_empty(),
		"open_t": float(m.get("open_t", INF))}


## The cousin row of a friend card: {variant, name_key, desc_key, riddle_key, rig, met, met_unix,
## open} or {} (no cousin defined).
func cousin_view(sim: WorldSim, species: StringName) -> Dictionary:
	var v: Dictionary = content.variants_by_species.get(species, {})
	if v.is_empty():
		return {}
	var vid := String(v["id"])
	return {"variant": StringName(vid), "species": species, "name_key": StringName(v["name_key"]),
		"desc_key": StringName(v["desc_key"]), "riddle_key": StringName(v["riddle_key"]),
		"rig": (v["rig"] as Dictionary).duplicate(), "met": sim.state.variants_met.has(vid),
		"met_unix": float(sim.state.variants_met.get(vid, -1.0)), "open": sim.state.mysteries.has(vid)}


## Album › Keepsakes: ♥5 portraits, signature gifts and cousins met, each newest last.
func keepsake_view(sim: WorldSim) -> Dictionary:
	var portraits: Array[Dictionary] = []
	for sp: String in sim.state.keepsakes:
		portraits.append({"species": StringName(sp), "unix": float(sim.state.keepsakes[sp]),
			"pose": StringName(content.friendship["keepsake"]["pose"]),
			"frame": StringName(content.friendship["keepsake"]["frame"])})
	var gifts: Array[Dictionary] = []
	for sp: String in sim.state.signature_gifts:
		var item := String(content.species_by_id[StringName(sp)]["signature_gift"])
		gifts.append({"species": StringName(sp), "item": StringName(item), "unix": float(sim.state.signature_gifts[sp]),
			"name_key": StringName(content.gift_item_def(StringName(item)).get("name_key", ""))})
	var cousins: Array[Dictionary] = []
	for vid: String in sim.state.variants_met:
		cousins.append(cousin_view(sim, mystery_species(vid)))
	var by_unix := func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("unix", a.get("met_unix", 0.0))) < float(b.get("unix", b.get("met_unix", 0.0)))
	portraits.sort_custom(by_unix)
	gifts.sort_custom(by_unix)
	cousins.sort_custom(by_unix)
	return {"portraits": portraits, "signature_gifts": gifts, "cousins": cousins}


## Best-buddy line: {friend, met, active} (GDD §13.2.4; ALBUM_PAIR shows when active).
func buddy_view(sim: WorldSim, species: StringName) -> Dictionary:
	var b := best_friend(species)
	return {"friend": b, "met": sim.is_met(b), "active": pair_active(sim, species)}


## The UI showed this friend's heart-up (toast or Album dot): it never toasts again.
func mark_hearts_seen(sim: WorldSim, species: StringName) -> void:
	var key := String(species)
	sim.state.hearts_seen[key] = maxi(int(sim.state.hearts_seen.get(key, 0)), sim.hearts_of(species))
