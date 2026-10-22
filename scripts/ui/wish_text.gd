class_name WishText
extends RefCounted
## Active F1 wish copy (ACTIVE_WISHES §7.2, §7.4, §13; strings.csv WISH_*): every placeholder a
## wish string can hold, filled from the content and a name lookup, so no "{spot}" ever reaches
## the screen. Pure (the caller passes the display-name lookup; tests pass their own).
##
##   {name}    the friend's display name
##   {friend}  its best buddy's display name (species.best_friend)
##   {spot}    its favourite spot's name (SPOT_<ID>)
##   {wish}    the wish title (A11Y lines)
##   {hint}    the hint line (A11Y lines)

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

## The name tag while a friend holds a wish: "{name} · {wish}" (ACTIVE_WISHES §7.2).
const TAG_KEY := "WISH_NAME_TAG"


## Placeholder values for [param species]'s wishes. [param names]: (StringName) -> String.
static func args(content: GameContent, species: StringName, names: Callable) -> Dictionary:
	var s: Dictionary = content.species_by_id.get(species, {})
	var buddy := StringName(String(s.get("best_friend", "")))
	var spot := String(s.get("favourite_spot", ""))
	return {"name": String(names.call(species)), "friend": String(names.call(buddy)) if buddy != &"" else "",
		"spot": TranslationServer.translate("SPOT_" + spot.to_upper()) if spot != "" else ""}


## The wish's title for [param species] (wishes.json title_key, placeholders filled).
static func title(content: GameContent, wish: StringName, species: StringName, names: Callable) -> String:
	return _fmt(_key(content, wish, "title_key"), args(content, species, names))


## The wish's hint line for [param species].
static func hint(content: GameContent, wish: StringName, species: StringName, names: Callable) -> String:
	return _fmt(_key(content, wish, "hint_key"), args(content, species, names))


## The name tag: "{name} · {wish title}".
static func tag(content: GameContent, wish: StringName, species: StringName, names: Callable) -> String:
	return _fmt(TAG_KEY, {"name": String(names.call(species)), "wish": title(content, wish, species, names)})


## A11Y_WISH_BUBBLE / A11Y_WISH_LIST_ROW for [param species]'s wish.
static func a11y(content: GameContent, key: StringName, wish: StringName, species: StringName,
		names: Callable) -> String:
	var a := args(content, species, names)
	a["wish"] = title(content, wish, species, names)
	a["hint"] = hint(content, wish, species, names)
	return _fmt(String(key), a)


## Fills every {placeholder} in the translation of [param key] that [param a] knows.
static func _fmt(key: String, a: Dictionary) -> String:
	if key == "":
		return ""
	return TranslationServer.translate(key).format(a)


static func _key(content: GameContent, wish: StringName, field: String) -> String:
	var def: Dictionary = content.wishes_by_id.get(wish, {})
	return String(def.get(field, ""))
