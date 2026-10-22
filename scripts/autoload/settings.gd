extends Node
## Settings (autoload #2): the X1 accessibility and comfort settings (GDD §7.6), persisted in
## user://settings.cfg (ConfigFile text, written atomically). Settings is a validated store only;
## each consumer applies its own setting by listening to [signal changed]:
##   Motion/Clock <- reduce_motion · UI theme <- text_scale, reduce_transparency, left_handed
##   AudioDirector <- music, volume_*, mono, captions · Haptics <- haptics · Locale <- language
##   FrameGovernor/Game <- auto_hide_ui, keep_awake

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

signal changed(key: StringName, value: Variant)

const PATH := "user://settings.cfg"
const SECTION := "settings"
const SCHEMA := 1

const REDUCE_MOTION := &"reduce_motion"
const REDUCE_TRANSPARENCY := &"reduce_transparency"
const TEXT_SCALE := &"text_scale"
const AUTO_HIDE_UI := &"auto_hide_ui"
const KEEP_AWAKE := &"keep_awake"
const MUSIC := &"music"
const VOLUME_MUSIC := &"volume_music"
const VOLUME_AMBIENCE := &"volume_ambience"
const VOLUME_EFFECTS := &"volume_effects"
const MONO := &"mono"
const CAPTIONS := &"captions"
const HAPTICS := &"haptics"
const LEFT_HANDED := &"left_handed"
const LANGUAGE := &"language"
## Active F2 Tea (ACTIVE_TEA §4): one Brew tap instead of stir and pour. Until the player sets it,
## it follows Reduce Motion (TeaSheet.simple_brewing).
const SIMPLE_BREWING := &"simple_brewing"

const TEXT_SCALES: Array[int] = [100, 115, 130, 150, 200]
const MUSIC_MODES: Array[String] = ["on", "ambience", "off"]
const HAPTIC_MODES: Array[String] = ["off", "subtle", "full"]
const LANGUAGES: Array[String] = ["auto", "en", "vi"]
const VOLUME_MIN := 0
const VOLUME_MAX := 100
const VOLUME_STEP := 10

## Defaults (GDD §7.6, bold values). reduce_motion and text_scale follow the OS until the player
## changes them (see [method _os_default]).
const DEFAULTS := {
	REDUCE_MOTION: false,
	REDUCE_TRANSPARENCY: false,
	TEXT_SCALE: 100,
	AUTO_HIDE_UI: true,
	KEEP_AWAKE: false,
	MUSIC: "on",
	VOLUME_MUSIC: 80,
	VOLUME_AMBIENCE: 80,
	VOLUME_EFFECTS: 80,
	MONO: false,
	CAPTIONS: false,
	HAPTICS: "subtle",
	LEFT_HANDED: false,
	LANGUAGE: "auto",
	SIMPLE_BREWING: false,
}
## Keys whose default is read from the OS when the player has not set them.
const OS_DEFAULT_KEYS: Array[StringName] = [REDUCE_MOTION, TEXT_SCALE]

## Set to false by tests to keep everything in memory.
var persist: bool = true
var _values: Dictionary = {}
## Keys the player set explicitly (others follow defaults / the OS).
var _explicit: Dictionary = {}
## OS-derived defaults, read once per launch/resume (native bridges are not free).
var _os_cache: Dictionary = {}


func _ready() -> void:
	refresh_os_defaults()
	load_settings()
	I18n.apply(String(get_value(LANGUAGE)))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		var before := {}
		for key: StringName in OS_DEFAULT_KEYS:
			before[key] = get_value(key)
		refresh_os_defaults()
		for key: StringName in OS_DEFAULT_KEYS:
			if get_value(key) != before[key]:
				changed.emit(key, get_value(key))


## Re-reads the OS preferences that seed defaults (reduce motion, font scale).
func refresh_os_defaults() -> void:
	_os_cache.clear()
	var rm := Platform.os_reduce_motion()
	if rm != Platform.UNKNOWN:
		_os_cache[REDUCE_MOTION] = rm == 1
	var fs := Platform.os_font_scale()
	if fs > 0.0:
		_os_cache[TEXT_SCALE] = validate(TEXT_SCALE, roundi(fs * 100.0))


func get_value(key: StringName) -> Variant:
	if _values.has(key):
		return _values[key]
	return _os_default(key)


func get_bool(key: StringName) -> bool:
	return bool(get_value(key))


func get_int(key: StringName) -> int:
	return int(get_value(key))


func get_string(key: StringName) -> String:
	return String(get_value(key))


## Validates, stores, persists and announces a change. Invalid values are coerced to the nearest
## valid one (never an error dialog). Returns the stored value.
func set_value(key: StringName, value: Variant) -> Variant:
	if not DEFAULTS.has(key):
		push_warning("Settings: unknown key %s" % key)
		return null
	var v: Variant = validate(key, value)
	var old: Variant = get_value(key)
	_values[key] = v
	_explicit[key] = true
	if key == LANGUAGE:
		I18n.apply(String(v))
	if persist:
		save_settings()
	if v != old:
		changed.emit(key, v)
	return v


func is_explicit(key: StringName) -> bool:
	return _explicit.has(key)


## Coerces [param value] into the valid set for [param key].
static func validate(key: StringName, value: Variant) -> Variant:
	var def: Variant = DEFAULTS[key]
	match key:
		TEXT_SCALE:
			var want := int(value)
			var best := TEXT_SCALES[0]
			for s: int in TEXT_SCALES:
				if absi(s - want) < absi(best - want):
					best = s
			return best
		MUSIC:
			return String(value) if MUSIC_MODES.has(String(value)) else def
		HAPTICS:
			return String(value) if HAPTIC_MODES.has(String(value)) else def
		LANGUAGE:
			return String(value) if LANGUAGES.has(String(value)) else def
		VOLUME_MUSIC, VOLUME_AMBIENCE, VOLUME_EFFECTS:
			var vol := clampi(int(value), VOLUME_MIN, VOLUME_MAX)
			return roundi(float(vol) / VOLUME_STEP) * VOLUME_STEP
	if typeof(def) == TYPE_BOOL:
		return bool(value)
	return value


func load_settings() -> void:
	_values.clear()
	_explicit.clear()
	if not persist:
		return
	var text := AtomicFile.read_text(PATH)
	if text.is_empty():
		text = AtomicFile.read_text(PATH + AtomicFile.BAK_SUFFIX)
	if text.is_empty():
		return
	var cfg := ConfigFile.new()
	if cfg.parse(text) != OK:
		push_warning("Settings: unreadable settings file, using defaults")
		return
	for key: StringName in DEFAULTS:
		if cfg.has_section_key(SECTION, String(key)):
			_values[key] = validate(key, cfg.get_value(SECTION, String(key)))
			_explicit[key] = true


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "schema", SCHEMA)
	for key: StringName in _values:
		cfg.set_value(SECTION, String(key), _values[key])
	var err := AtomicFile.write_text(PATH, cfg.encode_to_text())
	if err != OK:
		push_warning("Settings: could not save (%s)" % error_string(err))


## Restores defaults in memory (tests, QA). Does not touch the file unless persist is on.
func reset_to_defaults() -> void:
	var keys := _values.keys()
	_values.clear()
	_explicit.clear()
	if persist:
		save_settings()
	for key: StringName in keys:
		changed.emit(key, get_value(key))


func _os_default(key: StringName) -> Variant:
	if key == SIMPLE_BREWING:
		# Simple brewing follows Reduce Motion until the player sets it (ACTIVE_TEA §4)
		return get_value(REDUCE_MOTION)
	return _os_cache.get(key, DEFAULTS[key])
