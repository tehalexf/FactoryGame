## The Simulation façade, which is the project's only test seam.
##
## Everything here goes through `step`, `hash` and the `query_*` projections. No
## test reaches behind them, so the modules that will eventually live back there —
## Belts, Power, Waves — can be rewritten freely without touching this file.
extends TestCase


func test_a_new_simulation_starts_at_tick_zero() -> void:
	var sim: Simulation = Simulation.new()
	assert_eq(sim.query_tick(), 0)


func test_stepping_advances_exactly_one_tick() -> void:
	var sim: Simulation = Simulation.new()
	sim.step([])
	assert_eq(sim.query_tick(), 1, "a step is one whole tick, never a fraction")


func test_stepping_repeatedly_counts_ticks() -> void:
	var sim: Simulation = Simulation.new()
	for i: int in range(37):
		sim.step([])
	assert_eq(sim.query_tick(), 37)


func test_stepping_with_no_actions_is_legal() -> void:
	var sim: Simulation = Simulation.new()
	sim.step([])
	sim.step([])
	assert_eq(sim.query_tick(), 2, "an idle tick is a normal tick")


# ── Hashing ───────────────────────────────────────────────────────────────────

func test_hashing_does_not_change_the_simulation() -> void:
	var sim: Simulation = Simulation.new()
	var first: int = sim.hash()
	assert_eq(sim.hash(), first, "hash must be a pure read")
	assert_eq(sim.query_tick(), 0, "hashing must not advance anything")


func test_the_same_seed_produces_the_same_starting_hash() -> void:
	var a: Simulation = Simulation.new(4321)
	var b: Simulation = Simulation.new(4321)
	assert_eq(a.hash(), b.hash(), "identical construction means identical state")


func test_a_different_seed_produces_a_different_starting_hash() -> void:
	var a: Simulation = Simulation.new(1)
	var b: Simulation = Simulation.new(2)
	assert_ne(a.hash(), b.hash(), "the seed is part of the state, so it is hashed")


func test_a_different_player_count_produces_a_different_hash() -> void:
	var one: Simulation = Simulation.new(7, 1)
	var four: Simulation = Simulation.new(7, 4)
	assert_ne(one.hash(), four.hash())


func test_the_hash_tracks_the_tick() -> void:
	var sim: Simulation = Simulation.new(9)
	var at_zero: int = sim.hash()
	sim.step([])
	assert_ne(sim.hash(), at_zero, "the tick number is part of the state")


func test_two_simulations_stepped_alike_stay_hash_identical() -> void:
	var a: Simulation = Simulation.new(11)
	var b: Simulation = Simulation.new(11)
	for i: int in range(50):
		a.step([])
		b.step([])
		if not assert_eq(a.hash(), b.hash(), "diverged at tick %d" % a.query_tick()):
			return


# ── Players ───────────────────────────────────────────────────────────────────

func test_player_count_is_what_was_asked_for() -> void:
	assert_eq(Simulation.new(0, 1).query_player_count(), 1)
	assert_eq(Simulation.new(0, 4).query_player_count(), 4)


func test_player_count_is_at_least_one() -> void:
	assert_eq(Simulation.new(0, 0).query_player_count(), 1, "a Run has at least one player")
	assert_eq(Simulation.new(0, -5).query_player_count(), 1)


func test_players_start_at_the_origin() -> void:
	var sim: Simulation = Simulation.new(0, 2)
	for player_id: int in range(2):
		var position: FixedVec2 = sim.query_player_position(player_id)
		assert_eq(position.x, 0, "player %d x" % player_id)
		assert_eq(position.z, 0, "player %d z" % player_id)


func test_querying_an_unknown_player_gives_the_origin_rather_than_crashing() -> void:
	var sim: Simulation = Simulation.new(0, 1)
	var position: FixedVec2 = sim.query_player_position(99)
	assert_not_null(position, "a bad id must not crash a Run in lockstep")
	assert_eq(position.x, 0)
	assert_eq(position.z, 0)


func test_a_query_result_cannot_be_used_to_mutate_state() -> void:
	var sim: Simulation = Simulation.new(0, 1)
	var position: FixedVec2 = sim.query_player_position(0)
	position.x = Fixed.from_int(500)
	assert_eq(
		sim.query_player_position(0).x,
		0,
		"queries must project a copy, not hand out a reference into state"
	)


# ── Input Actions ─────────────────────────────────────────────────────────────
# A full-throttle tick covers 4 m/s ÷ 60 ticks. That is 4369.066… in fixed point,
# which floors to 4369 — so the expected values below are deliberately the
# quantised ones. Fixed point is exact, not infinitely precise, and a test that
# expected 4369.066 would be testing a float.

const STEP_PER_TICK: int = 4369


func test_a_move_action_moves_the_player() -> void:
	var sim: Simulation = Simulation.new()
	sim.step([InputAction.move(0, Fixed.ONE, 0)])
	assert_eq(sim.query_player_position(0).x, STEP_PER_TICK, "one tick of full throttle")
	assert_eq(sim.query_player_position(0).z, 0, "no intent along z, no movement along z")


func test_movement_accumulates_over_ticks() -> void:
	var sim: Simulation = Simulation.new()
	for i: int in range(60):
		sim.step([InputAction.move(0, Fixed.ONE, 0)])
	assert_eq(
		sim.query_player_position(0).x,
		STEP_PER_TICK * 60,
		"a second of walking, quantised per tick"
	)


func test_a_negative_intent_moves_the_other_way() -> void:
	var sim: Simulation = Simulation.new()
	sim.step([InputAction.move(0, -Fixed.ONE, 0)])
	assert_eq(sim.query_player_position(0).x, -STEP_PER_TICK)


func test_partial_intent_moves_proportionally() -> void:
	var sim: Simulation = Simulation.new()
	sim.step([InputAction.move(0, Fixed.HALF, 0)])
	# floor(32768 * 4369 / 65536) = floor(2184.5)
	assert_eq(sim.query_player_position(0).x, 2184, "half throttle, floored")


func test_intent_beyond_full_throttle_is_clamped() -> void:
	var sim: Simulation = Simulation.new()
	sim.step([InputAction.move(0, Fixed.from_int(1000), 0)])
	assert_eq(
		sim.query_player_position(0).x,
		STEP_PER_TICK,
		"the Simulation owns speed; an oversized intent must not buy more of it"
	)


func test_an_action_moves_only_the_player_who_sent_it() -> void:
	var sim: Simulation = Simulation.new(0, 3)
	sim.step([InputAction.move(1, Fixed.ONE, 0)])
	assert_eq(sim.query_player_position(0).x, 0, "player 0 did not move")
	assert_eq(sim.query_player_position(1).x, STEP_PER_TICK, "player 1 did")
	assert_eq(sim.query_player_position(2).x, 0, "player 2 did not move")


func test_several_actions_in_one_tick_all_apply() -> void:
	var sim: Simulation = Simulation.new(0, 2)
	sim.step([
		InputAction.move(0, Fixed.ONE, 0),
		InputAction.move(1, 0, Fixed.ONE),
	])
	assert_eq(sim.query_player_position(0).x, STEP_PER_TICK)
	assert_eq(sim.query_player_position(1).z, STEP_PER_TICK)


func test_repeated_actions_from_one_player_in_one_tick_accumulate() -> void:
	var sim: Simulation = Simulation.new()
	sim.step([
		InputAction.move(0, Fixed.ONE, 0),
		InputAction.move(0, Fixed.ONE, 0),
	])
	assert_eq(
		sim.query_player_position(0).x,
		STEP_PER_TICK * 2,
		"actions apply in order, each one fully"
	)


func test_a_none_action_changes_nothing_but_the_tick() -> void:
	var sim: Simulation = Simulation.new(3)
	var idle: Simulation = Simulation.new(3)
	sim.step([InputAction.none(0)])
	idle.step([])
	assert_eq(sim.hash(), idle.hash(), "an explicit no-op must be exactly a no-op")


func test_an_action_from_an_unknown_player_is_ignored() -> void:
	var sim: Simulation = Simulation.new(0, 1)
	sim.step([InputAction.move(99, Fixed.ONE, Fixed.ONE)])
	assert_eq(sim.query_tick(), 1, "the tick still happens")
	assert_eq(sim.query_player_position(0).x, 0, "nobody moved")


func test_a_null_action_is_ignored() -> void:
	var sim: Simulation = Simulation.new()
	sim.step([null, InputAction.move(0, Fixed.ONE, 0)])
	assert_eq(sim.query_player_position(0).x, STEP_PER_TICK, "the real action still applied")


func test_movement_changes_the_hash() -> void:
	var moved: Simulation = Simulation.new(5)
	var still: Simulation = Simulation.new(5)
	moved.step([InputAction.move(0, Fixed.ONE, 0)])
	still.step([])
	assert_ne(moved.hash(), still.hash(), "player position is part of the hashed state")


func test_moving_along_x_and_z_are_distinguishable_in_the_hash() -> void:
	var along_x: Simulation = Simulation.new(5)
	var along_z: Simulation = Simulation.new(5)
	along_x.step([InputAction.move(0, Fixed.ONE, 0)])
	along_z.step([InputAction.move(0, 0, Fixed.ONE)])
	assert_ne(along_x.hash(), along_z.hash(), "the axes must not be conflated")
