extends Node
## "Workspace": what you have running. Spawns yggapps and keeps one record
## per application, alive or recently gone. The tree reads `apps`; nothing
## else in the art layer touches the pipe. Without the helper (or in the
## shots tool) a scripted day stands in.
##
## The helper is per OS, same JSON: on macOS a Swift binary reading
## NSWorkspace and the window server; on Linux a Python script that asks
## KWin (KDE Plasma) for windows over D-Bus and /proc for CPU. On a Linux
## desktop without KWin it exits at once with a reason on stderr, the pipe
## closes, and the scripted day takes over as it does for a missing helper.
## A helper lost mid-session is respawned; the scripted day is only for one
## that never ran, so fake apps never grow on a tree of real ones.

signal changed
## On-screen window rects changed (something was dragged or resized).
signal windows_moved
signal source_changed(name: String)

const HELPER := "res://bin/yggapps"
const INTERVAL_MS := 1000
const RESPAWN_TRIES := 5        # restarts in a row, 2 s apart and doubling
const RESPAWN_SETTLED := 60.0   # a helper up this long has earned a fresh count

## One application, alive or withered.
class App:
	var id := ""
	var name := ""
	var pid := 0
	var launched := 0.0     # unix seconds
	var windows := 0
	var visible := 0
	## On-screen windows: macOS screen points from the main display's
	## top-left; on Linux KWin's global logical pixels from the screen
	## layout's origin, which are X11 pixels at scale 1 (the cockpit runs
	## under XWayland); frames.gd subtracts the window's own position.
	var rects: Array[Rect2] = []
	## The fast path's key when not the pid: a Linux web app shares its
	## browser's process, so its rects come as "pid/id".
	var wkey := ""
	var cpu := 0.0          # fraction of one core, this app and its children
	var active := false
	var hidden := false
	var alive := true
	var seen := 0.0         # app-clock seconds when first seen
	var gone := 0.0         # app-clock seconds when it left


var apps: Dictionary[String, App] = {}
var source_name := "none"
var clock := 0.0            # seconds since the workspace started watching

var _proc: Dictionary = {}
var _thread: Thread
var _running := false
var _synthetic := false
var _synthetic_t := 0.0
var _had_samples := false
var _respawns := 0
var _spawned_at := 0.0


func _ready() -> void:
	# The headless run that hands zen back (main.gd _unzen) spawns no
	# helper: one would stand another guard over it.
	if "--unzen" in OS.get_cmdline_user_args():
		return
	start_helper()


## In the editor the helper sits in the project's bin/. In an exported
## app it sits beside the executable: inside Contents/MacOS on macOS,
## next to YggdrasilSystem.x86_64 in dist/linux on Linux.
static func helper_path() -> String:
	var beside_exe := OS.get_executable_path().get_base_dir().path_join("yggapps")
	if FileAccess.file_exists(beside_exe):
		return beside_exe
	return ProjectSettings.globalize_path(HELPER)


func start_helper() -> void:
	var path := helper_path()
	if not FileAccess.file_exists(path):
		_fallback("helper missing at %s; run helper/build.sh" % path)
		return
	var args := ["--interval", str(INTERVAL_MS)]
	if OS.get_name() == "Linux":
		# The helper's watchdog hands zen back if the cockpit dies holding
		# it: this program again, headless, with `--unzen <pid>`.
		args += ["--guard", ProjectSettings.globalize_path("user://"), "--", OS.get_executable_path()]
		if not OS.has_feature("template"):
			args += ["--path", ProjectSettings.globalize_path("res://")]
		args += ["--headless", "--", "--unzen"]
	_proc = OS.execute_with_pipe(path, args)
	if _proc.is_empty():
		_fallback("could not spawn helper")
		return
	_running = true
	_spawned_at = clock
	# A respawned helper names itself with its first sample: until then the
	# records are withered, and the dock must not read that as NERViewer quit.
	if not _had_samples:
		source_name = "yggapps"
		source_changed.emit(source_name)
	_thread = Thread.new()
	_thread.start(_read_loop)


func _read_loop() -> void:
	var pipe: FileAccess = _proc["stdio"]
	while _running and pipe.is_open():
		var line := pipe.get_line()
		if line.is_empty():
			# A pipe's end is never eof_reached() in Godot 4.7: get_line()
			# returns "" and get_error() goes to ERR_FILE_CANT_READ.
			if pipe.eof_reached() or pipe.get_error() != OK:
				break
			OS.delay_msec(10)
			continue
		_on_line.call_deferred(line)
	_on_closed.call_deferred()


func _on_line(line: String) -> void:
	var d = JSON.parse_string(line)
	if not d is Dictionary:
		return
	if d.has("apps"):
		_had_samples = true
		if clock - _spawned_at >= RESPAWN_SETTLED:
			_respawns = 0
		if source_name != "yggapps":
			source_name = "yggapps"
			source_changed.emit(source_name)
		_ingest(d["apps"])
	elif d.has("win"):
		_ingest_windows(d["win"])


## The fast path: on-screen rects by pid, sent whenever a window moves.
## On Linux an app's windows can belong to several processes (two Konsole
## instances are one app); the helper keys them all under the record's pid.
func _ingest_windows(by_pid: Dictionary) -> void:
	for id in apps:
		var app: App = apps[id]
		if not app.alive:
			continue
		var list = by_pid.get(app.wkey if not app.wkey.is_empty() else str(app.pid), [])
		app.rects.clear()
		for r in list:
			if r is Array and r.size() == 4:
				app.rects.append(Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])))
	windows_moved.emit()
	changed.emit()


func _on_closed() -> void:
	if _running:
		_running = false
		_fallback("helper exited")


func _fallback(reason: String) -> void:
	if _had_samples:
		_retry(reason)
		return
	print("Workspace: %s; using the scripted day" % reason)
	use_synthetic()


## The feed is lost, not the apps frozen: every branch withers until the
## new helper's first sample revives the ones still running.
func _retry(reason: String) -> void:
	_drop_pipe()
	for id in apps:
		var app: App = apps[id]
		if app.alive:
			app.alive = false
			app.gone = clock
			app.active = false
			app.cpu = 0.0
	source_name = "none"
	source_changed.emit(source_name)
	changed.emit()
	if _respawns >= RESPAWN_TRIES:
		print("Workspace: %s; gave up after %d restarts" % [reason, _respawns])
		return
	var wait := 2.0 * pow(2.0, _respawns)
	_respawns += 1
	print("Workspace: %s; restarting the helper in %d s" % [reason, int(wait)])
	get_tree().create_timer(wait).timeout.connect(_respawn)


func _respawn() -> void:
	if not _running and not _synthetic:
		start_helper()


## Close a pipe whose helper has already gone and join its reader. No kill:
## the pid is the dead helper's.
func _drop_pipe() -> void:
	_running = false
	if _proc.has("stdio"):
		_proc["stdio"].close()
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	_proc = {}


func stop() -> void:
	_running = false
	if _proc.has("pid"):
		OS.kill(_proc["pid"])
	if _proc.has("stdio"):
		_proc["stdio"].close()
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	_proc = {}


func _exit_tree() -> void:
	stop()


## Merge one sample into the records. Apps not in the sample wither; an
## app that comes back is the same branch, revived.
func _ingest(list: Array) -> void:
	var present := {}
	for raw in list:
		if not raw is Dictionary or bool(raw.get("self", false)):
			continue
		var id := str(raw.get("id", ""))
		if id.is_empty():
			continue
		present[id] = true
		var app: App = apps.get(id)
		if app == null:
			app = App.new()
			app.id = id
			app.seen = clock
			apps[id] = app
		elif not app.alive:
			app.alive = true
			app.seen = clock
		app.name = str(raw.get("name", id))
		app.pid = int(raw.get("pid", 0))
		app.launched = float(raw.get("launched", 0.0))
		app.windows = int(raw.get("windows", 0))
		app.visible = int(raw.get("visible", 0))
		app.rects.clear()
		for r in raw.get("rects", []):
			if r is Array and r.size() == 4:
				app.rects.append(Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])))
		app.wkey = str(raw.get("wkey", ""))
		app.cpu = float(raw.get("cpu", 0.0))
		app.active = bool(raw.get("active", false))
		app.hidden = bool(raw.get("hidden", false))
	for id in apps:
		var app: App = apps[id]
		if app.alive and not present.has(id):
			app.alive = false
			app.gone = clock
			app.active = false
			app.cpu = 0.0
	changed.emit()


func alive_apps() -> Array:
	var out := []
	for id in apps:
		if apps[id].alive:
			out.append(apps[id])
	return out


func _process(dt: float) -> void:
	clock += dt
	if _synthetic:
		_synthetic_t += dt
		_play_day()


# --- The scripted day -------------------------------------------------------

## [t_in, t_out, id, name, windows, cpu]; t_out < 0 means it never quits.
## The same Mac day on every OS: it is a demo and the shots' fixture, and
## it carries no rects, so nothing keyed on real ids (cover, frames) reads it.
const DAY := [
	[0.0, -1.0, "com.apple.finder", "Finder", 1, 0.01],
	[1.5, -1.0, "com.apple.Terminal", "Terminal", 2, 0.04],
	[4.0, -1.0, "org.godotengine.godot", "Godot", 3, 0.35],
	[7.0, -1.0, "com.google.Chrome", "Chrome", 4, 0.6],
	[10.0, 24.0, "com.apple.mail", "Mail", 1, 0.02],
	[13.0, -1.0, "com.tinyspeck.slackmacgap", "Slack", 1, 0.05],
	[16.0, -1.0, "com.apple.Music", "Music", 1, 0.03],
	[19.0, 30.0, "com.apple.Preview", "Preview", 2, 0.01],
]
const ACTIVE_ORDER := ["com.apple.Terminal", "org.godotengine.godot", "com.google.Chrome"]


func use_synthetic() -> void:
	stop()
	_synthetic = true
	_synthetic_t = 0.0
	source_name = "scripted"
	source_changed.emit(source_name)


## Jump the scripted day to a moment; the shots tool uses it.
func seek(t: float) -> void:
	_synthetic_t = t
	_play_day()


func _play_day() -> void:
	var t := _synthetic_t
	var list := []
	var active_id: String = ACTIVE_ORDER[int(t / 6.0) % ACTIVE_ORDER.size()]
	for e in DAY:
		if t < e[0] or (e[1] >= 0.0 and t >= e[1]):
			continue
		list.append({
			"id": e[2], "name": e[3], "pid": 0, "launched": 0.0,
			"windows": e[4], "visible": e[4], "cpu": e[5],
			"active": e[2] == active_id, "hidden": false, "self": false,
		})
	_ingest(list)
