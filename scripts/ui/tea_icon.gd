class_name TeaIcon
extends Control
## A small felt picture from the tea atlas for the Tea sheet's cards (Active F2, ACTIVE_TEA §10):
## a cup of tea or a treat on its leaf in the recipe's colour, a recipe still to find (a soft
## silhouette), a teaware piece in its colours, or a petal mix. Fitted into the control's rect.
## Every TeaIcon of a sheet draws from one texture at one z slot (above the cards' surfaces), so a
## whole recipe grid costs one batch; in a scroll list it takes the shared fading content material.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

enum Kind { RECIPE, SECRET, TEAPOT, CUP, CLOTH, MIX }

var kind: Kind = Kind.RECIPE
var recipe: StringName = &""
var teaware: StringName = &""
## Flower ids of a MIX (repeats count) plus [member drops] dew drops.
var mix: Array = []
var drops: int = 0
var glow: float = 0.0
## Extra z above the usual slot (an icon on a card that is itself lifted, the reveal).
var z_extra: int = 0


static func of_recipe(id: StringName, found: bool, px: Vector2) -> TeaIcon:
	var t := TeaIcon.new()
	t.kind = Kind.RECIPE if found else Kind.SECRET
	t.recipe = id
	t.custom_minimum_size = px
	return t


static func of_teaware(id: StringName, px: Vector2) -> TeaIcon:
	var t := TeaIcon.new()
	var x: Dictionary = ContentRegistry.content.teaware_by_id.get(id, {})
	match String(x.get("slot", "cup")):
		"teapot":
			t.kind = Kind.TEAPOT
		"cloth":
			t.kind = Kind.CLOTH
		_:
			t.kind = Kind.CUP
	t.teaware = id
	t.custom_minimum_size = px
	return t


static func of_mix(petals: Array, p_drops: int, px: Vector2) -> TeaIcon:
	var t := TeaIcon.new()
	t.kind = Kind.MIX
	t.mix = petals
	t.drops = p_drops
	t.custom_minimum_size = px
	return t


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_lift_z.call_deferred()


## Above the card surfaces and the duotone icons, below the text (UiBatch layers a plain Control
## at its parent's z); scroll content fades with the shared content material.
func _lift_z() -> void:
	var root := UiBatch._root_of(self)
	if root == null:
		return
	var scroll := UiBatch._in_scroll(self, root)
	var band := int(root.get_meta(UiBatch.META_BASE, 0)) + (UiBatch.SCROLL_BAND if scroll else 0)
	material = UiBatch.content_material(scroll)
	z_as_relative = true
	z_index = band + UiBatch.TEX + UiBatch.TEX_SLOTS - 1 + _lifted_by() + z_extra - UiBatch._parent_abs(self)


## How far an ancestor was lifted above its layer after placement (the reveal card).
func _lifted_by() -> int:
	var p := get_parent()
	var n := 0
	while p != null and not p.has_meta(UiBatch.META_ROOT):
		if p.has_meta(&"tea_lift"):
			n += int(p.get_meta(&"tea_lift"))
		p = p.get_parent()
	return n


func _draw() -> void:
	var c := size * 0.5
	var k := minf(size.x, size.y)
	match kind:
		Kind.RECIPE, Kind.SECRET:
			_draw_recipe(c, k)
		Kind.TEAPOT:
			var tw := TeaArt.teaware_colors(teaware)
			var s := k / 470.0
			TeaArt.draw(self, &"pot_body", c + Vector2(0.0, 150.0 * s), s, 0.0, tw["body"])
			TeaArt.draw(self, &"pot_cap", c + Vector2(-8.0, -30.0) * s * 1.0, s * 0.92, 0.0, tw["cap"])
		Kind.CUP:
			var tw2 := TeaArt.teaware_colors(teaware)
			var s2 := k / 190.0
			TeaArt.draw(self, &"cup", c + Vector2(0.0, 50.0 * s2), s2, 0.0, tw2["body"])
			TeaArt.draw(self, &"cup_tea", c + Vector2(-1.0, -26.0) * s2, s2, 0.0, TeaArt.liquid_color(["sweet_clover"]))
		Kind.CLOTH:
			var tw3 := TeaArt.teaware_colors(teaware)
			var s3 := k / 300.0
			TeaArt.draw(self, &"cloth", c + Vector2(0.0, 10.0 * s3), s3, 0.0, tw3["body"])
		Kind.MIX:
			_draw_mix()


func _draw_recipe(c: Vector2, k: float) -> void:
	var r: Dictionary = ContentRegistry.content.recipes_by_id.get(recipe, {})
	var treat := String(r.get("kind", "tea")) == "treat"
	var col := TeaArt.recipe_color(recipe)
	var line := Color.WHITE
	if kind == Kind.SECRET:
		# a soft felt silhouette: never a lock, never a question mark
		col = UiTokens.sc_tinted(&"ink", 0.16)
		line = UiTokens.sc_tinted(&"ink", 0.16)
	if treat:
		var s := k / 190.0
		TeaArt.draw(self, &"mould", c + Vector2(0.0, 44.0 * s), s, 0.0, line)
		TeaArt.draw(self, &"treat", c + Vector2(0.0, 34.0 * s), s * 1.05, 0.0, col)
	else:
		var s2 := k / 175.0
		var cup := TeaArt.teaware_colors(TeaArt.in_use("cup"))
		var cup_col: Color = cup["body"] if kind == Kind.RECIPE else line
		TeaArt.draw(self, &"cup", c + Vector2(0.0, 52.0 * s2), s2, 0.0, cup_col)
		TeaArt.draw(self, &"cup_tea", c + Vector2(-1.0, -24.0) * s2, s2, 0.0, col)
		if kind == Kind.RECIPE:
			TeaArt.draw(self, &"steam", c + Vector2(-14.0, -30.0) * s2, s2 * 0.42, 0.0, Color(1, 1, 1, 0.75))
	if glow > 0.0:
		TeaArt.draw(self, &"sparkle", c + Vector2(k * 0.34, -k * 0.3), k / 140.0, 0.2, Color(1, 1, 1, glow))


## A row of the mix: one petal per petal, then the dew drops.
func _draw_mix() -> void:
	var n := mix.size() + drops
	if n == 0:
		return
	var step := minf(size.x / float(n), size.y * 0.95)
	var x0 := (size.x - step * float(n)) * 0.5 + step * 0.5
	var s := step / 64.0 * 0.82
	for i in mix.size():
		var col := TeaArt.flower_color(StringName(str(mix[i])))
		TeaArt.draw(self, &"petal", Vector2(x0 + step * i, size.y * 0.5), s, 0.25, col)
	for d in drops:
		TeaArt.draw(self, &"drop", Vector2(x0 + step * (mix.size() + d), size.y * 0.5 + 30.0 * s), s * 0.72)
