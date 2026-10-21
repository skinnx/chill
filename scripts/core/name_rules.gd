class_name NameRules
extends RefCounted
## Friend-name input rules (GDD §7.3): allowed characters = the subset fonts' coverage
## (Latin + Vietnamese + digits + space + - ' .), max 12 characters, trimmed, NFC-normalised.
## Disallowed characters are dropped silently (no error state, E2/A3).

## GDD §7.3 "max 12 characters".
const MAX_LENGTH := 12
const EXTRA_ALLOWED := " -'."

static var _decompose: Dictionary = {}


## Returns the cleaned name; an empty result means "use the default name".
static func sanitize(text: String) -> String:
	var filtered := ""
	for ch in nfc(text):
		if is_allowed(ch.unicode_at(0)):
			filtered += ch
	# Collapse runs of spaces and trim.
	var words := filtered.split(" ", false)
	var out := " ".join(words)
	if out.length() > MAX_LENGTH:
		out = out.substr(0, MAX_LENGTH).strip_edges()
	return out


static func is_allowed(cp: int) -> bool:
	if (cp >= 0x30 and cp <= 0x39) or (cp >= 0x41 and cp <= 0x5A) or (cp >= 0x61 and cp <= 0x7A):
		return true
	if EXTRA_ALLOWED.contains(char(cp)):
		return true
	if cp >= 0xC0 and cp <= 0x17F and cp != 0xD7 and cp != 0xF7:
		return true  # Latin-1 letters + Latin Extended-A
	if cp == 0x1A0 or cp == 0x1A1 or cp == 0x1AF or cp == 0x1B0:
		return true  # Ơ ơ Ư ư
	if cp >= 0x1EA0 and cp <= 0x1EF9:
		return true  # Vietnamese precomposed block
	return NfcTable.COMBINING_CLASS.has(cp) and _is_vietnamese_mark(cp)


static func _is_vietnamese_mark(cp: int) -> bool:
	# grave, acute, circumflex, tilde, breve, hook above, horn, dot below
	return cp in [0x300, 0x301, 0x302, 0x303, 0x306, 0x309, 0x31B, 0x323]


## Canonical composition (NFC) for the Latin + Vietnamese repertoire of [NfcTable]:
## full canonical decomposition, canonical reordering of marks, then pairwise composition.
static func nfc(text: String) -> String:
	if _decompose.is_empty():
		for key: int in NfcTable.PAIRS:
			_decompose[NfcTable.PAIRS[key]] = key
	var cps := PackedInt32Array()
	for ch in text:
		_decompose_into(ch.unicode_at(0), cps)
	_reorder(cps)
	return _compose(cps)


static func _decompose_into(cp: int, out: PackedInt32Array) -> void:
	if _decompose.has(cp):
		var key: int = _decompose[cp]
		_decompose_into(key >> 21, out)
		out.append(key & 0x1FFFFF)
	else:
		out.append(cp)


static func _ccc(cp: int) -> int:
	var cls: int = NfcTable.COMBINING_CLASS.get(cp, 0)
	return cls


static func _reorder(cps: PackedInt32Array) -> void:
	# Stable insertion sort of each run of non-starters by combining class.
	var i := 1
	while i < cps.size():
		var c := _ccc(cps[i])
		if c != 0:
			var j := i
			while j > 0 and _ccc(cps[j - 1]) > c:
				var tmp := cps[j - 1]
				cps[j - 1] = cps[j]
				cps[j] = tmp
				j -= 1
		i += 1


static func _compose(cps: PackedInt32Array) -> String:
	if cps.is_empty():
		return ""
	var out := PackedInt32Array()
	out.append(cps[0])
	var starter_pos := 0
	var last_class := 256 if _ccc(cps[0]) != 0 else 0
	for i in range(1, cps.size()):
		var ch := cps[i]
		var cls := _ccc(ch)
		var key := (out[starter_pos] << 21) | ch
		if NfcTable.PAIRS.has(key) and (last_class < cls or last_class == 0):
			out[starter_pos] = NfcTable.PAIRS[key]
			continue
		if cls == 0:
			starter_pos = out.size()
		last_class = cls
		out.append(ch)
	var s := ""
	for cp: int in out:
		s += char(cp)
	return s
