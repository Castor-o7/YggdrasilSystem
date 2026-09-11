extends Node2D
## The great ship (gear 12, the equals key): Bebop's colony liners,
## Yamato, Macross. A hull far bigger than ours overtakes from behind on
## a parallel course, below and to one side, slides past toward the
## vanishing point, and dwindles into it. Our course and speed never
## change; the scale is the show. A hairline silhouette in the tree's
## perspective: spine, keel and deck lines, a bridge tower, fins at the
## stern, windows on the breath, gold running lights, the engines' glow.
## Dissolves on any other shift.

const LENGTH := 6.0             # in depth units
const LATERAL := Vector2(300.0, 200.0)   # px at z = 1; x is mirrored by side
const Z_START := 0.25           # the bow's depth when the sequence starts
const Z_RATE := 0.3             # depth per second it gains on us
## Once ahead it pulls away: extra depth per second squared past then.
const Z_PULL := 0.15
const STEPS := 28
const DISSOLVE := 1.0

var _vis := 0.0
var _head := Z_START
var _side := 1


func _process(dt: float) -> void:
	var d = get_parent().drive
	if d == null:
		return
	var on: bool = d.gear == d.SHIP
	if on:
		var t: float = d.ship_t()
		var ahead: float = maxf(t - d.SHIP_OVERTAKE - d.SHIP_PASS, 0.0)
		_head = Z_START + Z_RATE * t + Z_PULL * ahead * ahead
		_side = d.ship_side
	_vis = move_toward(_vis, 1.0 if on else 0.0, dt / DISSOLVE)
	visible = _vis > 0.0
	if visible:
		queue_redraw()


## A point of the hull at depth z, offset `lat` px (at z = 1) from its
## spine, projected.
func _at(z: float, lat: Vector2, vp: Vector2) -> Vector2:
	return vp + (Vector2(LATERAL.x * _side, LATERAL.y) + Vector2(lat.x * _side, lat.y)) / z


static func _fade(z: float) -> float:
	return smoothstep(0.12, 0.5, z) * smoothstep(22.0, 12.0, z)


## A hairline along the hull from depth z0 to z1 at a lateral offset.
func _run(z0: float, z1: float, lat: Vector2, col: Color, alpha: float, width: float, vp: Vector2, c: Vector2) -> void:
	var lo := maxf(z0, 0.12)
	if z1 <= lo:
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in STEPS + 1:
		var z := lerpf(lo, z1, float(i) / STEPS)
		var p := _at(z, lat, vp)
		pts.append(p)
		cols.append(Palette.dim(col, alpha * _fade(z) * _mask(p, c) * _vis))
	draw_polyline_colors(pts, cols, width, true)


func _draw() -> void:
	var vp: Vector2 = get_parent().vp()
	var c: Vector2 = get_parent().size * 0.5
	var frame := Palette.color("frame")
	var light := Palette.color("light")
	var gold := Palette.color("core")
	var breathe := 0.85 + 0.15 * Palette.breath()
	var head := _head
	var tail := head - LENGTH
	var w := clampf(1.6 / sqrt(maxf(head - LENGTH * 0.5, 0.3)), 0.8, 1.8)
	# The hull: spine, keel, and the deck line over the middle.
	_run(tail, head, Vector2.ZERO, light, 0.55, w, vp, c)
	_run(tail, head - LENGTH * 0.06, Vector2(0.0, 44.0), frame, 0.3, w * 0.8, vp, c)
	_run(tail + LENGTH * 0.12, tail + LENGTH * 0.86, Vector2(0.0, -26.0), frame, 0.3, w * 0.8, vp, c)
	# Ribs between spine and keel, every so often.
	for i in 12:
		var z := tail + LENGTH * (0.08 + 0.07 * i)
		if z < 0.12:
			continue
		var a := 0.22 * _fade(z) * _vis
		draw_line(_at(z, Vector2.ZERO, vp), _at(z, Vector2(0.0, 44.0), vp), Palette.dim(frame, a * _mask(_at(z, Vector2.ZERO, vp), c)), w * 0.7, true)
	# The bridge tower, aft of the middle.
	var t0 := tail + LENGTH * 0.66
	var t1 := tail + LENGTH * 0.76
	if t0 > 0.12:
		var at := 0.45 * _fade(t0) * _vis * _mask(_at(t0, Vector2.ZERO, vp), c)
		var tower := PackedVector2Array([
			_at(t0, Vector2(0.0, -26.0), vp), _at(t0, Vector2(0.0, -96.0), vp),
			_at(t1, Vector2(0.0, -96.0), vp), _at(t1, Vector2(0.0, -26.0), vp)])
		draw_polyline(tower, Palette.dim(frame, at), w * 0.9, true)
		draw_circle(_at(t0 + (t1 - t0) * 0.5, Vector2(0.0, -96.0), vp), 2.0, Palette.dim(gold, 0.9 * at * breathe))
	# Fins at the stern.
	var f0 := tail + LENGTH * 0.03
	var f1 := tail + LENGTH * 0.16
	if f0 > 0.12:
		var af := 0.35 * _fade(f0) * _vis * _mask(_at(f0, Vector2.ZERO, vp), c)
		for lat in [Vector2(0.0, -70.0), Vector2(0.0, 100.0)]:
			draw_line(_at(f0, lat, vp), _at(f1, Vector2(0.0, lat.y * 0.35), vp), Palette.dim(frame, af), w * 0.8, true)
			draw_line(_at(f0, lat, vp), _at(f0, Vector2(0.0, lat.y * 0.35), vp), Palette.dim(frame, af), w * 0.8, true)
	# Windows along the deck line, and running lights bow and stern.
	var n := 22
	for i in n:
		var z := tail + LENGTH * (0.14 + 0.7 * float(i) / (n - 1))
		if z < 0.12:
			continue
		var p := _at(z, Vector2(0.0, -12.0), vp)
		draw_circle(p, 1.0, Palette.dim(light, 0.5 * _fade(z) * _mask(p, c) * _vis * breathe))
	for z in [head - 0.02, tail + 0.02]:
		if z > 0.12:
			var p := _at(z, Vector2.ZERO, vp)
			draw_circle(p, 2.2, Palette.dim(gold, 0.9 * _fade(z) * _mask(p, c) * _vis * breathe))
	# The engines: a soft gold at the stern.
	if tail > 0.12:
		var p := _at(tail, Vector2(0.0, 22.0), vp)
		var ae := _fade(tail) * _mask(p, c) * _vis * breathe
		draw_circle(p, 3.0, Palette.dim(gold, 0.6 * ae))
		draw_circle(p, 9.0, Palette.dim(gold, 0.1 * ae))


## The middle is kept quieter for real windows, not cut: a parallel
## course converges on the vanishing point, and the hull must reach it.
static func _mask(p: Vector2, c: Vector2) -> float:
	return lerpf(0.4, 1.0, smoothstep(120.0, 380.0, p.distance_to(c)))
