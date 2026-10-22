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
	# Retention v1 (GDD §13.10)
	"friendship": ["schema", "heart_unlocks", "wave_on_open", "signature_gift", "nest", "pair", "keepsake",
		"celebration"],
	"mysteries": ["schema", "sign_types", "anchors", "species", "variants", "max_visible", "sign_windows_s",
		"variant_sign_windows_s", "debut_after_last_sign_s", "variant_hearts_required",
		"variant_requires_all_met", "cousin_every_n_visits"],
	"scenes": ["schema", "scenes", "min_absence_s", "max_per_return", "scene_chance", "linger_s", "away_sample_s"],
	# Active Play v1 (GDD §14): Active F1 wishes, Active F2 tea & treats, Active F3 free décor placement
	"wishes": ["schema", "tuning", "reward", "hash_keys", "traits", "wishes"],
	"tea": ["schema", "unlock", "nook", "harvest", "petals", "dew_drop", "pot", "brewing", "tray", "offering",
		"recipes", "species_prefs", "likes_revealed_at_heart", "teaware", "event_postcards"],
	"decor_placement": ["schema", "feature_flag", "edit_mode", "hit", "area", "clearances", "sets", "snap",
		"beautify", "derived_spots", "attraction", "auto_place", "migration", "undo"],
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

# --- Retention v1 (GDD §13; friendship.json, mysteries.json, scenes.json)
var friendship: Dictionary = {}
var mysteries: Dictionary = {}
var scenes_doc: Dictionary = {}
## economy.signature_gift_items by id (GDD §13.2.2); [method gift_item_def] looks in both lists.
var signature_items_by_id: Dictionary = {}
## Nest stages sorted by at_s ({id, at_s, name_key}); styles and anchors by id / species.
var nest_stages: Array[Dictionary] = []
var nest_styles_by_id: Dictionary = {}
var nest_anchor_by_species: Dictionary = {}
## mysteries.json species records by species id ({species, riddle_key, signs, onboarding, ...}).
var mystery_species_by_id: Dictionary = {}
## Cousins in data order; by id and by base species (one per species in the MVP).
var variants: Array[Dictionary] = []
var variants_by_id: Dictionary = {}
var variants_by_species: Dictionary = {}
## Sign anchors in data order (the anchor tie-break) and sign types by id.
var sign_anchors: Array[Dictionary] = []
var sign_types_by_id: Dictionary = {}
## Away scenes in data order (the weighted pick walks this order) and by id.
var scenes: Array[Dictionary] = []
var scenes_by_id: Dictionary = {}

# --- Active Play v1 (GDD §14; wishes.json, tea.json, decor_placement.json)
var wishes_doc: Dictionary = {}
var tea: Dictionary = {}
var decor_placement: Dictionary = {}
## Wishes in data order (append-only: wish_stamps are a bitmask over this order), by id, and the
## index of each id in that order.
var wishes: Array[Dictionary] = []
var wishes_by_id: Dictionary = {}
var wish_index: Dictionary = {}
## Parsed wish targets by wish id: {kind: StringName, arg: String, n: int} (ACTIVE_WISHES §5 grammar).
var wish_targets: Dictionary = {}
## species -> Array[String] personality tags (wishes.json traits).
var wish_traits: Dictionary = {}
## flower id -> tea.json petals row {flower, petal_regrow_s, pantry_cap, jar_order}.
var petals_by_flower: Dictionary = {}
## Tea recipes in book order, by id; named recipes by their mix key ([method tea_mix_key]);
## fallback recipe id by drop count.
var recipes: Array[Dictionary] = []
var recipes_by_id: Dictionary = {}
var recipe_by_mix: Dictionary = {}
var recipe_fallback_by_drops: Dictionary = {}
var named_recipe_count: int = 0
## species -> {loves: Array, likes: Array, gift_petal: String}.
var tea_prefs: Dictionary = {}
var teaware_by_id: Dictionary = {}
## slot -> the free default teaware id.
var teaware_default: Dictionary = {}


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


## A gift item from economy.gift_items or economy.signature_gift_items ({} if unknown).
func gift_item_def(item_id: StringName) -> Dictionary:
	if gift_items_by_id.has(item_id):
		return gift_items_by_id[item_id]
	return signature_items_by_id.get(item_id, {})


## Album index (0-based, album_order) of a species; a large number for unknown ids.
func album_index(species_id: StringName) -> int:
	for i in species.size():
		if StringName(species[i]["id"]) == species_id:
			return i
	return species.size()


## True for the onboarding friends, who arrive without a mystery (mysteries.json "onboarding").
func is_onboarding_species(species_id: StringName) -> bool:
	var rec: Dictionary = mystery_species_by_id.get(species_id, {})
	return bool(rec.get("onboarding", true))


## Seconds windows [[lo, hi]...] for a mystery with [param n] signs (species or cousin table).
func sign_windows(n: int, variant: bool) -> Array:
	var table: Dictionary = mysteries["variant_sign_windows_s" if variant else "sign_windows_s"]
	return table.get(str(n), [])


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


# ------------------------------------------------------------------ Active Play v1 (GDD §14)

## The recipe-match key of a pot: petals as a sorted multiset plus the drop count
## ("button_daisy,sweet_clover,sweet_clover|0"). Order in the pot never matters (tea.json match_rule).
static func tea_mix_key(petals: Array, drops: int) -> String:
	var list := PackedStringArray()
	for p: Variant in petals:
		list.append(str(p))
	list.sort()
	return "%s|%d" % [",".join(list), drops]


## The recipe a pot makes: the exact named mix, else the fallback for its drop count (&"" when the
## pot is not brewable: no petals, too many, or a drop count without a fallback).
func match_recipe(petals: Array, drops: int) -> StringName:
	var pot: Dictionary = tea.get("pot", {})
	if petals.size() < int(pot.get("min_petals", 1)) or petals.size() > int(pot.get("max_petals", 3)):
		return &""
	var key := tea_mix_key(petals, drops)
	if recipe_by_mix.has(key):
		return recipe_by_mix[key]
	return recipe_fallback_by_drops.get(drops, &"")


## Petals a named recipe needs as flower -> count ({} for a fallback).
func recipe_petals(recipe_id: StringName) -> Dictionary:
	var r: Dictionary = recipes_by_id.get(recipe_id, {})
	var p: Variant = r.get("petals", {})
	return p if p is Dictionary else {}


func is_named_recipe(recipe_id: StringName) -> bool:
	var r: Dictionary = recipes_by_id.get(recipe_id, {})
	return not r.is_empty() and String(r.get("match", "")) != "fallback"


## decor_placement.json sets record of a décor id ({} if unknown).
func placement_set(decor_id: StringName) -> Dictionary:
	var sets: Dictionary = decor_placement.get("sets", {})
	return sets.get(String(decor_id), {})


func is_movable_decor(decor_id: StringName) -> bool:
	return bool(placement_set(decor_id).get("movable", false))


func _index_active() -> void:
	wishes = _records(wishes_doc["wishes"])
	for i in wishes.size():
		var w := wishes[i]
		var id := StringName(w["id"])
		wishes_by_id[id] = w
		wish_index[id] = i
		var target := String(w["target"])
		var kind := target.get_slice(":", 0)
		var arg := target.substr(kind.length() + 1) if target.contains(":") else ""
		wish_targets[id] = {"kind": StringName(kind), "arg": arg, "n": arg.to_int() if arg.is_valid_int() else 0}
	var traits: Dictionary = wishes_doc["traits"]
	for sp: Variant in traits:
		wish_traits[StringName(sp)] = Array(traits[sp])
	for p: Dictionary in _records(tea["petals"]):
		petals_by_flower[StringName(p["flower"])] = p
	recipes = _sorted_records(tea["recipes"], "book_order")
	for r: Dictionary in recipes:
		var id := StringName(r["id"])
		recipes_by_id[id] = r
		if String(r.get("match", "")) == "fallback":
			for d: Variant in r.get("drops_any", []):
				recipe_fallback_by_drops[int(d)] = id
			continue
		named_recipe_count += 1
		var list: Array = []
		var petals: Dictionary = r["petals"]
		for f: Variant in petals:
			for i in int(petals[f]):
				list.append(String(f))
		recipe_by_mix[tea_mix_key(list, int(r["drops"]))] = id
	var prefs: Dictionary = tea["species_prefs"]
	for sp: Variant in prefs:
		tea_prefs[StringName(sp)] = prefs[sp]
	for x: Dictionary in _records(tea["teaware"]):
		teaware_by_id[StringName(x["id"])] = x
		if bool(x.get("default", false)):
			teaware_default[String(x["slot"])] = String(x["id"])
	# Tea event postcards live in tea.json (GDD §14.4 D20); the world sends them like any other.
	for p: Dictionary in _records(tea["event_postcards"]):
		event_postcards_by_trigger[StringName(p["trigger"])] = p


## Cross-references of the Active Play data (the full lint is tools/sim/validate_content.py).
func _check_active() -> void:
	for sp: Dictionary in species:
		var sid := StringName(sp["id"])
		if not wish_traits.has(sid):
			errors.append("wishes.json: no traits for species %s" % sid)
		if not tea_prefs.has(sid):
			errors.append("tea.json: no species_prefs for %s" % sid)
	for w: Dictionary in wishes:
		var id := StringName(w["id"])
		var tg: Dictionary = wish_targets[id]
		var arg := StringName(tg["arg"])
		match StringName(tg["kind"]):
			&"bed_invite", &"tea_petal":
				if not flowers_by_id.has(arg):
					errors.append("wish %s: unknown flower %s" % [id, arg])
			&"decor_near", &"decor_tap":
				if not decor_by_id.has(arg):
					errors.append("wish %s: unknown décor %s" % [id, arg])
			&"tea":
				if not recipes_by_id.has(arg):
					errors.append("wish %s: unknown recipe %s" % [id, arg])
			&"tea_kind":
				if arg != &"tea" and arg != &"treat":
					errors.append("wish %s: tea_kind must be tea or treat" % id)
			&"pet", &"play_taps", &"chime_tap", &"boat", &"stream_tap", &"tea_loved":
				pass
			_:
				errors.append("wish %s: unknown target kind %s" % [id, tg["kind"]])
		var req: Dictionary = w["requires"]
		for f: Variant in req.get("bloomed", {}):
			if not flowers_by_id.has(StringName(f)):
				errors.append("wish %s requires unknown flower %s" % [id, f])
		for d: Variant in req.get("owned", {}):
			if not decor_by_id.has(StringName(d)):
				errors.append("wish %s requires unknown décor %s" % [id, d])
		for s: Variant in Array(w["prefer"]) + Array(w["species_only"]):
			if not species_by_id.has(StringName(s)):
				errors.append("wish %s names unknown species %s" % [id, s])
	if wishes.size() > 62:
		errors.append("wishes.json: more than 62 wishes do not fit the wish_stamps bitmask")
	if not wishes_by_id.has(StringName(wishes_doc["tuning"]["first_wish"]["wish"])):
		errors.append("wishes.json: unknown first_wish")
	for f: Dictionary in flowers:
		if not petals_by_flower.has(StringName(f["id"])):
			errors.append("tea.json: no petals row for flower %s" % f["id"])
	for r: Dictionary in recipes:
		var petals: Variant = r.get("petals", {})
		if petals is Dictionary:
			for f: Variant in petals:
				if not flowers_by_id.has(StringName(f)):
					errors.append("recipe %s: unknown flower %s" % [r["id"], f])
	for d in int(tea["pot"]["max_drops"]) + 1:
		if not recipe_fallback_by_drops.has(d):
			errors.append("tea.json: no fallback recipe for %d drops" % d)
	for sp: StringName in tea_prefs:
		var pr: Dictionary = tea_prefs[sp]
		for rid: Variant in Array(pr["loves"]) + Array(pr["likes"]):
			if not recipes_by_id.has(StringName(rid)):
				errors.append("tea.species_prefs.%s: unknown recipe %s" % [sp, rid])
		if not flowers_by_id.has(StringName(pr["gift_petal"])):
			errors.append("tea.species_prefs.%s: unknown gift_petal %s" % [sp, pr["gift_petal"]])
	for slot: Variant in ["teapot", "cup", "cloth"]:
		if not teaware_default.has(slot):
			errors.append("tea.json: no default teaware for slot %s" % slot)
	if not props_by_id.has(StringName(tea["nook"]["on_prop"])):
		errors.append("tea.json: nook.on_prop is not a spots.json prop")
	var sets: Dictionary = decor_placement["sets"]
	for d: Dictionary in decor:
		if not sets.has(String(d["id"])):
			errors.append("decor_placement.json: no sets entry for %s" % d["id"])
	for id: Variant in sets:
		var st: Dictionary = sets[id]
		if not decor_by_id.has(StringName(id)):
			errors.append("decor_placement.json: unknown set %s" % id)
		elif bool(st.get("movable", false)) and Array(st.get("rot_render", [])).size() != int(st["rot_steps"]):
			errors.append("decor_placement.sets.%s: rot_render must hold rot_steps entries" % id)
	for sid: Variant in decor_placement["derived_spots"]:
		var ds: Variant = decor_placement["derived_spots"][sid]
		if ds is Dictionary and not spots_by_id.has(StringName(sid)):
			errors.append("decor_placement.derived_spots: unknown spot %s" % sid)


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
	friendship = raw.get("friendship", {})
	mysteries = raw.get("mysteries", {})
	scenes_doc = raw.get("scenes", {})
	wishes_doc = raw.get("wishes", {})
	tea = raw.get("tea", {})
	decor_placement = raw.get("decor_placement", {})
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
	_index_retention()
	_index_active()
	_check_references()
	_check_retention()
	_check_active()


func _index_retention() -> void:
	for g: Dictionary in _records(economy.get("signature_gift_items", [])):
		signature_items_by_id[StringName(g["id"])] = g
	var nest: Dictionary = friendship["nest"]
	nest_stages = _sorted_records(nest["stages"], "at_s")
	for st: Dictionary in _records(nest["styles"]):
		nest_styles_by_id[StringName(st["id"])] = st
	for a: Dictionary in _records(nest["anchors"]):
		nest_anchor_by_species[StringName(a["species"])] = a
	for m: Dictionary in _records(mysteries["species"]):
		mystery_species_by_id[StringName(m["species"])] = m
	variants = _records(mysteries["variants"])
	for v: Dictionary in variants:
		variants_by_id[StringName(v["id"])] = v
		variants_by_species[StringName(v["species"])] = v
	sign_anchors = _records(mysteries["anchors"])
	for st: Dictionary in _records(mysteries["sign_types"]):
		sign_types_by_id[StringName(st["id"])] = st
	scenes = _records(scenes_doc["scenes"])
	for sc: Dictionary in scenes:
		scenes_by_id[StringName(sc["id"])] = sc


## Cross-references of the Retention v1 data (the full lint is tools/sim/validate_content.py).
func _check_retention() -> void:
	for s: Dictionary in species:
		var sid := StringName(s["id"])
		for key: String in ["signature_gift", "nest_style", "best_friend", "postcard_heart2", "postcard_heart4",
				"postcard_heart5"]:
			if String(s.get(key, "")) == "":
				errors.append("species %s: missing %s" % [sid, key])
		if not signature_items_by_id.has(StringName(s.get("signature_gift", ""))):
			errors.append("species %s signature gift %s missing" % [sid, s.get("signature_gift", "")])
		if not nest_styles_by_id.has(StringName(s.get("nest_style", ""))):
			errors.append("species %s nest style %s missing" % [sid, s.get("nest_style", "")])
		var bf := StringName(s.get("best_friend", ""))
		if not species_by_id.has(bf) or bf == sid:
			errors.append("species %s best friend %s invalid" % [sid, bf])
		elif StringName((species_by_id[bf] as Dictionary).get("best_friend", "")) != sid:
			errors.append("species %s best friend %s is not symmetric" % [sid, bf])
		if not nest_anchor_by_species.has(sid):
			errors.append("species %s has no nest anchor" % sid)
		if not mystery_species_by_id.has(sid):
			errors.append("species %s has no mysteries.json record" % sid)
	for m: Dictionary in mystery_species_by_id.values():
		if not species_by_id.has(StringName(m["species"])):
			errors.append("mysteries.json: unknown species %s" % m["species"])
		_check_sign_list(String(m["species"]), m["signs"], false)
	for v: Dictionary in variants:
		if not species_by_id.has(StringName(v["species"])):
			errors.append("variant %s: unknown species %s" % [v["id"], v["species"]])
		var cond: Dictionary = v["condition"]
		for r: Dictionary in cond["items"]:
			if not item_kind.has(StringName(r["item"])):
				errors.append("variant %s requires unknown item %s" % [v["id"], r["item"]])
		for p: Variant in cond["arrival_phases"]:
			if not phase_index.has(StringName(p)):
				errors.append("variant %s: unknown phase %s" % [v["id"], p])
		for w: Variant in cond["arrival_weather"]:
			if not weather_by_id.has(StringName(w)):
				errors.append("variant %s: unknown weather %s" % [v["id"], w])
		_check_sign_list(String(v["id"]), v["signs"], true)
	for a: Dictionary in sign_anchors:
		for ty: Variant in a["types"]:
			if not sign_types_by_id.has(StringName(ty)):
				errors.append("sign anchor %s: unknown type %s" % [a["id"], ty])
	for sc: Dictionary in scenes:
		var cond: Dictionary = sc["conditions"]
		for r: Dictionary in _records(cond.get("items", [])):
			if not item_kind.has(StringName(r["item"])):
				errors.append("scene %s requires unknown item %s" % [sc["id"], r["item"]])
		for r: Dictionary in _records(sc["roles"]):
			for p: Variant in r.get("prefer", []):
				if not species_by_id.has(StringName(p)):
					errors.append("scene %s prefers unknown species %s" % [sc["id"], p])


func _check_sign_list(owner: String, signs: Variant, variant: bool) -> void:
	var list: Array = signs if signs is Array else []
	for ty: Variant in list:
		if not sign_types_by_id.has(StringName(ty)):
			errors.append("%s: unknown sign type %s" % [owner, ty])
	if not list.is_empty() and sign_windows(list.size(), variant).size() != list.size():
		errors.append("%s: no sign windows for %d signs" % [owner, list.size()])


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
