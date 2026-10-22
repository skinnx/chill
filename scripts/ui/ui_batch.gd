class_name UiBatch
extends RefCounted
## Draw-order layering for the sheets and modal cards (round 5, Art Bible §4.19 budget; QA r4
## blocker: 130-152 draw calls with a sheet open). The GLES3 canvas batcher merges consecutive
## draws that share material, texture and clip; built in tree order a card list alternates
## surface / portrait / text / icon / surface ..., so every card cost 4-5 calls. A batch root
## (a sheet or a modal card) instead gives every drawing leaf an absolute z by KIND:
##
##   band (chrome 0 | scroll SCROLL_BAND) + SURF + nesting depth   UiSurface (one material: 1 call)
##   band + RIPPLE                                                  press ripples (only while pressed)
##   band + TEX + atlas index                                       icons, baked wells (1 per atlas)
##   band + OVERLAY                                                 other shader rects (rings)
##   band + TEXT + font class                                       labels / button text (1 per font+size)
##
## so the whole sheet draws in about a dozen calls whatever its length. The scroll band sits
## entirely above the chrome band, so the scroll's clip rect changes once. Textured leaves take the
## shared content material (scroll-edge fade, rounded baked wells). Live sub-scenes (CreaturePortrait,
## ItemPreview, LiveWell) keep their own internal order and draw at band + MISC.
##
## Nodes added later (refreshes, ripples, swapped labels) are placed as they enter the tree.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const CONTENT_SHADER := "res://shaders/ui/content.gdshader"
const META_ROOT := &"ui_batch_root"
const META_SCROLL := &"ui_batch_scroll"
const META_KEYS := &"ui_batch_keys"
const META_BASE := &"ui_batch_base"
## Offsets inside a band.
const SURF := 1
const SURF_MAX_DEPTH := 8
const RIPPLE := 10
const MISC := 11
const TEX := 12
const TEX_SLOTS := 6
## Shader-drawn decorations over the wells (the dew cup's level ring).
const OVERLAY := 18
const TEXT := 19
const TEXT_SLOTS := 10
const SCROLL_BAND := 30
## Scroll-edge fade bands, px (QA r4: the 72 px fade read as an overlap bug; 96 px at the bottom).
## Round 6: the fades are the scroll affordance and only show where more content waits (UiSheet
## grows each band in with the distance left to scroll), so they can be clearly visible.
const FADE_TOP_PX := 48.0
const FADE_BOTTOM_PX := 120.0

const META_ALPHA := &"ui_batch_alpha"
const META_WELL := &"ui_batch_well"

## Content materials by "fade|alpha|well" (no instance uniforms: that buffer is the world's).
static var _content: Dictionary = {}
static var _window := Vector4(-1e6, -1e6, 1e6, 1e6)
static var _bands := Vector2(FADE_TOP_PX, FADE_BOTTOM_PX)


static func content_material(fade: bool = false, a: float = 1.0, well: bool = false) -> ShaderMaterial:
	var key := "%d|%.2f|%d" % [int(fade), a, int(well)]
	var hit: Variant = _content.get(key)
	if hit is ShaderMaterial:
		return hit
	var m := ShaderMaterial.new()
	m.shader = load(CONTENT_SHADER) as Shader
	m.set_shader_parameter(&"u_band", _bands)
	m.set_shader_parameter(&"u_window", _window)
	m.set_shader_parameter(&"u_fade", 1.0 if fade else 0.0)
	m.set_shader_parameter(&"u_alpha", a)
	m.set_shader_parameter(&"u_unpremultiply", 1.0 if well else 0.0)
	_content[key] = m
	return m


static func release_shared() -> void:
	_content = {}


## Per-leaf opacity of a textured leaf (empty hearts, dim drops, the switch's check) WITHOUT its
## modulate: differing modulates break the GLES3 batch (it compares each item's final modulate),
## so the leaf takes an alpha variant of the content material (and its own z slot).
static func set_alpha(leaf: CanvasItem, a: float) -> void:
	leaf.set_meta(META_ALPHA, snappedf(a, 0.05))
	if _root_of(leaf) != null:
		place(leaf)


## Baked wells take the un-premultiplying content variant.
static func mark_well(leaf: CanvasItem) -> void:
	leaf.set_meta(META_WELL, true)


## The scroll window (canvas px rect) the fading content melts into and its fade bands (top px,
## bottom px), on every shared material.
static func set_window(r: Rect2, bands: Vector2 = Vector2(FADE_TOP_PX, FADE_BOTTOM_PX)) -> void:
	_window = Vector4(r.position.x, r.position.y, r.end.x, r.end.y)
	_bands = bands
	var mats: Array[ShaderMaterial] = UiSurface.shared_materials().duplicate()
	for m: Variant in _content.values():
		mats.append(m as ShaderMaterial)
	for m: ShaderMaterial in mats:
		m.set_shader_parameter(&"u_window", _window)
		m.set_shader_parameter(&"u_band", _bands)


## Makes [param root] a batch root at absolute z [param base] and layers its whole subtree; nodes
## that enter it later are layered as they arrive.
static func adopt(root: Control, base: int) -> void:
	root.set_meta(META_ROOT, true)
	root.set_meta(META_BASE, base)
	root.set_meta(META_KEYS, {})
	root.z_as_relative = false
	root.z_index = base
	_walk(root, root)
	var tree := root.get_tree()
	if tree != null:
		var cb := func(n: Node) -> void:
			if is_instance_valid(root) and root.is_ancestor_of(n):
				place(n)
		tree.node_added.connect(cb)
		root.tree_exiting.connect(func() -> void:
			if tree.node_added.is_connected(cb):
				tree.node_added.disconnect(cb))


## Marks [param scroll] (inside a batch root) as the fading scroll band.
static func mark_scroll(scroll: Control) -> void:
	scroll.set_meta(META_SCROLL, true)


## Layers one node (and its subtree) that is inside a batch root.
static func place(n: Node) -> void:
	var root := _root_of(n)
	if root == null:
		return
	_walk(n, root)


static func _walk(n: Node, root: Control) -> void:
	if n != root:
		_place_one(n, root)
	if _is_opaque_scene(n):
		return
	for c: Node in n.get_children(true):
		_walk(c, root)


static func _root_of(n: Node) -> Control:
	var p := n
	while p != null:
		if p is Control and p.has_meta(META_ROOT):
			return p as Control
		p = p.get_parent()
	return null


## Live sub-scenes keep their own internal draw order.
static func _is_opaque_scene(n: Node) -> bool:
	return n is CreaturePortrait or n is ItemPreview or n is LiveWell or not (n is Control)


static func _place_one(n: Node, root: Control) -> void:
	var ci := n as CanvasItem
	if ci == null or (n.get_parent() is GlassPanel and n.name == &"Glass"):
		return
	# Nodes inside a live sub-scene are left alone.
	var p := n.get_parent()
	while p != null and p != root:
		if _is_opaque_scene(p) and p != n:
			return
		p = p.get_parent()
	var scroll := _in_scroll(n, root)
	var band := int(root.get_meta(META_BASE, 0)) + (SCROLL_BAND if scroll else 0)
	var want := -1
	if n is UiSurface:
		want = band + SURF + mini(_surface_depth(n, root), SURF_MAX_DEPTH)
		ci.material = UiSurface.shared_material(scroll)
	elif n is ColorRect and n.name == &"Ripple":
		want = band + RIPPLE
	elif _is_opaque_scene(n):
		want = band + MISC
	elif n is ColorRect and (n as ColorRect).material != null:
		want = band + OVERLAY
	elif n is TextureRect:
		var t := (n as TextureRect).texture
		var mk := _content_leaf(ci, scroll)
		want = band + TEX + _slot(root, "tex", _tex_key(t) + mk, TEX_SLOTS)
	elif n is Label or n is LineEdit or n is RichTextLabel or (n is Button and (n as Button).text != ""):
		var c := n as Control
		var rich := n is RichTextLabel
		var f := c.get_theme_font(&"normal_font" if rich else &"font")
		var fs := c.get_theme_font_size(&"normal_font_size" if rich else &"font_size")
		var key := "%d|%d" % [f.get_rid().get_id() if f != null else 0, fs]
		if n is Label:
			# polish (draw calls): the label's content-material variant (its per-leaf alpha) is part
			# of its slot, as for textures, so dimmed and plain labels of one font no longer
			# alternate materials inside one z layer (8 Garden labels cost 5 calls)
			key += _content_leaf(ci, scroll)
		want = band + TEXT + _slot(root, "font", key, TEXT_SLOTS)
	if want < 0:
		# non-drawing containers: keep their parent's absolute z
		ci.z_as_relative = true
		ci.z_index = 0
		return
	ci.z_as_relative = true
	ci.z_index = want - _parent_abs(n)


## Gives a textured leaf its content material variant; returns the variant key (z slot part).
static func _content_leaf(ci: CanvasItem, scroll: bool) -> String:
	var own := ci.material != null and not _content.values().has(ci.material)
	if own:
		return "|own"
	var a := float(ci.get_meta(META_ALPHA, 1.0))
	var well := bool(ci.get_meta(META_WELL, false))
	ci.material = content_material(scroll, a, well)
	return "|%.2f|%d" % [a, int(well)]


static func _tex_key(t: Texture2D) -> String:
	if t is AtlasTexture and (t as AtlasTexture).atlas != null:
		return str((t as AtlasTexture).atlas.get_rid().get_id())
	return str(t.get_rid().get_id()) if t != null else "none"


static func _slot(root: Control, kind: String, key: String, slots: int) -> int:
	var keys: Dictionary = root.get_meta(META_KEYS, {})
	var k := kind + ":" + key
	if not keys.has(k):
		var n := 0
		for e: String in keys:
			if e.begins_with(kind + ":"):
				n += 1
		keys[k] = mini(n, slots - 1)
		root.set_meta(META_KEYS, keys)
	return int(keys[k])


static func _in_scroll(n: Node, root: Control) -> bool:
	var p := n
	while p != null and p != root:
		if p.has_meta(META_SCROLL):
			return true
		p = p.get_parent()
	return false


static func _surface_depth(n: Node, root: Control) -> int:
	var d := 0
	var p := n.get_parent()
	while p != null and p != root:
		if p.has_meta(UiSurface.META_OWNER):
			d += 1
		p = p.get_parent()
	return d


## The absolute z of [param n]'s parent.
static func _parent_abs(n: Node) -> int:
	var p := n.get_parent() as CanvasItem
	var z := 0
	while p != null:
		z += p.z_index
		if not p.z_as_relative:
			return z
		p = p.get_parent() as CanvasItem
	return z
