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


func test_the_hud_reads_the_nest_store_and_why_a_withdrawal_is_refused() -> void:
	# The store is only useful if a player can see what is in it and why they cannot have it.
	# A Run opens standing away from the Nest on the starter Map, with a Miner on the Build
	# Gun it can already afford, so both halves of the reading are the opening state.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)

	assert_true(
		view.hud_text().contains("nest store: empty"),
		"an empty store must say so rather than going missing, got %s" % view.hud_text()
	)
	assert_true(
		view.hud_text().contains("nothing on the Build Gun needs paying for"),
		"a Machine the player can afford needs no withdrawal, got %s" % view.hud_text()
	)

	# Spend the opening bill on Machines until the Build Gun's own Machine is out of reach,
	# which is when a player needs to be told what to do about it.
	# Fourteen rather than ten, since #47 raised the opening bill to 110 plate to cover the
	# Belts the Factory needs: a Miner is 8, so thirteen of them leave six in the pocket and
	# the fourteenth is the refusal this test is about.
	var miner: int = sim.query_definitions().machine_index("miner_mk1")
	for which: int in range(14):
		sim.step([InputAction.build_machine(0, miner, Vector3i(20 + which * 3, WorldGrid.GROUND_LAYER, 20))])
	view.sync(sim)
	assert_true(
		view.hud_text().contains("take iron_plate"),
		"the HUD must name what is short, got %s" % view.hud_text()
	)
	assert_true(
		view.hud_text().contains("walk to the Nest"),
		"and why it cannot be had — a Run opens out of reach of its own Nest, got %s" % view.hud_text()
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
	# With the Build Gun drawn, since #42 opens a Run with the weapon out and #35 hides
	# the hologram when it is. The Machine on the gun at tick 0 is `ammo_press_mk1`, a
	# crafter, so nothing snaps and the aim is the tile — `test_build_gun` owns the
	# Miner's snap.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_mode(0, true)])
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
	sim.step([InputAction.set_build_mode(0, true)])
	# **A Machine that can stand anywhere, which #55 made something to say out loud.** This
	# test is about green-on-clear against red-on-occupied, and a Run now opens on the Miner
	# — which is refused on bare rock whatever the tile's occupancy, because a Miner snaps to
	# a Node or points nowhere (#42). The Ammo Press is what a Run opened on before #55, so
	# the walk below is the one it always made.
	sim.step([
		InputAction.select_machine(
			0, sim.query_definitions().machine_index("ammo_press_mk1")
		)
	])
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_false(view.hologram_is_refused(), "clear ground with the Build Gun out")

	# Fill the aimed tile, then look again at the same place.
	var aimed: Vector3i = BuildGun.aimed_tile(sim, 0)
	sim.step([
		InputAction.build_machine(0, sim.query_definitions().machine_index("miner_mk1"), aimed)
	])
	view.sync(sim)
	assert_true(view.hologram_is_refused(), "aiming at a Miner must read as refused")
	view.free()


func test_the_hologram_goes_away_when_the_build_gun_is_holstered() -> void:
	# #35, in the player's words: *"the hologram is still visible in gun mode"*. The
	# hologram is a promise that the next click will place something, so with a rifle in
	# frame it is promising something the next click will not do.
	#
	# Hidden rather than reddened, which is the one place this departs from how every
	# other refusal is drawn. A red hologram says "not **there**" and invites the player
	# to aim elsewhere; nowhere they aim will help, because the problem is in their hands.
	# A Run opens with the weapon out since #42, so the walk starts from there: no
	# hologram, draw the gun and it appears, holster and it goes again.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_false(view.hologram_is_visible(), "a Run opens with the weapon out")

	sim.step([InputAction.set_build_mode(0, true)])
	view.sync(sim)
	assert_true(view.hologram_is_visible(), "and drawing the Build Gun brings the promise")

	sim.step([InputAction.set_build_mode(0, false)])
	view.sync(sim)
	assert_false(view.hologram_is_visible(), "and the weapon takes it away again")
	view.free()


func test_the_hud_does_not_call_a_tile_clear_while_the_build_gun_is_away() -> void:
	# The other half of #35's first report, and the reason the rule had to become one
	# function rather than a visibility flag on the hologram: the panel reads out of the
	# same projection, so it cannot tell a player the tile is clear while the thing that
	# would fill it is on their back.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	# Drawn first: a Run opens with the weapon out since #42, so "clear" is what the panel
	# says once the gun is in hand rather than what it opens saying.
	sim.step([InputAction.set_build_mode(0, true)])
	# **And a Machine that can stand anywhere** (#55). What this asserts is that the panel
	# says "clear" with the gun in hand and stops saying it when the gun goes away — so the
	# tile has to be one the gun would actually take. A Run now opens on the Miner, which is
	# refused on bare rock wherever it is aimed, because a Miner snaps to a Node or points
	# nowhere (#42); that is a true refusal and a different test's subject. The Ammo Press is
	# what a Run opened on before #55, so this reads what it always read.
	sim.step([
		InputAction.select_machine(
			0, sim.query_definitions().machine_index("ammo_press_mk1")
		)
	])
	view.sync(sim)
	assert_true(view.hud_text().contains("clear"), "clear ground with the Build Gun out")

	sim.step([InputAction.set_build_mode(0, false)])
	view.sync(sim)
	assert_false(view.hud_text().contains("— clear"), "and nothing is clear for a rifle")
	assert_true(
		view.hud_text().contains("holstered"),
		"the panel names what is in the way, which is what is in the hands"
	)
	view.free()


func test_a_refusal_is_shown_as_a_reason_and_not_only_as_a_colour() -> void:
	# The acceptance criterion: refused *with a visible reason*, not silently.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	var aimed: Vector3i = BuildGun.aimed_tile(sim, 0)
	# With the Build Gun drawn, because a Run opens with the weapon out since #42 and a
	# holstered gun has a refusal of its own (#35) that would mask the one under test.
	sim.step([
		InputAction.set_build_mode(0, true),
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
	# What is **on the gun**, asked of the Simulation rather than spelled as the first row by
	# id. The two were the same thing until #55 named the opening Machine in content, and the
	# line this is about has always claimed to report the selection rather than the table.
	assert_true(
		view.hud_text().contains("build gun: %s" % sim.query_player_selected_machine(0)),
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
const SOON: Array = [["telegraph_seconds = 12", "telegraph_seconds = 0.5"]]


## The fixture every site in this file starts from: the shipped content, a tier that locks
## nothing, pockets that pay for anything, and this file's readable Gear and Stratagems.
## Seven sites used to spell all of that out a `FileAccess.open` at a time.
func _fixture() -> ContentFixture:
	var fixture: ContentFixture = ContentFixture.for_case(self)
	fixture.deliveries = DELIVERIES
	fixture.gear = GEAR
	fixture.stratagems = STRATAGEMS
	return fixture.stock(STOCKED_BILL)


## A Run whose first Wave arrives within a second, so a test can see Crawlers.
func _threatened_sim() -> Simulation:
	var definitions: Definitions = _fixture().tune(SOON).definitions()
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


## A Wave of Crawlers and Breakers both, so the two swarm kinds are on the Map at once and the
## renderer has to tell them apart. Both tiers are unlocked at Heat 0, which the shipped file
## does not do — `shock_breakers.min_heat` is 5200, about minute twenty-six.
const CRAWLERS_AND_BREAKERS: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,3,0,3
shock_breakers,breaker,0,2,0,2
"""


func _mixed_sim() -> Simulation:
	var mixed: ContentFixture = _fixture()
	mixed.waves = CRAWLERS_AND_BREAKERS
	var definitions: Definitions = mixed.tune(SOON).definitions()
	assert_true(
		not definitions.has_errors(),
		"the mixed fixture's content must load: %s" % definitions.describe_errors()
	)
	var sim: Simulation = Simulation.new(1, 1, definitions)
	sim.step([InputAction.call_wave_early(0)])
	return sim


func test_a_crawler_and_a_breaker_are_drawn_through_different_meshes() -> void:
	# #38's acceptance criterion, and the reason it is a criterion: a player's response to a
	# Breaker is to be somewhere else and their response to Chaff is to hold the line, so the
	# two have to be distinguishable at a glance. Before #38 both drew the *same* procedural
	# carapace out of one MultiMesh, so the only thing separating them on screen was the HUD.
	var sim: Simulation = _mixed_sim()
	var view: WorldView = WorldView.new()
	_run(sim, 5 * Simulation.TICKS_PER_SECOND)
	view.sync(sim)

	var crawlers: int = 0
	var breakers: int = 0
	for index: int in range(sim.query_enemy_count()):
		if sim.query_enemy_kind(index) == Simulation.ENEMY_KIND_CRAWLER:
			crawlers += 1
		elif sim.query_enemy_kind(index) == Simulation.ENEMY_KIND_BREAKER:
			breakers += 1
	if not assert_true(crawlers > 0 and breakers > 0, "the premise: both kinds are out"):
		view.free()
		return

	assert_eq(
		view.enemy_instance_count(Simulation.ENEMY_KIND_CRAWLER),
		crawlers,
		"every Crawler is an instance of the Crawler's own mesh"
	)
	assert_eq(
		view.enemy_instance_count(Simulation.ENEMY_KIND_BREAKER),
		breakers,
		"and every Breaker of the Breaker's"
	)
	assert_ne(
		view.enemy_mesh_id(Simulation.ENEMY_KIND_CRAWLER),
		view.enemy_mesh_id(Simulation.ENEMY_KIND_BREAKER),
		"and the two meshes are not the same mesh"
	)
	view.free()


func test_an_enemy_is_scaled_by_the_height_the_simulation_says_it_is() -> void:
	# "A body is placed, never measured", from the other end: the body is baked one metre
	# tall and the renderer scales it by `query_enemy_hit_height_metres`, which is the capsule
	# a round is resolved against. So a player shoots at what they can see. A constant here
	# would be the second authority that shipped #41's ownerless red rectangle.
	var sim: Simulation = _mixed_sim()
	var view: WorldView = WorldView.new()
	_run(sim, 5 * Simulation.TICKS_PER_SECOND)
	view.sync(sim)
	if not assert_true(sim.query_enemy_count() > 0, "the premise: a Wave is out"):
		view.free()
		return
	var kind: int = sim.query_enemy_kind(0)
	var expected: float = Fixed.to_float(sim.query_enemy_hit_height_metres(0))
	var drawn: float = view.enemy_instance_scale(kind, 0)
	assert_true(
		absf(drawn - expected) < 0.01,
		"expected a scale of %f, got %f" % [expected, drawn]
	)
	view.free()


func test_two_enemies_out_of_one_breach_are_drawn_on_different_frames() -> void:
	# The swarm is not in visible lockstep, asserted where it is observable: the per-instance
	# animation row. `EnemyAnimator` owns the rule and its own suite owns the arithmetic; this
	# is the claim that the number actually reaches the MultiMesh, which no test of a pure
	# function could make.
	var sim: Simulation = _mixed_sim()
	var view: WorldView = WorldView.new()
	_run(sim, 5 * Simulation.TICKS_PER_SECOND)
	view.sync(sim)
	var drawn: int = view.enemy_instance_count(Simulation.ENEMY_KIND_CRAWLER)
	if not assert_true(drawn >= 2, "the premise: at least two Crawlers are out"):
		view.free()
		return
	var rows: Dictionary = {}
	for instance: int in range(drawn):
		rows[view.enemy_instance_pose_row(Simulation.ENEMY_KIND_CRAWLER, instance)] = true
	assert_true(
		rows.size() > 1,
		"%d Crawlers are on %d different frames" % [drawn, rows.size()]
	)
	view.free()


func test_baking_a_character_adds_no_node_to_the_view() -> void:
	# The bake instantiates a character scene to read its rig, which is nodes — so the rule
	# is not only "no node per Enemy" but "no node at all": the scene is detached, read and
	# freed, and the view's own child count is what this measures. A bake that leaked its
	# scaffolding would grow the tree by nine MeshInstance3Ds the first time a Wave arrived,
	# which is the exact failure `test_an_enemy_is_never_a_node` is written to catch and
	# would not have caught, because it counts after the first sync.
	var sim: Simulation = _mixed_sim()
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var quiet: int = view.get_child_count()
	_run(sim, 5 * Simulation.TICKS_PER_SECOND)
	view.sync(sim)
	if not assert_true(sim.query_enemy_count() > 0, "the premise: a Wave is out"):
		view.free()
		return
	# **Zero**, not "no more than one a kind": the MultiMesh a kind is drawn through is
	# created on the first sync, before a Breach has released anything, so by the time a
	# Wave arrives there is nothing left to create. That is also why the bake is paid at
	# load rather than on the frame the first Crawler appears, which is the one frame of a
	# Run where a hitch is least affordable.
	assert_eq(
		view.get_child_count(),
		quiet,
		"the tree grew by %d for a whole Wave" % [view.get_child_count() - quiet]
	)
	_run(sim, 5 * Simulation.TICKS_PER_SECOND)
	view.sync(sim)
	assert_eq(view.get_child_count(), quiet, "and not by one more after that")

	# And the swarm really was drawn, so that this is a claim about a Wave rather than about
	# an empty Map — the honesty check beside the structural one.
	assert_true(
		view.enemy_instance_count() > 0,
		"the premise again: the swarm was drawn through the buffers rather than not at all"
	)
	view.free()


## A Run under siege: the shipped Map and the shipped content, with the Wave table replaced by a
## single Siege Hulk so one arrives on the first Wave of a cold Factory rather than at 1200 Heat.
## The Map is the shipped one, which is where the Hives are.
func _besieged_sim() -> Simulation:
	var besieged: ContentFixture = _fixture()
	besieged.waves = (
		"id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach\n"
		+ "siege_hulks,siege_hulk,0,1,0,1\n"
	)
	var definitions: Definitions = besieged.tune(SOON).definitions()
	assert_true(
		not definitions.has_errors(),
		"the besieged fixture's content must load: %s" % definitions.describe_errors()
	)
	var sim: Simulation = Simulation.new(1, 1, definitions)
	sim.step([InputAction.call_wave_early(0)])
	return sim


func test_a_siege_hulk_and_a_hive_are_never_nodes_either() -> void:
	# The boss is one more entry in the Enemy arrays (ADR 0001), so it is one more instance in a
	# buffer here — not a node, and not an exception to the rule the swarm obeys. The Hives are
	# the same claim about something that is on the Map from tick 0.
	var sim: Simulation = _besieged_sim()
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var quiet: int = view.get_child_count()
	assert_eq(view.hive_instance_count(), 2, "the shipped Map's two Hives, as instances")

	_run(sim, 20 * Simulation.TICKS_PER_SECOND)
	view.sync(sim)
	assert_eq(sim.query_enemy_count(), 1, "a Siege Hulk is on the Map")
	assert_eq(view.siege_hulk_instance_count(), 1, "drawn as one instance")
	assert_eq(view.enemy_instance_count(), 0, "and not through the swarm's mesh, which is empty")
	# A shell in the air is a pooled marker on the ground, which *is* a node — bounded by the
	# number of Siege Hulks on the Map, exactly as a Breach's slab is bounded by the geography.
	# What must never grow by a node is the Enemy, and that is what this measures.
	assert_eq(
		view.get_child_count(),
		quiet + view.shell_marker_count(),
		"and not one node was added for it beyond the markers for its shells"
	)
	view.free()


func test_the_view_draws_a_siege_hulk_where_the_simulation_says_it_is() -> void:
	var sim: Simulation = _besieged_sim()
	var view: WorldView = WorldView.new()
	_run(sim, 20 * Simulation.TICKS_PER_SECOND)
	view.sync(sim)
	if not assert_eq(sim.query_enemy_count(), 1, "a Siege Hulk is on the Map"):
		view.free()
		return
	var where: FixedVec2 = sim.query_enemy_position_metres(0)
	var drawn: Vector3 = view.siege_hulk_instance_position(0)
	assert_true(
		is_equal_approx(drawn.x, Fixed.to_float(where.x)),
		"expected x %f, got %f" % [Fixed.to_float(where.x), drawn.x]
	)
	assert_true(
		is_equal_approx(drawn.z, Fixed.to_float(where.z)),
		"expected z %f, got %f" % [Fixed.to_float(where.z), drawn.z]
	)
	view.free()


func test_the_view_marks_where_a_shell_will_land_before_it_lands() -> void:
	# The marker is the Telegraph: it is drawn from the Simulation's own impact point, so what a
	# player runs out of is literally where the damage will be.
	var sim: Simulation = _besieged_sim()
	var view: WorldView = WorldView.new()
	var ticks: int = 0
	while sim.query_shell_count() == 0 and ticks < 120 * Simulation.TICKS_PER_SECOND:
		sim.step([])
		ticks += 1
	view.sync(sim)
	if not assert_eq(sim.query_shell_count(), 1, "a shell is in the air after %d ticks" % ticks):
		view.free()
		return
	assert_eq(view.shell_marker_count(), 1, "and there is a marker on the ground for it")
	var at: FixedVec2 = sim.query_shell_impact_metres(0)
	var marker: Vector3 = view.shell_marker_position(0)
	assert_true(
		is_equal_approx(marker.x, Fixed.to_float(at.x)),
		"expected x %f, got %f" % [Fixed.to_float(at.x), marker.x]
	)
	assert_true(
		is_equal_approx(marker.z, Fixed.to_float(at.z)),
		"expected z %f, got %f" % [Fixed.to_float(at.z), marker.z]
	)

	# And it is gone once the shell has landed, because the query it is drawn from is.
	_run(sim, sim.query_shell_flight_ticks() + 1)
	view.sync(sim)
	assert_eq(sim.query_shell_count(), 0, "the shell landed")
	assert_eq(view.shell_marker_count(), 0, "and the marker went with it")
	view.free()


func test_the_hud_names_the_siege_hulk_and_the_bill_the_hives_are_charging() -> void:
	# A sortie has to be a decision made knowingly, so the HUD carries the bill the whole time
	# there is something out there worth leaving for. It deliberately does **not** say where the
	# Hulk's weak point is: discovering that the front is the wrong end is the fight.
	var sim: Simulation = _besieged_sim()
	var view: WorldView = WorldView.new()
	_run(sim, 20 * Simulation.TICKS_PER_SECOND)
	view.sync(sim)
	var text: String = view.hud_text()
	assert_true(text.contains("SIEGE HULK"), "the thing that is shelling them: %s" % text)
	assert_true(text.contains("ARMOURED FRONT"), "and that shooting it blind will not do: %s" % text)
	assert_true(text.contains("hives 2"), "what is still standing out on the Map: %s" % text)
	assert_true(
		text.contains("hiding %d/min less heat" % sim.query_hive_heat_shadow_per_minute()),
		"and what it is costing them: %s" % text
	)
	assert_true(text.contains("away from the nest"), "and how far from home they are: %s" % text)
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
	var definitions: Definitions = (
		_fixture().tune(SOON).tune([["health = 6000", "health = 10"]]).definitions()
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
	var undrawn: ContentFixture = _fixture()
	undrawn.machines = (
		ContentFixture.shipped(Definitions.MACHINES_FILE)
		+ "\nwind_vane_mk1,Wind Vane Mk1,crafter,2,2,3,10,0,100,0,0,0,0,0,smelt_iron_plate,\n"
	)
	var definitions: Definitions = undrawn.definitions()
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
	# Machine 1 is the Turret; machine 0 is the Miner, and asserting against the wrong
	# Machine's height is how a gauge hanging in the wrong place went unnoticed.
	assert_true(
		where.y > Fixed.to_float(sim.query_machine_height_metres(1)),
		"and above its roof, not inside it"
	)
	view.free()


func test_a_gauge_hangs_off_its_own_machines_roof_rather_than_a_fixed_height() -> void:
	# #41: a bright red rectangle floating in mid-air over the Factory with nothing under
	# it, which turned out to be a dry MG Turret's gauge hung from a constant set "taller
	# than any housing in the content". A mark 2.1 m clear of its own roof has visibly
	# stopped belonging to anything.
	#
	# **The Turret is given a housing shorter than the body it draws, and that is the whole
	# point of the fixture.** #50 found that this assertion passed while the rule it names
	# was broken: the gauge is worn only by a Turret, and both shipped Turret meshes are
	# *exactly* their declared housing, so the one Machine class that can wear both marks is
	# the one class where the two numbers cannot disagree. The test looked like it covered
	# the rule and in fact covered only the case where the rule is trivially true. Declaring
	# a Turret given one of the bodies the repository already carries is how the two numbers
	# are prised apart without inventing art: nothing else about the Turret changes, and both
	# marks have to find the body rather than the declaration.
	var sim: Simulation = _sim_with_a_turret_taller_than_its_housing()
	var view: WorldView = WorldView.new()
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("press_mk1"), Vector3i(10, 0, 4)
		),
	])
	sim.step([])
	view.sync(sim)

	var housing: float = Fixed.to_float(sim.query_machine_height_metres(0))
	var drawn: float = view.machine_drawn_roof_metres(sim, 0)
	assert_true(
		drawn > housing + 1.0,
		"the fixture really did prise the two numbers apart: %f drawn over %f declared"
			% [drawn, housing]
	)

	var clearance: float = view.turret_gauge_position(0).y - drawn
	assert_true(
		is_equal_approx(clearance, WorldView.AMMUNITION_GAUGE_LIFT_METRES),
		"the bar sits one lift above the body a player can see, got %f above %f"
			% [clearance, drawn]
	)
	assert_true(
		clearance > WorldView.AMMUNITION_GAUGE_HEIGHT_METRES * 0.5,
		"clear of the roof rather than sunk into it"
	)
	# The other mark this Machine is wearing hangs from the same roof, and this is the
	# assertion #50 rewrote. It used to compare two *constants*, which can only ever restate
	# the order they were written in; it now compares the two marks **where they were
	# actually drawn**, on a Machine whose housing and body disagree — so a mark measured off
	# the wrong one of the two fails here instead of passing by construction.
	assert_eq(view.starved_marker_count(), 1, "a Turret with no Ammunition is starved")
	assert_true(
		view.starved_marker_position(0).y
			> view.turret_gauge_position(0).y + WorldView.AMMUNITION_GAUGE_HEIGHT_METRES * 0.5,
		(
			"and the amber starved tag stacks above the bar instead of drawing through it: "
			+ "tag at %f, bar at %f"
		) % [view.starved_marker_position(0).y, view.turret_gauge_position(0).y]
	)
	view.free()


## A Run carrying **a Turret that has a body**, which neither shipped Turret does.
##
## `mg_turret_mk1` and `repair_pylon_mk1` have no row in `content/machine_bodies.csv` and no
## `.glb`, so both draw a placeholder box — and a placeholder box is sized *from the
## declaration*, which is precisely why a Turret can never catch a mark measured off the
## wrong number. This row borrows `press_mk1`, a body the repository already carries at
## 2.4 m with a superstructure over it, and declares a 1.2 m housing under it. Every other
## column is the shipped MG Turret's, including the reach — `Definitions` refuses a content
## set in which a Turret outranges the Siege Hulk, and this fixture is not the place to find
## that out.
const TURRET_WITH_A_BODY: String = (
	"press_mk1,Hydraulic Turret Mk1,turret,2,3,1.2,90,0,350,0,8,15,0,0,fire_mg,iron_plate:20\n"
)


func _sim_with_a_turret_taller_than_its_housing() -> Simulation:
	var tall: ContentFixture = _fixture()
	tall.machines = ContentFixture.shipped(Definitions.MACHINES_FILE) + TURRET_WITH_A_BODY
	var definitions: Definitions = tall.definitions()
	assert_false(definitions.has_errors(), definitions.describe_errors())
	# No Breach, so no Wave arrives to give the Turret something to shoot at and empty its
	# magazine in the middle of an assertion about where a bar is drawn.
	return Simulation.new(1, 1, definitions, MapLayout.empty())


func test_a_starved_tag_clears_the_body_a_player_can_see_not_the_housing_underneath_it() -> void:
	# #50, and #41's bug pointed inwards. `query_machine_height_metres` is the **housing** —
	# what the Simulation collides against — and five of the seven Machines draw a body well
	# above theirs: a Miner's derrick reaches 8.24 m over a declared 1.80, a Smelter's flue
	# 7.75 over 1.50. A tag hung off the housing is therefore *inside the derrick*, which a
	# render showed immediately and no count could have: the amber mark was drawn, was the
	# right colour and was in the right place horizontally, and was invisible.
	var layout: MapLayout = MapLayout.empty()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var view: WorldView = WorldView.new()
	# A Miner on bare rock, which is starved by the rule that a Miner's input is the ground
	# under it. No Node anywhere on this Map, so there is nothing for it to be working.
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("miner_mk1"), Vector3i(4, 0, 4)
		),
	])
	sim.step([])
	view.sync(sim)
	assert_eq(view.starved_marker_count(), 1, "a Miner over bare rock is starved")

	var housing: float = Fixed.to_float(sim.query_machine_height_metres(0))
	var drawn: float = view.machine_drawn_roof_metres(sim, 0)
	assert_true(
		drawn > housing + 1.0,
		"the Miner's derrick really does rise well over its housing: %f against %f"
			% [drawn, housing]
	)
	var clearance: float = view.starved_marker_position(0).y - drawn
	assert_true(
		clearance >= STARVED_MARK_CLEARS_THE_BODY_METRES,
		"so the tag clears the body rather than hiding in it, got %f above %f"
			% [clearance, drawn]
	)
	# And the other half of #41: a mark can be too high as well as too low. A tag floating
	# clear of the thing it is about is the ownerless red rectangle that ticket shipped.
	assert_true(
		clearance < 2.0 * STARVED_MARK_CLEARS_THE_BODY_METRES,
		"and rests on it rather than floating over it, got %f above %f" % [clearance, drawn]
	)
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


# ── The Delivery the Nest is waiting on ───────────────────────────────────────
# "What the next Delivery requires is visible to the player" is an acceptance criterion of
# its own (#14): progression is physical, so a player aims their whole Factory at this bill
# and one they cannot read is one they are guessing at.

func test_the_hud_names_the_next_delivery_and_what_it_still_wants() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)

	var text: String = view.hud_text()
	var next: int = sim.query_next_delivery()
	assert_true(
		text.contains(sim.query_delivery_display_name(next)),
		"the tier is named, got %s" % text
	)
	for item_id: String in sim.query_delivery_goods(next):
		assert_true(
			text.contains(
				"%s 0/%d" % [item_id, sim.query_delivery_goods_required(next, item_id)]
			),
			"every line of the bill is readable, got %s" % text
		)
	view.free()


func test_the_hud_says_why_a_delivery_cannot_be_handed_over_yet() -> void:
	# Two reasons in order, and the HUD carries whichever is current. A Run opens mining
	# nothing, so the first complaint is the Depth gate; once a Miner is standing, what is
	# left is that the spawn point is not the Nest's doorstep.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_true(
		view.hud_text().contains("mine deeper first"),
		"a Factory mining nothing has not reached Depth 1, got %s" % view.hud_text()
	)

	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("miner_mk1"), Vector3i(4, 0, 4)
		),
	])
	view.sync(sim)
	assert_eq(
		sim.query_delivery_refusal(0),
		Simulation.Refusal.TOO_FAR_FROM_THE_NEST,
		"the Depth gate is open and the player is not at the Nest"
	)
	assert_true(
		view.hud_text().contains("walk to the Nest"),
		"and the HUD says so, got %s" % view.hud_text()
	)
	view.free()


## A Run on the starter Map with a Mk2 Miner on its Depth 2 seam, run far enough that the
## Breach that mine opens has been announced and is part-way through its Telegraph.
func _sim_with_a_breach_coming() -> Simulation:
	var sim: Simulation = _unlocked_sim(9)
	for index: int in range(sim.query_node_count()):
		if sim.query_node_depth(index) != 2:
			continue
		sim.step([
			InputAction.build_machine(
				0,
				sim.query_definitions().machine_index("miner_mk2"),
				sim.query_node_tile(index)
			)
		])
		break
	_run(sim, 3900)
	return sim


func test_the_view_marks_a_breach_that_is_about_to_open() -> void:
	# A hole that is coming has to be visible on the ground before anything comes out of it,
	# not only in a line of text: the whole point of the warning is that a player can go and
	# look at where it will be and put something in the way.
	var sim: Simulation = _sim_with_a_breach_coming()
	assert_eq(sim.query_pending_breach_count(), 1, "a Breach is on its way")
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_eq(view.pending_breach_marker_count(), 1, "and it is marked where it will open")
	assert_eq(
		view.breach_marker_count(),
		sim.query_breach_count(),
		"the Breaches that already exist are drawn separately, because they are different things"
	)

	_run(sim, 2700)
	view.sync(sim)
	assert_eq(sim.query_breach_count(), 2, "it opened")
	assert_eq(view.pending_breach_marker_count(), 0, "so the warning marker is gone")
	assert_eq(view.breach_marker_count(), 2, "and it is a Breach now")
	view.free()


func test_the_hud_raises_a_klaxon_for_a_breach_that_is_about_to_open() -> void:
	var sim: Simulation = _sim_with_a_breach_coming()
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var text: String = view.hud_text()
	assert_true(text.contains("BREACH OPENING"), "the klaxon is on screen: %s" % text)
	var tile: Vector3i = sim.query_pending_breach_tile(0)
	assert_true(
		text.contains("%d, %d" % [tile.x, tile.z]),
		"and it says where, because that is what a player has to act on: %s" % text
	)
	view.free()


func test_the_hud_reports_the_depth_the_factory_has_reached() -> void:
	# Depth gates what is possible to deliver, so the figure it is gated against belongs on
	# the same line as the gate rather than somewhere a player has to go and find.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_eq(sim.query_depth_reached(), 0, "no Miner is standing yet")
	assert_true(
		view.hud_text().contains("depth 0 of 1"),
		"the HUD reads reached against required, got %s" % view.hud_text()
	)
	view.free()


func test_the_hud_says_nothing_about_a_breach_that_is_not_coming() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_false(
		view.hud_text().contains("BREACH OPENING"),
		"a Run that has dug nothing is not warned about anything"
	)
	view.free()


func test_the_hud_says_a_locked_machine_is_locked_rather_than_unbuildable() -> void:
	# "not unlocked" and "something is in the way" are different problems with different
	# fixes, so the Build Gun line never collapses them into one word.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	# With the Build Gun drawn, since #42 opens a Run with the weapon out and the
	# holstered refusal (#35) would mask the one under test — which is the ordering this
	# test is about, one step further out.
	sim.step([
		InputAction.set_build_mode(0, true),
		InputAction.select_machine(0, sim.query_definitions().machine_index("miner_mk2")),
	])
	view.sync(sim)
	assert_true(
		view.hud_text().contains("not unlocked"),
		"got %s" % view.hud_text()
	)
	view.free()


# ── Fixtures that keep progression out of the way ─────────────────────────────
# The shipped Delivery chain locks the two deeper Miners behind its tiers and a Run opens
# holding exactly the plates for one line (`content/deliveries.csv`, `content/tuning.toml`).
# Neither is what this file asserts, so these fixtures replace them with a tier that locks
# nothing and a stock that pays for anything.

## How far over the body a player can see a starved tag has to sit, in metres. Not
## `WorldView.STARVED_MARK_LIFT_METRES` restated — that is the number under test, and a test
## that reads it back asserts nothing. This is the independent claim: a tag is readable when
## it is clear of the silhouette and still visibly resting on it.
const STARVED_MARK_CLEARS_THE_BODY_METRES: float = 1.0

const STOCKED_BILL: String = "ammunition:400;coal:400;iron_ore:400;iron_plate:400"

## The Gear a Run is holding, inline so the fixture is a complete definition set. One
## weapon frame and whatever component this file's Delivery tiers name, because a tier
## naming Gear that does not exist is content somebody broke. These tests are not about
## combat, so the frame is the Pneumatic Wrench and nothing is fitted to it.
const GEAR: String = """id,display_name,kind,attack,damage,range_metres,spread_degrees,seconds_per_shot,ammunition_item,ammunition_per_shot,damage_percent,range_percent,spread_percent,interval_percent,ammunition_percent,damage_taken_percent
pneumatic_wrench,Pneumatic Wrench,weapon,melee,55,4,0,0.6,,0,0,0,0,0,0,0
placeholder_gear,Placeholder Barrel,barrel,,0,0,0,0,,0,10,0,0,0,0,0
"""


## A Stratagem table that is not what this file is about. One row, so the table is not empty —
## `Definitions` refuses an empty one, because a Silo with nothing to load is a Machine a
## player can build, feed and never use. `test_silo.gd` is where the shipped table is
## asserted, exactly as `test_delivery.gd` is where the shipped Delivery chain is.
const STRATAGEMS: String = """id,display_name,effect,paint_seconds,radius_tiles,damage_per_charge,goods_per_charge,sentry_machine,sentry_seconds
artillery_barrage,Artillery Barrage,barrage,5,6,150,,,0
"""


const DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_opening,Opening Licence,1,iron_plate:1,,placeholder_gear,
"""


## A Run on the Map a Run starts on, reading the shipped content with those two substitutions
## made — so a test about what the renderer draws can build whatever it needs to without
## walking the Delivery chain first.
func _unlocked_sim(world_seed: int) -> Simulation:
	var definitions: Definitions = _fixture().definitions()
	assert_false(definitions.has_errors(), definitions.describe_errors())
	return Simulation.new(world_seed, 1, definitions)


func test_the_hud_says_how_close_a_deep_mine_is_to_opening_a_breach() -> void:
	# Heat's rule applied to the Breach: a consequence a player cannot watch themselves cause
	# reads as bad luck. So a deep Miner's line carries the count against its threshold, next
	# to the Machine that is running it up.
	var sim: Simulation = _unlocked_sim(9)
	var seam: Vector3i = Vector3i.ZERO
	for index: int in range(sim.query_node_count()):
		if sim.query_node_depth(index) == 2:
			seam = sim.query_node_tile(index)
			break
	sim.step([
		InputAction.build_machine(0, sim.query_definitions().machine_index("miner_mk2"), seam)
	])
	_run(sim, 1000)

	var view: WorldView = WorldView.new()
	view.sync(sim)
	var text: String = view.hud_text()
	assert_true(text.contains("digging"), "the deep Miner's line names what it is doing: %s" % text)
	assert_true(
		text.contains("/%d" % sim.query_node_deep_crafts_until_a_breach()),
		"against the threshold, so the number has a scale: %s" % text
	)

	var shallow: Simulation = _unlocked_sim(1)
	shallow.step([
		InputAction.build_machine(
			0, shallow.query_definitions().machine_index("miner_mk1"), shallow.query_node_tile(0)
		)
	])
	_run(shallow, 1000)
	view.sync(shallow)
	assert_false(
		view.hud_text().contains("digging"),
		"and a Miner on the ore a Run opens on is not digging anything up it should not"
	)
	view.free()


# ── Walls ─────────────────────────────────────────────────────────────────────

func test_the_view_draws_every_wall_through_one_multimesh() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var empty: int = view.get_child_count()
	assert_eq(view.wall_instance_count(), 0, "nothing walled off yet")

	# Thirty Walls, which is a modest length of one, through the one MultiMesh they share.
	for step: int in range(30):
		sim.step([InputAction.build_wall(0, Vector3i(20, 0, 20 + step))])
	view.sync(sim)
	assert_eq(view.wall_instance_count(), 30, "the premise of the assertion below")
	assert_eq(
		view.get_child_count(),
		empty,
		"and not one node for any of them — the MultiMesh they share was already there, so"
		+ " the scene tree does not grow by so much as one node for a hundred Walls"
	)
	view.free()


func test_a_wall_is_drawn_on_its_own_tile() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	var tile: Vector3i = Vector3i(8, 0, -4)
	sim.step([InputAction.build_wall(0, tile)])
	view.sync(sim)

	var centre: FixedVec2 = sim.query_tile_centre_metres(tile)
	var at: Vector3 = view.wall_instance_position(0)
	assert_true(absf(at.x - Fixed.to_float(centre.x)) < 0.01, "on the tile's own centre")
	assert_true(absf(at.z - Fixed.to_float(centre.z)) < 0.01)
	assert_true(at.y > 0.0, "and standing on the ground rather than sunk into it")
	view.free()


func test_a_demolished_wall_stops_being_drawn() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	var tile: Vector3i = Vector3i(8, 0, -4)
	sim.step([InputAction.build_wall(0, tile)])
	view.sync(sim)
	assert_eq(view.wall_instance_count(), 1)
	sim.step([InputAction.demolish(0, tile)])
	view.sync(sim)
	assert_eq(view.wall_instance_count(), 0, "the buffer is rebuilt from the queries, not diffed")
	view.free()


func test_the_hud_names_a_damaged_machine_and_counts_damaged_walls() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([InputAction.build_wall(0, Vector3i(8, 0, -4))])
	view.sync(sim)
	assert_true(view.hud_text().contains("walls 1 — 0 damaged"), view.hud_text())
	assert_false(view.hud_text().contains("DAMAGED"), "nothing has been chewed")
	view.free()


# ── The weapon in frame ───────────────────────────────────────────────────────
# The model itself is `game/weapon_viewmodel.gd` and `tests/cases/test_weapon_viewmodel.gd`
# is where its clips and its model swaps are asserted. What is worth asserting here is that
# every number `WorldView` moves it by comes out of the Simulation: the model follows the
# Run, never the other way round.

func test_the_weapon_is_in_frame_and_follows_the_run() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()

	# A Run opens with the Build Gun out, so the weapon has to be asked for — and the swap
	# has to finish, because the model in frame is still the old one until it has been put
	# away. The holster and the draw are clips, so wait for the carriage rather than for a
	# tick count.
	sim.step([InputAction.set_build_mode(0, false)])
	assert_true(_settled(sim, view), "the holster and the draw finish")
	assert_true(view.weapon_is_visible(), "the weapon is drawn once the holster is done")
	assert_eq(view.weapon_model_id(), sim.query_player_weapon(0), "and it is the weapon")
	var standing: Vector3 = view.weapon_offset()

	# Walking sways it, and the sway is read off `query_player_velocity` rather than off a
	# clock — so a player standing still has a steady weapon.
	for tick: int in range(30):
		sim.step([InputAction.move(0, Fixed.ONE, 0)])
	view.sync(sim)
	assert_ne(view.weapon_offset(), standing, "walking moves it")

	# And it comes back to rest when they stop, because the velocity does.
	_run(sim, 60)
	view.sync(sim)
	assert_eq(view.weapon_offset(), standing, "and standing still brings it back to rest")

	view.free()


func test_the_weapon_drops_out_of_frame_while_the_player_is_down() -> void:
	# A weapon still in frame while bleeding out reads as a bug rather than as a state.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	sim.step([InputAction.set_build_mode(0, false)])
	assert_true(_settled(sim, view), "the weapon is out")
	assert_true(view.weapon_is_visible())
	assert_true(sim.query_player_is_alive(0), "and the player is on their feet to start with")
	view.free()


func test_the_swap_is_over_within_the_tuned_budget() -> void:
	# #35, in the player's words: *"swapping modes should be instant, not taking so long"*.
	#
	# They reached for `player.holster_seconds` first and nothing changed, which was correct
	# and was the bug: #28 timed the swap off the `holster` and `draw` clip lengths of the
	# model on screen, so what you actually waited through was
	# `WeaponAnimator.DEFAULT_SECONDS` — 0.3 s down plus 0.4 s up, seven tenths of a second
	# — while the tuning key a tuner would reach for was read by nothing in `game/` at all.
	#
	# So the key is the **budget** for the visible swap and the clips decide its shape
	# inside that. Asserted against the tuning rather than against a number written here,
	# because the whole point is that turning the key down is what makes the swap quicker.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)

	var budget: float = Fixed.to_float(sim.query_definitions().player_holster_seconds)
	# One tick of slack either side of the budget: the swap begins on the tick the intent
	# lands and the clip boundary is a float compared against whole ticks.
	var ticks: int = int(ceilf(budget * float(Simulation.TICKS_PER_SECOND))) + 2

	sim.step([InputAction.set_build_mode(0, false)])
	for _tick: int in range(ticks):
		sim.step([])
		view.sync(sim)

	assert_eq(
		view.weapon_model_id(),
		sim.query_player_weapon(0),
		"%d ticks is the whole budget, and the weapon should be the thing in frame" % ticks
	)
	assert_false(
		[WeaponAnimator.HOLSTER, WeaponAnimator.DRAW].has(view.weapon_clip_role()),
		"and nothing should still be going down or coming up, got %s" % view.weapon_clip_role()
	)
	view.free()


func test_the_build_gun_and_the_weapon_swap_places_rather_than_popping() -> void:
	# The holster, which is what makes left mouse able to place *and* fire: one object goes
	# down, the other comes up, and the model in frame is the one *going away* for exactly
	# as long as putting it away takes.
	#
	# **It goes through the same seam a weapon change does.** `WorldView._sync_weapon` reads
	# `query_player_is_in_build_mode` and hands `WeaponViewmodel` the Build Gun's id; the
	# `holster`, the model swap and the `draw` are `WeaponAnimator`'s, which is why the waits
	# here are "until it settles" rather than a count of ticks — see
	# `tests/cases/test_weapon_viewmodel.gd`.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()

	view.sync(sim)
	assert_true(view.weapon_is_visible(), "a Run opens with something in hand")
	assert_eq(
		view.weapon_model_id(),
		sim.query_player_weapon(0),
		"and it is the weapon, because a Run opens with it out (#42)"
	)
	assert_true(_settled(sim, view), "the opening draw finishes")

	# The tick the key goes down the mode has already changed and the model has not: the
	# weapon is the thing being put away, and you cannot holster a thing you have already
	# swapped out.
	sim.step([InputAction.set_build_mode(0, true)])
	view.sync(sim)
	assert_true(sim.query_player_is_in_build_mode(0), "the mode flips instantly")
	assert_eq(view.weapon_clip_role(), WeaponAnimator.HOLSTER, "and the weapon goes down")
	assert_eq(
		view.weapon_model_id(), sim.query_player_weapon(0), "still the thing going away"
	)

	# Then they have changed over, and the Build Gun is what came up.
	assert_true(_settled(sim, view), "the swap finishes")
	assert_eq(
		view.weapon_model_id(), WorldView.BUILD_GUN_HELD_ID, "and the Build Gun is drawn"
	)
	view.free()


## Steps until the thing in frame is being carried rather than drawn or stowed, and reports
## whether it got there. Bounded, because a test that hangs is worse than one that fails.
func _settled(sim: Simulation, view: WorldView) -> bool:
	for tick: int in range(600):
		sim.step([])
		view.sync(sim)
		var role: String = view.weapon_clip_role()
		if role == WeaponAnimator.IDLE or role == WeaponAnimator.WALK:
			return true
	return false


func test_the_weapon_does_not_grow_the_scene_tree_as_the_run_goes_on() -> void:
	# Everything after a model is in hand is a transform, never a node.
	#
	# Models load lazily, the first time the thing they belong to is actually shown —
	# which is what lets a clone with no purchased packs run on placeholders, and what
	# stops a Run paying for art it never puts in frame. So the baseline is taken *after*
	# both hands have been seen once: counting before that measures the loading, not a
	# leak, and this test is about the leak.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	for warm: int in range(4):
		sim.step([InputAction.set_build_mode(0, warm % 2 == 0)])
		view.sync(sim)
	var before: int = _descendants(view)
	for tick: int in range(120):
		# Swapping hands every other tick too, which is the thing most likely to build a
		# node per swap if somebody ever writes it that way.
		sim.step([
			InputAction.fire(0), InputAction.set_build_mode(0, tick % 2 == 0)
		])
		view.sync(sim)
	assert_eq(_descendants(view), before, "a hundred and twenty swings add not one node")
	view.free()


## How many nodes hang off a node, all the way down.
func _descendants(node: Node) -> int:
	var total: int = 0
	for child: Node in node.get_children():
		total += 1 + _descendants(child)
	return total


func test_the_telegraph_names_the_tiers_in_the_wave_it_is_warning_about() -> void:
	# #34's legibility criterion, at the only place a player can read it. The geography fix
	# brings a Breaker down the lane under fire and turns it on the Factory when it gets there;
	# that is a lesson only if the warning said a Breaker was coming. A line reading "WAVE 12
	# INCOMING" and nothing else cannot teach anybody where to stand.
	var sim: Simulation = Simulation.new(1, 1, null, MapLayout.starter())
	var view: WorldView = WorldView.new()
	sim.step([InputAction.call_wave_early(0)])
	view.sync(sim)

	var crawlers: int = sim.query_telegraphed_wave_count_of_kind(EnemyKind.CRAWLER)
	assert_true(crawlers > 0, "the shipped cold Wave is Crawlers")
	assert_true(
		view.hud_text().contains("INCOMING"),
		"the Telegraph is still the loudest line, got %s" % view.hud_text()
	)
	assert_true(
		view.hud_text().contains("%d crawler" % crawlers),
		"and it names the tier and the count, got %s" % view.hud_text()
	)
	assert_false(
		view.hud_text().contains("breaker"),
		"a cold Factory has not earned the Breaker tier, so nothing announces one"
	)
	view.free()


func test_a_split_tag_hangs_off_its_own_machines_roof_and_stacks_with_the_others() -> void:
	# #41 again, and the reason it is asserted rather than trusted: a mark hung at a constant
	# "taller than any housing in the content" is a second authority on how tall a Machine is,
	# and what it shipped was a saturated red rectangle floating over the Factory with nothing
	# under it. A Miner is 1.8 m and this tag has to be 1.8 m plus a lift, read off
	# `query_machine_height_metres` like every other mark a Machine wears.
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
		InputAction.build_belt(0, Vector3i(2, 0, 1), Vector3i(6, 0, 1)),
	])
	view.sync(sim)
	assert_eq(view.split_marker_count(), 1, "the Miner splits, so it wears the tag")

	var housing: float = Fixed.to_float(sim.query_machine_height_metres(0))
	assert_true(
		view.split_marker_position(0).y >= housing + WorldView.SPLIT_MARK_CLEARS_THE_ROOF_METRES,
		"at least one lift above the Miner's declared 1.8 m housing, got %f over %f"
			% [view.split_marker_position(0).y, housing]
	)
	# And above the body actually drawn, which on this Machine is the taller of the two: a
	# Miner's housing is 1.8 m and its derrick goes well past that, so a tag placed off the
	# housing alone would be inside the model. That is #41's bug pointed the other way, and
	# only a render found it — see `WorldView._machine_roof`.
	var drawn: float = view.machine_drawn_roof_metres(sim, 0)
	assert_true(
		drawn > housing,
		"the Miner's body really is taller than its housing: %f against %f" % [drawn, housing]
	)
	var clearance: float = view.split_marker_position(0).y - drawn
	assert_true(
		clearance >= WorldView.SPLIT_MARK_CLEARS_THE_BODY_METRES,
		"and the tag clears the body too, got %f above %f" % [clearance, drawn]
	)
	# The other half of #41: a mark can be too high as well as too low. The second render of
	# this had the tag seven metres up over a Smelter's flue, overlapping the HUD, with
	# nothing visibly under it — which is exactly the ownerless rectangle #41 was about.
	assert_true(
		clearance < 2.0 * WorldView.SPLIT_MARK_CLEARS_THE_ROOF_METRES,
		"and is not floating clear of the thing it is about, got %f above %f" % [clearance, drawn]
	)
	# The three marks a Machine can wear all hang off that same roof, so the lifts have to be
	# an order rather than three numbers: the Ammunition bar, then the amber starved tag, then
	# this one. Any two at the same height draw through each other.
	assert_true(
		WorldView.AMMUNITION_GAUGE_LIFT_METRES < WorldView.STARVED_MARK_LIFT_METRES
			and WorldView.STARVED_MARK_LIFT_METRES < WorldView.SPLIT_MARK_CLEARS_THE_ROOF_METRES,
		"the three stack in that order"
	)
	assert_true(
		WorldView.SPLIT_MARK_CLEARS_THE_ROOF_METRES - WorldView.STARVED_MARK_LIFT_METRES
			> WorldView.SPLIT_MARK_SIZE_METRES * 0.3,
		"and this one clears the starved tag by more than its own thickness"
	)
	# The branch post stands on a Belt tile rather than on a roof, so the number it has to
	# clear is the deck under it. At 0.7 m it was *inside* the conveyor it was about, which a
	# render found and no count could have.
	assert_true(
		WorldView.BRANCH_MARK_HEIGHT_METRES
			> Fixed.to_float(sim.query_belt_deck_height_metres())
				+ WorldView.BRANCH_MARK_SIZE_METRES * 0.5,
		"and a branch post stands clear of the Belt deck rather than inside it"
	)
	view.free()


# ── Ore you can see ───────────────────────────────────────────────────────────
# #52, from a playtest: "I cant seem to find any ore in range for the miners." A Node was a
# 0.4 m slab in a brown the ground itself is made of, 28 m from where a Run starts. The slab
# stays a slab — a Node is **ground a Miner is placed over**, and anything that made it a
# structure would trade one confusion for another — so what carries the legibility is a stack
# of unshaded segments floating well clear of it, one per Depth tier.

func test_a_node_wears_one_floating_segment_for_every_depth_tier_it_sits_at() -> void:
	# Depth counted out rather than coloured, so "deeper" reads as "taller mark" and a player
	# learns the tiers by looking rather than by being starved by one.
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(10, 0, 0), "iron_ore", 1)
	layout.add_node(Vector3i(16, 0, 0), "iron_ore", 3)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_eq(view.ore_beacon_count(), 4, "one segment for the shallow Node and three for the seam")
	view.free()


func test_the_ore_wears_a_marking_on_the_ground_and_a_stack_in_the_air_above_it() -> void:
	# Two marks because two viewpoints, and a render is what settled it. The stack is what
	# reads at eye level across the yard; the marking is what reads from Survey View, where a
	# vertical mark is a 0.6 m square seen end on and the first survey shot showed no ore at
	# all. The marking also gives the floating stack an owner — #41's lesson, which is that a
	# bright mark with nothing under it belongs to nobody.
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(10, 0, 0), "iron_ore", 2)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var view: WorldView = WorldView.new()
	view.sync(sim)

	assert_eq(view.ore_marking_count(), 1, "one marking painted on the one piece of ore")
	assert_eq(view.ore_beacon_count(), 2, "and a segment in the air for each of its two tiers")

	# Tile (10,0,0) is 20 m to 22 m on x and 0 m to 2 m on z, so the centre is (21, 1). Every
	# mark stands over the middle of the Node's own tile.
	for at: Vector3 in [
		view.ore_marking_position(0), view.ore_beacon_position(0), view.ore_beacon_position(1)
	]:
		assert_eq(at.x, 21.0)
		assert_eq(at.z, 1.0)

	# The marking lies on the ore. The stack starts clear above it, with open air between —
	# which is what stops a mark over buildable ground reading as a structure standing on it.
	assert_true(
		view.ore_marking_position(0).y <= WorldView.NODE_HEIGHT_METRES + 0.1,
		"the marking is paint on the ore, got %f" % view.ore_marking_position(0).y
	)
	var lowest: float = minf(view.ore_beacon_position(0).y, view.ore_beacon_position(1).y)
	assert_true(
		lowest - WorldView.NODE_BEACON_SEGMENT_METRES * 0.5 > WorldView.NODE_HEIGHT_METRES + 0.5,
		"and there is open air under the stack, got %f" % lowest
	)
	assert_ne(view.ore_beacon_position(0).y, view.ore_beacon_position(1).y, "a stack, not a pile")
	view.free()


func test_iron_and_coal_wear_different_colours_and_ore_out_of_reach_wears_neither() -> void:
	# Three questions one mark has to answer at thirty metres: is there ore here, which ore,
	# and is it mine yet. The third is `query_node_is_workable_now` — the Simulation's own
	# answer, the same one the objective line points by — so a mark cannot promise a seam the
	# hint will not send a player to.
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(10, 0, 0), "iron_ore", 1)
	layout.add_node(Vector3i(16, 0, 0), "coal", 1)
	layout.add_node(Vector3i(22, 0, 0), "iron_ore", 2)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var view: WorldView = WorldView.new()
	view.sync(sim)

	var iron: Color = _beacon_over(view, sim, Vector3i(10, 0, 0))
	var coal: Color = _beacon_over(view, sim, Vector3i(16, 0, 0))
	var seam: Color = _beacon_over(view, sim, Vector3i(22, 0, 0))
	assert_ne(iron, coal, "iron and coal are told apart by colour")
	assert_eq(iron, WorldView.ORE_IRON_COLOUR)
	assert_eq(coal, WorldView.ORE_COAL_COLOUR)
	assert_eq(seam, WorldView.ORE_OUT_OF_REACH_COLOUR, "and a seam no Miner can lift is inert")
	view.free()


## The colour of the lowest beacon segment over a Node's tile.
func _beacon_over(view: WorldView, sim: Simulation, tile: Vector3i) -> Color:
	var centre: FixedVec2 = sim.query_tile_centre_metres(tile)
	var best: int = -1
	for instance: int in range(view.ore_beacon_count()):
		var at: Vector3 = view.ore_beacon_position(instance)
		if not is_equal_approx(at.x, Fixed.to_float(centre.x)):
			continue
		if not is_equal_approx(at.z, Fixed.to_float(centre.z)):
			continue
		if best == -1 or at.y < view.ore_beacon_position(best).y:
			best = instance
	assert_true(best != -1, "there is a mark over %s" % tile)
	return view.ore_beacon_colour(best)


func test_building_on_ore_takes_its_marks_away_whether_or_not_the_machine_works_it() -> void:
	# The mark is an invitation — *this is ore you can still claim* — so it leaves when the
	# ground stops being claimable, with nothing remembered. Deliberately not "when the ore is
	# being worked": a Miner standing idle on ore it cannot mine already says so in amber
	# through `query_machine_is_starved`, and marking the same tile twice is two marks about
	# one thing. Pointing at it would be pointing at ground nothing can be placed on, which is
	# the very reason `Objective` skips it too.
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(10, 0, 0), "iron_ore", 1)
	layout.add_node(Vector3i(16, 0, 0), "coal", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_eq(view.ore_marking_count(), 2, "two Nodes, nothing built on either")

	var miner: int = sim.query_definitions().machine_index("miner_mk1")
	sim.step([InputAction.build_machine(0, miner, Vector3i(10, 0, 0))])
	view.sync(sim)
	assert_eq(view.ore_marking_count(), 1, "the iron has been claimed")
	assert_eq(view.ore_beacon_count(), 1, "and its stack went with it")

	# An iron Miner over coal: it covers the Node and mines the wrong thing, so it is starved —
	# and the ground is taken all the same.
	sim.step([InputAction.build_machine(0, miner, Vector3i(16, 0, 0))])
	view.sync(sim)
	assert_true(sim.query_machine_is_starved(1), "the second Miner is over the wrong ore")
	assert_eq(view.ore_marking_count(), 0, "and claimed ground is claimed either way")
	view.free()


func test_the_ore_marks_do_not_grow_the_scene_tree() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var children: int = view.get_child_count()
	assert_true(view.ore_beacon_count() > 1, "the shipped Map has ore with tiers to count")
	_run(sim, 30)
	view.sync(sim)
	assert_eq(view.get_child_count(), children, "every segment is one instance of one MultiMesh")
	view.free()


func test_the_ore_in_the_ground_is_painted_inside_the_palette_rather_than_brightened() -> void:
	# The lesson #32 recorded and #38 paid for again: a colour picked against a white
	# background is a colour picked against the wrong thing. The old slab was 0.45 albedo
	# against a palette that runs 0.055 to 0.14, so it was *already* the brightest thing in
	# frame and still invisible — because it shared its hue with the rust and soot the ground
	# is made of. Brightness was never the lever, so the ore reads as a seam in the ground and
	# the marks above it do the work.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	for colour: Color in [WorldView.ORE_IRON_GROUND, WorldView.ORE_COAL_GROUND]:
		for channel: float in [colour.r, colour.g, colour.b]:
			assert_true(
				channel <= 0.2, "%s sits inside the palette's range, got %f" % [colour, channel]
			)
	assert_ne(WorldView.ORE_IRON_GROUND, WorldView.ORE_COAL_GROUND, "and the two seams differ")
	view.free()


# ── The scanner ───────────────────────────────────────────────────────────────
# The player's own words: "we need a sort of scanner to ping the nearest node while putting
# down miners". So the hint is a mechanic rather than a line of text — a run of pings that
# travels the ground from the player's feet out to the nearest ore they could claim, in that
# ore's own colour, so the thing that leads you there and the thing you arrive at are
# visibly one thing.
#
# **Timed by the tick and nothing else.** A pulse driven by a clock is two Runs down the same
# script looking different, which is the rule `WeaponViewmodel` keeps by seeking its clips
# from the tick count and the rule the audio director keeps with `tick % count`.

## A Run with a Miner on the Build Gun, which is the condition the scanner runs under.
func _scanning_run(layout: MapLayout) -> Simulation:
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	sim.step([
		InputAction.set_build_mode(0, true),
		InputAction.select_machine(0, sim.query_definitions().machine_index("miner_mk1")),
	])
	return sim


func _ore_layout() -> MapLayout:
	var layout: MapLayout = MapLayout.empty()
	layout.nest_tile = Vector3i(0, 0, 0)
	layout.add_node(Vector3i(0, 0, 14), "iron_ore", 1)
	layout.sort_nodes()
	return layout


func test_the_scanner_runs_only_while_a_miner_is_on_the_build_gun() -> void:
	# "While putting down miners" is the condition, and it is read three ways because it is
	# three facts: the Build Gun is in hand, the Machine tool is out, and what is on it mines.
	# A player holding a rifle or about to place a Smelter is not looking for ore.
	var sim: Simulation = _scanning_run(_ore_layout())
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_true(view.ore_scanner_ping_count() > 0, "a Miner is on the gun and there is ore")

	sim.step([InputAction.select_machine(0, sim.query_definitions().machine_index("smelter_mk1"))])
	view.sync(sim)
	assert_eq(view.ore_scanner_ping_count(), 0, "a Smelter is not a reason to hunt for ore")

	sim.step([InputAction.select_machine(0, sim.query_definitions().machine_index("miner_mk1"))])
	view.sync(sim)
	assert_true(view.ore_scanner_ping_count() > 0, "and picking the Miner again brings it back")

	sim.step([InputAction.set_build_mode(0, false)])
	view.sync(sim)
	assert_eq(view.ore_scanner_ping_count(), 0, "nor is a rifle")
	view.free()


func test_the_scanner_runs_out_to_the_ore_the_objective_line_names() -> void:
	# One authority for where a player is being sent — `query_nearest_workable_node` — so the
	# trail and the line cannot point at different Nodes. The pings lie on the ground between
	# the two, in the ore's own colour, which is what makes the trail and its destination read
	# as one mark rather than as two.
	var sim: Simulation = _scanning_run(_ore_layout())
	var view: WorldView = WorldView.new()
	view.sync(sim)

	var node: int = sim.query_nearest_workable_node(0)
	var target: FixedVec2 = sim.query_tile_centre_metres(sim.query_node_tile(node))
	var at: FixedVec2 = sim.query_player_position(0)
	var span: float = Vector2(
		Fixed.to_float(target.x) - Fixed.to_float(at.x),
		Fixed.to_float(target.z) - Fixed.to_float(at.z)
	).length()

	assert_true(view.ore_scanner_ping_count() > 0, "the scanner is running")
	for ping: int in range(view.ore_scanner_ping_count()):
		var p: Vector3 = view.ore_scanner_ping_position(ping)
		var from_player: float = Vector2(
			p.x - Fixed.to_float(at.x), p.z - Fixed.to_float(at.z)
		).length()
		assert_true(
			from_player <= span + 1.0, "no ping overshoots the ore, got %f of %f" % [from_player, span]
		)
		var off_line: float = Vector2(
			p.x - Fixed.to_float(at.x), p.z - Fixed.to_float(at.z)
		).distance_to(
			Vector2(
				Fixed.to_float(target.x) - Fixed.to_float(at.x),
				Fixed.to_float(target.z) - Fixed.to_float(at.z)
			).normalized() * from_player
		)
		assert_true(off_line < 0.01, "and every ping is on the line to it, got %f" % off_line)
		assert_eq(
			view.ore_scanner_ping_colour(ping).r,
			WorldView.ORE_IRON_COLOUR.r,
			"in the ore's own colour"
		)
	view.free()


func test_the_pulse_travels_and_repeats_on_the_tick_rather_than_on_a_clock() -> void:
	# Two Runs down the same script look the same, which they could not if a pulse were
	# driven by elapsed seconds or by how many frames the renderer happened to draw. The head
	# is a function of `query_tick`, so it advances when the Simulation does, it does not move
	# on a frame that stepped nothing, and it comes back round to exactly where it was one
	# period later.
	var sim: Simulation = _scanning_run(_ore_layout())
	var view: WorldView = WorldView.new()

	view.sync(sim)
	var opening: float = _scanner_head(view)
	var pattern: Array = _scanner_pattern(view)

	# One tick changes the sweep — the pings fade as the head moves past them — but it does
	# not necessarily move the *head*, because the pings are laid every
	# `SCANNER_STEP_METRES` and a tick carries the sweep a fraction of that. Both halves are
	# worth asserting: the first is what makes it look alive, the second that it travels.
	sim.step([])
	view.sync(sim)
	assert_ne(_scanner_pattern(view), pattern, "a tick moves the sweep on")
	for tick: int in range(10):
		sim.step([])
	view.sync(sim)
	assert_true(_scanner_head(view) > opening, "and carries the head further out")

	view.sync(sim)
	assert_eq(
		_scanner_pattern(view),
		_scanner_pattern(view),
		"and a frame that stepped nothing draws the same sweep: the renderer has no clock"
	)

	# Eleven ticks have been stepped since the opening sync, so this lands the Run exactly
	# one period on from it.
	for tick: int in range(WorldView.SCANNER_PERIOD_TICKS - 11):
		sim.step([])
	view.sync(sim)
	assert_eq(_scanner_pattern(view), pattern, "one whole period later the sweep is back")
	view.free()


## How far out the leading ping of the sweep has got, in metres from the player's feet. The
## first ping is laid at the feet and never moves, so the *head* is the furthest one lit.
func _scanner_head(view: WorldView) -> float:
	var furthest: float = 0.0
	var foot: Vector3 = view.ore_scanner_ping_position(0)
	for ping: int in range(view.ore_scanner_ping_count()):
		furthest = maxf(furthest, foot.distance_to(view.ore_scanner_ping_position(ping)))
	return furthest


## Every lit ping and what it is painted, as one comparable value.
func _scanner_pattern(view: WorldView) -> Array:
	var pattern: Array = []
	for ping: int in range(view.ore_scanner_ping_count()):
		pattern.append([view.ore_scanner_ping_position(ping), view.ore_scanner_ping_colour(ping)])
	return pattern


func test_the_scanner_goes_quiet_once_a_miner_is_working_ore() -> void:
	# `Objective`'s shape, with nothing remembered and nothing to skip: a player who walks
	# straight to the ore and places a Miner should barely register that a scanner existed.
	# And it is the same question the objective line goes quiet on, so the two cannot
	# disagree about whether the opening has taught itself.
	var layout: MapLayout = MapLayout.empty()
	layout.nest_tile = Vector3i(0, 0, 0)
	layout.add_node(Vector3i(0, 0, 14), "iron_ore", 1)
	layout.add_node(Vector3i(0, 0, 26), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = _scanning_run(layout)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_true(view.ore_scanner_ping_count() > 0, "nothing is mining yet")

	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("miner_mk1"), Vector3i(0, 0, 14)
		)
	])
	view.sync(sim)
	assert_eq(
		view.ore_scanner_ping_count(),
		0,
		"the Factory is mining, so the player has no further use for being led anywhere"
	)
	view.free()


func test_the_scanner_does_not_grow_the_scene_tree() -> void:
	var sim: Simulation = _scanning_run(_ore_layout())
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var children: int = view.get_child_count()
	for tick: int in range(40):
		sim.step([])
		view.sync(sim)
	assert_true(view.ore_scanner_ping_count() > 0, "still scanning")
	assert_eq(view.get_child_count(), children, "every ping is one instance of one MultiMesh")
	view.free()


func test_every_enemy_surface_wears_the_graded_atlas_rather_than_the_packs_own() -> void:
	# #75. The committed KayKit atlas is a cold bone-white at eight times the luminance of the
	# darkest cell a Crawler wears, and #38's answer was one dark tint per kind — which cannot
	# change a ratio, so what shipped was a pale skull on a near-black body. The surface is
	# `tools/assets/enemy_grade.py`'s graded copy now, and the assertion is that the graded
	# file is what actually reaches the shader: a grade nothing samples is `prop_grade.py`'s
	# own opening defect, and the only way to catch it is from this side of the seam.
	var sim: Simulation = _threatened_sim()
	var view: WorldView = WorldView.new()
	view.sync(sim)
	for kind: int in [Simulation.ENEMY_KIND_CRAWLER, Simulation.ENEMY_KIND_BREAKER]:
		assert_eq(
			view.enemy_surface_texture_path(kind),
			WorldView.ENEMY_GRADED_ATLAS,
			"kind %d is painted with %s" % [kind, view.enemy_surface_texture_path(kind)]
		)
	view.free()


func test_an_enemy_is_metal_because_the_light_in_this_world_is_tuned_for_metal() -> void:
	# `_sync_scenery` takes ambient and reflections off the sky precisely because the generated
	# surfaces are mostly metal and a metal lit by an ambient *colour* has nothing to reflect.
	# Until #75 a Crawler was the one thing in the world that was not metal — 0.05 metallic at
	# 0.88 roughness — so it had nothing to catch, and measured off a `swarm bare` render it sat
	# at a seventh of the luminance of the ground it was standing on.
	var sim: Simulation = _threatened_sim()
	var view: WorldView = WorldView.new()
	view.sync(sim)
	for kind: int in [Simulation.ENEMY_KIND_CRAWLER, Simulation.ENEMY_KIND_BREAKER]:
		assert_true(
			view.enemy_surface_metallic(kind) >= 0.5,
			"kind %d is %f metallic" % [kind, view.enemy_surface_metallic(kind)]
		)
