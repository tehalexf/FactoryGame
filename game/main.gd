## The Godot-side root. An input producer and a state reader, nothing more.
##
## ADR 0001 makes Godot a renderer and input layer only, so everything this node
## is allowed to do is:
##
##   1. decide when to step the Simulation (via TickPump),
##   2. translate devices into Input Actions,
##   3. read `query_*` projections back out to draw with.
##
## It holds no authoritative state. Nothing here may write Simulation state except
## by handing Input Actions to `step`, and nothing may read it except through a
## query. That restraint is what keeps the test seam count at one — if this node
## started remembering things, those things would need their own tests and their
## own determinism argument.
##
## Milestone 1 step 1 has no rendering at all, so this currently drives an empty
## Simulation and draws nothing. The first-person controller, Build Gun, Survey
## View and HUD arrive in later tickets and attach here.
class_name Main
extends Node

## Fixed for now. Becomes a new-Run / load-Run choice once saves exist.
const WORLD_SEED: int = 1
const PLAYER_COUNT: int = 1

var _simulation: Simulation = null
var _tick_pump: TickPump = null


func _init() -> void:
	_simulation = Simulation.new(WORLD_SEED, PLAYER_COUNT)
	_tick_pump = TickPump.new(Simulation.TICKS_PER_SECOND)


func _process(delta: float) -> void:
	advance_frame(delta)


## Runs however many whole ticks `delta_seconds` has earned.
##
## Separate from `_process` so it can be driven directly, without a frame loop or
## a node tree — which is how the smoke test exercises it. Returns the number of
## ticks run.
func advance_frame(delta_seconds: float) -> int:
	var ticks: int = _tick_pump.advance(delta_seconds)
	for i: int in range(ticks):
		# Input is sampled per tick rather than per frame, so one Input Action
		# script corresponds exactly to one sequence of ticks. Sampling per frame
		# would make the recorded script depend on frame rate, and a replay on a
		# different machine would then drift.
		_simulation.step(collect_input_actions())
	return ticks


## Translates the current device state into Input Actions for one tick.
##
## Deliberately raw key polling for now: the input map, mouse look, Build Gun and
## the rest belong to the first-person controller ticket. What matters at this
## stage is that the only channel from a device into the Simulation is a list of
## Input Actions.
func collect_input_actions() -> Array:
	var intent_x: int = 0
	var intent_z: int = 0

	if Input.is_key_pressed(KEY_D):
		intent_x += Fixed.ONE
	if Input.is_key_pressed(KEY_A):
		intent_x -= Fixed.ONE
	if Input.is_key_pressed(KEY_S):
		intent_z += Fixed.ONE
	if Input.is_key_pressed(KEY_W):
		intent_z -= Fixed.ONE

	if intent_x == 0 and intent_z == 0:
		return []

	return [InputAction.move(0, intent_x, intent_z)]


## Read-only access for the rendering layer. Callers may only use `query_*` and
## `hash` on what comes back.
func simulation() -> Simulation:
	return _simulation
