extends Node
## "Pace": the frame rate governor. The cockpit lives on the desktop all
## day. It rests at 30, the floor (a 12 fps rest was tried on 2026-09-10
## and read as harsh; below 30 the rate is not a lever). Anything that
## needs more asks with stir(): the zen paint chasing a dragged window
## runs at 60 until it settles. The highest live request wins, and a
## minimized window drops to a few frames a second.
##
## Measured 2026-09-09: the cost scales with the frame rate, and holding
## 60 whenever zen was on cost most of a core with WindowServer.

const IDLE := 30
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
func stir(seconds: float, fps: int = FAST) -> void:
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
