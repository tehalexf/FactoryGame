## Base class for every test case.
##
## Subclass it in `res://tests/cases/`, name the file `test_*.gd`, and write
## methods named `test_*`. The runner discovers both by sorted name, so the
## suite's execution order is deterministic.
##
## Assertions record failures rather than aborting, so one method reports every
## way it is wrong in a single run. `fail_fast()` is available when a later
## assertion would crash on the earlier one's wreckage.
class_name TestCase
extends RefCounted

## Failure messages recorded by this instance, in the order they occurred.
var failures: PackedStringArray = PackedStringArray()

## Name of the test method currently executing. Set by the runner.
var current_test: String = ""

## Set true by fail_fast(); the runner skips the rest of the method.
var aborted: bool = false

## How many assertions this instance evaluated. The runner requires at least one:
## a GDScript runtime error — a call to a method that does not exist, an index out
## of range — aborts the method on the spot without raising anything a test can
## catch, which would otherwise leave a half-executed method looking like a pass.
## Counting assertions turns that silence into a failure.
var assertions: int = 0


## Override to build state shared by every test method in the case.
func before_each() -> void:
	pass


## Override to tear that state down.
func after_each() -> void:
	pass


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> bool:
	if _values_equal(actual, expected):
		_counted()
		return true
	return _record("expected %s, got %s" % [_show(expected), _show(actual)], message)


func assert_ne(actual: Variant, forbidden: Variant, message: String = "") -> bool:
	if not _values_equal(actual, forbidden):
		_counted()
		return true
	return _record("expected a value other than %s" % _show(forbidden), message)


func assert_true(value: bool, message: String = "") -> bool:
	if value:
		_counted()
		return true
	return _record("expected true, got false", message)


func assert_false(value: bool, message: String = "") -> bool:
	if not value:
		_counted()
		return true
	return _record("expected false, got true", message)


func assert_null(value: Variant, message: String = "") -> bool:
	if value == null:
		_counted()
		return true
	return _record("expected null, got %s" % _show(value), message)


func assert_not_null(value: Variant, message: String = "") -> bool:
	if value != null:
		_counted()
		return true
	return _record("expected a value, got null", message)


## Records a failure unconditionally.
func fail(reason: String) -> bool:
	return _record(reason, "")


## Records a failure and stops the current test method.
func fail_fast(reason: String) -> bool:
	aborted = true
	return _record(reason, "")


## Called by every assertion, whatever its verdict.
func _counted() -> void:
	assertions += 1


func _record(detail: String, message: String) -> bool:
	assertions += 1
	var text: String = detail
	if message != "":
		text = "%s — %s" % [message, detail]
	failures.append("%s: %s" % [current_test, text])
	return false


## Arrays and dictionaries compare by value in GDScript's `==`, but
## PackedInt64Array vs Array of the same contents does not. Normalise first so
## assertions compare what the test author meant.
func _values_equal(a: Variant, b: Variant) -> bool:
	if a is Array or a is PackedInt64Array or a is PackedStringArray:
		if b is Array or b is PackedInt64Array or b is PackedStringArray:
			return _to_plain_array(a) == _to_plain_array(b)
	return a == b


func _to_plain_array(value: Variant) -> Array:
	var out: Array = []
	for item: Variant in value:
		out.append(item)
	return out


func _show(value: Variant) -> String:
	if value is String:
		return '"%s"' % value
	return str(value)
