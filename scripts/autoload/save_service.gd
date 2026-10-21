extends Node
## SaveService (autoload #4): where and how the world is persisted (synthesis D12).
##
## The format and crash safety live in [SaveStore] / [AtomicFile]; this node adds the policy
## that is not tied to app lifecycle: a provider callable (registered by Game), the 30 s autosave
## timer, and debounced "save soon" requests after player actions. Game calls [method save_now] on
## FOCUS_OUT, PAUSED and quit, because it must settle the world first (docs/ARCHITECTURE.md §6).

signal saved(ok: bool, reason: StringName)
signal loaded(source: StringName)

const SAVE_PATH := "user://save.json"
const AUTOSAVE_INTERVAL_S := 30.0
## Player actions coalesce into one write this long after the last one.
const DEBOUNCE_S := 2.0

var store: SaveStore
var last_save_unix: float = 0.0
var last_error: Error = OK
var enabled: bool = true

## Callable() -> Dictionary {"world": Dictionary, "saved_at_unix": float}
var _provider: Callable = Callable()
var _autosave_left: float = AUTOSAVE_INTERVAL_S
var _debounce_left: float = -1.0


func _ready() -> void:
	store = SaveStore.new(SAVE_PATH, func(w: Dictionary) -> Dictionary: return WorldState.from_dict(w).to_dict())
	for a: String in OS.get_cmdline_user_args():
		if a == "--no-save":
			enabled = false
		elif a == "--fresh":
			AtomicFile.remove_all(SAVE_PATH)


func _process(delta: float) -> void:
	if not _provider.is_valid():
		return
	_autosave_left -= delta
	if _debounce_left >= 0.0:
		_debounce_left -= delta
		if _debounce_left < 0.0:
			save_now(&"action")
	if _autosave_left <= 0.0:
		save_now(&"autosave")


func register_provider(provider: Callable) -> void:
	_provider = provider


func has_save() -> bool:
	return store.exists()


## {ok, source, world, saved_at_unix, ...} - see [method SaveStore.read].
func load_world() -> Dictionary:
	var res := store.read()
	for msg: String in res["tried"]:
		push_warning("SaveService: skipped " + msg)
	if res["ok"]:
		loaded.emit(res["source"])
	return res


## Writes now. Returns true on success. Never throws away the previous good file.
func save_now(reason: StringName = &"manual") -> bool:
	_autosave_left = AUTOSAVE_INTERVAL_S
	_debounce_left = -1.0
	if not enabled or not _provider.is_valid():
		return false
	var payload: Dictionary = _provider.call()
	var world: Dictionary = payload["world"]
	var saved_at: float = payload["saved_at_unix"]
	var version: String = ProjectSettings.get_setting("application/config/version", "0")
	var err := store.write(world, saved_at, version)
	last_error = err
	var ok := err == OK
	if ok:
		last_save_unix = saved_at
	else:
		push_warning("SaveService: save failed (%s)" % error_string(err))
	saved.emit(ok, reason)
	return ok


## Moves unreadable save files aside (never deletes them) before a fresh start, so a damaged
## save can still be recovered by hand: save.json -> save.json.broken-<unix>.
func quarantine() -> void:
	var stamp := floori(Time.get_unix_time_from_system())
	for p: String in AtomicFile.candidates(SAVE_PATH):
		if FileAccess.file_exists(p):
			DirAccess.rename_absolute(p, "%s.broken-%d" % [p, stamp])


## Coalesces bursts of player actions into one write.
func request_save() -> void:
	_debounce_left = DEBOUNCE_S
