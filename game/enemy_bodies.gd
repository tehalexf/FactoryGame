## The thing a `MultiMesh` draws an Enemy with: one character mesh, and one texture of
## skinning matrices covering every frame of every clip that Enemy plays.
##
## **The constraint this file exists to satisfy is ADR 0001's: an Enemy is never a node.**
## The Chaff tier is thousands of Crawlers and `test_world_view` asserts the scene tree
## does not gain one node when a Wave arrives, so an `AnimationPlayer` per Crawler — the
## idiomatic answer, and the one that caps out around 150-250 agents — is exactly the
## architecture this project refused. The animation therefore has to live somewhere a
## `MultiMesh` can reach, which means a texture the vertex shader samples and a per-instance
## number saying which row to read.
##
## ### Bone poses, not vertex positions
##
## The technique named in the ticket is a vertex animation texture: bake every vertex's
## position on every frame. For these characters that is 4858 vertices by ninety frames —
## 437,000 texels a kind, three kinds, and a texture whose size is a property of the model
## rather than of the rig.
##
## This bakes the **skinning matrices** instead: 23 bones by ninety frames is 69 by 90, about
## two thousand texels, and it does not grow by one texel if somebody triples the polygon
## count. The shader then does the four-bone linear blend any skinned mesh does. The one
## thing it costs is getting the bone indices and weights to the shader, and `ARRAY_BONES`
## is only readable through a `Skeleton3D` — which is why `_surface_arrays` moves them into
## `CUSTOM0` and `CUSTOM1`, ordinary vertex attributes that reach a shader unchanged.
##
## ### Why the bake is at load time rather than in `tools/assets/`
##
## `world_view.gd` already flattens every Machine `.glb` into one mesh per material on first
## use, and the reason is the same one: **what Godot imports out of a glTF is the wrong
## shape to put in a `MultiMesh`**, and the fix is a transform of a committed asset rather
## than a second committed asset. A `tools/assets/` bake step would commit a derived mesh and
## a derived texture beside the artist's file and give the project two authorities on what a
## Crawler looks like — the thing `machines.csv` against `machine_bodies.csv` is careful to
## avoid. So this is that same flattening with a skinning bake attached.
##
## It is paid once per kind, lazily, on the frame the first Enemy of that kind appears. See
## `_bake` for what that costs.
##
## ### Nothing here is chosen at random and nothing is timed by a clock
##
## The bake is a pure function of the committed `.glb`s, so two Runs get the same texture,
## and `EnemyAnimator` picks the row out of hashed Simulation facts. The animation is as
## reproducible as the Simulation is, which is the rule `WeaponViewmodel` keeps by computing
## clip time from the tick count and seeking explicitly.
class_name EnemyBodies
extends RefCounted

## A skinning matrix is a 3x4 affine, so three RGBA texels hold one bone.
const TEXELS_PER_BONE: int = 3

## How many bone influences a vertex keeps. Godot's glTF importer gives four unless the
## surface asks for eight, and all thirteen committed characters use four — so a fifth
## influence is a case the committed art does not contain, and `_surface_arrays` drops
## and renormalises rather than silently scaling the vertex towards the origin.
const INFLUENCES: int = 4

## The bake's frame rate. Half the Simulation's tick rate, so `EnemyAnimator` advances one
## frame every two ticks — an exact integer division rather than a ratio with a rounding
## rule, which is the arrangement every other counted thing in this project has.
const FRAMES_PER_SECOND: float = 30.0

## The longest any one clip may be baked for, in frames. A ceiling rather than an
## expectation: an idle take is often several seconds and a texture row a frame is cheap,
## but a library carrying a two-minute clip should not silently become a 3600-row texture.
const MAX_FRAMES_PER_CLIP: int = 120

## Where the generated bodies live.
##
## **#79 replaced a cast with a declaration, and that is the one change to this file's
## premise.** #38 cast three KayKit CC0 characters because they existed and shared one rig;
## the asset was still a fantasy skeleton in a world of cast iron, and the user said so.
## `tools/assets/enemy_recipe.py` declares three insects as proportions and a gait and
## `generate_enemies.sh` builds them, so these three `.glb` are this project's own work and
## are **committed** — the arrangement the Machine meshes and the Build Gun already have,
## proved by `tools/assets/tests/test_generated_enemies.py` regenerating and comparing the
## bytes rather than by `asset_staleness.py` dating them (#57).
##
## Two consequences for the bake, and both of them make it cheaper. **Each body carries its
## own clips**, so a recipe's `libraries` names the character itself rather than a separate
## shared-rig library — these are three different rigs, so a library between them could only
## carry the bones they have in common. And **every vertex has exactly one influence at
## weight 1**: a chitin plate is rigid, so `_influences`' four-heaviest rule has nothing to
## drop and `_merge` renormalises a sum that is already one.
const INSECTS: String = "res://assets/characters/insects/"

## The node a generated body names its weak point with. One string, read here and written
## by `tools/assets/generate_enemies.py`.
const VENT_MARKER: String = "Vent"

## The two views a silhouette is measured in: head-on down the lane an Enemy walks, and
## along it. Both, for `machine_silhouette.py`'s reason — a player moves, so two kinds that
## are identical head-on and obviously different side-on are still tellable apart.
const VIEW_FRONT: int = 0
const VIEW_SIDE: int = 1

## The frame a silhouette is rasterised in, in metres. Shared by every kind rather than
## fitted to each, because **absolute size is part of a silhouette**: a 3.2 m Siege Hulk and
## a 1.6 m Crawler are told apart by being different sizes, and normalising each to fill the
## frame would throw away the one cue that survives at any range. 4.6 m clears the tallest
## Enemy the content declares with room for a taller one.
const SILHOUETTE_FRAME_METRES: float = 4.6

## Cells across and up, and the number is the player's own resolution at thirty metres
## rather than a chosen coarseness. `player.field_of_view_degrees` is 75 over a 720-line
## view, which is 550 pixels a radian, so at 30 m one metre is 18.3 pixels and this frame is
## 84 of them. **Measuring at one cell a pixel is what makes the gate ungameable**: detail
## finer than a cell cannot move the score, and detail finer than a cell is detail a player
## at thirty metres cannot see either. `machine_silhouette.py` argues its 28 cm a cell the
## other way round, from the size of a hydraulic ram, because a Machine is read at fifty
## metres and at five.
const SILHOUETTE_CELLS: int = 84


## How far apart two outlines are: 1 - intersection over union. 0.0 is the same outline,
## 1.0 shares no cell. The measure `machine_silhouette.jaccard_distance` uses, so the two
## gates report a number that means the same thing.
static func jaccard_distance(left: PackedByteArray, right: PackedByteArray) -> float:
	var shared: int = 0
	var either: int = 0
	for cell: int in range(mini(left.size(), right.size())):
		var in_left: bool = left[cell] != 0
		var in_right: bool = right[cell] != 0
		if in_left and in_right:
			shared += 1
		if in_left or in_right:
			either += 1
	if either == 0:
		return 0.0
	return 1.0 - float(shared) / float(either)


## How far apart two kinds look: the view that disagrees most. The *best* view rather than
## the average, because a player walks around a Wave as readily as a Factory — two kinds
## identical head-on but obviously different in profile are still tellable apart.
static func separation(left: Dictionary, right: Dictionary) -> float:
	var worst: float = 0.0
	for view: int in [VIEW_FRONT, VIEW_SIDE]:
		worst = maxf(worst, jaccard_distance(left[view], right[view]))
	return worst


## Which character and which clips an Enemy kind is made of.
##
## **This is the whole of the casting, and it is the one place a kind and an asset meet.**
## The Golem is the Siege Hulk and the Minion is the Crawler because the ticket says so and
## because they are the obvious reads; the Warrior is the Breaker because it is the one
## committed character that is visibly *armoured and carrying something*, which is what has
## to separate "the threat" from "the sense of threat" at thirty metres.
class Recipe extends RefCounted:
	## The character `.glb`, which carries the mesh and the rig and no animation at all.
	var character: String = ""
	## The animation libraries to resolve clip names against, in order. KayKit ships its
	## animation as separate files on a shared rig — the arrangement
	## `docs/ASSET_PIPELINE.md` section 4 calls the worked example of doing it right — so
	## movement and everything else are two files.
	var libraries: PackedStringArray = PackedStringArray()
	## Role to clip name. A role is what the game asks for and a clip name is what the pack
	## happens to call it, which is the split `WeaponAnimator.CLIP_NEEDLES` already makes.
	var clips: Dictionary = {}

	func _init(
		from_character: String, from_libraries: PackedStringArray, from_clips: Dictionary
	) -> void:
		character = from_character
		libraries = from_libraries
		clips = from_clips


## One kind's baked body.
class Body extends RefCounted:
	## One `Mesh`, one surface per source material, ready to go in a `MultiMesh`.
	var mesh: ArrayMesh = null
	## The skinning matrices: `bone_count * TEXELS_PER_BONE` across, `frame_total` down.
	var pose: ImageTexture = null
	var bone_count: int = 0
	var frame_total: int = 0

	## Where this kind's weak point is, in the body's own normalised units and in Godot
	## axes — `+y` up, `+z` the way it faces — or `Vector3.ZERO` for a kind whose `.glb`
	## declares none.
	##
	## **It is read out of the mesh rather than held as a constant in `world_view.gd`**, and
	## that is #79's one addition to this class. The Siege Hulk's vent is the only place in
	## this project where geometry carries a rule (#16), and it used to be placed by a pair
	## of numbers in the renderer while the body it is an opening in was somebody else's art
	## — so the two could come apart with nothing saying so. `enemy_recipe` derives the tail's
	## far face from the abdomen's own declaration and `generate_enemies` exports it as a
	## marker node, exactly as a Machine's `Port_*` markers are exported: one authority, and
	## editing `abdomen_rise` moves the glow with the tail.
	var vent_offset: Vector3 = Vector3.ZERO

	var _frames: Dictionary = {}
	var _first_row: Dictionary = {}
	var _root_offsets: PackedFloat32Array = PackedFloat32Array()

	## How many frames a role's clip runs for, or 1 for a role this body has no clip for —
	## never 0, because a count of 0 is a modulus by zero in the animator.
	func frames_of(role: String) -> int:
		return int(_frames.get(role, 1))

	## Which row of the pose texture is this frame of this role's clip. Out-of-range frames
	## are wrapped rather than clamped, because the animator's own modulus is the thing
	## that should decide and a second clamp here would hide a disagreement.
	func row_of(role: String, frame: int) -> int:
		var frames: int = frames_of(role)
		var first: int = int(_first_row.get(role, 0))
		return first + posmod(frame, frames)

	## Where the root bone sits on this row, relative to its rest, in metres. The suite
	## reads it to assert a walk cycle does not travel; nothing in the renderer does.
	func root_offset_metres(row: int) -> Vector3:
		if row < 0 or (row + 1) * 3 > _root_offsets.size():
			return Vector3.ZERO
		return Vector3(
			_root_offsets[row * 3 + 0], _root_offsets[row * 3 + 1], _root_offsets[row * 3 + 2]
		)

	## What `EnemyAnimator.set_frame_counts` wants.
	func frame_counts() -> Dictionary:
		return _frames.duplicate()

	## How low and how high the body stands on one row of the pose texture, in metres,
	## **measured by doing what the shader does**: read the matrices back out of the
	## texture, blend them by the weights on `CUSTOM1`, and look at where the vertices
	## land.
	##
	## The suite reads it to check the scale, and it is deliberately the long way round. A
	## figure carried out of `_bake` would be the normalisation restated — 0 and 1 by
	## construction, which is an assertion that cannot disagree with the code and so says
	## nothing. This is an independent measurement of the thing a player will see, and it
	## fails if the matrices are written to the wrong texel, composed in the wrong order,
	## or folded with the wrong normalisation.
	##
	## Walks every `stride`-th vertex, because the point is the extent and five thousand
	## vertices measure it no better than five hundred.
	func drawn_extent_metres(row: int, stride: int = 7) -> Vector2:
		var matrices: Array[Transform3D] = _matrices_of(row)

		var low: float = INF
		var high: float = -INF
		for surface: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var slots: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
			var loads: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM1]
			for vertex: int in range(0, points.size(), maxi(stride, 1)):
				var at: Vector3 = Vector3.ZERO
				for influence: int in range(INFLUENCES):
					var weight: float = loads[vertex * INFLUENCES + influence]
					if weight <= 0.0:
						continue
					var bone: int = int(slots[vertex * INFLUENCES + influence])
					if bone < 0 or bone >= matrices.size():
						continue
					at += (matrices[bone] * points[vertex]) * weight
				low = minf(low, at.y)
				high = maxf(high, at.y)
		return Vector2(low, high)

	## The skinning matrices on one row of the pose texture, read back out of the texture
	## exactly as the shader reads them. `drawn_extent_metres` and `silhouette` are both
	## measurements of what a player sees, so they go through one read rather than two.
	func _matrices_of(row: int) -> Array[Transform3D]:
		var image: Image = pose.get_image()
		var matrices: Array[Transform3D] = []
		for bone: int in range(bone_count):
			var rows: Array[Color] = []
			for texel: int in range(TEXELS_PER_BONE):
				rows.append(image.get_pixel(bone * TEXELS_PER_BONE + texel, row))
			matrices.append(Transform3D(
				Basis(
					Vector3(rows[0].r, rows[1].r, rows[2].r),
					Vector3(rows[0].g, rows[1].g, rows[2].g),
					Vector3(rows[0].b, rows[1].b, rows[2].b)
				),
				Vector3(rows[0].a, rows[1].a, rows[2].a)
			))
		return matrices

	## This body's outline, posed on one row of the pose texture and standing `metres` tall,
	## as one bit a cell with row 0 at the ground — the occupancy grid
	## `tools/assets/machine_silhouette.py` rasterises a Machine into, pointed at an Enemy.
	##
	## **It is skinned, scaled and projected rather than read off the rest pose**, because all
	## three of those are what a player is looking at: the Crawler runs where the Breaker
	## walks, `query_enemy_hit_height_metres` is what each one is drawn at, and a body baked
	## one metre tall says nothing about either until it has been through both.
	func silhouette(row: int, metres: float, view: int) -> PackedByteArray:
		var cells: int = EnemyBodies.SILHOUETTE_CELLS
		var cell: float = EnemyBodies.SILHOUETTE_FRAME_METRES / float(cells)
		var half: float = EnemyBodies.SILHOUETTE_FRAME_METRES * 0.5
		var grid: PackedByteArray = PackedByteArray()
		grid.resize(cells * cells)
		grid.fill(0)
		var matrices: Array[Transform3D] = _matrices_of(row)

		for surface: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var slots: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
			var loads: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM1]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

			# Every vertex is skinned once and the triangles are rasterised off that.
			# Skinning inside the triangle loop would do the four-bone blend three times a
			# face, and these meshes carry about five thousand vertices each.
			var flat: PackedVector2Array = PackedVector2Array()
			flat.resize(points.size())
			for vertex: int in range(points.size()):
				var at: Vector3 = Vector3.ZERO
				for influence: int in range(INFLUENCES):
					var weight: float = loads[vertex * INFLUENCES + influence]
					if weight <= 0.0:
						continue
					var bone: int = int(slots[vertex * INFLUENCES + influence])
					if bone < 0 or bone >= matrices.size():
						continue
					at += (matrices[bone] * points[vertex]) * weight
				at *= metres
				flat[vertex] = Vector2(
					at.z if view == EnemyBodies.VIEW_SIDE else at.x, at.y
				)

			for corner: int in range(0, indices.size() - 2, 3):
				_cover(
					grid,
					flat[indices[corner]],
					flat[indices[corner + 1]],
					flat[indices[corner + 2]],
					cell,
					cells,
					half
				)
		return grid

	## One triangle's cells, filled where it covers a cell's centre. No anti-aliasing, for
	## `machine_silhouette.py`'s reason: a sliver that half-filled a cell would let detailing
	## move a score that is supposed to be about gross form.
	func _cover(
		grid: PackedByteArray,
		a: Vector2,
		b: Vector2,
		c: Vector2,
		cell: float,
		cells: int,
		half: float
	) -> void:
		var area: float = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
		if absf(area) < 0.000000000001:
			return
		var low_column: int = maxi(0, int((minf(minf(a.x, b.x), c.x) + half) / cell))
		var high_column: int = mini(
			cells - 1, int((maxf(maxf(a.x, b.x), c.x) + half) / cell)
		)
		var low_row: int = maxi(0, int(minf(minf(a.y, b.y), c.y) / cell))
		var high_row: int = mini(cells - 1, int(maxf(maxf(a.y, b.y), c.y) / cell))
		for row: int in range(low_row, high_row + 1):
			var y: float = (row + 0.5) * cell
			var base: int = row * cells
			for column: int in range(low_column, high_column + 1):
				if grid[base + column] != 0:
					continue
				var x: float = (column + 0.5) * cell - half
				var first: float = (
					(b.x - a.x) * (y - a.y) - (x - a.x) * (b.y - a.y)
				) / area
				var second: float = (
					(c.x - b.x) * (y - b.y) - (x - b.x) * (c.y - b.y)
				) / area
				var third: float = (
					(a.x - c.x) * (y - c.y) - (x - c.x) * (a.y - c.y)
				) / area
				if (
					(first >= 0.0 and second >= 0.0 and third >= 0.0)
					or (first <= 0.0 and second <= 0.0 and third <= 0.0)
				):
					grid[base + column] = 1


var _baked: Dictionary = {}


## The body for an Enemy kind, baked on the first ask and handed out again after.
##
## Returns null for a kind nobody has cast a character for and for one whose character is
## not on disk. **That is an ordinary state and not a warning**, the rule a Machine with no
## generated `.glb` already obeys: adding an Enemy kind is four tuning keys and a row, and it
## is never blocked on art. `WorldView` draws the procedural carapace it always drew.
func body_for(kind: int) -> Body:
	if _baked.has(kind):
		return _baked[kind]
	var body: Body = _bake(kind)
	_baked[kind] = body
	return body


## Which body and which clips each kind is made of.
##
## Static and in one place, so the casting is readable without reading the bake. A kind with
## no entry has no body, which is what makes adding a kind cost nothing here.
##
## **The three bodies are generated and committed, and the roles are the same three.** What
## changed with #79 is only the asset: `enemy_recipe.py` declares the proportions and the
## gaits, and the four clips travel inside each body's own `.glb`, so `libraries` names the
## character itself. Every body carries all four clips and every one of them is read by some
## kind, which is why `walk` and `run` are both here — a clip nothing names would be the
## asset-pipeline version of a tuning key nothing reads.
##
## The *choice* of gait per kind survives #38's reasoning unchanged, because it was never
## about the art: Chaff has to read as **numerous and coming**, so a Crawler runs; a Breaker
## marches the Nest's own lane under fire (#34), so it walks, and that contrast is the
## clearest thing separating the sense of threat from the threat in motion.
static func recipe_for(kind: int) -> Recipe:
	match kind:
		EnemyKind.CRAWLER:
			return Recipe.new(
				INSECTS + "crawler.glb",
				PackedStringArray([INSECTS + "crawler.glb"]),
				{
					EnemyAnimator.MOVE: "run",
					EnemyAnimator.IDLE: "idle",
					EnemyAnimator.ATTACK: "attack",
				}
			)
		EnemyKind.BREAKER:
			return Recipe.new(
				INSECTS + "breaker.glb",
				PackedStringArray([INSECTS + "breaker.glb"]),
				{
					EnemyAnimator.MOVE: "walk",
					EnemyAnimator.IDLE: "idle",
					EnemyAnimator.ATTACK: "attack",
				}
			)
		EnemyKind.SIEGE_HULK:
			# **The one role that was a stand-in is not one any more.** #38 played the
			# Golem's `Hit_A` for a stomp because `Rig_Large` carried no attack take at
			# all; a declared body declares its own, so the boss bites with the same
			# authored gesture the other two do.
			return Recipe.new(
				INSECTS + "siege_hulk.glb",
				PackedStringArray([INSECTS + "siege_hulk.glb"]),
				{
					EnemyAnimator.MOVE: "walk",
					EnemyAnimator.IDLE: "idle",
					EnemyAnimator.ATTACK: "attack",
				}
			)
	return null


## Bakes one kind: load the character, load its libraries, walk every frame of every clip
## composing a skinning matrix per bone, and write the lot into one float texture.
##
## **The cost is bones times frames and not vertices times frames**, which is what makes it
## affordable at load time: 23 bones over about 150 frames is 3,450 transforms a kind, each
## one a couple of multiplies up a 23-deep hierarchy. The mesh is walked exactly once, to
## move its bone attributes into `CUSTOM0` and `CUSTOM1`.
##
## **It composes the poses itself rather than driving an `AnimationPlayer`.** Three reasons,
## and the third is the one that matters: a player has to be in a `SceneTree` to resolve its
## track paths, `advance` is a side effect on a node this function would have to own and
## free, and interpolating an `Animation` directly is a pure read of a `Resource` — which is
## what makes the retarget below expressible at all.
func _bake(kind: int) -> Body:
	var recipe: Recipe = recipe_for(kind)
	if recipe == null or not ResourceLoader.exists(recipe.character):
		return null
	var scene: PackedScene = load(recipe.character) as PackedScene
	if scene == null:
		return null
	var root: Node = scene.instantiate()
	var skeleton: Skeleton3D = _first_skeleton(root)
	if skeleton == null:
		root.free()
		return null

	var bones: int = skeleton.get_bone_count()
	var bone_of_name: Dictionary = {}
	for bone: int in range(bones):
		bone_of_name[skeleton.get_bone_name(bone)] = bone

	# Where every bone sits with no animation on it. Composed up the hierarchy here rather
	# than taken from `get_bone_global_rest`, so that the rest and the animated poses go
	# through exactly one piece of arithmetic and cannot disagree about it.
	var rest_local: Array[Transform3D] = []
	for bone: int in range(bones):
		rest_local.append(skeleton.get_bone_rest(bone))
	var rest_global: Array[Transform3D] = _compose(skeleton, rest_local)

	# The inverse bind matrices, which are what take a vertex out of the mesh's own space
	# and into the bone's. Resolved by **name**: Godot's glTF importer leaves
	# `Skin.get_bind_bone` at -1 and names the bind instead, which is checked rather than
	# assumed because a silent -1 would index the first bone for every vertex.
	var surfaces: Array = []
	var binds: Array[Transform3D] = []
	var bind_resolved: bool = false
	for child: Node in skeleton.get_children():
		if not (child is MeshInstance3D):
			continue
		var holder: MeshInstance3D = child
		if holder.mesh == null:
			continue
		if not bind_resolved and holder.skin != null:
			binds = _binds(holder.skin, bone_of_name, bones)
			bind_resolved = true
		for surface: int in range(holder.mesh.get_surface_count()):
			surfaces.append([holder.mesh, surface])
	if not bind_resolved or surfaces.is_empty():
		root.free()
		return null

	# The rest pose's extent, which is what the normalisation is derived from. Measured on
	# the skinned rest rather than on the raw vertices, because a rig whose mesh is authored
	# away from its rest would otherwise normalise to the wrong number.
	var low: float = INF
	var high: float = -INF
	for entry: Array in surfaces:
		var arrays: Array = (entry[0] as ArrayMesh).surface_get_arrays(entry[1])
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per: int = INFLUENCES
		if points.size() > 0 and indices.size() / points.size() == 8:
			per = 8
		for vertex: int in range(points.size()):
			var at: Vector3 = _skinned(
				points[vertex], vertex, per, indices, weights, rest_global, binds
			)
			low = minf(low, at.y)
			high = maxf(high, at.y)
	if not (high > low):
		root.free()
		return null
	# `P`, the normalisation: one metre tall with its feet on the ground. Folded onto every
	# bone matrix rather than applied to the vertices, because skinning is a weighted sum
	# whose weights total 1, so `P * (sum w M v)` is `sum w (P M) v` — one multiply a bone a
	# frame instead of a second pass over five thousand vertices.
	var scale: float = 1.0 / (high - low)
	var normalise: Transform3D = Transform3D(
		Basis.from_scale(Vector3.ONE * scale), Vector3(0.0, -low * scale, 0.0)
	)

	var body: Body = Body.new()
	body.bone_count = bones
	# Through the same normalisation the bone matrices get, so the vent lands where the
	# body does however the declaration moves. The marker is authored in normalised units
	# already, so this is the identity on a body one metre tall — applied anyway, because
	# "the same transform" is the claim rather than "the same number".
	body.vent_offset = _vent_offset(root, normalise)

	# Every clip, in a fixed order, so the texture's rows are a function of the recipe and
	# not of whatever order a Dictionary iterates in. That is determinism rule four applied
	# to an asset: the roles are sorted, so two Runs lay out the same texture.
	var clips: Array = recipe.clips.keys()
	clips.sort()
	var animations: Dictionary = _animations(recipe)
	var rows: Array[Transform3D] = []
	var root_offsets: PackedFloat32Array = PackedFloat32Array()
	for role: String in clips:
		var clip: Animation = animations.get(recipe.clips.get(role, ""), null) as Animation
		var frames: int = 1
		if clip != null:
			frames = clampi(
				int(round(clip.length * FRAMES_PER_SECOND)), 1, MAX_FRAMES_PER_CLIP
			)
		body._first_row[role] = rows.size() / bones
		body._frames[role] = frames
		for frame: int in range(frames):
			var at: float = 0.0
			if clip != null and frames > 1:
				at = clip.length * float(frame) / float(frames)
			var local: Array[Transform3D] = _pose(
				clip, at, skeleton, rest_local, bone_of_name
			)
			var posed: Array[Transform3D] = _compose(skeleton, local)
			var offset: Vector3 = local[0].origin - rest_local[0].origin
			root_offsets.append_array(
				PackedFloat32Array([offset.x, offset.y, offset.z])
			)
			for bone: int in range(bones):
				rows.append(normalise * posed[bone] * binds[bone])

	body.frame_total = rows.size() / bones
	body._root_offsets = root_offsets
	body.pose = _texture(rows, bones, body.frame_total)
	body.mesh = _flatten(surfaces, rest_global, binds)
	root.free()
	return body


## Every bone's transform relative to the skeleton, from its transform relative to its
## parent. One walk, in index order, which Godot guarantees puts a parent before its child.
func _compose(skeleton: Skeleton3D, local: Array[Transform3D]) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(local.size())
	for bone: int in range(local.size()):
		var parent: int = skeleton.get_bone_parent(bone)
		if parent < 0:
			out[bone] = local[bone]
		else:
			out[bone] = out[parent] * local[bone]
	return out


## One frame of a clip as a local transform per bone.
##
## **This is the retarget, and it is three lines of it**, because
## `docs/ASSET_PIPELINE.md` section 3 did the work: every rig in this repository is already
## named with Godot's `SkeletonProfileHumanoid` bone names, so a clip drives the bone it was
## authored for by *matching its name*. A bone the clip says nothing about keeps its rest,
## which is how a sparse rig plays a clip authored for a denser one — section 4's "sparse
## rigs are fine; they simply cover a subset of the profile".
##
## The root's **horizontal** translation is replaced by its rest on every frame. The
## Simulation owns where an Enemy is, so a forward-travelling walk cycle baked as authored
## would slide a Crawler out of the instance transform the renderer put it in. The vertical
## is kept, because that is the body's weight.
func _pose(
	clip: Animation,
	at: float,
	skeleton: Skeleton3D,
	rest_local: Array[Transform3D],
	bone_of_name: Dictionary
) -> Array[Transform3D]:
	var local: Array[Transform3D] = rest_local.duplicate()
	if clip == null:
		return local
	for track: int in range(clip.get_track_count()):
		var bone: int = int(bone_of_name.get(String(clip.track_get_path(track).get_concatenated_subnames()), -1))
		if bone < 0:
			continue
		var was: Transform3D = local[bone]
		match clip.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				var moved: Vector3 = clip.position_track_interpolate(track, at)
				if skeleton.get_bone_parent(bone) < 0:
					moved = Vector3(rest_local[bone].origin.x, moved.y, rest_local[bone].origin.z)
				local[bone] = Transform3D(was.basis, moved)
			Animation.TYPE_ROTATION_3D:
				var turned: Quaternion = clip.rotation_track_interpolate(track, at)
				local[bone] = Transform3D(
					Basis(turned).scaled(was.basis.get_scale()), was.origin
				)
			Animation.TYPE_SCALE_3D:
				var sized: Vector3 = clip.scale_track_interpolate(track, at)
				local[bone] = Transform3D(
					Basis(was.basis.get_rotation_quaternion()).scaled(sized), was.origin
				)
	return local


## Every clip in every library the recipe names, by name. Earlier libraries win, so a recipe
## can put the movement file first and know which `T-Pose` it got.
func _animations(recipe: Recipe) -> Dictionary:
	var out: Dictionary = {}
	for path: String in recipe.libraries:
		if not ResourceLoader.exists(path):
			continue
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			continue
		var root: Node = scene.instantiate()
		var player: AnimationPlayer = _first_player(root)
		if player != null:
			for name: String in player.get_animation_list():
				if not out.has(name):
					out[name] = player.get_animation(name)
		root.free()
	return out


## The inverse bind matrix per bone, resolved by name because Godot's glTF importer leaves
## the bind's bone index at -1 and names it instead. A bone no bind mentions gets the
## inverse of its own rest, which is what an unskinned bone's bind would have been.
func _binds(
	skin: Skin, bone_of_name: Dictionary, bones: int
) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(bones)
	for bone: int in range(bones):
		out[bone] = Transform3D.IDENTITY
	var filled: PackedByteArray = PackedByteArray()
	filled.resize(bones)
	for bind: int in range(skin.get_bind_count()):
		var bone: int = skin.get_bind_bone(bind)
		if bone < 0:
			bone = int(bone_of_name.get(skin.get_bind_name(bind), -1))
		if bone < 0 or bone >= bones:
			continue
		out[bone] = skin.get_bind_pose(bind)
		filled[bone] = 1
	return out


## Where one vertex of the rest pose ends up, through the same weighted sum the shader does.
## Used only to measure the body's height; the shader is what draws it.
func _skinned(
	at: Vector3,
	vertex: int,
	per: int,
	indices: PackedInt32Array,
	weights: PackedFloat32Array,
	poses: Array[Transform3D],
	binds: Array[Transform3D]
) -> Vector3:
	var out: Vector3 = Vector3.ZERO
	var total: float = 0.0
	for influence: int in range(per):
		var slot: int = vertex * per + influence
		if slot >= weights.size():
			break
		var weight: float = weights[slot]
		if weight <= 0.0:
			continue
		var bone: int = indices[slot]
		if bone < 0 or bone >= poses.size():
			continue
		out += (poses[bone] * binds[bone] * at) * weight
		total += weight
	if total <= 0.0:
		return at
	return out / total


## The skinning matrices as a float texture: three texels a bone across, one row a frame
## down, holding the three rows of each 3x4 affine.
##
## `FORMAT_RGBAF` and built in memory, so no importer is involved — the trap `content/`
## and `assets_licensed/` both carry a `.gdignore` for. An eight-bit texture would have
## quantised a two-metre character to eight millimetres, which is visible as a shimmer on a
## held pose.
func _texture(rows: Array[Transform3D], bones: int, frames: int) -> ImageTexture:
	var image: Image = Image.create(bones * TEXELS_PER_BONE, frames, false, Image.FORMAT_RGBAF)
	for frame: int in range(frames):
		for bone: int in range(bones):
			var matrix: Transform3D = rows[frame * bones + bone]
			var basis: Basis = matrix.basis
			var origin: Vector3 = matrix.origin
			for row: int in range(3):
				image.set_pixel(
					bone * TEXELS_PER_BONE + row,
					frame,
					Color(
						basis.x[row], basis.y[row], basis.z[row], origin[row]
					)
				)
	return ImageTexture.create_from_image(image)


## Every surface of every mesh under the skeleton, as one `ArrayMesh` with a surface per
## source material — `world_view.gd`'s `_flatten` for a character, and for the same reason:
## nine `MeshInstance3D`s are nine nodes and a shape a `MultiMesh` cannot take at all.
func _flatten(
	surfaces: Array, rest_global: Array[Transform3D], binds: Array[Transform3D]
) -> ArrayMesh:
	var by_material: Dictionary = {}
	var order: Array = []
	for entry: Array in surfaces:
		var mesh: ArrayMesh = entry[0]
		var surface: int = entry[1]
		var material: Material = mesh.surface_get_material(surface)
		var key: String = "" if material == null else material.resource_name
		if not by_material.has(key):
			by_material[key] = []
			order.append(key)
		by_material[key].append(entry)

	var out: ArrayMesh = ArrayMesh.new()
	for key: String in order:
		var merged: Array = _merge(by_material[key])
		if merged.is_empty():
			continue
		out.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES,
			merged,
			[],
			{},
			(
				Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
				| Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
			)
		)
		var source: Material = (by_material[key][0][0] as ArrayMesh).surface_get_material(
			by_material[key][0][1]
		)
		out.surface_set_name(out.get_surface_count() - 1, key)
		out.surface_set_material(out.get_surface_count() - 1, source)
	return out


## Several surfaces sharing a material, concatenated into one set of surface arrays with the
## bone indices and weights moved into `CUSTOM0` and `CUSTOM1`.
##
## **`ARRAY_BONES` is dropped**, deliberately and not as an oversight: a surface that still
## declared bones would be a mesh Godot tries to skin through a `Skeleton3D` the `MultiMesh`
## does not have. The shader is what skins this now, and the only way it can see an influence
## is as an ordinary vertex attribute.
func _merge(entries: Array) -> Array:
	var points: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var slots: PackedFloat32Array = PackedFloat32Array()
	var loads: PackedFloat32Array = PackedFloat32Array()
	var indices: PackedInt32Array = PackedInt32Array()

	for entry: Array in entries:
		var arrays: Array = (entry[0] as ArrayMesh).surface_get_arrays(entry[1])
		var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if source.is_empty():
			continue
		var base: int = points.size()
		points.append_array(source)
		var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for vertex: int in range(source.size()):
			normals.append(
				source_normals[vertex] if vertex < source_normals.size() else Vector3.UP
			)
		var source_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for vertex: int in range(source.size()):
			uvs.append(source_uvs[vertex] if vertex < source_uvs.size() else Vector2.ZERO)

		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per: int = INFLUENCES
		if bones.size() / maxi(source.size(), 1) == 8:
			per = 8
		for vertex: int in range(source.size()):
			_influences(vertex, per, bones, weights, slots, loads)

		var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if source_indices.is_empty():
			for vertex: int in range(source.size()):
				indices.append(base + vertex)
		else:
			for slot: int in range(source_indices.size()):
				indices.append(base + source_indices[slot])

	if points.is_empty():
		return []
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = points
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_TEX_UV] = uvs
	out[Mesh.ARRAY_CUSTOM0] = slots
	out[Mesh.ARRAY_CUSTOM1] = loads
	out[Mesh.ARRAY_INDEX] = indices
	return out


## One vertex's four strongest influences, renormalised so they sum to one.
##
## A surface with eight influences a vertex keeps the four heaviest, because `CUSTOM0` is
## four floats and a fifth would need a third attribute for a case the committed art does
## not contain. Renormalising is what stops that dropping shrink a vertex toward the origin,
## which reads as a character collapsing into its own feet.
func _influences(
	vertex: int,
	per: int,
	bones: PackedInt32Array,
	weights: PackedFloat32Array,
	slots: PackedFloat32Array,
	loads: PackedFloat32Array
) -> void:
	var picked: Array = []
	for influence: int in range(per):
		var slot: int = vertex * per + influence
		if slot >= weights.size():
			break
		picked.append([weights[slot], bones[slot]])
	picked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var total: float = 0.0
	for influence: int in range(mini(INFLUENCES, picked.size())):
		total += picked[influence][0]
	for influence: int in range(INFLUENCES):
		if influence < picked.size() and total > 0.0:
			slots.append(float(picked[influence][1]))
			loads.append(picked[influence][0] / total)
		else:
			slots.append(0.0)
			loads.append(1.0 if influence == 0 and total <= 0.0 else 0.0)


## The weak-point marker a body's `.glb` declares, or `Vector3.ZERO`.
##
## A marker node carrying no mesh, named `Vent`, which falls out of `_flatten` by itself
## exactly as a Machine's `Port_*` markers do. Absence is an ordinary state: two of the
## three kinds have no weak point and say so by not exporting one.
func _vent_offset(root: Node, normalise: Transform3D) -> Vector3:
	var marker: Node3D = _named(root, VENT_MARKER)
	if marker == null:
		return Vector3.ZERO
	return normalise * marker.position


func _named(node: Node, wanted: String) -> Node3D:
	if node.name == wanted and node is Node3D:
		return node
	for child: Node in node.get_children():
		var found: Node3D = _named(child, wanted)
		if found != null:
			return found
	return null


func _first_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var found: Skeleton3D = _first_skeleton(child)
		if found != null:
			return found
	return null


func _first_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child: Node in node.get_children():
		var found: AnimationPlayer = _first_player(child)
		if found != null:
			return found
	return null
