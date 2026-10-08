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


## A Run with the Build Gun already drawn.
##
## A Run opens with the weapon out since #42, so a test about what a *click* does with the
## Build Gun has to put it in the player's hand first. In its own tick, so that the one
## test which is about the swap routing the tick it lands on — the holster test below — is
## the only one making that claim.
func _building() -> Simulation:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_mode(0, true)])
	return sim


func test_every_action_the_controller_produces_is_an_input_action() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	# The Build Gun out, because two of the readings below are build acts and the wheel
	# reads by hand — a Run opens with the weapon out since #42.
	sim.step([InputAction.set_build_mode(0, true)])
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
	var sim: Simulation = _building()
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
	var sim: Simulation = _building()
	var controller: PlayerController = PlayerController.new()
	var sample: PlayerController.DeviceSample = _sample()
	sample.place_clicked = true
	sim.step(controller.actions_for_tick(sim, 0, sample))
	sim.step(controller.actions_for_tick(sim, 0, sample))
	assert_eq(sim.query_machine_count(), 1)


func test_rotating_and_placing_in_one_tick_places_the_rotation_the_player_can_see() -> void:
	var sim: Simulation = _building()
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
	# The wheel is the Machine picker only with the Build Gun out; scrolling with a weapon
	# in hand chooses nothing, which `test_building_view` asserts from the other side.
	sim.step([InputAction.set_build_mode(0, true)])
	var controller: PlayerController = PlayerController.new()
	var count: int = sim.query_definitions().machine_count()
	assert_true(count >= 2, "the premise of the rest")

	# **The wheel walks the chain, not the alphabet** (#53). It and the number row are two
	# ways of reaching the same row of cells, so they walk the same order — otherwise one
	# click off the Miner lands on whatever sorts next by id.
	var definitions: Definitions = sim.query_definitions()
	# A Run opens with whatever Machine sits at index 0 of the sorted table on the Build
	# Gun, which is not where the chain starts — so where a step *lands* is read off the
	# cell the Build Gun is on rather than assumed to be the second cell.
	var opened_on: int = BuildChain.cell_of(
		definitions, sim.query_player_selected_machine_index(0)
	)
	var next_along: String = definitions.machine_at(
		BuildChain.order(definitions)[opened_on + 1]
	).id
	var sample: PlayerController.DeviceSample = _sample()
	sample.machine_steps = 1
	sim.step(controller.actions_for_tick(sim, 0, sample))
	assert_eq(
		sim.query_player_selected_machine(0), next_along, "one step is the next in the chain"
	)

	# A full lap of the list comes back to where it started, rather than running off the
	# end of the Machine table.
	for step: int in range(count):
		sim.step(controller.actions_for_tick(sim, 0, sample))
	assert_eq(sim.query_player_selected_machine(0), next_along, "stepping all the way wraps")


func test_a_demolish_returns_the_materials_the_build_spent() -> void:
	var sim: Simulation = _building()
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
	var sim: Simulation = _building()
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


func test_the_belt_key_and_a_dragged_click_lay_a_belt_through_the_whole_chain() -> void:
	# Belts have no row in `content/machines.csv` and so cannot sit on the Build Gun's
	# Machine list — they are a **tool** on it instead. The Belt key swaps the tool, and the
	# primary button then lays Belt: press, drag, release. This is that whole chain through
	# the real input producer, which is what the smoke test is for; the shape of the route
	# itself is `test_belt_routing.gd`.
	var sim: Simulation = _building()
	var controller: PlayerController = PlayerController.new()
	var aimed: Vector3i = BuildGun.aimed_tile(sim, 0)

	var swapping: PlayerController.DeviceSample = _sample()
	swapping.belt_clicked = true
	sim.step(controller.actions_for_tick(sim, 0, swapping))
	assert_true(sim.query_player_is_laying_belt(0), "the Belt tool is out")
	assert_eq(sim.query_belt_count(), 0, "and the key itself laid nothing")

	var pressing: PlayerController.DeviceSample = _sample()
	pressing.place_clicked = true
	sim.step(controller.actions_for_tick(sim, 0, pressing))
	assert_eq(sim.query_belt_count(), 0, "the press is the start of a drag, not a Belt")

	# Drag by turning, which is how a player aims the far end of a route.
	for tick: int in range(20):
		sim.step(controller.actions_for_tick(sim, 0, _sample()))
	var released_at: Vector3i = BuildGun.aimed_tile(sim, 0)

	var releasing: PlayerController.DeviceSample = _sample()
	releasing.primary_released = true
	sim.step(controller.actions_for_tick(sim, 0, releasing))

	assert_true(sim.query_belt_count() >= 1, "the release laid the route")
	assert_eq(sim.query_belt_tile(0, 0), aimed, "Items enter where the press was")
	assert_ne(
		sim.query_belt_at_tile(released_at), -1, "and the route reaches where the drag ended"
	)


func test_the_lever_key_calls_the_next_wave_early() -> void:
	# The lever as a player actually reaches it: a key, through the controller, as an Input
	# Action. Nothing about the Wave is decided on this side of the boundary.
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	assert_false(sim.query_wave_is_telegraphed(), "nothing is coming yet")

	var sample: PlayerController.DeviceSample = _sample()
	sample.call_wave_clicked = true
	sim.step(controller.actions_for_tick(sim, 0, sample))

	assert_true(sim.query_wave_was_called_early(), "the lever moved")
	assert_true(sim.query_wave_is_telegraphed(), "and the warning went up with it")


func test_the_lever_key_is_an_edge_so_holding_it_does_not_call_a_wave_a_tick() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	var held: InputEventKey = InputEventKey.new()
	held.keycode = PlayerController.KEY_CALL_WAVE
	held.pressed = true
	controller.note_event(held)

	var first: PlayerController.DeviceSample = controller.sample_devices()
	assert_true(first.call_wave_clicked, "the press was gathered")
	var second: PlayerController.DeviceSample = controller.sample_devices()
	assert_false(second.call_wave_clicked, "and spent exactly once")


func test_demolishing_takes_a_belt_back_apart_too() -> void:
	var sim: Simulation = _building()
	var controller: PlayerController = PlayerController.new()
	var swapping: PlayerController.DeviceSample = _sample()
	swapping.belt_clicked = true
	sim.step(controller.actions_for_tick(sim, 0, swapping))
	# A click with the Belt tool out — press and release in one tick — is one tile of Belt
	# on the aimed tile, which is the shortest route there is and exactly what a demolish
	# then wants to find.
	var clicking: PlayerController.DeviceSample = _sample()
	clicking.place_clicked = true
	clicking.primary_released = true
	sim.step(controller.actions_for_tick(sim, 0, clicking))
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


# ── Build mode: one button, two acts ──────────────────────────────────────────
# The routing #29 asked for. **This is the only place in the project that knows which of
# the two a left click means**, which is the point: the Simulation has no opinion, and the
# only thing build mode decides is which intent leaves this file.

## Which kinds a controller produced from one sample, for asserting against.
func _kinds(actions: Array) -> Array:
	var kinds: Array = []
	for action: InputAction in actions:
		kinds.append(action.kind)
	return kinds


func test_a_left_click_places_in_build_mode() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	var sample: PlayerController.DeviceSample = _sample()
	# Both readings of the one button, which is what a real click produces: the polling
	# cannot know which mode anybody is in, so it samples the edge and the held state and
	# `actions_for_tick` decides.
	sample.place_clicked = true
	sample.fire_held = true

	# A Run opens with the weapon out since #42, so the Build Gun has to be drawn before a
	# click can place. Drawn in its own tick, so what this test is about is the click.
	sim.step([InputAction.set_build_mode(0, true)])
	assert_true(sim.query_player_is_in_build_mode(0), "the Build Gun is out")
	var kinds: Array = _kinds(controller.actions_for_tick(sim, 0, sample))
	assert_true(kinds.has(InputAction.Kind.BUILD_MACHINE), "the click placed")
	assert_false(kinds.has(InputAction.Kind.FIRE), "and did not also fire")


func test_a_left_click_fires_in_combat_mode() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	# Where a Run opens since #42. Asked for anyway rather than assumed, so this test says
	# what it is about rather than leaning on an initial value that could change again.
	sim.step([InputAction.set_build_mode(0, false)])

	var sample: PlayerController.DeviceSample = _sample()
	sample.place_clicked = true
	sample.fire_held = true

	var kinds: Array = _kinds(controller.actions_for_tick(sim, 0, sample))
	assert_true(kinds.has(InputAction.Kind.FIRE), "the trigger pulled")
	assert_false(kinds.has(InputAction.Kind.BUILD_MACHINE), "and nothing was built")


func test_the_holster_key_toggles_and_routes_the_same_tick() -> void:
	# The swap is an edge, and the rest of the tick routes by the mode the player *will* be
	# in — the same rule that makes a scroll-and-click place what the player scrolled to.
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	# From the Build Gun, because the claim is about the swap routing the *same tick* and a
	# Run now opens on the other side of it.
	sim.step([InputAction.set_build_mode(0, true)])
	var sample: PlayerController.DeviceSample = _sample()
	sample.build_mode_clicked = true
	sample.place_clicked = true
	sample.fire_held = true

	var actions: Array = controller.actions_for_tick(sim, 0, sample)
	var kinds: Array = _kinds(actions)
	assert_true(kinds.has(InputAction.Kind.SET_BUILD_MODE), "the holster swapped")
	assert_true(
		kinds.has(InputAction.Kind.FIRE),
		"and the click in the same tick fired, because the weapon is what came up"
	)
	assert_false(kinds.has(InputAction.Kind.BUILD_MACHINE))

	sim.step(actions)
	assert_false(sim.query_player_is_in_build_mode(0), "and the Simulation agrees")


func test_belt_laying_lives_in_build_mode() -> void:
	# `B` used to lay a Belt and is now the holster; the Belt moved to `KEY_BELT`, and it
	# is only read with the Build Gun out, because routing a Belt is a build act. Since #36
	# what the key does is swap the **tool** rather than stamp a run, so what this asserts
	# is that the swap is a build-mode act too — a player holding a rifle has no use for the
	# Belt tool, and would otherwise find the Build Gun holding it when they drew it.
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	sim.step([InputAction.set_build_mode(0, true)])
	var sample: PlayerController.DeviceSample = _sample()
	sample.belt_clicked = true

	assert_true(
		_kinds(controller.actions_for_tick(sim, 0, sample)).has(InputAction.Kind.SET_BUILD_TOOL),
		"with the Build Gun out, the key swaps the tool"
	)

	sim.step([InputAction.set_build_mode(0, false)])
	assert_false(
		_kinds(controller.actions_for_tick(sim, 0, sample)).has(InputAction.Kind.SET_BUILD_TOOL),
		"with the weapon out, it does not"
	)
	assert_true(
		PlayerController.KEY_BELT != PlayerController.KEY_BUILD_MODE,
		"and the two keys are no longer the same key"
	)


func test_every_build_act_goes_through_the_one_hand_rule() -> void:
	# #35's second report — *"the hologram should not be placable in gun mode"* — covering
	# every build act rather than only the two that had tests. It is the net under collapsing
	# the inline readings of the mode into `BuildGun.hand_refusal`: the renderer, the panel
	# and all of these now ask one function, so there is no longer a version of this that can
	# be fixed in one place and left wrong in another.
	#
	# **One sample per act, not one sample with every flag set.** #36 gave the Build Gun two
	# tools and made `belt_clicked` swap between them, so the flags are no longer independent:
	# setting them all at once swaps to the Belt tool and the Machine click then correctly
	# does nothing. Driving each act through the gesture that really produces it is both the
	# honest test and the one that keeps meaning something the next time the scheme moves.
	var acts: Array = [
		["a Machine", InputAction.Kind.BUILD_MACHINE, "place_clicked"],
		["a Wall", InputAction.Kind.BUILD_WALL, "wall_clicked"],
		["a demolition", InputAction.Kind.DEMOLISH, "demolish_clicked"],
		# The tool swap is a build act too: it is the Build Gun's own control, and a
		# holstered gun has no tool to change.
		["the tool swap", InputAction.Kind.SET_BUILD_TOOL, "belt_clicked"],
	]

	for act: Array in acts:
		# `_building()`, because a Run opens with the weapon out since #42 and both halves
		# of this test name the hand they are about rather than inheriting one.
		var sim: Simulation = _building()
		var controller: PlayerController = PlayerController.new()
		var sample: PlayerController.DeviceSample = _sample()
		sample.set(act[2] as String, true)

		assert_true(
			_kinds(controller.actions_for_tick(sim, 0, sample)).has(act[1] as int),
			"%s happens with the Build Gun out" % act[0]
		)
		sim.step([InputAction.set_build_mode(0, false)])
		assert_false(
			_kinds(controller.actions_for_tick(sim, 0, sample)).has(act[1] as int),
			"%s does not, with a rifle out" % act[0]
		)

	# A Belt route is the one act that is a *gesture* rather than a click: press, drag,
	# release, with a press and a release in one tick being the one-tile case. So it needs the
	# Belt tool on the gun first, which is a second tick either way.
	var sim: Simulation = _building()
	var controller: PlayerController = PlayerController.new()
	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	var drag: PlayerController.DeviceSample = _sample()
	drag.place_clicked = true
	drag.primary_released = true

	assert_true(
		_kinds(controller.actions_for_tick(sim, 0, drag)).has(InputAction.Kind.BUILD_BELT),
		"a Belt route happens with the Build Gun out"
	)
	sim.step([InputAction.set_build_mode(0, false)])
	assert_false(
		_kinds(controller.actions_for_tick(sim, 0, drag)).has(InputAction.Kind.BUILD_BELT),
		"a Belt route does not, with a rifle out"
	)


func test_holding_a_rifle_does_not_stop_a_player_building() -> void:
	# The line this must not cross, from the other side. The four acts above are about what
	# a *button* means; the Simulation is not being asked for permission, and an intent that
	# reaches it is applied whatever is in the player's hands. If this ever goes red, the
	# refusal has leaked out of `game/` and into the build path —
	# `test_nothing_in_the_simulation_asks_the_mode_for_permission` says the same thing
	# about the Simulation's own refusal.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_mode(0, false)])
	assert_false(sim.query_player_is_in_build_mode(0), "the premise")
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("miner_mk1"), Vector3i(6, 0, 6), 0
		)
	])
	assert_eq(sim.query_machine_count(), 1, "building is never gated")


func test_no_two_actions_share_a_key() -> void:
	# The thing three branches landing at once kept nearly doing. #29 moved the Belt to `C`
	# while #17 was putting the Silo's charge counter there, and `T` was quietly bound to
	# *both* revive and withdraw from the moment #27 landed — press it next to a Downed
	# teammate and you did both. A collision is invisible until somebody plays the game, so
	# it is asserted rather than reviewed: the whole map, read off the constants, with the
	# two banks of keys expanded.
	var keys: Dictionary = {}
	var constants: Dictionary = PlayerController.new().get_script().get_script_constant_map()
	for name: String in constants:
		if not name.begins_with("KEY_") or typeof(constants[name]) != TYPE_INT:
			continue
		var span: int = 1
		if name == "KEY_WEAPON_FIRST":
			span = PlayerController.WEAPON_KEY_COUNT
		elif name == "KEY_SLOT_FIRST":
			span = PlayerController.SLOT_KEY_COUNT
		for step: int in range(span):
			var key: int = int(constants[name]) + step
			assert_false(
				keys.has(key),
				"%s and %s are the same key" % [name, keys.get(key, "")]
			)
			keys[key] = name


func test_the_jump_key_becomes_a_jump_intent_and_leaves_the_ground() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	var sample: PlayerController.DeviceSample = _sample()
	sample.jump_held = true

	sim.step(controller.actions_for_tick(sim, 0, sample))
	assert_true(sim.query_player_height_metres(0) > 0, "off the ground")
	assert_false(sim.query_player_is_grounded(0))


# ── Sprint: a toggle or a hold, and the setting is content ────────────────────

func test_sprint_is_a_toggle_at_the_shipped_setting() -> void:
	# `player.sprint_is_toggle` ships true: one press starts running, another stops. The
	# interpretation lives here because it is an interpretation of a device; what crosses
	# the boundary is still "this player is sprinting", so a replay reproduces either
	# reading identically.
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	assert_true(
		sim.query_definitions().player_sprint_is_toggle, "the shipped setting is a toggle"
	)

	var pressed: PlayerController.DeviceSample = _sample()
	pressed.sprint_clicked = true
	pressed.sprint_held = true
	sim.step(controller.actions_for_tick(sim, 0, pressed))
	assert_true(sim.query_player_is_sprinting(0), "one press starts it")

	# The key comes up. A hold would stop here; a toggle does not.
	var released: PlayerController.DeviceSample = _sample()
	sim.step(controller.actions_for_tick(sim, 0, released))
	assert_true(sim.query_player_is_sprinting(0), "and letting go does not stop it")

	sim.step(controller.actions_for_tick(sim, 0, pressed))
	assert_false(sim.query_player_is_sprinting(0), "a second press stops it")


func test_a_latched_sprint_is_dropped_for_a_player_who_is_not_on_their_feet() -> void:
	# **A latched sprint does not survive dying** — you come back at the Nest walking,
	# because respawning already at a run is a control the player did not give. The latch
	# is cleared off `query_player_is_alive` every tick rather than on an event, which is
	# what stops it drifting out of step with the Simulation: the Simulation stays the
	# authority on what is true and the latch is only a reading on its way in.
	#
	# Asserted against a player id the Simulation does not report as alive, because nothing
	# in this suite kills a player cheaply — `test_gear.gd` needs a Crawler and a Wave
	# schedule to do it, which is not what a smoke case is for. What is being held here is
	# the branch and its direction.
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	var pressed: PlayerController.DeviceSample = _sample()
	pressed.sprint_clicked = true
	sim.step(controller.actions_for_tick(sim, 0, pressed))
	assert_true(sim.query_player_is_sprinting(0), "running")

	assert_false(sim.query_player_is_alive(1), "player 1 is not on this Run's feet")
	var still_pressed: Array = controller.actions_for_tick(sim, 1, pressed)
	var sprint_intent: bool = true
	for action: InputAction in still_pressed:
		if action.kind == InputAction.Kind.SPRINT:
			sprint_intent = action.sprint_is_held()
	assert_false(sprint_intent, "so the latch is dropped rather than re-asserted")

	# And it is the controller's own latch that went, not the Simulation's flag: player 0
	# is still running until they say otherwise.
	assert_true(sim.query_player_is_sprinting(0), "nothing reached into the Simulation")


func test_sprint_is_a_hold_when_the_tuning_says_so() -> void:
	var sim: Simulation = _sim_with_tuning("sprint_is_toggle", "false")
	var controller: PlayerController = PlayerController.new()

	var held: PlayerController.DeviceSample = _sample()
	held.sprint_clicked = true
	held.sprint_held = true
	sim.step(controller.actions_for_tick(sim, 0, held))
	assert_true(sim.query_player_is_sprinting(0), "down is sprinting")

	var released: PlayerController.DeviceSample = _sample()
	sim.step(controller.actions_for_tick(sim, 0, released))
	assert_false(sim.query_player_is_sprinting(0), "and up is not")


## A Simulation on the shipped content with one `[player]` tuning key changed.
func _sim_with_tuning(key: String, value: String) -> Simulation:
	var tuning: String = FileAccess.get_file_as_string("res://content/tuning.toml")
	var replaced: PackedStringArray = PackedStringArray()
	var found: bool = false
	for line: String in tuning.split("\n"):
		if line.begins_with("%s = " % key):
			replaced.append("%s = %s" % [key, value])
			found = true
		else:
			replaced.append(line)
	assert_true(found, "content/tuning.toml should carry a key called %s" % key)
	var definitions: Definitions = Definitions.parse(
		FileAccess.get_file_as_string("res://content/machines.csv"),
		FileAccess.get_file_as_string("res://content/recipes.csv"),
		"\n".join(replaced),
		FileAccess.get_file_as_string("res://content/waves.csv"),
		FileAccess.get_file_as_string("res://content/deliveries.csv"),
		FileAccess.get_file_as_string("res://content/gear.csv"),
		FileAccess.get_file_as_string("res://content/stratagems.csv")
	)
	assert_true(definitions.errors.is_empty(), definitions.describe_errors())
	return Simulation.new(1, 1, definitions)
