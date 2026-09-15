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
## Star trails are this much travel long (doubled 2026-09-10 so cruise
## wears its speed).
const STREAK_TIME := 0.8
## The bow's bearing places the vanishing point on an arc this far from
## the frame's center.
const VP_RADIUS := 120.0
## When the bow swings, the fabric slides against it: near layer more.
const NEAR_YAW := 0.5
const FAR_YAW := 0.15
const FAR_ROT := PI / 6.0
## The nebula (gear 4) lives in the shader; it eases in and out over this long.
const NEBULA_DISSOLVE := 1.5
## The ring plane (gear 5), also in the shader: a flat field of particles
## the ship flies just above. Its world runs PLANE_RATE units per unit of
## depth travelled (the plane is near, the stars are far), wraps on a
## multiple of its cell, and streaks PLANE_STREAK seconds of motion.
const RING_DISSOLVE := 1.5
const PLANE_RATE := 250.0
const PLANE_CELL := 3.0
const PLANE_STREAK := 0.15

const DriveScript := preload("res://scenes/void/drive.gd")

@onready var drive: DriveScript = $Drive
@onready var voyage: Node = $Voyage

var _mat: ShaderMaterial
var travel := 0.0     # depth crossed, wraps each 1.0
## The clouds move at CLOUD_RATE of the stars' travel and wrap on their
## own period; sharing `travel` made every cloud slice jump 0.3 in depth
## when it wrapped (found 2026-09-10: a frame cut in the nebula).
const CLOUD_RATE := 0.7
var cloud_travel := 0.0
## The shader's clock wraps on the period every rhythm in it divides
## (see PULSE_BASE there); the engine's TIME rolls over hourly and cut them.
const CLOCK_PERIOD := TAU / 0.05
var _nebula := 0.0
var _ring := 0.0
var _plane := 0.0


func _ready() -> void:
	_mat = material as ShaderMaterial
	_mat.set_shader_parameter("ground", Palette.color("ground"))
	_mat.set_shader_parameter("line_color", Palette.color("frame"))
	_mat.set_shader_parameter("light_color", Palette.color("light"))
	_mat.set_shader_parameter("gold_color", Palette.color("core"))
	_mat.set_shader_parameter("cool_color", Palette.color("cool"))
	_mat.set_shader_parameter("alarm_color", Palette.color("alarm"))
	resized.connect(_on_resized)
	# Main is a Node2D, so this rect's full-frame anchors have nothing to
	# bind to and it would stay at its saved 1440x900. Follow the viewport
	# instead, as the hull does; over the desktop with the Dock and menu
	# bar showing the frame is wider than 16:10, and the void stopped 136
	# design px short of the right edge (found by Josh 2026-09-11).
	get_viewport().size_changed.connect(_fit)
	_fit()
	_on_resized()
	# A still rendered at a later moment (the shots tool) has drifted that
	# long at idle.
	_travel(time_offset)


func _fit() -> void:
	var s := get_viewport_rect().size
	if size != s:
		size = s


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
	cloud_travel = fposmod(cloud_travel + rate() * dt * CLOUD_RATE, 1.0)


func _process(dt: float) -> void:
	_travel(dt)
	var lean := vp() - size * 0.5
	_nebula = move_toward(_nebula, 1.0 if drive.gear == drive.NEBULA else 0.0, dt / NEBULA_DISSOLVE)
	_mat.set_shader_parameter("nebula", _nebula)
	_mat.set_shader_parameter("cloud_travel", cloud_travel)
	_ring = move_toward(_ring, 1.0 if drive.gear == drive.RING else 0.0, dt / RING_DISSOLVE)
	_plane = fposmod(_plane + rate() * dt * PLANE_RATE, PLANE_CELL * 1024.0)
	_mat.set_shader_parameter("ring", _ring)
	_mat.set_shader_parameter("plane_travel", _plane)
	_mat.set_shader_parameter("plane_smear", rate() * PLANE_RATE * PLANE_STREAK)
	_mat.set_shader_parameter("breath", Palette.breath())
	_mat.set_shader_parameter("headroom", Palette.headroom)
	_mat.set_shader_parameter("clock", fposmod(Time.get_ticks_msec() / 1000.0 + time_offset, CLOCK_PERIOD))
	_mat.set_shader_parameter("vp", vp())
	_mat.set_shader_parameter("travel", travel)
	_mat.set_shader_parameter("blur", rate() * STREAK_TIME)
	_mat.set_shader_parameter("near_off", lean * NEAR_YAW)
	_mat.set_shader_parameter("far_off", lean.rotated(FAR_ROT) * FAR_YAW)
	_mat.set_shader_parameter("heading", drive.direction())
	# The warp seam: while the jump runs, the field inside the seam is the
	# next seed; the seam is a ring growing from the vanishing point until
	# it has passed the farthest corner.
	var seam := -1.0
	var glow := 0.0
	if drive.gear == drive.WARP and drive.phase == "sweep":
		var v := vp()
		var reach := 0.0
		for corner in [Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]:
			reach = maxf(reach, v.distance_to(corner))
		seam = lerpf(0.0, reach + 60.0, smoothstep(0.0, 1.0, drive.sweep))
		glow = sin(PI * drive.sweep)
	_mat.set_shader_parameter("seed_a", drive.seed)
	_mat.set_shader_parameter("seed_b", drive.seed_next)
	_mat.set_shader_parameter("sweep", seam)
	_mat.set_shader_parameter("sweep_glow", glow)
