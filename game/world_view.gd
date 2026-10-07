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
## The camera is part of that. It goes where `query_player_camera_*` says it goes, every
## frame — on foot, mid-lift and in Survey View alike. There is no camera controller and
## no tween: the lift a player feels is the Simulation easing a tick counter, which is
## what lets its height and duration be tuned in `content/tuning.toml` while the game is
## running.
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

## Which player this view is looking through. One for now; co-op makes it the local id.
const VIEWED_PLAYER: int = 0

## Where the Nest's mesh lives. Generated from the `nest` row of
## `content/machine_bodies.csv` by `tools/assets/generate_machines.sh`, like every other
## body, even though the Nest is not a Machine.
const NEST_MESH: String = "res://assets/machines/nest.glb"

## How many cells the Telegraph's gauge is drawn with. A rising bar of text, because there
## is no audio yet and a countdown alone does not read as a klaxon.
const TELEGRAPH_GAUGE_CELLS: int = 20

## How tall the Nest reads when its mesh cannot be loaded — headless, or before the asset
## pipeline has run. The placeholder is a box like a Machine's, only taller, because the
## thing the Run is about should be the thing on the skyline.
const NEST_HEIGHT_METRES: float = 6.0

## A Breach is drawn as a dark slab flush with the ground: a hole, not a building. Flat
## enough that the Crawlers coming out of it are what the eye catches.
const BREACH_HEIGHT_METRES: float = 0.2

## How big a Crawler is, in metres. Smaller than a 2 m tile, so a swarm packed into a
## chokepoint still reads as a number of individuals.
const ENEMY_SIZE_METRES: float = 0.9

## The Ammunition gauge floating over every Turret: how wide a full magazine reads, how
## thick the bar is, and how far above the Turret's roof it hangs.
##
## **A Turret's remaining Ammunition has to be readable from a distance** — that is an
## acceptance criterion of its own, and the reason is triage: mid-Wave a player is looking
## at six Machines at once from across the Factory and needs to know which one is about to
## stop shooting, which is not a question a HUD line answers in time. So it is drawn in the
## world, over the Machine it belongs to, as a bar wide enough to read at thirty metres.
##
## Two meshes, not one: a dark backing at full width and a coloured fill scaled to the
## fraction held. One mesh would make an empty magazine indistinguishable from a Turret with
## no gauge at all, which is the exact state a player most needs to see.
const AMMUNITION_GAUGE_WIDTH_METRES: float = 2.6
const AMMUNITION_GAUGE_HEIGHT_METRES: float = 0.42
const AMMUNITION_GAUGE_DEPTH_METRES: float = 0.18
const AMMUNITION_GAUGE_LIFT_METRES: float = 1.1

## The gauge's colours. Green with rounds to spare, amber below half, and the *backing* goes
## red when the magazine is empty — so a dry Turret reads as a red bar rather than as an
## absence, and absence of a bar means there is no Turret there.
const AMMUNITION_FULL: Color = Color(0.36, 0.82, 0.38)
const AMMUNITION_LOW: Color = Color(0.95, 0.74, 0.16)
const AMMUNITION_BACKING: Color = Color(0.09, 0.08, 0.08)
const AMMUNITION_DRY: Color = Color(0.88, 0.17, 0.14)

## Below this fraction of a full magazine the gauge goes amber. Half, because a Turret's
## input buffer is `machine.input_buffer_crafts` crafts deep and half of that is the point
## at which a player still has time to go and look at the Belt.
const AMMUNITION_LOW_FRACTION: float = 0.5

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

## Every Enemy on the Map, as instances of one mesh.
##
## **One MultiMesh, never a node per Enemy.** ADR 0001 keeps Godot a renderer, and
## DESIGN.md's ~100-Enemy target rests on exactly this: idiomatic engine agents cap out
## around 150-250 before frame times collapse, where instanced array entries reach
## thousands. Milestone 1 draws twenty Crawlers through this path so that the Chaff tier
## needs no new drawing code at all — only more array entries.
var _enemy_meshes: MultiMeshInstance3D = null

## The instance transforms handed to the Enemy MultiMesh, in the same flat twelve-floats
## layout the Items use. Rebuilt from `query_enemy_*` every frame and uploaded in one
## assignment; nothing ever reads a position back out of it to make a decision.
var _enemy_transforms: PackedFloat32Array = PackedFloat32Array()

## The Nest, and a slab per Breach. One node each and not a pool, because there is one
## Nest and the Breaches are fixed geography.
var _nest_mesh: Node3D = null
var _breach_meshes: Array[MeshInstance3D] = []

## The Ammunition gauge over every Turret: a dark backing bar and the coloured fill in front
## of it, one pair per Turret. Pools rather than children of a Machine node, because a
## Machine is not a node here either — it is a box this view rebuilds from the queries.
var _turret_gauge_backings: Array[MeshInstance3D] = []
var _turret_gauge_fills: Array[MeshInstance3D] = []

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

## The hologram the Build Gun projects. One box, moved and recoloured every frame from
## the aim and the refusal the Simulation reports — never from a remembered placement.
var _hologram: MeshInstance3D = null

## The scenery: a lit sky and a ground plane with the 2 m grid on it. Not a mirror of
## anything, and the reason scale reads at all — a 1.8 m eye height against 2 m tiles
## means nothing without a surface to see the tiles on.
var _ground: MeshInstance3D = null
var _sun: DirectionalLight3D = null
var _environment: WorldEnvironment = null

var _hud: Label = null
var _hud_layer: CanvasLayer = null
var _camera: Camera3D = null


## Hologram colours. Green where a Machine would land, red where it would be refused —
## and the HUD says *why* in words, because a red box only says "no".
const HOLOGRAM_ALLOWED: Color = Color(0.35, 0.85, 0.45, 0.45)
const HOLOGRAM_REFUSED: Color = Color(0.9, 0.25, 0.2, 0.45)

## How far the ground plane extends, in tiles from the origin. The Map's own extent, so
## a player cannot walk off the edge of what they can see.
const GROUND_HALF_EXTENT_TILES: int = 64

## How long each arm of the crosshair is, in pixels. Small: it marks where the Build Gun
## points without becoming a thing a player looks at instead of the Factory.
const CROSSHAIR_ARM_PIXELS: float = 13.0


## Redraws everything from the Simulation's queries. Called once a frame; cheap
## enough at Milestone 1 scale that it rebuilds rather than diffs, and the shape it
## rebuilds from is the query output, so a divergence between what is simulated and
## what is drawn cannot survive a frame.
func sync(sim: Simulation) -> void:
	if sim == null:
		return

	_sync_scenery(sim)
	_sync_nodes(sim)
	_sync_nest(sim)
	_sync_breaches(sim)
	_sync_machines(sim)
	_sync_turret_gauges(sim)
	_sync_enemies(sim)
	_sync_belts(sim)
	_sync_items(sim)
	_sync_hologram(sim)
	_sync_hud(sim)
	_place_camera(sim)


## How many placeholders are on screen — Nodes plus Machines.
func placeholder_count() -> int:
	return _node_meshes.size() + _machine_meshes.size()


## How many tiles of Belt are on screen.
func belt_placeholder_count() -> int:
	return _belt_meshes.size()


## Where the Nest is standing, in metres. For the smoke test.
func nest_position() -> Vector3:
	if _nest_mesh == null:
		return Vector3.ZERO
	return _nest_mesh.position


## How many Breaches are marked on screen.
func breach_marker_count() -> int:
	return _breach_meshes.size()


## How many Enemies are on screen. Instances of one mesh, so this is a count of
## transforms rather than a count of nodes — there is one node for the whole swarm.
func enemy_instance_count() -> int:
	@warning_ignore("integer_division")
	return _enemy_transforms.size() / FLOATS_PER_INSTANCE


## Where an Enemy instance is standing, in metres. For the smoke test.
func enemy_instance_position(instance: int) -> Vector3:
	if instance < 0 or instance >= enemy_instance_count():
		return Vector3.ZERO
	var base: int = instance * FLOATS_PER_INSTANCE
	return Vector3(
		_enemy_transforms[base + 3], _enemy_transforms[base + 7], _enemy_transforms[base + 11]
	)


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


## How many Ammunition gauges are on screen. One per Turret and none for anything else.
func turret_gauge_count() -> int:
	return _turret_gauge_fills.size()


## How wide a Turret's Ammunition gauge is drawn, in metres. `AMMUNITION_GAUGE_WIDTH_METRES`
## for a full magazine, proportionally less as it empties, and effectively nothing when dry.
func turret_gauge_width_metres(slot: int) -> float:
	if slot < 0 or slot >= _turret_gauge_fills.size():
		return 0.0
	if not _turret_gauge_fills[slot].visible:
		return 0.0
	return (_turret_gauge_fills[slot].mesh as BoxMesh).size.x


## What colour a Turret's gauge is reading. The backing, because that is the half that turns
## red on a dry Turret and is therefore the half that answers "which one has stopped".
func turret_gauge_backing_colour(slot: int) -> Color:
	if slot < 0 or slot >= _turret_gauge_backings.size():
		return Color(0.0, 0.0, 0.0, 0.0)
	return (_turret_gauge_backings[slot].material_override as StandardMaterial3D).albedo_color


## Where a Turret's gauge hangs, in metres. For the smoke test, and so a reviewer can check
## it is over the Turret rather than over the Factory's centre of mass.
func turret_gauge_position(slot: int) -> Vector3:
	if slot < 0 or slot >= _turret_gauge_backings.size():
		return Vector3.ZERO
	return _turret_gauge_backings[slot].position


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

		# The footprint comes from content/machines.csv, through the Simulation, and
		# *turned* — `query_machine_footprint` reports the ground the Machine actually
		# covers, so a rotated Machine is drawn over its own tiles. The renderer does not
		# get its own copy of those numbers; #19 generates the real meshes against the
		# same file, and two sources would drift apart on the first balance change.
		var footprint: Vector2i = sim.query_machine_footprint(index)
		var box: BoxMesh = _machine_meshes[index].mesh
		box.size = Vector3(
			float(footprint.x) * tile_size, MACHINE_HEIGHT_METRES, float(footprint.y) * tile_size
		)

		var tile: Vector3i = sim.query_machine_tile(index)
		var near: FixedVec2 = sim.query_tile_centre_metres(tile)
		var far: FixedVec2 = sim.query_tile_centre_metres(
			Vector3i(tile.x + footprint.x - 1, tile.y, tile.z + footprint.y - 1)
		)
		_machine_meshes[index].position = Vector3(
			(Fixed.to_float(near.x) + Fixed.to_float(far.x)) * 0.5,
			Fixed.to_float(sim.query_layer_height_metres(tile.y)) + MACHINE_HEIGHT_METRES * 0.5,
			(Fixed.to_float(near.z) + Fixed.to_float(far.z)) * 0.5
		)


## An Ammunition gauge over every Turret, and over nothing else.
##
## The one thing in this view that exists for *triage* rather than for depiction: a player
## mid-Wave needs to know which Turret is about to stop firing, and they are thirty metres
## away looking at the whole Factory. So the number is drawn where the Turret is, as a bar
## whose length is the fraction of a full magazine and whose colour says how worried to be.
##
## Both numbers come out of the Simulation on the frame they are drawn, like everything else
## here. There is no remembered magazine and no interpolation: a Turret that fired this tick
## has one fewer round and the bar is one round shorter.
func _sync_turret_gauges(sim: Simulation) -> void:
	var turrets: PackedInt64Array = PackedInt64Array()
	for index: int in range(sim.query_machine_count()):
		if sim.query_machine_is_turret(index):
			turrets.append(index)

	_resize_pool(
		_turret_gauge_backings,
		turrets.size(),
		AMMUNITION_GAUGE_WIDTH_METRES,
		AMMUNITION_GAUGE_HEIGHT_METRES,
		AMMUNITION_BACKING
	)
	_resize_pool(
		_turret_gauge_fills,
		turrets.size(),
		AMMUNITION_GAUGE_WIDTH_METRES,
		AMMUNITION_GAUGE_HEIGHT_METRES,
		AMMUNITION_FULL
	)

	for slot: int in range(turrets.size()):
		var index: int = turrets[slot]
		var held: int = sim.query_turret_ammunition(index)
		var capacity: int = maxi(sim.query_turret_ammunition_capacity(index), 1)
		var fraction: float = clampf(float(held) / float(capacity), 0.0, 1.0)
		var above: Vector3 = (
			_machine_centre(sim, index)
			+ Vector3(0.0, MACHINE_HEIGHT_METRES + AMMUNITION_GAUGE_LIFT_METRES, 0.0)
		)

		var backing: BoxMesh = _turret_gauge_backings[slot].mesh
		backing.size = Vector3(
			AMMUNITION_GAUGE_WIDTH_METRES,
			AMMUNITION_GAUGE_HEIGHT_METRES,
			AMMUNITION_GAUGE_DEPTH_METRES
		)
		_turret_gauge_backings[slot].position = above
		_paint_gauge(
			_turret_gauge_backings[slot], AMMUNITION_DRY if held == 0 else AMMUNITION_BACKING
		)

		# The fill grows from the left, so an emptying magazine reads as a bar retreating
		# rather than as a bar shrinking towards its middle — the same direction every gauge
		# a player has ever read empties in.
		var width: float = AMMUNITION_GAUGE_WIDTH_METRES * fraction
		var fill: BoxMesh = _turret_gauge_fills[slot].mesh
		fill.size = Vector3(
			maxf(width, 0.001),
			AMMUNITION_GAUGE_HEIGHT_METRES,
			AMMUNITION_GAUGE_DEPTH_METRES * 1.4
		)
		_turret_gauge_fills[slot].position = above + Vector3(
			(width - AMMUNITION_GAUGE_WIDTH_METRES) * 0.5, 0.0, 0.0
		)
		_turret_gauge_fills[slot].visible = held > 0
		_paint_gauge(
			_turret_gauge_fills[slot],
			AMMUNITION_LOW if fraction < AMMUNITION_LOW_FRACTION else AMMUNITION_FULL
		)


## Colours a gauge bar, unshaded so it reads the same in the Factory's shadow as it does in
## the sun. A gauge that a directional light could darken is a gauge a player misreads at
## the worst moment.
func _paint_gauge(bar: MeshInstance3D, colour: Color) -> void:
	var skin: StandardMaterial3D = bar.material_override
	skin.albedo_color = colour
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


## The middle of a Machine's footprint at ground level, in metres. The same three queries
## `_sync_machines` uses to place the box, so a gauge cannot end up over a different Machine.
func _machine_centre(sim: Simulation, index: int) -> Vector3:
	var footprint: Vector2i = sim.query_machine_footprint(index)
	var tile: Vector3i = sim.query_machine_tile(index)
	var near: FixedVec2 = sim.query_tile_centre_metres(tile)
	var far: FixedVec2 = sim.query_tile_centre_metres(
		Vector3i(tile.x + footprint.x - 1, tile.y, tile.z + footprint.y - 1)
	)
	return Vector3(
		(Fixed.to_float(near.x) + Fixed.to_float(far.x)) * 0.5,
		Fixed.to_float(sim.query_layer_height_metres(tile.y)),
		(Fixed.to_float(near.z) + Fixed.to_float(far.z)) * 0.5
	)


## The Nest: one mesh, standing on the middle of its footprint.
##
## Built once, because the Nest does not move. Its real mesh is loaded when the asset
## pipeline has produced one and a placeholder box stands in otherwise, so the Simulation
## and the tests do not depend on an import having run.
func _sync_nest(sim: Simulation) -> void:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	var footprint: Vector2i = sim.query_nest_footprint()

	if _nest_mesh == null:
		_nest_mesh = _nest_body(footprint, tile_size)
		add_child(_nest_mesh)

	var tile: Vector3i = sim.query_nest_tile()
	var near: FixedVec2 = sim.query_tile_centre_metres(tile)
	var far: FixedVec2 = sim.query_tile_centre_metres(
		Vector3i(tile.x + footprint.x - 1, tile.y, tile.z + footprint.y - 1)
	)
	_nest_mesh.position = Vector3(
		(Fixed.to_float(near.x) + Fixed.to_float(far.x)) * 0.5,
		Fixed.to_float(sim.query_layer_height_metres(tile.y)),
		(Fixed.to_float(near.z) + Fixed.to_float(far.z)) * 0.5
	)


## The Nest's body: its generated mesh if there is one, and a tall box if there is not.
func _nest_body(footprint: Vector2i, tile_size: float) -> Node3D:
	if ResourceLoader.exists(NEST_MESH):
		var scene: PackedScene = load(NEST_MESH)
		if scene != null:
			var body: Node3D = scene.instantiate()
			# The mesh is modelled standing on the ground, like every generated body, so it
			# is parented at the footprint's floor rather than at its centre.
			return body

	var placeholder: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(
		float(footprint.x) * tile_size, NEST_HEIGHT_METRES, float(footprint.y) * tile_size
	)
	placeholder.mesh = box
	placeholder.position = Vector3(0.0, NEST_HEIGHT_METRES * 0.5, 0.0)
	var skin: StandardMaterial3D = StandardMaterial3D.new()
	skin.albedo_color = Color(0.46, 0.40, 0.30)
	placeholder.material_override = skin
	var holder: Node3D = Node3D.new()
	holder.add_child(placeholder)
	return holder


## A dark slab on every Breach. Fixed geography, so this is a pool that fills once — but a
## pool rather than one node, because deep mining opens more Breaches.
func _sync_breaches(sim: Simulation) -> void:
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	_resize_pool(
		_breach_meshes,
		sim.query_breach_count(),
		tile_size,
		BREACH_HEIGHT_METRES,
		Color(0.12, 0.08, 0.10)
	)
	for index: int in range(sim.query_breach_count()):
		var tile: Vector3i = sim.query_breach_tile(index)
		var centre: FixedVec2 = sim.query_tile_centre_metres(tile)
		_breach_meshes[index].position = Vector3(
			Fixed.to_float(centre.x),
			Fixed.to_float(sim.query_layer_height_metres(tile.y)) + BREACH_HEIGHT_METRES * 0.5,
			Fixed.to_float(centre.z)
		)


## Every Enemy on the Map, at the position the Simulation says it is at.
##
## One MultiMesh for the whole swarm and **no node per Enemy** (ADR 0001). That is the
## decision the ~100-Enemy target depends on, and it is made here once so that the Chaff
## tier arriving later is more array entries rather than new drawing code.
##
## No interpolation and no remembered previous frame, for the reason the Items have none:
## the Simulation moves a Crawler a fixed amount every tick and this draws it there.
func _sync_enemies(sim: Simulation) -> void:
	if _enemy_meshes == null:
		_enemy_meshes = MultiMeshInstance3D.new()
		var instanced: MultiMesh = MultiMesh.new()
		instanced.transform_format = MultiMesh.TRANSFORM_3D
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(ENEMY_SIZE_METRES, ENEMY_SIZE_METRES, ENEMY_SIZE_METRES)
		instanced.mesh = box
		_enemy_meshes.multimesh = instanced
		var skin: StandardMaterial3D = StandardMaterial3D.new()
		skin.albedo_color = Color(0.58, 0.14, 0.12)
		_enemy_meshes.material_override = skin
		add_child(_enemy_meshes)

	var total: int = sim.query_enemy_count()
	_enemy_transforms.resize(total * FLOATS_PER_INSTANCE)
	for index: int in range(total):
		var where: FixedVec2 = sim.query_enemy_position_metres(index)
		var base: int = index * FLOATS_PER_INSTANCE
		_enemy_transforms[base + 0] = 1.0
		_enemy_transforms[base + 1] = 0.0
		_enemy_transforms[base + 2] = 0.0
		_enemy_transforms[base + 3] = Fixed.to_float(where.x)
		_enemy_transforms[base + 4] = 0.0
		_enemy_transforms[base + 5] = 1.0
		_enemy_transforms[base + 6] = 0.0
		_enemy_transforms[base + 7] = ENEMY_SIZE_METRES * 0.5
		_enemy_transforms[base + 8] = 0.0
		_enemy_transforms[base + 9] = 0.0
		_enemy_transforms[base + 10] = 1.0
		_enemy_transforms[base + 11] = Fixed.to_float(where.z)

	_enemy_meshes.multimesh.instance_count = total
	if total > 0:
		_enemy_meshes.multimesh.buffer = _enemy_transforms


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
		_hud_layer.add_child(_crosshair())
		add_child(_hud_layer)

	var lines: PackedStringArray = PackedStringArray()
	# The Run-over condition first, and in capitals, because it is the only line on the
	# HUD that means the game has stopped — and it names the Wave reached, which is the
	# whole of the score at this milestone.
	if sim.query_run_is_over():
		lines.append("THE NEST HAS FALLEN — reached wave %d" % sim.query_wave_number())
	lines.append_array(_telegraph_lines(sim))
	lines.append("tick %d" % sim.query_tick())
	# What the Run is about, the pressure on it, and what is on the Map. Read out of the
	# queries every frame, so none of it can be stale.
	lines.append(
		"nest %d/%d — wave %d — next in %ds — crawlers %d"
		% [
			sim.query_nest_health(),
			sim.query_nest_max_health(),
			sim.query_wave_number(),
			sim.query_ticks_until_next_wave() / Simulation.TICKS_PER_SECOND,
			sim.query_enemy_count(),
		]
	)
	lines.append_array(_heat_lines(sim))
	lines.append_array(_build_gun_lines(sim))

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
		# The Heat this Machine has made and the rate it is making it at, on the Machine's
		# own line. That is the whole of "Heat's contributors are visible": a player reads
		# the cause next to the thing that caused it, rather than inferring it from a total.
		var line: String = (
			"%s — %s — in %d, out %d — heat %d (+%d/min)"
			% [
				sim.query_machine_id(index),
				state,
				sim.query_machine_input_total(index),
				sim.query_machine_output_total(index),
				sim.query_machine_heat_units(index),
				sim.query_machine_heat_per_minute(index),
			]
		)
		# A Turret's magazine, in words as well as on the gauge over its roof. The gauge is
		# what a player reads mid-fight; this is what they read afterwards to work out which
		# Belt could not keep up, and it says DRY in capitals because an empty Turret is the
		# one Machine state that costs the Run.
		if sim.query_machine_is_turret(index):
			var held: int = sim.query_turret_ammunition(index)
			line += " — ammo %d/%d" % [held, sim.query_turret_ammunition_capacity(index)]
			line += " — DRY" if held == 0 else " — %d shots" % sim.query_turret_shots_remaining(index)
		lines.append(line)

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


## The Telegraph, as the loudest thing on the HUD.
##
## There is no audio yet, so the klaxon GLOSSARY.md describes is this line and the countdown
## in it. It is first and in capitals for the same reason the Run-over line is: it is the one
## thing on screen that means *stop laying Belt and go and stand somewhere useful*.
##
## The gauge is drawn from `query_telegraph_ticks_served` against `query_telegraph_ticks`,
## which is a fraction of a warning that has already been served rather than a guess at how
## long is left — so it fills at the same rate however the Wave was summoned.
func _telegraph_lines(sim: Simulation) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if not sim.query_wave_is_telegraphed():
		return lines

	var served: int = sim.query_telegraph_ticks_served()
	var total: int = maxi(sim.query_telegraph_ticks(), 1)
	var filled: int = mini(served * TELEGRAPH_GAUGE_CELLS / total, TELEGRAPH_GAUGE_CELLS)
	var gauge: String = (
		"#".repeat(filled) + ".".repeat(TELEGRAPH_GAUGE_CELLS - filled)
	)
	var called: String = " — CALLED" if sim.query_wave_was_called_early() else ""
	lines.append(
		"!! WAVE %d INCOMING IN %ds [%s]%s"
		% [
			sim.query_wave_number() + 1,
			(sim.query_ticks_until_next_wave() + Simulation.TICKS_PER_SECOND - 1)
			/ Simulation.TICKS_PER_SECOND,
			gauge,
			called,
		]
	)
	return lines


## Heat, what the Factory is doing to it, and whether the lever is available.
##
## Three numbers rather than one, because one would not let a player make a decision: the
## Heat they are carrying, the rate they are adding to it against the rate the Nest hides,
## and how much sooner that is bringing the next Wave. The last of those is what turns Heat
## from a score into a warning.
func _heat_lines(sim: Simulation) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var interval: int = sim.query_wave_interval_ticks()
	lines.append(
		"heat %d — +%d/min, -%d/min — wave gap %ds"
		% [
			sim.query_heat(),
			sim.query_heat_per_minute(),
			sim.query_heat_decay_per_minute(),
			interval / Simulation.TICKS_PER_SECOND,
		]
	)
	lines.append("call wave (%s) — %s" % [
		OS.get_keycode_string(PlayerController.KEY_CALL_WAVE),
		_call_wave_text(sim.query_call_wave_early_refusal(VIEWED_PLAYER)),
	])
	return lines


## What to tell a player about the lever. The wording lives here and the rule lives in the
## Simulation, which is the right way round — the same split `BuildGun.refusal_text` makes.
func _call_wave_text(refusal: int) -> String:
	match refusal:
		Simulation.Refusal.NONE:
			return "ready"
		Simulation.Refusal.WAVE_ALREADY_COMING:
			return "a Wave is already on its way"
		Simulation.Refusal.WAVE_STILL_ARRIVING:
			return "this Wave is still coming through"
		Simulation.Refusal.NO_BREACH:
			return "nothing can reach this Map"
		Simulation.Refusal.RUN_IS_OVER:
			return "the Run is over"
		_:
			return "unavailable"


## Points the camera where the Simulation says a player's camera is.
##
## Every frame, from `query_player_camera_*`: the ground position is the player's, the
## height is eye level easing up to Survey View height, and the pitch is the player's own
## easing down to the Survey View tilt. No tween and no camera state — the transition a
## player feels is the Simulation counting ticks, which is what makes its height and
## duration hot-reloadable tuning rather than numbers compiled into a renderer.
func _place_camera(sim: Simulation) -> void:
	if _camera == null:
		_camera = Camera3D.new()
		add_child(_camera)

	var ground: FixedVec2 = sim.query_player_camera_ground_metres(VIEWED_PLAYER)
	_camera.position = Vector3(
		Fixed.to_float(ground.x),
		Fixed.to_float(sim.query_player_camera_height_metres(VIEWED_PLAYER)),
		Fixed.to_float(ground.z)
	)
	# Turns, not radians: the Simulation holds the angle in turns because radians need
	# PI and PI is a float. One multiplication by TAU is the whole conversion.
	_camera.rotation = Vector3(
		Fixed.to_float(sim.query_player_camera_pitch_turns(VIEWED_PLAYER)) * TAU,
		Fixed.to_float(sim.query_player_yaw_turns(VIEWED_PLAYER)) * TAU,
		0.0
	)


## Where the camera is standing, in metres. For the smoke test, which asserts it against
## the queries rather than against a remembered value.
func camera_position() -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	return _camera.position


## Which way the camera is pointing, in radians. For the smoke test.
func camera_rotation() -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	return _camera.rotation


## A small cross at the centre of the screen.
##
## Decoration in the sense that nothing reads it, and load-bearing in the sense that the
## Build Gun aims down the middle of the view: without a mark there, a player placing a
## Machine is guessing where the gun points.
func _crosshair() -> Control:
	var mark: Control = Control.new()
	mark.set_anchors_preset(Control.PRESET_CENTER)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for arm: Vector2 in [Vector2(CROSSHAIR_ARM_PIXELS, 1.0), Vector2(1.0, CROSSHAIR_ARM_PIXELS)]:
		var bar: ColorRect = ColorRect.new()
		bar.color = Color(0.95, 0.95, 0.92, 0.75)
		bar.size = arm
		bar.position = -arm * 0.5
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.add_child(bar)

	return mark


## What the Build Gun is holding, and why it would refuse.
##
## The refusal is in **words**, not only in a red box: "cannot build there" with no reason
## is the silent failure this ticket exists to remove. The wording lives in `BuildGun`
## because it is presentation; the rule lives in the Simulation.
func _build_gun_lines(sim: Simulation) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()

	var rotation: int = sim.query_player_build_rotation(VIEWED_PLAYER)
	var selected: String = sim.query_player_selected_machine(VIEWED_PLAYER)
	lines.append(
		"build gun: %s facing %d" % ["nothing" if selected.is_empty() else selected, rotation]
	)

	var tile: Vector3i = BuildGun.aimed_tile(sim, VIEWED_PLAYER)
	var refusal: int = sim.query_build_refusal(
		VIEWED_PLAYER, sim.query_player_selected_machine_index(VIEWED_PLAYER), tile, rotation
	)
	if refusal == Simulation.Refusal.NONE:
		lines.append("aimed at %d, %d — clear" % [tile.x, tile.z])
	else:
		lines.append("aimed at %d, %d — %s" % [tile.x, tile.z, BuildGun.refusal_text(refusal)])

	var carried: PackedStringArray = PackedStringArray()
	for item_id: String in sim.query_player_items(VIEWED_PLAYER):
		carried.append("%s %d" % [item_id, sim.query_player_item(VIEWED_PLAYER, item_id)])
	lines.append("carrying: %s" % ("nothing" if carried.is_empty() else ", ".join(carried)))

	if sim.query_player_is_surveying(VIEWED_PLAYER):
		lines.append("survey view")
	if sim.query_player_is_sprinting(VIEWED_PLAYER):
		lines.append("sprinting")

	return lines


## A lit sky and a ground plane with the 2 m grid marked on it, built once.
##
## Not decoration. A first-person controller judged on how it feels needs a surface to
## walk on and a grid to read the 2 m tiles off, or a 1.8 m eye height is a number with
## nothing to be 1.8 m against.
func _sync_scenery(sim: Simulation) -> void:
	if _ground != null:
		return

	_environment = WorldEnvironment.new()
	var world: Environment = Environment.new()
	world.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	# Dieselpunk: a low, smoky, ochre sky rather than a clear blue one (DESIGN.md).
	sky_material.sky_top_color = Color(0.22, 0.24, 0.28)
	sky_material.sky_horizon_color = Color(0.52, 0.44, 0.33)
	sky_material.ground_bottom_color = Color(0.14, 0.13, 0.12)
	sky_material.ground_horizon_color = Color(0.32, 0.28, 0.23)
	sky.sky_material = sky_material
	world.sky = sky
	# An explicit ambient colour rather than the sky's own, and a generous one. A single
	# directional light leaves every face turned away from it black, and a Machine whose
	# silhouette a player cannot read is a Machine they cannot diagnose — readability is
	# the point of the placeholders, not realism.
	world.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.ambient_light_color = Color(0.62, 0.63, 0.68)
	world.ambient_light_energy = 0.9
	_environment.environment = world
	add_child(_environment)

	_sun = DirectionalLight3D.new()
	# High and off to one side, so vertical faces catch it at different angles and a box
	# reads as a box rather than as a silhouette.
	_sun.rotation = Vector3(-0.85, -2.3, 0.0)
	_sun.light_energy = 1.4
	_sun.light_color = Color(1.0, 0.94, 0.84)
	_sun.shadow_enabled = true
	# Not fully black. A placeholder box in shadow still has to read as a box, and a
	# Factory half of which is unreadable at a glance defeats the point of Survey View.
	_sun.shadow_opacity = 0.65
	add_child(_sun)

	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	var span: float = float(GROUND_HALF_EXTENT_TILES * 2) * tile_size

	_ground = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(span, span)
	_ground.mesh = plane
	var surface: StandardMaterial3D = StandardMaterial3D.new()
	surface.albedo_texture = _grid_texture()
	# Anisotropic, because the grid runs away to the horizon and nearest-neighbour
	# filtering turns the far half of it into noise.
	surface.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# One texture repeat per tile, so what a player sees on the ground is the grid the
	# Build Gun snaps to rather than an arbitrary pattern.
	surface.uv1_scale = Vector3(span / tile_size, span / tile_size, 1.0)
	_ground.material_override = surface
	add_child(_ground)


## A one-tile ground texture: a dark face with a lighter edge, so every 2 m tile boundary
## is visible. Generated rather than committed, because a committed image would be an
## asset with a licence and this is a few pixels of information.
func _grid_texture() -> ImageTexture:
	var size: int = 16
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGB8)
	image.fill(Color(0.29, 0.27, 0.25))
	for along: int in range(size):
		image.set_pixel(along, 0, Color(0.38, 0.36, 0.33))
		image.set_pixel(0, along, Color(0.38, 0.36, 0.33))
	return ImageTexture.create_from_image(image)


## The Build Gun's hologram: a translucent box on the tile the gun is aimed at, sized to
## the footprint the selected Machine would occupy *turned by the rotation the player is
## holding*, and coloured by whether the Simulation would accept it.
##
## Everything here is a query. The aim comes from `BuildGun`, which derives it from where
## the Simulation says the camera is; the refusal comes from `query_build_refusal`, which
## is the same rule a build obeys. Nothing is remembered between frames, so there is no
## way for the hologram to promise a placement the Simulation would refuse.
func _sync_hologram(sim: Simulation) -> void:
	if _hologram == null:
		_hologram = MeshInstance3D.new()
		_hologram.mesh = BoxMesh.new()
		var fresh: StandardMaterial3D = StandardMaterial3D.new()
		fresh.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fresh.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hologram.material_override = fresh
		add_child(_hologram)

	var selected: MachineDefinition = sim.query_definitions().machine(
		sim.query_player_selected_machine(VIEWED_PLAYER)
	)
	_hologram.visible = selected != null
	if selected == null:
		return

	var rotation: int = sim.query_player_build_rotation(VIEWED_PLAYER)
	var footprint: Vector2i = WorldGrid.rotated_footprint(
		selected.footprint_x, selected.footprint_z, rotation
	)
	var tile: Vector3i = BuildGun.aimed_tile(sim, VIEWED_PLAYER)
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())

	var box: BoxMesh = _hologram.mesh
	box.size = Vector3(
		float(footprint.x) * tile_size, MACHINE_HEIGHT_METRES, float(footprint.y) * tile_size
	)

	var near: FixedVec2 = sim.query_tile_centre_metres(tile)
	var far: FixedVec2 = sim.query_tile_centre_metres(
		Vector3i(tile.x + footprint.x - 1, tile.y, tile.z + footprint.y - 1)
	)
	_hologram.position = Vector3(
		(Fixed.to_float(near.x) + Fixed.to_float(far.x)) * 0.5,
		Fixed.to_float(sim.query_layer_height_metres(tile.y)) + MACHINE_HEIGHT_METRES * 0.5,
		(Fixed.to_float(near.z) + Fixed.to_float(far.z)) * 0.5
	)

	var refusal: int = sim.query_build_refusal(
		VIEWED_PLAYER, sim.query_player_selected_machine_index(VIEWED_PLAYER), tile, rotation
	)
	var skin: StandardMaterial3D = _hologram.material_override
	skin.albedo_color = (
		HOLOGRAM_ALLOWED if refusal == Simulation.Refusal.NONE else HOLOGRAM_REFUSED
	)


## Where the hologram is standing, in metres. For the smoke test.
func hologram_position() -> Vector3:
	if _hologram == null:
		return Vector3.ZERO
	return _hologram.position


## Whether the hologram is showing a refusal. For the smoke test.
func hologram_is_refused() -> bool:
	if _hologram == null:
		return false
	var skin: StandardMaterial3D = _hologram.material_override
	return skin.albedo_color.is_equal_approx(HOLOGRAM_REFUSED)


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
