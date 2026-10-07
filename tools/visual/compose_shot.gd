## Composes a screenshot of a *working* Factory and writes it to a PNG.
##
##   bash tools/visual/shot.sh out.png [eye|survey|ground]
##
## A tool, not part of the game. It exists because the only honest way to judge
## the look of the world is to look at it: render, read the image, change
## something, render again. Several defects in earlier art tickets were visible
## only in a render.
##
## It drives the real `Simulation` with real Input Actions — a Miner on a Node, a
## Belt run to a Smelter, a Boiler, a Turret — then lets the real `WorldView` draw
## it. The only thing it does that the game does not is move the camera: the
## Simulation's camera follows the player, and a composed shot wants a chosen
## vantage. Nothing else about the frame is special-cased.
extends SceneTree

const FRAMES_TO_SETTLE: int = 40


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = "shot.png" if arguments.size() < 1 else arguments[0]
	var preset: String = "eye" if arguments.size() < 2 else arguments[1]

	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	root.add_child(view)

	_build_a_factory(sim)
	for tick: int in range(600):
		sim.step([])
	view.sync(sim)

	var camera: Camera3D = _camera_of(view)
	_frame(camera, sim, preset)
	# The HUD covers a third of the frame and the first-person placeholder covers a
	# corner of it. Both are real and both are somebody else's ticket; neither tells
	# us anything about how the world looks, so a composition shot does without them.
	if not arguments.has("hud"):
		_hide_the_overlay(view)

	# Let the renderer settle: the sky, the reflections, SSAO and the shadow
	# cascades all take a frame or two, and a shot taken on frame one is a shot of
	# a half-built frame rather than of the look being judged.
	for frame: int in range(FRAMES_TO_SETTLE):
		await process_frame
		view.sync(sim)
		_frame(camera, sim, preset)
		if not arguments.has("hud"):
			_hide_the_overlay(view)

	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	quit()


## A small but complete Factory: ore out of the ground, along a Belt, into a
## Smelter, with a Boiler feeding the grid and a Turret facing the Breach.
func _build_a_factory(sim: Simulation) -> void:
	var definitions: Definitions = sim.query_definitions()
	var node_tile: Vector3i = sim.query_node_tile(0)
	var miner: int = definitions.machine_index("miner_mk1")
	var smelter: int = definitions.machine_index("smelter_mk1")
	var boiler: int = definitions.machine_index("steam_boiler_mk1")
	var turret: int = definitions.machine_index("mg_turret_mk1")

	sim.step([InputAction.build_machine(0, miner, node_tile)])
	var smelter_tile: Vector3i = node_tile + Vector3i(6, 0, 0)
	sim.step([InputAction.build_machine(0, smelter, smelter_tile)])
	sim.step([
		InputAction.build_belt(
			0, node_tile + Vector3i(2, 0, 0), smelter_tile - Vector3i(1, 0, 0)
		)
	])
	sim.step([InputAction.build_machine(0, boiler, node_tile + Vector3i(0, 0, 5))])
	sim.step([InputAction.build_machine(0, turret, node_tile + Vector3i(6, 0, 5))])
	for which: int in range(4):
		sim.step([InputAction.build_wall(0, node_tile + Vector3i(-2, 0, which - 1))])


## Where to stand. `eye` is a three-quarter view at head height, which is how a
## player meets their own Factory; `survey` looks down on it the way Survey View
## does; `ground` lies low enough to judge whether props sit on the surface.
func _frame(camera: Camera3D, sim: Simulation, preset: String) -> void:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	var node_tile: Vector3i = sim.query_node_tile(0)
	var centre: Vector3 = Vector3(
		(float(node_tile.x) + 2.0) * tile_size, 0.0, (float(node_tile.z) + 2.0) * tile_size
	)
	var from: Vector3 = centre + Vector3(-16.0, 7.0, 18.0)
	var at: Vector3 = centre + Vector3(0.0, 1.5, 0.0)
	if preset == "survey":
		from = centre + Vector3(-4.0, 40.0, 26.0)
	elif preset == "ground":
		from = centre + Vector3(-9.0, 1.7, 13.0)
	camera.fov = 70.0
	camera.look_at_from_position(from, at, Vector3.UP)


func _hide_the_overlay(view: WorldView) -> void:
	for child: Node in view.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	var weapon: WeaponViewmodel = view.weapon_viewmodel()
	if weapon != null:
		weapon.visible = false


func _camera_of(view: WorldView) -> Camera3D:
	for child: Node in view.get_children():
		if child is Camera3D:
			return child
	push_error("the view drew no camera")
	return null
