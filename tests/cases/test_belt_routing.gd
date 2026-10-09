## Laying a Belt by dragging a route out: what the route *is*, what refuses it, and
## what crosses the boundary when the drag is released.
##
## The route is the unit of intent. A player presses, drags and releases, and one
## `BUILD_BELT` action carries the whole thing — so a dragged route either lands or is
## refused, never half-lands. The shape is an L: a run along one axis, a corner, a run
## along the other, which is one corner per drag and a zigzag for the player who wants
## one.
##
## `BeltRoute` is pure arithmetic over tiles and is shared by three callers that must
## never disagree — the refusal projection, the apply, and the renderer drawing the
## preview. That sharing is the point of the module, so the tests here assert the
## agreement directly rather than asserting each caller separately.
extends TestCase


func _run(sim: Simulation, ticks: int) -> void:
	for tick: int in range(ticks):
		sim.step([])


# ── The shape of a route ──────────────────────────────────────────────────────

func test_a_straight_route_is_one_run_of_belt() -> void:
	var segments: Array = BeltRoute.segments(
		Vector3i(0, 0, 0), Vector3i(3, 0, 0), BeltRoute.ALONG_X
	)
	assert_eq(segments.size(), 1, "nothing to corner round")
	assert_eq(segments[0].from, Vector3i(0, 0, 0))
	assert_eq(segments[0].to, Vector3i(3, 0, 0))
	assert_eq(segments[0].direction, 0, "+x is direction 0")


func test_a_straight_route_ignores_the_corner_axis_it_was_given() -> void:
	# A drag that never left one axis has no corner to put anywhere, so the two
	# readings of the corner must describe the same run. Otherwise flipping the corner
	# mid-drag would silently move a straight Belt.
	var along_x: Array = BeltRoute.segments(
		Vector3i(0, 0, 0), Vector3i(0, 0, 4), BeltRoute.ALONG_X
	)
	var along_z: Array = BeltRoute.segments(
		Vector3i(0, 0, 0), Vector3i(0, 0, 4), BeltRoute.ALONG_Z
	)
	assert_eq(along_x.size(), 1)
	assert_eq(along_z.size(), 1)
	assert_eq(along_x[0].to, along_z[0].to, "one run either way")
	assert_eq(along_x[0].direction, along_z[0].direction)


func test_a_route_that_turns_a_corner_is_two_runs_that_meet_end_to_end() -> void:
	# Worked by hand: (0,0) to (3,2) turning along x first covers
	# (0,0) (1,0) (2,0) along x, then (3,0) (3,1) (3,2) along z. The first run stops one
	# short of the corner, because a Belt hands Items to the Belt whose run *starts* on
	# the tile past its own end — so the corner tile has to be the second run's entry.
	var segments: Array = BeltRoute.segments(
		Vector3i(0, 0, 0), Vector3i(3, 0, 2), BeltRoute.ALONG_X
	)
	assert_eq(segments.size(), 2)
	assert_eq(segments[0].from, Vector3i(0, 0, 0))
	assert_eq(segments[0].to, Vector3i(2, 0, 0), "one short of the corner")
	assert_eq(segments[0].direction, 0, "+x")
	assert_eq(segments[1].from, Vector3i(3, 0, 0), "the corner tile is the second entry")
	assert_eq(segments[1].to, Vector3i(3, 0, 2))
	assert_eq(segments[1].direction, 1, "+z")


func test_the_corner_axis_decides_which_way_the_route_bends() -> void:
	var segments: Array = BeltRoute.segments(
		Vector3i(0, 0, 0), Vector3i(3, 0, 2), BeltRoute.ALONG_Z
	)
	assert_eq(segments.size(), 2)
	assert_eq(segments[0].direction, 1, "+z first this time")
	assert_eq(segments[0].to, Vector3i(0, 0, 1), "one short of the corner")
	assert_eq(segments[1].from, Vector3i(0, 0, 2))
	assert_eq(segments[1].direction, 0, "+x second")
	assert_eq(segments[1].to, Vector3i(3, 0, 2))


func test_a_routes_tiles_are_the_tiles_its_runs_cover_entry_first() -> void:
	var tiles: Array[Vector3i] = BeltRoute.tiles(
		Vector3i(0, 0, 0), Vector3i(2, 0, 1), BeltRoute.ALONG_X
	)
	assert_eq(
		tiles,
		[
			Vector3i(0, 0, 0),
			Vector3i(1, 0, 0),
			Vector3i(2, 0, 0),
			Vector3i(2, 0, 1),
		] as Array[Vector3i],
		"no tile twice, and the corner counted once"
	)
	assert_eq(BeltRoute.length_tiles(Vector3i(0, 0, 0), Vector3i(2, 0, 1), BeltRoute.ALONG_X), 4)


func test_a_route_whose_ends_are_on_different_layers_is_no_route_at_all() -> void:
	var segments: Array = BeltRoute.segments(
		Vector3i(0, 0, 0), Vector3i(3, 1, 0), BeltRoute.ALONG_X
	)
	assert_eq(segments.size(), 0, "a Belt runs along one layer")
	assert_eq(BeltRoute.length_tiles(Vector3i(0, 0, 0), Vector3i(3, 1, 0), BeltRoute.ALONG_X), 0)


# ── Laying one ────────────────────────────────────────────────────────────────

func test_a_dragged_route_that_corners_lays_two_belts_that_connect() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.build_belt_route(0, Vector3i(0, 0, 0), Vector3i(3, 0, 2), BeltRoute.ALONG_X)])
	assert_eq(sim.query_belt_count(), 2, "one Belt per run")
	assert_eq(sim.query_belt_length_tiles(0), 3)
	assert_eq(sim.query_belt_length_tiles(1), 3)
	for tile: Vector3i in BeltRoute.tiles(Vector3i(0, 0, 0), Vector3i(3, 0, 2), BeltRoute.ALONG_X):
		assert_ne(sim.query_belt_at_tile(tile), -1, "%s is Belt" % tile)


func test_a_route_blocked_part_way_lays_nothing_at_all() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.build_wall(0, Vector3i(3, 0, 1))])
	sim.step([InputAction.build_belt_route(0, Vector3i(0, 0, 0), Vector3i(3, 0, 2), BeltRoute.ALONG_X)])
	assert_eq(sim.query_belt_count(), 0, "a dragged route lands whole or not at all")


func test_the_old_two_tile_belt_intent_still_lays_a_straight_run() -> void:
	# `BUILD_BELT` grew a corner argument rather than being replaced, so every recorded
	# script and every fixture written before the drag existed still means what it meant.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.build_belt(0, Vector3i(0, 0, 0), Vector3i(3, 0, 0))])
	assert_eq(sim.query_belt_count(), 1)
	assert_eq(sim.query_belt_length_tiles(0), 4)


# ── The refusal the preview reads ─────────────────────────────────────────────

func test_a_clear_route_refuses_nothing() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_eq(
		sim.query_belt_route_refusal(0, Vector3i(0, 0, 0), Vector3i(3, 0, 2), BeltRoute.ALONG_X),
		Simulation.Refusal.NONE
	)


func test_a_route_through_something_standing_is_refused_before_the_click() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.build_wall(0, Vector3i(2, 0, 0))])
	assert_eq(
		sim.query_belt_route_refusal(0, Vector3i(0, 0, 0), Vector3i(3, 0, 2), BeltRoute.ALONG_X),
		Simulation.Refusal.OCCUPIED,
		"the reason is on screen before the drag is released"
	)


func test_a_route_off_the_map_is_refused_before_the_click() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var outside: int = sim.query_grid_half_extent_tiles() + 1
	assert_eq(
		sim.query_belt_route_refusal(0, Vector3i(0, 0, 0), Vector3i(outside, 0, 2), BeltRoute.ALONG_X),
		Simulation.Refusal.OFF_THE_MAP
	)


func test_what_the_preview_is_told_and_what_the_drag_does_are_one_rule() -> void:
	# The projection is consulted by the renderer *and* by the apply. Two checks that
	# could disagree is the failure this asserts the absence of: every route that reads
	# as clear lands, and every route that reads as refused leaves the Factory alone.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.build_wall(0, Vector3i(2, 0, 2))])
	var checked: int = 0
	for to_x: int in range(0, 4):
		for to_z: int in range(0, 4):
			var to: Vector3i = Vector3i(to_x, 0, to_z)
			var probe: Simulation = Simulation.new(1, 1)
			probe.step([InputAction.build_wall(0, Vector3i(2, 0, 2))])
			var refusal: int = probe.query_belt_route_refusal(
				0, Vector3i(0, 0, 0), to, BeltRoute.ALONG_X
			)
			probe.step([
				InputAction.build_belt_route(0, Vector3i(0, 0, 0), to, BeltRoute.ALONG_X)
			])
			var laid: bool = probe.query_belt_count() > 0
			assert_eq(
				laid,
				refusal == Simulation.Refusal.NONE,
				"route to %s: refusal %d, laid %s" % [to, refusal, laid]
			)
			checked += 1
	assert_eq(checked, 16, "every route in the square was probed")


func test_a_route_nobody_is_dragging_is_refused() -> void:
	# The same fact about the *player* that refuses a Machine placement, and still not a
	# build mode: nothing here asks whether building is currently permitted, it asks
	# whether this player exists and is on their feet.
	var sim: Simulation = Simulation.new(1, 1)
	assert_eq(
		sim.query_belt_route_refusal(9, Vector3i(0, 0, 0), Vector3i(2, 0, 0), BeltRoute.ALONG_X),
		Simulation.Refusal.NO_SUCH_PLAYER,
		"there is no player 9 to be building"
	)


# ── A single tile ─────────────────────────────────────────────────────────────

func test_a_drag_that_never_moved_lays_one_tile_along_the_players_facing() -> void:
	# A one-tile Belt still has to be aimed, and the player's facing is the aim. Yaw is
	# authoritative Simulation state, so nothing crosses the boundary that was not
	# already a fact about the Run — the argument `PAINT` makes for carrying no aim at
	# all.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.build_belt_route(0, Vector3i(4, 0, 4), Vector3i(4, 0, 4), BeltRoute.ALONG_X)])
	assert_eq(sim.query_belt_count(), 1)
	assert_eq(sim.query_belt_length_tiles(0), 1)
	assert_eq(
		sim.query_belt_direction(0),
		WorldGrid.direction_from_turns(sim.query_player_yaw_turns(0)),
		"a fresh Run faces down -z, and so does the tile it lays"
	)


# ── Items go round the corner ─────────────────────────────────────────────────

func test_items_cross_the_corner_of_a_dragged_route() -> void:
	# The honesty check on the shape: two runs that meet end to end are two runs that
	# hand Items over, which is the whole reason the first one stops a tile short.
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var miner: int = sim.query_definitions().machine_index("miner_mk1")
	sim.step([InputAction.build_machine(0, miner, Vector3i(0, 0, 0))])
	# The Miner is 2x2 at the origin, so its south edge is z = 1 and the tile past it is
	# (1, 0, 2). The route runs +z for a tile, then turns and runs +x.
	sim.step([
		InputAction.build_belt_route(0, Vector3i(1, 0, 2), Vector3i(5, 0, 3), BeltRoute.ALONG_Z)
	])
	assert_eq(sim.query_belt_count(), 2)
	_run(sim, 600)
	assert_true(
		sim.query_belt_item_count(1) > 0,
		"ore that started on the first run reached the second"
	)


# ── What the Build Gun is holding ─────────────────────────────────────────────
# A Belt is not a Machine, so it cannot sit on the Build Gun's Machine list — but a
# player still has to be able to say "I am laying Belt now" and have the mouse mean it.
# That is a *tool*, and it is Simulation state for the three reasons build mode is: what
# somebody is holding is a fact about them, a replay has to reproduce the swap or every
# drag after it means something different, and in co-op it is worth drawing.
#
# **It is not a gate.** Nothing in the Simulation asks which tool is out before accepting
# anything: a `BUILD_BELT` sent with the Machine tool out lays Belt, and a `BUILD_MACHINE`
# sent with the Belt tool out places a Machine. What the tool decides is what the mouse
# means, which is `game/player_controller.gd`'s business and nowhere else's.

func test_a_run_opens_with_the_machine_tool_on_the_build_gun() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_eq(sim.query_player_build_tool(0), Simulation.BUILD_TOOL_MACHINE)
	assert_false(sim.query_player_is_laying_belt(0))


func test_the_build_gun_takes_the_belt_tool_and_gives_it_back() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	assert_true(sim.query_player_is_laying_belt(0))
	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_MACHINE)])
	assert_false(sim.query_player_is_laying_belt(0))


func test_asking_for_the_tool_already_out_leaves_the_hash_where_it_was() -> void:
	var held: Simulation = Simulation.new(1, 1)
	var idle: Simulation = Simulation.new(1, 1)
	held.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_MACHINE)])
	idle.step([])
	assert_eq(held.hash(), idle.hash(), "leaning on the key is not an act")


func test_which_tool_is_out_reaches_the_hash() -> void:
	var belt: Simulation = Simulation.new(1, 1)
	var machine: Simulation = Simulation.new(1, 1)
	belt.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	machine.step([])
	assert_ne(belt.hash(), machine.hash(), "a replay has to reproduce the swap")


func test_choosing_a_machine_puts_the_machine_tool_back_in_hand() -> void:
	# Scrolling to a Smelter or pressing its key is a player saying they want to place
	# one. Making them press the Belt key again to get out of Belt mode would be a mode
	# they have to escape rather than a tool they are holding.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	sim.step([InputAction.select_machine(0, sim.query_definitions().machine_index("smelter_mk1"))])
	assert_eq(sim.query_player_build_tool(0), Simulation.BUILD_TOOL_MACHINE)
	assert_eq(sim.query_player_selected_machine(0), "smelter_mk1")


func test_nothing_in_the_simulation_asks_which_tool_is_out() -> void:
	# The sibling of `test_nothing_in_the_simulation_asks_the_mode_for_permission`. A tool
	# decides what the mouse means and never what a player may do, so a route laid with
	# the Machine tool out lands exactly as one laid with the Belt tool does.
	var with_machine: Simulation = Simulation.new(1, 1)
	var with_belt: Simulation = Simulation.new(1, 1)
	with_belt.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	for sim: Simulation in [with_machine, with_belt]:
		sim.step([
			InputAction.build_belt_route(0, Vector3i(0, 0, 0), Vector3i(3, 0, 2), BeltRoute.ALONG_X)
		])
	assert_eq(with_machine.query_belt_count(), 2, "the Machine tool did not refuse a Belt")
	assert_eq(with_belt.query_belt_count(), 2)
	assert_eq(
		with_machine.query_belt_route_refusal(
			0, Vector3i(8, 0, 0), Vector3i(10, 0, 2), BeltRoute.ALONG_X
		),
		Simulation.Refusal.NONE,
		"and no refusal consults the tool either"
	)


# ── Press, drag, release ──────────────────────────────────────────────────────
# The controller's half, at the seam the rest of the input tests use: a sample built by
# hand in, Input Actions out. The drag anchor is the one thing remembered between ticks
# and it is the same category of thing as the mouse buffer — a reading on its way in, not
# a fact about the world. **The route is decided on release, and the route is what
# crosses.**

func _sample() -> PlayerController.DeviceSample:
	return PlayerController.DeviceSample.new()


## A Run with the Build Gun already drawn.
##
## A Run opens with the weapon out since #42, and every test below this line is about what
## the *Build Gun* makes of a click — so having it in hand is the fixture rather than the
## subject, and it is asked for in its own tick so no test is accidentally also about the
## swap routing the tick it happens on. `test_godot_layer_smoke` owns that claim.
func _building(seed_value: int = 1) -> Simulation:
	var sim: Simulation = Simulation.new(seed_value, 1)
	sim.step([InputAction.set_build_mode(0, true)])
	return sim


func test_the_belt_key_swaps_the_tool_on_the_build_gun_both_ways() -> void:
	var sim: Simulation = _building()
	var controller: PlayerController = PlayerController.new()

	var pressing: PlayerController.DeviceSample = _sample()
	pressing.belt_clicked = true
	var actions: Array = controller.actions_for_tick(sim, 0, pressing)
	var asked: Array = _of_kind(actions, InputAction.Kind.SET_BUILD_TOOL)
	assert_eq(asked.size(), 1, "one key, one swap")
	assert_eq(asked[0].build_tool_wanted(), Simulation.BUILD_TOOL_BELT)

	for action: InputAction in actions:
		sim.step([action])
	var again: Array = controller.actions_for_tick(sim, 0, pressing)
	var back: Array = _of_kind(again, InputAction.Kind.SET_BUILD_TOOL)
	assert_eq(back.size(), 1)
	assert_eq(
		back[0].build_tool_wanted(),
		Simulation.BUILD_TOOL_MACHINE,
		"a tool you are holding, not a mode you have to escape"
	)


func test_a_press_with_the_belt_tool_out_commits_nothing() -> void:
	var sim: Simulation = _building()
	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	var controller: PlayerController = PlayerController.new()

	var pressing: PlayerController.DeviceSample = _sample()
	pressing.place_clicked = true
	var actions: Array = controller.actions_for_tick(sim, 0, pressing)
	assert_eq(
		_of_kind(actions, InputAction.Kind.BUILD_BELT).size(),
		0,
		"the button going down is the start of a drag, not a Belt"
	)
	assert_eq(
		_of_kind(actions, InputAction.Kind.BUILD_MACHINE).size(),
		0,
		"and it is not a Machine either, because the Belt tool is what is out"
	)
	assert_true(controller.is_dragging_a_belt(), "the anchor is held until the release")
	assert_eq(controller.belt_drag_anchor(), BuildGun.aimed_tile(sim, 0))


func test_the_release_sends_the_route_from_where_the_press_was_to_where_the_aim_ended() -> void:
	var sim: Simulation = _building()
	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	var controller: PlayerController = PlayerController.new()

	var pressing: PlayerController.DeviceSample = _sample()
	pressing.place_clicked = true
	controller.actions_for_tick(sim, 0, pressing)
	var anchor: Vector3i = controller.belt_drag_anchor()

	# Turn the player, so the aim at the release is somewhere else entirely.
	for tick: int in range(30):
		sim.step([InputAction.look(0, Fixed.from_int(60), 0)])
	var ended_at: Vector3i = BuildGun.aimed_tile(sim, 0)
	assert_ne(ended_at, anchor, "the drag went somewhere")

	var releasing: PlayerController.DeviceSample = _sample()
	releasing.primary_released = true
	var routed: Array = _of_kind(
		controller.actions_for_tick(sim, 0, releasing), InputAction.Kind.BUILD_BELT
	)
	assert_eq(routed.size(), 1, "one drag, one route")
	assert_eq(routed[0].belt_from_tile(), anchor, "Items enter where the press was")
	assert_eq(routed[0].belt_to_tile(), ended_at, "and leave where the aim ended")
	assert_false(controller.is_dragging_a_belt(), "the anchor is spent")


func test_a_press_and_release_in_one_tick_is_one_tile_of_belt() -> void:
	var sim: Simulation = _building()
	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	var controller: PlayerController = PlayerController.new()

	var clicking: PlayerController.DeviceSample = _sample()
	clicking.place_clicked = true
	clicking.primary_released = true
	var routed: Array = _of_kind(
		controller.actions_for_tick(sim, 0, clicking), InputAction.Kind.BUILD_BELT
	)
	assert_eq(routed.size(), 1)
	assert_eq(routed[0].belt_from_tile(), routed[0].belt_to_tile(), "a click is a tile")


func test_the_right_button_flips_the_corner_instead_of_turning_a_hologram() -> void:
	# With the Belt tool out there is no hologram to turn, and the one thing about a route
	# a player chooses is which way it bends. So the same button does the one useful thing
	# in each hand — which is a tool deciding what the mouse means and not a gate.
	var sim: Simulation = _building()
	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	var controller: PlayerController = PlayerController.new()

	var pressing: PlayerController.DeviceSample = _sample()
	pressing.place_clicked = true
	controller.actions_for_tick(sim, 0, pressing)
	var natural: int = controller.belt_corner_axis(sim, 0)

	var flipping: PlayerController.DeviceSample = _sample()
	flipping.rotate_steps = 1
	var actions: Array = controller.actions_for_tick(sim, 0, flipping)
	assert_eq(
		_of_kind(actions, InputAction.Kind.ROTATE_BUILD).size(),
		0,
		"nothing to turn with the Belt tool out"
	)
	assert_ne(controller.belt_corner_axis(sim, 0), natural, "the corner went the other way")
	controller.actions_for_tick(sim, 0, flipping)
	assert_eq(controller.belt_corner_axis(sim, 0), natural, "and back")


func test_a_click_with_the_machine_tool_out_still_places_a_machine() -> void:
	# **The Ammo Press rather than whatever a Run opens on, and #55 is why it had to be
	# said.**
	# This test is about the *tool*: with the Machine tool out a click builds and does not
	# start a Belt drag. Since #55 a Run opens on the Miner, and a Miner aimed at bare rock
	# legitimately sends **no intent at all** — the Build Gun decides where it is pointing
	# and an aim with nowhere to put a Miner points nowhere (#42). That is a different rule
	# with its own tests, and it was silently standing in for this one's subject the moment
	# the opening selection changed under it. Naming a crafter makes the test about the tool
	# again, which is what it always claimed to be about — and the Press is what a Run
	# opened on before #55, so the test does exactly what it did.
	var sim: Simulation = _building()
	sim.step([
		InputAction.select_machine(
			0, sim.query_definitions().machine_index("ammo_press_mk1")
		)
	])
	var controller: PlayerController = PlayerController.new()
	var clicking: PlayerController.DeviceSample = _sample()
	clicking.place_clicked = true
	clicking.primary_released = true
	var actions: Array = controller.actions_for_tick(sim, 0, clicking)
	assert_eq(_of_kind(actions, InputAction.Kind.BUILD_MACHINE).size(), 1)
	assert_eq(_of_kind(actions, InputAction.Kind.BUILD_BELT).size(), 0)
	assert_false(controller.is_dragging_a_belt())


func test_choosing_a_machine_mid_drag_abandons_the_route() -> void:
	# Scrolling to a Smelter puts the Machine tool back, and a drag whose tool is gone is a
	# drag the player changed their mind about. It must not land on the next release.
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.set_build_tool(0, Simulation.BUILD_TOOL_BELT)])
	var controller: PlayerController = PlayerController.new()

	var pressing: PlayerController.DeviceSample = _sample()
	pressing.place_clicked = true
	controller.actions_for_tick(sim, 0, pressing)

	var scrolling: PlayerController.DeviceSample = _sample()
	scrolling.machine_steps = 1
	controller.actions_for_tick(sim, 0, scrolling)
	assert_false(controller.is_dragging_a_belt())

	var releasing: PlayerController.DeviceSample = _sample()
	releasing.primary_released = true
	assert_eq(
		_of_kind(
			controller.actions_for_tick(sim, 0, releasing), InputAction.Kind.BUILD_BELT
		).size(),
		0,
		"nothing crosses for a drag nobody is holding"
	)


func _of_kind(actions: Array, kind: int) -> Array:
	var found: Array = []
	for action: InputAction in actions:
		if action.kind == kind:
			found.append(action)
	return found


# ── Is it connected? ──────────────────────────────────────────────────────────
# A Belt pointed at a wall and a Belt feeding a Smelter look identical until you read a
# line of HUD text. These are the two projections the renderer marks them apart with, and
# they ask the questions `_load_from_port` and `_hand_off` already ask — so a Belt the
# renderer draws as connected is a Belt that really would hand an Item over.

func test_a_belt_laid_on_open_ground_is_connected_at_neither_end() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.build_belt(0, Vector3i(20, 0, 20), Vector3i(24, 0, 20))])
	assert_false(sim.query_belt_start_is_fed(0), "nothing behind it to load from")
	assert_false(sim.query_belt_end_is_connected(0), "and nothing past it to hand to")


func test_a_belt_off_a_machines_edge_is_fed_and_a_belt_into_one_is_connected() -> void:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	var definitions: Definitions = sim.query_definitions()
	# A 2x2 Miner at the origin, a 3x3 Smelter four tiles further along +z, and a Belt
	# running from the tile past the Miner's south edge to the tile before the Smelter's
	# north edge.
	sim.step([InputAction.build_machine(0, definitions.machine_index("miner_mk1"), Vector3i(0, 0, 0))])
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("smelter_mk1"), Vector3i(0, 0, 5))
	])
	sim.step([InputAction.build_belt(0, Vector3i(1, 0, 2), Vector3i(1, 0, 4))])
	assert_eq(sim.query_belt_count(), 1)
	assert_true(sim.query_belt_start_is_fed(0), "the Miner is behind its entry")
	assert_true(sim.query_belt_end_is_connected(0), "and the Smelter is past its exit")


func test_the_two_runs_of_a_cornered_route_are_connected_to_each_other() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([
		InputAction.build_belt_route(0, Vector3i(20, 0, 20), Vector3i(24, 0, 23), BeltRoute.ALONG_X)
	])
	assert_eq(sim.query_belt_count(), 2)
	assert_true(sim.query_belt_end_is_connected(0), "the first run hands to the second")
	assert_true(sim.query_belt_start_is_fed(1), "and the second is fed by the first")
	assert_false(sim.query_belt_start_is_fed(0), "the route as a whole still dangles")
	assert_false(sim.query_belt_end_is_connected(1))


func test_a_belt_into_the_nest_is_connected() -> void:
	# Goods reach the Delivery counter by Belt as well as by hand, so a Belt pointed into the
	# Nest's footprint is connected to something — and a player laying one deserves to see
	# that rather than find out by waiting.
	var sim: Simulation = Simulation.new(1, 1)
	var nest: Vector3i = sim.query_nest_tile()
	sim.step([
		InputAction.build_belt(
			0, Vector3i(nest.x, nest.y, nest.z - 4), Vector3i(nest.x, nest.y, nest.z - 1)
		)
	])
	assert_eq(sim.query_belt_count(), 1, "the run stops short of the footprint")
	assert_true(sim.query_belt_end_is_connected(0))


func test_demolishing_what_a_belt_fed_leaves_the_belt_dangling() -> void:
	# The projection is asked every frame and remembers nothing, which is the whole reason
	# there is no stored connection to go stale (CLAUDE.md: Belts connect by adjacency, and
	# nothing else).
	var sim: Simulation = Simulation.new(1, 1)
	sim.step([InputAction.build_belt(0, Vector3i(20, 0, 20), Vector3i(22, 0, 20))])
	sim.step([InputAction.build_belt(0, Vector3i(23, 0, 20), Vector3i(25, 0, 20))])
	assert_true(sim.query_belt_end_is_connected(0))
	sim.step([InputAction.demolish(0, Vector3i(23, 0, 20))])
	assert_false(sim.query_belt_end_is_connected(0), "nothing stored, so nothing stale")
