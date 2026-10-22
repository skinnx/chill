class_name ActiveFixture
extends RefCounted
## QA save fixture for Active Play v1 (GDD §14.11; docs/QA.md):
##
##   tools/qa/capture.sh still --tod=0.6 --fixture=active_mid --out=qa/out/active_mid.png
##   tools/qa/capture.sh still --tod=0.6 --fixture=active_mid --debug-hits --out=...
##
## active_mid = the garden_mid garden (GardenFixture) plus: five friends met with hearts 1-3,
## three of them visiting; two open wishes (puffmoss craves clover tea, buttonbud wants to nap
## beside the daisies) and one held by an away friend (dandelfluff, a pinwheel spin); a few stamps
## and granted wishes; the tea nook awake with petals in five jars, full petal glints on bed_1, two
## petals stirred halfway in the pot, two cups on the tray, six recipes found (two reactions seen)
## and a teaware piece in use; and free-placed décor (pinwheels moved up the hill crest, the
## toadstool ring rebuilt beside the moss cushion, one lantern turned, a second cairn stack, a
## stream stone tucked away). Placement goes through the real rules (ActiveRules.move), so every
## piece stands on valid ground. Written into the state at its world time; captures run with
## --no-save, so a fixture never reaches a real save.
##
## Wiring: GardenFixture.apply_from_args (PlotsLayer._ready) hands over to [method apply_from_args].

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const NAME := "active_mid"
const HOUR := 3600.0
const DAY := 86400.0
## species -> affection (hearts 1-3 at the 3/8/15 thresholds; economy.json).
const AFFECTION := {&"puffmoss": 16, &"buttonbud": 9, &"pebblepaw": 4, &"honeyhum": 8, &"dandelfluff": 3}
const VISITING: Array[StringName] = [&"puffmoss", &"buttonbud", &"honeyhum"]
## [species, wish, state]: two bubbles in the hollow, one wish kept by an away friend.
const WISHES: Array[Array] = [
	[&"puffmoss", &"clover_tea", "open"],
	[&"buttonbud", &"nap_daisies", "open"],
	[&"dandelfluff", &"pinwheel_spin", "held"],
]
const STAMPS := {&"puffmoss": [&"cuddle", &"clover_nibble"], &"buttonbud": [&"tag_game"],
	&"honeyhum": [&"buttercup_sip"]}
const PANTRY := {&"sweet_clover": 6, &"button_daisy": 4, &"forget_me_not": 3, &"buttercup": 2, &"bluebell": 1}
const RECIPES: Array[StringName] = [&"clover_tea", &"daisy_tea", &"meadow_blend", &"blue_sky_tea", &"meadow_tea",
	&"daisy_biscuit"]
const PREFS_SEEN := {&"puffmoss": [&"clover_tea"], &"buttonbud": [&"daisy_tea"]}
const TRAY: Array[Array] = [[&"clover_tea", [&"sweet_clover", &"sweet_clover"], 0],
	[&"daisy_biscuit", [&"button_daisy", &"button_daisy"], 2]]
const TEAWARE := &"daisy_cup"
## Décor moves: [piece id, x, y, rot] in frame-normalised foot positions (resolved by the rules).
const MOVES: Array[Array] = [
	["leaf_pinwheel#0", 0.53, 0.392, 0],
	["leaf_pinwheel#1", 0.585, 0.39, 1],
	["leaf_pinwheel#2", 0.635, 0.396, 3],
	["toadstool_seat#0", 0.27, 0.565, 0],
	["toadstool_seat#1", 0.3, 0.548, 1],
	["toadstool_seat#2", 0.24, 0.548, 2],
	["toadstool_seat#3", 0.255, 0.585, 3],
	["firefly_lantern#1", 0.76, 0.728, 1],
	["pebble_cairn#2", 0.12, 0.72, 0],
]
const STORED: Array[String] = ["stream_stones#3"]

static var applied: bool = false


static func wanted() -> bool:
	return RetentionFixture.requested_fixture() == NAME


## QA hook (idempotent): the garden_mid world, then the Active Play state, on a rebuilt Game.sim.
static func apply_from_args(content: GameContent) -> void:
	if applied or Game.sim == null:
		return
	var state := Game.sim.state
	GardenFixture.apply(content, state, GardenFixture.MID)
	GardenFixture.applied = GardenFixture.MID
	Game.sim = WorldSim.new(content, state)  # migrates the décor from the anchors
	apply(Game.sim)
	Game.sim = WorldSim.new(content, state)  # derived caches and spots from the final state
	Game.sim.drain_events()
	applied = true


## Writes the active_mid friends, wishes, tea and décor into [param sim]'s state at its world time.
static func apply(sim: WorldSim) -> void:
	var content := sim.content
	var st := sim.state
	var t := st.t
	for sp: StringName in AFFECTION:
		st.met[String(sp)] = sim.unix_at(t - 2.0 * DAY)
		st.affection[String(sp)] = int(AFFECTION[sp])
		st.hearts_seen[String(sp)] = sim.hearts_of(sp)
		st.visit_aff_t[String(sp)] = t - HOUR
	st.present.clear()
	for i in VISITING.size():
		st.present.append({"species": String(VISITING[i]), "arrive_t": t - 300.0 - 60.0 * i, "depart_t": t + 2.0 * HOUR,
			"gift_dew": int(content.species_by_id[VISITING[i]]["gift_dew"]), "gift_item": "", "boat_credit": false,
			"pet_credit": false, "scripted": false, "greeter": false, "cousin": ""})
	# Active F2: the nook, jars, full glints on bed_1, a half-stirred pot, cups, the book, teaware.
	st.tea_unlocked = true
	for f: StringName in PANTRY:
		st.pantry[String(f)] = int(PANTRY[f])
	for i in st.stems.size():
		var stem: Dictionary = st.stems[i]
		if String(stem["bed"]) == "bed_1" and int(stem["stage"]) >= WorldSim.STAGE_BLOOM:
			st.petal_from_t[TeaRules.stem_key(stem)] = t - 3.0 * sim.active.tea.regrow_s(StringName(stem["flower"]))
	st.pot = {"petals": ["sweet_clover", "button_daisy"], "drops": 0, "stir_deg": 180.0}
	st.tray.clear()
	for row: Array in TRAY:
		st.tray.append({"recipe": String(row[0]), "made_unix": sim.unix_at(t - HOUR), "drops": int(row[2]),
			"petals": (row[1] as Array).map(func(f: Variant) -> String: return String(f))})
	for i in RECIPES.size():
		st.recipes_found[String(RECIPES[i])] = sim.unix_at(t - DAY + i * HOUR)
	for sp: StringName in PREFS_SEEN:
		st.tea_prefs_seen[String(sp)] = (PREFS_SEEN[sp] as Array).map(func(r: Variant) -> String: return String(r))
		st.tea_aff_t[String(sp)] = t - 2.0 * HOUR
	st.teaware_owned = [String(TEAWARE)]
	st.teaware_set = {"cup": String(TEAWARE)}
	st.cups_offered = 5
	st.tea_flags = {"first_hint_done": true, "nook_seen": true}
	# Active F1: stamps, then the pending wishes.
	for sp: StringName in STAMPS:
		var bits := 0
		for w: StringName in STAMPS[sp]:
			bits |= 1 << int(content.wish_index[w])
		st.wish_stamps[String(sp)] = bits
	st.wishes_granted = 6
	st.wish_tutorial_done = true
	st.wishes.clear()
	for i in WISHES.size():
		var row: Array = WISHES[i]
		var at := t - 240.0 + 90.0 * i
		st.wishes.append({"species": String(row[0]), "wish": String(row[1]), "opened_t": at, "state": String(row[2]),
			"taps": 0, "placed": false})
		st.wish_friend_t[String(row[0])] = at
		st.wish_last_id[String(row[0])] = String(row[1])
	st.wish_last_t = t - 60.0
	st.wish_checks = 24
	st.wish_list_seen_t = t - HOUR
	# Active F3: free-placed pieces through the real rules, one tucked away.
	for m: Array in MOVES:
		sim.active.move(sim, String(m[0]), Vector2(float(m[1]), float(m[2])), int(m[3]))
	for id: String in STORED:
		sim.active.store(sim, id)
	sim.active.refresh_spots(sim)
	st.active_v = WorldState.ACTIVE_VERSION
