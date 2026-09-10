class_name SigilBlock
extends Control
## One instrument on the hull: a magic circle. Concentric rings of glyphs
## turn around whatever lives in `Content`, each ring at its own speed and
## every other ring the other way. Hairlines, pale light, real alpha: the
## same register as the void, so the instruments belong to it.

const LABEL_SIZE := 8
const GLYPH_COUNT := 28
const TEXT_RING_SEP := "  ·  "

## Rings, outermost first: radius inset from the edge, angular speed
## (radians per second; sign is chirality), and what the ring carries.
const RINGS := [
	{"inset": 6.0, "speed": 0.05, "kind": "glyphs"},
	{"inset": 24.0, "speed": -0.08, "kind": "text"},
	{"inset": 38.0, "speed": 0.14, "kind": "arcs"},
]
const INNER_INSET := 46.0

@export var title := "":
	set(v):
		title = v
		queue_redraw()
@export var seed := 1

@onready var content: MarginContainer = $Content

var _glyphs: Array = []   # per glyph: Array of strokes; a stroke is [kind, a, b]
var _font: Font
var _t := 0.0


func _ready() -> void:
	_font = ThemeDB.fallback_font
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
			"text":
				draw_arc(c, r + 7.0, 0.0, TAU, 128, Palette.dim(frame, 0.16 * breathe), 1.0, true)
				_draw_text_ring(c, r, rot, Palette.dim(light, 0.5 * breathe))
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

	# The name, at the foot of the disc, tiny and upright.
	if title != "":
		var label := title.to_upper()
		var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
		draw_string(_font, Vector2(c.x - w * 0.5, c.y + ri - 5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, Palette.dim(light, 0.55 * breathe))


func _draw_glyph(at: Vector2, angle: float, strokes: Array, col: Color) -> void:
	draw_set_transform(at, angle, Vector2.ONE)
	for s in strokes:
		match s[0]:
			"line": draw_line(s[1], s[2], col, 1.0, true)
			"dot": draw_circle(s[1], 0.9, col)
			"ring": draw_arc(s[1], s[2].x, 0.0, TAU, 12, col, 1.0, true)
			"arc": draw_arc(s[1], s[2].x, s[2].y, s[2].y + PI, 10, col, 1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The title and the system's name circle the disc, glyph by glyph, each
## character standing on the ring.
func _draw_text_ring(c: Vector2, r: float, rot: float, col: Color) -> void:
	var text := ((title if title != "" else "sigil") + TEXT_RING_SEP + "yggdrasil" + TEXT_RING_SEP).to_upper()
	var widths: Array[float] = []
	var total := 0.0
	for ch in text:
		var w := _font.get_char_size(ch.unicode_at(0), LABEL_SIZE).x
		widths.append(w)
		total += w
	var circumference := TAU * r
	var repeats := maxi(1, int(floor(circumference / total)))
	var step_scale := circumference / (total * repeats)
	var a := rot
	for rep in repeats:
		for i in text.length():
			var w := widths[i] * step_scale
			var mid := a + (w * 0.5) / r
			var at := c + Vector2.from_angle(mid) * r
			draw_set_transform(at, mid + PI / 2.0, Vector2.ONE)
			_font.draw_char(get_canvas_item(), Vector2(-widths[i] * 0.5, LABEL_SIZE * 0.35), text.unicode_at(i), LABEL_SIZE, col)
			a += w / r
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
