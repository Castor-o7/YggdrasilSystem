extends Node
## Renders the void and the tree at a settled moment to screenshots/ beside the project:
## void_ground.png on the opaque ground, void_overlay.png over the fake
## wallpaper (what the desktop would show). Screen capture is not granted
## to the terminal on this machine, so this is how the look gets judged.
##
## Run: /Applications/Godot.app/Contents/MacOS/Godot --path game res://tools/shots.tscn

const MOMENT := 40.0


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.persist = false          # neither load nor save Josh's prefs
	add_child(main)
	main.get_node("Void").time_offset = MOMENT
	var dir := ProjectSettings.globalize_path("res://../screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var written: Array[String] = []
	var tree: Node2D = main.get_node("Void/Tree")
	# First, if the helper is running, the real workspace: void_live.png.
	if Workspace.source_name == "yggapps":
		await get_tree().create_timer(3.0).timeout
		if not Workspace.apps.is_empty():
			for _i in 60:
				tree._sync(0.1)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var live := "%s/void_live.png" % dir
			if _frame().save_png(live) == OK:
				written.append(live)
	# Then the scripted day, twenty seconds in: seven apps up, Mail still open,
	# Godot frontmost. Branches are grown in by hand since no time passes.
	Workspace.use_synthetic()
	Workspace.apps.clear()      # no ghosts of the real apps in the scripted frame
	tree._branches.clear()
	Workspace.seek(20.0)
	await get_tree().process_frame
	for _i in 60:
		tree._sync(0.1)
	await get_tree().process_frame
	for shot in [["void_ground", false], ["void_overlay", true]]:
		main.set_fake_wallpaper(shot[1])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var path := "%s/%s.png" % [dir, shot[0]]
		if _frame().save_png(path) == OK:
			written.append(path)
		else:
			push_error("could not save " + path)
	print("shots: wrote %d files" % written.size())
	for p in written:
		print("  ", p)
	get_tree().quit(0)


## The frame as the screen shows it. The float 2D viewport (HDR output,
## 2026-09-15) renders in linear light and reads back that way; the PNG
## wants it encoded, or every still comes out dark.
func _frame() -> Image:
	var img := get_viewport().get_texture().get_image()
	if ProjectSettings.get_setting("rendering/viewport/hdr_2d", false):
		# Per pixel in float: Image.linear_to_srgb is 8-bit only, and
		# quantizing linear light first would crush the darks this piece
		# lives in. A few seconds a frame; this is a tool.
		for y in img.get_height():
			for x in img.get_width():
				img.set_pixel(x, y, img.get_pixel(x, y).linear_to_srgb())
	return img
