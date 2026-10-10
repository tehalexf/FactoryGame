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
## Measured on 2026-10-09, seeds 7/11/29, `tools/balance/measure.sh`, with everything up to and
## including #62 in. **All fifteen rows of record reproduced #60's figures exactly** — every
## clock, Wave, peak Heat and list of Machines lost — which is the fourth time this table has
## been independently re-derived rather than carried forward. See "The table, measured
## 2026-10-09", "What #60 measured" and "What #62 measured" in CLAUDE.md.
##
## Two rows now spread across seeds rather than one, and both are rows that fire a ranged
## weapon: `rifle_picket` by 39 seconds and `armed_player` by one. `armed_second_press` fires one
## too and is bit-identical on all three, because 133 shots are too few to change which Wave
## lands last — so firing a weapon is necessary for a spread and not sufficient.
##
##     bare                3m22s   undefended — #35's shorter first Wave, a minute off
##     opening_line        3m12s   undefended, and sooner than bare
##     competent          28m48s   a Siege Hulk standing, with 96 rounds still in the Factory
##     over_producer      20m21s   the same, 29% sooner
##     fortified          28m45s   the same, with 112 rounds unspent — a wash against competent
##     deep_digger        12m27s   swarmed with two Breaches open
##     hive_sortie        32m05s   the same, 3m17s later than competent — the longest Run measured
##     rifle_picket       27m18s   swarmed, 90s sooner than competent
##     artillery          16m40s   swarmed, 42% sooner — one Stratagem fired on two Charges
##     second_press       24m14s   swarmed with 416 rounds unspent — the pair makes it *shorter*
##     walled_lane        28m45s   11 Walls, every one standing, nothing ever bit one
##     sealed_breach      26m42s   ran dry; 7 Walls built, 3 left, 980 hit points absorbed
##     branched_artillery 13m57s   the Silo fires, and branching is dearer than a second Smelter
##     deep_silo          12m59s   Depth 2 and a Silo; the Barrage was never unlocked
##     coal_haul          15m41s   *longer* than deep_digger, browned out for 47% of itself
##     armed_player       24m14s   a player armed off the store, dry 9% — one Press serves both
##     armed_second_press 14m43s   dry 83% on 240 unspent rounds — the worst build measured
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
	# a player has to be able to say what killed them.
	#
	# **#34 changed the answer, which is the whole point of #34.** It used to be "ran dry, and
	# then the Breakers took the Factory" — and the Breaker half of that was a rule a player
	# could not see, because a Breaker never walked into the reach of the Turret they had built.
	# Now a Breaker marches the lane under fire, the documented Factory holds its Machines
	# through the whole Breaker tier with rounds to spare, and what ends the Run is the boss:
	# three Siege Hulks that a Factory cannot answer **by design** (DESIGN.md — it outranges
	# Turrets and its frontal armour leaves an MG doing 2) and a player on foot can.
	#
	# That is a nameable pressure in the strong sense: the Hulk walks in, halts and shells, the
	# HUD draws where the shell will land, and the answer is the first-person pillar the game
	# already ships. Asserted as "the tier arrived and Ammunition was not what ran out",
	# because the exact figure belongs in CLAUDE.md.
	var report: BalanceProbe.Report = _play("competent")
	assert_true(report.shots_fired > 0, "the Turret was fed and fired")
	assert_true(report.a_breaker_arrived, "the Breaker tier arrived")
	assert_true(
		report.dry_endgame_percent() < BalanceProbe.DRY_ENDGAME_PERCENT,
		"Ammunition was not what ran out: dry for %d%% of the endgame, %d rounds left"
		% [report.dry_endgame_percent(), report.ammunition_in_the_factory]
	)
	# **And this is the assertion that says the Breaker tier was survived**, which is worth
	# spelling out because it looks indirect. Heat is made by Machines that are working, so
	# `siege_hulks.min_heat` of 6400 is unreachable for a Factory whose production line was
	# eaten at 5200 — which is exactly the argument #26 set that number on. A Run that met the
	# boss is a Run that still had five production Machines after the Breakers came, and before
	# #34 no measured Run ever got there at all.
	assert_true(
		report.a_siege_hulk_arrived,
		"and the boss did, which only a Factory that kept its line through the Breakers reaches"
	)
	assert_true(report.cause().contains("Siege Hulk"), "named: %s" % report.cause())


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


## How much of a Run two scenarios may differ by and still count as the same length. A
## minute and a half in a Run of twenty-six minutes: smaller than the swing #30's collision
## and #35's schedule each produced on their own, so a difference inside it is phase and not
## a mechanic.
## **Widened from 90 to 150 by #47, and the reason is a cost the row now carries rather than a
## weaker claim.** Pricing a Belt per tile means the twenty-four-tile haul that banks the
## picket's magazine at the Nest is bought with a pull of the call-early lever — one Wave
## arriving sooner than it would have — where before it was free. That is a real cost on top of
## the rounds, and it lands in the same phase noise this constant exists to tolerate: the row
## measured 27m18s against `competent`'s 28m48s, which is 90 seconds exactly and would sit on
## the old boundary. The claim is unchanged and is still the one the figures support — a
## rifleman is neither free nor ruinous — and a later Ammunition change that made the rifle
## genuinely cheap or genuinely fatal still fails here.
##
## **Widened again to 300 by #76, and this is the first move with a mechanism behind it rather
## than phase.** Separation spreads a crowd, and a spread crowd is a worse target for a
## *scattering* weapon: an interpenetrating stack was several Crawlers at one coordinate, so a
## round that missed the one it was aimed at very often hit a neighbour standing inside it. The
## row measured **25m03s against `competent`'s 28m51s**, which is 228 seconds. Both rows moved
## in the same direction for the same reason and the picket moved further, because it is the
## one row that fires a scattering weapon at all — `competent`'s Turret resolves on an Enemy's
## *point* and never on its hit volume, so the spread costs it nothing.
##
## The claim is still the one the figures support and is deliberately not restated: a rifleman
## is **neither free nor ruinous**, now within five minutes of a twenty-nine-minute Run rather
## than within two and a half. What would still fail here is the thing this guards — a change
## that made the rifle pay for itself, or one that made standing at the Nest with it fatal.
const SAME_LENGTH_SECONDS: int = 300


func test_the_rifle_at_the_nest_is_a_fourth_claimant_on_one_ammo_press() -> void:
	# #17's open question, measured — and **the claim has now flipped, so what is asserted is
	# what was measured.** A Bolt Rifle spends `ammunition` at 75 rounds a minute out of the
	# Nest's store against a Press that makes 37, so the mechanism is real: a player who
	# leans on the trigger is competing with his own Turret. What the harness cannot show any
	# more is that it *costs* anything end to end.
	#
	# #26 measured a two-minute penalty. #30's collision moved the picket's open-loop stance
	# and took it to 28 seconds. #34's Breaker approach took it back out to 1m54s. #35's
	# shorter first Wave moved the whole schedule's phase and, measured on its own branch,
	# crossed zero — 26m52s against `competent`'s 26m42s, ten seconds the *other* way.
	#
	# Merged, it was 46 seconds and back on the original side: 28m02s against 28m48s. **#47
	# then made it 90 seconds** — 27m18s against 28m48s — by giving the haul that banks his
	# magazine a price, which the row buys with a lever pull. So the sign or the size of this
	# margin has now moved five times across five tickets without anything about the
	# Ammunition economy changing, which is the finding. It is not a penalty with a value; it
	# is phase noise in a schedule that other tickets keep re-phasing.
	#
	# So the claim this guards is the one the figures still support: a rifleman at the Nest is
	# **neither free nor ruinous** — the fourth claimant costs about what it takes, within the
	# phase noise of the schedule. A later Ammunition change that made the rifle genuinely
	# cheap or genuinely fatal would move it outside `SAME_LENGTH_SECONDS` and fail here.
	var competent: BalanceProbe.Report = _play("competent")
	var picket: BalanceProbe.Report = _play("rifle_picket")
	assert_true(picket.nest_fell, "the Run ends")
	var apart: int = absi(picket.end_tick - competent.end_tick)
	assert_true(
		apart <= SAME_LENGTH_SECONDS * Simulation.TICKS_PER_SECOND,
		(
			"the rifle should cost about what it takes: %s against %s"
			% [picket.clock(), competent.clock()]
		)
	)


# ── The acceptance test: a Factory powers, loads and fires a Silo ────────────

func test_a_factory_can_power_load_and_fire_a_silo_within_a_run() -> void:
	# **#37's first dead end, closed.** #26 recorded "Milestone 1 cannot power a Silo" as a
	# finding rather than a number: the opening Factory draws 660 kW of the 900 one Steam Boiler
	# and the Nest's baseline plant supply, a Silo wants 400 more, and the Map has one coal Node
	# yielding 40 coal a minute against a Boiler's 30 — "so there is no second Boiler to be had".
	#
	# That last step is the one that does not follow. A Boiler is on the grid only *while it is
	# burning*, so 40 coal a minute is 1.33 Boilers burning rather than one Boiler burning and 10
	# coal a minute piling up on a Belt: two Boilers on one Node are worth about 800 kW averaged
	# over time instead of 600, and 300 + 800 pays for a Silo. The Power was already there to be
	# built toward, which is why nothing in `content/` changed for this.
	#
	# **Demonstrated rather than asserted**, which is the acceptance criterion's own wording: the
	# `artillery` scenario grows the Factory out of lever plate, stands a Silo up, walks a player
	# to it, commits two Charges to a Sentry Drop and holds the key on the tile it wants it on.
	# `stratagems_fired` is Simulation state, so this is a Stratagem that was called in and not an
	# effect somebody inferred.
	var report: BalanceProbe.Report = _play("artillery")
	assert_eq(report.silos_standing, 1, "a Silo was built and was still standing at the end")
	assert_true(
		report.most_charges_banked > 0,
		"it assembled Charges out of Belt-fed plate and rounds"
	)
	assert_eq(report.stratagems_fired, 1, "and one was called in: %s" % report.cause())
	assert_eq(
		report.charges_fired,
		BalanceScenarios.CHARGES_PER_LOAD,
		"with both the Charges the dial committed, because a Charge is a multiplier"
	)
	assert_eq(report.charges_wasted, 0, "and the Painting was not interrupted")


func test_building_artillery_costs_a_run_a_visible_part_of_its_length() -> void:
	# The other half of the acceptance criterion: getting there has to have *cost* something, or
	# a weapon of last resort is a free one. Against `competent` — the same six Machines on the
	# same tiles — artillery is four more Machines, four more Belts, seven pulls of the call-early
	# lever, 400 kW of a grid that was running on 240 of headroom, and a third claimant on the one
	# Ammo Press — which since #46 takes an equal share of that Press rather than the overflow
	# off the Turret's Belt, and is 48 seconds of the price. The Run is measurably shorter for all
	# of it: 16m40s against 28m48s, which is 42%.
	#
	# Asserted as a band rather than a figure, like every other claim in this file: what matters
	# is that the Silo is a decision with a price and not a button.
	var competent: BalanceProbe.Report = _play("competent")
	var artillery: BalanceProbe.Report = _play("artillery")
	if not assert_true(artillery.nest_fell and competent.nest_fell, "both Runs end"):
		return
	assert_true(
		artillery.end_tick < competent.end_tick,
		"artillery shortened the Run: %s against %s" % [artillery.clock(), competent.clock()]
	)
	@warning_ignore("integer_division")
	var shorter_by: int = (
		(competent.seconds() - artillery.seconds()) * 100 / competent.seconds()
	)
	assert_true(
		shorter_by >= VISIBLE_MISTAKE_PERCENT,
		"and by enough to feel: %d%% of the Run" % shorter_by
	)


# ── #60: the claims the table had been making on arithmetic ─────────────────

func test_a_second_ammo_press_and_a_second_turret_bank_rounds_nobody_can_spend() -> void:
	# **The claim this project has made since #10, measured at last, and it does not hold.** A
	# second Ammo Press is "the arithmetic answer to the middle of the Run" — production is the
	# defence — and #34 sharpened rather than answered it: `competent` ends with 96 rounds
	# unspent and `fortified` with 112, so one Turret cannot spend what one Press makes. The
	# obvious next build is therefore both at once, and nobody had played it.
	#
	# Measured, the pair makes the Run **shorter** and leaves four times as many rounds on the
	# shelf. What binds is neither Presses nor guns: it is how many Enemies walk inside a
	# Turret's 8 tiles, and the Heat and Power four more Machines' worth of Factory costs.
	#
	# Asserted as two bands rather than as the figures: the Run is not longer, and the Factory
	# finishes holding several times the rounds `competent` finishes holding. A later change that
	# made a second Press genuinely pay would fail here, which is the point.
	var competent: BalanceProbe.Report = _play("competent")
	var pair: BalanceProbe.Report = _play("second_press")
	if not assert_true(pair.nest_fell and competent.nest_fell, "both Runs end"):
		return
	assert_eq(pair.turrets_built, 2, "a second Turret stood")
	assert_true(
		pair.machines_built >= competent.machines_built + 2,
		"and a second Ammo Press with it: %d Machines against %d"
		% [pair.machines_built, competent.machines_built]
	)
	assert_true(
		pair.ammunition_in_the_factory >= competent.ammunition_in_the_factory * 3,
		(
			"the rounds pile up rather than being spent: %d left against %d"
			% [pair.ammunition_in_the_factory, competent.ammunition_in_the_factory]
		)
	)
	assert_true(
		pair.end_tick <= competent.end_tick,
		(
			"and the Run is no longer for it: %s against %s"
			% [pair.clock(), competent.clock()]
		)
	)


func test_a_wall_that_can_be_walked_round_is_never_bitten() -> void:
	# **What a Wall is worth, measured, and the answer is nothing a Wave ever touches.**
	# `_enemy_contact_target` chews a Wall in exactly one case — an Enemy in a pocket it cannot
	# route out of — so a funnel across the lane is a detour and not a defence, however much it
	# cost. Eleven tiles at two plate each, every one of them still standing at the end, and
	# **zero hit points absorbed between them.**
	#
	# That is the honest statement of where `wall.health` against `enemy.breaker_damage` stands:
	# it is unreachable by anything a player builds in the open. `sealed_breach` is the row that
	# reaches it.
	var report: BalanceProbe.Report = _play("walled_lane")
	assert_eq(report.walls_built, 11, "the funnel went up whole")
	assert_eq(report.walls_standing, 11, "and every tile of it was still there at the end")
	assert_eq(
		report.wall_hit_points_absorbed,
		0,
		"with nothing ever having bitten one: %s" % report.cause()
	)
	# And it bought about what a second Turret bought, which is to say nothing outside the phase
	# noise this file already tolerates.
	var competent: BalanceProbe.Report = _play("competent")
	assert_true(
		absi(report.end_tick - competent.end_tick)
		<= SAME_LENGTH_SECONDS * Simulation.TICKS_PER_SECOND,
		"and the same Run: %s against %s" % [report.clock(), competent.clock()]
	)


func test_sealing_the_breach_is_what_gets_a_wall_bitten() -> void:
	# The other half, and the only arrangement on this Map that puts a Wall in front of a tooth:
	# four tiles box the one Breach in, Enemies emerge into a pocket they cannot route out of,
	# and `_enemy_contact_target`'s last clause chews them out of it.
	#
	# So `wall.health` is measured rather than argued about — and it is measured as a Wall being
	# chewed through and not rebuilt, which is what one pull of the lever buys.
	var report: BalanceProbe.Report = _play("sealed_breach")
	assert_true(report.walls_built >= 4, "the seal went up: %d Walls" % report.walls_built)
	assert_true(
		report.wall_hit_points_absorbed > 0,
		"and was bitten, which is what a pocket does: %d hit points" % report.wall_hit_points_absorbed
	)
	assert_true(
		report.walls_standing < report.walls_built,
		(
			"chewing all the way through some of it: %d of %d left"
			% [report.walls_standing, report.walls_built]
		)
	)


func test_branching_one_smelter_is_dearer_than_building_a_second_one() -> void:
	# **The Run #46 made possible and none of the nine built**, and the arithmetic that said it
	# would pay left out the geography. Feeding the Silo's plate off a branch of the first
	# Smelter saves a Miner and a Smelter — 20 plate, 300 kW and two Machines' worth of Heat —
	# and costs thirty-five tiles of Belt to carry that plate round the Factory and the Nest to
	# where the Silo stands, which is 35 plate. So branching is dearer in the only currency a
	# Run has, and it is thirty-five tiles of buffer in front of the Ammo Press as well.
	#
	# It still works: a Silo stands, assembles Charges and fires. What it does not do is pay.
	var branched: BalanceProbe.Report = _play("branched_artillery")
	var ore_line: BalanceProbe.Report = _play("artillery")
	assert_eq(branched.silos_standing, 1, "a Silo stood up on a branch of the one Smelter")
	assert_eq(branched.stratagems_fired, 1, "and fired: %s" % branched.cause())
	assert_true(
		branched.end_tick < ore_line.end_tick,
		(
			"and the Run was shorter for it than the second ore line's: %s against %s"
			% [branched.clock(), ore_line.clock()]
		)
	)


func test_no_run_in_this_table_ever_unlocks_the_artillery_barrage() -> void:
	# **The premise #60 set out to measure, contradicted by the Delivery chain's own bill.**
	# `artillery_barrage` sits behind `t03_deep_survey`, which wants 400 plate and 200 coal at
	# Depth 2 — about twenty-one minutes of one Smelter's entire output — and the only Run that
	# reaches Depth 2 at all lasts thirteen minutes. So a Barrage's 150 points over six tiles and
	# `silo.paint_seconds` at five seconds are not unmeasured because nobody wrote the scenario;
	# they are unmeasured because no Factory in Milestone 1 can buy the row.
	#
	# `deep_silo` is that scenario, and it is worth having: it reaches Depth 2, stands a Silo up
	# out of what the lever has left, and assembles a Charge. What it cannot do is get there in
	# time, because the plate for a Silo and the plate for the chain are the same plate.
	var report: BalanceProbe.Report = _play("deep_silo")
	assert_eq(report.depth_reached, 2, "the Run really did dig the Depth 2 seam")
	assert_eq(report.silos_standing, 1, "and stood a Silo up as well")
	assert_true(
		report.most_charges_banked > 0,
		"which assembled a Charge out of Belt-fed plate and rounds"
	)
	assert_false(
		report.stratagems_unlocked.has("artillery_barrage"),
		(
			"and never unlocked the Barrage: %s"
			% [", ".join(report.stratagems_unlocked) if report.stratagems_unlocked.size() > 0
				else "no Delivery unlocked a Stratagem at all"]
		)
	)


func test_a_long_belt_to_the_nest_is_a_buffer_and_no_longer_a_tax() -> void:
	# **Finding 9's cheap half, re-measured on #46's fair share, and the sign has flipped.**
	# A forty-tile coal haul to the Nest holds 160 coal before back-pressure reaches the Miner,
	# so a line nobody tears down goes on diverting the Boiler's fuel. Measured *before* #46 —
	# when that line took **all** the Miner's coal rather than half of it — leaving it standing
	# cost the Run more than four minutes: 6m20s with 98% of itself browned out, against 10m48s
	# with the demolish in.
	#
	# On a fair share, leaving it standing makes the Run **longer**. Half the coal is enough to
	# keep the Boiler relighting, and what the haul buys instead is a Factory that stays cooler
	# — every lump on that Belt is a lump not being burned into crafts, so the Heat curve is
	# flatter and the Waves come slower. The trap is a buffer now, not a tax.
	#
	# Asserted as the direction rather than the margin, because the margin is a tuning change
	# away from moving and the direction is the finding.
	var torn_down: BalanceProbe.Report = _play("deep_digger")
	var left_standing: BalanceProbe.Report = _play("coal_haul")
	if not assert_true(torn_down.nest_fell and left_standing.nest_fell, "both Runs end"):
		return
	assert_eq(left_standing.breach_count, 2, "both Runs dug deep enough to open a second Breach")
	assert_true(
		left_standing.most_heat_at_once < torn_down.most_heat_at_once,
		(
			"the haul holds coal the Boiler would have burned into crafts: peak Heat %d against %d"
			% [left_standing.most_heat_at_once, torn_down.most_heat_at_once]
		)
	)
	assert_true(
		left_standing.end_tick > torn_down.end_tick,
		(
			"so leaving it standing is no longer the trap it was: %s against %s"
			% [left_standing.clock(), torn_down.clock()]
		)
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


func test_a_stratagem_fired_from_a_factory_that_built_it_replays_identically() -> void:
	# **#37's replay fixture.** Everything a Stratagem touches is either irreversible or arrives
	# from outside the Map — Charges leave the Silo on the tick the channel begins, a Sentry is
	# placed with no Build Gun and a pre-filled buffer, and an expiry tick removes it again — so
	# "it replays" is a stronger claim here than anywhere else in the project.
	#
	# The whole Run up to a few seconds past the firing, because the claim is about the Factory
	# that built the Silo and not only about the Painting: twelve Belts, four Machines bought with
	# lever plate, a walk, a dial, an irreversible load and a held key, all as Input Actions.
	# Costs the suite a couple of minutes on its own, which is the honest price of replaying a
	# Factory rather than a fixture: the harness compares every one of the 41,000 ticks.
	var script: InputScript = BalanceScenarios.artillery().to_script(
		680 * Simulation.TICKS_PER_SECOND
	)
	var recording: ReplayRecording = DeterminismHarness.record(script, 7, 1)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())

	# And a fixture that fired nothing would replay perfectly and prove nothing, which is the
	# honesty check every determinism test in this project carries beside it.
	var report: BalanceProbe.Report = _play("artillery")
	assert_eq(report.stratagems_fired, 1, "the fixture really did call one in")


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


# ── #62: whether a player can arm themselves out of their own Factory ────────

func test_a_melee_run_is_never_dry_because_a_wrench_spends_nothing() -> void:
	# **The figure #62 needed and the reason it has to be conditional.** The probe's existing
	# dryness verdict is about the *Factory* — `query_item_total` walks Machines and Belts and
	# has never heard of the Nest's store or of a player's pockets — so it says nothing at all
	# about whether the person holding the gun had anything to fire. #62's question is the
	# other one, and it is a different fact: a Run can hold 400 rounds at the counter while the
	# player stands next to it empty.
	#
	# So the player's dryness is measured only over the ticks a **ranged** weapon was in hand.
	# A Pneumatic Wrench spends nothing (`gear.csv` leaves its `ammunition_item` empty), so a
	# player holding one is not dry, they are not in the market — and a figure that counted
	# those ticks would report every row in this table as 100% dry, including the twelve that
	# never equip a rifle at all. `bare` is the cheapest proof of that: three minutes, a
	# wrench, no Factory and nothing to withdraw.
	var report: BalanceProbe.Report = _play("bare")
	assert_eq(report.player_armed_ticks, 0, "a wrench is never in the market for a round")
	assert_eq(report.player_dry_ticks, 0, "so no tick of it counts as dry")
	assert_eq(report.player_dry_percent(), 0, "and the share is zero rather than undefined")
	assert_eq(report.player_shots_fired, 0, "and nothing ranged was ever fired")


func test_a_player_can_arm_himself_out_of_the_nests_store_across_a_whole_run() -> void:
	# **#62's first acceptance criterion, and it is a claim about the instrument before it is a
	# claim about the balance.** `player.starting_stock` is plate alone, deliberately — putting
	# rounds in the opening bill would conjure exactly the thing the Factory is supposed to make
	# — so a Run opens with a rifle that is a stick, and the only way it ever fires is the Nest's
	# store. `test_gear` proves that path works once. What had never been measured is whether it
	# *keeps up*, over a Run, against the Turret drinking from the same Press.
	#
	# This row is the measurement. It is deliberately not `rifle_picket`: that one leans on the
	# trigger for thirty seconds of every minute whether or not a Wave is on the Map, which is a
	# measurement of its own impatience, and its end-to-end margin has moved five times across
	# five tickets without anything about Ammunition changing. This one withdraws once a cycle
	# and spends a burst, and what is asserted is the chain rather than the clock.
	var report: BalanceProbe.Report = _play("armed_player")
	assert_true(report.nest_fell, "the Run ends: %s" % report.cause())
	assert_true(
		report.rounds_that_reached_the_player > 0,
		"rounds really did come out of the store and into his pockets"
	)
	assert_true(report.player_shots_fired > 0, "and he really did fire them")
	assert_true(
		report.player_armed_ticks > report.end_tick / 2,
		"with a gun in hand for most of the Run, not a moment of it"
	)
	# The figure the ticket asks for, reported rather than asserted at a value: what it *is* is
	# a measurement and belongs in CLAUDE.md, and a test that pinned it would turn every
	# legitimate tuning change into a red suite.
	assert_true(
		report.cause().contains("dry for"),
		"and the printed row says how long he spent with nothing to fire: %s" % report.cause()
	)


## How dry a player has to be before the magazine, rather than their aim, is what is wrong.
##
## A quarter of the ticks they were holding the gun. Measured, burst discipline comes out at 9%
## — the gaps between a withdrawal landing and the next burst — and leaning on the trigger comes
## out at 74%, so the band sits well clear of both and a change that moved either across it is a
## change to the Ammunition economy rather than phase noise.
const DRY_ENOUGH_TO_BE_THE_PROBLEM_PERCENT: int = 25


func test_one_ammo_press_serves_a_turret_and_a_player_only_at_burst_discipline() -> void:
	# **#62's second acceptance criterion, and the answer is "yes, at a discipline".**
	#
	# The two armed rows receive **the same income** and differ enormously in whether they can
	# fight out of it, which is the whole finding. The Nest's line is a 50/50 branch off the one
	# Ammo Press (#46), so it delivers about nineteen rounds a minute whatever the player does —
	# measured, 452 rounds over 1434 s of gun-in-hand for the burst rifleman and 520 over 1618 s
	# for the picket, which is 18.9 and 19.3 a minute. **The faucet sets a player's income and
	# their trigger discipline sets their dryness**, and those are different facts.
	#
	# So a Bolt Rifle leaning on the trigger demands 75 rounds a minute, gets 19, and is dry for
	# **74%** of the Run; one spending eight seconds in forty demands about 15, gets the same 19,
	# and is dry for **9%**. One Press really does arm a Turret and a player — and only because
	# the player is firing at a Wave rather than at the horizon.
	#
	# **This also corrects what `rifle_picket`'s own note claims.** That row says it spends
	# rounds at 75 a minute against a Press that makes 37; it cannot, and never did. It spends
	# 19 and holds an empty gun for three-quarters of the Run, so its 30-second bursts are mostly
	# dry trigger pulls. That is the mechanical reason its end-to-end margin has moved five times
	# across five tickets without anything about Ammunition changing: the demand the row was
	# built to measure never happened.
	var burst: BalanceProbe.Report = _play("armed_player")
	var picket: BalanceProbe.Report = _play("rifle_picket")
	if not assert_true(burst.nest_fell and picket.nest_fell, "both Runs end"):
		return
	assert_true(
		burst.player_dry_percent() < DRY_ENOUGH_TO_BE_THE_PROBLEM_PERCENT,
		(
			"a player who fires at Waves is armed when one arrives: dry %d%% of %ds"
			% [burst.player_dry_percent(), burst.player_armed_seconds()]
		)
	)
	assert_true(
		picket.player_dry_percent() >= DRY_ENOUGH_TO_BE_THE_PROBLEM_PERCENT,
		(
			"and one who leans on the trigger is holding an empty gun: dry %d%% of %ds"
			% [picket.player_dry_percent(), picket.player_armed_seconds()]
		)
	)
	# The income is the same to within a fifth, which is what makes the dryness a fact about the
	# discipline rather than about the Factory. Compared as rounds per minute of gun-in-hand,
	# because the two Runs are not the same length.
	var burst_rate: int = burst.rounds_that_reached_the_player * 60 / maxi(
		burst.player_armed_seconds(), 1
	)
	var picket_rate: int = picket.rounds_that_reached_the_player * 60 / maxi(
		picket.player_armed_seconds(), 1
	)
	assert_true(
		absi(burst_rate - picket_rate) * 5 <= maxi(burst_rate, picket_rate),
		(
			"one Press's Nest line pays both of them about the same: %d against %d rounds a minute"
			% [burst_rate, picket_rate]
		)
	)
	# And what it costs the Turret is real rather than rhetorical: the player's share comes out
	# of the same branch, so the gun that holds the lane spends longer empty and fires less.
	var competent: BalanceProbe.Report = _play("competent")
	assert_true(
		burst.dry_turret_ticks > competent.dry_turret_ticks,
		(
			"the Turret pays for the magazine: %d Turret-ticks empty against %d"
			% [burst.dry_turret_ticks, competent.dry_turret_ticks]
		)
	)
	assert_true(
		burst.end_tick < competent.end_tick,
		"and the Run is shorter for it: %s against %s" % [burst.clock(), competent.clock()]
	)


func test_a_second_ammo_press_off_one_smelter_starves_the_lane_turret_and_the_player_at_once() -> void:
	# **#60's finding 1, sharpened into something worse than neutral.** #60 measured a second
	# Ammo Press and a second Turret as a *mistake* — 16% shorter than `competent`, ending with
	# 416 rounds nobody could spend — because a Turret's output is bounded by how long an Enemy
	# spends inside its 16 m rather than by its feed. What that left open is the player's side: a
	# player is not range-bound, so rounds a Turret cannot spend are rounds a player could.
	#
	# Measured, they are not, and the reason is upstream of both guns. The second Press is fed by
	# a second Belt off the **one Smelter**, which since #46 is a 50/50 share — so it halves the
	# first Press, and the first Press is the only one whose rounds reach *either* the lane
	# Turret or the Nest's counter. So one build halves the feed of the gun holding the lane and
	# halves the player's income at the same time, and banks the surplus behind a second gun that
	# the Breaker tier never even arrives to give targets to.
	#
	# The figures: **14m43s against `armed_player`'s 24m14s** — 39% shorter, and the shortest
	# defended Run in the table — with the player **dry for 83%** of the time, 137 rounds
	# reaching him against 452, and the Factory finishing on **240 rounds** with all eight
	# Machines standing and nothing lost. A Factory in perfect health that cannot shoot.
	#
	# Asserted as bands: the pair is not longer, the player is starved rather than supplied, and
	# the rounds pile up instead. A later change that made a second Press genuinely arm a player
	# would fail here, which is the point of writing it down.
	var one: BalanceProbe.Report = _play("armed_player")
	var two: BalanceProbe.Report = _play("armed_second_press")
	if not assert_true(one.nest_fell and two.nest_fell, "both Runs end"):
		return
	assert_eq(two.turrets_built, 2, "a second Turret stood")
	assert_true(
		two.machines_built >= one.machines_built + 2,
		"and a second Ammo Press with it: %d Machines against %d"
		% [two.machines_built, one.machines_built]
	)
	assert_true(
		two.player_dry_percent() > one.player_dry_percent() * 2,
		(
			"the player is far worse armed for it: dry %d%% against %d%%"
			% [two.player_dry_percent(), one.player_dry_percent()]
		)
	)
	assert_true(
		two.rounds_that_reached_the_player < one.rounds_that_reached_the_player,
		(
			"because fewer rounds ever reach the counter: %d against %d"
			% [two.rounds_that_reached_the_player, one.rounds_that_reached_the_player]
		)
	)
	assert_true(
		two.ammunition_in_the_factory > one.ammunition_in_the_factory,
		(
			"while the Factory finishes holding more of them: %d against %d"
			% [two.ammunition_in_the_factory, one.ammunition_in_the_factory]
		)
	)
	assert_true(
		two.end_tick < one.end_tick,
		"and the Run is shorter: %s against %s" % [two.clock(), one.clock()]
	)
