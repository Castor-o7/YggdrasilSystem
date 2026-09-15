extends Node
## Where the frame goes: CPU of this process (ps) and the renderer's own
## measured CPU and GPU time per frame, with a part of the scene hidden.
##   ... res://tools/profile.tscn -- --hide <what>   what: none | voidshader | hull | tree | setpieces
const WARMUP := 3.0
const SECONDS := 10.0
var _hide := "none"
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--hide" and i + 1 < args.size():
			_hide = args[i + 1]
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.persist = false
	add_child(main)
	var void_node: Control = main.get_node("Void")
	if _hide == "stopall" or _hide == "hideall":
		for c in main.get_children():
			c.process_mode = Node.PROCESS_MODE_DISABLED
			if _hide == "hideall" and c is CanvasItem:
				c.visible = false
		main.set_process(false)
	if _hide.begins_with("stop:"):
		# Stop a subtree's processing (it keeps drawing its last frame).
		var what := _hide.trim_prefix("stop:")
		var target: Node = main.get_node(what) if what != "Workspace" and what != "Pace" else get_node("/root/" + what)
		target.process_mode = Node.PROCESS_MODE_DISABLED
	OS.low_processor_usage_mode = false   # else a still frame is never drawn and frame_post_draw never fires
	main.set_process(false)   # main re-shows the hull and tree each frame for the stow fade
	if _hide == "blocks":
		for c in main.get_node("Hull").get_children():
			if c is Control:
				c.visible = false
	if _hide == "hullboth":
		main.get_node("Hull").visible = false
		main.get_node("Hull").process_mode = Node.PROCESS_MODE_DISABLED
	match _hide:
		"voidshader":
			void_node.material = null
			if void_node.get("_screen") != null:
				void_node.get("_screen").visible = false
		"hull":
			main.get_node("Hull").visible = false
		"tree":
			void_node.get_node("Tree").visible = false
		"setpieces":
			for n in ["Gate", "Warp", "Ether", "Limb", "Debris", "Station", "Ship"]:
				void_node.get_node(n).visible = false
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await get_tree().create_timer(WARMUP).timeout
	var cpu0 := _cpu_seconds()
	var t0 := Time.get_ticks_usec()
	var gpu := 0.0; var rcpu := 0.0; var n := 0; var objs := 0.0
	while (Time.get_ticks_usec() - t0) / 1e6 < SECONDS:
		await RenderingServer.frame_post_draw
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		rcpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		n += 1
	var wall := (Time.get_ticks_usec() - t0) / 1e6
	print("profile hide=%-10s fps %.1f  process cpu %.1f%%  items/frame %.0f" % [_hide, n / wall, (_cpu_seconds() - cpu0) / wall * 100.0, objs / n])
	get_tree().quit()
static func _cpu_seconds() -> float:
	var out := []
	OS.execute("/bin/ps", ["-o", "time=", "-p", str(OS.get_process_id())], out)
	if out.is_empty(): return 0.0
	var s := 0.0
	for p in str(out[0]).strip_edges().split(":"): s = s * 60.0 + float(p)
	return s
