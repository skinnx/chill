class_name WorldState
extends RefCounted
## Everything the world remembers, as plain typed data (docs/ARCHITECTURE.md §6, GDD §5.8).
##
## Pure data: no behaviour beyond (de)serialisation and normalisation. [WorldSim] mutates it,
## [SaveService] persists [method to_dict]. All times are world seconds unless the name says
## _unix (UTC wall clock) or _local (wall clock + time-zone offset).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const POSE_COUNT := 5
## Bumped when WorldSim's content-aware retention migration changes (see [member retention_v]).
const RETENTION_VERSION := 1
const BASKET_TEMPLATE := {"species": "", "gift_item": "", "dew": 0, "signature": false}
const PRESENT_TEMPLATE := {"species": "", "arrive_t": 0.0, "depart_t": 0.0, "gift_dew": 0, "gift_item": "",
	"boat_credit": false, "pet_credit": false, "scripted": false, "greeter": false, "cousin": ""}
const MYSTERY_TEMPLATE := {"kind": "", "target": "", "open_t": 0.0, "ok_t": 0.0, "solved_unix": -1.0}
const SIGN_TEMPLATE := {"mystery": "", "index": 0, "type": "", "appear_t": 0.0, "anchor": ""}
const NEST_TEMPLATE := {"style": "", "built_t": 0.0, "stage": 0}
const SCENE_TEMPLATE := {"scene": "", "phase": "", "weather": "", "world_t": 0.0, "shown_s": 0.0}
const MEMORY_TEMPLATE := {"scene": "", "phase": "", "weather": "", "world_t": 0.0, "unix": 0.0}
## Bumped when the content-aware Active Play migration changes (see [member active_v], GDD §14.9).
const ACTIVE_VERSION := 1
const WISH_OPEN := "open"
const WISH_HELD := "held"
const WISH_TEMPLATE := {"species": "", "wish": "", "opened_t": 0.0, "state": "open", "taps": 0, "placed": false}
const VISIT_COUNT_TEMPLATE := {"arrive_t": 0.0, "n": 0}
const TRAY_TEMPLATE := {"recipe": "", "made_unix": 0.0, "drops": 0}
const DECOR_PIECE_TEMPLATE := {"id": "", "set": "", "x": 0.0, "y": 0.0, "rot": 0, "stored": false, "stack": "",
	"level": 0}
## "No wish yet" for the global wish gap that survives a JSON round trip (-INF does not).
const NEVER_T := -1.0e18

## Seed fixed at install; drives the weather plan and seeds [member rng_state].
var install_seed: int = 0
var installed_unix: float = 0.0
## RandomNumberGenerator.state of the world stream, persisted so replays are exact.
var rng_state: int = 0
## Monotonic world clock (GDD §5.8). Never decreases.
var t: float = 0.0
## Wall-clock anchor: world second [member anchor_world_t] happened at [member anchor_unix];
## [member tz_offset_s] converts UTC to device-local seconds.
var anchor_world_t: float = 0.0
var anchor_unix: float = 0.0
var tz_offset_s: float = 0.0

# --- wallet, basket, dew cup (GDD §5.3, §5.7)
var dew: int = 0
## {species, gift_item, dew} in arrival order; never more than economy.basket_slots.
var basket: Array[Dictionary] = []
var cup: float = 0.0
var cup_last_t: float = 0.0
var last_collect_t: float = 0.0

# --- garden (GDD §2.4, §2.5, §4.2, §4.3)
## item id (String) -> copies owned, flowers and décor (the tutorial clover counts).
var owned: Dictionary = {}
## {flower, bed, slot, planted_t, tutorial, stage}; stage 0 seed, 1 sprout, 2 bud, 3 bloom.
var stems: Array[Dictionary] = []
var items_bought: int = 0

# --- visitors (GDD §5.4 - §5.6)
## {species, arrive_t, depart_t, gift_dew, gift_item, boat_credit, pet_credit, scripted, greeter}
var present: Array[Dictionary] = []
var next_candidate_t: float = 0.0
## Pending scripted events {t, kind ("arrive"/"postcard"), species, stay_s, gift_dew, id, role}.
var scripted: Array[Dictionary] = []

# --- relationships and collection (GDD §7)
## species -> unix time of the first visit.
var met: Dictionary = {}
## species -> custom name (NFC, <= 12 chars); absent = default name in the current language.
var names: Dictionary = {}
var affection: Dictionary = {}
## species -> bitmask of the 5 photo poses (GameContent.BEHAVIOURS order).
var photos: Dictionary = {}
## "species/pose" -> {phase, weather, world_t}: photos are metadata rendered live (GDD §7.1).
var photo_meta: Dictionary = {}
## {id, template, species, received_unix, read}
var postcards: Array[Dictionary] = []
var boats: int = 0
## species -> unix time of the last pet that granted affection (greeter rule, GDD §5.6).
var last_pet_unix: Dictionary = {}

# --- onboarding and one-shot flags (GDD §3.4)
var seed_planted: bool = false
var seed_tap_t: float = -1.0
var basket_full_seen: bool = false
var first_bloom_postcard_sent: bool = false

# --- Retention v1 (GDD §13.6; schema 2). Every collection below only ever grows (G1).
## 0 = loaded from a schema-1 save: WorldSim runs the content-aware part of the §13.6 migration
## once (nests, keepsakes, earned postcards, mysteries) and sets it to [constant RETENTION_VERSION].
var retention_v: int = 0
## species -> world t of the last visit that granted affection (the 20 h rest, GDD §13.2.1).
var visit_aff_t: Dictionary = {}
## species -> hearts already celebrated to the player (offline toasts never repeat).
var hearts_seen: Dictionary = {}
## species -> {style, built_t, stage}; stage is derived from built_t and never decreases.
var nests: Dictionary = {}
## ♥4 postcard ids waiting for the best buddy's first visit.
var postcards_waiting: Array[String] = []
## mystery id (species or variant id) -> {kind, target, open_t, ok_t, solved_unix (-1 = open)}.
var mysteries: Dictionary = {}
## Untapped signs {mystery, index, type, appear_t, anchor ("" until visible)}; never expire.
var signs: Array[Dictionary] = []
## mystery id -> bitmask of the signs found (clues).
var clues: Dictionary = {}
## variant id -> unix time the cousin was met.
var variants_met: Dictionary = {}
## species -> base arrivals since its cousin was met (every cousin_every_n_visits-th brings it).
var cousin_visits: Dictionary = {}
## Qualifying returns so far (the scene hash key r, GDD §13.4).
var scene_returns: int = 0
## scene id -> times staged.
var scenes_seen: Dictionary = {}
## scene id -> Array[String] of friends who have appeared in it (the casting rule).
var scene_cast: Dictionary = {}
## {scene, cast: Array[String], phase, weather, world_t, shown_s} or {} (a staged scene not archived).
var pending_scene: Dictionary = {}
## Album > Memories: {scene, cast: Array[String], phase, weather, world_t, unix} (metadata only).
var memories: Array[Dictionary] = []
## species -> unix time of the ♥5 keepsake portrait.
var keepsakes: Dictionary = {}
## species -> unix time of its first signature gift (Keepsakes; the first carries the note).
var signature_gifts: Dictionary = {}
## World t when the app was last backgrounded (the 2 h scene rule); -1 = never.
var last_bg_t: float = -1.0
## Foreground opens so far (the wave-delay hash key, GDD §13.2.2).
var open_count: int = 0

# --- Active Play v1 (GDD §14.9; schema 3). Nothing here decays or expires (AP2).
## 0 = loaded from an older save: WorldSim runs ActiveRules.migrate_v1 once (décor anchors -> free
## positions, tea unlock) and sets it to [constant ACTIVE_VERSION].
var active_v: int = 0
## Active F1: pending wishes (<= max_pending) {species, wish, opened_t, state open/held, taps, placed}.
var wishes: Array[Dictionary] = []
## Foreground spawn checks so far (the hash index n) and foreground seconds since the last one.
var wish_checks: int = 0
var wish_fg_s: float = 0.0
## World t of the last spawn or grant (global gap); species -> the same per friend.
var wish_last_t: float = NEVER_T
var wish_friend_t: Dictionary = {}
## species -> {arrive_t, n}: wishes spawned during the visit that arrived at arrive_t (cap per visit).
var wish_visit_count: Dictionary = {}
## species -> previous wish id (repeat_mult).
var wish_last_id: Dictionary = {}
## species -> world t of the last affection-granting wish (its own 20 h rest).
var wish_aff_t: Dictionary = {}
## species -> bitmask over GameContent.wishes order (stamps; never decreases).
var wish_stamps: Dictionary = {}
var wishes_granted: int = 0
var wish_tutorial_done: bool = false
## World t the wish list card was last opened (its unread dot).
var wish_list_seen_t: float = 0.0
## Active F2: the tea nook has appeared.
var tea_unlocked: bool = false
## "bed_id:slot" -> petal anchor (world t); absent = the stem's bloom time (ACTIVE_TEA §2.1).
var petal_from_t: Dictionary = {}
## flower -> petals in its jar.
var pantry: Dictionary = {}
## {petals: Array[String], drops: int, stir_deg: float}; survives closing the sheet and the app.
var pot: Dictionary = {"petals": [], "drops": 0, "stir_deg": 0.0}
## Cups and treats waiting (<= tray.slots): {recipe, made_unix, drops, petals: Array[String]}.
var tray: Array[Dictionary] = []
## recipe id -> unix time first brewed.
var recipes_found: Dictionary = {}
## species -> Array[String] recipes whose reaction the player has seen.
var tea_prefs_seen: Dictionary = {}
## species -> world t of the last affection-granting cup (its own 20 h rest).
var tea_aff_t: Dictionary = {}
var teaware_owned: Array[String] = []
## slot -> teaware id in use; a missing slot uses the free default.
var teaware_set: Dictionary = {}
var cups_offered: int = 0
var tea_flags: Dictionary = {}
## Active F3: one entry per owned movable décor copy {id "set#n", set, x, y, rot, stored, stack, level}.
## x/y are frame-normalised foot positions (x may leave [0, 1] into the pan wings).
var decor_layout: Array[Dictionary] = []
## Save schema 4: one-time tips already shown, tip id -> true (Game.TIP_*). Additive; never cleared
## by the sim (only a "show tips again" reset would).
var tips_seen: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"install_seed": str(install_seed),
		"installed_unix": installed_unix,
		"rng_state": str(rng_state),
		"t": t,
		"anchor_world_t": anchor_world_t,
		"anchor_unix": anchor_unix,
		"tz_offset_s": tz_offset_s,
		"dew": dew,
		"basket": _copy_records(basket),
		"cup": cup,
		"cup_last_t": cup_last_t,
		"last_collect_t": last_collect_t,
		"owned": owned.duplicate(),
		"stems": _copy_records(stems),
		"items_bought": items_bought,
		"present": _copy_records(present),
		"next_candidate_t": next_candidate_t,
		"scripted": _copy_records(scripted),
		"met": met.duplicate(),
		"names": names.duplicate(),
		"affection": affection.duplicate(),
		"photos": photos.duplicate(),
		"photo_meta": photo_meta.duplicate(true),
		"postcards": _copy_records(postcards),
		"boats": boats,
		"last_pet_unix": last_pet_unix.duplicate(),
		"seed_planted": seed_planted,
		"seed_tap_t": seed_tap_t,
		"basket_full_seen": basket_full_seen,
		"first_bloom_postcard_sent": first_bloom_postcard_sent,
		"retention_v": retention_v,
		"visit_aff_t": visit_aff_t.duplicate(),
		"hearts_seen": hearts_seen.duplicate(),
		"nests": nests.duplicate(true),
		"postcards_waiting": postcards_waiting.duplicate(),
		"mysteries": mysteries.duplicate(true),
		"signs": _copy_records(signs),
		"clues": clues.duplicate(),
		"variants_met": variants_met.duplicate(),
		"cousin_visits": cousin_visits.duplicate(),
		"scene_returns": scene_returns,
		"scenes_seen": scenes_seen.duplicate(),
		"scene_cast": scene_cast.duplicate(true),
		"pending_scene": pending_scene.duplicate(true),
		"memories": _copy_records(memories),
		"keepsakes": keepsakes.duplicate(),
		"signature_gifts": signature_gifts.duplicate(),
		"last_bg_t": last_bg_t,
		"open_count": open_count,
		"active_v": active_v,
		"wishes": _copy_records(wishes),
		"wish_checks": wish_checks,
		"wish_fg_s": wish_fg_s,
		"wish_last_t": wish_last_t,
		"wish_friend_t": wish_friend_t.duplicate(),
		"wish_visit_count": wish_visit_count.duplicate(true),
		"wish_last_id": wish_last_id.duplicate(),
		"wish_aff_t": wish_aff_t.duplicate(),
		"wish_stamps": wish_stamps.duplicate(),
		"wishes_granted": wishes_granted,
		"wish_tutorial_done": wish_tutorial_done,
		"wish_list_seen_t": wish_list_seen_t,
		"tea_unlocked": tea_unlocked,
		"petal_from_t": petal_from_t.duplicate(),
		"pantry": pantry.duplicate(),
		"pot": pot.duplicate(true),
		"tray": _copy_records(tray),
		"recipes_found": recipes_found.duplicate(),
		"tea_prefs_seen": tea_prefs_seen.duplicate(true),
		"tea_aff_t": tea_aff_t.duplicate(),
		"teaware_owned": teaware_owned.duplicate(),
		"teaware_set": teaware_set.duplicate(),
		"cups_offered": cups_offered,
		"tea_flags": tea_flags.duplicate(),
		"decor_layout": _copy_records(decor_layout),
		"tips_seen": tips_seen.duplicate(),
	}


## Rebuilds a state from [method to_dict] output (or parsed JSON, where every number is a float).
## Unknown keys are ignored, missing keys keep their defaults, and every value is coerced to its
## declared type, so a hand-edited or partially written file can never inject a wrong type.
static func from_dict(d: Dictionary) -> WorldState:
	var s := WorldState.new()
	s.install_seed = _to_int64(d.get("install_seed", "0"))
	s.installed_unix = float(d.get("installed_unix", 0.0))
	s.rng_state = _to_int64(d.get("rng_state", "0"))
	s.t = maxf(0.0, float(d.get("t", 0.0)))
	s.anchor_world_t = float(d.get("anchor_world_t", s.t))
	s.anchor_unix = float(d.get("anchor_unix", 0.0))
	s.tz_offset_s = float(d.get("tz_offset_s", 0.0))
	s.dew = maxi(0, int(d.get("dew", 0)))
	s.basket = _records(d.get("basket", []), BASKET_TEMPLATE)
	s.cup = maxf(0.0, float(d.get("cup", 0.0)))
	s.cup_last_t = float(d.get("cup_last_t", 0.0))
	s.last_collect_t = float(d.get("last_collect_t", 0.0))
	s.owned = _int_map(d.get("owned", {}))
	s.stems = _records(d.get("stems", []),
			{"flower": "", "bed": "", "slot": 0, "planted_t": 0.0, "tutorial": false, "stage": 0})
	s.items_bought = maxi(0, int(d.get("items_bought", 0)))
	s.present = _records(d.get("present", []), PRESENT_TEMPLATE)
	s.next_candidate_t = float(d.get("next_candidate_t", 0.0))
	s.scripted = _records(d.get("scripted", []), {"t": 0.0, "kind": "", "species": "", "stay_s": 0.0,
		"gift_dew": 0, "id": "", "role": ""})
	s.met = _float_map(d.get("met", {}))
	s.names = _string_map(d.get("names", {}))
	s.affection = _int_map(d.get("affection", {}))
	s.photos = _int_map(d.get("photos", {}))
	var pm: Variant = d.get("photo_meta", {})
	if pm is Dictionary:
		for k: Variant in pm:
			var v: Variant = pm[k]
			if v is Dictionary:
				var meta: Dictionary = v
				s.photo_meta[String(k)] = _coerce(meta, {"phase": "", "weather": "", "world_t": 0.0})
	s.postcards = _records(d.get("postcards", []),
			{"id": "", "template": "", "species": "", "received_unix": 0.0, "read": false})
	s.boats = maxi(0, int(d.get("boats", 0)))
	s.last_pet_unix = _float_map(d.get("last_pet_unix", {}))
	s.seed_planted = bool(d.get("seed_planted", false))
	s.seed_tap_t = float(d.get("seed_tap_t", -1.0))
	s.basket_full_seen = bool(d.get("basket_full_seen", false))
	s.first_bloom_postcard_sent = bool(d.get("first_bloom_postcard_sent", false))
	s.retention_v = maxi(0, int(d.get("retention_v", 0)))
	s.visit_aff_t = _float_map(d.get("visit_aff_t", {}))
	s.hearts_seen = _int_map(d.get("hearts_seen", {}))
	s.nests = _record_map(d.get("nests", {}), NEST_TEMPLATE)
	s.postcards_waiting = _strings(d.get("postcards_waiting", []))
	s.mysteries = _record_map(d.get("mysteries", {}), MYSTERY_TEMPLATE)
	s.signs = _records(d.get("signs", []), SIGN_TEMPLATE)
	s.clues = _int_map(d.get("clues", {}))
	s.variants_met = _float_map(d.get("variants_met", {}))
	s.cousin_visits = _int_map(d.get("cousin_visits", {}))
	s.scene_returns = maxi(0, int(d.get("scene_returns", 0)))
	s.scenes_seen = _int_map(d.get("scenes_seen", {}))
	var sc: Variant = d.get("scene_cast", {})
	if sc is Dictionary:
		for k: Variant in sc:
			s.scene_cast[String(k)] = Array(_strings(sc[k]))
	var ps: Variant = d.get("pending_scene", {})
	if ps is Dictionary and String((ps as Dictionary).get("scene", "")) != "":
		var pend: Dictionary = ps
		s.pending_scene = _coerce(pend, SCENE_TEMPLATE)
		s.pending_scene["shown_s"] = maxf(0.0, float(s.pending_scene["shown_s"]))
		s.pending_scene["cast"] = Array(_strings(pend.get("cast", [])))
	var mem: Variant = d.get("memories", [])
	if mem is Array:
		for v: Variant in mem:
			if v is Dictionary:
				var m: Dictionary = v
				var rec := _coerce(m, MEMORY_TEMPLATE)
				rec["cast"] = Array(_strings(m.get("cast", [])))
				s.memories.append(rec)
	s.keepsakes = _float_map(d.get("keepsakes", {}))
	s.signature_gifts = _float_map(d.get("signature_gifts", {}))
	s.last_bg_t = float(d.get("last_bg_t", -1.0))
	s.open_count = maxi(0, int(d.get("open_count", 0)))
	_active_from_dict(s, d)
	return s


## Active Play v1 fields (GDD §14.9), coerced like the rest.
static func _active_from_dict(s: WorldState, d: Dictionary) -> void:
	s.active_v = maxi(0, int(d.get("active_v", 0)))
	s.wishes = _records(d.get("wishes", []), WISH_TEMPLATE)
	s.wish_checks = maxi(0, int(d.get("wish_checks", 0)))
	s.wish_fg_s = maxf(0.0, float(d.get("wish_fg_s", 0.0)))
	s.wish_last_t = float(d.get("wish_last_t", NEVER_T))
	s.wish_friend_t = _float_map(d.get("wish_friend_t", {}))
	s.wish_visit_count = _record_map(d.get("wish_visit_count", {}), VISIT_COUNT_TEMPLATE)
	s.wish_last_id = _string_map(d.get("wish_last_id", {}))
	s.wish_aff_t = _float_map(d.get("wish_aff_t", {}))
	s.wish_stamps = _int_map(d.get("wish_stamps", {}))
	s.wishes_granted = maxi(0, int(d.get("wishes_granted", 0)))
	s.wish_tutorial_done = bool(d.get("wish_tutorial_done", false))
	s.wish_list_seen_t = float(d.get("wish_list_seen_t", 0.0))
	s.tea_unlocked = bool(d.get("tea_unlocked", false))
	s.petal_from_t = _float_map(d.get("petal_from_t", {}))
	s.pantry = _int_map(d.get("pantry", {}))
	var pot: Variant = d.get("pot", {})
	if pot is Dictionary:
		var pd: Dictionary = pot
		s.pot = {"petals": Array(_strings(pd.get("petals", []))), "drops": maxi(0, int(pd.get("drops", 0))),
			"stir_deg": maxf(0.0, float(pd.get("stir_deg", 0.0)))}
	var tray: Variant = d.get("tray", [])
	if tray is Array:
		for v: Variant in tray:
			if v is Dictionary:
				var rec := _coerce(v, TRAY_TEMPLATE)
				rec["petals"] = Array(_strings((v as Dictionary).get("petals", [])))
				s.tray.append(rec)
	s.recipes_found = _float_map(d.get("recipes_found", {}))
	var seen: Variant = d.get("tea_prefs_seen", {})
	if seen is Dictionary:
		for k: Variant in seen:
			s.tea_prefs_seen[String(k)] = Array(_strings(seen[k]))
	s.tea_aff_t = _float_map(d.get("tea_aff_t", {}))
	s.teaware_owned = _strings(d.get("teaware_owned", []))
	s.teaware_set = _string_map(d.get("teaware_set", {}))
	s.cups_offered = maxi(0, int(d.get("cups_offered", 0)))
	var flags: Variant = d.get("tea_flags", {})
	if flags is Dictionary:
		for k: Variant in flags:
			s.tea_flags[String(k)] = bool(flags[k])
	s.decor_layout = _records(d.get("decor_layout", []), DECOR_PIECE_TEMPLATE)
	var tips: Variant = d.get("tips_seen", {})
	if tips is Dictionary:
		for k: Variant in tips:
			var on: Variant = tips[k]
			if (on is bool and on) or ((on is int or on is float) and on != 0):
				s.tips_seen[String(k)] = true


func duplicate_state() -> WorldState:
	return WorldState.from_dict(to_dict())


# ------------------------------------------------------------------ helpers

static func _copy_records(list: Array[Dictionary]) -> Array:
	var out: Array = []
	for r: Dictionary in list:
		out.append(r.duplicate(true))
	return out


## Coerces each record to the types of [param template] (its keys and default values).
static func _records(list: Variant, template: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if list is Array:
		for v: Variant in list:
			if v is Dictionary:
				var rec: Dictionary = v
				out.append(_coerce(rec, template))
	return out


static func _coerce(src: Dictionary, template: Dictionary) -> Dictionary:
	var r := {}
	for key: String in template:
		var def: Variant = template[key]
		var v: Variant = src.get(key, def)
		match typeof(def):
			TYPE_BOOL:
				r[key] = bool(v)
			TYPE_INT:
				r[key] = int(v)
			TYPE_FLOAT:
				r[key] = float(v)
			_:
				r[key] = str(v)
	return r


## String -> record map, each record coerced to [param template].
static func _record_map(v: Variant, template: Dictionary) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k: Variant in v:
			var r: Variant = v[k]
			if r is Dictionary:
				var rec: Dictionary = r
				out[String(k)] = _coerce(rec, template)
	return out


static func _strings(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for e: Variant in v:
			out.append(str(e))
	return out


static func _int_map(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k: Variant in v:
			out[String(k)] = maxi(0, int(v[k]))
	return out


static func _float_map(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k: Variant in v:
			out[String(k)] = float(v[k])
	return out


static func _string_map(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k: Variant in v:
			out[String(k)] = str(v[k])
	return out


## 64-bit integers are stored as decimal strings: JSON numbers are doubles (53-bit mantissa).
static func _to_int64(v: Variant) -> int:
	if v is String:
		return (v as String).to_int()
	return int(v)
