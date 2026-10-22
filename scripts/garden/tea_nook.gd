class_name TeaNook
extends Node2D
## The tea nook on the stump (Active F2 Tea & Treats; GDD §14.1-§14.2, ACTIVE_TEA §2.3, §10): a
## felt acorn teapot with its lid, a petal jar, up to three cups on the cloth and a soft steam
## wisp, in the teaware the player picked. A fixed prop (never décor), world target prio 4 with a
## 64 dp hit (WorldPan.PRIO_TEA_NOOK): touch-down squashes it 0.94 with S01 and the touch ring in
## the same frame; a tap (release-to-fire) emits [signal open_requested] (HUD: the Tea sheet).
## A long-press does nothing special (Active F3's long-press-to-edit never collides with it).
##
## It appears when the nook wakes (Game.tea_nook_awake: a 400 ms fade with a steam puff and S34)
## or is simply there for a returning player; until the first brew it twinkles with the standard
## "something new" sparkle (never a dot). Petals gathered from a bed arc into its jar, which bobs
## once (PlotsLayer -> [method catch_petals]); an offered cup arcs from it to the friend
## ([method send_cup]). All sprites share one atlas and one lit material (tea_nook.gdshader): the
## nook costs one draw call (two while a cup or the sparkle flies).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

signal open_requested

const SHADER_PATH := "res://shaders/props/tea_nook.gdshader"
const KEY := &"tea_nook"
const CUE_TOUCH := &"S01"
const CUE_AWAKE := &"S34"
## The nook's pieces at 1/3.6 of the sheet's teapot (~42 dp wide on the stump).
const POT_SCALE := 0.3
const JAR_SCALE := 0.36
const CUP_SCALE := 0.3
const CLOTH_SCALE := 0.62
## Pieces relative to the foot (design px): the teapot sits on the stump top's centre.
const FOOT_FROM_HIT := Vector2(0.0, 30.0)
const JAR_AT := Vector2(-50.0, 2.0)
const CUP_AT: Array[Vector2] = [Vector2(48.0, 6.0), Vector2(66.0, -4.0), Vector2(34.0, -8.0)]
const STEAM_AT := Vector2(-6.0, -96.0)
const SQUASH := 0.94
const FADE_IN_S := 0.4
const BOB_S := 0.45
const FLY_S := 0.32
const TWINKLE_PERIOD_S := 2.2
## Sorts in front of the stump's front face and moss (props_atlas stump_front sort_y 86).
const SORT_FROM_STUMP := 88.0

static var current: TeaNook = null

var content: GameContent
var hit_centre := Vector2.ZERO
var hit_radius: float = 96.0
## The teapot's foot in this node's space.
var foot := Vector2.ZERO
var _mat: ShaderMaterial
var _colors: Dictionary = {}
var _tray: Array[Dictionary] = []
var _glow: bool = false
var _twinkle: bool = false
var _jar_fill: float = 0.0
var _press: Spring
var _pressed: bool = false
var _t: float = 0.0
var _fade: float = 1.0
var _bob: float = -1.0
var _fly_t: float = -1.0
var _fly_from := Vector2.ZERO
var _fly_to := Vector2.ZERO
var _fly_tea := Color.WHITE
var _fly_treat: bool = false
var _qa_frozen: bool = false


func _ready() -> void:
	current = self
	add_to_group(WorldPan.GROUP_HIT)
	content = ContentRegistry.content
	var nook: Dictionary = content.tea.get("nook", {})
	var frame: Dictionary = content.spots_doc["frame"]
	var dp := float(frame["px_per_dp"])
	hit_centre = GardenRules.frame_to_px(content, Vector2(float(nook.get("x", 0.9)), float(nook.get("y", 0.4))))
	hit_radius = float(nook.get("hit_dp", 64.0)) * dp * 0.5
	var stump := PropsLayer.prop_centre(content, StringName(String(nook.get("on_prop", "stump"))))
	position = Vector2(hit_centre.x, stump.y + SORT_FROM_STUMP)
	foot = hit_centre + FOOT_FROM_HIT - position
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH) as Shader
	material = _mat
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var box := Rect2(foot + Vector2(-110.0, -130.0), Vector2(220.0, 140.0))
	set_instance_shader_parameter(&"i_box", Vector4(box.position.x, box.position.y, box.size.x, box.size.y))
	_press = Motion.spring(&"press", 1.0)
	Game.tea_nook_awake.connect(_on_awake)
	Game.sim_event.connect(_on_sim_event)
	Game.teaware_changed.connect(func(_slot: StringName, _id: StringName) -> void: sync())
	Game.world_ready.connect(func(_r: Array) -> void: sync())
	tree_exiting.connect(func() -> void:
		if current == self:
			current = null)
	sync()


func is_awake() -> bool:
	return Game.sim != null and Game.tea_unlocked()


## Re-reads teaware, tray and unlock state from Game.
func sync() -> void:
	if Game.sim == null:
		visible = false
		return
	visible = is_awake()
	var tw: Dictionary = Game.teaware().get("in_use", {})
	_colors = {"pot": TeaArt.teaware_colors(StringName(String(tw.get("teapot", "acorn_teapot")))),
		"cup": TeaArt.teaware_colors(StringName(String(tw.get("cup", "walnut_cup")))),
		"cloth": TeaArt.teaware_colors(StringName(String(tw.get("cloth", "moss_mat"))))}
	_glow = bool((_colors["pot"] as Dictionary)["glow"]) or bool((_colors["cup"] as Dictionary)["glow"])
	set_instance_shader_parameter(&"i_fx", Vector4(1.0 if _glow else 0.0, 1.0, 0.0, 0.0))
	_tray = Game.tray()
	var total := 0
	var pantry := Game.pantry()
	for f: String in pantry:
		total += int(pantry[f])
	_jar_fill = clampf(float(total) / 24.0, 0.0, 1.0)
	_twinkle = Game.recipes_found().is_empty()
	queue_redraw()
	set_process(visible)


func _on_awake() -> void:
	sync()
	_fade = 0.0
	modulate.a = 0.0
	TeaArt.cue(CUE_AWAKE, {"world": true, "position": get_global_transform() * foot}, {})
	FrameGovernor.hold_for(FADE_IN_S + 0.1)
	set_process(true)


func _on_sim_event(ev: Dictionary) -> void:
	match StringName(String(ev.get("type", ""))):
		WorldSim.EV_BREWED, WorldSim.EV_TEA_OFFERED, WorldSim.EV_PETALS, WorldSim.EV_RECIPE_FOUND:
			sync()


## A gather's petals arrived (PlotsLayer): the pantry jar bobs once.
func catch_petals() -> void:
	_bob = 0.0
	sync()
	set_process(true)


## Where gathered petals fly to (PlotsLayer / design px: the jar's mouth).
func jar_point() -> Vector2:
	return position + foot + JAR_AT + Vector2(0.0, -58.0)


## An offered cup arcs from the nook to [param species] (320 ms; ACTIVE_TEA §7 step 2).
func send_cup(species: StringName, tea: Color, treat: bool) -> void:
	var to := _friend_point(species)
	if to == Vector2.INF or not visible:
		return
	_fly_from = foot + CUP_AT[0]
	_fly_to = to - position
	_fly_t = 0.0
	_fly_tea = tea
	_fly_treat = treat
	FrameGovernor.hold_for(FLY_S + 0.1)
	set_process(true)


func _friend_point(species: StringName) -> Vector2:
	var layer := get_tree().root.find_child("CreatureLayer", true, false)
	if layer == null:
		return Vector2.INF
	for n: Node in layer.find_children("*", "Node2D", true, false):
		if n is Mossling and (n as Mossling).species_id == species:
			var g := (n as Node2D).global_position
			return (get_parent() as Node2D).get_global_transform().affine_inverse() * g + Vector2(18.0, -30.0)
	return Vector2.INF


func _process(delta: float) -> void:
	if _qa_frozen:
		return
	_t += delta
	var busy := false
	if _fade < 1.0:
		_fade = minf(_fade + delta / FADE_IN_S, 1.0)
		modulate.a = _fade
		busy = true
	if not _press.is_at_rest() or _press.target != 1.0:
		_press.step(delta)
		busy = true
	if _bob >= 0.0:
		_bob += delta
		if _bob >= BOB_S:
			_bob = -1.0
		busy = true
	if _fly_t >= 0.0:
		_fly_t += delta
		if _fly_t >= FLY_S:
			_fly_t = -1.0
		busy = true
	queue_redraw()
	if busy:
		FrameGovernor.poke()


func _draw() -> void:
	if _colors.is_empty():
		return
	var sq := _press.value
	# squash about the teapot's foot (0.94, volume-preserving)
	var k := Vector2(1.0 / maxf(sq, 0.5), sq)
	var at := func(p: Vector2) -> Vector2: return foot + (p * k)
	var pot: Dictionary = _colors["pot"]
	var cup: Dictionary = _colors["cup"]
	var cloth: Dictionary = _colors["cloth"]
	TeaArt.draw(self, &"cloth", at.call(Vector2(0.0, 2.0)), CLOTH_SCALE * sq, 0.0, cloth["body"])
	# the pantry jar (bobs once when petals arrive)
	var jb := 1.0
	if _bob >= 0.0:
		var u := clampf(_bob / BOB_S, 0.0, 1.0)
		jb = 1.0 + 0.12 * sin(PI * u) * (1.0 - u)
	var jar_at: Vector2 = at.call(JAR_AT)
	TeaArt.draw(self, &"jar_back", jar_at, JAR_SCALE * jb, 0.0, Color(1, 1, 1, 0.75 + 0.25 * _jar_fill))
	var pile := roundi(_jar_fill * 5.0)
	var flowers := Game.pantry().keys() if pile > 0 else []
	for i in pile:
		var f := StringName(str(flowers[i % flowers.size()]))
		var j := TeaArt.scatter(i, 31)
		TeaArt.draw(self, &"petal", jar_at + Vector2((j.x - 0.5) * 30.0, -14.0 - float(i / 2) * 9.0) * jb, 0.32 * jb, 0.0,
				TeaArt.flower_color(f))
	TeaArt.draw(self, &"jar_front", jar_at, JAR_SCALE * jb)
	# cups on the cloth (at most cups_drawn_max)
	var max_cups := int(TeaArt.tea_num("nook", "cups_drawn_max", 3))
	for i in mini(_tray.size(), mini(max_cups, CUP_AT.size())):
		var c: Dictionary = _tray[i]
		var p: Vector2 = at.call(CUP_AT[i])
		if StringName(String(c.get("kind", "tea"))) == TeaRules.KIND_TREAT:
			TeaArt.draw(self, &"mould", p, CUP_SCALE * 0.9)
			TeaArt.draw(self, &"treat", p + Vector2(0.0, -6.0), CUP_SCALE * 0.9, 0.0,
					TeaArt.recipe_color(StringName(String(c.get("recipe", ""))), c.get("petals", [])))
		else:
			TeaArt.draw(self, &"cup", p, CUP_SCALE, 0.0, cup["body"])
			TeaArt.draw(self, &"cup_tea", p + Vector2(-0.3, -22.8), CUP_SCALE, 0.0,
					TeaArt.recipe_color(StringName(String(c.get("recipe", ""))), c.get("petals", [])))
	TeaArt.draw(self, &"pot_body", at.call(Vector2.ZERO), POT_SCALE * sq, 0.0, pot["body"])
	TeaArt.draw(self, &"pot_cap", at.call(Vector2(0.0, -46.0)), POT_SCALE * 0.95 * sq, 0.0, pot["cap"])
	# the steam wisp breathes and sways (V5: slow); the "new" sparkle twinkles until the first brew
	var w := 0.0 if Motion.reduce_motion else sin(_t * TAU / 4.0)
	TeaArt.draw(self, &"steam", at.call(STEAM_AT) + Vector2(w * 3.0, -2.0 * w), 0.32, 0.0,
			Color(1, 1, 1, 0.45 + 0.25 * (0.5 + 0.5 * sin(_t * TAU / 3.1))))
	if _twinkle:
		var tk := 0.5 + 0.5 * sin(_t * TAU / TWINKLE_PERIOD_S)
		TeaArt.draw(self, &"sparkle", at.call(Vector2(40.0, -92.0)), 0.3 + 0.16 * tk, 0.0, Color(1, 1, 1, 0.45 + 0.55 * tk))
	if _fly_t >= 0.0:
		var u2 := clampf(_fly_t / FLY_S, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - u2, 3.0)
		var fp := _fly_from.lerp(_fly_to, e) + Vector2(0.0, -sin(PI * e) * 120.0)
		if _fly_treat:
			TeaArt.draw(self, &"treat", fp, CUP_SCALE * 0.9, 0.0, _fly_tea)
		else:
			TeaArt.draw(self, &"cup", fp, CUP_SCALE, 0.0, cup["body"])
			TeaArt.draw(self, &"cup_tea", fp + Vector2(-0.3, -22.8), CUP_SCALE, 0.0, _fly_tea)


# ------------------------------------------------------------------ world target (WorldPan)

func world_hit(canvas_pos: Vector2, slop: float) -> Dictionary:
	if not visible or Game.sim == null:
		return {}
	var pos := (get_parent() as Node2D).get_global_transform_with_canvas().affine_inverse() * canvas_pos
	return WorldPan.circle_hit(pos, hit_centre, hit_radius, slop, WorldPan.PRIO_TEA_NOOK, KEY)


func world_press(_key: Variant, canvas_pos: Vector2) -> void:
	var pos := (get_parent() as Node2D).get_global_transform_with_canvas().affine_inverse() * canvas_pos
	_pressed = true
	_press = Motion.spring(&"press", _press.value)
	_press.target = SQUASH
	var ring := TouchRing.spawn(self, pos - position)
	ring.z_index = 1
	queue_redraw()
	AudioDirector.play_cue(CUE_TOUCH, {"world": true, "position": get_global_transform() * (pos - position)})
	FrameGovernor.hold_for(Motion.duration(&"short"))
	set_process(true)


func world_release(_key: Variant, _canvas_pos: Vector2, act: bool) -> void:
	if not _pressed:
		return
	_pressed = false
	var pop := Motion.spring(&"pop", _press.value)
	pop.velocity = _press.velocity
	pop.target = 1.0
	_press = pop
	set_process(true)
	if act:
		open_requested.emit()


func world_hit_shapes() -> Array:
	if not visible:
		return []
	var xf := (get_parent() as Node2D).get_global_transform_with_canvas()
	return [{"kind": "circle", "c": xf * hit_centre, "r": hit_radius * xf.get_scale().x, "prio": WorldPan.PRIO_TEA_NOOK,
		"name": "tea_nook"}]


## QA: hold the current pose (captures).
func qa_freeze() -> void:
	_qa_frozen = true
