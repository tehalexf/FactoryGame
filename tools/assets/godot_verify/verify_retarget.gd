extends SceneTree

## Prove that animation is interchangeable between characters: take an animation
## authored for one character and play it on another character's rig, with no
## conversion at playback time.
##
## This only works because both rigs were converted onto the shared humanoid
## skeleton, so the animation's bone tracks name bones the other skeleton also
## has. It is the thing the shared-skeleton convention buys, so it is worth
## checking rather than asserting in prose.
##
## Run through tools/assets/verify_retarget_in_godot.sh.

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("usage: ... -- res://Donor.glb <animation name> res://Recipient.glb")
		quit(2)
		return
	var donor_path: String = args[0]
	var animation_name: String = args[1]
	var recipient_path: String = args[2]

	print("=== retargeting %s from %s onto %s ===" % [
		animation_name, donor_path.get_file(), recipient_path.get_file()])

	var donor := instantiate(donor_path)
	var recipient := instantiate(recipient_path)
	if donor == null or recipient == null:
		finish()
		return

	var donor_player := find_node(donor, "AnimationPlayer") as AnimationPlayer
	var recipient_player := find_node(recipient, "AnimationPlayer") as AnimationPlayer
	var recipient_skeleton := find_node(recipient, "Skeleton3D") as Skeleton3D
	check(donor_player != null and recipient_player != null and recipient_skeleton != null,
		"both characters import with an AnimationPlayer and the recipient has a Skeleton3D")
	if donor_player == null or recipient_player == null or recipient_skeleton == null:
		finish()
		return

	check(donor_player.has_animation(animation_name),
		"the donor carries %s (has: %s)" % [
			animation_name, ", ".join(donor_player.get_animation_list())])
	if not donor_player.has_animation(animation_name):
		finish()
		return

	var animation: Animation = donor_player.get_animation(animation_name).duplicate()

	# Which of the donor's bone tracks name a bone the recipient also has? That
	# count is the measure of how interchangeable the two rigs are.
	var shared := 0
	var unmatched: Array[String] = []
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		var bone := String(path.get_concatenated_subnames())
		if bone.is_empty():
			continue
		if recipient_skeleton.find_bone(bone) != -1:
			shared += 1
		elif not unmatched.has(bone):
			unmatched.append(bone)
	check(shared > 0, "the donor's animation names bones the recipient has (%d tracks)" % shared)
	print("    tracks the recipient cannot use: %s" % [
		", ".join(unmatched) if not unmatched.is_empty() else "none"])

	# Re-root the tracks at the recipient's own Skeleton3D and play it there.
	var skeleton_path := String(recipient_player.get_node(
		recipient_player.root_node).get_path_to(recipient_skeleton))
	for track in animation.get_track_count():
		var subnames := animation.track_get_path(track).get_concatenated_subnames()
		if not String(subnames).is_empty():
			animation.track_set_path(track, NodePath("%s:%s" % [skeleton_path, subnames]))

	var library := AnimationLibrary.new()
	library.add_animation("borrowed", animation)
	recipient_player.add_animation_library("donor", library)

	var before := pose_snapshot(recipient_skeleton)
	recipient_player.play("donor/borrowed")
	recipient_player.seek(0.0, true)
	recipient_player.advance(maxf(animation.length * 0.5, 0.05))
	var after := pose_snapshot(recipient_skeleton)
	var movement := difference(before, after)
	check(movement > 0.0001,
		"the borrowed animation moves the recipient's skeleton (max bone delta %.5f)" % movement)

	finish()


func instantiate(path: String) -> Node:
	var scene := ResourceLoader.load(path) as PackedScene
	check(scene != null, "Godot imported %s" % path)
	if scene == null:
		return null
	var node := scene.instantiate()
	get_root().add_child(node)
	return node


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


func difference(before: PackedFloat32Array, after: PackedFloat32Array) -> float:
	var largest := 0.0
	for i in before.size():
		largest = maxf(largest, absf(after[i] - before[i]))
	return largest
