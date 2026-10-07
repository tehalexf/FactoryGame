## The first-person controller, as behaviour of the Simulation.
##
## Everything a player does with a mouse and four keys arrives as an Input Action and
## nothing else, so all of it is testable here, through the façade, with no node tree
## and no frame loop. The Godot-side controller gets smoke coverage only
## (`test_godot_layer_smoke.gd`) because it is allowed to hold nothing worth asserting.
##
## Expected values are worked out from `content/tuning.toml` and the fixed-point
## scale, never by restating the code. The walk speed is 4 m/s, acceleration is
## 24 m/s², look sensitivity is 0.4 turns per 1000 pixels of mouse travel, and a tick
## is a sixtieth of a second.
extends TestCase

## 24 m/s² ÷ 60 ticks is 0.4 m/s of velocity a tick. 0.4 × 65536 is 26214.4, which
## floors to 26214 — fixed point is exact, not infinitely precise.
const ACCELERATION_PER_TICK: int = 26214

## And 9 m/s² ÷ 60 ticks is 0.15 m/s, which is 9830.4 and floors to 9830. **A separate
## figure, and a smaller one** — see `test_a_player_stops_more_slowly_than_they_start`.
const DECELERATION_PER_TICK: int = 9830

## 4 m/s in fixed-point metres.
const WALK_SPEED: int = 262144



## The look tests below are worked examples in a *fixed* sensitivity, so they pin their
## own tuning rather than reading the shipped one. Sensitivity is a feel setting the
## player owns and is expected to change; the Simulation's arithmetic is not. Coupling
## the two meant every tweak to how the game felt broke the maths tests.
const LOOK_TUNING: String = """[player]
walk_speed_metres_per_second = 4
sprint_speed_multiplier = 1.8
walk_acceleration_metres_per_second_squared = 24
walk_deceleration_metres_per_second_squared = 9
air_acceleration_metres_per_second_squared = 6
air_deceleration_metres_per_second_squared = 1.5
jump_height_metres = 1.1
gravity_metres_per_second_squared = 22
jump_repeats_while_held = false
land_settle_seconds = 0.18
land_settle_acceleration_percent = 45
sprint_ramp_seconds = 0.45
sprint_is_toggle = true
bob_vertical_metres = 0.012
bob_lateral_metres = 0.008
bob_stride_metres = 1.6
bob_sprint_multiplier = 1.6
land_dip_metres = 0.035
land_dip_seconds = 0.22
land_dip_reference_speed_metres_per_second = 7
lean_roll_degrees_per_metre_per_second = 0.12
lean_pitch_degrees_per_metre_per_second = 0.06
field_of_view_degrees = 75
sprint_field_of_view_add_degrees = 6
holster_seconds = 0.2
look_sensitivity_turns_per_1000_pixels = 0.4
eye_height_metres = 1.7
health = 150
downed_bleed_out_seconds = 20
respawn_delay_seconds = 8
revive_seconds = 4
revive_reach_metres = 3
starting_weapon = "pneumatic_wrench"
starting_stock = "iron_plate:200"
[belt]
items_per_second = 4
items_per_tile = 4
[machine]
input_buffer_crafts = 2
[survey]
height_metres = 26
transition_seconds = 0.4
pitch_degrees = 68
[power]
baseline_supply_kw = 300
[nest]
health = 6000
delivery_reach_metres = 5
store_capacity_per_item = 200
[wave]
telegraph_seconds = 12
spawn_interval_seconds = 0.5
call_early_bounty_per_item = 25

[heat]
per_craft = 2
per_craft_per_depth = 1
decay_per_minute = 240
wave_interval_baseline_seconds = 150
wave_interval_minimum_seconds = 40
per_second_sooner = 20
[depth]
draw_percent_per_depth = 60
breach_tier = 2
breach_crafts = 40
breach_offset_tiles = 6
breach_telegraph_seconds = 45
[gear]
enemy_hit_radius_metres = 0.6
enemy_hit_height_metres = 1.6
view_kick_degrees_per_shot = 0.35
view_kick_recover_seconds = 0.5
[enemy]
crawler_health = 30
player_bite_reach_metres = 1.6
crawler_speed_metres_per_second = 3
crawler_damage = 10
crawler_attack_interval_seconds = 1
breaker_health = 240
breaker_speed_metres_per_second = 2
breaker_damage = 60
breaker_attack_interval_seconds = 1
[wall]
health = 240
[wrench]
repair_points_per_second = 60
reach_metres = 4
"""


## A Simulation whose look sensitivity is exactly 0.4 turns per 1000 pixels.
func _looking_sim(players: int = 1) -> Simulation:
	var machines: String = FileAccess.get_file_as_string("res://content/machines.csv")
	var recipes: String = FileAccess.get_file_as_string("res://content/recipes.csv")
	var definitions: Definitions = Definitions.parse(machines, recipes, LOOK_TUNING, WAVES, DELIVERIES, GEAR)
	assert_true(definitions.errors.is_empty(), "the look fixture's content must load")
	return Simulation.new(0, players, definitions)

## The shipped Wave composition, inline so the fixture is a complete definition set. A
## Wave's contents are a table (`content/waves.csv`), and a set with no rows in it is an
## error rather than a Run that is never attacked.
const WAVES: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,6,150,40
"""


func _step_many(sim: Simulation, actions: Array, ticks: int) -> void:
	for tick: int in range(ticks):
		sim.step(actions)


# ── Looking ───────────────────────────────────────────────────────────────────
# Mouse look is the one device reading that is genuinely continuous, so it is the
# one most likely to smuggle a float into the Simulation. The intent that crosses is
# a quantised count of pixels; the Simulation owns the sensitivity, exactly as it
# owns the walking speed, so the angle is a function of state and tuning rather
# than of whatever number a client felt like sending.

func test_a_player_starts_facing_along_negative_z_and_level() -> void:
	var sim: Simulation = Simulation.new()
	assert_eq(sim.query_player_yaw_turns(0), 0, "yaw 0 looks down -z, as Godot's forward does")
	assert_eq(sim.query_player_pitch_turns(0), 0, "and level with the horizon")


func test_moving_the_mouse_right_turns_the_player_clockwise() -> void:
	var sim: Simulation = _looking_sim()
	# 500 pixels is half a thousand; half of 0.4 turns is 0.2 turns, which is
	# 13107.2 in fixed point and floors to 13107. Turning right is a *decrease* in
	# yaw, because a positive rotation about Godot's +y axis turns left.
	sim.step([InputAction.look(0, Fixed.from_int(500), 0)])
	assert_eq(sim.query_player_yaw_turns(0), Fixed.TURN - 13107)


func test_moving_the_mouse_left_turns_the_player_the_other_way() -> void:
	var sim: Simulation = _looking_sim()
	sim.step([InputAction.look(0, Fixed.from_int(-500), 0)])
	assert_eq(sim.query_player_yaw_turns(0), 13107)


func test_yaw_wraps_rather_than_growing_without_bound() -> void:
	var sim: Simulation = _looking_sim()
	# 2500 pixels is one whole turn at this sensitivity: 2.5 × 0.4. Three of those
	# is three turns, which has to read as facing forward again.
	_step_many(sim, [InputAction.look(0, Fixed.from_int(2500), 0)], 3)
	assert_true(
		sim.query_player_yaw_turns(0) >= 0 and sim.query_player_yaw_turns(0) < Fixed.TURN,
		"yaw must stay inside one revolution, got %d" % sim.query_player_yaw_turns(0)
	)
	assert_true(
		absi(sim.query_player_yaw_turns(0)) <= 3,
		"three whole turns is no turn at all, got %d" % sim.query_player_yaw_turns(0)
	)


func test_moving_the_mouse_down_pitches_the_view_down() -> void:
	var sim: Simulation = _looking_sim()
	sim.step([InputAction.look(0, 0, Fixed.from_int(250))])
	# A quarter of a thousand pixels is 0.1 turns, 6553.6 floored to 6553.
	assert_eq(sim.query_player_pitch_turns(0), -6553, "down is a negative pitch")


func test_pitch_stops_at_the_vertical_rather_than_rolling_over() -> void:
	var sim: Simulation = Simulation.new()
	_step_many(sim, [InputAction.look(0, 0, Fixed.from_int(2000))], 10)
	# 0.24 of a turn is 86.4 degrees: 15728.64 floored to 15728. Clamped there, so
	# a player can never look through their own feet and come up behind themselves.
	assert_eq(sim.query_player_pitch_turns(0), -15728)

	var up: Simulation = Simulation.new()
	_step_many(up, [InputAction.look(0, 0, Fixed.from_int(-2000))], 10)
	assert_eq(up.query_player_pitch_turns(0), 15728)


func test_a_look_action_turns_only_the_player_who_sent_it() -> void:
	var sim: Simulation = _looking_sim(3)
	sim.step([InputAction.look(1, Fixed.from_int(500), 0)])
	assert_eq(sim.query_player_yaw_turns(0), 0, "player 0 did not look")
	assert_eq(sim.query_player_yaw_turns(1), Fixed.TURN - 13107, "player 1 did")
	assert_eq(sim.query_player_yaw_turns(2), 0, "player 2 did not look")


func test_an_absurd_look_intent_is_clamped_rather_than_obeyed() -> void:
	var sim: Simulation = Simulation.new()
	var honest: Simulation = Simulation.new()
	sim.step([InputAction.look(0, Fixed.from_int(900000), 0)])
	honest.step([InputAction.look(0, Fixed.from_int(10000), 0)])
	assert_eq(
		sim.query_player_yaw_turns(0),
		honest.query_player_yaw_turns(0),
		"a client cannot buy a faster turn by sending a larger number"
	)


func test_where_a_player_is_looking_is_part_of_the_state_hash() -> void:
	var sim: Simulation = Simulation.new()
	var before: int = sim.hash()
	sim.step([InputAction.look(0, Fixed.from_int(500), 0)])
	assert_ne(sim.hash(), before, "a turn is a state change the harness must be able to see")


# ── Walking ───────────────────────────────────────────────────────────────────
# Movement intent is a throttle in the player's *own* frame — forward and strafe —
# and the Simulation rotates it by the yaw it is holding. That is what keeps a
# single source of truth for which way a player faces: the controller does not get
# its own copy of the angle to rotate WASD by, so the two can never disagree.
#
# Intent is also per-tick. Sending no MOVE is how a player stands still, so an idle
# tick in a recorded script is a tick spent slowing down rather than one spent
# coasting on a stale throttle.

## 625 pixels of mouse travel is exactly a quarter turn at the tuned sensitivity:
## 0.4 turns per thousand pixels, so 2500 pixels is one revolution.
const QUARTER_TURN_PIXELS: int = 625


func test_a_player_walks_forward_along_the_way_they_are_looking() -> void:
	var sim: Simulation = Simulation.new()
	sim.step([InputAction.move(0, Fixed.ONE, 0)])
	assert_true(sim.query_player_position(0).z < 0, "yaw 0 faces -z, so forward is -z")
	assert_eq(sim.query_player_position(0).x, 0, "and nowhere along x")


func test_turning_a_quarter_turn_turns_which_way_forward_is() -> void:
	var sim: Simulation = _looking_sim()
	sim.step([InputAction.look(0, Fixed.from_int(-QUARTER_TURN_PIXELS), 0)])
	assert_eq(sim.query_player_yaw_turns(0), Fixed.QUARTER_TURN, "the premise of the rest")

	sim.step([InputAction.move(0, Fixed.ONE, 0)])
	assert_true(
		sim.query_player_position(0).x < 0,
		"a quarter turn left of -z is -x, got x %d" % sim.query_player_position(0).x
	)
	assert_eq(sim.query_player_position(0).z, 0, "and nothing more along z")


func test_strafing_moves_sideways_rather_than_forwards() -> void:
	var sim: Simulation = Simulation.new()
	sim.step([InputAction.move(0, 0, Fixed.ONE)])
	assert_true(sim.query_player_position(0).x > 0, "strafing right of -z is +x")
	assert_eq(sim.query_player_position(0).z, 0)


func test_a_player_takes_a_moment_to_reach_full_walking_speed() -> void:
	var sim: Simulation = Simulation.new()
	var walking: Array = [InputAction.move(0, Fixed.ONE, 0)]

	sim.step(walking)
	assert_eq(
		sim.query_player_velocity(0).z,
		-ACCELERATION_PER_TICK,
		"one tick of 24 m/s squared is 0.4 m/s"
	)
	assert_eq(sim.query_player_position(0).z, -437, "0.4 m/s for a sixtieth of a second")

	_step_many(sim, walking, 19)
	assert_eq(
		sim.query_player_velocity(0).z, -WALK_SPEED, "and a third of a second gets there"
	)


func test_a_player_never_walks_faster_than_the_tuned_speed() -> void:
	var sim: Simulation = Simulation.new()
	_step_many(sim, [InputAction.move(0, Fixed.ONE, 0)], 600)
	assert_eq(
		sim.query_player_velocity(0).z,
		-WALK_SPEED,
		"ten seconds of walking is still 4 m/s, not 40"
	)


func test_releasing_the_keys_slows_a_player_down_rather_than_stopping_them_dead() -> void:
	# **Starting and stopping do not share a figure**, which is #29's central change:
	# `player.walk_deceleration_metres_per_second_squared` is 9 against the acceleration's
	# 24, because a body leans into a start and slides into a stop. 9 m/s² ÷ 60 ticks is
	# 0.15 m/s a tick; 0.15 × 65536 is 9830.4, which floors to 9830.
	var sim: Simulation = Simulation.new()
	_step_many(sim, [InputAction.move(0, Fixed.ONE, 0)], 30)

	sim.step([])
	assert_eq(
		sim.query_player_velocity(0).z,
		-WALK_SPEED + DECELERATION_PER_TICK,
		"one tick of letting go sheds one tick of deceleration, not one of acceleration"
	)

	# 4 m/s at 0.15 m/s a tick is 27 ticks of slide, against the 10 it would have been at
	# the acceleration figure. That difference is the whole of what a player feels.
	_step_many(sim, [], 15)
	assert_true(
		sim.query_player_velocity(0).z < 0, "still sliding after a quarter of a second"
	)
	_step_many(sim, [], 15)
	assert_eq(sim.query_player_velocity(0).z, 0, "and then the player is standing still")


func test_a_player_stops_more_slowly_than_they_start() -> void:
	# The asymmetry itself, asserted without reference to either figure: the ticks a player
	# takes to come to rest from walking pace against the ticks they took to reach it.
	# One figure for both is the commonest cause of a first-person game feeling weightless,
	# so this is the assertion that fails if somebody ever collapses them back together.
	var sim: Simulation = Simulation.new()
	var walking: Array = [InputAction.move(0, Fixed.ONE, 0)]
	var to_speed: int = 0
	while to_speed < 600 and sim.query_player_velocity(0).z != -WALK_SPEED:
		sim.step(walking)
		to_speed += 1

	var to_rest: int = 0
	while to_rest < 600 and sim.query_player_velocity(0).z != 0:
		sim.step([])
		to_rest += 1

	assert_true(
		to_rest > to_speed,
		"took %d ticks to reach walking pace and %d to stop" % [to_speed, to_rest]
	)


func test_a_standing_player_does_not_drift() -> void:
	var sim: Simulation = Simulation.new()
	_step_many(sim, [], 60)
	assert_eq(sim.query_player_position(0).x, 0)
	assert_eq(sim.query_player_position(0).z, 0)


func test_walking_diagonally_is_no_faster_than_walking_straight() -> void:
	# Forward and strafe at once is a throttle of root two, which would make a
	# player 41% faster on the diagonal if it were taken literally. The intent is
	# normalised to at most unit length instead.
	var sim: Simulation = Simulation.new()
	_step_many(sim, [InputAction.move(0, Fixed.ONE, Fixed.ONE)], 60)

	var velocity: FixedVec2 = sim.query_player_velocity(0)
	var speed: int = Fixed.sqrt(
		Fixed.mul(velocity.x, velocity.x) + Fixed.mul(velocity.z, velocity.z)
	)
	assert_true(
		absi(speed - WALK_SPEED) <= 64,
		"expected 4 m/s on the diagonal too, got %d" % speed
	)


func test_how_fast_a_player_is_moving_is_part_of_the_state_hash() -> void:
	# Velocity outlives the tick that created it — a player who let go a moment ago
	# is still sliding — so it is state, and state the harness cannot see is state
	# that can diverge unnoticed.
	var sliding: Simulation = Simulation.new()
	var standing: Simulation = Simulation.new()
	_step_many(sliding, [InputAction.move(0, Fixed.ONE, 0)], 10)
	_step_many(standing, [], 10)
	assert_ne(sliding.hash(), standing.hash())


# ── Survey View ───────────────────────────────────────────────────────────────
# A Factory is illegible at eye level, which is the whole reason Survey View exists
# (DESIGN.md). It is held rather than toggled, and it is not a mode: building works
# the same at either height, so nothing here gates a build.
#
# The transition lives in the Simulation rather than in the camera, and that is a
# deliberate choice about *feel* rather than about determinism. A height and a
# duration in `content/tuning.toml` can be adjusted while the game runs; a tween
# written into the renderer cannot, and the only way to find out whether a lift
# feels good is to try several.

## 1.7 m of eye height in fixed point: 17/10 × 65536 floors to 111411.
const EYE_HEIGHT: int = 111411

## 26 m of Survey View height.
const SURVEY_HEIGHT: int = 1703936

## 0.4 s of transition at 60 ticks a second.
const TRANSITION_TICKS: int = 24

## 68 degrees of downward tilt, in turns: 68/360 × 65536 floors to 12379.
const SURVEY_PITCH: int = 12379


func test_a_player_looks_out_from_eye_height_by_default() -> void:
	var sim: Simulation = Simulation.new()
	assert_eq(
		sim.query_player_camera_height_metres(0),
		EYE_HEIGHT,
		"1.7 m of eye on a 1.8 m person, against 2 m tiles"
	)
	assert_false(sim.query_player_is_surveying(0))


func test_holding_survey_view_lifts_the_camera_and_tilts_it_down() -> void:
	var sim: Simulation = Simulation.new()
	_step_many(sim, [InputAction.survey_view(0, true)], TRANSITION_TICKS)
	assert_eq(sim.query_player_camera_height_metres(0), SURVEY_HEIGHT, "all the way up")
	assert_eq(
		sim.query_player_camera_pitch_turns(0), -SURVEY_PITCH, "and looking down at the Factory"
	)
	assert_true(sim.query_player_is_surveying(0))


func test_releasing_survey_view_brings_the_camera_back_down() -> void:
	var sim: Simulation = Simulation.new()
	_step_many(sim, [InputAction.survey_view(0, true)], TRANSITION_TICKS)
	_step_many(sim, [InputAction.survey_view(0, false)], TRANSITION_TICKS)
	assert_eq(sim.query_player_camera_height_metres(0), EYE_HEIGHT, "back to eye level")
	assert_eq(sim.query_player_camera_pitch_turns(0), 0, "and level again")


func test_the_lift_takes_the_tuned_time_rather_than_snapping() -> void:
	# The single most important property of this feature for how it feels: an
	# instant snap to 26 m is disorienting, and a slide is not.
	var sim: Simulation = Simulation.new()
	sim.step([InputAction.survey_view(0, true)])
	assert_true(
		sim.query_player_camera_height_metres(0) > EYE_HEIGHT,
		"one tick in, the camera has started to rise"
	)
	assert_true(
		sim.query_player_camera_height_metres(0) < SURVEY_HEIGHT / 4,
		"but is nowhere near the top, got %d" % sim.query_player_camera_height_metres(0)
	)

	_step_many(sim, [InputAction.survey_view(0, true)], TRANSITION_TICKS - 2)
	assert_true(
		sim.query_player_camera_height_metres(0) < SURVEY_HEIGHT,
		"a tick before the end it is still climbing"
	)


func test_the_lift_eases_in_and_out_rather_than_running_at_a_constant_rate() -> void:
	# Halfway through the transition the camera is halfway up — the easing is
	# symmetric — but a quarter of the way through it has covered less than a
	# quarter, because it started from rest.
	var sim: Simulation = Simulation.new()
	_step_many(sim, [InputAction.survey_view(0, true)], TRANSITION_TICKS / 2)
	var halfway: int = sim.query_player_camera_height_metres(0)
	assert_eq(
		halfway,
		EYE_HEIGHT + (SURVEY_HEIGHT - EYE_HEIGHT) / 2,
		"halfway through the time is halfway up"
	)

	var quarter: Simulation = Simulation.new()
	_step_many(quarter, [InputAction.survey_view(0, true)], TRANSITION_TICKS / 4)
	assert_true(
		quarter.query_player_camera_height_metres(0)
		< EYE_HEIGHT + (SURVEY_HEIGHT - EYE_HEIGHT) / 4,
		"a quarter of the way through the time is less than a quarter of the way up"
	)


func test_a_lift_interrupted_halfway_comes_back_down_from_where_it_got_to() -> void:
	var sim: Simulation = Simulation.new()
	_step_many(sim, [InputAction.survey_view(0, true)], TRANSITION_TICKS / 2)
	var reached: int = sim.query_player_camera_height_metres(0)

	sim.step([InputAction.survey_view(0, false)])
	assert_true(
		sim.query_player_camera_height_metres(0) < reached,
		"letting go partway must reverse rather than complete the lift"
	)


func test_a_player_can_still_walk_while_surveying() -> void:
	# Survey View is a camera, not a mode. Nothing about it suspends the player.
	var sim: Simulation = Simulation.new()
	_step_many(
		sim, [InputAction.survey_view(0, true), InputAction.move(0, Fixed.ONE, 0)], 30
	)
	assert_true(sim.query_player_position(0).z < 0, "the player walked while the camera was up")
	assert_eq(sim.query_player_camera_height_metres(0), SURVEY_HEIGHT)


func test_surveying_is_private_to_the_player_who_asked_for_it() -> void:
	var sim: Simulation = Simulation.new(0, 2)
	_step_many(sim, [InputAction.survey_view(1, true)], TRANSITION_TICKS)
	assert_eq(sim.query_player_camera_height_metres(0), EYE_HEIGHT, "player 0 is still on foot")
	assert_eq(sim.query_player_camera_height_metres(1), SURVEY_HEIGHT, "player 1 is not")


func test_the_camera_follows_the_player_rather_than_the_other_way_round() -> void:
	# The camera's ground position is the player's, in Survey View as on foot: the
	# renderer is told where to point and never decides.
	var sim: Simulation = Simulation.new()
	_step_many(sim, [InputAction.survey_view(0, true), InputAction.move(0, Fixed.ONE, 0)], 40)
	assert_eq(sim.query_player_camera_ground_metres(0).x, sim.query_player_position(0).x)
	assert_eq(sim.query_player_camera_ground_metres(0).z, sim.query_player_position(0).z)


func test_where_the_camera_has_got_to_is_part_of_the_state_hash() -> void:
	var lifting: Simulation = Simulation.new()
	var level: Simulation = Simulation.new()
	_step_many(lifting, [InputAction.survey_view(0, true)], 5)
	_step_many(level, [], 5)
	assert_ne(lifting.hash(), level.hash(), "a half-raised camera is a different state")


## The Gear a Run is holding, inline so the fixture is a complete definition set. One
## weapon frame and whatever component this file's Delivery tiers name, because a tier
## naming Gear that does not exist is content somebody broke. These tests are not about
## combat, so the frame is the Pneumatic Wrench and nothing is fitted to it.
const GEAR: String = """id,display_name,kind,attack,damage,range_metres,spread_degrees,seconds_per_shot,ammunition_item,ammunition_per_shot,damage_percent,range_percent,spread_percent,interval_percent,ammunition_percent,damage_taken_percent
pneumatic_wrench,Pneumatic Wrench,weapon,melee,55,4,0,0.6,,0,0,0,0,0,0,0
placeholder_gear,Placeholder Barrel,barrel,,0,0,0,0,,0,10,0,0,0,0,0
"""


## The Delivery tiers, inline so the fixture is a complete definition set. Progression is
## physical (`content/deliveries.csv`), and a table with no rows in it is an error rather
## than a Run with no progression. This one unlocks a Gear component and names no Machine,
## so nothing this file builds is locked behind it — `test_delivery.gd` is where locking is
## asserted.
const DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_opening,Opening Licence,1,iron_plate:1,,placeholder_gear,
"""
