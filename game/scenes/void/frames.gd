extends Node2D
## Zen: every window on screen gets a hairline frame, so the desktop's own
## windows read as part of the system rather than as intruders on it.
## The frontmost app's frame is gold. Only meaningful over the desktop,
## where the cockpit covers the screen and its canvas maps to it; the
## helper reports window bounds in screen points, the cockpit works in
## screen pixels, so the display scale bridges them.

const FADE := 0.8
const CORNER := 14.0
const LABEL_SIZE := 9
## No frame for these: Terminal has dissolved into the void in zen, and
## NERViewer is an instrument of the hull, not a window on the desk.
const EXEMPT := ["com.apple.Terminal", "edu.pdx.josh.nerviewer"]

var shown := false
var _alpha := 0.0
var _font: Font


func _ready() -> void:
	_font = Palette.FONT


func set_shown(on: bool) -> void:
	shown = on


func _process(dt: float) -> void:
	var target := 1.0 if shown else 0.0
	_alpha = move_toward(_alpha, target, dt / FADE)
	visible = _alpha > 0.0
	if visible:
		queue_redraw()


func _draw() -> void:
	var win := get_window()
	# Godot measures the whole desktop at the largest scale of any screen
	# attached, not at this screen's own: with a Retina panel beside a 1x
	# monitor, points are doubled on both (found 2026-09-17, when a second
	# monitor put every frame at half its place).
	var scale := DisplayServer.screen_get_max_scale()
	var origin := Vector2(win.position)
	var xf := get_viewport().get_final_transform().affine_inverse()
	var frame := Palette.color("frame")
	var light := Palette.color("light")
	var gold := Palette.color("core")
	var breathe := 0.85 + 0.15 * Palette.breath()
	for id in Workspace.apps:
		var app = Workspace.apps[id]
		if not app.alive or id in EXEMPT:
			continue
		var col: Color = gold if app.active else frame
		var line_alpha := (0.55 if app.active else 0.3) * _alpha * breathe
		for r in app.rects:
			# points -> desktop units -> this window -> canvas.
			var px := Rect2(r.position * scale, r.size * scale)
			var tl: Vector2 = xf * (px.position - origin)
			var br: Vector2 = xf * (px.end - origin)
			var rect := Rect2(tl, br - tl).abs()
			if rect.size.x < 8.0 or rect.size.y < 8.0:
				continue
			draw_rect(rect, Palette.dim(col, line_alpha), false, 1.0, true)
			_corners(rect, Palette.dim(light if app.active else col, line_alpha * 1.4))
			# The name sits inside the frame, top right, where a title bar
			# has room and a window at the screen's top edge still shows it.
			var label: String = str(app.name).to_upper()
			var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
			draw_string(_font, Vector2(rect.end.x - CORNER - 4.0 - w, rect.position.y + LABEL_SIZE + 5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, Palette.dim(light, line_alpha * 1.2))


## Bracket ticks at the four corners: the frame is held, not merely drawn.
func _corners(r: Rect2, col: Color) -> void:
	var pts := [
		[r.position, Vector2(1, 0), Vector2(0, 1)],
		[Vector2(r.end.x, r.position.y), Vector2(-1, 0), Vector2(0, 1)],
		[Vector2(r.position.x, r.end.y), Vector2(1, 0), Vector2(0, -1)],
		[r.end, Vector2(-1, 0), Vector2(0, -1)],
	]
	for p in pts:
		var c: Vector2 = p[0]
		draw_line(c, c + p[1] * CORNER, col, 2.0, true)
		draw_line(c, c + p[2] * CORNER, col, 2.0, true)
