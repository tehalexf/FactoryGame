## Sprinting.
##
## Sprint scales the speed a player is reaching for, not their acceleration, so a
## sprint ramps up over the same time a walk does rather than snapping to full pace.
extends TestCase


## Walks a Simulation for `ticks`, holding full forward throttle, and returns how far
## the player travelled along -z. Forward at yaw 0 is -z, per Godot's convention.
func _distance_walked(sim: Simulation, ticks: int, sprinting: bool) -> int:
	var start: int = sim.query_player_position(0).z
	for _i: int in range(ticks):
		var actions: Array[InputAction] = [InputAction.move(0, Fixed.ONE, 0)]
		if sprinting:
			actions.append(InputAction.sprint(0, true))
		sim.step(actions)
	return start - sim.query_player_position(0).z


func test_a_sprinting_player_covers_more_ground_than_a_walking_one() -> void:
	var walker: Simulation = Simulation.new()
	var sprinter: Simulation = Simulation.new()
	var walked: int = _distance_walked(walker, 120, false)
	var sprinted: int = _distance_walked(sprinter, 120, true)
	assert_true(sprinted > walked, "sprinting covered %d, walking %d" % [sprinted, walked])


func test_sprint_tops_out_at_the_multiplier_the_tuning_names() -> void:
	# Two seconds is long enough for both to have reached their top speed, so the
	# ratio of the last second's travel is the multiplier itself: 1.8 at the shipped
	# setting.
	#
	# The tolerance is 32 fixed-point units rather than 1 because position is
	# integrated once per tick and each of those 60 divisions floors. The shortfall
	# is bounded and the same every run — it is quantisation, not drift — but it is
	# larger than a single unit, so a ratio of exactly 1.8 would be the wrong thing
	# to demand.
	var walker: Simulation = Simulation.new()
	var sprinter: Simulation = Simulation.new()
	_distance_walked(walker, 120, false)
	_distance_walked(sprinter, 120, true)
	var walked: int = _distance_walked(walker, 60, false)
	var sprinted: int = _distance_walked(sprinter, 60, true)
	var ratio: int = Fixed.div(sprinted, walked)
	assert_true(
		absi(ratio - Fixed.from_decimal_string("1.8")) <= 32,
		"expected a ratio of 1.8, got %f" % Fixed.to_float(ratio)
	)


func test_letting_go_of_sprint_slows_the_player_down_again() -> void:
	var sim: Simulation = Simulation.new()
	_distance_walked(sim, 120, true)
	var at_sprint: int = _distance_walked(sim, 60, true)
	# Releasing is its own action, so the Simulation hears the let-go rather than
	# inferring it from the absence of one.
	for _i: int in range(120):
		sim.step([InputAction.move(0, Fixed.ONE, 0), InputAction.sprint(0, false)])
	var after: int = _distance_walked(sim, 60, false)
	assert_true(after < at_sprint, "sprinting %d, after release %d" % [at_sprint, after])


func test_a_standing_player_does_not_drift_while_holding_sprint() -> void:
	var sim: Simulation = Simulation.new()
	var start_x: int = sim.query_player_position(0).x
	var start_z: int = sim.query_player_position(0).z
	for _i: int in range(60):
		sim.step([InputAction.sprint(0, true)])
	assert_eq(sim.query_player_position(0).x, start_x, "no throttle, no movement")
	assert_eq(sim.query_player_position(0).z, start_z, "no throttle, no movement")


func test_whether_a_player_is_sprinting_reaches_the_hash() -> void:
	var sprinting: Simulation = Simulation.new()
	var walking: Simulation = Simulation.new()
	sprinting.step([InputAction.sprint(0, true)])
	walking.step([InputAction.sprint(0, false)])
	assert_true(
		sprinting.hash() != walking.hash(),
		"a held sprint is state, so it has to be part of the digest"
	)


func test_determinism_a_sprinting_session_replays_identically() -> void:
	var script: InputScript = InputScript.new()
	script.add_tick([InputAction.sprint(0, true), InputAction.move(0, Fixed.ONE, 0)])
	for _i: int in range(90):
		script.add_tick([InputAction.sprint(0, true), InputAction.move(0, Fixed.ONE, 0)])
	script.add_tick([InputAction.sprint(0, false), InputAction.move(0, Fixed.ONE, 0)])
	script.add_idle_ticks(30)

	var recording: ReplayRecording = DeterminismHarness.record(script, 0, 1)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())
