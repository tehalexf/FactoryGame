## Belts, the Items on them, and back-pressure — through the Simulation façade.
extends TestCase


func _miner_index(sim: Simulation) -> int:
	return sim.query_definitions().machine_index("miner_mk1")


func _smelter_index(sim: Simulation) -> int:
	return sim.query_definitions().machine_index("smelter_mk1")


func _run(sim: Simulation, ticks: int) -> void:
	for tick: int in range(ticks):
		sim.step([])


## A Run on a Map with one iron ore Node at the origin, so that every tile a test names
## is a small number and every expected metre can be worked by hand. The starter Map's
## Nodes sit at awkward coordinates on purpose; a test about Belt arithmetic should not
## also be a test about where the Map put its ore.
func _sim_on_one_node() -> Simulation:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	return Simulation.new(1, 1, null, layout)


# ── Laying a Belt ─────────────────────────────────────────────────────────────

func test_a_belt_can_be_laid_along_a_straight_run_of_tiles() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_eq(sim.query_belt_count(), 0, "a Run starts with no Belts")
	sim.step([InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(3, 0, 0))])
	assert_eq(sim.query_belt_count(), 1)
	assert_eq(sim.query_belt_length_tiles(0), 4, "tiles 0 to 3 inclusive is four tiles")
	assert_eq(sim.query_belt_tile(0, 0), Vector3i(0, 0, 0), "the run starts where it was aimed")
	assert_eq(sim.query_belt_tile(0, 3), Vector3i(3, 0, 0), "and ends where it was aimed")


func test_a_belt_occupies_every_tile_of_its_run() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(0, 0, 2))])
	for step: int in range(3):
		assert_eq(sim.query_belt_at_tile(Vector3i(0, 0, step)), 0, "tile %d is Belt" % step)
	assert_eq(sim.query_belt_at_tile(Vector3i(0, 0, 3)), -1, "the run stops where it stops")


func test_a_belt_that_is_not_axis_aligned_is_refused() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(2, 0, 2))])
	assert_eq(sim.query_belt_count(), 0, "there is no diagonal Belt on a 2 m grid")


func test_a_belt_off_the_map_or_off_the_ground_layer_is_refused() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var outside: int = sim.query_grid_half_extent_tiles() + 1
	sim.step([InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(outside, 0, 0))])
	sim.step([InputAction.build_belt(0, Vector3i(0, 1, 0), Vector3i(3, 1, 0))])
	assert_eq(sim.query_belt_count(), 0, "only layer 0, and only inside the Map")


func test_a_belt_cannot_be_laid_through_a_machine_or_another_belt() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.build_machine(0, _miner_index(sim), Vector3i(0, 0, 0))])
	sim.step([InputAction.build_belt(0, Vector3i(-2, 0, 0), Vector3i(2, 0, 0))])
	assert_eq(sim.query_belt_count(), 0, "the 2x2 Miner is in the way")
	sim.step([InputAction.build_belt(0, Vector3i(-4, 0, 0), Vector3i(-2, 0, 0))])
	assert_eq(sim.query_belt_count(), 1)
	sim.step([InputAction.build_belt(0, Vector3i(-3, 0, -2), Vector3i(-3, 0, 2))])
	assert_eq(sim.query_belt_count(), 1, "two Belts cannot share a tile")


func test_a_machine_cannot_be_built_on_top_of_a_belt() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(3, 0, 0))])
	sim.step([InputAction.build_machine(0, _miner_index(sim), Vector3i(1, 0, 0))])
	assert_eq(sim.query_machine_count(), 0, "a Belt occupies its tiles against everything")
	assert_eq(sim.query_belt_count(), 1)


func test_a_belt_starts_empty() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(3, 0, 0))])
	_run(sim, 60)
	assert_eq(sim.query_belt_item_count(0), 0, "a Belt with nothing feeding it carries nothing")


# ── A Belt's rating ───────────────────────────────────────────────────────────
# content/tuning.toml rates a Belt at 4 Items a second and 4 Items a tile. The
# Simulation runs at 60 ticks a second, so an Item crosses one Item's worth of Belt
# every 15 ticks, and a 2 m tile holds 4 Items 0.5 m apart — which is 2 m/s. Every
# expected number below is worked from those two tuning values and nothing else.

const TICKS_PER_ITEM: int = 15
const ITEMS_PER_TILE: int = 4
const TICKS_PER_ORE: int = 90


func test_a_belt_is_rated_by_tuning_rather_than_by_code() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_eq(sim.query_belt_ticks_per_item(), TICKS_PER_ITEM, "4 Items a second at 60 ticks")
	assert_eq(sim.query_belt_items_per_tile(), ITEMS_PER_TILE)


func test_a_belts_capacity_is_its_length_times_its_density() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(3, 0, 0))])
	assert_eq(sim.query_belt_capacity(0), 4 * ITEMS_PER_TILE, "four tiles, four Items each")


# ── Taking from a Machine's output port ───────────────────────────────────────
# The Miner's footprint is 2x2 anchored on the Node at the origin, so it covers tiles
# x 0..1 by z 0..1. A Belt whose run starts at (2, 0, 0) runs straight out of the
# footprint edge at (1, 0, 0): that edge is the output port, and nothing sits between
# the two — no inserter entity exists (DESIGN.md).
#
# recipes.csv gives mine_iron_ore 1.5 s, so ore lands on ticks 90, 180, 270 … and the
# Belt collects each one on the tick after it lands, because a tick runs its Belts
# before its Machines.
#
# The Belt's entry edge is therefore at x = 2 tiles * 2 m = 4 m, and the centre of its
# run is at z = 1 m.

func _miner_and_belt(sim: Simulation, belt_tiles: int) -> void:
	sim.step([
		InputAction.build_machine(0, _miner_index(sim), Vector3i(0, 0, 0)),
		InputAction.build_belt(0, Vector3i(2, 0, 0), Vector3i(1 + belt_tiles, 0, 0)),
	])


func test_a_belt_takes_items_from_the_machine_output_port_it_runs_out_of() -> void:
	var sim: Simulation = _sim_on_one_node()
	_miner_and_belt(sim, 4)
	_run(sim, TICKS_PER_ORE)
	assert_eq(sim.query_machine_output(0, "iron_ore"), 1, "the craft has paid out")
	assert_eq(sim.query_belt_item_count(0), 0, "and has not been collected yet")
	_run(sim, 1)
	assert_eq(sim.query_machine_output(0, "iron_ore"), 0, "the Belt drained the port")
	assert_eq(sim.query_belt_item_count(0), 1)
	assert_eq(sim.query_belt_item_id(0, 0), "iron_ore")


func test_a_belt_one_tile_short_of_a_port_is_fed_by_nothing() -> void:
	var sim: Simulation = _sim_on_one_node()
	sim.step([
		InputAction.build_machine(0, _miner_index(sim), Vector3i(0, 0, 0)),
		InputAction.build_belt(0, Vector3i(3, 0, 0), Vector3i(6, 0, 0)),
	])
	_run(sim, TICKS_PER_ORE * 3)
	assert_eq(sim.query_belt_item_count(0), 0, "a Belt that does not touch the port gets nothing")
	assert_eq(sim.query_machine_output(0, "iron_ore"), 3, "the ore stayed in the Miner")


# ── Where an Item is ──────────────────────────────────────────────────────────

func test_an_item_enters_a_belt_at_the_end_it_was_fed_from() -> void:
	var sim: Simulation = _sim_on_one_node()
	_miner_and_belt(sim, 4)
	_run(sim, TICKS_PER_ORE + 1)
	# An Item occupies half a metre of Belt, so the first one on sits with its centre
	# 0.25 m past the entry edge at 4 m.
	var where: FixedVec2 = sim.query_belt_item_position_metres(0, 0)
	assert_eq(where.x, Fixed.from_rational(17, 4), "4.25 m along x")
	assert_eq(where.z, Fixed.from_int(1), "the centre of the Belt's tile")


func test_an_item_travels_at_the_speed_its_rating_implies() -> void:
	var sim: Simulation = _sim_on_one_node()
	_miner_and_belt(sim, 4)
	_run(sim, TICKS_PER_ORE + 1)
	var entered: FixedVec2 = sim.query_belt_item_position_metres(0, 0)
	# 4 Items a second, 0.5 m apart, is 2 m/s — so 30 ticks carries an Item 1 m.
	_run(sim, 30)
	var later: FixedVec2 = sim.query_belt_item_position_metres(0, 0)
	assert_eq(later.x - entered.x, Fixed.from_int(1), "half a second at 2 m/s is 1 m")
	assert_eq(later.z, entered.z, "a Belt does not wander off its run")


func test_a_belt_leading_nowhere_holds_its_items_at_the_far_end() -> void:
	var sim: Simulation = _sim_on_one_node()
	_miner_and_belt(sim, 2)
	# A 2-tile run is 8 Items long: 105 sub-units from the first Item's position to the
	# last's, which at one sub-unit a tick is 105 ticks.
	_run(sim, TICKS_PER_ORE + 1 + 105)
	assert_eq(
		sim.query_belt_item_position_metres(0, 0).x,
		Fixed.from_rational(31, 4),
		"4 m + 3.75 m: a quarter of a metre short of the 8 m end"
	)
	assert_eq(sim.query_belt_item_count(0), 2, "the second ore is aboard too")
	assert_eq(
		sim.query_belt_item_position_metres(0, 1).x,
		Fixed.from_rational(19, 4),
		"and 15 ticks behind, which is 0.5 m"
	)

	_run(sim, 60)
	assert_eq(
		sim.query_belt_item_position_metres(0, 0).x,
		Fixed.from_rational(31, 4),
		"a Belt leading nowhere holds its Items rather than dropping them off the end"
	)
	assert_eq(
		sim.query_belt_item_position_metres(0, 1).x,
		Fixed.from_rational(27, 4),
		"and the one behind keeps closing on it"
	)


# ── Feeding a Smelter ─────────────────────────────────────────────────────────
# The whole line: a Miner on the Node at the origin, a 4-tile Belt out of its port, and
# a Smelter whose 3x3 footprint is anchored at (6, 0, 0) so its edge tile is the one the
# Belt's far end points at.
#
# recipes.csv gives smelt_iron_plate 2 iron ore in, 1 iron plate out, 3.2 s a craft.
# 3.2 s is 191 ticks, not 192: a decimal crosses into fixed point by flooring, like
# every other lossy operation in the Simulation, and 3.2 has no exact binary
# representation. The Recipe's duration is what the file says it is, to the Simulation's
# precision.
#
# Ore k leaves the Miner on tick 90k, is collected on 90k + 1, takes 225 ticks to cross
# the Belt, and is handed to the Smelter on 90k + 227. So the Smelter has its two ore on
# tick 407 and finishes its first plate 191 ticks later, on tick 597.

const SMELTER_TICKS_PER_CRAFT: int = 191


func _mining_line(sim: Simulation) -> void:
	sim.step([
		InputAction.build_machine(0, _miner_index(sim), Vector3i(0, 0, 0)),
		InputAction.build_belt(0, Vector3i(2, 0, 0), Vector3i(5, 0, 0)),
		InputAction.build_machine(0, _smelter_index(sim), Vector3i(6, 0, 0)),
	])


func test_a_belt_delivers_into_the_machine_input_port_it_runs_into() -> void:
	var sim: Simulation = _sim_on_one_node()
	_mining_line(sim)
	assert_eq(sim.query_machine_id(1), "smelter_mk1", "the Smelter is the second Machine built")
	_run(sim, 316)
	assert_eq(sim.query_machine_input(1, "iron_ore"), 0, "the first ore is still on the Belt")
	_run(sim, 1)
	assert_eq(sim.query_machine_input(1, "iron_ore"), 1, "and now it is in the Smelter")
	assert_eq(sim.query_belt_item_count(0), 2, "with two more behind it on the Belt")


func test_a_smelter_consumes_ore_and_produces_ingots_per_its_recipe() -> void:
	var sim: Simulation = _sim_on_one_node()
	_mining_line(sim)
	_run(sim, 596)
	assert_eq(sim.query_machine_output(1, "iron_plate"), 0, "one tick short of the first plate")
	_run(sim, 1)
	assert_eq(sim.query_machine_output(1, "iron_plate"), 1, "2 ore in, 1 plate out")
	assert_eq(
		sim.query_machine_input(1, "iron_ore"),
		2,
		"four ore had arrived by tick 597 and the craft ate two of them"
	)


func test_a_smelter_does_not_start_a_craft_until_it_holds_a_whole_recipe() -> void:
	var sim: Simulation = _sim_on_one_node()
	_mining_line(sim)
	# The first ore lands on tick 317 and the second on 407. A Smelter holding one of the
	# two it needs is starved and banks no progress at all — if it banked time while
	# waiting, its first plate would appear on tick 317 + 191 = 508 instead of 597.
	_run(sim, 508)
	assert_eq(sim.query_machine_input(1, "iron_ore"), 3, "three ore have arrived by now")
	assert_eq(sim.query_machine_output(1, "iron_plate"), 0, "a starved Smelter banks no time")


# ── Reporting starvation ──────────────────────────────────────────────────────

func test_a_machine_starved_of_an_input_produces_nothing_and_says_so() -> void:
	var sim: Simulation = _sim_on_one_node()
	sim.step([InputAction.build_machine(0, _smelter_index(sim), Vector3i(6, 0, 0))])
	_run(sim, SMELTER_TICKS_PER_CRAFT * 3)
	assert_true(sim.query_machine_is_starved(0), "a Smelter with no Belt is starved")
	assert_eq(sim.query_machine_output_total(0), 0, "and has made nothing")


func test_a_miner_over_no_node_reports_as_starved_too() -> void:
	var sim: Simulation = _sim_on_one_node()
	sim.step([InputAction.build_machine(0, _miner_index(sim), Vector3i(20, 0, 20))])
	_run(sim, TICKS_PER_ORE)
	assert_true(sim.query_machine_is_starved(0), "a Miner's input is the ground under it")
	assert_eq(sim.query_machine_output_total(0), 0)


func test_a_machine_holding_its_inputs_is_not_starved() -> void:
	var sim: Simulation = _sim_on_one_node()
	_mining_line(sim)
	assert_true(sim.query_machine_is_starved(1), "the Smelter starts with nothing")
	_run(sim, 407)
	assert_eq(sim.query_machine_input(1, "iron_ore"), 2)
	assert_false(sim.query_machine_is_starved(1), "two ore is a whole Recipe")
	assert_false(sim.query_machine_is_starved(0), "the Miner is sitting on its Node")


# ── Saturation and back-pressure ──────────────────────────────────────────────
# The shipped Miner produces one ore every 90 ticks, which no Belt could ever struggle
# with. Saturating a Belt needs a producer faster than the Belt's 4 Items a second, so
# these tests bring their own content: a Miner whose Recipe takes 0.1 s, which floors to
# 5 ticks and so offers 12 ore a second to a Belt rated for 4.

const FAST_MACHINES: String = """id,display_name,role,footprint_x,footprint_z,power_draw_kw,power_supply_kw,health,max_depth,range_tiles,damage,repair,recipe_id,build_cost
miner_mk1,Miner Mk1,miner,2,2,120,0,400,1,0,0,0,mine_iron_ore,
smelter_mk1,Smelter Mk1,crafter,3,3,180,0,500,0,0,0,0,smelt_iron_plate,
"""

const FAST_RECIPES: String = """id,display_name,inputs,outputs,seconds
mine_iron_ore,Mine Iron Ore,,iron_ore:1,0.1
smelt_iron_plate,Smelt Iron Plate,iron_ore:2,iron_plate:1,3.2
"""

const FAST_TUNING: String = """[player]
walk_speed_metres_per_second = 4
sprint_speed_multiplier = 1.8
walk_acceleration_metres_per_second_squared = 24
look_sensitivity_turns_per_1000_pixels = 0.4
eye_height_metres = 1.7
starting_stock = "iron_ore:200;iron_plate:200"
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
[enemy]
crawler_health = 30
crawler_speed_metres_per_second = 3
crawler_damage = 10
crawler_attack_interval_seconds = 1
breaker_health = 240
breaker_speed_metres_per_second = 2
breaker_damage = 60
breaker_attack_interval_seconds = 1
[wall]
health = 240
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


func _fast_content() -> Definitions:
	return Definitions.parse(FAST_MACHINES, FAST_RECIPES, FAST_TUNING, WAVES, DELIVERIES)


## A Run whose Miner outruns its Belt, on a Map with one Node at the origin.
func _saturating_sim() -> Simulation:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	var content: Definitions = _fast_content()
	return Simulation.new(1, 1, content, layout)


func test_the_content_these_tests_bring_loads_cleanly() -> void:
	var content: Definitions = _fast_content()
	assert_false(content.has_errors(), content.describe_errors())


func test_a_belt_accepts_items_at_exactly_its_rated_throughput() -> void:
	var sim: Simulation = _saturating_sim()
	sim.step([
		InputAction.build_machine(0, _miner_index(sim), Vector3i(0, 0, 0)),
		InputAction.build_belt(0, Vector3i(2, 0, 0), Vector3i(11, 0, 0)),
	])
	# 4 Items a second at 60 ticks a second is one Item every 15 ticks, and nothing about
	# the Miner's own 5-tick rate can make the Belt take them faster. The first ore lands
	# on tick 5 and is collected on tick 6, so the tenth is collected on tick 141.
	_run(sim, 141)
	assert_eq(sim.query_belt_item_count(0), 10, "ten Items in 135 ticks is 4 a second")
	_run(sim, TICKS_PER_ITEM - 1)
	assert_eq(sim.query_belt_item_count(0), 10, "and not one early")
	_run(sim, 1)
	assert_eq(sim.query_belt_item_count(0), 11, "the cadence is exact, not approximate")
	assert_true(
		sim.query_machine_output(0, "iron_ore") > 0,
		"the surplus the Belt could not take is still in the Miner"
	)


func test_a_saturated_belt_carries_its_items_exactly_one_spacing_apart() -> void:
	var sim: Simulation = _saturating_sim()
	sim.step([
		InputAction.build_machine(0, _miner_index(sim), Vector3i(0, 0, 0)),
		InputAction.build_belt(0, Vector3i(2, 0, 0), Vector3i(11, 0, 0)),
	])
	_run(sim, 141)
	var half_metre: int = Fixed.from_rational(1, 2)
	for slot: int in range(sim.query_belt_item_count(0) - 1):
		assert_eq(
			(
				sim.query_belt_item_distance_metres(0, slot)
				- sim.query_belt_item_distance_metres(0, slot + 1)
			),
			half_metre,
			"Items %d and %d should be 0.5 m apart" % [slot, slot + 1]
		)


# ── A full destination backs the Belt up ──────────────────────────────────────
# A fast Miner, a 2-tile Belt holding 8 Items, and a Smelter that buffers 4 ore — 2 per
# craft times the 2 crafts machine.input_buffer_crafts allows. The Smelter takes 191
# ticks a craft, so it falls a long way behind and the Belt has to absorb the difference
# and then stop.

func _backed_up_line(sim: Simulation) -> void:
	sim.step([
		InputAction.build_machine(0, _miner_index(sim), Vector3i(0, 0, 0)),
		InputAction.build_belt(0, Vector3i(2, 0, 0), Vector3i(3, 0, 0)),
		InputAction.build_machine(0, _smelter_index(sim), Vector3i(4, 0, 0)),
	])


func test_a_machine_input_port_holds_only_what_tuning_allows() -> void:
	var sim: Simulation = _saturating_sim()
	_backed_up_line(sim)
	assert_eq(
		sim.query_machine_input_capacity(1, "iron_ore"),
		4,
		"2 ore a craft, 2 crafts' worth"
	)
	assert_eq(
		sim.query_machine_input_capacity(1, "iron_plate"),
		0,
		"an input port does not accept what its Recipe does not eat"
	)


func test_a_full_destination_fills_the_belt_and_stalls_it() -> void:
	var sim: Simulation = _saturating_sim()
	_backed_up_line(sim)
	_run(sim, 250)
	assert_eq(sim.query_machine_input(1, "iron_ore"), 4, "the Smelter cannot hold a fifth ore")
	assert_eq(sim.query_belt_item_count(0), sim.query_belt_capacity(0), "so the Belt filled up")
	assert_eq(sim.query_belt_item_count(0), 8, "two tiles of 4 Items")
	assert_true(sim.query_belt_is_stalled(0), "and it is visibly stalled")
	# Stalled means stopped, not drifting: the leading Item is parked at the far end and
	# the queue behind it is packed at its spacing.
	assert_eq(
		sim.query_belt_item_position_metres(0, 0).x,
		Fixed.from_rational(31, 4),
		"the leading Item sits at the far end"
	)
	assert_eq(
		sim.query_belt_item_position_metres(0, 7).x,
		Fixed.from_rational(17, 4),
		"and the hindmost is back at the entry"
	)
	_run(sim, 30)
	assert_eq(
		sim.query_belt_item_position_metres(0, 0).x,
		Fixed.from_rational(31, 4),
		"a stalled Belt does not creep forward"
	)


func test_a_stalled_belt_resumes_the_moment_space_frees() -> void:
	var sim: Simulation = _saturating_sim()
	_backed_up_line(sim)
	# The Smelter's first craft finishes on tick 317: it had its two ore on tick 127 and
	# a craft is 191 ticks. That is the tick two ore leave its input buffer.
	_run(sim, 316)
	assert_eq(sim.query_machine_input(1, "iron_ore"), 4)
	assert_eq(sim.query_belt_item_count(0), 8)
	_run(sim, 1)
	assert_eq(sim.query_machine_output(1, "iron_plate"), 1, "the craft paid out")
	assert_eq(sim.query_machine_input(1, "iron_ore"), 2, "and two ore left the buffer")
	_run(sim, 1)
	assert_eq(sim.query_machine_input(1, "iron_ore"), 3, "the Belt handed over again at once")
	assert_eq(sim.query_belt_item_count(0), 7, "which is one Item fewer on the Belt")
	assert_false(sim.query_belt_is_stalled(0), "and the Belt is moving again")


func test_a_belt_running_into_a_machine_that_cannot_use_its_items_backs_up() -> void:
	var sim: Simulation = _saturating_sim()
	# A Belt out of one Miner's port and into another Miner. A Miner's input is the ground
	# under it, so there is no port to deliver to and the Belt simply fills.
	sim.step([
		InputAction.build_machine(0, _miner_index(sim), Vector3i(0, 0, 0)),
		InputAction.build_belt(0, Vector3i(2, 0, 0), Vector3i(3, 0, 0)),
		InputAction.build_machine(0, _miner_index(sim), Vector3i(4, 0, 0)),
	])
	_run(sim, 250)
	assert_eq(sim.query_belt_item_count(0), 8, "the Belt filled and stopped")
	assert_true(sim.query_belt_is_stalled(0))
	assert_eq(sim.query_machine_input_total(1), 0, "and nothing was quietly voided into it")


# ── Belts that feed Belts ─────────────────────────────────────────────────────
# A Belt's far end feeds whatever starts on the next tile, so a corner is two Belts and
# a long route is a chain of them. This is where update order stops being an
# implementation detail: a Belt advanced before the Belt it feeds sees a different
# downstream than one advanced after it.

func _chained_line(sim: Simulation, downstream_first: bool) -> void:
	var miner: InputAction = InputAction.build_machine(0, _miner_index(sim), Vector3i(0, 0, 0))
	var upstream: InputAction = InputAction.build_belt(0, Vector3i(2, 0, 0), Vector3i(3, 0, 0))
	var downstream: InputAction = InputAction.build_belt(0, Vector3i(4, 0, 0), Vector3i(5, 0, 0))
	if downstream_first:
		sim.step([miner, downstream, upstream])
		return
	sim.step([miner, upstream, downstream])


## Everything a player can see about a two-Belt chain, keyed by tile rather than by index
## so that two Factories laid in different orders can be compared at all.
func _describe_chain(sim: Simulation) -> PackedInt64Array:
	var described: PackedInt64Array = PackedInt64Array()
	for entry: Vector3i in [Vector3i(2, 0, 0), Vector3i(4, 0, 0)]:
		var belt: int = sim.query_belt_at_tile(entry)
		described.append(sim.query_belt_item_count(belt))
		for slot: int in range(sim.query_belt_item_count(belt)):
			described.append(sim.query_belt_item_distance_metres(belt, slot))
	return described


func test_a_belt_hands_its_items_on_to_the_belt_its_far_end_runs_into() -> void:
	var sim: Simulation = _sim_on_one_node()
	_chained_line(sim, false)
	# The first ore is collected on tick 91 and crosses the 2-tile upstream Belt in 105
	# ticks, so it reaches the far end on 196 and is handed over on 197.
	_run(sim, 196)
	assert_eq(sim.query_belt_item_count(0), 2, "the first two ore are both still upstream")
	assert_eq(sim.query_belt_item_count(1), 0, "and nothing has crossed the join yet")
	_run(sim, 1)
	assert_eq(sim.query_belt_item_count(0), 1, "the leading ore left the upstream Belt")
	assert_eq(sim.query_belt_item_count(1), 1, "and joined the downstream one")
	assert_eq(
		sim.query_belt_item_distance_metres(1, 0),
		Fixed.from_rational(1, 4),
		"a join puts an Item at the entry of the next Belt, which is the same place"
	)


func test_a_chain_of_belts_behaves_the_same_whichever_order_it_was_laid_in() -> void:
	# The bias this guards against is real: advancing Belts in index order would let a
	# chain laid upstream-first move an Item twice in one tick, and the same chain laid
	# downstream-first move it once. Both Factories below are the same Factory, so every
	# Item in them must be in the same place.
	var laid_upstream_first: Simulation = _sim_on_one_node()
	var laid_downstream_first: Simulation = _sim_on_one_node()
	_chained_line(laid_upstream_first, false)
	_chained_line(laid_downstream_first, true)
	for tick: int in range(400):
		laid_upstream_first.step([])
		laid_downstream_first.step([])
		assert_eq(
			_describe_chain(laid_upstream_first),
			_describe_chain(laid_downstream_first),
			"the two chains diverged on tick %d" % tick
		)


func test_a_saturated_chain_delivers_at_the_same_rate_a_single_belt_would() -> void:
	var chained: Simulation = _saturating_sim()
	_chained_line(chained, false)
	var single: Simulation = _saturating_sim()
	single.step([
		InputAction.build_machine(0, _miner_index(single), Vector3i(0, 0, 0)),
		InputAction.build_belt(0, Vector3i(2, 0, 0), Vector3i(5, 0, 0)),
	])
	# Ten Items enter either route on the same ticks, because a join costs latency and
	# not throughput: the Belt behind a join still loads one Item every 15 ticks.
	_run(chained, 141)
	_run(single, 141)
	assert_eq(
		(
			chained.query_belt_item_count(0)
			+ chained.query_belt_item_count(1)
		),
		single.query_belt_item_count(0),
		"a chain carries as many Items as the single Belt it replaces"
	)
	assert_eq(single.query_belt_item_count(0), 10, "and that number is the rated ten")


func test_two_belts_merging_into_one_merge_the_same_whichever_was_laid_first() -> void:
	# A merge is the one place two Belts compete, so it is the one place an arbitrary
	# order would show. Priority goes to the canonically first Belt — by the tile its run
	# starts at — which is geography and not history.
	var first: Simulation = _merging_sim(false)
	var second: Simulation = _merging_sim(true)
	for tick: int in range(700):
		first.step([])
		second.step([])
	var shared_first: int = first.query_belt_at_tile(Vector3i(4, 0, 0))
	var shared_second: int = second.query_belt_at_tile(Vector3i(4, 0, 0))
	assert_true(first.query_belt_item_count(shared_first) > 0, "the merge carried something")
	assert_eq(
		first.query_belt_item_count(shared_first),
		second.query_belt_item_count(shared_second),
		"the merge is not decided by build order"
	)
	for slot: int in range(first.query_belt_item_count(shared_first)):
		assert_eq(
			first.query_belt_item_distance_metres(shared_first, slot),
			second.query_belt_item_distance_metres(shared_second, slot),
			"Item %d sits in a different place" % slot
		)


## Two Miners, each with a short Belt, both running into the entry of a third.
func _merging_sim(reversed: bool) -> Simulation:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.add_node(Vector3i(4, 0, -4), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)

	var miner: int = _miner_index(sim)
	var along_x: Array = [
		InputAction.build_machine(0, miner, Vector3i(0, 0, 0)),
		InputAction.build_belt(0, Vector3i(2, 0, 0), Vector3i(3, 0, 0)),
	]
	var along_z: Array = [
		InputAction.build_machine(0, miner, Vector3i(4, 0, -4)),
		InputAction.build_belt(0, Vector3i(4, 0, -2), Vector3i(4, 0, -1)),
	]
	var shared: Array = [InputAction.build_belt(0, Vector3i(4, 0, 0), Vector3i(7, 0, 0))]

	if reversed:
		sim.step(shared + along_z + along_x)
		return sim
	sim.step(along_x + along_z + shared)
	return sim


func test_a_belt_loop_neither_eats_items_nor_breeds_them() -> void:
	# A loop has no downstream-most Belt, so the update order has to cut the cycle
	# somewhere. Wherever it cuts, the Items on the loop must be conserved: a join that
	# dropped one would be a silent leak, and one that kept a copy would be worse.
	var sim: Simulation = _sim_on_one_node()
	sim.step([
		InputAction.build_machine(0, _miner_index(sim), Vector3i(0, 0, 0)),
		InputAction.build_belt(0, Vector3i(2, 0, 0), Vector3i(4, 0, 0)),
		InputAction.build_belt(0, Vector3i(5, 0, 0), Vector3i(5, 0, 2)),
		InputAction.build_belt(0, Vector3i(5, 0, 3), Vector3i(3, 0, 3)),
		InputAction.build_belt(0, Vector3i(2, 0, 3), Vector3i(2, 0, 1)),
	])
	assert_eq(sim.query_belt_count(), 4, "the loop closed")
	_run(sim, 1000)
	# Ore lands on ticks 90, 180 … 990: eleven of them, and not one more or fewer, whether
	# it is in the Miner, on the loop, or going round for a second time.
	assert_eq(sim.query_item_total("iron_ore"), 11, "eleven ore mined, eleven ore accounted for")
	assert_true(
		sim.query_belt_item_count(2) > 0,
		"and Items have made it round two corners onto the third Belt"
	)


# ── Determinism ───────────────────────────────────────────────────────────────
# The harness builds its Simulation from a seed, a player count and a definition set, so
# these fixtures are laid out on the starter Map. Its first Node is at (-6, 0, 10), which
# a 2x2 Miner covers, and a Belt out of the footprint edge therefore starts at
# (-4, 0, 10).

const FIXTURE_MINER_TILE: Vector3i = Vector3i(-6, 0, 10)
const FIXTURE_BELT_ENTRY: Vector3i = Vector3i(-4, 0, 10)
const FIXTURE_SMELTER_TILE: Vector3i = Vector3i(-2, 0, 10)


func test_laying_a_belt_changes_the_hash() -> void:
	var laid: Simulation = Simulation.new(1, 1)
	var bare: Simulation = Simulation.new(1, 1)
	laid.step([InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(3, 0, 0))])
	bare.step([])
	assert_ne(laid.hash(), bare.hash(), "a Belt is part of the Factory and part of the state")


func test_a_refused_belt_leaves_the_hash_where_it_was() -> void:
	var refused: Simulation = Simulation.new(1, 1)
	var idle: Simulation = Simulation.new(1, 1)
	refused.step([InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(3, 0, 3))])
	idle.step([])
	assert_eq(refused.hash(), idle.hash(), "a Belt that could not be laid is not a Belt")


func test_where_the_items_on_a_belt_are_reaches_the_hash() -> void:
	# Two Factories identical in every respect except when the Belt was laid: the first ore
	# lands on tick 90, so a Belt laid on tick 100 collects it nine ticks later than one
	# laid at the start, and every later ore is collected on the same tick in both. Same
	# tick, same Miner, same empty buffers, same four ore — only their positions differ.
	# If Item positions were not hashed, these two would agree, and a desync in the system
	# that dominates a late-game frame would be invisible to the harness.
	var early: Simulation = _sim_on_one_node()
	var late: Simulation = _sim_on_one_node()
	var miner: InputAction = InputAction.build_machine(0, _miner_index(early), Vector3i(0, 0, 0))
	var belt: InputAction = InputAction.build_belt(0, Vector3i(2, 0, 0), Vector3i(11, 0, 0))

	early.step([miner, belt])
	_run(early, 100)
	late.step([miner])
	_run(late, 99)
	late.step([belt])
	_run(early, 300)
	_run(late, 300)

	assert_eq(early.query_tick(), late.query_tick(), "the two Runs are on the same tick")
	assert_eq(early.query_belt_item_count(0), 4, "four ore are riding the Belt")
	assert_eq(late.query_belt_item_count(0), 4, "in both Factories")
	assert_eq(
		early.query_machine_output_total(0),
		late.query_machine_output_total(0),
		"and neither Miner is holding anything back"
	)
	assert_ne(
		early.query_belt_item_distance_metres(0, 0),
		late.query_belt_item_distance_metres(0, 0),
		"the Items really are in different places"
	)
	assert_ne(early.hash(), late.hash(), "so the two states must hash differently")


func test_determinism_a_line_from_miner_through_belt_to_smelter_replays_identically() -> void:
	# The ticket's first fixture, on the shipped content: ore mined, carried, smelted. No
	# Definitions is passed, so the replay re-reads content/ and a content change is
	# reported as a definitions_mismatch rather than passing unnoticed.
	var sim: Simulation = Simulation.new(5, 1)
	var script: InputScript = InputScript.new()
	script.add_tick([
		InputAction.build_machine(0, _miner_index(sim), FIXTURE_MINER_TILE),
		InputAction.build_belt(0, FIXTURE_BELT_ENTRY, Vector3i(-3, 0, 10)),
		InputAction.build_machine(0, _smelter_index(sim), FIXTURE_SMELTER_TILE),
	])
	script.add_idle_ticks(700)

	var recording: ReplayRecording = DeterminismHarness.record(script, 5, 1)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_a_saturated_belt_replays_identically() -> void:
	# A Belt taking everything it can at its rated 4 Items a second, for 300 ticks, with
	# nothing yet having reached the far end. Needs a Miner faster than the Belt, which the
	# shipped content has no reason to provide, so the fixture carries its own.
	var content: Definitions = _fast_content()
	var sim: Simulation = Simulation.new(11, 1, content)
	var script: InputScript = InputScript.new()
	script.add_tick([
		InputAction.build_machine(0, _miner_index(sim), FIXTURE_MINER_TILE),
		InputAction.build_belt(0, FIXTURE_BELT_ENTRY, Vector3i(5, 0, 10)),
	])
	script.add_idle_ticks(300)

	var recording: ReplayRecording = DeterminismHarness.record(script, 11, 1, content)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_a_stalled_belt_replays_identically() -> void:
	# The other fixture: the same fast Miner against a 2-tile Belt and a Smelter that
	# cannot keep up, so the Belt fills, stalls, and starts moving again when the Smelter's
	# first craft frees two slots on tick 317. The window covers all three.
	var content: Definitions = _fast_content()
	var sim: Simulation = Simulation.new(13, 1, content)
	var script: InputScript = InputScript.new()
	script.add_tick([
		InputAction.build_machine(0, _miner_index(sim), FIXTURE_MINER_TILE),
		InputAction.build_belt(0, FIXTURE_BELT_ENTRY, Vector3i(-3, 0, 10)),
		InputAction.build_machine(0, _smelter_index(sim), FIXTURE_SMELTER_TILE),
	])
	script.add_idle_ticks(400)

	var recording: ReplayRecording = DeterminismHarness.record(script, 13, 1, content)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_a_stalled_belt_really_did_stall_during_its_fixture() -> void:
	# A fixture that replays a Factory doing nothing interesting proves nothing, so this
	# walks the same scenario and insists the stall and the recovery both happened.
	var content: Definitions = _fast_content()
	var sim: Simulation = Simulation.new(13, 1, content)
	sim.step([
		InputAction.build_machine(0, _miner_index(sim), FIXTURE_MINER_TILE),
		InputAction.build_belt(0, FIXTURE_BELT_ENTRY, Vector3i(-3, 0, 10)),
		InputAction.build_machine(0, _smelter_index(sim), FIXTURE_SMELTER_TILE),
	])
	var stalled_ticks: int = 0
	var full_ticks: int = 0
	for tick: int in range(400):
		sim.step([])
		if sim.query_belt_is_stalled(0):
			stalled_ticks += 1
		if sim.query_belt_is_full(0):
			full_ticks += 1
	assert_true(stalled_ticks > 100, "the Belt spent %d ticks blocked" % stalled_ticks)
	assert_true(full_ticks > 100, "and %d ticks completely full" % full_ticks)
	assert_eq(sim.query_machine_output(1, "iron_plate"), 1, "while the Smelter got one plate out")


## The Delivery tiers, inline so the fixture is a complete definition set. Progression is
## physical (`content/deliveries.csv`), and a table with no rows in it is an error rather
## than a Run with no progression. This one unlocks a Gear component and names no Machine,
## so nothing this file builds is locked behind it.
const DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_opening,Opening Licence,1,iron_ore:1,,placeholder_gear,
"""
