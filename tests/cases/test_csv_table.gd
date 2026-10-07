## The CSV reader the definition tables are loaded through.
##
## A leaf utility with a contract of its own, so it is tested directly rather
## than through the Simulation façade: its whole job is to turn a malformed table
## into a message that names the file and the row, and that is not observable
## from behind `step`, `hash` and `query_*`.
##
## The bar this file holds the reader to: a typo must never parse as a usable
## value. Every malformed case below has to produce an error that a human can act
## on without opening the loader's source.
extends TestCase

const PATH: String = "res://content/machines.csv"


func _parse(source: String, required: Array = []) -> CsvTable:
	return CsvTable.parse(source, PATH, PackedStringArray(required))


# ── Well-formed tables ────────────────────────────────────────────────────────

func test_a_table_reads_its_header_and_rows() -> void:
	var table: CsvTable = _parse("id,rate\nminer,2\nsmelter,3\n")
	assert_false(table.has_errors(), table.describe_errors())
	assert_eq(table.row_count(), 2)
	assert_eq(table.value(0, "id"), "miner")
	assert_eq(table.value(1, "rate"), "3")


func test_blank_lines_and_comment_lines_are_skipped() -> void:
	# The tables are hand-edited, so they get commented and spaced like the tuning
	# file does.
	var table: CsvTable = _parse("# Machines.\nid,rate\n\nminer,2\n# the smelter\nsmelter,3\n")
	assert_false(table.has_errors(), table.describe_errors())
	assert_eq(table.row_count(), 2)
	assert_eq(table.value(1, "id"), "smelter")


func test_a_row_remembers_the_line_it_came_from() -> void:
	# Line numbers are what make an error message actionable, so they count the
	# physical lines of the file including the ones that were skipped.
	var table: CsvTable = _parse("# Machines.\nid,rate\n\nminer,2\nsmelter,3\n")
	assert_eq(table.line_number(0), 4)
	assert_eq(table.line_number(1), 5)


func test_fields_are_trimmed() -> void:
	var table: CsvTable = _parse("id , rate\n miner , 2 \n")
	assert_eq(table.value(0, "id"), "miner")
	assert_eq(table.value(0, "rate"), "2")


func test_an_empty_field_reads_as_an_empty_string() -> void:
	var table: CsvTable = _parse("id,inputs\nminer,\n")
	assert_false(table.has_errors(), table.describe_errors())
	assert_eq(table.value(0, "inputs"), "")


func test_a_table_with_a_header_and_no_rows_is_legal_and_empty() -> void:
	var table: CsvTable = _parse("id,rate\n")
	assert_false(table.has_errors(), table.describe_errors())
	assert_eq(table.row_count(), 0)


# ── Malformed tables name the file and the row ────────────────────────────────

func test_an_empty_file_is_an_error_naming_the_file() -> void:
	var table: CsvTable = _parse("")
	assert_true(table.has_errors(), "an empty table is a broken table, not an empty one")
	assert_true(table.describe_errors().contains(PATH))


func test_a_row_with_too_few_fields_names_its_line() -> void:
	var table: CsvTable = _parse("id,rate,health\nminer,2\n")
	assert_true(table.has_errors())
	assert_true(
		table.describe_errors().contains("%s:2" % PATH),
		"expected the offending line named, got: %s" % table.describe_errors()
	)


func test_a_row_with_too_many_fields_names_its_line() -> void:
	var table: CsvTable = _parse("id,rate\nminer,2,extra\n")
	assert_true(table.has_errors())
	assert_true(table.describe_errors().contains("%s:2" % PATH))


func test_a_duplicated_column_name_is_an_error() -> void:
	# Two columns of the same name makes every read of it ambiguous, so it is
	# rejected rather than resolved by a rule nobody will remember.
	var table: CsvTable = _parse("id,rate,rate\nminer,2,3\n")
	assert_true(table.has_errors())
	assert_true(table.describe_errors().contains("rate"))


func test_a_missing_required_column_is_an_error_naming_the_column() -> void:
	var table: CsvTable = _parse("id,rate\nminer,2\n", ["id", "rate", "health"])
	assert_true(table.has_errors())
	var text: String = table.describe_errors()
	assert_true(text.contains("health"), "expected the missing column named, got: %s" % text)
	assert_true(text.contains(PATH))


func test_a_row_that_failed_to_parse_is_not_offered_as_data() -> void:
	# The alternative — handing back a short row padded with blanks — is exactly
	# the silent default this whole module exists to prevent.
	var table: CsvTable = _parse("id,rate,health\nminer,2\nsmelter,3,500\n")
	assert_eq(table.row_count(), 1, "only the well-formed row is data")
	assert_eq(table.value(0, "id"), "smelter")


# ── Typed reads record their own errors ───────────────────────────────────────

func test_a_required_int_reads_as_an_integer() -> void:
	var table: CsvTable = _parse("id,health\nminer,400\n")
	assert_eq(table.require_int(0, "health"), 400)
	assert_false(table.has_errors(), table.describe_errors())


func test_a_non_numeric_int_is_an_error_naming_the_file_row_and_column() -> void:
	var table: CsvTable = _parse("id,health\nminer,lots\n")
	assert_eq(table.require_int(0, "health"), 0)
	var text: String = table.describe_errors()
	assert_true(text.contains("%s:2" % PATH), text)
	assert_true(text.contains("health"), text)
	assert_true(text.contains("lots"), text)


func test_a_required_fixed_point_value_parses_a_decimal_exactly() -> void:
	var table: CsvTable = _parse("id,seconds\nsmelter,3.2\n")
	assert_eq(table.require_fixed(0, "seconds"), 209715, "3.2 * 65536 floored")
	assert_false(table.has_errors(), table.describe_errors())


func test_a_malformed_rate_is_an_error_rather_than_zero() -> void:
	# The failure this project cannot afford: a typo'd rate that quietly becomes 0
	# and costs hours of wondering why nothing is produced.
	var table: CsvTable = _parse("id,seconds\nsmelter,3,2\n")
	assert_true(table.has_errors())

	var comma: CsvTable = _parse("id,seconds\nsmelter,fast\n")
	comma.require_fixed(0, "seconds")
	assert_true(comma.has_errors())
	assert_true(comma.describe_errors().contains("fast"))


func test_a_required_id_rejects_an_empty_or_malformed_identifier() -> void:
	var table: CsvTable = _parse("id,rate\n,2\n")
	assert_eq(table.require_id(0, "id"), "")
	assert_true(table.has_errors(), "a row with a blank id has no id")

	var spaced: CsvTable = _parse("id,rate\nIron Ore,2\n")
	assert_eq(spaced.require_id(0, "id"), "")
	assert_true(spaced.describe_errors().contains("Iron Ore"), spaced.describe_errors())


func test_a_well_formed_id_is_accepted() -> void:
	var table: CsvTable = _parse("id\nminer_mk1\n")
	assert_eq(table.require_id(0, "id"), "miner_mk1")
	assert_false(table.has_errors(), table.describe_errors())


func test_reading_an_unknown_column_is_an_error_not_an_empty_string() -> void:
	var table: CsvTable = _parse("id\nminer\n")
	assert_eq(table.require_int(0, "health"), 0)
	assert_true(table.has_errors(), "a loader asking for a column that is not there is a bug")
