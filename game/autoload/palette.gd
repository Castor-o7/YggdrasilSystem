extends Node
## "Palette": every color and tempo lives here and nowhere else.
##
## One family. Everything is Yggdrasil: pale, severe, thin light on a deep
## ground. The instruments are magic circles in the same register; gold is
## reserved for what is live or frontmost.

signal changed

## The one face for every label: a thin condensed sans, uppercase and
## letterspaced, from the system (Avenir Next Condensed). Labels get it
## through the project theme; drawn text takes it from here. DISPLAY is
## the ultra-light cut for large numerals (the clock).
const FONT: Font = preload("res://fonts/ui.tres")
const DISPLAY: Font = preload("res://fonts/display.tres")

const VOID := {
	"ground": Color("#05070D"),
	"frame": Color("#6F7FA8"),
	"light": Color("#DCE6FF"),
	"core": Color("#F2D48A"),
	"cool": Color("#9EF0C8"),
	"alarm": Color("#FF7A1A"),
	"breath_period": 10.0,
}



func color(key: String) -> Color:
	return VOID[key]


func breath_period() -> float:
	return VOID["breath_period"]


## The one slow breath, 0..1 and back, shared by everything that breathes.
func breath() -> float:
	var period := breath_period()
	var phase := fmod(Time.get_ticks_msec() / 1000.0, period) / period
	return 0.5 - 0.5 * cos(TAU * phase)


## Light past white. The window asks macOS for HDR output (project
## setting) and `headroom` is how far above SDR white this screen can go
## right now: 1.0 at full brightness, up to 2.0 on this panel as the
## brightness slider comes down. `emit` scales a color toward that limit
## by its heat, so at 1.0 every color is exactly itself and nothing
## shifts hue; only when there is room does what is live burn brighter.
## Reserved, like gold, for the few true light sources: the OS node, the
## frontmost bud, the star heads, the warp seam's core.
var headroom := 1.0


func _ready() -> void:
	var win := get_window()
	headroom = win.get_output_max_linear_value()
	win.output_max_linear_value_changed.connect(func(v: float) -> void:
		headroom = v
		changed.emit())


func emit(c: Color, heat: float) -> Color:
	var k := 1.0 + (headroom - 1.0) * clampf(heat, 0.0, 1.0)
	return Color(c.r * k, c.g * k, c.b * k, c.a)


static func dim(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, alpha)
