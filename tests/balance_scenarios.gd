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

## How many of a Factory's own pixels of mouse travel make one whole turn, at the shipped
## `player.look_sensitivity_turns_per_1000_pixels`. Derived rather than written down, so a
## sensitivity change re-aims the sorties instead of silently sending them past the Hive.
const LOOK_PIXELS_PER_TURN: int = 1000 * 10 / 2

## How finely `_look_pixels_towards` searches for a heading: 4096 steps of a turn, which is
## about five arc-minutes. Over the longest leg of the sortie to the eastern Hive — 56 m, from
## `SORTIE_WAYPOINT` — that is under 9 cm of drift, well inside the Wrench's 4 m reach.
const HEADING_STEPS: int = 4096


## Every scenario, in report order: least built to most built, then the two sorties.
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
	# And the coal line comes back up at three minutes, because a Belt into the Nest banks the
	# surplus **for ever**: `t01_munitions` wants 20 coal and the store will then take 200
	# more, so a coal Belt nobody tears down keeps the Boiler short for the rest of the Run.
	# Tearing it down once the tier is paid is the decision this models, and the Power trace
	# in the report is what says whether it was made in time.
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
## Press has room for two entries along its eastern wall. So the Press alternates between the
## two lines, which is the arithmetic `fortified` is built to expose — a second Turret does
## not come with a second Press.
static func _factory_turret_belts() -> Array:
	return [
		InputAction.build_belt(0, Vector3i(10, GROUND, 9), Vector3i(11, GROUND, 9)),
		InputAction.build_belt(0, Vector3i(12, GROUND, 9), Vector3i(12, GROUND, 8)),
	]


## Coal from the coal Miner's northern face, out around the north of the Factory and down to
## the Nest's eastern wall. This is what pays `t01_munitions`, which wants 20 coal.
##
## It takes coal the Boiler would otherwise have burned — the Miner alternates between the
## two Belts — so Power sags while the tier is open and recovers the moment it closes and the
## Nest stops wanting coal. That sag is a real cost of progression and the report shows it.
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
static func _ammunition_belts_to_the_nest() -> Array:
	return [
		InputAction.build_belt(0, Vector3i(7, GROUND, 11), Vector3i(0, GROUND, 11)),
		InputAction.build_belt(0, Vector3i(-1, GROUND, 11), Vector3i(-1, GROUND, -2)),
		InputAction.build_belt(0, Vector3i(-1, GROUND, -3), Vector3i(-2, GROUND, -3)),
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
