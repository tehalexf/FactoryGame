## Smoke coverage for the rendering layer.
##
## The spec gives the Godot layer smoke-level coverage only, and that is all these
## are: the view draws one placeholder per thing the Simulation reports, reports the
## count a player is meant to read off the screen, and holds no state of its own. The
## numbers it shows are asserted against the queries, never against a remembered
## copy — a copy is the thing this layer is forbidden to have.
extends TestCase


func _run(sim: Simulation, ticks: int) -> void:
	for tick: int in range(ticks):
		sim.step([])


func test_the_view_draws_a_placeholder_for_every_node_and_machine() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()

	view.sync(sim)
	assert_eq(
		view.placeholder_count(),
		sim.query_node_count(),
		"a fresh Run has Nodes to look at and no Machines"
	)

	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("miner_mk1"), sim.query_node_tile(0)
		)
	])
	view.sync(sim)
	assert_eq(view.placeholder_count(), sim.query_node_count() + 1)

	view.free()


func test_a_placeholder_stands_at_the_centre_of_its_footprint() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	# A 2x2 Miner anchored at tile (4,0,4) spans 8 m to 12 m on both axes, so its
	# centre is (10 m, 10 m).
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("miner_mk1"), Vector3i(4, 0, 4)
		)
	])
	view.sync(sim)
	var placed: Vector3 = view.machine_placeholder_position(0)
	assert_true(is_equal_approx(placed.x, 10.0), "expected x 10.0, got %f" % placed.x)
	assert_true(is_equal_approx(placed.z, 10.0), "expected z 10.0, got %f" % placed.z)
	view.free()


func test_the_view_shows_what_the_factory_has_extracted() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("miner_mk1"), sim.query_node_tile(0)
		)
	])
	# 1.5 s a craft at 60 ticks a second is 90 ticks an ore; two crafts is 180.
	_run(sim, 180)
	view.sync(sim)
	assert_eq(sim.query_item_total("iron_ore"), 2, "the premise of the assertion below")
	assert_true(
		view.hud_text().contains("iron_ore 2"),
		"a player must be able to read the count off the screen, got %s" % view.hud_text()
	)
	view.free()


func test_a_run_opens_with_an_empty_factory_for_the_player_to_build() -> void:
	# The opening Miner, Belt and Smelter are gone. They existed so #4 and #5 had
	# something to look at while nothing could build; a player now builds it themselves.
	var main: Main = Main.new()
	main.advance_frame(1.0 / float(Simulation.TICKS_PER_SECOND))
	var sim: Simulation = main.simulation()
	assert_eq(sim.query_machine_count(), 0, "nothing is built for the player")
	assert_eq(sim.query_belt_count(), 0)
	assert_true(sim.query_node_count() > 0, "but there are Nodes to build a Factory on")
	main.free()


func test_a_run_opens_with_materials_in_hand_so_the_build_gun_works_at_all() -> void:
	var main: Main = Main.new()
	var sim: Simulation = main.simulation()
	assert_true(
		sim.query_player_item(0, "iron_plate") > 0,
		"a Run has to open with enough to build the first Miner"
	)
	main.free()


# ── The camera ────────────────────────────────────────────────────────────────
# The camera goes where the Simulation says a player's camera goes. There is no camera
# controller on this side and nothing is remembered between frames.

func test_the_camera_stands_at_eye_height_over_the_player() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)

	var height: float = Fixed.to_float(sim.query_player_camera_height_metres(0))
	assert_true(
		is_equal_approx(view.camera_position().y, height),
		"expected %f, got %f" % [height, view.camera_position().y]
	)
	assert_true(
		is_equal_approx(view.camera_position().x, Fixed.to_float(sim.query_player_position(0).x)),
		"and directly over the player"
	)
	view.free()


func test_the_camera_follows_the_player_as_they_walk() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	for tick: int in range(30):
		sim.step([InputAction.move(0, Fixed.ONE, 0)])
	view.sync(sim)
	assert_true(
		is_equal_approx(view.camera_position().z, Fixed.to_float(sim.query_player_position(0).z)),
		"the camera is told where to be, it does not decide"
	)
	view.free()


func test_the_camera_turns_with_the_yaw_the_simulation_holds() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	# 1250 pixels left is a quarter turn at the shipped 0.2 turns per 1000 pixels.
	sim.step([InputAction.look(0, Fixed.from_int(-1250), 0)])
	view.sync(sim)
	# A quarter turn of yaw is a quarter of TAU in radians.
	assert_true(
		is_equal_approx(view.camera_rotation().y, TAU * 0.25),
		"expected %f, got %f" % [TAU * 0.25, view.camera_rotation().y]
	)
	view.free()


func test_the_camera_rises_and_tilts_down_in_survey_view() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var on_foot: float = view.camera_position().y

	for tick: int in range(30):
		sim.step([InputAction.survey_view(0, true)])
	view.sync(sim)

	assert_true(
		view.camera_position().y > on_foot + 10.0,
		"expected the camera well above eye level, got %f" % view.camera_position().y
	)
	assert_true(
		view.camera_rotation().x < -0.5,
		"and tilted down, got %f radians" % view.camera_rotation().x
	)
	view.free()


# ── The Build Gun hologram ────────────────────────────────────────────────────

func test_the_hologram_stands_on_the_tile_the_build_gun_is_aimed_at() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)

	var aimed: Vector3i = BuildGun.aimed_tile(sim, 0)
	var centre: FixedVec2 = sim.query_tile_centre_metres(aimed)
	# The selected Machine is 2x2, so its centre is one tile past the anchor's centre.
	assert_true(
		view.hologram_position().x >= Fixed.to_float(centre.x),
		"the hologram covers the aimed tile, got x %f" % view.hologram_position().x
	)
	assert_true(
		absf(view.hologram_position().z - Fixed.to_float(centre.z)) <= 4.0,
		"and sits on it rather than somewhere else entirely"
	)
	view.free()


func test_the_hologram_is_green_on_clear_ground_and_red_on_a_machine() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_false(view.hologram_is_refused(), "clear ground ahead of a fresh Run")

	# Fill the aimed tile, then look again at the same place.
	var aimed: Vector3i = BuildGun.aimed_tile(sim, 0)
	sim.step([
		InputAction.build_machine(0, sim.query_definitions().machine_index("miner_mk1"), aimed)
	])
	view.sync(sim)
	assert_true(view.hologram_is_refused(), "aiming at a Miner must read as refused")
	view.free()


func test_a_refusal_is_shown_as_a_reason_and_not_only_as_a_colour() -> void:
	# The acceptance criterion: refused *with a visible reason*, not silently.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	var aimed: Vector3i = BuildGun.aimed_tile(sim, 0)
	sim.step([
		InputAction.build_machine(0, sim.query_definitions().machine_index("miner_mk1"), aimed)
	])
	view.sync(sim)
	assert_true(
		view.hud_text().contains("already standing"),
		"the HUD must say why, got %s" % view.hud_text()
	)
	view.free()


func test_the_hud_names_what_is_on_the_build_gun_and_what_is_in_hand() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_true(
		view.hud_text().contains("build gun: %s" % sim.query_definitions().machine_ids()[0]),
		view.hud_text()
	)
	assert_true(view.hud_text().contains("iron_plate"), view.hud_text())
	view.free()


func test_a_turned_machine_is_drawn_over_the_ground_it_covers() -> void:
	# A 3x3 Smelter is square, so the shipped content cannot show this on a Machine.
	# What it can show is that the box is sized from the *turned* footprint query rather
	# than from the file's two columns, which is the same code path either way.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), Vector3i(10, 0, 10), 1
		)
	])
	view.sync(sim)
	assert_eq(sim.query_machine_footprint(0), Vector2i(3, 3), "the premise of the assertion below")
	# 3x3 tiles from (10,10) spans 20 m to 26 m, so its centre is 23 m on both axes.
	assert_true(
		is_equal_approx(view.machine_placeholder_position(0).x, 23.0),
		"expected 23.0, got %f" % view.machine_placeholder_position(0).x
	)
	view.free()


# ── Belts and the Items on them ───────────────────────────────────────────────
# Items are derived Simulation state and never nodes (ADR 0002), so the view draws them
# as instances of one mesh and reads every position out of a query on the frame it
# draws. The assertions below are about exactly that: the count on screen is the count
# on the Belt, and the place on screen is the place the Simulation says.

func test_the_view_draws_a_slab_for_every_tile_of_belt() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(3, 0, 0))])
	view.sync(sim)
	assert_eq(view.belt_placeholder_count(), 4, "a four-tile run is four slabs")
	view.free()


func test_the_view_draws_one_instance_for_every_item_on_a_belt() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	var node_tile: Vector3i = sim.query_node_tile(0)
	sim.step([
		InputAction.build_machine(0, sim.query_definitions().machine_index("miner_mk1"), node_tile),
		InputAction.build_belt(
			0,
			Vector3i(node_tile.x + 2, node_tile.y, node_tile.z),
			Vector3i(node_tile.x + 9, node_tile.y, node_tile.z)
		),
	])
	view.sync(sim)
	assert_eq(view.item_instance_count(), 0, "nothing has been mined yet")
	# Ore lands on tick 90 and the Belt collects it on tick 91; the second follows 90
	# ticks later.
	_run(sim, 181)
	view.sync(sim)
	assert_eq(sim.query_belt_item_count(0), 2, "the premise of the assertion below")
	assert_eq(view.item_instance_count(), 2, "two Items on the Belt, two on screen")
	view.free()


func test_an_item_is_drawn_exactly_where_the_simulation_says_it_is() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	var node_tile: Vector3i = sim.query_node_tile(0)
	sim.step([
		InputAction.build_machine(0, sim.query_definitions().machine_index("miner_mk1"), node_tile),
		InputAction.build_belt(
			0,
			Vector3i(node_tile.x + 2, node_tile.y, node_tile.z),
			Vector3i(node_tile.x + 9, node_tile.y, node_tile.z)
		),
	])
	_run(sim, 150)
	view.sync(sim)
	var truth: FixedVec2 = sim.query_belt_item_position_metres(0, 0)
	var drawn: Vector3 = view.item_instance_position(0)
	assert_true(
		is_equal_approx(drawn.x, Fixed.to_float(truth.x)),
		"expected x %f, got %f" % [Fixed.to_float(truth.x), drawn.x]
	)
	assert_true(
		is_equal_approx(drawn.z, Fixed.to_float(truth.z)),
		"expected z %f, got %f" % [Fixed.to_float(truth.z), drawn.z]
	)
	view.free()


func test_the_hud_names_a_stalled_belt_and_a_starved_machine() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	var smelter: int = sim.query_definitions().machine_index("smelter_mk1")
	sim.step([InputAction.build_machine(0, smelter, Vector3i(20, 0, 20))])
	view.sync(sim)
	assert_true(
		view.hud_text().contains("starved"),
		"a Smelter with no Belt must read as starved, got %s" % view.hud_text()
	)
	view.free()


func test_the_hud_shows_the_power_grids_supply_demand_and_ratio() -> void:
	# The gauge the Power ticket exists to put on screen. Read off the Simulation every
	# frame, never remembered, so it cannot disagree with the grid it describes.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("miner_mk1"), sim.query_node_tile(0)
		),
	])
	sim.step([])
	view.sync(sim)
	assert_true(
		view.hud_text().contains("power 300/120 kW"),
		"a player must be able to read supply against demand, got %s" % view.hud_text()
	)
	assert_true(
		view.hud_text().contains("100%"),
		"and the ratio the two of them come to, got %s" % view.hud_text()
	)
	view.free()


func test_the_hud_reads_a_brownout_as_a_fraction_of_the_power_asked_for() -> void:
	# Three Miners at 120 kW on a 300 kW baseline is five sixths of what the Factory asked
	# for, and the HUD rounds that to a whole percent for the player.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	var miner: int = sim.query_definitions().machine_index("miner_mk1")
	var coal_miner: int = sim.query_definitions().machine_index("coal_miner_mk1")
	sim.step([
		InputAction.build_machine(0, miner, sim.query_node_tile(0)),
		InputAction.build_machine(0, miner, sim.query_node_tile(1)),
		InputAction.build_machine(0, coal_miner, sim.query_node_tile(2)),
	])
	sim.step([])
	view.sync(sim)
	assert_true(
		view.hud_text().contains("power 300/360 kW"),
		"got %s" % view.hud_text()
	)
	assert_true(
		view.hud_text().contains("83%"),
		"five sixths is 83%% of the Power asked for, got %s" % view.hud_text()
	)
	assert_true(
		view.hud_text().contains("throttled"),
		"and every Machine on the short grid must say so, got %s" % view.hud_text()
	)
	view.free()


func test_a_factory_the_player_builds_really_powers_itself() -> void:
	# Power has to be visible in the running game and not only in a test. The opening
	# Factory that used to prove it is gone, so this builds the same chain the way a
	# player does: a Coal Miner on the Map's coal, a Belt, and the Steam Boiler that
	# burns what the Belt delivers.
	var sim: Simulation = Simulation.new(1, 1)
	var definitions: Definitions = sim.query_definitions()
	var coal: Vector3i = Vector3i.ZERO
	for node: int in range(sim.query_node_count()):
		if sim.query_node_resource(node) == "coal":
			coal = sim.query_node_tile(node)
	assert_ne(coal, Vector3i.ZERO, "the starter Map has coal to burn")

	sim.step([
		InputAction.build_machine(0, definitions.machine_index("coal_miner_mk1"), coal),
		InputAction.build_belt(
			0, Vector3i(coal.x + 2, coal.y, coal.z), Vector3i(coal.x + 3, coal.y, coal.z)
		),
		InputAction.build_machine(
			0,
			definitions.machine_index("steam_boiler_mk1"),
			Vector3i(coal.x + 4, coal.y, coal.z)
		),
	])
	for tick: int in range(400):
		sim.step([])

	assert_eq(sim.query_power_supply_kw(), 900, "the baseline plant and a burning Boiler")
	assert_false(sim.query_power_is_in_deficit(), "so the Factory is in surplus")


func test_a_factory_the_player_builds_really_carries_ore_to_the_smelter() -> void:
	# The line #4 and #5 hardcoded, built the way a player builds it: as Input Actions.
	# This is the same Factory, proving the Build Gun can produce it rather than the
	# root node having to.
	var sim: Simulation = Simulation.new(1, 1)
	var definitions: Definitions = sim.query_definitions()
	var node_tile: Vector3i = sim.query_node_tile(0)
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), node_tile),
		InputAction.build_belt(
			0,
			Vector3i(node_tile.x + 2, node_tile.y, node_tile.z),
			Vector3i(node_tile.x + 5, node_tile.y, node_tile.z)
		),
		InputAction.build_machine(
			0,
			definitions.machine_index("smelter_mk1"),
			Vector3i(node_tile.x + 6, node_tile.y, node_tile.z)
		),
	])
	assert_eq(sim.query_machine_count(), 2, "the premise of the assertion below")

	# Long enough for the first ore to be mined, carried the length of the Belt, and
	# handed into the Smelter's input port.
	for tick: int in range(400):
		sim.step([])
	assert_true(
		sim.query_machine_input(1, "iron_ore") > 0, "the Smelter should have been fed by now"
	)
