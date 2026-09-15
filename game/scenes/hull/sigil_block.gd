class_name SigilBlock
extends Control
## One instrument on the hull: a magic circle. Concentric rings of glyphs
## turn around whatever lives in `Content`, each ring at its own speed and
## every other ring the other way. Hairlines, pale light, real alpha: the
## same register as the void, so the instruments belong to it.
##
## Drawn once, moved every frame (2026-09-15): each ring is a Node2D of
## its own that draws its hairlines when the block is laid out and then
## only turns, by its `rotation`; the breath is the rings' modulate. The
## cockpit used to rebuild every antialiased stroke thirty times a second,
## and that, not the void's shader, was most of its idle cost.

const GLYPH_COUNT := 28
## The middle ring carries the Ring verse in Tengwar (fonts/the_one_ring.ttf,
## see Inscription), this tall. It replaced a ring of the title and
## "yggdrasil" as text on 2026-09-09.
const INSCRIPTION_HEIGHT := 9.0

## Rings, outermost first: radius inset from the edge, angular speed
## (radians per second; sign is chirality), and what the ring carries.
## Speeds are two thirds of the first cut (Josh, 2026-09-10: a third
## slower).
const RINGS := [
	{"inset": 6.0, "speed": 0.0333, "kind": "glyphs"},
	{"inset": 24.0, "speed": -0.0533, "kind": "inscription"},
	{"inset": 38.0, "speed": 0.0933, "kind": "arcs"},
]
const INNER_INSET := 46.0
## The inscription's strips come from the font atlas, whose placement
## could move if the text server repacked it; redraw that ring this often.
const INSCRIPTION_REFRESH := 2.0

## The instrument's name. Not drawn (the disc stays bare); kept for the
## dock and for tools that need to tell blocks apart.
@export var title := ""
## Bare: nothing is painted inside the inner ring. For a block whose guest
## is another window (NERViewer), so the cockpit never smokes it over,
## whichever of the two floating windows the system has put on top.
var bare := false:
	set(v):
		if v != bare:
			bare = v
			queue_redraw()
@export var seed := 1
## Failing: the instrument's source is gone (NERViewer not running after
## its launch grace, say). Bugs appear: rabbits on the disc's floor.
var failing := false:
	set(v):
		failing = v
		if _rabbits == null:
			_rabbits = RABBITS.new()
			_rabbits.name = "Rabbits"
			add_child(_rabbits)
		_rabbits.disc = inner_rect()
		_rabbits.failing = v
## The warp: 0 at rest; the rings spin up to WARP_SPIN times their pace
## and the inscription warms toward gold as it rises.
var warp := 0.0
const WARP_SPIN := 6.0
const RABBITS := preload("res://scenes/hull/rabbits.gd")
var _rabbits: Node2D

@onready var content: MarginContainer = $Content

var _glyphs: Array = []   # per glyph: Array of strokes; a stroke is [kind, a, b]
var _inscription: Inscription
var _t := 0.0
var _rings: Node2D                 # breathes by modulate; sits under Content
var _ring_nodes: Array[Node2D] = []   # RINGS in order, then the ticks, then the inner ring
var _inscription_guard := 0.0


func _ready() -> void:
	_inscription = Inscription.new()
	_build_glyphs()
	_rings = Node2D.new()
	_rings.name = "Rings"
	add_child(_rings)
	move_child(_rings, 0)
	for spec in RINGS:
		var ring := Node2D.new()
		ring.name = str(spec["kind"]).capitalize()
		ring.draw.connect(_draw_ring.bind(ring, spec))
		_rings.add_child(ring)
		_ring_nodes.append(ring)
	var ticks := Node2D.new()   # the arcs ring's ticks turn the other way
	ticks.name = "Ticks"
	ticks.draw.connect(_draw_ticks.bind(ticks, RINGS[2]))
	_rings.add_child(ticks)
	_ring_nodes.append(ticks)
	var inner := Node2D.new()
	inner.name = "Inner"
	inner.draw.connect(_draw_inner.bind(inner))
	_rings.add_child(inner)
	_ring_nodes.append(inner)
	resized.connect(_fit_content)
	_fit_content()


func _fit_content() -> void:
	_rings.position = size * 0.5
	for ring in _ring_nodes:
		ring.queue_redraw()
	queue_redraw()
	var r := _outer_radius() - INNER_INSET
	if _rabbits != null:
		_rabbits.disc = inner_rect()
	var side := r * 1.5
	content.position = size * 0.5 - Vector2(side, side) * 0.5
	content.size = Vector2(side, side)


func _outer_radius() -> float:
	return minf(size.x, size.y) * 0.5


## The square inside the innermost ring, in this block's coordinates:
## where a guest window would sit.
func inner_rect() -> Rect2:
	var r := _outer_radius() - INNER_INSET
	return Rect2(size * 0.5 - Vector2(r, r), Vector2(r, r) * 2.0)


## A glyph is two to four strokes from a small grammar, chosen once from
## the seed so the circle reads the same every day.
func _build_glyphs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919
	_glyphs.clear()
	for i in GLYPH_COUNT:
		var strokes := []
		var n := rng.randi_range(2, 4)
		for k in n:
			match rng.randi_range(0, 6):
				0: strokes.append(["line", Vector2(0, -4), Vector2(0, 4)])
				1: strokes.append(["line", Vector2(-2.5, -4), Vector2(2.5, 4)])
				2: strokes.append(["line", Vector2(-2.5, rng.randf_range(-3, 3)), Vector2(2.5, rng.randf_range(-3, 3))])
				3: strokes.append(["dot", Vector2(rng.randf_range(-2, 2), rng.randf_range(-3.5, 3.5)), Vector2.ZERO])
				4: strokes.append(["ring", Vector2(0, rng.randf_range(-2, 2)), Vector2(1.8, 0)])
				5: strokes.append(["line", Vector2(-2.5, -4), Vector2(2.5, -4)])
				6: strokes.append(["arc", Vector2(0, rng.randf_range(-1.5, 1.5)), Vector2(2.6, rng.randf_range(0, TAU))])
		_glyphs.append(strokes)


func _process(dt: float) -> void:
	_t += dt * (1.0 + (WARP_SPIN - 1.0) * warp)
	# Turn and breathe; nothing is redrawn.
	for i in RINGS.size():
		_ring_nodes[i].rotation = _t * RINGS[i]["speed"]
	_ring_nodes[RINGS.size()].rotation = -_t * RINGS[2]["speed"]
	_rings.modulate.a = 0.85 + 0.15 * Palette.breath()
	_ring_nodes[1].modulate = Color.WHITE.lerp(Palette.color("core"), 0.8 * warp)
	_inscription_guard -= dt
	if _inscription_guard <= 0.0:
		_inscription_guard = INSCRIPTION_REFRESH
		_ring_nodes[1].queue_redraw()


## The disc: a faint fill so the instrument has a floor over the desktop.
## It does not breathe; drawn when the block is laid out or `bare` changes.
func _draw() -> void:
	var c := size * 0.5
	var R := _outer_radius()
	var ri := R - INNER_INSET
	if bare:
		draw_arc(c, (R + ri) * 0.5, 0.0, TAU, 128, Palette.dim(Palette.color("ground"), 0.18), R - ri, false)
	else:
		draw_circle(c, ri, Palette.dim(Palette.color("ground"), 0.35))
		draw_circle(c, R, Palette.dim(Palette.color("ground"), 0.18))


func _draw_inner(ci: CanvasItem) -> void:
	ci.draw_arc(Vector2.ZERO, _outer_radius() - INNER_INSET, 0.0, TAU, 96, Palette.dim(Palette.color("light"), 0.28), 1.0, true)


## One ring about its own origin, unturned: the node's rotation turns it.
func _draw_ring(ci: CanvasItem, ring: Dictionary) -> void:
	var r: float = _outer_radius() - ring["inset"]
	var frame := Palette.color("frame")
	var light := Palette.color("light")
	var gold := Palette.color("core")
	var c := Vector2.ZERO
	match ring["kind"]:
		"glyphs":
			ci.draw_arc(c, r + 6.0, 0.0, TAU, 128, Palette.dim(frame, 0.38), 1.0, true)
			ci.draw_arc(c, r - 7.0, 0.0, TAU, 128, Palette.dim(frame, 0.18), 1.0, true)
			for i in GLYPH_COUNT:
				var a := TAU * float(i) / float(GLYPH_COUNT)
				_draw_glyph(ci, Vector2.from_angle(a) * r, a + PI / 2.0, _glyphs[i], Palette.dim(light, 0.55))
		"inscription":
			ci.draw_arc(c, r + 7.0, 0.0, TAU, 128, Palette.dim(frame, 0.16), 1.0, true)
			_inscription.draw(ci, c, r, 0.0, INSCRIPTION_HEIGHT, Palette.dim(light, 0.7))
			ci.draw_arc(c, r - 7.0, 0.0, TAU, 128, Palette.dim(frame, 0.16), 1.0, true)
		"arcs":
			for k in 3:
				var a0 := TAU * float(k) / 3.0
				ci.draw_arc(c, r, a0, a0 + deg_to_rad(74.0), 32, Palette.dim(gold, 0.5), 1.2, true)
				ci.draw_circle(Vector2.from_angle(a0) * r, 1.4, Palette.dim(gold, 0.85))


func _draw_ticks(ci: CanvasItem, ring: Dictionary) -> void:
	var r: float = _outer_radius() - ring["inset"]
	var frame := Palette.color("frame")
	for k in 24:
		var d := Vector2.from_angle(TAU * float(k) / 24.0)
		var long := k % 6 == 0
		ci.draw_line(d * (r - 3.0), d * (r - (7.0 if long else 5.0)), Palette.dim(frame, 0.45), 1.0, true)


func _draw_glyph(ci: CanvasItem, at: Vector2, angle: float, strokes: Array, col: Color) -> void:
	ci.draw_set_transform(at, angle, Vector2.ONE)
	for s in strokes:
		match s[0]:
			"line": ci.draw_line(s[1], s[2], col, 1.0, true)
			"dot": ci.draw_circle(s[1], 0.9, col)
			"ring": ci.draw_arc(s[1], s[2].x, 0.0, TAU, 12, col, 1.0, true)
			"arc": ci.draw_arc(s[1], s[2].x, s[2].y, s[2].y + PI, 10, col, 1.0, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
