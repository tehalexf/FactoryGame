## Where the Nodes are: the geography a Run starts from.
##
## One Map exists and it is handcrafted (GLOSSARY.md), so this is a layout rather
## than a generator — no seed is consulted and nothing here is random. Nodes, the
## Nest, the Breaches and the Hives.
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


## Whether one tile comes before another in the Map's canonical order: layer, then x, then
## z. **The single authority for that order**, and the reason it is a static on this class
## rather than a method on either of its callers.
##
## Nodes and Breaches are both sorted by it, and the Simulation inserts a Breach that deep
## mining opened at the position it names — which is the whole of how a runtime Breach keeps
## the ordering discipline a starting Breach has. Enemies are released in Breach order, so
## if that order were ever "the order they appeared" rather than geography, which Breach
## went first would be a function of *when a player dug* and two clients that dug in a
## different order would release Enemies in a different sequence. One comparator, used by
## everything that orders tiles, is what makes that impossible rather than merely unlikely.
static func tile_precedes(a: Vector3i, b: Vector3i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	if a.x != b.x:
		return a.x < b.x
	return a.z < b.z

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

## The Hives: Enemy structures out on the Map, one tile each, as parallel coordinate
## arrays.
##
## **Geography, for the reason the Breaches are.** A Hive is a fixed place a player has to
## walk to — "destroying one reduces pressure permanently but requires leaving the Factory"
## (GLOSSARY.md) — and a Hive that moved would make that walk unplannable. What is *left* of
## each one is Simulation state, because a Hive can be killed and a killed Hive never comes
## back; where they stand is here, because moving one is a different Map rather than a
## balance change.
##
## Sorted canonically on construction for the reason the Nodes and the Breaches are: Hives
## brood Enemies in this order and their indices reach the state hash, so the order has to
## be a property of the Map rather than of the order somebody typed the rows in.
var hive_tile_x: PackedInt64Array = PackedInt64Array()
var hive_tile_y: PackedInt64Array = PackedInt64Array()
var hive_tile_z: PackedInt64Array = PackedInt64Array()


## The Map a Run starts on. Three Nodes at Depth 1 — two iron ore and one coal — and two
## deeper seams of iron out to the east, far enough apart that a Belt between them is a
## decision rather than a formality.
##
## The shallow ore is finite in *number*, which is what makes Depth a real lever rather than
## a curiosity: a Factory that wants to grow past three Nodes has to reach for the Depth 2
## seam at (22, 10) or the Depth 3 one at (30, -14), and reaching costs a higher-tier Miner,
## more Power, more Heat and a new Breach six tiles north-west of whichever one it digs. The
## Depth 2 seam's hole opens at (16, 4) — squarely in the eastern ground the opening Factory
## wants — so greed rearranges the Map a player has already laid out rather than adding a
## threat somewhere they were not using.
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
	layout.add_node(Vector3i(22, WorldGrid.GROUND_LAYER, 10), "iron_ore", 2)
	layout.add_node(Vector3i(30, WorldGrid.GROUND_LAYER, -14), "iron_ore", 3)
	layout.sort_nodes()
	layout.nest_tile = Vector3i(-6, WorldGrid.GROUND_LAYER, -6)
	layout.add_breach(Vector3i(16, WorldGrid.GROUND_LAYER, -6))
	layout.sort_breaches()
	# Two Hives, both well clear of the ground the opening Factory wants and both a real walk
	# from the Nest — 44 and 48 tiles, which is a little under half a minute each way at a
	# sprint. They are out in opposite directions on purpose: one sortie does not pass the
	# other, so a player who wants both back has to make the decision twice.
	#
	# They are standing from tick 0 rather than arriving later, because the pressure they add
	# is the *baseline* a Run is played against: `hive.heat_per_minute` is already shortening
	# the interval between Waves before the first Machine is placed, and clearing one is how a
	# Factory buys permanent room to grow. A Map with no Hive is `empty()`, which is what a
	# test studying the Factory asks for.
	layout.add_hive(Vector3i(38, WorldGrid.GROUND_LAYER, 24))
	layout.add_hive(Vector3i(-34, WorldGrid.GROUND_LAYER, -30))
	layout.sort_hives()
	return layout


## A Map with no Nodes, no Breaches and no Hives — the geography a test asks for when it is
## studying the Factory and not the threat. It still has a Nest, because a Run always
## has something to lose; with nowhere for Enemies to enter, no Wave arrives, and with no
## Hive nothing is raising Heat from outside.
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
	return tile_precedes(breach_tile(a), breach_tile(b))


func add_hive(tile: Vector3i) -> void:
	hive_tile_x.append(tile.x)
	hive_tile_y.append(tile.y)
	hive_tile_z.append(tile.z)


func hive_count() -> int:
	return hive_tile_x.size()


func hive_tile(index: int) -> Vector3i:
	if index < 0 or index >= hive_count():
		return Vector3i.ZERO
	return Vector3i(hive_tile_x[index], hive_tile_y[index], hive_tile_z[index])


## Orders Hives by tile — layer, then x, then z — for the reason `sort_breaches` orders
## Breaches: Hives brood Enemies in this order, so it must be geography rather than
## authoring order.
func sort_hives() -> void:
	var order: Array = []
	for index: int in range(hive_count()):
		order.append(index)
	order.sort_custom(func(a: int, b: int) -> bool: return _hive_precedes(a, b))

	var sorted: MapLayout = MapLayout.new()
	for index: int in order:
		sorted.add_hive(hive_tile(index))

	hive_tile_x = sorted.hive_tile_x
	hive_tile_y = sorted.hive_tile_y
	hive_tile_z = sorted.hive_tile_z


func _hive_precedes(a: int, b: int) -> bool:
	return tile_precedes(hive_tile(a), hive_tile(b))


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
	return tile_precedes(node_tile(a), node_tile(b))
