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

## A stock that pays for anything these tests place, so a refusal under test is never
## `MISSING_MATERIALS` by accident. Every number is the shipped file's otherwise — see
## `ContentFixture`.
const STOCK: String = "iron_frame:40;iron_ore:40;iron_plate:40"


## The shipped Wave composition, inline so the fixture is a complete definition set. A
## Wave's contents are a table (`content/waves.csv`), and a set with no rows in it is an
## error rather than a Run that is never attacked.
const WAVES: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,6,150,40
"""


func _content() -> Definitions:
	var fixture: ContentFixture = ContentFixture.for_case(self).stock(STOCK)
	fixture.machines = MACHINES
	fixture.recipes = RECIPES
	fixture.waves = WAVES
	fixture.deliveries = DELIVERIES
	fixture.gear = GEAR
	fixture.stratagems = STRATAGEMS
	return fixture.definitions()


## A Run on an empty Map, so nothing but the Factory under test is in the way.
func _sim(players: int = 1) -> Simulation:
	return Simulation.new(7, players, _content(), MapLayout.empty())


func _index(sim: Simulation, id: String) -> int:
	return sim.query_definitions().machine_index(id)


## A Map with one shallow iron Node at the origin and one Depth 3 seam ten tiles east.
##
## Hand-built rather than the starter Map for the reason `test_belts._sim_on_one_node`
## is: a test about how far a snap reaches should not also be a test about where the
## starter Map happened to put its ore. `miner_mk1` in the content above has
## `max_depth = 1`, so the eastern seam is ore it can see and cannot lift.
const SHALLOW_NODE: Vector3i = Vector3i(0, 0, 0)
const DEEP_NODE: Vector3i = Vector3i(10, 0, 0)


func _sim_with_nodes() -> Simulation:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(SHALLOW_NODE, "iron_ore", 1)
	layout.add_node(DEEP_NODE, "iron_ore", 3)
	layout.sort_nodes()
	return Simulation.new(7, 1, _content(), layout)


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
	# A Run opens with the weapon out since #42 and a Wall is a build act, so the Build Gun
	# comes out first — the same fixture every controller-driven build test now carries.
	sim.step([InputAction.set_build_mode(0, true)])
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


# ── Snapping a Miner onto a Node (#42) ────────────────────────────────────────
#
# The player's words were *"miners should snap to the nearest node (within range) or show
# red"*. A Node is one tile and a Miner is four, so hitting it means covering a flat
# marker on a textured floor with the corner of a footprint — and a Miner one tile out is
# placed, paid for, and silently does nothing for ever.
#
# **The snap is the aim's, not the Simulation's**, which is the decision this section
# pins. `BuildGun.snap_to_a_node` is what both the hologram and the build intent read, so
# the tile drawn and the tile built on are one answer; the Simulation goes on believing
# what it has always believed, that the tile in an intent is the tile built on. See the
# argument in `game/build_gun.gd`.


func test_a_miner_aimed_near_a_node_snaps_its_footprint_onto_it() -> void:
	var sim: Simulation = _sim_with_nodes()
	var miner: int = _index(sim, "miner_mk1")
	var placed: BuildGun.Placement = BuildGun.snap_to_a_node(
		sim, miner, 0, SHALLOW_NODE + Vector3i(3, 0, 2)
	)
	assert_eq(placed.aim, BuildGun.Aim.ON_TARGET, "there is a Node in range")
	assert_true(placed.snapped, "and the aim moved to reach it")
	assert_true(
		WorldGrid.footprint_covers(placed.tile, 2, 2, SHALLOW_NODE),
		"the 2x2 the snap chose, %s, does not cover the Node" % placed.tile
	)


func test_the_snapped_tile_is_what_a_build_really_lands_on() -> void:
	# The claim the whole design rests on: the hologram and the placement are one answer.
	# A snap the apply did not know about would draw a promise the Simulation breaks.
	var sim: Simulation = _sim_with_nodes()
	var miner: int = _index(sim, "miner_mk1")
	var placed: BuildGun.Placement = BuildGun.snap_to_a_node(
		sim, miner, 0, SHALLOW_NODE + Vector3i(3, 0, 2)
	)
	sim.step([InputAction.build_machine(0, miner, placed.tile)])
	assert_eq(sim.query_machine_count(), 1, "it placed")
	assert_eq(
		sim.query_node_under_machine(0),
		sim.query_node_at_tile(SHALLOW_NODE),
		"and the Miner is standing on the Node, which is the whole point"
	)


func test_a_miner_aimed_at_nothing_in_range_is_refused_rather_than_moved() -> void:
	var sim: Simulation = _sim_with_nodes()
	var miner: int = _index(sim, "miner_mk1")
	var far: Vector3i = Vector3i(40, 0, 40)
	var placed: BuildGun.Placement = BuildGun.snap_to_a_node(sim, miner, 0, far)
	assert_eq(placed.aim, BuildGun.Aim.NO_NODE_IN_RANGE, "no ore anywhere near")
	assert_false(placed.snapped)
	assert_eq(placed.tile, far, "and the aim is left where the player put it")
	assert_ne(BuildGun.aim_text(placed.aim), "", "a red box with no words is the old bug")


func test_a_node_this_miner_cannot_lift_says_so_rather_than_saying_nothing_is_there() -> void:
	# Two different problems with two different answers — ore you do not mine and ore you
	# cannot reach — so they are two reasons, the standing `GEAR_IS_LOCKED` has beside
	# `CONTENT_IS_LOCKED`.
	var sim: Simulation = _sim_with_nodes()
	var miner: int = _index(sim, "miner_mk1")
	var placed: BuildGun.Placement = BuildGun.snap_to_a_node(
		sim, miner, 0, DEEP_NODE + Vector3i(1, 0, 0)
	)
	assert_eq(placed.aim, BuildGun.Aim.NODE_TOO_DEEP)
	assert_false(placed.snapped, "a Miner is not dragged onto ore it cannot work")
	assert_ne(
		BuildGun.aim_text(placed.aim),
		BuildGun.aim_text(BuildGun.Aim.NO_NODE_IN_RANGE),
		"and the two reasons do not read the same"
	)


func test_the_nearest_workable_node_wins() -> void:
	var sim: Simulation = _sim_with_nodes()
	var miner: int = _index(sim, "miner_mk1")
	# Between the two, but nearer the deep one. The deep one is not workable, so the snap
	# has to walk past it to the shallow one rather than reporting the nearest Node.
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.add_node(Vector3i(4, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	var two: Simulation = Simulation.new(7, 1, _content(), layout)
	var placed: BuildGun.Placement = BuildGun.snap_to_a_node(
		two, miner, 0, Vector3i(3, 0, 0)
	)
	assert_true(
		WorldGrid.footprint_covers(placed.tile, 2, 2, Vector3i(4, 0, 0)),
		"the nearer of the two, not the first in the Map's order: %s" % placed.tile
	)


func test_only_a_miner_snaps() -> void:
	# A Smelter has no business being dragged onto ore, and a player placing one beside a
	# Miner would find it moving under their aim. Generalising this past Miners does not
	# fall out cleanly, so it is deliberately not generalised.
	var sim: Simulation = _sim_with_nodes()
	var press: int = _index(sim, "press_mk1")
	var aimed: Vector3i = SHALLOW_NODE + Vector3i(2, 0, 0)
	var placed: BuildGun.Placement = BuildGun.snap_to_a_node(sim, press, 0, aimed)
	assert_eq(placed.tile, aimed, "a crafter lands where it was aimed")
	assert_eq(placed.aim, BuildGun.Aim.ON_TARGET, "and is never refused for want of ore")
	assert_false(placed.snapped)


func test_a_snap_is_a_function_of_the_aim_and_nothing_else() -> void:
	# The replay claim. What crosses into the Simulation is the snapped tile, so a
	# recorded script describes where the Miner went without being replayed to find out —
	# but the hologram and the intent still have to agree on every frame, which they can
	# only do if this is a pure function. Asked twice, with a Machine built in between.
	var sim: Simulation = _sim_with_nodes()
	var miner: int = _index(sim, "miner_mk1")
	var aimed: Vector3i = SHALLOW_NODE + Vector3i(3, 0, 2)
	var first: BuildGun.Placement = BuildGun.snap_to_a_node(sim, miner, 0, aimed)
	for tick: int in range(10):
		sim.step([])
	var second: BuildGun.Placement = BuildGun.snap_to_a_node(sim, miner, 0, aimed)
	assert_eq(first.tile, second.tile, "the same aim is the same answer")
	assert_eq(first.aim, second.aim)


func test_the_rotation_the_player_is_holding_is_what_is_centred() -> void:
	# `press_mk1` is 2x3, so a quarter turn makes it 3x2 and the origin that centres it
	# over a tile is a different one. The Press does not snap, so this is asserted of the
	# shared centring rather than through it.
	var sim: Simulation = _sim_with_nodes()
	var miner: int = _index(sim, "miner_mk1")
	for rotation: int in range(4):
		var placed: BuildGun.Placement = BuildGun.snap_to_a_node(
			sim, miner, rotation, SHALLOW_NODE + Vector3i(2, 0, 2)
		)
		var size: Vector2i = WorldGrid.rotated_footprint(2, 2, rotation)
		assert_true(
			WorldGrid.footprint_covers(placed.tile, size.x, size.y, SHALLOW_NODE),
			"turned a quarter %d times, the footprint still covers the Node" % rotation
		)


func test_the_simulation_answers_what_a_miner_would_make_of_a_node() -> void:
	# The two queries the snap is built out of, asserted at their own seam. They are
	# projections about a row and a Node, so neither needs anything standing.
	var sim: Simulation = _sim_with_nodes()
	var miner: int = _index(sim, "miner_mk1")
	var shallow: int = sim.query_node_at_tile(SHALLOW_NODE)
	var deep: int = sim.query_node_at_tile(DEEP_NODE)
	assert_true(sim.query_node_yields_for(miner, shallow), "a Miner mines iron ore")
	assert_true(sim.query_node_yields_for(miner, deep), "including the deep seam's")
	assert_true(sim.query_node_is_within_depth_of(miner, shallow), "Depth 1 is in reach")
	assert_false(sim.query_node_is_within_depth_of(miner, deep), "Depth 3 is not")
	assert_false(
		sim.query_node_yields_for(_index(sim, "press_mk1"), shallow),
		"and a crafter mines nothing at all"
	)
	assert_false(sim.query_node_yields_for(miner, 99), "an unknown Node is no Node")


func test_asking_about_a_placement_does_not_move_the_hash() -> void:
	# `BuildGun` is presentation and the two queries behind it are projections, so a
	# player waving the hologram over the Map leaves the Run exactly where it was.
	var asked: Simulation = _sim_with_nodes()
	var idle: Simulation = _sim_with_nodes()
	var miner: int = _index(asked, "miner_mk1")
	for step: int in range(12):
		BuildGun.snap_to_a_node(asked, miner, step % 4, Vector3i(step - 6, 0, step - 3))
	assert_eq(asked.hash(), idle.hash(), "looking is free")


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
