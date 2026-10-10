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

## Where the shared palette materials live. One StandardMaterial3D per palette
## entry, wired onto every Machine by the `_subresources` override in its
## `.glb.import` — so eleven Machines share one copy of each generated texture
## rather than embedding eight 1024x1024 PNGs apiece.
const MATERIAL_DIR: String = "res://assets/machines/materials"

## The Milestone 1 bodies from docs/DESIGN.md: the nine Machines, plus the Nest
## and a Belt segment. Written out rather than globbed, so deleting a mesh fails
## instead of quietly shrinking the expectation.
const EXPECTED_MACHINES: Array[String] = [
	"ammo_press_mk1",
	"assembler_mk1",
	"belt_straight",
	"coal_miner_mk1",
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


func test_every_machine_mesh_arrives_wearing_the_shared_dieselpunk_materials() -> void:
	# The thing only the real project can answer about the texture pass. The .glb
	# carries geometry, UVs and a palette *name*; the surface itself is a shared
	# StandardMaterial3D that this project's import settings substitute in. Asked
	# of the engine rather than of the file, because an import that silently
	# dropped the override would leave every byte-level check green and still put
	# eleven flat-shaded blocks on the Factory floor.
	var textured: int = 0
	for machine_id: String in EXPECTED_MACHINES:
		var scene: PackedScene = ResourceLoader.load(_path_for(machine_id)) as PackedScene
		if scene == null:
			continue
		var model: Node = scene.instantiate()
		var surfaces: Array[Material] = []
		_collect_materials(model, surfaces)
		assert_true(not surfaces.is_empty(), "%s has no materials" % machine_id)
		for material: Material in surfaces:
			var standard: StandardMaterial3D = material as StandardMaterial3D
			if not assert_not_null(standard,
					"%s: %s is not the shared material" % [machine_id, material]):
				continue
			assert_true(standard.resource_path.begins_with(MATERIAL_DIR),
				"%s: %s came from the glTF, not from %s"
					% [machine_id, standard.resource_name, MATERIAL_DIR])
			if standard.albedo_texture != null:
				textured += 1
		model.free()
	# Not every material wears a texture - a gauge bezel is a coloured dot - but
	# a Factory in which none of them do is the defect this ticket was filed for.
	assert_true(textured > 0, "no Machine surface carries a texture at all")


func test_every_machine_mesh_carries_uvs_for_those_materials() -> void:
	# A textured material on a mesh with no UV channel renders as one pixel of
	# the texture stretched over the whole Machine, which looks like flat shading
	# and is not.
	for machine_id: String in EXPECTED_MACHINES:
		var scene: PackedScene = ResourceLoader.load(_path_for(machine_id)) as PackedScene
		if scene == null:
			continue
		var model: Node = scene.instantiate()
		var meshes: Array[Mesh] = []
		_collect_meshes(model, meshes)
		for mesh: Mesh in meshes:
			for surface: int in mesh.get_surface_count():
				var format: int = (mesh as ArrayMesh).surface_get_format(surface)
				assert_true((format & Mesh.ARRAY_FORMAT_TEX_UV) != 0,
					"%s surface %d has no UVs" % [machine_id, surface])
		model.free()


func _collect_materials(node: Node, into: Array[Material]) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			for surface: int in mesh.get_surface_count():
				var material: Material = mesh.surface_get_material(surface)
				if material != null:
					into.append(material)
	for child: Node in node.get_children():
		_collect_materials(child, into)


func _collect_meshes(node: Node, into: Array[Mesh]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		into.append((node as MeshInstance3D).mesh)
	for child: Node in node.get_children():
		_collect_meshes(child, into)


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
