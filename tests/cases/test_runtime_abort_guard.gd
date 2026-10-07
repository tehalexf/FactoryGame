## The half-run guard's own tests.
##
## A GDScript runtime error aborts the frame it fires in, leaves every assertion
## that already passed on the books, and raises nothing. Before this guard the
## runner called such a method `ok` and the untested remainder went unmentioned —
## on a suite that is the project's only guarantee of determinism.
##
## The guard has to fire on a method that aborts after a passing assertion and
## stay silent on a method that finishes, so both directions are tested here: a
## guard that always fires and a guard that never fires are equally useless.
extends TestCase


func _probe() -> TestCase:
	var probe: TestCase = TestCase.new()
	probe.current_test = "probe"
	return probe


## Aborts on the spot. Its caller resumes at the statement after the call, which
## is exactly why a half-run method is invisible without the engine's report.
func _abort_on_a_function_that_does_not_exist() -> void:
	var object: Variant = RefCounted.new()
	object.this_function_does_not_exist()
	fail("unreachable: the line above must abort this frame")


func test_an_abort_after_a_passing_assertion_is_reported_by_the_engine() -> void:
	assert_true(true, "a passing assertion, before anything goes wrong")

	_abort_on_a_function_that_does_not_exist()

	# Draining here is also how this method claims the error as deliberate: the
	# runner drains what is left when the method returns, and finds nothing.
	var errors: PackedStringArray = engine_log.drain()
	assert_eq(errors.size(), 1, "the abort must be reported exactly once: %s" % str(errors))
	assert_true(
		errors[0].contains("Nonexistent function 'this_function_does_not_exist'"),
		"the report must carry the engine's own words: %s" % errors[0]
	)
	assert_true(
		errors[0].contains("_abort_on_a_function_that_does_not_exist"),
		"and name where it fired: %s" % errors[0]
	)


func test_a_method_that_completes_normally_reports_no_abort() -> void:
	assert_true(true, "a method that only asserts logs nothing for the guard to find")
	var errors: PackedStringArray = engine_log.drain()
	assert_eq(errors.size(), 0, "a completing method must not be accused: %s" % str(errors))


## Production code reporting a problem through push_error() is not an abort, and
## several cases rely on driving it there deliberately.
func test_a_reported_error_is_not_mistaken_for_an_abort() -> void:
	push_error("deliberate: the guard must ignore a reported error")
	var errors: PackedStringArray = engine_log.drain()
	assert_eq(errors.size(), 0, "push_error logs ERROR:, aborts nothing: %s" % str(errors))


func test_an_abort_fails_a_method_whose_assertions_all_passed() -> void:
	var probe: TestCase = _probe()
	probe.assert_true(true)
	assert_eq(probe.failures.size(), 0, "a passing assertion on its own records nothing")

	probe.note_runtime_errors(PackedStringArray(["Invalid call. Nonexistent function 'x' (f (res://a.gd:3))"]))

	assert_eq(probe.failures.size(), 1, "an abort must fail the method despite the passing assertion")
	assert_true(probe.failures[0].begins_with("probe:"), "the failure names the method: %s" % probe.failures[0])
	assert_true(
		probe.failures[0].contains("Nonexistent function 'x'"),
		"and quotes the engine error: %s" % probe.failures[0]
	)


func test_no_abort_records_no_failure() -> void:
	var probe: TestCase = _probe()
	probe.assert_true(true)
	probe.note_runtime_errors(PackedStringArray())
	assert_eq(probe.failures.size(), 0, "a guard that fired on nothing would fail every test in the suite")


func test_the_guard_refuses_a_log_it_cannot_read() -> void:
	var live: TestEngineLog = TestEngineLog.new()
	assert_true(
		live.verify_live("Runtime-abort guard: liveness probe"),
		"the engine log must be live, or the runner has nothing to read"
	)

	var missing: TestEngineLog = TestEngineLog.new("user://logs/no_such_log_for_the_guard_test.log")
	assert_false(
		missing.verify_live("Runtime-abort guard: liveness probe against a missing log"),
		"an unreadable log is not live; the runner fails the suite rather than guard nothing"
	)
