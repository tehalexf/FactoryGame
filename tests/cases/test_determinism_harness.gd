## The determinism harness, and the proof that it has teeth.
##
## ADR 0002 rests on one promise: a recorded script of Input Actions, replayed
## from an identical starting state, reproduces the same hash on every tick. This
## file asserts that promise holds — and, more importantly, that the harness
## notices when it does not.
##
## A harness that always reports success is worse than no harness, because it
## converts an unknown risk into a false sense of safety. So the second half of
## this file deliberately breaks determinism in each of the ways ADR 0002 forbids
## and requires the harness to catch every one.
extends TestCase


const SEED: int = 20261006
const PLAYERS: int = 2


## A script that actually stirs the state: both players moving on both axes, with
## idle ticks mixed in. A script of pure idle ticks would let a broken harness
## pass by comparing one unchanging hash against itself.
func _busy_script() -> InputScript:
	var script: InputScript = InputScript.new()
	script.add_tick([InputAction.move(0, Fixed.ONE, 0)])
	script.add_tick([InputAction.move(0, Fixed.ONE, Fixed.HALF), InputAction.move(1, -Fixed.ONE, 0)])
	script.add_idle_ticks(2)
	script.add_tick([InputAction.move(1, 0, Fixed.ONE)])
	script.add_tick([InputAction.move(0, -Fixed.HALF, -Fixed.ONE)])
	script.add_idle_ticks(1)
	script.add_tick([InputAction.move(0, Fixed.from_rational(1, 3), Fixed.from_rational(-2, 7))])
	return script


func _recording() -> ReplayRecording:
	return DeterminismHarness.record(_busy_script(), SEED, PLAYERS)


# ── Recording ─────────────────────────────────────────────────────────────────

func test_a_recording_captures_one_hash_per_tick_plus_the_initial_state() -> void:
	var script: InputScript = _busy_script()
	var recording: ReplayRecording = DeterminismHarness.record(script, SEED, PLAYERS)
	assert_eq(
		recording.hashes.size(),
		script.tick_count() + 1,
		"every tick needs a hash, and so does the starting state"
	)


func test_a_recording_remembers_how_to_rebuild_the_starting_state() -> void:
	var recording: ReplayRecording = _recording()
	assert_eq(recording.world_seed, SEED)
	assert_eq(recording.player_count, PLAYERS)


func test_the_recorded_hashes_actually_change() -> void:
	# Guards every other test in this file: if the hash were constant, a harness
	# that compared nothing at all would still look correct.
	var recording: ReplayRecording = _recording()
	var distinct: Dictionary = {}
	for value: int in recording.hashes:
		distinct[value] = true
	assert_true(
		distinct.size() >= recording.hashes.size() - 1,
		"expected the state hash to move almost every tick, saw %d distinct of %d"
			% [distinct.size(), recording.hashes.size()]
	)


func test_recording_the_same_script_twice_gives_the_same_hashes() -> void:
	var first: ReplayRecording = _recording()
	var second: ReplayRecording = _recording()
	assert_eq(first.hashes, second.hashes, "recording must itself be reproducible")


func test_an_empty_script_records_only_the_initial_state() -> void:
	var recording: ReplayRecording = DeterminismHarness.record(InputScript.new(), SEED, PLAYERS)
	assert_eq(recording.hashes.size(), 1)


# ── Replay ────────────────────────────────────────────────────────────────────

func test_replaying_a_recording_reproduces_every_tick() -> void:
	var recording: ReplayRecording = _recording()
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, "the promise of ADR 0002: %s" % divergence.describe())


func test_replay_compares_every_tick_not_merely_the_last() -> void:
	var recording: ReplayRecording = _recording()
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_eq(
		divergence.ticks_compared,
		recording.hashes.size(),
		"the initial state and every tick after it must be checked"
	)


func test_an_empty_script_still_verifies_the_starting_state() -> void:
	var recording: ReplayRecording = DeterminismHarness.record(InputScript.new(), SEED, PLAYERS)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical)
	assert_eq(divergence.ticks_compared, 1)


func test_a_different_seed_diverges_before_the_first_tick() -> void:
	var recording: ReplayRecording = _recording()
	var wrong_start: Simulation = Simulation.new(SEED + 1, PLAYERS)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording, wrong_start)
	assert_false(divergence.is_identical, "a different starting state is a divergence")
	assert_eq(divergence.tick, 0, "and it is visible at tick 0, before anything is stepped")


func test_a_different_player_count_diverges() -> void:
	var recording: ReplayRecording = _recording()
	var wrong_start: Simulation = Simulation.new(SEED, PLAYERS + 1)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording, wrong_start)
	assert_false(divergence.is_identical)


func test_a_faithful_replacement_simulation_does_not_diverge() -> void:
	# The control for the injection tests below. Without it, those tests would
	# only show that *some* replacement diverges, not that the injected fault is
	# what caused it.
	var recording: ReplayRecording = _recording()
	var faithful: Simulation = Simulation.new(SEED, PLAYERS)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording, faithful)
	assert_true(divergence.is_identical, divergence.describe())


func test_the_divergence_report_names_the_tick_and_both_hashes() -> void:
	var recording: ReplayRecording = _recording()
	var leaky: Simulation = WallClockSimulation.new(SEED, PLAYERS)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording, leaky)
	assert_false(divergence.is_identical)
	assert_ne(divergence.expected_hash, divergence.actual_hash, "the two hashes must differ")
	assert_true(divergence.tick >= 0)
	assert_true(
		divergence.describe().contains(str(divergence.tick)),
		"the description should be usable on its own: %s" % divergence.describe()
	)


# ── Proof that the harness catches real non-determinism ───────────────────────

func test_the_harness_catches_a_simulation_that_reads_the_wall_clock() -> void:
	var recording: ReplayRecording = _recording()
	var leaky: Simulation = WallClockSimulation.new(SEED, PLAYERS)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording, leaky)
	assert_false(
		divergence.is_identical,
		"a Simulation that reads real time must be caught"
	)
	assert_eq(divergence.tick, 1, "and caught on the very first tick that reads it")


func test_the_harness_catches_a_simulation_that_uses_unseeded_randomness() -> void:
	var recording: ReplayRecording = _recording()
	var leaky: Simulation = UnseededRandomSimulation.new(SEED, PLAYERS)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording, leaky)
	assert_false(
		divergence.is_identical,
		"a Simulation drawing from the engine's global RNG must be caught"
	)
	assert_eq(divergence.tick, 1)


func test_the_harness_catches_divergence_that_repairs_itself_later() -> void:
	# The sharpest version of the requirement. This Simulation is wrong for two
	# ticks in the middle and then exactly right again, so its FINAL hash matches
	# the recording perfectly. Only per-tick comparison can see it — which is why
	# the acceptance criterion says "the same hash for every tick" and not "the
	# same hash at the end".
	var recording: ReplayRecording = _recording()
	var transient: TransientlyWrongSimulation = TransientlyWrongSimulation.new(SEED, PLAYERS)

	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording, transient)
	assert_false(divergence.is_identical, "a transient divergence must still be caught")
	assert_eq(divergence.tick, 3, "reported at the first tick that differs")

	# Prove the trap is real: the same Simulation run to the end lands on the
	# recorded final hash, so a final-hash-only check would have passed it.
	var replayed: TransientlyWrongSimulation = TransientlyWrongSimulation.new(SEED, PLAYERS)
	for tick_index: int in range(recording.input_script.tick_count()):
		replayed.step(recording.input_script.actions_at(tick_index))
	assert_eq(
		replayed.hash(),
		recording.hashes[recording.hashes.size() - 1],
		"the self-repairing Simulation really does end in the recorded state"
	)


# ── The deliberately broken Simulations ───────────────────────────────────────
# Each one breaks exactly one rule from ADR 0002. They live here, in the test
# file, so no unsanctioned call ever appears in res://sim/.

## Breaks "no wall-clock time".
class WallClockSimulation extends Simulation:
	func step(actions: Array) -> void:
		super(actions)
		_player_x[0] += Time.get_ticks_usec()


## Breaks "no unseeded randomness" by drawing from the engine's global stream,
## which is seeded at startup and shared with everything else in the process.
class UnseededRandomSimulation extends Simulation:
	func step(actions: Array) -> void:
		super(actions)
		_player_z[0] += randi()


## Deterministic in itself, but not the same as the recorded Simulation: wrong on
## tick 3, and exactly right again from tick 4 onward.
class TransientlyWrongSimulation extends Simulation:
	func step(actions: Array) -> void:
		super(actions)
		if query_tick() == 3:
			_player_x[0] += Fixed.from_int(1000)
		elif query_tick() == 4:
			_player_x[0] -= Fixed.from_int(1000)
