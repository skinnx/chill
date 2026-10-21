class_name MosslingRig
extends RefCounted
## Species -> mossling_fur shader parameters (docs/ART_BIBLE.md §5.4-5.5). Pure: reads only the
## GameContent it is given (creature_rig.json catalog + resolved species, palettes.json resolved
## species colours, motion_tokens.json breathing/loops), so tests build one without autoloads.
##
## Static slots (0-10, 15) are resolved once per species; the four animated slots (11-14) are
## written by Mossling every frame they change, keeping the static parts in a CPU mirror (§5.5).

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const FUR_SHADER := "res://shaders/creature/mossling_fur.gdshader"
const SHADOW_SHADER := "res://shaders/creature/creature_shadow.gdshader"
const FX_SHADER := "res://shaders/creature/creature_fx.gdshader"

## Instance-uniform names in slot order (creature_rig.json instance_uniforms, Art Bible §5.5).
const I_FUR := &"i_fur"
const I_FUR2 := &"i_fur2"
const I_BELLY := &"i_belly"
const I_ACCENT := &"i_accent"
const I_TIP := &"i_tip"
const I_CHEEK := &"i_cheek"
const I_EYE := &"i_eye"
const I_BODY := &"i_body"
const I_PARTS := &"i_parts"
const I_PART_P := &"i_part_p"
const I_FACE := &"i_face"
const I_ANIM := &"i_anim"
const I_FOLLOW := &"i_follow"
const I_STATE := &"i_state"
const I_LIGHT := &"i_light"
const I_MISC := &"i_misc"
const STATIC_SLOTS: Array[StringName] = [I_FUR, I_FUR2, I_BELLY, I_ACCENT, I_TIP, I_CHEEK, I_EYE, I_BODY,
	I_PARTS, I_PART_P, I_FACE, I_MISC]
const ANIMATED_SLOTS: Array[StringName] = [I_ANIM, I_FOLLOW, I_STATE, I_LIGHT]

## Catalog ids the view code branches on (creature_rig.json catalog).
const EAR_NONE := 0
const TAIL_NONE := 0
const ANTENNA_GLOW_BOBBLE := 5
const EYE_SLEEPY := 1
const CLOSED_OPEN := 0
const CLOSED_SLEEP := 1
const CLOSED_HAPPY := 2

var content: GameContent


func _init(p_content: GameContent) -> void:
	content = p_content


func rig() -> Dictionary:
	return content.creature_rig


func view() -> Dictionary:
	return rig().get("view", {})


func behaviour() -> Dictionary:
	return view().get("behaviour", {})


func species_rig(species_id: StringName) -> Dictionary:
	var sp: Dictionary = rig().get("species", {})
	return sp.get(String(species_id), {})


func species_colours(species_id: StringName) -> Dictionary:
	var cr: Dictionary = content.palettes.get("creatures", {})
	var res: Dictionary = cr.get("species_resolved", {})
	return res.get(String(species_id), {})


func has_species(species_id: StringName) -> bool:
	return not species_rig(species_id).is_empty() and not species_colours(species_id).is_empty()


## Body height in local px (S = base_body_px x size, Art Bible §5.2).
func body_px(species_id: StringName) -> float:
	var r := species_rig(species_id)
	var body: Dictionary = r.get("body", {})
	var defaults: Dictionary = rig().get("defaults", {})
	return float(defaults.get("base_body_px", 150.0)) * float(body.get("size_mul", 1.0))


func body_width_bu(species_id: StringName) -> float:
	var body: Dictionary = species_rig(species_id).get("body", {})
	return float(body.get("w_h", 1.0))


## Highest part above the head top in bu (ears or antennae, plus the glow halo; §5.2).
func top_extent_bu(species_id: StringName) -> float:
	var r := species_rig(species_id)
	var te: Dictionary = view().get("top_extent_bu", {})
	var ears: Dictionary = te.get("ear", {})
	var ants: Dictionary = te.get("antenna", {})
	var ear_type := String((r.get("ear", {}) as Dictionary).get("type", "none"))
	var ant_type := String((r.get("antenna", {}) as Dictionary).get("type", "none"))
	var ext := maxf(float(ears.get(ear_type, 0.0)), float(ants.get(ant_type, 0.0)))
	if int((r.get("antenna", {}) as Dictionary).get("id", 0)) == ANTENNA_GLOW_BOBBLE:
		ext += float(te.get("glow_halo", 0.0))
	return ext


## The SDF quad in local px, feet at the origin (§5.2, with room for squash, stretch and fringe).
func quad_rect(species_id: StringName) -> Rect2:
	var s := body_px(species_id)
	var pad: Dictionary = view().get("quad_pad_bu", {})
	var half_w := (0.5 * body_width_bu(species_id) + float(pad.get("side", 0.5))) * s
	var top := (1.0 + top_extent_bu(species_id) + float(pad.get("top", 0.2))) * s
	var bottom := float(pad.get("bottom", 0.1)) * s
	return Rect2(-half_w, -top, 2.0 * half_w, top + bottom)


## Seeded integer breathing k (period 600/k s) inside motion_tokens loops_k (V5, C4).
func breath_k(asleep: bool, seed01: float) -> float:
	var loops: Dictionary = content.motion.get("loops_k", {})
	var key := "breathe_asleep" if asleep else "breathe_awake"
	var range_k: Array = loops.get(key, [150, 150])
	var lo := int(range_k[0])
	var hi := int(range_k[1])
	return float(lo + int(floor(clampf(seed01, 0.0, 0.9999) * float(hi - lo + 1))))


## Static instance uniforms (slots 0-10 and 15) by name. [param seed01] varies the pattern.
func static_params(species_id: StringName, seed01: float) -> Dictionary:
	var r := species_rig(species_id)
	var c := species_colours(species_id)
	var body: Dictionary = r.get("body", {})
	var defaults: Dictionary = rig().get("defaults", {})
	var ear: Dictionary = r.get("ear", {})
	var tail: Dictionary = r.get("tail", {})
	var ant: Dictionary = r.get("antenna", {})
	var pat: Dictionary = r.get("pattern", {})
	var eye: Dictionary = r.get("eye", {})
	var mouth: Dictionary = r.get("mouth", {})
	var strengths: Dictionary = view().get("pattern_strength", {})
	var pat_type := String(pat.get("type", "none"))
	var out := {}
	out[I_FUR] = _col(c, "fur", float(r.get("fuzz_dp", 1.0)) * 0.5)
	out[I_FUR2] = _col(c, "pattern_ink", float(strengths.get(pat_type, 0.0)))
	out[I_BELLY] = _col(c, "belly", float(pat.get("belly_size", defaults.get("belly_size_default", 0.6))))
	out[I_ACCENT] = _col(c, "accent", float(ant.get("emission", 0.0)))
	out[I_TIP] = _col(c, "tip", float(view().get("tip_mix", 0.45)))
	out[I_CHEEK] = _col(c, "cheek", float(c.get("cheek_alpha", defaults.get("cheek_alpha", 0.5))))
	out[I_EYE] = _col(c, "eye", float(eye.get("size", defaults.get("eye_size", 0.2))))
	out[I_BODY] = Vector4(float(body.get("w_h", 1.0)), float(body.get("squircle_n", defaults.get("squircle_n", 2.4))),
		body_px(species_id), float(defaults.get("bottom_flatten_n_add", 1.2)))
	out[I_PARTS] = Vector4(float(ear.get("id", 0)), float(tail.get("id", 0)), float(ant.get("id", 0)),
		float(pat.get("id", 0)))
	out[I_PART_P] = Vector4(float(ear.get("size", 0.0)), float(ear.get("spread", 0.0)), float(tail.get("size", 0.0)),
		float(ant.get("length", 0.0)))
	out[I_FACE] = Vector4(float(eye.get("id", 0)), float(eye.get("spacing", defaults.get("eye_spacing", 0.4))),
		float(eye.get("height_from_top", defaults.get("eye_height_from_top", 0.58))), float(mouth.get("id", 0)))
	out[I_MISC] = Vector4(seed01, 1.0, float(body.get("feet_nubs", 0)), float(CLOSED_OPEN))
	return out


func ear_type(species_id: StringName) -> String:
	return String((species_rig(species_id).get("ear", {}) as Dictionary).get("type", "none"))


func antenna_id(species_id: StringName) -> int:
	return int((species_rig(species_id).get("antenna", {}) as Dictionary).get("id", 0))


func eye_id(species_id: StringName) -> int:
	return int((species_rig(species_id).get("eye", {}) as Dictionary).get("id", 0))


## Ear droop when asleep, rad (motion_tokens creature.sleep.ear_droop_deg by ear type).
func sleep_ear_droop(species_id: StringName) -> float:
	var sleep: Dictionary = (content.motion.get("creature", {}) as Dictionary).get("sleep", {})
	var droop: Dictionary = sleep.get("ear_droop_deg", {})
	return deg_to_rad(float(droop.get(ear_type(species_id), 0.0)))


## Shared materials. The fur material carries the data-driven uniforms (cr_leaf, eye shine,
## breathing amplitudes, loop k) so the shader holds no colours or motion numbers of its own.
func make_fur_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(FUR_SHADER) as Shader
	var tokens: Dictionary = (content.palettes.get("creatures", {}) as Dictionary).get("tokens", {})
	mat.set_shader_parameter(&"u_leaf", Color.html(String(tokens.get("cr_leaf", "#86B97B"))))
	mat.set_shader_parameter(&"u_shine", Color.html(String(tokens.get("cr_eye_shine", "#FFFDF8"))))
	var cr: Dictionary = content.motion.get("creature", {})
	var breathe: Dictionary = cr.get("breathe", {})
	var awake: Array = breathe.get("awake_scale", [0.99, 1.025])
	var asleep: Array = breathe.get("asleep_scale", [0.985, 1.035])
	mat.set_shader_parameter(&"u_breath", Vector4(1.0 - float(awake[0]), float(awake[1]) - 1.0,
		1.0 - float(asleep[0]), float(asleep[1]) - 1.0))
	var loops: Dictionary = content.motion.get("loops_k", {})
	var spatial: Dictionary = content.motion.get("loops_spatial", {})
	var gust_sp: Dictionary = spatial.get("gust", {})
	mat.set_shader_parameter(&"u_wind_k", Vector4(_k(loops, "ear_wind"), _k(loops, "antenna_bob"),
		_k(loops, "gust"), float(gust_sp.get("spacing_px", 1742.0))))
	return mat


func make_shadow_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADOW_SHADER) as Shader
	return mat


## The five shared feedback-stamp materials (heart, z, sparkle, ring, umbrella), keyed by
## MosslingFx.KIND_*. Colours from palettes.json fx / materials; no instance uniforms.
func make_fx_materials() -> Dictionary:
	var shader := load(FX_SHADER) as Shader
	var heart := fx_colour("heart")
	var spark := fx_colour("sparkle")
	var zzz := fx_colour("zzz")
	var leaf := material_tones("leaf_boat")
	var spec := {
		MosslingFx.KIND_HEART: [MosslingFx.HEART_HALF_PX, heart, heart.darkened(0.12), spark],
		MosslingFx.KIND_Z: [MosslingFx.Z_HALF_PX, zzz, zzz, zzz],
		MosslingFx.KIND_SPARKLE: [MosslingFx.SPARKLE_HALF_PX, spark, spark, spark],
		MosslingFx.KIND_RING: [1.0, spark, spark, spark],
		MosslingFx.KIND_UMBRELLA: [MosslingFx.UMBRELLA_HALF_PX, leaf[0], leaf[1], leaf[2]],
	}
	var out := {}
	for kind: int in spec:
		var v: Array = spec[kind]
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter(&"u_kind", float(kind))
		mat.set_shader_parameter(&"u_half", float(v[0]))
		mat.set_shader_parameter(&"u_a", v[1])
		mat.set_shader_parameter(&"u_b", v[2])
		mat.set_shader_parameter(&"u_c", v[3])
		out[kind] = mat
	return out


## Colour of an FX element from palettes.json fx (hearts coral, z's, sparkles).
func fx_colour(key: String) -> Color:
	var fx: Dictionary = content.palettes.get("fx", {})
	var v := String(fx.get(key, "#FFFDF8"))
	if v.begins_with("#"):
		return Color.html(v)
	var ui: Dictionary = content.palettes.get("ui", {})
	return Color.html(String(ui.get(v, "#FFFDF8")))


## Tone-mask triple of a palettes.json material ([lit, shade, detail]).
func material_tones(id: String) -> PackedColorArray:
	var mats: Dictionary = content.palettes.get("materials", {})
	var m: Dictionary = mats.get(id, {})
	return PackedColorArray([Color.html(String(m.get("lit", "#8FC07C"))), Color.html(String(m.get("shade", "#539C7A"))),
		Color.html(String(m.get("detail", "#D2E6C2")))])


static func _col(c: Dictionary, key: String, a: float) -> Color:
	var col := Color.html(String(c.get(key, "#FFFFFF")))
	col.a = a
	return col


static func _k(loops: Dictionary, key: String) -> float:
	var r: Array = loops.get(key, [1, 1])
	return float(r[0])
