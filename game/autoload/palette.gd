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


static func dim(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, alpha)
