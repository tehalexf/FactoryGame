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
