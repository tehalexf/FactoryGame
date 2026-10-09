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
	# A Smelter is 3x3 and declares whole faces: ore along the north, coal along the west,
	# ingot along the south and the east. Whole faces rather than one tile each, because #47
	# made the declaration the rule and a Machine with one declared output could not branch —
	# see `content/machine_ports.csv`.
	assert_eq(view.input_port_marker_count() - held_in, 6, "ore and coal go in, three tiles each")
	assert_eq(view.output_port_marker_count() - held_out, 6, "ingot comes out of two faces")
	view.free()


func test_a_port_marker_stands_on_the_tile_a_belt_would_dock_at() -> void:
	# The Smelter is 3x3 and the first ingot output declared is the near end of its south edge,
	# which is tile (12, 14) of a body anchored at (12, 12). The marker goes on the tile *past*
	# it — (12, 15), spanning 24 m to 26 m on x and 30 m to 32 m on z, centre (25, 31) — because
	# a marker on the port tile is a marker inside the Machine, which a render showed
	# immediately, and because the tile outside is where the Belt actually goes.
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
	assert_true(is_equal_approx(at.x, 25.0), "expected x 25.0, got %f" % at.x)
	assert_true(is_equal_approx(at.z, 31.0), "expected z 31.0, got %f" % at.z)
	view.free()


func test_turning_the_machine_moves_its_markers_with_it() -> void:
	# A half turn puts the south face north: the first ingot port goes from local (0, 2) to
	# (2, 0), which for an anchor at (12, 12) is tile (14, 12), and the tile a Belt would
	# dock at is (14, 11) — centre (29, 23).
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), Vector3i(12, 0, 12), 2
		)
	])
	view.sync(sim)
	var at: Vector3 = view.output_port_marker_position(0)
	assert_true(is_equal_approx(at.x, 29.0), "expected x 29.0, got %f" % at.x)
	assert_true(is_equal_approx(at.z, 23.0), "expected z 23.0, got %f" % at.z)
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
	var tuning: String = FileAccess.get_file_as_string("res://content/tuning.toml").replace(
		"delivery_reach_metres = 5", "delivery_reach_metres = 80"
	)
	var definitions: Definitions = Definitions.parse(
		FileAccess.get_file_as_string("res://content/machines.csv"),
		FileAccess.get_file_as_string("res://content/recipes.csv"),
		tuning,
		FileAccess.get_file_as_string("res://content/waves.csv"),
		deliveries,
		FileAccess.get_file_as_string("res://content/gear.csv"),
		FileAccess.get_file_as_string("res://content/stratagems.csv")
	)
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
	# #20 generated ten icons and the content has grown Items since — `iron_plate` is one
	# with no picture. A Machine whose output has no icon reads by its name rather than by a
	# broken one, which is the rule a Machine with no generated body already obeys.
	var smelter: int = BuildChain.cell_of(definitions, definitions.machine_index("smelter_mk1"))
	assert_eq(view.machine_picker_icon_path(smelter), "", "no iron_plate icon exists yet")
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
