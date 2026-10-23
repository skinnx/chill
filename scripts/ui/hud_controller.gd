class_name HudController
extends Control
## The HUD root (scenes/main.tscn HUD/HudRoot; Art Bible §9, GDD §3.4, §7.5, §8; ARCHITECTURE
## §3.3, §12): builds the top bar, the dock, the sheet host and the overlays inside the scene's
## named hosts, and owns the flows that join them:
##  * dock buttons (Album, Garden, Basket) and the top bar's Settings gear open / close / swap the
##    sheets; the dock (or the gear) shows the open sheet as active;
##  * ambient watch (the eye, or 60 s without input when "Hide buttons while I watch" is on):
##    HUD and dock fade out over 600 ms, the first tap only wakes them;
##  * onboarding (GDD §3.4): Garden, Basket and Album sleep (full colour, a sleepy icon) until
##    their moment; Garden and Album get a tiny sparkle when something new waits there;
##  * welcome-back recap (world_ready), new-friend card (met), leave dialog (Back at Main),
##    sound captions (AudioDirector.cue_played), choose-a-bed mode, postcards from the mailbox;
##  * left-handed mirroring and safe areas.
##
## QA user args (tools/qa/capture.sh still ... --qa-sheet=garden):
##   --qa-sheet=garden|album|basket|settings|tea   open that sheet instantly once the world is ready
##                         (Tea: see TeaSheet --qa-tea for its mid-interaction states)
##   --qa-tab=<n>          select tab n of the open sheet (Garden: 1 = Décor; Album: 1 Photos, 2 Postcards)
##   --qa-recap            show the welcome-back card with sample lines (no auto-dismiss)
##   --qa-peek             hold the time chip's label peek open
##   --qa-ambient          enter ambient watch (HUD hidden)
##   --qa-leave            show "Leave the hollow for now?"
##   --qa-toast            show a sample toast (choose-a-bed copy)
##   --qa-newfriend=<id>   show the new-friend card for that species
##   --qa-friend=<id>      open the Album on that friend's detail card ("present": a met friend
##                         who is visiting right now, so the card shows Pet)
##   --qa-press=<target>   freeze a touch-down for the touch strip: a dock tab (garden, basket,
##                         album), settings (= gear, the top bar's Settings button), eye, close
##                         (the open sheet's close), primary (the open sheet's or modal's first
##                         enabled primary pill: Plant, Collect all, Say hello), tab (the open
##                         sheet's second segment), card (the Album's first friend card), toggle
##                         (Settings' first switch row)
##   --qa-press-t=<ms>     time after touch-down to freeze at (default 60 = the press dip near its
##                         peak with the ripple a sixth grown; 0..380 shows the whole ripple)
##   --qa-drawcalls        print "qa-drawcalls: <n>" (RENDER_TOTAL_DRAW_CALLS_IN_FRAME) every 30 frames
##   --qa-ui-audit         with a sheet or modal open: the draw calls of each UiBatch z layer of it
##   --qa-captions         show a sample caption bubble (Captions on)
##   --qa-met=<n>          (with --no-save captures) mark the first n friends met, with hearts,
##                         photos and two postcards, so the Album shows a lived-in collection
##   --qa-scroll=<v>       scroll the open sheet's list: a fraction 0..1 of its range ("0.5",
##                         "1" = the end) or px ("640px"), after its layout settles
##   --qa-detent=large     open the sheet at its large detent
##   --qa-rename           (with --qa-friend) start renaming: the name field focused, all selected
##   --qa-kb=<px>          simulate an on-screen keyboard this tall (canvas px; drawn as a grey
##                         block) so the sheet's keyboard lift can be captured on desktop

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
const ARG_PRESS_T := "--qa-press-t="
const ARG_DRAWCALLS := "--qa-drawcalls"
## Round 5: with a sheet open, prints what each UiBatch layer of it costs ("qa-ui-audit:" lines).
const ARG_UI_AUDIT := "--qa-ui-audit"
const QA_PRESS_T_MS := 60.0
const QA_DRAWCALL_EVERY := 30
const ARG_CAPTIONS := "--qa-captions"
const ARG_MET := "--qa-met="
const ARG_SCROLL := "--qa-scroll="
const ARG_DETENT := "--qa-detent="
const ARG_RENAME := "--qa-rename"
const ARG_KB := "--qa-kb="
## Frames for a sheet's containers, bakes and springs to settle before --qa-scroll applies.
const QA_SETTLE_FRAMES := 6
## --qa-met: friends met this many days apart, hearts cycling 1..5, photos and two postcards.
const QA_MET_DAY_S := 86400.0
const QA_PHOTO_BITS := [0b00001, 0b00011, 0b10101, 0b01111, 0b11111]
const SHEETS: Array[StringName] = [&"settings", &"garden", &"basket", &"album", &"tea"]
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
## Night chrome (palettes ui_alpha.night_chrome): on after dark, with hysteresis on g_lights.
var night_on: bool = false
var _idle_s: float = 0.0
var _safe := Rect2(48, 72, 48, 127)
var _qa: Dictionary = {}
var _qa_done: bool = false
var _garden_seen: bool = false
var _choose_flower: StringName = &""
var _choose_back := Callable()
var _pending_friends: Array[StringName] = []
var _night_known: bool = false
var _night_k: float = 0.0
var _night_tween: Tween
var _qa_frames: int = 0
## Swallows the rest of the gesture whose first touch woke the HUD from ambient watch.
var _wake_gate := PointerGate.new()
## Active F3 edit mode is on (DecorEdit): the top bar and dock make way for the edit chrome.
var _decor_edit: bool = false

@onready var _safe_area: SafeAreaContainer = $SafeArea
@onready var _sheets_host: Control = $Sheets
@onready var _overlays_host: Control = $Overlays


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Children are built now, before Main attaches the theme in its own _ready (theme propagation
	# stops at the CanvasLayer), so the HUD takes it here first (idempotent with Main's attach).
	UiTheme.attach(self)
	_parse_qa()
	var baker := SnapshotBaker.new()
	baker.name = "SnapshotBaker"
	add_child(baker)
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
	top_bar.settings_pressed.connect(func() -> void: open_sheet(&"settings"))
	dock.button_pressed.connect(_on_dock)
	sheets.sheet_changed.connect(_on_sheet_changed)
	_safe_area.margins_changed.connect(func(m: Rect2) -> void:
		_safe = m
		_layout())
	get_viewport().size_changed.connect(_layout)
	# the dock and the top bar grow with the Text size setting (round 5)
	UiTheme.theme_rebuilt.connect(func(_t: Theme) -> void: _layout.call_deferred())
	Settings.changed.connect(_on_setting)
	Game.world_ready.connect(_on_world_ready)
	Game.sim_event.connect(_on_sim_event)
	Game.wallet_changed.connect(func(_d: int) -> void: _refresh_onboarding())
	Game.basket_changed.connect(func(_n: int, _d: int) -> void:
		_refresh_onboarding()
		sheets.refresh())
	Game.leave_requested.connect(func() -> void: overlays.show_leave())
	Game.clue_found.connect(_on_clue_found)
	Game.decor_edit_entered.connect(_on_decor_edit.bind(true))
	Game.decor_edit_exited.connect(_on_decor_edit.bind(false))
	TimeOfDay.globals_updated.connect(_on_globals)
	_on_globals({&"g_lights": float(TimeOfDay.scalars.get("lights", 0.0))})
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
	GlassPanel.release_shared()
	UiSurface.release_shared()
	UiBatch.release_shared()


func _process(delta: float) -> void:
	if _qa.has(ARG_DRAWCALLS):
		_qa_frames += 1
		if _qa_frames % QA_DRAWCALL_EVERY == 0:
			print("qa-drawcalls: %d" % int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	if ambient or sheets.is_open() or overlays.is_modal_open() or _decor_edit:
		_idle_s = 0.0
		return
	if not Settings.get_bool(Settings.AUTO_HIDE_UI):
		return
	_idle_s += delta
	if _idle_s >= UiTokens.ui_float("auto_hide_after_s", 60.0):
		set_ambient(true)


func _input(event: InputEvent) -> void:
	if _wake_gate.swallow(event):
		# GDD §1.5 / Art Bible §9.6: the touch that wakes the HUD only wakes it. Every event of that
		# gesture (the touch and its emulated mouse twin, their moves and releases) stops here, so
		# neither a dock tab nor the world behind it acts on it.
		get_viewport().set_input_as_handled()
		return
	if not PointerGate.is_press(event):
		return
	_idle_s = 0.0
	if ambient:
		set_ambient(false)
		_wake_gate.begin(event)
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


## After dark (round 4, QA r3: the cream dock and chips were a glare slab under the night sky):
## the HUD chrome switches to its night scheme (dim warm-navy glass, night_ink labels and icons;
## GlassPanel / TopBarView / DockView.set_night), crossfading over hud_ambient_fade when g_lights
## crosses night_chrome.on (back below .off). Sheets and overlays stay light, dimmed neutrally by
## night_chrome.sheet_dim x g_lights (no lavender cast: ink and the primary label keep >= 4.5:1).
func _on_globals(values: Dictionary) -> void:
	if not values.has(&"g_lights"):
		return
	var lights := clampf(float(values.get(&"g_lights", 0.0)), 0.0, 1.0)
	var nt := GlassPanel.night_tokens()
	var want := night_on
	if lights >= float(nt.get("on", 0.6)):
		want = true
	elif lights <= float(nt.get("off", 0.4)):
		want = false
	if want != night_on or not _night_known:
		set_night(want, not _night_known)
		_night_known = true
	# day-built sheets and cards dim neutrally toward dusk; night-built ones are already dim
	var dim := 1.0 if night_on else 1.0 - float(nt.get("sheet_dim", 0.08)) * lights
	var c := Color(dim, dim, dim)
	sheets.tint = c
	overlays.modulate = Color(c.r, c.g, c.b, overlays.modulate.a)


## Switches the chrome scheme (instant at start-up and for QA stills). Round 5: sheets and modal
## cards follow it too (palettes ui_night, QA r4: near-white sheets at night); an open sheet is
## rebuilt in the new scheme with the swap crossfade.
func set_night(on: bool, instant: bool = false) -> void:
	var changed := on != UiTokens.night_scheme
	night_on = on
	UiTokens.night_scheme = on
	if changed and sheets != null and sheets.is_open():
		sheets.rebuild(instant)
	if _night_tween != null and _night_tween.is_valid():
		_night_tween.kill()
	var to := 1.0 if on else 0.0
	if instant:
		_apply_night(to)
		return
	var dur := Motion.duration(&"reduce_motion_crossfade") if Motion.reduce_motion \
			else UiTokens.seconds("hud_ambient_fade")
	_night_tween = create_tween()
	_night_tween.tween_method(_apply_night, _night_k, to, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	FrameGovernor.hold_for(dur)


func _apply_night(k: float) -> void:
	_night_k = k
	GlassPanel.set_night(k)
	top_bar.set_night(k)
	dock.set_night(k)
	overlays.set_night(k)


func _set_chrome_input(enabled: bool) -> void:
	var controls: Array[Control] = [top_bar.eye, top_bar.gear]
	controls.append_array(dock.input_controls())
	for c: Control in controls:
		c.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	_sync_band()


## The top bar's band takes presses while the world is in view; under an open sheet the scrim does
## (a tap there closes the sheet as before), and in ambient watch the wake gate does.
func _sync_band() -> void:
	var on := not ambient and not sheets.is_open() and not _decor_edit
	top_bar.band.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE


## Active F3 edit mode (ACTIVE_DECOR §2, §11): the sheet exits, the top bar and the dock fade out on
## `short` and take no presses (the DecorEditChrome takes their places); back in play they return.
## Ambient watch and its auto-hide timer are off meanwhile.
func _on_decor_edit(on: bool) -> void:
	_decor_edit = on
	if on:
		if ambient:
			set_ambient(false, true)
		sheets.close()
	var chrome := sheets.chrome
	chrome.visible = true
	var t := Motion.tween(chrome, "modulate:a", 0.0 if on else 1.0, &"short")
	if on:
		# hidden once faded: an invisible top bar and dock would still cost their draw calls
		t.finished.connect(func() -> void: chrome.visible = not _decor_edit)
	_set_chrome_input(not on)


## Where the Active F3 edit chrome lives: above the sheets and the dock, under the modal cards and
## the toast.
func edit_chrome_host() -> Control:
	return _sheets_host


## The OS safe-area margins (position = left, top; size = right, bottom) in screen px.
func safe_margins() -> Rect2:
	return _safe


func open_sheet(id: StringName, instant: bool = false) -> void:
	if ambient:
		set_ambient(false, true)
	sheets.toggle(id, instant)


func _layout() -> void:
	var screen := get_viewport_rect().size
	top_bar.layout(screen, _safe.position.y)
	dock.layout(screen, _safe.size.y)
	sheets.top_limit = top_bar.bottom()
	sheets.layout(screen, dock.top())
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
		&"tea":
			return TeaSheet.make(self)
	return null


func _on_dock(id: StringName) -> void:
	if id == &"garden":
		_garden_seen = true
	dock.set_new(id, false)
	open_sheet(id)


func _on_sheet_changed(id: StringName) -> void:
	_sync_band()
	dock.set_active(id)
	top_bar.set_settings_open(id == &"settings")


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
		if sheets.current_id != &"album":
			dock.set_new(&"album", true)
		get_tree().create_timer(NEW_FRIEND_DELAY_S).timeout.connect(_show_next_friend)
	if type in [WorldSim.EV_PLANTED, WorldSim.EV_PLACED, WorldSim.EV_COLLECTED, WorldSim.EV_STAGE,
			WorldSim.EV_HEARTS, WorldSim.EV_POSTCARD, WorldSim.EV_MET, WorldSim.EV_PHOTO]:
		sheets.refresh()
	_refresh_onboarding()


## A sign was tapped and its clue taken (Retention v1 F2, GDD §13.3.2). A note opens the riddle
## reader; every other sign toasts what was found. The "added to your album" line shows once per
## install, on the very first clue, so the player learns where clues go and is never told again.
func _on_clue_found(clue: Dictionary) -> void:
	var line := clue_line(clue, _clues_found_total())
	if line == "":
		overlays.show_riddle(clue)  # the note is the one clue worth stopping for
		return
	overlays.show_toast(line)


## The toast a found clue shows, or "" when it is the note and the riddle card takes over
## (GDD §13.3.3). [param found_total] is clues found across every mystery: the line that explains
## where the clue went is only worth showing the first time.
static func clue_line(clue: Dictionary, found_total: int) -> String:
	var kind := String(clue.get("sign", ""))
	if kind == "note":
		return ""
	var line := I18n.fmt(StringName("CLUE_FOUND_%s" % kind.to_upper()))
	if found_total <= 1:
		line += "\n" + I18n.fmt(&"CLUE_ADDED")
	return "%s %s" % [I18n.fmt(&"CLUE_FOUND_TITLE"), line]


## Clues found across every mystery (for the once-per-install line above).
func _clues_found_total() -> int:
	var n := 0
	for c: Dictionary in Game.clue_cards():
		n += int(c.get("found", 0))
	return n


func _show_next_friend() -> void:
	if _pending_friends.is_empty():
		return
	var sp: StringName = _pending_friends.pop_front()
	overlays.show_new_friend(sp)


## GDD §3.4: Garden, Basket and Album are asleep (sleepy full-colour icons, round 6) until their
## onboarding moment; Settings (the top bar gear) is always awake. Garden gets a tiny "new"
## sparkle when it wakes.
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
		dock.set_new(&"garden", true)


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
	# Active F2: the tea nook prop, the petal toasts and --qa-tea (TeaSheet owns the wiring)
	TeaSheet.wire(self)


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
		for key: String in [ARG_SHEET, ARG_TAB, ARG_NEWFRIEND, ARG_FRIEND, ARG_PRESS_T, ARG_PRESS, ARG_MET,
				ARG_SCROLL, ARG_DETENT, ARG_KB]:
			if a.begins_with(key):
				_qa[key] = a.trim_prefix(key)
		for flag: String in [ARG_RECAP, ARG_PEEK, ARG_AMBIENT, ARG_LEAVE, ARG_TOAST, ARG_CAPTIONS, ARG_DRAWCALLS,
				ARG_UI_AUDIT, ARG_RENAME]:
			if a == flag:
				_qa[flag] = true


func _apply_qa() -> void:
	if _qa.is_empty() or _qa_done:
		return
	_qa_done = true
	if _qa.has(ARG_MET):
		_qa_seed_album(int(String(_qa[ARG_MET])))
	if _qa.has(ARG_FRIEND):
		var friend := StringName(String(_qa[ARG_FRIEND]))
		if friend == &"present" and Game.sim != null:
			# a met friend strolls in (the greeter rule), so the detail card shows Pet
			friend = Game.sim.add_greeter(Game.sim.state.t)
			if friend == &"" and not Game.sim.state.present.is_empty():
				friend = StringName(String((Game.sim.state.present[0] as Dictionary)["species"]))
		open_friend(friend)
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
	dock.snap_active()
	if _qa.has(ARG_PRESS):
		# After the sheet / modal has laid out (containers sort on the next frame).
		get_tree().process_frame.connect(_qa_press, CONNECT_ONE_SHOT)
	if _qa.has(ARG_CAPTIONS):
		overlays.show_caption(tr("CAPTION_CHIRP"), get_viewport_rect().size * Vector2(0.5, 0.55), true)
	if _qa.has(ARG_UI_AUDIT):
		_qa_ui_audit.call_deferred()
	if sheets.current != null and (_qa.has(ARG_SCROLL) or _qa.has(ARG_DETENT) or _qa.has(ARG_RENAME) or _qa.has(ARG_KB)):
		_qa_sheet_state.call_deferred()


## --qa-detent / --qa-kb / --qa-rename / --qa-scroll on the open sheet (in that order).
func _qa_sheet_state() -> void:
	var s := sheets.current
	if s == null:
		return
	if String(_qa.get(ARG_DETENT, "")) == "large":
		s.expand(true, false)
	if _qa.has(ARG_KB):
		var kb := float(String(_qa[ARG_KB]).trim_suffix("px"))
		sheets.qa_keyboard_px = kb
		var block := ColorRect.new()
		block.name = "QaKeyboard"
		block.color = Color(0.82, 0.83, 0.86)
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		block.position = Vector2(0.0, get_viewport_rect().size.y - kb)
		block.size = Vector2(get_viewport_rect().size.x, kb)
		block.z_index = 100
		overlays.add_child(block)
	if _qa.has(ARG_RENAME) and s is AlbumSheet:
		(s as AlbumSheet).begin_rename()
	for i in QA_SETTLE_FRAMES:
		await get_tree().process_frame
	if _qa.has(ARG_SCROLL) and is_instance_valid(s) and s.scroll_list() != null:
		var sc := s.scroll_list()
		var raw := String(_qa[ARG_SCROLL])
		var bar := sc.get_v_scroll_bar()
		var room := maxf(bar.max_value - bar.page, 0.0)
		sc.scroll_vertical = int(raw.trim_suffix("px").to_float()) if raw.ends_with("px") \
				else roundi(clampf(raw.to_float(), 0.0, 1.0) * room)


## --qa-ui-audit: hides each absolute z layer of the open sheet / modal in turn and prints its cost
## (draw calls averaged over a few frames, the world keeps animating).
func _qa_ui_audit() -> void:
	for i in 40:
		await get_tree().process_frame
	var root: CanvasItem = overlays if overlays.is_modal_open() else sheets.current
	if root == null:
		return
	var by_z: Dictionary = {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var leaf := n.get_child_count(true) == 0 or n is CreaturePortrait or n is LiveWell
		if n is CanvasItem and (n as CanvasItem).visible and leaf and n != root:
			var z := UiBatch._parent_abs(n) + (n as CanvasItem).z_index
			if not by_z.has(z):
				by_z[z] = []
			(by_z[z] as Array).append(n)
		if not (n is CreaturePortrait or n is LiveWell):
			for c: Node in n.get_children(true):
				stack.append(c)
	var avg := func() -> float:
		var sum := 0.0
		for k in 8:
			await get_tree().process_frame
			sum += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		return sum / 8.0
	var total: float = await avg.call()
	root.visible = false
	var world: float = await avg.call()
	root.visible = true
	print("qa-ui-audit: total %.1f  without the sheet/modal %.1f  -> it costs %.1f" % [total, world, total - world])
	var zs: Array = by_z.keys()
	zs.sort()
	for z: int in zs:
		var items: Array = by_z[z]
		for n: CanvasItem in items:
			n.visible = false
		var without: float = await avg.call()
		for n: CanvasItem in items:
			n.visible = true
		print("qa-ui-audit: z %3d  %3d leaves  %5.1f calls  (%s %s)" % [z, items.size(), total - without,
				(items[0] as Node).get_class(), (items[0] as Node).name])


## --qa-press: freeze the named target mid touch-down (see the header).
func _qa_press() -> void:
	await get_tree().process_frame
	var target := StringName(String(_qa[ARG_PRESS]))
	var t_s := float(String(_qa.get(ARG_PRESS_T, str(QA_PRESS_T_MS)))) * UiTokens.MS
	var c: Control = null
	var root: Node = overlays if overlays.is_modal_open() else sheets.current
	match target:
		&"eye":
			c = top_bar.eye
		&"settings", &"gear":
			c = top_bar.gear
		&"close":
			c = sheets.current.close_button if sheets.current != null else null
		&"primary":
			c = _find_control(root, func(n: Node) -> bool:
				return n is Button and not (n as Button).flat and (n as Button).theme_type_variation == &"" \
						and not (n as Button).disabled and (n as Button).text != "")
		&"tab":
			var seg := _find_control(root, func(n: Node) -> bool: return n is Segmented) as Segmented
			if seg != null and seg.get_child_count() > 1:
				c = seg.get_child(1) as Control
		&"card":
			c = _find_control(root, func(n: Node) -> bool:
				return n is Button and (n as Button).flat and n.get_child_count() > 0 and n.get_child(0) is PanelContainer)
		&"toggle":
			var tg := _find_control(root, func(n: Node) -> bool: return n is UiToggle) as UiToggle
			if tg != null:
				tg.force_pressed = true
				PressFeedback.pose(tg, t_s)
				var row := tg.get_parent()
				while row != null and not (row is PanelContainer):
					row = row.get_parent()
				if row != null and row.get_child(0) is Button:
					c = row.get_child(0) as Control
		_:
			c = dock.button(target)
	if c == null:
		push_warning("HUD: --qa-press target %s not found" % target)
		return
	if c is RoundButton:
		(c as RoundButton).force_pressed = true
	var at := Vector2(-1, -1)
	if c.has_meta(PressFeedback.META_RIPPLE_RECT):
		var r: Rect2 = c.get_meta(PressFeedback.META_RIPPLE_RECT)
		# a touch a little off-centre, as a thumb lands
		at = r.get_center() + r.size * Vector2(0.12, 0.08)
	PressFeedback.pose(c, t_s, at)


static func _find_control(root: Node, pred: Callable) -> Control:
	if root == null:
		return null
	for n: Node in root.get_children():
		if pred.call(n):
			return n as Control
		var hit := _find_control(n, pred)
		if hit != null:
			return hit
	return null


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
