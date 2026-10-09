## `content/machine_ports.csv`, read and turned into tiles of the Map.
##
## The file has declared every port since #19 and the mesh generator has put a marker at
## each one since then too — and until #36 nothing in the game read it, so a player was
## shown none of it. These are the arithmetic that makes it showable: which tile of the
## Map a declared port presents, which way it faces, and where a Belt would dock against
## it, for a Machine turned any of four ways.
##
## Worked examples throughout, off the shipped table and the shipped footprints. A test
## that recomputed the rotation the way the code does would assert nothing.
extends TestCase

const PORTS: String = """\
machine_id,port_id,direction,edge,tile,height_mm
smelter_mk1,ore,input,north,1,900
smelter_mk1,ingot,output,south,1,900
boiler,coal,input,west,0,900
oblong,out,output,east,2,900
"""


func _ports() -> MachinePorts:
	var ports: MachinePorts = MachinePorts.parse(PORTS)
	assert_false(ports.has_errors(), ports.describe_errors())
	return ports


func _port(ports: MachinePorts, machine_id: String, port_id: String) -> MachinePorts.Port:
	for port: MachinePorts.Port in ports.ports_of(machine_id):
		if port.port_id == port_id:
			return port
	fail("no port %s on %s" % [port_id, machine_id])
	return null


# ── Reading the table ─────────────────────────────────────────────────────────

func test_the_shipped_table_declares_the_smelters_faces_tile_by_tile() -> void:
	# A Smelter is 3x3 and declares whole faces: ore along the north, coal along the west,
	# ingot along the south and the east. Tile by tile rather than one port per good, because
	# #47 made the declaration the rule — a port is one tile wide, so a Machine with one
	# declared output could not serve two Belts, and #46 made serving two Belts a feature.
	var ports: MachinePorts = MachinePorts.parse(
		ContentFixture.shipped(Definitions.PORTS_FILE),
		"content/machine_ports.csv"
	)
	assert_false(ports.has_errors(), ports.describe_errors())
	var smelter: Array[MachinePorts.Port] = ports.ports_of("smelter_mk1")
	assert_eq(smelter.size(), 12, "three tiles each of two input faces and two output faces")
	var names: PackedStringArray = PackedStringArray()
	for port: MachinePorts.Port in smelter:
		names.append(port.port_id)
	assert_eq(
		names,
		PackedStringArray([
			"ore_n0", "ore_n1", "ore_n2",
			"coal_w0", "coal_w1", "coal_w2",
			"ingot_s0", "ingot_s1", "ingot_s2",
			"ingot_e0", "ingot_e1", "ingot_e2",
		]),
		"in file order"
	)


func test_a_port_knows_whether_goods_go_in_or_come_out() -> void:
	var ports: MachinePorts = _ports()
	assert_true(_port(ports, "smelter_mk1", "ore").is_an_input())
	assert_false(_port(ports, "smelter_mk1", "ingot").is_an_input())


func test_the_files_compass_words_become_world_grid_directions() -> void:
	# North is -Z, which is `WorldGrid` direction 3; south is +Z, direction 1. One
	# vocabulary for the code and one for the human editing the table, meeting in one
	# place.
	var ports: MachinePorts = _ports()
	assert_eq(_port(ports, "smelter_mk1", "ore").edge, 3, "north is -Z")
	assert_eq(_port(ports, "smelter_mk1", "ingot").edge, 1, "south is +Z")
	assert_eq(_port(ports, "boiler", "coal").edge, 2, "west is -X")
	assert_eq(_port(ports, "oblong", "out").edge, 0, "east is +X")


func test_a_row_with_a_direction_or_an_edge_nobody_recognises_is_an_error() -> void:
	var broken: MachinePorts = MachinePorts.parse(
		"""machine_id,port_id,direction,edge,tile,height_mm
smelter_mk1,ore,sideways,north,1,900
smelter_mk1,ingot,output,up,1,900
"""
	)
	assert_true(broken.has_errors(), "a typo'd port is a typo, not a port")
	assert_eq(broken.port_count(), 0, "and nothing is invented from a table in error")


func test_ports_declared_for_a_machine_nobody_defined_are_simply_never_asked_for() -> void:
	# The table also declares the Nest's delivery port and a Belt's own two ends, neither
	# of which is a Machine. Refusing those rows would mean refusing the whole file, which
	# is why nothing in the game could read it before.
	var ports: MachinePorts = MachinePorts.parse(
		ContentFixture.shipped(Definitions.PORTS_FILE),
		"content/machine_ports.csv"
	)
	assert_false(ports.has_errors())
	assert_eq(ports.ports_of("nest").size(), 1, "declared, and for the mesh generator")
	assert_eq(ports.ports_of("no_such_machine_mk9").size(), 0, "and nothing is invented")


# ── Where a port is on the Map ────────────────────────────────────────────────

func test_an_unturned_ports_tile_is_the_footprint_tile_the_file_names() -> void:
	# The Smelter is 3x3. Its ore input is on the north edge at index 1, so the middle
	# tile of the near x edge: one along x, zero along z from the anchor.
	var ports: MachinePorts = _ports()
	assert_eq(
		MachinePorts.port_tile(
			_port(ports, "smelter_mk1", "ore"), Vector3i(10, 0, 20), 3, 3, 0
		),
		Vector3i(11, 0, 20)
	)
	# And its ingot output is the middle of the far x edge: one along x, two along z.
	assert_eq(
		MachinePorts.port_tile(
			_port(ports, "smelter_mk1", "ingot"), Vector3i(10, 0, 20), 3, 3, 0
		),
		Vector3i(11, 0, 22)
	)


func test_a_port_faces_out_of_the_footprint_and_a_belt_docks_past_it() -> void:
	var ports: MachinePorts = _ports()
	var ingot: MachinePorts.Port = _port(ports, "smelter_mk1", "ingot")
	assert_eq(MachinePorts.port_direction(ingot, 0), 1, "the south face looks down +Z")
	assert_eq(
		MachinePorts.dock_tile(ingot, Vector3i(10, 0, 20), 3, 3, 0),
		Vector3i(11, 0, 23),
		"a Belt run starts on the tile past the footprint edge"
	)


func test_turning_a_machine_turns_its_ports_with_it() -> void:
	# A quarter turn walks a direction one step round the grid's four: south (1) becomes
	# west (2). A 3x3 footprint keeps its extents, so the anchor and the shape are
	# unchanged and only the face moves — which is the whole of what a player needs to
	# know before they point a Belt at one.
	var ports: MachinePorts = _ports()
	var ingot: MachinePorts.Port = _port(ports, "smelter_mk1", "ingot")
	assert_eq(MachinePorts.port_direction(ingot, 1), 2, "a quarter turn puts it west")
	assert_eq(MachinePorts.port_direction(ingot, 2), 3, "a half turn puts it north")
	assert_eq(MachinePorts.port_direction(ingot, 3), 0, "and three quarters east")
	# The tile it sits on moves with the face. The ingot port is the local (1, 2) tile of a
	# 3x3 body; a quarter turn maps (x, z) to (size_z - 1 - z, x), so (1, 2) becomes (0, 1).
	assert_eq(
		MachinePorts.port_tile(ingot, Vector3i(10, 0, 20), 3, 3, 1),
		Vector3i(10, 0, 21)
	)
	assert_eq(
		MachinePorts.dock_tile(ingot, Vector3i(10, 0, 20), 3, 3, 1),
		Vector3i(9, 0, 21),
		"and the dock tile goes with it, one step west"
	)


func test_a_turned_oblong_keeps_its_port_inside_the_footprint_it_covers() -> void:
	# The case a square Machine cannot show, and the one a render shows immediately if it
	# is wrong: a 2x3 body turned a quarter covers 3x2 tiles from the same anchor, so a
	# port that was two tiles down the east edge has to end up inside those 3x2 tiles.
	var ports: MachinePorts = _ports()
	var out: MachinePorts.Port = _port(ports, "oblong", "out")
	# Unturned: the east edge is the far x edge, index 2 along z. Local (1, 2).
	assert_eq(MachinePorts.port_tile(out, Vector3i(0, 0, 0), 2, 3, 0), Vector3i(1, 0, 2))
	# A quarter turn: (1, 2) maps to (size_z - 1 - 2, 1) = (0, 1), which is inside the 3x2
	# the turned footprint covers.
	var turned: Vector3i = MachinePorts.port_tile(out, Vector3i(0, 0, 0), 2, 3, 1)
	assert_eq(turned, Vector3i(0, 0, 1))
	var covered: Vector2i = WorldGrid.rotated_footprint(2, 3, 1)
	assert_true(
		WorldGrid.footprint_covers(Vector3i(0, 0, 0), covered.x, covered.y, turned),
		"a port off the body is an arrow in mid-air"
	)


func test_every_declared_port_of_every_shipped_machine_sits_on_its_own_footprint() -> void:
	# The invariant rather than a list of cases, over the whole shipped table and all four
	# rotations. This is what would have caught the rotation convention being the other way
	# round, on the two Machines that are not square.
	var ports: MachinePorts = MachinePorts.parse(
		ContentFixture.shipped(Definitions.PORTS_FILE),
		"content/machine_ports.csv"
	)
	var definitions: Definitions = Definitions.load_from_directory("res://content")
	assert_false(definitions.has_errors(), definitions.describe_errors())
	var checked: int = 0
	for index: int in range(definitions.machine_count()):
		var machine: MachineDefinition = definitions.machine_at(index)
		for port: MachinePorts.Port in ports.ports_of(machine.id):
			for rotation: int in range(WorldGrid.DIRECTION_COUNT):
				var covered: Vector2i = WorldGrid.rotated_footprint(
					machine.footprint_x, machine.footprint_z, rotation
				)
				var tile: Vector3i = MachinePorts.port_tile(
					port, Vector3i(4, 0, 6), machine.footprint_x, machine.footprint_z, rotation
				)
				assert_true(
					WorldGrid.footprint_covers(Vector3i(4, 0, 6), covered.x, covered.y, tile),
					"%s turned %d puts its %s port at %s, off the body"
					% [machine.id, rotation, port.port_id, tile]
				)
				checked += 1
	assert_true(checked >= 24, "the shipped table really was walked, saw %d" % checked)
