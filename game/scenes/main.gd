extends Node2D
## The cockpit. A fixed 1440x900 composition in the window; over the desktop
## it grows to cover the screen, always on top, and hands every click that
## is not on the hull straight through to whatever window is under it.
##
## Keys: B toggles desktop mode, Z toggles zen (the macOS Dock and menu
## bar, or on Linux the Plasma panels, auto-hide, so the cockpit has the
## whole screen; they come back when the mouse touches their edge), W
## toggles a fake wallpaper behind the void (windowed only, for judging
## the overlay look without leaving the app), S saves a screenshot
## beside the project, Q or Escape quits.
## H stows the HUD (the hull, its instruments, NERViewer with them) while
## the void flies on; T stows the tree. Both persist.
## The number keys are the drive's gears: 1 to 5 states (idle, cruise,
## ether, nebula, ring), 6 to 0 sequences (gate, warp, debris, squall,
## arrival; 0 is gear 10), then minus for departure (11, from a berth
## only) and equals for the great ship (12). Backtick toggles Voyage,
## the autopilot (scenes/void/voyage.gd); tilde skips to its next
## movement; a gear key takes the helm back. See
## scenes/void/drive.gd. Mode, zen, wallpaper, HUD and tree persist, the
## gear does not; zen restores the system's own settings when it ends or the
## cockpit quits. What zen does to the desktop, on either system, is
## scripts/desk.gd's business; this file only says when.

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
const Desk := preload("res://scripts/desk.gd")

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
## The desktop's chrome as it was before zen (the Dock and menu-bar
## auto-hide on macOS, each Plasma panel's hiding mode on Linux; see
## Desk.zen_read), so zen can hand it back exactly.
var _zen_prev := {}
## Konsole windows seen while in zen: a new one is switched to the zen
## profile too (Linux; Terminal takes the startup profile on its own).
var _zen_konsoles := 0
var _screen_timer := 0.0
## Quick rechecks still owed after a zen swap: the panels (or the Dock and
## menu bar) move a beat after we ask, and the window manager shoves an
## always-on-top window around while the struts change, so the first
## recheck can land before it settles.
var _screen_burst := 0
const SCREEN_BURST := 4
const SCREEN_BURST_GAP := 0.15
## The shots tool flips modes for the camera; those must not become prefs.
var persist := true
## One cockpit flies the desk. A second one (editor Play beside the
## running app, a headless check) would take over zen, the borders and
## Konsole, and on quit hand them all back and undock NERViewer from under
## the live one. It runs with persist off instead: it only watches.
const LOCK := "user://cockpit.pid"
var _lock_held := false


func _ready() -> void:
	if persist and not _take_lock():
		persist = false
	get_window().size_changed.connect(_update_passthrough)
	Workspace.windows_moved.connect(_on_windows_moved)
	hull.laid_out.connect(_update_passthrough)
	_load_prefs()
	if persist:
		Desk.terminal_prepare()
		Workspace.changed.connect(_on_workspace_changed)
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


## Desktop mode: borderless, transparent, on top, covering the usable
## screen, the one the window is on (on Linux, whichever monitor it was
## on; Desk.usable_rect explains why Godot's own answer is not used).
func set_desktop(on: bool) -> void:
	desktop = on
	var win := get_window()
	win.transparent = on
	win.borderless = on
	win.always_on_top = on
	if on:
		var usable := Desk.usable_rect(win.current_screen)
		win.position = usable.position
		win.size = usable.size
	else:
		win.size = DESIGN
		var screen := Desk.usable_rect(win.current_screen)
		win.position = screen.position + (screen.size - DESIGN) / 2
	void_layer.set_ground_alpha(0.0 if on else 1.0)
	_apply_wallpaper()
	_update_passthrough()
	_zen_paint()
	_save_prefs()


## The zen paint that only makes sense over the desktop: the frames, the
## title-bar cover (macOS), Konsole's frames taken off (Linux).
func _zen_paint() -> void:
	frames.set_shown(zen and desktop)
	cover.set_shown(zen and desktop)
	if persist:  # a bystander or a tool leaves the live cockpit's borders be
		Desk.borders(zen and desktop)


## Zen: the Dock and the menu bar (macOS) or the Plasma panels (Linux)
## auto-hide, and the terminal dissolves into the void. Over the desktop,
## zen also frames every open window in hairlines.
## The terminal's zen profile is Desk.TERM_PROFILE; the one to go back to
## is remembered here and in prefs.
var _term_prev := ""
## Linux: konsolerc's DefaultProfile entry from before zen (a file name,
## "" for the built-in profile), so zen's profile never outlives zen
## there (see Desk.terminal_default_file). Unknown until read at zen-on
## or loaded from prefs.
var _term_prev_file := ""
var _term_file_known := false


func set_zen(on: bool) -> void:
	if not persist:
		# Zen is the desk's (panels, Konsole, konsolerc), and the desk
		# belongs to the cockpit holding the lock.
		print("cockpit: another cockpit has the helm; zen is its to change")
		return
	if on and not zen:
		_zen_prev = Desk.zen_read()
		_remember_terminal(Desk.terminal_current())
		_remember_terminal_file()
	zen = on
	_zen_paint()
	Desk.zen_apply(on, _zen_prev)
	_refit_soon()
	_apply_terminal(on)
	_save_prefs()


## The profile to hand the terminal back. Never the zen profile itself: if
## zen was already in force when it was read (a restart with zen on, a
## crash), the earlier answer stands; failing that, the profile the zen
## profile was built from (the tools/*_zen_profile.sh scripts record it in
## terminal/.source); failing that, Terminal's own "Basic" (Konsole's
## configured default on Linux). Josh's default was Homebrew, and a guess
## of "Basic" lost it once (2026-09-10).
func _remember_terminal(name: String) -> void:
	if not name.is_empty() and name != Desk.TERM_PROFILE:
		_term_prev = name
		return
	if not _term_prev.is_empty() and _term_prev != Desk.TERM_PROFILE:
		return
	var source := Paths.find_up("terminal/.source")
	var from := FileAccess.get_file_as_string(source).strip_edges() if not source.is_empty() else ""
	_term_prev = from if not from.is_empty() and from != Desk.TERM_PROFILE else Desk.terminal_fallback()


func _apply_terminal(on: bool) -> void:
	var profile := Desk.TERM_PROFILE if on else _term_prev
	if not profile.is_empty() and (not on or Desk.terminal_ready()):
		Desk.terminal_set(profile)
	if not on:
		Desk.terminal_unstick(_terminal_file())


## Linux: read konsolerc's default at zen-on. Already the zen profile (a
## restart with zen on, a crash) means the earlier answer stands.
func _remember_terminal_file() -> void:
	if not Desk.LINUX:
		return
	var file := Desk.terminal_default_file()
	if file != Desk.TERM_PROFILE + ".profile":
		_term_prev_file = file
		_term_file_known = true


## The konsolerc entry to hand back: as read, else found from the
## profile's name (prefs from before it was read).
func _terminal_file() -> String:
	return _term_prev_file if _term_file_known else Desk.terminal_profile_file(_term_prev)


## A Konsole window opened in zen starts in the default profile (a new
## tab in an existing window already takes the zen one): sweep again
## whenever there are more Konsole windows than last time.
func _on_workspace_changed() -> void:
	if not Desk.LINUX:
		return
	var app = Workspace.apps.get("org.kde.konsole")
	var n: int = app.windows if app != null and app.alive else 0
	if zen and n > _zen_konsoles:
		Desk.terminal_set(Desk.TERM_PROFILE)
	_zen_konsoles = n


## The lock is the pid of the cockpit holding it and its program (godot,
## or the exported binary). A pid that is gone (a crash, a kill) frees it;
## so does one reused by some other program.
func _take_lock() -> bool:
	if DisplayServer.get_name() == "headless":
		print("cockpit: headless; leaving the desk alone")
		return false
	var held := FileAccess.get_file_as_string(LOCK).split("\n") if FileAccess.file_exists(LOCK) else PackedStringArray()
	var other := int(held[0].strip_edges()) if held.size() > 0 else 0
	var program := held[1].strip_edges() if held.size() > 1 else ""
	if other > 0 and other != OS.get_process_id() and _cockpit_alive(other, program):
		print("cockpit: pid %d has the helm; this one only watches" % other)
		return false
	var f := FileAccess.open(LOCK, FileAccess.WRITE)
	if f == null:
		return true  # no lock to be had; fly anyway, as before there was one
	f.store_string("%d\n%s\n" % [OS.get_process_id(), OS.get_executable_path().get_file()])
	f.close()
	_lock_held = true
	return true


func _drop_lock() -> void:
	if not _lock_held:
		return
	_lock_held = false
	if int(FileAccess.get_file_as_string(LOCK).split("\n")[0].strip_edges()) == OS.get_process_id():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOCK))


## Alive, and still the program that took the lock, so a recycled pid
## (after a crash, a reboot) does not hold the helm forever.
static func _cockpit_alive(pid: int, program: String) -> bool:
	var cmd := _command_line(pid)
	return not cmd.is_empty() and (program.is_empty() or program in cmd)


## A process's whole command line, "" if there is no such process.
## Linux: /proc through a handle (proc files report a length of 0, so
## get_file_as_string reads nothing). macOS: ps, which answers for any
## process (OS.is_process_running only knows our own children).
static func _command_line(pid: int) -> String:
	if Desk.LINUX:
		var f := FileAccess.open("/proc/%d/cmdline" % pid, FileAccess.READ)
		if f == null:
			return ""
		var raw := f.get_buffer(4096)
		for i in raw.size():
			if raw[i] == 0:
				raw[i] = 32  # argv is NUL-separated
		return raw.get_string_from_utf8().strip_edges()
	var out := []
	if OS.execute("/bin/ps", ["-p", str(pid), "-o", "command="], out) != 0 or out.is_empty():
		return ""
	return str(out[0]).strip_edges()


func _exit_tree() -> void:
	_drop_lock()


## Refit now rather than on the next one-second check, then a few more
## times while the desktop settles.
func _refit_soon() -> void:
	_screen_timer = 0.0
	_screen_burst = SCREEN_BURST


## Leaving zen without touching the prefs: the quit path.
func _release_zen() -> void:
	if not persist:
		return  # never took the desk, so has nothing to hand back
	if zen:
		Desk.zen_apply(false, _zen_prev)
		if not _term_prev.is_empty():
			Desk.terminal_set(_term_prev)
		Desk.terminal_unstick(_terminal_file())
	Desk.borders(false)


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
	_zen_prev = Desk.zen_load(cfg)
	_remember_terminal(str(cfg.get_value("zen", "prev_terminal", "")))
	if cfg.has_section_key("zen", "prev_terminal_file"):
		_term_prev_file = str(cfg.get_value("zen", "prev_terminal_file"))
		_term_file_known = true
	zen = bool(cfg.get_value("zen", "on", false))
	if want_desktop:
		set_desktop(true)
	# Always, zen or not: a cockpit that crashed in zen may have left
	# Konsole's frames off (Linux); this puts them back.
	_zen_paint()
	if zen:
		Desk.zen_apply(true, _zen_prev)
		_refit_soon()
		_apply_terminal(true)
		_save_prefs()
	else:
		# A cockpit that died in zen may have left Konsole's default on the
		# zen profile.
		Desk.terminal_unstick(_terminal_file())


func _save_prefs() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("look", "desktop", desktop)
	cfg.set_value("look", "wallpaper", fake_wallpaper)
	cfg.set_value("look", "hud", hud)
	cfg.set_value("look", "tree", tree_shown)
	cfg.set_value("zen", "on", zen)
	Desk.zen_save(cfg, _zen_prev)
	cfg.set_value("zen", "prev_terminal", _term_prev)
	if _term_file_known:
		cfg.set_value("zen", "prev_terminal_file", _term_prev_file)
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
		_screen_timer = SCREEN_BURST_GAP if _screen_burst > 0 else 1.0
		_screen_burst = maxi(_screen_burst - 1, 0)
		var win := get_window()
		var usable := Desk.usable_rect(win.current_screen)
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
		KEY_S:
			# Note: over the desktop this captures only what the app draws,
			# on transparent; the desktop behind it is not in the frame.
			# For the real look, use the system screenshot (Cmd-Shift-3,
			# or Spectacle on Plasma).
			var stamp := Time.get_datetime_string_from_system().replace(":", "-")
			var path := ProjectSettings.globalize_path("res://../screenshots/manual_%s.png" % stamp)
			get_viewport().get_texture().get_image().save_png(path)
			print("saved ", path)
