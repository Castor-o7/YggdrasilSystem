extends Node
## NERViewer is its own application; this docks it. The block's inner
## disc is measured on screen and written to NERViewer's user://dock.cfg,
## which NERViewer polls; while the file exists it shows its sigil alone,
## filling that rect. If NERViewer is not running when the workspace
## first reports, it is launched once. On exit the file is removed and
## NERViewer goes back to being itself.

const BUNDLE_ID := "edu.pdx.josh.nerviewer"
const APP_CANDIDATES := [
	"res://../../NERViewer/dist/NERViewer.app",
	"/Applications/NERViewer.app",
]
const POLL := 0.5

var block: SigilBlock
var _timer := 0.0
var _last_rect := Rect2i()
var _launched := false
var _dock_path := ""


func _ready() -> void:
	# Sibling of this project's own user dir.
	_dock_path = OS.get_user_data_dir().get_base_dir().path_join("NERViewer").path_join("dock.cfg")
	Workspace.changed.connect(_maybe_launch)


func _process(dt: float) -> void:
	_timer -= dt
	if _timer > 0.0 or block == null:
		return
	_timer = POLL
	block.bare = running()
	var rect := _screen_rect()
	if rect != _last_rect:
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
	cfg.set_value("dock", "by", "MagitechDesk")
	cfg.set_value("dock", "pid", OS.get_process_id())  # so a crash cannot leave NERViewer stranded
	if cfg.save(_dock_path) != OK:
		push_warning("could not write " + _dock_path)


func running() -> bool:
	var app = Workspace.apps.get(BUNDLE_ID)
	return app != null and app.alive


func _maybe_launch() -> void:
	if _launched or Workspace.source_name != "yggapps" or Workspace.apps.is_empty():
		return
	_launched = true  # once per session; if Josh quits it, it stays quit
	if running():
		return
	for c in APP_CANDIDATES:
		var path: String = ProjectSettings.globalize_path(c) if c.begins_with("res://") else c
		if DirAccess.dir_exists_absolute(path):
			OS.create_process("/usr/bin/open", [path])
			print("NERViewer dock: launched ", path)
			return
	print("NERViewer dock: app not found; the slot waits")


func release() -> void:
	if _dock_path != "" and FileAccess.file_exists(_dock_path):
		DirAccess.remove_absolute(_dock_path)


func _exit_tree() -> void:
	release()
