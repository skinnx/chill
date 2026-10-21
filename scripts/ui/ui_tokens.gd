class_name UiTokens
extends RefCounted
## The UI design tokens in one place (Art Bible §3.5, §9.1-9.2, §10; data/palettes.json ui,
## ui_derived, ui_alpha, icon_accent; data/motion_tokens.json ui, durations_ms). Every UI script
## reads colours, alphas and timings through here, never as literals.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## spots.json frame.px_per_dp (synthesis C2: 1 dp = 3 px at the 1080 design width).
const PX_PER_DP := 3.0
const MS := 0.001
## Art Bible §9.2 elevation levels.
const E0 := 0
const E1 := 1
const E2 := 2
const E3 := 3
## Elevation shape (blur size, y offset) per level; alpha is ui_alpha.shadow_e<n>.
const ELEVATION_SHAPE: Array[Vector2] = [Vector2.ZERO, Vector2(24, 6), Vector2(48, 18), Vector2(72, 24)]

static var _curves: Dictionary = {}


static func color(token: StringName) -> Color:
	var pal := ContentRegistry.palettes()
	for sect: String in ["ui", "ui_derived"]:
		var d: Dictionary = pal.get(sect, {})
		if d.has(String(token)):
			return Color.html(String(d[String(token)]))
	push_error("UiTokens: unknown colour token %s" % token)
	return Color.MAGENTA


static func alpha(token: StringName) -> float:
	var d: Dictionary = ContentRegistry.palettes().get("ui_alpha", {})
	return float(d.get(String(token), 1.0))


static func alpha_section(token: StringName) -> Dictionary:
	var d: Dictionary = ContentRegistry.palettes().get("ui_alpha", {})
	var v: Variant = d.get(String(token), {})
	return v if v is Dictionary else {}


## The accent colour of an icon family (palettes.json icon_accent; primary by default).
static func accent(icon_family: StringName) -> Color:
	var d: Dictionary = ContentRegistry.palettes().get("icon_accent", {})
	return color(StringName(String(d.get(String(icon_family), "primary"))))


## Colour with alpha.
static func tinted(token: StringName, a: float) -> Color:
	var c := color(token)
	c.a = a
	return c


## motion_tokens.json ui block.
static func ui() -> Dictionary:
	var d: Variant = ContentRegistry.motion_tokens().get("ui", {})
	return d if d is Dictionary else {}


## A ui sub-block (sheet_open, counter_tick, tutorial_hint_ring ...).
static func ui_block(key: String) -> Dictionary:
	var d: Variant = ui().get(key, {})
	return d if d is Dictionary else {}


static func ui_float(key: String, fallback: float = 0.0) -> float:
	return float(ui().get(key, fallback))


## durations_ms.<key> in seconds.
static func seconds(key: String) -> float:
	var d: Dictionary = ContentRegistry.motion_tokens().get("durations_ms", {})
	return float(d.get(key, 0.0)) * MS


## Eased progress of a motion token's curve at [param u] in 0..1 (exact bézier, motion_tokens
## curves), for tween_method callbacks where a PropertyTweener's custom interpolator is not
## available.
static func ease(token: StringName, u: float) -> float:
	var curve_name := Motion.curve_of(token)
	var hit: Variant = _curves.get(curve_name)
	if hit == null:
		var curves: Dictionary = ContentRegistry.motion_tokens().get("curves", {})
		var c: Dictionary = curves.get(curve_name, {})
		hit = CubicBezier.from_array(c["bezier"]) if c.has("bezier") else false
		_curves[curve_name] = hit
	if hit is CubicBezier:
		return (hit as CubicBezier).progress(clampf(u, 0.0, 1.0))
	return clampf(u, 0.0, 1.0)


## A StyleBoxFlat that draws only an elevation shadow (Art Bible §9.2; drawn even with a clear fill).
static func shadow_box(radius: float, level: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0, 0, 0, 0)
	b.set_corner_radius_all(roundi(radius))
	b.corner_detail = ThemeBuilder.CORNER_DETAIL_SMALL if radius <= ThemeBuilder.R_M else ThemeBuilder.CORNER_DETAIL_LARGE
	b.anti_aliasing = true
	if level > E0 and level < ELEVATION_SHAPE.size():
		b.shadow_color = tinted(&"ink", alpha(StringName("shadow_e%d" % level)))
		b.shadow_size = roundi(ELEVATION_SHAPE[level].x)
		b.shadow_offset = Vector2(0.0, ELEVATION_SHAPE[level].y)
	return b


## Opaque rounded fill with an optional elevation (cards, plates, buttons).
static func fill_box(fill: Color, radius: float, level: int = E0) -> StyleBoxFlat:
	var b := shadow_box(radius, level)
	b.bg_color = fill
	return b


## The contrast ratio of two colours (WCAG 2.2 relative luminance), for tests and asserts.
static func contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _lum(c: Color) -> float:
	var lin := c.srgb_to_linear()
	return 0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b
