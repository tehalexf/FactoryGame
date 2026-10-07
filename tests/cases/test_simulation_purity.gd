## Enforces the ADR 0002 prohibitions against the Simulation's actual source.
##
## The first half proves the checker works, because a linter that finds nothing is
## indistinguishable from a linter that looks for nothing. The second half points
## it at res://sim/ and requires silence.
extends TestCase

const SIM_DIR: String = "res://sim"


func _rules_found(source: String) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for violation: PurityCheck.Violation in PurityCheck.scan_source(source, "probe.gd"):
		names.append(violation.rule)
	return names


# ── The checker has teeth ─────────────────────────────────────────────────────

func test_clean_source_passes() -> void:
	var clean: String = "var total: int = Fixed.mul(a, b)\nvar count: int = 3\n"
	assert_eq(PurityCheck.scan_source(clean).size(), 0)


func test_wall_clock_is_flagged() -> void:
	assert_true(
		_rules_found("var t: int = Time.get_ticks_usec()").has("reads wall-clock time"),
		"a Time call must be caught"
	)


func test_unseeded_randomness_is_flagged() -> void:
	assert_true(_rules_found("var r: int = randi()").has("uses unseeded randomness"))
	assert_true(_rules_found("var r: int = randf_range(0, 1)").has("uses unseeded randomness"))
	assert_true(
		_rules_found("var g = RandomNumberGenerator.new()").has("uses the engine random generator")
	)


func test_floats_are_flagged() -> void:
	assert_true(_rules_found("var ratio: float = 1").has("uses a float"))
	assert_true(_rules_found("var ratio = 0.75").has("uses a decimal literal"))
	assert_true(_rules_found("var turn = TAU").has("uses a float constant"))
	assert_true(_rules_found("var p = Vector3(1, 2, 3)").has("uses a float-based vector"))


func test_integer_vectors_are_not_flagged() -> void:
	# Vector3i is integer and explicitly sanctioned by DESIGN.md for grid tiles.
	assert_false(
		_rules_found("var tile: Vector3i = Vector3i(1, 0, 2)").has("uses a float-based vector"),
		"Vector3i must not be mistaken for Vector3"
	)


func test_unordered_iteration_risks_are_flagged() -> void:
	assert_true(
		_rules_found("var by_id: Dictionary = {}").has(
			"uses a Dictionary, whose iteration order must be justified"
		)
	)
	assert_true(
		_rules_found("for k in thing.keys():").has(
			"iterates keys or values, which may be unordered"
		)
	)


func test_node_tree_access_is_flagged() -> void:
	assert_true(_rules_found("var n = get_tree().root").has("touches the Godot node tree"))
	assert_true(_rules_found("extends Node3D").has("touches the Godot node tree"))


func test_await_is_flagged() -> void:
	assert_true(_rules_found("await something()").has("awaits, which makes tick ordering non-local"))


# ── …but not false teeth ──────────────────────────────────────────────────────

func test_prose_in_comments_is_not_flagged() -> void:
	var source: String = "# Floats and Time.get_ticks_usec() are banned; see randi().\nvar n: int = 1\n"
	assert_eq(
		PurityCheck.scan_source(source).size(),
		0,
		"documentation must be free to name the thing it forbids"
	)


func test_docstrings_are_not_flagged() -> void:
	var source: String = "## Converts to float at the rendering boundary.\nvar n: int = 1\n"
	assert_eq(PurityCheck.scan_source(source).size(), 0)


func test_a_hash_inside_a_string_does_not_start_a_comment() -> void:
	var source: String = 'var label: String = "# not a comment" ; var bad: float = 1'
	assert_true(
		_rules_found(source).has("uses a float"),
		"the float after a quoted hash must still be seen"
	)


func test_an_annotated_exemption_is_respected() -> void:
	var source: String = "return float(value)  # purity-ok: the rendering boundary\n"
	assert_eq(
		PurityCheck.scan_source(source).size(),
		0,
		"a documented exception is how the sanctioned boundary is expressed"
	)


func test_an_exemption_covers_only_its_own_line() -> void:
	var source: String = "var a: float = 1  # purity-ok: reason\nvar b: float = 2\n"
	var violations: Array = PurityCheck.scan_source(source)
	assert_eq(violations.size(), 1, "the unannotated line must still be caught")
	assert_eq((violations[0] as PurityCheck.Violation).line_number, 2)


# ── The real Simulation ───────────────────────────────────────────────────────

func test_the_simulation_directory_has_sources_to_check() -> void:
	# Without this, an empty or mistyped directory would make the check below pass
	# by scanning nothing at all.
	var sources: PackedStringArray = PurityCheck.list_sources(SIM_DIR)
	assert_true(sources.size() >= 5, "expected the Simulation's sources, found %d" % sources.size())


func test_the_simulation_breaks_none_of_the_rules() -> void:
	var violations: Array = PurityCheck.scan_directory(SIM_DIR)
	if violations.is_empty():
		return
	for violation: PurityCheck.Violation in violations:
		fail(violation.describe())


func test_the_sanctioned_exemptions_are_few_and_accounted_for() -> void:
	# Every escape hatch in the Simulation, counted. If this number grows, someone
	# should have to argue for it in review rather than let it drift upward.
	var exempted: int = 0
	for path: String in PurityCheck.list_sources(SIM_DIR):
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		for line: String in file.get_as_text().split("\n"):
			if line.contains(PurityCheck.EXEMPTION_MARKER):
				exempted += 1
		file.close()
	assert_true(
		exempted <= 4,
		"%d exempted lines in the Simulation; the rendering boundary needs very few" % exempted
	)
