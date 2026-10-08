## What the yard costs, with a full Factory standing in it and a Wave on the Map.
##
##   bash tools/visual/frame_cost.sh
##
## Two numbers, measured separately, because under Xvfb only one of them means
## anything:
##
## * **`WorldView.sync` in milliseconds.** The CPU side — the queries, the
##   MultiMesh buffers, the occupancy filter `SetDressing` runs when something is
##   built. This is real on any machine and is the half this ticket could plausibly
##   have broken, because it added a few hundred instances and a per-tile lookup.
## * **Draw calls and primitives in the frame.** A count rather than a time, so it
##   is honest under software rendering: the question "does the yard cost a draw
##   call per crate" has a number, and the answer does not depend on the GPU.
##
## Frame *time* is deliberately not reported. Xvfb gives llvmpipe, which is one to
## two orders of magnitude off any real GPU, and a number that wrong is worse than
## no number.
extends SceneTree

const WARMUP_FRAMES: int = 30
const MEASURED_FRAMES: int = 120


## The shipped content with one key changed: a stock big enough to pay for a
## Factory. The opening eighty plate buys a Miner, a Smelter and a Boiler, which
## is a worked example rather than a load — and what this measures is the load.
## Every other number is the real file's.
## How many Enemies of each swarm kind to put on the Map, taken off the command line:
##
##   ENEMY_COUNT=200 bash tools/visual/frame_cost.sh
##
## The shipped Wave table puts six Crawlers on the Map at Heat 1, which is the honest
## *typical* load and is not the one a scale claim is made about. ADR 0001's whole Enemy
## target is thousands of array entries, so the number that settles whether the renderer can
## carry it has to be asked for rather than waited for.
func _wave_table(count: int) -> String:
	if count <= 0:
		return _read("res://content/waves.csv")
	@warning_ignore("integer_division")
	var each: int = maxi(count / 3, 1)
	return (
		"id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach\n"
		+ "chaff_crawlers,crawler,0,%d,0,%d\n" % [each * 2, each * 2]
		+ "shock_breakers,breaker,0,%d,0,%d\n" % [each, each]
	)


func _funded(count: int = 0) -> Definitions:
	var tuning: FileAccess = FileAccess.open("res://content/tuning.toml", FileAccess.READ)
	var text: String = tuning.get_as_text()
	tuning.close()
	var stocked: String = text.replace(
		'starting_stock = "iron_plate:110"',
		'starting_stock = "ammunition:900;coal:900;iron_ore:900;iron_plate:900"'
	)
	return Definitions.parse(
		_read("res://content/machines.csv"),
		_read("res://content/recipes.csv"),
		stocked,
		_wave_table(count),
		_read("res://content/deliveries.csv"),
		_read("res://content/gear.csv"),
		_read("res://content/stratagems.csv"),
		"machines.csv", "recipes.csv", "tuning.toml", "waves.csv",
		"deliveries.csv", "gear.csv", "stratagems.csv"
	)


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	return text


func _initialize() -> void:
	var asked: int = int(OS.get_environment("ENEMY_COUNT"))
	var funded: Definitions = _funded(asked)
	if funded.has_errors():
		push_error(funded.describe_errors())
	var sim: Simulation = Simulation.new(1, 1, funded)
	var view: WorldView = WorldView.new()
	root.add_child(view)

	_build_a_full_factory(sim)
	_bring_a_wave(sim, asked)

	print("Factory: %d Machines, %d Belts, %d Walls" % [
		sim.query_machine_count(), sim.query_belt_count(), sim.query_wall_count()
	])
	print("Wave: %d Enemies on the Map, Heat %d" % [sim.query_enemy_count(), sim.query_heat()])

	for frame: int in range(WARMUP_FRAMES):
		await process_frame
		view.sync(sim)

	var dressing: SetDressing = null
	for child: Node in view.get_children():
		if child is SetDressing:
			dressing = child
	if dressing != null:
		print("Yard: %d props out of %d meshes, purchased packs: %s" % [
			dressing.instance_count(), dressing.group_count(),
			"yes" if dressing.uses_purchased_props() else "no (stand-ins)"
		])

	var spent: int = 0
	var worst: int = 0
	for frame: int in range(MEASURED_FRAMES):
		await process_frame
		sim.step([])
		var began: int = Time.get_ticks_usec()
		view.sync(sim)
		var took: int = Time.get_ticks_usec() - began
		spent += took
		worst = maxi(worst, took)

	print("WorldView.sync: mean %.3f ms, worst %.3f ms over %d frames" % [
		float(spent) / float(MEASURED_FRAMES) / 1000.0, float(worst) / 1000.0, MEASURED_FRAMES
	])
	# The yard's own share, both ways round. In the steady state `SetDressing.sync`
	# compares one integer and returns, because nothing has been built; the cost
	# that matters is the **rebuild**, which happens on the frame after a player
	# places something and walks every placement against the occupancy queries.
	if dressing != null:
		var idle_began: int = Time.get_ticks_usec()
		for frame: int in range(MEASURED_FRAMES):
			dressing.sync(sim)
		var idle: float = float(Time.get_ticks_usec() - idle_began) / float(MEASURED_FRAMES)
		sim.step([InputAction.build_wall(0, Vector3i(30, WorldGrid.GROUND_LAYER, 30))])
		var rebuild_began: int = Time.get_ticks_usec()
		dressing.sync(sim)
		var rebuild: int = Time.get_ticks_usec() - rebuild_began
		print("SetDressing.sync: %.4f ms unchanged, %.3f ms on the frame after a build" % [
			idle / 1000.0, float(rebuild) / 1000.0
		])

	print("draw calls in frame: %d" % int(
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	))
	print("primitives in frame: %d" % int(
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	))
	print("objects in frame:    %d" % int(
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	))
	print("video memory:        %.1f MB" % (
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	))
	quit()


## Every Node worked, a Belt off each, and a wall of Walls. Bigger than anything
## `tests/` builds, because the question is what a Factory costs rather than what
## one Machine does.
func _build_a_full_factory(sim: Simulation) -> void:
	var definitions: Definitions = sim.query_definitions()
	var miner: int = definitions.machine_index("miner_mk1")
	var smelter: int = definitions.machine_index("smelter_mk1")
	var boiler: int = definitions.machine_index("steam_boiler_mk1")
	var turret: int = definitions.machine_index("mg_turret_mk1")

	for index: int in range(sim.query_node_count()):
		var node: Vector3i = sim.query_node_tile(index)
		sim.step([InputAction.build_machine(0, miner, node)])
		sim.step([InputAction.build_machine(0, smelter, node + Vector3i(6, 0, 0))])
		sim.step([InputAction.build_machine(0, boiler, node + Vector3i(0, 0, 6))])
		sim.step([InputAction.build_machine(0, turret, node + Vector3i(6, 0, 6))])
		sim.step([
			InputAction.build_belt(0, node + Vector3i(2, 0, 0), node + Vector3i(5, 0, 0))
		])
		for along: int in range(12):
			sim.step([InputAction.build_wall(0, node + Vector3i(-3, 0, along - 6))])
		# A second line out the other side, so the Factory is a Factory rather than
		# one chain repeated.
		sim.step([InputAction.build_machine(0, smelter, node + Vector3i(0, 0, 11))])
		sim.step([InputAction.build_machine(0, turret, node + Vector3i(6, 0, 11))])
		sim.step([InputAction.build_machine(0, boiler, node + Vector3i(11, 0, 0))])
		sim.step([
			InputAction.build_belt(0, node + Vector3i(0, 0, 8), node + Vector3i(0, 0, 10))
		])


## Call the Wave in and let it arrive, so the swarm is on the Map while the cost
## is taken. A Wave is the busiest the renderer ever gets.
func _bring_a_wave(sim: Simulation, wanted: int = 0) -> void:
	sim.step([InputAction.call_wave_early(0)])
	for tick: int in range(6000):
		sim.step([])
		if wanted > 0:
			# A Wave trickles out of its Breaches rather than arriving at once, so asking
			# for two hundred means waiting for two hundred rather than for the Telegraph.
			if sim.query_enemy_count() >= wanted:
				break
		elif sim.query_enemy_count() > 0 and tick > 900:
			break
