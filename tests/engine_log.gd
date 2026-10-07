## Reader for the engine's own log file, used to notice GDScript runtime errors.
##
## A GDScript runtime error — a call to a function that does not exist, an index
## out of range, a division by zero — aborts the frame it occurred in and nothing
## else. The caller carries on from the statement after the call, which is why the
## test runner survives one at all. It also means a test method can be cut off
## halfway with every assertion it had already evaluated still counted, and
## nothing in GDScript raises, returns or signals to say so. The error is only
## ever *reported*, never thrown.
##
## So the runner reads the report. Godot mirrors everything it prints into
## `user://logs/godot.log` and flushes as it goes, so the file is readable by the
## very process writing it. Each runtime error appears there as a line prefixed
## `SCRIPT ERROR: `, which is the prefix GDScript aborts carry and which neither
## `push_error()` (`ERROR: `) nor `push_warning()` (`WARNING: `) use — so a test
## that deliberately drives production code into reporting an error is unaffected.
##
## The runner holds one of these for the whole suite and drains it around every
## test method, so each method is judged only on what it printed itself.
class_name TestEngineLog
extends RefCounted

## The prefix Godot gives a GDScript runtime error, and only a runtime error.
const SCRIPT_ERROR_PREFIX: String = "SCRIPT ERROR: "

## The line Godot puts under an error naming the function and line it fired in.
const LOCATION_PREFIX: String = "at: "

## How many times to re-read the log waiting for the engine's writes to settle,
## and how long to pause between attempts. Cheap: the common case is that the
## first two reads already agree and nothing waits at all.
const SETTLE_ATTEMPTS: int = 20
const SETTLE_DELAY_MS: int = 5

var _path: String

## How many runtime errors the whole log has already been credited with. The
## reader counts errors rather than bytes: Godot rotates and re-opens this file
## on its own schedule, so a byte cursor can find the file shorter than it left
## it and has no way to tell a rotation from a lost report. A count survives
## that — after a rotation the log holds fewer errors than the count, which
## means nothing new, which is the truth.
var _seen: int = 0


func _init(path: String = "") -> void:
	_path = path if path != "" else default_path()
	reset()


## Where this run's engine log is.
##
## `tools/run_tests.sh` gives each run a private log under `.godot/` and names it
## here, because the default lives in the user data directory Godot derives from
## the project name — which every worktree of this repo shares. A sibling
## checkout running its own suite would otherwise rotate this run's log away
## mid-suite.
static func default_path() -> String:
	var from_runner: String = OS.get_environment("DEEP_FOUNDRY_TEST_LOG")
	if from_runner != "":
		return from_runner
	return "user://logs/godot.log"


func path() -> String:
	return _path


## Confirms the engine really is mirroring its output into the log, by printing
## `probe` and looking for it there. Without this the guard could quietly become
## a no-op — file logging off, a different log path — and every half-run method
## would go back to reporting `ok`. The runner fails the whole suite if this
## returns false, because a suite whose guards are not working is not green.
func verify_live(probe: String) -> bool:
	reset()
	print(probe)
	# The engine writes its log on its own schedule, so the line is not always
	# there the instant print() returns. Wait for it rather than concluding the
	# guard is dead — a false negative here fails the whole suite.
	for _attempt: int in range(SETTLE_ATTEMPTS):
		if _read_all().contains(probe):
			return true
		OS.delay_msec(SETTLE_DELAY_MS)
	return false


## Forgets everything written so far, so the next drain reports only what follows.
func reset() -> void:
	_seen = _all_errors().size()


## Returns one description per GDScript runtime error logged since the last drain
## or reset, and advances past them. Empty when nothing aborted.
func drain() -> PackedStringArray:
	var all: PackedStringArray = _all_errors()
	if all.size() < _seen:
		# Fewer errors than we have already been credited with means the engine
		# rotated the file under us. Nothing was missed that this reader could
		# have reported; resynchronise and carry on rather than accusing the
		# suite of an abort that did not happen.
		_seen = all.size()
		return PackedStringArray()

	var fresh: PackedStringArray = PackedStringArray()
	for index: int in range(_seen, all.size()):
		fresh.append(all[index])
	_seen = all.size()
	return fresh


## Every runtime error the log currently holds, oldest first.
##
## Reads until two consecutive reads agree. The engine flushes on its own
## schedule, so a single snapshot taken while it is mid-write can be short by a
## line — which would report an abort one drain late, or miss it entirely if the
## next drain belongs to a different test method.
func _all_errors() -> PackedStringArray:
	var previous: String = _read_all()
	for _attempt: int in range(SETTLE_ATTEMPTS):
		OS.delay_msec(SETTLE_DELAY_MS)
		var current: String = _read_all()
		if current == previous:
			return _parse(current)
		previous = current
	return _parse(previous)


func _read_all() -> String:
	var file: FileAccess = FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _parse(text: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var lines: PackedStringArray = text.split("\n")
	for index: int in range(lines.size()):
		var line: String = lines[index]
		if not line.begins_with(SCRIPT_ERROR_PREFIX):
			continue
		var description: String = line.trim_prefix(SCRIPT_ERROR_PREFIX).strip_edges()
		# The following line, if present, is `   at: func (res://file.gd:12)`.
		if index + 1 < lines.size():
			var next: String = lines[index + 1].strip_edges()
			if next.begins_with(LOCATION_PREFIX):
				description = "%s (%s)" % [description, next.trim_prefix(LOCATION_PREFIX)]
		found.append(description)
	return found




