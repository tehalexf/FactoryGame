## The tuning file, parsed. A deliberately small TOML reader.
##
## Tuning values live in a commented file because the person tuning balance is not
## always the person editing code, and because a comment explaining *why* a number
## is 3 is worth more than the number. TOML is the format that supports that;
## Godot ships no parser for it, and this repository is public, so vendoring one is
## out (docs/ASSETS.md). So this reads the subset the tuning file uses:
##
##     # a comment
##     [section]
##     an_integer = 3
##     a_rate = 4.5          # becomes a fixed-point quantity, exactly
##     a_string = "iron_ore"
##     a_flag = true         # or false
##
## And nothing else. Arrays, inline tables, nested tables, dates, multi-line
## strings and bare multi-word keys are all valid TOML and all rejected here, by
## name and line number. A parser that silently ignores what it does not
## understand is worse than no parser, because the tuning value you thought you
## changed did not change.
##
## Values are addressed as `section.key`. Keys are held sorted, so the order the
## Simulation reads and hashes them in does not depend on the order a human
## happened to type them — which is the difference between a tuning file that can
## be reorganised and one that silently changes the state hash when it is.
class_name TomlDocument
extends RefCounted

enum ValueKind {
	INTEGER = 0,
	## A decimal in the file, held as a fixed-point Simulation quantity.
	FIXED = 1,
	STRING = 2,
	BOOLEAN = 3,
}

## Every problem found, each naming the file and the line.
var errors: PackedStringArray = PackedStringArray()

var source_path: String = ""

## One parsed `section.key = value`.
class Entry extends RefCounted:
	var key: String = ""
	var kind: ValueKind = ValueKind.INTEGER
	## Holds the integer, the fixed-point value, or 0/1 for a boolean.
	var number: int = 0
	var text: String = ""
	var line: int = 0
	var was_read: bool = false

var _entries: Array = []
## The keys of `_entries`, in the same order, so a lookup is a `find` rather than a
## walk over objects.
var _keys: PackedStringArray = PackedStringArray()


static func parse(source: String, path: String) -> TomlDocument:
	var doc: TomlDocument = TomlDocument.new()
	doc.source_path = path

	var section: String = ""
	var seen_sections: PackedStringArray = PackedStringArray()
	var line_number: int = 0

	for raw_line: String in source.split("\n"):
		line_number += 1

		var line: String = doc._strip_comment(raw_line).strip_edges()
		if line.is_empty():
			continue

		if line.begins_with("["):
			section = doc._read_section(line, line_number, seen_sections)
			continue

		doc._read_pair(line, line_number, section)

	doc._sort_entries()
	return doc


# ── Inspecting ────────────────────────────────────────────────────────────────

func has_errors() -> bool:
	return not errors.is_empty()


func describe_errors() -> String:
	return "\n".join(errors)


## Every key present, sorted. This is the order the Simulation hashes them in.
func keys() -> PackedStringArray:
	return _keys.duplicate()


func has(key: String) -> bool:
	return _keys.find(key) != -1


## Keys the file defines that nothing has read. A tuning file carrying a key the
## Simulation stopped reading is a file that lies to whoever is tuning it, so the
## loader reports these.
func unread_keys() -> PackedStringArray:
	var unread: PackedStringArray = PackedStringArray()
	for entry: Entry in _entries:
		if not entry.was_read:
			unread.append(entry.key)
	return unread


## The line a key was defined on. 0 when it is not defined.
func line_of(key: String) -> int:
	var entry: Entry = _find(key)
	return 0 if entry == null else entry.line


# ── Reads that report nothing ─────────────────────────────────────────────────
# For callers that have already established the key is there and the right kind.

func get_int(key: String, fallback: int = 0) -> int:
	var entry: Entry = _find(key)
	if entry == null or entry.kind != ValueKind.INTEGER:
		return fallback
	entry.was_read = true
	return entry.number


## An integer or a decimal, as a fixed-point quantity. Writing `4` where `4.0` was
## meant is a mistake nobody should be punished for, so both are accepted.
func get_fixed(key: String, fallback: int = 0) -> int:
	var entry: Entry = _find(key)
	if entry == null:
		return fallback
	if entry.kind == ValueKind.FIXED:
		entry.was_read = true
		return entry.number
	if entry.kind == ValueKind.INTEGER:
		entry.was_read = true
		return Fixed.from_int(entry.number)
	return fallback


func get_string(key: String, fallback: String = "") -> String:
	var entry: Entry = _find(key)
	if entry == null or entry.kind != ValueKind.STRING:
		return fallback
	entry.was_read = true
	return entry.text


func get_bool(key: String, fallback: bool = false) -> bool:
	var entry: Entry = _find(key)
	if entry == null or entry.kind != ValueKind.BOOLEAN:
		return fallback
	entry.was_read = true
	return entry.number == 1


# ── Reads the Simulation depends on ───────────────────────────────────────────
# A missing or wrongly-typed value here is a broken tuning file, so each of these
# records an error naming the key rather than handing back a plausible zero.

func require_int(key: String) -> int:
	if not _require_kind(key, ValueKind.INTEGER, "a whole number"):
		return 0
	return get_int(key)


func require_fixed(key: String) -> int:
	var entry: Entry = _find(key)
	if entry == null:
		_report(0, 'required tuning value "%s" is missing' % key)
		return 0
	if entry.kind != ValueKind.FIXED and entry.kind != ValueKind.INTEGER:
		_report(entry.line, '"%s" must be a number' % key)
		return 0
	return get_fixed(key)


func require_string(key: String) -> String:
	if not _require_kind(key, ValueKind.STRING, "a quoted string"):
		return ""
	return get_string(key)


func require_bool(key: String) -> bool:
	if not _require_kind(key, ValueKind.BOOLEAN, "true or false"):
		return false
	return get_bool(key)


## Feeds every key and value into a hash, in sorted key order. This is how tuning
## becomes part of the Simulation's state hash: change a number in the file and the
## hash changes, visibly, rather than the Run quietly behaving differently.
func feed_into(hasher: StateHasher) -> void:
	hasher.feed_int(_entries.size())
	for entry: Entry in _entries:
		hasher.feed_text(entry.key)
		hasher.feed_int(entry.kind)
		hasher.feed_int(entry.number)
		hasher.feed_text(entry.text)


# ── Parsing ───────────────────────────────────────────────────────────────────

func _read_section(line: String, line_at: int, seen: PackedStringArray) -> String:
	if not line.ends_with("]"):
		_report(line_at, "section header is not closed with ]")
		return ""

	var name: String = line.substr(1, line.length() - 2).strip_edges()
	if not CsvTable.is_identifier(name):
		_report(line_at, 'section name "%s" must be an identifier' % name)
		return ""
	if seen.has(name):
		_report(line_at, "section [%s] appears more than once" % name)
		return ""

	seen.append(name)
	return name


func _read_pair(line: String, line_at: int, section: String) -> void:
	var separator: int = line.find("=")
	if separator == -1:
		_report(line_at, 'expected "key = value", got "%s"' % line)
		return

	var name: String = line.substr(0, separator).strip_edges()
	var text: String = line.substr(separator + 1).strip_edges()

	if not CsvTable.is_identifier(name):
		_report(line_at, 'key "%s" must be an identifier' % name)
		return
	if section.is_empty():
		_report(line_at, 'key "%s" is not inside a [section], so it has no address' % name)
		return
	if text.is_empty():
		_report(line_at, 'key "%s" has no value' % name)
		return

	var key: String = "%s.%s" % [section, name]
	var existing: Entry = _find(key)
	if existing != null:
		_report(line_at, '"%s" is already defined on line %d' % [key, existing.line])
		return

	var entry: Entry = _read_value(text, line_at)
	if entry == null:
		return
	entry.key = key
	entry.line = line_at
	_entries.append(entry)
	_keys.append(key)


## Classifies a value, or reports that it is outside the supported subset.
func _read_value(text: String, line_at: int) -> Entry:
	var entry: Entry = Entry.new()

	if text == "true" or text == "false":
		entry.kind = ValueKind.BOOLEAN
		entry.number = 1 if text == "true" else 0
		return entry

	if text.begins_with('"'):
		if text.length() < 2 or not text.ends_with('"'):
			_report(line_at, "string is not closed with a quote")
			return null
		entry.kind = ValueKind.STRING
		entry.text = text.substr(1, text.length() - 2)
		return entry

	if text.is_valid_int():
		entry.kind = ValueKind.INTEGER
		entry.number = text.to_int()
		return entry

	if Fixed.is_decimal_string(text):
		entry.kind = ValueKind.FIXED
		entry.number = Fixed.from_decimal_string(text)
		return entry

	_report(
		line_at,
		'value "%s" is outside the supported subset (integer, decimal, "string", true, false)' % text
	)
	return null


## Removes a trailing comment, leaving a `#` inside a quoted string alone.
func _strip_comment(line: String) -> String:
	var in_string: bool = false
	for index: int in range(line.length()):
		var character: String = line[index]
		if character == '"':
			in_string = not in_string
		elif character == "#" and not in_string:
			return line.substr(0, index)
	return line


## Sorts entries by key. Keys are unique, so this is a total order and does not
## depend on the sort being stable.
func _sort_entries() -> void:
	_entries.sort_custom(func(a: Entry, b: Entry) -> bool: return a.key < b.key)
	_keys.clear()
	for entry: Entry in _entries:
		_keys.append(entry.key)


func _find(key: String) -> Entry:
	var index: int = _keys.find(key)
	if index == -1:
		return null
	return _entries[index]


func _require_kind(key: String, kind: ValueKind, described: String) -> bool:
	var entry: Entry = _find(key)
	if entry == null:
		_report(0, 'required tuning value "%s" is missing' % key)
		return false
	if entry.kind != kind:
		_report(entry.line, '"%s" must be %s' % [key, described])
		return false
	return true


func _report(line_at: int, detail: String) -> void:
	if line_at > 0:
		errors.append("%s:%d: %s" % [source_path, line_at, detail])
	else:
		errors.append("%s: %s" % [source_path, detail])
