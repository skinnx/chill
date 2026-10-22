class_name SaveStore
extends RefCounted
## Versioned JSON save file (synthesis D12; docs/ARCHITECTURE.md §6).
##
## File = one JSON object:
##   {"format": "mossling-meadow-save", "schema": N, "app_version": "...", "saved_at_unix": f,
##    "sha256": "<hex of the canonical world encoding>", "world": {...WorldState.to_dict()...}}
## Numbers are written with full precision (17 significant digits). Godot 4.7.2's number parser
## is not correctly rounded (about 12 % of such doubles come back 1 ulp off, measured), so the
## checksum is computed over the PARSED-BACK encoding at save time: the same text always parses
## to the same doubles, which makes load-time verification exact. A reload can therefore differ
## from the in-memory state by <= 1 ulp per float, which no game rule can observe.
## 64-bit integers (seeds, RNG state) are decimal strings inside the world payload.
## JSON.from_native was evaluated and rejected: in 4.7.2 it stores floats as "f:<15 digits>"
## strings, which loses far more precision.
##
## Reading tries <path>, <path>.tmp, <path>.bak in that order and returns the first file that
## parses, has a supported schema and a matching checksum. Older schemas are migrated forward.

const FORMAT := "mossling-meadow-save"
## Bump when WorldState.to_dict() changes shape; add a migration from the previous schema.
## 1: MVP. 2: Retention v1 (GDD §13.6). 3: Active Play v1 (GDD §14.9). 4: tips_seen (Active Play
## polish: one-time tips survive reloads). Additive fields only.
const SCHEMA := 4
const SOURCE_MAIN := &"main"
const SOURCE_TMP := &"tmp"
const SOURCE_BACKUP := &"backup"
const SOURCE_NONE := &"none"

## Schemas that have a forward migration to N + 1 ([method migrate]).
const MIGRATABLE: Array[int] = [1, 2, 3]
## Retention v1 fields a schema-1 world gains, all empty (GDD §13.6). Kept literal here, not read
## from WorldState, so this migration keeps meaning "1 -> 2" after later schemas change the state.
const RETENTION_V1_DEFAULTS := {
	"retention_v": 0, "visit_aff_t": {}, "hearts_seen": {}, "nests": {}, "postcards_waiting": [],
	"mysteries": {}, "signs": [], "clues": {}, "variants_met": {}, "cousin_visits": {}, "scene_returns": 0,
	"scenes_seen": {}, "scene_cast": {}, "pending_scene": {}, "memories": [], "keepsakes": {},
	"signature_gifts": {}, "last_bg_t": -1.0, "open_count": 0,
}
## Active Play v1 fields a schema-2 world gains (GDD §14.9), all empty and active_v 0, so WorldSim
## runs ActiveRules.migrate_v1 (décor anchors -> free positions, tea unlock) once at load. Literal
## for the same reason as above.
const ACTIVE_V1_DEFAULTS := {
	"active_v": 0, "wishes": [], "wish_checks": 0, "wish_fg_s": 0.0, "wish_last_t": -1.0e18, "wish_friend_t": {},
	"wish_visit_count": {}, "wish_last_id": {}, "wish_aff_t": {}, "wish_stamps": {}, "wishes_granted": 0,
	"wish_tutorial_done": false, "wish_list_seen_t": 0.0, "tea_unlocked": false, "petal_from_t": {}, "pantry": {},
	"pot": {"petals": [], "drops": 0, "stir_deg": 0.0}, "tray": [], "recipes_found": {}, "tea_prefs_seen": {},
	"tea_aff_t": {}, "teaware_owned": [], "teaware_set": {}, "cups_offered": 0, "tea_flags": {}, "decor_layout": [],
}
## Schema 4: the one-time tips already shown (tip id -> true), empty for a schema-3 world. Literal
## for the same reason as above.
const TIPS_DEFAULTS := {"tips_seen": {}}

var path: String
## Optional Callable(world: Dictionary) -> Dictionary: re-normalises parsed data (e.g.
## WorldState.from_dict(d).to_dict()) so the checksum compares typed, canonical encodings.
var normalizer: Callable = Callable()


func _init(p_path: String, p_normalizer: Callable = Callable()) -> void:
	path = p_path
	normalizer = p_normalizer


func exists() -> bool:
	for p: String in AtomicFile.candidates(path):
		if FileAccess.file_exists(p):
			return true
	return false


## Serialises and writes atomically. Returns OK or the failing Error.
func write(world: Dictionary, saved_at_unix: float, app_version: String) -> Error:
	var text := encode(world, saved_at_unix, app_version)
	return AtomicFile.write_text(path, text, true, func(back: String) -> bool: return decode(back)["ok"])


## {ok, source, world, saved_at_unix, schema, app_version, error, tried}
func read() -> Dictionary:
	var tried: Array[String] = []
	var sources: Array[StringName] = [SOURCE_MAIN, SOURCE_TMP, SOURCE_BACKUP]
	var files := AtomicFile.candidates(path)
	for i in files.size():
		if not FileAccess.file_exists(files[i]):
			continue
		var res := decode(AtomicFile.read_text(files[i]))
		if res["ok"]:
			res["source"] = sources[i]
			res["tried"] = tried
			return res
		tried.append("%s: %s" % [files[i].get_file(), res["error"]])
	return {"ok": false, "source": SOURCE_NONE, "world": {}, "saved_at_unix": 0.0, "schema": 0,
		"app_version": "", "error": "no readable save", "tried": tried}


func encode(world: Dictionary, saved_at_unix: float, app_version: String) -> String:
	var reparsed: Variant = JSON.parse_string(JSON.stringify(world, "", true, true))
	var as_loaded := world
	if reparsed is Dictionary:
		var parsed_world: Dictionary = reparsed
		as_loaded = _normalize(parsed_world)
	var doc := {
		"format": FORMAT,
		"schema": SCHEMA,
		"app_version": app_version,
		"saved_at_unix": saved_at_unix,
		"sha256": checksum(as_loaded),
		"world": world,
	}
	return JSON.stringify(doc, "\t", true, true)


func decode(text: String) -> Dictionary:
	var out := {"ok": false, "world": {}, "saved_at_unix": 0.0, "schema": 0, "app_version": "", "error": ""}
	if text.is_empty():
		out["error"] = "empty"
		return out
	var json := JSON.new()
	if json.parse(text) != OK:
		out["error"] = "parse error line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return out
	var doc: Variant = json.data
	if not doc is Dictionary or (doc as Dictionary).get("format", "") != FORMAT:
		out["error"] = "not a save file"
		return out
	var d: Dictionary = doc
	var schema: int = d.get("schema", 0)
	var world: Variant = d.get("world", null)
	if not world is Dictionary:
		out["error"] = "missing world"
		return out
	if schema < 1 or schema > SCHEMA:
		out["error"] = "unsupported schema %d" % schema
		return out
	var w: Dictionary = world
	if schema == SCHEMA:
		# Checksum only for the current schema: older files cannot be re-encoded by this code.
		var normal := _normalize(w)
		var stored_sum: String = d.get("sha256", "")
		if checksum(normal) != stored_sum:
			out["error"] = "checksum mismatch"
			return out
		w = normal
	else:
		while schema < SCHEMA:
			if not MIGRATABLE.has(schema):
				out["error"] = "no migration from schema %d" % schema
				return out
			w = migrate(schema, w)
			schema += 1
		w = _normalize(w)
	out["ok"] = true
	out["world"] = w
	out["schema"] = schema
	var saved_at: float = d.get("saved_at_unix", 0.0)
	var version: String = d.get("app_version", "")
	out["saved_at_unix"] = saved_at
	out["app_version"] = version
	return out


## Forward migration of a world payload from [param from_schema] to from_schema + 1. Only adds
## keys (never removes or lowers a value, G1); unknown schemas return the data unchanged.
static func migrate(from_schema: int, world: Dictionary) -> Dictionary:
	var w := world.duplicate(true)
	match from_schema:
		1:
			# Retention v1 (GDD §13.6): every new field empty and retention_v 0, so WorldSim runs
			# the content-aware steps (hearts_seen, nests, keepsakes, earned ♥4/♥5 postcards,
			# mysteries) once at load. Basket entries gain signature = false via WorldState.
			_add_defaults(w, RETENTION_V1_DEFAULTS)
		2:
			# Active Play v1 (GDD §14.9): every new field empty and active_v 0; the content-aware
			# step (décor anchors -> decor_layout, tea_unlocked) runs in WorldSim at load.
			_add_defaults(w, ACTIVE_V1_DEFAULTS)
		3:
			# Active Play polish: tips_seen starts empty, so a returning player sees each one-time
			# tip once (the checksum of a schema-3 file is over the state without the field).
			_add_defaults(w, TIPS_DEFAULTS)
	return w


## Adds each missing key of [param defaults] (deep copies); never overwrites an existing key.
static func _add_defaults(w: Dictionary, defaults: Dictionary) -> void:
	for key: String in defaults:
		if not w.has(key):
			var def: Variant = defaults[key]
			if def is Dictionary:
				w[key] = (def as Dictionary).duplicate(true)
			elif def is Array:
				w[key] = (def as Array).duplicate(true)
			else:
				w[key] = def


static func checksum(world: Dictionary) -> String:
	return JSON.stringify(world, "", true, true).sha256_text()


func _normalize(w: Dictionary) -> Dictionary:
	if normalizer.is_valid():
		return normalizer.call(w)
	return w
