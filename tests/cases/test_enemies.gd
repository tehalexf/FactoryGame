## Crawlers: spawning at a Breach, pathing along the shared field, biting the Nest, and
## replaying bit-identically. Through the Simulation façade, which is the only seam.
##
## The architectural claim this file stands behind is that an Enemy is an entry in a set
## of parallel arrays and never a node or an object (ADR 0001). Nothing here can see a
## node, which is the point: the façade hands out integers, and `WorldView` draws them
## with one MultiMesh — `test_world_view` is where that half is asserted.
extends TestCase

## The Nest at the origin covering (0,0) to (3,3), one Breach ten tiles east on the
## Nest's own lane.
func _layout() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(0, WorldGrid.GROUND_LAYER, 0)
	layout.add_breach(Vector3i(10, WorldGrid.GROUND_LAYER, 1))
	layout.sort_breaches()
	return layout


## Shipped content with the Wave clock wound forward, so a Wave fits in a test. Every
## other number is the real file's.
func _content(overrides: Array = []) -> Definitions:
	var tuning: String = _read("res://content/tuning.toml")
	tuning = tuning.replace("first_wave_seconds = 90", "first_wave_seconds = 1")
	for pair: PackedStringArray in overrides:
		tuning = tuning.replace(pair[0], pair[1])
	return Definitions.parse(
		_read("res://content/machines.csv"),
		_read("res://content/recipes.csv"),
		tuning,
		"machines.csv",
		"recipes.csv",
		"tuning.toml"
	)


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	return text


func _sim(overrides: Array = []) -> Simulation:
	return Simulation.new(11, 1, _content(overrides), _layout())


## Steps until there is at least one Enemy on the Map, and reports how many ticks it took.
func _step_until_spawned(sim: Simulation) -> int:
	var ticks: int = 0
	while sim.query_enemy_count() == 0 and ticks < 600:
		sim.step([])
		ticks += 1
	return ticks


# ── Spawning ──────────────────────────────────────────────────────────────────

func test_a_crawler_comes_out_of_the_breach() -> void:
	var sim: Simulation = _sim()
	_step_until_spawned(sim)
	assert_eq(sim.query_enemy_count(), 1, "the first Crawler of Wave 1")
	assert_eq(sim.query_enemy_kind(0), Simulation.ENEMY_KIND_CRAWLER)
	assert_eq(
		sim.query_enemy_tile(0),
		Vector3i(10, WorldGrid.GROUND_LAYER, 1),
		"standing on the Breach it entered at"
	)
	assert_eq(sim.query_enemy_health(0), 30, "enemy.crawler_health")


func test_a_crawler_stands_at_the_centre_of_the_breach_tile() -> void:
	var sim: Simulation = _sim()
	_step_until_spawned(sim)
	var centre: FixedVec2 = WorldGrid.tile_centre_metres(sim.query_breach_tile(0))
	var where: FixedVec2 = sim.query_enemy_position_metres(0)
	assert_eq(where.x, centre.x, "21 m along x, which is the middle of tile 10")
	assert_eq(where.z, centre.z)


func test_a_wave_trickles_out_rather_than_arriving_in_a_stack() -> void:
	var sim: Simulation = _sim()
	_step_until_spawned(sim)
	assert_eq(sim.query_enemy_count(), 1)
	# spawn_interval_seconds is 0.5, so the next one is exactly thirty ticks behind.
	@warning_ignore("integer_division")
	var interval: int = Simulation.TICKS_PER_SECOND / 2
	for i: int in range(interval - 1):
		sim.step([])
	assert_eq(sim.query_enemy_count(), 1, "one tick short of the tuned interval")
	sim.step([])
	assert_eq(sim.query_enemy_count(), 2)


func test_a_wave_stops_once_it_has_sent_what_it_was_going_to_send() -> void:
	var sim: Simulation = _sim()
	for i: int in range(20 * Simulation.TICKS_PER_SECOND):
		sim.step([])
	assert_eq(sim.query_wave_number(), 1, "Wave 2 is two minutes out")
	assert_eq(sim.query_enemy_count(), 6, "wave.crawlers_in_first_wave and no more")
	assert_eq(sim.query_wave_spawns_remaining(), 0)


func test_an_unknown_enemy_reads_as_nothing_rather_than_crashing() -> void:
	var sim: Simulation = _sim()
	assert_eq(sim.query_enemy_count(), 0)
	assert_eq(sim.query_enemy_kind(99), -1, "never a plausible-looking default")
	assert_eq(sim.query_enemy_serial(99), -1)
	assert_eq(sim.query_enemy_health(99), 0)
	assert_eq(sim.query_enemy_tile(99), Vector3i.ZERO)


# ── Pathing ───────────────────────────────────────────────────────────────────

func test_a_crawler_walks_the_shared_field_towards_the_nest() -> void:
	var sim: Simulation = _sim()
	_step_until_spawned(sim)
	var opened_at: int = sim.query_flow_distance_tiles(sim.query_enemy_tile(0))
	assert_eq(opened_at, 7, "ten tiles east of the anchor, seven from the footprint's edge")

	for i: int in range(2 * Simulation.TICKS_PER_SECOND):
		sim.step([])
	var now: int = sim.query_flow_distance_tiles(sim.query_enemy_tile(0))
	assert_true(now < opened_at, "it is closer: %d tiles rather than %d" % [now, opened_at])


func test_a_crawler_moves_at_the_speed_tuning_states() -> void:
	var sim: Simulation = _sim()
	_step_until_spawned(sim)
	var opened_at: FixedVec2 = sim.query_enemy_position_metres(0)
	for i: int in range(Simulation.TICKS_PER_SECOND):
		sim.step([])
	var travelled: int = opened_at.x - sim.query_enemy_position_metres(0).x
	# enemy.crawler_speed_metres_per_second is 3, floored to a whole number of
	# sub-metres a tick, so a second of walking is a shade under 3 m and never over it.
	assert_true(
		travelled <= Fixed.from_int(3) and travelled > Fixed.from_int(3) - Fixed.from_int(1) / 100,
		"3 m in a second, floored: %d" % travelled
	)
	assert_eq(sim.query_enemy_position_metres(0).z, opened_at.z, "and it stayed in its lane")


func test_a_crawler_reaches_the_nest() -> void:
	var sim: Simulation = _sim()
	_step_until_spawned(sim)
	var ticks: int = 0
	while not sim.query_enemy_is_attacking(0) and ticks < 900:
		sim.step([])
		ticks += 1
	assert_true(sim.query_enemy_is_attacking(0), "in contact after %d ticks" % ticks)
	assert_eq(
		sim.query_flow_distance_tiles(sim.query_enemy_tile(0)),
		1,
		"one tile from the footprint, which is biting range"
	)


func test_a_crawler_walks_round_a_machine_in_its_way() -> void:
	var sim: Simulation = _sim([["crawlers_in_first_wave = 6", "crawlers_in_first_wave = 1"]])
	# A 3x3 Smelter squarely across the Breach-to-Nest lane.
	var smelter: int = sim.query_definitions().machine_index("smelter_mk1")
	sim.step([InputAction.build_machine(0, smelter, Vector3i(5, WorldGrid.GROUND_LAYER, 0))])
	assert_eq(sim.query_machine_count(), 1)

	_step_until_spawned(sim)
	var through_the_machine: bool = false
	var ticks: int = 0
	while not sim.query_enemy_is_attacking(0) and ticks < 1200:
		sim.step([])
		ticks += 1
		if sim.query_tile_obstructs_enemies(sim.query_enemy_tile(0)):
			through_the_machine = true
	assert_false(through_the_machine, "it never stood on a tile the Machine occupies")
	assert_true(sim.query_enemy_is_attacking(0), "and still arrived, after %d ticks" % ticks)


func test_a_machine_dropped_on_a_crawler_does_not_park_it_for_ever() -> void:
	# The field has no direction for a tile inside an obstruction, so without a fallback
	# a player could pin a Crawler by building over it. That is a cheese, not a defence.
	var sim: Simulation = _sim()
	_step_until_spawned(sim)
	var smelter: int = sim.query_definitions().machine_index("smelter_mk1")
	sim.step([InputAction.build_machine(0, smelter, sim.query_enemy_tile(0))])
	assert_true(
		sim.query_tile_obstructs_enemies(sim.query_enemy_tile(0)),
		"it is standing inside the new Machine"
	)
	assert_eq(sim.query_flow_direction(sim.query_enemy_tile(0)), -1, "with no route out")

	var opened_at: FixedVec2 = sim.query_enemy_position_metres(0)
	for i: int in range(Simulation.TICKS_PER_SECOND):
		sim.step([])
	assert_true(
		sim.query_enemy_position_metres(0).x < opened_at.x,
		"and it walked straight at the Nest anyway"
	)


# ── Biting the Nest ───────────────────────────────────────────────────────────

func test_a_crawler_damages_the_nest_on_contact_and_not_before() -> void:
	var sim: Simulation = _sim([["crawlers_in_first_wave = 6", "crawlers_in_first_wave = 1"]])
	_step_until_spawned(sim)
	var full: int = sim.query_nest_health()

	while not sim.query_enemy_is_attacking(0):
		assert_eq(sim.query_nest_health(), full, "untouched while the Crawler is still walking")
		sim.step([])

	sim.step([])
	assert_eq(
		sim.query_nest_health(),
		full - 10,
		"enemy.crawler_damage, taken on the first tick of contact"
	)


func test_a_crawler_bites_at_the_interval_tuning_states() -> void:
	var sim: Simulation = _sim([["crawlers_in_first_wave = 6", "crawlers_in_first_wave = 1"]])
	while not sim.query_enemy_is_attacking(0):
		sim.step([])
	sim.step([])
	var after_one_bite: int = sim.query_nest_health()

	for i: int in range(Simulation.TICKS_PER_SECOND - 1):
		sim.step([])
	assert_eq(sim.query_nest_health(), after_one_bite, "one tick short of the tuned second")
	sim.step([])
	assert_eq(sim.query_nest_health(), after_one_bite - 10, "and then it bites again")


func test_a_crawler_in_contact_stops_walking() -> void:
	var sim: Simulation = _sim([["crawlers_in_first_wave = 6", "crawlers_in_first_wave = 1"]])
	while not sim.query_enemy_is_attacking(0):
		sim.step([])
	var standing: FixedVec2 = sim.query_enemy_position_metres(0)
	for i: int in range(60):
		sim.step([])
	assert_eq(sim.query_enemy_position_metres(0).x, standing.x, "it is chewing, not walking")
	assert_eq(sim.query_enemy_position_metres(0).z, standing.z)


func test_a_swarm_chews_faster_than_one_crawler_does() -> void:
	var one: Simulation = _sim([["crawlers_in_first_wave = 6", "crawlers_in_first_wave = 1"]])
	var many: Simulation = _sim()
	for i: int in range(30 * Simulation.TICKS_PER_SECOND):
		one.step([])
		many.step([])
	assert_eq(one.query_enemy_count(), 1)
	assert_eq(many.query_enemy_count(), 6)
	assert_true(
		many.query_nest_health() < one.query_nest_health(),
		"six Crawlers did more damage than one: %d left against %d"
		% [many.query_nest_health(), one.query_nest_health()]
	)


# ── Determinism of the Enemy order ────────────────────────────────────────────

func test_enemy_index_order_is_always_ascending_spawn_order() -> void:
	# The invariant the whole Enemy loop rests on, asserted directly rather than trusted
	# to a comment: the purity lint catches a float and would never catch an ordering bug.
	var sim: Simulation = _sim()
	for i: int in range(20 * Simulation.TICKS_PER_SECOND):
		sim.step([])
		for index: int in range(1, sim.query_enemy_count()):
			assert_true(
				sim.query_enemy_serial(index) > sim.query_enemy_serial(index - 1),
				"serial at %d is not above the one before it" % index
			)
			assert_true(
				sim.query_enemy_spawn_tick(index) >= sim.query_enemy_spawn_tick(index - 1),
				"spawn ticks run forward with the index too"
			)
	assert_eq(sim.query_enemy_count(), 6, "and the whole Wave was walked")


func test_a_serial_is_issued_once_and_never_reused() -> void:
	var sim: Simulation = _sim()
	for i: int in range(20 * Simulation.TICKS_PER_SECOND):
		sim.step([])
	assert_eq(sim.query_enemy_serial(0), 0, "the first Crawler of the Run")
	assert_eq(
		sim.query_enemy_serial(5),
		5,
		"and the sixth carries 5 — a serial is a stable identity across the ticks an"
		+ " Enemy exists for, which indices are not"
	)


func test_two_runs_spawn_the_same_enemies_in_the_same_order() -> void:
	var one: Simulation = _sim()
	var two: Simulation = _sim()
	for i: int in range(20 * Simulation.TICKS_PER_SECOND):
		one.step([])
		two.step([])
		assert_eq(one.hash(), two.hash(), "diverged at tick %d" % one.query_tick())
	assert_eq(one.query_enemy_count(), 6)


func test_a_breach_releases_its_crawlers_in_canonical_tile_order() -> void:
	# Two Breaches added in opposite orders. `MapLayout.sort_breaches` puts them into tile
	# order, so which one releases first is geography rather than authoring order — and
	# two clients therefore issue the same serials to the same Enemies.
	var west_first: MapLayout = MapLayout.new()
	west_first.nest_tile = Vector3i(0, WorldGrid.GROUND_LAYER, 0)
	west_first.add_breach(Vector3i(-10, WorldGrid.GROUND_LAYER, 1))
	west_first.add_breach(Vector3i(10, WorldGrid.GROUND_LAYER, 1))
	west_first.sort_breaches()

	var east_first: MapLayout = MapLayout.new()
	east_first.nest_tile = Vector3i(0, WorldGrid.GROUND_LAYER, 0)
	east_first.add_breach(Vector3i(10, WorldGrid.GROUND_LAYER, 1))
	east_first.add_breach(Vector3i(-10, WorldGrid.GROUND_LAYER, 1))
	east_first.sort_breaches()

	var one: Simulation = Simulation.new(11, 1, _content(), west_first)
	var two: Simulation = Simulation.new(11, 1, _content(), east_first)
	_step_until_spawned(one)
	_step_until_spawned(two)
	assert_eq(one.query_enemy_count(), 2, "one beat releases a Crawler at every Breach")
	assert_eq(
		one.query_enemy_tile(0),
		Vector3i(-10, WorldGrid.GROUND_LAYER, 1),
		"and the lower tile goes first, so it holds the lower serial"
	)

	for i: int in range(Simulation.TICKS_PER_SECOND):
		one.step([])
		two.step([])
	assert_eq(one.query_enemy_count(), 6, "three beats of a Wave, at two Breaches")
	assert_eq(one.hash(), two.hash(), "and the order the rows were typed in reached nothing")


func test_every_enemy_is_part_of_the_state_hash() -> void:
	var sim: Simulation = _sim()
	_step_until_spawned(sim)
	var standing: int = sim.hash()
	sim.step([])
	assert_ne(
		sim.hash(),
		standing,
		"a Crawler that moved is a Simulation in a different state"
	)


# ── Replay fixtures ───────────────────────────────────────────────────────────

func test_determinism_crawlers_spawn_and_path_identically_on_a_replay() -> void:
	# Deliberately against the *shipped* content, with no definitions passed, so the
	# replay re-reads content/ and a change to the Wave or Crawler tuning is reported as a
	# definitions mismatch rather than passing unnoticed (CLAUDE.md).
	var script: InputScript = InputScript.new()
	script.add_tick([InputAction.build_machine(0, _shipped_index("smelter_mk1"), Vector3i(4, 0, -8))])
	# Far enough to clear the 90 s first Wave and watch the whole of it walk.
	script.add_idle_ticks(100 * Simulation.TICKS_PER_SECOND)

	var recording: ReplayRecording = DeterminismHarness.record(script, 4, 1)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_the_fixture_really_did_spawn_and_walk_crawlers() -> void:
	# A fixture that proved determinism over a Run in which nothing happened would prove
	# nothing, so the scenario is checked separately from the replay.
	var sim: Simulation = Simulation.new(4, 1)
	sim.step([InputAction.build_machine(0, _shipped_index("smelter_mk1"), Vector3i(4, 0, -8))])
	var moved: int = 0
	var first_position: FixedVec2 = FixedVec2.zero()
	for i: int in range(100 * Simulation.TICKS_PER_SECOND):
		sim.step([])
		if sim.query_enemy_count() > 0:
			if first_position.x == 0:
				first_position = sim.query_enemy_position_metres(0)
			elif sim.query_enemy_position_metres(0).x != first_position.x:
				moved = 1
	assert_eq(sim.query_wave_number(), 1, "the shipped first Wave arrived")
	assert_eq(sim.query_enemy_count(), 6, "with its full complement of Crawlers")
	assert_eq(moved, 1, "and the leading one walked")
	assert_false(sim.query_run_is_over(), "a 100-second Run does not lose the Nest yet")


func test_determinism_a_run_that_ends_replays_identically() -> void:
	# A thin Nest and a fast Wave, so the Run is lost inside the fixture. Content is
	# passed here rather than read from content/, because the shipped numbers take some
	# minutes to lose and a fixture should be seconds.
	var content: Definitions = _content([["health = 6000", "health = 40"]])
	assert_false(content.has_errors(), content.describe_errors())

	var script: InputScript = InputScript.new()
	script.add_idle_ticks(20 * Simulation.TICKS_PER_SECOND)

	var recording: ReplayRecording = DeterminismHarness.record(script, 9, 1, content)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())

	# And the Run really did end inside it, rather than the fixture proving a quiet Map
	# replays quietly. The layout the harness builds is the starter Map, so this walks the
	# same script by hand against the same content.
	var sim: Simulation = Simulation.new(9, 1, content)
	for i: int in range(20 * Simulation.TICKS_PER_SECOND):
		sim.step([])
	assert_true(sim.query_run_is_over(), "the Nest fell during the fixture")
	assert_eq(sim.query_wave_number(), 1, "on Wave 1, which is what the report names")


func _shipped_index(machine_id: String) -> int:
	return Definitions.load_from_directory(Definitions.CONTENT_DIR).machine_index(machine_id)
