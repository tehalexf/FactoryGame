## The baked Enemy bodies: a character mesh and a texture of bone poses, per Enemy kind.
##
## The seam is `EnemyBodies.body_for(kind)` — "give me the thing a `MultiMesh` draws a
## Crawler with". What comes back is one `Mesh`, one `ImageTexture` of skinning matrices,
## and the frame count of each clip. Nothing else in the renderer knows how a character
## is animated.
##
## **Why a bone-pose texture rather than a vertex one.** The established vertex-animation
## technique bakes every vertex of every frame, which for these characters is 4858
## vertices against ninety frames — half a million texels a kind, and a texture that grows
## with the model. Skinning matrices are 23 bones against the same ninety frames: 69 by 90,
## about two thousand texels, and it does not grow with the mesh at all. The shader then
## does the same four-bone linear blend any skinned mesh does, out of `CUSTOM0` and
## `CUSTOM1` on the baked surface. Same picture, three orders of magnitude less texture.
##
## **Why the bake is here and not in `tools/assets/`.** `world_view.gd` already flattens
## every Machine `.glb` into one mesh per material on first use, for exactly the reason
## this exists: what Godot imports from a glTF is the wrong *shape* to put in a `MultiMesh`,
## and the fix is a transform of a committed asset rather than a second committed asset.
## This is that flattening with a skinning bake attached, and it keeps the artist's file the
## one authority on what a Crawler looks like.
##
## These tests need the committed CC0 characters, which every clone has — unlike the
## purchased viewmodels. What they must not need is the *purchased* packs, and they do not.
extends TestCase


func _bodies() -> EnemyBodies:
	return EnemyBodies.new()


func test_every_enemy_kind_has_a_body_and_each_one_is_a_different_character() -> void:
	# The acceptance criterion: Crawler, Breaker and Siege Hulk each draw a distinct
	# character mesh. Distinctness is asserted on the geometry rather than on the file
	# names, because three recipes naming three files that happened to be copies would
	# pass the weaker check — this is the argument `machine_silhouette.py` makes for
	# Machines, at the cheapest version of itself.
	var bodies: EnemyBodies = _bodies()
	var seen: Array = []
	for kind: int in [
		Simulation.ENEMY_KIND_CRAWLER,
		Simulation.ENEMY_KIND_BREAKER,
		Simulation.ENEMY_KIND_SIEGE_HULK,
	]:
		var body: EnemyBodies.Body = bodies.body_for(kind)
		if not assert_not_null(body, "kind %d has a body" % kind):
			continue
		assert_true(
			body.mesh.get_surface_count() > 0,
			"kind %d's mesh has surfaces" % kind
		)
		var shape: String = "%d/%v" % [
			body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(),
			body.mesh.get_aabb().size.snappedf(0.01),
		]
		assert_false(seen.has(shape), "kind %d is not a copy of another: %s" % [kind, shape])
		seen.append(shape)
	assert_eq(seen.size(), 3, "three kinds, three distinct bodies")


func test_a_body_is_modelled_one_metre_tall_so_the_simulation_decides_how_big_it_is() -> void:
	# The renderer scales a body by `query_enemy_hit_height_metres`, which is the volume a
	# round is resolved against — so a body baked at the artist's own height would be a
	# second authority on how big an Enemy is. Normalised here, at the one place that has
	# the geometry in hand, and the scale is folded into the baked bone matrices rather
	# than into the vertices: skinning is `P * M * v`, and `P` is uniform, so it composes
	# onto each bone's matrix instead of needing a second pass over the mesh.
	#
	# Measured through `drawn_extent_metres`, which reads the matrices back out of the
	# texture and blends them exactly as the shader does. Deliberately the long way round:
	# a figure carried out of the bake would be the normalisation restated and could never
	# disagree with it.
	var bodies: EnemyBodies = _bodies()
	for kind: int in [
		Simulation.ENEMY_KIND_CRAWLER,
		Simulation.ENEMY_KIND_BREAKER,
		Simulation.ENEMY_KIND_SIEGE_HULK,
	]:
		var body: EnemyBodies.Body = bodies.body_for(kind)
		if not assert_not_null(body, "kind %d has a body" % kind):
			continue
		# Frame 0 of the move clip, which is a stride rather than the rest pose — so the
		# tolerance is a quarter of a metre rather than a millimetre. That is still tight
		# enough to catch any scale error worth the name: an unnormalised Golem would
		# measure three and a half.
		var extent: Vector2 = body.drawn_extent_metres(body.row_of(EnemyAnimator.MOVE, 0))
		assert_true(
			extent.x > -0.25 and extent.x < 0.25,
			"kind %d has its feet near the ground, not at %f" % [kind, extent.x]
		)
		assert_true(
			extent.y > 0.75 and extent.y < 1.25,
			"kind %d stands about one metre tall, not %f" % [kind, extent.y]
		)


func test_a_pose_texture_is_three_texels_a_bone_by_one_row_a_frame() -> void:
	# The layout the shader reads, asserted from the outside: a skinning matrix is three
	# rows of four, so a bone is three texels across, and one frame of animation is one row
	# down. Getting this wrong draws a character inside out, which no other test would say.
	var body: EnemyBodies.Body = _bodies().body_for(Simulation.ENEMY_KIND_CRAWLER)
	if not assert_not_null(body, "the Crawler's body baked"):
		return
	assert_eq(
		body.pose.get_width(),
		body.bone_count * EnemyBodies.TEXELS_PER_BONE,
		"three texels a bone"
	)
	assert_eq(body.pose.get_height(), body.frame_total, "one row a frame")
	assert_eq(
		body.pose.get_image().get_format(),
		Image.FORMAT_RGBAF,
		"full float, so a matrix survives the bake exactly rather than to eight bits"
	)


func test_every_role_the_animator_asks_for_resolves_to_frames_of_a_real_clip() -> void:
	# `EnemyAnimator` names three roles and a role a body does not carry would be a frame
	# read off the end of the texture. The suite asserts the pairing rather than trusting
	# it, because the names come from two files — a role here, a clip name in the recipe.
	var bodies: EnemyBodies = _bodies()
	for kind: int in [
		Simulation.ENEMY_KIND_CRAWLER,
		Simulation.ENEMY_KIND_BREAKER,
		Simulation.ENEMY_KIND_SIEGE_HULK,
	]:
		var body: EnemyBodies.Body = bodies.body_for(kind)
		if not assert_not_null(body, "kind %d has a body" % kind):
			continue
		for role: String in [EnemyAnimator.MOVE, EnemyAnimator.IDLE, EnemyAnimator.ATTACK]:
			var frames: int = body.frames_of(role)
			assert_true(frames > 1, "kind %d's %s clip has frames: %d" % [kind, role, frames])
			var last: int = body.row_of(role, frames - 1)
			assert_true(
				last >= 0 and last < body.frame_total,
				"kind %d's last %s frame is row %d of %d" % [kind, role, last, body.frame_total]
			)


func test_a_baked_clip_actually_moves_the_bones() -> void:
	# The honesty check beside the structural ones, and the shape `test_silo.gd` argues
	# for: every assertion above would pass on a texture of ninety identical rows, which
	# is exactly what a bake that lost its keyframes produces. The engine's own
	# `verify_in_godot.sh` makes this claim about a `.glb`; this makes it about the bake.
	var body: EnemyBodies.Body = _bodies().body_for(Simulation.ENEMY_KIND_CRAWLER)
	if not assert_not_null(body, "the Crawler's body baked"):
		return
	var frames: int = body.frames_of(EnemyAnimator.MOVE)
	var first: PackedByteArray = _row(body, body.row_of(EnemyAnimator.MOVE, 0))
	var moved: bool = false
	for frame: int in range(1, frames):
		if _row(body, body.row_of(EnemyAnimator.MOVE, frame)) != first:
			moved = true
			break
	assert_true(moved, "the move clip's %d frames are not all the same pose" % frames)

	# And the three roles are three different clips rather than one clip named thrice.
	assert_ne(
		_row(body, body.row_of(EnemyAnimator.MOVE, 0)),
		_row(body, body.row_of(EnemyAnimator.ATTACK, 0)),
		"moving and biting are different poses"
	)


func test_a_clip_never_walks_the_body_away_from_where_the_simulation_put_it() -> void:
	# The Simulation owns where an Enemy is; a clip owns how it looks getting there. A
	# forward-travelling walk cycle baked as authored would slide a Crawler out of its own
	# instance transform, so the root's horizontal translation is replaced by its rest
	# value on every frame. The vertical is kept, because that is the body's weight.
	var body: EnemyBodies.Body = _bodies().body_for(Simulation.ENEMY_KIND_CRAWLER)
	if not assert_not_null(body, "the Crawler's body baked"):
		return
	var frames: int = body.frames_of(EnemyAnimator.MOVE)
	var drift: float = 0.0
	for frame: int in range(frames):
		var at: Vector3 = body.root_offset_metres(body.row_of(EnemyAnimator.MOVE, frame))
		drift = maxf(drift, Vector2(at.x, at.z).length())
	assert_true(drift < 0.01, "the root stays put horizontally, not %f m out" % drift)


func test_a_surface_carries_the_bone_indices_and_weights_the_shader_blends_by() -> void:
	# `ARRAY_BONES` and `ARRAY_WEIGHTS` are only readable by a shader through a
	# `Skeleton3D`, which a `MultiMesh` has none of — so the bake moves them into
	# `CUSTOM0` and `CUSTOM1`, which are ordinary vertex attributes and reach the shader
	# unchanged. The surface carries no bones at all afterwards, so Godot does not try to
	# skin it a second way.
	var body: EnemyBodies.Body = _bodies().body_for(Simulation.ENEMY_KIND_CRAWLER)
	if not assert_not_null(body, "the Crawler's body baked"):
		return
	for surface: int in range(body.mesh.get_surface_count()):
		var format: int = body.mesh.surface_get_format(surface)
		assert_true(
			(format & Mesh.ARRAY_FORMAT_CUSTOM0) != 0,
			"surface %d carries bone indices" % surface
		)
		assert_true(
			(format & Mesh.ARRAY_FORMAT_CUSTOM1) != 0,
			"surface %d carries bone weights" % surface
		)
		assert_eq(
			format & Mesh.ARRAY_FORMAT_BONES,
			0,
			"and is not a skinned mesh any more, so nothing skins it twice"
		)


func test_the_weights_on_every_vertex_sum_to_one() -> void:
	# A linear blend whose weights do not sum to 1 shrinks the vertex towards the origin,
	# which reads as a character collapsing into its own feet. Godot's importer normalises,
	# but the bake drops any fifth and later influence to fit four texels of `CUSTOM0`, so
	# this is a claim about the bake rather than about the importer.
	var body: EnemyBodies.Body = _bodies().body_for(Simulation.ENEMY_KIND_CRAWLER)
	if not assert_not_null(body, "the Crawler's body baked"):
		return
	var weights: PackedFloat32Array = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM1]
	var worst: float = 0.0
	for vertex: int in range(weights.size() / 4):
		var total: float = (
			weights[vertex * 4 + 0]
			+ weights[vertex * 4 + 1]
			+ weights[vertex * 4 + 2]
			+ weights[vertex * 4 + 3]
		)
		worst = maxf(worst, absf(total - 1.0))
	assert_true(worst < 0.001, "the worst vertex is %f off unity" % worst)


func test_a_kind_with_no_recipe_has_no_body_rather_than_an_error() -> void:
	# "A missing asset is an ordinary state", which is the rule a Machine with no `.glb`
	# already obeys: the renderer draws its box. A kind nobody has cast a character for
	# must therefore come back empty rather than failing, so that adding an Enemy kind is
	# never blocked on art.
	assert_null(_bodies().body_for(999), "a kind with no recipe has no body")


func test_a_body_is_baked_once_and_handed_out_again() -> void:
	# The bake walks every bone of every frame of every clip, so a renderer asking once a
	# frame must get the cached answer. The same arrangement `world_view.gd`'s `_body()`
	# cache has, and for the same reason.
	var bodies: EnemyBodies = _bodies()
	var first: EnemyBodies.Body = bodies.body_for(Simulation.ENEMY_KIND_CRAWLER)
	var again: EnemyBodies.Body = bodies.body_for(Simulation.ENEMY_KIND_CRAWLER)
	if not assert_not_null(first, "the Crawler's body baked"):
		return
	assert_true(first == again, "the second ask is the same object, not a second bake")


## One row of a pose texture, as bytes, for comparing two frames without caring what a
## matrix means.
func _row(body: EnemyBodies.Body, row: int) -> PackedByteArray:
	var image: Image = body.pose.get_image()
	var bytes: PackedByteArray = PackedByteArray()
	for column: int in range(image.get_width()):
		var texel: Color = image.get_pixel(column, row)
		bytes.append_array(var_to_bytes(texel))
	return bytes
