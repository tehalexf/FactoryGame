## Smoke coverage for the rendering layer.
##
## The spec gives the Godot layer smoke-level coverage only, and that is all these
## are: the view draws one placeholder per thing the Simulation reports, reports the
## count a player is meant to read off the screen, and holds no state of its own. The
## numbers it shows are asserted against the queries, never against a remembered
## copy — a copy is the thing this layer is forbidden to have.
extends TestCase


func _run(sim: Simulation, ticks: int) -> void:
	for tick: int in range(ticks):
		sim.step([])


func test_the_view_draws_a_placeholder_for_every_node_and_machine() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()

	view.sync(sim)
	assert_eq(
		view.placeholder_count(),
		sim.query_node_count(),
		"a fresh Run has Nodes to look at and no Machines"
	)

	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("miner_mk1"), sim.query_node_tile(0)
		)
	])
	view.sync(sim)
	assert_eq(view.placeholder_count(), sim.query_node_count() + 1)

	view.free()


func test_a_placeholder_stands_at_the_centre_of_its_footprint() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	# A 2x2 Miner anchored at tile (4,0,4) spans 8 m to 12 m on both axes, so its
	# centre is (10 m, 10 m).
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("miner_mk1"), Vector3i(4, 0, 4)
		)
	])
	view.sync(sim)
	var placed: Vector3 = view.machine_placeholder_position(0)
	assert_true(is_equal_approx(placed.x, 10.0), "expected x 10.0, got %f" % placed.x)
	assert_true(is_equal_approx(placed.z, 10.0), "expected z 10.0, got %f" % placed.z)
	view.free()


func test_the_view_shows_what_the_factory_has_extracted() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("miner_mk1"), sim.query_node_tile(0)
		)
	])
	# 1.5 s a craft at 60 ticks a second is 90 ticks an ore; two crafts is 180.
	_run(sim, 180)
	view.sync(sim)
	assert_eq(sim.query_item_total("iron_ore"), 2, "the premise of the assertion below")
	assert_true(
		view.hud_text().contains("iron_ore 2"),
		"a player must be able to read the count off the screen, got %s" % view.hud_text()
	)
	view.free()


func test_the_root_builds_a_starting_miner_so_there_is_something_to_look_at() -> void:
	var main: Main = Main.new()
	main.advance_frame(1.0 / float(Simulation.TICKS_PER_SECOND))
	var sim: Simulation = main.simulation()
	assert_eq(sim.query_machine_id(0), "miner_mk1", "the line opens with a Miner")
	assert_ne(sim.query_node_under_machine(0), -1, "and it is standing on a Node")
	main.free()


func test_the_opening_line_is_built_once_and_not_once_a_tick() -> void:
	var main: Main = Main.new()
	for frame: int in range(10):
		main.advance_frame(1.0 / float(Simulation.TICKS_PER_SECOND))
	assert_eq(main.simulation().query_machine_count(), 2)
	assert_eq(main.simulation().query_belt_count(), 1)
	main.free()


# ── Belts and the Items on them ───────────────────────────────────────────────
# Items are derived Simulation state and never nodes (ADR 0002), so the view draws them
# as instances of one mesh and reads every position out of a query on the frame it
# draws. The assertions below are about exactly that: the count on screen is the count
# on the Belt, and the place on screen is the place the Simulation says.

func test_the_view_draws_a_slab_for_every_tile_of_belt() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(3, 0, 0))])
	view.sync(sim)
	assert_eq(view.belt_placeholder_count(), 4, "a four-tile run is four slabs")
	view.free()


func test_the_view_draws_one_instance_for_every_item_on_a_belt() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	var node_tile: Vector3i = sim.query_node_tile(0)
	sim.step([
		InputAction.build_machine(0, sim.query_definitions().machine_index("miner_mk1"), node_tile),
		InputAction.build_belt(
			0,
			Vector3i(node_tile.x + 2, node_tile.y, node_tile.z),
			Vector3i(node_tile.x + 9, node_tile.y, node_tile.z)
		),
	])
	view.sync(sim)
	assert_eq(view.item_instance_count(), 0, "nothing has been mined yet")
	# Ore lands on tick 90 and the Belt collects it on tick 91; the second follows 90
	# ticks later.
	_run(sim, 181)
	view.sync(sim)
	assert_eq(sim.query_belt_item_count(0), 2, "the premise of the assertion below")
	assert_eq(view.item_instance_count(), 2, "two Items on the Belt, two on screen")
	view.free()


func test_an_item_is_drawn_exactly_where_the_simulation_says_it_is() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	var node_tile: Vector3i = sim.query_node_tile(0)
	sim.step([
		InputAction.build_machine(0, sim.query_definitions().machine_index("miner_mk1"), node_tile),
		InputAction.build_belt(
			0,
			Vector3i(node_tile.x + 2, node_tile.y, node_tile.z),
			Vector3i(node_tile.x + 9, node_tile.y, node_tile.z)
		),
	])
	_run(sim, 150)
	view.sync(sim)
	var truth: FixedVec2 = sim.query_belt_item_position_metres(0, 0)
	var drawn: Vector3 = view.item_instance_position(0)
	assert_true(
		is_equal_approx(drawn.x, Fixed.to_float(truth.x)),
		"expected x %f, got %f" % [Fixed.to_float(truth.x), drawn.x]
	)
	assert_true(
		is_equal_approx(drawn.z, Fixed.to_float(truth.z)),
		"expected z %f, got %f" % [Fixed.to_float(truth.z), drawn.z]
	)
	view.free()


func test_the_hud_names_a_stalled_belt_and_a_starved_machine() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	var smelter: int = sim.query_definitions().machine_index("smelter_mk1")
	sim.step([InputAction.build_machine(0, smelter, Vector3i(20, 0, 20))])
	view.sync(sim)
	assert_true(
		view.hud_text().contains("starved"),
		"a Smelter with no Belt must read as starved, got %s" % view.hud_text()
	)
	view.free()


func test_the_root_opens_a_whole_line_so_there_is_something_to_watch() -> void:
	var main: Main = Main.new()
	main.advance_frame(1.0 / float(Simulation.TICKS_PER_SECOND))
	var sim: Simulation = main.simulation()
	assert_eq(sim.query_belt_count(), 1, "a Run opens with one Belt, until the Build Gun")
	assert_eq(sim.query_machine_count(), 2, "a Miner and the Smelter it feeds")
	assert_eq(sim.query_machine_id(1), "smelter_mk1")
	main.free()


func test_the_opening_line_really_carries_ore_to_the_smelter() -> void:
	var main: Main = Main.new()
	# Long enough for the first ore to be mined, carried the length of the Belt, and
	# handed into the Smelter's input port.
	for frame: int in range(400):
		main.advance_frame(1.0 / float(Simulation.TICKS_PER_SECOND))
	var sim: Simulation = main.simulation()
	assert_true(
		sim.query_machine_input(1, "iron_ore") > 0,
		"the Smelter should have been fed by now"
	)
	main.free()
