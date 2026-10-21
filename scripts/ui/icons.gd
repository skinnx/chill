class_name Icons
extends RefCounted
## Duotone icons (Art Bible §9.3; art/icons/*.svg from tools/ui/make_icons.py, imported as
## DPITexture). Each icon is re-rasterised once per drawn size from its SVG source, so it is crisp
## at every size and at every canvas oversampling (no bilinear blow-up of a 72 px bitmap). The
## active variant (dock "Active" state, §9.4) lifts the accent layer from 0.40 to 1.0.

const DIR := "res://art/icons/"
## Icon canvas in px (24 dp).
const CANVAS_PX := 72.0
## The accent layer's literal opacity in the generated SVG (ui_alpha.icon_duotone_secondary).
const ACCENT_ATTR := "fill-opacity=\"0.4\""
const ACCENT_ACTIVE := "fill-opacity=\"1\""

static var _cache: Dictionary = {}


## [param name] is the file stem ("garden", "dew" ...); [param px] the drawn size.
static func texture(name: StringName, px: float, active: bool = false) -> Texture2D:
	var key := "%s@%d%s" % [name, roundi(px), "+" if active else ""]
	var hit: Variant = _cache.get(key)
	if hit is Texture2D:
		return hit
	var base := load(DIR + String(name) + ".svg") as DPITexture
	if base == null:
		push_error("Icons: missing %s.svg" % name)
		return null
	var src := base.get_source()
	if active:
		src = src.replace(ACCENT_ATTR, ACCENT_ACTIVE)
	var tex := DPITexture.create_from_string(src, maxf(px, 1.0) / CANVAS_PX)
	_cache[key] = tex
	return tex


static func exists(name: StringName) -> bool:
	return ResourceLoader.exists(DIR + String(name) + ".svg")


## A TextureRect showing [param name] at [param px] (mouse-transparent).
static func rect(name: StringName, px: float, active: bool = false) -> TextureRect:
	var r := TextureRect.new()
	r.texture = texture(name, px, active)
	r.custom_minimum_size = Vector2(px, px)
	r.size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
