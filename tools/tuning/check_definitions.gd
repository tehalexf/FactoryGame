extends SceneTree

## Ask the game's own loader whether a content directory would load.
##
## The dashboard already refuses anything outside the TOML subset before it
## writes, by porting `sim/toml_document.gd` into Python. What that port cannot
## know is the second half of `Definitions`: that `bob_stride_metres` may not be
## 0 because it is a divisor, that Survey View has to be above eye level, that a
## Siege Hulk has to outrange every Turret. Those rules are a page of
## cross-checks in `sim/definitions.gd`, and restating them in Python would be a
## second source of truth that drifts — the exact failure the tuning file's
## comments are written to avoid.
##
## So the dashboard asks the loader instead. It renders the candidate file into a
## throwaway directory next to copies of the other six content files, runs this,
## and only writes the real file if the whole definition set loads. The live
## `content/` is never the thing being tested, so a refused value never reaches
## the game at all.
##
## This opens no channel into a running game: it is a second reader of files,
## not a back door into a Run. The file is still the only API.
##
##     godot --headless --path . --script tools/tuning/check_definitions.gd -- <dir>
##
## Exits 0 when the set loads. Prints each error on its own line, prefixed
## `DEFINITION-ERROR: `, and exits 1 when it does not.

func _initialize() -> void:
	var directory: String = ""
	var after_separator: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--":
			after_separator = true
			continue
		directory = argument
	if directory.is_empty():
		for argument: String in OS.get_cmdline_args():
			if after_separator:
				directory = argument
			if argument == "--":
				after_separator = true

	if directory.is_empty():
		print("DEFINITION-ERROR: no content directory given")
		quit(1)
		return

	var definitions: Definitions = Definitions.load_from_directory(directory)
	if not definitions.errors.is_empty():
		for error: String in definitions.errors:
			print("DEFINITION-ERROR: %s" % error)
		quit(1)
		return

	print("DEFINITIONS-OK")
	quit(0)
