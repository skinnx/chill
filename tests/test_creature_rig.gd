extends GutTest
## Mossling rig and node (Art Bible §5.2-5.7): every species resolves all 16 instance uniforms
## from data, breathing periods stay inside V5, the quad holds every part, squash stays within
## 12 %, and the touch flow (tap, long-press pet, stroke) answers on the first frame and ends
## with hearts.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")

const DT := 1.0 / 60.0
const FUR_SHADER := "res://shaders/creature/mossling_fur.gdshader"

var content: GameContent
var rig: MosslingRig


func before_all() -> void:
	content = GameContent.load_from_dir()
	rig = MosslingRig.new(content)


func _ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for s: Dictionary in content.species:
		out.append(StringName(s["id"]))
	return out


func test_shader_declares_exactly_16_instance_uniforms() -> void:
	var src := FileAccess.get_file_as_string(FUR_SHADER)
	var n := 0
	var code := PackedStringArray()
	for line: String in src.split("\n"):
		code.append(line.get_slice("//", 0))
		if line.strip_edges().begins_with("instance uniform"):
			n += 1
	assert_eq(n, 16, "Art Bible §5.5: 16 of 16 instance uniforms")
	var re := RegEx.create_from_string("\\bTIME\\b")
	assert_null(re.search("\n".join(code)), "no TIME in shader code (g_time only)")
	var all := MosslingRig.STATIC_SLOTS.duplicate()
	all.append_array(MosslingRig.ANIMATED_SLOTS)
	for name: StringName in all:
		assert_true(src.contains("instance uniform vec4 %s" % name), "%s is declared" % name)


func test_every_species_resolves_its_static_uniforms() -> void:
	for id: StringName in _ids():
		assert_true(rig.has_species(id), "%s has a rig and colours" % id)
		var p := rig.static_params(id, 0.3)
		assert_eq(p.size(), MosslingRig.STATIC_SLOTS.size(), "%s: all static slots" % id)
		for k: StringName in MosslingRig.STATIC_SLOTS:
			assert_true(p.has(k), "%s.%s" % [id, k])
		var fur: Color = p[MosslingRig.I_FUR]
		var spec: Dictionary = content.palettes["creatures"]["species_resolved"][String(id)]
		assert_true(fur.is_equal_approx(Color(Color.html(String(spec["fur"])), fur.a)), "%s fur from palettes" % id)
		var body: Vector4 = p[MosslingRig.I_BODY]
		assert_almost_eq(body.z, rig.body_px(id), 1e-4, "S px in i_body.z")
		var sp: Dictionary = content.species_by_id[id]
		assert_almost_eq(body.x, float(sp["rig"]["body_w_h"]), 1e-4, "w/h from species.json")


func test_breathing_periods_stay_in_v5() -> void:
	for i in 50:
		var u := float(i) / 49.0
		var awake := 600.0 / rig.breath_k(false, u)
		var asleep := 600.0 / rig.breath_k(true, u)
		assert_between(awake, 3.5, 4.5, "awake breath 3.5-4.5 s")
		assert_between(asleep, 5.0, 6.0, "asleep breath 5-6 s")
		assert_eq(rig.breath_k(false, u), floorf(rig.breath_k(false, u)), "integer k (k/600 loops)")


func test_quad_holds_the_body_and_its_parts() -> void:
	for id: StringName in _ids():
		var r := rig.quad_rect(id)
		var s := rig.body_px(id)
		assert_true(r.position.y <= -(1.0 + rig.top_extent_bu(id)) * s, "%s: room above the tallest part" % id)
		assert_true(r.size.x >= rig.body_width_bu(id) * s * 1.2, "%s: room for squash and the tail" % id)
		assert_true(r.end.y > 0.0, "%s: room below the feet for the fringe" % id)


func test_species_differ_in_at_least_two_identity_features() -> void:
	var ids := _ids()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Dictionary = content.species_by_id[ids[i]]["rig"]
			var b: Dictionary = content.species_by_id[ids[j]]["rig"]
			var diff := 0
			for k: String in ["ear", "tail", "antenna", "pattern", "eye"]:
				if a[k] != b[k]:
					diff += 1
			if absf(float(a["body_w_h"]) - float(b["body_w_h"])) >= 0.1 or absf(float(a["size"]) - float(b["size"])) >= 0.1:
				diff += 1
			assert_gt(diff, 1, "%s vs %s read apart (colour is never the only cue)" % [ids[i], ids[j]])


func test_motion_tokens_keep_squash_within_12_percent() -> void:
	var cr: Dictionary = content.motion["creature"]
	for v: float in [float(cr["hop"]["anticipation_squash"]), float(cr["hop"]["air_stretch"]),
			float(cr["hop"]["land_squash"]), float(cr["pet"]["hold_squash"]), float(cr["tap"]["squash"])]:
		assert_true(absf(v - 1.0) <= 0.12 + 1e-6, "creature squash %.2f within 12 %%" % v)


# ------------------------------------------------------------------ node behaviour

func _mossling(id: StringName) -> Mossling:
	var m := Mossling.new()
	add_child_autofree(m)
	m.setup(rig, id, 0.37, rig.make_fur_material(), rig.make_shadow_material(), rig.make_fx_materials())
	m.place_at(Vector2(540, 1100))
	return m


func _run(m: Mossling, seconds: float) -> void:
	var t := 0.0
	var fx: MosslingFx = m.get("_fx")
	while t < seconds:
		m._process(DT)
		fx._process(DT)
		t += DT


func test_tap_answers_at_once_and_reports_a_tap() -> void:
	var m := _mossling(&"buttonbud")
	watch_signals(m)
	m.touch_down(Vector2(540, 1040))
	assert_signal_emitted(m, "touched", "touch-down is reported in the same frame (cue S13)")
	_run(m, 0.1)
	assert_lt(m.get("_squash").value, 0.99, "squash toward 0.94 within 100 ms (I1)")
	m.touch_up(Vector2(540, 1040))
	assert_signal_emitted(m, "tapped")
	assert_signal_not_emitted(m, "pet_started")


func test_long_press_pets_with_hearts_on_release() -> void:
	var m := _mossling(&"puffmoss")
	watch_signals(m)
	m.touch_down(Vector2(540, 1040))
	_run(m, 0.3)
	assert_signal_not_emitted(m, "pet_started", "not before 450 ms")
	_run(m, 0.3)
	assert_signal_emitted(m, "pet_started", "pet at 450 ms (purr on)")
	_run(m, 0.6)
	assert_almost_eq(float(m.get("_squash").value), 0.88, 0.03, "held squash 0.88 on jelly")
	m.touch_up(Vector2(540, 1040))
	assert_signal_emitted(m, "pet_ended")
	assert_signal_emitted(m, "petted")
	_run(m, 0.5)
	var fx: MosslingFx = m.get("_fx")
	assert_eq(fx.hearts_alive(), 3, "three hearts rise on release")


func test_stroke_pets_too() -> void:
	var m := _mossling(&"bellkin")
	watch_signals(m)
	m.touch_down(Vector2(540, 1040))
	_run(m, 0.1)
	m.touch_move(Vector2(570, 1040))
	assert_signal_emitted(m, "pet_started", "a 24 px stroke starting on the mossling pets")


func test_napping_mossling_only_stirs() -> void:
	var m := _mossling(&"moonpuff")
	m.debug_pose(&"asleep")
	assert_true(m.asleep)
	m.touch_down(Vector2(540, 1040))
	_run(m, 0.1)
	m.touch_up(Vector2(540, 1040))
	_run(m, 0.5)
	assert_true(m.asleep, "a tap never wakes a napper")


func test_hop_walk_arrives_and_keeps_squash_in_bounds() -> void:
	var m := _mossling(&"capling")   # a bouncy species: full hops
	watch_signals(m)
	m.walk(PackedVector2Array([Vector2(700, 1100)]))
	var lo := 1.0
	var hi := 1.0
	var t := 0.0
	while t < 12.0 and m.is_walking():
		m._process(DT)
		var s := float(m.get("_squash").value) * float(m.get("_hop_f"))
		lo = minf(lo, s)
		hi = maxf(hi, s)
		t += DT
	assert_false(m.is_walking(), "arrived")
	assert_signal_emitted(m, "walk_finished")
	assert_almost_eq(m.feet().x, 700.0, 0.5, "feet at the target")
	assert_true(lo >= 0.86 and hi <= 1.12, "squash %.3f..%.3f stays within ~12 %%" % [lo, hi])


func test_nap_switches_breathing_without_a_phase_jump() -> void:
	var m := _mossling(&"puffmoss")
	var g := Clock.g_time
	var k0: float = m.get("_breath_k")
	var off0: float = m.get("_breath_off")
	var ph0 := fposmod(g * k0 / 600.0 + m.seed01 + off0, 1.0)
	m.perform(&"nap", &"sun_stone")
	var k1: float = m.get("_breath_k")
	var off1: float = m.get("_breath_off")
	var ph1 := fposmod(g * k1 / 600.0 + m.seed01 + off1, 1.0)
	assert_between(600.0 / k1, 5.0, 6.0, "asleep period")
	assert_almost_eq(ph1, ph0, 1e-4, "breath phase continues across the switch")


func test_eye_ink_is_lifted_so_eyes_never_outrank_the_focal() -> void:
	var base := Color.html(String(content.palettes["creatures"]["tokens"]["cr_eye"]))
	var ink: Dictionary = rig.view()["eye_ink"]
	for id: StringName in _ids():
		var eye: Color = rig.static_params(id, 0.3)[MosslingRig.I_EYE]
		assert_gte(eye.ok_hsl_l, float(ink["ok_l"]) - 1e-3, "%s eye ink lifted" % id)
		assert_lt(eye.ok_hsl_l, 0.45, "%s eyes stay dark enough to read" % id)
	var pp: Color = rig.static_params(&"pebblepaw", 0.3)[MosslingRig.I_EYE]
	assert_gt(pp.ok_hsl_l, base.ok_hsl_l + 0.05, "pebblepaw (frontmost) has the softest eyes")


func test_lamp_light_reaches_a_creature_near_a_lantern() -> void:
	LampRegistry.clear()
	var cfg: Dictionary = rig.view()["lamp"]
	assert_eq(Mossling.lamp_light(Vector2(500, 1500), cfg), Vector4.ZERO, "no lamps, no light")
	LampRegistry.set_lamp(&"t_lamp", Vector2(700, 1500), 150.0, 1.0)
	var near := Mossling.lamp_light(Vector2(600, 1500), cfg)
	var far := Mossling.lamp_light(Vector2(380, 1500), cfg)
	var out := Mossling.lamp_light(Vector2(100, 1500), cfg)
	assert_gt(near.z, far.z, "weight falls off with distance")
	assert_gt(far.z, 0.0, "a body catches a lantern beyond its ground pool (reach x2.2)")
	assert_eq(out.z, 0.0, "out of reach")
	assert_almost_eq(near.x, 1.0, 1e-4, "direction points at the lamp (+x)")
	assert_almost_eq(near.y, 0.0, 1e-4, "local y is up")
	LampRegistry.clear()


func test_nestle_is_off_on_props_and_while_hopping() -> void:
	assert_eq(rig.nestle_at(&"sun_stone"), 0.0, "sitting on the sun stone: no grass in front")
	assert_eq(rig.nestle_at(&"stream_bend"), 1.0, "on the meadow: nestled")
	var m := _mossling(&"pebblepaw")
	m.perform(&"sit_by_stream", &"stream_bend")
	m._process(DT)
	var misc: Vector4 = m.get("_u_misc")
	assert_almost_eq(misc.y, 1.0, 1e-4, "i_misc.y nestle on the meadow")
	m.set("_hop_h", 20.0)
	assert_almost_eq(float(m.call("_nestle_now")), 0.0, 1e-4, "no grass while in the air")


func test_umbrella_is_held_behind_the_body_and_rooted_at_the_paw() -> void:
	var m := _mossling(&"buttonbud")
	m.set_rain(true, false, true)
	_run(m, 0.6)
	var back: Node2D = m.get("_umbrella_back")
	var body: Node2D = m.get("_body")
	assert_lt(back.get_index(), body.get_index(), "umbrella draws before (behind) the body")
	var fx: MosslingFx = m.get("_fx")
	assert_true(fx.umbrella_visible(), "umbrella fades in in rain")
	var pivot := back.get_child(0) as Node2D
	assert_lt(pivot.position.y, 0.0, "stem foot above the feet (the paw)")
	assert_almost_eq(absf(pivot.rotation), deg_to_rad(float(rig.behaviour()["umbrella_tilt_deg"])), 0.15,
		"tilted ~12 degrees in over the head")
	m.set_rain(true, false, false)
	_run(m, 0.6)
	assert_false(fx.umbrella_visible(), "rain lovers hold no umbrella")


func test_zzz_starts_beside_the_head_not_above_it() -> void:
	var m := _mossling(&"puffmoss")
	m.debug_pose(&"asleep")
	m.set_still(true)
	_run(m, 3.5)
	var fx: MosslingFx = m.get("_fx")
	assert_gt(fx.zzz_alive(), 0, "a z rises while napping")
	var w := rig.body_px(&"puffmoss") * rig.body_width_bu(&"puffmoss")
	for s: MosslingFx.Stamp in fx.get("_zs"):
		if s.active:
			assert_gt(absf(s.from.x), w * 0.3, "z starts at the side of the head")
