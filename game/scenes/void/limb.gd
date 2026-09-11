extends Node2D
## The planet's limb, for the ring passage (gear 5): the body whose ring
## the ship is skimming, so vast and so close that only one arc of it
## shows, off the bow's high side. A dark disc that dims the stars behind
## it, a hairline limb, a few bands of atmosphere inside it and one thin
## haze line outside. Still, as a planet is. Dissolves on any other shift.

const OFFSET := Vector2(1150.0, -1350.0)   # the planet's center from the bow
const RADIUS := 1250.0
const DISSOLVE := 1.5

var _vis := 0.0


func _process(dt: float) -> void:
	var d = get_parent().drive
	if d == null:
		return
	_vis = move_toward(_vis, 1.0 if d.gear == d.RING else 0.0, dt / DISSOLVE)
	visible = _vis > 0.0
	if visible:
		queue_redraw()


func _draw() -> void:
	var c: Vector2 = get_parent().vp() + OFFSET
	var frame := Palette.color("frame")
	var light := Palette.color("light")
	var breathe := 0.85 + 0.15 * Palette.breath()
	draw_circle(c, RADIUS, Palette.dim(Palette.color("ground"), 0.5 * _vis))
	for i in 4:
		draw_arc(c, RADIUS - 4.0 - i * 5.0, 0.0, TAU, 256, Palette.dim(frame, (0.16 - 0.035 * i) * _vis * breathe), 1.0, true)
	draw_arc(c, RADIUS, 0.0, TAU, 256, Palette.dim(light, 0.5 * _vis * breathe), 1.2, true)
	draw_arc(c, RADIUS + 7.0, 0.0, TAU, 256, Palette.dim(frame, 0.2 * _vis * breathe), 1.0, true)
