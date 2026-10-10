## What `game/combat_events.gd` reports, and the one thing no query can.
##
## #69. Where a round went and what it struck is known inside `_fight` and `_fire` and told to
## nobody: `query_enemy_health` reports a *condition* and a round landing is a *change*. This
## is `game/audio_director.gd`'s own design pointed at the picture instead of the sound, and it
## is asserted here for the same reason the cue list is — a diff with no device attached is a
## cheap assertion, where a tracer is something only a render could catch.
extends TestCase


## Content that puts Ammunition in a Turret without the three-stage chain in the way: a Miner
## whose Node yields Ammunition directly, feeding the shipped MG Turret by one Belt.
##
## Deliberately the arrangement `test_turrets._ammo_fixture` already uses, down to the tiles.
## That file is the authority on how a Turret comes to fire at all; this one is about what is
## reported when it does, and a second opinion about the former would be a fixture asserting
## the wrong thing. Power is left out of it so a brownout cannot be mistaken for a Turret that
## chose not to shoot.
const SHOOTING_MACHINES: String = """id,display_name,role,footprint_x,footprint_z,height_metres,power_draw_kw,power_supply_kw,health,max_depth,range_tiles,damage,repair,charge_capacity,recipe_id,build_cost
ammo_source_mk1,Ammunition Seam,miner,2,2,2,0,0,400,1,0,0,0,0,dig_ammunition,
mg_turret_mk1,MG Turret Mk1,turret,2,2,2,0,0,350,0,8,15,0,0,fire_mg,
"""

const SHOOTING_RECIPES: String = """id,display_name,inputs,outputs,seconds
dig_ammunition,Dig Ammunition,,ammunition:1,0.25
fire_mg,Fire MG,ammunition:1,,0.25
"""

## One Crawler a Breach and never any more however hot the Factory gets. The subject here is
## one round reaching one Crawler, and a swarm would only make it harder to read which.
const ONE_CRAWLER: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,1,0,1
"""

const GEAR: String = """id,display_name,kind,attack,damage,range_metres,spread_degrees,seconds_per_shot,ammunition_item,ammunition_per_shot,damage_percent,range_percent,spread_percent,interval_percent,ammunition_percent,damage_taken_percent
pneumatic_wrench,Pneumatic Wrench,weapon,melee,55,4,0,0.6,,0,0,0,0,0,0,0
placeholder_gear,Placeholder Barrel,barrel,,0,0,0,0,,0,10,0,0,0,0,0
"""

const STRATAGEMS: String = """id,display_name,effect,paint_seconds,radius_tiles,damage_per_charge,goods_per_charge,sentry_machine,sentry_seconds
artillery_barrage,Artillery Barrage,barrage,5,6,150,,,0
"""

const DELIVERIES: String = (
	"id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems\n"
	+ "t01_rounds,Rounds,1,ammunition:1,,placeholder_gear,\n"
)


func _layout() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(0, WorldGrid.GROUND_LAYER, 0)
	layout.add_node(Vector3i(8, WorldGrid.GROUND_LAYER, 6), "ammunition", 1)
	layout.sort_nodes()
	layout.add_breach(Vector3i(20, WorldGrid.GROUND_LAYER, 1))
	layout.sort_breaches()
	return layout


## A Run with one fed MG Turret in the lane and one Crawler walking into it. The Turret is
## built first, so machine 0 is the Turret in every assertion below.
func _firing_turret_sim() -> Simulation:
	var fixture: ContentFixture = ContentFixture.for_case(self)
	fixture.machines = SHOOTING_MACHINES
	fixture.recipes = SHOOTING_RECIPES
	fixture.waves = ONE_CRAWLER
	fixture.deliveries = DELIVERIES
	fixture.gear = GEAR
	fixture.stratagems = STRATAGEMS
	var definitions: Definitions = (
		fixture
		. tune([["telegraph_seconds = 12", "telegraph_seconds = 2"]])
		. stock("")
		. starting_machine("ammo_source_mk1")
		. definitions()
	)
	assert_false(definitions.has_errors(), definitions.describe_errors())
	var sim: Simulation = Simulation.new(1, 1, definitions, _layout())
	sim.step([
		InputAction.build_machine(
			0, definitions.machine_index("mg_turret_mk1"), Vector3i(8, WorldGrid.GROUND_LAYER, 0)
		),
		InputAction.build_machine(
			0,
			definitions.machine_index("ammo_source_mk1"),
			Vector3i(8, WorldGrid.GROUND_LAYER, 6)
		),
		InputAction.build_belt(
			0,
			Vector3i(8, WorldGrid.GROUND_LAYER, 5),
			Vector3i(8, WorldGrid.GROUND_LAYER, 2)
		),
		InputAction.call_wave_early(0),
	])
	return sim


## Steps the Run one tick at a time with the events watching, until one is reported or the
## bound runs out. Bounded, like every wait in this suite: an unbounded `while` is a hung
## suite rather than a failing one.
func _watch_until_something_happens(
	sim: Simulation, events: CombatEvents, bound: int = 1800
) -> Array:
	var waited: int = 0
	events.observe(sim)
	while waited < bound:
		sim.step([])
		waited += 1
		events.observe(sim)
		var reported: Array = events.events()
		if not reported.is_empty():
			return reported
	return []


func test_a_turret_round_that_lands_is_reported_with_what_it_struck() -> void:
	# The fact `_fire` knows and tells nobody. A Crawler's health going down is the only
	# evidence outside the façade that a round arrived, and it is evidence a single query
	# cannot carry, because a query reports what the health *is*.
	var sim: Simulation = _firing_turret_sim()
	var events: CombatEvents = CombatEvents.new()
	var reported: Array = _watch_until_something_happens(sim, events)
	if not assert_false(reported.is_empty(), "the premise: the Turret hits the Crawler"):
		return

	var first: CombatEvents.Event = reported[0]
	assert_eq(first.kind, CombatEvents.Kind.HIT, "a Crawler that lost health was hit")
	assert_true(first.points > 0, "and the round took something off it: %d" % first.points)
	assert_eq(
		first.serial,
		sim.query_enemy_serial(0),
		"and it names the Crawler by the handle that outlives an index"
	)
	# The 2x2 Turret at (8,0,0) is centred on (18 m, 2 m) and reaches 16 m, so the Crawler it
	# hit is somewhere inside that circle rather than at the Breach forty metres out.
	assert_true(
		Vector2(first.at.x, first.at.z).distance_to(Vector2(18.0, 2.0)) <= 16.0,
		"and says where, which is inside the Turret's reach: %s" % first.at
	)
	assert_eq(first.from, CombatEvents.From.TURRET, "fired by a Turret")
	assert_eq(first.from_index, 0, "and by the one standing in the lane")


func test_a_kill_is_reported_where_the_body_last_stood() -> void:
	# The fact no query can answer at any price. `_fire` removes an Enemy it reduced to
	# nothing in the same tick, so by the time anything outside the façade can look there is
	# no serial to resolve, no position to read and no health to compare — only an absence
	# from a set that otherwise grows by appending. Last frame's snapshot is the whole of the
	# evidence, which is why this file holds one.
	var sim: Simulation = _firing_turret_sim()
	var events: CombatEvents = CombatEvents.new()
	var killed: CombatEvents.Event = null
	var waited: int = 0
	events.observe(sim)
	var standing: Vector3 = Vector3.ZERO
	while waited < 1800 and killed == null:
		if sim.query_enemy_count() > 0:
			standing = Vector3(
				Fixed.to_float(sim.query_enemy_position_metres(0).x),
				0.0,
				Fixed.to_float(sim.query_enemy_position_metres(0).z)
			)
		sim.step([])
		waited += 1
		events.observe(sim)
		for event: CombatEvents.Event in events.events():
			if event.kind == CombatEvents.Kind.KILLED:
				killed = event
				break
	if not assert_not_null(killed, "the premise: the Turret kills the Crawler"):
		return

	assert_eq(sim.query_enemy_count(), 0, "and there is nothing left on the Map to ask")
	assert_eq(
		sim.query_enemy_index_of_serial(killed.serial),
		-1,
		"the serial resolves to nothing, which is exactly why this had to be remembered"
	)
	assert_true(
		Vector2(killed.at.x, killed.at.z).distance_to(Vector2(standing.x, standing.z)) < 0.5,
		"and it is reported at %s, where the body was last seen at %s" % [killed.at, standing]
	)
	assert_eq(killed.from, CombatEvents.From.TURRET, "credited to the gun that finished it")
	assert_eq(
		killed.from_index,
		0,
		"which only last frame's target serial could say, because the shot cleared its own"
	)


func test_asking_what_happened_leaves_the_run_exactly_where_it_was() -> void:
	# The rule every projection in this project obeys, asserted the way `test_game_audio`
	# asserts it: the same ticks with and without something watching leave the same state
	# hash. A diff that moved the Run it is describing would be the Godot layer holding
	# authoritative state, which ADR 0001 forbids outright.
	var watched: Simulation = _firing_turret_sim()
	var alone: Simulation = _firing_turret_sim()
	var events: CombatEvents = CombatEvents.new()
	events.observe(watched)
	var reported: int = 0
	for tick: int in range(400):
		watched.step([])
		alone.step([])
		events.observe(watched)
		reported += events.events().size()
	assert_true(reported > 0, "the premise: there was something to watch")
	assert_eq(
		watched.hash(),
		alone.hash(),
		"and watching it cost the Run nothing"
	)


func test_a_frame_that_stepped_nothing_reports_what_it_reported_before_and_not_twice() -> void:
	# Both halves matter and they pull in opposite directions. A second observation on the
	# same tick must not re-diff and double a hit — the snapshot has already moved on — and it
	# must not forget one either, or a mark would flicker out on any frame the Simulation did
	# not advance. `_observed_tick` is what makes it a no-op in both directions.
	var sim: Simulation = _firing_turret_sim()
	var events: CombatEvents = CombatEvents.new()
	var reported: Array = _watch_until_something_happens(sim, events)
	if not assert_false(reported.is_empty(), "the premise: something happened"):
		return

	var before: int = events.events().size()
	events.observe(sim)
	assert_eq(events.events().size(), before, "no second copy of a hit that happened once")
	events.observe(sim)
	assert_eq(events.events().size(), before, "and it is still there to be drawn")


func test_the_first_look_at_a_run_reports_nothing_that_was_already_standing() -> void:
	# A Simulation resumed from a save is a Simulation with a Wave already on the Map, and the
	# first observation of one has nothing to diff against. Reporting then would read as every
	# Enemy alive having just been hit — so the first observation establishes the snapshot and
	# says nothing, which is the same rule `AudioDirector` keeps for the frame it is attached.
	var sim: Simulation = _firing_turret_sim()
	for tick: int in range(5 * Simulation.TICKS_PER_SECOND):
		sim.step([])
	if not assert_true(sim.query_enemy_count() > 0, "the premise: a Crawler is already out"):
		return

	var events: CombatEvents = CombatEvents.new()
	events.observe(sim)
	assert_true(events.events().is_empty(), "nothing has happened since it started watching")


# ── A player's own round ──────────────────────────────────────────────────────

## A rifle and a wrench, so the one test about a shot and the one about a swing can share a
## fixture. `heavy_barrel` is there because the Delivery tier below has to unlock something.
const ARMED_GEAR: String = """id,display_name,kind,attack,damage,range_metres,spread_degrees,seconds_per_shot,ammunition_item,ammunition_per_shot,damage_percent,range_percent,spread_percent,interval_percent,ammunition_percent,damage_taken_percent
bolt_rifle,Bolt Rifle,weapon,ranged,30,60,0,1,ammunition,1,0,0,0,0,0,0
pneumatic_wrench,Pneumatic Wrench,weapon,melee,50,4,0,0.5,,0,0,0,0,0,0,0
heavy_barrel,Heavy Barrel,barrel,,0,0,0,0,,0,100,50,0,100,100,0
"""

const ARMED_DELIVERIES: String = (
	"id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems\n"
	+ "t01_rounds,Rounds,1,ammunition:1,,heavy_barrel,\n"
)

const ONE_BREAKER: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
shock_breakers,breaker,0,1,0,1
"""

## `test_gear`'s own arithmetic, and the comment there is the authority on it: tile (4,-5) puts
## the Enemy at (9, -9) metres, exactly forty-five degrees to the right of a player who has not
## turned, and 625 pixels is exactly an eighth of a turn at the shipped sensitivity. So the aim
## here is exact arithmetic rather than a number somebody nudged until it passed.
const DIAGONAL_BREACH: Vector3i = Vector3i(4, 0, -5)
const FORTY_FIVE_DEGREES_RIGHT: int = 625


## A Run with a Breaker frozen forty-five degrees off the player's opening facing, and a Bolt
## Rifle with rounds in the pockets. A Breaker rather than a Crawler because a Crawler dies to
## one rifle round, and what is wanted here is a hit that leaves something standing.
func _rifleman_sim() -> Simulation:
	var fixture: ContentFixture = ContentFixture.for_case(self)
	fixture.machines = SHOOTING_MACHINES
	fixture.recipes = SHOOTING_RECIPES
	fixture.waves = ONE_BREAKER
	fixture.deliveries = ARMED_DELIVERIES
	fixture.gear = ARMED_GEAR
	fixture.stratagems = STRATAGEMS
	var definitions: Definitions = (
		fixture
		. tune([
			["telegraph_seconds = 12", "telegraph_seconds = 0.5"],
			["breaker_speed_metres_per_second = 2", "breaker_speed_metres_per_second = 0.02"],
		])
		. stock("ammunition:400")
		. starting_machine("ammo_source_mk1")
		. definitions()
	)
	assert_false(definitions.has_errors(), definitions.describe_errors())
	var layout: MapLayout = MapLayout.new()
	# The Nest far to the south-west, so the ground around the player is open and the Breaker
	# walks nowhere near it in the half-second this takes.
	layout.nest_tile = Vector3i(-30, WorldGrid.GROUND_LAYER, -30)
	layout.add_node(Vector3i(8, WorldGrid.GROUND_LAYER, 6), "ammunition", 1)
	layout.sort_nodes()
	layout.add_breach(DIAGONAL_BREACH)
	layout.sort_breaches()
	var sim: Simulation = Simulation.new(11, 1, definitions, layout)
	sim.step([InputAction.call_wave_early(0)])
	return sim


## Steps until the Wave is out, puts the named weapon in the player's hands and turns the view
## onto the diagonal.
func _arm_and_aim(sim: Simulation, weapon: String) -> bool:
	var waited: int = 0
	while sim.query_enemy_count() == 0 and waited < 600:
		sim.step([])
		waited += 1
	if not assert_true(sim.query_enemy_count() > 0, "the premise: an Enemy came out"):
		return false
	sim.step([InputAction.equip_weapon(0, sim.query_definitions().gear_index(weapon))])
	sim.step([InputAction.look(0, Fixed.from_int(FORTY_FIVE_DEGREES_RIGHT), 0)])
	return true


func test_a_players_round_that_connects_is_credited_to_the_player() -> void:
	# The other half of the ticket's first acceptance criterion. No query says where a
	# player's round went — `FIRE` carries no aim at all, deliberately (#15), and the scatter
	# is an RNG draw the renderer has no business reproducing — so the only evidence a round
	# connected is a Breaker with less health than it had, on a tick the trigger went.
	var sim: Simulation = _rifleman_sim()
	if not _arm_and_aim(sim, "bolt_rifle"):
		return
	var events: CombatEvents = CombatEvents.new()
	events.observe(sim)
	var whole: int = sim.query_enemy_health(0)

	sim.step([InputAction.fire(0)])
	events.observe(sim)

	if not assert_true(sim.query_enemy_health(0) < whole, "the premise: the round connected"):
		return
	var reported: Array = events.events()
	if not assert_eq(reported.size(), 1, "one round, one event"):
		return
	var hit: CombatEvents.Event = reported[0]
	assert_eq(hit.kind, CombatEvents.Kind.HIT, "the Breaker is still standing")
	assert_eq(hit.points, whole - sim.query_enemy_health(0), "and it says how much came off")
	assert_eq(hit.from, CombatEvents.From.PLAYER, "fired by the player")
	assert_eq(hit.from_index, 0, "and by the one this view is drawn for")
	assert_eq(
		hit.tick,
		sim.query_player_last_shot_tick(0),
		"stamped with the tick the trigger went, which is a Simulation number"
	)


func test_a_wrench_landing_is_a_hit_with_nobody_behind_it() -> void:
	# A swing is a real hit and is reported, because #70 is about the body it lands on. What it
	# is not is a shot: there is no line of flight to draw, so `From.NOBODY` is how this file
	# says "something happened to this Enemy and no tracer belongs anywhere" without inventing
	# a third kind of shooter. A melee weapon never reaches `_player_last_shot_tick`'s
	# ranged clause, which is the clause being exercised here.
	var sim: Simulation = _rifleman_sim()
	if not _arm_and_aim(sim, "pneumatic_wrench"):
		return
	var events: CombatEvents = CombatEvents.new()
	# A swing catches the nearest living Enemy in front of the player inside the weapon's
	# reach, so the Breaker has to be walked up to rather than aimed at. It is frozen, so the
	# player does the walking: twelve metres of sprint on the diagonal it is standing on.
	var closed: int = 0
	while closed < 600 and sim.query_enemy_count() > 0:
		sim.step([InputAction.move(0, Fixed.ONE, 0), InputAction.sprint(0, true)])
		closed += 1
		if _gap_to_the_breaker(sim) < 3.0:
			break
	if not assert_true(
		_gap_to_the_breaker(sim) < 3.0,
		"the premise: the player got within a wrench's reach"
	):
		return

	events.observe(sim)
	var whole: int = sim.query_enemy_health(0)
	sim.step([InputAction.fire(0)])
	events.observe(sim)
	if not assert_true(sim.query_enemy_health(0) < whole, "the premise: the swing landed"):
		return
	var reported: Array = events.events()
	if not assert_eq(reported.size(), 1, "one swing, one event"):
		return
	assert_eq(reported[0].kind, CombatEvents.Kind.HIT, "the Breaker lost health")
	assert_eq(
		reported[0].from,
		CombatEvents.From.NOBODY,
		"and nothing was shot, so nothing draws a round in flight"
	)


## How far the player is from the one Enemy on the Map, in metres. A float, because this is a
## test deciding when to stop walking rather than anything the Simulation will be told.
func _gap_to_the_breaker(sim: Simulation) -> float:
	if sim.query_enemy_count() == 0:
		return 9999.0
	var at: FixedVec2 = sim.query_player_position(0)
	var enemy: FixedVec2 = sim.query_enemy_position_metres(0)
	return Vector2(
		Fixed.to_float(at.x) - Fixed.to_float(enemy.x),
		Fixed.to_float(at.z) - Fixed.to_float(enemy.z)
	).length()
