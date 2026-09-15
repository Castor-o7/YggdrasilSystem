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
## After an instrument was dragged to a new slot (garage mode).
signal arranged

## Garage mode (G): the instruments can be dragged between slots. Each
## column shows its slots as faint gold circles, the one after the last
## instrument empty; a block lifted and dropped goes to the nearest slot
## and the others ease over. The arrangement persists (main's prefs).
var garage := false:
	set(v):
		garage = v
		_garage.queue_redraw()
		if not v and _drag != null:
			_drop()
var _garage: Node2D
var _drag = null          # [block, offset from the block's origin to the mouse] while dragging
var _tweens: Dictionary[Control, Tween] = {}
const EASE := 0.3          # seconds for a block to ease into its slot

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
	_garage = Node2D.new()
	_garage.name = "Garage"
	_garage.draw.connect(_draw_garage)
	add_child(_garage)
	move_child(_garage, 1)


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
		block.gui_input.connect(_block_input.bind(block))
	_docked.append([block, side, index])
	_laid_for = Vector2.ZERO


## Where every instrument sits: title -> "side:index".
func arrangement() -> Dictionary:
	var out := {}
	for entry in _docked:
		out[entry[0].title] = "%s:%d" % [entry[1], entry[2]]
	return out


## Move a block to a slot; the column's indices close up around it.
func place(block: Control, side: String, index: int) -> void:
	for entry in _docked:
		if entry[0] == block:
			_docked.erase(entry)
			break
	var column := _docked.filter(func(e): return e[1] == side)
	column.sort_custom(func(a, b): return a[2] < b[2])
	column.insert(clampi(index, 0, column.size()), [block, side, 0])
	for i in column.size():
		column[i][2] = i
	_docked = _docked.filter(func(e): return e[1] != side) + column
	_laid_for = Vector2.ZERO
	arranged.emit()


## The slot under a point in the hull's coordinates: the side by which
## half, the index by how many of that column's other blocks sit above.
func slot_at(p: Vector2, ignoring: Control) -> Array:
	var side := "left" if p.x < _laid_for.x * 0.5 else "right"
	var index := 0
	for entry in _docked:
		if entry[1] == side and entry[0] != ignoring and entry[0].position.y + entry[0].size.y * 0.5 < p.y:
			index += 1
	return [side, index]


func _block_input(event: InputEvent, block: Control) -> void:
	if not garage:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _drag == null:
			_drag = [block, block.get_local_mouse_position()]
			block.z_index = 1
			_kill_tween(block)
		elif not event.pressed and _drag != null and _drag[0] == block:
			_drop()
	elif event is InputEventMouseMotion and _drag != null and _drag[0] == block:
		block.position = get_local_mouse_position() - _drag[1]
		_garage.queue_redraw()


func _drop() -> void:
	var block: Control = _drag[0]
	_drag = null
	block.z_index = 0
	var slot := slot_at(block.position + block.size * 0.5, block)
	place(block, slot[0], slot[1])


func _kill_tween(block: Control) -> void:
	if _tweens.has(block):
		_tweens[block].kill()
		_tweens.erase(block)


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
		var target := Vector2(x, next_y[side])
		next_y[side] += block.size.y + GAP
		if _drag != null and _drag[0] == block:
			pass   # in hand
		elif block.position == Vector2.ZERO or block.position.distance_to(target) < 0.5:
			block.position = target
		else:
			# Ease over; a tween in flight is replaced.
			_kill_tween(block)
			var tw := block.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_property(block, "position", target, EASE)
			tw.finished.connect(func(): _tweens.erase(block); laid_out.emit())
			_tweens[block] = tw
	_garage.queue_redraw()
	laid_out.emit()


## Garage mode's slots: a faint gold circle at each, the empty one after
## the last instrument in each column drawn fainter.
func _draw_garage() -> void:
	if not garage:
		return
	var s := _laid_for
	var col_w := s.x * SIDE
	var gold := Palette.color("core")
	var next_y := {"left": GAP, "right": GAP}
	for entry in _docked:
		var block: Control = entry[0]
		var side: String = entry[1]
		var cx := col_w * 0.5 + (s.x - col_w if side == "right" else 0.0)
		var r := minf(block.size.x, block.size.y) * 0.5
		_garage.draw_arc(Vector2(cx, next_y[side] + block.size.y * 0.5), r + 4.0, 0.0, TAU, 96, Palette.dim(gold, 0.35), 1.0, true)
		next_y[side] += block.size.y + GAP
	for side in ["left", "right"]:
		var cx := col_w * 0.5 + (s.x - col_w if side == "right" else 0.0)
		_garage.draw_arc(Vector2(cx, next_y[side] + 100.0), 104.0, 0.0, TAU, 96, Palette.dim(gold, 0.15), 1.0, true)


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
