extends SceneTree

## Verify generated Machine meshes in Godot itself: that the engine's own glTF
## importer accepts them with no manual fixing, that each one occupies exactly
## the footprint the declaration gives it, and that its port markers arrive as
## nodes at exactly the declared positions.
##
## The Python asset suite already checks all of this against the glTF bytes. This
## checks it again on the other side of Godot's importer, which is the thing that
## actually has to be true — an importer that silently rescales or reorients a
## mesh would pass every byte-level test and still put the Belt in the wrong
## place.
##
## Run through tools/assets/verify_machines_in_godot.sh, which builds a throwaway
## project around the meshes, hands this script the resolved declaration as JSON,
## and lets the editor import first.

## Millimetres of slack. A mesh extent survives a 32-bit float round trip and a
## metres conversion; a real disagreement is a whole tile out, not a micron.
const TOLERANCE_MM: float = 0.5

var failures: Array[String] = []
var checks: int = 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: ... -- <declaration.json> <palette.json>")
		quit(2)
		return

	var declaration: Dictionary = load_json(args[0])
	var palette: Dictionary = load_json(args[1])
	if declaration.is_empty() or palette.is_empty():
		quit(2)
		return

	var allowed_materials: Array[String] = []
	for entry: Dictionary in palette["materials"]:
		allowed_materials.append(entry["name"])

	for machine: Dictionary in declaration["machines"]:
		verify_machine(machine, allowed_materials)

	finish()


func load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("cannot read %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed
	push_error("%s is not a JSON object" % path)
	return {}


func verify_machine(machine: Dictionary, allowed_materials: Array[String]) -> void:
	var machine_id: String = machine["id"]
	var path := "res://%s.glb" % machine_id
	print("=== %s ===" % machine_id)

	var scene := ResourceLoader.load(path) as PackedScene
	check(scene != null, "%s: Godot imported it as a PackedScene" % machine_id)
	if scene == null:
		return

	var model := scene.instantiate() as Node3D
	check(model != null, "%s: the imported scene instantiates as a Node3D" % machine_id)
	if model == null:
		return

	# Deliberately not added to the scene tree. In a `--script` run the root is
	# not itself inside the tree, so `global_transform` would quietly return
	# identity for every node and every position check would pass by accident.
	# `transform_within` walks the local transforms instead.
	verify_footprint(machine, model)
	verify_ports(machine, model)
	verify_materials(machine, model, allowed_materials)

	model.free()


func verify_footprint(machine: Dictionary, model: Node3D) -> void:
	var machine_id: String = machine["id"]
	var bounds := visual_bounds(model)
	check(bounds.size != Vector3.ZERO, "%s: the scene contains mesh geometry" % machine_id)
	if bounds.size == Vector3.ZERO:
		return

	var footprint: Array = machine["footprint_mm"]
	check_mm("%s: X extent" % machine_id, bounds.size.x * 1000.0, float(footprint[0]))
	check_mm("%s: Z extent" % machine_id, bounds.size.z * 1000.0, float(footprint[1]))
	# Origin convention: footprint centre, standing on the ground. A Machine
	# placed at a tile centre is only placed correctly if this holds.
	check_mm("%s: X centre" % machine_id, (bounds.position.x + bounds.size.x * 0.5) * 1000.0, 0.0)
	check_mm("%s: Z centre" % machine_id, (bounds.position.z + bounds.size.z * 0.5) * 1000.0, 0.0)
	check_mm("%s: base sits on the ground" % machine_id, bounds.position.y * 1000.0, 0.0)
	print("    footprint %.3f m x %.3f m, %.2f m tall" % [
		bounds.size.x, bounds.size.z, bounds.size.y])


func verify_ports(machine: Dictionary, model: Node3D) -> void:
	var machine_id: String = machine["id"]
	var found: Array[String] = []
	collect_port_names(model, found)
	found.sort()

	var expected: Array[String] = []
	for port: Dictionary in machine["ports"]:
		expected.append(port["node"])
	expected.sort()
	check(found == expected,
		"%s: port markers are exactly the declared ports (found %s, expected %s)" % [
			machine_id, found, expected])

	for port: Dictionary in machine["ports"]:
		var node := find_descendant(model, port["node"]) as Node3D
		check(node != null, "%s: has a marker node %s" % [machine_id, port["node"]])
		if node == null:
			continue
		var at := transform_within(model, node).origin * 1000.0
		var want: Array = port["position_mm"]
		check_mm("%s.%s: X" % [machine_id, port["id"]], at.x, float(want[0]))
		check_mm("%s.%s: Y" % [machine_id, port["id"]], at.y, float(want[1]))
		check_mm("%s.%s: Z" % [machine_id, port["id"]], at.z, float(want[2]))
		print("    %s %s at (%.0f, %.0f, %.0f) mm" % [
			port["direction"], port["id"], at.x, at.y, at.z])


func verify_materials(machine: Dictionary, model: Node3D,
		allowed_materials: Array[String]) -> void:
	var machine_id: String = machine["id"]
	var used: Array[String] = []
	collect_material_names(model, used)
	check(not used.is_empty(), "%s: the meshes carry materials" % machine_id)
	for name: String in used:
		check(allowed_materials.has(name),
			"%s: material %s is in the shared palette" % [machine_id, name])


## A descendant's transform relative to `root`, from local transforms only.
func transform_within(root: Node3D, node: Node3D) -> Transform3D:
	var combined := Transform3D.IDENTITY
	var walk: Node = node
	while walk != null and walk != root:
		if walk is Node3D:
			combined = (walk as Node3D).transform * combined
		walk = walk.get_parent()
	return combined


## Union of every MeshInstance3D's AABB, in the model's own space.
func visual_bounds(node: Node) -> AABB:
	var bounds := AABB()
	var started := false
	for mesh_instance: MeshInstance3D in mesh_instances(node):
		var world := transform_within(node, mesh_instance) * mesh_instance.get_aabb()
		if not started:
			bounds = world
			started = true
		else:
			bounds = bounds.merge(world)
	return bounds


func mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for child: Node in node.get_children():
		found.append_array(mesh_instances(child))
	return found


func collect_port_names(node: Node, into: Array[String]) -> void:
	if node.name.begins_with("Port_"):
		into.append(String(node.name))
	for child: Node in node.get_children():
		collect_port_names(child, into)


func collect_material_names(node: Node, into: Array[String]) -> void:
	for mesh_instance: MeshInstance3D in mesh_instances(node):
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for surface: int in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface)
			if material != null and not into.has(String(material.resource_name)):
				into.append(String(material.resource_name))


func find_descendant(node: Node, wanted: String) -> Node:
	if String(node.name) == wanted:
		return node
	for child: Node in node.get_children():
		var hit := find_descendant(child, wanted)
		if hit != null:
			return hit
	return null


func check(passed: bool, description: String) -> void:
	checks += 1
	if passed:
		print("  ok   %s" % description)
	else:
		print("  FAIL %s" % description)
		failures.append(description)


func check_mm(description: String, actual: float, expected: float) -> void:
	check(absf(actual - expected) <= TOLERANCE_MM,
		"%s is %.2f mm, declared %.2f mm" % [description, actual, expected])


func finish() -> void:
	print("\n%d checks, %d failure(s)" % [checks, failures.size()])
	for failure: String in failures:
		print("  FAILED: %s" % failure)
	quit(1 if not failures.is_empty() else 0)
