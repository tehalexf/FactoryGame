## The boundary between Godot's variable frame time and the Simulation's fixed
## ticks.
##
## This is the only place a float is allowed to influence *when* the Simulation
## steps — and it still cannot influence *what* a step computes, because all it
## ever produces is a whole number of ticks.
extends TestCase

const HZ: int = Simulation.TICKS_PER_SECOND


func _pump() -> TickPump:
	return TickPump.new(HZ)


func test_exactly_one_tick_of_frame_time_yields_one_tick() -> void:
	assert_eq(_pump().advance(1.0 / HZ), 1)


func test_less_than_a_tick_yields_nothing_yet() -> void:
	var pump: TickPump = _pump()
	assert_eq(pump.advance(0.5 / HZ), 0, "a partial tick is never run as a partial tick")


func test_leftover_time_is_carried_and_not_lost() -> void:
	var pump: TickPump = _pump()
	pump.advance(0.5 / HZ)
	assert_eq(pump.advance(0.5 / HZ), 1, "two halves make a whole tick")


func test_a_long_frame_yields_several_ticks() -> void:
	# Headroom above the default clamp, so this measures catch-up rather than the
	# clamp that the stall test covers.
	var pump: TickPump = TickPump.new(HZ, 16)
	assert_eq(pump.advance(10.0 / HZ), 10, "the Simulation catches up in whole ticks")


func test_the_default_clamp_bounds_catch_up() -> void:
	assert_eq(
		_pump().advance(10.0 / HZ),
		TickPump.DEFAULT_MAX_TICKS_PER_FRAME,
		"the default pump refuses to run an unbounded number of ticks in one frame"
	)


func test_zero_and_negative_frame_time_yield_nothing() -> void:
	assert_eq(_pump().advance(0.0), 0)
	assert_eq(_pump().advance(-1.0), 0, "a clock that went backwards must not rewind the Run")


func test_a_stall_is_clamped_so_the_simulation_cannot_spiral() -> void:
	var pump: TickPump = TickPump.new(HZ, 5)
	assert_eq(
		pump.advance(100.0),
		5,
		"a long stall must not demand a hundred seconds of simulation in one frame"
	)


func test_a_clamped_stall_discards_the_backlog_rather_than_queueing_it() -> void:
	# Game time slows down rather than the frame rate collapsing while the
	# Simulation tries to catch up on a debt it can never pay off.
	var pump: TickPump = TickPump.new(HZ, 5)
	pump.advance(100.0)
	assert_eq(pump.advance(1.0 / HZ), 1, "the next frame is back to normal")


func test_tick_production_does_not_drift_over_many_frames() -> void:
	# An accumulator that reset its remainder each frame would lose time steadily.
	# Three hundred frames of an awkward, non-dividing frame time should still
	# produce the right number of ticks.
	var pump: TickPump = _pump()
	var frame_time: float = 1.0 / 144.0
	var total: int = 0
	for frame: int in range(300):
		total += pump.advance(frame_time)

	var elapsed_seconds: float = frame_time * 300.0
	var expected: int = int(elapsed_seconds * HZ)
	assert_true(
		absi(total - expected) <= 1,
		"expected about %d ticks over %f s, got %d" % [expected, elapsed_seconds, total]
	)


func test_the_pump_reports_its_rate() -> void:
	assert_eq(_pump().ticks_per_second, HZ)
