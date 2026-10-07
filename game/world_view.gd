## Draws the Simulation. A reader, never a writer.
##
## ADR 0001 makes Godot a renderer only, so every number here comes out of a
## `query_*` call on the tick it is drawn and is thrown away again. There is no
## mirror of Simulation state on this side — no list of Machines, no cached counts —
## because a mirror is a second copy of the truth and the first thing to drift from
## it. The meshes below are the one thing this node owns, and they are a function of
## the queries, rebuilt whenever what the queries report stops matching them.
##
## Everything it draws is a placeholder: a box per Node, a box per Machine, sized
## from the footprint `content/machines.csv` states. Real meshes arrive with the art
## pass; what matters now is that the box is in the place the Simulation says the
## Machine is, and that the count on screen is the count in the buffer.
##
## Floats appear freely here. This is the outbound side of the boundary, and
## `Fixed.to_float` is the sanctioned crossing.
class_name WorldView
extends Node3D

## Height of a placeholder Machine box, in metres. Taller than the 1.8 m player, so
## a Factory reads as a Factory from eye level.
const MACHINE_HEIGHT_METRES: float = 3.0

## A Node is drawn as a low slab, so a Miner standing on one does not hide it.
const NODE_HEIGHT_METRES: float = 0.4

## A tile of Belt is a low slab too, so the Items riding it are what the eye follows.
const BELT_HEIGHT_METRES: float = 0.3

## An Item is a small cube sitting on the Belt. Smaller than the 0.5 m an Item occupies
## along the run, so a packed Belt reads as a queue of distinct boxes with gaps rather
## than as one continuous bar — which is the whole point of drawing them.
const ITEM_SIZE_METRES: float = 0.35

var _machine_meshes: Array[MeshInstance3D] = []
var _node_meshes: Array[MeshInstance3D] = []
var _belt_meshes: Array[MeshInstance3D] = []

## Every Item on every Belt, as instances of one mesh.
##
## Deliberately a MultiMesh rather than a node each. ADR 0002 makes Items derived state
## that is recomputed rather than replicated, and ADR 0001 keeps Godot a renderer: an
## Item must therefore never be a node, and at the scale this system reaches — the
## genre's reference implementation spends most of a late-game frame on Belts and their
## Items — one node per Item would be the first thing to fall over.
var _item_meshes: MultiMeshInstance3D = null

## The instance transforms handed to the MultiMesh, in its own flat layout: twelve floats
## an instance, with the position in slots 3, 7 and 11. Built from the queries every frame
## and uploaded in one assignment, which is both the fast path and the only way to read
## back what was drawn — a MultiMesh keeps its buffer on the rendering server, where a
## headless test cannot see it.
##
## Not a mirror of Simulation state: it is rebuilt from scratch out of `query_*` calls on
## the frame it is drawn, and nothing ever reads a position out of it to make a decision.
var _item_transforms: PackedFloat32Array = PackedFloat32Array()

## How many floats one MultiMesh instance transform occupies in TRANSFORM_3D format.
const FLOATS_PER_INSTANCE: int = 12

var _hud: Label = null
var _hud_layer: CanvasLayer = null
var _camera: Camera3D = null


## Redraws everything from the Simulation's queries. Called once a frame; cheap
## enough at Milestone 1 scale that it rebuilds rather than diffs, and the shape it
## rebuilds from is the query output, so a divergence between what is simulated and
## what is drawn cannot survive a frame.
func sync(sim: Simulation) -> void:
	if sim == null:
		return

	_sync_nodes(sim)
	_sync_machines(sim)
	_sync_belts(sim)
	_sync_items(sim)
	_sync_hud(sim)
	_place_camera(sim)


## How many placeholders are on screen — Nodes plus Machines.
func placeholder_count() -> int:
	return _node_meshes.size() + _machine_meshes.size()


## How many tiles of Belt are on screen.
func belt_placeholder_count() -> int:
	return _belt_meshes.size()


## How many Items are on screen.
func item_instance_count() -> int:
	@warning_ignore("integer_division")
	return _item_transforms.size() / FLOATS_PER_INSTANCE


## Where an Item instance is standing, in metres. For the smoke test, and for anything
## later that needs to point at a specific Item.
func item_instance_position(instance: int) -> Vector3:
	if instance < 0 or instance >= item_instance_count():
		return Vector3.ZERO
	var base: int = instance * FLOATS_PER_INSTANCE
	return Vector3(
		_item_transforms[base + 3], _item_transforms[base + 7], _item_transforms[base + 11]
	)


## Where a Machine's placeholder stands, in metres. For the smoke test, and for
## anything later that needs to point at a Machine on screen.
func machine_placeholder_position(index: int) -> Vector3:
	if index < 0 or index >= _machine_meshes.size():
		return Vector3.ZERO
	return _machine_meshes[index].position


## What the HUD is showing. The Items the Factory is holding, and how many.
func hud_text() -> String:
	if _hud == null:
		return ""
	return _hud.text


# ── Drawing ───────────────────────────────────────────────────────────────────

func _sync_nodes(sim: Simulation) -> void:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	_resize_pool(_node_meshes, sim.query_node_count(), tile_size, NODE_HEIGHT_METRES, Color(0.45, 0.32, 0.18))

	for index: int in range(sim.query_node_count()):
		var tile: Vector3i = sim.query_node_tile(index)
		var centre: FixedVec2 = sim.query_tile_centre_metres(tile)
		_node_meshes[index].position = Vector3(
			Fixed.to_float(centre.x),
			Fixed.to_float(sim.query_layer_height_metres(tile.y)) + NODE_HEIGHT_METRES * 0.5,
			Fixed.to_float(centre.z)
		)


func _sync_machines(sim: Simulation) -> void:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	_resize_pool(_machine_meshes, sim.query_machine_count(), tile_size, MACHINE_HEIGHT_METRES, Color(0.35, 0.37, 0.33))

	for index: int in range(sim.query_machine_count()):
		var definition: MachineDefinition = sim.query_definitions().machine(sim.query_machine_id(index))
		if definition == null:
			continue

		# The footprint comes from content/machines.csv, through the Simulation. The
		# renderer does not get its own copy of those numbers — #19 generates the real
		# meshes against the same file, and two sources would drift apart on the first
		# balance change.
		var box: BoxMesh = _machine_meshes[index].mesh
		box.size = Vector3(
			float(definition.footprint_x) * tile_size,
			MACHINE_HEIGHT_METRES,
			float(definition.footprint_z) * tile_size
		)

		var tile: Vector3i = sim.query_machine_tile(index)
		var near: FixedVec2 = sim.query_tile_centre_metres(tile)
		var far: FixedVec2 = sim.query_tile_centre_metres(
			Vector3i(tile.x + definition.footprint_x - 1, tile.y, tile.z + definition.footprint_z - 1)
		)
		_machine_meshes[index].position = Vector3(
			(Fixed.to_float(near.x) + Fixed.to_float(far.x)) * 0.5,
			Fixed.to_float(sim.query_layer_height_metres(tile.y)) + MACHINE_HEIGHT_METRES * 0.5,
			(Fixed.to_float(near.z) + Fixed.to_float(far.z)) * 0.5
		)


## One slab per tile of Belt. Flat on the ground, so the Items on top of it are what the
## eye follows along a line.
func _sync_belts(sim: Simulation) -> void:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())

	var tiles: int = 0
	for index: int in range(sim.query_belt_count()):
		tiles += sim.query_belt_length_tiles(index)
	_resize_pool(_belt_meshes, tiles, tile_size, BELT_HEIGHT_METRES, Color(0.24, 0.22, 0.20))

	var slab: int = 0
	for index: int in range(sim.query_belt_count()):
		for step: int in range(sim.query_belt_length_tiles(index)):
			var tile: Vector3i = sim.query_belt_tile(index, step)
			var centre: FixedVec2 = sim.query_tile_centre_metres(tile)
			_belt_meshes[slab].position = Vector3(
				Fixed.to_float(centre.x),
				Fixed.to_float(sim.query_layer_height_metres(tile.y)) + BELT_HEIGHT_METRES * 0.5,
				Fixed.to_float(centre.z)
			)
			slab += 1


## Every Item on every Belt, at the position the Simulation says it is at.
##
## No interpolation, no smoothing, no remembered previous frame: the Simulation moves an
## Item by a fixed amount every tick and this draws it there. That is what makes a backed
## -up line diagnosable by looking at it — the queue of Items on screen is the queue in
## the state, down to the sub-unit.
func _sync_items(sim: Simulation) -> void:
	if _item_meshes == null:
		_item_meshes = MultiMeshInstance3D.new()
		var instanced: MultiMesh = MultiMesh.new()
		instanced.transform_format = MultiMesh.TRANSFORM_3D
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(ITEM_SIZE_METRES, ITEM_SIZE_METRES, ITEM_SIZE_METRES)
		instanced.mesh = box
		_item_meshes.multimesh = instanced
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(0.62, 0.36, 0.20)
		_item_meshes.material_override = material
		add_child(_item_meshes)

	var total: int = 0
	for index: int in range(sim.query_belt_count()):
		total += sim.query_belt_item_count(index)

	_item_transforms.resize(total * FLOATS_PER_INSTANCE)
	var instance: int = 0
	for index: int in range(sim.query_belt_count()):
		var layer: int = sim.query_belt_tile(index, 0).y
		var height: float = (
			Fixed.to_float(sim.query_layer_height_metres(layer))
			+ BELT_HEIGHT_METRES
			+ ITEM_SIZE_METRES * 0.5
		)
		for slot: int in range(sim.query_belt_item_count(index)):
			var where: FixedVec2 = sim.query_belt_item_position_metres(index, slot)
			var base: int = instance * FLOATS_PER_INSTANCE
			# An identity basis with the position in the fourth column of each row, which
			# is the layout a MultiMesh expects for TRANSFORM_3D.
			_item_transforms[base + 0] = 1.0
			_item_transforms[base + 1] = 0.0
			_item_transforms[base + 2] = 0.0
			_item_transforms[base + 3] = Fixed.to_float(where.x)
			_item_transforms[base + 4] = 0.0
			_item_transforms[base + 5] = 1.0
			_item_transforms[base + 6] = 0.0
			_item_transforms[base + 7] = height
			_item_transforms[base + 8] = 0.0
			_item_transforms[base + 9] = 0.0
			_item_transforms[base + 10] = 1.0
			_item_transforms[base + 11] = Fixed.to_float(where.z)
			instance += 1

	_item_meshes.multimesh.instance_count = total
	if total > 0:
		_item_meshes.multimesh.buffer = _item_transforms


## The one number this ticket exists to make visible: what the Factory has extracted.
## Read out of the buffers every frame, so it cannot be stale or invented.
func _sync_hud(sim: Simulation) -> void:
	if _hud == null:
		_hud_layer = CanvasLayer.new()
		_hud = Label.new()
		_hud_layer.add_child(_hud)
		add_child(_hud_layer)

	var lines: PackedStringArray = PackedStringArray()
	lines.append("tick %d" % sim.query_tick())

	# The one Power grid, as one line: what it supplies, what the Factory is drawing, and
	# the fraction of that it is actually getting. The percentage is rounded for the
	# player's benefit and that is the only place it is rounded — the Simulation throttles
	# on the two kilowatt figures themselves, so nothing here can move an Item.
	lines.append(
		"power %d/%d kW — %d%%"
		% [
			sim.query_power_supply_kw(),
			sim.query_power_demand_kw(),
			roundi(Fixed.to_float(sim.query_power_ratio()) * 100.0),
		]
	)

	var totals: PackedStringArray = PackedStringArray()
	for item_id: String in sim.query_definitions().item_ids():
		var total: int = sim.query_item_total(item_id)
		if total > 0:
			totals.append("%s %d" % [item_id, total])
	if totals.is_empty():
		totals.append("nothing extracted yet")
	lines.append_array(totals)

	for index: int in range(sim.query_machine_count()):
		# Starvation is asked of the Simulation rather than guessed from a count that has
		# stopped moving. A renderer that inferred it would be a second opinion about the
		# Factory, and the wrong one on the frame they disagreed.
		# Starved and throttled are different diagnoses with different fixes — lay a Belt,
		# or build a Boiler — so the HUD never collapses them into one word.
		var state: String = "running"
		if sim.query_machine_is_starved(index):
			state = "starved"
		elif sim.query_machine_is_throttled(index):
			state = "throttled"
		lines.append(
			"%s — %s — in %d, out %d"
			% [
				sim.query_machine_id(index),
				state,
				sim.query_machine_input_total(index),
				sim.query_machine_output_total(index),
			]
		)

	for index: int in range(sim.query_belt_count()):
		var flow: String = "stalled" if sim.query_belt_is_stalled(index) else "moving"
		lines.append(
			"belt %d tiles — %s — %d/%d"
			% [
				sim.query_belt_length_tiles(index),
				flow,
				sim.query_belt_item_count(index),
				sim.query_belt_capacity(index),
			]
		)

	_hud.text = "\n".join(lines)


## A fixed raised view over the Factory. The first-person controller and Survey View
## ticket replaces this; until then it exists so there is something to look through.
func _place_camera(sim: Simulation) -> void:
	if _camera != null:
		return

	_camera = Camera3D.new()
	var centre: FixedVec2 = sim.query_tile_centre_metres(sim.query_node_tile(0))
	_camera.position = Vector3(
		Fixed.to_float(centre.x), 18.0, Fixed.to_float(centre.z) + 18.0
	)
	_camera.look_at_from_position(
		_camera.position,
		Vector3(Fixed.to_float(centre.x), 0.0, Fixed.to_float(centre.z)),
		Vector3.UP
	)
	add_child(_camera)


## Grows or shrinks a pool of placeholder boxes to `wanted`. Pooled rather than
## rebuilt from scratch each frame so the node count is stable; Enemies get MultiMesh
## instead, which is the ticket that needs thousands rather than tens.
func _resize_pool(
	pool: Array[MeshInstance3D], wanted: int, tile_size: float, height: float, colour: Color
) -> void:
	while pool.size() > wanted:
		var spare: MeshInstance3D = pool.pop_back()
		remove_child(spare)
		spare.queue_free()

	while pool.size() < wanted:
		var mesh: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(tile_size, height, tile_size)
		mesh.mesh = box
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = colour
		mesh.material_override = material
		add_child(mesh)
		pool.append(mesh)
