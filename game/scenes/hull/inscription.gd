class_name Inscription
extends RefCounted
## The One Ring's inscription, curved along a ring. fonts/the_one_ring.ttf is
## a dingbat set, not a text face: s, t, u and v are the four lines of the
## verse as Tengwar strips. The text server rasterizes each strip close to
## the size it will show at (so its anti-aliasing does the work; the strokes
## are hairlines), and the strip is laid along the arc as a fan of textured
## quads, so it hugs the circle at any radius.
##
## Texture handles are looked up every draw, never kept: the text server
## drops and rebuilds its glyph atlases when oversampling changes (the window
## moving to a Retina screen, say), and a kept handle then draws a solid quad.

const FONT: FontFile = preload("res://fonts/the_one_ring.ttf")
const LINES := "stuv"
const PROBE := 100       # em used once to learn how tall a strip is per em
const OVERSAMPLE := 2.0  # rasterize this many times taller than shown
const SEGMENTS := 12     # quads per strip
const GAP_MIN := 8.0     # least arc between strips, px

var _ts: TextServer
var _rid: RID
var _ratio := 0.0        # strip height per em


func _init() -> void:
	_ts = TextServerManager.get_primary_interface()
	_rid = FONT.get_rids()[0]
	var tallest := 0.0
	for ch in LINES:
		var idx := _ts.font_get_glyph_index(_rid, PROBE, ch.unicode_at(0), 0)
		tallest = maxf(tallest, _ts.font_get_glyph_size(_rid, Vector2i(PROBE, 0), idx).y)
	_ratio = tallest / PROBE


## Lay the verse once around the ring: `height` px tall, standing on the
## circle of `radius` about `c`, starting at angle `rot`. The slack is shared
## out as equal gaps and a dot stands in each. If the ring is too small for
## the verse at that height, the strips shrink to fit.
func draw(ci: CanvasItem, c: Vector2, radius: float, rot: float, height: float, col: Color) -> void:
	if _ratio <= 0.0:
		return
	var em := maxi(8, roundi(height * OVERSAMPLE / _ratio))
	var sz := Vector2i(em, 0)
	# Fetch this frame's atlas placement for each strip.
	var texs: Array[RID] = []
	var uvs_px: Array[Rect2] = []
	var tex_sizes: Array[Vector2] = []
	for ch in LINES:
		var idx := _ts.font_get_glyph_index(_rid, em, ch.unicode_at(0), 0)
		_ts.font_render_glyph(_rid, sz, idx)
		var tex := _ts.font_get_glyph_texture_rid(_rid, sz, idx)
		var uv := _ts.font_get_glyph_uv_rect(_rid, sz, idx)
		var ts_size := _ts.font_get_glyph_texture_size(_rid, sz, idx)
		if not tex.is_valid() or ts_size.x <= 0.0 or uv.size.y <= 0.0:
			continue
		texs.append(tex)
		uvs_px.append(uv)
		tex_sizes.append(ts_size)
	var n := texs.size()
	if n == 0:
		return
	var circ := TAU * radius
	var total := 0.0
	for i in n:
		total += uvs_px[i].size.x / uvs_px[i].size.y * height
	var gap := (circ - total) / n
	if gap < GAP_MIN:
		height *= (circ - GAP_MIN * n) / total
		gap = GAP_MIN
	var colors := PackedColorArray([col, col, col, col])
	var item := ci.get_canvas_item()
	var ro := radius + height * 0.5
	var ri := radius - height * 0.5
	var a := rot
	for i in n:
		var uv := uvs_px[i]
		var tsz := tex_sizes[i]
		var da := uv.size.x / uv.size.y * height / radius
		var v0 := uv.position.y / tsz.y
		var v1 := uv.end.y / tsz.y
		for j in SEGMENTS:
			var f0 := float(j) / SEGMENTS
			var f1 := float(j + 1) / SEGMENTS
			var a0 := a + da * f0
			var a1 := a + da * f1
			var u0 := (uv.position.x + uv.size.x * f0) / tsz.x
			var u1 := (uv.position.x + uv.size.x * f1) / tsz.x
			var pts := PackedVector2Array([
				c + Vector2.from_angle(a0) * ro, c + Vector2.from_angle(a1) * ro,
				c + Vector2.from_angle(a1) * ri, c + Vector2.from_angle(a0) * ri])
			var quv := PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])
			RenderingServer.canvas_item_add_polygon(item, pts, colors, quv, texs[i])
		a += da
		ci.draw_circle(c + Vector2.from_angle(a + (gap * 0.5) / radius) * radius, 1.0, col)
		a += gap / radius
