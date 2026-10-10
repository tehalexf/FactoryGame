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
	# With the Build Gun drawn: a Run opens with the weapon out since #42, and since #35
	# a holstered gun draws no hologram at all — which is a different claim from this one
	# and has its own test.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_mode(0, true)])
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


## **#67, and it is #35's defect in the Belt tool.** A route lands whole or not at all —
## `_apply_build_belt` consults `_belt_route_refusal` over every tile before the first Belt
## appears — so a route with one blocked tile lays **nothing**. The preview tinted tile by
## tile off `query_belt_tile_refusal`, which is only part of that rule, so nine tiles of a
## ten-tile route wore `HOLOGRAM_ALLOWED` and the release did not put one of them down.
##
## The per-tile red is kept and is not what this is about: it says *where* the trouble is.
## What the colour of the route says is whether the release will be kept.
func test_a_route_that_would_be_refused_is_not_drawn_in_the_colour_that_promises_a_lay() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	var view: WorldView = WorldView.new()
	var aimed: Vector3i = BuildGun.aimed_tile(sim, 0)
	var anchor: Vector3i = Vector3i(aimed.x + 4, aimed.y, aimed.z)

	view.note_belt_drag(true, anchor, BeltRoute.ALONG_X)
	view.sync(sim)
	assert_true(view.belt_preview_promises_a_lay(), "open ground: the release is kept")

	sim.step([InputAction.build_wall(0, Vector3i(anchor.x - 1, anchor.y, anchor.z))])
	view.sync(sim)
	assert_eq(
		sim.query_belt_route_refusal(0, anchor, aimed, BeltRoute.ALONG_X),
		Simulation.Refusal.OCCUPIED,
		"the route under test really is one the release would refuse whole"
	)
	assert_false(
		view.belt_preview_promises_a_lay(),
		"so not one tile of it may wear the colour that invites the release"
	)
	assert_true(
		view.belt_preview_refused_tile_count() > 0,
		"and the tile in the way is still marked, because the colour says whether and the"
			+ " mark says where"
	)
	view.free()


## The purest version of the same fault, and the one no per-tile tint could ever have
## caught: every tile is clear ground and the wallet cannot pay for them. Before #67 this
## drew a full route in green and laid nothing at all.
func test_a_route_the_wallet_cannot_pay_for_previews_as_refused_though_every_tile_is_clear() -> void:
	# Three plate in the pockets against a four-tile route, so the refusal is the wallet and
	# nothing else. Shrinking the bill rather than lengthening the drag keeps the premise
	# independent of how wide the Map happens to be.
	var fixture: ContentFixture = ContentFixture.for_case(self).stock("iron_plate:3")
	# A fixture that supplies no structures table gets structures that are **free** (#47's
	# escape), so a test about the wallet has to ask for the shipped prices by name.
	fixture.structures = ContentFixture.shipped(Definitions.STRUCTURES_FILE)
	var definitions: Definitions = fixture.definitions()
	assert_false(definitions.has_errors(), definitions.describe_errors())
	var sim: Simulation = Simulation.new(1, 1, definitions)
	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	var view: WorldView = WorldView.new()
	var aimed: Vector3i = BuildGun.aimed_tile(sim, 0)
	var anchor: Vector3i = Vector3i(aimed.x + 3, aimed.y, aimed.z)

	view.note_belt_drag(true, anchor, BeltRoute.ALONG_X)
	view.sync(sim)
	assert_eq(
		sim.query_belt_route_refusal(0, anchor, aimed, BeltRoute.ALONG_X),
		Simulation.Refusal.MISSING_MATERIALS,
		"the premise: refused for the plate rather than for the ground"
	)
	assert_eq(
		view.belt_preview_refused_tile_count(), 0, "and no tile of it is individually blocked"
	)
	assert_false(
		view.belt_preview_promises_a_lay(),
		"so the only thing that can say so is the colour of the route"
	)
	view.free()


## The rule #56 settled, pinned from the renderer's side: **dock advice is advice and never
## a veto**. A route whose far end will not hand its goods over lays perfectly well — a
## player routes a line in stages past where the Machine is going to stand every day — so it
## must still preview in the colour that says the release will be kept.
func test_a_route_whose_end_will_not_dock_still_previews_as_one_that_lays() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	var view: WorldView = WorldView.new()
	var aimed: Vector3i = BuildGun.aimed_tile(sim, 0)
	var anchor: Vector3i = Vector3i(aimed.x + 4, aimed.y, aimed.z)

	view.note_belt_drag(true, anchor, BeltRoute.ALONG_X)
	view.sync(sim)
	assert_eq(
		sim.query_belt_route_refusal(0, anchor, aimed, BeltRoute.ALONG_X),
		Simulation.Refusal.NONE,
		"nothing is in the way and the plate is there"
	)
	assert_true(
		view.belt_preview_promises_a_lay(),
		"whatever either end would or would not dock against"
	)
	view.free()


## A line cannot mean "release it" and "cannot build there" at once, and the shot in #67 had
## one that said both: the lead clause was printed unconditionally beside a verdict that was
## perfectly correct. So the lead is the liar, and it is the half that moves.
func test_the_belt_line_does_not_invite_a_release_it_says_in_the_same_breath_is_refused() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	var view: WorldView = WorldView.new()
	var aimed: Vector3i = BuildGun.aimed_tile(sim, 0)
	var anchor: Vector3i = Vector3i(aimed.x + 4, aimed.y, aimed.z)

	view.note_belt_drag(true, anchor, BeltRoute.ALONG_X)
	view.sync(sim)
	assert_true(
		view.hud_text().contains("release to lay"),
		"a route that lays invites the release: %s" % view.hud_text()
	)

	sim.step([InputAction.build_wall(0, Vector3i(anchor.x - 1, anchor.y, anchor.z))])
	view.sync(sim)
	var refused: String = view.hud_text()
	assert_true(
		refused.contains(BuildGun.refusal_text(Simulation.Refusal.OCCUPIED)),
		"the reason is still said: %s" % refused
	)
	assert_false(
		refused.contains("release to lay"),
		"and the same line no longer invites the release it is refusing: %s" % refused
	)
	view.free()


## **The panel describes the tool in hand.** `_build_gun_lines` asked `BuildGun.placement`
## about the Machine on the gun and printed its refusal unconditionally, so #67's shot read
## `aimed at -6, 10 — cannot build there — something is already standing` directly above the
## route line — a sentence about where a Miner could stand, in a frame where the player was
## dragging a Belt, which reads as being about the route.
##
## Where a Machine would or would not go is simply not the question being asked with the
## Belt tool out, and the route line underneath answers the one that is.
func test_the_aim_line_is_about_the_machine_only_while_the_machine_tool_is_out() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_mode(0, true)])
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_true(
		view.hud_text().contains("aimed at"),
		"the Machine tool: where it would land is exactly the question: %s" % view.hud_text()
	)

	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	view.sync(sim)
	var belting: String = view.hud_text()
	assert_false(
		belting.contains("aimed at"),
		"the Belt tool: the route line is what the player is asking about: %s" % belting
	)
	assert_true(
		belting.contains("belt:"), "and it is still there to answer them: %s" % belting
	)
	view.free()


## The same sentence one line up. `build gun: miner_mk1 facing 0` over a Belt drag names a
## Machine nobody is placing and a rotation nothing will be turned by, which is the fault
## above wearing a different hat.
func test_the_build_gun_line_names_the_tool_that_is_actually_in_hand() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_mode(0, true)])
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_true(
		view.hud_text().contains("build gun: %s" % sim.query_player_selected_machine(0)),
		"the Machine tool names the Machine: %s" % view.hud_text()
	)

	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	view.sync(sim)
	var belting: String = view.hud_text()
	assert_false(
		belting.contains("build gun: %s" % sim.query_player_selected_machine(0)),
		"the Belt tool does not: %s" % belting
	)
	assert_true(
		belting.contains("build gun: belt"), "it names the Belt: %s" % belting
	)
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

func test_the_tile_the_port_tests_stand_on_is_the_one_a_run_opens_pointed_at() -> void:
	# `AIMED_TILE` is a literal in four tests below. If the opening pose ever moves, this is
	# what says so, rather than four tests quietly asserting about empty ground.
	var sim: Simulation = Simulation.new(1, 1)
	assert_eq(BuildGun.aimed_tile(sim, 0), AIMED_TILE)


func test_a_holstered_build_gun_draws_no_port_arrows_at_all() -> void:
	# #66. An arrow is advice about where to put a Belt, and since #42 the weapon is the
	# default hand — so the state a player spends most of a Run in was the state the whole
	# Factory wore a hedge of 3.2 m quads in.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	var where: Vector3i = BuildGun.aimed_tile(sim, 0)
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), where
		)
	])
	view.sync(sim)
	assert_eq(view.port_marker_count(), 0, "the Build Gun is holstered")

	sim.step([InputAction.set_build_mode(0, true)])
	view.sync(sim)
	assert_true(
		view.port_marker_count() > 0, "and the same Machine wears them once it is drawn"
	)
	view.free()


func test_a_belt_drag_keeps_the_arrows_at_the_end_it_started_from() -> void:
	# A route has two ends, and the far one is the one a player committed to several seconds
	# ago. Without the anchor the arrow that started the drag goes out while the drag is being
	# made, which is the one moment it is being read.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([
		InputAction.set_build_mode(0, true),
		InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT),
	])
	var view: WorldView = WorldView.new()
	var far: Vector3i = AIMED_TILE + Vector3i(WorldView.PORT_ARROW_RANGE_TILES * 4, 0, 0)
	sim.step([
		InputAction.build_machine(0, sim.query_definitions().machine_index("smelter_mk1"), far)
	])
	view.sync(sim)
	assert_eq(view.port_marker_count(), 0, "out of range of the aim, and no hologram is up")

	view.note_belt_drag(true, far, BeltRoute.ALONG_X)
	view.sync(sim)
	assert_eq(
		view.port_marker_count(),
		sim.query_definitions().machine_ports().ports_of("smelter_mk1").size(),
		"a drag anchored on it is a question about it"
	)
	view.free()


func test_a_machine_near_the_aim_wears_every_port_it_has_or_none_of_them() -> void:
	# A render caught this: filtered tile by tile, a Machine straddling the range showed the
	# arrows on its near face and not the ones on its far one — which reads as "those are all
	# the ports it has", and is a worse thing to tell a player than nothing at all. So the
	# range decides *whether a Machine is being asked about*, and the answer is its whole
	# declaration either way.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_mode(0, true)])
	var view: WorldView = WorldView.new()
	var declared: int = sim.query_definitions().machine_ports().ports_of("smelter_mk1").size()
	var view_before: int = 0
	view.sync(sim)
	view_before = view.port_marker_count()

	# A 3x3 Smelter with one corner just inside the range and the opposite one outside it.
	sim.step([
		InputAction.build_machine(
			0,
			sim.query_definitions().machine_index("smelter_mk1"),
			AIMED_TILE + Vector3i(WorldView.PORT_ARROW_RANGE_TILES - 1, 0, 0)
		)
	])
	view.sync(sim)
	assert_eq(
		view.port_marker_count() - view_before,
		declared,
		"every port of a Machine the range reaches, not the near face only"
	)
	view.free()


func test_arrows_are_drawn_where_the_build_gun_is_pointing_and_not_across_the_yard() -> void:
	# #66's second fault. Eight of the ten shipped Machines declare every tile of every face,
	# so a Factory left to wear all of them at once is a hedge of quads — and a ring of twelve
	# arrows pointing outward in every direction has no tile in it. Drawn only around the aim,
	# the ring is a legend for the Machine a player is actually deciding about.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_mode(0, true)])
	var view: WorldView = WorldView.new()
	var smelter: int = sim.query_definitions().machine_index("smelter_mk1")
	var aimed: Vector3i = BuildGun.aimed_tile(sim, 0)

	sim.step([InputAction.build_machine(0, smelter, aimed + Vector3i(0, 0, 2))])
	view.sync(sim)
	var near: int = view.port_marker_count()
	assert_true(near > 0, "the Machine the gun is pointing at wears its ports")

	sim.step([InputAction.build_machine(0, smelter, aimed + Vector3i(30, 0, 30))])
	view.sync(sim)
	assert_eq(
		view.port_marker_count(), near, "and one thirty tiles away adds nothing to the frame"
	)
	view.free()


## The tile a Run's Build Gun points at on tick 0, with nobody having moved or looked.
## Written down rather than read back, so these tests state the ground they stand on — and
## since #66 an arrow is only drawn near the aim, so the port tests have to build *here*.
const AIMED_TILE: Vector3i = Vector3i(0, 0, -8)


# `content/machine_ports.csv` has declared every port since #19 and nothing showed a
# player any of it, so you could not tell which face of a Smelter takes ore. These assert
# that the declaration reaches the screen, for a Machine standing and for one about to be.

func test_a_standing_machine_shows_one_marker_for_every_port_it_declares() -> void:
	# With the Build Gun drawn, and named rather than assumed: since #66 a holstered gun
	# draws no arrows at all, which is its own test above.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_mode(0, true)])
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var before: int = view.port_marker_count()

	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), AIMED_TILE
		)
	])
	view.sync(sim)
	var declared: int = sim.query_definitions().machine_ports().ports_of("smelter_mk1").size()
	assert_eq(
		declared,
		12,
		"the Smelter declares whole faces: ore in, coal in, ingot out two ways, three tiles each"
	)
	assert_eq(view.port_marker_count(), before + declared)
	view.free()


func test_inputs_and_outputs_are_counted_apart_so_they_can_be_drawn_apart() -> void:
	# Against the hologram's own ports, which are in the same buffers and are counted here
	# first — a Run opens with a Machine on the Build Gun, so there is never a frame with
	# nothing to draw.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_mode(0, true)])
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var held_in: int = view.input_port_marker_count()
	var held_out: int = view.output_port_marker_count()

	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), AIMED_TILE
		)
	])
	view.sync(sim)
	# A Smelter is 3x3 and declares whole faces: ore along the north, coal along the west,
	# ingot along the south and the east. Whole faces rather than one tile each, because #47
	# made the declaration the rule and a Machine with one declared output could not branch —
	# see `content/machine_ports.csv`.
	assert_eq(view.input_port_marker_count() - held_in, 6, "ore and coal go in, three tiles each")
	assert_eq(view.output_port_marker_count() - held_out, 6, "ingot comes out of two faces")
	view.free()


func test_a_port_marker_stands_on_the_tile_a_belt_would_dock_at() -> void:
	# The Smelter is 3x3 and the first ingot output declared is the near end of its south edge,
	# which is tile (0, -6) of a body anchored at (0, -8). The marker goes on the tile *past*
	# it — (0, -5), spanning 0 m to 2 m on x and -10 m to -8 m on z, centre (1, -9) — because
	# a marker on the port tile is a marker inside the Machine, which a render showed
	# immediately, and because the tile outside is where the Belt actually goes.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.set_build_mode(0, true),
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), AIMED_TILE
		)
	])
	view.sync(sim)
	# Marker 0 is the standing Smelter's: the Machines are written before the hologram's.
	var at: Vector3 = view.output_port_marker_position(0)
	assert_true(is_equal_approx(at.x, 1.0), "expected x 1.0, got %f" % at.x)
	assert_true(is_equal_approx(at.z, -9.0), "expected z -9.0, got %f" % at.z)
	view.free()


func test_turning_the_machine_moves_its_markers_with_it() -> void:
	# A half turn puts the south face north: the first ingot port goes from local (0, 2) to
	# (2, 0), which for an anchor at (0, -8) is tile (2, -8), and the tile a Belt would
	# dock at is (2, -9) — centre (5, -17).
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.set_build_mode(0, true),
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), AIMED_TILE, 2
		)
	])
	view.sync(sim)
	var at: Vector3 = view.output_port_marker_position(0)
	assert_true(is_equal_approx(at.x, 5.0), "expected x 5.0, got %f" % at.x)
	assert_true(is_equal_approx(at.z, -17.0), "expected z -17.0, got %f" % at.z)
	view.free()


func test_the_hologram_shows_the_ports_of_the_machine_about_to_land() -> void:
	# The whole point: which way round a Machine's faces will be is a thing to know *before*
	# the click, not after. The hologram already asks about a placement that has not
	# happened, and its ports are drawn from the same rotation it is.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.set_build_mode(0, true),
		InputAction.select_machine(0, sim.query_definitions().machine_index("smelter_mk1"))
	])
	view.sync(sim)
	assert_eq(
		view.port_marker_count(), 12, "nothing is standing, so these are the hologram's"
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


func test_a_starved_tag_is_tethered_to_the_body_it_is_about() -> void:
	# #66's third fault, which is #41's rule a fourth time. A Steam Boiler's drawn body tops
	# out in a narrow chimney, so a tag resting 1.2 m over that top is 1.2 m of sky over a
	# pipe: at the distance a player reads a Factory from it is a bright amber slab belonging
	# to nobody, which is exactly what the `running` render showed. The lift is right — #50
	# measured it — so what was missing was the thing that says whose mark it is.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), AIMED_TILE
		)
	])
	view.sync(sim)
	assert_eq(view.starved_marker_count(), 1, "a Smelter with nothing coming in")
	assert_eq(
		view.starved_tether_count(),
		view.starved_marker_count(),
		"one tether per tag, so no tag is ever left floating"
	)

	var tag: Vector3 = view.starved_marker_position(0)
	var tether: Vector3 = view.starved_tether_position(0)
	var roof: float = view.machine_drawn_roof_metres(sim, 0)
	assert_true(
		roof < tether.y and tether.y < tag.y,
		"the tether spans roof %.2f to tag %.2f, and sits at %.2f" % [roof, tag.y, tether.y]
	)
	assert_true(
		is_equal_approx(tether.x, tag.x) and is_equal_approx(tether.z, tag.z),
		"and stands directly under it"
	)
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


# ── The one objective line ────────────────────────────────────────────────────
# A Run opens on bare ground with 110 plate and no idea what to do. The line is a pure
# function of the Run's state, so there is nothing to enter, nothing to skip, and it comes
# back if the thing it was about stops being true.

func test_a_fresh_run_is_told_to_put_a_miner_on_a_node() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_true(Objective.line(sim, 0).contains("Miner"), Objective.line(sim, 0))
	# Where to put it, which since #52 is a Resource and a bearing rather than the word
	# "node": the playtest that produced that ticket proves naming the act was not enough.
	assert_true(Objective.line(sim, 0).contains("iron ore"), "and where to put it")


func test_a_miner_on_bare_rock_has_not_done_the_first_thing() -> void:
	# Telling a player they have done a step they have not is worse than saying nothing: a
	# Miner off its Node banks no progress at all, and the line has to agree with that.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("miner_mk1"), Vector3i(20, 0, 20)
		)
	])
	assert_true(Objective.line(sim, 0).contains("Miner"), Objective.line(sim, 0))


func test_the_line_moves_on_as_the_opening_line_gets_built() -> void:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var definitions: Definitions = sim.query_definitions()

	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), Vector3i(0, 0, 0))
	])
	assert_true(Objective.line(sim, 0).contains("Smelter"), Objective.line(sim, 0))

	sim.step([
		InputAction.build_machine(0, definitions.machine_index("smelter_mk1"), Vector3i(0, 0, 5))
	])
	assert_true(Objective.line(sim, 0).contains("Belt"), Objective.line(sim, 0))

	sim.step([InputAction.build_belt(0, Vector3i(1, 0, 2), Vector3i(1, 0, 4))])
	assert_false(
		Objective.line(sim, 0).contains("Belt tool"),
		"the Belt is fed at one end and lands at the other: %s" % Objective.line(sim, 0)
	)


## **#67: the line does not name a key for a tool already in hand.** Both survey shots said
## `Press C for the Belt tool, then drag from the orange arrow to the blue one` in a frame
## where the Belt tool was out and a route was mid-drag — an instruction to do a thing the
## player had done. It is `_with_the_build_gun`'s shape one step further: a step's *wording*
## changing off a query, not a step of its own, because "press C" is not a thing to achieve.
func test_the_belt_step_stops_naming_the_key_once_the_belt_tool_is_out() -> void:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var definitions: Definitions = sim.query_definitions()
	sim.step([InputAction.set_build_mode(0, true)])
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), Vector3i(0, 0, 0))
	])
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("smelter_mk1"), Vector3i(0, 0, 5))
	])
	assert_true(
		Objective.line(sim, 0).contains("Belt tool"),
		"the Machine tool is out, so the key is worth naming: %s" % Objective.line(sim, 0)
	)

	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	var holding: String = Objective.line(sim, 0)
	assert_false(
		holding.contains("Belt tool"), "and it stops being, the moment it is out: %s" % holding
	)
	assert_true(
		holding.to_lower().contains("drag from the orange arrow"),
		"but the act itself is still named: %s" % holding
	)


## And the two clauses compose rather than racing: a player holding a rifle is told about
## the Build Gun first, whatever tool the gun happens to have on it.
func test_the_belt_step_names_the_build_gun_first_when_it_is_holstered() -> void:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var definitions: Definitions = sim.query_definitions()
	sim.step([InputAction.set_build_mode(0, true)])
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), Vector3i(0, 0, 0))
	])
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("smelter_mk1"), Vector3i(0, 0, 5))
	])
	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	sim.step([InputAction.set_build_mode(0, false)])
	var line: String = Objective.line(sim, 0)
	assert_true(line.begins_with("Press B for the Build Gun"), line)
	assert_false(line.contains("Belt tool"), "the Belt tool is already on it: %s" % line)


func test_a_belt_laid_on_open_ground_does_not_count_as_a_connection() -> void:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), Vector3i(0, 0, 0))
	])
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("smelter_mk1"), Vector3i(0, 0, 5))
	])
	sim.step([InputAction.build_belt(0, Vector3i(20, 0, 20), Vector3i(24, 0, 20))])
	assert_true(
		Objective.line(sim, 0).contains("Belt tool"),
		"a Belt nothing feeds taught the player nothing: %s" % Objective.line(sim, 0)
	)


func test_the_line_goes_away_once_a_delivery_has_been_made() -> void:
	# The loop has closed at least once: mined, crafted, moved and been paid for it. A hint
	# line at the top of the screen after that is a hint line in the way.
	var sim: Simulation = Simulation.new(1, 1)
	assert_ne(Objective.line(sim, 0), "", "there is something to say at the start")
	var stocked: Simulation = _run_with_a_tier_completed()
	assert_eq(Objective.line(stocked, 0), "", "and nothing to say once a tier has landed")


## A Run whose first Delivery tier wants one plate, handed over by the player standing where
## a Run starts them — on the Nest's own crown, which is within reach of its counter.
##
## The shipped chain wants twenty coal, which is a Coal Miner and several minutes. The tier
## is replaced rather than the clock wound forward, which is the substitution several suites
## already make: what is under test is the objective line going quiet, not the shipped chain.
func _run_with_a_tier_completed() -> Simulation:
	var deliveries: String = (
		"id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems\n"
		+ "t01_first_crate,First Crate,1,iron_plate:1,miner_mk2,,\n"
	)
	# The hand-over reach widened, so the fixture does not have to walk the player to the
	# Nest to prove something that is not about walking. Progression is physical and the
	# reach is the rule that makes it so; `test_delivery` is where that rule is asserted.
	var fixture: ContentFixture = ContentFixture.for_case(self)
	fixture.deliveries = deliveries
	var definitions: Definitions = fixture.tune_key("delivery_reach_metres", "80").definitions()
	assert_false(definitions.has_errors(), definitions.describe_errors())
	var sim: Simulation = Simulation.new(1, 1, definitions)
	# Depth 1 is the shallowest a tier can be gated at, and Depth is derived from the Factory
	# — a Miner actually working a Node — so the tier needs one standing before it will take
	# anything. Which is the chain doing its job.
	sim.step([
		InputAction.build_machine(
			0, definitions.machine_index("miner_mk1"), sim.query_node_tile(0)
		)
	])
	sim.step([InputAction.deliver_to_nest(0)])
	assert_true(sim.query_delivery_is_complete(0), "the premise of the assertion above")
	return sim


func test_the_hud_carries_the_objective_line() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_true(view.hud_text().contains(Objective.line(sim, 0)), view.hud_text())
	view.free()


# ── A triaged HUD, and a Machine picker ──────────────────────────────────────
# Fifty-three appended lines drawn over the Factory they describe. `hud_text` is still the
# whole of what the HUD can say and the existing suite still asserts against it; what is
# *shown* is the brief, and the wall is behind a key.

func test_the_brief_hud_is_a_fraction_of_the_full_one() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var brief: int = view.hud_brief_text().split("\n").size()
	var full: int = view.hud_text().split("\n").size()
	assert_true(brief < full / 2, "brief %d lines against %d" % [brief, full])
	assert_true(brief > 0, "and it still says something")
	view.free()


func test_the_brief_hud_keeps_what_the_player_is_doing_and_what_is_coming() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var brief: String = view.hud_brief_text()
	assert_true(brief.contains(Objective.line(sim, 0)), "the objective: %s" % brief)
	assert_true(brief.contains("nest"), "what is at stake: %s" % brief)
	assert_true(brief.contains("power"), "the gauge a Factory is read off: %s" % brief)
	assert_true(brief.contains("build gun"), "what is in their hands: %s" % brief)
	view.free()


func test_the_rest_is_behind_a_key_and_the_key_says_so() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_false(view.hud_is_detailed(), "a Run opens on the brief")
	assert_eq(view.shown_hud_text(), view.hud_brief_text())
	assert_true(view.hud_brief_text().to_lower().contains("details"), "and names the key")

	view.set_hud_detailed(true)
	view.sync(sim)
	assert_true(view.hud_is_detailed())
	assert_eq(view.shown_hud_text(), view.hud_text(), "the whole wall, on request")
	view.free()


func test_a_machine_in_trouble_reaches_the_brief_even_so() -> void:
	# Triage is not silence. The whole reason the wall existed is that a player mid-Wave has
	# to know which Machine is in trouble; what was wrong was the forty lines around it.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("miner_mk1"), Vector3i(20, 0, 20)
		)
	])
	_run(sim, 2)
	view.sync(sim)
	assert_true(sim.query_machine_is_starved(0), "the premise")
	assert_true(view.hud_brief_text().contains("starved"), view.hud_brief_text())
	view.free()


func test_the_picker_has_a_cell_for_every_machine_and_one_for_the_belt() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_eq(
		view.machine_picker_cell_count(),
		sim.query_definitions().machine_count() + 1,
		"every Machine, and the Belt tool beside them"
	)
	view.free()


func test_a_picker_cell_says_what_it_is_what_it_costs_and_whether_it_is_locked() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	# A cell is a position in the chain since #53, not a Machine's index in a sorted table,
	# so this is how a test names the one it means.
	var definitions: Definitions = sim.query_definitions()
	var miner: int = BuildChain.cell_of(definitions, definitions.machine_index("miner_mk1"))
	assert_true(view.machine_picker_label(miner).contains("Miner Mk1"), view.machine_picker_label(miner))
	assert_true(view.machine_picker_label(miner).contains("8"), "the plate it costs")
	assert_false(view.machine_picker_is_locked(miner), "a Run opens able to build one")

	var deep: int = BuildChain.cell_of(definitions, definitions.machine_index("miner_mk2"))
	assert_true(view.machine_picker_is_locked(deep), "and unable to build this one")
	view.free()


func test_the_picker_marks_what_is_on_the_build_gun() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	var smelter: int = sim.query_definitions().machine_index("smelter_mk1")
	sim.step([InputAction.select_machine(0, smelter)])
	view.sync(sim)
	assert_eq(view.machine_picker_selected(), smelter)

	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	view.sync(sim)
	assert_eq(
		view.machine_picker_selected(),
		sim.query_definitions().machine_count(),
		"the Belt cell is the last one, and the Belt tool is what is in hand"
	)
	view.free()


func test_a_picker_cell_carries_the_icon_of_what_the_machine_makes() -> void:
	# The icons #20 generated and nothing used. A Machine's glyph is the Item it produces,
	# which is the thing a player is actually looking for when they go hunting for a
	# Smelter — and it means a new Machine gets a picture by having a Recipe rather than by
	# somebody drawing one.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var definitions: Definitions = sim.query_definitions()
	var miner: int = BuildChain.cell_of(definitions, definitions.machine_index("miner_mk1"))
	assert_true(
		view.machine_picker_icon_path(miner).contains("iron_ore"),
		"a Miner digs ore, so ore is its glyph: %s" % view.machine_picker_icon_path(miner)
	)
	# And since #59 the Smelter has one too, which is what makes the chain pictured end to
	# end. `tests/cases/test_item_icons.gd` is the general claim — every Item the Recipes
	# mention resolves an icon — and this is the one cell this test is already standing in
	# front of. A Machine whose output has *no* icon still reads by its name rather than by
	# a broken one, which is the rule a Machine with no generated body already obeys; that
	# case is the Turret's, asserted below.
	var smelter: int = BuildChain.cell_of(definitions, definitions.machine_index("smelter_mk1"))
	assert_true(
		view.machine_picker_icon_path(smelter).contains("iron_plate"),
		"a Smelter makes plate: %s" % view.machine_picker_icon_path(smelter)
	)
	view.free()


# ── Reaching a Machine with a key ─────────────────────────────────────────────
# The number row reads both ways and the hand decides which, exactly as the primary button
# does. With the Build Gun out it is the picker; with the weapon out it is the weapon and
# Gear-slot keys it always was.

func test_a_number_key_puts_that_machine_on_the_build_gun() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	# The number row is the picker with the Build Gun out and the weapon keys with it
	# holstered, and a Run opens holstered since #42 — so the hand this test is about
	# is asked for rather than assumed.
	sim.step([InputAction.set_build_mode(0, true)])
	var controller: PlayerController = PlayerController.new()
	var pressing: PlayerController.DeviceSample = PlayerController.DeviceSample.new()
	pressing.machine_picked = 3
	# The same keypress carries the weapon reading too, because the polling cannot know
	# which hand the player is in. This is the tick where that is decided.
	pressing.weapon_chosen = 0

	sim.step(controller.actions_for_tick(sim, 0, pressing))
	assert_eq(
		sim.query_player_selected_machine_index(0),
		BuildChain.order(sim.query_definitions())[3],
		"the fourth cell of the picker is what the fourth key reaches"
	)


func test_the_same_key_equips_a_weapon_with_the_weapon_out() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	sim.step([InputAction.set_build_mode(0, false)])
	var before: String = sim.query_player_selected_machine(0)

	var pressing: PlayerController.DeviceSample = PlayerController.DeviceSample.new()
	pressing.machine_picked = 3
	pressing.weapon_chosen = 0
	sim.step(controller.actions_for_tick(sim, 0, pressing))
	assert_eq(
		sim.query_player_selected_machine(0),
		before,
		"the Build Gun is holstered, so the number row is not its picker"
	)
	assert_eq(
		sim.query_player_weapon_index(0),
		sim.query_definitions().weapon_gear_index(0),
		"it equipped the first weapon frame instead"
	)


func test_a_number_key_past_the_end_of_the_machine_list_does_nothing() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	# The number row is the picker with the Build Gun out and the weapon keys with it
	# holstered, and a Run opens holstered since #42 — so the hand this test is about
	# is asked for rather than assumed.
	sim.step([InputAction.set_build_mode(0, true)])
	var controller: PlayerController = PlayerController.new()
	var before: String = sim.query_player_selected_machine(0)
	var pressing: PlayerController.DeviceSample = PlayerController.DeviceSample.new()
	pressing.machine_picked = PlayerController.PICK_KEY_COUNT - 1
	sim.step(controller.actions_for_tick(sim, 0, pressing))
	if sim.query_definitions().machine_count() <= PlayerController.PICK_KEY_COUNT - 1:
		assert_eq(sim.query_player_selected_machine(0), before, "nothing to select")
	else:
		assert_ne(sim.query_player_selected_machine(0), before, "the tenth Machine")


func test_the_number_row_is_the_one_thing_two_acts_share_and_it_shares_by_hand() -> void:
	# `test_no_two_actions_share_a_key` reads the key constants and would not see this,
	# because the picker does not have constants of its own: it reads the same `1`-`9` the
	# weapon and slot keys do, plus `0`. That sharing is deliberate and is the primary
	# button's arrangement — so it is asserted here rather than left to be noticed, and the
	# claim is the one that matters: in either hand, one press does exactly one thing.
	var sim: Simulation = Simulation.new(1, 1)
	# The number row is the picker with the Build Gun out and the weapon keys with it
	# holstered, and a Run opens holstered since #42 — so the hand this test is about
	# is asked for rather than assumed.
	sim.step([InputAction.set_build_mode(0, true)])
	var controller: PlayerController = PlayerController.new()
	var pressing: PlayerController.DeviceSample = PlayerController.DeviceSample.new()
	pressing.machine_picked = 0
	pressing.weapon_chosen = 0
	pressing.slot_cycled = 0

	var in_build: Array = controller.actions_for_tick(sim, 0, pressing)
	assert_eq(_count_of(in_build, InputAction.Kind.SELECT_MACHINE), 1)
	assert_eq(_count_of(in_build, InputAction.Kind.EQUIP_WEAPON), 0)
	assert_eq(_count_of(in_build, InputAction.Kind.FIT_COMPONENT), 0)

	sim.step([InputAction.set_build_mode(0, false)])
	var in_combat: Array = controller.actions_for_tick(sim, 0, pressing)
	assert_eq(_count_of(in_combat, InputAction.Kind.SELECT_MACHINE), 0)
	assert_eq(_count_of(in_combat, InputAction.Kind.EQUIP_WEAPON), 1)
	# Not the slot: a fresh Run has unlocked no components, and a ring with nothing in it
	# sends no intent at all. What matters here is that the *picker* did not fire.

	assert_true(
		PlayerController.KEY_HUD_DETAIL != PlayerController.KEY_PICK_TENTH,
		"and the two keys #36 did add are not each other"
	)


func test_the_wheel_turns_the_building_and_the_number_row_chooses_it() -> void:
	# A playtest asked for this in these words: "scrolling while in build mode should rotate
	# the building and not switch the currently hologrammed building". The wheel used to be
	# the Machine picker, which left rotation on the right mouse button and gave a player two
	# devices for the discrete act and one for the continuous one.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_mode(0, true)])
	var controller: PlayerController = PlayerController.new()
	var scrolling: PlayerController.DeviceSample = PlayerController.DeviceSample.new()
	scrolling.machine_steps = 1

	var chosen_before: String = sim.query_player_selected_machine(0)
	var turning: Array = controller.actions_for_tick(sim, 0, scrolling)
	assert_eq(_count_of(turning, InputAction.Kind.ROTATE_BUILD), 1, "the wheel turns it")
	assert_eq(_count_of(turning, InputAction.Kind.SELECT_MACHINE), 0, "and chooses nothing")

	sim.step(turning)
	assert_eq(
		sim.query_player_selected_machine(0),
		chosen_before,
		"the Machine on the gun is the one it was"
	)
	assert_eq(sim.query_player_build_rotation(0), 1, "and it has turned a quarter")


func test_the_wheel_reads_by_hand_so_scrolling_with_a_rifle_out_turns_nothing() -> void:
	# It reads by hand for the reason the number row does: a player holding a rifle has no
	# hologram to turn, so the only effect of the old reading was to silently re-point the
	# Build Gun they would draw next.
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	var scrolling: PlayerController.DeviceSample = PlayerController.DeviceSample.new()
	scrolling.machine_steps = 1

	assert_false(sim.query_player_is_in_build_mode(0), "a Run opens with the weapon out")
	var in_combat: Array = controller.actions_for_tick(sim, 0, scrolling)
	assert_eq(_count_of(in_combat, InputAction.Kind.ROTATE_BUILD), 0, "nothing turns")
	assert_eq(_count_of(in_combat, InputAction.Kind.SELECT_MACHINE), 0, "nothing is chosen")


func test_escape_holsters_the_build_gun_and_never_draws_it() -> void:
	# A playtest asked for it: "can pressing esc while in build mode exit build mode?".
	# Escape is one-way — it backs out of the thing you are doing, so it holsters and never
	# draws. `Main._input` owns the pointer half and reads the same mode, so one press
	# leaves build mode and a second gives the mouse back.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_mode(0, true)])
	var controller: PlayerController = PlayerController.new()
	var escaping: PlayerController.DeviceSample = PlayerController.DeviceSample.new()
	escaping.exit_build_pressed = true

	var leaving: Array = controller.actions_for_tick(sim, 0, escaping)
	assert_eq(_count_of(leaving, InputAction.Kind.SET_BUILD_MODE), 1, "it holsters")
	sim.step(leaving)
	assert_false(sim.query_player_is_in_build_mode(0), "and the Build Gun is away")

	# Pressed again with the weapon already out it sends nothing at all, rather than an
	# intent nobody needed sitting in a recorded script.
	var again: Array = controller.actions_for_tick(sim, 0, escaping)
	assert_eq(_count_of(again, InputAction.Kind.SET_BUILD_MODE), 0, "and never draws one")


func _count_of(actions: Array, kind: int) -> int:
	var found: int = 0
	for action: InputAction in actions:
		if action.kind == kind:
			found += 1
	return found


# ── A branch you can read ─────────────────────────────────────────────────────
# #46 made a Machine share its output between its Belts and #47 decided which Belts those
# are; neither drew a line of it. A fairly-shared Belt and a blocked one look identical from
# above, so back-pressure read as a bug. Three marks, and every one of them is a query asked
# every frame: a tag over a Machine that splits, a post at each branch, and a different post
# at the branch that cannot take its turn.

func _branching_view() -> Array:
	# A Miner with ore leaving by two faces, both Belts running onto open ground, so nothing
	# downstream can mask which of them is doing what. A Miner declares an output on every
	# face, which is what lets one Factory make this branch without turning anything.
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("miner_mk1"), Vector3i(0, 0, 0)
		),
		InputAction.build_belt(0, Vector3i(2, 0, 0), Vector3i(3, 0, 0)),
		InputAction.build_belt(0, Vector3i(2, 0, 1), Vector3i(3, 0, 1)),
	])
	return [sim, view]


func test_a_machine_with_one_belt_off_it_wears_no_split_tag() -> void:
	# The control. One Belt is an ordinary line and marking it would make the tag mean
	# "there is a Belt here", which is a thing a player can already see.
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("miner_mk1"), Vector3i(0, 0, 0)
		),
		InputAction.build_belt(0, Vector3i(2, 0, 0), Vector3i(6, 0, 0)),
	])
	view.sync(sim)
	assert_eq(sim.query_machine_branch_count(0), 1, "the Simulation calls it one Belt")
	assert_eq(view.split_marker_count(), 0, "so nothing says it split")
	assert_eq(view.branch_marker_count(), 0, "and neither Belt end is a branch post")
	view.free()


func test_a_machine_serving_two_belts_is_visibly_doing_so() -> void:
	var made: Array = _branching_view()
	var sim: Simulation = made[0]
	var view: WorldView = made[1]
	_run(sim, 120)
	view.sync(sim)
	assert_eq(view.split_marker_count(), 1, "one tag, over the Machine that splits")
	assert_eq(view.branch_marker_count(), 2, "and a post at each branch it feeds")
	assert_eq(view.blocked_branch_marker_count(), 0, "with neither of them blocked")
	view.free()


func test_a_branch_post_stands_at_the_belt_it_is_about() -> void:
	# The mark is where the thing it describes is, which is the rule the dangling post and
	# the starved tag already obey. A post at the Machine's own centre would say a split
	# exists and not which Belts are in it.
	var made: Array = _branching_view()
	var sim: Simulation = made[0]
	var view: WorldView = made[1]
	view.sync(sim)
	var north: Vector3 = view.branch_marker_position(0)
	var south: Vector3 = view.branch_marker_position(1)
	var first: FixedVec2 = sim.query_tile_centre_metres(Vector3i(2, 0, 0))
	assert_true(
		is_equal_approx(north.x, Fixed.to_float(first.x))
			and is_equal_approx(north.z, Fixed.to_float(first.z)),
		"the first post stands on the first branch's entry tile, got %v" % north
	)
	assert_true(south.z > north.z, "and the second on the other one's, got %v" % south)
	view.free()


func test_a_blocked_branch_is_marked_differently_from_a_sharing_one() -> void:
	# The thing a player has to act on, and the whole reason this is drawn: a Belt whose far
	# end will not take another Item is not taking its turn, and from above it looks exactly
	# like one that is. The Smelter here cannot keep up with the Miner, so that branch backs
	# up solid while the other goes on running.
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var view: WorldView = WorldView.new()
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), Vector3i(0, 0, 0)),
		# South off the Miner into an Ammo Press, which takes plate on that face and not ore —
		# the mistake a real player makes, and the one that produces a branch that is docked,
		# pointing the right way, and will never hand over a single Item.
		InputAction.build_belt(0, Vector3i(0, 0, 2), Vector3i(0, 0, 3)),
		InputAction.build_machine(
			0, definitions.machine_index("ammo_press_mk1"), Vector3i(0, 0, 4)
		),
		# East off the Miner onto open ground, which goes on taking its turn.
		InputAction.build_belt(0, Vector3i(2, 0, 0), Vector3i(8, 0, 0)),
	])
	assert_eq(sim.query_machine_branch_count(0), 2, "the Miner feeds two branches")

	_run(sim, 400)
	view.sync(sim)
	var refused: int = sim.query_belt_at_tile(Vector3i(0, 0, 2))
	assert_true(
		sim.query_belt_end_is_connected(refused),
		"that branch is docked against a declared input port, so it is not dangling"
	)
	assert_true(
		sim.query_belt_is_stalled(refused),
		"and it is backed up, because the Press will not take ore"
	)
	assert_eq(view.blocked_branch_marker_count(), 1, "exactly the blocked one is marked")
	assert_eq(view.branch_marker_count(), 1, "and the branch still running wears the other post")
	# The one dangling post belongs to the east branch, which really does pour onto the
	# ground. The blocked branch is not marked dangling, which is the distinction: it leads
	# somewhere and cannot get there, where a dangling end leads nowhere at all.
	assert_eq(view.dangling_marker_count(), 1, "the east branch pours onto open ground")
	assert_true(
		sim.query_belt_end_is_connected(refused),
		"and the blocked one does not, so the two complaints never land on one tile"
	)
	view.free()


func test_a_split_whose_branches_are_both_blocked_says_the_surplus_is_banking() -> void:
	# The third thing worth showing. Two stalled Belts off one Machine look like a Factory
	# that has lost its output; `query_machine_output_total` says it is in the Machine, whose
	# buffer is uncapped. A player with no reason to believe that would tear the line down.
	var made: Array = _branching_view()
	var sim: Simulation = made[0]
	var view: WorldView = made[1]
	_run(sim, 1800)
	view.sync(sim)
	assert_true(sim.query_belt_is_full(0), "both branches filled up")
	assert_true(sim.query_belt_is_full(1))
	assert_true(sim.query_machine_output_total(0) > 0, "and the Miner is holding the surplus")
	assert_eq(view.banking_marker_count(), 1, "which the tag over it says")
	assert_eq(view.split_marker_count(), 0, "in place of the plain split tag, not beside it")
	view.free()


func test_the_branch_marks_do_not_grow_the_scene_tree() -> void:
	var made: Array = _branching_view()
	var sim: Simulation = made[0]
	var view: WorldView = made[1]
	view.sync(sim)
	var nodes: int = view.get_child_count()
	for which: int in range(6):
		sim.step([
			InputAction.build_belt(
				0, Vector3i(20, 0, 20 + which * 2), Vector3i(26, 0, 20 + which * 2)
			)
		])
		_run(sim, 30)
		view.sync(sim)
	assert_eq(view.get_child_count(), nodes, "six more Belts, no new nodes")
	assert_eq(view.branch_marker_count(), 2, "and the branch is still the one Machine's two")
	view.free()


func test_the_brief_hud_says_a_branch_is_blocked_and_that_a_split_is_banking() -> void:
	# `hud_brief_text()` is what a player actually sees, and the test of a line in it is
	# whether it changes what they do in the next few seconds. "a branch is blocked" does: it
	# turns two Belts that look the same into one to go and look at. The counts come off the
	# marks rather than being recomputed, which is the arrangement the dangling-ends clause in
	# this very sentence already has — one decision about what a blocked branch is, not two.
	var made: Array = _branching_view()
	var sim: Simulation = made[0]
	var view: WorldView = made[1]
	_run(sim, 1800)
	view.sync(sim)
	assert_eq(view.banking_marker_count(), 1, "the split is banking its surplus")
	assert_true(
		view.hud_brief_text().contains("1 split banking"),
		"the brief HUD says so, got:\n%s" % view.hud_brief_text()
	)
	view.free()


func test_the_brief_hud_counts_a_blocked_branch() -> void:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var view: WorldView = WorldView.new()
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), Vector3i(0, 0, 0)),
		InputAction.build_belt(0, Vector3i(0, 0, 2), Vector3i(0, 0, 3)),
		InputAction.build_machine(
			0, definitions.machine_index("ammo_press_mk1"), Vector3i(0, 0, 4)
		),
		InputAction.build_belt(0, Vector3i(2, 0, 0), Vector3i(8, 0, 0)),
	])
	view.sync(sim)
	assert_true(
		not view.hud_brief_text().contains("branch"),
		"nothing is blocked yet, so nothing is said about a branch"
	)

	_run(sim, 400)
	view.sync(sim)
	assert_eq(view.blocked_branch_marker_count(), 1, "the ore branch is blocked at the Press")
	assert_true(
		view.hud_brief_text().contains("1 branch blocked"),
		"and the brief HUD counts it, got:\n%s" % view.hud_brief_text()
	)
	view.free()


# ── Being pointed at the ore ───────────────────────────────────────────────────
# #52, from a playtest: "I cant seem to find any ore in range for the miners." The first
# thing the game asks of a player is to walk 28 m to something they cannot see, in a
# direction nothing indicates. The line already goes quiet the moment a Miner is working
# ore, so the hint is a *rewording of the first step* rather than a step of its own —
# nothing remembered, nothing to skip, and no tutorial state anywhere.
#
# The bearing is relative to where the player is looking rather than to a compass, because
# this game has no compass and "north-east" is a word a player cannot act on.

func test_the_first_line_says_how_far_the_ore_is_and_which_way_to_turn() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var line: String = Objective.line(sim, 0)
	assert_true(line.contains("Miner"), line)
	assert_true(line.contains("iron ore"), "it names the Resource, not an item id: %s" % line)
	assert_true(line.contains(" m "), "and how far away it is: %s" % line)


func test_the_bearing_is_relative_to_where_the_player_is_looking() -> void:
	# A Map with one Node due east of the Nest, where a Run starts the player. Yaw 0 looks
	# down -z, so east is squarely to their right; a half turn puts it squarely to their
	# left, with nothing but the look having happened.
	var layout: MapLayout = MapLayout.empty()
	layout.nest_tile = Vector3i(0, 0, 0)
	layout.add_node(Vector3i(20, 0, 1), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)

	assert_true(
		Objective.line(sim, 0).contains("to your right"),
		"the ore is east and the player looks north: %s" % Objective.line(sim, 0)
	)
	# 2500 pixels is half a turn at the shipped sensitivity of 0.2 turns per thousand.
	sim.step([InputAction.look(0, Fixed.from_int(2500), 0)])
	assert_true(
		Objective.line(sim, 0).contains("to your left"),
		"and after a half turn it is to their left: %s" % Objective.line(sim, 0)
	)


func test_the_line_points_at_the_nearest_ore_a_run_could_actually_work() -> void:
	# A seam no unlocked Miner can lift is not somewhere to send a player, however close it
	# is: sending them there would be telling them to do the one thing that cannot be done.
	# `query_node_is_workable_now` is the Simulation's answer and this reads it rather than
	# working out its own.
	var layout: MapLayout = MapLayout.empty()
	layout.nest_tile = Vector3i(0, 0, 0)
	layout.add_node(Vector3i(0, 0, 4), "iron_ore", 3)
	layout.add_node(Vector3i(0, 0, 30), "coal", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var line: String = Objective.line(sim, 0)
	assert_true(line.contains("coal"), "the far coal is workable and the near seam is not: %s" % line)
	assert_false(line.contains("iron"), line)


func test_a_node_already_built_on_is_not_where_the_player_is_sent() -> void:
	# A Miner standing on ore it cannot work leaves the first step unmet, so the line is
	# still up — and pointing at the tile it is standing on would be pointing at ground
	# nothing can be placed on.
	var layout: MapLayout = MapLayout.empty()
	layout.nest_tile = Vector3i(0, 0, 0)
	layout.add_node(Vector3i(0, 0, 6), "coal", 1)
	layout.add_node(Vector3i(0, 0, 24), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	# An iron Miner over the coal: it reaches the Depth and mines the wrong thing, so
	# nothing is mining and the near Node is nonetheless occupied.
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("miner_mk1"), Vector3i(0, 0, 6)
		)
	])
	var line: String = Objective.line(sim, 0)
	assert_true(line.contains("Miner"), "the first step is still unmet: %s" % line)
	assert_true(line.contains("iron ore"), "and the free Node is the far one: %s" % line)


func test_the_hint_goes_quiet_the_moment_a_miner_is_working_ore() -> void:
	# Both halves of #52's second part: a player at the Nest is told which way to walk, and
	# the telling stops once they are mining. Nothing is remembered to make that happen —
	# it is the first step being met, which is how every other step here goes quiet.
	# Clear of the Nest, which stands on the origin of an empty layout and obstructs
	# building: a Miner refused is not a Miner working, and the first render of this test
	# was a refusal reading as a hint that would not go quiet.
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 12), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	assert_true(Objective.line(sim, 0).contains(" m "), Objective.line(sim, 0))
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("miner_mk1"), Vector3i(0, 0, 12)
		)
	])
	assert_false(
		Objective.line(sim, 0).contains(" m "),
		"a player who is mining is not told where ore is: %s" % Objective.line(sim, 0)
	)


func test_a_map_with_no_workable_ore_says_nothing_it_cannot_back_up() -> void:
	# A direction to nowhere is worse than no direction. With nothing a Run could work the
	# line falls back to naming the act, which is exactly what it said before #52.
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 3)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var line: String = Objective.line(sim, 0)
	assert_true(line.contains("Miner"), line)
	assert_false(line.contains(" m "), "there is no distance to quote: %s" % line)


# ── The hotbar states the chain ───────────────────────────────────────────────
# #53, from a playtest: "please simplify the hotbar right now so I am CRYSTAL clear about
# what chain of buildings to build". The cells #36 built were right and their *order* was
# sorted id order, which put the Ammo Press first and the Miner fourth — the chain backwards.
# The order now comes out of `BuildChain`, which reads it off the Recipes.

func test_the_hotbar_reads_left_to_right_as_the_chain_to_build() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var definitions: Definitions = sim.query_definitions()
	# The top row is the line, in the order it is built, on the keys 1 to 4.
	var line: PackedStringArray = PackedStringArray(
		["miner_mk1", "smelter_mk1", "ammo_press_mk1", "mg_turret_mk1"]
	)
	for step: int in range(line.size()):
		assert_eq(
			view.machine_picker_machine(step),
			definitions.machine_index(line[step]),
			"cell %d is %s" % [step, line[step]]
		)
		assert_eq(view.machine_picker_row(step), 0, "and it is on the main line")
		assert_eq(view.machine_picker_column(step), step, "one column per craft")
		assert_true(
			view.machine_picker_label(step).contains("[%d]" % (step + 1)),
			"on key %d: %s" % [step + 1, view.machine_picker_label(step)]
		)
	view.free()


func test_a_cell_says_what_the_machine_eats_as_well_as_what_it_makes() -> void:
	# #36 put the output Item's icon on a cell, which is half the information: a player
	# hunting for "the thing that turns ore into plate" needs the input too.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var definitions: Definitions = sim.query_definitions()

	var smelter: int = BuildChain.cell_of(definitions, definitions.machine_index("smelter_mk1"))
	assert_true(
		view.machine_picker_input_icon_path(smelter).contains("iron_ore"),
		"a Smelter eats ore: %s" % view.machine_picker_input_icon_path(smelter)
	)

	# A Miner's input is the ground, so there is nothing to draw on the left of it — the
	# honest state, and the one a Machine with no generated body already reads in.
	var miner: int = BuildChain.cell_of(definitions, definitions.machine_index("miner_mk1"))
	assert_eq(view.machine_picker_input_icon_path(miner), "", "the ground is not an Item")
	assert_true(view.machine_picker_icon_path(miner).contains("iron_ore"), "and it digs ore")

	# And a Machine whose product is not an Item reads by what it makes in words, because
	# there is no picture of damage. The case #36 already had to handle.
	var turret: int = BuildChain.cell_of(definitions, definitions.machine_index("mg_turret_mk1"))
	assert_eq(view.machine_picker_icon_path(turret), "", "no icon for damage")
	assert_true(
		view.machine_picker_label(turret).contains("damage"),
		"so it says so: %s" % view.machine_picker_label(turret)
	)
	var boiler: int = BuildChain.cell_of(definitions, definitions.machine_index("steam_boiler_mk1"))
	assert_true(
		view.machine_picker_label(boiler).contains("power"),
		"and a generator makes Power: %s" % view.machine_picker_label(boiler)
	)
	view.free()


func test_the_hotbar_marks_the_cell_the_objective_line_is_talking_about() -> void:
	# One fact drawn twice, from one authority. A hotbar that marked one Machine while the
	# line named another would be worse than a hotbar that marked nothing.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var definitions: Definitions = sim.query_definitions()
	var miner: int = BuildChain.cell_of(definitions, definitions.machine_index("miner_mk1"))
	assert_true(view.machine_picker_is_next(miner), "the first thing to build is marked")
	var turret: int = BuildChain.cell_of(definitions, definitions.machine_index("mg_turret_mk1"))
	assert_false(view.machine_picker_is_next(turret), "and the last thing is not")
	assert_eq(
		view.machine_picker_machine(view.machine_picker_next_cell()),
		Objective.pointed_at(sim, 0),
		"the marked cell is the one the line is about"
	)
	view.free()


func test_a_number_key_reaches_the_machine_whose_cell_carries_it() -> void:
	# The keys follow the chain now, so `1` is the Miner rather than the Ammo Press. The
	# controller and the hotbar read the same order, or a player presses 1 and gets the
	# thing printed on cell 3.
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	var view: WorldView = WorldView.new()
	view.sync(sim)
	sim.step([InputAction.set_build_mode(0, true)])
	for cell: int in range(4):
		var sample: PlayerController.DeviceSample = PlayerController.DeviceSample.new()
		sample.machine_picked = cell
		sim.step(controller.actions_for_tick(sim, 0, sample))
		assert_eq(
			sim.query_player_selected_machine_index(0),
			view.machine_picker_machine(cell),
			"key %s puts cell %d on the Build Gun" % [BuildChain.key_label(cell), cell]
		)
	view.free()


# ── Why a Belt will not dock, in words (#56) ──────────────────────────────────
# The docking rule has been the Simulation's since #47 and the arrows have been drawn since
# #36, so a player is both governed by the rule and shown it — and the *consequence* was
# still missing: a red post at the dangling end with nothing saying what would clear it.
# These assert the sentences, which is this layer's half. The reasons themselves are
# `test_declared_ports.gd`'s, because a `Refusal` is a fact and a sentence about it is
# presentation.

## A Smelter and a Steam Boiler on empty ground with a Belt at the wrong wall of each: the
## Smelter's northern face is where ore **arrives**, so a line leaving it is never loaded, and
## the Boiler's southern face declares no port at all. Two walls, two different answers, which
## is the whole of why there are two reasons.
func _view_of_two_belts_that_cannot_dock() -> Array:
	var sim: Simulation = Simulation.new(1, 1, null, MapLayout.empty())
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(
			0, definitions.machine_index("smelter_mk1"), Vector3i(4, 0, 0)
		),
		InputAction.build_machine(
			0, definitions.machine_index("steam_boiler_mk1"), Vector3i(10, 0, 0)
		),
	])
	sim.step([
		InputAction.build_belt(0, Vector3i(5, 0, -1), Vector3i(5, 0, -4)),
		InputAction.build_belt(0, Vector3i(11, 0, 5), Vector3i(11, 0, 2)),
	])
	var view: WorldView = WorldView.new()
	view.sync(sim)
	return [sim, view]


func test_the_hud_says_what_would_make_a_belt_at_a_machines_wall_connect() -> void:
	var pair: Array = _view_of_two_belts_that_cannot_dock()
	var sim: Simulation = pair[0]
	var view: WorldView = pair[1]
	assert_eq(sim.query_machine_count(), 2, "both Machines stood up")
	assert_eq(sim.query_belt_count(), 2, "and both lines laid, because this is advice")

	var hud: String = view.hud_brief_text()
	# Four, not two: each of these lines is unfed at its entry as well as refused at its far
	# end, which is exactly what a player who laid one gets. The count is read off the marks
	# rather than restated here, because that is the division of labour #36 settled — the mark
	# says where, the line says how many.
	assert_true(
		hud.contains("%d belt ends lead nowhere" % view.dangling_marker_count()),
		"the count is still where #36 put it: %s" % hud
	)
	assert_true(
		hud.contains(BuildGun.refusal_text(Simulation.Refusal.PORT_RUNS_THE_OTHER_WAY)),
		"and the wall that is a port pointing the wrong way says so: %s" % hud
	)
	assert_true(
		hud.contains(BuildGun.refusal_text(Simulation.Refusal.NO_PORT_ON_THAT_FACE)),
		"as does the wall that declares nothing at all: %s" % hud
	)
	view.free()


func test_the_two_sentences_name_different_fixes() -> void:
	# The distinction is the ticket. A wall with no port on it can be answered by turning the
	# Machine *or* by docking somewhere else, so both are offered; a wall whose port runs the
	# other way can only be answered by turning it, and "aim somewhere else" would be wrong
	# advice about the one face the player chose on purpose.
	var blank: String = BuildGun.refusal_text(Simulation.Refusal.NO_PORT_ON_THAT_FACE)
	var backwards: String = BuildGun.refusal_text(Simulation.Refusal.PORT_RUNS_THE_OTHER_WAY)
	assert_ne(blank, backwards, "two reasons, two sentences")
	assert_true(blank.contains("turn the Machine"), blank)
	assert_true(blank.contains("another face"), "and the second way out: %s" % blank)
	assert_true(backwards.contains("turn the Machine"), backwards)
	assert_false(
		backwards.contains("another face"),
		"which rotation alone fixes, so only rotation is offered: %s" % backwards
	)


func test_one_sentence_per_reason_rather_than_one_per_belt() -> void:
	# A Smelter stood square in an east-to-west line refuses **both** of its Belts for the
	# same reason, which is the shape of the mistake this exists for — and two identical
	# sentences would be the wall of text this HUD is trying to stop being.
	var sim: Simulation = Simulation.new(1, 1, null, MapLayout.empty())
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), Vector3i(4, 0, 0)
		)
	])
	sim.step([
		InputAction.build_belt(0, Vector3i(10, 0, 1), Vector3i(7, 0, 1)),
		InputAction.build_belt(0, Vector3i(3, 0, 1), Vector3i(0, 0, 1)),
	])
	var view: WorldView = WorldView.new()
	view.sync(sim)

	var sentence: String = BuildGun.refusal_text(Simulation.Refusal.PORT_RUNS_THE_OTHER_WAY)
	var hud: String = view.hud_brief_text()
	assert_true(hud.contains(sentence), "the reason is said: %s" % hud)
	assert_eq(hud.count(sentence), 1, "once, for two Belts that share it: %s" % hud)
	view.free()


func test_a_factory_whose_belts_all_dock_is_told_nothing_about_ports() -> void:
	# Silence is the default. A HUD that carried port advice about a working Factory would be
	# one more line to read on every frame of a Wave.
	var sim: Simulation = Simulation.new(1, 1, null, MapLayout.empty())
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), Vector3i(4, 0, 0)
		)
	])
	sim.step([InputAction.build_belt(0, Vector3i(5, 0, -4), Vector3i(5, 0, -1))])
	var view: WorldView = WorldView.new()
	view.sync(sim)

	assert_true(sim.query_belt_end_is_connected(0), "the line docks at the declared input")
	assert_false(
		view.hud_brief_text().contains("belt will not dock"),
		"so nothing is said: %s" % view.hud_brief_text()
	)
	view.free()


func test_the_route_line_says_it_before_the_drag_is_released() -> void:
	# The strongest version of the claim: no Belt exists, the button is still down, and the
	# HUD already names the fix. The anchor is four tiles east of the aim, so the route's
	# first run travels west and the wall behind its entry is the Smelter's western face —
	# which is where ore goes **in**, so nothing would ever load this line.
	var sim: Simulation = Simulation.new(1, 1, null, MapLayout.empty())
	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	var aimed: Vector3i = BuildGun.aimed_tile(sim, 0)
	var anchor: Vector3i = Vector3i(aimed.x + 4, aimed.y, aimed.z)
	sim.step([
		InputAction.build_machine(
			0,
			sim.query_definitions().machine_index("smelter_mk1"),
			Vector3i(aimed.x + 5, aimed.y, aimed.z)
		)
	])
	assert_eq(sim.query_machine_count(), 1, "the Smelter stood up beside the route")

	var view: WorldView = WorldView.new()
	view.note_belt_drag(true, anchor, BeltRoute.ALONG_X)
	view.sync(sim)
	assert_eq(sim.query_belt_count(), 0, "nothing has been laid")
	assert_true(
		view.hud_brief_text().contains(
			BuildGun.refusal_text(Simulation.Refusal.PORT_RUNS_THE_OTHER_WAY)
		),
		"and the reason is already on screen: %s" % view.hud_brief_text()
	)
	view.free()


func test_a_post_at_a_machines_wall_stands_clear_of_the_port_arrows_under_it() -> void:
	# #56's first render, as an assertion. #48 raised the *branch* post to 2.25 m because a
	# dock tile is where #36 draws a 3.2 m port arrow, and wrote that nothing else collided
	# with them "because a dangling end has no Machine behind it and therefore no arrow".
	# The end this whole section is about is exactly that end, and its hip-height post was a
	# small red cube half inside a 0.9 m conveyor deck among the arrows. So a post refused by
	# a wall gets the clearance #48 already measured, and one on open ground does not.
	var sim: Simulation = Simulation.new(1, 1, null, MapLayout.empty())
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), Vector3i(4, 0, 0)
		)
	])
	sim.step([
		# Into the Smelter's eastern wall, which gives plate out: refused, and standing on a
		# tile that carries a port arrow.
		InputAction.build_belt(0, Vector3i(10, 0, 1), Vector3i(7, 0, 1)),
		# And one on open ground, with nothing to clear.
		InputAction.build_belt(0, Vector3i(10, 0, 9), Vector3i(13, 0, 9)),
	])
	var view: WorldView = WorldView.new()
	view.sync(sim)

	assert_ne(
		sim.query_belt_end_dock_refusal(0),
		Simulation.Refusal.NONE,
		"the first line really is refused by a wall"
	)
	assert_eq(
		sim.query_belt_end_dock_refusal(1),
		Simulation.Refusal.NONE,
		"and the second really is pouring onto open ground"
	)

	var at_a_wall: float = -1.0
	var on_open_ground: float = -1.0
	for marker: int in range(view.dangling_marker_count()):
		var at: Vector3 = view.dangling_marker_position(marker)
		# The refused end of the first line is its last tile; the second line's far end is
		# the only mark out on the open ground to the east of it.
		if at.z < 4.0:
			at_a_wall = maxf(at_a_wall, at.y)
		else:
			on_open_ground = maxf(on_open_ground, at.y)

	assert_true(
		at_a_wall > on_open_ground,
		"a post at a wall stands above one on open ground: %f against %f"
			% [at_a_wall, on_open_ground]
	)
	assert_true(
		at_a_wall > Fixed.to_float(sim.query_belt_deck_height_metres())
			+ WorldView.PORT_MARKER_HEIGHT_METRES,
		"and clear of the port arrows lying at deck height: %f" % at_a_wall
	)
func test_a_run_opens_pointed_at_the_first_cell_of_the_chain() -> void:
	# #55, and the acceptance criterion for it: on tick 0 the hologram, the lit cell and the
	# objective line all name the same Machine. #53 got the hotbar into chain order and left
	# the Build Gun on index 0 of the *sorted* table, which is `ammo_press_mk1` — so a Run
	# opened with the hotbar saying build a Miner, the line saying press 1, and an Ammo Press
	# hologram in front of the player.
	#
	# **Nothing in `sim/` learnt what a chain is.** The agreement is `player.starting_machine`
	# naming an id and `BuildChain` deriving the order off the Recipes; this test is the only
	# place the two are put side by side, because it is the only place they *can* be — the
	# Simulation has no opinion about cell 0 and must not grow one.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_mode(0, true)])
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var definitions: Definitions = sim.query_definitions()

	# `machine_picker_selected` is a *Machine index* — the Build Gun's own selection space —
	# where `machine_picker_next_cell` is a *cell*. Asymmetric, and the asymmetry is the
	# whole subject: the two spaces are exactly what #53 left disagreeing, so the assertion
	# has to cross between them rather than compare two numbers that look alike.
	assert_eq(
		BuildChain.cell_of(definitions, view.machine_picker_selected()),
		0,
		"the Build Gun is on the first cell of the chain, not the first row by id"
	)
	assert_eq(
		view.machine_picker_next_cell(),
		0,
		"which is also the cell the objective line is about"
	)
	assert_eq(
		sim.query_player_selected_machine_index(0),
		view.machine_picker_machine(0),
		"and the hologram is that cell's Machine"
	)
	assert_eq(
		definitions.machine_at(view.machine_picker_machine(0)).role,
		MachineDefinition.Role.MINER,
		"a Run starts by digging, which is what the line says to do"
	)
	assert_true(
		Objective.line(sim, 0).contains(BuildChain.key_label(0)),
		"the line names the key the cell carries: %s" % Objective.line(sim, 0)
	)
	assert_true(view.hologram_is_visible(), "and it is in front of the player")
	view.free()


# ── The step that pays for the Run, and the act it names ──────────────────────
# **#71, and the report is the strongest kind there is: a player read the line, did what it
# said, and was stuck anyway.** *"its not clear how to carry ingots to the nest... the
# smelter works but idk what next"*. The line said `Carry ingots to the Nest and press F`,
# and **there is no way to carry ingots** — the only two hand transfers in the Simulation are
# `_apply_deliver_to_nest`, which spends out of a player's own pockets, and
# `_apply_withdraw_from_nest`, which fills them from the Nest's store. Nothing moves goods
# out of a Machine's output buffer into a player's hands, so the only way a plate leaves a
# Smelter is a Belt.
#
# And it was wrong about the goods as well as the verb, which is the half the report could
# not see: `t01_munitions` wants **coal**, so `F` at the Nest with a pocketful of plate is
# refused `NOTHING_TO_DELIVER` and does nothing at all. A player who followed the line
# exactly was told to perform an impossible act in aid of the wrong Item.

## A Map and a Factory at the step the report was stuck on: something mining, something
## crafting, a Belt between them, and nothing yet carrying anything to the Nest.
##
## Compact rather than the shipped Map, which is `test_nest_store`'s precedent and for its
## reason: the starter Map's Nodes are far enough apart that joining them up is a lesson in
## Belt routing rather than a statement about the objective line. The content is the shipped
## content, because the whole point of the assertions below is what the shipped Delivery
## chain actually asks for.
func _at_the_step_that_pays_for_the_run() -> Simulation:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.add_node(Vector3i(0, 0, -6), "coal", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var definitions: Definitions = sim.query_definitions()
	sim.step([InputAction.set_build_mode(0, true)])
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), Vector3i(0, 0, 0))
	])
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("smelter_mk1"), Vector3i(0, 0, 5))
	])
	sim.step([InputAction.build_belt(0, Vector3i(1, 0, 2), Vector3i(1, 0, 4))])
	_run(sim, 300)
	return sim


func test_the_line_never_tells_a_player_to_carry_goods_out_of_a_machine() -> void:
	var sim: Simulation = _at_the_step_that_pays_for_the_run()
	var line: String = Objective.line(sim, 0)
	assert_false(
		line.to_lower().contains("carry"),
		"there is no intent anywhere that moves goods out of a Machine: %s" % line
	)
	assert_false(
		line.to_lower().contains("ingot"),
		"and the open tier does not want ingots at all: %s" % line
	)


func test_the_step_that_pays_for_the_run_names_what_the_nest_actually_wants() -> void:
	# Read off `query_delivery_goods` rather than written down, so the line cannot name one
	# Item while the counter waits for another — which is exactly what it did.
	var sim: Simulation = _at_the_step_that_pays_for_the_run()
	var line: String = Objective.line(sim, 0)
	assert_true(line.contains("coal"), "the shipped chain opens on twenty coal: %s" % line)
	assert_true(line.contains("20"), "and how much of it: %s" % line)


func test_making_what_the_nest_wants_comes_before_the_belt_that_carries_it() -> void:
	# Nothing on this Map makes coal yet, so a line about a Belt would be a line about a Belt
	# out of nowhere. The act is to build the Machine that makes it, and the cell the hotbar
	# marks is that Machine's — one `_step`, drawn twice (#53).
	var sim: Simulation = _at_the_step_that_pays_for_the_run()
	var definitions: Definitions = sim.query_definitions()
	assert_eq(
		Objective.pointed_at(sim, 0),
		definitions.machine_index("coal_miner_mk1"),
		Objective.line(sim, 0)
	)
	assert_true(Objective.line(sim, 0).contains("key 5"), Objective.line(sim, 0))


func test_once_something_makes_it_the_step_is_the_belt_into_the_nest() -> void:
	var sim: Simulation = _at_the_step_that_pays_for_the_run()
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(
			0, definitions.machine_index("coal_miner_mk1"), Vector3i(0, 0, -6)
		)
	])
	_run(sim, 200)
	var line: String = Objective.line(sim, 0)
	assert_true(line.contains("Belt"), line)
	assert_true(line.contains("Nest"), line)
	# The Nest is deliberately not port-enforced (#47) — it is not a Machine, so a Belt docks
	# anywhere on its 4x4 wall. Sending a player looking for an arrow on it would be sending
	# them after a mark that is not drawn.
	assert_false(
		line.contains("blue"), "there is no input arrow on the Nest to aim at: %s" % line
	)
	assert_eq(
		Objective.pointed_at(sim, 0),
		definitions.machine_count(),
		"and the cell is the Belt tool's, past the end of the Machine list"
	)


func test_the_step_stops_asking_for_a_belt_once_one_lands_in_the_nest() -> void:
	# #67's defect, which is the one this step is most exposed to: the tier takes thirty
	# seconds to fill, and a line still saying "run a Belt into the Nest" for all of it is an
	# instruction to do a thing already done.
	var sim: Simulation = _at_the_step_that_pays_for_the_run()
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(
			0, definitions.machine_index("coal_miner_mk1"), Vector3i(0, 0, -6)
		)
	])
	sim.step([InputAction.build_belt(0, Vector3i(-1, 0, -6), Vector3i(-2, 0, -6))])
	_run(sim, 60)
	assert_true(
		sim.query_belt_ends_at_the_nest(1),
		"the premise: the second Belt runs into the Nest's wall"
	)
	assert_eq(
		Objective.line(sim, 0), "", "the opening has taught itself: %s" % Objective.line(sim, 0)
	)


func test_asking_whether_a_belt_feeds_the_nest_leaves_the_run_where_it_was() -> void:
	var sim: Simulation = _at_the_step_that_pays_for_the_run()
	var before: int = sim.hash()
	for index: int in range(sim.query_belt_count()):
		sim.query_belt_ends_at_the_nest(index)
	assert_eq(sim.hash(), before, "a projection the Simulation never reads back")


# ── The starved step is about a Machine nothing feeds (#74) ───────────────────
# `query_machine_is_starved` is "does not hold a whole Recipe's worth right now", which is
# the right answer to the Simulation's question — it is what the grid bills against and what
# the amber tag means — and the wrong answer to this one. A correctly belted opening line is
# saturated and still briefly short between consuming one craft's ore and holding the next,
# so the step used to alternate with the step underneath it and tell a player to apply a fix
# they had already applied. It now fires for a Machine that is starved **and** has nothing
# docked into a declared input port, which is the population the sentence is about.

## The opening line as a player who did it right would leave it: something mining, a Belt,
## something crafting, and nothing wrong with any of it. Deliberately *not* settled onto a
## tick where nothing happens to be starved — standing on a chosen tick is how the defect
## survived, so the fixture hands back a Run that is mid-cycle like any other.
func _a_working_opening_line() -> Simulation:
	return _at_the_step_that_pays_for_the_run()


func test_a_line_that_is_working_is_never_reported_as_starved() -> void:
	# Over a window rather than at one tick, because the defect was intermittent: the
	# Smelter's cycle is 3.2 s and the Miner's 1.5 s, so any single tick is a coin toss and
	# a single-tick assertion is exactly what let this ship.
	var sim: Simulation = _a_working_opening_line()
	var offending: int = -1
	var said: String = ""
	for tick: int in range(600):
		var line: String = Objective.line(sim, 0)
		if line.to_lower().contains("starved"):
			offending = tick
			said = line
			break
		sim.step([])
	assert_eq(
		offending, -1, "ten seconds in, on a Factory that works: %s" % said
	)


func test_a_miner_on_bare_rock_is_still_reported_as_starved() -> void:
	# The case the step earns its place for, and the one any reading that merely required a
	# missing Belt would have broken: a Miner's input is the ground, so it declares no input
	# port at all and can never be fed. One on bare rock is starved for ever.
	var sim: Simulation = _a_working_opening_line()
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), Vector3i(8, 0, 8))
	])
	var placed: int = sim.query_machine_at_tile(Vector3i(8, 0, 8))
	assert_true(placed != -1, "the premise: a second Miner stands on bare rock")
	assert_true(sim.query_machine_is_starved(placed), "and it is starved")
	assert_false(sim.query_machine_is_fed(placed), "and nothing feeds it, nor ever could")
	assert_true(
		Objective.line(sim, 0).to_lower().contains("starved"), Objective.line(sim, 0)
	)


func test_a_miner_over_the_wrong_resource_is_still_reported_as_starved() -> void:
	# #52's distinction, which this step has to keep: covering a Node is not working one. An
	# iron Miner over the coal seam covers a Node, accumulates nothing, and is exactly as
	# stuck as one on bare rock — so the line has to say so.
	var sim: Simulation = _a_working_opening_line()
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), Vector3i(0, 0, -6))
	])
	var placed: int = sim.query_machine_at_tile(Vector3i(0, 0, -6))
	assert_true(placed != -1, "the premise: an iron Miner stands over the coal")
	assert_true(sim.query_machine_is_starved(placed), "it covers a Node and mines nothing")
	assert_true(
		Objective.line(sim, 0).to_lower().contains("starved"), Objective.line(sim, 0)
	)


func test_a_crafter_with_no_belt_into_it_is_still_reported_as_starved() -> void:
	var sim: Simulation = _a_working_opening_line()
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("smelter_mk1"), Vector3i(8, 0, 8))
	])
	var placed: int = sim.query_machine_at_tile(Vector3i(8, 0, 8))
	assert_true(placed != -1, "the premise: a second Smelter stands with nothing coming in")
	assert_false(sim.query_machine_is_fed(placed), "and no Belt docks into it")
	assert_true(
		Objective.line(sim, 0).to_lower().contains("starved"), Objective.line(sim, 0)
	)


func test_taking_the_belt_out_from_under_a_crafter_brings_the_step_back() -> void:
	# `Objective` is a pure function of the Run's state and stays one: nothing is remembered
	# about having passed this step, so it comes back the moment the feed goes.
	#
	# A second line is standing while the first is cut, and that is the premise rather than
	# decoration: `Step.BELT` is walked ahead of this one and asks for a Belt whenever *no*
	# Belt is both fed and landing somewhere, which on a one-line Factory is the better
	# answer anyway. What this is about is a Factory with Belts in it, one of whose Machines
	# has had its own feed taken away.
	var sim: Simulation = _a_working_opening_line()
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(
			0, definitions.machine_index("coal_miner_mk1"), Vector3i(0, 0, -6)
		)
	])
	sim.step([InputAction.build_belt(0, Vector3i(-1, 0, -6), Vector3i(-2, 0, -6))])
	_run(sim, 60)
	assert_true(sim.query_belt_ends_at_the_nest(1), "the premise: a second line is working")
	assert_false(
		Objective.line(sim, 0).to_lower().contains("starved"),
		"and nothing is complained about: %s" % Objective.line(sim, 0)
	)

	var smelter: int = sim.query_machine_at_tile(Vector3i(0, 0, 5))
	sim.step([InputAction.demolish(0, Vector3i(1, 0, 2))])
	assert_eq(sim.query_belt_count(), 1, "the ore line is gone and the coal line is not")
	# The Smelter has to be given time to spend what it was holding when the Belt went; what
	# is asserted is that the step returns, not how many ticks of buffer it had.
	_run(sim, 400)
	assert_true(sim.query_machine_is_starved(smelter), "the Smelter has run out")
	assert_false(sim.query_machine_is_fed(smelter), "and nothing docks into it any more")
	assert_true(
		Objective.line(sim, 0).to_lower().contains("starved"), Objective.line(sim, 0)
	)
