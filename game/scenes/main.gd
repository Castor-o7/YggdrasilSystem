extends Node2D
## The cockpit. A fixed 1440x900 composition in the window; over the desktop
## it grows to cover the screen, always on top, and hands every click that
## is not on the hull straight through to whatever window is under it.
##
## Keys: B toggles desktop mode, Z toggles zen (the macOS Dock and menu
## bar auto-hide, so the cockpit has the whole screen; both come back
## when the mouse touches their edge), W toggles a fake wallpaper behind
## the void (windowed only, for judging the overlay look without leaving
## the app), S saves a screenshot to ~/Pictures, Q or Escape quits.
## H stows the HUD (the hull, its instruments, NERViewer with them) while
## the void flies on; T stows the tree. Both persist.
## The number keys are the drive's gears: 1 to 5 states (idle, cruise,
## ether, nebula, ring), 6 to 0 sequences (gate, warp, debris, squall,
## arrival; 0 is gear 10), then minus for departure (11, from a berth
## only) and equals for the great ship (12). Backtick toggles Voyage,
## the autopilot (scenes/void/voyage.gd); tilde skips to its next
## movement; a gear key takes the helm back. See
## scenes/void/drive.gd. ? shows the keys on a card (scenes/hull/
## help_card.gd), as does Help > Yggdrasil Keys in the menu bar; a new key
## belongs on that card too. Mode, zen, wallpaper, HUD and tree persist, the
## gear does not; zen restores the system's own settings when it ends or the
## cockpit quits.

const PREFS := "user://prefs.cfg"
const DESIGN := Vector2i(1440, 900)

@onready var wallpaper: TextureRect = $Wallpaper
@onready var void_layer: ColorRect = $Void
@onready var hull: Control = $Hull
@onready var frames: Node2D = $Frames
@onready var cover: Node2D = $Cover
@onready var tree: Node2D = $Void/Tree

const BLOCK := preload("res://scenes/hull/sigil_block.tscn")
const CLOCK := preload("res://scenes/blocks/clock.tscn")
const NERVIEWER_DOCK := preload("res://scenes/hull/nerviewer_dock.gd")
const Paths := preload("res://scripts/paths.gd")

var _nerviewer_dock: Node

var desktop := false
var fake_wallpaper := false
var zen := false
## The HUD (the hull and its instruments, NERViewer among them) and the
## tree can be stowed while the void flies on (Josh, 2026-09-11: still
## floating through the void while reading email, the cockpit put away
## until it is wanted).
var hud := true
var garage := false
var tree_shown := true
const STOW := 0.8               # seconds to fade either away or back
var _hud_alpha := 1.0
var _tree_alpha := 1.0
## The Dock and menu-bar auto-hide settings as they were before zen, so
## zen can hand them back exactly.
var _zen_prev := [false, false]
var _screen_timer := 0.0
## The shots tool flips modes for the camera; those must not become prefs.
var persist := true
var _help: HelpCard


func _ready() -> void:
	get_window().size_changed.connect(_update_passthrough)
	Workspace.windows_moved.connect(_on_windows_moved)
	hull.laid_out.connect(_update_passthrough)
	_help = HelpCard.new()
	add_child(_help)
	if NativeMenu.has_feature(NativeMenu.FEATURE_GLOBAL_MENU):
		NativeMenu.add_item(NativeMenu.get_system_menu(NativeMenu.HELP_MENU_ID), "Yggdrasil Keys", func(_tag: Variant) -> void: _help.toggle())
	_load_prefs()
	_apply_wallpaper()
	_dock_blocks()
	_update_passthrough()


## The instruments. For now: the clock, top of the left column.
func _dock_blocks() -> void:
	var clock: SigilBlock = BLOCK.instantiate()
	clock.title = "chrono"
	clock.seed = 3
	clock.size = Vector2(200, 200)
	clock.get_node("Content").add_child(CLOCK.instantiate())
	hull.dock(clock, "left", 0)
	_place_from_prefs(clock, "left", 0)
	# NERViewer: a sigil with nothing inside; NERViewer's own window fills it.
	var nerv: SigilBlock = BLOCK.instantiate()
	nerv.title = "nerviewer"
	nerv.seed = 7
	nerv.size = Vector2(256, 256)
	var waiting := Label.new()
	waiting.text = "AWAITING\nNERVIEWER"
	waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	waiting.add_theme_font_size_override("font_size", 9)
	waiting.add_theme_color_override("font_color", Palette.dim(Palette.color("light"), 0.35))
	nerv.get_node("Content").add_child(waiting)
	hull.dock(nerv, "right", 0)
	_place_from_prefs(nerv, "right", 0)
	hull.arranged.connect(_save_prefs)
	if not persist:
		return  # the shots tool must not launch or dock the real NERViewer
	_nerviewer_dock = NERVIEWER_DOCK.new()
	_nerviewer_dock.block = nerv
	_nerviewer_dock.set_hidden(not hud)
	add_child(_nerviewer_dock)
	Workspace.changed.connect(func() -> void: waiting.visible = not _nerviewer_dock.running())


## A window moved under the zen paint: draw fast until it settles, so the
## cover and the frames stay locked to it.
func _on_windows_moved() -> void:
	if zen and desktop:
		Pace.stir(0.75)


## Desktop mode: borderless, transparent, on top, covering the usable screen.
func set_desktop(on: bool) -> void:
	desktop = on
	var win := get_window()
	win.transparent = on
	win.borderless = on
	win.always_on_top = on
	if on:
		var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
		win.position = usable.position
		win.size = usable.size
	else:
		win.size = DESIGN
		var screen := DisplayServer.screen_get_usable_rect(win.current_screen)
		win.position = screen.position + (screen.size - DESIGN) / 2
	void_layer.set_ground_alpha(0.0 if on else 1.0)
	_apply_wallpaper()
	_update_passthrough()
	frames.set_shown(zen and on)
	cover.set_shown(zen and on)
	_save_prefs()


## Zen: ask System Events to auto-hide the Dock and the menu bar. This is
## the setting the user could flip in System Settings, changed live; the
## first use asks the user to allow the app to control System Events.
## Over the desktop, zen also frames every open window in hairlines.
const ZEN_GET := 'tell application "System Events" to tell dock preferences to get {autohide, autohide menu bar}'
const ZEN_SET := 'tell application "System Events" to tell dock preferences to set {autohide, autohide menu bar} to {%s, %s}'

## Terminal dissolves in zen: its windows switch to the "Yggdrasil"
## profile, the default profile with a transparent background, so the
## text sits on the void. The bundled zenprof (helper/zenprof.swift) writes
## the profile and Terminal imports it by opening it; the cockpit does
## this once if the profile is missing.
const TERM_PROFILE := "Yggdrasil"
const TERM_GET := 'tell application "Terminal" to if it is running then get name of default settings'
const TERM_HAS := 'tell application "Terminal" to exists settings set "%s"'
const TERM_SET := 'tell application "Terminal"
if it is running then
set default settings to settings set "%s"
set startup settings to settings set "%s"
set current settings of every tab of every window to settings set "%s"
end if
end tell'
## Importing opens a window in the new profile; it is closed again.
const TERM_CLOSE := 'tell application "Terminal"
repeat with w in windows
if name of current settings of selected tab of w is "%s" then
close w saving no
exit repeat
end if
end repeat
exists settings set "%s"
end tell'
const TERM_FILE := "user://Yggdrasil.terminal"
var _term_prev := ""
var _term_source := ""


func set_zen(on: bool) -> void:
	if on and not zen:
		_zen_prev = _read_zen()
		_remember_terminal(Osa.run(TERM_GET))
	zen = on
	frames.set_shown(on and desktop)
	cover.set_shown(on and desktop)
	var want := [true, true] if on else _zen_prev
	Osa.fire(ZEN_SET % [str(want[0]).to_lower(), str(want[1]).to_lower()])
	_apply_terminal(on)
	_save_prefs()


## The profile to hand Terminal back. Never the zen profile itself: if zen
## was already in force when it was read (a restart with zen on, a crash),
## the earlier answer stands; failing that, the profile the zen profile
## was built from (zenprof names it; kept in prefs); failing that,
## Terminal's own "Basic". Josh's default
## was Homebrew, and a guess of "Basic" lost it once (2026-09-10).
func _remember_terminal(name: String) -> void:
	if not name.is_empty() and name != TERM_PROFILE:
		_term_prev = name
		return
	if not _term_prev.is_empty() and _term_prev != TERM_PROFILE:
		return
	_term_prev = _term_source if not _term_source.is_empty() and _term_source != TERM_PROFILE else "Basic"


func _apply_terminal(on: bool) -> void:
	var profile := TERM_PROFILE if on else _term_prev
	if profile.is_empty():
		return
	if on and Osa.run(TERM_HAS % TERM_PROFILE) != "true" and not _make_terminal_profile():
		return
	Osa.fire(TERM_SET % [profile, profile, profile])


func _make_terminal_profile() -> bool:
	var out := []
	var file := ProjectSettings.globalize_path(TERM_FILE)
	if OS.execute(Paths.bundled("zenprof"), [file], out, true) != 0:
		print("zen: could not make Terminal profile %s: %s" % [TERM_PROFILE, "".join(out).strip_edges()])
		return false
	var from := "".join(out).strip_edges()
	if from != TERM_PROFILE:
		_term_source = from
	OS.execute("/usr/bin/open", [file])
	OS.delay_msec(1500)
	return Osa.run(TERM_CLOSE % [TERM_PROFILE, TERM_PROFILE]) == "true"


static func _read_zen() -> Array:
	var parts := Osa.run(ZEN_GET).split(",")
	if parts.size() != 2:
		return [false, false]
	return [parts[0].strip_edges() == "true", parts[1].strip_edges() == "true"]


## Leaving zen without touching the prefs: the quit path.
func _release_zen() -> void:
	if zen:
		Osa.fire(ZEN_SET % [str(_zen_prev[0]).to_lower(), str(_zen_prev[1]).to_lower()])
		if not _term_prev.is_empty():
			Osa.fire(TERM_SET % [_term_prev, _term_prev, _term_prev])


func set_hud(on: bool) -> void:
	hud = on
	if _nerviewer_dock:
		_nerviewer_dock.set_hidden(not on)
	_update_passthrough()
	_save_prefs()


func set_tree(on: bool) -> void:
	tree_shown = on
	_save_prefs()


func set_fake_wallpaper(on: bool) -> void:
	fake_wallpaper = on
	_apply_wallpaper()
	_save_prefs()


func _apply_wallpaper() -> void:
	wallpaper.visible = fake_wallpaper and not desktop
	if wallpaper.visible:
		void_layer.set_ground_alpha(0.0)
	elif not desktop:
		void_layer.set_ground_alpha(1.0)


## Where clicks land: each instrument's disc and a thin strip under the
## rail's hairline (somewhere to click so the keys reach the cockpit).
## Everything else passes through to the desktop. Until 2026-09-11 the
## shape was the whole rail band and each column down to its instruments:
## the top-left column sat over the traffic lights of most windows and
## the band over their bottom edges (Josh: could not minimize them). With
## the HUD stowed only the strip remains. Godot treats an empty polygon
## as "capture everything", which is what windowed mode wants. Window
## pixels throughout.
const RAIL_STRIP := 16.0        # design px under the hairline
const DISC_SIDES := 24


func _update_passthrough() -> void:
	var win := get_window()
	if not desktop:
		win.mouse_passthrough_polygon = PackedVector2Array()
		return
	var s := Vector2(win.size)
	var k: float = get_viewport().get_final_transform().get_scale().y
	var rail_top: float = s.y * (1.0 - hull.RAIL)
	var rail_low: float = rail_top + k * RAIL_STRIP
	var loops: Array = [[Vector2(0, rail_top), Vector2(s.x, rail_top), Vector2(s.x, rail_low), Vector2(0, rail_low)]]
	if hud and garage:
		var col_w: float = s.x * hull.SIDE
		loops.append([Vector2(0, 0), Vector2(col_w, 0), Vector2(col_w, rail_top), Vector2(0, rail_top)])
		loops.append([Vector2(s.x - col_w, 0), Vector2(s.x, 0), Vector2(s.x, rail_top), Vector2(s.x - col_w, rail_top)])
	elif hud:
		for disc in hull.discs():
			var c: Vector2 = disc[0] * k
			var r: float = disc[1] * k
			var loop := []
			for i in DISC_SIDES:
				loop.append(c + Vector2.from_angle(TAU * i / DISC_SIDES) * r)
			loops.append(loop)
	win.mouse_passthrough_polygon = _one_polygon(loops)


## One polygon from several closed loops: each loop is reached from the
## first loop's first point along a bridge and left the same way, so the
## bridges have no area and the even-odd ray test macOS is given
## (Geometry2D.is_point_in_polygon) cancels them out.
static func _one_polygon(loops: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var home: Vector2 = loops[0][0]
	for loop in loops:
		pts.append(home)
		for p in loop:
			pts.append(p)
		pts.append(loop[0])
	return pts


## Where the block was left in garage mode, if anywhere.
func _place_from_prefs(block: Control, side: String, index: int) -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	if cfg.load(PREFS) != OK:
		return
	var at := str(cfg.get_value("hull", block.title, "%s:%d" % [side, index])).split(":")
	if at.size() == 2 and at[0] in ["left", "right"]:
		hull.place(block, at[0], int(at[1]))


func set_garage(on: bool) -> void:
	garage = on
	hull.garage = on
	_update_passthrough()


func _load_prefs() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	if cfg.load(PREFS) != OK:
		return
	# Read everything before applying anything: set_desktop() saves the
	# prefs, and it must not save zen back as off before zen is read.
	fake_wallpaper = bool(cfg.get_value("look", "wallpaper", false))
	hud = bool(cfg.get_value("look", "hud", true))
	tree_shown = bool(cfg.get_value("look", "tree", true))
	_hud_alpha = 1.0 if hud else 0.0
	_tree_alpha = 1.0 if tree_shown else 0.0
	var want_desktop := bool(cfg.get_value("look", "desktop", false))
	_zen_prev = [bool(cfg.get_value("zen", "prev_dock", false)), bool(cfg.get_value("zen", "prev_menu", false))]
	_term_source = str(cfg.get_value("zen", "source_terminal", ""))
	_remember_terminal(str(cfg.get_value("zen", "prev_terminal", "")))
	zen = bool(cfg.get_value("zen", "on", false))
	if want_desktop:
		set_desktop(true)
	if zen:
		frames.set_shown(desktop)
		cover.set_shown(desktop)
		Osa.fire(ZEN_SET % ["true", "true"])
		_apply_terminal(true)
		_save_prefs()


func _save_prefs() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("look", "desktop", desktop)
	cfg.set_value("look", "wallpaper", fake_wallpaper)
	cfg.set_value("look", "hud", hud)
	cfg.set_value("look", "tree", tree_shown)
	cfg.set_value("zen", "on", zen)
	cfg.set_value("zen", "prev_dock", _zen_prev[0])
	cfg.set_value("zen", "prev_menu", _zen_prev[1])
	cfg.set_value("zen", "prev_terminal", _term_prev)
	cfg.set_value("zen", "source_terminal", _term_source)
	var at: Dictionary = hull.arrangement()
	for title in at:
		cfg.set_value("hull", title, at[title])
	cfg.save(PREFS)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_prefs()
		_release_zen()
		if _nerviewer_dock:
			_nerviewer_dock.release()


func _process(dt: float) -> void:
	_hud_alpha = move_toward(_hud_alpha, 1.0 if hud else 0.0, dt / STOW)
	_warp(dt)
	hull.modulate.a = _hud_alpha
	hull.visible = _hud_alpha > 0.0
	_tree_alpha = move_toward(_tree_alpha, 1.0 if tree_shown else 0.0, dt / STOW)
	tree.modulate.a = _tree_alpha
	tree.visible = _tree_alpha > 0.0
	# The usable screen changes when the menu bar hides or the display
	# changes; over the desktop, keep covering all of it.
	_screen_timer -= dt
	if desktop and _screen_timer <= 0.0:
		_screen_timer = 1.0
		var win := get_window()
		var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
		if win.position != usable.position or win.size != usable.size:
			win.position = usable.position
			win.size = usable.size


## The warp transition: the hull answers the jump. Over the charge the
## rings spin up and the inscription warms; at the jump a surge of light
## runs root to bud through every branch; over the arrival the rings
## wind down. `_warp_k` rises with the charge, holds through the sweep
## and falls over the arrive.
var _warp_k := 0.0
func _warp(dt: float) -> void:
	var d = void_layer.drive
	var want := 0.0
	var surge := -1.0
	if d.gear == d.WARP:
		match d.phase:
			"charge": want = smoothstep(0.0, 1.0, d.phase_t / d.WARP_CHARGE)
			"sweep":
				want = 1.0
				surge = clampf(d.phase_t / 0.9, 0.0, 1.2)
			"arrive": want = 1.0 - smoothstep(0.0, 1.0, d.phase_t / d.WARP_ARRIVE)
	_warp_k = move_toward(_warp_k, want, dt / 0.5) if want < _warp_k else want
	hull.set_warp(_warp_k)
	tree.set_surge(surge)


## A gear key: the pilot has the helm, so Voyage ends and the gear runs.
func _helm(gear: int) -> void:
	void_layer.voyage.stop()
	void_layer.drive.shift(gear)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	match event.keycode:
		KEY_B:
			set_desktop(not desktop)
		KEY_W:
			set_fake_wallpaper(not fake_wallpaper)
		KEY_Z:
			set_zen(not zen)
		KEY_H:
			set_hud(not hud)
		KEY_G:
			set_garage(not garage)
		KEY_T:
			set_tree(not tree_shown)
		KEY_Q, KEY_ESCAPE:
			_save_prefs()
			_release_zen()
			if _nerviewer_dock:
				_nerviewer_dock.release()
			get_tree().quit()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			_helm(event.keycode - KEY_0)
		KEY_0:
			_helm(10)
		KEY_MINUS:
			_helm(11)
		KEY_EQUAL:
			_helm(12)
		KEY_QUOTELEFT, KEY_ASCIITILDE:
			if event.shift_pressed or event.keycode == KEY_ASCIITILDE:
				void_layer.voyage.skip()
			else:
				void_layer.voyage.toggle()
		KEY_SLASH, KEY_QUESTION:
			_help.toggle()
		KEY_S:
			# Note: over the desktop this captures only what the app draws,
			# on transparent; the desktop behind it is not in the frame.
			# For the real look, use the system screenshot (Cmd-Shift-3).
			var stamp := Time.get_datetime_string_from_system().replace(":", "-")
			var path := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES).path_join("Yggdrasil %s.png" % stamp)
			get_viewport().get_texture().get_image().save_png(path)
			print("saved ", path)
