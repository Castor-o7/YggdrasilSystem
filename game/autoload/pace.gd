extends Node
## "Pace": the frame rate governor. The cockpit lives on the desktop all
## day, so at rest it draws only as often as its slowest visible motion
## needs: the lattice drifts a pixel or two a second, the sigil rings turn
## about as fast. Anything quicker asks for more with stir(): a branch
## growing in, the zen paint chasing a dragged window. The highest live
## request wins, and a minimized window drops to a few frames a second.
##
## Measured 2026-09-09: at 60 fps the cockpit and WindowServer together
## cost most of a core on an M2; the cost scales with the frame rate.

const IDLE := 12
const AWAKE := 30
const FAST := 60
const MINIMIZED := 3

## The resting rate. Tools (the bench) set it; nothing else should.
var idle_fps := IDLE

var _requests: Array = []   # [until (ticks msec), fps]


func _ready() -> void:
	OS.low_processor_usage_mode = true
	Engine.max_fps = idle_fps


## Ask for at least `fps` for the next `seconds`. Repeated calls extend
## the same request rather than piling up.
func stir(seconds: float, fps: int = AWAKE) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	for r in _requests:
		if r[1] == fps:
			r[0] = maxi(r[0], until)
			return
	_requests.append([until, fps])


func current() -> int:
	return Engine.max_fps


func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec()
	var want := idle_fps
	var i := 0
	while i < _requests.size():
		if _requests[i][0] <= now:
			_requests.remove_at(i)
			continue
		want = maxi(want, _requests[i][1])
		i += 1
	if get_window().mode == Window.MODE_MINIMIZED:
		want = MINIMIZED
	if Engine.max_fps != want:
		Engine.max_fps = want
		_log()


## The rate and when it changed go to the log (user://logs/godot.log in
## an exported app), so a cockpit that is not resting can be caught.
var _log_last := -1
var _log_changes := 0
func _log() -> void:
	_log_changes += 1
	var now := Time.get_ticks_msec() / 1000
	if now == _log_last:
		return  # one line a second at most
	_log_last = now
	print("pace: %d fps at %ds (%d changes)" % [Engine.max_fps, now, _log_changes])
