extends RefCounted
## The desk's own hand: one thread that makes every Desk call, one job at a
## time, in the order they were asked for, so the cockpit never waits on a
## peer (a Z press was 0.2 s of frozen void, seconds with a wedged
## Konsole). Preloaded where used, like desk.gd.
##
## A job is a Callable that touches only Desk and the plain data it was
## bound with, never a node or the cockpit's own vars; what it returns
## goes to its `done` on the main thread, in order, a frame or so later.
## Desk's statics belong to whichever thread holds the hand: the main
## thread before the first post and after finish(), this thread between
## (Desk.owner).
##
## macOS runs every job inline, on the spot, as it always has: its desk
## calls are AppleScript through Osa, mostly fired and not waited on.

const Desk := preload("res://scripts/desk.gd")

## Jobs run where they are posted, their `done` at once: no thread.
var inline := not Desk.LINUX

var _thread: Thread
var _lock := Mutex.new()
var _wake := Semaphore.new()
var _queue: Array = []          # [job, done, key], not yet started
var _out: Array = []            # [done, result], finished, for the main thread
var _running := false            # a job is being made now
var _closed := false


## Queue `job`; `done` gets its result on the main thread. A `key` job is
## asked once: posted again while the first still waits, it is dropped
## (a sweep or a refresh asked twice does the same thing twice), and its
## `done` takes the first's place only if `wins` (a new window's sweep
## outranks a resweep's). False once the hand is closed.
func post(job: Callable, done := Callable(), key := "", wins := false) -> bool:
	_lock.lock()
	if _closed:
		_lock.unlock()
		return false
	if inline:
		_lock.unlock()
		Desk.begin()
		var result = job.call()
		if done.is_valid():
			done.call(result)
		return true
	if not key.is_empty():
		for q in _queue:
			if q[2] == key:
				if wins:
					q[1] = done
				_lock.unlock()
				return true
	_queue.append([job, done, key])
	_lock.unlock()
	if _thread == null:
		_thread = Thread.new()
		_thread.start(_loop)
	_wake.post()
	return true


## From inside a job: hand `value` to `done` now, ahead of the job's end
## (zen's record goes to prefs before the chrome is hidden).
func tell(done: Callable, value) -> void:
	if inline:
		done.call(value)
		return
	_lock.lock()
	_out.append([done, value])
	_lock.unlock()
	_pump.call_deferred()


## A job waiting or being made.
func busy() -> bool:
	_lock.lock()
	var b := _running or not _queue.is_empty()
	_lock.unlock()
	return b


func _loop() -> void:
	Desk.owner = OS.get_thread_caller_id()
	while true:
		_wake.wait()
		_lock.lock()
		if _queue.is_empty():
			var done := _closed
			_lock.unlock()
			if done:
				return
			continue
		var q: Array = _queue.pop_front()
		_running = true
		_lock.unlock()
		Desk.begin()
		var result = q[0].call()
		_lock.lock()
		_running = false
		if (q[1] as Callable).is_valid():
			_out.append([q[1], result])
		_lock.unlock()
		_pump.call_deferred()


## Every finished job's `done`, in order. Deferred from the thread; the
## quit runs it itself, since it never returns to the loop.
func _pump() -> void:
	_lock.lock()
	var out := _out
	_out = []
	_lock.unlock()
	for o in out:
		if (o[0] as Callable).is_valid():
			o[0].call(o[1])


## The quit: take no more, let the queue run for up to `wait` seconds (the
## job in hand always ends: every Desk call is bounded), drop what has
## not started by then (the desk is as if the cockpit quit that much
## earlier), join, and run the `done`s here. Desk is the main thread's
## again after. Says how many were dropped; a second call does nothing.
func finish(wait: float) -> int:
	_lock.lock()
	var again := _closed
	_closed = true
	_lock.unlock()
	if again:
		return 0
	var dropped := 0
	if _thread != null:
		var until := Time.get_ticks_msec() + int(wait * 1000.0)
		while busy() and Time.get_ticks_msec() < until:
			OS.delay_msec(5)
		_lock.lock()
		dropped = _queue.size()
		_queue.clear()
		_lock.unlock()
		_wake.post()  # wakes it to see the empty, closed queue and end
		_thread.wait_to_finish()
		_thread = null
		Desk.owner = 0
	_pump()
	if dropped > 0:
		print("desk: %d job%s left undone at the quit" % [dropped, "" if dropped == 1 else "s"])
	return dropped
