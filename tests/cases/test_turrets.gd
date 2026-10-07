## The MG Turret: a Machine whose output is damage rather than an Item.
##
## This is the file the project's thesis stands behind — production *is* combat power,
## mechanically rather than thematically (docs/DESIGN.md). Everything asserted here goes
## through the Simulation façade, because a Turret is deliberately **not** a separate
## combat subsystem: it is a row in `content/machines.csv` with a Recipe whose input is
## Ammunition, and the Recipe, inventory, Belt and Power rules that move a Smelter are
## the ones that make it shoot.
extends TestCase

## The Nest at the origin covering (0,0) to (3,3), one Breach ten tiles east on the
## Nest's own lane — the same geography `test_enemies` studies the threat with, so a
## Turret's effect on it is readable against that file's numbers.
func _layout() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(0, WorldGrid.GROUND_LAYER, 0)
	layout.add_breach(Vector3i(10, WorldGrid.GROUND_LAYER, 1))
	layout.sort_breaches()
	return layout


## The shipped content, exactly as the game ships it. Nothing here steps a Wave, so there is
## no schedule to wind forward.
func _content(overrides: Array = []) -> Definitions:
	var tuning: String = _read("res://content/tuning.toml")
	for pair: PackedStringArray in overrides:
		tuning = tuning.replace(pair[0], pair[1])
	return Definitions.parse(
		_read("res://content/machines.csv"),
		_read("res://content/recipes.csv"),
		tuning.replace(SHIPPED_STOCK, STOCKED),
		_read("res://content/waves.csv"),
		DELIVERIES,
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv",
		"deliveries.csv"
	)


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	return text


## Content that puts Ammunition on a Belt without a three-stage chain in the way: a Miner
## whose Node yields Ammunition directly, and the shipped MG Turret's numbers.
##
## The shipped chain — Miner, Smelter, Ammo Press, three Belts — is exercised whole further
## down, because that is the acceptance criterion. Here it would only be a slower way of
## filling an input buffer, and a test that takes a minute of game time to reach its first
## assertion is a test nobody runs. Every Turret number is the real file's; nothing about
## the Turret is special-cased for the test. Power is left out of it (nothing draws) so a
## brownout cannot be mistaken for an empty magazine.
const AMMO_MACHINES: String = """id,display_name,role,footprint_x,footprint_z,power_draw_kw,power_supply_kw,health,max_depth,range_tiles,damage,recipe_id,build_cost
ammo_source_mk1,Ammunition Seam,miner,2,2,0,0,400,1,0,0,dig_ammunition,
mg_turret_mk1,MG Turret Mk1,turret,2,2,0,0,350,0,8,15,fire_mg,
"""

const AMMO_RECIPES: String = """id,display_name,inputs,outputs,seconds
dig_ammunition,Dig Ammunition,,ammunition:1,0.25
fire_mg,Fire MG,ammunition:1,,0.25
"""


## A Wave of one Crawler a Breach, and never any more however hot the Factory gets. Most of
## what is asserted below is about one Turret and one Enemy; a test that wants a swarm asks
## for `FOUR_CRAWLERS` instead. Pinned flat rather than left to grow with Heat, because the
## subject here is the Turret and not the schedule.
const ONE_CRAWLER: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,1,0,1
"""

const FOUR_CRAWLERS: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,4,0,4
"""


## The same tuning the game ships, with the Telegraph stretched to ten seconds — long enough
## for the Belt to prime the Turret before the Wave a test called arrives.
##
## The gap between Waves is left at the shipped baseline and the Wave is brought forward with
## the lever instead, which is both the same code path a player uses and what keeps Wave 2
## two and a half minutes out of the way of a test about one Turret.
func _ammo_content(overrides: Array = [], waves: String = ONE_CRAWLER) -> Definitions:
	var tuning: String = _read("res://content/tuning.toml")
	tuning = tuning.replace("telegraph_seconds = 12", "telegraph_seconds = 10")
	tuning = tuning.replace(SHIPPED_STOCK, AMMO_STOCK)
	for pair: PackedStringArray in overrides:
		tuning = tuning.replace(pair[0], pair[1])
	return Definitions.parse(
		AMMO_MACHINES,
		AMMO_RECIPES,
		tuning,
		waves,
		AMMO_DELIVERIES,
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv",
		"deliveries.csv"
	)


## A Run on the Ammunition Map with a Wave already called, so it arrives ten seconds in
## rather than two and a half minutes in.
func _ammo_sim(overrides: Array = [], waves: String = ONE_CRAWLER) -> Simulation:
	var sim: Simulation = Simulation.new(5, 1, _ammo_content(overrides, waves), _ammo_layout())
	sim.step([InputAction.call_wave_early(0)])
	return sim


## A Map with an Ammunition seam beside the Crawlers' lane, so a Turret standing in the
## lane can be fed by one Belt.
func _ammo_layout() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(0, WorldGrid.GROUND_LAYER, 0)
	layout.add_node(Vector3i(8, WorldGrid.GROUND_LAYER, 6), "ammunition", 1)
	layout.sort_nodes()
	layout.add_breach(Vector3i(20, WorldGrid.GROUND_LAYER, 1))
	layout.sort_breaches()
	return layout


## An MG Turret at (8,1) in the Crawlers' lane, fed from the seam at (8,6) by one Belt.
##
## The Turret is built first, so index 0 is the Turret in every test below.
func _fed_turret(sim: Simulation) -> void:
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(
			0, definitions.machine_index("mg_turret_mk1"), Vector3i(8, WorldGrid.GROUND_LAYER, 0)
		),
		InputAction.build_machine(
			0, definitions.machine_index("ammo_source_mk1"), Vector3i(8, WorldGrid.GROUND_LAYER, 6)
		),
		# The seam occupies (8,6) to (9,7); the Belt starts on the tile past its north edge
		# and ends pointing at the Turret, which occupies (8,0) to (9,1).
		InputAction.build_belt(
			0,
			Vector3i(8, WorldGrid.GROUND_LAYER, 5),
			Vector3i(8, WorldGrid.GROUND_LAYER, 2)
		),
	])


## Steps until the Turret is holding at least one round, and reports the ticks it took.
##
## Bounded, like every wait in this file: an unbounded `while` in a test is a hung suite
## rather than a failing one, and a hung suite says nothing at all.
func _step_until_loaded(sim: Simulation) -> int:
	var ticks: int = 0
	while sim.query_turret_ammunition(0) == 0 and ticks < 1200:
		sim.step([])
		ticks += 1
	return ticks


## Steps until the Turret has something in its sights, and reports the ticks it took.
func _step_until_aimed(sim: Simulation) -> int:
	var ticks: int = 0
	while sim.query_turret_target_serial(0) == -1 and ticks < 1800:
		sim.step([])
		ticks += 1
	return ticks


# ── The definition ────────────────────────────────────────────────────────────

func test_an_mg_turret_is_a_machine_that_consumes_ammunition() -> void:
	var content: Definitions = _content()
	assert_false(content.has_errors(), content.describe_errors())

	var turret: MachineDefinition = content.machine("mg_turret_mk1")
	if not assert_not_null(turret, "mg_turret_mk1 must be a row in content/machines.csv"):
		return
	assert_true(turret.is_turret(), "its role is turret")
	assert_eq(turret.range_tiles, 8, "how far it reaches, in tiles")
	assert_eq(turret.damage, 15, "what one round takes off an Enemy — two to a Crawler")

	var recipe: RecipeDefinition = content.recipe_at(turret.recipe_index)
	if not assert_not_null(recipe, "a Turret runs a Recipe like any other Machine"):
		return
	assert_eq(recipe.input_count(), 1, "Ammunition, and nothing else")
	assert_eq(content.item_id(recipe.input_item(0)), "ammunition")
	assert_eq(recipe.input_quantity(0), 1, "one round a shot")
	assert_eq(
		recipe.output_count(),
		0,
		"and no outputs at all: what a Turret produces is damage, which is not an Item"
	)


# ── Acquiring and firing ──────────────────────────────────────────────────────

func test_a_fed_turret_kills_a_crawler_that_walks_into_range() -> void:
	var sim: Simulation = _ammo_sim()
	_fed_turret(sim)
	assert_true(sim.query_machine_is_turret(0), "index 0 is the Turret")
	_step_until_loaded(sim)

	var ticks: int = 0
	while sim.query_enemy_count() == 0 and ticks < 600:
		sim.step([])
		ticks += 1
	assert_eq(sim.query_enemy_count(), 1, "a Crawler came out of the Breach")
	var doomed: int = sim.query_enemy_serial(0)

	ticks = 0
	while sim.query_enemy_count() > 0 and ticks < 1200:
		sim.step([])
		ticks += 1
	assert_true(ticks < 1200, "the Crawler was killed after %d ticks" % ticks)
	assert_eq(sim.query_nest_health(), sim.query_nest_max_health(), "and never reached the Nest")
	assert_eq(
		sim.query_turret_last_shot_tick(0),
		sim.query_tick() - 1,
		"the shot that killed it landed on the tick the Crawler disappeared"
	)
	assert_ne(doomed, -1, "and the Crawler it killed had been issued a serial")


func test_a_turret_without_ammunition_does_not_fire() -> void:
	# The whole point of the ticket: defence costs continuous production, so a Turret that
	# was built and walked away from is an ornament.
	var sim: Simulation = _ammo_sim()
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(
			0, definitions.machine_index("mg_turret_mk1"), Vector3i(8, WorldGrid.GROUND_LAYER, 0)
		),
	])
	assert_eq(sim.query_turret_ammunition(0), 0, "nothing is feeding it")

	for i: int in range(40 * Simulation.TICKS_PER_SECOND):
		sim.step([])
	assert_eq(sim.query_turret_last_shot_tick(0), -1, "it never fired, not once")
	assert_eq(sim.query_enemy_count(), 1, "and the Crawler is still on the Map")
	assert_true(
		sim.query_nest_health() < sim.query_nest_max_health(),
		"chewing the Nest the Turret was built to protect"
	)
	assert_true(sim.query_machine_is_starved(0), "an empty magazine reads as starved")


func test_a_turret_does_not_fire_at_an_enemy_beyond_its_reach() -> void:
	var sim: Simulation = _ammo_sim()
	_fed_turret(sim)
	_step_until_loaded(sim)

	var waiting: int = 0
	while sim.query_enemy_count() == 0 and waiting < 1800:
		sim.step([])
		waiting += 1
	# The Breach is at tile 20 and the Turret's footprint centre is at 18 m, which is 23 m
	# away — half as far again as the 16 m its row declares.
	assert_eq(sim.query_turret_target_serial(0), -1, "nothing in reach to aim at")
	assert_eq(sim.query_turret_last_shot_tick(0), -1, "so it has not fired")
	var loaded: int = sim.query_turret_ammunition(0)

	sim.step([])
	assert_eq(sim.query_turret_ammunition(0), loaded, "and it is not burning rounds either")


func test_a_turret_acquires_at_the_range_its_row_declares() -> void:
	var sim: Simulation = _ammo_sim()
	_fed_turret(sim)
	_step_until_loaded(sim)
	assert_eq(
		sim.query_turret_range_metres(0),
		Fixed.from_int(16),
		"range_tiles 8 on a 2 m grid"
	)

	var ticks: int = 0
	while sim.query_turret_target_serial(0) == -1 and ticks < 1200:
		sim.step([])
		ticks += 1
	if not assert_true(ticks < 1200, "it acquired a target after %d ticks" % ticks):
		return

	var gap: int = _gap_metres(sim, 0, sim.query_enemy_index_of_serial(sim.query_turret_target_serial(0)))
	assert_true(
		gap <= Fixed.from_int(16),
		"acquired inside its reach: %d" % gap
	)
	assert_true(
		gap > Fixed.from_int(15),
		"and on the very tick the Crawler crossed the line, not once it was on top of it: %d" % gap
	)


func test_a_turret_keeps_shooting_at_the_crawler_it_was_shooting_at() -> void:
	# Target retention, and the reason the target is held as a serial. Crawlers walk in a
	# file, so the nearest is always the earliest spawn: a Turret that re-decided every tick
	# would still look right, and one holding an *index* would silently switch to a different
	# Crawler every time one died. So what is asserted is that the serial never goes
	# backwards and that each one is held for the whole three shots it takes to kill it.
	var sim: Simulation = _ammo_sim(
		[PackedStringArray(["crawler_health = 30", "crawler_health = 90"])], FOUR_CRAWLERS
	)
	_fed_turret(sim)
	_step_until_loaded(sim)

	var targeted: PackedInt64Array = PackedInt64Array()
	var highest: int = -1
	for i: int in range(60 * Simulation.TICKS_PER_SECOND):
		sim.step([])
		var serial: int = sim.query_turret_target_serial(0)
		if serial == -1:
			continue
		assert_true(serial >= highest, "the target serial went backwards: %d after %d" % [serial, highest])
		if serial > highest:
			highest = serial
			targeted.append(serial)
		assert_ne(
			sim.query_enemy_index_of_serial(serial),
			-1,
			"a Turret is never aimed at a Crawler that is no longer on the Map"
		)
	assert_eq(targeted.size(), 4, "it worked through the whole Wave, one Crawler at a time")
	assert_eq(sim.query_enemy_count(), 0, "and killed all four")


func test_a_turret_with_nothing_in_reach_is_not_on_the_power_grid() -> void:
	# A Turret idle between Waves must not be charged for, exactly as a starved Smelter is
	# not: `_machine_would_work` is the one predicate behind what the grid bills, what
	# advances and what fires, so this is the same assertion as "it does not burn rounds".
	var content: Definitions = Definitions.parse(
		AMMO_MACHINES.replace("mg_turret_mk1,MG Turret Mk1,turret,2,2,0,0", "mg_turret_mk1,MG Turret Mk1,turret,2,2,90,0"),
		AMMO_RECIPES,
		(
			_read("res://content/tuning.toml")
			. replace("telegraph_seconds = 12", "telegraph_seconds = 10")
			. replace(SHIPPED_STOCK, AMMO_STOCK)
		),
		ONE_CRAWLER,
		AMMO_DELIVERIES,
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv",
		"deliveries.csv"
	)
	assert_false(content.has_errors(), content.describe_errors())
	var sim: Simulation = Simulation.new(5, 1, content, _ammo_layout())
	sim.step([InputAction.call_wave_early(0)])
	_fed_turret(sim)
	_step_until_loaded(sim)
	sim.step([])
	assert_eq(sim.query_power_demand_kw(), 0, "loaded, but with nothing to shoot at")

	_step_until_aimed(sim)
	sim.step([])
	assert_eq(sim.query_power_demand_kw(), 90, "and on the grid the moment it has a target")


## How far an Enemy is from the centre of a Machine's footprint, in fixed-point metres.
##
## Derived here from the public queries the renderer uses — the anchor tile, the turned
## footprint and a tile centre — rather than from anything the Simulation exposes about
## Turrets, so this is an independent measurement and not a restatement of the code.
func _gap_metres(sim: Simulation, machine: int, enemy: int) -> int:
	var anchor: Vector3i = sim.query_machine_tile(machine)
	var footprint: Vector2i = sim.query_machine_footprint(machine)
	var near: FixedVec2 = sim.query_tile_centre_metres(anchor)
	var far: FixedVec2 = sim.query_tile_centre_metres(
		Vector3i(anchor.x + footprint.x - 1, anchor.y, anchor.z + footprint.y - 1)
	)
	var where: FixedVec2 = sim.query_enemy_position_metres(enemy)
	var gap_x: int = where.x - (near.x + far.x) / 2
	var gap_z: int = where.z - (near.z + far.z) / 2
	return Fixed.sqrt(Fixed.mul(gap_x, gap_x) + Fixed.mul(gap_z, gap_z))


# ── The whole keystone loop, on the Map the game ships ────────────────────────
# Shipped content, shipped Map, shipped numbers. Everything above isolates one rule; this
# is the ticket's actual claim — that an Ammo Press connected by Belt to an MG Turret turns
# iron ore into dead Crawlers — and it is asserted on the Factory a player would build.

## Where each piece of the reference Factory stands on the starter Map, so a test can name a
## tile without restating the layout. The iron line runs east from the Node at (4,4); the
## coal line runs east from the Node at (12,4) into a Boiler that pays for all of it; and the
## Ammunition travels the long way round to a Turret standing in the Crawlers' lane.
const TURRET_TILE: Vector3i = Vector3i(2, 0, -7)
## How far into the Run the dry fixture cuts the Turret's supply line. Just past tick 8479,
## which is when this Factory's Turret first fires — the Wave it is shooting at arrived at
## 8217, pulled in from 9000 by the Heat the Factory made producing the Ammunition.
const DRY_CUT_TICK: int = 8520

const LAST_BELT_TILE: Vector3i = Vector3i(1, 0, -6)


## Builds the Factory this ticket exists to make work: ore to plates to Ammunition to a
## Turret, with a Boiler paying the Power bill. One tick, because a Build Gun places one
## Machine a click and the Simulation does not care how many clicks arrive together.
func _competent_factory(sim: Simulation) -> void:
	sim.step(_factory_machines(sim.query_definitions()))
	sim.step(_factory_belts())


## The six Machines, as Input Actions. Returned rather than applied so that the replay
## fixtures can put the same Factory in an `InputScript` — a fixture built out of a different
## sequence than the tests assert against would prove determinism over a Run nobody checked.
func _factory_machines(definitions: Definitions) -> Array:
	var ground: int = WorldGrid.GROUND_LAYER
	return [
		# The iron line.
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), Vector3i(4, ground, 4)),
		InputAction.build_machine(0, definitions.machine_index("smelter_mk1"), Vector3i(8, ground, 4)),
		InputAction.build_machine(0, definitions.machine_index("ammo_press_mk1"), Vector3i(8, ground, 9)),
		# The Power that pays for it.
		InputAction.build_machine(0, definitions.machine_index("coal_miner_mk1"), Vector3i(12, ground, 4)),
		InputAction.build_machine(0, definitions.machine_index("steam_boiler_mk1"), Vector3i(16, ground, 4)),
		# And the thing it is all for.
		InputAction.build_machine(0, definitions.machine_index("mg_turret_mk1"), TURRET_TILE),
	]


## And the six Belts that join them. A tick after the Machines, because a Belt is refused on
## a tile a Machine already stands on and the two arriving together would depend on the order
## within one tick.
func _factory_belts() -> Array:
	var ground: int = WorldGrid.GROUND_LAYER
	return [
		InputAction.build_belt(0, Vector3i(6, ground, 4), Vector3i(7, ground, 4)),
		InputAction.build_belt(0, Vector3i(8, ground, 7), Vector3i(8, ground, 8)),
		InputAction.build_belt(0, Vector3i(14, ground, 4), Vector3i(15, ground, 4)),
		InputAction.build_belt(0, Vector3i(7, ground, 9), Vector3i(1, ground, 9)),
		InputAction.build_belt(0, Vector3i(0, ground, 9), Vector3i(0, ground, -5)),
		InputAction.build_belt(0, Vector3i(0, ground, -6), LAST_BELT_TILE),
	]


## Which Machine index the Turret ended up at. Looked up rather than assumed, because build
## order is the Factory's business and not this helper's.
func _turret_index(sim: Simulation) -> int:
	for index: int in range(sim.query_machine_count()):
		if sim.query_machine_is_turret(index):
			return index
	return -1


func test_an_ammo_press_feeds_a_turret_by_belt_and_it_holds_the_lane() -> void:
	var sim: Simulation = Simulation.new(7, 1, null, MapLayout.starter())
	assert_true(sim.query_definitions_loaded(), "the shipped content")
	_competent_factory(sim)
	assert_eq(sim.query_machine_count(), 6, "six Machines")
	assert_eq(sim.query_belt_count(), 6, "joined by six Belts")

	var turret: int = _turret_index(sim)
	if not assert_true(turret != -1, "the Turret is standing"):
		return

	# Long enough for the first Wave and the far side of it. **This Factory brings its own
	# Wave forward**: six working Machines raise Heat, Heat shortens the gap, and the Wave
	# lands at tick 8217 rather than at the 9000 a cold Factory would wait. That is #12's
	# mechanic acting on #10's arithmetic, and the comparison below is where it shows.
	var fired: int = 0
	var highest_magazine: int = 0
	for i: int in range(180 * Simulation.TICKS_PER_SECOND):
		var before: int = sim.query_turret_last_shot_tick(turret)
		sim.step([])
		if sim.query_turret_last_shot_tick(turret) != before:
			fired += 1
		highest_magazine = maxi(highest_magazine, sim.query_turret_ammunition(turret))

	assert_eq(sim.query_wave_number(), 1, "one Wave came and went")
	assert_true(
		sim.query_item_total("ammunition") > 0,
		"the Ammo Press turned plates into Ammunition"
	)
	assert_true(highest_magazine > 0, "and a Belt carried rounds into the Turret")
	assert_true(fired >= 6, "which fired %d times — at least once per Crawler" % fired)
	assert_eq(sim.query_enemy_count(), 0, "the whole Wave is dead")
	assert_eq(
		sim.query_nest_health(),
		sim.query_nest_max_health(),
		"and not one Crawler reached the Nest"
	)


func test_an_undefended_nest_loses_the_wave_the_same_factory_holds() -> void:
	# The comparison the ticket is for. Identical content, identical Map, identical three
	# minutes — the only difference is whether a Turret was fed.
	#
	# The defended Factory is attacked **earlier** than the bare one, at tick 8217 against
	# 9000, because producing is what raised its Heat. That is the bet the whole game is
	# about: the Factory that can hold a Wave is also the Factory that summons it sooner.
	var defended: Simulation = Simulation.new(7, 1, null, MapLayout.starter())
	var bare: Simulation = Simulation.new(7, 1, null, MapLayout.starter())
	_competent_factory(defended)
	for i: int in range(180 * Simulation.TICKS_PER_SECOND):
		defended.step([])
		bare.step([])

	assert_eq(defended.query_nest_health(), defended.query_nest_max_health(), "untouched")
	assert_true(
		bare.query_nest_health() < bare.query_nest_max_health(),
		"while the undefended Nest is being chewed: %d of %d left"
		% [bare.query_nest_health(), bare.query_nest_max_health()]
	)
	assert_eq(bare.query_enemy_count(), 6, "by a Wave nothing shot at")


# ── A Cannon Turret is a row ──────────────────────────────────────────────────

## A Cannon Turret added the only way a Machine is ever added: a row in the Machine table
## and a row in the Recipe table. Longer reach, a much heavier shell, slower, and two rounds
## a shot — four numbers, none of which is named anywhere in `sim/`.
##
## Deliberately built on top of the shipped files rather than beside them, so this is
## literally the diff a content ticket would commit.
func _cannon_content() -> Definitions:
	var machines: String = (
		_read("res://content/machines.csv")
		+ "cannon_turret_mk1,Cannon Turret Mk1,turret,3,3,160,0,500,0,14,80,fire_cannon,iron_plate:30\n"
	)
	var recipes: String = (
		_read("res://content/recipes.csv") + "fire_cannon,Fire Cannon,ammunition:2,,1.5\n"
	)
	return Definitions.parse(
		machines,
		recipes,
		_read("res://content/tuning.toml").replace(SHIPPED_STOCK, STOCKED),
		_read("res://content/waves.csv"),
		DELIVERIES,
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv",
		"deliveries.csv"
	)


func test_a_cannon_turret_is_addable_as_a_data_definition() -> void:
	var content: Definitions = _cannon_content()
	assert_false(content.has_errors(), content.describe_errors())

	var cannon: MachineDefinition = content.machine("cannon_turret_mk1")
	if not assert_not_null(cannon, "two rows and nothing else"):
		return
	assert_true(cannon.is_turret())
	assert_eq(cannon.range_tiles, 14, "it outreaches the MG")
	assert_eq(cannon.damage, 80, "and hits very much harder")
	assert_eq(
		content.recipe_at(cannon.recipe_index).input_quantity(0),
		2,
		"two rounds a shot, which is a Recipe quantity and not a special case"
	)


func test_a_cannon_turret_fires_further_and_harder_with_no_code_that_knows_about_it() -> void:
	# The acceptance criterion, asserted as behaviour rather than as a parsed row: the Cannon
	# acquires at its own reach, spends its own two rounds a shot, and kills with its own
	# damage — all of it through the same `_craft` the MG and a Smelter go through.
	var tuning: String = _read("res://content/tuning.toml")
	tuning = tuning.replace("telegraph_seconds = 12", "telegraph_seconds = 10")
	tuning = tuning.replace(SHIPPED_STOCK, AMMO_STOCK)
	var content: Definitions = Definitions.parse(
		AMMO_MACHINES + "cannon_turret_mk1,Cannon Turret Mk1,turret,3,3,0,0,500,0,14,80,fire_cannon,\n",
		AMMO_RECIPES + "fire_cannon,Fire Cannon,ammunition:2,,1.5\n",
		tuning,
		ONE_CRAWLER,
		AMMO_DELIVERIES,
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv",
		"deliveries.csv"
	)
	assert_false(content.has_errors(), content.describe_errors())

	var sim: Simulation = Simulation.new(5, 1, content, _ammo_layout())
	sim.step([InputAction.call_wave_early(0)])
	var ground: int = WorldGrid.GROUND_LAYER
	sim.step([
		InputAction.build_machine(0, content.machine_index("cannon_turret_mk1"), Vector3i(8, ground, 0)),
		InputAction.build_machine(0, content.machine_index("ammo_source_mk1"), Vector3i(8, ground, 6)),
		InputAction.build_belt(0, Vector3i(8, ground, 5), Vector3i(8, ground, 3)),
	])
	assert_eq(sim.query_turret_range_metres(0), Fixed.from_int(28), "14 tiles of 2 m")

	var waited: int = 0
	while sim.query_turret_ammunition(0) < 2 and waited < 1200:
		sim.step([])
		waited += 1
	assert_eq(sim.query_turret_shots_remaining(0), 1, "two rounds held is one shot's worth")

	var ticks: int = 0
	while sim.query_enemy_count() == 0 and ticks < 1200:
		sim.step([])
		ticks += 1
	# The Breach is 23 m from the Turret's centre, inside the Cannon's 28 m reach, so unlike
	# the MG it is aimed at the Crawler the moment the Crawler exists.
	sim.step([])
	assert_ne(sim.query_turret_target_serial(0), -1, "in reach where the MG's 16 m is not")

	var magazine: int = sim.query_turret_ammunition(0)
	ticks = 0
	while sim.query_turret_last_shot_tick(0) == -1 and ticks < 300:
		sim.step([])
		ticks += 1
	assert_true(ticks < 300, "it fired after %d ticks" % ticks)
	assert_eq(sim.query_enemy_count(), 0, "80 damage against 30 hit points is one shell")
	assert_true(
		magazine - sim.query_turret_ammunition(0) >= 2,
		"and the shell cost two rounds"
	)


# ── Replay fixtures ───────────────────────────────────────────────────────────
# Both against the *shipped* content, with no definitions passed, so a replay re-reads
# content/ and a change to the Turret's row or the Ammunition Recipe is reported as a
# definitions mismatch rather than passing unnoticed (CLAUDE.md).

func test_determinism_a_turret_firing_and_killing_crawlers_replays_identically() -> void:
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	var script: InputScript = InputScript.new()
	script.add_tick(_factory_machines(definitions))
	script.add_tick(_factory_belts())
	# Past the first Wave — which this Factory's own Heat pulls in to tick 8217 — and out the
	# far side of it.
	script.add_idle_ticks(180 * Simulation.TICKS_PER_SECOND)

	var recording: ReplayRecording = DeterminismHarness.record(script, 7, 1)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_the_firing_fixture_really_did_kill_crawlers() -> void:
	# A fixture proving determinism over a Run in which nothing was shot would prove nothing,
	# so the scenario is checked separately from the replay — on the same seed, Map and script.
	var sim: Simulation = Simulation.new(7, 1, null, MapLayout.starter())
	_competent_factory(sim)
	var turret: int = _turret_index(sim)
	var killed: int = 0
	var seen: int = 0
	for i: int in range(180 * Simulation.TICKS_PER_SECOND):
		var before: int = sim.query_enemy_count()
		sim.step([])
		seen = maxi(seen, sim.query_enemy_count())
		if sim.query_enemy_count() < before:
			killed += before - sim.query_enemy_count()
	assert_eq(sim.query_wave_number(), 1, "the shipped first Wave arrived")
	# Seven rather than the six a *cold* Factory earns, and the extra one is the whole point
	# of #12: `content/waves.csv` buys the Enemy one more Crawler a Breach every 150 Heat, and
	# this Factory made enough producing the Ammunition it is defending itself with. The
	# Turret still killed every one of them.
	assert_eq(killed, 7, "and the Turret shot every Crawler the Wave sent")
	assert_true(
		killed > 6,
		"a Factory that produces is sent more than a Factory that does not: %d" % killed
	)
	assert_true(seen > 0, "there were Crawlers on the Map to shoot at")
	assert_true(
		sim.query_turret_last_shot_tick(turret) > 0,
		"the Turret fired at least once"
	)


func test_determinism_a_turret_running_dry_mid_wave_replays_identically() -> void:
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	var script: InputScript = InputScript.new()
	script.add_tick(_factory_machines(definitions))
	script.add_tick(_factory_belts())
	# Just after the Turret opens fire — it first shoots on tick 8479 — the last Belt into it
	# is taken up, so it spends what it is holding and then stops with Crawlers still walking
	# at it. One Input Action, which is what makes "it ran dry" a thing a replay can
	# reproduce exactly.
	script.add_idle_ticks(DRY_CUT_TICK)
	script.add_tick([InputAction.demolish(0, LAST_BELT_TILE)])
	script.add_idle_ticks(45 * Simulation.TICKS_PER_SECOND)

	var recording: ReplayRecording = DeterminismHarness.record(script, 7, 1)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_the_dry_fixture_really_did_run_dry_with_crawlers_still_coming() -> void:
	var sim: Simulation = Simulation.new(7, 1, null, MapLayout.starter())
	_competent_factory(sim)
	var turret: int = _turret_index(sim)
	for i: int in range(DRY_CUT_TICK):
		sim.step([])
	assert_true(sim.query_turret_ammunition(turret) > 0, "supplied, and shooting")
	var shots_before: int = sim.query_turret_last_shot_tick(turret)
	assert_true(shots_before > 0, "it had already fired")

	sim.step([InputAction.demolish(0, LAST_BELT_TILE)])
	assert_eq(sim.query_belt_count(), 5, "its supply line is gone")

	var ran_dry_with_enemies_alive: bool = false
	for i: int in range(45 * Simulation.TICKS_PER_SECOND):
		sim.step([])
		if sim.query_turret_ammunition(turret) == 0 and sim.query_enemy_count() > 0:
			ran_dry_with_enemies_alive = true
	assert_true(ran_dry_with_enemies_alive, "it ran out mid-Wave, which is the whole scenario")
	assert_true(
		sim.query_nest_health() < sim.query_nest_max_health(),
		"and the Crawlers it could not shoot got through to the Nest"
	)


# ── State, saved and hashed ───────────────────────────────────────────────────

func test_a_turret_mid_fight_is_part_of_the_state_hash() -> void:
	var sim: Simulation = _ammo_sim()
	_fed_turret(sim)
	_step_until_loaded(sim)
	_step_until_aimed(sim)

	var aimed: int = sim.hash()
	sim.step([])
	assert_ne(aimed, sim.hash(), "a Turret that fired is a Simulation in a different state")


func test_a_run_with_a_turret_mid_fight_saves_and_resumes_identically() -> void:
	var content: Definitions = _ammo_content()
	var sim: Simulation = Simulation.new(5, 1, content, _ammo_layout())
	sim.step([InputAction.call_wave_early(0)])
	_fed_turret(sim)
	_step_until_loaded(sim)
	_step_until_aimed(sim)
	assert_ne(sim.query_turret_target_serial(0), -1, "the Turret is aimed at something")

	var loaded: RunSave.Load = RunSave.deserialise(
		RunSave.serialise(sim), content, Simulation.new(0, 1, content, MapLayout.empty())
	)
	assert_false(loaded.has_errors(), loaded.describe_errors())
	assert_eq(
		loaded.simulation.hash(),
		sim.hash(),
		"the target serial, the magazine and the shot clock all came back"
	)
	assert_eq(
		loaded.simulation.query_turret_target_serial(0),
		sim.query_turret_target_serial(0),
		"and it is still aimed at the same Crawler, by serial"
	)

	# And the two go on agreeing, which is the only test of restored combat state that matters.
	for i: int in range(5 * Simulation.TICKS_PER_SECOND):
		sim.step([])
		loaded.simulation.step([])
		assert_eq(loaded.simulation.hash(), sim.hash(), "diverged at tick %d" % sim.query_tick())


# ── Fixtures that keep progression out of the way ─────────────────────────────
# This file is about a Turret, and the shipped Delivery chain locks the MG Turret behind
# its first tier and opens a Run holding exactly the plates for one line
# (`content/deliveries.csv`, `content/tuning.toml`). Both are balance rather than anything
# asserted here, so the fixtures below replace them with a tier that locks nothing and a
# stock that pays for anything. `test_delivery.gd` is where the real chain is asserted.

const SHIPPED_STOCK: String = 'starting_stock = "iron_plate:80"'
const STOCKED: String = 'starting_stock = "ammunition:400;coal:400;iron_ore:400;iron_plate:400"'

## A tier against the shipped Items that names no Machine, so every row of the shipped
## `machines.csv` is buildable from tick 0.
const DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_opening,Opening Licence,1,iron_plate:1,,placeholder_gear,
"""

## The Ammunition fixture's Machines are all free to build, so it opens a Run holding
## nothing — an empty bill is legal and says plainly that materials are not what is under
## test here.
const AMMO_STOCK: String = 'starting_stock = ""'

## The same, against the one Item the Ammunition fixture's Recipes mention.
const AMMO_DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_opening,Opening Licence,1,ammunition:1,,placeholder_gear,
"""
