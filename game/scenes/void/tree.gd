extends Node2D
## Yggdrasil, live. The trunk is the machine. The one bright node above the
## rail is the operating system: a single node, because nobody wants to see
## the litany of services it runs. Each branch is an application you have
## open; each twig on it is one of that application's windows. The frontmost
## app carries a gold bud. Branches warm with the CPU they and their children
## burn. When an app quits its branch withers but stays, faint, so by evening
## the tree remembers the day.
##
## The crown is a solid: branches leave the OS node in three dimensions,
## spread left to right and alternating in front of and behind the trunk,
## and are drawn through a simple perspective. Depth is one number per
## branch and every cue agrees with it: near branches are wider, brighter
## and crisp with larger names; far ones thin, dim and soft.
##
## Drawn, not shaded: every branch is addressable.

const OS_RISE := 96.0            # OS node this far above the bottom edge
const EL_MIN := deg_to_rad(18.0) # outermost branches lean this far above level
const EL_MAX := deg_to_rad(72.0) # the middle ones reach nearly straight up
const SPREAD := 0.92             # the crown's half-width across the screen, as a fraction of branch length
const BRANCH_MIN := 170.0
const BRANCH_MAX := 300.0
const BEND := 0.35               # how much a branch curves back toward up
const STEPS := 14
const TWIG_LEN := 46.0
const TWIG_FAN := deg_to_rad(84.0)
const TWIG_ROLL := deg_to_rad(35.0)  # the twig fan tilts this far out of the branch's plane
const MAX_TWIGS := 8
const GROW := 1.8                # seconds for a branch to grow in
const WITHER := 6.0              # seconds for a branch to fade after quit
const GHOST := 0.22              # how much of a withered branch remains
const TURN := 1.2                # radians per second a branch swings to its slot
const LABEL_SIZE := 10

## Depth. The camera sits this far in front of the OS node (design px):
## a branch reaching toward it grows, one reaching away shrinks.
const CAM := 1100.0
const NEAR_WIDTH := 1.5
const FAR_WIDTH := 0.7
const UP := Vector3(0.0, 1.0, 0.0)

## Per-app drawing state, keyed by app id.
var _branches: Dictionary = {}
var _font: Font
var _built_for := Vector2.ZERO
var _root := Vector2.ZERO
var _os := Vector2.ZERO


## Azimuth turns about the trunk: 0 is right, PI/2 toward the viewer, PI
## left, negative behind. Elevation is above level.
class Branch:
	var az := PI / 2.0
	var az_target := PI / 2.0
	var el := 1.0
	var el_target := 1.0
	var growth := 0.0
	var life := 1.0
	var twigs: Array[float] = []   # growth per twig


func _ready() -> void:
	_font = Palette.FONT


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
	# Slots: spread evenly left to right as the old flat fan was, every
	# other one leaning behind the trunk and the rest toward the viewer, as
	# far as the leftover length allows. Order comes from a hash of the app
	# id, so Terminal grows on the same side of the tree every day.
	alive.sort_custom(func(a, b): return _slot_key(a.id) < _slot_key(b.id))
	var n := alive.size()
	for i in n:
		var app = alive[i]
		var t := 0.5 if n == 1 else float(i) / float(n - 1)
		var x := (t - 0.5) * 2.0 * SPREAD
		var y := sin(lerpf(EL_MIN, EL_MAX, 1.0 - absf(1.0 - 2.0 * t)))
		var z := sqrt(maxf(0.0, 1.0 - x * x - y * y)) * (-1.0 if i % 2 == 1 else 1.0)
		var az := atan2(z, x)
		var el := asin(clampf(y / Vector3(x, y, z).length(), -1.0, 1.0))
		var b: Branch = _branches.get(app.id)
		if b == null:
			b = Branch.new()
			b.az = az
			b.el = el
			_branches[app.id] = b
		b.az_target = az
		b.el_target = el
	var moving := false   # anything growing, withering or swinging wants frames
	for id in _branches:
		var b: Branch = _branches[id]
		var app = Workspace.apps.get(id)
		var alive_now: bool = app != null and app.alive
		if absf(angle_difference(b.az, b.az_target)) > 0.001 or absf(b.el - b.el_target) > 0.001:
			moving = true
		b.az = _approach_angle(b.az, b.az_target, TURN * dt)
		b.el = move_toward(b.el, b.el_target, TURN * dt)
		if alive_now:
			if b.life < 1.0 or b.growth < 1.0:
				moving = true
			b.life = minf(1.0, b.life + dt / (WITHER * 0.5))
			b.growth = minf(1.0, b.growth + dt / GROW)
			var want: int = mini(app.windows, MAX_TWIGS)
			while b.twigs.size() < want:
				b.twigs.append(0.0)
			for k in b.twigs.size():
				var g: float = b.twigs[k]
				if (k < want and g < 1.0) or (k >= want and g > 0.0):
					moving = true
				b.twigs[k] = minf(1.0, g + dt / GROW) if k < want else maxf(0.0, g - dt / GROW)
			while b.twigs.size() > want and b.twigs[-1] <= 0.0:
				b.twigs.pop_back()
		else:
			if b.life > GHOST:
				moving = true
			b.life = maxf(GHOST, b.life - dt / WITHER)
			for k in b.twigs.size():
				if b.twigs[k] > 0.0:
					moving = true
				b.twigs[k] = maxf(0.0, b.twigs[k] - dt / GROW)
	if moving:
		Pace.stir(0.25)


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


static func _dir(az: float, el: float) -> Vector3:
	return Vector3(cos(el) * cos(az), sin(el), cos(el) * sin(az))


## Points along a branch, relative to the OS node, y up and z toward the
## viewer: leaves along `d0` and bends toward up as it goes.
static func _curve(d0: Vector3, length: float, growth: float) -> Array[Vector3]:
	var pts: Array[Vector3] = [Vector3.ZERO]
	var p := Vector3.ZERO
	var steps := maxi(1, int(ceil(STEPS * growth)))
	var seg := length / float(STEPS)
	for i in steps:
		var t := float(i + 1) / float(STEPS)
		var d := d0.lerp(UP, BEND * t).normalized()
		var part := seg if i < steps - 1 or growth >= 1.0 else seg * (STEPS * growth - float(steps - 1))
		p += d * part
		pts.append(p)
	return pts


## Perspective scale at a point: 1 in the plane of the OS node.
func _scale(p: Vector3) -> float:
	return CAM / (CAM - p.z)


func _project(p: Vector3) -> Vector2:
	return _os + Vector2(p.x, -p.y) * _scale(p)


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

	# Lay every branch out, then draw back to front so near ones cross over.
	var laid: Array = []
	for id in _branches:
		var b: Branch = _branches[id]
		var app = Workspace.apps.get(id)
		if app == null or b.growth <= 0.0:
			continue
		var pts3 := _curve(_dir(b.az, b.el), _length(app), b.growth)
		laid.append([pts3[-1].z, b, app, pts3])
	laid.sort_custom(func(p, q): return p[0] < q[0])

	for entry in laid:
		var b: Branch = entry[1]
		var app = entry[2]
		var pts3: Array[Vector3] = entry[3]
		var tip3: Vector3 = pts3[-1]
		var near := clampf(0.5 + 0.5 * tip3.z / BRANCH_MAX, 0.0, 1.0)
		var k := _scale(tip3)

		var heat := clampf(app.cpu, 0.0, 1.0) if app.alive else 0.0
		var col := frame.lerp(light, 0.4 * heat).lerp(gold, 0.5 * heat * heat)
		var alpha := lerpf(0.16, 0.5, heat) * b.life * breathe
		if app.alive and app.hidden:
			alpha *= 0.55
		if app.active:
			alpha = maxf(alpha, 0.42 * breathe)
		alpha = minf(1.0, alpha * lerpf(0.5, 1.1, near))

		var pts := PackedVector2Array()
		for p in pts3:
			pts.append(_project(p))
		if near < 0.5:
			# Out of focus: a soft wide stroke under a fainter line.
			draw_polyline(pts, Palette.dim(col, alpha * 0.3 * (1.0 - 2.0 * near)), 3.0, true)
		draw_polyline(pts, Palette.dim(col, alpha), lerpf(FAR_WIDTH, NEAR_WIDTH, near), true)
		if heat > 0.15:
			draw_polyline(pts, Palette.dim(col, alpha * 0.25 * heat), 4.0 * k, true)
		if b.growth < 1.0:
			continue

		var tip := pts[-1]
		var d3 := (pts3[-1] - pts3[-2]).normalized()
		var dir := (pts[-1] - pts[-2]).angle()
		# Twigs: the app's windows, fanned about the tip in a tilted plane.
		var side := d3.cross(UP)
		side = Vector3.RIGHT if side.length() < 0.001 else side.normalized()
		var side2 := side.cross(d3).normalized()
		var fan_axis := (side2 * cos(TWIG_ROLL) + side * sin(TWIG_ROLL)).normalized()
		var count := b.twigs.size()
		for j in count:
			var g: float = b.twigs[j]
			if g <= 0.0:
				continue
			var t := 0.5 if count == 1 else float(j) / float(count - 1)
			var a := (t - 0.5) * TWIG_FAN
			var end3 := tip3 + (d3 * cos(a) + fan_axis * sin(a)).normalized() * TWIG_LEN * g
			var end := _project(end3)
			draw_line(tip, end, Palette.dim(col, alpha * 0.8), lerpf(FAR_WIDTH, 1.0, near), true)
			if g >= 1.0:
				var ke := _scale(end3)
				draw_circle(end, 2.6 * ke, Palette.dim(light, 0.07 * b.life * breathe))
				draw_circle(end, 1.0 * ke, Palette.dim(light, 0.55 * b.life * breathe))
		# The tip: a bud, gold and haloed when the app is frontmost.
		if app.active:
			draw_circle(tip, 9.0 * k, Palette.dim(gold, 0.10 * breathe))
			draw_circle(tip, 4.5 * k, Palette.dim(gold, 0.22 * breathe))
			draw_circle(tip, 1.8 * k, Palette.dim(gold, 0.95))
		else:
			draw_circle(tip, 1.4 * k, Palette.dim(light, 0.6 * b.life * breathe))
		# The name, thin and uppercase, set off the tip on the branch's side;
		# nearer names are a little larger.
		var label: String = str(app.name).to_upper()
		var px := clampi(roundi(LABEL_SIZE * k), 8, 12)
		var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var off := Vector2.from_angle(dir) * (TWIG_LEN * k + 14.0)
		var at := tip + off + Vector2(-w * 0.5 if absf(cos(dir)) < 0.35 else (0.0 if cos(dir) > 0.0 else -w), 3.0)
		var label_alpha := (0.7 if app.active else 0.3) * b.life * breathe * lerpf(0.6, 1.0, near)
		draw_string(_font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Palette.dim(light, label_alpha))
