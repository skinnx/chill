class_name TestUtil
extends RefCounted
## Shared test helpers.

# Tests read JSON dictionaries and GUT asserts take Variants, so every value is converted or
# compared explicitly; only the analyzer's unsafe_call_argument warning is silenced here
# (docs/ARCHITECTURE.md §10). untyped_declaration and unsafe_method_access stay active.
@warning_ignore_start("unsafe_call_argument")


## JSON text of [param v] with every float rounded to 10 significant digits, for comparing
## states across a save/load: Godot 4.7.2's number parser may return a double 1 ulp away from
## the one that was written (docs/ARCHITECTURE.md §6), while ints, strings and ids stay exact.
static func canonical(v: Variant) -> String:
	return JSON.stringify(round_floats(v), "", true)


static func round_floats(v: Variant) -> Variant:
	if v is float:
		var x: float = v
		if x == 0.0 or is_inf(x) or is_nan(x):
			return x
		var step := pow(10.0, floorf(log(absf(x)) / log(10.0)) - 9.0)
		return snappedf(x, step)
	if v is Dictionary:
		var d: Dictionary = v
		var out := {}
		for k: Variant in d:
			out[k] = round_floats(d[k])
		return out
	if v is Array:
		var a: Array = v
		return a.map(func(e: Variant) -> Variant: return round_floats(e))
	return v
