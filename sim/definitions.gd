## The content definitions a Simulation is built from: Machines, Recipes, Items and
## tuning, loaded from files in `content/`.
##
## Why this exists: so that every later content ticket is additive rather than
## structural. Adding a Machine is a row in `machines.csv`; adding a Recipe is a row
## in `recipes.csv`; changing balance is a number in `tuning.toml`. No code change,
## no registry, no enum to extend — and the person tuning balance never has to be
## the person editing code.
##
## Three properties this module owes the rest of the project:
##
## **Deterministic.** Loading is part of Simulation construction, so the same files
## must produce the same `digest()` on every machine and in every process. Machines,
## Recipes and Items are therefore sorted by id, and tuning keys are sorted too, so
## the order rows happen to be written in — which drifts every time a human edits a
## table — cannot reach the state hash. Comments and blank lines cannot either.
##
## **Loud.** Every malformed value is an error naming the file, the row and the
## column. There are no defaults: a typo'd rate does not become 0, a missing tuning
## key does not become 0, a Machine pointing at a Recipe that does not exist is not
## quietly Recipe-less. And a set with any error at all carries *no* definitions,
## because half a definition set is more dangerous than none — it looks usable.
##
## **Immutable.** Nothing mutates a loaded set. Hot-reload builds a new one and
## swaps it in via an Input Action (see `InputAction.Kind.RELOAD_DEFINITIONS`), so
## the swap is ordered, visible in the state hash, and reproducible in a replay.
##
## Usage:
##
##     var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
##     if definitions.has_errors():
##         push_error(definitions.describe_errors())   # and do not start a Run
##     var sim: Simulation = Simulation.new(seed, players, definitions)
class_name Definitions
extends RefCounted

## Where the shipped content lives. `content/.gdignore` keeps Godot's importer out
## of it — left to itself, it claims every `.csv` as a translation table.
const CONTENT_DIR: String = "res://content"

const MACHINES_FILE: String = "machines.csv"
const RECIPES_FILE: String = "recipes.csv"
const TUNING_FILE: String = "tuning.toml"

const MACHINE_COLUMNS: Array = [
	"id",
	"display_name",
	"role",
	"footprint_x",
	"footprint_z",
	"power_draw_kw",
	"health",
	"max_depth",
	"recipe_id",
]

const RECIPE_COLUMNS: Array = ["id", "display_name", "inputs", "outputs", "seconds"]

## Tuning keys the Simulation reads. Each must be present.
const TUNING_PLAYER_WALK_SPEED: String = "player.walk_speed_metres_per_second"

## Every problem that makes this set unusable, each naming the file and the row.
var errors: PackedStringArray = PackedStringArray()

## Problems that do not make the set unusable but mislead whoever is reading the
## files — chiefly a tuning key nothing reads.
var warnings: PackedStringArray = PackedStringArray()

## How fast a player walks, in fixed-point metres per second.
var player_walk_speed: int = 0

var _machines: Array = []
var _machine_ids: PackedStringArray = PackedStringArray()
var _recipes: Array = []
var _recipe_ids: PackedStringArray = PackedStringArray()
var _item_ids: PackedStringArray = PackedStringArray()


# ── Loading ───────────────────────────────────────────────────────────────────

## Reads the three files out of a directory. A missing or unreadable file is an
## error naming the path, never an empty table.
static func load_from_directory(dir_path: String) -> Definitions:
	var missing: PackedStringArray = PackedStringArray()
	for file_name: String in [MACHINES_FILE, RECIPES_FILE, TUNING_FILE]:
		var path: String = "%s/%s" % [dir_path, file_name]
		if not FileAccess.file_exists(path):
			missing.append(path)

	if not missing.is_empty():
		var unreadable: Definitions = Definitions.new()
		for path: String in missing:
			unreadable.errors.append("%s: no such file" % path)
		return unreadable

	var machines: String = _read_file("%s/%s" % [dir_path, MACHINES_FILE])
	var recipes: String = _read_file("%s/%s" % [dir_path, RECIPES_FILE])
	var tuning: String = _read_file("%s/%s" % [dir_path, TUNING_FILE])

	var definitions: Definitions = parse(
		machines,
		recipes,
		tuning,
		"%s/%s" % [dir_path, MACHINES_FILE],
		"%s/%s" % [dir_path, RECIPES_FILE],
		"%s/%s" % [dir_path, TUNING_FILE]
	)
	return definitions


## Builds a set from the file contents directly. The paths are used only to name
## errors, which is what lets a test exercise a malformed table without writing one
## to disk.
static func parse(
	machines_source: String,
	recipes_source: String,
	tuning_source: String,
	machines_path: String = MACHINES_FILE,
	recipes_path: String = RECIPES_FILE,
	tuning_path: String = TUNING_FILE
) -> Definitions:
	var definitions: Definitions = Definitions.new()

	var machines: CsvTable = CsvTable.parse(machines_source, machines_path, PackedStringArray(MACHINE_COLUMNS))
	var recipes: CsvTable = CsvTable.parse(recipes_source, recipes_path, PackedStringArray(RECIPE_COLUMNS))
	var tuning: TomlDocument = TomlDocument.parse(tuning_source, tuning_path)

	definitions._read_recipes(recipes)
	definitions._intern_items()
	definitions._read_machines(machines)
	definitions._check_machines_against_recipes(machines)
	definitions._read_tuning(tuning)

	# Errors are gathered in file order — machines, then Recipes, then tuning — so
	# the report reads like a list of things to go and fix.
	definitions.errors.append_array(machines.errors)
	definitions.errors.append_array(recipes.errors)
	definitions.errors.append_array(tuning.errors)

	if definitions.has_errors():
		definitions._discard_content()

	return definitions


## An empty set that is explicitly in error. What a caller gets when there is
## nothing to load, so that "no definitions" can never be mistaken for "loaded".
static func unloaded(reason: String) -> Definitions:
	var definitions: Definitions = Definitions.new()
	definitions.errors.append(reason)
	return definitions


# ── Verdict ───────────────────────────────────────────────────────────────────

func has_errors() -> bool:
	return not errors.is_empty()


func describe_errors() -> String:
	return "\n".join(errors)


func describe_warnings() -> String:
	return "\n".join(warnings)


# ── Machines ──────────────────────────────────────────────────────────────────

func machine_count() -> int:
	return _machines.size()


## Every Machine id, sorted. This is the index order the Simulation uses.
func machine_ids() -> PackedStringArray:
	return _machine_ids.duplicate()


func has_machine(id: String) -> bool:
	return _machine_ids.find(id) != -1


## The index of a Machine definition, or -1.
func machine_index(id: String) -> int:
	return _machine_ids.find(id)


func machine_at(index: int) -> MachineDefinition:
	if index < 0 or index >= _machines.size():
		return null
	return _machines[index]


## A Machine by id, or null. Null rather than a blank definition, so a mistyped id
## cannot be mistaken for a Machine with every value at zero.
func machine(id: String) -> MachineDefinition:
	return machine_at(machine_index(id))


# ── Recipes ───────────────────────────────────────────────────────────────────

func recipe_count() -> int:
	return _recipes.size()


func recipe_ids() -> PackedStringArray:
	return _recipe_ids.duplicate()


func has_recipe(id: String) -> bool:
	return _recipe_ids.find(id) != -1


func recipe_index(id: String) -> int:
	return _recipe_ids.find(id)


func recipe_at(index: int) -> RecipeDefinition:
	if index < 0 or index >= _recipes.size():
		return null
	return _recipes[index]


func recipe(id: String) -> RecipeDefinition:
	return recipe_at(recipe_index(id))


# ── Items ─────────────────────────────────────────────────────────────────────

func item_count() -> int:
	return _item_ids.size()


## Every Item id, sorted. Exactly the Items the Recipes mention.
func item_ids() -> PackedStringArray:
	return _item_ids.duplicate()


func item_index(id: String) -> int:
	return _item_ids.find(id)


func item_id(index: int) -> String:
	if index < 0 or index >= _item_ids.size():
		return ""
	return _item_ids[index]


# ── Hashing ───────────────────────────────────────────────────────────────────

## Reduces the whole definition set to one integer.
##
## Fed into `Simulation.hash()`, so the definitions a Run is using are part of its
## state hash. That is what makes a definition change visible rather than silent: a
## replay recorded under one set cannot pass under another, and a reload mid-Run
## changes the hash at the exact tick it is applied.
##
## Deliberately insensitive to file paths, row order, line numbers, comments and
## blank lines — a digest that changed when someone tidied a table would make the
## determinism guarantee unusable in practice.
func digest() -> int:
	var hasher: StateHasher = StateHasher.new()

	hasher.feed_int(_item_ids.size())
	for id: String in _item_ids:
		hasher.feed_text(id)

	hasher.feed_int(_recipes.size())
	for definition: RecipeDefinition in _recipes:
		definition.feed_into(hasher)

	hasher.feed_int(_machines.size())
	for definition: MachineDefinition in _machines:
		definition.feed_into(hasher)

	hasher.feed_int(player_walk_speed)

	# Errors are part of the verdict, not of the content, but a set that failed to
	# load must never share a digest with one that loaded empty.
	hasher.feed_int(errors.size())

	return hasher.digest()


# ── Reading the Recipe table ──────────────────────────────────────────────────

func _read_recipes(table: CsvTable) -> void:
	for row: int in range(table.row_count()):
		var definition: RecipeDefinition = RecipeDefinition.new()
		definition.source_row = row
		definition.id = table.require_id(row, "id")
		definition.display_name = table.value(row, "display_name")
		definition.duration_seconds = table.require_fixed(row, "seconds")

		if definition.duration_seconds <= 0:
			table.report_row(
				row,
				'seconds: a Recipe must take more than no time, got "%s"'
				% table.value(row, "seconds")
			)

		_read_item_list(table, row, "inputs", definition, true)
		_read_item_list(table, row, "outputs", definition, false)

		if definition.output_count() == 0:
			table.report_row(row, "outputs: a Recipe with no outputs produces nothing")

		if definition.id.is_empty():
			continue
		if _recipe_ids.find(definition.id) != -1:
			table.report_row(row, 'id: "%s" is already defined' % definition.id)
			continue

		_recipe_ids.append(definition.id)
		_recipes.append(definition)

	_sort_recipes()


## Reads an `item:count;item:count` list. An empty field is an empty list, which is
## legal for inputs and not for outputs.
func _read_item_list(
	table: CsvTable, row: int, column: String, definition: RecipeDefinition, is_input: bool
) -> void:
	var names: PackedStringArray = PackedStringArray()
	var quantities: PackedInt64Array = PackedInt64Array()
	var text: String = table.value(row, column).strip_edges()

	if not text.is_empty():
		for entry: String in text.split(";"):
			var pair: PackedStringArray = entry.split(":")
			if pair.size() != 2:
				table.report_row(
					row, '%s: expected "item:count", got "%s"' % [column, entry.strip_edges()]
				)
				continue

			var item: String = pair[0].strip_edges()
			var quantity_text: String = pair[1].strip_edges()

			if not CsvTable.is_identifier(item):
				table.report_row(
					row, '%s: "%s" is not a valid Item id' % [column, item]
				)
				continue
			if not quantity_text.is_valid_int() or quantity_text.to_int() <= 0:
				table.report_row(
					row,
					'%s: "%s" must be a positive whole quantity, got "%s"'
					% [column, item, quantity_text]
				)
				continue
			if names.has(item):
				table.report_row(row, '%s: "%s" appears twice' % [column, item])
				continue

			names.append(item)
			quantities.append(quantity_text.to_int())

	if is_input:
		definition.set_inputs(names, quantities)
	else:
		definition.set_outputs(names, quantities)


## Collects every Item the Recipes mention, sorted, and hands each Recipe the
## indices. There is no Item table: naming an Item in a Recipe is how it comes to
## exist, which is one fewer file that can fall out of step.
func _intern_items() -> void:
	for definition: RecipeDefinition in _recipes:
		for item: String in definition.mentioned_items():
			if _item_ids.find(item) == -1:
				_item_ids.append(item)
	_item_ids.sort()

	for definition: RecipeDefinition in _recipes:
		definition.resolve_items(_item_ids)


# ── Reading the Machine table ─────────────────────────────────────────────────

func _read_machines(table: CsvTable) -> void:
	for row: int in range(table.row_count()):
		var definition: MachineDefinition = MachineDefinition.new()
		definition.source_row = row
		definition.id = table.require_id(row, "id")
		definition.display_name = table.value(row, "display_name")
		definition.footprint_x = table.require_int(row, "footprint_x")
		definition.footprint_z = table.require_int(row, "footprint_z")
		definition.power_draw_kw = table.require_int(row, "power_draw_kw")
		definition.health = table.require_int(row, "health")
		definition.max_depth = table.require_int(row, "max_depth")
		definition.recipe_id = table.require_id(row, "recipe_id")

		var role: int = MachineDefinition.parse_role(table.value(row, "role"))
		if role == -1:
			table.report_row(
				row,
				'role: expected one of %s, got "%s"'
				% [", ".join(PackedStringArray(MachineDefinition.ROLE_NAMES)), table.value(row, "role")]
			)
		else:
			definition.role = role

		_check_machine_values(table, row, definition, role)

		if definition.id.is_empty():
			continue
		if _machine_ids.find(definition.id) != -1:
			table.report_row(row, 'id: "%s" is already defined' % definition.id)
			continue

		_machine_ids.append(definition.id)
		_machines.append(definition)

	_sort_machines()


func _check_machine_values(
	table: CsvTable, row: int, definition: MachineDefinition, role: int
) -> void:
	var limit: int = MachineDefinition.MAX_FOOTPRINT_TILES
	if definition.footprint_x < 1 or definition.footprint_x > limit:
		table.report_row(
			row, "footprint_x: must be 1 to %d tiles, got %d" % [limit, definition.footprint_x]
		)
	if definition.footprint_z < 1 or definition.footprint_z > limit:
		table.report_row(
			row, "footprint_z: must be 1 to %d tiles, got %d" % [limit, definition.footprint_z]
		)
	if definition.power_draw_kw < 0:
		table.report_row(row, "power_draw_kw: must not be negative")
	if definition.health < 1:
		table.report_row(row, "health: a Machine with no health is already destroyed")

	if role == MachineDefinition.Role.MINER:
		if definition.max_depth < 1:
			table.report_row(row, "max_depth: a Miner must reach at least Depth 1")
	elif role == MachineDefinition.Role.CRAFTER:
		if definition.max_depth != 0:
			table.report_row(
				row, "max_depth: only a Miner reaches a Depth, so this must be 0"
			)


## The cross-checks between the two tables. Reported against the Machine's row,
## because the Machine is what declares the relationship.
func _check_machines_against_recipes(table: CsvTable) -> void:
	for definition: MachineDefinition in _machines:
		if definition.recipe_id.is_empty():
			continue

		definition.recipe_index = recipe_index(definition.recipe_id)
		if definition.recipe_index == -1:
			table.report_row(
				definition.source_row,
				'recipe_id: "%s" matches no Recipe' % definition.recipe_id
			)
			continue

		var used: RecipeDefinition = recipe_at(definition.recipe_index)
		if definition.is_miner() and used.input_count() > 0:
			table.report_row(
				definition.source_row,
				(
					'"%s" is a Miner, so its Recipe "%s" must have no inputs — a Miner draws'
					+ " what it extracts from the ground it stands on, not from a Belt"
				) % [definition.id, used.id]
			)
		elif not definition.is_miner() and used.input_count() == 0:
			table.report_row(
				definition.source_row,
				'"%s" is a crafter, so its Recipe "%s" must have at least one input'
				% [definition.id, used.id]
			)


# ── Reading the tuning file ───────────────────────────────────────────────────

func _read_tuning(tuning: TomlDocument) -> void:
	player_walk_speed = tuning.require_fixed(TUNING_PLAYER_WALK_SPEED)

	# Checked after every read, so this names exactly the keys nothing asked for.
	for key: String in tuning.unread_keys():
		warnings.append(
			"%s:%d: nothing in the Simulation reads \"%s\""
			% [tuning.source_path, tuning.line_of(key), key]
		)


# ── Ordering and discarding ───────────────────────────────────────────────────
# Sorted by id so the index space is a function of the content and not of the order
# someone happened to type the rows in. Ids are unique by the time these run, so the
# order is total and does not depend on the sort being stable.

func _sort_machines() -> void:
	_machines.sort_custom(
		func(a: MachineDefinition, b: MachineDefinition) -> bool: return a.id < b.id
	)
	_machine_ids.clear()
	for definition: MachineDefinition in _machines:
		_machine_ids.append(definition.id)


func _sort_recipes() -> void:
	_recipes.sort_custom(
		func(a: RecipeDefinition, b: RecipeDefinition) -> bool: return a.id < b.id
	)
	_recipe_ids.clear()
	for definition: RecipeDefinition in _recipes:
		_recipe_ids.append(definition.id)


## Throws away everything a broken load managed to read. Half a definition set is
## more dangerous than none, because it looks usable.
func _discard_content() -> void:
	_machines.clear()
	_machine_ids.clear()
	_recipes.clear()
	_recipe_ids.clear()
	_item_ids.clear()
	player_walk_speed = 0


static func _read_file(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		# `load_from_directory` checks existence first, so this is the rarer case of a
		# file that exists and cannot be read. The parser will report it as an empty
		# table, naming the path.
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
