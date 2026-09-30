extends Node
## "Palette": every color and tempo lives here and nowhere else.
##
## One family. Everything is Yggdrasil: pale, severe, thin light on a deep
## ground. The instruments are magic circles in the same register; gold is
## reserved for what is live or frontmost.

signal changed

## The one face for every label: a thin condensed sans, uppercase and
## letterspaced, from the system: Avenir Next Condensed on macOS. Linux has
## no Avenir, so the SystemFont lists fallbacks after it, tried in order:
## Nimbus Sans Narrow (a condensed grotesque) for labels, the ExtraLight
## and Thin cuts of Source Sans 3 and Noto Sans for display numerals, and
## DejaVu Sans Condensed last because every desktop has it. The lists are
## NERViewer's, so the clock and its numerals share one face there too.
## Labels get it through the project theme; drawn text takes it from here.
## DISPLAY is the ultra-light cut for large numerals (the clock).
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

## Light for a plain screen. The tree was tuned on a Retina panel: about
## two device pixels to a design pixel, so a 1.5 hairline is three pixels
## and its halo has room to show. A 1080p screen stretched from the
## 1440x900 design gets 1.15 to 1.2: the same hairline is one faint pixel,
## the halos a smudge, the twig tips pinpricks. `hair` widens a hairline
## back to the Mac's weight in pixels; `lift` (0..1) is how far the light
## is lifted to make up the rest: a glow under every bough, a bloom under
## every light. Keyed on the screen, never the OS: a Retina screen (scale
## 2, or two pixels to the design pixel) keeps 1.0 and 0.
const MAC_PX := 2.0
var hair := 1.0
var lift := 0.0


func _ready() -> void:
	var win := get_window()
	headroom = win.get_output_max_linear_value()
	win.output_max_linear_value_changed.connect(func(v: float) -> void:
		headroom = v
		_measure())
	win.size_changed.connect(_measure)
	win.dpi_changed.connect(_measure)   # moved to a screen of another density
	_measure()


## Device pixels per design pixel: the window's stretch, or the screen's
## own scale (2 on a Retina Mac) if that says more. Headroom fades the lift
## out too: a screen with light to spend past white has its own glow.
func _measure() -> void:
	var win := get_window()
	var px := maxf(win.get_final_transform().get_scale().x, DisplayServer.screen_get_scale(win.current_screen))
	var room := clampf(2.0 - headroom, 0.0, 1.0)
	hair = 1.0 + (clampf(MAC_PX / maxf(px, 0.01), 1.0, 1.8) - 1.0) * room
	lift = clampf((hair - 1.0) / 0.6, 0.0, 1.0)
	changed.emit()


func emit(c: Color, heat: float) -> Color:
	var k := 1.0 + (headroom - 1.0) * clampf(heat, 0.0, 1.0)
	return Color(c.r * k, c.g * k, c.b * k, c.a)


static func dim(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, alpha)
