extends Node
## NERViewer is its own application; this docks it. The block's inner
## disc is measured on screen and written to NERViewer's user://dock.cfg,
## which NERViewer polls; while the file exists it shows its sigil alone,
## filling that rect. If NERViewer is not running when the workspace
## first reports, it is launched once. On exit the file is removed and
## NERViewer goes back to being itself.
##
## Stowing (the HUD put away) is the file's `hidden` key on any system;
## NERViewer goes invisible while it is docked and hidden. macOS also
## hides the app through System Events, as it always has; Linux has no
## such switch for another app, hence the key.

const Paths := preload("res://scripts/paths.gd")
const BUNDLE_ID := "edu.pdx.josh.nerviewer"
## The sibling repo's built app first (found from the editor or from an
## exported cockpit alike), then an installed copy.
const APP_SIBLING := "NERViewer/dist/NERViewer.app"
const APP_INSTALLED := "/Applications/NERViewer.app"
## Linux: the sibling repo's export for this machine's architecture
## (its build_app.sh names it NERViewer.x86_64 or NERViewer.arm64, as
## Engine.get_architecture_name does), else (developing) its Godot project.
const LINUX_SIBLING := "NERViewer/dist/linux/NERViewer.%s"
const LINUX_PROJECT := "NERViewer/game/project.godot"
## Wait this long after the workspace starts reporting before launching:
## at login NERViewer's own launch agent may still be coming up.
const LAUNCH_GRACE := 5.0
## If NERViewer has a launch agent (macOS) or a systemd user unit
## (Linux), that owns it: kickstart and `systemctl --user start` are both
## idempotent (a running job is left alone), so a slow first launch can
## never end in two copies. Without one, open the app.
const AGENT := "edu.pdx.josh.nerviewer"
const POLL := 0.5
## Stowed with the HUD: NERViewer is hidden as an app (what Cmd-H does)
## through System Events, and shown again when the HUD returns or the
## cockpit quits. Applied once it is running, so a boot with the HUD
## stowed hides it as soon as it comes up.
const HIDE := 'tell application "System Events" to set visible of (first process whose bundle identifier is "%s") to %s'

var block: SigilBlock
var _timer := 0.0
var _last_rect := Rect2i()
var _launched := false
var _dock_path := ""
var _want_hidden := false
var _hidden := false
## Set by release(): the quit path, so the frame between it and the tree
## going away does not write the file back.
var _released := false


func _ready() -> void:
	# Sibling of this project's own user dir.
	_dock_path = OS.get_user_data_dir().get_base_dir().path_join("NERViewer").path_join("dock.cfg")
	Workspace.changed.connect(_maybe_launch)


func _process(dt: float) -> void:
	_timer -= dt
	if _timer > 0.0 or block == null or _released:
		return
	_timer = POLL
	block.bare = running()
	# Failing: launched (or given up on) and still not here, past the grace.
	block.failing = _launched and not running() and Workspace.clock > LAUNCH_GRACE * 2.0
	if OS.get_name() == "macOS" and running() and _hidden != _want_hidden:
		_hidden = _want_hidden
		Osa.fire(HIDE % [BUNDLE_ID, "true" if _hidden else "false"])
	var rect := _screen_rect()
	# Rewritten when gone too: something removed it (an older cockpit's
	# quit), and NERViewer would stay undocked until the next move.
	if rect != _last_rect or not FileAccess.file_exists(_dock_path):
		_last_rect = rect
		_write(rect)


## The inner disc in screen pixels: canvas -> window pixels -> screen.
func _screen_rect() -> Rect2i:
	var local: Rect2 = block.inner_rect()
	var canvas := block.get_global_transform_with_canvas()
	var final := get_viewport().get_final_transform()
	var xf := final * canvas
	var p: Vector2 = xf * local.position
	var s := xf.basis_xform(local.size)
	var origin: Vector2 = Vector2(get_window().position) + p
	return Rect2i(Vector2i(origin.round()), Vector2i(s.round()))


func _write(rect: Rect2i) -> void:
	DirAccess.make_dir_recursive_absolute(_dock_path.get_base_dir())
	var cfg := ConfigFile.new()
	cfg.set_value("dock", "rect", rect)
	cfg.set_value("dock", "by", "Yggdrasil System")
	cfg.set_value("dock", "pid", OS.get_process_id())  # so a crash cannot leave NERViewer stranded
	cfg.set_value("dock", "hidden", _want_hidden)
	# NERViewer checks the pid is still this program, not a recycled one.
	cfg.set_value("dock", "program", OS.get_executable_path().get_file())
	# Written aside and renamed over: ConfigFile.save truncates first, and
	# NERViewer polling in that instant would read an empty file.
	var tmp := _dock_path + ".tmp"
	if cfg.save(tmp) != OK or DirAccess.rename_absolute(tmp, _dock_path) != OK:
		DirAccess.remove_absolute(tmp)
		push_warning("could not write " + _dock_path)


func running() -> bool:
	var app = Workspace.apps.get(BUNDLE_ID)
	return app != null and app.alive


func _maybe_launch() -> void:
	if _launched or Workspace.source_name != "yggapps" or Workspace.apps.is_empty():
		return
	if running():
		_launched = true
		return
	if Workspace.clock < LAUNCH_GRACE:
		return
	_launched = true  # once per session; if Josh quits it, it stays quit
	if DisplayServer.get_name() == "headless":
		print("NERViewer dock: headless; not launching")  # a test run has no slot to dock into
		return
	if OS.get_name() == "Linux":
		_launch_linux()
		return
	var plist := OS.get_environment("HOME").path_join("Library/LaunchAgents/%s.plist" % AGENT)
	if FileAccess.file_exists(plist):
		OS.create_process("/bin/launchctl", ["kickstart", "gui/%d/%s" % [_uid(), AGENT]])
		print("NERViewer dock: kickstarted ", AGENT)
		return
	for path in [Paths.find_up(APP_SIBLING), APP_INSTALLED]:
		if not path.is_empty() and DirAccess.dir_exists_absolute(path):
			OS.create_process("/usr/bin/open", [path])
			print("NERViewer dock: launched ", path)
			return
	print("NERViewer dock: app not found; the slot waits")


## Linux: the systemd user unit if installed (tools/launch_agent.sh),
## else the sibling export, else the sibling project run by Godot (the
## one running this, when this is the editor build).
func _launch_linux() -> void:
	var config := OS.get_environment("XDG_CONFIG_HOME")
	if config.is_empty():
		config = OS.get_environment("HOME").path_join(".config")
	var unit := config.path_join("systemd/user/%s.service" % AGENT)
	# The unit if it starts; one that will not (its binary moved, the user
	# manager without a display) falls through to the export. Bounded: a
	# slow manager must not hold the frame (systemctl waits for the start).
	if FileAccess.file_exists(unit):
		var timeout := _which("timeout")
		var start := PackedStringArray(["systemctl", "--user", "start", "%s.service" % AGENT])
		var code := _exit_code(timeout, PackedStringArray(["-k", "0.5", "3"]) + start) if not timeout.is_empty() \
			else _exit_code(_which("systemctl"), start.slice(1))
		if code == 0:
			print("NERViewer dock: started ", AGENT, ".service")
			return
		print("NERViewer dock: ", AGENT, ".service would not start (", code, "); trying the export")
	var exe := Paths.find_up(LINUX_SIBLING % Engine.get_architecture_name())
	if not exe.is_empty():
		_spawn(PackedStringArray([exe]))
		print("NERViewer dock: launched ", exe)
		return
	var project := Paths.find_up(LINUX_PROJECT)
	if not project.is_empty():
		var godot := _which("godot") if OS.has_feature("template") else OS.get_executable_path()
		if godot.is_empty():
			print("NERViewer dock: no godot on PATH to run ", project.get_base_dir(), "; the slot waits")
			return
		var dir := project.get_base_dir()
		if DirAccess.dir_exists_absolute(dir.path_join(".godot")):
			_spawn(PackedStringArray([godot, "--path", dir]))
		else:
			# Never opened in the editor: without an import its class_names
			# are unknown and every script fails to parse. Import first, in
			# the same child; the paths ride in as $0/$1, never as script text.
			_spawn(PackedStringArray(["/bin/sh", "-c",
				"\"$0\" --headless --path \"$1\" --import >/dev/null 2>&1; exec \"$0\" --path \"$1\"",
				godot, dir]))
		print("NERViewer dock: launched ", dir, " with ", godot)
		return
	print("NERViewer dock: app not found; the slot waits")


## A fallback started as a plain child lives in the cockpit's cgroup, and
## a cockpit run as a systemd unit takes its whole cgroup down when it
## stops: NERViewer would die instead of undocking. So it gets a transient
## unit of its own, as macOS's `open` hands the app to launchd, carrying
## the display and data paths the cockpit sees. Without systemd-run, or if
## the user manager will not take it, a plain child as before.
const ADHOC_UNIT := "edu.pdx.josh.nerviewer-adhoc"
const ADHOC_ENV := ["DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "PATH"]


static func _spawn(argv: PackedStringArray) -> void:
	var run := _which("systemd-run")
	if not run.is_empty() and _exit_code(run, adhoc_args(argv)) == 0:
		return
	OS.create_process(argv[0], argv.slice(1))


## systemd-run's arguments for `argv`; an env name alone copies its value.
static func adhoc_args(argv: PackedStringArray) -> PackedStringArray:
	var args := PackedStringArray(["--user", "--collect", "--quiet", "--unit=" + ADHOC_UNIT])
	for name in ADHOC_ENV:
		if OS.has_environment(name):
			args.append("--setenv=" + name)
	args.append("--")
	args.append_array(argv)
	return args


static func _which(bin: String) -> String:
	for dir in OS.get_environment("PATH").split(":", false):
		if FileAccess.file_exists(dir.path_join(bin)):
			return dir.path_join(bin)
	return ""


## Run and wait for the exit code; argv goes to the program untouched
## (OS.execute runs a shell on Linux; see desk.gd). -1 if it would not run.
static func _exit_code(bin: String, args: PackedStringArray) -> int:
	var proc := OS.execute_with_pipe(bin, args)
	if proc.is_empty():
		return -1
	var pipe: FileAccess = proc["stdio"]
	while not (pipe.get_line().is_empty() and (pipe.eof_reached() or pipe.get_error() != OK)):
		pass
	pipe.close()
	(proc["stderr"] as FileAccess).close()
	var code := -1
	for _i in 500:
		code = OS.get_process_exit_code(proc["pid"])
		if code != -1:
			break
		OS.delay_msec(2)
	return code


## macOS only: the launchd domain is gui/<uid>.
static func _uid() -> int:
	var out := []
	OS.execute("/usr/bin/id", ["-u"], out)
	return int(str(out[0]).strip_edges()) if not out.is_empty() else 501


## Rewrites the dock file at once (if it has been written) so NERViewer
## hears about it on its next poll.
func set_hidden(on: bool) -> void:
	if on == _want_hidden:
		return
	_want_hidden = on
	if _last_rect != Rect2i():
		_write(_last_rect)


func release() -> void:
	_released = true
	if _hidden:
		_hidden = false
		Osa.fire(HIDE % [BUNDLE_ID, "false"])  # only ever set on macOS
	# Only our own file: another cockpit's dock is not ours to undo.
	if _dock_path != "" and FileAccess.file_exists(_dock_path):
		var cfg := ConfigFile.new()
		if cfg.load(_dock_path) != OK or int(cfg.get_value("dock", "pid", 0)) == OS.get_process_id():
			DirAccess.remove_absolute(_dock_path)


func _exit_tree() -> void:
	release()
