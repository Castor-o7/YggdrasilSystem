extends Node2D
## Zen: the one seam Terminal cannot hide, its title bar, is covered up.
## The cockpit floats above every window, so over each Terminal window it
## paints the wallpaper back over the title bar strip, cut from the same
## spot, and the strip vanishes. Drawn under the void so the lattice
## still passes over it. Solid-color wallpapers are the easy case; an
## image wallpaper is mapped the way macOS fills the screen (aspect fill,
## centered). If the wallpaper cannot be read, the void's ground color
## stands in.

const TITLE_POINTS := 28.0     # macOS title bar height, in points
## The window frame's other three sides: macOS draws a hairline border at
## the edge and Terminal keeps a small inset inside it. The band reaches
## this far outside the frame and this far inside it.
const EDGE_OUT := 4.0
const EDGE_IN := 3.0
const FADE := 0.8
const PICTURE := 'tell application "System Events" to get picture of current desktop'

var shown := false
var _alpha := 0.0
var _wall: Texture2D
var _wall_path := ""


func set_shown(on: bool) -> void:
	shown = on
	if on:
		_refresh_wallpaper()


func _process(dt: float) -> void:
	_alpha = move_toward(_alpha, 1.0 if shown else 0.0, dt / FADE)
	visible = _alpha > 0.0
	if visible:
		queue_redraw()


## Load the current wallpaper once per path. Formats Godot cannot read
## (HEIC, and whatever else) go through sips to a PNG in user://.
func _refresh_wallpaper() -> void:
	var path := Osa.run(PICTURE)
	if path.is_empty():
		return
	if path == _wall_path and _wall != null:
		return
	_wall_path = path
	_wall = null
	if not FileAccess.file_exists(path):
		return
	var img := Image.new()
	var ext := path.get_extension().to_lower()
	if ext in ["png", "jpg", "jpeg", "webp"]:
		if img.load(path) != OK:
			return
	else:
		var tmp := ProjectSettings.globalize_path("user://wallpaper.png")
		if OS.execute("/usr/bin/sips", ["-s", "format", "png", path, "--out", tmp], [], true) != 0:
			return
		if img.load(tmp) != OK:
			return
	_wall = ImageTexture.create_from_image(img)


func _draw() -> void:
	var win := get_window()
	var scale := DisplayServer.screen_get_scale(win.current_screen)
	var screen := Vector2(DisplayServer.screen_get_size(win.current_screen))
	var origin := Vector2(win.position)
	var xf := get_viewport().get_final_transform().affine_inverse()
	var app = Workspace.apps.get("com.apple.Terminal")
	if app == null or not app.alive:
		return
	var tint := Color(1, 1, 1, _alpha)
	var ground := Palette.dim(Palette.color("ground"), _alpha)
	for r in app.rects:
		# The title bar, then bands down both sides and along the bottom,
		# all in screen points.
		var top := Rect2(r.position - Vector2(EDGE_OUT, EDGE_OUT), Vector2(r.size.x + 2.0 * EDGE_OUT, TITLE_POINTS + EDGE_OUT))
		var left := Rect2(r.position.x - EDGE_OUT, r.position.y, EDGE_OUT + EDGE_IN, r.size.y)
		var right := Rect2(r.end.x - EDGE_IN, r.position.y, EDGE_OUT + EDGE_IN, r.size.y)
		var bottom := Rect2(r.position.x - EDGE_OUT, r.end.y - EDGE_IN, r.size.x + 2.0 * EDGE_OUT, EDGE_IN + EDGE_OUT)
		for band in [top, left, right, bottom]:
			_paint(Rect2(band.position * scale, band.size * scale), origin, xf, screen, tint, ground)


## Paint the wallpaper (or the ground) over a rect given in screen pixels.
func _paint(strip: Rect2, origin: Vector2, xf: Transform2D, screen: Vector2, tint: Color, ground: Color) -> void:
	var tl: Vector2 = xf * (strip.position - origin)
	var br: Vector2 = xf * (strip.end - origin)
	var rect := Rect2(tl, br - tl).abs()
	if _wall == null:
		draw_rect(rect, ground)
		return
	# Aspect-fill mapping of the wallpaper onto the screen.
	var ws := Vector2(_wall.get_size())
	var k := maxf(screen.x / ws.x, screen.y / ws.y)
	var offset := (screen - ws * k) * 0.5
	var src := Rect2((strip.position - offset) / k, strip.size / k)
	draw_texture_rect_region(_wall, rect, src, tint)
