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


func test_a_port_marker_stands_on_the_tile_a_belt_would_dock_at() -> void:
	# The Smelter is 3x3 and its ingot output is the middle of the south edge, which is tile
	# (13, 14) of a body anchored at (12, 12). The marker goes on the tile *past* it — (13,
	# 15), spanning 26 m to 28 m on x and 30 m to 32 m on z, centre (27, 31) — because a
	# marker on the port tile is a marker inside the Machine, which a render showed
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
	assert_true(is_equal_approx(at.x, 27.0), "expected x 27.0, got %f" % at.x)
	assert_true(is_equal_approx(at.z, 31.0), "expected z 31.0, got %f" % at.z)
	view.free()


func test_turning_the_machine_moves_its_markers_with_it() -> void:
	# A half turn puts the south face north: the ingot port goes from local (1, 2) to
	# (1, 0), which for an anchor at (12, 12) is tile (13, 12), and the tile a Belt would
	# dock at is (13, 11) — centre (27, 23).
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
	assert_true(is_equal_approx(at.z, 23.0), "expected z 23.0, got %f" % at.z)
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


# ── The one objective line ────────────────────────────────────────────────────
# A Run opens on bare ground with 80 plate and no idea what to do. The line is a pure
# function of the Run's state, so there is nothing to enter, nothing to skip, and it comes
# back if the thing it was about stops being true.

func test_a_fresh_run_is_told_to_put_a_miner_on_a_node() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_true(Objective.line(sim).contains("Miner"), Objective.line(sim))
	assert_true(Objective.line(sim).contains("node"), "and where to put it")


func test_a_miner_on_bare_rock_has_not_done_the_first_thing() -> void:
	# Telling a player they have done a step they have not is worse than saying nothing: a
	# Miner off its Node banks no progress at all, and the line has to agree with that.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("miner_mk1"), Vector3i(20, 0, 20)
		)
	])
	assert_true(Objective.line(sim).contains("Miner"), Objective.line(sim))


func test_the_line_moves_on_as_the_opening_line_gets_built() -> void:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var definitions: Definitions = sim.query_definitions()

	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), Vector3i(0, 0, 0))
	])
	assert_true(Objective.line(sim).contains("Smelter"), Objective.line(sim))

	sim.step([
		InputAction.build_machine(0, definitions.machine_index("smelter_mk1"), Vector3i(0, 0, 5))
	])
	assert_true(Objective.line(sim).contains("Belt"), Objective.line(sim))

	sim.step([InputAction.build_belt(0, Vector3i(1, 0, 2), Vector3i(1, 0, 4))])
	assert_false(
		Objective.line(sim).contains("Belt tool"),
		"the Belt is fed at one end and lands at the other: %s" % Objective.line(sim)
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
		Objective.line(sim).contains("Belt tool"),
		"a Belt nothing feeds taught the player nothing: %s" % Objective.line(sim)
	)


func test_the_line_goes_away_once_a_delivery_has_been_made() -> void:
	# The loop has closed at least once: mined, crafted, moved and been paid for it. A hint
	# line at the top of the screen after that is a hint line in the way.
	var sim: Simulation = Simulation.new(1, 1)
	assert_ne(Objective.line(sim), "", "there is something to say at the start")
	var stocked: Simulation = _run_with_a_tier_completed()
	assert_eq(Objective.line(stocked), "", "and nothing to say once a tier has landed")


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
	assert_true(view.hud_text().contains(Objective.line(sim)), view.hud_text())
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
	assert_true(brief.contains(Objective.line(sim)), "the objective: %s" % brief)
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
	var miner: int = sim.query_definitions().machine_index("miner_mk1")
	assert_true(view.machine_picker_label(miner).contains("Miner Mk1"), view.machine_picker_label(miner))
	assert_true(view.machine_picker_label(miner).contains("8"), "the plate it costs")
	assert_false(view.machine_picker_is_locked(miner), "a Run opens able to build one")

	var deep: int = sim.query_definitions().machine_index("miner_mk2")
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
	var miner: int = sim.query_definitions().machine_index("miner_mk1")
	assert_true(
		view.machine_picker_icon_path(miner).contains("iron_ore"),
		"a Miner digs ore, so ore is its glyph: %s" % view.machine_picker_icon_path(miner)
	)
	# #20 generated ten icons and the content has grown Items since — `iron_plate` is one
	# with no picture. A Machine whose output has no icon reads by its name rather than by a
	# broken one, which is the rule a Machine with no generated body already obeys.
	var smelter: int = sim.query_definitions().machine_index("smelter_mk1")
	assert_eq(view.machine_picker_icon_path(smelter), "", "no iron_plate icon exists yet")
	view.free()


# ── Reaching a Machine with a key ─────────────────────────────────────────────
# The number row reads both ways and the hand decides which, exactly as the primary button
# does. With the Build Gun out it is the picker; with the weapon out it is the weapon and
# Gear-slot keys it always was.

func test_a_number_key_puts_that_machine_on_the_build_gun() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var controller: PlayerController = PlayerController.new()
	var pressing: PlayerController.DeviceSample = PlayerController.DeviceSample.new()
	pressing.machine_picked = 3
	# The same keypress carries the weapon reading too, because the polling cannot know
	# which hand the player is in. This is the tick where that is decided.
	pressing.weapon_chosen = 0

	sim.step(controller.actions_for_tick(sim, 0, pressing))
	assert_eq(
		sim.query_player_selected_machine_index(0),
		3,
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


func _count_of(actions: Array, kind: int) -> int:
	var found: int = 0
	for action: InputAction in actions:
		if action.kind == kind:
			found += 1
	return found
