## What a Belt and a Wall cost, through the Simulation façade.
##
## #47's half one. Before it, the two cheapest things a player could lay down were free, so a
## layout was a question of taste rather than of routing — and the HUD's route line said
## "free" in as many words. `content/structures.csv` is the table that owns both prices, and
## these are the claims that make it a rule rather than a number in a file.
extends TestCase

const BELT: String = Definitions.STRUCTURE_BELT
const WALL: String = Definitions.STRUCTURE_WALL


func _run(sim: Simulation, ticks: int) -> void:
	for tick: int in range(ticks):
		sim.step([])


## A Map with nothing on it but the Nest, so a test about a wallet is not also a test about
## where the Map put its ore.
func _sim() -> Simulation:
	return Simulation.new(1, 1, null, MapLayout.empty())


func _plate(sim: Simulation) -> int:
	return sim.query_player_item(0, "iron_plate")


# ── What the table says ───────────────────────────────────────────────────────

func test_the_shipped_table_prices_a_belt_and_a_wall_by_the_tile() -> void:
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	assert_false(definitions.has_errors(), definitions.describe_errors())
	assert_eq(definitions.structure_cost_of(BELT, "iron_plate"), 1, "a Belt tile is a plate")
	assert_eq(definitions.structure_cost_of(WALL, "iron_plate"), 2, "a Wall tile is two")


func test_a_belt_and_a_wall_are_still_not_machines() -> void:
	# The thing giving them a price must not have done by making them rows in the Machine
	# table. DESIGN.md and GLOSSARY.md both put them outside the eight Machines.
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	assert_false(definitions.has_machine(BELT), "a Belt has no row in machines.csv")
	assert_false(definitions.has_machine(WALL), "nor does a Wall")
	for index: int in range(definitions.machine_count()):
		var machine: MachineDefinition = definitions.machine_at(index)
		assert_ne(machine.id, BELT, "and nothing in that table is called belt")
		assert_ne(machine.id, WALL, "or wall")


# ── Laying one costs ──────────────────────────────────────────────────────────

func test_a_belt_route_spends_its_price_for_every_tile_it_laid() -> void:
	var sim: Simulation = _sim()
	var before: int = _plate(sim)
	sim.step([InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(5, 0, 0))])
	assert_eq(sim.query_belt_length_tiles(0), 6, "tiles 0 to 5 inclusive")
	assert_eq(before - _plate(sim), 6, "six tiles at a plate each")


func test_a_route_with_a_corner_is_charged_for_both_of_its_runs() -> void:
	# The corner is where one run ends and the next begins, so a player pays once per tile of
	# Belt and not once per intent.
	var sim: Simulation = _sim()
	var before: int = _plate(sim)
	sim.step([InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(2, 0, 3))])
	var laid: int = 0
	for index: int in range(sim.query_belt_count()):
		laid += sim.query_belt_length_tiles(index)
	assert_eq(sim.query_belt_count(), 2, "an L is two runs")
	assert_eq(before - _plate(sim), laid, "charged once for every tile that appeared")


func test_a_wall_costs_what_its_one_tile_costs() -> void:
	var sim: Simulation = _sim()
	var before: int = _plate(sim)
	sim.step([InputAction.build_wall(0, Vector3i(3, 0, 3))])
	assert_eq(sim.query_wall_count(), 1, "the Wall stood up")
	assert_eq(before - _plate(sim), 2, "two plates, which is the table's per-tile figure")


# ── A route you cannot afford ─────────────────────────────────────────────────

## An L across open ground well clear of the Nest, longer than any wallet in this test file.
## A single straight run cannot be made long enough — the Map is 129 tiles across and a route
## off the end of it is refused for being off the Map, which is the wrong refusal to be
## asserting about a wallet.
const LONG_ROUTE_FROM: Vector3i = Vector3i(-60, 0, 40)
const LONG_ROUTE_TO: Vector3i = Vector3i(60, 0, -20)


func test_a_route_longer_than_the_wallet_is_refused_for_materials() -> void:
	var sim: Simulation = _sim()
	var held: int = _plate(sim)
	var tiles: int = sim.query_belt_route_tiles(0, LONG_ROUTE_FROM, LONG_ROUTE_TO, 0)
	assert_true(tiles > held, "a route of %d tiles against %d plates" % [tiles, held])
	assert_eq(
		sim.query_belt_route_refusal(0, LONG_ROUTE_FROM, LONG_ROUTE_TO, 0),
		Simulation.Refusal.MISSING_MATERIALS,
		"and the wallet is what it is refused for"
	)


func test_a_refused_route_lays_nothing_and_leaves_the_hash_where_it_was() -> void:
	# The whole route or none of it. A route half-laid up to the tile the wallet ran out on
	# is a player demolishing what they did not ask for.
	# Against an idle Run rather than against its own earlier hash, because a tick always moves
	# the hash by being a tick: what is asserted is that the refused route left no other mark.
	var sim: Simulation = _sim()
	var idle: Simulation = _sim()
	var held: int = _plate(sim)
	sim.step([InputAction.build_belt(0, LONG_ROUTE_FROM, LONG_ROUTE_TO)])
	idle.step([])
	assert_eq(sim.query_belt_count(), 0, "not one tile of it was laid")
	assert_eq(_plate(sim), held, "and nothing was spent")
	assert_eq(sim.hash(), idle.hash(), "a refused route is a silent no-op")


func test_the_reason_is_on_screen_before_the_release_rather_than_after_it() -> void:
	# A projection about a route that has not happened, the arrangement every refusal in this
	# project has: asking does not move the hash, so the HUD may ask every frame.
	var sim: Simulation = _sim()
	var before: int = sim.hash()
	var refusal: int = sim.query_belt_route_refusal(0, LONG_ROUTE_FROM, LONG_ROUTE_TO, 0)
	assert_eq(refusal, Simulation.Refusal.MISSING_MATERIALS)
	assert_eq(sim.hash(), before, "asking is not a tick, so it changed nothing at all")


func test_the_route_line_can_read_the_bill_for_the_whole_route() -> void:
	# The length is the number a player decides on, so the figure beside it has to be the
	# bill for the route rather than the price of a tile.
	var sim: Simulation = _sim()
	var items: PackedStringArray = sim.query_belt_route_cost_items(
		0, Vector3i(0, 0, 0), Vector3i(3, 0, 0), 0
	)
	var counts: PackedInt64Array = sim.query_belt_route_cost_counts(
		0, Vector3i(0, 0, 0), Vector3i(3, 0, 0), 0
	)
	assert_eq(sim.query_belt_route_tiles(0, Vector3i(0, 0, 0), Vector3i(3, 0, 0), 0), 4)
	assert_eq(items.size(), 1, "one Item in the bill")
	assert_eq(items[0], "iron_plate")
	assert_eq(counts[0], 4, "four tiles at a plate each")


func test_a_wall_a_player_cannot_afford_is_refused_for_materials() -> void:
	var sim: Simulation = _sim()
	# Spend the pocket down to one plate, which is less than a Wall tile's two. Two runs
	# rather than one, because a straight run long enough would leave the Map.
	var held: int = _plate(sim)
	var first: int = (held - 1) / 2
	sim.step([
		InputAction.build_belt(0, Vector3i(-60, 0, 40), Vector3i(-61 + first, 0, 40)),
		InputAction.build_belt(
			0, Vector3i(-60, 0, 42), Vector3i(-61 + (held - 1 - first), 0, 42)
		),
	])
	assert_eq(_plate(sim), 1, "one plate left")
	assert_eq(
		sim.query_build_wall_refusal(0, Vector3i(0, 0, 5)),
		Simulation.Refusal.MISSING_MATERIALS
	)
	sim.step([InputAction.build_wall(0, Vector3i(0, 0, 5))])
	assert_eq(sim.query_wall_count(), 0, "no Wall")
	# The same comparison, against a Run that spent its plate the same way and was then left
	# alone for a tick.
	var idle: Simulation = _sim()
	var spare: int = (held - 1) / 2
	idle.step([
		InputAction.build_belt(0, Vector3i(-60, 0, 40), Vector3i(-61 + spare, 0, 40)),
		InputAction.build_belt(
			0, Vector3i(-60, 0, 42), Vector3i(-61 + (held - 1 - spare), 0, 42)
		),
	])
	idle.step([])
	assert_eq(sim.hash(), idle.hash(), "and no change to the Run")


# ── Taking one apart returns it ───────────────────────────────────────────────

func test_demolishing_a_belt_returns_every_plate_its_tiles_cost() -> void:
	var sim: Simulation = _sim()
	var before: int = _plate(sim)
	sim.step([InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(7, 0, 0))])
	assert_eq(_plate(sim), before - 8, "eight tiles paid for")
	sim.step([InputAction.demolish(0, Vector3i(3, 0, 0))])
	assert_eq(sim.query_belt_count(), 0, "pointing at any tile takes the run down")
	assert_eq(_plate(sim), before, "and iterating on a layout costs only the ticks")


func test_demolishing_a_wall_returns_what_it_cost() -> void:
	var sim: Simulation = _sim()
	var before: int = _plate(sim)
	sim.step([InputAction.build_wall(0, Vector3i(2, 0, 2))])
	sim.step([InputAction.demolish(0, Vector3i(2, 0, 2))])
	assert_eq(sim.query_wall_count(), 0)
	assert_eq(_plate(sim), before, "nothing is destroyed")


func test_a_belt_hands_back_its_price_and_the_items_riding_it_at_once() -> void:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var miner: int = sim.query_definitions().machine_index("miner_mk1")
	sim.step([
		InputAction.build_machine(0, miner, Vector3i(0, 0, 0)),
		InputAction.build_belt(0, Vector3i(2, 0, 0), Vector3i(5, 0, 0)),
	])
	var after_building: int = _plate(sim)
	_run(sim, 300)
	var riding: int = sim.query_belt_item_count(0)
	assert_true(riding > 0, "the Miner put ore on it")
	sim.step([InputAction.demolish(0, Vector3i(2, 0, 0))])
	assert_eq(_plate(sim), after_building + 4, "four tiles' worth of plate came back")
	assert_eq(sim.query_player_item(0, "iron_ore"), riding, "and the ore that was riding it")


# ── The trap this ticket had to solve ─────────────────────────────────────────

func test_a_set_that_brings_its_own_recipes_gets_structures_that_are_free() -> void:
	# **This is the acceptance criterion the previous attempt failed.** A price has to be
	# checked against the Recipes, because an Item exists only because a Recipe mentions one.
	# A test that supplies its own Recipes mentions no `iron_plate`, so a price naming one
	# would make its whole definition set an error and every such test would fail. The
	# resolution is that the price lives in a *table*, and a caller that supplies no
	# structures source gets structures that cost nothing — which is exactly what an empty
	# `build_cost` column already means for a Machine.
	var definitions: Definitions = Definitions.parse(
		OWN_MACHINES, OWN_RECIPES, _own_tuning(), OWN_WAVES, OWN_DELIVERIES, OWN_GEAR,
		OWN_STRATAGEMS
	)
	assert_false(definitions.has_errors(), definitions.describe_errors())
	assert_eq(definitions.item_index("iron_plate"), -1, "no Recipe here mentions a plate")
	assert_true(definitions.structure_cost_items(BELT).is_empty(), "so a Belt is free")

	var sim: Simulation = Simulation.new(1, 1, definitions, MapLayout.empty())
	var before: int = sim.query_player_item(0, "iron_ore")
	sim.step([InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(9, 0, 0))])
	assert_eq(sim.query_belt_count(), 1, "a ten-tile Belt went up")
	assert_eq(sim.query_player_item(0, "iron_ore"), before, "paid for with nothing")


# ── Determinism ───────────────────────────────────────────────────────────────

func test_determinism_paying_for_belts_and_walls_replays_identically() -> void:
	var script: InputScript = InputScript.new()
	script.add_tick([
		InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(9, 0, 0)),
		InputAction.build_wall(0, Vector3i(0, 0, 4)),
		InputAction.build_wall(0, Vector3i(1, 0, 4)),
	])
	script.add_idle_ticks(10)
	# A route the wallet cannot cover, which must be the same no-op on both runs.
	script.add_tick([InputAction.build_belt(0, LONG_ROUTE_FROM, LONG_ROUTE_TO)])
	script.add_idle_ticks(10)
	script.add_tick([InputAction.demolish(0, Vector3i(0, 0, 4))])
	script.add_idle_ticks(10)

	var recording: ReplayRecording = DeterminismHarness.record(script, 3, 1)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_the_paying_fixture_really_did_pay_and_really_was_refused() -> void:
	# **The honesty check beside the fixture.** A replay of a Run in which nothing was ever
	# bought and nothing was ever refused reads as a passing determinism test, and the failure
	# is silent. So the same script is driven again and the events asserted.
	var sim: Simulation = Simulation.new(3, 1, null, MapLayout.empty())
	var opening: int = _plate(sim)
	sim.step([
		InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(9, 0, 0)),
		InputAction.build_wall(0, Vector3i(0, 0, 4)),
		InputAction.build_wall(0, Vector3i(1, 0, 4)),
	])
	assert_eq(_plate(sim), opening - 14, "ten tiles of Belt and two of Wall")
	_run(sim, 10)

	var before_the_refusal: int = _plate(sim)
	assert_eq(
		sim.query_belt_route_refusal(0, LONG_ROUTE_FROM, LONG_ROUTE_TO, 0),
		Simulation.Refusal.MISSING_MATERIALS,
		"the long route really is unaffordable"
	)
	sim.step([InputAction.build_belt(0, LONG_ROUTE_FROM, LONG_ROUTE_TO)])
	assert_eq(sim.query_belt_count(), 1, "and really was refused")
	assert_eq(_plate(sim), before_the_refusal, "costing nothing")
	_run(sim, 10)

	sim.step([InputAction.demolish(0, Vector3i(0, 0, 4))])
	assert_eq(_plate(sim), before_the_refusal + 2, "the demolished Wall paid back in full")


# ── A definition set whose Recipes are its own ────────────────────────────────

## The shipped tuning with its opening bill written in the one Item these Recipes mention.
## The shipped file rather than a hand-copied one, so this test cannot drift out of step with
## what a Run is actually played on — what is under test is the Recipes, not the numbers.
func _own_tuning() -> String:
	var file: FileAccess = FileAccess.open(
		"%s/%s" % [Definitions.CONTENT_DIR, Definitions.TUNING_FILE], FileAccess.READ
	)
	assert_not_null(file, "the shipped tuning file is readable")
	var text: String = file.get_as_text()
	file.close()
	return text.replace('starting_stock = "iron_plate:110"', 'starting_stock = "iron_ore:110"')


const OWN_MACHINES: String = """id,display_name,role,footprint_x,footprint_z,height_metres,power_draw_kw,power_supply_kw,health,max_depth,range_tiles,damage,repair,charge_capacity,recipe_id,build_cost
miner_mk1,Miner Mk1,miner,2,2,1.8,120,0,400,1,0,0,0,0,mine_iron_ore,iron_ore:1
"""

const OWN_RECIPES: String = """id,display_name,inputs,outputs,seconds
mine_iron_ore,Mine Iron Ore,,iron_ore:1,1.5
"""

const OWN_WAVES: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,6,1200,40
"""

## A tier that unlocks a Gear component and names no Machine, so nothing this test builds is
## locked behind it. A tier that unlocked nothing is refused — a bill a player pays for nothing.
const OWN_DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_opening,Opening Licence,1,iron_ore:1,,placeholder_gear,
"""

const OWN_GEAR: String = """id,display_name,kind,attack,damage,range_metres,spread_degrees,seconds_per_shot,ammunition_item,ammunition_per_shot,damage_percent,range_percent,spread_percent,interval_percent,ammunition_percent,damage_taken_percent
pneumatic_wrench,Pneumatic Wrench,weapon,melee,40,2.5,0,0.6,,0,0,0,0,0,0,0
placeholder_gear,Placeholder Barrel,barrel,,0,0,0,0,,0,10,0,0,0,0,0
"""

## One row, so the table is not empty — a Silo with nothing to load is a Machine a player can
## build, feed and never use, and `Definitions` refuses that.
const OWN_STRATAGEMS: String = """id,display_name,effect,paint_seconds,radius_tiles,damage_per_charge,goods_per_charge,sentry_machine,sentry_seconds
artillery_barrage,Artillery Barrage,barrage,5,6,150,,,0
"""
