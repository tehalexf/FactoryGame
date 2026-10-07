## Scans GDScript source for constructs ADR 0002 forbids inside the Simulation.
##
## The behavioural tests prove the Simulation is deterministic *today*. This
## proves the next ticket cannot quietly make it otherwise — a stray `Time.`,
## `randi()` or float slips through code review far more easily than it slips
## through a grep, and by the time a replay fixture notices, the question is which
## of fifty commits did it.
##
## Blunt on purpose. It flags the construct wherever it appears and offers one
## escape hatch: a `# purity-ok: <reason>` comment on the same line, which skips
## that line entirely. So the sanctioned exceptions — `Fixed.to_float` at the
## rendering boundary — are visible in the source, annotated, and countable.
##
## Comments and docstrings are stripped before scanning, so prose may discuss
## floats and wall-clock time freely. Only code is checked.
class_name PurityCheck
extends RefCounted

const EXEMPTION_MARKER: String = "# purity-ok:"


## One flagged line.
class Violation extends RefCounted:
	var file_path: String = ""
	var line_number: int = 0
	var rule: String = ""
	var text: String = ""

	func describe() -> String:
		return "%s:%d — %s — %s" % [file_path, line_number, rule, text.strip_edges()]


## Rule name to the pattern that catches it. Each is an ADR 0002 or ADR 0001
## prohibition made mechanical.
const RULES: Dictionary = {
	"reads wall-clock time": "\\bTime\\s*\\.",
	"reads the operating system": "\\bOS\\s*\\.",
	"reads engine frame state": "\\bEngine\\s*\\.",
	"uses unseeded randomness": "\\brand(i|f|i_range|f_range|omize|_from_seed)\\s*\\(",
	"uses the engine random generator": "\\bRandomNumberGenerator\\b",
	"uses a float": "\\bfloat\\b",
	"uses a decimal literal": "[0-9]+\\.[0-9]+",
	"uses a float constant": "\\b(PI|TAU|INF|NAN)\\b",
	"uses a float-based vector": "\\bVector[234](?!i)\\b",
	"uses a Dictionary, whose iteration order must be justified": "\\bDictionary\\b",
	"iterates keys or values, which may be unordered": "\\.\\s*(keys|values)\\s*\\(",
	"touches the Godot node tree": "\\b(Node|Node2D|Node3D|SceneTree|get_tree|get_node|add_child|queue_free)\\b",
	"awaits, which makes tick ordering non-local": "\\bawait\\b",
}


## Scans one source string. `path` is used only for reporting.
static func scan_source(source: String, path: String = "") -> Array:
	var violations: Array = []
	var regexes: Dictionary = _compiled_rules()
	var rule_names: Array = RULES.keys()
	rule_names.sort()

	var line_number: int = 0
	for raw_line: String in source.split("\n"):
		line_number += 1

		if raw_line.contains(EXEMPTION_MARKER):
			continue

		var code: String = strip_comment(raw_line)
		if code.strip_edges().is_empty():
			continue

		for rule_name: String in rule_names:
			var regex: RegEx = regexes[rule_name]
			if regex.search(code) != null:
				var violation: Violation = Violation.new()
				violation.file_path = path
				violation.line_number = line_number
				violation.rule = rule_name
				violation.text = raw_line
				violations.append(violation)

	return violations


## Scans every `.gd` file in a directory, sorted by name.
static func scan_directory(dir_path: String) -> Array:
	var violations: Array = []
	for path: String in list_sources(dir_path):
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		violations.append_array(scan_source(file.get_as_text(), path))
		file.close()
	return violations


## The `.gd` files in a directory, sorted.
static func list_sources(dir_path: String) -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return paths
	for file_name: String in dir.get_files():
		var name: String = file_name.trim_suffix(".remap")
		if name.ends_with(".gd"):
			paths.append("%s/%s" % [dir_path, name])
	paths.sort()
	return paths


## Removes a trailing comment, leaving string literals intact so a `#` inside a
## quoted string is not mistaken for the start of a comment.
static func strip_comment(line: String) -> String:
	var in_single: bool = false
	var in_double: bool = false

	for index: int in range(line.length()):
		var character: String = line[index]
		if character == '"' and not in_single:
			in_double = not in_double
		elif character == "'" and not in_double:
			in_single = not in_single
		elif character == "#" and not in_single and not in_double:
			return line.substr(0, index)

	return line


static func _compiled_rules() -> Dictionary:
	var compiled: Dictionary = {}
	for rule_name: String in RULES.keys():
		var regex: RegEx = RegEx.new()
		regex.compile(RULES[rule_name])
		compiled[rule_name] = regex
	return compiled
