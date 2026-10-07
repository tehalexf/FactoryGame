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
## What it drives today: a Run on the starter Map, one opening Miner placed by an
## ordinary build Input Action, and `WorldView` drawing placeholders and the extracted
## count. The first-person controller, Build Gun and Survey View arrive in later
## tickets and replace the fixed camera and the opening Miner with player intent.
class_name Main
extends Node

## Fixed for now. Becomes a new-Run / load-Run choice once saves exist.
const WORLD_SEED: int = 1
const PLAYER_COUNT: int = 1

## The line a Run opens with: a Miner on the first Node, a Belt out of its output port,
## and a Smelter at the far end of the Belt. Enough to watch ore travel and become
## plates. All of it goes away when the Build Gun arrives.
##
## The Belt starts on the tile just past the Miner's footprint and the Smelter is anchored
## on the tile just past the Belt's far end, because that adjacency *is* the connection —
## Belts run straight into Machine ports and no inserter entity exists (DESIGN.md).
const STARTING_MINER: String = "miner_mk1"
const STARTING_SMELTER: String = "smelter_mk1"
const STARTING_BELT_TILES: int = 4

var _simulation: Simulation = null
var _tick_pump: TickPump = null
var _definition_watcher: DefinitionWatcher = null
var _world_view: WorldView = null

## Whether the opening Miner still has to be built.
##
## Temporary, and only here so this ticket has something to look at: the Build Gun
## ticket is what turns placement into a player intent. Note what it is *not* — a
## special path into the Simulation. It is an ordinary `BUILD_MACHINE` Input Action
## on the first tick, so it records, replays and hashes like a player's own build.
var _starting_miner_pending: bool = true

## A definition set the watcher produced that has not been handed to the Simulation
## yet, because definitions change on a tick like all other state and a frame does
## not always earn one.
var _pending_definitions: Definitions = null


func _init() -> void:
	_simulation = Simulation.new(WORLD_SEED, PLAYER_COUNT)
	_tick_pump = TickPump.new(Simulation.TICKS_PER_SECOND)
	_definition_watcher = DefinitionWatcher.new()

	if not _simulation.query_definitions_loaded():
		# Loud and early. A Run on a definition set that failed to load is a Run with
		# no Machines and no Recipes, and discovering that by watching nothing happen
		# is strictly worse than being told.
		push_error(
			"refusing to start a Run: the content definitions did not load:\n%s"
			% "\n".join(_simulation.query_definition_errors())
		)


func _ready() -> void:
	# The view is created here rather than in `_init` because it is a node and wants a
	# tree. Nothing about the Simulation depends on it existing: run headless and the
	# same ticks happen, unobserved.
	_world_view = WorldView.new()
	_world_view.name = "WorldView"
	add_child(_world_view)


func _process(delta: float) -> void:
	advance_frame(delta)
	if _world_view != null:
		_world_view.sync(_simulation)


## Runs however many whole ticks `delta_seconds` has earned.
##
## Separate from `_process` so it can be driven directly, without a frame loop or
## a node tree — which is how the smoke test exercises it. Returns the number of
## ticks run.
func advance_frame(delta_seconds: float) -> int:
	# Hot-reload: if a content file was saved, the watcher hands back a loaded, valid
	# definition set, and it is queued as an Input Action for the next tick. A
	# malformed file yields null and the Run carries on with what it has.
	var reloaded: Definitions = _definition_watcher.poll(delta_seconds)
	if reloaded != null:
		_pending_definitions = reloaded

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
	var actions: Array = []

	# Ordered first, so the tick that reloads already runs on the new definitions.
	# Taken rather than copied, so one saved edit produces exactly one reload.
	if _pending_definitions != null:
		actions.append(InputAction.reload_definitions(0, _pending_definitions))
		_pending_definitions = null

	# The opening line, on the Map's first Node. Once only — a flag rather than a
	# check against the Simulation, because the Godot layer does not get to decide
	# anything from state it has read back.
	if _starting_miner_pending:
		_starting_miner_pending = false
		actions.append_array(_opening_line_actions())

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

	if intent_x != 0 or intent_z != 0:
		actions.append(InputAction.move(0, intent_x, intent_z))

	return actions


## The Input Actions that lay the opening line, in the order they have to happen in.
##
## Ordinary build intents, on the first tick, exactly as a player's own would be — so the
## opening line records, replays and hashes like anything else, and this method is the
## only thing the Build Gun ticket has to delete.
##
## The geometry comes out of the queries: the Miner's footprint from
## `content/machines.csv` by way of the Simulation, the Node from the Map. Nothing here
## has its own copy of either.
func _opening_line_actions() -> Array:
	var definitions: Definitions = _simulation.query_definitions()
	var miner: int = definitions.machine_index(STARTING_MINER)
	var smelter: int = definitions.machine_index(STARTING_SMELTER)
	if miner == -1 or smelter == -1 or _simulation.query_node_count() == 0:
		return []

	var footprint: MachineDefinition = definitions.machine(STARTING_MINER)
	var anchor: Vector3i = _simulation.query_node_tile(0)
	var belt_entry: Vector3i = Vector3i(anchor.x + footprint.footprint_x, anchor.y, anchor.z)
	var belt_exit: Vector3i = Vector3i(
		belt_entry.x + STARTING_BELT_TILES - 1, belt_entry.y, belt_entry.z
	)

	return [
		InputAction.build_machine(0, miner, anchor),
		InputAction.build_belt(0, belt_entry, belt_exit),
		InputAction.build_machine(0, smelter, Vector3i(belt_exit.x + 1, belt_exit.y, belt_exit.z)),
	]


## The watcher that notices a saved content file. Replaceable so a test can point it
## at a directory it owns rather than at the repository's own content.
func definition_watcher() -> DefinitionWatcher:
	return _definition_watcher


func set_definition_watcher(watcher: DefinitionWatcher) -> void:
	_definition_watcher = watcher


## The view, once the tree has built it. Null when running headless without a tree.
func world_view() -> WorldView:
	return _world_view


## Read-only access for the rendering layer. Callers may only use `query_*` and
## `hash` on what comes back.
func simulation() -> Simulation:
	return _simulation
