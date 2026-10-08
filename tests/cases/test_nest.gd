## The Nest, the Breach, the Wave clock and losing the Run — through the Simulation
## façade, which is the only seam (CLAUDE.md).
extends TestCase

## A Map small enough to lose on quickly: the Nest at the origin and one Breach six
## tiles east of its edge, on the Nest's own lane.
func _layout() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(0, WorldGrid.GROUND_LAYER, 0)
	layout.add_breach(Vector3i(10, WorldGrid.GROUND_LAYER, 1))
	layout.sort_breaches()
	return layout


## A Wave of two Crawlers a Breach, and never any more however hot the Factory gets. The
## schedule under test here is the clock and the Telegraph, so the composition is pinned
## flat — `test_heat` is where Heat growing a Wave is asserted.
const TWO_CRAWLERS: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,2,0,2
"""


## Shipped content with the Wave clock wound forward and the Nest made of paper, so a
## whole Run fits in a few hundred ticks. Everything else is the real file.
##
## All three schedule keys move together: `Definitions` refuses a Telegraph longer than
## the minimum interval and a minimum interval above the baseline, because a schedule that
## contradicts itself is content somebody broke rather than a fixture.
## `interval` is the gap between Waves in seconds, as text, and all three schedule keys take
## it together: `Definitions` refuses a minimum interval above the baseline, or a first
## interval below the minimum, because a schedule that contradicts itself is content somebody
## broke rather than a fixture. Pass "1" for a stream of Waves and the shipped "150" for
## exactly one.
func _quick_content(nest_health: int = 40, interval: String = "1") -> Definitions:
	return Definitions.parse(
		_read("res://content/machines.csv"),
		_read("res://content/recipes.csv"),
		(
			_read("res://content/tuning.toml")
			. replace("telegraph_seconds = 12", "telegraph_seconds = 0.5")
			. replace(
				"wave_interval_baseline_seconds = 150",
				"wave_interval_baseline_seconds = %s" % interval
			)
			. replace(
				"first_wave_interval_seconds = 90",
				"first_wave_interval_seconds = %s" % interval
			)
			. replace(
				"wave_interval_minimum_seconds = 40",
				"wave_interval_minimum_seconds = %s" % interval
			)
			. replace("spawn_interval_seconds = 0.5", "spawn_interval_seconds = 0.2")
			. replace("health = 6000", "health = %d" % nest_health)
			. replace(SHIPPED_STOCK, STOCKED)
		),
		TWO_CRAWLERS,
		DELIVERIES,
		GEAR,
		STRATAGEMS,
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv",
		"deliveries.csv",
		"gear.csv",
		"stratagems.csv"
	)


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	return text


func _quick_sim(nest_health: int = 40) -> Simulation:
	return Simulation.new(3, 1, _quick_content(nest_health), _layout())


## A Run on the shipped interval with one Wave already called, so exactly one Wave ever
## arrives and the Wave the Run-over report names is unambiguous. The lever is the honest
## way to bring a Wave forward in a test: it is the same code path a player uses.
func _one_wave_sim(nest_health: int = 40) -> Simulation:
	var sim: Simulation = Simulation.new(3, 1, _quick_content(nest_health, "150"), _layout())
	sim.step([InputAction.call_wave_early(0)])
	return sim


# ── The Nest ──────────────────────────────────────────────────────────────────

func test_the_map_places_a_nest_with_health() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_eq(sim.query_nest_tile(), Vector3i(-6, WorldGrid.GROUND_LAYER, -6), "the starter Nest")
	assert_eq(sim.query_nest_footprint(), Vector2i(4, 4), "the Nest is 4x4 tiles")
	assert_eq(sim.query_nest_health(), 6000, "nest.health in content/tuning.toml")
	assert_eq(sim.query_nest_max_health(), 6000, "a fresh Nest is undamaged")


func test_the_nest_covers_every_tile_of_its_footprint() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var anchor: Vector3i = sim.query_nest_tile()
	assert_true(sim.query_nest_covers_tile(anchor), "its anchor")
	assert_true(
		sim.query_nest_covers_tile(Vector3i(anchor.x + 3, anchor.y, anchor.z + 3)),
		"the far corner of a 4x4 footprint"
	)
	assert_false(
		sim.query_nest_covers_tile(Vector3i(anchor.x + 4, anchor.y, anchor.z)),
		"one tile past the footprint is not the Nest"
	)


func test_the_nest_is_not_a_machine() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_eq(sim.query_machine_count(), 0, "a Run opens with an empty Factory")
	assert_eq(
		sim.query_machine_at_tile(sim.query_nest_tile()),
		-1,
		"the Nest is listed alongside Belt and Wall, outside the eight Machines (DESIGN.md)"
	)


func test_the_nest_stands_on_ground_nothing_can_be_built_on() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var miner: int = sim.query_definitions().machine_index("miner_mk1")
	assert_eq(
		sim.query_build_refusal(0, miner, sim.query_nest_tile(), 0),
		Simulation.Refusal.OCCUPIED,
		"a Machine cannot be built on top of the Nest"
	)
	sim.step([InputAction.build_machine(0, miner, sim.query_nest_tile())])
	assert_eq(sim.query_machine_count(), 0, "and the refusal is a silent no-op")


func test_a_belt_cannot_be_laid_across_the_nest() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var anchor: Vector3i = sim.query_nest_tile()
	sim.step([
		InputAction.build_belt(
			0,
			Vector3i(anchor.x - 2, anchor.y, anchor.z),
			Vector3i(anchor.x + 2, anchor.y, anchor.z)
		)
	])
	assert_eq(sim.query_belt_count(), 0, "a run through the Nest is refused whole")


# ── The Breach ────────────────────────────────────────────────────────────────

func test_the_map_places_a_fixed_breach() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_eq(sim.query_breach_count(), 1, "Milestone 1 ships one Breach")
	assert_eq(
		sim.query_breach_tile(0),
		Vector3i(16, WorldGrid.GROUND_LAYER, -6),
		"the starter Breach, on the Nest's own lane so the Factory is in the way"
	)


func test_the_breach_does_not_move_during_a_run() -> void:
	var sim: Simulation = _quick_sim()
	var where: Vector3i = sim.query_breach_tile(0)
	for i: int in range(200):
		sim.step([])
	assert_eq(
		sim.query_breach_tile(0),
		where,
		"a Breach is known in advance and fortifiable (GLOSSARY.md), so it is fixed"
	)


func test_an_unknown_breach_reads_as_the_origin_rather_than_crashing() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_eq(sim.query_breach_tile(99), Vector3i.ZERO)


# ── The Wave clock ────────────────────────────────────────────────────────────

func test_a_run_opens_before_the_first_wave_with_a_countdown_to_it() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_eq(sim.query_wave_number(), 0, "no Wave has arrived yet")
	assert_eq(
		sim.query_ticks_until_next_wave(),
		90 * Simulation.TICKS_PER_SECOND,
		(
			"heat.first_wave_interval_seconds — a Run opens cold, and the opening gap is its"
			+ " own number because it is the one nobody has had the chance to shorten (#35)"
		)
	)
	assert_eq(sim.query_enemy_count(), 0, "and no Enemies are on the Map")


func test_the_first_wave_arrives_when_its_timer_runs_out() -> void:
	var sim: Simulation = _quick_sim()
	for i: int in range(Simulation.TICKS_PER_SECOND - 1):
		sim.step([])
	assert_eq(sim.query_wave_number(), 0, "one tick short of the tuned second")
	sim.step([])
	assert_eq(sim.query_wave_number(), 1, "Wave 1")


func test_a_map_with_no_breach_never_sees_a_wave() -> void:
	# A Map Enemies have nowhere to enter is a Map nothing attacks, which is the
	# geography a test studying only the Factory asks for.
	var sim: Simulation = Simulation.new(3, 1, _quick_content(), MapLayout.empty())
	for i: int in range(600):
		sim.step([])
	assert_eq(sim.query_breach_count(), 0)
	assert_eq(sim.query_wave_number(), 0, "no Breach, no Wave")
	assert_eq(sim.query_enemy_count(), 0)


func test_a_cold_factory_is_sent_the_same_wave_every_time() -> void:
	# The counterpart to `test_heat`'s escalation, and the half that makes it mean
	# something: a Wave grows because the Factory got hotter, **not** because time passed.
	# A Run with no Machines at all is attacked by the same two Crawlers for ever.
	var sim: Simulation = _quick_sim(1000000)
	var first: int = 0
	var second: int = 0
	for i: int in range(3 * 60 * Simulation.TICKS_PER_SECOND):
		var before: int = sim.query_enemy_count()
		sim.step([])
		if sim.query_enemy_count() > before:
			if sim.query_wave_number() == 1:
				first += 1
			elif sim.query_wave_number() == 2:
				second += 1
	assert_eq(sim.query_heat(), 0, "nothing was ever produced")
	assert_eq(first, 2, "the tuned count_per_breach")
	assert_eq(second, 2, "and Wave 2 is the same Wave, because the Factory is the same")


# ── Losing the Run ────────────────────────────────────────────────────────────

func test_a_run_is_not_over_while_the_nest_stands() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_false(sim.query_run_is_over())
	assert_eq(sim.query_run_over_tick(), -1, "no tick ended it")


func test_crawlers_chew_the_nest_down_and_the_run_ends() -> void:
	var sim: Simulation = _quick_sim(40)
	var full: int = sim.query_nest_health()

	var ticks: int = 0
	while not sim.query_run_is_over() and ticks < 2000:
		sim.step([])
		ticks += 1

	assert_true(sim.query_run_is_over(), "the Nest fell within %d ticks" % ticks)
	assert_eq(sim.query_nest_health(), 0, "a destroyed Nest has nothing left")
	assert_true(sim.query_nest_health() < full, "and it was whole when the Run started")
	assert_eq(
		sim.query_run_over_tick(),
		ticks - 1,
		"the Run ended on the tick the last hit point went"
	)


func test_the_run_over_condition_names_the_wave_reached() -> void:
	var sim: Simulation = _one_wave_sim(40)
	while not sim.query_run_is_over():
		sim.step([])
	assert_eq(
		sim.query_wave_number(),
		1,
		"a Nest this thin falls to the first Wave, and the report says which"
	)


func test_a_run_that_has_ended_stays_ended_and_stops_escalating() -> void:
	var sim: Simulation = _quick_sim(40)
	while not sim.query_run_is_over():
		sim.step([])
	var ended_at: int = sim.query_run_over_tick()
	var wave: int = sim.query_wave_number()
	var enemies: int = sim.query_enemy_count()

	for i: int in range(5 * 60 * Simulation.TICKS_PER_SECOND):
		sim.step([])

	assert_true(sim.query_run_is_over(), "a lost Run is not won back by waiting")
	assert_eq(sim.query_run_over_tick(), ended_at, "and the tick it ended on is frozen")
	assert_eq(sim.query_wave_number(), wave, "the Wave reached is the Wave that did it")
	assert_eq(sim.query_enemy_count(), enemies, "no further Wave is sent at a dead Nest")


# ── Fixtures that keep progression out of the way ─────────────────────────────
# The shipped Delivery chain locks the Ammo Press and the MG Turret behind its first tier
# and a Run opens holding exactly the plates for one line (`content/deliveries.csv`,
# `content/tuning.toml`). Both are balance rather than anything asserted in this file, so
# these fixtures replace them with a tier that locks nothing and a stock that pays for
# anything. `test_delivery.gd` is where the real chain is asserted.

const SHIPPED_STOCK: String = 'starting_stock = "iron_plate:80"'
const STOCKED: String = 'starting_stock = "ammunition:400;coal:400;iron_ore:400;iron_plate:400"'

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
