## Depth: the tier a Node sits at, the Miner tier that can reach it, what reaching
## deeper costs in Power and Heat, and the Breach it opens.
##
## The claim this file stands behind is that **greed rearranges the Map a player has to
## defend**. Deeper ore is richer, but it needs a better Miner, it draws more Power, it
## raises more Heat, and sustained extraction from it opens a new Breach near the mine —
## so reaching for better ore is a decision with geography attached rather than an
## upgrade. Everything here goes through the Simulation façade, which is the only seam.
extends TestCase

## recipes.csv gives mine_iron_ore a duration of 1.5 s against 60 ticks a second, so a
## Miner of any tier finishes one craft every 90 ticks. Every expected value below is
## worked from those two numbers.
const TICKS_PER_CRAFT: int = 90



## A tuning override that takes the Power grid out of the picture, for the tests whose
## subject is something other than the brownout a deep Miner causes.
func _plentiful_power() -> Array:
	return [PackedStringArray(["baseline_supply_kw = 300", "baseline_supply_kw = 9000"])]


## The shipped content, with `overrides` applied to the tuning file as plain text
## substitutions. Every number not named is the real file's, so a test that cares about
## one key is still reading the balance the game ships.
func _content(overrides: Array = []) -> Definitions:
	var fixture: ContentFixture = ContentFixture.for_case(self)
	fixture.deliveries = DELIVERIES
	fixture.gear = GEAR
	fixture.stratagems = STRATAGEMS
	return fixture.tune(overrides).stock(STOCKED_BILL).definitions()


## A Map with one iron Node at each of three Depths and no Breach, so Depth can be
## studied without a Wave arriving to interrupt. The Nest is far to the north-west, out
## of the way of anything a test builds.
func _depth_layout() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(-30, WorldGrid.GROUND_LAYER, -30)
	layout.add_node(Vector3i(0, WorldGrid.GROUND_LAYER, 0), "iron_ore", 1)
	layout.add_node(Vector3i(10, WorldGrid.GROUND_LAYER, 0), "iron_ore", 2)
	layout.add_node(Vector3i(20, WorldGrid.GROUND_LAYER, 0), "iron_ore", 3)
	layout.add_node(Vector3i(30, WorldGrid.GROUND_LAYER, 0), "iron_ore", 3)
	layout.sort_nodes()
	return layout


func _sim(overrides: Array = []) -> Simulation:
	return Simulation.new(12, 1, _content(overrides), _depth_layout())


func _machine(sim: Simulation, id: String) -> int:
	return sim.query_definitions().machine_index(id)


## Puts a Miner of the given id on the first free Node at the given Depth and returns its
## index.
func _build_miner_at_depth(sim: Simulation, id: String, depth: int) -> int:
	for index: int in range(sim.query_node_count()):
		if sim.query_node_depth(index) != depth:
			continue
		if sim.query_machine_at_tile(sim.query_node_tile(index)) != -1:
			continue
		sim.step([InputAction.build_machine(0, _machine(sim, id), sim.query_node_tile(index))])
		return sim.query_machine_count() - 1
	assert_true(false, "the layout must hold a Node at Depth %d" % depth)
	return -1


func _run(sim: Simulation, ticks: int) -> void:
	for tick: int in range(ticks):
		sim.step([])


# ── The tier gate ─────────────────────────────────────────────────────────────

func test_a_miner_cannot_extract_from_a_node_deeper_than_its_tier() -> void:
	var sim: Simulation = _sim()
	var shallow: int = _build_miner_at_depth(sim, "miner_mk1", 1)
	var deep: int = _build_miner_at_depth(sim, "miner_mk1", 2)
	_run(sim, TICKS_PER_CRAFT * 4)

	assert_eq(
		sim.query_machine_output(shallow, "iron_ore"),
		4,
		"miner_mk1 reaches Depth 1, so the shallow Node pays out"
	)
	assert_eq(
		sim.query_machine_output_total(deep),
		0,
		"and it does not reach Depth 2, so the deeper Node gives up nothing"
	)


func test_a_deeper_miner_tier_is_a_row_and_reaches_what_the_shallow_one_cannot() -> void:
	# miner_mk2 differs from miner_mk1 in `max_depth`, `power_draw_kw`, its Recipe and its
	# build cost, and in nothing else. Nothing in `sim/` names it, so a Mk3 and a Mk4 are
	# rows in the same sense a Cannon Turret is.
	# On a grid with room to spare, so what is under study here is the tier and not the
	# brownout a deep Miner causes on the shipped baseline — that is its own test below.
	var sim: Simulation = _sim(_plentiful_power())
	var mk1: int = _build_miner_at_depth(sim, "miner_mk1", 3)
	var mk2: int = _build_miner_at_depth(sim, "miner_mk2", 2)
	_run(sim, TICKS_PER_CRAFT * 4)
	assert_eq(sim.query_machine_output_total(mk1), 0, "Mk1 still cannot reach Depth 3")
	assert_eq(
		sim.query_machine_output(mk2, "iron_ore"),
		12,
		"Mk2 reaches Depth 2 and mine_iron_ore_deep brings up three ore a craft"
	)


func test_a_miner_over_ore_it_cannot_reach_reports_itself_starved() -> void:
	# Starved rather than silently idle, because that is the word the rest of the Factory
	# already uses for "this Machine has no input": the HUD lists it, it is off the Power
	# grid, and a player is told why their new Miner is not producing.
	var sim: Simulation = _sim()
	var out_of_reach: int = _build_miner_at_depth(sim, "miner_mk1", 3)
	var in_reach: int = _build_miner_at_depth(sim, "miner_mk3", 3)
	_run(sim, 2)
	assert_true(sim.query_machine_is_starved(out_of_reach), "Mk1 over Depth 3 ore is starved")
	assert_false(sim.query_machine_is_starved(in_reach), "Mk3 over the same Depth is fed")


# ── What Depth costs in Power ─────────────────────────────────────────────────

func test_deeper_extraction_draws_proportionally_more_power() -> void:
	# Worked from the files: machines.csv gives miner_mk3 a `power_draw_kw` of 320 and
	# tuning.toml a `depth.draw_percent_per_depth` of 60. The first tier is the quoted
	# draw, and every tier past it adds 60% of that — so 320 at Depth 1, 512 at Depth 2
	# and 704 at Depth 3.
	var shallow: Simulation = _sim()
	var mid: Simulation = _sim()
	var deep: Simulation = _sim()
	var at_one: int = _build_miner_at_depth(shallow, "miner_mk3", 1)
	var at_two: int = _build_miner_at_depth(mid, "miner_mk3", 2)
	var at_three: int = _build_miner_at_depth(deep, "miner_mk3", 3)
	_run(shallow, 2)
	_run(mid, 2)
	_run(deep, 2)

	assert_eq(shallow.query_machine_power_draw_kw(at_one), 320, "Depth 1 draws what the row says")
	assert_eq(mid.query_machine_power_draw_kw(at_two), 512, "Depth 2 adds 60% of it")
	assert_eq(deep.query_machine_power_draw_kw(at_three), 704, "Depth 3 adds that again")


func test_what_depth_costs_in_power_is_what_the_one_grid_is_charged() -> void:
	# The per-Machine figure is not a second opinion: it is the number the grid totals, so
	# a deep mine browns out the Factory rather than quietly drawing for free.
	var sim: Simulation = _sim()
	var deep: int = _build_miner_at_depth(sim, "miner_mk3", 3)
	_run(sim, 2)
	assert_eq(sim.query_power_demand_kw(), sim.query_machine_power_draw_kw(deep))
	assert_eq(sim.query_power_demand_kw(), 704, "one deep Miner, and the grid feels all of it")
	assert_true(
		sim.query_power_is_in_deficit(),
		"power.baseline_supply_kw is 300, so one Depth 3 Miner alone browns the Factory out"
	)


func test_a_miner_out_of_its_depth_is_not_on_the_power_grid_at_all() -> void:
	# `_machine_would_work` is the single predicate behind what the grid bills, what
	# advances and what a query calls starved, so a Miner that cannot reach its ore costs
	# nothing — the same rule a Smelter with an empty Belt obeys.
	var sim: Simulation = _sim()
	var out_of_reach: int = _build_miner_at_depth(sim, "miner_mk1", 3)
	_run(sim, 2)
	assert_eq(sim.query_power_demand_kw(), 0, "nothing on this Map is working")
	assert_eq(sim.query_machine_power_draw_kw(out_of_reach), 0)


func test_the_power_a_deep_miner_draws_throttles_it_on_the_shipped_grid() -> void:
	# The cost is not bookkeeping. machines.csv gives miner_mk2 a draw of 200 kW, Depth 2
	# makes that 320, and `power.baseline_supply_kw` is 300 — so the Factory's own small
	# plant can no longer carry one Miner, and the Factory sags together while it digs.
	# Over 360 ticks the duty cycle buys floor(360 * 300 / 320) = 337 ticks of work, which
	# is three whole 90-tick crafts and not four.
	var sim: Simulation = _sim()
	var deep: int = _build_miner_at_depth(sim, "miner_mk2", 2)
	_run(sim, TICKS_PER_CRAFT * 4)
	assert_true(sim.query_machine_is_throttled(deep), "a deep Miner outruns the baseline plant")
	assert_eq(sim.query_machine_output(deep, "iron_ore"), 9, "three crafts at three ore each")

	var shallow: Simulation = _sim()
	var fine: int = _build_miner_at_depth(shallow, "miner_mk1", 1)
	_run(shallow, TICKS_PER_CRAFT * 4)
	assert_false(shallow.query_machine_is_throttled(fine), "the opening Miner still fits")


# ── What Depth costs in Heat ───────────────────────────────────────────────────

func test_deeper_extraction_contributes_proportionally_more_heat() -> void:
	# There is **one** Depth term in Heat and #12 already shipped it: `heat.per_craft` is 2
	# and `heat.per_craft_per_depth` is 1, so a craft off a Depth 1 Node is worth 3 units
	# and one off a Depth 3 Node is worth 5. This ticket deliberately adds no second term —
	# a Depth surcharge counted twice would make the gauge disagree with the arithmetic a
	# player can do in their head, which is the whole value of Heat being made of crafts.
	var sim: Simulation = _sim(_plentiful_power())
	var shallow: int = _build_miner_at_depth(sim, "miner_mk1", 1)
	var deep: int = _build_miner_at_depth(sim, "miner_mk3", 3)
	_run(sim, TICKS_PER_CRAFT * 4)

	assert_eq(sim.query_machine_output(shallow, "iron_ore"), 4, "four shallow crafts")
	assert_eq(sim.query_machine_output(deep, "iron_ore"), 12, "and four deep ones")
	assert_eq(sim.query_machine_heat_units(shallow), 12, "4 crafts x (2 + 1 x 1)")
	assert_eq(sim.query_machine_heat_units(deep), 20, "4 crafts x (2 + 1 x 3)")
	assert_true(
		sim.query_machine_heat_units(deep) > sim.query_machine_heat_units(shallow),
		"digging deeper is louder, and a player can read which Machine did it"
	)


# ── The Breach deep mining opens ───────────────────────────────────────────────

## The Depth tuning with the two slow numbers shortened: three deep crafts open a Breach
## and its Telegraph runs for two seconds. Both are the shipped mechanism at a scale a
## test can watch; `test_the_shipped_numbers_*` below reads the real figures.
func _quick_breach() -> Array:
	return [
		PackedStringArray(["baseline_supply_kw = 300", "baseline_supply_kw = 9000"]),
		PackedStringArray(["breach_crafts = 40", "breach_crafts = 3"]),
		PackedStringArray(["breach_telegraph_seconds = 45", "breach_telegraph_seconds = 2"]),
	]


func test_sustained_deep_extraction_opens_a_new_breach_near_that_mine() -> void:
	var sim: Simulation = _sim(_quick_breach())
	assert_eq(sim.query_breach_count(), 0, "this Map opens with nowhere for Enemies to enter")
	var deep: int = _build_miner_at_depth(sim, "miner_mk2", 2)
	var mine: Vector3i = sim.query_machine_tile(deep)

	_run(sim, TICKS_PER_CRAFT * 2)
	assert_eq(sim.query_pending_breach_count(), 0, "two deep crafts is not yet sustained")
	assert_eq(sim.query_breach_count(), 0)

	_run(sim, TICKS_PER_CRAFT)
	assert_eq(sim.query_pending_breach_count(), 1, "the third deep craft opens one")
	# `depth.breach_offset_tiles` is 6 and the ring is scanned in the Map's own canonical
	# tile order — ascending x, then ascending z — so the hole lands on the north-west
	# corner of the square six tiles out from the mine. Predictable, because a Breach a
	# player cannot plan for is not fortifiable (GLOSSARY.md).
	assert_eq(
		sim.query_pending_breach_tile(0),
		Vector3i(mine.x - 6, WorldGrid.GROUND_LAYER, mine.z - 6),
		"six tiles from the mine that caused it"
	)

	_run(sim, Simulation.TICKS_PER_SECOND * 2)
	assert_eq(sim.query_pending_breach_count(), 0, "the warning has run out")
	assert_eq(sim.query_breach_count(), 1, "and the Breach is now on the Map")
	assert_eq(sim.query_breach_tile(0), Vector3i(mine.x - 6, WorldGrid.GROUND_LAYER, mine.z - 6))


func test_a_newly_opened_breach_is_telegraphed_before_it_first_spawns() -> void:
	# The acceptance criterion in its own words. A Breach appearing silently next to a
	# player's base is the ambush the Telegraph exists to prevent, so the warning is a gate
	# and not a courtesy: for every tick of it the Breach count stays where it was, so there
	# is no tick on which anything could have come out.
	var sim: Simulation = _sim(_quick_breach())
	var deep: int = _build_miner_at_depth(sim, "miner_mk2", 2)
	assert_true(deep >= 0, "the deep Miner is standing")
	_run(sim, TICKS_PER_CRAFT * 3)
	assert_eq(sim.query_pending_breach_count(), 1, "announced")

	var telegraph: int = Simulation.TICKS_PER_SECOND * 2
	assert_eq(sim.query_pending_breach_ticks_remaining(0), telegraph, "the full warning, from zero")
	for tick: int in range(telegraph):
		assert_eq(
			sim.query_breach_count(),
			0,
			"nothing has entered the Map on tick %d of the warning" % tick
		)
		assert_eq(sim.query_pending_breach_ticks_remaining(0), telegraph - tick)
		assert_eq(sim.query_enemy_count(), 0, "and no Enemy is out")
		sim.step([])
	assert_eq(sim.query_breach_count(), 1, "the Breach opens on the tick the warning ends")


func test_one_node_opens_at_most_one_breach_however_long_it_is_mined() -> void:
	# Bounded on purpose. A forty-hour Run must not be able to ring itself with a hundred
	# holes, and the cap is per Node rather than per Run so that the second deep mine a
	# player opens still costs them something.
	var sim: Simulation = _sim(_quick_breach())
	var deep: int = _build_miner_at_depth(sim, "miner_mk2", 2)
	assert_true(deep >= 0, "the deep Miner is standing")
	_run(sim, TICKS_PER_CRAFT * 30)
	assert_eq(sim.query_breach_count(), 1, "thirty deep crafts, one Breach")
	assert_eq(sim.query_pending_breach_count(), 0, "and nothing more coming")


func test_shallow_extraction_opens_nothing() -> void:
	# `depth.breach_tier` is 2, so the ore a Run opens on is not a transgression. The
	# opening Factory must not be punished or the mechanic teaches the wrong lesson.
	var sim: Simulation = _sim(_quick_breach())
	var shallow: int = _build_miner_at_depth(sim, "miner_mk1", 1)
	_run(sim, TICKS_PER_CRAFT * 30)
	assert_eq(sim.query_machine_output(shallow, "iron_ore"), 30, "it has been mining steadily")
	assert_eq(sim.query_breach_count(), 0, "and it has drawn nothing to the Map")
	assert_eq(sim.query_pending_breach_count(), 0)


# ── The ordering discipline a runtime Breach has to keep ───────────────────────
# `MapLayout` sorts the starting Breaches into tile order and Enemies are released in that
# order, so which Breach goes first is geography. A Breach that joined the array by being
# appended would quietly change that to "the order somebody dug in" — and since serials are
# issued in release order, two clients whose Miners finished a craft in a different order
# would then disagree about which Crawler is which. These are the tests for that.

## A Map with two Depth 3 Nodes well apart, so a test can open two Breaches and choose which
## order it opens them in. Six tiles north-west of each is where they land, so the Node at x
## 20 opens the canonically *earlier* Breach.
func _two_deep_mines() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(-30, WorldGrid.GROUND_LAYER, -30)
	layout.add_node(Vector3i(20, WorldGrid.GROUND_LAYER, 0), "iron_ore", 3)
	layout.add_node(Vector3i(40, WorldGrid.GROUND_LAYER, 0), "iron_ore", 3)
	layout.sort_nodes()
	return layout


## Mines both Nodes of `_two_deep_mines`, starting with the one at the given x, and runs long
## enough for both Breaches to open.
func _dig_both(first_x: int) -> Simulation:
	var sim: Simulation = Simulation.new(5, 1, _content(_quick_breach()), _two_deep_mines())
	var second_x: int = 40 if first_x == 20 else 20
	for x: int in [first_x, second_x]:
		sim.step([
			InputAction.build_machine(
				0, _machine(sim, "miner_mk3"), Vector3i(x, WorldGrid.GROUND_LAYER, 0)
			)
		])
		_run(sim, TICKS_PER_CRAFT * 4 + Simulation.TICKS_PER_SECOND * 3)
	return sim


func test_a_breach_opened_at_runtime_joins_the_map_in_canonical_tile_order() -> void:
	var dug_east_first: Simulation = _dig_both(40)
	assert_eq(dug_east_first.query_breach_count(), 2, "both mines opened a hole")
	assert_eq(
		dug_east_first.query_breach_tile(0),
		Vector3i(14, WorldGrid.GROUND_LAYER, -6),
		"the lower tile is index 0 even though its mine was dug second"
	)
	assert_eq(dug_east_first.query_breach_tile(1), Vector3i(34, WorldGrid.GROUND_LAYER, -6))

	for index: int in range(1, dug_east_first.query_breach_count()):
		assert_true(
			MapLayout.tile_precedes(
				dug_east_first.query_breach_tile(index - 1), dug_east_first.query_breach_tile(index)
			),
			"the Breaches are still in ascending tile order"
		)


func test_which_breach_is_first_does_not_depend_on_which_mine_was_dug_first() -> void:
	# The determinism claim, stated as the thing a player could otherwise have changed by
	# accident: dig in the opposite order and the Map that results is the same Map.
	var east_first: Simulation = _dig_both(40)
	var west_first: Simulation = _dig_both(20)
	assert_eq(east_first.query_breach_count(), west_first.query_breach_count())
	for index: int in range(east_first.query_breach_count()):
		assert_eq(
			east_first.query_breach_tile(index),
			west_first.query_breach_tile(index),
			"Breach %d is the same tile whichever mine came first" % index
		)


func test_enemies_are_released_from_a_runtime_breach_in_breach_order() -> void:
	# Release order is Breach index order, and Breach index order is geography — so the first
	# serial of a Wave comes out of the canonically first Breach, whenever that Breach opened.
	var sim: Simulation = _dig_both(40)
	sim.step([InputAction.call_wave_early(0)])
	var guard: int = 0
	while sim.query_enemy_count() < 2 and guard < 20000:
		sim.step([])
		guard += 1
	assert_true(sim.query_enemy_count() >= 2, "a Wave came through both Breaches")
	assert_eq(
		sim.query_enemy_tile(0),
		sim.query_breach_tile(0),
		"the earliest serial came out of the canonically first Breach"
	)
	assert_eq(sim.query_enemy_tile(1), sim.query_breach_tile(1))


# ── The flowfield and a Breach that did not exist when it was built ────────────

func test_the_flowfield_routes_a_new_breach_without_disturbing_the_rest_of_it() -> void:
	# The field is a pure function of the Map's ground and the Machines standing on it. A
	# Breach is neither — it does not obstruct and it is not a destination — so the tile a new
	# Breach opens on already has a direction and a distance, and nothing about the opening
	# needs the field rebuilt. Asserted both ways: every tile sampled routes to exactly where
	# it did before, and the brand new Breach is routed too.
	var sim: Simulation = _sim(_quick_breach())
	var deep: int = _build_miner_at_depth(sim, "miner_mk2", 2)
	var mine: Vector3i = sim.query_machine_tile(deep)
	var opening: Vector3i = Vector3i(mine.x - 6, WorldGrid.GROUND_LAYER, mine.z - 6)

	var sampled: Array[Vector3i] = [
		Vector3i(0, WorldGrid.GROUND_LAYER, 0),
		Vector3i(-10, WorldGrid.GROUND_LAYER, -10),
		Vector3i(12, WorldGrid.GROUND_LAYER, 8),
		opening,
	]
	var before: PackedInt64Array = PackedInt64Array()
	for tile: Vector3i in sampled:
		before.append(sim.query_flow_distance_tiles(tile))
	assert_true(before[3] > 0, "the tile the Breach will open on is already routed to the Nest")

	_run(sim, TICKS_PER_CRAFT * 3 + Simulation.TICKS_PER_SECOND * 3)
	assert_eq(sim.query_breach_count(), 1, "the Breach is open")
	for slot: int in range(sampled.size()):
		assert_eq(
			sim.query_flow_distance_tiles(sampled[slot]),
			before[slot],
			"%s routes exactly as it did before the Breach opened" % sampled[slot]
		)
	assert_true(
		sim.query_flow_direction(opening) != -1,
		"and the new Breach has a way out towards the Nest"
	)


func test_an_enemy_out_of_a_new_breach_walks_the_shared_field_to_the_nest() -> void:
	# The behavioural half: an Enemy entering through a Breach that did not exist when the
	# field was built steers by that same field rather than by a path of its own.
	var sim: Simulation = _sim(_quick_breach())
	var deep: int = _build_miner_at_depth(sim, "miner_mk2", 2)
	assert_true(deep >= 0, "the deep Miner is standing")
	_run(sim, TICKS_PER_CRAFT * 3 + Simulation.TICKS_PER_SECOND * 3)
	assert_eq(sim.query_breach_count(), 1, "the Breach is open")

	sim.step([InputAction.call_wave_early(0)])
	var guard: int = 0
	while sim.query_enemy_count() == 0 and guard < 20000:
		sim.step([])
		guard += 1
	assert_true(sim.query_enemy_count() > 0, "a Wave came through the new Breach")

	var opened_at: int = sim.query_flow_distance_tiles(sim.query_enemy_tile(0))
	_run(sim, Simulation.TICKS_PER_SECOND * 4)
	assert_true(
		sim.query_flow_distance_tiles(sim.query_enemy_tile(0)) < opened_at,
		"it is closing on the Nest, which means it is reading the shared field"
	)


# ── The shipped Map and the shipped numbers ────────────────────────────────────

func test_the_starter_map_offers_depth_a_shipped_miner_cannot_reach() -> void:
	# A mechanic unreachable in the real game is a mechanic that does not exist. The shallow
	# ore on the starter Map is finite in number, so a Factory that wants to grow past three
	# Nodes has to reach for a deeper seam — and reaching is what the rest of this file costs.
	var sim: Simulation = Simulation.new(1, 1)
	var deepest: int = 0
	for index: int in range(sim.query_node_count()):
		deepest = maxi(deepest, sim.query_node_depth(index))
	assert_true(deepest >= 2, "the starter Map carries ore below Depth 1")
	assert_eq(
		sim.query_definitions().machine("miner_mk1").max_depth,
		1,
		"and the Miner a Run opens with cannot reach it"
	)


func test_the_shipped_numbers_open_a_breach_on_the_starter_map() -> void:
	# The shipped figures end to end, on the shipped Map: depth.breach_crafts is 40 and
	# depth.breach_telegraph_seconds is 45. A Depth 2 Miner draws 320 kW against a 300 kW
	# baseline plant, so the duty cycle stretches 40 crafts of 90 ticks out to 3840, and the
	# warning runs 2700 ticks behind that.
	#
	# The one thing not shipped is the Delivery chain, which locks Miner Mk2 behind two tiers
	# (`content/deliveries.csv`). Whether a Run has earned the licence to dig is a different
	# question from what digging costs, and these are the figures for the second — so the
	# fixture replaces the chain and leaves every number the test names alone.
	var sim: Simulation = _starter_sim(9)
	var seam: int = -1
	for index: int in range(sim.query_node_count()):
		if sim.query_node_depth(index) == 2:
			seam = index
			break
	assert_true(seam != -1, "the starter Map has a Depth 2 seam")
	var before: int = sim.query_breach_count()
	sim.step([
		InputAction.build_machine(
			0, _machine(sim, "miner_mk2"), sim.query_node_tile(seam)
		)
	])

	_run(sim, 3900)
	assert_eq(sim.query_pending_breach_count(), 1, "forty deep crafts announced a Breach")
	assert_eq(sim.query_breach_count(), before, "and the warning is still running")
	_run(sim, 2700)
	assert_eq(sim.query_breach_count(), before + 1, "it opened once the warning was served")
	# Six tiles north-west of the seam at (22, 10). It sorts *after* the Map's own Breach at
	# (16, -6) — same x, greater z — so it is index 1 and the original is still index 0, which
	# is the ordering discipline holding on the shipped Map rather than only in a fixture.
	assert_eq(sim.query_breach_tile(0), Vector3i(16, WorldGrid.GROUND_LAYER, -6))
	assert_eq(sim.query_breach_tile(1), Vector3i(16, WorldGrid.GROUND_LAYER, 4))


# ── Round-tripping, and the replay fixtures ────────────────────────────────────

func test_a_run_with_a_breach_half_telegraphed_round_trips_through_a_save() -> void:
	# The hardest moment to save: the count is part-way to its threshold on one Node, and a
	# Breach is announced with half its warning served. `RunSave` reflects over the
	# Simulation's own properties, so none of that needed a line in that file — but the
	# promise is a hash comparison, and this is where it has teeth.
	var content: Definitions = _content(_quick_breach())
	var sim: Simulation = Simulation.new(4, 1, content, _depth_layout())
	var deep: int = _build_miner_at_depth(sim, "miner_mk2", 2)
	assert_true(deep >= 0, "the deep Miner is standing")
	_run(sim, TICKS_PER_CRAFT * 3 + Simulation.TICKS_PER_SECOND)
	assert_eq(sim.query_pending_breach_count(), 1, "a Breach is announced")
	assert_true(
		sim.query_pending_breach_ticks_remaining(0) > 0, "with some of its warning still to run"
	)

	var loaded: RunSave.Load = RunSave.deserialise(
		RunSave.serialise(sim), content, Simulation.new(0, 1, content, MapLayout.empty())
	)
	assert_false(loaded.has_errors(), loaded.describe_errors())
	var resumed: Simulation = loaded.simulation
	assert_eq(resumed.hash(), sim.hash(), "a Run written out and read back is the same Run")
	assert_eq(resumed.query_pending_breach_ticks_remaining(0), sim.query_pending_breach_ticks_remaining(0))

	# And it keeps running the same way: the Breach opens on the same tick in both.
	_run(sim, Simulation.TICKS_PER_SECOND * 3)
	_run(resumed, Simulation.TICKS_PER_SECOND * 3)
	assert_eq(resumed.query_breach_count(), 1, "the resumed Run opened the Breach too")
	assert_eq(resumed.hash(), sim.hash(), "and stayed in step doing it")


func test_determinism_a_deep_miner_running_replays_identically() -> void:
	# The ticket's first replay fixture: a Mk2 Miner on the starter Map's Depth 2 seam,
	# throttled by the Power its Depth costs, raising the Heat its Depth costs, for long
	# enough to be sure the duty cycle and the deep-craft counter agree tick for tick. No
	# `Definitions` is passed, so the replay re-reads content/ and a change there is reported
	# as a definitions_mismatch rather than passing unnoticed.
	var sim: Simulation = Simulation.new(7, 1)
	var seam: Vector3i = Vector3i.ZERO
	for index: int in range(sim.query_node_count()):
		if sim.query_node_depth(index) == 2:
			seam = sim.query_node_tile(index)
			break

	var script: InputScript = InputScript.new()
	script.add_tick([InputAction.build_machine(0, _machine(sim, "miner_mk2"), seam)])
	script.add_idle_ticks(600)
	script.add_tick([InputAction.move(0, Fixed.ONE, 0)])
	script.add_idle_ticks(600)

	var recording: ReplayRecording = DeterminismHarness.record(script, 7, 1)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_a_new_breach_opening_and_being_telegraphed_replays_identically() -> void:
	# The ticket's second fixture, and the one that matters: the whole arc on the shipped
	# numbers — forty deep crafts, the announcement, the 45-second warning, the Breach joining
	# the Map in canonical order, and the Wave clock starting to count against two Breaches
	# instead of one. Every tick of it compared, because a fault that perturbs a few ticks and
	# settles back is still a desync.
	#
	# It carries its own definition set rather than letting the replay re-read `content/`,
	# because the Run it describes needs a Miner Mk2 the shipped Delivery chain has not
	# unlocked — which is exactly the case CLAUDE.md says to pass one for.
	var content: Definitions = _content()
	var sim: Simulation = Simulation.new(7, 1, content)
	var seam: Vector3i = Vector3i.ZERO
	for index: int in range(sim.query_node_count()):
		if sim.query_node_depth(index) == 2:
			seam = sim.query_node_tile(index)
			break

	var script: InputScript = InputScript.new()
	script.add_tick([InputAction.build_machine(0, _machine(sim, "miner_mk2"), seam)])
	script.add_idle_ticks(6700)

	var recording: ReplayRecording = DeterminismHarness.record(script, 7, 1, content)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())

	# The fixture has to actually contain the thing it claims to: a replay of a Run where
	# nothing happened would be just as identical.
	var replayed: Simulation = Simulation.new(7, 1, content)
	replayed.step([InputAction.build_machine(0, _machine(replayed, "miner_mk2"), seam)])
	_run(replayed, 6700)
	assert_eq(replayed.query_breach_count(), 2, "the Run really did open a second Breach")


# ── Fixtures that keep progression out of the way ─────────────────────────────
# The shipped Delivery chain locks the two deeper Miners behind its tiers, and a Run opens
# holding exactly the plates for one line (`content/deliveries.csv`, `content/tuning.toml`).
# This file is about what a Miner tier *reaches*, which is the question the chain is priced
# against rather than one it answers, so these fixtures replace both with a tier that locks
# nothing and a stock that pays for anything. `test_delivery.gd` is where the chain itself is
# asserted.

const STOCKED_BILL: String = "ammunition:400;coal:400;iron_ore:400;iron_plate:400"

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


const DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_opening,Opening Licence,1,iron_plate:1,,placeholder_gear,
"""


## A Run on the Map a Run starts on, reading that same content.
func _starter_sim(world_seed: int) -> Simulation:
	return Simulation.new(world_seed, 1, _content(), MapLayout.starter())


# ── Which ore a Run can actually work, and saying so ──────────────────────────
# #52. A Depth 2 seam that no Miner a Run owns can lift looks exactly like shallow iron,
# so the first thing a player may learn about Depth is a Miner that is silently starved.
# `query_node_is_workable_now` is the projection that lets a mark say which is which, and
# it is one answer rather than three because the mark and the objective line must not
# disagree about what is reachable.

func test_a_node_is_workable_when_some_unlocked_miner_could_lift_it() -> void:
	# The shipped Map: three Depth 1 Nodes, and seams at Depth 2 and Depth 3. A Run opens
	# with miner_mk1 and coal_miner_mk1, both Depth 1, so exactly the shallow three are
	# workable and the two seams are not.
	var sim: Simulation = Simulation.new(1, 1)
	var workable: int = 0
	var out_of_reach: int = 0
	for index: int in range(sim.query_node_count()):
		if sim.query_node_is_workable_now(index):
			assert_eq(
				sim.query_node_depth(index), 1, "only the shallow ore is within a Mk1's reach"
			)
			workable += 1
		else:
			assert_true(sim.query_node_depth(index) >= 2, "and the seams are the ones that are not")
			out_of_reach += 1
	assert_eq(workable, 3, "the three shallow Nodes")
	assert_eq(out_of_reach, 2, "and the two deeper seams")


func test_a_node_whose_resource_nothing_unlocked_mines_is_not_workable() -> void:
	# Depth is not the only reason a Node can be out of reach, and the projection answers
	# the question the mark asks rather than the Depth half of it: a Node yielding something
	# no unlocked Miner's Recipe produces is a Node nothing can work either.
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.add_node(Vector3i(6, 0, 0), "ammunition", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var iron: int = sim.query_node_at_tile(Vector3i(0, 0, 0))
	var nothing: int = sim.query_node_at_tile(Vector3i(6, 0, 0))
	assert_true(sim.query_node_is_workable_now(iron), "a Miner mines iron ore")
	assert_false(sim.query_node_is_workable_now(nothing), "and no Miner mines Ammunition")


func test_a_chain_that_unlocks_a_deeper_miner_makes_the_seam_workable() -> void:
	# The projection reads the Run's unlocks, which is what makes it a statement about this
	# Run rather than about `content/machines.csv`: the same Depth 2 seam is out of reach
	# under the shipped chain, which locks miner_mk2 behind `t02_deep_mining`, and in reach
	# under this file's chain, which locks nothing.
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 2)
	layout.sort_nodes()

	var shipped: Simulation = Simulation.new(1, 1, null, layout)
	assert_false(shipped.query_node_is_workable_now(0), "the shipped chain locks miner_mk2")

	var open_chain: Simulation = Simulation.new(1, 1, _content(), layout)
	assert_true(
		open_chain.query_node_is_workable_now(0), "and a chain that locks nothing frees the seam"
	)


func test_asking_which_ore_is_workable_does_not_move_the_hash() -> void:
	# A projection the Simulation never reads back, the standing `query_belt_end_is_connected`
	# has. A mark drawn from it must not be able to change the Run it is a mark about.
	var sim: Simulation = Simulation.new(1, 1)
	var before: int = sim.hash()
	for index: int in range(sim.query_node_count()):
		sim.query_node_is_workable_now(index)
	assert_eq(sim.hash(), before, "asking is a read")


# ── Which ore a player is being pointed at ────────────────────────────────────
# #52's scanner and #52's objective line both answer "where should I go and put a Miner",
# and they must answer it with the same Node — a trail of pings running out to one piece of
# ore while the line names another is two opinions about one question.

func test_the_nearest_ore_a_player_could_claim_is_the_one_they_are_pointed_at() -> void:
	# Nearest by distance from the player, not by index: the Map's canonical order is
	# geography and has nothing to say about where somebody is standing.
	var layout: MapLayout = MapLayout.empty()
	layout.nest_tile = Vector3i(0, 0, 0)
	layout.add_node(Vector3i(0, 0, 30), "iron_ore", 1)
	layout.add_node(Vector3i(0, 0, 8), "coal", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	assert_eq(
		sim.query_nearest_workable_node(0),
		sim.query_node_at_tile(Vector3i(0, 0, 8)),
		"the coal is nearer than the iron"
	)


func test_ore_out_of_reach_and_ore_already_built_on_are_not_offered() -> void:
	# Two reasons a Node is not somewhere to send a player, and the projection applies both:
	# a seam no unlocked Miner could lift, and ground that is already taken.
	var layout: MapLayout = MapLayout.empty()
	layout.nest_tile = Vector3i(0, 0, 0)
	layout.add_node(Vector3i(0, 0, 6), "iron_ore", 3)
	layout.add_node(Vector3i(0, 0, 14), "iron_ore", 1)
	layout.add_node(Vector3i(0, 0, 26), "coal", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	assert_eq(
		sim.query_nearest_workable_node(0),
		sim.query_node_at_tile(Vector3i(0, 0, 14)),
		"the Depth 3 seam is nearer and is not offered"
	)

	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("miner_mk1"), Vector3i(0, 0, 14)
		)
	])
	assert_eq(
		sim.query_nearest_workable_node(0),
		sim.query_node_at_tile(Vector3i(0, 0, 26)),
		"and claimed ground is passed over for the next free Node"
	)


func test_a_map_with_nothing_to_claim_points_at_nothing() -> void:
	# -1 rather than a nearest-anyway, for the reason `query_turret_target_serial` names
	# nothing rather than a corpse: a direction to nowhere is worse than no direction.
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 12), "iron_ore", 3)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	assert_eq(sim.query_nearest_workable_node(0), -1, "nothing here is workable")


func test_asking_where_the_nearest_ore_is_does_not_move_the_hash() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var before: int = sim.hash()
	sim.query_nearest_workable_node(0)
	assert_eq(sim.hash(), before, "a projection the Simulation never reads back")
