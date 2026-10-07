## Record Input Actions, replay them, assert the state hash matches tick for tick.
##
## This is the mitigation ADR 0002 commits to, and the reason co-op can be left
## until last: determinism is testable in single-player, so the risk that sinks
## lockstep projects is retired long before any networking exists.
##
## The comparison is per-tick, never final-state-only. A fault that perturbs the
## Simulation for a few ticks and then settles back — a Machine that finishes one
## tick early, a Wave timer that rounds differently — leaves the end state intact
## and would sail through a final-hash check. In lockstep that is a desync.
##
## `verify` accepts a replacement Simulation so a test can replay a recording into
## something deliberately broken and confirm the harness notices. That is what
## keeps the harness honest: a check that never fails is indistinguishable from no
## check at all.
class_name DeterminismHarness
extends RefCounted


## The verdict of a replay: either identical throughout, or the first tick where
## it was not.
class Divergence extends RefCounted:
	var is_identical: bool = true
	## The tick the hashes first differed at. 0 means the starting states already
	## differed, before anything was stepped. -1 when identical.
	var tick: int = -1
	var expected_hash: int = 0
	var actual_hash: int = 0
	## How many hashes were compared — the starting state plus one per tick.
	var ticks_compared: int = 0
	## Set when the replay was fed different inputs than were recorded, which
	## would otherwise look like a divergence in the Simulation.
	var script_mismatch: bool = false

	func describe() -> String:
		if script_mismatch:
			return "replay was fed a different Input Action script than was recorded"
		if is_identical:
			return "identical across %d compared states" % ticks_compared
		if tick == 0:
			return "starting states differ: expected hash %d, got %d" % [expected_hash, actual_hash]
		return (
			"diverged at tick %d: expected hash %d, got %d"
			% [tick, expected_hash, actual_hash]
		)


## Runs `script` against a fresh Simulation and captures the hash at every point.
static func record(script: InputScript, world_seed: int = 0, player_count: int = 1) -> ReplayRecording:
	var sim: Simulation = Simulation.new(world_seed, player_count)

	var recording: ReplayRecording = ReplayRecording.new()
	recording.world_seed = world_seed
	recording.player_count = player_count
	recording.input_script = script
	recording.script_digest = script.digest()

	recording.hashes = PackedInt64Array()
	recording.hashes.append(sim.hash())
	for tick_index: int in range(script.tick_count()):
		sim.step(script.actions_at(tick_index))
		recording.hashes.append(sim.hash())

	return recording


## Replays a recording and reports the first divergence, if any.
##
## Pass `replacement_sim` to replay into something other than a fresh faithful
## Simulation — a subclass with an injected fault, or a Simulation restored from a
## save file, which is how the save/load ticket proves a round trip is exact.
static func verify(recording: ReplayRecording, replacement_sim: Simulation = null) -> Divergence:
	var divergence: Divergence = Divergence.new()

	if recording == null or recording.input_script == null:
		divergence.is_identical = false
		divergence.tick = 0
		return divergence

	# Guard against the embarrassing failure mode where the harness proves two
	# different scripts produce different hashes and calls it a desync.
	if recording.input_script.digest() != recording.script_digest:
		divergence.is_identical = false
		divergence.script_mismatch = true
		divergence.tick = 0
		return divergence

	var sim: Simulation = replacement_sim
	if sim == null:
		sim = Simulation.new(recording.world_seed, recording.player_count)

	# The starting state is compared before any tick is stepped. Lockstep's first
	# requirement is an identical state to start from, so a mismatch here is a
	# different and more serious fault than a drift later on.
	divergence.ticks_compared = 1
	if sim.hash() != recording.hash_at(0):
		return _diverged(divergence, 0, recording.hash_at(0), sim.hash())

	for tick_index: int in range(recording.input_script.tick_count()):
		sim.step(recording.input_script.actions_at(tick_index))

		var tick_number: int = tick_index + 1
		divergence.ticks_compared += 1

		var expected: int = recording.hash_at(tick_number)
		var actual: int = sim.hash()
		if actual != expected:
			return _diverged(divergence, tick_number, expected, actual)

	return divergence


static func _diverged(divergence: Divergence, tick: int, expected: int, actual: int) -> Divergence:
	divergence.is_identical = false
	divergence.tick = tick
	divergence.expected_hash = expected
	divergence.actual_hash = actual
	return divergence
