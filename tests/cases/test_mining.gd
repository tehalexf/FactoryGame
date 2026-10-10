## Nodes, Miners and extraction, through the Simulation façade.
extends TestCase


func test_the_map_holds_nodes() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_true(sim.query_node_count() > 0, "the Map holds Nodes (GLOSSARY.md)")


func test_a_node_exposes_a_resource_and_a_depth_tier() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var resource_id: String = sim.query_node_resource(0)
	assert_eq(resource_id, "iron_ore", "the starter Map's first Node is iron ore")
	assert_eq(sim.query_node_depth(0), 1, "Depth tiers start at 1")


func test_a_node_sits_on_a_buildable_tile() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	for index: int in range(sim.query_node_count()):
		var tile: Vector3i = sim.query_node_tile(index)
		assert_true(
			sim.query_is_buildable_tile(tile),
			"Node %d is at %s, which cannot be built on" % [index, tile]
		)


func test_an_unknown_node_reads_as_nothing_rather_than_crashing() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_eq(sim.query_node_resource(99), "")
	assert_eq(sim.query_node_depth(99), 0)


func test_a_tile_names_the_node_on_it() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var tile: Vector3i = sim.query_node_tile(0)
	assert_eq(sim.query_node_at_tile(tile), 0)
	assert_eq(
		sim.query_node_at_tile(Vector3i(tile.x, tile.y, tile.z + 1000)),
		-1,
		"a tile with no Node on it names none"
	)


# ── Placing a Machine ─────────────────────────────────────────────────────────

## A Miner anchored on the Map's first Node, so its 2x2 footprint covers that tile.
func _build_miner_on_first_node(sim: Simulation) -> void:
	sim.step([InputAction.build_machine(0, _miner_index(sim), sim.query_node_tile(0))])


func _miner_index(sim: Simulation) -> int:
	return sim.query_definitions().machine_index("miner_mk1")


func test_a_built_machine_appears_on_the_grid() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_eq(sim.query_machine_count(), 0, "a Run starts with no Machines built")
	_build_miner_on_first_node(sim)
	assert_eq(sim.query_machine_count(), 1)
	assert_eq(sim.query_machine_id(0), "miner_mk1")
	assert_eq(sim.query_machine_tile(0), sim.query_node_tile(0))


func test_a_machine_occupies_the_footprint_its_definition_states() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	_build_miner_on_first_node(sim)
	# machines.csv gives miner_mk1 a 2x2 footprint, and that file is the only
	# authority for it.
	var origin: Vector3i = sim.query_node_tile(0)
	for offset_x: int in range(2):
		for offset_z: int in range(2):
			var tile: Vector3i = Vector3i(origin.x + offset_x, origin.y, origin.z + offset_z)
			assert_eq(sim.query_machine_at_tile(tile), 0, "%s should be occupied" % tile)
	assert_eq(
		sim.query_machine_at_tile(Vector3i(origin.x + 2, origin.y, origin.z)),
		-1,
		"a 2x2 Miner does not reach three tiles"
	)


func test_a_machine_cannot_be_built_overlapping_another() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	_build_miner_on_first_node(sim)
	var origin: Vector3i = sim.query_node_tile(0)
	sim.step([
		InputAction.build_machine(0, _miner_index(sim), Vector3i(origin.x + 1, origin.y, origin.z))
	])
	assert_eq(sim.query_machine_count(), 1, "the overlapping build is refused")


func test_a_machine_cannot_be_built_off_the_ground_layer() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.build_machine(0, _miner_index(sim), Vector3i(0, 1, 0))])
	assert_eq(sim.query_machine_count(), 0, "only layer 0 is buildable")


func test_a_machine_cannot_be_built_off_the_map() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var outside: int = sim.query_grid_half_extent_tiles() + 1
	sim.step([InputAction.build_machine(0, _miner_index(sim), Vector3i(outside, 0, 0))])
	assert_eq(sim.query_machine_count(), 0)


func test_a_build_naming_no_machine_is_refused_rather_than_fatal() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.build_machine(0, 99, Vector3i(0, 0, 0))])
	assert_eq(sim.query_machine_count(), 0, "a malformed action degrades to a no-op")


# ── Extracting ────────────────────────────────────────────────────────────────
# recipes.csv gives mine_iron_ore a duration of 1.5 s, and the Simulation runs at
# 60 ticks a second, so one iron ore lands every 90 ticks. Every expected value
# below is worked from those two numbers.

const TICKS_PER_ORE: int = 90


func _run(sim: Simulation, ticks: int) -> void:
	for tick: int in range(ticks):
		sim.step([])


func test_a_miner_on_a_node_extracts_its_resource_at_the_rate_its_recipe_states() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	_build_miner_on_first_node(sim)
	_run(sim, TICKS_PER_ORE)
	assert_eq(sim.query_machine_output(0, "iron_ore"), 1, "one craft, one ore")
	_run(sim, TICKS_PER_ORE * 5)
	assert_eq(sim.query_machine_output(0, "iron_ore"), 6, "six crafts in nine seconds")


func test_a_miner_produces_nothing_until_a_craft_finishes() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	_build_miner_on_first_node(sim)
	_run(sim, TICKS_PER_ORE - 1)
	assert_eq(sim.query_machine_output(0, "iron_ore"), 0, "a craft pays out whole, or not yet")
	assert_eq(sim.query_machine_output_total(0), 0)


func test_a_miner_not_on_a_node_does_not_produce() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var bare: Vector3i = Vector3i(20, 0, 20)
	assert_eq(sim.query_node_at_tile(bare), -1, "the test's tile must really be bare")
	sim.step([InputAction.build_machine(0, _miner_index(sim), bare)])
	_run(sim, TICKS_PER_ORE * 4)
	assert_eq(sim.query_machine_output_total(0), 0, "a Miner's input is the Node under it")


func test_a_miner_extracts_only_what_the_node_under_it_yields() -> void:
	var elsewhere: MapLayout = MapLayout.empty()
	elsewhere.add_node(Vector3i(0, 0, 0), "coal", 1)
	elsewhere.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, elsewhere)
	_build_miner_on_first_node(sim)
	_run(sim, TICKS_PER_ORE * 4)
	assert_eq(
		sim.query_machine_output_total(0),
		0,
		"miner_mk1 mines iron ore, and this Node holds coal"
	)


func test_a_node_never_depletes() -> void:
	# Inexhaustibility is a design decision (DESIGN.md): a 40-hour Factory must never
	# need relocating, so a Node that has given up 100 ore gives up the 101st at the
	# same rate as the first.
	var sim: Simulation = Simulation.new(1, 1)
	_build_miner_on_first_node(sim)
	_run(sim, TICKS_PER_ORE * 100)
	assert_eq(sim.query_machine_output(0, "iron_ore"), 100)
	_run(sim, TICKS_PER_ORE)
	assert_eq(sim.query_machine_output(0, "iron_ore"), 101, "the rate did not fall off")


func test_a_miner_reports_the_resource_it_is_holding() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	_build_miner_on_first_node(sim)
	_run(sim, TICKS_PER_ORE * 2)
	assert_eq(sim.query_machine_output_items(0), PackedStringArray(["iron_ore"]))
	assert_eq(sim.query_machine_output_total(0), 2)
	assert_eq(sim.query_item_total("iron_ore"), 2, "the Factory's total, across Machines")
	assert_eq(sim.query_machine_output(0, "steel_plate"), 0, "an Item it never made reads as none")


# ── Determinism ───────────────────────────────────────────────────────────────

func test_building_a_machine_changes_the_hash() -> void:
	var built: Simulation = Simulation.new(1, 1)
	var bare: Simulation = Simulation.new(1, 1)
	_build_miner_on_first_node(built)
	bare.step([])
	assert_ne(built.hash(), bare.hash(), "a Factory is state")


func test_a_refused_build_leaves_the_hash_where_it_was() -> void:
	var refused: Simulation = Simulation.new(1, 1)
	var idle: Simulation = Simulation.new(1, 1)
	refused.step([InputAction.build_machine(0, _miner_index(refused), Vector3i(0, 1, 0))])
	idle.step([])
	assert_eq(refused.hash(), idle.hash(), "a refused build is not a build")


func test_what_a_miner_has_extracted_reaches_the_hash() -> void:
	var productive: Simulation = Simulation.new(1, 1)
	var idle: Simulation = Simulation.new(1, 1)
	_build_miner_on_first_node(productive)
	idle.step([InputAction.build_machine(0, _miner_index(idle), Vector3i(20, 0, 20))])
	_run(productive, TICKS_PER_ORE)
	_run(idle, TICKS_PER_ORE)
	assert_eq(idle.query_machine_output_total(0), 0, "the idle Miner is on bare rock")
	assert_ne(
		productive.hash(),
		idle.hash(),
		"an output buffer the hash cannot see is a desync the harness cannot see"
	)


func test_determinism_a_miner_extracting_replays_identically() -> void:
	# The ticket's replay fixture: build a Miner on a Node, let it run through several
	# crafts, and prove the hash matches tick for tick. No `Definitions` is passed, so
	# the replay re-reads content/ and a content change is reported as a
	# definitions_mismatch rather than passing unnoticed.
	var sim: Simulation = Simulation.new(7, 1)
	var script: InputScript = InputScript.new()
	script.add_tick([InputAction.build_machine(0, _miner_index(sim), sim.query_node_tile(0))])
	script.add_idle_ticks(TICKS_PER_ORE * 3)
	script.add_tick([InputAction.move(0, Fixed.ONE, 0)])
	script.add_idle_ticks(TICKS_PER_ORE)

	var recording: ReplayRecording = DeterminismHarness.record(script, 7, 1)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_two_runs_of_the_same_build_order_agree() -> void:
	var first: Simulation = Simulation.new(3, 1)
	var second: Simulation = Simulation.new(3, 1)
	for sim: Simulation in [first, second]:
		sim.step([InputAction.build_machine(0, _miner_index(sim), sim.query_node_tile(1))])
		_run(sim, TICKS_PER_ORE * 2)
	assert_eq(first.hash(), second.hash())
	assert_eq(first.query_machine_output(0, "iron_ore"), second.query_machine_output(0, "iron_ore"))
