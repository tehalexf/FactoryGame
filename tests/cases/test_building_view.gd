## What a player can see while they build: the previewed route, the ports on a Machine,
## whether a line is connected, what is on the Machine picker, and the one objective line.
##
## Smoke coverage of the rendering layer, like `test_world_view.gd`, and in its own file
## because it is all one ticket's worth of surface: #36, "the act of building". Everything
## here is asserted against the queries rather than against a remembered copy — a copy is
## the thing this layer is forbidden to have.
extends TestCase


func _run(sim: Simulation, ticks: int) -> void:
	for tick: int in range(ticks):
		sim.step([])


# ── The previewed route ───────────────────────────────────────────────────────

func test_nothing_is_previewed_until_the_belt_tool_is_out() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_eq(view.belt_preview_tile_count(), 0, "the Machine tool draws a hologram instead")
	assert_true(view.hologram_is_visible())
	view.free()


func test_the_belt_tool_previews_the_tile_under_the_aim_before_any_drag() -> void:
	# A player who has just taken the Belt tool out has not pressed anything yet, and a
	# preview that waited for the press would leave them aiming at nothing. One tile is
	# also exactly what a click would lay.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_eq(view.belt_preview_tile_count(), 1)
	assert_false(view.hologram_is_visible(), "and no Machine hologram competing with it")
	view.free()


func test_the_preview_is_the_route_the_drag_would_lay() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	var view: WorldView = WorldView.new()
	var aimed: Vector3i = BuildGun.aimed_tile(sim, 0)
	var anchor: Vector3i = Vector3i(aimed.x + 3, aimed.y, aimed.z + 2)

	view.note_belt_drag(true, anchor, BeltRoute.ALONG_X)
	view.sync(sim)
	assert_eq(
		view.belt_preview_tile_count(),
		BeltRoute.length_tiles(anchor, aimed, BeltRoute.ALONG_X),
		"every tile of the route, corner included"
	)
	assert_true(
		view.belt_preview_tile_count() > 2, "the route under test really did corner"
	)
	view.free()


func test_the_preview_marks_the_tiles_that_would_be_refused_and_not_the_others() -> void:
	# The refusal is shown **on the preview**, tile by tile, rather than as a line of text
	# after the click. The projection is the Simulation's, so what is drawn red and what the
	# drag would refuse cannot disagree.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	var view: WorldView = WorldView.new()
	var aimed: Vector3i = BuildGun.aimed_tile(sim, 0)
	var anchor: Vector3i = Vector3i(aimed.x + 4, aimed.y, aimed.z)

	view.note_belt_drag(true, anchor, BeltRoute.ALONG_X)
	view.sync(sim)
	var clear: int = view.belt_preview_tile_count()
	assert_eq(view.belt_preview_refused_tile_count(), 0, "open ground refuses nothing")

	sim.step([InputAction.build_wall(0, Vector3i(anchor.x - 1, anchor.y, anchor.z))])
	view.sync(sim)
	assert_eq(view.belt_preview_tile_count(), clear, "the route is the same length")
	assert_eq(view.belt_preview_refused_tile_count(), 1, "and one tile of it is marked")
	view.free()


func test_the_hud_says_how_long_the_route_is_and_why_it_would_be_refused() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	var view: WorldView = WorldView.new()
	var aimed: Vector3i = BuildGun.aimed_tile(sim, 0)
	var anchor: Vector3i = Vector3i(aimed.x + 4, aimed.y, aimed.z)

	view.note_belt_drag(true, anchor, BeltRoute.ALONG_X)
	view.sync(sim)
	var length: int = BeltRoute.length_tiles(anchor, aimed, BeltRoute.ALONG_X)
	assert_true(
		view.hud_text().contains("%d tiles" % length),
		"the length is on screen before the release: %s" % view.hud_text()
	)

	sim.step([InputAction.build_wall(0, Vector3i(anchor.x - 1, anchor.y, anchor.z))])
	view.sync(sim)
	assert_true(
		view.hud_text().contains(
			BuildGun.refusal_text(Simulation.Refusal.OCCUPIED)
		),
		"and so is the reason: %s" % view.hud_text()
	)
	view.free()


# ── Ports made visible ────────────────────────────────────────────────────────
# `content/machine_ports.csv` has declared every port since #19 and nothing showed a
# player any of it, so you could not tell which face of a Smelter takes ore. These assert
# that the declaration reaches the screen, for a Machine standing and for one about to be.

func test_a_standing_machine_shows_one_marker_for_every_port_it_declares() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var before: int = view.port_marker_count()

	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), Vector3i(12, 0, 12)
		)
	])
	view.sync(sim)
	var declared: int = sim.query_definitions().machine_ports().ports_of("smelter_mk1").size()
	assert_eq(declared, 3, "the Smelter declares ore in, coal in and ingot out")
	assert_eq(view.port_marker_count(), before + declared)
	view.free()


func test_inputs_and_outputs_are_counted_apart_so_they_can_be_drawn_apart() -> void:
	# Against the hologram's own ports, which are in the same buffers and are counted here
	# first — a Run opens with a Machine on the Build Gun, so there is never a frame with
	# nothing to draw.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var held_in: int = view.input_port_marker_count()
	var held_out: int = view.output_port_marker_count()

	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), Vector3i(12, 0, 12)
		)
	])
	view.sync(sim)
	assert_eq(view.input_port_marker_count() - held_in, 2, "ore and coal go in")
	assert_eq(view.output_port_marker_count() - held_out, 1, "ingot comes out")
	view.free()


func test_a_port_marker_stands_on_the_tile_the_table_declares() -> void:
	# The Smelter is 3x3 and its ingot output is the middle of the south edge, so for a body
	# anchored at (12, 12) that is tile (13, 14) — spanning 26 m to 28 m on x and 28 m to
	# 30 m on z, centre (27, 29).
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), Vector3i(12, 0, 12)
		)
	])
	view.sync(sim)
	# Marker 0 is the standing Smelter's: the Machines are written before the hologram's.
	var at: Vector3 = view.output_port_marker_position(0)
	assert_true(is_equal_approx(at.x, 27.0), "expected x 27.0, got %f" % at.x)
	assert_true(is_equal_approx(at.z, 29.0), "expected z 29.0, got %f" % at.z)
	view.free()


func test_turning_the_machine_moves_its_markers_with_it() -> void:
	# A half turn puts the south face north: the ingot port goes from local (1, 2) to
	# (1, 0), which for an anchor at (12, 12) is tile (13, 12) — centre (27, 25).
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), Vector3i(12, 0, 12), 2
		)
	])
	view.sync(sim)
	var at: Vector3 = view.output_port_marker_position(0)
	assert_true(is_equal_approx(at.x, 27.0), "expected x 27.0, got %f" % at.x)
	assert_true(is_equal_approx(at.z, 25.0), "expected z 25.0, got %f" % at.z)
	view.free()


func test_the_hologram_shows_the_ports_of_the_machine_about_to_land() -> void:
	# The whole point: which way round a Machine's faces will be is a thing to know *before*
	# the click, not after. The hologram already asks about a placement that has not
	# happened, and its ports are drawn from the same rotation it is.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.select_machine(0, sim.query_definitions().machine_index("smelter_mk1"))
	])
	view.sync(sim)
	assert_eq(
		view.port_marker_count(), 3, "nothing is standing, so these are the hologram's"
	)

	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	view.sync(sim)
	assert_eq(
		view.port_marker_count(),
		0,
		"and they go away with the hologram when the Belt tool comes out"
	)
	view.free()


# ── Connection feedback, in the world ─────────────────────────────────────────
# A Belt that feeds nothing and a Machine nothing reaches should be visible *as you build*,
# not inferred from a line of text. Each marker is one query asked every frame; nothing
# here remembers whether anything was connected.

func test_a_belt_laid_on_open_ground_is_marked_at_both_ends() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_eq(view.dangling_marker_count(), 0, "a Run with no Belts has nothing to mark")

	sim.step([InputAction.build_belt(0, Vector3i(20, 0, 20), Vector3i(24, 0, 20))])
	view.sync(sim)
	assert_eq(
		view.dangling_marker_count(), 2, "nothing feeds it and it pours onto the ground"
	)
	view.free()


func test_joining_a_belt_to_a_machine_takes_the_mark_away() -> void:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var view: WorldView = WorldView.new()
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), Vector3i(0, 0, 0))
	])
	sim.step([InputAction.build_belt(0, Vector3i(1, 0, 2), Vector3i(1, 0, 5))])
	view.sync(sim)
	assert_eq(view.dangling_marker_count(), 1, "fed by the Miner, pouring out the far end")

	sim.step([
		InputAction.build_machine(0, definitions.machine_index("smelter_mk1"), Vector3i(0, 0, 6))
	])
	view.sync(sim)
	assert_eq(view.dangling_marker_count(), 0, "both ends are somewhere now")
	view.free()


func test_a_starved_machine_is_marked_and_a_working_one_is_not() -> void:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var view: WorldView = WorldView.new()
	var definitions: Definitions = sim.query_definitions()

	# A Miner on the Node is fed by the ground under it; a Miner on bare rock is starved.
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), Vector3i(0, 0, 0))
	])
	_run(sim, 2)
	view.sync(sim)
	assert_eq(view.starved_marker_count(), 0, "a Miner over its own ore is working")

	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), Vector3i(10, 0, 10))
	])
	_run(sim, 2)
	view.sync(sim)
	assert_eq(view.starved_marker_count(), 1, "the one on bare rock is starved")
	assert_true(
		sim.query_machine_is_starved(1),
		"and the Simulation is what said so — the renderer never guesses"
	)
	view.free()


func test_a_running_belt_shows_which_way_it_carries() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_eq(view.belt_flow_arrow_count(), 0)

	sim.step([InputAction.build_belt(0, Vector3i(20, 0, 20), Vector3i(24, 0, 20))])
	view.sync(sim)
	assert_eq(
		view.belt_flow_arrow_count(),
		sim.query_belt_length_tiles(0),
		"an arrow a tile, so a line reads as a direction from any angle"
	)
	view.free()


func test_the_markers_do_not_grow_the_scene_tree_as_a_factory_is_built() -> void:
	# The rule the Belt tiles, the Items and the Enemies already obey: a thing there can be
	# thousands of is a MultiMesh instance and never a node.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var nodes: int = view.get_child_count()
	for which: int in range(6):
		sim.step([
			InputAction.build_belt(
				0, Vector3i(20, 0, 20 + which * 2), Vector3i(26, 0, 20 + which * 2)
			)
		])
		view.sync(sim)
	assert_eq(view.get_child_count(), nodes, "six Belts, no new nodes")
	assert_eq(view.dangling_marker_count(), 12, "and all twelve ends marked")
	view.free()
