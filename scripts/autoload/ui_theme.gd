extends Node
## UiTheme (autoload): builds the UI Theme from the design tokens (ThemeBuilder) and sets it on
## the root window. Rebuilt when Text size (X1), language (Vietnamese +12 % line spacing) or
## Reduce transparency change.
##
## Theme propagation stops at a CanvasLayer (a Control under a CanvasLayer has no Control or
## Window parent), so the root Control of every CanvasLayer (HUD, sheets, overlays) calls
## [method attach] once; attached controls are updated on every rebuild.
##
## Not set through project.godot gui/theme/custom on purpose: the editor loads that theme before
## the first import of a fresh clone has produced the fonts, which logs load errors.
## ui/theme/base_theme.tres is the same build at 100 % for editor previews (assign it to a UI
## scene's root Control while designing); tools/ui/build_theme.gd regenerates it.

signal theme_rebuilt(theme: Theme)

const PERCENT := 100.0

var theme: Theme
var _attached: Array[WeakRef] = []


func _ready() -> void:
	rebuild()
	Settings.changed.connect(_on_setting_changed)


func rebuild() -> void:
	var scale := float(Settings.get_int(Settings.TEXT_SCALE)) / PERCENT
	theme = ThemeBuilder.build(ContentRegistry.palettes(), scale, I18n.is_vietnamese(),
		Settings.get_bool(Settings.REDUCE_TRANSPARENCY))
	get_tree().root.theme = theme
	var alive: Array[WeakRef] = []
	for ref: WeakRef in _attached:
		var c := ref.get_ref() as Control
		if c != null:
			c.theme = theme
			alive.append(ref)
	_attached = alive
	theme_rebuilt.emit(theme)


## Gives [param control] (the root Control under a CanvasLayer) the current theme, now and after
## every rebuild.
func attach(control: Control) -> void:
	control.theme = theme
	_attached.append(weakref(control))


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key in [Settings.TEXT_SCALE, Settings.LANGUAGE, Settings.REDUCE_TRANSPARENCY]:
		rebuild()
