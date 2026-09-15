extends Node
## NERViewer is its own application; this docks it. The block's inner
## disc is measured on screen and written to NERViewer's user://dock.cfg,
## which NERViewer polls; while the file exists it shows its sigil alone,
## filling that rect. If NERViewer is not running when the workspace
## first reports, it is launched once. On exit the file is removed and
## NERViewer goes back to being itself.

const Paths := preload("res://scripts/paths.gd")
const BUNDLE_ID := "edu.pdx.josh.nerviewer"
## The sibling repo's built app first (found from the editor or from an
## exported cockpit alike), then an installed copy.
const APP_SIBLING := "NERViewer/dist/NERViewer.app"
const APP_INSTALLED := "/Applications/NERViewer.app"
## Wait this long after the workspace starts reporting before launching:
## at login NERViewer's own launch agent may still be coming up.
const LAUNCH_GRACE := 5.0
## If NERViewer has a launch agent, launchd owns it: kickstart is
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
	if running() and _hidden != _want_hidden:
		_hidden = _want_hidden
		Osa.fire(HIDE % [BUNDLE_ID, "true" if _hidden else "false"])
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
	cfg.set_value("dock", "by", "Yggdrasil System")
	cfg.set_value("dock", "pid", OS.get_process_id())  # so a crash cannot leave NERViewer stranded
	if cfg.save(_dock_path) != OK:
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


static func _uid() -> int:
	var out := []
	OS.execute("/usr/bin/id", ["-u"], out)
	return int(str(out[0]).strip_edges()) if not out.is_empty() else 501


func set_hidden(on: bool) -> void:
	_want_hidden = on


func release() -> void:
	if _hidden:
		_hidden = false
		Osa.fire(HIDE % [BUNDLE_ID, "false"])
	if _dock_path != "" and FileAccess.file_exists(_dock_path):
		DirAccess.remove_absolute(_dock_path)


func _exit_tree() -> void:
	release()
