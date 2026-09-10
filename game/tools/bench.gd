extends Node
## Idle-cost bench. Runs the cockpit windowed, with prefs untouched and
## no NERViewer docking, for a fixed time, and reports how much of one
## core it used (from ps) beside the frame rate it held. The zen paint
## and the window frames are off, so this is the resting cost of the
## void, the tree, the hull and the helper.
##
##   Godot --path game res://tools/bench.tscn -- --seconds 20 --fps 12
##   ... -- --desktop            over the desktop, as it really runs
##   ... -- --desktop --opaque   the same window without per-pixel alpha
##   Godot --path game --rendering-method mobile res://tools/bench.tscn -- --label mobile
##   Godot --path game --rendering-method gl_compatibility --rendering-driver opengl3 res://tools/bench.tscn -- --label gl

const WARMUP := 3.0

var _seconds := 20.0
var _fps := Pace.IDLE
var _label := "forward_plus"
var _desktop := false
var _opaque := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seconds" and i + 1 < args.size():
			_seconds = float(args[i + 1])
		elif args[i] == "--fps" and i + 1 < args.size():
			_fps = int(args[i + 1])
		elif args[i] == "--label" and i + 1 < args.size():
			_label = args[i + 1]
		elif args[i] == "--desktop":
			_desktop = true
		elif args[i] == "--opaque":
			_opaque = true
	Pace.idle_fps = _fps
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.persist = false
	add_child(main)
	if _desktop:
		main.set_desktop(true)
		_label += " desktop"
	if _opaque:
		get_window().transparent = false
		_label += " opaque"
	await get_tree().create_timer(WARMUP).timeout
	var cpu0 := _cpu_seconds()
	var t0 := Time.get_ticks_usec()
	var frames0 := Engine.get_frames_drawn()
	await get_tree().create_timer(_seconds).timeout
	var cpu1 := _cpu_seconds()
	var wall := (Time.get_ticks_usec() - t0) / 1e6
	var frames := Engine.get_frames_drawn() - frames0
	print("bench: %s  fps=%d (held %.1f)  cpu=%.1f%% of one core  over %.0fs  apps=%d (%s)" % [
		_label, _fps, frames / wall, (cpu1 - cpu0) / wall * 100.0, wall,
		Workspace.alive_apps().size(), Workspace.source_name])
	get_tree().quit(0)


## This process's CPU time so far, from ps (minutes:seconds.hundredths).
static func _cpu_seconds() -> float:
	var out := []
	OS.execute("/bin/ps", ["-o", "time=", "-p", str(OS.get_process_id())], out)
	if out.is_empty():
		return 0.0
	var parts := str(out[0]).strip_edges().split(":")
	var s := 0.0
	for p in parts:
		s = s * 60.0 + float(p)
	return s
