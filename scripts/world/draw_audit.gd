class_name DrawAudit
extends Node
## QA user arg --qa-draw-audit (round-3 directive 5): measures the full frame's draw calls
## (RENDER_TOTAL_DRAW_CALLS_IN_FRAME), then hides one layer at a time and prints what each layer
## costs, so every team can see its share of the <= 100 budget:
##   tools/qa/capture.sh still --size=1080x2400 --tod=0.6 --fixture=garden_full --qa-creatures=6 \
##       --qa-draw-audit --frames=200 --out=none
## Output lines start with "qa-draw-audit:". Added by ValueFrame only when the arg is present.

const ARG := "--qa-draw-audit"
const ARG_LEAVES := "--qa-draw-audit-leaves"
const SETTLE_FRAMES := 30
const STEP_FRAMES := 4
## Layers measured (paths under the main scene root), world first, then the HUD.
const LAYERS: Array[String] = [
	"World/Sky", "World/Celestial", "World/FarHills", "World/MidHills", "World/Ground/Meadow",
	"World/Ground/Stream", "World/Ground/Play/Props", "World/Ground/Play/Props/PropsLayer/Grass",
	"World/Ground/Play/Props/PropsLayer/Shadows", "World/Ground/Play/Plots",
	"World/Ground/Play/Decor", "World/Ground/Play/Creatures", "World/Ground/Particles",
	"World/Foreground", "HUD",
]


static func requested() -> bool:
	return OS.get_cmdline_user_args().has(ARG)


func _ready() -> void:
	_run.call_deferred()


func _calls() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _run() -> void:
	await _wait(SETTLE_FRAMES)
	var root := get_tree().current_scene
	var total := _calls()
	print("qa-draw-audit: total %d" % total)
	var sum := 0
	for path: String in LAYERS:
		var n := root.get_node_or_null(path)
		if n == null or not (n is CanvasItem or n is CanvasLayer):
			print("qa-draw-audit: %s missing" % path)
			continue
		n.set(&"visible", false)
		await _wait(STEP_FRAMES)
		var without := _calls()
		n.set(&"visible", true)
		await _wait(STEP_FRAMES)
		sum += total - without
		print("qa-draw-audit: %-28s %3d" % [path, total - without])
	print("qa-draw-audit: layers sum %d of %d (rest: viewport / blit)" % [sum, total])
	if OS.get_cmdline_user_args().has(ARG_LEAVES):
		await _run_leaves(root)


## --qa-draw-audit-leaves: every drawing node under World on its own (hidden alone for a few
## frames); prints the ones whose absence changes the frame's draw calls, so batch breakers show.
func _run_leaves(root: Node) -> void:
	var world := root.get_node_or_null(^"World")
	if world == null:
		return
	var stack: Array[Node] = [world]
	var leaves: Array[CanvasItem] = []
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			stack.append(c)
		if n is CanvasItem and n != world and (n as CanvasItem).is_visible_in_tree():
			var ci := n as CanvasItem
			if ci.get_child_count() == 0 or n is MultiMeshInstance2D or n is MeshInstance2D or n is GPUParticles2D:
				leaves.append(ci)
	for ci: CanvasItem in leaves:
		var base := _calls()
		ci.visible = false
		await _wait(2)
		var without := _calls()
		ci.visible = true
		await _wait(2)
		if base != without:
			print("qa-draw-audit-leaf: %3d  %s (%s)" % [base - without, world.get_path_to(ci), ci.get_class()])
