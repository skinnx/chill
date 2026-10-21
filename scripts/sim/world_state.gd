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
	s.basket = _records(d.get("basket", []), {"species": "", "gift_item": "", "dew": 0})
	s.cup = maxf(0.0, float(d.get("cup", 0.0)))
	s.cup_last_t = float(d.get("cup_last_t", 0.0))
	s.last_collect_t = float(d.get("last_collect_t", 0.0))
	s.owned = _int_map(d.get("owned", {}))
	s.stems = _records(d.get("stems", []),
			{"flower": "", "bed": "", "slot": 0, "planted_t": 0.0, "tutorial": false, "stage": 0})
	s.items_bought = maxi(0, int(d.get("items_bought", 0)))
	s.present = _records(d.get("present", []), {"species": "", "arrive_t": 0.0, "depart_t": 0.0, "gift_dew": 0,
		"gift_item": "", "boat_credit": false, "pet_credit": false, "scripted": false, "greeter": false})
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
	return s


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
