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
const SCHEMA := 1
const SOURCE_MAIN := &"main"
const SOURCE_TMP := &"tmp"
const SOURCE_BACKUP := &"backup"
const SOURCE_NONE := &"none"

## schema N -> Callable(world: Dictionary) -> Dictionary returning schema N + 1 data.
const MIGRATIONS := {}

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
			if not MIGRATIONS.has(schema):
				out["error"] = "no migration from schema %d" % schema
				return out
			w = (MIGRATIONS[schema] as Callable).call(w)
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


static func checksum(world: Dictionary) -> String:
	return JSON.stringify(world, "", true, true).sha256_text()


func _normalize(w: Dictionary) -> Dictionary:
	if normalizer.is_valid():
		return normalizer.call(w)
	return w
