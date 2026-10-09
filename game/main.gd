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

## The seed a *new* Run starts on. A resumed Run carries its own, out of the save.
## Becomes a menu choice once there is a menu.
const WORLD_SEED: int = 1
const PLAYER_COUNT: int = 1

## Which player this instance is driving. One for now; co-op makes it the local id.
const LOCAL_PLAYER: int = 0

var _simulation: Simulation = null
var _controller: PlayerController = null
var _tick_pump: TickPump = null
var _definition_watcher: DefinitionWatcher = null
var _world_view: WorldView = null
var _audio: AudioDirector = null

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

	# A sibling of the view rather than a child of it, because the two read the same
	# queries and neither is upstream of the other — and in world space, which is
	# where `WorldView` puts the camera that acts as the listener. Like the view, it
	# is created here rather than in `_init` because it is a node and wants a tree,
	# and like the view, nothing about the Simulation depends on it existing: run
	# headless and the same ticks happen, unheard.
	_audio = AudioDirector.new()
	_audio.name = "AudioDirector"
	add_child(_audio)

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
	#
	# **But it holsters the Build Gun first.** A playtest asked for escape to leave build
	# mode, and that is the reading every game trains a player into: back out of the thing
	# you are doing, and only once there is nothing to back out of, leave the game. So the
	# pointer is released only when the Build Gun is already away — one press out of build
	# mode, a second out of the window. The holster half is a player action and travels as
	# an Input Action from `PlayerController`; this half reads the same mode so the two
	# cannot both fire on one press.
	if event is InputEventKey and (event as InputEventKey).pressed:
		var key: InputEventKey = event
		if key.keycode == KEY_ESCAPE:
			if not _simulation.query_player_is_in_build_mode(0):
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# Saving and resuming sit here with Escape rather than in `PlayerController`,
		# because neither is an Input Action. Saving is a pure read of the Simulation and
		# leaves its hash alone; loading *replaces* the Simulation, which is something no
		# method on it could do and nothing a replay could reproduce. The reasoning is
		# written out in full above `PlayerController.KEY_SAVE`.
		elif key.keycode == PlayerController.KEY_SAVE and not key.echo:
			save_run()
		elif key.keycode == PlayerController.KEY_LOAD and not key.echo:
			load_run()
		# How much of the HUD is on screen, here for the reason saving is here: it does
		# nothing to the Run, it leaves the hash where it was, and a replay has nothing to
		# reproduce. The brief is the default and this is the rest of the wall.
		elif key.keycode == PlayerController.KEY_HUD_DETAIL and not key.echo:
			if _world_view != null:
				_world_view.set_hud_detailed(not _world_view.hud_is_detailed())
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
		# The drag in flight, handed from the input producer to the renderer so the preview
		# is the route that would cross. Neither may reach for the other, and this is the one
		# place both are in scope. It is a device reading on its way in, like the mouse
		# buffer it sits next to — the Simulation is still the only thing that knows a Belt
		# was laid.
		if _controller != null and _simulation != null:
			_world_view.note_belt_drag(
				_controller.is_dragging_a_belt(),
				_controller.belt_drag_anchor(),
				_controller.belt_corner_axis(_simulation, LOCAL_PLAYER)
			)
		_world_view.sync(_simulation)
	# After the view, so a cue about a Machine that has just appeared is played in
	# the same frame the Machine is drawn in rather than the frame before it.
	if _audio != null:
		_audio.sync(_simulation)


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


# ── Saving and resuming a Run ─────────────────────────────────────────────────
# Both are driven by a key in `_input` and both are callable directly, because headless
# never reports a key press and this is behaviour worth asserting.

## Writes the Run to `path`. Returns an empty string on success, or the reason it failed.
##
## A read of the Simulation and nothing more: no step, no Input Action, and the hash
## where it was. A Run saved mid-flight carries on along exactly the ticks it would have
## followed unsaved.
func save_run(path: String = RunSave.DEFAULT_PATH) -> String:
	var failure: String = RunSave.write_to_file(_simulation, path)
	if failure != "":
		push_error("could not save the Run: %s" % failure)
	return failure


## Resumes the Run in `path`, replacing the Simulation. Returns an empty string on
## success, or the reasons it refused.
##
## A refusal leaves the Run that is running completely untouched — the same rule a failed
## hot-reload obeys, and for the same reason: a bad file must never take a Factory down.
## Nothing reconstructs the renderer, because there is nothing to reconstruct: `WorldView`
## rebuilds every frame from `query_*` and holds no state of its own, so the Factory on
## screen is whatever the Simulation says the moment after the swap.
func load_run(path: String = RunSave.DEFAULT_PATH) -> String:
	var loaded: RunSave.Load = RunSave.read_from_file(path)
	if loaded.has_errors():
		push_error("could not resume the Run: %s" % loaded.describe_errors())
		return loaded.describe_errors()

	_simulation = loaded.simulation
	# A queued hot-reload belonged to the Run that has just been replaced. The resumed
	# Run already loaded against the content on disk — that is what its digest check
	# proved — so there is nothing left to apply.
	_pending_definitions = null
	return ""


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


## The sound, once the tree has built it. Null without a tree, for the reason the
## view is.
func audio_director() -> AudioDirector:
	return _audio


## Read-only access for the rendering layer. Callers may only use `query_*` and
## `hash` on what comes back.
func simulation() -> Simulation:
	return _simulation
