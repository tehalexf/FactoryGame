## The Build Gun, as behaviour of the Simulation.
##
## The Build Gun is the tool through which all construction happens, available at all
## times including mid-Wave (GLOSSARY.md). There is no build mode: nothing in the
## Simulation consults a flag before accepting a build intent, and the tests here are
## written so that a mode could not be added without one of them going red.
##
## The content below is local to this case because the shipped `content/machines.csv`
## has only square Machines, and a square footprint cannot show whether rotation
## works. `press_mk1` is 2x3 for exactly that reason.
extends TestCase

const MACHINES: String = """\
id,display_name,role,footprint_x,footprint_z,height_metres,power_draw_kw,power_supply_kw,health,max_depth,range_tiles,damage,repair,charge_capacity,recipe_id,build_cost
miner_mk1,Miner Mk1,miner,2,2,1.8,120,0,400,1,0,0,0,0,mine_iron_ore,iron_plate:8
press_mk1,Press Mk1,crafter,2,3,2,180,0,500,0,0,0,0,0,press_iron_frame,iron_plate:12;iron_ore:4
free_mk1,Scaffold,crafter,1,1,2,10,0,50,0,0,0,0,0,press_iron_frame,
"""

const RECIPES: String = """\
id,display_name,inputs,outputs,seconds
mine_iron_ore,Mine Iron Ore,,iron_ore:1,1.5
press_iron_frame,Press Iron Frame,iron_plate:2,iron_frame:1,2
"""

const TUNING: String = """\
[player]
walk_speed_metres_per_second = 4
sprint_speed_multiplier = 1.8
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
starting_stock = "iron_frame:40;iron_ore:40;iron_plate:40"
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


## The shipped Wave composition, inline so the fixture is a complete definition set. A
## Wave's contents are a table (`content/waves.csv`), and a set with no rows in it is an
## error rather than a Run that is never attacked.
const WAVES: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,6,150,40
"""


func _content() -> Definitions:
	return Definitions.parse(
		MACHINES,
		RECIPES,
		TUNING,
		WAVES,
		DELIVERIES,
		GEAR,
		STRATAGEMS,
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv",
		"deliveries.csv",
		"gear.csv",
		"stratagems.csv"
	)


## A Run on an empty Map, so nothing but the Factory under test is in the way.
func _sim(players: int = 1) -> Simulation:
	return Simulation.new(7, players, _content(), MapLayout.empty())


func _index(sim: Simulation, id: String) -> int:
	return sim.query_definitions().machine_index(id)


# ── The content these tests bring ─────────────────────────────────────────────

func test_the_content_these_tests_bring_loads_cleanly() -> void:
	var definitions: Definitions = _content()
	assert_false(definitions.has_errors(), definitions.describe_errors())
	assert_eq(definitions.machine_count(), 3)


# ── Choosing what to build ────────────────────────────────────────────────────
# What a player has on the Build Gun is Simulation state, not controller state. Two
# reasons: the controller is forbidden to hold anything authoritative, and in co-op
# what another player is about to place is worth drawing.

func test_a_run_opens_with_the_first_machine_on_the_build_gun() -> void:
	var sim: Simulation = _sim()
	assert_eq(
		sim.query_player_selected_machine(0),
		"free_mk1",
		"the first Machine by id, so a fresh Run has something to place"
	)


func test_selecting_a_machine_puts_it_on_the_build_gun() -> void:
	var sim: Simulation = _sim()
	sim.step([InputAction.select_machine(0, _index(sim, "press_mk1"))])
	assert_eq(sim.query_player_selected_machine(0), "press_mk1")


func test_the_build_gun_holds_a_machine_by_id_so_a_reload_cannot_renumber_it() -> void:
	# The selection is stored resolved, exactly as a placed Machine is, because a
	# hot-reload resorts the definition table and a player must not find a different
	# Machine on the Build Gun because somebody added a row.
	var sim: Simulation = _sim()
	sim.step([InputAction.select_machine(0, _index(sim, "press_mk1"))])
	assert_eq(
		sim.query_player_selected_machine_index(0),
		_index(sim, "press_mk1"),
		"the index is derived from the id, not stored beside it"
	)


func test_selecting_a_machine_that_does_not_exist_is_refused() -> void:
	var sim: Simulation = _sim()
	sim.step([InputAction.select_machine(0, _index(sim, "press_mk1"))])
	var before: int = sim.hash()
	sim.step([InputAction.select_machine(0, 99)])
	assert_eq(sim.query_player_selected_machine(0), "press_mk1", "the choice stands")
	assert_ne(before, 0)


func test_each_player_carries_their_own_build_gun() -> void:
	var sim: Simulation = _sim(2)
	sim.step([InputAction.select_machine(1, _index(sim, "miner_mk1"))])
	assert_eq(sim.query_player_selected_machine(0), "free_mk1")
	assert_eq(sim.query_player_selected_machine(1), "miner_mk1")


func test_what_is_on_the_build_gun_is_part_of_the_state_hash() -> void:
	var sim: Simulation = _sim()
	var before: int = sim.hash()
	sim.step([InputAction.select_machine(0, _index(sim, "miner_mk1"))])
	assert_ne(sim.hash(), before)


# ── Rotating the hologram ─────────────────────────────────────────────────────

func test_a_run_opens_unrotated() -> void:
	assert_eq(_sim().query_player_build_rotation(0), 0)


func test_rotating_advances_a_quarter_turn_at_a_time() -> void:
	var sim: Simulation = _sim()
	sim.step([InputAction.rotate_build(0, 1)])
	assert_eq(sim.query_player_build_rotation(0), 1)
	sim.step([InputAction.rotate_build(0, 1)])
	assert_eq(sim.query_player_build_rotation(0), 2)


func test_rotation_comes_back_round_after_four_quarters() -> void:
	var sim: Simulation = _sim()
	for quarter: int in range(4):
		sim.step([InputAction.rotate_build(0, 1)])
	assert_eq(sim.query_player_build_rotation(0), 0, "four quarter turns is where it started")


func test_rotating_backwards_wraps_the_other_way() -> void:
	var sim: Simulation = _sim()
	sim.step([InputAction.rotate_build(0, -1)])
	assert_eq(sim.query_player_build_rotation(0), 3)


func test_a_rotated_machine_occupies_a_turned_footprint() -> void:
	# A 2x3 Press rotated a quarter turn covers 3x2 tiles. The anchor does not move:
	# a footprint still grows along +x and +z from the tile it was placed on, so
	# rotation swaps the extents and nothing else needs a second convention.
	var sim: Simulation = _sim()
	var press: int = _index(sim, "press_mk1")
	sim.step([InputAction.build_machine(0, press, Vector3i(0, 0, 0), 1)])

	assert_eq(sim.query_machine_count(), 1, "the premise of the rest")
	assert_eq(sim.query_machine_rotation(0), 1)
	assert_eq(sim.query_machine_footprint(0), Vector2i(3, 2), "2x3 turned is 3x2")
	assert_eq(sim.query_machine_at_tile(Vector3i(2, 0, 0)), 0, "the third tile along x is covered")
	assert_eq(sim.query_machine_at_tile(Vector3i(0, 0, 2)), -1, "and the third along z is not")


func test_an_unrotated_machine_occupies_the_footprint_the_file_declares() -> void:
	var sim: Simulation = _sim()
	sim.step([InputAction.build_machine(0, _index(sim, "press_mk1"), Vector3i(0, 0, 0))])
	assert_eq(sim.query_machine_footprint(0), Vector2i(2, 3))
	assert_eq(sim.query_machine_at_tile(Vector3i(0, 0, 2)), 0)
	assert_eq(sim.query_machine_at_tile(Vector3i(2, 0, 0)), -1)


func test_rotation_changes_what_a_footprint_collides_with() -> void:
	# The reason rotation has to reach placement validation rather than only the
	# mesh: a turned Machine covers different ground.
	var sim: Simulation = _sim()
	var press: int = _index(sim, "press_mk1")
	sim.step([InputAction.build_machine(0, press, Vector3i(0, 0, 0), 1)])
	sim.step([InputAction.build_machine(0, press, Vector3i(2, 0, 0), 0)])
	assert_eq(sim.query_machine_count(), 1, "the second Press lands on the turned first one")


func test_which_way_a_machine_faces_is_part_of_the_state_hash() -> void:
	var turned: Simulation = _sim()
	var square: Simulation = _sim()
	var press: int = _index(turned, "press_mk1")
	turned.step([InputAction.build_machine(0, press, Vector3i(0, 0, 0), 1)])
	square.step([InputAction.build_machine(0, press, Vector3i(0, 0, 0), 0)])
	assert_ne(turned.hash(), square.hash())


func test_the_rotation_the_build_gun_is_holding_is_part_of_the_state_hash() -> void:
	var sim: Simulation = _sim()
	var before: int = sim.hash()
	sim.step([InputAction.rotate_build(0, 1)])
	assert_ne(sim.hash(), before)


# ── Why a placement was refused ───────────────────────────────────────────────
# A refused build is still a silent no-op that does not move the hash — a misaimed
# Build Gun is an ordinary thing for a player to do, and a Run whose hash twitched
# every time somebody clicked at a wall would be hard to reason about.
#
# The *reason* is therefore a query rather than stored state: a pure function of the
# current state and the placement being considered. The hologram asks it every frame
# about the tile it is hovering over, so the reason is on screen before the click
# rather than after it, which is both better UX and the only version that leaves the
# hash alone. `_apply_build_machine` consults the same function, so what the player
# is told and what the Simulation does cannot disagree.

func test_a_placement_with_nothing_in_the_way_is_not_refused() -> void:
	var sim: Simulation = _sim()
	assert_eq(
		sim.query_build_refusal(0, _index(sim, "press_mk1"), Vector3i(0, 0, 0), 0),
		Simulation.Refusal.NONE
	)


func test_a_placement_off_the_map_is_refused_as_off_the_map() -> void:
	var sim: Simulation = _sim()
	var beyond: int = sim.query_grid_half_extent_tiles() + 1
	assert_eq(
		sim.query_build_refusal(0, _index(sim, "miner_mk1"), Vector3i(beyond, 0, 0), 0),
		Simulation.Refusal.OFF_THE_MAP
	)


func test_a_placement_above_the_ground_is_refused_while_building_is_flat() -> void:
	var sim: Simulation = _sim()
	assert_eq(
		sim.query_build_refusal(0, _index(sim, "miner_mk1"), Vector3i(0, 1, 0), 0),
		Simulation.Refusal.OFF_THE_MAP
	)


func test_a_placement_on_another_machine_is_refused_as_occupied() -> void:
	var sim: Simulation = _sim()
	var miner: int = _index(sim, "miner_mk1")
	sim.step([InputAction.build_machine(0, miner, Vector3i(0, 0, 0))])
	assert_eq(
		sim.query_build_refusal(0, miner, Vector3i(1, 0, 1), 0),
		Simulation.Refusal.OCCUPIED,
		"the first Miner's 2x2 footprint reaches that tile"
	)


func test_a_placement_on_a_belt_is_refused_as_occupied() -> void:
	var sim: Simulation = _sim()
	sim.step([InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(4, 0, 0))])
	assert_eq(
		sim.query_build_refusal(0, _index(sim, "miner_mk1"), Vector3i(2, 0, 0), 0),
		Simulation.Refusal.OCCUPIED
	)


func test_a_rotation_can_be_the_difference_between_refused_and_allowed() -> void:
	# The reason the hologram has to ask about the rotation it is holding rather than
	# about the bare tile: the same anchor is legal one way round and not the other.
	var sim: Simulation = _sim()
	var press: int = _index(sim, "press_mk1")
	sim.step([InputAction.build_machine(0, press, Vector3i(0, 0, 4))])

	assert_eq(
		sim.query_build_refusal(0, press, Vector3i(0, 0, 2), 0),
		Simulation.Refusal.OCCUPIED,
		"2x3 from z=2 reaches z=4, where the first Press stands"
	)
	assert_eq(
		sim.query_build_refusal(0, press, Vector3i(0, 0, 2), 1),
		Simulation.Refusal.NONE,
		"turned, it is only 2 tiles deep and stops short"
	)


func test_a_build_gun_holding_no_machine_is_refused_by_name() -> void:
	var sim: Simulation = _sim()
	assert_eq(sim.query_build_refusal(0, 99, Vector3i(0, 0, 0), 0), Simulation.Refusal.NO_SUCH_MACHINE)


func test_a_refused_build_leaves_the_hash_exactly_where_it_was() -> void:
	var sim: Simulation = _sim()
	var miner: int = _index(sim, "miner_mk1")
	sim.step([InputAction.build_machine(0, miner, Vector3i(0, 0, 0))])

	var settled: Simulation = _sim()
	settled.step([InputAction.build_machine(0, miner, Vector3i(0, 0, 0))])

	sim.step([InputAction.build_machine(0, miner, Vector3i(1, 0, 1))])
	settled.step([])
	assert_eq(
		sim.hash(),
		settled.hash(),
		"clicking at an occupied tile must be indistinguishable from not clicking"
	)


func test_the_refusal_a_query_reports_is_the_one_a_build_obeys() -> void:
	# The property that keeps the hologram honest: every refusal the query names is a
	# refusal the Simulation actually enforces.
	var sim: Simulation = _sim()
	var miner: int = _index(sim, "miner_mk1")
	sim.step([InputAction.build_machine(0, miner, Vector3i(0, 0, 0))])

	var tiles: Array = [Vector3i(1, 0, 1), Vector3i(0, 1, 0), Vector3i(200, 0, 0)]
	for tile: Vector3i in tiles:
		var refusal: int = sim.query_build_refusal(0, miner, tile, 0)
		var before: int = sim.query_machine_count()
		sim.step([InputAction.build_machine(0, miner, tile)])
		assert_eq(
			sim.query_machine_count(),
			before,
			"the query said %d about %s, so nothing should have been built" % [refusal, tile]
		)
		assert_ne(refusal, Simulation.Refusal.NONE, "and it should have named a reason")


# ── What a Machine costs ──────────────────────────────────────────────────────
# A Machine's build cost is a column in `content/machines.csv`, in the same
# `item:count` form a Recipe's inputs use, and may be empty for something free.
# The materials come out of the player's own stock, which is what makes demolishing
# worth doing: a layout you can take back apart is a layout you will iterate on.
#
# Where that stock comes from is `player.starting_stock`: an explicit bill of goods, so a
# Run opens with exactly the materials for its opening line and everything past that is
# unlocked at the Nest (`content/deliveries.csv`).

func test_a_run_opens_holding_the_tuned_starting_stock() -> void:
	var sim: Simulation = _sim()
	assert_eq(sim.query_player_item(0, "iron_plate"), 40)
	assert_eq(sim.query_player_item(0, "iron_ore"), 40)
	assert_eq(
		sim.query_player_items(0),
		PackedStringArray(["iron_frame", "iron_ore", "iron_plate"]),
		"sorted, so the order is a property of the content and not of what happened"
	)


func test_an_item_nothing_mentions_is_not_in_the_stock() -> void:
	assert_eq(_sim().query_player_item(0, "unobtainium"), 0)


func test_building_a_machine_spends_its_build_cost() -> void:
	var sim: Simulation = _sim()
	sim.step([InputAction.build_machine(0, _index(sim, "press_mk1"), Vector3i(0, 0, 0))])
	assert_eq(sim.query_player_item(0, "iron_plate"), 28, "40 less the Press's 12 plate")
	assert_eq(sim.query_player_item(0, "iron_ore"), 36, "and less its 4 ore")


func test_a_machine_with_no_build_cost_is_free() -> void:
	var sim: Simulation = _sim()
	sim.step([InputAction.build_machine(0, _index(sim, "free_mk1"), Vector3i(0, 0, 0))])
	assert_eq(sim.query_machine_count(), 1, "it was built")
	assert_eq(sim.query_player_item(0, "iron_plate"), 40, "and cost nothing")


func test_a_placement_a_player_cannot_pay_for_is_refused_by_name() -> void:
	var sim: Simulation = _sim()
	var miner: int = _index(sim, "miner_mk1")
	# 8 plate each out of 40 buys five Miners and no more.
	for which: int in range(5):
		sim.step([InputAction.build_machine(0, miner, Vector3i(which * 2, 0, 0))])
	assert_eq(sim.query_machine_count(), 5, "the premise of the rest")
	assert_eq(sim.query_player_item(0, "iron_plate"), 0)

	assert_eq(
		sim.query_build_refusal(0, miner, Vector3i(10, 0, 0), 0),
		Simulation.Refusal.MISSING_MATERIALS
	)
	sim.step([InputAction.build_machine(0, miner, Vector3i(10, 0, 0))])
	assert_eq(sim.query_machine_count(), 5, "and the sixth really was not built")


func test_the_ground_is_checked_before_the_wallet() -> void:
	# Which reason a player is shown when more than one applies. Aiming at a wall is
	# the more immediate problem and the one they can fix by aiming elsewhere.
	var sim: Simulation = _sim()
	var miner: int = _index(sim, "miner_mk1")
	for which: int in range(5):
		sim.step([InputAction.build_machine(0, miner, Vector3i(which * 2, 0, 0))])
	assert_eq(
		sim.query_build_refusal(0, miner, Vector3i(0, 0, 0), 0),
		Simulation.Refusal.OCCUPIED,
		"broke *and* aiming at a Miner reads as aiming at a Miner"
	)


func test_what_a_player_is_carrying_is_part_of_the_state_hash() -> void:
	var spent: Simulation = _sim()
	var saved: Simulation = _sim()
	spent.step([InputAction.build_machine(0, _index(spent, "miner_mk1"), Vector3i(0, 0, 0))])
	saved.step([])
	assert_ne(spent.hash(), saved.hash())


func test_each_player_carries_their_own_materials() -> void:
	var sim: Simulation = _sim(2)
	sim.step([InputAction.build_machine(1, _index(sim, "miner_mk1"), Vector3i(0, 0, 0))])
	assert_eq(sim.query_player_item(0, "iron_plate"), 40, "player 0 paid for nothing")
	assert_eq(sim.query_player_item(1, "iron_plate"), 32, "player 1 paid for the Miner")


# ── Demolishing ───────────────────────────────────────────────────────────────

func test_demolishing_a_machine_removes_it_and_returns_its_materials() -> void:
	var sim: Simulation = _sim()
	sim.step([InputAction.build_machine(0, _index(sim, "press_mk1"), Vector3i(0, 0, 0))])
	assert_eq(sim.query_player_item(0, "iron_plate"), 28, "the premise of the rest")

	sim.step([InputAction.demolish(0, Vector3i(1, 0, 1))])
	assert_eq(sim.query_machine_count(), 0, "the Press is gone")
	assert_eq(sim.query_player_item(0, "iron_plate"), 40, "and every plate came back")
	assert_eq(sim.query_player_item(0, "iron_ore"), 40, "and every ore")


func test_demolishing_works_from_any_tile_of_the_footprint() -> void:
	var sim: Simulation = _sim()
	sim.step([InputAction.build_machine(0, _index(sim, "press_mk1"), Vector3i(4, 0, 4))])
	sim.step([InputAction.demolish(0, Vector3i(5, 0, 6))])
	assert_eq(sim.query_machine_count(), 0, "a Machine is demolished by pointing at any of it")
	assert_eq(sim.query_player_item(0, "iron_plate"), 40)


func test_demolishing_a_machine_returns_what_it_was_holding_as_well() -> void:
	# Nothing is destroyed by demolishing. A Miner that has banked ore hands it over
	# rather than deleting it, which is also what stops demolish-and-rebuild being a
	# way to make Items disappear.
	var sim: Simulation = _sim()
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	var mining: Simulation = Simulation.new(7, 1, _content(), layout)
	mining.step([InputAction.build_machine(0, _index(mining, "miner_mk1"), Vector3i(0, 0, 0))])
	# 1.5 s a craft at 60 ticks a second is 90 ticks an ore; three crafts is 270.
	for tick: int in range(270):
		mining.step([])
	assert_eq(mining.query_machine_output(0, "iron_ore"), 3, "the premise of the rest")

	mining.step([InputAction.demolish(0, Vector3i(0, 0, 0))])
	assert_eq(
		mining.query_player_item(0, "iron_ore"),
		43,
		"40 in stock, plus the 3 the Miner had banked"
	)
	assert_eq(sim.query_machine_count(), 0)


func test_demolishing_a_belt_removes_the_whole_run_and_returns_its_items() -> void:
	var sim: Simulation = _sim()
	sim.step([InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(4, 0, 0))])
	assert_eq(sim.query_belt_count(), 1, "the premise of the rest")

	sim.step([InputAction.demolish(0, Vector3i(2, 0, 0))])
	assert_eq(sim.query_belt_count(), 0, "a Belt is a run, so demolishing it takes all of it")


func test_demolishing_empty_ground_is_refused_by_name() -> void:
	var sim: Simulation = _sim()
	assert_eq(
		sim.query_demolish_refusal(0, Vector3i(9, 0, 9)), Simulation.Refusal.NOTHING_THERE
	)

	var settled: Simulation = _sim()
	sim.step([InputAction.demolish(0, Vector3i(9, 0, 9))])
	settled.step([])
	assert_eq(sim.hash(), settled.hash(), "and leaves the hash exactly where it was")


func test_demolishing_something_that_is_there_is_not_refused() -> void:
	var sim: Simulation = _sim()
	sim.step([InputAction.build_machine(0, _index(sim, "free_mk1"), Vector3i(0, 0, 0))])
	assert_eq(sim.query_demolish_refusal(0, Vector3i(0, 0, 0)), Simulation.Refusal.NONE)


func test_building_and_demolishing_leaves_the_factory_where_it_started() -> void:
	# The property that makes iterating on a layout cheap: a round trip costs nothing
	# but the ticks it took. Only the tick counter and the Run's history differ, so
	# this is asserted on the Factory and the stock rather than on the hash.
	var sim: Simulation = _sim()
	var press: int = _index(sim, "press_mk1")
	for attempt: int in range(6):
		sim.step([InputAction.build_machine(0, press, Vector3i(0, 0, 0))])
		sim.step([InputAction.demolish(0, Vector3i(0, 0, 0))])
	assert_eq(sim.query_machine_count(), 0)
	assert_eq(sim.query_player_item(0, "iron_plate"), 40, "six rebuilds cost nothing net")


func test_demolishing_then_rebuilding_renumbers_nothing_a_player_can_see() -> void:
	# Machines live in parallel arrays indexed by build order, so removing one shifts
	# the indices after it. That is fine because nothing outside the Simulation holds
	# an index across a tick — but the Machines themselves must survive it.
	var sim: Simulation = _sim()
	var miner: int = _index(sim, "miner_mk1")
	sim.step([
		InputAction.build_machine(0, miner, Vector3i(0, 0, 0)),
		InputAction.build_machine(0, miner, Vector3i(4, 0, 0)),
		InputAction.build_machine(0, miner, Vector3i(8, 0, 0)),
	])
	sim.step([InputAction.demolish(0, Vector3i(4, 0, 0))])

	assert_eq(sim.query_machine_count(), 2)
	assert_eq(sim.query_machine_tile(0), Vector3i(0, 0, 0), "the first Miner is still first")
	assert_eq(sim.query_machine_tile(1), Vector3i(8, 0, 0), "and the third has moved up")
	assert_eq(sim.query_machine_at_tile(Vector3i(5, 0, 1)), -1, "the middle one is really gone")


## The Gear a Run is holding, inline so the fixture is a complete definition set. One
## weapon frame and whatever component this file's Delivery tiers name, because a tier
## naming Gear that does not exist is content somebody broke. These tests are not about
## combat, so the frame is the Pneumatic Wrench and nothing is fitted to it.
const GEAR: String = """id,display_name,kind,attack,damage,range_metres,spread_degrees,seconds_per_shot,ammunition_item,ammunition_per_shot,damage_percent,range_percent,spread_percent,interval_percent,ammunition_percent,damage_taken_percent
pneumatic_wrench,Pneumatic Wrench,weapon,melee,55,4,0,0.6,,0,0,0,0,0,0,0
placeholder_gear,Placeholder Barrel,barrel,,0,0,0,0,,0,10,0,0,0,0,0
"""


## A Stratagem table that is not what this file is about. One row, so the table is not empty —
## `Definitions` refuses an empty one, because a Silo with nothing to load is a Machine a
## player can build, feed and never use. `test_silo.gd` is where the shipped table is
## asserted, exactly as `test_delivery.gd` is where the shipped Delivery chain is.
const STRATAGEMS: String = """id,display_name,effect,paint_seconds,radius_tiles,damage_per_charge,goods_per_charge,sentry_machine,sentry_seconds
artillery_barrage,Artillery Barrage,barrage,5,6,150,,,0
"""


## The Delivery tiers, inline so the fixture is a complete definition set. Progression is
## physical (`content/deliveries.csv`), and a table with no rows in it is an error rather
## than a Run with no progression. This one unlocks a Gear component and names no Machine,
## so nothing this file builds is locked behind it — `test_delivery.gd` is where locking is
## asserted.
const DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_opening,Opening Licence,1,iron_ore:1,,placeholder_gear,
"""
# ── The Wall key and the wrench key ───────────────────────────────────────────

func test_the_wall_key_lays_one_tile_of_wall_on_the_aimed_tile() -> void:
	# A key rather than a slot on the Build Gun's Machine list, because a Wall has no row in
	# `content/machines.csv` — it is not a Machine (DESIGN.md).
	var sim: Simulation = _sim()
	var controller: PlayerController = PlayerController.new()
	var sample: PlayerController.DeviceSample = PlayerController.DeviceSample.new()
	sample.wall_clicked = true

	var actions: Array = controller.actions_for_tick(sim, 0, sample)
	var wall: InputAction = _only_of_kind(actions, InputAction.Kind.BUILD_WALL)
	if not assert_not_null(wall, "one press is one Wall"):
		return
	assert_eq(wall.wall_tile(), BuildGun.aimed_tile(sim, 0), "on the tile the gun is aimed at")

	sim.step(actions)
	assert_eq(sim.query_wall_count(), 1)


func test_the_wrench_key_is_held_rather_than_an_edge() -> void:
	# A repair is restoration over time, so the intent is sent every tick the key is down and
	# the Simulation consumes it each tick. An edge would mend for one tick and stop.
	var sim: Simulation = _sim()
	var controller: PlayerController = PlayerController.new()
	var sample: PlayerController.DeviceSample = PlayerController.DeviceSample.new()

	assert_null(
		_only_of_kind(controller.actions_for_tick(sim, 0, sample), InputAction.Kind.REPAIR),
		"nothing is sent while the key is up"
	)

	sample.repair_held = true
	var first: InputAction = _only_of_kind(
		controller.actions_for_tick(sim, 0, sample), InputAction.Kind.REPAIR
	)
	if not assert_not_null(first, "held, so it is sent"):
		return
	assert_eq(first.repair_tile(), BuildGun.aimed_tile(sim, 0))
	assert_not_null(
		_only_of_kind(controller.actions_for_tick(sim, 0, sample), InputAction.Kind.REPAIR),
		"and sent again on the next tick it is still down, without a fresh press"
	)


## The one action of a kind in a list, or null. Fails if there are two: an intent sent twice
## in one tick is an intent applied twice.
func _only_of_kind(actions: Array, kind: int) -> InputAction:
	var found: InputAction = null
	for action: InputAction in actions:
		if action.kind == kind:
			if found != null:
				fail("two %d actions in one tick" % kind)
			found = action
	return found


# ── Build mode is a hand, not a gate ─────────────────────────────────────────
# #35, from the first playtest: *"the hologram is still visible in gun mode"* and
# *"the hologram should not be placable in gun mode"*. Build mode landed in #29 and the
# hologram never heard about it.
#
# The fix cannot live in the Simulation. **Building is never gated** — nothing behind the
# façade asks whether building is permitted, and
# `test_nothing_in_the_simulation_asks_the_mode_for_permission` holds that line. What the
# mode decides is what the left mouse button *means* and what is in the player's hands,
# which is `game/`'s business from end to end. So the projection lives on `BuildGun`,
# where the aim already lives, and it is the single thing both the renderer and the
# controller consult: `BuildGun.hand_refusal` is the rule, `BuildGun.build_refusal`
# composes it with the Simulation's own, and neither caller reads the mode for itself.

func test_the_build_gun_refuses_a_placement_when_it_is_not_in_the_players_hands() -> void:
	var sim: Simulation = _sim()
	assert_eq(
		BuildGun.build_refusal(sim, 0, false, _index(sim, "press_mk1"), Vector3i(0, 0, 0), 0),
		Simulation.Refusal.BUILD_GUN_IS_HOLSTERED,
		"a player holding a rifle is not aiming a Build Gun"
	)


func test_the_build_gun_reports_the_simulations_own_refusal_when_it_is_in_hand() -> void:
	var sim: Simulation = _sim()
	var press: int = _index(sim, "press_mk1")
	assert_eq(
		BuildGun.build_refusal(sim, 0, true, press, Vector3i(0, 0, 0), 0),
		Simulation.Refusal.NONE,
		"clear ground with the gun out"
	)
	sim.step([InputAction.build_machine(0, press, Vector3i(0, 0, 0))])
	assert_eq(
		BuildGun.build_refusal(sim, 0, true, press, Vector3i(0, 0, 0), 0),
		Simulation.Refusal.OCCUPIED,
		"and the Simulation's reason, unaltered, when there is one"
	)


func test_the_hand_is_checked_before_the_ground() -> void:
	# Which reason wins when both apply. What is in your hands is the more immediate
	# fact and the one a player fixes with one key, so it is reported first — the same
	# ordering `test_the_ground_is_checked_before_the_wallet` settles further up.
	var sim: Simulation = _sim()
	var press: int = _index(sim, "press_mk1")
	sim.step([InputAction.build_machine(0, press, Vector3i(0, 0, 0))])
	assert_eq(
		BuildGun.build_refusal(sim, 0, false, press, Vector3i(0, 0, 0), 0),
		Simulation.Refusal.BUILD_GUN_IS_HOLSTERED
	)
