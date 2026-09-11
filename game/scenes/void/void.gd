extends ColorRect
## The void layer: a full-frame quad running the void shader. Feeds it the
## frame size, the palette, the shared breath, and the flight: the drive
## gives a speed and the bow's bearing; this node turns them into depth
## travelled and a vanishing point, which the shader's starfield and the
## set pieces share. Forward flight, decided 2026-09-10 on Josh's note
## that stars sliding diagonally made no sense for a ship moving ahead
## (reference: the Starfield screensaver).

@export var time_offset := 0.0

## Depth per second per px/s of drive speed: at cruise (36) a star crosses
## from far to near in about 25 s; in hyperspace (420) in about two.
const SPEED_SCALE := 900.0
## Mote streaks are this much travel long.
const STREAK_TIME := 0.4
## The bow's bearing places the vanishing point on an arc this far from
## the frame's center.
const VP_RADIUS := 120.0
## When the bow swings, the fabric slides against it: near layer more.
const NEAR_YAW := 0.5
const FAR_YAW := 0.15
const FAR_ROT := PI / 6.0

const DriveScript := preload("res://scenes/void/drive.gd")

@onready var drive: DriveScript = $Drive

var _mat: ShaderMaterial
var travel := 0.0     # depth crossed, wraps each 1.0


func _ready() -> void:
	_mat = material as ShaderMaterial
	_mat.set_shader_parameter("ground", Palette.color("ground"))
	_mat.set_shader_parameter("line_color", Palette.color("frame"))
	_mat.set_shader_parameter("light_color", Palette.color("light"))
	_mat.set_shader_parameter("gold_color", Palette.color("core"))
	_mat.set_shader_parameter("time_offset", time_offset)
	resized.connect(_on_resized)
	_on_resized()
	# A still rendered at a later moment (the shots tool) has drifted that
	# long at idle.
	_travel(time_offset)


func _on_resized() -> void:
	_mat.set_shader_parameter("res", size)


## Opaque ground in windowed mode; over the desktop the void is only light.
func set_ground_alpha(a: float) -> void:
	_mat.set_shader_parameter("ground_alpha", a)


## Where the bow points: the vanishing point, in this node's coordinates.
func vp() -> Vector2:
	return size * 0.5 + drive.direction() * VP_RADIUS


## Depth per second at the drive's current speed.
func rate() -> float:
	return drive.speed / SPEED_SCALE


func _travel(dt: float) -> void:
	travel = fposmod(travel + rate() * dt, 1.0)


func _process(dt: float) -> void:
	_travel(dt)
	var lean := vp() - size * 0.5
	_mat.set_shader_parameter("breath", Palette.breath())
	_mat.set_shader_parameter("vp", vp())
	_mat.set_shader_parameter("travel", travel)
	_mat.set_shader_parameter("blur", rate() * STREAK_TIME)
	_mat.set_shader_parameter("near_off", lean * NEAR_YAW)
	_mat.set_shader_parameter("far_off", lean.rotated(FAR_ROT) * FAR_YAW)
	_mat.set_shader_parameter("heading", drive.direction())
	# The warp seam: while the plane of light sweeps, the field behind it
	# is the next seed; the seam runs from behind the ship to ahead of it.
	var seam := -1.0e9
	var glow := 0.0
	if drive.gear == drive.WARP and drive.phase == "sweep":
		var reach := size.length() * 0.5 + 60.0
		seam = lerpf(-reach, reach, smoothstep(0.0, 1.0, drive.sweep))
		glow = sin(PI * drive.sweep)
	_mat.set_shader_parameter("seed_a", drive.seed)
	_mat.set_shader_parameter("seed_b", drive.seed_next)
	_mat.set_shader_parameter("sweep", seam)
	_mat.set_shader_parameter("sweep_glow", glow)
