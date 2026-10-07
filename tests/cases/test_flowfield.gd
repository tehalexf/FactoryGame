## The shared flowfield every Enemy steers by, through the Simulation façade.
##
## One field per destination, amortised across every Enemy — not a path per agent
## (DESIGN.md). The structural claim is observable from outside: the field answers for
## every ground tile on the Map whether or not an Enemy is standing there, which a
## per-agent path could not do.
extends TestCase

## The Nest at the origin, covering tiles (0,0) to (3,3). No Breach: these tests are
## about the field, and the field does not care whether anything is walking on it.
func _sim() -> Simulation:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(0, WorldGrid.GROUND_LAYER, 0)
	return Simulation.new(5, 1, null, layout)


func _tile(x: int, z: int) -> Vector3i:
	return Vector3i(x, WorldGrid.GROUND_LAYER, z)


# ── The field itself ──────────────────────────────────────────────────────────

func test_the_field_is_a_property_of_the_map_rather_than_of_any_enemy() -> void:
	var sim: Simulation = _sim()
	assert_eq(sim.query_enemy_count(), 0, "nothing is walking on it")
	assert_eq(
		sim.query_flow_distance_tiles(_tile(9, 1)),
		6,
		"and it still knows the way from a tile nine east of the Nest's anchor"
	)


func test_the_nest_is_the_destination_so_its_own_tiles_are_zero_away() -> void:
	var sim: Simulation = _sim()
	assert_eq(sim.query_flow_distance_tiles(_tile(0, 0)), 0, "the anchor")
	assert_eq(sim.query_flow_distance_tiles(_tile(3, 3)), 0, "the far corner of the footprint")
	assert_eq(
		sim.query_flow_direction(_tile(1, 1)),
		-1,
		"a tile already at the destination has nowhere to go"
	)


func test_the_whole_nest_footprint_is_the_destination_not_only_its_anchor() -> void:
	var sim: Simulation = _sim()
	# Tile (4,3) shares an edge with the Nest tile (3,3). Were the field seeded on the
	# anchor alone it would be four tiles away rather than one.
	assert_eq(sim.query_flow_distance_tiles(_tile(4, 3)), 1)


func test_distance_counts_whole_tiles_along_a_four_connected_walk() -> void:
	var sim: Simulation = _sim()
	assert_eq(sim.query_flow_distance_tiles(_tile(4, 1)), 1)
	assert_eq(sim.query_flow_distance_tiles(_tile(5, 1)), 2)
	assert_eq(sim.query_flow_distance_tiles(_tile(6, 1)), 3)
	assert_eq(
		sim.query_flow_distance_tiles(_tile(6, 5)),
		5,
		"three tiles east and two north of the footprint's corner, with no diagonals"
	)


func test_a_tile_points_at_the_neighbour_one_step_nearer_the_nest() -> void:
	var sim: Simulation = _sim()
	var direction: int = sim.query_flow_direction(_tile(6, 1))
	var step: Vector3i = WorldGrid.direction_step(direction)
	assert_eq(step, Vector3i(-1, 0, 0), "straight back down the lane towards the Nest")
	assert_eq(
		sim.query_flow_distance_tiles(_tile(6, 1) + step),
		sim.query_flow_distance_tiles(_tile(6, 1)) - 1,
		"and following it is always exactly one tile of progress"
	)


func test_every_tile_in_the_field_points_at_a_tile_one_step_nearer() -> void:
	# The sweep works in flat index space for speed, so the direction it records could in
	# principle disagree with what `WorldGrid.direction_step` means by it. This walks a
	# whole region of the field a tile at a time and catches any such mismatch — including
	# an x step that wrapped off one edge of the Map onto the other.
	var sim: Simulation = _sim()
	var smelter: int = sim.query_definitions().machine_index("smelter_mk1")
	sim.step([InputAction.build_machine(0, smelter, _tile(6, 2))])

	var checked: int = 0
	for x: int in range(-30, 31):
		for z: int in range(-30, 31):
			var here: Vector3i = _tile(x, z)
			var distance: int = sim.query_flow_distance_tiles(here)
			var direction: int = sim.query_flow_direction(here)
			if distance <= 0:
				assert_eq(direction, -1, "%s is at the destination or unreachable" % here)
				continue
			var step: Vector3i = WorldGrid.direction_step(direction)
			assert_eq(
				sim.query_flow_distance_tiles(here + step),
				distance - 1,
				"the way out of %s does not lead one tile nearer" % here
			)
			checked += 1
	assert_true(checked > 3000, "swept %d routed tiles" % checked)


func test_a_tile_on_the_edge_of_the_map_does_not_step_off_it() -> void:
	var edge: int = WorldGrid.HALF_EXTENT_TILES
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(0, WorldGrid.GROUND_LAYER, 0)
	var sim: Simulation = Simulation.new(5, 1, null, layout)
	# The west edge is 64 tiles out and the Nest is at the origin, so the far corner is
	# reachable by a walk that never leaves the Map: 64 east and 64 north, less the
	# footprint's three tiles on each axis.
	assert_eq(sim.query_flow_distance_tiles(_tile(-edge, -edge)), edge * 2)
	assert_eq(
		sim.query_flow_distance_tiles(_tile(edge, edge)),
		(edge - 3) * 2,
		"and the east corner is nearer by the footprint's reach"
	)


func test_following_the_field_from_anywhere_arrives_at_the_nest() -> void:
	var sim: Simulation = _sim()
	var walked: Vector3i = _tile(-20, 17)
	var steps: int = 0
	while not sim.query_nest_covers_tile(walked) and steps < 200:
		var direction: int = sim.query_flow_direction(walked)
		assert_true(direction != -1, "the field routes %s" % walked)
		walked += WorldGrid.direction_step(direction)
		steps += 1
	assert_true(sim.query_nest_covers_tile(walked), "arrived after %d tiles" % steps)


func test_a_tile_off_the_map_is_not_in_the_field() -> void:
	var sim: Simulation = _sim()
	var beyond: int = WorldGrid.HALF_EXTENT_TILES + 1
	assert_eq(sim.query_flow_distance_tiles(_tile(beyond, 0)), -1)
	assert_eq(sim.query_flow_direction(_tile(beyond, 0)), -1)
	assert_eq(
		sim.query_flow_direction(Vector3i(0, WorldGrid.GROUND_LAYER + 1, 8)),
		-1,
		"and the field is the ground, not the storeys reserved above it"
	)


# ── Obstructions ──────────────────────────────────────────────────────────────

func test_bare_ground_a_node_and_a_belt_do_not_obstruct_an_enemy() -> void:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(0, WorldGrid.GROUND_LAYER, 0)
	layout.add_node(_tile(8, 1), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(5, 1, null, layout)

	sim.step([InputAction.build_belt(0, _tile(6, 1), _tile(6, 4))])
	assert_eq(sim.query_belt_count(), 1, "the Belt was laid")

	assert_false(sim.query_tile_obstructs_enemies(_tile(8, 1)), "a Node is ground")
	assert_false(
		sim.query_tile_obstructs_enemies(_tile(6, 1)),
		"a Crawler crawls over a conveyor"
	)
	assert_eq(sim.query_flow_distance_tiles(_tile(6, 1)), 3, "so the route is unchanged")


func test_a_machine_obstructs_an_enemy() -> void:
	var sim: Simulation = _sim()
	assert_false(sim.query_tile_obstructs_enemies(_tile(5, 1)), "clear ground to begin with")

	var smelter: int = sim.query_definitions().machine_index("smelter_mk1")
	sim.step([InputAction.build_machine(0, smelter, _tile(4, 0))])
	assert_eq(sim.query_machine_count(), 1, "a 3x3 Smelter covering (4,0) to (6,2)")

	assert_true(sim.query_tile_obstructs_enemies(_tile(5, 1)), "its middle")
	assert_true(sim.query_tile_obstructs_enemies(_tile(6, 2)), "its far corner")
	assert_false(sim.query_tile_obstructs_enemies(_tile(7, 1)), "the tile past it is clear")


func test_the_field_routes_around_a_machine_rather_than_through_it() -> void:
	var sim: Simulation = _sim()
	var straight_through: int = sim.query_flow_distance_tiles(_tile(7, 1))
	assert_eq(straight_through, 4, "four tiles down the open lane")

	var smelter: int = sim.query_definitions().machine_index("smelter_mk1")
	sim.step([InputAction.build_machine(0, smelter, _tile(4, 0))])

	assert_eq(
		sim.query_flow_distance_tiles(_tile(5, 1)),
		-1,
		"the ground under the Machine is no longer walkable"
	)
	assert_eq(
		sim.query_flow_distance_tiles(_tile(7, 1)),
		6,
		"and the tile behind it is six tiles away, round the Machine's north face"
	)
	var detour: Vector3i = WorldGrid.direction_step(sim.query_flow_direction(_tile(7, 1)))
	assert_false(
		sim.query_tile_obstructs_enemies(_tile(7, 1) + detour),
		"the way out of that tile does not lead into the Machine"
	)


func test_demolishing_a_machine_opens_the_route_again() -> void:
	var sim: Simulation = _sim()
	var smelter: int = sim.query_definitions().machine_index("smelter_mk1")
	sim.step([InputAction.build_machine(0, smelter, _tile(4, 0))])
	assert_eq(sim.query_flow_distance_tiles(_tile(7, 1)), 6, "the detour while it stands")

	sim.step([InputAction.demolish(0, _tile(5, 1))])
	assert_eq(sim.query_machine_count(), 0, "it came back apart")
	assert_eq(
		sim.query_flow_distance_tiles(_tile(7, 1)),
		4,
		"and the field no longer describes a wall that is not there"
	)


func test_a_machine_can_seal_a_pocket_off_from_the_nest_entirely() -> void:
	# A Nest in the corner of the Map with its two open faces walled off by 3x3
	# Smelters, so there is genuinely no walk to it rather than merely a longer one.
	var corner: int = -WorldGrid.HALF_EXTENT_TILES
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(corner, WorldGrid.GROUND_LAYER, corner)
	var sim: Simulation = Simulation.new(5, 1, null, layout)

	var outside: Vector3i = Vector3i(corner + 7, WorldGrid.GROUND_LAYER, corner + 7)
	assert_eq(sim.query_flow_distance_tiles(outside), 8, "reachable to begin with")

	var smelter: int = sim.query_definitions().machine_index("smelter_mk1")
	var walls: Array = []
	# An L of 3x3 footprints: a column at x+5 spanning z+0 to z+5, meeting a row at z+6
	# spanning x+0 to x+5. The two map edges close the other two sides.
	for anchor: Vector2i in [Vector2i(5, 0), Vector2i(5, 3), Vector2i(0, 6), Vector2i(3, 6)]:
		walls.append(
			InputAction.build_machine(
				0,
				smelter,
				Vector3i(corner + anchor.x, WorldGrid.GROUND_LAYER, corner + anchor.y)
			)
		)
	sim.step(walls)
	assert_eq(sim.query_machine_count(), 4, "four Smelters sealing the corner")

	assert_eq(
		sim.query_flow_distance_tiles(outside),
		-1,
		"a tile the Nest cannot be walked to from has no route at all"
	)
	assert_eq(sim.query_flow_direction(outside), -1)
	assert_eq(
		sim.query_flow_distance_tiles(Vector3i(corner + 1, WorldGrid.GROUND_LAYER, corner + 1)),
		0,
		"and the Nest inside the pocket is still the destination"
	)


# ── Determinism ───────────────────────────────────────────────────────────────

func test_two_simulations_built_the_same_way_build_the_same_field() -> void:
	# The field is derived rather than hashed, so it has to be compared directly. Which
	# way a tile equidistant from two routes points is fixed by the grid's own direction
	# order, not by anything that happened during the Run.
	var one: Simulation = _sim()
	var two: Simulation = _sim()
	var smelter: int = one.query_definitions().machine_index("smelter_mk1")
	one.step([InputAction.build_machine(0, smelter, _tile(4, 0))])
	two.step([InputAction.build_machine(0, smelter, _tile(4, 0))])

	var differences: int = 0
	for x: int in range(-12, 13):
		for z: int in range(-12, 13):
			if one.query_flow_direction(_tile(x, z)) != two.query_flow_direction(_tile(x, z)):
				differences += 1
			if one.query_flow_distance_tiles(_tile(x, z)) != two.query_flow_distance_tiles(
				_tile(x, z)
			):
				differences += 1
	assert_eq(differences, 0, "625 tiles of field, identical both ways")


func test_the_field_does_not_depend_on_the_order_the_factory_was_built_in() -> void:
	var forwards: Simulation = _sim()
	var backwards: Simulation = _sim()
	var smelter: int = forwards.query_definitions().machine_index("smelter_mk1")
	var first: Vector3i = _tile(4, 0)
	var second: Vector3i = _tile(8, 4)

	forwards.step([InputAction.build_machine(0, smelter, first)])
	forwards.step([InputAction.build_machine(0, smelter, second)])
	backwards.step([InputAction.build_machine(0, smelter, second)])
	backwards.step([InputAction.build_machine(0, smelter, first)])

	var differences: int = 0
	for x: int in range(-4, 16):
		for z: int in range(-4, 16):
			if forwards.query_flow_direction(_tile(x, z)) != backwards.query_flow_direction(
				_tile(x, z)
			):
				differences += 1
	assert_eq(differences, 0, "the field is geography, not history")
