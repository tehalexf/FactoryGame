## Composes a screenshot of **two Belts that will not dock, for the two different reasons**,
## and writes it to a PNG.
##
##   SHOT_SCRIPT=tools/visual/compose_dock_shot.gd tools/visual/shot.sh out.png [bare]
##
## A tool, not part of the game, and a fourth sibling of `compose_shot.gd`,
## `compose_building_shot.gd` and `compose_branch_shot.gd`. It answers the question #56 is
## about: **a line is laid, the Machine is right there, and nothing hands over — does the game
## tell you what to do about it?**
##
## It needs its own composer for `compose_branch_shot.gd`'s reason, and the subject is even
## more awkward. What has to be legible is four things at once, at three very different
## scales: the red post at each refused end, the **port arrows** on the Machine beside it
## (because the advice is "turn the Machine", and the arrows are what a turned Machine would
## move), and the HUD's own sentences. At eye level the near Machine hides the far one; from
## Survey View the arrows are a smear and the posts are three pixels. So the camera is
## **placed**, like `compose_shot.gd`'s, and the **HUD is left on**, like
## `compose_building_shot.gd`'s, because the sentences are half the subject.
##
## The two subjects are chosen so that one picture carries both answers:
##
##  * **A Smelter stood square with a line arriving at its eastern wall.** That wall is where
##    plate comes *out*, so the port is right there and pointing the wrong way — the mistake
##    #47 recorded, and the one only rotation fixes.
##  * **A Steam Boiler with a line arriving at its southern wall.** `content/machine_ports.csv`
##    declares that Machine's coal faces as north and west and says nothing at all about its
##    south, so that wall is not a port — which rotation *or* aiming elsewhere would fix.
extends SceneTree

const FRAMES_TO_SETTLE: int = 30

## Only long enough for the Factory to be visibly working: nothing in frame depends on an
## Item having travelled, because what is being judged is a mark and a sentence about
## geometry. A few seconds so the Miner has something on its Belt and the picture is of a
## Factory rather than of a diagram.
const TICKS_TO_RUN: int = 600


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = "shot.png" if arguments.size() < 1 else arguments[0]
	# `bare` hides the yard, for the reason `compose_branch_shot.gd` has it: judge the grade
	# on a dressed shot and the *geometry* on a bare one, because a mark hidden behind a prop
	# and a mark that was never drawn look identical in a picture.
	var bare: bool = arguments.has("bare")

	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	root.add_child(view)

	var anchor: Vector3i = _build_the_two_mistakes(sim)
	print("smelter at ", anchor)
	for tick: int in range(TICKS_TO_RUN):
		sim.step([])

	view.sync(sim)
	var camera: Camera3D = _camera_of(view)
	for frame: int in range(FRAMES_TO_SETTLE):
		await process_frame
		view.sync(sim)
		_frame(camera, sim, anchor)
		if bare:
			_hide_the_yard(view)

	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(out_path)
	print(
		"wrote %s (%dx%d) — %d belts, %d dangling posts"
		% [
			out_path,
			image.get_width(),
			image.get_height(),
			sim.query_belt_count(),
			view.dangling_marker_count(),
		]
	)
	# The reasons, printed, so the picture can be read against what the Simulation actually
	# says rather than against what the composer meant to build. Three renders of #48 had a
	# counter and a picture that disagreed.
	for index: int in range(sim.query_belt_count()):
		print(
			"  belt %d: start %d, end %d"
			% [
				index,
				sim.query_belt_start_dock_refusal(index),
				sim.query_belt_end_dock_refusal(index),
			]
		)
	for marker: int in range(view.dangling_marker_count()):
		print("  dangling post at ", view.dangling_marker_position(marker))
	print("  HUD:")
	for line: String in view.hud_brief_text().split("\n"):
		print("    ", line)
	quit()


## The subject. A working Miner for context, then the two mistakes side by side.
##
## Both lines are laid **toward** their Machine so the refused end is the far one, which is
## how a player lays a line: you start at the thing that has the goods and drag to the thing
## that wants them. Returns the tile the camera frames about.
func _build_the_two_mistakes(sim: Simulation) -> Vector3i:
	var definitions: Definitions = sim.query_definitions()
	var node_tile: Vector3i = sim.query_node_tile(_first_iron_node(sim))
	var smelter_tile: Vector3i = node_tile + Vector3i(0, 0, 6)

	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), node_tile),
		InputAction.build_machine(0, definitions.machine_index("smelter_mk1"), smelter_tile),
	])
	sim.step([
		# The line that works, so the picture contains a connected Belt as well as two that
		# are not: a render in which everything is refused says nothing about the contrast.
		InputAction.build_belt(
			0, node_tile + Vector3i(1, 0, 2), smelter_tile + Vector3i(1, 0, -1)
		),
		InputAction.build_machine(
			0, definitions.machine_index("steam_boiler_mk1"), smelter_tile + Vector3i(0, 0, 6)
		),
	])
	sim.step([
		# A line arriving at the Smelter's **eastern** wall, which is an output port. Docked,
		# pointing the right way, and it will never be handed anything.
		InputAction.build_belt(
			0, smelter_tile + Vector3i(6, 0, 1), smelter_tile + Vector3i(3, 0, 1)
		),
		# And one arriving at the Boiler's **southern** wall, which declares no port at all.
		InputAction.build_belt(
			0, smelter_tile + Vector3i(1, 0, 11), smelter_tile + Vector3i(1, 0, 8)
		),
	])
	return smelter_tile


func _first_iron_node(sim: Simulation) -> int:
	for index: int in range(sim.query_node_count()):
		if sim.query_node_resource(index) == "iron_ore" and sim.query_node_depth(index) == 1:
			return index
	return 0


## Where to stand. **From the east and above**, because that is the one quarter from which
## both refused ends are on the near side of their own Machine — the Smelter's is on its
## eastern face and the Boiler's on its southern, so a camera to the west or the north puts
## one of the two behind a body, which is `compose_branch_shot.gd`'s fourth finding and reads
## exactly like a mark that was never drawn.
##
## High enough to see over the near Belt's deck and down onto the port arrows, which are flat
## on the ground: the arrows are what the advice is about, so a vantage that flattened them
## to nothing would be framing away half the subject.
func _frame(camera: Camera3D, sim: Simulation, _smelter_tile: Vector3i) -> void:
	# Framed on the **two refused ends themselves**, read back out of the Simulation rather
	# than worked out from the tiles this file asked for. #48 spent three renders on a counter
	# that said one blocked post and a picture with none in it, and the cause every time was a
	# camera placed from what the composer meant rather than from where the mark went.
	var centre: Vector3 = (_refused_end(sim, 1) + _refused_end(sim, 2)) * 0.5
	camera.fov = 66.0
	camera.look_at_from_position(
		centre + Vector3(9.5, 6.5, 6.0), centre + Vector3(0.0, 1.3, 0.0), Vector3.UP
	)


## Where a Belt's far end actually is, in metres.
func _refused_end(sim: Simulation, index: int) -> Vector3:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	var tile: Vector3i = sim.query_belt_tile(index, sim.query_belt_length_tiles(index) - 1)
	return Vector3((float(tile.x) + 0.5) * tile_size, 0.0, (float(tile.z) + 0.5) * tile_size)


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
