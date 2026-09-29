extends Node
## Does the key card list every key the cockpit answers, and only those?
## Reads the KEY_ names in main.gd's _unhandled_key_input from its source
## and compares them, by Godot's own name for each keycode, with the card's
## KEYS. Prints and exits 1 on a mismatch.
## Run: godot --headless --path game res://tools/keys_probe.tscn (a scene,
## not -s: the card script needs the autoloads)

const CARD := preload("res://scenes/hull/key_card.gd")


func _ready() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/main.gd")
	var body := src.substr(src.find("func _unhandled_key_input"))
	var next := body.find("\nfunc ", 1)
	if next > 0:
		body = body.substr(0, next)
	var handled := {}
	for m in RegEx.create_from_string("\\bKEY_([A-Z0-9_]+)\\b").search_all(body):
		handled[m.get_string(1).to_lower().replace("_", "")] = true
	var carded := {}
	for code in CARD.keycodes():
		carded[OS.get_keycode_string(code).to_lower().replace(" ", "")] = true
	var missing := handled.keys().filter(func(k): return not carded.has(k))
	var extra := carded.keys().filter(func(k): return not handled.has(k))
	if missing.is_empty() and extra.is_empty():
		print("keys_probe: ok, the card lists all %d keys" % carded.size())
		get_tree().quit(0)
	else:
		print("keys_probe: handled but not on the card: %s; on the card but not handled: %s" % [missing, extra])
		get_tree().quit(1)
