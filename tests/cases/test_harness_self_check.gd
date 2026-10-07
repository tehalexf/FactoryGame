## The suite's own credibility check.
##
## Every other test is worthless if a false assertion can pass quietly. These
## tests drive a second TestCase instance as data and inspect what it recorded.
extends TestCase


func _probe() -> TestCase:
	var probe: TestCase = TestCase.new()
	probe.current_test = "probe"
	return probe


func test_satisfied_assertions_record_nothing() -> void:
	var probe: TestCase = _probe()
	probe.assert_eq(2 + 2, 4)
	probe.assert_ne(1, 2)
	probe.assert_true(true)
	probe.assert_false(false)
	probe.assert_null(null)
	probe.assert_not_null(0)
	assert_eq(probe.failures.size(), 0, "satisfied assertions must stay silent")


func test_violated_assertion_is_recorded() -> void:
	var probe: TestCase = _probe()
	probe.assert_eq(2 + 2, 5)
	assert_eq(probe.failures.size(), 1, "a false assert_eq must record a failure")
	assert_true(
		probe.failures[0].contains("expected 5, got 4"),
		"the failure should name both values: %s" % probe.failures[0]
	)


func test_every_assertion_kind_can_fail() -> void:
	var probe: TestCase = _probe()
	probe.assert_eq(1, 2)
	probe.assert_ne(3, 3)
	probe.assert_true(false)
	probe.assert_false(true)
	probe.assert_null(7)
	probe.assert_not_null(null)
	probe.fail("explicit")
	assert_eq(probe.failures.size(), 7, "no assertion kind may be incapable of failing")


func test_assertions_return_their_verdict() -> void:
	var probe: TestCase = _probe()
	assert_true(probe.assert_eq(1, 1), "a satisfied assertion returns true")
	assert_false(probe.assert_eq(1, 2), "a violated assertion returns false")


func test_failures_name_the_test_method() -> void:
	var probe: TestCase = _probe()
	probe.current_test = "test_something_specific"
	probe.fail("boom")
	assert_true(
		probe.failures[0].begins_with("test_something_specific:"),
		"a failure must identify its method: %s" % probe.failures[0]
	)


func test_fail_fast_marks_the_case_aborted() -> void:
	var probe: TestCase = _probe()
	assert_false(probe.aborted, "a fresh case is not aborted")
	probe.fail_fast("cannot continue")
	assert_true(probe.aborted, "fail_fast must abort")
	assert_eq(probe.failures.size(), 1, "fail_fast also records the failure")


func test_arrays_compare_by_contents_across_array_types() -> void:
	var probe: TestCase = _probe()
	var packed: PackedInt64Array = PackedInt64Array([1, 2, 3])
	probe.assert_eq(packed, [1, 2, 3])
	assert_eq(probe.failures.size(), 0, "a packed array equals a plain array of the same ints")
	probe.assert_eq(packed, [1, 2, 4])
	assert_eq(probe.failures.size(), 1, "differing contents must still fail")
