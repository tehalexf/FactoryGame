## Composes a screenshot of **a line that has just started working** and writes it to a PNG.
##
##   SHOT_SCRIPT=tools/visual/compose_line_shot.gd bash tools/visual/shot.sh out.png "eye bare"
##   SHOT_SCRIPT=tools/visual/compose_line_shot.gd bash tools/visual/shot.sh out.png "survey bare"
##   SHOT_SCRIPT=tools/visual/compose_line_shot.gd bash tools/visual/shot.sh out.png "eye before bare"
##
## A sibling of `compose_building_shot.gd` rather than a preset on it, and the reason is the
## one `compose_death_shot.gd` gives: **the subject is a change, so the tool has to be
## watching while it happens.** That composer builds its line, steps 240 ticks with nothing
## looking, and only then syncs the view — which is fine for a shot of a *condition* (ports
## arrowed, Machines fed) and cannot photograph a signal that fires on one frame and runs for
## five seconds. Everything here therefore steps the Simulation **with the view synced every
## tick**, because that is what the game does and what a change-detector needs.
##
## Two vantages, because #52 found that the two disagree: a vertical mark is a 0.6 m square
## seen end on from the lift, so a mark judged only at eye level can be invisible from the one
## mode this game has for reading a whole yard at a glance.
##
##   eye      standing beside the line, which is where a player is when they release the drag
##   survey   the same Factory from the lift, which is where they read it from
##
## And `before`, which is honest rather than reconstructed: it watches the line for longer
## than `WorldView.LINE_WORKS_TICKS` and shoots after the signal has subsided, so what comes
## out is a working line with nothing anywhere saying so — which is exactly what shipped.
##
## `bare` hides the yard, for the two reasons every composer carries it: a prop standing where
## a mark is makes "drawn and hidden" indistinguishable from "never drawn", and the set
## dressing is loaded from the **purchased** packs, so a shot bound for a public repository has
## to be able to leave them out.
##
## The HUD is left on, like the building shots: the `LINE RUNNING` line is half the subject.
extends SceneTree

const FRAMES_TO_SETTLE: int = 30

## How long the tool waits for the chain to read whole, in ticks.
##
## Bounded, because a tool that hangs is worse than a tool that renders the wrong frame. The
## shipped Smelter wants two ore at 90 ticks a lump plus the Belt's travel, so this is a wide
## margin over the ~400 it actually takes.
const TICKS_TO_WAIT_FOR_THE_LINE: int = 1200

## How far down the line the train of lights has run when the shutter opens.
##
## Measured in **tiles**, not ticks, so the framing does not move if
## `WorldView.LINE_WORKS_PULSE_TICKS_PER_TILE` is tuned. Six tiles puts the head most of the
## way along the opening line's own run, which is the picture the ticket asks for: lights
## travelling, not one light sitting at the Miner's port.
const TILES_INTO_THE_SWEEP: int = 6

var _node_tile: Vector3i = Vector3i.ZERO
var _surveying: bool = false


func _initialize() -> void:
	var given: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = "shot.png" if given.size() < 1 else given[0]
	var arguments: PackedStringArray = PackedStringArray()
	for word: String in " ".join(given.slice(1)).split(" ", false):
		arguments.append(word)
	var survey: bool = arguments.has("survey")
	var before: bool = arguments.has("before")
	var bare: bool = arguments.has("bare")

	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	root.add_child(view)

	_node_tile = sim.query_node_tile(_first_iron_node(sim))
	_build_the_opening_line(sim)
	# The walk happens **before** anything is watching, deliberately. The camera has to be
	# parked where the shot wants it by the time the signal fires, and a tool that walked
	# afterwards would spend the five seconds it has to photograph walking. Nothing is lost by
	# it: the signal is a function of the tick a chain was *first seen* whole, so starting to
	# look is starting the observation rather than altering the Run.
	_stand_the_player_where_the_work_is(sim, survey)

	var lit: int = _watch_until_the_line_works(sim, view)
	if lit == -1:
		push_error("the line never read whole within %d ticks" % TICKS_TO_WAIT_FOR_THE_LINE)
		quit(1)
		return

	var wait: int = (
		WorldView.LINE_WORKS_TICKS + 60
		if before
		else TILES_INTO_THE_SWEEP * WorldView.LINE_WORKS_PULSE_TICKS_PER_TILE
	)
	for tick: int in range(wait):
		_step(sim, [])
		view.sync(sim)

	for frame: int in range(FRAMES_TO_SETTLE):
		await process_frame
		view.sync(sim)
		if bare:
			_hide_the_yard(view)

	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(out_path)
	print(
		"wrote %s (%dx%d) — %s%s: whole on tick %d, %d lights, %d tags, hud %s"
		% [
			out_path,
			image.get_width(),
			image.get_height(),
			"survey" if survey else "eye",
			" before" if before else "",
			lit,
			view.line_works_pulse_count(),
			view.line_works_tag_count(),
			"\"LINE RUNNING\"" if view.hud_brief_text().contains("LINE RUNNING") else "quiet",
		]
	)
	quit()


## Steps with the view watching until a chain first reads whole, and returns that tick. -1 if
## it never did, which is a tool failure rather than a picture.
func _watch_until_the_line_works(sim: Simulation, view: WorldView) -> int:
	for tick: int in range(TICKS_TO_WAIT_FOR_THE_LINE):
		_step(sim, [])
		view.sync(sim)
		if view.line_works_tag_count() > 0:
			return sim.query_tick()
	return -1


func _hide_the_yard(view: WorldView) -> void:
	for child: Node in view.get_children():
		if child is SetDressing:
			(child as SetDressing).visible = false


func _first_iron_node(sim: Simulation) -> int:
	for index: int in range(sim.query_node_count()):
		if sim.query_node_resource(index) == "iron_ore" and sim.query_node_depth(index) == 1:
			return index
	return 0


## The opening line, exactly as `compose_building_shot.gd`'s `running` preset builds it: a
## Miner on the Node, a Smelter across from it, the Belt between them and a Boiler to keep the
## grid up. The same Factory on purpose — the two shots are of the same thing and only one of
## them was ever able to say it was working.
func _build_the_opening_line(sim: Simulation) -> void:
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), _node_tile)
	])
	sim.step([
		InputAction.build_machine(
			0, definitions.machine_index("smelter_mk1"), _smelter_tile(), 0
		)
	])
	sim.step([
		InputAction.build_belt_route(
			0,
			_node_tile + Vector3i(1, 0, 2),
			_smelter_tile() + Vector3i(1, 0, -1),
			BeltRoute.ALONG_Z
		)
	])
	sim.step([
		InputAction.build_machine(
			0, definitions.machine_index("steam_boiler_mk1"), _node_tile + Vector3i(-4, 0, 0)
		)
	])


func _smelter_tile() -> Vector3i:
	return _node_tile + Vector3i(0, 0, 6)


## Walks the player to where the shot is taken from and points them down the line.
##
## Deliberately **not** `compose_building_shot.gd`'s closed loop over the Build Gun's aim:
## that one needs the crosshair on a particular tile because the hologram is its subject,
## where here the subject is a run of Belt several tiles long and what matters is that the
## whole of it is in frame. So this stands off to the side and looks at the middle of the run.
func _stand_the_player_where_the_work_is(sim: Simulation, survey: bool) -> void:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	var middle: Vector3 = Vector3(
		(float(_node_tile.x) + 1.5) * tile_size,
		1.0,
		(float(_node_tile.z) + 4.5) * tile_size
	)
	if survey:
		# **Walk first, then lift, which a render decided.** Walking *while* surveying barely
		# moved the player at all: `_walk_to` steers by `_aim_at`, and from 26 m up the pitch
		# it is asking for is one the lift has pinned, so the aim never converges and the walk
		# spends its whole budget turning. The order is free — where a player stands and how
		# high they are looking from are independent — and this way the walk is an ordinary
		# one. The `_aim_at` afterwards is for the yaw alone, which is the only thing about a
		# Survey View camera a `LOOK` can still move.
		_walk_to(sim, Vector2(middle.x + 6.0, middle.z - 10.0))
		_lift_into_survey(sim)
		_aim_at(sim, middle)
		return
	# **South-east of the line and well back, which a render decided.** The first attempt
	# stood eleven metres due west of the run so the Belt would cross the frame, and three
	# things went wrong at once: the Boiler stands on that ground, so the walk slid along it
	# and finished somewhere else; the Miner's derrick filled the shot; and the Belt the
	# picture is about was not in it at all. That is the project's own note about eye level —
	# a 1.7 m player among 1.5 m Machines is looking at a wall of Machine — arriving in the
	# one shot that cannot answer it from the lift instead. A three-quarter view from
	# eighteen metres puts the whole eighteen-metre run on the diagonal with both Machines in
	# shot and nothing standing between the camera and the Belt.
	_walk_to(sim, Vector2(middle.x + 13.0, middle.z - 13.0))
	_aim_at(sim, middle)
	for tick: int in range(20):
		_step(sim, [])
	_aim_at(sim, middle)


func _walk_to(sim: Simulation, target: Vector2) -> void:
	for tick: int in range(240):
		var gap: Vector2 = target - _player_ground(sim)
		if gap.length() < 1.0:
			return
		_aim_at(sim, Vector3(target.x, 1.6, target.y))
		_step(sim, [InputAction.move(0, Fixed.ONE, 0)])


func _player_ground(sim: Simulation) -> Vector2:
	var here: FixedVec2 = sim.query_player_position(0)
	return Vector2(Fixed.to_float(here.x), Fixed.to_float(here.z))


## One tick, with Survey View carried along if it is up — a tick that forgot the intent is a
## tick the camera spent descending.
func _step(sim: Simulation, actions: Array) -> void:
	var carried: Array = actions.duplicate()
	carried.append(InputAction.survey_view(0, _surveying))
	sim.step(carried)


func _lift_into_survey(sim: Simulation) -> void:
	_surveying = true
	for tick: int in range(90):
		_step(sim, [])


func _aim_at(sim: Simulation, target: Vector3) -> void:
	var sensitivity: float = Fixed.to_float(sim.query_definitions().player_look_sensitivity)
	if is_zero_approx(sensitivity):
		return
	for attempt: int in range(8):
		var ground: FixedVec2 = sim.query_player_camera_ground_metres(0)
		var eye: Vector3 = Vector3(
			Fixed.to_float(ground.x),
			Fixed.to_float(sim.query_player_camera_height_metres(0)),
			Fixed.to_float(ground.z)
		)
		var want: Vector3 = (target - eye).normalized()
		var wanted_yaw: float = atan2(-want.x, -want.z) / TAU
		var wanted_pitch: float = asin(clampf(want.y, -1.0, 1.0)) / TAU
		var yaw_gap: float = _shortest_turn(
			wanted_yaw - Fixed.to_float(sim.query_player_yaw_turns(0))
		)
		var pitch_gap: float = (
			wanted_pitch - Fixed.to_float(sim.query_player_camera_pitch_turns(0))
		)
		if absf(yaw_gap) < 0.0005 and absf(pitch_gap) < 0.0005:
			return
		_step(sim, [
			InputAction.look(
				0,
				InputQuantiser.pixels_to_fixed(-yaw_gap / sensitivity * 1000.0),
				InputQuantiser.pixels_to_fixed(-pitch_gap / sensitivity * 1000.0)
			)
		])


func _shortest_turn(turns: float) -> float:
	var wrapped: float = fposmod(turns, 1.0)
	return wrapped - 1.0 if wrapped > 0.5 else wrapped
