## Where a body may stand: no Enemy inside a solid thing, and everything that must keep
## working once the walk is allowed to be refused.
##
## **#78, and the gap it fills is a gap between two kinds of assertion.** Every existing
## claim about an Enemy's position is either about *separation between bodies*
## (`test_enemy_separation`: no two of them at one coordinate) or about *who gets bitten*
## (`test_machine_mortality`, `test_enemies`: a Breaker eats a Smelter, a cornered Crawler
## chews a Wall). Nothing anywhere asserted **where a body is allowed to be**, so the one
## solid thing on the Map that was not painted as an obstruction — the Nest — went unnoticed
## for every ticket that touched the Enemy walk, and a Crawler's centre reached the dead
## middle of the 4x4 a player respawns on top of.
##
## Through the Simulation façade, which is the only seam: the refusal is observable as
## `query_enemy_position_metres` against `query_tile_obstructs_enemies` and in nothing else.
extends TestCase

## The Nest at the origin covering (0,0) to (3,3) — metres [0,8) on both axes — with one
## Breach ten tiles east on the Nest's own lane. `test_enemies`' and
## `test_enemy_separation`' geography, so a Wave here is the Wave those files watch walk.
func _layout(breach_tiles: int = 10) -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(0, WorldGrid.GROUND_LAYER, 0)
	layout.add_breach(Vector3i(breach_tiles, WorldGrid.GROUND_LAYER, 1))
	layout.sort_breaches()
	return layout


## Eight Crawlers a Breach, flat however hot the Factory gets: these tests are about where a
## body may stand, and `test_heat` is where Heat growing a Wave is asserted.
const EIGHT_CRAWLERS: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,8,0,8
"""

## One Crawler, for the tests that watch exactly one of them.
const ONE_CRAWLER: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,1,0,1
"""

## One Breaker, which is the kind that hunts Machines and therefore the kind that walks at a
## wall that is not the Nest's.
const ONE_BREAKER: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
shock_breakers,breaker,0,1,0,1
"""

## The boss alone, for the one test about `_withdraw_enemy`.
const ONE_HULK: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
siege_hulks,siege_hulk,0,1,0,1
"""


## Shipped content with the Telegraph shortened to half a second and — for the crowd tests —
## the spawn trickle wound right down, so a whole Wave leaves one Breach tile inside eight
## ticks and arrives as a stack rather than strung out down the road. That is the degenerate
## case on purpose: a lane contains no crowd, and the thing #78 is about only happens where
## the lane stops.
func _content(waves: String = EIGHT_CRAWLERS, overrides: Array = []) -> Definitions:
	var fixture: ContentFixture = ContentFixture.for_case(self)
	fixture.waves = waves
	return (
		fixture
		. stock("iron_plate:4000")
		. tune([
			["telegraph_seconds = 12", "telegraph_seconds = 0.5"],
			["spawn_interval_seconds = 0.5", "spawn_interval_seconds = 0.01"],
		])
		. tune(overrides)
		. definitions()
	)


## A Run with a Wave already called, so it arrives half a second in rather than two and a
## half minutes in. The lever is the honest way to bring a Wave forward in a test: it is the
## code path a player uses and it leaves the interval alone, so Wave 2 stays out of the way.
func _sim(
	waves: String = EIGHT_CRAWLERS, breach_tiles: int = 10, overrides: Array = []
) -> Simulation:
	var sim: Simulation = Simulation.new(
		11, 1, _content(waves, overrides), _layout(breach_tiles)
	)
	sim.step([InputAction.call_wave_early(0)])
	return sim


## Steps until there is at least one Enemy on the Map, and reports how many ticks it took.
func _step_until_spawned(sim: Simulation) -> int:
	var ticks: int = 0
	while sim.query_enemy_count() == 0 and ticks < 600:
		sim.step([])
		ticks += 1
	return ticks


## How far a position lies **outside** the Nest's footprint, in fixed-point metres: negative
## for a point inside it, so the worst case over a Run is one maximum of the negation.
##
## Read off `query_nest_tile` and `query_nest_footprint` rather than off the literals this
## file's `_layout` happens to use, for `MapLayout.NEST_FOOTPRINT_TILES`' own reason: the
## footprint has one authority and a test measuring against a second copy of 4x4 is the
## disagreement that cross-check exists to catch.
func _metres_outside_the_nest(sim: Simulation, at: FixedVec2) -> int:
	var size: Vector2i = sim.query_nest_footprint()
	var anchor: Vector3i = sim.query_nest_tile()
	var low_x: int = Fixed.from_int(anchor.x * WorldGrid.TILE_SIZE_METRES)
	var high_x: int = Fixed.from_int((anchor.x + size.x) * WorldGrid.TILE_SIZE_METRES)
	var low_z: int = Fixed.from_int(anchor.z * WorldGrid.TILE_SIZE_METRES)
	var high_z: int = Fixed.from_int((anchor.z + size.y) * WorldGrid.TILE_SIZE_METRES)
	return maxi(
		maxi(low_x - at.x, at.x - high_x),
		maxi(low_z - at.z, at.z - high_z)
	)


# ── The obstruction set ───────────────────────────────────────────────────────

func test_the_nest_obstructs_enemies_like_every_other_solid_thing() -> void:
	# The claim #78 had to make before any refusal could do anything: `_move_enemy_against_
	# the_factory` reads the obstruction field, and the field said the Nest was open ground.
	var sim: Simulation = _sim(ONE_CRAWLER)
	var ground: int = WorldGrid.GROUND_LAYER
	assert_true(
		sim.query_tile_obstructs_enemies(Vector3i(0, ground, 0)),
		"the Nest's anchor tile"
	)
	assert_true(
		sim.query_tile_obstructs_enemies(Vector3i(3, ground, 3)),
		"and its far corner, three tiles on"
	)
	assert_false(
		sim.query_tile_obstructs_enemies(Vector3i(4, ground, 3)),
		"and the tile past its wall is clear ground, which is where a body stops"
	)


func test_painting_the_nest_routes_a_wave_to_it_exactly_as_before() -> void:
	# A seed takes distance 0 without being asked whether it is blocked, which is the whole
	# reason painting the destination is safe — and it is worth asserting rather than
	# trusting, because the note this replaced claimed the opposite.
	var sim: Simulation = _sim(ONE_CRAWLER)
	var ground: int = WorldGrid.GROUND_LAYER
	assert_eq(
		sim.query_flow_distance_tiles(Vector3i(0, ground, 0)), 0, "the Nest is still the seed"
	)
	assert_eq(
		sim.query_flow_distance_tiles(Vector3i(4, ground, 1)),
		1,
		"the tile at its wall is still one step away"
	)
	assert_eq(
		sim.query_flow_distance_tiles(Vector3i(10, ground, 1)),
		7,
		"and the Breach is still seven steps out"
	)


# ── Where a body may stand ────────────────────────────────────────────────────

func test_no_enemy_ever_stands_inside_a_blocked_tile_while_a_wave_converges_on_the_nest() -> void:
	# The invariant, asserted on **every** tick rather than at the end of one, in the shape
	# `test_collision` states the player's: a body is never inside a solid, because there is
	# no tick on which it is allowed to be.
	var sim: Simulation = _sim()
	var breaches: int = 0
	var ticks: int = 0
	while ticks < 2400 and not sim.query_run_is_over():
		sim.step([])
		ticks += 1
		for index: int in range(sim.query_enemy_count()):
			var at: FixedVec2 = sim.query_enemy_position_metres(index)
			if sim.query_tile_obstructs_enemies(WorldGrid.tile_at_metres(at.x, at.z)):
				breaches += 1
	assert_true(ticks > 600, "the Wave had time to arrive: %d ticks" % ticks)
	assert_eq(breaches, 0, "no Enemy stood inside an obstruction on any tick")


func test_a_wave_stops_at_the_nests_wall_rather_than_walking_onto_its_footprint() -> void:
	# The measurement that opened the ticket, as an assertion. Before #78 a Crawler's centre
	# reached 3.000 m **inside** this 4x4 Nest — its dead middle — which is what the Windows
	# build's "the skeletons phase into the base" was a picture of.
	var sim: Simulation = _sim()
	var deepest: int = 0
	var closest: int = Fixed.from_int(1000)
	var ticks: int = 0
	while ticks < 2400 and not sim.query_run_is_over():
		sim.step([])
		ticks += 1
		for index: int in range(sim.query_enemy_count()):
			var outside: int = _metres_outside_the_nest(
				sim, sim.query_enemy_position_metres(index)
			)
			deepest = maxi(deepest, -outside)
			closest = mini(closest, outside)
	assert_eq(deepest, 0, "nothing was ever inside the footprint, by any margin")
	assert_true(
		closest < Fixed.from_int(1) / 10,
		"and the crowd really did press up against the wall: %d" % closest
	)


func test_a_wave_stopped_at_the_wall_still_brings_the_nest_down() -> void:
	# **The worst regression this fix could have caused**, and the one worth a test of its
	# own: a refusal that stopped a body one tile short of biting range would leave the Nest
	# untouchable and the Run unlosable. It cannot, because `_nest_in_contact` tests the tile
	# a body stands on **or one sharing an edge with it** — so the tile the refusal leaves a
	# body on is a tile it bites from.
	var sim: Simulation = _sim()
	var ticks: int = 0
	while ticks < 12000 and not sim.query_run_is_over():
		sim.step([])
		ticks += 1
	assert_true(sim.query_run_is_over(), "the Nest fell, after %d ticks" % ticks)
	assert_eq(sim.query_nest_health(), 0, "with nothing left of it")


func test_a_crawler_held_at_the_wall_is_in_contact_with_the_nest() -> void:
	# The same claim stated about one body rather than about the Run, so a failure says which
	# of the two halves broke.
	var sim: Simulation = _sim(ONE_CRAWLER)
	_step_until_spawned(sim)
	var ticks: int = 0
	while not sim.query_enemy_is_attacking(0) and ticks < 1200:
		sim.step([])
		ticks += 1
	assert_true(sim.query_enemy_is_attacking(0), "biting after %d ticks" % ticks)
	assert_eq(
		sim.query_flow_distance_tiles(sim.query_enemy_tile(0)),
		1,
		"from the tile at the wall, one step from the footprint"
	)
	assert_true(
		_metres_outside_the_nest(sim, sim.query_enemy_position_metres(0)) >= 0,
		"and standing outside it"
	)


# ── #9's rule: a Machine on top of a Crawler is not a prison ─────────────────

func test_an_enemy_a_machine_was_built_on_top_of_still_walks_out_of_it() -> void:
	# The case a naive refusal freezes for ever, and the reason
	# `_move_enemy_against_the_factory` takes an `escaping` argument at all: every step out of
	# the middle of a 3x3 footprint is a step into another blocked tile of the same footprint,
	# so a body inside an obstruction can only leave if the refusal lets it.
	var sim: Simulation = _sim(ONE_CRAWLER)
	_step_until_spawned(sim)
	var smelter: int = sim.query_definitions().machine_index("smelter_mk1")
	sim.step([InputAction.build_machine(0, smelter, sim.query_enemy_tile(0))])
	assert_true(
		sim.query_tile_obstructs_enemies(sim.query_enemy_tile(0)),
		"it is standing inside the new Machine"
	)
	assert_eq(sim.query_flow_direction(sim.query_enemy_tile(0)), -1, "with no route out")

	var trapped_at: FixedVec2 = sim.query_enemy_position_metres(0)
	for tick: int in range(Simulation.TICKS_PER_SECOND):
		sim.step([])
	assert_true(
		sim.query_enemy_position_metres(0).x < trapped_at.x,
		"and it walked straight at the Nest anyway"
	)


func test_an_enemy_walled_in_on_the_tile_it_stands_on_still_gets_out() -> void:
	# The same rule through a Wall rather than a Machine, because a Wall is one tile and the
	# escape is therefore a single step from blocked ground to clear — the shortest version of
	# the case, and the one a refusal written as "only if the step is to clear ground" would
	# pass while failing the Machine above.
	var sim: Simulation = _sim(ONE_CRAWLER)
	_step_until_spawned(sim)
	sim.step([InputAction.build_wall(0, sim.query_enemy_tile(0))])
	assert_true(
		sim.query_tile_obstructs_enemies(sim.query_enemy_tile(0)), "a Wall around its feet"
	)
	var trapped_at: FixedVec2 = sim.query_enemy_position_metres(0)
	for tick: int in range(Simulation.TICKS_PER_SECOND):
		sim.step([])
	assert_true(
		sim.query_enemy_position_metres(0).x < trapped_at.x, "and it left on the next tick"
	)


# ── A sealed pocket is still chewed ──────────────────────────────────────────

func test_a_wave_sealed_into_a_pocket_chews_its_way_out_rather_than_wandering() -> void:
	# `_enemy_contact_target`'s cornered clause is what stops sealing a Breach being a cheese,
	# and it is reached only by a body that is standing on **open** ground with nowhere to
	# walk. A refusal that left a sealed Wave shuffling against the inside of its box instead
	# of biting it would take that away without any existing test noticing.
	var ground: int = WorldGrid.GROUND_LAYER
	var sim: Simulation = _sim(EIGHT_CRAWLERS, 10)
	sim.step([
		InputAction.build_wall(0, Vector3i(9, ground, 1)),
		InputAction.build_wall(0, Vector3i(11, ground, 1)),
		InputAction.build_wall(0, Vector3i(10, ground, 0)),
		InputAction.build_wall(0, Vector3i(10, ground, 2)),
	])
	assert_eq(sim.query_wall_count(), 4, "the Breach is boxed in")
	var whole: int = sim.query_wall_health(0)

	_step_until_spawned(sim)
	for tick: int in range(Simulation.TICKS_PER_SECOND * 4):
		sim.step([])
	# **Chewed through, not merely chewed.** Eight bodies on one tile all bite the same Wall,
	# so four seconds is enough to take one off the Map entirely — which is why what is
	# counted is hit points *absorbed* rather than a Wall still standing with a dent in it.
	var standing: int = sim.query_wall_count()
	var dented: bool = standing < 4
	for index: int in range(standing):
		if sim.query_wall_health(index) < whole:
			dented = true
	assert_true(dented, "and the Wave chewed its way at the box rather than wandering in it")


# ── A Breaker at a Machine's wall ────────────────────────────────────────────

func test_a_breaker_stopped_at_a_machines_wall_still_eats_it() -> void:
	# The Factory's half of "a body stops at the footprint edge and bites from there".
	# `_machine_in_contact` walks the same tile-or-edge-sharing ring `_nest_in_contact` does,
	# so the tile the refusal leaves a Breaker on is a tile it eats from.
	var sim: Simulation = _sim(ONE_BREAKER)
	var smelter: int = sim.query_definitions().machine_index("smelter_mk1")
	sim.step([InputAction.build_machine(0, smelter, Vector3i(6, WorldGrid.GROUND_LAYER, 0))])
	var whole: int = sim.query_machine_health(0)

	_step_until_spawned(sim)
	var ticks: int = 0
	while sim.query_machine_health(0) == whole and sim.query_machine_count() == 1 and ticks < 1800:
		sim.step([])
		ticks += 1
	assert_true(sim.query_machine_count() == 1, "the Smelter is still there to be measured")
	assert_true(
		sim.query_machine_health(0) < whole, "and it is being eaten, after %d ticks" % ticks
	)
	assert_false(
		sim.query_tile_obstructs_enemies(sim.query_enemy_tile(0)),
		"from outside the footprint rather than from inside it"
	)


# ── The boss backing away ────────────────────────────────────────────────────

func test_a_siege_hulk_backing_away_from_a_turret_does_not_reverse_into_a_machine() -> void:
	# `_withdraw_enemy` is the one mover where the refusal is not merely belt and braces:
	# nothing checks what is behind a Hulk before it backs away from what is in front of it,
	# so before #78 a boss pushed out by a Turret reversed straight through the Factory.
	#
	# The Wall is the thing behind it rather than a Machine, because a Machine behind the Hulk
	# would be a Machine its own bombardment could remove mid-test.
	var ground: int = WorldGrid.GROUND_LAYER
	var sim: Simulation = _sim(ONE_HULK, 10)
	var turret: int = sim.query_definitions().machine_index("mg_turret_mk1")
	# The Turret between the Breach and the Nest, so the Hulk withdraws **east**, and a wall
	# of Wall standing in the ground it would withdraw into.
	sim.step([InputAction.build_machine(0, turret, Vector3i(6, ground, 0))])
	var walls: Array = []
	for offset: int in range(-3, 4):
		walls.append(InputAction.build_wall(0, Vector3i(13, ground, 1 + offset)))
	sim.step(walls)

	_step_until_spawned(sim)
	var breaches: int = 0
	for tick: int in range(Simulation.TICKS_PER_SECOND * 30):
		sim.step([])
		if sim.query_enemy_count() == 0:
			break
		if sim.query_tile_obstructs_enemies(sim.query_enemy_tile(0)):
			breaches += 1
	assert_eq(breaches, 0, "the boss never reversed into anything")


# ── Determinism ──────────────────────────────────────────────────────────────

func test_determinism_a_wave_reaching_the_nest_replays_bit_for_bit() -> void:
	# #78 moves `hash()` — a refused step is a position that did not change — so the Wave that
	# converges on the Nest and chews it down wants a fixture of its own. On the **shipped**
	# Map rather than this file's compact one, because `DeterminismHarness.record` constructs
	# its own Simulation and takes no layout — which is the right constraint: a fixture that
	# could only be reproduced on a handmade geography would be a weaker claim. Nothing here is
	# asserted about the positions: the claim is that two Runs down one script agree about
	# every one of them, tick by tick, which is what the harness compares.
	var script: InputScript = InputScript.new()
	script.add_tick([InputAction.call_wave_early(0)])
	script.add_idle_ticks(2000)

	var recording: ReplayRecording = DeterminismHarness.record(script, 11, 1, _content())
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_the_wave_in_that_fixture_really_did_reach_the_nest() -> void:
	# The honesty check beside the fixture above, which is the shape this project asks for: a
	# replay of a Run in which the thing never happened reads as a passing determinism test,
	# and the failure mode is silent.
	var sim: Simulation = Simulation.new(11, 1, _content())
	sim.step([InputAction.call_wave_early(0)])
	var whole: int = sim.query_nest_health()
	for tick: int in range(2000):
		sim.step([])
	assert_true(
		sim.query_nest_health() < whole,
		"the Nest took damage, so the Wave arrived: %d of %d" % [sim.query_nest_health(), whole]
	)
