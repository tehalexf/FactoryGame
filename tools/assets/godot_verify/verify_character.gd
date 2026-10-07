extends SceneTree

## Verify that a converted character actually works in Godot: that the engine's
## own glTF importer accepts it, that the rig arrives as a single-rooted
## Skeleton3D with shared-humanoid bone names, and that every animation plays
## and moves bones rather than merely existing in a list.
##
## Run through tools/assets/verify_in_godot.sh, which builds a throwaway Godot
## project around the asset and lets the editor import it first.

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: godot --headless --script verify_character.gd -- res://Model.glb")
		quit(2)
		return
	var path: String = args[0]
	var expected_height := float(args[1]) if args.size() > 1 else 0.0
	# How many animations this asset is expected to carry. A base rig legitimately
	# ships none; an animated character shipping none is a conversion failure.
	var min_animations := int(args[2]) if args.size() > 2 else 1

	print("=== verifying %s ===" % path)
	var scene := ResourceLoader.load(path) as PackedScene
	check(scene != null, "Godot imported %s as a PackedScene" % path)
	if scene == null:
		finish()
		return

	var model := scene.instantiate()
	check(model != null, "the imported scene instantiates")
	get_root().add_child(model)

	var skeleton := find_node(model, "Skeleton3D") as Skeleton3D
	check(skeleton != null, "the scene contains a Skeleton3D")
	if skeleton:
		var roots := skeleton.get_parentless_bones()
		check(roots.size() == 1,
			"the skeleton has exactly one root bone (found %d: %s)" % [
				roots.size(), bone_names_of(skeleton, roots)])
		print("    bones (%d): %s" % [skeleton.get_bone_count(), all_bone_names(skeleton)])
		report_humanoid_coverage(skeleton)

	var player := find_node(model, "AnimationPlayer") as AnimationPlayer
	if min_animations > 0:
		check(player != null, "the scene contains an AnimationPlayer")

	if player and skeleton:
		var names := player.get_animation_list()
		check(names.size() >= min_animations,
			"the character ships at least %d animation(s) (%d: %s)" % [
				min_animations, names.size(), ", ".join(names)])
		for anim_name in names:
			verify_animation_moves_bones(player, skeleton, anim_name)

	if expected_height > 0.0:
		var height := visual_height(model)
		check(absf(height - expected_height) < 0.05,
			"the character stands %.3f m, expected %.2f m" % [height, expected_height])

	finish()


func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  ok   %s" % description)
	else:
		print("  FAIL %s" % description)
		failures.append(description)


func finish() -> void:
	print("=== %d checks, %d failed ===" % [checks, failures.size()])
	for failure in failures:
		print("  failed: %s" % failure)
	quit(1 if failures.size() > 0 else 0)


func find_node(root: Node, type_name: String) -> Node:
	if root.is_class(type_name):
		return root
	for child in root.get_children():
		var found := find_node(child, type_name)
		if found:
			return found
	return null


func all_bone_names(skeleton: Skeleton3D) -> String:
	var names: Array[String] = []
	for i in skeleton.get_bone_count():
		names.append(skeleton.get_bone_name(i))
	return ", ".join(names)


func bone_names_of(skeleton: Skeleton3D, indices: PackedInt32Array) -> String:
	var names: Array[String] = []
	for i in indices:
		names.append(skeleton.get_bone_name(i))
	return ", ".join(names)


func report_humanoid_coverage(skeleton: Skeleton3D) -> void:
	## How much of the shared humanoid skeleton this rig covers. Reported rather
	## than asserted: sparse rigs (a 13-bone monster) legitimately cover a subset,
	## and the point is that the names they do have are the shared ones.
	var profile := SkeletonProfileHumanoid.new()
	var profile_names := {}
	for i in profile.bone_size:
		profile_names[String(profile.get_bone_name(i))] = true
	var matched: Array[String] = []
	var foreign: Array[String] = []
	for i in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(i)
		if profile_names.has(bone):
			matched.append(bone)
		else:
			foreign.append(bone)
	# The core chain every humanoid animation drives. A rig may legitimately carry
	# extra bones (IK pole targets, weapon sockets) and may legitimately lack
	# fingers or toes, but if these are missing or misnamed, animation written for
	# one character cannot drive another.
	var core := ["Root", "Hips", "Spine", "Neck", "Head",
		"LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm",
		"LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg"]
	var missing: Array[String] = []
	for bone in core:
		if not matched.has(bone):
			missing.append(bone)
	check(missing.is_empty(),
		"the rig carries the core shared-skeleton bones (missing: %s)" % [
			", ".join(missing) if not missing.is_empty() else "none"])
	check(not matched.is_empty() and no_near_misses(foreign, profile_names),
		"no bone is a near-miss variant of a shared-skeleton name (extras: %s)" % [
			", ".join(foreign) if not foreign.is_empty() else "none"])
	print("    shared-skeleton coverage: %d of this rig's %d bones; off-profile extras: %s" % [
		matched.size(), skeleton.get_bone_count(),
		", ".join(foreign) if not foreign.is_empty() else "none"])


func no_near_misses(foreign: Array[String], profile_names: Dictionary) -> bool:
	## A bone called "Hips.001" or "hips" means a rename went wrong, which is a
	## very different thing from an extra bone the profile has no slot for.
	for bone in foreign:
		var stem := bone.split(".")[0]
		if profile_names.has(stem) or profile_names.has(stem.capitalize()):
			print("    near-miss bone name: %s" % bone)
			return false
	return true


func verify_animation_moves_bones(player: AnimationPlayer, skeleton: Skeleton3D,
		anim_name: String) -> void:
	var animation := player.get_animation(anim_name)
	var length := animation.length
	player.play(anim_name)
	player.seek(0.0, true)
	var before := pose_snapshot(skeleton)
	player.advance(maxf(length * 0.5, 0.05))
	var after := pose_snapshot(skeleton)
	var movement := pose_difference(before, after)
	check(movement > 0.0001,
		"animation %s (%.2fs) moves the skeleton when played (max bone delta %.5f)" % [
			anim_name, length, movement])


func pose_difference(before: PackedFloat32Array, after: PackedFloat32Array) -> float:
	var largest := 0.0
	for i in before.size():
		largest = maxf(largest, absf(after[i] - before[i]))
	return largest


func pose_snapshot(skeleton: Skeleton3D) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	for i in skeleton.get_bone_count():
		var pose := skeleton.get_bone_pose(i)
		values.append(pose.origin.x)
		values.append(pose.origin.y)
		values.append(pose.origin.z)
		var quaternion := pose.basis.get_rotation_quaternion()
		values.append(quaternion.x)
		values.append(quaternion.y)
		values.append(quaternion.z)
		values.append(quaternion.w)
	return values


func visual_height(root: Node) -> float:
	var lowest := INF
	var highest := -INF
	for mesh_instance in find_all_meshes(root):
		var aabb := mesh_instance.get_aabb()
		# In a --script SceneTree run the nodes are not considered inside the tree,
		# so fall back to the local transform rather than warning on every mesh.
		var transform := mesh_instance.global_transform if mesh_instance.is_inside_tree() \
			else mesh_instance.transform
		for corner in 8:
			var point := transform * aabb.get_endpoint(corner)
			lowest = minf(lowest, point.y)
			highest = maxf(highest, point.y)
	return 0.0 if lowest == INF else highest - lowest


func find_all_meshes(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		found.append(root)
	for child in root.get_children():
		found.append_array(find_all_meshes(child))
	return found
