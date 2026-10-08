## The sessions #26 measures the game against, on the Map the game ships.
##
## Each one is a player with a plan, expressed as Input Actions and nothing else. They are
## here rather than inside a test case because they are the *fixtures of record*: the suite
## asserts against them and `tools/balance/measure.sh` prints them, so the figures in
## CLAUDE.md and the figures a test guards are the same Runs.
##
## Three rules they all obey:
##
## 1. **The shipped Map and the shipped content.** `MapLayout.starter()`, `content/` off
##    disk, `player.starting_stock` as written. A scenario that gave itself plate would be
##    measuring a game nobody can play.
## 2. **Nothing but Input Actions.** No pokes at Simulation state, no injected Definitions.
##    Every one of these is a session that could have been recorded from a keyboard.
## 3. **One Factory, grown.** Every scenario past `bare` contains `competent`'s six Machines
##    on the same tiles, so the difference between two rows is the difference between two
##    decisions and never between two Factories.
class_name BalanceScenarios
extends RefCounted

const GROUND: int = WorldGrid.GROUND_LAYER

## Where the first Turret stands: on the lane between the one Breach at (16, -6) and the
## Nest at (-6, -6), close enough that its 8-tile reach covers the approach. The same tile
## `test_turrets.gd` uses, so the measurement and the behavioural test describe one Factory.
const TURRET_TILE: Vector3i = Vector3i(2, GROUND, -7)

## The tile the first Ammunition Belt ends on, one west of the Turret's footprint.
const LAST_BELT_TILE: Vector3i = Vector3i(1, GROUND, -6)

## Where the Factory's own Turret stands, in `fortified`: wedged between the Smelter and the
## coal Miner, where its 8-tile reach covers **every** Machine of the opening line — the
## Miner at 14.6 m, the Smelter at 5.8 m, the Ammo Press at 8.5 m, the coal Miner at 4.5 m
## and the Boiler at 11.7 m, all inside 16 m.
##
## That is the whole of what `fortified` adds, and it is the answer to the thing `competent`
## has none: a Breaker steers by the **Factory** flowfield rather than by the Nest, so it
## never walks into a Turret that is guarding the Nest's lane. A Turret on the lane cannot
## defend the Factory, however much Ammunition it has.
const FACTORY_TURRET_TILE: Vector3i = Vector3i(11, GROUND, 6)

## The spare iron Node, out to the north-west of the opening line. The second thing a
## Factory grows onto, and in `over_producer` the thing it grows onto without a plan.
const SPARE_IRON_NODE: Vector3i = Vector3i(-6, GROUND, 10)

## The Depth 2 seam. A Miner Mk2 standing here is what `depth.breach_tier` is about: after
## `depth.breach_crafts` deep crafts it opens a second Breach in the middle of the ground
## the opening Factory is standing on.
const DEEP_IRON_NODE: Vector3i = Vector3i(22, GROUND, 10)

## The eastern Hive. Geography, from `MapLayout.starter()`; named here because a sortie is
## a walk to a place and the place is the whole of the plan.
const EASTERN_HIVE: Vector3i = Vector3i(38, GROUND, 24)

## Where a sortie turns, out past the east end of the Factory and south of all of it.
##
## **The straight line from the Nest to the eastern Hive goes through the Smelter**, which
## was free when a player could walk through a Machine and is not free now that #30 made the
## Factory solid. What collision does to an open-loop walk is not a stop — the player slides
## along the housing and comes out of it pointing somewhere else — so the measured cost was
## two seconds of detour and a sortie that halted twelve metres short of the Hive and swung
## at nothing. A player who could see the Smelter would have gone round it, so the scenario
## does: east along the Nest's own latitude until the Factory is behind it, then north-east
## to the Hive. Both legs are clear ground, which is what keeps `_sprint_ticks_for`'s
## arithmetic honest.
const SORTIE_WAYPOINT: Vector3i = Vector3i(24, GROUND, 0)

## Where the second Steam Boiler stands, in `artillery`: south of the coal Miner at (12, 4),
## reached by two Belts out of the Miner's own southern face.
##
## **The second Boiler is the whole of #37's Power answer.** One coal Node yields 40 coal a
## minute against a Boiler's 30, which #26 read as "there is no second Boiler to be had" — but
## a Boiler is only on the grid *while it is burning* (`_machine_would_work`), so 40 coal a
## minute is 1.33 Boilers burning rather than one Boiler burning and 10 coal a minute piling up
## on a Belt. Two Boilers on one Node supply about 800 kW averaged over time instead of 600, and
## 300 + 800 is what pays for a Silo beside the opening line.
const SECOND_BOILER_TILE: Vector3i = Vector3i(16, GROUND, 8)

## The second ore line, out on the spare iron Node at (-6, 10) — the Node `over_producer` digs
## into and collects nothing from, used here for what it is for.
##
## **The Silo needs its own plate and the opening line has none to spare.** The Smelter makes
## 18.75 plate a minute and the Ammo Press wants 20, so the Press can use every plate the Smelter
## produces. Before #46 a second Belt off that Smelter never got one at all, because the Press's
## was served first every tick; since #46 it would get half, and halving the Press is not a trade
## this row wants. **The second ore line is therefore still the right build and no longer the
## only one** — a judgement rather than a measurement, because what has been measured is this Run
## and not the branched alternative. See CLAUDE.md, "What is still unmeasured". A Silo's Recipe is a plate and twenty rounds, so the
## plate has to come from somewhere, and a second Miner and Smelter is what a player would
## build. They cost 20 plate between them and almost nothing in Power — the Silo takes 3 plate a
## minute of the 18.75 they make, so both spend about a sixth of their time working and the rest
## idle and off the grid, which is back-pressure paying for itself.
const SECOND_MINER_TILE: Vector3i = Vector3i(-6, GROUND, 10)
const SECOND_SMELTER_TILE: Vector3i = Vector3i(-6, GROUND, 14)

## Where the Silo stands: in the clear ground south of the Nest, beside the second ore line that
## feeds it and a short Belt run from the Ammo Press's western face.
const SILO_TILE: Vector3i = Vector3i(-1, GROUND, 14)

## Where the walk to the Silo turns, and where a player stands to load it.
##
## The approach goes west of the long Ammunition Belt down x = 0 before turning south, because
## the straight line from where a Run starts walks the whole length of that Belt — and a Belt is
## solid, so an open-loop walk along one is a walk at deck height that comes off somewhere
## unplanned. The loading spot is one tile north of the Silo's wall, inside
## `silo.load_reach_metres` of 4 m.
const SILO_APPROACH: Vector3i = Vector3i(-3, GROUND, 8)
const SILO_LOADING_SPOT: Vector3i = Vector3i(0, GROUND, 13)

## Where the Sentry is wanted, and where the player walks to paint it: north-west of the Silo,
## where an 8-tile reach covers the Silo, the second Smelter and the second Miner at once. The
## western line is the half of this Factory no Turret on the Nest's lane can see, and it is where
## the Run keeps its artillery.
const PAINT_APPROACH: Vector3i = Vector3i(-3, GROUND, 12)

## The tile the walk to `PAINT_APPROACH` actually settles the player on, which is the tile the
## Painting is held over. **Measured, not assumed**: a painted tile is the one under a player's
## feet, and an open-loop walk stops where its arithmetic stops. If a later movement change moves
## it, this row reports no Stratagem fired rather than quietly passing.
const PAINT_TILE: Vector3i = Vector3i(-5, GROUND, 12)

## How many Charges one load commits, against `silo.max_charges_per_load` of 4. Two, so the
## Sentry arrives with 120 rounds — a Charge is a multiplier and this row spends two of them.
const CHARGES_PER_LOAD: int = 2

## When the player leaves the Factory for the Silo, and when they leave the Silo for the tile
## they want the Sentry on. Late enough that the Silo has been standing for minutes with
## Belt-fed plate and rounds to assemble Charges out of.
const LOAD_WALK_SECOND: int = 420
const PAINT_WALK_SECOND: int = 660

## How many of a Factory's own pixels of mouse travel make one whole turn, at the shipped
## `player.look_sensitivity_turns_per_1000_pixels`. Derived rather than written down, so a
## sensitivity change re-aims the sorties instead of silently sending them past the Hive.
const LOOK_PIXELS_PER_TURN: int = 1000 * 10 / 2

## How finely `_look_pixels_towards` searches for a heading: 4096 steps of a turn, which is
## about five arc-minutes. Over the longest leg of the sortie to the eastern Hive — 56 m, from
## `SORTIE_WAYPOINT` — that is under 9 cm of drift, well inside the Wrench's 4 m reach.
const HEADING_STEPS: int = 4096


## Every scenario, in report order: least built to most built, then the two sorties, then the
## Factory that builds artillery.
static func all() -> Array:
	return [
		bare(),
		opening_line(),
		competent(),
		over_producer(),
		fortified(),
		deep_digger(),
		hive_sortie(),
		rifle_picket(),
		artillery(),
	]


static func by_id(scenario_id: String) -> BalanceScenario:
	for scenario: BalanceScenario in all():
		if scenario.id == scenario_id:
			return scenario
	return null


## A player who builds nothing at all. The floor of the loop: the spec wants this Run over in
## a few minutes, and it is the control every other row is read against.
static func bare() -> BalanceScenario:
	return BalanceScenario.named(
		"bare", "builds nothing — the opening 80 plate never leaves their pockets"
	)


## A player who builds the production line and forgets the defence. Five Machines, no Turret.
##
## Worth its own row because it isolates Heat from defence: identical production to
## `competent`, nothing shooting. The gap between this row and `bare` is what producing
## costs you before anything it bought starts paying.
static func opening_line() -> BalanceScenario:
	var scenario: BalanceScenario = BalanceScenario.named(
		"opening_line", "builds the iron line and the Power but no Turret"
	)
	scenario.at(1, _iron_line() + _power_line())
	scenario.at(2, _iron_belts() + _power_belts())
	return scenario


## The documented competent Factory: a Miner, a Smelter, an Ammo Press, a coal Miner, a
## Steam Boiler and one MG Turret, joined by six Belts.
##
## **The direct successor to #10's figure**, built from the same Machines on the same tiles,
## so the before-and-after in CLAUDE.md compares two measurements of one Factory. The bill is
## 78 of the 80 plate a Run opens with, which is why this is *the* opening Factory rather
## than one of several.
static func competent() -> BalanceScenario:
	var scenario: BalanceScenario = BalanceScenario.named(
		"competent", "the six-Machine chain and one MG Turret, the whole opening stock"
	)
	scenario.at(1, _iron_line() + _power_line() + [_turret(TURRET_TILE)])
	scenario.at(2, _iron_belts() + _power_belts() + _first_ammunition_belts())
	return scenario


## The competent Factory plus a second Miner on the spare iron Node, feeding nothing.
##
## **The over-production mistake in its purest form.** A Machine's output buffer is uncapped,
## so the Miner digs forever into a pile nobody collects — 120 kW of draw and a Node's worth
## of Heat a minute, bought for no Ammunition at all.
##
## Paired with `fortified`: both pull the call-early lever once at a minute in and spend the
## 25 plate it pays, one on a Miner and one on a Turret. So the gap between those two rows is
## what the plate was spent on and nothing else, and the gap to `competent` is what spending
## it at all cost.
static func over_producer() -> BalanceScenario:
	var scenario: BalanceScenario = BalanceScenario.named(
		"over_producer", "spends the call-early plate on an unbelted Miner that only makes Heat"
	)
	scenario.at(1, _iron_line() + _power_line() + [_turret(TURRET_TILE)])
	scenario.at(2, _iron_belts() + _power_belts() + _first_ammunition_belts())
	scenario.at_second(60, [InputAction.call_wave_early(0)])
	scenario.at_second(61, [_machine("miner_mk1", SPARE_IRON_NODE)])
	return scenario


## The competent Factory, then a Turret over the Factory itself, bought with the call-early
## lever.
##
## **The competently defended Factory**, and the row the spec's 20-40 minutes is about. The
## lever is the only way a Run can turn breathing room into build material, so this is the
## Factory that grows: pull it a minute in, take the 25 plate, and put a second MG where it
## covers the five Machines the first one cannot see.
static func fortified() -> BalanceScenario:
	var scenario: BalanceScenario = BalanceScenario.named(
		"fortified", "the competent chain, then a Turret over the Factory itself"
	)
	scenario.at(1, _iron_line() + _power_line() + [_turret(TURRET_TILE)])
	scenario.at(2, _iron_belts() + _power_belts() + _first_ammunition_belts())
	scenario.at(3, _factory_turret_belts())
	scenario.at_second(60, [InputAction.call_wave_early(0)])
	scenario.at_second(61, [_turret(FACTORY_TURRET_TILE)])
	return scenario


## The competent Factory, plus everything needed to pay the Delivery chain and then dig.
##
## The greedy Run. `t01_munitions` wants 20 coal and `t02_deep_mining` wants 120 plate and 60
## Ammunition, so this Factory runs a coal Belt and a second Ammunition Belt into the Nest —
## which halves what reaches the Turret while they are open — and pulls the call-early lever
## once a minute for the plate, because the lever is the only plate a Run has. The reward is
## `miner_mk2` and the Depth 2 seam; the price is `depth.breach_crafts` later, when a second
## Breach opens at (16, 4), in the middle of the ground this Factory is standing on.
##
## Everything past the Belts is attempted **blind**, once a minute, from the first minute on. A
## scenario is a function from tick to Input Actions and cannot read the Simulation, so a lever
## pulled while a Wave is still arriving, a hand-over of something the open tier does not want
## and a Mk2 before the tier unlocks are all silent refusals whose hash does not move. That is
## the same discipline a recorded session has, and it is why the report says which Depth was
## actually reached rather than assuming it.
static func deep_digger() -> BalanceScenario:
	var scenario: BalanceScenario = BalanceScenario.named(
		"deep_digger", "pays the Delivery chain off the Factory's output, then digs Depth 2"
	)
	scenario.at(1, _iron_line() + _power_line() + [_turret(TURRET_TILE)])
	scenario.at(2, _iron_belts() + _power_belts() + _first_ammunition_belts())
	scenario.at(3, _coal_belts_to_the_nest() + _ammunition_belts_to_the_nest())
	# The player walks to the Nest's counter and stays there: handing goods over and taking
	# them back out both happen at that one counter. They will be bitten standing there, and
	# the report counts it.
	_walk_to(scenario, 10 * Simulation.TICKS_PER_SECOND, Vector3i(-3, GROUND, -3), 0)
	# And the coal line comes back up at three minutes, which is still the decision this row
	# models even though #37 took the Nest's store out of the reason.
	#
	# **What is left is the Belt itself.** The store used to take 200 coal past the tier's bill
	# and now takes none, because coal is not an Item a player can spend again
	# (`Definitions.item_can_be_spent`) — but this line is forty tiles long, so it holds 160 coal
	# of its own before back-pressure ever reaches the Miner, and since #46 it takes **half** the
	# Miner's coal while it is filling rather than all of it. Measured with the demolish removed
	# and before #46, this Run lasted **6m20s with 98% of it in Power deficit** — against 10m48s
	# with it. That pair has not been re-measured on a fair share, and the share is exactly what
	# #46 changed, so read it as the shape of the trap rather than its current size. So the diversion a long Belt can hide inside itself is bigger than the one the Nest
	# was hiding, and tearing the line down once the tier is paid is still a decision a player has
	# to make. See "Findings that are not tuning" in CLAUDE.md.
	scenario.at_second(180, _demolish_all(_coal_belts_to_the_nest_tiles()))
	# Then, once a minute: pull the lever, hand over whatever the open tier wants, take plate
	# back out, and try to put a Mk2 on the seam. **The lever is the only plate a Run has** —
	# `wave.call_early_bounty_per_item` is 25 of each starting Item — so paying 120 plate for
	# `t02_deep_mining` means five pulls, and five Waves arriving sooner than they would have.
	# That is the price of digging, charged in the only currency the game has.
	#
	# Every one of these is attempted blind. A scenario is a function from tick to Input
	# Actions and cannot read the Simulation, so a pull while a Wave is still arriving, a
	# hand-over of something the tier does not want and a Mk2 before the tier unlocks are all
	# silent refusals whose hash does not move. That is the same discipline a recorded session
	# has, and it is why the report says which Depth was actually reached.
	var plate: int = _definitions().item_index("iron_plate")
	for minute: int in range(1, 55):
		scenario.at_second(minute * 60, [InputAction.call_wave_early(0)])
		scenario.at_second(minute * 60 + 1, [InputAction.deliver_to_nest(0)])
		scenario.at_second(minute * 60 + 2, [InputAction.withdraw_from_nest(0, plate, 40)])
		scenario.at_second(minute * 60 + 3, [_machine("miner_mk2", DEEP_IRON_NODE)])
	return scenario


## The competent Factory, then a sortie: the player sprints out to the eastern Hive and takes
## it apart with the Pneumatic Wrench.
##
## Each standing Hive takes `hive.heat_shadow_per_minute` off what the Nest can shed, so the
## shipped Map starts every Run decaying at 280 a minute rather than 340. This row is what
## buying 30 of that back is worth, against two minutes of a player not being in the Factory.
##
## The Wrench is melee, so this sortie reaches no randomness: `Simulation._scatter` is only
## consulted by a *ranged* shot. `rifle_picket` is the row the seed can reach.
static func hive_sortie() -> BalanceScenario:
	var scenario: BalanceScenario = BalanceScenario.named(
		"hive_sortie", "the competent chain, then a wrench sortie against the eastern Hive"
	)
	scenario.at(1, _iron_line() + _power_line() + [_turret(TURRET_TILE)])
	scenario.at(2, _iron_belts() + _power_belts() + _first_ammunition_belts())
	# The weapon comes out before the walk: the holster takes 0.2 s and a player who arrives
	# still holding the Build Gun wastes a swing.
	scenario.at_second(120, [InputAction.set_build_mode(0, false)])
	# Two legs out, round the east end of the Factory rather than through the Smelter. See
	# `SORTIE_WAYPOINT`: a walk that clips a solid housing arrives late and aimed wrong.
	var home: Vector3i = Vector3i(0, GROUND, 0)
	var turn: int = _walk_to(scenario, 121 * Simulation.TICKS_PER_SECOND, SORTIE_WAYPOINT, 0)
	var out: int = _walk_to(
		scenario,
		turn,
		EASTERN_HIVE,
		3,
		SORTIE_WAYPOINT,
		heading_towards(home, SORTIE_WAYPOINT)
	)
	# 1200 hit points at 55 a swing is 22 swings, and the Wrench swings every 0.6 s — so
	# fifteen seconds of leaning on the trigger, with another fifteen of margin for where the
	# open-loop walk actually stopped. Held every tick, because that is what leaning on a
	# trigger is; the cooldown is the Simulation's business.
	scenario.hold(out, 30 * Simulation.TICKS_PER_SECOND, [InputAction.fire(0)])
	# And back to the Factory the way he came, so the rest of the Run is played by a player
	# who is standing in it rather than one stranded on the far side of the Map — or one who
	# walked home into the side of his own Smelter.
	var back: int = _walk_to(
		scenario,
		out + 31 * Simulation.TICKS_PER_SECOND,
		SORTIE_WAYPOINT,
		0,
		EASTERN_HIVE,
		heading_towards(SORTIE_WAYPOINT, EASTERN_HIVE)
	)
	_walk_to(
		scenario, back, home, 0, SORTIE_WAYPOINT, heading_towards(EASTERN_HIVE, SORTIE_WAYPOINT)
	)
	return scenario


## The competent Factory, plus a player standing at the Nest with the Bolt Rifle.
##
## **The only scenario the world seed can reach.** `Simulation._scatter` is the one consumer
## of the seeded RNG in the whole Simulation, and it is only reached by a *ranged* shot — so
## this is the only row in the table whose numbers can differ between seeds. Every other
## scenario is bit-identical across every seed, because the Map is handcrafted and the Wave
## schedule is a function of Heat. That is worth proving rather than asserting, which is what
## this row is for.
##
## It is also #17's fourth claimant, measured: the rifle spends the same Ammunition the Turret
## does, out of the Nest's store, at 75 rounds a minute against the Press's 37. A player who
## leans on the trigger is competing with his own Turret.
static func rifle_picket() -> BalanceScenario:
	var scenario: BalanceScenario = BalanceScenario.named(
		"rifle_picket", "the competent chain, plus a rifleman at the Nest spending the same rounds"
	)
	scenario.at(1, _iron_line() + _power_line() + [_turret(TURRET_TILE)])
	scenario.at(2, _iron_belts() + _power_belts() + _first_ammunition_belts())
	scenario.at(3, _ammunition_belts_to_the_nest())
	_walk_to(scenario, 10 * Simulation.TICKS_PER_SECOND, Vector3i(-3, GROUND, -3), 0)
	# Rifle out, pointed down the lane the Breach feeds.
	scenario.at_second(20, [
		InputAction.set_build_mode(0, false),
		InputAction.equip_weapon(0, _definitions().gear_index("bolt_rifle")),
		InputAction.look(
			0,
			_look_pixels_between(
				heading_towards(Vector3i(0, GROUND, 0), Vector3i(-3, GROUND, -3)),
				heading_towards(Vector3i(-3, GROUND, -3), Vector3i(16, GROUND, -6))
			),
			0
		),
	])
	# Then, each minute: draw a magazine out of the store and spend half the minute on the
	# trigger. Thirty seconds on and thirty off, because a scenario cannot see a Wave coming
	# and a player who fires at nothing for a whole Run is measuring his own impatience.
	var ammunition: int = _definitions().item_index("ammunition")
	for minute: int in range(1, 60):
		scenario.at_second(minute * 60, [InputAction.withdraw_from_nest(0, ammunition, 60)])
		scenario.hold_seconds(minute * 60 + 1, 30, [InputAction.fire(0)])
	return scenario


## The competent Factory, then a second Boiler, a second ore line and a Silo — loaded by hand
## and fired.
##
## **#37's acceptance criterion, as a Run**: a competently built Factory can power, load and fire
## a Silo within a Run, demonstrated rather than asserted. #26 could not ask the question, and
## recorded why as a finding: the opening Factory draws 660 kW of the 900 one Boiler and the
## Nest's baseline plant supply, and a Silo asks for 400 more.
##
## Three things a player has to build, and none of them is a new mechanic:
##
## 1. **A second Steam Boiler on the same coal Node.** See `SECOND_BOILER_TILE`: a Boiler is on
##    the grid only while it burns, so one Node's 40 coal a minute is worth about 800 kW across
##    two Boilers rather than 600 across one.
## 2. **A second Miner and Smelter on the spare iron Node.** See `SECOND_MINER_TILE`: the Press
##    already takes every plate the first Smelter makes, so the Silo's plate has to be made
##    rather than diverted.
## 3. **Sixty plate for the Silo**, and ninety-six in total, out of a Run whose only source of
##    plate is the call-early lever at 25 a pull. Six pulls, so six Waves arrive sooner than they
##    would have — which is what makes artillery a thing this Run *paid* for.
##
## What it fires is a **Sentry Drop**, because that is the one Stratagem the shipped Delivery
## chain does not lock: `supply_drop` sits behind `t02_deep_mining` and `artillery_barrage` behind
## `t03_deep_survey`, so a Run that has paid for neither has exactly one thing to put in the tube.
## Which is worth knowing on its own — the Stratagem a Factory can reach first is the one that
## hands it a second Turret.
static func artillery() -> BalanceScenario:
	var scenario: BalanceScenario = BalanceScenario.named(
		"artillery", "grows a second Boiler and ore line, then loads and fires a Silo"
	)
	scenario.at(1, _iron_line() + _power_line() + [_turret(TURRET_TILE)])
	scenario.at(2, _iron_belts() + _power_belts() + _first_ammunition_belts())

	# **The lever is the only plate a Run has** — `wave.call_early_bounty_per_item` is 25 — so
	# ninety-six plate is seven pulls against the lever's own refusals, and seven Waves arriving
	# sooner than they would have. Pulled
	# blind once a minute, like `deep_digger`: a pull while a Wave is still arriving is a silent
	# refusal whose hash does not move, so what a scenario can do is keep asking.
	#
	# The builds are attempted blind too, cheapest first, once a minute from the first minute on.
	# A build nobody can afford is `MISSING_MATERIALS` and a build on a tile already taken is
	# `OCCUPIED`, so repeating the whole list every minute is how an open-loop script says "as
	# soon as the plate is there". The Belts go in with them, because a Belt whose far end has no
	# Machine yet simply backs up.
	for minute: int in range(1, 11):
		if minute <= 7:
			scenario.at_second(minute * 60, [InputAction.call_wave_early(0)])
		scenario.at_second(minute * 60 + 1, [_machine("steam_boiler_mk1", SECOND_BOILER_TILE)])
		scenario.at_second(minute * 60 + 2, [_machine("miner_mk1", SECOND_MINER_TILE)])
		scenario.at_second(minute * 60 + 3, [_machine("smelter_mk1", SECOND_SMELTER_TILE)])
		scenario.at_second(minute * 60 + 4, [_machine("silo_mk1", SILO_TILE)])
		scenario.at_second(minute * 60 + 5, _second_boiler_belts())
		scenario.at_second(minute * 60 + 6, _second_ore_belts())
		scenario.at_second(minute * 60 + 7, _silo_ammunition_belts())

	# Then the walk out to the Silo. Two legs, both on clear ground: west and south to
	# `SILO_APPROACH`, clear of the long Ammunition Belt down x = 0, then south-east to the
	# Silo's northern wall.
	var home: Vector3i = Vector3i(0, GROUND, 0)
	var turn: int = _walk_to(
		scenario, LOAD_WALK_SECOND * Simulation.TICKS_PER_SECOND, SILO_APPROACH, 0
	)
	_walk_to(
		scenario, turn, SILO_LOADING_SPOT, 0, SILO_APPROACH, heading_towards(home, SILO_APPROACH)
	)

	# Winding the dial and committing, blind, once every ten seconds. The dial commits nothing
	# and the load is irreversible, so a load attempted before the Silo has banked two Charges is
	# a silent refusal and a load attempted after the first one landed is `SILO_ALREADY_LOADED` —
	# which is exactly what makes repeating it safe.
	var sentry: int = _definitions().stratagem_index("sentry_drop")
	for attempt: int in range(1, 19):
		var second: int = LOAD_WALK_SECOND + 20 + attempt * 10
		scenario.at_second(second, [InputAction.set_silo_dial(0, sentry, CHARGES_PER_LOAD)])
		scenario.at_second(
			second + 1, [InputAction.load_silo(0, SILO_TILE, sentry, CHARGES_PER_LOAD)]
		)

	# And the Painting: a short walk back off the Silo's wall to the tile the Sentry is wanted on, five
	# seconds of standing still so the walk's deceleration has finished, and then the key held for
	# ten. A Sentry Drop channels three seconds and **any damage interrupts it**, so a Wave
	# arriving on top of the player is a Charge lost — which the report counts as
	# `charges_wasted` rather than hiding.
	var paint_walk: int = _walk_to(
		scenario,
		PAINT_WALK_SECOND * Simulation.TICKS_PER_SECOND,
		PAINT_APPROACH,
		0,
		SILO_LOADING_SPOT,
		heading_towards(SILO_APPROACH, SILO_LOADING_SPOT)
	)
	scenario.hold(
		paint_walk + 5 * Simulation.TICKS_PER_SECOND,
		10 * Simulation.TICKS_PER_SECOND,
		[InputAction.paint(0, PAINT_TILE)]
	)
	return scenario


# ── The Factory, in pieces ────────────────────────────────────────────────────

## Miner, Smelter and Ammo Press on the eastern iron.
static func _iron_line() -> Array:
	return [
		_machine("miner_mk1", Vector3i(4, GROUND, 4)),
		_machine("smelter_mk1", Vector3i(8, GROUND, 4)),
		_machine("ammo_press_mk1", Vector3i(8, GROUND, 9)),
	]


## The coal Miner and the Steam Boiler that pay for all of it.
static func _power_line() -> Array:
	return [
		_machine("coal_miner_mk1", Vector3i(12, GROUND, 4)),
		_machine("steam_boiler_mk1", Vector3i(16, GROUND, 4)),
	]


static func _iron_belts() -> Array:
	return [
		InputAction.build_belt(0, Vector3i(6, GROUND, 4), Vector3i(7, GROUND, 4)),
		InputAction.build_belt(0, Vector3i(8, GROUND, 7), Vector3i(8, GROUND, 8)),
	]


static func _power_belts() -> Array:
	return [InputAction.build_belt(0, Vector3i(14, GROUND, 4), Vector3i(15, GROUND, 4))]


## The long haul west and then north from the Ammo Press to the first Turret's lane. Three
## Belts because a Belt is a straight line; the corners are where one ends and the next
## begins.
static func _first_ammunition_belts() -> Array:
	return [
		InputAction.build_belt(0, Vector3i(7, GROUND, 9), Vector3i(1, GROUND, 9)),
		InputAction.build_belt(0, Vector3i(0, GROUND, 9), Vector3i(0, GROUND, -5)),
		InputAction.build_belt(0, Vector3i(0, GROUND, -6), LAST_BELT_TILE),
	]


## A second line off the same Ammo Press, east off its other face and down to the Factory's
## own Turret.
##
## **Two Belts off one Machine is a real splitter**, and it is not a special case:
## `_load_from_port` reads whatever Machine sits behind each Belt's *entry* tile, and a 2x3
## Press has room for two entries along its eastern wall. So one Press feeds two Turret lines,
## which is the arithmetic `fortified` is built to expose — a second Turret does not come with a
## second Press.
##
## **It is a priority rather than a half-share**, which is worth saying because it reads like a
## split: Belts are walked in canonical order and each takes one Item from the Machine behind its
## entry, so this line's (10, 9) is served after the first Turret's (7, 9) and receives only what
## that line has no room for. Between Waves the first line is sixty rounds of full Belt, so this
## one does get fed; a Machine whose first Belt never backs up would starve its second outright.
## See the splitter finding in CLAUDE.md.
static func _factory_turret_belts() -> Array:
	return [
		InputAction.build_belt(0, Vector3i(10, GROUND, 9), Vector3i(11, GROUND, 9)),
		InputAction.build_belt(0, Vector3i(12, GROUND, 9), Vector3i(12, GROUND, 8)),
	]


## Coal from the coal Miner's northern face, out around the north of the Factory and down to
## the Nest's eastern wall. This is what pays `t01_munitions`, which wants 20 coal.
##
## It takes coal the Boiler would otherwise have burned — this line's entry precedes the Boiler's
## in canonical Belt order, so it is served first — and Power sags for as long as it has anywhere
## to put coal. That sag is a real cost of progression and the report shows it.
##
## Forty tiles of Belt is 160 coal before back-pressure reaches the Miner at all, which is why
## this row demolishes the line rather than waiting for it to pack up. The Nest's own store used
## to add 200 more; since #37 it adds none.
static func _coal_belts_to_the_nest() -> Array:
	return [
		InputAction.build_belt(0, Vector3i(12, GROUND, 6), Vector3i(12, GROUND, 13)),
		InputAction.build_belt(0, Vector3i(12, GROUND, 14), Vector3i(-2, GROUND, 14)),
		InputAction.build_belt(0, Vector3i(-3, GROUND, 14), Vector3i(-3, GROUND, -2)),
	]


## One tile of each coal Belt, which is all a demolish needs: a Belt is removed whole by any
## tile of it.
static func _coal_belts_to_the_nest_tiles() -> Array:
	return [
		Vector3i(12, GROUND, 6),
		Vector3i(12, GROUND, 14),
		Vector3i(-3, GROUND, 14),
	]


## A demolish for each of a set of tiles. One Input Action per tile, because a demolish names
## a tile and a Belt is removed whole by any tile of it.
static func _demolish_all(tiles: Array) -> Array:
	var out: Array = []
	for tile: Vector3i in tiles:
		out.append(InputAction.demolish(0, tile))
	return out


## A second line off the Ammo Press's northern face, down the western corridor and into the
## Nest's eastern wall. This is the 60 Ammunition `t02_deep_mining` wants.
##
## It halves what reaches the Turret while it is open, and keeps halving it until the Nest's
## store fills to `nest.store_capacity_per_item` — at which point the Belt backs up and the
## Turret gets everything again. Paying for progression out of the Ammunition that was
## defending you is the whole of what this row costs.
##
## **"Halves" became literal with #46.** Before branching it was a priority: this Belt's entry at
## (7, 11) comes after the Turret's at (7, 9), so the Turret was fed first and this line got only
## the overflow. The row's cost is now the one its comment always claimed.
static func _ammunition_belts_to_the_nest() -> Array:
	return [
		InputAction.build_belt(0, Vector3i(7, GROUND, 11), Vector3i(0, GROUND, 11)),
		InputAction.build_belt(0, Vector3i(-1, GROUND, 11), Vector3i(-1, GROUND, -2)),
		InputAction.build_belt(0, Vector3i(-1, GROUND, -3), Vector3i(-2, GROUND, -3)),
	]


## Coal from the coal Miner's southern face, east and into the second Boiler at (16, 8).
##
## Since #46 the Coal Miner gives its two Belts equal turns, so 40 coal a minute against two
## appetites of 30 is **two Boilers each burning two thirds of the time** rather than one burning
## continuously and the other a third of the time. The grid cannot tell the difference — the
## average supply is 800 kW either way, which is what pays for the Silo — but the Factory reads
## very differently, because both Boilers now visibly cycle instead of one sitting idle.
static func _second_boiler_belts() -> Array:
	return [
		InputAction.build_belt(0, Vector3i(13, GROUND, 6), Vector3i(13, GROUND, 8)),
		InputAction.build_belt(0, Vector3i(13, GROUND, 9), Vector3i(15, GROUND, 9)),
	]


## The second ore line: ore from the Miner on the spare Node into the second Smelter, and that
## Smelter's plate into the Silo.
static func _second_ore_belts() -> Array:
	return [
		InputAction.build_belt(0, Vector3i(-6, GROUND, 12), Vector3i(-6, GROUND, 13)),
		InputAction.build_belt(0, Vector3i(-3, GROUND, 15), Vector3i(-2, GROUND, 15)),
	]


## Rounds off the Ammo Press's western face, west along z = 11 and south into the Silo.
##
## **A third claimant on one Press, and the one #17 asked about.** Since #46 the Press gives this
## line and the Turret's equal turns, so the Silo takes half of what the Press makes rather than
## the overflow off a sixty-round Belt. A Charge is twenty rounds, so the artillery and the
## magazine are spending the same output — which is exactly the tension the Silo was priced for,
## and which this row now pays at full price: see "What #46 cost the table" in CLAUDE.md for the
## 48 seconds it costs.
static func _silo_ammunition_belts() -> Array:
	return [
		InputAction.build_belt(0, Vector3i(7, GROUND, 11), Vector3i(3, GROUND, 11)),
		InputAction.build_belt(0, Vector3i(2, GROUND, 11), Vector3i(2, GROUND, 13)),
	]


static func _turret(tile: Vector3i) -> InputAction:
	return _machine("mg_turret_mk1", tile)


## A build action naming a Machine by id rather than by index, so a reordering of
## `machines.csv` cannot silently build something else.
static func _machine(machine_id: String, tile: Vector3i) -> InputAction:
	return InputAction.build_machine(0, _definitions().machine_index(machine_id), tile)


## The shipped content, read once per process. A scenario is built out of ids and needs the
## table only to turn them into the indices an Input Action carries.
static var _cached_definitions: Definitions = null


static func _definitions() -> Definitions:
	if _cached_definitions == null:
		_cached_definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	return _cached_definitions


# ── Walking somewhere, as Input Actions ──────────────────────────────────────

## Points a player at a tile and sprints them to it. Returns the tick they are expected to
## arrive on.
##
## **Open loop on purpose.** A scenario is a function from tick to Input Actions, so it
## cannot consult where the player got to — the same constraint a recorded session has. If
## the arithmetic here is wrong the player misses, and the measurement says so by reporting a
## Hive that is still standing.
##
## The throttle is sent on **every** tick of the walk, because `_walk` consumes it: standing
## still is the absence of an intent rather than an intent of its own, so a `move` that
## arrived once would buy exactly one tick of gait. The look and the sprint are held state and
## are sent once.
##
## `slack_metres` is how far short to stop, for the deceleration a released throttle does not
## cancel instantly. `from_tile` is where the player is starting, which the scenario knows
## because it put them there.
static func _walk_to(
	scenario: BalanceScenario,
	start_tick: int,
	target_tile: Vector3i,
	slack_metres: int,
	from_tile: Vector3i = Vector3i(0, GROUND, 0),
	from_yaw: int = 0
) -> int:
	var from: FixedVec2 = WorldGrid.tile_centre_metres(from_tile)
	var to: FixedVec2 = WorldGrid.tile_centre_metres(target_tile)
	var away_x: int = to.x - from.x
	var away_z: int = to.z - from.z
	var distance: int = Fixed.sqrt(Fixed.mul(away_x, away_x) + Fixed.mul(away_z, away_z))
	var travel: int = maxi(distance - Fixed.from_int(slack_metres), 0)
	var ticks: int = _sprint_ticks_for(travel)

	scenario.at(start_tick, [
		InputAction.look(0, _look_pixels_between(from_yaw, heading_towards(from_tile, target_tile)), 0),
		InputAction.sprint(0, true),
	])
	scenario.hold(start_tick + 1, ticks, [InputAction.move(0, Fixed.ONE, 0)])
	scenario.at(start_tick + 1 + ticks, [InputAction.sprint(0, false)])
	return start_tick + 2 + ticks


## The yaw, in Fixed turns, that points from one tile at another.
##
## A scan rather than an arctangent, because the Simulation has no arctangent and inventing
## one here would be a second definition of "which way am I facing". It walks headings and
## keeps the one whose facing has the largest dot product with the direction wanted, using
## the same `Fixed.sin_turns` the Simulation steers by — so the answer agrees with where the
## player will actually go.
##
## Public because a scenario that chains two walks has to know the yaw it left the player at:
## `look` is a **delta**, not a heading.
static func heading_towards(from_tile: Vector3i, to_tile: Vector3i) -> int:
	var from: FixedVec2 = WorldGrid.tile_centre_metres(from_tile)
	var to: FixedVec2 = WorldGrid.tile_centre_metres(to_tile)
	var away_x: int = to.x - from.x
	var away_z: int = to.z - from.z
	var length: int = Fixed.sqrt(Fixed.mul(away_x, away_x) + Fixed.mul(away_z, away_z))
	if length <= 0:
		return 0
	var want_x: int = Fixed.div(away_x, length)
	var want_z: int = Fixed.div(away_z, length)

	var best_yaw: int = 0
	var best_dot: int = -Fixed.ONE * 2
	for step: int in range(HEADING_STEPS):
		@warning_ignore("integer_division")
		var yaw: int = step * Fixed.ONE / HEADING_STEPS
		var dot: int = (
			Fixed.mul(-Fixed.sin_turns(yaw), want_x) + Fixed.mul(-Fixed.cos_turns(yaw), want_z)
		)
		if dot > best_dot:
			best_dot = dot
			best_yaw = yaw
	return best_yaw


## The mouse travel that turns a player from one yaw to another, as the fixed-point pixels
## `InputAction.look` takes. `_apply_look` *subtracts*, so reaching a larger yaw means
## travelling the rest of the way round.
static func _look_pixels_between(from_yaw: int, to_yaw: int) -> int:
	return Fixed.mul(
		Fixed.wrap_turns(from_yaw - to_yaw), Fixed.from_int(LOOK_PIXELS_PER_TURN)
	)


## How many ticks of held sprint cover a distance.
##
## The sprint is `player.walk_speed_metres_per_second` times
## `player.sprint_speed_multiplier` — 7.2 m/s on the shipped numbers — reached over
## `player.sprint_ramp_seconds`. The ramp is charged as a flat 20 ticks of overhead rather
## than integrated, because a scenario that stops a metre early is a scenario that stops a
## metre early, and the report says where the player ended up.
static func _sprint_ticks_for(distance_metres: int) -> int:
	var per_tick: int = Fixed.div(
		Fixed.from_rational(72, 10), Fixed.from_int(Simulation.TICKS_PER_SECOND)
	)
	if per_tick <= 0:
		return 0
	return Fixed.floor_to_int(Fixed.div(distance_metres, per_tick)) + 20
