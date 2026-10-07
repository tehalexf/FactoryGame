## The grid, through the Simulation façade.
##
## DESIGN.md fixes the grid early because it is expensive to change: 2 m tiles,
## `Vector3i` coordinates, flat building only for now with 4 m storeys reserved so
## discrete floors can be switched on without a rewrite. These assert the rules a
## later ticket would have to deliberately change rather than accidentally drift.
extends TestCase


func test_a_tile_is_two_metres_across() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_eq(sim.query_tile_size_metres(), Fixed.from_int(2), "DESIGN.md fixes a 2 m grid")


func test_layer_zero_is_buildable() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_true(sim.query_is_buildable_tile(Vector3i(0, 0, 0)))
	assert_true(sim.query_is_buildable_tile(Vector3i(5, 0, -7)))


func test_no_layer_above_or_below_zero_is_buildable() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_false(sim.query_is_buildable_tile(Vector3i(0, 1, 0)), "flat building only, for now")
	assert_false(sim.query_is_buildable_tile(Vector3i(0, -1, 0)))


func test_a_tile_outside_the_map_is_not_buildable() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var outside: int = sim.query_grid_half_extent_tiles() + 1
	assert_false(sim.query_is_buildable_tile(Vector3i(outside, 0, 0)))
	assert_false(sim.query_is_buildable_tile(Vector3i(0, 0, -outside)))


func test_a_tile_centre_is_half_a_tile_in_from_its_corner() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	# Tile (0,0,0) spans 0 m to 2 m on both axes, so its centre is (1 m, 1 m).
	var origin: FixedVec2 = sim.query_tile_centre_metres(Vector3i(0, 0, 0))
	assert_eq(origin.x, Fixed.from_int(1))
	assert_eq(origin.z, Fixed.from_int(1))
	# Tile (3,0,-2) spans 6 m to 8 m and -4 m to -2 m, so its centre is (7 m, -3 m).
	var offset: FixedVec2 = sim.query_tile_centre_metres(Vector3i(3, 0, -2))
	assert_eq(offset.x, Fixed.from_int(7))
	assert_eq(offset.z, Fixed.from_int(-3))


func test_a_storey_is_four_metres_so_floors_can_be_switched_on_later() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	assert_eq(sim.query_layer_height_metres(0), 0, "layer 0 is the ground")
	assert_eq(
		sim.query_layer_height_metres(1),
		Fixed.from_int(4),
		"DESIGN.md reserves a 4 m storey height for vertical building"
	)


# ── Which way a player is facing, as a grid direction ─────────────────────────
# A Belt runs along one of four axes, so laying one along the way a player is looking
# means rounding a continuous angle to the nearest of four. Pure grid geometry, so it
# lives with the grid rather than in the controller that needs it — the Turret that has
# to face a direction will want the same answer.

func test_facing_forward_is_the_negative_z_direction() -> void:
	# Yaw 0 looks down -z, Godot's forward, which is direction 3 in the grid's order.
	assert_eq(WorldGrid.direction_from_turns(0), 3)


func test_each_quarter_turn_is_the_next_direction_round() -> void:
	assert_eq(WorldGrid.direction_from_turns(Fixed.QUARTER_TURN), 2, "a quarter left is -x")
	assert_eq(WorldGrid.direction_from_turns(2 * Fixed.QUARTER_TURN), 1, "half round is +z")
	assert_eq(WorldGrid.direction_from_turns(3 * Fixed.QUARTER_TURN), 0, "three quarters is +x")


func test_an_angle_between_two_directions_rounds_to_the_nearer() -> void:
	# A fifth of a turn is 72 degrees, nearer the quarter turn's 90 than zero.
	assert_eq(WorldGrid.direction_from_turns(Fixed.ONE / 5), 2)
	# A tenth is 36 degrees, nearer zero.
	assert_eq(WorldGrid.direction_from_turns(Fixed.ONE / 10), 3)


func test_an_angle_outside_one_revolution_still_names_a_direction() -> void:
	assert_eq(WorldGrid.direction_from_turns(5 * Fixed.TURN), 3, "five turns is no turn")
	assert_eq(WorldGrid.direction_from_turns(-Fixed.QUARTER_TURN), 0, "and backwards wraps")
