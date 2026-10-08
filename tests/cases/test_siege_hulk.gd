## The Siege Hulk and the Hive: the threat the Factory cannot answer, and the reason to
## leave it.
##
## This is the file that stands behind the first-person combat pillar. Everything else in
## this project can be solved by building; a Siege Hulk cannot — it stops beyond every
## Turret's reach and shells what you built from there, so the only answer is a player on
## foot with what the Factory made. A Hive is the standing half of the same argument: it
## sits out on the Map, it pays Heat into the Wave schedule every minute it lives, and it
## stops paying for ever once somebody walks out and kills it.
##
## Everything is asserted through the Simulation façade, which is the only seam.
extends TestCase


# ── Fixtures ──────────────────────────────────────────────────────────────────

## A Map with the Nest at the origin and one Breach far enough east that a Siege Hulk out
## of it has to walk before anything is in shelling range. No Hive, because most of this
## file is about the Hulk and a Hive would be raising Heat underneath it.
func _layout() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(0, WorldGrid.GROUND_LAYER, 0)
	layout.add_breach(Vector3i(36, WorldGrid.GROUND_LAYER, 1))
	layout.sort_breaches()
	return layout


## The same Map with one Hive twelve tiles north of the Nest — close enough that a test can
## walk a player to it, far enough that it is out on the Map rather than in the Factory.
func _hive_layout() -> MapLayout:
	var layout: MapLayout = _layout()
	layout.add_hive(Vector3i(0, WorldGrid.GROUND_LAYER, 12))
	layout.sort_hives()
	return layout


## A Map with a Hive and no Breach at all: the geography a test asks for when it wants to
## watch a Hive's own pressure without a Wave arriving on top of it.
func _hive_only_layout() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(0, WorldGrid.GROUND_LAYER, 0)
	layout.add_hive(Vector3i(0, WorldGrid.GROUND_LAYER, 12))
	layout.sort_hives()
	return layout


## One Siege Hulk a Breach from a cold Factory, and nothing else. The shipped table holds
## it behind 1200 Heat, which is balance rather than anything asserted here.
const ONE_HULK: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
siege_hulks,siege_hulk,0,1,0,1
"""

## One Crawler a Breach, for the tests that want an ordinary Enemy beside the Hulk.
const ONE_CRAWLER: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,1,0,1
"""

## No Wave composition at all — a legal table, and what a test asking only about Hives
## wants.
const NO_WAVE: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,999999999,1,0,1
"""


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	return text


## Shipped content with the Telegraph shortened to half a second, a stock that pays for
## anything and a Delivery chain that locks nothing, so a test can arm a player and build
## without the progression chain being what it is measuring.
func _content(waves: String = ONE_HULK, overrides: Array = []) -> Definitions:
	var tuning: String = _read("res://content/tuning.toml")
	tuning = tuning.replace("telegraph_seconds = 12", "telegraph_seconds = 0.5")
	tuning = tuning.replace(SHIPPED_STOCK, STOCKED)
	for pair: PackedStringArray in overrides:
		var before: String = tuning
		tuning = tuning.replace(pair[0], pair[1])
		assert_true(before != tuning, "the override '%s' matched nothing" % pair[0])
	return Definitions.parse(
		_read("res://content/machines.csv"),
		_read("res://content/recipes.csv"),
		tuning,
		waves,
		DELIVERIES,
		_read("res://content/gear.csv"),
		_read("res://content/stratagems.csv"),
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv",
		"deliveries.csv",
		"gear.csv",
		"stratagems.csv"
	)


## A Run with the Wave already called, so it arrives half a second in rather than two and a
## half minutes in. The lever is the honest way to bring a Wave forward in a test: it is the
## same code path a player uses.
func _sim(
	waves: String = ONE_HULK, overrides: Array = [], layout: MapLayout = null
) -> Simulation:
	var map: MapLayout = layout if layout != null else _layout()
	var sim: Simulation = Simulation.new(7, 1, _content(waves, overrides), map)
	sim.step([InputAction.call_wave_early(0)])
	return sim


## Steps until there is at least one Enemy on the Map, and reports how many ticks it took.
func _step_until_spawned(sim: Simulation) -> int:
	var ticks: int = 0
	while sim.query_enemy_count() == 0 and ticks < 600:
		sim.step([])
		ticks += 1
	return ticks


## Steps until the Hulk has stopped walking, and reports how far from the Nest's centre it
## came to rest, in whole metres.
func _step_until_bombarding(sim: Simulation) -> int:
	var ticks: int = 0
	while not sim.query_enemy_is_bombarding(0) and ticks < 60 * Simulation.TICKS_PER_SECOND:
		sim.step([])
		ticks += 1
	return ticks


# ── The Hulk arrives ──────────────────────────────────────────────────────────

func test_a_siege_hulk_is_one_more_enemy_entry_and_not_an_exception() -> void:
	var sim: Simulation = _sim()
	_step_until_spawned(sim)
	assert_eq(sim.query_enemy_count(), 1, "the Hulk is an Enemy like any other")
	assert_eq(sim.query_enemy_kind(0), Simulation.ENEMY_KIND_SIEGE_HULK)
	assert_eq(sim.query_enemy_serial(0), 0, "carrying an ordinary serial")
	assert_eq(
		sim.query_enemy_tile(0),
		Vector3i(36, WorldGrid.GROUND_LAYER, 1),
		"standing on the Breach it came through"
	)
	assert_eq(sim.query_enemy_health(0), 1800, "siege_hulk.health")


## How far apart two points are, in whole metres. For an assertion about a stand-off, which is
## a distance a player reads off the Map rather than a fixed-point quantity.
func _metres_between(from: FixedVec2, to: FixedVec2) -> int:
	var gap_x: int = to.x - from.x
	var gap_z: int = to.z - from.z
	return Fixed.floor_to_int(Fixed.sqrt(Fixed.mul(gap_x, gap_x) + Fixed.mul(gap_z, gap_z)))


## Where the Nest's footprint centre is, in fixed-point metres. The Nest here covers (0,0) to
## (3,3), so its centre is 4 m along both axes — a worked literal rather than a recomputation of
## what the Simulation does.
func _nest_centre() -> FixedVec2:
	return FixedVec2.new(Fixed.from_int(4), Fixed.from_int(4))


# ── The stand-off ─────────────────────────────────────────────────────────────

func test_a_siege_hulk_walks_in_and_halts_the_moment_it_can_shell_something() -> void:
	var sim: Simulation = _sim()
	_step_until_spawned(sim)
	var arrived: FixedVec2 = sim.query_enemy_position_metres(0)
	assert_eq(_metres_between(_nest_centre(), arrived), 69, "it comes through the Breach at 69 m")
	assert_false(sim.query_enemy_is_bombarding(0), "with nothing yet in reach")

	var walked: int = _step_until_bombarding(sim)
	assert_true(walked > 0, "so it walks: %d ticks" % walked)
	var standing: FixedVec2 = sim.query_enemy_position_metres(0)
	# It stops on the first tick something is inside `siege_hulk.range_metres`, which is 60 — so
	# where it comes to rest *is* the reach and not a second number that could disagree with it.
	# It walks a sixtieth of a metre a tick, so the first tick inside 60 m is a shade under it
	# and floors to 59.
	assert_eq(
		_metres_between(_nest_centre(), standing),
		59,
		"and halts a fraction inside its own shelling reach of 60 m"
	)
	assert_true(sim.query_enemy_is_bombarding(0), "bombarding from there")

	# And it stays there. A siege is a problem to solve rather than a chase: it does not close
	# the distance and it does not wander.
	for i: int in range(20 * Simulation.TICKS_PER_SECOND):
		sim.step([])
	assert_eq(
		sim.query_enemy_position_metres(0).x,
		standing.x,
		"and it is still standing in the same place twenty seconds later"
	)
	assert_eq(sim.query_enemy_position_metres(0).z, standing.z)


func test_where_a_siege_hulk_stands_is_beyond_every_turret_in_the_game() -> void:
	# The acceptance criterion, measured rather than asserted about: the shipped MG Turret
	# reaches 8 tiles and the Repair Pylon 6, and the Hulk stops 60 m out.
	var sim: Simulation = _sim()
	_step_until_spawned(sim)
	_step_until_bombarding(sim)
	var stand_off: int = _metres_between(_nest_centre(), sim.query_enemy_position_metres(0))

	var definitions: Definitions = sim.query_definitions()
	var turrets: int = 0
	for index: int in range(definitions.machine_count()):
		var definition: MachineDefinition = definitions.machine_at(index)
		if not definition.is_turret():
			continue
		turrets += 1
		assert_true(
			definition.range_tiles * WorldGrid.TILE_SIZE_METRES < stand_off,
			(
				"%s reaches %d m against a stand-off of %d m"
				% [definition.id, definition.range_tiles * WorldGrid.TILE_SIZE_METRES, stand_off]
			)
		)
	assert_true(turrets >= 2, "the shipped content has Turrets to be out of reach of")


func test_content_whose_turret_could_reach_the_stand_off_is_refused_by_name() -> void:
	# "It cannot be defeated by Turrets alone" as a content check rather than as a hope about
	# one. A Cannon Turret that outranged the Hulk would quietly turn the one threat the Factory
	# cannot answer into one it can, and that is an edit somebody would make without noticing.
	var machines: String = _read("res://content/machines.csv")
	machines += "zz_siege_cannon_mk1,Siege Cannon,turret,2,2,2,90,0,350,0,40,80,0,0,fire_mg,\n"
	var definitions: Definitions = Definitions.parse(
		machines,
		_read("res://content/recipes.csv"),
		_read("res://content/tuning.toml"),
		_read("res://content/waves.csv"),
		_read("res://content/deliveries.csv"),
		_read("res://content/gear.csv"),
		_read("res://content/stratagems.csv"),
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv",
		"deliveries.csv",
		"gear.csv",
		"stratagems.csv"
	)
	assert_true(definitions.has_errors(), "a Turret that outranges the boss is a content error")
	var text: String = definitions.describe_errors()
	assert_true(text.contains("zz_siege_cannon_mk1"), text)
	assert_true(text.contains("siege_hulk.range_metres"), text)


func test_no_turret_ever_takes_a_shot_at_a_siege_hulk() -> void:
	# A Turret standing in the Factory, a Hulk shelling it from sixty metres, and the Turret
	# with nothing to do for the whole fight. The Turret is deliberately fed and in working
	# order: what stops it is distance, not supply.
	var sim: Simulation = _sim()
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(
			0, definitions.machine_index("mg_turret_mk1"), Vector3i(6, WorldGrid.GROUND_LAYER, 0)
		)
	])
	_step_until_spawned(sim)
	_step_until_bombarding(sim)

	var full: int = sim.query_enemy_health(0)
	for i: int in range(30 * Simulation.TICKS_PER_SECOND):
		sim.step([])
		if sim.query_enemy_count() == 0:
			break
		assert_eq(
			sim.query_turret_target_serial(0),
			-1,
			"the Turret never acquires it"
		)
	assert_eq(sim.query_enemy_health(0), full, "and the Hulk takes nothing off the defences")
	assert_eq(sim.query_turret_last_shot_tick(0), -1, "the Turret never fired a round")


func test_a_turret_pushed_out_to_the_stand_off_makes_a_siege_hulk_back_away() -> void:
	# The behavioural half of the same criterion, for the Turret a player walks out into the
	# field. It withdraws and goes on shelling from further out, rather than letting the Factory
	# quietly solve the one thing it must not.
	var sim: Simulation = _sim()
	_step_until_spawned(sim)
	_step_until_bombarding(sim)
	var held: FixedVec2 = sim.query_enemy_position_metres(0)

	# An MG Turret two tiles from where it is standing, which is well inside its 8-tile reach.
	var tile: Vector3i = sim.query_enemy_tile(0)
	sim.step([
		InputAction.build_machine(
			0,
			sim.query_definitions().machine_index("mg_turret_mk1"),
			Vector3i(tile.x + 2, WorldGrid.GROUND_LAYER, tile.z)
		)
	])
	assert_eq(sim.query_machine_count(), 1, "the Turret is standing beside it")

	for i: int in range(10 * Simulation.TICKS_PER_SECOND):
		sim.step([])
	assert_true(
		_metres_between(_nest_centre(), sim.query_enemy_position_metres(0))
		< _metres_between(_nest_centre(), held),
		"it backed away from the Turret rather than standing to be shot"
	)
	assert_eq(sim.query_turret_last_shot_tick(0), -1, "and the Turret never got a round off")


# ── The bombardment ───────────────────────────────────────────────────────────

func test_a_shell_is_marked_on_the_ground_before_it_lands() -> void:
	# The Telegraph rule, applied to a single shell. Nothing in this project arrives
	# unannounced, so the impact point is on the ground with a countdown — and what is marked is
	# literally where the damage will be rather than an approximation of it.
	var sim: Simulation = _sim()
	_step_until_spawned(sim)
	_step_until_bombarding(sim)

	var ticks: int = 0
	while sim.query_shell_count() == 0 and ticks < 20 * Simulation.TICKS_PER_SECOND:
		sim.step([])
		ticks += 1
	assert_eq(sim.query_shell_count(), 1, "a shell is in the air after %d ticks" % ticks)
	# siege_hulk.shell_flight_seconds is 3, and a shell does not land on the tick it was fired.
	assert_eq(sim.query_shell_ticks_remaining(0), 3 * Simulation.TICKS_PER_SECOND)
	var marked: FixedVec2 = sim.query_shell_impact_metres(0)
	assert_eq(marked.x, _nest_centre().x, "aimed at the only thing in reach, which is the Nest")
	assert_eq(marked.z, _nest_centre().z)
	assert_eq(
		sim.query_shell_blast_radius_metres(),
		Fixed.from_int(6),
		"siege_hulk.shell_blast_radius_metres, so the ring drawn is the blast"
	)

	var whole: int = sim.query_nest_health()
	for i: int in range(3 * Simulation.TICKS_PER_SECOND - 1):
		sim.step([])
		assert_eq(sim.query_nest_health(), whole, "nothing happens there while it is in the air")
	sim.step([])
	assert_eq(sim.query_shell_count(), 0, "and then it lands")
	assert_eq(whole - sim.query_nest_health(), 220, "siege_hulk.shell_damage, off the Nest")


func test_a_siege_hulk_shells_the_factory_in_preference_to_the_nest() -> void:
	# "It damages Machines and the Nest from that range." The Factory first, because a
	# bombardment is for what a player built; the Nest is what is left when there is no Factory.
	var sim: Simulation = _sim()
	var definitions: Definitions = sim.query_definitions()
	# A Smelter out towards the Hulk, so it is the nearest thing it can shell.
	sim.step([
		InputAction.build_machine(
			0, definitions.machine_index("smelter_mk1"), Vector3i(10, WorldGrid.GROUND_LAYER, 0)
		)
	])
	var whole_machine: int = sim.query_definitions().machine("smelter_mk1").health
	_step_until_spawned(sim)
	_step_until_bombarding(sim)

	var whole_nest: int = sim.query_nest_health()
	var landed: int = 0
	for i: int in range(20 * Simulation.TICKS_PER_SECOND):
		var before: int = sim.query_shell_count()
		sim.step([])
		if sim.query_shell_count() < before:
			landed += 1
		if sim.query_machine_count() == 0:
			break
	assert_true(landed > 0, "shells landed: %d" % landed)
	assert_eq(sim.query_nest_health(), whole_nest, "the Nest was not what it shot at")
	if sim.query_machine_count() > 0:
		assert_true(
			sim.query_machine_health(0) < whole_machine,
			"the Smelter took the bombardment instead"
		)
	else:
		assert_eq(sim.query_machine_count(), 0, "and three shells took the Smelter off the Map")


# ── Walking and aiming, for the tests that fight on foot ──────────────────────
#
# Everything here produces ordinary Input Actions and nothing reaches into the Simulation. The
# arithmetic that turns "face that thing" into a count of mouse pixels is float arithmetic, which
# a test is allowed and `sim/` is not: what crosses the boundary is the integer the quantiser
# would have produced, so a script captured from these helpers replays exactly.

## How many pixels of mouse travel turn the view by one whole revolution, at the shipped
## `player.look_sensitivity_turns_per_1000_pixels` of 0.2. A worked literal: 1000 / 0.2.
const PIXELS_PER_TURN: int = 5000


## The `LOOK` that points a player at a place on the ground, as one action.
##
## The Simulation's own convention: at yaw 0 forward is -z, and a positive yaw turns left, so
## the yaw that faces a gap is `atan2(-gap_x, -gap_z)`. Right is a *decrease* in yaw, which is
## why the pixel count is the negative of the turn wanted.
func _look_at(sim: Simulation, from: FixedVec2, to: FixedVec2) -> InputAction:
	var wanted: float = atan2(
		-Fixed.to_float(to.x - from.x), -Fixed.to_float(to.z - from.z)
	) / TAU
	var held: float = Fixed.to_float(sim.query_player_yaw_turns(0))
	var delta: float = fposmod(wanted - held + 0.5, 1.0) - 0.5
	return InputAction.look(0, Fixed.from_int(int(roundf(-delta * PIXELS_PER_TURN))), 0)


## Steps a Run, appending what crossed on every tick to `log`.
##
## **Every tick, including the idle ones**, which is what lets a replay fixture be built out of
## the very sequence a scenario ran on rather than out of a hand-written approximation of it.
## `test_recorded_session` makes the same argument about device readings; this is the same
## discipline applied to a fight.
func _advance(sim: Simulation, log: Array, actions: Array, ticks: int) -> void:
	for i: int in range(ticks):
		log.append(actions)
		sim.step(actions)


## Walks player 0 to within `stop_metres` of a place, turning to face it as they go.
##
## Bounded, like every wait in this suite: an unbounded loop in a test is a hung suite rather
## than a failing one.
func _walk_to(
	sim: Simulation, to: FixedVec2, stop_metres: int, budget: int, log: Array = []
) -> void:
	for i: int in range(budget):
		var here: FixedVec2 = sim.query_player_position(0)
		if _metres_between(here, to) <= stop_metres:
			return
		_advance(
			sim,
			log,
			[
				_look_at(sim, here, to),
				InputAction.move(0, Fixed.ONE, 0),
				InputAction.sprint(0, true)
			],
			1
		)


## Stands player 0 off `stand_metres` beyond an Enemy on the far side from the Nest, which is the
## side a Siege Hulk's armour is not on while it is shelling the Factory.
func _behind(sim: Simulation, enemy: int, stand_metres: int) -> FixedVec2:
	var where: FixedVec2 = sim.query_enemy_position_metres(enemy)
	var facing: FixedVec2 = sim.query_enemy_facing_point_metres(enemy)
	var away_x: float = Fixed.to_float(where.x - facing.x)
	var away_z: float = Fixed.to_float(where.z - facing.z)
	var length: float = sqrt(away_x * away_x + away_z * away_z)
	if length <= 0.0:
		return where
	var reach: float = float(stand_metres) / length * float(Fixed.ONE)
	return FixedVec2.new(
		where.x + int(roundf(away_x * reach)), where.z + int(roundf(away_z * reach))
	)


## Holds the trigger for a number of ticks, aiming at an Enemy every tick.
func _fire_at(sim: Simulation, enemy: int, ticks: int, log: Array = []) -> void:
	for i: int in range(ticks):
		if sim.query_enemy_count() <= enemy:
			return
		_advance(
			sim,
			log,
			[
				_look_at(
					sim, sim.query_player_position(0), sim.query_enemy_position_metres(enemy)
				),
				InputAction.fire(0)
			],
			1
		)


## Puts the Drum Autocannon in player 0's hands. Nothing is fitted to it: the fight below is
## about where a player stands, not about what they bolted on.
func _arm_with_the_autocannon(sim: Simulation) -> void:
	sim.step([InputAction.equip_weapon(0, sim.query_definitions().gear_index("drum_autocannon"))])
	assert_eq(sim.query_player_weapon(0), "drum_autocannon", "the Factory's own weapon")


# ── The weak point ────────────────────────────────────────────────────────────

func test_the_same_weapon_does_six_times_the_damage_from_behind_a_siege_hulk() -> void:
	# **The decision this ticket turned on.** A damage sponge is a timer: more hit points only
	# ever asks a player to hold the trigger for longer, and the answer to the boss would have
	# been "bring more Ammunition" rather than "move". An armoured front gives the fight a shape,
	# and the shape is a flank.
	#
	# The two halves are measured with the identical weapon against the identical Hulk, and the
	# only difference between them is which side of it the player is standing on.
	var front: Simulation = _sim()
	_step_until_spawned(front)
	_step_until_bombarding(front)
	_arm_with_the_autocannon(front)
	var whole: int = front.query_enemy_health(0)
	assert_eq(
		front.query_enemy_frontal_armour_percent(0), 85, "siege_hulk.frontal_armour_percent"
	)

	# Standing between the Hulk and the Nest, which is where a player defending the Factory is.
	_walk_to(front, front.query_enemy_position_metres(0), 8, 60 * Simulation.TICKS_PER_SECOND)
	_fire_at(front, 0, 5 * Simulation.TICKS_PER_SECOND)
	var frontal: int = whole - front.query_enemy_health(0)
	assert_true(frontal > 0, "the rounds landed: %d damage" % frontal)

	var behind: Simulation = _sim()
	_step_until_spawned(behind)
	_step_until_bombarding(behind)
	_arm_with_the_autocannon(behind)
	_walk_to(behind, _behind(behind, 0, 8), 2, 120 * Simulation.TICKS_PER_SECOND)
	_fire_at(behind, 0, 5 * Simulation.TICKS_PER_SECOND)
	var rear: int = whole - behind.query_enemy_health(0)

	# 85% off the front is a shade under seven times, and the two bursts are not identical
	# lengths of fire, so the claim is the order of magnitude rather than an exact ratio.
	assert_true(
		rear > frontal * 4,
		"the same weapon from behind did %d against %d from the front" % [rear, frontal]
	)


func test_a_crawler_carries_no_armour_at_all() -> void:
	# The armour belongs to the boss and to nothing else, which is what keeps "Chaff is one-hit"
	# true arithmetically rather than only in prose.
	var sim: Simulation = _sim(ONE_CRAWLER)
	_step_until_spawned(sim)
	assert_eq(sim.query_enemy_kind(0), Simulation.ENEMY_KIND_CRAWLER)
	assert_eq(sim.query_enemy_frontal_armour_percent(0), 0)


# ── Killing it on foot ────────────────────────────────────────────────────────

func test_a_siege_hulk_can_be_killed_on_foot_with_what_the_factory_made() -> void:
	# **The pillar's whole sentence as one test.** Nothing the Factory can build stops this
	# thing; a player with the weapon the Factory armed them with, standing on the right side of
	# it, does.
	var sim: Simulation = _sim()
	_step_until_spawned(sim)
	_step_until_bombarding(sim)
	_arm_with_the_autocannon(sim)
	var rounds: int = sim.query_player_ammunition(0)
	assert_true(rounds > 0, "carrying Ammunition the Factory made")

	_walk_to(sim, _behind(sim, 0, 8), 2, 120 * Simulation.TICKS_PER_SECOND)
	for burst: int in range(12):
		if sim.query_enemy_count() == 0:
			break
		_fire_at(sim, 0, 5 * Simulation.TICKS_PER_SECOND)
		# Keep flanking it: a Hulk turns to face whatever it is shelling, and if it has turned
		# on the player the rounds stop telling.
		if sim.query_enemy_count() > 0:
			_walk_to(sim, _behind(sim, 0, 8), 2, 10 * Simulation.TICKS_PER_SECOND)
	assert_eq(sim.query_enemy_count(), 0, "the Siege Hulk is dead")
	assert_true(
		sim.query_player_ammunition(0) < rounds,
		"and it cost the Factory's Ammunition to do it"
	)
	assert_true(sim.query_player_is_alive(0), "the player who did it is still standing")


func test_standing_at_a_siege_hulks_feet_stops_the_bombardment() -> void:
	# A stomp and a shell share one cooldown, so closing the distance is worth something from the
	# first second rather than only at the end: a player standing there is a player whose Factory
	# is not being shelled. The same trade standing in a doorway makes against a Crawler, at the
	# same price — your own skin.
	var sim: Simulation = _sim()
	_step_until_spawned(sim)
	_step_until_bombarding(sim)

	# The walk out there costs the Factory shells, which is the honest price of the sortie and
	# the reason the reading that matters is taken once the player has arrived.
	_walk_to(sim, sim.query_enemy_position_metres(0), 2, 120 * Simulation.TICKS_PER_SECOND)
	assert_false(
		sim.query_enemy_is_bombarding(0), "with somebody at its feet it is not shelling anything"
	)
	# Let whatever was already in the air come down — a shell in flight is damage that has
	# already been decided, and standing at its feet does not call it back.
	for i: int in range(3 * Simulation.TICKS_PER_SECOND):
		sim.step([])
	assert_eq(sim.query_shell_count(), 0, "the last shell has landed")

	var whole: int = sim.query_nest_health()
	var health: int = sim.query_player_health(0)
	# Standing still, which is what the trade costs: no walking, no building, no wrench.
	for i: int in range(20 * Simulation.TICKS_PER_SECOND):
		sim.step([])
		assert_eq(sim.query_shell_count(), 0, "it put nothing in the air while they stood there")
	assert_true(
		sim.query_player_health(0) < health,
		"it stomped the player instead: %d hit points" % [health - sim.query_player_health(0)]
	)
	assert_eq(sim.query_nest_health(), whole, "and the Nest was left alone the whole time")


# ── The Hives ─────────────────────────────────────────────────────────────────

func test_the_shipped_map_carries_hives_out_on_it() -> void:
	var sim: Simulation = Simulation.new(3, 1, null, MapLayout.starter())
	assert_eq(sim.query_hive_count(), 2, "two Hives, in opposite directions")
	assert_eq(sim.query_hive_health(0), 1200, "hive.health")
	assert_eq(sim.query_hive_max_health(), 1200)
	# Far enough that reaching one is a sortie rather than a stroll, and nowhere near the ground
	# the opening Factory wants.
	for index: int in range(sim.query_hive_count()):
		var centre: FixedVec2 = WorldGrid.tile_centre_metres(sim.query_hive_tile(index))
		assert_true(
			_metres_between(centre, sim.query_player_position(0)) > 80,
			"Hive %d is %d m out" % [index, _metres_between(centre, sim.query_player_position(0))]
		)


func test_a_standing_hive_is_heat_the_nest_cannot_hide() -> void:
	# **How a Hive applies pressure, and the decision behind it.** A Hive sends nothing out: a
	# Breach is "known in advance and fortifiable" (GLOSSARY.md), and a Hive that emitted its own
	# Enemies would be a second entry point nobody can fortify. So its pressure goes through the
	# Breaches that already exist, by making the Factory louder than it is — it subtracts from
	# what the Nest sheds rather than adding to Heat, so an idle Run is still owed its silence.
	var quiet: Simulation = Simulation.new(3, 1, _content(NO_WAVE), _layout())
	var watched: Simulation = Simulation.new(3, 1, _content(NO_WAVE), _hive_layout())

	assert_eq(quiet.query_hive_count(), 0, "one Map with no Hive on it")
	assert_eq(watched.query_hive_count(), 1, "and one with a Hive")
	assert_eq(quiet.query_heat_decay_per_minute(), 240, "heat.decay_per_minute")
	assert_eq(
		watched.query_heat_decay_per_minute(),
		210,
		"less hive.heat_shadow_per_minute for the one standing"
	)
	assert_eq(
		watched.query_hive_heat_shadow_per_minute(), 30, "which is the bill, stated as a bill"
	)

	# And a Factory producing nothing is still silent on both Maps. A Hive taxes growth; it does
	# not hunt a Run for standing still.
	for i: int in range(2 * Simulation.TICKS_PER_MINUTE):
		quiet.step([])
		watched.step([])
	assert_eq(quiet.query_heat(), 0, "an idle Factory makes no Heat")
	assert_eq(watched.query_heat(), 0, "and a Hive does not make it for them")


func test_destroying_a_hive_hands_the_pressure_back_for_good() -> void:
	var sim: Simulation = Simulation.new(3, 1, _content(NO_WAVE), _hive_layout())
	assert_eq(sim.query_heat_decay_per_minute(), 210, "a Hive is standing")
	_arm_with_the_autocannon(sim)

	var centre: FixedVec2 = WorldGrid.tile_centre_metres(sim.query_hive_tile(0))
	_walk_to(sim, centre, 10, 60 * Simulation.TICKS_PER_SECOND)
	var whole: int = sim.query_hive_health(0)
	for burst: int in range(8):
		if sim.query_hive_count() == 0:
			break
		for i: int in range(5 * Simulation.TICKS_PER_SECOND):
			sim.step([
				_look_at(sim, sim.query_player_position(0), centre), InputAction.fire(0)
			])
	assert_true(whole > 0, "it had hit points to take off")
	assert_eq(sim.query_hive_count(), 0, "the Hive is destroyed")
	assert_eq(
		sim.query_heat_decay_per_minute(),
		240,
		"and the Nest hides everything it ever could again"
	)
	assert_eq(sim.query_hive_heat_shadow_per_minute(), 0, "with no bill left to pay")

	# Permanently. There is nowhere in the Simulation that puts a Hive back, and a long Run
	# proves the absence of one better than reading the code does.
	for i: int in range(5 * Simulation.TICKS_PER_MINUTE):
		sim.step([])
	assert_eq(sim.query_hive_count(), 0, "five minutes later it has not come back")
	assert_eq(sim.query_heat_decay_per_minute(), 240)


func test_a_turret_cannot_touch_a_hive_however_far_out_it_is_belted() -> void:
	# The cheese this closes, and it closes by construction rather than by a rule: a Turret
	# acquires Enemies, and a Hive is a structure rather than an Enemy. So a player who runs a
	# fifty-tile Belt out to a Hive has built a Turret with nothing to shoot — "requires leaving
	# the Factory" survives the most determined attempt to build its way out of it.
	var sim: Simulation = Simulation.new(3, 1, _content(NO_WAVE), _hive_layout())
	var tile: Vector3i = sim.query_hive_tile(0)
	sim.step([
		InputAction.build_machine(
			0,
			sim.query_definitions().machine_index("mg_turret_mk1"),
			Vector3i(tile.x + 2, WorldGrid.GROUND_LAYER, tile.z)
		)
	])
	assert_eq(sim.query_machine_count(), 1, "an MG Turret two tiles from the Hive")

	for i: int in range(30 * Simulation.TICKS_PER_SECOND):
		sim.step([])
	assert_eq(sim.query_turret_target_serial(0), -1, "it never acquires the Hive")
	assert_eq(sim.query_turret_last_shot_tick(0), -1, "and never fires at it")
	assert_eq(sim.query_hive_health(0), 1200, "the Hive is untouched")


# ── State, saved and hashed ───────────────────────────────────────────────────

func test_a_siege_hulk_mid_bombardment_is_part_of_the_state_hash() -> void:
	var sim: Simulation = _sim()
	_step_until_spawned(sim)
	_step_until_bombarding(sim)
	var ticks: int = 0
	while sim.query_shell_count() == 0 and ticks < 20 * Simulation.TICKS_PER_SECOND:
		sim.step([])
		ticks += 1
	assert_eq(sim.query_shell_count(), 1, "a shell is in the air")

	var flying: int = sim.hash()
	sim.step([])
	assert_ne(flying, sim.hash(), "a shell one tick closer is a Simulation in a different state")


func test_a_run_mid_bombardment_saves_and_resumes_identically() -> void:
	var content: Definitions = _content()
	var sim: Simulation = Simulation.new(7, 1, content, _hive_layout())
	sim.step([InputAction.call_wave_early(0)])
	_step_until_spawned(sim)
	_step_until_bombarding(sim)
	var ticks: int = 0
	while sim.query_shell_count() == 0 and ticks < 30 * Simulation.TICKS_PER_SECOND:
		sim.step([])
		ticks += 1
	assert_eq(sim.query_shell_count(), 1, "with a shell in the air and a Hive standing")
	assert_eq(sim.query_hive_count(), 1)

	var restored: Simulation = RunSave.deserialise(
		RunSave.serialise(sim), content, Simulation.new(0, 1, content, MapLayout.empty())
	).simulation
	if not assert_not_null(restored, "the save read back"):
		return
	assert_eq(restored.hash(), sim.hash(), "to the integer it hashed to before")
	assert_eq(restored.query_shell_count(), 1, "with the shell still in the air")
	assert_eq(
		restored.query_shell_ticks_remaining(0),
		sim.query_shell_ticks_remaining(0),
		"the same number of ticks from landing"
	)
	assert_eq(restored.query_hive_count(), 1, "and the Hive still standing")
	assert_eq(
		restored.query_heat_decay_per_minute(),
		sim.query_heat_decay_per_minute(),
		"shadowing exactly as much of the Nest's shedding as it was"
	)
	assert_eq(
		restored.query_enemy_facing_point_metres(0).x,
		sim.query_enemy_facing_point_metres(0).x,
		"and the Hulk facing the same way, which is what its armour is measured against"
	)

	# And the two Runs go on agreeing, which is the only test of a restored fight that matters.
	for i: int in range(20 * Simulation.TICKS_PER_SECOND):
		sim.step([])
		restored.step([])
		assert_eq(restored.hash(), sim.hash(), "diverged at tick %d" % sim.query_tick())


# ── Replay fixtures ───────────────────────────────────────────────────────────
#
# Both are built out of the ticks the scenario really ran on: a live Run is driven, every tick's
# Input Actions are captured, and the captured script is what the harness replays. A fixture
# written as a hand-made guess at the sequence would prove determinism over a Run nobody checked.
#
# Both pass their `Definitions` to `record`, because the scenarios need content the shipped files
# do not have — a Siege Hulk from the first Wave of a cold Factory, and a player carrying the
# Ammunition to finish a Hive. The Map is the shipped one either way, which is where the Hives
# are.

## Shipped content with the Siege Hulk brought to the front of the Wave table, the Telegraph
## shortened, and a player carrying enough to finish a fight. The Map is left alone.
func _fixture_content(waves: String = ONE_HULK) -> Definitions:
	return _content(waves)


## Drives a Run through a whole sortie against a Siege Hulk and reports the script it took:
## call the Wave, wait for the Hulk to take up its stand-off, walk round behind it and shoot it
## until it falls.
func _hulk_sortie(sim: Simulation, log: Array) -> void:
	_advance(sim, log, [InputAction.call_wave_early(0)], 1)
	while sim.query_enemy_count() == 0 and log.size() < 10 * Simulation.TICKS_PER_SECOND:
		_advance(sim, log, [], 1)
	while not sim.query_enemy_is_bombarding(0) and log.size() < 90 * Simulation.TICKS_PER_SECOND:
		_advance(sim, log, [], 1)
	_advance(
		sim, log, [InputAction.equip_weapon(0, sim.query_definitions().gear_index("drum_autocannon"))], 1
	)
	for burst: int in range(14):
		if sim.query_enemy_count() == 0:
			break
		_walk_to(sim, _behind(sim, 0, 8), 2, 30 * Simulation.TICKS_PER_SECOND, log)
		_fire_at(sim, 0, 5 * Simulation.TICKS_PER_SECOND, log)


## Drives a Run out to the first Hive on the shipped Map and shoots it down.
func _hive_sortie(sim: Simulation, log: Array) -> void:
	_advance(
		sim, log, [InputAction.equip_weapon(0, sim.query_definitions().gear_index("drum_autocannon"))], 1
	)
	var centre: FixedVec2 = WorldGrid.tile_centre_metres(sim.query_hive_tile(0))
	_walk_to(sim, centre, 10, 60 * Simulation.TICKS_PER_SECOND, log)
	# The aim is recomputed **every tick**, the same shape `_fire_at` has, rather than once
	# per burst and then repeated. A `LOOK` intent is a count of pixels of mouse travel, so
	# one held for a hundred and twenty ticks turns the view a hundred and twenty times —
	# which only aimed at the Hive at all while the walk happened to leave the player's yaw
	# already on it and the rounded delta at zero. #29 moved where that walk stops (sprint
	# ramps in now, so the tick the player comes inside ten metres is a different tick) and
	# the burst then spun the view off the target. Per tick converges instead of diverging.
	for tick: int in range(20 * Simulation.TICKS_PER_SECOND):
		if sim.query_hive_count() == 0:
			break
		_advance(
			sim,
			log,
			[_look_at(sim, sim.query_player_position(0), centre), InputAction.fire(0)],
			1
		)


func _script_of(log: Array) -> InputScript:
	var script: InputScript = InputScript.new()
	for actions: Array in log:
		script.add_tick(actions)
	return script


func test_determinism_a_siege_hulk_bombarding_and_being_killed_on_foot_replays_identically() -> void:
	var content: Definitions = _fixture_content()
	var log: Array = []
	_hulk_sortie(Simulation.new(7, 1, content), log)
	assert_true(log.size() > 0, "the sortie took %d ticks" % log.size())

	var recording: ReplayRecording = DeterminismHarness.record(_script_of(log), 7, 1, content)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_the_hulk_fixture_really_did_shell_the_factory_and_die_on_foot() -> void:
	# A fixture proving determinism over a Run in which the Hulk was never shot would prove
	# nothing, so the scenario is checked separately from the replay, on the same seed and Map.
	var sim: Simulation = Simulation.new(7, 1, _fixture_content())
	var log: Array = []
	var whole: int = sim.query_nest_health()
	_hulk_sortie(sim, log)

	assert_eq(sim.query_enemy_count(), 0, "the Siege Hulk is dead")
	assert_true(
		sim.query_nest_health() < whole,
		"and it shelled the Factory on the way: %d hit points" % [whole - sim.query_nest_health()]
	)
	assert_true(
		Fixed.floor_to_int(sim.query_player_metres_from_the_nest(0)) > 20,
		"killed on foot, out on the Map rather than from the doorstep"
	)


func test_determinism_a_hive_destroyed_on_foot_replays_identically() -> void:
	var content: Definitions = _fixture_content(NO_WAVE)
	var log: Array = []
	_hive_sortie(Simulation.new(9, 1, content), log)
	assert_true(log.size() > 0, "the sortie took %d ticks" % log.size())

	var recording: ReplayRecording = DeterminismHarness.record(_script_of(log), 9, 1, content)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_the_hive_fixture_really_did_destroy_a_hive_and_win_the_heat_back() -> void:
	var sim: Simulation = Simulation.new(9, 1, _fixture_content(NO_WAVE))
	assert_eq(sim.query_hive_count(), 2, "the shipped Map's two Hives")
	var shadowed: int = sim.query_heat_decay_per_minute()

	var log: Array = []
	_hive_sortie(sim, log)
	assert_eq(sim.query_hive_count(), 1, "one Hive down and one still standing")
	assert_true(
		sim.query_heat_decay_per_minute() > shadowed,
		"and the Nest hides more than it did: %d against %d"
		% [sim.query_heat_decay_per_minute(), shadowed]
	)
	assert_eq(
		sim.query_hive_heat_shadow_per_minute(), 30, "with one Hive's worth of bill left to pay"
	)


# ── What leaving the Factory costs, as something a player can read ────────────

func test_the_bill_for_leaving_is_readable_before_the_player_commits() -> void:
	# A sortie has to be a decision made knowingly, which means the cost has to be on screen
	# *before* the walk rather than discovered on the way back. All three numbers the HUD shows
	# are pure projections, so asking for them cannot move the Run.
	var sim: Simulation = Simulation.new(7, 1, _content(), _hive_layout())
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(
			0, definitions.machine_index("smelter_mk1"), Vector3i(10, WorldGrid.GROUND_LAYER, 0)
		)
	])
	assert_eq(sim.query_machines_damaged(), 0, "nothing is hurt yet")
	assert_eq(sim.query_hive_heat_shadow_per_minute(), 30, "one Hive is costing this much")
	assert_eq(
		Fixed.floor_to_int(sim.query_player_metres_from_the_nest(0)),
		5,
		"and the player is at home — five metres from the middle of the Nest"
	)

	sim.step([InputAction.call_wave_early(0)])
	_step_until_spawned(sim)
	_step_until_bombarding(sim)
	var before: int = sim.hash()
	assert_eq(sim.query_machines_damaged(), 0, "asking the question changes nothing")
	assert_eq(sim.hash(), before, "and leaves the hash exactly where it was")

	var ticks: int = 0
	while sim.query_machines_damaged() == 0 and ticks < 30 * Simulation.TICKS_PER_SECOND:
		sim.step([])
		ticks += 1
	assert_eq(sim.query_machines_damaged(), 1, "the bombardment hurt the Smelter")

	_walk_to(sim, sim.query_enemy_position_metres(0), 4, 90 * Simulation.TICKS_PER_SECOND)
	var out: int = Fixed.floor_to_int(sim.query_player_metres_from_the_nest(0))
	assert_true(out > 40, "and the player who went out to answer it is %d m from a wrench" % out)


# ── Fixtures that keep progression out of the way ─────────────────────────────

const SHIPPED_STOCK: String = 'starting_stock = "iron_plate:110"'
const STOCKED: String = 'starting_stock = "ammunition:4000;coal:400;iron_ore:400;iron_plate:400"'

const DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_opening,Opening Licence,1,iron_plate:1,,reflex_sight,
"""
