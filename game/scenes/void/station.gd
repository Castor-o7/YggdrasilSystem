extends Node2D
## The station, for arrival (gear 0): the port the voyage ends at. A
## point of light on its own bearing resolves into structure as the ship
## closes; the bow bends onto that bearing, the docking arm comes down to
## the bow, and as the ship stops the arm's guide lights come up one by
## one, hub to cradle: the port has received us. At idle, berthed, it
## holds ahead with the stars still, until the next shift. Kin to the
## hull's own instruments: hairline rings with dashes, a turning inner
## ring, two long spars with windows, gold running lights that ride the
## breath. Dissolves on any shift away.
##
## Departure (the minus key, from a berth only) runs it backward and
## then some: the guide lights go down cradle to hub, and as the drive
## opens the station grows and slides up out of the frame, passed
## beneath. Bebop's leaving-port shot.

const DISSOLVE := 1.2
const Z_FAR := 24.0
const Z_MID := 6.0
const SCALE := 0.8            # its size at berth
const SPIN := 0.05
const ARM := 150.0            # the docking arm, hub to cradle, station units
const GUIDES := 5             # guide lights along the arm, then the cradle pair
const DEPART_Z := 0.5         # how close it looms as we pass beneath it
const DEPART_LIFT := 700.0    # how far up the frame it slides, px

var _vis := 0.0
var _z := Z_FAR
var _spin := 0.0
var _dock := 0.0              # guide lights lit, 0..1
var _lift := 0.0              # departure: how far it has slid up


func _process(dt: float) -> void:
	var d = get_parent().drive
	if d == null:
		return
	var on: bool = d.gear == d.ARRIVE or d.gear == d.DEPART or (d.gear == d.IDLE and d.berthed)
	if d.gear == d.DEPART:
		match d.phase:
			"cast":
				_z = 1.0
				_lift = 0.0
				_dock = 1.0 - clampf(d.phase_t / d.DEPART_CAST, 0.0, 1.0)
			"underway":
				var u := smoothstep(0.0, 1.0, d.phase_t / d.DEPART_UNDERWAY)
				_z = lerpf(1.0, DEPART_Z, u)
				_lift = DEPART_LIFT * u
				_dock = 0.0
			"open":
				_z = DEPART_Z
				_lift = DEPART_LIFT
	elif d.gear == d.ARRIVE:
		_lift = 0.0
		match d.phase:
			"sighting":
				_z = lerpf(Z_FAR, Z_MID, smoothstep(0.0, 1.0, d.phase_t / d.ARRIVE_SIGHTING))
				_dock = 0.0
			"approach":
				_z = lerpf(Z_MID, 1.0, smoothstep(0.0, 1.0, d.phase_t / d.ARRIVE_APPROACH))
				_dock = 0.0
			"berth":
				_z = 1.0
				_dock = clampf(d.phase_t / d.ARRIVE_BERTH, 0.0, 1.0)
	elif on:
		_z = 1.0
		_dock = 1.0
		_lift = 0.0
	_vis = move_toward(_vis, 1.0 if on else 0.0, dt / DISSOLVE)
	_spin += SPIN * dt
	visible = _vis > 0.0
	if visible:
		queue_redraw()


## Where the port lies: on its own bearing, where the bow's vanishing
## point will be once the bow has bent onto it.
func _anchor() -> Vector2:
	var void_layer = get_parent()
	return void_layer.size * 0.5 + Vector2.from_angle(void_layer.drive.berth_course) * void_layer.VP_RADIUS


func _draw() -> void:
	var cradle := _anchor() - Vector2(0.0, _lift)
	var s := SCALE / _z
	var frame := Palette.color("frame")
	var light := Palette.color("light")
	var gold := Palette.color("core")
	var breathe := 0.85 + 0.15 * Palette.breath()
	# Far off it is one light; the structure resolves as it closes.
	var point := (1.0 - smoothstep(Z_MID * 1.5, Z_MID * 0.4, _z)) * smoothstep(Z_FAR, Z_FAR * 0.7, _z) * _vis
	var a := smoothstep(Z_MID * 1.5, Z_MID * 0.4, _z) * _vis
	if point > 0.0:
		draw_circle(cradle, 1.6, Palette.dim(gold, 0.9 * point * breathe))
		draw_circle(cradle, 5.0, Palette.dim(gold, 0.12 * point))
	if a <= 0.0:
		return
	var w := lerpf(0.7, 1.3, s)
	# The hub sits up the arm from the cradle; the cradle is at the bow.
	draw_set_transform(cradle + Vector2(0.0, -ARM) * s, 0.0, Vector2.ONE * s)
	# The hub and its spokes.
	draw_arc(Vector2.ZERO, 54.0, 0.0, TAU, 64, Palette.dim(frame, 0.5 * a * breathe), w, true)
	for i in 6:
		var dir := Vector2.from_angle(i * TAU / 6.0)
		draw_line(dir * 54.0, dir * 88.0, Palette.dim(frame, 0.35 * a), w, true)
	# The turning ring.
	var step := TAU / 18.0
	for i in 18:
		var a0 := _spin + i * step
		draw_arc(Vector2.ZERO, 90.0, a0, a0 + step * 0.5, 8, Palette.dim(light, 0.4 * a * breathe), w, true)
	# The outer ring with its dashes and four running lights.
	draw_arc(Vector2.ZERO, 240.0, 0.0, TAU, 160, Palette.dim(frame, 0.3 * a * breathe), w, true)
	step = TAU / 24.0
	for i in 24:
		var a0 := -_spin * 0.5 + i * step
		draw_arc(Vector2.ZERO, 252.0, a0, a0 + step * 0.4, 8, Palette.dim(frame, 0.28 * a), w * 0.8, true)
	for i in 4:
		var p := Vector2.from_angle(i * TAU / 4.0 + PI * 0.25) * 240.0
		draw_circle(p, 2.2, Palette.dim(gold, 0.85 * a * breathe))
	# The spars and their windows.
	draw_line(Vector2(-430.0, 0.0), Vector2(430.0, 0.0), Palette.dim(light, 0.5 * a), w, true)
	draw_line(Vector2(-430.0, 6.0), Vector2(430.0, 6.0), Palette.dim(frame, 0.2 * a), w * 0.8, true)
	for x in range(-420, 421, 30):
		if absf(x) < 250.0:
			continue
		draw_line(Vector2(x, 0.0), Vector2(x, -4.0), Palette.dim(light, 0.3 * a * breathe), w * 0.8, true)
	for sx in [-1.0, 1.0]:
		draw_circle(Vector2(sx * 430.0, 0.0), 2.0, Palette.dim(gold, 0.85 * a * breathe))
	# The docking arm, hub to cradle, with its guide lights and the cradle's
	# brackets around the bow. The lights come up in order as we berth.
	draw_line(Vector2(0.0, 54.0), Vector2(0.0, ARM - 18.0), Palette.dim(frame, 0.4 * a), w, true)
	draw_line(Vector2(-4.0, 54.0), Vector2(-4.0, ARM - 18.0), Palette.dim(frame, 0.15 * a), w * 0.8, true)
	for sx in [-1.0, 1.0]:
		var b := Vector2(sx * 30.0, ARM - 14.0)
		draw_line(Vector2(0.0, ARM - 18.0), b, Palette.dim(frame, 0.4 * a), w, true)
		draw_line(b, Vector2(sx * 24.0, ARM + 6.0), Palette.dim(frame, 0.4 * a), w, true)
	var slots := GUIDES + 1
	for i in GUIDES:
		var lit := smoothstep(float(i) / slots, float(i + 1) / slots, _dock)
		var y := lerpf(64.0, ARM - 30.0, float(i) / (GUIDES - 1))
		draw_circle(Vector2(0.0, y), 1.8, Palette.dim(gold, 0.85 * a * breathe * lit))
	var cradle_lit := smoothstep(float(GUIDES) / slots, 1.0, _dock)
	for sx in [-1.0, 1.0]:
		draw_circle(Vector2(sx * 30.0, ARM - 14.0), 2.2, Palette.dim(gold, 0.9 * a * breathe * cradle_lit))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
