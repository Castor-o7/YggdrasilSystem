extends Control
## The hull: the rail along the foot of the frame and the two side columns
## where instruments dock. Slots are laid out from the frame size, so
## desktop mode (which grows the window to the screen) re-docks everything.
## The rail is drawn: a hairline with a ruler's ticks, the ground the
## tree stands on.

const SIDE := 0.18       # column width, fraction of frame width (matches Main)
const RAIL := 0.08       # rail height, fraction of frame height
const GAP := 8.0
const TICK := 48.0

var _docked: Array = []  # [block, side ("left"/"right"), index]
var _laid_for := Vector2.ZERO


func _process(_dt: float) -> void:
	var s := get_viewport_rect().size
	if s != _laid_for:
		_laid_for = s
		_layout(s)
	queue_redraw()


func dock(block: Control, side: String, index: int) -> void:
	if block.get_parent() != self:
		add_child(block)
	_docked.append([block, side, index])
	_laid_for = Vector2.ZERO


## How far down a column its instruments reach, in canvas units. The
## hull's click area ends there, so windows below stay reachable.
func arm_bottom(side: String) -> float:
	var y := GAP
	for entry in _docked:
		if entry[1] == side:
			y += entry[0].size.y + GAP
	return y


func _layout(s: Vector2) -> void:
	var col_w := s.x * SIDE
	var next_y := {"left": GAP, "right": GAP}
	_docked.sort_custom(func(a, b): return a[2] < b[2])
	for entry in _docked:
		var block: Control = entry[0]
		var side: String = entry[1]
		var x := (col_w - block.size.x) * 0.5
		if side == "right":
			x += s.x - col_w
		block.position = Vector2(x, next_y[side])
		next_y[side] += block.size.y + GAP


func _draw() -> void:
	var s := _laid_for
	if s == Vector2.ZERO:
		return
	var frame := Palette.color("frame")
	var light := Palette.color("light")
	var breathe := 0.85 + 0.15 * Palette.breath()
	var y := s.y - s.y * RAIL
	draw_line(Vector2(0, y), Vector2(s.x, y), Palette.dim(frame, 0.45 * breathe), 1.0, true)
	draw_line(Vector2(0, y + 3.0), Vector2(s.x, y + 3.0), Palette.dim(frame, 0.16 * breathe), 1.0, true)
	var x := fmod(s.x * 0.5, TICK)
	var i := 0
	while x <= s.x:
		var long := i % 5 == 0
		draw_line(Vector2(x, y + 3.0), Vector2(x, y + (11.0 if long else 7.0)), Palette.dim(frame, (0.4 if long else 0.25) * breathe), 1.0, true)
		x += TICK
		i += 1
	# The rail's edge, where the columns begin.
	for cx in [s.x * SIDE, s.x - s.x * SIDE]:
		draw_line(Vector2(cx, y), Vector2(cx, y + 14.0), Palette.dim(light, 0.35 * breathe), 1.0, true)
