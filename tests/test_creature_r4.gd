extends GutTest
## Round 4 creature contract (Director R4 #2, #4; QA r3 creature issues): UI portraits get the
## fixed studio light, the tap ends in a bespoke stretch beat, a held pet streams 3+ hearts by
## 1.1 s, sparkles burst outward from the silhouette, pose hints give the fixture varied faces,
## the near creatures stop growing at near_cap, the rain fur divides the ambient_mult back out,
## the creature shadow multiplies like the prop shadows, and the brain's forced bouts stay
## deterministic per seed.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const DT := 1.0 / 60.0
const SHADOW_SHADER := "res://shaders/creature/creature_shadow.gdshader"
const PROP_SHADOW_SHADER := "res://shaders/fx/contact_shadow.gdshader"
const FX_SHADER := "res://shaders/creature/creature_fx.gdshader"
const SEED := 77
## Mossling._on_tap: the tap burst is centred this far below the head point (body units).
const TAP_SPARKLE_DROP_BU := 0.35
const LAYER_SCRIPT := "res://scripts/creature/creature_layer.gd"

var content: GameContent
var rig: MosslingRig


func before_all() -> void:
	content = GameContent.load_from_dir()
	rig = MosslingRig.new(content)


func _mossling(id: StringName, parent: Node = null) -> Mossling:
	var m := Mossling.new()
	if parent == null:
		add_child_autofree(m)
	else:
		parent.add_child(m)
	m.setup(rig, id, 0.37, rig.make_fur_material(), rig.make_shadow_material(), rig.make_fx_materials())
	m.place_at(Vector2(540, 1100))
	return m


func _fixture_rows() -> Array:
	return (load(LAYER_SCRIPT) as GDScript).get_script_constant_map()["QA_FIXTURE"]


func _run(m: Mossling, seconds: float) -> void:
	var t := 0.0
	var fx: MosslingFx = m.get("_fx")
	while t < seconds:
		m._process(DT)
		fx._process(DT)
		t += DT


func test_portrait_mossling_gets_the_studio_light() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var m := _mossling(&"puffmoss", host)
	var body := m.get_node(^"Visual/Body") as CanvasItem
	var mat := body.material as ShaderMaterial
	assert_almost_eq(float(mat.get_shader_parameter(&"u_studio")), 1.0, 1e-4, "a portrait is studio-lit")
	var day: Dictionary = (content.palettes["tod"]["palettes"] as Dictionary)["day"]
	var amb := mat.get_shader_parameter(&"u_studio_ambient") as Color
	assert_true(amb.is_equal_approx(Color.html(String(day["ambient"]))), "studio ambient is the day ambient")


func test_world_mossling_stays_world_lit() -> void:
	var m := _mossling(&"puffmoss")
	var mat := (m.get_node(^"Visual/Body") as CanvasItem).material as ShaderMaterial
	var v: Variant = mat.get_shader_parameter(&"u_studio")
	assert_true(v == null or is_zero_approx(float(v)), "the meadow mosslings follow the world light")


func test_rain_ambient_is_read_from_world_json() -> void:
	var mat := rig.make_fur_material()
	var w: Dictionary = content.weather_by_id[&"rain"]
	assert_almost_eq(float(mat.get_shader_parameter(&"u_rain_amb")), float(w["ambient_mult"]), 1e-4)


func test_tap_ends_in_a_stretch_beat_within_the_squash_cap() -> void:
	var m := _mossling(&"buttonbud")
	m.touch_down(Vector2(540, 1040))
	_run(m, 0.05)
	m.touch_up(Vector2(540, 1040))
	var sq: Spring = m.get("_squash")
	var stretch := float(rig.behaviour()["tap_stretch"])
	assert_almost_eq(sq.target, stretch, 1e-4, "the press squash springs into a stretch")
	assert_lte(absf(stretch - 1.0), 0.12, "S&S stays within 12 %")
	_run(m, 0.5)
	assert_almost_eq(sq.target, float(m.get("_rest_squash")), 1e-4, "and settles back to rest")


## Round 8, ARCHITECTURE §3.5: one slop on every target. The mossling used to tap at 18 px and
## stroke at 24 px with a 60 ms hold, so a thumb that slid 19-24 px, and a flick that crossed
## 24 px inside the first frame, both did nothing at all on the most-tapped thing in the game.
func test_a_small_slide_still_taps_and_there_is_no_dead_band() -> void:
	for slide: float in [0.0, 12.0, 19.0, 23.0]:
		var m := _mossling(&"buttonbud")
		m.touch_down(Vector2(540, 1040))
		_run(m, 0.05)
		m.touch_move(Vector2(540 + slide, 1040))
		m.touch_up(Vector2(540 + slide, 1040))
		var sq: Spring = m.get("_squash")
		assert_almost_eq(sq.target, float(rig.behaviour()["tap_stretch"]), 1e-4,
				"a %d px slide is still a tap" % int(slide))
		assert_false(bool(m.get("_petting")), "and not a pet")


func test_a_fast_flick_across_a_friend_pets_it_without_waiting_out_a_hold() -> void:
	var m := _mossling(&"pebblepaw")
	m.touch_down(Vector2(540, 1040))
	# Past the slop inside the very first frame: the old 60 ms hold swallowed this entirely.
	m.touch_move(Vector2(540 + 60.0, 1040))
	assert_true(bool(m.get("_petting")), "a stroke is a stroke however quickly it crosses the slop")


func test_held_pet_streams_three_hearts_by_1100_ms() -> void:
	var m := _mossling(&"pebblepaw")
	var fx: MosslingFx = m.get("_fx")
	m.touch_down(Vector2(540, 1040))
	_run(m, 1.1)
	assert_true(bool(m.get("_petting")))
	assert_gte(fx.hearts_alive(), 3, "a steady stream of hearts while petting (QA r3: one heart read thin)")


func test_release_bouquet_has_room_in_the_pool() -> void:
	var m := _mossling(&"pebblepaw")
	var fx: MosslingFx = m.get("_fx")
	m.touch_down(Vector2(540, 1040))
	_run(m, 1.5)
	m.touch_up(Vector2(540, 1040))
	_run(m, 0.7)
	assert_gte(fx.hearts_alive(), int(rig.behaviour()["release_hearts"]), "every release heart finds a stamp")
	assert_lte(fx.hearts_alive(), MosslingFx.HEART_POOL)


func test_tap_sparkles_burst_from_the_silhouette() -> void:
	var m := _mossling(&"buttonbud")
	var fx: MosslingFx = m.get("_fx")
	m.touch_down(Vector2(540, 1040))
	_run(m, 0.05)
	m.touch_up(Vector2(540, 1040))
	var w := rig.body_px(&"buttonbud") * rig.body_width_bu(&"buttonbud")
	var n := 0
	var s_px := rig.body_px(&"buttonbud")
	var head := Vector2(0.0, -s_px * Mossling.HEAD_BU + s_px * TAP_SPARKLE_DROP_BU)
	for s: MosslingFx.Stamp in fx.get("_sparkles"):
		if s.active:
			n += 1
			assert_gt(s.from.distance_to(head), w * 0.3, "sparkles start at the edge, not over the fur")
	assert_eq(n, int(rig.behaviour()["tap_sparkles"]))


func test_pose_hints_hold_a_happy_face_through_play() -> void:
	var a := _mossling(&"honeyhum")
	a.perform(Mossling.B_PLAY, &"moss_cushion", {"look": 0.8, "look_hold_s": 8.0, "happy_s": 8.0})
	_run(a, 4.0)
	assert_eq(int(a.get("_closed")), MosslingRig.CLOSED_HAPPY, "play hops never cancel a held happy beat")
	_run(a, 6.0)
	assert_ne(int(a.get("_closed")), MosslingRig.CLOSED_HAPPY, "and the beat runs out on its own")


func test_near_creatures_stop_growing_at_near_cap() -> void:
	var m := _mossling(&"pebblepaw")
	var ds: Dictionary = rig.view()["depth_scale"]
	m.place_at(Vector2(540, 1900))
	assert_almost_eq(m.depth, float(ds["near_cap"]), 1e-4)
	m.place_at(Vector2(540, float(ds["y0"])))
	assert_almost_eq(m.depth, float(ds["min"]), 1e-4, "the far ramp is unchanged")


func test_creature_shadow_blends_like_prop_shadows() -> void:
	var code := (load(SHADOW_SHADER) as Shader).code
	# round 5: one family of shadows, the same blend as fx/contact_shadow (a tint, not a multiply)
	var prop := (load(PROP_SHADOW_SHADER) as Shader).code
	for mode: String in ["blend_mix", "blend_mul"]:
		assert_eq(code.contains(mode), prop.contains(mode), "same blend as the prop shadows: " + mode)
	assert_true(code.contains("g_sky_mid"), "lavender-leaning shade at golden, like the props")
	assert_true(code.contains("shadow_tint()"), "same tint as fx/contact_shadow")
	assert_true(code.contains("cast_offset_k(key_dir(origin))"), "fanned from the light like the props")


func test_hearts_have_a_cream_outline() -> void:
	assert_true((load(FX_SHADER) as Shader).code.contains("HEART_OUTLINE"))


func test_fixture_poses_are_varied() -> void:
	var looks := {}
	var happy := 0
	for row: Array in _fixture_rows():
		var hints: Dictionary = row[3]
		if hints.has("look"):
			looks[snappedf(float(hints["look"]), 0.1)] = true
		if hints.has("happy_s"):
			happy += 1
	assert_gte(looks.size(), 3, "friends look in different directions")
	assert_gte(happy, 1, "one friend beams ^ ^")


func test_forced_bouts_are_deterministic_per_seed() -> void:
	var sig := func() -> String:
		var b := CreatureBrain.new(content, SEED)
		b.env = func(_t: float) -> Dictionary: return {"phase": &"day", "weather": &"clear"}
		b.owned = func(_item: StringName) -> int: return 0
		b.bed_flowers = func(_bed: StringName) -> Array: return []
		var out := PackedStringArray()
		for row: Array in _fixture_rows():
			var sp: StringName = row[0]
			b.add_visit(sp, 0.0, 3600.0, false)
			var bout := b.force_bout(sp, row[1], row[2], 1.0, 3600.0)
			out.append("%s:%s:%s:%s" % [sp, bout.behaviour, bout.spot, bout.pos])
		return ",".join(out)
	assert_eq(sig.call(), sig.call(), "same seed, same fixture plan")


func test_rain_umbrella_fades_in_fully_opaque() -> void:
	var m := _mossling(&"puffmoss")
	m.set_rain(true, false, true)
	_run(m, 1.0)
	var fx: MosslingFx = m.get("_fx")
	var u: CanvasItem = fx.get("_umbrella")
	gut.p("umbrella alpha %s modulate %s" % [fx.umbrella_alpha(), u.self_modulate])
	assert_almost_eq(fx.umbrella_alpha(), 1.0, 1e-3, "the held leaf is solid, never a see-through outline")
	assert_true(u.is_visible_in_tree())
