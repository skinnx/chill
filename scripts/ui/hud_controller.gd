class_name HudController
extends Control
## The HUD root (scenes/main.tscn HUD/HudRoot; Art Bible §9, GDD §3.4, §7.5, §8; ARCHITECTURE
## §3.3, §12): builds the top bar, the dock, the sheet host and the overlays inside the scene's
## named hosts, and owns the flows that join them:
##  * dock buttons open / close / swap the sheets; the dock shows the open sheet as active;
##  * ambient watch (the eye, or 60 s without input when "Hide buttons while I watch" is on):
##    HUD and dock fade out over 600 ms, the first tap only wakes them;
##  * onboarding (GDD §3.4): Garden, Basket and Album sleep at 50 % until their moment;
##  * welcome-back recap (world_ready), new-friend card (met), leave dialog (Back at Main),
##    sound captions (AudioDirector.cue_played), choose-a-bed mode, postcards from the mailbox;
##  * left-handed mirroring and safe areas.
##
## QA user args (tools/qa/capture.sh still ... --qa-sheet=garden):
##   --qa-sheet=garden|album|basket|settings   open that sheet instantly once the world is ready
##   --qa-tab=<n>          select tab n of the open sheet (Garden: 1 = Décor; Album: 1 Photos, 2 Postcards)
##   --qa-recap            show the welcome-back card with sample lines (no auto-dismiss)
##   --qa-peek             hold the time chip's label peek open
##   --qa-ambient          enter ambient watch (HUD hidden)
##   --qa-leave            show "Leave the hollow for now?"
##   --qa-toast            show a sample toast (choose-a-bed copy)
##   --qa-newfriend=<id>   show the new-friend card for that species
##   --qa-friend=<id>      open the Album on that friend's detail card
##   --qa-press=<dock id>  hold that dock button pressed (touch feedback still)
##   --qa-captions         show a sample caption bubble (Captions on)
##   --qa-met=<n>          (with --no-save captures) mark the first n friends met, with hearts,
##                         photos and two postcards, so the Album shows a lived-in collection

# Data boundary: values read from JSON / Dictionaries are Variants and each one is converted
# explicitly (int(), float(), String() ...) where it is read; the analyzer still flags every
# such conversion, so only that warning is silenced in this file (docs/ARCHITECTURE.md §10).
@warning_ignore_start("unsafe_call_argument")

const ARG_SHEET := "--qa-sheet="
const ARG_TAB := "--qa-tab="
const ARG_RECAP := "--qa-recap"
const ARG_PEEK := "--qa-peek"
const ARG_AMBIENT := "--qa-ambient"
const ARG_LEAVE := "--qa-leave"
const ARG_TOAST := "--qa-toast"
const ARG_NEWFRIEND := "--qa-newfriend="
const ARG_FRIEND := "--qa-friend="
const ARG_PRESS := "--qa-press="
const ARG_CAPTIONS := "--qa-captions"
const ARG_MET := "--qa-met="
## --qa-met: friends met this many days apart, hearts cycling 1..5, photos and two postcards.
const QA_MET_DAY_S := 86400.0
const QA_PHOTO_BITS := [0b00001, 0b00011, 0b10101, 0b01111, 0b11111]
const SHEETS: Array[StringName] = [&"settings", &"garden", &"basket", &"album"]
## New-friend card waits for the friend to settle (GDD §3.4 "When Pip settles").
const NEW_FRIEND_DELAY_S := 3.0
const MAILBOX_ACTION := &"open_postcards"
const BASKET_ACTION := &"open_basket"
const PROPS_PATH := "World/Ground/Play/Props/PropsLayer"
const CREATURES_PATH := "World/Ground/Play/Creatures/CreatureLayer"

var top_bar: TopBarView
var dock: DockView
var sheets: SheetHost
var overlays: OverlayHost
var ambient: bool = false
var _idle_s: float = 0.0
var _safe := Rect2(48, 72, 48, 127)
var _qa: Dictionary = {}
var _qa_done: bool = false
var _garden_seen: bool = false
var _choose_flower: StringName = &""
var _choose_back := Callable()
var _pending_friends: Array[StringName] = []

@onready var _safe_area: SafeAreaContainer = $SafeArea
@onready var _sheets_host: Control = $Sheets
@onready var _overlays_host: Control = $Overlays


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Children are built now, before Main attaches the theme in its own _ready (theme propagation
	# stops at the CanvasLayer), so the HUD takes it here first (idempotent with Main's attach).
	UiTheme.attach(self)
	_parse_qa()
	sheets = SheetHost.new()
	sheets.name = "SheetHost"
	sheets.factory = _make_sheet
	_sheets_host.add_child(sheets)
	top_bar = TopBarView.new()
	top_bar.name = "TopBarView"
	sheets.chrome.add_child(top_bar)
	dock = DockView.new()
	dock.name = "DockView"
	sheets.chrome.add_child(dock)
	overlays = OverlayHost.new()
	overlays.name = "OverlayHost"
	overlays.hud = self
	_overlays_host.add_child(overlays)
	top_bar.watch_pressed.connect(func() -> void: set_ambient(true))
	dock.button_pressed.connect(_on_dock)
	sheets.sheet_changed.connect(_on_sheet_changed)
	_safe_area.margins_changed.connect(func(m: Rect2) -> void:
		_safe = m
		_layout())
	get_viewport().size_changed.connect(_layout)
	Settings.changed.connect(_on_setting)
	Game.world_ready.connect(_on_world_ready)
	Game.sim_event.connect(_on_sim_event)
	Game.wallet_changed.connect(func(_d: int) -> void: _refresh_onboarding())
	Game.basket_changed.connect(func(_n: int, _d: int) -> void:
		_refresh_onboarding()
		sheets.refresh())
	Game.leave_requested.connect(func() -> void: overlays.show_leave())
	AudioDirector.cue_played.connect(overlays.on_cue_played)
	_connect_world.call_deferred()
	top_bar.left_handed = Settings.get_bool(Settings.LEFT_HANDED)
	dock.left_handed = top_bar.left_handed
	_layout.call_deferred()
	_refresh_onboarding()
	if Game.is_ready:
		_apply_qa.call_deferred()


func _exit_tree() -> void:
	# Static caches (icons, preview builders, the portrait rig) hold GPU textures: release them
	# with the HUD so nothing is reported leaked at exit (QA smoke gate).
	Icons.clear_cache()
	ItemPreview.release_shared()
	CreaturePortrait.release_shared()


func _process(delta: float) -> void:
	if ambient or sheets.is_open() or overlays.is_modal_open():
		_idle_s = 0.0
		return
	if not Settings.get_bool(Settings.AUTO_HIDE_UI):
		return
	_idle_s += delta
	if _idle_s >= UiTokens.ui_float("auto_hide_after_s", 60.0):
		set_ambient(true)


func _input(event: InputEvent) -> void:
	var press := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
			or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if not press:
		return
	_idle_s = 0.0
	if ambient:
		# GDD §1.5 / Art Bible §9.6: the first tap only wakes the HUD.
		set_ambient(false)
		get_viewport().set_input_as_handled()


## Ambient watch: HUD and dock fade over durations_ms.hud_ambient_fade; out on `short`.
func set_ambient(on: bool, instant: bool = false) -> void:
	if ambient == on:
		return
	ambient = on
	if on:
		sheets.close()
	FrameGovernor.ambient_mode = on
	top_bar.set_ambient_icon(on)
	var chrome := sheets.chrome
	var dur := UiTokens.seconds("hud_ambient_fade") if on else Motion.duration(&"short")
	if instant:
		chrome.modulate.a = 0.0 if on else 1.0
	else:
		var t := chrome.create_tween()
		t.tween_property(chrome, "modulate:a", 0.0 if on else 1.0, dur).set_trans(Tween.TRANS_SINE) \
				.set_ease(Tween.EASE_IN_OUT)
		FrameGovernor.hold_for(dur)
	chrome.visible = true
	_set_chrome_input(not on)


func _set_chrome_input(enabled: bool) -> void:
	for c: Node in [top_bar.eye] + dock.buttons.values():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE


func open_sheet(id: StringName, instant: bool = false) -> void:
	if ambient:
		set_ambient(false, true)
	sheets.toggle(id, instant)


func _layout() -> void:
	var screen := get_viewport_rect().size
	top_bar.layout(screen, _safe.position.y)
	dock.layout(screen, _safe.size.y)
	sheets.layout(screen, dock.pill_rect().position.y)
	overlays.layout(screen, _safe)


func _make_sheet(id: StringName) -> UiSheet:
	match id:
		&"garden":
			var g := GardenSheet.new()
			g.hud = self
			return g
		&"album":
			return AlbumSheet.new()
		&"basket":
			var b := BasketSheet.new()
			b.hud = self
			return b
		&"settings":
			return SettingsSheet.new()
	return null


func _on_dock(id: StringName) -> void:
	if id == &"garden":
		_garden_seen = true
		dock.set_new_dot(false)
	open_sheet(id)


func _on_sheet_changed(id: StringName) -> void:
	dock.set_active(id)


func _on_setting(key: StringName, value: Variant) -> void:
	if key == Settings.LEFT_HANDED:
		top_bar.left_handed = bool(value)
		dock.left_handed = bool(value)
		_layout()


func _on_world_ready(recap: Array) -> void:
	_refresh_onboarding()
	if not recap.is_empty():
		overlays.show_recap(recap)
	if not _qa.is_empty():
		_apply_qa.call_deferred()


func _on_sim_event(ev: Dictionary) -> void:
	var type := StringName(String(ev.get("type", "")))
	if type == WorldSim.EV_MET and not bool(ev.get("catch_up", false)):
		var sp := StringName(String(ev.get("species", "")))
		_pending_friends.append(sp)
		get_tree().create_timer(NEW_FRIEND_DELAY_S).timeout.connect(_show_next_friend)
	if type in [WorldSim.EV_PLANTED, WorldSim.EV_PLACED, WorldSim.EV_COLLECTED, WorldSim.EV_STAGE,
			WorldSim.EV_HEARTS, WorldSim.EV_POSTCARD, WorldSim.EV_MET, WorldSim.EV_PHOTO]:
		sheets.refresh()
	_refresh_onboarding()


func _show_next_friend() -> void:
	if _pending_friends.is_empty():
		return
	var sp: StringName = _pending_friends.pop_front()
	overlays.show_new_friend(sp)


## GDD §3.4: Garden, Basket and Album are asleep (50 %) until their onboarding moment; Settings is
## always awake. Garden gets a small "new" dot when it wakes.
func _refresh_onboarding() -> void:
	if Game.sim == null or dock == null:
		return
	var st := Game.sim.state
	var collected := st.last_collect_t > 0.0 or st.dew > 0 or st.items_bought > 0
	var garden_awake := collected
	var was_asleep := dock.button(&"garden").asleep
	dock.set_asleep(&"garden", not garden_awake)
	dock.set_asleep(&"basket", not (collected or not st.basket.is_empty()))
	dock.set_asleep(&"album", Game.sim.met_count() == 0)
	dock.set_glint(not st.basket.is_empty() and st.last_collect_t <= 0.0 and sheets.current_id != &"basket")
	if was_asleep and garden_awake and not _garden_seen and Game.is_ready:
		dock.set_new_dot(true)


# ------------------------------------------------------------------ world hooks

func _connect_world() -> void:
	var main := owner if owner != null else get_parent()
	var props := main.get_node_or_null(PROPS_PATH) if main != null else null
	if props != null and props.has_signal(&"prop_tapped"):
		props.connect(&"prop_tapped", _on_prop_tapped)
	var creatures := main.get_node_or_null(CREATURES_PATH) if main != null else null
	if creatures != null and creatures.has_signal(&"card_requested"):
		creatures.connect(&"card_requested", func(sp: StringName) -> void: open_friend(sp))
	if PlotsLayer.current != null:
		PlotsLayer.current.bed_chosen.connect(_on_bed_chosen)
		PlotsLayer.current.bed_card_requested.connect(func(bed: StringName) -> void: overlays.show_bed_card(bed))


func _on_prop_tapped(_prop: StringName, action: StringName, _pos: Vector2) -> void:
	if action == BASKET_ACTION:
		if sheets.current_id != &"basket":
			open_sheet(&"basket")
	elif action == MAILBOX_ACTION:
		overlays.show_postcard_or_album()


## Album on a friend's detail card (a second tap on a mossling, GDD §3.1).
func open_friend(species: StringName) -> void:
	if sheets.current_id != &"album":
		open_sheet(&"album", Motion.reduce_motion)
	var a := sheets.current as AlbumSheet
	if a != null:
		a.show_friend(species)


## Garden -> Plant on a flower's first copy (GDD §2.4 rule 1): the sheet exits, a toast asks for a
## bed, beds with room glow; a tap plants, Back cancels.
func begin_choose_bed(flower: StringName) -> void:
	if PlotsLayer.current == null:
		Game.plant(flower)
		return
	_choose_flower = flower
	sheets.close()
	PlotsLayer.current.choose_mode = true
	var f: Dictionary = ContentRegistry.content.flowers_by_id.get(flower, {})
	overlays.show_toast(I18n.fmt(&"GARDEN_CHOOSE_BED", {"flower": tr(String(f.get("name_key", ""))).to_lower()}), 0.0)
	_choose_back = cancel_choose_bed
	Game.push_back_handler(_choose_back)


func cancel_choose_bed() -> void:
	if _choose_flower == &"":
		return
	_choose_flower = &""
	if PlotsLayer.current != null:
		PlotsLayer.current.choose_mode = false
	overlays.hide_toast()
	Game.remove_back_handler(_choose_back)


func _on_bed_chosen(bed: StringName) -> void:
	if _choose_flower == &"":
		return
	var flower := _choose_flower
	cancel_choose_bed()
	Game.plant(flower, bed)


# ------------------------------------------------------------------ QA

func _parse_qa() -> void:
	for a: String in OS.get_cmdline_user_args():
		for key: String in [ARG_SHEET, ARG_TAB, ARG_NEWFRIEND, ARG_FRIEND, ARG_PRESS, ARG_MET]:
			if a.begins_with(key):
				_qa[key] = a.trim_prefix(key)
		for flag: String in [ARG_RECAP, ARG_PEEK, ARG_AMBIENT, ARG_LEAVE, ARG_TOAST, ARG_CAPTIONS]:
			if a == flag:
				_qa[flag] = true


func _apply_qa() -> void:
	if _qa.is_empty() or _qa_done:
		return
	_qa_done = true
	if _qa.has(ARG_MET):
		_qa_seed_album(int(String(_qa[ARG_MET])))
	if _qa.has(ARG_FRIEND):
		open_friend(StringName(String(_qa[ARG_FRIEND])))
	elif _qa.has(ARG_SHEET):
		var id := StringName(String(_qa[ARG_SHEET]))
		if SHEETS.has(id):
			open_sheet(id, true)
			if _qa.has(ARG_TAB) and sheets.current != null and sheets.current.has_method(&"select_tab"):
				sheets.current.call(&"select_tab", int(String(_qa[ARG_TAB])), false)
	if _qa.has(ARG_RECAP):
		overlays.show_recap(overlays.sample_recap(), true)
	if _qa.has(ARG_PEEK):
		top_bar.peek(true)
	if _qa.has(ARG_AMBIENT):
		set_ambient(true, true)
	if _qa.has(ARG_LEAVE):
		overlays.show_leave(true)
	if _qa.has(ARG_TOAST):
		overlays.show_toast(I18n.fmt(&"GARDEN_CHOOSE_BED", {"flower": tr("FLOWER_SWEET_CLOVER_NAME").to_lower()}), 0.0,
				true)
	if _qa.has(ARG_NEWFRIEND):
		overlays.show_new_friend(StringName(String(_qa[ARG_NEWFRIEND])), true)
	if _qa.has(ARG_PRESS):
		var b := dock.button(StringName(String(_qa[ARG_PRESS])))
		if b != null:
			b.force_pressed = true
			PressFeedback.down(b)
	if _qa.has(ARG_CAPTIONS):
		overlays.show_caption(tr("CAPTION_CHIRP"), get_viewport_rect().size * Vector2(0.5, 0.55), true)


## QA only (captures run with --no-save): a lived-in Album without playing for days.
func _qa_seed_album(n: int) -> void:
	var sim := Game.sim
	if sim == null:
		return
	var content := ContentRegistry.content
	var thresholds: Array = content.economy.get("heart_thresholds", [])
	var now := Clock.now_unix()
	for i in mini(n, content.species.size()):
		var sp := String(content.species[i]["id"])
		sim.state.met[sp] = now - QA_MET_DAY_S * float(n - i)
		var hearts := 1 + i % thresholds.size()
		sim.state.affection[sp] = int(thresholds[hearts - 1])
		sim.state.photos[sp] = int(QA_PHOTO_BITS[i % QA_PHOTO_BITS.size()])
	for i in mini(2, n):
		var s: Dictionary = content.species[i]
		sim.state.postcards.append({"id": "qa_%d" % i, "template": String(s["postcard_heart2"]),
			"species": String(s["id"]), "received_unix": now, "read": i == 0})
	_refresh_onboarding()
