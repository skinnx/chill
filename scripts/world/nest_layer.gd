class_name NestLayer
extends Node2D
## The friends' nests in the hollow (Retention v1 F1, GDD §13.2.3, `friendship.json: nest`).
##
## A friend who reaches ♥3 builds a little home near its favourite spot - a moss bowl, a leaf
## cradle, a petal cup or a pebble ring - and it grows from a few twigs to a moss bed to a canopy
## of flowers over three days, offline too, and never wilts. It is the one thing in the hollow
## that is unmistakably THEIRS, and the brain naps them in it (CreatureBrain.nests): a return
## shows the friend asleep in the home it built, which is the whole point of having one.
##
## The sim has built, grown, saved and tested nests since Retention v1 P1; nothing ever drew them.
## This layer is that missing view and only that: it reads [method Game.nests] and holds no state
## beyond the fade-in and the little pop of a stage reached while watching. A nest is not a tap
## target (the mossling in it is); the ladder is unchanged.
##
## Drawing: every nest of every style and stage goes into ONE triangle array (WorldTris) and the
## layer issues a single draw_polygon. Procedural - no nest textures are authored.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## A nest appears (built live at ♥3) over this long.
const FADE_S := 0.6
## A stage reached while watching: the nest swells by POP_K and settles over POP_S.
const POP_S := 0.5
const POP_K := 0.12
const STYLE_MOSS := &"moss_bowl"
const STYLE_LEAF := &"leaf_cradle"
const STYLE_PETAL := &"petal_cup"
const STYLE_PEBBLE := &"pebble_ring"
const STAGE_TWIGS := 0
const STAGE_MOSS_BED := 1
const STAGE_CANOPY := 2
## Twig stroke width (px) and the canopy's three flowers (radius px).
const TWIG_W := 4.0
const FLOWER_R := 11.0

static var current: NestLayer = null

var _content: GameContent
var _dp: float = 3.0
## Half size of the visual (px): friendship.json nest.visual_w_dp x visual_h_dp.
var _half: Vector2 = Vector2(72.0, 36.0)
## species -> {nest (Game.nest_state view), t (seconds on screen), pop (-1 = none)}.
var _live: Dictionary = {}
var _materials: Dictionary = {}


func _ready() -> void:
	current = self
	_content = ContentRegistry.content
	if _content != null:
		var nest: Dictionary = _content.friendship.get("nest", {})
		_dp = float((_content.spots_doc["frame"] as Dictionary)["px_per_dp"])
		_half = Vector2(float(nest.get("visual_w_dp", 48.0)), float(nest.get("visual_h_dp", 24.0))) * _dp * 0.5
		_materials = _content.palettes.get("materials", {})
	if Game.world_ready.is_connected(_on_world_ready):
		return
	Game.world_ready.connect(_on_world_ready)
	Game.nest_grew.connect(_on_nest_grew)


func _exit_tree() -> void:
	if current == self:
		current = null


func _on_world_ready(_recap: Array) -> void:
	sync()


## A stage reached (or a nest built). Offline growth arrives with the recap line and simply shows
## grown; a stage reached while watching gets the little pop.
func _on_nest_grew(species: StringName, _stage: int, offline: bool) -> void:
	sync()
	var e: Variant = _live.get(species)
	if e != null and not offline and not Settings.get_bool(Settings.REDUCE_MOTION):
		(e as Dictionary)["pop"] = 0.0
		set_process(true)


## Takes the sim's nests as the truth: a new one starts its fade, the rest refresh their stage.
func sync() -> void:
	if not Game.is_ready or Game.sim == null:
		return
	var seen := {}
	var nests := Game.nests()
	for sp: StringName in nests:
		seen[sp] = true
		if _live.has(sp):
			(_live[sp] as Dictionary)["nest"] = nests[sp]
		else:
			_live[sp] = {"nest": nests[sp], "t": 0.0, "pop": -1.0}
	for sp: StringName in _live.keys():
		if not seen.has(sp):
			_live.erase(sp)  # nests never go away in play; a fixture or a new install can swap worlds
	set_process(not _live.is_empty())
	queue_redraw()


func _process(delta: float) -> void:
	var busy := false
	for sp: StringName in _live:
		var e: Dictionary = _live[sp]
		e["t"] = float(e["t"]) + delta
		if float(e["t"]) < FADE_S:
			busy = true
		if float(e["pop"]) >= 0.0:
			e["pop"] = float(e["pop"]) + delta
			if float(e["pop"]) >= POP_S:
				e["pop"] = -1.0
			else:
				busy = true
	set_process(busy)
	queue_redraw()


## The nest's visual rect (design px) for tests and the layout debug overlay; {} without a nest.
func nest_rect(species: StringName) -> Rect2:
	var e: Variant = _live.get(species)
	if e == null:
		return Rect2()
	return Rect2(_centre((e as Dictionary)["nest"]) - _half, _half * 2.0)


## A11Y_NEST, filled with the friend's name.
func a11y_label(species: StringName) -> String:
	if not _live.has(species):
		return ""
	return I18n.fmt(&"A11Y_NEST", {"name": Game.display_name(species)})


func _centre(nest: Dictionary) -> Vector2:
	return GardenRules.frame_to_px(_content, Vector2(float(nest["x"]), float(nest["y"])))


## A material's lit / shade / detail colour (palettes.json materials), alpha applied.
func _mat(id: String, part: String, alpha: float = 1.0) -> Color:
	var m: Dictionary = _materials.get(id, {})
	var c := Color.html(String(m.get(part, "#C9BFA8")))
	c.a = alpha
	return c


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if _live.is_empty():
		return
	var tris := WorldTris.new()
	for sp: StringName in _live:
		_draw_nest(tris, _live[sp])
	tris.flush(self)


func _draw_nest(tris: WorldTris, e: Dictionary) -> void:
	var nest: Dictionary = e["nest"]
	var a := clampf(float(e["t"]) / FADE_S, 0.0, 1.0)
	if a <= 0.004:
		return
	var k := 1.0
	var pop := float(e["pop"])
	if pop >= 0.0:
		k = 1.0 + POP_K * sin(clampf(pop / POP_S, 0.0, 1.0) * PI)
	var c := _centre(nest)
	var h := _half * k
	match StringName(nest.get("style", "")):
		STYLE_MOSS:
			_moss_bowl(tris, c, h, a)
		STYLE_LEAF:
			_leaf_cradle(tris, c, h, a)
		STYLE_PETAL:
			_petal_cup(tris, c, h, a)
		_:
			_pebble_ring(tris, c, h, a)
	var stage := int(nest.get("stage", 0))
	_twigs(tris, c, h, a)
	if stage >= STAGE_MOSS_BED:
		tris.blob(c + Vector2(0.0, -h.y * 0.08), Vector2(h.x * 0.56, h.y * 0.5), _mat("moss", "lit", a))
		tris.blob(c + Vector2(-h.x * 0.1, -h.y * 0.22), Vector2(h.x * 0.3, h.y * 0.2), _mat("moss", "detail", a * 0.7))
	if stage >= STAGE_CANOPY:
		_canopy(tris, c, h, a)


func _moss_bowl(tris: WorldTris, c: Vector2, h: Vector2, a: float) -> void:
	tris.blob(c, h, _mat("moss", "shade", a))
	tris.blob(c + Vector2(0.0, -h.y * 0.12), Vector2(h.x * 0.74, h.y * 0.62), _mat("moss", "lit", a))
	tris.blob(c + Vector2(0.0, -h.y * 0.5), Vector2(h.x * 0.8, h.y * 0.22), _mat("moss", "detail", a * 0.55))


func _leaf_cradle(tris: WorldTris, c: Vector2, h: Vector2, a: float) -> void:
	var lit := _mat("willow_leaf", "lit", a)
	var shade := _mat("willow_leaf", "shade", a)
	tris.blob_rot(c + Vector2(-h.x * 0.14, h.y * 0.05), Vector2(h.x * 0.86, h.y * 0.6), -0.22, shade)
	tris.blob_rot(c + Vector2(h.x * 0.14, 0.0), Vector2(h.x * 0.86, h.y * 0.6), 0.22, lit)
	var rib := _mat("willow_leaf", "detail", a * 0.8)
	tris.stroke(c + Vector2(-h.x * 0.9, h.y * 0.25), c + Vector2(h.x * 0.6, -h.y * 0.15), 2.0, rib)
	rib.a *= 0.75
	tris.stroke(c + Vector2(h.x * 0.9, h.y * 0.2), c + Vector2(-h.x * 0.55, -h.y * 0.15), 2.0, rib)


func _petal_cup(tris: WorldTris, c: Vector2, h: Vector2, a: float) -> void:
	var n := 6
	for i in n:
		var ang := TAU * float(i) / float(n) - PI * 0.5
		var p := c + Vector2(cos(ang) * h.x * 0.58, sin(ang) * h.y * 0.58)
		var part := "lit" if i % 2 == 0 else "shade"
		tris.blob_rot(p, Vector2(h.x * 0.42, h.y * 0.5), ang, _mat("toadstool_cap", part, a))
	tris.blob(c, Vector2(h.x * 0.42, h.y * 0.42), _mat("toadstool_cap", "detail", a))


func _pebble_ring(tris: WorldTris, c: Vector2, h: Vector2, a: float) -> void:
	tris.blob(c, Vector2(h.x * 0.6, h.y * 0.5), _mat("soil", "lit", a))
	var n := 8
	for i in n:
		var ang := TAU * float(i) / float(n)
		var p := c + Vector2(cos(ang) * h.x * 0.82, sin(ang) * h.y * 0.78)
		var mat := "stone_cool" if i % 2 == 0 else "pebble_alt"
		tris.blob(p + Vector2(0.0, 2.0), Vector2(h.x * 0.2, h.y * 0.24), _mat(mat, "shade", a))
		tris.blob(p, Vector2(h.x * 0.2, h.y * 0.24), _mat(mat, "lit", a))


## Stage 0, and the base every later stage keeps: a few twigs laid across.
func _twigs(tris: WorldTris, c: Vector2, h: Vector2, a: float) -> void:
	var col := _mat("wood_bark", "shade", a * 0.9)
	tris.stroke(c + Vector2(-h.x * 0.5, h.y * 0.1), c + Vector2(h.x * 0.45, -h.y * 0.2), TWIG_W, col)
	tris.stroke(c + Vector2(-h.x * 0.4, -h.y * 0.25), c + Vector2(h.x * 0.5, h.y * 0.15), TWIG_W, col)
	tris.stroke(c + Vector2(-h.x * 0.1, -h.y * 0.4), c + Vector2(h.x * 0.15, h.y * 0.3), TWIG_W * 0.8,
			_mat("wood_bark", "lit", a * 0.9))


## Stage 2: three little flowers on stems arching over the bed.
func _canopy(tris: WorldTris, c: Vector2, h: Vector2, a: float) -> void:
	var stem := _mat("moss", "shade", a)
	var petal := _mat("toadstool_cap", "lit", a)
	var heart := _mat("pinwheel_b", "detail", a)
	for i in 3:
		var x := (float(i) - 1.0) * h.x * 0.45
		var foot := c + Vector2(x * 1.3, -h.y * 0.1)
		var head := c + Vector2(x, -h.y * 0.9 - h.y * (0.5 if i == 1 else 0.3))
		tris.stroke(foot, head, 3.0, stem)
		var r := FLOWER_R * (h.x / _half.x)
		for k in 5:
			var ang := TAU * float(k) / 5.0
			tris.blob(head + Vector2(cos(ang), sin(ang)) * r * 0.55, Vector2(r * 0.5, r * 0.5), petal, 8)
		tris.blob(head, Vector2(r * 0.32, r * 0.32), heart, 8)
