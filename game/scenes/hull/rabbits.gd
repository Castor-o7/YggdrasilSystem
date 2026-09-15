extends Node2D
## Bugs, which are literally rabbits (the premise: errors hop). A failing
## instrument gets one on the floor of its inner disc: a hairline
## creature in the void's register that sits still and, every few
## seconds, hops. The hop is the error's own motion; nothing else moves.
## If the failure persists a second rabbit arrives after MULTIPLY seconds
## and a third after twice that. When the failure clears they hop off.

const HOP_EVERY := [1.6, 4.5]    # seconds between hops, chosen per hop
const HOP_TIME := 0.45
const HOP_HEIGHT := 16.0
const HOP_LENGTH := 22.0
const SIZE := 1.0                # scale of the drawing (about 14 px tall)
const MULTIPLY := 60.0
const MAX := 3
const FADE := 1.0

var disc := Rect2()              # the inner disc's square, in this node's coordinates
var failing := false:
	set(v):
		if v != failing:
			failing = v
			_since = 0.0
			if v and _rabbits.is_empty():
				_rabbits.append(_new_rabbit())
var _rabbits: Array = []         # [x, dir, wait, hop_t]
var _since := 0.0
var _life := 0.0                 # 1 shown, fades to 0 when the failure clears
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _new_rabbit() -> Array:
	var half := _floor_half()
	return [_rng.randf_range(-half * 0.6, half * 0.6), 1.0 if _rng.randf() < 0.5 else -1.0, _rng.randf_range(HOP_EVERY[0], HOP_EVERY[1]), -1.0]


## Half the width of the floor the rabbits sit on: a chord of the disc a
## little above its bottom.
func _floor_half() -> float:
	var r := disc.size.x * 0.5
	var y := r * 0.72
	return sqrt(maxf(0.0, r * r - y * y)) - 6.0


func _process(dt: float) -> void:
	_life = move_toward(_life, 1.0 if failing else 0.0, dt / FADE)
	visible = _life > 0.0
	if not visible:
		return
	if failing:
		_since += dt
		if _rabbits.size() < MAX and _since > MULTIPLY * _rabbits.size():
			_rabbits.append(_new_rabbit())
	var moving := _life < 1.0 or not failing
	var half := _floor_half()
	for r in _rabbits:
		if r[3] >= 0.0:
			# Mid-hop.
			r[3] += dt
			r[0] += r[1] * HOP_LENGTH * dt / HOP_TIME
			moving = true
			if r[3] >= HOP_TIME:
				r[3] = -1.0
				r[2] = _rng.randf_range(HOP_EVERY[0], HOP_EVERY[1])
				if absf(r[0]) > half:
					r[1] = -r[1]
					r[0] = clampf(r[0], -half, half)
		else:
			r[2] -= dt
			if r[2] <= 0.0:
				r[3] = 0.0
				if absf(r[0] + r[1] * HOP_LENGTH) > half:
					r[1] = -r[1]
				moving = true
	if moving:
		queue_redraw()


func _draw() -> void:
	var c := disc.position + disc.size * 0.5
	var r := disc.size.x * 0.5
	var floor_y := c.y + r * 0.72
	var light := Palette.color("light")
	var a := 0.75 * _life
	for rb in _rabbits:
		var lift := 0.0
		if rb[3] >= 0.0:
			var u: float = rb[3] / HOP_TIME
			lift = HOP_HEIGHT * 4.0 * u * (1.0 - u)
		_draw_rabbit(Vector2(c.x + rb[0], floor_y - lift), rb[1], Palette.dim(light, a))


## A rabbit, a few hairline strokes: haunch, back, head, two ears, an
## eye, a tail. `at` is where it sits; `dir` which way it faces.
func _draw_rabbit(at: Vector2, dir: float, col: Color) -> void:
	draw_set_transform(at, 0.0, Vector2(dir * SIZE, SIZE))
	# Body: an arc from the tail up over the back to the chest.
	draw_arc(Vector2(-1.0, -4.5), 5.0, PI * 0.15, PI * 1.05, 18, col, 1.0, true)
	# Chest and feet.
	draw_line(Vector2(3.6, -2.0), Vector2(3.0, 0.0), col, 1.0, true)
	draw_line(Vector2(-4.0, 0.0), Vector2(3.0, 0.0), col, 1.0, true)
	# Head: a small circle forward and up.
	draw_arc(Vector2(5.2, -6.6), 2.4, 0.0, TAU, 12, col, 1.0, true)
	# Ears: two long strokes up and back.
	draw_line(Vector2(4.6, -8.8), Vector2(2.8, -15.5), col, 1.0, true)
	draw_line(Vector2(5.8, -8.9), Vector2(5.4, -15.8), col, 1.0, true)
	# Eye and tail.
	draw_circle(Vector2(6.0, -6.8), 0.6, col)
	draw_circle(Vector2(-6.2, -4.2), 1.1, Palette.dim(col, col.a * 0.8))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
