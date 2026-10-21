class_name SafeAreaContainer
extends MarginContainer
## Keeps HUD and dock inside the OS safe area with the floors of Art Bible §2.2 / §2.6 and
## synthesis D3 (notches, gesture bar, rounded corners; Android 15+ is edge-to-edge). Margins are
## in canvas units: the OS rect is scaled by visible-rect / window size (01 §6).

signal margins_changed(margins: Rect2)

## Art Bible §2.2: top inset T = max(safe top, 72 px = 24 dp).
@export var floor_top_px: float = 72.0
## Art Bible §2.2: Z5 gesture zone = max(safe bottom, 127 px).
@export var floor_bottom_px: float = 127.0
## Art Bible §2.2: targets keep >= 16 dp (48 px) from the side edges.
@export var floor_side_px: float = 48.0


func _ready() -> void:
	get_viewport().size_changed.connect(_update)
	_update()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		_update()  # rotation is locked, but cutout/gesture-bar state can change while paused


func _update() -> void:
	var vp := get_viewport()
	var visible_rect := vp.get_visible_rect()
	var safe := Platform.safe_area_canvas(vp)
	var left := maxf(safe.position.x - visible_rect.position.x, floor_side_px)
	var top := maxf(safe.position.y - visible_rect.position.y, floor_top_px)
	var right := maxf(visible_rect.end.x - safe.end.x, floor_side_px)
	var bottom := maxf(visible_rect.end.y - safe.end.y, floor_bottom_px)
	add_theme_constant_override(&"margin_left", roundi(left))
	add_theme_constant_override(&"margin_top", roundi(top))
	add_theme_constant_override(&"margin_right", roundi(right))
	add_theme_constant_override(&"margin_bottom", roundi(bottom))
	margins_changed.emit(Rect2(left, top, right, bottom))
