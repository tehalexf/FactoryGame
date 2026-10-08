## Composes a screenshot of the **act of building** and writes it to a PNG.
##
##   bash tools/visual/shot.sh out.png placing    SHOT_SCRIPT=tools/visual/compose_building_shot.gd
##
## A tool, not part of the game, and a sibling of `compose_shot.gd` rather than a
## replacement for it: that one frames the Factory from a chosen vantage to judge how the
## world looks, and this one frames it **through the player's own eyes** to judge what a
## player is told while they work. Those are different questions and the second one needs
## the real camera, because everything under test here — the hologram, the port arrows, the
## previewed route — is drawn from where the Build Gun is pointing.
##
## Three presets, which are the three things #36 asked for a picture of:
##
##   placing   a Machine on the Build Gun, its ports arrowed, over a clear tile
##   routing   a Belt drag in flight, cornering, with a refused tile in it
##   running   a fed line, flowing, with the Machines reading as fed
##
## The HUD is **left on**, unlike the composition shots: here it is half the subject.
extends SceneTree

const FRAMES_TO_SETTLE: int = 30

## Where the opening line goes. The starter Map's first iron Node by tile order, picked out
## of the Simulation rather than written down, so a Map change moves the shot rather than
## breaking it.
var _node_tile: Vector3i = Vector3i.ZERO

## Whether every tick this tool steps is a tick with Survey View held.
##
## **The shot is taken from Survey View for the two building presets**, and that is a
## finding rather than a convenience: at eye level a 1.7 m player among 1.5 m to 2.4 m
## Machines sees a wall of Machine, and a previewed route on the ground behind one is a
## route nobody can see. Survey View exists because a Factory is illegible at eye level
## (CLAUDE.md), and laying out a line is exactly the moment that bites. It is **held**, so
## every step while it is up has to carry the intent or the camera starts coming down.
var _surveying: bool = false


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = "shot.png" if arguments.size() < 1 else arguments[0]
	var preset: String = "routing" if arguments.size() < 2 else arguments[1]

	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	root.add_child(view)

	_node_tile = sim.query_node_tile(_first_iron_node(sim))
	_build_the_opening_line(sim, preset)
	# Long enough that ore is on the Belt and the Smelter has crafted, which is what makes
	# the "running" shot a shot of a Factory rather than of a diagram.
	for tick: int in range(240):
		sim.step([])

	_stand_the_player_where_the_work_is(sim, preset)
	var drag: Array = _set_up_the_shot(sim, view, preset)

	for frame: int in range(FRAMES_TO_SETTLE):
		await process_frame
		view.note_belt_drag(drag[0], drag[1], drag[2])
		view.sync(sim)

	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s (%dx%d) — %s" % [out_path, image.get_width(), image.get_height(), preset])
	quit()


## The first Depth 1 iron Node, by the index order the Simulation sorted them into.
func _first_iron_node(sim: Simulation) -> int:
	for index: int in range(sim.query_node_count()):
		if sim.query_node_resource(index) == "iron_ore" and sim.query_node_depth(index) == 1:
			return index
	return 0


## A Miner on the Node and a Smelter across from it, and for the running shot the Belt
## between them and a Boiler to keep the grid up.
func _build_the_opening_line(sim: Simulation, preset: String) -> void:
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), _node_tile)
	])
	sim.step([
		InputAction.build_machine(
			0, definitions.machine_index("smelter_mk1"), _smelter_tile(), 0
		)
	])
	if preset != "running":
		return

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


## Walks the player until the Build Gun's crosshair is on what the shot is about.
##
## **A closed loop over the real aim rather than a camera placed by hand**, because in
## Survey View the two are not interchangeable: the camera pitch at full lift is the
## tuned `survey.pitch_degrees` and nothing a `LOOK` does can change it, so from 26 m up
## the Build Gun lands a fixed distance ahead of the player and the only way to aim it
## somewhere is to **stand somewhere else**. That is a fact about the game worth a tool
## discovering rather than a tool working around: it is what a player does too.
func _stand_the_player_where_the_work_is(sim: Simulation, preset: String) -> void:
	var target: Vector3 = _what_the_shot_is_about(sim, preset)
	# The running shot is the one a player meets at eye level — a line going past you is
	# the picture — and the two building shots are the ones Survey View exists for: at
	# 1.7 m among 1.5 m to 2.4 m Machines you are looking at a wall of Machine, and a
	# previewed route on the ground behind one is a route nobody can see.
	if preset != "running":
		_lift_into_survey(sim)
	_put_the_crosshair_on(sim, target, preset == "running")


## Turns to face a point and then walks towards or away from it until the Build Gun's
## crosshair is on it. Bounded, because a tool that hangs is worse than a tool that renders
## the wrong frame.
##
## The approach is from the open ground to the north-west, because the Factory is solid to a
## player (#30) and a loop that walked straight at a Smelter would spend its whole budget
## leaning on one.
func _put_the_crosshair_on(sim: Simulation, target: Vector3, stop_short: bool) -> void:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	var wanted: Vector3i = Vector3i(
		floori(target.x / tile_size), WorldGrid.GROUND_LAYER, floori(target.z / tile_size)
	)
	var approach: Vector2 = Vector2(-0.8, -1.0).normalized()
	for attempt: int in range(3):
		_aim_at(sim, target)
		if BuildGun.aimed_tile(sim, 0) == wanted:
			break
		# How far ahead of the player the aim is landing right now. In Survey View that is
		# fixed by the tuned tilt and nothing a `LOOK` does can change it, so the only way to
		# aim somewhere is to stand somewhere else — which is what a player does too.
		var here: Vector2 = _player_ground(sim)
		var aim_centre: Vector2 = Vector2(
			(float(BuildGun.aimed_tile(sim, 0).x) + 0.5) * tile_size,
			(float(BuildGun.aimed_tile(sim, 0).z) + 0.5) * tile_size
		)
		var lead: float = (aim_centre - here).length()
		if stop_short:
			lead = maxf(lead, 8.0)
		_walk_to(sim, Vector2(target.x, target.z) - approach * lead)
	_aim_at(sim, target)
	for tick: int in range(20):
		_step(sim, [])
	_aim_at(sim, target)


## Walks a player to within a metre of a point on the ground, facing where they are going.
func _walk_to(sim: Simulation, target: Vector2) -> void:
	for tick: int in range(140):
		var gap: Vector2 = target - _player_ground(sim)
		if gap.length() < 1.0:
			return
		_aim_at(sim, Vector3(target.x, 1.6, target.y))
		_step(sim, [InputAction.move(0, Fixed.ONE, 0)])


func _player_ground(sim: Simulation) -> Vector2:
	var here: FixedVec2 = sim.query_player_position(0)
	return Vector2(Fixed.to_float(here.x), Fixed.to_float(here.z))


## What the player should be looking at, per preset.
func _what_the_shot_is_about(sim: Simulation, preset: String) -> Vector3:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	if preset == "running":
		# The Smelter at the far end of the line, at head height, so the Belt runs away
		# from the camera and the Items on it are what the eye follows.
		return Vector3(
			(float(_smelter_tile().x) + 1.5) * tile_size,
			1.6,
			(float(_smelter_tile().z) + 0.5) * tile_size
		)
	if preset == "placing":
		# Clear ground beside the line, which is where a Machine actually gets placed.
		return Vector3(
			(float(_node_tile.x) + 4.5) * tile_size, 0.0, (float(_node_tile.z) + 3.5) * tile_size
		)
	# Routing: the far end of the run between the Miner and the Smelter, so the route being
	# previewed is most of the gap.
	return Vector3(
		(float(_node_tile.x) + 1.5) * tile_size, 0.0, (float(_node_tile.z) + 5.5) * tile_size
	)


## One tick, with Survey View carried along if it is up. Every step this tool takes goes
## through here, because a tick that forgot the intent is a tick the camera spent descending.
func _step(sim: Simulation, actions: Array) -> void:
	var carried: Array = actions.duplicate()
	carried.append(InputAction.survey_view(0, _surveying))
	sim.step(carried)


## Lifts into Survey View and waits out the transition, which the Simulation counts in ticks.
func _lift_into_survey(sim: Simulation) -> void:
	_surveying = true
	for tick: int in range(90):
		_step(sim, [])


## Turns a player until they are looking at a point in the world.
##
## The yaw and pitch wanted come straight out of `InputQuantiser.forward_vector`'s own
## convention — at yaw 0 forward is -z and a positive yaw turns left — and the pixel count
## that gets there comes out of the sensitivity the Simulation is holding. A couple of
## iterations because one `LOOK` is capped at `InputAction.MAX_LOOK_PIXELS`.
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
		# Right is a decrease in yaw and down is a decrease in pitch, so both signs flip.
		_step(sim, [
			InputAction.look(
				0,
				InputQuantiser.pixels_to_fixed(-yaw_gap / sensitivity * 1000.0),
				InputQuantiser.pixels_to_fixed(-pitch_gap / sensitivity * 1000.0)
			)
		])


## A turn difference brought into [-0.5, 0.5], so aiming never takes the long way round.
func _shortest_turn(turns: float) -> float:
	var wrapped: float = fposmod(turns, 1.0)
	return wrapped - 1.0 if wrapped > 0.5 else wrapped


## Puts the Build Gun in the state the preset is a picture of, and returns the drag the
## renderer should be told about: [active, anchor, corner axis].
func _set_up_the_shot(sim: Simulation, view: WorldView, preset: String) -> Array:
	var definitions: Definitions = sim.query_definitions()
	if preset == "placing":
		_step(sim, [
			InputAction.select_machine(0, definitions.machine_index("smelter_mk1")),
			InputAction.rotate_build(0, 1),
		])
		return [false, Vector3i.ZERO, BeltRoute.ALONG_X]

	if preset == "running":
		return [false, Vector3i.ZERO, BeltRoute.ALONG_X]

	# Routing: the Belt tool out and a drag anchored back at the Miner's output, so the
	# previewed route is a real L.
	_step(sim, [InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	var anchor: Vector3i = _node_tile + Vector3i(1, 0, 2)
	# Something squarely in the way, on a tile of the route as it actually came out, so the
	# shot shows a refusal marked **on the preview** rather than only a clear one. Worked out
	# from `BeltRoute` rather than guessed, because the aim lands where the aim lands.
	var tiles: Array[Vector3i] = BeltRoute.tiles(
		anchor, BuildGun.aimed_tile(sim, 0), BeltRoute.ALONG_Z
	)
	if tiles.size() > 3:
		_step(sim, [InputAction.build_wall(0, tiles[tiles.size() - 3])])
	view.sync(sim)
	return [true, anchor, BeltRoute.ALONG_Z]
