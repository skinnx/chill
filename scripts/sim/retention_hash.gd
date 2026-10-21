class_name RetentionHash
extends RefCounted
## The stateless retention draw (GDD §13.1): every Retention v1 random choice (sign times, scene
## roll and pick, wave delays) comes from here and never from the world RNG stream, so adding the
## retention systems cannot change the visitor/economy history of a save (G6).
##
##   u(seed, parts...) = (splitmix64(seed XOR fnv1a64(utf8(join(parts, "|")))) >>> 11) / 2^53
##
## Reference implementation: tools/sim/economy_sim.py hash_u (golden vectors in GDD §13.1 and
## tests/test_retention_hash.gd). GDScript ints are signed 64-bit with wrapping multiplication;
## `>>` is arithmetic, so logical shifts mask off the sign-extended bits.

## FNV-1a 64 offset basis 0xCBF29CE484222325 and prime 0x100000001B3 (GDD §13.1).
const FNV_OFFSET := -3750763034362895579
const FNV_PRIME := 0x100000001B3
## splitmix64 constants 0x9E3779B97F4A7C15, 0xBF58476D1CE4E5B9, 0x94D049BB133111EB (GDD §13.1).
const SM_GAMMA := -7046029254386353131
const SM_MUL_1 := -4658895280553007687
const SM_MUL_2 := -7723592293110705685
## 2^53: the top 53 bits of the mix become a double in [0, 1).
const TWO_POW_53 := 9007199254740992.0
const SEPARATOR := "|"


## The draw in [0, 1). [param parts] are joined with "|" after str(); pass ints as ints (a JSON
## float would print as "1.0" and give a different key).
static func u(seed: int, parts: Array) -> float:
	var key := PackedStringArray()
	for p: Variant in parts:
		key.append(str(p))
	var z := splitmix64(seed ^ fnv1a64(SEPARATOR.join(key)))
	return float(lshr(z, 11)) / TWO_POW_53


static func fnv1a64(text: String) -> int:
	var h := FNV_OFFSET
	for b: int in text.to_utf8_buffer():
		h = (h ^ b) * FNV_PRIME
	return h


static func splitmix64(x: int) -> int:
	var z := x + SM_GAMMA
	z = (z ^ lshr(z, 30)) * SM_MUL_1
	z = (z ^ lshr(z, 27)) * SM_MUL_2
	return z ^ lshr(z, 31)


## Logical (unsigned) right shift of a 64-bit int, 0 < n < 64.
static func lshr(x: int, n: int) -> int:
	return (x >> n) & ((1 << (64 - n)) - 1)
