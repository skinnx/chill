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

const RING_DP := 3.0
const ASLEEP_ALPHA := 0.5
## Gap between the icon and the in-plate label, px.
const LABEL_GAP := 2.0

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
			queue_redraw()
var asleep: bool = false:
	set(v):
		asleep = v
		_refresh_alpha()
		queue_redraw()
## Plate centre inside the rect (default: the rect centre).
var plate_center: Vector2 = Vector2(-1, -1):
	set(v):
		plate_center = v
		_relayout()

var label: Label
var _icon: TextureRect
var _box: StyleBoxFlat


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_icon)
	resized.connect(_relayout)


func _ready() -> void:
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
	_relayout()


func center() -> Vector2:
	return size * 0.5 if plate_center.x < 0.0 else plate_center


func _draw() -> void:
	var c := center()
	var r := plate_px * 0.5
	var fill := UiTokens.color(&"primary_tint") if active else UiTokens.color(fill_token)
	if asleep:
		fill.a *= ASLEEP_ALPHA
	_box = UiTokens.fill_box(fill, r, UiTokens.E0 if asleep else elevation)
	draw_style_box(_box, Rect2(c - Vector2(r, r), Vector2(plate_px, plate_px)))
	if active:
		var w := RING_DP * UiTokens.PX_PER_DP
		draw_arc(c, r - w * 0.5, 0.0, TAU, 96, UiTokens.color(&"primary"), w, true)


func _refresh_icon() -> void:
	if _icon == null or icon_name == &"":
		return
	_icon.texture = Icons.texture(icon_name, icon_px, active)
	_relayout()


func _refresh_alpha() -> void:
	if _icon != null:
		_icon.modulate.a = ASLEEP_ALPHA if asleep else 1.0


func _relayout() -> void:
	if _icon == null:
		return
	var c := center()
	var stack_h := icon_px
	var lh := 0.0
	if label != null:
		lh = label.get_combined_minimum_size().y
		stack_h += LABEL_GAP + lh
	var top := c.y - stack_h * 0.5
	_icon.size = Vector2(icon_px, icon_px)
	_icon.position = Vector2(c.x - icon_px * 0.5, top)
	if label != null:
		var w := plate_px
		label.size = Vector2(w, lh)
		label.position = Vector2(c.x - w * 0.5, top + icon_px + LABEL_GAP)
	pivot_offset = c
	queue_redraw()
