## Zen's desk work, as jobs for the desk hand (desk_hand.gd): what used to
## run inside main.gd's set_zen, now on the hand's thread. Every job takes
## the record (`rec`, below) and plain values, changes only Desk and the
## record, and returns a copy of the record for main.gd to keep and save:
## the prefs only ever hold a record a job finished with, or the one Z on
## read and told before it hid anything, never one half made. Preloaded
## where used, like desk.gd.
##
## The record is one Dictionary, owned by whoever runs the jobs: the hand
## while it runs, the main thread before it starts and after it finishes
## (the quit's release, the guard's --unzen). main.gd never reads it
## otherwise; it reads the copies.
##   held        the desk has zen (the panels hidden, Konsole dissolved)
##   prev        the chrome before zen (Desk.zen_read), {} for no record
##   term        the terminal profile to hand back
##   term_file   konsolerc's DefaultProfile before zen, if file_known
##   konsole     Konsole's layout before zen (Desk.konsole_layout)
##   bars_hidden zen hid a Konsole bar
##   owed        the last sweep left a Konsole unasked (not saved)

const Desk := preload("res://scripts/desk.gd")
const Paths := preload("res://scripts/paths.gd")


static func record() -> Dictionary:
	return {"held": false, "prev": {}, "term": "", "term_file": "", "file_known": false,
		"konsole": {}, "bars_hidden": false, "owed": false}


static func copy(rec: Dictionary) -> Dictionary:
	return rec.duplicate(true)


## Z on. `bare`: Konsole's frames off too (desktop mode). `told` gets the
## record as soon as it is read, before anything is hidden, so a kill
## mid-job leaves prefs that can hand it back. The desk already in zen
## (an intent asked twice) only has its frames set: hiding again would
## forget which bars were showing.
static func on(rec: Dictionary, bare: bool, hand, told: Callable) -> Dictionary:
	Desk.ask_again()
	if rec["held"]:
		Desk.borders(bare)
		return copy(rec)
	# A failed read never replaces an answer we have: that would hide the
	# chrome with nothing recorded to hand back.
	var read := Desk.zen_read()
	if not read.is_empty():
		rec["prev"] = read
	remember_terminal(rec, Desk.terminal_current())
	_remember_terminal_file(rec)
	if Desk.LINUX:
		# Unlike the chrome's, an older snapshot is never worth keeping: a
		# restart with zen on never gets here, so it could only be a stale
		# layout from an earlier zen, and a failed read ({}) just skips the
		# offline layout step.
		rec["konsole"] = Desk.konsole_layout()
	rec["held"] = true
	if hand != null and told.is_valid():
		hand.tell(told, copy(rec))
	Desk.borders(bare)
	chrome(rec, true)
	_terminal(rec, true)
	return copy(rec)


## Z off. The desk already out of zen only has its frames set.
static func off(rec: Dictionary, bare: bool) -> Dictionary:
	Desk.ask_again()
	Desk.borders(bare)
	if not rec["held"]:
		return copy(rec)
	chrome(rec, false)
	_terminal(rec, false)
	rec["held"] = false
	rec["bars_hidden"] = false
	rec["owed"] = false
	Desk.hid_bars = false
	Desk.menubar_back = false
	return copy(rec)


## A start with zen saved on: panels added since join the record.
static func resume(rec: Dictionary) -> Dictionary:
	rec["prev"] = Desk.zen_merge(rec["prev"])
	rec["held"] = true
	chrome(rec, true)
	_terminal(rec, true)
	return copy(rec)


## A start with zen saved off: a cockpit that died in zen may have left
## Konsole's default on the zen profile.
static func settle(rec: Dictionary) -> Dictionary:
	Desk.terminal_unstick(terminal_file(rec))
	return copy(rec)


## A new Konsole window, or a sweep owed: the zen profile again, if zen
## still holds by the time the job runs (a Z off queued first wins).
static func sweep(rec: Dictionary) -> Dictionary:
	if rec["held"]:
		rec["owed"] = not Desk.terminal_set(Desk.TERM_PROFILE)
		_note_bars(rec)
	return copy(rec)


## The chrome in or out, but only with a record of how it was: without
## one zen leaves the Dock and menu bar, or the panels, alone both ways
## (handing back nothing would turn macOS's auto-hide off).
static func chrome(rec: Dictionary, on: bool, careful := false) -> String:
	if (rec["prev"] as Dictionary).is_empty():
		if on:
			print("zen: could not read the desktop's chrome; leaving it as it is")
		return "skipped (no record)"
	return Desk.zen_apply(on, rec["prev"], careful)


static func _terminal(rec: Dictionary, on: bool) -> void:
	var profile: String = Desk.TERM_PROFILE if on else rec["term"]
	rec["owed"] = false
	if not profile.is_empty() and (not on or Desk.terminal_ready()):
		rec["owed"] = not Desk.terminal_set(profile) and on
		_note_bars(rec)
	if not on:
		Desk.terminal_unstick(terminal_file(rec))


static func _note_bars(rec: Dictionary) -> void:
	if rec["held"] and Desk.hid_bars:
		rec["bars_hidden"] = true


## The profile to hand the terminal back. Never the zen profile itself: if
## zen was already in force when it was read (a restart with zen on, a
## crash), the earlier answer stands; failing that, the profile the zen
## profile was built from (the tools/*_zen_profile.sh scripts record it in
## terminal/.source); failing that, Terminal's own "Basic" (Konsole's
## configured default on Linux). Josh's default was Homebrew, and a guess
## of "Basic" lost it once (2026-09-10).
static func remember_terminal(rec: Dictionary, name: String) -> void:
	if not name.is_empty() and name != Desk.TERM_PROFILE:
		rec["term"] = name
		return
	var had: String = rec["term"]
	if not had.is_empty() and had != Desk.TERM_PROFILE:
		return
	var source := Paths.find_up("terminal/.source")
	var from := FileAccess.get_file_as_string(source).strip_edges() if not source.is_empty() else ""
	rec["term"] = from if not from.is_empty() and from != Desk.TERM_PROFILE else Desk.terminal_fallback()


## Linux: konsolerc's default at zen-on (a file name, "" for the built-in
## profile), so zen's profile never outlives zen there (see
## Desk.terminal_default_file). Already the zen profile (a restart with
## zen on, a crash) means the earlier answer stands.
static func _remember_terminal_file(rec: Dictionary) -> void:
	if not Desk.LINUX:
		return
	var file := Desk.terminal_default_file()
	if Desk.read_failed():
		return  # no answer is not "built-in", which would lose his default
	if file != Desk.TERM_PROFILE + ".profile":
		rec["term_file"] = file
		rec["file_known"] = true


## The konsolerc entry to hand back: as read, else found from the
## profile's name (prefs from before it was read).
static func terminal_file(rec: Dictionary) -> String:
	return rec["term_file"] if rec["file_known"] else Desk.terminal_profile_file(rec["term"])


## Konsole's menu bar comes back on the way out where zen's memory of it
## is lost (a restart, the guard): only if zen hid bars and it was on.
static func menubar_back(rec: Dictionary) -> bool:
	var lay: Dictionary = rec["konsole"]
	return rec["bars_hidden"] and not lay.is_empty() and lay["menubar"] != "Disabled"


## Prefs in and out (pure).
static func load_prefs(cfg: ConfigFile) -> Dictionary:
	var rec := record()
	rec["held"] = bool(cfg.get_value("zen", "on", false))
	rec["prev"] = Desk.zen_load(cfg)
	remember_terminal_pure(rec, str(cfg.get_value("zen", "prev_terminal", "")))
	if cfg.has_section_key("zen", "prev_terminal_file"):
		rec["term_file"] = str(cfg.get_value("zen", "prev_terminal_file"))
		rec["file_known"] = true
	rec["bars_hidden"] = bool(cfg.get_value("zen", "bars_hidden", false))
	if cfg.has_section_key("zen", "prev_konsole_state") and cfg.has_section_key("zen", "prev_menubar"):
		rec["konsole"] = {"state": str(cfg.get_value("zen", "prev_konsole_state")), "menubar": str(cfg.get_value("zen", "prev_menubar"))}
	return rec


## Pure: the fallback (a konsolerc read) is a desk call, which the loader
## makes itself (remember_terminal) before the hand has the desk.
static func remember_terminal_pure(rec: Dictionary, name: String) -> void:
	if not name.is_empty() and name != Desk.TERM_PROFILE:
		rec["term"] = name


static func save_prefs(cfg: ConfigFile, rec: Dictionary) -> void:
	cfg.set_value("zen", "on", rec["held"])
	Desk.zen_save(cfg, rec["prev"])
	cfg.set_value("zen", "prev_terminal", rec["term"])
	if rec["file_known"]:
		cfg.set_value("zen", "prev_terminal_file", rec["term_file"])
	if Desk.LINUX:
		cfg.set_value("zen", "bars_hidden", rec["bars_hidden"])
		var lay: Dictionary = rec["konsole"]
		if not lay.is_empty():
			cfg.set_value("zen", "prev_konsole_state", lay["state"])
			cfg.set_value("zen", "prev_menubar", lay["menubar"])
