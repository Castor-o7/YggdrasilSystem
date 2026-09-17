## Paths. Preloaded where used (not a class_name: the global class cache
## is the editor's, and the tools run without it).
## Files that live outside the project: the sibling NERViewer app, the
## tools directory. In the editor the project root is one level above
## res://; in an exported app the executable sits in
## dist/<App>.app/Contents/MacOS, four levels below it, and res:// is the
## bundle's Resources. Both starts are walked upward until the relative
## path exists, so the same call works in both.


static func find_up(rel: String, max_depth := 8) -> String:
	for start in [OS.get_executable_path().get_base_dir(), ProjectSettings.globalize_path("res://")]:
		var dir: String = start
		for _i in max_depth:
			var candidate := dir.path_join(rel)
			if FileAccess.file_exists(candidate) or DirAccess.dir_exists_absolute(candidate):
				return candidate
			var parent := dir.get_base_dir()
			if parent.is_empty() or parent == dir:
				break
			dir = parent
	return ""


## A binary the build makes: beside the executable in an exported app
## (Contents/MacOS), in the project's bin/ in the editor.
static func bundled(name: String) -> String:
	var beside_exe := OS.get_executable_path().get_base_dir().path_join(name)
	if FileAccess.file_exists(beside_exe):
		return beside_exe
	return ProjectSettings.globalize_path("res://bin/".path_join(name))
