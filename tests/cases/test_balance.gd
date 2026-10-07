## The shape of the loop, asserted against the shipped content.
##
## #26's complaint was that the recorded Run lengths came from a Wave schedule that no longer
## existed and nobody could re-derive them. The fix is two things, and this file is the
## second: `BalanceProbe` is the instrument, and these are the claims the suite will not let
## a later content edit break silently.
##
## **Bands, not ticks.** The exact figures live in CLAUDE.md and come out of
## `tools/balance/measure.sh`; what is asserted here is the *shape* the spec asks for —
## build nothing and lose in a few minutes, build competently and get twenty to forty, and
## have over-production be a mistake you can see. A test that pinned the tick would turn
## every legitimate tuning change into a red suite, which is how a balance guard stops being
## read.
##
## Measured on 2026-10-07, seeds 7/11/29, `tools/balance/measure.sh`, with #30's collision
## in — which is why the two scenarios that walk anywhere read a little differently from
## #26's own figures. See "What collision cost the two sorties" in CLAUDE.md.
##
##     bare           4m22s   undefended
##     opening_line   4m04s   undefended, and sooner than bare
##     competent     27m00s   ran dry, then Breakers took the Factory
##     over_producer 19m36s   ran dry, 27% sooner
##     fortified     29m15s   swarmed, with 274 rounds still in the Factory
##     deep_digger   10m48s   dug too deep, two Breaches
##     hive_sortie   29m36s   ran dry, 2m36s later than competent
##     rifle_picket  26m32s   ran dry, 28s sooner than competent (and 26m29s on seeds 11/29)
extends TestCase

## An hour of game time. Every scenario here ends well inside it; reaching it is a failure
## and is asserted as one.
const CAP_TICKS: int = 60 * 60 * Simulation.TICKS_PER_SECOND

const A_FEW_MINUTES: int = 6 * 60
const TWENTY_MINUTES: int = 20 * 60
const FORTY_MINUTES: int = 40 * 60

## How much shorter over-producing has to make a Run before it counts as a *visible* mistake.
## A fifth: smaller than that and a player would put it down to a bad Wave.
const VISIBLE_MISTAKE_PERCENT: int = 20


## Reports already measured, keyed by scenario and seed.
##
## Not an optimisation for its own sake: a Run of `competent` is half a million ticks of
## Simulation and six of these tests want it. Playing it once and reading it six times is the
## difference between a balance guard the suite can afford to carry and one somebody
## eventually deletes. Safe because a report is a record of a finished Run and nothing here
## mutates one.
static var _measured: Dictionary = {}


func _play(scenario_id: String, world_seed: int = 7) -> BalanceProbe.Report:
	var key: String = "%s|%d" % [scenario_id, world_seed]
	if not _measured.has(key):
		_measured[key] = BalanceProbe.play(
			BalanceScenarios.by_id(scenario_id), world_seed, CAP_TICKS
		)
	return _measured[key]


# ── The loop the spec asks for ────────────────────────────────────────────────

func test_a_player_who_builds_nothing_loses_in_a_few_minutes() -> void:
	var report: BalanceProbe.Report = _play("bare")
	assert_true(report.nest_fell, "the Nest falls: %s" % report.cause())
	assert_eq(report.turrets_built, 0, "nothing was ever built to shoot with")
	assert_true(
		report.seconds() < A_FEW_MINUTES,
		"over in a few minutes, not %s" % report.clock()
	)
	assert_true(
		report.cause().contains("undefended"),
		"and the reason is nameable: %s" % report.cause()
	)


func test_producing_without_defending_summons_the_wave_sooner_than_doing_nothing() -> void:
	# The whole of #12's bet, as a two-row comparison: identical Machines to `competent` and
	# nothing shooting, so the only thing the production bought was Heat. It dies *sooner*
	# than the Factory that built nothing at all.
	var bare: BalanceProbe.Report = _play("bare")
	var line: BalanceProbe.Report = _play("opening_line")
	assert_true(line.most_heat_at_once > 0, "the line made Heat")
	assert_eq(bare.most_heat_at_once, 0, "where building nothing makes none")
	assert_true(
		line.end_tick < bare.end_tick,
		"so the Wave came sooner: %s against %s" % [line.clock(), bare.clock()]
	)


func test_a_competent_factory_reaches_twenty_to_forty_minutes() -> void:
	var report: BalanceProbe.Report = _play("competent")
	if not assert_true(report.nest_fell, "the Run ends inside the cap"):
		return
	assert_true(
		report.seconds() >= TWENTY_MINUTES and report.seconds() <= FORTY_MINUTES,
		"20-40 minutes, not %s" % report.clock()
	)


func test_a_competent_factory_loses_to_a_pressure_it_can_name() -> void:
	# The acceptance criterion that matters most, and the one a bare Run length cannot carry:
	# a player has to be able to say what killed them. "Ran dry" is the answer here — one Ammo
	# Press cannot keep one MG Turret fed once the Wave interval reaches its floor — and a
	# Factory with no Ammunition anywhere in it through the last two minutes is the evidence.
	var report: BalanceProbe.Report = _play("competent")
	assert_true(report.shots_fired > 0, "the Turret was fed and fired")
	assert_true(
		report.dry_endgame_percent() >= BalanceProbe.DRY_ENDGAME_PERCENT,
		"and ended with nothing to shoot: dry for %d%% of the endgame"
		% report.dry_endgame_percent()
	)
	assert_true(report.cause().contains("ran dry"), "named: %s" % report.cause())


func test_over_producing_is_a_visible_mistake() -> void:
	# `over_producer` and `competent` differ by one Machine: a Miner on the spare Node with no
	# Belt off it, bought with the plate the call-early lever pays. It produces nothing and
	# makes a Node's worth of Heat a minute, and the Run is measurably shorter for it.
	var competent: BalanceProbe.Report = _play("competent")
	var greedy: BalanceProbe.Report = _play("over_producer")
	if not assert_true(greedy.nest_fell and competent.nest_fell, "both Runs end"):
		return
	@warning_ignore("integer_division")
	var shorter_by: int = (competent.seconds() - greedy.seconds()) * 100 / competent.seconds()
	assert_true(
		shorter_by >= VISIBLE_MISTAKE_PERCENT,
		"over-producing cost %d%% of the Run (%s against %s), which has to be at least %d%%"
		% [shorter_by, greedy.clock(), competent.clock(), VISIBLE_MISTAKE_PERCENT]
	)
	assert_true(
		greedy.heat_per_minute > 0 or greedy.most_heat_at_once > competent.most_heat_at_once,
		"and it cost it in Heat: peaked at %d against %d"
		% [greedy.most_heat_at_once, competent.most_heat_at_once]
	)


func test_clearing_a_hive_lengthens_a_run() -> void:
	# `hive.heat_shadow_per_minute` is 30 of the 340 the Nest can shed, per Hive, and the
	# shipped Map carries two. A player who spends two minutes outside the Factory with a
	# wrench buys that back for the rest of the Run — which is the whole of why #16 says a
	# sortie is worth making.
	var competent: BalanceProbe.Report = _play("competent")
	var sortie: BalanceProbe.Report = _play("hive_sortie")
	assert_eq(sortie.hives_standing, 1, "one Hive came down")
	assert_eq(competent.hives_standing, 2, "where the Factory that stayed home kept both")
	assert_true(
		sortie.end_tick > competent.end_tick,
		"and the Run was longer for it: %s against %s" % [sortie.clock(), competent.clock()]
	)


func test_digging_deep_early_opens_a_second_breach_and_shortens_the_run() -> void:
	# #13's surcharge, played rather than reasoned about. Paying `t02_deep_mining` costs the
	# Ammunition that was defending you and five pulls of the call-early lever; what it buys
	# is a Depth 2 seam and a second Breach at (16, 4), in the middle of the ground the
	# opening Factory is standing on.
	var competent: BalanceProbe.Report = _play("competent")
	var greedy: BalanceProbe.Report = _play("deep_digger")
	assert_eq(greedy.depth_reached, 2, "a Miner Mk2 went onto the Depth 2 seam")
	assert_eq(greedy.breach_count, 2, "and digging it opened a second Breach")
	assert_eq(competent.breach_count, 1, "where the Factory that stayed shallow kept one")
	assert_true(
		greedy.end_tick < competent.end_tick,
		"and paid for it: %s against %s" % [greedy.clock(), competent.clock()]
	)
	assert_true(
		greedy.cause().contains("dug too deep"),
		"named as what it was: %s" % greedy.cause()
	)


# ── What the seed can and cannot reach ────────────────────────────────────────

func test_a_run_length_is_a_function_of_the_factory_and_not_of_the_seed() -> void:
	# **A finding asserted as a fact, and the reason three seeds are honest rather than
	# decorative.** The Map is handcrafted, the Wave schedule is a function of Heat, and the
	# single consumer of the seeded RNG in the whole Simulation is `_scatter` — the spread on
	# a *ranged* shot. So there is no distribution to sample here: three seeds are three
	# identical Runs, down to which Machines were lost in which order.
	#
	# Compared on `figures()` rather than on the state hash, which cannot answer this
	# question: `Simulation.hash()` feeds `_rng.state`, so two seeds differ in hash from tick
	# 0 whether or not a draw is ever taken.
	var seven: BalanceProbe.Report = _play("competent", 7)
	for world_seed: int in [11, 29]:
		var other: BalanceProbe.Report = _play("competent", world_seed)
		assert_eq(
			other.figures(),
			seven.figures(),
			"seed %d produced the same Run as seed 7" % world_seed
		)


func test_the_rifle_at_the_nest_is_a_fourth_claimant_on_one_ammo_press() -> void:
	# #17's open question, measured. A Bolt Rifle spends `ammunition` at 75 rounds a minute
	# out of the Nest's store; the Press makes 37. So a player who leans on the trigger is
	# competing with his own Turret, and the Run is shorter for it even though the rounds went
	# into Crawlers either way.
	#
	# This is also the only scenario a seed can reach at all, and the only row in the table
	# that is not bit-identical across seeds: 26m32s on seed 7 against 26m29s on 11 and 29.
	# Three seconds in twenty-six minutes — the spread moves where the rounds go without
	# moving how long the Nest stands, which is why the row above is the whole of the seed
	# story and why this one is asserted against `competent` rather than against a figure.
	var competent: BalanceProbe.Report = _play("competent")
	var picket: BalanceProbe.Report = _play("rifle_picket")
	assert_true(picket.nest_fell, "the Run ends")
	assert_true(
		picket.end_tick < competent.end_tick,
		"and sooner for the rifle: %s against %s" % [picket.clock(), competent.clock()]
	)


# ── The instrument itself ─────────────────────────────────────────────────────

func test_a_scenario_is_a_replayable_input_script() -> void:
	# What makes a measurement evidence rather than an anecdote: a `BalanceScenario` is a
	# function from tick to Input Actions and nothing else, so it goes into
	# `DeterminismHarness` unchanged and replays to the same state hash tick for tick. A
	# measurement harness that could not be replayed would be measuring something nobody
	# could reproduce.
	#
	# Two minutes of the Factory rather than the whole Run, because the harness compares
	# every tick and the claim is about the scenario's shape, not its length.
	var script: InputScript = BalanceScenarios.competent().to_script(
		120 * Simulation.TICKS_PER_SECOND
	)
	var recording: ReplayRecording = DeterminismHarness.record(script, 7, 1)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())
	assert_eq(
		divergence.ticks_compared,
		120 * Simulation.TICKS_PER_SECOND + 1,
		"every tick plus the starting state"
	)


func test_the_probe_reports_what_ran_out_rather_than_only_that_something_did() -> void:
	# The probe's own acceptance criterion. A report that said "the Nest fell at tick 108,000"
	# and nothing else would leave #26 exactly where it started, so every figure the cause is
	# derived from has to be on the report beside it.
	var report: BalanceProbe.Report = _play("competent")
	assert_true(report.machines_built >= 6, "it counted the Factory that was built")
	assert_true(report.shots_fired > 0, "the rounds that were spent")
	assert_true(report.endgame_ticks > 0, "the ticks of the endgame it judged dryness over")
	assert_true(report.samples.size() > 10, "and a sample a minute throughout")
	assert_true(report.most_ammunition_at_once > 0, "the Ammunition stockpile it built")
	assert_true(report.describe().contains("cause:"), "with the verdict spelled out")
