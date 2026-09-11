extends Node2D
## The cockpit. A fixed 1440x900 composition in the window; over the desktop
## it grows to cover the screen, always on top, and hands every click that
## is not on the hull straight through to whatever window is under it.
##
## Keys: B toggles desktop mode, Z toggles zen (the macOS Dock and menu
## bar auto-hide, so the cockpit has the whole screen; both come back
## when the mouse touches their edge), W toggles a fake wallpaper behind
## the void (windowed only, for judging the overlay look without leaving
## the app), S saves a screenshot beside the project, Q or Escape quits.
## The number keys are the drive's gears: 1 to 5 states (idle, cruise,
## ether, nebula, ring), 6 to 0 sequences (gate, warp, debris, squall,
## arrival; 0 is gear 10), then minus for departure (11, from a berth
## only) and equals for the great ship (12). Backtick toggles Voyage,
## the autopilot (scenes/void/voyage.gd); tilde skips to its next
## movement; a gear key takes the helm back. See
## scenes/void/drive.gd. Mode, zen and wallpaper persist, the gear does
## not; zen restores the system's own settings when it ends or the
## cockpit quits.

const PREFS := "user://prefs.cfg"
const DESIGN := Vector2i(1440, 900)

@onready var wallpaper: TextureRect = $Wallpaper
@onready var void_layer: ColorRect = $Void
@onready var hull: Control = $Hull
@onready var frames: Node2D = $Frames
@onready var cover: Node2D = $Cover

const BLOCK := preload("res://scenes/hull/sigil_block.tscn")
const CLOCK := preload("res://scenes/blocks/clock.tscn")
const NERVIEWER_DOCK := preload("res://scenes/hull/nerviewer_dock.gd")
const Paths := preload("res://scripts/paths.gd")

var _nerviewer_dock: Node

var desktop := false
var fake_wallpaper := false
var zen := false
## The Dock and menu-bar auto-hide settings as they were before zen, so
## zen can hand them back exactly.
var _zen_prev := [false, false]
var _screen_timer := 0.0
## The shots tool flips modes for the camera; those must not become prefs.
var persist := true


func _ready() -> void:
	get_window().size_changed.connect(_update_passthrough)
	Workspace.windows_moved.connect(_on_windows_moved)
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
	if not persist:
		return  # the shots tool must not launch or dock the real NERViewer
	_nerviewer_dock = NERVIEWER_DOCK.new()
	_nerviewer_dock.block = nerv
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
## text sits on the void. tools/terminal_zen_profile.sh makes the profile;
## the cockpit runs it once if the profile is missing.
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
var _term_prev := ""


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
## was built from (tools/terminal_zen_profile.sh records it in
## terminal/.source); failing that, Terminal's own "Basic". Josh's default
## was Homebrew, and a guess of "Basic" lost it once (2026-09-10).
func _remember_terminal(name: String) -> void:
	if not name.is_empty() and name != TERM_PROFILE:
		_term_prev = name
		return
	if not _term_prev.is_empty() and _term_prev != TERM_PROFILE:
		return
	var source := Paths.find_up("terminal/.source")
	var from := FileAccess.get_file_as_string(source).strip_edges() if not source.is_empty() else ""
	_term_prev = from if not from.is_empty() and from != TERM_PROFILE else "Basic"


func _apply_terminal(on: bool) -> void:
	var profile := TERM_PROFILE if on else _term_prev
	if profile.is_empty():
		return
	if on and Osa.run(TERM_HAS % TERM_PROFILE) != "true":
		var script := Paths.find_up("tools/terminal_zen_profile.sh")
		if not script.is_empty():
			OS.execute("/bin/sh", [script])
		else:
			print("zen: Terminal profile %s missing and no script to make it" % TERM_PROFILE)
			return
	Osa.fire(TERM_SET % [profile, profile, profile])


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


## Where clicks land: the rail, and each side column only as far down as
## its instruments reach, joined into one shape by a one-pixel strip along
## the screen edge. Everything else passes through to the desktop, so a
## window under the empty part of a column is still the desktop's. Godot
## treats an empty polygon as "capture everything", which is what windowed
## mode wants. Window pixels throughout.
func _update_passthrough() -> void:
	var win := get_window()
	if not desktop:
		win.mouse_passthrough_polygon = PackedVector2Array()
		return
	var s := Vector2(win.size)
	var k: float = get_viewport().get_final_transform().get_scale().y
	var side: float = s.x * hull.SIDE
	var rail_top: float = s.y * (1.0 - hull.RAIL)
	var left := minf(k * hull.arm_bottom("left"), rail_top)
	var right := minf(k * hull.arm_bottom("right"), rail_top)
	var e := 1.0
	win.mouse_passthrough_polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(side, 0), Vector2(side, left), Vector2(e, left),
		Vector2(e, rail_top), Vector2(s.x - e, rail_top), Vector2(s.x - e, right),
		Vector2(s.x - side, right), Vector2(s.x - side, 0), Vector2(s.x, 0),
		Vector2(s.x, s.y), Vector2(0, s.y),
	])


func _load_prefs() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	if cfg.load(PREFS) != OK:
		return
	# Read everything before applying anything: set_desktop() saves the
	# prefs, and it must not save zen back as off before zen is read.
	fake_wallpaper = bool(cfg.get_value("look", "wallpaper", false))
	var want_desktop := bool(cfg.get_value("look", "desktop", false))
	_zen_prev = [bool(cfg.get_value("zen", "prev_dock", false)), bool(cfg.get_value("zen", "prev_menu", false))]
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
	cfg.set_value("zen", "on", zen)
	cfg.set_value("zen", "prev_dock", _zen_prev[0])
	cfg.set_value("zen", "prev_menu", _zen_prev[1])
	cfg.set_value("zen", "prev_terminal", _term_prev)
	cfg.save(PREFS)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_prefs()
		_release_zen()
		if _nerviewer_dock:
			_nerviewer_dock.release()


func _process(dt: float) -> void:
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
		KEY_S:
			# Note: over the desktop this captures only what the app draws,
			# on transparent; the desktop behind it is not in the frame.
			# For the real look, use the system screenshot (Cmd-Shift-3).
			var stamp := Time.get_datetime_string_from_system().replace(":", "-")
			var path := ProjectSettings.globalize_path("res://../screenshots/manual_%s.png" % stamp)
			get_viewport().get_texture().get_image().save_png(path)
			print("saved ", path)
