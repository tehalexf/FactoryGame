## A roof is cover against what is shorter than it, and against nothing else.
##
## #58's whole ticket. `_player_in_contact` subtracted positions on two axes and had never
## heard of `_player_y`, so a 1.6 m Crawler standing on the ground bit a player on a 2.2 m
## Steam Boiler roof. That was the conservative default rather than a decision — and #30 is
## what made it matter, because a player reaches
## `player.jump_height_metres + player.step_up_height_metres` and their own Factory is
## therefore the staircase. They will be up there.
##
## **The rule chosen is that an Enemy reaches as high as it is tall**, read off
## `_enemy_hit_height` — the one authority on a kind's size and the number `WorldView` scales
## the drawn body by. What protects the keystone loop is not a ceiling anybody tuned: it is
## that the Breaker, which is the kind that actually takes a Factory apart, is the tall one.
## So Chaff cannot reach a player on a production roof and the threat can, which is
## DESIGN.md's own split arriving as geometry — and a Breaker prefers the Machine anyway, so
## a player standing on one watches it eat their floor.
##
## Everything here is driven through the façade: `step` with Input Actions, assertions on
## `query_*`. Expected values are the shipped `content/tuning.toml` figures and the declared
## heights in `content/machines.csv` — a Crawler at 1.6 m, a Breaker at 2.2, a Siege Hulk at
## 3.2, against a Smelter at 1.5, a Boiler at 2.2 and a Wall at 2.4.
extends TestCase

## The perch stands here, two tiles' worth of Map east of the origin, and whatever an Enemy
## comes out of stands immediately east of *it*. The Nest is a long way west, so the lane
## runs through the perch and an Enemy has somewhere to be going.
const PERCH_TILE: Vector3i = Vector3i(0, WorldGrid.GROUND_LAYER, 0)

## Where player 1 is sent before it builds anything. Thirty metres south of the lane and
## twenty-nine clear of any Breach, so the player this file is about is the only one in
## reach — a second body standing on the ground beside the perch would be bitten in a test
## whose whole claim is that nobody was.
const SPECTATOR_Z: int = 30

## One Enemy a Breach and never any more, so these tests watch exactly one of them.
const ONE_CRAWLER: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,1,0,1
"""
const ONE_BREAKER: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
shock_breakers,breaker,0,1,0,1
"""
const ONE_SIEGE_HULK: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
siege_hulks,siege_hulk,0,1,0,1
"""

## Long enough for an Enemy to emerge, stop shuffling and spend several bites, at sixty ticks
## a second. Bounded, so a Simulation that stopped biting fails rather than hangs.
const PATIENCE_TICKS: int = 40 * Simulation.TICKS_PER_SECOND

## Long enough for a Breaker to chew a 400-point Boiler down at 60 a bite, drop the player on
## the ground and walk the two metres to them.
const SIEGE_TICKS: int = 90 * Simulation.TICKS_PER_SECOND

## How near, horizontally, any Enemy got to player 0 over the window `_wait_for_a_bite` just
## watched — in fixed-point metres, or -1 if the Map never held an Enemy at all.
##
## **Recorded as it happens rather than read at the end, and that distinction is load-bearing.**
## An Enemy that could not reach the player walks on to the Nest, so by the last tick of a
## negative test it is sixteen metres away and a reading taken then would say the Wave never
## came near — which is precisely the vacuous pass this measurement exists to rule out.
var _closest_approach: int = -1


## A Map whose Nest is twenty-four metres west of the perch, with one Breach at `breach_tile`.
##
## The Nest is deliberately nowhere near the perch: an Enemy that reached the Nest would bite
## *that* instead, and these tests are about a player. It is west so the lane runs through
## the perch, and far enough that nothing arrives at it inside `PATIENCE_TICKS`.
func _layout(breach_tile: Vector3i) -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(-12, WorldGrid.GROUND_LAYER, 0)
	layout.add_breach(breach_tile)
	layout.sort_breaches()
	return layout


## The shipped content with three things changed and nothing else.
##
## The Telegraph is half a second, so a called Wave arrives in thirty ticks rather than
## twelve seconds — `test_machine_mortality`'s substitution, for its reason.
##
## **`enemy.player_bite_reach_metres` goes from 1.6 to 6, and that is what makes these tests
## about height and nothing else.** The perch is a tile of Map and an Enemy cannot stand on
## it, so at the shipped reach whether a bite lands depends on exactly how near the footprint
## edge a player happened to walk and on which way round an obstruction the flowfield sent the
## Enemy — neither of which this ticket changed, and both of which would make a test about
## the vertical rule fail or pass for horizontal reasons. Widened, every one of these Enemies
## is comfortably in horizontal reach for the whole window, so the only thing left that can
## decide a bite is the new rule. It also makes the negative tests *stronger* rather than
## weaker: six metres of reach and still no bite.
##
## The stock pays for any perch, because what it costs is not what is being measured.
func _content(waves: String, overrides: Array = []) -> Definitions:
	var all: Array = [
		["telegraph_seconds = 12", "telegraph_seconds = 0.5"],
		["player_bite_reach_metres = 1.6", "player_bite_reach_metres = 6"],
	]
	all.append_array(overrides)
	var fixture: ContentFixture = ContentFixture.for_case(self).tune(all).stock("iron_plate:400")
	fixture.waves = waves
	return fixture.definitions()


## A Run with two players and its first Wave already called, with player 1 sent out of the
## way. The lever is the honest way to bring a Wave forward in a test: it is the code path a
## player uses.
##
## Two players because **the only way to be standing on something is for the something to
## have arrived** — movement cannot put a player inside a solid, so #30's
## `_lift_out_of_anything_built_on_them` is the one route onto a roof that a test can drive,
## and somebody other than the occupant has to do the building.
func _sim(waves: String, breach_tile: Vector3i, overrides: Array = []) -> Simulation:
	var sim: Simulation = Simulation.new(11, 2, _content(waves, overrides), _layout(breach_tile))
	_walk_to(sim, 1, 0, Fixed.from_int(SPECTATOR_Z))
	return sim


## Steps until `predicate` holds, and reports how many ticks that took — or -1 if it never
## did inside `limit`.
func _step_until(sim: Simulation, limit: int, predicate: Callable) -> int:
	for tick: int in range(limit):
		if predicate.call():
			return tick
		sim.step([])
	return -1 if not predicate.call() else limit


## Puts a player's feet at a point in fixed-point metres by walking the Simulation's own state
## there, rather than by setting a private array: a test that did the latter would be testing
## something `step` cannot produce. `test_collision`'s scaffolding with a player id on it.
##
## Deliberately crude — it is scaffolding, not a mechanic. +x is `strafe` at yaw 0 and -z is
## `forward`, and the two axes are driven together.
func _walk_to(sim: Simulation, player_id: int, x: int, z: int) -> void:
	for _i: int in range(4000):
		var here: FixedVec2 = sim.query_player_position(player_id)
		var gap_x: int = x - here.x
		var gap_z: int = z - here.z
		var close_enough: int = Fixed.from_decimal_string("0.05")
		if absi(gap_x) <= close_enough and absi(gap_z) <= close_enough:
			return
		var strafe: int = Fixed.clamp_fixed(
			Fixed.mul(gap_x, Fixed.from_int(4)), -Fixed.ONE, Fixed.ONE
		)
		var forward: int = Fixed.clamp_fixed(
			Fixed.mul(-gap_z, Fixed.from_int(4)), -Fixed.ONE, Fixed.ONE
		)
		sim.step([InputAction.move(player_id, forward, strafe)])
	assert_true(false, "the scaffolding failed to walk player %d where a test wanted them" % player_id)


## Stands player 0 at `x`, `z`, has player 1 build `machine_id` on top of them, and asserts
## they ended up on its roof at the height its row declares. Returns that height.
func _stand_on_a_machine(sim: Simulation, machine_id: String, x: int, z: int) -> int:
	_walk_to(sim, 0, x, z)
	assert_eq(sim.query_player_height_metres(0), 0, "on the ground to begin with")
	var index: int = sim.query_definitions().machine_index(machine_id)
	sim.step([InputAction.build_machine(1, index, PERCH_TILE)])
	var roof: int = sim.query_machine_height_metres(0)
	assert_eq(
		sim.query_player_height_metres(0),
		roof,
		"and on the roof of the %s that was built under them" % machine_id
	)
	return roof


## The same, for a Wall — which is **not a Machine**, and that is the whole reason this file
## has two perches. A Breaker takes a Machine over a player
## (`_enemy_contact_target`'s first clause), so a Breaker's own ceiling can only be measured
## on something that is not one. A Wall is also only ever chewed by an Enemy with nowhere
## left to walk, and one Wall on an open Map leaves a route round it.
func _stand_on_a_wall(sim: Simulation, x: int, z: int) -> int:
	_walk_to(sim, 0, x, z)
	assert_eq(sim.query_player_height_metres(0), 0, "on the ground to begin with")
	sim.step([InputAction.build_wall(1, PERCH_TILE)])
	assert_eq(sim.query_wall_count(), 1, "the Wall went up")
	var roof: int = sim.query_player_height_metres(0)
	assert_true(roof > 0, "and the player is standing on it, %s m up" % Fixed.to_float(roof))
	return roof


## Pulls the lever and steps until something takes a bite out of player 0, reporting the tick
## it happened on or -1, and recording the nearest any Enemy got on the way.
func _wait_for_a_bite(sim: Simulation, limit: int = PATIENCE_TICKS) -> int:
	var whole: int = sim.query_player_health(0)
	_closest_approach = -1
	sim.step([InputAction.call_wave_early(0)])
	for tick: int in range(limit):
		_note_the_approach(sim)
		if sim.query_player_health(0) < whole:
			return tick
		sim.step([])
	_note_the_approach(sim)
	return -1 if sim.query_player_health(0) >= whole else limit


func _note_the_approach(sim: Simulation) -> void:
	var me: FixedVec2 = sim.query_player_position(0)
	for index: int in range(sim.query_enemy_count()):
		var them: FixedVec2 = sim.query_enemy_position_metres(index)
		var gap_x: int = them.x - me.x
		var gap_z: int = them.z - me.z
		var gap: int = Fixed.sqrt(Fixed.mul(gap_x, gap_x) + Fixed.mul(gap_z, gap_z))
		if _closest_approach == -1 or gap < _closest_approach:
			_closest_approach = gap


# ── A Crawler reaches 1.6 m, which is a Smelter and not a Boiler ───────────────

func test_a_crawler_bites_a_player_standing_on_a_smelter_roof() -> void:
	# enemy.enemy_hit_height_metres is 1.6 and smelter_mk1's row declares 1.5, so a Crawler
	# standing beside its own height of Machine can still reach what is on top of it. This is
	# the half of the rule that is *not* a behaviour change, and it is here so that the
	# negative tests below cannot pass by the reach being broken outright.
	var sim: Simulation = _sim(ONE_CRAWLER, Vector3i(3, WorldGrid.GROUND_LAYER, 0))
	var roof: int = _stand_on_a_machine(
		sim, "smelter_mk1", Fixed.from_int(5), Fixed.from_int(1)
	)
	assert_eq(roof, Fixed.from_decimal_string("1.5"), "the Smelter's declared height")
	assert_true(
		_wait_for_a_bite(sim) != -1,
		"a 1.6 m Crawler reaches a player 1.5 m up"
	)


func test_a_crawler_cannot_reach_a_player_on_a_steam_boiler_roof() -> void:
	# The ticket in one assertion. steam_boiler_mk1 declares 2.2 m against a Crawler's 1.6,
	# so seventy centimetres of Machine is the difference between being eaten and not — and
	# before #58 the Crawler bit anyway, because the subtraction had two terms.
	var sim: Simulation = _sim(ONE_CRAWLER, Vector3i(3, WorldGrid.GROUND_LAYER, 0))
	var roof: int = _stand_on_a_machine(
		sim, "steam_boiler_mk1", Fixed.from_int(5), Fixed.from_int(1)
	)
	assert_eq(roof, Fixed.from_decimal_string("2.2"), "the Boiler's declared height")
	assert_eq(_wait_for_a_bite(sim), -1, "a 1.6 m Crawler cannot reach 2.2 m")
	assert_eq(sim.query_player_health(0), sim.query_player_max_health(0), "untouched")
	# And the premise: a Crawler really was alongside, well inside the six metres of
	# horizontal reach this fixture grants it. Without this the test would pass just as
	# happily against a Wave that never arrived.
	assert_true(_closest_approach != -1, "a Crawler did arrive")
	assert_true(
		_closest_approach < Fixed.from_int(6),
		"and came within the fixture's own reach, %s m" % Fixed.to_float(_closest_approach)
	)
	# Chaff walks past a Machine untouched, so the roof is still there to be standing on.
	assert_eq(sim.query_machine_count(), 1, "and a Crawler never ate the Boiler either")


# ── A Breaker reaches 2.2 m, and a Wall is where that can be measured ──────────

func test_a_breaker_reaches_a_player_two_metres_up_where_a_crawler_cannot() -> void:
	# The per-kind half of the rule, on a two-metre perch that sits between a Crawler's 1.6
	# and a Breaker's 2.2. A Wall rather than a Machine because a Breaker prefers a Machine
	# to a player whatever the heights are, so a Machine roof can never show a Breaker's own
	# ceiling. The height is tuned to 2 m for exactly that gap; every other number is the
	# shipped file's.
	var lowered: Array = [["height_metres = 2.4", "height_metres = 2.0"]]
	var crawler: Simulation = _sim(
		ONE_CRAWLER, Vector3i(1, WorldGrid.GROUND_LAYER, 0), lowered
	)
	var height: int = _stand_on_a_wall(crawler, Fixed.from_int(1), Fixed.from_int(1))
	assert_eq(height, Fixed.from_int(2), "wall.height_metres, as this fixture tuned it")
	assert_eq(_wait_for_a_bite(crawler), -1, "a 1.6 m Crawler cannot reach 2 m")
	assert_true(
		_closest_approach != -1 and _closest_approach < Fixed.from_int(6),
		"having come within reach of it horizontally, %s m" % Fixed.to_float(_closest_approach)
	)

	var breaker: Simulation = _sim(
		ONE_BREAKER, Vector3i(1, WorldGrid.GROUND_LAYER, 0), lowered
	)
	assert_eq(
		_stand_on_a_wall(breaker, Fixed.from_int(1), Fixed.from_int(1)),
		Fixed.from_int(2),
		"the same two-metre perch"
	)
	assert_true(
		_wait_for_a_bite(breaker) != -1,
		"and a 2.2 m Breaker reaches the player a Crawler could not"
	)


func test_a_breaker_cannot_reach_a_player_on_top_of_a_wall() -> void:
	# wall.height_metres is 2.4 against a Breaker's 2.2 — and a Wall is the one structure
	# whose entire job is to stop something, which #30 already made out of reach from the
	# ground on purpose. So the top of a Wall is genuinely cover from everything but the
	# boss, and the price is that a player standing up there is holding a wrench nothing
	# brought them within reach of.
	var sim: Simulation = _sim(ONE_BREAKER, Vector3i(1, WorldGrid.GROUND_LAYER, 0))
	assert_eq(
		_stand_on_a_wall(sim, Fixed.from_int(1), Fixed.from_int(1)),
		Fixed.from_decimal_string("2.4"),
		"wall.height_metres as shipped"
	)
	assert_eq(_wait_for_a_bite(sim), -1, "a 2.2 m Breaker cannot reach 2.4 m")
	assert_true(
		_closest_approach != -1 and _closest_approach < Fixed.from_int(6),
		"and a Breaker really was alongside, %s m away" % Fixed.to_float(_closest_approach)
	)


# ── A roof is not a free safe spot, because the Breaker eats the roof ──────────

func test_a_breaker_eats_the_roof_a_player_is_standing_on_and_then_bites_them() -> void:
	# **The acceptance criterion, and the whole argument that height counting does not undo
	# the keystone loop.** A Breaker takes a Machine over a player — `_enemy_contact_target`'s
	# first clause, which is GLOSSARY.md's sentence made literal — so a player who climbs a
	# 2.2 m Boiler to get out of Chaff's reach has not bought safety from the thing that
	# actually takes Factories apart. It chews their floor out from under them at 60 a bite,
	# they fall to the ground, and then they are an ordinary player standing in front of a
	# Breaker.
	var sim: Simulation = _sim(ONE_BREAKER, Vector3i(3, WorldGrid.GROUND_LAYER, 0))
	var roof: int = _stand_on_a_machine(
		sim, "steam_boiler_mk1", Fixed.from_int(5), Fixed.from_int(1)
	)
	assert_eq(roof, Fixed.from_decimal_string("2.2"), "out of a Crawler's reach, up there")

	sim.step([InputAction.call_wave_early(0)])
	var gone: int = _step_until(
		sim, SIEGE_TICKS, func() -> bool: return sim.query_machine_count() == 0
	)
	assert_true(gone != -1, "the Breaker chewed the floor out from under them")
	# The floor going away is a fall on the *next* tick — `_is_on_their_feet` compares against
	# the support height, so nothing special-cases a demolished roof and a player is still
	# 2.2 m up on the tick it vanished.
	assert_eq(
		sim.query_player_height_metres(0),
		roof,
		"still up in the air on the tick it went, because a fall is the next tick's business"
	)
	assert_true(
		_step_until(
			sim, SIEGE_TICKS, func() -> bool: return sim.query_player_height_metres(0) == 0
		) != -1,
		"and then they drop back onto the Map"
	)

	var whole: int = sim.query_player_health(0)
	assert_true(
		_step_until(
			sim, SIEGE_TICKS, func() -> bool: return sim.query_player_health(0) < whole
		) != -1,
		"and then it bites them, which is why a roof is not a safe spot"
	)


# ── A Siege Hulk is 3.2 m, which is every roof in the content ──────────────────

func test_a_siege_hulk_reaches_a_player_on_a_boiler_roof_that_a_crawler_cannot_touch() -> void:
	# siege_hulk.hit_height_metres is 3.2, so the boss reaches every roof `machines.csv`
	# declares — the tallest is the Repair Pylon at 2.4. And `_siege_hulk` answers a player at
	# its feet *before* it decides what to shell, so unlike a Breaker it has no Machine
	# preference to get in the way: a player who climbs a Boiler to dodge the boss has simply
	# stopped walking.
	var sim: Simulation = _sim(ONE_SIEGE_HULK, Vector3i(3, WorldGrid.GROUND_LAYER, 0))
	assert_eq(
		_stand_on_a_machine(sim, "steam_boiler_mk1", Fixed.from_int(5), Fixed.from_int(1)),
		Fixed.from_decimal_string("2.2"),
		"the same roof a Crawler could not reach"
	)
	assert_true(
		_wait_for_a_bite(sim, SIEGE_TICKS) != -1,
		"a 3.2 m Siege Hulk stomps a player 2.2 m up"
	)


# ── What the rule must not have broken ────────────────────────────────────────

func test_an_enemy_still_bites_a_player_standing_on_the_ground() -> void:
	# The regression guard. A vertical test that was accidentally strict — or that compared
	# against the wrong end of a body — would take the bite away from every player in the
	# game, which is the one failure none of the tests above could see, because every one of
	# them is about somebody who climbed something. Both kinds, on bare ground, nothing built.
	for waves: String in [ONE_CRAWLER, ONE_BREAKER]:
		var sim: Simulation = _sim(waves, Vector3i(1, WorldGrid.GROUND_LAYER, 0))
		_walk_to(sim, 0, Fixed.from_int(1), Fixed.from_int(1))
		assert_eq(sim.query_player_height_metres(0), 0, "both feet on the Map")
		assert_true(_wait_for_a_bite(sim) != -1, "and still bitten where they stand")


func test_the_rule_is_the_enemys_own_drawn_height_and_not_a_number_of_its_own() -> void:
	# `_enemy_player_vertical_reach` is `_enemy_hit_height`, which is the capsule a round is
	# resolved against and the figure `WorldView` scales the body by — so the thing that can
	# reach you is the thing you can see reaching, and there is no second authority on how big
	# a kind is. Asserted from the outside: the three kinds a Wave can hold really do have
	# three different drawn heights, in the order the tests above depend on. A later ticket
	# that gave the reach a tuning key of its own would make these three facts and the bites
	# above stop agreeing.
	var sim: Simulation = _sim(ONE_CRAWLER, Vector3i(3, WorldGrid.GROUND_LAYER, 0))
	sim.step([InputAction.call_wave_early(0)])
	assert_true(
		_step_until(sim, PATIENCE_TICKS, func() -> bool: return sim.query_enemy_count() > 0) != -1,
		"a Crawler arrived to be measured"
	)
	assert_eq(
		sim.query_enemy_hit_height_metres(0),
		Fixed.from_decimal_string("1.6"),
		"gear.enemy_hit_height_metres, which is a Crawler's whole size"
	)
	var definitions: Definitions = sim.query_definitions()
	assert_true(
		definitions.breaker_hit_height_metres > definitions.gear_enemy_hit_height_metres,
		"a Breaker is taller than a Crawler, which is what makes the threat the thing that reaches"
	)
	assert_true(
		definitions.siege_hulk_hit_height_metres > definitions.breaker_hit_height_metres,
		"and the boss is taller again, so no roof in the content is cover from it"
	)


func test_asking_how_high_an_enemy_reaches_changes_nothing_about_the_run() -> void:
	# The rule is read inside the tick and exposed nowhere new, so the only thing a caller can
	# ask about it is the height it is derived from — and that must stay a projection the
	# Simulation never reads back, exactly as every other `query_*` is.
	var sim: Simulation = _sim(ONE_CRAWLER, Vector3i(3, WorldGrid.GROUND_LAYER, 0))
	sim.step([InputAction.call_wave_early(0)])
	assert_true(
		_step_until(sim, PATIENCE_TICKS, func() -> bool: return sim.query_enemy_count() > 0) != -1,
		"a Crawler arrived"
	)
	var before: int = sim.hash()
	for index: int in range(sim.query_enemy_count()):
		sim.query_enemy_hit_height_metres(index)
		sim.query_enemy_hit_radius_metres(index)
	assert_eq(sim.hash(), before, "asking left the Run exactly where it was")


# ── Determinism ───────────────────────────────────────────────────────────────
#
# The fixture is a Crawler Wave arriving on a player who is standing on a Boiler roof, on
# `MapLayout.starter()` — which is the Map `DeterminismHarness.record` constructs, so a
# fixture has to be written against it.

## The Boiler is built at the origin so that it lands on the player standing there at tick 0,
## which is the one route onto a roof that needs no walking at all — and a script handed to
## the harness cannot look at the Simulation to find out where anybody got to.
const FIXTURE_PERCH_TILE: Vector3i = Vector3i(-1, WorldGrid.GROUND_LAYER, 0)

## The horizontal reach the fixture grants, wide enough that the starter Map's lane from its
## Breach to its Nest passes inside it. The vertical rule is the only thing left to decide
## whether a bite lands, which is what makes the honesty check below a measurement of this
## ticket rather than of the flowfield.
const FIXTURE_REACH: String = "player_bite_reach_metres = 16"


func _fixture_content(crawler_height: String = "enemy_hit_height_metres = 1.6") -> Definitions:
	var fixture: ContentFixture = (
		ContentFixture
		. for_case(self)
		. tune([
			["telegraph_seconds = 12", "telegraph_seconds = 0.5"],
			["player_bite_reach_metres = 1.6", FIXTURE_REACH],
			["enemy_hit_height_metres = 1.6", crawler_height],
		])
		. stock("iron_plate:400")
	)
	fixture.waves = ONE_CRAWLER
	return fixture.definitions()


func _roof_script(definitions: Definitions) -> InputScript:
	var script: InputScript = InputScript.new()
	script.add_tick([
		InputAction.build_machine(
			1, definitions.machine_index("steam_boiler_mk1"), FIXTURE_PERCH_TILE
		),
		InputAction.call_wave_early(0),
	])
	script.add_idle_ticks(30 * Simulation.TICKS_PER_SECOND)
	return script


func _play(definitions: Definitions) -> Simulation:
	var sim: Simulation = Simulation.new(7, 2, definitions, MapLayout.starter())
	var script: InputScript = _roof_script(definitions)
	for tick: int in range(script.tick_count()):
		sim.step(script.actions_at(tick))
	return sim


func test_determinism_a_wave_arriving_on_a_player_on_a_roof_replays_identically() -> void:
	var definitions: Definitions = _fixture_content()
	var recording: ReplayRecording = DeterminismHarness.record(
		_roof_script(definitions), 7, 2, definitions
	)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_the_roof_fixture_really_did_put_a_player_out_of_reach() -> void:
	# **The honesty check, and it is a control rather than an inspection.** A replay of a Run
	# in which the Crawlers never came near reads exactly like a replay of one in which they
	# came and could not reach, so the premise is proved by changing the one number under
	# test: the same script, the same Map, the same seed, with a Crawler drawn three metres
	# tall instead of 1.6, bites the player off the Boiler's 2.2 m roof. Nothing else about
	# the fixture differs, so the bite is the vertical rule and can be nothing else.
	var out_of_reach: Simulation = _play(_fixture_content())
	assert_eq(out_of_reach.query_player_height_metres(0), Fixed.from_decimal_string("2.2"))
	assert_eq(
		out_of_reach.query_player_health(0),
		out_of_reach.query_player_max_health(0),
		"a 1.6 m Crawler never reached a player on a 2.2 m roof"
	)

	var tall: Simulation = _play(_fixture_content("enemy_hit_height_metres = 3.0"))
	assert_eq(tall.query_player_height_metres(0), Fixed.from_decimal_string("2.2"))
	assert_true(
		tall.query_player_health(0) < tall.query_player_max_health(0),
		"and a three-metre one did, off the identical script — so they were always in reach"
	)
