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

## #60: where the second Ammo Press stands, and the second Turret it feeds.
##
## **The pair #34 left unmeasured.** `competent` ends with 96 rounds still in the Factory and
## `fortified` with 112, so one Turret cannot spend what one Press makes — which says the plate
## is better spent on throughput than on a second gun, and leaves the obvious next build
## untested: a second Press *and* a second Turret, so that there is both more Ammunition and
## somewhere for it to go.
##
## The Press sits east of the Smelter, fed by a second Belt off the Smelter's own eastern wall,
## and the Turret it feeds stands at (11, 7) — one tile south of `fortified`'s, because
## `fortified`'s own tile is where this row's plate Belt has to run. Measured off the footprint
## centres, an 8-tile reach from there covers **all six** Machines of the opening line: the iron
## Miner at 15.2 m, the Smelter at 7.1 m, the first Ammo Press at 7.8 m, the coal Miner at
## 6.3 m, the Boiler at 12.5 m and the second Press at 9.2 m.
const SECOND_PRESS_TILE: Vector3i = Vector3i(14, GROUND, 10)
const SECOND_PRESS_TURRET_TILE: Vector3i = Vector3i(11, GROUND, 7)

## #60: the funnel, and the one thing on this Map a Wall can be.
##
## A line of Wall across the lane at x = 6, from z = -11 to z = 0, with the tile the Breach's own
## latitude runs through left **open**. Eleven tiles at two plate each is 22 of the 25 the
## call-early lever pays, which is what makes this row `fortified`'s sibling: the same single
## pull, spent on Wall instead of on a second Turret.
##
## **A gap rather than a seal, and that is the design rather than a shortfall.** Enemies route
## four-connected on a shared flowfield, so a line with a hole in it is a line they walk through
## — and the hole is three and a half tiles from the Turret's own footprint, with every tile of
## the Wall inside its 16 m reach. So what 22 plate buys is a Wave that comes through the one
## place the gun is pointed, which is the best case a Wall has here. A line with no gap would be
## walked round, because the Map is 129 tiles across and has no choke in it.
const WALLED_LANE_X: int = 6
const WALLED_LANE_FROM_Z: int = -11
const WALLED_LANE_TO_Z: int = 0

## The one tile of that line left open, which is the Breach's own latitude on the starter Map.
const WALLED_LANE_GAP_Z: int = -6

## #60: the four tiles that seal the one Breach, which is the only arrangement on this Map that
## gets a Wall *bitten*.
##
## `_enemy_contact_target` chews a Wall in exactly one case — an Enemy in a pocket it cannot
## route out of — so a Wall that can be walked round is never attacked, whatever it cost. Four
## tiles, eight plate, and `wall.health` against `enemy.crawler_damage` and `enemy.breaker_damage`
## is finally a measurement rather than arithmetic.
const SEALED_BREACH_TILES: Array = [
	Vector3i(15, GROUND, -6),
	Vector3i(17, GROUND, -6),
	Vector3i(16, GROUND, -7),
	Vector3i(16, GROUND, -5),
]

## #60: where `deep_silo` stands its Silo, and where the player walks to load and paint it.
##
## It sits south of the Ammo Press, on ground the coal haul to the Nest is standing on — so it
## cannot go up until that line comes down at five minutes, which is the same decision this row
## already models. The loading spot is one tile south of the Silo's own wall, inside
## `silo.load_reach_metres` of 4 m, and it is also the tile the Painting is held over: a Supply
## Drop lands in the painting player's own pockets, so where they stand is the whole of the aim.
const DEEP_SILO_TILE: Vector3i = Vector3i(9, GROUND, 14)
const DEEP_SILO_WAYPOINT: Vector3i = Vector3i(-3, GROUND, 18)
const DEEP_SILO_LOADING_SPOT: Vector3i = Vector3i(11, GROUND, 18)

## How many Charges `deep_silo` commits to one load. **One**, against `artillery`'s two, because
## this Run is twelve minutes long and its Ammo Press is feeding three claimants: a Charge is
## twenty rounds, and a Charge is a multiplier rather than a minimum, so one is what a Factory
## this stretched can actually bank before the Nest falls.
const DEEP_SILO_CHARGES: int = 1

## #62: how long a burst is, and how often one is spent.
##
## **The difference between this and `rifle_picket`, and the whole reason #62 needed a second
## armed row.** The picket leans on the trigger for thirty seconds of every minute whether or
## not there is anything on the Map to shoot — 37 rounds a minute, which is one whole Ammo
## Press, so it is a measurement of a player's impatience rather than of a player's fight. A
## burst is what fighting a Wave actually costs: a Bolt Rifle does 30 damage a shot against a
## Crawler's 30 hit points, so one shot is one Crawler, and `competent` is sent six Crawlers a
## Wave early on and ten late. Eight seconds at `bolt_rifle`'s 0.8 s between shots is ten
## shots, which is a Wave's worth of Chaff and not a round more.
##
## Forty seconds between bursts because that is `heat.wave_interval_minimum_seconds` — the
## floor the schedule spends most of a long Run pinned at — so a Run that lasts is a Run
## firing about one burst a Wave. Early, when the gap is ninety seconds and then sixty, the
## player is firing more often than Waves arrive and the report says so in the shots fired
## against the rounds that reached him.
##
## **It is a discipline and not a reaction, and that limit is the instrument's rather than the
## design's.** A scenario is a function from tick to Input Actions and cannot see a Wave
## coming, so a burst lands where the clock says and not where the Crawlers are. What that
## costs is rounds spent at nothing, which is the same error in the same direction as the
## picket's and about a third of the size.
const BURST_SECONDS: int = 8
const BURST_CYCLE_SECONDS: int = 40

## Where a player stands to arm themselves, which is **not a choice the scenario makes**.
##
## A withdrawal is made from `nest.delivery_reach_metres` of the Nest's footprint, through the
## same `_player_is_at_the_nest` a hand-over goes through — there is no spot a player can stand
## on where the Nest takes goods but hands none back, and there is no spot off it where it hands
## any back at all. So "a player who arms themselves out of their own store" is a player standing
## at the counter, and that is a property of the faucet rather than of this row. It is also the
## same tile `rifle_picket` fires from, which is what makes the two rows comparable.
const NEST_COUNTER: Vector3i = Vector3i(-3, GROUND, -3)

## How many rounds a withdrawal asks for.
##
## Deliberately far more than a burst spends, because `_apply_withdraw_from_nest` clamps to what
## is there: asking for sixty is asking for *whatever the store has*, which is what a player
## does, and it makes the dryness figure a measurement of the Factory rather than of how much
## this scenario thought to ask for. The same figure `rifle_picket` asks for, for the same
## reason.
const ROUNDS_PER_WITHDRAWAL: int = 60

## How far short of a target a sprint is aimed, in metres, when the tile a walk ends on matters.
##
## **Measured rather than reasoned about.** `_sprint_ticks_for` charges the ramp as a flat twenty
## ticks and nothing cancels the deceleration a released throttle leaves, so a leg aimed exactly
## at its target overshoots it by a little over four metres — two tiles, which is the difference
## between a Painting that lands and a `NOT_AT_THE_TARGET`. The first attempt at `deep_silo`
## overshot its loading spot by 4.2 m and reported a Silo that was never loaded, which is what
## this constant exists to stop being rediscovered.
const WALK_SLACK_METRES: int = 4

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
		second_press(),
		walled_lane(),
		sealed_breach(),
		branched_artillery(),
		deep_silo(),
		coal_haul(),
		armed_player(),
		armed_second_press(),
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
		"bare", "builds nothing — the opening 110 plate never leaves their pockets"
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
## 108 of the 110 plate a Run opens with — 78 of Machines and 30 tiles of Belt, since #47
## priced them — which is why this is *the* opening Factory rather
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
	# The second Turret's feed waits on the lever with the Turret itself, since #47 priced a
	# Belt: the opening bill covers the Factory's own thirty tiles and no more, so these four
	# come out of the same bounty the Turret does.
	scenario.at_second(60, [InputAction.call_wave_early(0)])
	scenario.at_second(61, [_turret(FACTORY_TURRET_TILE)])
	scenario.at_second(62, _factory_turret_belts())
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
	return _deep_digger(
		"deep_digger",
		"pays the Delivery chain off the Factory's output, then digs Depth 2",
		true,
		false
	)


## `deep_digger` with the coal haul **left standing**, which is finding 9's own variant.
##
## The finding is that a long Belt is a long buffer: forty tiles hold 160 coal before
## back-pressure ever reaches the Miner, so a line run to the Nest to pay a twenty-coal bill goes
## on diverting the Boiler's fuel for as long as it is filling. Measured before #46 — when that
## line took **all** the Miner's coal rather than half of it — the Run was 6m20s with 98% of
## itself in Power deficit, against 10m48s with the demolish in. #46 changed exactly the quantity
## that figure depended on and nobody re-measured it, which is what this row is for: the same
## trap on a fair share.
##
## It is `deep_digger` with one segment removed and nothing else, so the difference between the
## two rows is the decision to tear the line down and nothing else.
static func coal_haul() -> BalanceScenario:
	return _deep_digger(
		"coal_haul",
		"pays the chain the same way and never tears the forty-tile coal haul down",
		false,
		false
	)


## `deep_digger` with a Silo, which is the only Run in the table that pays `t02_deep_mining` —
## and therefore the only one that has ever unlocked a second Stratagem.
##
## **`artillery` fires a Sentry Drop because it is the one row the shipped chain does not lock**,
## so a Barrage's 150 points over six tiles and a Supply Drop into a player's own pockets have
## both been arithmetic since #17. This row goes for the Barrage first and takes whatever is
## actually unlocked: the dial is wound to `artillery_barrage`, then to `supply_drop`, then to
## `sentry_drop`, and a load of something a Delivery still locks is a silent refusal whose hash
## does not move. `BalanceProbe.Report.stratagems_called` is what says which one it got, because
## a count of Stratagems fired cannot tell those three apart.
##
## The Silo stands on ground the coal haul occupies, so it waits for the five-minute demolish;
## its plate comes off the Smelter's southern wall and its rounds off the Ammo Press's southern
## one, which makes that Press a **three-way** branch — the first Turret, the Nest, and the Silo.
static func deep_silo() -> BalanceScenario:
	return _deep_digger(
		"deep_silo",
		"pays the chain, digs Depth 2, and stands a Silo up out of what is left",
		true,
		true
	)


static func _deep_digger(
	scenario_id: String, summary: String, tear_the_coal_line_down: bool, with_a_silo: bool
) -> BalanceScenario:
	var scenario: BalanceScenario = BalanceScenario.named(scenario_id, summary)
	scenario.at(1, _iron_line() + _power_line() + [_turret(TURRET_TILE)])
	scenario.at(2, _iron_belts() + _power_belts() + _first_ammunition_belts())
	# **The two Nest lines are laid when the Run can pay for them, not at tick 3.** #47 gave a
	# Belt a price per tile, and these two lines are forty and twenty-four tiles — 64 plate
	# against an opening bill budgeted for the thirty tiles the Factory itself needs. So they
	# wait on the lever, which is the only plate a Run has early: two pulls buy the coal line
	# and a third buys the ammunition line, and each pull is a Wave arriving sooner. That is
	# the Belt price doing exactly what it is for — a forty-tile haul to pay a twenty-coal
	# bill is now a visible forty-plate decision rather than a free one — and it is why this
	# row's figure moved. The coal line's episode is the same shape it always was, two minutes
	# later: lay it, let it divert the Boiler's fuel, tear it down once the tier is paid.
	scenario.at_second(121, _coal_belts_to_the_nest())
	scenario.at_second(181, _ammunition_belts_to_the_nest())
	# The player walks to the Nest's counter and stays there: handing goods over and taking
	# them back out both happen at that one counter. They will be bitten standing there, and
	# the report counts it.
	_walk_to(scenario, 10 * Simulation.TICKS_PER_SECOND, Vector3i(-3, GROUND, -3), 0)
	# And the coal line comes back down at five minutes, which is still the decision this row
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
	if tear_the_coal_line_down:
		scenario.at_second(300, _demolish_all(_coal_belts_to_the_nest_tiles()))
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
		# **A Run going for artillery stops paying the chain**, and it has to: `t03_deep_survey`
		# wants 400 plate, `deliver_to_nest` hands over everything the player is carrying up to
		# the open bill, and the call-early lever is the only plate this Run has. Measured, the
		# first attempt at this row shovelled every pull at a tier it could never finish and
		# reported a Silo that was never built. Six minutes is where `t02_deep_mining` lands.
		if not with_a_silo or minute <= 6:
			scenario.at_second(minute * 60 + 1, [InputAction.deliver_to_nest(0)])
		scenario.at_second(minute * 60 + 2, [InputAction.withdraw_from_nest(0, plate, 40)])
		scenario.at_second(minute * 60 + 3, [_machine("miner_mk2", DEEP_IRON_NODE)])
	if with_a_silo:
		_add_a_silo_to_the_deep_dig(scenario)
	return scenario


## The Silo half of `deep_silo`: four builds attempted blind, a walk, a load and a Painting.
##
## Everything here is attempted repeatedly and from a fixed tick, because a scenario is a
## function from tick to Input Actions and cannot look at the Run. The Silo's ground is under the
## coal haul until five minutes, so the builds start after that; the walk goes south down the
## corridor the haul itself has just vacated and then east along z = 18, which is clear ground on
## both legs.
static func _add_a_silo_to_the_deep_dig(scenario: BalanceScenario) -> void:
	# The Silo stands on ground the coal haul occupies until the five-minute demolish, so the
	# builds are attempted from just after it and go on being attempted: the plate they need is
	# competing with `t02_deep_mining`'s 120, and which minute it is finally there is not
	# something an open-loop script can know.
	# **The second Boiler comes with the Silo**, which is #37's answer applied to a Factory that
	# also paid for Depth 2: a Silo draws 400 kW and a Miner Mk2 on the Depth 2 seam draws its
	# quoted 200 plus `depth.draw_percent_per_depth` of it again, so the Nest's plant and one
	# Boiler cannot carry both. A Boiler is on the grid only while it burns, so the one coal Node
	# pays for a second one.
	for attempt: int in range(0, 43):
		var second: int = 310 + attempt * 10
		scenario.at_second(second, [_machine("silo_mk1", DEEP_SILO_TILE)])
		scenario.at_second(second + 1, _deep_silo_belts())
		scenario.at_second(second + 2, [_machine("steam_boiler_mk1", SECOND_BOILER_TILE)])
		scenario.at_second(second + 3, _second_boiler_belts())

	# **And the Nest's Ammunition line comes down with the chain payments.** Once a Run has
	# stopped paying for Deliveries, the rounds it was banking at the counter are rounds the
	# Silo could be assembling Charges out of — so the Ammo Press goes from a three-way branch
	# back to two, and the Silo's share goes from a third to a half. Measured, the first attempt
	# at this row left all three open and reported a Silo that stood for two minutes with eighteen
	# rounds in the whole Factory and never banked a single Charge.
	scenario.at_second(540, _demolish_all(_ammunition_belts_to_the_nest_tiles()))

	# Out to the Silo at eight minutes, down the corridor the coal haul has just vacated and then
	# east along z = 18. **The yaw this leg starts from is the one the walk to the Nest left**:
	# `look` carries a delta rather than a heading, so a leg that assumed zero would set off in
	# the wrong direction — which is exactly what it did on the first attempt, and the row reported
	# a Silo that was never loaded rather than anything looking wrong.
	var home: Vector3i = Vector3i(0, GROUND, 0)
	var nest_post: Vector3i = Vector3i(-3, GROUND, -3)
	var turn: int = _walk_to(
		scenario,
		480 * Simulation.TICKS_PER_SECOND,
		DEEP_SILO_WAYPOINT,
		WALK_SLACK_METRES,
		nest_post,
		heading_towards(home, nest_post)
	)
	_walk_to(
		scenario,
		turn,
		DEEP_SILO_LOADING_SPOT,
		0,
		DEEP_SILO_WAYPOINT,
		heading_towards(nest_post, DEEP_SILO_WAYPOINT)
	)

	# Then, every twenty seconds: wind the dial to the best Stratagem the chain might have reached
	# and then to the ones it certainly has, commit, and hold the key.
	#
	# **A load of something a Delivery still locks is a silent refusal**, and so is a load onto a
	# Silo that already has one — which is what makes asking for all three safe. The order is the
	# preference: a Barrage is the thing this row exists to try, and a Supply Drop is what
	# `t02_deep_mining` actually buys.
	#
	# **The load has to come before the Painting and not beside it**, because `_act_refusal`
	# answers `PLAYER_IS_PAINTING` to every intent a player sends: somebody mid-channel cannot
	# load. So each attempt is dial, load, then ten seconds of key — and an attempt whose Charge
	# was lost to a bite is followed by another one twenty seconds later.
	var wanted: PackedStringArray = PackedStringArray(
		["artillery_barrage", "supply_drop", "sentry_drop"]
	)
	# Every twelve seconds rather than every twenty, because the Charge this row is waiting for
	# arrives late and the window is a twelve-minute Run: the Ammo Press is feeding the Turret and
	# the Silo while the Smelter is feeding the Press and the Silo, so a twenty-round Charge takes
	# a little over two minutes to assemble. The first attempt at this row banked its Charge with
	# twenty seconds of Run left and fired nothing.
	for attempt: int in range(0, 22):
		var second: int = 480 + attempt * 12
		for choice: int in range(wanted.size()):
			var index: int = _definitions().stratagem_index(wanted[choice])
			scenario.at_second(
				second + choice * 2,
				[InputAction.set_silo_dial(0, index, DEEP_SILO_CHARGES)]
			)
			scenario.at_second(
				second + choice * 2 + 1,
				[InputAction.load_silo(0, DEEP_SILO_TILE, index, DEEP_SILO_CHARGES)]
			)
		# The Painting is held on the tile the player is already standing on: a Supply Drop lands
		# in their own pockets and a Sentry lands where they stand, so there is nowhere to walk to.
		scenario.hold_seconds(
			second + 6, 5, [InputAction.paint(0, DEEP_SILO_LOADING_SPOT)]
		)


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
## It is also #17's fourth claimant, and **#62 measured what it actually spends rather than what
## it demands.** This comment used to say the rifle spends rounds at 75 a minute against a Press
## that makes 37, and that figure is a *demand*: the Nest's line is a 50/50 branch off one Press,
## so it pays about nineteen rounds a minute, and this row receives 520 over a 27-minute Run,
## fires all 520, and **holds an empty gun for 74% of it.** Its thirty-second bursts are mostly
## dry trigger pulls, which is the mechanical reason its end-to-end margin has moved five times
## across five tickets without anything about Ammunition changing — the demand it was built to
## measure never happened. `armed_player` is the row to read about arming a player; this one is
## still the row the seed can reach.
static func rifle_picket() -> BalanceScenario:
	var scenario: BalanceScenario = BalanceScenario.named(
		"rifle_picket", "the competent chain, plus a rifleman at the Nest spending the same rounds"
	)
	scenario.at(1, _iron_line() + _power_line() + [_turret(TURRET_TILE)])
	scenario.at(2, _iron_belts() + _power_belts() + _first_ammunition_belts())
	# **The line that banks his magazine costs twenty-four plate now, and the lever is what pays
	# for it.** #47 priced a Belt per tile and the opening bill covers the Factory's own thirty
	# tiles, so a rifleman who wants Ammunition at the Nest buys the haul with one pull of the
	# call-early lever — one Wave arriving sooner than it would have. That is a cost this row
	# did not carry before and it is the right one: the rounds he spends were never free, and
	# now neither is the Belt that brings them to him.
	scenario.at_second(60, [InputAction.call_wave_early(0)])
	scenario.at_second(61, _ammunition_belts_to_the_nest())
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
	return _artillery(
		"artillery", "grows a second Boiler and ore line, then loads and fires a Silo", false
	)


## `artillery` with **no second ore line**: the Silo's plate comes off a branch of the first
## Smelter, down a thirty-five-tile haul, instead of out of a Miner and a Smelter of its own.
##
## **The Run #46 made possible and none of the nine built.** Every scenario in this table is a
## Factory a player would have laid out before a line could branch, and the sharpest missing one
## is this: `artillery` saves a Miner and a Smelter — 20 plate, 300 kW and two Machines' worth of
## Heat — at the price of halving the plate reaching the Ammo Press for as long as the Silo's
## branch is filling. The arithmetic says it works, because the Silo wants about 3 plate a minute
## out of 18.75 and its branch therefore fills, backs up and hands the Press everything back.
## Arithmetic is what this harness exists to replace.
##
## **The haul is the thing the arithmetic left out.** The Silo stands where the second ore line
## put it, so plate from the first Smelter has to travel the long way round the Factory and the
## Nest to reach its western wall: thirty-five tiles, which is 35 plate against the 24 the ore
## line and its four Belts cost. So branching is *dearer* on this geography, and it is also
## thirty-five tiles of buffer — the Press is halved until all thirty-five are full, which is
## finding 9's shape in a line nobody would have called a haul.
##
## The lever is pulled the same seven times as `artillery`, so the two rows cost the Enemy the
## same and differ only in what was built.
static func branched_artillery() -> BalanceScenario:
	return _artillery(
		"branched_artillery",
		"the same Silo, fed off a branch of the one Smelter instead of a second ore line",
		true
	)


static func _artillery(
	scenario_id: String, summary: String, branched: bool
) -> BalanceScenario:
	var scenario: BalanceScenario = BalanceScenario.named(scenario_id, summary)
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
		if not branched:
			scenario.at_second(minute * 60 + 2, [_machine("miner_mk1", SECOND_MINER_TILE)])
			scenario.at_second(minute * 60 + 3, [_machine("smelter_mk1", SECOND_SMELTER_TILE)])
		scenario.at_second(minute * 60 + 4, [_machine("silo_mk1", SILO_TILE)])
		scenario.at_second(minute * 60 + 5, _second_boiler_belts())
		if branched:
			scenario.at_second(minute * 60 + 6, _branched_plate_belts())
		else:
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


## The competent Factory, then a second Ammo Press and a second Turret for it to feed.
##
## **The claim CLAUDE.md has made on arithmetic since #10, and the one #34 sharpened rather than
## answered.** A second Press is "the arithmetic answer to the middle of the Run" — production is
## the defence — and a second Turret was measured by `fortified` and came out a wash. What has
## never been measured is the pair: more Ammunition *and* somewhere for it to go.
##
## Three Machines' worth of plate out of the call-early lever: the Press at 14, the Turret at 20
## and eleven tiles of Belt at one each, which is two pulls and two Waves arriving sooner.
##
## **The plate it eats is the plate the first Press was eating**, which is the whole question.
## The Smelter makes 18.75 plate a minute and one Press wants 20, so a second Belt off that
## Smelter is a 50/50 share since #46 — about 9.4 plate a minute each, and two Presses each
## running at half speed make exactly what one running at 94% made. If that is what happens then
## the arithmetic answer is wrong and the answer is a second *Smelter*; the row is here to say
## which.
static func second_press() -> BalanceScenario:
	var scenario: BalanceScenario = BalanceScenario.named(
		"second_press", "a second Ammo Press and a second Turret, off the one Smelter"
	)
	scenario.at(1, _iron_line() + _power_line() + [_turret(TURRET_TILE)])
	scenario.at(2, _iron_belts() + _power_belts() + _first_ammunition_belts())
	# Two pulls, two builds, attempted blind once a minute from the first minute on — the shape
	# `artillery` uses. A build nobody can afford is `MISSING_MATERIALS` and one on ground already
	# taken is `OCCUPIED`, both silent, so repeating the list is how an open-loop script says "as
	# soon as the plate is there".
	for minute: int in range(1, 11):
		if minute <= 2:
			scenario.at_second(minute * 60, [InputAction.call_wave_early(0)])
		scenario.at_second(minute * 60 + 1, [_machine("ammo_press_mk1", SECOND_PRESS_TILE)])
		scenario.at_second(minute * 60 + 2, _second_press_plate_belts())
		scenario.at_second(minute * 60 + 3, [_turret(SECOND_PRESS_TURRET_TILE)])
		scenario.at_second(minute * 60 + 4, _second_press_ammunition_belts())
	return scenario


## The competent Factory, a haul banking rounds at the Nest, and a player who arms himself out
## of it and fights in bursts.
##
## **#62's question, which this table could not ask.** `player.starting_stock` is plate alone
## and deliberately so — rounds in the opening bill would conjure the one thing the Factory
## exists to make — so a Run opens with a rifle that is a stick, and #27's faucet is the only
## way it ever fires. `test_gear` walks that chain once: belt plate to the Nest, bank a round,
## withdraw it, kill a Crawler. Whether it *keeps up* across a Run, against the Turret drinking
## from the same Ammo Press, had never been played.
##
## **It is not `rifle_picket` and the difference is the point.** That row leans on the trigger
## for thirty seconds of every minute, which is 37 rounds a minute — one whole Press — spent
## whether or not anything is on the Map; its own note says so, and CLAUDE.md records that its
## end-to-end margin has moved five times across five tickets without one of them touching what
## a round costs or what a Press makes. So the picket's clock cannot be read as an Ammunition
## finding, and a row that could had to spend rounds the way a fight does. See `BURST_SECONDS`.
##
## What it costs to set up is one pull of the call-early lever for the twenty-four-tile haul
## that banks rounds at the counter, which is exactly what the picket pays — so the two rows
## differ in trigger discipline and in nothing else a player paid for.
static func armed_player() -> BalanceScenario:
	return _armed_player(
		"armed_player",
		"arms himself at the Nest's counter and fights the Waves in bursts",
		false
	)


## `armed_player` with #60's second Ammo Press and the second Turret that spends it.
##
## **The second half of #62's acceptance criterion, and the pair is controlled against #60's.**
## `second_press` answered the Turret side and answered it against expectation: the pair is 16%
## *shorter* than `competent` and ends holding 416 rounds nobody could spend, because a Turret's
## output is bounded by how long an Enemy spends inside its 16 m and not by its feed. What that
## leaves open is the player's side — a player is not range-bound, so rounds a Turret cannot
## spend are rounds a player could.
##
## This row builds exactly what `second_press` builds, on the same tiles, out of the same two
## extra pulls of the lever, so `armed_player` against this is the same difference
## `competent` against `second_press` is: a Press, a gun, eleven tiles of Belt and two Waves
## arriving sooner.
##
## **And it is a real question rather than a formality, because the second Press does not
## obviously help the player at all.** It is fed off a second Belt from the one Smelter, which
## since #46 is a 50/50 share — so the first Press, the only one whose rounds reach *either* the
## lane Turret or the Nest's counter, is halved. Measured, this is the one build in the table
## where that halving and the player's own share land on the same Press: the lane Turret is fed
## 9.4 rounds a minute against `competent`'s 37.5, which is a quarter. The second Press's rounds
## go to the second Turret and never come near the store, so they make up neither shortfall. On
## the arithmetic the player is worse off; the row is here to say by how much.
static func armed_second_press() -> BalanceScenario:
	return _armed_player(
		"armed_second_press",
		"the same armed player, on #60's second Ammo Press and second Turret",
		true
	)


static func _armed_player(
	scenario_id: String, summary: String, with_a_second_press: bool
) -> BalanceScenario:
	var scenario: BalanceScenario = BalanceScenario.named(scenario_id, summary)
	scenario.at(1, _iron_line() + _power_line() + [_turret(TURRET_TILE)])
	scenario.at(2, _iron_belts() + _power_belts() + _first_ammunition_belts())

	# The haul that banks rounds at the counter costs twenty-four plate, which the opening bill
	# does not stretch to: it covers the Factory's own thirty tiles and two plate over. So it is
	# bought with a pull of the lever, exactly as `rifle_picket` buys the same line — one Wave
	# arriving sooner, which is the right price for it, because the rounds he spends were never
	# free and nor is the Belt that brings them to him.
	scenario.at_second(60, [InputAction.call_wave_early(0)])
	scenario.at_second(61, _ammunition_belts_to_the_nest())

	# #60's pair, on #60's tiles, out of two more pulls. Attempted blind once a minute from the
	# first minute on, the shape `second_press` uses: a build nobody can afford is
	# `MISSING_MATERIALS` and one on ground already taken is `OCCUPIED`, both silent no-ops whose
	# hash does not move, so repeating the list is how an open-loop script says "as soon as the
	# plate is there".
	if with_a_second_press:
		for minute: int in range(2, 12):
			if minute <= 3:
				scenario.at_second(minute * 60 + 10, [InputAction.call_wave_early(0)])
			scenario.at_second(minute * 60 + 11, [_machine("ammo_press_mk1", SECOND_PRESS_TILE)])
			scenario.at_second(minute * 60 + 12, _second_press_plate_belts())
			scenario.at_second(minute * 60 + 13, [_turret(SECOND_PRESS_TURRET_TILE)])
			scenario.at_second(minute * 60 + 14, _second_press_ammunition_belts())

	# To the counter, which is where a withdrawal has to be made from. See `NEST_COUNTER`.
	_walk_to(scenario, 10 * Simulation.TICKS_PER_SECOND, NEST_COUNTER, 0)
	# Rifle out, pointed down the lane the one Breach feeds. The weapon has to be drawn before
	# anything is fired: a Run opens with the Build Gun holstered and the wrench in hand (#42),
	# and a `fire` sent in build mode places a Machine instead.
	scenario.at_second(20, [
		InputAction.set_build_mode(0, false),
		InputAction.equip_weapon(0, _definitions().gear_index("bolt_rifle")),
		InputAction.look(
			0,
			_look_pixels_between(
				heading_towards(Vector3i(0, GROUND, 0), NEST_COUNTER),
				heading_towards(NEST_COUNTER, Vector3i(16, GROUND, -6))
			),
			0
		),
	])

	# Then the fight, as a cycle rather than as a minute: take whatever the store has, wait a
	# second for it to land, and spend a burst. See `BURST_SECONDS` for why eight seconds in
	# forty rather than thirty in sixty, and `ROUNDS_PER_WITHDRAWAL` for why he asks for sixty
	# of something he will spend ten of.
	var ammunition: int = _definitions().item_index("ammunition")
	var cycles: int = 60 * 60 / BURST_CYCLE_SECONDS
	for cycle: int in range(1, cycles):
		var second: int = cycle * BURST_CYCLE_SECONDS
		scenario.at_second(
			second, [InputAction.withdraw_from_nest(0, ammunition, ROUNDS_PER_WITHDRAWAL)]
		)
		scenario.hold_seconds(second + 1, BURST_SECONDS, [InputAction.fire(0)])
	return scenario


## The competent Factory, then a funnel of Wall across the lane instead of a second Turret.
##
## **`fortified`'s sibling, and the one thing in this table that has never built a Wall.**
## `wall.health` is 240 against a Breaker's 60 a second, and since #47 a Wall costs two plate a
## tile — priced against a Belt's one on an argument about what a player would rather lose, with
## nothing measuring whether anybody ever wants one at that price. This row spends the same
## single pull of the call-early lever `fortified` spends on a second MG on eleven tiles of Wall
## instead, so the gap between the two rows is what 22 plate bought in each form.
##
## See `WALLED_LANE_X` for why the line has a gap in it: a Wave routes round a seal and walks
## through a funnel, and the funnel's mouth is three and a half tiles from the Turret.
static func walled_lane() -> BalanceScenario:
	var scenario: BalanceScenario = BalanceScenario.named(
		"walled_lane", "spends the call-early plate on a funnel of Wall rather than a second Turret"
	)
	scenario.at(1, _iron_line() + _power_line() + [_turret(TURRET_TILE)])
	scenario.at(2, _iron_belts() + _power_belts() + _first_ammunition_belts())
	scenario.at_second(60, [InputAction.call_wave_early(0)])
	# Attempted for five minutes rather than once, because a Wall on ground already walled is an
	# `OCCUPIED` no-op and a pull refused for a Wave still arriving would otherwise cost the row
	# its whole build.
	for minute: int in range(1, 6):
		scenario.at_second(minute * 60 + 1, _walled_lane_walls())
	return scenario


## The competent Factory, then four tiles of Wall sealing the one Breach.
##
## **The only arrangement on this Map that gets a Wall bitten**, and therefore the only one that
## measures `wall.health` against what chews it. `_enemy_contact_target` attacks a Wall in
## exactly one case — an Enemy in a pocket it cannot route out of — so the funnel in
## `walled_lane` is never attacked at all, however much it cost. Four tiles box the Breach in,
## Enemies come out into a pocket, and `wall_hit_points_absorbed` is what 8 plate was worth.
##
## `test_machine_mortality.test_sealing_a_breach_buys_time_rather_than_stopping_a_wave` already
## says a seal buys time rather than stopping a Wave. What it does not say is **how much**, on
## the shipped Map against the shipped Waves, which is a number rather than a rule.
##
## Sealed once and never rebuilt, deliberately: one pull of the lever and one decision, so what
## is measured is what a seal is worth and not what a treadmill of seals is worth.
static func sealed_breach() -> BalanceScenario:
	var scenario: BalanceScenario = BalanceScenario.named(
		"sealed_breach", "spends the call-early plate on walling the Breach shut, once"
	)
	scenario.at(1, _iron_line() + _power_line() + [_turret(TURRET_TILE)])
	scenario.at(2, _iron_belts() + _power_belts() + _first_ammunition_belts())
	scenario.at_second(60, [InputAction.call_wave_early(0)])
	for minute: int in range(1, 6):
		scenario.at_second(minute * 60 + 1, _sealed_breach_walls())
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
## One tile of each of the Nest's Ammunition Belts, which is all a demolish needs.
static func _ammunition_belts_to_the_nest_tiles() -> Array:
	return [
		Vector3i(7, GROUND, 11),
		Vector3i(-1, GROUND, 11),
		Vector3i(-1, GROUND, -3),
	]


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


## Plate off the Smelter's **eastern** wall and round the north of the coal Miner into the second
## Ammo Press's own northern face.
##
## East rather than south because an Ammo Press takes plate on its north face and nowhere else
## (`content/machine_ports.csv`), so the Belt that feeds one has to arrive travelling south — and
## the Smelter's southern docks are where the first Press's line already starts. Three tiles east,
## then four south.
static func _second_press_plate_belts() -> Array:
	return [
		InputAction.build_belt(0, Vector3i(11, GROUND, 6), Vector3i(13, GROUND, 6)),
		InputAction.build_belt(0, Vector3i(14, GROUND, 6), Vector3i(14, GROUND, 9)),
	]


## Rounds off the second Press's western wall and north into the second Turret's southern face.
static func _second_press_ammunition_belts() -> Array:
	return [
		InputAction.build_belt(0, Vector3i(13, GROUND, 10), Vector3i(12, GROUND, 10)),
		InputAction.build_belt(0, Vector3i(11, GROUND, 10), Vector3i(11, GROUND, 9)),
	]


## The funnel: every tile of the line at `WALLED_LANE_X` except the one the Breach's latitude
## runs through. One Input Action a tile, because a Wall is one tile per intent — a Belt is a run
## because Items travel along it, and a Wall is a tile because the only question it answers is
## whether *this* tile is walkable.
static func _walled_lane_walls() -> Array:
	var out: Array = []
	for z: int in range(WALLED_LANE_FROM_Z, WALLED_LANE_TO_Z + 1):
		if z == WALLED_LANE_GAP_Z:
			continue
		out.append(InputAction.build_wall(0, Vector3i(WALLED_LANE_X, GROUND, z)))
	return out


## The seal: the four tiles four-connected movement has to cross to leave the Breach.
static func _sealed_breach_walls() -> Array:
	var out: Array = []
	for tile: Vector3i in SEALED_BREACH_TILES:
		out.append(InputAction.build_wall(0, tile))
	return out


## The Silo's own plate and rounds, in `deep_silo`: plate off the Smelter's southern wall and
## rounds off the Ammo Press's, both running straight south into the Silo's northern face.
##
## **That makes the Press a three-way branch** — the first Turret off its western wall, the Nest
## off the same wall and the Silo off its southern one — which is the most claimants any Machine
## in this table has ever had on one output.
static func _deep_silo_belts() -> Array:
	return [
		InputAction.build_belt(0, Vector3i(10, GROUND, 7), Vector3i(10, GROUND, 13)),
		InputAction.build_belt(0, Vector3i(9, GROUND, 12), Vector3i(9, GROUND, 13)),
	]


## The long way round: plate off the first Smelter's southern wall, south past the Factory, west
## along z = 18 under the Nest, and back up into the Silo's western wall.
##
## Thirty-five tiles, which is the finding rather than the plumbing: the second ore line this
## replaces costs 20 plate in Machines and four tiles of Belt, so **branching the Smelter is 11
## plate dearer than building a second one** on the geography the Silo is standing on. It is also
## thirty-five tiles of buffer in front of the Ammo Press.
static func _branched_plate_belts() -> Array:
	return [
		InputAction.build_belt(0, Vector3i(10, GROUND, 7), Vector3i(10, GROUND, 17)),
		InputAction.build_belt(0, Vector3i(10, GROUND, 18), Vector3i(-5, GROUND, 18)),
		InputAction.build_belt(0, Vector3i(-6, GROUND, 18), Vector3i(-6, GROUND, 16)),
		InputAction.build_belt(0, Vector3i(-6, GROUND, 15), Vector3i(-2, GROUND, 15)),
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
