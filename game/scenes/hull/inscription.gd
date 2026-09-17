class_name Inscription
extends RefCounted
## The inscription on a sigil block's middle ring: four lines of verse in
## the ship's own script, curved along the ring. The script is made here,
## in code, and belongs to the suite: a hanging script. Each word hangs
## from a headline; a letter is a stem (short, tall or deep, each ending in
## a curl) with one or two hanging loops, or one of a few odd shapes; a
## vowel is a short carrier with a mark over the headline. It leans hard to
## the right. Nothing is traced from any font. (It
## replaced a freeware Tengwar dingbat face on 2026-09-17, so the suite
## could be open source without a licence that was not ours to give.)
##
## The strokes are hairlines far smaller than a pixel grid forgives, so
## each line is rasterized once into a texture several times taller than
## it shows, with mipmaps, and laid along the arc as a fan of textured
## quads: it hugs the circle at any radius, and costs a few quads a frame
## rather than hundreds of strokes. The textures are shared by every block.

## What the ring says. Letters a to z; anything else is a space.
const VERSE := [
	"roots in the deep well",
	"boughs among the stars",
	"sap is light is time",
	"yggy sails between",
]

## The script's box, in units of the x-height: descenders reach -1,
## ascenders 2, marks stand above that.
const BOTTOM := -1.15
const TOP := 2.35
const HEAD := 1.0          # the headline the letters hang from
const SLANT := 0.45        # italic: x shifts this much per unit of height
const SPACING := 0.3       # between letters
const SPACE := 0.9         # between words
const LOOP := 0.6          # a hanging loop's width
const PX_PER_UNIT := 12.0  # texture resolution
const STROKE := 0.8        # half width of a stroke in the texture, px
const DOT := 1.7           # radius of a dot in the texture, px
const SEGMENTS := 12       # quads per strip
const GAP_MIN := 8.0       # least arc between strips, px

static var _strips: Array[ImageTexture] = []


func _init() -> void:
	if _strips.is_empty():
		for line in VERSE:
			_strips.append(_rasterize(_write(line)))


## Lay the verse once around the ring: `height` px tall, standing on the
## circle of `radius` about `c`, starting at angle `rot`. The slack is shared
## out as equal gaps and a dot stands in each. If the ring is too small for
## the verse at that height, the strips shrink to fit.
func draw(ci: CanvasItem, c: Vector2, radius: float, rot: float, height: float, col: Color) -> void:
	var n := _strips.size()
	if n == 0:
		return
	var circ := TAU * radius
	var total := 0.0
	for tex in _strips:
		total += float(tex.get_width()) / tex.get_height() * height
	var gap := (circ - total) / n
	if gap < GAP_MIN:
		height *= (circ - GAP_MIN * n) / total
		gap = GAP_MIN
	var colors := PackedColorArray([col, col, col, col])
	var item := ci.get_canvas_item()
	var ro := radius + height * 0.5
	var ri := radius - height * 0.5
	var a := rot
	for tex in _strips:
		var da := float(tex.get_width()) / tex.get_height() * height / radius
		for j in SEGMENTS:
			var f0 := float(j) / SEGMENTS
			var f1 := float(j + 1) / SEGMENTS
			var a0 := a + da * f0
			var a1 := a + da * f1
			var pts := PackedVector2Array([
				c + Vector2.from_angle(a0) * ro, c + Vector2.from_angle(a1) * ro,
				c + Vector2.from_angle(a1) * ri, c + Vector2.from_angle(a0) * ri])
			var quv := PackedVector2Array([Vector2(f0, 0.0), Vector2(f1, 0.0), Vector2(f1, 1.0), Vector2(f0, 1.0)])
			RenderingServer.canvas_item_add_polygon(item, pts, colors, quv, tex.get_rid())
		a += da
		ci.draw_circle(c + Vector2.from_angle(a + (gap * 0.5) / radius) * radius, 1.0, col)
		a += gap / radius


## A line of verse as strokes in script units, x running right from 0. A
## stroke is a polyline; a polyline of one point is a dot. Each word hangs
## from a headline, which runs on a little past its last letter and lifts.
static func _write(line: String) -> Array[PackedVector2Array]:
	var strokes: Array[PackedVector2Array] = []
	var x := 0.0
	var word_from := -1.0
	for ch in line.to_lower() + " ":
		var code := ch.unicode_at(0) - 97
		if code < 0 or code > 25:
			if word_from >= 0.0:
				var to := x - SPACING + 0.25
				var headline := PackedVector2Array([Vector2(word_from - 0.3, HEAD), Vector2(to, HEAD)])
				headline.append_array(_arc(Vector2(to, HEAD + 0.3), Vector2(0.3, 0.3), -90.0, 10.0))
				strokes.append(_slant(headline, 0.0))
				word_from = -1.0
			x += SPACE
			continue
		if word_from < 0.0:
			word_from = x
		var letter := _letter(code)
		for stroke: PackedVector2Array in letter[1]:
			strokes.append(_slant(stroke, x))
		x += letter[0] + SPACING
	return strokes


static func _slant(stroke: PackedVector2Array, x: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in stroke:
		out.append(Vector2(x + p.x + p.y * SLANT, p.y))
	return out


## One letter: [advance, strokes], hanging from the headline at x = 0.
static func _letter(code: int) -> Array:
	const VOWELS := [0, 4, 8, 14, 20]  # a e i o u
	var vowel := VOWELS.find(code)
	if vowel >= 0:
		# A short carrier with a mark over the headline.
		var strokes: Array[PackedVector2Array] = [PackedVector2Array([Vector2(0, HEAD), Vector2(0, 0.45)])]
		match vowel:
			0: strokes.append(PackedVector2Array([Vector2(0.0, 1.7)]))
			1: strokes.append(PackedVector2Array([Vector2(-0.2, 1.45), Vector2(0.3, 2.05)]))
			2:
				strokes.append(PackedVector2Array([Vector2(-0.28, 1.7)]))
				strokes.append(PackedVector2Array([Vector2(0.28, 1.7)]))
			3: strokes.append(_arc(Vector2(0.0, 1.8), Vector2(0.32, 0.3), 200.0, -20.0))
			4: strokes.append(PackedVector2Array([Vector2(-0.35, 1.5), Vector2(-0.12, 1.9), Vector2(0.12, 1.5), Vector2(0.35, 1.9)]))
		return [0.3, strokes]
	# The twenty-one consonants, in alphabet order.
	var k := code - (VOWELS.filter(func(v: int) -> bool: return v < code)).size()
	var strokes: Array[PackedVector2Array] = []
	if k < 15:
		# A stem (short, tall, deep) and hanging loops: one or two after the
		# stem, closed or left open with a flick; or one before it.
		var before := k >= 12
		var loops := 1 if before else 1 + (k / 3) % 2
		var open := k >= 6 and not before
		var stem_x := LOOP if before else 0.0
		strokes.append(_shift(_stem(k % 3), stem_x))
		for b in loops:
			var centre := Vector2((b + 0.5) * LOOP, HEAD)
			strokes.append(_arc(centre, Vector2(LOOP * 0.5, 0.85), 180.0, 325.0 if open else 360.0))
		return [loops * LOOP, strokes]
	match k:
		15:  # two shallow waves under the headline
			strokes.append(_arc(Vector2(0.3, HEAD), Vector2(0.3, 0.45), 180.0, 360.0))
			strokes.append(_arc(Vector2(0.9, HEAD), Vector2(0.3, 0.45), 180.0, 360.0))
			return [1.2, strokes]
		16:  # a tall stem that curls over
			strokes.append(_stem(1))
			strokes.append(PackedVector2Array([Vector2(0, 0.5), Vector2(0.5, 0.5)]))
			return [0.5, strokes]
		17:  # a crossed deep stem
			strokes.append(_stem(2))
			strokes.append(PackedVector2Array([Vector2(-0.35, 0.1), Vector2(0.45, 0.4)]))
			return [0.45, strokes]
		18:  # a hanging s-curve
			strokes.append(_arc(Vector2(0.3, 0.72), Vector2(0.3, 0.28), 90.0, 270.0))
			strokes.append(_arc(Vector2(0.3, 0.16), Vector2(0.3, 0.28), 90.0, -140.0))
			return [0.6, strokes]
		19:  # a deep stem with a foot to the right
			strokes.append(PackedVector2Array([Vector2(0, HEAD), Vector2(0, -0.55)]))
			strokes.append(_arc(Vector2(0.4, -0.55), Vector2(0.4, 0.45), 180.0, 300.0))
			return [0.7, strokes]
		_:   # a hanging zigzag
			strokes.append(PackedVector2Array([Vector2(0, HEAD), Vector2(0.5, 0.5), Vector2(0, 0.5), Vector2(0.5, 0)]))
			return [0.5, strokes]


## Stems hang from the headline and end in a curl: short with a flick to
## the right, tall rising through the headline and curling over, deep
## sweeping away to the left.
static func _stem(kind: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match kind:
		1:
			pts.append(Vector2(0, 0))
			pts.append(Vector2(0, 1.7))
			pts.append_array(_arc(Vector2(0.3, 1.7), Vector2(0.3, 0.3), 180.0, 50.0))
		2:
			pts.append(Vector2(0, HEAD))
			pts.append(Vector2(0, -0.55))
			pts.append_array(_arc(Vector2(-0.4, -0.55), Vector2(0.4, 0.45), 0.0, -100.0))
		_:
			pts.append(Vector2(0, HEAD))
			pts.append(Vector2(0, 0.22))
			pts.append_array(_arc(Vector2(0.22, 0.22), Vector2(0.22, 0.22), 180.0, 280.0))
	return pts


## Part of an ellipse about `centre`, from one angle to another in degrees
## (counter-clockwise on the page: y is up here).
static func _arc(centre: Vector2, radii: Vector2, from: float, to: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := maxi(3, int(absf(to - from) / 30.0))
	for i in steps + 1:
		var a := deg_to_rad(lerpf(from, to, float(i) / steps))
		pts.append(centre + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return pts


static func _shift(stroke: PackedVector2Array, dx: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in stroke:
		out.append(p + Vector2(dx, 0.0))
	return out


## The strokes as white on clear, antialiased by their distance from each
## pixel, the page's y turned over for the screen.
static func _rasterize(strokes: Array[PackedVector2Array]) -> ImageTexture:
	var right := 1.0
	for stroke in strokes:
		for p in stroke:
			right = maxf(right, p.x)
	var margin := 0.5
	var w := int(ceil((right + margin * 2.0) * PX_PER_UNIT))
	var h := int(ceil((TOP - BOTTOM) * PX_PER_UNIT))
	var cover := PackedFloat32Array()
	cover.resize(w * h)
	for stroke in strokes:
		var pts := PackedVector2Array()
		for p in stroke:
			pts.append(Vector2((p.x + margin) * PX_PER_UNIT, (TOP - p.y) * PX_PER_UNIT))
		if pts.size() == 1:
			_stamp(cover, w, h, pts[0], pts[0], DOT)
		for i in pts.size() - 1:
			_stamp(cover, w, h, pts[i], pts[i + 1], STROKE)
	var img := Image.create(w, h, true, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color(1, 1, 1, cover[y * w + x]))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _stamp(cover: PackedFloat32Array, w: int, h: int, a: Vector2, b: Vector2, half: float) -> void:
	var reach := half + 1.0
	var x0 := maxi(0, int(floor(minf(a.x, b.x) - reach)))
	var x1 := mini(w - 1, int(ceil(maxf(a.x, b.x) + reach)))
	var y0 := maxi(0, int(floor(minf(a.y, b.y) - reach)))
	var y1 := mini(h - 1, int(ceil(maxf(a.y, b.y) + reach)))
	var ab := b - a
	var len2 := ab.length_squared()
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0) if len2 > 0.0 else 0.0
			var d := p.distance_to(a + ab * t)
			var c := clampf(half + 0.5 - d, 0.0, 1.0)
			var i := y * w + x
			cover[i] = maxf(cover[i], c)
