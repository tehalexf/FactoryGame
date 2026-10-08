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
id,display_name,role,footprint_x,footprint_z,height_metres,power_draw_kw,power_supply_kw,health,max_depth,range_tiles,damage,repair,charge_capacity,recipe_id,build_cost
smelter_mk1,Smelter Mk1,crafter,3,3,1.5,180,0,500,0,0,0,0,0,smelt_iron_plate,
miner_mk1,Miner Mk1,miner,2,2,1.8,120,0,400,1,0,0,0,0,mine_iron_ore,
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
walk_deceleration_metres_per_second_squared = 9
air_acceleration_metres_per_second_squared = 6
air_deceleration_metres_per_second_squared = 1.5
jump_height_metres = 1.1
gravity_metres_per_second_squared = 22
jump_repeats_while_held = false
land_settle_seconds = 0.18
land_settle_acceleration_percent = 45
sprint_ramp_seconds = 0.45
sprint_is_toggle = true
bob_vertical_metres = 0.012
bob_lateral_metres = 0.008
bob_stride_metres = 1.6
bob_sprint_multiplier = 1.6
land_dip_metres = 0.035
land_dip_seconds = 0.22
land_dip_reference_speed_metres_per_second = 7
lean_roll_degrees_per_metre_per_second = 0.12
lean_pitch_degrees_per_metre_per_second = 0.06
field_of_view_degrees = 75
sprint_field_of_view_add_degrees = 6
holster_seconds = 0.2
look_sensitivity_turns_per_1000_pixels = 0.4
eye_height_metres = 1.7
collision_radius_metres = 0.4
step_up_height_metres = 0.75
health = 150
downed_bleed_out_seconds = 20
respawn_delay_seconds = 8
revive_seconds = 4
revive_reach_metres = 3
starting_weapon = "pneumatic_wrench"
starting_stock = "iron_ore:200;iron_plate:200"
[belt]
items_per_second = 4
items_per_tile = 4
deck_height_metres = 0.9
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
height_metres = 4.2
terrace_height_metres = 1.7
delivery_reach_metres = 5
store_capacity_per_item = 200
[silo]
load_reach_metres = 4
max_charges_per_load = 4
[wave]
telegraph_seconds = 12
spawn_interval_seconds = 0.5
call_early_bounty_per_item = 25

[heat]
per_craft = 2
per_craft_per_depth = 1
decay_per_minute = 240
wave_interval_baseline_seconds = 150
first_wave_interval_seconds = 50
wave_interval_minimum_seconds = 40
per_second_sooner = 20
[depth]
draw_percent_per_depth = 60
breach_tier = 2
breach_crafts = 40
breach_offset_tiles = 6
breach_telegraph_seconds = 45
[gear]
enemy_hit_radius_metres = 0.6
enemy_hit_height_metres = 1.6
view_kick_degrees_per_shot = 0.35
view_kick_recover_seconds = 0.5
[enemy]
crawler_health = 30
player_bite_reach_metres = 1.6
crawler_speed_metres_per_second = 3
crawler_damage = 10
crawler_attack_interval_seconds = 1
breaker_health = 240
breaker_speed_metres_per_second = 2
breaker_damage = 60
breaker_attack_interval_seconds = 1
breaker_breaks_ranks_within_tiles = 8
breaker_hit_radius_metres = 0.8
breaker_hit_height_metres = 2.2
[siege_hulk]
health = 1800
speed_metres_per_second = 1
range_metres = 60
shell_damage = 220
shell_blast_radius_metres = 6
shell_interval_seconds = 6
shell_flight_seconds = 3
stomp_damage = 45
frontal_armour_percent = 85
hit_radius_metres = 1.6
hit_height_metres = 3.2
[hive]
health = 1200
heat_shadow_per_minute = 30
hit_radius_metres = 2
hit_height_metres = 4
[wall]
health = 240
height_metres = 2.4
[wrench]
repair_points_per_second = 60
reach_metres = 4
"""

const GOOD_TUNING: String = """
[player]
walk_speed_metres_per_second = 4
sprint_speed_multiplier = 1.8
""" + OTHER_TUNING


## The shipped Wave composition, inline so the fixture is a complete definition set. A
## Wave's contents are a table (`content/waves.csv`), and a set with no rows in it is an
## error rather than a Run that is never attacked.
const WAVES: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,6,150,40
"""


func _parse(
	machines: String,
	recipes: String,
	tuning: String,
	waves: String = WAVES,
	deliveries: String = DELIVERIES,
	gear: String = GEAR
) -> Definitions:
	return Definitions.parse(
		machines,
		recipes,
		tuning,
		waves,
		deliveries,
		gear,
		STRATAGEMS,
		MACHINES,
		RECIPES,
		TUNING,
		WAVES_PATH,
		DELIVERIES_PATH,
		"gear.csv",
		"stratagems.csv"
	)


## The Gear a Run is holding, inline so the fixture is a complete definition set. One
## weapon frame and whatever component this file's Delivery tiers name, because a tier
## naming Gear that does not exist is content somebody broke. These tests are not about
## combat, so the frame is the Pneumatic Wrench and nothing is fitted to it.
const GEAR: String = """id,display_name,kind,attack,damage,range_metres,spread_degrees,seconds_per_shot,ammunition_item,ammunition_per_shot,damage_percent,range_percent,spread_percent,interval_percent,ammunition_percent,damage_taken_percent
pneumatic_wrench,Pneumatic Wrench,weapon,melee,55,4,0,0.6,,0,0,0,0,0,0,0
placeholder_gear,Placeholder Barrel,barrel,,0,0,0,0,,0,10,0,0,0,0,0
gear_a,Component A,barrel,,0,0,0,0,,0,10,0,0,0,0,0
gear_b,Component B,sight,,0,0,0,0,,0,0,0,-10,0,0,0
"""


## A Stratagem table that is not what this file is about. One row, so the table is not empty —
## `Definitions` refuses an empty one, because a Silo with nothing to load is a Machine a
## player can build, feed and never use. `test_silo.gd` is where the shipped table is
## asserted, exactly as `test_delivery.gd` is where the shipped Delivery chain is.
const STRATAGEMS: String = """id,display_name,effect,paint_seconds,radius_tiles,damage_per_charge,goods_per_charge,sentry_machine,sentry_seconds
artillery_barrage,Artillery Barrage,barrage,5,6,150,,,0
"""


const DELIVERIES_PATH: String = "deliveries.csv"


const WAVES_PATH: String = "waves.csv"


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
	# `[heat]` used to be the section nothing read; it is a real one now, so the key nobody
	# asked for has to come from a section nobody has written yet.
	var definitions: Definitions = _parse(
		GOOD_MACHINES, GOOD_RECIPES, GOOD_TUNING + "\n[stratagem]\nleftover = 3\n"
	)
	assert_false(definitions.has_errors(), "an unread key is misleading, not malformed")
	assert_true(
		definitions.describe_warnings().contains("stratagem.leftover"),
		definitions.describe_warnings()
	)


# ── The Wave table ────────────────────────────────────────────────────────────
# Composition is data (`content/waves.csv`), so adding an Enemy to the Waves is a row. The
# same loudness rules apply: no defaults, and every mistake names the row.

func test_the_shipped_wave_table_loads_and_opens_at_the_first_wave() -> void:
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	assert_false(definitions.has_errors(), definitions.describe_errors())
	assert_true(definitions.wave_entry_count() >= 1, "a Run has to be attacked by something")
	var first: WaveEntry = definitions.wave_entry_at(0)
	assert_eq(first.enemy_kind, EnemyKind.CRAWLER, "Milestone 1 ships Chaff and nothing else")
	assert_eq(first.min_heat, 0, "so it contributes from the first Wave of a cold Run")


func test_a_wave_tier_grows_with_heat_up_to_the_ceiling_the_row_names() -> void:
	# A worked example off the shipped row: opens at 6, one more every 1200 Heat, capped at 40.
	#
	# 1200 rather than the 150 this was first written against because #26 measured what one
	# Ammo Press can actually feed — about twelve Crawlers a Wave once the interval floors —
	# and at 150 a Factory earned itself two extra Crawlers on its very first Wave. See
	# `content/waves.csv`, which carries the whole derivation.
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	var entry: WaveEntry = definitions.wave_entry_at(0)
	assert_eq(entry.count_at_heat(0), 6, "a cold Factory")
	assert_eq(entry.count_at_heat(1199), 6, "one Heat short of the next Enemy")
	assert_eq(entry.count_at_heat(1200), 7)
	assert_eq(entry.count_at_heat(4800), 10)
	assert_eq(entry.count_at_heat(1000000), 40, "max_per_breach, and not one more")


func test_a_wave_tier_below_its_threshold_sends_nothing_rather_than_a_minimum() -> void:
	var entry: WaveEntry = WaveEntry.new()
	entry.min_heat = 500
	entry.count_per_breach = 4
	entry.max_per_breach = 4
	assert_eq(entry.count_at_heat(499), 0, "a tier that is not unlocked contributes nothing")
	assert_eq(entry.count_at_heat(500), 4)


func test_an_unknown_enemy_kind_names_the_row_and_the_kinds_that_exist() -> void:
	var definitions: Definitions = _parse(
		GOOD_MACHINES,
		GOOD_RECIPES,
		GOOD_TUNING,
		"id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach\n"
		+ "mystery,leviathan,0,1,0,1\n"
	)
	assert_true(definitions.has_errors(), "a kind nothing implements cannot be drawn")
	var text: String = definitions.describe_errors()
	assert_true(text.contains("%s:2" % WAVES_PATH), text)
	assert_true(text.contains("leviathan"), text)
	assert_true(text.contains("crawler"), "the message says what could be written: %s" % text)


func test_a_wave_table_with_no_rows_is_an_error_not_a_quiet_run() -> void:
	# The symptom of an empty table is a Run that is never attacked, which is the hardest
	# kind of bug to notice — so it is refused outright.
	var definitions: Definitions = _parse(
		GOOD_MACHINES,
		GOOD_RECIPES,
		GOOD_TUNING,
		"id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach\n"
	)
	assert_true(definitions.has_errors())
	assert_true(definitions.describe_errors().contains("no rows"), definitions.describe_errors())


func test_a_duplicate_wave_tier_id_names_the_row() -> void:
	var definitions: Definitions = _parse(
		GOOD_MACHINES,
		GOOD_RECIPES,
		GOOD_TUNING,
		"id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach\n"
		+ "chaff,crawler,0,1,0,1\n"
		+ "chaff,crawler,100,2,0,2\n"
	)
	assert_true(definitions.has_errors())
	var text: String = definitions.describe_errors()
	assert_true(text.contains("%s:3" % WAVES_PATH), text)
	assert_true(text.contains("chaff"), text)


func test_a_ceiling_below_the_opening_count_names_the_row() -> void:
	var definitions: Definitions = _parse(
		GOOD_MACHINES,
		GOOD_RECIPES,
		GOOD_TUNING,
		"id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach\n"
		+ "chaff,crawler,0,6,0,2\n"
	)
	assert_true(definitions.has_errors(), "the ceiling contradicts the opening count")
	assert_true(
		definitions.describe_errors().contains("max_per_breach"), definitions.describe_errors()
	)


func test_a_broken_wave_table_leaves_the_set_carrying_nothing_at_all() -> void:
	# The rule the whole loader obeys: half a definition set is more dangerous than none.
	var definitions: Definitions = _parse(
		GOOD_MACHINES,
		GOOD_RECIPES,
		GOOD_TUNING,
		"id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach\n"
		+ "chaff,nonsense,0,1,0,1\n"
	)
	assert_true(definitions.has_errors())
	assert_eq(definitions.wave_entry_count(), 0, "no Wave tiers")
	assert_eq(definitions.machine_count(), 0, "and no Machines either")


func test_a_missing_wave_file_names_the_path() -> void:
	var definitions: Definitions = Definitions.load_from_directory("res://content_that_is_not_there")
	assert_true(definitions.has_errors())
	assert_true(
		definitions.describe_errors().contains(Definitions.WAVES_FILE),
		definitions.describe_errors()
	)


func test_an_unknown_wave_tier_reads_as_nothing_rather_than_crashing() -> void:
	var definitions: Definitions = _good()
	assert_null(definitions.wave_entry_at(99), "never a plausible-looking default")
	assert_null(definitions.wave_entry_at(-1))


# ── The Heat and schedule tuning ──────────────────────────────────────────────

func test_a_telegraph_of_no_length_is_refused() -> void:
	var definitions: Definitions = _parse(
		GOOD_MACHINES, GOOD_RECIPES, GOOD_TUNING.replace("telegraph_seconds = 12", "telegraph_seconds = 0")
	)
	assert_true(definitions.has_errors(), "a Wave with no warning is the ambush to prevent")
	assert_true(
		definitions.describe_errors().contains("wave.telegraph_seconds"),
		definitions.describe_errors()
	)


func test_a_minimum_interval_above_the_baseline_is_refused() -> void:
	# Heat only ever shortens the gap, so a minimum above the baseline would mean a hot
	# Factory was hunted *later* — a schedule that contradicts itself.
	var definitions: Definitions = _parse(
		GOOD_MACHINES,
		GOOD_RECIPES,
		GOOD_TUNING.replace("wave_interval_minimum_seconds = 40", "wave_interval_minimum_seconds = 300")
	)
	assert_true(definitions.has_errors())
	assert_true(
		definitions.describe_errors().contains("heat.wave_interval_minimum_seconds"),
		definitions.describe_errors()
	)


func test_a_gap_shorter_than_the_telegraph_is_refused() -> void:
	var definitions: Definitions = _parse(
		GOOD_MACHINES,
		GOOD_RECIPES,
		GOOD_TUNING.replace("wave_interval_minimum_seconds = 40", "wave_interval_minimum_seconds = 5")
	)
	assert_true(definitions.has_errors(), "there would be no quiet tick to read the warning in")
	assert_true(
		definitions.describe_errors().contains("wave.telegraph_seconds"),
		"and the message names the key it is in conflict with: %s" % definitions.describe_errors()
	)


func test_heat_that_buys_no_time_is_refused() -> void:
	var definitions: Definitions = _parse(
		GOOD_MACHINES, GOOD_RECIPES, GOOD_TUNING.replace("per_second_sooner = 20", "per_second_sooner = 0")
	)
	assert_true(definitions.has_errors(), "Heat that does not drive the schedule is not Heat")
	assert_true(
		definitions.describe_errors().contains("heat.per_second_sooner"),
		definitions.describe_errors()
	)


func test_a_nest_that_hides_nothing_is_a_legal_balance_decision() -> void:
	# The counterpart: `decay_per_minute = 0` is a Map where Heat only ever climbs, which is
	# a balance choice rather than a broken file, and the loader must not second-guess it.
	var definitions: Definitions = _parse(
		GOOD_MACHINES, GOOD_RECIPES, GOOD_TUNING.replace("decay_per_minute = 240", "decay_per_minute = 0")
	)
	assert_false(definitions.has_errors(), definitions.describe_errors())
	assert_eq(definitions.heat_decay_per_minute, 0)


# ── Malformed definitions name the file and the row ───────────────────────────

func test_a_duplicate_machine_id_names_the_row() -> void:
	var machines: String = GOOD_MACHINES + "miner_mk1,Miner Again,miner,2,2,1.8,120,0,400,1,0,0,0,0,mine_iron_ore,\n"
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
		"miner_mk1,Miner Mk1,miner,2,2,1.8,120,0,400,1,0,0,0,0,mine_iron_ore,",
		"miner_mk1,Miner Mk1,digger,2,2,1.8,lots,0,400,1,0,0,0,0,mine_irn_ore,"
	)
	var definitions: Definitions = _parse(machines, GOOD_RECIPES, GOOD_TUNING)
	assert_true(definitions.errors.size() >= 3, definitions.describe_errors())


# ── Determinism ───────────────────────────────────────────────────────────────

func test_the_same_files_produce_the_same_digest() -> void:
	assert_eq(_good().digest(), _good().digest())


func test_the_digest_does_not_depend_on_the_order_of_the_rows() -> void:
	# The property the Simulation's starting hash rests on.
	var reordered_machines: String = """
id,display_name,role,footprint_x,footprint_z,height_metres,power_draw_kw,power_supply_kw,health,max_depth,range_tiles,damage,repair,charge_capacity,recipe_id,build_cost
miner_mk1,Miner Mk1,miner,2,2,1.8,120,0,400,1,0,0,0,0,mine_iron_ore,
smelter_mk1,Smelter Mk1,crafter,3,3,1.5,180,0,500,0,0,0,0,0,smelt_iron_plate,
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
		GOOD_MACHINES + "press_mk1,Press Mk1,crafter,2,3,2,90,0,350,0,0,0,0,0,press_iron_gear,iron_plate:5\n"
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


# ── The Delivery table ────────────────────────────────────────────────────────
# Progression is physical: goods carried to the Nest unlock the next tier
# (GLOSSARY.md). The tiers are a table, so adding one is a row.

const DELIVERY_HEADER: String = (
	"id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems\n"
)


func _with_deliveries(rows: String) -> Definitions:
	return _parse(GOOD_MACHINES, GOOD_RECIPES, GOOD_TUNING, WAVES, DELIVERY_HEADER + rows)


func test_a_delivery_table_with_no_rows_is_an_error_not_a_run_without_progression() -> void:
	var definitions: Definitions = _with_deliveries("")
	assert_true(definitions.has_errors())
	assert_true(definitions.describe_errors().contains("no rows"), definitions.describe_errors())


func test_a_tier_unlocking_a_machine_that_does_not_exist_names_the_row() -> void:
	var definitions: Definitions = _with_deliveries(
		"t01_a,A,1,iron_plate:1,nonesuch_mk1,,\n"
	)
	assert_true(definitions.has_errors())
	assert_true(
		definitions.describe_errors().contains("deliveries.csv:2"), definitions.describe_errors()
	)
	assert_true(
		definitions.describe_errors().contains("nonesuch_mk1"), definitions.describe_errors()
	)


func test_a_tier_wanting_an_item_no_recipe_mentions_names_the_row() -> void:
	var definitions: Definitions = _with_deliveries("t01_a,A,1,unobtainium:1,,gear_a,\n")
	assert_true(definitions.has_errors())
	assert_true(
		definitions.describe_errors().contains("unobtainium"), definitions.describe_errors()
	)


func test_a_tier_that_unlocks_nothing_names_the_row() -> void:
	var definitions: Definitions = _with_deliveries("t01_a,A,1,iron_plate:1,,,\n")
	assert_true(definitions.has_errors())
	assert_true(
		definitions.describe_errors().contains("unlocks nothing"), definitions.describe_errors()
	)


func test_a_tier_that_costs_nothing_names_the_row() -> void:
	var definitions: Definitions = _with_deliveries("t01_a,A,1,,,gear_a,\n")
	assert_true(definitions.has_errors())
	assert_true(definitions.describe_errors().contains("goods:"), definitions.describe_errors())


func test_a_depth_that_goes_backwards_down_the_chain_names_the_row() -> void:
	# The chain is walked in id order and nothing is skipped, so a tier shallower than one
	# before it could never be the thing holding it up.
	var definitions: Definitions = _with_deliveries(
		"t01_a,A,3,iron_plate:1,,gear_a,\nt02_b,B,1,iron_plate:1,,gear_b,\n"
	)
	assert_true(definitions.has_errors())
	assert_true(definitions.describe_errors().contains("shallower"), definitions.describe_errors())


func test_a_machine_unlocked_by_two_tiers_names_the_row() -> void:
	var definitions: Definitions = _with_deliveries(
		"t01_a,A,1,iron_plate:1,miner_mk1,,\nt02_b,B,1,iron_plate:1,miner_mk1,,\n"
	)
	assert_true(definitions.has_errors())
	assert_true(
		definitions.describe_errors().contains("already unlocked"), definitions.describe_errors()
	)


func test_delivery_tiers_are_ordered_by_id_whatever_order_the_rows_are_in() -> void:
	var forwards: Definitions = _with_deliveries(
		"t01_a,A,1,iron_plate:1,,gear_a,\nt02_b,B,1,iron_plate:1,,gear_b,\n"
	)
	var backwards: Definitions = _with_deliveries(
		"t02_b,B,1,iron_plate:1,,gear_b,\nt01_a,A,1,iron_plate:1,,gear_a,\n"
	)
	assert_false(forwards.has_errors(), forwards.describe_errors())
	assert_false(backwards.has_errors(), backwards.describe_errors())
	assert_eq(backwards.delivery_at(0).id, "t01_a")
	assert_eq(
		forwards.digest(), backwards.digest(), "and the order of the rows cannot reach the hash"
	)


func test_an_opening_stock_naming_an_unknown_item_names_the_key() -> void:
	var definitions: Definitions = _parse(
		GOOD_MACHINES,
		GOOD_RECIPES,
		GOOD_TUNING.replace(
			'starting_stock = "iron_ore:200;iron_plate:200"',
			'starting_stock = "unobtainium:1"'
		)
	)
	assert_true(definitions.has_errors())
	assert_true(
		definitions.describe_errors().contains("player.starting_stock"),
		definitions.describe_errors()
	)


func test_an_empty_opening_stock_is_a_run_that_opens_empty_handed() -> void:
	var definitions: Definitions = _parse(
		GOOD_MACHINES,
		GOOD_RECIPES,
		GOOD_TUNING.replace(
			'starting_stock = "iron_ore:200;iron_plate:200"', 'starting_stock = ""'
		)
	)
	assert_false(definitions.has_errors(), definitions.describe_errors())
	assert_eq(definitions.player_starting_stock_items.size(), 0)


func test_the_opening_stock_is_sorted_whatever_order_it_is_written_in() -> void:
	var definitions: Definitions = _parse(
		GOOD_MACHINES,
		GOOD_RECIPES,
		GOOD_TUNING.replace(
			'starting_stock = "iron_ore:200;iron_plate:200"',
			'starting_stock = "iron_plate:3;iron_ore:7"'
		)
	)
	assert_false(definitions.has_errors(), definitions.describe_errors())
	assert_eq(
		definitions.player_starting_stock_items, PackedStringArray(["iron_ore", "iron_plate"])
	)
	assert_eq(definitions.player_starting_stock_counts, PackedInt64Array([7, 3]))


func test_the_shipped_content_defines_the_delivery_tiers_in_id_order() -> void:
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	assert_false(definitions.has_errors(), definitions.describe_errors())
	assert_true(definitions.delivery_count() >= 2, "the shipped file defines tiers")
	var ids: PackedStringArray = PackedStringArray()
	for index: int in range(definitions.delivery_count()):
		ids.append(definitions.delivery_at(index).id)
	var sorted: PackedStringArray = ids.duplicate()
	sorted.sort()
	assert_eq(String(", ").join(ids), String(", ").join(sorted), "sorted by id")


## The Delivery tiers, inline so the fixture is a complete definition set. Progression is
## physical (`content/deliveries.csv`), and a table with no rows in it is an error rather
## than a Run with no progression. This one unlocks a Gear component and names no Machine,
## so nothing this file builds is locked behind it.
const DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_opening,Opening Licence,1,iron_plate:1,,placeholder_gear,
"""
# ── A Turret's output is damage or repair, never both and never neither ───────
# The rule that makes a Repair Pylon a row rather than a fifth Role (GLOSSARY.md calls it a
# Turret-class Machine). Checked here rather than through the façade because an error message
# naming a file and a row is not something `step`, `hash` or a query can report.

const PYLON_ROW: String = (
	"repair_pylon_mk1,Repair Pylon Mk1,turret,2,2,2.4,60,0,300,0,6,0,40,0,mend_machinery,\n"
)

const MEND_ROW: String = "mend_machinery,Mend Machinery,iron_plate:1,,1\n"


func test_a_repair_pylon_is_a_turret_row_with_repair_instead_of_damage() -> void:
	var definitions: Definitions = _parse(
		GOOD_MACHINES + PYLON_ROW, GOOD_RECIPES + MEND_ROW, GOOD_TUNING
	)
	assert_false(definitions.has_errors(), definitions.describe_errors())
	var pylon: MachineDefinition = definitions.machine("repair_pylon_mk1")
	if not assert_not_null(pylon, "three rows and nothing else"):
		return
	assert_true(pylon.is_turret(), "it is a Turret in every respect but its output")
	assert_true(pylon.heals())
	assert_eq(pylon.repair, 40)
	assert_eq(pylon.damage, 0)
	assert_true(
		pylon.produces_no_items(),
		"repair is not an Item either, so its Recipe has no outputs — the same predicate a"
		+ " generator and an MG Turret answer to"
	)


func test_a_turret_that_neither_damages_nor_repairs_is_refused() -> void:
	var definitions: Definitions = _parse(
		GOOD_MACHINES + PYLON_ROW.replace(",6,0,40,", ",6,0,0,"),
		GOOD_RECIPES + MEND_ROW,
		GOOD_TUNING
	)
	assert_true(definitions.has_errors(), "a Turret with no output at all does nothing")
	assert_true(
		definitions.describe_errors().contains("damage/repair"),
		definitions.describe_errors()
	)


func test_a_turret_that_both_damages_and_repairs_is_refused() -> void:
	var definitions: Definitions = _parse(
		GOOD_MACHINES + PYLON_ROW.replace(",6,0,40,", ",6,15,40,"),
		GOOD_RECIPES + MEND_ROW,
		GOOD_TUNING
	)
	assert_true(definitions.has_errors(), "one shot cannot both hurt and mend")
	assert_true(
		definitions.describe_errors().contains("never both"), definitions.describe_errors()
	)


func test_only_a_turret_may_carry_a_repair_value() -> void:
	var definitions: Definitions = _parse(
		GOOD_MACHINES.replace(
			"smelter_mk1,Smelter Mk1,crafter,3,3,1.5,180,0,500,0,0,0,0,0,smelt",
			"smelter_mk1,Smelter Mk1,crafter,3,3,1.5,180,0,500,0,0,0,40,0,smelt"
		),
		GOOD_RECIPES,
		GOOD_TUNING
	)
	assert_true(definitions.has_errors(), "a number sitting in a column nothing reads lies")
	assert_true(
		definitions.describe_errors().contains("only a Repair Pylon repairs"),
		definitions.describe_errors()
	)


func test_the_wave_table_knows_the_breaker_by_name() -> void:
	# Adding an Enemy to the Waves is a row, and `sim/enemy_kind.gd` is the one place a name
	# and its integer meet.
	assert_eq(EnemyKind.index_of("breaker"), EnemyKind.BREAKER)
	assert_eq(EnemyKind.name_of(EnemyKind.BREAKER), "breaker")
	var definitions: Definitions = _parse(
		GOOD_MACHINES,
		GOOD_RECIPES,
		GOOD_TUNING,
		"id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach\n"
		+ "shock_breakers,breaker,0,2,0,2\n"
	)
	assert_false(definitions.has_errors(), definitions.describe_errors())
	assert_eq(definitions.wave_entry_at(0).enemy_kind, EnemyKind.BREAKER)


# ── The Gear table ────────────────────────────────────────────────────────────
# Gear is modular: one weapon frame accepting components made on different production
# lines, and power from combination rather than from tiers (GLOSSARY.md). Half of "there
# is no Rifle Mk2" is enforced by the schema — a weapon states what it is and carries no
# modifiers, a component carries nothing but modifiers — and this is where that is
# asserted.

const GEAR_HEADER: String = (
	"id,display_name,kind,attack,damage,range_metres,spread_degrees,seconds_per_shot,"
	+ "ammunition_item,ammunition_per_shot,damage_percent,range_percent,spread_percent,"
	+ "interval_percent,ammunition_percent,damage_taken_percent\n"
)

## A well-formed weapon row, so a test that varies one column carries the rest unchanged.
const GOOD_WEAPON: String = (
	"pneumatic_wrench,Pneumatic Wrench,weapon,melee,55,4,0,0.6,,0,0,0,0,0,0,0\n"
)


## A Delivery tier that unlocks a Machine rather than a piece of Gear, so a test varying
## the Gear table is not also obliged to keep a component the tier names alive.
const GEAR_TEST_DELIVERIES: String = (
	"id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems\n"
	+ "t01_a,A,1,iron_plate:1,smelter_mk1,,\n"
)


func _with_gear(rows: String) -> Definitions:
	return _parse(
		GOOD_MACHINES,
		GOOD_RECIPES,
		GOOD_TUNING,
		WAVES,
		GEAR_TEST_DELIVERIES,
		GEAR_HEADER + rows
	)


func test_a_gear_table_with_no_rows_is_an_error_not_a_run_with_nothing_to_fight_with() -> void:
	var definitions: Definitions = _with_gear("")
	assert_true(definitions.has_errors())
	assert_true(definitions.describe_errors().contains("no rows"), definitions.describe_errors())


func test_a_gear_table_with_no_weapon_frame_is_an_error() -> void:
	# Components fit a frame. A table of nothing but components is a table with nothing to
	# hold, and `player.starting_weapon` could never name anything in it.
	var definitions: Definitions = _with_gear(
		"heavy_barrel,Heavy Barrel,barrel,,0,0,0,0,,0,40,0,0,0,0,0\n"
	)
	assert_true(definitions.has_errors())
	assert_true(
		definitions.describe_errors().contains("no frame to hold"), definitions.describe_errors()
	)


func test_a_weapon_carrying_a_modifier_is_refused_because_that_would_be_a_tier() -> void:
	# The schema half of "power comes from combination, not from tiers". A frame that gave
	# itself +40% damage would be a Rifle Mk2 written in the modifier columns.
	var definitions: Definitions = _with_gear(
		GOOD_WEAPON
		+ "bolt_rifle,Bolt Rifle,weapon,ranged,30,60,0.4,0.8,ammunition,1,40,0,0,0,0,0\n"
	)
	assert_true(definitions.has_errors())
	assert_true(
		definitions.describe_errors().contains("a tier in disguise"),
		definitions.describe_errors()
	)


func test_a_component_that_changes_nothing_is_refused_by_name() -> void:
	# A Delivery tier a player paid for and cannot feel is worse than no tier at all.
	var definitions: Definitions = _with_gear(
		GOOD_WEAPON + "dead_weight,Dead Weight,barrel,,0,0,0,0,,0,0,0,0,0,0,0\n"
	)
	assert_true(definitions.has_errors())
	assert_true(
		definitions.describe_errors().contains("changes nothing measurable"),
		definitions.describe_errors()
	)


func test_a_component_carrying_a_frame_column_is_refused() -> void:
	var definitions: Definitions = _with_gear(
		GOOD_WEAPON + "long_barrel,Long Barrel,barrel,,0,30,0,0,,0,40,0,0,0,0,0\n"
	)
	assert_true(definitions.has_errors())
	assert_true(
		definitions.describe_errors().contains("belong to the frame"),
		definitions.describe_errors()
	)


func test_a_weapon_with_no_attack_and_a_component_with_one_are_both_refused() -> void:
	# Two different mistakes with two different sentences, because a loader that said only
	# "bad attack" would leave the author guessing which.
	var missing: Definitions = _with_gear(
		"bolt_rifle,Bolt Rifle,weapon,,30,60,0,0.8,ammunition,1,0,0,0,0,0,0\n"
	)
	assert_true(missing.has_errors())
	assert_true(
		missing.describe_errors().contains("has to reach somehow"), missing.describe_errors()
	)

	var spurious: Definitions = _with_gear(
		GOOD_WEAPON + "heavy_barrel,Heavy Barrel,barrel,melee,0,0,0,0,,0,40,0,0,0,0,0\n"
	)
	assert_true(spurious.has_errors())
	assert_true(
		spurious.describe_errors().contains("leave it empty"), spurious.describe_errors()
	)


func test_a_ranged_weapon_firing_an_item_no_recipe_mentions_is_refused() -> void:
	# The Items that exist are exactly the ones some Recipe mentions, so a weapon firing
	# `plasma` is a weapon nothing in the Factory could ever load.
	var definitions: Definitions = _with_gear(
		GOOD_WEAPON + "arc_gun,Arc Gun,weapon,ranged,30,60,0,0.8,plasma,1,0,0,0,0,0,0\n"
	)
	assert_true(definitions.has_errors())
	assert_true(
		definitions.describe_errors().contains("not an Item any Recipe mentions"),
		definitions.describe_errors()
	)


func test_a_melee_weapon_naming_ammunition_is_refused() -> void:
	var definitions: Definitions = _with_gear(
		"club,Club,weapon,melee,55,4,0,0.6,iron_plate,1,0,0,0,0,0,0\n"
	)
	assert_true(definitions.has_errors())
	assert_true(
		definitions.describe_errors().contains("spends a player's presence"),
		definitions.describe_errors()
	)


func test_the_slots_are_interned_from_the_kind_column_and_sorted() -> void:
	# There is no slot table, for the reason there is no Item table: writing `barrel` in a
	# row is what makes a barrel slot exist, so a fourth slot is a row. Sorted, so the index
	# a `FIT_COMPONENT` intent carries is a property of the content and not of row order.
	var definitions: Definitions = _with_gear(
		GOOD_WEAPON
		+ "a_sight,A Sight,sight,,0,0,0,0,,0,0,0,-10,0,0,0\n"
		+ "a_barrel,A Barrel,barrel,,0,0,0,0,,0,10,0,0,0,0,0\n"
		+ "b_sight,B Sight,sight,,0,0,0,0,,0,0,0,-20,0,0,0\n"
	)
	assert_false(definitions.has_errors(), definitions.describe_errors())
	assert_eq(
		definitions.gear_slot_ids(),
		PackedStringArray(["barrel", "sight"]),
		"two slots from three components, in sorted order"
	)
	assert_eq(definitions.weapon_count(), 1)


func test_a_tier_unlocking_gear_that_does_not_exist_names_the_row() -> void:
	# One authority, exactly as `unlocks_machines` has one: the Gear a Run opens with is
	# exactly the Gear no tier names, so there is no `locked` column in `gear.csv` either.
	var definitions: Definitions = _with_deliveries(
		"t01_a,A,1,iron_plate:1,,nonesuch_barrel,\n"
	)
	assert_true(definitions.has_errors())
	assert_true(
		definitions.describe_errors().contains("not a piece of Gear in gear.csv"),
		definitions.describe_errors()
	)


func test_a_starting_weapon_that_is_a_component_or_missing_is_refused_by_name() -> void:
	# The likelier of the two mistakes is naming a component, and it is the more confusing
	# to debug, because the row exists.
	var missing: Definitions = _parse(
		GOOD_MACHINES,
		GOOD_RECIPES,
		GOOD_TUNING.replace('starting_weapon = "pneumatic_wrench"', 'starting_weapon = "nonesuch"')
	)
	assert_true(missing.has_errors())
	assert_true(
		missing.describe_errors().contains("is not a row in gear.csv"), missing.describe_errors()
	)

	var component: Definitions = _parse(
		GOOD_MACHINES,
		GOOD_RECIPES,
		GOOD_TUNING.replace(
			'starting_weapon = "pneumatic_wrench"', 'starting_weapon = "placeholder_gear"'
		)
	)
	assert_true(component.has_errors())
	assert_true(
		component.describe_errors().contains("rather than a weapon frame"),
		component.describe_errors()
	)


func test_a_starting_weapon_a_delivery_locks_is_refused() -> void:
	# A Run cannot open holding something it has not earned, and the rule is the one
	# sentence it has always been: the Gear a Run opens with is exactly the Gear no tier
	# names.
	var definitions: Definitions = _parse(
		GOOD_MACHINES,
		GOOD_RECIPES,
		GOOD_TUNING,
		WAVES,
		DELIVERY_HEADER + "t01_a,A,1,iron_plate:1,,pneumatic_wrench,\n"
	)
	assert_true(definitions.has_errors())
	assert_true(
		definitions.describe_errors().contains("unlocked by a Delivery tier"),
		definitions.describe_errors()
	)

# ── The Stratagem table ───────────────────────────────────────────────────────
# A Stratagem is a player-called intervention drawn from a stockpile of Charges
# (GLOSSARY.md), and adding one is a row. What is checked here is the *schema*, because the
# schema is what enforces the design: each effect reads exactly the columns that belong to it,
# so there is nowhere to write a Barrage that also drops a Turret even if somebody wanted to.
# Loader errors name a file, a row and a column, which is not something `step`, `hash` or a
# query can report.

const SILO_MACHINE_ROW: String = (
	"silo_mk1,Silo Mk1,silo,4,4,2.2,400,0,900,0,0,0,0,8,assemble_charge,\n"
)

const ASSEMBLE_ROW: String = "assemble_charge,Assemble Charge,iron_plate:1,,20\n"

const STRATAGEM_HEADER: String = (
	"id,display_name,effect,paint_seconds,radius_tiles,damage_per_charge,goods_per_charge"
	+ ",sentry_machine,sentry_seconds\n"
)


## Parses a Stratagem table against machines and recipes that declare a Silo and a Turret, so
## a `sentry` row has something real to name.
func _parse_stratagems(table: String) -> Definitions:
	return Definitions.parse(
		GOOD_MACHINES + SILO_MACHINE_ROW + PYLON_ROW.replace(",0,6,0,40,0,", ",0,6,15,0,0,"),
		GOOD_RECIPES + ASSEMBLE_ROW + MEND_ROW,
		GOOD_TUNING,
		WAVES,
		DELIVERY_HEADER + "t01_opening,Opening Licence,1,iron_plate:1,,gear_a,\n",
		GEAR,
		STRATAGEM_HEADER + table,
		MACHINES,
		RECIPES,
		TUNING,
		WAVES_PATH,
		DELIVERIES_PATH,
		"gear.csv",
		"stratagems.csv"
	)


func test_the_shipped_stratagem_table_loads_and_declares_three() -> void:
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	assert_false(definitions.has_errors(), definitions.describe_errors())
	assert_eq(definitions.stratagem_count(), 3, "DESIGN.md caps Milestone 1 at three")
	assert_eq(
		definitions.stratagem_ids(),
		PackedStringArray(["artillery_barrage", "sentry_drop", "supply_drop"]),
		"sorted by id, so the index a load intent carries is a property of the content"
	)


func test_a_stratagem_added_only_in_the_file_appears_in_the_definitions() -> void:
	# The acceptance criterion, asserted the only way it can be: a Stratagem this repository
	# has never heard of, named nowhere but in the text below.
	var definitions: Definitions = _parse_stratagems(
		"smoke_screen,Smoke Screen,barrage,2.5,9,4,,,0\n"
	)
	assert_false(definitions.has_errors(), definitions.describe_errors())
	var smoke: StratagemDefinition = definitions.stratagem("smoke_screen")
	if not assert_not_null(smoke, "one row and no code"):
		return
	assert_true(smoke.is_barrage())
	assert_eq(smoke.radius_tiles, 9, "it reaches further than anything shipped")
	assert_eq(smoke.damage_per_charge, 4)
	assert_eq(smoke.paint_seconds, 163840, "2.5 * 65536")


func test_a_stratagem_with_no_channel_at_all_is_refused() -> void:
	var definitions: Definitions = _parse_stratagems(
		"instant_barrage,Instant Barrage,barrage,0,6,150,,,0\n"
	)
	assert_true(definitions.has_errors(), "a Painting with no channel is not a Painting")
	assert_true(
		definitions.describe_errors().contains("paint_seconds"),
		definitions.describe_errors()
	)


func test_a_barrage_that_delivers_goods_is_refused_by_column() -> void:
	# The schema is what keeps the three effects distinct. A Barrage shells the ground; a row
	# that also handed out rounds would be two Stratagems pretending to be one.
	var definitions: Definitions = _parse_stratagems(
		"loot_barrage,Loot Barrage,barrage,5,6,150,ammunition:10,,0\n"
	)
	assert_true(definitions.has_errors(), "a number in a column nothing reads lies")
	assert_true(
		definitions.describe_errors().contains("goods_per_charge"),
		definitions.describe_errors()
	)


func test_a_supply_drop_with_a_radius_or_a_damage_value_is_refused_by_column() -> void:
	var with_radius: Definitions = _parse_stratagems(
		"wide_supply,Wide Supply,supply,3,4,0,ammunition:10,,0\n"
	)
	assert_true(with_radius.has_errors())
	assert_true(
		with_radius.describe_errors().contains("radius_tiles"), with_radius.describe_errors()
	)

	var with_damage: Definitions = _parse_stratagems(
		"hot_supply,Hot Supply,supply,3,0,9,ammunition:10,,0\n"
	)
	assert_true(with_damage.has_errors())
	assert_true(
		with_damage.describe_errors().contains("damage_per_charge"),
		with_damage.describe_errors()
	)


func test_a_supply_drop_that_delivers_nothing_is_refused() -> void:
	var definitions: Definitions = _parse_stratagems(
		"empty_supply,Empty Supply,supply,3,0,0,,,0\n"
	)
	assert_true(definitions.has_errors(), "a drop a player paid for and cannot feel")
	assert_true(
		definitions.describe_errors().contains("goods_per_charge"),
		definitions.describe_errors()
	)


func test_a_sentry_drop_must_name_a_turret_that_exists() -> void:
	var missing: Definitions = _parse_stratagems(
		"ghost_sentry,Ghost Sentry,sentry,3,0,0,ammunition:10,no_such_turret,45\n"
	)
	assert_true(missing.has_errors())
	assert_true(
		missing.describe_errors().contains("sentry_machine"), missing.describe_errors()
	)

	var not_a_turret: Definitions = _parse_stratagems(
		"smelter_sentry,Smelter Sentry,sentry,3,0,0,ammunition:10,smelter_mk1,45\n"
	)
	assert_true(not_a_turret.has_errors(), "a Sentry Drop places a Turret")
	assert_true(
		not_a_turret.describe_errors().contains("sentry_machine"),
		not_a_turret.describe_errors()
	)


func test_a_stratagem_that_is_not_a_sentry_may_not_be_temporary() -> void:
	var definitions: Definitions = _parse_stratagems(
		"timed_barrage,Timed Barrage,barrage,5,6,150,,,30\n"
	)
	assert_true(definitions.has_errors())
	assert_true(
		definitions.describe_errors().contains("sentry_seconds"), definitions.describe_errors()
	)


func test_a_stratagem_naming_an_effect_nothing_answers_to_is_refused_by_name() -> void:
	var definitions: Definitions = _parse_stratagems(
		"nuke,Nuke,orbital_strike,5,6,150,,,0\n"
	)
	assert_true(definitions.has_errors())
	assert_true(definitions.describe_errors().contains("effect"), definitions.describe_errors())


func test_a_stratagem_delivering_an_item_no_recipe_mentions_is_refused() -> void:
	# The set of Items is exactly what the Recipes mention, so a drop of something nothing in
	# the Factory could make is content somebody broke.
	var definitions: Definitions = _parse_stratagems(
		"medkit_drop,Medkit Drop,supply,3,0,0,bandages:2,,0\n"
	)
	assert_true(definitions.has_errors())
	assert_true(
		definitions.describe_errors().contains("goods_per_charge"),
		definitions.describe_errors()
	)


func test_an_empty_stratagem_table_is_an_error() -> void:
	var definitions: Definitions = _parse_stratagems("")
	assert_true(
		definitions.has_errors(), "a Silo with nothing to load is a Machine nobody can use"
	)


func test_a_delivery_tier_unlocking_a_stratagem_that_does_not_exist_is_refused() -> void:
	var definitions: Definitions = Definitions.parse(
		GOOD_MACHINES,
		GOOD_RECIPES,
		GOOD_TUNING,
		WAVES,
		DELIVERY_HEADER + "t01_opening,Opening Licence,1,iron_plate:1,,,no_such_stratagem\n",
		GEAR,
		STRATAGEMS,
		MACHINES,
		RECIPES,
		TUNING,
		WAVES_PATH,
		DELIVERIES_PATH,
		"gear.csv",
		"stratagems.csv"
	)
	assert_true(definitions.has_errors(), "one authority, checked rather than assumed")
	assert_true(
		definitions.describe_errors().contains("unlocks_stratagems"),
		definitions.describe_errors()
	)


func test_a_silo_whose_recipe_produces_an_item_is_refused() -> void:
	# A Charge is not an Item, so the Silo joins the rule a generator and a Turret already
	# obey rather than getting a clause of its own.
	var definitions: Definitions = Definitions.parse(
		GOOD_MACHINES + SILO_MACHINE_ROW,
		GOOD_RECIPES + "assemble_charge,Assemble Charge,iron_plate:1,iron_gear:1,20\n",
		GOOD_TUNING,
		WAVES,
		DELIVERY_HEADER + "t01_opening,Opening Licence,1,iron_plate:1,,gear_a,\n",
		GEAR,
		STRATAGEMS,
		MACHINES,
		RECIPES,
		TUNING,
		WAVES_PATH,
		DELIVERIES_PATH,
		"gear.csv",
		"stratagems.csv"
	)
	assert_true(definitions.has_errors())
	assert_true(
		definitions.describe_errors().contains("a Charge"),
		"and the message names what it does produce: " + definitions.describe_errors()
	)


func test_only_a_silo_may_declare_a_charge_capacity() -> void:
	var definitions: Definitions = _parse(
		GOOD_MACHINES.replace(
			"smelter_mk1,Smelter Mk1,crafter,3,3,1.5,180,0,500,0,0,0,0,0,smelt",
			"smelter_mk1,Smelter Mk1,crafter,3,3,1.5,180,0,500,0,0,0,0,6,smelt"
		),
		GOOD_RECIPES,
		GOOD_TUNING
	)
	assert_true(definitions.has_errors(), "a number in a column nothing reads lies")
	assert_true(
		definitions.describe_errors().contains("charge_capacity"),
		definitions.describe_errors()
	)


func test_a_silo_that_stockpiles_nothing_is_refused() -> void:
	var definitions: Definitions = Definitions.parse(
		GOOD_MACHINES + SILO_MACHINE_ROW.replace(",0,0,0,8,assemble", ",0,0,0,0,assemble"),
		GOOD_RECIPES + ASSEMBLE_ROW,
		GOOD_TUNING,
		WAVES,
		DELIVERY_HEADER + "t01_opening,Opening Licence,1,iron_plate:1,,gear_a,\n",
		GEAR,
		STRATAGEMS,
		MACHINES,
		RECIPES,
		TUNING,
		WAVES_PATH,
		DELIVERIES_PATH,
		"gear.csv",
		"stratagems.csv"
	)
	assert_true(definitions.has_errors(), "a Silo that holds nothing could never be loaded")
	assert_true(
		definitions.describe_errors().contains("charge_capacity"),
		definitions.describe_errors()
	)

