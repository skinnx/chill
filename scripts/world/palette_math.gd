class_name PaletteMath
extends RefCounted
## OKLab colour math (Björn Ottosson 2020) for palette interpolation and the rain transform.
## Matches Godot's Gradient GRADIENT_COLOR_SPACE_OKLAB sampling (checked in tests/test_palette.gd).

static func srgb_to_linear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


static func linear_to_srgb(c: float) -> float:
	return 12.92 * c if c <= 0.0031308 else 1.055 * pow(c, 1.0 / 2.4) - 0.055


## sRGB colour -> OKLab (L, a, b).
static func to_oklab(c: Color) -> Vector3:
	var r := srgb_to_linear(c.r)
	var g := srgb_to_linear(c.g)
	var b := srgb_to_linear(c.b)
	var l := 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
	var m := 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
	var s := 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
	var l_ := _cbrt(l)
	var m_ := _cbrt(m)
	var s_ := _cbrt(s)
	return Vector3(
		0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
		1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
		0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)


## OKLab -> sRGB colour (clamped to gamut by channel).
static func from_oklab(lab: Vector3, alpha: float = 1.0) -> Color:
	var l_ := lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
	var m_ := lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
	var s_ := lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z
	var l := l_ * l_ * l_
	var m := m_ * m_ * m_
	var s := s_ * s_ * s_
	var r := 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
	var g := -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
	var b := -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
	return Color(clampf(linear_to_srgb(r), 0.0, 1.0), clampf(linear_to_srgb(g), 0.0, 1.0),
		clampf(linear_to_srgb(b), 0.0, 1.0), alpha)


static func mix_oklab(a: Color, b: Color, t: float) -> Color:
	return from_oklab(to_oklab(a).lerp(to_oklab(b), t), lerpf(a.a, b.a, t))


## Scales OKLCh chroma by [param chroma_mul] and adds [param l_add] to lightness.
static func adjust(c: Color, chroma_mul: float, l_add: float) -> Color:
	var lab := to_oklab(c)
	return from_oklab(Vector3(clampf(lab.x + l_add, 0.0, 1.0), lab.y * chroma_mul, lab.z * chroma_mul), c.a)


## Euclidean OKLab distance (ΔE_OK), as used by the Art Bible checks.
static func delta_e(a: Color, b: Color) -> float:
	return to_oklab(a).distance_to(to_oklab(b))


static func _cbrt(x: float) -> float:
	return signf(x) * pow(absf(x), 1.0 / 3.0)
