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


# ── The Nest, the Breach and the Enemies ──────────────────────────────────────

## The shipped tuning with the Telegraph shortened to half a second, so a Wave the test
## calls arrives in thirty ticks. The *interval* is left alone: these fixtures bring their
## Wave forward with the lever, which is the same code path a player uses, rather than by
## rewriting a schedule into something the shipped game never runs.
func _soon(tuning: String) -> String:
	return tuning.replace("telegraph_seconds = 12", "telegraph_seconds = 0.5")


## A Run whose first Wave arrives within a second, so a test can see Crawlers.
func _threatened_sim() -> Simulation:
	var tuning: String = FileAccess.open("res://content/tuning.toml", FileAccess.READ).get_as_text()
	var definitions: Definitions = Definitions.parse(
		FileAccess.open("res://content/machines.csv", FileAccess.READ).get_as_text(),
		FileAccess.open("res://content/recipes.csv", FileAccess.READ).get_as_text(),
		_soon(tuning),
		FileAccess.open("res://content/waves.csv", FileAccess.READ).get_as_text(),
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv"
	)
	var sim: Simulation = Simulation.new(1, 1, definitions)
	sim.step([InputAction.call_wave_early(0)])
	return sim


func test_the_view_draws_the_nest_where_the_simulation_says_it_is() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	# The 4x4 footprint anchored at (-6,0,-6) spans -12 m to -4 m on both axes, so its
	# centre is (-8 m, -8 m).
	var placed: Vector3 = view.nest_position()
	assert_true(is_equal_approx(placed.x, -8.0), "expected x -8.0, got %f" % placed.x)
	assert_true(is_equal_approx(placed.z, -8.0), "expected z -8.0, got %f" % placed.z)
	view.free()


func test_the_view_marks_every_breach() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_eq(view.breach_marker_count(), sim.query_breach_count())
	view.free()


func test_the_view_draws_one_instance_for_every_enemy() -> void:
	var sim: Simulation = _threatened_sim()
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_eq(view.enemy_instance_count(), 0, "a Run opens with nothing on the Map")

	_run(sim, 2 * Simulation.TICKS_PER_SECOND)
	view.sync(sim)
	assert_true(sim.query_enemy_count() > 0, "the premise: Crawlers are out")
	assert_eq(view.enemy_instance_count(), sim.query_enemy_count())
	view.free()


func test_an_enemy_is_drawn_exactly_where_the_simulation_says_it_is() -> void:
	var sim: Simulation = _threatened_sim()
	var view: WorldView = WorldView.new()
	_run(sim, 5 * Simulation.TICKS_PER_SECOND)
	view.sync(sim)

	var where: FixedVec2 = sim.query_enemy_position_metres(0)
	var drawn: Vector3 = view.enemy_instance_position(0)
	assert_true(
		is_equal_approx(drawn.x, Fixed.to_float(where.x)),
		"expected x %f, got %f" % [Fixed.to_float(where.x), drawn.x]
	)
	assert_true(
		is_equal_approx(drawn.z, Fixed.to_float(where.z)),
		"expected z %f, got %f" % [Fixed.to_float(where.z), drawn.z]
	)
	view.free()


func test_an_enemy_is_never_a_node() -> void:
	# ADR 0001, and the whole reason the ~100-Enemy target is reachable: Enemies are
	# instances of one mesh, so the scene tree does not grow by one node per Crawler.
	var sim: Simulation = _threatened_sim()
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var quiet: int = view.get_child_count()

	_run(sim, 5 * Simulation.TICKS_PER_SECOND)
	view.sync(sim)
	assert_true(sim.query_enemy_count() >= 6, "a whole Wave is on the Map")
	assert_eq(
		view.get_child_count(),
		quiet,
		"and not one node was added for any of them"
	)
	view.free()


func test_the_hud_reports_the_nest_the_wave_and_the_swarm() -> void:
	var sim: Simulation = _threatened_sim()
	var view: WorldView = WorldView.new()
	_run(sim, 5 * Simulation.TICKS_PER_SECOND)
	view.sync(sim)
	var text: String = view.hud_text()
	assert_true(text.contains("nest %d/" % sim.query_nest_health()), "the Nest's health: %s" % text)
	assert_true(text.contains("wave 1"), "the Wave reached: %s" % text)
	assert_true(text.contains("crawlers %d" % sim.query_enemy_count()), "the swarm: %s" % text)
	view.free()


func test_the_hud_shows_heat_the_rates_behind_it_and_the_gap_it_is_buying() -> void:
	# The acceptance criterion about Heat being visible. Three numbers rather than one,
	# because one would not let a player decide anything: what they are carrying, what they
	# are adding against what the Nest hides, and how much sooner that makes the next Wave.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	var iron: int = sim.query_definitions().machine_index("miner_mk1")
	sim.step([InputAction.build_machine(0, iron, sim.query_node_tile(0))])
	_run(sim, 3 * Simulation.TICKS_PER_SECOND)

	view.sync(sim)
	var text: String = view.hud_text()
	assert_true(text.contains("heat %d" % sim.query_heat()), "the Factory's Heat: %s" % text)
	assert_true(
		text.contains("+%d/min, -%d/min" % [
			sim.query_heat_per_minute(), sim.query_heat_decay_per_minute()
		]),
		"what is driving it: %s" % text
	)
	assert_true(
		text.contains(
			"wave gap %ds" % (sim.query_wave_interval_ticks() / Simulation.TICKS_PER_SECOND)
		),
		"and what the Heat is costing in time: %s" % text
	)
	view.free()


func test_the_hud_names_each_machine_as_a_contributor_to_heat() -> void:
	# A player who cannot see *which* Machine is making them hot cannot make an informed
	# bet, so the contribution is on the Machine's own line next to what it is holding.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	var iron: int = sim.query_definitions().machine_index("miner_mk1")
	sim.step([InputAction.build_machine(0, iron, sim.query_node_tile(0))])
	_run(sim, 5 * Simulation.TICKS_PER_SECOND)
	assert_true(sim.query_machine_heat_units(0) > 0, "the Miner has made some Heat")

	view.sync(sim)
	var text: String = view.hud_text()
	assert_true(
		text.contains("heat %d (+%d/min)" % [
			sim.query_machine_heat_units(0), sim.query_machine_heat_per_minute(0)
		]),
		"the Miner's own contribution and rate: %s" % text
	)
	view.free()


func test_the_hud_says_nothing_about_a_telegraph_that_is_not_showing() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_false(sim.query_wave_is_telegraphed(), "a cold Run opens with a clear sky")
	assert_false(
		view.hud_text().contains("WAVE"),
		"so there is no warning on screen: %s" % view.hud_text()
	)
	view.free()


func test_the_hud_raises_a_telegraph_with_a_countdown_and_a_rising_gauge() -> void:
	# There is no audio yet, so the klaxon GLOSSARY.md describes is this line. It has to
	# carry enough to act on: which Wave, how long, and a gauge that fills.
	var sim: Simulation = _threatened_sim()
	var view: WorldView = WorldView.new()
	assert_true(sim.query_wave_is_telegraphed(), "the called Wave is being telegraphed")

	view.sync(sim)
	var opening: String = view.hud_text()
	assert_true(opening.contains("WAVE 1 INCOMING"), "which Wave, and in capitals: %s" % opening)
	assert_true(opening.contains("CALLED"), "and that a player asked for it: %s" % opening)
	assert_true(opening.contains("[" + ".".repeat(20) + "]"), "an empty gauge: %s" % opening)

	_run(sim, sim.query_telegraph_ticks() / 2)
	view.sync(sim)
	var halfway: String = view.hud_text()
	assert_true(halfway.contains("[##########.........."), "half full: %s" % halfway)
	assert_true(
		halfway.contains("INCOMING IN 1s") or halfway.contains("INCOMING IN 0s"),
		"and counting down: %s" % halfway
	)
	view.free()


func test_the_hud_says_whether_the_lever_can_be_pulled_and_why_not() -> void:
	# The reason is on screen *before* the player presses the key, exactly as a build
	# refusal is — which is both better than reporting a silence and the only version that
	# leaves the hash alone.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_true(view.hud_text().contains("call wave (G) — ready"), view.hud_text())

	sim.step([InputAction.call_wave_early(0)])
	view.sync(sim)
	assert_true(
		view.hud_text().contains("a Wave is already on its way"),
		"and says why once it cannot: %s" % view.hud_text()
	)
	view.free()


func test_the_hud_reports_a_lost_run_with_the_wave_it_reached() -> void:
	var tuning: String = FileAccess.open("res://content/tuning.toml", FileAccess.READ).get_as_text()
	var definitions: Definitions = Definitions.parse(
		FileAccess.open("res://content/machines.csv", FileAccess.READ).get_as_text(),
		FileAccess.open("res://content/recipes.csv", FileAccess.READ).get_as_text(),
		_soon(tuning).replace("health = 6000", "health = 10"),
		FileAccess.open("res://content/waves.csv", FileAccess.READ).get_as_text(),
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv"
	)
	var sim: Simulation = Simulation.new(1, 1, definitions)
	sim.step([InputAction.call_wave_early(0)])
	var view: WorldView = WorldView.new()
	while not sim.query_run_is_over():
		sim.step([])
	view.sync(sim)
	assert_true(
		view.hud_text().contains("THE NEST HAS FALLEN — reached wave 1"),
		"a Run that ended says so, and says how far it got: %s" % view.hud_text()
	)
	view.free()


# ── Real meshes ───────────────────────────────────────────────────────────────
# Each Machine, the Nest and every tile of Belt draw the body the asset pipeline
# generated for them. The assertions are about placement, orientation and the
# fallback — what the surfaces look like is judged by looking, not by a test.

func test_a_machine_draws_the_body_generated_for_its_id() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), Vector3i(10, 0, 10)
		)
	])
	view.sync(sim)
	assert_eq(
		view.machine_body_path(0),
		"res://assets/machines/smelter_mk1.glb",
		"a Smelter draws the Smelter the generator produced"
	)
	view.free()


func test_a_turned_machine_turns_its_body_with_its_footprint() -> void:
	# A 3x2 Steam Boiler turned a quarter covers 2x3 tiles from the same anchor, so the
	# body has to turn by the same quarter or it stands across its own neighbours.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("steam_boiler_mk1"), Vector3i(10, 0, 10), 1
		)
	])
	view.sync(sim)
	assert_eq(sim.query_machine_footprint(0), Vector2i(2, 3), "the premise of the assertions below")
	assert_true(
		is_equal_approx(view.machine_body_yaw(0), -TAU * 0.25),
		"expected a quarter turn, got %f radians" % view.machine_body_yaw(0)
	)
	# Two tiles from x=10 spans 20 m to 24 m, so the centre is 22 m; three tiles from
	# z=10 spans 20 m to 26 m, so the centre is 23 m.
	var placed: Vector3 = view.machine_placeholder_position(0)
	assert_true(is_equal_approx(placed.x, 22.0), "expected x 22.0, got %f" % placed.x)
	assert_true(is_equal_approx(placed.z, 23.0), "expected z 23.0, got %f" % placed.z)
	view.free()


func test_a_machine_body_stands_on_the_ground_rather_than_half_buried() -> void:
	# Every generated body is modelled with its feet on the ground, so it is seated at the
	# height of its layer and not at half its own height like a box would be.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), Vector3i(10, 0, 10)
		)
	])
	view.sync(sim)
	assert_ne(view.machine_body_path(0), "", "the premise: this Smelter has a body")
	assert_true(
		is_equal_approx(view.machine_placeholder_position(0).y, 0.0),
		"expected the ground, got y %f" % view.machine_placeholder_position(0).y
	)
	view.free()


## A definition set with a Machine the asset pipeline has never heard of, so the renderer
## has to draw something for a row that has no art.
func _sim_with_an_undrawn_machine() -> Simulation:
	var machines: String = (
		FileAccess.open("res://content/machines.csv", FileAccess.READ).get_as_text()
		+ "\nwind_vane_mk1,Wind Vane Mk1,crafter,2,2,10,0,100,0,0,0,smelt_iron_plate,\n"
	)
	var definitions: Definitions = Definitions.parse(
		machines,
		FileAccess.open("res://content/recipes.csv", FileAccess.READ).get_as_text(),
		FileAccess.open("res://content/tuning.toml", FileAccess.READ).get_as_text(),
		"machines.csv",
		"recipes.csv",
		"tuning.toml"
	)
	return Simulation.new(1, 1, definitions)


func test_a_machine_with_no_body_falls_back_to_a_placeholder() -> void:
	# Adding a Machine is a row in content/machines.csv and never a code change, so a row
	# whose art has not been drawn yet must still stand on the Map.
	var sim: Simulation = _sim_with_an_undrawn_machine()
	var view: WorldView = WorldView.new()
	assert_true(sim.query_definitions_loaded(), "the premise: the extra row loaded")
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("wind_vane_mk1"), Vector3i(10, 0, 10)
		)
	])
	view.sync(sim)
	assert_eq(sim.query_machine_count(), 1, "the premise of the assertions below")
	assert_eq(view.machine_body_path(0), "", "there is no body to draw")
	assert_eq(view.placeholder_count(), sim.query_node_count() + 1, "and it is drawn anyway")
	# 2x2 tiles from (10,10) spans 20 m to 24 m, so the placeholder's centre is 22 m.
	assert_true(
		is_equal_approx(view.machine_placeholder_position(0).x, 22.0),
		"on its own footprint, got x %f" % view.machine_placeholder_position(0).x
	)
	view.free()


# ── Belts ─────────────────────────────────────────────────────────────────────

func test_a_tile_of_belt_is_turned_to_the_direction_its_run_goes_in() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	# Along +z, which is the direction the Belt body is modelled running in, so it needs
	# no turn at all.
	sim.step([InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(0, 0, 3))])
	view.sync(sim)
	assert_eq(sim.query_belt_direction(0), 1, "the premise of the assertion below")
	assert_true(
		is_equal_approx(view.belt_instance_yaw(0), 0.0),
		"expected no turn, got %f radians" % view.belt_instance_yaw(0)
	)

	# And along +x, a quarter turn the other way round from a Machine's, because the grid
	# counts its directions clockwise and Godot turns counter-clockwise.
	sim.step([InputAction.build_belt(0, Vector3i(10, 0, 10), Vector3i(13, 0, 10))])
	view.sync(sim)
	assert_eq(sim.query_belt_direction(1), 0, "the premise of the assertion below")
	assert_true(
		is_equal_approx(view.belt_instance_yaw(4), TAU * 0.25),
		"expected a quarter turn, got %f radians" % view.belt_instance_yaw(4)
	)
	view.free()


func test_a_tile_of_belt_is_drawn_on_the_tile_the_simulation_says() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([InputAction.build_belt(0, Vector3i(10, 0, 10), Vector3i(12, 0, 10))])
	view.sync(sim)
	# Tile (10,0,10) is centred on 21 m, and the run advances one tile — 2 m — a step.
	assert_true(
		is_equal_approx(view.belt_instance_position(0).x, 21.0),
		"expected x 21.0, got %f" % view.belt_instance_position(0).x
	)
	assert_true(
		is_equal_approx(view.belt_instance_position(2).x, 25.0),
		"expected x 25.0, got %f" % view.belt_instance_position(2).x
	)
	view.free()


# ── Pooling ───────────────────────────────────────────────────────────────────
# The view rebuilds its numbers from the queries every frame but not its nodes. A
# standing Factory redrawn is the same nodes moved, and the things that reach the
# highest counts — Items, Enemies and tiles of Belt — are not nodes at all.

func test_redrawing_an_unchanged_factory_builds_no_new_nodes() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), Vector3i(10, 0, 10)
		),
		InputAction.build_belt(0, Vector3i(20, 0, 20), Vector3i(23, 0, 20)),
	])
	view.sync(sim)
	var settled: int = view.get_child_count()
	for frame: int in range(10):
		sim.step([])
		view.sync(sim)
	assert_eq(view.get_child_count(), settled, "ten more frames must cost nothing")
	view.free()


func test_a_machine_costs_one_node_and_a_belt_costs_none() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var empty: int = view.get_child_count()

	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), Vector3i(10, 0, 10)
		)
	])
	view.sync(sim)
	assert_eq(view.get_child_count(), empty + 1, "a Machine is one node, not a dozen")

	# Forty tiles of trestle, through the one MultiMesh every Belt on the Map shares.
	sim.step([InputAction.build_belt(0, Vector3i(20, 0, 20), Vector3i(59, 0, 20))])
	view.sync(sim)
	assert_eq(view.belt_placeholder_count(), 40, "the premise of the assertion below")
	assert_eq(view.get_child_count(), empty + 1, "and not one node for any of them")
	view.free()


func test_a_demolished_machine_hands_its_node_back() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var empty: int = view.get_child_count()

	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), Vector3i(10, 0, 10)
		)
	])
	view.sync(sim)
	sim.step([InputAction.demolish(0, Vector3i(10, 0, 10))])
	view.sync(sim)
	assert_eq(sim.query_machine_count(), 0, "the premise of the assertion below")
	assert_eq(view.get_child_count(), empty, "the pool shrinks back rather than leaking")
	view.free()


# ── A Turret's Ammunition, readable from a distance ───────────────────────────

func test_a_turret_wears_an_ammunition_gauge_and_nothing_else_does() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), Vector3i(4, 0, 4)),
	])
	view.sync(sim)
	assert_eq(view.turret_gauge_count(), 0, "a Miner has no magazine to read")

	sim.step([
		InputAction.build_machine(0, definitions.machine_index("mg_turret_mk1"), Vector3i(10, 0, 4)),
	])
	view.sync(sim)
	assert_eq(view.turret_gauge_count(), 1, "the Turret does")
	# The 2x2 Turret anchored at (10,0,4) spans 20 m to 24 m along x and 8 m to 12 m along z,
	# so the gauge hangs over (22 m, 10 m) — its own middle, not the Factory's.
	var where: Vector3 = view.turret_gauge_position(0)
	assert_true(is_equal_approx(where.x, 22.0), "expected x 22.0, got %f" % where.x)
	assert_true(is_equal_approx(where.z, 10.0), "expected z 10.0, got %f" % where.z)
	assert_true(where.y > WorldView.MACHINE_HEIGHT_METRES, "and above its roof, not inside it")
	view.free()


func test_an_empty_magazine_reads_red_from_across_the_factory() -> void:
	# The gauge has to distinguish "this Turret has stopped" from "there is no Turret here",
	# which is why the backing goes red rather than the fill simply vanishing.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("mg_turret_mk1"), Vector3i(10, 0, 4)
		),
	])
	view.sync(sim)
	assert_eq(sim.query_turret_ammunition(0), 0, "nothing has fed it")
	assert_eq(view.turret_gauge_width_metres(0), 0.0, "so the fill is not drawn at all")
	assert_eq(
		view.turret_gauge_backing_colour(0),
		WorldView.AMMUNITION_DRY,
		"and the bar itself is red"
	)
	assert_true(
		view.hud_text().contains("DRY"),
		"the HUD says so too, got %s" % view.hud_text()
	)
	view.free()
