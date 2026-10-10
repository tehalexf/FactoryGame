## A recorded run: how to build the starting state, what was done each tick, and
## what the state hashed to at every point along the way.
##
## This is the artifact the determinism promise is written down in. Every later
## ticket is expected to leave one or more of these behind as a fixture, so that a
## change to Belts or Power or Wave scheduling that perturbs a tick anywhere is
## caught by a hash mismatch rather than by a co-op session months later.
class_name ReplayRecording
extends RefCounted

## Everything needed to reconstruct the identical starting state.
var world_seed: int = 0
var player_count: int = 1

## The content definitions the Run was made under, or null for "whatever is in
## content/ at replay time". Null is the right default for a fixture: it makes the
## replay read the files again, so a content change that would alter the Run is
## caught by the digest check below instead of passing unnoticed.
var definitions: Definitions = null

## Digest of the definition set the recording was made under. `verify` compares the
## replaying Simulation's definitions against this before it compares a single tick,
## so a recording can never appear to pass against content it was not recorded under
## — and a mismatch is reported as a mismatch, not as a tick divergence that sends
## someone hunting through the wrong code.
var definitions_digest: int = 0

## What was done, tick by tick.
var input_script: InputScript = null

## State hashes. `hashes[0]` is the starting state before any tick is stepped, and
## `hashes[n]` is the state after n ticks. Size is always script.tick_count() + 1.
var hashes: PackedInt64Array = PackedInt64Array()

## Hash of the script itself, so a replay can confirm it was fed the same inputs.
var script_digest: int = 0


func tick_count() -> int:
	return 0 if input_script == null else input_script.tick_count()


## The expected hash after `tick_index` ticks. Index 0 is the starting state.
func hash_at(tick_index: int) -> int:
	if tick_index < 0 or tick_index >= hashes.size():
		return 0
	return hashes[tick_index]
