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
## What it drives: a Run on the starter Map with an **empty Factory**, a
## `PlayerController` turning a mouse and four keys into Input Actions, and a `WorldView`
## drawing what the queries report — including the camera, which goes where the Simulation
## says a player's camera is rather than anywhere this layer decides.
##
## The Run is currently **unwinnable on purpose**: the Nest, the Breach and the Crawlers
## exist and nothing shoots back, because Turrets are the next ticket. The HUD says so when
## the Nest falls, and names the Wave the Run reached.
##
## The opening Miner, Belt, Smelter, Coal Miner and Steam Boiler this file used to place
## are gone. They existed so
## that #4 and #5 had something to look at while nothing could build; now a player builds
## it themselves in about ten seconds, which is the ticket. Keeping them as a starting
## Factory was the alternative and was rejected for two reasons: a Factory the player did
## not place teaches them nothing about the Build Gun, and it would have to be paid for
## out of somebody's materials or be a quiet exception to the costs every other build
## obeys. The one Power grid #7 added is unaffected: `power.baseline_supply_kw` is what
## carries a Factory until its first generator, and that is tuning rather than a Factory
## somebody else built.
class_name Main
extends Node

## Fixed for now. Becomes a new-Run / load-Run choice once saves exist.
const WORLD_SEED: int = 1
const PLAYER_COUNT: int = 1

## Which player this instance is driving. One for now; co-op makes it the local id.
const LOCAL_PLAYER: int = 0

var _simulation: Simulation = null
var _controller: PlayerController = null
var _tick_pump: TickPump = null
var _definition_watcher: DefinitionWatcher = null
var _world_view: WorldView = null

## A definition set the watcher produced that has not been handed to the Simulation
## yet, because definitions change on a tick like all other state and a frame does
## not always earn one.
var _pending_definitions: Definitions = null


func _init() -> void:
	_simulation = Simulation.new(WORLD_SEED, PLAYER_COUNT)
	_tick_pump = TickPump.new(Simulation.TICKS_PER_SECOND)
	_controller = PlayerController.new()
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

	_capture_the_mouse()


## Hands every device event to the controller, which adds it to the readings the next
## tick will be built from. Mouse travel and clicks arrive between frames, so a tick has
## to gather up whatever fell inside it; nothing here interprets an event.
func _input(event: InputEvent) -> void:
	# Mouse travel counts only while the pointer is captured. Otherwise moving the cursor
	# across a windowed game — or the warp the engine performs at the moment of capture —
	# would arrive as a violent turn the player did not ask for.
	var is_motion: bool = event is InputEventMouseMotion
	var captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if _controller != null and (captured or not is_motion):
		_controller.note_event(event)

	# Escape gives the pointer back, because a captured mouse with no way out is a bad
	# way to meet a game. Not a player action and not an Input Action: it is a window
	# management concern and the Simulation has no opinion about it.
	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_capture_the_mouse()


## Captures the pointer so mouse travel becomes look rather than a cursor. Skipped
## headless, where there is no window to capture it in.
func _capture_the_mouse() -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
## The whole channel from a device into the Simulation, and it is a list of Input Actions
## and nothing else. `PlayerController` does the translating; this orders a hot-reload
## ahead of it and hands the rest over.
func collect_input_actions() -> Array:
	var actions: Array = []

	# Ordered first, so the tick that reloads already runs on the new definitions.
	# Taken rather than copied, so one saved edit produces exactly one reload.
	if _pending_definitions != null:
		actions.append(InputAction.reload_definitions(LOCAL_PLAYER, _pending_definitions))
		_pending_definitions = null

	actions.append_array(
		_controller.actions_for_tick(_simulation, LOCAL_PLAYER, _controller.sample_devices())
	)
	return actions


## The controller, so a test can feed it a device sample by hand rather than pressing
## keys that headless will never report.
func controller() -> PlayerController:
	return _controller


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
