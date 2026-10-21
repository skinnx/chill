class_name GameContent
extends RefCounted
## Read-only, pre-indexed view of every data file in res://data (docs/ARCHITECTURE.md §4).
##
## Pure: no nodes, no autoloads. The ContentRegistry autoload owns the shared instance;
## tests and tools build their own with [method load_from_dir]. Every game number comes from
## these files (GDD §10); this class adds indexes and formulas, never constants.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const DATA_DIR := "res://data"
const AUDIO_MANIFEST_PATH := "res://audio/manifest.json"
## File stem -> required top-level keys. Order is the load order.
const FILES := {
	"species": ["schema", "species"],
	"flora": ["schema", "flowers"],
	"decor": ["schema", "decor"],
	"economy": ["schema", "basket_slots", "onboarding", "heart_thresholds"],
	"world": ["schema", "phases", "weather", "weather_plan", "seasons", "season_cycle"],
	"spots": ["schema", "frame", "spots", "beds", "entries", "decor_anchors", "props", "stream"],
	"palettes": ["schema", "tod", "weather", "ui", "creatures", "flora"],
	"motion_tokens": ["schema", "durations_ms", "curves", "springs", "time", "reduce_motion", "world", "ui"],
	"creature_rig": ["schema", "catalog", "species"],
}
const SUPPORTED_SCHEMA := 1
const KIND_FLOWER := &"flower"
const KIND_DECOR := &"decor"
const BEHAVIOURS: Array[StringName] = [&"nap", &"nibble", &"play", &"wander", &"sit_by_stream"]

## Raw parsed files, keyed by stem ("species", "flora", ...). Treat as read-only.
var raw: Dictionary = {}
## Optional generated audio contract (tools/audio/synth.py); empty when not rendered yet.
var audio_manifest: Dictionary = {}
var errors: PackedStringArray = PackedStringArray()

var economy: Dictionary = {}
var world: Dictionary = {}
var spots_doc: Dictionary = {}
var palettes: Dictionary = {}
var motion: Dictionary = {}
var creature_rig: Dictionary = {}

## Species sorted by album_order.
var species: Array[Dictionary] = []
var species_by_id: Dictionary = {}
## Flowers / décor sorted by garden_order.
var flowers: Array[Dictionary] = []
var flowers_by_id: Dictionary = {}
var decor: Array[Dictionary] = []
var decor_by_id: Dictionary = {}
## item id -> KIND_FLOWER / KIND_DECOR.
var item_kind: Dictionary = {}
## Phases sorted by start_s.
var phases: Array[Dictionary] = []
var phase_index: Dictionary = {}
var weather: Array[Dictionary] = []
var weather_by_id: Dictionary = {}
var beds: Array[Dictionary] = []
var beds_by_id: Dictionary = {}
var spots: Array[Dictionary] = []
var spots_by_id: Dictionary = {}
var entries_by_id: Dictionary = {}
var anchors_by_decor: Dictionary = {}
var props_by_id: Dictionary = {}
var gift_items_by_id: Dictionary = {}
## Event postcard trigger -> postcard record.
var event_postcards_by_trigger: Dictionary = {}


## Loads and indexes every file in [param dir]. Never returns null; check [member errors].
static func load_from_dir(dir: String = DATA_DIR, manifest_path: String = AUDIO_MANIFEST_PATH) -> GameContent:
	var c := GameContent.new()
	for stem: String in FILES:
		var path := "%s/%s.json" % [dir, stem]
		var doc: Variant = read_json(path, c.errors)
		if doc is Dictionary:
			c.raw[stem] = doc
		else:
			c.raw[stem] = {}
	if manifest_path != "" and FileAccess.file_exists(manifest_path):
		var m: Variant = read_json(manifest_path, c.errors)
		if m is Dictionary:
			c.audio_manifest = m
	c._index()
	return c


## Builds content from already-parsed documents (used by tests to inject edited data).
static func from_documents(docs: Dictionary) -> GameContent:
	var c := GameContent.new()
	for stem: String in FILES:
		var d: Variant = docs.get(stem, {})
		c.raw[stem] = (d as Dictionary).duplicate(true) if d is Dictionary else {}
	c._index()
	return c


## Parses a UTF-8 JSON file. Appends a readable message to [param errors] on failure.
static func read_json(path: String, errors: PackedStringArray) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("missing file: %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.append("empty or unreadable file: %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		errors.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func is_valid() -> bool:
	return errors.is_empty()


# ------------------------------------------------------------------ formulas (GDD §5)

## price(item, n) = floor(cost_base * cost_growth^n + 0.5), n = copies already owned (GDD §5.2).
func price(item_id: StringName, owned: int) -> int:
	var d := item_def(item_id)
	if d.is_empty():
		return 0
	return int(floor(float(d["cost_base"]) * pow(float(d["cost_growth"]), owned) + 0.5))


func max_copies(item_id: StringName) -> int:
	var d := item_def(item_id)
	return int(d.get("max_copies", 0))


func item_def(item_id: StringName) -> Dictionary:
	var kind: StringName = item_kind.get(item_id, &"")
	if kind == KIND_FLOWER:
		return flowers_by_id[item_id]
	if kind == KIND_DECOR:
		return decor_by_id[item_id]
	return {}


func is_flower(item_id: StringName) -> bool:
	return item_kind.get(item_id, &"") == KIND_FLOWER


func is_decor(item_id: StringName) -> bool:
	return item_kind.get(item_id, &"") == KIND_DECOR


## Hearts for an affection total (GDD §5.10): thresholds passed.
func hearts_for(affection: int) -> int:
	var h := 0
	for thr: Variant in economy["heart_thresholds"]:
		if affection >= int(thr):
			h += 1
	return h


## Total number of purchasable copies (the free tutorial clover is copy #1 of its flower).
func catalogue_size() -> int:
	var n := 0
	for f: Dictionary in flowers:
		n += int(f["max_copies"])
	for d: Dictionary in decor:
		n += int(d["max_copies"])
	return n


func season_for_world_day(world_day: int) -> StringName:
	var cycle: Array = world["season_cycle"]
	var length_days := 1
	for s: Dictionary in world["seasons"]:
		if s["id"] == cycle[0]:
			length_days = maxi(1, int(s["length_days"]))
	var idx := posmod(floori(float(world_day) / float(length_days)), cycle.size())
	return StringName(cycle[idx])


# ------------------------------------------------------------------ indexing

func _index() -> void:
	for stem: String in FILES:
		var doc: Dictionary = raw.get(stem, {})
		if doc.is_empty():
			if not errors.has("missing file: %s/%s.json" % [DATA_DIR, stem]):
				errors.append("no data for %s" % stem)
			continue
		for key: String in FILES[stem]:
			if not doc.has(key):
				errors.append("%s.json: missing top-level key '%s'" % [stem, key])
		if int(doc.get("schema", -1)) != SUPPORTED_SCHEMA:
			errors.append("%s.json: unsupported schema %s" % [stem, str(doc.get("schema"))])
	economy = raw.get("economy", {})
	world = raw.get("world", {})
	spots_doc = raw.get("spots", {})
	palettes = raw.get("palettes", {})
	motion = raw.get("motion_tokens", {})
	creature_rig = raw.get("creature_rig", {})
	if not errors.is_empty():
		return

	species = _sorted_records(raw["species"]["species"], "album_order")
	flowers = _sorted_records(raw["flora"]["flowers"], "garden_order")
	decor = _sorted_records(raw["decor"]["decor"], "garden_order")
	phases = _sorted_records(world["phases"], "start_s")
	weather = _records(world["weather"])
	beds = _sorted_records(spots_doc["beds"], "fill_order")
	spots = _records(spots_doc["spots"])
	for s: Dictionary in species:
		species_by_id[StringName(s["id"])] = s
	for f: Dictionary in flowers:
		flowers_by_id[StringName(f["id"])] = f
		item_kind[StringName(f["id"])] = KIND_FLOWER
	for d: Dictionary in decor:
		decor_by_id[StringName(d["id"])] = d
		item_kind[StringName(d["id"])] = KIND_DECOR
	for i in phases.size():
		phase_index[StringName(phases[i]["id"])] = i
	for w: Dictionary in weather:
		weather_by_id[StringName(w["id"])] = w
	for b: Dictionary in beds:
		beds_by_id[StringName(b["id"])] = b
	for s: Dictionary in spots:
		spots_by_id[StringName(s["id"])] = s
	for e: Dictionary in _records(spots_doc["entries"]):
		entries_by_id[StringName(e["id"])] = e
	for a: Dictionary in _records(spots_doc["decor_anchors"]):
		anchors_by_decor[StringName(a["decor_id"])] = a
	for p: Dictionary in _records(spots_doc["props"]):
		props_by_id[StringName(p["id"])] = p
	for g: Dictionary in _records(economy.get("gift_items", [])):
		gift_items_by_id[StringName(g["id"])] = g
	for p: Dictionary in _records(economy.get("event_postcards", [])):
		event_postcards_by_trigger[StringName(p["trigger"])] = p
	_check_references()


func _check_references() -> void:
	for s: Dictionary in species:
		var sid: String = s["id"]
		for r: Dictionary in s["requires"]:
			if not item_kind.has(StringName(r["item"])):
				errors.append("species %s requires unknown item %s" % [sid, r["item"]])
		for l: Dictionary in s["likes_items"]:
			if not item_kind.has(StringName(l["item"])):
				errors.append("species %s likes unknown item %s" % [sid, l["item"]])
		for l: Dictionary in s["likes_weather"]:
			if not weather_by_id.has(StringName(l["weather"])):
				errors.append("species %s likes unknown weather %s" % [sid, l["weather"]])
		for p: Variant in s["phases"]:
			if not phase_index.has(StringName(p)):
				errors.append("species %s has unknown phase %s" % [sid, p])
		for l: Dictionary in s["likes_phases"]:
			if not phase_index.has(StringName(l["phase"])):
				errors.append("species %s likes unknown phase %s" % [sid, l["phase"]])
		if not spots_by_id.has(StringName(s["favourite_spot"])):
			errors.append("species %s favourite spot %s missing" % [sid, s["favourite_spot"]])
		if not entries_by_id.has(StringName(s["entry"])):
			errors.append("species %s entry %s missing" % [sid, s["entry"]])
		if not gift_items_by_id.has(StringName(s["gift_item"])):
			errors.append("species %s gift item %s missing" % [sid, s["gift_item"]])
		var total := 0.0
		var weights: Dictionary = s["behaviours"]
		for b: StringName in BEHAVIOURS:
			total += float(weights.get(String(b), 0.0))
		if absf(total - 1.0) > 1e-6:
			errors.append("species %s behaviour weights sum to %f" % [sid, total])
	for d: Dictionary in decor:
		if not anchors_by_decor.has(StringName(d["anchor"])):
			errors.append("decor %s anchor missing" % d["id"])
	var ob: Dictionary = economy["onboarding"]
	for key: String in ["first_visitor", "second_visitor", "third_visitor"]:
		if not species_by_id.has(StringName(ob[key])):
			errors.append("onboarding %s species %s missing" % [key, ob[key]])
	if not flowers_by_id.has(StringName(ob["tutorial_flower"])):
		errors.append("onboarding tutorial flower missing")
	if not beds_by_id.has(StringName(ob["tutorial_bed"])):
		errors.append("onboarding tutorial bed missing")
	for key: StringName in [&"night", &"dawn", &"day", &"golden", &"dusk"]:
		if not phase_index.has(key):
			errors.append("world.json: phase %s missing" % key)
	for key: StringName in [&"clear", &"breeze", &"rain"]:
		if not weather_by_id.has(key):
			errors.append("world.json: weather %s missing" % key)


static func _records(list: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if list is Array:
		for v: Variant in list:
			if v is Dictionary:
				out.append(v)
	return out


static func _sorted_records(list: Variant, key: String) -> Array[Dictionary]:
	var out := _records(list)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a[key]) < float(b[key]))
	return out
