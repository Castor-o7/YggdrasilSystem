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

## After the instruments are placed for a new frame size; the click area
## follows them.
signal laid_out

var _docked: Array = []  # [block, side ("left"/"right"), index]
var _laid_for := Vector2.ZERO
## The rail, drawn once per layout on a child under the instruments.
var _rail: Node2D


func _ready() -> void:
	_rail = Node2D.new()
	_rail.name = "Rail"
	_rail.draw.connect(_draw_rail)
	add_child(_rail)
	move_child(_rail, 0)


func _process(_dt: float) -> void:
	var s := get_viewport_rect().size
	if s != _laid_for:
		_laid_for = s
		_layout(s)
		_rail.queue_redraw()
	# The rail breathes by modulate; it is drawn only when laid out.
	_rail.modulate.a = 0.85 + 0.15 * Palette.breath()


func dock(block: Control, side: String, index: int) -> void:
	if block.get_parent() != self:
		add_child(block)
	_docked.append([block, side, index])
	_laid_for = Vector2.ZERO


## Each instrument's disc in the hull's coordinates, [center, radius]:
## the click area is these and nothing else of the columns.
func discs() -> Array:
	var out := []
	for entry in _docked:
		var block: Control = entry[0]
		out.append([block.position + block.size * 0.5, minf(block.size.x, block.size.y) * 0.5])
	return out


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
	laid_out.emit()


func _draw_rail() -> void:
	var s := _laid_for
	if s == Vector2.ZERO:
		return
	var frame := Palette.color("frame")
	var light := Palette.color("light")
	var breathe := 1.0   # the rail node's modulate breathes
	var y := s.y - s.y * RAIL
	_rail.draw_line(Vector2(0, y), Vector2(s.x, y), Palette.dim(frame, 0.45 * breathe), 1.0, true)
	_rail.draw_line(Vector2(0, y + 3.0), Vector2(s.x, y + 3.0), Palette.dim(frame, 0.16 * breathe), 1.0, true)
	var x := fmod(s.x * 0.5, TICK)
	var i := 0
	while x <= s.x:
		var long := i % 5 == 0
		_rail.draw_line(Vector2(x, y + 3.0), Vector2(x, y + (11.0 if long else 7.0)), Palette.dim(frame, (0.4 if long else 0.25) * breathe), 1.0, true)
		x += TICK
		i += 1
	# The rail's edge, where the columns begin.
	for cx in [s.x * SIDE, s.x - s.x * SIDE]:
		_rail.draw_line(Vector2(cx, y), Vector2(cx, y + 14.0), Palette.dim(light, 0.35 * breathe), 1.0, true)
