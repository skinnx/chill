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

## [name, px, active] of every HUD icon (TopBarView ICON_PX 72 / badge 36 incl. the Settings gear,
## DockView's plush tab icons 96 / hero 108 with their sleepy and basket-fill variants, the sleepy
## "z z" 42 and the sparkle 30). The HUD atlas holds each of these twice: as drawn by day and in the
## night-chrome variant ([method variant_source]).
const HUD_ATLAS: Array = [
	[&"dew", 72.0, false], [&"watch", 72.0, false], [&"watch_closed", 72.0, false],
	[&"dawn", 72.0, false], [&"sun", 72.0, false], [&"golden", 72.0, false], [&"dusk", 72.0, false],
	[&"moon", 72.0, false], [&"breeze", 36.0, false], [&"rain", 36.0, false],
	[&"gear", 72.0, false], [&"gear", 72.0, true],
	[&"dock_garden", 108.0, false], [&"dock_garden_sleep", 108.0, false],
	[&"dock_basket", 96.0, false], [&"dock_basket_sleep", 96.0, false], [&"dock_basket_1", 96.0, false],
	[&"dock_basket_2", 96.0, false], [&"dock_basket_3", 96.0, false], [&"dock_album", 96.0, false],
	[&"sleep_z", 42.0, false], [&"sparkle", 30.0, false],
]

## Round 5: every icon the sheets and modal cards draw, at its drawn size: one atlas (day and
## night variants), so a whole sheet's icons batch into one draw call (UiBatch). [method rect]
## takes its texture from here whenever the pair is listed.
const UI_ATLAS: Array = [
	[&"close", 48.0], [&"pencil", 48.0], [&"pencil", 42.0], [&"back", 42.0],
	[&"heart", 36.0], [&"heart_empty", 36.0], [&"dew", 48.0], [&"dew", 33.0], [&"check", 36.0],
	[&"postcard", 72.0], [&"postcard", 120.0], [&"photo", 120.0], [&"postcard", 144.0],
	[&"motion", 60.0], [&"transparency", 60.0], [&"text_size", 60.0], [&"watch_closed", 60.0],
	[&"watch", 60.0], [&"music", 60.0], [&"mono", 60.0], [&"haptics", 60.0], [&"hand", 60.0],
	[&"language", 60.0], [&"minus", 42.0], [&"plus", 42.0],
	[&"heart", 72.0], [&"paw", 72.0], [&"moon", 72.0], [&"garden", 72.0], [&"basket", 72.0],
	[&"photo", 72.0], [&"rain", 72.0],
	# polish (draw calls): the friend page's 18 dp hearts and the tea offer chip's wish sparkle drew
	# from textures of their own (one draw call each)
	[&"heart", 54.0], [&"heart_empty", 54.0], [&"sparkle", 30.0],
]
## Atlas rows wrap at this width (GLES3 mobile texture limits).
const ATLAS_MAX_W := 2048.0

## The top bar's icon sizes in HUD_ATLAS (scaled with its chips, TopBarView).
const TOP_ICON_PX := 72.0
const TOP_BADGE_PX := 36.0

static var _cache: Dictionary = {}


## [param name] is the file stem ("garden", "dew" ...); [param px] the drawn size.
static func texture(name: StringName, px: float, active: bool = false, night: bool = false) -> Texture2D:
	var key := atlas_key(name, px, active, night)
	var hit: Variant = _cache.get(key)
	if hit is Texture2D:
		return hit
	var base := load(DIR + String(name) + ".svg") as DPITexture
	if base == null:
		push_error("Icons: missing %s.svg" % name)
		return null
	var src := variant_source(base.get_source(), active, night)
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
		key_parts.append(atlas_key(StringName(e[0]), float(e[1]), bool(e[2]), e.size() > 3 and bool(e[3])))
	var cache_key := "atlas:" + ",".join(key_parts)
	var hit: Variant = _cache.get(cache_key)
	if hit is Dictionary:
		return hit
	var x := 0.0
	var y := 0.0
	var row_h := 0.0
	var w := 0.0
	var body := ""
	var regions: Dictionary = {}
	for i in entries.size():
		var e: Array = entries[i]
		var px := float(e[1])
		var base := load(DIR + String(e[0]) + ".svg") as DPITexture
		if base == null:
			push_error("Icons: missing %s.svg" % e[0])
			continue
		var src := variant_source(base.get_source(), bool(e[2]), e.size() > 3 and bool(e[3]))
		var inner := src.substr(src.find(">") + 1)
		inner = inner.substr(0, inner.rfind("</svg>"))
		if x + px > ATLAS_MAX_W and x > 0.0:
			x = 0.0
			y += row_h + ATLAS_GAP
			row_h = 0.0
		body += "<g transform=\"translate(%s %s) scale(%s)\">%s</g>" % [str(x), str(y), str(px / CANVAS_PX), inner]
		regions[key_parts[i]] = Rect2(x, y, px, px)
		x += ceilf(px) + ATLAS_GAP
		w = maxf(w, x)
		row_h = maxf(row_h, ceilf(px))
	var h := y + row_h
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\">%s</svg>" % [
		int(w), int(h), int(w), int(h), body]
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
## [param top_k]: the top bar's chip scale for the Text size setting (its 72 / 36 px icons grow
## with the chips; the dock's 84 px icons and the sparkles keep their size).
static func hud_atlas(top_k: float = 1.0) -> Dictionary:
	var entries: Array = []
	for e: Array in HUD_ATLAS:
		var px := float(e[1])
		if not is_equal_approx(top_k, 1.0) and (is_equal_approx(px, TOP_ICON_PX) or is_equal_approx(px, TOP_BADGE_PX)):
			px = roundf(px * top_k)
		entries.append([e[0], px, e[2]])
		entries.append([e[0], px, e[2], true])
	return atlas(entries)


## The sheet / modal icon atlas (UI_ATLAS, day and night variants).
static func ui_atlas() -> Dictionary:
	var entries: Array = []
	for e: Array in UI_ATLAS:
		entries.append([e[0], e[1], false])
		entries.append([e[0], e[1], false, true])
	return atlas(entries)


## The sheet / modal icon [param name] at [param px] in the current build scheme
## (UiTokens.night_scheme), from the UI atlas when listed, else its own texture.
static func ui(name: StringName, px: float) -> Texture2D:
	var t: Variant = ui_atlas().get(atlas_key(name, px, false, UiTokens.night_scheme))
	return t if t is Texture2D else texture(name, px, false, UiTokens.night_scheme)


static func atlas_key(name: StringName, px: float, active: bool = false, night: bool = false) -> String:
	return "%s@%d%s%s" % [name, roundi(px), "+" if active else "", "~n" if night else ""]


## The SVG source of a state: active lifts the accent layer to 100 %; night (the night-chrome HUD,
## palettes ui_alpha.night_chrome) redraws the ink layer in night_ink and lifts the accent layer
## to night_chrome.icon_secondary, so the duotone keeps its weight on the dim glass.
static func variant_source(src: String, active: bool, night: bool) -> String:
	if active:
		src = src.replace(ACCENT_ATTR, ACCENT_ACTIVE)
	if night:
		var ink := "#" + UiTokens.color(&"ink").to_html(false).to_upper()
		var night_ink := "#" + UiTokens.color(&"night_ink").to_html(false).to_upper()
		src = src.replace(ink, night_ink)
		var nt := UiTokens.alpha_section(&"night_chrome")
		src = src.replace(ACCENT_ATTR, "fill-opacity=\"%s\"" % str(float(nt.get("icon_secondary", 0.6))))
		# round 6: the plush dock icons keep their colours; their cocoa outline turns into a cream
		# sticker edge on the dim glass (palettes dock_icon.outline_night)
		var di: Dictionary = ContentRegistry.palettes().get("dock_icon", {})
		if di.has("outline") and di.has("outline_night"):
			src = src.replace(String(di["outline"]), String(di["outline_night"]))
	return src


## A TextureRect showing [param name] at [param px] (mouse-transparent).
static func rect(name: StringName, px: float, active: bool = false) -> TextureRect:
	var r := TextureRect.new()
	r.texture = texture(name, px, active) if active else ui(name, px)
	r.custom_minimum_size = Vector2(px, px)
	r.size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
