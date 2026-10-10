## Heat, the Wave schedule it drives, the Telegraph in front of every Wave, and the
## lever that calls one early. Through the Simulation façade, which is the only seam.
##
## The claim this file stands behind is the one that makes the game a game rather than a
## sandbox: **production is what hunts you**. A Factory that produces more is hotter, a
## hotter Factory is attacked sooner and harder, and a player can read both numbers off
## the façade before deciding whether to build the next Machine.
extends TestCase

## A Map with ore at two Depths and no Breach — the geography for studying Heat itself
## without a Wave arriving to interrupt. A Run with nowhere for Enemies to enter has no
## Waves at all, which is what makes this isolation honest rather than arranged.
func _heat_layout() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(-20, WorldGrid.GROUND_LAYER, -20)
	layout.add_node(Vector3i(4, WorldGrid.GROUND_LAYER, 4), "iron_ore", 1)
	layout.add_node(Vector3i(10, WorldGrid.GROUND_LAYER, 4), "iron_ore", 3)
	layout.sort_nodes()
	return layout


## A Map with the same ore and one Breach nineteen tiles from the Nest, for the half of
## this file that is about the schedule rather than about Heat itself.
func _threat_layout() -> MapLayout:
	var layout: MapLayout = _heat_layout()
	layout.add_breach(Vector3i(30, WorldGrid.GROUND_LAYER, -20))
	layout.sort_breaches()
	return layout


## The shipped content, with `overrides` applied to the tuning file as plain text
## substitutions. Every number not named is the real file's, so a test that cares about
## one key is still reading the balance the game ships.
func _content(overrides: Array = [], waves: String = "") -> Definitions:
	var fixture: ContentFixture = ContentFixture.for_case(self)
	fixture.deliveries = DELIVERIES
	fixture.gear = GEAR
	fixture.stratagems = STRATAGEMS
	if not waves.is_empty():
		fixture.waves = waves
	return fixture.tune(overrides).stock(STOCKED_BILL).definitions()


func _sim(overrides: Array = []) -> Simulation:
	return Simulation.new(12, 1, _content(overrides), _heat_layout())


## The tuning the schedule half of this file runs on: Heat that does not bleed away, so the
## arithmetic between a craft and an arrival time is exact and legible, and a thousand units
## a craft so a Factory reaches an interesting Heat in three seconds rather than ten minutes.
## The Telegraph is one second rather than twelve for the same reason.
##
## `decay_per_minute = 0` is deliberately a legal tuning value — a Map where the Nest hides
## nothing is a balance decision, not a broken file — and it is what lets these tests state
## a Heat as a literal.
const SCHEDULE_TUNING: Array = [
	["per_craft = 2", "per_craft = 1000"],
	["per_craft_per_depth = 1", "per_craft_per_depth = 0"],
	["decay_per_minute = 240", "decay_per_minute = 0"],
	["telegraph_seconds = 12", "telegraph_seconds = 1"],
	# The first Wave of a Run is deliberately sooner than the ones after it (#35), and the
	# tests below are about the Heat → interval *curve* rather than about a Run's opening
	# ramp — so the fixture puts the first interval back on the baseline and the curve is
	# read at one value throughout. `test_the_first_wave_is_sooner_than_the_baseline` is
	# where the ramp itself is asserted.
	["first_wave_interval_seconds = 90", "first_wave_interval_seconds = 150"],
]


func _schedule_overrides(extra: Array = []) -> Array:
	var overrides: Array = []
	for pair: Array in SCHEDULE_TUNING:
		overrides.append(PackedStringArray(pair))
	for pair: PackedStringArray in extra:
		overrides.append(pair)
	return overrides


## A Run on a Map with a Breach, on `SCHEDULE_TUNING`.
func _threat_sim(extra: Array = [], waves: String = "") -> Simulation:
	return Simulation.new(
		12, 1, _content(_schedule_overrides(extra), waves), _threat_layout()
	)


## A tuning override that takes the Power grid out of the picture, for the tests whose
## subject is Heat and not the brownout a deep Miner causes.
func _power_to_spare() -> Array:
	return [PackedStringArray(["baseline_supply_kw = 300", "baseline_supply_kw = 9000"])]


func _miner_index(sim: Simulation) -> int:
	return sim.query_definitions().machine_index("miner_mk1")


## The shallowest Miner tier that reaches a given Depth. A Miner cannot extract from ore
## deeper than its `max_depth` (#13), so a test studying Heat at Depth has to bring the tier
## that can actually lift it — and the shallowest one, so nothing here is paying for reach it
## is not using.
func _miner_for_depth(sim: Simulation, depth: int) -> int:
	for id: String in ["miner_mk1", "miner_mk2", "miner_mk3"]:
		var definition: MachineDefinition = sim.query_definitions().machine(id)
		if definition != null and definition.max_depth >= depth:
			return sim.query_definitions().machine_index(id)
	assert_true(false, "no shipped Miner reaches Depth %d" % depth)
	return -1


## Puts a Miner on the Node at `node_index` and steps the tick that places it, choosing the
## tier that reaches that Node's Depth.
func _build_miner(sim: Simulation, node_index: int) -> void:
	var tile: Vector3i = sim.query_node_tile(node_index)
	var tier: int = _miner_for_depth(sim, sim.query_node_depth(node_index))
	sim.step([InputAction.build_machine(0, tier, tile)])


func _step(sim: Simulation, ticks: int) -> void:
	for i: int in range(ticks):
		sim.step([])


# ── What Heat is made of ──────────────────────────────────────────────────────

func test_a_run_starts_cold() -> void:
	var sim: Simulation = _sim()
	assert_eq(sim.query_heat(), 0, "nothing has been produced yet")


func test_a_completed_craft_raises_heat() -> void:
	var sim: Simulation = _sim()
	_build_miner(sim, 0)
	# mine_iron_ore takes 1.5 s, which is 90 ticks, and a Machine does not run on the
	# tick it was built.
	_step(sim, 89)
	assert_eq(sim.query_heat(), 0, "one tick short of the first craft")
	sim.step([])
	# heat.per_craft is 2 and heat.per_craft_per_depth is 1, on a Depth 1 Node.
	assert_eq(sim.query_heat(), 3, "the first craft's Heat, and nothing before it")


func test_a_built_but_idle_machine_raises_no_heat() -> void:
	var sim: Simulation = _sim()
	# Bare rock, far from either Node: a Miner that accumulates no progress.
	sim.step([
		InputAction.build_machine(0, _miner_index(sim), Vector3i(30, WorldGrid.GROUND_LAYER, 30))
	])
	_step(sim, 300)
	assert_eq(
		sim.query_heat(),
		0,
		"Heat is throughput, not a count of Machines — building is not what hunts you"
	)


func test_a_deeper_node_is_a_louder_craft() -> void:
	# On a grid with room to spare: a Depth 3 Miner's draw scales with its Depth (#13), so on
	# the shipped baseline it would be throttled and the subject here would stop being Heat.
	var shallow: Simulation = _sim(_power_to_spare())
	var deep: Simulation = _sim(_power_to_spare())
	# Node 0 is the Depth 1 ore, Node 1 the Depth 3 ore — `_heat_layout` sorts them by
	# tile, and 4 comes before 10 on x.
	_build_miner(shallow, 0)
	_build_miner(deep, 1)
	_step(shallow, 90)
	_step(deep, 90)
	assert_eq(shallow.query_heat(), 3, "heat.per_craft plus one tier")
	assert_eq(deep.query_heat(), 5, "heat.per_craft plus three tiers — deeper ore is louder")


# ── The accumulator does not drift ────────────────────────────────────────────
# The point of this section, and the reason Heat is an integer with an integer credit
# behind its decay. A 40-hour Run sheds Heat for 8.6 million ticks; a per-tick fixed-point
# ratio would lose a fraction on every one of them.

## A Factory banked with a lot of Heat and nothing left running to add more, so what
## happens next is only the decay. `per_craft` is wound right up so one craft banks enough
## Heat to shed from for hours.
func _cooling_sim(decay_per_minute: int) -> Simulation:
	var sim: Simulation = _sim([
		PackedStringArray(["per_craft = 2", "per_craft = 1000000"]),
		PackedStringArray(["per_craft_per_depth = 1", "per_craft_per_depth = 0"]),
		PackedStringArray([
			"decay_per_minute = 240", "decay_per_minute = %d" % decay_per_minute
		]),
	])
	_build_miner(sim, 0)
	_step(sim, 90)
	assert_eq(sim.query_heat(), 1000000, "one craft's worth, before a single tick of decay")
	# Knocked down, so nothing adds Heat from here and the decay is the only thing moving.
	sim.step([InputAction.demolish(0, sim.query_node_tile(0))])
	assert_eq(sim.query_machine_count(), 0)
	return sim


func test_a_decay_slower_than_one_unit_a_tick_still_sheds_exactly() -> void:
	# The test that would catch the drift. One unit a minute is 1/3600 of a unit a tick,
	# which in 16.16 fixed point is 18 of 65536 — and 3600 ticks of that is 0.989 units,
	# not 1. Carried as an integer credit it is exactly 1.
	var sim: Simulation = _cooling_sim(1)
	# 3599 more, because the tick that demolished the Miner banked credit too.
	_step(sim, 3599)
	assert_eq(sim.query_heat(), 1000000 - 1, "one whole minute, one whole unit")

	_step(sim, 6 * Simulation.TICKS_PER_MINUTE)
	assert_eq(sim.query_heat(), 1000000 - 7, "and seven minutes is seven, not 6.92")


func test_the_decay_sheds_the_tuned_rate_a_minute_exactly() -> void:
	var sim: Simulation = _cooling_sim(240)
	# 240 a minute is one unit every fifteen ticks exactly. 3600 ticks of credit, plus the
	# tick that demolished the Miner, is 3601 ticks: 240 units with 1 tick of credit left
	# over, carried rather than thrown away.
	_step(sim, 3599)
	assert_eq(sim.query_heat(), 1000000 - 240, "one minute at 240 a minute")
	_step(sim, 15 * 10)
	assert_eq(sim.query_heat(), 1000000 - 250, "ten more units, fifteen ticks apart")


func test_a_rate_that_does_not_divide_the_minute_floors_once_over_the_whole_run() -> void:
	# 100 a minute is one unit every 36 ticks, so the remainder has to be carried. Over
	# 36000 ticks a per-tick floor would lose up to 1000 units; carried, it loses none.
	var sim: Simulation = _cooling_sim(100)
	_step(sim, 35)
	assert_eq(sim.query_heat(), 1000000 - 1, "the 36th tick of credit buys the first unit")
	_step(sim, 10 * Simulation.TICKS_PER_MINUTE - 36)
	assert_eq(sim.query_heat(), 1000000 - 1000, "ten minutes is a thousand units, exactly")


func test_a_factory_that_went_cold_does_not_bank_its_decay() -> void:
	# The rule Power credit obeys, for the same reason: a Nest with nothing to hide cannot
	# save the shedding up and spend it on a later spike.
	# A rate slow enough that an honest Factory sheds nothing inside this test — so any Heat
	# missing at the end was eaten by a bank rather than by the tick it was standing on.
	var sim: Simulation = _sim([
		PackedStringArray(["decay_per_minute = 240", "decay_per_minute = 1"])
	])
	assert_eq(sim.query_heat(), 0)
	# An hour of ticks with nothing running. Sixty units' worth of shedding, if a cold
	# Factory could bank shedding.
	_step(sim, 60 * Simulation.TICKS_PER_MINUTE)

	_build_miner(sim, 0)
	_step(sim, 90)
	assert_eq(
		sim.query_heat(), 3, "the first craft's Heat arrived whole, not swallowed by a bank"
	)


# ── Heat and its contributors are visible ─────────────────────────────────────

func test_each_machine_reports_the_heat_it_has_added() -> void:
	var sim: Simulation = _sim(_power_to_spare())
	_build_miner(sim, 0)
	_build_miner(sim, 1)
	_step(sim, 90)
	assert_eq(sim.query_machine_heat_units(0), 3, "the Depth 1 Miner's own contribution")
	assert_eq(sim.query_machine_heat_units(1), 5, "and the Depth 3 Miner's, separately")
	assert_eq(
		sim.query_heat(),
		8,
		"which is what the Factory's total is made of — a player can see the cause"
	)


func test_a_machine_reports_the_rate_it_is_heating_the_factory_at() -> void:
	var sim: Simulation = _sim()
	_build_miner(sim, 0)
	_step(sim, 90)
	# 3 units a craft and 90 ticks a craft, over 3600 ticks a minute: 120 a minute.
	assert_eq(sim.query_machine_heat_per_minute(0), 120)
	assert_eq(sim.query_heat_per_minute(), 120, "and the Factory's rate is the sum of them")


func test_a_machine_that_is_not_producing_reports_no_rate() -> void:
	var sim: Simulation = _sim()
	sim.step([
		InputAction.build_machine(0, _miner_index(sim), Vector3i(30, WorldGrid.GROUND_LAYER, 30))
	])
	_step(sim, 300)
	assert_eq(
		sim.query_machine_heat_per_minute(0),
		0,
		"a Miner over bare rock is not making the Factory loud"
	)
	assert_eq(sim.query_heat_per_minute(), 0)


func test_an_unknown_machine_reads_as_nothing_rather_than_crashing() -> void:
	var sim: Simulation = _sim()
	assert_eq(sim.query_machine_heat_units(99), 0, "never a plausible-looking default")
	assert_eq(sim.query_machine_heat_per_minute(99), 0)


func test_a_demolished_machine_takes_its_contribution_with_it() -> void:
	var sim: Simulation = _sim()
	_build_miner(sim, 0)
	_step(sim, 90)
	assert_eq(sim.query_machine_heat_units(0), 3)

	sim.step([InputAction.demolish(0, sim.query_node_tile(0))])
	assert_eq(sim.query_machine_count(), 0, "the Miner is gone")
	assert_eq(
		sim.query_heat(),
		3,
		"but the Heat it already made is not refunded — the Factory was loud, and was heard"
	)
	assert_eq(sim.query_heat_per_minute(), 0, "it is just no longer being loud")


## How many **Crawlers** the Wave now arriving will have sent through each Breach in total.
## The first one is already out by the end of the arrival tick, so
## `query_wave_spawns_remaining_of_kind` on its own understates the Wave by exactly that one.
##
## One tier rather than the whole Wave, because every assertion below is about what Heat
## does to the Chaff row: counting every kind would make these tests fail the day a second
## tier joins `content/waves.csv`, which is exactly the additive change the table exists to
## allow. #11 added the Breaker row and proved the point.
func _crawlers_in_the_wave(sim: Simulation) -> int:
	var already_out: int = 0
	for index: int in range(sim.query_enemy_count()):
		if sim.query_enemy_kind(index) == Simulation.ENEMY_KIND_CRAWLER:
			already_out += 1
	@warning_ignore("integer_division")
	var per_breach: int = already_out / maxi(sim.query_breach_count(), 1)
	return (
		sim.query_wave_spawns_remaining_of_kind(Simulation.ENEMY_KIND_CRAWLER) + per_breach
	)


# ── Heat drives when the next Wave arrives ────────────────────────────────────
# The half of the mechanic that makes a hot Factory hunted *sooner* and not merely harder.

func test_a_cold_factory_waits_the_full_baseline_for_its_first_wave() -> void:
	var sim: Simulation = _threat_sim()
	assert_eq(
		sim.query_wave_interval_ticks(),
		150 * Simulation.TICKS_PER_SECOND,
		"heat.wave_interval_baseline_seconds — this fixture puts the first interval there"
	)


func test_the_first_wave_is_sooner_than_the_baseline() -> void:
	# #35, in the player's words: *"crawlers dont seem to be coming"*. They were — two and a
	# half minutes out, in silence, on a Run whose most interesting thing is a Crawler.
	#
	# A shorter **first** interval rather than a shorter interval generally, because #26
	# measured the whole Heat → interval curve against played Runs and the curve is not what
	# was wrong. What was wrong is that a Run opens cold, so the baseline doubled as the
	# length of the one gap nobody has had the chance to shorten yet.
	var sim: Simulation = _threat_sim([
		PackedStringArray(["first_wave_interval_seconds = 150", "first_wave_interval_seconds = 45"])
	])
	assert_eq(
		sim.query_wave_interval_ticks(),
		45 * Simulation.TICKS_PER_SECOND,
		"heat.first_wave_interval_seconds, because no Wave has arrived yet"
	)


func test_every_wave_after_the_first_waits_the_full_baseline() -> void:
	# The other half: the opening ramp is one gap and not a new curve. Once a Wave has
	# arrived, the Factory is on the schedule #26 measured.
	var sim: Simulation = _threat_sim([
		PackedStringArray(["first_wave_interval_seconds = 150", "first_wave_interval_seconds = 45"])
	])
	for _tick: int in range(50 * Simulation.TICKS_PER_SECOND):
		sim.step([])
		if sim.query_wave_number() > 0:
			break
	assert_eq(sim.query_wave_number(), 1, "the first Wave arrived inside its short gap")
	assert_eq(
		sim.query_wave_interval_ticks(),
		150 * Simulation.TICKS_PER_SECOND,
		"and the gap to the second one is the baseline"
	)


func test_the_shipped_first_wave_is_well_inside_the_baseline() -> void:
	# The claim the report is actually about, made against the shipped file rather than
	# against a fixture: a first-run player meets a Crawler early enough to learn the loop.
	#
	# A minute and a half is the band rather than a tick, for the reason the whole of
	# `test_balance` asserts bands: the figure is `tools/balance/measure.sh`'s to move and a
	# test that pinned it would make every legitimate tuning change a red suite. What is
	# worth pinning is that it is **much** shorter than the gap between later Waves and
	# still longer than its own Telegraph — a first Wave that arrived before its warning
	# finished would be the ambush the Telegraph exists to prevent.
	var sim: Simulation = Simulation.new(12, 1, _content(), _threat_layout())
	var seconds: float = (
		float(sim.query_wave_interval_ticks()) / float(Simulation.TICKS_PER_SECOND)
	)
	assert_true(
		seconds <= 90.0,
		"the first Wave should be inside a minute and a half, got %fs" % seconds
	)
	var baseline: float = (
		float(sim.query_definitions().heat_wave_interval_baseline_seconds) / float(Fixed.ONE)
	)
	assert_true(
		seconds * 3.0 < baseline * 2.0,
		(
			"and comfortably inside the baseline it used to share: %fs against %fs"
			% [seconds, baseline]
		)
	)
	assert_true(
		seconds > float(sim.query_definitions().wave_telegraph_seconds) / float(Fixed.ONE),
		"and longer than its own Telegraph, got %fs" % seconds
	)


func test_a_factory_that_produces_meets_its_first_wave_sooner_than_an_idle_one() -> void:
	# The other half of the opening lesson, and the reason the first gap is shortened rather
	# than replaced by a fixed delay: **what a player builds in the first minute pulls the
	# first Wave towards them**, exactly as it pulls every later one. A fixed opening timer
	# would have taught the opposite — that the opening minute is free.
	var working: Simulation = Simulation.new(12, 1, _content(_power_to_spare()), _threat_layout())
	var idle: Simulation = Simulation.new(12, 1, _content(_power_to_spare()), _threat_layout())
	_build_miner(working, 0)
	for _tick: int in range(20 * Simulation.TICKS_PER_SECOND):
		working.step([])
		idle.step([])
	assert_true(working.query_heat() > 0, "the Miner made some noise")
	assert_true(
		working.query_ticks_until_next_wave() < idle.query_ticks_until_next_wave(),
		(
			"producing brought the first Wave in: %d ticks against the idle Run's %d"
			% [working.query_ticks_until_next_wave(), idle.query_ticks_until_next_wave()]
		)
	)


func test_a_hotter_factory_is_hunted_sooner() -> void:
	var sim: Simulation = _threat_sim()
	_build_miner(sim, 0)
	# Two crafts at 1000 units each: 90 ticks a craft, and the Miner does not run on the
	# tick it was built.
	_step(sim, 180)
	assert_eq(sim.query_heat(), 2000, "two crafts' worth")
	# heat.per_second_sooner is 20, so 2000 Heat buys the Enemy 100 seconds off the 150.
	assert_eq(sim.query_wave_interval_ticks(), 50 * Simulation.TICKS_PER_SECOND)


func test_the_countdown_moves_towards_the_player_as_the_factory_heats_up() -> void:
	# The whole lesson of the mechanic in one assertion: switching a line on does not
	# shorten the Wave after next, it shortens *this* one, and the player watches it happen.
	var sim: Simulation = _threat_sim()
	_build_miner(sim, 0)
	var before: int = sim.query_ticks_until_next_wave()
	assert_eq(before, 150 * Simulation.TICKS_PER_SECOND - 1, "one tick into a cold Run")

	_step(sim, 180)
	var after: int = sim.query_ticks_until_next_wave()
	assert_eq(after, 50 * Simulation.TICKS_PER_SECOND - 181, "181 ticks in, on a 50-second gap")
	assert_true(
		before - after > 180 * 2,
		"the clock came towards them by far more than the time that passed: %d to %d"
		% [before, after]
	)


func test_a_factory_that_cools_gets_its_breathing_room_back() -> void:
	# Which is what makes knocking a line down a real decision rather than a sunk cost.
	var sim: Simulation = _threat_sim([
		PackedStringArray(["decay_per_minute = 0", "decay_per_minute = 60000"])
	])
	_build_miner(sim, 0)
	_step(sim, 180)
	var hot: int = sim.query_wave_interval_ticks()
	assert_true(hot < 150 * Simulation.TICKS_PER_SECOND, "it got hot: %d" % hot)

	sim.step([InputAction.demolish(0, sim.query_node_tile(0))])
	_step(sim, 2 * Simulation.TICKS_PER_MINUTE)
	assert_eq(sim.query_heat(), 0, "and then it went quiet")
	assert_eq(
		sim.query_wave_interval_ticks(),
		150 * Simulation.TICKS_PER_SECOND,
		"so the gap is the baseline again"
	)


func test_the_interval_never_falls_below_the_tuned_minimum() -> void:
	# Past the floor, more Heat buys the Enemy more Enemies rather than less time.
	var sim: Simulation = _threat_sim([
		PackedStringArray(["per_craft = 1000", "per_craft = 1000000"])
	])
	_build_miner(sim, 0)
	_step(sim, 90)
	assert_eq(sim.query_heat(), 1000000)
	assert_eq(
		sim.query_wave_interval_ticks(),
		40 * Simulation.TICKS_PER_SECOND,
		"heat.wave_interval_minimum_seconds, and not a tick less"
	)


# ── The Telegraph precedes every Wave ─────────────────────────────────────────

func test_a_run_opens_with_no_telegraph_showing() -> void:
	var sim: Simulation = _threat_sim()
	assert_false(sim.query_wave_is_telegraphed(), "nothing is coming yet")
	assert_eq(sim.query_telegraph_ticks_served(), 0)
	assert_eq(sim.query_telegraph_ticks(), Simulation.TICKS_PER_SECOND, "the tuned second")


func test_every_wave_is_preceded_by_the_whole_telegraph() -> void:
	# The invariant the acceptance criterion names, asserted over a Factory that is heating
	# up the whole time — so the Waves are arriving sooner and sooner and the warning still
	# runs its full length in front of each one.
	# A Nest that cannot fall, because a lost Run stops the Waves and this test is about the
	# Waves rather than about losing.
	var sim: Simulation = _threat_sim([
		PackedStringArray(["health = 6000", "health = 100000000"])
	])
	_build_miner(sim, 0)

	var telegraph: int = sim.query_telegraph_ticks()
	var showing_for: int = 0
	var waves: int = 0
	for i: int in range(200 * Simulation.TICKS_PER_SECOND):
		var before: int = sim.query_wave_number()
		sim.step([])
		if sim.query_wave_number() > before:
			assert_true(
				showing_for >= telegraph,
				(
					"Wave %d arrived after only %d ticks of Telegraph, and the tuned warning"
					+ " is %d"
				) % [sim.query_wave_number(), showing_for, telegraph]
			)
			waves += 1
			showing_for = 0
		elif sim.query_wave_is_telegraphed():
			showing_for += 1
		else:
			showing_for = 0
	assert_true(waves >= 3, "and the fixture really did see several Waves: %d" % waves)


func test_a_heat_spike_cannot_pull_a_wave_out_of_a_clear_sky() -> void:
	# The hard case. A Factory 7910 ticks into a 9000-tick gap has no warning showing. One
	# craft then takes the gap to its 2400-tick floor, which is already in the past — so the
	# Wave is overdue the instant the craft lands, and it still has to wait out the full
	# Telegraph. Without that gate this is exactly the ambush the core loop must never be.
	var sim: Simulation = _threat_sim([
		PackedStringArray(["per_craft = 1000", "per_craft = 1000000"])
	])
	_step(sim, 7910)
	assert_false(sim.query_wave_is_telegraphed(), "a clear sky")

	_build_miner(sim, 0)
	_step(sim, 89)
	assert_eq(sim.query_heat(), 0, "one tick short of the craft")
	sim.step([])
	assert_eq(sim.query_heat(), 1000000, "and now the Factory is screaming")
	assert_true(sim.query_wave_is_telegraphed(), "the warning went up on the same tick")
	assert_eq(sim.query_wave_number(), 0, "and the Wave did not")

	var telegraph: int = sim.query_telegraph_ticks()
	for i: int in range(telegraph - 1):
		assert_true(sim.query_wave_is_telegraphed(), "the warning stays up")
		assert_eq(sim.query_wave_number(), 0, "and nothing has arrived yet")
		sim.step([])
	sim.step([])
	assert_eq(sim.query_wave_number(), 1, "the Wave arrives one whole Telegraph after the spike")


# ── The lever that calls a Wave early ─────────────────────────────────────────

func test_the_lever_brings_the_next_wave_forward_by_the_whole_remaining_gap() -> void:
	var sim: Simulation = _threat_sim()
	assert_eq(sim.query_call_wave_early_refusal(0), Simulation.Refusal.NONE, "the lever is live")

	sim.step([InputAction.call_wave_early(0)])
	assert_true(sim.query_wave_was_called_early(), "a player did this, not the clock")
	assert_true(sim.query_wave_is_telegraphed(), "and the warning went up at once")
	assert_eq(
		sim.query_ticks_until_next_wave(),
		sim.query_telegraph_ticks() - 1,
		"what is left is the Telegraph and nothing else"
	)

	_step(sim, sim.query_telegraph_ticks() - 1)
	assert_eq(sim.query_wave_number(), 1, "Wave 1, two and a half minutes early")
	assert_false(sim.query_wave_was_called_early(), "and the lever is back at rest")


func test_a_called_wave_still_waits_out_the_whole_telegraph() -> void:
	# The lever is a throttle, not a way for one player to ambush the other three.
	var sim: Simulation = _threat_sim()
	sim.step([InputAction.call_wave_early(0)])
	for i: int in range(sim.query_telegraph_ticks() - 2):
		assert_eq(sim.query_wave_number(), 0, "still inside the warning")
		sim.step([])
	sim.step([])
	assert_eq(sim.query_wave_number(), 1)


func test_the_lever_pays_a_bounty_of_every_item_to_whoever_pulled_it() -> void:
	var sim: Simulation = _threat_sim()
	var items: PackedStringArray = sim.query_definitions().item_ids()
	assert_true(items.size() >= 3, "the shipped content has coal, iron ore and iron plate")
	for item_id: String in items:
		assert_eq(sim.query_player_item(0, item_id), 400, "the opening stock the fixture sets")

	sim.step([InputAction.call_wave_early(0)])
	for item_id: String in items:
		assert_eq(
			sim.query_player_item(0, item_id),
			425,
			"plus wave.call_early_bounty_per_item of %s, to spend on meeting it" % item_id
		)


func test_the_lever_is_refused_while_the_wave_it_would_call_is_already_coming() -> void:
	var sim: Simulation = _threat_sim()
	sim.step([InputAction.call_wave_early(0)])
	assert_eq(
		sim.query_call_wave_early_refusal(0),
		Simulation.Refusal.WAVE_ALREADY_COMING,
		"there is nothing left to bring forward"
	)

	var before: int = sim.hash()
	var stock: int = sim.query_player_item(0, "iron_ore")
	sim.step([InputAction.call_wave_early(0)])
	sim.step([])
	var quiet: Simulation = _threat_sim()
	quiet.step([InputAction.call_wave_early(0)])
	quiet.step([])
	quiet.step([])
	assert_eq(sim.hash(), quiet.hash(), "a refused pull is a silent no-op")
	assert_eq(sim.query_player_item(0, "iron_ore"), stock, "and it is not paid twice")
	assert_ne(before, 0)


func test_the_lever_is_refused_while_a_wave_is_still_coming_out_of_the_breaches() -> void:
	# Calling then would stack two Waves behind one Telegraph.
	var sim: Simulation = _threat_sim()
	sim.step([InputAction.call_wave_early(0)])
	_step(sim, sim.query_telegraph_ticks() - 1)
	assert_eq(sim.query_wave_number(), 1)
	assert_true(sim.query_wave_spawns_remaining() > 0, "the Breach is still letting them out")
	assert_eq(
		sim.query_call_wave_early_refusal(0), Simulation.Refusal.WAVE_STILL_ARRIVING
	)


func test_the_lever_is_refused_on_a_map_with_nowhere_to_call_a_wave_from() -> void:
	var sim: Simulation = _sim()
	assert_eq(sim.query_breach_count(), 0)
	assert_eq(sim.query_call_wave_early_refusal(0), Simulation.Refusal.NO_BREACH)
	var before: int = sim.hash()
	sim.step([InputAction.call_wave_early(0)])
	var quiet: Simulation = _sim()
	quiet.step([])
	assert_eq(sim.hash(), quiet.hash(), "and pulling it does nothing at all")
	assert_ne(before, 0)


func test_the_lever_names_a_player_this_run_does_not_have() -> void:
	var sim: Simulation = _threat_sim()
	assert_eq(sim.query_call_wave_early_refusal(7), Simulation.Refusal.NO_SUCH_PLAYER)
	assert_eq(sim.query_call_wave_early_refusal(-1), Simulation.Refusal.NO_SUCH_PLAYER)


# ── Heat drives what is in the Wave ───────────────────────────────────────────

func test_a_hotter_factory_is_sent_a_bigger_wave() -> void:
	var cold: Simulation = _threat_sim()
	cold.step([InputAction.call_wave_early(0)])
	_step(cold, cold.query_telegraph_ticks() - 1)
	assert_eq(cold.query_wave_number(), 1)
	# content/waves.csv opens at 6 a Breach and buys one more every 1200 Heat.
	assert_eq(_crawlers_in_the_wave(cold), 6, "a cold Factory's Wave")

	var hot: Simulation = _threat_sim()
	_build_miner(hot, 0)
	_step(hot, 180)
	assert_eq(hot.query_heat(), 2000)
	hot.step([InputAction.call_wave_early(0)])
	_step(hot, hot.query_telegraph_ticks() - 1)
	assert_eq(hot.query_wave_number(), 1)
	assert_eq(_crawlers_in_the_wave(hot), 6 + 1, "2000 Heat at 1200 Heat an Enemy")


func test_a_waves_size_is_capped_by_the_table_rather_than_growing_for_ever() -> void:
	# A performance ceiling as much as a balance one: a Run left to cook must not try to put
	# a hundred thousand Enemies on the Map.
	var sim: Simulation = _threat_sim([
		PackedStringArray(["per_craft = 1000", "per_craft = 1000000"])
	])
	_build_miner(sim, 0)
	_step(sim, 90)
	sim.step([InputAction.call_wave_early(0)])
	_step(sim, sim.query_telegraph_ticks() - 1)
	assert_eq(sim.query_wave_number(), 1)
	assert_eq(_crawlers_in_the_wave(sim), 40, "max_per_breach, from the table")


func test_a_new_tier_in_the_wave_table_needs_no_code() -> void:
	# The acceptance criterion about composition being data: a second row, a second
	# threshold, and a Wave that is the sum of every tier the Factory has reached.
	var two_tiers: String = (
		"id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach\n"
		+ "a_chaff,crawler,0,2,0,2\n"
		+ "b_horde,crawler,1500,5,0,5\n"
	)
	var cold: Simulation = _threat_sim([], two_tiers)
	cold.step([InputAction.call_wave_early(0)])
	_step(cold, cold.query_telegraph_ticks() - 1)
	assert_eq(_crawlers_in_the_wave(cold), 2, "only the first tier has been reached")

	var hot: Simulation = _threat_sim([], two_tiers)
	_build_miner(hot, 0)
	_step(hot, 180)
	assert_eq(hot.query_heat(), 2000, "past the second tier's threshold")
	hot.step([InputAction.call_wave_early(0)])
	_step(hot, hot.query_telegraph_ticks() - 1)
	assert_eq(
		_crawlers_in_the_wave(hot),
		7,
		"both tiers — a hot Factory gets the Chaff it always got *and* the new horde"
	)


func test_a_wave_is_composed_once_rather_than_re_deciding_itself_while_it_spawns() -> void:
	# A Wave is a fact about how hot the Factory was when it was summoned. Otherwise a
	# player who switched a line off mid-Wave would watch Enemies vanish from the queue.
	var sim: Simulation = _threat_sim()
	_build_miner(sim, 0)
	_step(sim, 180)
	sim.step([InputAction.call_wave_early(0)])
	_step(sim, sim.query_telegraph_ticks() - 1)
	var owed: int = sim.query_wave_spawns_remaining()
	# 7 Crawlers at 2000 Heat, per content/waves.csv: the Chaff tier buys one more every 1200
	# Heat and nothing else has opened yet. No Breaker and no Siege Hulk — #26 measured what
	# one Ammo Press can feed and moved those tiers to 5200 and 6400, so a Factory has to be
	# very much louder than this one before the Wave stops being Chaff.
	assert_eq(owed, 6, "7 summoned, one already out of the Breach")

	sim.step([InputAction.demolish(0, sim.query_node_tile(0))])
	assert_eq(sim.query_heat(), 2000, "the Heat it already made stands")
	assert_eq(sim.query_wave_spawns_remaining(), owed, "and the Wave still owes every one")
	# wave.spawn_interval_seconds is half a second, so the next one is thirty ticks behind.
	_step(sim, 30)
	assert_eq(
		sim.query_wave_spawns_remaining(),
		owed - 1,
		"it keeps sending the Wave it was summoned with rather than re-deciding it"
	)


func test_the_wave_table_says_which_kind_each_enemy_is() -> void:
	var sim: Simulation = _threat_sim()
	sim.step([InputAction.call_wave_early(0)])
	assert_eq(
		sim.query_wave_spawns_remaining_of_kind(EnemyKind.CRAWLER),
		0,
		"nothing is owed before the Wave arrives"
	)
	_step(sim, sim.query_telegraph_ticks() - 1)
	assert_eq(sim.query_wave_spawns_remaining_of_kind(EnemyKind.CRAWLER), 5, "of the six")
	assert_eq(sim.query_wave_spawns_remaining_of_kind(99), 0, "and no kind that does not exist")


# ── Building is never disabled ────────────────────────────────────────────────

func test_a_machine_can_be_built_while_a_wave_is_on_the_map() -> void:
	# GLOSSARY.md: the Build Gun is available at all times, including mid-Wave. There is no
	# flag to check, which is the point — this test exists to prove nobody added one.
	var sim: Simulation = _threat_sim()
	sim.step([InputAction.call_wave_early(0)])
	_step(sim, sim.query_telegraph_ticks() + Simulation.TICKS_PER_SECOND)
	assert_true(sim.query_enemy_count() > 0, "Crawlers are on the Map")
	assert_true(sim.query_wave_spawns_remaining() > 0, "and more are still coming")

	_build_miner(sim, 0)
	assert_eq(sim.query_machine_count(), 1, "and a player built a Miner anyway")
	_step(sim, 90)
	assert_eq(sim.query_heat(), 1000, "which promptly made things worse, as intended")


# ── Round-tripping through a save ─────────────────────────────────────────────

func test_heat_and_the_whole_schedule_survive_a_save_and_a_resume() -> void:
	# Power out of the way, because this works the Depth 3 Node and what that costs on the
	# grid (#13) is `test_depth`'s subject rather than this one's.
	var content: Definitions = _content(_schedule_overrides(_power_to_spare()))
	var sim: Simulation = Simulation.new(12, 1, content, _threat_layout())
	_build_miner(sim, 0)
	_build_miner(sim, 1)
	_step(sim, 200)
	sim.step([InputAction.call_wave_early(0)])
	_step(sim, 20)
	assert_true(sim.query_heat() > 0, "the Factory is hot")
	assert_true(sim.query_wave_is_telegraphed(), "and caught mid-Telegraph, which is the hard bit")

	var loaded: RunSave.Load = RunSave.deserialise(
		RunSave.serialise(sim), content, Simulation.new(0, 1, content, MapLayout.empty())
	)
	assert_false(loaded.has_errors(), loaded.describe_errors())
	assert_eq(
		loaded.simulation.hash(),
		sim.hash(),
		"Heat, its decay credit, the Wave clock, the Telegraph and the release queue all came back"
	)
	assert_eq(loaded.simulation.query_heat(), sim.query_heat())
	assert_eq(loaded.simulation.query_telegraph_ticks_served(), sim.query_telegraph_ticks_served())
	assert_true(loaded.simulation.query_wave_was_called_early(), "including the pulled lever")


func test_a_resumed_run_arrives_at_the_same_wave_on_the_same_tick() -> void:
	# The round trip proves the state came back; this proves it came back *usable*, which is
	# the thing a player cares about: a saved Run and the Run it was saved from are hunted
	# identically from there on.
	var content: Definitions = _content(_schedule_overrides())
	var sim: Simulation = Simulation.new(12, 1, content, _threat_layout())
	_build_miner(sim, 0)
	# Fifty ticks short of the Wave this Factory's Heat has earned, so the arrival lands
	# inside the comparison below rather than before it.
	_step(sim, 2349)

	var loaded: RunSave.Load = RunSave.deserialise(
		RunSave.serialise(sim), content, Simulation.new(0, 1, content, MapLayout.empty())
	)
	assert_false(loaded.has_errors(), loaded.describe_errors())
	var resumed: Simulation = loaded.simulation
	for i: int in range(100):
		sim.step([])
		resumed.step([])
		assert_eq(resumed.hash(), sim.hash(), "diverged on tick %d after the resume" % i)
	assert_true(sim.query_wave_number() >= 1, "and a Wave arrived inside the comparison")


# ── Replay fixtures ───────────────────────────────────────────────────────────
# Three of them, on the content the game actually ships: Heat rising with throughput, a Wave
# arriving earlier because of it, and a Wave a player called. `record` is given no
# definitions, so the replay re-reads content/ and a balance change that would alter the Run
# is reported as a `definitions_mismatch` rather than passing unnoticed.

## The starter Map's three Depth 1 Nodes, each with the Miner that can work it. Three Miners
## is past `power.baseline_supply_kw`, so this Factory is in a brownout as well as being loud —
## which is the realistic case, and the one where a Heat rate and a duty cycle have to agree.
##
## The Map's deeper seams are deliberately left alone: what Depth costs is `test_depth`'s
## subject, and a fixture about Heat rising with throughput should not also be a fixture about
## a Breach opening.
func _three_miners(sim: Simulation) -> Array:
	var iron: int = sim.query_definitions().machine_index("miner_mk1")
	var coal: int = sim.query_definitions().machine_index("coal_miner_mk1")
	var actions: Array = []
	for index: int in range(sim.query_node_count()):
		if sim.query_node_depth(index) != 1:
			continue
		var definition_index: int = coal if sim.query_node_resource(index) == "coal" else iron
		actions.append(InputAction.build_machine(0, definition_index, sim.query_node_tile(index)))
	return actions


func test_determinism_heat_rising_with_throughput_replays_identically() -> void:
	var sim: Simulation = Simulation.new(21, 1)
	var opening: Array = _three_miners(sim)
	assert_eq(opening.size(), 3, "the starter Map has three Nodes at Depth 1")

	var script: InputScript = InputScript.new()
	script.add_tick(opening)
	script.add_idle_ticks(5 * Simulation.TICKS_PER_MINUTE)

	var recording: ReplayRecording = DeterminismHarness.record(script, 21, 1)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_the_fixture_really_did_heat_the_factory_up() -> void:
	# A fixture that proved determinism over a Factory that never got hot would prove
	# nothing, so the scenario is checked separately from the replay.
	var sim: Simulation = Simulation.new(21, 1)
	sim.step(_three_miners(sim))
	var readings: PackedInt64Array = PackedInt64Array()
	# Three minutes, where the replay beside it runs five. The shipped Map carries two Hives
	# since #16 and a standing Hive drowns out part of what the Nest can hide, so three
	# undefended Miners now cross `content/waves.csv`'s 500-Heat Breaker threshold inside three
	# minutes — and a Breaker eats the Miners that were making the Heat, after which the reading
	# falls. That is the mechanic working rather than failing, and what this fixture is for is
	# the climb, so it measures the climb. The replay still covers all five minutes, including
	# the Factory being taken apart.
	for minute: int in range(3):
		_step(sim, Simulation.TICKS_PER_MINUTE)
		readings.append(sim.query_heat())

	assert_true(readings[0] > 0, "the first minute of production made Heat: %d" % readings[0])
	for index: int in range(1, readings.size()):
		assert_true(
			readings[index] > readings[index - 1],
			"minute %d was hotter than minute %d: %s" % [index + 1, index, readings]
		)
	assert_true(
		sim.query_heat_per_minute() > sim.query_heat_decay_per_minute(),
		"three Miners out-produce what the Nest can hide, which is why it keeps climbing"
	)
	for index: int in range(sim.query_machine_count()):
		assert_true(
			sim.query_machine_heat_units(index) > 0,
			"and every one of them is a visible contributor"
		)


func test_determinism_a_wave_pulled_in_by_heat_replays_identically() -> void:
	var sim: Simulation = Simulation.new(22, 1)
	var script: InputScript = InputScript.new()
	script.add_tick(_three_miners(sim))
	# Long enough to cover the arrival and the Telegraph in front of it, with room to spare:
	# what is asserted is that a Heat-shortened arrival replays, not where it lands. The
	# figures themselves are `tools/balance/measure.sh`'s business.
	script.add_idle_ticks(150 * Simulation.TICKS_PER_SECOND)

	var recording: ReplayRecording = DeterminismHarness.record(script, 22, 1)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_the_fixture_really_did_pull_the_wave_in() -> void:
	var hot: Simulation = Simulation.new(22, 1)
	hot.step(_three_miners(hot))
	var cold: Simulation = Simulation.new(22, 1)
	cold.step([])

	# Measured rather than written down, because the tick a Wave lands on is a function of
	# four tuning keys and #35 moved one of them: what this test is about is the *gap*
	# between a working Factory's arrival and an idle one's, which is the whole of what Heat
	# bought the Enemy. `tools/balance/measure.sh` is where the figures live.
	var hot_tick: int = -1
	var cold_tick: int = -1
	for i: int in range(150 * Simulation.TICKS_PER_SECOND):
		hot.step([])
		cold.step([])
		if hot_tick < 0 and hot.query_wave_number() > 0:
			hot_tick = hot.query_tick()
		if cold_tick < 0 and cold.query_wave_number() > 0:
			cold_tick = cold.query_tick()
		if hot_tick >= 0 and cold_tick >= 0:
			break

	assert_eq(cold.query_heat(), 0, "the idle Factory never made a sound")
	assert_true(hot.query_heat() > 0, "the working Factory is hot: %d" % hot.query_heat())
	assert_true(hot_tick > 0 and cold_tick > 0, "both Runs were attacked eventually")
	assert_true(
		hot_tick < cold_tick,
		"Heat brought the Wave in: hot at tick %d against idle at %d" % [hot_tick, cold_tick]
	)
	assert_true(
		hot.query_wave_interval_ticks() < cold.query_wave_interval_ticks(),
		"because Heat shortened its gap: %d against %d"
		% [hot.query_wave_interval_ticks(), cold.query_wave_interval_ticks()]
	)


func test_determinism_a_called_wave_replays_identically() -> void:
	var script: InputScript = InputScript.new()
	script.add_idle_ticks(10)
	script.add_tick([InputAction.call_wave_early(0)])
	# The shipped Telegraph is twelve seconds, and then the Wave trickles out.
	script.add_idle_ticks(30 * Simulation.TICKS_PER_SECOND)

	var recording: ReplayRecording = DeterminismHarness.record(script, 23, 1)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_the_fixture_really_did_call_a_wave_early() -> void:
	var sim: Simulation = Simulation.new(23, 1)
	_step(sim, 10)
	assert_eq(sim.query_wave_number(), 0)
	assert_false(sim.query_wave_is_telegraphed(), "nothing was coming")

	sim.step([InputAction.call_wave_early(0)])
	assert_true(sim.query_wave_was_called_early())
	# The shipped Telegraph, to the tick.
	_step(sim, 12 * Simulation.TICKS_PER_SECOND - 1)
	assert_eq(sim.query_wave_number(), 1, "a Wave 138 seconds before the clock would have sent it")
	_step(sim, 18 * Simulation.TICKS_PER_SECOND)
	assert_eq(sim.query_enemy_count(), 6, "with the composition a cold Factory earns")


# ── Hot-reloading the Wave table ──────────────────────────────────────────────

func test_rebalancing_the_wave_table_mid_run_changes_the_next_wave() -> void:
	# `content/waves.csv` is content, so editing it while the game runs applies on save like
	# every other content file — which is the whole reason composition is a table.
	var sim: Simulation = _threat_sim()
	var bigger: Definitions = _content(
		_schedule_overrides(),
		(
			"id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach\n"
			+ "chaff_crawlers,crawler,0,11,0,11\n"
		)
	)
	assert_false(bigger.has_errors(), bigger.describe_errors())

	sim.step([InputAction.reload_definitions(0, bigger)])
	sim.step([InputAction.call_wave_early(0)])
	_step(sim, sim.query_telegraph_ticks() - 1)
	assert_eq(sim.query_wave_number(), 1)
	assert_eq(_crawlers_in_the_wave(sim), 11, "the reloaded table decided the Wave")


# ── Fixtures that keep progression out of the way ─────────────────────────────
# The shipped Delivery chain locks the Ammo Press and the MG Turret behind its first tier
# and a Run opens holding exactly the plates for one line (`content/deliveries.csv`,
# `content/tuning.toml`). Both are balance rather than anything asserted in this file, so
# these fixtures replace them with a tier that locks nothing and a stock that pays for
# anything. `test_delivery.gd` is where the real chain is asserted.

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
