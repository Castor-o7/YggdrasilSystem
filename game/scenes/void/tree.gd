extends Node2D
## Yggdrasil, live. The trunk is the machine. The one bright node above the
## rail is the operating system: a single node, because nobody wants to see
## the litany of services it runs. Each branch is an application you have
## open; each twig on it is one of that application's windows. The frontmost
## app carries a gold bud. Branches warm with the CPU they and their children
## burn. When an app quits its branch withers but stays, faint, so by evening
## the tree remembers the day.
##
## Drawn, not shaded: every branch is addressable.

const OS_RISE := 96.0            # OS node this far above the bottom edge
const FAN := deg_to_rad(150.0)   # the whole spread of branches
const BRANCH_MIN := 170.0
const BRANCH_MAX := 300.0
const STAGGER := 0.22            # every other branch reaches this much farther
const BEND := 0.35               # how much a branch curves back toward up
const STEPS := 14
const TWIG_LEN := 46.0
const TWIG_FAN := deg_to_rad(84.0)
const MAX_TWIGS := 8
const GROW := 1.8                # seconds for a branch to grow in
const WITHER := 6.0              # seconds for a branch to fade after quit
const GHOST := 0.22              # how much of a withered branch remains
const TURN := 1.2                # radians per second a branch swings to its slot
const LABEL_SIZE := 10

## Per-app drawing state, keyed by app id.
var _branches: Dictionary = {}
var _font: Font
var _built_for := Vector2.ZERO
var _root := Vector2.ZERO
var _os := Vector2.ZERO


class Branch:
	var angle := -PI / 2.0
	var target := -PI / 2.0
	var growth := 0.0
	var life := 1.0
	var stagger := 0.0
	var twigs: Array[float] = []   # growth per twig


func _ready() -> void:
	_font = ThemeDB.fallback_font


func _process(dt: float) -> void:
	var s := get_viewport_rect().size
	if s != _built_for:
		_built_for = s
		_root = Vector2(s.x * 0.5, s.y)
		_os = Vector2(s.x * 0.5, s.y - OS_RISE)
	_sync(dt)
	queue_redraw()


## Fold the workspace into drawing state: assign slots, grow, wither.
func _sync(dt: float) -> void:
	var alive := Workspace.alive_apps()
	# Slots: the fan is shared evenly; order comes from a hash of the app
	# id, so Terminal grows on the same side of the tree every day.
	alive.sort_custom(func(a, b): return _slot_key(a.id) < _slot_key(b.id))
	var n := alive.size()
	for i in n:
		var app = alive[i]
		var t := 0.5 if n == 1 else float(i) / float(n - 1)
		var b: Branch = _branches.get(app.id)
		if b == null:
			b = Branch.new()
			b.angle = -PI / 2.0 + (t - 0.5) * FAN
			_branches[app.id] = b
		b.target = -PI / 2.0 + (t - 0.5) * FAN
		b.stagger = STAGGER * float(i % 2)
	for id in _branches:
		var b: Branch = _branches[id]
		var app = Workspace.apps.get(id)
		var alive_now: bool = app != null and app.alive
		b.angle = _approach_angle(b.angle, b.target, TURN * dt)
		if alive_now:
			b.life = minf(1.0, b.life + dt / (WITHER * 0.5))
			b.growth = minf(1.0, b.growth + dt / GROW)
			var want: int = mini(app.windows, MAX_TWIGS)
			while b.twigs.size() < want:
				b.twigs.append(0.0)
			for k in b.twigs.size():
				var g: float = b.twigs[k]
				b.twigs[k] = minf(1.0, g + dt / GROW) if k < want else maxf(0.0, g - dt / GROW)
			while b.twigs.size() > want and b.twigs[-1] <= 0.0:
				b.twigs.pop_back()
		else:
			b.life = maxf(GHOST, b.life - dt / WITHER)
			for k in b.twigs.size():
				b.twigs[k] = maxf(0.0, b.twigs[k] - dt / GROW)


static func _slot_key(id: String) -> float:
	return float(hash(id) % 100000) / 100000.0


static func _approach_angle(a: float, target: float, step: float) -> float:
	var d := angle_difference(a, target)
	return a + clampf(d, -step, step)


## Branch length grows with how long the app has been open: an hour is
## already most of the way, a working day is the full reach.
static func _length(app) -> float:
	var hours := 0.0
	if app.launched > 0.0:
		hours = maxf(0.0, (Time.get_unix_time_from_system() - app.launched) / 3600.0)
	else:
		hours = Workspace.clock / 60.0  # scripted day: a minute is an hour
	var k := clampf(log(1.0 + hours) / log(9.0), 0.0, 1.0)
	return lerpf(BRANCH_MIN, BRANCH_MAX, k)


## Points along a branch: starts at `angle`, bends toward up as it goes.
static func _curve(from: Vector2, angle: float, length: float, growth: float) -> PackedVector2Array:
	var pts := PackedVector2Array([from])
	var p := from
	var steps := maxi(1, int(ceil(STEPS * growth)))
	var seg := length / float(STEPS)
	for i in steps:
		var t := float(i + 1) / float(STEPS)
		var a := lerp_angle(angle, -PI / 2.0, BEND * t)
		var part := seg if i < steps - 1 or growth >= 1.0 else seg * (STEPS * growth - float(steps - 1))
		p += Vector2.from_angle(a) * part
		pts.append(p)
	return pts


func _draw() -> void:
	var frame := Palette.color("frame")
	var light := Palette.color("light")
	var gold := Palette.color("core")
	var breathe := 0.85 + 0.15 * Palette.breath()

	# Trunk and the OS node.
	draw_line(_root, _os, Palette.dim(frame, 0.35 * breathe), 1.0, true)
	draw_circle(_os, 18.0, Palette.dim(light, 0.05 * breathe))
	draw_circle(_os, 9.0, Palette.dim(light, 0.14 * breathe))
	draw_circle(_os, 3.0, Palette.dim(light, 0.95))

	for id in _branches:
		var b: Branch = _branches[id]
		var app = Workspace.apps.get(id)
		if app == null or b.growth <= 0.0:
			continue
		var heat := clampf(app.cpu, 0.0, 1.0) if app.alive else 0.0
		var col := frame.lerp(light, 0.4 * heat).lerp(gold, 0.5 * heat * heat)
		var alpha := lerpf(0.16, 0.5, heat) * b.life * breathe
		if app.alive and app.hidden:
			alpha *= 0.55
		if app.active:
			alpha = maxf(alpha, 0.42 * breathe)
		var pts := _curve(_os, b.angle, _length(app) * (1.0 + b.stagger), b.growth)
		draw_polyline(pts, Palette.dim(col, alpha), 1.0, true)
		if heat > 0.15:
			draw_polyline(pts, Palette.dim(col, alpha * 0.25 * heat), 4.0, true)
		if b.growth < 1.0:
			continue
		var tip := pts[-1]
		var dir := (pts[-1] - pts[-2]).angle()
		# Twigs: the app's windows.
		var count := b.twigs.size()
		for k in count:
			var g: float = b.twigs[k]
			if g <= 0.0:
				continue
			var t := 0.5 if count == 1 else float(k) / float(count - 1)
			var a := dir + (t - 0.5) * TWIG_FAN
			var end := tip + Vector2.from_angle(a) * TWIG_LEN * g
			draw_line(tip, end, Palette.dim(col, alpha * 0.8), 1.0, true)
			if g >= 1.0:
				draw_circle(end, 2.6, Palette.dim(light, 0.07 * b.life * breathe))
				draw_circle(end, 1.0, Palette.dim(light, 0.55 * b.life * breathe))
		# The tip: a bud, gold and haloed when the app is frontmost.
		if app.active:
			draw_circle(tip, 9.0, Palette.dim(gold, 0.10 * breathe))
			draw_circle(tip, 4.5, Palette.dim(gold, 0.22 * breathe))
			draw_circle(tip, 1.8, Palette.dim(gold, 0.95))
		else:
			draw_circle(tip, 1.4, Palette.dim(light, 0.6 * b.life * breathe))
		# The name, thin and uppercase, set off the tip on the branch's side.
		var label: String = str(app.name).to_upper()
		var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
		var off := Vector2.from_angle(dir) * (TWIG_LEN + 14.0)
		var at := tip + off + Vector2(-w * 0.5 if absf(cos(dir)) < 0.35 else (0.0 if cos(dir) > 0.0 else -w), 3.0)
		var label_alpha := (0.7 if app.active else 0.3) * b.life * breathe
		draw_string(_font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, Palette.dim(light, label_alpha))
