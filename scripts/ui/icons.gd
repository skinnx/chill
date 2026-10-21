class_name Icons
extends RefCounted
## Duotone icons (Art Bible §9.3; art/icons/*.svg from tools/ui/make_icons.py, imported as
## DPITexture). Each icon is re-rasterised once per drawn size from its SVG source, so it is crisp
## at every size and at every canvas oversampling (no bilinear blow-up of a 72 px bitmap). The
## active variant (dock "Active" state, §9.4) lifts the accent layer from 0.40 to 1.0.

# The atlas entries are untyped [name, px, active] arrays; each element is converted explicitly
# where it is read (docs/ARCHITECTURE.md §10 data-boundary rule).
@warning_ignore_start("unsafe_call_argument")

const DIR := "res://art/icons/"
## Icon canvas in px (24 dp).
const CANVAS_PX := 72.0
## The accent layer's literal opacity in the generated SVG (ui_alpha.icon_duotone_secondary).
const ACCENT_ATTR := "fill-opacity=\"0.4\""
const ACCENT_ACTIVE := "fill-opacity=\"1\""
## px between atlas cells (no bleeding under bilinear filtering).
const ATLAS_GAP := 4.0

## [name, px, active] of every HUD icon (TopBarView ICON_PX 72 / badge 36, DockView 84, sparkle 30).
const HUD_ATLAS: Array = [
	[&"dew", 72.0, false], [&"watch", 72.0, false], [&"watch_closed", 72.0, false],
	[&"dawn", 72.0, false], [&"sun", 72.0, false], [&"golden", 72.0, false], [&"dusk", 72.0, false],
	[&"moon", 72.0, false], [&"breeze", 36.0, false], [&"rain", 36.0, false],
	[&"settings", 84.0, false], [&"settings", 84.0, true], [&"garden", 84.0, false], [&"garden", 84.0, true],
	[&"basket", 84.0, false], [&"basket", 84.0, true], [&"album", 84.0, false], [&"album", 84.0, true],
	[&"sparkle", 30.0, false],
]

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


## Drops every cached texture (the HUD calls this when it leaves the tree, so no texture RID
## outlives the scene at exit).
static func clear_cache() -> void:
	_cache.clear()


static func exists(name: StringName) -> bool:
	return ResourceLoader.exists(DIR + String(name) + ".svg")


## One DPITexture holding several icons side by side (each at its own drawn size, crisp), as
## AtlasTextures keyed by [method atlas_key]: icons drawn next to each other in draw order then
## share one texture and batch into one draw call (the HUD and dock, Art Bible §4.19 budget).
## [param entries]: [name, px, active] triples.
static func atlas(entries: Array) -> Dictionary:
	var key_parts := PackedStringArray()
	for e: Array in entries:
		key_parts.append(atlas_key(StringName(e[0]), float(e[1]), bool(e[2])))
	var cache_key := "atlas:" + ",".join(key_parts)
	var hit: Variant = _cache.get(cache_key)
	if hit is Dictionary:
		return hit
	var x := 0.0
	var h := 0.0
	var body := ""
	var regions: Dictionary = {}
	for i in entries.size():
		var e: Array = entries[i]
		var px := float(e[1])
		var base := load(DIR + String(e[0]) + ".svg") as DPITexture
		if base == null:
			push_error("Icons: missing %s.svg" % e[0])
			continue
		var src := base.get_source()
		if bool(e[2]):
			src = src.replace(ACCENT_ATTR, ACCENT_ACTIVE)
		var inner := src.substr(src.find(">") + 1)
		inner = inner.substr(0, inner.rfind("</svg>"))
		body += "<g transform=\"translate(%s 0) scale(%s)\">%s</g>" % [str(x), str(px / CANVAS_PX), inner]
		regions[key_parts[i]] = Rect2(x, 0.0, px, px)
		x += ceilf(px) + ATLAS_GAP
		h = maxf(h, ceilf(px))
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\">%s</svg>" % [
		int(x), int(h), int(x), int(h), body]
	var tex := DPITexture.create_from_string(svg, 1.0)
	var out: Dictionary = {}
	for k: String in regions:
		var a := AtlasTexture.new()
		a.atlas = tex
		a.region = regions[k]
		out[k] = a
	_cache[cache_key] = out
	return out


## The one atlas every HUD icon comes from (top bar + dock + brim sparkles), so all HUD icons
## draw in one batch (round 3 draw-call budget: HUD + dock = 6 calls).
static func hud_atlas() -> Dictionary:
	return atlas(HUD_ATLAS)


static func atlas_key(name: StringName, px: float, active: bool = false) -> String:
	return "%s@%d%s" % [name, roundi(px), "+" if active else ""]


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
