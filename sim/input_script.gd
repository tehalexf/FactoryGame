## An ordered sequence of ticks, each carrying the Input Actions intended for it.
##
## This is what "a recorded script of Input Actions" means: tick 0's actions, then
## tick 1's, and so on. A tick with no actions is still a tick, because an idle
## tick advances the Simulation and so belongs in the script.
##
## Later tickets build these two ways — by hand, as a test fixture describing a
## scenario, and by capture, from a real session.
class_name InputScript
extends RefCounted

## One entry per tick, each an Array of InputAction.
var _ticks: Array = []


## Appends a tick carrying the given actions. They are copied, so a caller
## reusing one Array to build several ticks cannot corrupt the script.
func add_tick(actions: Array) -> InputScript:
	var copied: Array = []
	for action: InputAction in actions:
		copied.append(action.duplicate_action() if action != null else null)
	_ticks.append(copied)
	return self


## Appends ticks with no actions. The Simulation still advances through them,
## which is often exactly what a test needs — a Belt moving, a Machine working, a
## Wave timer running down.
func add_idle_ticks(count: int) -> InputScript:
	for i: int in range(maxi(count, 0)):
		_ticks.append([])
	return self


func tick_count() -> int:
	return _ticks.size()


## The actions for a tick. Out-of-range reads as an empty tick.
func actions_at(tick_index: int) -> Array:
	if tick_index < 0 or tick_index >= _ticks.size():
		return []
	return _ticks[tick_index]


## Hashes the script itself. The harness records this alongside the state hashes
## so a replay can prove it was fed the inputs that were recorded, rather than
## comparing state hashes from two different scripts and declaring success.
func digest() -> int:
	var hasher: StateHasher = StateHasher.new()
	hasher.feed_int(_ticks.size())
	for tick: Array in _ticks:
		hasher.feed_int(tick.size())
		for action: InputAction in tick:
			if action == null:
				hasher.feed_int(-1)
			else:
				action.feed_into(hasher)
	return hasher.digest()
