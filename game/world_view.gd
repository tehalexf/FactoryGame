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

var _machine_meshes: Array[MeshInstance3D] = []
var _node_meshes: Array[MeshInstance3D] = []
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
	_sync_hud(sim)
	_place_camera(sim)


## How many placeholders are on screen — Nodes plus Machines.
func placeholder_count() -> int:
	return _node_meshes.size() + _machine_meshes.size()


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

	var totals: PackedStringArray = PackedStringArray()
	for item_id: String in sim.query_definitions().item_ids():
		var total: int = sim.query_item_total(item_id)
		if total > 0:
			totals.append("%s %d" % [item_id, total])
	if totals.is_empty():
		totals.append("nothing extracted yet")
	lines.append_array(totals)

	for index: int in range(sim.query_machine_count()):
		var where: String = "on a Node" if sim.query_node_under_machine(index) != -1 else "on bare rock"
		lines.append(
			"%s %s — holding %d"
			% [sim.query_machine_id(index), where, sim.query_machine_output_total(index)]
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
