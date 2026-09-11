extends Node2D
## The warp's charge (gear 7): the point ahead being opened. While the
## drive stops, a gold point brightens at the vanishing point and
## hairline rings converge on it from the frame's edge, each starting a
## little after the last and closing tighter: something ahead is being
## opened. When the jump comes the rings are gone and the point flares
## out as the new space blooms from it (the shader's seam). Dissolves on
## any other shift.

const RINGS := 5
const RING_EVERY := 0.6       # seconds between one ring's start and the next
const RING_CLOSE := 2.4       # seconds a ring takes to close
const R_START := 760.0
const R_END := 96.0           # the first ring closes to this; later ones tighter
const DISSOLVE := 0.8

var _vis := 0.0
var _phase := ""
var _phase_t := 0.0
var _sweep := 0.0


func _process(dt: float) -> void:
	var d = get_parent().drive
	if d == null:
		return
	var on: bool = d.gear == d.WARP and d.phase != "arrive"
	if on:
		_phase = d.phase
		_phase_t = d.phase_t
		_sweep = d.sweep
	_vis = move_toward(_vis, 1.0 if on else 0.0, dt / DISSOLVE)
	visible = _vis > 0.0
	if visible:
		queue_redraw()


func _draw() -> void:
	var d = get_parent().drive
	var vp: Vector2 = get_parent().vp()
	var frame := Palette.color("frame")
	var light := Palette.color("light")
	var gold := Palette.color("core")
	var breathe := 0.85 + 0.15 * Palette.breath()
	if _phase == "charge":
		var charge := smoothstep(0.0, 1.0, _phase_t / d.WARP_CHARGE)
		# The point.
		draw_circle(vp, 1.4 + 1.6 * charge, Palette.dim(gold, 0.95 * charge * _vis * breathe))
		draw_circle(vp, 4.0 + 14.0 * charge, Palette.dim(gold, 0.10 * charge * _vis))
		# The rings, closing.
		for i in RINGS:
			var u := clampf((_phase_t - i * RING_EVERY) / RING_CLOSE, 0.0, 1.0)
			if u <= 0.0:
				continue
			var e := smoothstep(0.0, 1.0, u)
			var r_end := R_END * (1.0 - float(i) / RINGS) + 6.0
			var r := lerpf(R_START, r_end, e)
			var a := (0.18 + 0.32 * e) * _vis * smoothstep(0.0, 0.15, u)
			var col := frame.lerp(light, 0.5 * e)
			draw_arc(vp, r, 0.0, TAU, 128, Palette.dim(col, a), 1.0, true)
	elif _phase == "sweep":
		# The point flares as the jump opens, and is gone.
		var flare := 1.0 - smoothstep(0.0, 0.5, _sweep)
		draw_circle(vp, 3.0 + 10.0 * _sweep, Palette.dim(light, 0.9 * flare * _vis))
		draw_circle(vp, 18.0 + 60.0 * _sweep, Palette.dim(gold, 0.12 * flare * _vis))
