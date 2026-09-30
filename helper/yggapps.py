#!/usr/bin/env python3
# yggapps — the Yggdrasil System workspace daemon, Linux/KDE edition.
#
# The same contract as main.swift (the macOS helper): one JSON object per
# line, every application with a window (and, as on macOS, one still
# running with its windows closed: see keep_windowless), its window count,
# whether it is frontmost, and its CPU including every process it has
# spawned; plus fast {"win": {...}} lines whenever an on-screen window
# moves. Exits when its stdout closes or its parent dies.
#
# Windows come from KWin, not polling: the helper owns a D-Bus name, loads
# a small KWin script (embedded below) that sends the whole window list back
# over D-Bus whenever a window appears, leaves, moves, (un)minimizes, changes
# desktop or takes focus, and unloads it on the way out. A forked watchdog
# unloads it too if the helper is killed outright (Godot's OS.kill is
# SIGKILL), so no script is ever left running in the user's KWin.
#
# With --guard, that watchdog also stands guard over zen: Godot dies on
# SIGTERM, SIGHUP and SIGINT without a word (a logout, a unit stop, a
# closed terminal, kill), so a cockpit killed mid-zen never hands the
# panels, Konsole's profile and bars or the window frames back. The
# watchdog outlives it, and if the cockpit's lock (DIR/cockpit.pid, which
# only a clean quit removes) still names it, runs the command after `--`
# with its pid: the cockpit itself, headless, releasing zen from prefs.
#
# Needs python3, dbus-python and PyGObject (GLib). Without KWin (another
# desktop) it exits 2 with a message on stderr and the cockpit falls back
# to its scripted day.
#
#   yggapps [--interval 1000] [--once] [--guard DIR -- UNZEN_ARGV...]

import fcntl
import json
import os
import signal
import sys
import tempfile
import time

PLUGIN = "yggapps_%d" % os.getpid()        # KWin plugin name, unique per process
BUS_NAME = "edu.pdx.josh.yggapps.p%d" % os.getpid()
IFACE = "edu.pdx.josh.yggapps"
OBJ_PATH = "/edu/pdx/josh/yggapps"
NERVIEWER_ID = "edu.pdx.josh.nerviewer"
MIN_SIDE = 40                              # smaller windows are not windows (as on macOS)
WIN_HZ = 60.0                              # ceiling for the fast "win" lines

# --- Arguments ---------------------------------------------------------------

interval_ms = 1000
once = False
guard_dir = ""             # the cockpit's user dir; "" stands no guard
unzen_argv = []            # what the guard runs, the cockpit's pid appended
_args = iter(sys.argv[1:])
for _a in _args:
	if _a == "--":
		unzen_argv = list(_args)
		break
	if _a == "--interval":
		try:
			_n = int(next(_args, ""))
			if _n >= 250:
				interval_ms = _n
		except ValueError:
			pass
	elif _a == "--once":
		once = True
	elif _a == "--guard":
		guard_dir = next(_args, "")


def start_tick(pid: int):
	"""(state, start ticks since boot) of a process, or None if it is gone.
	Fields counted from the last ')', as in process_table."""
	try:
		with open("/proc/%d/stat" % pid, "rb") as f:
			s = f.read()
		rest = s[s.rfind(b")") + 2:].split()
		return rest[0], int(rest[19])
	except (OSError, IndexError, ValueError):
		return None


parent_pid = os.getppid()
_st = start_tick(parent_pid)
parent_start = _st[1] if _st else -1   # a reused pid starts later


def die(msg: str, code: int) -> None:
	sys.stderr.write("yggapps: %s\n" % msg)
	sys.stderr.flush()
	os._exit(code)


# --- Watchdog ----------------------------------------------------------------

def unload_script() -> None:
	"""Ask KWin to drop our script. Safe to call twice (returns false then)."""
	try:
		import dbus
		k = dbus.SessionBus(private=True).get_object("org.kde.KWin", "/Scripting")
		k.get_dbus_method("unloadScript", "org.kde.kwin.Scripting")(PLUGIN)
	except Exception:
		pass


def fork_watchdog(js_path: str) -> None:
	"""A child that outlives a SIGKILLed helper just long enough to unload
	its KWin script. It blocks on a pipe whose only write end the helper
	holds, so any death of the helper, however abrupt, reads as EOF. It
	forks before the helper touches D-Bus, drops stdio (Godot must see EOF
	on the helper's stdout when the helper dies) and leaves the process
	group so a Ctrl-C meant for the cockpit does not reach it first. With
	--guard it then waits out the cockpit too (see zen_guard)."""
	r, w = os.pipe()
	if os.fork() != 0:
		os.close(r)
		os.set_inheritable(w, False)
		return
	try:
		os.close(w)
		os.setsid()
		for s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP, signal.SIGPIPE):
			signal.signal(s, signal.SIG_IGN)
		null = os.open(os.devnull, os.O_RDWR)
		for fd in (0, 1, 2):
			os.dup2(null, fd)
		while os.read(r, 64):
			pass
		unload_script()
		try:
			os.unlink(js_path)
		except OSError:
			pass
		if guard_dir and unzen_argv:
			zen_guard()
	finally:
		os._exit(0)


# --- Zen guard -------------------------------------------------------------------

GUARD_SETTLE = 0.5         # seconds after the cockpit's death before the release
GUARD_TRIES = 3            # release runs, while a TERM, HUP or INT cuts one short


def cockpit_gone() -> bool:
	"""No such process, another one on its pid, or a zombie (the project
	manager that ran it has not reaped it yet): dead all the same."""
	st = start_tick(parent_pid)
	return st is None or st[1] != parent_start or st[0] in (b"Z", b"X")


def zen_guard() -> None:
	"""In the watchdog, once the helper is gone: wait out the cockpit (no
	limit; a helper that failed early still guards), then hand zen back if
	it died holding the lock. A clean quit removed the lock; a new cockpit
	has rewritten it. One guard per cockpit: another watchdog (a helper
	restarted) holding the flock has it in hand.
	The release runs as a child, not in place: Godot resets every signal
	it inherits, ignored or blocked (checked 2026-09-29), so it dies on a
	TERM like the cockpit did. It starts a beat after the death, once the
	TERM a unit stop sends every process at once has come and gone (the
	watchdog ignores it), and runs again if a later one kills it; the
	release only undoes what zen still holds, so a second run is safe.
	systemd waits for both like any process of the unit."""
	while not cockpit_gone():
		time.sleep(0.5)
	time.sleep(GUARD_SETTLE)
	try:
		with open(os.path.join(guard_dir, "cockpit.pid")) as f:
			if f.readline().strip() != str(parent_pid):
				return
		fd = os.open(os.path.join(guard_dir, "zen_guard.lock"), os.O_RDWR | os.O_CREAT, 0o600)
		fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
	except OSError:
		return
	for _ in range(GUARD_TRIES):
		try:
			pid = os.fork()
		except OSError:
			return
		if pid == 0:
			try:
				os.close(fd)
				os.execvp(unzen_argv[0], unzen_argv + [str(parent_pid)])
			finally:
				os._exit(127)
		_, status = os.waitpid(pid, 0)
		if not os.WIFSIGNALED(status) or os.WTERMSIG(status) not in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
			return      # done, failed on its own, or SIGKILLed: systemd's last word


# --- The KWin script -----------------------------------------------------------

# Runs inside KWin. Sends {"cur", "act", "wins": [...]} as one string on
# every change; the helper coalesces bursts (a drag is one per frame).
# Only fields the grouping needs are sent; titles only for spotting
# NERViewer.
KWIN_JS = r"""
var SERVICE = "@SERVICE@", PATH = "@PATH@", IFACE = "@IFACE@";

function snapshot() {
	var out = [];
	var ws = workspace.windowList();
	var active = workspace.activeWindow;
	for (var i = 0; i < ws.length; i++) {
		var w = ws[i];
		if (!w.normalWindow)
			continue;
		var g = w.frameGeometry;
		var desks = [];
		for (var j = 0; j < w.desktops.length; j++)
			desks.push(w.desktops[j].id);
		out.push({
			pid: w.pid, cls: w.resourceClass, rn: w.resourceName,
			cap: w.caption, dfn: w.desktopFileName,
			skip: w.skipTaskbar, min: w.minimized, hid: w.hidden,
			all: w.onAllDesktops, desks: desks, acts: w.activities,
			op: w.opacity, g: [g.x, g.y, g.width, g.height],
			act: w === active
		});
	}
	callDBus(SERVICE, PATH, IFACE, "Update", JSON.stringify({
		cur: workspace.currentDesktop ? workspace.currentDesktop.id : "",
		act: workspace.currentActivity, wins: out
	}));
}

function watch(w) {
	w.frameGeometryChanged.connect(snapshot);
	w.minimizedChanged.connect(snapshot);
	w.desktopsChanged.connect(snapshot);
	w.activitiesChanged.connect(snapshot);
	w.skipTaskbarChanged.connect(snapshot);
}

var initial = workspace.windowList();
for (var i = 0; i < initial.length; i++)
	watch(initial[i]);
workspace.windowAdded.connect(function (w) { watch(w); snapshot(); });
workspace.windowRemoved.connect(snapshot);
workspace.windowActivated.connect(snapshot);
workspace.currentDesktopChanged.connect(snapshot);
workspace.currentActivityChanged.connect(snapshot);
snapshot();
"""


# --- Processes -----------------------------------------------------------------

CLK_TCK = os.sysconf("SC_CLK_TCK")


def boot_time() -> float:
	with open("/proc/stat") as f:
		for line in f:
			if line.startswith("btime "):
				return float(line.split()[1])
	return 0.0


BOOT = boot_time()


def process_table() -> dict:
	"""pid -> (ppid, utime+stime ticks, start ticks since boot), for every
	process. The command name is parenthesised and may hold spaces or
	parentheses, so fields are counted from its last ')'."""
	out = {}
	for d in os.listdir("/proc"):
		if not d.isdigit():
			continue
		try:
			with open("/proc/%s/stat" % d, "rb") as f:
				s = f.read()
		except OSError:
			continue
		rest = s[s.rfind(b")") + 2:].split()
		try:
			# rest[0] is field 3 (state): ppid 4, utime 14, stime 15, start 22.
			out[int(d)] = (int(rest[1]), int(rest[11]) + int(rest[12]), int(rest[19]))
		except (IndexError, ValueError):
			continue
	return out


def cmdline(pid: int) -> list:
	try:
		with open("/proc/%d/cmdline" % pid, "rb") as f:
			return [a.decode("utf-8", "replace") for a in f.read().split(b"\0") if a]
	except OSError:
		return []


# --- Names and ids ---------------------------------------------------------------

def _app_dirs() -> list:
	home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
	dirs = [home] + (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
	return [os.path.join(d, "applications") for d in dirs if d]


def _desktop_entry(path: str) -> dict:
	"""Name, StartupWMClass and Exec from the [Desktop Entry] group only."""
	out = {}
	group = ""
	try:
		with open(path, encoding="utf-8", errors="replace") as f:
			for line in f:
				line = line.strip()
				if line.startswith("["):
					group = line
					continue
				if group != "[Desktop Entry]" or "=" not in line:
					continue
				k, v = line.split("=", 1)
				if k in ("Name", "StartupWMClass", "Exec") and k not in out:
					out[k] = v
	except OSError:
		pass
	return out


_entries = None
_names = {}


def _all_entries() -> dict:
	global _entries
	if _entries is None:
		_entries = {}
		for d in reversed(_app_dirs()):       # earlier dirs win, so load them last
			try:
				for fn in os.listdir(d):
					if fn.endswith(".desktop"):
						_entries[fn[:-8]] = _desktop_entry(os.path.join(d, fn))
			except OSError:
				pass
	return _entries


def human_name(dfn: str, cls: str) -> str:
	"""The .desktop Name= for a window: by desktop file name, else by a file
	named for or claiming (StartupWMClass) its class or program; failing
	that the class, capitalised. Cached; .desktop files are read once."""
	key = (dfn, cls)
	if key in _names:
		return _names[key]
	entries = _all_entries()
	name = ""
	for cand in (dfn, cls, cls.lower()):
		if cand and cand in entries and entries[cand].get("Name"):
			name = entries[cand]["Name"]
			break
	if not name:
		want = {x.lower() for x in (dfn, cls) if x}
		for e in entries.values():
			wm = e.get("StartupWMClass", "").lower()
			prog = os.path.basename(e.get("Exec", "").split(" ")[0]).lower()
			if e.get("Name") and (wm in want or prog in want):
				name = e["Name"]
				break
	if not name:
		base = cls or dfn or "?"
		name = base[:1].upper() + base[1:]
	_names[key] = name
	return name


def is_nerviewer(w: dict) -> bool:
	"""NERViewer by its window's class or name (Godot's X11 class is the
	project name), or by its command line: an export (the program is
	NERViewer.x86_64) or `godot --path .../NERViewer/game`. The title
	counts only for a generic Godot window: Konsole's title carries its
	working directory, and a shell in .../NERViewer must not turn that
	whole Konsole into NERViewer. Other programs merely handed a NERViewer
	path (`kate NERViewer/README.md`, `konsole --workdir ...`) are not it,
	nor is the Godot editor open on that project."""
	cls = str(w.get("cls") or "").lower()
	rn = str(w.get("rn") or "").lower()
	if "nerviewer" in cls or "nerviewer" in rn:
		return True
	args = cmdline(int(w.get("pid") or 0))
	if any(a in ("-e", "--editor", "--project-manager") for a in args):
		return False
	if cls in ("godot_editor", "godot_projectlist"):
		return False
	if (cls.startswith("godot") or rn.startswith("godot")) and "nerviewer" in str(w.get("cap") or "").lower():
		return True
	if not args:
		return False
	prog = os.path.basename(args[0]).lower()
	if "nerviewer" in prog:
		return True
	return prog.startswith("godot") and any("NERViewer" in a for a in args[1:])


def app_id(w: dict) -> str:
	"""The desktop file name (what Wayland clients and most X11 ones set),
	else the X11 class. NERViewer is special-cased by the caller."""
	return str(w.get("dfn") or w.get("cls") or w.get("rn") or "pid%d" % int(w.get("pid") or 0))


# --- State fed by KWin ---------------------------------------------------------------

snap = None               # the latest {"cur", "act", "wins"} from KWin
_nerv_cache = {}          # pid -> is NERViewer (cmdline reads are not free)


def windows_by_app() -> dict:
	"""app key -> {"id", "name", "pids": set, "wins": [window dicts]}. Normal
	windows only (KWin's normalWindow; the script drops the rest), at least
	MIN_SIDE on both sides and not fully transparent, as on macOS. Windows
	that skip the taskbar are popups and tool windows, except the cockpit's
	and NERViewer's own, which may well be set that way."""
	out = {}
	if not snap:
		return out
	pids = {int(w.get("pid") or 0) for w in snap.get("wins", [])}
	for p in [p for p in _nerv_cache if p not in pids]:
		del _nerv_cache[p]      # the pid may be reused by something else
	for w in snap.get("wins", []):
		pid = int(w.get("pid") or 0)
		g = w.get("g") or [0, 0, 0, 0]
		if g[2] < MIN_SIDE or g[3] < MIN_SIDE or float(w.get("op", 1)) <= 0:
			continue
		if pid not in _nerv_cache:
			_nerv_cache[pid] = is_nerviewer(w)
		aid = NERVIEWER_ID if _nerv_cache[pid] else app_id(w)
		if w.get("skip") and pid != parent_pid and aid != NERVIEWER_ID:
			continue
		# The cockpit's own windows are a record of their own (as on macOS,
		# where self is one process), so another program sharing its class,
		# say the Godot editor, is not hidden along with it as "self".
		key = aid + "\0self" if pid == parent_pid else aid
		a = out.get(key)
		if a is None:
			name = "NERViewer" if aid == NERVIEWER_ID else human_name(str(w.get("dfn") or ""), str(w.get("cls") or w.get("rn") or ""))
			a = out[key] = {"id": aid, "name": name, "pids": set(), "wins": []}
		a["pids"].add(pid)
		a["wins"].append(w)
	return out


def on_screen(w: dict) -> bool:
	"""On the current virtual desktop and activity, not minimized."""
	if w.get("min") or w.get("hid"):
		return False
	cur = snap.get("cur", "")
	if not w.get("all") and cur and cur not in (w.get("desks") or []):
		return False
	acts = w.get("acts") or []
	return not acts or snap.get("act", "") in acts


def rect(w: dict) -> list:
	# KWin's global logical coordinates, origin at the top-left of the
	# screen layout; equal to X11/XWayland pixels at scale 1.
	return [float(v) for v in w["g"]]


# --- Windowless apps -----------------------------------------------------------------

_known = {}               # app key -> {"id", "name", "pids": {pid: start tick}}
_applike = {}             # (pid, start tick) -> may outlive its windows
_own_cg = None            # the cockpit's cgroup, read once


def cgroup(pid: int):
	"""The pid's cgroup v2 path, or None where there is none to read."""
	try:
		with open("/proc/%d/cgroup" % pid) as f:
			for line in f:
				if line.startswith("0::"):
					return line[3:].strip()
	except OSError:
		pass
	return None


def app_like(pid: int, start: int) -> bool:
	"""Whether a window process is an app (kept windowless, as macOS keeps
	a .regular app) or a session daemon that happened to open a dialog
	(plasmashell's wallpaper settings, the polkit or KWallet prompt), which
	on macOS would never be listed at all. systemd tells them apart: KDE
	starts apps in app-*.scope (and whatever runs from Konsole in a nested
	tab(N).scope), daemons run as *.service. What the cockpit spawned itself
	shares its unit, service or not. No cgroup v2: every pid counts, as
	before."""
	global _own_cg
	k = (pid, start)
	if k not in _applike:
		if _own_cg is None:
			_own_cg = cgroup(parent_pid) or ""
		cg = cgroup(pid)
		_applike[k] = cg is None or cg.endswith(".scope") or (cg != "" and cg == _own_cg)
	return _applike[k]


def keep_windowless(groups: dict, procs: dict) -> None:
	"""On macOS an app lives while its process runs, windows or not (Finder,
	Music playing with its window closed, a chat app in the tray). KWin only
	knows windows, so each app's window processes are remembered with their
	start ticks, and an app whose windows have all gone stays, with none,
	while one of those processes still runs as itself (a reused pid starts
	later) and is not now another app's (a Chrome web app's window closed,
	Chrome's own still open). Only app-like processes are remembered, so a
	daemon's dialog leaves with its window. Added to `groups` in place."""
	for p in [p for p in _applike if p[0] not in procs or procs[p[0]][2] != p[1]]:
		del _applike[p]
	for key, a in groups.items():
		_known[key] = {"id": a["id"], "name": a["name"],
			"pids": {p: procs[p][2] for p in a["pids"] if p in procs and app_like(p, procs[p][2])}}
	taken = {p for a in groups.values() for p in a["pids"]}
	for key in list(_known):
		if key in groups:
			continue
		k = _known[key]
		alive = {p for p, st in k["pids"].items() if p in procs and procs[p][2] == st and p not in taken}
		if not alive:
			del _known[key]
			continue
		groups[key] = {"id": k["id"], "name": k["name"], "pids": alive, "wins": []}


# --- Sample ------------------------------------------------------------------------

_last_ticks = {}          # pid -> utime+stime ticks at the last sample
_last_time = 0.0


def rep_pid(pids: set, procs: dict) -> int:
	"""The app's pid for the record and the "win" keys: its oldest window
	process, so it stays put while windows come and go."""
	live = [p for p in pids if p in procs]
	if not live:
		return min(pids) if pids else 0
	return min(live, key=lambda p: (procs[p][2], p))


def sample() -> str:
	global _last_ticks, _last_time
	now = time.time()
	dt = max(now - _last_time, 0.001)
	first = _last_time == 0.0
	procs = process_table()
	children = {}
	for pid, (ppid, _t, _s) in procs.items():
		children.setdefault(ppid, []).append(pid)
	since_boot_last = (_last_time - BOOT) * CLK_TCK
	groups = windows_by_app()
	keep_windowless(groups, procs)
	# A process that owns another app's windows is that app's, not its
	# parent's: a Godot game run from Konsole is Godot's CPU, not Konsole's.
	owner = {}
	for aid, a in groups.items():
		for p in a["pids"]:
			owner.setdefault(p, aid)

	apps = []
	for aid, a in groups.items():
		family = set()
		stack = list(a["pids"])
		while stack:
			p = stack.pop()
			if p in family or p not in procs:
				continue
			family.add(p)
			for c in children.get(p, []):
				if owner.get(c, aid) == aid:
					stack.append(c)
		ticks = 0
		for p in family:
			t = procs[p][1]
			if p in _last_ticks:
				ticks += max(t - _last_ticks[p], 0)
			elif not first and procs[p][2] >= since_boot_last:
				ticks += t          # born this interval: all of it is new
		cpu = 0.0 if first else ticks / CLK_TCK / dt   # fraction of one core
		pid = rep_pid(a["pids"], procs)
		wins = a["wins"]
		shown = [w for w in wins if on_screen(w)]
		apps.append({
			"id": a["id"],
			"name": a["name"],
			"pid": pid,
			"launched": round(BOOT + procs[pid][2] / CLK_TCK, 2) if pid in procs else 0,
			"windows": len(wins),
			"visible": len(shown),
			"rects": [rect(w) for w in shown],
			"cpu": round(cpu, 3),
			"active": any(w.get("act") for w in wins),
			"hidden": bool(wins) and all(w.get("min") for w in wins),
			"self": parent_pid in a["pids"],
		})
	_last_ticks = {p: v[1] for p, v in procs.items()}
	_last_time = now
	apps.sort(key=lambda x: x["id"])
	return json.dumps({"t": now, "interval": interval_ms, "apps": apps}, sort_keys=True)


# --- Fast window tracking -------------------------------------------------------------

_last_win = None


def win_line():
	"""{"win": {"<pid>": [[x,y,w,h]]}}: on-screen rects keyed by each app's
	record pid (an app's windows may belong to several processes, but the
	cockpit matches on the record's pid), or None if nothing moved."""
	global _last_win
	groups = windows_by_app()
	procs = {}
	for a in groups.values():
		for p in a["pids"]:
			try:
				with open("/proc/%d/stat" % p, "rb") as f:
					s = f.read()
				procs[p] = (0, 0, int(s[s.rfind(b")") + 2:].split()[19]))
			except (OSError, IndexError, ValueError):
				pass
	by_pid = {}
	for a in groups.values():
		rects = [rect(w) for w in a["wins"] if on_screen(w)]
		if rects:
			by_pid[str(rep_pid(a["pids"], procs))] = rects
	if by_pid == _last_win:
		return None
	_last_win = by_pid
	return json.dumps({"win": by_pid}, sort_keys=True)


# --- Main ------------------------------------------------------------------------------

def emit(line: str) -> None:
	try:
		sys.stdout.write(line + "\n")
		sys.stdout.flush()
	except (BrokenPipeError, OSError):
		quit_now(0)


_loop = None
_js_path = ""


def quit_now(code: int) -> None:
	"""Unload the KWin script and go. os._exit, not sys.exit: a flush of a
	closed stdout at interpreter shutdown would only raise again."""
	unload_script()
	try:
		if _js_path:
			os.unlink(_js_path)
	except OSError:
		pass
	os._exit(code)


def main() -> None:
	global _loop, _js_path, snap
	try:
		import dbus
		import dbus.service
		from dbus.mainloop.glib import DBusGMainLoop
		from gi.repository import GLib
	except ImportError as e:
		die("needs dbus-python and PyGObject (%s)" % e, 3)

	# KWin reads the script from a file, so it goes somewhere private.
	runtime = os.environ.get("XDG_RUNTIME_DIR", "")
	if not os.path.isdir(runtime):
		runtime = tempfile.gettempdir()
	fd, _js_path = tempfile.mkstemp(prefix=PLUGIN + "_", suffix=".js", dir=runtime)
	with os.fdopen(fd, "w") as f:
		f.write(KWIN_JS.replace("@SERVICE@", BUS_NAME).replace("@PATH@", OBJ_PATH).replace("@IFACE@", IFACE))
	fork_watchdog(_js_path)

	DBusGMainLoop(set_as_default=True)
	try:
		bus = dbus.SessionBus()
		if not bus.name_has_owner("org.kde.KWin"):
			raise RuntimeError("org.kde.KWin is not on the session bus")
		scripting = bus.get_object("org.kde.KWin", "/Scripting")
		scripting.get_dbus_method("isScriptLoaded", "org.kde.kwin.Scripting")(PLUGIN)
	except Exception as e:
		try:
			os.unlink(_js_path)
		except OSError:
			pass
		die("no KWin scripting on the session bus (KDE Plasma is needed): %s" % e, 2)

	_loop = GLib.MainLoop()
	win_state = {"last": 0.0, "pending": False}

	def flush_win() -> bool:
		win_state["pending"] = False
		win_state["last"] = time.monotonic()
		line = win_line()
		if line is not None and not once:
			emit(line)
		return False

	class Receiver(dbus.service.Object):
		@dbus.service.method(IFACE, in_signature="s", out_signature="")
		def Update(self, payload):
			global snap
			try:
				snap = json.loads(str(payload))
			except ValueError:
				return
			if win_state["pending"]:
				return
			wait = 1.0 / WIN_HZ - (time.monotonic() - win_state["last"])
			if wait <= 0:
				flush_win()
			else:
				win_state["pending"] = True
				GLib.timeout_add(max(int(wait * 1000), 1), flush_win)

	_name = dbus.service.BusName(BUS_NAME, bus)
	Receiver(bus, OBJ_PATH)

	try:
		from gi.repository import GLibUnix     # PyGObject >= 3.52
		signal_add = GLibUnix.signal_add
	except ImportError:
		signal_add = GLib.unix_signal_add
	for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
		signal_add(GLib.PRIORITY_HIGH, s, lambda *_: quit_now(0) or False)

	try:
		# A script of this name can only be a leftover from a dead process
		# that had our pid (helper and watchdog both killed); drop it first,
		# or loadScript refuses the name.
		scripting.get_dbus_method("unloadScript", "org.kde.kwin.Scripting")(PLUGIN)
		sid = int(scripting.get_dbus_method("loadScript", "org.kde.kwin.Scripting")(_js_path, PLUGIN, signature="ss"))
		if sid < 0:
			raise RuntimeError("loadScript returned %d" % sid)
		bus.get_object("org.kde.KWin", "/Scripting/Script%d" % sid).get_dbus_method("run", "org.kde.kwin.Script")()
	except Exception as e:
		sys.stderr.write("yggapps: could not run the KWin script: %s\n" % e)
		quit_now(2)

	# The cockpit's death, polled rather than PR_SET_PDEATHSIG, which fires
	# when the thread that spawned us ends, not the process.
	def parent_gone() -> bool:
		if os.getppid() != parent_pid:
			quit_now(0)
		return True

	if once:
		# The script's first snapshot, then a 250 ms CPU baseline.
		def first() -> bool:
			if snap is None:
				return True
			sample()
			GLib.timeout_add(250, lambda: (emit(sample()), quit_now(0)))
			return False
		GLib.timeout_add(10, first)
		GLib.timeout_add(5000, lambda: (sys.stderr.write("yggapps: KWin never answered\n"), quit_now(2)))
	else:
		sample()
		GLib.timeout_add(interval_ms, lambda: (emit(sample()), True)[1])
		GLib.timeout_add(500, parent_gone)
	_loop.run()


if __name__ == "__main__":
	main()
