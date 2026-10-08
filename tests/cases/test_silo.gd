## The Silo, the Charges it assembles, the dial that loads it and the Painting that
## calls a Stratagem in.
##
## This is the clearest expression of the whole design — **more production means more
## artillery, full stop** (docs/DESIGN.md) — so everything here goes through the
## Simulation façade, because a Silo is deliberately not a second kind of building: it is
## a row in `content/machines.csv` with a Recipe, fed by Belts, drawing Power, and the
## only thing the Simulation adds is what happens instead of depositing an output.
##
## Three claims carry the file:
##
## * A Charge is **assembled**, never instantaneous (GLOSSARY.md), and it stockpiles.
## * A load is **irreversible**: once the dial is committed there is no taking it back,
##   and nothing anywhere hands a Charge back.
## * An interrupted Painting **consumes the Charge and produces nothing**, which is true
##   by construction rather than by a special case — the Charge leaves the Silo on the
##   tick the Painting begins.
extends TestCase

# ── Fixtures ──────────────────────────────────────────────────────────────────

## A Delivery chain that locks nothing a Silo needs, so a test about artillery is not also a
## test about progression. It unlocks a Gear component because a tier that unlocks nothing is
## refused by the loader, and a component is the one thing nothing here reads. The shipped
## chain — which does lock two of the three Stratagems — is asserted further down.
const DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_open,Open Licence,1,iron_plate:1,,mg_drum_magazine,
"""

## Pockets deep enough to stand a Silo up without a Factory behind it. What a Run can
## actually afford is `test_nest_store.gd`'s subject.
const STOCKED: String = 'starting_stock = "iron_plate:400;ammunition:400"'
const SHIPPED_STOCK: String = 'starting_stock = "iron_plate:110"'


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	return text


## The shipped content, with the Delivery chain and the opening bill replaced.
func _content(overrides: Array = []) -> Definitions:
	var tuning: String = _read("res://content/tuning.toml").replace(SHIPPED_STOCK, STOCKED)
	for pair: PackedStringArray in overrides:
		tuning = tuning.replace(pair[0], pair[1])
	return Definitions.parse(
		_read("res://content/machines.csv"),
		_read("res://content/recipes.csv"),
		tuning,
		_read("res://content/waves.csv"),
		DELIVERIES,
		_read("res://content/gear.csv"),
		_read("res://content/stratagems.csv"),
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv",
		"deliveries.csv",
		"gear.csv",
		"stratagems.csv"
	)


# ── The definitions ───────────────────────────────────────────────────────────

func test_a_silo_is_a_machine_whose_recipe_produces_no_items() -> void:
	var content: Definitions = _content()
	assert_false(content.has_errors(), content.describe_errors())

	var silo: MachineDefinition = content.machine("silo_mk1")
	if not assert_not_null(silo, "silo_mk1 must be a row in content/machines.csv"):
		return
	assert_true(silo.is_silo(), "its role is silo")
	assert_true(
		silo.produces_no_items(),
		"a Charge is not an Item, so the Silo joins the predicate a generator and a Turret share"
	)
	assert_eq(silo.footprint_x, 4, "four tiles across, as content/machine_bodies.csv models it")
	assert_eq(silo.footprint_z, 4)
	assert_true(silo.charge_capacity > 0, "Charges stockpile up to a capacity")
	assert_true(silo.power_draw_kw > 0, "fed by Belts, consuming Power (GLOSSARY.md)")
	assert_true(silo.health > 0, "and destructible, so a breakthrough threatens it")

	var recipe: RecipeDefinition = content.recipe_at(silo.recipe_index)
	if not assert_not_null(recipe, "a Silo runs a Recipe like any other Machine"):
		return
	assert_true(recipe.input_count() > 0, "assembled from Belt-fed inputs")
	assert_eq(
		recipe.output_count(),
		0,
		"and no outputs at all: what a Silo produces is a Charge, which is not an Item"
	)


func test_the_three_stratagems_are_rows_that_resolve_distinctly() -> void:
	var content: Definitions = _content()
	assert_false(content.has_errors(), content.describe_errors())
	assert_eq(content.stratagem_count(), 3, "Artillery Barrage, Supply Drop and Sentry Drop")

	var barrage: StratagemDefinition = content.stratagem("artillery_barrage")
	if not assert_not_null(barrage, "artillery_barrage must be a row"):
		return
	assert_true(barrage.is_barrage(), "it shells the painted ground")
	assert_true(barrage.damage_per_charge > 0, "and what it does is damage, per Charge")
	assert_true(barrage.radius_tiles > 0, "over an area")

	var supply: StratagemDefinition = content.stratagem("supply_drop")
	if not assert_not_null(supply, "supply_drop must be a row"):
		return
	assert_true(supply.is_supply(), "it drops goods")
	assert_true(
		supply.goods_items.find("ammunition") != -1,
		"Ammunition, because the thing a Run runs out of is rounds"
	)
	assert_true(
		supply.goods_items.find("iron_plate") != -1,
		"and repair material, which is what a wrench and a Pylon spend"
	)

	var sentry: StratagemDefinition = content.stratagem("sentry_drop")
	if not assert_not_null(sentry, "sentry_drop must be a row"):
		return
	assert_true(sentry.is_sentry(), "it places a Turret")
	assert_true(
		content.machine(sentry.sentry_machine) != null,
		"and the Turret it places is an ordinary row in machines.csv"
	)
	assert_true(
		sentry.goods_items.find("ammunition") != -1,
		"arriving loaded, which is what lets it need no Belt"
	)
	assert_true(sentry.sentry_seconds > 0, "and it is temporary")

	for index: int in range(content.stratagem_count()):
		assert_true(
			content.stratagem_at(index).paint_seconds > 0,
			"every Stratagem is channelled: a Painting with no channel is not a Painting"
		)


# ── A Factory that assembles Charges ──────────────────────────────────────────
#
# This file brings its own content for the reason `test_turrets.gd` does: the shipped chain
# into a Silo is a Miner, a Smelter, an Ammo Press and twenty rounds a Charge, which is a
# minute of game time before the first assertion — and a test nobody runs asserts nothing.
# What is *not* altered is the shape: a Silo with a Recipe, fed by a Belt, crafting on the
# same `_craft` a Smelter runs on. Power is left out of it (nothing draws) so a brownout
# cannot be mistaken for a Silo with nothing to work with; `test_power.gd` owns the grid, and
# the one test here that is about the grid turns the draw back on.

const SILO_MACHINES: String = """id,display_name,role,footprint_x,footprint_z,height_metres,power_draw_kw,power_supply_kw,health,max_depth,range_tiles,damage,repair,charge_capacity,recipe_id,build_cost
mg_turret_mk1,MG Turret Mk1,turret,2,2,2,0,0,350,0,8,15,0,0,fire_mg,
plate_seam_mk1,Plate Seam,miner,2,2,2,0,0,400,1,0,0,0,0,dig_plate,
silo_mk1,Silo Mk1,silo,4,4,2.2,0,0,900,0,0,0,0,4,assemble_charge,
"""

const SILO_RECIPES: String = """id,display_name,inputs,outputs,seconds
assemble_charge,Assemble Charge,iron_plate:2,,0.5
dig_plate,Dig Plate,,iron_plate:1,0.1
fire_mg,Fire MG,ammunition:1,,0.25
"""

## One Crawler a Breach, flat however hot the Factory gets. The subject here is artillery and
## not the schedule.
const ONE_CRAWLER: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,1,0,1
"""

const FOUR_CRAWLERS: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,4,0,4
"""

## The dial's reach, stretched so that a player standing on the tile they will paint can also
## work the Silo beside them. The shipped four metres is asserted on its own, further down, by
## the test that stands too far away and reads the refusal.
const SHIPPED_DIAL_REACH: String = "load_reach_metres = 4"
const REACHABLE_DIAL_REACH: String = "load_reach_metres = 12"

## A Telegraph short enough that a called Wave arrives inside a test.
const SHIPPED_TELEGRAPH: String = "telegraph_seconds = 12"
const QUICK_TELEGRAPH: String = "telegraph_seconds = 2"


## The content a Silo test runs on: its own Machines and Recipes, the shipped Stratagems, and
## the shipped tuning with the dial's reach stretched.
func _silo_content(
	overrides: Array = [], waves: String = ONE_CRAWLER, stratagems: Array = []
) -> Definitions:
	var tuning: String = _read("res://content/tuning.toml").replace(SHIPPED_STOCK, STOCKED)
	tuning = tuning.replace(SHIPPED_DIAL_REACH, REACHABLE_DIAL_REACH)
	for pair: PackedStringArray in overrides:
		tuning = tuning.replace(pair[0], pair[1])

	var table: String = _read("res://content/stratagems.csv")
	for pair: PackedStringArray in stratagems:
		table = table.replace(pair[0], pair[1])

	return Definitions.parse(
		SILO_MACHINES,
		SILO_RECIPES,
		tuning,
		waves,
		DELIVERIES,
		_read("res://content/gear.csv"),
		table,
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv",
		"deliveries.csv",
		"gear.csv",
		"stratagems.csv"
	)


## The Map these tests play on. The Nest is twenty tiles up the +z lane and the player opens
## standing at the lane's mouth on tile (0,0) — which is the tile they paint, because a player
## must stand at the target (GLOSSARY.md), and which is within reach of the Silo's dial. No
## Breach, so no Wave interrupts a test about assembling and loading; `_lane_layout` is what a
## test about being shot at uses.
func _layout() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(0, WorldGrid.GROUND_LAYER, 20)
	layout.add_node(Vector3i(4, WorldGrid.GROUND_LAYER, 12), "iron_plate", 1)
	layout.sort_nodes()
	return layout


## The same Map with a Breach four tiles down the lane, so Crawlers come out of the ground and
## walk straight over the tile the player is painting. That is how a Painting gets interrupted
## by something other than the player's own hand.
func _lane_layout() -> MapLayout:
	var layout: MapLayout = _layout()
	layout.add_breach(Vector3i(0, WorldGrid.GROUND_LAYER, -4))
	layout.sort_breaches()
	return layout


func _sim(overrides: Array = [], stratagems: Array = []) -> Simulation:
	return Simulation.new(7, 1, _silo_content(overrides, ONE_CRAWLER, stratagems), _layout())


## A Silo at (4,4) fed by one Belt out of the plate seam at (4,12).
##
## The Silo is built first, so index 0 is the Silo in every test below. Its footprint covers
## (4,4) to (7,7); the Belt starts on the tile past the seam's north edge and ends pointing at
## the Silo's south edge, which is the only kind of connection there is (CLAUDE.md: Belts
## connect by adjacency and nothing else).
func _fed_silo(sim: Simulation) -> void:
	var definitions: Definitions = sim.query_definitions()
	var ground: int = WorldGrid.GROUND_LAYER
	sim.step([
		InputAction.build_machine(
			0, definitions.machine_index("silo_mk1"), Vector3i(4, ground, 4)
		),
		InputAction.build_machine(
			0, definitions.machine_index("plate_seam_mk1"), Vector3i(4, ground, 12)
		),
		InputAction.build_belt(0, Vector3i(4, ground, 11), Vector3i(4, ground, 8)),
	])


## Steps until the Silo is holding at least `wanted` Charges, and reports the ticks it took.
##
## Bounded, like every wait in this suite: an unbounded `while` in a test is a hung suite
## rather than a failing one, and a hung suite says nothing at all.
func _step_until_charges(sim: Simulation, wanted: int, limit: int = 1800) -> int:
	var ticks: int = 0
	while sim.query_silo_charges(0) < wanted and ticks < limit:
		sim.step([])
		ticks += 1
	return ticks


## The tile the player opens the Run standing on, and therefore the only tile they can paint
## without walking.
func _target(sim: Simulation) -> Vector3i:
	var here: FixedVec2 = sim.query_player_position(0)
	return WorldGrid.tile_at_metres(here.x, here.z)


## Loads the Silo with `charges` of a Stratagem and reports whether it landed.
func _load(sim: Simulation, stratagem_id: String, charges: int) -> bool:
	var index: int = sim.query_definitions().stratagem_index(stratagem_id)
	sim.step([
		InputAction.set_silo_dial(0, index, charges),
		InputAction.load_silo(0, Vector3i(4, WorldGrid.GROUND_LAYER, 4), index, charges),
	])
	return sim.query_silo_loaded_charges(0) == charges


## A Run with a fed Silo, stocked to its capacity and loaded. Built from scratch rather than
## copied, which is what makes it usable as a control: the Simulation is deterministic, so two
## Runs driven by the same intents are the same Run.
func _loaded_silo_run(stratagem_id: String, charges: int) -> Simulation:
	var sim: Simulation = _sim()
	_fed_silo(sim)
	_step_until_charges(sim, 4)
	_load(sim, stratagem_id, charges)
	return sim


## Holds a Painting on the tile the player is standing on until it resolves or the limit runs
## out, and reports the ticks held.
func _paint_until_done(sim: Simulation, limit: int = 600) -> int:
	var target: Vector3i = _target(sim)
	var ticks: int = 0
	while sim.query_player_paint_charges(0) > 0 or ticks == 0:
		if ticks >= limit:
			break
		sim.step([InputAction.paint(0, target)])
		ticks += 1
	return ticks


# ── A Charge is assembled, and it stockpiles ──────────────────────────────────

func test_a_silo_assembles_charges_from_belt_fed_inputs() -> void:
	var sim: Simulation = _sim()
	assert_false(sim.query_definitions().has_errors(), sim.query_definitions().describe_errors())
	_fed_silo(sim)

	assert_true(sim.query_machine_is_silo(0), "index 0 is the Silo")
	assert_eq(sim.query_silo_charges(0), 0, "a Silo arrives empty: a Charge is never instant")

	var ticks: int = _step_until_charges(sim, 1)
	assert_true(ticks > 0 and ticks < 1800, "the Belt primed it and a Charge came out, in %d ticks" % ticks)
	assert_eq(sim.query_silo_charges(0), 1, "one Charge, banked")
	assert_true(
		sim.query_machine_input(0, "iron_plate") >= 0,
		"and the plate it ate came off the Belt rather than from nowhere"
	)
	assert_eq(
		sim.query_machine_output_total(0),
		0,
		"a Charge is not an Item, so nothing landed in the output buffer"
	)


func test_charges_stockpile_up_to_a_capacity() -> void:
	var sim: Simulation = _sim()
	_fed_silo(sim)
	var capacity: int = sim.query_silo_charge_capacity(0)
	assert_eq(capacity, 4, "the capacity is the Machine's own column")

	_step_until_charges(sim, capacity)
	assert_eq(sim.query_silo_charges(0), capacity, "it filled up")

	# And then stops, rather than overflowing or throwing the surplus away.
	for _tick: int in range(600):
		sim.step([])
	assert_eq(sim.query_silo_charges(0), capacity, "a full Silo stays full and banks no more")


func test_a_full_silo_is_idle_and_off_the_power_grid() -> void:
	# The same rule a Turret with nothing in reach obeys: it has everything its Recipe asks
	# for and nowhere to put the result, so it draws nothing. Power is turned on for this one
	# test, because it is the only one about the grid.
	var sim: Simulation = Simulation.new(7, 1, _powered_content(), _layout())
	_fed_silo(sim)
	_step_until_charges(sim, 1)
	# Read over a window rather than on one tick: a Silo that has just banked a Charge is a
	# Silo that has just spent its plate, and the tick it is waiting for the Belt on is a tick
	# it is legitimately off the grid for.
	var drew: bool = false
	for _tick: int in range(180):
		sim.step([])
		if sim.query_machine_power_draw_kw(0) > 0:
			drew = true
	assert_true(drew, "a Silo with room and plate in it is on the grid")

	_step_until_charges(sim, sim.query_silo_charge_capacity(0))
	sim.step([])
	assert_eq(
		sim.query_machine_power_draw_kw(0),
		0,
		"and a full one is off it — it is not starved, it is finished"
	)
	assert_false(
		sim.query_machine_is_starved(0),
		"deliberately not starvation: it has its inputs, it has nowhere to put a Charge"
	)


## The same content with the Silo drawing Power, and a baseline big enough to pay for it.
func _powered_content() -> Definitions:
	var tuning: String = _read("res://content/tuning.toml").replace(SHIPPED_STOCK, STOCKED)
	tuning = tuning.replace(SHIPPED_DIAL_REACH, REACHABLE_DIAL_REACH)
	tuning = tuning.replace("baseline_supply_kw = 300", "baseline_supply_kw = 2000")
	return Definitions.parse(
		SILO_MACHINES.replace(
			"silo_mk1,Silo Mk1,silo,4,4,2.2,0,0", "silo_mk1,Silo Mk1,silo,4,4,2.2,400,0"
		),
		SILO_RECIPES,
		tuning,
		ONE_CRAWLER,
		DELIVERIES,
		_read("res://content/gear.csv"),
		_read("res://content/stratagems.csv"),
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv",
		"deliveries.csv",
		"gear.csv",
		"stratagems.csv"
	)

# ── Loading: a dial, by hand, and no way back ─────────────────────────────────
#
# DESIGN.md names Silo loading first in its list of diegetic controls, and the reason is in
# the same paragraph: friction is satisfying when it is problem-solving under pressure and
# tedious when it is transcription. An irreversible commitment made *before* the fight is the
# first kind. Everything in this section is about that commitment having teeth.

func test_the_dial_is_simulation_state_and_a_load_commits_what_it_reads() -> void:
	var sim: Simulation = _sim()
	_fed_silo(sim)
	var definitions: Definitions = sim.query_definitions()

	# A Run opens with the first unlocked Stratagem wound on and one Charge, so the dial is
	# never at a position a Silo would refuse — the arrangement the Build Gun's opening Machine
	# has.
	assert_true(
		definitions.has_stratagem(sim.query_player_dial_stratagem(0)),
		"the dial opens on something real: %s" % sim.query_player_dial_stratagem(0)
	)
	assert_eq(sim.query_player_dial_charges(0), 1, "and on one Charge")

	var sentry: int = definitions.stratagem_index("sentry_drop")
	sim.step([InputAction.set_silo_dial(0, sentry, 3)])
	assert_eq(sim.query_player_dial_stratagem(0), "sentry_drop", "the shell selector moved")
	assert_eq(sim.query_player_dial_charges(0), 3, "and the charge counter with it")
	assert_eq(
		sim.query_player_dial_stratagem_index(0),
		sentry,
		"and it reads back as the index a load intent carries"
	)

	# Winding the dial commits nothing. The Silo is still holding what it was holding.
	assert_eq(sim.query_silo_loaded_charges(0), 0, "winding a dial loads nothing")

	_step_until_charges(sim, 3)
	var before: int = sim.hash()
	sim.step([
		InputAction.load_silo(0, Vector3i(4, WorldGrid.GROUND_LAYER, 4), sentry, 3)
	])
	assert_ne(sim.hash(), before, "a load is a thing that happened")
	assert_eq(sim.query_silo_loaded_stratagem(0), "sentry_drop", "and that is what is in the tube")
	assert_eq(sim.query_silo_loaded_charges(0), 3, "three Charges of it")
	assert_eq(
		sim.query_silo_charges(0),
		0,
		"taken out of the stockpile rather than conjured alongside it"
	)


func test_a_completed_load_cannot_be_undone() -> void:
	# The claim the whole mechanic rests on. There is no unload intent, and a second load is
	# refused rather than replacing the first — so choosing wrong is a consequence you live
	# with until you fire it or lose the Silo.
	var sim: Simulation = _sim()
	_fed_silo(sim)
	var definitions: Definitions = sim.query_definitions()
	_step_until_charges(sim, 4)

	assert_true(_load(sim, "sentry_drop", 1), "the premise: one Charge of Sentry Drop is in")

	var barrage: int = definitions.stratagem_index("artillery_barrage")
	assert_eq(
		sim.query_load_silo_refusal(0, Vector3i(4, WorldGrid.GROUND_LAYER, 4), barrage, 1),
		Simulation.Refusal.SILO_ALREADY_LOADED,
		"and the Simulation says so before the key is pressed"
	)

	# A twin Run, identically built and not asked to load. The Factory goes on running either
	# way, so "a refusal moves nothing" is a comparison against the tick that would have
	# happened anyway rather than against the hash before it.
	var control: Simulation = _loaded_silo_run("sentry_drop", 1)
	assert_eq(sim.hash(), control.hash(), "the premise: two identical Runs")

	sim.step([
		InputAction.load_silo(0, Vector3i(4, WorldGrid.GROUND_LAYER, 4), barrage, 3),
	])
	control.step([])
	assert_eq(
		sim.query_silo_loaded_stratagem(0),
		"sentry_drop",
		"the second load did not replace the first"
	)
	assert_eq(sim.query_silo_loaded_charges(0), 1, "nor add to it")
	assert_eq(
		sim.hash(), control.hash(), "and a refused load is a silent no-op that moves nothing"
	)


func test_demolishing_a_loaded_silo_is_not_a_way_to_undo_a_load() -> void:
	# The other direction somebody would look for a refund. A demolition hands back a build
	# cost and both buffers — but a Charge is not an Item, so there is nothing to hand back,
	# and the load goes with the Machine.
	var sim: Simulation = _sim()
	_fed_silo(sim)
	_step_until_charges(sim, 4)
	assert_true(_load(sim, "sentry_drop", 2), "the premise: two Charges committed")
	assert_eq(sim.query_silo_charges(0), 2, "and two still banked")

	sim.step([InputAction.demolish(0, Vector3i(4, WorldGrid.GROUND_LAYER, 4))])
	assert_eq(sim.query_machine_count(), 1, "the Silo came apart")
	assert_eq(
		sim.query_player_item(0, "ammunition"),
		400,
		"and gave back no rounds: the opening stock, untouched"
	)

	# Rebuild it and it is a Silo that has never been loaded.
	sim.step([
		InputAction.build_machine(
			0,
			sim.query_definitions().machine_index("silo_mk1"),
			Vector3i(4, WorldGrid.GROUND_LAYER, 4)
		)
	])
	var rebuilt: int = sim.query_machine_at_tile(Vector3i(4, WorldGrid.GROUND_LAYER, 4))
	assert_eq(sim.query_silo_charges(rebuilt), 0, "a rebuilt Silo starts empty")
	assert_eq(sim.query_silo_loaded_charges(rebuilt), 0, "and unloaded")


func test_a_load_the_silo_has_not_assembled_is_refused_by_name() -> void:
	var sim: Simulation = _sim()
	_fed_silo(sim)
	var barrage: int = sim.query_definitions().stratagem_index("artillery_barrage")
	var tile: Vector3i = Vector3i(4, WorldGrid.GROUND_LAYER, 4)

	assert_eq(
		sim.query_load_silo_refusal(0, tile, barrage, 1),
		Simulation.Refusal.NOT_ENOUGH_CHARGES,
		"an empty Silo cannot be loaded: a Charge is built in advance, never instantaneous"
	)

	_step_until_charges(sim, 2)
	assert_eq(
		sim.query_load_silo_refusal(0, tile, barrage, 4),
		Simulation.Refusal.NOT_ENOUGH_CHARGES,
		"and two banked will not pay for a load of four"
	)
	assert_eq(
		sim.query_load_silo_refusal(0, tile, barrage, 2),
		Simulation.Refusal.NONE,
		"two will pay for a load of two"
	)


func test_the_dial_stops_rather_than_refusing_and_a_load_past_the_stop_is_refused() -> void:
	# A dial is a physical thing with stops on it, so winding it clamps. A *load* asking for
	# more than a load may carry is a different thing — that is an intent off the wire, and the
	# Simulation refuses it by name rather than quietly clamping what it commits.
	var sim: Simulation = _sim()
	_fed_silo(sim)
	var barrage: int = sim.query_definitions().stratagem_index("artillery_barrage")
	var stop: int = sim.query_max_charges_per_load()
	assert_eq(stop, 4, "the dial's upper stop is tuning")

	sim.step([InputAction.set_silo_dial(0, barrage, 99)])
	assert_eq(sim.query_player_dial_charges(0), stop, "the counter stopped at the stop")
	sim.step([InputAction.set_silo_dial(0, barrage, -3)])
	assert_eq(sim.query_player_dial_charges(0), 1, "and at one going the other way")

	assert_eq(
		sim.query_load_silo_refusal(0, Vector3i(4, WorldGrid.GROUND_LAYER, 4), barrage, stop + 1),
		Simulation.Refusal.BAD_CHARGE_COUNT,
		"a load past the stop is refused by name"
	)
	assert_eq(
		sim.query_load_silo_refusal(0, Vector3i(4, WorldGrid.GROUND_LAYER, 4), barrage, 0),
		Simulation.Refusal.BAD_CHARGE_COUNT,
		"and so is a load of nothing"
	)


func test_a_dial_worked_from_out_of_reach_is_refused_by_name() -> void:
	# Loading is diegetic: a physical mechanism operated at the Machine (DESIGN.md), so there
	# is somewhere a player has to be standing. This Run uses the shipped four metres rather
	# than the stretched reach the rest of the file leans on, and the player opens eight tiles
	# from the Silo.
	var sim: Simulation = Simulation.new(
		7,
		1,
		_silo_content([PackedStringArray([REACHABLE_DIAL_REACH, SHIPPED_DIAL_REACH])]),
		_layout()
	)
	_fed_silo(sim)
	_step_until_charges(sim, 1)
	var barrage: int = sim.query_definitions().stratagem_index("artillery_barrage")
	var tile: Vector3i = Vector3i(4, WorldGrid.GROUND_LAYER, 4)

	assert_eq(
		sim.query_load_silo_refusal(0, tile, barrage, 1),
		Simulation.Refusal.OUT_OF_REACH,
		"the dial is on the Silo, and the Silo is across the yard"
	)
	var control: Simulation = Simulation.new(
		7,
		1,
		_silo_content([PackedStringArray([REACHABLE_DIAL_REACH, SHIPPED_DIAL_REACH])]),
		_layout()
	)
	_fed_silo(control)
	_step_until_charges(control, 1)
	assert_eq(sim.hash(), control.hash(), "the premise: two identical Runs")

	sim.step([InputAction.load_silo(0, tile, barrage, 1)])
	control.step([])
	assert_eq(sim.hash(), control.hash(), "and reaching for it from here moves nothing")
	assert_eq(sim.query_silo_loaded_charges(0), 0, "the tube is still empty")


func test_a_dial_worked_at_a_tile_with_no_silo_on_it_is_refused_by_name() -> void:
	var sim: Simulation = _sim()
	_fed_silo(sim)
	_step_until_charges(sim, 1)
	var barrage: int = sim.query_definitions().stratagem_index("artillery_barrage")
	assert_eq(
		sim.query_load_silo_refusal(
			0, Vector3i(0, WorldGrid.GROUND_LAYER, 0), barrage, 1
		),
		Simulation.Refusal.NO_SILO_THERE,
		"there is no dial on bare ground"
	)
	assert_eq(
		sim.query_load_silo_refusal(
			0, Vector3i(4, WorldGrid.GROUND_LAYER, 12), barrage, 1
		),
		Simulation.Refusal.NO_SILO_THERE,
		"and none on a Miner either"
	)


func test_a_stratagem_no_delivery_has_unlocked_cannot_be_loaded_and_the_refusal_says_why() -> void:
	# A Stratagem is locked because a tier names it, exactly as a Machine and a piece of Gear
	# are. The chain here names the Barrage and nothing else, so what is being asserted is the
	# gate rather than the shipped tiers — those are
	# `test_the_shipped_chain_locks_two_of_the_three_stratagems`.
	var shipped: Definitions = Definitions.parse(
		SILO_MACHINES,
		SILO_RECIPES,
		_read("res://content/tuning.toml")
			.replace(SHIPPED_STOCK, STOCKED)
			.replace(SHIPPED_DIAL_REACH, REACHABLE_DIAL_REACH),
		ONE_CRAWLER,
		LOCKING_DELIVERIES,
		_read("res://content/gear.csv"),
		_read("res://content/stratagems.csv"),
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv",
		"deliveries.csv",
		"gear.csv",
		"stratagems.csv"
	)
	assert_false(shipped.has_errors(), shipped.describe_errors())

	var sim: Simulation = Simulation.new(7, 1, shipped, _layout())
	_fed_silo(sim)
	_step_until_charges(sim, 2)
	var tile: Vector3i = Vector3i(4, WorldGrid.GROUND_LAYER, 4)

	var barrage: int = shipped.stratagem_index("artillery_barrage")
	assert_eq(
		sim.query_load_silo_refusal(0, tile, barrage, 1),
		Simulation.Refusal.STRATAGEM_IS_LOCKED,
		"a Stratagem a tier names is a Stratagem a Run has to earn"
	)
	assert_false(sim.query_stratagem_is_unlocked(barrage))

	var sentry: int = shipped.stratagem_index("sentry_drop")
	assert_true(
		sim.query_stratagem_is_unlocked(sentry),
		"and one no tier names is open from tick 0"
	)
	assert_eq(sim.query_load_silo_refusal(0, tile, sentry, 1), Simulation.Refusal.NONE)


const LOCKING_DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_open,Open Licence,1,iron_plate:1,,mg_drum_magazine,artillery_barrage
"""


func test_the_shipped_chain_locks_two_of_the_three_stratagems() -> void:
	# The shipped files exactly as the game ships them, because what is being asserted is the
	# chain itself: a Run opens able to drop a Sentry and has to earn the rest.
	var shipped: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	assert_false(shipped.has_errors(), shipped.describe_errors())

	assert_false(
		shipped.locks_stratagem("sentry_drop"),
		"the Sentry Drop is open from tick 0: the first thing a Silo is for is covering ground,"
		+ " and a Run that had to deliver before it could use the Silo it just built would have"
		+ " paid twice"
	)
	assert_true(shipped.locks_stratagem("supply_drop"), "the Supply Drop comes with a tier")
	assert_true(
		shipped.locks_stratagem("artillery_barrage"),
		"and the heaviest thing in the game sits behind the deepest mine"
	)

# ── Painting: standing at the target, exposed, unable to act ──────────────────
#
# The best co-op moment the design has, because one player is committed and helpless while
# the others cover them (GLOSSARY.md). Which means the two things worth asserting hardest are
# that the commitment is real — rooted, unable to act — and that interruption costs the
# Charge. The second is true by construction: the Charges leave the Silo on the tick the
# channel begins, so there is nowhere for them to go back to.

## Holds a Painting on the player's own tile for a fixed number of ticks, whatever becomes of
## it. Deliberately unconditional, so a test can assert what happened rather than steering it.
func _hold_paint(sim: Simulation, ticks: int) -> void:
	var target: Vector3i = _target(sim)
	for _tick: int in range(ticks):
		sim.step([InputAction.paint(0, target)])


## A fed, stocked, loaded Silo on the lane Map, with a Wave called and a Crawler out of the
## ground — the shape every test about being shot at while channelling needs.
func _run_with_a_crawler_coming(stratagems: Array = []) -> Simulation:
	var sim: Simulation = Simulation.new(
		7,
		1,
		_silo_content([PackedStringArray([SHIPPED_TELEGRAPH, QUICK_TELEGRAPH])], ONE_CRAWLER, stratagems),
		_lane_layout()
	)
	_fed_silo(sim)
	_step_until_charges(sim, 1)
	_load(sim, "artillery_barrage", 1)
	sim.step([InputAction.call_wave_early(0)])
	var ticks: int = 0
	while sim.query_enemy_count() == 0 and ticks < 600:
		sim.step([])
		ticks += 1
	return sim


func test_painting_requires_standing_at_the_target() -> void:
	var sim: Simulation = _loaded_silo_run("artillery_barrage", 1)
	var here: Vector3i = _target(sim)

	assert_eq(
		sim.query_paint_refusal(0, here),
		Simulation.Refusal.NONE,
		"the tile under the player's feet is paintable"
	)
	assert_eq(
		sim.query_paint_refusal(0, here + Vector3i(3, 0, 0)),
		Simulation.Refusal.NOT_AT_THE_TARGET,
		"and a tile six metres away is not — a player must stand at the target"
	)

	# Holding it on somewhere else does nothing at all, and spends nothing.
	sim.step([InputAction.paint(0, here + Vector3i(3, 0, 0))])
	assert_false(sim.query_player_is_painting(0), "no channel started")
	assert_eq(sim.query_silo_loaded_charges(0), 1, "and the tube is untouched")


func test_painting_with_nothing_loaded_is_refused_by_name() -> void:
	var sim: Simulation = _sim()
	_fed_silo(sim)
	assert_eq(
		sim.query_paint_refusal(0, _target(sim)),
		Simulation.Refusal.NOTHING_LOADED,
		"the load comes first and the Painting spends it"
	)
	_step_until_charges(sim, 2)
	assert_eq(
		sim.query_paint_refusal(0, _target(sim)),
		Simulation.Refusal.NOTHING_LOADED,
		"a stockpile is not a loaded Silo: loading is a thing a player does by hand"
	)
	_load(sim, "artillery_barrage", 2)
	assert_eq(sim.query_paint_refusal(0, _target(sim)), Simulation.Refusal.NONE)


func test_a_painting_player_is_rooted_and_unable_to_act() -> void:
	var sim: Simulation = _loaded_silo_run("artillery_barrage", 1)
	var here: Vector3i = _target(sim)
	var definitions: Definitions = sim.query_definitions()

	sim.step([InputAction.paint(0, here)])
	assert_true(sim.query_player_is_painting(0), "the channel is running")
	assert_eq(sim.query_player_paint_stratagem(0), "artillery_barrage", "carrying the Barrage")
	assert_eq(sim.query_player_paint_charges(0), 1, "and the Charge it took off the Silo")
	assert_eq(
		sim.query_silo_loaded_charges(0),
		0,
		"which is no longer in the Silo — that is what makes an interruption cost it"
	)
	assert_eq(
		sim.query_player_paint_ticks_served(0),
		0,
		"and it has served no tick of channel yet, like everything else that arrived this tick"
	)

	# Unable to act, as a refusal rather than as a mode. Every intent a player's refusal goes
	# through opens with the same function, so each of these is the real reason and not a
	# guess.
	assert_eq(
		sim.query_build_refusal(0, definitions.machine_index("mg_turret_mk1"), here + Vector3i(2, 0, 0), 0),
		Simulation.Refusal.PLAYER_IS_PAINTING
	)
	assert_eq(sim.query_fire_refusal(0), Simulation.Refusal.PLAYER_IS_PAINTING)
	assert_eq(sim.query_repair_refusal(0, here), Simulation.Refusal.PLAYER_IS_PAINTING)
	assert_eq(
		sim.query_load_silo_refusal(
			0, Vector3i(4, WorldGrid.GROUND_LAYER, 4), definitions.stratagem_index("sentry_drop"), 1
		),
		Simulation.Refusal.PLAYER_IS_PAINTING,
		"including working another dial: both hands are on the designator"
	)

	# And rooted. The throttle is consumed and the player does not move.
	var before: FixedVec2 = sim.query_player_position(0)
	for _tick: int in range(60):
		sim.step([InputAction.paint(0, here), InputAction.move(0, Fixed.ONE, 0)])
	var after: FixedVec2 = sim.query_player_position(0)
	assert_eq(after.x, before.x, "a player channelling a Painting stands still")
	assert_eq(after.z, before.z)
	assert_eq(_target(sim), here, "and is therefore still at the target")


# ── An interrupted Painting consumes the Charge and produces nothing ──────────

func test_letting_go_of_a_painting_consumes_the_charge_and_produces_nothing() -> void:
	var sim: Simulation = _loaded_silo_run("artillery_barrage", 2)
	# A twin that loads the same two Charges and never paints, so "the Charges did not come
	# back" is a comparison rather than an assumption: the Silo goes on assembling either way.
	var control: Simulation = _loaded_silo_run("artillery_barrage", 2)
	var here: Vector3i = _target(sim)
	var required: int = sim.query_stratagem_paint_ticks(
		sim.query_definitions().stratagem_index("artillery_barrage")
	)
	assert_eq(required, 300, "the shipped Barrage channels five seconds")

	# Most of the way, and then let go.
	for _tick: int in range(required - 10):
		sim.step([InputAction.paint(0, here)])
		control.step([])
	assert_true(sim.query_player_is_painting(0), "the premise: nearly there")
	assert_eq(sim.query_player_paint_ticks_served(0), required - 11, "and it had served the ticks")

	sim.step([])
	control.step([])

	# **Proven interrupted, not merely absent.** The tick it happened on and the Charges it
	# cost are both recorded, which is what makes this a statement about the interruption
	# rather than about an effect that failed to turn up.
	assert_false(sim.query_player_is_painting(0), "the channel is over")
	assert_eq(
		sim.query_player_paint_interrupted_tick(0),
		sim.query_tick() - 1,
		"interrupted, on the tick the key came up"
	)
	assert_eq(sim.query_player_charges_wasted(0), 2, "and both Charges are gone")
	assert_eq(sim.query_silo_loaded_charges(0), 0, "not back in the tube")
	assert_eq(sim.query_player_paint_charges(0), 0, "and not in the player's hands")
	assert_eq(
		sim.query_silo_charges(0),
		control.query_silo_charges(0),
		"and not in the stockpile: the Silo holds exactly what it assembled meanwhile"
	)
	assert_eq(
		control.query_silo_loaded_charges(0),
		2,
		"where the twin that never painted is still holding its load"
	)

	# Starting again is a Silo that has to be loaded again, which is the whole cost.
	assert_eq(
		sim.query_paint_refusal(0, here),
		Simulation.Refusal.NOTHING_LOADED,
		"a wasted Painting leaves the Silo empty: the Charge bought nothing"
	)


func test_a_bite_interrupts_a_painting_and_the_charge_is_gone() -> void:
	# The clause that makes Painting the co-op moment it is meant to be: the channel is five
	# seconds and the Crawler out of the Breach four tiles down the lane needs under two to
	# reach the player standing in it. Nobody is covering them, so the Painting is lost.
	var sim: Simulation = _run_with_a_crawler_coming()
	var control: Simulation = _run_with_a_crawler_coming()
	if not assert_true(sim.query_enemy_count() > 0, "the premise: a Crawler is on the Map"):
		return
	var here: Vector3i = _target(sim)
	var whole: int = sim.query_player_max_health(0)
	assert_eq(sim.query_player_health(0), whole, "and the player is whole")

	_hold_paint(sim, 300)
	for _tick: int in range(300):
		control.step([])

	# The bite is *proven* to be what did it: the player lost hit points, the tick the
	# interruption was recorded on is a tick the Painting was still being held, and the
	# Crawler that did it is still alive because no Barrage ever landed on it.
	assert_true(
		sim.query_player_health(0) < whole,
		"the Crawler reached them: %d of %d left" % [sim.query_player_health(0), whole]
	)
	assert_true(
		sim.query_player_paint_interrupted_tick(0) >= 0,
		"and the Painting was interrupted rather than merely absent"
	)
	assert_eq(sim.query_player_charges_wasted(0), 1, "at a cost of one Charge")
	assert_false(sim.query_player_is_painting(0), "the channel is over")
	assert_true(sim.query_enemy_count() > 0, "and nothing was shelled: the Barrage never came")
	assert_eq(sim.query_silo_loaded_charges(0), 0, "the tube is empty")
	assert_eq(
		sim.query_silo_charges(0),
		control.query_silo_charges(0),
		"and the Charge is not back in the stockpile either — the twin that never painted holds"
		+ " exactly as much"
	)
	assert_eq(control.query_silo_loaded_charges(0), 1, "with its own load still in the tube")

# ── What was fired, as a number beside what was lost ─────────────────────────

func test_a_finished_painting_is_counted_and_an_interrupted_one_is_not() -> void:
	# The symmetric half of `query_player_charges_wasted`, and the figure #37's acceptance
	# criterion is measured on: "a competently built Factory can power, load and fire a Silo
	# within a Run" has to be *demonstrated* in the balance harness, and every one of the three
	# effects can resolve leaving nothing to look at. A Barrage with no Enemy in the radius
	# kills nobody, a Sentry expires, and a Supply Drop's goods look exactly like a withdrawal.
	# So what was fired is recorded where what was wasted already is.
	var fired: Simulation = _loaded_silo_run("artillery_barrage", 2)
	assert_eq(fired.query_player_stratagems_fired(0), 0, "a Run opens having fired nothing")
	assert_eq(fired.query_player_charges_fired(0), 0)

	_paint_until_done(fired)

	assert_eq(fired.query_player_stratagems_fired(0), 1, "one Stratagem was called in")
	assert_eq(fired.query_player_charges_fired(0), 2, "and both Charges went into it")
	assert_eq(fired.query_player_charges_wasted(0), 0, "with none wasted")

	# And the one that was let go of counts for nothing, which is the whole of "an interrupted
	# Painting consumes the Charge and produces nothing".
	var lost: Simulation = _loaded_silo_run("artillery_barrage", 2)
	lost.step([InputAction.paint(0, _target(lost))])
	lost.step([])
	assert_eq(lost.query_player_charges_wasted(0), 2, "the premise: the channel was broken")
	assert_eq(lost.query_player_stratagems_fired(0), 0, "so nothing was fired")
	assert_eq(lost.query_player_charges_fired(0), 0, "and no Charge landed anywhere")


# ── The three Stratagems, each resolving distinctly ───────────────────────────

func test_an_artillery_barrage_shells_everything_in_reach_of_the_painted_tile() -> void:
	# A one-second channel rather than the shipped five, because the Crawler coming up the
	# lane needs under two seconds to reach the player and interrupt them — which is the
	# subject of the test above this one, not of this one.
	var sim: Simulation = _run_with_a_crawler_coming([
		PackedStringArray(["barrage,5,6", "barrage,1,6"])
	])
	if not assert_true(sim.query_enemy_count() > 0, "the premise: a Crawler is on the Map"):
		return
	var alive: int = sim.query_enemy_count()

	_paint_until_done(sim)

	assert_eq(sim.query_player_charges_wasted(0), 0, "the Painting was not interrupted")
	assert_eq(
		sim.query_player_paint_interrupted_tick(0), -1, "and nothing recorded one"
	)
	assert_eq(
		sim.query_enemy_count(),
		alive - 1,
		"and the Crawler inside the radius is gone: 150 points against a Crawler's 30"
	)
	assert_eq(sim.query_silo_loaded_charges(0), 0, "the tube is empty, as it is either way")


func test_a_supply_drop_delivers_ammunition_and_repair_material_into_the_players_pockets() -> void:
	# Into their own pockets, which is what makes it the answer to having run out: the same
	# pockets the Build Gun spends from and a weapon fires out of. A drop that banked at the
	# Nest would ask the player to walk home, which is what a Stratagem is for not doing.
	var sim: Simulation = _loaded_silo_run("supply_drop", 2)
	var rounds: int = sim.query_player_item(0, "ammunition")
	var plate: int = sim.query_player_item(0, "iron_plate")
	var definitions: Definitions = sim.query_definitions()
	var supply: int = definitions.stratagem_index("supply_drop")

	_paint_until_done(sim)

	assert_eq(sim.query_player_charges_wasted(0), 0, "it resolved")
	assert_eq(
		sim.query_player_item(0, "ammunition"),
		rounds + definitions.stratagem("supply_drop").goods_of("ammunition") * 2,
		"two Charges' worth of Ammunition, so a Charge is a multiplier"
	)
	assert_eq(
		sim.query_player_item(0, "iron_plate"),
		plate + definitions.stratagem("supply_drop").goods_of("iron_plate") * 2,
		"and two Charges' worth of repair material"
	)
	assert_eq(
		sim.query_stratagem_goods_per_charge(supply, "ammunition"),
		40,
		"out of the row and nowhere else"
	)


func test_a_sentry_drop_places_a_temporary_turret_that_needs_no_belt() -> void:
	var sim: Simulation = _loaded_silo_run("sentry_drop", 2)
	var here: Vector3i = _target(sim)
	var standing: int = sim.query_machine_count()
	var definitions: Definitions = sim.query_definitions()

	_paint_until_done(sim)

	assert_eq(sim.query_machine_count(), standing + 1, "a Turret arrived")
	var sentry: int = sim.query_machine_at_tile(here)
	if not assert_true(sentry != -1, "on the painted tile"):
		return
	assert_eq(sim.query_machine_id(sentry), "mg_turret_mk1", "the row's own Machine")
	assert_true(sim.query_machine_is_turret(sentry), "an ordinary Turret in every respect")
	assert_eq(
		sim.query_turret_ammunition(sentry),
		definitions.stratagem("sentry_drop").goods_of("ammunition") * 2,
		"arriving with two Charges' worth of rounds already in it — which is the whole of"
		+ " what needing no Belt means"
	)
	assert_true(
		sim.query_turret_ammunition_capacity(sentry) >= sim.query_turret_ammunition(sentry),
		"and the gauge tells the truth about a magazine a Belt could never have filled"
	)
	assert_eq(sim.query_belt_count(), 1, "no second Belt was laid: the one feeding the Silo")

	# Temporary, and the clock is a tick rather than a countdown.
	assert_true(sim.query_machine_is_temporary(sentry), "it is on a clock")
	var seconds: int = definitions.stratagem("sentry_drop").sentry_seconds
	assert_eq(
		sim.query_machine_ticks_remaining(sentry),
		seconds * Simulation.TICKS_PER_SECOND - 1,
		"%d seconds of it, less the tick it arrived on — a Sentry does not act on the tick"
		% seconds
		+ " it was dropped, for the reason nothing else does"
	)
	assert_false(
		sim.query_machine_is_temporary(0), "where the Silo that dropped it stands until taken"
	)

	for _tick: int in range(seconds * Simulation.TICKS_PER_SECOND + 1):
		sim.step([])
	assert_eq(
		sim.query_machine_at_tile(here), -1, "and when its time is up it is gone"
	)
	assert_eq(sim.query_machine_count(), standing, "leaving the Factory as it found it")


func test_a_sentry_drop_painted_onto_occupied_ground_is_refused_before_the_channel() -> void:
	# The ground is checked before the commitment rather than after it, which is the whole
	# point of a refusal being a projection: a player who would have nowhere to put the Sentry
	# is told so while the Charges are still in the tube.
	var sim: Simulation = _loaded_silo_run("sentry_drop", 1)
	var definitions: Definitions = sim.query_definitions()

	# Stand a Turret on the tile the player is painting, under their feet.
	sim.step([
		InputAction.build_machine(
			0, definitions.machine_index("mg_turret_mk1"), _target(sim)
		)
	])
	assert_eq(
		sim.query_paint_refusal(0, _target(sim)),
		Simulation.Refusal.OCCUPIED,
		"there is already something standing there"
	)
	sim.step([InputAction.paint(0, _target(sim))])
	assert_false(sim.query_player_is_painting(0), "so no channel started")
	assert_eq(sim.query_silo_loaded_charges(0), 1, "and the Charge is still in the tube")
	assert_eq(sim.query_player_charges_wasted(0), 0, "nothing was wasted")


# ── A destroyed Silo loses its stockpile ──────────────────────────────────────

func test_a_destroyed_silo_loses_its_stockpile_and_its_load() -> void:
	# #11 established that a destroyed Machine's contents are lost, and argued why: a Machine
	# about to fall has to be worth *rescuing*, and there is no player standing there to pay.
	# A Silo is the most expensive thing that rule applies to, which is what makes a
	# breakthrough threaten the players' heaviest weapon and not just their smelters.
	var sim: Simulation = Simulation.new(7, 1, _fragile_content(), _lane_layout())
	_fed_silo(sim)
	_step_until_charges(sim, 3)
	assert_true(_load(sim, "artillery_barrage", 1), "the premise: loaded, with two banked")
	assert_eq(sim.query_silo_charges(0), 2)

	sim.step([InputAction.call_wave_early(0)])
	# Read the pockets *after* the lever, because pulling it pays a bounty — and what is being
	# asserted below is that the Silo paid nothing, not that nothing else did.
	var pockets: int = sim.query_player_item(0, "iron_plate")
	var ticks: int = 0
	while sim.query_machine_at_tile(Vector3i(4, WorldGrid.GROUND_LAYER, 4)) != -1 and ticks < 6000:
		sim.step([])
		ticks += 1
	if not assert_true(ticks < 6000, "the premise: a Breaker chewed the Silo down"):
		return

	assert_eq(
		sim.query_player_item(0, "iron_plate"),
		pockets,
		"and handed nothing back: not the build cost, not the plate in its buffer"
	)
	assert_eq(
		sim.query_paint_refusal(0, _target(sim)),
		Simulation.Refusal.NOTHING_LOADED,
		"the load went with it"
	)

	# Rebuilt, it is a Silo that has never assembled anything.
	sim.step([
		InputAction.build_machine(
			0,
			sim.query_definitions().machine_index("silo_mk1"),
			Vector3i(4, WorldGrid.GROUND_LAYER, 4)
		)
	])
	var rebuilt: int = sim.query_machine_at_tile(Vector3i(4, WorldGrid.GROUND_LAYER, 4))
	if not assert_true(rebuilt != -1, "a Silo can be rebuilt: you repair the living and"
			+ " rebuild the dead"):
		return
	assert_eq(sim.query_silo_charges(rebuilt), 0, "with nothing banked")
	assert_eq(sim.query_silo_loaded_charges(rebuilt), 0, "and nothing in the tube")


## Content whose Silo a single Breaker can chew down inside a test, and a Wave made of one.
## Nothing else about it differs — the point is the destruction, not how long it takes.
func _fragile_content() -> Definitions:
	var tuning: String = _read("res://content/tuning.toml").replace(SHIPPED_STOCK, STOCKED)
	tuning = tuning.replace(SHIPPED_DIAL_REACH, REACHABLE_DIAL_REACH)
	tuning = tuning.replace(SHIPPED_TELEGRAPH, QUICK_TELEGRAPH)
	return Definitions.parse(
		SILO_MACHINES.replace("silo,4,4,0,0,900", "silo,4,4,0,0,120"),
		SILO_RECIPES,
		tuning,
		ONE_BREAKER,
		DELIVERIES,
		_read("res://content/gear.csv"),
		_read("res://content/stratagems.csv"),
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv",
		"deliveries.csv",
		"gear.csv",
		"stratagems.csv"
	)


const ONE_BREAKER: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
siege_breakers,breaker,0,1,0,1
"""


# ── Save and load ─────────────────────────────────────────────────────────────

func test_a_stockpile_a_load_and_a_painting_in_flight_round_trip_through_save_and_load() -> void:
	var sim: Simulation = _loaded_silo_run("artillery_barrage", 2)
	# Catch the Painting mid-channel, which is the hard case: a channel half-served is a
	# distinct state from one at either end, and the Charges it is carrying have already left
	# the Silo.
	for _tick: int in range(90):
		sim.step([InputAction.paint(0, _target(sim))])
	_step_until_charges(sim, 1)

	assert_true(sim.query_player_is_painting(0), "the premise: a Painting is in flight")
	assert_true(sim.query_player_paint_ticks_served(0) > 0, "part way through")
	assert_true(sim.query_silo_charges(0) > 0, "with a stockpile behind it")

	var loaded: RunSave.Load = RunSave.deserialise(
		RunSave.serialise(sim), sim.query_definitions()
	)
	if not assert_false(loaded.has_errors(), loaded.describe_errors()):
		return
	assert_eq(loaded.simulation.hash(), sim.hash(), "the whole Run, to the integer")
	assert_eq(
		loaded.simulation.query_player_paint_ticks_served(0),
		sim.query_player_paint_ticks_served(0),
		"including how far through the channel is"
	)
	assert_eq(
		loaded.simulation.query_player_paint_charges(0),
		2,
		"and what it is carrying"
	)
	assert_eq(loaded.simulation.query_silo_charges(0), sim.query_silo_charges(0))

	# And it goes on from there identically: the resumed Run finishes the same Painting.
	var resumed: Simulation = loaded.simulation
	for _tick: int in range(400):
		sim.step([InputAction.paint(0, _target(sim))])
		resumed.step([InputAction.paint(0, _target(resumed))])
	assert_eq(resumed.hash(), sim.hash(), "tick for tick, afterwards")


func test_the_dial_and_what_interruption_has_cost_reach_the_hash() -> void:
	# State that is not hashed is state whose divergence the harness cannot see.
	var sim: Simulation = _sim()
	_fed_silo(sim)
	var before: int = sim.hash()
	sim.step([
		InputAction.set_silo_dial(0, sim.query_definitions().stratagem_index("supply_drop"), 3)
	])
	var control: Simulation = _sim()
	_fed_silo(control)
	control.step([])
	assert_ne(sim.hash(), control.hash(), "winding the dial is a change to the Run")
	assert_ne(sim.hash(), before, "and not a no-op")

	var wasted: Simulation = _loaded_silo_run("artillery_barrage", 1)
	var untouched: Simulation = _loaded_silo_run("artillery_barrage", 1)
	wasted.step([InputAction.paint(0, _target(wasted))])
	untouched.step([])
	wasted.step([])
	untouched.step([])
	assert_eq(wasted.query_player_charges_wasted(0), 1, "the premise: one Charge lost")
	assert_ne(
		wasted.hash(),
		untouched.hash(),
		"and a Run that has thrown a Charge away is not in the same state as one that has not"
	)

# ── Replay fixtures ───────────────────────────────────────────────────────────
#
# Two of them, and the pair is the point: a Charge assembled and **fired**, and a Painting
# **interrupted**. Each has an honesty check beside it that runs the same script and asserts
# the thing actually happened — because a replay of a Run in which nothing was ever loaded
# would read as a passing determinism test, and an interruption is exactly the kind of event
# it is easy to assume from an effect that failed to arrive.
#
# They run on the starter Map, which is what `DeterminismHarness.record` builds, and they
# carry their own `Definitions`: the shipped Silo Recipe is a plate and twenty rounds, which
# is an Ammo Press and a minute of game time before the first Charge. `verify` compares the
# digest it recorded under before it compares a single tick, so a fixture cannot quietly pass
# against content that has since changed.

## Content for the fixtures: the shipped tables, with the Silo's Recipe fed straight off ore
## so that one Miner and one Belt are the whole supply line, a grid that can pay for both,
## and a Delivery chain that locks no Stratagem. Everything else — the Silo's footprint, its
## capacity, its hit points, the three Stratagems and what each one does — is the real file's.
func _fixture_content() -> Definitions:
	var tuning: String = _read("res://content/tuning.toml")
	tuning = tuning.replace(SHIPPED_DIAL_REACH, REACHABLE_DIAL_REACH)
	tuning = tuning.replace("baseline_supply_kw = 300", "baseline_supply_kw = 1200")
	return Definitions.parse(
		_read("res://content/machines.csv"),
		_read("res://content/recipes.csv").replace(
			"assemble_charge,Assemble Charge,iron_plate:1;ammunition:20,,20",
			"assemble_charge,Assemble Charge,iron_ore:1,,0.5"
		),
		tuning,
		_read("res://content/waves.csv"),
		DELIVERIES,
		_read("res://content/gear.csv"),
		_read("res://content/stratagems.csv"),
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv",
		"deliveries.csv",
		"gear.csv",
		"stratagems.csv"
	)


## The artillery supply line, on the starter Map, within arm's reach of where a player stands
## at tick 0.
##
## The Silo covers (1,-2) to (4,1), so its west face is two metres from the origin the player
## opens on — close enough to work the dial without walking, which keeps the fixture about
## the Silo rather than about pathing. A Miner sits on the Depth 1 ore at (4,4) and one Belt
## runs from the tile past its north edge into the Silo's south face. Sixty-eight plate of the
## opening eighty.
func _supply_line() -> Array:
	var definitions: Definitions = _fixture_content()
	var ground: int = WorldGrid.GROUND_LAYER
	return [
		InputAction.build_machine(
			0, definitions.machine_index("silo_mk1"), Vector3i(1, ground, -2)
		),
		InputAction.build_machine(
			0, definitions.machine_index("miner_mk1"), Vector3i(4, ground, 4)
		),
		InputAction.build_belt(0, Vector3i(4, ground, 3), Vector3i(4, ground, 2)),
	]


## The fixture script: stand the line up, wait for a Charge, commit it to a Supply Drop, and
## paint the ground underfoot until it lands.
##
## A Supply Drop rather than a Barrage, because what it resolves into is observable without a
## Wave: rounds and plate in the player's own pockets. The three-second channel is the
## shipped row's.
func _firing_script() -> InputScript:
	var definitions: Definitions = _fixture_content()
	var supply: int = definitions.stratagem_index("supply_drop")
	var silo: Vector3i = Vector3i(1, WorldGrid.GROUND_LAYER, -2)
	var here: Vector3i = Vector3i(0, WorldGrid.GROUND_LAYER, 0)

	var script: InputScript = InputScript.new()
	script.add_tick(_supply_line())
	script.add_idle_ticks(600)
	script.add_tick([InputAction.set_silo_dial(0, supply, 2)])
	script.add_tick([InputAction.load_silo(0, silo, supply, 2)])
	for _tick: int in range(240):
		script.add_tick([InputAction.paint(0, here)])
	script.add_idle_ticks(60)
	return script


## The same thing, let go of eleven ticks short. Everything up to the release is identical to
## the fixture above, which is what makes the pair readable: one Run fires and one wastes it.
func _interrupted_script() -> InputScript:
	var definitions: Definitions = _fixture_content()
	var supply: int = definitions.stratagem_index("supply_drop")
	var silo: Vector3i = Vector3i(1, WorldGrid.GROUND_LAYER, -2)
	var here: Vector3i = Vector3i(0, WorldGrid.GROUND_LAYER, 0)

	var script: InputScript = InputScript.new()
	script.add_tick(_supply_line())
	script.add_idle_ticks(600)
	script.add_tick([InputAction.set_silo_dial(0, supply, 2)])
	script.add_tick([InputAction.load_silo(0, silo, supply, 2)])
	for _tick: int in range(169):
		script.add_tick([InputAction.paint(0, here)])
	script.add_idle_ticks(120)
	return script


func test_determinism_a_charge_assembled_and_fired_replays_identically() -> void:
	var recording: ReplayRecording = DeterminismHarness.record(
		_firing_script(), 17, 1, _fixture_content()
	)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_the_firing_fixture_really_did_assemble_a_charge_and_fire_it() -> void:
	var sim: Simulation = Simulation.new(17, 1, _fixture_content(), MapLayout.starter())
	var script: InputScript = _firing_script()
	var banked: int = 0
	var committed: int = 0
	var channelled: int = 0
	for tick: int in range(script.tick_count()):
		sim.step(script.actions_at(tick))
		banked = maxi(banked, sim.query_silo_charges(0))
		committed = maxi(committed, sim.query_silo_loaded_charges(0))
		channelled = maxi(channelled, sim.query_player_paint_ticks_served(0))

	assert_true(banked >= 2, "the Factory assembled Charges: %d of them" % banked)
	assert_eq(committed, 2, "two were committed to the tube")
	assert_true(channelled > 0, "a Painting was channelled")
	assert_eq(sim.query_player_charges_wasted(0), 0, "and never interrupted")
	assert_eq(sim.query_player_paint_interrupted_tick(0), -1)
	assert_eq(
		sim.query_player_item(0, "ammunition"),
		80,
		"so two Charges of Supply Drop landed: 40 rounds each, out of a Run that opened with"
		+ " none at all"
	)
	assert_eq(sim.query_silo_loaded_charges(0), 0, "and the tube is empty again")


func test_determinism_a_painting_interrupted_replays_identically() -> void:
	var recording: ReplayRecording = DeterminismHarness.record(
		_interrupted_script(), 17, 1, _fixture_content()
	)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_the_interrupted_fixture_really_was_interrupted_and_really_did_cost_a_charge() -> void:
	# The honesty check that matters most in this file. An interruption is easy to *assume*
	# from an effect that did not arrive, so this proves it three ways: the channel was
	# genuinely under way, the interruption is recorded with the tick it happened on, and the
	# Charges are accounted for as lost rather than merely missing.
	var sim: Simulation = Simulation.new(17, 1, _fixture_content(), MapLayout.starter())
	var script: InputScript = _interrupted_script()
	var channelled: int = 0
	var required: int = 0
	for tick: int in range(script.tick_count()):
		sim.step(script.actions_at(tick))
		channelled = maxi(channelled, sim.query_player_paint_ticks_served(0))
		required = maxi(required, sim.query_player_paint_ticks_required(0))

	assert_eq(required, 180, "the shipped Supply Drop channels three seconds")
	assert_true(
		channelled > 0 and channelled < required,
		"the channel ran and then stopped short: %d of %d ticks" % [channelled, required]
	)
	assert_true(
		sim.query_player_paint_interrupted_tick(0) >= 0,
		"the interruption is recorded, with the tick it happened on"
	)
	assert_eq(
		sim.query_player_charges_wasted(0), 2, "and both Charges are accounted for as lost"
	)
	assert_eq(
		sim.query_player_item(0, "ammunition"),
		0,
		"nothing was delivered: an interrupted Painting produces nothing at all"
	)
	assert_eq(sim.query_silo_loaded_charges(0), 0, "and the tube is empty, with nothing to show")

# ── The diegetic controls, and reading them ───────────────────────────────────
#
# DESIGN.md names Silo loading and Painting first in its list of diegetic controls, and the
# half of that which is already true is the half that matters: both are weighty, infrequent
# and operated at a place, and neither is a menu. What is still a key rather than a crank is
# the mechanism and its hero sound, which DESIGN.md says an art pass owes each of them.
#
# These test the input producer, which is a pure function of a device sample and a Simulation,
# and the HUD text, which is where the commitment has to be legible before it is made.

func _only_of_kind(actions: Array, kind: int) -> InputAction:
	var found: InputAction = null
	for action: InputAction in actions:
		if action.kind == kind:
			if found != null:
				return null
			found = action
	return found


func test_the_dial_keys_wind_the_shell_and_the_charge_counter_and_commit_nothing() -> void:
	var sim: Simulation = _sim()
	_fed_silo(sim)
	var controller: PlayerController = PlayerController.new()
	var sample: PlayerController.DeviceSample = PlayerController.DeviceSample.new()
	var opening: String = sim.query_player_dial_stratagem(0)

	sample.silo_shell_cycled = true
	var actions: Array = controller.actions_for_tick(sim, 0, sample)
	var dial: InputAction = _only_of_kind(actions, InputAction.Kind.SET_SILO_DIAL)
	if not assert_not_null(dial, "one press is one click of the selector"):
		return
	assert_null(
		_only_of_kind(actions, InputAction.Kind.LOAD_SILO),
		"and it commits nothing: winding a dial is not loading a Silo"
	)

	sim.step(actions)
	assert_ne(sim.query_player_dial_stratagem(0), opening, "the selector moved")
	assert_true(
		sim.query_definitions().has_stratagem(sim.query_player_dial_stratagem(0)),
		"to another real position"
	)

	# Round the ring and back, so the dial is a ring rather than a one-way ratchet.
	var seen: PackedStringArray = PackedStringArray([opening, sim.query_player_dial_stratagem(0)])
	for _press: int in range(sim.query_stratagem_count() - 1):
		sim.step(controller.actions_for_tick(sim, 0, sample))
		var here: String = sim.query_player_dial_stratagem(0)
		if seen.find(here) == -1:
			seen.append(here)
	assert_eq(
		seen.size(), sim.query_stratagem_count(), "every unlocked position is reachable"
	)
	assert_eq(sim.query_player_dial_stratagem(0), opening, "and the ring comes back round")

	# The counter, likewise: up to the stop and then back to one.
	sample.silo_shell_cycled = false
	sample.silo_charges_cycled = true
	var stop: int = sim.query_max_charges_per_load()
	for expected: int in range(2, stop + 1):
		sim.step(controller.actions_for_tick(sim, 0, sample))
		assert_eq(sim.query_player_dial_charges(0), expected, "the counter clicks up")
	sim.step(controller.actions_for_tick(sim, 0, sample))
	assert_eq(sim.query_player_dial_charges(0), 1, "and wraps at the stop")


func test_the_load_key_is_an_edge_that_commits_what_the_dial_reads() -> void:
	var sim: Simulation = _sim()
	_fed_silo(sim)
	_step_until_charges(sim, 3)
	var controller: PlayerController = PlayerController.new()
	var sample: PlayerController.DeviceSample = PlayerController.DeviceSample.new()

	assert_null(
		_only_of_kind(
			controller.actions_for_tick(sim, 0, sample), InputAction.Kind.LOAD_SILO
		),
		"nothing is sent while the key is up"
	)

	var sentry: int = sim.query_definitions().stratagem_index("sentry_drop")
	sim.step([InputAction.set_silo_dial(0, sentry, 2)])

	sample.load_silo_clicked = true
	var load: InputAction = _only_of_kind(
		controller.actions_for_tick(sim, 0, sample), InputAction.Kind.LOAD_SILO
	)
	if not assert_not_null(load, "one press is one commitment"):
		return
	assert_eq(load.load_stratagem_index(), sentry, "carrying the shell the dial is set to")
	assert_eq(load.load_charges(), 2, "and the count it is wound to")
	assert_eq(
		load.load_silo_tile(),
		PlayerController.silo_tile_for_loading(sim, 0),
		"aimed at the Silo through the one function the HUD asks as well, so the reason on"
		+ " screen is about the Silo the key means"
	)
	assert_true(
		sim.query_machine_is_silo(sim.query_machine_at_tile(load.load_silo_tile())),
		"and that tile has a Silo on it"
	)


func test_the_paint_key_is_held_and_targets_the_tile_the_player_is_standing_on() -> void:
	var sim: Simulation = _loaded_silo_run("artillery_barrage", 1)
	var controller: PlayerController = PlayerController.new()
	var sample: PlayerController.DeviceSample = PlayerController.DeviceSample.new()

	assert_null(
		_only_of_kind(controller.actions_for_tick(sim, 0, sample), InputAction.Kind.PAINT),
		"nothing is sent while the key is up"
	)

	sample.paint_held = true
	var first: InputAction = _only_of_kind(
		controller.actions_for_tick(sim, 0, sample), InputAction.Kind.PAINT
	)
	if not assert_not_null(first, "held, so it is sent"):
		return
	assert_eq(
		first.paint_tile(), _target(sim), "on the tile under the player's own feet"
	)
	assert_ne(
		first.paint_tile(),
		BuildGun.aimed_tile(sim, 0),
		"and emphatically not on the tile they are looking at: a player must stand at the"
		+ " target, so there is nothing here for a camera ray to decide"
	)
	assert_not_null(
		_only_of_kind(controller.actions_for_tick(sim, 0, sample), InputAction.Kind.PAINT),
		"and again next tick, because a channel is held rather than latched"
	)

	sample.paint_held = false
	assert_null(
		_only_of_kind(controller.actions_for_tick(sim, 0, sample), InputAction.Kind.PAINT),
		"letting go stops sending it, which is how a player interrupts themselves"
	)


func test_the_hud_says_what_is_about_to_be_committed_before_it_is_committed() -> void:
	# The reason the refusal is a projection: a load cannot be taken back, so the whole
	# bargain depends on the reason being on screen *before* the key goes down.
	var sim: Simulation = _sim()
	_fed_silo(sim)
	var view: WorldView = WorldView.new()

	view.sync(sim)
	assert_true(
		view.hud_text().contains("dial "), "the dial is on screen: %s" % view.hud_text()
	)
	assert_true(
		view.hud_text().contains("not enough charges assembled"),
		"and an empty Silo says so rather than waiting to be pressed: %s" % view.hud_text()
	)

	_step_until_charges(sim, 2)
	view.sync(sim)
	assert_true(
		view.hud_text().contains("charges 2/4"),
		"the stockpile is readable off the Silo's own line: %s" % view.hud_text()
	)

	_load(sim, "sentry_drop", 2)
	view.sync(sim)
	assert_true(
		view.hud_text().contains("LOADED sentry_drop x2"),
		"and what is in the tube, in capitals: %s" % view.hud_text()
	)
	assert_true(
		view.hud_text().contains("already loaded"),
		"with the refusal that makes the irreversibility legible: %s" % view.hud_text()
	)

	sim.step([InputAction.paint(0, _target(sim))])
	view.sync(sim)
	assert_true(
		view.hud_text().contains("PAINTING sentry_drop x2"),
		"a Painting is the loudest line on the HUD: %s" % view.hud_text()
	)
	assert_true(
		view.hud_text().contains("HOLD STILL"),
		"and it says what letting go costs: %s" % view.hud_text()
	)

	sim.step([])
	view.sync(sim)
	assert_true(
		view.hud_text().contains("charges wasted to interrupted paintings: 2"),
		"and afterwards, what it cost: %s" % view.hud_text()
	)
	view.free()


func test_a_charge_gauge_hangs_over_every_silo_and_over_nothing_else() -> void:
	# The Turret gauge's argument applied to the other number a player triages on: mid-Wave,
	# deciding whether to run for the Silo means knowing whether there is anything in it from
	# thirty metres away.
	var sim: Simulation = _sim()
	var view: WorldView = WorldView.new()

	view.sync(sim)
	assert_eq(view.silo_gauge_count(), 0, "no Silo, no gauge")

	_fed_silo(sim)
	view.sync(sim)
	assert_eq(view.silo_gauge_count(), 1, "one per Silo")
	assert_eq(view.turret_gauge_count(), 0, "and none over a Miner")
	assert_eq(view.silo_gauge_width_metres(0), 0.0, "an empty Silo draws no fill")
	assert_eq(
		view.silo_gauge_backing_colour(0),
		WorldView.CHARGE_EMPTY,
		"and its backing goes red, so absence of a bar means there is no Silo there"
	)

	_step_until_charges(sim, 4)
	view.sync(sim)
	assert_true(view.silo_gauge_width_metres(0) > 0.0, "a full Silo draws a full bar")
	assert_eq(view.silo_gauge_backing_colour(0), WorldView.CHARGE_BACKING)

	_load(sim, "artillery_barrage", 2)
	view.sync(sim)
	assert_eq(
		view.silo_gauge_fill_colour(0),
		WorldView.CHARGE_LOADED,
		"and a loaded one reads differently, because what is in the tube is already spent"
	)
	view.free()

