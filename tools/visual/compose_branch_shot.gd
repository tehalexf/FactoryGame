## Composes a screenshot of **a line that branches** and writes it to a PNG.
##
##   SHOT_SCRIPT=tools/visual/compose_branch_shot.gd tools/visual/shot.sh out.png
##
## A tool, not part of the game, and a third sibling of `compose_shot.gd` and
## `compose_building_shot.gd`. Those two answer "how does the world look" and "what is a
## player told while they aim the Build Gun"; this one answers the question #48 is about —
## **can you tell, looking at it, which of two Belts off one Machine is blocked?**
##
## It needs its own composer for a reason worth writing down, because both of the others
## were tried first and both failed in the same way. The subject is a Machine and the two
## Belts either side of it, which is about twenty metres of Factory: at eye level you are
## nose-first into a conveyor and the far branch is behind it, and from Survey View at
## twenty-six metres the whole Factory is a sixth of the frame and every mark in it is three
## pixels wide under a wall of port arrows. The vantage this wants is in between and neither
## of those tools can be asked for it — `compose_building_shot.gd` is framed by *walking a
## player*, deliberately, because what it is judging is the aim.
##
## So the camera is placed, like `compose_shot.gd`'s. The **HUD is left on**, like
## `compose_building_shot.gd`'s, because the brief panel's branch line is half the subject.
extends SceneTree

const FRAMES_TO_SETTLE: int = 30

## Long enough that the Smelter has crafted several plates, both branches have carried one to
## their far end, and the blocked one has been refused there. A Smelter crafts every 3.2 s and
## a three-tile Belt is about three seconds of travel, so this is generous rather than tight.
const TICKS_TO_RUN: int = 2400


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = "shot.png" if arguments.size() < 1 else arguments[0]
	# `bare` hides the yard, for the reason `compose_wave_shot.gd` has one: judge the grade on
	# a dressed shot and the *geometry* on a bare one. It earned its place here immediately —
	# the first dressed render of this scene has a four-metre prop standing over the Smelter,
	# and whether the tag over that Smelter's roof was hidden behind it or was never drawn are
	# two very different bugs that look identical in a picture.
	var bare: bool = arguments.has("bare")

	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	root.add_child(view)

	var smelter_tile: Vector3i = _build_the_split(sim)
	for tick: int in range(TICKS_TO_RUN):
		sim.step([])

	view.sync(sim)
	var camera: Camera3D = _camera_of(view)
	for frame: int in range(FRAMES_TO_SETTLE):
		await process_frame
		view.sync(sim)
		_frame(camera, sim, smelter_tile)
		if bare:
			_hide_the_yard(view)

	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(out_path)
	print(
		"wrote %s (%dx%d) — %d split, %d banking, %d branch posts, %d blocked"
		% [
			out_path,
			image.get_width(),
			image.get_height(),
			view.split_marker_count(),
			view.banking_marker_count(),
			view.branch_marker_count(),
			view.blocked_branch_marker_count(),
		]
	)
	print("  split tag at ", view.split_marker_position(0))
	print("  branch post at ", view.branch_marker_position(0))
	quit()


## The subject: a Smelter fed by a Miner, with plate leaving by **both** of its declared
## output faces into two Machines of which only one wants plate.
##
## The Ammo Press takes plate on its northern face and goes on taking it; the Steam Boiler
## takes *coal* on its western one, so that branch is docked, pointing the right way, and will
## never hand over an Item. That is the mistake a real player makes — and before #48 the two
## Belts looked exactly alike from any angle, which is the whole of what this picture is for.
func _build_the_split(sim: Simulation) -> Vector3i:
	var definitions: Definitions = sim.query_definitions()
	var node_tile: Vector3i = sim.query_node_tile(_first_iron_node(sim))
	var smelter_tile: Vector3i = node_tile + Vector3i(0, 0, 6)

	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), node_tile),
		InputAction.build_machine(0, definitions.machine_index("smelter_mk1"), smelter_tile),
	])
	sim.step([
		InputAction.build_belt(
			0, node_tile + Vector3i(1, 0, 2), smelter_tile + Vector3i(1, 0, -1)
		),
		# A Boiler off to one side to keep the grid up, so nothing in frame is throttled for
		# a reason that has nothing to do with the split.
		InputAction.build_machine(
			0, definitions.machine_index("steam_boiler_mk1"), node_tile + Vector3i(-5, 0, 0)
		),
	])
	sim.step([
		# South off the Smelter into an Ammo Press, which wants plate. This branch runs.
		InputAction.build_belt(
			0, smelter_tile + Vector3i(0, 0, 3), smelter_tile + Vector3i(0, 0, 5)
		),
		InputAction.build_machine(
			0, definitions.machine_index("ammo_press_mk1"), smelter_tile + Vector3i(0, 0, 6)
		),
		# East off the Smelter into a Boiler, which wants coal. This branch is blocked.
		InputAction.build_belt(
			0, smelter_tile + Vector3i(3, 0, 0), smelter_tile + Vector3i(5, 0, 0)
		),
		InputAction.build_machine(
			0, definitions.machine_index("steam_boiler_mk1"), smelter_tile + Vector3i(6, 0, 0)
		),
	])
	return smelter_tile


func _first_iron_node(sim: Simulation) -> int:
	for index: int in range(sim.query_node_count()):
		if sim.query_node_resource(index) == "iron_ore" and sim.query_node_depth(index) == 1:
			return index
	return 0


## Where to stand, and the vantage is a finding rather than a taste.
##
## **From the south-east, because that is the only quarter from which both branch entries are
## on the near side of the Smelter.** The split leaves by the Machine's southern and eastern
## faces, so a camera to the west or the north has one of the two entries directly behind the
## body — which is what the first three renders of this had, and it reads exactly like a mark
## that was never drawn. The counter said one blocked post and the picture had none.
##
## High enough that the near Belt does not hide the far one, low enough that a metre of tag is
## a thing with a size rather than a dot.
func _frame(camera: Camera3D, sim: Simulation, smelter_tile: Vector3i) -> void:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	var centre: Vector3 = Vector3(
		(float(smelter_tile.x) + 1.5) * tile_size,
		0.0,
		(float(smelter_tile.z) + 1.5) * tile_size
	)
	camera.fov = 70.0
	camera.look_at_from_position(
		centre + Vector3(15.0, 12.0, 17.0), centre + Vector3(1.0, 1.0, 2.0), Vector3.UP
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
