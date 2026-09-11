extends Node
## Voyage: the autopilot. With it on, the ship works the gearbox itself
## in the grammar the movements were built in, so the void travels all
## day with the keys untouched. Proposed by Josh 2026-09-10 and built
## the same night.
##
## Cruise is the spine. A leg is a state (cruise, ether, nebula, ring,
## rarely an idle drift) held for 6, 9 or 12 minutes, chosen per leg,
## never the same state twice running. Leaving a leg there is a chance
## of a passage first (gate, warp, debris, the great ship), never the
## same one twice running; every passage lands in cruise. An ether leg
## has a chance of a squall somewhere in its middle third, which clears
## back into ether. After 45 to 90 minutes under way the next leg is a
## port call: arrival, 2 to 3 minutes berthed, departure, and the clock
## resets. Course corrections from the frontmost app work as ever:
## Voyage steers the gearbox, not the bow.
##
## Backtick toggles it; tilde ends the current movement and lets Voyage
## choose the next; any gear key takes the helm (Voyage ends, the gear
## runs). It does not survive a restart: boot is idle, drifting. Every
## choice is printed with its reason, so the log shows it think.

const LEG_MINUTES := [6.0, 9.0, 12.0]
const PASSAGE_CHANCE := 0.6
const SQUALL_CHANCE := 0.5
const PORT_AFTER := [45.0, 90.0]   # minutes under way before a port call
const BERTH := [2.0, 3.0]          # minutes berthed
## The first leg begins this long after Voyage starts, if the ship is
## not mid-sequence (then it waits for the settle).
const FIRST_LEG := 2.0

const DriveScript := preload("res://scenes/void/drive.gd")

var on := false

@onready var _drive: DriveScript = get_parent().get_node("Drive")

## What we are waiting on: "" (a leg is running), "first", "passage",
## "squall", "arrive", "berth", "depart".
var _waiting := ""
var _leg_gear := 0
var _leg_left := 0.0
var _squall_in := -1.0        # seconds of leg left when the squall strikes, or -1
var _last_passage := 0
var _under_way := 0.0
var _port_at := 0.0
var _berth_left := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_drive.shifted.connect(_on_shifted)


func toggle() -> void:
	if on:
		stop()
	else:
		start()


func start() -> void:
	if on:
		return
	on = true
	_under_way = 0.0
	_port_at = _rng.randf_range(PORT_AFTER[0], PORT_AFTER[1]) * 60.0
	_last_passage = 0
	print("voyage: under way; port call in %d min" % int(_port_at / 60.0))
	if _drive.is_sequence():
		_waiting = "passage"
		print("voyage: waiting for the %s to settle" % _drive.gear_name())
	else:
		_waiting = "first"
		_leg_left = FIRST_LEG


## The helm is taken: the ship holds whatever it is doing.
func stop() -> void:
	if not on:
		return
	on = false
	_waiting = ""
	print("voyage: helm taken")


## Tilde: end the current movement now and choose the next.
func skip() -> void:
	if not on:
		return
	match _waiting:
		"", "first":
			print("voyage: skip")
			_end_leg()
		"berth":
			print("voyage: skip, casting off")
			_depart()
		_:
			print("voyage: skip, leaving the %s" % _drive.gear_name())
			_next_leg()


func _process(dt: float) -> void:
	if not on:
		return
	_under_way += dt
	match _waiting:
		"", "first":
			_leg_left -= dt
			if _waiting == "" and _squall_in >= 0.0 and _leg_left <= _squall_in:
				_squall_in = -1.0
				_waiting = "squall"
				print("voyage: weather, a squall")
				_drive.shift(_drive.SQUALL)
			elif _leg_left <= 0.0:
				if _waiting == "first":
					_next_leg()
				else:
					_end_leg()
		"berth":
			_berth_left -= dt
			if _berth_left <= 0.0:
				_depart()


## A leg is over: a passage first, most of the time.
func _end_leg() -> void:
	if _rng.randf() < PASSAGE_CHANCE:
		var passage := _pick({
			_drive.GATE: 3, _drive.WARP: 2, _drive.DEBRIS: 3, _drive.SHIP: 2}, _last_passage)
		_last_passage = passage
		_waiting = "passage"
		print("voyage: passage, the %s" % _drive.GEARS[passage]["name"])
		_drive.shift(passage)
	else:
		_next_leg()


## The next leg: a port call when it is time, otherwise a state held for
## a while, with the weather decided now.
func _next_leg() -> void:
	if _under_way >= _port_at:
		_waiting = "arrive"
		print("voyage: port call after %d min under way" % int(_under_way / 60.0))
		_drive.shift(_drive.ARRIVE)
		return
	_leg_gear = _pick({
		_drive.CRUISE: 4, _drive.ETHER: 3, _drive.NEBULA: 2, _drive.RING: 2, _drive.IDLE: 1}, _leg_gear)
	var minutes: float = LEG_MINUTES[_rng.randi_range(0, LEG_MINUTES.size() - 1)]
	_leg_left = minutes * 60.0
	_squall_in = -1.0
	var note := ""
	if _leg_gear == _drive.ETHER and _rng.randf() < SQUALL_CHANCE:
		_squall_in = _leg_left * _rng.randf_range(1.0 / 3.0, 2.0 / 3.0)
		note = ", squall at %d:%02d" % [int((_leg_left - _squall_in) / 60.0), int(_leg_left - _squall_in) % 60]
	_waiting = ""
	print("voyage: leg, %s for %d min%s" % [_drive.GEARS[_leg_gear]["name"], int(minutes), note])
	_drive.shift(_leg_gear)


func _depart() -> void:
	_waiting = "depart"
	print("voyage: casting off")
	_drive.shift(_drive.DEPART)


## The drive shifted: under Voyage that is our own shift or a settle.
## Settles move the plan along; our own shifts are ignored.
func _on_shifted(gear: int) -> void:
	if not on or _drive.is_sequence():
		return
	match _waiting:
		"passage":
			_next_leg()
		"squall":
			_waiting = ""
			print("voyage: weather cleared, %d min of ether left" % int(_leg_left / 60.0))
		"arrive":
			if gear == _drive.IDLE and _drive.berthed:
				_waiting = "berth"
				_berth_left = _rng.randf_range(BERTH[0], BERTH[1]) * 60.0
				print("voyage: berthed for %d:%02d" % [int(_berth_left / 60.0), int(_berth_left) % 60])
		"depart":
			_under_way = 0.0
			_port_at = _rng.randf_range(PORT_AFTER[0], PORT_AFTER[1]) * 60.0
			print("voyage: under way again; next port call in %d min" % int(_port_at / 60.0))
			_next_leg()


## A weighted pick, never `avoid`.
func _pick(weights: Dictionary, avoid: int) -> int:
	var total := 0
	for g in weights:
		if g != avoid:
			total += weights[g]
	var r := _rng.randi_range(1, total)
	for g in weights:
		if g == avoid:
			continue
		r -= weights[g]
		if r <= 0:
			return g
	return weights.keys()[0]
