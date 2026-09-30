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
## the void flies on; T stows the tree; C stows the chrono alone, keeping
## its slot, whatever H says. All three persist. ? or F1 shows the key
## card (scenes/hull/key_card.gd), the list of all of this; any key or a
## click on it puts it away.
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
## Linux: Godot dies on SIGTERM, SIGHUP and SIGINT without a word, so a
## cockpit killed in zen never hands it back itself. The helper's watchdog
## runs this program again, headless, with `--unzen <pid>` (see _unzen).

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
const KEY_CARD := preload("res://scenes/hull/key_card.gd")
const Paths := preload("res://scripts/paths.gd")
const Desk := preload("res://scripts/desk.gd")
const Zen := preload("res://scripts/zen.gd")
const DeskHand := preload("res://scripts/desk_hand.gd")
## Every Desk call that can wait on a peer goes to the desk hand, one job
## at a time in the order asked, so no frame waits on one (a Z press held
## the void still 0.2 s, seconds with a slow Konsole). The quit and the
## guard's release still wait: they hand zen back before the process ends.
var _hand := DeskHand.new()
## The panels are being asked for (see _ask_panels).
var _panels_asked := false

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
var chrono_shown := true
const STOW := 0.8               # seconds to fade either away or back
var _hud_alpha := 1.0
var _tree_alpha := 1.0
var _chrono_alpha := 1.0
var _chrono: SigilBlock
var _key_card: Node2D
## Zen's record (scripts/zen.gd): what the desk had before zen, so zen
## can hand it back exactly, and whether the desk has zen now. The desk
## hand's while it runs; this file reads only _seen, the copy the last
## finished job gave back, which is what the prefs hold. `zen` is what
## the keys asked for, and may be a job or two ahead of the desk.
var _rec := Zen.record()
var _seen := Zen.record()
## The instruments' slots from prefs (title -> "side:index"), kept for
## the blocks docked after the prefs are read.
var _hull_prefs := {}
## Konsole windows seen while in zen: a new one is switched to the zen
## profile too (Linux; Terminal takes the startup profile on its own).
var _zen_konsoles := 0
## Sweeps still owed to a Konsole a zen sweep could not reach (no answer,
## a window not on the bus yet), one each RESWEEP_SECS: past WEDGE_SECS,
## so a peer that timed out is really asked again, and only a few, so one
## that stays wedged does not cost a timeout every ten seconds all zen.
const RESWEEP_SECS := Desk.WEDGE_SECS + 1.0
const RESWEEPS := 3
var _resweeps := 0
var _resweep_timer := 0.0
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
## What the guard's release did, one line per run (see _unzen).
const GUARD_LOG := "user://zen_guard.log"
var _quitting := false
## The start's settle is not done yet. Unlike a key's intent, a quit that
## drops it still owes its unstick.
var _settle_owed := false


func _ready() -> void:
	if Desk.LINUX and "--unzen" in OS.get_cmdline_user_args():
		# The guard's release: before the lock, which it never takes, so a
		# cockpit started meanwhile keeps the helm.
		set_process(false)
		_unzen()
		get_tree().quit()
		return
	if persist and not _take_lock():
		persist = false
	get_window().size_changed.connect(_update_passthrough)
	Workspace.windows_moved.connect(_on_windows_moved)
	hull.laid_out.connect(_update_passthrough)
	_load_prefs()
	if persist:
		_hand.post(Desk.terminal_prepare)
		Workspace.changed.connect(_on_workspace_changed)
	if not desktop and DisplayServer.get_name() != "headless":
		_ask_panels()  # so the first B has them to fit to
	_apply_wallpaper()
	_dock_blocks()
	_key_card = KEY_CARD.new()
	add_child(_key_card)
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
	_chrono = clock
	clock.modulate.a = _chrono_alpha
	clock.visible = _chrono_alpha > 0.0
	if not chrono_shown:
		hull.stowed.append(clock)
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
	_ask_panels()
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
## title-bar cover (macOS), Konsole's frames taken off (Linux), the last
## on the desk hand, as `zen and desktop` says now. `borders` false: a zen
## job sets them itself.
func _zen_paint(borders := true) -> void:
	frames.set_shown(zen and desktop)
	cover.set_shown(zen and desktop)
	if persist and borders:  # a bystander or a tool leaves the live cockpit's borders be
		_hand.post(Desk.borders.bind(zen and desktop))


## Zen: the Dock and the menu bar (macOS) or the Plasma panels (Linux)
## auto-hide, and the terminal dissolves into the void. Over the desktop,
## zen also frames every open window in hairlines.
## The terminal's zen profile is Desk.TERM_PROFILE; the one to go back to
## is remembered in the record (Zen.remember_terminal) and in prefs.
func set_zen(on: bool) -> void:
	if not persist:
		# Zen is the desk's (panels, Konsole, konsolerc), and the desk
		# belongs to the cockpit holding the lock.
		print("cockpit: another cockpit has the helm; zen is its to change")
		return
	zen = on
	_resweeps = 0
	# The desk's part goes to the hand, Konsole's frames with it in its
	# order; the job takes the record as the jobs before it left it, so an
	# off hands back exactly what its on read, however fast the keys.
	if on:
		_hand.post(Zen.on.bind(_rec, on and desktop, _hand, _on_zen_told), _on_zen_done)
	else:
		_hand.post(Zen.off.bind(_rec, on and desktop), _on_zen_done)
	_zen_paint(false)


## Zen's record, read and not yet acted on: into prefs before the chrome
## is hidden, so a kill mid-job leaves the guard something to hand back.
## Not once quitting: the quit saves what the desk was left with.
func _on_zen_told(rec: Dictionary) -> void:
	if _quitting:
		return
	_seen = rec
	_save_prefs()


## A zen job done: the desk is as the record says.
func _on_zen_done(rec: Dictionary) -> void:
	_settle_owed = false  # before the guard: the quit's own join lands here
	if _quitting:
		return
	_seen = rec
	_owe_sweep(zen and rec["held"] and rec["owed"])
	_refit_soon()
	_save_prefs()


## A Konsole window opened in zen starts in the default profile (a new
## tab in an existing window already takes the zen one): sweep again
## whenever there are more Konsole windows than last time.
func _on_workspace_changed() -> void:
	if not Desk.LINUX:
		return
	var app = Workspace.apps.get("org.kde.konsole")
	var n: int = app.windows if app != null and app.alive else 0
	if zen and n > _zen_konsoles:
		_sweep(true)
	_zen_konsoles = n


## A sweep asked while one still waits is the same sweep; a new window's
## outranks a resweep's (see _on_swept).
func _sweep(fresh: bool) -> void:
	_hand.post(Zen.sweep.bind(_rec), _on_swept.bind(fresh), "sweep", fresh)


## A sweep done. `fresh`: a new window's, which owes the full count again
## if it missed one; a resweep's own miss only uses up its turn. A bar zen
## hid goes into prefs at once, so a release after a kill knows to show
## them again.
func _on_swept(rec: Dictionary, fresh: bool) -> void:
	if _quitting:
		return
	var hid: bool = rec["bars_hidden"] and not _seen["bars_hidden"]
	_seen = rec
	if not rec["held"] or not rec["owed"]:
		_resweeps = 0
	elif fresh:
		_owe_sweep(zen)
	if hid:
		_save_prefs()


func _owe_sweep(owed: bool) -> void:
	if owed:
		_resweeps = RESWEEPS
		_resweep_timer = RESWEEP_SECS


## A sweep owed (see RESWEEP_SECS) is paid on its own clock: the window
## count that prompted it may not change again.
func _resweep(dt: float) -> void:
	if _resweeps <= 0:
		return
	if not zen:
		_resweeps = 0
		return
	_resweep_timer -= dt
	if _resweep_timer > 0.0:
		return
	_resweeps -= 1
	_resweep_timer = RESWEEP_SECS
	_sweep(false)


## The lock is the pid of the cockpit holding it and its program (godot,
## or the exported binary). A pid that is gone (a crash, a kill) frees it;
## so does one reused by some other program.
func _take_lock() -> bool:
	if DisplayServer.get_name() == "headless":
		print("cockpit: headless; leaving the desk alone")
		return false
	var held := _lock_holder()
	var other: int = held[0]
	var program: String = held[1]
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


## [pid, program] from the lock, [0, ""] with none.
static func _lock_holder() -> Array:
	var held := FileAccess.get_file_as_string(LOCK).split("\n") if FileAccess.file_exists(LOCK) else PackedStringArray()
	return [int(held[0].strip_edges()) if held.size() > 0 else 0, held[1].strip_edges() if held.size() > 1 else ""]


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
	_hand.finish(0.0)  # a tool's quit: the job in hand ends, then the thread
	_drop_lock()


## Refit now rather than on the next one-second check, then a few more
## times while the desktop settles.
func _refit_soon() -> void:
	_screen_timer = 0.0
	_screen_burst = SCREEN_BURST


## Leaving zen without touching the prefs: the quit path, and the guard's
## release (_unzen), which is `careful` (each part undoes only what zen
## still holds) and stops when `ours` says a new cockpit has the desk.
## Konsole's bars are shown again only if zen hid some. Says what each
## part did, for the guard's log.
func _release_zen(ours := Callable(), careful := false) -> PackedStringArray:
	var did := PackedStringArray()
	if not persist:
		return did  # never took the desk, so has nothing to hand back
	assert(not _hand.busy(), "the release runs with the desk hand finished")
	Desk.ask_again()
	if _rec["held"]:  # what the desk has, whatever the keys last asked
		did.append("panels " + Zen.chrome(_rec, false, careful))
		if not _still_ours(ours, did):
			return did
		if not str(_rec["term"]).is_empty():
			Desk.terminal_set(_rec["term"], _rec["bars_hidden"])
			did.append("konsole " + ("live (%d)" % Desk.terminal_live if Desk.terminal_live > 0 else "none running"))
		if not _still_ours(ours, did):
			return did
		did.append("konsolerc " + ("handed back" if Desk.terminal_unstick(Zen.terminal_file(_rec)) else "left"))
		# konsole_layout_offline checks /proc itself for a live Konsole; the
		# bus listing may predate a wait for plasmashell.
		if careful and _rec["bars_hidden"]:
			if not _still_ours(ours, did):
				return did
			did.append("layout " + Desk.konsole_layout_offline(_rec["konsole"]))
	if not _still_ours(ours, did):
		return did
	did.append("frames " + ("live" if Desk.borders(false) else "skipped"))
	return did


func _still_ours(ours: Callable, did: PackedStringArray) -> bool:
	if not ours.is_valid() or ours.call():
		return true
	did.append("stopped (a new cockpit has the desk)")
	return false


## Q or Escape: prefs, zen, NERViewer, gone.
func _quit() -> void:
	if _quitting:
		return
	_hand_back()
	get_tree().quit()


## Both ways out (Q, Escape, the window's close), once, and done before it
## returns: the process ends straight after. The job the hand is making
## ends (every Desk call is bounded); the ones still waiting are dropped,
## being only what the keys asked for (the start's settle excepted: its
## unstick is made here), and the release undoes whatever the desk was
## left holding. The prefs say zen is on only if the desk had it
## and the keys still wanted it, so the next start re-zens as before.
func _hand_back() -> void:
	_quitting = true
	_hand.finish(0.0)
	if _settle_owed and not _rec["held"]:
		Desk.terminal_unstick(Zen.terminal_file(_rec))
	_seen = Zen.copy(_rec)
	_seen["held"] = zen and _rec["held"]
	_save_prefs()
	_release_zen()
	if _nerviewer_dock:
		_nerviewer_dock.release()


## `--unzen [pid]` (Linux, headless): hand zen back from prefs for a
## cockpit that died holding it. The helper's watchdog runs it with the
## dead cockpit's pid (yggapps.py zen_guard), which the lock must still
## name; tools/launch_agent.sh unzen runs it bare, and then no live
## cockpit may hold the lock. Never takes the lock and never saves the
## prefs, so the next start re-zens as before; drops the dead cockpit's
## lock after, so no later guard repeats it.
func _unzen() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--unzen")
	var dead := int(args[at + 1]) if at + 1 < args.size() and args[at + 1].is_valid_int() else 0
	var held := _lock_holder()
	var who := "pid %d" % dead if dead > 0 else "by hand"
	var ours: Callable
	if dead > 0:
		if held[0] != dead:
			return  # a clean quit after all, or a new cockpit has the helm
		ours = func() -> bool: return _lock_holder()[0] == dead
	else:
		if held[0] > 0 and _cockpit_alive(held[0], held[1]):
			print("unzen: pid %d is flying; Z or Q hands zen back" % held[0])
			return
		ours = func() -> bool:
			var now := _lock_holder()
			return now[0] == held[0] or not _cockpit_alive(now[0], now[1])
	var cfg := ConfigFile.new()
	if cfg.load(PREFS) != OK or not bool(cfg.get_value("zen", "on", false)):
		_guard_log(who, "zen was off; nothing to hand back")
		return
	# No desk hand here: the guard has no frames to keep, and the release
	# must be done before the quit.
	_rec = Zen.load_prefs(cfg)
	Zen.remember_terminal(_rec, _rec["term"])
	Desk.menubar_back = Zen.menubar_back(_rec)
	var did := _release_zen(ours, true)
	var now := _lock_holder()
	if now[0] > 0 and now[0] == held[0] and not _cockpit_alive(now[0], now[1]):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOCK))
	_guard_log(who, ", ".join(did))


func _guard_log(who: String, what: String) -> void:
	var line := "%s %s: %s" % [Time.get_datetime_string_from_system(), who, what]
	print("unzen: ", line)
	var f := FileAccess.open(GUARD_LOG, FileAccess.READ_WRITE if FileAccess.file_exists(GUARD_LOG) else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(line)


func set_hud(on: bool) -> void:
	hud = on
	if _nerviewer_dock:
		_nerviewer_dock.set_hidden(not on)
	_update_passthrough()
	_save_prefs()


func set_tree(on: bool) -> void:
	tree_shown = on
	_save_prefs()


## The chrono alone: it fades like the HUD, keeps its slot, and gives its
## disc back to the desktop while it is away.
func set_chrono(on: bool) -> void:
	chrono_shown = on
	if _chrono:
		hull.stowed.erase(_chrono)
		if not on:
			hull.stowed.append(_chrono)
	_update_passthrough()
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
	if _key_card and _key_card.shown:
		# The card takes clicks while it is up, so one on it puts it away.
		var card: Rect2 = _key_card.rect()
		loops.append([card.position * k, Vector2(card.end.x, card.position.y) * k, card.end * k, Vector2(card.position.x, card.end.y) * k])
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
	var at := str(_hull_prefs.get(block.title, "%s:%d" % [side, index])).split(":")
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
	chrono_shown = bool(cfg.get_value("look", "chrono", true))
	_chrono_alpha = 1.0 if chrono_shown else 0.0
	var want_desktop := bool(cfg.get_value("look", "desktop", false))
	_rec = Zen.load_prefs(cfg)
	# Here, not in the start's job: a quit can drop that job, and the
	# release still needs the menu bar's and the terminal's answers. The
	# hand has no thread yet, so the desk is still this thread's.
	Zen.remember_terminal(_rec, _rec["term"])
	Desk.menubar_back = Zen.menubar_back(_rec)
	_seen = Zen.copy(_rec)
	# Read now: the prefs are saved (set_desktop, zen) before the blocks
	# are docked, and a save then would have nothing to write for them.
	if cfg.has_section("hull"):
		for title in cfg.get_section_keys("hull"):
			_hull_prefs[title] = str(cfg.get_value("hull", title))
	zen = _rec["held"]
	if want_desktop:
		# Where the panels are, before the first frame and before the
		# hand has the desk: the window's first size is its right one.
		Desk.panels_refresh()
		set_desktop(true)
	# Always, zen or not: a cockpit that crashed in zen may have left
	# Konsole's frames off (Linux); this puts them back.
	_zen_paint()
	# Zen as saved, on the hand like a Z press: on, the record takes in any
	# panel added since and the chrome and Konsole go again; off, Konsole's
	# default is taken back from the zen profile if a crash left it there.
	_settle_owed = not zen
	_hand.post((Zen.resume if zen else Zen.settle).bind(_rec), _on_zen_done)


func _save_prefs() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("look", "desktop", desktop)
	cfg.set_value("look", "wallpaper", fake_wallpaper)
	cfg.set_value("look", "hud", hud)
	cfg.set_value("look", "tree", tree_shown)
	cfg.set_value("look", "chrono", chrono_shown)
	Zen.save_prefs(cfg, _seen)
	# The layout as loaded, under the layout as it stands: a save before
	# the blocks are docked keeps their places.
	var at: Dictionary = hull.arrangement()
	for title in at:
		_hull_prefs[title] = at[title]
	for title in _hull_prefs:
		cfg.set_value("hull", title, _hull_prefs[title])
	cfg.save(PREFS)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not _quitting:
		_hand_back()


func _process(dt: float) -> void:
	_hud_alpha = move_toward(_hud_alpha, 1.0 if hud else 0.0, dt / STOW)
	_warp(dt)
	_resweep(dt)
	hull.modulate.a = _hud_alpha
	hull.visible = _hud_alpha > 0.0
	_tree_alpha = move_toward(_tree_alpha, 1.0 if tree_shown else 0.0, dt / STOW)
	tree.modulate.a = _tree_alpha
	tree.visible = _tree_alpha > 0.0
	if _chrono:
		_chrono_alpha = move_toward(_chrono_alpha, 1.0 if chrono_shown else 0.0, dt / STOW)
		_chrono.modulate.a = _chrono_alpha
		_chrono.visible = _chrono_alpha > 0.0
	# The usable screen changes when the menu bar hides or the display
	# changes; over the desktop, keep covering all of it.
	_screen_timer -= dt
	if desktop and _screen_timer <= 0.0:
		_screen_timer = SCREEN_BURST_GAP if _screen_burst > 0 else 1.0
		_screen_burst = maxi(_screen_burst - 1, 0)
		_ask_panels()
		var win := get_window()
		var usable := Desk.usable_rect(win.current_screen)
		if win.position != usable.position or win.size != usable.size:
			win.position = usable.position
			win.size = usable.size


## Linux: the panels are asked for on the desk hand when the last answer
## is old (Desk.PANEL_TTL, or zen just moved them); usable_rect reads the
## last answer, and a new one refits at once.
func _ask_panels() -> void:
	if _panels_asked or not Desk.panels_stale():
		return
	_panels_asked = true  # before the post: an inline hand answers inside it
	if not _hand.post(Desk.panels_refresh, _on_panels):
		_panels_asked = false


func _on_panels(_panels: Array) -> void:
	if _quitting:
		return
	_panels_asked = false
	_screen_timer = 0.0


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


func set_key_card(on: bool) -> void:
	_key_card.set_shown(on)
	_update_passthrough()


## A click anywhere the cockpit takes one puts the key card away.
func _unhandled_input(event: InputEvent) -> void:
	if _key_card and _key_card.shown and event is InputEventMouseButton and event.pressed:
		set_key_card(false)
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	# While the card is up, any key puts it away and does nothing else, so
	# Escape closes the card rather than the cockpit.
	if _key_card.shown:
		set_key_card(false)
		return
	match event.keycode:
		KEY_SLASH, KEY_F1:
			set_key_card(true)
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
		KEY_C:
			set_chrono(not chrono_shown)
		KEY_Q, KEY_ESCAPE:
			_quit()
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
