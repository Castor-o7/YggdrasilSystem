extends Node
## Force the NERViewer block to fail and photograph the rabbits.
func _ready() -> void:
	OS.low_processor_usage_mode = false
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.persist = false
	add_child(main)
	await get_tree().process_frame
	var block: Control = null
	for c in main.get_node("Hull").get_children():
		if c is Control and c.title == "nerviewer":
			block = c
	block.failing = true
	block.get_node("Rabbits")._since = 130.0   # three rabbits at once, for the still
	var dir := ProjectSettings.globalize_path("res://../rabbits")
	DirAccess.make_dir_recursive_absolute(dir)
	var t := 0.0; var n := 0
	while t < 9.0:
		await RenderingServer.frame_post_draw
		t += get_process_delta_time()
		if t > 2.0 + n * 0.35 and n < 12:
			var img := get_viewport().get_texture().get_image()
			var r: Rect2 = block.get_global_rect()
			var crop := img.get_region(Rect2i(Vector2i(r.position), Vector2i(r.size)))
			crop.resize(int(r.size.x) * 3, int(r.size.y) * 3, Image.INTERPOLATE_NEAREST)
			crop.save_png("%s/rabbits_%02d.png" % [dir, n])
			n += 1
	print("rabbits_probe: wrote %d" % n)
	get_tree().quit()
