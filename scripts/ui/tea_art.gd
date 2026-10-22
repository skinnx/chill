class_name TeaArt
extends RefCounted
## Active F2 Tea & Treats art (GDD §14, ACTIVE_TEA §10): the one felt sticker atlas
## (art/tea/tea_atlas.svg + .json, art/tea/src/tea_svg.py) and its colours. The tea nook in the
## world and the teapot panel in the sheet both draw from it, so each is one batch.
##
## Colours: petals take their flower's palettes.json `flora.flowers.fl_*.petal[0]`; a tea's
## liquid blends its petals (or the recipe's liquid_token) toward a warm tea amber; teaware pieces
## are a colour pair over the shared shapes (art/tea/tea_atlas.json "teaware", placeholders until
## the Art Director's set, GDD §14.11).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const ATLAS_JSON := "res://art/tea/tea_atlas.json"
## Brewed tea leans toward this warm amber (the petals alone read as paint, not tea).
const TEA_AMBER := Color("#E7B46E")
const TEA_AMBER_K := 0.28
## The empty pot's warm water.
const WATER := Color("#EDD2A2")
## Treats are the petal colour lifted toward cream (sweets, not drinks).
const TREAT_CREAM := Color("#FFF4E8")
const TREAT_CREAM_K := 0.35

static var _doc: Dictionary = {}
static var _tex: Texture2D = null
static var _flower_colors: Dictionary = {}


static func _ensure() -> void:
	if _tex != null:
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_JSON))
	_doc = parsed if parsed is Dictionary else {}
	_tex = load(String(_doc.get("atlas", "res://art/tea/tea_atlas.svg"))) as Texture2D
	_flower_colors.clear()
	var flora: Dictionary = ContentRegistry.palettes().get("flora", {})
	var fl: Dictionary = flora.get("flowers", {})
	for token: String in fl:
		var row: Dictionary = fl[token]
		var petals: Array = row.get("petal", ["#FFFFFF"])
		var c := Color.html(String(petals[0]))
		_flower_colors[StringName(String(row.get("flower_id", "")))] = c
		_flower_colors[StringName(token)] = c


static func texture() -> Texture2D:
	_ensure()
	return _tex


static func release_shared() -> void:
	_tex = null
	_doc = {}
	_flower_colors = {}


## Atlas region of piece [param name] (px).
static func region(name: StringName) -> Rect2:
	_ensure()
	var p: Dictionary = (_doc.get("pieces", {}) as Dictionary).get(String(name), {})
	var r: Array = p.get("region", [0, 0, 1, 1])
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


## Where the piece stands or turns, in piece px.
static func pivot(name: StringName) -> Vector2:
	_ensure()
	var p: Dictionary = (_doc.get("pieces", {}) as Dictionary).get(String(name), {})
	var v: Array = p.get("pivot", [0, 0])
	return Vector2(float(v[0]), float(v[1]))


## Draws piece [param name] into [param ci] with its pivot at [param at], scaled and turned
## about the pivot, multiplied by [param color]. Call from _draw().
static func draw(ci: CanvasItem, name: StringName, at: Vector2, scale: float = 1.0, rot: float = 0.0,
		color: Color = Color.WHITE) -> void:
	var r := region(name)
	var pv := pivot(name)
	if is_zero_approx(rot):
		# no command transform: VERTEX stays in the item's own space (the lit nook shader reads it)
		ci.draw_texture_rect_region(texture(), Rect2(at - pv * scale, r.size * scale), r, color)
		return
	ci.draw_set_transform(at, rot, Vector2(scale, scale))
	ci.draw_texture_rect_region(texture(), Rect2(-pv, r.size), r, color)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A Sprite2D of piece [param name] whose origin is the piece's pivot (world nook).
static func sprite(name: StringName, material: Material = null) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = texture()
	s.region_enabled = true
	var r := region(name)
	s.region_rect = r
	s.centered = false
	s.offset = -pivot(name)
	s.material = material
	var size := texture().get_size()
	if material != null:
		s.set_instance_shader_parameter(&"i_region", Vector4(r.position.x / size.x, r.position.y / size.y,
				r.size.x / size.x, r.size.y / size.y))
	return s


## A flower's petal colour (its fl_* token).
static func flower_color(flower: StringName) -> Color:
	_ensure()
	return _flower_colors.get(flower, Color.WHITE)


## The liquid of a pot or cup holding [param petals] (flower ids, repeats count); [param treat]
## lifts it toward cream. No petals = warm water.
static func liquid_color(petals: Array, treat: bool = false) -> Color:
	if petals.is_empty():
		return WATER
	var acc := Color(0, 0, 0, 0)
	for p: Variant in petals:
		var c := flower_color(StringName(str(p)))
		acc += Color(c.r, c.g, c.b, 1.0)
	var n := float(petals.size())
	var mix := Color(acc.r / n, acc.g / n, acc.b / n, 1.0)
	if treat:
		return mix.lerp(TREAT_CREAM, TREAT_CREAM_K)
	return mix.lerp(TEA_AMBER, TEA_AMBER_K)


## A recipe's colour (its book card, the reveal): the recipe's own petals, else its liquid token.
static func recipe_color(recipe: StringName, petals: Array = []) -> Color:
	var content := ContentRegistry.content
	var r: Dictionary = content.recipes_by_id.get(recipe, {})
	var treat := String(r.get("kind", "tea")) == "treat"
	if not petals.is_empty():
		return liquid_color(petals, treat)
	var want := content.recipe_petals(recipe)
	var list: Array = []
	for f: String in want:
		for i in int(want[f]):
			list.append(f)
	if list.is_empty():
		var token := String(r.get("liquid_token", "mix"))
		if token == "mix":
			list = ["sweet_clover", "button_daisy", "buttercup"]
		else:
			list = [token]
	return liquid_color(list, treat)


## The colour pair of a teaware piece: {body, cap} for a teapot, {body} for cups and cloths,
## glow (bool) for the night pieces.
static func teaware_colors(id: StringName) -> Dictionary:
	_ensure()
	var all: Dictionary = _doc.get("teaware", {})
	var row: Dictionary = all.get(String(id), {})
	var out := {"body": Color.html(String(row.get("body", "#E9C497"))),
		"cap": Color.html(String(row.get("cap", row.get("body", "#B7845A")))),
		"glow": bool(row.get("glow", false))}
	return out


## Petal pieces in a pot or jar sit on a small deterministic scatter (no RNG stream).
static func scatter(i: int, salt: int = 0) -> Vector2:
	var h := hash([i, salt, "tea"])
	return Vector2(float(h & 0xFFFF) / 65535.0, float((h >> 16) & 0xFFFF) / 65535.0)


## Plays tea cue [param id] (S28-S34, audio/manifest.json, Sound Designer). Until the manifest
## carries the cue, its GDD §14.8 haptic ([param haptic]: {subtle, full} kinds) plays directly, so
## the touch is never silent and never double-buzzes once the cue lands.
static func cue(id: StringName, ctx: Dictionary = {}, haptic: Dictionary = {}) -> void:
	var cues: Dictionary = ContentRegistry.audio_manifest().get("cues", {})
	if cues.has(String(id)):
		AudioDirector.play_cue(id, ctx)
	elif not haptic.is_empty():
		Haptics.play_for_cue(haptic, id)


## A number from tea.json: [param section].[param key] (or [param fallback]).
static func tea_num(section: String, key: String, fallback: float = 0.0) -> float:
	var tea: Dictionary = ContentRegistry.content.tea
	var sec: Variant = tea.get(section, {})
	if sec is Dictionary:
		return float((sec as Dictionary).get(key, fallback))
	return fallback


## The teaware id in use for [param slot] ("teapot", "cup", "cloth").
static func in_use(slot: String) -> StringName:
	if Game.sim == null:
		return StringName(String(ContentRegistry.content.teaware_default.get(slot, "")))
	var use: Dictionary = Game.teaware().get("in_use", {})
	return StringName(String(use.get(slot, ContentRegistry.content.teaware_default.get(slot, ""))))


## A recipe's translated name.
static func recipe_name(recipe: StringName) -> String:
	var r: Dictionary = ContentRegistry.content.recipes_by_id.get(recipe, {})
	return TranslationServer.translate(String(r.get("name_key", "")))
