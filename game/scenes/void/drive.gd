extends Node
## The drive: the gearbox of movements. The pilot selects a gear with the
## number keys and the void answers: a speed, a heading, and for some
## gears a set piece. Nothing cuts. Speed opens and closes like a throttle
## and the heading swings with inertia, so a shift is felt, never seen as
## a jump. Boot is always idle: a ship that has been drifting. The gear is
## not saved. Decided with Josh 2026-09-10; the movements are the source
## material put to work (Bebop's gates, Outlaw Star's ether, the pale
## clouds every 90s series flew through, Bebop's ring plane, Homeworld's
## plane of light) one gear at a time.
##
## Two kinds of gear, and the keyboard says which: 1 to 5 are states
## (idle, cruise, ether, nebula, ring), which hold until the next shift;
## 6 to 0 and then minus and equals are sequences (gate, warp, debris,
## squall, arrival, departure, the great ship), which run their phases
## and settle by themselves: into cruise, or for the squall into ether,
## or for arrival into idle, berthed. Layout decided with Josh
## 2026-09-10 when the project was greenlit in full; fold and slingshot
## retired the same night on review and the two keys added. Set pieces
## (gate.gd, ether.gd, debris.gd, station.gd, ship.gd) read `gear`,
## `phase` and `phase_t` and draw; the shader reads speed, heading and
## the warp seam through Void.
##
## Speed is in design pixels per second by tradition; Void turns it into
## depth per second (see Void.SPEED_SCALE). The heading is the bow's
## bearing: where the vanishing point sits on its arc around the center.

signal shifted(gear: int)

const IDLE := 1
const CRUISE := 2
const ETHER := 3
const NEBULA := 4
const RING := 5
const GATE := 6
const WARP := 7
const DEBRIS := 8
const SQUALL := 9
const ARRIVE := 10
const DEPART := 11
const SHIP := 12

## Per gear: the name and the motes' speed at rest.
const GEARS := {
	IDLE: {"name": "idle", "speed": 2.5},
	CRUISE: {"name": "cruise", "speed": 36.0},
	ETHER: {"name": "ether", "speed": 60.0},
	NEBULA: {"name": "nebula", "speed": 22.0},
	RING: {"name": "ring", "speed": 44.0},
	GATE: {"name": "gate", "speed": 90.0},
	WARP: {"name": "warp", "speed": 0.0},
	DEBRIS: {"name": "debris", "speed": 24.0},
	SQUALL: {"name": "squall", "speed": 60.0},
	ARRIVE: {"name": "arrival", "speed": 30.0},
	DEPART: {"name": "departure", "speed": 0.0},
	SHIP: {"name": "great ship", "speed": 36.0},
}

## The gate: it drifts in and grows for APPROACH seconds, we pass through,
## hyperspace holds for TRANSIT, the tunnel thins for RETURN, then cruise.
const GATE_APPROACH := 9.0
const GATE_TRANSIT := 12.0
const GATE_RETURN := 5.0
const GATE_TRANSIT_SPEED := 420.0
## Warp: the drive stops and a point ahead is opened, hairline rings
## converging on it (CHARGE); new space blooms out of the point as a ring
## of light growing past the frame, the drive spiking for JUMP seconds so
## the stars stretch into the point (SWEEP); the ship is elsewhere, on a
## new course, opening up to cruise (ARRIVE). Reworked 2026-09-10 on
## review: the first cut's plane wiping across the frame read as a scan.
const WARP_CHARGE := 4.0
const WARP_SWEEP := 3.0
const WARP_ARRIVE := 3.0
const WARP_JUMP := 1.2
const WARP_JUMP_SPEED := 2400.0
const THROTTLE_JUMP := 3.0
## Debris passage (Star Wars, Star Fox, Outlaw Star): fragments appear
## ahead and the drive eases down (AHEAD); the field thickens and the bow
## weaves to thread it, a new lean every WEAVE seconds, alternating sides
## (THREAD); the field thins and the drive opens to cruise (CLEAR).
const DEBRIS_AHEAD := 5.0
const DEBRIS_THREAD := 14.0
const DEBRIS_CLEAR := 5.0
const DEBRIS_WEAVE := 3.0
const DEBRIS_LEAN := deg_to_rad(25.0)
## Ether squall (Outlaw Star's currents turned rough): the ribbons come
## in, dim and thicken (RISE); they thrash, discharges arc between them,
## the bow is shoved off course every SHOVE seconds and fights back, the
## drive surges and sags (SQUALL); it clears into calm ether (CLEAR).
const SQUALL_RISE := 6.0
const SQUALL_SQUALL := 12.0
const SQUALL_CLEAR := 6.0
const SQUALL_SHOVE := 2.0
const SQUALL_LEAN := deg_to_rad(20.0)
const SQUALL_SURGE := 0.4      # speed swing, as a fraction of ether's
const SQUALL_SURGE_RATE := 1.3 # radians per second of the swing
## Departure, the mirror of arrival, from a berth only: the port's lights
## go down cradle to hub (CAST), the drive opens gently and the station
## slides up over us as we pass beneath it (UNDERWAY), the stars streak up
## to cruise (OPEN).
const DEPART_CAST := 6.0
const DEPART_UNDERWAY := 8.0
const DEPART_OPEN := 6.0
## The great ship: a hull far bigger than ours overtakes from behind on a
## parallel course (OVERTAKE), slides past toward the vanishing point
## (PASS), and dwindles into it (AHEAD). Our course and speed never change.
const SHIP_OVERTAKE := 8.0
const SHIP_PASS := 14.0
const SHIP_AHEAD := 8.0
## Arrival: a light ahead resolves into a station (SIGHTING); the bow
## bends onto the berth's bearing and the drive eases to a crawl as the
## docking arm comes to the bow (APPROACH); the ship stops dead and the
## port answers, its guide lights coming up one by one (BERTH). Then idle,
## berthed: the stars hold and the station stays until the next shift.
## Reworked 2026-09-10 on the brass's note that 0 did not read as docking.
const ARRIVE_SIGHTING := 7.0
const ARRIVE_APPROACH := 24.0
const ARRIVE_BERTH := 6.0
const ARRIVE_CRAWL := 8.0

## The throttle: per second, how fast speed closes on its target. At 0.5
## a shift is most of the way there in four seconds. Hyperspace and the
## warp's stop are harder.
const THROTTLE_RATE := 0.5
const THROTTLE_HARD := 1.2
## Course corrections settle at this rate (per second); a change of
## frontmost app swings the bow over ten seconds or so. Threading debris
## and fighting a squall turn harder.
const TURN_RATE := 0.25
const TURN_HARD := 0.9
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
var phase := ""                # the sequence's phase, named per gear above
var phase_t := 0.0             # seconds into the phase
## The star field's seed and, during a warp sweep, the one being written.
var seed := 0.0
var seed_next := 0.0
## Warp sweep progress 0..1 while phase is "sweep".
var sweep := 0.0
## Which side the great ship passes on: 1 right, -1 left.
var ship_side := 1
## True from an arrival's berth until the next shift away from idle.
## Berthed, the drive is off: idle at zero, the stars holding.
var berthed := false
## The port's bearing, chosen at sighting; the bow bends onto it.
var berth_course := COURSE

var _course := COURSE
var _target_speed: float = GEARS[IDLE]["speed"]
var _rate := THROTTLE_RATE
var _turn := TURN_RATE
var _weave_side := 1
var _weave_t := 0.0            # seconds until the next lean or shove
var _frontmost := ""
var _load := 0.0               # summed workspace CPU, fraction of one core
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	Workspace.changed.connect(_on_workspace)


## Select a gear. Unknown gears are ignored, so a key for a movement that
## is not built does nothing; departure is ignored unless we are berthed.
## A sequence can be left mid-way by any shift; its set piece dissolves
## rather than vanishing.
func shift(to: int) -> bool:
	if not GEARS.has(to) or to == gear:
		return false
	if to == DEPART and not (gear == IDLE and berthed):
		return false
	gear = to
	phase_t = 0.0
	berthed = false
	match to:
		GATE: phase = "approach"
		WARP: phase = "charge"
		DEBRIS:
			phase = "ahead"
			_weave_t = 0.0
		SQUALL:
			phase = "rise"
			_weave_t = 0.0
		ARRIVE:
			phase = "sighting"
			berth_course = COURSE + _rng.randf_range(-1.0, 1.0) * COURSE_LEAN
		DEPART: phase = "cast"
		SHIP:
			phase = "overtake"
			ship_side = 1 if _rng.randi() % 2 == 0 else -1
		_: phase = ""
	print("drive: %s" % GEARS[to]["name"])
	shifted.emit(gear)
	return true


func gear_name() -> String:
	return GEARS[gear]["name"]


func is_sequence() -> bool:
	return gear >= GATE


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
	# Not while arriving or berthed: the port sets the course then.
	if not front.is_empty() and front != _frontmost and gear != ARRIVE and not berthed:
		_frontmost = front
		var lean := (float(front.hash() % 1000) / 999.0) * 2.0 - 1.0
		_course = COURSE + lean * COURSE_LEAN


func _process(dt: float) -> void:
	_rate = THROTTLE_RATE
	_turn = TURN_RATE
	match gear:
		CRUISE:
			_target_speed = GEARS[CRUISE]["speed"] * (1.0 + CRUISE_THROTTLE * _load)
		GATE:
			_advance_gate(dt)
		WARP:
			_advance_warp(dt)
		DEBRIS:
			_advance_debris(dt)
		SQUALL:
			_advance_squall(dt)
		ARRIVE:
			_advance_arrive(dt)
		DEPART:
			_advance_depart(dt)
		SHIP:
			_advance_ship(dt)
		IDLE:
			_target_speed = 0.0 if berthed else GEARS[IDLE]["speed"]
		_:
			_target_speed = GEARS[gear]["speed"]
	speed = lerpf(speed, _target_speed, 1.0 - exp(-_rate * dt))
	heading = lerp_angle(heading, _course, 1.0 - exp(-_turn * dt))


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
			# The jump: a hard spike, then dead still in the new field.
			_target_speed = WARP_JUMP_SPEED if phase_t < WARP_JUMP else 0.0
			_rate = THROTTLE_JUMP
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


func _advance_debris(dt: float) -> void:
	phase_t += dt
	Pace.stir(0.5)
	match phase:
		"ahead":
			_target_speed = GEARS[DEBRIS]["speed"]
			if phase_t >= DEBRIS_AHEAD:
				phase = "thread"
				phase_t = 0.0
		"thread":
			_target_speed = GEARS[DEBRIS]["speed"]
			_turn = TURN_HARD
			_weave_t -= dt
			if _weave_t <= 0.0:
				# The next lean, the other way, so the bow weaves.
				_weave_side = -_weave_side
				_course = COURSE + _weave_side * _rng.randf_range(0.5, 1.0) * DEBRIS_LEAN
				_weave_t = DEBRIS_WEAVE * _rng.randf_range(0.7, 1.3)
			if phase_t >= DEBRIS_THREAD:
				phase = "clear"
				phase_t = 0.0
				_course = COURSE
		"clear":
			_target_speed = GEARS[CRUISE]["speed"]
			if phase_t >= DEBRIS_CLEAR:
				_settle(CRUISE)


func _advance_squall(dt: float) -> void:
	phase_t += dt
	Pace.stir(0.5)
	match phase:
		"rise":
			_target_speed = GEARS[SQUALL]["speed"]
			if phase_t >= SQUALL_RISE:
				phase = "squall"
				phase_t = 0.0
		"squall":
			_target_speed = GEARS[SQUALL]["speed"] * (1.0 + SQUALL_SURGE * sin(phase_t * SQUALL_SURGE_RATE))
			_rate = THROTTLE_HARD
			_turn = TURN_HARD
			_weave_t -= dt
			if _weave_t <= 0.0:
				# Shoved off course; the bow fights back toward it.
				_course = COURSE + _rng.randf_range(-1.0, 1.0) * SQUALL_LEAN
				_weave_t = SQUALL_SHOVE * _rng.randf_range(0.6, 1.4)
			if phase_t >= SQUALL_SQUALL:
				phase = "clear"
				phase_t = 0.0
				_course = COURSE
		"clear":
			_target_speed = GEARS[ETHER]["speed"]
			if phase_t >= SQUALL_CLEAR:
				_settle(ETHER)


func _advance_arrive(dt: float) -> void:
	phase_t += dt
	match phase:
		"sighting":
			_target_speed = GEARS[ARRIVE]["speed"]
			if phase_t >= ARRIVE_SIGHTING:
				phase = "approach"
				phase_t = 0.0
				_course = berth_course
		"approach":
			_target_speed = ARRIVE_CRAWL
			if phase_t >= ARRIVE_APPROACH:
				phase = "berth"
				phase_t = 0.0
		"berth":
			_target_speed = 0.0
			_rate = THROTTLE_HARD
			if phase_t >= ARRIVE_BERTH:
				berthed = true
				_settle(IDLE)


func _advance_depart(dt: float) -> void:
	phase_t += dt
	match phase:
		"cast":
			_target_speed = 0.0
			if phase_t >= DEPART_CAST:
				phase = "underway"
				phase_t = 0.0
		"underway":
			_target_speed = ARRIVE_CRAWL
			if phase_t >= DEPART_UNDERWAY:
				phase = "open"
				phase_t = 0.0
		"open":
			_target_speed = GEARS[CRUISE]["speed"]
			if phase_t >= DEPART_OPEN:
				_settle(CRUISE)


func _advance_ship(dt: float) -> void:
	phase_t += dt
	_target_speed = GEARS[SHIP]["speed"]
	match phase:
		"overtake":
			if phase_t >= SHIP_OVERTAKE:
				phase = "pass"
				phase_t = 0.0
		"pass":
			if phase_t >= SHIP_PASS:
				phase = "ahead"
				phase_t = 0.0
		"ahead":
			if phase_t >= SHIP_AHEAD:
				_settle(CRUISE)


## Seconds since the great ship first showed, across its phases.
func ship_t() -> float:
	match phase:
		"overtake": return phase_t
		"pass": return SHIP_OVERTAKE + phase_t
		"ahead": return SHIP_OVERTAKE + SHIP_PASS + phase_t
	return 0.0


## Unit vector of the bow's bearing.
func direction() -> Vector2:
	return Vector2.from_angle(heading)
