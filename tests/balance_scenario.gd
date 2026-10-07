## A scripted session, expressed as Input Actions against a tick clock.
##
## The unit `BalanceProbe` plays. It exists because a balance measurement has to be a
## *replayable* thing rather than a narrated one: a scenario is a function from tick number
## to Input Actions and nothing else, so the same scenario run twice is the same Run twice,
## and `to_script` hands it to `DeterminismHarness` unchanged when a test wants that proved.
##
## Deliberately not in `sim/`. This is a test and tooling fixture; the Simulation has never
## heard of it.
class_name BalanceScenario
extends RefCounted

## Identifier used in the report table. Short, lowercase, stable — it is what a later
## balance change is compared against.
var id: String = ""

## One line saying what the player in this scenario is doing, and why it is worth measuring.
var summary: String = ""

## Segments, as parallel arrays: the tick each starts on, how many ticks it covers, and the
## Input Actions it issues on every tick it covers. Parallel arrays rather than a Dictionary
## for the reason the Simulation uses them — the iteration order is the insertion order and
## is therefore a property of the scenario rather than of a hash.
var _start_tick: PackedInt64Array = PackedInt64Array()
var _tick_span: PackedInt64Array = PackedInt64Array()
var _actions: Array = []


static func named(scenario_id: String, what_the_player_does: String) -> BalanceScenario:
	var scenario: BalanceScenario = BalanceScenario.new()
	scenario.id = scenario_id
	scenario.summary = what_the_player_does
	return scenario


## Issues `actions` on exactly one tick.
func at(tick: int, actions: Array) -> BalanceScenario:
	return hold(tick, 1, actions)


## Issues `actions` on every tick of a span — how a held key is expressed. A player walking
## for twenty seconds is one segment and not twelve hundred.
func hold(tick: int, ticks: int, actions: Array) -> BalanceScenario:
	_start_tick.append(maxi(tick, 0))
	_tick_span.append(maxi(ticks, 1))
	_actions.append(actions)
	return self


func at_second(second: int, actions: Array) -> BalanceScenario:
	return at(second * Simulation.TICKS_PER_SECOND, actions)


func hold_seconds(second: int, seconds: int, actions: Array) -> BalanceScenario:
	return hold(
		second * Simulation.TICKS_PER_SECOND, seconds * Simulation.TICKS_PER_SECOND, actions
	)


## The last tick any segment of this scenario touches. After it the player is idle, which is
## the usual shape: a Factory is built in the first minute and then defends itself.
func last_scripted_tick() -> int:
	var last: int = 0
	for index: int in range(_start_tick.size()):
		last = maxi(last, _start_tick[index] + _tick_span[index] - 1)
	return last


## The Input Actions for one tick: every segment covering it, in the order the segments were
## added. A tick no segment covers is an idle tick, which is most of them.
func actions_at(tick: int) -> Array:
	var out: Array = []
	for index: int in range(_start_tick.size()):
		var start: int = _start_tick[index]
		if tick < start or tick >= start + _tick_span[index]:
			continue
		for action: InputAction in _actions[index]:
			out.append(action)
	return out


## The first `ticks` ticks of this scenario as an `InputScript`, so a measurement can be
## handed to `DeterminismHarness` and proved replayable rather than asserted to be.
func to_script(ticks: int) -> InputScript:
	var script: InputScript = InputScript.new()
	for tick: int in range(maxi(ticks, 0)):
		script.add_tick(actions_at(tick))
	return script
