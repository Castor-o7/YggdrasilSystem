#!/usr/bin/env python3
# yggapps' windowless apps: which records outlive their windows (an app in
# the tray, as on macOS) and which leave with them (a session daemon's
# dialog, a reused pid). Fake process tables and cgroups; no KWin, no D-Bus.
#
#   python3 helper/test_windowless.py -v

import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("yggapps", os.path.join(HERE, "yggapps.py"))
yggapps = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(yggapps)  # defines only; main() never runs

U = "/user.slice/user-1000.slice/user@1000.service/"
COCKPIT = 900
CGROUPS = {
	COCKPIT: U + "app.slice/edu.pdx.josh.yggdrasil.service",
	100: U + "session.slice/plasma-plasmashell.service",
	101: U + "app.slice/app-dbus\\x2d:1.2\\x2dorg.kde.kwalletd6.slice/dbus-:1.2-org.kde.kwalletd6@0.service",
	102: U + "background.slice/plasma-polkit-agent.service",
	200: U + "app.slice/app-org.kde.konsole-108112.scope/tab(108120).scope",
	201: U + "app.slice/app-flatpak-com.google.Chrome-5.scope",
	202: U + "app.slice/edu.pdx.josh.yggdrasil.service",   # spawned by the cockpit
	203: U + "app.slice/app-org.godotengine.Godot@7ba84e61a2b44c0e9d3f5a1b2c3d4e5f.service",   # from Kickoff
	204: U + "app.slice/app-pamac\\x2dtray\\x2dplasma@autostart.service",
	205: U + "app.slice/edu.pdx.josh.nerviewer-adhoc.service",
}


def group(aid, *pids):
	return {"id": aid, "name": aid, "pids": set(pids), "wins": [{}]}


class Windowless(unittest.TestCase):
	def setUp(self):
		yggapps._known.clear()
		yggapps._applike.clear()
		yggapps._own_cg = None
		self._pp, self._cg = yggapps.parent_pid, yggapps.cgroup
		yggapps.parent_pid = COCKPIT
		yggapps.cgroup = lambda pid: CGROUPS.get(pid)
		self.procs = {p: (1, 0, 1000 + p) for p in list(CGROUPS) + [300]}

	def tearDown(self):
		yggapps.parent_pid, yggapps.cgroup = self._pp, self._cg

	def run_twice(self, first, then=None):
		yggapps.keep_windowless(first, self.procs)
		groups = dict(then or {})
		yggapps.keep_windowless(groups, self.procs)
		return groups

	def test_daemon_dialog_leaves_with_its_window(self):
		for pid, aid in ((100, "plasma"), (101, "kwallet"), (102, "polkit")):
			self.assertNotIn(aid, self.run_twice({aid: group(aid, pid)}))

	def test_scoped_app_stays_windowless(self):
		g = self.run_twice({"tray": group("tray", 200)})
		self.assertEqual(g["tray"]["pids"], {200})
		self.assertEqual(g["tray"]["wins"], [])

	def test_launcher_started_app_stays_windowless(self):
		self.assertIn("godot", self.run_twice({"godot": group("godot", 203)}))

	def test_autostarted_tray_app_stays_windowless(self):
		self.assertIn("tray", self.run_twice({"tray": group("tray", 204)}))

	def test_nerviewer_in_its_own_unit_stays(self):
		nv = yggapps.NERVIEWER_ID
		self.assertIn(nv, self.run_twice({nv: group(nv, 205)}))

	def test_cockpit_spawned_app_stays(self):
		self.assertIn("kid", self.run_twice({"kid": group("kid", 202)}))

	def test_no_cgroup_v2_keeps_as_before(self):
		self.assertIn("old", self.run_twice({"old": group("old", 300)}))

	def test_reused_pid_drops(self):
		yggapps.keep_windowless({"tray": group("tray", 200)}, self.procs)
		self.procs[200] = (1, 0, 99999)
		groups = {}
		yggapps.keep_windowless(groups, self.procs)
		self.assertNotIn("tray", groups)
		self.assertNotIn((200, 1200), yggapps._applike)

	def test_pwa_closes_while_browser_stays(self):
		g = self.run_twice({"chrome": group("chrome", 201), "pwa": group("pwa", 201)},
			{"chrome": group("chrome", 201)})
		self.assertNotIn("pwa", g)

	def test_daemon_still_listed_while_its_window_is_open(self):
		g = {"plasma": group("plasma", 100)}
		yggapps.keep_windowless(g, self.procs)
		self.assertIn("plasma", g)


if __name__ == "__main__":
	unittest.main()
