extends Node
## ContentRegistry (autoload #1): loads every res://data/*.json once at startup and shares the
## read-only [GameContent] view (docs/ARCHITECTURE.md §3-4). Everything numeric in the game reads
## from here; nothing else opens data files.

## Emitted after a successful (re)load. Debug builds can call [method reload] after editing data.
signal content_loaded(content: GameContent)

var content: GameContent


func _ready() -> void:
	reload()


func reload() -> void:
	content = GameContent.load_from_dir()
	for e: String in content.errors:
		push_error("ContentRegistry: " + e)
	if content.is_valid():
		content_loaded.emit(content)


func is_valid() -> bool:
	return content != null and content.is_valid()


func economy() -> Dictionary:
	return content.economy


func motion_tokens() -> Dictionary:
	return content.motion


func palettes() -> Dictionary:
	return content.palettes


func audio_manifest() -> Dictionary:
	return content.audio_manifest
