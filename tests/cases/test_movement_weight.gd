## Weight: jumping, gravity, asymmetric acceleration and the camera's response to all
## three.
##
## The ticket this covers (#29) came out of a play session rather than out of a spec, and
## its complaint was that movement read as "Minecraft creative mode" where it wanted to
## read as survival mode. So almost every number here is a feel number and almost none of
## it can be asserted as a value — what *can* be asserted is the shape: that a jump rises
## and falls, that stopping takes longer than starting, that the air is stiffer than the
## ground, that a landing settles, and that every one of those is state the hash sees and
## a replay reproduces.
##
## Expected values are worked out from `content/tuning.toml` and the fixed-point scale,
## never by restating the code.
extends TestCase


## Steps a Simulation `ticks` times with the given actions repeated every tick.
func _hold(sim: Simulation, ticks: int, actions: Array) -> void:
	for _i: int in range(ticks):
		var copied: Array = []
		for action: InputAction in actions:
			copied.append(action)
		sim.step(copied)


## A Simulation on the shipped content with one `[player]` tuning key changed.
##
## The shipped file rather than an inline fixture, because what is being asserted is that a
## *key* does what it says — "0 turns the bob off" is a claim about the key and not about a
## set of numbers invented here.
func _sim_with(key: String, value: String) -> Simulation:
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
	return Simulation.new(0, 1, definitions)


# ── Jumping ───────────────────────────────────────────────────────────────────

func test_a_player_on_the_ground_is_at_zero_height() -> void:
	var sim: Simulation = Simulation.new()
	assert_eq(sim.query_player_height_metres(0), 0, "a Run opens with both feet down")
	assert_true(sim.query_player_is_grounded(0), "and grounded")


func test_a_jump_leaves_the_ground() -> void:
	var sim: Simulation = Simulation.new()
	sim.step([InputAction.jump(0, true)])
	assert_true(
		sim.query_player_height_metres(0) > 0,
		"one tick of jump should already be off the ground, got %d"
		% sim.query_player_height_metres(0)
	)
	assert_false(sim.query_player_is_grounded(0), "and airborne")


func test_a_jump_comes_back_down_by_itself() -> void:
	var sim: Simulation = Simulation.new()
	sim.step([InputAction.jump(0, true)])
	# Long enough for any sane jump at any sane gravity to have landed.
	_hold(sim, 300, [])
	assert_eq(sim.query_player_height_metres(0), 0, "gravity brings a jump back")
	assert_true(sim.query_player_is_grounded(0), "and grounded again")


func test_a_jump_reaches_the_height_the_tuning_names() -> void:
	# `player.jump_height_metres` is the apex of a standing jump, and the impulse is
	# derived from it rather than tuned separately — a tuner thinks in how high they
	# clear, not in metres per second. Shipped at 1.1 m.
	#
	# The tolerance is generous because the apex is sampled once per tick: with a
	# 60 Hz tick a jump passes its true apex between two samples, so the highest
	# sample is always a little under. Within 10 cm is the claim worth making.
	var sim: Simulation = Simulation.new()
	sim.step([InputAction.jump(0, true)])
	var apex: int = 0
	for _i: int in range(300):
		sim.step([])
		apex = maxi(apex, sim.query_player_height_metres(0))
	var wanted: int = Fixed.from_decimal_string("1.1")
	assert_true(
		absi(apex - wanted) < Fixed.from_decimal_string("0.1"),
		"expected an apex near 1.1 m, got %f" % Fixed.to_float(apex)
	)


func test_a_player_already_in_the_air_cannot_jump_again() -> void:
	var sim: Simulation = Simulation.new()
	sim.step([InputAction.jump(0, true)])
	var first: int = sim.query_player_vertical_velocity(0)
	# Held, so the intent arrives every tick. Nothing may add a second impulse to it.
	_hold(sim, 10, [InputAction.jump(0, true)])
	assert_true(
		sim.query_player_vertical_velocity(0) < first,
		"gravity should have taken the rise off, not a second impulse put it back"
	)


func test_holding_jump_through_a_landing_does_not_bounce() -> void:
	# `jump_repeats_while_held` is false by default: a jump is a press, so a player who
	# holds the key through a landing stays landed until they let go and press again.
	# Bunny-hopping on a held key is the arcade reading of this control, and the
	# reference is Satisfactory.
	var sim: Simulation = Simulation.new()
	_hold(sim, 300, [InputAction.jump(0, true)])
	assert_eq(
		sim.query_player_height_metres(0), 0, "a held key should not re-launch on landing"
	)


func test_letting_go_and_pressing_again_jumps_again() -> void:
	var sim: Simulation = Simulation.new()
	_hold(sim, 300, [InputAction.jump(0, true)])
	sim.step([InputAction.jump(0, false)])
	sim.step([InputAction.jump(0, true)])
	assert_true(
		sim.query_player_height_metres(0) > 0, "a fresh press is a fresh jump"
	)


# ── Where a jump reaches the rest of the Run ──────────────────────────────────

func test_height_and_vertical_velocity_reach_the_hash() -> void:
	var jumping: Simulation = Simulation.new()
	var standing: Simulation = Simulation.new()
	jumping.step([InputAction.jump(0, true)])
	standing.step([])
	assert_true(
		jumping.hash() != standing.hash(),
		"a player in the air is in a different state from one standing"
	)


func test_determinism_a_jump_and_a_landing_replay_identically() -> void:
	var script: InputScript = InputScript.new()
	script.add_tick([InputAction.move(0, Fixed.ONE, 0), InputAction.jump(0, true)])
	for _i: int in range(20):
		script.add_tick([InputAction.move(0, Fixed.ONE, 0), InputAction.jump(0, true)])
	script.add_tick([InputAction.jump(0, false)])
	script.add_idle_ticks(120)

	var recording: ReplayRecording = DeterminismHarness.record(script, 0, 1)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


# ── Ground against air ────────────────────────────────────────────────────────

func test_the_air_is_stiffer_than_the_ground() -> void:
	# The air-control decision, asserted as the thing it is: a player who starts pushing a
	# direction in mid-air gains speed more slowly than one doing it on the ground.
	# `player.air_acceleration_metres_per_second_squared` is 6 against the ground's 24.
	var on_the_ground: Simulation = Simulation.new()
	var in_the_air: Simulation = Simulation.new()

	in_the_air.step([InputAction.jump(0, true)])
	# One tick each of full forward throttle, from a standing start.
	on_the_ground.step([InputAction.move(0, Fixed.ONE, 0)])
	in_the_air.step([InputAction.move(0, Fixed.ONE, 0)])

	var ground_speed: int = -on_the_ground.query_player_velocity(0).z
	var air_speed: int = -in_the_air.query_player_velocity(0).z
	assert_true(air_speed > 0, "there is *some* air control, got %d" % air_speed)
	assert_true(
		air_speed * 2 < ground_speed,
		"the air should be far stiffer: air %d, ground %d" % [air_speed, ground_speed]
	)


func test_momentum_survives_letting_go_in_mid_air() -> void:
	# `air_deceleration` is 1.5 against the ground's 9, so a jump carries you: letting go
	# of the keys in the air sheds far less speed than letting go on the ground does.
	var airborne: Simulation = Simulation.new()
	var grounded: Simulation = Simulation.new()
	for _i: int in range(40):
		airborne.step([InputAction.move(0, Fixed.ONE, 0)])
		grounded.step([InputAction.move(0, Fixed.ONE, 0)])
	airborne.step([InputAction.move(0, Fixed.ONE, 0), InputAction.jump(0, true)])

	for _i: int in range(10):
		airborne.step([])
		grounded.step([])

	assert_true(
		-airborne.query_player_velocity(0).z > -grounded.query_player_velocity(0).z,
		"airborne %d, grounded %d"
		% [-airborne.query_player_velocity(0).z, -grounded.query_player_velocity(0).z]
	)


func test_a_landing_settles_rather_than_restoring_full_control() -> void:
	# For `player.land_settle_seconds` after a landing a player has
	# `land_settle_acceleration_percent` of their normal ground acceleration, so arriving
	# is something that happens over a moment instead of on one frame.
	var landed: Simulation = Simulation.new()
	landed.step([InputAction.jump(0, true)])
	for _i: int in range(300):
		landed.step([])
		if landed.query_player_is_grounded(0):
			break
	assert_true(landed.query_player_is_grounded(0), "down again")

	# Against a player who never left the ground, from the same standing start.
	var settled: Simulation = Simulation.new()
	landed.step([InputAction.move(0, Fixed.ONE, 0)])
	settled.step([InputAction.move(0, Fixed.ONE, 0)])
	assert_true(
		-landed.query_player_velocity(0).z < -settled.query_player_velocity(0).z,
		"a player gathering themselves accelerates less: settling %d, settled %d"
		% [-landed.query_player_velocity(0).z, -settled.query_player_velocity(0).z]
	)


# ── Sprint as a gait ──────────────────────────────────────────────────────────

func test_sprint_ramps_in_rather_than_snapping() -> void:
	# `player.sprint_ramp_seconds` is 0.45, so a quarter of a second into holding the key a
	# player is part-way into the gait rather than fully in it.
	var sim: Simulation = Simulation.new()
	assert_eq(sim.query_player_sprint_blend(0), 0, "a Run opens walking")
	_hold(sim, 15, [InputAction.sprint(0, true)])
	var part_way: int = sim.query_player_sprint_blend(0)
	assert_true(part_way > 0, "something has happened")
	assert_true(part_way < Fixed.ONE, "and it is not all of it yet, got %d" % part_way)
	_hold(sim, 45, [InputAction.sprint(0, true)])
	assert_eq(sim.query_player_sprint_blend(0), Fixed.ONE, "and then it is")


func test_letting_go_of_sprint_ramps_back_out() -> void:
	var sim: Simulation = Simulation.new()
	_hold(sim, 60, [InputAction.sprint(0, true)])
	_hold(sim, 10, [InputAction.sprint(0, false)])
	var part_way: int = sim.query_player_sprint_blend(0)
	assert_true(part_way < Fixed.ONE, "coming out of it")
	assert_true(part_way > 0, "and not out of it yet, got %d" % part_way)


func test_the_gait_widens_the_field_of_view() -> void:
	# One blend drives the speed, the field of view and the bob together, which is what
	# makes a sprint read as a change of gear rather than as a number going up.
	var sim: Simulation = Simulation.new()
	assert_eq(
		sim.query_player_field_of_view_degrees(0),
		Fixed.from_int(75),
		"`player.field_of_view_degrees`, which is 75 at the shipped setting"
	)
	_hold(sim, 60, [InputAction.sprint(0, true), InputAction.move(0, Fixed.ONE, 0)])
	assert_eq(
		sim.query_player_field_of_view_degrees(0),
		Fixed.from_int(81),
		"plus the whole of `sprint_field_of_view_add_degrees`, which is 6"
	)


# ── The camera's response ─────────────────────────────────────────────────────

func test_a_standing_player_has_no_bob_at_all() -> void:
	var sim: Simulation = Simulation.new()
	_hold(sim, 60, [])
	assert_eq(sim.query_player_view_bob_vertical_metres(0), 0, "nothing to bob about")
	assert_eq(sim.query_player_view_bob_lateral_metres(0), 0)


func test_a_walking_player_bobs_and_it_is_tiny() -> void:
	# The amplitude is `player.bob_vertical_metres`, which ships at 1.2 cm — deliberately
	# barely perceptible, because this is the easiest thing in the game to overdo into
	# motion sickness. What is worth asserting is that it is non-zero and that it stays
	# inside the tuned amplitude, not what it is at any given tick.
	var sim: Simulation = Simulation.new()
	var peak: int = 0
	for _i: int in range(180):
		sim.step([InputAction.move(0, Fixed.ONE, 0)])
		peak = maxi(peak, absi(sim.query_player_view_bob_vertical_metres(0)))
	assert_true(peak > 0, "a walking player bobs")
	assert_true(
		peak <= Fixed.from_decimal_string("0.012"),
		"and never past the tuned amplitude, got %f m" % Fixed.to_float(peak)
	)


func test_bob_turns_off_when_the_tuning_says_zero() -> void:
	# Every camera-response value takes 0 as "off", which is a setting somebody prone to
	# motion sickness is entitled to.
	var sim: Simulation = _sim_with("bob_vertical_metres", "0")
	var peak: int = 0
	for _i: int in range(180):
		sim.step([InputAction.move(0, Fixed.ONE, 0)])
		peak = maxi(peak, absi(sim.query_player_view_bob_vertical_metres(0)))
	assert_eq(peak, 0, "off is off")


func test_a_landing_dips_the_view_and_then_recovers() -> void:
	var sim: Simulation = Simulation.new()
	sim.step([InputAction.jump(0, true)])
	assert_eq(sim.query_player_view_dip_metres(0), 0, "nothing to dip about on the way up")
	for _i: int in range(300):
		sim.step([])
		if sim.query_player_is_grounded(0):
			break
	var dip: int = sim.query_player_view_dip_metres(0)
	assert_true(dip > 0, "the landing dipped the view")
	assert_true(
		dip <= Fixed.from_decimal_string("0.035"),
		"and never past `player.land_dip_metres`, got %f m" % Fixed.to_float(dip)
	)
	_hold(sim, 30, [])
	assert_eq(sim.query_player_view_dip_metres(0), 0, "and came back")


func test_the_bob_and_the_dip_do_not_move_the_aim() -> void:
	# The bob and the dip are projections the renderer reads and the Simulation never does.
	# A shot leaves from eye height and a hologram snaps to the tile a player is pointing
	# at, neither of which may be nudged by a footfall — which is the whole reason these
	# are their own queries rather than terms in `query_player_camera_height_metres`.
	var sim: Simulation = Simulation.new()
	sim.step([InputAction.jump(0, true)])
	var apex: int = sim.query_player_camera_height_metres(0)
	for _i: int in range(300):
		sim.step([])
		if sim.query_player_is_grounded(0):
			break
	assert_true(sim.query_player_view_dip_metres(0) > 0, "a dip is in progress")
	assert_eq(
		sim.query_player_camera_height_metres(0),
		Fixed.from_decimal_string("1.7"),
		"and the aim is back at `player.eye_height_metres`, not below it"
	)
	assert_true(apex > Fixed.from_decimal_string("1.7"), "the jump itself did raise the aim")


func test_a_strafing_player_leans_into_it() -> void:
	var level: Simulation = Simulation.new()
	_hold(level, 60, [])
	assert_eq(level.query_player_view_roll_turns(0), 0, "standing still is level")

	var right: Simulation = Simulation.new()
	_hold(right, 60, [InputAction.move(0, 0, Fixed.ONE)])
	var banked: int = right.query_player_view_roll_turns(0)
	assert_true(banked != 0, "strafing right banks, got %d" % banked)

	var left: Simulation = Simulation.new()
	_hold(left, 60, [InputAction.move(0, 0, -Fixed.ONE)])
	var other_way: int = left.query_player_view_roll_turns(0)
	assert_true(other_way < 0 and banked > 0, "strafing left banks the other way")
	# Within one fixed-point unit of a mirror image rather than exactly one, because every
	# floor in the chain floors towards negative infinity: the two directions are symmetric
	# in the arithmetic and quantise by one unit differently. Bounded, not drifting.
	assert_true(
		absi(absi(other_way) - banked) <= 1,
		"and by the same amount: right %d, left %d" % [banked, other_way]
	)


# ── Build mode ────────────────────────────────────────────────────────────────

func test_a_run_opens_with_the_build_gun_in_hand() -> void:
	var sim: Simulation = Simulation.new()
	assert_true(
		sim.query_player_is_in_build_mode(0),
		"the first thing a Run asks of a player is a Factory"
	)
	assert_eq(sim.query_player_holster_blend(0), 0, "and nothing is mid-swap")


func test_the_mode_switches_on_the_tick_the_intent_lands() -> void:
	var sim: Simulation = Simulation.new()
	sim.step([InputAction.set_build_mode(0, false)])
	assert_false(sim.query_player_is_in_build_mode(0), "instant, not after the holster")
	sim.step([InputAction.set_build_mode(0, true)])
	assert_true(sim.query_player_is_in_build_mode(0), "and back, just as instantly")


func test_asking_for_the_mode_you_are_already_in_does_nothing_at_all() -> void:
	# Including to the hash, so leaning on the key does not restart the holster animation
	# sixty times a second.
	var asking: Simulation = Simulation.new()
	var idle: Simulation = Simulation.new()
	asking.step([InputAction.set_build_mode(0, true)])
	idle.step([])
	assert_eq(asking.hash(), idle.hash(), "a no-op leaves the Run exactly where it was")
	assert_true(asking.hash() != 0, "and the hash is a real number to begin with")


func test_the_holster_plays_out_over_the_tuned_duration() -> void:
	# `player.holster_seconds` is 0.06 — three or four ticks, after #35's playtest asked
	# for an instant swap — and the blend peaks half way through, which is the moment the
	# old thing has gone down and the new thing has not yet come up. The loop below is
	# deliberately longer than the span: what is asserted is that the swap *finishes*, not
	# how many ticks it takes, so turning the key is not a test edit.
	#
	# **The renderer does not read this**, and has not since #28's view model landed: a
	# `holster` and a `draw` are clips there, timed off the lengths of the model on screen.
	# This is the Simulation's own answer to the same question, which is what anything that
	# is not that renderer has — a co-op client's HUD, a replay viewer — so it is asserted
	# here rather than deleted.
	var sim: Simulation = Simulation.new()
	sim.step([InputAction.set_build_mode(0, false)])
	var peak: int = 0
	for _i: int in range(12):
		peak = maxi(peak, sim.query_player_holster_blend(0))
		sim.step([])
	assert_true(
		peak > Fixed.ONE / 2,
		"the swap took the held object most of the way out, got %d" % peak
	)
	assert_eq(sim.query_player_holster_blend(0), 0, "and twelve ticks later it is over")


func test_what_is_drawn_crosses_over_half_way_through_the_swap() -> void:
	var sim: Simulation = Simulation.new()
	sim.step([InputAction.set_build_mode(0, false)])
	assert_true(
		sim.query_player_held_is_build_gun(0),
		"the Build Gun is still the thing on its way down"
	)
	_hold(sim, 8, [])
	assert_false(
		sim.query_player_held_is_build_gun(0), "and then the weapon is the thing coming up"
	)


func test_nothing_in_the_simulation_asks_the_mode_for_permission() -> void:
	# The acceptance criterion written as the absence of a gate: a player in combat mode
	# builds exactly as well as one in build mode, because the Simulation's build path has
	# never heard of the flag. What the mode decides is which intent a left click produces,
	# which is `game/player_controller.gd`'s business and not the Simulation's.
	var building: Simulation = Simulation.new()
	var fighting: Simulation = Simulation.new()
	fighting.step([InputAction.set_build_mode(0, false)])

	var machine: int = building.query_definitions().machine_index("miner_mk1")
	assert_true(machine != -1, "the shipped table has a Miner")
	var tile: Vector3i = Vector3i(3, 0, 3)
	assert_eq(
		fighting.query_build_refusal(0, machine, tile, 0),
		building.query_build_refusal(0, machine, tile, 0),
		"the refusal does not know which mode anybody is in"
	)
	building.step([InputAction.build_machine(0, machine, tile, 0)])
	fighting.step([InputAction.build_machine(0, machine, tile, 0)])
	assert_eq(fighting.query_machine_count(), 1, "building is never gated")
	assert_eq(building.query_machine_count(), 1)


func test_determinism_a_session_with_a_mode_switch_replays_identically() -> void:
	var script: InputScript = InputScript.new()
	script.add_tick([InputAction.move(0, Fixed.ONE, 0), InputAction.jump(0, true)])
	script.add_idle_ticks(15)
	script.add_tick([InputAction.set_build_mode(0, false)])
	script.add_idle_ticks(20)
	for _i: int in range(40):
		script.add_tick([InputAction.sprint(0, true), InputAction.move(0, 0, Fixed.ONE)])
	script.add_tick([InputAction.set_build_mode(0, true), InputAction.jump(0, true)])
	script.add_idle_ticks(120)

	var recording: ReplayRecording = DeterminismHarness.record(script, 0, 1)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_a_jump_a_landing_and_a_mode_switch_survive_a_save_and_a_resume() -> void:
	var sim: Simulation = Simulation.new()
	sim.step([InputAction.set_build_mode(0, false)])
	sim.step([InputAction.move(0, Fixed.ONE, 0), InputAction.jump(0, true)])
	_hold(sim, 6, [InputAction.move(0, Fixed.ONE, 0)])

	var loaded: RunSave.Load = RunSave.deserialise(RunSave.serialise(sim))
	assert_false(loaded.has_errors(), loaded.describe_errors())
	assert_eq(
		loaded.simulation.hash(), sim.hash(), "a Run written out and read back is the same Run"
	)
	assert_true(loaded.simulation.query_player_height_metres(0) > 0, "still mid-air")
	assert_false(
		loaded.simulation.query_player_is_in_build_mode(0), "still holding the weapon"
	)
