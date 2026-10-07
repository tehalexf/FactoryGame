## The build grid: what a tile is, where one sits in metres, and which tiles may be
## built on.
##
## DESIGN.md fixes these numbers early because they are expensive to change — a 2 m
## tile, Machines 2x2 to 4x4 tiles, a 1.8 m player, Belts one tile. Coordinates are
## `Vector3i` from the start even though building is flat for now, with a 4 m storey
## height reserved, so switching discrete floors on later is a change to
## `VERTICAL_BUILDING_ENABLED` and the layer range it governs rather than a rewrite
## of every call site.
##
## Pure rules and arithmetic, no state. The Simulation owns what is *on* the grid;
## this owns what the grid *is*, which is why it can be shared by placement,
## rendering projections and (later) the flowfield without any of them agreeing on a
## convention separately.
##
## Horizontal positions are fixed-point metres (ADR 0002). `Vector3i` is an integer
## vector, so it crosses the purity rules unharmed; `Vector3` would not.
class_name WorldGrid
extends RefCounted

## Tile edge length in whole metres.
const TILE_SIZE_METRES: int = 2

## Height of one storey in whole metres. Reserved, not yet reachable.
const STOREY_HEIGHT_METRES: int = 4

## Flat building only, for now. Flipping this true is what enables discrete floors;
## `buildable_layers` is the one place that reads it.
const VERTICAL_BUILDING_ENABLED: bool = false

## The ground layer, and the only buildable one while building is flat.
const GROUND_LAYER: int = 0

## Highest layer vertical building would reach, once enabled.
const TOP_LAYER: int = 3

## How far the Map extends from the origin, in tiles, on both horizontal axes. The
## Map is handcrafted and finite (GLOSSARY.md), so a tile outside it is not a tile.
const HALF_EXTENT_TILES: int = 64


## Tile edge length in fixed-point metres.
static func tile_size_metres() -> int:
	return Fixed.from_int(TILE_SIZE_METRES)


## The highest layer that may be built on. Flat building answers with the ground.
static func highest_buildable_layer() -> int:
	if VERTICAL_BUILDING_ENABLED:
		return TOP_LAYER
	return GROUND_LAYER


## Whether a tile is inside the Map at all, ignoring the layer rule.
static func is_within_extent(tile: Vector3i) -> bool:
	if absi(tile.x) > HALF_EXTENT_TILES or absi(tile.z) > HALF_EXTENT_TILES:
		return false
	return tile.y >= GROUND_LAYER and tile.y <= TOP_LAYER


## Whether something may be built on a tile: inside the Map, and on a layer the
## current build rules allow.
static func is_buildable(tile: Vector3i) -> bool:
	if not is_within_extent(tile):
		return false
	return tile.y >= GROUND_LAYER and tile.y <= highest_buildable_layer()


## The centre of a tile in fixed-point metres, on the horizontal plane. Tile (0,0,0)
## spans 0 m to 2 m on both axes, so its centre is (1 m, 1 m).
static func tile_centre_metres(tile: Vector3i) -> FixedVec2:
	var half: int = Fixed.from_rational(TILE_SIZE_METRES, 2)
	return FixedVec2.new(
		Fixed.from_int(tile.x * TILE_SIZE_METRES) + half,
		Fixed.from_int(tile.z * TILE_SIZE_METRES) + half
	)


## The floor height of a layer in fixed-point metres. 0 for the ground.
static func layer_height_metres(layer: int) -> int:
	return Fixed.from_int(layer * STOREY_HEIGHT_METRES)


## Whether a footprint anchored at `origin`, `size_x` by `size_z` tiles, covers
## `tile`. A footprint grows along +x and +z from its origin tile and stays on one
## layer.
static func footprint_covers(origin: Vector3i, size_x: int, size_z: int, tile: Vector3i) -> bool:
	if tile.y != origin.y:
		return false
	if tile.x < origin.x or tile.x >= origin.x + size_x:
		return false
	return tile.z >= origin.z and tile.z < origin.z + size_z


## A footprint turned by `rotation` quarter turns, as (size along x, size along z).
##
## The anchor does not move. A footprint still grows along +x and +z from the tile it
## was placed on, so a quarter or three-quarter turn swaps the extents and a half turn
## leaves them alone. That is one convention rather than two: placement validation,
## the renderer and the mesh generator all ask this same question and get the same
## answer, and no caller needs its own opinion about where a turned Machine's origin
## went.
static func rotated_footprint(size_x: int, size_z: int, rotation: int) -> Vector2i:
	if wrap_rotation(rotation) % 2 == 0:
		return Vector2i(size_x, size_z)
	return Vector2i(size_z, size_x)


## A rotation reduced to [0, DIRECTION_COUNT). Rotating past the fourth quarter comes
## back round, and rotating backwards wraps the other way.
static func wrap_rotation(rotation: int) -> int:
	return rotation - Fixed.floor_div(rotation, DIRECTION_COUNT) * DIRECTION_COUNT


## Whether two footprints share a tile.
static func footprints_overlap(
	a_origin: Vector3i, a_size_x: int, a_size_z: int,
	b_origin: Vector3i, b_size_x: int, b_size_z: int
) -> bool:
	if a_origin.y != b_origin.y:
		return false
	if a_origin.x + a_size_x <= b_origin.x or b_origin.x + b_size_x <= a_origin.x:
		return false
	return not (a_origin.z + a_size_z <= b_origin.z or b_origin.z + b_size_z <= a_origin.z)


## Whether every tile of a footprint may be built on. A Machine half off the Map is
## refused rather than clipped.
static func footprint_is_buildable(origin: Vector3i, size_x: int, size_z: int) -> bool:
	if size_x < 1 or size_z < 1:
		return false
	if not is_buildable(origin):
		return false
	return is_buildable(Vector3i(origin.x + size_x - 1, origin.y, origin.z + size_z - 1))


# ── Directions ────────────────────────────────────────────────────────────────
# A Belt runs along one axis, so a direction is one of four. Held as a small
# integer because it reaches the state hash and the network wire; the step it means
# is resolved here and nowhere else, so no caller gets its own opinion about which
# way +z is.

## How many directions a Belt can run in. Four, because the grid is square and
## diagonal Belts do not exist (DESIGN.md).
const DIRECTION_COUNT: int = 4

## +x, +z, -x, -z, indexed by direction. Counter-clockwise order, so rotating a
## Belt later is `(direction + 1) % DIRECTION_COUNT`.
const DIRECTION_STEPS: Array = [
	Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1)
]


## The one-tile step a direction means. The zero vector for an unknown direction,
## so a malformed value moves nothing rather than crashing a Run.
static func direction_step(direction: int) -> Vector3i:
	if direction < 0 or direction >= DIRECTION_COUNT:
		return Vector3i.ZERO
	return DIRECTION_STEPS[direction]


## The direction from one tile to another, or -1 when they do not lie on one axis
## of one layer. Two identical tiles have no direction either: a run of one tile
## still has to be aimed.
static func direction_from_to(from: Vector3i, to: Vector3i) -> int:
	if from.y != to.y:
		return -1
	if from.x != to.x and from.z != to.z:
		return -1
	for direction: int in range(DIRECTION_COUNT):
		var step: Vector3i = DIRECTION_STEPS[direction]
		if step.x != 0 and to.x != from.x and signi(to.x - from.x) == step.x:
			return direction
		if step.z != 0 and to.z != from.z and signi(to.z - from.z) == step.z:
			return direction
	return -1


## How many tiles a straight run from one tile to another covers, counting both
## ends. 0 when the two tiles do not lie on one axis of one layer.
static func tiles_between(from: Vector3i, to: Vector3i) -> int:
	if direction_from_to(from, to) == -1:
		return 0
	return absi(to.x - from.x) + absi(to.z - from.z) + 1
