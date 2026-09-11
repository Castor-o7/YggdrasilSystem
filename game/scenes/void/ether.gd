extends Node2D
## Ether currents: Outlaw Star's space as streams the ship rides, the
## drive's gear 4. Hairline ribbons running the length of the flight,
## from far ahead at the vanishing point out past the rim. The current is
## continuous, never an object: along each ribbon a slow swell of light
## and the ribbon's own sway both run inward toward the bow at one speed,
## the stream carrying the ship. The ribbons are the palette's cool
## color, so the ether reads as its own substance beside the blue lattice
## and the white stars. Seeded, so the currents are the same each day.
## Dissolves on any other shift. Packets (dashes) were tried first and
## replaced 2026-09-10: a dash is a thing, a current is not.
##
## The squall (gear 9): the same currents turned rough. The storm rises,
## holds and clears with the drive's phases: the ribbons darken and
## thicken, their sway grows and a faster shiver rides it, the flow
## quickens, and hairline discharges arc between neighboring ribbons,
## dim and brief, never a flash. Settles back into calm ether.

const STREAMS := 10
const POINTS := 36
const Z_FAR := 1.0
const Z_NEAR := 0.12
## The current runs in w = 1 / z, which is proportional to a point's
## distance from the bow on screen, so a crest moves at a steady pace on
## screen instead of whipping at the rim. FLOW is w per second inward;
## on a ribbon 300 px from the bow at its far end that is 75 px/s.
const FLOW := 0.25
const TIDE_LEN := 2.2       # one swell of light, in w
const DISSOLVE := 1.2
const SEED := 11
const STORM_EASE := 1.5     # seconds for the storm to follow its phase
const ARC_LIFE := 0.3       # a discharge lasts this long
const ARC_SEGMENTS := 9

var _streams := []          # [angle, radius at z = 1, sway amplitude (px), sway wavelength (w), phase]
var _vis := 0.0
var _flow := 0.0
var _storm := 0.0
var _arcs := []             # [stream i, stream j, z, age, seed]
var _arc_t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in STREAMS:
		_streams.append([
			TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / STREAMS,
			rng.randf_range(150.0, 420.0),
			rng.randf_range(10.0, 26.0),
			rng.randf_range(1.2, 2.6),
			rng.randf_range(0.0, TAU),
		])


func _process(dt: float) -> void:
	var d = get_parent().drive
	if d == null:
		return
	var on: bool = d.gear == d.ETHER or d.gear == d.SQUALL
	_vis = move_toward(_vis, 1.0 if on else 0.0, dt / DISSOLVE)
	var want := 0.0
	if d.gear == d.SQUALL:
		match d.phase:
			"rise": want = smoothstep(0.0, 1.0, d.phase_t / d.SQUALL_RISE)
			"squall": want = 1.0
			"clear": want = 1.0 - smoothstep(0.0, 1.0, d.phase_t / d.SQUALL_CLEAR)
	_storm = move_toward(_storm, want, dt / STORM_EASE)
	_flow += FLOW * (1.0 + 1.5 * _storm) * dt
	# Discharges: born between neighbors while the storm is up, gone in a beat.
	for arc in _arcs:
		arc[3] += dt
	_arcs = _arcs.filter(func(arc): return arc[3] < ARC_LIFE)
	_arc_t -= dt
	if _storm > 0.4 and _arc_t <= 0.0:
		var i := _rng.randi_range(0, STREAMS - 1)
		_arcs.append([i, (i + 1) % STREAMS, _rng.randf_range(0.2, 0.7), 0.0, _rng.randf_range(0.0, 1000.0)])
		_arc_t = _rng.randf_range(0.25, 1.0) / _storm
	visible = _vis > 0.0
	if visible:
		queue_redraw()


## A point on a stream at depth z, projected. The sway's amplitude is in
## screen px, so a ribbon sways the same near and far.
func _at(st: Array, z: float, vp: Vector2) -> Vector2:
	var base: Vector2 = Vector2.from_angle(st[0]) * float(st[1])
	var normal: Vector2 = Vector2.from_angle(st[0]).orthogonal()
	var w := 1.0 / z
	var sway: float = float(st[2]) * (1.0 + 2.5 * _storm) * z * sin(TAU * (w + _flow) / float(st[3]) + float(st[4]))
	# The storm's shiver: a faster, smaller wave riding the sway.
	sway += 5.0 * _storm * z * sin(TAU * (w * 1.2 + _flow * 2.0) + float(st[4]) * 3.0)
	return vp + (base + normal * sway) / z


## The swell of light at depth z, 0..1, running inward with the sway.
func _tide(st: Array, z: float) -> float:
	var s := 0.5 + 0.5 * sin(TAU * (1.0 / z + _flow) / TIDE_LEN + float(st[4]) * 1.7)
	return s * s


func _draw() -> void:
	var vp: Vector2 = get_parent().vp()
	var c: Vector2 = get_parent().size * 0.5
	var cool := Palette.color("cool")
	var light := Palette.color("light")
	var breathe := 0.85 + 0.15 * Palette.breath()
	var halo_w := 3.5 + 4.0 * _storm
	var line_w := 1.0 + 0.8 * _storm
	for st in _streams:
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		var halo := PackedColorArray()
		for i in POINTS + 1:
			# Geometric steps in depth, so the points space evenly on screen.
			var z := Z_FAR * pow(Z_NEAR / Z_FAR, float(i) / POINTS)
			var p := _at(st, z, vp)
			var a := _mask(p, c) * _fade(z) * _vis * breathe
			var tide := _tide(st, z)
			var col := cool.lerp(light, 0.45 * tide * (1.0 - 0.5 * _storm)).darkened(0.35 * _storm)
			pts.append(p)
			cols.append(Palette.dim(col, (0.22 + 0.5 * tide) * a * (1.0 - 0.15 * _storm)))
			halo.append(Palette.dim(col, (0.03 + 0.09 * tide) * a * (1.0 + 0.6 * _storm)))
		draw_polyline_colors(pts, halo, halo_w, true)
		draw_polyline_colors(pts, cols, line_w, true)
	# The discharges: a jagged hairline between two ribbons at one depth,
	# fading over its short life.
	var arc_col := cool.lerp(light, 0.5)
	for arc in _arcs:
		var z: float = arc[2]
		var pa := _at(_streams[arc[0]], z, vp)
		var pb := _at(_streams[arc[1]], z, vp)
		var life: float = 1.0 - arc[3] / ARC_LIFE
		var a := 0.55 * life * _storm * _vis * _mask((pa + pb) * 0.5, c) * _fade(z)
		if a <= 0.005:
			continue
		var normal := (pb - pa).orthogonal().normalized()
		var reach := pa.distance_to(pb) * 0.08
		var pts := PackedVector2Array()
		for k in ARC_SEGMENTS + 1:
			var u := float(k) / ARC_SEGMENTS
			var jitter := 0.0
			if k > 0 and k < ARC_SEGMENTS:
				jitter = (fmod(sin(float(arc[4]) + k * 12.9898) * 43758.5453, 1.0) - 0.5) * 2.0 * reach
			pts.append(pa.lerp(pb, u) + normal * jitter)
		draw_polyline(pts, Palette.dim(arc_col, a * 0.25), 3.0, true)
		draw_polyline(pts, Palette.dim(arc_col, a), 1.0, true)


static func _fade(z: float) -> float:
	return smoothstep(Z_FAR, 0.85, z) * smoothstep(Z_NEAR, 0.2, z)


## The middle stays clear for real windows; the currents live at the rim.
static func _mask(p: Vector2, c: Vector2) -> float:
	return smoothstep(170.0, 430.0, p.distance_to(c))
