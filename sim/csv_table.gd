## A CSV table of content definitions, and the errors found reading it.
##
## Why hand-rolled rather than `FileAccess.get_csv_line`: that helper reads a line
## at a time and has no notion of a header, a required column, or where the line
## it just read came from. The whole value of this module is the last of those —
## an error that names the file and the row, so a typo'd rate is a message a human
## can act on instead of a zero that costs an afternoon.
##
## The format is the hand-editable subset, nothing more:
##
##     # comments run to end of line, on their own line
##     id,display_name,seconds
##     smelter_mk1,Smelter Mk1,3.2
##
## First non-blank, non-comment line is the header. Fields are comma-separated and
## trimmed. No quoting, no embedded commas, no multi-line fields — a definition
## table that needs those is a definition table that has outgrown being a table.
##
## Reading is total but never lenient. A malformed row is dropped from the data and
## recorded as an error; a typed read of a malformed field returns a zero *and*
## records an error. Callers must consult `has_errors` before trusting anything,
## which is why `DefinitionLoader` refuses to build a definition set from a table
## with any error at all.
class_name CsvTable
extends RefCounted

## Every problem found, in the order found, each naming the file and the line.
var errors: PackedStringArray = PackedStringArray()

## The file these rows came from. Reporting only.
var source_path: String = ""

var _header: PackedStringArray = PackedStringArray()
var _rows: Array = []
var _row_lines: PackedInt64Array = PackedInt64Array()


## Reads a table. `required_columns` are the columns the caller intends to read;
## naming them up front turns a renamed column into one clear error instead of a
## row's worth of confusing ones.
static func parse(source: String, path: String, required_columns: PackedStringArray = PackedStringArray()) -> CsvTable:
	var table: CsvTable = CsvTable.new()
	table.source_path = path

	var line_number: int = 0
	for raw_line: String in source.split("\n"):
		line_number += 1

		var line: String = raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue

		if table._header.is_empty():
			table._read_header(line, line_number)
			continue

		table._read_row(line, line_number)

	if table._header.is_empty():
		table._report(0, "no header row; the table is empty")

	for column: String in required_columns:
		if table._header.find(column) == -1:
			table._report(0, 'required column "%s" is missing' % column)

	return table


func has_errors() -> bool:
	return not errors.is_empty()


## Every error as one block of text, one per line. Empty when there are none.
func describe_errors() -> String:
	return "\n".join(errors)


## How many well-formed rows the table holds. Malformed rows are not counted,
## because handing one back padded with blanks is the silent default this module
## exists to prevent.
func row_count() -> int:
	return _rows.size()


## The physical line a row came from, counting comments and blank lines.
func line_number(row_index: int) -> int:
	if row_index < 0 or row_index >= _row_lines.size():
		return 0
	return _row_lines[row_index]


## The columns, in file order.
func columns() -> PackedStringArray:
	return _header.duplicate()


## A field as written. An unknown column or row reads as the empty string without
## recording anything — the `require_*` family is what enforces presence.
func value(row_index: int, column: String) -> String:
	var column_index: int = _header.find(column)
	if column_index == -1 or row_index < 0 or row_index >= _rows.size():
		return ""
	var row: PackedStringArray = _rows[row_index]
	return row[column_index]


# ── Typed reads ───────────────────────────────────────────────────────────────
# Each returns a usable zero value *and* records an error, so a loader can read a
# whole row and report everything wrong with it rather than stopping at the first
# problem.

## A whole number. Anything else is an error.
func require_int(row_index: int, column: String) -> int:
	var text: String = _require_present(row_index, column)
	if text.is_empty():
		return 0
	if not text.is_valid_int():
		_report_field(row_index, column, "expected a whole number", text)
		return 0
	return text.to_int()


## A fixed-point quantity, written in decimal. The one place a rate written for a
## human becomes a Simulation quantity, and it is exact — see
## `Fixed.from_decimal_string`.
func require_fixed(row_index: int, column: String) -> int:
	var text: String = _require_present(row_index, column)
	if text.is_empty():
		return 0
	if not Fixed.is_decimal_string(text):
		_report_field(row_index, column, "expected a decimal number", text)
		return 0
	return Fixed.from_decimal_string(text)


## An identifier: lowercase letters, digits and underscores. Identifiers are keys
## that Recipes, Machines and save files refer to each other by, so the character
## set is narrow on purpose — "Iron Ore" and "iron_ore" being different keys that
## look the same is a bug nobody enjoys finding.
func require_id(row_index: int, column: String) -> String:
	var text: String = _require_present(row_index, column)
	if text.is_empty():
		return ""
	if not is_identifier(text):
		_report_field(
			row_index, column, "expected an identifier of lowercase letters, digits and _", text
		)
		return ""
	return text


## True for a well-formed identifier.
static func is_identifier(text: String) -> bool:
	if text.is_empty():
		return false
	for index: int in range(text.length()):
		var character: String = text[index]
		var is_lower: bool = character >= "a" and character <= "z"
		var is_digit: bool = character >= "0" and character <= "9"
		if not (is_lower or is_digit or character == "_"):
			return false
	return true


## Records an error against a row from outside — how the loader reports a problem
## only it can see, such as a Recipe id that matches no Recipe.
func report_row(row_index: int, detail: String) -> void:
	_report(line_number(row_index), detail)


# ── Reading ───────────────────────────────────────────────────────────────────

func _read_header(line: String, line_at: int) -> void:
	var names: PackedStringArray = _split_fields(line)
	for index: int in range(names.size()):
		var name: String = names[index]
		if name.is_empty():
			_report(line_at, "column %d of the header has no name" % (index + 1))
		elif names.slice(0, index).has(name):
			_report(line_at, 'column "%s" appears more than once in the header' % name)
	_header = names


func _read_row(line: String, line_at: int) -> void:
	var fields: PackedStringArray = _split_fields(line)
	if fields.size() != _header.size():
		_report(
			line_at,
			"expected %d fields to match the header, found %d" % [_header.size(), fields.size()]
		)
		return
	_rows.append(fields)
	_row_lines.append(line_at)


func _split_fields(line: String) -> PackedStringArray:
	var fields: PackedStringArray = PackedStringArray()
	for field: String in line.split(","):
		fields.append(field.strip_edges())
	return fields


## The raw field, or the empty string after recording why it could not be read.
func _require_present(row_index: int, column: String) -> String:
	if _header.find(column) == -1:
		_report(line_number(row_index), 'no column named "%s"' % column)
		return ""
	var text: String = value(row_index, column)
	if text.is_empty():
		_report_field(row_index, column, "is required but empty", text)
		return ""
	return text


func _report_field(row_index: int, column: String, detail: String, text: String) -> void:
	_report(line_number(row_index), '%s: %s, got "%s"' % [column, detail, text])


func _report(line_at: int, detail: String) -> void:
	if line_at > 0:
		errors.append("%s:%d: %s" % [source_path, line_at, detail])
	else:
		errors.append("%s: %s" % [source_path, detail])
