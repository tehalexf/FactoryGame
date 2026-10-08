## Where a Belt may dock against a Machine: which edge, which tile of it, which way round
## once the Machine has been turned, and whether goods go in or come out.
##
## `content/machine_ports.csv` is the authority on all of that and has been since #19 — the
## Blender generator puts a marker on the mesh at the position each row describes and the
## asset suite fails if the two disagree. What was missing is that **nothing in the game
## read the file**, so a player was shown none of it: you could not tell which face of a
## Smelter takes ore, which is how you find out by building it wrong.
##
## This is the half that makes it readable. It loads the table and answers, for a Machine
## standing at a tile and turned by a rotation, exactly which tiles its ports present and
## which way each one faces.
##
## **It is not yet what the Simulation accepts a Belt against.** `_load_from_port` and
## `_hand_off` still take any footprint edge tile, which is looser than this. Tightening
## them is a behaviour change with a balance consequence — every Factory in every fixture
## docks wherever it docks today — and is its own ticket; see CLAUDE.md. What is true now is
## that the declaration is loaded, hashed into nothing, and **on screen**, so the player and
## the renderer read the same file the mesh was built from.
##
## Pure arithmetic and integers, like `WorldGrid`, and sharing its conventions rather than
## restating them: a direction is one of `WorldGrid`'s four and a rotation turns one by
## adding to it.
class_name MachinePorts
extends RefCounted

## The columns this reads. The file declares `height_mm` too, which the mesh generator uses
## to place a marker and nothing on this side of the boundary needs: a port's height is a
## fact about the model, and the grid is flat.
const PORT_COLUMNS: Array = ["machine_id", "port_id", "direction", "edge", "tile"]

## Goods go in here. A Belt ending against this tile feeds the Machine.
const INTO: int = 0

## Goods come out here. A Belt starting on the tile past this one carries them away.
const OUT_OF: int = 1


## One declared port, as the file wrote it: which Machine, what it is called, whether it
## takes or gives, and where on the footprint it sits before any rotation.
##
## `edge` is a `WorldGrid` direction — the outward normal of the face, so north (-Z) is
## direction 3 — resolved on the way in, because the file's compass words are a convenience
## for a human editing it and not a second coordinate system for the code to carry.
class Port extends RefCounted:
	var machine_id: String = ""
	var port_id: String = ""
	var flow: int = INTO
	var edge: int = 0
	var tile_along_edge: int = 0

	func _init(
		owner_id: String, name_of_port: String, direction: int, out_of_edge: int, along: int
	) -> void:
		machine_id = owner_id
		port_id = name_of_port
		flow = direction
		edge = out_of_edge
		tile_along_edge = along

	func is_an_input() -> bool:
		return flow == INTO

	func _to_string() -> String:
		return "Port(%s.%s, %s, edge %d, tile %d)" % [
			machine_id, port_id, "in" if is_an_input() else "out", edge, tile_along_edge
		]


## The compass words the file uses, as `WorldGrid` directions. North is -Z and so is
## direction 3; the table's own header says as much, and this is the one place the two
## vocabularies meet.
const EDGE_DIRECTIONS: Array = [
	["east", 0],
	["south", 1],
	["west", 2],
	["north", 3],
]

var errors: PackedStringArray = PackedStringArray()

## Every port, in file order. File order rather than sorted, because the file is grouped by
## Machine and reads as a description of each one — and because the renderer walks all of
## them for one Machine at a time, never by index.
var _ports: Array[Port] = []


## Reads the table. A row whose `machine_id` names no row in `content/machines.csv` is kept
## rather than refused: the file also declares the Nest's delivery port and a Belt's own two
## ends, neither of which is a Machine, and `machine_bodies.csv` still declares bodies that
## `machines.csv` has not caught up with. Those rows describe a mesh the generator builds and
## are none of the Simulation's business — `ports_of` simply never finds them, because nothing
## asks about a Machine that does not exist.
##
## That looseness is the price of loading the file at all today, and it is the clause the
## ticket that makes ports authoritative should tighten: once `_load_from_port` docks against
## a declared port, a port declared for a Machine nobody defined is a typo worth refusing.
static func parse(source: String, path: String = "machine_ports.csv") -> MachinePorts:
	var ports: MachinePorts = MachinePorts.new()
	var table: CsvTable = CsvTable.parse(source, path, PackedStringArray(PORT_COLUMNS))

	for row: int in range(table.row_count()):
		var machine_id: String = table.require_id(row, "machine_id")
		var port_id: String = table.require_id(row, "port_id")
		var written_flow: String = table.value(row, "direction")
		var written_edge: String = table.value(row, "edge")
		var along: int = table.require_int(row, "tile")

		var flow: int = -1
		if written_flow == "input":
			flow = INTO
		elif written_flow == "output":
			flow = OUT_OF
		else:
			ports.errors.append(
				"%s:%d: direction: expected input or output, got \"%s\""
				% [path, table.line_number(row), written_flow]
			)

		var edge: int = -1
		for pair: Array in EDGE_DIRECTIONS:
			if pair[0] == written_edge:
				edge = pair[1]
		if edge == -1:
			ports.errors.append(
				"%s:%d: edge: expected north, south, east or west, got \"%s\""
				% [path, table.line_number(row), written_edge]
			)

		if along < 0:
			ports.errors.append(
				"%s:%d: tile: expected a tile index along the edge, got %d"
				% [path, table.line_number(row), along]
			)

		if flow == -1 or edge == -1 or machine_id.is_empty() or port_id.is_empty():
			continue
		ports._ports.append(Port.new(machine_id, port_id, flow, edge, maxi(along, 0)))

	ports.errors.append_array(table.errors)
	if ports.has_errors():
		ports._ports.clear()
	return ports


## An empty set, which is what a Run gets when the file is absent. Ports are **drawn** and
## nothing else, so a missing table costs a player the arrows and costs the Factory nothing —
## the same rule a Machine with no generated body obeys.
static func none() -> MachinePorts:
	return MachinePorts.new()


func has_errors() -> bool:
	return not errors.is_empty()


func describe_errors() -> String:
	return "\n".join(errors)


func port_count() -> int:
	return _ports.size()


## Every port declared for a Machine, in file order. Empty for a Machine the table says
## nothing about, which is an ordinary state and not a warning: a row in `machines.csv` is
## never blocked on art, and a port is art's half of the declaration.
func ports_of(machine_id: String) -> Array[Port]:
	var found: Array[Port] = []
	for port: Port in _ports:
		if port.machine_id == machine_id:
			found.append(port)
	return found


## Which tile of the Map a port presents, for a Machine anchored at `origin`, declared
## `footprint_x` by `footprint_z` tiles, and turned by `rotation` quarter turns.
##
## **The anchor does not move and the extents swap**, which is `WorldGrid.rotated_footprint`'s
## convention and therefore this one: a port is rotated about the centre of the footprint it
## ends up covering, which is exactly where the renderer puts the body. Get that wrong and the
## arrows drift off the model on every non-square Machine, which is the one defect here a
## render shows immediately.
static func port_tile(
	port: Port, origin: Vector3i, footprint_x: int, footprint_z: int, rotation: int
) -> Vector3i:
	var local: Vector2i = _local_tile(port, footprint_x, footprint_z)
	var turned: Vector2i = _rotate_within(local, footprint_x, footprint_z, rotation)
	return Vector3i(origin.x + turned.x, origin.y, origin.z + turned.y)


## Which way a port faces once the Machine has been turned: a `WorldGrid` direction pointing
## **out** of the footprint. Goods travel along it for an output and against it for an input.
static func port_direction(port: Port, rotation: int) -> int:
	return WorldGrid.wrap_rotation(port.edge + rotation)


## The tile just outside a port — where a Belt docks. The tile an output's run starts on and
## the tile an input's run ends pointing at, which is the adjacency rule Belts already follow.
static func dock_tile(
	port: Port, origin: Vector3i, footprint_x: int, footprint_z: int, rotation: int
) -> Vector3i:
	return (
		port_tile(port, origin, footprint_x, footprint_z, rotation)
		+ WorldGrid.direction_step(port_direction(port, rotation))
	)


## Where a port sits inside its own unrotated footprint, as (tiles along x, tiles along z)
## from the anchor.
##
## The file's `tile` counts along the edge: north and south edges run along x and so have
## `footprint_x` tiles, east and west run along z. An index past the end of its edge is
## clamped rather than refused, because the asset suite is what catches a port off the end of
## a body and a renderer that crashed on one would be the worse failure.
static func _local_tile(port: Port, footprint_x: int, footprint_z: int) -> Vector2i:
	match port.edge:
		3:  # north, -Z: along the near x edge
			return Vector2i(clampi(port.tile_along_edge, 0, footprint_x - 1), 0)
		1:  # south, +Z: along the far x edge
			return Vector2i(clampi(port.tile_along_edge, 0, footprint_x - 1), footprint_z - 1)
		2:  # west, -X: along the near z edge
			return Vector2i(0, clampi(port.tile_along_edge, 0, footprint_z - 1))
		_:  # east, +X: along the far z edge
			return Vector2i(footprint_x - 1, clampi(port.tile_along_edge, 0, footprint_z - 1))


## A tile of an unrotated footprint, as a tile of the rotated one. A quarter turn maps
## (x, z) to (size_z - 1 - z, x), which keeps the anchor where it is and the extents swapped.
static func _rotate_within(
	local: Vector2i, footprint_x: int, footprint_z: int, rotation: int
) -> Vector2i:
	match WorldGrid.wrap_rotation(rotation):
		1:
			return Vector2i(footprint_z - 1 - local.y, local.x)
		2:
			return Vector2i(footprint_x - 1 - local.x, footprint_z - 1 - local.y)
		3:
			return Vector2i(local.y, footprint_x - 1 - local.x)
		_:
			return local
