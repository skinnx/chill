extends GutTest
## Round 5 creature contract (studio owner: the mosslings read as premium plush toys): the plush
## detail rides in i_parts.y without breaking the tail id, only a few species wear one, the fur
## shader carries the plush features, and the lineup keeps the world's shadow direction.

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly where it is read (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const FUR_SHADER := "res://shaders/creature/mossling_fur.gdshader"
const LINEUP_SCRIPT := "res://scripts/creature/lineup.gd"
const BACKDROP_SHADER := "res://shaders/creature/lineup_backdrop.gdshader"
## A tasteful extra on "a few species only".
const MAX_DETAIL_SPECIES := 4

var content: GameContent
var rig: MosslingRig


func before_all() -> void:
	content = GameContent.load_from_dir()
	rig = MosslingRig.new(content)


func _decode_detail(code: float) -> int:
	return int(floor(fposmod(code, 1.0) * rig.plush_detail_code() + 0.5))


func test_plush_detail_keeps_the_tail_id() -> void:
	for s: Dictionary in content.species:
		var id := StringName(s["id"])
		var p: Dictionary = rig.static_params(id, 0.3)
		var parts: Vector4 = p[MosslingRig.I_PARTS]
		var tail: Dictionary = rig.species_rig(id).get("tail", {})
		# the shader reads the tail as int(x + 0.5) and the detail from the fraction
		assert_eq(int(parts.y + 0.5), int(tail.get("id", 0)), "%s tail id survives" % id)
		assert_eq(_decode_detail(parts.y), rig.plush_detail_id(id), "%s detail decodes" % id)


func test_only_a_few_species_wear_a_detail() -> void:
	var n := 0
	for s: Dictionary in content.species:
		if rig.plush_detail_id(StringName(s["id"])) != 0:
			n += 1
	assert_between(n, 1, MAX_DETAIL_SPECIES)
	assert_eq(rig.plush_detail_id(&"buttonbud"), 2, "Buttonbud wears a sewn-on button")


func test_detail_code_matches_the_shader() -> void:
	var code := (load(FUR_SHADER) as Shader).code
	assert_true(code.contains("const float DETAIL_CODE = %.1f;" % rig.plush_detail_code()),
		"creature_rig view.plush.detail_code and the shader DETAIL_CODE agree")


func test_fur_shader_carries_the_plush_features() -> void:
	var code := (load(FUR_SHADER) as Shader).code
	for key: String in ["plush_pile(", "VELVET_K", "GUSSET_BU", "EYE_SOCKET_K", "THREAD_FREQ", "BUTTON_R", "TAG_HALF"]:
		assert_true(code.contains(key), "plush feature " + key)
	# smooth, band-limited pile: no quantised floor() cells in the pile function
	var start := code.find("float plush_pile(")
	var body := code.substr(start, code.find("\n}", start) - start)
	assert_false(body.contains("floor("), "the pile is never a quantised cell grid")


func test_lineup_keeps_the_world_light() -> void:
	var src := (load(LINEUP_SCRIPT) as GDScript).source_code
	assert_false(src.contains("g_sun_dir"), "the lineup never overrides the world's sun direction")
	assert_true((load(BACKDROP_SHADER) as Shader).code.contains("u_grid"), "studio sweep per row")


func test_golden_shadows_fall_toward_the_viewer() -> void:
	# the creature shadow uses world_light cast_offset_k, the same law as ShadowMath: its screen y
	# is TOWARD_VIEWER + BACKLIGHT_K x backlight, so it always falls down the screen (QA r4 blocker)
	for sun: Vector2 in [Vector2(-0.6, -0.8), Vector2(0.6, -0.8), Vector2(0.2, 0.98)]:
		var v := {&"g_sun_dir": sun, &"g_backlight": 0.85}
		assert_gt(ShadowMath.cast_dir(v).y, 0.0, "golden cast falls toward the viewer for %s" % sun)
