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
