extends Node
## Walks every gear under the current engine, windowed (about four
## minutes): a still every few seconds of each phase into gearwalk/
## beside the project, and at every phase boundary the frame before and
## the frame after, so a cut shows up as a big diff between the pair.
##   Godot --path game res://tools/gearwalk.tscn
const ORDER := [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
const STATE_HOLD := 8.0
const STILL_EVERY := 3.0
var _dir := ""
var _main: Node
var _drive
var _prev: Image
var _prev_key := ""
func _ready() -> void:
	OS.low_processor_usage_mode = false
	_main = load("res://scenes/main.tscn").instantiate()
	_main.persist = false
	add_child(_main)
	_drive = _main.get_node("Void/Drive")
	_dir = ProjectSettings.globalize_path("res://../gearwalk")
	DirAccess.make_dir_recursive_absolute(_dir)
	await get_tree().create_timer(2.0).timeout
	for g in ORDER:
		_drive.shift(g)
		var name: String = _drive.GEARS[g]["name"].replace(" ", "_")
		var t := 0.0; var since := STILL_EVERY; var key := ""
		while true:
			await RenderingServer.frame_post_draw
			var dt := get_process_delta_time()
			t += dt; since += dt
			var now_key := "%s_%s" % [name, _drive.phase if _drive.phase != "" else "state"]
			var img := get_viewport().get_texture().get_image()
			if key != "" and now_key != key and _prev != null:
				_prev.save_png("%s/%s_cut_before.png" % [_dir, key])
				img.save_png("%s/%s_cut_after.png" % [_dir, now_key])
				since = STILL_EVERY
			if since >= STILL_EVERY:
				since = 0.0
				img.save_png("%s/%s_%03d.png" % [_dir, now_key, int(t)])
			_prev = img; key = now_key
			var done := false
			if g <= 5:
				done = t >= STATE_HOLD
			else:
				done = not _drive.is_sequence() and t > 1.0
			if done:
				break
		print("gearwalk: %s done at %.0f s (settled to %s)" % [name, t, _drive.gear_name()])
	print("gearwalk: complete")
	get_tree().quit()
