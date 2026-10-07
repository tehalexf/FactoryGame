## The float-to-fixed boundary, which is the one place in the project where a float
## device reading becomes a Simulation quantity.
##
## This is the most likely place in the whole first-person layer for a determinism leak,
## so it gets a contract of its own rather than smoke coverage: it is a leaf utility
## like `Fixed`, with rounding behaviour that nothing else can observe.
##
## The rule it keeps: whatever crosses is *floored* to a fixed-point integer or to a
## whole tile before it is handed to an Input Action, so the intent recorded in a replay
## is an integer and the float that produced it is never consulted again.
extends TestCase

## The 2 m grid, per DESIGN.md.
const TILE: float = 2.0


# ── Mouse travel ──────────────────────────────────────────────────────────────

func test_whole_pixels_convert_exactly() -> void:
	assert_eq(InputQuantiser.pixels_to_fixed(0.0), 0)
	assert_eq(InputQuantiser.pixels_to_fixed(1.0), Fixed.ONE)
	assert_eq(InputQuantiser.pixels_to_fixed(-3.0), -3 * Fixed.ONE)


func test_fractional_pixels_floor_rather_than_round() -> void:
	# The same rounding rule as every lossy operation in `Fixed`: toward negative
	# infinity, so the sign of the input never changes the rule being applied. A
	# high-resolution mouse reports fractional pixels, and two machines must agree
	# on what a fraction becomes.
	assert_eq(InputQuantiser.pixels_to_fixed(1.5), 98304, "1.5 × 65536")
	assert_eq(InputQuantiser.pixels_to_fixed(0.3), 19660, "19660.8 floors to 19660")
	assert_eq(InputQuantiser.pixels_to_fixed(-0.3), -19661, "and -19660.8 floors to -19661")


func test_an_absurd_reading_does_not_overflow_into_nonsense() -> void:
	# A device driver glitch, or a window resize mid-frame. Clamped to something
	# finite, because an unbounded intent is an unbounded turn.
	var huge: int = InputQuantiser.pixels_to_fixed(1.0e12)
	assert_true(huge > 0, "still positive")
	assert_true(
		huge <= InputAction.MAX_LOOK_PIXELS,
		"and inside what a LOOK action will carry, got %d" % huge
	)


func test_a_reading_that_is_not_a_number_becomes_nothing() -> void:
	# NAN compares false against everything, so an unguarded conversion would make it
	# through as an arbitrary integer and desync a Run.
	assert_eq(InputQuantiser.pixels_to_fixed(NAN), 0)
	assert_eq(InputQuantiser.pixels_to_fixed(INF), InputAction.MAX_LOOK_PIXELS)


# ── Throttles ─────────────────────────────────────────────────────────────────

func test_a_full_throttle_is_exactly_full() -> void:
	assert_eq(InputQuantiser.throttle_to_fixed(1.0), Fixed.ONE)
	assert_eq(InputQuantiser.throttle_to_fixed(-1.0), -Fixed.ONE)
	assert_eq(InputQuantiser.throttle_to_fixed(0.0), 0)


func test_a_throttle_beyond_full_saturates() -> void:
	assert_eq(InputQuantiser.throttle_to_fixed(4.0), Fixed.ONE)
	assert_eq(InputQuantiser.throttle_to_fixed(-4.0), -Fixed.ONE)
	assert_eq(InputQuantiser.throttle_to_fixed(NAN), 0)


func test_a_partial_throttle_floors() -> void:
	assert_eq(InputQuantiser.throttle_to_fixed(0.5), Fixed.HALF)
	assert_eq(InputQuantiser.throttle_to_fixed(0.3), 19660, "19660.8 floors to 19660")


# ── Where the Build Gun is aimed ──────────────────────────────────────────────
# The aim is a whole tile, so what crosses into the Simulation is an integer
# coordinate and the camera ray that produced it is never consulted again.

func test_looking_straight_down_aims_at_the_tile_underfoot() -> void:
	# Tile (0,0,0) spans 0 m to 2 m on both axes, so 5 m along x is tile 2 and 7 m
	# along z is tile 3.
	assert_eq(
		InputQuantiser.aimed_tile(Vector3(5.0, 10.0, 7.0), Vector3(0.0, -1.0, 0.0), 100.0, TILE),
		Vector3i(2, 0, 3)
	)


func test_negative_ground_floors_toward_negative_infinity() -> void:
	# -1 m is inside tile -1, not tile 0. Truncation toward zero would put the two
	# tiles either side of the origin in the same place.
	assert_eq(
		InputQuantiser.aimed_tile(Vector3(-1.0, 5.0, -3.0), Vector3(0.0, -1.0, 0.0), 100.0, TILE),
		Vector3i(-1, 0, -2)
	)


func test_a_level_look_aims_at_the_limit_of_reach() -> void:
	# A ray parallel to the ground never meets it. Rather than aiming at infinity, the
	# hologram sits at the end of the player's reach, which is what keeps it on screen.
	assert_eq(
		InputQuantiser.aimed_tile(Vector3(1.0, 1.7, 1.0), Vector3(0.0, 0.0, -1.0), 16.0, TILE),
		Vector3i(0, 0, -8),
		"16 m back from 1 m is -15 m, which is tile -8"
	)


func test_looking_at_the_sky_still_aims_somewhere_in_front() -> void:
	var tile: Vector3i = InputQuantiser.aimed_tile(
		Vector3(1.0, 1.7, 1.0), Vector3(0.0, 0.8, -0.6), 16.0, TILE
	)
	assert_true(tile.z < 0, "in front of the player, not behind them")
	assert_eq(tile.y, 0, "and on the ground layer, because that is the only one built on")


func test_a_distant_ground_hit_is_pulled_back_to_the_limit_of_reach() -> void:
	# From 20 m up at a shallow angle the ground is far away. The Build Gun's reach is
	# what keeps a player from laying a Factory out on the horizon.
	var reached: Vector3i = InputQuantiser.aimed_tile(
		Vector3(0.0, 20.0, 0.0), Vector3(0.0, -0.1, -0.995), 16.0, TILE
	)
	assert_true(
		reached.z >= -8, "within 16 m of the player, got z %d tiles away" % reached.z
	)


func test_the_aim_is_the_same_integer_every_time_for_the_same_look() -> void:
	# Not a tautology: it is the property a replay rests on. The same queried camera
	# produces the same tile, so a recorded build intent is reproducible from state
	# rather than from whatever the mouse did between frames.
	var first: Vector3i = InputQuantiser.aimed_tile(
		Vector3(3.25, 1.7, -4.125), Vector3(0.3, -0.5, -0.8), 16.0, TILE
	)
	var second: Vector3i = InputQuantiser.aimed_tile(
		Vector3(3.25, 1.7, -4.125), Vector3(0.3, -0.5, -0.8), 16.0, TILE
	)
	assert_eq(first, second)


# ── Pointing the camera from what the Simulation says ─────────────────────────

func test_a_yaw_of_zero_faces_along_negative_z() -> void:
	var forward: Vector3 = InputQuantiser.forward_vector(0, 0)
	assert_true(is_equal_approx(forward.z, -1.0), "expected -1, got %f" % forward.z)
	assert_true(absf(forward.x) < 0.001, "and nothing along x, got %f" % forward.x)


func test_a_quarter_turn_of_yaw_faces_along_negative_x() -> void:
	var forward: Vector3 = InputQuantiser.forward_vector(Fixed.QUARTER_TURN, 0)
	assert_true(is_equal_approx(forward.x, -1.0), "expected -1, got %f" % forward.x)
	assert_true(absf(forward.z) < 0.001, "and nothing along z, got %f" % forward.z)


func test_pitching_down_points_the_ray_at_the_ground() -> void:
	var forward: Vector3 = InputQuantiser.forward_vector(0, -Fixed.QUARTER_TURN)
	assert_true(is_equal_approx(forward.y, -1.0), "straight down, got %f" % forward.y)


# ── A hand tool's aim ─────────────────────────────────────────────────────────
# `aimed_tile` is the Build Gun's aim and only ever meets the ground, because building is
# flat and a hologram snaps to a floor tile. A wrench is held against a Machine's *body*,
# several metres up, so it crosses a different plane — and a level look that meets neither
# still has to land somewhere a player can see.

func test_a_level_look_at_eye_height_meets_the_tool_plane_it_is_level_with() -> void:
	# The camera is already on the plane, so the ray never crosses it and the answer falls
	# back to the limit of reach ahead of the player rather than to infinity.
	var tile: Vector3i = InputQuantiser.aimed_tile_at_height(
		Vector3(0.0, 2.0, 0.0), Vector3(0.0, 0.0, -1.0), 2.0, 10.0, 2.0
	)
	assert_eq(tile, Vector3i(0, 0, -5), "ten metres ahead, which is five tiles")


func test_looking_down_from_eye_height_meets_the_tool_plane_before_the_ground() -> void:
	# From 4 m up at forty-five degrees, the 2 m plane is 2 m ahead and the ground is 4 m
	# ahead. A wrench aims at the first of those; the Build Gun aims at the second.
	var camera: Vector3 = Vector3(0.0, 4.0, 0.0)
	var forward: Vector3 = Vector3(0.0, -1.0, -1.0)
	assert_eq(
		InputQuantiser.aimed_tile_at_height(camera, forward, 2.0, 20.0, 2.0),
		Vector3i(0, 0, -1),
		"two metres ahead: tile -1"
	)
	assert_eq(
		InputQuantiser.aimed_tile(camera, forward, 20.0, 2.0),
		Vector3i(0, 0, -2),
		"against four metres for the ground plane: tile -2"
	)


func test_looking_up_from_below_the_tool_plane_still_meets_it() -> void:
	# A player crouched under a gantry looking up at a Machine's body. The ray crosses the
	# plane going the other way, and the sign of the gap is what decides whether it does.
	var tile: Vector3i = InputQuantiser.aimed_tile_at_height(
		Vector3(0.0, 0.0, 0.0), Vector3(0.0, 1.0, -1.0), 2.0, 20.0, 2.0
	)
	assert_eq(tile, Vector3i(0, 0, -1), "two metres ahead, two metres up")


func test_a_tool_aim_is_pulled_back_to_the_limit_of_reach() -> void:
	# Bounded, like every other conversion in this module: an unbounded intent is an
	# unbounded aim. From 22 m up at a shallow angle the plane is 200 m ahead, and four
	# metres of reach is four metres of reach.
	var tile: Vector3i = InputQuantiser.aimed_tile_at_height(
		Vector3(0.0, 22.0, 0.0), Vector3(0.0, -0.1, -1.0), 2.0, 4.0, 2.0
	)
	assert_eq(tile, Vector3i(0, 0, -2), "four metres ahead, which is two tiles")


func test_a_tool_plane_that_is_not_a_number_is_reduced_rather_than_cast() -> void:
	# NAN compares false against everything, so an unguarded cast would let it through as an
	# arbitrary integer and desync a Run. Reduced to the ground plane instead.
	var tile: Vector3i = InputQuantiser.aimed_tile_at_height(
		Vector3(0.0, 4.0, 0.0), Vector3(0.0, -1.0, -1.0), NAN, 20.0, 2.0
	)
	assert_eq(tile, Vector3i(0, 0, -2), "the ground plane, four metres ahead")
