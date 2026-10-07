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


## Shipped content with the Wave clock wound forward and the Nest made of paper, so a
## whole Run fits in a few hundred ticks. Everything else is the real file.
func _quick_content(nest_health: int = 40) -> Definitions:
	return Definitions.parse(
		_read("res://content/machines.csv"),
		_read("res://content/recipes.csv"),
		(
			_read("res://content/tuning.toml")
			. replace("first_wave_seconds = 90", "first_wave_seconds = 1")
			. replace("crawlers_in_first_wave = 6", "crawlers_in_first_wave = 2")
			. replace("spawn_interval_seconds = 0.5", "spawn_interval_seconds = 0.2")
			. replace("health = 6000", "health = %d" % nest_health)
		),
		"machines.csv",
		"recipes.csv",
		"tuning.toml"
	)


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	return text


func _quick_sim(nest_health: int = 40) -> Simulation:
	return Simulation.new(3, 1, _quick_content(nest_health), _layout())


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
		"wave.first_wave_seconds, in ticks"
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


func test_each_wave_sends_more_crawlers_than_the_last() -> void:
	var sim: Simulation = _quick_sim(1000000)
	var first: int = 0
	var second: int = 0
	# Wave 1 arrives after a second; Wave 2 two minutes later. Counted by watching the
	# Wave number change rather than by predicting a tick.
	for i: int in range(3 * 60 * Simulation.TICKS_PER_SECOND):
		var before: int = sim.query_enemy_count()
		sim.step([])
		if sim.query_enemy_count() > before:
			if sim.query_wave_number() == 1:
				first += 1
			elif sim.query_wave_number() == 2:
				second += 1
	assert_eq(first, 2, "the tuned crawlers_in_first_wave")
	assert_eq(
		second,
		2 + 4,
		"plus crawlers_added_per_wave — Waves escalate without bound (GLOSSARY.md)"
	)


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
	var sim: Simulation = _quick_sim(40)
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
