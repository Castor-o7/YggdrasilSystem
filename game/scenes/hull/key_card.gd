extends Node2D
## The key card: every key the cockpit answers, on a card over the void.
## ? or F1 brings it up; any key or a click on it puts it away. KEYS is the
## one list the card draws from, and tools/keys_probe.gd checks it against
## the keycodes main.gd's _unhandled_key_input matches, so the card cannot
## quietly fall behind the keys.

const FADE := 0.25
const W := 600.0
const PAD := 26.0
const ROW := 19.0
const TITLE_SIZE := 13
const TEXT_SIZE := 11
const CORNER := 16.0
const KEY_COL := 58.0          # design px from a column's left to its text

## [keycodes, what the card prints for them, what they do], in groups.
## The two gear columns are drawn side by side.
const KEYS := {
	"display": [
		[[KEY_H], "H", "stow or show the HUD"],
		[[KEY_C], "C", "stow or show the chrono"],
		[[KEY_T], "T", "stow or show the tree"],
		[[KEY_Z], "Z", "zen on or off"],
		[[KEY_B], "B", "desktop mode on or off"],
		[[KEY_G], "G", "garage: drag the instruments"],
		[[KEY_W], "W", "fake wallpaper (windowed)"],
		[[KEY_S], "S", "save a screenshot"],
		[[KEY_SLASH, KEY_F1], "? F1", "this card"],
		[[KEY_Q, KEY_ESCAPE], "Q Esc", "quit, zen handed back"],
	],
	"states": [
		[[KEY_1], "1", "idle"],
		[[KEY_2], "2", "cruise"],
		[[KEY_3], "3", "ether"],
		[[KEY_4], "4", "nebula"],
		[[KEY_5], "5", "ring"],
	],
	"sequences": [
		[[KEY_6], "6", "gate"],
		[[KEY_7], "7", "warp"],
		[[KEY_8], "8", "debris"],
		[[KEY_9], "9", "squall"],
		[[KEY_0], "0", "arrival"],
		[[KEY_MINUS], "−", "departure (berthed)"],
		[[KEY_EQUAL], "=", "the great ship"],
	],
	"voyage": [
		[[KEY_QUOTELEFT], "`", "backtick: Voyage, the autopilot"],
		[[KEY_ASCIITILDE], "~", "tilde: Voyage's next movement"],
	],
}

var shown := false
var _alpha := 0.0
var _font: Font


func _ready() -> void:
	_font = Palette.FONT
	z_index = 10
	visible = false


func set_shown(on: bool) -> void:
	shown = on
	Pace.stir(FADE + 0.1)


## Every keycode on the card, for tools/keys_probe.gd.
static func keycodes() -> Array:
	var out := []
	for group in KEYS.values():
		for entry in group:
			out.append_array(entry[0])
	return out


## The card in canvas coordinates, centred on the view.
func rect() -> Rect2:
	var h := _height()
	var c := get_viewport_rect().size * 0.5
	return Rect2(c - Vector2(W, h) * 0.5, Vector2(W, h))


func _height() -> float:
	var left: int = KEYS["display"].size() + 1 + KEYS["voyage"].size() + 1
	var right: int = KEYS["states"].size() + 1 + KEYS["sequences"].size() + 1
	return PAD * 2.0 + 28.0 + ROW * maxi(left, right)


func _process(dt: float) -> void:
	var target := 1.0 if shown else 0.0
	if _alpha == target:
		return
	_alpha = move_toward(_alpha, target, dt / FADE)
	visible = _alpha > 0.0
	queue_redraw()


func _draw() -> void:
	var r := rect()
	var ground := Palette.color("ground")
	var frame := Palette.color("frame")
	var light := Palette.color("light")
	var gold := Palette.color("core")
	draw_rect(r, Palette.dim(ground, 0.86 * _alpha))
	draw_rect(r, Palette.dim(frame, 0.45 * _alpha), false, 1.0, true)
	_corners(r, Palette.dim(gold, 0.8 * _alpha))
	var y := r.position.y + PAD + TITLE_SIZE
	draw_string(_font, Vector2(r.position.x + PAD, y), "K E Y S", HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, Palette.dim(gold, _alpha))
	draw_string(_font, Vector2(r.end.x - PAD - 200.0, y), "any key puts this away", HORIZONTAL_ALIGNMENT_RIGHT, 200.0, TEXT_SIZE - 1, Palette.dim(frame, 0.9 * _alpha))
	var top := y + 28.0
	var half := (W - PAD * 2.0) * 0.5
	var lx := r.position.x + PAD
	var rx := lx + half + 12.0
	var ly := _group(lx, top, "THE COCKPIT", KEYS["display"], frame, light, gold)
	_group(lx, ly + ROW, "VOYAGE", KEYS["voyage"], frame, light, gold)
	var ry := _group(rx, top, "GEARS: STATES", KEYS["states"], frame, light, gold)
	_group(rx, ry + ROW, "GEARS: SEQUENCES", KEYS["sequences"], frame, light, gold)


## A heading and its rows; returns the y below the last row.
func _group(x: float, y: float, heading: String, rows: Array, frame: Color, light: Color, gold: Color) -> float:
	draw_string(_font, Vector2(x, y), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE - 1, Palette.dim(frame, _alpha))
	for entry in rows:
		y += ROW
		draw_string(_font, Vector2(x, y), entry[1], HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, Palette.dim(gold, 0.95 * _alpha))
		draw_string(_font, Vector2(x + KEY_COL, y), entry[2], HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, Palette.dim(light, 0.85 * _alpha))
	return y + ROW * 0.5


## Bracket ticks at the corners, as the zen frames hold a window.
func _corners(r: Rect2, col: Color) -> void:
	for c in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var sx := 1.0 if c.x == r.position.x else -1.0
		var sy := 1.0 if c.y == r.position.y else -1.0
		draw_line(c, c + Vector2(sx * CORNER, 0.0), col, 2.0, true)
		draw_line(c, c + Vector2(0.0, sy * CORNER), col, 2.0, true)
