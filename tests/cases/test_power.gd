## The one Power grid: total supply against total demand, and the proportional
## throttle a shortfall applies — through the Simulation façade.
extends TestCase


func _run(sim: Simulation, ticks: int) -> void:
	for tick: int in range(ticks):
		sim.step([])


# ── The grid reads supply against demand ──────────────────────────────────────

func test_an_empty_factory_demands_nothing_and_runs_at_full_rate() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_eq(sim.query_power_demand_kw(), 0, "nothing is built, so nothing is drawing")
	assert_eq(sim.query_power_ratio(), Fixed.ONE, "a grid with no demand is not short")
	assert_false(sim.query_power_is_in_deficit(), "and therefore not in deficit")


# ── A Factory that has the Power it asks for ──────────────────────────────────

func test_a_factory_within_its_power_runs_at_the_rate_its_recipes_state() -> void:
	# content/tuning.toml gives the grid a 300 kW baseline and machines.csv draws 120 kW
	# for the Miner, so the opening line is inside its Power and nothing is throttled.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.build_machine(0, _machine(sim, "miner_mk1"), sim.query_node_tile(0))])
	_run(sim, 90)
	assert_eq(sim.query_power_supply_kw(), 300, "the baseline plant, and no generator yet")
	assert_eq(sim.query_power_demand_kw(), 120, "one working Miner")
	assert_eq(sim.query_power_ratio(), Fixed.ONE, "supply covers demand")
	assert_false(sim.query_machine_is_throttled(0), "so the Miner is not held back")
	assert_eq(sim.query_machine_output(0, "iron_ore"), 1, "one ore in 1.5 s, as the Recipe says")


# ── A Factory in deficit ──────────────────────────────────────────────────────
# A grid supplying 1 kW against a demand of 3 kW is the most awkward ratio there is: it
# is not representable as a terminating fraction, so it is exactly where a rounding rule
# would show. The Miner here mines in 0.1 s, which floors to 5 ticks, so at full rate an
# ore lands every 5 ticks and at a third of that every 15 — a whole number either way,
# which is the point: the throttle is a duty cycle over whole ticks, never a fraction of
# one.

const THIRD_MACHINES: String = """id,display_name,role,footprint_x,footprint_z,height_metres,power_draw_kw,power_supply_kw,health,max_depth,range_tiles,damage,repair,charge_capacity,recipe_id,build_cost
miner_mk1,Miner Mk1,miner,2,2,1.8,3,0,400,1,0,0,0,0,mine_iron_ore,
"""

const THIRD_RECIPES: String = """id,display_name,inputs,outputs,seconds
mine_iron_ore,Mine Iron Ore,,iron_ore:1,0.1
"""

const THIRD_TUNING: String = """[player]
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
starting_stock = "iron_ore:200"
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
baseline_supply_kw = 1
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


func _one_third_content() -> Definitions:
	return Definitions.parse(THIRD_MACHINES, THIRD_RECIPES, THIRD_TUNING, WAVES, DELIVERIES, GEAR, STRATAGEMS)


## The shipped Wave composition, inline so the fixture is a complete definition set. A
## Wave's contents are a table (`content/waves.csv`), and a set with no rows in it is an
## error rather than a Run that is never attacked.
const WAVES: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,6,150,40
"""


## A Factory whose single Miner asks for three times the Power the grid has.
func _one_third_sim() -> Simulation:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, _one_third_content(), layout)
	sim.step([InputAction.build_machine(0, _machine(sim, "miner_mk1"), Vector3i(0, 0, 0))])
	return sim


func test_the_content_these_tests_bring_loads_cleanly() -> void:
	assert_false(_one_third_content().has_errors(), _one_third_content().describe_errors())


func test_a_grid_supplying_a_third_of_its_demand_reports_a_third() -> void:
	var sim: Simulation = _one_third_sim()
	_run(sim, 1)
	assert_eq(sim.query_power_supply_kw(), 1)
	assert_eq(sim.query_power_demand_kw(), 3)
	assert_eq(sim.query_power_ratio(), Fixed.from_rational(1, 3), "a third, in fixed point")
	assert_true(sim.query_power_is_in_deficit())
	assert_true(sim.query_machine_is_throttled(0))


func test_a_machine_on_a_grid_supplying_a_third_runs_at_exactly_a_third_rate() -> void:
	var sim: Simulation = _one_third_sim()
	_run(sim, 14)
	assert_eq(sim.query_machine_output(0, "iron_ore"), 0, "5 ticks of work at a third rate is 15")
	_run(sim, 1)
	assert_eq(sim.query_machine_output(0, "iron_ore"), 1, "and it lands on the 15th, exactly")


func test_a_throttled_machine_does_not_drift_over_a_long_run() -> void:
	# The whole reason the throttle is a duty cycle over integers rather than a
	# fixed-point fraction added up every tick. 1800 ticks at a third is 600 ticks of
	# work, which at 5 ticks a craft is 120 ore — not 119 and not 121, however long the
	# Run goes on.
	var sim: Simulation = _one_third_sim()
	_run(sim, 1800)
	assert_eq(sim.query_machine_output(0, "iron_ore"), 120, "600 ticks of work, 120 crafts")


func test_a_throttled_machine_is_slowed_rather_than_stopped() -> void:
	var sim: Simulation = _one_third_sim()
	_run(sim, 600)
	assert_false(sim.query_machine_is_starved(0), "it has everything but Power")
	assert_true(sim.query_machine_is_throttled(0), "and it is being held back")
	assert_true(
		sim.query_machine_output(0, "iron_ore") > 0,
		"a brownout degrades the Factory; it does not halt a Machine outright"
	)


func _machine(sim: Simulation, id: String) -> int:
	return sim.query_definitions().machine_index(id)


# ── The Steam Boiler ──────────────────────────────────────────────────────────
# The shipped Map puts coal at (12, 0, 4). A 2x2 Coal Miner anchored on it covers tiles
# x 12..13 by z 4..5, so a two-tile Belt whose run starts at (14, 0, 4) loads from that
# footprint's edge and hands off into a 3x2 Steam Boiler anchored at (16, 0, 4).
#
# machines.csv draws 120 kW for the Coal Miner and supplies 600 kW from the Boiler, and
# tuning.toml gives the grid a 300 kW baseline, so a burning Boiler takes the grid from
# 300 kW to 900 kW against a 120 kW demand.

const COAL_MINER_TILE: Vector3i = Vector3i(12, 0, 4)
const FUEL_BELT_ENTRY: Vector3i = Vector3i(14, 0, 4)
const FUEL_BELT_EXIT: Vector3i = Vector3i(15, 0, 4)
const BOILER_TILE: Vector3i = Vector3i(16, 0, 4)


## A Coal Miner on the Map's coal, a one-tile fuel Belt, and a Steam Boiler at the end
## of it. The whole Power chain, and the Factory's first logistics problem.
func _fuelled_boiler_sim() -> Simulation:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([
		InputAction.build_machine(0, _machine(sim, "coal_miner_mk1"), COAL_MINER_TILE),
		InputAction.build_belt(0, FUEL_BELT_ENTRY, FUEL_BELT_EXIT),
		InputAction.build_machine(0, _machine(sim, "steam_boiler_mk1"), BOILER_TILE),
	])
	return sim


func test_the_map_offers_coal_for_the_boiler_to_burn() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_eq(sim.query_node_at_tile(COAL_MINER_TILE), 2, "the Map's third Node is the coal")
	assert_eq(sim.query_node_resource(2), "coal")


func test_a_boiler_with_no_fuel_supplies_nothing_and_reads_as_starved() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.build_machine(0, _machine(sim, "steam_boiler_mk1"), BOILER_TILE)])
	_run(sim, 60)
	assert_eq(sim.query_power_supply_kw(), 300, "an unlit Boiler adds nothing to the grid")
	assert_true(sim.query_machine_is_starved(0), "it is waiting on a Belt, like any crafter")
	assert_false(sim.query_machine_is_throttled(0), "and it draws nothing, so nothing throttles it")


func test_a_boiler_supplies_power_from_the_tick_its_first_coal_is_delivered() -> void:
	# recipes.csv mines coal in 1.5 s, so the first lump lands in the Coal Miner on tick 90
	# and the Belt collects it on tick 91 — a tick runs its Belts before its Machines. The
	# Belt is two tiles, which at 4 Items a tile and 15 ticks an Item is 120 sub-units, and
	# an Item can get to 105 of them before it is at the far end: tick 196. The hand-off is
	# the next tick's first act, so the Boiler is burning on tick 197, and the grid is read
	# after the Belts have run, so the gauge shows it on that same tick.
	var sim: Simulation = _fuelled_boiler_sim()
	_run(sim, 195)
	assert_eq(sim.query_power_supply_kw(), 300, "the coal is still on the Belt")
	_run(sim, 1)
	assert_eq(sim.query_power_supply_kw(), 300, "and still has one tick to go")
	_run(sim, 1)
	assert_eq(sim.query_tick(), 198, "197 ticks of Run, and the tick counter has moved past it")
	assert_eq(sim.query_power_supply_kw(), 900, "the baseline plus a burning Boiler")
	assert_eq(sim.query_power_demand_kw(), 120, "against one working Coal Miner")
	assert_eq(sim.query_power_ratio(), Fixed.ONE, "comfortably in surplus")


func test_a_boiler_burns_one_lump_of_coal_per_burn_and_produces_no_item() -> void:
	# The Boiler is Machine 1: a Belt is not a Machine (GLOSSARY.md) and takes no index.
	var sim: Simulation = _fuelled_boiler_sim()
	_run(sim, 400)
	assert_eq(sim.query_machine_id(1), "steam_boiler_mk1")
	assert_eq(sim.query_machine_output_total(1), 0, "Power is not an Item, so nothing comes out")
	assert_true(
		sim.query_machine_input(1, "coal") > 0,
		"and it is holding fuel, which is what a Belt delivered"
	)
	assert_eq(sim.query_power_supply_kw(), 900, "so the grid stays up")


func test_a_boiler_is_not_throttled_by_the_brownout_it_is_there_to_end() -> void:
	# A generator that slowed down in a deficit could never lift one, so Power never
	# throttles a Machine that draws none.
	var sim: Simulation = _fuelled_boiler_sim()
	sim.step([InputAction.build_machine(0, _machine(sim, "smelter_mk1"), Vector3i(-20, 0, -20))])
	_run(sim, 400)
	assert_eq(sim.query_machine_id(1), "steam_boiler_mk1")
	assert_false(sim.query_machine_is_throttled(1), "the Boiler is never held back")
	assert_eq(sim.query_power_supply_kw(), 900, "and keeps supplying while it has coal")


# ── Cutting the fuel line ─────────────────────────────────────────────────────
# The failure mode that makes Steam Steam (GLOSSARY.md): the Boiler's fuel arrives by
# Belt, so the fuel line is a thing that can be cut, and cutting it takes the whole
# Factory down a notch rather than killing one Machine.
#
# It is cut here with a single Belt. A second Belt laid against the Coal Miner's northern
# edge loads from the same output port as the fuel line, and the Belts are advanced in
# canonical tile order — by the tile a run starts at, which is geography and not build
# order — so the Belt starting at (12, 0, 3) is served before the one starting at
# (14, 0, 4). The Coal Miner only ever holds one lump at a time, so the diverted Belt
# takes every one of them and the Boiler never sees another.

const DIVERSION_ENTRY: Vector3i = Vector3i(12, 0, 3)
const DIVERSION_EXIT: Vector3i = Vector3i(12, 0, 0)

## The Map's two iron Nodes, which two more Miners stand on to give the brownout something
## to be visible in. Three Miners at 120 kW is 360 kW against a 300 kW baseline, so losing
## the Boiler is the difference between surplus and five-sixths of what the Factory asked
## for.
const IRON_MINER_A_TILE: Vector3i = Vector3i(4, 0, 4)
const IRON_MINER_B_TILE: Vector3i = Vector3i(-6, 0, 10)


func _factory_on_a_boiler() -> Simulation:
	var sim: Simulation = _fuelled_boiler_sim()
	sim.step([
		InputAction.build_machine(0, _machine(sim, "miner_mk1"), IRON_MINER_A_TILE),
		InputAction.build_machine(0, _machine(sim, "miner_mk1"), IRON_MINER_B_TILE),
	])
	return sim


func test_a_factory_on_a_burning_boiler_has_all_the_power_it_asks_for() -> void:
	var sim: Simulation = _factory_on_a_boiler()
	_run(sim, 400)
	assert_eq(sim.query_power_supply_kw(), 900, "baseline plus Boiler")
	assert_eq(sim.query_power_demand_kw(), 360, "three Miners at 120 kW")
	assert_eq(sim.query_power_ratio(), Fixed.ONE)
	assert_false(sim.query_power_is_in_deficit())


func test_cutting_the_fuel_line_browns_out_the_whole_factory_rather_than_one_machine() -> void:
	var sim: Simulation = _factory_on_a_boiler()
	_run(sim, 400)
	var ore_before: int = sim.query_machine_output(2, "iron_ore")

	sim.step([InputAction.build_belt(0, DIVERSION_ENTRY, DIVERSION_EXIT)])
	# Long enough for the Boiler to burn the two lumps it was holding and for the
	# diverted Belt to take every lump since.
	_run(sim, 600)

	assert_eq(sim.query_power_supply_kw(), 300, "the Boiler has gone out")
	assert_eq(sim.query_power_demand_kw(), 360, "and the Factory still wants 360 kW")
	assert_eq(sim.query_power_ratio(), Fixed.from_rational(300, 360), "five sixths of it")
	assert_true(sim.query_power_is_in_deficit())
	for index: int in [0, 2, 3]:
		assert_true(
			sim.query_machine_is_throttled(index),
			"Machine %d must sag with the rest of them, not be singled out" % index
		)
	assert_true(
		sim.query_machine_output(2, "iron_ore") > ore_before,
		"and every one of them is slowed rather than stopped"
	)


func test_a_cut_fuel_line_slows_the_very_miner_that_feeds_it() -> void:
	# The Coal Miner draws from the grid the Boiler supplies, so a cut fuel line is a
	# brownout that makes the fuel harder to get. The Factory sags; it does not deadlock,
	# because the baseline plant is always there.
	var sim: Simulation = _factory_on_a_boiler()
	_run(sim, 400)
	sim.step([InputAction.build_belt(0, DIVERSION_ENTRY, DIVERSION_EXIT)])
	_run(sim, 600)
	assert_true(sim.query_machine_is_throttled(0), "the Coal Miner is on the same grid")
	assert_false(sim.query_machine_is_starved(0), "it is short of Power, not of ground")
	var mined: int = sim.query_item_total("coal")
	_run(sim, 600)
	assert_true(sim.query_item_total("coal") > mined, "and it is still mining, slowly")


# ── What a brownout looks like on a Belt ──────────────────────────────────────
# The emergent behaviour that makes the system legible without a single gauge: throttle a
# Miner and the Belt running out of it visibly thins, because there is less on it.
#
# These bring their own content. A Miner mining in 0.25 s — exactly 15 ticks — matches the
# Belt's rated 4 Items a second, so at full Power the Belt carries one Item every 15 ticks
# and the only thing that can thin it is Power. The two Factories below are identical
# except for one number in tuning: a 3 kW baseline against a 3 kW draw is a grid in
# balance, and a 1 kW baseline against the same draw is a grid supplying a third.

const THIN_MACHINES: String = """id,display_name,role,footprint_x,footprint_z,height_metres,power_draw_kw,power_supply_kw,health,max_depth,range_tiles,damage,repair,charge_capacity,recipe_id,build_cost
miner_mk1,Miner Mk1,miner,2,2,1.8,3,0,400,1,0,0,0,0,mine_iron_ore,
"""

const THIN_RECIPES: String = """id,display_name,inputs,outputs,seconds
mine_iron_ore,Mine Iron Ore,,iron_ore:1,0.25
"""


func _thinning_content(baseline_kw: int) -> Definitions:
	return Definitions.parse(
		THIN_MACHINES,
		THIN_RECIPES,
		"""[player]
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
starting_stock = "iron_ore:200"
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
baseline_supply_kw = %d
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
""" % baseline_kw,
		WAVES,
		DELIVERIES,
		GEAR
	,
		STRATAGEMS)


## A Miner at the origin running onto a ten-tile Belt, on a grid of the given baseline.
func _thinning_sim(baseline_kw: int) -> Simulation:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, _thinning_content(baseline_kw), layout)
	sim.step([
		InputAction.build_machine(0, _machine(sim, "miner_mk1"), Vector3i(0, 0, 0)),
		InputAction.build_belt(0, Vector3i(2, 0, 0), Vector3i(11, 0, 0)),
	])
	return sim


func test_the_content_the_thinning_tests_bring_loads_cleanly() -> void:
	assert_false(_thinning_content(3).has_errors(), _thinning_content(3).describe_errors())
	assert_false(_thinning_content(1).has_errors(), _thinning_content(1).describe_errors())


func test_a_throttled_miner_visibly_thins_the_items_on_its_belt() -> void:
	# At full Power the Miner pays out every 15 ticks and the Belt collects each one the
	# tick after, so Items enter at ticks 16, 31, 46 … and by tick 450 there are 29 of
	# them. Throttled to a third, a 15-tick craft takes 45 ticks: Items enter at 46, 91,
	# 136 … and there are 9. A third of the Power, a third of the Items, and nothing about
	# the Belt itself has changed.
	var full: Simulation = _thinning_sim(3)
	var short: Simulation = _thinning_sim(1)
	_run(full, 450)
	_run(short, 450)

	assert_eq(full.query_power_ratio(), Fixed.ONE, "the first grid is in balance")
	assert_eq(short.query_power_ratio(), Fixed.from_rational(1, 3), "the second supplies a third")
	assert_eq(full.query_belt_item_count(0), 29, "a Belt at the Factory's full rate")
	assert_eq(short.query_belt_item_count(0), 9, "and the same Belt in a brownout")
	assert_false(full.query_belt_is_full(0), "neither Belt is backed up")
	assert_false(short.query_belt_is_full(0), "so what thinned it was Power")


# ── Determinism ───────────────────────────────────────────────────────────────

func test_the_grids_baseline_reaches_the_hash() -> void:
	# The baseline is a tuning value, and a Run on a different grid is in a different
	# state before it has taken a single tick — which is what stops a replay recorded on
	# one grid from passing on another.
	var strong: Simulation = Simulation.new(1, 1, _thinning_content(3))
	var weak: Simulation = Simulation.new(1, 1, _thinning_content(1))
	assert_ne(strong.hash(), weak.hash(), "the grid a Factory runs on is part of its state")


func test_a_brownout_puts_a_factory_in_a_different_state_than_a_surplus() -> void:
	var full: Simulation = _thinning_sim(3)
	var short: Simulation = _thinning_sim(1)
	_run(full, 450)
	_run(short, 450)
	assert_eq(full.query_tick(), short.query_tick(), "the two Runs are on the same tick")
	assert_ne(full.hash(), short.hash(), "and a throttled Factory is not the same Factory")


func test_determinism_a_factory_in_surplus_replays_identically() -> void:
	# The first of the three fixtures: a Coal Miner, a fuel Belt, a burning Steam Boiler
	# and two more Miners, all inside the Power the grid has. No `Definitions` is passed,
	# so the replay re-reads content/ and a content change is reported as a
	# definitions_mismatch rather than passing unnoticed.
	var sim: Simulation = Simulation.new(17, 1)
	var script: InputScript = InputScript.new()
	script.add_tick([
		InputAction.build_machine(0, _machine(sim, "coal_miner_mk1"), COAL_MINER_TILE),
		InputAction.build_belt(0, FUEL_BELT_ENTRY, FUEL_BELT_EXIT),
		InputAction.build_machine(0, _machine(sim, "steam_boiler_mk1"), BOILER_TILE),
		InputAction.build_machine(0, _machine(sim, "miner_mk1"), IRON_MINER_A_TILE),
		InputAction.build_machine(0, _machine(sim, "miner_mk1"), IRON_MINER_B_TILE),
	])
	script.add_idle_ticks(600)

	var recording: ReplayRecording = DeterminismHarness.record(script, 17, 1)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_a_factory_in_deficit_replays_identically() -> void:
	# The second fixture: three Miners at 120 kW on a 300 kW baseline and no Boiler at all,
	# so every tick of it runs the duty cycle that makes a proportional throttle exact.
	var sim: Simulation = Simulation.new(19, 1)
	var script: InputScript = InputScript.new()
	script.add_tick([
		InputAction.build_machine(0, _machine(sim, "coal_miner_mk1"), COAL_MINER_TILE),
		InputAction.build_machine(0, _machine(sim, "miner_mk1"), IRON_MINER_A_TILE),
		InputAction.build_machine(0, _machine(sim, "miner_mk1"), IRON_MINER_B_TILE),
	])
	script.add_idle_ticks(600)

	var recording: ReplayRecording = DeterminismHarness.record(script, 19, 1)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_a_factory_losing_its_fuel_line_replays_identically() -> void:
	# The third fixture, and the interesting one. It crosses the line in both directions:
	# 360 kW of Miners on a 300 kW baseline start it short, the Boiler lights on tick 197
	# and lifts it into surplus, and a Belt laid on tick 401 diverts the coal so the Boiler
	# goes out and the Factory falls back into deficit. Recorded across both crossings, so
	# a divergence on the tick the grid changed its mind is caught rather than settled back
	# into.
	var recording: ReplayRecording = DeterminismHarness.record(_fuel_cut_script(), 23, 1)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_the_factory_losing_its_fuel_really_did_cross_into_deficit() -> void:
	# A fixture that replays a Factory doing nothing interesting proves nothing, so this
	# walks the same script and insists the surplus, the crossing and the deficit all
	# happened inside the window it covers.
	var sim: Simulation = Simulation.new(23, 1)
	var script: InputScript = _fuel_cut_script()
	var surplus_ticks: int = 0
	var deficit_ticks: int = 0
	for tick: int in range(script.tick_count()):
		sim.step(script.actions_at(tick))
		if sim.query_power_is_in_deficit():
			deficit_ticks += 1
		else:
			surplus_ticks += 1
	assert_eq(sim.query_machine_count(), 4, "four Machines; a Belt is not one of them")
	assert_true(surplus_ticks > 100, "the Factory spent %d ticks in surplus" % surplus_ticks)
	assert_true(deficit_ticks > 100, "and %d ticks short of Power" % deficit_ticks)
	assert_eq(sim.query_power_supply_kw(), 300, "ending on the baseline alone")
	assert_true(sim.query_power_is_in_deficit(), "and ending short of what it asked for")


## The script both fuel-cut tests run: build the whole Power chain, let it reach surplus,
## then divert the coal and keep going well past the Boiler going out.
func _fuel_cut_script() -> InputScript:
	var sim: Simulation = Simulation.new(23, 1)
	var script: InputScript = InputScript.new()
	script.add_tick([
		InputAction.build_machine(0, _machine(sim, "coal_miner_mk1"), COAL_MINER_TILE),
		InputAction.build_belt(0, FUEL_BELT_ENTRY, FUEL_BELT_EXIT),
		InputAction.build_machine(0, _machine(sim, "steam_boiler_mk1"), BOILER_TILE),
		InputAction.build_machine(0, _machine(sim, "miner_mk1"), IRON_MINER_A_TILE),
		InputAction.build_machine(0, _machine(sim, "miner_mk1"), IRON_MINER_B_TILE),
	])
	script.add_idle_ticks(400)
	script.add_tick([InputAction.build_belt(0, DIVERSION_ENTRY, DIVERSION_EXIT)])
	script.add_idle_ticks(700)
	return script


# ── The edge of the model ─────────────────────────────────────────────────────

func test_a_grid_with_no_supply_at_all_leaves_the_factory_standing_still() -> void:
	# The honest boundary of "a shortfall throttles rather than stops": throttling is
	# proportional, and nothing times zero is nothing. A Factory on a dead grid does stop,
	# which is exactly why the shipped grid has a baseline plant — see the test below.
	var sim: Simulation = _thinning_sim(0)
	_run(sim, 600)
	assert_eq(sim.query_power_supply_kw(), 0, "a grid with no baseline and no generator")
	assert_eq(sim.query_power_ratio(), 0, "supplies none of what is asked of it")
	assert_eq(sim.query_machine_output(0, "iron_ore"), 0, "so nothing turns")
	assert_true(sim.query_machine_is_throttled(0), "and the Machine says why")


func test_the_baseline_plant_is_what_lets_a_factory_start_at_all() -> void:
	# The bootstrap: a Steam Boiler burns Belt-delivered coal, mining coal needs a Miner,
	# and a Miner needs Power. Without a baseline the Factory could never turn the first
	# wheel, so the Nest brings its own small plant and the Coal Miner runs on that.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.build_machine(0, _machine(sim, "coal_miner_mk1"), COAL_MINER_TILE)])
	_run(sim, 90)
	assert_eq(sim.query_power_supply_kw(), 300, "the Nest's own plant, with no generator built")
	assert_false(sim.query_power_is_in_deficit(), "which covers one Miner")
	assert_eq(sim.query_machine_output(0, "coal"), 1, "so the first coal can be mined")


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
## so nothing this file builds is locked behind it.
const DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_opening,Opening Licence,1,iron_ore:1,,placeholder_gear,
"""
