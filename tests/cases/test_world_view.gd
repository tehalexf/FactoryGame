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
	assert_eq(sim.query_machine_count(), 1, "a Run opens with one Miner, until the Build Gun")
	assert_eq(sim.query_machine_id(0), "miner_mk1")
	assert_ne(sim.query_node_under_machine(0), -1, "and it is standing on a Node")
	main.free()


func test_the_starting_miner_is_built_once_and_not_once_a_tick() -> void:
	var main: Main = Main.new()
	for frame: int in range(10):
		main.advance_frame(1.0 / float(Simulation.TICKS_PER_SECOND))
	assert_eq(main.simulation().query_machine_count(), 1)
	main.free()
