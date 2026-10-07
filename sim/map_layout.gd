## Where the Nodes are: the geography a Run starts from.
##
## One Map exists and it is handcrafted (GLOSSARY.md), so this is a layout rather
## than a generator — no seed is consulted and nothing here is random. Nodes, the
## Nest and the Breaches; Hives join it with the ticket that sends Enemies out onto
## the Map rather than into the Nest.
##
## Deliberately not in `content/`. The files there are the *definitions* a Factory
## is built from — Machines, Recipes, tuning — and are hot-reloadable mid-Run.
## Geography is not: moving a Node under a Factory that is already standing on it is
## not a balance change, it is a different Map. When the Map becomes an authored
## file, this is the single place that changes.
##
## Nodes are **inexhaustible** (DESIGN.md). That is a design decision, not an
## oversight: a 40-hour Factory must never need relocating, so Depth tiers gate
## value instead of a quantity running down. There is consequently no "remaining"
## field here, and nothing in the Simulation subtracts from a Node.
##
## Sorted canonically on construction, so the index space is a function of the Map
## and not of the order the rows happen to be written in — the same property
## `Definitions` gives Machines and Recipes, and for the same reason: these indices
## reach the state hash.
class_name MapLayout
extends RefCounted

## How many tiles on a side the Nest occupies. 4x4, which is the largest footprint
## DESIGN.md allows and matches the `nest` row in `content/machine_bodies.csv` that
## the mesh is generated from.
##
## Here rather than in `content/machines.csv` because **the Nest is not a Machine**:
## DESIGN.md lists it alongside Belt and Wall, outside the eight Machines, and it
## runs no Recipe, draws no Power and cannot be built or demolished. Its *health* is
## tuning, because that is a balance number; its size and position are geography,
## because moving the thing a Run is defending is a different Map.
const NEST_FOOTPRINT_TILES: int = 4

## Tile each Node sits on, as parallel coordinate arrays. One tile per Node; a
## Miner covers it with its footprint.
var node_tile_x: PackedInt64Array = PackedInt64Array()
var node_tile_y: PackedInt64Array = PackedInt64Array()
var node_tile_z: PackedInt64Array = PackedInt64Array()

## The Resource each Node yields, as an Item id. The Items that exist are exactly
## the ones the Recipes mention, so a Node naming one that no Recipe produces is a
## Node nothing can mine — which is why the id is checked against the definitions
## at extraction time rather than assumed.
var node_resource: PackedStringArray = PackedStringArray()

## The Depth tier each Node sits at. Greater Depth is more valuable Resource, more
## Power and more Heat (GLOSSARY.md); the tier gating itself arrives with Depth.
var node_depth: PackedInt64Array = PackedInt64Array()

## Where the Nest stands: the anchor of a `NEST_FOOTPRINT_TILES` square footprint,
## growing along +x and +z like a Machine's. The structure the Run is about — its
## destruction ends the Run (GLOSSARY.md) — and the players' respawn point.
var nest_tile: Vector3i = Vector3i(0, WorldGrid.GROUND_LAYER, 0)

## The Breaches: the fixed points Enemies enter the Map at, one tile each, as
## parallel coordinate arrays.
##
## Fixed and known in advance, because that is the whole deal GLOSSARY.md strikes —
## a Breach is fortifiable, which it could not be if it moved. Deep mining opens new
## ones near the mine, which is why this is an array rather than a single tile even
## though Milestone 1 ships one.
##
## Sorted canonically on construction for the reason the Nodes are: Enemies spawn in
## Breach order, and that order has to be a property of the Map rather than of the
## order somebody typed the rows in.
var breach_tile_x: PackedInt64Array = PackedInt64Array()
var breach_tile_y: PackedInt64Array = PackedInt64Array()
var breach_tile_z: PackedInt64Array = PackedInt64Array()


## The Map a Run starts on. Two iron ore Nodes and one coal Node, all at Depth 1, far
## enough apart that a Belt between them is a decision rather than a formality.
##
## The coal is what the one Power grid runs on: a Steam Boiler burns Belt-delivered coal,
## so the Factory's first Power source is also its first logistics problem, and the coal
## sits far enough east that the fuel line is a line rather than a formality.
## The Nest sits just west of where a player starts, close enough to be the first
## thing they see and clear of the ground east of the origin that the opening Factory
## wants. The one Breach is nineteen tiles due east of it, on the Nest's own lane, so
## everything a player builds between the two is in the Crawlers' way — which is what
## makes a chokepoint a decision rather than a diagram.
static func starter() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.add_node(Vector3i(4, WorldGrid.GROUND_LAYER, 4), "iron_ore", 1)
	layout.add_node(Vector3i(-6, WorldGrid.GROUND_LAYER, 10), "iron_ore", 1)
	layout.add_node(Vector3i(12, WorldGrid.GROUND_LAYER, 4), "coal", 1)
	layout.sort_nodes()
	layout.nest_tile = Vector3i(-6, WorldGrid.GROUND_LAYER, -6)
	layout.add_breach(Vector3i(16, WorldGrid.GROUND_LAYER, -6))
	layout.sort_breaches()
	return layout


## A Map with no Nodes and no Breaches — the geography a test asks for when it is
## studying the Factory and not the threat. It still has a Nest, because a Run always
## has something to lose; with nowhere for Enemies to enter, no Wave arrives.
static func empty() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(-6, WorldGrid.GROUND_LAYER, -6)
	return layout


## The tiles the Nest's footprint covers, as (size along x, size along z). Square, so
## rotation would mean nothing and there is none.
func nest_footprint() -> Vector2i:
	return Vector2i(NEST_FOOTPRINT_TILES, NEST_FOOTPRINT_TILES)


func add_breach(tile: Vector3i) -> void:
	breach_tile_x.append(tile.x)
	breach_tile_y.append(tile.y)
	breach_tile_z.append(tile.z)


func breach_count() -> int:
	return breach_tile_x.size()


func breach_tile(index: int) -> Vector3i:
	if index < 0 or index >= breach_count():
		return Vector3i.ZERO
	return Vector3i(breach_tile_x[index], breach_tile_y[index], breach_tile_z[index])


## Orders Breaches by tile — layer, then x, then z — for the reason `sort_nodes`
## orders Nodes: Enemies are spawned in this order, so it must be geography rather
## than authoring order.
func sort_breaches() -> void:
	var order: Array = []
	for index: int in range(breach_count()):
		order.append(index)
	order.sort_custom(func(a: int, b: int) -> bool: return _breach_precedes(a, b))

	var sorted: MapLayout = MapLayout.new()
	for index: int in order:
		sorted.add_breach(breach_tile(index))

	breach_tile_x = sorted.breach_tile_x
	breach_tile_y = sorted.breach_tile_y
	breach_tile_z = sorted.breach_tile_z


func _breach_precedes(a: int, b: int) -> bool:
	if breach_tile_y[a] != breach_tile_y[b]:
		return breach_tile_y[a] < breach_tile_y[b]
	if breach_tile_x[a] != breach_tile_x[b]:
		return breach_tile_x[a] < breach_tile_x[b]
	return breach_tile_z[a] < breach_tile_z[b]


func add_node(tile: Vector3i, resource_id: String, depth: int) -> void:
	node_tile_x.append(tile.x)
	node_tile_y.append(tile.y)
	node_tile_z.append(tile.z)
	node_resource.append(resource_id)
	node_depth.append(depth)


func node_count() -> int:
	return node_resource.size()


func node_tile(index: int) -> Vector3i:
	if index < 0 or index >= node_count():
		return Vector3i.ZERO
	return Vector3i(node_tile_x[index], node_tile_y[index], node_tile_z[index])


## Orders Nodes by tile — layer, then x, then z — so the index space is total and
## independent of authoring order.
func sort_nodes() -> void:
	var order: Array = []
	for index: int in range(node_count()):
		order.append(index)
	order.sort_custom(func(a: int, b: int) -> bool: return _precedes(a, b))

	var sorted: MapLayout = MapLayout.new()
	for index: int in order:
		sorted.add_node(node_tile(index), node_resource[index], node_depth[index])

	node_tile_x = sorted.node_tile_x
	node_tile_y = sorted.node_tile_y
	node_tile_z = sorted.node_tile_z
	node_resource = sorted.node_resource
	node_depth = sorted.node_depth


func _precedes(a: int, b: int) -> bool:
	if node_tile_y[a] != node_tile_y[b]:
		return node_tile_y[a] < node_tile_y[b]
	if node_tile_x[a] != node_tile_x[b]:
		return node_tile_x[a] < node_tile_x[b]
	return node_tile_z[a] < node_tile_z[b]
