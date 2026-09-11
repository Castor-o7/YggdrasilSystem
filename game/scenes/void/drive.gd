extends Node
## The drive: the gearbox of movements. The pilot selects a gear with the
## number keys and the void answers: a speed, a heading, and for some
## gears a set piece. Nothing cuts. Speed opens and closes like a throttle
## and the heading swings with inertia, so a shift is felt, never seen as
## a jump. Boot is always idle: a ship that has been drifting. The gear is
## not saved. Decided with Josh 2026-09-10; the movements are the source
## material put to work (Bebop's gates, Outlaw Star's ether, Panzer
## Dragoon's ruins, Homeworld's plane of light) one gear at a time.
##
## Two kinds of gear. A state (idle, cruise, ether, ruins) holds until the
## next shift. A sequence (gate, warp) runs its phases and settles into
## cruise by itself. Set pieces (gate.gd, ether.gd, ruins.gd) read `gear`,
## `phase` and `phase_t` and draw; the shader reads speed, heading, streak
## and the warp seam through Void.
##
## Speed is in design pixels per second by tradition; Void turns it into
## depth per second (see Void.SPEED_SCALE). The heading is the bow's
## bearing: where the vanishing point sits on its arc around the center.

signal shifted(gear: int)

const IDLE := 1
const CRUISE := 2
const GATE := 3
const ETHER := 4
const RUINS := 5
const WARP := 6

## Per gear: the name and the motes' speed at rest.
const GEARS := {
	IDLE: {"name": "idle", "speed": 2.5},
	CRUISE: {"name": "cruise", "speed": 36.0},
	GATE: {"name": "gate", "speed": 90.0},
	ETHER: {"name": "ether", "speed": 60.0},
	RUINS: {"name": "ruins", "speed": 30.0},
	WARP: {"name": "warp", "speed": 0.0},
}

## The gate: it drifts in and grows for APPROACH seconds, we pass through,
## hyperspace holds for TRANSIT, the tunnel thins for RETURN, then cruise.
const GATE_APPROACH := 9.0
const GATE_TRANSIT := 12.0
const GATE_RETURN := 5.0
const GATE_TRANSIT_SPEED := 420.0
## Warp: the drive stops (CHARGE), a plane of light sweeps the frame and
## rewrites the stars behind it (SWEEP), and the ship is elsewhere, on a
## new course, opening up to cruise (ARRIVE).
const WARP_CHARGE := 4.0
const WARP_SWEEP := 3.0
const WARP_ARRIVE := 3.0

## The throttle: per second, how fast speed closes on its target. At 0.5
## a shift is most of the way there in four seconds. Hyperspace and the
## warp's stop are harder.
const THROTTLE_RATE := 0.5
const THROTTLE_HARD := 1.2
## Course corrections settle at this rate (per second); a change of
## frontmost app swings the bow over ten seconds or so.
const TURN_RATE := 0.25
## The default bearing: the bow a little up and to the right of center.
const COURSE := deg_to_rad(-29.0)
## How far a course correction can lean off the default course.
const COURSE_LEAN := deg_to_rad(22.0)
## A warp arrives on a course this far off the default, either way.
const WARP_LEAN := deg_to_rad(45.0)
## Cruise opens up to this much faster under a full core of workspace CPU.
## Idle has the engine off and ignores the workspace.
const CRUISE_THROTTLE := 0.35

var gear := IDLE
var speed: float = GEARS[IDLE]["speed"]
var heading := COURSE          # radians, the bow's bearing
var phase := ""                # sequences: approach, transit, return; charge, sweep, arrive
var phase_t := 0.0             # seconds into the phase
## The star field's seed and, during a warp sweep, the one being written.
var seed := 0.0
var seed_next := 0.0
## Warp sweep progress 0..1 while phase is "sweep".
var sweep := 0.0

var _course := COURSE
var _target_speed: float = GEARS[IDLE]["speed"]
var _rate := THROTTLE_RATE
var _frontmost := ""
var _load := 0.0               # summed workspace CPU, fraction of one core
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	Workspace.changed.connect(_on_workspace)


## Select a gear. Unknown gears are ignored, so a key for a movement that
## is not built does nothing. A sequence can be left mid-way by any shift;
## its set piece dissolves rather than vanishing.
func shift(to: int) -> bool:
	if not GEARS.has(to) or to == gear:
		return false
	gear = to
	phase_t = 0.0
	match to:
		GATE: phase = "approach"
		WARP: phase = "charge"
		_: phase = ""
	print("drive: %s" % GEARS[to]["name"])
	shifted.emit(gear)
	return true


func gear_name() -> String:
	return GEARS[gear]["name"]


func is_sequence() -> bool:
	return gear == GATE or gear == WARP


func _settle(to: int) -> void:
	gear = to
	phase = ""
	phase_t = 0.0
	print("drive: %s (settled)" % GEARS[to]["name"])
	shifted.emit(gear)


func _on_workspace() -> void:
	var load := 0.0
	var front := ""
	for app in Workspace.alive_apps():
		load += app.cpu
		if app.active:
			front = app.id
	_load = clampf(load, 0.0, 1.0)
	# A new frontmost app is a course correction: the bow leans a little,
	# by an angle that is the app's own, so the same app always means the
	# same course and Finder never feels like Chrome.
	if not front.is_empty() and front != _frontmost:
		_frontmost = front
		var lean := (float(front.hash() % 1000) / 999.0) * 2.0 - 1.0
		_course = COURSE + lean * COURSE_LEAN


func _process(dt: float) -> void:
	_rate = THROTTLE_RATE
	match gear:
		CRUISE:
			_target_speed = GEARS[CRUISE]["speed"] * (1.0 + CRUISE_THROTTLE * _load)
		GATE:
			_advance_gate(dt)
		WARP:
			_advance_warp(dt)
		_:
			_target_speed = GEARS[gear]["speed"]
	speed = lerpf(speed, _target_speed, 1.0 - exp(-_rate * dt))
	heading = lerp_angle(heading, _course, 1.0 - exp(-TURN_RATE * dt))


func _advance_gate(dt: float) -> void:
	phase_t += dt
	Pace.stir(0.5)
	match phase:
		"approach":
			_target_speed = GEARS[GATE]["speed"]
			if phase_t >= GATE_APPROACH:
				phase = "transit"
				phase_t = 0.0
		"transit":
			_target_speed = GATE_TRANSIT_SPEED
			_rate = THROTTLE_HARD
			if phase_t >= GATE_TRANSIT:
				phase = "return"
				phase_t = 0.0
		"return":
			_target_speed = GEARS[CRUISE]["speed"]
			if phase_t >= GATE_RETURN:
				_settle(CRUISE)


func _advance_warp(dt: float) -> void:
	phase_t += dt
	match phase:
		"charge":
			_target_speed = 0.0
			_rate = THROTTLE_HARD
			if phase_t >= WARP_CHARGE:
				phase = "sweep"
				phase_t = 0.0
				sweep = 0.0
				seed_next = float(_rng.randi_range(1, 1000)) * 37.0
		"sweep":
			_target_speed = 0.0
			Pace.stir(0.5)
			sweep = clampf(phase_t / WARP_SWEEP, 0.0, 1.0)
			if phase_t >= WARP_SWEEP:
				# Space rewritten: new stars behind the plane, a new course ahead.
				seed = seed_next
				_course = COURSE + _rng.randf_range(-1.0, 1.0) * WARP_LEAN
				phase = "arrive"
				phase_t = 0.0
		"arrive":
			_target_speed = GEARS[CRUISE]["speed"]
			if phase_t >= WARP_ARRIVE:
				_settle(CRUISE)


## Unit vector of the bow's bearing.
func direction() -> Vector2:
	return Vector2.from_angle(heading)
