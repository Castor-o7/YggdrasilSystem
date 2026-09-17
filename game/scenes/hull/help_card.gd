class_name HelpCard
extends Control
## The keys, on a card over the middle of the void. Shown by ? (or by
## Help > Yggdrasil Keys in the menu bar) and put away the same way; it
## fades rather than pops, takes no clicks, and draws once per fade step,
## so while it is away it costs nothing.

const FADE := 0.25
const TITLE := "THE HELM"
const FOOT := "?  PUTS THIS CARD AWAY"
## [keys, what they do]; an empty pair is a gap between groups.
const KEYS := [
	["B", "DESKTOP MODE: OVER THE DESKTOP, OR IN A WINDOW"],
	["Z", "ZEN: DOCK AND MENU BAR HIDE, TERMINAL DISSOLVES"],
	["H", "STOW OR SHOW THE HUD (NERVIEWER WITH IT)"],
	["T", "STOW OR SHOW THE TREE"],
	["G", "GARAGE: DRAG THE INSTRUMENTS BETWEEN SLOTS"],
	["W", "FAKE WALLPAPER BEHIND THE VOID (WINDOWED ONLY)"],
	["", ""],
	["`", "VOYAGE, THE AUTOPILOT, ON OR OFF"],
	["~", "SKIP TO THE VOYAGE'S NEXT MOVEMENT"],
	["1 – 5", "TAKE THE HELM: IDLE, CRUISE, ETHER, NEBULA, RING"],
	["6 – 0", "SEQUENCES: GATE, WARP, DEBRIS, SQUALL, ARRIVAL"],
	["–   =", "DEPARTURE (FROM A BERTH)   ·   THE GREAT SHIP"],
	["", ""],
	["S", "SAVE A SCREENSHOT TO PICTURES"],
	["Q  ESC", "QUIT; ZEN HANDS THE DESKTOP BACK"],
]
const ROW := 22.0
const KEY_COLUMN := 92.0
const PAD := 30.0
const WIDTH := 520.0

var shown := false
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	visible = false
	get_viewport().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	queue_redraw()


func toggle() -> void:
	shown = not shown
	if _tween:
		_tween.kill()
	visible = true
	Pace.stir(FADE + 0.1)
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0 if shown else 0.0, FADE)
	if not shown:
		_tween.tween_callback(func() -> void: visible = false)


func _draw() -> void:
	var frame := Palette.color("frame")
	var light := Palette.color("light")
	var core := Palette.color("core")
	var font := Palette.FONT
	var height := PAD * 2.0 + 34.0 + KEYS.size() * ROW + 26.0
	var card := Rect2((size - Vector2(WIDTH, height)) * 0.5, Vector2(WIDTH, height))
	draw_rect(card, Palette.dim(Palette.color("ground"), 0.9), true)
	# Corner brackets, not a box, as everywhere else.
	for sx in [0.0, 1.0]:
		for sy in [0.0, 1.0]:
			var c := card.position + Vector2(sx * card.size.x, sy * card.size.y)
			draw_line(c, c + Vector2(18.0 - 36.0 * sx, 0.0), Palette.dim(frame, 0.85), 1.0, true)
			draw_line(c, c + Vector2(0.0, 18.0 - 36.0 * sy), Palette.dim(frame, 0.85), 1.0, true)
	var x := card.position.x + PAD
	var y := card.position.y + PAD + 12.0
	draw_string(font, Vector2(x, y), TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.dim(core, 0.9))
	draw_line(Vector2(x, y + 10.0), Vector2(card.end.x - PAD, y + 10.0), Palette.dim(frame, 0.3), 1.0, true)
	y += 34.0
	for pair in KEYS:
		if pair[0] != "":
			draw_string(font, Vector2(x, y), pair[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.dim(light, 0.95))
			draw_string(font, Vector2(x + KEY_COLUMN, y), pair[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.dim(frame, 0.95))
		y += ROW
	draw_string(font, Vector2(x, card.end.y - PAD + 8.0), FOOT, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Palette.dim(frame, 0.6))
