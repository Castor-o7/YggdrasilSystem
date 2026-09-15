extends Node
## Eight simulated hours of Voyage, headless, a second at a time: the
## grammar's promises checked against what it actually chose.
##   Godot --path game --headless res://tools/voyage_sim.tscn
func _ready() -> void:
	var void_scene: Node = load("res://scenes/void/void.tscn").instantiate()
	add_child(void_scene)
	var drive = void_scene.get_node("Drive")
	var voyage = void_scene.get_node("Voyage")
	void_scene.set_process(false)   # no shader feed needed
	voyage.start()
	var legs: Array = []; var passages: Array = []; var ports: Array = []; var squalls: Array = []
	var last_gear: int = drive.gear; var t := 0.0
	var leg_started := 0.0; var cur_leg := 0
	var last_pass := 0
	var log: Array = []
	for i in 8 * 3600:
		t += 1.0
		drive._process(1.0)
		voyage._process(1.0)
		if drive.gear != last_gear:
			log.append([t, drive.gear, drive.phase])
			last_gear = drive.gear
	# Fold the shifts into the grammar's terms.
	var names: Dictionary = drive.GEARS
	var prev_state := 0; var prev_passage := 0; var same_state := 0; var same_passage := 0
	var state_hold: Array = []; var hold_start := 0.0; var hold_gear := 0
	var under_way_start := 0.0; var port_gaps: Array = []; var berths: Array = []
	var berth_start := 0.0
	for e in log:
		var g: int = e[1]
		if g <= 5:
			if hold_gear != 0 and hold_gear <= 5:
				state_hold.append(e[0] - hold_start)
			if g != drive.IDLE or not drive.berthed:
				if g == prev_state: same_state += 1
				prev_state = g
			hold_gear = g; hold_start = e[0]
		elif g == drive.SQUALL:
			squalls.append(e[0])
		elif g == drive.ARRIVE:
			ports.append(e[0]); port_gaps.append((e[0] - under_way_start) / 60.0)
		elif g == drive.DEPART:
			under_way_start = e[0]
		elif g >= drive.GATE and g != drive.ARRIVE and g != drive.DEPART:
			passages.append(g)
			if g == prev_passage: same_passage += 1
			prev_passage = g
	var counts := {}
	for g in passages: counts[names[g]["name"]] = counts.get(names[g]["name"], 0) + 1
	var state_counts := {}
	for e in log:
		if e[1] <= 5: state_counts[names[e[1]]["name"]] = state_counts.get(names[e[1]]["name"], 0) + 1
	print("sim: %d shifts in 8 h; legs by state %s; passages %s" % [log.size(), state_counts, counts])
	print("sim: same state twice running: %d; same passage twice running: %d" % [same_state, same_passage])
	print("sim: port calls %d at minutes-under-way %s" % [ports.size(), port_gaps.map(func(m): return int(m))])
	print("sim: squalls %d" % squalls.size())
	var holds := state_hold.map(func(s): return int(s / 60.0))
	print("sim: leg holds (min, first 20) %s" % [holds.slice(0, 20)])
	# Switched on in port: the ship must cast off, not skip the port.
	voyage.stop()
	drive.shift(drive.ARRIVE)
	for i in 60:
		drive._process(1.0)
	voyage.start()
	print("sim: voyage on from a berth -> %s (%s)" % [drive.gear_name(), "casts off" if drive.gear == drive.DEPART else "SKIPS THE PORT"])
	get_tree().quit()
