extends Node2D
## Debris passage (gear 8): Star Wars' asteroid field, Star Fox 64's
## Meteo, Outlaw Star's wrecks. Fragments come out of the vanishing
## point and stream past on every side while the bow weaves to thread
## them: dark hairline polygons that hide the stars behind them, tumbling
## slowly, in the tree's perspective. Cheap: a pool of COUNT fragments,
## each respawning far ahead when it passes, as often as the phase's
## density allows. Dissolves on any other shift.

const COUNT := 40
const Z_FAR := 12.0
const Z_NEAR := 0.15
## Depth per second per px/s of drive speed: at the passage's 24 a
## fragment crosses from far to near in about six seconds.
const RATE := 0.085
## Chance per second, per empty slot, of a new fragment at full density.
const SPAWN := 0.6
const DISSOLVE := 1.0

var _frags := []            # [angle, radius at z = 1, size at z = 1, z, rot, spin, shape, live]
var _vis := 0.0
var _density := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for i in COUNT:
		_frags.append([0.0, 0.0, 0.0, Z_FAR, 0.0, 0.0, PackedVector2Array(), false])


func _process(dt: float) -> void:
	var d = get_parent().drive
	if d == null:
		return
	var on: bool = d.gear == d.DEBRIS
	var want := 0.0
	if on:
		match d.phase:
			"ahead": want = smoothstep(0.0, 1.0, d.phase_t / d.DEBRIS_AHEAD)
			"thread": want = 1.0
			"clear": want = 1.0 - smoothstep(0.0, 1.0, d.phase_t / d.DEBRIS_CLEAR)
	_density = want
	_vis = move_toward(_vis, 1.0 if on else 0.0, dt / DISSOLVE)
	var dz: float = d.speed * RATE * dt
	for f in _frags:
		if f[7]:
			f[3] -= dz
			f[4] += f[5] * dt
			if f[3] < Z_NEAR:
				f[7] = false
		elif _vis > 0.0 and _rng.randf() < _density * SPAWN * dt:
			_spawn(f)
	visible = _vis > 0.0
	if visible:
		queue_redraw()


## A new fragment far ahead: a bearing and distance off the bow, a size,
## a tumble, and its own irregular outline.
func _spawn(f: Array) -> void:
	f[0] = _rng.randf_range(0.0, TAU)
	f[1] = _rng.randf_range(260.0, 900.0)
	f[2] = _rng.randf_range(30.0, 120.0)
	f[3] = Z_FAR
	f[4] = _rng.randf_range(0.0, TAU)
	f[5] = _rng.randf_range(-0.6, 0.6)
	var n := _rng.randi_range(5, 7)
	var shape := PackedVector2Array()
	for i in n:
		var ang := TAU * (float(i) + _rng.randf_range(-0.25, 0.25)) / n
		shape.append(Vector2.from_angle(ang) * _rng.randf_range(0.55, 1.0))
	f[6] = shape
	f[7] = true


func _draw() -> void:
	var vp: Vector2 = get_parent().vp()
	var c: Vector2 = get_parent().size * 0.5
	var ground := Palette.color("ground")
	var frame := Palette.color("frame")
	var light := Palette.color("light")
	var breathe := 0.85 + 0.15 * Palette.breath()
	for f in _frags:
		if not f[7]:
			continue
		var z: float = f[3]
		var p: Vector2 = vp + Vector2.from_angle(f[0]) * float(f[1]) / z
		var s: float = float(f[2]) / z
		if s < 1.5:
			continue
		var a := _mask(p, c) * _fade(z) * _vis
		if a <= 0.005:
			continue
		var shape: PackedVector2Array = f[6]
		draw_set_transform(p, f[4], Vector2.ONE * s)
		draw_colored_polygon(shape, Palette.dim(ground, 0.85 * a))
		var outline := PackedVector2Array(shape)
		outline.append(shape[0])
		draw_polyline(outline, Palette.dim(frame, 0.55 * a * breathe), 1.0 / s, true)
		# One lit facet, the side toward the light.
		draw_line(shape[0], shape[1], Palette.dim(light, 0.35 * a * breathe), 1.0 / s, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _fade(z: float) -> float:
	return smoothstep(Z_FAR, Z_FAR * 0.55, z) * smoothstep(Z_NEAR, 0.45, z)


## The middle stays clear for real windows.
static func _mask(p: Vector2, c: Vector2) -> float:
	return smoothstep(150.0, 400.0, p.distance_to(c))
