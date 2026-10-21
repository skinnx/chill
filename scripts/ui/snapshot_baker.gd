class_name SnapshotBaker
extends Node
## One-shot bakes of the UI's mini-renders into a shared atlas page (round 5, Art Bible §4.19; QA r4
## blocker: twelve live Album portraits and the Garden's live flower wells cost one or more draw
## calls each). Every request made during a frame (a sheet building its grid) is drawn once, next
## frame, into ONE transient SubViewport laid out as a grid of cells, read back after
## frame_post_draw into an ImageTexture and handed out as AtlasTextures; the SubViewport is freed
## right away (no live SubViewport is ever kept for art: §4.19). All the wells of a sheet then draw
## from one texture in a single batch (UiBatch). Cells are cached by key until the light they were
## baked in changes (the caller puts that in the key).
##
## Without a readable renderer (headless tests) [method request] returns null and callers keep the
## live node instead.

# Data boundary: queued jobs are untyped [size, make] arrays; each element is converted
# explicitly where it is read (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

signal baked(key: String, texture: Texture2D)

## Cells are padded so bilinear filtering never bleeds between neighbours.
const CELL_GAP := 4
## Atlas pages stay within the GLES3 mobile texture limit.
const PAGE_MAX_W := 2048
const PAGE_MAX_H := 4096

static var current: SnapshotBaker

var _cache: Dictionary = {}
## key -> [size: Vector2i, make: Callable] waiting for the next bake.
var _queue: Dictionary = {}
var _busy: bool = false


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null
	_cache.clear()


static func can_bake() -> bool:
	return current != null and DisplayServer.get_name() != "headless"


## The cached texture of [param key], or null (then [signal baked] fires once it is ready, if a
## [param make] callable was given: make(cell_size: Vector2) -> Control fills the cell).
func request(key: String, size: Vector2i, make: Callable) -> Texture2D:
	var hit: Variant = _cache.get(key)
	if hit is Texture2D:
		return hit
	if not _queue.has(key):
		_queue[key] = [size, make]
		if not _busy:
			_bake.call_deferred()
	return null


func has(key: String) -> bool:
	return _cache.has(key)


func forget(prefix: String) -> void:
	for k: String in _cache.keys():
		if k.begins_with(prefix):
			_cache.erase(k)


func _bake() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	var jobs := _queue
	_queue = {}
	# shelf-pack the cells into one page
	var keys: Array = jobs.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return (jobs[a][0] as Vector2i).y > (jobs[b][0] as Vector2i).y)
	var rects: Dictionary = {}
	var x := 0
	var y := 0
	var shelf := 0
	var page_w := 0
	for k: String in keys:
		var s: Vector2i = jobs[k][0]
		if x + s.x > PAGE_MAX_W:
			x = 0
			y += shelf + CELL_GAP
			shelf = 0
		if y + s.y > PAGE_MAX_H:
			break
		rects[k] = Rect2i(Vector2i(x, y), s)
		x += s.x + CELL_GAP
		shelf = maxi(shelf, s.y)
		page_w = maxi(page_w, x)
	var page := Vector2i(maxi(page_w, 1), maxi(y + shelf, 1))
	var vp := SubViewport.new()
	vp.name = "Bake"
	vp.size = page
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	add_child(vp)
	for k: String in rects:
		var r: Rect2i = rects[k]
		var make: Callable = jobs[k][1]
		var cell: Control = make.call(Vector2(r.size))
		if cell == null:
			continue
		vp.add_child(cell)
		# sized inside the tree, so `resized` reaches the cell (LiveWell, portrait fit)
		cell.position = Vector2(r.position)
		cell.size = Vector2(r.size)
	# two frames: containers sort and the rig poses, then the page draws once
	await get_tree().process_frame
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image() if is_instance_valid(vp) else null
	if is_instance_valid(vp):
		vp.queue_free()
	_busy = false
	if img == null or img.is_empty():
		_bake.call_deferred()
		return
	var tex := ImageTexture.create_from_image(img)
	for k: String in rects:
		var a := AtlasTexture.new()
		a.atlas = tex
		a.region = Rect2(rects[k])
		_cache[k] = a
		baked.emit(k, a)
	if not _queue.is_empty():
		_bake.call_deferred()
