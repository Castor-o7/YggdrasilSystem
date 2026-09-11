extends Node2D
## Ruins: Panzer Dragoon's ancient age drifting past, the drive's gear 5.
## Wireframe fragments (an arch, a broken ring, a lattice shard, an
## obelisk, a sigil shard) appear far ahead, off the bow, and fly out past
## the rim as the ship closes on them, growing as they come, tumbling
## slowly. Hairlines in frame color with a gold node where something
## still burns. Dissolves on any other shift.

const COUNT := 8
const DISSOLVE := 1.2
const Z_FAR := 1.0
const Z_NEAR := 0.12
const OFF_MIN := 120.0        # lateral offset from the bow at z = 1, px
const OFF_MAX := 400.0
const SCALE := 0.4            # a fragment's scale at z = 1
const TURN := 0.03            # radians per second a fragment tumbles

class Ruin:
	var lateral := Vector2.ZERO   # offset from the bow on the far plane
	var z := 1.0
	var kind := 0
	var rot := 0.0
	var spin := 0.0

var _ruins: Array[Ruin] = []
var _rng := RandomNumberGenerator.new()
var _vis := 0.0


func _ready() -> void:
	_rng.seed = 23
	for i in COUNT:
		var r := Ruin.new()
		_respawn(r, lerpf(0.3, 1.6, float(i) / COUNT))
		_ruins.append(r)


func _respawn(r: Ruin, z: float) -> void:
	r.z = z
	r.lateral = Vector2.from_angle(_rng.randf_range(0.0, TAU)) * _rng.randf_range(OFF_MIN, OFF_MAX)
	r.kind = _rng.randi_range(0, 4)
	r.rot = _rng.randf_range(-0.5, 0.5)
	r.spin = _rng.randf_range(-TURN, TURN)


func _process(dt: float) -> void:
	var d = get_parent().drive
	if d == null:
		return
	var on: bool = d.gear == d.RUINS
	_vis = move_toward(_vis, 1.0 if on else 0.0, dt / DISSOLVE)
	var rate: float = get_parent().rate()
	for r in _ruins:
		r.z -= rate * dt
		r.rot += r.spin * dt
		if r.z < Z_NEAR:
			_respawn(r, Z_FAR + _rng.randf_range(0.0, 0.8))
	visible = _vis > 0.0
	if visible:
		queue_redraw()


func _draw() -> void:
	var vp: Vector2 = get_parent().vp()
	var c: Vector2 = get_parent().size * 0.5
	var frame := Palette.color("frame")
	var gold := Palette.color("core")
	var breathe := 0.85 + 0.15 * Palette.breath()
	for r in _ruins:
		if r.z > Z_FAR or r.z < Z_NEAR:
			continue
		var p := vp + r.lateral / r.z
		var near := 1.0 - r.z
		var a := smoothstep(Z_FAR, 0.75, r.z) * smoothstep(Z_NEAR, 0.22, r.z) * smoothstep(200.0, 420.0, p.distance_to(c)) * 0.85 * _vis * breathe
		if a <= 0.001:
			continue
		var w := lerpf(0.7, 1.4, near)
		draw_set_transform(p, r.rot, Vector2.ONE * SCALE / r.z)
		_draw_kind(r.kind, Palette.dim(frame, a), Palette.dim(gold, a * 1.3), w)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_kind(kind: int, col: Color, gold: Color, w: float) -> void:
	match kind:
		0:  # an arch, one pillar broken
			draw_line(Vector2(-30, 0), Vector2(-30, -60), col, w, true)
			draw_line(Vector2(30, 0), Vector2(30, -38), col, w, true)
			draw_arc(Vector2(0, -60), 30.0, PI, TAU, 24, col, w, true)
			draw_line(Vector2(-44, 0), Vector2(44, 0), col, w * 0.8, true)
		1:  # a broken ring with ticks, a beacon at one end
			draw_arc(Vector2.ZERO, 45.0, 0.3, 4.2, 40, col, w, true)
			for k in 8:
				var ang := 0.3 + k * 0.5
				var dir := Vector2.from_angle(ang)
				draw_line(dir * 45.0, dir * 51.0, col, w * 0.8, true)
			draw_circle(Vector2.from_angle(4.2) * 45.0, 1.8, gold)
		2:  # a lattice shard
			var pts := [Vector2(-40, 20), Vector2(0, 20), Vector2(40, 20), Vector2(-20, -15), Vector2(20, -15), Vector2(0, -50)]
			for pair in [[0, 1], [1, 2], [0, 3], [1, 3], [1, 4], [2, 4], [3, 4], [3, 5], [4, 5]]:
				draw_line(pts[pair[0]], pts[pair[1]], col, w * 0.8, true)
			draw_circle(pts[3], 1.4, col)
		3:  # an obelisk with a node still lit above it
			draw_rect(Rect2(-7, -90, 14, 90), col, false, w)
			draw_line(Vector2(-7, -90), Vector2(0, -104), col, w, true)
			draw_line(Vector2(7, -90), Vector2(0, -104), col, w, true)
			draw_circle(Vector2(0, -116), 1.8, gold)
			draw_arc(Vector2(0, -116), 6.0, 0.0, TAU, 16, Color(gold.r, gold.g, gold.b, gold.a * 0.35), w * 0.6, true)
		4:  # a sigil shard
			draw_arc(Vector2.ZERO, 40.0, PI * 0.9, PI * 1.9, 32, col, w, true)
			for k in 3:
				var ang := PI * 1.05 + k * 0.32
				draw_arc(Vector2.ZERO, 48.0, ang, ang + 0.18, 6, col, w * 0.8, true)
			draw_circle(Vector2.from_angle(PI * 1.4) * 40.0, 1.6, gold)
