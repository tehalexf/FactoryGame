## The TOML reader the tuning file is loaded through.
##
## Godot ships no TOML parser and this repository is public, so vendoring one is
## not an option (docs/ASSETS.md). What is here is the subset the tuning file
## actually uses — sections, key/value pairs, comments, integers, decimals,
## strings, booleans — and nothing else. Anything outside that subset is an error
## naming the line, not a best guess.
##
## A leaf utility with a contract of its own, tested directly for the same reason
## `CsvTable` is: "line 7 says `rate 2` and means `rate = 2`" is not observable
## from behind the Simulation façade.
extends TestCase

const PATH: String = "res://content/tuning.toml"


func _parse(source: String) -> TomlDocument:
	return TomlDocument.parse(source, PATH)


# ── The subset it accepts ─────────────────────────────────────────────────────

func test_a_key_in_a_section_is_read_by_its_dotted_name() -> void:
	var doc: TomlDocument = _parse("[player]\nwalk_speed = 4\n")
	assert_false(doc.has_errors(), doc.describe_errors())
	assert_eq(doc.get_int("player.walk_speed"), 4)


func test_comments_and_blank_lines_are_ignored() -> void:
	var source: String = """
# DEEP FOUNDRY tuning.

[heat]
# Heat added per Item produced.
per_item = 3   # trailing comments too

"""
	var doc: TomlDocument = _parse(source)
	assert_false(doc.has_errors(), doc.describe_errors())
	assert_eq(doc.get_int("heat.per_item"), 3)


func test_integers_may_be_negative() -> void:
	var doc: TomlDocument = _parse("[heat]\ndecay = -2\n")
	assert_eq(doc.get_int("heat.decay"), -2)


func test_booleans_are_read_as_booleans() -> void:
	var doc: TomlDocument = _parse("[run]\nwaves_enabled = true\nchaff_enabled = false\n")
	assert_false(doc.has_errors(), doc.describe_errors())
	assert_true(doc.get_bool("run.waves_enabled"))
	assert_false(doc.get_bool("run.chaff_enabled"))


func test_strings_are_read_without_their_quotes() -> void:
	var doc: TomlDocument = _parse('[run]\nstarting_recipe = "mine_iron_ore"\n')
	assert_false(doc.has_errors(), doc.describe_errors())
	assert_eq(doc.get_string("run.starting_recipe"), "mine_iron_ore")


func test_a_decimal_is_read_as_a_fixed_point_quantity() -> void:
	# The reason tuning is worth having in a file at all: a rate written the way a
	# human thinks about it, converted exactly.
	var doc: TomlDocument = _parse("[player]\nwalk_speed = 4.5\n")
	assert_false(doc.has_errors(), doc.describe_errors())
	assert_eq(doc.get_fixed("player.walk_speed"), 294912, "4.5 * 65536")


func test_a_whole_number_also_reads_as_fixed_point() -> void:
	# So that writing `4` instead of `4.0` for a rate is not a trap.
	var doc: TomlDocument = _parse("[player]\nwalk_speed = 4\n")
	assert_eq(doc.get_fixed("player.walk_speed"), 4 * 65536)


func test_several_sections_keep_their_keys_apart() -> void:
	var doc: TomlDocument = _parse("[a]\nrate = 1\n[b]\nrate = 2\n")
	assert_eq(doc.get_int("a.rate"), 1)
	assert_eq(doc.get_int("b.rate"), 2)


func test_keys_are_listed_in_sorted_order_regardless_of_file_order() -> void:
	# A tuning file is hand-edited and its key order drifts. The Simulation hashes
	# what it loaded, so the order the keys end up in cannot depend on that drift.
	var one: TomlDocument = _parse("[z]\nb = 1\na = 2\n[a]\nc = 3\n")
	var other: TomlDocument = _parse("[a]\nc = 3\n[z]\na = 2\nb = 1\n")
	assert_eq(one.keys(), PackedStringArray(["a.c", "z.a", "z.b"]))
	assert_eq(one.keys(), other.keys())


# ── What it refuses ───────────────────────────────────────────────────────────

func test_a_line_without_an_equals_sign_names_its_line() -> void:
	var doc: TomlDocument = _parse("[player]\nwalk_speed 4\n")
	assert_true(doc.has_errors())
	assert_true(doc.describe_errors().contains("%s:2" % PATH), doc.describe_errors())


func test_a_key_before_any_section_names_its_line() -> void:
	# Every value the Simulation reads is addressed as section.key, so a key with
	# no section has no address.
	var doc: TomlDocument = _parse("walk_speed = 4\n")
	assert_true(doc.has_errors())
	assert_true(doc.describe_errors().contains("%s:1" % PATH), doc.describe_errors())


func test_an_unclosed_section_header_names_its_line() -> void:
	var doc: TomlDocument = _parse("[player\nwalk_speed = 4\n")
	assert_true(doc.has_errors())
	assert_true(doc.describe_errors().contains("%s:1" % PATH), doc.describe_errors())


func test_an_empty_section_name_is_an_error() -> void:
	var doc: TomlDocument = _parse("[]\nwalk_speed = 4\n")
	assert_true(doc.has_errors())


func test_an_unterminated_string_names_its_line() -> void:
	var doc: TomlDocument = _parse('[run]\nname = "unfinished\n')
	assert_true(doc.has_errors())
	assert_true(doc.describe_errors().contains("%s:2" % PATH), doc.describe_errors())


func test_a_value_outside_the_subset_names_its_line_and_the_text() -> void:
	# Arrays, tables and dates are all valid TOML and none of them are supported.
	# Refusing them loudly is the difference between a small parser and a liar.
	var doc: TomlDocument = _parse("[heat]\ncurve = [1, 2, 3]\n")
	assert_true(doc.has_errors())
	var text: String = doc.describe_errors()
	assert_true(text.contains("%s:2" % PATH), text)
	assert_true(text.contains("[1, 2, 3]"), text)


func test_an_empty_value_is_an_error() -> void:
	var doc: TomlDocument = _parse("[heat]\nper_item =\n")
	assert_true(doc.has_errors())


func test_a_duplicate_key_is_an_error_naming_both_lines() -> void:
	# Last-wins would make the file's meaning depend on reading order, and a
	# duplicated key in a hand-edited tuning file is always a mistake.
	var doc: TomlDocument = _parse("[heat]\nper_item = 1\nper_item = 2\n")
	assert_true(doc.has_errors())
	assert_true(doc.describe_errors().contains("per_item"), doc.describe_errors())


func test_a_malformed_key_name_is_an_error() -> void:
	var doc: TomlDocument = _parse("[heat]\nPer Item = 1\n")
	assert_true(doc.has_errors())


func test_a_repeated_section_is_an_error() -> void:
	var doc: TomlDocument = _parse("[heat]\na = 1\n[heat]\nb = 2\n")
	assert_true(doc.has_errors())


# ── Reads that are not satisfied ──────────────────────────────────────────────

func test_a_missing_key_is_reported_rather_than_defaulted() -> void:
	# The whole point. A tuning value the Simulation needs and the file does not
	# have must stop the load, not become zero.
	var doc: TomlDocument = _parse("[player]\nwalk_speed = 4\n")
	assert_false(doc.has("player.sprint_speed"))
	assert_eq(doc.require_fixed("player.sprint_speed"), 0)
	assert_true(doc.has_errors())
	assert_true(doc.describe_errors().contains("player.sprint_speed"), doc.describe_errors())


func test_reading_a_key_as_the_wrong_type_is_an_error() -> void:
	var doc: TomlDocument = _parse('[run]\nname = "deep"\n')
	assert_eq(doc.require_int("run.name"), 0)
	assert_true(doc.has_errors())
	assert_true(doc.describe_errors().contains("run.name"), doc.describe_errors())


func test_a_satisfied_required_read_records_nothing() -> void:
	var doc: TomlDocument = _parse("[player]\nwalk_speed = 4.5\n")
	assert_eq(doc.require_fixed("player.walk_speed"), 294912)
	assert_eq(doc.require_int("player.walk_speed"), 0, "a decimal is not an integer")
	assert_true(doc.has_errors(), "...and asking for one anyway is reported")


func test_every_key_read_is_recorded_so_unused_keys_can_be_found() -> void:
	# A tuning file that still carries a key the Simulation stopped reading is a
	# file that lies to whoever is tuning it.
	var doc: TomlDocument = _parse("[player]\nwalk_speed = 4\n[heat]\nper_item = 1\n")
	doc.require_fixed("player.walk_speed")
	assert_eq(doc.unread_keys(), PackedStringArray(["heat.per_item"]))
