## Composes a screenshot of **the marks a Machine wears**, and writes it to a PNG.
##
##   SHOT_SCRIPT=tools/visual/compose_mark_shot.gd tools/visual/shot.sh out.png [bare]
##
## A tool, not part of the game, and a fourth sibling of `compose_shot.gd`,
## `compose_building_shot.gd` and `compose_branch_shot.gd`. It answers the one question #50
## is about: **where should a tag hang on a Machine whose art rises well above the housing
## the Simulation collides against?**
##
## The subject is three starved Machines in a row, chosen so that the two numbers disagree by
## very different amounts: a Miner's derrick reaches about 8.2 m over a declared 1.8, a
## Smelter's flue about 7.8 over 1.5, and an MG Turret is 2.0 m of body over 2.0 m of housing
## — exactly its declaration, which is why a Turret could never have caught this. The Turret
## is dry as well as starved, so the Ammunition gauge is in frame beside the amber tag and the
## two can be seen stacking or not.
##
## The camera is placed, like `compose_shot.gd`'s, because what is being judged is a vertical
## relationship over ten metres and neither a player's eye nor Survey View can be asked for
## that vantage. The HUD is left off: the subject is the world.
extends SceneTree

const FRAMES_TO_SETTLE: int = 30

## Long enough that nothing in frame is mid-anything. Every Machine here is starved by
## construction — a Miner on bare rock, a Smelter and a Turret with no Belt — so there is
## nothing to wait for except the "a Machine does not run on the tick it was built" rule.
const TICKS_TO_RUN: int = 120

## Where the row stands. Open ground on the starter Map, clear of the Nest and of every Node,
## so the Miner is on bare rock and visibly idle rather than quietly working.
const ROW_TILE: Vector3i = Vector3i(14, 0, 14)


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = "shot.png" if arguments.size() < 1 else arguments[0]
	# `bare` hides the yard, for the reason `compose_branch_shot.gd` has it: a four-metre prop
	# standing in front of a tag and a tag that was never drawn look identical in a picture.
	var bare: bool = arguments.has("bare")

	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	root.add_child(view)

	_build_the_row(sim)
	for tick: int in range(TICKS_TO_RUN):
		sim.step([])

	view.sync(sim)
	var camera: Camera3D = _camera_of(view)
	for frame: int in range(FRAMES_TO_SETTLE):
		await process_frame
		view.sync(sim)
		_frame(camera, sim)
		if bare:
			_hide_the_yard(view)

	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(out_path)
	print(
		"wrote %s (%dx%d) — %d starved, %d gauge"
		% [
			out_path,
			image.get_width(),
			image.get_height(),
			view.starved_marker_count(),
			view.turret_gauge_count(),
		]
	)
	for index: int in range(sim.query_machine_count()):
		print(
			"  %s: housing %.2f, drawn %.2f"
			% [
				sim.query_machine_id(index),
				Fixed.to_float(sim.query_machine_height_metres(index)),
				view.machine_drawn_roof_metres(sim, index),
			]
		)
	for which: int in range(view.starved_marker_count()):
		print("  starved tag at ", view.starved_marker_position(which))
	for slot: int in range(view.turret_gauge_count()):
		print("  gauge at ", view.turret_gauge_position(slot))
	quit()


## Three starved Machines in a row, spaced so no body hides its neighbour's tag.
##
## Nothing is belted and nothing stands on a Node, so all three are starved from the tick
## after they were built: the Miner is over bare rock, the Smelter holds no ore and the Turret
## holds no round. The Turret is the one that also wears a gauge.
func _build_the_row(sim: Simulation) -> void:
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), ROW_TILE),
		InputAction.build_machine(
			0, definitions.machine_index("smelter_mk1"), ROW_TILE + Vector3i(5, 0, 0)
		),
		InputAction.build_machine(
			0, definitions.machine_index("mg_turret_mk1"), ROW_TILE + Vector3i(10, 0, 0)
		),
	])


## Where to stand: south-east of the row and low enough that ten metres of height is ten
## metres of frame rather than a thin band at the top of it.
func _frame(camera: Camera3D, sim: Simulation) -> void:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	var centre: Vector3 = Vector3(
		(float(ROW_TILE.x) + 6.0) * tile_size, 0.0, (float(ROW_TILE.z) + 1.0) * tile_size
	)
	camera.fov = 60.0
	camera.look_at_from_position(
		centre + Vector3(0.0, 5.5, 23.0), centre + Vector3(0.0, 4.6, 0.0), Vector3.UP
	)


func _hide_the_yard(view: WorldView) -> void:
	for child: Node in view.get_children():
		if child is SetDressing:
			(child as SetDressing).visible = false


func _camera_of(view: WorldView) -> Camera3D:
	for child: Node in view.get_children():
		if child is Camera3D:
			return child
	push_error("the view drew no camera")
	return null
