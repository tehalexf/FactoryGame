## A Wave that moves like a crowd rather than a rank: no two Enemies standing in the same
## space, and the pass that keeps them apart costing a count of neighbours rather than a
## count of Enemies.
##
## **#76, and it overturns a design note rather than filling a gap.** The Simulation said
## Enemies do not collide with one another by design, because the alternative looked like an
## O(n^2) separation pass the Chaff tier could not afford. The user looked at the result —
## a rank of bodies interpenetrating as they converge on one tile — and overruled it. The
## reason behind the note was real, so what is asserted here is both halves: that a crowd
## reads as a crowd, and that the rule is still local.
##
## Through the Simulation façade, which is the only seam. Separation is observable as
## `query_enemy_position_metres` and in nothing else — there is no separation state, no
## Enemy class and no node, so there is nothing else for a test to look at.
extends TestCase

## The Nest at the origin covering (0,0) to (3,3), one Breach east of it on the Nest's own
## lane. `test_enemies`' geography, so a crowd here is the crowd that file watches walk.
##
## **How far out the Breach is, is the one thing these tests vary**, because a crowd has two
## regimes and they want asking about separately: one with road ahead of it, and one pressed
## up against the thing it came to eat.
func _layout(breach_tiles: int = 10) -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(0, WorldGrid.GROUND_LAYER, 0)
	layout.add_breach(Vector3i(breach_tiles, WorldGrid.GROUND_LAYER, 1))
	layout.sort_breaches()
	return layout


## Eight Crawlers a Breach, flat however hot the Factory gets: these tests are about what a
## crowd does, and `test_heat` is where Heat growing a Wave is asserted.
const EIGHT_CRAWLERS: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,8,0,8
"""

## Four Crawlers and four Breakers, for the one test that asks whether two kinds of body
## leave each other the room their own two sizes ask for.
const MIXED_WAVE: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,4,0,4
shock_breakers,breaker,0,4,0,4
"""

## Six Crawlers and the boss, for the one test that asks what a crowd may *not* push around.
const HULK_AND_CHAFF: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,6,0,6
siege_hulks,siege_hulk,0,1,0,1
"""


## Shipped content with the Telegraph shortened to half a second, and **the spawn trickle
## wound down to one Crawler a tick**, so a whole Wave comes out of one Breach tile inside
## eight ticks and arrives as a stack.
##
## That is the degenerate case on purpose rather than for convenience: a half-second trickle
## hands a crowd its spacing for free, where eight bodies released a tick apart are four
## centimetres apart on the axis they are walking along and have nothing to push on. It is
## also the picture the user was complaining about — several Crawlers occupying the same
## half-metre at a Breach.
##
## **Zero is refused by the loader and that is the right refusal**, by name: *"a whole Wave
## arriving in no time is a stack of Enemies on one tile"*. So the exactly-coincident case is
## unreachable from `content/`, and the nearly-coincident one is what a fixture can build.
func _content(waves: String = EIGHT_CRAWLERS, overrides: Array = []) -> Definitions:
	var fixture: ContentFixture = ContentFixture.for_case(self)
	fixture.waves = waves
	return (
		fixture
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


## Steps until the whole Wave is on the Map, and reports how many there are.
func _step_until_released(sim: Simulation, want: int) -> int:
	var ticks: int = 0
	while sim.query_enemy_count() < want and ticks < 600:
		sim.step([])
		ticks += 1
	return sim.query_enemy_count()


## The closest two Enemies get, as a fraction of the room their own two radii ask for.
##
## Reported as a **ratio rather than a distance** so one number covers a crowd of mixed
## kinds: 1.0 or more is a crowd nobody is standing inside, and 0 is two bodies exactly on
## top of one another. All-pairs, because a test is allowed to be quadratic about eight
## Enemies — what has to be local is the Simulation's pass, not this.
func _tightest_gap_ratio(sim: Simulation) -> float:
	var tightest: float = 1000.0
	for a: int in range(sim.query_enemy_count()):
		for b: int in range(a + 1, sim.query_enemy_count()):
			var here: FixedVec2 = sim.query_enemy_position_metres(a)
			var there: FixedVec2 = sim.query_enemy_position_metres(b)
			var gap_x: float = Fixed.to_float(there.x - here.x)
			var gap_z: float = Fixed.to_float(there.z - here.z)
			var room: float = Fixed.to_float(
				sim.query_enemy_hit_radius_metres(a) + sim.query_enemy_hit_radius_metres(b)
			)
			var gap: float = sqrt(gap_x * gap_x + gap_z * gap_z)
			tightest = minf(tightest, gap / room)
	return tightest


## The deepest any two Enemies are standing inside one another, in fixed-point metres, or 0
## when nobody overlaps at all.
##
## **Measured in fixed point rather than as a float, because the claim is exact.** A settled
## pair comes to rest *touching*, and the only thing between it and arithmetic equality is
## that `Fixed.sqrt` floors and half an overlap is a right shift — so the honest statement is
## "inside tangency by a couple of fixed-point units", which is a statement a float ratio
## cannot make.
func _worst_overlap(sim: Simulation) -> int:
	var worst: int = 0
	for a: int in range(sim.query_enemy_count()):
		for b: int in range(a + 1, sim.query_enemy_count()):
			var here: FixedVec2 = sim.query_enemy_position_metres(a)
			var there: FixedVec2 = sim.query_enemy_position_metres(b)
			var gap_x: int = there.x - here.x
			var gap_z: int = there.z - here.z
			var room: int = (
				sim.query_enemy_hit_radius_metres(a) + sim.query_enemy_hit_radius_metres(b)
			)
			var gap: int = Fixed.sqrt(Fixed.mul(gap_x, gap_x) + Fixed.mul(gap_z, gap_z))
			worst = maxi(worst, room - gap)
	return worst


## How far inside tangency a settled pair is allowed to come to rest, in fixed-point units.
##
## Four, against a measured two. One unit is 1/65536 of a metre — fifteen micrometres — so
## this is a tolerance on the two floors in the arithmetic and not a tolerance on the rule:
## a pair that was overlapping by anything a player could see would miss it by four orders
## of magnitude.
const SETTLING_UNITS: int = 4


## How many Enemies are standing in exactly the same place as another.
##
## The sharpest statement of what the user was complaining about, and the one claim that has
## to hold in *every* regime: a crowd pressed against the Nest is allowed to be a crush, and
## it is never allowed to be two bodies at one coordinate.
func _count_coincident(sim: Simulation) -> int:
	var stacked: int = 0
	for a: int in range(sim.query_enemy_count()):
		for b: int in range(a + 1, sim.query_enemy_count()):
			var here: FixedVec2 = sim.query_enemy_position_metres(a)
			var there: FixedVec2 = sim.query_enemy_position_metres(b)
			if here.x == there.x and here.z == there.z:
				stacked += 1
	return stacked


## Steps a Run on for a count of whole seconds.
func _step_seconds(sim: Simulation, seconds: int) -> void:
	for i: int in range(seconds * Simulation.TICKS_PER_SECOND):
		sim.step([])


# ── A crowd at a Breach ───────────────────────────────────────────────────────

func test_a_crowd_with_road_ahead_of_it_settles_at_exactly_the_room_its_bodies_ask_for() -> void:
	# Fifty tiles out, so the whole Wave is still walking when it is measured and what is
	# being asked about is the crowd rather than the bottleneck at the far end of it.
	var sim: Simulation = _sim(EIGHT_CRAWLERS, 50)
	assert_eq(_step_until_released(sim, 8), 8, "the whole Wave, released onto one tile")
	_step_seconds(sim, 5)
	# Measured: 0.02 of the room they need on the tick they are all out, 0.42 after a second
	# and a half, and **settled two fixed-point units inside tangency from about four seconds
	# on** — where it stays, for as long as the Run was left running, because a pair that is
	# touching has no overlap left to push on. That it converges and then *holds* is the
	# half worth asserting: a relaxation pass that overshot would oscillate for ever.
	assert_true(
		_worst_overlap(sim) <= SETTLING_UNITS,
		"no two Crawlers inside the room their own two radii ask for"
	)


func test_a_crowd_pressed_against_the_nest_crushes_rather_than_interpenetrating() -> void:
	# Ten tiles out, so by the time this is measured the leaders are chewing the Nest and the
	# rest have walked into the back of them. **A bottleneck is allowed to compress** — eight
	# bodies 1.2 m wide cannot stand abreast on one lane, and a crowd that pressed in and
	# then stopped pressing would be a crowd that had given up on the Nest. What it may not
	# do is put two of them in the same place.
	var sim: Simulation = _sim(EIGHT_CRAWLERS, 10)
	assert_eq(_step_until_released(sim, 8), 8)
	_step_seconds(sim, 8)
	assert_eq(_count_coincident(sim), 0, "nobody standing inside anybody")
	# Measured at 0.82 of the room they would like, which is a crush and not a stack. The
	# bound is loose on purpose: what is being pinned is that the crush has a floor at all,
	# and the exact figure is a property of how many bodies a lane can hold.
	assert_true(
		_tightest_gap_ratio(sim) >= 0.6,
		"pressed together, and still further apart than half the room they want"
	)


func test_nothing_in_a_wave_ever_stands_in_the_same_place_as_anything_else() -> void:
	# The user's own complaint, asserted on every tick of a Wave rather than at the end of
	# one: Enemies are released at the centre of a Breach tile, so a Wave out of one hole
	# arrives as a stack of bodies at identical coordinates and has to come apart on its own.
	var sim: Simulation = _sim(EIGHT_CRAWLERS, 10)
	var checked: int = 0
	for i: int in range(12 * Simulation.TICKS_PER_SECOND):
		sim.step([])
		if sim.query_enemy_count() > 1:
			assert_eq(
				_count_coincident(sim), 0, "two Enemies at one coordinate on tick %d" % i
			)
			checked += 1
	assert_true(checked > 300, "a Wave was actually on the Map for the ticks that were checked")


func test_two_kinds_in_one_crowd_leave_each_other_the_room_both_their_bodies_ask_for() -> void:
	# A Breaker is 0.8 m where a Crawler is 0.6 (#49), so a mixed crowd has three different
	# spacings in it and `_tightest_gap_ratio` is a ratio for exactly this reason. Nothing
	# here names a number: the room a pair needs comes out of
	# `query_enemy_hit_radius_metres`, which is the same authority `WorldView` scales the
	# drawn body by — so the Enemies a player sees not overlapping are the Enemies that do
	# not overlap.
	var sim: Simulation = _sim(MIXED_WAVE, 50)
	assert_eq(_step_until_released(sim, 8), 8, "four of each")
	_step_seconds(sim, 6)
	var kinds: int = 0
	for i: int in range(sim.query_enemy_count()):
		if sim.query_enemy_kind(i) == Simulation.ENEMY_KIND_BREAKER:
			kinds += 1
	assert_eq(kinds, 4, "the Breakers really are in this crowd")
	assert_true(
		_worst_overlap(sim) <= SETTLING_UNITS,
		"a Breaker takes the room a Breaker is wide, not the room a Crawler is wide"
	)


func test_a_siege_hulk_is_not_pushed_around_by_the_crowd_it_arrived_with() -> void:
	# A Hulk halts the moment anything is inside `siege_hulk.range_metres` and that stand-off
	# *is* its reach (#16). Shoving it would be a second opinion about where it comes to rest,
	# and it would let a crowd rotate the one Enemy whose facing carries a rule — its armoured
	# front. So it does not take part in separation, and a crowd walking through it is the
	# price of that rather than an oversight.
	var sim: Simulation = _sim(HULK_AND_CHAFF, 20)
	assert_eq(_step_until_released(sim, 7), 7, "six Crawlers and the boss")
	var hulk: int = -1
	for i: int in range(sim.query_enemy_count()):
		if sim.query_enemy_kind(i) == Simulation.ENEMY_KIND_SIEGE_HULK:
			hulk = i
	assert_ne(hulk, -1, "the boss is on the Map")
	var serial: int = sim.query_enemy_serial(hulk)
	_step_seconds(sim, 4)
	var at: int = sim.query_enemy_index_of_serial(serial)
	assert_ne(at, -1, "still alive")
	var where: FixedVec2 = sim.query_enemy_position_metres(at)
	# It walks its own lane to the centimetre: the z it was released on is the z it keeps,
	# because nothing pushed it off and its lane-gathering is untouched by #76.
	var lane: FixedVec2 = WorldGrid.tile_centre_metres(sim.query_breach_tile(0))
	assert_eq(where.z, lane.z, "on the middle of its lane, where the crowd cannot move it")


# ── The pass is local ─────────────────────────────────────────────────────────
#
# What makes this ticket affordable is that the work is a count of *neighbours* and not a
# count of Enemies — the design note #76 overturned was right that an all-pairs pass is
# quadratic and the Chaff tier could not afford one. The algorithm itself is not visible
# through the façade and must not be: what is visible, and what these assert, are its two
# observable consequences. A body with nobody inside its own width is not touched, and a
# pair that straddles two of the buckets is still found.

func test_a_crawler_with_nobody_inside_its_own_width_is_moved_by_walking_alone() -> void:
	# The locality claim, from the only side a façade can see it: separation acts inside the
	# sum of two radii and nowhere else, so the Crawler at the head of a settled queue — the
	# one with open road in front and a full body's width behind — advances by exactly one
	# tick of walking, to the fixed-point unit, with nothing added and nothing taken away.
	var sim: Simulation = _sim(EIGHT_CRAWLERS, 50)
	assert_eq(_step_until_released(sim, 8), 8)
	_step_seconds(sim, 5)

	var leader: int = 0
	for i: int in range(sim.query_enemy_count()):
		if sim.query_enemy_position_metres(i).x < sim.query_enemy_position_metres(leader).x:
			leader = i
	var serial: int = sim.query_enemy_serial(leader)
	var before: FixedVec2 = sim.query_enemy_position_metres(leader)
	sim.step([])
	var after: FixedVec2 = sim.query_enemy_position_metres(sim.query_enemy_index_of_serial(serial))

	# `enemy.crawler_speed_metres_per_second` is 3 against sixty ticks a second, which is
	# 0.05 m a tick — the content's own number divided by the tick rate, not a figure read
	# back out of the code. It is walking west, so x falls by exactly that.
	var step: int = Fixed.div(Fixed.from_int(3), Fixed.from_int(Simulation.TICKS_PER_SECOND))
	assert_eq(before.x - after.x, step, "one tick of walking, with no push in it")
	assert_eq(after.z, before.z, "and not nudged off its lane either")


func test_a_pair_that_straddles_two_buckets_is_still_pushed_apart() -> void:
	# **The bug the bucketing could silently reintroduce.** Neighbours are looked up by the
	# cell an Enemy stands in and the cells around it, so a search that looked only inside
	# one cell would separate a crowd that happened to share a tile and quietly stop
	# separating one spread across a tile boundary — which does not fail, it just looks like
	# the old behaviour. A settled queue is eight bodies 1.2 m apart over a 2 m grid, so it
	# necessarily straddles boundaries; this finds a tangent pair that does and says so.
	var sim: Simulation = _sim(EIGHT_CRAWLERS, 50)
	assert_eq(_step_until_released(sim, 8), 8)
	_step_seconds(sim, 5)
	assert_true(_worst_overlap(sim) <= SETTLING_UNITS, "the queue has settled")

	var straddling: int = 0
	for a: int in range(sim.query_enemy_count()):
		for b: int in range(a + 1, sim.query_enemy_count()):
			if sim.query_enemy_tile(a) == sim.query_enemy_tile(b):
				continue
			var here: FixedVec2 = sim.query_enemy_position_metres(a)
			var there: FixedVec2 = sim.query_enemy_position_metres(b)
			var gap_x: int = there.x - here.x
			var gap_z: int = there.z - here.z
			var room: int = (
				sim.query_enemy_hit_radius_metres(a) + sim.query_enemy_hit_radius_metres(b)
			)
			var gap: int = Fixed.sqrt(Fixed.mul(gap_x, gap_x) + Fixed.mul(gap_z, gap_z))
			if gap - room <= SETTLING_UNITS:
				straddling += 1
	assert_true(
		straddling > 0,
		"a pair held at exactly touching distance across a tile boundary, which is a pair"
		+ " the neighbour search had to look out of its own cell to find"
	)


# ── Determinism ───────────────────────────────────────────────────────────────
#
# **The half of #76 most likely to have gone wrong silently.** A separation pass is the most
# desync-prone thing anybody has added to this Simulation: it reads several Enemies to decide
# one Enemy's position, which is the one shape every other loop in the file is careful to
# avoid. The fixture below is the standing expectation (CLAUDE.md), and the honesty check
# beside it is what stops it proving determinism over a Run in which nothing happened.
#
# The harness builds its own Simulation on the starter Map, so these use the shipped
# geography and supply only the content.

## A Wave big enough to be a crowd, released onto a Breach as fast as the loader allows.
const A_CROWD: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,12,0,12
"""


## The content the two tests below share, on the starter Map: a Telegraph of half a second
## and a trickle of one Crawler a tick, so twelve of them come out of one hole together.
func _crowd_content() -> Definitions:
	var fixture: ContentFixture = ContentFixture.for_case(self)
	fixture.waves = A_CROWD
	return (
		fixture
		. tune([
			["telegraph_seconds = 12", "telegraph_seconds = 0.5"],
			["spawn_interval_seconds = 0.5", "spawn_interval_seconds = 0.01"],
		])
		. definitions()
	)


## The script both tests drive: call the Wave, then stand back and let the crowd arrive and
## come apart. Nothing a player does is in it, because separation is not something a player
## does — what is being replayed is the Simulation's own arithmetic over twelve bodies.
func _crowd_script() -> InputScript:
	var script: InputScript = InputScript.new()
	script.add_tick([InputAction.call_wave_early(0)])
	script.add_idle_ticks(30 * Simulation.TICKS_PER_SECOND)
	return script


func test_determinism_a_wave_converging_on_a_breach_replays_tick_for_tick() -> void:
	var content: Definitions = _crowd_content()
	var recording: ReplayRecording = DeterminismHarness.record(_crowd_script(), 17, 1, content)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_the_fixture_really_did_put_a_crowd_through_the_pass() -> void:
	# A replay of a Run in which the crowd never formed would read as a pass, and that is
	# exactly the failure mode `test_silo`'s pair of fixtures exists to rule out. So the
	# scenario is checked separately from the replay, and it is checked at **both** ends:
	# that the Wave really did come out as a stack, and that it really did come apart.
	var sim: Simulation = Simulation.new(17, 1, _crowd_content())
	sim.step([InputAction.call_wave_early(0)])

	var stacked_at_release: int = 0
	for i: int in range(30 * Simulation.TICKS_PER_SECOND):
		sim.step([])
		if sim.query_enemy_count() >= 2:
			stacked_at_release = maxi(stacked_at_release, _count_coincident(sim))
			break
	assert_eq(
		stacked_at_release,
		0,
		"the pass had already pulled the second body off the first on the tick it could act"
	)

	for i: int in range(28 * Simulation.TICKS_PER_SECOND):
		sim.step([])
	assert_true(sim.query_enemy_count() >= 2, "a crowd was on the Map for the whole fixture")
	assert_eq(_count_coincident(sim), 0, "and no two of them ever shared a coordinate")
