## Where the Nodes are: the geography a Run starts from.
##
## One Map exists and it is handcrafted (GLOSSARY.md), so this is a layout rather
## than a generator — no seed is consulted and nothing here is random. Breaches and
## Hives join it in the ticket that introduces Enemies; for now it is Nodes.
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


## The Map a Run starts on. Two iron ore Nodes at Depth 1, far enough apart that a
## Belt between them is a decision rather than a formality.
static func starter() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.add_node(Vector3i(4, WorldGrid.GROUND_LAYER, 4), "iron_ore", 1)
	layout.add_node(Vector3i(-6, WorldGrid.GROUND_LAYER, 10), "iron_ore", 1)
	layout.sort_nodes()
	return layout


## An empty Map. What a test that wants no Nodes at all asks for.
static func empty() -> MapLayout:
	return MapLayout.new()


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
