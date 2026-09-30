class_name Osa
## AppleScript from Godot. OS.execute on macOS splits every argument on
## spaces and drops its quotes, so a script cannot be passed with -e; it
## would arrive as fragments. Every script is written to a file in user://
## and osascript is handed the path. Eight rotating files, so a few
## non-blocking calls in a row do not overwrite each other mid-read.

static var _n := 0
## One writer at a time, so no two calls take the same file. macOS runs the
## desk hand (desk_hand.gd) inline on the main thread, so today there is
## only ever one; the lock is for the day it gets a thread of its own.
static var _lock := Mutex.new()


static func _file(script: String) -> String:
	_lock.lock()
	_n = (_n + 1) % 8
	var path := "user://osa_%d.applescript" % _n
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(script)
	f.close()
	_lock.unlock()
	return ProjectSettings.globalize_path(path)


## Run and wait; the first line of output, stripped, or "" on failure.
static func run(script: String) -> String:
	var out := []
	if OS.execute("/usr/bin/osascript", [_file(script)], out, true) != 0 or out.is_empty():
		if not out.is_empty():
			push_warning("osascript: " + str(out[0]).strip_edges())
		return ""
	return str(out[0]).strip_edges()


## Fire and forget.
static func fire(script: String) -> void:
	OS.create_process("/usr/bin/osascript", [_file(script)])
