## The desk: everything the cockpit changes about the desktop around it,
## one call per intent, with the macOS way and the Linux (KDE Plasma 6,
## KWin) way side by side. Preloaded where used (not a class_name, like
## paths.gd).
##
## macOS: AppleScript through Osa, unchanged from when it lived in
## main.gd. Linux: D-Bus through qdbus6. Never OS.execute on Linux: in
## Godot 4.7 it runs the command through a shell that drops double quotes
## and expands $ and backticks (found 2026-09-28: every Plasma script lost
## its string literals). OS.execute_with_pipe and OS.create_process hand argv
## straight to the program, so a whole script goes as one argument (see
## _run). Every Linux call is blocking but short (about 10 ms each on
## Josh's machine), which also lets the quit path finish its restores
## before the process ends; and bounded, so a peer that stops answering
## (a busy Konsole, plasmashell restarting) holds a frame at most 1.5 s
## for a question, 4 s for a change, not qdbus's own 25 s (see _run).

const Paths := preload("res://scripts/paths.gd")

static var MAC: bool = OS.get_name() == "macOS"
static var LINUX: bool = OS.get_name() == "Linux"


# --- Zen: the desktop's own chrome gets out of the way ---------------------

## macOS: the Dock and the menu bar auto-hide, the setting the user could
## flip in System Settings, changed live; the first use asks the user to
## allow the app to control System Events.
const ZEN_GET := 'tell application "System Events" to tell dock preferences to get {autohide, autohide menu bar}'
const ZEN_SET := 'tell application "System Events" to tell dock preferences to set {autohide, autohide menu bar} to {%s, %s}'

## Linux: every Plasma panel goes to auto-hide through plasmashell's
## scripting console, and comes back to exactly the hiding mode it had
## ("none", "autohide", "dodgewindows", ...), by panel id.
## The same query tells the cockpit where the panels are (see
## usable_rect); screenGeometry is in logical px, like everything else.
const PANELS_GET := 'print(JSON.stringify(panels().map(function (p) { var g = screenGeometry(p.screen); return {id: String(p.id), hiding: p.hiding, loc: p.location, h: p.height, floating: p.floating, g: [g.x, g.y, g.width, g.height]}; })))'
const PANELS_HIDE := 'panels().forEach(function (p) { p.hiding = "autohide"; })'
const PANELS_SET := 'var want = %s; panels().forEach(function (p) { var h = want[String(p.id)]; if (h !== undefined) p.hiding = h; })'
## Careful (the guard's release, main.gd _unzen): only a panel zen still
## holds, so one set otherwise since stays as it was set.
const PANELS_SET_CAREFUL := 'var want = %s; panels().forEach(function (p) { var h = want[String(p.id)]; if (h !== undefined && p.hiding == "autohide") p.hiding = h; })'
## plasmashellrc's panelVisibility for each hiding mode (Plasma 6's
## PanelView::VisibilityMode), for the offline hand-back.
const HIDING := {"none": 0, "autohide": 1, "dodgewindows": 2, "windowsgobelow": 3}
## How long the guard's release waits for plasmashell to exit before
## giving the panels up (see _panels_offline).
const OFFLINE_WAIT := 15.0


## What zen will hand back: {dock, menu} on macOS, {panels: {id: hiding}}
## on Linux; {} when it could not be read (System Events not allowed yet,
## plasmashell busy or restarting), so the caller knows it has nothing to
## hand back rather than a record of no panels.
static func zen_read() -> Dictionary:
	if MAC:
		var parts := Osa.run(ZEN_GET).split(",")
		if parts.size() != 2:
			return {}
		return {"dock": parts[0].strip_edges() == "true", "menu": parts[1].strip_edges() == "true"}
	if LINUX:
		var hiding := {}
		for p in _panels(true):
			hiding[str(p.get("id", ""))] = str(p.get("hiding", "none"))
		return {"panels": hiding} if not hiding.is_empty() else {}
	return {}


## On: hide the chrome. Off: hand back `prev`, as zen_read gave it;
## `careful` (the guard's release) only what zen still holds. Linux, off:
## with plasmashell gone from the bus, its file instead (_panels_offline).
## Says how it went, for the guard's log.
static func zen_apply(on: bool, prev: Dictionary, careful := false) -> String:
	if MAC:
		var dock: bool = true if on else bool(prev.get("dock", false))
		var menu: bool = true if on else bool(prev.get("menu", false))
		Osa.fire(ZEN_SET % [str(dock).to_lower(), str(menu).to_lower()])
		return "live"
	if not LINUX:
		return "skipped"
	var how := "live"
	if on:
		_plasma(PANELS_HIDE, WRITE_SECS)
	else:
		var want: Dictionary = prev.get("panels", {})
		if want.is_empty():
			how = "skipped"
		else:
			_plasma((PANELS_SET_CAREFUL if careful else PANELS_SET) % JSON.stringify(want), WRITE_SECS)
			if _failed:
				how = "failed live" if _on_bus("org.kde.plasmashell") else _panels_offline(want, OFFLINE_WAIT if careful else 0.0)
	_panels_at = -1  # the struts just changed; usable_rect asks again
	return how


## The panels handed back through plasmashellrc, for a plasmashell already
## off the bus (a logout that took it first). plasmashell syncs its config
## lazily and again at exit, so a file edit only holds once it is gone: it
## waits up to `wait` seconds for every plasmashell of this session (our
## uid, our bus) to exit, and gives up past that. A panel is written only
## if the file still says auto-hide and zen found it otherwise.
static func _panels_offline(want: Dictionary, wait: float) -> String:
	var until := Time.get_ticks_msec() + int(wait * 1000.0)
	var left := _session_procs("plasmashell")
	while not left.is_empty():
		if Time.get_ticks_msec() >= until:
			return "gave up (plasmashell %s still running)" % str(left[0])
		OS.delay_msec(250)
		_trees_frame = -1  # a listing from before the wait is stale after it
		left = _session_procs("plasmashell")
	var n := 0
	for id in want:
		var mode = HIDING.get(str(want[id]))
		if mode == null or str(want[id]) == "autohide":
			continue
		var key := ["--file", "plasmashellrc", "--group", "PlasmaViews", "--group", "Panel %s" % id, "--key", "panelVisibility"]
		if _run("kreadconfig6", key, WRITE_SECS) != "1" or _failed:
			continue
		_run("kwriteconfig6", key + [str(mode)], WRITE_SECS)
		n += 0 if _failed else 1
	return "offline (%d written)" % n


## This session's processes named `comm`: our uid and our session bus (a
## plasmashell or Konsole of another login is not ours to wait for). One
## whose bus cannot be read counts as ours; a zombie does not count.
static func _session_procs(comm: String) -> Array:
	var me := _uid(_read_proc("/proc/self/status"))
	var addr := OS.get_environment("DBUS_SESSION_BUS_ADDRESS")
	var found := []
	for d in DirAccess.get_directories_at("/proc"):
		if not d.is_valid_int() or _read_proc("/proc/%s/comm" % d).strip_edges() != comm:
			continue
		var status := _read_proc("/proc/%s/status" % d)
		if _uid(status) != me or "\nState:\tZ" in status:
			continue  # another user's, or a zombie: gone all but the name
		if not addr.is_empty():
			var theirs := ""
			for kv in _read_proc("/proc/%s/environ" % d, 65536).split("\n", false):
				if kv.begins_with("DBUS_SESSION_BUS_ADDRESS="):
					theirs = kv.trim_prefix("DBUS_SESSION_BUS_ADDRESS=")
			if not theirs.is_empty() and theirs != addr:
				continue
		found.append(int(d))
	return found


## A /proc file through a handle (they report a length of 0), NULs (an
## environ's separators) read as line breaks.
static func _read_proc(path: String, most := 4096) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var raw := f.get_buffer(most)
	for i in raw.size():
		if raw[i] == 0:
			raw[i] = 10
	return raw.get_string_from_utf8()


static func _uid(status: String) -> String:
	for line in status.split("\n"):
		if line.begins_with("Uid:"):
			return line.split("\t", false)[1] if line.split("\t", false).size() > 1 else ""
	return ""


## The previous values live in prefs beside the rest of zen. macOS keeps
## its original keys, so an existing prefs file still reads. No record is
## saved as no keys, so it loads back as {} (see main.gd _desk_zen), never
## as a record of nothing to hand back.
static func zen_save(cfg: ConfigFile, prev: Dictionary) -> void:
	if MAC and prev.has("dock") and prev.has("menu"):
		cfg.set_value("zen", "prev_dock", bool(prev["dock"]))
		cfg.set_value("zen", "prev_menu", bool(prev["menu"]))
	elif LINUX and not (prev.get("panels", {}) as Dictionary).is_empty():
		cfg.set_value("zen", "prev_panels", prev["panels"])


static func zen_load(cfg: ConfigFile) -> Dictionary:
	if MAC:
		if not (cfg.has_section_key("zen", "prev_dock") and cfg.has_section_key("zen", "prev_menu")):
			return {}
		return {"dock": bool(cfg.get_value("zen", "prev_dock")), "menu": bool(cfg.get_value("zen", "prev_menu"))}
	if LINUX:
		var panels = cfg.get_value("zen", "prev_panels", {})
		return {"panels": panels} if panels is Dictionary and not panels.is_empty() else {}
	return {}


## Linux, a restart in zen: a panel added since zen began is not in the
## record, and hiding every panel again would leave it on auto-hide for
## good. It joins the record as it is now (zen never hid it). Recorded
## panels keep their answer: they are hidden now.
static func zen_merge(prev: Dictionary) -> Dictionary:
	if not LINUX or prev.is_empty():
		return prev
	var now := zen_read()
	if now.is_empty():
		return prev
	var panels: Dictionary = (prev["panels"] as Dictionary).duplicate()
	for id in now["panels"]:
		if not panels.has(id):
			panels[id] = now["panels"][id]
	return {"panels": panels}


# --- The terminal dissolves -------------------------------------------------

## Terminal (macOS) or Konsole (Linux) switches to the "Yggdrasil"
## profile, the default profile with a transparent background, so the
## text sits on the void. tools/terminal_zen_profile.sh (macOS) or
## tools/konsole_zen_profile.sh (Linux) makes it; the cockpit runs the
## script once if the profile is missing.
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
const TERM_SCRIPT_MAC := "tools/terminal_zen_profile.sh"
const TERM_SCRIPT_LINUX := "tools/konsole_zen_profile.sh"


## The profile the terminal is using now, or "" if it is not running.
## Konsole: the first window's default profile (what new tabs open in),
## the closest thing to Terminal's "default settings".
static func terminal_current() -> String:
	if MAC:
		return Osa.run(TERM_GET)
	if LINUX:
		for svc in _konsoles():
			for obj in _objects(svc, "/Windows/"):
				var name := _qdbus([svc, obj, "org.kde.konsole.Window.defaultProfile"])
				if not name.is_empty():
					return name
	return ""


## The last resort for the profile to hand back: Terminal's own "Basic";
## Konsole's configured default profile, else its built-in one; "" when
## konsolerc could not be read, which is no answer: a guess of built-in
## would hand every window back the wrong profile.
static func terminal_fallback() -> String:
	if LINUX:
		var file := terminal_default_file()
		if read_failed():
			return ""
		var name := file.trim_suffix(".profile")
		return name if not name.is_empty() and name != TERM_PROFILE else "Built-in"
	return "Basic"


## Konsole keeps its default profile in konsolerc, by file name, and
## setDefaultProfile writes it there, so zen's profile outlives zen: with
## no Konsole running when zen ends (every window closed first, or the
## cockpit killed mid-zen), every Konsole opened after would start
## dissolved. The entry as it stands: "" is Konsole's built-in profile
## (no key at all), and "" too when the read failed: read_failed tells
## them apart. A local file with no peer to wedge, so it gets a write's
## bound: a read cut short on a loaded box must not pass for "built-in".
static func terminal_default_file() -> String:
	if not LINUX:
		return ""
	return _run("kreadconfig6", ["--file", "konsolerc", "--group", "Desktop Entry", "--key", "DefaultProfile"], WRITE_SECS)


## Hand konsolerc back `file` ("" for the built-in profile), but only if
## zen's profile is still the default there: a default Josh picked since
## is his.
static func terminal_unstick(file: String) -> bool:
	if not LINUX or terminal_default_file() != TERM_PROFILE + ".profile":
		return false
	var args := ["--file", "konsolerc", "--group", "Desktop Entry", "--key", "DefaultProfile"]
	if file.is_empty() or file == TERM_PROFILE + ".profile":
		args.append("--delete")
	else:
		args.append(file)
	_run("kwriteconfig6", args, WRITE_SECS)
	return not _failed


## The file a Konsole profile named `name` lives in (the user's profiles,
## then the system's), for prefs that predate terminal_default_file; ""
## when there is none, which is the built-in profile.
static func terminal_profile_file(name: String) -> String:
	if not LINUX or name.is_empty():
		return ""
	var data := OS.get_environment("XDG_DATA_HOME")
	if data.is_empty():
		data = OS.get_environment("HOME").path_join(".local/share")
	var sys := OS.get_environment("XDG_DATA_DIRS")
	var dirs := PackedStringArray([data])
	dirs.append_array((sys if not sys.is_empty() else "/usr/local/share:/usr/share").split(":", false))
	for dir in dirs:
		var d := dir.path_join("konsole")
		if not DirAccess.dir_exists_absolute(d):
			continue
		for f in DirAccess.get_files_at(d):
			if f.get_extension() != "profile":
				continue
			for line in FileAccess.get_file_as_string(d.path_join(f)).split("\n"):
				if line.strip_edges() == "Name=" + name:
					return f
	return ""


## Make sure the zen profile exists, making it if it does not. False when
## it cannot be made.
static func terminal_ready() -> bool:
	if MAC:
		if Osa.run(TERM_HAS % TERM_PROFILE) == "true":
			return true
		return _make_profile(TERM_SCRIPT_MAC)
	if LINUX:
		if FileAccess.file_exists(_konsole_profile_path()):
			return true
		return _make_profile(TERM_SCRIPT_LINUX)
	return false


## Linux only, at startup: a running Konsole never rereads its profile
## directory, so the zen profile must exist before a Konsole starts for
## that Konsole to be able to switch to it. Made as early as possible,
## every Konsole opened after the cockpit's first run can dissolve. Not
## from a headless test run, which should leave the desktop alone.
static func terminal_prepare() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if LINUX and not FileAccess.file_exists(_konsole_profile_path()):
		_make_profile(TERM_SCRIPT_LINUX)


## Switch every window and tab to `profile`. Konsole: every session of
## every Konsole process, and every window's default for new tabs; going
## back, only what is on the zen profile, so a tab Josh had put on some
## other profile keeps it.
## Konsole 26 answers setProfile with AccessDenied ("security sensitive
## DBus API is disabled") yet applies it; the answer is ignored. A
## Konsole that predates the profile file does not know it, and is named
## once so the reason it stayed opaque is on record.
## False when going to zen left a Konsole unasked (no answer, or a window
## not on the bus yet), so the caller can sweep again later. `bars` false
## leaves the toolbars and menu bars be on the way back (zen never hid
## any). terminal_live counts the Konsoles the last call found.
static var terminal_live := 0


static func terminal_set(profile: String, bars := true) -> bool:
	if MAC:
		Osa.fire(TERM_SET % [profile, profile, profile])
		return true
	if not LINUX:
		return true
	var all := true
	terminal_live = _konsoles().size()
	for svc in _konsoles():
		var windows := _objects(svc, "/Windows/")
		if profile == TERM_PROFILE and windows.is_empty():
			all = false  # still starting, or wedged: its listing said nothing
			continue
		if profile == TERM_PROFILE and svc not in _stale_warned and svc not in _knows_zen:
			var known := _qdbus([svc, windows[0], "org.kde.konsole.Window.profileList"])
			if known.is_empty():
				all = false
				continue  # no answer (busy, just gone) says nothing; next time
			if TERM_PROFILE not in known.split("\n"):
				_stale_warned.append(svc)
				print("zen: %s started before the %s profile existed; restart it to dissolve" % [svc, TERM_PROFILE])
				continue
			_knows_zen.append(svc)  # and always will, so it is asked once
		var back := profile != TERM_PROFILE
		for obj in windows:
			if not back or _qdbus([svc, obj, "org.kde.konsole.Window.defaultProfile"]) == TERM_PROFILE:
				_qdbus([svc, obj, "org.kde.konsole.Window.setDefaultProfile", profile], WRITE_SECS)
		for obj in _objects(svc, "/Sessions/"):
			if not back or _qdbus([svc, obj, "org.kde.konsole.Session.profile"]) == TERM_PROFILE:
				_qdbus([svc, obj, "org.kde.konsole.Session.setProfile", profile], WRITE_SECS)
		if bars or not back:
			_toolbars(svc, not back)
	return all


static var _stale_warned: PackedStringArray = []
static var _knows_zen: PackedStringArray = []


## Terminal.app has no toolbar; Konsole does, an opaque strip (New Tab,
## Split View, Copy, Paste) left floating over the void once the
## background clears (Josh, 2026-09-28). In zen each window's toolbars are
## hidden, and the ones that were showing are remembered by
## "service window", so leaving zen shows those again and a toolbar Josh
## had hidden himself stays hidden. A cockpit restarted mid-zen has lost
## that memory, so it shows them all: the stock look.
## Konsole's own menu bar is the same kind of strip (on in a stock
## Konsole; macOS's is global and zen hides it). It goes the same way,
## through the window's Show Menubar action, and comes back only where it
## was showing; with no memory it is left alone, since off is the one
## Josh chose, unless menubar_back says it was on before zen (konsolerc,
## read at zen-on and kept in prefs).
## hid_bars: zen has hidden a bar or a menu bar (main.gd keeps it in
## prefs, so a release after a kill knows whether to show them again).
static var _shown_toolbars := {}
static var _shown_menubars := {}
static var hid_bars := false
static var menubar_back := false
const MENUBAR := "/actions/options_show_menubar"


static func _toolbars(svc: String, hide: bool) -> void:
	for win in _objects(svc, "/konsole/MainWindow_"):
		var key := svc + " " + win
		if hide:
			if _shown_toolbars.has(key):
				continue  # already put away; a second pass must not forget them
			var shown := PackedStringArray()
			for bar in _bar_names(svc, win):
				if _qdbus([svc, win, "org.kde.konsole.KXmlGuiWindow.isToolBarVisible", bar]) == "true":
					shown.append(bar)
					_qdbus([svc, win, "org.kde.konsole.KXmlGuiWindow.setToolBarVisible", bar, "false"], WRITE_SECS)
					hid_bars = true
			_shown_toolbars[key] = shown
			# trigger, not setChecked: the menu bar follows the action's
			# triggered signal, which setChecked does not send.
			if _menubar_shown(svc, win):
				_qdbus([svc, win + MENUBAR, "org.qtproject.Qt.QAction.trigger"], WRITE_SECS)
				_shown_menubars[key] = true
				hid_bars = true
		else:
			var bars = _shown_toolbars.get(key, null)
			if bars == null:
				bars = _bar_names(svc, win)
				if menubar_back:
					_shown_menubars[key] = true
			for bar in bars:
				_qdbus([svc, win, "org.kde.konsole.KXmlGuiWindow.setToolBarVisible", bar, "true"], WRITE_SECS)
			_shown_toolbars.erase(key)
			if _shown_menubars.has(key) and not _menubar_shown(svc, win):
				_qdbus([svc, win + MENUBAR, "org.qtproject.Qt.QAction.trigger"], WRITE_SECS)
			_shown_menubars.erase(key)


## A window's toolbars by name, asked once: a window keeps the ones it
## was made with.
static var _bars := {}


static func _bar_names(svc: String, win: String) -> PackedStringArray:
	var key := svc + " " + win
	if not _bars.has(key):
		var names := _qdbus([svc, win, "org.kde.konsole.KXmlGuiWindow.toolBars"]).split("\n", false)
		if names.is_empty():
			return names  # no answer is not an answer; ask next time
		_bars[key] = names
	return _bars[key]


static func _menubar_shown(svc: String, win: String) -> bool:
	return _qdbus([svc, win + MENUBAR, "org.qtproject.Qt.QAction.checked"]) == "true"


## Konsole's layout as zen found it, for a release with no Konsole left
## to ask: konsolestaterc's window State (toolbars included; written by
## each window as it closes) and konsolerc's MenuBar ("" when unset). {}
## when either read failed, so it never replaces an answer.
static func konsole_layout() -> Dictionary:
	if not LINUX:
		return {}
	var state := _run("kreadconfig6", ["--file", _konsole_state_file(), "--group", "MainWindow", "--key", "State"], WRITE_SECS)
	if _failed:
		return {}
	var menubar := _run("kreadconfig6", ["--file", "konsolerc", "--group", "MainWindow", "--key", "MenuBar"], WRITE_SECS)
	if _failed:
		return {}
	return {"state": state, "menubar": menubar}


## The guard's release, with no Konsole of ours running: a window closed
## in zen saved its bars hidden, so the next one would open that way.
## Each entry goes back to `lay` (konsole_layout's) only where it moved.
static func konsole_layout_offline(lay: Dictionary) -> String:
	if not LINUX or lay.is_empty():
		return "skipped"
	if not _session_procs("konsole").is_empty():
		return "skipped (Konsole running)"
	var n := 0
	var at := ["--file", _konsole_state_file(), "--group", "MainWindow", "--key", "State"]
	var was := str(lay.get("state", ""))
	var now := _run("kreadconfig6", at, WRITE_SECS)
	if not _failed and now != was:
		_run("kwriteconfig6", at + ([was] if not was.is_empty() else ["--delete"]), WRITE_SECS)
		n += 0 if _failed else 1
	at = ["--file", "konsolerc", "--group", "MainWindow", "--key", "MenuBar"]
	was = str(lay.get("menubar", ""))
	if _run("kreadconfig6", at, WRITE_SECS) == "Disabled" and not _failed and was != "Disabled":
		_run("kwriteconfig6", at + ([was] if not was.is_empty() else ["--delete"]), WRITE_SECS)
		n += 0 if _failed else 1
	return "offline (%d written)" % n


static func _konsole_state_file() -> String:
	var state := OS.get_environment("XDG_STATE_HOME")
	if state.is_empty():
		state = OS.get_environment("HOME").path_join(".local/state")
	return state.path_join("konsolestaterc")


static func _make_profile(rel: String) -> bool:
	var script := Paths.find_up(rel)
	if script.is_empty():
		print("zen: %s profile missing and no %s to make it" % [TERM_PROFILE, rel])
		return false
	if LINUX:
		# The script renames the profile into place last, so a run cut
		# short leaves none; say so rather than trust it.
		_run("/bin/sh", [script], PROFILE_SECS)
		if _timed_out or not FileAccess.file_exists(_konsole_profile_path()):
			print("zen: %s did not finish; no %s profile" % [rel, TERM_PROFILE])
			return false
	else:
		OS.execute("/bin/sh", [script])
	return true


static func _konsole_profile_path() -> String:
	var data := OS.get_environment("XDG_DATA_HOME")
	if data.is_empty():
		data = OS.get_environment("HOME").path_join(".local/share")
	return data.path_join("konsole").path_join(TERM_PROFILE + ".profile")


# --- Borders (Linux) -----------------------------------------------------------

## macOS cannot script Terminal's title bar away, so cover.gd paints the
## wallpaper over it. KWin can: in zen a small KWin script takes the frame
## off every Konsole window, and off any opened while it runs; leaving zen
## unloads it and a one-shot script puts the frames back (KWin does not
## undo a script's changes when it is unloaded). The scripts are written
## to user:// so an exported cockpit carries them.
const BORDERS_PLUGIN := "yggdrasil_zen_borders"
const BORDERS_JS := '// Yggdrasil System, zen: Konsole windows lose their frame.
function konsole(w) {
	return w.normalWindow && (w.desktopFileName == "org.kde.konsole" || w.resourceClass == "org.kde.konsole" || w.resourceClass == "konsole");
}
function bare(w) { if (konsole(w)) w.noBorder = true; }
workspace.windowList().forEach(bare);
workspace.windowAdded.connect(bare);
'
const CLOTHE_JS := '// Yggdrasil System, zen over: Konsole windows get their frame back.
function konsole(w) {
	return w.normalWindow && (w.desktopFileName == "org.kde.konsole" || w.resourceClass == "org.kde.konsole" || w.resourceClass == "konsole");
}
workspace.windowList().forEach(function (w) { if (konsole(w)) w.noBorder = false; });
callDBus("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting", "unloadScript", "%s");
'

## null until the first call, so the first call always looks: a cockpit
## that crashed in zen left the script loaded, and the next start's
## borders(false) takes it away. Only then acts: KWin forgets a D-Bus loaded
## script when it restarts (the frames it took then come back with the
## new session's windows), so a start that finds no script left over has
## nothing to put back, and a Konsole Josh made frameless himself stays so.
static var _bare = null


## True when it asked KWin to change something.
static func borders(bare: bool) -> bool:
	if not LINUX or (_bare != null and _bare == bare):
		return false
	var first: bool = _bare == null
	_bare = bare
	if first and not bare and not _kwin_loaded(BORDERS_PLUGIN):
		return false
	if bare:
		_kwin_run(BORDERS_JS, BORDERS_PLUGIN)
	else:
		_kwin_unload(BORDERS_PLUGIN)
		# It unloads itself once it has run: KWin reads a script's file on
		# a worker thread after run(), so unloading it from here at once
		# could beat it to the windows.
		_kwin_run(CLOTHE_JS % (BORDERS_PLUGIN + "_off"), BORDERS_PLUGIN + "_off")
	return true


## Loads and runs `js` as `plugin`, first unloading any copy left over
## (KWin will not load a name twice).
static func _kwin_run(js: String, plugin: String) -> void:
	_kwin_unload(plugin)
	var path := ProjectSettings.globalize_path("user://%s.js" % plugin)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("could not write " + path)
		return
	f.store_string(js)
	f.close()
	var id := _qdbus(["org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.loadScript", path, plugin], WRITE_SECS)
	if not id.is_valid_int() or int(id) < 0:
		push_warning("KWin would not load %s (%s)" % [plugin, id])
		return
	_qdbus(["org.kde.KWin", "/Scripting/Script" + id, "org.kde.kwin.Script.run"], WRITE_SECS)


static func _kwin_loaded(plugin: String) -> bool:
	return _qdbus(["org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.isScriptLoaded", plugin]) == "true"


## Unasked: KWin answers false for a name it has not loaded, so asking
## first (isScriptLoaded) would only cost a spawn.
static func _kwin_unload(plugin: String) -> void:
	_qdbus(["org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.unloadScript", plugin], WRITE_SECS)


# --- The usable screen ----------------------------------------------------------

## The part of a screen windows may use. Godot's X11 backend reads the
## one _NET_WORKAREA rect X11 has for the whole desktop and clips every
## screen by it, so on Josh's two monitors the 1440-high screen came back
## 1036 high, the 1080 screen's panel cut taken off both. On Linux the
## cockpit works it out itself: the screen, less each Plasma panel on it
## that reserves space (hiding "none"). Panels are asked for at most
## every PANEL_TTL seconds; zen_apply asks again at once.
## A floating panel (Plasma 6's default) reserves its gap to the screen
## edge too, FLOAT_GAP logical px, so the cockpit's edge stays clear of it.
const PANEL_TTL := 5.0
const FLOAT_GAP := 8
static var _panel_cache: Array = []
static var _panels_at := -1


static func usable_rect(screen: int) -> Rect2i:
	if not LINUX:
		return DisplayServer.screen_get_usable_rect(screen)
	var r := Rect2i(DisplayServer.screen_get_position(screen), DisplayServer.screen_get_size(screen))
	for p in _panels(false):
		var g: Array = p.get("g", [])
		if g.size() != 4 or str(p.get("hiding", "")) != "none":
			continue
		var at := Rect2i(int(g[0]), int(g[1]), int(g[2]), int(g[3]))
		if not r.has_point(at.get_center()):
			continue
		var h := int(p.get("h", 0)) + (FLOAT_GAP if p.get("floating", false) == true else 0)
		match str(p.get("loc", "")):
			"bottom": r.size.y -= h
			"top":
				r.position.y += h
				r.size.y -= h
			"left":
				r.position.x += h
				r.size.x -= h
			"right": r.size.x -= h
	return r


static func _panels(fresh: bool) -> Array:
	var now := Time.get_ticks_msec()
	if fresh or _panels_at < 0 or now - _panels_at > PANEL_TTL * 1000.0:
		_panels_at = now
		var parsed = JSON.parse_string(_plasma(PANELS_GET))
		_panel_cache = parsed if parsed is Array else []
	return _panel_cache


# --- D-Bus plumbing (Linux) -----------------------------------------------------

## How long a call may take before it is given up: a question (a getter,
## a listing) READ_SECS, anything that changes the desk WRITE_SECS, and
## the zen profile script PROFILE_SECS. A peer that does not answer is
## sent SIGTERM then, and SIGKILL KILL_GRACE later, so the worst a read
## costs is 1.5 s and a write 4 s. A healthy answer takes about 10 ms.
const READ_SECS := 1.0
const WRITE_SECS := 3.5
const PROFILE_SECS := 10.0
const KILL_GRACE := 0.5
## A peer that timed out is left alone for WEDGE_SECS (its calls answer
## "" at once), so a wedged Konsole costs one timeout, not one per call.
## ask_again forgets them: each Z press, and the quit, gives every peer
## one more chance.
const WEDGE_SECS := 10.0
static var _wedged := {}
static var _timed_out := false
static var _failed := false
static var _qdbus_bin := ""
static var _timeout_bin = null


## The Qt 6 qdbus: qdbus6 (Arch, Manjaro: qt6-tools), qdbus-qt6 (Fedora),
## else plain qdbus. `secs`: READ_SECS for a question, WRITE_SECS for a
## change.
static func _qdbus(args: Array, secs := READ_SECS) -> String:
	if _qdbus_bin.is_empty():
		_qdbus_bin = "qdbus"
		for bin in ["qdbus6", "qdbus-qt6"]:
			if _qdbus_bin == "qdbus":
				var found := _which(bin)
				if not found.is_empty():
					_qdbus_bin = found
	var peer: String = args[0] if not args.is_empty() else ""
	if _wedged.has(peer):
		if Time.get_ticks_msec() - int(_wedged[peer]) < WEDGE_SECS * 1000.0:
			_failed = true
			return ""
		_wedged.erase(peer)
	var out := _run(_qdbus_bin, args, secs)
	if _timed_out:
		_wedged[peer] = Time.get_ticks_msec()
		var asked: String = args[2] if args.size() > 2 else "its listing"
		print("desk: %s did not answer %s; left alone for %d s" % [peer if not peer.is_empty() else "the bus", asked, int(WEDGE_SECS)])
	return out


## A Z press, or the quit: every peer is asked again (see WEDGE_SECS).
static func ask_again() -> void:
	_wedged.clear()


## Whether the last call failed (timed out, or exited non-zero), which
## its "" alone does not say.
static func read_failed() -> bool:
	return _failed


static func _which(bin: String) -> String:
	for dir in OS.get_environment("PATH").split(":", false):
		if FileAccess.file_exists(dir.path_join(bin)):
			return dir.path_join(bin)
	return ""


## Run and wait; stdout stripped, or "" on failure. Argv goes to the
## program untouched (see the top of this file). At the end of a pipe
## Godot's FileAccess does not set eof_reached, it reports a read error,
## so either ends the read.
## Bounded by coreutils timeout, argv again, which signals its whole
## process group (a script's children too), so the pipe closes by
## `secs` + KILL_GRACE whatever the program does. It exits 124 when
## SIGTERM sufficed; when SIGKILL was needed it goes down with its group,
## which Godot reports as the signal, 9. Either sets _timed_out. The
## child is always reaped: OS.kill waits for one that outlives the pipe.
static func _run(bin: String, args: Array, secs := READ_SECS) -> String:
	if _timeout_bin == null:
		_timeout_bin = _which("timeout")
	var argv := PackedStringArray(args)
	if not _timeout_bin.is_empty():
		argv = PackedStringArray(["-k", str(KILL_GRACE), str(secs), bin]) + argv
		bin = _timeout_bin
	_timed_out = false
	_failed = true
	var proc := OS.execute_with_pipe(bin, argv)
	if proc.is_empty():
		return ""
	var pipe: FileAccess = proc["stdio"]
	var lines := PackedStringArray()
	while true:
		var line := pipe.get_line()
		if line.is_empty() and (pipe.eof_reached() or pipe.get_error() != OK):
			break
		lines.append(line)
	pipe.close()
	(proc["stderr"] as FileAccess).close()
	# Reap it (the pipe is closed, so it is exiting if not gone), in fine
	# steps: timeout exits a beat after its child, and 2 ms steps cost
	# every call about that much.
	var code := -1
	for _i in 500:
		code = OS.get_process_exit_code(proc["pid"])
		if code != -1:
			break
		OS.delay_usec(200)
	if code == -1:
		OS.kill(proc["pid"])
	_timed_out = not _timeout_bin.is_empty() and (code == 124 or code == 9)
	_failed = code != 0
	return "\n".join(lines).strip_edges() if code == 0 else ""


static func _plasma(js: String, secs := READ_SECS) -> String:
	return _qdbus(["org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", js], secs)


## The bus's names ("") or a Konsole's objects. A Z press asks for the
## same listings over and over (terminal_current, then each step of
## terminal_set), and nothing the cockpit does adds or takes objects, so
## each is asked once a frame.
static var _trees := {}
static var _trees_frame := -1


static func _tree(svc: String) -> String:
	var frame := Engine.get_process_frames()
	if frame != _trees_frame:
		_trees.clear()
		_trees_frame = frame
	if not _trees.has(svc):
		_trees[svc] = _qdbus([svc] if not svc.is_empty() else [])
	return _trees[svc]


## A well-known name on the bus. qdbus6 indents them under their owners.
static func _on_bus(svc: String) -> bool:
	for line in _tree("").split("\n"):
		if line.strip_edges() == svc:
			return true
	return false


## Every running Konsole process: each owns org.kde.konsole-<pid>.
static func _konsoles() -> PackedStringArray:
	var found := PackedStringArray()
	for line in _tree("").split("\n"):
		var name := line.strip_edges()
		if name.begins_with("org.kde.konsole-"):
			found.append(name)
	return found


## A Konsole's numbered objects: /Windows/N, /Sessions/N,
## /konsole/MainWindow_N.
static func _objects(svc: String, prefix: String) -> PackedStringArray:
	var found := PackedStringArray()
	for line in _tree(svc).split("\n"):
		var path := line.strip_edges()
		if path.begins_with(prefix) and path.trim_prefix(prefix).is_valid_int():
			found.append(path)
	return found
