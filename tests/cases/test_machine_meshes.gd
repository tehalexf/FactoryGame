## The generated Machine meshes, as the real project sees them.
##
## The exhaustive numeric agreement between a mesh and the declaration lives in
## the asset suite (`tools/assets/run_tests.sh`), which drives Blender and reads
## the glTF bytes, and in `tools/assets/verify_machines_in_godot.sh`, which checks
## the same numbers on the far side of Godot's importer.
##
## What is left for *this* suite is the thing only this project can answer: that
## the committed meshes are importable in the real project, with the real import
## settings, and that the port markers survive as nodes named the way the Godot
## layer will later look them up. A separate throwaway project cannot prove that,
## because it has its own import configuration.
##
## Deliberately not asserted here: footprint and port millimetres. They would need
## a second reader of `content/machine_ports.csv` in GDScript, and a second reader
## is how the two halves of a declaration drift apart — the exact failure this
## ticket exists to prevent. One reader, in the asset pipeline, checked there.
extends TestCase

const MACHINE_DIR: String = "res://assets/machines"

## The Milestone 1 bodies from docs/DESIGN.md: the eight Machines, plus the Nest
## and a Belt segment. Written out rather than globbed, so deleting a mesh fails
## instead of quietly shrinking the expectation.
const EXPECTED_MACHINES: Array[String] = [
	"ammo_press_mk1",
	"assembler_mk1",
	"belt_straight",
	"generator_mk1",
	"miner_mk1",
	"nest",
	"press_mk1",
	"silo_mk1",
	"smelter_mk1",
	"steam_boiler_mk1",
]


func test_every_milestone_1_machine_has_a_committed_mesh() -> void:
	for machine_id: String in EXPECTED_MACHINES:
		assert_true(ResourceLoader.exists(_path_for(machine_id)),
			"%s.glb is missing — run tools/assets/generate_machines.sh" % machine_id)


func test_the_project_imports_every_machine_mesh_as_a_scene() -> void:
	for machine_id: String in EXPECTED_MACHINES:
		var scene: PackedScene = ResourceLoader.load(_path_for(machine_id)) as PackedScene
		if not assert_not_null(scene, "%s did not import as a PackedScene" % machine_id):
			continue
		var model: Node = scene.instantiate()
		assert_true(model is Node3D, "%s is not a Node3D" % machine_id)
		assert_true(_count_mesh_instances(model) > 0, "%s has no geometry" % machine_id)
		model.free()


func test_every_machine_mesh_exposes_its_ports_as_named_nodes() -> void:
	# The Godot layer will find a Machine's Belt connection points by this prefix,
	# so losing them to an import setting would be silent until a Belt had to dock.
	for machine_id: String in EXPECTED_MACHINES:
		var scene: PackedScene = ResourceLoader.load(_path_for(machine_id)) as PackedScene
		if scene == null:
			continue
		var model: Node = scene.instantiate()
		var ports: Array[String] = []
		_collect_ports(model, ports)
		assert_true(not ports.is_empty(),
			"%s exposes no Port_ marker nodes" % machine_id)
		for port_name: String in ports:
			assert_true(port_name.begins_with("Port_input_")
					or port_name.begins_with("Port_output_"),
				"%s: %s is neither an input nor an output" % [machine_id, port_name])
		model.free()


func test_no_machine_mesh_carries_a_skeleton() -> void:
	# Machines are static. A Skeleton3D here would mean the shared humanoid rig
	# leaked in from the character pipeline.
	for machine_id: String in EXPECTED_MACHINES:
		var scene: PackedScene = ResourceLoader.load(_path_for(machine_id)) as PackedScene
		if scene == null:
			continue
		var model: Node = scene.instantiate()
		assert_null(_find_skeleton(model), "%s imported with a Skeleton3D" % machine_id)
		model.free()


func _path_for(machine_id: String) -> String:
	return "%s/%s.glb" % [MACHINE_DIR, machine_id]


func _count_mesh_instances(node: Node) -> int:
	var total: int = 1 if node is MeshInstance3D else 0
	for child: Node in node.get_children():
		total += _count_mesh_instances(child)
	return total


func _collect_ports(node: Node, into: Array[String]) -> void:
	if String(node.name).begins_with("Port_"):
		into.append(String(node.name))
	for child: Node in node.get_children():
		_collect_ports(child, into)


func _find_skeleton(node: Node) -> Node:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var hit: Node = _find_skeleton(child)
		if hit != null:
			return hit
	return null
