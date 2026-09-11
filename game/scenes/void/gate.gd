extends Node2D
## The gate: Cowboy Bebop's astral gate as the drive's gear 3. A ring far
## ahead on the heading grows as we close on it (constant speed through
## depth, so it swells slowly and then rushes), we pass through, and the
## tunnel is rings rushing past with gold beacons and the walls' hairlines
## converging on the vanishing point. The middle stays open: down a tunnel
## the center is the far end. On any other shift the piece dissolves.
## Drawn, not shaded, in the tree's perspective.
##
## The portal (Josh, 2026-09-10): the ring holds a disc of deep blue, a
## lighter rim inside the ring and a soft halo outside it, that goes
## opaque as we close and has covered the whole frame by the pass; then
## hyperspace is washed in the same blue, easing from full to a tint and
## fading out through the return.

const CAM := 1100.0
const Z_FAR := 7000.0
const Z_PASS := 380.0
const R_GATE := 320.0
const R_TUNNEL := 300.0
const RINGS := 9
const RING_FAR := 5200.0
const RING_NEAR := 220.0
const TUNNEL_SPEED := 1400.0   # depth units per second at full transit speed
const RAYS := 12
const DISSOLVE := 1.0
const SPIN := 0.06             # radians per second the gate turns
## The portal: how much of the ring it fills, how far its halo reaches
## (as a multiple of the portal's radius), and the hyperspace wash.
const PORTAL_FRACTION := 0.94
const HALO_REACH := 1.5
const TINT_ALPHA := 0.35
const TINT_IN := 1.5           # seconds for the wash to ease from full to the tint

static var _portal_tex: GradientTexture2D

var _vis := 0.0
var _phase := ""
var _phase_t := 0.0
var _tunnel := 0.0
var _spin := 0.0


func _process(dt: float) -> void:
	var d = get_parent().drive
	if d == null:
		return
	var on: bool = d.gear == d.GATE
	if on:
		_phase = d.phase
		_phase_t = d.phase_t
	_vis = move_toward(_vis, 1.0 if on else 0.0, dt / DISSOLVE)
	_spin += SPIN * dt
	if _phase != "approach":
		_tunnel += TUNNEL_SPEED * dt * clampf(d.speed / d.GATE_TRANSIT_SPEED, 0.15, 1.0)
	visible = _vis > 0.0
	if visible:
		queue_redraw()


func _draw() -> void:
	var d = get_parent().drive
	var c: Vector2 = get_parent().vp()
	match _phase:
		"approach":
			var z := lerpf(Z_FAR, Z_PASS, clampf(_phase_t / d.GATE_APPROACH, 0.0, 1.0))
			_draw_gate(c, z, _vis)
		"transit":
			_draw_tint(lerpf(1.0, TINT_ALPHA, smoothstep(0.0, TINT_IN, _phase_t)) * _vis)
			_draw_tunnel(c, _vis)
		"return":
			var left := 1.0 - clampf(_phase_t / d.GATE_RETURN, 0.0, 1.0)
			_draw_tint(TINT_ALPHA * left * _vis)
			_draw_tunnel(c, _vis * left)


## The portal's blue: the frame color deepened toward the ground.
static func portal_color() -> Color:
	return Palette.color("frame").lerp(Palette.color("ground"), 0.45)


## One radial texture, built once: the deep disc, a lighter rim just
## inside the ring's edge (at 1 / HALO_REACH of the texture's radius), and
## the halo falling off outside it. Real alpha, as every glow here.
static func _portal_texture() -> GradientTexture2D:
	if _portal_tex == null:
		var deep := portal_color()
		var rim := Palette.color("frame").lerp(Palette.color("light"), 0.35)
		var halo := Palette.color("frame")
		var edge := 1.0 / HALO_REACH
		var g := Gradient.new()
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
		g.offsets = PackedFloat32Array([0.0, edge * 0.84, edge * 0.97, edge, edge + 0.04, edge + 0.14, edge + 0.24, 1.0])
		g.colors = PackedColorArray([
			deep, deep, rim, rim,
			Palette.dim(halo, 0.4), Palette.dim(halo, 0.14), Palette.dim(halo, 0.04), Palette.dim(halo, 0.0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 512
		t.height = 512
		_portal_tex = t
	return _portal_tex


## The wash over hyperspace: the whole frame in the portal's blue.
func _draw_tint(alpha: float) -> void:
	if alpha <= 0.001:
		return
	draw_rect(Rect2(Vector2.ZERO, get_parent().size), Palette.dim(portal_color(), alpha), true)


## The gate at depth z: outer and inner rings, spokes between them, dashes
## outside, gold beacons at the spoke tips, three pylons. Far away it is
## thin and dim; near, wide and bright.
func _draw_gate(c: Vector2, z: float, vis: float) -> void:
	var frame := Palette.color("frame")
	var light := Palette.color("light")
	var gold := Palette.color("core")
	var breathe := 0.85 + 0.15 * Palette.breath()
	var r := R_GATE * CAM / z
	var near := 1.0 - clampf(z / Z_FAR, 0.0, 1.0)
	var a := lerpf(0.2, 1.0, near) * vis * breathe
	var w := lerpf(0.7, 1.6, near)
	# The portal, under the ring's lines: translucent far off, opaque well
	# before the pass, so by the pass the whole frame is its blue.
	var reach := r * PORTAL_FRACTION * HALO_REACH
	var opacity := lerpf(0.3, 1.0, smoothstep(Z_FAR, 1200.0, z)) * vis
	draw_texture_rect(_portal_texture(), Rect2(c - Vector2.ONE * reach, Vector2.ONE * reach * 2.0), false, Color(1.0, 1.0, 1.0, opacity))
	draw_arc(c, r, 0.0, TAU, 160, Palette.dim(frame, 0.6 * a), w, true)
	draw_arc(c, r * 0.9, 0.0, TAU, 160, Palette.dim(frame, 0.3 * a), w * 0.8, true)
	for i in 8:
		var dir := Vector2.from_angle(_spin + i * TAU / 8.0)
		draw_line(c + dir * r * 0.9, c + dir * r, Palette.dim(light, 0.5 * a), w, true)
		draw_circle(c + dir * r * 1.06, 1.2 + 1.2 * near, Palette.dim(gold, 0.85 * a))
	var step := TAU / 24.0
	for i in 24:
		var a0 := -_spin * 0.5 + i * step
		draw_arc(c, r * 1.04, a0, a0 + step * 0.45, 8, Palette.dim(frame, 0.35 * a), w * 0.8, true)
	for i in 3:
		var dir := Vector2.from_angle(_spin * 0.3 + i * TAU / 3.0 - PI * 0.5)
		draw_line(c + dir * r, c + dir * r * 1.18, Palette.dim(light, 0.45 * a), w, true)
		var t := c + dir * r * 1.18
		draw_line(t + dir.orthogonal() * 4.0 * (1.0 + near), t - dir.orthogonal() * 4.0 * (1.0 + near), Palette.dim(light, 0.45 * a), w, true)


## Hyperspace: rings cycling from far to near, six beacons each, and the
## walls as rays converging on the far end.
func _draw_tunnel(c: Vector2, vis: float) -> void:
	var frame := Palette.color("frame")
	var gold := Palette.color("core")
	var breathe := 0.85 + 0.15 * Palette.breath()
	var span := RING_FAR - RING_NEAR
	for i in RAYS:
		var dir := Vector2.from_angle(_spin * 0.5 + i * TAU / RAYS)
		draw_line(c + dir * 230.0, c + dir * 1400.0, Palette.dim(frame, 0.12 * vis * breathe), 0.8, true)
	for i in RINGS:
		var z := RING_NEAR + fposmod(-_tunnel + i * span / RINGS, span)
		var r := R_TUNNEL * CAM / z
		# Rings fade in only once they are wider than the clear middle.
		var a := smoothstep(2400.0, 1400.0, z) * smoothstep(RING_NEAR, 700.0, z) * vis * breathe
		var w := lerpf(0.7, 1.5, 1.0 - z / RING_FAR)
		draw_arc(c, r, 0.0, TAU, 128, Palette.dim(frame, 0.4 * a), w, true)
		for k in 6:
			var dir := Vector2.from_angle(_spin * 3.0 + k * TAU / 6.0 + i * 0.37)
			draw_line(c + dir * (r - 4.0), c + dir * (r + 4.0), Palette.dim(gold, 0.7 * a), w, true)
