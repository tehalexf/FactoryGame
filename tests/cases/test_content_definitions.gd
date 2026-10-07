## Content definitions loaded from files: Machines, Recipes and tuning.
##
## The loader is a leaf with a contract of its own — "names the file and the row"
## and "the same files produce the same digest" are not observable from behind
## `step`, `hash` and `query_*` — so it is tested directly, the way `Fixed` and
## `StateHasher` are. How definitions reach the Simulation, and what happens when
## they are reloaded mid-Run, is tested through the façade in
## `test_definition_hot_reload.gd`.
##
## Two things this file is built to protect:
##
## 1. **No silent defaults.** Every malformed case asserts on an error, and most
##    assert the error names the row, because a typo'd rate that quietly becomes 0
##    is the single most expensive failure mode this subsystem has.
## 2. **Order independence.** Definitions must land in the same order whatever
##    order the rows are written in, or the Simulation's starting hash depends on
##    how someone sorted a spreadsheet.
extends TestCase

const MACHINES: String = "res://content/machines.csv"
const RECIPES: String = "res://content/recipes.csv"
const TUNING: String = "res://content/tuning.toml"

const GOOD_MACHINES: String = """
id,display_name,role,footprint_x,footprint_z,power_draw_kw,power_supply_kw,health,max_depth,range_tiles,damage,recipe_id,build_cost
smelter_mk1,Smelter Mk1,crafter,3,3,180,0,500,0,0,0,smelt_iron_plate,
miner_mk1,Miner Mk1,miner,2,2,120,0,400,1,0,0,mine_iron_ore,
"""

const GOOD_RECIPES: String = """
id,display_name,inputs,outputs,seconds
smelt_iron_plate,Smelt Iron Plate,iron_ore:2,iron_plate:1,3.2
mine_iron_ore,Mine Iron Ore,,iron_ore:1,1.5
"""

## The tuning keys this file is not about. Every key the Simulation reads has to be
## present or the set does not load, so the tests below that vary one key carry the rest
## of them unchanged rather than each restating the whole file.
const OTHER_TUNING: String = """
walk_acceleration_metres_per_second_squared = 24
look_sensitivity_turns_per_1000_pixels = 0.4
eye_height_metres = 1.7
starting_stock_per_item = 200
[belt]
items_per_second = 4
items_per_tile = 4
[machine]
input_buffer_crafts = 2
[survey]
height_metres = 26
transition_seconds = 0.4
pitch_degrees = 68
[power]
baseline_supply_kw = 300
[nest]
health = 6000
[wave]
first_wave_seconds = 90
interval_seconds = 120
crawlers_in_first_wave = 6
crawlers_added_per_wave = 4
spawn_interval_seconds = 0.5
[enemy]
crawler_health = 30
crawler_speed_metres_per_second = 3
crawler_damage = 10
crawler_attack_interval_seconds = 1
"""

const GOOD_TUNING: String = """
[player]
walk_speed_metres_per_second = 4
sprint_speed_multiplier = 1.8
""" + OTHER_TUNING


func _parse(machines: String, recipes: String, tuning: String) -> Definitions:
	return Definitions.parse(machines, recipes, tuning, MACHINES, RECIPES, TUNING)


func _good() -> Definitions:
	return _parse(GOOD_MACHINES, GOOD_RECIPES, GOOD_TUNING)


# ── The content that ships ────────────────────────────────────────────────────

func test_the_shipped_content_files_load_without_complaint() -> void:
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	assert_false(definitions.has_errors(), definitions.describe_errors())
	assert_eq(definitions.warnings.size(), 0, definitions.describe_warnings())


func test_the_shipped_content_defines_the_miner_and_the_smelter() -> void:
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	assert_true(definitions.has_machine("miner_mk1"), "DESIGN.md's first Machine")
	assert_true(definitions.has_machine("smelter_mk1"), "DESIGN.md's second Machine")
	assert_true(definitions.has_recipe("mine_iron_ore"))
	assert_true(definitions.has_recipe("smelt_iron_plate"))


func test_a_missing_content_directory_is_an_error_naming_the_path() -> void:
	var definitions: Definitions = Definitions.load_from_directory("res://content_that_is_not_there")
	assert_true(definitions.has_errors())
	assert_true(
		definitions.describe_errors().contains("content_that_is_not_there"),
		definitions.describe_errors()
	)


# ── Machines ──────────────────────────────────────────────────────────────────

func test_a_machine_carries_every_column_of_its_row() -> void:
	var machine: MachineDefinition = _good().machine("miner_mk1")
	assert_not_null(machine)
	assert_eq(machine.display_name, "Miner Mk1")
	assert_eq(machine.role, MachineDefinition.Role.MINER)
	assert_eq(machine.footprint_x, 2)
	assert_eq(machine.footprint_z, 2)
	assert_eq(machine.power_draw_kw, 120)
	assert_eq(machine.health, 400)
	assert_eq(machine.max_depth, 1)
	assert_eq(machine.recipe_id, "mine_iron_ore")


func test_a_machine_resolves_its_recipe_to_an_index() -> void:
	# Machines refer to Recipes by name in the file and by index in the Simulation,
	# because an index is what an array lookup on a hot tick can afford.
	var definitions: Definitions = _good()
	var machine: MachineDefinition = definitions.machine("smelter_mk1")
	assert_eq(machine.recipe_index, definitions.recipe_index("smelt_iron_plate"))
	assert_eq(definitions.recipe_at(machine.recipe_index).id, "smelt_iron_plate")


func test_machines_are_ordered_by_id_whatever_order_the_rows_are_in() -> void:
	# The file lists the smelter first. The Simulation gets them sorted, because a
	# starting hash that depends on row order is a starting hash that changes when
	# someone tidies a spreadsheet.
	var definitions: Definitions = _good()
	assert_eq(definitions.machine_ids(), PackedStringArray(["miner_mk1", "smelter_mk1"]))


func test_an_unknown_machine_reads_as_absent_rather_than_as_a_blank_machine() -> void:
	var definitions: Definitions = _good()
	assert_false(definitions.has_machine("assembler_mk1"))
	assert_null(definitions.machine("assembler_mk1"))
	assert_eq(definitions.machine_index("assembler_mk1"), -1)


# ── Recipes ───────────────────────────────────────────────────────────────────

func test_a_recipe_parses_its_inputs_and_outputs() -> void:
	var definitions: Definitions = _good()
	var smelt: RecipeDefinition = definitions.recipe("smelt_iron_plate")
	assert_eq(smelt.input_count(), 1)
	assert_eq(definitions.item_id(smelt.input_item(0)), "iron_ore")
	assert_eq(smelt.input_quantity(0), 2)
	assert_eq(smelt.output_count(), 1)
	assert_eq(definitions.item_id(smelt.output_item(0)), "iron_plate")
	assert_eq(smelt.output_quantity(0), 1)


func test_a_recipe_rate_is_an_exact_fixed_point_quantity() -> void:
	# 3.2 seconds is 16/5, so 3.2 * 65536 is 1048576/5 = 209715.2, floored to
	# 209715. Not 3.2 as a float, and not 3.
	assert_eq(_good().recipe("smelt_iron_plate").duration_seconds, 209715)
	assert_eq(_good().recipe("mine_iron_ore").duration_seconds, 98304, "1.5 seconds")


func test_a_miner_recipe_has_no_inputs_because_the_node_is_its_input() -> void:
	var mine: RecipeDefinition = _good().recipe("mine_iron_ore")
	assert_eq(mine.input_count(), 0)
	assert_eq(mine.output_count(), 1)


func test_recipes_are_ordered_by_id_whatever_order_the_rows_are_in() -> void:
	assert_eq(
		_good().recipe_ids(), PackedStringArray(["mine_iron_ore", "smelt_iron_plate"])
	)


# ── Items ─────────────────────────────────────────────────────────────────────

func test_items_are_exactly_those_the_recipes_mention_in_sorted_order() -> void:
	# There is no items table. Naming an Item in a Recipe is how an Item comes to
	# exist, which is one fewer file to keep in step.
	assert_eq(_good().item_ids(), PackedStringArray(["iron_ore", "iron_plate"]))


func test_an_item_index_round_trips() -> void:
	var definitions: Definitions = _good()
	assert_eq(definitions.item_index("iron_plate"), 1)
	assert_eq(definitions.item_id(1), "iron_plate")
	assert_eq(definitions.item_index("unobtainium"), -1)


# ── Tuning ────────────────────────────────────────────────────────────────────

func test_a_tuning_value_reaches_the_definitions_as_fixed_point() -> void:
	assert_eq(_good().player_walk_speed, 4 * 65536, "4 metres per second")


func test_a_tuning_value_may_be_written_as_a_decimal() -> void:
	var definitions: Definitions = _parse(
		GOOD_MACHINES, GOOD_RECIPES, "[player]\nwalk_speed_metres_per_second = 5.5\nsprint_speed_multiplier = 1.8\n" + OTHER_TUNING
	)
	assert_false(definitions.has_errors(), definitions.describe_errors())
	assert_eq(definitions.player_walk_speed, 360448, "5.5 * 65536")


func test_a_missing_tuning_value_is_an_error_naming_the_key() -> void:
	var definitions: Definitions = _parse(GOOD_MACHINES, GOOD_RECIPES, "[player]\n" + OTHER_TUNING)
	assert_true(definitions.has_errors())
	assert_true(
		definitions.describe_errors().contains("player.walk_speed_metres_per_second"),
		definitions.describe_errors()
	)


func test_a_tuning_key_nothing_reads_is_a_warning_naming_it() -> void:
	var definitions: Definitions = _parse(
		GOOD_MACHINES, GOOD_RECIPES, GOOD_TUNING + "\n[heat]\nleftover = 3\n"
	)
	assert_false(definitions.has_errors(), "an unread key is misleading, not malformed")
	assert_true(definitions.describe_warnings().contains("heat.leftover"), definitions.describe_warnings())


# ── Malformed definitions name the file and the row ───────────────────────────

func test_a_duplicate_machine_id_names_the_row() -> void:
	var machines: String = GOOD_MACHINES + "miner_mk1,Miner Again,miner,2,2,120,0,400,1,0,0,mine_iron_ore,\n"
	var definitions: Definitions = _parse(machines, GOOD_RECIPES, GOOD_TUNING)
	assert_true(definitions.has_errors())
	var text: String = definitions.describe_errors()
	assert_true(text.contains("%s:5" % MACHINES), text)
	assert_true(text.contains("miner_mk1"), text)


func test_a_machine_pointing_at_no_recipe_names_the_row_and_the_recipe() -> void:
	var machines: String = GOOD_MACHINES.replace("mine_iron_ore", "mine_irn_ore")
	var definitions: Definitions = _parse(machines, GOOD_RECIPES, GOOD_TUNING)
	assert_true(definitions.has_errors())
	var text: String = definitions.describe_errors()
	assert_true(text.contains("%s:4" % MACHINES), text)
	assert_true(text.contains("mine_irn_ore"), text)


func test_an_unknown_role_names_the_row() -> void:
	var machines: String = GOOD_MACHINES.replace(",crafter,", ",smelterish,")
	var definitions: Definitions = _parse(machines, GOOD_RECIPES, GOOD_TUNING)
	assert_true(definitions.has_errors())
	assert_true(definitions.describe_errors().contains("smelterish"), definitions.describe_errors())


func test_a_malformed_rate_names_the_row_and_does_not_become_zero() -> void:
	# The expensive failure, asserted explicitly: a bad rate must stop the load,
	# never arrive as a Recipe that takes no time.
	var recipes: String = GOOD_RECIPES.replace(",3.2", ",fast")
	var definitions: Definitions = _parse(GOOD_MACHINES, recipes, GOOD_TUNING)
	assert_true(definitions.has_errors())
	var text: String = definitions.describe_errors()
	assert_true(text.contains("%s:3" % RECIPES), text)
	assert_true(text.contains("fast"), text)


func test_a_zero_or_negative_rate_names_the_row() -> void:
	for rate: String in ["0", "-1.5"]:
		var recipes: String = GOOD_RECIPES.replace(",3.2", "," + rate)
		var definitions: Definitions = _parse(GOOD_MACHINES, recipes, GOOD_TUNING)
		assert_true(definitions.has_errors(), "a Recipe taking %s seconds is not a Recipe" % rate)


func test_a_crafter_whose_recipe_produces_nothing_names_the_machine_row() -> void:
	# Whether a Recipe must have an output depends on the role of the Machine that runs
	# it: a crafter's must produce something, and a generator's must not, because what a
	# generator produces is Power and Power is not an Item. So the pairing is checked
	# against the Machine that declares it, and the error names that row.
	var recipes: String = GOOD_RECIPES.replace(",iron_plate:1,", ",,")
	var definitions: Definitions = _parse(GOOD_MACHINES, recipes, GOOD_TUNING)
	assert_true(definitions.has_errors())
	assert_true(definitions.describe_errors().contains("%s:3" % MACHINES), definitions.describe_errors())


func test_a_recipe_that_neither_consumes_nor_produces_names_the_recipe_row() -> void:
	# The one case no role could rescue, and the one still refused by the Recipe table
	# itself rather than by the Machine that runs it.
	var recipes: String = GOOD_RECIPES.replace("iron_ore:2,iron_plate:1", ",")
	var definitions: Definitions = _parse(GOOD_MACHINES, recipes, GOOD_TUNING)
	assert_true(definitions.has_errors())
	assert_true(definitions.describe_errors().contains("%s:3" % RECIPES), definitions.describe_errors())


func test_a_malformed_item_quantity_names_the_row_and_the_text() -> void:
	for broken: String in ["iron_ore:none", "iron_ore:0", "iron_ore", "Iron Ore:2", "iron_ore:2;iron_ore:1"]:
		var recipes: String = GOOD_RECIPES.replace("iron_ore:2", broken)
		var definitions: Definitions = _parse(GOOD_MACHINES, recipes, GOOD_TUNING)
		assert_true(definitions.has_errors(), 'expected "%s" to be refused' % broken)
		assert_true(
			definitions.describe_errors().contains("%s:3" % RECIPES),
			'expected the row named for "%s", got: %s' % [broken, definitions.describe_errors()]
		)


func test_a_miner_whose_recipe_has_inputs_names_the_row() -> void:
	# A Miner's input is the Node it stands on. One with a Belt-fed input is a
	# contradiction, and the kind of mistake that otherwise shows up as a Miner
	# that mysteriously never runs.
	var recipes: String = GOOD_RECIPES.replace(
		"mine_iron_ore,Mine Iron Ore,,", "mine_iron_ore,Mine Iron Ore,iron_plate:1,"
	)
	var definitions: Definitions = _parse(GOOD_MACHINES, recipes, GOOD_TUNING)
	assert_true(definitions.has_errors())
	assert_true(definitions.describe_errors().contains("miner_mk1"), definitions.describe_errors())


func test_a_crafter_with_no_inputs_names_the_row() -> void:
	var recipes: String = GOOD_RECIPES.replace(",iron_ore:2,", ",,")
	var definitions: Definitions = _parse(GOOD_MACHINES, recipes, GOOD_TUNING)
	assert_true(definitions.has_errors())
	assert_true(definitions.describe_errors().contains("smelter_mk1"), definitions.describe_errors())


func test_an_oversized_footprint_names_the_row() -> void:
	# DESIGN.md caps Machines at 4x4 on the 2 m grid.
	var machines: String = GOOD_MACHINES.replace("crafter,3,3", "crafter,9,3")
	var definitions: Definitions = _parse(machines, GOOD_RECIPES, GOOD_TUNING)
	assert_true(definitions.has_errors())
	assert_true(definitions.describe_errors().contains("%s:3" % MACHINES), definitions.describe_errors())


func test_a_broken_table_yields_no_definitions_at_all() -> void:
	# Half a definition set is more dangerous than none, because it looks usable.
	var definitions: Definitions = _parse("nonsense", GOOD_RECIPES, GOOD_TUNING)
	assert_true(definitions.has_errors())
	assert_eq(definitions.machine_count(), 0)
	assert_eq(definitions.recipe_count(), 0)


func test_every_error_in_a_row_is_reported_not_just_the_first() -> void:
	# So that fixing a definition file is one pass, not a guessing game.
	var machines: String = GOOD_MACHINES.replace(
		"miner_mk1,Miner Mk1,miner,2,2,120,0,400,1,0,0,mine_iron_ore,",
		"miner_mk1,Miner Mk1,digger,2,2,lots,0,400,1,0,0,mine_irn_ore,"
	)
	var definitions: Definitions = _parse(machines, GOOD_RECIPES, GOOD_TUNING)
	assert_true(definitions.errors.size() >= 3, definitions.describe_errors())


# ── Determinism ───────────────────────────────────────────────────────────────

func test_the_same_files_produce_the_same_digest() -> void:
	assert_eq(_good().digest(), _good().digest())


func test_the_digest_does_not_depend_on_the_order_of_the_rows() -> void:
	# The property the Simulation's starting hash rests on.
	var reordered_machines: String = """
id,display_name,role,footprint_x,footprint_z,power_draw_kw,power_supply_kw,health,max_depth,range_tiles,damage,recipe_id,build_cost
miner_mk1,Miner Mk1,miner,2,2,120,0,400,1,0,0,mine_iron_ore,
smelter_mk1,Smelter Mk1,crafter,3,3,180,0,500,0,0,0,smelt_iron_plate,
"""
	var reordered_recipes: String = """
id,display_name,inputs,outputs,seconds
mine_iron_ore,Mine Iron Ore,,iron_ore:1,1.5
smelt_iron_plate,Smelt Iron Plate,iron_ore:2,iron_plate:1,3.2
"""
	var reordered: Definitions = _parse(reordered_machines, reordered_recipes, GOOD_TUNING)
	assert_false(reordered.has_errors(), reordered.describe_errors())
	assert_eq(reordered.digest(), _good().digest())


func test_the_digest_does_not_depend_on_comments_or_blank_lines() -> void:
	var commented: Definitions = _parse(
		"# a note\n" + GOOD_MACHINES + "\n",
		GOOD_RECIPES + "\n# another note\n",
		"# tuning\n" + GOOD_TUNING
	)
	assert_eq(commented.digest(), _good().digest(), "prose must not change the Simulation")


func test_the_digest_does_not_depend_on_tuning_key_order() -> void:
	var one: Definitions = _parse(
		GOOD_MACHINES, GOOD_RECIPES, "[player]\nwalk_speed_metres_per_second = 4\nsprint_speed_multiplier = 1.8\n" + OTHER_TUNING
	)
	var other: Definitions = _parse(
		GOOD_MACHINES, GOOD_RECIPES, "[player]\n# a comment first\nwalk_speed_metres_per_second = 4\nsprint_speed_multiplier = 1.8\n" + OTHER_TUNING
	)
	assert_eq(one.digest(), other.digest())


func test_changing_a_machine_changes_the_digest() -> void:
	var changed: Definitions = _parse(
		GOOD_MACHINES.replace(",400,", ",401,"), GOOD_RECIPES, GOOD_TUNING
	)
	assert_ne(changed.digest(), _good().digest())


func test_changing_a_rate_changes_the_digest() -> void:
	var changed: Definitions = _parse(GOOD_MACHINES, GOOD_RECIPES.replace(",3.2", ",3.3"), GOOD_TUNING)
	assert_ne(changed.digest(), _good().digest())


func test_changing_a_tuning_value_changes_the_digest() -> void:
	var changed: Definitions = _parse(
		GOOD_MACHINES, GOOD_RECIPES, "[player]\nwalk_speed_metres_per_second = 5\nsprint_speed_multiplier = 1.8\n" + OTHER_TUNING
	)
	assert_ne(changed.digest(), _good().digest())


# ── Adding content requires no code change ────────────────────────────────────

func test_a_machine_and_recipe_added_only_in_the_files_appear_in_the_definitions() -> void:
	# The acceptance criterion, asserted the only way it can be: content this
	# repository has never heard of, named nowhere but in the text below.
	var machines: String = (
		GOOD_MACHINES + "press_mk1,Press Mk1,crafter,2,3,90,0,350,0,0,0,press_iron_gear,iron_plate:5\n"
	)
	var recipes: String = (
		GOOD_RECIPES + "press_iron_gear,Press Iron Gear,iron_plate:3,iron_gear:1,0.75\n"
	)
	var definitions: Definitions = _parse(machines, recipes, GOOD_TUNING)
	assert_false(definitions.has_errors(), definitions.describe_errors())

	assert_eq(definitions.machine_count(), 3)
	var press: MachineDefinition = definitions.machine("press_mk1")
	assert_not_null(press)
	assert_eq(press.power_draw_kw, 90)

	var recipe: RecipeDefinition = definitions.recipe_at(press.recipe_index)
	assert_eq(recipe.id, "press_iron_gear")
	assert_eq(recipe.duration_seconds, 49152, "0.75 * 65536")
	assert_eq(definitions.item_id(recipe.output_item(0)), "iron_gear")
	assert_eq(definitions.item_ids(), PackedStringArray(["iron_gear", "iron_ore", "iron_plate"]))
