## Headless test runner. Zero dependencies — no addons, no editor.
##
##     godot --headless --path . --script res://tests/run_tests.gd
##
## Exits 0 when every test passes and 1 on any failure, load error, or an empty
## suite, so CI can treat the exit code as the whole answer.
##
## Optional filter: pass a substring and only matching `case.method` names run.
##
##     godot --headless --path . --script res://tests/run_tests.gd -- determinism
##
## Discovery and execution order are both sorted by name. The suite is itself a
## deterministic program; a test run that depends on filesystem enumeration
## order would be a poor advertisement for ADR 0002.
extends SceneTree

const CASES_DIR: String = "res://tests/cases"

var _passed: int = 0
var _failed: int = 0
var _failure_log: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var filter: String = _read_filter()
	var paths: PackedStringArray = _discover_case_paths()

	if paths.is_empty():
		printerr("No test cases found in %s" % CASES_DIR)
		quit(1)
		return

	print("Running test cases from %s" % CASES_DIR)
	if filter != "":
		print('Filter: "%s"' % filter)
	print("")

	for path: String in paths:
		_run_case(path, filter)

	# An unfiltered run that executed nothing is a broken suite, not a green one.
	if filter == "" and _passed + _failed == 0:
		_fail_hard("discovered %d case files but ran no tests" % paths.size())

	_report()
	quit(1 if _failed > 0 else 0)


## Everything after a bare `--` is ours; Godot keeps its own flags away from it.
func _read_filter() -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		return args[0]
	return ""


func _discover_case_paths() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(CASES_DIR)
	if dir == null:
		printerr("Cannot open %s" % CASES_DIR)
		return found

	for file_name: String in dir.get_files():
		# Exported projects serve `.gd` as `.gd.remap`; source trees do not.
		var name: String = file_name.trim_suffix(".remap")
		if name.begins_with("test_") and name.ends_with(".gd"):
			found.append("%s/%s" % [CASES_DIR, name])

	found.sort()
	return found


func _run_case(path: String, filter: String) -> void:
	# A file with a parse error does not load as null — it loads as a GDScript
	# that cannot be instantiated. Both must turn the suite red rather than be
	# skipped, or a syntax error would read as a pass.
	var script: Resource = load(path)
	if script == null or not (script is GDScript):
		_fail_hard("%s — failed to load" % path)
		return

	var gdscript: GDScript = script
	if not gdscript.can_instantiate():
		_fail_hard("%s — parse error, cannot instantiate (see the ERROR above)" % path)
		return

	var instance: Variant = gdscript.new()
	if not (instance is TestCase):
		_fail_hard("%s — script does not extend TestCase" % path)
		return

	var test_case: TestCase = instance
	var case_name: String = path.get_file().trim_suffix(".gd")

	for method_name: String in _test_method_names(test_case):
		var label: String = "%s.%s" % [case_name, method_name]
		if filter != "" and not label.contains(filter):
			continue
		_run_method(gdscript, case_name, method_name, label)


## A fresh instance per method, so no test can lean on another's leftovers.
func _run_method(script: GDScript, case_name: String, method_name: String, label: String) -> void:
	var test_case: TestCase = script.new()
	test_case.current_test = method_name

	test_case.before_each()
	if not test_case.aborted:
		test_case.call(method_name)
	test_case.after_each()

	if test_case.failures.is_empty():
		_passed += 1
		print("  ok    %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)
		for failure: String in test_case.failures:
			var line: String = "        %s" % failure.trim_prefix("%s: " % method_name)
			print(line)
			_failure_log.append("%s: %s" % [case_name, failure])


func _test_method_names(test_case: TestCase) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for method: Dictionary in test_case.get_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_") and not names.has(method_name):
			names.append(method_name)
	names.sort()
	return names


func _fail_hard(reason: String) -> void:
	_failed += 1
	print("  FAIL  %s" % reason)
	_failure_log.append(reason)


func _report() -> void:
	print("")
	if _failed == 0:
		print("PASS — %d tests" % _passed)
		return

	print("Failures:")
	for failure: String in _failure_log:
		print("  %s" % failure)
	print("")
	print("FAIL — %d passed, %d failed" % [_passed, _failed])
