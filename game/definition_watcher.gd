## Watches the content files and produces a new `Definitions` when one is saved.
##
## This is the half of hot-reload that cannot live in the Simulation. It reads the
## clock to decide when to look and the filesystem to see what changed, and ADR 0002
## forbids both inside `sim/` — so it lives here in `game/` next to `TickPump`, which
## exists for the same reason.
##
## What crosses the boundary is a loaded, validated `Definitions`, which `Main` hands
## to the Simulation as an Input Action. The watcher writes no Simulation state and
## holds none.
##
## Change is detected by **content**, not by modification time. Modification times
## have one-second granularity, so two saves in the same second would read as one;
## they also change when an editor touches a file it did not alter. Hashing the content
## files is a few kilobytes of reading, which is why `poll` only does it a couple of
## times a second rather than every frame.
##
## A malformed save produces no definition set at all. Half of hot-reload's value is
## being able to tune with the game running, and all of that value is gone if a typo
## halfway through an edit takes the Run down — so the error is reported, naming the
## file and the row, and the Run carries on with the definitions it has.
class_name DefinitionWatcher
extends RefCounted

## How often `poll` actually looks at the files, in seconds.
const DEFAULT_SECONDS_BETWEEN_CHECKS: float = 0.5

## The directory being watched.
var directory: String = Definitions.CONTENT_DIR

var seconds_between_checks: float = DEFAULT_SECONDS_BETWEEN_CHECKS

## Why the most recent change was refused, each naming the file and the row. Empty
## when the last change loaded cleanly, or when nothing has changed.
var errors: PackedStringArray = PackedStringArray()

## Digest of the file contents as last seen — whether they loaded or not. Recording
## broken content too is what lets a fix be noticed: a watcher that remembered only
## the last *good* content would either re-report the same typo every frame or stop
## looking at the file that is actually being worked on.
var _content_digest: int = 0

var _seconds_since_check: float = 0.0


## The baseline is taken here, at construction, rather than on the first check. A
## lazy baseline would swallow the first edit of a session, which is the one a
## developer is most likely to be trying the feature out with.
func _init(watched_directory: String = Definitions.CONTENT_DIR, check_interval: float = DEFAULT_SECONDS_BETWEEN_CHECKS) -> void:
	directory = watched_directory
	seconds_between_checks = maxf(check_interval, 0.0)
	_content_digest = _read_content_digest()


## Looks at most once per interval. Returns a freshly loaded `Definitions` when the
## files changed and loaded cleanly, and null otherwise — which covers "nothing
## changed", "not time to look yet" and "the change was refused".
func poll(delta_seconds: float) -> Definitions:
	_seconds_since_check += maxf(delta_seconds, 0.0)
	if _seconds_since_check < seconds_between_checks:
		return null
	_seconds_since_check = 0.0
	return check_now()


## Looks immediately, ignoring the interval.
func check_now() -> Definitions:
	var digest: int = _read_content_digest()
	if digest == _content_digest:
		return null

	# Recorded before the load is attempted, so a file that cannot be loaded is still
	# "seen" and is not re-reported on every subsequent check.
	_content_digest = digest

	var definitions: Definitions = Definitions.load_from_directory(directory)
	if definitions.has_errors():
		errors = definitions.errors.duplicate()
		push_error(
			"content definitions were edited but will not load; keeping the current set:\n%s"
			% definitions.describe_errors()
		)
		return null

	errors = PackedStringArray()
	for warning: String in definitions.warnings:
		push_warning(warning)
	return definitions


func has_errors() -> bool:
	return not errors.is_empty()


func describe_errors() -> String:
	return "\n".join(errors)


## One integer standing for the contents of every content file. A missing file contributes
## a distinct value, so deleting one counts as a change rather than reading as an unchanged
## empty string.
func _read_content_digest() -> int:
	var hasher: StateHasher = StateHasher.new()
	for file_name: String in [
		Definitions.MACHINES_FILE,
		Definitions.RECIPES_FILE,
		Definitions.TUNING_FILE,
		Definitions.WAVES_FILE,
		Definitions.DELIVERIES_FILE,
		Definitions.GEAR_FILE,
		Definitions.STRATAGEMS_FILE,
	]:
		var path: String = "%s/%s" % [directory, file_name]
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			hasher.feed_bool(false)
			continue
		hasher.feed_bool(true)
		hasher.feed_text(file.get_as_text())
		file.close()
	return hasher.digest()
