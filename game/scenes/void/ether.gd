extends Node2D
## Ether currents: Outlaw Star's space as streams the ship rides, the
## drive's gear 4. Hairline ribbons running the length of the flight,
## from far ahead at the vanishing point out past the rim, each a slow
## wave that streams past with the void, with pale (one in three gold)
## packets running inward along them: the current carrying the ship.
## Seeded, so the currents are the same each day. Dissolves on any other
## shift.

const STREAMS := 10
const POINTS := 36
const PACKETS := 3
const Z_FAR := 1.0
const Z_NEAR := 0.12
const FLOW := 0.05          # depth per second the packets run inward
const PACKET_DZ := 0.012    # a packet's length in depth, at z = 1
const DISSOLVE := 1.2
const SEED := 11

var _streams := []          # [angle, radius at z = 1, amplitude, wavelength, phase, gold]
var _vis := 0.0
var _travel := 0.0
var _flow := 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in STREAMS:
		_streams.append([
			TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / STREAMS,
			rng.randf_range(150.0, 420.0),
			rng.randf_range(10.0, 26.0),
			rng.randf_range(0.25, 0.6),
			rng.randf_range(0.0, TAU),
			i % 3 == 0,
		])


func _process(dt: float) -> void:
	var d = get_parent().drive
	if d == null:
		return
	var on: bool = d.gear == d.ETHER
	_vis = move_toward(_vis, 1.0 if on else 0.0, dt / DISSOLVE)
	_travel += get_parent().rate() * dt
	_flow += FLOW * dt
	visible = _vis > 0.0
	if visible:
		queue_redraw()


## A point on a stream at depth z, projected.
func _at(st: Array, z: float, vp: Vector2) -> Vector2:
	var base: Vector2 = Vector2.from_angle(st[0]) * float(st[1])
	var normal: Vector2 = Vector2.from_angle(st[0]).orthogonal()
	# The wave's amplitude is in screen px, so a ribbon sways the same near and far.
	var wave: float = st[2] * z * sin(TAU * (z + _travel) / st[3] + st[4])
	return vp + (base + normal * wave) / z


func _draw() -> void:
	var vp: Vector2 = get_parent().vp()
	var c: Vector2 = get_parent().size * 0.5
	var frame := Palette.color("frame")
	var light := Palette.color("light")
	var gold := Palette.color("core")
	var breathe := 0.85 + 0.15 * Palette.breath()
	var span := Z_FAR - Z_NEAR
	for st in _streams:
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		var halo := PackedColorArray()
		for i in POINTS + 1:
			# Geometric steps in depth, so the points space evenly on screen.
			var z := Z_FAR * pow(Z_NEAR / Z_FAR, float(i) / POINTS)
			var p := _at(st, z, vp)
			var a := _mask(p, c) * _fade(z) * _vis * breathe
			pts.append(p)
			cols.append(Palette.dim(frame, 0.3 * a))
			halo.append(Palette.dim(frame, 0.05 * a))
		draw_polyline_colors(pts, halo, 3.0, true)
		draw_polyline_colors(pts, cols, 1.0, true)
		# Packets: short bright runs along the ribbon, running inward.
		for k in PACKETS:
			var z0 := Z_NEAR + fposmod(k * span / PACKETS + st[4] * 0.1 + _flow, span)
			var run := PackedVector2Array()
			for j in 6:
				run.append(_at(st, z0 + (j - 2.5) * PACKET_DZ * z0, vp))
			var a := _mask(run[3], c) * _fade(z0) * _vis * breathe
			var col: Color = gold if st[5] else light
			draw_polyline(run, Palette.dim(col, 0.2 * a), 4.0, true)
			draw_polyline(run, Palette.dim(col, 0.9 * a), 1.4, true)


static func _fade(z: float) -> float:
	return smoothstep(Z_FAR, 0.85, z) * smoothstep(Z_NEAR, 0.2, z)


## The middle stays clear for real windows; the currents live at the rim.
static func _mask(p: Vector2, c: Vector2) -> float:
	return smoothstep(170.0, 430.0, p.distance_to(c))
