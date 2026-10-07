## The Godot-side watcher that notices a content file was saved.
##
## This is the half of hot-reload that cannot live in the Simulation: it reads the
## clock to decide when to look, and reads the filesystem to see what changed. Both
## are forbidden inside `sim/` (ADR 0002), which is why the watcher lives in `game/`
## alongside `TickPump` and is tested the same way — directly, as a game-layer
## component with a contract of its own.
##
## What crosses the boundary is a `Definitions`, handed to the Simulation as an
## Input Action. The watcher never touches Simulation state.
##
## Two behaviours worth the test effort:
##
## * **A broken edit must not reach the Simulation.** Half of hot-reload's value is
##   that you can tune with the game running; all of that value is gone if a typo
##   mid-edit takes the Run down. So a malformed file produces errors and no
##   definition set at all.
## * **A fix after a break must still be noticed.** The obvious implementation
##   remembers the last *good* content and therefore re-reports the same broken file
##   forever, or worse, stops looking.
extends TestCase

const DIR: String = "user://definition_watcher_test"

const MACHINES: String = """
id,display_name,role,footprint_x,footprint_z,power_draw_kw,power_supply_kw,health,max_depth,range_tiles,damage,repair,recipe_id,build_cost
miner_mk1,Miner Mk1,miner,2,2,120,0,400,1,0,0,0,mine_iron_ore,
"""

const RECIPES: String = """
id,display_name,inputs,outputs,seconds
mine_iron_ore,Mine Iron Ore,,iron_ore:1,1.5
"""

## The tuning keys this file is not about. Every key the Simulation reads must be present
## for a set to load, so a test that varies one carries the rest unchanged.
const OTHER_TUNING: String = """
walk_acceleration_metres_per_second_squared = 24
look_sensitivity_turns_per_1000_pixels = 0.4
eye_height_metres = 1.7
health = 150
downed_bleed_out_seconds = 20
respawn_delay_seconds = 8
revive_seconds = 4
revive_reach_metres = 3
starting_weapon = "pneumatic_wrench"
starting_stock = "iron_ore:200"
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
delivery_reach_metres = 5
store_capacity_per_item = 200
[wave]
telegraph_seconds = 12
spawn_interval_seconds = 0.5
call_early_bounty_per_item = 25

[heat]
per_craft = 2
per_craft_per_depth = 1
decay_per_minute = 240
wave_interval_baseline_seconds = 150
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
[wrench]
repair_points_per_second = 60
reach_metres = 4
"""

const TUNING: String = """
[player]
walk_speed_metres_per_second = 4
sprint_speed_multiplier = 1.8
""" + OTHER_TUNING

## Long enough to pass any sane check interval.
const A_LONG_FRAME: float = 10.0


## The shipped Wave composition, inline so the fixture is a complete definition set. A
## Wave's contents are a table (`content/waves.csv`), and a set with no rows in it is an
## error rather than a Run that is never attacked.
const WAVES: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,6,150,40
"""


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_write(Definitions.MACHINES_FILE, MACHINES)
	_write(Definitions.RECIPES_FILE, RECIPES)
	_write(Definitions.TUNING_FILE, TUNING)
	_write(Definitions.WAVES_FILE, WAVES)
	_write(Definitions.DELIVERIES_FILE, DELIVERIES)
	_write(Definitions.GEAR_FILE, GEAR)


func after_each() -> void:
	for file_name: String in [
		Definitions.MACHINES_FILE,
		Definitions.RECIPES_FILE,
		Definitions.TUNING_FILE,
		Definitions.WAVES_FILE,
		Definitions.DELIVERIES_FILE,
		Definitions.GEAR_FILE,
	]:
		DirAccess.remove_absolute("%s/%s" % [DIR, file_name])
	DirAccess.remove_absolute(DIR)


func _write(file_name: String, text: String) -> void:
	var file: FileAccess = FileAccess.open("%s/%s" % [DIR, file_name], FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _watcher() -> DefinitionWatcher:
	return DefinitionWatcher.new(DIR)


# ── Noticing nothing ──────────────────────────────────────────────────────────

func test_a_fresh_watcher_reports_no_change() -> void:
	# The baseline is the content at construction, so nothing has changed yet.
	# Reporting a change here would make every Run reload on its first frame, and
	# establishing the baseline lazily on the first check would make every Run miss
	# its first edit.
	var watcher: DefinitionWatcher = _watcher()
	assert_null(watcher.check_now())
	assert_false(watcher.has_errors())


func test_checking_an_unchanged_directory_reports_no_change() -> void:
	var watcher: DefinitionWatcher = _watcher()
	watcher.check_now()
	assert_null(watcher.check_now())
	assert_null(watcher.check_now())


func test_rewriting_a_file_with_identical_content_reports_no_change() -> void:
	# A save that changed nothing is not a change. Watching content rather than
	# modification times means an editor that touches a file on focus loss does not
	# produce a reload, and — more importantly for tests and for rapid saves — two
	# edits within the same second are not mistaken for one.
	var watcher: DefinitionWatcher = _watcher()
	watcher.check_now()
	_write(Definitions.TUNING_FILE, TUNING)
	assert_null(watcher.check_now())


# ── Noticing a save ───────────────────────────────────────────────────────────

func test_editing_the_tuning_file_produces_a_new_definition_set() -> void:
	var watcher: DefinitionWatcher = _watcher()
	watcher.check_now()

	_write(Definitions.TUNING_FILE, "[player]\nwalk_speed_metres_per_second = 7\nsprint_speed_multiplier = 1.8\n" + OTHER_TUNING)

	var reloaded: Definitions = watcher.check_now()
	assert_not_null(reloaded, "a saved edit must be noticed")
	assert_false(reloaded.has_errors(), reloaded.describe_errors())
	assert_eq(reloaded.player_walk_speed, 7 * 65536)


func test_adding_a_machine_and_recipe_produces_a_new_definition_set() -> void:
	var watcher: DefinitionWatcher = _watcher()
	watcher.check_now()

	_write(
		Definitions.RECIPES_FILE,
		RECIPES + "smelt_iron_plate,Smelt Iron Plate,iron_ore:2,iron_plate:1,3.2\n"
	)
	_write(
		Definitions.MACHINES_FILE,
		MACHINES + "smelter_mk1,Smelter Mk1,crafter,3,3,180,0,500,0,0,0,0,smelt_iron_plate,\n"
	)

	var reloaded: Definitions = watcher.check_now()
	assert_not_null(reloaded)
	assert_false(reloaded.has_errors(), reloaded.describe_errors())
	assert_true(reloaded.has_machine("smelter_mk1"))


func test_a_change_is_reported_once_not_on_every_check() -> void:
	var watcher: DefinitionWatcher = _watcher()
	watcher.check_now()
	_write(Definitions.TUNING_FILE, "[player]\nwalk_speed_metres_per_second = 7\nsprint_speed_multiplier = 1.8\n" + OTHER_TUNING)

	assert_not_null(watcher.check_now())
	assert_null(watcher.check_now(), "the same edit must not reload every frame")


# ── A broken save ─────────────────────────────────────────────────────────────

func test_a_malformed_edit_produces_no_definitions_and_names_the_file_and_row() -> void:
	var watcher: DefinitionWatcher = _watcher()
	watcher.check_now()

	_write(Definitions.RECIPES_FILE, RECIPES.replace(",1.5", ",soon"))

	assert_null(watcher.check_now(), "a broken edit must never reach the Simulation")
	assert_true(watcher.has_errors())
	var text: String = watcher.describe_errors()
	assert_true(text.contains(Definitions.RECIPES_FILE), text)
	assert_true(text.contains(":3"), "the row, got: %s" % text)
	assert_true(text.contains("soon"), text)


func test_fixing_a_malformed_edit_is_noticed() -> void:
	# The failure mode this guards: a watcher that remembers only the last *good*
	# content either re-reports the same broken file forever or stops looking.
	var watcher: DefinitionWatcher = _watcher()
	watcher.check_now()

	_write(Definitions.TUNING_FILE, "[player]\nwalk_speed_metres_per_second = oops\n")
	assert_null(watcher.check_now())
	assert_true(watcher.has_errors())

	_write(Definitions.TUNING_FILE, "[player]\nwalk_speed_metres_per_second = 9\nsprint_speed_multiplier = 1.8\n" + OTHER_TUNING)
	var reloaded: Definitions = watcher.check_now()
	assert_not_null(reloaded, "the fix must be picked up")
	assert_eq(reloaded.player_walk_speed, 9 * 65536)
	assert_false(watcher.has_errors(), "and the complaint must be cleared")


func test_the_same_broken_file_is_not_reported_over_and_over() -> void:
	var watcher: DefinitionWatcher = _watcher()
	watcher.check_now()
	_write(Definitions.TUNING_FILE, "[player]\nwalk_speed_metres_per_second = oops\n")

	watcher.check_now()
	var first: String = watcher.describe_errors()
	watcher.check_now()
	assert_eq(watcher.describe_errors(), first, "a stuck typo must not spam the log each frame")


func test_a_deleted_file_is_reported_rather_than_read_as_empty() -> void:
	var watcher: DefinitionWatcher = _watcher()
	watcher.check_now()
	DirAccess.remove_absolute("%s/%s" % [DIR, Definitions.TUNING_FILE])

	assert_null(watcher.check_now())
	assert_true(watcher.has_errors())
	assert_true(watcher.describe_errors().contains(Definitions.TUNING_FILE), watcher.describe_errors())

	# Put it back so after_each has something to remove and the next test starts clean.
	_write(Definitions.TUNING_FILE, TUNING)


# ── When it looks ─────────────────────────────────────────────────────────────

func test_polling_only_checks_once_the_interval_has_elapsed() -> void:
	# Reading three files every frame to support a developer convenience would be a
	# poor trade. The interval is the whole reason `poll` takes a frame time.
	var watcher: DefinitionWatcher = DefinitionWatcher.new(DIR, 1.0)
	watcher.check_now()
	_write(Definitions.TUNING_FILE, "[player]\nwalk_speed_metres_per_second = 7\nsprint_speed_multiplier = 1.8\n" + OTHER_TUNING)

	assert_null(watcher.poll(0.1), "not yet")
	assert_null(watcher.poll(0.1), "still not yet")
	assert_not_null(watcher.poll(A_LONG_FRAME), "now")


func test_the_very_first_edit_of_a_session_is_not_missed() -> void:
	# The baseline is taken at construction precisely so this works. A watcher that
	# established it lazily would swallow the first edit after launch, which is the
	# one a developer is most likely to be testing the feature with.
	var watcher: DefinitionWatcher = _watcher()
	_write(Definitions.TUNING_FILE, "[player]\nwalk_speed_metres_per_second = 7\nsprint_speed_multiplier = 1.8\n" + OTHER_TUNING)
	assert_not_null(watcher.check_now())


# ── Reaching the Simulation ───────────────────────────────────────────────────
# The last link: a saved file becomes an Input Action, and the Simulation applies
# it. Asserted through `Main` because that is the only thing allowed to join the two
# halves — the watcher must never write Simulation state itself.

func test_a_saved_edit_reaches_the_simulation_as_an_input_action() -> void:
	var main: Main = Main.new()
	main.set_definition_watcher(DefinitionWatcher.new(DIR, 0.0))

	_write(Definitions.TUNING_FILE, "[player]\nwalk_speed_metres_per_second = 7\nsprint_speed_multiplier = 1.8\n" + OTHER_TUNING)
	main.advance_frame(1.0 / float(Simulation.TICKS_PER_SECOND))

	assert_eq(main.simulation().query_definition_generation(), 1, "the edit was applied")
	assert_eq(main.simulation().query_definitions().player_walk_speed, 7 * 65536)
	main.free()


func test_a_saved_edit_is_applied_once_not_on_every_frame() -> void:
	var main: Main = Main.new()
	main.set_definition_watcher(DefinitionWatcher.new(DIR, 0.0))

	_write(Definitions.TUNING_FILE, "[player]\nwalk_speed_metres_per_second = 7\nsprint_speed_multiplier = 1.8\n" + OTHER_TUNING)
	for frame: int in range(10):
		main.advance_frame(1.0 / float(Simulation.TICKS_PER_SECOND))

	assert_eq(main.simulation().query_definition_generation(), 1)
	main.free()


func test_a_broken_edit_does_not_reach_the_simulation() -> void:
	var main: Main = Main.new()
	main.set_definition_watcher(DefinitionWatcher.new(DIR, 0.0))

	_write(Definitions.TUNING_FILE, "[player]\nwalk_speed_metres_per_second = oops\n")
	main.advance_frame(1.0 / float(Simulation.TICKS_PER_SECOND))

	assert_eq(main.simulation().query_definition_generation(), 0, "a typo must not reach a Run")
	assert_true(main.simulation().query_definitions_loaded(), "and must not break the one it has")
	main.free()


func test_a_frame_with_no_tick_holds_the_edit_until_there_is_one() -> void:
	# Definitions are Simulation state, so they change on a tick like everything else.
	# A frame too short to earn a tick must not apply the reload early, and must not
	# drop it either.
	var main: Main = Main.new()
	main.set_definition_watcher(DefinitionWatcher.new(DIR, 0.0))

	_write(Definitions.TUNING_FILE, "[player]\nwalk_speed_metres_per_second = 7\nsprint_speed_multiplier = 1.8\n" + OTHER_TUNING)
	main.advance_frame(0.001)
	assert_eq(main.simulation().query_definition_generation(), 0, "no tick, no change")

	main.advance_frame(1.0 / float(Simulation.TICKS_PER_SECOND))
	assert_eq(main.simulation().query_definition_generation(), 1, "and it was not dropped")
	main.free()


## The Delivery tiers, inline so the fixture is a complete definition set. Progression is
## physical (`content/deliveries.csv`), and a table with no rows in it is an error rather
## than a Run with no progression. This one unlocks a Gear component and names no Machine,
## so nothing this file builds is locked behind it.
const DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_opening,Opening Licence,1,iron_ore:1,,placeholder_gear,
"""


## The Gear a Run is holding, inline so the fixture is a complete definition set. One
## weapon frame and the component the tier above names, because a tier naming Gear that
## does not exist is content somebody broke.
const GEAR: String = """id,display_name,kind,attack,damage,range_metres,spread_degrees,seconds_per_shot,ammunition_item,ammunition_per_shot,damage_percent,range_percent,spread_percent,interval_percent,ammunition_percent,damage_taken_percent
pneumatic_wrench,Pneumatic Wrench,weapon,melee,55,4,0,0.6,,0,0,0,0,0,0,0
placeholder_gear,Placeholder Barrel,barrel,,0,0,0,0,,0,10,0,0,0,0,0
"""
