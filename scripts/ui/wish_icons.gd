class_name WishIcons
extends RefCounted
## Active F1 Wishes art (ACTIVE_WISHES §7.1, §7.3; GDD §14.11 b FE-W): the felt thought bubble, the
## sleepy "z", the grant petals, the Album stamp disc and every wish icon (the eleven `wish_*`
## glyphs, one per flower and one per décor set), drawn as plush stickers in the dock's style (Art
## Bible §9.3 round 6: soft full-colour fills, a warm cocoa outline, a cream highlight) and
## rasterised ONCE into a single DPITexture. Everything a bubble draws comes from this one texture
## (one draw call per bubble), and the Album's stamps and wish rows batch into one call too.
##
## Colours are data: palettes.json dock_icon (outline, fills), flora.flowers (petal / leaf triples
## of each flower), materials (décor) and ui (the bubble's cream felt). Icon ids follow
## wishes.json: "wish_heart", "flower:<flower_id>", "decor:<set_id>".

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## Authoring canvas of every glyph (the dock icons' 72 px canvas, Art Bible §9.3).
const CANVAS := 72.0
## Raster px per design px: the world draws a bubble at 44 dp = 132 design px, shown up to ~1.4x on
## tablets, so the atlas is rasterised at 1.5x and drawn scaled (crisp, no bilinear blow-up).
const RASTER_K := 1.5
## Drawn sizes in design px (ACTIVE_WISHES §7.1: 44 dp cloud, 28 dp icon; the Album's 48 dp stamp).
const BUBBLE_W := 156.0
const BUBBLE_H := 150.0
const ICON_PX := 144.0
const SMALL_PX := 48.0
const GAP := 4.0
const MAX_W := 2048.0
const BUBBLE := &"bubble"
const STAMP := &"stamp"
const PETAL := &"petal"
const SLEEP_Z := &"z"
const FALLBACK := &"wish_heart"
## The eleven wish glyphs (wishes.json icon values that are not flower: / decor:).
const GLYPHS: Array[StringName] = [&"wish_heart", &"wish_paw", &"wish_note", &"wish_firefly", &"wish_pinwheel",
	&"wish_boat", &"wish_candle", &"wish_droplet", &"wish_ripple", &"wish_teacup", &"wish_treat"]
const DECOR_SETS: Array[StringName] = [&"leaf_pinwheel", &"pebble_cairn", &"toadstool_seat", &"firefly_lantern",
	&"stream_stones", &"wind_chime"]
## The bubble cloud's body centre and the icon's centre inside the bubble region (design px): the
## cloud sits up and right, its two trailing dots run down-left toward the friend's head.
const CLOUD_CENTRE := Vector2(88.0, 66.0)
## Outline stroke (canvas units), as the dock icons.
const STROKE := 4.0

static var _atlas: Dictionary = {}
static var _textures: Dictionary = {}


## {tex: DPITexture, regions: {id: Rect2 in texture px}} (built once).
static func atlas() -> Dictionary:
	if not _atlas.is_empty():
		return _atlas
	var entries: Array = []  # [id, w, h] in design px
	entries.append([BUBBLE, BUBBLE_W, BUBBLE_H])
	entries.append([STAMP, ICON_PX, ICON_PX])
	entries.append([PETAL, SMALL_PX, SMALL_PX])
	entries.append([SLEEP_Z, SMALL_PX, SMALL_PX])
	for id: StringName in all_icon_ids():
		entries.append([id, ICON_PX, ICON_PX])
	var x := 0.0
	var y := 0.0
	var row_h := 0.0
	var w := 0.0
	var body := ""
	var regions: Dictionary = {}
	for e: Array in entries:
		var id: StringName = e[0]
		var ew := ceilf(float(e[1]) * RASTER_K)
		var eh := ceilf(float(e[2]) * RASTER_K)
		if x + ew > MAX_W and x > 0.0:
			x = 0.0
			y += row_h + GAP
			row_h = 0.0
		var view := Vector2(BUBBLE_W, BUBBLE_H) / BUBBLE_W * CANVAS if id == BUBBLE else Vector2(CANVAS, CANVAS)
		body += "<g transform=\"translate(%s %s) scale(%s)\">%s</g>" % [str(x), str(y), str(ew / view.x), svg_body(id)]
		regions[id] = Rect2(x, y, ew, eh)
		x += ew + GAP
		w = maxf(w, x)
		row_h = maxf(row_h, eh)
	var h := y + row_h
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\">%s</svg>" % [
		int(w), int(h), int(w), int(h), body]
	var tex := DPITexture.create_from_string(svg, 1.0)
	_atlas = {"tex": tex, "regions": regions}
	return _atlas


static func texture() -> Texture2D:
	return atlas()["tex"]


## Texture px of [param id] (the fallback heart for an unknown id).
static func region(id: StringName) -> Rect2:
	var regions: Dictionary = atlas()["regions"]
	return regions.get(id, regions.get(resolve(id), Rect2()))


## An icon id as wishes.json writes it, mapped to an atlas entry (unknown -> the heart; a flower
## or décor set without its own art -> the nearest glyph).
static func resolve(icon: StringName) -> StringName:
	var s := String(icon)
	if all_icon_ids().has(icon) or icon in [BUBBLE, STAMP, PETAL, SLEEP_Z]:
		return icon
	if s.begins_with("decor:"):
		return &"wish_pinwheel"
	return FALLBACK


## One AtlasTexture per id (cached), for TextureRects in the Album and the wish list.
static func atlas_texture(icon: StringName) -> AtlasTexture:
	var id := resolve(icon)
	var hit: Variant = _textures.get(id)
	if hit is AtlasTexture:
		return hit
	var a := AtlasTexture.new()
	a.atlas = texture()
	a.region = region(id)
	_textures[id] = a
	return a


## A mouse-transparent TextureRect of [param icon] at [param px] (Album rows, stamps).
static func rect(icon: StringName, px: float) -> TextureRect:
	var r := TextureRect.new()
	# ignore the texture's own size BEFORE it is set (else the rect grows to the 1.5x raster)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture = atlas_texture(icon)
	r.custom_minimum_size = Vector2(px, px)
	r.size = Vector2(px, px)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Drops the atlas (the creature layer and the HUD call this on exit: no texture outlives them).
static func release() -> void:
	_atlas = {}
	_textures.clear()


## Every icon id the atlas holds besides the bubble parts: glyphs, flowers, décor sets.
static func all_icon_ids() -> Array[StringName]:
	var out: Array[StringName] = GLYPHS.duplicate()
	for f: StringName in _flower_ids():
		out.append(StringName("flower:%s" % f))
	for d: StringName in DECOR_SETS:
		out.append(StringName("decor:%s" % d))
	return out


static func _flower_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var fl: Dictionary = (_pal().get("flora", {}) as Dictionary).get("flowers", {})
	for k: String in fl:
		out.append(StringName(String((fl[k] as Dictionary).get("flower_id", k))))
	return out


# ================================================================= art

## The inner SVG (no root element) of [param id] in its canvas (72 x 72; the bubble 72 x 69.2).
static func svg_body(id: StringName) -> String:
	var s := String(id)
	if id == BUBBLE:
		return _bubble()
	if id == STAMP:
		return _stamp()
	if id == PETAL:
		# white (tinted by the gift flower at draw time) with a soft edge and a vein so even a
		# cream daisy petal reads over a bright meadow
		return "<path d=\"M36 8 C50 18 52 42 36 64 C20 42 22 18 36 8 Z\" fill=\"#FFFFFF\" stroke=\"#8C7F78\" " \
			+ "stroke-width=\"5\" stroke-linejoin=\"round\"/><path d=\"M36 18 V52\" stroke=\"#B5AAA3\" " \
			+ "stroke-width=\"3\" stroke-linecap=\"round\"/>"
	if id == SLEEP_Z:
		return "<path d=\"M18 18 H54 L20 54 H56\" fill=\"none\" stroke=\"%s\" stroke-width=\"9\" stroke-linecap=\"round\" " \
			% _dock("zz") + "stroke-linejoin=\"round\"/>"
	if s.begins_with("flower:"):
		return _flower(StringName(s.trim_prefix("flower:")))
	if s.begins_with("decor:"):
		return _decor(StringName(s.trim_prefix("decor:")))
	match id:
		&"wish_heart":
			return _heart(_dock("coral"), _dock("coral_deep"))
		&"wish_paw":
			return _paw()
		&"wish_note":
			return _note()
		&"wish_firefly":
			return _firefly()
		&"wish_pinwheel":
			return _pinwheel()
		&"wish_boat":
			return _boat(false)
		&"wish_candle":
			return _boat(true)
		&"wish_droplet":
			return _droplet(36.0, 38.0, 1.0)
		&"wish_ripple":
			return _ripple()
		&"wish_teacup":
			return _teacup()
		&"wish_treat":
			return _treat()
	return _heart(_dock("coral"), _dock("coral_deep"))


## The felt cloud: a cream body of soft lobes, a warm shade along the bottom, a stitched edge
## (felt seam, dashed) and a highlight; two trailing dots down-left. 72-wide canvas.
static func _bubble() -> String:
	var k := CANVAS / BUBBLE_W
	var c := CLOUD_CENTRE * k
	var cream := _ui(&"surface_hi")
	var shade := _mix(cream, _dock("weave"), 0.16)
	var seam := _mix(cream, _dock("outline"), 0.28)
	var o := _mix(_dock("outline"), cream, 0.25)
	var lobes := [[0.0, -9.0, 16.0], [-15.0, -1.0, 12.5], [15.0, -1.0, 12.5], [-9.0, 9.5, 12.0], [9.0, 9.5, 12.0],
		[0.0, 7.0, 14.0], [-6.0, -11.0, 11.0], [7.0, -11.0, 11.5]]
	var shape := ""
	for l: Array in lobes:
		shape += "<circle cx=\"%s\" cy=\"%s\" r=\"%s\"/>" % [str(c.x + float(l[0])), str(c.y + float(l[1])), str(float(l[2]))]
	var out := ""
	# outline: the same lobes, grown by the stroke, in the soft cocoa (one silhouette)
	out += "<g fill=\"%s\">" % o
	for l: Array in lobes:
		out += "<circle cx=\"%s\" cy=\"%s\" r=\"%s\"/>" % [str(c.x + float(l[0])), str(c.y + float(l[1])),
			str(float(l[2]) + 2.2)]
	out += "</g>"
	out += "<g fill=\"%s\">%s</g>" % [cream, shape]
	# warm felt shade under the bottom lobes
	out += "<ellipse cx=\"%s\" cy=\"%s\" rx=\"21\" ry=\"6.5\" fill=\"%s\"/>" % [str(c.x), str(c.y + 15.5), shade]
	out += "<g fill=\"%s\">" % cream
	out += "<circle cx=\"%s\" cy=\"%s\" r=\"11\"/>" % [str(c.x - 8.0), str(c.y + 6.5)]
	out += "<circle cx=\"%s\" cy=\"%s\" r=\"11\"/>" % [str(c.x + 8.0), str(c.y + 6.5)]
	out += "<circle cx=\"%s\" cy=\"%s\" r=\"15\"/></g>" % [str(c.x), str(c.y - 3.0)]
	# stitched seam inside the edge
	out += "<ellipse cx=\"%s\" cy=\"%s\" rx=\"21.5\" ry=\"17\" fill=\"none\" stroke=\"%s\" stroke-width=\"1.3\" " \
		% [str(c.x), str(c.y), seam] + "stroke-dasharray=\"2.6 2.4\" stroke-linecap=\"round\"/>"
	# highlight
	out += "<ellipse cx=\"%s\" cy=\"%s\" rx=\"6\" ry=\"2.6\" fill=\"#FFFFFF\" fill-opacity=\"0.85\" " \
		% [str(c.x - 10.0), str(c.y - 15.0)] + "transform=\"rotate(-18 %s %s)\"/>" % [str(c.x - 10.0), str(c.y - 15.0)]
	# trailing dots toward the head (down-left)
	for d: Array in [[-23.0, 23.0, 4.6], [-31.0, 30.0, 3.0]]:
		var dx := c.x + float(d[0])
		var dy := c.y + float(d[1])
		out += "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"%s\"/>" % [str(dx), str(dy), str(float(d[2]) + 1.6), o]
		out += "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"%s\"/>" % [str(dx), str(dy), str(float(d[2])), cream]
	return out


## The Album stamp: a felt disc with a stitched ring (the icon draws on top).
static func _stamp() -> String:
	var cream := _dock("cream")
	var ring := _mix(cream, _dock("clay"), 0.45)
	return "<circle cx=\"36\" cy=\"36\" r=\"33\" fill=\"%s\"/>" % ring \
		+ "<circle cx=\"36\" cy=\"36\" r=\"29\" fill=\"%s\"/>" % cream \
		+ "<circle cx=\"36\" cy=\"36\" r=\"31\" fill=\"none\" stroke=\"%s\" stroke-width=\"1.4\" " % _dock("outline") \
		+ "stroke-opacity=\"0.35\" stroke-dasharray=\"3 3\"/>"


static func _ol() -> String:
	return "stroke=\"%s\" stroke-width=\"%s\" stroke-linejoin=\"round\" stroke-linecap=\"round\"" % [
		_dock("outline"), str(STROKE)]


static func _heart(fill: String, deep: String) -> String:
	var d := "M36 60 C22 50 10 40 10 27 C10 18 17 12 25 12 C30 12 34 15 36 19 C38 15 42 12 47 12 C55 12 62 18 62 27 " \
		+ "C62 40 50 50 36 60 Z"
	return "<path d=\"%s\" fill=\"%s\" %s/>" % [d, fill, _ol()] \
		+ "<path d=\"M36 60 C46 53 56 44 60 34 C56 42 48 48 40 52 Z\" fill=\"%s\"/>" % deep \
		+ "<ellipse cx=\"23\" cy=\"23\" rx=\"5\" ry=\"3.4\" fill=\"%s\" fill-opacity=\"0.85\" " % _dock("cream") \
		+ "transform=\"rotate(-30 23 23)\"/>"


static func _paw() -> String:
	var f := _dock("clay")
	var hi := _dock("clay_hi")
	var out := "<ellipse cx=\"36\" cy=\"46\" rx=\"15\" ry=\"12.5\" fill=\"%s\" %s/>" % [f, _ol()]
	for t: Array in [[17.0, 30.0, 6.5], [28.0, 20.0, 7.0], [44.0, 20.0, 7.0], [55.0, 30.0, 6.5]]:
		out += "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"%s\" %s/>" % [str(t[0]), str(t[1]), str(t[2]), f, _ol()]
	out += "<ellipse cx=\"31\" cy=\"42\" rx=\"5\" ry=\"3\" fill=\"%s\"/>" % hi
	return out


static func _note() -> String:
	var f := _dock("bloom")
	return "<path d=\"M28 50 V18 L54 12 V44\" fill=\"none\" %s/>" % _ol() \
		+ "<path d=\"M28 18 L54 12 V20 L28 26 Z\" fill=\"%s\" %s/>" % [_dock("honey"), _ol()] \
		+ "<ellipse cx=\"21\" cy=\"52\" rx=\"9\" ry=\"7.5\" fill=\"%s\" %s/>" % [f, _ol()] \
		+ "<ellipse cx=\"47\" cy=\"46\" rx=\"9\" ry=\"7.5\" fill=\"%s\" %s/>" % [f, _ol()] \
		+ "<ellipse cx=\"18\" cy=\"49\" rx=\"3\" ry=\"2\" fill=\"%s\"/>" % _dock("cream")


static func _firefly() -> String:
	var glow := _pal_fx("firefly_core", "#FFE7A6")
	return "<circle cx=\"40\" cy=\"44\" r=\"20\" fill=\"%s\" fill-opacity=\"0.45\"/>" % glow \
		+ "<circle cx=\"40\" cy=\"44\" r=\"13\" fill=\"%s\" fill-opacity=\"0.7\"/>" % glow \
		+ "<ellipse cx=\"22\" cy=\"20\" rx=\"9\" ry=\"6\" fill=\"%s\" fill-opacity=\"0.9\" %s " % [_dock("cream"), _ol()] \
		+ "transform=\"rotate(-25 22 20)\"/>" \
		+ "<ellipse cx=\"38\" cy=\"18\" rx=\"9\" ry=\"6\" fill=\"%s\" fill-opacity=\"0.9\" %s " % [_dock("cream"), _ol()] \
		+ "transform=\"rotate(20 38 18)\"/>" \
		+ "<ellipse cx=\"31\" cy=\"32\" rx=\"9\" ry=\"11\" fill=\"%s\" %s transform=\"rotate(-35 31 32)\"/>" \
		% [_dock("zz"), _ol()] \
		+ "<circle cx=\"42\" cy=\"45\" r=\"8.5\" fill=\"%s\" %s/>" % [_dock("bloom_heart"), _ol()] \
		+ "<circle cx=\"40\" cy=\"43\" r=\"3\" fill=\"#FFFFFF\" fill-opacity=\"0.9\"/>"


static func _pinwheel() -> String:
	var a := _mat("pinwheel_a", "lit")
	var b := _mat("pinwheel_b", "lit")
	var out := "<path d=\"M36 38 V66\" fill=\"none\" stroke=\"%s\" stroke-width=\"7\" stroke-linecap=\"round\"/>" \
		% _dock("outline")
	out += "<path d=\"M36 38 V66\" fill=\"none\" stroke=\"%s\" stroke-width=\"3\" stroke-linecap=\"round\"/>" \
		% _mat("wood_cut", "lit")
	var blades := [["M36 34 L36 8 C48 10 52 22 36 34 Z", a], ["M36 34 L62 34 C60 46 48 50 36 34 Z", b],
		["M36 34 L36 60 C24 58 20 46 36 34 Z", a], ["M36 34 L10 34 C12 22 24 18 36 34 Z", b]]
	for bl: Array in blades:
		out += "<path d=\"%s\" fill=\"%s\" %s/>" % [String(bl[0]), String(bl[1]), _ol()]
	out += "<circle cx=\"36\" cy=\"34\" r=\"4.5\" fill=\"%s\" %s/>" % [_dock("honey"), _ol()]
	return out


static func _boat(candle: bool) -> String:
	var lit := _mat("leaf_boat", "lit")
	var shade := _mat("leaf_boat", "shade")
	var out := "<path d=\"M8 40 C20 58 52 58 64 40 C52 46 20 46 8 40 Z\" fill=\"%s\" %s/>" % [lit, _ol()]
	out += "<path d=\"M14 44 C26 52 46 52 58 44\" fill=\"none\" stroke=\"%s\" stroke-width=\"2.4\" " % shade \
		+ "stroke-linecap=\"round\"/>"
	out += "<path d=\"M8 62 C20 58 28 66 36 62 C44 58 52 66 64 62\" fill=\"none\" stroke=\"%s\" stroke-width=\"3.4\" " \
		% _dock("dew") + "stroke-linecap=\"round\"/>"
	if candle:
		out += "<rect x=\"30\" y=\"24\" width=\"12\" height=\"19\" rx=\"4\" fill=\"%s\" %s/>" % [_dock("cream"), _ol()]
		out += "<path d=\"M36 8 C42 15 41 21 36 22 C31 21 30 15 36 8 Z\" fill=\"%s\" %s/>" % [_dock("bloom_heart"), _ol()]
	else:
		out += "<path d=\"M36 42 V12\" fill=\"none\" %s/>" % _ol()
		out += "<path d=\"M38 14 C52 18 56 30 54 38 L38 38 Z\" fill=\"%s\" %s/>" % [_dock("cream"), _ol()]
	return out


static func _droplet(cx: float, cy: float, k: float) -> String:
	var d := "M%s %s C%s %s %s %s %s %s C%s %s %s %s %s %s Z" % [
		str(cx), str(cy - 26.0 * k), str(cx + 19.0 * k), str(cy - 4.0 * k), str(cx + 16.0 * k), str(cy + 20.0 * k),
		str(cx), str(cy + 20.0 * k), str(cx - 16.0 * k), str(cy + 20.0 * k), str(cx - 19.0 * k), str(cy - 4.0 * k),
		str(cx), str(cy - 26.0 * k)]
	return "<path d=\"%s\" fill=\"%s\" %s/>" % [d, _dock("dew"), _ol()] \
		+ "<ellipse cx=\"%s\" cy=\"%s\" rx=\"%s\" ry=\"%s\" fill=\"%s\" transform=\"rotate(-25 %s %s)\"/>" % [
			str(cx - 6.0 * k), str(cy + 2.0 * k), str(4.0 * k), str(7.0 * k), _dock("dew_hi"), str(cx - 6.0 * k),
			str(cy + 2.0 * k)]


static func _ripple() -> String:
	return "<ellipse cx=\"36\" cy=\"52\" rx=\"29\" ry=\"10\" fill=\"none\" stroke=\"%s\" " % _dock("dew") \
		+ "stroke-width=\"4\"/>" \
		+ "<ellipse cx=\"36\" cy=\"52\" rx=\"16\" ry=\"5.5\" fill=\"%s\" fill-opacity=\"0.7\"/>" % _dock("dew_hi") \
		+ _droplet(36.0, 26.0, 0.7)


static func _teacup() -> String:
	var cup := _dock("cream")
	var tea := _dock("honey")
	return "<path d=\"M26 16 C22 11 30 8 27 3 M38 16 C34 11 42 8 39 3\" fill=\"none\" stroke=\"%s\" " % _dock("outline") \
		+ "stroke-opacity=\"0.45\" stroke-width=\"3\" stroke-linecap=\"round\"/>" \
		+ "<ellipse cx=\"34\" cy=\"58\" rx=\"27\" ry=\"7\" fill=\"%s\" %s/>" % [_dock("clay_hi"), _ol()] \
		+ "<path d=\"M52 30 C64 28 64 46 50 44\" fill=\"none\" %s/>" % _ol() \
		+ "<path d=\"M12 24 H56 C56 44 48 54 34 54 C20 54 12 44 12 24 Z\" fill=\"%s\" %s/>" % [cup, _ol()] \
		+ "<ellipse cx=\"34\" cy=\"25\" rx=\"20\" ry=\"4\" fill=\"%s\"/>" % tea \
		+ "<path d=\"M28 38 C28 34 33 34 34 37 C35 34 40 34 40 38 C40 42 34 45 34 45 C34 45 28 42 28 38 Z\" fill=\"%s\"/>" \
		% _dock("bloom")


static func _treat() -> String:
	var biscuit := _dock("honey")
	var out := "<circle cx=\"36\" cy=\"38\" r=\"25\" fill=\"%s\" %s/>" % [biscuit, _ol()]
	out += "<circle cx=\"36\" cy=\"38\" r=\"19\" fill=\"none\" stroke=\"%s\" stroke-width=\"1.6\" " % _dock("weave") \
		+ "stroke-dasharray=\"3 3\"/>"
	out += "<path d=\"M28 36 C28 31 34 31 36 35 C38 31 44 31 44 36 C44 42 36 47 36 47 C36 47 28 42 28 36 Z\" " \
		+ "fill=\"%s\" %s/>" % [_dock("bloom"),
			"stroke=\"%s\" stroke-width=\"2.4\" stroke-linejoin=\"round\"" % _dock("outline")]
	out += "<ellipse cx=\"26\" cy=\"25\" rx=\"5\" ry=\"3\" fill=\"%s\" fill-opacity=\"0.8\"/>" % _dock("honey_hi")
	return out


## A flower by its palette form (flora.flowers: petal [lit, shade, detail], leaf [lit, ...]).
static func _flower(flower: StringName) -> String:
	var fl := _flower_pal(flower)
	var petal: Array = fl.get("petal", ["#FFFFFF", "#DDDDDD", "#FFE08A"])
	var leaf: Array = fl.get("leaf", ["#79C27C", "#4C9C78", "#AEDF98"])
	var p0 := String(petal[0])
	var p1 := String(petal[1])
	var p2 := String(petal[2])
	var lf := String(leaf[0])
	var out := "<path d=\"M36 66 C36 56 36 50 36 44\" fill=\"none\" stroke=\"%s\" stroke-width=\"7\" " % _dock("outline") \
		+ "stroke-linecap=\"round\"/><path d=\"M36 66 C36 56 36 50 36 44\" fill=\"none\" stroke=\"%s\" " % lf \
		+ "stroke-width=\"3\" stroke-linecap=\"round\"/>"
	out += "<path d=\"M36 60 C26 60 18 54 16 46 C26 46 32 50 36 58 Z\" fill=\"%s\" %s/>" % [lf, _ol()]
	var form := String(fl.get("form", "daisy"))
	match form:
		"globe":
			out += "<circle cx=\"36\" cy=\"28\" r=\"18\" fill=\"%s\" %s/>" % [p0, _ol()]
			for q: Array in [[28.0, 22.0], [40.0, 18.0], [44.0, 30.0], [32.0, 34.0], [26.0, 30.0]]:
				out += "<circle cx=\"%s\" cy=\"%s\" r=\"4.5\" fill=\"%s\"/>" % [str(q[0]), str(q[1]), p2]
			out += "<path d=\"M22 36 C28 44 44 44 50 36\" fill=\"none\" stroke=\"%s\" stroke-width=\"2.4\"/>" % p1
		"cup":
			out += "<path d=\"M16 18 C16 38 24 46 36 46 C48 46 56 38 56 18 C50 26 44 22 36 26 C28 22 22 26 16 18 Z\" " \
				+ "fill=\"%s\" %s/>" % [p0, _ol()]
			out += "<path d=\"M24 26 C26 36 30 40 36 40\" fill=\"none\" stroke=\"%s\" stroke-width=\"3\" " % p2 \
				+ "stroke-linecap=\"round\"/>"
		"bell":
			out += "<path d=\"M36 6 C26 6 22 16 22 26 C22 34 16 38 14 42 C22 42 26 38 30 42 C33 38 39 38 42 42 " \
				+ "C46 38 50 42 58 42 C56 38 50 34 50 26 C50 16 46 6 36 6 Z\" fill=\"%s\" %s/>" % [p0, _ol()]
			out += "<path d=\"M30 14 C28 20 28 28 30 34\" fill=\"none\" stroke=\"%s\" stroke-width=\"3\" " % p2 \
				+ "stroke-linecap=\"round\"/>"
		"cluster":
			for c: Array in [[24.0, 26.0, 0.8], [46.0, 22.0, 0.85], [36.0, 38.0, 1.0]]:
				out += _five(float(c[0]), float(c[1]), 12.0 * float(c[2]), p0, p2)
		"primrose":
			out += _five(36.0, 28.0, 21.0, p0, p2, true)
		"puff":
			out += "<circle cx=\"36\" cy=\"28\" r=\"21\" fill=\"%s\" fill-opacity=\"0.55\" %s/>" % [p2, _ol()]
			for i in 12:
				var a := TAU * float(i) / 12.0
				out += "<path d=\"M36 28 L%s %s\" stroke=\"%s\" stroke-width=\"2\" stroke-linecap=\"round\"/>" % [
					str(36.0 + cos(a) * 17.0), str(28.0 + sin(a) * 17.0), p1]
			out += "<circle cx=\"36\" cy=\"28\" r=\"9\" fill=\"%s\" %s/>" % [p0, _ol()]
		"lily":
			out += _star(36.0, 28.0, 21.0, p0, p2)
		_:
			out += _daisy(36.0, 28.0, 21.0, p0, p1, p2)
	return out


static func _five(cx: float, cy: float, r: float, fill: String, centre: String, hearts: bool = false) -> String:
	var out := ""
	for i in 5:
		var a := -PI * 0.5 + TAU * float(i) / 5.0
		var px := cx + cos(a) * r * 0.55
		var py := cy + sin(a) * r * 0.55
		out += "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"%s\" %s/>" % [str(px), str(py),
			str(r * (0.5 if hearts else 0.45)),
			fill, _ol() if r > 14.0 else "stroke=\"%s\" stroke-width=\"2.6\"" % _dock("outline")]
	out += "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"%s\"/>" % [str(cx), str(cy), str(r * 0.42), fill]
	out += "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"%s\"/>" % [str(cx), str(cy), str(r * 0.22), centre]
	return out


static func _daisy(cx: float, cy: float, r: float, p0: String, p1: String, centre: String) -> String:
	var out := ""
	for i in 10:
		var a := TAU * float(i) / 10.0
		var deg := rad_to_deg(a) + 90.0
		out += "<ellipse cx=\"%s\" cy=\"%s\" rx=\"5\" ry=\"10\" fill=\"%s\" stroke=\"%s\" stroke-width=\"2.4\" " % [
			str(cx + cos(a) * r * 0.55), str(cy + sin(a) * r * 0.55), p0, _dock("outline")] \
			+ "transform=\"rotate(%s %s %s)\"/>" % [str(deg), str(cx + cos(a) * r * 0.55), str(cy + sin(a) * r * 0.55)]
	out += "<circle cx=\"%s\" cy=\"%s\" r=\"8.5\" fill=\"%s\" %s/>" % [str(cx), str(cy), centre, _ol()]
	out += "<circle cx=\"%s\" cy=\"%s\" r=\"3\" fill=\"%s\"/>" % [str(cx - 2.5), str(cy - 2.5), p1]
	return out


static func _star(cx: float, cy: float, r: float, fill: String, centre: String) -> String:
	var pts := PackedStringArray()
	for i in 12:
		var a := -PI * 0.5 + PI * float(i) / 6.0
		var rr := r if i % 2 == 0 else r * 0.55
		pts.append("%s,%s" % [str(cx + cos(a) * rr), str(cy + sin(a) * rr)])
	return "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"%s\" fill-opacity=\"0.4\"/>" % [str(cx), str(cy),
		str(r + 4.0), centre] \
		+ "<polygon points=\"%s\" fill=\"%s\" %s/>" % [" ".join(pts), fill, _ol()] \
		+ "<circle cx=\"%s\" cy=\"%s\" r=\"6\" fill=\"%s\"/>" % [str(cx), str(cy), centre]


static func _decor(set_id: StringName) -> String:
	match set_id:
		&"leaf_pinwheel":
			return _pinwheel()
		&"pebble_cairn":
			var a := _mat("stone_cool", "lit")
			var b := _mat("pebble_alt", "lit")
			return "<ellipse cx=\"36\" cy=\"56\" rx=\"24\" ry=\"9\" fill=\"%s\" %s/>" % [a, _ol()] \
				+ "<ellipse cx=\"36\" cy=\"40\" rx=\"18\" ry=\"8\" fill=\"%s\" %s/>" % [b, _ol()] \
				+ "<ellipse cx=\"37\" cy=\"26\" rx=\"12\" ry=\"6.5\" fill=\"%s\" %s/>" % [a, _ol()] \
				+ "<ellipse cx=\"36\" cy=\"14\" rx=\"7\" ry=\"4.5\" fill=\"%s\" %s/>" % [b, _ol()]
		&"toadstool_seat":
			return "<path d=\"M28 36 C28 50 26 58 24 62 H48 C46 58 44 50 44 36 Z\" fill=\"%s\" %s/>" % [
				_mat("toadstool_stem", "lit"), _ol()] \
				+ "<path d=\"M8 38 C8 18 22 8 36 8 C50 8 64 18 64 38 C52 42 20 42 8 38 Z\" fill=\"%s\" %s/>" % [
					_mat("toadstool_cap", "lit"), _ol()] \
				+ "<circle cx=\"26\" cy=\"24\" r=\"4.5\" fill=\"%s\"/>" % _mat("toadstool_cap", "detail") \
				+ "<circle cx=\"44\" cy=\"18\" r=\"3.5\" fill=\"%s\"/>" % _mat("toadstool_cap", "detail") \
				+ "<circle cx=\"50\" cy=\"30\" r=\"3\" fill=\"%s\"/>" % _mat("toadstool_cap", "detail")
		&"firefly_lantern":
			var glow := _mat("lantern_light", "detail")
			return "<circle cx=\"36\" cy=\"42\" r=\"26\" fill=\"%s\" fill-opacity=\"0.35\"/>" % glow \
				+ "<path d=\"M28 14 C28 6 44 6 44 14\" fill=\"none\" %s/>" % _ol() \
				+ "<rect x=\"18\" y=\"18\" width=\"36\" height=\"42\" rx=\"12\" fill=\"%s\" %s/>" % [
					_mat("lantern_jar", "lit"), _ol()] \
				+ "<rect x=\"24\" y=\"14\" width=\"24\" height=\"8\" rx=\"3\" fill=\"%s\" %s/>" % [
					_mat("wood_cut", "shade"), _ol()] \
				+ "<circle cx=\"32\" cy=\"40\" r=\"6\" fill=\"%s\"/>" % glow \
				+ "<circle cx=\"42\" cy=\"48\" r=\"4\" fill=\"%s\"/>" % glow \
				+ "<circle cx=\"40\" cy=\"32\" r=\"3\" fill=\"%s\"/>" % glow
		&"stream_stones":
			return "<path d=\"M4 54 C16 50 22 58 36 54 C50 50 56 58 68 54\" fill=\"none\" stroke=\"%s\" " % _dock("dew") \
				+ "stroke-width=\"4\" stroke-linecap=\"round\"/>" \
				+ "<ellipse cx=\"20\" cy=\"44\" rx=\"14\" ry=\"8\" fill=\"%s\" %s/>" % [_mat("stone_cool", "lit"), _ol()] \
				+ "<ellipse cx=\"48\" cy=\"40\" rx=\"16\" ry=\"9\" fill=\"%s\" %s/>" % [_mat("pebble_alt", "lit"), _ol()] \
				+ "<ellipse cx=\"44\" cy=\"36\" rx=\"5\" ry=\"2.4\" fill=\"%s\"/>" % _mat("stone_cool", "detail")
		&"wind_chime":
			return _note()
	return _pinwheel()


# ================================================================= palette access

static func _pal() -> Dictionary:
	return ContentRegistry.palettes()


static func _dock(key: String) -> String:
	return String((_pal().get("dock_icon", {}) as Dictionary).get(key, "#4B3A33"))


static func _ui(token: StringName) -> String:
	return "#" + UiTokens.color(token).to_html(false).to_upper()


static func _mat(material: String, tone: String) -> String:
	var m: Dictionary = (_pal().get("materials", {}) as Dictionary).get(material, {})
	return String(m.get(tone, "#CFCAD8"))


static func _pal_fx(key: String, fallback: String) -> String:
	var v: Variant = (_pal().get("fx", {}) as Dictionary).get(key, fallback)
	return String(v) if v is String else fallback


static func _flower_pal(flower: StringName) -> Dictionary:
	var fl: Dictionary = (_pal().get("flora", {}) as Dictionary).get("flowers", {})
	for k: String in fl:
		var e: Dictionary = fl[k]
		if StringName(String(e.get("flower_id", ""))) == flower:
			return e
	return {}


static func _mix(a: String, b: String, k: float) -> String:
	return "#" + Color.html(a).lerp(Color.html(b), k).to_html(false).to_upper()
