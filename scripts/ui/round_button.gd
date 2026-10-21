class_name RoundButton
extends BaseButton
## A round plate with a duotone icon (Art Bible §9.4: dock plates, the sheet close button, the
## text-size stepper, the friend-card pencil). The control's rect is the HIT area; the plate is
## drawn centred in it at [member plate_px] (so a 56 dp plate can carry a 76 dp hit). Plates are
## surface_hi on e1 (never glass on glass). Active (its sheet open): primary_tint plate, a 3 dp
## primary ring and the icon accent at 100 %. Asleep (onboarding): plate and icon at 50 %.
## Optional label (Caption 36, ink) inside the plate under the icon.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## The plate's look changed (state, size): an owner that draws the plate redraws.
signal appearance_changed

const RING_DP := 3.0
const ASLEEP_ALPHA := 0.5
## Gap between the icon and the in-plate label, px.
const LABEL_GAP := 2.0
## Label colour when active (dock tab: the selected label takes primary_deep, 7.0:1 on
## primary_tint; round 4: primary_pressed measured 3.7:1 at 200 % vi text in QA r3 stills).
const ACTIVE_LABEL_TOKEN := &"primary_deep"

var plate_px: float = 168.0:
	set(v):
		plate_px = v
		_relayout()
var icon_name: StringName = &"":
	set(v):
		icon_name = v
		_refresh_icon()
var icon_px: float = 72.0:
	set(v):
		icon_px = v
		_refresh_icon()
var fill_token: StringName = &"surface_hi"
var elevation: int = UiTokens.E1
var active: bool = false:
	set(v):
		if active != v:
			active = v
			_refresh_icon()
			_refresh_label_color()
			_changed()
var asleep: bool = false:
	set(v):
		asleep = v
		_refresh_alpha()
		_changed()
## Plate centre inside the rect (default: the rect centre).
var plate_center: Vector2 = Vector2(-1, -1):
	set(v):
		plate_center = v
		_relayout()

## QA stills: draw the touch-down state without a touch.
var force_pressed: bool = false:
	set(v):
		force_pressed = v
		_changed()
## false: an owner draws the plate (the dock draws its four plates in one batch).
var draw_plate: bool = true
## Optional icon textures (an atlas region), normal and active: icons from one atlas batch.
var icon_textures: Array[Texture2D] = []
## Label box width (px; below 0 = the plate width) and the icon-to-label gap.
var label_w: float = -1.0
var label_gap: float = LABEL_GAP
## Round 5 (large text, dock grid): the label sits to the right of the icon, the pair centred.
var inline: bool = false:
	set(v):
		inline = v
		_relayout()
## Gap between the icon and an inline label, px.
var inline_gap: float = 18.0
## The active label takes ACTIVE_LABEL_TOKEN (dock tabs).
var tint_active_label: bool = false
## Night chrome blend (dock tabs): the label lerps toward night_ink.
var night_k: float = 0.0:
	set(v):
		night_k = v
		_refresh_label_color()
var label: Label
## The icon's z_index (the dock lifts its icons to the HUD icon layer so they batch).
var icon_z: int = 0:
	set(v):
		icon_z = v
		if _icon != null:
			_icon.z_index = v
var _icon: TextureRect
var _box: StyleBoxFlat
## Round 5: the plate is a batched UiSurface (one draw for every surface of a sheet) whenever this
## button draws its own plate.
var _plate: UiSurface


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_icon)
	resized.connect(_relayout)
	button_down.connect(_changed)
	button_up.connect(_changed)


func _ready() -> void:
	if draw_plate and _plate == null:
		_plate = UiSurface.new()
		_plate.name = "Plate"
		add_child(_plate, false, Node.INTERNAL_MODE_FRONT)
		set_meta(UiSurface.META_OWNER, _plate)
	_refresh_icon()
	_relayout()


## Adds the in-plate caption under the icon.
func set_label(text: String) -> void:
	if label == null:
		label = Label.new()
		label.theme_type_variation = &"CaptionLabel"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.clip_text = false
		add_child(label)
	label.text = text
	_refresh_alpha()
	_refresh_label_color()
	_relayout()


## Touch-down look (also forced by QA stills: --qa-press).
func looks_pressed() -> bool:
	var m := get_draw_mode()
	return force_pressed or m == DRAW_PRESSED or m == DRAW_HOVER_PRESSED


func _changed() -> void:
	queue_redraw()
	_sync_plate()
	appearance_changed.emit()


func _sync_plate() -> void:
	if _plate == null:
		return
	var c := center()
	var r := plate_px * 0.5
	_plate.position = c - Vector2(r, r)
	_plate.size = Vector2(r, r) * 2.0
	_plate.radius = UiSurface.PILL
	var fill := UiTokens.sc(&"primary_tint") if active or looks_pressed() else UiTokens.sc(fill_token)
	if asleep:
		fill.a *= ASLEEP_ALPHA
	_plate.color = fill
	_plate.elevation = UiTokens.E0 if asleep else elevation


func center() -> Vector2:
	return size * 0.5 if plate_center.x < 0.0 else plate_center


func _draw() -> void:
	if draw_plate and _plate == null:
		draw_plate_at(self, center(), 1.0)
	elif draw_plate and active:
		var w := RING_DP * UiTokens.PX_PER_DP
		draw_arc(center(), plate_px * 0.5 - w * 0.5, 0.0, TAU, 96, UiTokens.sc(&"primary"), w, true)


## Draws this button's plate on [param canvas] at [param c] (shared by the dock's plate layer).
func draw_plate_at(canvas: CanvasItem, c: Vector2, k: float) -> void:
	var r := plate_px * 0.5 * k
	# Pressed (touch-down, same frame): the plate takes primary_tint, a visible state on a white
	# plate where a +6 L* lift cannot show (Art Bible §10.3 "instant" tint).
	var fill := UiTokens.color(&"primary_tint") if active or looks_pressed() else UiTokens.color(fill_token)
	if asleep:
		fill.a *= ASLEEP_ALPHA
	_box = UiTokens.fill_box(fill, r, UiTokens.E0 if asleep else elevation)
	canvas.draw_style_box(_box, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0))
	if active:
		var w := RING_DP * UiTokens.PX_PER_DP * k
		canvas.draw_arc(c, r - w * 0.5, 0.0, TAU, 96, UiTokens.color(&"primary"), w, true)


func _refresh_icon() -> void:
	if _icon == null or icon_name == &"":
		return
	if icon_textures.size() == 2:
		_icon.texture = icon_textures[1] if active else icon_textures[0]
	elif draw_plate and not active:
		_icon.texture = Icons.ui(icon_name, icon_px)
	else:
		_icon.texture = Icons.texture(icon_name, icon_px, active)
	_relayout()


func _refresh_alpha() -> void:
	if _icon != null:
		_icon.modulate.a = ASLEEP_ALPHA if asleep else 1.0
	if label != null:
		label.modulate.a = ASLEEP_ALPHA if asleep else 1.0


func _refresh_label_color() -> void:
	if label == null:
		return
	var night := UiTokens.color(&"night_ink")
	if active and tint_active_label:
		label.add_theme_color_override(&"font_color", UiTokens.color(ACTIVE_LABEL_TOKEN).lerp(night, night_k))
	elif night_k > 0.0:
		label.add_theme_color_override(&"font_color", UiTokens.color(&"ink").lerp(night, night_k))
	else:
		label.remove_theme_color_override(&"font_color")


func _relayout() -> void:
	if _icon == null:
		return
	var c := center()
	if inline and label != null:
		var lsz := label.get_combined_minimum_size()
		var lw := minf(lsz.x, (plate_px if label_w < 0.0 else label_w) - icon_px - inline_gap)
		var x0 := c.x - (icon_px + inline_gap + lw) * 0.5
		_icon.size = Vector2(icon_px, icon_px)
		_icon.position = Vector2(x0, c.y - icon_px * 0.5)
		label.size = Vector2(lw, lsz.y)
		label.position = Vector2(x0 + icon_px + inline_gap, c.y - lsz.y * 0.5)
		pivot_offset = c
		_changed()
		return
	var stack_h := icon_px
	var lh := 0.0
	if label != null:
		lh = label.get_combined_minimum_size().y
		stack_h += label_gap + lh
	var top := c.y - stack_h * 0.5
	_icon.size = Vector2(icon_px, icon_px)
	_icon.position = Vector2(c.x - icon_px * 0.5, top)
	if label != null:
		var w := plate_px if label_w < 0.0 else label_w
		label.size = Vector2(w, lh)
		label.position = Vector2(c.x - w * 0.5, top + icon_px + label_gap)
	# The ripple and the press scale follow the plate (a 56 dp plate in a 76 dp hit), unless an
	# owner set its own shape (the dock's tab capsule).
	if not has_meta(&"ripple_owner_shape"):
		var r := plate_px * 0.5
		set_meta(PressFeedback.META_RIPPLE_RECT, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0))
		set_meta(PressFeedback.META_RIPPLE_RADIUS, r)
	pivot_offset = c
	_changed()


## The icon's centre in local px (badges and rings sit around it).
func icon_center() -> Vector2:
	return _icon.position + _icon.size * 0.5 if _icon != null else center()
