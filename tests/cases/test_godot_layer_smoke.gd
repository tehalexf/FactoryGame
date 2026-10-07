## Smoke coverage for the Godot-side layer.
##
## Per the spec's testing decisions, this layer gets smoke-level coverage only —
## it launches, and it produces Input Actions. It holds no authoritative state, so
## there is nothing else here worth asserting, and assertions about rendering or
## frame timing would be worse than none.
extends TestCase


func test_the_root_constructs_an_empty_simulation() -> void:
	var main: Main = Main.new()
	assert_not_null(main.simulation())
	assert_eq(main.simulation().query_tick(), 0, "a fresh Run starts at tick 0")
	main.free()


func test_driving_frames_advances_the_simulation_in_whole_ticks() -> void:
	var main: Main = Main.new()
	var ticks_run: int = main.advance_frame(1.0 / float(Simulation.TICKS_PER_SECOND))
	assert_eq(ticks_run, 1)
	assert_eq(main.simulation().query_tick(), 1)
	main.free()


func test_a_frame_shorter_than_a_tick_does_not_advance_the_simulation() -> void:
	var main: Main = Main.new()
	main.advance_frame(0.001)
	assert_eq(main.simulation().query_tick(), 0, "the Simulation steps in whole ticks only")
	main.free()


func test_one_second_of_frames_runs_about_one_second_of_ticks() -> void:
	var main: Main = Main.new()
	for frame: int in range(120):
		main.advance_frame(1.0 / 120.0)
	assert_true(
		absi(main.simulation().query_tick() - Simulation.TICKS_PER_SECOND) <= 1,
		"expected about %d ticks, got %d" % [Simulation.TICKS_PER_SECOND, main.simulation().query_tick()]
	)
	main.free()


func test_input_collection_produces_input_actions_and_nothing_else() -> void:
	# Headless with no keys held, so the honest assertion is that the channel
	# exists, returns a list, and that anything in it is an Input Action — never a
	# direct write into Simulation state.
	var main: Main = Main.new()
	var actions: Array = main.collect_input_actions()
	assert_not_null(actions)
	for action: Variant in actions:
		assert_true(action is InputAction, "only Input Actions may cross into the Simulation")
	main.free()


func test_the_simulation_is_only_reachable_through_queries() -> void:
	# A guard on the architecture rather than on behaviour: if someone later adds a
	# setter or exposes state directly, this is the test that should start looking
	# wrong to whoever reads it.
	var main: Main = Main.new()
	var sim: Simulation = main.simulation()

	# Only what the Simulation script itself declares; Object's own methods are
	# not part of the façade's design.
	var unexpected: PackedStringArray = PackedStringArray()
	for method: Dictionary in sim.get_script().get_script_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("_") or method_name.begins_with("query_"):
			continue
		if method_name == "step" or method_name == "hash":
			continue
		unexpected.append(method_name)

	assert_eq(
		unexpected,
		PackedStringArray(),
		"the façade is step, hash and query_* — these do not fit: %s" % str(unexpected)
	)
	main.free()
