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


# ── The player controller ─────────────────────────────────────────────────────
# The input producer. Every player action leaves it as an Input Action and nothing else,
# which is the acceptance criterion this case exists to hold.
#
# Device *polling* is not tested: headless reports no key as held, so there would be
# nothing to assert. The translation is, by handing it a device sample built by hand.

func _sample() -> PlayerController.DeviceSample:
	return PlayerController.DeviceSample.new()


func test_every_action_the_controller_produces_is_an_input_action() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()

	var sample: PlayerController.DeviceSample = _sample()
	sample.forward = 1.0
	sample.mouse_motion = Vector2(12.0, -3.0)
	sample.place_clicked = true
	sample.rotate_steps = 1
	sample.machine_steps = 1
	sample.demolish_clicked = true
	sample.survey_held = true

	var actions: Array = controller.actions_for_tick(sim, 0, sample)
	assert_true(actions.size() >= 6, "every reading should have produced an intent")
	for action: Variant in actions:
		assert_true(action is InputAction, "only Input Actions may cross into the Simulation")


func test_mouse_travel_becomes_a_look_intent_and_turns_the_player() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	var sample: PlayerController.DeviceSample = _sample()
	sample.mouse_motion = Vector2(1000.0, 0.0)

	sim.step(controller.actions_for_tick(sim, 0, sample))
	# 1000 pixels is exactly the sensitivity's own unit, so the player turns by
	# whatever one unit is worth — 0.2 of a turn at the shipped setting, clockwise.
	# 0.2 in fixed point is 13107.2, which floors to 13107.
	assert_eq(sim.query_player_yaw_turns(0), Fixed.TURN - 13107)


func test_a_held_key_becomes_a_walk_intent() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	var sample: PlayerController.DeviceSample = _sample()
	sample.forward = 1.0

	sim.step(controller.actions_for_tick(sim, 0, sample))
	assert_true(sim.query_player_velocity(0).z < 0, "forward at yaw 0 is -z")


func test_a_click_builds_whatever_the_build_gun_is_aimed_at() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	var aimed: Vector3i = BuildGun.aimed_tile(sim, 0)

	var sample: PlayerController.DeviceSample = _sample()
	sample.place_clicked = true
	sim.step(controller.actions_for_tick(sim, 0, sample))

	assert_eq(sim.query_machine_count(), 1, "the click placed a Machine")
	assert_eq(sim.query_machine_tile(0), aimed, "on the tile the gun was pointing at")
	assert_eq(
		sim.query_machine_id(0),
		sim.query_definitions().machine_ids()[0],
		"the one a fresh Run opens with on the Build Gun"
	)


func test_a_second_click_on_the_same_spot_builds_nothing_more() -> void:
	# A refused build is a silent no-op. The reason is on screen already, because the
	# hologram was red before the player clicked.
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	var sample: PlayerController.DeviceSample = _sample()
	sample.place_clicked = true
	sim.step(controller.actions_for_tick(sim, 0, sample))
	sim.step(controller.actions_for_tick(sim, 0, sample))
	assert_eq(sim.query_machine_count(), 1)


func test_rotating_and_placing_in_one_tick_places_the_rotation_the_player_can_see() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	var sample: PlayerController.DeviceSample = _sample()
	sample.rotate_steps = 1
	sample.place_clicked = true

	sim.step(controller.actions_for_tick(sim, 0, sample))
	assert_eq(sim.query_machine_count(), 1, "the premise of the assertion below")
	assert_eq(
		sim.query_machine_rotation(0),
		1,
		"the Machine lands turned, not with the rotation it had before the click"
	)


func test_the_wheel_steps_through_the_machines_and_wraps() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	var count: int = sim.query_definitions().machine_count()
	assert_true(count >= 2, "the premise of the rest")

	var ids: PackedStringArray = sim.query_definitions().machine_ids()
	var sample: PlayerController.DeviceSample = _sample()
	sample.machine_steps = 1
	sim.step(controller.actions_for_tick(sim, 0, sample))
	assert_eq(sim.query_player_selected_machine(0), ids[1], "one step is the next by id")

	# A full lap of the list comes back to where it started, rather than running off the
	# end of the Machine table.
	for step: int in range(count):
		sim.step(controller.actions_for_tick(sim, 0, sample))
	assert_eq(sim.query_player_selected_machine(0), ids[1], "stepping all the way wraps")


func test_a_demolish_returns_the_materials_the_build_spent() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	var stock: int = sim.query_player_item(0, "iron_plate")

	var building: PlayerController.DeviceSample = _sample()
	building.place_clicked = true
	sim.step(controller.actions_for_tick(sim, 0, building))
	assert_true(sim.query_player_item(0, "iron_plate") < stock, "building spent materials")

	var wrecking: PlayerController.DeviceSample = _sample()
	wrecking.demolish_clicked = true
	sim.step(controller.actions_for_tick(sim, 0, wrecking))
	assert_eq(sim.query_machine_count(), 0, "the Machine is gone")
	assert_eq(sim.query_player_item(0, "iron_plate"), stock, "and every plate came back")


func test_survey_view_is_sent_every_tick_so_the_simulation_knows_it_is_still_held() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	var holding: PlayerController.DeviceSample = _sample()
	holding.survey_held = true

	for tick: int in range(30):
		sim.step(controller.actions_for_tick(sim, 0, holding))
	assert_true(sim.query_player_is_surveying(0))
	assert_true(
		sim.query_player_survey_blend(0) == Fixed.ONE,
		"thirty ticks is past the tuned transition"
	)

	for tick: int in range(30):
		sim.step(controller.actions_for_tick(sim, 0, _sample()))
	assert_false(sim.query_player_is_surveying(0), "and letting go brings it back down")
	assert_eq(sim.query_player_survey_blend(0), 0)


func test_building_is_possible_while_surveying_because_there_is_no_mode() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	var surveying: PlayerController.DeviceSample = _sample()
	surveying.survey_held = true
	for tick: int in range(30):
		sim.step(controller.actions_for_tick(sim, 0, surveying))

	surveying.place_clicked = true
	sim.step(controller.actions_for_tick(sim, 0, surveying))
	assert_eq(sim.query_machine_count(), 1, "a raised camera is not a mode that gates building")


func test_a_device_reading_is_spent_exactly_once() -> void:
	# The controller's one piece of state is a device buffer, and a buffer that was not
	# drained would turn one click into a Machine a tick.
	var controller: PlayerController = PlayerController.new()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(7.0, 11.0)
	controller.note_event(motion)

	assert_eq(controller.sample_devices().mouse_motion, Vector2(7.0, 11.0))
	assert_eq(controller.sample_devices().mouse_motion, Vector2.ZERO, "and not a second time")


func test_a_belt_key_lays_a_run_along_the_way_the_player_is_looking() -> void:
	# Belts have no row in `content/machines.csv` and so cannot sit on the Build Gun's
	# Machine list. Until the Belt routing UI arrives — DESIGN.md puts routing in a menu —
	# one key lays a fixed-length run from the aimed tile along the player's facing, which
	# is enough for a player to build the Miner-Belt-Smelter line by hand.
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	var aimed: Vector3i = BuildGun.aimed_tile(sim, 0)

	var sample: PlayerController.DeviceSample = _sample()
	sample.belt_clicked = true
	sim.step(controller.actions_for_tick(sim, 0, sample))

	assert_eq(sim.query_belt_count(), 1, "a Belt was laid")
	assert_eq(sim.query_belt_tile(0, 0), aimed, "starting at the tile the gun was aimed at")
	assert_eq(
		sim.query_belt_length_tiles(0),
		PlayerController.BELT_RUN_TILES,
		"and running the fixed length"
	)
	assert_eq(
		sim.query_belt_direction(0),
		WorldGrid.direction_from_turns(sim.query_player_yaw_turns(0)),
		"along the way the player is facing"
	)


func test_demolishing_takes_a_belt_back_apart_too() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	var laying: PlayerController.DeviceSample = _sample()
	laying.belt_clicked = true
	sim.step(controller.actions_for_tick(sim, 0, laying))
	assert_eq(sim.query_belt_count(), 1, "the premise of the assertion below")

	var wrecking: PlayerController.DeviceSample = _sample()
	wrecking.demolish_clicked = true
	sim.step(controller.actions_for_tick(sim, 0, wrecking))
	assert_eq(sim.query_belt_count(), 0)


# ── Saving and resuming a Run ─────────────────────────────────────────────────
# Smoke coverage for the wiring only. `tests/cases/test_run_save.gd` is where the round
# trip itself is proved exact; these assert that the Godot layer reaches it, and that the
# two keys doing so are not Input Actions.

const SMOKE_SAVE_PATH: String = "user://smoke_run.deepfoundry"


func _remove_smoke_save() -> void:
	if FileAccess.file_exists(SMOKE_SAVE_PATH):
		DirAccess.remove_absolute(SMOKE_SAVE_PATH)


func test_the_layer_can_save_a_run_and_resume_it() -> void:
	_remove_smoke_save()
	var main: Main = Main.new()
	for frame: int in range(90):
		main.advance_frame(1.0 / 60.0)
	var saved_hash: int = main.simulation().hash()

	assert_eq(main.save_run(SMOKE_SAVE_PATH), "", "saving should not fail")
	assert_eq(main.simulation().hash(), saved_hash, "and must leave the Run it saved alone")

	for frame: int in range(60):
		main.advance_frame(1.0 / 60.0)
	assert_ne(main.simulation().hash(), saved_hash, "the Run moved on after saving")

	assert_eq(main.load_run(SMOKE_SAVE_PATH), "", "resuming should not fail")
	assert_eq(main.simulation().hash(), saved_hash, "and puts the Run back where it was")

	main.free()
	_remove_smoke_save()


func test_a_run_that_refuses_to_load_leaves_the_running_run_alone() -> void:
	# The rule a failed hot-reload already obeys: a bad file must never take a Factory
	# down.
	var main: Main = Main.new()
	for frame: int in range(30):
		main.advance_frame(1.0 / 60.0)
	var before: int = main.simulation().hash()
	var sim_before: Simulation = main.simulation()

	var refusal: String = main.load_run("user://a_run_that_was_never_saved.deepfoundry")

	assert_ne(refusal, "", "a missing save must be reported")
	assert_eq(main.simulation(), sim_before, "and the Run that is running is untouched")
	assert_eq(main.simulation().hash(), before)
	main.free()


func test_saving_and_resuming_are_not_input_actions() -> void:
	# Both keys are held in `PlayerController` with the rest of the controls, but neither
	# may ever become an intent: a save does nothing to the Simulation, and a load
	# replaces it, which is not something `step` could express.
	var main: Main = Main.new()
	var sample: PlayerController.DeviceSample = PlayerController.DeviceSample.new()
	var actions: Array = main.controller().actions_for_tick(main.simulation(), 0, sample)
	for action: InputAction in actions:
		assert_ne(
			action.kind,
			InputAction.Kind.NONE,
			"no save or load kind exists for the controller to produce"
		)
	assert_true(
		PlayerController.KEY_SAVE != PlayerController.KEY_LOAD,
		"saving and resuming are two different keys"
	)
	main.free()
