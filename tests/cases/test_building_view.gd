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
