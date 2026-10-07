## Converts Godot's variable frame time into whole Simulation ticks.
##
## The Simulation has no clock — it only knows which tick it is on — so something
## outside it has to decide when to step. That decision belongs here, on the Godot
## side of the boundary, and this is the only component in the project where real
## elapsed time is allowed to matter.
##
## Note what crosses: a count. Frame time influences *how many* ticks run, never
## what a tick computes. Two machines running the same Input Actions at wildly
## different frame rates still produce identical state, which is what ADR 0002
## requires.
##
## Lives in res://game/ rather than res://sim/ precisely because it uses floats.
class_name TickPump
extends RefCounted

## Default ceiling on ticks produced in one frame.
const DEFAULT_MAX_TICKS_PER_FRAME: int = 8

var ticks_per_second: int = 60
var max_ticks_per_frame: int = DEFAULT_MAX_TICKS_PER_FRAME

var _unspent_seconds: float = 0.0


func _init(rate: int = 60, max_catch_up: int = DEFAULT_MAX_TICKS_PER_FRAME) -> void:
	ticks_per_second = maxi(rate, 1)
	max_ticks_per_frame = maxi(max_catch_up, 1)


## How many whole ticks to run for a frame of `delta_seconds`.
##
## Remainders carry across frames, so a frame time that does not divide evenly
## into the tick rate — which is every real frame time — does not lose game time.
##
## A frame long enough to demand more than `max_ticks_per_frame` is clamped and the
## backlog discarded rather than queued. Queueing it is the classic death spiral:
## the Simulation falls further behind each frame while trying to catch up on a
## debt that only grows. Discarding means a stall makes game time run slow for a
## moment, which is survivable and, in single-player, barely visible.
func advance(delta_seconds: float) -> int:
	if delta_seconds <= 0.0:
		return 0

	_unspent_seconds += delta_seconds

	var seconds_per_tick: float = 1.0 / float(ticks_per_second)
	var ticks: int = int(_unspent_seconds / seconds_per_tick)

	if ticks <= 0:
		return 0

	if ticks > max_ticks_per_frame:
		_unspent_seconds = 0.0
		return max_ticks_per_frame

	_unspent_seconds -= float(ticks) * seconds_per_tick
	return ticks


## Drops any partial tick. Used when a Run is loaded or reset, so leftover time
## from the previous session cannot leak into the new one.
func reset() -> void:
	_unspent_seconds = 0.0
