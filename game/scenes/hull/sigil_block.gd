class_name SigilBlock
extends Control
## One instrument on the hull: a magic circle. Concentric rings of glyphs
## turn around whatever lives in `Content`, each ring at its own speed and
## every other ring the other way. Hairlines, pale light, real alpha: the
## same register as the void, so the instruments belong to it.

const GLYPH_COUNT := 28
## The middle ring carries the Ring verse in Tengwar (fonts/the_one_ring.ttf,
## see Inscription), this tall. It replaced a ring of the title and
## "yggdrasil" as text on 2026-09-09.
const INSCRIPTION_HEIGHT := 9.0

## Rings, outermost first: radius inset from the edge, angular speed
## (radians per second; sign is chirality), and what the ring carries.
const RINGS := [
	{"inset": 6.0, "speed": 0.05, "kind": "glyphs"},
	{"inset": 24.0, "speed": -0.08, "kind": "inscription"},
	{"inset": 38.0, "speed": 0.14, "kind": "arcs"},
]
const INNER_INSET := 46.0

## The instrument's name. Not drawn (the disc stays bare); kept for the
## dock and for tools that need to tell blocks apart.
@export var title := ""
## Bare: nothing is painted inside the inner ring. For a block whose guest
## is another window (NERViewer), so the cockpit never smokes it over,
## whichever of the two floating windows the system has put on top.
var bare := false
@export var seed := 1

@onready var content: MarginContainer = $Content

var _glyphs: Array = []   # per glyph: Array of strokes; a stroke is [kind, a, b]
var _inscription: Inscription
var _t := 0.0


func _ready() -> void:
	_inscription = Inscription.new()
	_build_glyphs()
	resized.connect(_fit_content)
	_fit_content()


func _fit_content() -> void:
	var r := _outer_radius() - INNER_INSET
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
	_t += dt
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var R := _outer_radius()
	var frame := Palette.color("frame")
	var light := Palette.color("light")
	var gold := Palette.color("core")
	var breathe := 0.85 + 0.15 * Palette.breath()

	# The disc: a faint fill so the instrument has a floor over the desktop.
	var ri := R - INNER_INSET
	if bare:
		draw_arc(c, (R + ri) * 0.5, 0.0, TAU, 128, Palette.dim(Palette.color("ground"), 0.18), R - ri, false)
	else:
		draw_circle(c, ri, Palette.dim(Palette.color("ground"), 0.35))
		draw_circle(c, R, Palette.dim(Palette.color("ground"), 0.18))
	draw_arc(c, ri, 0.0, TAU, 96, Palette.dim(light, 0.28 * breathe), 1.0, true)

	for ring in RINGS:
		var r: float = R - ring["inset"]
		var rot: float = _t * ring["speed"]
		match ring["kind"]:
			"glyphs":
				draw_arc(c, r + 6.0, 0.0, TAU, 128, Palette.dim(frame, 0.38 * breathe), 1.0, true)
				draw_arc(c, r - 7.0, 0.0, TAU, 128, Palette.dim(frame, 0.18 * breathe), 1.0, true)
				for i in GLYPH_COUNT:
					var a := rot + TAU * float(i) / float(GLYPH_COUNT)
					_draw_glyph(c + Vector2.from_angle(a) * r, a + PI / 2.0, _glyphs[i], Palette.dim(light, 0.55 * breathe))
			"inscription":
				draw_arc(c, r + 7.0, 0.0, TAU, 128, Palette.dim(frame, 0.16 * breathe), 1.0, true)
				_inscription.draw(self, c, r, rot, INSCRIPTION_HEIGHT, Palette.dim(light, 0.7 * breathe))
				draw_arc(c, r - 7.0, 0.0, TAU, 128, Palette.dim(frame, 0.16 * breathe), 1.0, true)
			"arcs":
				for k in 3:
					var a0 := rot + TAU * float(k) / 3.0
					draw_arc(c, r, a0, a0 + deg_to_rad(74.0), 32, Palette.dim(gold, 0.5 * breathe), 1.2, true)
					draw_circle(c + Vector2.from_angle(a0) * r, 1.4, Palette.dim(gold, 0.85 * breathe))
				for k in 24:
					var a := -rot + TAU * float(k) / 24.0
					var d := Vector2.from_angle(a)
					var long := k % 6 == 0
					draw_line(c + d * (r - 3.0), c + d * (r - (7.0 if long else 5.0)), Palette.dim(frame, 0.45 * breathe), 1.0, true)


func _draw_glyph(at: Vector2, angle: float, strokes: Array, col: Color) -> void:
	draw_set_transform(at, angle, Vector2.ONE)
	for s in strokes:
		match s[0]:
			"line": draw_line(s[1], s[2], col, 1.0, true)
			"dot": draw_circle(s[1], 0.9, col)
			"ring": draw_arc(s[1], s[2].x, 0.0, TAU, 12, col, 1.0, true)
			"arc": draw_arc(s[1], s[2].x, s[2].y, s[2].y + PI, 10, col, 1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

